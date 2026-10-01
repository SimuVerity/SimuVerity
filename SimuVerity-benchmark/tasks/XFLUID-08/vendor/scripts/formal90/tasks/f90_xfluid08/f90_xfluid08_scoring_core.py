"""Dedicated score-only evaluator for F90-XFLUID-08 fixed evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
import h5py
import numpy as np
TASK_ID = 'F90-XFLUID-08'
POLICY_ID = 'simuverity-101-v1:f90-xfluid-08:scoring'
REQUIRED_IDS = {'native_profile_1_nominal_inventory', 'native_profile_2_nominal_inventory', 'native_profile_3_nominal_inventory', 'native_profile_2_low_inventory', 'native_profile_3_high_inventory'}
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}
DERIVATION_METHOD = 'f90-xfluid08-uniform-time-active-physics'

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

def weighted_geometric(groups: dict[str, float]) -> float:
    if any((groups[key] <= 0 for key in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS)))

def rows_by_id(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row['id']): row for row in evidence.get('scenarios', [])}

def metrics_for(row: dict[str, Any]) -> dict[str, Any]:
    return row.get('offline_metrics', row['metrics'])

def vector(metric: Any) -> list[float]:
    if isinstance(metric, list):
        return [float(item) for item in metric]
    return [float(metric)]

def relative_change(a: float, b: float) -> float:
    return abs(b - a) / max(abs(a), 1e-09)

def _uniform_matrix(group: h5py.Group, name: str, grid: np.ndarray, time: np.ndarray) -> np.ndarray:
    raw = np.asarray(group[name], dtype=float).T
    return np.column_stack([np.interp(grid, time, raw[:, column]) for column in range(raw.shape[1])])

def _settling_times(grid: np.ndarray, command: np.ndarray, measured: np.ndarray) -> list[float]:
    times: list[float] = []
    edges = np.flatnonzero(np.abs(np.diff(command)) > 100.0)
    for edge in edges:
        start = int(edge + 1)
        target = float(command[start])
        tolerance = max(0.08 * abs(target), 120.0)
        within = np.abs(measured[start:] - target) <= tolerance
        for offset in range(max(0, within.size - 4)):
            if bool(np.all(within[offset:offset + 5])):
                times.append(float(grid[start + offset] - grid[start]))
                break
    return times

def attach_offline_derivations(evidence: dict[str, Any], raw_path: Path) -> None:
    """Derive time-weighted metrics from current raw signals without MATLAB."""
    rows = evidence.get('scenarios', [])
    if not raw_path.is_file():
        raise FileNotFoundError(f'Current raw evidence is missing: {raw_path}')
    with h5py.File(raw_path, 'r') as handle:
        signal_refs = handle['artifacts/signals'][0]
        if len(signal_refs) != len(rows):
            raise ValueError('Raw artifact scenario count does not match evidence.json')
        for row, reference in zip(rows, signal_refs):
            group = handle[reference]
            time = np.asarray(group['time_s'], dtype=float).reshape(-1)
            grid = np.arange(math.ceil(time[0]), math.floor(time[-1]) + 1.0, 1.0)
            speed = _uniform_matrix(group, 'pump_speed_state', grid, time)
            tanks = _uniform_matrix(group, 'tank_fuel_state', grid, time)
            hydraulics = _uniform_matrix(group, 'transfer_hydraulics', grid, time)
            engine = _uniform_matrix(group, 'engine_feed_state', grid, time)
            power = _uniform_matrix(group, 'pump_power_state', grid, time)
            command = speed[:, ::2]
            measured = speed[:, 1::2]
            tracking: list[float] = []
            correlations: list[float] = []
            reverse: list[float] = []
            efficiencies: list[float] = []
            transition_times: list[float] = []
            for column in range(4):
                tank_volume = tanks[:, 0] if column < 2 else tanks[:, 1]
                active = (grid >= 5.0) & (command[:, column] > 300.0) & (tank_volume > 0.15)
                if int(np.count_nonzero(active)) < 10:
                    tracking.append(1.0)
                    correlations.append(0.0)
                    reverse.append(1.0)
                    efficiencies.append(0.0)
                    continue
                error = measured[active, column] - command[active, column]
                denominator = max(float(np.sqrt(np.mean(command[active, column] ** 2))), 300.0)
                tracking.append(float(np.sqrt(np.mean(error ** 2)) / denominator))
                if float(np.std(command[active, column])) > 1.0 and float(np.std(measured[active, column])) > 1.0:
                    correlations.append(float(abs(np.corrcoef(command[active, column], measured[active, column])[0, 1])))
                else:
                    correlations.append(1.0)
                significant = active & (np.abs(hydraulics[:, column]) > 0.01)
                reverse.append(float(np.mean(hydraulics[significant, column] < -0.01)) if bool(np.any(significant)) else 0.0)
                powered = active & (power[:, column] > 1.0)
                efficiencies.append(float(np.median(power[powered, 4 + column] / power[powered, column])) if bool(np.any(powered)) else 0.0)
                transition_times.extend(_settling_times(grid, command[:, column], measured[:, column]))
            warm = grid >= max(60.0, 0.02 * float(grid[-1]))
            feed = np.abs(engine[:, 0])
            derived = copy.deepcopy(row['metrics'])
            derived.update({'pump_tracking_nrmse': tracking, 'pump_command_speed_abs_correlation': correlations, 'pump_reverse_flow_fraction': reverse, 'pump_efficiency_late': efficiencies, 'pump_pressure_rise_mpa_late': [float(np.max(np.abs(hydraulics[:, 4 + column]))) for column in range(4)], 'pump_hydraulic_power_w_late': [float(np.max(np.abs(power[:, 4 + column]))) for column in range(4)], 'engine_feed_mass_flow_kg_s_late': float(np.median(feed[warm])), 'engine_feed_availability_fraction': float(np.mean(feed[warm] > 0.5)), 'engine_feed_dropout_fraction': float(1.0 - np.mean(feed[warm] > 0.5)), 'engine_feed_cv_after_warmup': float(np.std(feed[warm]) / max(np.mean(feed[warm]), 1e-09)), 'maximum_command_transition_settling_time_s': max(transition_times) if transition_times else -1.0, 'command_transition_settling_event_count': len(transition_times), 'offline_derivation_method': DERIVATION_METHOD})
            row['offline_metrics'] = derived
    evidence['offline_derivation'] = {'method': DERIVATION_METHOD, 'raw_artifact': str(raw_path), 'uniform_time_step_s': 1.0, 'startup_exclusion_s': 5.0, 'engine_warmup_exclusion_s': 60.0, 'dry_tank_protection_exclusion_threshold_m3': 0.15}

def scenario_operability(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metric = metrics_for(row)
    tracking = max(vector(metric['pump_tracking_nrmse']))
    reverse = max(vector(metric['pump_reverse_flow_fraction']))
    parts = {'engine_feed_continuity': (higher_better(float(metric['engine_feed_availability_fraction']), 0.9, 0.995), 0.25), 'pump_speed_regulation': (lower_better(tracking, 0.035, 0.15), 0.2), 'tank_dryout_protection': (higher_better(float(metric['minimum_tank_volume_m3']), 0.02, 0.09), 0.15), 'center_overflow_protection': (lower_better(float(metric['maximum_center_volume_m3']), 270.0, 284.0), 0.1), 'bounded_lateral_imbalance': (lower_better(float(metric['maximum_absolute_cg_offset_percent']), 8.0, 35.0), 0.1), 'one_way_transfer': (lower_better(reverse, 0.001, 0.05), 0.1), 'finite_complete_evidence': (higher_better(float(metric['finite_fraction']), 0.999, 1.0), 0.1)}
    return (weighted_mean(parts), parts)

def scenario_dynamics(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metric = metrics_for(row)
    transition_count = int(metric['command_transition_settling_event_count'])
    transition_time = float(metric['maximum_command_transition_settling_time_s'])
    transition_score = 1.0 if transition_count == 0 else lower_better(transition_time, 12.0, 35.0)
    parts = {'command_transition_settling': (transition_score, 0.4), 'feed_during_transients': (lower_better(float(metric['engine_feed_dropout_fraction']), 0.005, 0.12), 0.3), 'post_event_inventory_stability': (lower_better(float(metric['late_tank_volume_relative_drift']), 0.01, 0.12), 0.15), 'physical_balance_during_transients': (lower_better(float(metric['inventory_balance_relative_residual']), 0.2, 0.6), 0.15)}
    return (weighted_mean(parts), parts)

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = rows_by_id(evidence)
    static = evidence.get('static_audit', {})
    qualification_checks = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'scenario_set': set(rows) == REQUIRED_IDS, 'all_scenarios_valid': set(rows) == REQUIRED_IDS and all((bool(rows[key].get('valid')) for key in REQUIRED_IDS)), 'required_products': bool(static.get('required_products_available')), 'causal_fuel_path': bool(static.get('causal_fuel_path_signature')), 'redundant_transfer_path': bool(static.get('redundant_transfer_signature')), 'closed_loop_pump_speed': bool(static.get('closed_loop_pump_speed_signature'))}
    gate = all(qualification_checks.values())
    if not gate:
        return {'schema': 'simuverity.f90-xfluid08-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 0.0, 'groups': {'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 'group_weights': WEIGHTS, 'score_raw': 0.0, 'admission_threshold_raw': 85.0, 'admission_pass': False, 'qualification_checks': qualification_checks, 'failures': [key for key, passed in qualification_checks.items() if not passed]}
    nominal = metrics_for(rows['native_profile_1_nominal_inventory'])
    nominal_tracking = max(vector(nominal['pump_tracking_nrmse']))
    nominal_reverse = max(vector(nominal['pump_reverse_flow_fraction']))
    group_a_parts = {'pump_speed_tracking': (lower_better(nominal_tracking, 0.03, 0.12), 0.3), 'engine_feed_availability': (higher_better(float(nominal['engine_feed_availability_fraction']), 0.94, 0.998), 0.25), 'tank_bounds': (higher_better(float(nominal['minimum_tank_volume_m3']), 0.02, 0.09), 0.15), 'lateral_balance': (lower_better(float(nominal['maximum_absolute_cg_offset_percent']), 5.0, 25.0), 0.15), 'complete_finite_output': (higher_better(float(nominal['finite_fraction']), 0.999, 1.0), 0.15)}
    group_a = weighted_mean(group_a_parts)
    efficiencies = vector(nominal['pump_efficiency_late'])
    nonzero_efficiencies = [value for value in efficiencies if value > 0]
    median_efficiency = sorted(nonzero_efficiencies)[len(nonzero_efficiencies) // 2] if nonzero_efficiencies else 0.0
    pressure_rise = vector(nominal['pump_pressure_rise_mpa_late'])
    shaft_power = vector(nominal['pump_shaft_power_w_late'])
    hydraulic_power = vector(nominal['pump_hydraulic_power_w_late'])
    group_q_parts = {'one_way_branch_quality': (lower_better(nominal_reverse, 0.001, 0.04), 0.2), 'inventory_conservation': (lower_better(float(nominal['inventory_balance_relative_residual']), 0.2, 0.6), 0.25), 'physical_pump_efficiency': (band_score(median_efficiency, 0.25, 0.7, 0.95, 1.1), 0.2), 'nonzero_pressure_rise': (higher_better(min(pressure_rise), 0.005, 0.05), 0.15)}
    group_q = weighted_mean(group_q_parts)
    profile_2 = metrics_for(rows['native_profile_2_nominal_inventory'])
    profile_3 = metrics_for(rows['native_profile_3_nominal_inventory'])
    low_inventory = metrics_for(rows['native_profile_2_low_inventory'])
    high_inventory = metrics_for(rows['native_profile_3_high_inventory'])
    profile_response = max(relative_change(float(nominal['left_volume_end_m3']), float(profile_2['left_volume_end_m3'])), relative_change(float(nominal['right_volume_end_m3']), float(profile_3['right_volume_end_m3'])), relative_change(float(nominal['maximum_absolute_cg_offset_percent']), float(profile_2['maximum_absolute_cg_offset_percent'])))
    inventory_response = max(abs(float(low_inventory['left_volume_start_m3']) - float(profile_2['left_volume_start_m3'])), abs(float(high_inventory['center_volume_start_m3']) - float(profile_3['center_volume_start_m3'])))
    inventory_evolution = max((abs(float(metric[f'{tank}_volume_end_m3']) - float(metric[f'{tank}_volume_start_m3'])) for metric in (metrics_for(row) for row in rows.values()) for tank in ('left', 'center', 'right')))
    correlations: list[float] = []
    speed_ranges: list[float] = []
    for row in rows.values():
        metric = metrics_for(row)
        correlations.extend(vector(metric['pump_command_speed_abs_correlation']))
        speed_ranges.extend(vector(metric['pump_measured_speed_range_rpm']))
    active_correlations = [correlation for correlation, response_range in zip(correlations, speed_ranges) if response_range > 300]
    command_correlation = sum(active_correlations) / len(active_correlations) if active_correlations else 0.0
    group_m_parts = {'static_physical_chain': (1.0, 0.2), 'closed_loop_speed_path': (1.0, 0.15), 'command_to_measured_speed': (higher_better(command_correlation, 0.2, 0.95), 0.2), 'speed_to_pressure_flow_power': (min(higher_better(max(pressure_rise), 0.005, 0.05), higher_better(max(hydraulic_power), 5.0, 80.0)), 0.15), 'official_profile_response': (higher_better(profile_response, 0.01, 0.12), 0.15), 'initial_inventory_response': (higher_better(inventory_response, 0.5, 2.0), 0.15)}
    group_m = weighted_mean(group_m_parts)
    robustness_by_scenario: dict[str, float] = {}
    robustness_parts: dict[str, Any] = {}
    dynamics_by_scenario: dict[str, float] = {}
    dynamics_parts: dict[str, Any] = {}
    for key in sorted(REQUIRED_IDS):
        robustness_by_scenario[key], robustness_parts[key] = scenario_operability(rows[key])
        dynamics_by_scenario[key], dynamics_parts[key] = scenario_dynamics(rows[key])
    group_r = min(robustness_by_scenario.values())
    group_d = min(dynamics_by_scenario.values())
    groups = {'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    raw = 100.0 * weighted_geometric(groups)
    return {'schema': 'simuverity.f90-xfluid08-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score_raw': raw, 'admission_threshold_raw': 85.0, 'admission_pass': raw >= 85.0, 'qualification_checks': qualification_checks, 'details': {'A': group_a_parts, 'Q': {'parts': group_q_parts, 'median_pump_efficiency': median_efficiency}, 'M': {'parts': group_m_parts, 'command_speed_correlation': command_correlation, 'official_profile_response': profile_response, 'initial_inventory_response_m3': inventory_response, 'maximum_inventory_evolution_m3': inventory_evolution}, 'R': {'aggregation': '100_percent_minimum', 'by_scenario': robustness_by_scenario, 'parts': robustness_parts}, 'D': {'aggregation': '100_percent_minimum', 'by_scenario': dynamics_by_scenario, 'parts': dynamics_by_scenario}}, 'offline_derivation': evidence.get('offline_derivation'), 'failures': []}

def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []
    missing = copy.deepcopy(evidence)
    missing['scenarios'][0]['valid'] = False
    cases.append(('required_output_missing', missing, 0.0))
    no_path = copy.deepcopy(evidence)
    no_path['static_audit']['causal_fuel_path_signature'] = False
    cases.append(('physical_transfer_path_missing', no_path, 0.0))
    no_feedback = copy.deepcopy(evidence)
    no_feedback['static_audit']['closed_loop_pump_speed_signature'] = False
    cases.append(('pump_speed_feedback_missing', no_feedback, 0.0))
    copied_command = copy.deepcopy(evidence)
    for row in copied_command['scenarios']:
        metric = metrics_for(row)
        metric['pump_tracking_nrmse'] = [0.0] * 4
        metric['pump_measured_speed_range_rpm'] = [0.0] * 4
        metric['pump_command_speed_abs_correlation'] = [0.0] * 4
    cases.append(('command_copied_without_pump_dynamics', copied_command, 60.0))
    constant_inventory = copy.deepcopy(evidence)
    for row in constant_inventory['scenarios']:
        metric = metrics_for(row)
        metric['left_volume_end_m3'] = metric['left_volume_start_m3']
        metric['right_volume_end_m3'] = metric['right_volume_start_m3']
        metric['center_volume_end_m3'] = metric['center_volume_start_m3']
        metric['inventory_balance_relative_residual'] = 1.0
    cases.append(('constant_prerecorded_inventory', constant_inventory, 60.0))
    insensitive = copy.deepcopy(evidence)
    nominal_metric = copy.deepcopy(metrics_for(rows_by_id(insensitive)['native_profile_1_nominal_inventory']))
    for row in insensitive['scenarios']:
        current = metrics_for(row)
        requested = {key: value for key, value in current.items() if key.startswith('requested_') or key == 'native_profile'}
        row['offline_metrics'] = copy.deepcopy(nominal_metric)
        row['offline_metrics'].update(requested)
    cases.append(('official_profiles_ignored', insensitive, 70.0))
    zero_power = copy.deepcopy(evidence)
    for row in zero_power['scenarios']:
        metric = metrics_for(row)
        metric['pump_hydraulic_power_w_late'] = [0.0] * 4
        metric['pump_pressure_rise_mpa_late'] = [0.0] * 4
    cases.append(('zero_power_fuel_transfer', zero_power, 60.0))
    results = []
    for case_id, mutated, maximum in cases:
        result = score(mutated)
        value = float(result['score_raw'])
        results.append({'id': case_id, 'score_raw': value, 'required_maximum': maximum, 'pass': value <= maximum + 1e-09})
    return {'schema': 'simuverity.f90-xfluid08-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': results, 'pass': all((item['pass'] for item in results))}

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
