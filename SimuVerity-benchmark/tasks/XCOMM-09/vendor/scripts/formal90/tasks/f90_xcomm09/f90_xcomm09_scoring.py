#!/usr/bin/env python3
"""Strict-geometric XCOMM-09 scorer with shortcut rules inside groups."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import f90_xcomm09_scoring_core as core


WEIGHTS = core.WEIGHTS
POLICY_ID = "simuverity-101-v1:f90-xcomm-09:scoring"
SOURCE_RULE_GROUPS = {
    "missing causal TGn/AWGN link": "M",
    "perfect true-channel state reaches receiver": "G",
    "reported PER is unsupported by recovered PSDUs": "Q",
    "transmitted PSDU is replayed across independent seeds": "R",
    "recovered PSDU is replayed across independent seeds": "R",
    "receiver does not expose a rank-two channel estimate": "M",
    "one stream is duplicated as two MIMO streams": "M",
    "TGn channel is absent or copied through": "M",
    "spatial-mapping input is fixed or ignored": "M",
    "MCS input is fixed or ignored": "M",
}


def strict_geometric(
    groups: dict[str, float], weights: dict[str, float], gate: bool = True
) -> float:
    values = {name: float(groups[name]) for name in weights}
    if any(not math.isfinite(value) or not 0.0 <= value <= 1.0 for value in values.values()):
        raise ValueError("group scores must be finite and in [0,1]")
    if not gate or any(value <= 0.0 for value in values.values()):
        return 0.0
    return 100.0 * math.exp(sum(weights[name] * math.log(values[name]) for name in weights))


def apply_group_internal_rules(
    groups: dict[str, float], source_findings: list[dict[str, Any]]
) -> tuple[dict[str, float], bool, list[dict[str, str]]]:
    revised = dict(groups)
    gate = bool(revised.get("G", 1.0))
    migrated: list[dict[str, str]] = []
    for item in source_findings:
        reason = str(item.get("reason", ""))
        group = SOURCE_RULE_GROUPS.get(reason)
        if group is None:
            raise ValueError(f"unmapped source shortcut condition: {reason}")
        if group == "G":
            gate = False
            revised["G"] = 0.0
        else:
            revised[group] = 0.0
        migrated.append({"condition": reason, "group": group, "utility": "zero"})
    return revised, gate, migrated


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = core.score_evidence(evidence)
    diagnostics = result.setdefault("diagnostics", {})
    source_findings = list(diagnostics.pop("shortcut_findings", []))
    groups, gate, migrated = apply_group_internal_rules(result["groups"], source_findings)
    total = strict_geometric(groups, WEIGHTS, gate)
    diagnostics["group_internal_shortcut_rules"] = migrated
    result.update(
        {
            "schema": "simuverity.f90-xcomm09-score.v1",
            "policy_id": POLICY_ID,
            "G": gate,
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
