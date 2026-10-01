#!/usr/bin/env python3
"""Combine F90-XAUTO-07 groups by strict weighted geometry."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xauto07_robustness_dynamics as robustness_dynamics


def _weighted_geometric(groups: dict[str, float], weights: dict[str, float]) -> float:
    if any(groups[name] <= 0.0 for name in weights):
        return 0.0
    return 100.0 * math.exp(
        sum(weights[name] * math.log(groups[name] / 100.0) for name in weights)
    )


def score(
    evidence: dict[str, Any],
    evidence_path: Path,
    requested_subject: str = "auto",
    context: dict[str, Any] | None = None,
    loaded_override: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    result = robustness_dynamics.score(
        evidence, evidence_path, requested_subject, context, loaded_override
    )
    result["schema"] = "simuverity.f90-xauto07-offline-score.v1"
    result["scorer_implementation"] = "simuverity-101-v1:f90-xauto-07:scoring"
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--subject", choices=("auto", "candidate", "reference"), default="auto"
    )
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    result = score(evidence, args.evidence, args.subject)
    (args.output_dir / "score.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
