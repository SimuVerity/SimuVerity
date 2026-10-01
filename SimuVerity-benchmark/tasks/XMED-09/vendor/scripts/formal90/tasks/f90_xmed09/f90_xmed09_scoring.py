#!/usr/bin/env python3
"""Pure offline scorer for F90-XMED-09 fixed cardiovascular/LVAD evidence."""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


POLICY_ID = 'simuverity-101-v1:f90-xmed-09:scoring'
SCENARIOS = (
    "nominal_impaired_sliding", "healthy_assisted", "impaired_unassisted",
    "pid_assist", "baroreflex_disabled", "fixed_resistance_elastance",
)
WEIGHTS = {"A": 0.20, "Q": 0.10, "M": 0.25, "C": 0.20, "R": 0.15, "D": 0.10}


def clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def low_good(value: float, full: float, zero: float) -> float:
    return clip((zero - float(value)) / (zero - full))


def high_good(value: float, zero: float, full: float) -> float:
    return clip((float(value) - zero) / (full - zero))


def band_good(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    value = float(value)
    if low_full <= value <= high_full:
        return 1.0
    return high_good(value, low_zero, low_full) if value < low_full else low_good(value, high_full, high_zero)


def mean(items: list[tuple[float, float]]) -> float:
    return sum(value * weight for value, weight in items) / sum(weight for _, weight in items)


def rows_by_id(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row.get("id", "")): row for row in evidence.get("scenarios", [])}


def qualification(evidence: dict[str, Any], rows: dict[str, dict[str, Any]]) -> list[str]:
    failures: list[str] = []
    for key in ("evidence_complete", "load_pass", "update_pass", "compile_pass"):
        if not evidence.get(key): failures.append(f"{key}=false")
    missing = [name for name in SCENARIOS if name not in rows]
    if missing: failures.append("missing required scenarios: " + ", ".join(missing))
    invalid = [name for name in SCENARIOS if name in rows and not (rows[name].get("simulation_pass") and rows[name].get("valid"))]
    if invalid: failures.append("invalid required scenarios: " + ", ".join(invalid))
    audit = evidence.get("static_audit", {})
    core = {
        "heart_lvad": audit.get("heart_lvad_present"),
        "control_processing": audit.get("control_processing_present"),
        "controller": audit.get("controller_present"),
        "baroreflex": audit.get("baroreflex_present"),
        "measured_pressure": audit.get("measured_pressure_tag_present"),
        "assist_pressure": audit.get("assist_pressure_tag_present"),
        "control_effort": audit.get("control_effort_tag_present"),
        "initializer": audit.get("initializer_present"),
    }
    failed_core = [name for name, passed in core.items() if not passed]
    if failed_core: failures.append("missing essential closed-loop mechanism: " + ", ".join(failed_core))
    if int(audit.get("dynamic_block_count", 0)) < 20:
        failures.append("insufficient dynamic cardiovascular state structure")
    return failures


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = rows_by_id(evidence)
    failures = qualification(evidence, rows)
    if failures:
        return {"schema": "simuverity.offline-score-receipt.v1", "task_id": "F90-XMED-09",
                "policy_id": POLICY_ID, "valid": False, "G": 0.0,
                "groups": {name: 0.0 for name in WEIGHTS}, "group_weights": WEIGHTS,
                "raw_total": 0.0, "total": 0.0, "failures": failures}

    metrics = {name: rows[name]["metrics"] for name in SCENARIOS}
    nominal = metrics["nominal_impaired_sliding"]
    connected = [metrics[name] for name in SCENARIOS if name != "impaired_unassisted"]
    audit = evidence["static_audit"]

    a_metrics = {
        "nominal_pressure_target": low_good(nominal["systemic_target_tail_mae_mmHg"], 5.0, 15.0),
        "nominal_mean_pressure": band_good(nominal["systemic_pressure_tail_mean_mmHg"], 45.0, 60.0, 95.0, 120.0),
        "nominal_pulsatility": band_good(nominal["systemic_pressure_tail_pulsatility_mmHg"], 2.0, 15.0, 45.0, 70.0),
        "nominal_lv_pressure": band_good(nominal["left_ventricular_pressure_max_mmHg"], 45.0, 70.0, 130.0, 180.0),
        "nominal_lv_volume": min(
            band_good(nominal["left_ventricular_volume_min_mL"], -2.0, 0.0, 25.0, 45.0),
            band_good(nominal["left_ventricular_volume_max_mL"], 5.0, 12.0, 45.0, 70.0)),
    }
    A = mean([(a_metrics["nominal_pressure_target"], .30), (a_metrics["nominal_mean_pressure"], .20),
              (a_metrics["nominal_pulsatility"], .20), (a_metrics["nominal_lv_pressure"], .15),
              (a_metrics["nominal_lv_volume"], .15)])

    quality_by_scenario: dict[str, float] = {}
    for name, item in metrics.items():
        quality_by_scenario[name] = min(
            float(bool(item.get("all_finite"))),
            band_good(item["systemic_pressure_tail_min_mmHg"], 20.0, 45.0, 110.0, 150.0),
            band_good(item["systemic_pressure_tail_max_mmHg"], 30.0, 55.0, 130.0, 180.0),
            band_good(item["left_ventricular_volume_min_mL"], -5.0, 0.0, 35.0, 55.0),
            band_good(item["left_ventricular_volume_max_mL"], 0.0, 8.0, 55.0, 80.0),
            band_good(item["right_ventricular_volume_min_mL"], 0.0, 5.0, 45.0, 70.0),
            band_good(item["right_ventricular_volume_max_mL"], 5.0, 10.0, 60.0, 90.0),
        )
    Q = min(quality_by_scenario.values())

    hemo_signatures = {round(float(item["hemodynamic_summary"]), 4) for item in metrics.values()}
    assist_signatures = {round(float(item["assist_summary"]), 4) for item in metrics.values()}
    mechanism_structure = mean([
        (high_good(audit["recursive_block_count"], 100, 700), .20),
        (high_good(audit["subsystem_count"], 10, 45), .15),
        (high_good(audit["dynamic_block_count"], 20, 60), .20),
        (float(audit["heart_lvad_present"] and audit["controller_present"]), .20),
        (float(audit["baroreflex_present"] and audit["measured_pressure_tag_present"]), .25),
    ])
    mechanism_response = min(high_good(len(hemo_signatures), 1, 5), high_good(len(assist_signatures), 1, 5))
    M = math.sqrt(mechanism_structure * mechanism_response)

    c_metrics = {
        "measured_pressure_feedback": float(audit["measured_pressure_tag_present"] and audit["control_effort_tag_present"]),
        "nominal_pressure_regulation": low_good(nominal["systemic_target_tail_mae_mmHg"], 5.0, 15.0),
        "connected_assist_is_dynamic": min(high_good(item["assist_pressure_tail_span_mmHg"], 2.0, 12.0) for item in connected),
        "controller_law_changes_effort": high_good(abs(metrics["pid_assist"]["controller_effort_tail_rms"] - nominal["controller_effort_tail_rms"]), 50.0, 400.0),
        "disconnect_changes_hemodynamics": high_good(abs(metrics["impaired_unassisted"]["systemic_pressure_tail_mean_mmHg"] - nominal["systemic_pressure_tail_mean_mmHg"]), 2.0, 7.0),
    }
    C = mean([(value, 1.0) for value in c_metrics.values()])

    worst_target = max(item["systemic_target_tail_mae_mmHg"] for item in metrics.values())
    worst_min_pressure = min(item["systemic_pressure_tail_min_mmHg"] for item in metrics.values())
    worst_max_pressure = max(item["systemic_pressure_tail_max_mmHg"] for item in metrics.values())
    r_metrics = {
        "worst_target_error": low_good(worst_target, 7.0, 15.0),
        "minimum_pressure_boundary": high_good(worst_min_pressure, 35.0, 55.0),
        "maximum_pressure_boundary": low_good(worst_max_pressure, 115.0, 150.0),
        "worst_state_quality": Q,
    }
    R = mean([(r_metrics["worst_target_error"], .30), (r_metrics["minimum_pressure_boundary"], .25),
              (r_metrics["maximum_pressure_boundary"], .20), (r_metrics["worst_state_quality"], .25)])

    d_metrics = {
        "worst_pulsatility": min(band_good(item["systemic_pressure_tail_pulsatility_mmHg"], 2.0, 15.0, 45.0, 70.0) for item in metrics.values()),
        "worst_lv_volume_excursion": min(high_good(item["left_ventricular_volume_excursion_mL"], 2.0, 8.0) for item in metrics.values()),
        "connected_assist_excursion": min(high_good(item["assist_pressure_tail_span_mmHg"], 2.0, 12.0) for item in connected),
        "controller_effort_changes": high_good(max(item["controller_effort_tail_rms"] for item in metrics.values()) - min(item["controller_effort_tail_rms"] for item in metrics.values()), 100.0, 2000.0),
    }
    D = mean([(value, 1.0) for value in d_metrics.values()])

    groups = {"A": A, "Q": Q, "M": M, "C": C, "R": R, "D": D}
    raw = 100.0 * math.prod(groups[name] ** WEIGHTS[name] for name in WEIGHTS)
    return {"schema": "simuverity.offline-score-receipt.v1", "task_id": "F90-XMED-09",
            "policy_id": POLICY_ID, "valid": True, "G": 1.0, "groups": groups,
            "group_weights": WEIGHTS,
            "aggregation": "G*100*A^0.20*Q^0.10*M^0.25*C^0.20*R^0.15*D^0.10; Q/R and dynamic terms use worst required scenario",
            "raw_total": raw, "total": raw,
            "per_metric": {"A": a_metrics, "Q_by_scenario": quality_by_scenario,
                           "M": {"structure": mechanism_structure, "response": mechanism_response,
                                 "hemodynamic_signature_count": len(hemo_signatures), "assist_signature_count": len(assist_signatures)},
                           "C": c_metrics, "R": r_metrics, "D": d_metrics},
            "per_scenario": metrics, "failures": []}


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    missing = copy.deepcopy(evidence); missing["scenarios"] = missing.get("scenarios", [])[:-1]
    no_controller = copy.deepcopy(evidence); no_controller["static_audit"]["controller_present"] = False
    insensitive = copy.deepcopy(evidence)
    base = insensitive["scenarios"][0]["metrics"]
    for row in insensitive["scenarios"]:
        row["metrics"] = copy.deepcopy(base)
    scores = {"missing_required_scenario": score_evidence(missing)["total"],
              "missing_controller": score_evidence(no_controller)["total"],
              "input_insensitive_modes": score_evidence(insensitive)["total"]}
    return {"pass": scores["missing_required_scenario"] == 0 and scores["missing_controller"] == 0
            and scores["input_insensitive_modes"] == 0, "scores": scores}


def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("evidence"); parser.add_argument("--output", required=True); parser.add_argument("--shortcut-output")
    args = parser.parse_args(); evidence = json.loads(Path(args.evidence).read_text(encoding="utf-8"))
    Path(args.output).write_text(json.dumps(score_evidence(evidence), indent=2) + "\n", encoding="utf-8")
    if args.shortcut_output:
        Path(args.shortcut_output).write_text(json.dumps(shortcut_sanity(evidence), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__": main()
