#!/usr/bin/env python3
"""Field-quality-sensitive, strict-geometric XTHERM-05 scorer.

The task requires 24 meaningful battery and 24 meaningful plate temperature
fields.  Q weights plate-field uniformity directly alongside channel
distinctness and dynamic response.  The total uses the declared A/Q/M/R/D
weights and strict geometric aggregation without a post-total cap.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path

import f90_xtherm05_mechanism_scoring as GROUP_SCORING

WEIGHTS = {"A": .20, "Q": .25, "M": .22, "R": .23, "D": .10}
Q_WEIGHTS = {
    "battery_uniformity": .30,
    "plate_uniformity": .35,
    "tail_drift": .10,
    "battery_spatial_field": .125,
    "plate_spatial_field": .125,
}


def _strict_geometric(groups: dict[str, float], gate: bool) -> float:
    if not gate or any(groups[name] <= 0.0 for name in WEIGHTS):
        return 0.0
    return 100.0 * math.prod(groups[name] ** weight for name, weight in WEIGHTS.items())


def score_evidence(evidence: dict) -> dict:
    result = copy.deepcopy(GROUP_SCORING.score_evidence(evidence))
    gate = bool(result["G"])
    q_utilities = result.get("utility_metrics", {}).get("Q", {})
    q = (
        GROUP_SCORING._bottleneck(
            [float(q_utilities[name]) for name in Q_WEIGHTS],
            list(Q_WEIGHTS.values()),
        )
        if gate and all(name in q_utilities for name in Q_WEIGHTS)
        else 0.0
    )
    groups = {
        "A": float(result["groups"]["A"]),
        "Q": float(q),
        "M": float(result["groups"]["M"]),
        "R": float(result["groups"]["R"]),
        "D": float(result["groups"]["D"]),
    }
    total = _strict_geometric(groups, gate)
    failures = [
        str(reason) for reason in result.get("failure_reasons", [])
        if not str(reason).startswith("Q temperature-field quality")
    ]
    if gate and q < .60:
        failures.append(f"Q temperature-field quality group below 0.60: {q:.4f}")
    result.update({
        "schema": "simuverity.f90-xtherm05-score.v1",
        "policy_id": "simuverity-101-v1:f90-xtherm-05:scoring",
        "groups": {"G": 1.0 if gate else 0.0, **groups},
        "group_weights": WEIGHTS,
        "formula": "G*100*A^0.20*Q^0.25*M^0.22*R^0.23*D^0.10",
        "aggregation": {
            "method": "G_times_strict_weighted_geometric_mean",
            "post_total_cap": "none",
            "zero_rule": "any applicable group equal to zero yields total zero",
        },
        "raw_total": total,
        "total": total,
        "score": total,
        "failure_reasons": failures,
    })
    result.setdefault("utility_metrics", {})["Q_weights"] = Q_WEIGHTS
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    args = parser.parse_args()
    result = score_evidence(json.loads(args.evidence.read_text(encoding="utf-8-sig")))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
