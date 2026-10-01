#!/usr/bin/env python3
"""Validate all public SimuVerity system profiles using only Python's standard library."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path, PureWindowsPath
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
RELEASE = "simuverity-101-v1"
PROFILE_SCHEMA = "simuverity.system-profile.v1"
BINDINGS_SCHEMA = "simuverity.system-profile-task-bindings.v1"
MANIFEST_SCHEMA = "simuverity.system-profile-manifest.v1"
REPORT_SCHEMA = "simuverity.system-profile-validation.v1"
EXPECTED_COUNTS = {'XELEC': 9, 'XAERO': 10, 'XAUTO': 11, 'XBATT': 10, 'XCOMM': 9, 'XFLUID': 11, 'XMECH': 11, 'XMED': 9, 'XROBO': 10, 'XTHERM': 11}
EXPECTED_MATERIALIZATIONS = {"bundled": 68, "local_importer": 33}

PROFILE_KEYS = {
    "schema", "task_id", "collection", "reference", "runtime",
    "system", "sources", "scope",
}
REFERENCE_KEYS = {"identity_path", "entry_kind", "entrypoint", "model_path"}
RUNTIME_KEYS = {
    "matlab_release", "execution_mode", "command", "runner_path",
    "collection_success",
}
SYSTEM_KEYS = {
    "boundary", "engineering_objects", "physical_paths", "functional_paths",
    "information_paths", "modes_and_events", "interfaces",
    "signs_and_coordinates", "feedback_and_control_causality",
    "signal_sources", "operating_range", "disturbances", "dynamic_processes",
    "task_specific_shortcuts",
}
INTERFACE_KEYS = {"name", "direction", "description", "units", "range_or_shape", "source"}
SOURCE_KEYS = {"role", "path"}
SCOPE = {"system_only": True, "sent_to_agent": False, "used_for_scoring": False}
FORBIDDEN_FRAGMENTS = (
    "d:/" + "claude", "d:\\" + "claude", "c:/" + "users/", "c:\\" + "users\\",
    "docs/" + "audit/", "_" + "work/", "final_" + "receipt",
    "trial" + "id", "evaluation" + "id",
    "internal_" + "testable", "blocked_" + "for_v0", "paper_" + "result",
)
FORBIDDEN_IDENTITY_TERMS = (
    "sha" + "256", "check" + "sum", "di" + "gest", "finger" + "print"
)


def _read_json(path: Path, failures: list[str], label: str) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        failures.append(f"{label}: cannot read JSON: {exc}")
        return None
    if not isinstance(value, dict):
        failures.append(f"{label}: JSON object required")
        return None
    return value


def _relative_path(root: Path, value: Any, failures: list[str], label: str) -> Path | None:
    if not isinstance(value, str) or not value.strip():
        failures.append(f"{label}: non-empty repository-relative path required")
        return None
    path = Path(value.replace("\\", "/"))
    if path.is_absolute() or PureWindowsPath(value).is_absolute() or ":" in value or ".." in path.parts:
        failures.append(f"{label}: unsafe path")
        return None
    target = (root / path).resolve()
    try:
        target.relative_to(root.resolve())
    except ValueError:
        failures.append(f"{label}: path escapes repository")
        return None
    return target


def _strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def _check_public_value(value: Any, failures: list[str], label: str) -> None:
    lowered = "\n".join(_strings(value)).casefold().replace("\\", "/")
    for fragment in FORBIDDEN_FRAGMENTS:
        if fragment.replace("\\", "/") in lowered:
            failures.append(f"{label}: private workflow fragment present: {fragment}")
    for term in FORBIDDEN_IDENTITY_TERMS:
        if term in lowered:
            failures.append(f"{label}: project identity field present: {term}")
    if re.search(r"\b(?:trial|evaluation)[-_]?[0-9a-f]{10,}\b", lowered):
        failures.append(f"{label}: private experiment identifier present")


def _nonempty_strings(value: Any) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(item, str) and item.strip() for item in value)


def _validate_profile_shape(profile: dict[str, Any], failures: list[str], label: str) -> None:
    if set(profile) != PROFILE_KEYS:
        failures.append(f"{label}: profile fields differ from the public schema")
    if profile.get("schema") != PROFILE_SCHEMA:
        failures.append(f"{label}: profile schema identity differs")
    reference = profile.get("reference")
    if not isinstance(reference, dict) or set(reference) != REFERENCE_KEYS:
        failures.append(f"{label}: reference fields differ from the public schema")
    runtime = profile.get("runtime")
    if not isinstance(runtime, dict) or set(runtime) != RUNTIME_KEYS:
        failures.append(f"{label}: runtime fields differ from the public schema")
    system = profile.get("system")
    if not isinstance(system, dict) or set(system) != SYSTEM_KEYS:
        failures.append(f"{label}: system fields differ from the public schema")
        return
    if not isinstance(system.get("boundary"), str) or not system["boundary"].strip():
        failures.append(f"{label}: system boundary is empty")
    for key in SYSTEM_KEYS - {"boundary", "interfaces", "task_specific_shortcuts"}:
        if not _nonempty_strings(system.get(key)):
            failures.append(f"{label}: {key} must be a non-empty string array")
    shortcuts = system.get("task_specific_shortcuts")
    if not _nonempty_strings(shortcuts) or not 1 <= len(shortcuts) <= 2:
        failures.append(f"{label}: one or two task-specific shortcuts required")
    interfaces = system.get("interfaces")
    if not isinstance(interfaces, list) or not interfaces:
        failures.append(f"{label}: at least one interface is required")
    else:
        names: set[str] = set()
        for index, item in enumerate(interfaces):
            item_label = f"{label}.interfaces[{index}]"
            if not isinstance(item, dict) or set(item) != INTERFACE_KEYS:
                failures.append(f"{item_label}: fields differ from the public schema")
                continue
            name = item.get("name")
            if not isinstance(name, str) or not name.strip() or name in names:
                failures.append(f"{item_label}: interface name is empty or duplicated")
            else:
                names.add(name)
            if item.get("direction") not in {"input", "output", "internal"}:
                failures.append(f"{item_label}: invalid direction")
            if not isinstance(item.get("units"), list) or not all(isinstance(unit, str) for unit in item["units"]):
                failures.append(f"{item_label}: units must be a string array")
            for key in ("description", "range_or_shape", "source"):
                if not isinstance(item.get(key), str) or not item[key].strip():
                    failures.append(f"{item_label}: {key} is empty")
    sources = profile.get("sources")
    if not isinstance(sources, list) or not sources:
        failures.append(f"{label}: source bindings are missing")
    else:
        for index, source in enumerate(sources):
            if not isinstance(source, dict) or set(source) != SOURCE_KEYS:
                failures.append(f"{label}.sources[{index}]: fields differ from the public schema")
    if profile.get("scope") != SCOPE:
        failures.append(f"{label}: scope must declare metadata-only use")
    _check_public_value(profile, failures, label)


def _validate_task(
    root: Path,
    task_row: dict[str, Any],
    binding_row: dict[str, Any],
    profile_row: dict[str, Any],
    failures: list[str],
) -> None:
    task_id = task_row.get("task_id")
    label = str(task_id)
    task_path = _relative_path(root, task_row.get("task_manifest"), failures, f"{label}: task manifest")
    profile_path = _relative_path(root, profile_row.get("path"), failures, f"{label}: profile")
    if task_path is None or profile_path is None or not task_path.is_file() or not profile_path.is_file():
        failures.append(f"{label}: task manifest or profile is missing")
        return
    task = _read_json(task_path, failures, f"{label}: task manifest")
    profile = _read_json(profile_path, failures, f"{label}: profile")
    if task is None or profile is None:
        return
    _validate_profile_shape(profile, failures, label)
    collection = task.get("collection")
    if task.get("task_id") != task_id or profile.get("task_id") != task_id:
        failures.append(f"{label}: task identity differs across bindings")
    if profile.get("collection") != collection or task_row.get("collection") != collection:
        failures.append(f"{label}: collection differs across bindings")
    if task.get("release") != RELEASE:
        failures.append(f"{label}: release identity differs")
    profile_binding = task.get("system_profile")
    if profile_binding != {"path": "system_profile.json", "schema": PROFILE_SCHEMA}:
        failures.append(f"{label}: task profile binding differs")
    expected_profile_path = f"tasks/{task_id}/system_profile.json"
    if profile_row != {"task_id": task_id, "collection": collection, "path": expected_profile_path}:
        failures.append(f"{label}: central profile row differs")

    public_spec_path = _relative_path(root, binding_row.get("public_spec"), failures, f"{label}: public spec")
    runtime_path = _relative_path(root, binding_row.get("reference_runtime_manifest"), failures, f"{label}: runtime manifest")
    if public_spec_path is None or runtime_path is None or not public_spec_path.is_file() or not runtime_path.is_file():
        failures.append(f"{label}: public spec or reference runtime manifest is missing")
        return
    public_spec = _read_json(public_spec_path, failures, f"{label}: public spec")
    runtime = _read_json(runtime_path, failures, f"{label}: runtime manifest")
    if public_spec is None or runtime is None:
        return
    prompt = public_spec.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        failures.append(f"{label}: public prompt is missing")
        prompt = ""
    if public_spec.get("task_id") != task_id or public_spec.get("schema") != "simuverity.public-spec.v1":
        failures.append(f"{label}: public spec identity differs")
    if public_spec.get("candidate_filename") != task.get("required_model_file"):
        failures.append(f"{label}: submission filename differs from the task contract")

    reference = profile.get("reference", {})
    expected_identity = f"tasks/{task_id}/reference/runtime_manifest.json"
    if reference.get("identity_path") != expected_identity:
        failures.append(f"{label}: reference identity path differs")
    if reference.get("entry_kind") != "matlab_model":
        failures.append(f"{label}: reference entry kind differs")
    task_reference = task.get("reference", {})
    if runtime.get("schema") != "simuverity.reference-runtime-manifest.v1" or runtime.get("task_id") != task_id:
        failures.append(f"{label}: runtime manifest identity differs")
    for key in ("materialization", "entrypoint"):
        values = {runtime.get(key), task_reference.get(key), binding_row.get(f"reference_{key}")}
        if len(values) != 1:
            failures.append(f"{label}: reference {key} differs across bindings")
    if reference.get("entrypoint") != runtime.get("entrypoint"):
        failures.append(f"{label}: profile reference entrypoint differs")
    materialization = runtime.get("materialization")
    if materialization == "bundled":
        expected_model = f"tasks/{task_id}/{runtime.get('entrypoint')}"
        if reference.get("model_path") != expected_model:
            failures.append(f"{label}: bundled reference model path differs")
        model_path = _relative_path(root, expected_model, failures, f"{label}: bundled reference model")
        if model_path is None or not model_path.is_file():
            failures.append(f"{label}: bundled reference model is missing")
    elif materialization == "local_importer":
        if reference.get("model_path") is not None:
            failures.append(f"{label}: importer profile model_path must be null before import")
        for key in ("recipe", "transform"):
            bound = runtime.get(key)
            path = _relative_path(task_path.parent, bound, failures, f"{label}: importer {key}")
            if path is None or not path.is_file():
                failures.append(f"{label}: importer {key} is missing")
    else:
        failures.append(f"{label}: unsupported reference materialization")

    closure = task.get("candidate_closure", {})
    public_inputs = closure.get("public_input_names") if isinstance(closure, dict) else None
    profile_inputs = [
        item.get("name") for item in profile.get("system", {}).get("interfaces", [])
        if isinstance(item, dict) and item.get("direction") == "input"
    ]
    if profile_inputs != public_inputs:
        failures.append(f"{label}: profile inputs differ from the task contract")
    outputs = [
        item.get("name") for item in profile.get("system", {}).get("interfaces", [])
        if isinstance(item, dict) and item.get("direction") == "output"
    ]
    for output in outputs:
        if isinstance(output, str) and re.search(rf"(?<![A-Za-z0-9_]){re.escape(output)}(?![A-Za-z0-9_])", prompt) is None:
            failures.append(f"{label}: output {output!r} is absent from the public prompt")

    expected_binding = {
        "task_id": task_id,
        "collection": collection,
        "task_manifest": f"tasks/{task_id}/task.json",
        "public_spec": f"tasks/{task_id}/public_spec.json",
        "reference_runtime_manifest": f"tasks/{task_id}/reference/runtime_manifest.json",
        "reference_materialization": materialization,
        "reference_entrypoint": runtime.get("entrypoint"),
    }
    if binding_row != expected_binding:
        failures.append(f"{label}: central profile binding differs")
    for source in profile.get("sources", []):
        if isinstance(source, dict):
            source_path = _relative_path(root, source.get("path"), failures, f"{label}: profile source")
            if source_path is None or not source_path.is_file():
                failures.append(f"{label}: profile source is missing")


def validate_profiles(root: Path, task_id: str | None = None) -> dict[str, Any]:
    root = root.resolve()
    failures: list[str] = []
    registry = _read_json(root / "registry" / "tasks.json", failures, "task registry")
    bindings = _read_json(root / "registry" / "system_profile_bindings.json", failures, "system-profile bindings")
    manifest = _read_json(root / "registry" / "system_profiles.json", failures, "system-profile manifest")
    schema = _read_json(root / "schemas" / "system_profile_v1.schema.json", failures, "system-profile schema")
    if any(document is None for document in (registry, bindings, manifest, schema)):
        return _report([], Counter(), Counter(), failures)
    assert registry is not None and bindings is not None and manifest is not None and schema is not None
    if schema.get("properties", {}).get("schema", {}).get("const") != PROFILE_SCHEMA:
        failures.append("system-profile schema identity differs")
    if bindings.get("schema") != BINDINGS_SCHEMA or manifest.get("schema") != MANIFEST_SCHEMA:
        failures.append("system-profile registry schema identity differs")
    if registry.get("release") != RELEASE or bindings.get("release") != RELEASE or manifest.get("release") != RELEASE:
        failures.append("system-profile release identity differs")

    task_rows = registry.get("tasks")
    binding_rows = bindings.get("tasks")
    profile_rows = manifest.get("tasks")
    if not all(isinstance(rows, list) for rows in (task_rows, binding_rows, profile_rows)):
        failures.append("system-profile registries require task arrays")
        return _report([], Counter(), Counter(), failures)
    ids = [row.get("task_id") for row in task_rows if isinstance(row, dict)]
    if task_id is not None:
        selected_ids = [task_id] if task_id in ids else []
        if not selected_ids:
            failures.append(f"unknown task id: {task_id}")
    else:
        selected_ids = ids
        if len(ids) != 101 or len(ids) != len(set(ids)):
            failures.append(f"task registry must contain 101 unique tasks, found {len(ids)}")
        if set(ids) != {row.get("task_id") for row in binding_rows if isinstance(row, dict)} or set(ids) != {row.get("task_id") for row in profile_rows if isinstance(row, dict)}:
            failures.append("system-profile registry task sets differ")

    task_by_id = {row.get("task_id"): row for row in task_rows if isinstance(row, dict)}
    binding_by_id = {row.get("task_id"): row for row in binding_rows if isinstance(row, dict)}
    profile_by_id = {row.get("task_id"): row for row in profile_rows if isinstance(row, dict)}
    collections: Counter[str] = Counter()
    materializations: Counter[str] = Counter()
    for selected in selected_ids:
        task_row = task_by_id.get(selected)
        binding_row = binding_by_id.get(selected)
        profile_row = profile_by_id.get(selected)
        if not all(isinstance(row, dict) for row in (task_row, binding_row, profile_row)):
            failures.append(f"{selected}: central system-profile row is missing")
            continue
        assert task_row is not None and binding_row is not None and profile_row is not None
        collections[str(task_row.get("collection"))] += 1
        materializations[str(task_row.get("reference_materialization"))] += 1
        _validate_task(root, task_row, binding_row, profile_row, failures)

    if task_id is None:
        if dict(collections) != EXPECTED_COUNTS:
            failures.append(f"profile collection counts differ: {dict(collections)}")
        if dict(materializations) != EXPECTED_MATERIALIZATIONS:
            failures.append(f"profile reference materializations differ: {dict(materializations)}")
        for document, label in ((bindings, "bindings"), (manifest, "manifest")):
            if document.get("task_count") != 101 or document.get("collection_counts") != EXPECTED_COUNTS:
                failures.append(f"system-profile {label} counts differ")
        expected_global = {
            "profile_schema": {"path": "schemas/system_profile_v1.schema.json"},
            "validator": {"path": "tools/validate_system_profiles.py"},
            "bindings": {"path": "registry/system_profile_bindings.json"},
        }
        for key, value in expected_global.items():
            if manifest.get(key) != value:
                failures.append(f"system-profile manifest {key} binding differs")
    return _report(selected_ids, collections, materializations, failures)


def _report(task_ids: list[Any], collections: Counter[str], materializations: Counter[str], failures: list[str]) -> dict[str, Any]:
    return {
        "schema": REPORT_SCHEMA,
        "status": "PASS" if not failures else "FAIL",
        "task_count": len(task_ids),
        "collection_counts": dict(collections),
        "reference_materializations": dict(materializations),
        "failures": sorted(set(failures)),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--task-id")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    report = validate_profiles(args.repo, args.task_id)
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output is not None:
        args.output.write_text(rendered, encoding="utf-8", newline="\n")
    print(rendered, end="")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
