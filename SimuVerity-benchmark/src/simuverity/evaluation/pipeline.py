from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from ..candidate_closure import run_clean_replay, seal_submission
from ..candidate_closure.seal import (
    _copy_bundle,
    _is_reparse,
    _make_bundle_writable,
    bundles_match,
)
from ..errors import ContractError
from ..jsonutil import load_json, write_json_exclusive
from ..runtime.windows.isolation import (
    MatlabScratchLayout,
    RuntimeLayout,
    build_isolated_environment,
    cleanup_evaluation_matlab_scratch,
    create_evaluation_matlab_scratch,
    create_runtime_layout,
)
from ..runtime.identity import reserve_identity
from ..types import TaskDefinition
from .evidence import create_evidence_bundle, resolve_evidence_sidecars, validate_evidence_bundle
from .scoring import run_offline_scorer


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _matlab_literal(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def _copy_sealed_bundle_to_runtime(
    sealed_submission: Path, runtime_submission: Path
) -> None:
    source = sealed_submission.resolve()
    destination = runtime_submission.resolve()
    if (
        source == destination
        or destination.is_relative_to(source)
        or source.is_relative_to(destination)
    ):
        raise ContractError("Sealed and runtime submission roots may not overlap")
    if not source.is_dir() or _is_reparse(source):
        raise ContractError("Sealed submission root is missing or is a reparse point")
    if not destination.is_dir() or _is_reparse(destination):
        raise ContractError("Runtime submission root is missing or is a reparse point")
    if any(destination.iterdir()):
        raise ContractError("Runtime submission destination must be empty")

    destination.rmdir()
    _copy_bundle(source, destination)
    if not bundles_match(source, destination):
        raise ContractError("Runtime submission copy differs from the sealed bundle")


def _evaluator_support_directory() -> Path:
    return (
        Path(__file__).resolve().parents[1]
        / "runtime"
        / "matlab"
        / "evaluator_support"
    )


def _extractor_command(
    task: TaskDefinition,
    candidate: Path,
    evidence_path: Path,
    *,
    sealed_candidate: Path,
    runtime_override_receipt: Path,
    evaluation_subject: str = "candidate",
) -> list[str]:
    if evaluation_subject not in {"candidate", "reference"}:
        raise ContractError("evaluation_subject must be candidate or reference")
    if task.extractor_kind == "python":
        return [
            os.environ.get("PYTHON", "python"),
            str(task.extractor_path),
            "--candidate",
            str(candidate),
            "--scenarios",
            str(task.scenarios_path),
            "--output",
            str(evidence_path),
        ]
    if task.extractor_kind != "matlab":
        raise ContractError(
            f"Unsupported normalized extractor kind: {task.extractor_kind}"
        )
    extractor_directory = task.extractor_path if task.extractor_path.is_dir() else task.extractor_path.parent
    runtime_helper = (
        Path(__file__).resolve().parents[1]
        / "runtime"
        / "matlab"
        / "simuverity_prepare_runtime_copy.m"
    )
    evaluator_support = _evaluator_support_directory()
    candidate_bundle = candidate.parent
    runtime_preparation = ""
    candidate_dependency_path = ""
    if evaluation_subject == "candidate":
        runtime_preparation = (
            f"simuverity_prepare_runtime_copy({_matlab_literal(candidate)},"
            f"{_matlab_literal(sealed_candidate)},{_matlab_literal(runtime_override_receipt)});"
        )
        candidate_dependency_path = (
            f"addpath(genpath({_matlab_literal(candidate_bundle)}),'-end');"
        )
    expression = (
        # MATLAB child processes do not reliably expose every inherited
        # Windows environment update to `getenv` on all launch paths.  Bind
        # the already-validated evaluator subject again inside the owned
        # batch process so subject-gated reference wrappers cannot silently
        # fall back to their candidate branch.  This mirrors (rather than
        # changes) the subprocess environment value.
        f"setenv('SIMUVERITY_EVALUATION_SUBJECT','{evaluation_subject}');"
        f"addpath(genpath({_matlab_literal(evaluator_support)}),'-begin');"
        # Diagnostic publication lives beside the runtime-copy helper, not
        # inside evaluator_support.  Reference extraction must see it even
        # though reference subjects deliberately skip runtime-copy saving.
        f"addpath({_matlab_literal(runtime_helper.parent)},'-begin');"
        f"{runtime_preparation}"
        # Candidate extraction keeps the submitted dependency bundle at the
        # end of the path. Reference dependencies are evaluator-owned and
        # must instead be supplied explicitly by the wrapper and asset root.
        f"{candidate_dependency_path}"
        f"addpath({_matlab_literal(extractor_directory)},'-begin');"
        # Bind the public wrapper, then remove its generic `run.m` directory
        # before task code executes. Otherwise task-owned calls to MATLAB's
        # built-in run(script) resolve back to the three-argument wrapper.
        f"simuverityExtractorHandle=@{task.extractor_entrypoint};"
        f"rmpath({_matlab_literal(extractor_directory)});"
        f"simuverityExtractorHandle({_matlab_literal(candidate)},"
        f"{_matlab_literal(task.scenarios_path)},{_matlab_literal(evidence_path)});"
    )
    return [os.environ.get("MATLAB_EXECUTABLE", "matlab"), "-batch", expression]


def _valid_runtime_override(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        value = load_json(path)
    except Exception:
        return False
    if not isinstance(value, Mapping):
        return False
    allowed = {"LimitDataPoints", "MaxDataPoints"}
    rows = value.get("parameter_overrides", [])
    # MATLAB jsonencode represents a scalar struct as one JSON object and a
    # struct array as a JSON array.  Normalize only that representation
    # difference; every row remains subject to the same fail-closed checks.
    if isinstance(rows, Mapping):
        rows = [rows]

    def valid_row(row: Any) -> bool:
        if not isinstance(row, Mapping):
            return False
        parameter = row.get("parameter")
        before = row.get("before")
        after = row.get("after")
        block_path = row.get("block_path")
        if (
            parameter not in allowed
            or not isinstance(block_path, str)
            or not block_path
            or not isinstance(before, str)
            or not isinstance(after, str)
        ):
            return False
        expected_after = "off" if parameter == "LimitDataPoints" else "inf"
        return after.lower() == expected_after and before.lower() != expected_after

    return (
        value.get("schema") == "simuverity.runtime-output-override.v1"
        and value.get("runtime_copy_only") is True
        and value.get("sealed_original_modified") is False
        and value.get("parameter_allowlist_only") is True
        and value.get("sealed_candidate_unchanged") is True
        and value.get("runtime_copy_prepared") is True
        and isinstance(rows, list)
        and bool(rows)
        and all(valid_row(row) for row in rows)
    )


def _run_declared_sidecars(
    task: TaskDefinition,
    *,
    sealed_candidate: Path,
    extraction_root: Path,
    environment: Mapping[str, str],
) -> dict[str, dict[str, Any]]:
    if not task.extractor_sidecars:
        return {}
    sidecar_root = extraction_root / "sidecars"
    sidecar_root.mkdir(exist_ok=False)
    results: dict[str, dict[str, Any]] = {}
    for sidecar in task.extractor_sidecars:
        output = sidecar_root / sidecar.output_name
        values = {"candidate": str(sealed_candidate), "output": str(output)}
        arguments = [value.format_map(values) for value in sidecar.arguments]
        command = [sys.executable, "-I", str(sidecar.producer_path), *arguments]
        completed = subprocess.run(
            command,
            cwd=sidecar_root,
            env=dict(environment),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        (sidecar_root / f"{sidecar.role}.stdout.log").write_text(
            completed.stdout, encoding="utf-8", newline="\n"
        )
        (sidecar_root / f"{sidecar.role}.stderr.log").write_text(
            completed.stderr, encoding="utf-8", newline="\n"
        )
        if completed.returncode != 0 or not output.is_file():
            raise ContractError(
                f"DECLARED_SIDECAR_FAILED:{sidecar.role}:exit={completed.returncode}"
            )
        value = load_json(output)
        if (
            not isinstance(value, Mapping)
            or value.get("schema") != sidecar.expected_schema
            or value.get("task_id") != task.task_id
        ):
            raise ContractError(f"DECLARED_SIDECAR_CONTRACT_INVALID:{sidecar.role}")
        results[sidecar.role] = {
            "path": output,
            "schema": sidecar.expected_schema,
        }
    return results


def _evidence_sidecar_context(bundle_path: Path, bundle: Mapping[str, Any]) -> dict[str, Any]:
    paths = resolve_evidence_sidecars(bundle_path, bundle)
    rows = {
        str(item["role"]): item
        for item in bundle.get("sidecars", [])
        if isinstance(item, Mapping) and item.get("role")
    }
    bindings = {
        role: {
            "path": str(path),
            "size_bytes": rows[role]["size_bytes"],
            "schema": rows[role].get("schema", ""),
        }
        for role, path in paths.items()
    }
    context: dict[str, Any] = {}
    if bindings:
        context["evidence_sidecars"] = bindings
    if "structure_audit" in bindings:
        context["structure_audit_path"] = bindings["structure_audit"]["path"]
    artifact_rows = bundle.get("artifacts", [])
    if isinstance(artifact_rows, list) and artifact_rows:
        context["evidence_artifacts"] = {
            str(item["file"]): {
                "path": str(bundle_path.parent / str(item["file"])),
                "size_bytes": item["size_bytes"],
            }
            for item in artifact_rows
            if isinstance(item, Mapping)
        }
    return context


def _receipt_path(layout_root: Path) -> Path:
    return layout_root / "evaluation_result.json"


def _invalid_extractor_diagnostic(path: Path, task_id: str) -> tuple[list[str], dict[str, Any]] | None:
    if not path.is_file():
        return None
    try:
        evidence = load_json(path)
    except Exception:
        return None
    if (
        not isinstance(evidence, Mapping)
        or evidence.get("task_id") != task_id
        or evidence.get("score_inputs_valid") is not False
    ):
        return None
    identifiers: list[str] = []
    errors = evidence.get("errors", {})
    if isinstance(errors, Mapping):
        for value in errors.values():
            if isinstance(value, Mapping) and isinstance(value.get("identifier"), str):
                identifiers.append(value["identifier"])
    scenarios = evidence.get("scenarios", [])
    if isinstance(scenarios, list):
        for row in scenarios:
            error = row.get("error", {}) if isinstance(row, Mapping) else {}
            if isinstance(error, Mapping) and isinstance(error.get("identifier"), str):
                identifiers.append(error["identifier"])
    reasons = ["EXTRACTOR_SCORE_INPUTS_INVALID"]
    reasons.extend(f"EXTRACTOR_DIAGNOSTIC:{value}" for value in sorted(set(filter(None, identifiers))))
    return reasons, dict(evidence)


def _prepare_pmsm_measurement_pack(
    task: TaskDefinition,
    *,
    evaluator_asset_root: Path,
    layout: RuntimeLayout,
    environment: Mapping[str, str],
) -> Path | None:
    """Materialize the one evaluator-owned input required by the PMSM task."""

    if task.task_id != "XAUTO-13":
        return None
    default_root = (task.root / str(task.reference.get("path", "reference/files"))).resolve()
    declared_entrypoint = (task.root / str(task.reference["entrypoint"])).resolve()
    try:
        relative_entrypoint = declared_entrypoint.relative_to(default_root)
    except ValueError as exc:
        raise ContractError("PMSM reference entrypoint escapes its asset root") from exc
    source_entrypoint = evaluator_asset_root / relative_entrypoint
    if not source_entrypoint.is_file():
        raise ContractError("PMSM reference entrypoint is missing")

    input_root = layout.root / "evaluator_inputs" / "pmsm"
    runtime_root = input_root / "reference_runtime"
    extraction_root = input_root / "reference_extraction"
    input_root.mkdir(parents=True, exist_ok=False)
    _copy_bundle(evaluator_asset_root, runtime_root)
    _make_bundle_writable(runtime_root)
    runtime_entrypoint = runtime_root / relative_entrypoint
    extraction_root.mkdir(exist_ok=False)
    evidence_path = extraction_root / "evidence.json"
    command = _extractor_command(
        task,
        runtime_entrypoint,
        evidence_path,
        sealed_candidate=runtime_entrypoint,
        runtime_override_receipt=extraction_root / "runtime_override_receipt.json",
        evaluation_subject="reference",
    )
    reference_environment = dict(environment)
    reference_environment["SIMUVERITY_EVALUATION_SUBJECT"] = "reference"
    reference_environment["SIMUVERITY_EVALUATOR_ASSET_ROOT"] = str(runtime_root)
    reference_environment.pop("SIMUVERITY_EXT_PMSM_MEASUREMENT_PACK", None)
    completed = subprocess.run(
        command,
        cwd=layout.workspace,
        env=reference_environment,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    (extraction_root / "stdout.log").write_text(
        completed.stdout, encoding="utf-8", newline="\n"
    )
    (extraction_root / "stderr.log").write_text(
        completed.stderr, encoding="utf-8", newline="\n"
    )
    pack_path = extraction_root / "pmsm_measurement_experiments.mat"
    if completed.returncode != 0 or not evidence_path.is_file() or not pack_path.is_file():
        raise ContractError(
            f"PMSM evaluator input preparation failed with exit code {completed.returncode}"
        )
    return pack_path


_CANDIDATE_REFERENCE_INPUT_TASKS = frozenset({"XAUTO-13"})


def _resolve_evaluator_asset_root(
    task: TaskDefinition,
    *,
    evaluator_asset_root: Path | None,
    evaluation_subject: str,
) -> Path | None:
    """Resolve reference assets only for reference evaluation or a declared input.

    Candidate evaluation is intentionally independent of optional local-importer
    references.  The one current candidate workflow that derives an evaluator
    input from a reference uses a bundled reference and is named explicitly.
    """

    if evaluation_subject not in {"candidate", "reference"}:
        raise ContractError("evaluation_subject must be candidate or reference")
    needs_reference = (
        evaluation_subject == "reference"
        or task.task_id in _CANDIDATE_REFERENCE_INPUT_TASKS
    )
    if not needs_reference:
        return None
    if evaluator_asset_root is None:
        from ..assets import resolve_reference_asset_root

        evaluator_asset_root = resolve_reference_asset_root(task)
    resolved = evaluator_asset_root.resolve()
    if not resolved.is_dir():
        raise ContractError(f"{task.task_id}: evaluator asset root is missing")
    return resolved


def _evaluate_submission_in_layout(
    task: TaskDefinition,
    *,
    submission_root: Path,
    layout: RuntimeLayout,
    matlab_scratch: MatlabScratchLayout,
    generation_run_id: str,
    scoring_run_id: str,
    simulation_timeout_seconds: int = 1800,
    evaluator_asset_root: Path | None = None,
    evaluation_subject: str = "candidate",
) -> dict[str, Any]:
    started_at = _utc_now()
    try:
        closure = seal_submission(
            submission_root,
            required_model_file=task.required_model_file,
            closure_root=layout.root / "closure",
            task_id=task.task_id,
            generation_run_id=generation_run_id,
        )
    except ContractError as exc:
        receipt = {
            "schema": "simuverity.evaluation-result.v1",
            "status": "CANDIDATE_INVALID",
            "failure_attribution": "candidate",
            "failure_reasons": [str(exc)],
            "task_id": task.task_id,
            "generation_run_id": generation_run_id,
            "scoring_run_id": scoring_run_id,
            "candidate_file": "",
            "evidence_complete": False,
            "started_at": started_at,
            "ended_at": _utc_now(),
        }
        write_json_exclusive(_receipt_path(layout.root), receipt)
        return {**receipt, "receipt_path": str(_receipt_path(layout.root))}
    sealed_candidate = Path(closure["sealed_candidate"])
    original_bytes = sealed_candidate.read_bytes()
    environment = build_isolated_environment(layout, allow_credentials=False)
    if evaluation_subject not in {"candidate", "reference"}:
        raise ContractError("evaluation_subject must be candidate or reference")
    evaluator_asset_root = _resolve_evaluator_asset_root(
        task,
        evaluator_asset_root=evaluator_asset_root,
        evaluation_subject=evaluation_subject,
    )
    # Reference-only clean-replay setup runs in its own MATLAB process before
    # extraction, so it must receive the same evaluator-owned subject binding.
    # Candidate evaluation keeps the explicit candidate value and never
    # resolves a reference setup helper.
    environment["SIMUVERITY_EVALUATION_SUBJECT"] = evaluation_subject
    if task.task_id == "XMED-10":
        environment["SIMUVERITY_F90_XMED10_PYTHON_EXE"] = sys.executable
    matlab_environment = dict(environment)
    matlab_environment.update(matlab_scratch.environment())
    try:
        clean_replay = run_clean_replay(
            task,
            sealed_candidate=sealed_candidate,
            output_root=layout.root / "clean_replay",
            environment=matlab_environment,
            simulation_timeout_seconds=simulation_timeout_seconds,
            evaluation_subject=evaluation_subject,
        )
    except (ContractError, OSError, ValueError) as exc:
        receipt = {
            "schema": "simuverity.evaluation-result.v1",
            "status": "EVALUATION_INFRA_ERROR",
            "failure_attribution": "evaluation_infrastructure",
            "failure_reasons": [f"CLEAN_REPLAY_RUNTIME_CONTRACT:{exc}"],
            "task_id": task.task_id,
            "generation_run_id": generation_run_id,
            "scoring_run_id": scoring_run_id,
            "candidate_file": task.required_model_file,
            "evidence_complete": False,
            "started_at": started_at,
            "ended_at": _utc_now(),
        }
        write_json_exclusive(_receipt_path(layout.root), receipt)
        return {**receipt, "receipt_path": str(_receipt_path(layout.root))}
    if clean_replay["status"] != "CANDIDATE_CLOSURE_PASSED":
        status = clean_replay["status"]
        if status == "GENERATION_INFRA_ERROR":
            status = "EVALUATION_INFRA_ERROR"
            attribution = "evaluation_infrastructure"
        else:
            attribution = "candidate"
        receipt = {
            "schema": "simuverity.evaluation-result.v1",
            "status": status,
            "failure_attribution": attribution,
            "failure_reasons": [str(clean_replay.get("failure_reason", clean_replay.get("failed_phase", "CLEAN_REPLAY_FAILED")))],
            "task_id": task.task_id,
            "generation_run_id": generation_run_id,
            "scoring_run_id": scoring_run_id,
            "candidate_file": task.required_model_file,
            "evidence_complete": False,
            "clean_replay_status": clean_replay["status"],
            "reference_clean_replay_setup_phase": clean_replay.get(
                "reference_clean_replay_setup_phase", ""
            ),
            "started_at": started_at,
            "ended_at": _utc_now(),
        }
        write_json_exclusive(_receipt_path(layout.root), receipt)
        return {**receipt, "receipt_path": str(_receipt_path(layout.root))}
    _copy_sealed_bundle_to_runtime(
        Path(closure["sealed_submission"]), layout.submission
    )
    writable_file_count = _make_bundle_writable(layout.submission)
    if writable_file_count != int(closure["file_count"]):
        raise ContractError("Runtime writable walk did not visit the sealed file closure")
    runtime_candidate = layout.submission / task.required_model_file
    extraction_root = layout.root / "extraction"
    extraction_root.mkdir(exist_ok=False)
    evidence_source = extraction_root / "evidence.json"
    runtime_override_receipt = extraction_root / "runtime_override_receipt.json"
    command = _extractor_command(
        task,
        runtime_candidate,
        evidence_source,
        sealed_candidate=sealed_candidate,
        runtime_override_receipt=runtime_override_receipt,
        evaluation_subject=evaluation_subject,
    )
    evaluation_bindings = {
            "SIMUVERITY_TASK_ID": task.task_id,
            "SIMUVERITY_GENERATION_RUN_ID": generation_run_id,
            "SIMUVERITY_SCORING_RUN_ID": scoring_run_id,
            "SIMUVERITY_RUN_ROOT": str(layout.root),
            "SIMUVERITY_WORKSPACE": str(layout.workspace),
            "SIMUVERITY_MATLAB_LANE": "evaluation",
            "SIMUVERITY_RUNTIME_OVERRIDE_PATH": str(runtime_override_receipt),
            "SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE": str(layout.submission),
            "SIMUVERITY_SEALED_SUBMISSION_BUNDLE": str(closure["sealed_submission"]),
            "SIMUVERITY_SEALED_CANDIDATE_PATH": str(sealed_candidate),
            "SIMUVERITY_EVALUATION_SUBJECT": evaluation_subject,
        }
    if evaluator_asset_root is not None:
        evaluation_bindings["SIMUVERITY_EVALUATOR_ASSET_ROOT"] = str(
            evaluator_asset_root
        )
    environment.update(evaluation_bindings)
    matlab_environment.update(evaluation_bindings)
    try:
        if (
            evaluation_subject == "candidate"
            and task.task_id in _CANDIDATE_REFERENCE_INPUT_TASKS
        ):
            if evaluator_asset_root is None:  # pragma: no cover - contract guard
                raise ContractError("PMSM evaluator input requires bundled assets")
            measurement_pack = _prepare_pmsm_measurement_pack(
                task,
                evaluator_asset_root=evaluator_asset_root,
                layout=layout,
                environment=matlab_environment,
            )
        else:
            measurement_pack = None
    except (ContractError, OSError, ValueError) as exc:
        receipt = {
            "schema": "simuverity.evaluation-result.v1",
            "status": "EVALUATION_INFRA_ERROR",
            "failure_attribution": "evaluation_infrastructure",
            "failure_reasons": [f"EVALUATOR_INPUT_PREPARATION:{exc}"],
            "task_id": task.task_id,
            "generation_run_id": generation_run_id,
            "scoring_run_id": scoring_run_id,
            "candidate_file": task.required_model_file,
            "evidence_complete": False,
            "started_at": started_at,
            "ended_at": _utc_now(),
        }
        write_json_exclusive(_receipt_path(layout.root), receipt)
        return {**receipt, "receipt_path": str(_receipt_path(layout.root))}
    if measurement_pack is not None:
        environment["SIMUVERITY_EXT_PMSM_MEASUREMENT_PACK"] = str(measurement_pack)
        matlab_environment["SIMUVERITY_EXT_PMSM_MEASUREMENT_PACK"] = str(
            measurement_pack
        )
    if task.extractor_kind == "matlab":
        extractor_environment = matlab_environment
    elif task.extractor_kind == "python":
        extractor_environment = environment
    else:
        raise ContractError(
            f"Unsupported normalized extractor kind: {task.extractor_kind}"
        )
    try:
        completed = subprocess.run(
            command,
            # Never use the directory containing the same-named sealed model as
            # MATLAB's current folder.  See _extractor_command for how the full
            # dependency bundle remains available without shadowing the inner
            # runtime model.
            cwd=layout.workspace,
            env=extractor_environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    finally:
        if measurement_pack is not None:
            shutil.rmtree(layout.root / "evaluator_inputs")
    (extraction_root / "stdout.log").write_text(completed.stdout, encoding="utf-8", newline="\n")
    (extraction_root / "stderr.log").write_text(completed.stderr, encoding="utf-8", newline="\n")
    invalid_diagnostic = _invalid_extractor_diagnostic(evidence_source, task.task_id)
    if completed.returncode != 0 or not evidence_source.is_file():
        candidate_diagnostic = invalid_diagnostic is not None
        receipt = {
            "schema": "simuverity.evaluation-result.v1",
            "status": "CANDIDATE_INVALID" if candidate_diagnostic else "EVALUATION_INFRA_ERROR",
            "failure_attribution": "candidate" if candidate_diagnostic else "evaluation_infrastructure",
            "failure_reasons": (
                invalid_diagnostic[0]
                if candidate_diagnostic
                else [f"EXTRACTOR_EXIT_NONZERO:{completed.returncode}"]
                if completed.returncode
                else ["EXTRACTOR_EVIDENCE_MISSING"]
            ),
            "task_id": task.task_id,
            "generation_run_id": generation_run_id,
            "scoring_run_id": scoring_run_id,
            "candidate_file": task.required_model_file,
            "evidence_complete": False,
            "diagnostic_evidence_path": str(evidence_source) if candidate_diagnostic else "",
            "started_at": started_at,
            "ended_at": _utc_now(),
        }
        write_json_exclusive(_receipt_path(layout.root), receipt)
        return {**receipt, "receipt_path": str(_receipt_path(layout.root))}
    if sealed_candidate.read_bytes() != original_bytes:
        raise ContractError("Extractor modified the sealed candidate")
    extracted = load_json(evidence_source)
    if isinstance(extracted, Mapping) and extracted.get("evidence_complete") is False:
        receipt = {
            "schema": "simuverity.evaluation-result.v1",
            "status": "EVALUATION_INFRA_ERROR",
            "failure_attribution": "evaluation_infrastructure",
            "failure_reasons": ["EXTRACTOR_DECLARED_EVIDENCE_INCOMPLETE"],
            "task_id": task.task_id,
            "generation_run_id": generation_run_id,
            "scoring_run_id": scoring_run_id,
            "candidate_file": task.required_model_file,
            "evidence_complete": False,
            "diagnostic_evidence_path": str(evidence_source),
            "started_at": started_at,
            "ended_at": _utc_now(),
        }
        write_json_exclusive(_receipt_path(layout.root), receipt)
        return {**receipt, "receipt_path": str(_receipt_path(layout.root))}
    if runtime_candidate.read_bytes() != original_bytes and not _valid_runtime_override(
        runtime_override_receipt
    ):
        raise ContractError("Runtime candidate changed outside the two allowed logging overrides")
    try:
        sidecars = _run_declared_sidecars(
            task,
            sealed_candidate=sealed_candidate,
            extraction_root=extraction_root,
            environment=environment,
        )
    except (ContractError, OSError, ValueError) as exc:
        receipt = {
            "schema": "simuverity.evaluation-result.v1",
            "status": "EVALUATION_INFRA_ERROR",
            "failure_attribution": "evaluation_infrastructure",
            "failure_reasons": [str(exc)],
            "task_id": task.task_id,
            "generation_run_id": generation_run_id,
            "scoring_run_id": scoring_run_id,
            "candidate_file": task.required_model_file,
            "evidence_complete": False,
            "started_at": started_at,
            "ended_at": _utc_now(),
        }
        write_json_exclusive(_receipt_path(layout.root), receipt)
        return {**receipt, "receipt_path": str(_receipt_path(layout.root))}
    bundle_path = create_evidence_bundle(
        evidence_source,
        bundle_root=layout.root / "evidence_bundle",
        task_id=task.task_id,
        generation_run_id=generation_run_id,
        scoring_run_id=scoring_run_id,
        candidate_file=task.required_model_file,
        scenarios_source=task.scenarios_path,
        evaluation_policy_id=task.evaluation_policy_id,
        evaluation_subject=evaluation_subject,
        sidecars=sidecars,
    )
    bundle, evidence_copy = validate_evidence_bundle(
        bundle_path, task_id=task.task_id, scenarios_path=task.scenarios_path
    )
    score_context = {
        "schema": "simuverity.scoring-context.v1",
        "task_id": task.task_id,
        "generation_run_id": generation_run_id,
        "scoring_run_id": scoring_run_id,
        "evaluation_policy_id": task.evaluation_policy_id,
        "candidate_file": task.required_model_file,
        "evidence_file": bundle["evidence_file"],
        "evidence_bundle_path": str(bundle_path),
        "evidence_path": str(evidence_copy),
        "official_scenarios_path": str(bundle_path.parent / bundle["official_scenarios_file"]),
        "subject": evaluation_subject,
    }
    score_context.update(_evidence_sidecar_context(bundle_path, bundle))
    score = run_offline_scorer(
        task,
        evidence_path=evidence_copy,
        output_root=layout.root / "offline_scoring",
        context=score_context,
    )
    receipt = {
        "schema": "simuverity.evaluation-result.v1",
        "status": score.get("status", "SCORED"),
        "failure_attribution": "",
        "task_id": task.task_id,
        "generation_run_id": generation_run_id,
        "scoring_run_id": scoring_run_id,
        "evaluation_policy_id": task.evaluation_policy_id,
        "candidate_file": task.required_model_file,
        "evidence_complete": True,
        "evidence_file": bundle["evidence_file"],
        "evidence_sidecars": bundle.get("sidecars", []),
        "reference_clean_replay_setup_phase": clean_replay.get(
            "reference_clean_replay_setup_phase", ""
        ),
        "protocol_zero": bool(score.get("protocol_zero", False)),
        "score": score,
        "started_at": started_at,
        "ended_at": _utc_now(),
    }
    write_json_exclusive(_receipt_path(layout.root), receipt)
    return {**receipt, "receipt_path": str(_receipt_path(layout.root)), "evidence_bundle_path": str(bundle_path)}


def evaluate_submission(
    task: TaskDefinition,
    *,
    submission_root: Path,
    output_parent: Path,
    generation_run_id: str,
    scoring_run_id: str,
    simulation_timeout_seconds: int = 1800,
    evaluator_asset_root: Path | None = None,
    evaluation_subject: str = "candidate",
) -> dict[str, Any]:
    """Evaluate with a durable result tree and a separate short MATLAB tree."""

    repository_root = task.root.parent.parent
    reserve_identity(
        repository_root,
        kind="scoring",
        identity=scoring_run_id,
        task_id=task.task_id,
    )
    layout = create_runtime_layout(output_parent, scoring_run_id)
    matlab_scratch = create_evaluation_matlab_scratch(
        scoring_run_id,
        receipt_root=layout.root,
    )
    try:
        return _evaluate_submission_in_layout(
            task,
            submission_root=submission_root,
            layout=layout,
            matlab_scratch=matlab_scratch,
            generation_run_id=generation_run_id,
            scoring_run_id=scoring_run_id,
            simulation_timeout_seconds=simulation_timeout_seconds,
            evaluator_asset_root=evaluator_asset_root,
            evaluation_subject=evaluation_subject,
        )
    finally:
        cleanup_evaluation_matlab_scratch(matlab_scratch)


def rescore_evidence(
    task: TaskDefinition,
    *,
    evidence_bundle_path: Path,
    output_parent: Path,
    scoring_run_id: str,
) -> dict[str, Any]:
    bundle, evidence_path = validate_evidence_bundle(
        evidence_bundle_path, task_id=task.task_id, scenarios_path=task.scenarios_path
    )
    repository_root = task.root.parent.parent
    reserve_identity(repository_root, kind="scoring", identity=scoring_run_id, task_id=task.task_id)
    output_root = output_parent.resolve() / scoring_run_id
    if output_root.exists():
        raise ContractError(f"Scoring run is not fresh: {scoring_run_id}")
    output_root.mkdir(parents=True, exist_ok=False)
    score_context = {
        "schema": "simuverity.scoring-context.v1",
        "task_id": task.task_id,
        "generation_run_id": bundle["generation_run_id"],
        "scoring_run_id": scoring_run_id,
        "evaluation_policy_id": task.evaluation_policy_id,
        "candidate_file": bundle["candidate_file"],
        "evidence_file": bundle["evidence_file"],
        "evidence_bundle_path": str(evidence_bundle_path.resolve()),
        "evidence_path": str(evidence_path),
        "official_scenarios_path": str(
            evidence_bundle_path.resolve().parent / bundle["official_scenarios_file"]
        ),
        "subject": bundle.get("evaluation_subject", "candidate"),
        "rescored_from_run_id": bundle["scoring_run_id"],
        "would_start_matlab": False,
        "would_start_mcp": False,
        "would_resimulate": False,
    }
    score_context.update(_evidence_sidecar_context(evidence_bundle_path.resolve(), bundle))
    score = run_offline_scorer(
        task,
        evidence_path=evidence_path,
        output_root=output_root / "offline_scoring",
        context=score_context,
    )
    receipt = {
        "schema": "simuverity.evaluation-result.v1",
        "status": score.get("status", "SCORED"),
        "task_id": task.task_id,
        "generation_run_id": bundle["generation_run_id"],
        "scoring_run_id": scoring_run_id,
        "evaluation_policy_id": task.evaluation_policy_id,
        "candidate_file": bundle["candidate_file"],
        "evidence_complete": True,
        "evidence_file": bundle["evidence_file"],
        "evidence_sidecars": bundle.get("sidecars", []),
        "rescored_from_run_id": bundle["scoring_run_id"],
        "matlab_or_mcp_started": False,
        "resimulated": False,
        "protocol_zero": bool(score.get("protocol_zero", False)),
        "score": score,
        "started_at": _utc_now(),
        "ended_at": _utc_now(),
    }
    receipt_path = output_root / "evaluation_result.json"
    write_json_exclusive(receipt_path, receipt)
    return {**receipt, "receipt_path": str(receipt_path)}
