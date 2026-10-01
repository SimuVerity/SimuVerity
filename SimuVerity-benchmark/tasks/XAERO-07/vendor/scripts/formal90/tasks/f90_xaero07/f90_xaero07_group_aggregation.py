#!/usr/bin/env python3
"""Pure-offline XAERO-07 scorer with weighted-geometric aggregation."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xaero07_component_availability as component_availability


TASK_ID = component_availability.TASK_ID
WEIGHTS = component_availability.WEIGHTS


def weighted_geometric_total(
    group_scores: dict[str, float], weights: dict[str, float]
) -> float:
    """Return the 0--100 weighted geometric mean with a strict zero rule."""
    if set(group_scores) != set(weights):
        raise ValueError("group/weight keys differ")
    if not math.isclose(sum(weights.values()), 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError("weights must sum to one")
    values = {name: float(group_scores[name]) for name in weights}
    if any(not math.isfinite(value) or value < 0.0 or value > 100.0 for value in values.values()):
        raise ValueError("group scores must be finite and in [0, 100]")
    if any(value <= 0.0 for value in values.values()):
        return 0.0
    return round(
        100.0
        * math.exp(
            sum(weights[name] * math.log(values[name] / 100.0) for name in weights)
        ),
        9,
    )


def score(
    evidence: dict[str, Any],
    path: Path,
    evidence_role: str = "candidate",
) -> dict[str, Any]:
    result = component_availability.score(evidence, path, evidence_role=evidence_role)
    gate = int(result["gate"]["G"])
    result["schema"] = "simuverity.f90-xaero07-offline-score.v1"
    result["raw_score"] = (
        weighted_geometric_total(result["group_scores"], result["weights"])
        if gate == 1
        else 0.0
    )
    result["total_aggregation"] = {
        "method": "G_times_weighted_geometric_mean",
        "formula": "G*100*product((group_score/100)^weight)",
        "strict_zero_rule": "any_applicable_group_le_zero_means_total_zero",
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--evidence-role", choices=("candidate", "reference"), default="candidate"
    )
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    result = score(evidence, args.evidence, evidence_role=args.evidence_role)
    (args.output_dir / "score.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
