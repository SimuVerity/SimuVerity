"""Pure-offline scorer for F90-XAUTO-11 evidence."""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XAUTO-11'
SCENARIO_IDS = ('light_body', 'intermediate_body', 'nominal_body', 'soft_low_damping', 'rougher_faster_road')
LOG_SPEC = {'suspension_state': (['road_displacement_m', 'body_displacement_m', 'wheel_displacement_m', 'suspension_deflection_m', 'body_acceleration_m_per_s2'], ['m', 'm', 'm', 'm', 'm/s^2']), 'active_control_state': (['controller_normalized_command', 'applied_active_force_n'], ['1', 'N'])}
EXPECTED_APPLICATION_CONTRACT = 'xauto11-base-and-simulationinput'

def _load_source() -> Any:
    path = Path(__file__).with_name('f90_xauto11_scoring_core.py')
    spec = importlib.util.spec_from_file_location('f90_xauto11_scoring_core_module', path)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load the XAUTO-11 scoring core')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
SOURCE = _load_source()
WEIGHTS = dict(SOURCE.WEIGHTS)

def read_json(path: Path) -> dict[str, Any]:
    with path.open('r', encoding='utf-8') as handle:
        return json.load(handle)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def _simulation_pass(scenario: dict[str, Any]) -> bool:
    """Accept native extractor and Unified-normalized simulation flags."""
    return scenario.get('simulation_pass') is True or scenario.get('simulate_pass') is True

def _matrix(value: Any, width: int) -> list[list[float]]:
    if not isinstance(value, list):
        raise ValueError('data is not an array')
    rows: list[list[float]] = []
    for row in value:
        if isinstance(row, list) and len(row) == width and all((finite(item) for item in row)):
            rows.append([float(item) for item in row])
        else:
            raise ValueError('data width or finiteness mismatch')
    return rows

def _validate_application(evidence: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if evidence.get('input_application_contract') != EXPECTED_APPLICATION_CONTRACT:
        failures.append('candidate input_application_contract does not match the required contract')
    if evidence.get('input_application_all_pass') is not True:
        failures.append('candidate input_application_all_pass is not true')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return failures
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            continue
        sid = str(scenario.get('id', '<missing>'))
        if scenario.get('scenario_application_pass') is not True:
            failures.append(f'{sid}: scenario_application_pass is not true')
        offline_metrics = scenario.get('offline_metrics')
        log = offline_metrics.get('input_application_log') if isinstance(offline_metrics, dict) else None
        if not isinstance(log, dict) or log.get('pass') is not True:
            failures.append(f'{sid}: verified input application log is absent or failed')
            continue
        requested = log.get('requested_parameters')
        applied = scenario.get('applied_parameters')
        published = scenario.get('input')
        if not isinstance(requested, dict) or requested != applied or requested != published:
            failures.append(f'{sid}: requested, applied, and published parameters differ')
        for flag in ('base_value_before_simulation_matches_requested', 'simulationinput_and_base_match', 'base_value_after_simulation_matches_requested'):
            if log.get(flag) is not True:
                failures.append(f'{sid}: {flag} is not true')
    return failures

def validate(evidence: dict[str, Any], role: str) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    if evidence.get('evidence_complete') is not True:
        failures.append('evidence is not complete')
    for flag in ('load_pass', 'update_pass', 'compile_pass'):
        if evidence.get(flag) is not True:
            failures.append(f'{flag} is not true')
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
        if not _simulation_pass(scenario):
            failures.append(f'{sid}: neither simulation_pass nor simulate_pass is true')
        if 'required_evidence_pass' in scenario and scenario.get('required_evidence_pass') is not True:
            failures.append(f'{sid}: required_evidence_pass is not true')
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
                values = _matrix(log.get('data'), len(channels))
            except ValueError as exception:
                failures.append(f'{sid}/{name}: {exception}')
                continue
            if len(values) != len(times):
                failures.append(f'{sid}/{name}: data and time lengths differ')
    if role == 'candidate':
        if evidence.get('score_inputs_valid') is not True:
            failures.append('candidate score_inputs_valid is not true')
        if evidence.get('all_scenarios_valid') is not True:
            failures.append('candidate all_scenarios_valid is not true')
        failures.extend(_validate_application(evidence))
    return (not failures, failures)

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    reference_valid, reference_failures = validate(reference, 'reference')
    candidate_valid, candidate_failures = validate(candidate, 'candidate')
    if not reference_valid:
        raise ValueError('reference evidence is invalid: ' + '; '.join(reference_failures))
    original_validate = SOURCE.validate
    try:
        SOURCE.validate = lambda value: (reference_valid, reference_failures) if value is reference else (candidate_valid, candidate_failures)
        result = SOURCE.score(reference, candidate)
    finally:
        SOURCE.validate = original_validate
    result['schema'] = 'simuverity.f90-xauto11-score.v1'
    result['status'] = 'SCORED' if result.get('G') == 1 else 'INVALID_EVIDENCE'
    result['failure_attribution'] = '' if result.get('G') == 1 else 'candidate_evidence_or_runtime'
    result['groups'] = copy.deepcopy(result.get('group_scores', {}))
    result['scenarios'] = copy.deepcopy(result.get('per_scenario', {}))
    result['weights'] = dict(WEIGHTS)
    result['gate_semantics'] = 'G checks runnable complete evidence and verified scenario application only; performance is scored in A/M/C/R/D'
    return result

def shortcut_sanity(reference: dict[str, Any]) -> dict[str, Any]:
    candidate = copy.deepcopy(reference)
    candidate['evaluation_subject'] = 'candidate'
    candidate['input_application_contract'] = EXPECTED_APPLICATION_CONTRACT
    candidate['input_application_all_pass'] = True
    for index, scenario in enumerate(candidate['scenarios']):
        scenario['scenario_application_pass'] = True
        scenario['simulation_pass'] = True
        scenario['applied_parameters'] = copy.deepcopy(scenario['input'])
        scenario.setdefault('offline_metrics', {})['input_application_log'] = {'pass': True, 'requested_parameters': copy.deepcopy(scenario['input']), 'base_value_before_simulation_matches_requested': True, 'simulationinput_and_base_match': True, 'base_value_after_simulation_matches_requested': True}
    missing = copy.deepcopy(candidate)
    del missing['scenarios'][0]['logs']['active_control_state']
    missing_score = score(reference, missing)
    zero_force = copy.deepcopy(candidate)
    for scenario in zero_force['scenarios']:
        log = scenario['logs']['active_control_state']
        log['data'] = [[0.0, 0.0] for _ in log['time']]
    zero_force_score = score(reference, zero_force)
    return {'schema': 'simuverity.f90-xauto11-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'cases': [{'id': 'missing_required_log', 'G': missing_score['G'], 'raw_total': missing_score['raw_total']}, {'id': 'zero_control_and_force_performance', 'G': zero_force_score['G'], 'raw_total': zero_force_score['raw_total']}]}

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
