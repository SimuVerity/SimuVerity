#!/usr/bin/env python3
"""Pure-offline D022 strict-geometric outer-group aggregation.

The validated utilities make the redundant ``min(max(total, 0), 100)``
serialization guard unnecessary: G is
validated as 0/1, every applicable group is validated in [0, 1], the positive
weights sum to one, and the resulting strict weighted geometric score is
therefore already in [0, 100].
"""

from __future__ import annotations

import math
from collections.abc import Mapping


POLICY_ID = "simuverity-101-v1:d022:scoring"
SCORE_SCHEMA = "simuverity.d022-direct-score.v1"
FORMULA = "G*100*A^(14/85)*Q^(21/170)*C^(7/34)*R^(7/34)*D^0.30"
WEIGHTS = {
    "A": 14 / 85,
    "Q": 21 / 170,
    "C": 7 / 34,
    "R": 7 / 34,
    "D": 0.30,
}


def score_complete_groups(groups: Mapping[str, object]) -> dict[str, object]:
    """Return the exact mathematical total for validated complete utilities."""

    missing = sorted(({"G"} | set(WEIGHTS)) - set(groups))
    if missing:
        raise ValueError(f"missing D022 groups: {missing}")

    gate = groups["G"]
    if isinstance(gate, bool):
        gate_value = int(gate)
    elif isinstance(gate, (int, float)) and not isinstance(gate, bool):
        if float(gate) not in (0.0, 1.0):
            raise ValueError("G must be exactly 0 or 1")
        gate_value = int(gate)
    else:
        raise ValueError("G must be a boolean or numeric 0/1")

    utilities: dict[str, float] = {}
    for name in WEIGHTS:
        value = groups[name]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{name} must be a finite number in [0, 1]")
        utility = float(value)
        if not math.isfinite(utility) or not 0.0 <= utility <= 1.0:
            raise ValueError(f"{name} must be a finite number in [0, 1]")
        utilities[name] = utility

    if gate_value == 0 or any(value == 0.0 for value in utilities.values()):
        total = 0.0
    else:
        total = 100.0 * math.prod(
            utilities[name] ** WEIGHTS[name] for name in WEIGHTS
        )

    return {
        "policy_id": POLICY_ID,
        "score_schema": SCORE_SCHEMA,
        "formula": FORMULA,
        "weights": dict(WEIGHTS),
        "G": gate_value,
        **utilities,
        "total_score": total,
        "mathematical_total_returned_directly": True,
        "post_geometric_cap_floor_or_range_clamp": None,
    }


def self_test() -> None:
    assert math.isclose(sum(WEIGHTS.values()), 1.0, abs_tol=1e-15)
    assert score_complete_groups(
        {"G": 1, "A": 1, "Q": 1, "C": 1, "R": 1, "D": 1}
    )["total_score"] == 100.0
    assert score_complete_groups(
        {"G": 0, "A": 1, "Q": 1, "C": 1, "R": 1, "D": 1}
    )["total_score"] == 0.0
    assert score_complete_groups(
        {"G": 1, "A": 1, "Q": 1, "C": 0, "R": 1, "D": 1}
    )["total_score"] == 0.0


if __name__ == "__main__":
    self_test()
    print("D022_TOTAL_SCORING_SELF_TEST_OK")
