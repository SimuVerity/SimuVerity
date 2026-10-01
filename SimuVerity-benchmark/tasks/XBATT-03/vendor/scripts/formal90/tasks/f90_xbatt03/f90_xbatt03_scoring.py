#!/usr/bin/env python3
"""XBATT-03 strict geometric aggregation without epsilon or caps."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xbatt03_scoring_core as core


WEIGHTS = core.WEIGHTS


def strict_geometric(groups: dict[str, float], weights: dict[str, float]) -> float:
    values = {name: float(groups[name]) for name in weights}
    if any(not math.isfinite(value) or value < 0.0 or value > 1.0 for value in values.values()):
        raise ValueError("group scores must be finite and in [0, 1]")
    if any(value <= 0.0 for value in values.values()):
        return 0.0
    return 100.0 * math.exp(sum(weights[name] * math.log(values[name]) for name in weights))


def score(evidence_path: Path) -> dict[str, Any]:
    result = core.score(evidence_path)
    gate = bool(result["G"])
    groups = {name: float(result["groups"][name]) for name in WEIGHTS}
    total = strict_geometric(groups, WEIGHTS) if gate else 0.0
    result["schema"] = "simuverity.f90-xbatt03-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xbatt-03:scoring"
    result["score"] = total
    result["total"] = total
    result["weights"] = dict(WEIGHTS)
    result["admission_candidate"] = bool(gate and total >= 85.0)
    result["total_aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "formula": "G*100*product(group_score^weight)",
        "epsilon_floor": "none",
        "strict_zero_rule": "any_applicable_group_le_zero_means_total_zero",
        "post_group_score_cap": "none",
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = score(args.evidence)
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
