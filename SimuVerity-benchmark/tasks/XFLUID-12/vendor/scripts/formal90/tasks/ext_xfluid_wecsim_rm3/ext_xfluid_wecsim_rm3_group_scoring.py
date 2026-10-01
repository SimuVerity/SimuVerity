"""Pure-offline group scorer for EXT-XFLUID-WECSIM-RM3."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import ext_xfluid_wecsim_rm3_scoring_core as core

POLICY_ID = "simuverity-101-v1:ext-xfluid-wecsim-rm3:scoring"


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(core.score_evidence(evidence))
    if result["G"] != 1:
        result["evaluation_policy_id"] = POLICY_ID
        return result

    sm = result["scenario_metrics"]
    values = list(sm.values())
    per_scenario_mechanism = {
        scenario_id: core.weighted([(.70, metrics["mechanism_u"]), (.30, metrics["pto_law_u"])])
        for scenario_id, metrics in sm.items()
    }
    causal = result["causal_metrics"]
    causal_components = {
        "wave_excitation": core.utility(causal["wave_excitation_gain_high_over_low"], 1.5, 1.05, False),
        "body_response": core.utility(causal["heave_gain_high_over_low"], 1.2, 1.02, False),
        "pto_force_response": core.utility(causal["damping_force_change_fraction"], .08, .01, False),
        "pto_velocity_response": core.utility(causal["damping_velocity_change_fraction"], .05, .005, False),
    }

    groups = dict(result["groups_normalized"])
    # Quality is based on observed boundedness in every operating regime.
    groups["Q"] = min(metrics["bounded_u"] for metrics in values)
    groups["M"] = min(per_scenario_mechanism.values())
    groups["C"] = min(causal_components.values())
    groups["D"] = min(metrics["startup_u"] for metrics in values)
    raw = core.strict_weighted_geometric(result["G"], groups, core.WEIGHTS)
    result.update({
        "evaluation_policy_id": POLICY_ID,
        "groups": {name: 100.0 * value for name, value in groups.items()},
        "groups_normalized": groups,
        "raw_score": raw,
        "admission_pass": bool(result["G"] and raw >= 90.0),
        "scoring_diagnostics": {
            "quality_uses_observed_boundedness": True,
            "mechanism_across_scenarios": "worst_case",
            "causality_across_intervention_obligations": "bottleneck",
            "dynamic_across_scenarios": "worst_case",
            "per_scenario_mechanism": per_scenario_mechanism,
            "causal_component_utilities": causal_components,
        },
    })
    return result


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    base = score_evidence(evidence)
    checks: dict[str, bool] = {}
    missing = copy.deepcopy(evidence)
    missing["scenarios"][0].pop("rm3_pto_response", None)
    checks["required_output_loses_score"] = score_evidence(missing)["raw_score"] < base["raw_score"]
    no_pto = copy.deepcopy(evidence)
    for item in no_pto["scenarios"]:
        item["rm3_pto_response"] = [[0.0, 0.0, 0.0, 0.0] for _ in item["time_s"]]
    checks["disconnected_pto_loses_score"] = score_evidence(no_pto)["raw_score"] < base["raw_score"]
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
