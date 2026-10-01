from __future__ import annotations

import contextlib
import os
import re
import shutil
import stat
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, Mapping

from ...errors import ContractError
from ...jsonutil import load_json, write_json_exclusive

IDENTITY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
REPARSE_POINT = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _native_path(path: Path) -> str:
    """Return the exact path using Windows extended-length transport."""

    value = os.path.abspath(os.fspath(path))
    if os.name != "nt" or value.startswith("\\\\?\\"):
        return value
    if value.startswith("\\\\"):
        return "\\\\?\\UNC\\" + value[2:]
    return "\\\\?\\" + value


def _is_reparse(path: Path) -> bool:
    try:
        info = os.lstat(path)
    except OSError:
        return True
    return path.is_symlink() or bool(
        getattr(info, "st_file_attributes", 0) & REPARSE_POINT
    )


@dataclass(frozen=True)
class RuntimeLayout:
    root: Path
    workspace: Path
    submission: Path
    appdata: Path
    localappdata: Path
    temp: Path
    matlab_prefdir: Path
    simulink_cache: Path
    simulink_codegen: Path
    mcp_log: Path
    agent_home: Path
    claude_config: Path

    def environment(self) -> dict[str, str]:
        return {
            "APPDATA": str(self.appdata),
            "LOCALAPPDATA": str(self.localappdata),
            "TEMP": str(self.temp),
            "TMP": str(self.temp),
            "MATLAB_PREFDIR": str(self.matlab_prefdir),
            "SIMULINK_CACHE_FOLDER": str(self.simulink_cache),
            "SIMULINK_CODEGEN_FOLDER": str(self.simulink_codegen),
            "SIMUVERITY_CACHE_DIR": str(self.simulink_cache),
            "SIMUVERITY_CODEGEN_DIR": str(self.simulink_codegen),
        }


@dataclass(frozen=True)
class MatlabScratchLayout:
    """Fresh short-lived MATLAB process state owned by one scoring run."""

    scoring_run_id: str
    base_root: Path
    root: Path
    matlab_prefdir: Path
    temp: Path
    simulink_cache: Path
    simulink_codegen: Path
    binding_receipt_path: Path

    @property
    def role_paths(self) -> dict[str, Path]:
        return {
            "matlab_prefdir": self.matlab_prefdir,
            "temp": self.temp,
            "simulink_cache": self.simulink_cache,
            "simulink_codegen": self.simulink_codegen,
        }

    def environment(self) -> dict[str, str]:
        return {
            "TEMP": str(self.temp),
            "TMP": str(self.temp),
            "MATLAB_PREFDIR": str(self.matlab_prefdir),
            "SIMULINK_CACHE_FOLDER": str(self.simulink_cache),
            "SIMULINK_CODEGEN_FOLDER": str(self.simulink_codegen),
            "SIMUVERITY_CACHE_DIR": str(self.simulink_cache),
            "SIMUVERITY_CODEGEN_DIR": str(self.simulink_codegen),
        }


def _stable_evaluation_scratch_name(scoring_run_id: str) -> str:
    if not IDENTITY_RE.fullmatch(scoring_run_id):
        raise ContractError("Scoring run ID contains unsupported characters or is too long")
    return f"sv-score-{scoring_run_id.lower()}"


def create_evaluation_matlab_scratch(
    scoring_run_id: str,
    *,
    receipt_root: Path,
    base_root: Path | None = None,
) -> MatlabScratchLayout:
    """Create one mature-CC-style short p/t/x/g tree and bind it durably."""

    stable_name = _stable_evaluation_scratch_name(scoring_run_id)
    scratch_parent = (
        (Path.home() / ".svr") if base_root is None else base_root
    ).resolve()
    scratch_parent.mkdir(parents=True, exist_ok=True)
    if _is_reparse(scratch_parent):
        raise ContractError("MATLAB scratch parent may not be a reparse point")
    root = (scratch_parent / stable_name).resolve()
    if root.parent != scratch_parent:
        raise ContractError("MATLAB scratch root escaped its configured parent")
    if root.exists():
        raise ContractError(f"MATLAB scratch run is not fresh: {scoring_run_id}")

    durable_receipt_root = receipt_root.resolve()
    try:
        durable_receipt_root.relative_to(root)
    except ValueError:
        pass
    else:
        raise ContractError("MATLAB scratch receipts must remain outside the scratch root")
    durable_receipt_root.mkdir(parents=True, exist_ok=True)

    roles = {
        "matlab_prefdir": root / "p",
        "temp": root / "t",
        "simulink_cache": root / "x",
        "simulink_codegen": root / "g",
    }
    root.mkdir(exist_ok=False)
    try:
        for path in roles.values():
            path.mkdir(exist_ok=False)
    except BaseException:
        shutil.rmtree(root, ignore_errors=True)
        raise

    binding_receipt_path = durable_receipt_root / "matlab_scratch_binding.json"
    binding = {
        "schema": "simuverity.matlab-scratch-binding.v1",
        "scoring_run_id": scoring_run_id,
        "scratch_root_name": stable_name,
        "scratch_root_length": len(str(root)),
        "base_root_kind": "configured" if base_root is not None else "user_profile_runtime",
        "exclusive": True,
        "fresh": True,
        "child_process_only": True,
        "roles": {
            name: {
                "relative_path": path.relative_to(root).as_posix(),
                "path_length": len(str(path)),
            }
            for name, path in roles.items()
        },
        "created_at": _utc_now(),
    }
    try:
        write_json_exclusive(binding_receipt_path, binding)
    except BaseException:
        shutil.rmtree(root, ignore_errors=True)
        raise
    return MatlabScratchLayout(
        scoring_run_id=scoring_run_id,
        base_root=scratch_parent,
        root=root,
        binding_receipt_path=binding_receipt_path,
        **roles,
    )


def _validate_owned_matlab_scratch(scratch: MatlabScratchLayout) -> None:
    stable_name = _stable_evaluation_scratch_name(scratch.scoring_run_id)
    if scratch.root != scratch.base_root / stable_name or scratch.root.parent != scratch.base_root:
        raise ContractError("MATLAB scratch root is not the scoring-run-owned child")
    if scratch.root.exists() and (
        scratch.root.resolve() != scratch.root or _is_reparse(scratch.root)
    ):
        raise ContractError("MATLAB scratch root became a reparse point or escaped confinement")
    expected_roles = {
        "matlab_prefdir": scratch.root / "p",
        "temp": scratch.root / "t",
        "simulink_cache": scratch.root / "x",
        "simulink_codegen": scratch.root / "g",
    }
    if scratch.role_paths != expected_roles:
        raise ContractError("MATLAB scratch role paths changed after binding")
    for path in expected_roles.values():
        if path.exists() and (path.resolve() != path or _is_reparse(path)):
            raise ContractError("MATLAB scratch role became a reparse point or escaped confinement")

    binding = load_json(scratch.binding_receipt_path)
    if not isinstance(binding, Mapping):
        raise ContractError("MATLAB scratch binding receipt is invalid")
    if (
        binding.get("schema") != "simuverity.matlab-scratch-binding.v1"
        or binding.get("scoring_run_id") != scratch.scoring_run_id
        or binding.get("scratch_root_name") != stable_name
    ):
        raise ContractError("MATLAB scratch binding receipt no longer matches the owned root")


def _remove_owned_matlab_scratch(root: Path) -> None:
    """Remove only one validated root despite MAX_PATH and retiring children."""

    native_root = _native_path(root)

    def make_writable_or_ignore_disappeared(function, value, exception_info) -> None:
        error = exception_info[1]
        if isinstance(error, FileNotFoundError) or getattr(error, "winerror", None) == 3:
            return
        try:
            os.chmod(value, stat.S_IWRITE)
            function(value)
        except OSError as retry_error:
            if isinstance(retry_error, FileNotFoundError) or getattr(
                retry_error, "winerror", None
            ) == 3:
                return
            raise

    attempts = 100
    for attempt in range(attempts):
        if not os.path.exists(native_root):
            return
        try:
            shutil.rmtree(native_root, onerror=make_writable_or_ignore_disappeared)
        except OSError as error:
            retryable = getattr(error, "winerror", None) == 145 or error.errno == 39
            if not retryable or attempt == attempts - 1:
                raise
        else:
            if not os.path.exists(native_root):
                return
            if attempt == attempts - 1:
                raise OSError(39, "MATLAB scratch root remained non-empty")
        time.sleep(0.05)


def cleanup_evaluation_matlab_scratch(scratch: MatlabScratchLayout) -> dict[str, object]:
    """Remove only the exact owned root and leave a durable recovery receipt."""

    cleanup_receipt_path = (
        scratch.binding_receipt_path.parent / "matlab_scratch_cleanup_receipt.json"
    )
    failure_reason = ""
    existed_before = scratch.root.exists()
    try:
        _validate_owned_matlab_scratch(scratch)
        if existed_before:
            _remove_owned_matlab_scratch(scratch.root)
    except (ContractError, OSError, ValueError) as exc:
        failure_reason = str(exc)

    exists_after = scratch.root.exists()
    status = "CLEANED" if not failure_reason and not exists_after else "CLEANUP_FAILED_RETAINED"
    cleanup = {
        "schema": "simuverity.matlab-scratch-cleanup.v1",
        "status": status,
        "scoring_run_id": scratch.scoring_run_id,
        "binding_receipt": scratch.binding_receipt_path.name,
        "scratch_root_name": scratch.root.name,
        "scratch_root_existed_before": existed_before,
        "scratch_root_exists_after": exists_after,
        "failure_reason": failure_reason,
        "ended_at": _utc_now(),
    }
    write_json_exclusive(cleanup_receipt_path, cleanup)
    return {**cleanup, "receipt_path": str(cleanup_receipt_path)}


def create_runtime_layout(parent: Path, identity: str) -> RuntimeLayout:
    if not IDENTITY_RE.fullmatch(identity):
        raise ContractError("Run identity contains unsupported characters or is too long")
    parent = parent.resolve()
    root = (parent / identity).resolve()
    try:
        root.relative_to(parent)
    except ValueError as exc:
        raise ContractError("Run root escaped its configured parent") from exc
    if root.exists():
        raise ContractError(f"Run identity is not fresh: {identity}")
    roles = {
        "workspace": root / "w",
        "submission": root / "s",
        "appdata": root / "a",
        "localappdata": root / "l",
        "temp": root / "t",
        "matlab_prefdir": root / "p",
        "simulink_cache": root / "x",
        "simulink_codegen": root / "g",
        "mcp_log": root / "m",
        "agent_home": root / "codex",
        "claude_config": root / "claude",
    }
    root.mkdir(parents=True, exist_ok=False)
    for path in roles.values():
        path.mkdir(exist_ok=False)
    return RuntimeLayout(root=root, **roles)


SENSITIVE_GENERATION_NAMES = {
    "OPENAI_API_KEY",
    "OPENAI_BASE_URL",
    "AZURE_OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_BASE_URL",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
}


def build_isolated_environment(
    layout: RuntimeLayout,
    *,
    inherited: Mapping[str, str] | None = None,
    allow_credentials: bool = True,
) -> dict[str, str]:
    source = dict(os.environ if inherited is None else inherited)
    environment = {
        name: value
        for name, value in source.items()
        if not name.upper().startswith("SIMUVERITY_")
    }
    environment.update(layout.environment())
    environment["NO_COLOR"] = "1"
    environment["PYTHONUTF8"] = "1"
    if not allow_credentials:
        for name in SENSITIVE_GENERATION_NAMES:
            environment.pop(name, None)
    return environment


@contextlib.contextmanager
def isolated_environment(layout: RuntimeLayout, *, allow_credentials: bool = True) -> Iterator[dict[str, str]]:
    """Yield a child-process environment; the parent process is never mutated."""

    yield build_isolated_environment(layout, allow_credentials=allow_credentials)
