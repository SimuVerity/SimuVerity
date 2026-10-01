from __future__ import annotations

import importlib.util
import json
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).parents[1]
TASK = ROOT / "tasks" / "XAERO-02"


def _json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _scorer():
    path = TASK / "scorer.py"
    spec = importlib.util.spec_from_file_location("xaero02_public_scorer", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_xaero02_candidate_closure_is_current_public_contract() -> None:
    task = _json(TASK / "task.json")
    implementation = task["extractor"]["implementation"]
    assert implementation.endswith("f90_xaero02_extract_candidate_evidence.m")
    source = (TASK / implementation).read_text(encoding="utf-8-sig")
    assert "widths = [10, 7, 8];" in source
    assert "simuverity_run_candidate_evidence" in source
    assert "all_scenarios_valid = evidence.all_official_evidence_valid" in source

    source_root = TASK / "vendor/scripts/formal90/tasks/f90_xaero02"
    assert {path.name for path in source_root.iterdir() if path.is_file()} == {
        "f90_xaero02_channel_availability.py",
        "f90_xaero02_engineering_criteria.json",
        "f90_xaero02_engineering_criteria_targets.json.gz",
        "f90_xaero02_extract_candidate_evidence.m",
        "f90_xaero02_extract_reference_evidence.m",
        "f90_xaero02_scoring.py",
        "f90_xaero02_scoring_core.py",
    }

    manifest = _json(TASK / "extractor" / "manifest.json")
    assert manifest["entrypoint"] == implementation
    paths = {item["public_path"] for item in manifest["files"]}
    assert implementation in paths


def test_xaero02_engineering_criteria_uses_channel_availability_scorer() -> None:
    manifest = _json(TASK / "scorer" / "manifest.json")
    modules = {item["module"] for item in manifest["source_modules"]}
    assert modules == {
        "f90_xaero02_channel_availability",
        "f90_xaero02_scoring",
        "f90_xaero02_scoring_core",
    }
    assert manifest["public_bridge"] == {"mode": "function"}
    criteria_source = (TASK / "vendor/scripts/formal90/tasks/f90_xaero02/f90_xaero02_scoring.py").read_text(encoding="utf-8-sig")
    assert "import f90_xaero02_channel_availability as channel_availability" in criteria_source

    scorer = _scorer()
    current = scorer._module()
    criteria = current.read_criteria(scorer._criteria_path())
    candidate = deepcopy(current.target_evidence(criteria))
    candidate.update({
        "load_pass": True,
        "update_pass": True,
        "compile_pass": True,
        "simulate_pass": True,
        "all_scenarios_valid": True,
        "runtime_model_unchanged": True,
        "evidence_complete": True,
        "static_audit": {"core_path_qualified": True},
    })
    for scenario in candidate["scenarios"]:
        for log in scenario["logs"].values():
            width = len(log["channels"])
            log["availability"] = [True] * width
            log["sources"] = [f"public:{index + 1}" for index in range(width)]
    result = scorer.score(candidate)
    assert result["G"] == 1
    assert result["total"] == 100.0
    assert result["validation_failures"] == []
