#!/usr/bin/env python3
"""Subject-aware reference binding for XBATT-10 candidate/reference scoring."""

from __future__ import annotations

from typing import Any

import f90_xbatt10_representation_compatibility as representation_compatibility


def score(
    reference_evidence: dict[str, Any], candidate_evidence: dict[str, Any]
) -> dict[str, Any]:
    reference_branch = candidate_evidence is reference_evidence
    if not reference_branch:
        result = representation_compatibility.score(reference_evidence, candidate_evidence)
    else:
        original_validate = representation_compatibility.validate_candidate
        original_component_values = representation_compatibility.component_values

        def reference_component_values(
            scenario: dict[str, Any], log_name: str, index: int, *, reference: bool
        ) -> list[float] | None:
            return original_component_values(
                scenario, log_name, index, reference=True
            )

        representation_compatibility.validate_candidate = representation_compatibility.validate_reference
        representation_compatibility.component_values = reference_component_values
        try:
            result = representation_compatibility.score(reference_evidence, candidate_evidence)
        finally:
            representation_compatibility.validate_candidate = original_validate
            representation_compatibility.component_values = original_component_values
    result["schema"] = "simuverity.f90-xbatt10-offline-score.v1"
    result["scorer_implementation"] = "f90_xbatt10_reference_binding"
    result["reference_branch"] = reference_branch
    return result
