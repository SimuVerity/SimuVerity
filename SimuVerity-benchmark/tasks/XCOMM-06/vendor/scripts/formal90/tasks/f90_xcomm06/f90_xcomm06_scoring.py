#!/usr/bin/env python3
"""F90-XCOMM-06 scorer that withdraws only unearned FrameValid credit."""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path

import f90_xcomm06_scoring_core as base
import f90_xcomm06_group_aggregation as geometric
import f90_xcomm06_diagnostics as active


POLICY_ID = "simuverity-101-v1:f90-xcomm-06:scoring"
REQUIRED = tuple(base.REQUIRED)
FRAME_FINDING = "frame-valid output is permanently asserted"
WITHDRAWAL_REASON = (
    "frame-valid asserted from capture time zero; "
    "FrameValid-dependent credits withdrawn"
)


def frame_valid_from_capture_zero(evidence: dict) -> bool:
    """Return true only for exact 1.0/0.0 values in every required scenario."""
    rows = {str(row.get("id")): row for row in evidence.get("scenarios", [])}
    if any(name not in rows for name in REQUIRED):
        return False
    for name in REQUIRED:
        metrics = rows[name].get("metrics", {})
        try:
            frame_valid_fraction = float(metrics["frame_valid_fraction"])
            acquisition_fraction = float(metrics["acquisition_fraction"])
        except (KeyError, TypeError, ValueError):
            return False
        if (
            not math.isfinite(frame_valid_fraction)
            or not math.isfinite(acquisition_fraction)
            or frame_valid_fraction != 1.0
            or acquisition_fraction != 0.0
        ):
            return False
    return True


def _recompute_r_without_frame_valid_credit(
    evidence: dict, diagnostics: dict
) -> tuple[float, dict[str, float], dict[str, dict[str, float]]]:
    rows = {str(row.get("id")): row for row in evidence["scenarios"]}
    scores: dict[str, float] = {}
    utilities: dict[str, dict[str, float]] = {}
    for name in REQUIRED:
        metrics = rows[name]["metrics"]
        parts = {
            "reported_ber": base.low(float(metrics["reported_ber"]), 1e-4, 0.05),
            "bit_accuracy": base.high(
                float(metrics["bit_accuracy"]), 0.92, 0.998
            ),
            "frame_recovery": 0.0,
            "synchronized_constellation": base.low(
                float(metrics["rx_synchronized_evm"]), 0.25, 0.75
            ),
            "residual_cfo": base.low(
                float(metrics["residual_cfo_hz"]), 10.0, 220.0
            ),
            "delay_profile": base.high(
                float(diagnostics["delay_profile_scores"][name]), 0.45, 0.90
            ),
        }
        utilities[name] = parts
        scores[name] = base.weighted(
            list(parts.values()), [0.25, 0.20, 0.15, 0.15, 0.10, 0.15]
        )
    return min(scores.values()), scores, utilities


def score_evidence(evidence: dict) -> dict:
    result = copy.deepcopy(active.score_evidence(evidence))
    groups = copy.deepcopy(result["groups"])
    diagnostics = copy.deepcopy(result.get("diagnostics", {}))
    exact_condition = frame_valid_from_capture_zero(evidence)
    applied = bool(result.get("G")) and exact_condition

    pre_groups = copy.deepcopy(groups)
    withdrawals: list[dict[str, object]] = []
    if applied:
        a_parts = copy.deepcopy(diagnostics["A_utilities"])
        a_parts["valid_frame_recovery"] = 0.0
        groups["A"] = base.weighted(
            [
                a_parts["reported_ber"],
                a_parts["payload_bit_accuracy"],
                a_parts["synchronized_constellation"],
                a_parts["valid_frame_recovery"],
            ],
            [0.35, 0.30, 0.20, 0.15],
        )
        diagnostics["A_utilities"] = a_parts
        withdrawals.append({
            "group": "A",
            "component": "valid_frame_recovery",
            "withdrawn_weight": 0.15,
        })

        q_parts = copy.deepcopy(diagnostics["Q_utilities"])
        q_parts["frame_continuity"] = 0.0
        groups["Q"] = base.weighted(
            [
                q_parts["physical_error_count_agreement"],
                q_parts["worst_constellation_evm"],
                q_parts["worst_residual_cfo"],
                q_parts["ber_denominator_integrity"],
                q_parts["frame_continuity"],
            ],
            [0.30, 0.175, 0.175, 0.175, 0.175],
        )
        diagnostics["Q_utilities"] = q_parts
        withdrawals.append({
            "group": "Q",
            "component": "frame_continuity",
            "withdrawn_weight": 0.175,
        })

        r_score, r_scores, r_utilities = _recompute_r_without_frame_valid_credit(
            evidence, diagnostics
        )
        groups["R"] = r_score
        diagnostics["R_scenario_scores"] = r_scores
        diagnostics["R_scenario_utilities"] = r_utilities
        withdrawals.append({
            "group": "R",
            "component": "frame_recovery_each_scenario",
            "withdrawn_weight": 0.15,
        })

        d_parts = copy.deepcopy(diagnostics["D_utilities"])
        d_parts["cold_start_acquisition"] = 0.0
        d_parts["post_acquisition_continuity"] = 0.0
        d_parts["tracking_under_delay_motion"] = 0.0
        groups["D"] = base.weighted(
            [
                d_parts["cold_start_acquisition"],
                d_parts["post_acquisition_continuity"],
                d_parts["tracking_under_delay_motion"],
                d_parts["ramp_and_triangle_delay_realized"],
            ],
            [0.30, 0.25, 0.25, 0.20],
        )
        diagnostics["D_utilities"] = d_parts
        withdrawals.extend([
            {
                "group": "D",
                "component": "cold_start_acquisition",
                "withdrawn_weight": 0.30,
            },
            {
                "group": "D",
                "component": "post_acquisition_continuity",
                "withdrawn_weight": 0.25,
            },
            {
                "group": "D",
                "component": "tracking_under_delay_motion",
                "withdrawn_weight": 0.25,
            },
        ])

    total = geometric.strict_geometric_total(result["G"], groups)
    failures = list(result.get("failure_reasons", []))
    diagnostic_findings = list(
        result.get("diagnostic_findings", [])
    )
    if applied:
        diagnostic_findings = [
            reason for reason in diagnostic_findings if reason != FRAME_FINDING
        ]
        failures = [
            reason
            for reason in failures
            if not (
                reason.endswith(" group below 0.60")
                or reason == FRAME_FINDING
                or reason == WITHDRAWAL_REASON
            )
        ]
        failures.extend(
            f"{name} group below 0.60"
            for name in base.WEIGHTS
            if groups[name] < 0.60
        )
        failures.append(WITHDRAWAL_REASON)

    result.update({
        "schema": "simuverity.f90-xcomm06-score.v1",
        "policy_id": POLICY_ID,
        "groups": groups,
        "score": total,
        "admission_score_pass": bool(
            result["G"] and total >= result["admission_threshold"]
        ),
        "diagnostics": diagnostics,
        "failure_reasons": failures,
        "diagnostic_findings": diagnostic_findings,
        "frame_valid_from_capture_zero": {
            "triggered": exact_condition,
            "credit_withdrawal_applied": applied,
            "credit_withdrawal_only": True,
            "condition": (
                "every required scenario has exact "
                "frame_valid_fraction == 1.0 and acquisition_fraction == 0.0"
            ),
            "approximate_or_rounded_match_forbidden": True,
            "pre_withdrawal_groups": pre_groups,
            "post_withdrawal_groups": copy.deepcopy(groups),
            "withdrawals": withdrawals,
            "preserved_independent_evidence": [
                "BER",
                "bit_accuracy",
                "EVM",
                "CFO",
                "channel_activity",
                "delay_profile",
            ],
        },
        "total_aggregation": {
            "method": "G_times_strict_weighted_geometric_mean",
            "applicable_groups": list(geometric.APPLICABLE),
            "zero_group_rule": "any applicable zero group makes total zero",
            "epsilon_floor": "none",
            "post_total_cap_or_floor": "none",
            "frame_valid_dependent_component_credit_withdrawal": True,
            "whole_group_forced_to_zero_by_this_rule": False,
        },
    })
    return result


def frame_valid_shortcut_sanity(evidence: dict) -> dict:
    fixture = copy.deepcopy(evidence)
    rows = {str(row.get("id")): row for row in fixture.get("scenarios", [])}
    for name in REQUIRED:
        metrics = rows[name]["metrics"]
        metrics["frame_valid_fraction"] = 1.0
        metrics["post_acquisition_valid_fraction"] = 1.0
        metrics["acquisition_fraction"] = 0.0
        metrics["longest_post_acquisition_invalid_fraction"] = 0.0
    result = score_evidence(fixture)
    return {
        "schema": "simuverity.f90-xcomm06.v1-frame-valid-sanity.v1",
        "task_id": "F90-XCOMM-06",
        "policy_id": POLICY_ID,
        "fixture_basis": "deep copy of supplied evidence",
        "fixture_mutations": {
            "frame_valid_fraction": 1.0,
            "post_acquisition_valid_fraction": 1.0,
            "acquisition_fraction": 0.0,
            "longest_post_acquisition_invalid_fraction": 0.0,
            "all_other_evidence_fields_preserved": True,
        },
        "exact_fixture_mutation_only": True,
        "matlab_or_simulation_invoked": False,
        "result": result,
        "all_pass": bool(
            result["frame_valid_from_capture_zero"]["triggered"]
            and result["score"] < result["admission_threshold"]
            and all(result["groups"][name] > 0.0 for name in geometric.APPLICABLE)
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--frame-valid-sanity-out", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name("score.json")
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    sanity_summary = None
    if args.frame_valid_sanity_out:
        sanity = frame_valid_shortcut_sanity(evidence)
        args.frame_valid_sanity_out.write_text(
            json.dumps(sanity, indent=2), encoding="utf-8"
        )
        sanity_summary = {
            "all_pass": sanity["all_pass"],
            "out": str(args.frame_valid_sanity_out),
        }
    print(json.dumps({
        "score": result["score"],
        "groups": result["groups"],
        "triggered": result["frame_valid_from_capture_zero"]["triggered"],
        "frame_valid_sanity": sanity_summary,
        "out": str(out),
    }))


if __name__ == "__main__":
    main()
