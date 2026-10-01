#!/usr/bin/env python3
"""Pure-offline scorer for F90-XMECH-03 fixed evidence."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np


POLICY_ID = 'simuverity-101-v1:f90-xmech-03:scoring'
WEIGHTS = {"A": 0.20, "Q": 0.10, "M": 0.30, "R": 0.10, "D": 0.30}
REQUIRED_SCENARIOS = (
    "urban_short_nominal",
    "eudc_nominal",
    "ftp_transient_nominal",
    "urban_short_heavy",
    "urban_short_clutch_derated",
)


def clip01(value: float) -> float:
    return float(np.clip(value, 0.0, 1.0))


def ramp_up(value: float, bad: float, good: float) -> float:
    if good == bad:
        return float(value >= good)
    return clip01((value - bad) / (good - bad))


def ramp_down(value: float, good: float, bad: float) -> float:
    if good == bad:
        return float(value <= good)
    return clip01((bad - value) / (bad - good))


def corr_abs(left: np.ndarray, right: np.ndarray) -> float:
    left = np.asarray(left, dtype=float).ravel()
    right = np.asarray(right, dtype=float).ravel()
    mask = np.isfinite(left) & np.isfinite(right)
    if mask.sum() < 12:
        return 0.0
    if np.std(left[mask]) < 1e-10 or np.std(right[mask]) < 1e-10:
        return 0.0
    return float(abs(np.corrcoef(left[mask], right[mask])[0, 1]))


def load_scenarios(evidence_path: Path, evidence: dict) -> tuple[dict, list[str]]:
    rows = evidence.get("scenarios", [])
    failures: list[str] = []
    scenarios: dict[str, dict[str, np.ndarray]] = {}
    for row in rows:
        scenario_id = str(row.get("id", ""))
        if not row.get("success", False):
            failures.append(f"{scenario_id or 'unknown'}: simulation did not succeed")
            continue
        output_path = evidence_path.parent / str(row.get("output_file", ""))
        if not output_path.is_file():
            failures.append(f"{scenario_id}: output evidence file is missing")
            continue
        raw = json.loads(output_path.read_text(encoding="utf-8"))
        required = (
            "time_s",
            "speed_response",
            "engine_speed",
            "transmission_state",
            "engine_torque_demand",
        )
        missing_fields = [name for name in required if name not in raw]
        if missing_fields:
            failures.append(
                f"{scenario_id}: missing outputs {', '.join(missing_fields)}"
            )
            continue
        try:
            arrays = {
                "time_s": np.asarray(raw["time_s"], dtype=float).ravel(),
                "speed_response": np.asarray(raw["speed_response"], dtype=float),
                "engine_speed": np.asarray(
                    raw["engine_speed"], dtype=float
                ).reshape(-1, 1),
                "transmission_state": np.asarray(
                    raw["transmission_state"], dtype=float
                ),
                "engine_torque_demand": np.asarray(
                    raw["engine_torque_demand"], dtype=float
                ).reshape(-1, 1),
            }
        except (TypeError, ValueError) as error:
            failures.append(f"{scenario_id}: unreadable outputs ({error})")
            continue
        n = arrays["time_s"].size
        expected_shapes = {
            "speed_response": (n, 2),
            "engine_speed": (n, 1),
            "transmission_state": (n, 5),
            "engine_torque_demand": (n, 1),
        }
        if n <= 1024 or abs(arrays["time_s"][0]) > 1e-9:
            failures.append(f"{scenario_id}: evidence is truncated")
        for name, shape in expected_shapes.items():
            if arrays[name].shape != shape or not np.isfinite(arrays[name]).all():
                failures.append(f"{scenario_id}: invalid {name}")
        if np.any(np.diff(arrays["time_s"]) <= 0):
            failures.append(f"{scenario_id}: invalid time base")
        scenarios[scenario_id] = arrays
    missing = sorted(set(REQUIRED_SCENARIOS) - set(scenarios))
    failures.extend(f"missing scenario: {name}" for name in missing)
    return scenarios, failures


def event_indices(time: np.ndarray, gear: np.ndarray) -> np.ndarray:
    quantized = np.round(np.asarray(gear, dtype=float).ravel() * 2.0) / 2.0
    candidates = np.flatnonzero(np.abs(np.diff(quantized)) >= 0.25) + 1
    candidates = candidates[time[candidates] >= 1.0]
    kept: list[int] = []
    for index in candidates:
        if not kept or time[index] - time[kept[-1]] >= 0.5:
            kept.append(int(index))
    return np.asarray(kept, dtype=int)


def command_response_lag(
    time: np.ndarray, command: np.ndarray, measured: np.ndarray
) -> float:
    dt = float(np.median(np.diff(time)))
    dcommand = np.gradient(command, dt)
    dmeasured = np.gradient(measured, dt)
    if np.std(dcommand) < 1e-8 or np.std(dmeasured) < 1e-8:
        return float("inf")
    maximum = max(1, int(round(8.0 / dt)))
    scores = []
    for lag in range(maximum + 1):
        if lag == 0:
            scores.append(corr_abs(dcommand, dmeasured))
        else:
            scores.append(corr_abs(dcommand[:-lag], dmeasured[lag:]))
    return float(np.argmax(scores) * dt)


def contiguous_durations(time: np.ndarray, mask: np.ndarray) -> list[float]:
    indices = np.flatnonzero(mask)
    if indices.size == 0:
        return []
    breaks = np.flatnonzero(np.diff(indices) > 1) + 1
    groups = np.split(indices, breaks)
    return [float(time[group[-1]] - time[group[0]]) for group in groups]


def scenario_metrics(arrays: dict[str, np.ndarray]) -> dict[str, float]:
    time = arrays["time_s"]
    speed = arrays["speed_response"]
    command = speed[:, 0]
    measured = speed[:, 1]
    engine = arrays["engine_speed"][:, 0]
    state = arrays["transmission_state"]
    gear = state[:, 0]
    pressure = state[:, 1:3]
    slip = state[:, 3:5]
    torque = arrays["engine_torque_demand"][:, 0]
    dt = float(np.median(np.diff(time)))
    acceleration = np.gradient(measured / 3.6, dt)
    jerk = np.gradient(acceleration, dt)
    active = command >= max(3.0, 0.05 * float(np.max(command)))
    if active.sum() < 20:
        active = np.ones_like(command, dtype=bool)
    error = measured - command
    events = event_indices(time, gear)
    shift_local_jerk = []
    for index in events:
        window = np.abs(time - time[index]) <= 1.0
        shift_local_jerk.append(float(np.percentile(np.abs(jerk[window]), 95)))

    pressure_scale = max(float(np.percentile(np.abs(pressure), 99)), 1.0)
    transfer = []
    shift_error_fraction = []
    for index in events:
        window = np.abs(time - time[index]) <= 1.25
        pressure_range = np.ptp(pressure[window, :], axis=0)
        transfer.append(float(np.max(pressure_range) / pressure_scale))
        local_scale = max(float(np.max(command[window])), 20.0)
        shift_error_fraction.append(
            float(np.percentile(np.abs(error[window]), 90) / local_scale)
        )

    pressure_activity = np.ptp(pressure, axis=0)
    active_clutches = int(np.sum(pressure_activity >= 0.05 * pressure_scale))
    complete_slip = []
    for clutch in range(2):
        complete = pressure[:, clutch] >= 2.0e6
        if complete.sum() >= 10:
            complete_slip.append(float(np.percentile(np.abs(slip[complete, clutch]), 95)))
        else:
            complete_slip.append(float("inf"))

    fractional = np.abs(gear - np.round(gear)) >= 0.20
    durations = contiguous_durations(time, fractional)
    quantized = np.round(gear * 2.0) / 2.0
    directions = np.sign(np.diff(quantized))
    change_indices = np.flatnonzero(np.abs(directions) > 0)
    hunting = 0
    for left, right in zip(change_indices[:-1], change_indices[1:]):
        if directions[left] * directions[right] < 0 and time[right] - time[left] <= 5.0:
            hunting += 1

    return {
        "speed_rmse_kph": float(np.sqrt(np.mean(error[active] ** 2))),
        "speed_p95_abs_error_kph": float(np.percentile(np.abs(error[active]), 95)),
        "speed_max_abs_error_kph": float(np.max(np.abs(error[active]))),
        "speed_abs_correlation": corr_abs(command[active], measured[active]),
        "speed_command_to_response_lag_s": command_response_lag(
            time, command, measured
        ),
        "gear_valid_fraction": float(np.mean((gear >= -0.1) & (gear <= 6.5))),
        "gear_transition_count": int(events.size),
        "active_clutch_count": active_clutches,
        "shift_pressure_transfer_fraction": float(
            np.mean(np.asarray(transfer) >= 0.10) if transfer else 0.0
        ),
        # A stopped vehicle is not an engine overspeed/underspeed failure.  The
        # quality metric applies while the public command requests traction.
        "engine_safe_fraction": float(
            np.mean((engine[active] >= 200.0) & (engine[active] <= 7000.0))
        ),
        "engine_speed_max_rpm": float(np.max(engine)),
        "clutch_pressure_p99_pa": float(np.percentile(np.abs(pressure), 99)),
        "complete_clutch_slip_p95_rpm": float(max(complete_slip)),
        "longitudinal_jerk_p95_mps3": float(np.percentile(np.abs(jerk), 95)),
        "shift_local_jerk_p95_mps3": float(
            max(shift_local_jerk, default=float("inf"))
        ),
        "torque_to_acceleration_abs_correlation": corr_abs(torque, acceleration),
        "shift_error_fraction_p90": float(max(shift_error_fraction, default=1.0)),
        "median_fractional_shift_duration_s": float(
            np.median(durations) if durations else 8.0
        ),
        "gear_hunting_event_count": int(hunting),
        "measured_speed_range_kph": float(np.ptp(measured)),
        "torque_demand_range_nm": float(np.ptp(torque)),
        "clutch_slip_rms_rpm": float(np.sqrt(np.mean(slip**2))),
    }


def scenario_scores(metrics: dict[str, float]) -> dict[str, float]:
    achievement = (
        0.45 * ramp_down(metrics["speed_rmse_kph"], 2.0, 12.0)
        + 0.25 * ramp_down(metrics["speed_p95_abs_error_kph"], 5.0, 25.0)
        + 0.15 * ramp_up(metrics["speed_abs_correlation"], 0.55, 0.96)
        + 0.10 * ramp_up(metrics["gear_valid_fraction"], 0.90, 0.995)
        + 0.05 * ramp_up(metrics["gear_transition_count"], 1.0, 3.0)
    )
    quality = (
        0.30 * ramp_up(metrics["engine_safe_fraction"], 0.96, 1.0)
        + 0.20 * ramp_down(metrics["clutch_pressure_p99_pa"], 5.2e6, 7.0e6)
        + 0.30
        * ramp_down(metrics["complete_clutch_slip_p95_rpm"], 300.0, 1800.0)
        + 0.20 * ramp_down(metrics["longitudinal_jerk_p95_mps3"], 4.0, 20.0)
    )
    mechanism = (
        0.30 * ramp_up(metrics["active_clutch_count"], 1.0, 2.0)
        + 0.40
        * ramp_up(metrics["shift_pressure_transfer_fraction"], 0.20, 0.85)
        + 0.30
        * ramp_up(
            metrics["torque_to_acceleration_abs_correlation"], 0.10, 0.65
        )
    )
    pressure_slip_recovery = 0.50 * ramp_up(
        metrics["shift_pressure_transfer_fraction"], 0.20, 0.85
    ) + 0.50 * ramp_down(metrics["complete_clutch_slip_p95_rpm"], 300.0, 1800.0)
    dynamics = (
        0.40 * ramp_down(metrics["shift_local_jerk_p95_mps3"], 4.0, 20.0)
        + 0.25 * ramp_down(metrics["shift_error_fraction_p90"], 0.08, 0.35)
        + 0.20 * pressure_slip_recovery
        + 0.15 * ramp_down(metrics["gear_hunting_event_count"], 0.0, 4.0)
    )
    return {
        "A": clip01(achievement),
        "Q": clip01(quality),
        "M": clip01(mechanism),
        "D": clip01(dynamics),
    }


def behavior_distance(left: dict[str, np.ndarray], right: dict[str, np.ndarray]) -> float:
    n = min(left["time_s"].size, right["time_s"].size)
    terms = []
    for name, columns in (
        ("speed_response", [1]),
        ("transmission_state", [1, 2, 3, 4]),
        ("engine_torque_demand", [0]),
    ):
        a = left[name][:n, columns]
        b = right[name][:n, columns]
        scale = np.maximum(np.percentile(np.abs(a), 95, axis=0), 1.0)
        terms.append(float(np.sqrt(np.mean(((a - b) / scale) ** 2))))
    return float(np.mean(terms))


def qualification(evidence: dict, failures: list[str]) -> tuple[bool, list[str]]:
    failures = list(failures)
    for name in ("load_pass", "update_pass", "compile_pass"):
        if not evidence.get(name, False):
            failures.append(f"{name} is false")
    if evidence.get("evaluation_subject") == "reference":
        if not evidence.get("model_closed_without_save", False):
            failures.append("reference was not closed without save")
    static = evidence.get("static_audit", {})
    if not static.get("implementation_gate", False):
        failures.append(
            "connected physical-path or feedback-connectivity gate failed"
        )
    return not failures, failures


def score(evidence_path: Path) -> dict:
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    scenarios, failures = load_scenarios(evidence_path, evidence)
    gate, failures = qualification(evidence, failures)
    if not gate:
        return {
            "task_id": "F90-XMECH-03",
            "policy_id": POLICY_ID,
            "G": 0,
            "valid": False,
            "total": 0.0,
            "failures": failures,
        }

    metrics = {name: scenario_metrics(arrays) for name, arrays in scenarios.items()}
    per_scenario = {name: scenario_scores(value) for name, value in metrics.items()}
    static = evidence["static_audit"]
    topology = static.get("generic_connectivity_audit", {})
    static_mechanism = float(
        np.mean(
            [
                bool(static.get("connected_dual_path_gate", False)),
                bool(static.get("feedback_connectivity_gate", False)),
                topology.get("parallel_or_branching_physical_nodes", 0) >= 2,
                topology.get("measurement_to_control_signal_paths", 0) >= 1,
            ]
        )
    )
    nominal = scenarios["urban_short_nominal"]
    mass_distance = behavior_distance(nominal, scenarios["urban_short_heavy"])
    clutch_distance = behavior_distance(
        nominal, scenarios["urban_short_clutch_derated"]
    )
    parameter_binding = min(
        ramp_up(mass_distance, 1e-4, 0.01),
        ramp_up(clutch_distance, 1e-4, 0.01),
    )
    nominal_metrics = metrics["urban_short_nominal"]
    eudc_metrics = metrics["eudc_nominal"]
    behavior_gate = (
        min(
            nominal_metrics["active_clutch_count"],
            eudc_metrics["active_clutch_count"],
        )
        >= 2
        and max(
            nominal_metrics["shift_pressure_transfer_fraction"],
            eudc_metrics["shift_pressure_transfer_fraction"],
        )
        >= 0.20
        and max(
            nominal_metrics["torque_to_acceleration_abs_correlation"],
            eudc_metrics["torque_to_acceleration_abs_correlation"],
        )
        >= 0.05
        and min(
            nominal_metrics["speed_abs_correlation"],
            eudc_metrics["speed_abs_correlation"],
        )
        >= 0.40
        and min(
            nominal_metrics["speed_max_abs_error_kph"],
            eudc_metrics["speed_max_abs_error_kph"],
        )
        > 1e-4
        and min(
            nominal_metrics["gear_transition_count"],
            eudc_metrics["gear_transition_count"],
        )
        >= 1
        and mass_distance > 1e-4
        and clutch_distance > 1e-4
    )
    if not behavior_gate:
        return {
            "task_id": "F90-XMECH-03",
            "policy_id": POLICY_ID,
            "G": 0,
            "valid": False,
            "total": 0.0,
            "metrics": metrics,
            "cross_scenario_metrics": {
                "vehicle_mass_behavior_distance": mass_distance,
                "clutch_capacity_behavior_distance": clutch_distance,
                "behavior_gate": False,
            },
            "failures": failures
            + [
                "two-path pressure/slip/torque feedback or physical parameter "
                "binding was not demonstrated behaviorally"
            ],
        }
    operational_mechanism = min(value["M"] for value in per_scenario.values())
    # Topology, two-path dynamic operation, and physical parameter binding are
    # non-substitutable parts of the public dual-clutch requirement.  Their
    # equal geometric mean keeps partial credit for a weak pillar without
    # letting two perfect pillars arithmetically hide it.
    mechanism = math.exp(
        (
            math.log(max(static_mechanism, 1e-6))
            + math.log(max(operational_mechanism, 1e-6))
            + math.log(max(parameter_binding, 1e-6))
        )
        / 3.0
    )

    nominal_a = max(per_scenario["urban_short_nominal"]["A"], 1e-6)
    boundary_scores = []
    for name in ("urban_short_heavy", "urban_short_clutch_derated"):
        absolute = per_scenario[name]["A"]
        retention = min(1.0, absolute / nominal_a)
        boundary_scores.append(0.70 * absolute + 0.30 * retention)

    groups = {
        "A": min(value["A"] for value in per_scenario.values()),
        "Q": min(value["Q"] for value in per_scenario.values()),
        "M": clip01(mechanism),
        "R": min(boundary_scores),
        "D": min(value["D"] for value in per_scenario.values()),
    }
    total = 100.0 * math.exp(
        sum(WEIGHTS[name] * math.log(max(groups[name], 1e-6)) for name in WEIGHTS)
    )
    return {
        "task_id": "F90-XMECH-03",
        "policy_id": POLICY_ID,
        "G": 1,
        "valid": True,
        "total": total,
        # Unified scorer contract stores group utilities on [0, 1].  Human-
        # readable per-scenario diagnostics below remain on the 0--100 scale.
        "groups": groups,
        "weights": WEIGHTS,
        "scenario_scores": {
            scenario: {name: 100.0 * value for name, value in values.items()}
            for scenario, values in per_scenario.items()
        },
        "metrics": metrics,
        "cross_scenario_metrics": {
            "vehicle_mass_behavior_distance": mass_distance,
            "clutch_capacity_behavior_distance": clutch_distance,
            "direct_speed_replay_detected": min(
                nominal_metrics["speed_max_abs_error_kph"],
                eudc_metrics["speed_max_abs_error_kph"],
            )
            <= 1e-4,
            "parameter_binding_score": parameter_binding,
            "vehicle_mass_binding_score": ramp_up(mass_distance, 1e-4, 0.01),
            "clutch_capacity_binding_score": ramp_up(
                clutch_distance, 1e-4, 0.01
            ),
            "static_mechanism_score": static_mechanism,
            "operational_mechanism_score": operational_mechanism,
            "worst_shift_local_jerk_p95_mps3": max(
                value["shift_local_jerk_p95_mps3"] for value in metrics.values()
            ),
            "behavior_gate": behavior_gate,
        },
        "failures": failures,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = score(args.evidence)
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
