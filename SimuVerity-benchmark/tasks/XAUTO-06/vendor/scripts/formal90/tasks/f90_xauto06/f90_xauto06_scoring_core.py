"""Dedicated offline scorer for F90-XAUTO-06 fixed evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


POLICY_ID = "simuverity-101-v1:f90-xauto-06:scoring"


def clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def good_high(value: float, zero: float, full: float) -> float:
    return clip((value - zero) / (full - zero))


def good_low(value: float, full: float, zero: float) -> float:
    return clip((zero - value) / (zero - full))


def weighted_mean(items: list[tuple[float, float]]) -> float:
    return sum(value * weight for value, weight in items) / sum(weight for _, weight in items)


def score(evidence: dict) -> dict:
    rows = [row for row in evidence.get("scenarios", []) if row.get("valid")]
    if not (
        evidence.get("evidence_complete")
        and evidence.get("load_pass")
        and evidence.get("update_pass")
        and evidence.get("compile_pass")
        and evidence.get("nominal_smoke_pass")
        and len(rows) == 5
    ):
        return {
            "policy_id": POLICY_ID,
            "valid": False,
            "G": 0.0,
            "groups": {key: 0.0 for key in "AQMRD"},
            "raw_total": 0.0,
            "total": 0.0,
            "failures": ["qualification gate or complete official evidence is missing"],
        }

    by_id = {row["id"]: row for row in rows}
    nominal = by_id["nominal"]["metrics"]
    metrics = [row["metrics"] for row in rows]
    audit = evidence.get("static_audit", {})

    worst_rmse = max(row["speed_rmse_kph"] for row in metrics)
    worst_peak_error = max(row["speed_peak_abs_error_kph"] for row in metrics)
    worst_tracking_fraction = min(row["tracking_fraction_within_5kph"] for row in metrics)
    min_soc = min(row["battery_soc_min_pct"] for row in metrics)
    max_soc = max(row["battery_soc_max_pct"] for row in metrics)
    worst_final_error = max(row["final_window_abs_error_kph"] for row in metrics)
    min_reference_excursion = min(row["speed_reference_excursion_kph"] for row in metrics)
    min_power_activity = min(row["power_split_activity_fraction"] for row in metrics)
    # RegenCommand is the only public regenerative-braking activity contract.
    # BrakeCommand is not declared to be a total braking request, so no
    # BrakeCommand/RegenCommand overlap is assumed here.
    min_regen_activity = min(row["regen_active_fraction"] for row in metrics)
    # A positive task-level core connectivity check can substantiate the
    # planetary and feedback paths when every required component is present.
    core_semantic_support = bool(audit.get("core_powertrain_connected")) and all([
        bool(audit.get("engine_present")),
        bool(audit.get("mg1_present")),
        bool(audit.get("mg2_present")),
        bool(audit.get("battery_present")),
        bool(audit.get("dcdc_present")),
        bool(audit.get("vehicle_present")),
    ])
    planetary_evidence = bool(audit.get("planetary_power_split_present")) or core_semantic_support
    feedback_evidence = bool(audit.get("feedback_path_connected")) or core_semantic_support
    mechanism_flags = [
        bool(audit.get("engine_present")),
        bool(audit.get("mg1_present")),
        bool(audit.get("mg2_present")),
        bool(audit.get("battery_present")),
        bool(audit.get("dcdc_present")),
        planetary_evidence,
        bool(audit.get("vehicle_present")),
        feedback_evidence,
    ]
    m = 0.65 * (sum(mechanism_flags) / len(mechanism_flags)) + 0.35 * good_high(min_power_activity, 0.04, 0.30)

    # A evaluates the nominal control objective. Q keeps electrically and
    # mechanically plausible operation separate from A. R and D are strict
    # worst-official-case measures, so a good nominal trace cannot hide a
    # poor uphill/low-SOC or deceleration result.
    a = weighted_mean([
        (good_low(nominal["speed_rmse_kph"], 0.75, 8.0), 0.50),
        (good_low(nominal["speed_peak_abs_error_kph"], 2.0, 20.0), 0.25),
        (good_high(nominal["tracking_fraction_within_5kph"], 0.65, 0.98), 0.25),
    ])
    q = weighted_mean([
        (good_high(min_soc, 35.0, 48.0), 0.40),
        (good_low(max_soc, 80.0, 98.0), 0.20),
        (good_high(min_reference_excursion, 15.0, 35.0), 0.15),
        (good_high(min_power_activity, 0.04, 0.30), 0.25),
    ])
    r = weighted_mean([
        (good_low(worst_rmse, 1.5, 12.0), 0.40),
        (good_low(worst_peak_error, 4.0, 28.0), 0.25),
        (good_high(worst_tracking_fraction, 0.50, 0.94), 0.20),
        (good_high(min_soc, 30.0, 47.0), 0.15),
    ])
    final_recovery_utility = good_low(worst_final_error, 1.5, 15.0)
    regen_activity_utility = good_high(min_regen_activity, 0.02, 0.15)
    # Both recovery and regenerative response are required dynamic
    # capabilities.  Use their bottleneck so perfect final tracking cannot
    # dilute weak worst-scenario regenerative activity.
    d = min(final_recovery_utility, regen_activity_utility)
    groups = {"A": a, "Q": q, "M": m, "R": r, "D": d}
    # Avoid awarding the same speed-tracking behavior through both A and D:
    # A remains the primary nominal objective, while D carries the explicitly
    # required regenerative and recovery behavior.
    raw = 100.0 * (a ** 0.20) * (q ** 0.10) * (m ** 0.30) * (r ** 0.10) * (d ** 0.30)
    total = raw
    return {
        "policy_id": POLICY_ID,
        "valid": True,
        "G": 1.0,
        "groups": groups,
        "group_weights": {"A": 0.20, "Q": 0.10, "M": 0.30, "R": 0.10, "D": 0.30},
        "aggregation": "G*100*A^0.20*Q^0.10*M^0.30*R^0.10*D^0.30; critical R/D measures use the worst valid official scenario; D=min(final recovery, regenerative activity)",
        "raw_total": raw,
        "total": total,
        "headline_metrics": {
            "nominal_speed_rmse_kph": nominal["speed_rmse_kph"],
            "worst_speed_rmse_kph": worst_rmse,
            "worst_peak_abs_error_kph": worst_peak_error,
            "minimum_battery_soc_pct": min_soc,
            "minimum_power_split_activity_fraction": min_power_activity,
            "minimum_regen_activity_fraction": min_regen_activity,
            "worst_final_window_abs_error_kph": worst_final_error,
            "regenerative_activity_utility": regen_activity_utility,
            "final_recovery_utility": final_recovery_utility,
            "core_semantic_support": core_semantic_support,
        },
        "failures": (
            ["REGENERATIVE_BRAKING_ACTIVITY_MISSING"]
            if missing_regen_activity
            else []
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    evidence = json.loads(Path(args.evidence).read_text(encoding="utf-8"))
    Path(args.output).write_text(json.dumps(score(evidence), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
