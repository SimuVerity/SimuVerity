"""Current pure-offline score implementation for EXT-XTHERM-PVTES-01."""
from __future__ import annotations

import math
from typing import Any

import numpy as np


TASK_ID = "EXT-XTHERM-PVTES-01"
SCHEMA = "simuverity.ext-xtherm-pvtes-score.v1"
POLICY_ID = "simuverity-101-v1:ext-xtherm-pvtes-01:scoring"
WEIGHTS = {"A": 0.24, "Q": 0.12, "M": 0.20, "C": 0.18, "R": 0.14, "D": 0.12}
ACCURACY_SCENARIOS = (
    "baseline",
    "solar_low",
    "solar_high",
    "ambient_cold",
    "ambient_warm",
    "setpoint_low",
    "setpoint_high",
    "solar_nominal_timing",
    "solar_delayed_3h",
)
ALL_SCENARIOS = ACCURACY_SCENARIOS + (
    "measurement_bias_negative",
    "measurement_bias_positive",
)
PHYSICAL_INPUT_FIELDS = (
    "time_s",
    "solar_irradiance_W_m2",
    "ambient_temperature_degC",
    "room_setpoint_degC",
)


def _above(value: float, bad: float, good: float) -> float:
    if not np.isfinite(value) or value <= bad:
        return 0.0
    if value >= good:
        return 1.0
    return float((value - bad) / (good - bad))


def _below(value: float, good: float, bad: float) -> float:
    if not np.isfinite(value) or value >= bad:
        return 0.0
    if value <= good:
        return 1.0
    return float((bad - value) / (bad - good))


def _corr(left: Any, right: Any) -> float:
    left_array = np.asarray(left)
    right_array = np.asarray(right)
    if left_array.size < 3 or np.ptp(left_array) <= 1e-12 or np.ptp(right_array) <= 1e-12:
        return 0.0
    value = float(np.corrcoef(left_array, right_array)[0, 1])
    return value if np.isfinite(value) else 0.0


def _strict_total(groups: dict[str, float]) -> float:
    if any(float(groups[name]) <= 0.0 for name in WEIGHTS):
        return 0.0
    return 100.0 * math.exp(
        sum(WEIGHTS[name] * math.log(float(groups[name])) for name in WEIGHTS)
    )


def _zero(reason: str, failures: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "task_id": TASK_ID,
        "status": "FAILED",
        "G": 0.0,
        "groups": {name: 0.0 for name in WEIGHTS},
        "total": 0.0,
        "metrics": {},
        "scenarios": [],
        "failure_reasons": list(failures or [{"reason": reason}]),
        "gate": {"reason": reason},
    }


def _accuracy(
    candidate: dict[str, dict[str, np.ndarray]],
    reference: dict[str, dict[str, np.ndarray]],
) -> dict[str, float]:
    detail: dict[str, float] = {}
    for scenario_id in ACCURACY_SCENARIOS:
        if scenario_id not in candidate or scenario_id not in reference:
            detail[scenario_id] = 0.0
            continue
        candidate_row = candidate[scenario_id]
        reference_row = reference[scenario_id]
        values: list[float] = []
        for key, minimum_ranges in (
            ("thermal", np.array([2, 2, 2, 2, 5, 5, 5.0])),
            ("energy", np.array([500, 1e7, 20, 20, 0.5, 0.2])),
            ("control", np.array([0.05, 5e4, 0.5, 5, 10, 2.0])),
        ):
            scale = np.maximum(np.ptp(reference_row[key], axis=0), minimum_ranges)
            normalized_error = (
                np.sqrt(np.mean((candidate_row[key] - reference_row[key]) ** 2, axis=0))
                / scale
            )
            values.extend(_below(float(value), 0.05, 0.50) for value in normalized_error)
        detail[scenario_id] = float(np.mean(values))
    return detail


def _measurement_only_feedback(
    evidence: dict[str, dict[str, np.ndarray]],
) -> tuple[bool, dict[str, Any]]:
    negative = evidence.get("measurement_bias_negative")
    positive = evidence.get("measurement_bias_positive")
    if negative is None or positive is None:
        return False, {"reason": "missing measurement-only pair"}
    if not np.array_equal(negative["time_s"], positive["time_s"]):
        return False, {"reason": "measurement pair time mismatch"}
    time_s = negative["time_s"]
    active = (time_s >= 21600) & (time_s < 43200)
    post = (time_s >= 43200) & (time_s <= 64800)
    if not np.any(active) or not np.any(post):
        return False, {"reason": "measurement intervention evidence windows absent"}

    def delta(array_name: str, column: int, window: np.ndarray) -> float:
        return float(
            np.mean(negative[array_name][window, column])
            - np.mean(positive[array_name][window, column])
        )

    pump_active = delta("control", 1, active)
    blower_active = delta("control", 2, active)
    water_active = delta("energy", 4, active)
    air_active = delta("energy", 5, active)
    zone_post = float(
        np.mean(negative["thermal"][post, :4])
        - np.mean(positive["thermal"][post, :4])
    )
    pump_post = delta("control", 1, post)
    blower_post = delta("control", 2, post)
    checks = {
        "pump_responds_to_measurement_only_bias": pump_active > 5000,
        "blower_responds_to_measurement_only_bias": blower_active > 0.05,
        "water_flow_propagates": water_active > 0.005,
        "air_flow_propagates": air_active > 0.01,
        "physical_zone_state_changed": zone_post > 0.02,
        "post_pulse_state_feedback_correction": pump_post < -1000 or blower_post < -0.01,
    }
    return all(checks.values()), {
        "checks": checks,
        "active_pump_difference_Pa": pump_active,
        "active_blower_difference_kg_s": blower_active,
        "active_water_flow_difference_kg_s": water_active,
        "active_air_flow_difference_kg_s": air_active,
        "post_zone_temperature_difference_degC": zone_post,
        "post_pump_difference_Pa": pump_post,
        "post_blower_difference_kg_s": blower_post,
    }


def _opaque_mechanism(
    evidence: dict[str, dict[str, np.ndarray]],
    observations: dict[str, Any],
) -> tuple[bool, dict[str, Any]]:
    required = {"baseline", "solar_low", "solar_high"}
    if not required.issubset(evidence):
        return False, {"reason": "missing mechanism pairs"}
    baseline = evidence["baseline"]
    solar_low = evidence["solar_low"]
    solar_high = evidence["solar_high"]
    low_energy = np.trapezoid(solar_low["energy"][:, 0], solar_low["time_s"])
    high_energy = np.trapezoid(solar_high["energy"][:, 0], solar_high["time_s"])
    separation = max(
        float(np.max(np.abs(baseline["thermal"][:, left] - baseline["thermal"][:, right])))
        for left in range(4)
        for right in range(left)
    )
    checks = {
        "valve_structure_pass": bool(observations.get("valve_structure_pass", False)),
        "solar_to_pv_pair": bool(high_energy / max(abs(low_energy), 1.0) > 1.5),
        "finite_store_memory": bool(np.ptp(baseline["energy"][:, 1]) > 1e6),
        "liquid_heat_transfer": bool(np.max(np.abs(baseline["energy"][:, 2])) > 1),
        "air_heat_and_flow": bool(np.max(np.abs(baseline["energy"][:, 5])) > 0.05),
        "liquid_flow": bool(np.max(np.abs(baseline["energy"][:, 4])) > 0.05),
        "four_distinct_zone_response": bool(separation > 0.1),
    }
    return all(checks.values()), checks


def _score_core(
    candidate: dict[str, dict[str, np.ndarray]],
    reference: dict[str, dict[str, np.ndarray]],
    observations: dict[str, Any],
    failures: list[dict[str, Any]],
) -> dict[str, Any]:
    if failures:
        return _zero("required_public_container_contract_failed", failures)
    if any(scenario_id not in reference for scenario_id in ACCURACY_SCENARIOS):
        return _zero("invalid_reference_evidence")
    if not candidate:
        return _zero("no_valid_scenario")

    accuracy = _accuracy(candidate, reference)
    accuracy_mean = float(np.mean(list(accuracy.values())))
    robustness = float(min(accuracy.values()))
    if "baseline" not in candidate:
        groups = {"A": accuracy_mean, "Q": 0.0, "M": 0.0, "C": 0.0, "R": robustness, "D": 0.0}
        return {
            "task_id": TASK_ID,
            "G": 1.0,
            "groups": groups,
            "total": 0.0,
            "metrics": {
                "accuracy_by_scenario": accuracy,
                "missing_scenarios": [sid for sid in ACCURACY_SCENARIOS if sid not in candidate],
            },
        }

    baseline = candidate["baseline"]
    thermal = baseline["thermal"]
    energy = baseline["energy"]
    control = baseline["control"]
    quality_checks = [
        float(np.min(thermal[:, index]) >= -20 and np.max(thermal[:, index]) <= 60)
        for index in range(4)
    ]
    quality_checks += [
        float(np.min(thermal[:, 4]) >= -20 and np.max(thermal[:, 4]) <= 150),
        float(np.min(thermal[:, 5]) >= -20 and np.max(thermal[:, 5]) <= 150),
        float(np.min(thermal[:, 6]) >= -40 and np.max(thermal[:, 6]) <= 120),
        float(np.max(np.abs(control[:, 0])) <= 1),
        float(np.min(control[:, 1]) >= -1e-6 and np.max(control[:, 1]) <= 250000),
        float(np.max(np.abs(control[:, 2])) <= 5),
    ]
    quality = float(np.mean(quality_checks))

    zone_separation = max(
        float(np.max(np.abs(thermal[:, left] - thermal[:, right])))
        for left in range(4)
        for right in range(left)
    )
    if "solar_low" in candidate and "solar_high" in candidate:
        low = candidate["solar_low"]
        high = candidate["solar_high"]
        low_energy = np.trapezoid(low["energy"][:, 0], low["time_s"])
        high_energy = np.trapezoid(high["energy"][:, 0], high["time_s"])
        solar_ratio = high_energy / max(abs(low_energy), 1.0)
    else:
        solar_ratio = 0.0
    mechanism_bottlenecks = [
        _above(zone_separation, 0.01, 0.1),
        _above(float(np.ptp(energy[:, 1])), 1e5, 1e6),
        _above(float(solar_ratio), 1.1, 1.5),
        float(np.max(np.abs(energy[:, 2])) > 1),
        float(np.max(np.abs(energy[:, 4])) > 0.05),
        float(np.max(np.abs(energy[:, 5])) > 0.05),
    ]
    copied = all(
        scenario_id in candidate
        and np.array_equal(candidate[scenario_id]["thermal"], thermal)
        for scenario_id in ACCURACY_SCENARIOS[1:]
    )

    trace_state = observations.get("trace_state", "unavailable")
    opaque_mechanism, opaque_mechanism_detail = _opaque_mechanism(candidate, observations)
    measurement_control, measurement_control_detail = _measurement_only_feedback(candidate)
    if trace_state == "transparent":
        mechanism_proof = bool(
            observations.get("mechanism_pass", False)
            and observations.get("valve_structure_pass", False)
        )
        control_proof = bool(observations.get("control_pass", False))
        proof_route = "transparent_typed_domain"
    elif trace_state == "opaque":
        mechanism_proof = opaque_mechanism
        control_proof = measurement_control
        proof_route = "paired_behavioral_equivalence"
    else:
        mechanism_proof = False
        control_proof = False
        proof_route = "unavailable_fail_closed"
    mechanism = 0.0 if copied else min(mechanism_bottlenecks + [float(mechanism_proof)])

    pair_ids = {"setpoint_low", "setpoint_high", "ambient_cold", "ambient_warm"}
    if pair_ids.issubset(candidate):
        low = candidate["setpoint_low"]
        high = candidate["setpoint_high"]
        cold = candidate["ambient_cold"]
        warm = candidate["ambient_warm"]
        setpoint_zone = abs(float(np.mean(high["thermal"][:, :4]) - np.mean(low["thermal"][:, :4])))
        setpoint_pump = abs(float(np.mean(high["control"][:, 1]) - np.mean(low["control"][:, 1])))
        setpoint_blower = abs(float(np.mean(high["control"][:, 2]) - np.mean(low["control"][:, 2])))
        ambient_pump = abs(float(np.mean(cold["control"][:, 1]) - np.mean(warm["control"][:, 1])))
        ambient_blower = abs(float(np.mean(cold["control"][:, 2]) - np.mean(warm["control"][:, 2])))
    else:
        setpoint_zone = setpoint_pump = setpoint_blower = ambient_pump = ambient_blower = 0.0
    mean_zone = np.mean(thermal[:, :4], axis=1)
    error = control[:, 5] - mean_zone
    control_bottlenecks = [
        _above(float(np.ptp(control[:, 1])), 1000, 20000),
        _above(float(np.ptp(control[:, 2])), 0.01, 0.3),
        _above(_corr(control[:, 1], energy[:, 4]), 0.5, 0.9),
        _above(_corr(control[:, 2], energy[:, 5]), 0.5, 0.9),
        _above(_corr(error, control[:, 1]), 0.1, 0.3),
        _above(_corr(error, control[:, 2]), 0.1, 0.3),
        _above(setpoint_zone, 0.2, 1.0),
        max(_above(setpoint_pump, 5000, 20000), _above(setpoint_blower, 0.05, 0.3)),
        max(_above(ambient_pump, 10000, 40000), _above(ambient_blower, 0.05, 0.3)),
    ]
    control_score = min(control_bottlenecks + [float(control_proof)])

    if "solar_nominal_timing" in candidate and "solar_delayed_3h" in candidate:
        timing_separation = float(
            np.max(
                np.abs(
                    candidate["solar_nominal_timing"]["energy"][:, 1]
                    - candidate["solar_delayed_3h"]["energy"][:, 1]
                )
            )
        )
    else:
        timing_separation = 0.0
    dynamics = min(
        _above(timing_separation, 1e5, 1e6),
        float(np.ptp(energy[:, 1]) > 1e6 and np.ptp(thermal[:, 4]) > 1),
    )
    groups = {
        "A": accuracy_mean,
        "Q": quality,
        "M": mechanism,
        "C": control_score,
        "R": robustness,
        "D": dynamics,
    }
    return {
        "task_id": TASK_ID,
        "G": 1.0,
        "groups": groups,
        "total": _strict_total(groups),
        "proof_route": proof_route,
        "opaque_mechanism_equivalence": opaque_mechanism_detail,
        "measurement_only_feedback_equivalence": measurement_control_detail,
        "valve_schema_field": "valve_structure_pass",
        "strict_weighted_geometric": True,
        "epsilon_floor": False,
        "post_total_cap": False,
        "metrics": {
            "accuracy_by_scenario": accuracy,
            "missing_scenarios": [sid for sid in ACCURACY_SCENARIOS if sid not in candidate],
            "zone_separation_degC": zone_separation,
            "solar_pair_pv_energy_ratio": float(solar_ratio),
            "mechanism_behavior_bottlenecks": mechanism_bottlenecks,
            "control_behavior_bottlenecks": control_bottlenecks,
            "setpoint_mean_zone_separation_degC": setpoint_zone,
            "setpoint_mean_pump_separation_Pa": setpoint_pump,
            "setpoint_mean_blower_separation_kg_s": setpoint_blower,
            "ambient_mean_pump_separation_Pa": ambient_pump,
            "timing_store_energy_max_separation_J": timing_separation,
            "copied_all_scenarios": copied,
            "system_observations": observations,
        },
    }


def _score_behavioral(
    candidate: dict[str, dict[str, np.ndarray]],
    reference: dict[str, dict[str, np.ndarray]],
    observations: dict[str, Any],
    candidate_inputs: dict[str, dict[str, Any]],
    failures: list[dict[str, Any]],
) -> dict[str, Any]:
    raw = _score_core(candidate, reference, observations, failures)
    raw_metrics = raw.get("metrics", {})
    accuracy = {
        scenario_id: float(raw_metrics.get("accuracy_by_scenario", {}).get(scenario_id, 0.0))
        for scenario_id in ACCURACY_SCENARIOS
    }
    pair = _measurement_pair_contract(candidate_inputs)
    mechanism = _mechanism_behavior(candidate, raw)
    control = _measurement_behavior(candidate, pair)

    required_scenarios_complete = all(scenario_id in candidate for scenario_id in ALL_SCENARIOS)
    inherited_mechanism = float(raw.get("groups", {}).get("M", 0.0))
    inherited_control = float(raw.get("groups", {}).get("C", 0.0))
    mechanism_pass = inherited_mechanism > 0.0 or bool(mechanism.get("pass"))
    control_pass = inherited_control > 0.0 or bool(control.get("pass"))
    qualifications = {
        "required_scenarios_complete": required_scenarios_complete,
        "system_observations_available": bool(observations),
        "mechanism_core_present": mechanism_pass,
        "closed_loop_control_core_present": control_pass,
    }
    qualified = raw.get("G") == 1.0 and all(qualifications.values())

    groups = {name: float(raw.get("groups", {}).get(name, 0.0)) for name in WEIGHTS}
    if accuracy:
        groups["A"] = float(np.mean(list(accuracy.values())))
        groups["R"] = float(min(accuracy.values()))
    if inherited_mechanism <= 0.0 and mechanism_pass:
        groups["M"] = min(mechanism["mechanism_behavior_bottlenecks"])
    if inherited_control <= 0.0 and control_pass:
        groups["C"] = min(float(value) for value in raw_metrics.get("control_behavior_bottlenecks", []))

    result = dict(raw)
    result.update(
        {
            "schema": SCHEMA,
            "policy_id": POLICY_ID,
            "status": "SCORED" if qualified else "FAILED",
            "G": 1.0 if qualified else 0.0,
            "groups": groups,
            "total": _strict_total(groups) if qualified else 0.0,
            "strict_weighted_geometric": True,
            "epsilon_floor": False,
            "post_total_cap": False,
            "behavioral_causal_qualification": {
                "pass": qualified,
                "checks": qualifications,
                "input_pair": pair,
                "mechanism": mechanism,
                "control": control,
                "structural_mechanism_score": inherited_mechanism,
                "structural_control_score": inherited_control,
                "behavioral_substitution_used": {
                    "mechanism": inherited_mechanism <= 0.0 and mechanism_pass,
                    "control": inherited_control <= 0.0 and control_pass,
                },
            },
            "failure_reasons": list(raw.get("failure_reasons", [])),
        }
    )
    result.setdefault("metrics", {})["accuracy_by_scenario"] = accuracy
    result["metrics"]["accuracy_aggregation"] = "arithmetic_mean"
    result["metrics"]["robustness_aggregation"] = "worst_scenario"
    if not qualified:
        failed = [name for name, value in qualifications.items() if not value]
        if not mechanism.get("checks", {}).get("scenario_outputs_are_distinct", True):
            failed.append("scenario_outputs_are_distinct")
        result["gate"] = {"reason": "public_core_qualification_failed", "failed_checks": failed}
        result["failure_reasons"].append({"reason": "public_core_qualification_failed", "failed_checks": failed})
    return result


def _same_json_number_sequence(left: Any, right: Any) -> bool:
    try:
        return bool(np.array_equal(np.asarray(left, dtype=float), np.asarray(right, dtype=float)))
    except (TypeError, ValueError):
        return False


def _measurement_pair_contract(inputs: dict[str, dict[str, Any]]) -> dict[str, Any]:
    negative = inputs.get("measurement_bias_negative")
    positive = inputs.get("measurement_bias_positive")
    detail: dict[str, Any] = {
        "pair_present": isinstance(negative, dict) and isinstance(positive, dict),
        "physical_inputs_identical": False,
        "bias_only": False,
        "symmetric_opposite_bias": False,
        "active_window_s": [],
        "post_window_s": [],
    }
    if not detail["pair_present"]:
        detail["pass"] = False
        return detail
    physical_equal = all(
        field in negative
        and field in positive
        and _same_json_number_sequence(negative[field], positive[field])
        for field in PHYSICAL_INPUT_FIELDS
    )
    detail["physical_inputs_identical"] = physical_equal
    try:
        time_s = np.asarray(negative["time_s"], dtype=float).reshape(-1)
        negative_bias = np.asarray(negative["thermal_measurement_bias_degC"], dtype=float).reshape(-1)
        positive_bias = np.asarray(positive["thermal_measurement_bias_degC"], dtype=float).reshape(-1)
    except (KeyError, TypeError, ValueError):
        detail["pass"] = False
        return detail
    shape_ok = time_s.size >= 3 and negative_bias.shape == time_s.shape and positive_bias.shape == time_s.shape
    finite = bool(shape_ok and np.all(np.isfinite(time_s)) and np.all(np.isfinite(negative_bias)) and np.all(np.isfinite(positive_bias)))
    symmetric = bool(finite and np.array_equal(negative_bias, -positive_bias))
    active_index = np.flatnonzero(negative_bias < positive_bias) if symmetric else np.asarray([], dtype=int)
    contiguous = bool(active_index.size and np.array_equal(active_index, np.arange(active_index[0], active_index[-1] + 1)))
    outside_zero = bool(
        contiguous
        and np.all(negative_bias[: active_index[0]] == 0)
        and np.all(negative_bias[active_index[-1] + 1 :] == 0)
        and np.all(positive_bias[: active_index[0]] == 0)
        and np.all(positive_bias[active_index[-1] + 1 :] == 0)
    )
    bias_only = bool(
        physical_equal
        and symmetric
        and contiguous
        and outside_zero
        and np.all(negative_bias[active_index] < 0)
        and np.all(positive_bias[active_index] > 0)
    )
    detail.update(
        {
            "symmetric_opposite_bias": symmetric,
            "bias_only": bias_only,
            "input_sample_count": int(time_s.size),
        }
    )
    if bias_only:
        start = float(time_s[active_index[0]])
        end = float(time_s[active_index[-1] + 1]) if active_index[-1] + 1 < time_s.size else float(time_s[active_index[-1]])
        duration = max(end - start, 0.0)
        detail["active_window_s"] = [start, end]
        detail["post_window_s"] = [end, min(float(time_s[-1]), end + duration)]
    detail["pass"] = bias_only
    return detail


def _measurement_behavior(
    evidence: dict[str, dict[str, np.ndarray]], pair: dict[str, Any]
) -> dict[str, Any]:
    negative = evidence.get("measurement_bias_negative")
    positive = evidence.get("measurement_bias_positive")
    if negative is None or positive is None or not pair.get("pass"):
        return {"pass": False, "reason": "validated measurement intervention pair unavailable", "checks": {}}
    if not np.array_equal(negative["time_s"], positive["time_s"]):
        return {"pass": False, "reason": "measurement evidence time axes differ", "checks": {}}
    time_s = np.asarray(negative["time_s"], dtype=float)
    start, end = pair["active_window_s"]
    post_start, post_end = pair["post_window_s"]
    active = (time_s >= start) & (time_s < end)
    post = (time_s >= post_start) & (time_s <= post_end)
    if not np.any(active) or not np.any(post):
        return {"pass": False, "reason": "measurement intervention evidence windows absent", "checks": {}}

    def delta(array_name: str, column: int, window: np.ndarray) -> float:
        return float(
            np.mean(negative[array_name][window, column])
            - np.mean(positive[array_name][window, column])
        )

    metrics = {
        "active_pump_difference_Pa": delta("control", 1, active),
        "active_blower_difference_kg_s": delta("control", 2, active),
        "active_water_flow_difference_kg_s": delta("energy", 4, active),
        "active_air_flow_difference_kg_s": delta("energy", 5, active),
        "post_zone_temperature_difference_degC": float(np.mean(negative["thermal"][post, :4]) - np.mean(positive["thermal"][post, :4])),
        "post_pump_difference_Pa": delta("control", 1, post),
        "post_blower_difference_kg_s": delta("control", 2, post),
    }
    checks = {
        "negative_bias_increases_pump_command": metrics["active_pump_difference_Pa"] > 0.0,
        "negative_bias_increases_blower_command": metrics["active_blower_difference_kg_s"] > 0.0,
        "pump_response_propagates_to_water_flow": metrics["active_water_flow_difference_kg_s"] > 0.0,
        "blower_response_propagates_to_air_flow": metrics["active_air_flow_difference_kg_s"] > 0.0,
        "real_zone_state_retains_expected_signed_difference": metrics["post_zone_temperature_difference_degC"] > 0.0,
        "post_pulse_feedback_correction_has_expected_direction": metrics["post_pump_difference_Pa"] < 0.0 or metrics["post_blower_difference_kg_s"] < 0.0,
    }
    return {"pass": all(checks.values()), "checks": checks, "metrics": metrics}


def _mechanism_behavior(
    evidence: dict[str, dict[str, np.ndarray]], raw: dict[str, Any]
) -> dict[str, Any]:
    baseline = evidence.get("baseline")
    metrics = raw.get("metrics", {})
    bottlenecks = [float(value) for value in metrics.get("mechanism_behavior_bottlenecks", [])]
    if baseline is None:
        return {"pass": False, "reason": "baseline evidence absent", "checks": {}}
    valve_range = float(np.ptp(baseline["control"][:, 0]))
    water_flow_range = float(np.ptp(baseline["energy"][:, 4]))
    valve_water_correlation = abs(float(_corr(baseline["control"][:, 0], baseline["energy"][:, 4])))
    checks = {
        "all_mechanism_behavior_bottlenecks_positive": bool(bottlenecks and min(bottlenecks) > 0.0),
        "flow_valve_signal_dynamic": valve_range > 0.005,
        "water_flow_path_dynamic": water_flow_range > 0.05,
        "scenario_outputs_are_distinct": not bool(metrics.get("copied_all_scenarios", True)),
    }
    return {
        "pass": all(checks.values()),
        "checks": checks,
        "flow_valve_signal_range": valve_range,
        "water_flow_range_kg_s": water_flow_range,
        "absolute_valve_water_flow_correlation": valve_water_correlation,
        "mechanism_behavior_bottlenecks": bottlenecks,
    }


def _public_rows(evidence: dict[str, Any]) -> tuple[
    dict[str, dict[str, np.ndarray]],
    dict[str, dict[str, Any]],
    list[dict[str, Any]],
]:
    if evidence.get("schema") != "simuverity.ext-xtherm-pvtes-public-evidence.v1":
        raise ValueError("Unexpected public evidence schema")
    rows = evidence.get("scenarios")
    if not isinstance(rows, list):
        raise TypeError("Public evidence scenarios must be a list")
    scenario_data: dict[str, dict[str, np.ndarray]] = {}
    scenario_inputs: dict[str, dict[str, Any]] = {}
    failures: list[dict[str, Any]] = []
    seen: list[str] = []
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            failures.append({"reason": "invalid_scenario_row"})
            continue
        scenario_id = str(row["id"])
        seen.append(scenario_id)
        payload = row.get("evidence")
        scenario_input = row.get("input")
        if row.get("status") != "EXTRACTED" or not isinstance(payload, dict):
            failures.append({"scenario_id": scenario_id, "reason": str(row.get("failure") or "extraction_failed")})
            continue
        if not isinstance(scenario_input, dict):
            failures.append({"scenario_id": scenario_id, "reason": "public_input_missing"})
            continue
        try:
            scenario_data[scenario_id] = {
                "time_s": np.asarray(payload["time_s"], dtype=float).reshape(-1),
                "thermal": np.asarray(payload["thermal"], dtype=float),
                "energy": np.asarray(payload["energy"], dtype=float),
                "control": np.asarray(payload["control"], dtype=float),
            }
        except (KeyError, TypeError, ValueError) as exc:
            failures.append({"scenario_id": scenario_id, "reason": f"invalid_public_arrays: {exc}"})
            continue
        scenario_inputs[scenario_id] = dict(scenario_input)
    if tuple(seen) != ALL_SCENARIOS:
        failures.append({"reason": "scenario_set_or_order_mismatch"})
    return scenario_data, scenario_inputs, failures


def score_public_evidence(
    candidate_evidence: dict[str, Any],
    reference_evidence: dict[str, Any],
    *,
    subject: str = "candidate",
) -> dict[str, Any]:
    """Apply the current formula to public candidate and reference evidence."""
    if subject not in {"candidate", "reference"}:
        raise ValueError("Scoring subject must be candidate or reference")
    if candidate_evidence.get("role") != subject:
        raise ValueError("Evidence role does not match the scoring subject")
    if reference_evidence.get("role") != "reference":
        raise ValueError("Reference evidence must declare the reference role")
    candidate, candidate_inputs, failures = _public_rows(candidate_evidence)
    reference, _, reference_failures = _public_rows(reference_evidence)
    failures.extend({"reference": item} for item in reference_failures)
    observations = candidate_evidence.get("system_observations")
    if not isinstance(observations, dict):
        failures.append({"reason": "system_observations_missing"})
        observations = {}
    result = _score_behavioral(candidate, reference, observations, candidate_inputs, failures)
    accuracy = result.get("metrics", {}).get("accuracy_by_scenario", {})
    result["scenarios"] = [
        {
            "id": scenario_id,
            "status": "SCORED" if scenario_id in candidate else "FAILED",
            "valid": scenario_id in candidate,
            "accuracy": accuracy.get(scenario_id),
        }
        for scenario_id in ALL_SCENARIOS
    ]
    return result
