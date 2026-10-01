"""Dedicated fixed-evidence scorer for F90-XFLUID-05.

The MATLAB adapter extracts physical evidence only.  This module owns every
threshold, weight, aggregation rule, and shortcut sanity mutation,
so offline scoring never requires another simulation.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XFLUID-05'
POLICY_ID = 'simuverity-101-v1:f90-xfluid-05:scoring'
REQUIRED_IDS = {'nominal_six_loads', 'low_speed', 'low_speed_rated_demand', 'reduced_flow_demand', 'open_load', 'restrictive_load'}
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}

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
    if any((groups[key] <= 0.0 for key in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS)))

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row['id']): row for row in evidence.get('scenarios', [])}

def metric(row: dict[str, Any], key: str) -> float:
    return float(row['metrics'][key])

def relative_change(base: float, changed: float) -> float:
    return abs(changed - base) / max(abs(base), 1e-12)

def target_flow(row: dict[str, Any]) -> float:
    inputs = row['metrics']['applied_inputs']
    return 0.0011 * float(inputs['FlowDemandScale'])

def flow_error(row: dict[str, Any]) -> float:
    return abs(metric(row, 'nonlimited_mean_flow_m3_s') - target_flow(row)) / max(target_flow(row), 1e-12)

def scenario_robustness(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    parts = {'nonlimited_flow_tracking': (lower_better(flow_error(row), 0.08, 0.38), 0.35), 'pressure_containment': (lower_better(metric(row, 'maximum_outlet_pressure_Pa'), 28500000.0, 34000000.0), 0.25), 'load_sensing_differential': (band_score(metric(row, 'mean_load_sensing_delta_pressure_Pa'), 250000.0, 1000000.0, 3400000.0, 5500000.0), 0.15), 'five_piston_phase': (lower_better(metric(row, 'piston_phase_gap_rmse_deg'), 4.0, 24.0), 0.15), 'physical_piston_motion': (higher_better(metric(row, 'minimum_piston_amplitude_m'), 1e-05, 0.0008), 0.1)}
    return (weighted_mean(parts), parts)

def scenario_dynamic(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    parts = {'transition_settling': (lower_better(metric(row, 'maximum_load_transition_settling_s'), 0.1, 0.32), 0.45), 'mean_settling': (lower_better(metric(row, 'mean_load_transition_settling_s'), 0.055, 0.22), 0.15), 'active_yoke_adaptation': (higher_better(metric(row, 'yoke_position_range_m'), 2e-05, 0.0005), 0.15), 'active_pilot_motion': (higher_better(metric(row, 'pilot_spool_range_m'), 2e-06, 8e-05), 0.1), 'pressure_limit_entry': (higher_better(metric(row, 'pressure_limit_flow_reduction_fraction'), 0.03, 0.2), 0.15)}
    return (weighted_mean(parts), parts)

def gate_failure(qualification_checks: dict[str, bool]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xfluid05-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 0.0, 'groups': {'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 'group_weights': WEIGHTS, 'score_raw': 0.0, 'admission_threshold_raw': 85.0, 'preferred_reference_score_raw': 90.0, 'admission_pass': False, 'qualification_checks': qualification_checks, 'failures': [name for name, passed in qualification_checks.items() if not passed]}

def semantic_static_check(static: dict[str, Any], new_key: str, source_keys: tuple[str, ...]) -> bool:
    """Prefer the name-neutral current audit while retaining old reference evidence."""
    if new_key in static:
        return bool(static.get(new_key))
    return all((bool(static.get(key)) for key in source_keys))

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = scenario_map(evidence)
    static = evidence.get('static_audit', {})
    qualification_checks = {'reference_identity': bool(evidence.get('reference_direct_golden') or evidence.get('evaluation_subject') == 'candidate'), 'evidence_complete': bool(evidence.get('evidence_complete')), 'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'scenario_set': set(rows) == REQUIRED_IDS, 'all_scenarios_valid': set(rows) == REQUIRED_IDS and all((bool(rows[key].get('valid')) for key in REQUIRED_IDS)), 'five_physical_pistons': bool(static.get('five_physical_pistons')), 'real_fluid_power_path': semantic_static_check(static, 'real_fluid_power_path', ('booster_to_pump', 'pump_to_pipe', 'pipe_to_control', 'control_to_flow_sensor', 'flow_sensor_to_load')), 'load_profile_drives_real_orifice': bool(static.get('load_profile_drives_real_orifice')), 'pressure_to_yoke_control_path': semantic_static_check(static, 'pressure_to_yoke_control_path', ('flow_control_orifice_present', 'pilot_actuator_present', 'directional_valve_present', 'servo_yoke_actuator_present', 'pressure_limit_valve_present'))}
    if not all(qualification_checks.values()):
        return gate_failure(qualification_checks)
    nominal_row = rows['nominal_six_loads']
    nominal = nominal_row['metrics']
    group_a_parts = {'rated_nonlimited_flow': (lower_better(flow_error(nominal_row), 0.055, 0.3), 0.3), 'pressure_limit_near_27MPa': (band_score(float(nominal['maximum_outlet_pressure_Pa']), 17000000.0, 23500000.0, 29000000.0, 34000000.0), 0.25), 'load_sensing_differential': (band_score(float(nominal['mean_load_sensing_delta_pressure_Pa']), 250000.0, 1000000.0, 3400000.0, 5500000.0), 0.15), 'five_piston_phase': (lower_better(float(nominal['piston_phase_gap_rmse_deg']), 3.0, 20.0), 0.15), 'five_piston_motion': (higher_better(float(nominal['minimum_piston_amplitude_m']), 1e-05, 0.0008), 0.15)}
    group_a_core = min(group_a_parts['rated_nonlimited_flow'][0], group_a_parts['pressure_limit_near_27MPa'][0])
    group_a_support = sum((group_a_parts[key][0] for key in ('load_sensing_differential', 'five_piston_phase', 'five_piston_motion'))) / 3.0
    group_a = 0.7 * group_a_core + 0.3 * group_a_support
    group_q_parts = {'flow_ripple': (lower_better(float(nominal['maximum_flow_ripple_fraction']), 0.08, 0.4), 0.25), 'pressure_overshoot': (lower_better(float(nominal['maximum_outlet_pressure_Pa']), 28000000.0, 34000000.0), 0.25), 'piston_phase_uniformity': (lower_better(float(nominal['piston_phase_gap_rmse_deg']), 3.0, 22.0), 0.2), 'piston_amplitude_balance': (lower_better(float(nominal['maximum_piston_amplitude_m']) / max(float(nominal['minimum_piston_amplitude_m']), 1e-12) - 1.0, 0.05, 0.45), 0.1), 'bounded_yoke_motion': (band_score(float(nominal['yoke_position_range_m']), 1e-06, 0.0001, 0.035, 0.045), 0.1), 'finite_piston_speed': (band_score(float(nominal['maximum_piston_speed_m_s']), 0.001, 0.02, 8.0, 20.0), 0.1)}
    group_q = weighted_mean(group_q_parts)
    reduced = rows['reduced_flow_demand']['metrics']
    low_speed = rows['low_speed']['metrics']
    low_rated = rows['low_speed_rated_demand']['metrics']
    opened = rows['open_load']['metrics']
    restrictive = rows['restrictive_load']['metrics']
    flow_command_response = relative_change(float(nominal['nonlimited_mean_flow_m3_s']), float(reduced['nonlimited_mean_flow_m3_s']))
    load_pressure_response = relative_change(float(opened['maximum_outlet_pressure_Pa']), float(restrictive['maximum_outlet_pressure_Pa']))
    capacity_response = max(relative_change(float(nominal['nonlimited_mean_flow_m3_s']), float(low_rated['nonlimited_mean_flow_m3_s'])), relative_change(float(nominal['maximum_piston_speed_m_s']), float(low_rated['maximum_piston_speed_m_s'])))
    summarys = {round(float(row['metrics']['service_summary']), 4) for row in rows.values()}
    group_m_parts = {'physical_five_piston_power_path': (1.0, 0.2), 'pressure_to_pilot_to_yoke_path': (1.0, 0.2), 'active_yoke': (higher_better(float(nominal['yoke_position_range_m']), 2e-05, 0.0005), 0.1), 'active_pilot': (higher_better(float(nominal['pilot_spool_range_m']), 2e-06, 8e-05), 0.1), 'flow_command_response': (band_score(flow_command_response, 0.02, 0.06, 0.18, 0.35), 0.15), 'load_pressure_response': (higher_better(load_pressure_response, 0.08, 0.3), 0.1), 'speed_capacity_response': (higher_better(capacity_response, 0.03, 0.12), 0.05), 'distinct_official_responses': (higher_better(float(len(summarys)), 2.0, 5.0), 0.1)}
    group_m = weighted_mean(group_m_parts)
    robustness_by_scenario: dict[str, float] = {}
    robustness_parts: dict[str, Any] = {}
    dynamic_by_scenario: dict[str, float] = {}
    dynamic_parts: dict[str, Any] = {}
    for key in sorted(REQUIRED_IDS):
        robustness_by_scenario[key], robustness_parts[key] = scenario_robustness(rows[key])
        dynamic_by_scenario[key], dynamic_parts[key] = scenario_dynamic(rows[key])
    group_r = min(robustness_by_scenario.values())
    group_d = min(dynamic_by_scenario.values())
    groups = {'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    raw = 100.0 * geometric(groups)
    shortcut_findings: list[dict[str, str]] = []
    if float(nominal['piston_phase_gap_rmse_deg']) >= 30.0:
        shortcut_findings.append({'id': 'duplicated_or_invalid_piston_phase'})
    if float(nominal['yoke_position_range_m']) <= 2e-05 or float(nominal['pilot_spool_range_m']) <= 2e-06:
        shortcut_findings.append({'id': 'inactive_pressure_to_yoke_control'})
    if float(nominal['maximum_outlet_pressure_Pa']) >= 34000000.0:
        shortcut_findings.append({'id': 'pressure_limit_absent'})
    if len(summarys) <= 2:
        shortcut_findings.append({'id': 'scenario_inputs_ignored'})
    if group_m < 0.7:
        shortcut_findings.append({'id': 'weak_causal_mechanism'})
    return {'schema': 'simuverity.f90-xfluid05-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score_raw': raw, 'admission_threshold_raw': 85.0, 'preferred_reference_score_raw': 90.0, 'admission_pass': raw >= 85.0, 'qualification_checks': qualification_checks, 'details': {'A': group_a_parts, 'A_aggregation': {'method': '70_percent_core_bottleneck_plus_30_percent_support_mean', 'core_bottleneck': group_a_core, 'core_members': ['rated_nonlimited_flow', 'pressure_limit_near_27MPa'], 'support_mean': group_a_support, 'support_members': ['load_sensing_differential', 'five_piston_phase', 'five_piston_motion']}, 'Q': group_q_parts, 'M': {'parts': group_m_parts, 'flow_command_response': flow_command_response, 'load_pressure_response': load_pressure_response, 'speed_capacity_response': capacity_response}, 'R': {'aggregation': '100_percent_minimum', 'by_scenario': robustness_by_scenario, 'parts': robustness_parts}, 'D': {'aggregation': '100_percent_minimum', 'by_scenario': dynamic_by_scenario, 'parts': dynamic_parts}}, 'shortcut_findings': shortcut_findings, 'failures': []}

def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['valid'] = False
    cases.append(('missing_required_output', missing_output, 0.0))
    four_pistons = copy.deepcopy(evidence)
    four_pistons['static_audit']['five_physical_pistons'] = False
    cases.append(('fewer_than_five_physical_pistons', four_pistons, 0.0))
    duplicated_phase = copy.deepcopy(evidence)
    for row in duplicated_phase['scenarios']:
        row['metrics']['piston_phase_gap_rmse_deg'] = 72.0
    cases.append(('duplicated_piston_phase', duplicated_phase, 60.0))
    disconnected_feedback = copy.deepcopy(evidence)
    disconnected_feedback['static_audit']['pressure_to_yoke_control_path'] = False
    disconnected_feedback['static_audit']['pilot_actuator_present'] = False
    cases.append(('pressure_feedback_disconnected', disconnected_feedback, 0.0))
    prescribed = copy.deepcopy(evidence)
    for row in prescribed['scenarios']:
        row['metrics']['yoke_position_range_m'] = 0.0
        row['metrics']['pilot_spool_range_m'] = 0.0
        row['metrics']['nonlimited_mean_flow_m3_s'] = target_flow(row)
    cases.append(('prescribed_flow_or_yoke', prescribed, 65.0))
    no_limit = copy.deepcopy(evidence)
    for row in no_limit['scenarios']:
        row['metrics']['maximum_outlet_pressure_Pa'] = 40000000.0
        row['metrics']['pressure_limit_flow_reduction_fraction'] = 0.0
    cases.append(('pressure_limit_removed', no_limit, 60.0))
    replayed = copy.deepcopy(evidence)
    nominal_metrics = copy.deepcopy(scenario_map(replayed)['nominal_six_loads']['metrics'])
    for row in replayed['scenarios']:
        requested = row['metrics']['applied_inputs']
        row['metrics'] = copy.deepcopy(nominal_metrics)
        row['metrics']['applied_inputs'] = requested
    cases.append(('scenario_inputs_ignored', replayed, 65.0))
    bypassed_load = copy.deepcopy(evidence)
    bypassed_load['static_audit']['real_fluid_power_path'] = False
    bypassed_load['static_audit']['flow_sensor_to_load'] = False
    cases.append(('load_not_in_real_flow_path', bypassed_load, 0.0))
    results = []
    for name, mutated, maximum in cases:
        result = score(mutated)
        value = float(result['score_raw'])
        results.append({'id': name, 'score_raw': value, 'required_maximum': maximum, 'pass': value <= maximum + 1e-09})
    return {'schema': 'simuverity.f90-xfluid05-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': results, 'pass': all((item['pass'] for item in results))}

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
