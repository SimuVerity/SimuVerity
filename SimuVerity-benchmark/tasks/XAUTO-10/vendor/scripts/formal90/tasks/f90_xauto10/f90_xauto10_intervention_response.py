#!/usr/bin/env python3
"""Distinguish an incorrect XAUTO-10 intervention response from no response."""

from __future__ import annotations

import math
from typing import Any

import f90_xauto10_scoring_core as core


def _segmented_effect_score(candidate: float, reference: float, source: float) -> dict[str, float | bool]:
    scale = max(abs(reference), 1.0e-8)
    absent = abs(candidate) <= max(1.0e-12, 1.0e-6 * scale)
    if absent:
        return {
            "score": 0.0,
            "response_present": False,
            "activity_utility": 0.0,
            "direction_utility": 0.0,
            "magnitude_utility": float(source),
        }
    response_ratio = abs(candidate) / scale
    activity = 100.0 if response_ratio >= 1.0 else 100.0 * (1.0 - math.exp(-response_ratio / 0.05))
    direction = 100.0 if candidate * reference > 0.0 else 0.0
    value = 0.10 * activity + 0.25 * direction + 0.65 * float(source)
    return {
        "score": value,
        "response_present": True,
        "activity_utility": activity,
        "direction_utility": direction,
        "magnitude_utility": float(source),
    }


def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    result = core.score(reference, candidate)
    result["schema"] = "simuverity.f90-xauto10-score.v1"
    result["scorer_implementation"] = "f90_xauto10_intervention_response"
    if int(result.get("G", 0)) != 1:
        return result

    metrics = result["metrics"]
    reference_effects = metrics["reference_intervention_effects"]
    candidate_effects = metrics["candidate_intervention_effects"]
    source_scores = metrics["intervention_scores"]
    segmented = {
        name: _segmented_effect_score(candidate_effects[name], reference_value, source_scores[name])
        for name, reference_value in reference_effects.items()
    }
    values = [float(row["score"]) for row in segmented.values()]
    causal = 0.60 * min(values) + 0.40 * (sum(values) / len(values))
    groups = {name: float(value) for name, value in result["group_scores"].items()}
    groups["C"] = causal
    total = 0.0 if any(value <= 0.0 for value in groups.values()) else 100.0 * math.prod(
        (groups[name] / 100.0) ** weight for name, weight in core.WEIGHTS.items()
    )
    source_gate = bool(metrics.pop("causal_gate", False))
    metrics.update({
        "source_hard_causal_gate": source_gate,
        "causal_utility_semantics": "60_percent_worst_plus_40_percent_mean_of_segmented_effect_utilities",
        "segmented_intervention_scores": segmented,
        "all_intervention_responses_absent": not any(bool(row["response_present"]) for row in segmented.values()),
    })
    result["group_scores"] = {name: round(value, 9) for name, value in groups.items()}
    result["raw_total"] = round(total, 9)
    result["total"] = round(total, 9)
    return result
