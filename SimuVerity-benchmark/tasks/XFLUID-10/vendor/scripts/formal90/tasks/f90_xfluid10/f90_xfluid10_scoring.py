#!/usr/bin/env python3
"""Strict-geometric XFLUID-10 scorer with shortcut rules inside groups."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

import f90_xfluid10_scoring_core as current


WEIGHTS = current.WEIGHTS
POLICY_ID = 'simuverity-101-v1:f90-xfluid-10:scoring'
RULES = {
    "wrong_firing_order": ("M", 0.0),
    "duplicated_injector_traces": ("M", 0.0),
    "fuel_command_ignored": ("M", 0.0),
    "scenarios_replayed": ("R", 0.0),
    "one_or_more_scenarios_fail_materially": ("R", 0.30),
}


def strict_geometric(groups: dict[str, float], weights: dict[str, float], gate: bool = True) -> float:
    values = {name: float(groups[name]) for name in weights}
    if any(not math.isfinite(value) or not 0.0 <= value <= 1.0 for value in values.values()):
        raise ValueError("group scores must be finite and in [0,1]")
    if not gate or any(value <= 0.0 for value in values.values()):
        return 0.0
    return 100.0 * math.exp(sum(weights[name] * math.log(values[name]) for name in weights))


def apply_group_internal_rules(
    groups: dict[str, float], source_findings: list[dict[str, Any]]
) -> tuple[dict[str, float], list[dict[str, Any]]]:
    revised = dict(groups)
    migrated: list[dict[str, Any]] = []
    for item in source_findings:
        rule_id = str(item.get("name", ""))
        if rule_id not in RULES:
            raise ValueError(f"unmapped source shortcut condition: {rule_id}")
        group, ceiling = RULES[rule_id]
        revised[group] = min(float(revised[group]), ceiling)
        migrated.append({"condition": rule_id, "group": group, "group_utility_ceiling": ceiling})
    return revised, migrated


def score(evidence: dict[str, Any], evidence_path: Path | None = None) -> dict[str, Any]:
    working = copy.deepcopy(evidence)
    refreshed = current.refresh_metrics_from_complete_raw(working, evidence_path) if evidence_path else 0
    result = current.score(working)
    findings = list(result.pop("shortcut_findings", []))
    groups, migrated = apply_group_internal_rules(result["groups"], findings)
    gate = bool(result["G"])
    total = strict_geometric(groups, WEIGHTS, gate)
    result.update(
        {
            "schema": "simuverity.f90-xfluid10-score.v1",
            "policy_id": POLICY_ID,
            "groups": groups,
            "score_raw": total,
            "score": total,
            "total": total,
            "admission_pass": bool(gate and total >= 85.0),
            "preferred_reference_pass": bool(gate and total >= 90.0),
            "group_internal_shortcut_rules": migrated,
            "offline_raw_metric_refresh": {
                "scenario_count": refreshed,
                "simulation_restarted": False,
            },
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score(evidence, args.evidence)
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
