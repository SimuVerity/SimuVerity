from __future__ import annotations

import importlib.util
import json
from pathlib import Path

from simuverity.repository import TaskRepository


ROOT = Path(__file__).resolve().parents[1]


def _read(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    assert isinstance(value, dict)
    return value


def _declared_paths(manifest: dict) -> list[str]:
    rows = [*manifest.get("files", []), *manifest.get("source_modules", [])]
    final = manifest.get("final_module")
    if isinstance(final, dict):
        rows.append(final)
    rows.extend(manifest.get("payload_files", []))
    return [
        str(row.get("public_path") or row.get("path"))
        for row in rows
        if isinstance(row, dict) and (row.get("public_path") or row.get("path"))
    ]


def test_all_public_entrypoints_and_declared_dependencies_exist() -> None:
    repository = TaskRepository(ROOT)
    for index, task_id in enumerate(repository.task_ids()):
        task = repository.get(task_id)
        extractor_manifest = _read(task.root / "extractor" / "manifest.json")
        scorer_manifest = _read(task.root / "scorer" / "manifest.json")
        assert extractor_manifest["task_id"] == task_id
        assert scorer_manifest["task_id"] == task_id
        for relative in _declared_paths(extractor_manifest) + _declared_paths(scorer_manifest):
            assert (task.root / relative).is_file(), f"{task_id}: {relative}"

        source = task.scorer_path.read_text(encoding="utf-8")
        assert "base64" not in source.casefold()
        spec = importlib.util.spec_from_file_location(f"simuverity_task_{index}", task.scorer_path)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert callable(module.score)
        payload_rows = scorer_manifest.get("payload_files", [])
        if payload_rows and hasattr(module, "_payload_paths"):
            resolved = module._payload_paths()
            assert len(resolved) == len(payload_rows), task_id
            for name, path in resolved:
                assert name
                assert path.is_file(), f"{task_id}: {path}"


def test_current_special_bindings_are_explicit() -> None:
    d022 = _read(ROOT / "tasks" / "XELEC-22" / "scorer" / "manifest.json")
    assert d022["public_bridge"] == {
        "mode": "function",
        "function": "score_complete_groups",
        "preprocessor": {
            "module": "d022_group_scoring",
            "function": "score_evidence",
            "result": "group_scores",
        },
    }

    pvtes = ROOT / "tasks" / "XTHERM-13"
    assert "/policy/" in (pvtes / "task.json").read_text(encoding="utf-8")
    assert "/policy/" in (pvtes / "extractor" / "manifest.json").read_text(encoding="utf-8")
    assert "/policy/" in (pvtes / "scorer" / "manifest.json").read_text(encoding="utf-8")

    xtherm08 = _read(ROOT / "tasks" / "XTHERM-08" / "task.json")
    assert xtherm08["evaluation_policy_id"] == (
        "simuverity-101-v1:xtherm-08:scoring"
    )
    scorer = _read(ROOT / "tasks" / "XTHERM-08" / "scorer" / "manifest.json")
    assert scorer["final_module"]["path"].endswith("f90_xtherm08_scoring.py")


def test_xauto_reference_adapters_use_the_public_official_scenario_flag() -> None:
    for task_id in ("XAUTO-07", "XAUTO-09"):
        path = ROOT / "tasks" / task_id / "scorer.py"
        spec = importlib.util.spec_from_file_location(f"{task_id}_reference_adapter", path)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        evidence = {
            "task_id": task_id,
            "scenarios": [{"id": name, "valid": True} for name in module._SCENARIOS],
            "load_pass": True,
            "update_pass": True,
            "compile_pass": True,
            "simulate_pass": True,
            "all_official_evidence_valid": True,
        }
        assert module._reference_applicable(evidence, "reference") is True
        evidence["all_official_evidence_valid"] = False
        assert module._reference_applicable(evidence, "reference") is False


def test_wec_desal_scorer_accepts_the_published_completion_flag() -> None:
    path = ROOT / "tasks" / "XFLUID-11" / "scorer.py"
    spec = importlib.util.spec_from_file_location("wec_desal_completion_bridge", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    published = {"EVIDENCE_COMPLETE": True}
    normalized = module._normalize_evidence_contract(published)
    assert normalized == {
        "EVIDENCE_COMPLETE": True,
        "evidence_complete": True,
    }
    assert published == {"EVIDENCE_COMPLETE": True}


def test_wecsim_rm3_scorer_accepts_the_published_completion_flag() -> None:
    path = ROOT / "tasks" / "XFLUID-12" / "scorer.py"
    spec = importlib.util.spec_from_file_location("wecsim_rm3_completion_bridge", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    published = {"EVIDENCE_COMPLETE": True}
    normalized = module._normalize_evidence_contract(published)
    assert normalized == {
        "EVIDENCE_COMPLETE": True,
        "evidence_complete": True,
    }
    assert published == {"EVIDENCE_COMPLETE": True}


def test_bev_multiloop_scorer_accepts_the_published_completion_flag() -> None:
    path = ROOT / "tasks" / "XTHERM-12" / "scorer.py"
    spec = importlib.util.spec_from_file_location("bev_multiloop_completion_bridge", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    published = {"EVIDENCE_COMPLETE": True}
    normalized = module._normalize_evidence_contract(published)
    assert normalized == {
        "EVIDENCE_COMPLETE": True,
        "evidence_complete": True,
    }
    assert published == {"EVIDENCE_COMPLETE": True}


def test_xauto10_scorer_accepts_the_published_validity_flags() -> None:
    path = ROOT / "tasks" / "XAUTO-10" / "scorer.py"
    spec = importlib.util.spec_from_file_location("xauto10_validity_bridge", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    published = {
        "EVIDENCE_COMPLETE": True,
        "all_official_evidence_valid": True,
    }
    normalized = module._normalize_evidence_contract(published)
    assert normalized == {
        **published,
        "evidence_complete": True,
        "all_scenarios_valid": True,
    }
    assert "evidence_complete" not in published
    assert "all_scenarios_valid" not in published


def test_xaero10_scorer_accepts_the_published_validity_flags() -> None:
    path = ROOT / "tasks" / "XAERO-10" / "scorer.py"
    spec = importlib.util.spec_from_file_location("xaero10_validity_bridge", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    published = {
        "EVIDENCE_COMPLETE": True,
        "all_official_evidence_valid": True,
    }
    normalized = module._normalize_evidence_contract(published)
    assert normalized == {
        **published,
        "evidence_complete": True,
        "all_scenarios_valid": True,
    }
    assert "evidence_complete" not in published
    assert "all_scenarios_valid" not in published


def test_xauto06_scorer_accepts_the_published_completion_flag() -> None:
    path = ROOT / "tasks" / "XAUTO-06" / "scorer.py"
    spec = importlib.util.spec_from_file_location("xauto06_completion_bridge", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    published = {"EVIDENCE_COMPLETE": True}
    normalized = module._normalize_evidence_contract(published)
    assert normalized == {
        "EVIDENCE_COMPLETE": True,
        "evidence_complete": True,
    }
    assert published == {"EVIDENCE_COMPLETE": True}


def test_xmech10_current_scorer_closure_loads() -> None:
    path = ROOT / "tasks" / "XMECH-10" / "scorer.py"
    spec = importlib.util.spec_from_file_location("xmech10_scorer_closure", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(module._module().score)


def test_xmech10_candidate_evidence_uses_six_output_public_contract() -> None:
    path = ROOT / "tasks" / "XMECH-10" / "scorer.py"
    spec = importlib.util.spec_from_file_location("xmech10_public_contract_route", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    evidence = {
        "schema": "simuverity.f90-xmech10-evidence.v1",
        "task_id": "F90-XMECH-10",
        "public_contract_id": "f90-xmech10-public-contract",
        "scenarios": [],
        "load_pass": False,
        "update_pass": False,
        "compile_pass": False,
    }
    result = module.score(evidence)
    assert result["public_contract_id"] == "f90-xmech10-public-contract"
    assert result["score_eligible"] is True
    assert result["G"] is False
    assert result["score"] == 0.0
    assert result["post_total_cap_or_floor"] is False


def test_xmech10_reference_evidence_keeps_native_reference_route() -> None:
    path = ROOT / "tasks" / "XMECH-10" / "scorer.py"
    spec = importlib.util.spec_from_file_location("xmech10_reference_route", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    evidence = {
        "schema": "simuverity.f90-xmech10-evidence.v1",
        "task_id": "F90-XMECH-10",
        "scenarios": [],
    }
    result = module.score(evidence)
    assert result["reference_evidence_mode"] == "fresh_native_reference_not_relabelled"
    assert "public_contract_id" not in result
    assert result["score"] == 0.0


def test_public_routes_do_not_apply_discarded_intermediate_total_caps() -> None:
    """Legacy source caps must not survive into any public total path."""
    targets = [
        ("XAERO-04", "f90_xaero04_scoring_core.py"),
        ("XAERO-06", "f90_xaero06_scoring_core.py"),
        ("XAUTO-04", "f90_xauto04_scoring_core.py"),
        ("XMED-07", "f90_xmed07_scoring_core.py"),
        ("XTHERM-06", "f90_xtherm06_scoring_core.py"),
        ("XMECH-06", "f90_xmech06_group_aggregation.py"),
        ("XMECH-06", "f90_xmech06_scoring_core.py"),
        ("XBATT-02", "f90_xbatt02_scoring_core.py"),
        ("XCOMM-02", "f90_xcomm02_scoring_core.py"),
        ("XCOMM-06", "f90_xcomm06_scoring_core.py"),
        ("XCOMM-08", "f90_xcomm08_scoring_core.py"),
        ("XCOMM-09", "f90_xcomm09_scoring_core.py"),
        ("XFLUID-05", "f90_xfluid05_scoring_core.py"),
        ("XFLUID-08", "f90_xfluid08_scoring_core.py"),
        ("XFLUID-09", "f90_xfluid09_scoring_core.py"),
        ("XFLUID-10", "f90_xfluid10_scoring_core.py"),
        ("XMECH-02", "f90_xmech02_scoring_core.py"),
        ("XMECH-05", "f90_xmech05_scoring_core.py"),
        ("XMECH-08", "f90_xmech08_scoring_core_core.py"),
        ("XMECH-10", "f90_xmech10_public_contract_scoring.py"),
        ("XMED-03", "f90_xmed03_scoring_core.py"),
        ("XMED-05", "f90_xmed05_scoring_core.py"),
        ("XROBO-03", "f90_xrobo03_group_aggregation.py"),
        ("XROBO-01", "f90_xrobo01_scoring_core_core.py"),
        ("XROBO-02", "f90_xrobo02_scoring_core_core.py"),
        ("XROBO-09", "f90_xrobo09_scoring_core.py"),
        ("XROBO-10", "f90_xrobo10_scoring_core.py"),
        ("XTHERM-04", "f90_xtherm04_scoring_core.py"),
        ("XTHERM-11", "f90_xtherm11_scoring_core.py"),
    ]
    for task_id, filename in targets:
        matches = list((ROOT / "tasks" / task_id).rglob(filename))
        assert len(matches) == 1, (task_id, matches)
        source = matches[0].read_text(encoding="utf-8")
        assert "total = min(total" not in source, task_id
        assert "raw = min(raw" not in source, task_id
        assert "raw_fraction = min(geometric(groups), cap)" not in source, task_id
        assert "value=min(raw_value,cap)" not in source, task_id

    xrobo03 = ROOT / "tasks" / "XROBO-03" / "vendor" / "scripts" / "formal90" / "tasks" / "f90_xrobo03" / "f90_xrobo03_structure_scoring.py"
    source = xrobo03.read_text(encoding="utf-8")
    assert "applied_cap" not in source

    for task_id, filename in (("XAUTO-02", "f90_xauto02_measurement.m"),
                              ("XBATT-02", "f90_xbatt02_measurement.m")):
        matches = list((ROOT / "tasks" / task_id).rglob(filename))
        assert len(matches) == 1, (task_id, matches)
        source = matches[0].read_text(encoding="utf-8")
        assert "total = min(total" not in source, task_id


def test_xrobo02_reference_route_declares_its_current_closure() -> None:
    task = ROOT / "tasks" / "XROBO-02"
    manifest = _read(task / "extractor" / "manifest.json")
    declared = set(_declared_paths(manifest))
    required = {
        "vendor/scripts/formal90/formal90_write_evidence.m",
        "vendor/scripts/formal90/tasks/f90_xrobo02/f90_xrobo02_definition.m",
        "vendor/scripts/formal90/tasks/f90_xrobo02/f90_xrobo02_extract_reference_evidence.m",
        "vendor/scripts/formal90/tasks/f90_xrobo02/f90_xrobo02_measurement_compatibility.m",
    }
    assert required <= declared
    measurement = (
        task
        / "vendor/scripts/formal90/tasks/f90_xrobo02/f90_xrobo02_measurement_compatibility.m"
    ).read_text(encoding="utf-8")
    assert "simuverity_public_output_compatibility(" in measurement
    assert "unified_public_output_compat" not in measurement
