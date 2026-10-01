#!/usr/bin/env python3
"""Normalized pure-offline scorer for F90-XAUTO-07 HDF5 evidence."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import h5py
import numpy as np


TASK_ID = "F90-XAUTO-07"
SCENARIOS = [
    "nominal_start_stop",
    "reduced_acceleration",
    "reduced_braking",
    "moderate_cycle",
    "strong_motoring_light_brake",
]
LOG_WIDTHS = {"driver_input": 2, "motor_torque": 4, "phase_currents": 3, "vehicle_speed": 1}
STRUCTURE = [
    "battery_and_dc_link", "controlled_three_phase_converter",
    "interior_permanent_magnet_motor", "closed_loop_phase_current_control",
    "torque_reference_and_estimation", "fixed_ratio_gear_and_axle",
    "finite_mass_vehicle_dynamics", "closed_driver_drive_vehicle_feedback",
]
ANTI_CHEAT_STRUCTURE = ["finite_mass_vehicle_dynamics", "closed_driver_drive_vehicle_feedback"]
WEIGHTS = {"A": 0.25, "Q": 0.10, "M": 0.25, "C": 0.20, "R": 0.10, "D": 0.10}
def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def low(value: float, full: float, zero: float) -> float:
    return 100.0 if value <= full else 0.0 if value >= zero else 100.0 * (zero - value) / (zero - full)


def high(value: float, zero: float, full: float) -> float:
    return 100.0 if value >= full else 0.0 if value <= zero else 100.0 * (value - zero) / (full - zero)


def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row.get("id", "")): row for row in evidence.get("scenarios", []) if isinstance(row, dict)}


def _array(handle: h5py.File, name: str) -> np.ndarray:
    value = np.asarray(handle[f"data/{name}"], dtype=float)
    return value.T if value.ndim == 2 else value


def load_series(evidence: dict[str, Any], evidence_path: Path) -> tuple[dict[str, dict[str, np.ndarray]], list[str]]:
    loaded: dict[str, dict[str, np.ndarray]] = {}
    failures: list[str] = []
    for sid, row in scenario_map(evidence).items():
        data_path = evidence_path.parent / str(row.get("data_file", ""))
        if not data_path.is_file():
            failures.append(f"{sid}:missing_data_file")
            continue
        try:
            with h5py.File(data_path, "r") as handle:
                loaded[sid] = {
                    name: _array(handle, name)
                    for name in (
                        "driver_time_s", "driver_input", "torque_time_s", "torque_Nm",
                        "phase_current_time_s", "phase_currents_A", "vehicle_time_s",
                        "vehicle_speed_kph",
                    )
                }
        except (OSError, KeyError, ValueError) as error:
            failures.append(f"{sid}:unreadable_data:{type(error).__name__}")
    return loaded, failures


def _subject(evidence: dict[str, Any], requested: str) -> str:
    if requested in {"candidate", "reference"}:
        return requested
    return "reference" if "fixed-evidence" in str(evidence.get("schema", "")) else "candidate"


def structure_ready(evidence: dict[str, Any], subject: str) -> bool:
    if subject != "candidate":
        return True
    structure = evidence.get("structure", {})
    return (
        evidence.get("structure_policy_id") == "f90_xauto07_structure_policy"
        and structure.get("schema") == "simuverity.f90-xauto07-structure-audit.v1"
        and structure.get("audit_complete") is True
    )


def gate(
    evidence: dict[str, Any], subject: str,
    loaded: dict[str, dict[str, np.ndarray]], load_failures: list[str],
) -> tuple[bool, list[str]]:
    failures = list(load_failures)
    if evidence.get("task_id") != TASK_ID:
        failures.append("wrong_task_id")
    for key in ("load_pass", "update_pass", "compile_pass", "simulate_pass", "all_official_evidence_valid"):
        if evidence.get(key) is not True:
            failures.append(key)
    scenarios = scenario_map(evidence)
    if list(scenarios) != SCENARIOS:
        failures.append("scenario_set_or_order")
    for name in ANTI_CHEAT_STRUCTURE:
        if evidence.get("structure", {}).get(name) is not True:
            failures.append(f"anti_cheat:{name}")
    acceleration_ratios: list[float] = []
    brake_ratios: list[float] = []
    for sid in SCENARIOS:
        row = scenarios.get(sid)
        if not row or row.get("valid") is not True:
            failures.append(f"{sid}:invalid")
            continue
        logs = row.get("logs", {})
        if not set(LOG_WIDTHS).issubset(logs):
            failures.append(f"{sid}:missing_required_output")
            continue
        for name, width in LOG_WIDTHS.items():
            descriptor = logs[name]
            if int(descriptor.get("channels", 0)) != width:
                failures.append(f"{sid}:{name}:width")
        data = loaded.get(sid)
        if not data:
            continue
        expected_shapes = {
            "driver_input": 2, "torque_Nm": 4, "phase_currents_A": 3,
        }
        for name, width in expected_shapes.items():
            if data[name].ndim != 2 or data[name].shape[1] != width:
                failures.append(f"{sid}:{name}:shape")
        if data["vehicle_speed_kph"].reshape(-1).size < 100 or data["torque_time_s"].reshape(-1).size < 100 or data["phase_current_time_s"].reshape(-1).size < 100:
            failures.append(f"{sid}:short_evidence")
        for name, value in data.items():
            if value.size == 0 or not np.isfinite(value).all():
                failures.append(f"{sid}:{name}:nonfinite_or_empty")
        for time_name in ("driver_time_s", "torque_time_s", "phase_current_time_s", "vehicle_time_s"):
            times = data[time_name].reshape(-1)
            if np.any(np.diff(times) <= 0) or times[0] > 0.01 or times[-1] < 4.99:
                failures.append(f"{sid}:{time_name}:incomplete_or_unordered")
        inputs = row.get("inputs", {})
        driver = data["driver_input"]
        acceleration_scale = float(inputs.get("acceleration_scale", math.nan))
        brake_scale = float(inputs.get("brake_scale", math.nan))
        acceleration_peak = float(np.max(driver[:, 0]))
        brake_peak = float(np.max(driver[:, 1]))
        if (
            not math.isfinite(acceleration_scale) or not math.isfinite(brake_scale)
            or np.min(driver) < -1e-9 or np.max(driver) > 1.0 + 1e-9
            or acceleration_scale <= 0.0 or brake_scale <= 0.0
            or acceleration_peak <= 0.0 or brake_peak <= 0.0
        ):
            failures.append(f"{sid}:driver_input_fidelity")
        else:
            acceleration_ratios.append(acceleration_peak / acceleration_scale)
            brake_ratios.append(brake_peak / brake_scale)
    if acceleration_ratios and max(acceleration_ratios) - min(acceleration_ratios) > 0.02:
        failures.append("driver_input_fidelity:acceleration_scale_not_proportional")
    if brake_ratios and max(brake_ratios) - min(brake_ratios) > 0.02:
        failures.append("driver_input_fidelity:brake_scale_not_proportional")
    return not failures, failures


def _interp(grid: np.ndarray, time: np.ndarray, values: np.ndarray) -> np.ndarray:
    return np.interp(grid, time.reshape(-1), values.reshape(-1))


def derive(data: dict[str, np.ndarray]) -> dict[str, float | bool]:
    torque_time = data["torque_time_s"].reshape(-1)
    torque = data["torque_Nm"]
    vehicle_time = data["vehicle_time_s"].reshape(-1)
    vehicle_speed = data["vehicle_speed_kph"].reshape(-1)
    phase = data["phase_currents_A"]
    driver_time = data["driver_time_s"].reshape(-1)
    driver = data["driver_input"]
    grid = np.arange(0.0, 5.0001, 0.001)
    reference = _interp(grid, torque_time, torque[:, 0])
    measured = _interp(grid, torque_time, torque[:, 1])
    estimated = _interp(grid, torque_time, torque[:, 2])
    speed_mps = _interp(grid, vehicle_time, vehicle_speed / 3.6)
    acceleration = np.gradient(speed_mps, 0.001)
    jerk = np.gradient(acceleration, 0.001)
    moving_count = 21
    moving = np.convolve(measured, np.ones(moving_count) / moving_count, mode="same")
    interior = slice(moving_count, -moving_count)
    active = np.abs(measured) > max(5.0, 0.10 * float(np.max(np.abs(measured))))
    phase_rms = np.sqrt(np.mean(np.square(phase), axis=0))

    coupling_grid = np.arange(0.05, 4.951, 0.005)
    coupling_torque = _interp(coupling_grid, torque_time, torque[:, 1])
    coupling_speed = _interp(coupling_grid, vehicle_time, vehicle_speed / 3.6)
    coupling_acceleration = np.gradient(coupling_speed, 0.005)
    correlation = float(np.corrcoef(coupling_torque, coupling_acceleration)[0, 1])
    regression = float(np.dot(coupling_torque, coupling_acceleration) / max(np.dot(coupling_torque, coupling_torque), 1e-12))
    ideal_gain = 9.0 / (1100.0 * 0.3)

    accelerator = _interp(grid, driver_time, driver[:, 0])
    brake = _interp(grid, driver_time, driver[:, 1])
    accelerator_indices = np.flatnonzero(accelerator > 0.05)
    brake_indices = np.flatnonzero(brake > 0.05)
    accelerator_start = float(grid[accelerator_indices[0]]) if accelerator_indices.size else math.inf
    brake_start = float(grid[brake_indices[0]]) if brake_indices.size else math.inf
    positive_indices = np.flatnonzero((grid >= accelerator_start) & (measured > 5.0))
    negative_indices = np.flatnonzero((grid >= brake_start) & (measured < -5.0))
    positive = measured[measured > 5.0]
    negative = measured[measured < -5.0]
    return {
        "torque_tracking_nrmse": float(np.sqrt(np.mean(np.square(measured - reference))) / max(np.sqrt(np.mean(np.square(reference))), 5.0)),
        "torque_estimation_nrmse": float(np.sqrt(np.mean(np.square(estimated - measured))) / max(np.sqrt(np.mean(np.square(measured))), 5.0)),
        "torque_ripple_ratio_20ms": float(np.sqrt(np.mean(np.square(measured[interior] - moving[interior]))) / max(np.sqrt(np.mean(np.square(measured[interior]))), 5.0)),
        "torque_active_peak_to_mean": float(np.max(np.abs(measured[active])) / max(np.mean(np.abs(measured[active])), 1e-12)),
        "phase_current_crest_factor": float(np.max(np.abs(phase)) / max(np.sqrt(np.mean(np.square(phase))), 1.0)),
        "phase_rms_imbalance_fraction": float(np.std(phase_rms) / max(np.mean(phase_rms), 1.0)),
        "vehicle_jerk_rms_mps3": float(np.sqrt(np.mean(np.square(jerk[20:-20])))),
        "torque_acceleration_correlation": correlation,
        "torque_to_acceleration_gain_fraction_of_ideal": regression / ideal_gain,
        "torque_per_phase_current_rms_Nm_per_A": float(np.sqrt(np.mean(np.square(measured))) / max(np.sqrt(np.mean(np.square(phase))), 1.0)),
        "motoring_present": bool(np.any(measured > 5.0)),
        "generating_present": bool(np.any(measured < -5.0)),
        "motoring_mean_Nm": float(np.mean(positive)) if positive.size else 0.0,
        "generating_mean_Nm": float(np.mean(negative)) if negative.size else 0.0,
        "vehicle_speed_max_kph": float(np.max(vehicle_speed)),
        "vehicle_speed_final_kph": float(vehicle_speed[-1]),
        "startup_torque_delay_s": float(grid[positive_indices[0]] - accelerator_start) if positive_indices.size else math.inf,
        "brake_generating_delay_s": float(grid[negative_indices[0]] - brake_start) if negative_indices.size else math.inf,
        "accelerator_peak": float(np.max(driver[:, 0])),
        "brake_peak": float(np.max(driver[:, 1])),
    }


def performance(evidence: dict[str, Any], loaded: dict[str, dict[str, np.ndarray]]) -> tuple[dict[str, float], dict[str, Any], dict[str, Any]]:
    derived = {sid: derive(loaded[sid]) for sid in SCENARIOS}
    accuracy: dict[str, float] = {}
    quality: dict[str, float] = {}
    physical: dict[str, float] = {}
    modes: dict[str, float] = {}
    for sid, row in derived.items():
        accuracy[sid] = mean([
            low(float(row["torque_tracking_nrmse"]), 0.05, 0.30),
            low(float(row["torque_estimation_nrmse"]), 0.05, 0.25),
        ])
        quality[sid] = mean([
            low(float(row["torque_ripple_ratio_20ms"]), 0.05, 0.25),
            low(float(row["torque_active_peak_to_mean"]), 1.60, 5.00),
            low(float(row["phase_current_crest_factor"]), 2.50, 7.00),
            low(float(row["phase_rms_imbalance_fraction"]), 0.03, 0.15),
            low(float(row["vehicle_jerk_rms_mps3"]), 25.0, 150.0),
        ])
        physical[sid] = mean([
            high(float(row["torque_acceleration_correlation"]), 0.60, 0.90),
            high(float(row["torque_to_acceleration_gain_fraction_of_ideal"]), 0.20, 0.65),
            high(float(row["torque_per_phase_current_rms_Nm_per_A"]), 0.20, 0.60),
        ])
        modes[sid] = 100.0 if row["motoring_present"] and row["generating_present"] else 0.0

    groups = {"A": mean(list(accuracy.values())), "Q": mean(list(quality.values()))}
    structure = {
        name: 100.0 if evidence.get("structure", {}).get(name) is True else 0.0
        for name in STRUCTURE
    }
    groups["M"] = mean([mean(list(structure.values())), mean(list(modes.values())), mean(list(physical.values()))])

    nominal = derived[SCENARIOS[0]]
    reduced_acceleration = derived[SCENARIOS[1]]
    reduced_braking = derived[SCENARIOS[2]]
    acceleration_effect = mean([
        high(abs(1.0 - float(reduced_acceleration["motoring_mean_Nm"]) / max(float(nominal["motoring_mean_Nm"]), 1e-9)), 0.10, 0.35),
        high(abs(1.0 - float(reduced_acceleration["vehicle_speed_max_kph"]) / max(float(nominal["vehicle_speed_max_kph"]), 1e-9)), 0.10, 0.35),
    ])
    braking_effect = mean([
        high(abs(1.0 - float(reduced_braking["generating_mean_Nm"]) / min(float(nominal["generating_mean_Nm"]), -1e-9)), 0.10, 0.35),
        high((float(reduced_braking["vehicle_speed_final_kph"]) - float(nominal["vehicle_speed_final_kph"])) / max(float(nominal["vehicle_speed_max_kph"]), 1.0), 0.05, 0.25),
    ])
    scenarios = scenario_map(evidence)
    profile_fidelity = mean([
        low(abs(float(derived[sid]["accelerator_peak"]) / float(scenarios[sid]["inputs"]["acceleration_scale"]) - 1.0), 0.02, 0.25)
        for sid in SCENARIOS
    ] + [
        low(abs(float(derived[sid]["brake_peak"]) / float(scenarios[sid]["inputs"]["brake_scale"]) - 1.0), 0.02, 0.25)
        for sid in SCENARIOS
    ])
    groups["C"] = mean([acceleration_effect, braking_effect, profile_fidelity])

    scenario_quality = {
        sid: mean([accuracy[sid], quality[sid], physical[sid], modes[sid]])
        for sid in SCENARIOS
    }
    groups["R"] = 0.60 * min(scenario_quality.values()) + 0.40 * mean(list(scenario_quality.values()))

    nominal_transition = mean([
        low(float(nominal["startup_torque_delay_s"]), 0.02, 0.25),
        low(float(nominal["brake_generating_delay_s"]), 0.02, 0.25),
        low(abs(float(nominal["vehicle_speed_final_kph"])) / max(float(nominal["vehicle_speed_max_kph"]), 1.0), 0.05, 0.50),
        modes[SCENARIOS[0]],
    ])
    reduced_brake_transition = mean([
        low(float(reduced_braking["brake_generating_delay_s"]), 0.02, 0.25),
        high((float(reduced_braking["vehicle_speed_final_kph"]) - float(nominal["vehicle_speed_final_kph"])) / max(float(nominal["vehicle_speed_max_kph"]), 1.0), 0.05, 0.25),
        100.0 if reduced_braking["generating_present"] else 0.0,
    ])
    groups["D"] = mean([nominal_transition, reduced_brake_transition])
    groups = {name: round(max(0.0, min(100.0, float(value))), 9) for name, value in groups.items()}
    components = {
        "A": accuracy,
        "Q": quality,
        "M": {"structure": structure, "motoring_and_generating": modes, "electromechanical_coupling": physical},
        "C": {"acceleration_scale_response": acceleration_effect, "brake_scale_response": braking_effect, "published_profile_scale_fidelity": profile_fidelity},
        "R": {"aggregation": "0.60*worst+0.40*mean", "scenario_quality": scenario_quality},
        "D": {"nominal_start_brake_transition": nominal_transition, "reduced_brake_transition": reduced_brake_transition},
    }
    return groups, components, derived


def score(
    evidence: dict[str, Any], evidence_path: Path, requested_subject: str = "auto",
    context: dict[str, Any] | None = None,
    loaded_override: dict[str, dict[str, np.ndarray]] | None = None,
) -> dict[str, Any]:
    subject = _subject(evidence, requested_subject)
    if loaded_override is None:
        loaded, load_failures = load_series(evidence, evidence_path)
    else:
        loaded, load_failures = loaded_override, []
    passed, failures = gate(evidence, subject, loaded, load_failures)
    ready = structure_ready(evidence, subject)
    waiting_for_structure = passed and not ready
    if passed and ready:
        groups, components, derived = performance(evidence, loaded)
        total = round(sum(WEIGHTS[name] * groups[name] for name in WEIGHTS), 9)
    elif waiting_for_structure:
        groups = {name: None for name in WEIGHTS}
        components, derived, total = {}, {}, None
    else:
        groups = {name: 0.0 for name in WEIGHTS}
        components, derived, total = {}, {}, 0.0
    g_value = None if waiting_for_structure else (1 if passed else 0)
    readiness_failures = ["structure_policy_required"] if waiting_for_structure else []
    return {
        "schema": "simuverity.f90-xauto07-offline-score.v1",
        "status": "AWAITING_STRUCTURE_EVIDENCE" if waiting_for_structure else (
            "SCORED" if passed else "INELIGIBLE_EVIDENCE"
        ),
        "task_id": TASK_ID,
        "subject": subject,
        "G": g_value,
        "raw_total": total,
        "total": total,
        "groups": groups,
        "metrics": {"group_components": components, "normalization_basis": "relative torque/current/vehicle quantities and fixed public 9:1, 1100 kg, 0.3 m constants"},
        "scenarios": {sid: {"source_metrics": scenario_map(evidence).get(sid, {}).get("metrics", {}), "derived_metrics": derived.get(sid, {})} for sid in SCENARIOS},
        "weights": WEIGHTS,
        "gate": {"G": g_value, "passed": None if waiting_for_structure else passed, "failures": failures},
        "readiness": {"structure_evidence_ready": ready, "failures": readiness_failures},
        "score_eligible": passed and ready,
        "scoring_completed": passed and ready,
        "offline_only": True,
        "matlab_invoked": False,
        "group_scores": groups,
        "raw_score": total,
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
    result = score(evidence, args.evidence, args.subject)
    (args.output_dir / "score.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
