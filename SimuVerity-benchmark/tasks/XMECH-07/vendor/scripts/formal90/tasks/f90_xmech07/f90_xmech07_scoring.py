"""Pure offline scorer for fixed F90-XMECH-07 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XMECH-07'
POLICY_ID = 'simuverity-101-v1:f90-xmech-07:scoring'
REQUIRED = ['native_nominal_transfer', 'moderate_low_belt_friction', 'moderate_high_belt_friction', 'moderate_slow_belts', 'belt_speed_mismatch', 'heavier_payload_boundary']
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

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
    return sum((clamp(score) * weight for score, weight in parts.values())) / denominator if denominator > 0 else 0.0

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[name] * math.log(groups[name]) for name in WEIGHTS)))

def columns(rows: list[list[float]]) -> list[list[float]]:
    return [list(map(float, column)) for column in zip(*rows)]

def first_time(time: list[float], active: list[bool]) -> float:
    for t, state in zip(time, active):
        if state:
            return t
    return math.inf

def last_time(time: list[float], active: list[bool]) -> float:
    for t, state in zip(reversed(time), reversed(active)):
        if state:
            return t
    return -math.inf

def active_duration(time: list[float], active: list[bool]) -> float:
    if len(time) < 2:
        return 0.0
    return sum((time[index] - time[index - 1] for index in range(1, len(time)) if active[index] or active[index - 1]))

def trace_distance(left: list[list[float]], right: list[list[float]], columns_used: list[int]) -> float:
    if len(left) != len(right) or not left:
        return 0.0
    differences: list[float] = []
    scales: list[float] = []
    for index in columns_used:
        a = [float(row[index]) for row in left]
        b = [float(row[index]) for row in right]
        differences.extend((x - y for x, y in zip(a, b)))
        scales.extend(a)
    return rms(differences) / max(rms(scales), 1e-06)

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    time = list(map(float, outputs['time_s']))
    box = columns(outputs['box_state'])
    command = columns(outputs['command_state'])
    contact_in = columns(outputs['input_contact'])
    contact_out = columns(outputs['output_contact'])
    x, y, z, vx, vy, vz = box
    cin_fn = contact_in[2]
    cout_fn = contact_out[2]
    cin_sep = contact_in[0]
    cout_sep = contact_out[0]
    cin_vtx, cin_vty = (contact_in[3], contact_in[4])
    cout_vtx, cout_vty = (contact_out[3], contact_out[4])
    cin_ff, cin_ffx, cin_ffy = (contact_in[5], contact_in[6], contact_in[7])
    cout_ff, cout_ffx, cout_ffy = (contact_out[5], contact_out[6], contact_out[7])
    force_scale = max(max((abs(value) for value in cin_fn + cout_fn)), 1.0)
    threshold = max(0.25, 0.01 * force_scale)
    cin_active = [abs(value) >= threshold for value in cin_fn]
    cout_active = [abs(value) >= threshold for value in cout_fn]
    tail = [index for index, value in enumerate(time) if value >= 28.0]
    input_window = [index for index, value in enumerate(time) if value <= 10.0]
    transfer_window = [index for index, value in enumerate(time) if 7.0 <= value <= 25.0]
    output_window = [index for index, value in enumerate(time) if value >= 22.0]
    speed = [math.sqrt(vx[i] ** 2 + vy[i] ** 2 + vz[i] ** 2) for i in range(len(time))]
    lift_index = max(transfer_window, key=lambda index: z[index])
    force_active_indices = [index for index in range(len(time)) if cin_active[index] or cout_active[index]]
    support_values: list[bool] = []
    friction_vector_consistency: list[bool] = []
    friction_ratios: list[float] = []
    for sep, fn, active, vtx, vty, ff, ffx, ffy in zip(cin_sep + cout_sep, cin_fn + cout_fn, cin_active + cout_active, cin_vtx + cout_vtx, cin_vty + cout_vty, cin_ff + cout_ff, cin_ffx + cout_ffx, cin_ffy + cout_ffy):
        if not active:
            continue
        support_values.append(sep <= 0.005)
        friction_vector_consistency.append(math.hypot(ffx, ffy) <= 1.01 * abs(ff) + 1e-06)
        friction_ratios.append(abs(ff) / max(abs(fn), 1e-06))
    input_force_early = [cin_active[index] for index in input_window]
    output_force_late = [cout_active[index] for index in output_window]
    first_input = first_time(time, cin_active)
    first_output = first_time(time, cout_active)
    return {'x_span_m': max(x) - min(x), 'y_span_m': max(y) - min(y), 'z_span_m': max(z) - min(z), 'horizontal_path_m': sum((math.hypot(x[index] - x[index - 1], y[index] - y[index - 1]) for index in range(1, len(time)))), 'peak_height_m': z[lift_index], 'peak_height_time_s': time[lift_index], 'final_x_m': mean([x[index] for index in tail]), 'final_y_m': mean([y[index] for index in tail]), 'final_z_m': mean([z[index] for index in tail]), 'tail_speed_rms_mps': rms([speed[index] for index in tail]), 'peak_speed_mps': max(speed), 'input_contact_first_s': first_input, 'input_contact_last_s': last_time(time, cin_active), 'input_contact_duration_s': active_duration(time, cin_active), 'output_contact_first_s': first_output, 'output_contact_last_s': last_time(time, cout_active), 'output_contact_duration_s': active_duration(time, cout_active), 'input_contact_early_fraction': mean(input_force_early), 'output_contact_late_fraction': mean(output_force_late), 'input_normal_force_peak_N': max((abs(value) for value in cin_fn)), 'output_normal_force_peak_N': max((abs(value) for value in cout_fn)), 'maximum_penetration_m': max((max(-value, 0.0) for value in cin_sep + cout_sep)), 'normal_force_negative_fraction': mean([value < -threshold for value in cin_fn + cout_fn]), 'contact_force_support_fraction': mean(support_values) if support_values else 0.0, 'friction_resultant_consistency_fraction': mean(friction_vector_consistency) if friction_vector_consistency else 0.0, 'friction_to_normal_p99': sorted(friction_ratios)[min(len(friction_ratios) - 1, int(0.99 * len(friction_ratios)))] if friction_ratios else math.inf, 'gripper_translation_span': max(command[0]) - min(command[0]), 'gripper_rotation_span': max(command[1]) - min(command[1]), 'gripper_vertical_span': max(command[2]) - min(command[2]), 'gripper_post_rotation_span': max(command[3]) - min(command[3]), 'output_belt_command_peak_mps': max((abs(value) for value in command[4])), 'input_belt_command_peak_mps': max((abs(value) for value in command[5])), 'phase_order_valid': float(math.isfinite(first_input) and math.isfinite(first_output) and (first_input < time[lift_index] < first_output)), 'physical_contact_sample_count': float(len(force_active_indices))}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    required_outputs = {'time_s', 'box_state', 'command_state', 'input_contact', 'output_contact'}
    all_valid = all((name in rows and bool(rows[name].get('valid')) and (required_outputs <= set(rows[name].get('outputs', {}))) for name in REQUIRED))
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': all_valid, 'reference_unmodified': int(evidence.get('reference_substantive_modifications', -1)) == 0, 'physical_multistage_contact_path': bool(static.get('core_path_qualified'))}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['native_nominal_transfer']
    low_friction = metrics['moderate_low_belt_friction']
    high_friction = metrics['moderate_high_belt_friction']
    slow_belts = metrics['moderate_slow_belts']
    mismatch = metrics['belt_speed_mismatch']
    payload = metrics['heavier_payload_boundary']
    a_parts = {'orthogonal_horizontal_transfer': (min(high(nominal['x_span_m'], 0.18, 0.38), high(nominal['y_span_m'], 0.18, 0.38)), 0.25), 'physical_lift': (high(nominal['z_span_m'], 0.08, 0.2), 0.15), 'input_transport_contact': (high(nominal['input_contact_duration_s'], 0.25, 1.5), 0.15), 'output_transport_contact': (high(nominal['output_contact_duration_s'], 0.25, 1.5), 0.2), 'final_stability': (low(nominal['tail_speed_rms_mps'], 0.03, 0.25), 0.15), 'complete_commanded_mechanism': (min(high(nominal['gripper_translation_span'], 0.01, 0.05), high(nominal['gripper_vertical_span'], 0.02, 0.08), high(nominal['input_belt_command_peak_mps'], 0.03, 0.08), high(nominal['output_belt_command_peak_mps'], 0.03, 0.08)), 0.1)}
    group_a = weighted(a_parts)
    q_parts = {'bounded_penetration': (low(nominal['maximum_penetration_m'], 0.003, 0.02), 0.2), 'nonnegative_normal_force': (low(nominal['normal_force_negative_fraction'], 0.001, 0.1), 0.15), 'contact_only_force_support': (high(nominal['contact_force_support_fraction'], 0.8, 0.98), 0.2), 'friction_resultant_consistency': (high(nominal['friction_resultant_consistency_fraction'], 0.9, 0.99), 0.2), 'bounded_friction_ratio': (low(nominal['friction_to_normal_p99'], 0.85, 1.4), 0.1), 'bounded_payload_speed': (low(nominal['peak_speed_mps'], 0.8, 3.0), 0.15)}
    group_q = weighted(q_parts)
    nominal_outputs = rows['native_nominal_transfer']['outputs']
    low_outputs = rows['moderate_low_belt_friction']['outputs']
    high_outputs = rows['moderate_high_belt_friction']['outputs']
    slow_outputs = rows['moderate_slow_belts']['outputs']
    mismatch_outputs = rows['belt_speed_mismatch']['outputs']
    payload_outputs = rows['heavier_payload_boundary']['outputs']
    friction_response = max(trace_distance(nominal_outputs['box_state'], low_outputs['box_state'], [0, 1, 2]), trace_distance(nominal_outputs['input_contact'], low_outputs['input_contact'], [2, 5]), trace_distance(nominal_outputs['box_state'], high_outputs['box_state'], [0, 1, 2]))
    speed_response = max(trace_distance(nominal_outputs['box_state'], slow_outputs['box_state'], [0, 1, 2]), trace_distance(nominal_outputs['box_state'], mismatch_outputs['box_state'], [0, 1, 2]))
    payload_response = max(trace_distance(nominal_outputs['box_state'], payload_outputs['box_state'], [0, 1, 2]), trace_distance(nominal_outputs['input_contact'], payload_outputs['input_contact'], [2, 5]))
    m_parts = {'static_belt_contact_gripper_6dof_path': (1.0, 0.25), 'both_contact_interfaces_active': (min(high(nominal['input_contact_duration_s'], 0.1, 1.0), high(nominal['output_contact_duration_s'], 0.1, 1.0)), 0.15), 'active_gripper_commands': (min(high(nominal['gripper_translation_span'], 0.005, 0.03), high(nominal['gripper_vertical_span'], 0.01, 0.05)), 0.15), 'friction_parameter_causality': (high(friction_response, 0.003, 0.03), 0.15), 'belt_speed_causality': (high(speed_response, 0.003, 0.03), 0.15), 'payload_inertia_causality': (high(payload_response, 0.002, 0.02), 0.15)}
    group_m = weighted(m_parts)
    if min(m_parts['both_contact_interfaces_active'][0], m_parts['active_gripper_commands'][0], m_parts['friction_parameter_causality'][0], m_parts['belt_speed_causality'][0], m_parts['payload_inertia_causality'][0]) < 0.1:
        group_m = min(group_m, 0.4)
    r_by_scenario: dict[str, float] = {}
    d_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = weighted({'horizontal_transfer': (high(max(values['x_span_m'], values['y_span_m']), 0.25, 0.5), 0.2), 'orthogonal_motion': (min(high(values['x_span_m'], 0.12, 0.32), high(values['y_span_m'], 0.12, 0.32)), 0.2), 'lift': (high(values['z_span_m'], 0.05, 0.16), 0.15), 'two_interfaces': (min(high(values['input_contact_duration_s'], 0.1, 0.8), high(values['output_contact_duration_s'], 0.1, 0.8)), 0.2), 'bounded_penetration': (low(values['maximum_penetration_m'], 0.004, 0.025), 0.1), 'finite_final_state': (low(values['tail_speed_rms_mps'], 0.05, 0.35), 0.15)})
        d_by_scenario[name] = weighted({'ordered_pick_lift_release': (values['phase_order_valid'], 0.3), 'early_input_contact': (high(values['input_contact_early_fraction'], 0.01, 0.08), 0.15), 'mid_maneuver_lift': (high(values['z_span_m'], 0.05, 0.16), 0.2), 'late_output_contact': (high(values['output_contact_late_fraction'], 0.01, 0.08), 0.2), 'post_release_settling': (low(values['tail_speed_rms_mps'], 0.05, 0.35), 0.15)})
    group_r = min(r_by_scenario.values())
    group_d = min(d_by_scenario.values())
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D_by_scenario': d_by_scenario, 'derived': {'friction_response': friction_response, 'belt_speed_response': speed_response, 'payload_response': payload_response}}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xmech07-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['missing_free_6dof_or_contact_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('input_contact', None)
    cases['missing_required_output'] = score(missing_output)['score']
    constant_pose = copy.deepcopy(evidence)
    for row in constant_pose['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['box_state'] = [[0.0] * 6 for _ in range(count)]
    cases['constant_or_replayed_pose'] = score(constant_pose)['score']
    kinematic = copy.deepcopy(evidence)
    for row in kinematic['scenarios']:
        time = row['outputs']['time_s']
        command = row['outputs']['command_state']
        row['outputs']['box_state'] = [[float(command[index][0]), float(command[index][2]), 0.2 + 0.05 * float(command[index][1]), 0.0, 0.0, 0.0] for index in range(len(time))]
        row['outputs']['input_contact'] = [[0.1] + [0.0] * 7 for _ in time]
        row['outputs']['output_contact'] = [[0.1] + [0.0] * 7 for _ in time]
    cases['kinematic_pose_assignment'] = score(kinematic)['score']
    one_belt = copy.deepcopy(evidence)
    for row in one_belt['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['output_contact'] = [[0.1] + [0.0] * 7 for _ in range(count)]
    cases['one_belt_only'] = score(one_belt)['score']
    gripper_free = copy.deepcopy(evidence)
    for row in gripper_free['scenarios']:
        for sample in row['outputs']['command_state']:
            sample[0:4] = [0.0, 0.0, 0.0, 0.0]
    cases['gripper_free_transfer'] = score(gripper_free)['score']
    disconnected_friction = copy.deepcopy(evidence)
    nominal = next((row for row in disconnected_friction['scenarios'] if row['id'] == 'native_nominal_transfer'))['outputs']
    for row in disconnected_friction['scenarios']:
        if row['id'] in {'moderate_low_belt_friction', 'moderate_high_belt_friction'}:
            row['outputs'] = copy.deepcopy(nominal)
    cases['disconnected_friction_inputs'] = score(disconnected_friction)['score']
    disconnected_speed = copy.deepcopy(evidence)
    nominal = next((row for row in disconnected_speed['scenarios'] if row['id'] == 'native_nominal_transfer'))['outputs']
    for row in disconnected_speed['scenarios']:
        if row['id'] in {'moderate_slow_belts', 'belt_speed_mismatch'}:
            row['outputs'] = copy.deepcopy(nominal)
    cases['disconnected_belt_speed_inputs'] = score(disconnected_speed)['score']
    endpoint_only = copy.deepcopy(evidence)
    for row in endpoint_only['scenarios']:
        box = row['outputs']['box_state']
        count = len(box)
        start = box[0]
        finish = box[-1]
        row['outputs']['box_state'] = [[start[channel] + (finish[channel] - start[channel]) * index / max(count - 1, 1) for channel in range(6)] for index in range(count)]
        row['outputs']['input_contact'] = [[0.1] + [0.0] * 7 for _ in range(count)]
        row['outputs']['output_contact'] = [[0.1] + [0.0] * 7 for _ in range(count)]
    cases['endpoint_only_without_phase_transient'] = score(endpoint_only)['score']
    return {'schema': 'simuverity.f90-xmech07-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

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
