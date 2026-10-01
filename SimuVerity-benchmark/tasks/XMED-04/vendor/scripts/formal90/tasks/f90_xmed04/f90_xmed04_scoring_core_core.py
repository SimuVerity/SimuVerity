#!/usr/bin/env python3
"""Dedicated pure-offline scorer for F90-XMED-04 fixed evidence."""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


POLICY_ID = 'simuverity-101-v1:f90-xmed-04:scoring'
REQUIRED = [
    "nominal",
    "high_carbohydrate",
    "shifted_meals",
    "low_weight",
    "slow_sensor",
    "joint_service",
]
WEIGHTS = {"A": 0.20, "Q": 0.15, "M": 0.30, "R": 0.20, "D": 0.15}


def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value) or full <= zero:
        return 0.0
    return clamp((value - zero) / (full - zero))


def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value) or zero <= full:
        return 0.0
    return clamp((zero - value) / (zero - full))


def band(value: float, low_full: float, high_full: float,
         low_zero: float, high_zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return high(value, low_zero, low_full)
    return low(value, high_full, high_zero)


def weighted(values: list[float], weights: list[float]) -> float:
    total = sum(weights)
    if total <= 0:
        return 0.0
    return sum(v * w for v, w in zip(values, weights)) / total


def relative_difference(a: list[float], b: list[float]) -> float:
    if len(a) != len(b) or not a:
        return 0.0
    numerator = math.sqrt(sum((float(x) - float(y)) ** 2 for x, y in zip(a, b)))
    denominator = max(math.sqrt(sum(float(x) ** 2 for x in a)), 1e-9)
    return numerator / denominator


def scenario_score(summary: dict[str, Any]) -> tuple[float, dict[str, float]]:
    parts = {
        "time_in_range": high(float(summary["time_in_range_fraction"]), 0.25, 0.70),
        "severe_hypoglycaemia": low(
            float(summary["severe_hypoglycaemia_fraction"]), 0.0, 0.08
        ),
        "severe_hyperglycaemia": low(
            float(summary["severe_hyperglycaemia_fraction"]), 0.0, 0.25
        ),
        "minimum_glucose": high(float(summary["glucose_min_mg_dL"]), 45.0, 65.0),
        "maximum_glucose": low(float(summary["glucose_max_mg_dL"]), 250.0, 500.0),
        "finite": float(bool(summary["all_values_finite"])),
    }
    score = weighted(list(parts.values()), [0.35, 0.15, 0.15, 0.10, 0.15, 0.10])
    return score, parts


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get("id")): row for row in evidence.get("scenarios", [])}
    static = evidence.get("static_audit", {})
    failures: list[str] = []
    for key in ("load_pass", "update_pass", "compile_pass"):
        if not bool(evidence.get(key)):
            failures.append(f"{key} is false")
    missing = [
        name for name in REQUIRED
        if name not in rows
        or not bool(rows[name].get("simulation_pass"))
        or not bool(rows[name].get("valid"))
    ]
    if missing:
        failures.append("invalid required scenarios: " + ", ".join(missing))
    if not bool(static.get("core_path_qualified")):
        failures.append("connected physiological feedback path not qualified")
    if not bool(evidence.get("model_closed_without_save")):
        failures.append("model was not closed without save")
    gate = not failures
    if not gate:
        return make_receipt(
            evidence,
            {"G": 0.0, "A": 0.0, "Q": 0.0, "M": 0.0, "R": 0.0, "D": 0.0},
            0.0,
            failures,
            {},
        )

    summaries = {name: rows[name]["summary"] for name in REQUIRED}
    nominal = summaries["nominal"]
    per_scenario: dict[str, float] = {}
    per_parts: dict[str, dict[str, float]] = {}
    for name, summary in summaries.items():
        per_scenario[name], per_parts[name] = scenario_score(summary)

    a_parts = {
        "time_in_range": high(float(nominal["time_in_range_fraction"]), 0.25, 0.70),
        "severe_hypoglycaemia": low(
            float(nominal["severe_hypoglycaemia_fraction"]), 0.0, 0.06
        ),
        "severe_hyperglycaemia": low(
            float(nominal["severe_hyperglycaemia_fraction"]), 0.0, 0.20
        ),
        "minimum_glucose": high(float(nominal["glucose_min_mg_dL"]), 45.0, 65.0),
        "maximum_glucose": low(float(nominal["glucose_max_mg_dL"]), 250.0, 450.0),
    }
    A = weighted(list(a_parts.values()), [0.45, 0.15, 0.15, 0.10, 0.15])

    q_parts = {
        "sensor_fidelity": low(float(nominal["sensor_rmse_mg_dL"]), 4.0, 35.0),
        "nonnegative_insulin": high(float(nominal["insulin_min_mU_min"]), -1.0, 0.0),
        "bounded_insulin": low(float(nominal["insulin_max_mU_min"]), 200.0, 1000.0),
        "glucose_variability": low(float(nominal["glucose_cv"]), 0.20, 0.80),
        "nonconstant_insulin": high(
            float(nominal["insulin_std_mU_min"]), 0.02, 0.50
        ),
    }
    # Sensor fidelity is the primary quality contract of a sampled
    # artificial-pancreas loop; the remaining terms guard delivery bounds.
    Q = weighted(list(q_parts.values()), [0.60, 0.10, 0.10, 0.10, 0.10])

    nominal_profile = rows["nominal"]["profiles"]
    high_profile = rows["high_carbohydrate"]["profiles"]
    weight_profile = rows["low_weight"]["profiles"]
    slow_profile = rows["slow_sensor"]["profiles"]
    meal_expected = sum(
        float(v) for v in rows["nominal"]["requested_inputs"]["MealCarbs_g"]
    )
    meal_integral = float(nominal["meal_rate_integral_g"])
    absorbed_expected = meal_expected * 0.8 / 0.18
    absorbed_integral = float(nominal["absorbed_rate_integral_mmol"])
    m_parts = {
        "connected_roles_and_feedback": float(
            bool(static.get("core_path_qualified"))
        ),
        "meal_mass_conservation": band(
            meal_integral / max(meal_expected, 1e-9), 0.85, 1.15, 0.20, 2.0
        ),
        "absorption_mass_response": band(
            absorbed_integral / max(absorbed_expected, 1e-9),
            0.65, 1.25, 0.10, 2.5,
        ),
        "meal_load_causality": high(
            relative_difference(
                nominal_profile["true_glucose_mg_dL"],
                high_profile["true_glucose_mg_dL"],
            ),
            0.005,
            0.05,
        ),
        "patient_weight_causality": high(
            relative_difference(
                nominal_profile["true_glucose_mg_dL"],
                weight_profile["true_glucose_mg_dL"],
            ),
            0.003,
            0.03,
        ),
        "sensor_sample_causality": high(
            relative_difference(
                nominal_profile["observed_glucose_mg_dL"],
                slow_profile["observed_glucose_mg_dL"],
            ),
            0.001,
            0.02,
        ),
        "closed_loop_insulin_response": high(
            float(nominal["insulin_std_mU_min"]), 0.02, 0.50
        ),
    }
    M = weighted(
        list(m_parts.values()),
        [0.10, 0.20, 0.20, 0.20, 0.15, 0.05, 0.10],
    )

    R = min(per_scenario.values())

    peak_scores: list[float] = []
    recovery_scores: list[float] = []
    insulin_response_scores: list[float] = []
    for name in REQUIRED:
        summary = summaries[name]
        peaks = [float(value) for value in summary["meal_peak_glucose_mg_dL"]]
        recovery = [float(value) for value in summary["meal_recovery_time_s"]]
        rises = [float(value) for value in summary["meal_insulin_rise_mU_min"]]
        peak_scores.append(sum(low(value, 180.0, 400.0) for value in peaks) / len(peaks))
        recovery_scores.append(
            sum(low(value, 3600.0, 14400.0) for value in recovery) / len(recovery)
        )
        insulin_response_scores.append(
            sum(high(value, 0.02, 0.50) for value in rises) / len(rises)
        )
    d_parts = {
        "post_meal_peak_control": min(peak_scores),
        "post_meal_recovery": min(recovery_scores),
        "post_meal_insulin_response": min(insulin_response_scores),
    }
    # A meal response without a corresponding insulin actuation is not a
    # functioning closed-loop artificial pancreas, so actuation owns half
    # of the dynamic group.
    D = weighted(list(d_parts.values()), [0.30, 0.20, 0.50])

    groups = {"G": 1.0, "A": A, "Q": Q, "M": M, "R": R, "D": D}
    total = 100.0
    for name, exponent in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** exponent
    diagnostics = {
        "A_utilities": a_parts,
        "Q_utilities": q_parts,
        "M_utilities": m_parts,
        "R_scenario_scores": per_scenario,
        "R_scenario_utilities": per_parts,
        "D_utilities": d_parts,
        "raw_summaries": summaries,
    }
    return make_receipt(evidence, groups, total, [], diagnostics)


def make_receipt(
    evidence: dict[str, Any],
    groups: dict[str, float],
    total: float,
    failures: list[str],
    diagnostics: dict[str, Any],
) -> dict[str, Any]:
    return {
        "schema": "simuverity.f90-xmed04-score.v1",
        "task_id": "F90-XMED-04",
        "policy_id": POLICY_ID,
        "formula": "G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15",
        "score_is_raw_not_rescaled": True,
        "admission_threshold": 85,
        "G": groups.get("G") == 1.0,
        "groups": groups,
        "score": total,
        "admission_score_pass": bool(groups.get("G") == 1.0 and total >= 85),
        "diagnostics": diagnostics,
        "failure_reasons": failures,
    }


def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    variants: dict[str, dict[str, Any]] = {}

    missing_core = copy.deepcopy(evidence)
    missing_core["static_audit"]["core_path_qualified"] = False
    variants["disconnected_core"] = missing_core

    missing_output = copy.deepcopy(evidence)
    missing_output["scenarios"][0]["valid"] = False
    variants["missing_required_output"] = missing_output

    constant_insulin = copy.deepcopy(evidence)
    for row in constant_insulin["scenarios"]:
        profile = row["profiles"]["insulin_infusion_mU_min"]
        mean = sum(float(v) for v in profile) / max(len(profile), 1)
        row["profiles"]["insulin_infusion_mU_min"] = [mean] * len(profile)
        row["summary"]["insulin_std_mU_min"] = 0.0
        row["summary"]["insulin_change_rms_mU_min"] = 0.0
        row["summary"]["meal_insulin_rise_mU_min"] = [0.0, 0.0, 0.0]
    variants["constant_insulin"] = constant_insulin

    replayed_glucose = copy.deepcopy(evidence)
    nominal = replayed_glucose["scenarios"][0]
    for row in replayed_glucose["scenarios"][1:]:
        row["profiles"]["true_glucose_mg_dL"] = copy.deepcopy(
            nominal["profiles"]["true_glucose_mg_dL"]
        )
        row["profiles"]["observed_glucose_mg_dL"] = copy.deepcopy(
            nominal["profiles"]["observed_glucose_mg_dL"]
        )
        row["summary"] = copy.deepcopy(nominal["summary"])
    variants["replayed_nominal_glucose"] = replayed_glucose

    no_meal_path = copy.deepcopy(evidence)
    for row in no_meal_path["scenarios"]:
        row["event_evidence"]["meal_rate_integral_g"] = 0.0
        row["event_evidence"]["absorbed_rate_integral_mmol"] = 0.0
        row["summary"]["meal_rate_integral_g"] = 0.0
        row["summary"]["absorbed_rate_integral_mmol"] = 0.0
    variants["missing_meal_absorption"] = no_meal_path

    copied_target = copy.deepcopy(evidence)
    for row in copied_target["scenarios"]:
        n = len(row["profiles"]["observed_glucose_mg_dL"])
        row["profiles"]["observed_glucose_mg_dL"] = [110.0] * n
        row["summary"]["sensor_rmse_mg_dL"] = 90.0
        row["summary"]["sensor_max_abs_error_mg_dL"] = 200.0
    variants["copied_glucose_target"] = copied_target

    results: dict[str, Any] = {}
    for name, variant in variants.items():
        result = score_evidence(variant)
        results[name] = {
            "score": result["score"],
            "G": result["G"],
            "admission_score_pass": result["admission_score_pass"],
            "rejected": not result["admission_score_pass"],
        }
    return {
        "schema": "simuverity.f90-xmed04-shortcut-sanity.v1",
        "task_id": "F90-XMED-04",
        "variants": results,
        "all_rejected": all(item["rejected"] for item in results.values()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_positional", nargs="?")
    parser.add_argument("--evidence")
    parser.add_argument("--output")
    parser.add_argument("--out")
    parser.add_argument("--sanity-output")
    args = parser.parse_args()
    evidence_name = args.evidence or args.evidence_positional
    if not evidence_name:
        parser.error("an evidence path is required")
    source = Path(evidence_name)
    output_name = args.output or args.out
    output = Path(output_name) if output_name else source.with_name(
        "offline_score.json"
    )
    evidence = json.loads(source.read_text(encoding="utf-8"))
    result = score_evidence(evidence)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    if args.sanity_output:
        sanity_path = Path(args.sanity_output)
        sanity_path.parent.mkdir(parents=True, exist_ok=True)
        sanity_path.write_text(
            json.dumps(run_shortcut_sanity(evidence), indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
    print(output)


if __name__ == "__main__":
    main()
