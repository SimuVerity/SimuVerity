"""Pure-offline scorer for the wheel-loader task.

Causal contrast is computed within same-unit pathway families.  The precharge
intervention requires both accumulator-pressure response and downstream
regenerative dynamics.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
import ext_xmech_wheelloader_coord_01_scoring_core as source


EVALUATION_POLICY_ID = "simuverity-101-v1:ext-xmech-wheelloader-coord-01:scoring"


def _aligned(metrics: dict[str, dict], name: str, field: str) -> tuple[np.ndarray, np.ndarray]:
    nominal = metrics["nominal_y_cycle"]
    other = metrics[name]
    stop = min(nominal["_time"][-1], other["_time"][-1])
    grid = np.arange(0.0, stop + 1e-9, 0.05)
    left_source = nominal[field]
    right_source = other[field]
    left = np.column_stack([
        np.interp(grid, nominal["_time"], left_source[:, index])
        for index in range(left_source.shape[1])
    ])
    right = np.column_stack([
        np.interp(grid, other["_time"], right_source[:, index])
        for index in range(right_source.shape[1])
    ])
    return left, right


def _family_contrast(left: np.ndarray, right: np.ndarray) -> float:
    """Dimensionless contrast for channels that share one physical unit."""
    return source._relative_contrast(np.asarray(left, float), np.asarray(right, float))


def _response_utility(contrast: float) -> float:
    # Apply the task's causal-response boundaries.
    return source.utility(contrast, 0.025, 0.002, lower=False)


def _unavailable() -> dict:
    return {"available": False, "relative_contrast": 0.0, "utility": 0.0}


def causal_contrasts(metrics: dict[str, dict]) -> dict:
    nominal = metrics["nominal_y_cycle"]
    result: dict[str, dict] = {}

    # Tire friction acts through chassis-relative wheel slip.  All four
    # compared channels have the same public unit (km/h).
    other = metrics["low_friction"]
    motion_ok = (
        np.all(np.asarray(nominal["availability"]["motion"], bool)[[0, 4, 5, 6, 7]])
        and np.all(np.asarray(other["availability"]["motion"], bool)[[0, 4, 5, 6, 7]])
    )
    if motion_ok:
        left, right = _aligned(metrics, "low_friction", "_motion")
        left_slip = left[:, 4:8] - left[:, [0]]
        right_slip = right[:, 4:8] - right[:, [0]]
        contrast = _family_contrast(left_slip, right_slip)
        result["low_friction"] = {
            "available": True,
            "signal": "wheel_speed_minus_vehicle_speed",
            "relative_contrast": contrast,
            "utility": _response_utility(contrast),
        }
    else:
        result["low_friction"] = _unavailable()

    # Payload must be observable in both force and pressure families.  The
    # two unit families are evaluated independently to avoid scale dominance.
    other = metrics["heavy_payload"]
    hydraulic_ok = (
        np.all(np.asarray(nominal["availability"]["hydraulic"], bool)[:6])
        and np.all(np.asarray(other["availability"]["hydraulic"], bool)[:6])
    )
    if hydraulic_ok:
        left, right = _aligned(metrics, "heavy_payload", "_hydraulic")
        force = _family_contrast(left[:, :2], right[:, :2])
        pressure = _family_contrast(left[:, 2:6], right[:, 2:6])
        force_u = _response_utility(force)
        pressure_u = _response_utility(pressure)
        result["heavy_payload"] = {
            "available": True,
            "signal": "hydraulic_force_and_pressure",
            "family_contrasts": {"force": force, "pressure": pressure},
            "family_utilities": {"force": force_u, "pressure": pressure_u},
            "relative_contrast": min(force, pressure),
            "utility": min(force_u, pressure_u),
        }
    else:
        result["heavy_payload"] = _unavailable()

    # Pump derating must affect both delivered cylinder flow and pump
    # differential pressure.  Arithmetic combination is within this one
    # intervention, avoiding an unrelated local zero becoming the whole C
    # group while still withholding half credit from a one-family response.
    other = metrics["pump_derate"]
    pump_ok = (
        np.all(np.asarray(nominal["availability"]["hydraulic"], bool)[6:9])
        and np.all(np.asarray(other["availability"]["hydraulic"], bool)[6:9])
    )
    if pump_ok:
        left, right = _aligned(metrics, "pump_derate", "_hydraulic")
        flow = _family_contrast(left[:, 6:8], right[:, 6:8])
        pressure = _family_contrast(left[:, 8:9], right[:, 8:9])
        flow_u = _response_utility(flow)
        pressure_u = _response_utility(pressure)
        result["pump_derate"] = {
            "available": True,
            "signal": "implement_flow_and_pump_pressure",
            "family_contrasts": {"flow": flow, "pump_dp": pressure},
            "family_utilities": {"flow": flow_u, "pump_dp": pressure_u},
            "relative_contrast": min(flow, pressure),
            "utility": 0.5 * (flow_u + pressure_u),
        }
    else:
        result["pump_derate"] = _unavailable()

    # A precharge change has two distinct obligations: the accumulator
    # pressure must respond, and at least one downstream regenerative-energy
    # quantity must respond.  A constant pressure offset alone is not proof
    # that precharge participates in the accumulator/HRB dynamics.
    other = metrics["low_hrb_precharge"]
    hrb_ok = (
        np.all(np.asarray(nominal["availability"]["powertrain"], bool)[5:8])
        and np.all(np.asarray(other["availability"]["powertrain"], bool)[5:8])
    )
    if hrb_ok:
        left, right = _aligned(metrics, "low_hrb_precharge", "_power")
        hrb_power = _family_contrast(left[:, 5:6], right[:, 5:6])
        pressure = _family_contrast(left[:, 6:7], right[:, 6:7])
        displacement = _family_contrast(left[:, 7:8], right[:, 7:8])
        pressure_u = _response_utility(pressure)
        hrb_power_u = _response_utility(hrb_power)
        displacement_u = _response_utility(displacement)
        dynamic_u = max(hrb_power_u, displacement_u)
        result["low_hrb_precharge"] = {
            "available": True,
            "signal": "accumulator_pressure_and_regenerative_dynamics",
            "family_contrasts": {
                "hrb_power": hrb_power,
                "accumulator_pressure": pressure,
                "hydro_pump_displacement": displacement,
            },
            "family_utilities": {
                "hrb_power": hrb_power_u,
                "accumulator_pressure": pressure_u,
                "hydro_pump_displacement": displacement_u,
                "regenerative_dynamic_response": dynamic_u,
            },
            "relative_contrast": min(pressure, max(hrb_power, displacement)),
            "utility": 0.5 * (pressure_u + dynamic_u),
        }
    else:
        result["low_hrb_precharge"] = _unavailable()

    return result


def score_evidence(evidence: dict) -> dict:
    result = source.score_evidence(evidence)
    result["evaluation_policy_id"] = EVALUATION_POLICY_ID
    if result["G"] != 1:
        return result

    scenarios = {
        str(item.get("id", "")): item
        for item in evidence.get("scenarios", [])
        if isinstance(item, dict)
    }
    metrics = {name: source.scenario_metrics(scenarios[name]) for name in source.EXPECTED}
    contrasts = causal_contrasts(metrics)
    control = min(item["utility"] for item in contrasts.values())
    groups = dict(result["groups_normalized"])
    groups["C"] = control
    raw = source.strict_weighted_geometric(1, groups, source.WEIGHTS)

    result["groups"] = {name: 100.0 * value for name, value in groups.items()}
    result["groups_normalized"] = groups
    result["raw_score"] = raw
    result["admission_pass"] = bool(raw >= 90.0)
    result["causal_contrasts"] = contrasts
    result["causal_aggregation"] = {
        "scope": "same_unit_pathway_families",
        "reason": "same-unit pathway families prevent mixed-unit dominance and distinguish a precharge pressure offset from regenerative dynamic response",
    }
    if control == 0.0 and "paired_environment_interventions_not_observable" not in result["failure_reasons"]:
        result["failure_reasons"].append("paired_environment_interventions_not_observable")
    return result


def shortcut_sanity(evidence: dict) -> dict:
    checks: dict[str, bool] = {}
    base = score_evidence(evidence)

    mutant = copy.deepcopy(evidence)
    for item in mutant["scenarios"]:
        rows = len(item["time_s"])
        for name, width in source.WIDTHS.items():
            item[name] = np.zeros((rows, width)).tolist()
    checks["constant_outputs_mechanism_zero"] = score_evidence(mutant)["groups"]["M"] == 0.0

    mutant = copy.deepcopy(evidence)
    nominal = next(item for item in mutant["scenarios"] if item["id"] == "nominal_y_cycle")
    for item in mutant["scenarios"]:
        if item is nominal:
            continue
        grid = np.asarray(item["time_s"], float)
        source_time = np.asarray(nominal["time_s"], float)
        for name, width in source.WIDTHS.items():
            source = np.asarray(nominal[name], float)
            item[name] = np.column_stack([
                np.interp(grid, source_time, source[:, index]) for index in range(width)
            ]).tolist()
    checks["environment_ignored_control_zero"] = score_evidence(mutant)["groups"]["C"] == 0.0

    mutant = copy.deepcopy(evidence)
    for item in mutant["scenarios"]:
        item["container_availability"]["wheel_loader_hydraulic_response"] = [False] * 9
    checks["missing_hydraulics_mechanism_zero"] = score_evidence(mutant)["groups"]["M"] == 0.0

    mutant = copy.deepcopy(evidence)
    for item in mutant["scenarios"]:
        item["container_availability"]["wheel_loader_powertrain_response"] = [False] * 8
    checks["missing_powertrain_mechanism_zero"] = score_evidence(mutant)["groups"]["M"] == 0.0

    mutant = copy.deepcopy(evidence)
    mutant["scenarios"][0]["container_availability"]["wheel_loader_motion_response"][9] = False
    partial = score_evidence(mutant)
    checks["single_channel_partial_not_gate_failure"] = partial["G"] == 1 and partial["raw_score"] < base["raw_score"]

    # A direct precharge-to-pressure offset with unchanged HRB power and
    # displacement may receive pressure credit, but never full C credit.
    mutant = copy.deepcopy(evidence)
    nominal = next(item for item in mutant["scenarios"] if item["id"] == "nominal_y_cycle")
    precharge = next(item for item in mutant["scenarios"] if item["id"] == "low_hrb_precharge")
    grid = np.asarray(precharge["time_s"], float)
    source_time = np.asarray(nominal["time_s"], float)
    source = np.asarray(nominal["wheel_loader_powertrain_response"], float)
    replay = np.column_stack([
        np.interp(grid, source_time, source[:, index]) for index in range(source.shape[1])
    ])
    replay[:, 6] -= 1.601325
    precharge["wheel_loader_powertrain_response"] = replay.tolist()
    pressure_only = score_evidence(mutant)
    checks["precharge_pressure_only_control_not_full"] = 0.0 < pressure_only["groups"]["C"] <= 50.0

    return {"task_id": source.TASK_ID, "checks": checks, "pass": all(checks.values())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--shortcut-output", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output.write_text(
        json.dumps(score_evidence(evidence), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    if args.shortcut_output:
        result = shortcut_sanity(evidence)
        if not result["pass"]:
            raise AssertionError("shortcut_sanity failed")
        args.shortcut_output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
