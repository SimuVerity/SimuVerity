#!/usr/bin/env python3
"""Pure-offline scorer for complete F90-XAERO-04 evidence.

The ``missing_forward_transition`` finding remains diagnostic because the
underlying transition metrics already contribute continuously to A, M, R,
and D.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import f90_xaero04_scoring_core as core
import f90_xaero04_group_aggregation as group_aggregation


TASK_ID = core.TASK_ID
WEIGHTS = dict(core.WEIGHTS)
POLICY_ID = "simuverity-101-v1:f90-xaero-04:scoring"


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    """Apply group-owned shortcut penalties and strict aggregation."""
    result = core.score(evidence)
    gate = bool(result["G"])
    groups = {name: float(result["groups"][name]) for name in WEIGHTS}
    source_findings = result.pop("shortcut_findings", [])
    finding_ids = {
        str(item.get("id", "")) for item in source_findings if isinstance(item, dict)
    }

    penalties: list[dict[str, str]] = []
    diagnostics: list[str] = []
    for finding in sorted(finding_ids):
        if finding in {
            "position_command_copied_to_measurement",
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
        elif finding == "missing_forward_transition":
            diagnostics.append(finding)

    result["groups"] = {**result["groups"], **copy.deepcopy(groups)}
    total = group_aggregation.strict_geometric(groups, WEIGHTS) if gate else 0.0

    result["schema"] = "simuverity.f90-xaero04-score.v1"
    result["policy_id"] = POLICY_ID
    result["score_raw"] = total
    result["raw_total"] = total
    result["total"] = total
    result["score"] = total
    result["admission_pass"] = bool(gate and total >= 85.0)
    result["anti_shortcut_findings"] = sorted(finding_ids)
    result["diagnostic_only_findings"] = diagnostics
    result["anti_shortcut_group_penalties"] = penalties
    result["total_aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "formula": "G*100*product(applicable_group_score^weight)",
        "applicable_groups": list(WEIGHTS),
        "not_applicable_groups_excluded": ["C"],
        "strict_zero_rule": "any_applicable_group_zero_means_total_zero",
        "epsilon_floor": "none",
        "post_total_cap_floor_or_override": "none",
        "missing_forward_transition_handling": (
            "diagnostic_only; existing A/M/R/D metrics retain the performance loss"
        ),
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
