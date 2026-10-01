"""Dedicated offline scorer for F90-XFLUID-09 fixed evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


POLICY_ID = 'simuverity-101-v1:f90-xfluid-09:scoring'


def clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def good_high(value: float, zero: float, full: float) -> float:
    if full <= zero:
        raise ValueError("invalid high-is-good thresholds")
    return clip((value - zero) / (full - zero))


def good_low(value: float, full: float, zero: float) -> float:
    if zero <= full:
        raise ValueError("invalid low-is-good thresholds")
    return clip((zero - value) / (zero - full))


def mean(items: list[tuple[float, float]]) -> float:
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
    mechanism_flags = [
        bool(audit.get("low_pressure_storage_present")),
        bool(audit.get("multistage_compression_present")),
        bool(audit.get("cascade_buffer_present")),
        bool(audit.get("reduction_valve_present")),
        bool(audit.get("precooler_present")),
        bool(audit.get("vehicle_tank_present")),
        bool(audit.get("feedback_and_supervision_present")),
    ]
    m = sum(mechanism_flags) / len(mechanism_flags)

    worst_final_pressure = min(row["vehicle_final_pressure_bar"] for row in metrics)
    worst_mass = min(row["delivered_mass_kg"] for row in metrics)
    worst_peak_temperature = max(row["vehicle_peak_temperature_C"] for row in metrics)
    worst_pressure_rise = min(row["vehicle_pressure_rise_bar"] for row in metrics)
    min_valve_flow_correlation = min(abs(row["valve_flow_correlation"]) for row in metrics)
    min_pressure_flow_correlation = min(abs(row["pressure_flow_correlation"]) for row in metrics)
    min_buffer_excursion = min(row["buffer_pressure_excursion_bar"] for row in metrics)
    worst_backtrack_fraction = max(row["pressure_backtrack_fraction"] for row in metrics)

    # This is a 700--750 bar class fill. Scores remain continuous: 95 C is
    # still below a gross-failure temperature but is not premium thermal
    # quality, and a warm-boundary fill below 750 bar receives partial R
    # credit rather than being silently treated as a perfect completion.
    # Critical Q/R/D quantities use the literal worst valid official case.
    a = mean([
        (good_high(nominal["vehicle_final_pressure_bar"], 690.0, 750.0), 0.55),
        (good_high(nominal["delivered_mass_kg"], 2.0, 5.0), 0.20),
        (good_high(nominal["vehicle_pressure_rise_bar"], 400.0, 650.0), 0.25),
    ])
    q = mean([
        (good_low(worst_peak_temperature, 65.0, 95.0), 0.45),
        (good_low(worst_backtrack_fraction, 0.0001, 0.02), 0.25),
        (good_high(min_buffer_excursion, 100.0, 750.0), 0.30),
    ])
    r = mean([
        (good_high(worst_final_pressure, 650.0, 750.0), 0.45),
        (good_high(worst_mass, 1.0, 5.0), 0.20),
        (good_low(worst_peak_temperature, 75.0, 105.0), 0.20),
        (good_high(worst_pressure_rise, 250.0, 650.0), 0.15),
    ])
    d = mean([
        (good_high(min_valve_flow_correlation, 0.05, 0.60), 0.40),
        (good_high(min_pressure_flow_correlation, 0.10, 0.85), 0.35),
        (good_high(min_buffer_excursion, 100.0, 750.0), 0.25),
    ])

    groups = {"A": a, "Q": q, "M": m, "R": r, "D": d}
    raw = 100.0 * (a**0.25) * (q**0.15) * (m**0.25) * (r**0.20) * (d**0.15)
    core_path = bool(audit.get("core_physical_path_qualified"))
    causal_path = min_valve_flow_correlation >= 0.03 and min_pressure_flow_correlation >= 0.03
    total = raw
    return {
        "policy_id": POLICY_ID,
        "valid": True,
        "G": 1.0,
        "groups": groups,
        "group_weights": {"A": 0.25, "Q": 0.15, "M": 0.25, "R": 0.20, "D": 0.15},
        "aggregation": "G*100*A^0.25*Q^0.15*M^0.25*R^0.20*D^0.15; Q/R/D use worst valid official scenario",
        "raw_total": raw,
        "total": total,
        "headline_metrics": {
            "nominal_final_vehicle_pressure_bar": nominal["vehicle_final_pressure_bar"],
            "worst_final_vehicle_pressure_bar": worst_final_pressure,
            "worst_vehicle_peak_temperature_C": worst_peak_temperature,
            "worst_delivered_mass_kg": worst_mass,
            "minimum_valve_flow_correlation": min_valve_flow_correlation,
            "minimum_pressure_flow_correlation": min_pressure_flow_correlation,
            "minimum_buffer_pressure_excursion_bar": min_buffer_excursion,
        },
        "failures": [],
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
