"""Pure-offline XAERO-07 scorer with explicit missing-component zeros."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from statistics import mean
from typing import Any
import f90_xaero07_scoring_core as core
TASK_ID = core.TASK_ID
SCENARIOS = core.SCENARIOS
LOGS = core.LOGS
STRUCTURE = core.STRUCTURE
WEIGHTS = core.WEIGHTS
WIDTHS = {'flight_distance': 1, 'battery_state': 3, 'motor_current': 1, 'low_voltage_load_power': 1}

def mask(log: dict[str, Any], width: int) -> list[bool]:
    raw = log.get('availability')
    if isinstance(raw, bool) and width == 1:
        return [raw]
    if isinstance(raw, list) and len(raw) == width:
        return [item is True for item in raw]
    return []

def sources_valid(log: dict[str, Any], width: int) -> bool:
    raw = log.get('sources')
    return width == 1 and isinstance(raw, str) or (isinstance(raw, list) and len(raw) == width)

def metric_present(scenario: dict[str, Any], name: str) -> bool:
    availability = scenario.get('metric_availability')
    if availability is None:
        return True
    return availability.get(name) is True

def gate(evidence: dict[str, Any], path: Path) -> tuple[bool, list[str], dict[str, Any]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('wrong_task_id')
    for key in ('load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'runtime_model_unchanged', 'evidence_complete'):
        if evidence.get(key) is not True:
            failures.append(key)
    audit = evidence.get('static_audit', {})
    if audit.get('core_path_qualified') is not True:
        failures.append('anti_cheat:connected_dynamic_core')
    if evidence.get('open_plant_not_fcc_or_ndi') is not True:
        failures.append('anti_cheat:invalid_closed_loop_claim')
    scenarios = core.scenario_map(evidence)
    if list(scenarios) != SCENARIOS:
        failures.append('scenario_set_or_order')
    for sid in SCENARIOS:
        scenario = scenarios.get(sid)
        if not scenario or scenario.get('valid') is not True:
            failures.append(f'{sid}:invalid')
            continue
        logs = scenario.get('logs', {})
        if set(logs) != LOGS:
            failures.append(f'{sid}:output_contract')
            continue
        for name, width in WIDTHS.items():
            log = logs[name]
            if int(log.get('channels', 0)) != width or int(log.get('samples', 0)) < 100:
                failures.append(f'{sid}:{name}_shape')
            if len(mask(log, width)) != width or not sources_valid(log, width):
                failures.append(f'{sid}:{name}_identity_map')
        data_path = path.parent / scenario.get('data_file', '')
        if not data_path.is_file():
            failures.append(f'{sid}:missing_data_file')
        if scenario.get('metrics', {}).get('all_finite') is not True:
            failures.append(f'{sid}:nonfinite')
    axes = core.axes(scenarios)
    return (not failures, failures, axes)

def score(evidence: dict[str, Any], path: Path, evidence_role: str='candidate') -> dict[str, Any]:
    if evidence_role == 'reference':
        passed, failures, axes = core.gate(evidence, path)
    elif evidence_role == 'candidate':
        passed, failures, axes = gate(evidence, path)
    else:
        raise ValueError(f'unsupported evidence_role: {evidence_role}')
    scenarios = core.scenario_map(evidence)
    if not passed:
        groups = {name: 0.0 for name in WEIGHTS}
        raw = 0.0
        missing: list[str] = []
    else:
        rows = [scenarios[sid] for sid in SCENARIOS]
        metrics = [row['metrics'] for row in rows]
        distance = mean((core.high(float(m['flight_distance_km']), 40, 60) if metric_present(row, 'flight_distance_km') else 0.0 for row, m in zip(rows, metrics)))
        duration = mean((core.high(float(m['flight_duration_s']), 900, 1400) if metric_present(row, 'flight_duration_s') else 0.0 for row, m in zip(rows, metrics)))
        depletion = mean((core.high(float(m['battery_charge_used_Ah']), 40, 60) if metric_present(row, 'battery_charge') else 0.0 for row, m in zip(rows, metrics)))
        groups = {'A': mean([distance, duration, depletion])}
        voltage = mean((core.low(max(0, 80 - float(m['battery_voltage_min_V'])), 0, 30) if metric_present(row, 'battery_voltage') else 0.0 for row, m in zip(rows, metrics)))
        battery_current = mean((core.low(float(m['battery_current_abs_max_A']), 600, 900) if metric_present(row, 'battery_current') else 0.0 for row, m in zip(rows, metrics)))
        groups['Q'] = mean([100.0, voltage, battery_current])
        mechanism = 100 * mean((1.0 if evidence.get('structure', {}).get(key) is True else 0.0 for key in STRUCTURE))
        motor = mean((core.high(float(m['motor_current_rms_A']), 1, 20) if metric_present(row, 'motor_current') else 0.0 for row, m in zip(rows, metrics)))
        loads = 100 * mean((1.0 if metric_present(row, 'low_voltage_load_power') and m['load_switching_present'] else 0.0 for row, m in zip(rows, metrics)))
        groups['M'] = mean([mechanism, motor, loads])
        capacity = max(core.high(float(axes['battery_capacity_distance_delta_km']), 1, 5), core.high(float(axes['battery_capacity_duration_delta_s']), 10, 100))
        payload = max(core.high(float(axes['payload_distance_delta_km']), 1, 5), core.high(float(axes['payload_duration_delta_s']), 10, 100))
        groups['C'] = mean([capacity, payload])
        scenario_quality = []
        for row, m in zip(rows, metrics):
            current_component = core.low(float(m['battery_current_abs_max_A']), 600, 900) if metric_present(row, 'battery_current') else 0.0
            scenario_quality.append(mean([core.high(float(m['flight_distance_km']), 40, 60), core.high(float(m['flight_duration_s']), 900, 1400), current_component]))
        groups['R'] = min(scenario_quality)
        charge_evolution = mean((core.high(float(m['battery_charge_used_Ah']), 20, 40) if metric_present(row, 'battery_charge') else 0.0 for row, m in zip(rows, metrics)))
        mission = mean((core.high(float(m['flight_duration_s']), 500, 1000) for m in metrics))
        switching = 100 * mean((1.0 if metric_present(row, 'low_voltage_load_power') and m['load_switching_present'] else 0.0 for row, m in zip(rows, metrics)))
        groups['D'] = mean([charge_evolution, mission, switching])
        groups = {name: round(max(0.0, min(100.0, value)), 9) for name, value in groups.items()}
        raw = round(sum((WEIGHTS[name] * groups[name] for name in WEIGHTS)), 9)
        missing = sorted({name for row in rows for name, present in row.get('metric_availability', {}).items() if present is not True})
    performance_reasons = []
    if passed and (not axes['battery_capacity_effective']):
        performance_reasons.append('battery_capacity_intervention_low_or_absent')
    if passed and (not axes['payload_mass_effective']):
        performance_reasons.append('payload_intervention_low_or_absent')
    return {'schema': 'simuverity.f90-xaero07-offline-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'score_eligible': passed, 'gate': {'G': 1 if passed else 0, 'passed': passed, 'failures': failures}, 'weights': WEIGHTS, 'group_scores': groups, 'raw_score': raw, 'axis_metrics': axes, 'scenario_metrics': {sid: scenarios.get(sid, {}).get('metrics', {}) for sid in SCENARIOS}, 'unavailable_metric_components_scored_zero': missing, 'performance_failure_reasons': performance_reasons, 'failure_reasons': failures}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('output_dir', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    (args.output_dir / 'score.json').write_text(json.dumps(score(evidence, args.evidence), indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
