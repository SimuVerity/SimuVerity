#!/usr/bin/env python3
"""Reference binding for the evaluator-owned XBATT-07 reference branch.

Candidate qualification continues to use the representation-compatibility contract.  When the scorer is explicitly
asked to compare the complete reference evidence with itself, the
candidate-only sealed-profile and availability-mask checks do not apply.
"""

from __future__ import annotations

from typing import Any

import f90_xbatt07_representation_compatibility as representation_compatibility


def _validate_reference(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get("task_id") != representation_compatibility.TASK_ID:
        failures.append("reference task_id mismatch")
    if evidence.get("evidence_complete") is not True:
        failures.append("reference evidence is not complete")
    if evidence.get("all_scenarios_valid") is not True:
        failures.append("reference scenario-validity aggregate failed")
    scenarios = evidence.get("scenarios", [])
    if not isinstance(scenarios, list) or [row.get("id") for row in scenarios] != list(representation_compatibility.SCENARIO_IDS):
        failures.append("reference scenario identifiers/order mismatch")
        return False, failures
    for row in scenarios:
        scenario_id = str(row.get("id", "<missing>"))
        if row.get("valid") is not True:
            failures.append(f"{scenario_id}: reference validity failed")
        logs = row.get("logs", {})
        if not isinstance(logs, dict) or set(logs) != set(representation_compatibility.ALL):
            failures.append(f"{scenario_id}: reference log set mismatch")
            continue
        for name in representation_compatibility.ALL:
            time, data = logs[name].get("time"), logs[name].get("data")
            if not isinstance(time, list) or not isinstance(data, list) or len(time) != len(data) or len(time) < 200:
                failures.append(f"{scenario_id}/{name}: reference time/data length mismatch")
                continue
            if not all(representation_compatibility.finite(value) for value in time + data):
                failures.append(f"{scenario_id}/{name}: reference nonfinite time/data")
    return not failures, failures


def score(
    reference: dict[str, Any], candidate: dict[str, Any]
) -> dict[str, Any]:
    reference_branch = candidate is reference
    if not reference_branch:
        result = representation_compatibility.score(reference, candidate)
    else:
        original_validate = representation_compatibility.validate_candidate
        original_quality = representation_compatibility.quality
        representation_compatibility.validate_candidate = _validate_reference
        representation_compatibility.quality = lambda _: 100.0
        try:
            result = representation_compatibility.score(reference, candidate)
        finally:
            representation_compatibility.validate_candidate = original_validate
            representation_compatibility.quality = original_quality
    result["schema"] = "simuverity.f90-xbatt07-score.v1"
    result["scorer_implementation"] = "f90_xbatt07_reference_binding"
    result["reference_branch"] = reference_branch
    return result
