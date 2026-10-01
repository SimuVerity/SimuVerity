#!/usr/bin/env python3
"""Dedicated fixed-evidence offline scorer for F90-XMECH-08."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

import numpy as np


TASK_ID = "F90-XMECH-08"
POLICY_ID = 'simuverity-101-v1:f90-xmech-08:scoring'
REQUIRED_IDS = {
    "nominal",
    "short_crank",
    "long_crank",
    "short_coupler",
    "long_coupler",
    "near_grashof_boundary",
}
WEIGHTS = {"A": 0.30, "Q": 0.15, "M": 0.25, "R": 0.20, "D": 0.10}


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


def ratio_score(value: float, target: float, full: float, zero: float) -> float:
    relative = abs(value - target) / max(abs(target), 1e-12)
    return lower_better(relative, full, zero)


def weighted_mean(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum(weight for _, weight in parts.values())
    if denominator <= 0:
        return 0.0
    return sum(clamp(value) * weight for value, weight in parts.values()) / denominator


def geometric(groups: dict[str, float]) -> float:
    if any(groups[key] <= 0 for key in WEIGHTS):
        return 0.0
    return math.exp(sum(WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS))


def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row["id"]): row for row in evidence.get("scenarios", [])}


def trajectory(row: dict[str, Any]) -> np.ndarray:
    value = np.asarray(row["trajectory"]["tip_xy_m"], dtype=float)
    if value.ndim != 2 or value.shape[1] != 2:
        raise ValueError("tip trajectory must have shape N x 2")
    return value


def drive(row: dict[str, Any]) -> np.ndarray:
    value = np.asarray(row["trajectory"]["drive_state"], dtype=float)
    if value.ndim != 2 or value.shape[1] != 2:
        raise ValueError("drive state must have shape N x 2")
    return value


def rigid_cyclic_error(test: np.ndarray, reference: np.ndarray) -> float:
    """Return the best rigid, phase-cyclic path RMSE without scale fitting."""
    count = min(len(test), len(reference))
    if count < 8:
        return float("inf")
    test = test[:count]
    reference = reference[:count]
    # Drop the repeated endpoint before cyclic alignment.
    if count > 8:
        test = test[:-1]
        reference = reference[:-1]
    test_centered = test - np.mean(test, axis=0, keepdims=True)
    reference_centered = reference - np.mean(reference, axis=0, keepdims=True)
    best = float("inf")
    for shift in range(len(test_centered)):
        shifted = np.roll(test_centered, shift, axis=0)
        covariance = shifted.T @ reference_centered
        left, _, right = np.linalg.svd(covariance)
        rotation = left @ right
        aligned = shifted @ rotation
        error = float(np.sqrt(np.mean(np.sum((aligned - reference_centered) ** 2, axis=1))))
        best = min(best, error)
    return best


def scenario_accuracy(
    row: dict[str, Any], reference: dict[str, Any]
) -> tuple[float, dict[str, tuple[float, float]]]:
    metrics = row["metrics"]
    expected = reference["metrics"]
    path_error_m = rigid_cyclic_error(trajectory(row), trajectory(reference))
    drive_test = drive(row)
    drive_reference = drive(reference)
    drive_count = min(len(drive_test), len(drive_reference))
    drive_angle_rmse = float(
        np.sqrt(np.mean((drive_test[:drive_count, 0] - drive_reference[:drive_count, 0]) ** 2))
    )
    drive_speed_rmse = float(
        np.sqrt(np.mean((drive_test[:drive_count, 1] - drive_reference[:drive_count, 1]) ** 2))
    )
    parts = {
        "rigid_path_shape": (lower_better(path_error_m, 0.001, 0.050), 0.45),
        "path_length": (
            ratio_score(
                float(metrics["path_length_m"]),
                float(expected["path_length_m"]),
                0.01,
                0.25,
            ),
            0.15,
        ),
        "enclosed_area": (
            ratio_score(
                float(metrics["enclosed_area_m2"]),
                float(expected["enclosed_area_m2"]),
                0.02,
                0.40,
            ),
            0.15,
        ),
        "path_extent": (
            0.5
            * ratio_score(
                float(metrics["x_span_m"]),
                float(expected["x_span_m"]),
                0.02,
                0.30,
            )
            + 0.5
            * ratio_score(
                float(metrics["y_span_m"]),
                float(expected["y_span_m"]),
                0.02,
                0.30,
            ),
            0.10,
        ),
        "drive_angle": (lower_better(drive_angle_rmse, 0.3, 15.0), 0.10),
        "drive_speed": (lower_better(drive_speed_rmse, 0.2, 8.0), 0.05),
    }
    return weighted_mean(parts), parts


def path_quality(
    row: dict[str, Any], reference: dict[str, Any]
) -> tuple[float, dict[str, tuple[float, float]]]:
    metrics = row["metrics"]
    expected = reference["metrics"]
    step_ratio = float(metrics["maximum_step_m"]) / max(
        float(metrics["median_step_m"]), 1e-12
    )
    expected_step_ratio = float(expected["maximum_step_m"]) / max(
        float(expected["median_step_m"]), 1e-12
    )
    parts = {
        "finite": (
            higher_better(float(metrics["finite_fraction"]), 0.995, 1.0),
            0.25,
        ),
        "cycle_closure": (
            lower_better(float(metrics["closure_error_fraction"]), 0.002, 0.03),
            0.25,
        ),
        "smooth_sampling": (
            ratio_score(step_ratio, expected_step_ratio, 0.10, 1.00),
            0.20,
        ),
        "nondegenerate_x": (
            higher_better(float(metrics["x_span_m"]), 0.005, 0.05),
            0.10,
        ),
        "nondegenerate_y": (
            higher_better(float(metrics["y_span_m"]), 0.005, 0.05),
            0.10,
        ),
        "complete_interval": (
            higher_better(float(metrics["duration_s"]), 9.5, 9.9),
            0.10,
        ),
    }
    return weighted_mean(parts), parts


def dynamic_quality(
    row: dict[str, Any], reference: dict[str, Any]
) -> tuple[float, dict[str, tuple[float, float]]]:
    metrics = row["metrics"]
    expected = reference["metrics"]
    parts = {
        "one_revolution": (
            lower_better(abs(float(metrics["drive_angle_span_deg"]) - 360.0), 0.5, 20.0),
            0.30,
        ),
        "constant_drive_speed": (
            lower_better(abs(float(metrics["drive_speed_mean_deg_s"]) - 36.0), 0.2, 5.0),
            0.20,
        ),
        "drive_speed_uniformity": (
            lower_better(float(metrics["drive_speed_cv"]), 0.005, 0.08),
            0.15,
        ),
        "cycle_closure": (
            lower_better(float(metrics["closure_error_fraction"]), 0.002, 0.03),
            0.20,
        ),
        "tip_speed_envelope": (
            ratio_score(
                float(metrics["tip_speed_cv"]),
                float(expected["tip_speed_cv"]),
                0.10,
                1.00,
            ),
            0.15,
        ),
    }
    return weighted_mean(parts), parts


def response_descriptor(
    rows: dict[str, dict[str, Any]], scenario_id: str
) -> np.ndarray:
    nominal = rows["nominal"]["metrics"]
    changed = rows[scenario_id]["metrics"]
    names = ["path_length_m", "enclosed_area_m2", "x_span_m", "y_span_m", "radius_rms_m"]
    return np.asarray(
        [
            (float(changed[name]) - float(nominal[name]))
            / max(abs(float(nominal[name])), 1e-12)
            for name in names
        ],
        dtype=float,
    )


def score(evidence: dict[str, Any], reference_evidence: dict[str, Any]) -> dict[str, Any]:
    rows = scenario_map(evidence)
    reference_rows = scenario_map(reference_evidence)
    static = evidence.get("static_audit", {})
    qualification_checks = {
        "load": bool(evidence.get("load_pass")),
        "update": bool(evidence.get("update_pass")),
        "compile": bool(evidence.get("compile_pass")),
        "simulate": bool(evidence.get("simulate_pass")),
        "scenario_set": set(rows) == REQUIRED_IDS,
        "reference_scenario_set": set(reference_rows) == REQUIRED_IDS,
        "all_scenarios_valid": set(rows) == REQUIRED_IDS
        and all(bool(rows[key].get("outputs_valid")) for key in REQUIRED_IDS),
        "connected_four_bar": bool(static.get("connected_four_bar_signature")),
        "physical_drive": bool(static.get("physical_drive_signature")),
        "physical_tip_measurement": bool(static.get("physical_tip_measurement_signature")),
    }
    gate = all(qualification_checks.values())
    if not gate:
        return {
            "schema": "simuverity.f90-xmech08-score.v1",
            "task_id": TASK_ID,
            "policy_id": POLICY_ID,
            "G": 0.0,
            "groups": {"A": 0.0, "Q": 0.0, "M": 0.0, "R": 0.0, "D": 0.0},
            "group_weights": WEIGHTS,
            "score_raw": 0.0,
            "score": 0.0,
            "admission_threshold_raw": 85.0,
            "admission_pass": False,
            "qualification_checks": qualification_checks,
            "failures": [
                name for name, passed in qualification_checks.items() if not passed
            ],
        }

    accuracy: dict[str, float] = {}
    accuracy_parts: dict[str, Any] = {}
    quality: dict[str, float] = {}
    quality_parts: dict[str, Any] = {}
    dynamics: dict[str, float] = {}
    dynamics_parts: dict[str, Any] = {}
    for scenario_id in sorted(REQUIRED_IDS):
        accuracy[scenario_id], accuracy_parts[scenario_id] = scenario_accuracy(
            rows[scenario_id], reference_rows[scenario_id]
        )
        quality[scenario_id], quality_parts[scenario_id] = path_quality(
            rows[scenario_id], reference_rows[scenario_id]
        )
        dynamics[scenario_id], dynamics_parts[scenario_id] = dynamic_quality(
            rows[scenario_id], reference_rows[scenario_id]
        )

    response_scores: dict[str, float] = {}
    for scenario_id in sorted(REQUIRED_IDS - {"nominal"}):
        test_response = response_descriptor(rows, scenario_id)
        expected_response = response_descriptor(reference_rows, scenario_id)
        relative_error = float(
            np.linalg.norm(test_response - expected_response)
            / max(np.linalg.norm(expected_response), 1e-9)
        )
        response_scores[scenario_id] = lower_better(relative_error, 0.05, 1.0)
    response_minimum = min(response_scores.values())
    static_mechanism = float(
        bool(static.get("connected_four_bar_signature"))
        and bool(static.get("physical_drive_signature"))
        and bool(static.get("physical_tip_measurement_signature"))
    )
    mechanism_parts = {
        "connected_physical_loop": (static_mechanism, 0.40),
        "crank_length_causality": (
            min(response_scores["short_crank"], response_scores["long_crank"]),
            0.25,
        ),
        "coupler_length_causality": (
            min(response_scores["short_coupler"], response_scores["long_coupler"]),
            0.25,
        ),
        "joint_boundary_causality": (response_scores["near_grashof_boundary"], 0.10),
    }

    groups = {
        "A": accuracy["nominal"],
        "Q": min(quality.values()),
        "M": weighted_mean(mechanism_parts),
        "R": min(accuracy.values()),
        "D": min(dynamics.values()),
    }
    raw = 100.0 * geometric(groups)
    shortcut_findings: list[dict[str, str]] = []
    minimum_span = min(
        min(float(rows[key]["metrics"]["x_span_m"]), float(rows[key]["metrics"]["y_span_m"]))
        for key in REQUIRED_IDS
    )
    if minimum_span < 1e-3:
        shortcut_findings.append({"id": "constant_or_degenerate_tip"})
    if response_minimum < 0.50:
        shortcut_findings.append({"id": "official_geometry_ignored"})
    if min(accuracy.values()) < 0.50:
        shortcut_findings.append({"id": "wrong_official_trajectory"})
    minimum_drive_span = min(
        float(rows[key]["metrics"]["drive_angle_span_deg"]) for key in REQUIRED_IDS
    )
    if minimum_drive_span < 350.0:
        shortcut_findings.append({"id": "incomplete_crank_revolution"})

    return {
        "schema": "simuverity.f90-xmech08-score.v1",
        "task_id": TASK_ID,
        "policy_id": POLICY_ID,
        "G": 1.0,
        "groups": groups,
        "group_weights": WEIGHTS,
        "formula": "G*100*A^0.30*Q^0.15*M^0.25*R^0.20*D^0.10",
        "score_raw": raw,
        "score": raw,
        "score_is_raw_not_rescaled": True,
        "admission_threshold_raw": 85.0,
        "admission_pass": raw >= 85.0,
        "qualification_checks": qualification_checks,
        "details": {
            "A": accuracy_parts["nominal"],
            "Q": {
                "aggregation": "100_percent_minimum",
                "by_scenario": quality,
                "parts": quality_parts,
            },
            "M": {
                "parts": mechanism_parts,
                "geometry_response_by_scenario": response_scores,
            },
            "R": {
                "aggregation": "100_percent_minimum",
                "by_scenario": accuracy,
                "parts": accuracy_parts,
            },
            "D": {
                "aggregation": "100_percent_minimum",
                "by_scenario": dynamics,
                "parts": dynamics_parts,
            },
        },
        "shortcut_findings": shortcut_findings,
        "failures": [],
    }


def run_shortcut_sanity(
    evidence: dict[str, Any], reference_evidence: dict[str, Any]
) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []

    missing = copy.deepcopy(evidence)
    missing["scenarios"][0]["outputs_valid"] = False
    cases.append(("required_output_missing", missing, 0.0))

    disconnected = copy.deepcopy(evidence)
    disconnected["static_audit"]["connected_four_bar_signature"] = False
    cases.append(("physical_loop_disconnected", disconnected, 0.0))

    no_sensor = copy.deepcopy(evidence)
    no_sensor["static_audit"]["physical_tip_measurement_signature"] = False
    cases.append(("prescribed_tip_without_physical_sensor", no_sensor, 0.0))

    constant_tip = copy.deepcopy(evidence)
    for row in constant_tip["scenarios"]:
        row["trajectory"]["tip_xy_m"] = np.zeros((129, 2)).tolist()
        row["metrics"]["x_span_m"] = 0.0
        row["metrics"]["y_span_m"] = 0.0
        row["metrics"]["path_length_m"] = 0.0
        row["metrics"]["enclosed_area_m2"] = 0.0
        row["metrics"]["radius_rms_m"] = 0.0
    cases.append(("constant_tip_output", constant_tip, 30.0))

    nominal_replay = copy.deepcopy(evidence)
    nominal = copy.deepcopy(scenario_map(nominal_replay)["nominal"])
    for row in nominal_replay["scenarios"]:
        requested = copy.deepcopy(row["requested_inputs"])
        row["metrics"] = copy.deepcopy(nominal["metrics"])
        row["trajectory"] = copy.deepcopy(nominal["trajectory"])
        row["requested_inputs"] = requested
    cases.append(("nominal_geometry_replayed", nominal_replay, 65.0))

    constant_drive = copy.deepcopy(evidence)
    for row in constant_drive["scenarios"]:
        state = np.asarray(row["trajectory"]["drive_state"], dtype=float)
        state[:, 0] = 0.0
        state[:, 1] = 0.0
        row["trajectory"]["drive_state"] = state.tolist()
        row["metrics"]["drive_angle_span_deg"] = 0.0
        row["metrics"]["drive_speed_mean_deg_s"] = 0.0
        row["metrics"]["drive_speed_cv"] = 0.0
    cases.append(("crank_revolution_missing", constant_drive, 65.0))

    distorted = copy.deepcopy(evidence)
    for row in distorted["scenarios"]:
        xy = np.asarray(row["trajectory"]["tip_xy_m"], dtype=float)
        xy[:, 0] *= 0.55
        row["trajectory"]["tip_xy_m"] = xy.tolist()
        row["metrics"]["x_span_m"] *= 0.55
        row["metrics"]["path_length_m"] *= 0.70
        row["metrics"]["enclosed_area_m2"] *= 0.55
    cases.append(("wrong_linkage_geometry", distorted, 70.0))

    results = []
    for name, mutated, maximum in cases:
        result = score(mutated, reference_evidence)
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
        "schema": "simuverity.f90-xmech08-shortcut-sanity.v1",
        "task_id": TASK_ID,
        "cases": results,
        "all_pass": all(item["pass"] for item in results),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--reference-evidence", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--sanity-out", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    reference_path = args.reference_evidence or args.evidence
    reference = json.loads(reference_path.read_text(encoding="utf-8"))
    result = score(evidence, reference)
    text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
    if args.sanity_out:
        sanity = run_shortcut_sanity(evidence, reference)
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(
            json.dumps(sanity, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )
    print(text)


if __name__ == "__main__":
    main()
