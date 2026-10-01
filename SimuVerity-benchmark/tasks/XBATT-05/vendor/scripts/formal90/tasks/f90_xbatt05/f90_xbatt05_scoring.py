"""Pure offline scorer for fixed F90-XBATT-05 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XBATT-05'
POLICY_ID = "simuverity-101-v1:f90-xbatt-05:scoring"
REQUIRED = ['nominal', 'low_initial_soc', 'high_initial_soc', 'cold_cell_and_ambient', 'warm_cell_and_ambient', 'hot_weak_heat_rejection', 'hot_strong_heat_rejection']
WEIGHTS = {'A': 0.1, 'Q': 0.05, 'M': 0.5, 'R': 0.1, 'D': 0.25}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

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

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def columns(rows: list[list[float]]) -> list[list[float]]:
    return [list(map(float, column)) for column in zip(*rows)]

def monotonic_violation(values: list[float], direction: str) -> float:
    scale = max(max(map(abs, values)), 1e-12)
    tolerance = 1e-08 * scale
    changes = [values[i] - values[i - 1] for i in range(1, len(values))]
    if not changes:
        return 1.0
    if direction == 'nondecreasing':
        return mean([change < -tolerance for change in changes])
    return mean([change > tolerance for change in changes])

def trace_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    voltage, current, _, _ = columns(outputs['cell_state'])
    phase, _, _, _ = columns(outputs['charger_state'])
    positive, ocv, negative, film, porosity, soh, sei_loss, plating_loss = columns(outputs['electrochemical_state'])
    first_cv = next((index for index, value in enumerate(phase) if value == 3), None)
    cv_indices: list[int] = []
    if first_cv is not None:
        index = first_cv
        while index < len(phase) and phase[index] == 3:
            cv_indices.append(index)
            index += 1
    cv_initial = abs(current[cv_indices[0]]) if cv_indices else math.nan
    cv_final = abs(current[cv_indices[-1]]) if cv_indices else math.nan
    return {'potential_identity_rmse_V': rms([voltage[i] - (positive[i] - negative[i]) for i in range(len(voltage))]), 'soh_identity_rmse': rms([soh[i] - (1.0 - sei_loss[i] - plating_loss[i]) for i in range(len(soh))]), 'film_monotonic_violation': monotonic_violation(film, 'nondecreasing'), 'porosity_monotonic_violation': monotonic_violation(porosity, 'nonincreasing'), 'soh_monotonic_violation': monotonic_violation(soh, 'nonincreasing'), 'ocv_span_V': max(ocv) - min(ocv), 'cv_initial_current_A': cv_initial, 'cv_final_current_A': cv_final, 'cv_taper_ratio': cv_final / max(cv_initial, 1e-12)}

def row_score(metrics: dict[str, float]) -> tuple[float, dict[str, tuple[float, float]]]:
    voltage_violation = max(0.0, 2.5 - metrics['voltage_min_V'], metrics['voltage_max_V'] - 4.2)
    parts = {'full_sequence': (float(bool(metrics['full_sequence_pass'])), 0.2), 'constant_power': (low(metrics['cp_power_relative_error'], 0.03, 0.25), 0.14), 'constant_current': (low(metrics['cc_current_relative_error'], 0.02, 0.2), 0.14), 'constant_voltage': (low(metrics['cv_voltage_absolute_error_V'], 0.01, 0.1), 0.14), 'voltage_envelope': (low(voltage_violation, 0.015, 0.15), 0.1), 'thermal_safety': (min(high(metrics['temperature_min_C'], -20.0, -5.0), low(metrics['temperature_max_C'], 65.0, 90.0)), 0.08), 'soc_envelope': (min(high(metrics['soc_min'], -0.05, 0.0), low(metrics['soc_max'], 1.0, 1.05)), 0.06), 'cv_termination': (min(low(metrics['cv_final_current_A'], 0.65, 1.5), low(metrics['cv_taper_ratio'], 0.2, 0.7)), 0.08), 'sequence_completion': (high(metrics['completed_sequence_count'], 0.0, 1.0), 0.06)}
    return (weighted(parts), parts)

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    if 'core_path_qualified' in static:
        connected_dynamic_path = bool(static.get('core_path_qualified'))
    else:
        connected_dynamic_path = str(static.get('cell_component_path', '')).endswith('TSPMeA') and bool(static.get('convective_heat_transfer_present')) and bool(static.get('physical_voltage_sensor_present')) and bool(static.get('physical_current_sensor_present'))
    if 'feedback_cycle_present' in static:
        feedback_path = bool(static.get('feedback_cycle_present'))
    else:
        feedback_path = bool(static.get('charger_is_stateflow')) and int(static.get('charger_input_port_count', 0)) >= 2 and bool(static.get('measurement_feedback_connected')) and bool(static.get('command_actuator_connected'))
    required_outputs = {'time_s', 'cell_state', 'charger_state', 'electrochemical_state'}
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': all((name in rows and bool(rows[name].get('valid')) and (required_outputs <= set(rows[name].get('outputs', {}))) for name in REQUIRED)), 'connected_dynamic_candidate_path': connected_dynamic_path, 'closed_feedback_path': feedback_path}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {name: 0.0 for name in WEIGHTS}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics: dict[str, dict[str, float]] = {}
    scenario_scores: dict[str, float] = {}
    scenario_parts: dict[str, dict[str, tuple[float, float]]] = {}
    for name in REQUIRED:
        metrics[name] = {**{key: float(value) if isinstance(value, (int, float)) else value for key, value in rows[name]['metrics'].items()}, **trace_metrics(rows[name])}
        scenario_scores[name], scenario_parts[name] = row_score(metrics[name])
    nominal = metrics['nominal']
    a_parts = {'full_sequence': (float(bool(nominal['full_sequence_pass'])), 0.15), 'constant_power_accuracy': (low(nominal['cp_power_relative_error'], 0.02, 0.2), 0.17), 'constant_current_accuracy': (low(nominal['cc_current_relative_error'], 0.01, 0.15), 0.17), 'constant_voltage_accuracy': (low(nominal['cv_voltage_absolute_error_V'], 0.005, 0.08), 0.17), 'current_taper': (min(low(nominal['cv_final_current_A'], 0.65, 1.5), low(nominal['cv_taper_ratio'], 0.2, 0.7)), 0.17), 'sequence_completion': (high(nominal['completed_sequence_count'], 0.0, 1.0), 0.17)}
    a_weighted = weighted(a_parts)
    group_a = a_weighted * a_parts['current_taper'][0]
    voltage_violation = max(0.0, 2.5 - nominal['voltage_min_V'], nominal['voltage_max_V'] - 4.2)
    q_parts = {'voltage_envelope': (low(voltage_violation, 0.015, 0.12), 0.15), 'thermal_safety': (min(high(nominal['temperature_min_C'], -20.0, -5.0), low(nominal['temperature_max_C'], 60.0, 85.0)), 0.12), 'soc_envelope': (min(high(nominal['soc_min'], -0.05, 0.0), low(nominal['soc_max'], 1.0, 1.05)), 0.08), 'terminal_potential_identity': (low(nominal['potential_identity_rmse_V'], 0.02, 0.15), 0.16), 'soh_decomposition_identity': (low(nominal['soh_identity_rmse'], 1e-05, 0.01), 0.16), 'film_direction': (low(nominal['film_monotonic_violation'], 0.01, 0.15), 0.08), 'porosity_direction': (low(nominal['porosity_monotonic_violation'], 0.01, 0.15), 0.08), 'soh_direction': (low(nominal['soh_monotonic_violation'], 0.01, 0.15), 0.07), 'both_ageing_paths': (min(high(nominal['sei_capacity_loss_change'], 1e-09, 1e-06), high(nominal['plating_capacity_loss_change'], 1e-09, 1e-06)), 0.1)}
    group_q = weighted(q_parts)
    low_soc = metrics['low_initial_soc']
    high_soc = metrics['high_initial_soc']
    cold = metrics['cold_cell_and_ambient']
    warm = metrics['warm_cell_and_ambient']
    weak = metrics['hot_weak_heat_rejection']
    strong = metrics['hot_strong_heat_rejection']
    initial_soc_timing_delta = high_soc['rest_after_cp_s'] - low_soc['rest_after_cp_s']
    thermal_boundary_delta = abs(warm['temperature_max_C'] - cold['temperature_max_C'])
    heat_rejection_delta = weak['temperature_max_C'] - strong['temperature_max_C']
    degradation_temperature_delta = max(abs(warm['sei_capacity_loss_change'] - cold['sei_capacity_loss_change']), abs(warm['plating_capacity_loss_change'] - cold['plating_capacity_loss_change']))
    initial_soc_utility = high(initial_soc_timing_delta, 1000.0, 3000.0)
    thermal_boundary_utility = high(thermal_boundary_delta, 5.0, 15.0)
    heat_rejection_utility = high(heat_rejection_delta, 0.05, 0.5)
    degradation_temperature_utility = high(degradation_temperature_delta, 1e-08, 1e-05)
    electrochemical_ageing_utility = min(high(nominal['film_growth_um'], 1e-08, 1e-05), high(-nominal['porosity_change'], 1e-08, 1e-05), high(-nominal['capacity_soh_change'], 1e-08, 1e-05))
    closed_loop_utility = min(float(all((bool(metrics[name]['full_sequence_pass']) for name in REQUIRED))), initial_soc_utility, a_parts['constant_power_accuracy'][0], a_parts['constant_current_accuracy'][0], a_parts['constant_voltage_accuracy'][0])
    thermal_electrochemical_utility = min(thermal_boundary_utility, heat_rejection_utility, degradation_temperature_utility, electrochemical_ageing_utility)
    m_parts = {'behavioral_feedback_actuator_cell_chain': (closed_loop_utility, 0.2), 'behavioral_thermal_electrochemical_chain': (thermal_electrochemical_utility, 0.25), 'initial_soc_changes_discharge_duration': (initial_soc_utility, 0.1), 'thermal_boundary_changes_cell_response': (thermal_boundary_utility, 0.1), 'heat_rejection_changes_peak_temperature': (heat_rejection_utility, 0.15), 'temperature_changes_degradation_path': (degradation_temperature_utility, 0.05), 'electrochemical_ageing_states_active': (electrochemical_ageing_utility, 0.15)}
    group_m = weighted(m_parts)
    group_r = min(scenario_scores.values())
    rest_duration = nominal['cc_start_s'] - nominal['rest_after_cp_s']
    d_parts = {'ordered_transitions_all_scenarios': (min((float(bool(metrics[name]['full_sequence_pass'])) for name in REQUIRED)), 0.15), 'interphase_rest_present': (float(rest_duration > 0.0), 0.05), 'cv_current_taper': (min(low(nominal['cv_final_current_A'], 0.65, 1.5), low(nominal['cv_taper_ratio'], 0.2, 0.7)), 0.2), 'measured_voltage_transition': (low(nominal['cv_voltage_absolute_error_V'], 0.01, 0.1), 0.15), 'initial_soc_pair_order': (initial_soc_utility, 0.2), 'heat_rejection_pair_order': (high(heat_rejection_delta, 0.05, 0.5), 0.25)}
    group_d = weighted(d_parts)
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'A_aggregation': {'weighted_mean': a_weighted, 'mandatory_current_taper': a_parts['current_taper'][0]}, 'Q': q_parts, 'M': m_parts, 'D': d_parts, 'R_by_scenario': scenario_scores, 'R_parts_by_scenario': scenario_parts, 'paired_effects': {'initial_soc_discharge_duration_delta_s': initial_soc_timing_delta, 'cold_warm_peak_temperature_delta_C': thermal_boundary_delta, 'weak_minus_strong_heat_rejection_peak_C': heat_rejection_delta, 'cold_warm_degradation_delta': degradation_temperature_delta}}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xbatt05-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': float(groups.get('G', 0.0)), 'group_scores': {name: 100.0 * float(groups.get(name, 0.0)) for name in ('A', 'Q', 'M', 'R', 'D')}, 'raw_total_score': float(total), 'qualification': qualification, 'failure_reasons': failures, 'metrics': metrics, 'diagnostics': diagnostics, 'aggregation': {'within_group': 'weighted arithmetic mean', 'critical_multiscenario': '100 percent minimum', 'across_groups': 'weighted geometric mean', 'weights': WEIGHTS}}

def sanity_cases(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    cases: dict[str, dict[str, Any]] = {}
    missing_voltage = copy.deepcopy(evidence)
    missing_voltage['static_audit']['feedback_cycle_present'] = False
    cases['missing_voltage_feedback'] = missing_voltage
    missing_current = copy.deepcopy(evidence)
    missing_current['static_audit']['feedback_cycle_present'] = False
    cases['missing_current_feedback'] = missing_current
    disconnected = copy.deepcopy(evidence)
    disconnected['static_audit']['core_path_qualified'] = False
    cases['disconnected_charger_command'] = disconnected
    simple_cell = copy.deepcopy(evidence)
    simple_cell['static_audit']['core_path_qualified'] = False
    cases['non_electrochemical_cell'] = simple_cell
    fixed_current = copy.deepcopy(evidence)
    for row in fixed_current['scenarios']:
        row['metrics']['cv_final_current_A'] = 5.0
        row['metrics']['cv_taper_ratio'] = 1.0
        for cell, charger in zip(row['outputs']['cell_state'], row['outputs']['charger_state']):
            if float(charger[0]) == 3.0:
                cell[1] = 5.0
    cases['fixed_current_without_cv_taper'] = fixed_current
    copied_outputs = copy.deepcopy(evidence)
    nominal = next((row for row in copied_outputs['scenarios'] if row['id'] == 'nominal'))
    for row in copied_outputs['scenarios']:
        if row['id'] != 'nominal':
            row['metrics'] = copy.deepcopy(nominal['metrics'])
            row['outputs'] = copy.deepcopy(nominal['outputs'])
    cases['copied_nominal_outputs'] = copied_outputs
    return cases

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--shortcut-sanity', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score(evidence)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    if args.shortcut_sanity:
        cases = {name: score(case) for name, case in sanity_cases(evidence).items()}
        sanity = {'schema': 'simuverity.f90-xbatt05-shortcut-sanity.v1', 'task_id': TASK_ID, 'case_scores': {name: value['raw_total_score'] for name, value in cases.items()}, 'maximum_shortcut_score': max((value['raw_total_score'] for value in cases.values())), 'pass': all((value['raw_total_score'] <= 70.0 for value in cases.values())), 'details': cases}
        args.shortcut_sanity.parent.mkdir(parents=True, exist_ok=True)
        args.shortcut_sanity.write_text(json.dumps(sanity, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
