#!/usr/bin/env python3
"""Pure-offline scorer for F90-XMECH-02.

The scorer reads fixed JSON evidence.  It never starts MATLAB and never
changes the model, scenarios, or extracted signals.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


FORMAL_ID = "F90-XMECH-02"
EVIDENCE_SCHEMA = "simuverity.f90-xmech02-evidence.v1"
SCORE_SCHEMA = "simuverity.f90-xmech02-offline-score.v1"
ADMISSION_SCORE = 85.0

REQUIRED_METRICS = (
    "wind_speed_binding_rmse_mps",
    "wind_direction_binding_rmse_deg",
    "pitch_tracking_rmse_deg",
    "pitch_post_event_peak_abs_error_deg",
    "pitch_final_abs_error_deg",
    "pitch_measurement_range_deg",
    "hydraulic_force_active_channels",
    "hydraulic_force_range_n",
    "hydraulic_force_channel_balance",
    "yaw_initial_abs_error_deg",
    "yaw_post_event_peak_abs_error_deg",
    "yaw_final_abs_error_deg",
    "yaw_error_reduction_fraction",
    "yaw_tracking_rmse_deg",
    "yaw_signed_response_deg",
    "yaw_motor_active_channels",
    "yaw_motor_torque_range_nm",
    "yaw_motor_channel_balance",
    "rotor_speed_range_rad_s",
    "generator_speed_range_rpm",
    "drivetrain_torque_range_nm",
    "generator_power_range_w",
    "generator_energy_abs_j",
    "power_nonzero_fraction",
    "pitch_command_copy_rmse_deg",
    "yaw_command_copy_rmse_deg",
    "wind_to_torque_lag_s",
    "torque_to_power_lag_s",
    "pitch_effort_to_motion_lag_s",
    "yaw_effort_to_motion_lag_s",
    "steady_rotor_speed_cv",
    "steady_power_cv",
    "finite_fraction",
)


def _task_paths() -> tuple[Path, Path]:
    here = Path(__file__).resolve()
    task_root = here.parents[5]
    return task_root, task_root / "official_scenarios.json"


def _finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def _higher(value: float, bad: float, good: float) -> float:
    if good <= bad:
        raise ValueError("higher utility requires good > bad")
    return _clamp((value - bad) / (good - bad))


def _lower(value: float, good: float, bad: float) -> float:
    if bad <= good:
        raise ValueError("lower utility requires bad > good")
    return _clamp((bad - value) / (bad - good))


def _positive_lag(value: float, max_good: float = 15.0) -> float:
    if not math.isfinite(value) or value <= 0:
        return 0.0
    if value <= max_good:
        return 1.0
    return _lower(value, max_good, 2.0 * max_good)


def _mean(values: list[float], weights: list[float] | None = None) -> float:
    if not values:
        return 0.0
    if weights is None:
        return sum(values) / len(values)
    return sum(v * w for v, w in zip(values, weights)) / sum(weights)


def _row_utility(row: dict[str, Any]) -> float:
    m = row["metrics"]
    recovery = _recovery_utility(m)
    return _mean(
        [
            _lower(m["pitch_tracking_rmse_deg"], 0.5, 10.0),
            _lower(m["yaw_final_abs_error_deg"], 3.0, 20.0),
            _higher(m["yaw_error_reduction_fraction"], 0.0, 0.75),
            _lower(m["steady_rotor_speed_cv"], 0.05, 0.50),
            _higher(m["power_nonzero_fraction"], 0.05, 0.50),
            recovery,
        ]
    )


def _recovery_utility(metrics: dict[str, float]) -> float:
    yaw_peak = max(metrics["yaw_post_event_peak_abs_error_deg"], 1.0e-9)
    pitch_peak = max(metrics["pitch_post_event_peak_abs_error_deg"], 1.0e-9)
    yaw_recovery = _clamp(1.0 - metrics["yaw_final_abs_error_deg"] / yaw_peak)
    pitch_recovery = _clamp(1.0 - metrics["pitch_final_abs_error_deg"] / pitch_peak)
    return _mean([yaw_recovery, pitch_recovery])


def _validate_evidence(
    evidence: dict[str, Any], official: dict[str, Any]
) -> tuple[bool, list[str], dict[str, dict[str, Any]]]:
    failures: list[str] = []
    if evidence.get("schema") != EVIDENCE_SCHEMA:
        failures.append("evidence schema mismatch")
    if evidence.get("formal_id") != FORMAL_ID:
        failures.append("formal task id mismatch")
    if evidence.get("extraction_only") is not True:
        failures.append("evidence is not marked extraction-only")
    if evidence.get("contains_score_or_threshold_decisions") is not False:
        failures.append("evidence contains score or threshold decisions")
    if evidence.get("adapter") != "standard_public_outputs" and not isinstance(
        evidence.get("direct_reference_integrity"), dict
    ):
        failures.append("unknown evidence adapter")
    for field in ("load_pass", "update_pass", "compile_pass"):
        if evidence.get(field) is not True:
            failures.append(f"{field} is false")

    expected = official["scenarios"]
    rows = evidence.get("scenarios")
    if not isinstance(rows, list):
        failures.append("scenario evidence is missing")
        return False, failures, {}
    expected_ids = [item["id"] for item in expected]
    actual_ids = [row.get("id") for row in rows if isinstance(row, dict)]
    if actual_ids != expected_ids:
        failures.append("scenario order or membership mismatch")

    by_id: dict[str, dict[str, Any]] = {}
    for index, expected_row in enumerate(expected):
        if index >= len(rows) or not isinstance(rows[index], dict):
            continue
        row = rows[index]
        by_id[str(row.get("id", ""))] = row
        requested = row.get("requested_inputs", {})
        for source_field, evidence_field in (
            ("time_s", "time_s"),
            ("wind_speed_mps", "wind_speed_mps"),
            ("wind_direction_deg", "wind_direction_deg"),
        ):
            expected_values = [float(value) for value in expected_row[source_field]]
            actual_values = requested.get(evidence_field)
            if not isinstance(actual_values, list) or [
                float(value) for value in actual_values
            ] != expected_values:
                failures.append(
                    f"{expected_row['id']}: requested input {evidence_field} mismatch"
                )
        for flag in (
            "valid",
            "simulation_pass",
            "output_contract_pass",
            "finite_pass",
            "scenario_applied",
        ):
            if row.get(flag) is not True:
                failures.append(f"{expected_row['id']}: {flag} is false")
        if not _finite_number(row.get("samples")) or row["samples"] < 2:
            failures.append(f"{expected_row['id']}: insufficient samples")
        if not _finite_number(row.get("duration_s")) or row["duration_s"] <= 0:
            failures.append(f"{expected_row['id']}: invalid duration")
        metrics = row.get("metrics")
        if not isinstance(metrics, dict):
            failures.append(f"{expected_row['id']}: metrics missing")
            continue
        for metric in REQUIRED_METRICS:
            if metric not in metrics or not _finite_number(metrics[metric]):
                failures.append(f"{expected_row['id']}: invalid metric {metric}")
        if all(
            metric in metrics and _finite_number(metrics[metric])
            for metric in (
                "wind_speed_binding_rmse_mps",
                "wind_direction_binding_rmse_deg",
            )
        ):
            if metrics["wind_speed_binding_rmse_mps"] > 0.50:
                failures.append(f"{expected_row['id']}: wind-speed input was not applied")
            if metrics["wind_direction_binding_rmse_deg"] > 1.0:
                failures.append(f"{expected_row['id']}: wind-direction input was not applied")

    raw_artifact = evidence.get("raw_artifact", {})
    if raw_artifact.get("format") != "MAT-v7.3":
        failures.append("raw artifact format is not MAT-v7.3")
    return not failures, failures, by_id


def _score_groups(
    rows: dict[str, dict[str, Any]], official: dict[str, Any]
) -> tuple[dict[str, float], dict[str, Any], dict[str, float]]:
    nominal = rows["nominal_start"]["metrics"]
    all_rows = [rows[item["id"]] for item in official["scenarios"]]

    a = _mean(
        [
            # A measures nominal regulation accuracy after startup; D and R
            # retain the transient and whole-scenario penalties. Using the
            # full cold-start RMSE here would deduct the same startup event
            # twice even when the physical loop settles accurately.
            _lower(nominal["pitch_final_abs_error_deg"], 0.05, 1.0),
            _lower(nominal["yaw_final_abs_error_deg"], 3.0, 20.0),
            _higher(nominal["rotor_speed_range_rad_s"], 0.02, 0.30),
            _higher(nominal["generator_speed_range_rpm"], 2.0, 40.0),
            _higher(nominal["generator_energy_abs_j"], 1.0e5, 1.0e7),
            _higher(nominal["power_nonzero_fraction"], 0.05, 0.50),
        ]
    )

    q_rows = []
    for row in all_rows:
        m = row["metrics"]
        q_rows.append(
            _mean(
                [
                    _higher(m["finite_fraction"], 0.98, 1.0),
                    _lower(m["steady_rotor_speed_cv"], 0.05, 0.50),
                    _lower(m["steady_power_cv"], 0.10, 1.0),
                    _higher(m["hydraulic_force_channel_balance"], 0.10, 0.75),
                    _higher(m["yaw_motor_channel_balance"], 0.10, 0.75),
                ]
            )
        )
    q = min(q_rows)

    static = rows["nominal_start"].get("static_audit", {})
    structural_components = {
        "three_blade_aerodynamic_path": (
            1.0 if static.get("three_blade_aerodynamic_path") else 0.0
        ),
        "three_hydraulic_pitch_paths": _higher(
            float(static.get("hydraulic_pitch_path_count", 0)), 0.0, 3.0
        ),
        "four_electric_yaw_paths": _higher(
            float(static.get("electric_yaw_path_count", 0)), 0.0, 4.0
        ),
        "drivetrain_generator_grid_path": (
            1.0 if static.get("drivetrain_generator_grid_path") else 0.0
        ),
        "measured_pitch_feedback": (
            1.0 if static.get("measured_pitch_feedback") else 0.0
        ),
        "measured_yaw_feedback": (
            1.0 if static.get("measured_yaw_feedback") else 0.0
        ),
    }
    # These are six explicit, mandatory parts of the public physical chain.
    # The weakest part therefore defines structural completeness.  Dynamic
    # evidence remains a separate partial-credit route, so an absent path does
    # not mechanically zero the complete M group or the total score.
    structural_core = min(structural_components.values())

    def best(metric: str) -> float:
        return max(row["metrics"][metric] for row in all_rows)

    dynamic_mechanism = _mean(
        [
            _higher(best("hydraulic_force_active_channels"), 0.0, 3.0),
            _higher(best("yaw_motor_active_channels"), 0.0, 4.0),
            _higher(best("hydraulic_force_range_n"), 1.0, 1.0e3),
            _higher(best("yaw_motor_torque_range_nm"), 1.0, 100.0),
            _higher(best("drivetrain_torque_range_nm"), 100.0, 1.0e4),
            _higher(best("generator_power_range_w"), 1.0e3, 1.0e5),
            _higher(best("pitch_command_copy_rmse_deg"), 1.0e-4, 0.05),
            _higher(best("yaw_command_copy_rmse_deg"), 1.0e-4, 0.05),
            max(
                _positive_lag(row["metrics"]["wind_to_torque_lag_s"])
                for row in all_rows
            ),
            max(
                _positive_lag(row["metrics"]["torque_to_power_lag_s"])
                for row in all_rows
            ),
            max(
                _positive_lag(row["metrics"]["pitch_effort_to_motion_lag_s"])
                for row in all_rows
            ),
            max(
                _positive_lag(row["metrics"]["yaw_effort_to_motion_lag_s"])
                for row in all_rows
            ),
        ]
    )
    m_group = _mean([structural_core, dynamic_mechanism], [0.80, 0.20])

    worst_ids = official["scenario_sets"]["worst_case_reduction"]
    r_values = [_row_utility(rows[scenario_id]) for scenario_id in worst_ids]
    r = min(r_values)

    positive = rows["positive_direction_change"]["metrics"]
    negative = rows["negative_direction_change"]["metrics"]
    signed_yaw = _mean(
        [
            _higher(positive["yaw_signed_response_deg"], 0.0, 5.0),
            _higher(-negative["yaw_signed_response_deg"], 0.0, 5.0),
            _higher(positive["yaw_error_reduction_fraction"], 0.0, 0.75),
            _higher(negative["yaw_error_reduction_fraction"], 0.0, 0.75),
        ]
    )
    d = _mean(
        [
            _recovery_utility(rows["nominal_start"]["metrics"]),
            _recovery_utility(rows["high_wind_regulation"]["metrics"]),
            signed_yaw,
            _recovery_utility(rows["joint_wind_event"]["metrics"]),
        ]
    )

    groups = {"A": _clamp(a), "Q": _clamp(q), "M": _clamp(m_group), "R": _clamp(r), "D": _clamp(d)}
    diagnostics = {
        "structural_components": structural_components,
        "structural_core": structural_core,
        "cross_scenario_mechanism_score": dynamic_mechanism,
        "scenario_quality_min": min(q_rows),
        "worst_case_utilities": dict(zip(worst_ids, r_values)),
        "signed_yaw_score": signed_yaw,
    }
    # Policy current expresses deficiencies inside the applicable groups.  It has
    # no post-hoc total-score cap and does not scale the final score.
    return groups, diagnostics, {}


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    _, official_path = _task_paths()
    official = json.loads(official_path.read_text(encoding="utf-8"))
    valid, failures, rows = _validate_evidence(evidence, official)
    weights = {key: float(value) for key, value in official["groups"]["weights"].items()}

    if not valid:
        groups = {key: 0.0 for key in ("A", "Q", "M", "R", "D")}
        diagnostics: dict[str, Any] = {}
        raw_total = 0.0
        total = 0.0
    else:
        groups, diagnostics, _ = _score_groups(rows, official)
        if any(value <= 0.0 for value in groups.values()):
            raw_total = 0.0
        else:
            raw_total = 100.0 * math.prod(
                groups[key] ** weights[key] for key in ("A", "Q", "M", "R", "D")
            )
        total = raw_total

    return {
        "schema": SCORE_SCHEMA,
        "formal_id": FORMAL_ID,
        "policy_id": official["score_policy_id"],
        "admission_score": ADMISSION_SCORE,
        "reference_normalization_applied": False,
        "valid": valid,
        "score_inputs_valid": valid,
        "G": valid,
        "groups": groups,
        "group_weights": weights,
        "raw_total": raw_total,
        "total": total,
        "score": total,
        "threshold_pass": valid and total >= ADMISSION_SCORE,
        "metrics": diagnostics,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    evidence_path = Path(args.evidence)
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    score = score_evidence(evidence)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(score, indent=2, sort_keys=True), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
