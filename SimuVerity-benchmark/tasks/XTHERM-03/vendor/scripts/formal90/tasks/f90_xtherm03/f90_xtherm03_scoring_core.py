#!/usr/bin/env python3
"""Pure offline scorer for F90-XTHERM-03 complete MSF evidence."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


POLICY_ID = 'simuverity-101-v1:f90-xtherm-03:scoring'
REQUIRED_SCENARIOS = (
    "nominal",
    "cold_feed_step",
    "hot_feed_step",
    "low_recycle_step",
    "high_recycle_step",
    "combined_hot_low_recycle",
)
GROUP_WEIGHTS = {"A": 0.18, "Q": 0.12, "M": 0.20, "C": 0.20, "R": 0.15, "D": 0.15}


def clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def low_good(value: float, full: float, zero: float) -> float:
    if zero <= full:
        raise ValueError("low-good thresholds must satisfy zero > full")
    return clip((zero - float(value)) / (zero - full))


def high_good(value: float, zero: float, full: float) -> float:
    if full <= zero:
        raise ValueError("high-good thresholds must satisfy full > zero")
    return clip((float(value) - zero) / (full - zero))


def band_good(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    value = float(value)
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return high_good(value, low_zero, low_full)
    return low_good(value, high_full, high_zero)


def weighted(items: list[tuple[float, float]]) -> float:
    denominator = sum(weight for _, weight in items)
    return sum(value * weight for value, weight in items) / denominator


def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row.get("id", "")): row for row in evidence.get("scenarios", [])}


def qualification(evidence: dict[str, Any], rows: dict[str, dict[str, Any]]) -> list[str]:
    failures: list[str] = []
    for key in ("evidence_complete", "load_pass", "update_pass", "compile_pass"):
        if not bool(evidence.get(key, False)):
            failures.append(f"{key}=false")
    missing = [name for name in REQUIRED_SCENARIOS if name not in rows]
    if missing:
        failures.append("missing required scenarios: " + ", ".join(missing))
    invalid = [
        name
        for name in REQUIRED_SCENARIOS
        if name in rows
        and (not bool(rows[name].get("simulation_pass")) or not bool(rows[name].get("valid")))
    ]
    if invalid:
        failures.append("invalid required scenarios: " + ", ".join(invalid))
    audit = evidence.get("static_audit", {})
    core = {
        "22_stage_process": int(audit.get("published_stage_count", 0)) >= 22,
        "three_input_six_output_plant": int(audit.get("plant_input_port_count", 0)) >= 3
        and int(audit.get("plant_output_port_count", 0)) >= 6,
        "two_feedback_controllers": int(audit.get("feedback_controller_count", 0)) >= 2,
        "temperature_feedback_connected": bool(audit.get("temperature_feedback_connected")),
        "distillate_feedback_connected": bool(audit.get("distillate_feedback_connected")),
        "source_dependencies_complete": bool(audit.get("source_dependencies_complete")),
        "simulink_path_selected": bool(audit.get("simulink_path_selected")),
    }
    failed_core = [name for name, passed in core.items() if not passed]
    if failed_core:
        failures.append("missing essential MSF mechanism: " + ", ".join(failed_core))
    return failures


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = scenario_map(evidence)
    failures = qualification(evidence, rows)
    if failures:
        return {
            "schema": "simuverity.offline-score-receipt.v1",
            "task_id": "F90-XTHERM-03",
            "policy_id": POLICY_ID,
            "valid": False,
            "G": 0.0,
            "groups": {name: 0.0 for name in GROUP_WEIGHTS},
            "group_weights": GROUP_WEIGHTS,
            "raw_total": 0.0,
            "total": 0.0,
            "failures": failures,
        }

    metrics = {name: rows[name]["metrics"] for name in REQUIRED_SCENARIOS}
    nominal = metrics["nominal"]
    disturbed = [metrics[name] for name in REQUIRED_SCENARIOS if name != "nominal"]
    audit = evidence["static_audit"]

    a_metrics = {
        "nominal_top_brine_tail_mae": low_good(nominal["top_brine_tail_mae_C"], 0.10, 2.0),
        "nominal_distillate_tail_mae": low_good(nominal["distillate_tail_mae_ton_per_min"], 0.005, 0.10),
        "nominal_brine_level": min(
            band_good(nominal["last_brine_level_min_m"], 0.0, 0.20, 0.90, 1.20),
            band_good(nominal["last_brine_level_max_m"], 0.0, 0.20, 0.90, 1.20),
        ),
        "nominal_distillate_level": min(
            band_good(nominal["last_distillate_level_min_m"], 0.0, 0.10, 0.70, 1.00),
            band_good(nominal["last_distillate_level_max_m"], 0.0, 0.10, 0.70, 1.00),
        ),
    }
    A = weighted([(a_metrics["nominal_top_brine_tail_mae"], 0.35),
                  (a_metrics["nominal_distillate_tail_mae"], 0.35),
                  (a_metrics["nominal_brine_level"], 0.15),
                  (a_metrics["nominal_distillate_level"], 0.15)])

    scenario_quality: dict[str, float] = {}
    for name, item in metrics.items():
        scenario_quality[name] = min(
            float(bool(item.get("all_finite", False))),
            band_good(item["last_brine_level_min_m"], 0.0, 0.15, 0.95, 1.25),
            band_good(item["last_brine_level_max_m"], 0.0, 0.15, 0.95, 1.25),
            band_good(item["last_distillate_level_min_m"], 0.0, 0.08, 0.80, 1.10),
            band_good(item["last_distillate_level_max_m"], 0.0, 0.08, 0.80, 1.10),
        )
    Q = min(scenario_quality.values())

    response_utilities = {
        "top_brine_dynamic_response": min(
            high_good(item["top_brine_temperature_span_C"], 0.5, 3.5) for item in disturbed
        ),
        "distillate_dynamic_response": min(
            high_good(item["distillate_flow_span_ton_per_min"], 0.10, 1.00) for item in disturbed
        ),
        "steam_actuation_response": min(
            high_good(item["steam_flow_span_kg_per_min"], 50.0, 200.0) for item in disturbed
        ),
    }
    structural = {
        "stage_count": high_good(audit["published_stage_count"], 8, 22),
        "plant_io": float(audit["plant_input_port_count"] >= 3 and audit["plant_output_port_count"] >= 6),
        "native_process": float(str(audit.get("native_msf_sfunction", "")) == "MSFprocess"),
        "dependencies": float(bool(audit["source_dependencies_complete"])),
    }
    M = weighted([(sum(structural.values()) / len(structural), 0.70),
                  (sum(response_utilities.values()) / len(response_utilities), 0.30)])

    worst_distillate_tail = max(item["distillate_tail_mae_ton_per_min"] for item in metrics.values())
    c_metrics = {
        "two_controllers": float(audit["feedback_controller_count"] >= 2),
        "both_feedback_paths": float(audit["temperature_feedback_connected"] and audit["distillate_feedback_connected"]),
        "nominal_regulation": min(a_metrics["nominal_top_brine_tail_mae"], a_metrics["nominal_distillate_tail_mae"]),
        "disturbance_rejection": low_good(worst_distillate_tail, 0.01, 0.10),
        "actuation_is_dynamic": response_utilities["steam_actuation_response"],
    }
    C = weighted([(value, 1.0) for value in c_metrics.values()])

    worst_top_tail = max(item["top_brine_tail_mae_C"] for item in metrics.values())
    r_metrics = {
        "worst_top_brine_tail_error": low_good(worst_top_tail, 4.0, 8.0),
        "worst_distillate_tail_error": low_good(worst_distillate_tail, 0.01, 0.10),
        "worst_physical_quality": Q,
    }
    R = weighted([(r_metrics["worst_top_brine_tail_error"], 0.45),
                  (r_metrics["worst_distillate_tail_error"], 0.25),
                  (r_metrics["worst_physical_quality"], 0.30)])

    D = weighted([(response_utilities["top_brine_dynamic_response"], 0.35),
                  (response_utilities["distillate_dynamic_response"], 0.30),
                  (response_utilities["steam_actuation_response"], 0.35)])

    groups = {"A": A, "Q": Q, "M": M, "C": C, "R": R, "D": D}
    raw = 100.0 * math.prod(groups[name] ** GROUP_WEIGHTS[name] for name in GROUP_WEIGHTS)
    return {
        "schema": "simuverity.offline-score-receipt.v1",
        "task_id": "F90-XTHERM-03",
        "policy_id": POLICY_ID,
        "valid": True,
        "G": 1.0,
        "groups": groups,
        "group_weights": GROUP_WEIGHTS,
        "aggregation": "G*100*A^0.18*Q^0.12*M^0.20*C^0.20*R^0.15*D^0.15; Q/R and dynamic-response terms use the worst required official scenario",
        "raw_total": raw,
        "total": raw,
        "per_metric": {"A": a_metrics, "Q_by_scenario": scenario_quality, "M_structure": structural,
                       "M_response": response_utilities, "C": c_metrics, "R": r_metrics},
        "per_scenario": {name: metrics[name] for name in REQUIRED_SCENARIOS},
        "failures": [],
    }


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    missing = copy.deepcopy(evidence)
    missing["scenarios"] = missing.get("scenarios", [])[:-1]
    no_feedback = copy.deepcopy(evidence)
    no_feedback["static_audit"]["feedback_controller_count"] = 0
    no_feedback["static_audit"]["temperature_feedback_connected"] = False
    insensitive = copy.deepcopy(evidence)
    for row in insensitive.get("scenarios", []):
        if row.get("id") != "nominal":
            row["metrics"]["top_brine_temperature_span_C"] = 0.0
            row["metrics"]["distillate_flow_span_ton_per_min"] = 0.0
            row["metrics"]["steam_flow_span_kg_per_min"] = 0.0
    scores = {
        "missing_required_scenario": score_evidence(missing)["total"],
        "missing_feedback_core": score_evidence(no_feedback)["total"],
        "input_insensitive_response": score_evidence(insensitive)["total"],
    }
    return {"pass": scores["missing_required_scenario"] == 0.0
            and scores["missing_feedback_core"] == 0.0
            and scores["input_insensitive_response"] < 60.0,
            "scores": scores}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence")
    parser.add_argument("--output", required=True)
    parser.add_argument("--shortcut-output")
    args = parser.parse_args()
    evidence = json.loads(Path(args.evidence).read_text(encoding="utf-8"))
    result = score_evidence(evidence)
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    if args.shortcut_output:
        sanity = shortcut_sanity(evidence)
        Path(args.shortcut_output).write_text(json.dumps(sanity, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
