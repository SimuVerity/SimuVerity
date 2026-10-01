"""Pure-offline scorer for the XMECH-10 public contract current."""
from __future__ import annotations
import argparse
import importlib.util
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XMECH-10'
POLICY_ID = 'simuverity-101-v1:f90-xmech-10:scoring'
PUBLIC_CONTRACT_ID = 'f90-xmech10-public-contract'
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

def _load_policy_core():
    path = Path(__file__).with_name('f90_xmech10_diagnostic_scoring.py')
    spec = importlib.util.spec_from_file_location('f90_xmech10_diagnostic_scoring_dependency', path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'Cannot load XMECH-10 current scorer core: {path}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
SCORING_CORE = _load_policy_core()
REQUIRED = SCORING_CORE.REQUIRED

def _contract_identity(evidence: dict[str, Any]) -> Any:
    current = evidence.get('public_contract_id')
    if isinstance(current, str):
        return current
    compatible = [
        value
        for key, value in evidence.items()
        if key.startswith('public_contract_')
        and isinstance(value, str)
        and value.startswith(PUBLIC_CONTRACT_ID)
    ]
    return compatible[0] if len(compatible) == 1 else None


def _contract_matches(evidence: dict[str, Any]) -> bool:
    identity = _contract_identity(evidence)
    return identity == PUBLIC_CONTRACT_ID or (
        isinstance(identity, str) and identity.startswith(PUBLIC_CONTRACT_ID + '-')
    )

def _diagnostic_only(evidence: dict[str, Any]) -> dict[str, Any]:
    result = SCORING_CORE.score(evidence)
    result['public_contract_checks'] = {'expected_id': PUBLIC_CONTRACT_ID, 'identity_match': _contract_matches(evidence)}
    return result

def _same_unit_distance(changed: list[list[float]], nominal: list[list[float]], width: int) -> float:
    return SCORING_CORE._per_channel_distance(changed, nominal, range(width))

def _split_distance(changed: list[list[float]], nominal: list[list[float]], primary_width: int) -> float:
    groups = SCORING_CORE.grouped_trace_distance(changed, nominal, primary_width)
    return max(groups.values())

def _first_onset(time: list[float], values: list[float], threshold: float) -> float:
    for stamp, value in zip(time, values):
        if value > threshold:
            return stamp
    return math.inf

def _band(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    return min(SCORING_CORE.high(value, low_zero, low_full), SCORING_CORE.low(value, high_full, high_zero))

def _world_frame_metrics(row: dict[str, Any]) -> dict[str, float]:
    metrics = dict(SCORING_CORE.row_metrics(row))
    outputs = row['outputs']
    time = [float(value) for value in outputs['time_s']]
    command = [[float(value) for value in sample] for sample in outputs['joint_command']]
    position = [[float(value) for value in sample] for sample in outputs['joint_position']]
    pose = SCORING_CORE._payload_pose(outputs)
    sensor = [[float(value) for value in sample] for sample in outputs['sensor_state']]
    initial_count = min(len(pose), max(2, len(time) // 50))
    initial = [sum((sample[axis] for sample in pose[:initial_count])) / initial_count for axis in range(3)]
    command_ranges = [max(SCORING_CORE.column(command, axis)) - min(SCORING_CORE.column(command, axis)) for axis in range(7)]
    position_ranges = [max(SCORING_CORE.column(position, axis)) - min(SCORING_CORE.column(position, axis)) for axis in range(7)]
    horizontal = [math.hypot(sample[0] - initial[0], sample[1] - initial[1]) for sample in pose]
    lift = [sample[2] - initial[2] for sample in pose]
    steps = [math.sqrt(sum(((pose[index][axis] - pose[index - 1][axis]) ** 2 for axis in range(3)))) for index in range(1, len(pose))]
    metrics.update({'active_command_axes': float(sum((command_ranges[axis] > (0.05 if axis < 5 else 1.0) for axis in range(7)))), 'active_position_axes': float(sum((position_ranges[axis] > (0.04 if axis < 5 else 0.8) for axis in range(7)))), 'payload_horizontal_travel_m': max(horizontal), 'payload_lift_m': max(lift), 'payload_max_step_m': max(steps) if steps else 0.0, 'input_sensor_onset_s': _first_onset(time, SCORING_CORE.column(sensor, 0), 0.5), 'lift_onset_s': _first_onset(time, lift, 0.04), 'output_sensor_onset_s': _first_onset(time, SCORING_CORE.column(sensor, 2), 0.5), 'input_sensor_seen': float(max(SCORING_CORE.column(sensor, 0)) > 0.5)})
    return metrics

def _window_is_0_to_20(row: dict[str, Any]) -> bool:
    time = row.get('outputs', {}).get('time_s', [])
    return isinstance(time, list) and len(time) >= 2 and (abs(float(time[0])) <= 1e-09) and (abs(float(time[-1]) - 20.0) <= 1e-06)

def _formal_receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xmech10-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'score_eligible': True, 'public_contract_id': PUBLIC_CONTRACT_ID, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': float(total), 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    if not _contract_matches(evidence):
        return _diagnostic_only(evidence)
    base = SCORING_CORE.score(evidence)
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    window_ok = set(rows) == set(REQUIRED) and all((_window_is_0_to_20(rows[name]) for name in REQUIRED))
    qualification = dict(base['qualification_checks'])
    qualification.update({'public_contract_identity_match': True, 'evaluation_window_0_to_20_s': window_ok})
    gate = all(qualification.values())
    if not gate:
        groups = {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}
        return _formal_receipt(evidence, groups, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: _world_frame_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_transfer']
    nominal_outputs = rows['nominal_transfer']['outputs']
    low_supply_outputs = rows['low_supply_boundary']['outputs']
    heavy_outputs = rows['heavy_payload_boundary']['outputs']
    friction_outputs = rows['high_friction_boundary']['outputs']
    slow_outputs = rows['slow_sequence_boundary']['outputs']
    a_parts = {'input_payload_detected': (nominal['input_sensor_seen'], 0.1), 'five_axis_and_gripper_motion': (min(SCORING_CORE.high(nominal['active_command_axes'], 4.0, 6.0), SCORING_CORE.high(nominal['active_position_axes'], 4.0, 6.0)), 0.15), 'payload_lifted_world_z': (SCORING_CORE.high(nominal['payload_lift_m'], 0.03, 0.12), 0.2), 'payload_transferred_world_xy': (SCORING_CORE.high(nominal['payload_horizontal_travel_m'], 0.18, 0.5), 0.25), 'output_payload_detected': (nominal['output_sensor_seen'], 0.15), 'public_release_behavior': (nominal['release_public_evidence'], 0.15)}
    q_parts = {'arm_joint_tracking': (SCORING_CORE.low(nominal['arm_tracking_rms_rad'], 0.04, 0.3), 0.3), 'finger_tracking': (SCORING_CORE.low(nominal['finger_tracking_rms_mm'], 1.0, 8.0), 0.15), 'finite_bounded_motor_current': (min(SCORING_CORE.high(nominal['motor_current_rms_A'], 0.02, 0.2), SCORING_CORE.low(nominal['motor_current_peak_A'], 40.0, 150.0)), 0.2), 'bounded_arm_torque': (min(SCORING_CORE.high(nominal['arm_torque_rms_Nm'], 0.02, 0.3), SCORING_CORE.low(nominal['arm_torque_peak_Nm'], 120.0, 400.0)), 0.075), 'bounded_finger_force': (min(SCORING_CORE.high(nominal['finger_force_rms_N'], 0.02, 0.3), SCORING_CORE.low(nominal['finger_force_peak_N'], 120.0, 400.0)), 0.075), 'continuous_payload_motion': (min(SCORING_CORE.low(nominal['payload_max_step_m'], 0.01, 0.1), SCORING_CORE.low(nominal['payload_peak_speed_mps_from_public_pose'], 2.0, 10.0)), 0.2)}
    supply_response = max(_same_unit_distance(low_supply_outputs['motor_current'], nominal_outputs['motor_current'], 7), _split_distance(low_supply_outputs['joint_position'], nominal_outputs['joint_position'], 5))
    payload_response = max(_split_distance(heavy_outputs['joint_effort'], nominal_outputs['joint_effort'], 5), _same_unit_distance(heavy_outputs['motor_current'], nominal_outputs['motor_current'], 7), _same_unit_distance(heavy_outputs['payload_pose'], nominal_outputs['payload_pose'], 3))
    friction_response = max(_same_unit_distance(friction_outputs['motor_current'], nominal_outputs['motor_current'], 7), _split_distance(friction_outputs['joint_position'], nominal_outputs['joint_position'], 5))
    sequence_response = max(_split_distance(slow_outputs['joint_command'], nominal_outputs['joint_command'], 5), _same_unit_distance(slow_outputs['sensor_state'], nominal_outputs['sensor_state'], 4), _same_unit_distance(slow_outputs['payload_pose'], nominal_outputs['payload_pose'], 3))
    m_parts = {'connected_port_graph_core': (1.0, 0.25), 'command_to_measured_joint_response': (min(SCORING_CORE.high(nominal['active_command_axes'], 4.0, 6.0), SCORING_CORE.high(nominal['active_position_axes'], 4.0, 6.0), SCORING_CORE.low(nominal['arm_tracking_rms_rad'], 0.06, 0.4)), 0.15), 'real_motor_current_and_separated_effort': (min(SCORING_CORE.high(nominal['nonzero_current_fraction'], 0.02, 0.2), SCORING_CORE.high(nominal['arm_torque_rms_Nm'], 0.02, 0.3), SCORING_CORE.high(nominal['finger_force_rms_N'], 0.02, 0.3)), 0.15), 'supply_voltage_causality': (SCORING_CORE.high(supply_response, 5e-05, 0.0005), 0.12), 'payload_mass_causality': (SCORING_CORE.high(payload_response, 0.0001, 0.001), 0.12), 'joint_friction_causality': (SCORING_CORE.high(friction_response, 0.002, 0.03), 0.11), 'sequence_delay_causality': (SCORING_CORE.high(sequence_response, 0.003, 0.03), 0.1)}
    critical_mechanism = min((value for value, _ in list(m_parts.values())[1:]))
    r_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = SCORING_CORE.weighted({'all_evidence_finite': (values['all_values_finite'], 0.1), 'multi_axis_closed_loop_motion': (min(SCORING_CORE.high(values['active_position_axes'], 4.0, 6.0), SCORING_CORE.low(values['arm_tracking_rms_rad'], 0.08, 0.45)), 0.2), 'pickup_and_lift': (min(values['input_sensor_seen'], SCORING_CORE.high(values['payload_lift_m'], 0.03, 0.1)), 0.2), 'physical_transfer': (SCORING_CORE.high(values['payload_horizontal_travel_m'], 0.18, 0.48), 0.25), 'release_and_output': (values['release_public_evidence'], 0.15), 'bounded_electromechanical_effort': (min(SCORING_CORE.low(values['motor_current_peak_A'], 50.0, 180.0), SCORING_CORE.low(values['arm_torque_peak_Nm'], 150.0, 450.0), SCORING_CORE.low(values['finger_force_peak_N'], 150.0, 450.0)), 0.1)})
    group_r = min(r_by_scenario.values())
    ordered = nominal['input_sensor_onset_s'] < nominal['lift_onset_s'] < nominal['output_sensor_onset_s']
    d_parts = {'ordered_input_lift_output_sequence': (float(ordered), 0.25), 'noninstantaneous_sensor_to_lift_delay': (_band(nominal['lift_onset_s'] - nominal['input_sensor_onset_s'], 0.0, 0.15, 10.0, 18.0) if math.isfinite(nominal['lift_onset_s']) and math.isfinite(nominal['input_sensor_onset_s']) else 0.0, 0.15), 'noninstantaneous_transfer_delay': (_band(nominal['output_sensor_onset_s'] - nominal['lift_onset_s'], 0.0, 0.2, 12.0, 19.0) if math.isfinite(nominal['output_sensor_onset_s']) and math.isfinite(nominal['lift_onset_s']) else 0.0, 0.15), 'continuous_contact_supported_payload_motion': (min(SCORING_CORE.low(nominal['payload_max_step_m'], 0.01, 0.1), SCORING_CORE.high(nominal['payload_lift_m'], 0.03, 0.12), SCORING_CORE.high(nominal['payload_horizontal_travel_m'], 0.18, 0.5)), 0.2), 'public_release_continuity': (nominal['release_public_evidence'], 0.15), 'dynamic_scenario_response': (min(SCORING_CORE.high(supply_response, 5e-05, 0.0005), SCORING_CORE.high(payload_response, 0.0001, 0.001), SCORING_CORE.high(friction_response, 0.002, 0.03), SCORING_CORE.high(sequence_response, 0.003, 0.03)), 0.1)}
    groups = {'G': 1.0, 'A': SCORING_CORE.weighted(a_parts), 'Q': SCORING_CORE.weighted(q_parts), 'M': SCORING_CORE.weighted(m_parts), 'R': group_r, 'D': SCORING_CORE.weighted(d_parts)}
    total = 100.0
    for name, weight in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** weight
    shortcut_findings: list[dict[str, Any]] = []
    if groups['A'] < 0.5:
        shortcut_findings.append({'reason': 'nominal_transfer_not_completed', 'group': 'A'})
    if min(a_parts['output_payload_detected'][0], a_parts['public_release_behavior'][0]) < 0.1:
        shortcut_findings.append({'reason': 'output_detection_or_release_chain_missing', 'group': 'A'})
    if critical_mechanism < 0.1:
        shortcut_findings.append({'reason': 'missing_required_physical_causality', 'group': 'M'})
    if d_parts['continuous_contact_supported_payload_motion'][0] < 0.1:
        shortcut_findings.append({'reason': 'payload_transfer_not_physically_continuous', 'group': 'D'})
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D': d_parts, 'derived_causality': {'supply_response': supply_response, 'payload_response': payload_response, 'friction_response': friction_response, 'sequence_response': sequence_response, 'critical_mechanism_minimum': critical_mechanism}, 'shortcut_findings': shortcut_findings, 'semantic_fixes': {'belt_command': 'not_used_not_public', 'joint_effort': 'arm_torque_Nm_and_finger_force_N_scored_separately', 'joint_position_and_command': 'arm_rad_and_finger_mm_compared_separately', 'structure': 'true_port_graph'}}
    return _formal_receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score(evidence)
    rendered = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(rendered + '\n', encoding='utf-8')
    print(rendered)
if __name__ == '__main__':
    main()
