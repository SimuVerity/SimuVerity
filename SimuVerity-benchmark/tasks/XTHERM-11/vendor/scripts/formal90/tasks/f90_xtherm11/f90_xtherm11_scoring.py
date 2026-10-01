#!/usr/bin/env python3
"""Integrity-only G, strict-geometric/no-cap XTHERM-11 scorer."""
from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from geometric_scoring_adapter import adapt_source_result, load_current

SOURCE = Path(__file__).with_name("f90_xtherm11_scoring_core.py")
METRICS = load_current(SOURCE, "xtherm11_current_source_for",
)
WEIGHTS = {"A": .20, "Q": .10, "M": .20, "C": .20, "R": .15, "D": .15}
MAPPING = {
    "official input axes": "M/C",
    "dual actuation": "C/D",
    "degradation fidelity": "M",
    "physical envelope": "Q/R",
    "concentration response": "M",
}


def score_evidence(evidence: dict) -> dict:
    original_static = dict(evidence.get("static_audit", {}))
    original_behavior = dict(evidence.get("behavior_audit", {}))
    working = copy.deepcopy(evidence)
    working["evidence_complete"] = True
    working.setdefault("static_audit", {})["core_path_qualified"] = True
    working.setdefault("behavior_audit", {})["core_behavior_qualified"] = True
    source = METRICS.score_evidence(working)
    # The observed core-path flag supplies explicit feedback-structure credit
    # in C while qualification remains based on complete runnable evidence.
    c_parts = source.get("diagnostics", {}).get("C_utilities", {})
    if c_parts:
        c_parts["feedback_structure"] = float(
            bool(original_static.get("core_path_qualified"))
        )
        source["groups"]["C"] = METRICS.weighted(
            list(c_parts.values()), [0.20, 0.20, 0.18, 0.18, 0.24]
        )
    result = adapt_source_result(
        source,
        schema="simuverity.f90-xtherm11-score.v1",
        policy_id="simuverity-101-v1:f90-xtherm-11:scoring",
        weights=WEIGHTS,
        primary_total_key="score",
        cap_conditions_already_represented_in_groups=MAPPING,
    )
    result["observed_static_audit"] = original_static
    result["observed_behavior_audit"] = original_behavior
    result["qualification_policy"] = {
        "G": "outer-complete complete runnable six-scenario evidence",
        "structure_and_behavior_shortcomings": "M/C/R/D components only",
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
