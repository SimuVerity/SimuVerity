#!/usr/bin/env python3
"""Behavior-qualified, strict-geometric XTHERM-05 scorer.

The mechanism group uses complete counterfactual evidence rather than
name-sensitive implementation observations:

* independent 24-channel battery and plate temperature fields;
* coolant-flow -> hydraulic pressure response;
* coolant-flow -> battery/plate thermal response; and
* electrical power -> battery/plate temperature response.

The official scenarios use the declared A/Q/R/D definitions, group weights,
and strict geometric total.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import f90_xtherm05_scoring_core as METRICS

WEIGHTS = {"A": .20, "Q": .17, "M": .25, "R": .23, "D": .15}


def _clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def _high(value: float, bad: float, good: float) -> float:
    return _clip((float(value) - bad) / (good - bad))


def _bottleneck(values: list[float], weights: list[float]) -> float:
    clipped = [_clip(value) for value in values]
    return math.sqrt(
        sum(value * weight for value, weight in zip(clipped, weights))
        / sum(weights)
        * min(clipped)
    )


def _behavioral_mechanism(facts: dict) -> tuple[float, dict]:
    rows = {str(row.get("id")): row for row in facts.get("scenario_rows", [])}
    required = {"current_pair_up", "current_pair_control", "current_pair_down"}
    if not required.issubset(rows):
        return 0.0, {"reason": "current-pair rows unavailable"}

    all_rows = list(rows.values())
    minimum_battery_channels = min(
        float(row.get("battery_distinct_tail_channels", 0)) for row in all_rows
    )
    minimum_plate_channels = min(
        float(row.get("plate_distinct_tail_channels", 0)) for row in all_rows
    )
    distributed_spatial_fields = math.sqrt(
        _high(minimum_battery_channels, 3.0, 12.0)
        * _high(minimum_plate_channels, 3.0, 12.0)
    )

    flow = facts.get("paired_flow", {})
    flow_pressure_causality = _high(float(flow.get("pressure_ratio", 0)), 1.15, 2.0)
    flow_thermal_causality = math.sqrt(
        _high(float(flow.get("battery_improvement_K", 0)), .02, .35)
        * _high(float(flow.get("plate_improvement_K", 0)), .01, .25)
    )

    up = rows["current_pair_up"]
    control = rows["current_pair_control"]
    down = rows["current_pair_down"]
    control_power = max(abs(float(control.get("electrical_power_tail_W", 0))), 1.0)
    minimum_power_fraction = min(
        (float(up.get("electrical_power_tail_W", 0))
         - float(control.get("electrical_power_tail_W", 0))) / control_power,
        (float(control.get("electrical_power_tail_W", 0))
         - float(down.get("electrical_power_tail_W", 0))) / control_power,
    )
    minimum_battery_response_K = min(
        float(up.get("battery_tail_mean_K", 0))
        - float(control.get("battery_tail_mean_K", 0)),
        float(control.get("battery_tail_mean_K", 0))
        - float(down.get("battery_tail_mean_K", 0)),
    )
    minimum_plate_response_K = min(
        float(up.get("plate_tail_mean_K", 0))
        - float(control.get("plate_tail_mean_K", 0)),
        float(control.get("plate_tail_mean_K", 0))
        - float(down.get("plate_tail_mean_K", 0)),
    )
    electrothermal_coupling = (
        _high(minimum_power_fraction, .02, .10)
        * _high(minimum_battery_response_K, .002, .030)
        * _high(minimum_plate_response_K, .001, .020)
    ) ** (1.0 / 3.0)

    utilities = {
        "distributed_spatial_fields": distributed_spatial_fields,
        "flow_pressure_causality": flow_pressure_causality,
        "flow_thermal_causality": flow_thermal_causality,
        "electrothermal_coupling": electrothermal_coupling,
        "raw": {
            "minimum_battery_distinct_tail_channels": minimum_battery_channels,
            "minimum_plate_distinct_tail_channels": minimum_plate_channels,
            "minimum_relative_power_response": minimum_power_fraction,
            "minimum_battery_temperature_response_K": minimum_battery_response_K,
            "minimum_plate_temperature_response_K": minimum_plate_response_K,
        },
    }
    mechanism = _bottleneck(
        [
            distributed_spatial_fields,
            flow_pressure_causality,
            flow_thermal_causality,
            electrothermal_coupling,
        ],
        [.25, .25, .25, .25],
    )
    return mechanism, utilities


def score_evidence(evidence: dict) -> dict:
    facts = evidence.get("facts", {})
    source_groups, _source_total, _source_gate, source_reasons, utilities = METRICS.score(
        evidence
    )
    rows = facts.get("scenario_rows", [])
    integrity = bool(
        evidence.get("platform_valid")
        and facts.get("platform_valid")
        and facts.get("score_inputs_valid")
        and facts.get("diagnostics_valid")
        and rows
        and all(bool(row.get("valid")) for row in rows)
    )

    mechanism, mechanism_utilities = _behavioral_mechanism(facts)
    group_values = {
        "A": float(source_groups.get("A", 0.0)),
        "Q": float(source_groups.get("Q", 0.0)),
        "M": float(mechanism),
        "R": float(source_groups.get("R", 0.0)),
        "D": float(source_groups.get("D", 0.0)),
    }
    total = (
        100.0 * math.prod(group_values[name] ** WEIGHTS[name] for name in WEIGHTS)
        if integrity and all(group_values[name] > 0 for name in WEIGHTS)
        else 0.0
    )

    failures = [
        str(reason)
        for reason in source_reasons
        if not str(reason).startswith("M physical mechanism/causality")
    ]
    if mechanism < .60:
        failures.append(f"M physical mechanism/causality group below 0.60: {mechanism:.4f}")
    if not integrity:
        failures.extend(str(reason) for reason in facts.get("gate_reasons", []))

    result_groups = {"G": 1.0 if integrity else 0.0, **group_values}
    utilities = dict(utilities)
    utilities["M"] = mechanism_utilities
    return {
        "schema": "simuverity.f90-xtherm05-score.v1",
        "task_id": "F90-XTHERM-05",
        "policy_id": "simuverity-101-v1:f90-xtherm-05:scoring",
        "valid": integrity,
        "G": 1.0 if integrity else 0.0,
        "groups": result_groups,
        "group_weights": WEIGHTS,
        "formula": "G*100*A^0.20*Q^0.17*M^0.25*R^0.23*D^0.15",
        "aggregation": {
            "method": "G_times_strict_weighted_geometric_mean",
            "post_total_cap": "none",
            "zero_rule": "any applicable group equal to zero yields total zero",
        },
        "raw_total": total,
        "total": total,
        "score": total,
        "scenario_rows": rows,
        "name_sensitive_static_observations": facts.get("static_audit", {}),
        "raw_metrics": {
            "paired_flow": facts.get("paired_flow", {}),
            "paired_current": facts.get("paired_current", {}),
        },
        "utility_metrics": utilities,
        "failure_reasons": failures,
        "qualification_policy": {
            "G": "runnable complete complete scenario evidence",
            "M": "implementation-neutral spatial, hydraulic, thermal, and electrothermal counterfactual evidence",
            "name_sensitive_static_observations": "diagnostic only; never used in G or M",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--out", dest="output_flag", type=Path)
    parser.add_argument("--output", dest="output_long", type=Path)
    args = parser.parse_args()
    output = args.output_long or args.output_flag or args.output
    result = score_evidence(json.loads(args.evidence.read_text(encoding="utf-8-sig")))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
