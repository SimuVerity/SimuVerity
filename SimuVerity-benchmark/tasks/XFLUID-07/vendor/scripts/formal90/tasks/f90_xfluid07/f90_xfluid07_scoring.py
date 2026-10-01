"""Dedicated offline scorer for F90-XFLUID-07 fixed evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XFLUID-07'
POLICY_ID = 'simuverity-101-v1:f90-xfluid-07:scoring'
REQUIRED_IDS = {'nominal_ramp', 'reduced_speed_ramp', 'staged_acceleration', 'late_acceleration', 'reduced_engine_speed', 'reduced_engine_reduced_ramp'}
WEIGHTS = {'A': 0.1, 'Q': 0.35, 'M': 0.25, 'R': 0.15, 'D': 0.15}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def lower_better(value: float, full: float, zero: float) -> float:
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clamp((zero - value) / (zero - full))

def higher_better(value: float, zero: float, full: float) -> float:
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clamp((value - zero) / (full - zero))

def band_score(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return higher_better(value, low_zero, low_full)
    return lower_better(value, high_full, high_zero)

def weighted_mean(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    if denominator <= 0:
        return 0.0
    return sum((clamp(value) * weight for value, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[key] <= 0 for key in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS)))

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row['id']): row for row in evidence.get('scenarios', [])}

def relative_change(base: float, changed: float) -> float:
    return abs(changed - base) / max(abs(base), 1e-09)

def physical_topology_score(static: dict[str, Any]) -> float:
    """Credit a connected physical network without inspecting block names."""
    if bool(static.get('causal_hydro_mechanical_signature')):
        return 1.0
    return higher_better(float(static.get('physical_connection_block_count_observation', 0.0)), 0.0, 8.0)

def behavioral_qualification(rows: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Qualification from declared inputs and public dynamic outputs only."""
    result: dict[str, Any] = {'causal_hydro_mechanical_path': False, 'closed_loop_speed_control': False, 'front_drive_path': False, 'rear_drive_path': False, 'target_response_gain': 0.0, 'maximum_pump_displacement_range_cm3_rev': 0.0}
    if set(rows) != REQUIRED_IDS or not all((bool(rows[key].get('valid')) for key in REQUIRED_IDS)):
        return result
    nominal = rows['nominal_ramp']['metrics']
    reduced = rows['reduced_speed_ramp']['metrics']
    target_delta = abs(float(nominal['requested_profile_final_mps']) - float(reduced['requested_profile_final_mps']))
    measured_delta = abs(float(nominal['final_tractor_speed_mps']) - float(reduced['final_tractor_speed_mps']))
    target_response_gain = measured_delta / max(target_delta, 1e-09)
    pump_range = max((float(rows[key]['metrics']['pump_displacement_range_cm3_rev']) for key in REQUIRED_IDS))
    front_drive = abs(float(nominal['front_motor_speed_rpm'])) > 1.0 and float(nominal['front_motor_torque_rms_nm']) > 0.1 and (float(nominal['front_motor_flow_rms_m3_s']) > 1e-09)
    rear_drive = abs(float(nominal['rear_motor_speed_rpm'])) > 1.0 and float(nominal['rear_motor_torque_rms_nm']) > 0.1 and (float(nominal['rear_motor_flow_rms_m3_s']) > 1e-09)
    hydraulic_effort = float(nominal['maximum_loop_pressure_bar']) > 1.0 and float(nominal['late_mean_input_power_kw']) > 0.01 and (float(nominal['late_mean_output_power_kw']) > 0.01) and (pump_range > 1.0)
    closed_loop = target_delta > 0.05 and target_response_gain >= 0.2 and (float(nominal['tracking_normalized_rmse']) <= 0.8) and (pump_range > 1.0)
    result.update({'causal_hydro_mechanical_path': bool(hydraulic_effort and front_drive and rear_drive), 'closed_loop_speed_control': bool(closed_loop), 'front_drive_path': bool(front_drive), 'rear_drive_path': bool(rear_drive), 'target_response_gain': target_response_gain, 'maximum_pump_displacement_range_cm3_rev': pump_range})
    return result

def operability(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    m = row['metrics']
    parts = {'tracking': (lower_better(float(m['tracking_normalized_rmse']), 0.1, 0.4), 0.2), 'final_tracking': (lower_better(float(m['final_tracking_relative_error']), 0.05, 0.25), 0.1), 'pressure_bounded': (lower_better(float(m['maximum_loop_pressure_bar']), 260.0, 330.0), 0.1), 'finite_physics': (higher_better(float(m['finite_fraction']), 0.99, 1.0), 0.1), 'no_sustained_reverse': (lower_better(float(m['negative_vehicle_speed_fraction']), 0.0, 0.08), 0.05), 'limited_saturation': (lower_better(float(m['pump_saturation_fraction']), 0.25, 0.9), 0.45)}
    return (weighted_mean(parts), parts)

def dynamic_quality(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    m = row['metrics']
    parts = {'cold_start': (lower_better(float(m['cold_start_rise_time_s']), 20.0, 70.0), 0.25), 'final_command_settling': (lower_better(float(m['final_command_settling_time_s']), 12.0, 60.0), 0.35), 'late_tracking': (lower_better(float(m['late_tracking_rmse_mps']), 0.1, 0.8), 0.1), 'late_speed_stability': (lower_better(float(m['late_vehicle_speed_cv']), 0.01, 0.12), 0.1), 'limited_saturation': (lower_better(float(m['pump_saturation_fraction']), 0.25, 0.9), 0.2)}
    return (weighted_mean(parts), parts)

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = scenario_map(evidence)
    static = evidence.get('static_audit', {})
    behavior = behavioral_qualification(rows)
    qualification_checks = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'scenario_set': set(rows) == REQUIRED_IDS, 'all_scenarios_valid': set(rows) == REQUIRED_IDS and all((bool(rows[key].get('valid')) for key in REQUIRED_IDS)), 'required_products': bool(static.get('required_products_available')), 'causal_hydro_mechanical_path': bool(behavior['causal_hydro_mechanical_path']), 'closed_loop_speed_control': bool(behavior['closed_loop_speed_control']), 'front_drive_path': bool(behavior['front_drive_path']), 'rear_drive_path': bool(behavior['rear_drive_path'])}
    gate = all(qualification_checks.values())
    if not gate:
        return {'schema': 'simuverity.f90-xfluid07-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 0.0, 'groups': {'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 'group_weights': WEIGHTS, 'score_raw': 0.0, 'admission_threshold_raw': 85.0, 'admission_pass': False, 'qualification_checks': qualification_checks, 'qualification_witnesses': behavior, 'failures': [name for name, passed in qualification_checks.items() if not passed]}
    nominal = rows['nominal_ramp']['metrics']
    nominal_operability, nominal_operability_parts = operability(rows['nominal_ramp'])
    group_a_parts = {'tracking_rmse': (lower_better(float(nominal['tracking_normalized_rmse']), 0.07, 0.35), 0.25), 'final_tracking': (lower_better(float(nominal['final_tracking_relative_error']), 0.03, 0.2), 0.15), 'bounded_pressure': (lower_better(float(nominal['maximum_loop_pressure_bar']), 250.0, 325.0), 0.1), 'complete_finite_output': (higher_better(float(nominal['finite_fraction']), 0.995, 1.0), 0.1), 'control_authority_reserve': (lower_better(float(nominal['pump_saturation_fraction']), 0.25, 0.9), 0.3)}
    group_a = weighted_mean(group_a_parts)
    efficiency = float(nominal['late_energy_efficiency'])
    loss_kw = float(nominal['late_transmission_loss_kw'])
    input_power_kw = float(nominal['late_mean_input_power_kw'])
    loss_fraction = loss_kw / max(abs(input_power_kw), 1e-09)
    group_q_parts = {'axle_speed_consistency': (lower_better(float(nominal['axle_speed_relative_mismatch']), 0.18, 0.45), 0.05), 'axle_torque_participation': (lower_better(float(nominal['axle_torque_relative_mismatch']), 0.15, 0.75), 0.05), 'axle_flow_consistency': (lower_better(float(nominal['axle_flow_relative_mismatch']), 0.15, 0.45), 0.05), 'pressure_quality': (lower_better(float(nominal['late_pressure_ripple_fraction']), 0.03, 0.25), 0.05), 'energy_efficiency_physical': (band_score(efficiency, 0.25, 0.5, 0.85, 0.98), 0.35), 'transmission_loss_fraction_physical': (band_score(loss_fraction, 0.02, 0.15, 0.6, 0.85), 0.45)}
    group_q = weighted_mean(group_q_parts)
    reduced = rows['reduced_speed_ramp']['metrics']
    staged = rows['staged_acceleration']['metrics']
    late_profile = rows['late_acceleration']['metrics']
    low_engine = rows['reduced_engine_speed']['metrics']
    target_delta = abs(float(nominal['requested_profile_final_mps']) - float(reduced['requested_profile_final_mps']))
    measured_delta = abs(float(nominal['final_tractor_speed_mps']) - float(reduced['final_tractor_speed_mps']))
    target_response_gain = measured_delta / max(target_delta, 1e-09)

    def load_response(changed: dict[str, Any]) -> float:
        return max(relative_change(float(nominal['late_mean_input_power_kw']), float(changed['late_mean_input_power_kw'])), relative_change(float(nominal['maximum_loop_pressure_bar']), float(changed['maximum_loop_pressure_bar'])), relative_change(float(nominal['final_tractor_speed_mps']), float(changed['final_tractor_speed_mps'])))
    engine_response = max(relative_change(float(nominal['final_engine_speed_rpm']), float(low_engine['final_engine_speed_rpm'])), load_response(low_engine))
    group_m_parts = {'connected_physical_topology': (physical_topology_score(static), 0.4), 'pump_to_hydraulic_effort': (higher_better(float(nominal['pressure_to_pump_torque_abs_correlation']), 0.05, 0.4), 0.1), 'active_variable_pump': (higher_better(float(nominal['pump_displacement_range_cm3_rev']), 1.0, 12.0), 0.1), 'target_profile_causal': (band_score(target_response_gain, 0.2, 0.7, 1.3, 1.8), 0.1), 'distinct_dynamic_profiles': (higher_better(max(relative_change(float(nominal['tracking_rmse_mps']), float(staged['tracking_rmse_mps'])), relative_change(float(nominal['tracking_rmse_mps']), float(late_profile['tracking_rmse_mps'])), relative_change(float(nominal['pump_displacement_range_cm3_rev']), float(staged['pump_displacement_range_cm3_rev']))), 0.05, 0.3), 0.2), 'engine_speed_causal': (higher_better(engine_response, 0.03, 0.1), 0.05), 'both_axles_deliver_effort': (1.0 if float(nominal['front_motor_torque_rms_nm']) > 0.1 and float(nominal['rear_motor_torque_rms_nm']) > 0.1 else 0.0, 0.05)}
    group_m = weighted_mean(group_m_parts)
    robustness_by_scenario: dict[str, float] = {}
    robustness_parts: dict[str, Any] = {}
    dynamic_by_scenario: dict[str, float] = {}
    dynamic_parts: dict[str, Any] = {}
    for key in sorted(REQUIRED_IDS):
        robustness_by_scenario[key], robustness_parts[key] = operability(rows[key])
        dynamic_by_scenario[key], dynamic_parts[key] = dynamic_quality(rows[key])
    group_r = min(robustness_by_scenario.values())
    group_d = min(dynamic_by_scenario.values())
    groups = {'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    raw = 100.0 * geometric(groups)
    return {'schema': 'simuverity.f90-xfluid07-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score_raw': raw, 'admission_threshold_raw': 85.0, 'admission_pass': raw >= 85.0, 'qualification_checks': qualification_checks, 'qualification_witnesses': behavior, 'details': {'A': group_a_parts, 'Q': group_q_parts, 'M': {'parts': group_m_parts, 'physical_connection_block_count_observation': float(static.get('physical_connection_block_count_observation', 0.0)), 'target_response_gain': target_response_gain, 'official_input_response': {'engine_speed': engine_response}}, 'R': {'aggregation': '100_percent_minimum', 'by_scenario': robustness_by_scenario, 'parts': robustness_parts, 'nominal_operability': nominal_operability, 'nominal_parts': nominal_operability_parts}, 'D': {'aggregation': '100_percent_minimum', 'by_scenario': dynamic_by_scenario, 'parts': dynamic_parts}}, 'failures': []}

def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['valid'] = False
    cases.append(('required_output_missing', missing_output, 0.0))
    no_loop = copy.deepcopy(evidence)
    same_speed = scenario_map(no_loop)['nominal_ramp']['metrics']['final_tractor_speed_mps']
    for row in no_loop['scenarios']:
        row['metrics']['final_tractor_speed_mps'] = same_speed
        row['metrics']['pump_displacement_range_cm3_rev'] = 0.0
    cases.append(('closed_loop_path_missing', no_loop, 0.0))
    no_hydraulic = copy.deepcopy(evidence)
    for row in no_hydraulic['scenarios']:
        metric = row['metrics']
        metric['maximum_loop_pressure_bar'] = 0.0
        metric['late_mean_input_power_kw'] = 0.0
        metric['late_mean_output_power_kw'] = 0.0
        metric['pump_displacement_range_cm3_rev'] = 0.0
        metric['front_motor_torque_rms_nm'] = 0.0
        metric['rear_motor_torque_rms_nm'] = 0.0
    cases.append(('hydraulic_power_path_missing', no_hydraulic, 0.0))
    rear_missing = copy.deepcopy(evidence)
    for row in rear_missing['scenarios']:
        metric = row['metrics']
        metric['rear_motor_speed_rpm'] = 0.0
        metric['rear_motor_torque_rms_nm'] = 0.0
        metric['rear_motor_flow_rms_m3_s'] = 0.0
    cases.append(('rear_drive_missing', rear_missing, 0.0))
    copied_target = copy.deepcopy(evidence)
    for row in copied_target['scenarios']:
        row['metrics']['tracking_normalized_rmse'] = 0.0
        row['metrics']['tracking_rmse_mps'] = 0.0
        row['metrics']['late_tracking_rmse_mps'] = 0.0
        row['metrics']['final_tracking_relative_error'] = 0.0
        row['metrics']['tracking_r2'] = 1.0
        row['metrics']['pump_displacement_range_cm3_rev'] = 0.0
        row['metrics']['error_to_pump_abs_correlation'] = 0.0
    cases.append(('target_copied_to_measured_speed', copied_target, 60.0))
    fixed_pump = copy.deepcopy(evidence)
    for row in fixed_pump['scenarios']:
        row['metrics']['pump_displacement_range_cm3_rev'] = 0.0
        row['metrics']['error_to_pump_abs_correlation'] = 0.0
    cases.append(('fixed_pump_command', fixed_pump, 75.0))
    insensitive = copy.deepcopy(evidence)
    nominal_metrics = copy.deepcopy(scenario_map(insensitive)['nominal_ramp']['metrics'])
    for row in insensitive['scenarios']:
        requested = {key: value for key, value in row['metrics'].items() if key.startswith('requested_')}
        row['metrics'] = copy.deepcopy(nominal_metrics)
        row['metrics'].update(requested)
    cases.append(('scenario_inputs_ignored', insensitive, 70.0))
    zero_loss = copy.deepcopy(evidence)
    for row in zero_loss['scenarios']:
        row['metrics']['late_transmission_loss_kw'] = 0.0
        row['metrics']['late_energy_efficiency'] = 1.0
    cases.append(('nonphysical_zero_loss', zero_loss, 60.0))
    results = []
    for name, mutated, maximum in cases:
        result = score(mutated)
        value = float(result['score_raw'])
        results.append({'id': name, 'score_raw': value, 'required_maximum': maximum, 'pass': value <= maximum + 1e-09})
    return {'schema': 'simuverity.f90-xfluid07-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': results, 'pass': all((item['pass'] for item in results))}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score(evidence)
    text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    if args.sanity_out:
        sanity = run_shortcut_sanity(evidence)
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(json.dumps(sanity, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(text)
if __name__ == '__main__':
    main()
