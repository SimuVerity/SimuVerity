from __future__ import annotations
import argparse, copy, json
from pathlib import Path
from statistics import mean
from typing import Any
TASK_ID = 'F90-XAERO-07'
SCENARIOS = ['nominal_design', 'increased_capacity', 'added_payload', 'capacity_with_payload', 'mid_design']
LOGS = {'flight_distance', 'battery_state', 'motor_current', 'low_voltage_load_power'}
STRUCTURE = ['height_based_flight_cycle', 'finite_mass_aerodynamic_aircraft_load', 'thrust_and_shaft_load_conversion', 'controlled_motor_and_drive', 'high_voltage_battery', 'dc_conversion_and_distribution', 'switched_lamp_heater_avionics_loads', 'open_plant_not_fcc_or_ndi']
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.25, 'C': 0.2, 'R': 0.1, 'D': 0.1}

def high(x: float, lo: float, hi: float) -> float:
    return 100 * max(0, min(1, (x - lo) / (hi - lo)))

def low(x: float, good: float, bad: float) -> float:
    return 100 * max(0, min(1, (bad - x) / (bad - good)))

def scenario_map(e: dict[str, Any]) -> dict[str, Any]:
    return {s.get('id', ''): s for s in e.get('scenarios', [])}

def axes(sm: dict[str, Any]) -> dict[str, Any]:
    n = sm.get(SCENARIOS[0], {}).get('metrics', {})
    b = sm.get(SCENARIOS[1], {}).get('metrics', {})
    p = sm.get(SCENARIOS[2], {}).get('metrics', {})
    out = {'battery_capacity_distance_delta_km': abs(float(b.get('flight_distance_km', 0)) - float(n.get('flight_distance_km', 0))), 'battery_capacity_duration_delta_s': abs(float(b.get('flight_duration_s', 0)) - float(n.get('flight_duration_s', 0))), 'payload_distance_delta_km': abs(float(p.get('flight_distance_km', 0)) - float(n.get('flight_distance_km', 0))), 'payload_duration_delta_s': abs(float(p.get('flight_duration_s', 0)) - float(n.get('flight_duration_s', 0)))}
    out['battery_capacity_effective'] = out['battery_capacity_distance_delta_km'] >= 1 or out['battery_capacity_duration_delta_s'] >= 10
    out['payload_mass_effective'] = out['payload_distance_delta_km'] >= 1 or out['payload_duration_delta_s'] >= 10
    return out

def gate(e: dict[str, Any], path: Path) -> tuple[bool, list[str], dict[str, Any]]:
    f = []
    if e.get('task_id') != TASK_ID:
        f.append('wrong_task_id')
    for k in ['load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'runtime_model_unchanged']:
        if e.get(k) is not True:
            f.append(k)
    if e.get('open_plant_not_fcc_or_ndi') is not True:
        f.append('invalid_closed_loop_claim')
    sm = scenario_map(e)
    if list(sm) != SCENARIOS:
        f.append('scenario_set_or_order')
    for sid in SCENARIOS:
        s = sm.get(sid)
        if not s or s.get('valid') is not True:
            f.append(f'{sid}:invalid')
            continue
        if set(s.get('logs', {})) != LOGS:
            f.append(f'{sid}:output_contract')
        p = path.parent / s.get('data_file', '')
        if not p.is_file():
            f.append(f'{sid}:missing_data_file')
        m = s.get('metrics', {})
        if m.get('all_finite') is not True:
            f.append(f'{sid}:nonfinite')
        if any((int(s.get('logs', {}).get(k, {}).get('samples', 0)) < 100 for k in LOGS)):
            f.append(f'{sid}:short_evidence')
        if float(m.get('motor_current_rms_A', 0)) <= 1:
            f.append(f'{sid}:missing_motor_demand')
        if m.get('load_switching_present') is not True:
            f.append(f'{sid}:missing_load_switching')
    for k in STRUCTURE:
        if e.get('structure', {}).get(k) is not True:
            f.append('structure:' + k)
    ax = axes(sm)
    if not ax['battery_capacity_effective']:
        f.append('causal:battery_capacity_Ah')
    if not ax['payload_mass_effective']:
        f.append('causal:payload_mass_kg')
    return (not f, f, ax)

def score(e: dict[str, Any], path: Path) -> dict[str, Any]:
    passed, fail, ax = gate(e, path)
    sm = scenario_map(e)
    if not passed:
        groups = {k: 0.0 for k in WEIGHTS}
        raw = 0.0
    else:
        ms = [sm[x]['metrics'] for x in SCENARIOS]
        distance = mean((high(float(m['flight_distance_km']), 40, 60) for m in ms))
        duration = mean((high(float(m['flight_duration_s']), 900, 1400) for m in ms))
        depletion = mean((high(float(m['battery_charge_used_Ah']), 40, 60) for m in ms))
        groups = {'A': mean([distance, duration, depletion])}
        voltage = mean((low(max(0, 80 - float(m['battery_voltage_min_V'])), 0, 30) for m in ms))
        current = mean((low(float(m['battery_current_abs_max_A']), 600, 900) for m in ms))
        groups['Q'] = mean([100.0, voltage, current])
        mechanism = 100 * mean((1.0 if e['structure'].get(k) is True else 0.0 for k in STRUCTURE))
        motor = mean((high(float(m['motor_current_rms_A']), 1, 20) for m in ms))
        loads = 100 * mean((1.0 if m['load_switching_present'] else 0.0 for m in ms))
        groups['M'] = mean([mechanism, motor, loads])
        cap = max(high(float(ax['battery_capacity_distance_delta_km']), 1, 5), high(float(ax['battery_capacity_duration_delta_s']), 10, 100))
        payload = max(high(float(ax['payload_distance_delta_km']), 1, 5), high(float(ax['payload_duration_delta_s']), 10, 100))
        groups['C'] = mean([cap, payload])
        scenario_quality = [mean([high(float(m['flight_distance_km']), 40, 60), high(float(m['flight_duration_s']), 900, 1400), low(float(m['battery_current_abs_max_A']), 600, 900)]) for m in ms]
        groups['R'] = min(scenario_quality)
        charge_evolution = mean((high(float(m['battery_charge_used_Ah']), 20, 40) for m in ms))
        mission = mean((high(float(m['flight_duration_s']), 500, 1000) for m in ms))
        switching = 100 * mean((1.0 if m['load_switching_present'] else 0.0 for m in ms))
        groups['D'] = mean([charge_evolution, mission, switching])
        groups = {k: round(max(0, min(100, v)), 9) for k, v in groups.items()}
        raw = round(sum((WEIGHTS[k] * groups[k] for k in WEIGHTS)), 9)
    return {'schema': 'simuverity.f90-xaero07-offline-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'score_eligible': passed, 'gate': {'G': 1 if passed else 0, 'passed': passed, 'failures': fail}, 'weights': WEIGHTS, 'group_scores': groups, 'raw_score': raw, 'axis_metrics': ax, 'scenario_metrics': {x: sm.get(x, {}).get('metrics', {}) for x in SCENARIOS}, 'failure_reasons': fail}

def sanity(e: dict[str, Any], path: Path) -> dict[str, Any]:
    cases = []

    def run(name, m):
        s = score(m, path)
        cases.append({'id': name, 'raw_score': s['raw_score'], 'G': s['gate']['G'], 'failures': s['gate']['failures']})
    for name, log in [('missing_battery_state', 'battery_state'), ('missing_motor_current', 'motor_current'), ('missing_auxiliary_load_power', 'low_voltage_load_power')]:
        m = copy.deepcopy(e)
        for s in m['scenarios']:
            s['logs'].pop(log, None)
        run(name, m)
    m = copy.deepcopy(e)
    base = copy.deepcopy(m['scenarios'][0])
    for i in range(1, len(m['scenarios'])):
        keep = {k: m['scenarios'][i][k] for k in ['id', 'inputs', 'data_file'] if k in m['scenarios'][i]}
        m['scenarios'][i] = copy.deepcopy(base)
        m['scenarios'][i].update(keep)
    run('fixed_outputs_across_scenarios', m)
    m = copy.deepcopy(e)
    m['scenarios'][1]['metrics'] = copy.deepcopy(m['scenarios'][0]['metrics'])
    run('capacity_without_effect', m)
    m = copy.deepcopy(e)
    m['scenarios'][2]['metrics'] = copy.deepcopy(m['scenarios'][0]['metrics'])
    run('payload_without_effect', m)
    m = copy.deepcopy(e)
    m['structure']['finite_mass_aerodynamic_aircraft_load'] = False
    m['structure']['high_voltage_battery'] = False
    run('disconnected_aircraft_or_power_path', m)
    mx = max((x['raw_score'] for x in cases))
    return {'schema': 'simuverity.f90-xaero07-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'admission_threshold_raw': 85.0, 'cases': cases, 'maximum_shortcut_raw_score': mx, 'all_shortcuts_below_threshold': all((x['raw_score'] < 85 for x in cases))}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('evidence', type=Path)
    p.add_argument('output_dir', type=Path)
    p.add_argument('--shortcut-sanity', action='store_true')
    a = p.parse_args()
    e = json.loads(a.evidence.read_text(encoding='utf-8'))
    a.output_dir.mkdir(parents=True, exist_ok=False)
    (a.output_dir / 'score.json').write_text(json.dumps(score(e, a.evidence), indent=2) + '\n', encoding='utf-8')
    if a.shortcut_sanity:
        (a.output_dir / 'shortcut_sanity.json').write_text(json.dumps(sanity(e, a.evidence), indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
