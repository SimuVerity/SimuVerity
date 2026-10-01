from __future__ import annotations

import re
import shutil
import stat
from datetime import datetime, timezone
from pathlib import Path, PureWindowsPath
from typing import Any, Mapping

from ..errors import ContractError
from ..jsonutil import load_json, write_json_exclusive


SIDECAR_ROLE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
CLOSURE_MANIFEST_NAME = "evidence_closure_manifest.json"
SCENARIOS_COPY_NAME = "official_scenarios.json"


def _artifact_relative(value: Any) -> Path:
    if (
        not isinstance(value, str)
        or not value
        or Path(value).is_absolute()
        or PureWindowsPath(value).is_absolute()
        or ":" in value
    ):
        raise ContractError("Evidence closure contains an unsafe artifact path")
    normalized = Path(value.replace("\\", "/"))
    if normalized.as_posix() != value.replace("\\", "/") or any(
        part in {"", ".", ".."} for part in normalized.parts
    ):
        raise ContractError("Evidence closure contains an unsafe artifact path")
    if normalized.name in {
        "evidence.json",
        "evidence_manifest.json",
        CLOSURE_MANIFEST_NAME,
        SCENARIOS_COPY_NAME,
    }:
        raise ContractError("Evidence closure uses a reserved artifact path")
    return normalized


def _assert_plain_file_below(root: Path, path: Path) -> None:
    root = root.resolve()
    resolved = path.resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ContractError("Evidence artifact escaped its closure root") from exc
    current = path
    while current != root:
        try:
            attributes = current.lstat().st_file_attributes
        except AttributeError:
            attributes = 0
        if current.is_symlink() or attributes & getattr(
            stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400
        ):
            raise ContractError("Evidence closure may not contain links or reparse points")
        current = current.parent
    if not path.is_file():
        raise ContractError("Evidence closure artifact is missing")


def _valid_size(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _load_closure_manifest(
    evidence_source: Path, task_id: str
) -> tuple[Path, dict[str, Any]] | None:
    path = evidence_source.parent / CLOSURE_MANIFEST_NAME
    if not path.exists():
        return None
    value = load_json(path)
    if (
        not isinstance(value, dict)
        or value.get("schema") != "simuverity.evidence-closure-manifest.v1"
        or value.get("task_id") != task_id
        or value.get("evidence_file") != "evidence.json"
        or not isinstance(value.get("files"), list)
    ):
        raise ContractError("Extractor evidence closure manifest is invalid")
    return path, value


def create_evidence_bundle(
    evidence_source: Path,
    *,
    bundle_root: Path,
    task_id: str,
    generation_run_id: str,
    scoring_run_id: str,
    candidate_file: str,
    scenarios_source: Path,
    evaluation_policy_id: str,
    evaluation_subject: str = "candidate",
    sidecars: Mapping[str, Mapping[str, Any] | Path] | None = None,
) -> Path:
    if not evidence_source.is_file():
        raise ContractError("Extractor did not produce evidence.json")
    try:
        evidence = load_json(evidence_source)
    except Exception as exc:
        raise ContractError(f"Extractor evidence is not valid JSON: {exc}") from exc
    if not isinstance(evidence, dict):
        raise ContractError("Extractor evidence must be a JSON object")
    if not scenarios_source.is_file() or not isinstance(load_json(scenarios_source), dict):
        raise ContractError("Official scenario contract is missing or invalid")
    if evaluation_subject not in {"candidate", "reference"}:
        raise ContractError("Evidence bundle subject must be candidate or reference")
    if Path(candidate_file).name != candidate_file:
        raise ContractError("Candidate model identity must be a filename")

    bundle_root.mkdir(parents=True, exist_ok=False)
    evidence_copy = bundle_root / "evidence.json"
    scenario_copy = bundle_root / SCENARIOS_COPY_NAME
    shutil.copy2(evidence_source, evidence_copy)
    shutil.copy2(scenarios_source, scenario_copy)

    closure = _load_closure_manifest(evidence_source, task_id)
    artifact_rows: list[dict[str, Any]] = []
    evidence_artifacts: list[Path] = []
    closure_manifest_copy: Path | None = None
    if closure is not None:
        closure_path, closure_value = closure
        seen: set[str] = set()
        for item in closure_value["files"]:
            if not isinstance(item, Mapping):
                raise ContractError("Evidence closure artifact row is invalid")
            relative = _artifact_relative(item.get("path"))
            relative_text = relative.as_posix()
            expected_size = item.get("size_bytes")
            if relative_text in seen or not _valid_size(expected_size):
                raise ContractError("Evidence closure artifact identity is invalid")
            seen.add(relative_text)
            source = evidence_source.parent / relative
            _assert_plain_file_below(evidence_source.parent, source)
            if source.stat().st_size != expected_size:
                raise ContractError("Evidence closure artifact size differs from its manifest")
            target = bundle_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            if target.stat().st_size != expected_size or target.read_bytes() != source.read_bytes():
                raise ContractError("Evidence artifact copy differs")
            artifact_rows.append({"file": relative_text, "size_bytes": expected_size})
            evidence_artifacts.append(target)
        closure_manifest_copy = bundle_root / CLOSURE_MANIFEST_NAME
        shutil.copy2(closure_path, closure_manifest_copy)

    sidecar_rows: list[dict[str, Any]] = []
    evidence_sidecars: list[Path] = []
    if sidecars:
        sidecar_root = bundle_root / "sidecars"
        sidecar_root.mkdir()
        for role, item in sorted(sidecars.items()):
            if not isinstance(role, str) or not SIDECAR_ROLE_RE.fullmatch(role):
                raise ContractError(f"Invalid evidence sidecar role: {role!r}")
            descriptor = dict(item) if isinstance(item, Mapping) else {"path": item}
            source = Path(descriptor.get("path", ""))
            if not source.is_file():
                raise ContractError(f"Evidence sidecar is missing: {role}")
            expected_schema = descriptor.get("schema")
            try:
                sidecar_value = load_json(source)
            except Exception as exc:
                raise ContractError(f"Evidence sidecar is not valid JSON ({role}): {exc}") from exc
            if not isinstance(sidecar_value, Mapping):
                raise ContractError(f"Evidence sidecar must be a JSON object: {role}")
            if expected_schema and sidecar_value.get("schema") != expected_schema:
                raise ContractError(f"Evidence sidecar schema mismatch: {role}")
            target = sidecar_root / f"{role}.json"
            shutil.copy2(source, target)
            if target.read_bytes() != source.read_bytes():
                raise ContractError(f"Evidence sidecar copy differs: {role}")
            evidence_sidecars.append(target)
            row: dict[str, Any] = {
                "role": role,
                "file": f"sidecars/{role}.json",
                "size_bytes": target.stat().st_size,
                "media_type": "application/json",
            }
            if expected_schema:
                row["schema"] = expected_schema
            sidecar_rows.append(row)

    receipt: dict[str, Any] = {
        "schema": "simuverity.evidence-bundle.v1",
        "evidence_complete": True,
        "task_id": task_id,
        "generation_run_id": generation_run_id,
        "scoring_run_id": scoring_run_id,
        "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "candidate_file": candidate_file,
        "evidence_file": "evidence.json",
        "evidence_size_bytes": evidence_copy.stat().st_size,
        "official_scenarios_file": SCENARIOS_COPY_NAME,
        "evaluation_policy_id_at_extraction": evaluation_policy_id,
        "evaluation_subject": evaluation_subject,
    }
    if sidecar_rows:
        receipt["sidecars"] = sidecar_rows
    if closure is not None:
        receipt["evidence_closure_manifest_file"] = CLOSURE_MANIFEST_NAME
        receipt["artifacts"] = artifact_rows
    bundle_path = bundle_root / "evidence_manifest.json"
    write_json_exclusive(bundle_path, receipt)

    for path in [
        evidence_copy,
        scenario_copy,
        *evidence_sidecars,
        *evidence_artifacts,
        *([closure_manifest_copy] if closure_manifest_copy is not None else []),
    ]:
        try:
            path.chmod(path.stat().st_mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
        except OSError:
            pass
    return bundle_path


def resolve_evidence_sidecars(bundle_path: Path, bundle: Mapping[str, Any]) -> dict[str, Path]:
    schema = bundle.get("schema")
    if schema != "simuverity.evidence-bundle.v1":
        raise ContractError("Unsupported evidence bundle sidecar schema")
    rows = bundle.get("sidecars", [])
    if not isinstance(rows, list):
        raise ContractError("Evidence bundle sidecars must be an array")
    resolved: dict[str, Path] = {}
    for item in rows:
        if not isinstance(item, Mapping):
            raise ContractError("Evidence bundle sidecar entry is invalid")
        role = item.get("role")
        relative = item.get("file")
        size = item.get("size_bytes")
        if (
            not isinstance(role, str)
            or not SIDECAR_ROLE_RE.fullmatch(role)
            or role in resolved
            or not isinstance(relative, str)
            or Path(relative).as_posix() != f"sidecars/{role}.json"
            or not _valid_size(size)
        ):
            raise ContractError("Evidence bundle contains an unsafe or duplicate sidecar path")
        path = bundle_path.parent / Path(relative)
        _assert_plain_file_below(bundle_path.parent, path)
        if path.stat().st_size != size:
            raise ContractError(f"Evidence sidecar size differs: {role}")
        expected_schema = item.get("schema")
        if expected_schema:
            value = load_json(path)
            if not isinstance(value, Mapping) or value.get("schema") != expected_schema:
                raise ContractError(f"Evidence sidecar schema differs from its bundle: {role}")
        resolved[role] = path
    return resolved


def validate_evidence_artifacts(bundle_path: Path, bundle: Mapping[str, Any]) -> list[Path]:
    schema = bundle.get("schema")
    if schema != "simuverity.evidence-bundle.v1":
        raise ContractError("Unsupported evidence bundle schema")
    has_artifacts = "artifacts" in bundle
    has_manifest = "evidence_closure_manifest_file" in bundle
    if not has_artifacts and not has_manifest:
        return []
    if has_artifacts != has_manifest:
        raise ContractError("Evidence bundle closure binding is incomplete")
    if bundle.get("evidence_closure_manifest_file") != CLOSURE_MANIFEST_NAME:
        raise ContractError("Evidence bundle closure binding is invalid")
    rows = bundle.get("artifacts")
    if not isinstance(rows, list):
        raise ContractError("Evidence bundle artifacts must be an array")
    manifest_path = bundle_path.parent / CLOSURE_MANIFEST_NAME
    _assert_plain_file_below(bundle_path.parent, manifest_path)
    manifest = load_json(manifest_path)
    if (
        not isinstance(manifest, Mapping)
        or manifest.get("schema") != "simuverity.evidence-closure-manifest.v1"
        or manifest.get("task_id") != bundle.get("task_id")
        or manifest.get("evidence_file") != "evidence.json"
        or not isinstance(manifest.get("files"), list)
    ):
        raise ContractError("Evidence closure manifest is invalid")
    manifest_rows = [
        {
            "file": _artifact_relative(item.get("path")).as_posix(),
            "size_bytes": item.get("size_bytes"),
        }
        for item in manifest["files"]
        if isinstance(item, Mapping)
    ]
    if len(manifest_rows) != len(manifest["files"]) or manifest_rows != rows:
        raise ContractError("Evidence bundle artifact rows differ from the closure manifest")
    resolved: list[Path] = []
    seen: set[str] = set()
    for item in rows:
        if not isinstance(item, Mapping):
            raise ContractError("Evidence bundle artifact row is invalid")
        relative = _artifact_relative(item.get("file"))
        relative_text = relative.as_posix()
        expected_size = item.get("size_bytes")
        if relative_text in seen or not _valid_size(expected_size):
            raise ContractError("Evidence bundle artifact identity is invalid")
        seen.add(relative_text)
        path = bundle_path.parent / relative
        _assert_plain_file_below(bundle_path.parent, path)
        if path.stat().st_size != expected_size:
            raise ContractError("Evidence artifact size differs")
        resolved.append(path)
    return resolved


def validate_evidence_bundle(
    bundle_path: Path, *, task_id: str, scenarios_path: Path
) -> tuple[dict[str, Any], Path]:
    bundle_path = bundle_path.resolve()
    value = load_json(bundle_path)
    if (
        not isinstance(value, dict)
        or value.get("schema") != "simuverity.evidence-bundle.v1"
    ):
        raise ContractError("Unsupported evidence bundle schema")
    if value.get("evidence_complete") is not True or value.get("task_id") != task_id:
        raise ContractError("Evidence bundle does not belong to this task")
    if value.get("evaluation_subject", "candidate") not in {"candidate", "reference"}:
        raise ContractError("Evidence bundle subject is invalid")
    relative = value.get("evidence_file")
    if not isinstance(relative, str) or Path(relative).name != relative:
        raise ContractError("Evidence bundle contains an unsafe evidence path")
    evidence_path = bundle_path.parent / relative
    _assert_plain_file_below(bundle_path.parent, evidence_path)
    if not _valid_size(value.get("evidence_size_bytes")) or evidence_path.stat().st_size != value[
        "evidence_size_bytes"
    ]:
        raise ContractError("Evidence size differs from its bundle manifest")
    if not isinstance(load_json(evidence_path), dict):
        raise ContractError("Evidence must be a JSON object")
    if value.get("official_scenarios_file") != SCENARIOS_COPY_NAME:
        raise ContractError("Evidence bundle does not contain its official scenario contract")
    scenario_copy = bundle_path.parent / SCENARIOS_COPY_NAME
    _assert_plain_file_below(bundle_path.parent, scenario_copy)
    if load_json(scenario_copy) != load_json(scenarios_path):
        raise ContractError("Official scenario contract differs from the evidence")
    resolve_evidence_sidecars(bundle_path, value)
    validate_evidence_artifacts(bundle_path, value)
    return value, evidence_path
