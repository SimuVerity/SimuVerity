#!/usr/bin/env python3
"""XMED-02 offline scorer with pulsatility owned by the mechanism group."""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[1]))

from formal90_scoring_core import (  # noqa: E402
    base_receipt,
    clip,
    load_evidence,
    parser,
    write_receipt,
)
from f90_xmed02_structure_policy import (  # noqa: E402
    POLICY_ID as STRUCTURE_POLICY_ID,
    assess_circulation,
)


TASK_ID = "F90-XMED-02"
SCORE_POLICY_ID = "simuverity-101-v1:f90-xmed-02:scoring"
MECHANISM_COMPONENTS = (
    "circulation_structure",
    "physical_measurements",
    "real_pump_actuator",
    "pressure_feedback_to_pump",
    "public_interface",
    "pressure_output_provenance",
    "flow_output_provenance",
    "command_feedback_provenance",
)


def _reason_list(value: object) -> list[str]:
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, list):
        return [item for item in value if isinstance(item, str) and item]
    return []


def curve(value, anchors, scores):
    value = float(value)
    if value <= anchors[0]:
        return scores[0]
    if value >= anchors[-1]:
        return scores[-1]
    for index in range(1, len(anchors)):
        if value <= anchors[index]:
            fraction = (value - anchors[index - 1]) / (
                anchors[index] - anchors[index - 1]
            )
            return clip(
                scores[index - 1]
                + fraction * (scores[index] - scores[index - 1])
            )
    return scores[-1]


def plateau(value, bounds):
    value = float(value)
    if value < bounds[0] or value > bounds[3]:
        return 0.0
    if bounds[1] <= value <= bounds[2]:
        return 1.0
    if value < bounds[1]:
        return (value - bounds[0]) / (bounds[1] - bounds[0])
    return (bounds[3] - value) / (bounds[3] - bounds[2])


def scenario(row):
    metrics = row["metrics"]
    accuracy = min(
        curve(
            metrics["initial_error_mmHg"],
            [1, 2, 4, 8, 15],
            [1, 0.92, 0.70, 0.30, 0],
        ),
        curve(
            metrics["final_error_mmHg"],
            [1, 2, 4, 8, 15],
            [1, 0.92, 0.70, 0.30, 0],
        ),
    )
    q_pulse = plateau(metrics["pulse_pressure_mmHg"], [8, 15, 65, 90])
    q_cvp = plateau(metrics["cvp_mean_mmHg"], [0, 1, 10, 18])
    q_pap = plateau(metrics["pap_mean_mmHg"], [5, 10, 35, 55])
    quality = sum(
        [
            q_cvp,
            q_pap,
            curve(
                metrics["flow_balance_fraction"],
                [0.10, 0.20, 0.40, 0.80],
                [1, 0.9, 0.5, 0],
            ),
            curve(
                metrics["heart_rate_error_bpm"],
                [1, 3, 7, 15],
                [1, 0.9, 0.5, 0],
            ),
        ]
    ) / 4
    forward = min(
        curve(metrics["ecmo_flow_mean_cm3_s"], [0, 2, 8], [0, 0.7, 1]),
        curve(
            metrics["negative_ecmo_fraction"],
            [0, 0.001, 0.02, 0.10],
            [1, 0.9, 0.4, 0],
        ),
    )
    flow_range = (
        plateau(metrics["systemic_flow_mean_cm3_s"], [5, 20, 150, 250])
        + plateau(metrics["pulmonary_flow_mean_cm3_s"], [5, 20, 150, 250])
    ) / 2
    authority = float(bool(metrics["command_within_limit"])) * curve(
        metrics["pump_saturation_fraction"],
        [0.30, 0.60, 0.85, 1.0],
        [1, 0.9, 0.4, 0],
    )
    robustness = sum(
        [forward, flow_range, authority, (q_cvp + q_pap) / 2]
    ) / 4
    dynamics = sum(
        [
            curve(
                metrics["settling_time_s"],
                [0.8, 1.4, 2.3, 3.5],
                [1, 0.9, 0.5, 0],
            ),
            curve(
                metrics["overshoot_mmHg"],
                [2, 4, 8, 15],
                [1, 0.9, 0.5, 0],
            ),
            curve(
                metrics["initial_settling_time_s"],
                [0.8, 1.2, 1.8, 2.5],
                [1, 0.9, 0.5, 0],
            ),
        ]
    ) / 3
    return {
        "A": accuracy,
        "Q": quality,
        "R": robustness,
        "D": dynamics,
        "q_pulse": q_pulse,
    }


def _mechanism_decision(facts: dict) -> tuple[float, bool, list[str], dict]:
    audit = facts.get("static_audit", {})
    audit = audit if isinstance(audit, dict) else {}
    decision = assess_circulation(audit.get("circulation_graph"))
    reasons = _reason_list(facts.get("gate_reasons", []))
    reasons.extend(decision["reasons"])
    components = audit.get("components")
    complete = isinstance(components, dict) and all(
        name in components for name in MECHANISM_COMPONENTS
    )
    if not complete:
        reasons.append("missing_static_audit_components")
        mechanism = 0.0
    else:
        values = []
        for name in MECHANISM_COMPONENTS:
            if name == "circulation_structure":
                values.append(float(decision["pass"]))
            else:
                try:
                    values.append(clip(float(components[name])))
                except (TypeError, ValueError):
                    complete = False
                    values.append(0.0)
        if not complete:
            reasons.append("invalid_static_audit_components")
        mechanism = sum(values) / len(MECHANISM_COMPONENTS) if complete else 0.0
        if "missing_or_invalid_circulation_graph" in decision["reasons"]:
            mechanism = 0.0
    evidence_gate = facts.get("score_inputs_valid") is True
    if not evidence_gate and not reasons:
        reasons.append("evidence_score_inputs_invalid")
    gate = evidence_gate and decision["pass"] and complete
    return mechanism, gate, list(dict.fromkeys(reasons)), decision


def score(evidence):
    facts = evidence["facts"]
    rows = facts.get("scenario_rows", [])
    structure_mechanism, gate, reasons, _ = _mechanism_decision(facts)
    values = (
        [scenario(row) for row in rows]
        if rows and all(row.get("valid", False) for row in rows)
        else []
    )
    quality = min((value["Q"] for value in values), default=0.0)
    accuracy = min((value["A"] for value in values), default=0.0)
    robustness = min((value["R"] for value in values), default=0.0)
    dynamics = min((value["D"] for value in values), default=0.0)
    pulsatility = min((value["q_pulse"] for value in values), default=0.0)
    mechanism = 0.5 * structure_mechanism + 0.5 * pulsatility
    groups = {
        "A": accuracy,
        "Q": quality,
        "M": mechanism,
        "R": robustness,
        "D": dynamics,
    }
    weights = evidence["group_weights"]
    total = (
        100
        * accuracy ** weights["A"]
        * quality ** weights["Q"]
        * mechanism ** weights["M"]
        * robustness ** weights["R"]
        * dynamics ** weights["D"]
        if gate
        else 0.0
    )
    return groups, total, reasons, values


def main():
    args = parser(TASK_ID).parse_args()
    evidence = load_evidence(args.evidence, TASK_ID)
    groups, value, reasons, utilities = score(evidence)
    structure_mechanism, _, _, structure = _mechanism_decision(evidence["facts"])
    worst_pulsatility = min(
        (item["q_pulse"] for item in utilities), default=0.0
    )
    receipt = base_receipt(
        args.evidence,
        evidence,
        groups,
        value,
        policy_id=SCORE_POLICY_ID,
        gate_reasons=reasons,
    )
    receipt.update(
        {
            "structure_policy_id": STRUCTURE_POLICY_ID,
            "structure_decision": structure,
            "mechanism_aggregation": {
                "structure_weight": 0.5,
                "worst_case_pulsatility_weight": 0.5,
                "structure_utility": structure_mechanism,
                "worst_case_pulsatility_utility": worst_pulsatility,
            },
            "static_audit": evidence["facts"].get("static_audit", {}),
            "scenarios": evidence["facts"].get("scenario_rows", []),
            "scenario_utilities": utilities,
        }
    )
    write_receipt(args.output, receipt)


if __name__ == "__main__":
    main()
