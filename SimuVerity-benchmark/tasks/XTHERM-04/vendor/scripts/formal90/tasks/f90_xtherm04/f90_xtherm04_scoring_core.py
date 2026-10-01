"""Dedicated offline scorer for F90-XTHERM-04 current evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
import h5py
import numpy as np
TASK_ID = 'F90-XTHERM-04'
POLICY_ID = 'simuverity-101-v1:f90-xtherm-04:scoring'
DERIVATION_METHOD = 'f90-xtherm04-uniform-time-thermofluid'
REQUIRED_IDS = {'native_cold_to_hot_transition', 'cold_heating_boundary', 'hot_cooling_boundary', 'high_internal_heat_gain', 'upper_setpoint_boundary'}
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

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

def weighted_mean(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    return sum((clamp(value) * weight for value, weight in parts.values())) / denominator if denominator > 0 else 0.0

def weighted_geometric(groups: dict[str, float]) -> float:
    if any((groups[key] <= 0 for key in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS)))

def rows_by_id(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row['id']): row for row in evidence.get('scenarios', [])}

def metrics_for(row: dict[str, Any]) -> dict[str, Any]:
    return row.get('offline_metrics', row.get('metrics', {}))

def _uniform_matrix(group: h5py.Group, name: str, grid: np.ndarray, time: np.ndarray) -> np.ndarray:
    raw = np.asarray(group[name], dtype=float).T
    return np.column_stack([np.interp(grid, time, raw[:, column]) for column in range(raw.shape[1])])

def _correlation(a: np.ndarray, b: np.ndarray) -> float:
    if a.size < 10 or np.std(a) < 1e-09 or np.std(b) < 1e-09:
        return 0.0
    return float(abs(np.corrcoef(a, b)[0, 1]))

def _first_sustained(grid: np.ndarray, mask: np.ndarray, duration_s: float, step_s: float) -> float:
    count = max(1, int(round(duration_s / step_s)))
    if mask.size < count:
        return -1.0
    rolling = np.convolve(mask.astype(int), np.ones(count, dtype=int), 'valid')
    indices = np.flatnonzero(rolling == count)
    return float(grid[indices[0]]) if indices.size else -1.0

def attach_offline_derivations(evidence: dict[str, Any], raw_path: Path) -> None:
    """Derive all score metrics from immutable raw timeseries."""
    rows = evidence.get('scenarios', [])
    step_s = 10.0
    with h5py.File(raw_path, 'r') as handle:
        signal_refs = handle['artifacts/signals'][0]
        if len(signal_refs) != len(rows):
            raise ValueError('Raw artifact scenario count does not match evidence')
        for row, reference in zip(rows, signal_refs):
            group = handle[reference]
            time = np.asarray(group['time_s'], dtype=float).reshape(-1)
            grid = np.arange(math.ceil(time[0] / step_s) * step_s, math.floor(time[-1] / step_s) * step_s + step_s, step_s)
            thermal = _uniform_matrix(group, 'thermal_state', grid, time)
            control = _uniform_matrix(group, 'hvac_control', grid, time)
            heat = _uniform_matrix(group, 'heat_flow_state', grid, time)
            power = _uniform_matrix(group, 'power_cop_state', grid, time)
            refrigerant = _uniform_matrix(group, 'refrigerant_state', grid, time)
            error = np.abs(thermal[:, 1] - thermal[:, 0])
            after_hour = grid >= 3600.0
            active = (control[:, 2] > 0.05) & (power[:, 3] > 0.1)
            heating = active & (control[:, 0] > 0.8)
            cooling = active & (control[:, 0] < -0.8)
            stable_active = heating | cooling
            mode_cop: list[float] = []
            physical_consistency: list[float] = []
            energy_closure: list[float] = []
            for is_heating, mask in ((True, heating), (False, cooling)):
                if int(np.count_nonzero(mask)) < 10:
                    continue
                cop = np.abs(heat[mask, 1]) / np.maximum(power[mask, 3], 1e-06)
                mode_cop.append(float(np.median(cop)))
                if is_heating:
                    consistent = (refrigerant[mask, 4] > 0) & (refrigerant[mask, 5] < 0) & (refrigerant[mask, 0] > refrigerant[mask, 1]) & (heat[mask, 1] < 0)
                else:
                    consistent = (refrigerant[mask, 4] > 0) & (refrigerant[mask, 5] > 0) & (refrigerant[mask, 1] > refrigerant[mask, 0]) & (heat[mask, 1] > 0)
                physical_consistency.append(float(np.mean(consistent)))
                closure = np.abs(np.abs(np.abs(heat[mask, 0]) - np.abs(heat[mask, 1])) - power[mask, 0]) / np.maximum(power[mask, 0], 0.2)
                energy_closure.extend(closure.tolist())
            valve_consistency = float(np.mean(np.abs(control[stable_active, 1] - control[stable_active, 0]) <= 0.2)) if np.any(stable_active) else 0.0
            significant_flow = active & (np.abs(refrigerant[:, 4]) > 0.005)
            flow_ratio_error = float(np.median(np.abs(np.abs(refrigerant[significant_flow, 5]) / np.maximum(np.abs(refrigerant[significant_flow, 4]), 1e-06) - 1.0))) if np.any(significant_flow) else 1.0
            initial_recovery = _first_sustained(grid, error <= 1.0, 600.0, step_s)
            heat_indices = np.flatnonzero(control[:, 0] > 0.8)
            cool_indices = np.flatnonzero(control[:, 0] < -0.8)
            reversal_recovery = -1.0
            if heat_indices.size and cool_indices.size:
                reversal_index = max(int(heat_indices[0]), int(cool_indices[0]))
                relative = grid[reversal_index:] - grid[reversal_index]
                reversal_recovery = _first_sustained(relative, error[reversal_index:] <= 1.0, 600.0, step_s)
            requested = row['requested_inputs']
            derived = copy.deepcopy(row.get('metrics', {}))
            derived.update({'actual_setpoint_degC': float(np.median(thermal[:, 0])), 'actual_house_initial_degC': float(thermal[0, 1]), 'actual_ambient_initial_degC': float(thermal[0, 2]), 'actual_ambient_final_degC': float(thermal[-1, 2]), 'comfort_fraction_after_1h': float(np.mean(error[after_hour] <= 1.5)), 'p95_absolute_temperature_error_after_1h_degC': float(np.quantile(error[after_hour], 0.95)), 'final_absolute_temperature_error_degC': float(error[-1]), 'house_temperature_dynamic_range_degC': float(np.ptp(thermal[:, 1])), 'heating_active_fraction': float(np.mean(heating)), 'cooling_active_fraction': float(np.mean(cooling)), 'compressor_command_dynamic_range': float(np.ptp(control[:, 2])), 'compressor_command_power_abs_correlation': _correlation(control[active, 2], power[active, 0]), 'mode_valve_consistency_fraction': valve_consistency, 'mode_flow_pressure_heat_consistency_fraction': min(physical_consistency) if physical_consistency else 0.0, 'worst_mode_median_cop': min(mode_cop) if mode_cop else 0.0, 'energy_closure_p90_relative': float(np.quantile(energy_closure, 0.9)) if energy_closure else 1.0, 'compressor_exv_mass_flow_ratio_error': flow_ratio_error, 'maximum_refrigerant_pressure_mpa': float(np.max(refrigerant[:, :2])), 'minimum_refrigerant_pressure_mpa': float(np.min(refrigerant[:, :2])), 'median_active_pressure_separation_mpa': float(np.median(np.abs(refrigerant[stable_active, 0] - refrigerant[stable_active, 1]))) if np.any(stable_active) else 0.0, 'compressor_power_dynamic_range_kw': float(np.ptp(power[:, 0])), 'indoor_heat_flow_dynamic_range_kw': float(np.ptp(heat[:, 1])), 'median_active_compressor_command': float(np.median(control[active, 2])) if np.any(active) else 0.0, 'initial_recovery_time_s': initial_recovery, 'mode_reversal_recovery_time_s': reversal_recovery, 'mode_reversal_present': bool(heat_indices.size and cool_indices.size), 'finite_fraction': float(np.mean(np.isfinite(np.column_stack([thermal, control, heat, power, refrigerant])))), 'requested_T_set_degC': float(requested['T_set_degC']), 'requested_T_house_init_degC': float(requested['T_house_init_degC']), 'requested_T_ambient_cold_degC': float(requested['T_ambient_cold_degC']), 'requested_T_ambient_hot_degC': float(requested['T_ambient_hot_degC']), 'offline_derivation_method': DERIVATION_METHOD})
            row['offline_metrics'] = derived
    evidence['offline_derivation'] = {'method': DERIVATION_METHOD, 'raw_artifact': str(raw_path), 'uniform_time_step_s': step_s, 'steady_evaluation_start_s': 3600.0}

def _input_realization(row: dict[str, Any]) -> float:
    metric = metrics_for(row)
    requested = row['requested_inputs']
    errors = (abs(metric['actual_setpoint_degC'] - requested['T_set_degC']) / 0.1, abs(metric['actual_house_initial_degC'] - requested['T_house_init_degC']) / 0.1, abs(metric['actual_ambient_initial_degC'] - requested['T_ambient_cold_degC']) / 0.1, abs(metric['actual_ambient_final_degC'] - requested['T_ambient_hot_degC']) / 0.1)
    return lower_better(max(errors), 1.0, 5.0)

def scenario_robustness(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metric = metrics_for(row)
    pressure = min(lower_better(metric['maximum_refrigerant_pressure_mpa'], 4.2, 5.0), higher_better(metric['minimum_refrigerant_pressure_mpa'], 0.05, 0.15))
    parts = {'comfort_retention': (higher_better(metric['comfort_fraction_after_1h'], 0.8, 0.98), 0.25), 'steady_temperature_error': (lower_better(metric['p95_absolute_temperature_error_after_1h_degC'], 1.2, 3.0), 0.2), 'active_cop': (higher_better(metric['worst_mode_median_cop'], 0.25, 0.65), 0.15), 'mode_physics': (higher_better(metric['mode_flow_pressure_heat_consistency_fraction'], 0.7, 0.95), 0.2), 'pressure_envelope': (pressure, 0.1), 'finite_output': (higher_better(metric['finite_fraction'], 0.999, 1.0), 0.1)}
    return (weighted_mean(parts), parts)

def scenario_dynamics(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metric = metrics_for(row)
    initial = metric['initial_recovery_time_s']
    initial_score = 0.0 if initial < 0 else lower_better(initial, 1200.0, 5400.0)
    reversal = metric['mode_reversal_recovery_time_s']
    reversal_score = 1.0 if not metric['mode_reversal_present'] else 0.0 if reversal < 0 else lower_better(reversal, 300.0, 1800.0)
    parts = {'initial_comfort_recovery': (initial_score, 0.35), 'mode_reversal_recovery': (reversal_score, 0.35), 'post_startup_comfort': (higher_better(metric['comfort_fraction_after_1h'], 0.85, 0.98), 0.15), 'physical_transition_consistency': (higher_better(metric['mode_flow_pressure_heat_consistency_fraction'], 0.7, 0.95), 0.15)}
    return (weighted_mean(parts), parts)

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = rows_by_id(evidence)
    static = evidence.get('static_audit', {})
    qualification_checks = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'scenario_set': set(rows) == REQUIRED_IDS, 'all_scenarios_valid': set(rows) == REQUIRED_IDS and all((bool(rows[key].get('valid')) for key in REQUIRED_IDS)), 'required_products': bool(static.get('required_products_available')), 'thermo_fluid_path': bool(static.get('thermo_fluid_path_signature')), 'closed_loop_temperature': bool(static.get('closed_loop_temperature_signature'))}
    if not all(qualification_checks.values()):
        return {'schema': 'simuverity.f90-xtherm04-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 0.0, 'groups': {key: 0.0 for key in WEIGHTS}, 'group_weights': WEIGHTS, 'score_raw': 0.0, 'admission_threshold_raw': 85.0, 'admission_pass': False, 'qualification_checks': qualification_checks, 'failures': [key for key, passed in qualification_checks.items() if not passed]}
    nominal = metrics_for(rows['native_cold_to_hot_transition'])
    group_a_parts = {'steady_comfort': (higher_better(nominal['comfort_fraction_after_1h'], 0.7, 0.98), 0.3), 'steady_error': (lower_better(nominal['p95_absolute_temperature_error_after_1h_degC'], 1.0, 3.0), 0.25), 'final_error': (lower_better(nominal['final_absolute_temperature_error_degC'], 0.25, 2.0), 0.2), 'heating_and_cooling_operation': (higher_better(min(nominal['heating_active_fraction'], nominal['cooling_active_fraction']), 0.01, 0.1), 0.15), 'finite_complete_output': (higher_better(nominal['finite_fraction'], 0.999, 1.0), 0.1)}
    group_a = weighted_mean(group_a_parts)
    group_q_parts = {'active_mode_cop': (higher_better(nominal['worst_mode_median_cop'], 0.4, 1.0), 0.25), 'cycle_energy_closure': (lower_better(nominal['energy_closure_p90_relative'], 0.2, 0.6), 0.2), 'compressor_exv_mass_balance': (lower_better(nominal['compressor_exv_mass_flow_ratio_error'], 0.05, 0.4), 0.2), 'pressure_separation': (higher_better(nominal['median_active_pressure_separation_mpa'], 0.1, 0.5), 0.15), 'nonzero_heat_and_power': (min(higher_better(nominal['compressor_power_dynamic_range_kw'], 0.1, 1.0), higher_better(nominal['indoor_heat_flow_dynamic_range_kw'], 0.2, 2.0)), 0.2)}
    group_q = weighted_mean(group_q_parts)
    metrics = [metrics_for(row) for row in rows.values()]
    input_realization = min((_input_realization(row) for row in rows.values()))
    command_response_spread = max((metric['median_active_compressor_command'] for metric in metrics)) - min((metric['median_active_compressor_command'] for metric in metrics))
    command_power_correlation = min((metric['compressor_command_power_abs_correlation'] for metric in metrics))
    valve_consistency = min((metric['mode_valve_consistency_fraction'] for metric in metrics))
    physical_consistency = min((metric['mode_flow_pressure_heat_consistency_fraction'] for metric in metrics))
    group_m_parts = {'static_thermo_fluid_chain': (1.0, 0.15), 'closed_loop_temperature_path': (1.0, 0.15), 'command_to_compressor_power': (higher_better(command_power_correlation, 0.4, 0.85), 0.15), 'mode_to_reversing_valve': (higher_better(valve_consistency, 0.7, 0.95), 0.15), 'mode_to_pressure_flow_and_heat': (higher_better(physical_consistency, 0.7, 0.95), 0.2), 'official_input_realization': (input_realization, 0.1), 'official_condition_physical_response': (higher_better(command_response_spread, 0.02, 0.1), 0.1)}
    group_m = weighted_mean(group_m_parts)
    robustness: dict[str, float] = {}
    robustness_parts: dict[str, Any] = {}
    dynamics: dict[str, float] = {}
    dynamics_parts: dict[str, Any] = {}
    for key in sorted(REQUIRED_IDS):
        robustness[key], robustness_parts[key] = scenario_robustness(rows[key])
        dynamics[key], dynamics_parts[key] = scenario_dynamics(rows[key])
    group_r = min(robustness.values())
    group_d = min(dynamics.values())
    groups = {'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    raw = 100.0 * weighted_geometric(groups)
    return {'schema': 'simuverity.f90-xtherm04-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score_raw': raw, 'admission_threshold_raw': 85.0, 'admission_pass': raw >= 85.0, 'qualification_checks': qualification_checks, 'details': {'A': group_a_parts, 'Q': group_q_parts, 'M': {'parts': group_m_parts, 'minimum_command_power_correlation': command_power_correlation, 'minimum_valve_consistency': valve_consistency, 'minimum_mode_physics_consistency': physical_consistency, 'official_input_realization': input_realization, 'command_response_spread': command_response_spread}, 'R': {'aggregation': '100_percent_minimum', 'by_scenario': robustness, 'parts': robustness_parts}, 'D': {'aggregation': '100_percent_minimum', 'by_scenario': dynamics, 'parts': dynamics_parts}}, 'offline_derivation': evidence.get('offline_derivation'), 'failures': []}

def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []
    missing = copy.deepcopy(evidence)
    missing['scenarios'][0]['valid'] = False
    cases.append(('required_output_missing', missing, 0.0))
    no_path = copy.deepcopy(evidence)
    no_path['static_audit']['thermo_fluid_path_signature'] = False
    cases.append(('thermo_fluid_path_missing', no_path, 0.0))
    no_feedback = copy.deepcopy(evidence)
    no_feedback['static_audit']['closed_loop_temperature_signature'] = False
    cases.append(('temperature_feedback_missing', no_feedback, 0.0))
    prescribed = copy.deepcopy(evidence)
    for row in prescribed['scenarios']:
        metric = metrics_for(row)
        metric['house_temperature_dynamic_range_degC'] = 0.0
        metric['final_absolute_temperature_error_degC'] = 0.0
        metric['p95_absolute_temperature_error_after_1h_degC'] = 0.0
    cases.append(('house_temperature_copied_from_setpoint', prescribed, 60.0))
    constant = copy.deepcopy(evidence)
    for row in constant['scenarios']:
        metric = metrics_for(row)
        metric['compressor_power_dynamic_range_kw'] = 0.0
        metric['indoor_heat_flow_dynamic_range_kw'] = 0.0
        metric['compressor_command_power_abs_correlation'] = 0.0
    cases.append(('constant_prerecorded_heat_and_power', constant, 60.0))
    ignored = copy.deepcopy(evidence)
    nominal = copy.deepcopy(metrics_for(rows_by_id(ignored)['native_cold_to_hot_transition']))
    for row in ignored['scenarios']:
        row['offline_metrics'] = copy.deepcopy(nominal)
    cases.append(('official_conditions_ignored', ignored, 70.0))
    no_reversal = copy.deepcopy(evidence)
    for row in no_reversal['scenarios']:
        metrics_for(row)['mode_flow_pressure_heat_consistency_fraction'] = 0.0
    cases.append(('mode_without_physical_reversal', no_reversal, 60.0))
    results = []
    for case_id, mutated, maximum in cases:
        result = score(mutated)
        value = float(result['score_raw'])
        results.append({'id': case_id, 'score_raw': value, 'required_maximum': maximum, 'pass': value <= maximum + 1e-09})
    return {'schema': 'simuverity.f90-xtherm04-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': results, 'pass': all((item['pass'] for item in results))}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    raw_path = Path(str(evidence['raw_artifact']['path']))
    attach_offline_derivations(evidence, raw_path)
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
