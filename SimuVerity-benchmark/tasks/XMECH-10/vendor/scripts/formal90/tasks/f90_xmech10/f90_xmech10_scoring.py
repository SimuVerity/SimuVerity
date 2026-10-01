"""file binding-scoped partial-output scorer with strict cross-group geometry."""
from __future__ import annotations
import argparse
import importlib.util
import json
import math
from pathlib import Path
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
GROUP_SCORING_PATH = TASK_DIR / 'f90_xmech10_public_contract_scoring.py'
METRICS_PATH = TASK_DIR / 'f90_xmech10_scoring_core.py'
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}
REQUIRED = ('nominal_transfer', 'low_supply_boundary', 'heavy_payload_boundary', 'high_friction_boundary', 'slow_sequence_boundary')

def _load_policy_core():
    spec = importlib.util.spec_from_file_location('xmech10_current_current', GROUP_SCORING_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load XMECH-10 current scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
GROUP_SCORING = _load_policy_core()

def _load_policy_core():
    spec = importlib.util.spec_from_file_location('xmech10_current_reference_current', METRICS_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load XMECH-10 native reference scorer core')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
METRICS = _load_policy_core()

def _clip(value: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return min(1.0, max(0.0, value))

def _high(value: float, zero: float, full: float) -> float:
    return _clip((value - zero) / (full - zero))

def _geometric(groups: dict[str, float]) -> float:
    if any((not math.isfinite(groups[name]) or groups[name] <= 0.0 for name in WEIGHTS)):
        return 0.0
    return 100.0 * math.exp(sum((WEIGHTS[n] * math.log(groups[n]) for n in WEIGHTS)))

def _json_safe(value: Any) -> Any:
    if isinstance(value, float) and (not math.isfinite(value)):
        return None
    if isinstance(value, dict):
        return {name: _json_safe(item) for name, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    return value

def _distance(changed: list[list[float]], nominal: list[list[float]]) -> float:
    if not changed or len(changed) != len(nominal):
        return 0.0
    width = min(len(changed[0]), len(nominal[0]))
    if width <= 0:
        return 0.0
    delta = 0.0
    scale = 0.0
    count = 0
    for left, right in zip(changed, nominal):
        for index in range(width):
            delta += (float(left[index]) - float(right[index])) ** 2
            scale += float(right[index]) ** 2
            count += 1
    return math.sqrt(delta / max(count, 1)) / max(math.sqrt(scale / max(count, 1)), 1e-09)

def _matrix(row: dict[str, Any], name: str, width: int) -> list[list[float]]:
    outputs = row.get('outputs', {})
    time = outputs.get('time_s')
    value = outputs.get(name)
    if not isinstance(time, list) or not isinstance(value, list) or len(value) != len(time):
        return []
    if not value or any((not isinstance(sample, list) or len(sample) != width for sample in value)):
        return []
    try:
        result = [[float(item) for item in sample] for sample in value]
    except (TypeError, ValueError):
        return []
    if not all((math.isfinite(item) for sample in result for item in sample)):
        return []
    return result

def _column(matrix: list[list[float]], index: int) -> list[float]:
    return [sample[index] for sample in matrix]

def _rms(values: list[float]) -> float:
    return math.sqrt(sum((value * value for value in values)) / len(values)) if values else 0.0

def _partial_metrics(row: dict[str, Any]) -> dict[str, Any]:
    outputs = row.get('outputs', {})
    time_raw = outputs.get('time_s', [])
    time = [float(value) for value in time_raw] if isinstance(time_raw, list) else []
    matrices = {'joint_command': _matrix(row, 'joint_command', 7), 'joint_position': _matrix(row, 'joint_position', 7), 'motor_current': _matrix(row, 'motor_current', 7), 'joint_effort': _matrix(row, 'joint_effort', 7), 'payload_pose': _matrix(row, 'payload_pose', 3), 'sensor_state': _matrix(row, 'sensor_state', 4)}
    available = {name: bool(value) for name, value in matrices.items()}
    result: dict[str, Any] = {'available': available, 'available_fraction': sum(available.values()) / len(available), 'time_complete': float(len(time) >= 2 and abs(time[0]) <= 1e-09 and (abs(time[-1] - 20.0) <= 1e-06) and all((math.isfinite(value) for value in time)) and all((right > left for left, right in zip(time, time[1:])))), 'all_available_values_finite': float(all((math.isfinite(value) for matrix in matrices.values() for sample in matrix for value in sample)))}
    for name in ('joint_command', 'joint_position'):
        matrix = matrices[name]
        ranges = [max(_column(matrix, axis)) - min(_column(matrix, axis)) for axis in range(7)] if matrix else [0.0] * 7
        result[f'{name}_active_axes'] = float(sum((ranges[axis] > (0.05 if name == 'joint_command' and axis < 5 else 1.0 if name == 'joint_command' else 0.04 if axis < 5 else 0.8) for axis in range(7))))
    command = matrices['joint_command']
    position = matrices['joint_position']
    if command and position:
        result['arm_tracking_rms_rad'] = _rms([command[index][axis] - position[index][axis] for index in range(len(time)) for axis in range(5)])
        result['finger_tracking_rms_mm'] = _rms([command[index][axis] - position[index][axis] for index in range(len(time)) for axis in range(5, 7)])
    else:
        result['arm_tracking_rms_rad'] = math.inf
        result['finger_tracking_rms_mm'] = math.inf
    current = matrices['motor_current']
    current_values = [value for sample in current for value in sample]
    result['motor_current_rms_A'] = _rms(current_values)
    result['motor_current_peak_A'] = max(map(abs, current_values), default=math.inf)
    result['nonzero_current_fraction'] = sum((abs(value) > 0.0001 for value in current_values)) / len(current_values) if current_values else 0.0
    effort = matrices['joint_effort']
    arm_effort = [sample[axis] for sample in effort for axis in range(5)]
    finger_effort = [sample[axis] for sample in effort for axis in range(5, 7)]
    result.update({'arm_torque_rms_Nm': _rms(arm_effort), 'arm_torque_peak_Nm': max(map(abs, arm_effort), default=math.inf), 'finger_force_rms_N': _rms(finger_effort), 'finger_force_peak_N': max(map(abs, finger_effort), default=math.inf)})
    pose = matrices['payload_pose']
    sensor = matrices['sensor_state']
    result.update({'payload_lift_m': 0.0, 'payload_horizontal_travel_m': 0.0, 'payload_max_step_m': math.inf, 'payload_peak_speed_mps': math.inf, 'input_sensor_seen': 0.0, 'output_sensor_seen': 0.0, 'input_sensor_onset_s': math.inf, 'lift_onset_s': math.inf, 'output_sensor_onset_s': math.inf, 'release_public_evidence': 0.0})
    if pose:
        initial_count = min(len(pose), max(2, len(pose) // 50))
        initial = [sum((sample[axis] for sample in pose[:initial_count])) / initial_count for axis in range(3)]
        horizontal = [math.hypot(sample[0] - initial[0], sample[1] - initial[1]) for sample in pose]
        lift = [sample[2] - initial[2] for sample in pose]
        steps = [math.sqrt(sum(((pose[index][axis] - pose[index - 1][axis]) ** 2 for axis in range(3)))) for index in range(1, len(pose))]
        speeds = [steps[index] / (time[index + 1] - time[index]) for index in range(len(steps))]
        result.update({'payload_lift_m': max(lift), 'payload_horizontal_travel_m': max(horizontal), 'payload_max_step_m': max(steps, default=0.0), 'payload_peak_speed_mps': max(speeds, default=0.0), 'lift_onset_s': next((stamp for stamp, value in zip(time, lift) if value > 0.04), math.inf)})
    if sensor:
        input_sensor = _column(sensor, 0)
        output_sensor = _column(sensor, 2)
        result.update({'input_sensor_seen': float(max(input_sensor) > 0.5), 'output_sensor_seen': float(max(output_sensor) > 0.5), 'input_sensor_onset_s': next((stamp for stamp, value in zip(time, input_sensor) if value > 0.5), math.inf), 'output_sensor_onset_s': next((stamp for stamp, value in zip(time, output_sensor) if value > 0.5), math.inf)})
    if pose and sensor and position and math.isfinite(result['output_sensor_onset_s']):
        output_index = next((index for index, stamp in enumerate(time) if stamp >= result['output_sensor_onset_s']), len(time) - 1)
        post_pose = pose[output_index:]
        post_motion = math.sqrt(sum(((post_pose[-1][axis] - post_pose[0][axis]) ** 2 for axis in range(3)))) if len(post_pose) >= 2 else 0.0
        finger_reopen = min((max(_column(position, axis)[output_index:]) - min(_column(position, axis)) for axis in range(5, 7)))
        result['release_public_evidence'] = min(result['output_sensor_seen'], _high(post_motion, 0.01, 0.12), _high(finger_reopen, 1.0, 10.0))
    return result

def _best_response(changed: dict[str, Any], nominal: dict[str, Any], candidates: tuple[str, ...]) -> float:
    widths = {'joint_command': 7, 'joint_position': 7, 'motor_current': 7, 'joint_effort': 7, 'payload_pose': 3, 'sensor_state': 4}
    distances = []
    for name in candidates:
        changed_matrix = _matrix(changed, name, widths[name])
        nominal_matrix = _matrix(nominal, name, widths[name])
        if changed_matrix and nominal_matrix:
            distances.append(_distance(changed_matrix, nominal_matrix))
    return max(distances, default=0.0)

def _strict_full(evidence: dict[str, Any]) -> dict[str, Any]:
    base = GROUP_SCORING.score(evidence)
    groups = {name: float(base.get('groups', {}).get(name, 0.0)) for name in WEIGHTS}
    diagnostics = base.get('diagnostics', {})
    a_parts = diagnostics.get('A', {})
    d_parts = diagnostics.get('D', {})
    critical = float(diagnostics.get('derived_causality', {}).get('critical_mechanism_minimum', 0.0))
    output_release = min(float(a_parts.get('output_payload_detected', [0.0])[0]), float(a_parts.get('public_release_behavior', [0.0])[0]))
    continuity = float(d_parts.get('continuous_contact_supported_payload_motion', [0.0])[0])
    if output_release < 0.1:
        groups['A'] = 0.0
    if critical < 0.1:
        groups['M'] = 0.0
    if continuity < 0.1:
        groups['D'] = 0.0
    total = _geometric(groups) if bool(base.get('G')) else 0.0
    return {**base, 'schema': 'simuverity.f90-xmech10-score.v1', 'policy_id': 'simuverity-101-v1:f90-xmech-10:scoring', 'groups': {'G': 1.0 if bool(base.get('G')) else 0.0, **groups}, 'score': total, 'total_score': total, 'post_total_cap_or_floor': False, 'dimension_owned_critical_checks': {'A.output_detection_and_release': output_release >= 0.1, 'M.required_physical_causality': critical >= 0.1, 'D.continuous_physical_payload_motion': continuity >= 0.1}}

def _strict_native_reference(evidence: dict[str, Any]) -> dict[str, Any]:
    """Score a freshly extracted native golden without relabeling its evidence."""
    base = METRICS.score(evidence)
    groups = {name: float(base.get('groups', {}).get(name, 0.0)) for name in WEIGHTS}
    diagnostics = base.get('diagnostics', {})
    a_parts = diagnostics.get('A', {})
    d_parts = diagnostics.get('D', {})
    critical = float(diagnostics.get('derived_causality', {}).get('critical_mechanism_minimum', 0.0))
    output_release = min(float(a_parts.get('output_payload_detected', [0.0])[0]), float(a_parts.get('released_payload_conveyed', [0.0])[0]))
    continuity = float(d_parts.get('continuous_contact_supported_payload_motion', [0.0])[0])
    if output_release < 0.1:
        groups['A'] = 0.0
    if critical < 0.1:
        groups['M'] = 0.0
    if continuity < 0.1:
        groups['D'] = 0.0
    total = _geometric(groups) if bool(base.get('G')) else 0.0
    return {**base, 'schema': 'simuverity.f90-xmech10-score.v1', 'policy_id': 'simuverity-101-v1:f90-xmech-10:scoring', 'reference_evidence_mode': 'fresh_native_reference_not_relabelled', 'groups': {'G': 1.0 if bool(base.get('G')) else 0.0, **groups}, 'score': total, 'total_score': total, 'post_total_cap_or_floor': False}

def _partial(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_simulations_and_partial_capture_complete': set(rows) == set(REQUIRED) and all((bool(rows[name].get('simulation_pass')) and bool(rows[name].get('partial_output_capture_complete')) and bool(rows[name].get('valid')) for name in REQUIRED))}
    gate = all(qualification.values())
    if not gate:
        groups = {'G': 0.0, **{name: 0.0 for name in WEIGHTS}}
        return {'schema': 'simuverity.f90-xmech10-score.v1', 'task_id': 'F90-XMECH-10', 'policy_id': 'simuverity-101-v1:f90-xmech-10:scoring', 'G': False, 'groups': groups, 'group_weights': WEIGHTS, 'score': 0.0, 'total_score': 0.0, 'qualification_checks': qualification, 'failure_reasons': [name for name, passed in qualification.items() if not passed], 'post_total_cap_or_floor': False}
    metrics = {name: _partial_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_transfer']
    responses = {'supply': _best_response(rows['low_supply_boundary'], rows['nominal_transfer'], ('motor_current', 'joint_position')), 'payload': _best_response(rows['heavy_payload_boundary'], rows['nominal_transfer'], ('joint_effort', 'motor_current', 'payload_pose')), 'friction': _best_response(rows['high_friction_boundary'], rows['nominal_transfer'], ('motor_current', 'joint_position')), 'sequence': _best_response(rows['slow_sequence_boundary'], rows['nominal_transfer'], ('joint_command', 'sensor_state', 'payload_pose'))}
    structure = GROUP_SCORING.SCORING_CORE.STRUCTURE.evaluate_structure_graph(evidence.get('static_audit', {}).get('port_graph', {}))
    command_motion = _high(nominal['joint_command_active_axes'], 3.0, 6.0)
    position_motion = _high(nominal['joint_position_active_axes'], 3.0, 6.0)
    a_parts = {'input_payload_detected': (nominal['input_sensor_seen'], 0.1), 'command_motion': (command_motion, 0.075), 'measured_joint_motion': (position_motion, 0.075), 'payload_lifted_world_z': (_high(nominal['payload_lift_m'], 0.03, 0.12), 0.2), 'payload_transferred_world_xy': (_high(nominal['payload_horizontal_travel_m'], 0.18, 0.5), 0.25), 'output_payload_detected': (nominal['output_sensor_seen'], 0.15), 'public_release_behavior': (nominal['release_public_evidence'], 0.15)}
    group_a = sum((value * weight for value, weight in a_parts.values()))
    position = _matrix(rows['nominal_transfer'], 'joint_position', 7)
    position_bounded = float(bool(position) and all((abs(sample[axis]) <= (4.0 * math.pi if axis < 5 else 200.0) for sample in position for axis in range(7))))
    q_parts = {'finite_full_window_public_trace_coverage': (nominal['available_fraction'] * nominal['time_complete'] * nominal['all_available_values_finite'], 0.1), 'bounded_joint_position': (position_bounded, 0.1), 'arm_joint_tracking': (GROUP_SCORING.SCORING_CORE.low(nominal['arm_tracking_rms_rad'], 0.04, 0.3) if nominal['available']['joint_command'] and nominal['available']['joint_position'] else 0.0, 0.24), 'finger_tracking': (GROUP_SCORING.SCORING_CORE.low(nominal['finger_tracking_rms_mm'], 1.0, 8.0) if nominal['available']['joint_command'] and nominal['available']['joint_position'] else 0.0, 0.12), 'finite_bounded_motor_current': (min(_high(nominal['motor_current_rms_A'], 0.02, 0.2), GROUP_SCORING.SCORING_CORE.low(nominal['motor_current_peak_A'], 40.0, 150.0)) if nominal['available']['motor_current'] else 0.0, 0.16), 'bounded_arm_torque': (min(_high(nominal['arm_torque_rms_Nm'], 0.02, 0.3), GROUP_SCORING.SCORING_CORE.low(nominal['arm_torque_peak_Nm'], 120.0, 400.0)) if nominal['available']['joint_effort'] else 0.0, 0.06), 'bounded_finger_force': (min(_high(nominal['finger_force_rms_N'], 0.02, 0.3), GROUP_SCORING.SCORING_CORE.low(nominal['finger_force_peak_N'], 120.0, 400.0)) if nominal['available']['joint_effort'] else 0.0, 0.06), 'continuous_payload_motion': (min(GROUP_SCORING.SCORING_CORE.low(nominal['payload_max_step_m'], 0.01, 0.1), GROUP_SCORING.SCORING_CORE.low(nominal['payload_peak_speed_mps'], 2.0, 10.0)) if nominal['available']['payload_pose'] else 0.0, 0.16)}
    group_q = sum((value * weight for value, weight in q_parts.values()))
    m_parts = {'connected_port_graph_core': (float(bool(structure.get('qualified'))), 0.25), 'command_motion': (command_motion, 0.075), 'measured_joint_motion': (position_motion, 0.075), 'real_motor_current': (_high(nominal['nonzero_current_fraction'], 0.02, 0.2) if nominal['available']['motor_current'] else 0.0, 0.075), 'separated_effort': (min(_high(nominal['arm_torque_rms_Nm'], 0.02, 0.3), _high(nominal['finger_force_rms_N'], 0.02, 0.3)) if nominal['available']['joint_effort'] else 0.0, 0.075), 'supply_voltage_causality': (_high(responses['supply'], 5e-05, 0.0005), 0.12), 'payload_mass_causality': (_high(responses['payload'], 0.0001, 0.001), 0.12), 'joint_friction_causality': (_high(responses['friction'], 0.002, 0.03), 0.11), 'sequence_delay_causality': (_high(responses['sequence'], 0.003, 0.03), 0.1)}
    group_m = sum((value * weight for value, weight in m_parts.values()))
    r_by_scenario = {}
    for name in REQUIRED:
        value = metrics[name]
        effort_ok = 0.0
        if value['available']['motor_current']:
            effort_ok += 0.05 * GROUP_SCORING.SCORING_CORE.low(value['motor_current_peak_A'], 50.0, 180.0)
        if value['available']['joint_effort']:
            effort_ok += 0.025 * GROUP_SCORING.SCORING_CORE.low(value['arm_torque_peak_Nm'], 150.0, 450.0)
            effort_ok += 0.025 * GROUP_SCORING.SCORING_CORE.low(value['finger_force_peak_N'], 150.0, 450.0)
        r_by_scenario[name] = 0.1 * value['available_fraction'] * value['all_available_values_finite'] + 0.1 * _high(value['joint_position_active_axes'], 3.0, 6.0) + 0.1 * (GROUP_SCORING.SCORING_CORE.low(value['arm_tracking_rms_rad'], 0.08, 0.45) if value['available']['joint_command'] and value['available']['joint_position'] else 0.0) + 0.2 * min(value['input_sensor_seen'], _high(value['payload_lift_m'], 0.03, 0.1)) + 0.25 * _high(value['payload_horizontal_travel_m'], 0.18, 0.48) + 0.15 * value['release_public_evidence'] + effort_ok
    group_r = min(r_by_scenario.values())
    ordered = nominal['input_sensor_onset_s'] < nominal['lift_onset_s'] < nominal['output_sensor_onset_s']
    d_parts = {'ordered_input_lift_output_sequence': (float(ordered), 0.2), 'noninstantaneous_sensor_to_lift_delay': (GROUP_SCORING._band(nominal['lift_onset_s'] - nominal['input_sensor_onset_s'], 0.0, 0.15, 10.0, 18.0) if math.isfinite(nominal['lift_onset_s']) and math.isfinite(nominal['input_sensor_onset_s']) else 0.0, 0.12), 'noninstantaneous_transfer_delay': (GROUP_SCORING._band(nominal['output_sensor_onset_s'] - nominal['lift_onset_s'], 0.0, 0.2, 12.0, 19.0) if math.isfinite(nominal['output_sensor_onset_s']) and math.isfinite(nominal['lift_onset_s']) else 0.0, 0.12), 'continuous_contact_supported_payload_motion': (min(GROUP_SCORING.SCORING_CORE.low(nominal['payload_max_step_m'], 0.01, 0.1), _high(nominal['payload_lift_m'], 0.03, 0.12), _high(nominal['payload_horizontal_travel_m'], 0.18, 0.5)) if nominal['available']['payload_pose'] else 0.0, 0.16), 'public_release_continuity': (nominal['release_public_evidence'], 0.12), 'measured_joint_dynamic_evolution': (position_motion, 0.12), 'supply_dynamic_response': (_high(responses['supply'], 5e-05, 0.0005), 0.04), 'payload_dynamic_response': (_high(responses['payload'], 0.0001, 0.001), 0.04), 'friction_dynamic_response': (_high(responses['friction'], 0.002, 0.03), 0.04), 'sequence_dynamic_response': (_high(responses['sequence'], 0.003, 0.03), 0.04)}
    group_d = sum((value * weight for value, weight in d_parts.values()))
    groups = {'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    availability = {name: {'available': all((name in rows[row]['outputs'] for row in REQUIRED)), 'missing_is_scored_zero': not all((name in rows[row]['outputs'] for row in REQUIRED))} for name in ('joint_command', 'joint_position', 'motor_current', 'joint_effort', 'payload_pose', 'sensor_state')}
    return {'schema': 'simuverity.f90-xmech10-score.v1', 'task_id': 'F90-XMECH-10', 'policy_id': 'simuverity-101-v1:f90-xmech-10:scoring', 'G': True, 'groups': {'G': 1.0, **groups}, 'group_weights': WEIGHTS, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score': _geometric(groups), 'total_score': _geometric(groups), 'qualification_checks': qualification, 'output_availability': availability, 'scenario_metrics': _json_safe(metrics), 'diagnostics': {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D': d_parts, 'official_responses': responses}, 'failure_reasons': [], 'post_total_cap_or_floor': False}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    if evidence.get('schema') == 'simuverity.f90-xmech10-partial-evidence.v1':
        return _partial(evidence)
    if evidence.get('schema') == 'simuverity.f90-xmech10-evidence.v1':
        if GROUP_SCORING._contract_matches(evidence):
            # The current six-output candidate contract uses the same strict
            # geometric re-aggregation as the ordinary public route.  Keep a
            # single implementation here so dispatch repair cannot drift from
            # the established critical checks or accidentally revive an
            return _strict_full(evidence)
        return _strict_native_reference(evidence)
    return _strict_full(evidence)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = score(json.loads(args.evidence.read_text(encoding='utf-8')))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
