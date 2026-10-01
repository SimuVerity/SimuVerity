#!/usr/bin/env python3
"""Integrity-only G and implementation-neutral mechanism scoring for XROBO-06."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import f90_xrobo06_scoring_core as METRICS


STATIC_COMPONENT = "static_closed_loop_multibody_path"


def score(evidence: dict) -> dict:
    original_core = bool(evidence.get("static_audit", {}).get("core_path_qualified"))
    working = copy.deepcopy(evidence)
    working.setdefault("static_audit", {})["core_path_qualified"] = True
    result = METRICS.score(working)
    if result.get("groups", {}).get("G") != 1.0:
        return result

    parts = result["diagnostics"]["M"]
    _, weight = parts[STATIC_COMPONENT]
    parts[STATIC_COMPONENT] = (1.0 if original_core else 0.0, weight)
    result["groups"]["M"] = METRICS.weighted(parts)
    result["score"] = 100.0 * METRICS.geometric(result["groups"])
    result["schema"] = "simuverity.f90-xrobo06-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xrobo-06:scoring"
    result["qualification_checks"]["physical_closed_loop_path"] = True
    result["qualification_checks"]["physical_path_is_score_component_not_G"] = True
    result["diagnostics"]["static_audit_original_core_path_qualified"] = original_core
    result["diagnostics"]["aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "post_total_cap": "none",
    }
    result["failure_reasons"] = []
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--out", dest="output_flag", type=Path)
    parser.add_argument("--output", dest="output_long", type=Path)
    args = parser.parse_args()
    output = args.output_long or args.output_flag or args.output
    result = score(json.loads(args.evidence.read_text(encoding="utf-8-sig")))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
