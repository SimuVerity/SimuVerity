#!/usr/bin/env python3
"""XMECH-04 scorer over public evidence.

Hidden wrist and fixed-DH measurements are not applicable.  M is fail-closed on an implementation-
neutral six-channel graph plus per-channel motion/actuation, and D requires
both observed state and Cartesian-pose response to the paired disturbance.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import math
from pathlib import Path
from typing import Any, Mapping

import numpy as np


TASK_ID = "F90-XMECH-04"
POLICY_ID = 'simuverity-101-v1:f90-xmech-04:scoring'
MIN_CHANNEL_MOTION_RAD = 1e-5
MIN_CHANNEL_ACTUATION_RATIO = 1e-7
MIN_STATE_EVENT = 1e-8
MIN_POSE_EVENT_CM = 1e-8


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load dependency: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TASK_DIR = Path(__file__).resolve().parent
SCORING_CORE = _load_module(
    "f90_xmech04_current_primitives_for",
    TASK_DIR / "f90_xmech04_scoring_core.py",
)
STRUCTURE_POLICY = _load_module(
    "f90_xmech04_structure_policy_for",
    TASK_DIR / "f90_xmech04_structure_policy.py",
)


def _six_finite_above(value: Any, threshold: float) -> bool:
    if not isinstance(value, list) or len(value) != 6:
        return False
    try:
        numbers = [float(item) for item in value]
    except (TypeError, ValueError):
        return False
    return all(math.isfinite(number) and number > threshold for number in numbers)


def _activity_decision(activity: Mapping[str, Any]) -> dict[str, Any]:
    motion = activity.get("joint_motion_range_rad", [])
    actuation = activity.get("actuator_activity_ratio", [])
    checks = {
        "six_joint_motion_channels": _six_finite_above(
            motion, MIN_CHANNEL_MOTION_RAD
        ),
        "six_actuator_activity_channels": _six_finite_above(
            actuation, MIN_CHANNEL_ACTUATION_RATIO
        ),
    }
    return {
        "qualified": all(checks.values()),
        "checks": checks,
        "joint_motion_range_rad": motion,
        "actuator_activity_ratio": actuation,
        "motion_threshold_rad": MIN_CHANNEL_MOTION_RAD,
        "actuation_threshold_ratio": MIN_CHANNEL_ACTUATION_RATIO,
    }


def _compatible_mapping(facts: Mapping[str, Any], name: str) -> Mapping[str, Any]:
    current = facts.get(name)
    if isinstance(current, Mapping):
        return current
    compatible = [
        (key, value)
        for key, value in facts.items()
        if key.startswith(name + "_") and isinstance(value, Mapping)
    ]
    if not compatible:
        return {}
    shortest = min(len(key) for key, _ in compatible)
    selected = [value for key, value in compatible if len(key) == shortest]
    return selected[0] if len(selected) == 1 else {}


def _event_gate(pair: Mapping[str, Any]) -> tuple[dict[str, Any], list[str]]:
    corrected = copy.deepcopy(dict(pair))
    state_value = float(corrected.get("state_event_evidence", 0.0) or 0.0)
    pose_value = float(corrected.get("pose_event_evidence_cm", 0.0) or 0.0)
    state_present = bool(corrected.get("state_event_present", False)) and (
        math.isfinite(state_value) and state_value > MIN_STATE_EVENT
    )
    pose_present = bool(corrected.get("pose_event_present", False)) and (
        math.isfinite(pose_value) and pose_value > MIN_POSE_EVENT_CM
    )
    corrected["state_event_present"] = state_present
    corrected["pose_event_present"] = pose_present
    corrected["core_event_present"] = bool(
        corrected.get("core_event_present", False) and state_present and pose_present
    )
    corrected["valid"] = bool(
        corrected.get("valid", False) and state_present and pose_present
    )
    failures: list[str] = []
    if not state_present:
        failures.append("dynamics:state_event_missing")
    if not pose_present:
        failures.append("dynamics:pose_event_missing")
    return corrected, failures


def _named_metrics(
    groups: Mapping[str, float],
    structure: Mapping[str, Any],
    activity: Mapping[str, Any],
    pair: Mapping[str, Any],
    rows: list[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    metrics: list[dict[str, Any]] = []

    def add(metric_id: str, value: Any) -> None:
        if isinstance(value, bool):
            number = 1.0 if value else 0.0
        else:
            try:
                number = float(value)
            except (TypeError, ValueError):
                return
        if math.isfinite(number):
            metrics.append({"metric_id": metric_id, "value": number})

    for name, value in groups.items():
        add(f"group.{name}", value)
    for name in (
        "revolute_joint_count",
        "closed_loop_joint_path_count",
        "independent_sensor_count",
        "independent_actuator_count",
        "joint_state_lineage_count",
        "joint_torque_lineage_count",
    ):
        add(f"structure.{name}", structure.get(name))
    for name, value in structure.get("checks", {}).items():
        add(f"structure.check.{name}", value)
    for index, value in enumerate(activity.get("joint_motion_range_rad", []), 1):
        add(f"activity.joint_{index}.motion_range_rad", value)
    for index, value in enumerate(activity.get("actuator_activity_ratio", []), 1):
        add(f"activity.joint_{index}.actuator_activity_ratio", value)
    for name in (
        "torque_event_evidence",
        "state_event_evidence",
        "pose_event_evidence_cm",
        "peak_position_divergence_cm",
        "post_position_divergence_cm",
        "recovery_time_s",
    ):
        add(f"dynamics.{name}", pair.get(name))
    for row in rows:
        scenario = str(row.get("scenario", "unknown"))
        for name in (
            "final_position_error_cm",
            "final_speed_rms",
            "torque_excess_ratio",
            "tail_joint_ripple_rad",
            "tail_torque_ripple_ratio",
        ):
            add(f"scenario.{scenario}.{name}", row.get(name))
    return metrics


def score_evidence(
    evidence: Mapping[str, Any],
    *,
    scenario_rows: list[dict[str, Any]] | None = None,
    pair_metrics: dict[str, Any] | None = None,
) -> dict[str, Any]:
    facts = evidence.get("facts", {})
    rows = list(
        facts.get("scenario_rows", []) if scenario_rows is None else scenario_rows
    )
    pair_source = (
        _compatible_mapping(facts, "pair_metrics")
        if pair_metrics is None
        else pair_metrics
    )
    pair, event_failures = _event_gate(pair_source)
    structure = STRUCTURE_POLICY.evaluate_structure_graph(
        _compatible_mapping(facts, "structure_graph")
    )
    activity = _activity_decision(
        _compatible_mapping(facts, "channel_activity")
    )

    base_groups, _, utilities = SCORING_CORE.score(
        evidence, scenario_rows=rows, pair_metrics=pair
    )
    groups = dict(base_groups)
    failure_reasons = list(event_failures)
    if not structure["qualified"]:
        groups["M"] = 0.0
        failure_reasons.extend(
            f"mechanism:structure:{reason}"
            for reason in structure["failure_reasons"]
        )
    if not activity["qualified"]:
        groups["M"] = 0.0
        failure_reasons.append("mechanism:six_channel_activity_unproven")
    if event_failures:
        groups["D"] = 0.0

    gate = bool(facts.get("score_inputs_valid", False))
    score = SCORING_CORE.total(
        gate,
        [groups[name] for name in ("A", "Q", "M", "R", "D")],
        SCORING_CORE.weights(evidence),
    )
    metrics = _named_metrics(groups, structure, activity, pair, rows)
    result: dict[str, Any] = {
        "schema": "simuverity.formal90-offline-score.v1",
        "formal_task_id": TASK_ID,
        "policy_id": POLICY_ID,
        "offline_only": True,
        "score_inputs_valid": gate,
        "diagnostics_valid": bool(facts.get("diagnostics_valid", gate)),
        "G": gate,
        "groups": {"G": int(gate), **groups},
        "A": groups["A"],
        "Q": groups["Q"],
        "M": groups["M"],
        "R": groups["R"],
        "D": groups["D"],
        "score": score,
        "failure_reasons": list(dict.fromkeys(failure_reasons)),
        "gate_reasons": list(facts.get("gate_reasons", [])),
        "scenario_rows": rows,
        "pair_metrics": pair,
        "structure_decision": structure,
        "channel_activity_decision": activity,
        "utility_metrics": utilities,
        "metrics": metrics,
        "measurement_policy": {
            "wrist_scored": False,
            "wrist_reason": "public prompt mapping remains ambiguous",
            "position_closure_scored": False,
            "position_closure_reason": "hidden fixed-DH and joint-sign convention remains forbidden",
            "mechanism_replacement": "qualified port graph plus six-channel runtime activity",
        },
    }
    return result


def _separate_event_metrics(
    evidence: Mapping[str, Any],
    waveforms: list[dict[str, tuple[np.ndarray, np.ndarray]]],
    pair: Mapping[str, Any],
) -> dict[str, Any]:
    by_name = {
        str(run.get("scenario", "")): index
        for index, run in enumerate(evidence.get("runs", []))
    }
    disturbed_index = by_name["heavy_corner"]
    control_index = by_name["heavy_corner_no_disturbance"]
    disturbed_run = evidence["runs"][disturbed_index]
    disturbed = waveforms[disturbed_index]
    control = waveforms[control_index]
    time, state = disturbed["joint_state"]
    control_state = SCORING_CORE._interpolate(control["joint_state"][0], control["joint_state"][1], time)
    pose = SCORING_CORE._interpolate(
        disturbed["end_effector_pose"][0], disturbed["end_effector_pose"][1], time
    )
    control_pose = SCORING_CORE._interpolate(
        control["end_effector_pose"][0], control["end_effector_pose"][1], time
    )
    torque = SCORING_CORE._interpolate(
        disturbed["joint_torque"][0], disturbed["joint_torque"][1], time
    )
    control_torque = SCORING_CORE._interpolate(
        control["joint_torque"][0], control["joint_torque"][1], time
    )
    inputs = disturbed_run.get("inputs", {})
    start = float(inputs["disturbance_start"])
    scale = float(inputs["torque_limit_scale"])
    eligible = time >= start
    limits = np.asarray([80, 70, 60, 22, 18, 14], dtype=float) * scale
    state_difference = np.linalg.norm(state[:, :6] - control_state[:, :6], axis=1)
    pose_difference = np.linalg.norm(pose[:, :3] - control_pose[:, :3], axis=1)
    result = copy.deepcopy(dict(pair))
    result.update(
        {
            "torque_event_evidence": float(
                np.max(np.abs(torque[eligible] - control_torque[eligible]) / limits)
            ),
            "state_event_evidence": float(
                np.max(state_difference[eligible]) / math.sqrt(6.0)
            ),
            "pose_event_evidence_cm": float(np.max(pose_difference[eligible])),
        }
    )
    result["state_event_present"] = bool(
        result["state_event_evidence"] > MIN_STATE_EVENT
    )
    result["pose_event_present"] = bool(
        result["pose_event_evidence_cm"] > MIN_POSE_EVENT_CM
    )
    result["core_event_present"] = bool(
        result.get("core_event_present", False)
        and result["state_event_present"]
        and result["pose_event_present"]
    )
    result["valid"] = bool(
        result.get("valid", False)
        and result["state_event_present"]
        and result["pose_event_present"]
    )
    return result


def main() -> None:
    args = SCORING_CORE.parser(TASK_ID).parse_args()
    evidence = SCORING_CORE.load_evidence(args.evidence, TASK_ID)
    waveform_path = SCORING_CORE.locate_waveforms(args.evidence, evidence)
    rows, pair = SCORING_CORE.correct_measurements(evidence, waveform_path)
    waveforms = SCORING_CORE.load_waveforms(waveform_path, len(evidence.get("runs", [])))
    pair = _separate_event_metrics(evidence, waveforms, pair)
    receipt = score_evidence(evidence, scenario_rows=rows, pair_metrics=pair)
    receipt.update(
        {
            "evidence_path": str(args.evidence.resolve()),
            "waveforms_path": str(waveform_path.resolve()),
        }
    )
    SCORING_CORE.write_receipt(args.output, receipt)


if __name__ == "__main__":
    main()
