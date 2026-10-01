#!/usr/bin/env python3
"""F90-XAUTO-07 group scoring with explicit weakest-component aggregation.

M/C/R/D emphasize their weakest physical or dynamic component.  A and Q use
the direct torque-tracking, estimation, ripple, balance and smoothness evidence.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import f90_xauto07_normalized_evidence as base


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _strong_worst(values: list[float]) -> float:
    """Sixty-percent weakest component plus forty-percent component mean."""
    return 0.60 * min(values) + 0.40 * _mean(values) if values else 0.0


def _profile_fidelity(peak: float, scale: float) -> float:
    if scale <= 0.0:
        return 0.0
    return base.low(abs(peak / scale - 1.0), 0.02, 0.25)


def score(
    evidence: dict[str, Any],
    evidence_path: Path,
    requested_subject: str = "auto",
    context: dict[str, Any] | None = None,
    loaded_override: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    result = base.score(
        evidence, evidence_path, requested_subject, context, loaded_override
    )
    result["schema"] = "simuverity.f90-xauto07-offline-score.v1"
    result["scorer_implementation"] = "simuverity-101-v1:f90-xauto-07:scoring"
    if result.get("G") != 1 or not result.get("scoring_completed"):
        return result

    components = result["metrics"]["group_components"]
    scenarios = base.scenario_map(evidence)
    derived = {
        sid: result["scenarios"][sid]["derived_metrics"] for sid in base.SCENARIOS
    }

    structure = _mean([float(value) for value in components["M"]["structure"].values()])
    operating_modes = _mean(
        [float(value) for value in components["M"]["motoring_and_generating"].values()]
    )
    coupling = _mean(
        [float(value) for value in components["M"]["electromechanical_coupling"].values()]
    )
    mechanism_axes = {
        "connected_structure": structure,
        "motoring_and_generating": operating_modes,
        "electromechanical_coupling": coupling,
    }
    mechanism_score = _strong_worst(list(mechanism_axes.values()))

    acceleration_profile_rows: dict[str, float] = {}
    brake_profile_rows: dict[str, float] = {}
    for sid in base.SCENARIOS:
        inputs = scenarios[sid]["inputs"]
        acceleration_profile_rows[sid] = _profile_fidelity(
            float(derived[sid]["accelerator_peak"]),
            float(inputs["acceleration_scale"]),
        )
        brake_profile_rows[sid] = _profile_fidelity(
            float(derived[sid]["brake_peak"]),
            float(inputs["brake_scale"]),
        )
    acceleration_profile = _mean(list(acceleration_profile_rows.values()))
    brake_profile = _mean(list(brake_profile_rows.values()))
    acceleration_axis = _mean([
        float(components["C"]["acceleration_scale_response"]),
        acceleration_profile,
    ])
    brake_axis = _mean([
        float(components["C"]["brake_scale_response"]),
        brake_profile,
    ])
    causal_axes = {
        "acceleration_response_and_profile": acceleration_axis,
        "brake_response_and_profile": brake_axis,
    }
    causal_score = _strong_worst(list(causal_axes.values()))

    scenario_quality: dict[str, float] = {}
    scenario_quality_components: dict[str, dict[str, float]] = {}
    for sid in base.SCENARIOS:
        values = {
            "accuracy": float(components["A"][sid]),
            "quality": float(components["Q"][sid]),
            "electromechanical_coupling": float(
                components["M"]["electromechanical_coupling"][sid]
            ),
            "motoring_and_generating": float(
                components["M"]["motoring_and_generating"][sid]
            ),
        }
        scenario_quality_components[sid] = values
        scenario_quality[sid] = _strong_worst(list(values.values()))
    robustness_score = _strong_worst(list(scenario_quality.values()))

    transition_components = {
        name: float(value) for name, value in components["D"].items()
    }
    dynamic_score = _strong_worst(list(transition_components.values()))

    groups = {name: float(value) for name, value in result["groups"].items()}
    groups.update({
        "M": mechanism_score,
        "C": causal_score,
        "R": robustness_score,
        "D": dynamic_score,
    })
    groups = {name: round(max(0.0, min(100.0, value)), 9) for name, value in groups.items()}
    total = round(sum(float(result["weights"][name]) * groups[name] for name in result["weights"]), 9)

    result["groups"] = groups
    result["group_scores"] = groups
    result["raw_total"] = total
    result["total"] = total
    result["raw_score"] = total
    result["metrics"]["group_metric_components"] = {
        "A": {
            "score": groups["A"],
            "basis": "direct normalized torque tracking and estimation evidence",
        },
        "Q": {
            "score": groups["Q"],
            "basis": "direct ripple, crest, phase-balance and vehicle-smoothness evidence",
        },
        "M": {
            "aggregation": "0.60*weakest_axis+0.40*axis_mean",
            "axes": mechanism_axes,
        },
        "C": {
            "aggregation": "0.60*weaker_public_input_axis+0.40*axis_mean",
            "axes": causal_axes,
            "acceleration_profile_fidelity": acceleration_profile_rows,
            "brake_profile_fidelity": brake_profile_rows,
        },
        "R": {
            "within_scenario": "0.60*weakest_behavior+0.40*behavior_mean",
            "across_scenarios": "0.60*worst_scenario+0.40*scenario_mean",
            "scenario_components": scenario_quality_components,
            "scenario_quality": scenario_quality,
        },
        "D": {
            "aggregation": "0.60*weaker_transition+0.40*transition_mean",
            "transitions": transition_components,
        },
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--subject", choices=("auto", "candidate", "reference"), default="auto")
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    result = score(evidence, args.evidence, args.subject)
    (args.output_dir / "score.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
