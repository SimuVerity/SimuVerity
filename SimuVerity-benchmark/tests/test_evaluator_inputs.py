from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest

import simuverity.assets as assets
import simuverity.assets.importer as asset_importer

from simuverity.errors import ContractError
from simuverity.evaluation import pipeline
from simuverity.repository import TaskRepository


ROOT = Path(__file__).resolve().parents[1]


def test_local_importer_candidates_do_not_resolve_reference_assets(monkeypatch) -> None:
    repository = TaskRepository(ROOT)

    def unexpected_resolver(*_args, **_kwargs):
        raise AssertionError("candidate evaluation resolved optional reference assets")

    monkeypatch.setattr(assets, "resolve_reference_asset_root", unexpected_resolver)
    local_importers = [
        repository.get(task_id)
        for task_id in repository.task_ids()
        if repository.get(task_id).reference.get("materialization") == "local_importer"
    ]
    assert len(local_importers) == 33
    for task in local_importers:
        assert pipeline._resolve_evaluator_asset_root(
            task,
            evaluator_asset_root=None,
            evaluation_subject="candidate",
        ) is None


def test_reference_evaluation_still_resolves_ready_assets(monkeypatch) -> None:
    task = TaskRepository(ROOT).get("XAUTO-09")
    expected = task.root / "reference"
    observed = []

    def fake_resolver(received):
        observed.append(received.task_id)
        return expected

    monkeypatch.setattr(assets, "resolve_reference_asset_root", fake_resolver)
    assert pipeline._resolve_evaluator_asset_root(
        task,
        evaluator_asset_root=None,
        evaluation_subject="reference",
    ) == expected.resolve()
    assert observed == [task.task_id]


def test_local_importer_reference_without_ready_receipt_is_rejected(
    tmp_path, monkeypatch
) -> None:
    task = TaskRepository(ROOT).get("XAUTO-09")
    monkeypatch.setattr(asset_importer, "default_asset_root", lambda _release: tmp_path)
    with pytest.raises(ContractError, match="reference assets are not READY"):
        pipeline._resolve_evaluator_asset_root(
            task,
            evaluator_asset_root=None,
            evaluation_subject="reference",
        )


def test_bundled_pmsm_candidate_keeps_its_reference_derived_input(monkeypatch) -> None:
    task = TaskRepository(ROOT).get("XAUTO-13")
    expected = task.root / "reference" / "files"

    monkeypatch.setattr(
        assets,
        "resolve_reference_asset_root",
        lambda received: expected if received.task_id == task.task_id else None,
    )
    assert pipeline._resolve_evaluator_asset_root(
        task,
        evaluator_asset_root=None,
        evaluation_subject="candidate",
    ) == expected.resolve()


def test_local_importer_scorers_do_not_read_reference_assets() -> None:
    repository = TaskRepository(ROOT)
    forbidden = (
        "SIMUVERITY_EVALUATOR_ASSET_ROOT",
        "asset_receipt.json",
        "resolve_reference_asset_root",
        "reference/files",
    )
    checked = 0
    for task_id in repository.task_ids():
        task = repository.get(task_id)
        if task.reference.get("materialization") != "local_importer":
            continue
        manifest = json.loads(
            (task.root / "scorer" / "manifest.json").read_text(
                encoding="utf-8-sig"
            )
        )
        rows = [
            *manifest.get("files", []),
            *manifest.get("source_modules", []),
            *manifest.get("payload_files", []),
        ]
        final = manifest.get("final_module")
        if isinstance(final, dict):
            rows.append(final)
        elif isinstance(final, str):
            rows.append({"public_path": final})
        paths = {task.scorer_path}
        for row in rows:
            if not isinstance(row, dict):
                continue
            relative = row.get("path") or row.get("public_path")
            if isinstance(relative, str):
                path = task.root / relative
                if path.suffix in {".py", ".json"}:
                    paths.add(path)
        for path in paths:
            text = path.read_text(encoding="utf-8-sig")
            assert not any(token in text for token in forbidden), (
                f"{task_id}: scorer depends on optional reference asset: {path}"
            )
        checked += 1
    assert checked == 33


def test_pmsm_pack_is_generated_inside_the_evaluator_run(tmp_path, monkeypatch) -> None:
    task = TaskRepository(Path(__file__).resolve().parents[1]).get(
        "XAUTO-13"
    )
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    layout = SimpleNamespace(root=tmp_path / "evaluation", workspace=workspace)
    observed = {}

    def fake_command(_task, _candidate, evidence_path, **_kwargs):
        evidence_path.write_text("{}", encoding="utf-8")
        (evidence_path.parent / "pmsm_measurement_experiments.mat").write_bytes(
            b"sanitized-pack"
        )
        return ["fixture"]

    def fake_run(_command, **kwargs):
        observed.update(kwargs["env"])
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(pipeline, "_extractor_command", fake_command)
    monkeypatch.setattr(pipeline.subprocess, "run", fake_run)
    pack = pipeline._prepare_pmsm_measurement_pack(
        task,
        evaluator_asset_root=task.root / "reference" / "files",
        layout=layout,
        environment={
            "SIMUVERITY_TASK_ID": task.task_id,
            "SIMUVERITY_GENERATION_RUN_ID": "generation-test",
            "SIMUVERITY_SCORING_RUN_ID": "scoring-test",
        },
    )
    assert pack == layout.root / "evaluator_inputs" / "pmsm" / "reference_extraction" / "pmsm_measurement_experiments.mat"
    assert pack.read_bytes() == b"sanitized-pack"
    assert observed["SIMUVERITY_EVALUATION_SUBJECT"] == "reference"
    assert "SIMUVERITY_EXT_PMSM_MEASUREMENT_PACK" not in observed
