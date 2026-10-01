"""Pure-offline scorer for EXT-XFLUID-WEC-DESAL.

Physical mechanisms and startup quality are required across every operating
regime, while causal response covers the complete conversion path.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import ext_xfluid_wec_desal_scoring_core as core

POLICY_ID = "simuverity-101-v1:ext-xfluid-wec-desal:scoring"


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(core.score_evidence(evidence))
    if result["G"] != 1:
        result["evaluation_policy_id"] = POLICY_ID
        return result

    sm = result["scenario_metrics"]
    values = list(sm.values())
    nominal = sm["nominal_sea"]
    intervention = sm["height_intervention"]

    per_scenario_mechanism = {
        scenario_id: core.weighted([
            (.30, metrics["activity_utility"]),
            (.30, metrics["ro_split_u"]),
            (.25, metrics["recovery_coupling_u"]),
            (.15, metrics["power_identity_u"]),
        ])
        for scenario_id, metrics in sm.items()
    }
    path_utilities: dict[str, float] = {}
    for key in ("force_rms", "power_rms", "total_feed_rms", "pressure_rms"):
        gain = intervention[key] / max(nominal[key], 1e-12)
        change = abs(intervention[key] - nominal[key]) / max(nominal[key], 1e-12)
        path_utilities[key] = core.weighted([
            (.55, core.utility(gain, 1.15, 1.02, False)),
            (.45, core.utility(change, .12, .015, False)),
        ])

    groups = dict(result["groups_normalized"])
    # A physical mechanism must be present in every official operating regime.
    groups["M"] = min(per_scenario_mechanism.values())
    # C requires response across the disclosed conversion chain.
    groups["C"] = sum(path_utilities.values()) / len(path_utilities)
    # Dynamic/start-up quality is a worst-operating-regime obligation.
    groups["D"] = min(metrics["startup_u"] for metrics in values)

    result.update({
        "evaluation_policy_id": POLICY_ID,
        "groups": {name: 100.0 * value for name, value in groups.items()},
        "groups_normalized": groups,
        "raw_score": core.strict_weighted_geometric(result["G"], groups, core.WEIGHTS),
        "admission_pass": bool(result["G"] and core.strict_weighted_geometric(result["G"], groups, core.WEIGHTS) >= 90.0),
        "scoring_diagnostics": {
            "causal_path_aggregation": "mean_of_force_power_feed_pressure_path_utilities",
            "causal_path_utilities": path_utilities,
            "mechanism_across_scenarios": "worst_case",
            "dynamic_across_scenarios": "worst_case",
            "per_scenario_mechanism": per_scenario_mechanism,
        },
    })
    return result


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    base = score_evidence(evidence)
    checks: dict[str, bool] = {}
    missing = copy.deepcopy(evidence)
    missing["scenarios"][0].pop("desal_hydraulic_response", None)
    checks["required_output_loses_score"] = score_evidence(missing)["raw_score"] < base["raw_score"]
    inert = copy.deepcopy(evidence)
    nominal = next(item for item in inert["scenarios"] if item["id"] == "nominal_sea")
    changed = next(item for item in inert["scenarios"] if item["id"] == "height_intervention")
    changed["desal_hydraulic_response"] = copy.deepcopy(nominal["desal_hydraulic_response"])
    changed["desal_recovery_response"] = copy.deepcopy(nominal["desal_recovery_response"])
    checks["partly_inert_causal_chain_loses_score"] = score_evidence(inert)["groups"]["C"] < base["groups"]["C"]
    return {"task_id": core.TASK_ID, "checks": checks, "pass": all(checks.values())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--shortcut-output", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(score_evidence(evidence), indent=2) + "\n", encoding="utf-8")
    if args.shortcut_output:
        args.shortcut_output.write_text(json.dumps(shortcut_sanity(evidence), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
