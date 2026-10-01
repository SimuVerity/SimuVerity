"""Dedicated offline scorer for F90-XAERO-06 fixed HL-20 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any, Callable
REQUIRED_SCENARIOS = ('nominal_autoland', 'low_initial_energy', 'high_initial_energy', 'bank_angle_recovery', 'upper_mass_boundary', 'enhanced_native_wind')
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}
POLICY_ID = "simuverity-101-v1:f90-xaero-06:scoring"

def clamp(value: float, lower: float=0.0, upper: float=1.0) -> float:
    return max(lower, min(upper, float(value)))

def high_good(value: float, zero: float, full: float) -> float:
    if full == zero:
        return float(value >= full)
    return clamp((float(value) - zero) / (full - zero))

def low_good(value: float, full: float, zero: float) -> float:
    if zero == full:
        return float(value <= full)
    return clamp((zero - float(value)) / (zero - full))

def band_good(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    value = float(value)
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return high_good(value, low_zero, low_full)
    return low_good(value, high_full, high_zero)

def weighted_mean(values: dict[str, float], weights: dict[str, float] | None=None) -> float:
    if not values:
        return 0.0
    if weights is None:
        return sum(values.values()) / len(values)
    denominator = sum((weights[name] for name in values))
    return sum((values[name] * weights[name] for name in values)) / denominator

def all_true(mapping: dict[str, Any]) -> bool:
    return bool(mapping) and all((bool(value) for value in mapping.values()))

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row.get('id', '')): row for row in evidence.get('scenarios', [])}

def evaluation_subject(evidence: dict[str, Any]) -> str:
    return str(evidence.get('evaluation_subject', 'reference')).strip().lower()

def core_static_pass(evidence: dict[str, Any]) -> bool:
    audit = evidence.get('static_audit', {})
    if evaluation_subject(evidence) == 'candidate':
        required = ('six_dof_present', 'atmosphere_present', 'aerodynamics_present', 'guidance_to_control', 'bounded_actuators', 'zero_sustained_thrust', 'core_path_qualified', 'candidate_structure_scan')
        return all((bool(audit.get(name, False)) for name in required))
    required = ('guidance_to_control', 'control_to_actuators', 'actuators_to_airframe', 'airframe_to_model_bus', 'model_bus_to_sensors', 'model_bus_to_airdata', 'sensors_to_guidance', 'sensors_to_control', 'airdata_to_control', 'zero_sustained_thrust', 'six_dof_present', 'aerodynamics_present', 'environment_present', 'dynamic_actuator_present', 'flare_guidance_present')
    return all((bool(audit.get(name, False)) for name in required))

def qualification(evidence: dict[str, Any], rows: dict[str, dict[str, Any]]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    subject = evaluation_subject(evidence)
    required_flags = ['evidence_complete', 'load_pass', 'update_pass', 'compile_pass', 'nominal_smoke_pass']
    if subject == 'candidate':
        required_flags.extend(('score_inputs_valid', 'diagnostics_valid'))
    elif subject != 'reference':
        failures.append(f'unsupported evaluation_subject={subject}')
    for key in required_flags:
        if not bool(evidence.get(key, False)):
            failures.append(f'{key}=false')
    missing = [name for name in REQUIRED_SCENARIOS if name not in rows]
    if missing:
        failures.append('missing scenarios: ' + ', '.join(missing))
    invalid = [name for name in REQUIRED_SCENARIOS if name in rows and (not bool(rows[name].get('simulation_pass', False)) or not bool(rows[name].get('valid', False)) or (not all_true(rows[name].get('output_contract', {}))))]
    if invalid:
        failures.append('invalid required scenarios: ' + ', '.join(invalid))
    if not core_static_pass(evidence):
        failures.append('closed-loop guidance-actuator-aerodynamic-6DOF path failed')
    return (not failures, failures)

def static_mechanism_utilities(evidence: dict[str, Any]) -> dict[str, float]:
    audit = evidence['static_audit']
    if evaluation_subject(evidence) == 'candidate':
        bounded = bool(audit.get('bounded_actuators', False))
        aerodynamic_plant = bounded and bool(audit.get('aerodynamics_present', False)) and bool(audit.get('six_dof_present', False))
        return {'guidance_to_feedback_control': float(bool(audit.get('guidance_to_control', False))), 'controller_to_dynamic_actuator': float(bounded), 'actuator_to_aerodynamic_6dof_plant': float(aerodynamic_plant), 'wind_and_environment_path': float(bool(audit.get('atmosphere_present', False))), 'unpowered_energy_constraint': float(bool(audit.get('zero_sustained_thrust', False)))}
    return {'guidance_to_feedback_control': float(audit['guidance_to_control'] and audit['sensors_to_guidance'] and audit['sensors_to_control'] and audit['airdata_to_control']), 'controller_to_dynamic_actuator': float(audit['control_to_actuators'] and audit['dynamic_actuator_present']), 'actuator_to_aerodynamic_6dof_plant': float(audit['actuators_to_airframe'] and audit['aerodynamics_present'] and audit['six_dof_present']), 'wind_and_environment_path': float(audit['environment_present'] and audit['model_bus_to_airdata']), 'unpowered_energy_constraint': float(audit['zero_sustained_thrust'])}

def row_metrics(rows: dict[str, dict[str, Any]], name: str) -> dict[str, Any]:
    return rows[name]['metrics']

def terminal_completion_utility(item: dict[str, Any]) -> float:
    """Worst public terminal-landing requirement for one official scenario."""
    return min(high_good(item['downrange_progress_fraction'], 0.8, 0.96), low_good(abs(item['terminal_altitude_m']), 30.0, 300.0), low_good(item['terminal_sink_rate_mps'], 4.0, 11.0), band_good(item['terminal_speed_mps'], 25.0, 40.0, 115.0, 140.0))

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = scenario_map(evidence)
    gate, failures = qualification(evidence, rows)
    if not gate:
        return result_receipt(evidence, False, {name: 0.0 for name in WEIGHTS}, 0.0, {}, failures)
    nominal = row_metrics(rows, 'nominal_autoland')
    metrics = {name: row_metrics(rows, name) for name in REQUIRED_SCENARIOS}
    terminal_completion_by_scenario = {name: terminal_completion_utility(item) for name, item in metrics.items()}
    complete_dynamic_mission = min(terminal_completion_by_scenario.values(), default=0.0)
    a_utilities = {'downrange_progress': high_good(nominal['downrange_progress_fraction'], 0.85, 0.98), 'terminal_altitude': low_good(abs(nominal['terminal_altitude_m']), 20.0, 250.0), 'terminal_sink_rate': low_good(nominal['terminal_sink_rate_mps'], 3.5, 10.0), 'terminal_speed': band_good(nominal['terminal_speed_mps'], 30.0, 45.0, 105.0, 130.0), 'flare_demand_change': high_good(abs(nominal['late_alpha_demand_change_deg']), 0.15, 1.5)}
    nominal_primary_accuracy = weighted_mean(a_utilities, {'downrange_progress': 0.25, 'terminal_altitude': 0.2, 'terminal_sink_rate': 0.25, 'terminal_speed': 0.15, 'flare_demand_change': 0.15})
    A = weighted_mean({'nominal_primary_accuracy': nominal_primary_accuracy, 'worst_required_terminal_completion': complete_dynamic_mission}, {'nominal_primary_accuracy': 0.8, 'worst_required_terminal_completion': 0.2})
    q_per_scenario: dict[str, float] = {}
    q_diagnostics: dict[str, dict[str, float]] = {}
    for name, item in metrics.items():
        utilities = {'roll_envelope': low_good(item['maximum_abs_roll_deg'], 8.0, 30.0), 'pitch_envelope': low_good(item['maximum_abs_pitch_deg'], 30.0, 50.0), 'body_rate_envelope': low_good(item['maximum_abs_body_rate_radps'], 0.35, 1.2), 'alpha_lower_bound': high_good(item['minimum_alpha_deg'], -13.0, -9.5), 'alpha_upper_bound': low_good(item['maximum_alpha_deg'], 29.0, 36.0), 'beta_envelope': low_good(item['maximum_abs_beta_deg'], 5.0, 11.0), 'actuator_tracking': low_good(item['surface_tracking_rmse_deg'], 1.0, 7.0), 'limited_saturation': low_good(item['surface_saturation_fraction'], 0.02, 0.2)}
        q_diagnostics[name] = utilities
        q_per_scenario[name] = weighted_mean(utilities)
    Q = min(q_per_scenario.values())
    requested_applied = all((all((abs(float(row_metrics(rows, name)['applied_inputs'][key]) - float(rows[name]['requested_inputs'][key])) <= 1e-09 for key in ('InitialAirspeedScale', 'InitialBankOffset_deg', 'VehicleMassScale', 'WindSeverityScale'))) for name in REQUIRED_SCENARIOS))
    state_summarys = [round(float(metrics[name]['flight_state_summary']), 6) for name in REQUIRED_SCENARIOS]
    scenario_response_count = len(set(state_summarys))
    actuator_lag_present = all((0.002 <= float(metrics[name]['surface_tracking_peak_deg']) <= 20.0 for name in REQUIRED_SCENARIOS))
    m_utilities = {**static_mechanism_utilities(evidence), 'requested_inputs_applied': float(requested_applied), 'scenarios_change_state': high_good(scenario_response_count, 2.0, 5.0), 'guidance_is_dynamic': min((high_good(metrics[name]['guidance_activity_deg'], 0.05, 0.5) for name in REQUIRED_SCENARIOS)), 'surface_command_is_dynamic': min((high_good(metrics[name]['surface_command_activity_deg'], 0.05, 0.5) for name in REQUIRED_SCENARIOS)), 'bounded_actuator_lag_witness': float(actuator_lag_present)}
    M = weighted_mean(m_utilities)
    r_scenario_scores: dict[str, float] = {}
    r_diagnostics: dict[str, dict[str, float]] = {}
    for name, item in metrics.items():
        utilities = {'downrange_progress': high_good(item['downrange_progress_fraction'], 0.8, 0.96), 'terminal_altitude': low_good(abs(item['terminal_altitude_m']), 30.0, 300.0), 'terminal_sink': low_good(item['terminal_sink_rate_mps'], 4.0, 11.0), 'terminal_roll': low_good(item['terminal_abs_roll_deg'], 2.5, 15.0), 'terminal_speed': band_good(item['terminal_speed_mps'], 25.0, 40.0, 115.0, 140.0), 'alpha_table_support': min(high_good(item['minimum_alpha_deg'], -14.0, -10.0), low_good(item['maximum_alpha_deg'], 30.0, 38.0)), 'sideslip_table_support': low_good(item['maximum_abs_beta_deg'], 7.0, 12.0)}
        r_diagnostics[name] = utilities
        r_scenario_scores[name] = weighted_mean(utilities)
    R = min(r_scenario_scores.values())
    bank = metrics['bank_angle_recovery']
    d_utilities = {'nominal_terminal_sink_reduction': high_good(nominal['terminal_sink_reduction_fraction'], 0.02, 0.45), 'worst_terminal_sink_reduction': min((high_good(metrics[name]['terminal_sink_reduction_fraction'], 0.0, 0.35) for name in REQUIRED_SCENARIOS)), 'bank_perturbation_recovery': low_good(bank['bank_recovery_time_s'], 6.0, 25.0), 'terminal_bank_recovered': low_good(bank['terminal_abs_roll_deg'], 1.0, 8.0), 'flare_guidance_response': high_good(abs(nominal['late_alpha_demand_change_deg']), 0.1, 1.2), 'dynamic_surface_response': min((high_good(metrics[name]['surface_tracking_peak_deg'], 0.002, 0.15) for name in REQUIRED_SCENARIOS))}
    dynamic_response_mean = weighted_mean(d_utilities)
    D = weighted_mean({'dynamic_response_mean': dynamic_response_mean, 'worst_required_terminal_completion': complete_dynamic_mission}, {'dynamic_response_mean': 0.75, 'worst_required_terminal_completion': 0.25})
    groups = {'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    raw = 100.0
    for name, weight in WEIGHTS.items():
        raw *= max(groups[name], 1e-12) ** weight
    shortcut_findings: list[dict[str, str]] = []

    def record_finding(reason: str) -> None:
        shortcut_findings.append({'reason': reason})
        failures.append(reason)
    if not requested_applied:
        record_finding('workspace inputs are not applied')
    if scenario_response_count <= 2:
        record_finding('nominal trajectory is replayed across official inputs')
    if not actuator_lag_present:
        record_finding('surface command bypasses bounded dynamic actuator evidence')
    if min((metrics[name]['surface_command_activity_deg'] for name in REQUIRED_SCENARIOS)) <= 0.01:
        record_finding('surface command is constant or prescribed')
    if min((metrics[name]['guidance_activity_deg'] for name in REQUIRED_SCENARIOS)) <= 0.01:
        record_finding('endpoint-only descent lacks dynamic guidance evidence')
    terminal_performance_failures: list[str] = []
    if terminal_completion_by_scenario and all((value <= 0.0 for value in terminal_completion_by_scenario.values())):
        terminal_performance_failures.append('no required scenario reaches the public terminal landing envelope')
        failures.extend(terminal_performance_failures)
    diagnostics = {'A_utilities': a_utilities, 'A_aggregation': {'nominal_primary_accuracy': nominal_primary_accuracy, 'worst_required_terminal_completion': complete_dynamic_mission, 'weights': {'nominal_primary_accuracy': 0.8, 'worst_required_terminal_completion': 0.2}}, 'Q_scenario_scores': q_per_scenario, 'Q_utilities': q_diagnostics, 'M_utilities': m_utilities, 'R_scenario_scores': r_scenario_scores, 'R_utilities': r_diagnostics, 'D_utilities': d_utilities, 'D_aggregation': {'dynamic_response_mean': dynamic_response_mean, 'worst_required_terminal_completion': complete_dynamic_mission, 'weights': {'dynamic_response_mean': 0.75, 'worst_required_terminal_completion': 0.25}}, 'terminal_completion_by_scenario': terminal_completion_by_scenario, 'terminal_completion_definition': 'minimum across required scenarios of downrange progress, terminal altitude, sink-rate, and speed utilities', 'scenario_response_count': scenario_response_count, 'actuator_lag_present': actuator_lag_present, 'shortcut_findings': shortcut_findings, 'terminal_performance_failures': terminal_performance_failures}
    return result_receipt(evidence, True, groups, raw, diagnostics, failures)

def result_receipt(evidence: dict[str, Any], gate: bool, groups: dict[str, float], raw: float, diagnostics: dict[str, Any], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xaero06-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XAERO-06', 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'preferred_reference_score': 90, 'G': bool(gate), 'groups': {'G': 1.0 if gate else 0.0, **groups}, 'score': float(raw), 'admission_score_pass': bool(gate and raw >= 85.0), 'diagnostics': diagnostics, 'failure_reasons': failures}

def sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}

    def run_case(name: str, mutator: Callable[[dict[str, Any]], None], maximum: float) -> None:
        candidate = copy.deepcopy(evidence)
        mutator(candidate)
        result = score_evidence(candidate)
        score = float(result['score'])
        cases[name] = {'score': score, 'G': bool(result['G']), 'pass': score <= maximum + 1e-09, 'maximum_allowed': maximum, 'failure_reasons': result['failure_reasons']}

    def row(candidate: dict[str, Any], scenario_id: str) -> dict[str, Any]:
        return next((item for item in candidate['scenarios'] if item['id'] == scenario_id))
    run_case('missing_required_output', lambda value: row(value, 'nominal_autoland').update(valid=False), 0.0)
    run_case('kinematic_descent_without_6dof', lambda value: value['static_audit'].update(six_dof_present=False, core_path_qualified=False), 0.0)
    run_case('guidance_feedback_disconnected', lambda value: value['static_audit'].update(guidance_to_control=False, core_path_qualified=False), 0.0)
    run_case('surface_command_bypasses_dynamic_actuator', lambda value: [item['metrics'].update(surface_tracking_peak_deg=0.0, surface_tracking_rmse_deg=0.0) for item in value['scenarios']], 65.0)
    run_case('arbitrary_sustained_thrust', lambda value: value['static_audit'].update(zero_sustained_thrust=False, core_path_qualified=False), 0.0)

    def replay_nominal(value: dict[str, Any]) -> None:
        nominal = row(value, 'nominal_autoland')
        applied = nominal['metrics']['applied_inputs']
        for item in value['scenarios']:
            item['metrics']['applied_inputs'] = copy.deepcopy(applied)
    run_case('scenario_inputs_ignored_nominal_replayed', replay_nominal, 65.0)

    def endpoint_only(value: dict[str, Any]) -> None:
        for item in value['scenarios']:
            item['metrics']['guidance_activity_deg'] = 0.0
            item['metrics']['late_alpha_demand_change_deg'] = 0.0
    run_case('endpoint_only_without_glide_or_flare', endpoint_only, 65.0)

    def copied_surface(value: dict[str, Any]) -> None:
        for item in value['scenarios']:
            item['metrics']['surface_tracking_peak_deg'] = 0.0
            item['metrics']['surface_tracking_rmse_deg'] = 0.0
    run_case('surface_command_copied_as_position', copied_surface, 65.0)
    duration_only = copy.deepcopy(evidence)
    for item in duration_only['scenarios']:
        item['metrics'].update({'simulation_end_s': 70.0, 'downrange_progress_fraction': 0.5, 'terminal_altitude_m': 500.0, 'terminal_sink_rate_mps': 15.0, 'terminal_speed_mps': 150.0})
    duration_only_result = score_evidence(duration_only)
    duration_only_completion = duration_only_result.get('diagnostics', {}).get('D_aggregation', {}).get('worst_required_terminal_completion')
    completion_regression = {'score': duration_only_result['score'], 'complete_dynamic_mission': duration_only_completion, 'pass': duration_only_completion == 0.0 and float(duration_only_result['score']) < 85.0, 'maximum_allowed': 85.0}
    return {'schema': 'simuverity.f90-xaero06-shortcut-sanity.v1', 'task_id': 'F90-XAERO-06', 'regression_assertions': {'duration_without_terminal_landing_is_not_completion': completion_regression}, 'all_pass': all((item['pass'] for item in cases.values())) and completion_regression['pass'], 'max_shortcut_score': max((item['score'] for item in cases.values())), 'cases': cases}

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    temporary.replace(path)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8-sig'))
    score = score_evidence(evidence)
    sanity = sanity_suite(evidence)
    if args.out:
        write_json(args.out, score)
    if args.sanity_out:
        write_json(args.sanity_out, sanity)
    print(json.dumps({'score': score['score'], 'groups': score['groups'], 'out': str(args.out) if args.out else '', 'sanity': {'all_pass': sanity['all_pass'], 'max_shortcut_score': sanity['max_shortcut_score'], 'out': str(args.sanity_out) if args.sanity_out else ''}}))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
