#!/usr/bin/env python3
"""F90-XAUTO-06 scorer with continuous dynamic-group aggregation.

D is a 25/75 blend of independently measured final recovery and regenerative
activity; weak activity therefore reduces D continuously.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import f90_xauto06_group_aggregation as group_aggregation


POLICY_ID = "simuverity-101-v1:f90-xauto-06:scoring"


def score(evidence: dict) -> dict:
    result = copy.deepcopy(group_aggregation.score(evidence))
    if not result.get("valid"):
        result["policy_id"] = POLICY_ID
        return result

    headline = result["headline_metrics"]
    groups = copy.deepcopy(result["groups"])
    groups["D"] = (
        0.25 * float(headline["final_recovery_utility"])
        + 0.75 * float(headline["regenerative_activity_utility"])
    )

    diagnostics = []
    for item in result.get("anti_shortcut_group_penalties", []):
        if item.get("finding") != "REGENERATIVE_BRAKING_ACTIVITY_MISSING":
            diagnostics.append(item)
    if float(headline["minimum_regen_activity_fraction"]) < 0.02:
        diagnostics.append({
            "finding": "REGENERATIVE_BRAKING_ACTIVITY_MISSING",
            "group": "D",
            "score_effect": "through_existing_regenerative_activity_utility_only",
        })

    total = group_aggregation.strict_geometric_total(result["G"], groups)
    result.update({
        "policy_id": POLICY_ID,
        "groups": groups,
        "raw_total": total,
        "total": total,
        "diagnostic_findings": diagnostics,
        "anti_shortcut_group_penalties": [
            item for item in diagnostics if "score_effect" not in item
        ],
        "d_group_aggregation": (
            "0.25*final_recovery_utility + "
            "0.75*regenerative_activity_utility"
        ),
        "regeneration_activity_enters_blended_D_only": True,
    })
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    evidence = json.loads(Path(args.evidence).read_text(encoding="utf-8-sig"))
    Path(args.output).write_text(
        json.dumps(score(evidence), indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
