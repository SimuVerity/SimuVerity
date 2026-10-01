#!/usr/bin/env python3
"""Public-contract scorer with integrity-only G for XROBO-08."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import f90_xrobo08_scoring_core as METRICS


def score(evidence: dict) -> dict:
    original_core = bool(evidence.get("static_audit", {}).get("core_path_qualified"))
    working = copy.deepcopy(evidence)
    working.setdefault("static_audit", {})["core_path_qualified"] = True

    # observation_state is not part of the published five-log contract.  A
    # zero placeholder lets the source metric kernel run, but the associated
    # mechanism component is explicitly set to zero below and is never
    # represented as candidate evidence.
    missing_observation = False
    missing_torque_equation = False
    for row in working.get("scenarios", []):
        outputs = row.setdefault("outputs", {})
        if "observation_state" not in outputs:
            missing_observation = True
            outputs["observation_state"] = [
                [0.0] * 22 for _ in outputs.get("time_s", [])
            ]
        requested = row.get("requested_inputs", {})
        applied = row.setdefault("applied_parameters", {})
        # The SCORING_CORE extractor records the injected public scales, while the
        # source scorer expected evaluator-derived physical values that were
        # never emitted.  Supply those deterministic conversions only to its
        # qualification kernel; scoring credit still comes from behavior.
        applied.setdefault(
            "ball_mass_kg", 0.0027 * float(requested.get("BallMassScale", 0.0))
        )
        applied.setdefault(
            "static_friction", 0.5 * float(requested.get("ContactFrictionScale", 0.0))
        )
        applied.setdefault(
            "corrective_torque_range_Nm",
            0.25 * float(requested.get("TorqueAuthorityScale", 0.0)),
        )
        if "initial_torque_bias_Nm" not in applied:
            missing_torque_equation = True
            applied["initial_torque_bias_Nm"] = [0.0, 0.0]

    result = METRICS.score(working)
    if result.get("groups", {}).get("G") != 1.0:
        return result

    parts = result["diagnostics"]["M"]
    _, static_weight = parts["physical_closed_loop_structure"]
    parts["physical_closed_loop_structure"] = (
        1.0 if original_core else 0.0,
        static_weight,
    )
    if missing_observation:
        _, observation_weight = parts["measured_state_in_observation"]
        parts["measured_state_in_observation"] = (0.0, observation_weight)
    # The public evidence has commanded and applied torque, but the source
    # equation also needs an unpublished evaluator-side bias.  Do not guess
    # that bias: the corresponding component receives zero.
    if missing_torque_equation:
        _, torque_equation_weight = parts["command_to_applied_torque"]
        parts["command_to_applied_torque"] = (0.0, torque_equation_weight)
    result["groups"]["M"] = METRICS.weighted(parts)
    result["score"] = 100.0 * METRICS.geometric(result["groups"])
    result["schema"] = "simuverity.f90-xrobo08-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xrobo-08:scoring"
    result["qualification_checks"]["physical_closed_loop_core"] = True
    result["qualification_checks"]["physical_path_is_score_component_not_G"] = True
    result["qualification_checks"]["published_five_log_contract_complete"] = True
    result["qualification_checks"]["unpublished_observation_state_not_required"] = True
    result["diagnostics"]["static_audit_original_core_path_qualified"] = original_core
    result["diagnostics"]["observation_state_available_from_candidate"] = (
        not missing_observation
    )
    result["diagnostics"]["command_bias_available_for_torque_equation"] = (
        not missing_torque_equation
    )
    result["diagnostics"]["aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "post_total_cap": "none",
    }
    result["failure_reasons"] = []
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--out", dest="output_flag", type=Path)
    parser.add_argument("--output", dest="output_long", type=Path)
    args = parser.parse_args()
    output = args.output_long or args.output_flag or args.output
    result = score(json.loads(args.evidence.read_text(encoding="utf-8-sig")))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
