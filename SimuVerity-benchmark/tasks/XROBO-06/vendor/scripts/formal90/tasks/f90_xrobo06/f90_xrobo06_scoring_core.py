"""Pure offline scorer for current F90-XROBO-06 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XROBO-06'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-06:scoring'
REQUIRED = ['native_nominal_walk', 'moderate_low_friction', 'moderate_actuator_derating', 'cold_start_height_offset']
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}
REQUIRED_OUTPUTS = {'time_s', 'foot_contact', 'torso_state', 'joint_state', 'control_action', 'joint_torque', 'forward_position_m', 'power_w', 'reward', 'done'}

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
    return sum((clamp(value) * weight for value, weight in parts.values())) / denominator if denominator else 0.0

def geometric(groups: dict[str, float]) -> float:
    if groups['G'] <= 0:
        return 0.0
    value = 1.0
    for name, weight in WEIGHTS.items():
        value *= clamp(groups[name]) ** weight
    return value

def vector(value: Any) -> list[float]:
    if not isinstance(value, list):
        return []
    result: list[float] = []
    for item in value:
        if isinstance(item, list):
            if len(item) != 1:
                raise ValueError('expected a single-column vector')
            result.append(float(item[0]))
        else:
            result.append(float(item))
    return result

def matrix(value: Any, columns: int) -> list[list[float]]:
    if not isinstance(value, list):
        return []
    if columns == 1:
        return [[item] for item in vector(value)]
    rows: list[list[float]] = []
    for item in value:
        if not isinstance(item, list) or len(item) != columns:
            raise ValueError(f'expected {columns} columns')
        rows.append([float(entry) for entry in item])
    return rows

def column(values: list[list[float]], index: int) -> list[float]:
    return [row[index] for row in values]

def correlation(left: list[float], right: list[float]) -> float:
    count = min(len(left), len(right))
    if count < 3:
        return 0.0
    left = left[:count]
    right = right[:count]
    left_mean = mean(left)
    right_mean = mean(right)
    left_centered = [value - left_mean for value in left]
    right_centered = [value - right_mean for value in right]
    denominator = math.sqrt(sum((value * value for value in left_centered)) * sum((value * value for value in right_centered)))
    if denominator <= 1e-12:
        return 0.0
    return sum((a * b for a, b in zip(left_centered, right_centered))) / denominator

def trapz(time: list[float], values: list[float]) -> float:
    return sum((0.5 * (values[index] + values[index - 1]) * (time[index] - time[index - 1]) for index in range(1, min(len(time), len(values)))))

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    time = vector(outputs['time_s'])
    contact = matrix(outputs['foot_contact'], 2)
    torso = matrix(outputs['torso_state'], 11)
    joint = matrix(outputs['joint_state'], 12)
    action = matrix(outputs['control_action'], 6)
    torque = matrix(outputs['joint_torque'], 6)
    position = vector(outputs['forward_position_m'])
    power = vector(outputs['power_w'])
    reward = vector(outputs['reward'])
    done = vector(outputs['done'])
    count = min(len(time), len(contact), len(torso), len(joint), len(action), len(torque), len(position), len(power), len(reward), len(done))
    if count < 3:
        raise ValueError('insufficient aligned evidence')
    time = time[:count]
    contact = contact[:count]
    torso = torso[:count]
    joint = joint[:count]
    action = action[:count]
    torque = torque[:count]
    position = position[:count]
    power = power[:count]
    reward = reward[:count]
    done = done[:count]
    requested_horizon = float(row['requested_inputs']['stop_time_s'])
    done_indices = [index for index, value in enumerate(done) if value >= 0.5]
    effective_index = done_indices[0] if done_indices else count - 1
    effective_index = max(2, effective_index)
    active = slice(0, effective_index + 1)
    active_time = time[active]
    active_contact = contact[active]
    active_torso = torso[active]
    active_joint = joint[active]
    active_action = action[active]
    active_torque = torque[active]
    active_position = position[active]
    active_power = power[active]
    active_reward = reward[active]
    duration = max(active_time[-1] - active_time[0], 1e-09)
    forward_distance = active_position[-1] - active_position[0]
    angles = [math.sqrt(row[0] ** 2 + row[1] ** 2 + row[2] ** 2) for row in active_torso]
    lateral = [abs(row[6]) for row in active_torso]
    vertical = [abs(row[7]) for row in active_torso]
    right_contact = [1.0 if row[0] > 0.5 else 0.0 for row in active_contact]
    left_contact = [1.0 if row[1] > 0.5 else 0.0 for row in active_contact]
    no_contact = [1.0 if right == 0.0 and left == 0.0 else 0.0 for right, left in zip(right_contact, left_contact)]
    double_support = [1.0 if right == 1.0 and left == 1.0 else 0.0 for right, left in zip(right_contact, left_contact)]
    support_state = [0 if right == left else 1 if right > left else -1 for right, left in zip(right_contact, left_contact)]
    alternations = sum((1 for index in range(1, len(support_state)) if support_state[index] != 0 and support_state[index - 1] != 0 and (support_state[index] != support_state[index - 1])))
    upright = [angle <= math.radians(30.0) and lat <= 1.0 and (vert <= 0.5) for angle, lat, vert in zip(angles, lateral, vertical)]
    angle_columns = [0, 2, 4, 6, 8, 10]
    rate_columns = [1, 3, 5, 7, 9, 11]
    joint_spans = [max(column(active_joint, index)) - min(column(active_joint, index)) for index in angle_columns]
    torque_limit = 100.0 * float(row['requested_inputs']['TorqueLimitScale'])
    torque_flat = [abs(value) for sample in active_torque for value in sample]
    action_flat = [abs(value) for sample in active_action for value in sample]
    torque_action_correlations = [abs(correlation(column(active_action, index), column(active_torque, index))) for index in range(6)]
    torque_rate_correlations = [abs(correlation(column(active_torque, index), column(active_joint, rate_columns[index]))) for index in range(6)]
    tail_start = max(0, len(active_time) - max(3, len(active_time) // 5))
    tail_duration = max(active_time[-1] - active_time[tail_start], 1e-09)
    tail_speed = (active_position[-1] - active_position[tail_start]) / tail_duration
    return {'requested_horizon_s': requested_horizon, 'effective_duration_s': duration, 'survival_fraction': clamp(duration / requested_horizon), 'termination_seen': 1.0 if done_indices else 0.0, 'forward_distance_m': forward_distance, 'mean_forward_speed_mps': forward_distance / duration, 'tail_forward_speed_mps': tail_speed, 'lateral_peak_m': max(lateral), 'vertical_peak_m': max(vertical), 'torso_angle_peak_deg': math.degrees(max(angles)), 'upright_fraction': mean([1.0 if value else 0.0 for value in upright]), 'right_contact_fraction': mean(right_contact), 'left_contact_fraction': mean(left_contact), 'no_contact_fraction': mean(no_contact), 'double_support_fraction': mean(double_support), 'support_alternations': float(alternations), 'mean_joint_angle_span_rad': mean(joint_spans), 'minimum_joint_angle_span_rad': min(joint_spans), 'joint_rate_rms_radps': rms([row[index] for row in active_joint for index in rate_columns]), 'maximum_action_abs': max(action_flat), 'action_rms': rms(action_flat), 'mean_action_span': mean([max(column(active_action, index)) - min(column(active_action, index)) for index in range(6)]), 'maximum_torque_abs_Nm': max(torque_flat), 'torque_rms_Nm': rms(torque_flat), 'torque_saturation_fraction': mean([1.0 if value >= 0.98 * torque_limit else 0.0 for value in torque_flat]), 'mean_abs_action_torque_correlation': mean(torque_action_correlations), 'mean_abs_torque_rate_correlation': mean(torque_rate_correlations), 'mechanical_energy_abs_J': trapz(active_time, [abs(value) for value in active_power]), 'energy_per_forward_m_Jpm': trapz(active_time, [abs(value) for value in active_power]) / max(abs(forward_distance), 0.1), 'cumulative_reward': trapz(active_time, active_reward), 'tail_vertical_abs_m': abs(active_torso[-1][7]), 'tail_lateral_abs_m': abs(active_torso[-1][6]), 'tail_torso_angle_deg': math.degrees(angles[-1]), 'early_vertical_peak_m': max(vertical[:max(3, min(len(vertical), int(3.0 / max(time[1] - time[0], 1e-06))))])}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    scenarios_valid = all((name in rows and bool(rows[name].get('valid')) and (REQUIRED_OUTPUTS <= set(rows[name].get('outputs', {}))) for name in REQUIRED))
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': scenarios_valid, 'reference_unmodified': int(evidence.get('reference_substantive_modifications', -1)) == 0, 'physical_closed_loop_path': bool(static.get('core_path_qualified'))}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    try:
        metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    except (KeyError, TypeError, ValueError) as error:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, ['evidence_shape'])
    nominal = metrics['native_nominal_walk']
    friction = metrics['moderate_low_friction']
    derated = metrics['moderate_actuator_derating']
    cold = metrics['cold_start_height_offset']
    a_parts = {'survival': (high(nominal['survival_fraction'], 0.65, 0.98), 0.2), 'forward_distance': (high(nominal['forward_distance_m'], 1.0, 8.0), 0.25), 'forward_speed': (high(nominal['mean_forward_speed_mps'], 0.1, 0.5), 0.15), 'upright': (high(nominal['upright_fraction'], 0.8, 0.99), 0.15), 'lateral_bound': (low(nominal['lateral_peak_m'], 0.3, 1.0), 0.1), 'vertical_bound': (low(nominal['vertical_peak_m'], 0.2, 0.5), 0.05), 'torso_bound': (low(nominal['torso_angle_peak_deg'], 15.0, 30.0), 0.1)}
    group_a = weighted(a_parts)
    q_parts = {'right_contact': (high(nominal['right_contact_fraction'], 0.03, 0.15), 0.1), 'left_contact': (high(nominal['left_contact_fraction'], 0.03, 0.15), 0.1), 'limited_flight': (low(nominal['no_contact_fraction'], 0.2, 0.65), 0.1), 'contact_alternation': (high(nominal['support_alternations'], 2.0, 10.0), 0.15), 'joint_excursion': (high(nominal['mean_joint_angle_span_rad'], 0.12, 0.4), 0.15), 'nonconstant_action': (high(nominal['mean_action_span'], 0.1, 0.5), 0.1), 'normalized_action_bound': (low(nominal['maximum_action_abs'], 1.01, 1.1), 0.1), 'finite_torque_bound': (low(nominal['maximum_torque_abs_Nm'], 100.5, 105.0), 0.1), 'effort_quality': (low(nominal['energy_per_forward_m_Jpm'], 1500.0, 8000.0), 0.1)}
    group_q = weighted(q_parts)
    friction_response = max(abs(friction['forward_distance_m'] - nominal['forward_distance_m']) / max(abs(nominal['forward_distance_m']), 1.0), abs(friction['no_contact_fraction'] - nominal['no_contact_fraction']), abs(friction['energy_per_forward_m_Jpm'] - nominal['energy_per_forward_m_Jpm']) / max(abs(nominal['energy_per_forward_m_Jpm']), 100.0))
    torque_response = max(abs(derated['maximum_torque_abs_Nm'] - nominal['maximum_torque_abs_Nm']) / 100.0, abs(derated['forward_distance_m'] - nominal['forward_distance_m']) / max(abs(nominal['forward_distance_m']), 1.0), abs(derated['torque_saturation_fraction'] - nominal['torque_saturation_fraction']))
    height_response = max(abs(cold['early_vertical_peak_m'] - nominal['early_vertical_peak_m']), abs(cold['tail_vertical_abs_m'] - nominal['tail_vertical_abs_m']), abs(cold['forward_distance_m'] - nominal['forward_distance_m']) / max(abs(nominal['forward_distance_m']), 1.0))
    requested_inputs_correct = float(rows['native_nominal_walk']['requested_inputs']['FootFrictionScale']) == 1.0 and float(rows['moderate_low_friction']['requested_inputs']['FootFrictionScale']) == 0.75 and (float(rows['moderate_actuator_derating']['requested_inputs']['TorqueLimitScale']) == 0.85) and (float(rows['cold_start_height_offset']['requested_inputs']['InitialHeight_m']) == 1.5)
    m_parts = {'static_closed_loop_multibody_path': (1.0, 0.2), 'all_scenario_inputs_applied': (1.0 if requested_inputs_correct else 0.0, 0.08), 'bilateral_contact_support': (min(high(nominal['right_contact_fraction'], 0.02, 0.12), high(nominal['left_contact_fraction'], 0.02, 0.12), high(nominal['support_alternations'], 1.0, 8.0)), 0.12), 'action_to_torque': (high(nominal['mean_abs_action_torque_correlation'], 0.05, 0.25), 0.12), 'torque_to_joint_motion': (min(high(nominal['torque_rms_Nm'], 2.0, 15.0), high(nominal['joint_rate_rms_radps'], 0.05, 0.5), high(nominal['mean_abs_torque_rate_correlation'], 0.02, 0.15)), 0.12), 'physical_forward_motion': (min(high(nominal['forward_distance_m'], 0.5, 5.0), high(nominal['mean_joint_angle_span_rad'], 0.1, 0.35)), 0.12), 'friction_causality': (high(friction_response, 0.005, 0.05), 0.08), 'torque_limit_causality': (high(torque_response, 0.005, 0.05), 0.08), 'initial_height_causality': (high(height_response, 0.002, 0.025), 0.08)}
    group_m = weighted(m_parts)
    critical_mechanism = [m_parts['bilateral_contact_support'][0], m_parts['action_to_torque'][0], m_parts['torque_to_joint_motion'][0], m_parts['physical_forward_motion'][0], m_parts['friction_causality'][0], m_parts['torque_limit_causality'][0], m_parts['initial_height_causality'][0]]
    if min(critical_mechanism) < 0.1:
        group_m = min(group_m, 0.35)
    r_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        requested_limit = 100.0 * float(rows[name]['requested_inputs']['TorqueLimitScale'])
        r_by_scenario[name] = weighted({'survival': (high(values['survival_fraction'], 0.55, 0.95), 0.25), 'forward_progress': (high(values['forward_distance_m'], 0.8, 6.0), 0.2), 'upright': (high(values['upright_fraction'], 0.75, 0.97), 0.15), 'lateral_bound': (low(values['lateral_peak_m'], 0.4, 1.0), 0.1), 'vertical_bound': (low(values['vertical_peak_m'], 0.3, 0.5), 0.1), 'torso_bound': (low(values['torso_angle_peak_deg'], 20.0, 30.0), 0.1), 'scenario_torque_bound': (low(values['maximum_torque_abs_Nm'], requested_limit + 0.5, requested_limit + 5.0), 0.1)})
    group_r = min(r_by_scenario.values())
    d_parts = {'cold_start_survival': (high(cold['survival_fraction'], 0.55, 0.95), 0.2), 'cold_start_progress': (high(cold['forward_distance_m'], 0.8, 6.0), 0.15), 'cold_start_tail_upright': (min(low(cold['tail_vertical_abs_m'], 0.2, 0.5), low(cold['tail_lateral_abs_m'], 0.35, 1.0), low(cold['tail_torso_angle_deg'], 18.0, 30.0)), 0.2), 'cold_start_response_observed': (high(height_response, 0.002, 0.025), 0.1), 'derated_survival': (high(derated['survival_fraction'], 0.55, 0.95), 0.15), 'derated_progress': (high(derated['forward_distance_m'], 0.8, 6.0), 0.1), 'derated_finite_torque': (low(derated['maximum_torque_abs_Nm'], 85.5, 90.0), 0.1)}
    group_d = weighted(d_parts)
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D': d_parts, 'derived': {'friction_response': friction_response, 'torque_limit_response': torque_response, 'initial_height_response': height_response}}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xrobo06-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['missing_closed_loop_multibody_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('torso_state', None)
    cases['missing_required_output'] = score(missing_output)['score']
    kinematic = copy.deepcopy(evidence)
    for row in kinematic['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['foot_contact'] = [[0.0, 0.0] for _ in range(count)]
        row['outputs']['joint_state'] = [[0.0] * 12 for _ in range(count)]
        row['outputs']['control_action'] = [[0.0] * 6 for _ in range(count)]
        row['outputs']['joint_torque'] = [[0.0] * 6 for _ in range(count)]
    cases['kinematic_or_replayed_body'] = score(kinematic)['score']
    no_contact = copy.deepcopy(evidence)
    for row in no_contact['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['foot_contact'] = [[0.0, 0.0] for _ in range(count)]
    cases['disconnected_foot_contact'] = score(no_contact)['score']
    inactive_actuation = copy.deepcopy(evidence)
    for row in inactive_actuation['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['control_action'] = [[0.0] * 6 for _ in range(count)]
        row['outputs']['joint_torque'] = [[0.0] * 6 for _ in range(count)]
    cases['inactive_joint_actuation'] = score(inactive_actuation)['score']
    fixed_body = copy.deepcopy(evidence)
    for row in fixed_body['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['torso_state'] = [[0.0] * 11 for _ in range(count)]
        row['outputs']['forward_position_m'] = [0.0 for _ in range(count)]
    cases['fixed_body_pose'] = score(fixed_body)['score']
    ignored_inputs = copy.deepcopy(evidence)
    nominal_outputs = next((row for row in ignored_inputs['scenarios'] if row['id'] == 'native_nominal_walk'))['outputs']
    for row in ignored_inputs['scenarios']:
        if row['id'] != 'native_nominal_walk':
            row['outputs'] = copy.deepcopy(nominal_outputs)
    cases['ignored_scenario_inputs'] = score(ignored_inputs)['score']
    reward_only = copy.deepcopy(evidence)
    for row in reward_only['scenarios']:
        row['outputs'] = {'time_s': row['outputs']['time_s'], 'reward': row['outputs']['reward']}
    cases['reward_without_physical_evidence'] = score(reward_only)['score']
    return {'schema': 'simuverity.f90-xrobo06-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

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
