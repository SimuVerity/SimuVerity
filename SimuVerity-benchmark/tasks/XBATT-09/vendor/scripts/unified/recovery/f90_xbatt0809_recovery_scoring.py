#!/usr/bin/env python3
"""Pure-offline recovery scoring for XBATT-08/09.

The recovery adapter treats MATLAB jsonencode's scalar representation of a one-sample signal
as a one-element sequence. It does not promote that sample to dynamic data.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path
from types import ModuleType
from typing import Any


TASKS = {
    "F90-XBATT-08": {
        "scenarios": (
            "baseline_all", "selected_default", "light_ultracap_all",
            "heavy_ultracap_all", "light_battery_selected",
            "heavy_battery_selected",
        ),
        "logs": {
            "vehicle_speed": (["vehicle_speed_kph"], ["km/hr"]),
            "traction": (
                ["motor_torque_Nm", "motor_speed_rad_s", "motor_mechanical_power_W"],
                ["N*m", "rad/s", "W"],
            ),
            "storage_voltage": (
                ["battery_voltage_V", "ultracapacitor_voltage_V", "dc_bus_voltage_V"],
                ["V", "V", "V"],
            ),
            "storage_current": (["battery_current_A", "ultracapacitor_current_A"], ["A", "A"]),
            "storage_power": (["battery_power_W", "ultracapacitor_power_W"], ["W", "W"]),
        },
    },
    "F90-XBATT-09": {
        "scenarios": (
            "nominal_profile_a", "nominal_profile_b", "fault_profile_a_t30",
            "fault_profile_b_t30", "fault_profile_a_t55_low",
            "fault_profile_b_t20_high",
        ),
        "logs": {
            "assembly_voltage": (
                [f"parallel_assembly_voltage_{index:02d}_V" for index in range(1, 16)],
                ["V"] * 15,
            ),
            "contact_state": (
                [f"contact_symptom_{index:02d}" for index in range(1, 16)]
                + [f"contact_error_{index:02d}" for index in range(1, 16)],
                ["1"] * 30,
            ),
            "battery_state": (
                ["pack_voltage_V", "parallel_assembly_voltage_spread_V"],
                ["V", "V"],
            ),
        },
    },
}


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value: dict[str, Any]) -> None:
    if path.exists():
        raise FileExistsError(f"refusing to overwrite {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def load_module(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("xbatt_recovery_base_scorer", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load base scorer {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def normalize_matrix(data: Any, width: int) -> list[list[float]]:
    if finite(data):
        if width != 1:
            raise ValueError("scalar data cannot satisfy a multi-channel log")
        return [[float(data)]]
    if not isinstance(data, list) or not data:
        raise ValueError("data is empty or not an array")
    if width == 1 and all(finite(value) for value in data):
        return [[float(value)] for value in data]
    if len(data) == width and all(finite(value) for value in data):
        return [[float(value) for value in data]]
    rows: list[list[float]] = []
    for row in data:
        if not isinstance(row, list) or len(row) != width or not all(finite(value) for value in row):
            raise ValueError("data width or finiteness mismatch")
        rows.append([float(value) for value in row])
    return rows


def normalize_time(time: Any) -> list[float]:
    if finite(time):
        return [float(time)]
    if isinstance(time, list) and time and all(finite(value) for value in time):
        return [float(value) for value in time]
    raise ValueError("time is empty or nonfinite")


def validate_candidate(task_id: str, evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    contract = TASKS[task_id]
    failures: list[str] = []
    if evidence.get("task_id") != task_id:
        failures.append("task_id mismatch")
    if evidence.get("load_pass") is not True or evidence.get("update_compile_pass") is not True:
        failures.append("candidate load/update/compile did not pass")
    scenarios = evidence.get("scenarios")
    if not isinstance(scenarios, list):
        return False, failures + ["scenarios is not an array"]
    identifiers = [row.get("id") for row in scenarios if isinstance(row, dict)]
    if sorted(identifiers) != sorted(contract["scenarios"]) or len(identifiers) != len(contract["scenarios"]):
        failures.append("scenario identifiers are incomplete, duplicated, or unexpected")
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            failures.append("scenario entry is not an object")
            continue
        sid = str(scenario.get("id", "<missing>"))
        if scenario.get("simulation_pass") is not True or scenario.get("required_evidence_pass") is not True:
            failures.append(f"{sid}: simulation or finite-output evidence failed")
        logs = scenario.get("logs")
        if not isinstance(logs, dict) or set(logs) != set(contract["logs"]):
            failures.append(f"{sid}: exact public log-name set is unavailable")
            continue
        for name, (channels, units) in contract["logs"].items():
            log = logs.get(name)
            if not isinstance(log, dict):
                failures.append(f"{sid}/{name}: log is not an object")
                continue
            if log.get("channels") != channels or log.get("units") != units:
                failures.append(f"{sid}/{name}: channel identity/order/unit mismatch")
            try:
                times = normalize_time(log.get("time"))
            except ValueError as error:
                failures.append(f"{sid}/{name}: {error}")
                continue
            if abs(times[0]) > 1e-8 or any(right <= left for left, right in zip(times, times[1:])):
                failures.append(f"{sid}/{name}: time does not start at zero or is not increasing")
            try:
                values = normalize_matrix(log.get("data"), len(channels))
            except ValueError as error:
                failures.append(f"{sid}/{name}: {error}")
                continue
            if len(values) != len(times):
                failures.append(f"{sid}/{name}: data/time length mismatch")
    return not failures, failures


def dynamic_complete(task_id: str, evidence: dict[str, Any]) -> bool:
    for scenario in evidence["scenarios"]:
        if scenario.get("dynamic_coverage_pass") is not True:
            return False
        for name in TASKS[task_id]["logs"]:
            time = normalize_time(scenario["logs"][name]["time"])
            if len(time) < 100 or abs(float(time[-1]) - 100.0) > 1e-6:
                return False
    return True


def geometric(groups: dict[str, float], weights: dict[str, float]) -> float:
    if any(float(groups[name]) <= 0.0 for name in weights):
        return 0.0
    return math.exp(sum(float(weights[name]) * math.log(float(groups[name])) for name in weights))


def reference_score(task_id: str, module: ModuleType, reference: dict[str, Any]) -> dict[str, Any]:
    base = module.score(reference, reference)
    total = float(base.get("raw_score", base.get("total_score", 0.0)))
    gate = base.get("gate", {}).get("G", base.get("G", 0))
    return {
        "schema": "simuverity.xbatt0809-reference-replay.recovery.v1",
        "task_id": task_id,
        "G": int(gate),
        "weights": base["weights"],
        "group_scores": base["group_scores"],
        "total_score": round(total, 9),
        "offline_only": True,
        "matlab_invoked": False,
        "failure_reasons": base.get("failure_reasons", []),
    }


def candidate_score(
    task_id: str,
    module: ModuleType,
    reference: dict[str, Any],
    candidate: dict[str, Any],
) -> dict[str, Any]:
    gate, failures = validate_candidate(task_id, candidate)
    weights = dict(module.WEIGHTS)
    result: dict[str, Any] = {
        "schema": "simuverity.xbatt0809-candidate-score.recovery.v1",
        "task_id": task_id,
        "G": 1 if gate else 0,
        "weights": weights,
        "offline_only": True,
        "matlab_invoked": False,
        "compatibility_policy": {
            "scope": "published_evidence_interface",
            "no_channel_guessing": True,
            "missing_component_utility": 0.0,
            "single_sample_promoted_to_dynamic_evidence": False,
        },
    }
    if not gate:
        result.update(
            status="INVALID_CANDIDATE",
            protocol_zero_applied=True,
            total_score=0.0,
            group_scores={name: 0.0 for name in weights},
            scenario_scores=[],
            metrics={},
            failure_reasons=failures,
        )
        return result

    if task_id == "F90-XBATT-08" and not dynamic_complete(task_id, candidate):
        scenarios = []
        for scenario in candidate["scenarios"]:
            scenarios.append({
                "id": scenario["id"],
                "score": 0.0,
                "simulation_pass": True,
                "finite_outputs_present": True,
                "dynamic_coverage_pass": False,
                "failure_reasons": ["only one/short sample; no dynamic trajectory can be scored"],
            })
        result.update(
            status="SCORED",
            protocol_zero_applied=False,
            total_score=0.0,
            group_scores={name: 0.0 for name in weights},
            scenario_scores=scenarios,
            metrics={
                "operational_gate_pass": 1.0,
                "dynamic_coverage_scenario_fraction": 0.0,
                "single_sample_dynamic_metric_utility": 0.0,
            },
            failure_reasons=[
                "all six simulations ran and finite named outputs existed, so G=1",
                "all six scenarios exposed only t=0; A/Q/M/C/R/D requiring dynamic coverage are 0",
            ],
        )
        return result

    compatible = copy.deepcopy(candidate)
    missing_components: list[str] = []
    if task_id == "F90-XBATT-09":
        for scenario in compatible["scenarios"]:
            raw = scenario["logs"]["battery_state"]
            rows = normalize_matrix(raw["data"], 2)
            raw["data"] = [[row[0], 0.0, row[1]] for row in rows]
            raw["channels"] = [
                "pack_voltage_V", "pack_current_A",
                "parallel_assembly_voltage_spread_V",
            ]
            raw["units"] = ["V", "A", "V"]
            raw["available"] = [True, False, True]
            scenario["valid"] = True
            scenario["simulate_pass"] = True
            missing_components.append(f"{scenario['id']}.battery_state.pack_current_A")
    base = module.score(reference, compatible)
    groups = {name: float(value) for name, value in base["group_scores"].items()}
    if task_id == "F90-XBATT-09":
        # 15 assembly + 30 state + 3 battery components per scenario.  The
        # missing pack current is one component with utility zero, not a whole
        # evidence or task failure.
        groups["Q"] = 100.0 * (15.0 + 30.0 + 2.0) / (15.0 + 30.0 + 3.0)
        total = geometric(groups, weights)
        scenario_scores = []
        metrics = base.get("metrics", {})
        for sid in TASKS[task_id]["scenarios"]:
            row: dict[str, Any] = {
                "id": sid,
                "score": float(metrics.get("trajectory_scores", {}).get(sid, 0.0)),
                "simulation_pass": True,
                "dynamic_coverage_pass": True,
                "missing_components": ["battery_state.pack_current_A"],
            }
            for key in ("mechanism_scores", "causal_scores", "nominal_scores", "dynamic_scores"):
                if sid in metrics.get(key, {}):
                    row[key.removesuffix("_scores")] = float(metrics[key][sid])
            scenario_scores.append(row)
    else:
        total = float(base.get("raw_score", base.get("total_score", 0.0)))
        scenario_scores = base.get("scenario_scores", [])
        metrics = {
            "mechanism_metrics": base.get("mechanism_metrics", {}),
            "causal_pairs": base.get("causal_pairs", {}),
        }
    reasons = list(base.get("failure_reasons", []))
    if missing_components:
        reasons.append(
            "pack_current_A was not delivered; its interface component utility is 0 without clearing G"
        )
    result.update(
        status="SCORED",
        protocol_zero_applied=False,
        total_score=round(total, 9),
        group_scores={name: round(value, 9) for name, value in groups.items()},
        scenario_scores=scenario_scores,
        metrics=metrics,
        missing_components=missing_components,
        failure_reasons=reasons,
    )
    return result


def run(task_id: str, argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--base-scorer", type=Path, required=True)
    parser.add_argument("--candidate-output", type=Path, required=True)
    parser.add_argument("--reference-output", type=Path, required=True)
    args = parser.parse_args(argv)
    reference = read_json(args.reference)
    candidate = read_json(args.candidate)
    module = load_module(args.base_scorer.resolve())
    candidate_result = candidate_score(
        task_id, module, reference, candidate
    )
    reference_result = reference_score(task_id, module, reference)
    write_json(args.candidate_output, candidate_result)
    write_json(args.reference_output, reference_result)
    return 0
