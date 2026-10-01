#!/usr/bin/env python3
"""XROBO-03 scorer adapter with unique public metric IDs.

All thresholds, weights, qualification gates, causal ceilings, and numerical
scores remain owned by the base scorer.  This adapter only disambiguates
the two nominal robustness metric IDs that otherwise collide with group A.
"""

from __future__ import annotations

import argparse
from typing import Any

from f90_xrobo03_structure_scoring import read_json, score_evidence, write_json


SCORE_SCHEMA = "simuverity.f90-xrobo03-offline-score.v1"
POLICY_ID = 'simuverity-101-v1:f90-xrobo-03:scoring'
METRIC_ID_REBINDINGS = {
    ("R", "nominal_forward_displacement_m"):
        "robustness_nominal_forward_displacement_m",
    ("R", "nominal_positive_forward_fraction"):
        "robustness_nominal_positive_forward_fraction",
}


def score_evidence_with_unique_metrics(evidence: dict[str, Any]) -> dict[str, Any]:
    result = score_evidence(evidence)
    metrics = result.get("metrics", [])
    if not isinstance(metrics, list):
        raise ValueError("METRICS scorer returned a non-list metrics payload")

    seen: set[str] = set()
    for metric in metrics:
        if not isinstance(metric, dict):
            raise ValueError("METRICS scorer returned a non-object metric")
        metric_id = str(metric.get("id", ""))
        if not metric_id:
            raise ValueError("METRICS scorer returned an empty metric ID")
        if metric_id in seen:
            key = (str(metric.get("group", "")), metric_id)
            rebound = METRIC_ID_REBINDINGS.get(key)
            if rebound is None:
                raise ValueError(f"unexpected duplicate metric ID: {metric_id}")
            metric["id"] = rebound
            metric_id = rebound
        if metric_id in seen:
            raise ValueError(f"metric ID remains duplicated after rebinding: {metric_id}")
        seen.add(metric_id)

    result["schema"] = SCORE_SCHEMA
    result["policy_id"] = POLICY_ID
    result["metric_id_bindings"] = {
        "rebindings": [
            {
                "group": group,
                "from": source,
                "to": target,
            }
            for (group, source), target in METRIC_ID_REBINDINGS.items()
        ],
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = score_evidence_with_unique_metrics(read_json(args.evidence))
    write_json(args.output, result)
    print(
        f"F90_XROBO03_OFFLINE_SCORE total={result['total']:.6f} "
        f"G={int(result['G'])} "
        "metric_ids=unique"
    )


if __name__ == "__main__":
    main()
