#!/usr/bin/env python3
"""Pure-offline XAERO03 scorer with median feedback gate and no total cap.

The feedback-presence scorer supplies evidence normalization, qualification,
every metric threshold, every within-group formula, group weights, and the
strict weighted-geometric aggregate. Causal ceiling conditions are retained
as current diagnostics and never alter ``total``.
"""

from __future__ import annotations

import argparse
import copy
from typing import Any

import f90_xaero03_feedback_qualification as base


FORMAL_ID = base.FORMAL_ID
GROUP_WEIGHTS = dict(base.GROUP_WEIGHTS)
POLICY_ID = "simuverity-101-v1:f90-xaero-03:scoring"


def shortcut_diagnostics(
    findings: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Retain source conditions for explanation, never score mutation."""
    diagnostics: list[dict[str, Any]] = []
    for item in findings:
        if not isinstance(item, dict):
            continue
        finding_id = str(item.get("id", ""))
        diagnostics.append(
            {
                "id": finding_id,
                "triggered": bool(item.get("triggered", False)),
                "qualification_gate": finding_id == "general_gate",
                "affects_total": False,
            }
        )
    return diagnostics


def score_evidence(value: dict[str, Any]) -> dict[str, Any]:
    """Apply the current no-post-cap policy to normalized evidence."""
    result = copy.deepcopy(base.score_evidence(value))
    findings = result.pop("shortcut_findings", [])

    # uncapped_total is the strict weighted geometric aggregate.
    # When G is false its applicable groups are zero and this value is exactly
    # zero, so qualification still gates the score without being a total cap.
    total = float(result["uncapped_total"])
    result["schema"] = "simuverity.f90-xaero03-offline-score.v1"
    result["policy_id"] = POLICY_ID
    result["total"] = total
    result["score"] = total
    result["raw_total"] = total
    result["post_total_cap"] = "none"
    result["shortcut_diagnostics"] = shortcut_diagnostics(findings)
    result["total_aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "formula": "G*100*A^0.22*Q^0.12*M^0.32*R^0.15*D^0.19",
        "applicable_groups": list(GROUP_WEIGHTS),
        "not_applicable_groups_excluded": ["C"],
        "qualification_gate_zero_rule": "G=false means total=0",
        "epsilon_floor": "none",
        "post_total_cap": "none",
    }
    notes = result.setdefault("policy_notes", {})
    notes["post_total_cap"] = "none"
    notes["causal_ceiling_conditions"] = (
        "diagnostic only; all effects are represented by the continuous "
        "A/Q/M/R/D group formulas"
    )
    notes["policy_basis"] = (
        "Feedback qualification uses the suite median. Causal ceiling "
        "conditions are diagnostic only because the continuous group "
        "utilities represent performance."
    )
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True, help="input evidence JSON")
    parser.add_argument("--output", required=True, help="offline score JSON")
    parser.add_argument(
        "--normalized-evidence-output",
        help="optional normalized evidence-only JSON",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = base.read_json(args.evidence)
    normalized = base.normalize_evidence(source)
    if args.normalized_evidence_output:
        base.write_json(args.normalized_evidence_output, normalized)
    scored = score_evidence(normalized)
    base.write_json(args.output, scored)
    print(
        f"{FORMAL_ID} offline no-cap valid={int(scored['valid'])} "
        f"total={scored['total']:.12f} output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
