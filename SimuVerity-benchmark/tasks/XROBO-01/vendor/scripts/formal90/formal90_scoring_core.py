#!/usr/bin/env python3
"""Shared, process-free primitives for Formal90 task-local offline scorers.

This module intentionally contains no subprocess, MATLAB, simulation, network,
or filesystem mutation other than writing the requested JSON receipt.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


GROUP_NAMES = ("A", "Q", "M", "R", "D")


def finite(value: Any, fallback: float = 0.0) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return fallback
    return number if math.isfinite(number) else fallback


def clip(value: Any) -> float:
    return min(max(finite(value), 0.0), 1.0)


def utility(value: Any, anchors: Sequence[float], scores: Sequence[float]) -> float:
    """Exact process-free counterpart of scripts/xp9/xp9_utility.m."""
    number = finite(value, math.nan)
    if (
        not math.isfinite(number)
        or len(anchors) != len(scores)
        or len(anchors) < 2
        or any(float(b) <= float(a) for a, b in zip(anchors, anchors[1:]))
    ):
        return 0.0
    number = min(max(number, float(anchors[0])), float(anchors[-1]))
    for index in range(1, len(anchors)):
        left = float(anchors[index - 1])
        right = float(anchors[index])
        if number <= right:
            fraction = (number - left) / (right - left)
            return clip(float(scores[index - 1]) + fraction * (
                float(scores[index]) - float(scores[index - 1])
            ))
    return clip(scores[-1])


def group(values: Iterable[Any], weights: Iterable[Any]) -> float:
    """Exact process-free counterpart of scripts/xp9/xp9_group.m."""
    value_list = [clip(value) for value in values]
    weight_list = [finite(weight, math.nan) for weight in weights]
    if (
        not value_list
        or len(value_list) != len(weight_list)
        or any(not math.isfinite(weight) or weight < 0 for weight in weight_list)
        or sum(weight_list) <= 0
    ):
        return 0.0
    return sum(value * weight for value, weight in zip(value_list, weight_list)) / sum(
        weight_list
    )


def tail(values: Iterable[Any]) -> float:
    """Exact current XP9 required-scenario rule: the complete-suite minimum."""
    value_list = [clip(value) for value in values]
    return min(value_list) if value_list else 0.0


def total(gate: bool, groups: Sequence[Any], weights: Sequence[Any]) -> float:
    """Exact process-free counterpart of scripts/xp9/xp9_total.m."""
    value_list = [clip(value) for value in groups]
    weight_list = [finite(weight, math.nan) for weight in weights]
    if (
        not gate
        or not value_list
        or len(value_list) != len(weight_list)
        or any(not math.isfinite(weight) or weight < 0 for weight in weight_list)
        or sum(weight_list) <= 0
        or any(value == 0 for value in value_list)
    ):
        return 0.0
    denominator = sum(weight_list)
    result = 100.0 * math.prod(
        max(value, 1e-12) ** (weight / denominator)
        for value, weight in zip(value_list, weight_list)
    )
    return min(max(float(result), 0.0), 100.0)


def load_evidence(path: Path, task_id: str) -> dict[str, Any]:
    evidence = json.loads(path.read_text(encoding="utf-8"))
    if evidence.get("formal_task_id") != task_id:
        raise ValueError(
            f"task mismatch: expected {task_id}, got {evidence.get('formal_task_id')}"
        )
    if not isinstance(evidence.get("facts"), dict):
        raise ValueError("facts object missing")
    return evidence


def rows_by_id(evidence: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    rows = evidence["facts"].get("scenario_rows", [])
    return {str(row.get("scenario", row.get("id", ""))): row for row in rows}


def weights(evidence: Mapping[str, Any]) -> list[float]:
    source = evidence.get("group_weights", {})
    return [finite(source.get(name)) for name in GROUP_NAMES]


def base_receipt(
    evidence_path: Path,
    evidence: Mapping[str, Any],
    groups: Mapping[str, Any],
    score: float,
    *,
    policy_id: str,
    gate_reasons: Sequence[Any] | None = None,
    gate_override: bool | None = None,
) -> dict[str, Any]:
    gate = (
        bool(evidence["facts"].get("score_inputs_valid", False))
        if gate_override is None
        else bool(gate_override)
    )
    normalized_groups = {"G": int(gate)}
    normalized_groups.update({name: clip(groups.get(name, 0.0)) for name in GROUP_NAMES})
    reason_source = (
        gate_reasons
        if gate_reasons is not None
        else evidence["facts"].get("gate_reasons", [])
    )
    if isinstance(reason_source, (str, int, float, bool)):
        reason_source = [reason_source]
    reasons = [str(reason) for reason in reason_source if str(reason)]
    return {
        "schema": "simuverity.formal90-offline-score.v1",
        "formal_task_id": evidence["formal_task_id"],
        "policy_id": policy_id,
        "offline_only": True,
        "score_inputs_valid": gate,
        "diagnostics_valid": bool(evidence["facts"].get("diagnostics_valid", gate)),
        "G": gate,
        "groups": normalized_groups,
        "A": normalized_groups["A"],
        "Q": normalized_groups["Q"],
        "M": normalized_groups["M"],
        "R": normalized_groups["R"],
        "D": normalized_groups["D"],
        "score": min(max(finite(score), 0.0), 100.0),
        "gate_reasons": reasons,
        "failure_reasons": reasons,
    }


def parser(task_id: str) -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=f"Offline scorer for {task_id}")
    result.add_argument("evidence", type=Path)
    result.add_argument("output", type=Path)
    return result


def write_receipt(path: Path, receipt: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(receipt, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
