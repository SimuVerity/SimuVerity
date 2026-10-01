#!/usr/bin/env python3
"""Unbound diagnostic-only scorer for the incomplete XMECH-10 prompt contract."""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path
from typing import Any


TASK_ID = "F90-XMECH-10"
POLICY_ID = 'simuverity-101-v1:f90-xmech-10:scoring'
REQUIRED = (
    "nominal_transfer",
    "low_supply_boundary",
    "heavy_payload_boundary",
    "high_friction_boundary",
    "slow_sequence_boundary",
)
PUBLIC_WIDTHS = {
    "joint_command": 7,
    "joint_position": 7,
    "motor_current": 7,
    "joint_effort": 7,
    "payload_pose": 3,
    "sensor_state": 4,
}
WEIGHTS = {"A": 0.20, "Q": 0.15, "M": 0.30, "R": 0.20, "D": 0.15}


def _load_structure_policy():
    path = Path(__file__).with_name("f90_xmech10_structure_policy.py")
    spec = importlib.util.spec_from_file_location(
        "f90_xmech10_structure_policy_dependency", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load XMECH-10 current structure policy: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


STRUCTURE = _load_structure_policy()


def clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def low(value: float, full: float, zero: float) -> float:
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clip((zero - value) / (zero - full))


def high(value: float, zero: float, full: float) -> float:
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clip((value - zero) / (full - zero))


def weighted(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum(weight for _, weight in parts.values())
    if denominator <= 0:
        return 0.0
    return sum(clip(value) * weight for value, weight in parts.values()) / denominator


def rms(values: list[float]) -> float:
    if not values:
        return 0.0
    return math.sqrt(sum(value * value for value in values) / len(values))


def column(matrix: list[list[float]], index: int) -> list[float]:
    return [float(row[index]) for row in matrix]


def _per_channel_distance(
    changed: list[list[float]], nominal: list[list[float]], indexes: range
) -> float:
    if len(changed) != len(nominal) or not changed:
        return math.inf
    values: list[float] = []
    for index in indexes:
        differences = [
            float(left[index]) - float(right[index])
            for left, right in zip(changed, nominal)
        ]
        scale_values = [
            max(abs(float(left[index])), abs(float(right[index])))
            for left, right in zip(changed, nominal)
        ]
        values.append(rms(differences) / max(rms(scale_values), 1e-9))
    return rms(values)


def grouped_trace_distance(
    changed: list[list[float]], nominal: list[list[float]], primary_width: int
) -> dict[str, float]:
    """Return separate dimensionless distances for heterogeneous unit groups."""

    if not changed or not nominal:
        return {"primary": math.inf, "secondary": math.inf}
    width = len(changed[0])
    if primary_width <= 0 or primary_width >= width:
        raise ValueError("primary_width must split the signal into two groups")
    return {
        "primary": _per_channel_distance(
            changed, nominal, range(0, primary_width)
        ),
        "secondary": _per_channel_distance(
            changed, nominal, range(primary_width, width)
        ),
    }


def _gradient(values: list[list[float]], time: list[float]) -> list[list[float]]:
    result = [[0.0] * len(values[0]) for _ in values]
    for row_index in range(len(values)):
        if row_index == 0:
            left, right = 0, 1
        elif row_index == len(values) - 1:
            left, right = row_index - 1, row_index
        else:
            left, right = row_index - 1, row_index + 1
        delta = time[right] - time[left]
        for channel in range(len(values[0])):
            result[row_index][channel] = (
                values[right][channel] - values[left][channel]
            ) / delta
    return result


def _first_onset(time: list[float], values: list[float], threshold: float) -> float:
    for stamp, value in zip(time, values):
        if value > threshold:
            return stamp
    return math.inf


def _payload_pose(outputs: dict[str, Any]) -> list[list[float]]:
    if "payload_pose" in outputs:
        return [[float(value) for value in row] for row in outputs["payload_pose"]]
    # Existing reference evidence stores position followed by native velocity.
    return [
        [float(value) for value in row[:3]]
        for row in outputs.get("payload_state", [])
    ]


def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row["outputs"]
    time = [float(value) for value in outputs["time_s"]]
    command = [[float(value) for value in sample] for sample in outputs["joint_command"]]
    position = [[float(value) for value in sample] for sample in outputs["joint_position"]]
    current = [[float(value) for value in sample] for sample in outputs["motor_current"]]
    effort = [[float(value) for value in sample] for sample in outputs["joint_effort"]]
    pose = _payload_pose(outputs)
    sensor = [[float(value) for value in sample] for sample in outputs["sensor_state"]]
    velocity = _gradient(pose, time)

    command_ranges = [max(column(command, i)) - min(column(command, i)) for i in range(7)]
    position_ranges = [max(column(position, i)) - min(column(position, i)) for i in range(7)]
    arm_error = [
        command[k][i] - position[k][i]
        for k in range(len(time))
        for i in range(5)
    ]
    finger_error = [
        command[k][i] - position[k][i]
        for k in range(len(time))
        for i in range(5, 7)
    ]
    current_values = [value for sample in current for value in sample]
    arm_torque = [sample[i] for sample in effort for i in range(5)]
    finger_force = [sample[i] for sample in effort for i in range(5, 7)]
    initial_count = max(1, len(time) // 50)
    initial = [
        sum(sample[i] for sample in pose[:initial_count]) / initial_count
        for i in range(3)
    ]
    displacement = [
        math.sqrt(sum((sample[i] - initial[i]) ** 2 for i in range(3)))
        for sample in pose
    ]
    payload_speed = [math.sqrt(sum(value * value for value in sample)) for sample in velocity]
    output_sensor = column(sensor, 2)
    output_onset = _first_onset(time, output_sensor, 0.5)
    output_index = (
        next((index for index, stamp in enumerate(time) if stamp >= output_onset), len(time) - 1)
        if math.isfinite(output_onset)
        else len(time) - 1
    )
    post_output_pose = pose[output_index:]
    post_output_motion = 0.0
    if len(post_output_pose) >= 2:
        post_output_motion = math.sqrt(
            sum(
                (post_output_pose[-1][axis] - post_output_pose[0][axis]) ** 2
                for axis in range(3)
            )
        )
    finger_reopen = min(
        max(column(position, i)[output_index:]) - min(column(position, i))
        for i in range(5, 7)
    )
    release_public = min(
        float(max(output_sensor) > 0.5),
        high(post_output_motion, 0.01, 0.12),
        high(finger_reopen, 1.0, 10.0),
    )
    all_values = [
        value
        for matrix in (command, position, current, effort, pose, sensor)
        for sample in matrix
        for value in sample
    ]
    return {
        "duration_observed_s": time[-1] - time[0],
        "active_arm_command_axes": float(sum(value > 0.05 for value in command_ranges[:5])),
        "active_finger_command_axes": float(sum(value > 1.0 for value in command_ranges[5:])),
        "active_arm_position_axes": float(sum(value > 0.04 for value in position_ranges[:5])),
        "active_finger_position_axes": float(sum(value > 0.8 for value in position_ranges[5:])),
        "arm_tracking_rms_rad": rms(arm_error),
        "finger_tracking_rms_mm": rms(finger_error),
        "motor_current_rms_A": rms(current_values),
        "motor_current_peak_A": max(map(abs, current_values)),
        "nonzero_current_fraction": sum(abs(value) > 1e-4 for value in current_values)
        / len(current_values),
        "arm_torque_rms_Nm": rms(arm_torque),
        "arm_torque_peak_Nm": max(map(abs, arm_torque)),
        "finger_force_rms_N": rms(finger_force),
        "finger_force_peak_N": max(map(abs, finger_force)),
        "payload_displacement_3d_m": max(displacement),
        "payload_peak_speed_mps_from_public_pose": max(payload_speed),
        "output_sensor_seen": float(max(output_sensor) > 0.5),
        "post_output_payload_motion_m": post_output_motion,
        "finger_reopen_after_output_mm": finger_reopen,
        "release_public_evidence": release_public,
        "all_values_finite": float(all(math.isfinite(value) for value in all_values)),
    }


def _valid_public_outputs(row: dict[str, Any]) -> bool:
    outputs = row.get("outputs", {})
    time = outputs.get("time_s")
    if not isinstance(time, list) or len(time) < 2:
        return False
    for name, width in PUBLIC_WIDTHS.items():
        matrix = outputs.get(name)
        if name == "payload_pose" and matrix is None:
            source = outputs.get("payload_state")
            matrix = [sample[:3] for sample in source] if isinstance(source, list) else None
        if not (
            isinstance(matrix, list)
            and len(matrix) == len(time)
            and all(isinstance(sample, list) and len(sample) == width for sample in matrix)
        ):
            return False
    return bool(row.get("valid"))


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get("id")): row for row in evidence.get("scenarios", [])}
    structure = STRUCTURE.evaluate_structure_graph(
        evidence.get("static_audit", {}).get("port_graph", {})
    )
    qualification = {
        "load": bool(evidence.get("load_pass")),
        "update": bool(evidence.get("update_pass")),
        "compile": bool(evidence.get("compile_pass")),
        "nominal_smoke": bool(evidence.get("nominal_smoke_pass")),
        "exact_scenario_set": set(rows) == set(REQUIRED),
        "public_outputs_valid": set(rows) == set(REQUIRED)
        and all(_valid_public_outputs(rows[name]) for name in REQUIRED),
        "connected_physical_core": bool(structure["qualified"]),
    }
    gate = all(qualification.values())
    metrics = {
        name: row_metrics(rows[name])
        for name in REQUIRED
        if name in rows and _valid_public_outputs(rows[name])
    }
    nominal = metrics.get("nominal_transfer", {})

    groups: dict[str, float | None] = {"A": 0.0, "Q": 0.0, "M": 0.0, "R": None, "D": None}
    diagnostics: dict[str, Any] = {}
    if gate:
        a_parts = {
            "input_payload_detected": (
                float(max(column(rows["nominal_transfer"]["outputs"]["sensor_state"], 0)) > 0.5),
                0.10,
            ),
            "arm_and_finger_motion": (
                min(
                    high(nominal["active_arm_position_axes"], 3.0, 4.0),
                    high(nominal["active_finger_position_axes"], 1.0, 2.0),
                ),
                0.15,
            ),
            "coordinate_invariant_payload_transfer": (
                high(nominal["payload_displacement_3d_m"], 0.18, 0.50),
                0.25,
            ),
            "output_payload_detected": (nominal["output_sensor_seen"], 0.15),
            "public_release_behavior": (nominal["release_public_evidence"], 0.15),
        }
        q_parts = {
            "arm_joint_tracking": (low(nominal["arm_tracking_rms_rad"], 0.04, 0.30), 0.30),
            "finger_tracking": (low(nominal["finger_tracking_rms_mm"], 1.0, 8.0), 0.15),
            "finite_bounded_motor_current": (
                min(
                    high(nominal["motor_current_rms_A"], 0.02, 0.20),
                    low(nominal["motor_current_peak_A"], 40.0, 150.0),
                ),
                0.20,
            ),
            "bounded_arm_torque": (
                min(
                    high(nominal["arm_torque_rms_Nm"], 0.02, 0.30),
                    low(nominal["arm_torque_peak_Nm"], 120.0, 400.0),
                ),
                0.075,
            ),
            "bounded_finger_force": (
                min(
                    high(nominal["finger_force_rms_N"], 0.02, 0.30),
                    low(nominal["finger_force_peak_N"], 120.0, 400.0),
                ),
                0.075,
            ),
            "public_pose_continuity": (
                low(nominal["payload_peak_speed_mps_from_public_pose"], 2.0, 10.0),
                0.20,
            ),
        }
        m_parts = {
            "connected_port_graph_core": (1.0, 0.25),
            "command_to_measured_response": (
                min(
                    high(nominal["active_arm_command_axes"], 3.0, 4.0),
                    high(nominal["active_arm_position_axes"], 3.0, 4.0),
                    low(nominal["arm_tracking_rms_rad"], 0.06, 0.40),
                ),
                0.15,
            ),
            "electrical_and_mechanical_effort": (
                min(
                    high(nominal["nonzero_current_fraction"], 0.02, 0.20),
                    high(nominal["arm_torque_rms_Nm"], 0.02, 0.30),
                    high(nominal["finger_force_rms_N"], 0.02, 0.30),
                ),
                0.15,
            ),
        }
        groups.update({"A": weighted(a_parts), "Q": weighted(q_parts), "M": weighted(m_parts)})
        diagnostics = {"A": a_parts, "Q": q_parts, "M": m_parts}

    visible_group_weights = {name: WEIGHTS[name] for name in ("A", "Q", "M")}
    if gate and all(float(groups[name] or 0.0) > 0 for name in visible_group_weights):
        denominator = sum(visible_group_weights.values())
        diagnostic_total = 100.0 * math.exp(
            sum(
                (weight / denominator) * math.log(float(groups[name]))
                for name, weight in visible_group_weights.items()
            )
        )
    else:
        diagnostic_total = 0.0

    return {
        "schema": "simuverity.f90-xmech10-score.v1",
        "task_id": TASK_ID,
        "policy_id": POLICY_ID,
        "diagnostic_status": "INCOMPLETE_PUBLIC_OUTPUT_CONTRACT",
        "score": None,
        "score_eligible": False,
        "freezable": False,
        "diagnostic_total_visible_only": float(diagnostic_total),
        "diagnostic_total_freezable": False,
        "G": 1.0 if gate else 0.0,
        "groups": {"G": 1.0 if gate else 0.0, **groups},
        "group_weights": WEIGHTS,
        "diagnostic_applicable_group_weights": visible_group_weights,
        "qualification_checks": qualification,
        "structure_checks": structure,
        "scenario_metrics": metrics,
        "diagnostics": diagnostics,
        "metric_applicability": {
            "range_robustness": "N/A_NOT_IN_ACTUAL_PROMPT",
            "range_causality": "N/A_NOT_IN_ACTUAL_PROMPT",
            "completion_by_20_s": "N/A_NOT_IN_ACTUAL_PROMPT",
            "z_axis_lift": "N/A_COORDINATE_FRAME_NOT_IN_ACTUAL_PROMPT",
            "xy_horizontal_transfer": "N/A_COORDINATE_FRAME_NOT_IN_ACTUAL_PROMPT",
            "belt_command": "REMOVED_NOT_PUBLIC_OUTPUT",
            "release_public_evidence": "APPLICABLE_DIAGNOSTIC_ONLY",
            "coordinate_invariant_payload_transfer": "APPLICABLE_DIAGNOSTIC_ONLY",
        },
        "failure_reasons": [name for name, passed in qualification.items() if not passed],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score(evidence)
    rendered = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)


if __name__ == "__main__":
    main()
