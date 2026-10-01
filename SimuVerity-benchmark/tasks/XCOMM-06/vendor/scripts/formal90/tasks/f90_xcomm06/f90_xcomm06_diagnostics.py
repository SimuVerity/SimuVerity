#!/usr/bin/env python3
"""F90-XCOMM-06 scorer with non-score-bearing diagnostic findings."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import f90_xcomm06_scoring_core as base
from f90_xcomm06_group_aggregation import strict_geometric_total


POLICY_ID = "simuverity-101-v1:f90-xcomm-06:scoring"


def score_evidence(evidence: dict) -> dict:
    result = copy.deepcopy(base.score_evidence(evidence))
    groups = copy.deepcopy(result["groups"])
    diagnostics = copy.deepcopy(result.get("diagnostics", {}))
    source_findings = diagnostics.pop("shortcut_findings", [])
    findings = [item["reason"] for item in source_findings]
    total = strict_geometric_total(result["G"], groups)
    result.update({
        "schema": "simuverity.f90-xcomm06-score.v1",
        "policy_id": POLICY_ID,
        "groups": groups,
        "score": total,
        "admission_score_pass": bool(
            result["G"] and total >= result["admission_threshold"]
        ),
        "failure_reasons": [
            reason for reason in result.get("failure_reasons", [])
            if reason not in findings
        ],
        "diagnostics": diagnostics,
        "diagnostic_findings": findings,
        "total_aggregation": {
            "method": "G_times_strict_weighted_geometric_mean",
            "applicable_groups": list(base.WEIGHTS),
            "zero_group_rule": "any applicable zero group makes total zero",
            "epsilon_floor": "none",
            "post_total_cap_or_floor": "none",
        },
    })
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name("score.json")
    out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"score": result["score"], "groups": result["groups"], "out": str(out)}))


if __name__ == "__main__":
    main()
