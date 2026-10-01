#!/usr/bin/env python3
"""Strict-geometric, pure-offline scorer for F90-XAERO-04.

Anti-shortcut findings are assigned to their engineering groups before strict
cross-group aggregation; no epsilon floor or post-total adjustment is applied.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

import f90_xaero04_scoring_core as core


TASK_ID = core.TASK_ID
WEIGHTS = dict(core.WEIGHTS)
POLICY_ID = "simuverity-101-v1:f90-xaero-04:scoring"


def strict_geometric(
    groups: dict[str, float], weights: dict[str, float]
) -> float:
    """Return 100 times the strict weighted geometric mean."""
    if not weights:
        raise ValueError("at least one applicable group is required")
    if any(
        not math.isfinite(float(weight)) or float(weight) <= 0.0
        for weight in weights.values()
    ):
        raise ValueError("group weights must be finite and positive")
    if not math.isclose(sum(weights.values()), 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError("applicable group weights must sum to one")

    values = {name: float(groups[name]) for name in weights}
    if any(
        not math.isfinite(value) or value < 0.0 or value > 1.0
        for value in values.values()
    ):
        raise ValueError("group scores must be finite and in [0, 1]")
    if any(value == 0.0 for value in values.values()):
        return 0.0
    return 100.0 * math.exp(
        sum(weights[name] * math.log(values[name]) for name in weights)
    )


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    """Compute complete metrics, group-owned penalties, and the total."""
    result = core.score(evidence)
    gate = bool(result["G"])
    groups = {name: float(result["groups"][name]) for name in WEIGHTS}
    source_findings = result.pop("shortcut_findings", [])
    finding_ids = {
        str(item.get("id", "")) for item in source_findings if isinstance(item, dict)
    }
    penalties = []
    for finding in sorted(finding_ids):
        if finding in {
            "position_command_copied_to_measurement",
            "missing_forward_transition",
            "missing_tiltrotor_mechanism",
        }:
            groups["M"] = 0.0
            penalties.append({"finding": finding, "group": "M"})
        elif finding == "constant_or_missing_actuator_channels":
            groups["D"] = 0.0
            penalties.append({"finding": finding, "group": "D"})
        elif finding in {"nominal_output_replayed", "payload_and_wind_ignored"}:
            groups["R"] = 0.0
            penalties.append({"finding": finding, "group": "R"})
    result["groups"] = {**result["groups"], **copy.deepcopy(groups)}
    total = strict_geometric(groups, WEIGHTS) if gate else 0.0

    result["schema"] = "simuverity.f90-xaero04-score.v1"
    result["policy_id"] = POLICY_ID
    result["score_raw"] = total
    result["raw_total"] = total
    result["total"] = total
    result["score"] = total
    result["admission_pass"] = bool(gate and total >= 85.0)
    result["anti_shortcut_findings"] = [
        item for item in sorted(finding_ids)
    ]
    result["anti_shortcut_group_penalties"] = penalties
    result["total_aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "formula": "G*100*product(applicable_group_score^weight)",
        "applicable_groups": list(WEIGHTS),
        "not_applicable_groups_excluded": ["C"],
        "strict_zero_rule": "any_applicable_group_zero_means_total_zero",
        "epsilon_floor": "none",
        "post_total_cap_floor_or_override": "none",
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8-sig"))
    result = score(evidence)
    core.write_json(args.output, result)
    print(f"{TASK_ID} G={result['G']:.0f} strict={result['total']:.12f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
