#!/usr/bin/env python3
"""XAERO-07 scorer with an explicit top-level qualification gate."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import f90_xaero07_public_layout_compatibility as public_layout_compatibility


def score(
    evidence: dict[str, Any],
    path: Path,
    evidence_role: str = "candidate",
) -> dict[str, Any]:
    result = public_layout_compatibility.score(evidence, path, evidence_role=evidence_role)
    result["schema"] = "simuverity.f90-xaero07-offline-score.v1"
    result["scorer_implementation"] = "simuverity-101-v1:f90-xaero-07:scoring"
    result["G"] = int(result.get("gate", {}).get("G", 0))
    result["output_contract"] = {
        "top_level_G_source": "gate.G",
        "post_total_cap": "none",
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--evidence-role", choices=("candidate", "reference"), default="candidate"
    )
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    result = score(evidence, args.evidence, evidence_role=args.evidence_role)
    (args.output_dir / "score.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
