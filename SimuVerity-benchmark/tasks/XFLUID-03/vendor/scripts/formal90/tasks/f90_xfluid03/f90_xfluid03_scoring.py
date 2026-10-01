#!/usr/bin/env python3
"""Offline scorer for F90-XFLUID-03.

Only score-free evidence is consumed here.  Weight, threshold, aggregation,
and shortcut-policy changes therefore never require MATLAB replay.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


TASK_ID = "F90-XFLUID-03"
POLICY_ID = 'simuverity-101-v1:f90-xfluid-03:scoring'
REQUIRED_IDS = {
    "nominal",
    "low_engine_speed",
    "reduced_pump_displacement",
    "deep_implement",
    "cohesive_soil",
    "combined_boundary",
}
WEIGHTS = {"A": 0.15, "Q": 0.15, "M": 0.30, "R": 0.25, "D": 0.15}


def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def lower_better(value: float, full: float, zero: float) -> float:
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clamp((zero - value) / (zero - full))


def higher_better(value: float, zero: float, full: float) -> float:
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clamp((value - zero) / (full - zero))


def band_score(value: float, low_zero: float, low_full: float,
               high_full: float, high_zero: float) -> float:
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return higher_better(value, low_zero, low_full)
    return lower_better(value, high_full, high_zero)


def weighted_mean(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum(weight for _, weight in parts.values())
    if denominator <= 0:
        return 0.0
    return sum(clamp(score) * weight for score, weight in parts.values()) / denominator


def geometric(groups: dict[str, float]) -> float:
    if any(groups[key] <= 0 for key in WEIGHTS):
        return 0.0
    return math.exp(sum(WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS))


def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row["id"]): row for row in evidence.get("scenarios", [])}


def relative_error(actual: float, requested: float) -> float:
    return abs(actual - requested) / max(abs(requested), 1e-9)


def scenario_operability(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metrics = row["metrics"]
    engine_error = relative_error(
        float(metrics["final_engine_speed_rpm"]),
        float(metrics["requested_engine_speed_rpm"]),
    )
    displacement_error = relative_error(
        float(metrics["final_pump_displacement_cm3_rev"]),
        float(metrics["requested_pump_displacement_cm3_rev"]),
    )
    parts = {
        "engine_command_realized": (lower_better(engine_error, 0.01, 0.08), 0.20),
        "pump_command_realized": (lower_better(displacement_error, 0.01, 0.08), 0.15),
        "stable_forward_motion": (
            higher_better(float(metrics["final_tractor_speed_kph"]), 0.10, 2.0),
            0.25,
        ),
        "pressure_protected": (
            lower_better(float(metrics["maximum_loop_pressure_bar"]), 250.0, 310.0),
            0.15,
        ),
        "finite_physics": (higher_better(float(metrics["finite_fraction"]), 0.98, 1.0), 0.15),
        "no_sustained_reverse": (
            lower_better(float(metrics["negative_vehicle_speed_fraction"]), 0.0, 0.10),
            0.10,
        ),
    }
    return weighted_mean(parts), parts


def dynamic_quality(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metrics = row["metrics"]
    parts = {
        "cold_start_rise": (
            band_score(
                float(metrics["cold_start_rise_time_s"]), 1.0, 4.0, 10.0, 20.0
            ),
            0.50,
        ),
        "late_speed_stability": (
            lower_better(float(metrics["late_vehicle_speed_cv"]), 0.01, 0.12),
            0.35,
        ),
        "no_reverse_excursion": (
            lower_better(float(metrics["negative_vehicle_speed_fraction"]), 0.0, 0.10),
            0.15,
        ),
    }
    return weighted_mean(parts), parts


def response_change(base: float, changed: float) -> float:
    return abs(changed - base) / max(abs(base), 1e-9)


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = scenario_map(evidence)
    static = evidence.get("static_audit", {})
    explicit_causal_signature = bool(
        static.get("causal_hydro_mechanical_signature")
        and static.get("front_drive_signature")
        and static.get("rear_drive_signature")
    )
    qualification_checks = {
        "load": bool(evidence.get("load_pass")),
        "update": bool(evidence.get("update_pass")),
        "compile": bool(evidence.get("compile_pass")),
        "scenario_set": set(rows) == REQUIRED_IDS,
        "all_scenarios_valid": set(rows) == REQUIRED_IDS
        and all(bool(rows[key].get("valid")) for key in REQUIRED_IDS),
        "required_products": bool(static.get("required_products_available")),
    }
    gate = all(qualification_checks.values())
    if not gate:
        return {
            "schema": "simuverity.f90-xfluid03-score.v1",
            "task_id": TASK_ID,
            "policy_id": POLICY_ID,
            "G": 0.0,
            "groups": {"A": 0.0, "Q": 0.0, "M": 0.0, "R": 0.0, "D": 0.0},
            "group_weights": WEIGHTS,
            "score_raw": 0.0,
            "admission_threshold_raw": 85.0,
            "admission_pass": False,
            "qualification_checks": qualification_checks,
            "failures": [
                name for name, passed in qualification_checks.items() if not passed
            ],
        }

    nominal = rows["nominal"]["metrics"]
    nominal_operability, nominal_parts = scenario_operability(rows["nominal"])
    nominal_engine_error = relative_error(
        float(nominal["final_engine_speed_rpm"]),
        float(nominal["requested_engine_speed_rpm"]),
    )
    nominal_disp_error = relative_error(
        float(nominal["final_pump_displacement_cm3_rev"]),
        float(nominal["requested_pump_displacement_cm3_rev"]),
    )
    group_a_parts = {
        "engine_speed": (lower_better(nominal_engine_error, 0.005, 0.05), 0.25),
        "pump_displacement": (lower_better(nominal_disp_error, 0.005, 0.05), 0.20),
        "forward_speed": (
            higher_better(float(nominal["final_tractor_speed_kph"]), 0.25, 3.0),
            0.25,
        ),
        "bounded_pressure": (
            lower_better(float(nominal["maximum_loop_pressure_bar"]), 245.0, 310.0),
            0.15,
        ),
        "complete_finite_output": (
            higher_better(float(nominal["finite_fraction"]), 0.995, 1.0),
            0.15,
        ),
    }
    group_a = weighted_mean(group_a_parts)

    efficiency = float(nominal["late_energy_efficiency"])
    loss_kw = float(nominal["late_transmission_loss_kw"])
    group_q_parts = {
        "axle_speed_consistency": (
            lower_better(float(nominal["axle_speed_relative_mismatch"]), 0.03, 0.30),
            0.20,
        ),
        "axle_torque_participation": (
            lower_better(float(nominal["axle_torque_relative_mismatch"]), 0.15, 0.75),
            0.15,
        ),
        "axle_flow_consistency": (
            lower_better(float(nominal["axle_flow_relative_mismatch"]), 0.05, 0.40),
            0.15,
        ),
        "energy_efficiency_physical": (
            band_score(efficiency, 0.25, 0.55, 0.95, 1.05),
            0.25,
        ),
        "nonzero_finite_loss": (
            band_score(loss_kw, 0.01, 0.10, 15.0, 30.0),
            0.25,
        ),
    }
    group_q = min(
        weighted_mean(group_q_parts),
        group_q_parts["nonzero_finite_loss"][0],
    )

    low_engine = rows["low_engine_speed"]["metrics"]
    low_disp = rows["reduced_pump_displacement"]["metrics"]
    deep = rows["deep_implement"]["metrics"]
    cohesive = rows["cohesive_soil"]["metrics"]
    engine_response = response_change(
        float(nominal["final_engine_speed_rpm"]),
        float(low_engine["final_engine_speed_rpm"]),
    )
    displacement_response = response_change(
        float(nominal["final_pump_displacement_cm3_rev"]),
        float(low_disp["final_pump_displacement_cm3_rev"]),
    )
    deep_effort = max(
        response_change(
            float(nominal["late_mean_input_power_kw"]),
            float(deep["late_mean_input_power_kw"]),
        ),
        response_change(
            float(nominal["maximum_loop_pressure_bar"]),
            float(deep["maximum_loop_pressure_bar"]),
        ),
    )
    soil_effort = max(
        response_change(
            float(nominal["late_mean_input_power_kw"]),
            float(cohesive["late_mean_input_power_kw"]),
        ),
        response_change(
            float(nominal["maximum_loop_pressure_bar"]),
            float(cohesive["maximum_loop_pressure_bar"]),
        ),
    )
    engine_causal = band_score(engine_response, 0.02, 0.10, 0.20, 0.35)
    pump_causal = band_score(displacement_response, 0.03, 0.15, 0.35, 0.50)
    implement_causal = band_score(deep_effort, 0.002, 0.01, 0.15, 0.35)
    soil_causal = band_score(soil_effort, 0.0005, 0.003, 0.04, 0.20)
    two_axles_deliver_power = (
        1.0
        if float(nominal["front_motor_torque_rms_nm"]) > 0.1
        and float(nominal["rear_motor_torque_rms_nm"]) > 0.1
        else 0.0
    )
    # Keep the structure check out of G so equivalent implementations remain
    # scoreable, but make it score-bearing in M: input sensitivity alone does
    # not establish the requested connected hydro-mechanical power path.
    causal_chain = min(
        engine_causal,
        pump_causal,
        implement_causal,
        soil_causal,
        two_axles_deliver_power,
    )
    group_m_parts = {
        "connected_hydro_mechanical_path": (
            float(explicit_causal_signature) * causal_chain,
            0.50,
        ),
        "engine_input_causal": (engine_causal, 0.10),
        "pump_input_causal": (pump_causal, 0.10),
        "implement_load_causal": (implement_causal, 0.10),
        "soil_load_causal": (soil_causal, 0.10),
        "two_axles_deliver_power": (two_axles_deliver_power, 0.10),
    }
    group_m = weighted_mean(group_m_parts)

    robustness_by_scenario: dict[str, float] = {}
    robustness_parts: dict[str, Any] = {}
    dynamic_by_scenario: dict[str, float] = {}
    dynamic_parts: dict[str, Any] = {}
    for key in sorted(REQUIRED_IDS):
        robustness_by_scenario[key], robustness_parts[key] = scenario_operability(rows[key])
        dynamic_by_scenario[key], dynamic_parts[key] = dynamic_quality(rows[key])
    group_r = min(robustness_by_scenario.values())
    group_d = min(dynamic_by_scenario.values())

    groups = {"A": group_a, "Q": group_q, "M": group_m, "R": group_r, "D": group_d}
    raw = 100.0 * geometric(groups)
    return {
        "schema": "simuverity.f90-xfluid03-score.v1",
        "task_id": TASK_ID,
        "policy_id": POLICY_ID,
        "G": 1.0,
        "groups": groups,
        "group_weights": WEIGHTS,
        "score_raw": raw,
        "admission_threshold_raw": 85.0,
        "admission_pass": raw >= 85.0,
        "qualification_checks": qualification_checks,
        "details": {
            "A": group_a_parts,
            "Q": group_q_parts,
            "M": {
                "parts": group_m_parts,
                "explicit_static_signature": explicit_causal_signature,
                "causal_response_ratios": {
                    "engine": engine_response,
                    "pump_displacement": displacement_response,
                    "implement_load": deep_effort,
                    "soil_load": soil_effort,
                },
            },
            "R": {
                "aggregation": "100_percent_minimum",
                "by_scenario": robustness_by_scenario,
                "parts": robustness_parts,
                "nominal_parts": nominal_parts,
                "nominal_operability": nominal_operability,
            },
            "D": {
                "aggregation": "100_percent_minimum",
                "by_scenario": dynamic_by_scenario,
                "parts": dynamic_parts,
            },
        },
        "failures": [],
    }


def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []

    missing_output = copy.deepcopy(evidence)
    missing_output["scenarios"][0]["valid"] = False
    cases.append(("required_output_missing", missing_output, 0.0))

    zero_loss = copy.deepcopy(evidence)
    for row in zero_loss["scenarios"]:
        row["metrics"]["late_transmission_loss_kw"] = 0.0
        row["metrics"]["late_energy_efficiency"] = 1.0
    cases.append(("zero_loss_energy_shortcut", zero_loss, 82.0))

    insensitive = copy.deepcopy(evidence)
    nominal_metrics = copy.deepcopy(scenario_map(insensitive)["nominal"]["metrics"])
    for row in insensitive["scenarios"]:
        requested = {
            key: value
            for key, value in row["metrics"].items()
            if key.startswith("requested_")
        }
        row["metrics"] = copy.deepcopy(nominal_metrics)
        row["metrics"].update(requested)
    cases.append(("workspace_inputs_only_in_logs", insensitive, 75.0))

    results = []
    for name, mutated, maximum in cases:
        result = score(mutated)
        value = float(result["score_raw"])
        results.append(
            {
                "id": name,
                "score_raw": value,
                "required_maximum": maximum,
                "pass": value <= maximum + 1e-9,
            }
        )
    return {
        "schema": "simuverity.f90-xfluid03-shortcut-sanity.v1",
        "task_id": TASK_ID,
        "cases": results,
        "pass": all(item["pass"] for item in results),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--sanity-out", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score(evidence)
    text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
    if args.sanity_out:
        sanity = run_shortcut_sanity(evidence)
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(
            json.dumps(sanity, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )
    print(text)


if __name__ == "__main__":
    main()
