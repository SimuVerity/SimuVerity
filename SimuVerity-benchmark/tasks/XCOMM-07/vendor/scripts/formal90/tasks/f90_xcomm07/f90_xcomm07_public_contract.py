#!/usr/bin/env python3
"""Candidate-independent XCOMM-07 scorer for the public six-log contract."""

from __future__ import annotations

import copy
from typing import Any

import f90_xcomm07_scoring_core as core


POLICY_ID = "simuverity-101-v1:f90-xcomm-07:scoring"


def _adapt_candidate(evidence: dict[str, Any]) -> dict[str, Any]:
    """Normalize lossless JSON scalar encodings without changing values."""
    adapted = copy.deepcopy(evidence)
    for scenario in adapted.get("scenarios", []):
        logs = scenario.get("logs", {})
        for name in ("packet_detection", "cfo_estimation"):
            log = logs.get(name, {})
            if isinstance(log.get("time"), (int, float)):
                log["time"] = [float(log["time"])]
        packet = logs.get("packet_detection", {})
        if isinstance(packet.get("data"), (int, float)):
            packet["data"] = [float(packet["data"])]
        cfo = logs.get("cfo_estimation", {})
        if (
            isinstance(cfo.get("data"), list)
            and len(cfo["data"]) == 2
            and all(isinstance(value, (int, float)) for value in cfo["data"])
        ):
            cfo["data"] = [[float(value) for value in cfo["data"]]]
    return adapted


def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    result = core.score(reference, _adapt_candidate(candidate))
    groups = {
        name: float(result["group_scores"][name])
        for name in core.WEIGHTS
    }
    total = float(result["raw_score"])
    result.update(
        {
            "schema": "simuverity.f90-xcomm07-offline-score.v1",
            "policy_id": POLICY_ID,
            "G": float(result["gate"]["G"]),
            **groups,
            "raw_total": total,
            "total": total,
            "scorer_implementation": "f90_xcomm07_public_contract",
            "candidate_identity_binding": "candidate-independent-public-contract",
            "scalar_batch_adapter_applied": True,
        }
    )
    return result
