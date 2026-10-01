"""Shared strict cross-group aggregation for EXT CURRENT.

Task-specific metric utilities remain in each dedicated scorer.  This module
only fixes the batch-wide outer aggregation rule: G times a weighted geometric
mean over applicable A/Q/M/C/R/D groups, without epsilon floors, total caps,
or post-total clamps.
"""

from __future__ import annotations

import math
from collections.abc import Mapping


class ExtScoringContractError(ValueError):
    """Raised when a task attempts to score outside the EXT contract."""


def strict_weighted_geometric(
    gate: int | bool | float,
    groups: Mapping[str, float],
    weights: Mapping[str, float],
) -> float:
    """Return the unscaled 0--100 strict weighted geometric total.

    `groups` are normalized utilities in [0, 1].  Only applicable groups are
    supplied.  Their positive weights must sum to one.  A failed gate or any
    applicable zero group returns exactly zero.
    """

    if float(gate) not in (0.0, 1.0):
        raise ExtScoringContractError("G must be exactly 0 or 1")
    if not groups:
        raise ExtScoringContractError("at least one applicable group is required")
    if set(groups) != set(weights):
        raise ExtScoringContractError("group and weight keys must match exactly")
    if not set(groups).issubset({"A", "Q", "M", "C", "R", "D"}):
        raise ExtScoringContractError("unknown score group")

    normalized_groups: dict[str, float] = {}
    normalized_weights: dict[str, float] = {}
    for name, value in groups.items():
        number = float(value)
        if not math.isfinite(number) or not 0.0 <= number <= 1.0:
            raise ExtScoringContractError(f"{name} must be finite and in [0, 1]")
        normalized_groups[name] = number
    for name, value in weights.items():
        number = float(value)
        if not math.isfinite(number) or number <= 0.0:
            raise ExtScoringContractError(f"weight {name} must be finite and positive")
        normalized_weights[name] = number
    if not math.isclose(sum(normalized_weights.values()), 1.0, abs_tol=1e-12):
        raise ExtScoringContractError("applicable group weights must sum to one")

    if float(gate) == 0.0 or any(value == 0.0 for value in normalized_groups.values()):
        return 0.0
    log_total = sum(
        normalized_weights[name] * math.log(normalized_groups[name])
        for name in normalized_groups
    )
    return 100.0 * math.exp(log_total)

