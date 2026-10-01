#!/usr/bin/env python3
"""Dedicated offline scorer for F90-XAUTO-04."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


TASK_ID = "F90-XAUTO-04"
POLICY_ID = "simuverity-101-v1:f90-xauto-04:scoring"
SPLIT_MU_CLOSED_LOOP_RESPONSE_MISSING_SANITY_MAX = 55.0
REQUIRED_IDS = {
    "nominal_uniform",
    "uniform_low_friction",
    "uniform_high_demand",
    "longitudinal_low_patch",
    "left_right_split_mu",
    "lower_speed_reduced_demand",
}
WEIGHTS = {"A": 0.15, "Q": 0.15, "M": 0.30, "R": 0.25, "D": 0.15}


def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def lower(value: float, full: float, zero: float) -> float:
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clamp((zero - value) / (zero - full))


def higher(value: float, zero: float, full: float) -> float:
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clamp((value - zero) / (full - zero))


def band(value: float, low_zero: float, low_full: float,
         high_full: float, high_zero: float) -> float:
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return higher(value, low_zero, low_full)
    return lower(value, high_full, high_zero)


def weighted(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum(weight for _, weight in parts.values())
    if denominator <= 0:
        return 0.0
    return sum(clamp(score) * weight for score, weight in parts.values()) / denominator


def geometric(groups: dict[str, float]) -> float:
    if any(groups[key] <= 0 for key in WEIGHTS):
        return 0.0
    return math.exp(sum(WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS))


def rows(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row["id"]): row for row in evidence.get("scenarios", [])}


def rel(base: float, changed: float, floor: float = 1e-9) -> float:
    return abs(float(changed) - float(base)) / max(abs(float(base)), floor)


def max_value(value: Any) -> float:
    return max(float(item) for item in value)


def min_value(value: Any) -> float:
    return min(float(item) for item in value)


def scenario_operability(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metric = row["metrics"]
    request = row["requested_inputs"]
    # A longitudinal friction transition can legitimately trigger TCS brake
    # pressure before the driver's distance-based brake request.  The public
    # BrakeState signal does not identify those two pressure sources, so the
    # trigger metric is not observable in this scenario.  It remains tested in
    # every uniform-road scenario and in the nominal A group.
    distance_trigger_score = (
        1.0
        if row.get("class") == "friction_transition"
        else lower(float(metric["brake_start_relative_error"]), 0.04, 0.20)
    )
    parts = {
        "target_speed_attainment": (
            lower(float(metric["target_speed_relative_error"]), 0.04, 0.18),
            0.15,
        ),
        "distance_trigger_accuracy": (
            distance_trigger_score,
            0.10,
        ),
        "requested_deceleration_tracking": (
            lower(
                abs(float(metric["mean_deceleration_mps2"])
                    - 9.80665 * float(request["RequestedDeceleration_g"]))
                / max(9.80665 * float(request["RequestedDeceleration_g"]), 0.25),
                0.12,
                0.60,
            ),
            0.25,
        ),
        "meaningful_speed_reduction": (
            higher(float(metric["speed_reduction_fraction"]), 0.25, 0.60),
            0.15,
        ),
        "wheel_lock_suppression": (
            lower(float(metric["lock_fraction_any_wheel"]), 0.05, 0.40),
            0.15,
        ),
        "directional_stability": (
            lower(float(metric["maximum_abs_yaw_rate_rad_s"]), 0.18, 0.85),
            0.10,
        ),
        "lateral_containment": (
            lower(float(metric["maximum_abs_lateral_displacement_m"]), 0.55, 3.0),
            0.05,
        ),
        "four_tire_force_paths": (
            higher(float(metric["four_tire_force_active_fraction"]), 0.25, 0.80),
            0.05,
        ),
    }
    return weighted(parts), parts


def scenario_dynamics(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metric = row["metrics"]
    request = row["requested_inputs"]
    decel_error = abs(
        float(metric["mean_deceleration_mps2"])
        - 9.80665 * float(request["RequestedDeceleration_g"])
    ) / max(9.80665 * float(request["RequestedDeceleration_g"]), 0.25)
    parts = {
        "pressure_response_delay": (
            lower(float(metric["pressure_response_delay_s"]), 0.10, 0.65),
            0.20,
        ),
        "deceleration_response": (lower(decel_error, 0.12, 0.60), 0.30),
        "pressure_tracks_command": (
            lower(float(metric["brake_pressure_tracking_nrmse_worst"]), 0.12, 0.75),
            0.15,
        ),
        "pressure_is_dynamic": (
            higher(float(metric["brake_pressure_transitions_min"]), 2.0, 20.0),
            0.10,
        ),
        "bounded_lateral_transient": (
            lower(float(metric["maximum_abs_lateral_acceleration_mps2"]), 1.5, 6.0),
            0.10,
        ),
        "speed_response": (
            higher(float(metric["speed_reduction_fraction"]), 0.25, 0.60),
            0.15,
        ),
    }
    return weighted(parts), parts


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    by_id = rows(evidence)
    static = evidence.get("static_audit", {})
    qualification = {
        "load": bool(evidence.get("load_pass")),
        "update": bool(evidence.get("update_pass")),
        "compile": bool(evidence.get("compile_pass")),
        "scenario_set": set(by_id) == REQUIRED_IDS,
        "all_scenarios_valid": set(by_id) == REQUIRED_IDS
        and all(bool(by_id[key].get("valid")) for key in REQUIRED_IDS),
        "dynamic_vehicle_evidence": bool(
            static.get("minimum_dynamic_vehicle_signature")
        ),
    }
    gate = all(qualification.values())
    if not gate:
        return {
            "schema": "simuverity.f90-xauto04-score.v1",
            "task_id": TASK_ID,
            "policy_id": POLICY_ID,
            "G": 0.0,
            "groups": {key: 0.0 for key in WEIGHTS},
            "group_weights": WEIGHTS,
            "score_raw": 0.0,
            "admission_threshold_raw": 85.0,
            "preferred_reference_target_raw": 90.0,
            "admission_pass": False,
            "qualification_checks": qualification,
            "failures": [
                name for name, passed in qualification.items() if not passed
            ],
        }

    nominal = by_id["nominal_uniform"]["metrics"]
    request = by_id["nominal_uniform"]["requested_inputs"]
    nominal_decel_error = abs(
        float(nominal["mean_deceleration_mps2"])
        - 9.80665 * float(request["RequestedDeceleration_g"])
    ) / (9.80665 * float(request["RequestedDeceleration_g"]))
    a_parts = {
        "target_speed_attainment": (
            lower(float(nominal["target_speed_relative_error"]), 0.05, 0.15),
            0.20,
        ),
        "distance_trigger_accuracy": (
            lower(float(nominal["brake_start_relative_error"]), 0.025, 0.15),
            0.15,
        ),
        "requested_deceleration_tracking": (
            lower(nominal_decel_error, 0.10, 0.50),
            0.25,
        ),
        "effective_speed_reduction": (
            higher(float(nominal["speed_reduction_fraction"]), 0.30, 0.62),
            0.15,
        ),
        "limited_wheel_lock": (
            lower(float(nominal["lock_fraction_any_wheel"]), 0.03, 0.35),
            0.15,
        ),
        "straight_line_stability": (
            lower(float(nominal["maximum_abs_yaw_rate_rad_s"]), 0.08, 0.50),
            0.10,
        ),
    }
    group_a = weighted(a_parts)

    q_parts = {
        "bounded_slip_tail": (
            lower(float(nominal["worst_abs_slip_p95"]), 0.35, 0.85),
            0.25,
        ),
        "limited_severe_lock": (
            lower(float(nominal["severe_lock_fraction_all_wheels"]), 0.02, 0.30),
            0.20,
        ),
        "pressure_tracking": (
            lower(float(nominal["brake_pressure_tracking_nrmse_worst"]), 0.12, 0.75),
            0.15,
        ),
        "four_pressure_channels_present": (
            higher(min_value(nominal["brake_pressure_peak"]), 1e-6, 0.03
                   * max_value(nominal["brake_pressure_peak"])),
            0.10,
        ),
        "four_tire_force_channels_active": (
            higher(float(nominal["four_tire_force_active_fraction"]), 0.25, 0.85),
            0.15,
        ),
        "physical_force_balance": (
            lower(float(nominal["force_cross_channel_spread"]), 0.50, 1.50),
            0.05,
        ),
        "finite_independent_wheel_evidence": (
            1.0 if float(nominal["wheel_speed_identical_fraction"]) < 0.9999 else 0.4,
            0.10,
        ),
    }
    group_q = weighted(q_parts)

    low = by_id["uniform_low_friction"]["metrics"]
    high_demand = by_id["uniform_high_demand"]["metrics"]
    patch = by_id["longitudinal_low_patch"]["metrics"]
    split = by_id["left_right_split_mu"]["metrics"]
    reduced = by_id["lower_speed_reduced_demand"]["metrics"]

    friction_response = max(
        rel(float(nominal["brake_pressure_cross_channel_spread"]),
            float(low["brake_pressure_cross_channel_spread"]), 0.01),
        rel(float(nominal["worst_abs_slip_p95"]),
            float(low["worst_abs_slip_p95"]), 0.02),
        rel(float(nominal["abs_any_active_fraction"]),
            float(low["abs_any_active_fraction"]), 0.02),
        rel(float(nominal["mean_deceleration_mps2"]),
            float(low["mean_deceleration_mps2"]), 0.25),
    )
    demand_response = max(
        rel(max_value(nominal["brake_pressure_peak"]),
            max_value(high_demand["brake_pressure_peak"]), 1e-6),
        rel(float(nominal["mean_deceleration_mps2"]),
            float(high_demand["mean_deceleration_mps2"]), 0.25),
        rel(float(nominal["longitudinal_tire_force_peak_n"][0]),
            float(high_demand["longitudinal_tire_force_peak_n"][0]), 50.0),
    )
    patch_response = max(
        rel(float(nominal["worst_abs_slip_p95"]),
            float(patch["worst_abs_slip_p95"]), 0.02),
        rel(float(nominal["abs_any_active_fraction"]),
            float(patch["abs_any_active_fraction"]), 0.02),
        rel(max_value(nominal["brake_pressure_peak"]),
            max_value(patch["brake_pressure_peak"]), 1e-6),
    )
    split_response = max(
        abs(float(split["brake_pressure_cross_channel_spread"])
            - float(nominal["brake_pressure_cross_channel_spread"])),
        abs(float(split["wheel_speed_cross_channel_spread"])
            - float(nominal["wheel_speed_cross_channel_spread"])),
        abs(float(split["force_cross_channel_spread"])
            - float(nominal["force_cross_channel_spread"])),
    )
    lower_speed_response = rel(
        float(nominal["command_onset_s"]),
        float(reduced["command_onset_s"]),
        1.0,
    )
    m_parts = {
        "full_vehicle_mechanism": (
            1.0 if static.get("full_vehicle_mechanism") else 0.0,
            0.15,
        ),
        "closed_loop_four_channel_mechanism": (
            1.0 if static.get("closed_loop_four_channel_mechanism") else 0.0,
            0.15,
        ),
        "spatial_friction_mechanism": (
            1.0 if static.get("spatial_friction_mechanism") else 0.0,
            0.10,
        ),
        "uniform_friction_causal_response": (
            higher(friction_response, 0.02, 0.18),
            0.15,
        ),
        "brake_demand_causal_response": (
            higher(demand_response, 0.01, 0.10),
            0.15,
        ),
        "longitudinal_patch_causal_response": (
            higher(patch_response, 0.02, 0.18),
            0.10,
        ),
        "split_mu_independent_response": (
            higher(split_response, 0.005, 0.08),
            0.15,
        ),
        "lower_speed_operating_response": (
            higher(lower_speed_response, 0.03, 0.10),
            0.05,
        ),
    }
    split_abs_utility = higher(float(split["abs_any_active_fraction"]), 0.01, 0.15)
    split_closed_loop_utility = max(
        m_parts["split_mu_independent_response"][0], split_abs_utility
    )
    # Split-friction independent modulation is a named public requirement.
    # Retain 40% M credit for the otherwise connected vehicle/brake mechanism;
    # the remaining capability follows the measured split-mu response.
    group_m = min(weighted(m_parts), 0.40 + 0.60 * split_closed_loop_utility)

    robustness: dict[str, float] = {}
    robustness_parts: dict[str, Any] = {}
    dynamics: dict[str, float] = {}
    dynamics_parts: dict[str, Any] = {}
    for key in sorted(REQUIRED_IDS):
        robustness[key], robustness_parts[key] = scenario_operability(by_id[key])
        dynamics[key], dynamics_parts[key] = scenario_dynamics(by_id[key])
    # A generic successful stop on an effectively uniform road cannot count as
    # full split-friction robustness or split-friction closed-loop dynamics.
    robustness["left_right_split_mu"] = min(
        robustness["left_right_split_mu"],
        0.40 + 0.60 * split_closed_loop_utility,
    )
    dynamics["left_right_split_mu"] = min(
        dynamics["left_right_split_mu"],
        0.40 + 0.60 * split_closed_loop_utility,
    )
    group_r = min(robustness.values())
    group_d = min(dynamics.values())

    groups = {"A": group_a, "Q": group_q, "M": group_m,
              "R": group_r, "D": group_d}
    raw = 100.0 * geometric(groups)
    shortcut_findings: list[dict[str, str]] = []

    copied_wheels = all(
        float(by_id[key]["metrics"]["wheel_speed_identical_fraction"]) > 0.999
        and float(by_id[key]["metrics"]["worst_abs_slip_p95"]) < 0.01
        for key in REQUIRED_IDS
    )
    if copied_wheels:
        shortcut_findings.append({"id": "vehicle_speed_copied_to_four_wheels"})

    identical_open_loop = (
        float(split["identical_pressure_fraction"]) > 0.98
        and float(split["brake_pressure_cross_channel_spread"]) < 0.002
        and float(split["wheel_speed_cross_channel_spread"]) > 0.01
    )
    if identical_open_loop:
        shortcut_findings.append({"id": "identical_open_loop_split_mu_braking"})

    if min(
        float(by_id[key]["metrics"]["brake_pressure_transitions_min"])
        for key in REQUIRED_IDS
    ) < 1.0:
        shortcut_findings.append({"id": "constant_brake_pressure"})

    if (
        friction_response < 0.01
        and demand_response < 0.01
        and patch_response < 0.01
        and split_response < 0.003
        and lower_speed_response < 0.02
    ):
        shortcut_findings.append({"id": "nominal_response_replayed"})

    if not static.get("closed_loop_four_channel_mechanism"):
        shortcut_findings.append({"id": "missing_four_channel_closed_loop_mechanism"})

    split_abs_activity = float(split["abs_any_active_fraction"])
    split_mu_response_missing = (
        split_response < 0.005 and split_abs_activity <= 1e-9
    )
    return {
        "schema": "simuverity.f90-xauto04-score.v1",
        "task_id": TASK_ID,
        "policy_id": POLICY_ID,
        "G": 1.0,
        "groups": groups,
        "group_weights": WEIGHTS,
        "score_raw": raw,
        "admission_threshold_raw": 85.0,
        "preferred_reference_target_raw": 90.0,
        "admission_pass": raw >= 85.0,
        "qualification_checks": qualification,
        "details": {
            "A": a_parts,
            "Q": q_parts,
            "M": {
                "parts": m_parts,
                "causal_response": {
                    "uniform_friction": friction_response,
                    "high_demand": demand_response,
                    "longitudinal_patch": patch_response,
                    "split_mu": split_response,
                    "lower_speed": lower_speed_response,
                },
                "split_mu_closed_loop_diagnostic": {
                    "independent_response": split_response,
                    "abs_active_fraction": split_abs_activity,
                    "utility": split_closed_loop_utility,
                    "pass": not split_mu_response_missing,
                },
            },
            "R": {
                "aggregation": "100_percent_worst_scenario",
                "by_scenario": robustness,
                "parts": robustness_parts,
            },
            "D": {
                "aggregation": "100_percent_worst_scenario",
                "by_scenario": dynamics,
                "parts": dynamics_parts,
            },
        },
        "shortcut_findings": shortcut_findings,
        "failures": [item["id"] for item in shortcut_findings] + (
            ["SPLIT_MU_CLOSED_LOOP_RESPONSE_MISSING"]
            if split_mu_response_missing else []
        ),
    }


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []

    missing = copy.deepcopy(evidence)
    missing["scenarios"][0]["valid"] = False
    cases.append(("missing_required_output", missing, 0.0))

    disconnected = copy.deepcopy(evidence)
    disconnected["static_audit"]["minimum_dynamic_vehicle_signature"] = False
    cases.append(("missing_dynamic_vehicle", disconnected, 0.0))

    copied = copy.deepcopy(evidence)
    for row in copied["scenarios"]:
        metric = row["metrics"]
        metric["wheel_speed_identical_fraction"] = 1.0
        metric["worst_abs_slip_p95"] = 0.0
        metric["wheel_speed_cross_channel_spread"] = 0.0
        metric["controlled_slip_fraction"] = 0.0
    cases.append(("vehicle_speed_copied_to_wheels", copied, 55.0))

    open_loop = copy.deepcopy(evidence)
    split_metric = rows(open_loop)["left_right_split_mu"]["metrics"]
    split_metric["identical_pressure_fraction"] = 1.0
    split_metric["brake_pressure_cross_channel_spread"] = 0.0
    split_metric["wheel_speed_cross_channel_spread"] = 0.10
    cases.append(("identical_open_loop_pressure", open_loop, 65.0))

    missing_split_response = copy.deepcopy(evidence)
    nominal_metric = rows(missing_split_response)["nominal_uniform"]["metrics"]
    missing_split_metric = rows(missing_split_response)["left_right_split_mu"]["metrics"]
    for field in (
        "brake_pressure_cross_channel_spread",
        "wheel_speed_cross_channel_spread",
        "force_cross_channel_spread",
    ):
        missing_split_metric[field] = nominal_metric[field]
    missing_split_metric["abs_any_active_fraction"] = 0.0
    cases.append((
        "split_mu_closed_loop_response_missing",
        missing_split_response,
        SPLIT_MU_CLOSED_LOOP_RESPONSE_MISSING_SANITY_MAX,
    ))

    constant = copy.deepcopy(evidence)
    for row in constant["scenarios"]:
        row["metrics"]["brake_pressure_transitions_min"] = 0.0
    cases.append(("constant_pressure", constant, 70.0))

    replay = copy.deepcopy(evidence)
    nominal = copy.deepcopy(rows(replay)["nominal_uniform"]["metrics"])
    for row in replay["scenarios"]:
        row["metrics"] = copy.deepcopy(nominal)
    cases.append(("nominal_response_replayed", replay, 60.0))

    results = []
    for case_id, mutated, required_maximum in cases:
        scored = score(mutated)
        raw = float(scored["score_raw"])
        results.append({
            "id": case_id,
            "score_raw": raw,
            "required_maximum": required_maximum,
            "pass": raw <= required_maximum + 1e-9 and raw < 85.0,
        })
    return {
        "schema": "simuverity.f90-xauto04-shortcut-sanity.v1",
        "task_id": TASK_ID,
        "cases": results,
        "all_rejected": all(item["pass"] for item in results),
    }


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sanity-output", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score(evidence)
    write_json(args.output, result)
    if args.sanity_output:
        write_json(args.sanity_output, shortcut_sanity(evidence))
    print(f"{TASK_ID} G={result['G']:.0f} "
          f"raw={float(result['score_raw']):.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
