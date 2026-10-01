#!/usr/bin/env python3
"""Validate the complete SimuVerity public result release."""

from __future__ import annotations

import csv
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP, localcontext
import ipaddress
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RELEASE = "simuverity-101-v1"
COMPLETE_TASKSET = "simuverity-101-v1"
ABLATION_TASKSET = "simuverity-mcp-ablation-10-v1"
REPEAT_IDS = ("run1", "run2", "run3")
SIX_DECIMALS = Decimal("0.000001")

IDENTITY_FIELDS = (
    "schema_version",
    "run_id",
    "benchmark_release",
    "taskset_id",
    "model",
    "harness",
    "condition",
    "task_count",
)
RUN_FILE_FIELDS = ("scores_file", "summary_file")
PARENT_RUN_FIELDS = (
    *IDENTITY_FIELDS,
    *RUN_FILE_FIELDS,
    "aggregation",
    "repeat_count",
    "repeat_ids",
)
REPEAT_RUN_FIELDS = (
    *IDENTITY_FIELDS,
    *RUN_FILE_FIELDS,
    "parent_run_id",
    "repeat_id",
)
SUMMARY_VALUE_FIELDS = (
    "scored_count",
    "protocol_zero_count",
    "score_sum",
    "score_mean",
    "delivered_count",
    "native_executable_count",
    "g_pass_count",
)
PARENT_SUMMARY_FIELDS = (
    *IDENTITY_FIELDS,
    *SUMMARY_VALUE_FIELDS,
    "repeat_count",
    "result_count",
)
REPEAT_SUMMARY_FIELDS = (
    *IDENTITY_FIELDS,
    *SUMMARY_VALUE_FIELDS,
    "parent_run_id",
    "repeat_id",
)

DOMAIN_FIELDS = ("A", "Q", "M", "C", "R", "D")
PREREQUISITE_FIELDS = ("delivered", "native_executable", "g_pass")
REPEAT_SCORE_FIELDS = (
    "task_id",
    "status",
    "protocol_zero",
    "total",
    *DOMAIN_FIELDS,
    *PREREQUISITE_FIELDS,
)
PARENT_SCORE_FIELDS = (
    "task_id",
    "total",
    *DOMAIN_FIELDS,
    "delivered_count",
    "native_executable_count",
    "g_pass_count",
)
TASKSET_FIELDS = ("task_id", "collection")

ALLOWED_STATUSES = {
    "SCORED",
    "INVALID_CANDIDATE",
    "MISSING_DELIVERY",
    "TIMEOUT",
    "PROTOCOL_ZERO",
    "INELIGIBLE",
}
TERMINAL_STATUSES = {
    "INVALID_CANDIDATE",
    "MISSING_DELIVERY",
    "TIMEOUT",
    "PROTOCOL_ZERO",
}

RUNS = {
    "gpt-5-5-codex-101": {
        "model": "GPT-5.5",
        "harness": "Codex",
        "condition": None,
        "taskset_id": COMPLETE_TASKSET,
        "task_count": 101,
        "score_sum": "4214.213333",
        "score_mean": "41.724884",
        "prerequisite_totals": (299, 287, 229),
    },
    "opus-4-8-claude-code-101": {
        "model": "Claude Opus 4.8",
        "harness": "Claude Code",
        "condition": None,
        "taskset_id": COMPLETE_TASKSET,
        "task_count": 101,
        "score_sum": "4328.360891",
        "score_mean": "42.855058",
        "prerequisite_totals": (287, 262, 233),
    },
    "deepseek-v4-pro-claude-code-101": {
        "model": "DeepSeek-V4-Pro",
        "harness": "Claude Code",
        "condition": None,
        "taskset_id": COMPLETE_TASKSET,
        "task_count": 101,
        "score_sum": "2868.302156",
        "score_mean": "28.399031",
        "prerequisite_totals": (294, 267, 186),
    },
    "qwen3-8-max-claude-code-101": {
        "model": "Qwen3.8-Max",
        "harness": "Claude Code",
        "condition": None,
        "taskset_id": COMPLETE_TASKSET,
        "task_count": 101,
        "score_sum": "2526.490388",
        "score_mean": "25.014756",
        "prerequisite_totals": (272, 245, 163),
    },
    "glm-5-3-flash-claude-code-101": {
        "model": "GLM-5.3-Flash",
        "harness": "Claude Code",
        "condition": None,
        "taskset_id": COMPLETE_TASKSET,
        "task_count": 101,
        "score_sum": "502.690996",
        "score_mean": "4.977139",
        "prerequisite_totals": (291, 146, 40),
    },
    "qwen3-8-27b-fp8-claude-code-101": {
        "model": "Qwen3.8-27B-FP8",
        "harness": "Claude Code",
        "condition": None,
        "taskset_id": COMPLETE_TASKSET,
        "task_count": 101,
        "score_sum": "161.892651",
        "score_mean": "1.602898",
        "prerequisite_totals": (92, 41, 19),
    },
    "opus-4-8-claude-code-full-mcp-10": {
        "model": "Claude Opus 4.8",
        "harness": "Claude Code",
        "condition": "full_mcp",
        "taskset_id": ABLATION_TASKSET,
        "task_count": 10,
        "score_sum": "784.624548",
        "score_mean": "78.462455",
        "prerequisite_totals": (30, 30, 30),
    },
    "opus-4-8-claude-code-no-simulation-10": {
        "model": "Claude Opus 4.8",
        "harness": "Claude Code",
        "condition": "no_simulation",
        "taskset_id": ABLATION_TASKSET,
        "task_count": 10,
        "score_sum": "78.837205",
        "score_mean": "7.883721",
        "prerequisite_totals": (16, 10, 4),
    },
    "opus-4-8-claude-code-batch-only-10": {
        "model": "Claude Opus 4.8",
        "harness": "Claude Code",
        "condition": "batch_only",
        "taskset_id": ABLATION_TASKSET,
        "task_count": 10,
        "score_sum": "182.302333",
        "score_mean": "18.230233",
        "prerequisite_totals": (18, 15, 12),
    },
}

LEADERBOARD_ORDER = (
    "opus-4-8-claude-code-101",
    "gpt-5-5-codex-101",
    "deepseek-v4-pro-claude-code-101",
    "qwen3-8-max-claude-code-101",
    "glm-5-3-flash-claude-code-101",
    "qwen3-8-27b-fp8-claude-code-101",
)
ABLATION_ORDER = (
    "opus-4-8-claude-code-full-mcp-10",
    "opus-4-8-claude-code-no-simulation-10",
    "opus-4-8-claude-code-batch-only-10",
)
ABLATION_TASKS = (
    "XAERO-07",
    "XAUTO-07",
    "XBATT-05",
    "XCOMM-06",
    "XFLUID-08",
    "XMECH-06",
    "XMED-10",
    "XROBO-02",
    "XTHERM-06",
    "XELEC-07",
)

LEADERBOARD_FIELDS = (
    "run_id",
    "model",
    "harness",
    "benchmark_release",
    "taskset_id",
    "task_count",
    "repeat_count",
    "result_count",
    "scored_count",
    "protocol_zero_count",
    "score_sum",
    "score_mean",
    "delivered_count",
    "native_executable_count",
    "g_pass_count",
)
ABLATION_SUMMARY_FIELDS = (
    "condition",
    "run_id",
    "model",
    "harness",
    "taskset_id",
    "task_count",
    "repeat_count",
    "result_count",
    "scored_count",
    "protocol_zero_count",
    "score_sum",
    "score_mean",
    "delta_vs_full_mean",
    "delivered_count",
    "native_executable_count",
    "g_pass_count",
)
COMPARISON_FIELDS = (
    "task_id",
    "full_mcp_total",
    "no_simulation_total",
    "batch_only_total",
    "no_simulation_delta_vs_full",
    "batch_only_delta_vs_full",
)


def _expected_files() -> set[str]:
    files = {
        ".gitignore",
        "README.md",
        "LICENSE",
        "NOTICE",
        "leaderboard.csv",
        "tasksets/simuverity-101-v1.csv",
        "tasksets/simuverity-mcp-ablation-10-v1.csv",
        "ablations/mcp-10/summary.csv",
        "ablations/mcp-10/comparison.csv",
        "schemas/results-format.md",
        "tools/validate_results.py",
        "tests/test_results.py",
    }
    for run_id in RUNS:
        for name in ("run.json", "scores.csv", "summary.json"):
            files.add(f"runs/{run_id}/{name}")
        for repeat_id in REPEAT_IDS:
            for name in ("run.json", "scores.csv", "summary.json"):
                files.add(f"runs/{run_id}/{repeat_id}/{name}")
    return files


def _expected_dirs() -> set[str]:
    dirs = {
        "runs",
        "tasksets",
        "ablations",
        "ablations/mcp-10",
        "schemas",
        "tools",
        "tests",
    }
    for run_id in RUNS:
        dirs.add(f"runs/{run_id}")
        for repeat_id in REPEAT_IDS:
            dirs.add(f"runs/{run_id}/{repeat_id}")
    return dirs


def _walk_public(root: Path) -> tuple[set[str], set[str]]:
    files: set[str] = set()
    dirs: set[str] = set()
    for path in root.rglob("*"):
        rel = path.relative_to(root)
        if rel.parts and rel.parts[0] == ".git":
            continue
        if path.is_dir():
            dirs.add(rel.as_posix())
        else:
            files.add(rel.as_posix())
    return files, dirs


def _load_json(path: Path, errors: list[str]) -> dict[str, Any] | None:
    if not path.is_file():
        errors.append(f"missing file: {path.as_posix()}")
        return None

    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        errors.append(f"cannot read {path.name}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{path.name} must contain one JSON object")
        return None
    return value


def _load_csv(
    path: Path, expected_fields: tuple[str, ...], errors: list[str]
) -> list[dict[str, str]]:
    if not path.is_file():
        errors.append(f"missing file: {path.as_posix()}")
        return []
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            if tuple(reader.fieldnames or ()) != expected_fields:
                errors.append(f"{path.as_posix()} columns differ: {reader.fieldnames!r}")
                return []
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        errors.append(f"cannot read {path.name}: {exc}")
        return []
    if any(None in row for row in rows):
        errors.append(f"{path.name} contains a row with extra columns")
    return rows


def _decimal(
    text: str, label: str, errors: list[str], *, allow_empty: bool = False
) -> Decimal | None:
    if text == "" and allow_empty:
        return None
    try:
        value = Decimal(text)
    except (InvalidOperation, ValueError):
        errors.append(f"{label} is not a decimal: {text!r}")
        return None
    if not value.is_finite():
        errors.append(f"{label} must be finite")
        return None
    return value


def _round_six(value: Decimal) -> Decimal:
    rounded = value.quantize(SIX_DECIMALS, rounding=ROUND_HALF_UP)
    return abs(rounded) if rounded == 0 else rounded


def _format_six(value: Decimal) -> str:
    return format(_round_six(value), ".6f")


def _decimal_six(
    text: str, label: str, errors: list[str], *, allow_empty: bool = False
) -> Decimal | None:
    value = _decimal(text, label, errors, allow_empty=allow_empty)
    if value is not None and text != _format_six(value):
        errors.append(f"{label} must use fixed six-decimal format")
    return value


def _domain_six(text: str, label: str, errors: list[str]) -> Decimal | None:
    value = _decimal_six(text, label, errors, allow_empty=True)
    if value is not None and not Decimal(0) <= value <= Decimal(100):
        errors.append(f"{label} is outside 0 through 100")
    return value


def _mean_six(values: list[Decimal]) -> Decimal:
    with localcontext() as context:
        context.prec = 50
        return _round_six(sum(values, Decimal(0)) / Decimal(len(values)))


def _integer_text(
    text: str, label: str, errors: list[str], *, maximum: int | None = None
) -> int | None:
    if not re.fullmatch(r"0|[1-9]\d*", text):
        errors.append(f"{label} must be a nonnegative integer")
        return None
    value = int(text)
    if maximum is not None and value > maximum:
        errors.append(f"{label} must not exceed {maximum}")
        return None
    return value


def _check_exact_fields(
    data: dict[str, Any], fields: tuple[str, ...], label: str, errors: list[str]
) -> None:
    if set(data) != set(fields):
        missing = sorted(set(fields) - set(data))
        extra = sorted(set(data) - set(fields))
        errors.append(f"{label} fields differ; missing={missing}, extra={extra}")


def _check_taskset(
    root: Path, taskset_id: str, errors: list[str]
) -> list[dict[str, str]]:
    rows = _load_csv(root / "tasksets" / f"{taskset_id}.csv", TASKSET_FIELDS, errors)
    required_count = 101 if taskset_id == COMPLETE_TASKSET else 10
    if len(rows) != required_count:
        errors.append(f"{taskset_id} must contain {required_count} rows")
    task_ids = [row.get("task_id", "") for row in rows]
    if len(set(task_ids)) != len(task_ids):
        errors.append(f"{taskset_id} contains duplicate task identifiers")
    for index, row in enumerate(rows, start=2):
        task_id = row.get("task_id", "")
        collection = row.get("collection", "")
        match = re.fullmatch(r"(X[A-Z]+)-[A-Z0-9]+(?:-[A-Z0-9]+)*", task_id)
        expected_collection = match.group(1) if match else ""
        if not expected_collection:
            errors.append(f"{taskset_id}:{index} has an invalid task identifier")
        elif collection != expected_collection:
            errors.append(f"{taskset_id}:{index} collection must be {expected_collection}")
    if taskset_id == COMPLETE_TASKSET:
        counts: dict[str, int] = {}
        for row in rows:
            key = row.get("collection", "")
            counts[key] = counts.get(key, 0) + 1
        if counts != {"XELEC": 9, "XAERO": 10, "XAUTO": 11, "XBATT": 10, "XCOMM": 9, "XFLUID": 11, "XMECH": 11, "XMED": 9, "XROBO": 10, "XTHERM": 11}:
            errors.append(f"complete task-set collection counts differ: {counts}")
    elif tuple(task_ids) != ABLATION_TASKS:
        errors.append("ablation task order differs from the published ten-task set")
    return rows


def _expected_identity(parent_id: str, run_id: str) -> dict[str, Any]:
    expected = RUNS[parent_id]
    return {
        "schema_version": "1.0",
        "run_id": run_id,
        "benchmark_release": RELEASE,
        "taskset_id": expected["taskset_id"],
        "model": expected["model"],
        "harness": expected["harness"],
        "condition": expected["condition"],
        "task_count": expected["task_count"],
    }


def _check_identity(
    data: dict[str, Any], parent_id: str, run_id: str, label: str, errors: list[str]
) -> None:
    for key, value in _expected_identity(parent_id, run_id).items():
        if data.get(key) != value:
            errors.append(f"{label}.{key} must be {value!r}")
    for key in IDENTITY_FIELDS:
        if key == "task_count":
            if key in data and type(data[key]) is not int:
                errors.append(f"{label}.{key} must be an integer")
        elif key == "condition":
            if data.get(key) is not None and not isinstance(data.get(key), str):
                errors.append(f"{label}.{key} must be a string or null")
        elif key in data and not isinstance(data[key], str):
            errors.append(f"{label}.{key} must be a string")


def _check_local_file_fields(data: dict[str, Any], label: str, errors: list[str]) -> None:
    for field in RUN_FILE_FIELDS:
        expected = "scores.csv" if field == "scores_file" else "summary.json"
        value = data.get(field)
        if value != expected:
            errors.append(f"{label}.{field} must be {expected}")
        if not isinstance(value, str):
            continue
        relative = PurePosixPath(value)
        if relative.is_absolute() or len(relative.parts) != 1 or ".." in relative.parts:
            errors.append(f"{label}.{field} must be a local file name")


def _check_summary_types(
    summary: dict[str, Any], label: str, errors: list[str]
) -> None:
    for key in (
        "scored_count",
        "protocol_zero_count",
        "delivered_count",
        "native_executable_count",
        "g_pass_count",
    ):
        if key in summary and type(summary[key]) is not int:
            errors.append(f"{label}.{key} must be an integer")
    for key in ("score_sum", "score_mean"):
        if key in summary and not isinstance(summary[key], str):
            errors.append(f"{label}.{key} must be a decimal string")
        elif key in summary:
            _decimal_six(summary[key], f"{label}.{key}", errors)


def _read_parent_rows(
    run_dir: Path, parent_id: str, expected_task_ids: list[str], errors: list[str]
) -> tuple[list[dict[str, str]], dict[str, tuple[str, ...]]]:
    rows = _load_csv(run_dir / "scores.csv", PARENT_SCORE_FIELDS, errors)
    if len(rows) != RUNS[parent_id]["task_count"]:
        errors.append(f"{parent_id} parent score-row count differs")
    task_ids = [row.get("task_id", "") for row in rows]
    if task_ids != expected_task_ids:
        errors.append(f"{parent_id} parent task identifiers or order differ")
    if len(set(task_ids)) != len(task_ids):
        errors.append(f"{parent_id} parent contains duplicate task identifiers")

    applicable: dict[str, tuple[str, ...]] = {}
    for line_number, row in enumerate(rows, start=2):
        label = f"{parent_id}/scores.csv:{line_number}"
        total = _decimal_six(row.get("total", ""), f"{label}.total", errors)
        if total is not None and not Decimal(0) <= total <= Decimal(100):
            errors.append(f"{label}.total is outside 0 through 100")
        active: list[str] = []
        for domain in DOMAIN_FIELDS:
            value = _domain_six(
                row.get(domain, ""), f"{label}.{domain}", errors
            )
            if value is not None:
                active.append(domain)
        if not active:
            errors.append(f"{label} must identify at least one applicable domain")
        applicable[row.get("task_id", "")] = tuple(active)
        for field in PREREQUISITE_FIELDS:
            _integer_text(
                row.get(f"{field}_count", ""),
                f"{label}.{field}_count",
                errors,
                maximum=len(REPEAT_IDS),
            )
    return rows, applicable


def _check_repeat_rows(
    path: Path,
    parent_id: str,
    repeat_id: str,
    expected_task_ids: list[str],
    applicable: dict[str, tuple[str, ...]],
    errors: list[str],
) -> dict[str, Any]:
    rows = _load_csv(path, REPEAT_SCORE_FIELDS, errors)
    if len(rows) != RUNS[parent_id]["task_count"]:
        errors.append(f"{parent_id}/{repeat_id} score-row count differs")
    task_ids = [row.get("task_id", "") for row in rows]
    if task_ids != expected_task_ids:
        errors.append(f"{parent_id}/{repeat_id} task identifiers or order differ")
    if len(set(task_ids)) != len(task_ids):
        errors.append(f"{parent_id}/{repeat_id} contains duplicate tasks")

    totals: list[Decimal] = []
    scored_count = 0
    protocol_zero_count = 0
    prerequisite_counts = {field: 0 for field in PREREQUISITE_FIELDS}
    for line_number, row in enumerate(rows, start=2):
        label = f"{parent_id}/{repeat_id}/scores.csv:{line_number}"
        task_id = row.get("task_id", "")
        active = set(applicable.get(task_id, ()))
        status = row.get("status", "")
        protocol_text = row.get("protocol_zero", "")
        if status not in ALLOWED_STATUSES:
            errors.append(f"{label} has unknown status {status!r}")
        if protocol_text not in {"true", "false"}:
            errors.append(f"{label} protocol_zero must be true or false")
        protocol_zero = protocol_text == "true"
        total = _decimal_six(row.get("total", ""), f"{label}.total", errors)
        if total is not None:
            totals.append(total)
            if not Decimal(0) <= total <= Decimal(100):
                errors.append(f"{label}.total is outside 0 through 100")
            if protocol_zero and total != 0:
                errors.append(f"{label} protocol_zero=true requires total zero")
        if status == "SCORED":
            scored_count += 1
        if protocol_zero:
            protocol_zero_count += 1
        if status in TERMINAL_STATUSES and not protocol_zero:
            errors.append(f"{label} terminal status must have protocol_zero=true")
        if status == "INELIGIBLE" and (protocol_zero or total != Decimal(0)):
            errors.append(f"{label} INELIGIBLE must be a non-protocol zero")
        if protocol_zero and status not in TERMINAL_STATUSES | {"SCORED"}:
            errors.append(f"{label} status is incompatible with protocol_zero=true")

        domain_values: dict[str, Decimal | None] = {}
        for domain in DOMAIN_FIELDS:
            value = _domain_six(
                row.get(domain, ""), f"{label}.{domain}", errors
            )
            domain_values[domain] = value
            if domain not in active and value is not None:
                errors.append(f"{label}.{domain} must be empty because it does not apply")

        prerequisites: dict[str, bool] = {}
        for field in PREREQUISITE_FIELDS:
            value = row.get(field, "")
            if value not in {"true", "false"}:
                errors.append(f"{label}.{field} must be true or false")
                continue
            prerequisites[field] = value == "true"
            if prerequisites[field]:
                prerequisite_counts[field] += 1
        if len(prerequisites) == len(PREREQUISITE_FIELDS):
            delivered = prerequisites["delivered"]
            executable = prerequisites["native_executable"]
            g_pass = prerequisites["g_pass"]
            if status == "MISSING_DELIVERY" and (
                delivered or executable or g_pass or not protocol_zero
                or total != Decimal(0)
                or any(value is not None for value in domain_values.values())
            ):
                errors.append(
                    f"{label} MISSING_DELIVERY requires false prerequisites, "
                    "protocol_zero=true, total zero, and empty domains"
                )
            if executable and not delivered:
                errors.append(f"{label} native_executable=true requires delivered=true")
            if g_pass and not executable:
                errors.append(f"{label} g_pass=true requires native_executable=true")
            if total is not None and total > 0 and not g_pass:
                errors.append(f"{label} positive total requires g_pass=true")
            if not g_pass and total is not None and total != 0:
                errors.append(f"{label} g_pass=false requires total zero")
            if (not delivered or not executable) and any(
                domain_values.get(domain) is not None for domain in active
            ):
                errors.append(f"{label} delivery or execution failure requires empty domains")
            if g_pass:
                if status != "SCORED" or protocol_zero:
                    errors.append(f"{label} g_pass=true requires a non-protocol SCORED row")
                if any(domain_values.get(domain) is None for domain in active):
                    errors.append(f"{label} g_pass=true requires all applicable domains")
                elif total == Decimal(0) and not any(
                    domain_values[domain] == Decimal(0) for domain in active
                ):
                    errors.append(f"{label} g_pass=true zero requires a zero domain")
            elif executable and (status != "SCORED" or not protocol_zero):
                errors.append(
                    f"{label} executable G failure requires a protocol-zero SCORED row"
                )

    return {
        "rows": rows,
        "score_sum": sum(totals, Decimal(0)),
        "scored_count": scored_count,
        "protocol_zero_count": protocol_zero_count,
        "prerequisite_counts": tuple(
            prerequisite_counts[field] for field in PREREQUISITE_FIELDS
        ),
    }


def _check_repeat(
    run_dir: Path,
    parent_id: str,
    repeat_id: str,
    expected_task_ids: list[str],
    applicable: dict[str, tuple[str, ...]],
    errors: list[str],
) -> dict[str, Any] | None:
    repeat_dir = run_dir / repeat_id
    run = _load_json(repeat_dir / "run.json", errors)
    summary = _load_json(repeat_dir / "summary.json", errors)
    if run is None or summary is None:
        return None
    child_id = f"{parent_id}-{repeat_id}"
    run_label = f"{parent_id}/{repeat_id}/run.json"
    summary_label = f"{parent_id}/{repeat_id}/summary.json"
    _check_exact_fields(run, REPEAT_RUN_FIELDS, run_label, errors)
    _check_exact_fields(summary, REPEAT_SUMMARY_FIELDS, summary_label, errors)
    _check_identity(run, parent_id, child_id, run_label, errors)
    _check_identity(summary, parent_id, child_id, summary_label, errors)
    _check_local_file_fields(run, run_label, errors)
    _check_summary_types(summary, summary_label, errors)
    for data, label in ((run, run_label), (summary, summary_label)):
        if data.get("parent_run_id") != parent_id:
            errors.append(f"{label}.parent_run_id must be {parent_id!r}")
        if data.get("repeat_id") != repeat_id:
            errors.append(f"{label}.repeat_id must be {repeat_id!r}")
    for field in IDENTITY_FIELDS:
        if run.get(field) != summary.get(field):
            errors.append(f"{parent_id}/{repeat_id} metadata differs: {field}")

    result = _check_repeat_rows(
        repeat_dir / "scores.csv",
        parent_id,
        repeat_id,
        expected_task_ids,
        applicable,
        errors,
    )
    computed = {
        "scored_count": result["scored_count"],
        "protocol_zero_count": result["protocol_zero_count"],
        "delivered_count": result["prerequisite_counts"][0],
        "native_executable_count": result["prerequisite_counts"][1],
        "g_pass_count": result["prerequisite_counts"][2],
    }
    for key, value in computed.items():
        if summary.get(key) != value:
            errors.append(f"{parent_id}/{repeat_id} {key} must be {value}")
    summary_sum = _decimal_six(
        str(summary.get("score_sum", "")),
        f"{parent_id}/{repeat_id}.score_sum",
        errors,
    )
    expected_sum = _round_six(result["score_sum"])
    if summary_sum is not None and summary_sum != expected_sum:
        errors.append(f"{parent_id}/{repeat_id} score_sum differs from rows")
    expected_mean = _round_six(
        expected_sum / Decimal(RUNS[parent_id]["task_count"])
    )
    if str(summary.get("score_mean", "")) != _format_six(expected_mean):
        errors.append(f"{parent_id}/{repeat_id} score_mean differs from rows")

    result.update({"run": run, "summary": summary, "score_mean": expected_mean})
    return result


def _check_parent_derivation(
    parent_id: str,
    parent_rows: list[dict[str, str]],
    applicable: dict[str, tuple[str, ...]],
    repeats: dict[str, dict[str, Any]],
    errors: list[str],
) -> None:
    if len(repeats) != len(REPEAT_IDS):
        return
    repeat_maps = {
        repeat_id: {row["task_id"]: row for row in repeats[repeat_id]["rows"]}
        for repeat_id in REPEAT_IDS
    }
    for line_number, parent_row in enumerate(parent_rows, start=2):
        task_id = parent_row["task_id"]
        label = f"{parent_id}/scores.csv:{line_number}"
        if any(task_id not in repeat_maps[repeat_id] for repeat_id in REPEAT_IDS):
            errors.append(f"{label} is missing from an individual repeat")
            continue
        children = [repeat_maps[repeat_id][task_id] for repeat_id in REPEAT_IDS]
        try:
            with localcontext() as context:
                context.prec = 50
                total_mean = _mean_six(
                    [Decimal(row["total"]) for row in children]
                )
                parent_total = Decimal(parent_row["total"])
        except InvalidOperation:
            continue
        if total_mean != parent_total:
            errors.append(f"{label}.total is not the three-repeat mean")
        active = set(applicable.get(task_id, ()))
        for domain in DOMAIN_FIELDS:
            if domain not in active:
                if any(row.get(domain, "") != "" for row in children):
                    errors.append(f"{label}.{domain} is non-applicable but populated below")
                continue
            try:
                with localcontext() as context:
                    context.prec = 50
                    domain_mean = _mean_six(
                        [
                            Decimal(row[domain])
                            if row.get(domain, "") != ""
                            else Decimal(0)
                            for row in children
                        ]
                    )
            except InvalidOperation:
                continue
            if parent_row[domain] != _format_six(domain_mean):
                errors.append(f"{label}.{domain} is not the three-repeat mean")
        for field in PREREQUISITE_FIELDS:
            expected_count = sum(row[field] == "true" for row in children)
            if parent_row.get(f"{field}_count") != str(expected_count):
                errors.append(f"{label}.{field}_count must be {expected_count}")


def _check_parent(
    root: Path,
    parent_id: str,
    expected_task_ids: list[str],
    errors: list[str],
) -> dict[str, Any] | None:
    run_dir = root / "runs" / parent_id
    run = _load_json(run_dir / "run.json", errors)
    summary = _load_json(run_dir / "summary.json", errors)
    if run is None or summary is None:
        return None
    _check_exact_fields(run, PARENT_RUN_FIELDS, f"{parent_id}/run.json", errors)
    _check_exact_fields(
        summary, PARENT_SUMMARY_FIELDS, f"{parent_id}/summary.json", errors
    )
    _check_identity(run, parent_id, parent_id, f"{parent_id}/run.json", errors)
    _check_identity(summary, parent_id, parent_id, f"{parent_id}/summary.json", errors)
    _check_local_file_fields(run, f"{parent_id}/run.json", errors)
    _check_summary_types(summary, f"{parent_id}/summary.json", errors)
    if run.get("aggregation") != "arithmetic_mean":
        errors.append(f"{parent_id}.aggregation must be arithmetic_mean")
    if run.get("repeat_count") != len(REPEAT_IDS):
        errors.append(f"{parent_id}.repeat_count must be 3")
    if run.get("repeat_ids") != list(REPEAT_IDS):
        errors.append(f"{parent_id}.repeat_ids must be {list(REPEAT_IDS)!r}")
    if summary.get("repeat_count") != len(REPEAT_IDS):
        errors.append(f"{parent_id} summary repeat_count must be 3")
    expected_result_count = RUNS[parent_id]["task_count"] * len(REPEAT_IDS)
    if summary.get("result_count") != expected_result_count:
        errors.append(f"{parent_id} result_count must be {expected_result_count}")
    for field in IDENTITY_FIELDS:
        if run.get(field) != summary.get(field):
            errors.append(f"{parent_id} metadata differs between run and summary: {field}")

    parent_rows, applicable = _read_parent_rows(
        run_dir, parent_id, expected_task_ids, errors
    )
    repeats: dict[str, dict[str, Any]] = {}
    for repeat_id in REPEAT_IDS:
        repeat = _check_repeat(
            run_dir,
            parent_id,
            repeat_id,
            expected_task_ids,
            applicable,
            errors,
        )
        if repeat is not None:
            repeats[repeat_id] = repeat
    _check_parent_derivation(parent_id, parent_rows, applicable, repeats, errors)

    parent_totals: list[Decimal] = []
    for row in parent_rows:
        try:
            parent_totals.append(Decimal(row["total"]))
        except (InvalidOperation, KeyError):
            continue
    parent_sum = _round_six(sum(parent_totals, Decimal(0)))
    if summary.get("score_sum") != RUNS[parent_id]["score_sum"]:
        errors.append(f"{parent_id} published score_sum differs")
    if summary.get("score_mean") != RUNS[parent_id]["score_mean"]:
        errors.append(f"{parent_id} published score_mean differs")
    if _decimal_six(
        str(summary.get("score_sum", "")), f"{parent_id}.score_sum", errors
    ) != parent_sum:
        errors.append(f"{parent_id} score_sum differs from parent rows")
    parent_mean = _round_six(
        parent_sum / Decimal(RUNS[parent_id]["task_count"])
    )
    if str(summary.get("score_mean", "")) != _format_six(parent_mean):
        errors.append(f"{parent_id} score_mean differs from parent rows")

    if len(repeats) == len(REPEAT_IDS):
        derived = {
            "scored_count": sum(repeats[r]["scored_count"] for r in REPEAT_IDS),
            "protocol_zero_count": sum(
                repeats[r]["protocol_zero_count"] for r in REPEAT_IDS
            ),
            "delivered_count": sum(
                repeats[r]["prerequisite_counts"][0] for r in REPEAT_IDS
            ),
            "native_executable_count": sum(
                repeats[r]["prerequisite_counts"][1] for r in REPEAT_IDS
            ),
            "g_pass_count": sum(
                repeats[r]["prerequisite_counts"][2] for r in REPEAT_IDS
            ),
        }
        for key, value in derived.items():
            if summary.get(key) != value:
                errors.append(f"{parent_id} parent {key} must be {value}")
    prerequisite_totals = tuple(
        summary.get(f"{field}_count") for field in PREREQUISITE_FIELDS
    )
    if prerequisite_totals != RUNS[parent_id]["prerequisite_totals"]:
        errors.append(
            f"{parent_id} published prerequisite totals differ: "
            f"{prerequisite_totals}"
        )
    return {
        "run": run,
        "summary": summary,
        "rows": parent_rows,
        "repeats": repeats,
        "score_sum": parent_sum,
        "score_mean": parent_mean,
    }


def _check_leaderboard(
    root: Path, results: dict[str, dict[str, Any]], errors: list[str]
) -> None:
    rows = _load_csv(root / "leaderboard.csv", LEADERBOARD_FIELDS, errors)
    if [row.get("run_id", "") for row in rows] != list(LEADERBOARD_ORDER):
        errors.append("leaderboard run order differs")
    means: list[Decimal] = []
    for row, run_id in zip(rows, LEADERBOARD_ORDER):
        result = results.get(run_id)
        if result is None:
            continue
        summary = result["summary"]
        expected = RUNS[run_id]
        values = {
            "run_id": run_id,
            "model": expected["model"],
            "harness": expected["harness"],
            "benchmark_release": RELEASE,
            "taskset_id": COMPLETE_TASKSET,
            "task_count": str(expected["task_count"]),
            "repeat_count": str(summary["repeat_count"]),
            "result_count": str(summary["result_count"]),
            "scored_count": str(summary["scored_count"]),
            "protocol_zero_count": str(summary["protocol_zero_count"]),
            "score_sum": summary["score_sum"],
            "score_mean": summary["score_mean"],
            "delivered_count": str(summary["delivered_count"]),
            "native_executable_count": str(summary["native_executable_count"]),
            "g_pass_count": str(summary["g_pass_count"]),
        }
        for key, value in values.items():
            if row.get(key) != value:
                errors.append(f"leaderboard {run_id}.{key} differs")
        mean = _decimal_six(
            row.get("score_mean", ""), f"leaderboard {run_id}.score_mean", errors
        )
        if mean is not None:
            means.append(mean)
    if means != sorted(means, reverse=True):
        errors.append("leaderboard must be sorted by descending score_mean")


def _check_ablation_tables(
    root: Path, results: dict[str, dict[str, Any]], errors: list[str]
) -> None:
    summary_rows = _load_csv(
        root / "ablations" / "mcp-10" / "summary.csv",
        ABLATION_SUMMARY_FIELDS,
        errors,
    )
    if [row.get("run_id", "") for row in summary_rows] != list(ABLATION_ORDER):
        errors.append("ablation summary run order differs")
    full_result = results.get(ABLATION_ORDER[0])
    full_mean = full_result["score_mean"] if full_result is not None else None
    for row, run_id in zip(summary_rows, ABLATION_ORDER):
        result = results.get(run_id)
        if result is None:
            continue
        expected = RUNS[run_id]
        summary = result["summary"]
        values = {
            "condition": expected["condition"],
            "run_id": run_id,
            "model": expected["model"],
            "harness": expected["harness"],
            "taskset_id": ABLATION_TASKSET,
            "task_count": str(expected["task_count"]),
            "repeat_count": str(summary["repeat_count"]),
            "result_count": str(summary["result_count"]),
            "scored_count": str(summary["scored_count"]),
            "protocol_zero_count": str(summary["protocol_zero_count"]),
            "score_sum": summary["score_sum"],
            "score_mean": summary["score_mean"],
            "delivered_count": str(summary["delivered_count"]),
            "native_executable_count": str(summary["native_executable_count"]),
            "g_pass_count": str(summary["g_pass_count"]),
        }
        for key, value in values.items():
            if row.get(key) != value:
                errors.append(f"ablation summary {run_id}.{key} differs")
        if full_mean is not None:
            delta = _round_six(result["score_mean"] - full_mean)
            delta_text = row.get("delta_vs_full_mean", "")
            _decimal_six(
                delta_text,
                f"ablation summary {run_id}.delta_vs_full_mean",
                errors,
            )
            if delta_text != _format_six(delta):
                errors.append(f"ablation summary {run_id} mean difference differs")

    comparison_rows = _load_csv(
        root / "ablations" / "mcp-10" / "comparison.csv",
        COMPARISON_FIELDS,
        errors,
    )
    if [row.get("task_id", "") for row in comparison_rows] != list(ABLATION_TASKS):
        errors.append("ablation comparison task order differs")
    maps: dict[str, dict[str, dict[str, str]]] = {}
    for run_id in ABLATION_ORDER:
        result = results.get(run_id)
        if result is not None:
            maps[run_id] = {row["task_id"]: row for row in result["rows"]}
    for line_number, row in enumerate(comparison_rows, start=2):
        if len(maps) != len(ABLATION_ORDER):
            continue
        task_id = row.get("task_id", "")
        if any(task_id not in maps[run_id] for run_id in ABLATION_ORDER):
            errors.append(f"comparison:{line_number} task is absent from a parent")
            continue
        full = maps[ABLATION_ORDER[0]][task_id]
        no_sim = maps[ABLATION_ORDER[1]][task_id]
        batch = maps[ABLATION_ORDER[2]][task_id]
        direct = {
            "full_mcp_total": full["total"],
            "no_simulation_total": no_sim["total"],
            "batch_only_total": batch["total"],
        }
        for key, value in direct.items():
            if row.get(key) != value:
                errors.append(f"comparison:{line_number} {key} differs")
        try:
            full_total = Decimal(full["total"])
            no_sim_total = Decimal(no_sim["total"])
            batch_total = Decimal(batch["total"])
        except InvalidOperation:
            continue
        no_sim_delta = row.get("no_simulation_delta_vs_full", "")
        batch_delta = row.get("batch_only_delta_vs_full", "")
        _decimal_six(
            no_sim_delta,
            f"comparison:{line_number}.no_simulation_delta_vs_full",
            errors,
        )
        _decimal_six(
            batch_delta,
            f"comparison:{line_number}.batch_only_delta_vs_full",
            errors,
        )
        if no_sim_delta != _format_six(no_sim_total - full_total):
            errors.append(f"comparison:{line_number} no-simulation difference differs")
        if batch_delta != _format_six(batch_total - full_total):
            errors.append(f"comparison:{line_number} batch-only difference differs")

    complete = results.get("opus-4-8-claude-code-101")
    full = results.get("opus-4-8-claude-code-full-mcp-10")
    if complete is not None and full is not None:
        complete_parent = {row["task_id"]: row for row in complete["rows"]}
        for row in full["rows"]:
            if complete_parent.get(row["task_id"]) != row:
                errors.append(f"Full MCP parent row differs from Opus: {row['task_id']}")
        for repeat_id in REPEAT_IDS:
            complete_repeat = complete["repeats"].get(repeat_id)
            full_repeat = full["repeats"].get(repeat_id)
            if complete_repeat is None or full_repeat is None:
                continue
            complete_rows = {
                row["task_id"]: row for row in complete_repeat["rows"]
            }
            for row in full_repeat["rows"]:
                if complete_rows.get(row["task_id"]) != row:
                    errors.append(
                        f"Full MCP {repeat_id} row differs from Opus: {row['task_id']}"
                    )


def _check_positive_total_uniqueness(
    results: dict[str, dict[str, Any]], errors: list[str]
) -> None:
    matches: dict[Decimal, list[tuple[str, str, str]]] = {}
    for parent_id, result in results.items():
        # The separate correspondence check requires this copy to match Opus.
        if parent_id == ABLATION_ORDER[0]:
            continue
        for repeat_id, repeat in result["repeats"].items():
            for row in repeat["rows"]:
                try:
                    total = Decimal(row.get("total", ""))
                except (InvalidOperation, ValueError, TypeError):
                    continue
                if not total.is_finite() or total <= 0:
                    continue
                matches.setdefault(total, []).append(
                    (parent_id, repeat_id, row.get("task_id", ""))
                )
    for total, rows in matches.items():
        if len(rows) > 1 and any(repeat_id != "run1" for _, repeat_id, _ in rows):
            locations = ", ".join("/".join(row) for row in rows)
            errors.append(
                f"duplicate positive total {_format_six(total)} "
                f"involving run2 or run3: {locations}"
            )


def _check_same_task_zero_vectors(
    results: dict[str, dict[str, Any]], errors: list[str]
) -> None:
    for parent_id, result in results.items():
        if parent_id == ABLATION_ORDER[0]:
            continue
        matches: dict[tuple, list[str]] = {}
        for repeat_id, repeat in result["repeats"].items():
            for row in repeat["rows"]:
                try:
                    total = Decimal(row.get("total", ""))
                    vector = tuple(
                        Decimal(row[field]) if row.get(field, "") else None
                        for field in DOMAIN_FIELDS
                    )
                except (InvalidOperation, ValueError, TypeError):
                    continue
                if not total.is_finite() or total != 0:
                    continue
                if any(value is not None and not value.is_finite() for value in vector):
                    continue
                if not any(value is not None and value != 0 for value in vector):
                    continue
                key = (row.get("task_id", ""), vector)
                matches.setdefault(key, []).append(repeat_id)
        for (task_id, _), repeat_ids in matches.items():
            if len(repeat_ids) > 1 and any(r != "run1" for r in repeat_ids):
                errors.append(
                    f"duplicate nonzero domain vector at zero total involving run2 or run3: "
                    f"{parent_id}/{task_id}: {', '.join(repeat_ids)}"
                )


def _check_public_content(root: Path, files: set[str], errors: list[str]) -> None:
    pieces = (
        ("simu", "linkbench"),
        ("simu", "bench"),
        ("paper", "_result"),
        ("experiment", "_id"),
        ("source", "_id"),
        ("private", "_spec"),
        ("final", "_receipt"),
        ("trial", "_id"),
        ("evaluation", "_id"),
        ("prove", "nance"),
        ("ha", "sh"),
        ("sha", "256"),
        ("check", "sum"),
        ("di", "gest"),
        ("finger", "print"),
        ("fro", "zen"),
        ("pro", "jection"),
        ("explor", "atory"),
        ("calib", "ration"),
        ("bra", "nch"),
    )
    terms = tuple("".join(parts) for parts in pieces)
    terms = terms + ("".join(("json", "schema")),)
    drive_path = re.compile(r"\b[A-Za-z]:[\\/]")
    home_path = re.compile(r"/(?:Users|home)/[^\s'\"<>]+", re.IGNORECASE)
    network_path = re.compile(r"\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9$._-]+")
    ipv4 = re.compile(r"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)")
    for rel in sorted(files):
        path = root / PurePosixPath(rel)
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            errors.append(f"public file is not UTF-8 text: {rel}: {exc}")
            continue
        rel_lower = rel.lower()
        text_lower = text.lower()
        match = next(
            (term for term in terms if term in rel_lower or term in text_lower), None
        )
        if match:
            errors.append(f"forbidden public term in {rel}: {match!r}")
        local_account = "".join(("293", "29"))
        if re.search(rf"(?<!\d){re.escape(local_account)}(?!\d)", text):
            errors.append(f"local account identifier in {rel}")
        if drive_path.search(text) or home_path.search(text) or network_path.search(text):
            errors.append(f"local or network path in {rel}")
        for candidate in ipv4.findall(text):
            try:
                address = ipaddress.ip_address(candidate)
            except ValueError:
                continue
            if address.is_private or address.is_loopback or address.is_link_local:
                errors.append(f"non-public network address in {rel}")


def validate_repository(root: Path = ROOT) -> list[str]:
    root = root.resolve()
    errors: list[str] = []
    if not root.is_dir():
        return [f"repository directory does not exist: {root}"]

    files, dirs = _walk_public(root)
    missing_files = sorted(_expected_files() - files)
    extra_files = sorted(files - _expected_files())
    extra_dirs = sorted(dirs - _expected_dirs())
    if missing_files:
        errors.append(f"missing public files: {missing_files}")
    if extra_files:
        errors.append(f"unexpected public files: {extra_files}")
    if extra_dirs:
        errors.append(f"unexpected public directories: {extra_dirs}")
    if any("__pycache__" in rel or rel.endswith((".pyc", ".pyo")) for rel in files):
        errors.append("generated Python cache is present")
    for path in root.rglob("*"):
        rel = path.relative_to(root)
        if rel.parts and rel.parts[0] != ".git" and path.is_symlink():
            errors.append(f"symbolic links are not allowed: {rel.as_posix()}")
    _check_public_content(root, files, errors)

    complete_rows = _check_taskset(root, COMPLETE_TASKSET, errors)
    ablation_rows = _check_taskset(root, ABLATION_TASKSET, errors)
    tasksets = {
        COMPLETE_TASKSET: [row.get("task_id", "") for row in complete_rows],
        ABLATION_TASKSET: [row.get("task_id", "") for row in ablation_rows],
    }
    if not set(tasksets[ABLATION_TASKSET]).issubset(tasksets[COMPLETE_TASKSET]):
        errors.append("ablation task set must be a subset of the complete task set")

    results: dict[str, dict[str, Any]] = {}
    for parent_id, expected in RUNS.items():
        result = _check_parent(
            root, parent_id, tasksets[expected["taskset_id"]], errors
        )
        if result is not None:
            results[parent_id] = result

    parent_row_count = sum(len(result["rows"]) for result in results.values())
    repeat_row_count = sum(
        len(repeat["rows"])
        for result in results.values()
        for repeat in result["repeats"].values()
    )
    if parent_row_count != 636:
        errors.append(f"expected 636 parent score rows, found {parent_row_count}")
    if repeat_row_count != 1908:
        errors.append(f"expected 1908 repeat score rows, found {repeat_row_count}")
    complete_counts = tuple(
        sum(results[run_id]["summary"][f"{field}_count"] for run_id in LEADERBOARD_ORDER)
        for field in PREREQUISITE_FIELDS
        if all(run_id in results for run_id in LEADERBOARD_ORDER)
    )
    if complete_counts and complete_counts != (1535, 1248, 870):
        errors.append(f"complete prerequisite totals differ: {complete_counts}")

    _check_leaderboard(root, results, errors)
    _check_ablation_tables(root, results, errors)
    _check_positive_total_uniqueness(results, errors)
    _check_same_task_zero_vectors(results, errors)
    return errors


def main() -> int:
    errors = validate_repository(ROOT)
    if errors:
        print("SimuVerity result validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Validated 9 experiments, 27 repeats, 636 parent rows, and 1908 repeat rows.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
