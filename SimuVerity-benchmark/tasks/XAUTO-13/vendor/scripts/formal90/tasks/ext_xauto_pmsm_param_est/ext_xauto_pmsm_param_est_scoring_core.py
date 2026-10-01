"""Pure-offline scorer for the PMSM hidden-measurement contract."""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from ext_scoring_common import strict_weighted_geometric

TASK_ID = "EXT-XAUTO-PMSM-PARAM-EST"
EVIDENCE_SCHEMA = "simuverity.ext-xauto-pmsm-param-est-evidence.v1"
CONTRACT_ID = "hidden-measurement"
WEIGHTS = {"A": 0.30, "Q": 0.10, "M": 0.20, "C": 0.18, "R": 0.12, "D": 0.10}


def _number(value: Any, default: float = math.inf) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default


def _low(value: Any, full: float, zero: float) -> float:
    x = _number(value)
    if not math.isfinite(x) or zero <= full:
        return 0.0
    return max(0.0, min(1.0, (zero - x) / (zero - full)))


def _high(value: Any, zero: float, full: float) -> float:
    x = _number(value, -math.inf)
    if not math.isfinite(x) or full <= zero:
        return 0.0
    return max(0.0, min(1.0, (x - zero) / (full - zero)))


def _average(values: Iterable[float]) -> float:
    materialized = list(values)
    return sum(materialized) / len(materialized) if materialized else 0.0


def _accuracy(item: dict[str, Any]) -> float:
    return _average(
        (
            _low(item.get("mean_tail_relative_error"), 0.06, 0.55),
            _low(item.get("worst_tail_relative_error"), 0.15, 1.10),
        )
    )


def _quality(item: dict[str, Any]) -> float:
    checks = (
        bool(item.get("finite")),
        _number(item.get("coverage_fraction"), 0.0) >= 0.999,
        item.get("estimate_width") == 6,
        item.get("measurement_width") == 4,
        item.get("command_width") == 2,
        item.get("diagnostic_width") == 2,
    )
    return 1.0 if all(checks) else 0.0


def _mechanism(item: dict[str, Any]) -> float:
    # Candidate receives command and measurement, so those input amplitudes
    # cannot earn mechanism credit. Credit comes from estimator evolution,
    # signed coupling, and non-decorative diagnostics.
    components = (
        _high(item.get("estimate_motion_normalized"), 0.002, 0.08),
        _high(item.get("estimate_trace_span_normalized"), 0.005, 0.12),
        _high(item.get("innovation_early_rms"), 1e-7, 1e-3),
        1.0 if bool(item.get("tail_estimate_within_public_envelope")) else 0.0,
        1.0 if bool(item.get("signed_cross_coupling")) else 0.0,
    )
    return _average(components)


def _replay_utility(scenarios: list[dict[str, Any]]) -> float:
    scales = (0.015, 40e-6, 15e-6, 80e-6, 0.0025, 0.15)
    ratios: list[float] = []
    for left_index in range(len(scenarios)):
        for right_index in range(left_index + 1, len(scenarios)):
            left = scenarios[left_index]
            right = scenarios[right_index]
            p1, p2 = left.get("plant_signature", []), right.get("plant_signature", [])
            e1, e2 = left.get("estimate_signature", []), right.get("estimate_signature", [])
            if not (len(p1) == len(p2) == len(e1) == len(e2) == 6):
                return 0.0
            plant_delta = math.sqrt(
                sum(((_number(a) - _number(b)) / scale) ** 2 for a, b, scale in zip(p1, p2, scales))
            )
            if not math.isfinite(plant_delta):
                return 0.0
            if plant_delta > 1e-8:
                estimate_delta = math.sqrt(
                    sum(((_number(a) - _number(b)) / scale) ** 2 for a, b, scale in zip(e1, e2, scales))
                )
                if not math.isfinite(estimate_delta):
                    return 0.0
                ratios.append(estimate_delta / plant_delta)
    return _high(min(ratios) if ratios else 0.0, 0.01, 0.35)


def _role_attestation(evidence: dict[str, Any]) -> tuple[bool, str]:
    role = evidence.get("role")
    common = (
        bool(evidence.get("input_boundary_valid"))
        and bool(evidence.get("truth_fields_absent"))
    )
    if role == "reference":
        valid = (
            common
            and evidence.get("adapter_mode") == "reference_native_measurement_taps"
            and evidence.get("causality_basis") == "reference_native_feedback"
            and bool(evidence.get("official_measurement_pack_generated"))
            and not bool(evidence.get("candidate_contract_only"))
        )
        return valid, "reference_native_feedback"
    if role == "candidate":
        valid = (
            common
            and evidence.get("adapter_mode") == "candidate_measurement_contract"
            and evidence.get("causality_basis") == "held_measurement_counterfactual"
            and bool(evidence.get("official_measurement_pack_ready"))
            and bool(evidence.get("candidate_contract_only"))
        )
        return valid, "held_measurement_counterfactual"
    return False, "unknown"


def _measurement_causality(evidence: dict[str, Any], item: dict[str, Any]) -> float:
    if evidence.get("role") == "reference":
        # The reference adapter supplies native feedback rather than the candidate contract.
        return 1.0
    if not bool(item.get("counterfactual_valid")):
        return 0.0
    trace = _high(item.get("counterfactual_estimate_trace_delta"), 1e-5, 0.02)
    tail = _high(item.get("counterfactual_estimate_tail_delta"), 1e-5, 0.02)
    return min(trace, tail)


def _estimate_available(item: dict[str, Any]) -> bool:
    return bool(item.get("estimate_available", item.get("estimate_width") == 6)) and item.get("estimate_width") == 6


def _diagnostic_available(item: dict[str, Any]) -> bool:
    return bool(item.get("diagnostic_available", item.get("diagnostic_width") == 2)) and item.get("diagnostic_width") == 2


def _simulation_valid(item: dict[str, Any]) -> bool:
    return bool(item.get("simulation_valid", item.get("valid", False)))


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    scenarios_value = evidence.get("scenarios", [])
    scenarios = scenarios_value if isinstance(scenarios_value, list) else []
    role_valid, role_basis = _role_attestation(evidence)
    checks = {
        "schema": evidence.get("schema") == EVIDENCE_SCHEMA,
        "task": evidence.get("task_id") == TASK_ID,
        "contract_id": evidence.get("contract_id") == CONTRACT_ID,
        "stages": all(bool(evidence.get(name)) for name in ("load_ok", "update_ok", "compile_ok")),
        "scenario_count": evidence.get("scenario_count") == 4 and len(scenarios) == 4,
        "scenario_simulation_validity": len(scenarios) == 4 and all(_simulation_valid(item) for item in scenarios),
        "role_and_input_boundary": role_valid,
    }
    gate = 1.0 if all(checks.values()) else 0.0

    if not scenarios:
        groups = {name: 0.0 for name in WEIGHTS}
        accuracy_values: list[float] = []
        measurement_values: list[float] = []
        replay = 0.0
        copy_guard = 0.0
        causal_base = 0.0
    else:
        accuracy_values = [_accuracy(item) if _estimate_available(item) else 0.0 for item in scenarios]
        quality_values = [_quality(item) if _estimate_available(item) and _diagnostic_available(item) else 0.0 for item in scenarios]
        mechanism_values = [_mechanism(item) if _estimate_available(item) and _diagnostic_available(item) else 0.0 for item in scenarios]
        # Numerically exact direct wiring is rejected here. Near-truth traces
        # are not rejected merely for being accurate; they must also pass the
        # independent held-measurement causal intervention below.
        copy_guard = min(
            _low(item.get("exact_truth_copy_fraction", 1.0), 0.01, 0.90) if _estimate_available(item) else 0.0
            for item in scenarios
        )
        replay = _replay_utility(scenarios)
        causal_base = _average(
            _high(item.get("convergence_improvement"), 0.8, 1.5)
            for item in scenarios
        )
        measurement_values = [_measurement_causality(evidence, item) if _estimate_available(item) and _diagnostic_available(item) else 0.0 for item in scenarios]
        dynamics = [
            _high(item.get("convergence_improvement"), 1.0, 2.5) if _estimate_available(item) else 0.0
            for item in scenarios
        ]
        groups = {
            "A": _average(accuracy_values),
            "Q": min(quality_values),
            "M": _average(mechanism_values),
            "C": min(copy_guard, replay, causal_base, min(measurement_values)),
            "R": min(accuracy_values),
            "D": min(dynamics),
        }

    total = strict_weighted_geometric(gate, groups, WEIGHTS)
    return {
        "schema": "simuverity.ext-score.v1",
        "task_id": TASK_ID,
        "evaluation_policy_id": "simuverity-101-v1:ext-xauto-pmsm-param-est:scoring",
        "G": round(100.0 * gate, 6),
        "groups": {name: round(100.0 * value, 6) for name, value in groups.items()},
        "weights": WEIGHTS,
        "total_raw": round(total, 6),
        "raw_threshold": 90,
        "normalize_threshold_to_100": False,
        "aggregation": "G_times_strict_weighted_geometric_mean",
        "epsilon_floor": False,
        "post_total_cap": False,
        "partial_output_policy": "missing estimates or diagnostics zero only dependent metrics; no truth reconstruction",
        "gate_checks": checks,
        "causality_audit": {
            "role_basis": role_basis,
            "role_attested": role_valid,
            "copy_guard": round(100.0 * copy_guard, 6),
            "cross_plant_replay_utility": round(100.0 * replay, 6),
            "convergence_causal_base": round(100.0 * causal_base, 6),
            "measurement_counterfactual_worst": round(100.0 * min(measurement_values), 6) if measurement_values else 0.0,
        },
        "scenario_results": [
            {
                "id": item.get("id"),
                "valid": bool(item.get("valid")),
                "simulation_valid": _simulation_valid(item),
                "estimate_available": _estimate_available(item),
                "diagnostic_available": _diagnostic_available(item),
                "accuracy": round(100.0 * (_accuracy(item) if _estimate_available(item) else 0.0), 6),
                "mechanism": round(100.0 * (_mechanism(item) if _estimate_available(item) and _diagnostic_available(item) else 0.0), 6),
                "measurement_causality": round(100.0 * (_measurement_causality(evidence, item) if _estimate_available(item) and _diagnostic_available(item) else 0.0), 6),
                "mean_tail_relative_error": _number(item.get("mean_tail_relative_error")),
                "worst_tail_relative_error": _number(item.get("worst_tail_relative_error")),
                "convergence_improvement": _number(item.get("convergence_improvement"), 0.0),
            }
            for item in scenarios
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    evidence = json.loads(arguments.evidence.read_text(encoding="utf-8"))
    result = score(evidence)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
