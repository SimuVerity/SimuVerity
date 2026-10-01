#!/usr/bin/env python3
"""XROBO-03 scorer with upright-critical group aggregation.

The public objective requires sustained forward locomotion *while remaining
upright*. Upright support therefore carries 60% of the within-A and
within-scenario behavior aggregation. The remaining 40% is the weighted
composite of the other performance metrics.
"""

from __future__ import annotations

import argparse
from typing import Any

from f90_xrobo03_structure_scoring import (
    GROUP_WEIGHTS,
    RANGE_SCENARIOS,
    row_map,
    stress_scenario_score,
    weighted_mean,
)
from f90_xrobo03_metric_identity import (
    read_json,
    score_evidence_with_unique_metrics,
    write_json,
)


SCORE_SCHEMA = "simuverity.f90-xrobo03-offline-score.v1"
POLICY_ID = 'simuverity-101-v1:f90-xrobo-03:scoring'
UPRIGHT_CRITICAL_WEIGHT = 0.60
OTHER_BEHAVIOR_WEIGHT = 0.40
A_OTHER_WEIGHTS = {
    "nominal_forward_displacement_m": 0.35,
    "nominal_mean_forward_speed_mps": 0.25,
    "nominal_positive_forward_fraction": 0.20,
}
STRESS_WEIGHTS = (1.2, 0.8, 1.2, 1.0, 0.6, 1.0, 0.7, 0.8, 1.0)


def _metric_map(metrics: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {str(metric["id"]): metric for metric in metrics}


def _upright_critical_stress_score(
    row: dict[str, Any],
) -> tuple[float, float, float]:
    _, metrics = stress_scenario_score(row)
    height_metric = next(
        metric for metric in metrics if str(metric["id"]).endswith("_minimum_height_m")
    )
    other_pairs = [
        (float(metric["score"]), weight)
        for metric, weight in zip(metrics, STRESS_WEIGHTS)
        if metric is not height_metric
    ]
    height_score = float(height_metric["score"])
    other_score = weighted_mean(other_pairs)
    return (
        UPRIGHT_CRITICAL_WEIGHT * height_score
        + OTHER_BEHAVIOR_WEIGHT * other_score,
        height_score,
        other_score,
    )


def score_evidence_with_upright_aggregation(evidence: dict[str, Any]) -> dict[str, Any]:
    result = score_evidence_with_unique_metrics(evidence)
    result["schema"] = SCORE_SCHEMA
    result["policy_id"] = POLICY_ID
    result["upright_critical_aggregation"] = {
        "public_basis": "sustained forward locomotion while remaining upright",
        "upright_weight": UPRIGHT_CRITICAL_WEIGHT,
        "other_behavior_weight": OTHER_BEHAVIOR_WEIGHT,
    }
    if result.get("G") is not True:
        return result

    metrics = result.get("metrics", [])
    if not isinstance(metrics, list):
        raise ValueError("SCORING_CORE scorer returned a non-list metrics payload")
    by_id = _metric_map(metrics)
    height_a = float(by_id["nominal_min_body_height_m"]["score"])
    other_a = weighted_mean(
        (float(by_id[metric_id]["score"]), weight)
        for metric_id, weight in A_OTHER_WEIGHTS.items()
    )
    group_a = (
        UPRIGHT_CRITICAL_WEIGHT * height_a
        + OTHER_BEHAVIOR_WEIGHT * other_a
    )

    rows = row_map(evidence.get("scenarios"))
    range_details: list[dict[str, Any]] = []
    for scenario_id in RANGE_SCENARIOS:
        score, height_score, other_score = _upright_critical_stress_score(
            rows[scenario_id]
        )
        range_details.append(
            {
                "id": scenario_id,
                "score": score,
                "upright_height_score": height_score,
                "other_behavior_score": other_score,
            }
        )
    group_r = min(detail["score"] for detail in range_details)

    comparisons = result.get("paired_comparisons", {})
    if not isinstance(comparisons, dict):
        raise ValueError("SCORING_CORE scorer returned invalid paired comparisons")
    pair_scores: dict[str, float] = {}
    for pair_id, scenario_id in (
        ("friction_pair", "friction_derated_pair"),
        ("payload_pair", "payload_heavy_pair"),
    ):
        comparison = comparisons.get(pair_id)
        if not isinstance(comparison, dict):
            raise ValueError(f"SCORING_CORE scorer omitted {pair_id}")
        behavior, height_score, other_score = _upright_critical_stress_score(
            rows[scenario_id]
        )
        causal = float(comparison["causal_score"])
        pair_score = weighted_mean(((causal, 0.35), (behavior, 0.65)))
        comparison["behavior_score"] = behavior
        comparison["upright_height_score"] = height_score
        comparison["other_behavior_score"] = other_score
        comparison["score"] = pair_score
        pair_scores[pair_id] = pair_score
    comparisons["range_scenario_details"] = range_details
    group_d = weighted_mean(
        (
            (pair_scores["friction_pair"], 0.50),
            (pair_scores["payload_pair"], 0.50),
        )
    )
    by_id["friction_pair_response"]["score"] = pair_scores["friction_pair"]
    by_id["payload_pair_response"]["score"] = pair_scores["payload_pair"]

    groups = result["groups"]
    groups["A"] = group_a
    groups["R"] = group_r
    groups["D"] = group_d
    raw_total = 100.0 * sum(
        float(groups[group]) * weight
        for group, weight in GROUP_WEIGHTS.items()
    )
    total = raw_total
    result["raw_total"] = raw_total
    result["total"] = total
    result["score"] = total
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = score_evidence_with_upright_aggregation(read_json(args.evidence))
    write_json(args.output, result)
    print(
        f"F90_XROBO03_OFFLINE_SCORE total={result['total']:.6f} "
        f"G={int(result['G'])} "
        "status=UPRIGHT_CRITICAL_AGGREGATION"
    )


if __name__ == "__main__":
    main()
