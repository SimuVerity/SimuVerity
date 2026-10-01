from __future__ import annotations

import json
from pathlib import Path

import pytest

from simuverity.errors import ContractError
from simuverity.evaluation.evidence import create_evidence_bundle, validate_evidence_bundle


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def test_evidence_bundle_uses_public_run_ids_and_direct_file_checks(tmp_path: Path) -> None:
    extraction = tmp_path / "extraction"
    evidence = extraction / "evidence.json"
    artifact = extraction / "scenario_data" / "waveforms.mat"
    scenarios = tmp_path / "official_scenarios.json"
    sidecar = tmp_path / "structure_audit.json"
    _write_json(evidence, {"task_id": "XELEC-14", "scenarios": []})
    artifact.parent.mkdir()
    artifact.write_bytes(b"waveform")
    _write_json(
        extraction / "evidence_closure_manifest.json",
        {
            "schema": "simuverity.evidence-closure-manifest.v1",
            "task_id": "XELEC-14",
            "evidence_file": "evidence.json",
            "files": [{"path": "scenario_data/waveforms.mat", "size_bytes": 8}],
        },
    )
    _write_json(scenarios, {"task_id": "XELEC-14", "scenarios": []})
    _write_json(sidecar, {"schema": "simuverity.test-sidecar.v1", "task_id": "XELEC-14"})

    manifest_path = create_evidence_bundle(
        evidence,
        bundle_root=tmp_path / "bundle",
        task_id="XELEC-14",
        generation_run_id="generation-1",
        scoring_run_id="scoring-1",
        candidate_file="cand_XELEC-14.slx",
        scenarios_source=scenarios,
        evaluation_policy_id="simuverity-101-v1:d014:scoring",
        sidecars={
            "structure_audit": {
                "path": sidecar,
                "schema": "simuverity.test-sidecar.v1",
            }
        },
    )
    manifest, copied_evidence = validate_evidence_bundle(
        manifest_path, task_id="XELEC-14", scenarios_path=scenarios
    )
    assert manifest["generation_run_id"] == "generation-1"
    assert manifest["scoring_run_id"] == "scoring-1"
    assert manifest["schema"] == "simuverity.evidence-bundle.v1"
    assert copied_evidence.read_bytes() == evidence.read_bytes()
    assert manifest["artifacts"] == [
        {"file": "scenario_data/waveforms.mat", "size_bytes": 8}
    ]

    manifest["evidence_size_bytes"] += 1
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ContractError, match="Evidence size differs"):
        validate_evidence_bundle(manifest_path, task_id="XELEC-14", scenarios_path=scenarios)
