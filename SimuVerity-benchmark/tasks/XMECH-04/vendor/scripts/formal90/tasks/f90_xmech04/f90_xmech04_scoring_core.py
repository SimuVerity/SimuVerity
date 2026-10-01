#!/usr/bin/env python3
"""F90-XMECH-04 scoring from evidence and adjacent waveforms.

This scorer treats the wrist metric as not applicable because the public prompt did not map the
wrist target to either joint 4--6 or end-effector YPR, neutralizes the
unpublished position-closure convention, and derives recovery from the
observed response before applying the task's thresholds and raw weights.
"""

from __future__ import annotations

import copy
import json
import math
import os
import sys
from pathlib import Path
from typing import Any, Mapping

import h5py
import numpy as np


sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from formal90_scoring_core import (  # noqa: E402
    base_receipt,
    group,
    load_evidence,
    parser,
    tail,
    total,
    utility,
    weights,
    write_receipt,
)


TASK_ID = "F90-XMECH-04"
POLICY_ID = 'simuverity-101-v1:f90-xmech-04:scoring'
SIGNAL_WIDTHS = (
    ("joint_state", 12),
    ("end_effector_pose", 6),
    ("joint_torque", 6),
)
RECOVERY_HOLD_S = 0.20
STATE_RECOVERY_THRESHOLD_RAD = 0.04
POSITION_RECOVERY_THRESHOLD_CM = 1.0


def _same_path(left: Path, right: Path) -> bool:
    return os.path.normcase(str(left.resolve())) == os.path.normcase(
        str(right.resolve())
    )


def locate_waveforms(evidence_path: Path, evidence: Mapping[str, Any]) -> Path:
    """Locate the task-local waveform artifact by its public file presence."""
    if evidence.get("formal_task_id") != TASK_ID:
        raise ValueError("evidence task mismatch")
    waveform_path = evidence_path.with_name("waveforms.mat")
    if not waveform_path.is_file():
        raise ValueError("waveforms.mat is missing beside the evidence file")
    return waveform_path


def _decode_matlab_char(dataset: h5py.Dataset) -> str | None:
    if dataset.attrs.get("MATLAB_class") != b"char":
        return None
    values = np.asarray(dataset).ravel(order="F")
    try:
        return "".join(chr(int(value)) for value in values if int(value))
    except (TypeError, ValueError, OverflowError):
        return None


def _numeric_dataset(
    h5_file: h5py.File, references: np.ndarray, index: int
) -> np.ndarray:
    if index < 0 or index >= len(references):
        raise ValueError("unsupported MATLAB timeseries MCOS layout")
    dataset = h5_file[references[index]]
    if not isinstance(dataset, h5py.Dataset):
        raise ValueError("MATLAB timeseries payload is not a dataset")
    values = np.asarray(dataset)
    if values.dtype.kind not in "fiu":
        raise ValueError("MATLAB timeseries payload is not numeric")
    return np.asarray(values, dtype=float)


def load_waveforms(
    waveform_path: Path, run_count: int
) -> list[dict[str, tuple[np.ndarray, np.ndarray]]]:
    """Read the lossless R2025a timeseries stored in the MAT v7.3 file.

    MATLAB stores each serialized ``timeseries`` in a fixed MCOS record.  The
    signal name, time vector, and data matrix occur at offsets 0, 9, and 18 in
    that record.  We validate the complete expected record sequence and fail
    closed if MATLAB emits a different layout.
    """
    with h5py.File(waveform_path, "r") as h5_file:
        try:
            references = np.asarray(
                h5_file["#subsystem#"]["MCOS"]
            ).ravel(order="C")
        except KeyError as error:
            raise ValueError("waveforms.mat has no MATLAB MCOS payload") from error

        markers: list[tuple[int, str]] = []
        expected_names = {name for name, _ in SIGNAL_WIDTHS}
        for index, reference in enumerate(references):
            item = h5_file[reference]
            if not isinstance(item, h5py.Dataset):
                continue
            name = _decode_matlab_char(item)
            if name in expected_names:
                markers.append((index, name))

        expected_sequence = [
            name for _ in range(run_count) for name, _ in SIGNAL_WIDTHS
        ]
        if [name for _, name in markers] != expected_sequence:
            raise ValueError("waveform signal sequence does not match evidence runs")

        runs: list[dict[str, tuple[np.ndarray, np.ndarray]]] = []
        for run_index in range(run_count):
            signals: dict[str, tuple[np.ndarray, np.ndarray]] = {}
            for signal_index, (expected_name, width) in enumerate(SIGNAL_WIDTHS):
                marker_index, actual_name = markers[
                    run_index * len(SIGNAL_WIDTHS) + signal_index
                ]
                if actual_name != expected_name:
                    raise ValueError("waveform signal order mismatch")
                time = _numeric_dataset(
                    h5_file, references, marker_index + 9
                ).reshape(-1, order="F")
                data = _numeric_dataset(h5_file, references, marker_index + 18)
                if data.shape == (width, len(time)):
                    data = data.T
                elif data.shape != (len(time), width):
                    raise ValueError(
                        f"{expected_name} has unsupported shape {data.shape}"
                    )
                if (
                    len(time) < 2
                    or not np.all(np.isfinite(time))
                    or not np.all(np.diff(time) > 0)
                    or not np.all(np.isfinite(data))
                ):
                    raise ValueError(f"{expected_name} waveform is invalid")
                signals[expected_name] = (time, data)
            runs.append(signals)
    return runs


def _interpolate(
    source_time: np.ndarray, source_data: np.ndarray, target_time: np.ndarray
) -> np.ndarray:
    tolerance = 1e-12
    if (
        source_time[0] > target_time[0] + tolerance
        or source_time[-1] < target_time[-1] - tolerance
    ):
        raise ValueError("waveform does not cover the joint-state time horizon")
    return np.column_stack(
        [
            np.interp(target_time, source_time, source_data[:, column])
            for column in range(source_data.shape[1])
        ]
    )


def _wrap_degrees(values: np.ndarray) -> np.ndarray:
    return (values + 180.0) % 360.0 - 180.0


def _correct_scenario_rows(
    evidence: Mapping[str, Any],
    waveforms: list[dict[str, tuple[np.ndarray, np.ndarray]]],
) -> list[dict[str, Any]]:
    evidence_rows = evidence["facts"].get("scenario_rows", [])
    evidence_runs = evidence.get("runs", [])
    if not (
        isinstance(evidence_rows, list)
        and isinstance(evidence_runs, list)
        and len(evidence_rows) == len(evidence_runs) == len(waveforms)
        and evidence_rows
    ):
        raise ValueError("scenario rows, runs, and waveforms do not align")

    corrected_rows: list[dict[str, Any]] = []
    for original_row, run, _signals in zip(
        evidence_rows, evidence_runs, waveforms
    ):
        if not isinstance(original_row, dict) or not isinstance(run, dict):
            raise ValueError("scenario record is not an object")
        scenario = str(run.get("scenario", ""))
        if scenario != str(original_row.get("scenario", "")):
            raise ValueError("scenario order differs between runs and facts")
        row = copy.deepcopy(original_row)
        row["source_final_wrist_error_deg"] = row.get("final_wrist_error_deg")
        row["final_wrist_error_deg"] = None
        row["wrist_scored"] = False
        row["wrist_metric_basis"] = (
            "not_applicable_ambiguous_agent_prompt_mapping"
        )
        row["wrist_policy"] = (
            "agent-facing prompt does not map wrist_target_deg to joint "
            "q4-q6 or end-effector yaw-pitch-roll"
        )
        row["source_position_closure_cm"] = row.get("position_closure_cm")
        row["position_closure_cm"] = None
        row["position_closure_scored"] = False
        row["position_closure_policy"] = (
            "neutralized_unpublished_joint_coordinate_convention"
        )
        row["measurement_source"] = "adjacent_waveforms.mat"
        corrected_rows.append(row)
    return corrected_rows


def _recovery_time(
    time: np.ndarray,
    joint_difference: np.ndarray,
    position_difference: np.ndarray,
    response_peak_time: float,
) -> float | None:
    good = (joint_difference <= STATE_RECOVERY_THRESHOLD_RAD) & (
        position_difference <= POSITION_RECOVERY_THRESHOLD_CM
    )
    for index in np.flatnonzero(time >= response_peak_time):
        hold_end = int(
            np.searchsorted(time, time[index] + RECOVERY_HOLD_S, side="left")
        )
        if hold_end < len(time) and bool(np.all(good[index : hold_end + 1])):
            return float(time[index] - response_peak_time)
    return None


def _correct_pair_metrics(
    evidence: Mapping[str, Any],
    corrected_rows: list[dict[str, Any]],
    waveforms: list[dict[str, tuple[np.ndarray, np.ndarray]]],
) -> dict[str, Any]:
    evidence_runs = evidence["runs"]
    by_scenario = {
        str(run["scenario"]): (index, run)
        for index, run in enumerate(evidence_runs)
    }
    disturbed_name = "heavy_corner"
    control_name = "heavy_corner_no_disturbance"
    if disturbed_name not in by_scenario or control_name not in by_scenario:
        raise ValueError("disturbance comparison scenarios are missing")
    disturbed_index, disturbed_run = by_scenario[disturbed_name]
    control_index, _ = by_scenario[control_name]
    if not (
        corrected_rows[disturbed_index].get("valid") is True
        and corrected_rows[control_index].get("valid") is True
    ):
        raise ValueError("disturbance comparison scenarios are invalid")

    disturbed = waveforms[disturbed_index]
    control = waveforms[control_index]
    time, disturbed_state = disturbed["joint_state"]
    control_time, control_state = control["joint_state"]
    control_state = _interpolate(control_time, control_state, time)
    pose_time, disturbed_pose = disturbed["end_effector_pose"]
    control_pose_time, control_pose = control["end_effector_pose"]
    disturbed_pose = _interpolate(pose_time, disturbed_pose, time)
    control_pose = _interpolate(control_pose_time, control_pose, time)
    torque_time, disturbed_torque = disturbed["joint_torque"]
    control_torque_time, control_torque = control["joint_torque"]
    disturbed_torque = _interpolate(torque_time, disturbed_torque, time)
    control_torque = _interpolate(control_torque_time, control_torque, time)

    inputs = disturbed_run.get("inputs", {})
    disturbance_start = float(inputs.get("disturbance_start", math.nan))
    torque_limit_scale = float(inputs.get("torque_limit_scale", math.nan))
    if not all(
        math.isfinite(value)
        for value in (disturbance_start, torque_limit_scale)
    ) or torque_limit_scale <= 0:
        raise ValueError("invalid disturbance comparison inputs")
    eligible = time >= disturbance_start
    if int(np.count_nonzero(eligible)) < 20:
        raise ValueError("insufficient waveform after disturbance start")

    joint_difference = np.linalg.norm(
        disturbed_state[:, :6] - control_state[:, :6], axis=1
    )
    position_difference = np.linalg.norm(
        disturbed_pose[:, :3] - control_pose[:, :3], axis=1
    )
    torque_limits = (
        np.asarray([80, 70, 60, 22, 18, 14], dtype=float)
        * torque_limit_scale
    )
    torque_evidence = float(
        np.max(
            np.abs(disturbed_torque[eligible] - control_torque[eligible])
            / torque_limits
        )
    )
    state_evidence = float(
        np.max(joint_difference[eligible]) / math.sqrt(6.0)
    )
    eligible_indices = np.flatnonzero(eligible)
    joint_peak_index = eligible_indices[
        int(np.argmax(joint_difference[eligible]))
    ]
    position_peak_index = eligible_indices[
        int(np.argmax(position_difference[eligible]))
    ]
    joint_peak_time = float(time[joint_peak_index])
    position_peak_time = float(time[position_peak_index])
    response_peak_time = max(joint_peak_time, position_peak_time)
    recovery_time = _recovery_time(
        time, joint_difference, position_difference, response_peak_time
    )
    if recovery_time is None:
        raise ValueError("disturbance comparison never reaches sustained recovery")
    # Define the post-response region from the same observed recovery event,
    # not from an assumed disturbance duration or candidate implementation.
    post_window_start = (
        response_peak_time + recovery_time + RECOVERY_HOLD_S
    )
    post = time >= post_window_start
    if int(np.count_nonzero(post)) < 20:
        raise ValueError("insufficient post-response waveform")

    original_pair = evidence["facts"].get("pair_metrics", {})
    pair = copy.deepcopy(original_pair) if isinstance(original_pair, dict) else {}
    pair["source_recovery_time_s"] = pair.get("recovery_time_s")
    pair.update(
        {
            "event_evidence": max(torque_evidence, state_evidence),
            "peak_position_divergence_cm": float(
                np.max(position_difference[eligible])
            ),
            "post_position_divergence_cm": float(
                np.median(position_difference[post])
            ),
            "recovery_time_s": recovery_time,
            "core_event_present": bool(
                math.isfinite(max(torque_evidence, state_evidence))
                and max(torque_evidence, state_evidence) > 1e-8
            ),
            "recovery_anchor_policy": (
                "latest_observed_state_or_position_response_peak"
            ),
            "response_peak_time_s": response_peak_time,
            "joint_response_peak_time_s": joint_peak_time,
            "position_response_peak_time_s": position_peak_time,
            "disturbance_start_s": disturbance_start,
            "recovery_hold_s": RECOVERY_HOLD_S,
            "state_recovery_threshold_rad": STATE_RECOVERY_THRESHOLD_RAD,
            "position_recovery_threshold_cm": (
                POSITION_RECOVERY_THRESHOLD_CM
            ),
            "post_window_start_s": post_window_start,
            "post_window_policy": "after_first_continuous_recovery_hold",
            "measurement_source": "adjacent_waveforms.mat",
        }
    )
    numeric_values = (
        pair["event_evidence"],
        pair["peak_position_divergence_cm"],
        pair["post_position_divergence_cm"],
    )
    pair["valid"] = bool(
        pair["core_event_present"]
        and recovery_time is not None
        and all(math.isfinite(float(value)) for value in numeric_values)
    )
    return pair


def correct_measurements(
    evidence: Mapping[str, Any], waveform_path: Path
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    evidence_runs = evidence.get("runs", [])
    if not isinstance(evidence_runs, list):
        raise ValueError("evidence runs are missing")
    waveforms = load_waveforms(waveform_path, len(evidence_runs))
    rows = _correct_scenario_rows(evidence, waveforms)
    pair = _correct_pair_metrics(evidence, rows, waveforms)
    return rows, pair


def score(
    evidence: Mapping[str, Any],
    scenario_rows: list[dict[str, Any]] | None = None,
    pair_metrics: dict[str, Any] | None = None,
) -> tuple[dict[str, float], float, dict[str, Any]]:
    facts = evidence["facts"]
    rows = (
        facts.get("scenario_rows", [])
        if scenario_rows is None
        else scenario_rows
    )
    pair = facts.get("pair_metrics", {}) if pair_metrics is None else pair_metrics
    gate = bool(facts.get("score_inputs_valid", False))
    if not rows:
        return {"A": 0, "Q": 0, "M": 0, "R": 0, "D": 0}, 0, {}
    nominal = rows[0]
    accuracy = group(
        [
            utility(
                nominal["final_position_error_cm"],
                [0, 0.50, 1.50, 3, 7, 20],
                [1, 1, 0.96, 0.85, 0.50, 0],
            ),
            utility(
                nominal["final_speed_rms"],
                [0, 0.01, 0.03, 0.08, 0.25, 0.8],
                [1, 1, 0.96, 0.80, 0.35, 0],
            ),
        ],
        # final_wrist_error_deg is N/A.  Retain the other raw weights and let
        # group() renormalize them by their 0.73 sum.
        [0.58, 0.15],
    )
    quality = group(
        [
            utility(
                nominal["torque_excess_ratio"],
                [0, 0.001, 0.006, 0.02, 0.08, 0.30],
                [1, 1, 0.94, 0.72, 0.25, 0],
            ),
            utility(
                nominal["tail_joint_ripple_rad"],
                [0, 0.001, 0.004, 0.015, 0.06, 0.25],
                [1, 1, 0.95, 0.75, 0.28, 0],
            ),
            utility(
                nominal["tail_torque_ripple_ratio"],
                [0, 0.001, 0.006, 0.025, 0.10, 0.35],
                [1, 1, 0.94, 0.72, 0.25, 0],
            ),
        ],
        [0.42, 0.35, 0.23],
    )
    motion_utility = utility(
        max(row["motion_activity_rad"] for row in rows),
        [0, 0.01, 0.04, 0.12, 0.30, 0.65],
        [0, 0.35, 0.70, 0.93, 1, 1],
    )
    actuation_utility = utility(
        max(row["actuator_activity_ratio"] for row in rows),
        [0, 0.002, 0.008, 0.025, 0.07, 0.18],
        [0, 0.35, 0.72, 0.94, 1, 1],
    )
    mechanism = group(
        [
            utility(
                max(row["derivative_residual"] for row in rows),
                [0, 0.015, 0.04, 0.10, 0.28, 0.70],
                [1, 1, 0.95, 0.75, 0.28, 0],
            ),
            motion_utility,
            actuation_utility,
        ],
        # position_closure_cm is N/A.  Retain the other raw weights and let
        # group() renormalize them by their 0.68 sum.
        [0.28, 0.20, 0.20],
    )
    if not (
        math.isfinite(motion_utility)
        and math.isfinite(actuation_utility)
        and max(row["motion_activity_rad"] for row in rows) > 1e-5
        and max(row["actuator_activity_ratio"] for row in rows) > 1e-7
    ):
        mechanism = 0

    range_utilities = []
    for row in rows:
        if row.get("is_no_disturbance_control", False):
            continue
        range_utilities.append(
            group(
                [
                    utility(
                        row["final_position_error_cm"],
                        [0, 0.75, 2, 4.5, 10, 28],
                        [1, 1, 0.95, 0.76, 0.35, 0],
                    ),
                    utility(
                        row["final_speed_rms"],
                        [0, 0.015, 0.04, 0.12, 0.35, 1],
                        [1, 1, 0.95, 0.76, 0.30, 0],
                    ),
                    utility(
                        row["torque_excess_ratio"],
                        [0, 0.001, 0.006, 0.02, 0.08, 0.30],
                        [1, 1, 0.94, 0.72, 0.25, 0],
                    ),
                ],
                # final_wrist_error_deg is N/A.  Renormalize the declared raw
                # weights by their 0.75 sum.
                [0.55, 0.12, 0.08],
            )
        )
    robustness = tail(range_utilities)
    if pair.get("valid", False):
        dynamics = group(
            [
                utility(
                    pair["event_evidence"],
                    [0, 1e-5, 1e-4, 1e-3, 5e-3, 0.02],
                    [0, 0.35, 0.75, 0.96, 1, 1],
                ),
                utility(
                    pair["peak_position_divergence_cm"],
                    [0, 0.25, 0.8, 2.5, 7, 20],
                    [1, 1, 0.95, 0.75, 0.30, 0],
                ),
                utility(
                    pair["recovery_time_s"],
                    [0, 0.15, 0.35, 0.70, 1.40, 3],
                    [1, 1, 0.95, 0.75, 0.30, 0],
                ),
                utility(
                    pair["post_position_divergence_cm"],
                    [0, 0.10, 0.40, 1.5, 5, 15],
                    [1, 1, 0.95, 0.72, 0.25, 0],
                ),
            ],
            [0.15, 0.35, 0.30, 0.20],
        )
    else:
        dynamics = 0
    if not pair.get("core_event_present", False):
        dynamics = 0
    groups = {
        "A": accuracy,
        "Q": quality,
        "M": mechanism,
        "R": robustness,
        "D": dynamics,
    }
    return (
        groups,
        total(
            gate,
            [accuracy, quality, mechanism, robustness, dynamics],
            weights(evidence),
        ),
        {"range": range_utilities, "pair": pair},
    )


def main() -> None:
    args = parser(TASK_ID).parse_args()
    evidence = load_evidence(args.evidence, TASK_ID)
    waveform_path = locate_waveforms(args.evidence, evidence)
    scenario_rows, pair_metrics = correct_measurements(
        evidence, waveform_path
    )
    groups, value, utilities = score(
        evidence, scenario_rows, pair_metrics
    )
    receipt = base_receipt(
        args.evidence, evidence, groups, value, policy_id=POLICY_ID
    )
    receipt.update(
        {
            "scenario_rows": scenario_rows,
            "pair_metrics": pair_metrics,
            "utility_metrics": utilities,
            "measurement_policy": {
                "policy_id": POLICY_ID,
                "wrist_metric_basis": (
                    "not_applicable_ambiguous_agent_prompt_mapping"
                ),
                "wrist_scored": False,
                "wrist_reason": (
                    "agent-facing prompt does not map wrist_target_deg to "
                    "joint q4-q6 or end-effector yaw-pitch-roll"
                ),
                "wrist_aggregation": (
                    "excluded_as_not_applicable_and_remaining_raw_weights_renormalized"
                ),
                "position_closure_scored": False,
                "position_closure_reason": (
                    "public prompt does not define a DH/joint-sign convention"
                ),
                "position_closure_aggregation": (
                    "excluded_as_not_applicable_and_remaining_raw_weights_renormalized"
                ),
                "recovery_anchor": (
                    "latest_observed_state_or_position_response_peak"
                ),
            },
            "waveforms_path": str(waveform_path.resolve()),
        }
    )
    write_receipt(args.output, receipt)


if __name__ == "__main__":
    main()
