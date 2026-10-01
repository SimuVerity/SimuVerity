from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from .assets import prepare_reference_asset
from .doctor import run_doctor
from .errors import SimuVerityError
from .evaluation import evaluate_submission, rescore_evidence
from .orchestrator import generate_task, run_task
from .orchestrator.runner import new_identity
from .repository import TaskRepository


def _emit(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2))


def _repository(args: argparse.Namespace) -> TaskRepository:
    return TaskRepository.discover(args.repo)


def _add_generation_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("task")
    parser.add_argument("--agent", required=True, choices=("codex", "claude-code"))
    parser.add_argument("--model", required=True)
    parser.add_argument("--mcp-config", type=Path, required=True)
    parser.add_argument("--agent-home", type=Path)
    parser.add_argument("--generation-run-id")
    parser.add_argument("--simulation-timeout-seconds", type=int, default=1800)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="simuverity")
    parser.add_argument("--repo", type=Path, help="repository root (auto-detected by default)")
    commands = parser.add_subparsers(dest="command", required=True)
    tasks = commands.add_parser("tasks", help="inspect public tasks")
    task_commands = tasks.add_subparsers(dest="tasks_command", required=True)
    task_commands.add_parser("list")
    show = task_commands.add_parser("show")
    show.add_argument("task")
    commands.add_parser("doctor", help="check the supported local runtime")
    assets = commands.add_parser("assets", help="materialize reference assets")
    asset_commands = assets.add_subparsers(dest="assets_command", required=True)
    prepare = asset_commands.add_parser("prepare")
    group = prepare.add_mutually_exclusive_group(required=True)
    group.add_argument("task", nargs="?")
    group.add_argument("--all", action="store_true")
    prepare.add_argument("--asset-root", type=Path)
    prepare.add_argument("--matlab", default="matlab")
    prepare.add_argument("--dry-run", action="store_true")
    prepare.add_argument(
        "--evidence-bundle",
        type=Path,
        help="resume one local importer from an existing complete evidence bundle without MATLAB",
    )
    prepare.add_argument(
        "--materialized-root",
        type=Path,
        help="explicit failed importer files root paired with --evidence-bundle",
    )
    generate = commands.add_parser("generate", help="run only the generation plane")
    _add_generation_options(generate)
    generate.add_argument("--output", type=Path)
    evaluate = commands.add_parser("evaluate", help="seal and evaluate an existing submission")
    evaluate.add_argument("task")
    evaluate.add_argument("--submission", type=Path, required=True)
    evaluate.add_argument("--generation-run-id", default=None)
    evaluate.add_argument("--scoring-run-id", default=None)
    evaluate.add_argument("--output", type=Path)
    evaluate.add_argument("--simulation-timeout-seconds", type=int, default=1800)
    rescore = commands.add_parser("rescore", help="pure offline scoring from immutable evidence")
    rescore.add_argument("task")
    rescore.add_argument("--evidence-bundle", type=Path, required=True)
    rescore.add_argument("--scoring-run-id", default=None)
    rescore.add_argument("--output", type=Path)
    run = commands.add_parser("run", help="one-task generate then evaluate convenience command")
    _add_generation_options(run)
    run.add_argument("--scoring-run-id", default=None)
    run.add_argument("--generations-output", type=Path)
    run.add_argument("--evaluations-output", type=Path)
    return parser


def dispatch(args: argparse.Namespace) -> Any:
    repository = _repository(args)
    if args.command == "tasks":
        if args.tasks_command == "list":
            return {"schema": "simuverity.task-list.v1", "task_count": len(repository.task_ids()), "tasks": repository.task_ids()}
        return repository.summary(repository.get(args.task))
    if args.command == "doctor":
        return run_doctor(repository)
    if args.command == "assets":
        if (args.evidence_bundle is None) != (args.materialized_root is None):
            raise SimuVerityError(
                "assets prepare offline resume requires both --evidence-bundle and --materialized-root"
            )
        if args.all and args.evidence_bundle is not None:
            raise SimuVerityError("assets prepare --all cannot use a single offline evidence bundle")
        task_ids = repository.task_ids() if args.all else [args.task]
        return {
            "schema": "simuverity.asset-prepare-results.v1",
            "results": [
                prepare_reference_asset(
                    repository.get(task_id),
                    asset_root=args.asset_root,
                    matlab_executable=args.matlab,
                    dry_run=args.dry_run,
                    evidence_bundle_path=args.evidence_bundle,
                    materialized_root=args.materialized_root,
                )
                for task_id in task_ids
            ],
        }
    if args.command == "generate":
        output = args.output or repository.root / "runs" / "generations"
        return generate_task(
            repository,
            args.task,
            agent=args.agent,
            model=args.model,
            mcp_config=args.mcp_config,
            output_parent=output,
            generation_run_id=args.generation_run_id,
            source_agent_home=args.agent_home,
            simulation_timeout_seconds=args.simulation_timeout_seconds,
        )
    if args.command == "evaluate":
        task = repository.get(args.task)
        return evaluate_submission(
            task,
            submission_root=args.submission,
            output_parent=args.output or repository.root / "evaluations",
            generation_run_id=args.generation_run_id or new_identity("external"),
            scoring_run_id=args.scoring_run_id or new_identity("scoring"),
            simulation_timeout_seconds=args.simulation_timeout_seconds,
        )
    if args.command == "rescore":
        return rescore_evidence(
            repository.get(args.task),
            evidence_bundle_path=args.evidence_bundle,
            output_parent=args.output or repository.root / "evaluations",
            scoring_run_id=args.scoring_run_id or new_identity("rescore"),
        )
    if args.command == "run":
        return run_task(
            repository,
            args.task,
            agent=args.agent,
            model=args.model,
            mcp_config=args.mcp_config,
            generations_parent=args.generations_output or repository.root / "runs" / "generations",
            evaluations_parent=args.evaluations_output or repository.root / "evaluations",
            generation_run_id=args.generation_run_id,
            scoring_run_id=args.scoring_run_id,
            source_agent_home=args.agent_home,
            simulation_timeout_seconds=args.simulation_timeout_seconds,
        )
    raise AssertionError(args.command)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = dispatch(args)
        _emit(result)
        return 0
    except (SimuVerityError, OSError, ValueError) as exc:
        print(f"simuverity: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
