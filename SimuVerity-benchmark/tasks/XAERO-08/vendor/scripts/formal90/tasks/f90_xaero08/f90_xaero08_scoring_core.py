"""Pure-offline dedicated scorer for F90-XAERO-08."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XAERO-08'
SCENARIO_IDS = ('nominal', 'lower_mass_flow', 'higher_mass_flow', 'heavy_payload', 'stronger_gravity_turn')
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.22, 'C': 0.18, 'R': 0.13, 'D': 0.12}
FLIGHT_FLOORS = (1000.0, 2000.0, 100.0, 0.1, 0.1)
PROP_FLOORS = (100000.0, 10000.0, 1000.0, 1000.0)
GUIDANCE_FLOORS = (0.05, 0.1, 0.1, 0.05)

def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding='utf-8'))

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
        if not isinstance(row, list) or len(row) != width or (not all((finite(item) for item in row))):
            raise ValueError(f'data is not a finite width-{width} matrix')
        rows.append([float(item) for item in row])
    return rows

def validate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    if evidence.get('evidence_complete') is not True:
        failures.append('evidence_complete is not true')
    if evidence.get('simulate_pass') is not True or evidence.get('all_scenarios_valid') is not True:
        failures.append('top-level evidence validity is not true')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return (False, failures + ['scenarios is not an array'])
    ids = [row.get('id') for row in scenarios if isinstance(row, dict)]
    if len(ids) != len(SCENARIO_IDS) or sorted(ids) != sorted(SCENARIO_IDS):
        failures.append('official scenario identifiers are incomplete, duplicated, or unexpected')
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            failures.append('scenario entry is not an object')
            continue
        sid = str(scenario.get('id', '<missing>'))
        if scenario.get('valid') is not True:
            failures.append(f'{sid}: evaluator validity flag is not true')
        time = scenario.get('time_s')
        if not isinstance(time, list) or len(time) != 501 or (not all((finite(item) for item in time))):
            failures.append(f'{sid}: phase-grid time vector is invalid')
            continue
        times = [float(item) for item in time]
        terminal = scenario.get('actual_terminal_time_s')
        if not finite(terminal) or not 1.0 < float(terminal) <= 350.000001:
            failures.append(f'{sid}: terminal time is invalid')
        elif abs(times[0]) > 1e-09 or abs(times[-1] - float(terminal)) > 1e-05:
            failures.append(f'{sid}: time does not cover the actual run')
        if any((right <= left for left, right in zip(times, times[1:]))):
            failures.append(f'{sid}: time is not strictly increasing')
        try:
            flight = matrix(scenario.get('flight_state'), 5)
            propulsion = matrix(scenario.get('propulsion_state'), 4)
            guidance = matrix(scenario.get('guidance_attitude_state'), 4)
        except ValueError as exception:
            failures.append(f'{sid}: {exception}')
            continue
        if len(flight) != 501 or len(propulsion) != 501 or len(guidance) != 501:
            failures.append(f'{sid}: signal length differs from phase grid')
            continue
        command = float(scenario.get('inputs', {}).get('gravity_turn_angle_rad', math.nan))
        if not math.isfinite(command) or max((abs(row[0] - command) for row in guidance)) > 1e-06:
            failures.append(f'{sid}: gravity-turn command log does not match the official input')
    return (not failures, failures)

def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def column(values: list[list[float]], index: int) -> list[float]:
    return [row[index] for row in values]

def shape_similarity(reference: list[float], candidate: list[float], floor: float, sharpness: float=1.8) -> float:
    scale = max(rms(reference), 0.1 * max((abs(item) for item in reference)), floor)
    error = rms([left - right for left, right in zip(reference, candidate)]) / scale
    return 100.0 * math.exp(-sharpness * error)

def matrix_similarity(reference: list[list[float]], candidate: list[list[float]], floors: tuple[float, ...], indexes: tuple[int, ...] | None=None, sharpness: float=1.8) -> float:
    selected = indexes if indexes is not None else tuple(range(len(floors)))
    return mean([shape_similarity(column(reference, index), column(candidate, index), floors[index], sharpness) for index in selected])

def scalar_similarity(candidate: float, reference: float, floor: float=1e-08, sharpness: float=2.2) -> float:
    return 100.0 * math.exp(-sharpness * abs(candidate - reference) / max(abs(reference), floor))

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row['id']): row for row in evidence['scenarios']}

def scenario_scores(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, float]:
    rf, cf = (matrix(reference['flight_state'], 5), matrix(candidate['flight_state'], 5))
    rp, cp = (matrix(reference['propulsion_state'], 4), matrix(candidate['propulsion_state'], 4))
    rg, cg = (matrix(reference['guidance_attitude_state'], 4), matrix(candidate['guidance_attitude_state'], 4))
    terminal = scalar_similarity(float(candidate['actual_terminal_time_s']), float(reference['actual_terminal_time_s']), 10.0)
    flight = matrix_similarity(rf, cf, FLIGHT_FLOORS, sharpness=1.9)
    propulsion = matrix_similarity(rp, cp, PROP_FLOORS, sharpness=2.0)
    guidance = matrix_similarity(rg, cg, GUIDANCE_FLOORS, (1, 2, 3), sharpness=2.0)
    transient = matrix_similarity(rf, cf, FLIGHT_FLOORS, (0, 2, 3, 4), sharpness=2.1)
    terminal_state = mean([scalar_similarity(cf[-1][index], rf[-1][index], FLIGHT_FLOORS[index], 1.8) for index in range(5)])
    return {'flight': flight, 'propulsion': propulsion, 'guidance': guidance, 'transient': transient, 'terminal_state': terminal_state, 'terminal_time': terminal}

def effects(scenarios: dict[str, dict[str, Any]]) -> dict[str, float]:

    def peak(sid: str, key: str, index: int) -> float:
        width = 5 if key == 'flight_state' else 4 if key == 'propulsion_state' else 4
        return max((row[index] for row in matrix(scenarios[sid][key], width)))

    def final(sid: str, key: str, index: int) -> float:
        width = 5 if key == 'flight_state' else 4 if key == 'propulsion_state' else 4
        return matrix(scenarios[sid][key], width)[-1][index]

    def terminal(sid: str) -> float:
        return float(scenarios[sid]['actual_terminal_time_s'])
    return {'mass_flow_peak_altitude': peak('higher_mass_flow', 'flight_state', 0) - peak('lower_mass_flow', 'flight_state', 0), 'mass_flow_peak_speed': peak('higher_mass_flow', 'flight_state', 2) - peak('lower_mass_flow', 'flight_state', 2), 'mass_flow_terminal_time': terminal('higher_mass_flow') - terminal('lower_mass_flow'), 'payload_peak_altitude': peak('heavy_payload', 'flight_state', 0) - peak('nominal', 'flight_state', 0), 'payload_terminal_time': terminal('heavy_payload') - terminal('nominal'), 'gravity_turn_downrange': final('stronger_gravity_turn', 'flight_state', 1) - final('nominal', 'flight_state', 1), 'gravity_turn_pitch': final('stronger_gravity_turn', 'flight_state', 4) - final('nominal', 'flight_state', 4)}

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    reference_valid, reference_failures = validate(reference)
    candidate_valid, candidate_failures = validate(candidate)
    if not reference_valid:
        raise ValueError('reference evidence is invalid: ' + '; '.join(reference_failures))
    result: dict[str, Any] = {'schema': 'simuverity.f90-xaero08-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1 if candidate_valid else 0, 'failures': candidate_failures}
    if not candidate_valid:
        result.update({'group_scores': {name: 0.0 for name in WEIGHTS}, 'per_scenario': {}, 'metrics': {}, 'raw_total': 0.0, 'total': 0.0})
        return result
    ref, cand = (scenario_map(reference), scenario_map(candidate))
    per = {sid: scenario_scores(ref[sid], cand[sid]) for sid in SCENARIO_IDS}
    flight = [per[sid]['flight'] for sid in SCENARIO_IDS]
    propulsion = [per[sid]['propulsion'] for sid in SCENARIO_IDS]
    guidance = [per[sid]['guidance'] for sid in SCENARIO_IDS]
    dynamic = [0.55 * per[sid]['transient'] + 0.25 * per[sid]['terminal_state'] + 0.2 * per[sid]['terminal_time'] for sid in SCENARIO_IDS]
    ref_effects, cand_effects = (effects(ref), effects(cand))
    effect_scores = {name: scalar_similarity(cand_effects[name], value) for name, value in ref_effects.items()}
    causal_gate = all((abs(cand_effects[name]) >= 0.05 * max(abs(ref_effects[name]), 1e-08) and cand_effects[name] * ref_effects[name] > 0 for name in ref_effects))
    nominal_ref = matrix(ref['nominal']['propulsion_state'], 4)
    nominal_cand = matrix(cand['nominal']['propulsion_state'], 4)
    ref_ranges = [max(column(nominal_ref, i)) - min(column(nominal_ref, i)) for i in (0, 2, 3)]
    cand_ranges = [max(column(nominal_cand, i)) - min(column(nominal_cand, i)) for i in (0, 2, 3)]
    mechanism_gate = sum((value >= 0.05 * max(reference_value, 1e-08) for value, reference_value in zip(cand_ranges, ref_ranges))) >= 2
    groups = {'A': 0.75 * mean(flight) + 0.25 * min(flight), 'Q': 100.0, 'M': 0.62 * mean(propulsion) + 0.18 * min(propulsion) + 0.2 * mean(flight), 'C': 0.58 * mean(list(effect_scores.values())) + 0.22 * min(effect_scores.values()) + 0.2 * mean(guidance), 'R': min((0.55 * flight[i] + 0.3 * propulsion[i] + 0.15 * guidance[i] for i in range(len(SCENARIO_IDS)))), 'D': 0.7 * mean(dynamic) + 0.3 * min(dynamic)}
    if not mechanism_gate:
        groups['M'] = 0.0
    if not causal_gate:
        groups['C'] = 0.0
    raw = 0.0 if any((value <= 0 for value in groups.values())) else 100.0 * math.prod(((groups[name] / 100.0) ** weight for name, weight in WEIGHTS.items()))
    result.update({'group_scores': {name: round(value, 9) for name, value in groups.items()}, 'per_scenario': {sid: {name: round(value, 9) for name, value in row.items()} for sid, row in per.items()}, 'metrics': {'reference_intervention_effects': ref_effects, 'candidate_intervention_effects': cand_effects, 'intervention_scores': effect_scores, 'causal_gate': causal_gate, 'mechanism_gate': mechanism_gate, 'worst_official_condition': groups['R']}, 'raw_total': round(raw, 9), 'total': round(raw, 9)})
    return result

def shortcut_sanity(reference: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any]]] = []
    missing = copy.deepcopy(reference)
    del missing['scenarios'][0]['propulsion_state']
    cases.append(('missing_required_output', missing))
    replayed = copy.deepcopy(reference)
    baseline = replayed['scenarios'][0]
    for row in replayed['scenarios'][1:]:
        for key in ('flight_state', 'propulsion_state', 'guidance_attitude_state'):
            row[key] = copy.deepcopy(baseline[key])
        row['actual_terminal_time_s'] = baseline['actual_terminal_time_s']
        row['time_s'] = copy.deepcopy(baseline['time_s'])
        row['guidance_attitude_state'] = [[float(row['inputs']['gravity_turn_angle_rad']), *values[1:]] for values in row['guidance_attitude_state']]
    cases.append(('one_scenario_replayed_for_all_interventions', replayed))
    zero = copy.deepcopy(reference)
    for row in zero['scenarios']:
        row['flight_state'] = [[0.0] * 5 for _ in row['time_s']]
    cases.append(('zero_trajectory', zero))
    constant = copy.deepcopy(reference)
    for row in constant['scenarios']:
        row['propulsion_state'] = [copy.deepcopy(row['propulsion_state'][0]) for _ in row['time_s']]
    cases.append(('constant_propulsion_state', constant))
    copied = copy.deepcopy(reference)
    for row in copied['scenarios']:
        row['flight_state'] = [[values[0], values[1], values[2], values[0], values[2]] for values in row['guidance_attitude_state']]
    cases.append(('commands_copied_as_flight_state', copied))
    ignored = copy.deepcopy(reference)
    stronger = ignored['scenarios'][4]
    nominal = ignored['scenarios'][0]
    for key in ('flight_state', 'propulsion_state', 'guidance_attitude_state'):
        stronger[key] = copy.deepcopy(nominal[key])
    stronger['guidance_attitude_state'] = [[float(stronger['inputs']['gravity_turn_angle_rad']), *values[1:]] for values in stronger['guidance_attitude_state']]
    stronger['actual_terminal_time_s'] = nominal['actual_terminal_time_s']
    stronger['time_s'] = copy.deepcopy(nominal['time_s'])
    cases.append(('gravity_turn_response_ignored', ignored))
    truncated = copy.deepcopy(reference)
    target = truncated['scenarios'][2]
    for key in ('time_s', 'phase', 'flight_state', 'propulsion_state', 'guidance_attitude_state'):
        target[key] = target[key][:20]
    target['actual_terminal_time_s'] = target['time_s'][-1]
    cases.append(('truncated_run', truncated))
    compact = []
    for identifier, candidate in cases:
        scored = score(reference, candidate)
        compact.append({'id': identifier, 'G': scored['G'], 'raw_total': scored['raw_total'], 'passed_below_admission_threshold': scored['raw_total'] < 85.0})
    maximum = max((row['raw_total'] for row in compact))
    return {'schema': 'simuverity.f90-xaero08-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'admission_threshold_raw': 85.0, 'cases': compact, 'maximum_shortcut_raw_score': maximum, 'all_shortcuts_below_threshold': all((row['passed_below_admission_threshold'] for row in compact))}

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
