#!/usr/bin/env python3
"""Strict-geometric XMED-08 outer aggregation without cap/floor metadata."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xmed08_scoring_core_core as current


WEIGHTS = current.base.WEIGHTS
POLICY_ID = 'simuverity-101-v1:f90-xmed-08:scoring'


def strict_geometric(groups: dict[str, float], weights: dict[str, float], gate: bool = True) -> float:
    values = {name: float(groups[name]) for name in weights}
    if any(not math.isfinite(value) or not 0.0 <= value <= 1.0 for value in values.values()):
        raise ValueError("group scores must be finite and in [0,1]")
    if not gate or any(value <= 0.0 for value in values.values()):
        return 0.0
    return 100.0 * math.exp(sum(weights[name] * math.log(values[name]) for name in weights))


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = current.score_evidence(evidence)
    gate = bool(result["G"])
    total = strict_geometric(result["groups"], WEIGHTS, gate)
    result.update(
        {
            "schema": "simuverity.f90-xmed08-score.v1",
            "policy_id": POLICY_ID,
            "group_weights": dict(WEIGHTS),
            "score": total,
            "total": total,
            "group_internal_shortcut_rules": [],
            "total_aggregation": {
                "method": "G_times_strict_weighted_geometric_mean",
                "strict_zero_rule": "any_applicable_group_le_zero_means_total_zero",
                "not_applicable_groups_excluded": True,
                "epsilon_floor": "none",
                "post_total_cap_floor_or_override": "none",
            },
        }
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = score_evidence(json.loads(args.evidence.read_text(encoding="utf-8")))
    out = args.out or args.evidence.with_name("score.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"score": result["score"], "groups": result["groups"], "out": str(out)}))


if __name__ == "__main__":
    main()
