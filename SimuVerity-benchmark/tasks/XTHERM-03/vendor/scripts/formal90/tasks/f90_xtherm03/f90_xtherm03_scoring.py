#!/usr/bin/env python3
"""Integrity-only G for XTHERM-03 with engineering group scoring.

The public task permits equivalent vector-state realizations.  Block-level
implementation observations are scored in M/C; missing observations receive
zero component credit without erasing otherwise complete dynamic evidence.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import f90_xtherm03_scoring_core as METRICS


def _integrity_failures(evidence: dict, rows: dict) -> list[str]:
    failures: list[str] = []
    for key in ("evidence_complete", "load_pass", "update_pass", "compile_pass"):
        if not bool(evidence.get(key, False)):
            failures.append(f"{key}=false")
    # Optional runtime-integrity aliases are enforced whenever supplied.
    for key in ("nominal_smoke_pass", "score_inputs_valid"):
        if key in evidence and not bool(evidence.get(key)):
            failures.append(f"{key}=false")
    missing = [name for name in METRICS.REQUIRED_SCENARIOS if name not in rows]
    if missing:
        failures.append("missing required scenarios: " + ", ".join(missing))
    invalid = [
        name
        for name in METRICS.REQUIRED_SCENARIOS
        if name in rows
        and (
            not bool(rows[name].get("simulation_pass"))
            or not bool(rows[name].get("valid"))
            or not bool(rows[name].get("required_evidence_pass", True))
        )
    ]
    if invalid:
        failures.append("invalid required scenarios: " + ", ".join(invalid))
    return failures


def score_evidence(evidence: dict) -> dict:
    original = METRICS.qualification
    METRICS.qualification = _integrity_failures
    try:
        result = METRICS.score_evidence(evidence)
    finally:
        METRICS.qualification = original
    result["schema"] = "simuverity.f90-xtherm03-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xtherm-03:scoring"
    result["aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "post_total_cap": "none",
        "zero_rule": "any applicable group equal to zero yields total zero",
    }
    result["qualification_policy"] = {
        "G": "runtime, complete required scenarios/outputs, complete evidence",
        "implementation_specific_static_observations": "scored in M/C only",
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
    result = score_evidence(
        json.loads(args.evidence.read_text(encoding="utf-8-sig"))
    )
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
