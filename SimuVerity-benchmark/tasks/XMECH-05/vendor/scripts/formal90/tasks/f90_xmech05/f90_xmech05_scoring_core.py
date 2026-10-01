#!/usr/bin/env python3
"""Pure offline scorer for fixed F90-XMECH-05 evidence."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


TASK_ID = "F90-XMECH-05"
GROUP_WEIGHTS = {"A": 0.25, "Q": 0.15, "M": 0.25, "R": 0.20, "D": 0.15}


def clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def higher(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if full <= zero:
        return float(value >= full)
    return clip((value - zero) / (full - zero))


def lower(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if zero <= full:
        return float(value <= full)
    return clip((zero - value) / (zero - full))


def band(value: float, low_zero: float, low_full: float,
         high_full: float, high_zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return min(
        higher(value, low_zero, low_full),
        lower(value, high_full, high_zero),
    )


def weighted_mean(items: list[tuple[float, float]]) -> float:
    total = sum(weight for _, weight in items)
    return sum(clip(value) * weight for value, weight in items) / total


def geometric(groups: dict[str, float]) -> float:
    if any(groups[name] <= 0.0 for name in GROUP_WEIGHTS):
        return 0.0
    return math.exp(
        sum(GROUP_WEIGHTS[name] * math.log(groups[name]) for name in GROUP_WEIGHTS)
    )


def number(mapping: dict[str, Any], key: str, default: float = math.nan) -> float:
    try:
        return float(mapping.get(key, default))
    except (TypeError, ValueError):
        return default


def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row.get("id", "")): row for row in evidence.get("scenarios", [])}


def metrics(row: dict[str, Any]) -> dict[str, Any]:
    value = row.get("metrics", {})
    return value if isinstance(value, dict) else {}


def relative_change(a: float, b: float) -> float:
    if not math.isfinite(a) or not math.isfinite(b):
        return 0.0
    return abs(a - b) / max(abs(a), 1e-12)


def retention(value: float, nominal: float, floor: float = 0.0) -> float:
    if not math.isfinite(value) or not math.isfinite(nominal) or nominal <= 0:
        return 0.0
    return clip((value / nominal - floor) / max(1.0 - floor, 1e-12))


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    scenarios = scenario_map(evidence)
    required = int(evidence.get("required_scenario_count", 7))
    all_valid = (
        bool(evidence.get("pass"))
        and bool(evidence.get("all_scenarios_valid"))
        and len(scenarios) == required
        and all(bool(row.get("valid")) for row in scenarios.values())
    )
    if not all_valid or "nominal" not in scenarios:
        return result(0, {name: 0.0 for name in GROUP_WEIGHTS}, 0.0, [],
                      ["qualification_or_required_evidence_failed"])

    nominal = metrics(scenarios["nominal"])
    structure = evidence.get("structure", {})
    diagnostics: list[dict[str, Any]] = []

    a_items = [
        metric("chassis_horizontal_excursion", number(nominal, "chassis_horizontal_excursion_m"),
               higher(number(nominal, "chassis_horizontal_excursion_m"), 4.0, 11.0), 0.18, diagnostics),
        metric("payload_horizontal_excursion", number(nominal, "payload_horizontal_excursion_m"),
               higher(number(nominal, "payload_horizontal_excursion_m"), 2.5, 7.0), 0.18, diagnostics),
        metric("payload_vertical_excursion", number(nominal, "payload_vertical_excursion_m"),
               higher(number(nominal, "payload_vertical_excursion_m"), 2.0, 8.0), 0.18, diagnostics),
        metric("lift_extension_range", number(nominal, "lift_extension_range_m"),
               higher(number(nominal, "lift_extension_range_m"), 0.25, 1.0), 0.16, diagnostics),
        metric("tilt_extension_range", number(nominal, "tilt_extension_range_m"),
               higher(number(nominal, "tilt_extension_range_m"), 0.012, 0.05), 0.12, diagnostics),
        metric("payload_final_settling", number(nominal, "payload_final_speed_m_s"),
               lower(number(nominal, "payload_final_speed_m_s"), 0.03, 0.40), 0.18, diagnostics),
    ]
    A = weighted_mean([(x["utility"], x["weight"]) for x in a_items])

    support = nominal.get("wheel_support_fraction", [])
    support_min = min((float(v) for v in support), default=0.0)
    q_items = [
        metric("finite_fraction", number(nominal, "finite_fraction"),
               higher(number(nominal, "finite_fraction"), 0.97, 0.9999), 0.15, diagnostics),
        metric("vehicle_quaternion_norm", number(nominal, "vehicle_quaternion_norm_error"),
               lower(number(nominal, "vehicle_quaternion_norm_error"), 1e-5, 0.05), 0.12, diagnostics),
        metric("payload_quaternion_norm", number(nominal, "payload_quaternion_norm_error"),
               lower(number(nominal, "payload_quaternion_norm_error"), 1e-5, 0.05), 0.12, diagnostics),
        metric("four_wheel_support", support_min,
               higher(support_min, 0.15, 0.55), 0.22, diagnostics),
        metric("wheel_load_balance", number(nominal, "wheel_load_imbalance"),
               lower(number(nominal, "wheel_load_imbalance"), 0.25, 0.80), 0.14, diagnostics),
        metric("physical_normal_force", number(nominal, "mean_total_normal_force_N"),
               higher(number(nominal, "mean_total_normal_force_N"), 100.0, 3000.0), 0.13, diagnostics),
        metric("finite_continuing_vehicle_motion",
               number(nominal, "chassis_final_speed_m_s"),
               band(number(nominal, "chassis_final_speed_m_s"),
                    0.02, 0.20, 2.0, 4.0), 0.12, diagnostics),
    ]
    Q = weighted_mean([(x["utility"], x["weight"]) for x in q_items])

    structure_utility = weighted_mean([
        (higher(number(structure, "joint_count"), 4, 20), 0.30),
        (higher(number(structure, "solid_count"), 4, 20), 0.20),
        (higher(number(structure, "spatial_contact_count"), 2, 12), 0.25),
        (higher(number(structure, "connected_physical_port_count"), 20, 100), 0.25),
    ])
    heavy = metrics(scenarios.get("heavy_payload", {}))
    low_friction = metrics(scenarios.get("low_friction", {}))
    large_bump = metrics(scenarios.get("large_bump", {}))
    heavy_response = relative_change(
        number(nominal, "mean_total_normal_force_N"),
        number(heavy, "mean_total_normal_force_N"),
    )
    friction_response = relative_change(
        number(nominal, "friction_rms_N"),
        number(low_friction, "friction_rms_N"),
    )
    bump_response = relative_change(
        number(nominal, "chassis_vertical_excursion_m"),
        number(large_bump, "chassis_vertical_excursion_m"),
    )
    scenario_causality = weighted_mean([
        (higher(heavy_response, 0.002, 0.025), 0.40),
        (higher(friction_response, 0.001, 0.015), 0.30),
        (higher(bump_response, 0.001, 0.020), 0.30),
    ])
    m_items = [
        metric("connected_multibody_structure", structure_utility,
               structure_utility, 0.30, diagnostics),
        metric("lift_and_tilt_actuation", min(
            higher(number(nominal, "lift_extension_range_m"), 0.25, 0.9),
            higher(number(nominal, "tilt_extension_range_m"), 0.012, 0.045),
        ), min(
            higher(number(nominal, "lift_extension_range_m"), 0.25, 0.9),
            higher(number(nominal, "tilt_extension_range_m"), 0.012, 0.045),
        ), 0.18, diagnostics),
        metric("payload_vehicle_coupling",
               number(nominal, "payload_vehicle_motion_correlation"),
               higher(number(nominal, "payload_vehicle_motion_correlation"), 0.05, 0.45),
               0.17, diagnostics),
        metric("payload_lift_coupling",
               number(nominal, "payload_lift_correlation"),
               higher(abs(number(nominal, "payload_lift_correlation")), 0.05, 0.30),
               0.15, diagnostics),
        metric("official_input_causality", scenario_causality,
               scenario_causality, 0.20, diagnostics),
    ]
    M = weighted_mean([(x["utility"], x["weight"]) for x in m_items])

    retention_values: list[float] = []
    per_scenario_retention: dict[str, float] = {}
    for name, row in scenarios.items():
        if name == "nominal":
            continue
        current = metrics(row)
        values = [
            retention(number(current, "chassis_horizontal_excursion_m"),
                      number(nominal, "chassis_horizontal_excursion_m"), 0.65),
            retention(number(current, "payload_horizontal_excursion_m"),
                      number(nominal, "payload_horizontal_excursion_m"), 0.65),
            retention(number(current, "payload_vertical_excursion_m"),
                      number(nominal, "payload_vertical_excursion_m"), 0.65),
            retention(number(current, "lift_extension_range_m"),
                      number(nominal, "lift_extension_range_m"), 0.70),
            higher(number(current, "finite_fraction"), 0.97, 0.9999),
        ]
        utility = weighted_mean([(value, 1.0) for value in values])
        per_scenario_retention[name] = utility
        retention_values.append(utility)
    R = min(retention_values, default=0.0)
    diagnostics.append({
        "name": "worst_scenario_retention",
        "value": R,
        "utility": R,
        "weight": 1.0,
        "per_scenario": per_scenario_retention,
    })

    event_times = nominal.get("event_times_s", {})
    lift_onset = number(event_times, "lift_onset")
    payload_onset = number(event_times, "payload_lift_onset")
    event_coupling = 0.0
    if math.isfinite(lift_onset) and math.isfinite(payload_onset):
        delay = payload_onset - lift_onset
        if 0.0 <= delay <= 15.0:
            event_coupling = 1.0
        elif delay > 15.0:
            event_coupling = lower(delay, 15.0, 25.0)
    worst_payload_final_speed = max(
        number(metrics(row), "payload_final_speed_m_s", math.inf)
        for row in scenarios.values()
    )
    d_items = [
        metric("pickup_then_payload_lift_sequence",
               payload_onset - lift_onset
               if math.isfinite(lift_onset) and math.isfinite(payload_onset)
               else math.nan,
               event_coupling, 0.20, diagnostics),
        metric("obstacle_vertical_response", number(nominal, "chassis_vertical_excursion_m"),
               higher(number(nominal, "chassis_vertical_excursion_m"), 0.015, 0.09),
               0.15, diagnostics),
        metric("payload_dynamic_coupling", number(nominal, "payload_vehicle_motion_correlation"),
               higher(number(nominal, "payload_vehicle_motion_correlation"), 0.05, 0.45),
               0.15, diagnostics),
        metric("nominal_payload_placement_recovery",
               number(nominal, "payload_final_speed_m_s"),
               lower(number(nominal, "payload_final_speed_m_s"), 0.03, 0.40),
               0.15, diagnostics),
        metric("worst_case_payload_recovery", worst_payload_final_speed,
               lower(worst_payload_final_speed, 0.05, 0.90),
               0.35, diagnostics),
    ]
    D = weighted_mean([(x["utility"], x["weight"]) for x in d_items])

    groups = {"A": A, "Q": Q, "M": M, "R": R, "D": D}
    raw = 100.0 * geometric(groups)
    shortcut_findings: list[str] = []
    if structure_utility < 0.55:
        shortcut_findings.append("missing_or_inadequate_multibody_contact_structure")
    if A < 0.50:
        shortcut_findings.append("nominal_mission_not_completed")
    if scenario_causality < 0.40:
        shortcut_findings.append("scenario_inputs_do_not_change_physical_response")
    if min(
        number(nominal, "lift_extension_range_m"),
        20.0 * number(nominal, "tilt_extension_range_m"),
    ) < 0.20:
        shortcut_findings.append("lift_or_tilt_mechanism_inactive")
    if number(nominal, "mean_total_normal_force_N") <= 100.0:
        shortcut_findings.append("wheel_contact_evidence_missing")
    failures = [name for name, value in groups.items() if value < 0.5]
    return result(1, groups, raw, diagnostics, failures, shortcut_findings)


def metric(
    name: str,
    value: float,
    utility: float,
    weight: float,
    diagnostics: list[dict[str, Any]],
) -> dict[str, float]:
    row = {
        "name": name,
        "value": float(value),
        "utility": clip(utility),
        "weight": float(weight),
    }
    diagnostics.append(row)
    return row


def result(
    gate: int,
    groups: dict[str, float],
    score: float,
    diagnostics: list[dict[str, Any]],
    failures: list[str],
    shortcut_findings: list[str] | None = None,
) -> dict[str, Any]:
    finding_rows = [{"reason": reason} for reason in (shortcut_findings or [])]
    return {
        "schema": "simuverity.f90-xmech05-offline-score.v1",
        "task_id": TASK_ID,
        "G": int(gate),
        "groups": {name: clip(groups.get(name, 0.0)) for name in GROUP_WEIGHTS},
        "group_weights": GROUP_WEIGHTS,
        "score_raw": round(float(score), 10),
        "score_is_raw_not_rescaled": True,
        "admission_threshold": 85.0,
        "preferred_reference_target": 90.0,
        "admission_pass": gate == 1 and score >= 85.0,
        "diagnostics": diagnostics,
        "shortcut_findings": finding_rows,
        "failure_reasons": failures,
    }


def sanity_batch(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}

    missing = copy.deepcopy(evidence)
    missing["scenarios"] = missing.get("scenarios", [])[:-1]
    cases["required_scenario_missing"] = missing

    copied = copy.deepcopy(evidence)
    nominal = next(row for row in copied["scenarios"] if row["id"] == "nominal")
    for row in copied["scenarios"]:
        if row["id"] != "nominal":
            row["metrics"] = copy.deepcopy(nominal["metrics"])
            row["signals"] = copy.deepcopy(nominal.get("signals", {}))
    cases["nominal_trace_copied"] = copied

    constant_pose = copy.deepcopy(evidence)
    for row in constant_pose["scenarios"]:
        m = row["metrics"]
        for key in (
            "chassis_horizontal_excursion_m",
            "chassis_vertical_excursion_m",
            "payload_horizontal_excursion_m",
            "payload_vertical_excursion_m",
            "payload_net_displacement_m",
        ):
            m[key] = 0.0
        m["payload_vehicle_motion_correlation"] = 0.0
        m["payload_lift_correlation"] = 0.0
    cases["prescribed_or_constant_pose"] = constant_pose

    no_structure = copy.deepcopy(evidence)
    for key in (
        "joint_count",
        "solid_count",
        "spatial_contact_count",
        "connected_physical_port_count",
    ):
        no_structure["structure"][key] = 0
    cases["physical_structure_missing"] = no_structure

    no_contact = copy.deepcopy(evidence)
    for row in no_contact["scenarios"]:
        m = row["metrics"]
        m["mean_total_normal_force_N"] = 0.0
        m["peak_total_normal_force_N"] = 0.0
        m["wheel_support_fraction"] = [0.0, 0.0, 0.0, 0.0]
        m["all_wheels_support_fraction"] = 0.0
        m["friction_rms_N"] = 0.0
    cases["wheel_contact_missing"] = no_contact

    current_actuator = copy.deepcopy(evidence)
    for row in current_actuator["scenarios"]:
        m = row["metrics"]
        m["lift_extension_range_m"] = 0.0
        m["tilt_extension_range_m"] = 0.0
        m["fork_extension_range_m"] = 0.0
        m["payload_lift_correlation"] = 0.0
    cases["lift_and_tilt_current"] = current_actuator

    decoupled = copy.deepcopy(evidence)
    for row in decoupled["scenarios"]:
        m = row["metrics"]
        m["payload_horizontal_excursion_m"] = 0.0
        m["payload_vertical_excursion_m"] = 0.0
        m["payload_vehicle_motion_correlation"] = 0.0
        m["payload_lift_correlation"] = 0.0
    cases["payload_decoupled"] = decoupled

    rows = []
    for name, mutated in cases.items():
        scored = score_evidence(mutated)
        rows.append({
            "case": name,
            "score_raw": scored["score_raw"],
            "G": scored["G"],
            "rejected": scored["score_raw"] < 85.0,
        })
    return {
        "schema": "simuverity.f90-xmech05-shortcut-sanity.v1",
        "task_id": TASK_ID,
        "cases": rows,
        "all_rejected": all(row["rejected"] for row in rows),
        "maximum_shortcut_score": max(row["score_raw"] for row in rows),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence")
    parser.add_argument("--out", required=True)
    parser.add_argument("--sanity-out")
    args = parser.parse_args()

    evidence = json.loads(Path(args.evidence).read_text(encoding="utf-8"))
    scored = score_evidence(evidence)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(
        json.dumps(scored, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    if args.sanity_out:
        sanity = sanity_batch(evidence)
        Path(args.sanity_out).write_text(
            json.dumps(sanity, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        if not sanity["all_rejected"]:
            raise SystemExit("shortcut sanity failed")
    print(
        f"{TASK_ID} offline G={scored['G']} "
        f"score={scored['score_raw']:.4f} pass={int(scored['admission_pass'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
