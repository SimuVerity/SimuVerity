"""Dedicated offline scorer for F90-XMECH-10."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XMECH-10'
POLICY_ID = 'simuverity-101-v1:f90-xmech-10:scoring'
REQUIRED = ('nominal_transfer', 'low_supply_boundary', 'heavy_payload_boundary', 'high_friction_boundary', 'slow_sequence_boundary')
OUTPUT_WIDTHS = {'joint_command': 7, 'joint_position': 7, 'motor_current': 7, 'joint_effort': 7, 'joint_constraint': 21, 'payload_state': 6, 'sensor_state': 4, 'belt_command': 2}
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

def clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def low(value: float, full: float, zero: float) -> float:
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clip((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clip((value - zero) / (full - zero))

def band(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    return min(high(value, low_zero, low_full), low(value, high_full, high_zero))

def weighted(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    return sum((score * weight for score, weight in parts.values())) / denominator

def rms(values: list[float]) -> float:
    if not values:
        return 0.0
    return math.sqrt(sum((value * value for value in values)) / len(values))

def column(matrix: list[list[float]], index: int) -> list[float]:
    return [float(row[index]) for row in matrix]

def vector_norm_rows(matrix: list[list[float]], indexes: list[int]) -> list[float]:
    return [math.sqrt(sum((float(row[index]) ** 2 for index in indexes))) for row in matrix]

def first_onset(time: list[float], values: list[float], threshold: float=0.5) -> float:
    for timestamp, value in zip(time, values):
        if value > threshold:
            return float(timestamp)
    return math.inf

def trace_distance(a: list[list[float]], b: list[list[float]], indexes: list[int]) -> float:
    if len(a) != len(b) or not a:
        return math.inf
    numerator = 0.0
    denominator = 0.0
    count = 0
    for left, right in zip(a, b):
        for index in indexes:
            lv = float(left[index])
            rv = float(right[index])
            numerator += (lv - rv) ** 2
            denominator += max(lv * lv, rv * rv)
            count += 1
    return math.sqrt(numerator / max(count, 1)) / max(math.sqrt(denominator / max(count, 1)), 1e-09)

def relative_change(value: float, baseline: float, floor: float=1e-09) -> float:
    return abs(value - baseline) / max(abs(baseline), floor)

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    time = [float(value) for value in outputs['time_s']]
    command = outputs['joint_command']
    position = outputs['joint_position']
    current = outputs['motor_current']
    effort = outputs['joint_effort']
    constraint = outputs['joint_constraint']
    payload = outputs['payload_state']
    sensor = outputs['sensor_state']
    belt = outputs['belt_command']
    command_ranges = [max(column(command, index)) - min(column(command, index)) for index in range(7)]
    position_ranges = [max(column(position, index)) - min(column(position, index)) for index in range(7)]
    arm_errors = [float(command[k][index]) - float(position[k][index]) for k in range(len(time)) for index in range(5)]
    finger_errors = [float(command[k][index]) - float(position[k][index]) for k in range(len(time)) for index in range(5, 7)]
    current_flat = [float(value) for sample in current for value in sample]
    effort_flat = [float(value) for sample in effort for value in sample]
    constraint_flat = [float(value) for sample in constraint for value in sample]
    payload_xyz = [[float(value) for value in sample[:3]] for sample in payload]
    payload_speed = vector_norm_rows(payload, [3, 4, 5])
    initial = [sum((sample[index] for sample in payload_xyz[:max(2, len(time) // 50)])) / max(2, len(time) // 50) for index in range(3)]
    final = [sum((sample[index] for sample in payload_xyz[-max(2, len(time) // 50):])) / max(2, len(time) // 50) for index in range(3)]
    horizontal_from_initial = [math.hypot(sample[0] - initial[0], sample[1] - initial[1]) for sample in payload_xyz]
    payload_step = [math.sqrt(sum(((payload_xyz[k][axis] - payload_xyz[k - 1][axis]) ** 2 for axis in range(3)))) for k in range(1, len(payload_xyz))]
    lifted = [sample[2] - initial[2] for sample in payload_xyz]
    input_sensor = [float(sample[0]) for sample in sensor]
    output_sensor = [float(sample[2]) for sample in sensor]
    input_onset = first_onset(time, input_sensor)
    output_onset = first_onset(time, output_sensor)
    lift_onset = first_onset(time, lifted, 0.04)
    output_belt_onset = first_onset(time, column(belt, 1))
    tail_start = int(0.85 * len(time))
    after_output_index = next((k for k, stamp in enumerate(time) if stamp >= output_onset), len(time) - 1) if math.isfinite(output_onset) else len(time) - 1
    after_output = payload_xyz[after_output_index:]
    post_output_motion = 0.0
    if len(after_output) >= 2:
        post_output_motion = math.sqrt(sum(((after_output[-1][axis] - after_output[0][axis]) ** 2 for axis in range(3))))
    all_values = [float(value) for name in OUTPUT_WIDTHS for sample in outputs[name] for value in sample]
    return {'duration_s': time[-1] - time[0], 'active_command_axes': float(sum((command_ranges[index] > (0.05 if index < 5 else 1.0) for index in range(7)))), 'active_position_axes': float(sum((position_ranges[index] > (0.04 if index < 5 else 0.8) for index in range(7)))), 'worst_arm_command_range_rad': max(command_ranges[:5]), 'arm_tracking_rms_rad': rms(arm_errors), 'arm_tracking_peak_rad': max((abs(value) for value in arm_errors)), 'finger_tracking_rms_mm': rms(finger_errors), 'motor_current_rms_A': rms(current_flat), 'motor_current_peak_A': max((abs(value) for value in current_flat)), 'nonzero_current_fraction': sum((abs(value) > 0.0001 for value in current_flat)) / len(current_flat), 'joint_effort_rms': rms(effort_flat), 'joint_effort_peak': max((abs(value) for value in effort_flat)), 'constraint_effort_rms': rms(constraint_flat), 'payload_horizontal_travel_m': max(horizontal_from_initial), 'payload_lift_m': max(lifted), 'payload_final_displacement_m': math.sqrt(sum(((final[axis] - initial[axis]) ** 2 for axis in range(3)))), 'payload_peak_speed_mps': max(payload_speed), 'payload_max_step_m': max(payload_step) if payload_step else 0.0, 'payload_tail_speed_rms_mps': rms(payload_speed[tail_start:]), 'input_sensor_onset_s': input_onset, 'lift_onset_s': lift_onset, 'output_sensor_onset_s': output_onset, 'output_belt_onset_s': output_belt_onset, 'input_sensor_seen': float(max(input_sensor) > 0.5), 'output_sensor_seen': float(max(output_sensor) > 0.5), 'output_belt_active': float(max(column(belt, 1)) > 0.5), 'post_output_payload_motion_m': post_output_motion, 'all_values_finite': float(all((math.isfinite(value) for value in all_values)))}

def validate_evidence(evidence: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    exact = set(rows) == set(REQUIRED)
    all_valid = exact
    if all_valid:
        for name in REQUIRED:
            row = rows[name]
            outputs = row.get('outputs', {})
            all_valid = bool(row.get('valid'))
            if not all_valid:
                break
            for output_name, width in OUTPUT_WIDTHS.items():
                matrix = outputs.get(output_name)
                all_valid = isinstance(matrix, list) and len(matrix) >= 2 and all((isinstance(sample, list) and len(sample) == width for sample in matrix))
                if not all_valid:
                    break
            if not all_valid:
                break
    static = evidence.get('static_audit', {})
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'exact_scenario_set': exact, 'all_scenarios_and_outputs_valid': all_valid, 'reference_unmodified': int(evidence.get('reference_substantive_modifications', -1)) == 0, 'physical_electromechanical_contact_core': bool(static.get('core_path_qualified'))}
    return (rows, qualification)

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows, qualification = validate_evidence(evidence)
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_transfer']
    low_supply = metrics['low_supply_boundary']
    heavy = metrics['heavy_payload_boundary']
    friction = metrics['high_friction_boundary']
    slow_sequence = metrics['slow_sequence_boundary']
    a_parts = {'input_payload_detected': (nominal['input_sensor_seen'], 0.1), 'five_axis_and_gripper_motion': (min(high(nominal['active_command_axes'], 4.0, 6.0), high(nominal['active_position_axes'], 4.0, 6.0)), 0.15), 'payload_lifted': (high(nominal['payload_lift_m'], 0.03, 0.12), 0.2), 'payload_transferred': (high(nominal['payload_horizontal_travel_m'], 0.18, 0.5), 0.25), 'output_payload_detected': (nominal['output_sensor_seen'], 0.15), 'released_payload_conveyed': (min(nominal['output_belt_active'], high(nominal['post_output_payload_motion_m'], 0.01, 0.12)), 0.15)}
    group_a = weighted(a_parts)
    q_parts = {'arm_joint_tracking': (low(nominal['arm_tracking_rms_rad'], 0.04, 0.3), 0.3), 'finger_tracking': (low(nominal['finger_tracking_rms_mm'], 1.0, 8.0), 0.15), 'finite_bounded_motor_current': (min(high(nominal['motor_current_rms_A'], 0.02, 0.2), low(nominal['motor_current_peak_A'], 40.0, 150.0)), 0.2), 'finite_bounded_joint_effort': (min(high(nominal['joint_effort_rms'], 0.02, 0.3), low(nominal['joint_effort_peak'], 120.0, 400.0)), 0.15), 'continuous_payload_motion': (min(low(nominal['payload_max_step_m'], 0.01, 0.1), low(nominal['payload_peak_speed_mps'], 2.0, 10.0)), 0.2)}
    group_q = weighted(q_parts)
    nominal_outputs = rows['nominal_transfer']['outputs']
    low_supply_outputs = rows['low_supply_boundary']['outputs']
    heavy_outputs = rows['heavy_payload_boundary']['outputs']
    friction_outputs = rows['high_friction_boundary']['outputs']
    slow_sequence_outputs = rows['slow_sequence_boundary']['outputs']
    supply_response = max(trace_distance(low_supply_outputs['motor_current'], nominal_outputs['motor_current'], list(range(7))), trace_distance(low_supply_outputs['joint_position'], nominal_outputs['joint_position'], list(range(7))))
    payload_response = max(trace_distance(heavy_outputs['joint_effort'], nominal_outputs['joint_effort'], list(range(7))), trace_distance(heavy_outputs['motor_current'], nominal_outputs['motor_current'], list(range(7))), trace_distance(heavy_outputs['payload_state'], nominal_outputs['payload_state'], list(range(6))))
    friction_response = max(trace_distance(friction_outputs['motor_current'], nominal_outputs['motor_current'], list(range(7))), trace_distance(friction_outputs['joint_position'], nominal_outputs['joint_position'], list(range(7))))
    sequence_response = max(trace_distance(slow_sequence_outputs['joint_command'], nominal_outputs['joint_command'], list(range(7))), trace_distance(slow_sequence_outputs['sensor_state'], nominal_outputs['sensor_state'], list(range(4))), trace_distance(slow_sequence_outputs['payload_state'], nominal_outputs['payload_state'], list(range(6))))
    m_parts = {'static_electrical_motor_gear_feedback_contact_path': (1.0, 0.25), 'command_to_measured_joint_response': (min(high(nominal['active_command_axes'], 4.0, 6.0), high(nominal['active_position_axes'], 4.0, 6.0), low(nominal['arm_tracking_rms_rad'], 0.06, 0.4)), 0.15), 'real_motor_current_and_effort': (min(high(nominal['nonzero_current_fraction'], 0.02, 0.2), high(nominal['motor_current_rms_A'], 0.02, 0.2), high(nominal['joint_effort_rms'], 0.02, 0.3)), 0.15), 'supply_voltage_causality': (high(supply_response, 5e-05, 0.0005), 0.12), 'payload_mass_causality': (high(payload_response, 0.0001, 0.001), 0.12), 'joint_friction_causality': (high(friction_response, 0.002, 0.03), 0.11), 'sequence_delay_causality': (high(sequence_response, 0.003, 0.03), 0.1)}
    group_m = weighted(m_parts)
    critical_mechanism = min(m_parts['command_to_measured_joint_response'][0], m_parts['real_motor_current_and_effort'][0], m_parts['supply_voltage_causality'][0], m_parts['payload_mass_causality'][0], m_parts['joint_friction_causality'][0], m_parts['sequence_delay_causality'][0])
    r_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = weighted({'all_evidence_finite': (values['all_values_finite'], 0.1), 'multi_axis_closed_loop_motion': (min(high(values['active_position_axes'], 4.0, 6.0), low(values['arm_tracking_rms_rad'], 0.08, 0.45)), 0.2), 'pickup_and_lift': (min(values['input_sensor_seen'], high(values['payload_lift_m'], 0.03, 0.1)), 0.2), 'physical_transfer': (high(values['payload_horizontal_travel_m'], 0.18, 0.48), 0.25), 'release_and_output': (min(values['output_sensor_seen'], values['output_belt_active'], high(values['post_output_payload_motion_m'], 0.005, 0.1)), 0.15), 'bounded_electromechanical_effort': (min(low(values['motor_current_peak_A'], 50.0, 180.0), low(values['joint_effort_peak'], 150.0, 450.0)), 0.1)})
    group_r = min(r_by_scenario.values())
    ordered = nominal['input_sensor_onset_s'] < nominal['lift_onset_s'] < nominal['output_sensor_onset_s']
    d_parts = {'ordered_input_lift_output_sequence': (float(ordered), 0.25), 'noninstantaneous_sensor_to_lift_delay': (band(nominal['lift_onset_s'] - nominal['input_sensor_onset_s'], 0.0, 0.15, 10.0, 18.0) if math.isfinite(nominal['lift_onset_s']) and math.isfinite(nominal['input_sensor_onset_s']) else 0.0, 0.15), 'noninstantaneous_transfer_delay': (band(nominal['output_sensor_onset_s'] - nominal['lift_onset_s'], 0.0, 0.2, 12.0, 19.0) if math.isfinite(nominal['output_sensor_onset_s']) and math.isfinite(nominal['lift_onset_s']) else 0.0, 0.15), 'continuous_contact_supported_payload_motion': (min(low(nominal['payload_max_step_m'], 0.01, 0.1), high(nominal['payload_lift_m'], 0.03, 0.12), high(nominal['payload_horizontal_travel_m'], 0.18, 0.5)), 0.2), 'output_belt_release_continuity': (min(nominal['output_belt_active'], high(nominal['post_output_payload_motion_m'], 0.01, 0.12)), 0.15), 'dynamic_scenario_response': (min(high(supply_response, 5e-05, 0.0005), high(payload_response, 0.0001, 0.001), high(friction_response, 0.002, 0.03), high(sequence_response, 0.003, 0.03)), 0.1)}
    group_d = weighted(d_parts)
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0
    for name, weight in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** weight
    shortcut_findings: list[dict[str, Any]] = []
    if group_a < 0.5:
        shortcut_findings.append({'reason': 'nominal_transfer_not_completed', 'group': 'A'})
    output_release_chain = min(a_parts['output_payload_detected'][0], a_parts['released_payload_conveyed'][0])
    if output_release_chain < 0.1:
        shortcut_findings.append({'reason': 'output_detection_or_release_chain_missing', 'group': 'A'})
    if critical_mechanism < 0.1:
        shortcut_findings.append({'reason': 'missing_required_physical_causality', 'group': 'M'})
    if d_parts['continuous_contact_supported_payload_motion'][0] < 0.1:
        shortcut_findings.append({'reason': 'payload_transfer_not_physically_continuous', 'group': 'D'})
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D': d_parts, 'derived_causality': {'supply_response': supply_response, 'payload_response': payload_response, 'friction_response': friction_response, 'sequence_response': sequence_response, 'critical_mechanism_minimum': critical_mechanism}, 'shortcut_findings': shortcut_findings}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xmech10-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'preferred_reference_score': 90.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['prescribed_motion_or_missing_electromechanical_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('motor_current', None)
    cases['missing_required_output'] = score(missing_output)['score']
    constant_state = copy.deepcopy(evidence)
    for row in constant_state['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['joint_position'] = [[0.0] * 7 for _ in range(count)]
    cases['constant_joint_state'] = score(constant_state)['score']
    no_current = copy.deepcopy(evidence)
    for row in no_current['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['motor_current'] = [[0.0] * 7 for _ in range(count)]
        row['outputs']['joint_effort'] = [[0.0] * 7 for _ in range(count)]
    cases['reported_motion_without_motor_effort'] = score(no_current)['score']
    disconnected_inputs = copy.deepcopy(evidence)
    nominal = next((row for row in disconnected_inputs['scenarios'] if row['id'] == 'nominal_transfer'))['outputs']
    for row in disconnected_inputs['scenarios']:
        row['outputs'] = copy.deepcopy(nominal)
    cases['workspace_inputs_ignored'] = score(disconnected_inputs)['score']
    teleported_payload = copy.deepcopy(evidence)
    for row in teleported_payload['scenarios']:
        payload = row['outputs']['payload_state']
        start = payload[0][:]
        end = payload[-1][:]
        split = len(payload) // 2
        row['outputs']['payload_state'] = [start[:] if k < split else end[:] for k in range(len(payload))]
    cases['teleported_payload'] = score(teleported_payload)['score']
    no_sensors = copy.deepcopy(evidence)
    for row in no_sensors['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['sensor_state'] = [[0.0] * 4 for _ in range(count)]
    cases['declared_transfer_without_sensor_sequence'] = score(no_sensors)['score']
    no_release = copy.deepcopy(evidence)
    for row in no_release['scenarios']:
        for sample in row['outputs']['sensor_state']:
            sample[2] = 0.0
            sample[3] = 0.0
        for sample in row['outputs']['belt_command']:
            sample[1] = 0.0
    cases['pickup_without_output_release'] = score(no_release)['score']
    copied_commands = copy.deepcopy(evidence)
    for row in copied_commands['scenarios']:
        row['outputs']['joint_position'] = copy.deepcopy(row['outputs']['joint_command'])
        count = len(row['outputs']['time_s'])
        row['outputs']['motor_current'] = [[0.0] * 7 for _ in range(count)]
        row['outputs']['joint_effort'] = [[0.0] * 7 for _ in range(count)]
    cases['copied_command_as_measurement'] = score(copied_commands)['score']
    return {'schema': 'simuverity.f90-xmech10-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

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
