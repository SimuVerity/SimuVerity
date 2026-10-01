"""Pure offline scorer for fixed F90-XTHERM-08 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XTHERM-08'
POLICY_ID = 'simuverity-101-v1:f90-xtherm-08:scoring'
REQUIRED = ['nominal_variable_week', 'high_server_load', 'hot_humid_weather', 'moderate_joint_capacity', 'chilled_pump_derate', 'chiller_capacity_derate']
WEIGHTS = {'A': 0.2, 'Q': 0.2, 'M': 0.3, 'R': 0.2, 'D': 0.1}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def quantile(values: list[float], fraction: float) -> float:
    if not values:
        return math.nan
    ordered = sorted(values)
    position = fraction * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    mix = position - lower
    return ordered[lower] * (1 - mix) + ordered[upper] * mix

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

def band(value: float, lower_zero: float, lower_full: float, upper_full: float, upper_zero: float) -> float:
    return min(high(value, lower_zero, lower_full), low(value, upper_full, upper_zero))

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

def relative_change(value: float, baseline: float) -> float:
    return abs(value - baseline) / max(abs(baseline), 1e-09)

def correlation(left: list[float], right: list[float]) -> float:
    if len(left) != len(right) or len(left) < 2:
        return 0.0
    left_mean = mean(left)
    right_mean = mean(right)
    numerator = sum(((x - left_mean) * (y - right_mean) for x, y in zip(left, right)))
    denominator = math.sqrt(sum(((x - left_mean) ** 2 for x in left)) * sum(((y - right_mean) ** 2 for y in right)))
    return numerator / denominator if denominator > 1e-12 else 0.0

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    time = list(map(float, outputs['time_s']))
    temperatures = columns(outputs['thermal_state'])
    flow_control = columns(outputs['flow_control_state'])
    heat_power = columns(outputs['heat_power_state'])
    environment = columns(outputs['environment_state'])
    evap, server, exchanger, condenser, tower = temperatures
    chilled_flow, condenser_flow, chilled_cmd, condenser_cmd, chiller_cmd = flow_control
    server_heat, exchanger_heat, evaporator_heat, tower_heat = heat_power[:4]
    compressor, condenser_pump, chilled_pump, tower_fan, total_power = heat_power[4:]
    ambient, humidity, evaporation = environment
    active = [index for index, value in enumerate(time) if value >= 21600.0]
    tail = [index for index, value in enumerate(time) if value >= 0.9 * time[-1]]

    def take(values: list[float], indexes: list[int]=active) -> list[float]:
        return [values[index] for index in indexes]
    total_identity = [total_power[index] - (compressor[index] + condenser_pump[index] + chilled_pump[index] + tower_fan[index]) for index in active]
    total_scale = max(rms(take(total_power)), rms([compressor[index] + condenser_pump[index] + chilled_pump[index] + tower_fan[index] for index in active]), 1.0)
    cop_values = [abs(evaporator_heat[index]) / max(abs(compressor[index]), 1.0) for index in active if abs(compressor[index]) >= 100.0]
    flow_scale = max(rms(take(chilled_flow)), rms(take(condenser_flow)), 1e-09)
    temperature_spread = [max(values) - min(values) for values in zip(take(evap), take(server), take(exchanger), take(condenser), take(tower))]
    return {'evaporator_target_rmse_C': rms([evap[index] - 18.0 for index in active]), 'evaporator_tail_error_C': abs(mean(take(evap, tail)) - 18.0), 'server_temperature_p95_C': quantile(take(server), 0.95), 'server_temperature_max_C': max(take(server)), 'server_above_30_fraction': mean([server[index] > 30.0 for index in active]), 'condenser_tower_delta_p95_C': quantile([condenser[index] - tower[index] for index in active], 0.95), 'temperature_min_C': min((min(take(values)) for values in temperatures)), 'temperature_max_C': max((max(take(values)) for values in temperatures)), 'temperature_path_spread_C': mean(temperature_spread), 'chilled_flow_mean_kgps': mean(take(chilled_flow)), 'chilled_flow_min_kgps': min(take(chilled_flow)), 'condenser_flow_mean_kgps': mean(take(condenser_flow)), 'condenser_flow_min_kgps': min(take(condenser_flow)), 'distinct_flow_path_rms_fraction': rms([chilled_flow[index] - condenser_flow[index] for index in active]) / flow_scale, 'chilled_command_mean': mean(take(chilled_cmd)), 'chilled_command_range': max(take(chilled_cmd)) - min(take(chilled_cmd)), 'condenser_command_mean': mean(take(condenser_cmd)), 'condenser_command_range': max(take(condenser_cmd)) - min(take(condenser_cmd)), 'chiller_command_mean': mean(take(chiller_cmd)), 'chiller_command_range': max(take(chiller_cmd)) - min(take(chiller_cmd)), 'server_heat_mean_W': mean(take(server_heat)), 'exchanger_heat_mean_W': mean(take(exchanger_heat)), 'evaporator_heat_mean_W': mean(take(evaporator_heat)), 'tower_heat_mean_W': mean(take(tower_heat)), 'compressor_power_mean_W': mean(take(compressor)), 'condenser_pump_power_mean_W': mean(take(condenser_pump)), 'chilled_pump_power_mean_W': mean(take(chilled_pump)), 'tower_fan_power_mean_W': mean(take(tower_fan)), 'total_power_mean_W': mean(take(total_power)), 'total_power_identity_relative_rmse': rms(total_identity) / total_scale, 'cop_median': quantile(cop_values, 0.5), 'cop_p05': quantile(cop_values, 0.05), 'ambient_mean_C': mean(take(ambient)), 'humidity_mean': mean(take(humidity)), 'evaporation_mean_kgps': mean(take(evaporation)), 'evaporation_positive_fraction': mean([evaporation[index] > 1e-08 for index in active]), 'load_chilled_command_correlation': correlation(take(server_heat), take(chilled_cmd)), 'weather_evaporation_correlation': max(abs(correlation(take(ambient), take(evaporation))), abs(correlation(take(humidity), take(evaporation)))), 'tail_temperature_drift_C': max((abs(values[tail[-1]] - values[tail[0]]) for values in temperatures))}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    required_outputs = {'time_s', 'thermal_state', 'flow_control_state', 'heat_power_state', 'environment_state'}
    scenarios_valid = all((name in rows and bool(rows[name].get('valid')) and (required_outputs <= set(rows[name].get('outputs', {}))) for name in REQUIRED))
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': scenarios_valid, 'physical_two_loop_three_controller_path': bool(static.get('core_path_qualified'))}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_variable_week']
    high_load = metrics['high_server_load']
    weather = metrics['hot_humid_weather']
    joint = metrics['moderate_joint_capacity']
    pump_derate = metrics['chilled_pump_derate']
    chiller_derate = metrics['chiller_capacity_derate']
    a_parts = {'evaporator_regulation': (low(nominal['evaporator_target_rmse_C'], 0.5, 3.0), 0.35), 'evaporator_tail': (low(nominal['evaporator_tail_error_C'], 0.35, 2.0), 0.1), 'server_temperature': (low(nominal['server_temperature_p95_C'], 28.5, 35.0), 0.25), 'condenser_tower_delta': (low(nominal['condenser_tower_delta_p95_C'], 6.5, 11.0), 0.2), 'bounded_temperatures': (min(high(nominal['temperature_min_C'], 0.0, 8.0), low(nominal['temperature_max_C'], 38.0, 55.0)), 0.1)}
    group_a = weighted(a_parts)
    q_parts = {'positive_chilled_flow': (high(nominal['chilled_flow_min_kgps'], 0.1, 5.0), 0.14), 'positive_condenser_flow': (high(nominal['condenser_flow_min_kgps'], 0.1, 5.0), 0.14), 'distinct_physical_flows': (high(nominal['distinct_flow_path_rms_fraction'], 0.005, 0.05), 0.1), 'temperature_path_spread': (high(nominal['temperature_path_spread_C'], 0.1, 1.5), 0.1), 'power_identity': (low(nominal['total_power_identity_relative_rmse'], 1e-06, 0.02), 0.16), 'physical_cop': (band(nominal['cop_median'], 1.0, 2.0, 20.0, 40.0), 0.14), 'positive_evaporation': (high(nominal['evaporation_positive_fraction'], 0.5, 0.95), 0.12), 'finite_heat_rejection': (high(max(abs(nominal['server_heat_mean_W']), abs(nominal['tower_heat_mean_W'])), 1000.0, 100000.0), 0.1)}
    group_q = weighted(q_parts)
    load_ratio = high_load['server_heat_mean_W'] / max(abs(nominal['server_heat_mean_W']), 1.0)
    weather_delta = abs(weather['ambient_mean_C'] - nominal['ambient_mean_C'])
    humidity_delta = abs(weather['humidity_mean'] - nominal['humidity_mean'])
    pump_flow_reduction = (nominal['chilled_flow_mean_kgps'] - pump_derate['chilled_flow_mean_kgps']) / max(abs(nominal['chilled_flow_mean_kgps']), 1e-09)
    chiller_response = max(relative_change(chiller_derate['chiller_command_mean'], nominal['chiller_command_mean']), relative_change(chiller_derate['evaporator_heat_mean_W'], nominal['evaporator_heat_mean_W']), relative_change(chiller_derate['evaporator_target_rmse_C'], nominal['evaporator_target_rmse_C']))
    m_parts = {'static_two_loop_three_controller_chain': (1.0, 0.25), 'server_load_applied': (band(load_ratio, 1.02, 1.12, 1.28, 1.4), 0.15), 'load_following_response': (high(max(relative_change(high_load['chilled_command_mean'], nominal['chilled_command_mean']), relative_change(high_load['total_power_mean_W'], nominal['total_power_mean_W']), relative_change(high_load['server_temperature_p95_C'], nominal['server_temperature_p95_C'])), 0.005, 0.05), 0.13), 'weather_applied': (min(high(weather_delta, 2.0, 3.5), high(humidity_delta, 0.02, 0.05)), 0.1), 'tower_weather_response': (high(max(relative_change(weather['evaporation_mean_kgps'], nominal['evaporation_mean_kgps']), relative_change(weather['tower_heat_mean_W'], nominal['tower_heat_mean_W']), relative_change(weather['condenser_tower_delta_p95_C'], nominal['condenser_tower_delta_p95_C'])), 0.005, 0.05), 0.12), 'chilled_pump_derate_causality': (high(pump_flow_reduction, 0.01, 0.08), 0.13), 'chiller_capacity_causality': (high(chiller_response, 0.01, 0.08), 0.12)}
    group_m = weighted(m_parts)
    critical_causality = [m_parts['server_load_applied'][0], m_parts['load_following_response'][0], m_parts['weather_applied'][0], m_parts['tower_weather_response'][0], m_parts['chilled_pump_derate_causality'][0], m_parts['chiller_capacity_causality'][0], q_parts['distinct_physical_flows'][0], q_parts['temperature_path_spread'][0]]
    if min(critical_causality) < 0.1:
        group_m = min(group_m, 0.45)
    r_by_scenario: dict[str, float] = {}
    d_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = weighted({'evaporator_control': (low(values['evaporator_target_rmse_C'], 0.75, 4.0), 0.3), 'server_capacity': (low(values['server_temperature_p95_C'], 29.5, 40.0), 0.25), 'server_excursion': (low(values['server_temperature_max_C'], 34.0, 50.0), 0.15), 'condenser_capacity': (low(values['condenser_tower_delta_p95_C'], 7.5, 14.0), 0.15), 'both_flows': (min(high(values['chilled_flow_min_kgps'], 0.05, 2.0), high(values['condenser_flow_min_kgps'], 0.05, 2.0)), 0.15)})
        d_by_scenario[name] = weighted({'bounded_tail_drift': (low(values['tail_temperature_drift_C'], 0.5, 5.0), 0.3), 'chilled_staging': (high(values['chilled_command_range'], 0.05, 0.25), 0.25), 'condenser_staging': (high(values['condenser_command_range'], 0.05, 0.25), 0.25), 'chiller_modulation': (high(values['chiller_command_range'], 0.01, 0.1), 0.2)})
    group_r = min(r_by_scenario.values())
    group_d = min(d_by_scenario.values())
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D_by_scenario': d_by_scenario, 'derived': {'high_load_heat_ratio': load_ratio, 'hot_weather_temperature_delta_C': weather_delta, 'hot_weather_humidity_delta': humidity_delta, 'pump_derate_flow_reduction_fraction': pump_flow_reduction, 'chiller_derate_response_fraction': chiller_response, 'moderate_joint_server_p95_C': joint['server_temperature_p95_C']}}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xtherm08-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.20*M^0.30*R^0.20*D^0.10', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['one_loop_or_missing_physical_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('heat_power_state', None)
    cases['missing_required_output'] = score(missing_output)['score']
    copied_temperatures = copy.deepcopy(evidence)
    for row in copied_temperatures['scenarios']:
        for sample in row['outputs']['thermal_state']:
            sample[:] = [sample[0]] * 5
    cases['copied_temperature_trace'] = score(copied_temperatures)['score']
    one_flow = copy.deepcopy(evidence)
    for row in one_flow['scenarios']:
        for sample in row['outputs']['flow_control_state']:
            sample[1] = sample[0]
    cases['one_replayed_flow_for_two_loops'] = score(one_flow)['score']
    fixed_commands = copy.deepcopy(evidence)
    for row in fixed_commands['scenarios']:
        for sample in row['outputs']['flow_control_state']:
            sample[2:5] = [0.5, 0.5, 0.5]
    cases['fixed_actuator_commands'] = score(fixed_commands)['score']
    hard_coded_power = copy.deepcopy(evidence)
    nominal = next((row for row in hard_coded_power['scenarios'] if row['id'] == 'nominal_variable_week'))
    nominal_power = copy.deepcopy(nominal['outputs']['heat_power_state'])
    for row in hard_coded_power['scenarios']:
        row['outputs']['heat_power_state'] = copy.deepcopy(nominal_power)
    cases['hard_coded_power_and_cop'] = score(hard_coded_power)['score']
    missing_environment = copy.deepcopy(evidence)
    nominal_environment = next((row for row in missing_environment['scenarios'] if row['id'] == 'nominal_variable_week'))['outputs']['environment_state']
    for row in missing_environment['scenarios']:
        row['outputs']['environment_state'] = copy.deepcopy(nominal_environment)
    cases['missing_weather_and_evaporation_coupling'] = score(missing_environment)['score']
    ignored_inputs = copy.deepcopy(evidence)
    nominal_outputs = next((row for row in ignored_inputs['scenarios'] if row['id'] == 'nominal_variable_week'))['outputs']
    for row in ignored_inputs['scenarios']:
        if row['id'] != 'nominal_variable_week':
            row['outputs'] = copy.deepcopy(nominal_outputs)
    cases['ignored_scenario_inputs'] = score(ignored_inputs)['score']
    return {'schema': 'simuverity.f90-xtherm08-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

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
