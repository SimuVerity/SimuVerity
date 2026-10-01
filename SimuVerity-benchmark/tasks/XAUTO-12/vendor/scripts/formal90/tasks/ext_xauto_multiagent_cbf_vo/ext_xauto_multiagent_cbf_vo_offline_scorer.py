"""Pure-offline scorer for EXT-XAUTO-MULTIAGENT-CBF-VO."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import ext_xauto_multiagent_cbf_vo_scoring_core as core

POLICY_ID = "simuverity-101-v1:ext-xauto-multiagent-cbf-vo:scoring"


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    scenarios = evidence.get("scenarios", [])
    base = copy.deepcopy(core.score(evidence))
    if base["G"] != 100.0 or not scenarios:
        base["evaluation_policy_id"] = POLICY_ID
        return base

    navigation = [core.navigation(item) for item in scenarios]
    safety = [core.safety(item) for item in scenarios]
    quality = [
        1.0 if core.state_available(item) and core.control_available(item)
        and item.get("finite") and item.get("coverage_fraction", 0) >= .999 else 0.0
        for item in scenarios
    ]
    control_guard = min(core.high(item.get("control_rms"), 1e-5, .05) for item in scenarios)
    copy_guard = min(core.low(item.get("goal_copy_fraction", 1), .01, .8) for item in scenarios)
    coupled = core.avg([core.high(item.get("avoidance_modulation"), 1e-5, .03) for item in scenarios])
    # The public contract names solver_exit_flag but does not publish a
    # success/failure polarity.  Do not reward zero or punish positive values
    # using an evaluator-only convention.  Finite exposure remains in Q.
    dynamics = [
        core.avg([
            core.low(item.get("control_bound_violation_fraction"), 0, .03),
            core.low(item.get("passive_motion_rmse_m"), .03, .5),
            core.low(item.get("passive_control_rms"), 1e-6, .02),
        ])
        for item in scenarios
    ]
    groups = {
        "A": core.avg(navigation),
        "Q": min(quality),
        # Physical separation is required in every mission, not on average.
        "M": min(min(safety), control_guard),
        "C": min(copy_guard, core.replay_utility(scenarios), core.avg([coupled, control_guard])),
        "R": min(core.avg([navigation[index], safety[index]]) for index in range(len(scenarios))),
        "D": min(dynamics),
    }
    total = core.strict_weighted_geometric(1.0, groups, core.WEIGHTS)
    base.update({
        "evaluation_policy_id": POLICY_ID,
        "groups": {name: round(100.0 * value, 6) for name, value in groups.items()},
        "total_raw": round(total, 6),
        "scoring_diagnostics": {
            "physical_safety_across_scenarios": "worst_case",
            "solver_exit_flag_value_scoring": "not_scored_because_public_polarity_is_undefined",
            "per_scenario_safety": {
                str(item.get("id")): 100.0 * safety[index]
                for index, item in enumerate(scenarios)
            },
        },
    })
    return base


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    baseline = score(evidence)
    checks: dict[str, bool] = {}
    missing = copy.deepcopy(evidence)
    missing["scenarios"][0].update(control_available=False, control_width=0)
    checks["missing_control_strict_zero"] = score(missing)["total_raw"] == 0
    collision = copy.deepcopy(evidence)
    collision["scenarios"][0].update(minimum_separation_margin_m=-.15, collision_fraction=.02)
    checks["single_mission_collision_reduces_mechanism"] = score(collision)["groups"]["M"] < baseline["groups"]["M"]
    replay = copy.deepcopy(evidence)
    signature = replay["scenarios"][0].get("response_signature", [])
    for item in replay["scenarios"]:
        item["response_signature"] = signature
    checks["single_replay_loses_score"] = score(replay)["total_raw"] < baseline["total_raw"]
    return {"task_id": core.TASK_ID, "checks": checks, "pass": all(checks.values())}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--shortcut-output", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(score(evidence), indent=2) + "\n", encoding="utf-8")
    if args.shortcut_output:
        args.shortcut_output.write_text(json.dumps(shortcut_sanity(evidence), indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
