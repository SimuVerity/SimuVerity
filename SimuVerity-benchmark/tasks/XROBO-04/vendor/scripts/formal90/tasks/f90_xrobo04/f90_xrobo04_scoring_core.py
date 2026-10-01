"""Pure-offline SCORING_CORE scorer for F90-XROBO-04 complete evidence.

Qualification checks runtime, required finite evidence, subject role, and
anti-cheat signals only. Rover,
wheel, controller, motor, actuator, and manipulator block names are never used
for candidate qualification or score credit; M/C use official interventions
and output behavior.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XROBO-04'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-04:scoring'
REQUIRED = ('nominal_path1_uneven', 'path2_uneven', 'path2_flat', 'path1_low_speed', 'path1_low_friction')
REQUIRED_SUMMARY = ('mission_terminal_complete', 'pickup_latched', 'stored_latched', 'path_rmse_m', 'path_p95_m', 'path_tail_mean_m', 'speed_mean_mps', 'speed_rmse_mps', 'speed_tail_error_mps', 'max_abs_roll_pitch_rad', 'p95_abs_roll_pitch_rad', 'wheel_slip_rms', 'wheel_slip_p95_abs', 'wheel_torque_peak_Nm', 'arm_joint_rmse_rad', 'arm_joint_peak_error_rad', 'minimum_ee_sample_distance_m', 'final_energy_Wh', 'distance_travelled_m', 'drive_phase_sample_count', 'drive_phase_end_s', 'simulation_end_s')
WEIGHTS = {'A': 0.15, 'Q': 0.15, 'M': 0.15, 'C': 0.15, 'R': 0.2, 'D': 0.2}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def number(value: Any, default: float=math.nan) -> float:
    if isinstance(value, bool):
        return float(value)
    try:
        converted = float(value)
    except (TypeError, ValueError):
        return default
    return converted if math.isfinite(converted) else default

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value) or zero <= full:
        return 0.0
    return clamp((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value) or full <= zero:
        return 0.0
    return clamp((value - zero) / (full - zero))

def weighted(values: dict[str, float], weights: dict[str, float]) -> float:
    denominator = sum(weights.values())
    if denominator <= 0:
        return 0.0
    return sum((clamp(values[name]) * weights[name] for name in weights)) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return 100.0 * math.exp(sum((WEIGHTS[name] * math.log(clamp(groups[name])) for name in WEIGHTS)))

def _summary_complete(row: dict[str, Any]) -> bool:
    summary = row.get('summary')
    if not isinstance(summary, dict) or not all((name in summary for name in REQUIRED_SUMMARY)):
        return False
    return all((math.isfinite(number(summary[name])) for name in REQUIRED_SUMMARY))

def _row_integrity(row: dict[str, Any]) -> bool:
    return row.get('simulation_pass') is True and row.get('valid') is True and (number(row.get('time_start_s')) <= 1e-06) and (number(row.get('time_end_s')) > 100.0) and (number(row.get('sample_count')) >= 20.0) and _summary_complete(row)

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
    evidence_complete = exact_scenarios and all((_row_integrity(rows[name]) for name in REQUIRED))
    if not evidence_complete:
        failures.append('required outputs are missing, nonfinite, incomplete, or time-incomplete')
    raw = evidence.get('raw_artifact', {})
    raw_artifact_present = isinstance(raw, dict) and isinstance(raw.get('path'), str) and bool(raw.get('path'))
    candidate_subject = evidence.get('evaluation_subject') == 'candidate'
    identity_pass = evidence.get('evaluation_subject') in {'candidate', 'reference'}
    if not identity_pass:
        failures.append('candidate/reference evidence identity is invalid')
    score_free = evidence.get('contains_score_decisions') is not True
    explicit_anti_cheat_rejection = evidence.get('cheating_detected') is True or evidence.get('anti_cheat_pass') is False
    anti_cheat_pass = score_free and (not explicit_anti_cheat_rejection)
    if not anti_cheat_pass:
        failures.append('anti-cheat integrity failed')
    passed = all(runtime.values()) and evidence_complete and raw_artifact_present and identity_pass and anti_cheat_pass
    diagnostics = {'runtime': runtime, 'exact_required_scenarios': exact_scenarios, 'required_outputs_finite_complete_time_aligned': evidence_complete, 'candidate_or_reference_identity_pass': identity_pass, 'raw_artifact_present': raw_artifact_present, 'score_free_evidence': score_free, 'anti_cheat_pass': anti_cheat_pass, 'subject_role': 'candidate' if candidate_subject else 'reference', 'source_name_or_block_path_core_gate_ignored': True}
    return (passed, list(dict.fromkeys(failures)), diagnostics)

def make_receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, failures: list[str], per_scenario: dict[str, Any], per_metric: dict[str, Any], status: str) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xrobo04-score.v1', 'status': status, 'policy_id': POLICY_ID, 'task_id': TASK_ID, 'formula': 'G*100*A^0.15*Q^0.15*M^0.15*C^0.15*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 90.0, 'preferred_reference_score': 90.0, 'valid': True, 'score_inputs_valid': bool(groups['G']), 'diagnostics_valid': True, 'qualification_pass': bool(groups['G']), 'G': groups['G'], 'A': groups['A'], 'Q': groups['Q'], 'M': groups['M'], 'C': groups['C'], 'R': groups['R'], 'D': groups['D'], 'groups': groups, 'group_weights': WEIGHTS, 'raw_total': float(total), 'total': float(total), 'score': float(total), 'admission_score_pass': bool(groups['G'] and total >= 90.0), 'per_scenario': per_scenario, 'per_metric': per_metric, 'failure_reasons': list(dict.fromkeys(failures))}

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    gate, failures, integrity = integrity_gate(evidence)
    if not gate:
        groups = {'G': 0.0, **{name: 0.0 for name in WEIGHTS}}
        return make_receipt(evidence, groups, 0.0, failures, {}, {'integrity': integrity}, 'QUALIFICATION_FAILED')
    rows = {str(row['id']): row for row in evidence['scenarios']}
    metrics = {name: rows[name]['summary'] for name in REQUIRED}
    nominal = metrics['nominal_path1_uneven']
    energy_activity = high(number(nominal['final_energy_Wh']), 1e-06, 0.0001)
    a_parts = {'path_rmse': low(number(nominal['path_rmse_m']), 0.08, 0.8), 'path_tail': low(number(nominal['path_tail_mean_m']), 0.1, 1.0), 'speed_rmse': low(number(nominal['speed_rmse_mps']), 0.003, 0.02), 'pickup': float(bool(nominal['pickup_latched'])), 'storage': float(bool(nominal['stored_latched']))}
    A = weighted(a_parts, {'path_rmse': 0.25, 'path_tail': 0.1, 'speed_rmse': 0.2, 'pickup': 0.2, 'storage': 0.25})
    q_parts = {'body_attitude': low(number(nominal['p95_abs_roll_pitch_rad']), 0.2, 0.7), 'wheel_slip': low(number(nominal['wheel_slip_p95_abs']), 0.6, 3.0), 'bounded_wheel_torque': low(number(nominal['wheel_torque_peak_Nm']), 450.0, 650.0), 'finite_energy': energy_activity, 'arm_tracking': low(number(nominal['arm_joint_rmse_rad']), 0.03, 0.3)}
    Q = weighted(q_parts, {'body_attitude': 0.2, 'wheel_slip': 0.25, 'bounded_wheel_torque': 0.15, 'finite_energy': 0.15, 'arm_tracking': 0.25})
    terrain_delta = abs(number(metrics['path2_uneven']['p95_abs_roll_pitch_rad']) - number(metrics['path2_flat']['p95_abs_roll_pitch_rad']))
    friction_delta = number(metrics['path1_low_friction']['wheel_slip_p95_abs']) - number(nominal['wheel_slip_p95_abs'])
    speed_delta = abs(number(nominal['speed_mean_mps']) - number(metrics['path1_low_speed']['speed_mean_mps']))
    terrain_utility = high(terrain_delta, 0.005, 0.05)
    friction_utility = high(friction_delta, 0.01, 0.2)
    mobile_manipulation = min(float(bool(nominal['pickup_latched'])), float(bool(nominal['stored_latched'])))
    physical_motion_energy = min(energy_activity, float(number(nominal['distance_travelled_m']) > 0.0))
    m_parts = {'terrain_intervention_response': terrain_utility, 'friction_intervention_response': friction_utility, 'multi_condition_contact_response': min(terrain_utility, friction_utility), 'physical_motion_energy_coupling': physical_motion_energy, 'mobile_manipulation_mission': mobile_manipulation}
    M = weighted(m_parts, {'terrain_intervention_response': 0.2, 'friction_intervention_response': 0.15, 'multi_condition_contact_response': 0.2, 'physical_motion_energy_coupling': 0.2, 'mobile_manipulation_mission': 0.25})
    path_tracking = {name: low(number(item['path_rmse_m']), 0.12, 1.0) for name, item in metrics.items()}
    speed_tracking = {name: low(number(item['speed_rmse_mps']), 0.004, 0.025) for name, item in metrics.items()}
    c_parts = {'speed_command_intervention_response': high(speed_delta, 0.001, 0.005), 'worst_path_feedback_tracking': min(path_tracking.values()), 'worst_speed_feedback_tracking': min(speed_tracking.values()), 'joint_command_to_measured_arm_tracking': q_parts['arm_tracking'], 'end_effector_pickup_storage_response': min(mobile_manipulation, low(number(nominal['minimum_ee_sample_distance_m']), 0.03, 0.4))}
    C = weighted(c_parts, {'speed_command_intervention_response': 0.2, 'worst_path_feedback_tracking': 0.25, 'worst_speed_feedback_tracking': 0.2, 'joint_command_to_measured_arm_tracking': 0.15, 'end_effector_pickup_storage_response': 0.2})
    scenario_scores: dict[str, float] = {}
    for name, item in metrics.items():
        parts = {'path': path_tracking[name], 'speed': speed_tracking[name], 'attitude': low(number(item['max_abs_roll_pitch_rad']), 0.35, 1.0), 'pickup': float(bool(item['pickup_latched'])), 'storage': float(bool(item['stored_latched']))}
        scenario_scores[name] = weighted(parts, {'path': 0.25, 'speed': 0.2, 'attitude': 0.15, 'pickup': 0.15, 'storage': 0.25})
    R = min(scenario_scores.values())
    d_parts = {'tail_path_recovery': low(number(nominal['path_tail_mean_m']), 0.1, 1.0), 'tail_speed_recovery': low(number(nominal['speed_tail_error_mps']), 0.002, 0.015), 'arm_joint_convergence': low(number(nominal['arm_joint_peak_error_rad']), 0.1, 0.8), 'end_effector_sample_approach': low(number(nominal['minimum_ee_sample_distance_m']), 0.03, 0.4), 'mission_terminal': float(bool(nominal['mission_terminal_complete']))}
    D = weighted(d_parts, {'tail_path_recovery': 0.2, 'tail_speed_recovery': 0.15, 'arm_joint_convergence': 0.2, 'end_effector_sample_approach': 0.2, 'mission_terminal': 0.25})
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'C': C, 'R': R, 'D': D}
    total = geometric(groups)
    failures.extend((name + ' group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    per_metric = {'integrity': integrity, 'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_behavioral_utilities': m_parts, 'C_causal_control_utilities': c_parts, 'R_scenario_scores': scenario_scores, 'D_utilities': d_parts, 'causal_deltas': {'uneven_minus_flat_attitude_rad': terrain_delta, 'low_friction_minus_nominal_slip': friction_delta, 'nominal_minus_low_speed_mps': speed_delta}, 'semantic_or_block_path_names_used': False}
    return make_receipt(evidence, groups, total, failures, metrics, per_metric, 'SCORED')

def targeted_sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, Any] = {}

    def record(name: str, mutant: dict[str, Any]) -> None:
        result = score_evidence(mutant)
        cases[name] = {'G': result['G'], 'total': result['total'], 'groups': result['groups']}
    mutant = copy.deepcopy(evidence)
    mutant.setdefault('source_static_audit', {})['core_path_qualified'] = False
    record('source_name_gate_does_not_clear_G', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'][0]['summary'].pop('path_rmse_m', None)
    record('missing_required_summary_clears_G', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['cheating_detected'] = True
    record('explicit_anti_cheat_failure_clears_G', mutant)
    return {'schema': 'simuverity.f90-xrobo04-targeted-sanity.v1', 'task_id': TASK_ID, 'cases': cases}

def main() -> int:
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
    print(json.dumps({'out': str(output)}, ensure_ascii=False))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
