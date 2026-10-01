#!/usr/bin/env python3
"""Pure-offline scorer for F90-XAUTO-09 evidence.

G covers evidence integrity and anti-cheat checks.  Collision, causal-response
strength, structure detail, and dynamic quality are scored in R/D, C, M, and
A/Q/D respectively.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


TASK_ID = "F90-XAUTO-09"
SCENARIO_IDS = [
    "nominal_target_discrimination",
    "lower_driver_set_speed",
    "longer_time_gap",
    "stop_and_go",
    "curved_cut_in_out",
]
REQUIRED_LOGS = {
    "ego_acceleration",
    "ego_velocity",
    "driver_set_velocity",
    "relative_distance",
    "relative_velocity",
    "lateral_deviation",
    "relative_yaw_angle",
    "steering_angle",
    "collision",
}
STRUCTURE_METRICS = [
    "radar_and_vision_detection_path",
    "multi_object_fusion_and_lead_selection",
    "detected_lane_center_estimation",
    "coupled_longitudinal_lateral_mpc",
    "finite_mass_vehicle_dynamics",
    "closed_sensor_control_vehicle_loop",
    "native_fusion_derived_range_rate_logs",
    "native_lane_derived_lateral_yaw_logs",
]
ANTI_CHEAT_STRUCTURE = [
    "finite_mass_vehicle_dynamics",
    "closed_sensor_control_vehicle_loop",
]
WEIGHTS = {"A": 0.25, "Q": 0.10, "M": 0.20, "C": 0.20, "R": 0.15, "D": 0.10}
CONTROL_WINDOW_START_S = 1.0
TAIL_FRACTION = 0.20
def clip(value: float) -> float:
    return max(0.0, min(100.0, float(value)))


def low_good(value: float, full: float, zero: float) -> float:
    if value <= full:
        return 100.0
    if value >= zero:
        return 0.0
    return 100.0 * (zero - value) / (zero - full)


def high_good(value: float, zero: float, full: float) -> float:
    if value >= full:
        return 100.0
    if value <= zero:
        return 0.0
    return 100.0 * (value - zero) / (full - zero)


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return math.nan
    location = (len(ordered) - 1) * fraction
    lower = int(math.floor(location))
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (location - lower)


def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        str(item.get("id", "")): item
        for item in evidence.get("scenarios", [])
        if isinstance(item, dict)
    }


def _finite_scalar_list(value: Any, minimum: int = 100) -> bool:
    return (
        isinstance(value, list)
        and len(value) >= minimum
        and all(
            isinstance(item, (int, float)) and math.isfinite(float(item))
            for item in value
        )
    )


def _subject(evidence: dict[str, Any], requested: str) -> str:
    if requested in {"candidate", "reference"}:
        return requested
    schema = str(evidence.get("schema", ""))
    return "reference" if "fixed-evidence" in schema else "candidate"


def structure_ready(evidence: dict[str, Any], subject: str) -> bool:
    if subject != "candidate":
        return True
    structure = evidence.get("structure", {})
    return (
        evidence.get("structure_policy_id") == "f90_xauto09_structure_policy"
        and structure.get("schema") == "simuverity.f90-xauto09-structure-audit.v1"
        and structure.get("audit_complete") is True
    )


def gate(
    evidence: dict[str, Any], subject: str,
) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get("task_id") != TASK_ID:
        failures.append("wrong_task_id")
    for key in (
        "load_pass", "update_pass", "compile_pass", "simulate_pass",
        "all_official_evidence_valid",
    ):
        if evidence.get(key) is not True:
            failures.append(key)
    structure = evidence.get("structure", {})
    for name in ANTI_CHEAT_STRUCTURE:
        if structure.get(name) is not True:
            failures.append(f"anti_cheat:{name}")

    scenarios = scenario_map(evidence)
    if list(scenarios) != SCENARIO_IDS:
        failures.append("scenario_set_or_order")
    for sid in SCENARIO_IDS:
        row = scenarios.get(sid)
        if not row or row.get("valid") is not True:
            failures.append(f"{sid}:invalid")
            continue
        logs = row.get("logs", {})
        if not REQUIRED_LOGS.issubset(logs):
            failures.append(f"{sid}:missing_required_output")
            continue
        stop_time = float(row.get("stop_time_s", math.nan))
        common_time: list[float] | None = None
        for name in REQUIRED_LOGS:
            log = logs.get(name, {})
            times, values = log.get("time"), log.get("data")
            if not _finite_scalar_list(times) or not _finite_scalar_list(values):
                failures.append(f"{sid}:{name}:nonfinite_or_short")
                continue
            if len(times) != len(values):
                failures.append(f"{sid}:{name}:length_mismatch")
                continue
            if any(float(times[index]) <= float(times[index - 1]) for index in range(1, len(times))):
                failures.append(f"{sid}:{name}:time_not_strictly_increasing")
            if common_time is None:
                common_time = [float(value) for value in times]
            elif len(common_time) != len(times) or any(
                abs(left - float(right)) > 1e-9 for left, right in zip(common_time, times)
            ):
                failures.append(f"{sid}:{name}:time_not_aligned")
            if math.isfinite(stop_time) and (
                float(times[0]) > 0.1 or float(times[-1]) < stop_time - max(0.2, 0.01 * stop_time)
            ):
                failures.append(f"{sid}:{name}:incomplete_time_coverage")

        inputs = row.get("inputs", row.get("requested_inputs", {}))
        requested = float(inputs.get("driver_set_velocity_mps", math.nan))
        observed = logs.get("driver_set_velocity", {}).get("data", [])
        if (
            not math.isfinite(requested)
            or not observed
            or max(abs(float(value) - requested) for value in observed) > 0.05
        ):
            failures.append(f"{sid}:driver_set_velocity_log_fidelity")
    return not failures, failures


def derived_metrics(row: dict[str, Any]) -> dict[str, float | bool]:
    logs = row["logs"]
    times = [float(value) for value in logs["ego_velocity"]["time"]]
    speed = [float(value) for value in logs["ego_velocity"]["data"]]
    set_speed = [float(value) for value in logs["driver_set_velocity"]["data"]]
    distance = [float(value) for value in logs["relative_distance"]["data"]]
    lateral = [float(value) for value in logs["lateral_deviation"]["data"]]
    yaw = [float(value) for value in logs["relative_yaw_angle"]["data"]]
    collision = [float(value) for value in logs["collision"]["data"]]
    inputs = row.get("inputs", row.get("requested_inputs", {}))
    time_gap = float(inputs["time_gap_s"])
    default_spacing = float(inputs["default_spacing_m"])
    control_indices = [index for index, value in enumerate(times) if value >= CONTROL_WINDOW_START_S]
    tail_start = times[-1] * (1.0 - TAIL_FRACTION)
    tail_indices = [index for index, value in enumerate(times) if value >= tail_start]
    margins = [
        distance[index] - speed[index] * time_gap - default_spacing
        for index in control_indices
    ]
    tail_margins = [
        distance[index] - speed[index] * time_gap - default_spacing
        for index in tail_indices
    ]
    fraction = mean([1.0 if value >= 0.0 else 0.0 for value in margins])
    margin_p05 = percentile(margins, 0.05)
    spacing_utility = mean([
        high_good(fraction, 0.50, 0.98),
        high_good(margin_p05, -5.0, 0.50),
    ])
    return {
        "control_window_start_s": CONTROL_WINDOW_START_S,
        "safe_spacing_fraction": fraction,
        "safe_spacing_margin_p05_m": margin_p05,
        "safe_spacing_margin_min_m": min(margins),
        "safe_spacing_utility": spacing_utility,
        "tail_window_start_s": tail_start,
        "tail_safe_spacing_fraction": mean(
            [1.0 if value >= 0.0 else 0.0 for value in tail_margins]
        ),
        "tail_speed_tracking_mae_mps": mean(
            [abs(set_speed[index] - speed[index]) for index in tail_indices]
        ),
        "tail_lateral_deviation_mae_m": mean(
            [abs(lateral[index]) for index in tail_indices]
        ),
        "tail_relative_yaw_mae_rad": mean(
            [abs(yaw[index]) for index in tail_indices]
        ),
        "collision_any_from_log": any(value > 0.5 for value in collision),
    }


def _performance(
    evidence: dict[str, Any], scenarios: dict[str, dict[str, Any]]
) -> tuple[dict[str, float], dict[str, Any], dict[str, Any]]:
    metrics = {sid: scenarios[sid]["metrics"] for sid in SCENARIO_IDS}
    derived = {sid: derived_metrics(scenarios[sid]) for sid in SCENARIO_IDS}
    nominal, lower, longer, stopgo, cutin = SCENARIO_IDS

    straight_speed = mean([
        low_good(float(metrics[sid]["speed_tracking_rmse_mps"]), 1.0, 8.0)
        for sid in SCENARIO_IDS[:3]
    ])
    spacing = mean([
        float(derived[sid]["safe_spacing_utility"]) for sid in SCENARIO_IDS
    ])
    stopgo_control = mean([
        high_good(float(metrics[stopgo]["ego_speed_range_mps"]), 4.0, 10.0),
        low_good(float(derived[stopgo]["tail_speed_tracking_mae_mps"]), 2.0, 10.0),
        float(derived[stopgo]["safe_spacing_utility"]),
        0.0 if derived[stopgo]["collision_any_from_log"] else 100.0,
    ])
    cutin_longitudinal = mean([
        low_good(float(derived[cutin]["tail_speed_tracking_mae_mps"]), 0.5, 5.0),
        float(derived[cutin]["safe_spacing_utility"]),
        0.0 if derived[cutin]["collision_any_from_log"] else 100.0,
    ])
    cutin_lateral = mean([
        low_good(float(derived[cutin]["tail_lateral_deviation_mae_m"]), 0.05, 0.30),
        low_good(float(derived[cutin]["tail_relative_yaw_mae_rad"]), 0.02, 0.12),
    ])
    group_components: dict[str, Any] = {
        "A": {
            "straight_speed_tracking": straight_speed,
            "safe_spacing_fraction_and_margin": spacing,
            "stop_and_go_control": stopgo_control,
            "cut_in_longitudinal": cutin_longitudinal,
            "cut_in_lateral": cutin_lateral,
        }
    }
    groups = {"A": mean(list(group_components["A"].values()))}

    quality_by_scenario: dict[str, float] = {}
    for sid in SCENARIO_IDS:
        row = metrics[sid]
        command_bounds = mean([
            low_good(float(row["acceleration_abs_max_mps2"]), 3.2, 6.0),
            low_good(float(row["steering_abs_max_rad"]), 0.27, 0.60),
        ])
        quality_by_scenario[sid] = mean([
            low_good(float(row["jerk_rms_mps3"]), 2.0, 12.0),
            low_good(float(row["steering_rate_rms_radps"]), 0.10, 1.50),
            command_bounds,
        ])
    groups["Q"] = mean(list(quality_by_scenario.values()))
    group_components["Q"] = quality_by_scenario

    structure_detail = {
        name: 100.0 if evidence.get("structure", {}).get(name) is True else 0.0
        for name in STRUCTURE_METRICS
    }
    groups["M"] = mean(list(structure_detail.values()))
    group_components["M"] = structure_detail

    speed_input_delta = abs(
        float(metrics[lower]["driver_set_speed_mean_mps"])
        - float(metrics[nominal]["driver_set_speed_mean_mps"])
    )
    speed_output_delta = abs(
        float(metrics[lower]["ego_speed_mean_mps"])
        - float(metrics[nominal]["ego_speed_mean_mps"])
    )
    causal = {
        "driver_set_velocity": min(
            high_good(speed_input_delta, 1.0, 5.0),
            high_good(speed_output_delta, 0.5, 3.0),
        ),
        "time_gap": high_good(
            abs(
                float(metrics[longer]["relative_distance_min_m"])
                - float(metrics[nominal]["relative_distance_min_m"])
            ),
            2.0,
            10.0,
        ),
        "stop_and_go_traffic": high_good(
            float(metrics[stopgo]["ego_speed_range_mps"]), 4.0, 10.0
        ),
        "curved_lane": min(
            high_good(float(metrics[cutin]["lateral_deviation_abs_max_m"]), 0.01, 0.08),
            high_good(float(metrics[cutin]["steering_abs_max_rad"]), 0.005, 0.04),
        ),
    }
    groups["C"] = mean(list(causal.values()))
    group_components["C"] = causal

    safety_by_scenario: dict[str, float] = {}
    for sid in SCENARIO_IDS:
        row = metrics[sid]
        safety_by_scenario[sid] = mean([
            0.0 if derived[sid]["collision_any_from_log"] else 100.0,
            float(derived[sid]["safe_spacing_utility"]),
            low_good(float(row["acceleration_abs_max_mps2"]), 3.2, 6.0),
            low_good(float(row["steering_abs_max_rad"]), 0.27, 0.60),
            high_good(float(row["relative_distance_min_m"]), 2.0, 10.0),
        ])
    groups["R"] = 0.60 * min(safety_by_scenario.values()) + 0.40 * mean(
        list(safety_by_scenario.values())
    )
    group_components["R"] = {
        "aggregation": "0.60*worst_scenario+0.40*scenario_mean",
        "scenario_safety": safety_by_scenario,
    }

    stopgo_dynamic = mean([
        high_good(float(metrics[stopgo]["ego_speed_range_mps"]), 4.0, 10.0),
        low_good(float(derived[stopgo]["tail_speed_tracking_mae_mps"]), 2.0, 10.0),
        high_good(float(derived[stopgo]["tail_safe_spacing_fraction"]), 0.70, 0.98),
        low_good(float(metrics[stopgo]["jerk_rms_mps3"]), 2.0, 12.0),
        0.0 if derived[stopgo]["collision_any_from_log"] else 100.0,
    ])
    cutin_dynamic = mean([
        low_good(float(derived[cutin]["tail_speed_tracking_mae_mps"]), 0.5, 5.0),
        low_good(float(derived[cutin]["tail_lateral_deviation_mae_m"]), 0.05, 0.30),
        low_good(float(derived[cutin]["tail_relative_yaw_mae_rad"]), 0.02, 0.12),
        high_good(float(derived[cutin]["tail_safe_spacing_fraction"]), 0.70, 0.98),
        low_good(float(metrics[cutin]["steering_rate_rms_radps"]), 0.10, 1.50),
        0.0 if derived[cutin]["collision_any_from_log"] else 100.0,
    ])
    groups["D"] = mean([stopgo_dynamic, cutin_dynamic])
    group_components["D"] = {
        "stop_and_go_recovery_and_smoothness": stopgo_dynamic,
        "cut_in_recovery_and_smoothness": cutin_dynamic,
    }

    groups = {name: round(clip(value), 9) for name, value in groups.items()}
    return groups, group_components, derived


def score(
    evidence: dict[str, Any], requested_subject: str = "auto",
    context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    subject = _subject(evidence, requested_subject)
    passed, failures = gate(evidence, subject)
    ready = structure_ready(evidence, subject)
    waiting_for_structure = passed and not ready
    scenarios = scenario_map(evidence)
    if passed and ready:
        groups, components, derived = _performance(evidence, scenarios)
        raw_total = round(sum(WEIGHTS[name] * groups[name] for name in WEIGHTS), 9)
    elif waiting_for_structure:
        groups = {name: None for name in WEIGHTS}
        components, derived = {}, {}
        raw_total = None
    else:
        groups = {name: 0.0 for name in WEIGHTS}
        components, derived = {}, {}
        raw_total = 0.0

    reference_findings = {
        "safe_spacing_defect": (
            "The scoring core records but does not score safe-spacing fraction/margin. "
            "The reference has sustained post-start violations in nominal and "
            "longer-time-gap cases, so they are performance deductions, not an "
            "initialization-only exclusion."
        ),
        "window_rule": (
            "Ignore only t<1.0 s initialization; score fraction and the 5th-percentile "
            "margin so one brief lead-selection excursion cannot dominate the run."
        ),
    }
    g_value = None if waiting_for_structure else (1 if passed else 0)
    readiness_failures = ["structure_policy_required"] if waiting_for_structure else []
    return {
        "schema": "simuverity.f90-xauto09-offline-score.v1",
        "status": "AWAITING_STRUCTURE_EVIDENCE" if waiting_for_structure else (
            "SCORED" if passed else "INELIGIBLE_EVIDENCE"
        ),
        "task_id": TASK_ID,
        "subject": subject,
        "G": g_value,
        "raw_total": raw_total,
        "total": raw_total,
        "groups": groups,
        "metrics": {
            "group_components": components,
            "safe_spacing_semantics": reference_findings,
            "control_window_start_s": CONTROL_WINDOW_START_S,
            "tail_fraction": TAIL_FRACTION,
        },
        "scenarios": {
            sid: {
                "source_metrics": scenarios.get(sid, {}).get("metrics", {}),
                "derived_metrics": derived.get(sid, {}),
            }
            for sid in SCENARIO_IDS
        },
        "weights": WEIGHTS,
        "gate": {"G": g_value, "passed": None if waiting_for_structure else passed, "failures": failures},
        "readiness": {"structure_evidence_ready": ready, "failures": readiness_failures},
        "score_eligible": passed and ready,
        "scoring_completed": passed and ready,
        "offline_only": True,
        "matlab_invoked": False,
        "group_scores": groups,
        "raw_score": raw_total,
        "failure_reasons": failures,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--subject", choices=("auto", "candidate", "reference"), default="auto")
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    result = score(evidence, args.subject)
    (args.output_dir / "score.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
