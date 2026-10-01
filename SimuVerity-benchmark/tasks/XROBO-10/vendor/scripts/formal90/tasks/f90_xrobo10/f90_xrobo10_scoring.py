#!/usr/bin/env python3
"""CLI-compatible strict-geometric/no-cap scorer for XROBO-10."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import f90_xrobo10_group_aggregation as SCORING_CORE


def score_evidence(evidence: dict) -> dict:
    result = SCORING_CORE.score_evidence(evidence)
    result["schema"] = "simuverity.f90-xrobo10-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xrobo-10:scoring"
    return json_safe(result)


def json_safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    return value


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
