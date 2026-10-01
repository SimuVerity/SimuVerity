#!/usr/bin/env python3
"""XROBO-03 current: strict geometric total with no post-group score cap."""

from __future__ import annotations

import argparse
import math
from typing import Any

from f90_xrobo03_metric_identity import read_json, write_json
from f90_xrobo03_group_aggregation import score_evidence_with_upright_aggregation


SCORE_SCHEMA = "simuverity.f90-xrobo03-offline-score.v1"
POLICY_ID = 'simuverity-101-v1:f90-xrobo-03:scoring'


def weighted_geometric_total(
    group_scores: dict[str, float | None], weights: dict[str, float]
) -> float:
    applicable = {
        name: (float(group_scores[name]), float(weight))
        for name, weight in weights.items()
        if name in group_scores and group_scores[name] is not None and float(weight) > 0.0
    }
    if not applicable:
        raise ValueError("no applicable weighted groups")
    weight_sum = sum(weight for _, weight in applicable.values())
    if not math.isfinite(weight_sum) or weight_sum <= 0.0:
        raise ValueError("invalid applicable weight sum")
    if any(
        not math.isfinite(score) or score < 0.0 or score > 1.0
        for score, _ in applicable.values()
    ):
        raise ValueError("group scores must be finite and in [0, 1]")
    if any(score <= 0.0 for score, _ in applicable.values()):
        return 0.0
    return 100.0 * math.exp(
        sum((weight / weight_sum) * math.log(score) for score, weight in applicable.values())
    )


def geometric_total(
    gate: bool,
    group_scores: dict[str, float | None],
    weights: dict[str, float],
) -> float:
    return weighted_geometric_total(group_scores, weights) if gate else 0.0


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = score_evidence_with_upright_aggregation(evidence)
    total = geometric_total(bool(result.get("G")), result["groups"], result["group_weights"])
    result["schema"] = SCORE_SCHEMA
    result["policy_id"] = POLICY_ID
    result["raw_total"] = total
    result["total"] = total
    result["score"] = total
    result["total_aggregation"] = {
        "method": "G_times_weighted_geometric_mean",
        "formula": "G*100*product(group_score^(weight/sum_applicable_weights))",
        "not_applicable_groups_excluded": True,
        "strict_zero_rule": "any_applicable_group_le_zero_means_total_zero",
        "post_group_score_cap": "none",
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = score_evidence(read_json(args.evidence))
    write_json(args.output, result)
    print(
        f"F90_XROBO03_OFFLINE_SCORE total={result['total']:.9f} "
        f"G={int(result['G'])} status=GEOMETRIC_NO_POST_CAP"
    )


if __name__ == "__main__":
    main()
