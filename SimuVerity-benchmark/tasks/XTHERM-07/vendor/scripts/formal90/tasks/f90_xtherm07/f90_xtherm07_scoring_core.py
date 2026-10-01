"""Pure offline scorer for fixed F90-XTHERM-07 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XTHERM-07'
POLICY_ID = 'simuverity-101-v1:f90-xtherm-07:scoring'
REQUIRED = ['nominal', 'high_heat', 'warm_ambient', 'restricted_flow', 'degraded_fan', 'joint_service']
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return (zero - value) / (zero - full)

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return (value - zero) / (full - zero)

def weighted(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    if denominator <= 0:
        return 0.0
    return sum((clamp(score) * weight for score, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[name] * math.log(groups[name]) for name in WEIGHTS)))

def columns(rows: list[list[float]]) -> list[list[float]]:
    return [list(map(float, column)) for column in zip(*rows)]

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    time = list(map(float, outputs['time_s']))
    thermal = columns(outputs['thermal_state'])
    fan = columns(outputs['fan_state'])
    heat = columns(outputs['heat_flow'])
    cpu, base, fins, target = thermal
    speed, mass_flow, pressure = fan
    power, cpu_base, base_fins, fins_air = heat
    active = [i for i, t in enumerate(time) if t >= 1000.0]
    tail = [i for i, t in enumerate(time) if t >= 11000.0]
    error = [cpu[i] - target[i] for i in active]
    gradient_violation = mean([not (cpu[i] + 0.25 >= base[i] and base[i] + 0.25 >= fins[i]) for i in active])
    fan_active = [i for i in active if abs(speed[i]) >= 100.0]
    switching = sum((abs(speed[i] - speed[i - 1]) >= 150.0 for i in range(1, len(speed))))
    return {'temperature_rmse_C': rms(error), 'temperature_tail_error_C': abs(mean([cpu[i] - target[i] for i in tail])), 'peak_cpu_temperature_C': max(cpu), 'minimum_cpu_temperature_C': min(cpu), 'time_in_8C_band_fraction': mean([abs(value) <= 8.0 for value in error]), 'time_in_20C_band_fraction': mean([abs(value) <= 20.0 for value in error]), 'gradient_violation_fraction': gradient_violation, 'mean_abs_cpu_base_delta_C': mean([abs(cpu[i] - base[i]) for i in active]), 'mean_abs_base_fins_delta_C': mean([abs(base[i] - fins[i]) for i in active]), 'fan_max_rpm': max(map(abs, speed)), 'fan_switch_count': float(switching), 'active_air_mass_flow_kgps': mean([abs(mass_flow[i]) for i in fan_active]) if fan_active else 0.0, 'fan_pressure_rise_peak_Pa': max(map(abs, pressure)), 'cpu_heat_rms_W': rms(power), 'cpu_to_base_heat_rms_W': rms(cpu_base), 'base_to_fins_heat_rms_W': rms(base_fins), 'fins_to_air_heat_rms_W': rms(fins_air), 'mean_abs_air_mass_flow_kgps': mean(list(map(abs, mass_flow))), 'mean_fan_speed_rpm': mean(list(map(abs, speed)))}

def dynamic_quality(row: dict[str, Any]) -> tuple[float, dict[str, Any]]:
    outputs = row['outputs']
    time = list(map(float, outputs['time_s']))
    cpu, _, _, target = columns(outputs['thermal_state'])
    starts = [620.0, 4000.0, 7000.0, 8300.0]
    ends = [4000.0, 7000.0, 8300.0, 12000.0]
    segments: list[dict[str, float | None]] = []
    scores: list[float] = []
    for start, end in zip(starts, ends):
        idx = [i for i, t in enumerate(time) if start <= t <= end]
        late = [i for i in idx if time[i] >= end - min(500.0, 0.25 * (end - start))]
        error = [abs(cpu[i] - target[i]) for i in idx]
        late_mean = mean([cpu[i] for i in late])
        late_range = max((cpu[i] for i in late)) - min((cpu[i] for i in late))
        late_drift = abs(cpu[late[-1]] - cpu[late[0]])
        excursion = max((cpu[i] for i in idx)) - min((cpu[i] for i in idx))
        tolerance = max(1.0, 0.1 * excursion)
        recovery = None
        for i in idx:
            future = [j for j in idx if time[i] <= time[j] <= time[i] + 100.0]
            if future and all((abs(cpu[j] - late_mean) <= tolerance for j in future)):
                recovery = time[i] - start
                break
        duration = end - start
        recovery_fraction = None if recovery is None else recovery / duration
        utility = weighted({'recovery': (0.0 if recovery_fraction is None else low(recovery_fraction, 0.45, 0.85), 0.5), 'bounded_late_cycle': (low(late_range, 6.0, 15.0), 0.25), 'no_late_runaway': (low(late_drift, 6.0, 15.0), 0.25)})
        segments.append({'start_s': start, 'late_mean_C': late_mean, 'late_range_C': late_range, 'late_drift_C': late_drift, 'settling_tolerance_C': tolerance, 'peak_error_C': max(error), 'recovery_s': recovery, 'recovery_fraction': recovery_fraction, 'utility': utility})
        scores.append(utility)
    return (min(scores), {'segments': segments})

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    required_outputs = {'time_s', 'thermal_state', 'fan_state', 'heat_flow'}
    scenario_valid = all((name in rows and bool(rows[name].get('valid')) and (required_outputs <= set(rows[name].get('outputs', {}))) for name in REQUIRED))
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': scenario_valid, 'three_thermal_masses': int(static.get('thermal_mass_count', 0)) >= 3, 'two_conductive_paths': int(static.get('conductive_path_count', 0)) >= 2, 'physical_fan_and_gas_path': int(static.get('physical_fan_count', 0)) >= 1 and int(static.get('gas_pipe_count', 0)) >= 1 and (int(static.get('gas_resistance_count', 0)) >= 1), 'temperature_feedback_path': bool(static.get('core_path_qualified'))}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal']
    a_parts = {'temperature_rmse': (low(nominal['temperature_rmse_C'], 7.0, 20.0), 0.4), 'tail_error': (low(nominal['temperature_tail_error_C'], 6.0, 15.0), 0.35), 'peak_temperature': (low(nominal['peak_cpu_temperature_C'], 70.0, 105.0), 0.25)}
    group_a = weighted(a_parts)
    q_parts = {'distinct_thermal_states': (min(high(nominal['mean_abs_cpu_base_delta_C'], 0.01, 0.1), high(nominal['mean_abs_base_fins_delta_C'], 0.01, 0.1)), 0.3), 'fan_speed_bounded': (low(nominal['fan_max_rpm'], 3300.0, 4500.0), 0.15), 'airflow_present': (high(nominal['active_air_mass_flow_kgps'], 0.0002, 0.0005), 0.2), 'pressure_rise_present': (high(nominal['fan_pressure_rise_peak_Pa'], 0.05, 0.3), 0.1), 'three_heat_paths_active': (min(high(nominal['cpu_to_base_heat_rms_W'], 0.1, 5.0), high(nominal['base_to_fins_heat_rms_W'], 0.1, 5.0), high(nominal['fins_to_air_heat_rms_W'], 0.1, 5.0)), 0.25)}
    group_q = weighted(q_parts)
    high_heat = metrics['high_heat']
    warm = metrics['warm_ambient']
    restricted = metrics['restricted_flow']
    degraded = metrics['degraded_fan']
    m_parts = {'static_physical_chain': (1.0, 0.4), 'heat_load_response': (high(high_heat['peak_cpu_temperature_C'] - nominal['peak_cpu_temperature_C'], 0.05, 1.0), 0.15), 'ambient_response': (high(warm['temperature_tail_error_C'] - nominal['temperature_tail_error_C'], -0.05, 0.8), 0.15), 'restriction_changes_pressure': (high((restricted['fan_pressure_rise_peak_Pa'] - nominal['fan_pressure_rise_peak_Pa']) / max(nominal['fan_pressure_rise_peak_Pa'], 1e-09), 0.0005, 0.003), 0.15), 'fan_capacity_changes_speed': (high(nominal['fan_max_rpm'] - degraded['fan_max_rpm'], 50.0, 500.0), 0.15)}
    group_m = weighted(m_parts)
    causal_witnesses = [m_parts['heat_load_response'][0], m_parts['ambient_response'][0], m_parts['restriction_changes_pressure'][0], m_parts['fan_capacity_changes_speed'][0]]
    if min(causal_witnesses) < 0.2:
        group_m = min(group_m, 0.5)
    r_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = weighted({'peak_temperature': (low(values['peak_cpu_temperature_C'], 90.0, 110.0), 0.35), 'tail_error': (low(values['temperature_tail_error_C'], 8.5, 20.0), 0.3), 'band_occupancy': (high(values['time_in_20C_band_fraction'], 0.2, 0.6), 0.2), 'airflow': (high(values['active_air_mass_flow_kgps'], 0.0002, 0.0005), 0.15)})
    group_r = min(r_by_scenario.values())
    d_by_scenario: dict[str, float] = {}
    d_details: dict[str, Any] = {}
    for name in REQUIRED:
        d_by_scenario[name], d_details[name] = dynamic_quality(rows[name])
    group_d = min(d_by_scenario.values())
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D_by_scenario': d_by_scenario, 'D_details': d_details}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xtherm07-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['missing_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('fan_state', None)
    cases['missing_required_output'] = score(missing_output)['score']
    target_copy = copy.deepcopy(evidence)
    for row in target_copy['scenarios']:
        outputs = row['outputs']
        count = len(outputs['time_s'])
        outputs['thermal_state'] = [[50.0, 50.0, 50.0, 50.0] for _ in range(count)]
        outputs['fan_state'] = [[0.0, 0.0, 0.0] for _ in range(count)]
        outputs['heat_flow'] = [[0.0, 0.0, 0.0, 0.0] for _ in range(count)]
    cases['target_copy_disconnected'] = score(target_copy)['score']
    ignored_inputs = copy.deepcopy(evidence)
    nominal = next((row for row in ignored_inputs['scenarios'] if row['id'] == 'nominal'))
    for row in ignored_inputs['scenarios']:
        if row['id'] != 'nominal':
            row['outputs'] = copy.deepcopy(nominal['outputs'])
    cases['ignored_scenario_inputs'] = score(ignored_inputs)['score']
    fixed_fan = copy.deepcopy(evidence)
    nominal_speed = next((row for row in fixed_fan['scenarios'] if row['id'] == 'nominal'))['outputs']['fan_state']
    for row in fixed_fan['scenarios']:
        row['outputs']['fan_state'] = copy.deepcopy(nominal_speed)
    cases['fixed_fan_command'] = score(fixed_fan)['score']
    return {'schema': 'simuverity.f90-xtherm07-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    output = args.out or args.evidence.with_name('offline_score.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(score(evidence), indent=2, ensure_ascii=False), encoding='utf-8')
    if args.sanity_out:
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(json.dumps(shortcut_sanity(evidence), indent=2, ensure_ascii=False), encoding='utf-8')
    print(output)
if __name__ == '__main__':
    main()
