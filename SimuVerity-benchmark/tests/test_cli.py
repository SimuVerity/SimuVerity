from __future__ import annotations

import json
from pathlib import Path

import pytest

from simuverity.cli import build_parser, main


ROOT = Path(__file__).resolve().parents[1]


def test_task_listing_cli(capsys) -> None:
    assert main(["--repo", str(ROOT), "tasks", "list"]) == 0
    output = json.loads(capsys.readouterr().out)
    assert output["schema"] == "simuverity.task-list.v1"
    assert output["task_count"] == 101
    assert len(output["tasks"]) == 101


def test_run_id_options_are_consistent() -> None:
    parser = build_parser()
    evaluate = parser.parse_args(
        [
            "--repo",
            str(ROOT),
            "evaluate",
            "XELEC-14",
            "--submission",
            str(ROOT),
            "--generation-run-id",
            "generation-test",
            "--scoring-run-id",
            "scoring-test",
        ]
    )
    assert evaluate.generation_run_id == "generation-test"
    assert evaluate.scoring_run_id == "scoring-test"


@pytest.mark.parametrize("command", ("evaluate", "run"))
def test_candidate_commands_do_not_accept_reference_asset_root(command: str) -> None:
    parser = build_parser()
    argv = ["--repo", str(ROOT), command, "XELEC-14"]
    if command == "evaluate":
        argv.extend(["--submission", str(ROOT)])
    else:
        argv.extend(
            [
                "--agent",
                "codex",
                "--model",
                "fixture",
                "--mcp-config",
                str(ROOT / "README.md"),
            ]
        )
    argv.extend(["--asset-root", str(ROOT)])
    with pytest.raises(SystemExit):
        parser.parse_args(argv)
