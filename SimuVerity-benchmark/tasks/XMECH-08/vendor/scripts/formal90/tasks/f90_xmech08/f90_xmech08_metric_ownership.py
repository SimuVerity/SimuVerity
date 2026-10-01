#!/usr/bin/env python3
"""XMECH08 scorer with approved cross-group metric de-duplication.

This pure-offline scorer keeps the declared evidence and thresholds.  R
retains only trajectory accuracy because drive
performance is already owned by A/D; D drops the exact cycle-closure metric
already owned by Q.  The remaining declared weights are renormalized by the
existing weighted-mean helper.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import f90_xmech08_scoring_core as GROUP_RULES


WEIGHTS = GROUP_RULES.WEIGHTS
POLICY_ID = 'simuverity-101-v1:f90-xmech-08:scoring'
R_REMOVED = {"drive_angle", "drive_speed"}
D_REMOVED = {"cycle_closure"}
DEDUPLICATION = {
    "R": {
        "removed": ["drive_angle", "drive_speed"],
        "reason": "drive performance is owned by A and D; R retains trajectory only",
    },
    "D": {
        "removed": ["cycle_closure"],
        "reason": "the identical closure metric and thresholds remain owned by Q",
    },
}


def _without(
    parts: dict[str, tuple[float, float]], removed: set[str]
) -> dict[str, tuple[float, float]]:
    return {name: value for name, value in parts.items() if name not in removed}


def _reapply_group_internal_rules(
    groups: dict[str, float], findings: list[dict[str, Any]]
) -> dict[str, float]:
    revised = dict(groups)
    for finding in findings:
        group = finding.get("group")
        ceiling = finding.get("group_utility_ceiling")
        if group in revised and isinstance(ceiling, (int, float)):
            revised[str(group)] = min(float(revised[str(group)]), float(ceiling))
    return revised


def score(evidence: dict[str, Any], reference_evidence: dict[str, Any]) -> dict[str, Any]:
    result = GROUP_RULES.score(evidence, reference_evidence)
    result["schema"] = "simuverity.f90-xmech08-score.v1"
    result["policy_id"] = POLICY_ID
    result["metric_deduplication"] = copy.deepcopy(DEDUPLICATION)
    if not bool(result.get("G")):
        return result

    details = result["details"]
    r_parts = {
        scenario_id: _without(parts, R_REMOVED)
        for scenario_id, parts in details["R"]["parts"].items()
    }
    d_parts = {
        scenario_id: _without(parts, D_REMOVED)
        for scenario_id, parts in details["D"]["parts"].items()
    }
    r_by_scenario = {
        scenario_id: GROUP_RULES.STRUCTURE_SCORING.METRICS.weighted_mean(parts)
        for scenario_id, parts in r_parts.items()
    }
    d_by_scenario = {
        scenario_id: GROUP_RULES.STRUCTURE_SCORING.METRICS.weighted_mean(parts)
        for scenario_id, parts in d_parts.items()
    }

    groups = dict(result["groups"])
    groups["R"] = min(r_by_scenario.values())
    groups["D"] = min(d_by_scenario.values())
    groups = _reapply_group_internal_rules(
        groups, list(result.get("group_internal_shortcut_rules", []))
    )
    total = GROUP_RULES.strict_geometric(groups, WEIGHTS, bool(result["G"]))

    details["R"] = {
        "aggregation": "100_percent_minimum",
        "by_scenario": r_by_scenario,
        "parts": r_parts,
        "weight_denominator": 0.85,
    }
    details["D"] = {
        "aggregation": "100_percent_minimum",
        "by_scenario": d_by_scenario,
        "parts": d_parts,
        "weight_denominator": 0.80,
    }
    result.update(
        {
            "groups": groups,
            "score_raw": total,
            "score": total,
            "total": total,
            "admission_pass": bool(result["G"] and total >= 85.0),
            "details": details,
            "total_aggregation": {
                "method": "G_times_strict_weighted_geometric_mean",
                "strict_zero_rule": "any_applicable_group_le_zero_means_total_zero",
                "not_applicable_groups_excluded": True,
                "epsilon_floor": "none",
                "post_total_cap_floor_or_override": "none",
            },
        }
    )
    return result


def run_shortcut_sanity(
    evidence: dict[str, Any], reference_evidence: dict[str, Any]
) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any]]] = []

    missing = copy.deepcopy(evidence)
    missing["scenarios"][0]["outputs_valid"] = False
    cases.append(("required_output_missing", missing))

    disconnected = copy.deepcopy(evidence)
    disconnected.setdefault("static_audit", {})["four_bar_graph_connected"] = False
    cases.append(("physical_loop_disconnected", disconnected))

    no_sensor = copy.deepcopy(evidence)
    no_sensor.setdefault("static_audit", {})["physical_tip_measurement_signature"] = False
    cases.append(("physical_tip_measurement_missing", no_sensor))

    rows = []
    for name, mutated in cases:
        value = float(score(mutated, reference_evidence)["score_raw"])
        rows.append(
            {
                "id": name,
                "score_raw": value,
                "required_maximum": 0.0,
                "pass": value == 0.0,
            }
        )
    return {
        "schema": "simuverity.f90-xmech08-shortcut-sanity.v1",
        "task_id": GROUP_RULES.STRUCTURE_SCORING.TASK_ID,
        "cases": rows,
        "all_pass": all(row["pass"] for row in rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--reference-evidence", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--sanity-out", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    reference_path = args.reference_evidence or args.evidence
    reference = json.loads(reference_path.read_text(encoding="utf-8"))
    result = score(evidence, reference)
    text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
    if args.sanity_out:
        sanity = run_shortcut_sanity(evidence, reference)
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(
            json.dumps(sanity, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )
    print(text)


if __name__ == "__main__":
    main()
