#!/usr/bin/env python3
"""Strict-geometric XMECH-02 scorer without post-total cap metadata."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xmech02_scoring_core as current


def strict_geometric(groups: dict[str, float], weights: dict[str, float], gate: bool = True) -> float:
    values = {name: float(groups[name]) for name in weights}
    if any(not math.isfinite(value) or not 0.0 <= value <= 1.0 for value in values.values()):
        raise ValueError("group scores must be finite and in [0,1]")
    if not gate or any(value <= 0.0 for value in values.values()):
        return 0.0
    return 100.0 * math.exp(sum(weights[name] * math.log(values[name]) for name in weights))


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = current.score_evidence(evidence)
    result.pop("applied_cap", None)
    gate = bool(result["G"])
    total = strict_geometric(result["groups"], result["group_weights"], gate)
    result.update(
        {
            "schema": "simuverity.f90-xmech02-score.v1",
            "policy_id": "simuverity-101-v1:f90-xmech-02:scoring",
            "raw_total": total,
            "total": total,
            "score": total,
            "threshold_pass": bool(gate and total >= current.ADMISSION_SCORE),
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    path = Path(args.evidence)
    result = score_evidence(json.loads(path.read_text(encoding="utf-8")))
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
