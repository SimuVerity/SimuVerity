"""Pure-offline scorer for the RM3 public evidence contract.

The A/Q/M/C/R/D groups use strict weighted-geometric aggregation.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

import ext_xfluid_wecsim_rm3_group_scoring as group_scoring


WEIGHTS = {"A": .20, "Q": .10, "M": .20, "C": .10, "R": .20, "D": .20}
EVALUATION_POLICY_ID = "simuverity-101-v1:ext-xfluid-wecsim-rm3:scoring"


def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(group_scoring.score_evidence(evidence))
    groups = dict(result["groups_normalized"])
    raw = group_scoring.core.strict_weighted_geometric(result["G"], groups, WEIGHTS)
    result.update({
        "evaluation_policy_id": EVALUATION_POLICY_ID,
        "group_weights": WEIGHTS,
        "raw_score": raw,
        "admission_pass": bool(result["G"] and raw >= 90.0),
    })
    return result


def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    base = score_evidence(evidence)
    checks: dict[str, bool] = {}
    missing = copy.deepcopy(evidence)
    missing["scenarios"][0].pop("rm3_pto_response", None)
    checks["required_output_loses_score"] = score_evidence(missing)["raw_score"] < base["raw_score"]
    no_pto = copy.deepcopy(evidence)
    for item in no_pto["scenarios"]:
        item["rm3_pto_response"] = [[0.0, 0.0, 0.0, 0.0] for _ in item["time_s"]]
    checks["disconnected_pto_loses_score"] = score_evidence(no_pto)["raw_score"] < base["raw_score"]
    copied = copy.deepcopy(evidence)
    for item in copied["scenarios"]:
        height = float(item["input"]["wave_height_m"])
        item["rm3_body_response"] = [[height] * 4 for _ in item["time_s"]]
    checks["command_copy_loses_score"] = score_evidence(copied)["raw_score"] < base["raw_score"]
    return {"task_id": group_scoring.core.TASK_ID, "evaluation_policy_id": EVALUATION_POLICY_ID, "checks": checks, "pass": all(checks.values())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--shortcut-output", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(score_evidence(evidence), indent=2) + "\n", encoding="utf-8")
    if args.shortcut_output:
        args.shortcut_output.write_text(json.dumps(shortcut_sanity(evidence), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
