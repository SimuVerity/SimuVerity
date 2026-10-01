from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from simuverity.assets.importer import _verify_materialized
from simuverity.candidate_closure.replay import _stop_time
from simuverity.repository import TaskRepository


ROOT = Path(__file__).resolve().parents[1]


def test_all_release_tasks_load_from_public_assets() -> None:
    repository = TaskRepository(ROOT)
    task_ids = repository.task_ids()
    assert len(task_ids) == 101
    assert Counter(repository.get(task_id).collection for task_id in task_ids) == {
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

    for task_id in task_ids:
        task = repository.get(task_id)
        manifest = json.loads(task.manifest_path.read_text(encoding="utf-8-sig"))
        assert manifest["release"] == "simuverity-101-v1"
        assert manifest["system_profile"] == {
            "path": "system_profile.json",
            "schema": "simuverity.system-profile.v1",
        }
        assert repository.prompt_bytes(task).strip()
        assert task.system_profile_path.is_file()
        assert task.scenarios_path.is_file()
        assert task.scorer_path == task.root / "scorer.py"
        assert task.extractor_path.exists()
        assert task.evaluation_policy_id == (
            f"simuverity-101-v1:{task_id.casefold()}:scoring"
        )
        assert 90 <= float(task.reference["expected_score"]) <= 100
        assert int(task.reference["expected_valid_scenarios"]) > 0


def test_registry_matches_task_manifests() -> None:
    repository = TaskRepository(ROOT)
    registry = json.loads((ROOT / "registry" / "tasks.json").read_text(encoding="utf-8"))
    rows = registry["tasks"]
    assert [row["ordinal"] for row in rows] == list(range(1, 102))
    assert {row["task_id"] for row in rows} == set(repository.task_ids())
    for row in rows:
        task = repository.get(row["task_id"])
        assert row["evaluation_policy_id"] == task.evaluation_policy_id
        assert row["reference_expected_score"] == task.reference["expected_score"]
        assert row["system_profile"] == f"tasks/{task.task_id}/system_profile.json"
        assert "system_profile_status" not in row


def test_importer_inventory_accepts_filename_and_relative_path_rows(tmp_path: Path) -> None:
    nested = tmp_path / "nested"
    nested.mkdir()
    (nested / "model.slx").write_bytes(b"model")
    reference = {"entrypoint": "nested/model.slx"}
    for key, value in (("path", "nested/model.slx"), ("name", "nested/model.slx")):
        recipe = {
            "discovery": {
                "expected_files": [{key: value, "size_bytes": 5}],
            }
        }
        assert _verify_materialized(tmp_path, reference=reference, recipe=recipe) == nested / "model.slx"


def test_clean_replay_accepts_the_published_stop_s_field() -> None:
    task = TaskRepository(ROOT).get("XROBO-10")
    assert _stop_time(task) == 50.0
