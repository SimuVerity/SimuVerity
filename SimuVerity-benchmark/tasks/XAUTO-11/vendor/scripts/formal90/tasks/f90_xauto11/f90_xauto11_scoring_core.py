"""Pure-offline dedicated scorer for F90-XAUTO-11."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XAUTO-11'
SCENARIO_IDS = ('light_body', 'intermediate_body', 'nominal_body', 'soft_low_damping', 'rougher_faster_road')
LOG_SPEC = {'suspension_state': (['road_displacement_m', 'body_displacement_m', 'wheel_displacement_m', 'suspension_deflection_m', 'body_acceleration_m_per_s2'], ['m', 'm', 'm', 'm', 'm/s^2']), 'active_control_state': (['controller_normalized_command', 'applied_active_force_n'], ['1', 'N'])}
WEIGHTS = {'A': 0.23, 'Q': 0.12, 'M': 0.2, 'C': 0.18, 'R': 0.15, 'D': 0.12}

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
        if isinstance(row, list) and len(row) == width and all((finite(item) for item in row)):
            rows.append([float(item) for item in row])
        else:
            raise ValueError('data width or finiteness mismatch')
    return rows

def validate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    if evidence.get('evidence_complete') is not True:
        failures.append('evidence_complete is not true')
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
            if not isinstance(time, list) or len(time) < 100 or (not all((finite(item) for item in time))):
                failures.append(f'{sid}/{name}: time vector is short or nonfinite')
                continue
            times = [float(item) for item in time]
            if abs(times[0]) > 1e-09 or abs(times[-1] - 2.0) > 1e-06:
                failures.append(f'{sid}/{name}: time coverage is not 0--2 s')
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
    return [row[index] for row in matrix(log['data'], len(log['channels']))]

def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def peak(values: list[float]) -> float:
    return max((abs(value) for value in values), default=0.0)

def shape_similarity(reference: list[float], candidate: list[float], sharpness: float=2.0) -> float:
    if len(reference) != len(candidate) or not reference:
        return 0.0
    scale = max(rms(reference), 0.1 * peak(reference), 1e-09)
    error = rms([left - right for left, right in zip(reference, candidate)]) / scale
    return 100.0 * math.exp(-sharpness * error)

def upper_utility(candidate: float, reference: float) -> float:
    reference = max(abs(reference), 1e-12)
    ratio = max(candidate, 0.0) / reference
    if ratio <= 1.05:
        return 100.0
    if ratio >= 3.0:
        return 0.0
    return 100.0 * (3.0 - ratio) / 1.95

def amplitude_similarity(candidate: float, reference: float) -> float:
    reference = max(abs(reference), 1e-12)
    if candidate <= 1e-12:
        return 0.0
    return 100.0 * math.exp(-1.5 * abs(math.log(candidate / reference)))

def effect_similarity(candidate: float, reference: float) -> float:
    scale = max(abs(reference), 1e-09)
    return 100.0 * math.exp(-2.0 * abs(candidate - reference) / scale)

def correlation(left: list[float], right: list[float]) -> float:
    if len(left) != len(right) or len(left) < 2:
        return 0.0
    left_mean, right_mean = (mean(left), mean(right))
    a = [value - left_mean for value in left]
    b = [value - right_mean for value in right]
    denominator = math.sqrt(sum((value * value for value in a)) * sum((value * value for value in b)))
    return 0.0 if denominator <= 1e-15 else sum((x * y for x, y in zip(a, b))) / denominator

def scenario_metrics(scenario: dict[str, Any]) -> dict[str, float]:
    road = column(scenario, 'suspension_state', 0)
    body = column(scenario, 'suspension_state', 1)
    wheel = column(scenario, 'suspension_state', 2)
    deflection = column(scenario, 'suspension_state', 3)
    acceleration = column(scenario, 'suspension_state', 4)
    command = column(scenario, 'active_control_state', 0)
    force = column(scenario, 'active_control_state', 1)
    tail_start = int(0.75 * len(acceleration))
    return {'road_peak': peak(road), 'body_peak': peak(body), 'wheel_peak': peak(wheel), 'deflection_peak': peak(deflection), 'deflection_rms': rms(deflection), 'acceleration_peak': peak(acceleration), 'acceleration_rms': rms(acceleration), 'tail_acceleration_rms': rms(acceleration[tail_start:]), 'tail_deflection_rms': rms(deflection[tail_start:]), 'command_rms': rms(command), 'force_peak': peak(force), 'force_rms': rms(force), 'command_force_correlation': abs(correlation(command, force))}

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    reference_valid, reference_failures = validate(reference)
    candidate_valid, candidate_failures = validate(candidate)
    result: dict[str, Any] = {'schema': 'simuverity.f90-xauto11-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1 if candidate_valid else 0, 'failures': candidate_failures}
    if not reference_valid:
        raise ValueError('reference evidence is invalid: ' + '; '.join(reference_failures))
    if not candidate_valid:
        result.update({'group_scores': {name: 0.0 for name in WEIGHTS}, 'per_scenario': {}, 'metrics': {}, 'raw_total': 0.0, 'total': 0.0})
        return result
    ref, cand = (scenario_map(reference), scenario_map(candidate))
    ref_metrics = {sid: scenario_metrics(ref[sid]) for sid in SCENARIO_IDS}
    cand_metrics = {sid: scenario_metrics(cand[sid]) for sid in SCENARIO_IDS}
    per_scenario: dict[str, dict[str, float]] = {}
    performance_scores: list[float] = []
    dynamic_scores: list[float] = []
    force_scores: list[float] = []
    for sid in SCENARIO_IDS:
        rm, cm = (ref_metrics[sid], cand_metrics[sid])
        performance_parts = [upper_utility(cm['acceleration_peak'], rm['acceleration_peak']), upper_utility(cm['acceleration_rms'], rm['acceleration_rms']), upper_utility(cm['deflection_peak'], rm['deflection_peak']), upper_utility(cm['deflection_rms'], rm['deflection_rms']), upper_utility(cm['body_peak'], rm['body_peak']), upper_utility(cm['wheel_peak'], rm['wheel_peak'])]
        state_shapes = [shape_similarity(column(ref[sid], 'suspension_state', index), column(cand[sid], 'suspension_state', index)) for index in (1, 2, 3, 4)]
        performance = 0.65 * mean(performance_parts) + 0.35 * mean(state_shapes)
        dynamics = mean([upper_utility(cm['tail_acceleration_rms'], rm['tail_acceleration_rms']), upper_utility(cm['tail_deflection_rms'], rm['tail_deflection_rms']), shape_similarity(column(ref[sid], 'suspension_state', 4), column(cand[sid], 'suspension_state', 4), 1.5)])
        force = mean([upper_utility(cm['force_peak'], rm['force_peak']), upper_utility(cm['force_rms'], rm['force_rms']), amplitude_similarity(cm['force_rms'], rm['force_rms'])])
        performance_scores.append(performance)
        dynamic_scores.append(dynamics)
        force_scores.append(force)
        per_scenario[sid] = {'performance': performance, 'dynamic_recovery': dynamics, 'control_effort': force, 'command_force_correlation': cm['command_force_correlation'] * 100.0}
    nominal = 'nominal_body'
    intervention_scores: dict[str, float] = {}
    for sid in SCENARIO_IDS:
        if sid == nominal:
            continue
        components: list[float] = []
        for metric in ('acceleration_peak', 'acceleration_rms', 'deflection_peak', 'deflection_rms', 'body_peak', 'wheel_peak', 'force_peak'):
            reference_effect = ref_metrics[sid][metric] - ref_metrics[nominal][metric]
            candidate_effect = cand_metrics[sid][metric] - cand_metrics[nominal][metric]
            components.append(effect_similarity(candidate_effect, reference_effect))
        intervention_scores[sid] = mean(components)
    road_fidelity: list[float] = []
    for sid in SCENARIO_IDS:
        requested = float(cand[sid].get('input', {}).get('road_peak_m', 0.0))
        measured = cand_metrics[sid]['road_peak']
        road_fidelity.append(max(0.0, 100.0 * (1.0 - abs(measured - requested) / max(requested, 1e-09))))
    intervention_mean = mean(list(intervention_scores.values()))
    intervention_worst = min(intervention_scores.values())
    mechanism_nonzero = min((amplitude_similarity(cand_metrics[sid]['force_rms'], ref_metrics[sid]['force_rms']) for sid in SCENARIO_IDS))
    m_score = 0.3 * mean(road_fidelity) + 0.4 * intervention_mean + 0.2 * intervention_worst + 0.1 * mechanism_nonzero
    connectivity = [100.0 * cand_metrics[sid]['command_force_correlation'] for sid in SCENARIO_IDS]
    c_score = 0.35 * mean(connectivity) + 0.2 * min(connectivity) + 0.25 * mean(force_scores) + 0.2 * intervention_worst
    if max((cand_metrics[sid]['force_rms'] for sid in SCENARIO_IDS)) <= 1e-09 or mechanism_nonzero < 5.0:
        c_score = 0.0
    a_score = 0.7 * mean(performance_scores) + 0.3 * min(performance_scores)
    q_score = 100.0
    r_score = min((0.8 * performance_scores[index] + 0.2 * force_scores[index] for index in range(len(SCENARIO_IDS))))
    d_score = 0.65 * mean(dynamic_scores) + 0.35 * min(dynamic_scores)
    groups = {'A': a_score, 'Q': q_score, 'M': m_score, 'C': c_score, 'R': r_score, 'D': d_score}
    if any((value <= 0.0 for value in groups.values())):
        raw_total = 0.0
    else:
        raw_total = 100.0
        for name, weight in WEIGHTS.items():
            raw_total *= (groups[name] / 100.0) ** weight
    result.update({'group_scores': {name: round(value, 9) for name, value in groups.items()}, 'per_scenario': per_scenario, 'metrics': {'intervention_scores': intervention_scores, 'road_fidelity_scores': road_fidelity, 'worst_scenario_score': r_score}, 'raw_total': round(raw_total, 9), 'total': round(raw_total, 9)})
    return result

def shortcut_sanity(reference: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any]]] = []
    missing = copy.deepcopy(reference)
    del missing['scenarios'][0]['logs']['active_control_state']
    cases.append(('missing_required_log', missing))
    replayed = copy.deepcopy(reference)
    baseline_logs = copy.deepcopy(replayed['scenarios'][0]['logs'])
    for scenario in replayed['scenarios'][1:]:
        scenario['logs'] = copy.deepcopy(baseline_logs)
    cases.append(('one_scenario_replayed_for_all_conditions', replayed))
    zero_force = copy.deepcopy(reference)
    for scenario in zero_force['scenarios']:
        log = scenario['logs']['active_control_state']
        log['data'] = [[0.0, 0.0] for _ in log['time']]
    cases.append(('zero_disconnected_control_and_force', zero_force))
    unscaled_force = copy.deepcopy(reference)
    for scenario in unscaled_force['scenarios']:
        log = scenario['logs']['active_control_state']
        for row in log['data']:
            row[1] = row[0]
    cases.append(('normalized_command_copied_as_physical_force', unscaled_force))
    road_copy = copy.deepcopy(reference)
    for scenario in road_copy['scenarios']:
        state = scenario['logs']['suspension_state']['data']
        for row in state:
            row[1], row[2], row[3], row[4] = (row[0], row[0], 0.0, 0.0)
    cases.append(('road_copied_as_body_and_wheel_state', road_copy))
    constant = copy.deepcopy(reference)
    for scenario in constant['scenarios']:
        for log in scenario['logs'].values():
            first = copy.deepcopy(log['data'][0])
            log['data'] = [copy.deepcopy(first) for _ in log['time']]
    cases.append(('constant_state_histories', constant))
    truncated = copy.deepcopy(reference)
    for log in truncated['scenarios'][2]['logs'].values():
        log['time'] = log['time'][:80]
        log['data'] = log['data'][:80]
    cases.append(('truncated_run', truncated))
    compact: list[dict[str, Any]] = []
    for identifier, candidate in cases:
        scored = score(reference, candidate)
        compact.append({'id': identifier, 'G': scored['G'], 'raw_total': scored['raw_total'], 'passed_below_admission_threshold': scored['raw_total'] < 85.0})
    maximum = max((item['raw_total'] for item in compact))
    return {'schema': 'simuverity.f90-xauto11-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'admission_threshold_raw': 85.0, 'cases': compact, 'maximum_shortcut_raw_score': maximum, 'all_shortcuts_below_threshold': all((item['passed_below_admission_threshold'] for item in compact))}

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
