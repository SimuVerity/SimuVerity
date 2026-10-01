#!/usr/bin/env python3
"""Weakest-axis-sensitive, strict-geometric XTHERM-01 scorer.

The M aggregation gives independent mechanism obligations direct influence:
60% weakest component plus 40% weighted mean.  A/Q/R/D use their declared
utility curves, group weights, scenarios, and strict geometric total.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path

import f90_xtherm01_scoring_core as METRICS

WEIGHTS = {"A": .20, "Q": .10, "M": .30, "R": .20, "D": .20}
MECHANISM_WEIGHTS = {
    "storage": .28,
    "passivity": .13,
    "input_causality": .16,
    "capacity": .23,
    "power": .20,
}


def _clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def _mechanism_components(suite: dict) -> dict[str, float]:
    q_storage = METRICS.group(
        [
            METRICS.utility(value, [0, .015, .05, .14, .36, .85], [1, 1, .94, .72, .25, 0])
            for value in suite["storage_residual"]
        ] + [float(bool(suite["storage_coefficients_physical"]))],
        [1, 1, 1, 1, 1.5],
    )
    q_passive = METRICS.utility(
        suite["passivity_violation"],
        [0, .001, .005, .02, .08, .30],
        [1, 1, .95, .75, .28, 0],
    )
    q_input = METRICS.group(
        [
            METRICS.utility(
                suite["generation_schedule_residual"],
                [0, .002, .008, .025, .08, .25],
                [1, 1, .95, .75, .30, 0],
            ),
            METRICS.utility(
                suite["cabin_gain_causality_residual"],
                [0, .02, .07, .18, .45, 1.0],
                [1, 1, .94, .72, .25, 0],
            ),
        ],
        [.58, .42],
    )
    q_capacity = METRICS.group(
        [
            METRICS.utility(
                suite["capacity_schedule_residual"],
                [0, .002, .008, .025, .08, .25],
                [1, 1, .95, .75, .30, 0],
            ),
            METRICS.utility(
                suite["capacity_exceedance_residual"],
                [0, .001, .004, .015, .06, .25],
                [1, 1, .95, .74, .27, 0],
            ),
            METRICS.utility(
                suite["allocation_residual"],
                [0, .003, .012, .04, .14, .45],
                [1, 1, .94, .72, .25, 0],
            ),
        ],
        [.38, .34, .28],
    )
    q_power = METRICS.group(
        [
            METRICS.utility(
                suite["condenser_residual"],
                [0, .003, .012, .04, .14, .45],
                [1, 1, .94, .72, .25, 0],
            ),
            METRICS.utility(
                suite["cop_violation"],
                [0, .001, .004, .015, .06, .25],
                [1, 1, .95, .74, .27, 0],
            ),
            METRICS.utility(
                suite["energy_residual"],
                [0, .002, .008, .025, .08, .25],
                [1, 1, .95, .75, .30, 0],
            ),
            METRICS.utility(
                suite["actuator_contract_violation"],
                [0, .001, .004, .015, .06, .25],
                [1, 1, .95, .74, .27, 0],
            ),
        ],
        [.25, .20, .30, .25],
    )
    return {
        "storage": q_storage,
        "passivity": q_passive,
        "input_causality": q_input,
        "capacity": q_capacity,
        "power": q_power,
    }


def _strict_geometric(groups: dict[str, float], gate: bool) -> float:
    if not gate or any(groups[name] <= 0.0 for name in WEIGHTS):
        return 0.0
    return 100.0 * math.prod(groups[name] ** weight for name, weight in WEIGHTS.items())


def _formal_evidence_from_reference_receipt(receipt: dict) -> dict:
    source = receipt["score"]
    return {
        "schema": "simuverity.formal90-complete-evidence-input.v1",
        "formal_task_id": "F90-XTHERM-01",
        "group_weights": WEIGHTS,
        "platform_valid": bool(receipt.get("platform_valid", True)),
        "facts": {
            "score_inputs_valid": bool(source.get("score_inputs_valid", source.get("G", False))),
            "diagnostics_valid": bool(source.get("diagnostics_valid", True)),
            "gate_reasons": [],
            "scenario_rows": copy.deepcopy(source["scenario_rows"]),
            "suite_metrics": copy.deepcopy(source["suite_metrics"]),
        },
    }


def score_evidence(evidence: dict) -> dict:
    if "facts" not in evidence and isinstance(evidence.get("score"), dict):
        evidence = _formal_evidence_from_reference_receipt(evidence)
    source_groups, _source_total, source_utilities = METRICS.score(evidence)
    facts = evidence["facts"]
    suite = facts.get("suite_metrics", {})
    rows = facts.get("scenario_rows", [])
    gate = bool(facts.get("score_inputs_valid", False) and rows)
    components = _mechanism_components(suite) if gate else {
        name: 0.0 for name in MECHANISM_WEIGHTS
    }
    source_mean = sum(
        components[name] * weight for name, weight in MECHANISM_WEIGHTS.items()
    )
    weakest = min(components.values()) if components else 0.0
    mechanism = .60 * weakest + .40 * source_mean
    if gate:
        if not suite.get("core_thermal_storage", False) or suite.get("static_setpoint_shortcut", False):
            mechanism = 0.0
        elif not suite.get("core_shared_capacity", False):
            mechanism = min(mechanism, .45)
        elif not suite.get("core_component_coolant_path", False):
            mechanism = min(mechanism, .55)
    groups = {
        "A": _clip(source_groups["A"]),
        "Q": _clip(source_groups["Q"]),
        "M": _clip(mechanism),
        "R": _clip(source_groups["R"]),
        "D": _clip(source_groups["D"]),
    }
    total = _strict_geometric(groups, gate)
    failures = [str(reason) for reason in facts.get("gate_reasons", [])]
    if gate and groups["M"] < .60:
        failures.append(f"M independent mechanism obligations below 0.60: {groups['M']:.4f}")
    return {
        "schema": "simuverity.f90-xtherm01-score.v1",
        "task_id": "F90-XTHERM-01",
        "policy_id": "simuverity-101-v1:f90-xtherm-01:scoring",
        "valid": gate,
        "G": 1.0 if gate else 0.0,
        "groups": {"G": 1.0 if gate else 0.0, **groups},
        "group_weights": WEIGHTS,
        "formula": "G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20",
        "aggregation": {
            "method": "G_times_strict_weighted_geometric_mean",
            "post_total_cap": "none",
            "zero_rule": "any applicable group equal to zero yields total zero",
        },
        "raw_total": total,
        "total": total,
        "score": total,
        "scenario_rows": rows,
        "utility_metrics": {
            **source_utilities,
            "M": {
                "components": components,
                "source_weighted_mean": source_mean,
                "weakest_component": weakest,
                "aggregation": ".60*minimum+.40*source_weighted_mean",
            },
        },
        "failure_reasons": failures,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    args = parser.parse_args()
    result = score_evidence(json.loads(args.evidence.read_text(encoding="utf-8-sig")))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
