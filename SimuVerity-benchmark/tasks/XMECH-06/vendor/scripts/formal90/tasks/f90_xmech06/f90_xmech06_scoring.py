#!/usr/bin/env python3
"""Strict-geometric XMECH-06 scorer with shortcut rules inside groups."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xmech06_group_aggregation as current


WEIGHTS = current.WEIGHTS
POLICY_ID = 'simuverity-101-v1:f90-xmech-06:scoring'
RULES = {
    "four-wheel physical forces are inactive": "M",
    "suspension states are inactive": "M",
    "body attitude is fixed": "D",
    "fewer than two official operating inputs have measurable effects": "R",
    "wheel forces are unrelated to chassis acceleration": "M",
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
) -> tuple[dict[str, float], list[dict[str, str]]]:
    revised = dict(groups)
    migrated: list[dict[str, str]] = []
    for item in source_findings:
        reason = str(item.get("reason", ""))
        if reason not in RULES:
            raise ValueError(f"unmapped source shortcut condition: {reason}")
        group = RULES[reason]
        revised[group] = 0.0
        migrated.append({"condition": reason, "group": group, "utility": "zero"})
    return revised, migrated


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = current.score_evidence(evidence)
    diagnostics = result.setdefault("diagnostics", {})
    findings = list(diagnostics.pop("shortcut_findings", []))
    groups, migrated = apply_group_internal_rules(result["groups"], findings)
    gate = bool(result["G"])
    total = strict_geometric(groups, WEIGHTS, gate)
    diagnostics["group_internal_shortcut_rules"] = migrated
    result.update(
        {
            "schema": "simuverity.f90-xmech06-score.v1",
            "policy_id": POLICY_ID,
            "formula": "G*100*A^0.15*Q^0.10*M^0.30*R^0.15*D^0.30",
            "groups": groups,
            "group_weights": dict(WEIGHTS),
            "score": total,
            "total": total,
            "admission_score_pass": bool(gate and total >= 85.0),
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
    result = score_evidence(json.loads(args.evidence.read_text(encoding="utf-8")))
    out = args.out or args.evidence.with_name("score.json")
    out.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({"score": result["score"], "groups": result["groups"], "out": str(out)}))


if __name__ == "__main__":
    main()
