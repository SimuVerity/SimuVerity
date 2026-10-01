#!/usr/bin/env python3
"""Pure-offline scorer for F90-XBATT-09.

The scorer reads fixed evidence JSON only.  It never imports MATLAB, opens a
model, or starts a simulation.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any


TASK_ID = "F90-XBATT-09"
SCENARIO_IDS = (
    "nominal_profile_a",
    "nominal_profile_b",
    "fault_profile_a_t30",
    "fault_profile_b_t30",
    "fault_profile_a_t55_low",
    "fault_profile_b_t20_high",
)
FAULT_IDS = SCENARIO_IDS[2:]
ASSEMBLY_CHANNELS = [f"parallel_assembly_voltage_{index:02d}_V" for index in range(1, 16)]
CONTACT_CHANNELS = [f"contact_symptom_{index:02d}" for index in range(1, 16)] + [
    f"contact_error_{index:02d}" for index in range(1, 16)
]
BATTERY_CHANNELS = [
    "pack_voltage_V",
    "pack_current_A",
    "parallel_assembly_voltage_spread_V",
]
LOG_SPEC = {
    "assembly_voltage": (ASSEMBLY_CHANNELS, ["V"] * 15),
    "contact_state": (CONTACT_CHANNELS, ["1"] * 30),
    "battery_state": (BATTERY_CHANNELS, ["V", "A", "V"]),
}
WEIGHTS = {"A": 0.18, "Q": 0.10, "M": 0.22, "C": 0.20, "R": 0.12, "D": 0.18}


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def matrix(data: Any, width: int) -> list[list[float]]:
    if not isinstance(data, list):
        raise ValueError("data is not an array")
    rows: list[list[float]] = []
    for row in data:
        if width == 1 and finite(row):
            rows.append([float(row)])
        elif isinstance(row, list) and len(row) == width and all(finite(item) for item in row):
            rows.append([float(item) for item in row])
        else:
            raise ValueError("data width or finiteness mismatch")
    return rows


def validate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get("task_id") != TASK_ID:
        failures.append("task_id mismatch")
    scenarios = evidence.get("scenarios")
    if not isinstance(scenarios, list):
        return False, failures + ["scenarios is not an array"]
    identifiers = [item.get("id") for item in scenarios if isinstance(item, dict)]
    if sorted(identifiers) != sorted(SCENARIO_IDS) or len(identifiers) != len(SCENARIO_IDS):
        failures.append("official scenario identifiers are incomplete, duplicated, or unexpected")
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            failures.append("scenario entry is not an object")
            continue
        sid = str(scenario.get("id", "<missing>"))
        if scenario.get("valid") is not True or scenario.get("simulate_pass") is not True:
            failures.append(f"{sid}: evaluator validity/simulation flag is not true")
        logs = scenario.get("logs")
        if not isinstance(logs, dict) or set(logs) != set(LOG_SPEC):
            failures.append(f"{sid}: required log set mismatch")
            continue
        end_times: list[float] = []
        for name, (channels, units) in LOG_SPEC.items():
            log = logs.get(name)
            if not isinstance(log, dict):
                failures.append(f"{sid}/{name}: log is not an object")
                continue
            if log.get("channels") != channels:
                failures.append(f"{sid}/{name}: public channel order mismatch")
            if log.get("units") != units:
                failures.append(f"{sid}/{name}: unit order mismatch")
            time = log.get("time")
            if not isinstance(time, list) or len(time) < 100 or not all(finite(item) for item in time):
                failures.append(f"{sid}/{name}: time vector is short or nonfinite")
                continue
            times = [float(item) for item in time]
            if abs(times[0]) > 1e-9 or abs(times[-1] - 100.0) > 1e-6:
                failures.append(f"{sid}/{name}: time coverage is not 0--100 s")
            if any(right <= left for left, right in zip(times, times[1:])):
                failures.append(f"{sid}/{name}: time is not strictly increasing")
            try:
                values = matrix(log.get("data"), len(channels))
            except ValueError as exception:
                failures.append(f"{sid}/{name}: {exception}")
                continue
            if len(values) != len(times):
                failures.append(f"{sid}/{name}: data and time lengths differ")
            end_times.append(times[-1])
        if end_times and max(end_times) - min(end_times) > 1e-6:
            failures.append(f"{sid}: logs do not share one terminal time")
    return not failures, failures


def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {item["id"]: item for item in evidence["scenarios"]}


def resample(log: dict[str, Any], channel: int, *, logical: bool = False) -> list[float]:
    times = [float(value) for value in log["time"]]
    values = [row[channel] for row in matrix(log["data"], len(log["channels"]))]
    target = [index * 0.5 for index in range(201)]
    result: list[float] = []
    cursor = 0
    for sample in target:
        while cursor + 1 < len(times) and times[cursor + 1] <= sample:
            cursor += 1
        if logical or cursor + 1 >= len(times):
            result.append(float(values[cursor]))
            continue
        left, right = times[cursor], times[cursor + 1]
        fraction = (sample - left) / max(right - left, 1e-12)
        result.append(float(values[cursor] + fraction * (values[cursor + 1] - values[cursor])))
    return result


def rms(values: list[float]) -> float:
    return math.sqrt(sum(value * value for value in values) / max(len(values), 1))


def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)


def trajectory_similarity(reference: list[float], candidate: list[float], sharpness: float = 4.0) -> float:
    scale = max(rms(reference), max(abs(value) for value in reference) * 0.05, 1e-9)
    error = rms([actual - expected for expected, actual in zip(reference, candidate)])
    return 100.0 * math.exp(-sharpness * error / scale)


def ratio_utility(reference: float, candidate: float) -> float:
    if reference <= 1e-12:
        return 100.0 if candidate <= 1e-12 else 0.0
    if candidate <= 1e-12:
        return 0.0
    ratio = candidate / reference
    return 100.0 * min(ratio, 1.0 / ratio)


def first_time(values: list[float]) -> float:
    for index, value in enumerate(values):
        if value >= 0.5:
            return index * 0.5
    return -1.0


def time_utility(reference: float, candidate: float, scale: float = 5.0) -> float:
    if reference < 0:
        return 100.0 if candidate < 0 else 0.0
    if candidate < 0:
        return 0.0
    return 100.0 * math.exp(-abs(candidate - reference) / scale)


def derive(scenario: dict[str, Any]) -> dict[str, Any]:
    voltage = [resample(scenario["logs"]["assembly_voltage"], index) for index in range(15)]
    symptom = [resample(scenario["logs"]["contact_state"], index, logical=True) for index in range(15)]
    error = [resample(scenario["logs"]["contact_state"], index + 15, logical=True) for index in range(15)]
    target_delta = [
        abs(voltage[0][sample] - mean([voltage[index][sample] for index in range(1, 15)]))
        for sample in range(201)
    ]
    fault_time = float(scenario["input"]["contact_fault_time_s"])
    fault_index = min(max(int(round(fault_time / 0.5)), 0), 200)
    return {
        "voltage": voltage,
        "symptom": symptom,
        "error": error,
        "target_delta": target_delta,
        "post_delta": target_delta[fault_index:],
        "symptom_time": first_time(symptom[0]),
        "error_time": first_time(error[0]),
        "max_other_symptom": max(max(channel) for channel in symptom[1:]),
        "max_other_error": max(max(channel) for channel in error[1:]),
        "max_pre_error": max(error[0][:fault_index] or [0.0]),
    }


def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    gate, failures = validate(candidate)
    result: dict[str, Any] = {
        "schema": "simuverity.f90-xbatt09-score.v1",
        "task_id": TASK_ID,
        "status": "SCORED" if gate else "INVALID_EVIDENCE",
        "G": 1 if gate else 0,
        "failure_reasons": failures,
        "weights": WEIGHTS,
        "offline_only": True,
        "matlab_invoked": False,
    }
    if not gate:
        result.update(total_score=0.0, group_scores={name: 0.0 for name in WEIGHTS}, metrics={})
        return result

    ref = scenario_map(reference)
    cand = scenario_map(candidate)
    ref_derived = {sid: derive(ref[sid]) for sid in SCENARIO_IDS}
    cand_derived = {sid: derive(cand[sid]) for sid in SCENARIO_IDS}

    trajectory_scores: dict[str, float] = {}
    for sid in SCENARIO_IDS:
        scores: list[float] = []
        for channel in range(15):
            scores.append(trajectory_similarity(
                ref_derived[sid]["voltage"][channel], cand_derived[sid]["voltage"][channel]
            ))
        for channel in (0, 2):
            scores.append(trajectory_similarity(
                resample(ref[sid]["logs"]["battery_state"], channel),
                resample(cand[sid]["logs"]["battery_state"], channel),
            ))
        trajectory_scores[sid] = 0.6 * mean(scores) + 0.4 * min(scores)

    mechanism_scores: dict[str, float] = {}
    causal_scores: dict[str, float] = {}
    dynamic_scores: dict[str, float] = {}
    for sid in FAULT_IDS:
        r = ref_derived[sid]
        c = cand_derived[sid]
        magnitude = ratio_utility(max(r["post_delta"]), max(c["post_delta"]))
        shape = trajectory_similarity(r["target_delta"], c["target_delta"], sharpness=2.5)
        mechanism_scores[sid] = math.sqrt(max(magnitude, 0.0) * max(shape, 0.0))
        symptom_time = time_utility(r["symptom_time"], c["symptom_time"])
        error_time = time_utility(r["error_time"], c["error_time"])
        localization = 100.0 * max(0.0, 1.0 - max(c["max_other_symptom"], c["max_other_error"]))
        preclean = 100.0 * max(0.0, 1.0 - c["max_pre_error"])
        # Correct assembly localization is the central causal requirement of this
        # task.  Treating every assembly as faulty is not a partly-correct
        # detector, even when the target timing happens to match the reference.
        causal_scores[sid] = (
            0.15 * symptom_time
            + 0.15 * error_time
            + 0.60 * localization
            + 0.10 * preclean
        )
        r_gap = max(r["error_time"] - r["symptom_time"], 0.0)
        c_gap = max(c["error_time"] - c["symptom_time"], 0.0)
        qualification = ratio_utility(r_gap, c_gap)
        post_fault_delay = time_utility(
            r["symptom_time"] - float(ref[sid]["input"]["contact_fault_time_s"]),
            c["symptom_time"] - float(cand[sid]["input"]["contact_fault_time_s"]),
            scale=3.0,
        )
        dynamic_scores[sid] = mean([qualification, post_fault_delay, error_time])

    nominal_scores: dict[str, float] = {}
    for sid in SCENARIO_IDS[:2]:
        c = cand_derived[sid]
        no_flags = 100.0 * max(
            0.0,
            1.0 - max(max(max(channel) for channel in c["symptom"]), max(max(channel) for channel in c["error"])),
        )
        physical_quiet = trajectory_similarity(
            ref_derived[sid]["target_delta"], c["target_delta"], sharpness=3.0
        )
        nominal_scores[sid] = mean([no_flags, physical_quiet])

    group_scores = {
        "A": 0.65 * mean(list(trajectory_scores.values())) + 0.35 * min(trajectory_scores.values()),
        "Q": 100.0,
        "M": 0.65 * mean(list(mechanism_scores.values())) + 0.35 * min(mechanism_scores.values()),
        "C": 0.70 * mean(list(causal_scores.values())) + 0.30 * min(causal_scores.values()),
        "R": min([*mechanism_scores.values(), *causal_scores.values(), *nominal_scores.values()]),
        "D": 0.65 * mean(list(dynamic_scores.values())) + 0.35 * min(dynamic_scores.values()),
    }
    if any(value <= 0.0 for value in group_scores.values()):
        total = 0.0
    else:
        total = math.exp(sum(WEIGHTS[name] * math.log(group_scores[name]) for name in WEIGHTS))

    low = [f"group {name} below 50" for name, value in group_scores.items() if value < 50.0]
    result.update(
        total_score=round(total, 9),
        group_scores={name: round(value, 9) for name, value in group_scores.items()},
        metrics={
            "trajectory_scores": trajectory_scores,
            "mechanism_scores": mechanism_scores,
            "causal_scores": causal_scores,
            "nominal_scores": nominal_scores,
            "dynamic_scores": dynamic_scores,
        },
        failure_reasons=low,
    )
    return result


def fixed_outputs_mutant(reference: dict[str, Any]) -> dict[str, Any]:
    mutant = copy.deepcopy(reference)
    source = scenario_map(mutant)["nominal_profile_a"]["logs"]
    for scenario in mutant["scenarios"]:
        scenario["logs"] = copy.deepcopy(source)
    return mutant


def direct_flag_mutant(reference: dict[str, Any]) -> dict[str, Any]:
    mutant = fixed_outputs_mutant(reference)
    for scenario in mutant["scenarios"]:
        if not scenario["input"]["contact_fault_enable"]:
            continue
        fault_time = float(scenario["input"]["contact_fault_time_s"])
        contact = scenario["logs"]["contact_state"]
        for row_index, time in enumerate(contact["time"]):
            if float(time) >= fault_time:
                contact["data"][row_index][0] = 1.0
                contact["data"][row_index][15] = 1.0
    return mutant


def unqualified_mutant(reference: dict[str, Any]) -> dict[str, Any]:
    mutant = copy.deepcopy(reference)
    for scenario in mutant["scenarios"]:
        if not scenario["input"]["contact_fault_enable"]:
            continue
        contact = scenario["logs"]["contact_state"]["data"]
        for row in contact:
            row[15] = row[0]
    return mutant


def all_assemblies_mutant(reference: dict[str, Any]) -> dict[str, Any]:
    mutant = copy.deepcopy(reference)
    for scenario in mutant["scenarios"]:
        if not scenario["input"]["contact_fault_enable"]:
            continue
        for row in scenario["logs"]["contact_state"]["data"]:
            if row[0] >= 0.5:
                for index in range(15):
                    row[index] = 1.0
            if row[15] >= 0.5:
                for index in range(15, 30):
                    row[index] = 1.0
    return mutant


def shortcut_sanity(reference: dict[str, Any]) -> dict[str, Any]:
    missing = copy.deepcopy(reference)
    del missing["scenarios"][0]["logs"]["contact_state"]
    cases = {
        "missing_required_log": missing,
        "fixed_outputs_across_scenarios": fixed_outputs_mutant(reference),
        "direct_fault_flag_without_physical_response": direct_flag_mutant(reference),
        "unqualified_error_equals_symptom": unqualified_mutant(reference),
        "all_assemblies_flagged": all_assemblies_mutant(reference),
    }
    scored = {name: score(reference, evidence) for name, evidence in cases.items()}
    maximum = max(float(item["total_score"]) for item in scored.values())
    return {
        "schema": "simuverity.f90-xbatt09-shortcut-sanity.v1",
        "task_id": TASK_ID,
        "case_count": len(scored),
        "cases": {
            name: {
                "G": item["G"],
                "total_score": item["total_score"],
                "group_scores": item["group_scores"],
                "failure_reasons": item["failure_reasons"],
            }
            for name, item in scored.items()
        },
        "maximum_raw_score": maximum,
        "all_below_85": maximum < 85.0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--shortcut-sanity", action="store_true")
    args = parser.parse_args()

    reference = load_json(args.reference)
    if args.shortcut_sanity:
        output = shortcut_sanity(reference)
    else:
        if args.candidate is None:
            parser.error("--candidate is required unless --shortcut-sanity is used")
        candidate = load_json(args.candidate)
        output = score(reference, candidate)
        write_json(args.output, output)
    print(json.dumps(output, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
