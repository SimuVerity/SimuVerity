#!/usr/bin/env python3
"""Combine F90-XAUTO-09 groups by strict weighted geometry."""

from __future__ import annotations

import math
from typing import Any

import f90_xauto09_scoring_core as base


def _weighted_geometric(groups: dict[str, float], weights: dict[str, float]) -> float:
    if any(groups[name] <= 0.0 for name in weights):
        return 0.0
    return 100.0 * math.exp(
        sum(weights[name] * math.log(groups[name] / 100.0) for name in weights)
    )


def score(
    evidence: dict[str, Any],
    requested_subject: str = "auto",
    context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    result = base.score(evidence, requested_subject, context)
    result["schema"] = "simuverity.f90-xauto09-offline-score.v1"
    result["scorer_implementation"] = "simuverity-101-v1:f90-xauto-09:scoring"
    result["total_aggregation"] = {
        "method": "G_times_weighted_geometric_mean",
        "zero_group_floor_applied": False,
    }
    if result.get("G") != 1 or not result.get("scoring_completed"):
        return result

    groups = {name: float(value) for name, value in result["groups"].items()}
    weights = {name: float(value) for name, value in result["weights"].items()}
    total = round(_weighted_geometric(groups, weights), 9)
    result["raw_total"] = total
    result["total"] = total
    result["raw_score"] = total
    return result
