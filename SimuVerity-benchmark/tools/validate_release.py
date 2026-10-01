#!/usr/bin/env python3
"""Static release gate for the public SimuVerity benchmark repository."""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path, PureWindowsPath
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT / "tools"))

from simuverity.errors import ContractError  # noqa: E402
from simuverity.repository import TaskRepository  # noqa: E402
from validate_system_profiles import validate_profiles  # noqa: E402


RELEASE = "simuverity-101-v1"
EXPECTED_COLLECTIONS = {'XELEC': 9, 'XAERO': 10, 'XAUTO': 11, 'XBATT': 10, 'XCOMM': 9, 'XFLUID': 11, 'XMECH': 11, 'XMED': 9, 'XROBO': 10, 'XTHERM': 11}
EXPECTED_MATERIALIZATIONS = {"bundled": 68, "local_importer": 33}
TEXT_SUFFIXES = {
    ".cfg", ".csv", ".html", ".ini", ".json", ".m", ".md", ".ps1",
    ".py", ".toml", ".txt", ".xml", ".yaml", ".yml",
}
ARCHIVE_SUFFIXES = {".slx", ".mlproj", ".zip"}
GENERATED_PARTS = {"__pycache__", ".pytest_cache", ".simuverity", "slprj"}
GENERATED_SUFFIXES = {".pyc", ".slxc", ".mexw64"}
OLD_BRANDS = ("simu" + "linkbench", "simu" + "bench")
IDENTITY_TERMS = ("sha" + "256", "check" + "sum", "di" + "gest", "finger" + "print")
LEGACY_ENVIRONMENT_NAMES = (
    "formal" + "90_mcp_port",
    "formal" + "90_matlab_lane",
    "formal" + "90_workspace",
    "formal" + "90_run_root",
    "formal" + "90_trial_id",
)
BARE_XMED10_ENV = re.compile(rb"(?<!simuverity_)f90_" + rb"xmed10_python_exe")
LEGACY_MATLAB_ERROR_NAMESPACE = re.compile(
    rb"[\"'](?:F90|Formal90|UnifiedD16|D16UnifiedTaskDispatch|EXT|"
    rb"V4TaskDispatch|V4TaskPrepare|V4GraphQuery|V4Graph|D021|D023|"
    rb"D019V5|XAERO02|XAERO07|XAERO11|XAUTO11|P9|XP9|D16|"
    rb"f90_[A-Za-z0-9_]+):"
)
PRIVATE_FRAGMENTS = (
    "docs/" + "audit/", "_" + "work/", "final_" + "receipt", "paper_" + "result",
    "internal_" + "testable", "blocked_" + "for_v0",
)
LOCAL_PATH_PATTERNS = (
    re.compile(
        rb"(?i)(?<![A-Za-z0-9])[A-Z]:[\\/](?:users[\\/][^\\/\s]+|claude[_-]?code)(?:[\\/]|$)"
    ),
    re.compile(rb"(?i)(?<![A-Za-z0-9])/(?:home|users)/[^/\s]+(?:/|$)"),
)
FIRST_PARTY_IDENTITY_PATTERNS = (
    re.compile(rb"sha" + rb"-?256", re.IGNORECASE),
    re.compile(rb"check" + rb"\s*sum", re.IGNORECASE),
    re.compile(rb"di" + rb"gest", re.IGNORECASE),
    re.compile(rb"finger" + rb"print", re.IGNORECASE),
    re.compile(rb"\bha" + rb"sh(?:es|ed|ing)?\b", re.IGNORECASE),
)
SIMULINK_FORMAT_IDENTITY_EXCEPTIONS = {
    "tasks/xbatt-09/reference/transform_core.m",
}
SECRET_PATTERNS = (
    re.compile(rb"(?<![A-Za-z0-9])sk-(?:ant-)?[A-Za-z0-9_-]{32,}"),
    re.compile(rb"Bearer\s+[A-Za-z0-9._~+/-]{32,}"),
    re.compile(rb"AKIA[0-9A-Z]{16}"),
)
LIFECYCLE_FRAGMENTS = (
    "paper_" + "grade_os_isolation_claimed",
    "final_" + "frozen_policy_reference_replay",
    "current_" + "frozen_policy_reference",
    "internal-v0-" + "frozen",
    "frozen release " + "closure",
    "frozen " + "scorer",
    "internal reference " + "after",
    "nonofficial " + "eliminations",
    "task" + "ized",
    "proposed_" + "not_current",
    "policy_" + "provisional",
    "not_a_" + "replay",
    "current_after_real_reference_" + "calibration",
    "strict_" + "calibration_visible",
    "scoring_change_" + "metadata",
    "source_post_" + "total_",
    "unchanged_" + "from_v",
    "historical_reference_" + "release_blocker_codes",
    "historical_" + "candidate_only",
    "historical_structure_" + "audit_file_presence",
    "static_ready_" + "source_bound",
    "ready_unmodified_" + "official_copy",
    "ready_task_specific_" + "public_io_wrapper",
    "source_bound_" + "compatibility_copy",
)
EVALUATOR_PATH_VERSION = re.compile(r"(?i)(?:_|-)v[0-9]+(?=$|[_.-])")
EVALUATOR_SYMBOL_VERSION = (
    re.compile(r"(?i)(?:^|[_-])v[0-9]+(?:[_-]|$)"),
    re.compile(r"(?i)_v[0-9]+\b"),
    re.compile(r"\bV[0-9]+\b"),
    re.compile(r'''(?i)["'][^"'\r\n]{0,120}-v[0-9]+\b'''),
    re.compile(
        r"(?i)\b(?:apply|policy|schema|scorer|extractor|criteria|adapter|"
        r"compatibility|contract|revision|entrypoint|recompute)\b[^\r\n]{0,24}\bv[0-9]+\b"
    ),
)
PUBLIC_VERSION_TOKEN = re.compile(
    r"(?i)(?:simuverity-101-v1|simuverity\.[a-z0-9._-]+\.v1)"
)
MATLAB_FILE_FORMAT_TOKEN = re.compile(r"(?i)-v7(?:\.3)?")


def _is_first_party_evaluator(relative: Path) -> bool:
    parts = tuple(part.casefold() for part in relative.parts)
    if len(parts) >= 3 and parts[:2] == ("src", "simuverity"):
        return parts[2] in {
            "assets",
            "candidate_closure",
            "evaluation",
            "orchestrator",
            "runtime",
        }
    if len(parts) < 3 or parts[0] != "tasks":
        return False
    role = parts[2]
    if role in {
        "task.json",
        "official_scenarios.json",
        "scorer.py",
        "scorer",
        "extractor",
        "vendor",
    }:
        return True
    return role == "reference" and len(parts) >= 4 and parts[3] != "files"


def _evaluator_version_match(relative: Path, payload: bytes) -> str | None:
    label = relative.as_posix()
    if EVALUATOR_PATH_VERSION.search(label):
        return "path"
    if relative.suffix.casefold() not in TEXT_SUFFIXES:
        return None
    try:
        text = payload.decode("utf-8-sig")
    except UnicodeDecodeError:
        return None
    text = PUBLIC_VERSION_TOKEN.sub("", text)
    text = MATLAB_FILE_FORMAT_TOKEN.sub("", text)
    text = re.sub(
        r'''(?i)reference[\\/]files[\\/][^"'\s,}\]]+''', "", text
    )
    # These names are fixed block identities inside unchanged D reference
    # models.  They are not evaluator implementation revisions.
    if len(relative.parts) >= 2 and relative.parts[1].startswith("XELEC-"):
        text = re.sub(r"__v4_[A-Za-z0-9_./-]+", "", text)
    if len(relative.parts) >= 2 and relative.parts[1] == "XBATT-06":
        text = text.replace("BatteryEstim3RC_PTBS_EQ_RUL_v1", "")
        text = re.sub(r'''(["'])V1\1''', "", text)
    if len(relative.parts) >= 2 and relative.parts[1] == "XMED-05":
        text = text.replace("PACER_v0.2.0", "")
    for pattern in EVALUATOR_SYMBOL_VERSION:
        if pattern.search(text):
            return "content"
    return None


def _inside(root: Path, value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    path = Path(value.replace("\\", "/"))
    if path.is_absolute() or PureWindowsPath(value).is_absolute() or ":" in value or ".." in path.parts:
        return False
    try:
        (root / path).resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return True


def _json_identity_fields(value: Any, path: str = "") -> Iterable[str]:
    if isinstance(value, dict):
        for key, item in value.items():
            child = f"{path}.{key}" if path else key
            lowered = key.casefold()
            if any(term in lowered for term in IDENTITY_TERMS):
                yield child
            if lowered in {"paper_" + "result", "source_id", "experiment_id"}:
                yield child
            if "trial" in lowered or (
                lowered.endswith("evaluation_" + "id")
                and not lowered.endswith("evaluation_policy_id")
            ):
                yield child
            yield from _json_identity_fields(item, child)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _json_identity_fields(item, f"{path}[{index}]")


def _direct_policy_id_values(value: Any, path: str = "") -> Iterable[tuple[str, Any]]:
    """Yield evaluator policy identities embedded in a task contract payload."""

    if isinstance(value, dict):
        for key, item in value.items():
            child = f"{path}.{key}" if path else key
            if key in {"policy_id", "evaluation_policy_id", "score_policy_id"}:
                yield child, item
            yield from _direct_policy_id_values(item, child)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _direct_policy_id_values(item, f"{path}[{index}]")


def _is_upstream_payload(relative: Path) -> bool:
    parts = tuple(part.casefold() for part in relative.parts)
    if parts[:3] == ("licenses", "third_party", "texts"):
        return True
    return len(parts) >= 4 and parts[0] == "tasks" and parts[2:4] == ("reference", "files")


def _scan_bytes(data: bytes, failures: list[str], label: str) -> None:
    lowered = data.lower()
    for brand in OLD_BRANDS:
        if brand.encode() in lowered:
            failures.append(f"old project name in {label}")
    for fragment in PRIVATE_FRAGMENTS:
        if fragment.encode() in lowered:
            failures.append(f"private workflow or local path in {label}")
    for pattern in LOCAL_PATH_PATTERNS:
        if pattern.search(data):
            failures.append(f"private workflow or local path in {label}")
            break
    for name in LEGACY_ENVIRONMENT_NAMES:
        if name.encode() in lowered:
            failures.append(f"legacy first-party environment name in {label}")
    if BARE_XMED10_ENV.search(lowered):
        failures.append(f"legacy first-party environment name in {label}")
    if b"172." + b"22.11.2" in data:
        failures.append(f"private network address in {label}")
    for pattern in SECRET_PATTERNS:
        if pattern.search(data):
            if pattern.pattern.startswith(b"AKIA") and label.casefold().endswith("simulink/windowsinfo.xml"):
                continue
            failures.append(f"credential-like token in {label}")
            break


def _scan_first_party_identity_terms(
    data: bytes, failures: list[str], label: str
) -> None:
    if any(pattern.search(data) for pattern in FIRST_PARTY_IDENTITY_PATTERNS):
        failures.append(f"first-party identity term in {label}")


def _scan_lifecycle(data: bytes, failures: list[str], label: str) -> None:
    lowered = data.lower()
    if label.casefold().endswith("/official_scenarios.json") and any(
        token in lowered for token in (b"internal-" + b"v0", b"fro" + b"zen")
    ):
        failures.append(f"private lifecycle wording in {label}")
        return
    for fragment in LIFECYCLE_FRAGMENTS:
        if fragment.encode() in lowered:
            failures.append(f"private lifecycle wording in {label}")
            return


def _scan_matlab_error_identifiers(
    data: bytes, failures: list[str], label: str
) -> None:
    if LEGACY_MATLAB_ERROR_NAMESPACE.search(data):
        failures.append(f"legacy first-party MATLAB error identifier in {label}")


def _validate_reference(task: Any, manifest: dict[str, Any], failures: list[str]) -> None:
    task_id = task.task_id
    reference = manifest.get("reference")
    if not isinstance(reference, dict):
        failures.append(f"{task_id}: reference contract is missing")
        return
    mode = reference.get("materialization")
    entrypoint = reference.get("entrypoint")
    if mode not in EXPECTED_MATERIALIZATIONS or not _inside(task.root, entrypoint):
        failures.append(f"{task_id}: invalid reference materialization or entrypoint")
        return
    runtime_name = reference.get("runtime_manifest")
    if not _inside(task.root, runtime_name):
        failures.append(f"{task_id}: invalid reference runtime manifest path")
        return
    runtime_path = task.root / runtime_name
    try:
        runtime = json.loads(runtime_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        failures.append(f"{task_id}: cannot read reference runtime manifest: {exc}")
        return
    if runtime.get("schema") != "simuverity.reference-runtime-manifest.v1" or runtime.get("task_id") != task_id:
        failures.append(f"{task_id}: reference runtime identity differs")
    if runtime.get("materialization") != mode or runtime.get("entrypoint") != entrypoint:
        failures.append(f"{task_id}: reference bindings differ")
    if mode == "bundled":
        model = task.root / entrypoint
        if not model.is_file():
            failures.append(f"{task_id}: bundled reference entrypoint is missing")
        inventory_name = reference.get("manifest")
        if not _inside(task.root, inventory_name):
            failures.append(f"{task_id}: bundled reference inventory path is invalid")
        else:
            inventory_path = task.root / inventory_name
            try:
                inventory = json.loads(inventory_path.read_text(encoding="utf-8-sig"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                failures.append(f"{task_id}: cannot read bundled reference inventory: {exc}")
            else:
                rows = inventory.get("files")
                if not isinstance(rows, list) or inventory.get("file_count") != len(rows):
                    failures.append(f"{task_id}: bundled reference inventory count differs")
                else:
                    total = 0
                    for row in rows:
                        if not isinstance(row, dict) or set(row) != {"path", "size_bytes"}:
                            failures.append(f"{task_id}: bundled reference inventory row is invalid")
                            continue
                        path_value = row.get("path")
                        size = row.get("size_bytes")
                        if not _inside(task.root, path_value) or not isinstance(size, int) or isinstance(size, bool) or size < 0:
                            failures.append(f"{task_id}: bundled reference inventory row is unsafe")
                            continue
                        file_path = task.root / path_value
                        if not file_path.is_file() or file_path.stat().st_size != size:
                            failures.append(f"{task_id}: bundled reference inventory size differs for {path_value}")
                        total += size
                    if inventory.get("total_bytes") != total:
                        failures.append(f"{task_id}: bundled reference total bytes differ")
    else:
        for key in ("recipe", "transform"):
            value = runtime.get(key)
            if not _inside(task.root, value) or not (task.root / value).is_file():
                failures.append(f"{task_id}: importer {key} is missing")
    score = reference.get("expected_score")
    if not isinstance(score, (int, float)) or isinstance(score, bool) or not 90 <= score <= 100:
        failures.append(f"{task_id}: reference score must be between 90 and 100")
    count = reference.get("expected_valid_scenarios")
    if not isinstance(count, int) or isinstance(count, bool) or count < 1:
        failures.append(f"{task_id}: expected valid-scenario count is invalid")


def _validate_code_manifests(
    task: Any, task_manifest: dict[str, Any], failures: list[str]
) -> None:
    task_id = task.task_id
    extractor_binding = task_manifest.get("extractor", {})
    extractor_path = task.root / "extractor" / "manifest.json"
    try:
        extractor = json.loads(extractor_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        failures.append(f"{task_id}: cannot read extractor manifest: {exc}")
    else:
        if (
            extractor.get("schema") != "simuverity.extractor-closure.v1"
            or extractor.get("task_id") != task_id
            or extractor.get("entrypoint") != extractor_binding.get("implementation")
            or extractor.get("public_wrapper") != extractor_binding.get("path")
        ):
            failures.append(f"{task_id}: extractor manifest binding differs")
        rows = extractor.get("files")
        declared: set[str] = set()
        if not isinstance(rows, list) or not rows:
            failures.append(f"{task_id}: extractor manifest has no dependency rows")
        else:
            for row in rows:
                if not isinstance(row, dict) or set(row) != {"source_name", "public_path"}:
                    failures.append(f"{task_id}: extractor manifest row is invalid")
                    continue
                value = row.get("public_path")
                if (
                    row.get("source_name") != Path(str(value)).name
                    or not _inside(task.root, value)
                    or not (task.root / str(value)).is_file()
                    or value in declared
                ):
                    failures.append(f"{task_id}: extractor dependency is invalid: {value}")
                    continue
                declared.add(value)
        required = {extractor_binding.get("implementation")}
        required.update(
            item.get("path")
            for item in extractor_binding.get("sidecars", [])
            if isinstance(item, dict)
        )
        if None in required or not required.issubset(declared):
            failures.append(f"{task_id}: extractor manifest omits a current entrypoint")

    scorer_path = task.root / "scorer" / "manifest.json"
    try:
        scorer = json.loads(scorer_path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        failures.append(f"{task_id}: cannot read scorer manifest: {exc}")
        return
    schema = scorer.get("schema")
    if (
        schema != "simuverity.scorer-manifest.v1"
        or scorer.get("task_id") != task_id
        or scorer.get("public_interface") != "scorer.py:score"
        or scorer.get("implementation") != "scorer.py"
    ):
        failures.append(f"{task_id}: scorer manifest binding differs")
    rows = [*scorer.get("source_modules", []), *scorer.get("payload_files", [])]
    final = scorer.get("final_module")
    if isinstance(final, dict):
        rows.append(final)
    else:
        failures.append(f"{task_id}: scorer final module is missing")
    for row in rows:
        if not isinstance(row, dict):
            failures.append(f"{task_id}: scorer dependency row is invalid")
            continue
        value = row.get("path") or row.get("public_path")
        if not _inside(task.root, value) or not (task.root / str(value)).is_file():
            failures.append(f"{task_id}: scorer dependency is missing: {value}")


def validate_release(root: Path) -> dict[str, Any]:
    root = root.resolve()
    failures: list[str] = []
    try:
        profile_report = validate_profiles(root)
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        profile_report = {"status": "ERROR", "task_count": 0, "failures": [f"{type(exc).__name__}: {exc}"]}
    if profile_report.get("status") != "PASS":
        reasons = profile_report.get("failures")
        failures.extend(f"system profile: {reason}" for reason in reasons if isinstance(reason, str))
        if not reasons:
            failures.append("system profile validation failed")

    repository = TaskRepository(root)
    try:
        task_ids = repository.task_ids()
    except ContractError as exc:
        task_ids = []
        failures.append(f"task repository is invalid: {exc}")
    collections: Counter[str] = Counter()
    materializations: Counter[str] = Counter()
    license_statuses: Counter[str] = Counter()
    policies: list[str] = []
    ordinals: list[int] = []
    for task_id in task_ids:
        try:
            task = repository.get(task_id)
        except ContractError as exc:
            failures.append(f"{task_id}: task contract is invalid: {exc}")
            continue
        manifest = json.loads(task.manifest_path.read_text(encoding="utf-8-sig"))
        collections[task.collection] += 1
        materializations[str(task.reference.get("materialization"))] += 1
        license_statuses[str(manifest.get("release_license_status"))] += 1
        policies.append(task.evaluation_policy_id)
        ordinal = manifest.get("ordinal")
        if isinstance(ordinal, int) and not isinstance(ordinal, bool):
            ordinals.append(ordinal)
        else:
            failures.append(f"{task_id}: ordinal is invalid")
        expected_policy = f"{RELEASE}:{task_id.casefold()}:scoring"
        if task.evaluation_policy_id != expected_policy:
            failures.append(f"{task_id}: evaluation policy identity differs")
        for field in ("public_spec", "official_scenarios"):
            value = manifest.get(field)
            if not _inside(task.root, value) or not (task.root / value).is_file():
                failures.append(f"{task_id}: invalid {field} path")
        scenarios_path = task.root / str(manifest.get("official_scenarios", ""))
        if scenarios_path.is_file():
            try:
                scenarios = json.loads(scenarios_path.read_text(encoding="utf-8-sig"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                scenarios = None
            if scenarios is not None:
                for field_path, value in _direct_policy_id_values(scenarios):
                    if value != expected_policy:
                        failures.append(
                            f"{task_id}: official scenario policy identity differs at {field_path}"
                        )
        scorer_files = [
            path for path in task.root.rglob("scorer.py")
            if "reference" not in {part.casefold() for part in path.relative_to(task.root).parts}
        ]
        if scorer_files != [task.root / "scorer.py"]:
            failures.append(f"{task_id}: expected exactly one public scorer.py")
        _validate_reference(task, manifest, failures)
        _validate_code_manifests(task, manifest, failures)

    if len(task_ids) != 101:
        failures.append(f"task count is {len(task_ids)}, expected 101")
    if dict(collections) != EXPECTED_COLLECTIONS:
        failures.append(f"collection counts differ: {dict(collections)}")
    if dict(materializations) != EXPECTED_MATERIALIZATIONS:
        failures.append(f"reference materializations differ: {dict(materializations)}")
    if len(policies) != len(set(policies)):
        failures.append("evaluation policy identities must be unique")
    if sorted(ordinals) != list(range(1, 102)):
        failures.append("task ordinals must be exactly 1 through 101")

    all_files = [path for path in root.rglob("*") if path.is_file()]
    for path in all_files:
        relative = path.relative_to(root)
        label = relative.as_posix()
        lower_label = label.casefold()
        attributes = getattr(path.stat(), "st_file_attributes", 0)
        if path.is_symlink() or attributes & 0x400:
            failures.append(f"link or reparse point is forbidden: {label}")
        if path.stat().st_size > 100 * 1024 * 1024:
            failures.append(f"ordinary file exceeds 100 MiB: {label}")
        if any(part.casefold() in GENERATED_PARTS for part in relative.parts) or path.suffix.casefold() in GENERATED_SUFFIXES or lower_label.endswith(".egg-info"):
            failures.append(f"generated cache is forbidden: {label}")
        if any(brand in lower_label for brand in OLD_BRANDS):
            failures.append(f"old project name in path: {label}")
        if any(term in lower_label for term in IDENTITY_TERMS) or re.fullmatch(r"[0-9a-f]{32,}\.[a-z0-9.]+", path.name.casefold()):
            failures.append(f"identity-derived filename is forbidden: {label}")
        if re.fullmatch(r"cand_.*\.(?:slx|mdl)", path.name.casefold()):
            failures.append(f"candidate artifact is forbidden: {label}")
        if path.name.casefold() in {"evidence.json", "evidence_" + "lock.json", "auth.json", ".credentials.json"}:
            failures.append(f"runtime artifact is forbidden: {label}")
        if path.suffix.casefold() == ".ndjson":
            failures.append(f"agent trace is forbidden: {label}")
        if _is_first_party_evaluator(relative) and EVALUATOR_PATH_VERSION.search(label):
            failures.append(f"internal evaluator revision in path: {label}")

        if path.suffix.casefold() == ".json" and not _is_upstream_payload(relative):
            try:
                payload = json.loads(path.read_text(encoding="utf-8-sig"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                failures.append(f"invalid public JSON {label}: {exc}")
            else:
                identities = list(_json_identity_fields(payload))
                if identities:
                    failures.append(f"private or identity-derived fields in {label}: {', '.join(identities)}")
        if path.suffix.casefold() in TEXT_SUFFIXES and path.stat().st_size <= 20 * 1024 * 1024:
            data = path.read_bytes()
            _scan_bytes(data, failures, label)
            if _is_first_party_evaluator(relative):
                issue = _evaluator_version_match(relative, data)
                if issue == "content":
                    failures.append(f"internal evaluator revision in content: {label}")
            if not _is_upstream_payload(relative):
                if path.suffix.casefold() == ".m":
                    _scan_matlab_error_identifiers(data, failures, label)
                if lower_label not in SIMULINK_FORMAT_IDENTITY_EXCEPTIONS:
                    _scan_first_party_identity_terms(data, failures, label)
                _scan_lifecycle(data, failures, label)
        if path.suffix.casefold() in ARCHIVE_SUFFIXES:
            try:
                with zipfile.ZipFile(path) as archive:
                    for info in archive.infolist():
                        if info.file_size > 20 * 1024 * 1024:
                            continue
                        try:
                            _scan_bytes(archive.read(info), failures, f"{label}!/{info.filename}")
                        except Exception:
                            continue
            except zipfile.BadZipFile:
                pass

    return {
        "schema": "simuverity.public-release-validation.v1",
        "status": "PASS" if not failures else "FAIL",
        "release": RELEASE,
        "task_count": len(task_ids),
        "collection_counts": dict(collections),
        "reference_materializations": dict(materializations),
        "system_profiles": profile_report,
        "license_statuses": dict(license_statuses),
        "file_count": len(all_files),
        "failures": sorted(set(failures)),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    report = validate_release(args.repo)
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8", newline="\n")
    print(rendered, end="")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
