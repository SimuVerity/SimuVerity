from __future__ import annotations

import filecmp
import os
import shutil
import stat
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..errors import ContractError
from ..jsonutil import write_json_exclusive

REPARSE_POINT = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)


@dataclass(frozen=True)
class BundleSnapshot:
    root: Path
    files: tuple[dict[str, Any], ...]


def _native_path(path: Path) -> str:
    """Return an exact filesystem path that survives Windows MAX_PATH."""
    value = os.path.abspath(os.fspath(path))
    if os.name != "nt" or value.startswith("\\\\?\\"):
        return value
    if value.startswith("\\\\"):
        return "\\\\?\\UNC\\" + value[2:]
    return "\\\\?\\" + value


def _logical_path(path: str) -> Path:
    """Remove only the Windows extended-length transport prefix."""
    if path.startswith("\\\\?\\UNC\\"):
        return Path("\\\\" + path[8:])
    if path.startswith("\\\\?\\"):
        return Path(path[4:])
    return Path(path)


def _is_reparse(path: Path) -> bool:
    try:
        native = _native_path(path)
        info = os.lstat(native)
    except OSError:
        return True
    return os.path.islink(native) or bool(
        getattr(info, "st_file_attributes", 0) & REPARSE_POINT
    )


def snapshot_bundle(root: Path) -> BundleSnapshot:
    root = root.resolve()
    if not root.is_dir():
        raise ContractError(f"Submission directory is missing: {root}")
    rows: list[dict[str, Any]] = []
    for current, directories, files in os.walk(
        _native_path(root), topdown=True, followlinks=False
    ):
        current_path = _logical_path(current)
        for name in [*directories, *files]:
            if _is_reparse(current_path / name):
                raise ContractError("Submission bundles may not contain symlinks or reparse points")
        for name in files:
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            rows.append(
                {
                    "relative_path": relative,
                    "bytes": os.stat(_native_path(path)).st_size,
                }
            )
    rows.sort(key=lambda row: row["relative_path"])
    return BundleSnapshot(root=root, files=tuple(rows))


def bundles_match(left: Path, right: Path) -> bool:
    """Compare two plain-file bundles directly."""

    left_snapshot = snapshot_bundle(left)
    right_snapshot = snapshot_bundle(right)
    if left_snapshot.files != right_snapshot.files:
        return False
    return all(
        filecmp.cmp(
            _native_path(left / row["relative_path"]),
            _native_path(right / row["relative_path"]),
            shallow=False,
        )
        for row in left_snapshot.files
    )


def _copy_bundle(source: Path, destination: Path) -> None:
    if destination.exists():
        raise ContractError(f"Closure destination is not fresh: {destination}")
    destination.mkdir(parents=True, exist_ok=False)
    for current, directories, files in os.walk(
        _native_path(source), topdown=True, followlinks=False
    ):
        current_path = _logical_path(current)
        relative = current_path.relative_to(source)
        target_directory = destination / relative
        os.makedirs(_native_path(target_directory), exist_ok=True)
        for name in directories:
            path = current_path / name
            if _is_reparse(path):
                raise ContractError("Submission bundles may not contain symlinks or reparse points")
            os.makedirs(_native_path(target_directory / name), exist_ok=True)
        for name in files:
            path = current_path / name
            if _is_reparse(path):
                raise ContractError("Submission bundles may not contain symlinks or reparse points")
            shutil.copy2(_native_path(path), _native_path(target_directory / name))


def _make_bundle_writable(root: Path) -> int:
    root = root.resolve()
    if not root.is_dir() or _is_reparse(root):
        raise ContractError("Runtime bundle root is missing or is a reparse point")

    files: list[Path] = []
    for current, directories, names in os.walk(
        _native_path(root), topdown=True, followlinks=False
    ):
        current_path = _logical_path(current)
        try:
            current_path.relative_to(root)
        except ValueError as exc:
            raise ContractError("Runtime bundle walk escaped its root") from exc
        for name in [*directories, *names]:
            path = current_path / name
            try:
                path.relative_to(root)
            except ValueError as exc:
                raise ContractError("Runtime bundle walk escaped its root") from exc
            if _is_reparse(path):
                raise ContractError("Runtime bundles may not contain reparse points")
        files.extend(current_path / name for name in names)

    for path in files:
        native = _native_path(path)
        info = os.stat(native)
        os.chmod(native, info.st_mode | stat.S_IWRITE)
    return len(files)


def seal_submission(
    submission_root: Path,
    *,
    required_model_file: str,
    closure_root: Path,
    task_id: str,
    generation_run_id: str,
) -> dict[str, Any]:
    source = submission_root.resolve()
    candidate = source / required_model_file
    if not candidate.is_file() or _is_reparse(candidate):
        raise ContractError(f"Required candidate model is missing: {required_model_file}")
    before = snapshot_bundle(source)
    closure_root.mkdir(parents=True, exist_ok=False)
    sealed_root = closure_root / "submission"
    _copy_bundle(source, sealed_root)
    after = snapshot_bundle(sealed_root)
    if before.files != after.files or not bundles_match(source, sealed_root):
        raise ContractError("Sealed submission does not match the collected candidate bundle")
    sealed_candidate = sealed_root / required_model_file
    receipt = {
        "schema": "simuverity.candidate-closure.v1",
        "status": "CANDIDATE_CLOSURE_PASSED",
        "task_id": task_id,
        "generation_run_id": generation_run_id,
        "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "required_model_file": required_model_file,
        "file_count": len(after.files),
        "files": list(after.files),
        "source_modified": False,
        "reparse_points_allowed": False,
    }
    write_json_exclusive(closure_root / "candidate_closure_receipt.json", receipt)
    for row in after.files:
        path = sealed_root / row["relative_path"]
        try:
            native = _native_path(path)
            info = os.stat(native)
            os.chmod(native, info.st_mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
        except OSError:
            pass
    return {**receipt, "sealed_submission": str(sealed_root), "sealed_candidate": str(sealed_candidate)}
