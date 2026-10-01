"""Pure-offline dedicated scorer for F90-XAERO-02."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XAERO-02'
SCENARIO_IDS = ('baseline', 'wide_waypoints', 'compact_waypoints', 'crosswind_positive', 'crosswind_negative_low_speed')
LOG_SPEC = {'flight_state': (['position_x_m', 'position_y_m', 'position_z_m', 'velocity_x_mps', 'velocity_y_mps', 'velocity_z_mps', 'body_rate_p_radps', 'body_rate_q_radps', 'body_rate_r_radps', 'airspeed_mps'], ['m', 'm', 'm', 'm/s', 'm/s', 'm/s', 'rad/s', 'rad/s', 'rad/s', 'm/s']), 'tracking_state': (['reference_position_x_m', 'reference_position_y_m', 'reference_position_z_m', 'tracking_error_x_m', 'tracking_error_y_m', 'tracking_error_z_m', 'active_waypoint_index'], ['m', 'm', 'm', 'm', 'm', 'm', '1']), 'actuator_state': (['left_aileron_deflection_rad', 'right_aileron_deflection_rad', 'left_elevator_deflection_rad', 'right_elevator_deflection_rad', 'rudder_deflection_rad', 'horizontal_tail_trim_rad', 'left_motor_angular_speed_radps', 'right_motor_angular_speed_radps'], ['rad', 'rad', 'rad', 'rad', 'rad', 'rad', 'rad/s', 'rad/s'])}
WEIGHTS = {'A': 0.24, 'Q': 0.1, 'M': 0.22, 'C': 0.18, 'R': 0.14, 'D': 0.12}

def read_json(path: Path) -> dict[str, Any]:
    with path.open('r', encoding='utf-8') as handle:
        return json.load(handle)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def matrix(value: Any, width: int) -> list[list[float]]:
    if not isinstance(value, list):
        raise ValueError('data is not an array')
    rows: list[list[float]] = []
    for row in value:
        if width == 1 and finite(row):
            rows.append([float(row)])
        elif isinstance(row, list) and len(row) == width and all((finite(item) for item in row)):
            rows.append([float(item) for item in row])
        else:
            raise ValueError('data width or finiteness mismatch')
    return rows

def validate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return (False, failures + ['scenarios is not an array'])
    identifiers = [item.get('id') for item in scenarios if isinstance(item, dict)]
    if len(identifiers) != len(SCENARIO_IDS) or sorted(identifiers) != sorted(SCENARIO_IDS):
        failures.append('official scenario identifiers are incomplete, duplicated, or unexpected')
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            failures.append('scenario entry is not an object')
            continue
        sid = str(scenario.get('id', '<missing>'))
        if scenario.get('valid') is not True or scenario.get('simulate_pass') is not True:
            failures.append(f'{sid}: evaluator validity/simulation flag is not true')
        logs = scenario.get('logs')
        if not isinstance(logs, dict) or set(logs) != set(LOG_SPEC):
            failures.append(f'{sid}: required log set mismatch')
            continue
        for name, (channels, units) in LOG_SPEC.items():
            log = logs.get(name)
            if not isinstance(log, dict):
                failures.append(f'{sid}/{name}: log is not an object')
                continue
            if log.get('format') != 'Timeseries':
                failures.append(f'{sid}/{name}: format mismatch')
            if log.get('channels') != channels:
                failures.append(f'{sid}/{name}: public channel order mismatch')
            if log.get('units') != units:
                failures.append(f'{sid}/{name}: public unit order mismatch')
            time = log.get('time')
            if not isinstance(time, list) or len(time) < 250 or (not all((finite(item) for item in time))):
                failures.append(f'{sid}/{name}: time vector is short or nonfinite')
                continue
            times = [float(item) for item in time]
            if abs(times[0]) > 1e-09 or abs(times[-1] - 60.0) > 1e-06:
                failures.append(f'{sid}/{name}: time coverage is not 0--60 s')
            if any((right <= left for left, right in zip(times, times[1:]))):
                failures.append(f'{sid}/{name}: time is not strictly increasing')
            try:
                values = matrix(log.get('data'), len(channels))
            except ValueError as exception:
                failures.append(f'{sid}/{name}: {exception}')
                continue
            if len(values) != len(times):
                failures.append(f'{sid}/{name}: data and time lengths differ')
    return (not failures, failures)

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(item['id']): item for item in evidence['scenarios']}

def column(scenario: dict[str, Any], log_name: str, index: int) -> list[float]:
    log = scenario['logs'][log_name]
    values = matrix(log['data'], len(log['channels']))
    return [row[index] for row in values]

def flatten_columns(scenario: dict[str, Any], log_name: str, indices: list[int]) -> list[float]:
    result: list[float] = []
    for index in indices:
        result.extend(column(scenario, log_name, index))
    return result

def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def difference(left: list[float], right: list[float]) -> list[float]:
    return [a - b for a, b in zip(left, right)]

def derivative(values: list[float], dt: float=0.2) -> list[float]:
    return [(right - left) / dt for left, right in zip(values, values[1:])]

def similarity(reference: list[float], candidate: list[float], sharpness: float=4.0) -> float:
    if len(reference) != len(candidate) or not reference:
        return 0.0
    scale = max(rms(reference), max((abs(value) for value in reference)) * 0.05, 1e-09)
    error = rms([actual - expected for expected, actual in zip(reference, candidate)])
    return 100.0 * math.exp(-sharpness * error / scale)

def magnitude_similarity(reference: list[float], candidate: list[float]) -> float:
    expected = rms(reference)
    actual = rms(candidate)
    if expected <= 1e-10:
        return 100.0 if actual <= 1e-10 else 0.0
    if actual <= 1e-12:
        return 0.0
    ratio = actual / expected
    return 100.0 * min(ratio, 1.0 / ratio)

def group_trajectory_score(reference: dict[str, Any], candidate: dict[str, Any], log: str, indices: list[int]) -> float:
    scores = [similarity(column(reference, log, index), column(candidate, log, index)) for index in indices]
    return 0.7 * mean(scores) + 0.3 * min(scores)

def intervention_score(reference: dict[str, dict[str, Any]], candidate: dict[str, dict[str, Any]], target: str, log: str, indices: list[int]) -> float:
    ref_delta = difference(flatten_columns(reference[target], log, indices), flatten_columns(reference['baseline'], log, indices))
    cand_delta = difference(flatten_columns(candidate[target], log, indices), flatten_columns(candidate['baseline'], log, indices))
    return 0.65 * similarity(ref_delta, cand_delta, 3.0) + 0.35 * magnitude_similarity(ref_delta, cand_delta)

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    gate, failures = validate(candidate)
    result: dict[str, Any] = {'schema': 'simuverity.f90-xaero02-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1 if gate else 0, 'validation_failures': failures, 'weights': WEIGHTS}
    if not gate:
        result.update({'group_scores': {name: 0.0 for name in WEIGHTS}, 'per_scenario': {}, 'metrics': {}, 'raw_total': 0.0, 'total': 0.0})
        return result
    ref = scenario_map(reference)
    cand = scenario_map(candidate)
    per_scenario: dict[str, dict[str, float]] = {}
    for sid in SCENARIO_IDS:
        flight = group_trajectory_score(ref[sid], cand[sid], 'flight_state', list(range(10)))
        tracking = group_trajectory_score(ref[sid], cand[sid], 'tracking_state', list(range(6)))
        actuator = group_trajectory_score(ref[sid], cand[sid], 'actuator_state', list(range(8)))
        dynamic_scores: list[float] = []
        for log_name, indices in (('flight_state', [3, 4, 5, 6, 7, 8, 9]), ('actuator_state', list(range(8)))):
            for index in indices:
                dynamic_scores.append(similarity(derivative(column(ref[sid], log_name, index)), derivative(column(cand[sid], log_name, index)), 2.5))
        waypoint = similarity(column(ref[sid], 'tracking_state', 6), column(cand[sid], 'tracking_state', 6), 5.0)
        per_scenario[sid] = {'flight_trajectory': flight, 'tracking_trajectory': tracking, 'actuator_trajectory': actuator, 'dynamic_response': 0.8 * mean(dynamic_scores) + 0.2 * min(dynamic_scores), 'waypoint_sequence': waypoint, 'combined': 0.42 * flight + 0.28 * tracking + 0.2 * actuator + 0.1 * waypoint}
    scenario_combined = [per_scenario[sid]['combined'] for sid in SCENARIO_IDS]
    a_score = 0.65 * mean([0.65 * per_scenario[sid]['flight_trajectory'] + 0.35 * per_scenario[sid]['tracking_trajectory'] for sid in SCENARIO_IDS]) + 0.35 * min(scenario_combined)
    smoothness_scores: list[float] = []
    for sid in SCENARIO_IDS:
        for log_name, indices in (('flight_state', list(range(3, 10))), ('actuator_state', list(range(8)))):
            for index in indices:
                smoothness_scores.append(magnitude_similarity(derivative(column(ref[sid], log_name, index)), derivative(column(cand[sid], log_name, index))))
    q_score = 0.8 * mean(smoothness_scores) + 0.2 * min(smoothness_scores)
    interventions: dict[str, float] = {}
    for target in SCENARIO_IDS[1:]:
        state_effect = intervention_score(ref, cand, target, 'flight_state', list(range(10)))
        tracking_effect = intervention_score(ref, cand, target, 'tracking_state', list(range(7)))
        actuator_effect = intervention_score(ref, cand, target, 'actuator_state', list(range(8)))
        interventions[target] = 0.4 * state_effect + 0.25 * tracking_effect + 0.35 * actuator_effect
    m_score = 0.6 * mean(list(interventions.values())) + 0.4 * min(interventions.values())
    causal_scores: list[float] = []
    for sid in SCENARIO_IDS:
        causal_scores.append(0.55 * per_scenario[sid]['tracking_trajectory'] + 0.45 * per_scenario[sid]['actuator_trajectory'])
    c_score = 0.55 * mean(causal_scores) + 0.25 * min(causal_scores) + 0.2 * min(interventions.values())
    r_score = min(scenario_combined)
    dynamic = [per_scenario[sid]['dynamic_response'] for sid in SCENARIO_IDS]
    waypoint = [per_scenario[sid]['waypoint_sequence'] for sid in SCENARIO_IDS]
    d_score = 0.55 * mean(dynamic) + 0.25 * min(dynamic) + 0.2 * min(waypoint)
    groups = {'A': a_score, 'Q': q_score, 'M': m_score, 'C': c_score, 'R': r_score, 'D': d_score}
    if any((value <= 0.0 for value in groups.values())):
        raw_total = 0.0
    else:
        raw_total = 100.0
        for name, weight in WEIGHTS.items():
            raw_total *= (groups[name] / 100.0) ** weight
    result.update({'group_scores': {name: round(value, 9) for name, value in groups.items()}, 'per_scenario': per_scenario, 'metrics': {'intervention_scores': interventions, 'worst_scenario_score': r_score}, 'raw_total': round(raw_total, 9), 'total': round(raw_total, 9)})
    return result

def shortcut_sanity(reference: dict[str, Any]) -> dict[str, Any]:
    cases: list[dict[str, Any]] = []
    missing = copy.deepcopy(reference)
    del missing['scenarios'][0]['logs']['actuator_state']
    cases.append({'id': 'missing_required_log', 'score': score(reference, missing)})
    copied = copy.deepcopy(reference)
    baseline_logs = copy.deepcopy(copied['scenarios'][0]['logs'])
    for scenario in copied['scenarios'][1:]:
        scenario['logs'] = copy.deepcopy(baseline_logs)
    cases.append({'id': 'baseline_replayed_for_all_scenarios', 'score': score(reference, copied)})
    zero_actuator = copy.deepcopy(reference)
    for scenario in zero_actuator['scenarios']:
        log = scenario['logs']['actuator_state']
        log['data'] = [[0.0] * 8 for _ in log['time']]
    cases.append({'id': 'zero_disconnected_actuators', 'score': score(reference, zero_actuator)})
    copied_command = copy.deepcopy(reference)
    for scenario in copied_command['scenarios']:
        flight = scenario['logs']['flight_state']['data']
        tracking = scenario['logs']['tracking_state']['data']
        for index in range(len(flight)):
            flight[index][0:3] = tracking[index][0:3]
            tracking[index][3:6] = [0.0, 0.0, 0.0]
    cases.append({'id': 'command_copied_as_measurement', 'score': score(reference, copied_command)})
    constant = copy.deepcopy(reference)
    for scenario in constant['scenarios']:
        for log in scenario['logs'].values():
            first = copy.deepcopy(log['data'][0])
            log['data'] = [copy.deepcopy(first) for _ in log['time']]
    cases.append({'id': 'constant_state_and_actuator_outputs', 'score': score(reference, constant)})
    truncated = copy.deepcopy(reference)
    for log in truncated['scenarios'][2]['logs'].values():
        log['time'] = log['time'][:101]
        log['data'] = log['data'][:101]
    cases.append({'id': 'truncated_run', 'score': score(reference, truncated)})
    compact_cases: list[dict[str, Any]] = []
    for item in cases:
        scored = item['score']
        compact_cases.append({'id': item['id'], 'G': scored['G'], 'raw_total': scored['raw_total'], 'passed_below_admission_threshold': scored['raw_total'] < 85.0})
    maximum = max((item['raw_total'] for item in compact_cases))
    return {'schema': 'simuverity.f90-xaero02-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'admission_threshold_raw': 85.0, 'cases': compact_cases, 'maximum_shortcut_raw_score': maximum, 'all_shortcuts_below_threshold': all((item['passed_below_admission_threshold'] for item in compact_cases))}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--score-output', type=Path)
    parser.add_argument('--shortcut-sanity', type=Path)
    args = parser.parse_args()
    reference = read_json(args.reference)
    if args.shortcut_sanity:
        write_json(args.shortcut_sanity, shortcut_sanity(reference))
    if args.candidate:
        if not args.score_output:
            parser.error('--score-output is required with --candidate')
        output = score(reference, read_json(args.candidate))
        write_json(args.score_output, output)
    elif args.score_output:
        parser.error('--candidate is required with --score-output')
if __name__ == '__main__':
    main()
