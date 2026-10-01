"""Pure-offline dedicated scorer for F90-XAUTO-10."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XAUTO-10'
SCENARIO_IDS = ('straight_low_symmetric', 'straight_high_symmetric', 'moderate_left_steer', 'larger_left_steer', 'small_left_torque_bias', 'small_right_torque_bias')
WEIGHTS = {'A': 0.24, 'Q': 0.1, 'M': 0.22, 'C': 0.18, 'R': 0.14, 'D': 0.12}
VEHICLE_FLOORS = (1.0, 0.1, 0.5, 0.2, 0.05, 0.2, 0.05)
SLIP_FLOORS = (0.05,) * 12

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
    result: list[list[float]] = []
    for row in value:
        if not isinstance(row, list) or len(row) != width or (not all((finite(item) for item in row))):
            raise ValueError(f'data is not a finite width-{width} matrix')
        result.append([float(item) for item in row])
    return result

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(item['id']): item for item in evidence['scenarios']}

def validate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    if evidence.get('evidence_complete') is not True:
        failures.append('evidence_complete is not true')
    if evidence.get('simulate_pass') is not True or evidence.get('all_scenarios_valid') is not True:
        failures.append('top-level simulation/evidence validity is not true')
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
        if scenario.get('valid') is not True:
            failures.append(f'{sid}: evaluator validity flag is not true')
        time = scenario.get('time_s')
        if not isinstance(time, list) or len(time) < 400 or (not all((finite(item) for item in time))):
            failures.append(f'{sid}: time vector is short or nonfinite')
            continue
        times = [float(item) for item in time]
        if abs(times[0]) > 1e-09 or abs(times[-1] - 5.0) > 1e-06:
            failures.append(f'{sid}: time coverage is not 0--5 seconds')
        if any((right <= left for left, right in zip(times, times[1:]))):
            failures.append(f'{sid}: time is not strictly increasing')
        try:
            vehicle = matrix(scenario.get('vehicle_motion_state'), 7)
            slip = matrix(scenario.get('wheel_slip_state'), 12)
            commands = matrix(scenario.get('rear_wheel_command_state'), 3)
        except ValueError as exception:
            failures.append(f'{sid}: {exception}')
            continue
        if len(vehicle) != len(times) or len(slip) != len(times) or len(commands) != len(times):
            failures.append(f'{sid}: signal and time lengths differ')
            continue
        inputs = scenario.get('inputs', {})
        expected = (float(inputs.get('steering_angle_deg', math.nan)), float(inputs.get('rear_left_torque_nm', math.nan)), float(inputs.get('rear_right_torque_nm', math.nan)))
        for index, target in enumerate(expected):
            if not math.isfinite(target) or max((abs(row[index] - target) for row in commands)) > 1e-06:
                failures.append(f'{sid}: command channel {index} does not match the official input')
    return (not failures, failures)

def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def column(values: list[list[float]], index: int) -> list[float]:
    return [row[index] for row in values]

def shape_similarity(reference: list[float], candidate: list[float], floor: float, sharpness: float=1.8) -> float:
    if len(reference) != len(candidate) or not reference:
        return 0.0
    scale = max(rms(reference), 0.1 * max((abs(item) for item in reference)), floor)
    error = rms([left - right for left, right in zip(reference, candidate)]) / scale
    return 100.0 * math.exp(-sharpness * error)

def effect_similarity(candidate: float, reference: float) -> float:
    scale = max(abs(reference), 1e-08)
    return 100.0 * math.exp(-2.5 * abs(candidate - reference) / scale)

def matrix_similarity(reference: list[list[float]], candidate: list[list[float]], floors: tuple[float, ...], columns: tuple[int, ...] | None=None, sharpness: float=1.8) -> float:
    indexes = columns if columns is not None else tuple(range(len(floors)))
    return mean([shape_similarity(column(reference, index), column(candidate, index), floors[index], sharpness) for index in indexes])

def scenario_scores(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, float]:
    ref_vehicle = matrix(reference['vehicle_motion_state'], 7)
    cand_vehicle = matrix(candidate['vehicle_motion_state'], 7)
    ref_slip = matrix(reference['wheel_slip_state'], 12)
    cand_slip = matrix(candidate['wheel_slip_state'], 12)
    vehicle = matrix_similarity(ref_vehicle, cand_vehicle, VEHICLE_FLOORS)
    slip = matrix_similarity(ref_slip, cand_slip, SLIP_FLOORS, sharpness=2.0)
    dynamic = matrix_similarity(ref_vehicle, cand_vehicle, VEHICLE_FLOORS, (2, 3, 4, 5), sharpness=2.1)
    terminal = mean([100.0 * math.exp(-2.0 * abs(cand_vehicle[-1][index] - ref_vehicle[-1][index]) / max(abs(ref_vehicle[-1][index]), VEHICLE_FLOORS[index])) for index in range(7)])
    return {'vehicle': vehicle, 'slip': slip, 'dynamic': dynamic, 'terminal': terminal}

def effects(scenarios: dict[str, dict[str, Any]]) -> dict[str, float]:

    def final(sid: str, signal: str, index: int) -> float:
        width = 7 if signal == 'vehicle_motion_state' else 12
        return matrix(scenarios[sid][signal], width)[-1][index]
    return {'symmetric_torque_longitudinal': final('straight_high_symmetric', 'vehicle_motion_state', 0) - final('straight_low_symmetric', 'vehicle_motion_state', 0), 'steering_yaw': final('moderate_left_steer', 'vehicle_motion_state', 4) - final('straight_high_symmetric', 'vehicle_motion_state', 4), 'steering_lateral_velocity': final('moderate_left_steer', 'vehicle_motion_state', 1) - final('straight_high_symmetric', 'vehicle_motion_state', 1), 'larger_steering_yaw_increment': final('larger_left_steer', 'vehicle_motion_state', 4) - final('moderate_left_steer', 'vehicle_motion_state', 4), 'mirrored_differential_yaw': final('small_left_torque_bias', 'vehicle_motion_state', 4) - final('small_right_torque_bias', 'vehicle_motion_state', 4), 'mirrored_differential_rear_left_slip': final('small_left_torque_bias', 'wheel_slip_state', 2) - final('small_right_torque_bias', 'wheel_slip_state', 2), 'mirrored_differential_rear_right_slip': final('small_left_torque_bias', 'wheel_slip_state', 3) - final('small_right_torque_bias', 'wheel_slip_state', 3)}

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    reference_valid, reference_failures = validate(reference)
    candidate_valid, candidate_failures = validate(candidate)
    if not reference_valid:
        raise ValueError('reference evidence is invalid: ' + '; '.join(reference_failures))
    result: dict[str, Any] = {'schema': 'simuverity.f90-xauto10-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1 if candidate_valid else 0, 'failures': candidate_failures}
    if not candidate_valid:
        result.update({'group_scores': {name: 0.0 for name in WEIGHTS}, 'per_scenario': {}, 'metrics': {}, 'raw_total': 0.0, 'total': 0.0})
        return result
    ref = scenario_map(reference)
    cand = scenario_map(candidate)
    per_scenario = {sid: scenario_scores(ref[sid], cand[sid]) for sid in SCENARIO_IDS}
    vehicle_scores = [per_scenario[sid]['vehicle'] for sid in SCENARIO_IDS]
    slip_scores = [per_scenario[sid]['slip'] for sid in SCENARIO_IDS]
    dynamic_scores = [0.7 * per_scenario[sid]['dynamic'] + 0.3 * per_scenario[sid]['terminal'] for sid in SCENARIO_IDS]
    ref_effects = effects(ref)
    cand_effects = effects(cand)
    effect_scores = {name: effect_similarity(cand_effects[name], value) for name, value in ref_effects.items()}
    critical = ('symmetric_torque_longitudinal', 'steering_yaw', 'larger_steering_yaw_increment', 'mirrored_differential_yaw')
    causal_gate = all((abs(cand_effects[name]) >= 0.05 * max(abs(ref_effects[name]), 1e-08) and cand_effects[name] * ref_effects[name] > 0 for name in critical))
    a_score = 0.75 * mean(vehicle_scores) + 0.25 * min(vehicle_scores)
    q_score = 100.0
    m_score = 0.68 * mean(slip_scores) + 0.22 * min(slip_scores) + 10.0
    c_score = 0.7 * mean(list(effect_scores.values())) + 0.3 * min(effect_scores.values())
    if not causal_gate:
        c_score = 0.0
    r_score = min((0.58 * vehicle_scores[index] + 0.42 * slip_scores[index] for index in range(len(SCENARIO_IDS))))
    d_score = 0.7 * mean(dynamic_scores) + 0.3 * min(dynamic_scores)
    groups = {'A': a_score, 'Q': q_score, 'M': m_score, 'C': c_score, 'R': r_score, 'D': d_score}
    if any((value <= 0.0 for value in groups.values())):
        raw_total = 0.0
    else:
        raw_total = 100.0
        for name, weight in WEIGHTS.items():
            raw_total *= (groups[name] / 100.0) ** weight
    result.update({'group_scores': {name: round(value, 9) for name, value in groups.items()}, 'per_scenario': {sid: {name: round(value, 9) for name, value in values.items()} for sid, values in per_scenario.items()}, 'metrics': {'reference_intervention_effects': ref_effects, 'candidate_intervention_effects': cand_effects, 'intervention_scores': effect_scores, 'causal_gate': causal_gate, 'worst_scenario_score': r_score}, 'raw_total': round(raw_total, 9), 'total': round(raw_total, 9)})
    return result

def shortcut_sanity(reference: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any]]] = []
    missing = copy.deepcopy(reference)
    del missing['scenarios'][0]['wheel_slip_state']
    cases.append(('missing_required_output', missing))
    replayed = copy.deepcopy(reference)
    baseline = replayed['scenarios'][0]
    for scenario in replayed['scenarios'][1:]:
        scenario['vehicle_motion_state'] = copy.deepcopy(baseline['vehicle_motion_state'])
        scenario['wheel_slip_state'] = copy.deepcopy(baseline['wheel_slip_state'])
    cases.append(('one_scenario_replayed_for_all_interventions', replayed))
    zero_motion = copy.deepcopy(reference)
    for scenario in zero_motion['scenarios']:
        scenario['vehicle_motion_state'] = [[0.0] * 7 for _ in scenario['time_s']]
    cases.append(('zero_vehicle_motion', zero_motion))
    zero_slip = copy.deepcopy(reference)
    for scenario in zero_slip['scenarios']:
        scenario['wheel_slip_state'] = [[0.0] * 12 for _ in scenario['time_s']]
    cases.append(('zero_disconnected_wheel_slip', zero_slip))
    command_copy = copy.deepcopy(reference)
    for scenario in command_copy['scenarios']:
        commands = scenario['rear_wheel_command_state']
        scenario['vehicle_motion_state'] = [[row[0], row[1], row[2], row[0], row[1], row[2], row[0]] for row in commands]
    cases.append(('commands_copied_as_vehicle_state', command_copy))
    ignored_diff = copy.deepcopy(reference)
    left = ignored_diff['scenarios'][4]
    right = ignored_diff['scenarios'][5]
    right['vehicle_motion_state'] = copy.deepcopy(left['vehicle_motion_state'])
    right['wheel_slip_state'] = copy.deepcopy(left['wheel_slip_state'])
    cases.append(('differential_torque_sign_ignored', ignored_diff))
    truncated = copy.deepcopy(reference)
    target = truncated['scenarios'][2]
    for key in ('time_s', 'vehicle_motion_state', 'wheel_slip_state', 'rear_wheel_command_state'):
        target[key] = target[key][:100]
    cases.append(('truncated_run', truncated))
    compact: list[dict[str, Any]] = []
    for identifier, candidate in cases:
        scored = score(reference, candidate)
        compact.append({'id': identifier, 'G': scored['G'], 'raw_total': scored['raw_total'], 'passed_below_admission_threshold': scored['raw_total'] < 85.0})
    maximum = max((item['raw_total'] for item in compact))
    return {'schema': 'simuverity.f90-xauto10-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'admission_threshold_raw': 85.0, 'cases': compact, 'maximum_shortcut_raw_score': maximum, 'all_shortcuts_below_threshold': all((item['passed_below_admission_threshold'] for item in compact))}

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
    if args.score_output:
        candidate_path = args.candidate or args.reference
        result = score(reference, read_json(candidate_path))
        write_json(args.score_output, result)
if __name__ == '__main__':
    main()
