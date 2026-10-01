#!/usr/bin/env python3
"""F90-XCOMM-02 scorer with complete metrics and group-owned penalties."""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path

import f90_xcomm02_scoring_core as base


POLICY_ID = "simuverity-101-v1:f90-xcomm-02:scoring"
WEIGHTS = dict(base.WEIGHTS)
APPLICABLE = tuple(WEIGHTS)


def strict_geometric_total(gate: object, groups: dict) -> float:
    if not bool(gate):
        return 0.0
    values = {name: float(groups[name]) for name in APPLICABLE}
    if any(not math.isfinite(value) or value < 0.0 or value > 1.0 for value in values.values()):
        raise ValueError("applicable group utility must be finite and in [0,1]")
    if any(value == 0.0 for value in values.values()):
        return 0.0
    if any(not math.isfinite(float(WEIGHTS[name])) or float(WEIGHTS[name]) <= 0.0
           for name in APPLICABLE):
        raise ValueError("applicable group weight must be finite and positive")
    weight_sum = sum(float(WEIGHTS[name]) for name in APPLICABLE)
    if not math.isclose(weight_sum, 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError("applicable group weights must sum to one")
    return 100.0 * math.exp(sum(
        float(WEIGHTS[name]) * math.log(values[name])
        for name in APPLICABLE
    ))


def score_evidence(evidence: dict) -> dict:
    result = copy.deepcopy(base.score_evidence(evidence))
    groups = copy.deepcopy(result["groups"])
    diagnostics = copy.deepcopy(result.get("diagnostics", {}))
    source_findings = diagnostics.pop("shortcut_findings", {})
    findings = sorted(source_findings)
    penalties = []
    if "fixed_or_scenario_invariant_weights" in source_findings:
        groups["M"] = 0.0
        penalties.append({"finding": "fixed_or_scenario_invariant_weights", "group": "M"})
    if "InputValid_not_causally_respected" in source_findings:
        groups["M"] = 0.0
        penalties.append({"finding": "InputValid_not_causally_respected", "group": "M"})
    total = strict_geometric_total(result["G"], groups)
    result.update({
        "schema": "simuverity.f90-xcomm02-score.v1",
        "policy_id": POLICY_ID,
        "groups": groups,
        "score": total,
        "admission_score_pass": bool(result["G"] and total >= result["admission_threshold"]),
        "diagnostics": diagnostics,
        "failure_reasons": [
            reason.replace("score cap: ", "shortcut finding: ")
            for reason in result.get("failure_reasons", [])
        ],
        "anti_shortcut_findings": findings,
        "anti_shortcut_group_penalties": penalties,
        "total_aggregation": {
            "method": "G_times_strict_weighted_geometric_mean",
            "applicable_groups": list(APPLICABLE),
            "zero_group_rule": "any applicable zero group makes total zero",
            "epsilon_floor": "none",
            "post_total_cap_or_floor": "none",
        },
    })
    return result


def zero_group_sanity() -> dict:
    cases = {}
    for name in APPLICABLE:
        groups = {group: 1.0 for group in APPLICABLE}
        groups[name] = 0.0
        cases[name] = strict_geometric_total(True, groups)
    assert all(value == 0.0 for value in cases.values())
    return {"policy_id": POLICY_ID, "cases": cases, "all_zero": True}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence")
    parser.add_argument("--out")
    parser.add_argument("--zero-group-sanity-out")
    args = parser.parse_args()
    evidence_path = Path(args.evidence)
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    result = score_evidence(evidence)
    output = Path(args.out) if args.out else evidence_path.with_name("offline_score.json")
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    if args.zero_group_sanity_out:
        Path(args.zero_group_sanity_out).write_text(
            json.dumps(zero_group_sanity(), indent=2, ensure_ascii=False), encoding="utf-8"
        )
    print(json.dumps({"score": result["score"], "groups": result["groups"], "out": str(output)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
