#!/usr/bin/env python3
"""XROBO-09 scorer with duration-confidence recovery credit.

The D-group recovery utilities are multiplied by
min(1, observed_flag_duration / 0.5 s).  No observed flag still yields zero.
"""
from __future__ import annotations

from typing import Any

import f90_xrobo09_scoring_core as METRICS
import f90_xrobo09_group_aggregation as GROUP_SCORING
import f90_xrobo09_dynamic_response as COMPATIBILITY


EVIDENCE_CONFIDENCE_FULL_DURATION_S = 0.5
def _avoidance_performance_duration_confidence(m: dict[str, float]) -> float:
    duration = max(0.0, float(m["potential_collision_duration_s"]))
    if duration <= 0.0:
        return 0.0
    utility = COMPATIBILITY._avoidance_performance_continuous(m)
    confidence = min(1.0, duration / EVIDENCE_CONFIDENCE_FULL_DURATION_S)
    return utility * confidence


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    original = METRICS._avoidance_performance
    try:
        METRICS._avoidance_performance = _avoidance_performance_duration_confidence
        result = GROUP_SCORING.score_evidence(evidence)
    finally:
        METRICS._avoidance_performance = original

    result["schema"] = "simuverity.f90-xrobo09-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xrobo-09:scoring"
    result["aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "post_total_cap": "none",
    }
    qualification = result.setdefault("qualification", {})
    qualification.update(
        {
            "short_positive_duration_encounter_scored_continuously": True,
            "zero_duration_encounter_receives_zero_D_credit": True,
            "duration_confidence_full_at_seconds": EVIDENCE_CONFIDENCE_FULL_DURATION_S,
        }
    )
    result["dynamic_recovery_policy"] = {
        "group": "D",
        "response_rule": "recovery_utility_times_min(1,duration_s/0.5)",
        "duration_confidence_full_at_seconds": EVIDENCE_CONFIDENCE_FULL_DURATION_S,
        "post_total_floor_or_cap": "none",
    }
    return result


def main() -> None:
    original = GROUP_SCORING.score_evidence
    try:
        GROUP_SCORING.score_evidence = score_evidence
        GROUP_SCORING.main()
    finally:
        GROUP_SCORING.score_evidence = original


if __name__ == "__main__":
    main()
