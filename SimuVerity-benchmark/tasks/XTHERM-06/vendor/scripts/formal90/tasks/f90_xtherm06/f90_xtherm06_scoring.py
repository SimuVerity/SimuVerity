#!/usr/bin/env python3
"""Integrity-only G wrapper for XTHERM-06 engineering groups."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import f90_xtherm06_group_aggregation as SCORING_CORE


def score_evidence(evidence: dict) -> dict:
    original_core = bool(evidence.get("static_audit", {}).get("core_path_qualified"))
    prepared = copy.deepcopy(evidence)
    prepared.setdefault("static_audit", {})["core_path_qualified"] = True
    result = SCORING_CORE.score_evidence(prepared)
    result["schema"] = "simuverity.f90-xtherm06-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xtherm-06:scoring"
    result["observed_core_path_qualified"] = original_core
    result["qualification_policy"] = {
        "G": "load/update/compile and six complete required scenarios",
        "unproved_static_connections": "individual M utilities remain zero",
    }
    result["aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "post_total_cap": "none",
    }
    return result


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
