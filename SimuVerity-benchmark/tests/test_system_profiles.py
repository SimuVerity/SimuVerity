from __future__ import annotations

import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _load_validator():
    path = ROOT / "tools" / "validate_system_profiles.py"
    spec = importlib.util.spec_from_file_location("simuverity_profile_validator", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_all_system_profiles_pass_the_public_gate() -> None:
    report = _load_validator().validate_profiles(ROOT)
    assert report["status"] == "PASS", report["failures"]
    assert report["task_count"] == 101
    assert report["collection_counts"] == {
        "XELEC": 9,
        "XAERO": 10,
        "XAUTO": 11,
        "XBATT": 10,
        "XCOMM": 9,
        "XFLUID": 11,
        "XMECH": 11,
        "XMED": 9,
        "XROBO": 10,
        "XTHERM": 11,
        "XCOMM": 9,
        "XFLUID": 11,
        "XMECH": 11,
        "XMED": 9,
        "XROBO": 10,
        "XTHERM": 11,
    }
    assert report["reference_materializations"] == {
        "bundled": 68,
        "local_importer": 33,
    }


def test_static_validators_have_no_schema_package_dependency() -> None:
    for name in ("validate_system_profiles.py", "validate_release.py"):
        source = (ROOT / "tools" / name).read_text(encoding="utf-8")
        assert "json" + "schema" not in source.casefold()


def test_profiles_require_content_not_static_completion_markers() -> None:
    validator = _load_validator()
    profile = json.loads((ROOT / "tasks/XELEC-07/system_profile.json").read_text(encoding="utf-8"))
    assert "status" not in profile
    failures = []
    validator._validate_profile_shape(profile, failures, "XELEC-07")
    assert not failures
    profile["system"]["boundary"] = ""
    failures = []
    validator._validate_profile_shape(profile, failures, "XELEC-07")
    assert "XELEC-07: system boundary is empty" in failures


def test_profile_binding_schemas_do_not_require_lifecycle_status() -> None:
    profile_schema = json.loads((ROOT / "schemas/system_profile_v1.schema.json").read_text(encoding="utf-8"))
    task_schema = json.loads((ROOT / "schemas/task.schema.json").read_text(encoding="utf-8"))
    assert "status" not in profile_schema["required"]
    assert "status" not in profile_schema["properties"]
    binding = task_schema["properties"]["system_profile"]
    assert set(binding["required"]) == {"path", "schema"}
    assert set(binding["properties"]) == {"path", "schema"}


def test_static_metadata_cleanup_preserves_runtime_and_agent_isolation() -> None:
    profile = json.loads((ROOT / "tasks/XELEC-07/system_profile.json").read_text(encoding="utf-8"))
    assert profile["scope"]["sent_to_agent"] is False
    for name in ("generation-receipt.schema.json", "evaluation-result.schema.json"):
        schema = json.loads((ROOT / "schemas" / name).read_text(encoding="utf-8"))
        assert "status" in schema["properties"]
