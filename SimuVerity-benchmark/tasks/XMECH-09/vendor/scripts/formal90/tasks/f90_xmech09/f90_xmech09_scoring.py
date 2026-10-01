#!/usr/bin/env python3
"""Offline-only dedicated scorer for F90-XMECH-09 Backhoe evidence.

The scorer assigns low, decreasing utility to poor-but-responsive tracking while keeping
zero for missing/nonresponsive channels and a near-floor utility for gross
tracking mismatch.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


WEIGHTS = {"A": 0.30, "Q": 0.15, "M": 0.25, "R": 0.15, "D": 0.15}
POLICY_ID = 'simuverity-101-v1:f90-xmech-09:scoring'
TRACKING_BREAKPOINTS = (
    (0.004, 100.0),
    (0.008, 75.0),
    (0.030, 25.0),
    (0.100, 10.0),
    (0.500, 1.0),
)
RESPONSIVE_SPAN_FRACTION = 0.02
RESPONSIVE_ABSOLUTE_SPAN_DEG = 0.1
COMMAND_STD_MINIMUM = 1.0e-6


def clamp(value: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, float(value)))


def bool_score(value: Any) -> float:
    return 100.0 if bool(value) else 0.0


def response_present(
    reference_span: list[float],
    state_span: list[float],
    command_std: list[float],
) -> bool:
    """Require measurable response and an active command on every axis.

    The two-percent span test is only a response-presence floor.  It does not
    grant tracking quality: NRMSE supplies that penalty separately.
    """
    if len(reference_span) != 5 or len(state_span) != 5 or len(command_std) != 5:
        return False
    if not all(math.isfinite(x) for x in reference_span + state_span + command_std):
        return False
    if not all(r > 0.5 for r in reference_span):
        return False
    if not all(c > COMMAND_STD_MINIMUM for c in command_std):
        return False
    return all(
        s >= max(RESPONSIVE_ABSOLUTE_SPAN_DEG, RESPONSIVE_SPAN_FRACTION * r)
        for r, s in zip(reference_span, state_span)
    )


def tracking_score(value: float, responsive: bool) -> float:
    """Piecewise utility for precision through gross-but-real response.

    Three percent is the boundary between degraded and poor precision rather than a no-response
    gate.  Ten percent marks severe tracking error, and 50% marks gross
    mismatch.  A verified five-axis response retains only the one-point floor;
    absent response remains exactly zero.
    """
    if not responsive or not math.isfinite(value) or value < 0.0:
        return 0.0
    previous_x, previous_y = 0.0, 100.0
    for boundary_x, boundary_y in TRACKING_BREAKPOINTS:
        if value <= boundary_x:
            if boundary_x == previous_x:
                return boundary_y
            alpha = (value - previous_x) / (boundary_x - previous_x)
            return previous_y + alpha * (boundary_y - previous_y)
        previous_x, previous_y = boundary_x, boundary_y
    return 1.0


def scenario_quality(row: dict[str, Any]) -> dict[str, Any]:
    metrics = row.get("metrics") or {}
    worst = float(metrics.get("worst_tracking_nrmse", math.inf))
    tail = float(metrics.get("tail_tracking_nrmse", math.inf))
    reference_span = [float(x) for x in metrics.get("reference_excursion_deg", [])]
    state_span = [float(x) for x in metrics.get("state_excursion_deg", [])]
    command_std = [float(x) for x in metrics.get("hydraulic_command_std", [])]
    coverage = 100.0
    if len(reference_span) != 5 or len(state_span) != 5:
        coverage = 0.0
    elif any(r <= 0.5 or s <= 0.1 for r, s in zip(reference_span, state_span)):
        coverage = 0.0
    command = 100.0 if len(command_std) == 5 and all(x > COMMAND_STD_MINIMUM for x in command_std) else 0.0
    responsive = response_present(reference_span, state_span, command_std)
    finite = bool_score(metrics.get("all_finite", False))
    return {
        "tracking": tracking_score(worst, responsive),
        "tail": tracking_score(tail, responsive),
        "coverage": coverage,
        "command": command,
        "finite": finite,
        "response_present": responsive,
        "worst_tracking_nrmse": worst,
        "tail_tracking_nrmse": tail,
    }


def mechanism_score(audit: dict[str, Any], operating_command: float) -> tuple[float, dict[str, float]]:
    terms = {
        "reference_to_controller": bool_score(audit.get("reference_to_controller")),
        "feedback_to_controller": bool_score(audit.get("feedback_to_controller")),
        "controller_to_plant": bool_score(audit.get("controller_to_plant")),
        "physical_hydraulic_path": bool_score(audit.get("physical_hydraulic_path")),
        "closed_loop_causal_path": bool_score(audit.get("closed_loop_causal_path")),
        "five_reference_channels": bool_score(audit.get("five_reference_channels")),
        "five_measurement_channels": bool_score(audit.get("five_measurement_channels")),
        "five_hydraulic_commands_vary": operating_command,
    }
    score = sum(terms.values()) / len(terms)
    if min(terms[k] for k in (
        "reference_to_controller", "feedback_to_controller", "controller_to_plant",
        "physical_hydraulic_path", "closed_loop_causal_path",
        "five_hydraulic_commands_vary"
    )) == 0:
        score = 0.0
    return score, terms


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = evidence.get("scenarios") or []
    valid = [r for r in rows if bool(r.get("valid"))]
    admission = {
        "G": int(bool(evidence.get("evidence_complete"))
                 and bool(evidence.get("load_pass"))
                 and bool(evidence.get("update_pass"))
                 and bool(evidence.get("compile_pass"))
                 and bool(evidence.get("nominal_smoke_pass"))
                 and len(rows) >= 1 and len(valid) == len(rows)),
        "scenario_count": len(rows),
        "valid_scenario_count": len(valid),
    }
    if not admission["G"]:
        return {
            "schema": "simuverity.f90-xmech09-score.v1",
            "task_id": "F90-XMECH-09",
            "policy_id": POLICY_ID,
            "raw_score": 0.0,
            "groups": {k: 0.0 for k in WEIGHTS},
            "weights": WEIGHTS,
            "applicable_groups": ["G", *WEIGHTS],
            "non_applicable_groups": ["C"],
            "admission": admission,
            "reason": "qualification gate failed",
        }

    quality = {str(r.get("id")): scenario_quality(r) for r in rows}
    nominal_id = "nominal" if "nominal" in quality else next(iter(quality))
    nominal = quality[nominal_id]
    audit = evidence.get("static_audit") or {}
    operating_command = min(q["command"] for q in quality.values())
    mechanism, mechanism_terms = mechanism_score(audit, operating_command)

    group_a = 0.70 * nominal["tracking"] + 0.20 * nominal["tail"] + 0.10 * nominal["coverage"]
    group_q = 0.45 * min(q["finite"] for q in quality.values()) + \
              0.30 * min(q["coverage"] for q in quality.values()) + \
              0.25 * min(q["command"] for q in quality.values())
    group_m = mechanism
    group_r = min(q["tracking"] for q in quality.values())
    dynamic_ids = [name for name in quality if name != nominal_id]
    dynamic = [quality[name] for name in dynamic_ids] or [nominal]
    group_d = 0.70 * min(q["tail"] for q in dynamic) + \
              0.30 * min(q["command"] for q in dynamic)
    groups = {"A": clamp(group_a), "Q": clamp(group_q), "M": clamp(group_m),
              "R": clamp(group_r), "D": clamp(group_d)}
    if min(groups.values()) <= 0:
        raw = 0.0
    else:
        raw = 100.0 * math.prod((groups[key] / 100.0) ** WEIGHTS[key] for key in WEIGHTS)
    return {
        "schema": "simuverity.f90-xmech09-score.v1",
        "task_id": "F90-XMECH-09",
        "policy_id": POLICY_ID,
        "raw_score": raw,
        "groups": groups,
        "weights": WEIGHTS,
        "applicable_groups": ["G", *WEIGHTS],
        "non_applicable_groups": ["C"],
        "admission": admission,
        "scenario_quality": quality,
        "mechanism_terms": mechanism_terms,
        "tracking_utility_contract": {
            "breakpoints_nrmse_to_utility": [list(item) for item in TRACKING_BREAKPOINTS],
            "verified_response_floor": 1.0,
            "no_response_utility": 0.0,
            "responsive_span_fraction": RESPONSIVE_SPAN_FRACTION,
            "responsive_absolute_span_deg": RESPONSIVE_ABSOLUTE_SPAN_DEG,
            "command_std_minimum": COMMAND_STD_MINIMUM,
        },
        "aggregation": {
            "within_group": "weighted arithmetic means",
            "cross_scenario": "100 percent minimum for R and D",
            "across_groups": "weighted geometric mean",
        },
    }


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}
    base = copy.deepcopy(evidence)
    cases["missing_evidence"] = {**copy.deepcopy(base), "evidence_complete": False}

    broken_feedback = copy.deepcopy(base)
    broken_feedback.setdefault("static_audit", {})["feedback_to_controller"] = False
    broken_feedback["static_audit"]["closed_loop_causal_path"] = False
    cases["feedback_disconnected"] = broken_feedback

    copied = copy.deepcopy(base)
    copied.setdefault("static_audit", {})["physical_hydraulic_path"] = False
    copied["static_audit"]["controller_to_plant"] = False
    cases["prescribed_or_copied_motion"] = copied

    constant_command = copy.deepcopy(base)
    for row in constant_command.get("scenarios", []):
        row.setdefault("metrics", {})["hydraulic_command_std"] = [0.0] * 5
    cases["constant_hydraulic_command"] = constant_command

    no_response = copy.deepcopy(base)
    for row in no_response.get("scenarios", []):
        row.setdefault("metrics", {})["state_excursion_deg"] = [0.0] * 5
    cases["no_measured_joint_response"] = no_response

    fixed_trajectory = copy.deepcopy(base)
    for row in fixed_trajectory.get("scenarios", []):
        if row.get("id") != "nominal":
            row.setdefault("metrics", {})["worst_tracking_nrmse"] = 0.30
            row["metrics"]["tail_tracking_nrmse"] = 0.30
    cases["fixed_nominal_replayed"] = fixed_trajectory

    results = {name: score_evidence(value)["raw_score"] for name, value in cases.items()}
    return {"cases": results, "pass": all(score < 85.0 for score in results.values())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--shortcut-sanity", action="store_true")
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score_evidence(evidence)
    if args.shortcut_sanity:
        result["shortcut_sanity"] = shortcut_sanity(evidence)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
