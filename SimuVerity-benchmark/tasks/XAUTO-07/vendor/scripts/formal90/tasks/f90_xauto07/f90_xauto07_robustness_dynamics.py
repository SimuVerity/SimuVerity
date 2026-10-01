#!/usr/bin/env python3
"""Task-local scoring for F90-XAUTO-07 evidence.

R measures retention relative to the nominal scenario, while D uses three
independently timed transitions.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import f90_xauto07_group_metrics as group_metrics


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _strong_worst(values: list[float]) -> float:
    return 0.60 * min(values) + 0.40 * _mean(values) if values else 0.0


def _retention(value: float, nominal: float) -> float:
    """Return bounded percentage retention; an absent nominal earns no credit."""
    if nominal <= 0.0:
        return 0.0
    return 100.0 * min(1.0, max(0.0, value) / nominal)


def _retention_rows(
    components: dict[str, Any], scenario_ids: list[str]
) -> tuple[dict[str, dict[str, float]], dict[str, float]]:
    nominal_id = scenario_ids[0]
    nominal = {
        "accuracy": float(components["A"][nominal_id]),
        "quality": float(components["Q"][nominal_id]),
        "electromechanical_coupling": float(
            components["M"]["electromechanical_coupling"][nominal_id]
        ),
    }
    rows: dict[str, dict[str, float]] = {}
    scores: dict[str, float] = {}
    for sid in scenario_ids:
        axes = {
            "accuracy_retention": _retention(
                float(components["A"][sid]), nominal["accuracy"]
            ),
            "quality_retention": _retention(
                float(components["Q"][sid]), nominal["quality"]
            ),
            "electromechanical_coupling_retention": _retention(
                float(components["M"]["electromechanical_coupling"][sid]),
                nominal["electromechanical_coupling"],
            ),
            # Modes is already a per-scenario preservation score (0 or 100).
            "motoring_and_generating_preserved": float(
                components["M"]["motoring_and_generating"][sid]
            ),
        }
        rows[sid] = axes
        scores[sid] = _mean(list(axes.values()))
    return rows, scores


def _delay_components(
    derived: dict[str, dict[str, Any]], scenario_ids: list[str]
) -> dict[str, float]:
    nominal = derived[scenario_ids[0]]
    reduced_braking = derived[scenario_ids[2]]
    low = group_metrics.base.low
    return {
        "nominal_startup_torque_delay": low(
            float(nominal["startup_torque_delay_s"]), 0.02, 0.25
        ),
        "nominal_brake_generating_delay": low(
            float(nominal["brake_generating_delay_s"]), 0.02, 0.25
        ),
        "reduced_braking_brake_generating_delay": low(
            float(reduced_braking["brake_generating_delay_s"]), 0.02, 0.25
        ),
    }


def score(
    evidence: dict[str, Any],
    evidence_path: Path,
    requested_subject: str = "auto",
    context: dict[str, Any] | None = None,
    loaded_override: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    result = group_metrics.score(
        evidence, evidence_path, requested_subject, context, loaded_override
    )
    result["schema"] = "simuverity.f90-xauto07-offline-score.v1"
    result["scorer_implementation"] = "simuverity-101-v1:f90-xauto-07:scoring"
    if result.get("G") != 1 or not result.get("scoring_completed"):
        return result

    scenario_ids = list(group_metrics.base.SCENARIOS)
    components = result["metrics"]["group_components"]
    derived = {
        sid: result["scenarios"][sid]["derived_metrics"] for sid in scenario_ids
    }

    retention_axes, scenario_retention = _retention_rows(
        components, scenario_ids
    )
    robustness_score = _strong_worst(list(scenario_retention.values()))

    delay_components = _delay_components(derived, scenario_ids)
    dynamic_score = _strong_worst(list(delay_components.values()))

    groups = {name: float(value) for name, value in result["groups"].items()}
    groups.update({"R": robustness_score, "D": dynamic_score})
    groups = {
        name: round(max(0.0, min(100.0, value)), 9)
        for name, value in groups.items()
    }
    total = round(
        sum(float(result["weights"][name]) * groups[name] for name in result["weights"]),
        9,
    )

    result["groups"] = groups
    result["group_scores"] = groups
    result["raw_total"] = total
    result["total"] = total
    result["raw_score"] = total
    result["metrics"]["robustness_dynamic_components"] = {
        "A": {"score": groups["A"], "source": "accuracy components"},
        "Q": {"score": groups["Q"], "source": "quality components"},
        "M": {
            "score": groups["M"],
            "aggregation": "0.60*weakest_axis+0.40*axis_mean",
        },
        "C": {
            "score": groups["C"],
            "aggregation": "0.60*weaker_public_input_axis+0.40*axis_mean",
        },
        "R": {
            "within_scenario": "arithmetic_mean_of_retention_axes",
            "across_scenarios": "0.60*worst_scenario+0.40*scenario_mean",
            "nominal_scenario": scenario_ids[0],
            "scenario_retention_axes": retention_axes,
            "scenario_retention": scenario_retention,
        },
        "D": {
            "aggregation": "0.60*worst_timing_utility+0.40*timing_utility_mean",
            "timing_utilities": delay_components,
        },
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--subject", choices=("auto", "candidate", "reference"), default="auto"
    )
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    result = score(evidence, args.evidence, args.subject)
    (args.output_dir / "score.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
