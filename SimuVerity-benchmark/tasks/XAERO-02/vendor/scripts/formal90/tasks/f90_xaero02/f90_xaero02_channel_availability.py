"""Pure-offline XAERO-02 scorer with explicit channel availability."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
import f90_xaero02_scoring_core as core
TASK_ID = core.TASK_ID
SCENARIO_IDS = core.SCENARIO_IDS
LOG_SPEC = core.LOG_SPEC
WEIGHTS = core.WEIGHTS

def availability(scenario: dict[str, Any], log_name: str) -> list[bool]:
    log = scenario['logs'][log_name]
    width = len(log['channels'])
    raw = log.get('availability')
    if raw is None:
        return [True] * width
    if not isinstance(raw, list) or len(raw) != width:
        return []
    return [item is True for item in raw]

def metric_available(scenario: dict[str, Any], log_name: str, index: int) -> bool:
    mask = availability(scenario, log_name)
    return len(mask) > index and mask[index]

def validate_candidate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    for key in ('load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'runtime_model_unchanged', 'evidence_complete'):
        if evidence.get(key) is not True:
            failures.append(key)
    if evidence.get('static_audit', {}).get('core_path_qualified') is not True:
        failures.append('anti-cheat connected dynamic core path is not qualified')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return (False, failures + ['scenarios is not an array'])
    identifiers = [item.get('id') for item in scenarios if isinstance(item, dict)]
    if identifiers != list(SCENARIO_IDS):
        failures.append('official scenario identifiers/order mismatch')
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
            log = logs[name]
            if log.get('format') != 'Timeseries':
                failures.append(f'{sid}/{name}: format mismatch')
            if log.get('channels') != channels or log.get('units') != units:
                failures.append(f'{sid}/{name}: canonical identity/order/unit mismatch')
            mask = availability(scenario, name)
            if len(mask) != len(channels):
                failures.append(f'{sid}/{name}: availability mask mismatch')
            sources = log.get('sources')
            if not isinstance(sources, list) or len(sources) != len(channels):
                failures.append(f'{sid}/{name}: source map mismatch')
            time = log.get('time')
            if not isinstance(time, list) or len(time) < 250 or (not all((core.finite(item) for item in time))):
                failures.append(f'{sid}/{name}: time vector is short or nonfinite')
                continue
            times = [float(item) for item in time]
            if abs(times[0]) > 1e-09 or abs(times[-1] - 60.0) > 1e-06 or any((right <= left for left, right in zip(times, times[1:]))):
                failures.append(f'{sid}/{name}: time coverage/order mismatch')
            try:
                values = core.matrix(log.get('data'), len(channels))
            except ValueError as exception:
                failures.append(f'{sid}/{name}: {exception}')
                continue
            if len(values) != len(times):
                failures.append(f'{sid}/{name}: data and time lengths differ')
    return (not failures, failures)

def channel_score(reference: dict[str, Any], candidate: dict[str, Any], log: str, index: int) -> float:
    if not metric_available(candidate, log, index):
        return 0.0
    return core.similarity(core.column(reference, log, index), core.column(candidate, log, index))

def group_trajectory_score(reference: dict[str, Any], candidate: dict[str, Any], log: str, indices: list[int]) -> float:
    scores = [channel_score(reference, candidate, log, index) for index in indices]
    return 0.7 * core.mean(scores) + 0.3 * min(scores)

def intervention_score(ref: dict[str, dict[str, Any]], cand: dict[str, dict[str, Any]], target: str, log: str, indices: list[int]) -> float:
    scores: list[float] = []
    for index in indices:
        if not metric_available(cand[target], log, index) or not metric_available(cand['baseline'], log, index):
            scores.append(0.0)
            continue
        ref_delta = core.difference(core.column(ref[target], log, index), core.column(ref['baseline'], log, index))
        cand_delta = core.difference(core.column(cand[target], log, index), core.column(cand['baseline'], log, index))
        scores.append(0.65 * core.similarity(ref_delta, cand_delta, 3.0) + 0.35 * core.magnitude_similarity(ref_delta, cand_delta))
    return 0.7 * core.mean(scores) + 0.3 * min(scores)

def score(reference: dict[str, Any], candidate: dict[str, Any], evidence_role: str='candidate') -> dict[str, Any]:
    if evidence_role == 'reference':
        gate, failures = core.validate(candidate)
    elif evidence_role == 'candidate':
        gate, failures = validate_candidate(candidate)
    else:
        raise ValueError(f'unsupported evidence_role: {evidence_role}')
    result: dict[str, Any] = {'schema': 'simuverity.f90-xaero02-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1 if gate else 0, 'validation_failures': failures, 'weights': WEIGHTS}
    if not gate:
        result.update({'group_scores': {name: 0.0 for name in WEIGHTS}, 'per_scenario': {}, 'metrics': {}, 'raw_total': 0.0, 'total': 0.0})
        return result
    ref = core.scenario_map(reference)
    cand = core.scenario_map(candidate)
    per_scenario: dict[str, dict[str, float]] = {}
    for sid in SCENARIO_IDS:
        flight = group_trajectory_score(ref[sid], cand[sid], 'flight_state', list(range(10)))
        tracking = group_trajectory_score(ref[sid], cand[sid], 'tracking_state', list(range(6)))
        actuator = group_trajectory_score(ref[sid], cand[sid], 'actuator_state', list(range(8)))
        dynamic_scores: list[float] = []
        for log_name, indices in (('flight_state', list(range(3, 10))), ('actuator_state', list(range(8)))):
            for index in indices:
                if not metric_available(cand[sid], log_name, index):
                    dynamic_scores.append(0.0)
                else:
                    dynamic_scores.append(core.similarity(core.derivative(core.column(ref[sid], log_name, index)), core.derivative(core.column(cand[sid], log_name, index)), 2.5))
        waypoint = channel_score(ref[sid], cand[sid], 'tracking_state', 6)
        per_scenario[sid] = {'flight_trajectory': flight, 'tracking_trajectory': tracking, 'actuator_trajectory': actuator, 'dynamic_response': 0.8 * core.mean(dynamic_scores) + 0.2 * min(dynamic_scores), 'waypoint_sequence': waypoint, 'combined': 0.42 * flight + 0.28 * tracking + 0.2 * actuator + 0.1 * waypoint}
    scenario_combined = [per_scenario[sid]['combined'] for sid in SCENARIO_IDS]
    a_score = 0.65 * core.mean([0.65 * per_scenario[sid]['flight_trajectory'] + 0.35 * per_scenario[sid]['tracking_trajectory'] for sid in SCENARIO_IDS]) + 0.35 * min(scenario_combined)
    smoothness_scores: list[float] = []
    for sid in SCENARIO_IDS:
        for log_name, indices in (('flight_state', list(range(3, 10))), ('actuator_state', list(range(8)))):
            for index in indices:
                if not metric_available(cand[sid], log_name, index):
                    smoothness_scores.append(0.0)
                else:
                    smoothness_scores.append(core.magnitude_similarity(core.derivative(core.column(ref[sid], log_name, index)), core.derivative(core.column(cand[sid], log_name, index))))
    q_score = 0.8 * core.mean(smoothness_scores) + 0.2 * min(smoothness_scores)
    interventions: dict[str, float] = {}
    for target in SCENARIO_IDS[1:]:
        state = intervention_score(ref, cand, target, 'flight_state', list(range(10)))
        tracking = intervention_score(ref, cand, target, 'tracking_state', list(range(7)))
        actuator = intervention_score(ref, cand, target, 'actuator_state', list(range(8)))
        interventions[target] = 0.4 * state + 0.25 * tracking + 0.35 * actuator
    m_score = 0.6 * core.mean(list(interventions.values())) + 0.4 * min(interventions.values())
    causal = [0.55 * per_scenario[sid]['tracking_trajectory'] + 0.45 * per_scenario[sid]['actuator_trajectory'] for sid in SCENARIO_IDS]
    c_score = 0.55 * core.mean(causal) + 0.25 * min(causal) + 0.2 * min(interventions.values())
    r_score = min(scenario_combined)
    dynamic = [per_scenario[sid]['dynamic_response'] for sid in SCENARIO_IDS]
    waypoint = [per_scenario[sid]['waypoint_sequence'] for sid in SCENARIO_IDS]
    d_score = 0.55 * core.mean(dynamic) + 0.25 * min(dynamic) + 0.2 * min(waypoint)
    groups = {'A': a_score, 'Q': q_score, 'M': m_score, 'C': c_score, 'R': r_score, 'D': d_score}
    raw_total = 0.0 if any((value <= 0.0 for value in groups.values())) else 100.0
    if raw_total:
        for name, weight in WEIGHTS.items():
            raw_total *= (groups[name] / 100.0) ** weight
    missing = sorted({f'{log}:{index + 1}' for scenario in cand.values() for log in LOG_SPEC for index, present in enumerate(availability(scenario, log)) if not present})
    result.update({'group_scores': {name: round(value, 9) for name, value in groups.items()}, 'per_scenario': per_scenario, 'metrics': {'intervention_scores': interventions, 'worst_scenario_score': r_score, 'unavailable_components_scored_zero': missing}, 'raw_total': round(raw_total, 9), 'total': round(raw_total, 9)})
    return result

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--score-output', required=True, type=Path)
    args = parser.parse_args()
    reference = core.read_json(args.reference)
    candidate = core.read_json(args.candidate)
    output = score(reference, candidate)
    core.write_json(args.score_output, output)
if __name__ == '__main__':
    main()
