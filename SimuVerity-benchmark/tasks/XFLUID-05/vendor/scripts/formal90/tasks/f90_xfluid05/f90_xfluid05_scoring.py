#!/usr/bin/env python3
"""Strict-geometric XFLUID-05 scorer with shortcut rules inside groups."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xfluid05_scoring_core as current


WEIGHTS = current.WEIGHTS
POLICY_ID = 'simuverity-101-v1:f90-xfluid-05:scoring'
RULES = {
    "duplicated_or_invalid_piston_phase": ("M", 0.0),
    "inactive_pressure_to_yoke_control": ("D", 0.0),
    "pressure_limit_absent": ("M", 0.0),
    "scenario_inputs_ignored": ("R", 0.0),
    "weak_causal_mechanism": ("M", 0.70),
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
        rule_id = str(item.get("id", ""))
        if rule_id not in RULES:
            raise ValueError(f"unmapped source shortcut condition: {rule_id}")
        group, ceiling = RULES[rule_id]
        revised[group] = min(float(revised[group]), ceiling)
        migrated.append({"condition": rule_id, "group": group, "group_utility_ceiling": ceiling})
    return revised, migrated


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    result = current.score(evidence)
    findings = list(result.pop("shortcut_findings", []))
    groups, migrated = apply_group_internal_rules(result["groups"], findings)
    gate = bool(result["G"])
    total = strict_geometric(groups, WEIGHTS, gate)
    result.update(
        {
            "schema": "simuverity.f90-xfluid05-score.v1",
            "policy_id": POLICY_ID,
            "groups": groups,
            "score_raw": total,
            "score": total,
            "total": total,
            "admission_pass": bool(gate and total >= 85.0),
            "group_internal_shortcut_rules": migrated,
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = score(json.loads(args.evidence.read_text(encoding="utf-8")))
    text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
