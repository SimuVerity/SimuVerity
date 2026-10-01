#!/usr/bin/env python3
"""F90-XAUTO-04 scorer with group-owned findings and a strict geometric total."""
from __future__ import annotations

import copy
import json
import math

import f90_xauto04_scoring_core as base


TASK_ID = "F90-XAUTO-04"
POLICY_ID = "simuverity-101-v1:f90-xauto-04:scoring"
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


def score(evidence: dict) -> dict:
    result = copy.deepcopy(base.score(evidence))
    groups = copy.deepcopy(result["groups"])
    source_findings = result.pop("shortcut_findings", [])
    penalties = []
    finding_ids = {item["id"] for item in source_findings}
    if "vehicle_speed_copied_to_four_wheels" in finding_ids:
        groups["M"] = 0.0
        penalties.append({"finding": "vehicle_speed_copied_to_four_wheels", "group": "M"})
    if "identical_open_loop_split_mu_braking" in finding_ids:
        utility = float(result["details"]["M"]["split_mu_closed_loop_diagnostic"]["utility"])
        groups["M"] = min(groups["M"], utility)
        penalties.append({"finding": "identical_open_loop_split_mu_braking", "group": "M"})
    if "constant_brake_pressure" in finding_ids:
        groups["D"] = 0.0
        penalties.append({"finding": "constant_brake_pressure", "group": "D"})
    if "nominal_response_replayed" in finding_ids:
        groups["R"] = 0.0
        penalties.append({"finding": "nominal_response_replayed", "group": "R"})
    if "missing_four_channel_closed_loop_mechanism" in finding_ids:
        groups["M"] = 0.0
        penalties.append({"finding": "missing_four_channel_closed_loop_mechanism", "group": "M"})
    result["groups"] = groups
    total = strict_geometric_total(result["G"], groups)
    result.update({
        "schema": "simuverity.f90-xauto04-score.v1",
        "policy_id": POLICY_ID,
        "score_raw": total,
        "admission_pass": bool(result["G"] and total >= result["admission_threshold_raw"]),
        "anti_shortcut_findings": sorted(finding_ids),
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
    parser = base.argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=base.Path)
    parser.add_argument("--output", required=True, type=base.Path)
    parser.add_argument("--sanity-output", type=base.Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score(evidence)
    base.write_json(args.output, result)
    if args.sanity_output:
        base.write_json(args.sanity_output, zero_group_sanity())
    print(f"{TASK_ID} G={result['G']:.0f} raw={float(result['score_raw']):.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
