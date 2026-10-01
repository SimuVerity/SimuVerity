from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from pathlib import PureWindowsPath
from typing import Any, Mapping

from ..errors import ContractError
from ..jsonutil import load_json, write_json_exclusive
from ..runtime.process import terminate_owned_tree
from ..types import TaskDefinition
from .seal import _copy_bundle, _native_path


_MATLAB_ENTRYPOINT_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
@dataclass(frozen=True)
class ReferenceCleanReplaySetup:
    path: Path
    repository_relative_path: str
    entrypoint: str
    phase: str


def resolve_reference_clean_replay_setup(
    task: TaskDefinition,
    *,
    evaluation_subject: str,
) -> ReferenceCleanReplaySetup | None:
    """Resolve an evaluator-owned, reference-only before-load setup hook.

    Candidate and generation clean replays deliberately do not parse or
    validate this optional reference contract.  This keeps the hook outside
    every candidate-visible/executable path.
    """

    if evaluation_subject not in {"candidate", "reference"}:
        raise ContractError("evaluation_subject must be candidate or reference")
    if evaluation_subject != "reference":
        return None
    reference = task.raw.get("reference", {})
    binding = reference.get("clean_replay_setup") if isinstance(reference, Mapping) else None
    if binding is None:
        return None
    if not isinstance(binding, Mapping):
        raise ContractError("SimuVerity:ReferenceSetup:Contract: binding must be an object")
    phase = binding.get("phase")
    repository_path = binding.get("path")
    entrypoint = binding.get("entrypoint")
    if phase not in {"before_load", "after_load_before_update"}:
        raise ContractError(
            "SimuVerity:ReferenceSetup:Contract: phase must be before_load "
            "or after_load_before_update"
        )
    if (
        not isinstance(repository_path, str)
        or not repository_path.strip()
        or Path(repository_path).is_absolute()
        or PureWindowsPath(repository_path).is_absolute()
        or ":" in repository_path
        or ".." in Path(repository_path).parts
    ):
        raise ContractError(
            "SimuVerity:ReferenceSetup:PathConfinement: path must be repository-relative"
        )
    if not isinstance(entrypoint, str) or not _MATLAB_ENTRYPOINT_RE.fullmatch(entrypoint):
        raise ContractError("SimuVerity:ReferenceSetup:Contract: invalid MATLAB entrypoint")
    repository_root = task.root.parent.parent.resolve()
    path = (repository_root / Path(repository_path)).resolve()
    try:
        path.relative_to(repository_root)
        path.relative_to(task.root.resolve())
    except ValueError as exc:
        raise ContractError(
            "SimuVerity:ReferenceSetup:PathConfinement: setup must stay inside its task"
        ) from exc
    if path.suffix.lower() != ".m" or path.stem != entrypoint:
        raise ContractError(
            "SimuVerity:ReferenceSetup:Contract: path must name the declared MATLAB entrypoint"
        )
    if not path.is_file():
        raise ContractError("SimuVerity:ReferenceSetup:Missing: setup file is missing")
    scenarios_path = task.scenarios_path.resolve()
    try:
        scenarios_path.relative_to(task.root.resolve())
    except ValueError as exc:
        raise ContractError(
            "SimuVerity:ReferenceSetup:PathConfinement: official scenarios escape the task"
        ) from exc
    return ReferenceCleanReplaySetup(
        path=path,
        repository_relative_path=Path(repository_path).as_posix(),
        entrypoint=entrypoint,
        phase=phase,
    )


def _matlab_literal(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def _remove_replay_runtime(path: Path) -> None:
    def make_writable_and_retry(function, value, _error) -> None:
        os.chmod(value, stat.S_IWRITE)
        function(value)

    if path.exists():
        shutil.rmtree(_native_path(path), onerror=make_writable_and_retry)


def _copy_replay_runtime(sealed_candidate: Path, environment: Mapping[str, str]) -> tuple[Path, Path]:
    # MATLAB/Stateflow still contains MAX_PATH-limited build paths on the
    # supported Windows release.  The per-evaluation TEMP directory can be
    # deeply nested, so use Python's process temp root plus a unique short
    # directory.  Uniqueness preserves isolation without reusing any state.
    del environment
    sealed_root = sealed_candidate.parent.resolve()
    runtime_root = Path(tempfile.mkdtemp(prefix="svcr-"))
    runtime_submission = runtime_root / "submission"
    try:
        _copy_bundle(sealed_root, runtime_submission)
        for item in runtime_submission.rglob("*"):
            if item.is_file():
                item.chmod(item.stat().st_mode | stat.S_IWRITE)
        relative_candidate = sealed_candidate.resolve().relative_to(sealed_root)
        runtime_candidate = runtime_submission / relative_candidate
        if not runtime_candidate.is_file():
            raise ContractError("Clean replay runtime copy is missing the candidate model")
        return runtime_root, runtime_candidate
    except BaseException:
        _remove_replay_runtime(runtime_root)
        raise


def _stop_time(task: TaskDefinition) -> float:
    configured = task.raw.get("candidate_closure", {})
    if isinstance(configured, Mapping) and isinstance(configured.get("stop_time_s"), (int, float)):
        return float(configured["stop_time_s"])
    try:
        public = load_json(task.public_spec_path)
        simulation = public.get("simulation", {}) if isinstance(public, Mapping) else {}
        if isinstance(simulation, Mapping):
            for name in ("stop_time_s", "stop_s"):
                if isinstance(simulation.get(name), (int, float)):
                    return float(simulation[name])
        scenarios = load_json(task.scenarios_path)
        if isinstance(scenarios, Mapping):
            simulation = scenarios.get("simulation", {})
            if isinstance(simulation, Mapping):
                for name in ("stop_time_s", "stop_s"):
                    if isinstance(simulation.get(name), (int, float)):
                        return float(simulation[name])
            rows = scenarios.get("scenarios", [])
            if isinstance(rows, list) and rows and isinstance(rows[0], Mapping):
                for name in ("stop_time_s", "stop_s", "duration_s"):
                    if isinstance(rows[0].get(name), (int, float)):
                        return float(rows[0][name])
    except Exception:
        pass
    return 0.0


def verify_nominal_provider_closure(provider_root: Path) -> None:
    manifest_path = provider_root / "manifest.json"
    manifest = load_json(manifest_path)
    if not isinstance(manifest, Mapping) or manifest.get("schema") != "simuverity.public-nominal-provider-closure.v1":
        raise ContractError("Public nominal provider manifest is invalid")
    rows = manifest.get("files")
    if not isinstance(rows, list) or not rows:
        raise ContractError("Public nominal provider closure is empty")
    for row in rows:
        if not isinstance(row, Mapping):
            raise ContractError("Public nominal provider closure row is invalid")
        name = row.get("name")
        expected_size = row.get("size_bytes")
        if not isinstance(name, str) or Path(name).name != name:
            raise ContractError("Public nominal provider closure contains an unsafe row")
        path = provider_root / name
        if not path.is_file():
            raise ContractError(f"Public nominal provider file is missing: {name}")
        if expected_size is not None and (
            not isinstance(expected_size, int) or expected_size < 0 or path.stat().st_size != expected_size
        ):
            raise ContractError(f"Public nominal provider file size differs: {name}")


def run_clean_replay(
    task: TaskDefinition,
    *,
    sealed_candidate: Path,
    output_root: Path,
    environment: dict[str, str],
    simulation_timeout_seconds: int = 1800,
    matlab_executable: str | None = None,
    evaluation_subject: str = "candidate",
) -> dict[str, Any]:
    output_root.mkdir(parents=True, exist_ok=False)
    phase_path = output_root / "phase.json"
    receipt_path = output_root / "clean_replay_receipt.json"
    stdout_path = output_root / "stdout.log"
    stderr_path = output_root / "stderr.log"
    helper = Path(__file__).resolve().parents[1] / "runtime" / "matlab" / "simuverity_clean_replay.m"
    provider_root = helper.parent / "nominal_inputs"
    verify_nominal_provider_closure(provider_root)
    reference_setup = resolve_reference_clean_replay_setup(
        task, evaluation_subject=evaluation_subject
    )
    reference_setup_phase = reference_setup.phase if reference_setup is not None else ""
    public_names_path = output_root / "public_input_names.json"
    write_json_exclusive(
        public_names_path,
        {
            "schema": "simuverity.clean-replay-public-inputs.v1",
            "task_id": task.task_id,
            "public_input_names": list(task.public_input_names),
        },
    )
    original_bytes = sealed_candidate.read_bytes()
    runtime_root, runtime_candidate = _copy_replay_runtime(sealed_candidate, environment)
    runtime_original_bytes = runtime_candidate.read_bytes()
    if runtime_original_bytes != original_bytes:
        _remove_replay_runtime(runtime_root)
        raise ContractError("Clean replay runtime copy differs from the sealed candidate")

    def finish(value: dict[str, Any]) -> dict[str, Any]:
        _remove_replay_runtime(runtime_root)
        return value

    expression = (
        f"addpath({_matlab_literal(helper.parent)},'-begin');"
        f"simuverity_clean_replay({_matlab_literal(runtime_candidate)},"
        f"{_matlab_literal(task.task_id)},{_matlab_literal(public_names_path)},"
        f"{_matlab_literal(provider_root)},"
        f"{_matlab_literal(phase_path)},{_matlab_literal(receipt_path)},{_stop_time(task):.17g}"
    )
    if reference_setup is not None:
        expression += (
            f",{_matlab_literal(reference_setup.path)}"
            f",{_matlab_literal(reference_setup.entrypoint)}"
            f",{_matlab_literal(task.scenarios_path)}"
            f",{_matlab_literal(reference_setup.phase)}"
        )
    expression += ");"
    creationflags = 0
    if os.name == "nt":
        creationflags |= getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        creationflags |= getattr(subprocess, "CREATE_NO_WINDOW", 0)
    with stdout_path.open("w", encoding="utf-8", newline="\n") as stdout, stderr_path.open(
        "w", encoding="utf-8", newline="\n"
    ) as stderr:
        try:
            process = subprocess.Popen(
                [matlab_executable or os.environ.get("MATLAB_EXECUTABLE", "matlab"), "-batch", expression],
                cwd=runtime_candidate.parent,
                env=environment,
                stdout=stdout,
                stderr=stderr,
                text=True,
                encoding="utf-8",
                errors="replace",
                creationflags=creationflags,
            )
        except OSError as exc:
            return finish({
                "schema": "simuverity.candidate-clean-replay-process.v1",
                "status": "GENERATION_INFRA_ERROR",
                "failure_reason": f"MATLAB_PROCESS_START_FAILED:{exc}",
                "simulation_timeout_triggered": False,
                "reference_clean_replay_setup_phase": reference_setup_phase,
            })
        simulate_started: float | None = None
        timed_out = False
        try:
            while process.poll() is None:
                if phase_path.is_file():
                    try:
                        phase = load_json(phase_path).get("phase")
                    except Exception:
                        phase = None
                    if phase == "simulate" and simulate_started is None:
                        simulate_started = time.monotonic()
                    elif phase != "simulate":
                        simulate_started = None
                if (
                    simulation_timeout_seconds > 0
                    and simulate_started is not None
                    and time.monotonic() - simulate_started >= simulation_timeout_seconds
                ):
                    timed_out = True
                    terminate_owned_tree(process)
                    break
                time.sleep(0.2)
        except BaseException:
            terminate_owned_tree(process)
            _remove_replay_runtime(runtime_root)
            raise
        exit_code = process.wait()
    if sealed_candidate.read_bytes() != original_bytes:
        _remove_replay_runtime(runtime_root)
        raise ContractError("Clean replay modified the sealed candidate")
    if runtime_candidate.read_bytes() != runtime_original_bytes:
        _remove_replay_runtime(runtime_root)
        raise ContractError("Clean replay modified its evaluator-owned candidate copy")
    if timed_out:
        return finish({
            "schema": "simuverity.candidate-clean-replay-process.v1",
            "status": "CANDIDATE_TIMEOUT",
            "failure_reason": "NOMINAL_SIMULATION_EXCEEDED_TIMEOUT",
            "simulation_timeout_triggered": True,
            "matlab_exit_code": exit_code,
            "reference_clean_replay_setup_phase": reference_setup_phase,
        })
    if not receipt_path.is_file():
        return finish({
            "schema": "simuverity.candidate-clean-replay-process.v1",
            "status": "GENERATION_INFRA_ERROR",
            "failure_reason": f"CLEAN_REPLAY_RECEIPT_MISSING:exit={exit_code}",
            "simulation_timeout_triggered": False,
            "matlab_exit_code": exit_code,
            "reference_clean_replay_setup_phase": reference_setup_phase,
        })
    receipt = load_json(receipt_path)
    receipt_passed = (
        exit_code == 0
        and isinstance(receipt, Mapping)
        and receipt.get("status") == "CANDIDATE_CLOSURE_PASSED"
        and all(
            receipt.get(name) is True
            for name in (
                "load_passed",
                "update_passed",
                "compile_passed",
                "nominal_simulation_passed",
            )
        )
    )
    if reference_setup is not None and receipt_passed and (
        not isinstance(receipt, Mapping)
        or receipt.get("reference_setup_used") is not True
        or receipt.get("reference_setup_entrypoint") != reference_setup.entrypoint
        or receipt.get("reference_setup_phase") != reference_setup.phase
    ):
        return finish({
            **(dict(receipt) if isinstance(receipt, Mapping) else {}),
            "status": "GENERATION_INFRA_ERROR",
            "failure_reason": "REFERENCE_SETUP_RECEIPT_IDENTITY_MISMATCH",
            "matlab_exit_code": exit_code,
            "simulation_timeout_triggered": False,
            "reference_clean_replay_setup_phase": reference_setup_phase,
        })
    if receipt_passed:
        return finish({
            **receipt,
            "matlab_exit_code": exit_code,
            "simulation_timeout_triggered": False,
            "nominal_provider_validated": True,
            "reference_clean_replay_setup_phase": reference_setup_phase,
        })
    identifier = str(receipt.get("error_identifier", "")) if isinstance(receipt, Mapping) else ""
    error_message = str(receipt.get("error_message", "")) if isinstance(receipt, Mapping) else ""
    failed_phase = str(receipt.get("failed_phase", "")) if isinstance(receipt, Mapping) else ""
    reference_setup_failure = identifier.startswith("SimuVerity:ReferenceSetup:")
    provider_failure = identifier.startswith(
        (
            "SimuVerity:CleanReplay:PublicInput",
            "SimuVerity:CleanReplay:NominalProvider",
            "SimuVerity:CandidateClosure:",
        )
    )
    helper_api_failure = failed_phase == "compile" and (
        "Simulink.BlockDiagram.compile" in error_message
        or (identifier == "MATLAB:UndefinedFunction" and "compile" in error_message.lower())
    )
    receipt_io_failure = identifier.startswith("SimuVerity:CleanReplay:Receipt") or identifier in {
        "MATLAB:MOVEFILE:OSError",
        "MATLAB:DELETE:Permission",
    }
    return finish({
        **(dict(receipt) if isinstance(receipt, Mapping) else {}),
        "status": (
            "GENERATION_INFRA_ERROR"
            if reference_setup_failure or provider_failure or helper_api_failure or receipt_io_failure
            else "CANDIDATE_CLOSURE_FAILED"
        ),
        "failure_reason": (
            f"REFERENCE_SETUP_FAILED:{identifier}"
            if reference_setup_failure
            else f"PUBLIC_NOMINAL_PROVIDER_FAILED:{identifier}"
            if provider_failure
            else f"CLEAN_REPLAY_HELPER_API_FAILED:{identifier}"
            if helper_api_failure
            else f"CLEAN_REPLAY_RECEIPT_IO_FAILED:{identifier}"
            if receipt_io_failure
            else f"CANDIDATE_CLEAN_REPLAY_FAILED:{identifier}"
        ),
        "matlab_exit_code": exit_code,
        "simulation_timeout_triggered": False,
        "reference_clean_replay_setup_phase": reference_setup_phase,
    })
