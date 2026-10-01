#!/usr/bin/env python3
"""Dedicated offline-only scorer for F90-XAUTO-03 evidence."""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


TASK_ID = "F90-XAUTO-03"
POLICY_ID = "simuverity-101-v1:f90-xauto-03:scoring"
# The title and public contract center on regulation under dynamic public
# profiles, so robustness and dynamic response carry more weight than generic
# finite-log quality.
WEIGHTS = {"A": 0.25, "Q": 0.10, "M": 0.30, "R": 0.20, "D": 0.15}


def clamp(v: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, float(v)))


def linear(v: float, good: float, fair: float, bad: float) -> float:
    if not math.isfinite(v):
        return 0.0
    if v <= good:
        return 100.0
    if v <= fair:
        return 100.0 - 25.0 * (v - good) / (fair - good)
    if v < bad:
        return 75.0 * (bad - v) / (bad - fair)
    return 0.0


def voltage_band_score(vmin: float, vmax: float) -> float:
    # 12-V automotive bus: a 12.0--15.0 V envelope remains usable; penalties
    # begin inside that envelope rather than granting a binary pass.
    under = max(0.0, 12.0 - vmin)
    over = max(0.0, vmax - 15.0)
    return linear(max(under, over), 0.0, 0.25, 1.5)


def tail_regulation_score(mean_v: float) -> float:
    # Nominal alternator charging voltage is near 14 V, but source-valid
    # temperature and controller variants need not be exactly 14.00 V.
    return linear(abs(mean_v - 14.0), 0.35, 0.70, 2.0)


def scenario_terms(row: dict[str, Any]) -> dict[str, float]:
    m = row.get("metrics") or {}
    finite = 100.0 if bool(m.get("all_finite")) else 0.0
    coverage = 100.0 if float(m.get("time_coverage_ratio", 0.0)) >= 0.99 else 0.0
    dynamic = 100.0 if float(m.get("load_current_std_a", 0.0)) > 0.02 else 0.0
    battery = voltage_band_score(float(m.get("battery_voltage_min_v", math.nan)),
                                 float(m.get("battery_voltage_max_v", math.nan)))
    load = voltage_band_score(float(m.get("load_voltage_min_v", math.nan)),
                              float(m.get("load_voltage_max_v", math.nan)))
    tail = tail_regulation_score(float(m.get("battery_voltage_tail_mean_v", math.nan)))
    recovery = linear(float(m.get("load_step_recovery_error_v", math.nan)), 0.20, 0.50, 1.75)
    return {
        "finite": finite,
        "coverage": coverage,
        "dynamic": dynamic,
        "battery": battery,
        "load": load,
        "tail": tail,
        "recovery": recovery,
    }


def mechanism_score(audit: dict[str, Any]) -> tuple[float, dict[str, float]]:
    names = [
        "alternator_voltage_feedback",
        "alternator_to_dc_bus",
        "battery_to_dc_bus",
        "load_to_dc_bus",
        "native_dynamic_load_profile",
        "measured_battery_voltage",
        "measured_load_current",
    ]
    terms = {name: 100.0 if bool(audit.get(name)) else 0.0 for name in names}
    # Any missing power-path edge or feedback loop makes a claimed closed-loop
    # automotive supply physically non-equivalent, so M itself is zero.
    critical = [
        "alternator_voltage_feedback", "alternator_to_dc_bus",
        "battery_to_dc_bus", "load_to_dc_bus",
    ]
    return (0.0 if any(terms[name] == 0.0 for name in critical)
            else sum(terms.values()) / len(terms)), terms


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = evidence.get("scenarios") or []
    valid = [row for row in rows if bool(row.get("valid"))]
    admission = {
        "G": int(bool(evidence.get("evidence_complete"))
                 and bool(evidence.get("load_pass"))
                 and bool(evidence.get("update_pass"))
                 and bool(evidence.get("compile_pass"))
                 and bool(evidence.get("nominal_smoke_pass"))
                 and len(rows) > 0 and len(rows) == len(valid)),
        "scenario_count": len(rows),
        "valid_scenario_count": len(valid),
    }
    if not admission["G"]:
        return {
            "schema": "simuverity.f90-xauto03-score.v1",
            "task_id": TASK_ID,
            "policy_id": POLICY_ID,
            "raw_score": 0.0,
            "groups": {key: 0.0 for key in WEIGHTS},
            "admission": admission,
            "failures": ["QUALIFICATION_GATE_FAILED"],
            "reason": "qualification gate failed",
        }

    quality = {str(row.get("id")): scenario_terms(row) for row in rows}
    nominal = quality.get("nominal_dynamic_load", next(iter(quality.values())))
    mechanism, mechanism_terms = mechanism_score(evidence.get("static_audit") or {})
    group_a = 0.42 * nominal["battery"] + 0.33 * nominal["load"] + 0.25 * nominal["tail"]
    group_q = min(0.45 * q["finite"] + 0.30 * q["coverage"] + 0.25 * q["dynamic"]
                  for q in quality.values())
    profile_causality = 100.0 if bool(
        evidence.get("scenario_diversity_pass")
    ) else 0.0
    # Half of M is the connected bus/feedback mechanism and half is evidence
    # that the declared public profiles actually enter that mechanism.  A
    # missing critical bus/feedback edge is an absent core model, not a partial
    # profile defect, and therefore leaves M at zero.
    group_m = (0.0 if mechanism <= 0.0 else
               0.50 * mechanism + 0.50 * profile_causality)
    nominal_robustness = (
        0.45 * nominal["battery"] + 0.35 * nominal["load"]
        + 0.20 * nominal["tail"]
    )
    voltage_robustness = min(
        0.45 * q["battery"] + 0.35 * q["load"] + 0.20 * q["tail"]
        for q in quality.values()
    )
    # Twenty percent of R is nominal bus usability.  The remaining eighty
    # percent requires both usable worst-profile voltage and evidence that the
    # declared profile actually changes the measured trajectory.
    group_r = (
        0.20 * nominal_robustness
        + 0.80 * voltage_robustness * profile_causality / 100.0
    )
    # Recovery is meaningful only if an actual changing accessory demand was
    # measured.  A prescribed constant-current trace cannot receive a high
    # dynamic score merely because its voltage happens to be flat.
    dynamic_recovery = 0.0 if min(q["dynamic"] for q in quality.values()) <= 0.0 else min(
        0.65 * q["recovery"] + 0.35 * q["dynamic"] for q in quality.values()
    )
    # D primarily measures an actual recovery transient; public-profile
    # causality supplies the remaining part and prevents an internally dynamic
    # but externally fixed model from receiving full dynamic credit.
    group_d = 0.70 * dynamic_recovery + 0.30 * profile_causality
    groups = {
        "A": clamp(group_a), "Q": clamp(group_q), "M": clamp(group_m),
        "R": clamp(group_r), "D": clamp(group_d),
    }
    raw = 0.0 if min(groups.values()) <= 0.0 else 100.0 * math.prod(
        (groups[key] / 100.0) ** WEIGHTS[key] for key in WEIGHTS
    )
    return {
        "schema": "simuverity.f90-xauto03-score.v1",
        "task_id": TASK_ID,
        "policy_id": POLICY_ID,
        "raw_score": raw,
        "groups": groups,
        "weights": WEIGHTS,
        "admission": admission,
        "diagnostics": {
            "scenario_diversity_pass": bool(
                evidence.get("scenario_diversity_pass")
            ),
            "public_input_profile_causality_utility": profile_causality,
            "nominal_robustness_before_profile_causality": nominal_robustness,
            "voltage_robustness_before_profile_causality": voltage_robustness,
            "dynamic_recovery_before_profile_causality": dynamic_recovery,
        },
        "failures": ([] if profile_causality > 0.0 else [
            "PUBLIC_INPUT_PROFILE_NOT_CAUSAL"
        ]),
        "scenario_quality": quality,
        "mechanism_terms": mechanism_terms,
        "aggregation": {
            "within_group": "dedicated weighted arithmetic means",
            "cross_scenario": "100_percent_minimum for Q/R/D",
            "across_groups": "weighted geometric mean",
        },
    }


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}
    missing = copy.deepcopy(evidence)
    missing["evidence_complete"] = False
    cases["missing_evidence"] = missing

    feedback = copy.deepcopy(evidence)
    feedback.setdefault("static_audit", {})["alternator_voltage_feedback"] = False
    cases["feedback_disconnected"] = feedback

    bus = copy.deepcopy(evidence)
    bus.setdefault("static_audit", {})["battery_to_dc_bus"] = False
    cases["battery_not_on_bus"] = bus

    prescribed = copy.deepcopy(evidence)
    for row in prescribed.get("scenarios", []):
        row.setdefault("metrics", {})["load_current_std_a"] = 0.0
    cases["prescribed_or_constant_load"] = prescribed

    fixed = copy.deepcopy(evidence)
    for row in fixed.get("scenarios", []):
        if row.get("id") != "nominal_dynamic_load":
            row.setdefault("metrics", {})["battery_voltage_min_v"] = 10.0
            row["metrics"]["load_voltage_min_v"] = 10.0
    cases["fixed_nominal_replay"] = fixed

    noncausal_profiles = copy.deepcopy(evidence)
    noncausal_profiles["scenario_diversity_pass"] = False
    cases["public_input_profile_not_causal"] = noncausal_profiles

    scores = {name: score_evidence(case)["raw_score"] for name, case in cases.items()}
    return {
        "policy_id": POLICY_ID,
        "cases": scores,
        "pass": all(score < 85.0 for score in scores.values()),
    }


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
