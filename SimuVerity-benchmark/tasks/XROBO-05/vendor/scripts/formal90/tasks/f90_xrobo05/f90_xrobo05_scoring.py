"""Pure-offline SCORING_CORE scorer for F90-XROBO-05 complete evidence.

The evaluator-owned evidence bundle is authoritative. Candidate
qualification is limited to runtime/evidence integrity and anti-cheat.  The
reference-only modification audit and the METRICS semantic-name topology guess do
not qualify candidates.  Dual-loop control and 6DOF mechanism credit instead
come from connected public outputs and official input-output interventions.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
from f90_xrobo05_scoring_core import high, low, row_metrics, weighted
TASK_ID = 'F90-XROBO-05'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-05:scoring'
REQUIRED = ('native_nominal_dual_step', 'moderate_heading_boundary', 'moderate_depth_boundary', 'current_magnitude_boundary', 'current_direction_boundary', 'reduced_propulsive_authority')
OUTPUT_WIDTHS = {'reference_state': 4, 'vehicle_state': 12, 'actuation_state': 4, 'environment_state': 3}
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.15, 'C': 0.15, 'R': 0.2, 'D': 0.2}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return 100.0 * math.exp(sum((WEIGHTS[name] * math.log(clamp(groups[name])) for name in WEIGHTS)))

def _finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def _matrix_contract(value: Any, count: int, width: int) -> bool:
    return isinstance(value, list) and len(value) == count and all((isinstance(row, list) and len(row) == width and all((_finite_number(item) for item in row)) for row in value))

def _row_integrity(row: dict[str, Any]) -> bool:
    if row.get('simulation_pass') is not True or row.get('valid') is not True:
        return False
    if 'required_evidence_pass' in row and row.get('required_evidence_pass') is not True:
        return False
    outputs = row.get('outputs')
    if not isinstance(outputs, dict):
        return False
    time = outputs.get('time_s')
    if not isinstance(time, list) or len(time) < 2 or (not all((_finite_number(item) for item in time))):
        return False
    numeric_time = [float(item) for item in time]
    if abs(numeric_time[0]) > 0.051 or numeric_time[-1] < 399.949:
        return False
    if any((right <= left for left, right in zip(numeric_time, numeric_time[1:]))):
        return False
    return all((_matrix_contract(outputs.get(name), len(numeric_time), width) for name, width in OUTPUT_WIDTHS.items()))

def integrity_gate(evidence: dict[str, Any]) -> tuple[bool, list[str], dict[str, Any]]:
    failures: list[str] = []
    runtime = {name: evidence.get(name) is True for name in ('load_pass', 'update_pass', 'compile_pass', 'nominal_smoke_pass')}
    if not all(runtime.values()):
        failures.append('load/update/compile/nominal-smoke integrity failed')
    scenario_list = evidence.get('scenarios', [])
    rows = {str(row.get('id')): row for row in scenario_list if isinstance(row, dict) and isinstance(row.get('id'), str)}
    exact_scenarios = len(scenario_list) == len(REQUIRED) and set(rows) == set(REQUIRED)
    if not exact_scenarios:
        failures.append('required official scenario set is missing, duplicated, or changed')
    output_integrity = exact_scenarios and all((_row_integrity(rows[name]) for name in REQUIRED))
    if not output_integrity:
        failures.append('required outputs are missing, nonfinite, incomplete, truncated, or misaligned')
    score_free = evidence.get('contains_score_decisions') is not True
    if not score_free:
        failures.append('evidence extraction contains score decisions')
    explicit_anti_cheat_rejection = evidence.get('cheating_detected') is True or evidence.get('anti_cheat_pass') is False or evidence.get('candidate_anti_cheat_pass') is False
    anti_cheat_pass = score_free and (not explicit_anti_cheat_rejection)
    if not anti_cheat_pass:
        failures.append('sealed-candidate anti-cheat integrity failed')
    candidate_subject = evidence.get('evaluation_subject') == 'candidate' or evidence.get('reference_substantive_modifications') == 'N/A_FOR_CANDIDATE'
    reference_field_applicability = 'N/A_FOR_CANDIDATE' if candidate_subject else 'REFERENCE_ONLY'
    passed = all(runtime.values()) and output_integrity and anti_cheat_pass
    diagnostics = {'runtime': runtime, 'exact_required_scenarios': exact_scenarios, 'required_outputs_finite_complete_time_aligned': output_integrity, 'score_free_evidence': score_free, 'anti_cheat_pass': anti_cheat_pass, 'reference_substantive_modifications_applicability': reference_field_applicability, 'source_task_evidence_complete_ignored': True, 'semantic_name_topology_gate_ignored': True, 'evidence_bundle_complete_required': True}
    return (passed, list(dict.fromkeys(failures)), diagnostics)

def make_receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, failures: list[str], per_scenario: dict[str, Any], per_metric: dict[str, Any], status: str) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xrobo05-score.v1', 'status': status, 'policy_id': POLICY_ID, 'task_id': TASK_ID, 'evidence_authority': 'evaluator-owned evidence bundle', 'formula': 'G*100*A^0.20*Q^0.10*M^0.15*C^0.15*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 90.0, 'preferred_reference_score': 90.0, 'valid': True, 'score_inputs_valid': bool(groups['G']), 'diagnostics_valid': True, 'qualification_pass': bool(groups['G']), 'G': groups['G'], 'A': groups['A'], 'Q': groups['Q'], 'M': groups['M'], 'C': groups['C'], 'R': groups['R'], 'D': groups['D'], 'groups': groups, 'group_weights': WEIGHTS, 'raw_total': float(total), 'total': float(total), 'score': float(total), 'admission_score_pass': bool(groups['G'] and total >= 90.0), 'per_scenario': per_scenario, 'per_metric': per_metric, 'failure_reasons': list(dict.fromkeys(failures))}

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    gate, failures, integrity = integrity_gate(evidence)
    if not gate:
        groups = {'G': 0.0, **{name: 0.0 for name in WEIGHTS}}
        return make_receipt(evidence, groups, 0.0, failures, {}, {'integrity': integrity}, 'QUALIFICATION_FAILED')
    rows = {str(row['id']): row for row in evidence['scenarios']}
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['native_nominal_dual_step']
    heading_case = metrics['moderate_heading_boundary']
    depth_case = metrics['moderate_depth_boundary']
    current_speed_case = metrics['current_magnitude_boundary']
    current_direction_case = metrics['current_direction_boundary']
    propulsion_case = metrics['reduced_propulsive_authority']
    a_parts = {'heading_tracking': (low(nominal['heading_rmse_deg'], 2.0, 12.0), 0.3), 'heading_tail': (low(nominal['heading_tail_error_deg'], 1.0, 8.0), 0.1), 'depth_tracking': (low(nominal['depth_rmse_m'], 0.6, 4.0), 0.3), 'depth_tail': (low(nominal['depth_tail_error_m'], 0.3, 2.5), 0.1), 'attitude_bounds': (min(low(nominal['roll_peak_deg'], 15.0, 35.0), low(nominal['pitch_peak_deg'], 20.0, 40.0)), 0.1), 'forward_motion': (high(nominal['minimum_speed_mps'], 0.1, 0.8), 0.1)}
    A = weighted(a_parts)
    q_parts = {'rudder_limit': (low(nominal['rudder_peak_deg'], 20.0, 22.0), 0.15), 'stern_limit': (low(nominal['stern_peak_deg'], 20.0, 22.0), 0.15), 'position_kinematics': (low(nominal['position_kinematic_relative_rmse'], 0.03, 0.3), 0.2), 'attitude_kinematics': (low(nominal['attitude_kinematic_relative_rmse'], 0.03, 0.3), 0.2), 'coupled_lateral_state': (high(nominal['lateral_velocity_rms_mps'], 0.005, 0.05), 0.1), 'coupled_vertical_state': (high(nominal['vertical_velocity_rms_mps'], 0.005, 0.05), 0.1), 'bounded_rates': (min(low(nominal['yaw_rate_peak_degps'], 15.0, 40.0), low(nominal['pitch_rate_peak_degps'], 15.0, 40.0)), 0.1)}
    Q = weighted(q_parts)
    all_inputs = [values[key] for values in metrics.values() for key in ('heading_input_error_deg', 'depth_input_error_m', 'current_speed_input_error_mps', 'current_direction_input_error_rad', 'propeller_input_error_rpm')]
    depth_boundary_response = abs(depth_case['down_endpoint_m'] - nominal['down_endpoint_m'])
    current_speed_response = max(abs(current_speed_case['east_endpoint_m'] - nominal['east_endpoint_m']), abs(current_speed_case['north_endpoint_m'] - nominal['north_endpoint_m']), abs(current_speed_case['heading_rmse_deg'] - nominal['heading_rmse_deg']))
    current_direction_response = max(abs(current_direction_case['east_endpoint_m'] - nominal['east_endpoint_m']), abs(current_direction_case['north_endpoint_m'] - nominal['north_endpoint_m']), abs(current_direction_case['heading_rmse_deg'] - nominal['heading_rmse_deg']))
    propulsion_response = nominal['mean_speed_mps'] - propulsion_case['mean_speed_mps']
    heading_loop = min(high(heading_case['heading_response_amplitude_deg'], 0.6 * heading_case['heading_command_amplitude_deg'], 0.9 * heading_case['heading_command_amplitude_deg']), high(heading_case['rudder_active_rms_deg'], 0.1, 1.0))
    depth_loop = min(high(depth_case['depth_response_amplitude_m'], 0.6 * depth_case['depth_command_amplitude_m'], 0.9 * depth_case['depth_command_amplitude_m']), high(depth_case['stern_active_rms_deg'], 0.1, 1.0), high(depth_boundary_response, 2.0, 6.0))
    c_parts = {'heading_command_to_rudder_and_yaw_response': (heading_loop, 0.5), 'depth_command_to_stern_and_depth_response': (depth_loop, 0.5)}
    C = weighted(c_parts)
    m_parts = {'all_scenario_inputs_applied': (low(max(all_inputs), 1e-08, 0.001), 0.1), 'sixdof_position_kinematic_consistency': (q_parts['position_kinematics'][0], 0.15), 'sixdof_attitude_kinematic_consistency': (q_parts['attitude_kinematics'][0], 0.15), 'coupled_lateral_and_vertical_dynamics': (min(q_parts['coupled_lateral_state'][0], q_parts['coupled_vertical_state'][0]), 0.15), 'current_magnitude_causality': (high(current_speed_response, 0.5, 5.0), 0.15), 'current_direction_causality': (high(current_direction_response, 0.5, 5.0), 0.15), 'propulsive_authority_causality': (high(propulsion_response, 0.05, 0.2), 0.15)}
    M = weighted(m_parts)
    r_by_scenario: dict[str, float] = {}
    d_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = weighted({'heading_tracking': (low(values['heading_rmse_deg'], 3.0, 18.0), 0.25), 'depth_tracking': (low(values['depth_rmse_m'], 1.0, 6.0), 0.25), 'attitude_bounds': (min(low(values['roll_peak_deg'], 20.0, 45.0), low(values['pitch_peak_deg'], 25.0, 45.0)), 0.15), 'control_limits': (min(low(values['rudder_peak_deg'], 20.0, 22.0), low(values['stern_peak_deg'], 20.0, 22.0)), 0.15), 'forward_authority': (high(values['minimum_speed_mps'], 0.05, 0.6), 0.2)})
        d_by_scenario[name] = weighted({'heading_recovery': (low(values['heading_settling_s'], 100.0, 260.0), 0.25), 'depth_recovery': (low(values['depth_settling_s'], 120.0, 200.0), 0.25), 'heading_late_excursion': (low(values['heading_peak_error_after_60s_deg'], 5.0, 20.0), 0.15), 'depth_late_excursion': (low(values['depth_peak_error_after_80s_m'], 1.5, 6.0), 0.15), 'limited_saturation': (min(low(values['rudder_saturation_fraction'], 0.05, 0.4), low(values['stern_saturation_fraction'], 0.05, 0.4)), 0.1), 'bounded_cross_axis': (min(low(values['roll_peak_deg'], 20.0, 45.0), low(values['pitch_peak_deg'], 25.0, 45.0)), 0.1)})
    R = min(r_by_scenario.values())
    D = min(d_by_scenario.values())
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'C': C, 'R': R, 'D': D}
    total = geometric(groups)
    failures.extend((name + ' group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    per_metric = {'integrity': integrity, 'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_behavioral_utilities': m_parts, 'C_causal_loop_utilities': c_parts, 'R_by_scenario': r_by_scenario, 'D_by_scenario': d_by_scenario, 'derived': {'depth_boundary_endpoint_change_m': depth_boundary_response, 'current_magnitude_response': current_speed_response, 'current_direction_response': current_direction_response, 'reduced_propulsion_speed_drop_mps': propulsion_response}, 'semantic_block_names_used': False}
    return make_receipt(evidence, groups, total, failures, metrics, per_metric, 'SCORED')

def targeted_sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, Any] = {}

    def record(name: str, mutant: dict[str, Any]) -> None:
        result = score_evidence(mutant)
        cases[name] = {'G': result['G'], 'total': result['total'], 'groups': result['groups']}
    mutant = copy.deepcopy(evidence)
    mutant.pop('reference_substantive_modifications', None)
    mutant.setdefault('source_static_audit', {})['core_path_qualified'] = False
    record('reference_only_and_source_name_gate_do_not_clear_G', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'][0]['outputs'].pop('vehicle_state', None)
    record('missing_required_output_clears_G', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['cheating_detected'] = True
    record('explicit_anti_cheat_failure_clears_G', mutant)
    return {'schema': 'simuverity.f90-xrobo05-targeted-sanity.v1', 'task_id': TASK_ID, 'cases': cases}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8-sig'))
    output = args.out or args.evidence.with_name('offline_score.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(score_evidence(evidence), indent=2, ensure_ascii=False), encoding='utf-8')
    if args.sanity_out:
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(json.dumps(targeted_sanity_suite(evidence), indent=2, ensure_ascii=False), encoding='utf-8')
    print(output)
if __name__ == '__main__':
    main()
