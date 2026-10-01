#!/usr/bin/env python3
"""Strict-geometric XROBO-01 scorer without post-total mechanism caps."""

from __future__ import annotations

import math
from typing import Any

import f90_xrobo01_scoring_core as GROUP_SCORING


POLICY_ID = 'simuverity-101-v1:f90-xrobo-01:scoring'


def strict_geometric(groups: dict[str, float], weights: dict[str, float], gate: bool = True) -> float:
    values = {name: float(groups[name]) for name in weights}
    if any(not math.isfinite(value) or not 0.0 <= value <= 1.0 for value in values.values()):
        raise ValueError("group scores must be finite and in [0,1]")
    if not gate or any(value <= 0.0 for value in values.values()):
        return 0.0
    return 100.0 * math.exp(sum(weights[name] * math.log(values[name]) for name in weights))


def _score_with_context(evidence: dict[str, Any]):
    enriched, decision = GROUP_SCORING.evidence_with_structure_decision(evidence)
    groups, _source_value, diagnostics, reasons = GROUP_SCORING.METRICS.score(enriched)
    weights = {name: float(enriched["group_weights"][name]) for name in groups}
    gate = bool(enriched["facts"].get("score_inputs_valid", False))
    total = strict_geometric(groups, weights, gate)
    diagnostics = dict(diagnostics)
    diagnostics["structure_decision"] = decision
    diagnostics["group_internal_shortcut_rules"] = {
        "M": "M<0.35/M<0.55 conditions remain represented by M itself",
        "D": "D<0.25 condition remains represented by D itself",
    }
    diagnostics["total_aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "strict_zero_rule": "any_applicable_group_le_zero_means_total_zero",
        "not_applicable_groups_excluded": True,
        "epsilon_floor": "none",
        "post_total_cap_floor_or_override": "none",
    }
    return enriched, decision, groups, total, diagnostics, reasons, weights


def score(evidence: dict[str, Any]):
    _, _, groups, total, diagnostics, reasons, _ = _score_with_context(evidence)
    return groups, total, diagnostics, reasons


def main() -> int:
    arguments = GROUP_SCORING.METRICS.parser("F90-XROBO-01").parse_args()
    evidence = GROUP_SCORING.METRICS.load_evidence(arguments.evidence, "F90-XROBO-01")
    enriched, decision, groups, total, diagnostics, reasons, weights = _score_with_context(evidence)
    receipt = GROUP_SCORING.METRICS.base_receipt(
        arguments.evidence,
        enriched,
        groups,
        total,
        policy_id=POLICY_ID,
        gate_reasons=reasons,
    )
    receipt.update(
        {
            "scenario_rows": enriched["facts"].get("scenario_rows", []),
            "static_audit": enriched["facts"].get("static_audit", {}),
            "pair_diagnostics": diagnostics,
            "structure_decision": decision,
            "group_weights": weights,
            "scoring_configuration": "groups-strict-total",
            "total_aggregation": diagnostics["total_aggregation"],
        }
    )
    GROUP_SCORING.METRICS.write_receipt(arguments.output, receipt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
