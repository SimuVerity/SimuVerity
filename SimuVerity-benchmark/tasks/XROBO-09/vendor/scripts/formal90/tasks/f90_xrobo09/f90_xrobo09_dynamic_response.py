#!/usr/bin/env python3
"""XROBO-09 scorer with continuous observed-encounter recovery credit.

The D-group policy evaluates every positive-duration collision-risk flag
using separation, route recovery, speed recovery and control response.  A
scenario with no observed flag still receives zero D credit.
"""
from __future__ import annotations

from typing import Any

import f90_xrobo09_scoring_core as METRICS
import f90_xrobo09_group_aggregation as GROUP_SCORING


def _avoidance_performance_continuous(m: dict[str, float]) -> float:
    # No observed risk flag means this scenario provides no recovery evidence.
    # Any positive-duration flag is scored with the declared utilities.
    if m["potential_collision_duration_s"] <= 0.0:
        return 0.0
    return METRICS._weighted_mean(
        [
            (METRICS._higher_better(m["planner_collision_alignment"], 0.35, 0.75), 0.23),
            (METRICS._higher_better(m["minimum_physical_separation_m"], 3.0, 10.0), 0.25),
            (m["collision_flag_cleared_by_end"], 0.05),
            (METRICS._lower_better(m["post_encounter_speed_mae_mps"], 0.05, 0.35), 0.15),
            (METRICS._lower_better(m["post_encounter_route_error_m"], 20.0, 55.0), 0.14),
            (METRICS._higher_better(m["desired_yaw_range_rad"], 0.05, 0.30), 0.07),
            (
                METRICS._higher_better(
                    m["left_right_propeller_difference_rms"], 0.5, 8.0
                ),
                0.07,
            ),
            (
                METRICS._higher_better(
                    m["route_progress_ratio_to_available_distance"], 0.35, 0.68
                ),
                0.04,
            ),
        ]
    )


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    original = METRICS._avoidance_performance
    try:
        METRICS._avoidance_performance = _avoidance_performance_continuous
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
        }
    )
    result["dynamic_recovery_policy"] = {
        "group": "D",
        "response_rule": "positive_duration_flag_uses_declared_recovery_utilities",
        "post_total_floor_or_cap": "none",
    }
    return result


def main() -> None:
    # Reuse the complete CLI contract with this module's scoring function.
    original = GROUP_SCORING.score_evidence
    try:
        GROUP_SCORING.score_evidence = score_evidence
        GROUP_SCORING.main()
    finally:
        GROUP_SCORING.score_evidence = original


if __name__ == "__main__":
    main()
