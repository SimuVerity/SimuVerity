"""Pure offline scorer for fixed F90-XROBO-07 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XROBO-07'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-07:scoring'
REQUIRED = ['nominal_offroad', 'alternate_start_goal', 'heading_and_goal_shift', 'static_map_detour', 'kinematic_margin_stress']
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return math.nan
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int(fraction * len(ordered))))
    return ordered[index]

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

def angle_error(left: float, right: float) -> float:
    return abs(math.atan2(math.sin(left - right), math.cos(left - right)))

def distance(left: list[float], right: list[float]) -> float:
    return math.hypot(left[0] - right[0], left[1] - right[1])

def active_duration(time: list[float], active: list[bool]) -> float:
    return sum((time[index] - time[index - 1] for index in range(1, len(time)) if active[index] or active[index - 1]))

def normalized_trace_distance(left: list[list[float]], right: list[list[float]]) -> float:
    if not left or not right:
        return 0.0
    count = 31

    def samples(rows: list[list[float]]) -> list[tuple[float, float]]:
        output: list[tuple[float, float]] = []
        for k in range(count):
            index = round(k * (len(rows) - 1) / max(count - 1, 1))
            output.append((float(rows[index][0]), float(rows[index][1])))
        return output
    a = samples(left)
    b = samples(right)
    differences = [math.hypot(x1 - x2, y1 - y2) for (x1, y1), (x2, y2) in zip(a, b)]
    span = max(math.hypot(a[-1][0] - a[0][0], a[-1][1] - a[0][1]), 1.0)
    return rms(differences) / span

def best_command_delay_error(velocity: list[list[float]], command: list[list[float]]) -> float:
    best = math.inf
    for shift in range(0, min(12, len(command) // 4 + 1)):
        differences: list[float] = []
        scales: list[float] = []
        for index in range(shift, min(len(velocity), len(command))):
            for channel in range(2):
                differences.append(float(velocity[index][channel]) - float(command[index - shift][channel]))
                scales.append(float(velocity[index][channel]))
        if differences:
            best = min(best, rms(differences) / max(rms(scales), 0.1))
    return best

def best_pose_speed_error(time: list[float], x: list[float], y: list[float], linear_velocity: list[float]) -> float:
    observed = [math.hypot(x[index] - x[index - 1], y[index] - y[index - 1]) / max(time[index] - time[index - 1], 1e-09) for index in range(1, len(time))]
    best = math.inf
    for shift in range(-4, 5):
        differences: list[float] = []
        scales: list[float] = []
        for index, observed_speed in enumerate(observed, start=1):
            velocity_index = index + shift
            if 0 <= velocity_index < len(linear_velocity):
                differences.append(observed_speed - abs(float(linear_velocity[velocity_index])))
                scales.append(observed_speed)
        if differences:
            best = min(best, rms(differences) / max(rms(scales), 0.1))
    return best

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    request = row['requested_inputs']
    time = list(map(float, outputs['time_s']))
    robot_rows = outputs['robot_state']
    command_rows = outputs['executed_command']
    planner_rows = outputs['planner_state']
    robot = columns(robot_rows)
    command = columns(command_rows)
    planner = columns(planner_rows)
    x, y, heading, linear_velocity, angular_velocity = robot
    linear_command, angular_command = command
    reached_goal, last_feasible, exit_flag, replan = planner
    start = list(map(float, request['StartPose']))
    goal = list(map(float, request['GoalPose']))
    max_linear = float(request['MaxLinearVelocity'])
    max_angular = float(request['MaxAngularVelocity'])
    minimum_radius = float(request['MinimumTurningRadius'])
    goal_distance = [math.hypot(x_value - goal[0], y_value - goal[1]) for x_value, y_value in zip(x, y)]
    initial_distance = max(goal_distance[0], 1e-06)
    step_distance = [math.hypot(x[index] - x[index - 1], y[index] - y[index - 1]) for index in range(1, len(time))]
    path_length = sum(step_distance)
    dt = [max(time[index] - time[index - 1], 1e-09) for index in range(1, len(time))]
    linear_acceleration = [abs(linear_command[index] - linear_command[index - 1]) / dt[index - 1] for index in range(1, len(time))]
    angular_acceleration = [abs(angular_command[index] - angular_command[index - 1]) / dt[index - 1] for index in range(1, len(time))]
    heading_rate_error: list[float] = []
    for index in range(1, len(time)):
        measured = math.atan2(math.sin(heading[index] - heading[index - 1]), math.cos(heading[index] - heading[index - 1])) / dt[index - 1]
        heading_rate_error.append(measured - angular_velocity[index])
    radius_values = [abs(v / w) for v, w in zip(linear_command, angular_command) if abs(v) >= 0.1 and abs(w) >= 0.02]
    collision = [float(value) >= 0.5 for value in outputs['collision_free']]
    clearance = list(map(float, outputs['obstacle_clearance_margin_m']))
    progress_steps = [goal_distance[index - 1] - goal_distance[index] for index in range(1, len(goal_distance))]
    stalled = [abs(linear_command[index]) < 0.02 and abs(angular_command[index]) < 0.02 and (goal_distance[index] > 1.0) for index in range(len(time))]
    nonzero_exit = [abs(value) > 0.5 for value in exit_flag]
    return {'start_position_error_m': distance([x[0], y[0]], start), 'start_heading_error_rad': angle_error(heading[0], start[2]), 'final_position_error_m': goal_distance[-1], 'final_heading_error_rad': angle_error(heading[-1], goal[2]), 'minimum_goal_distance_m': min(goal_distance), 'progress_fraction': clamp((initial_distance - goal_distance[-1]) / initial_distance), 'best_progress_fraction': clamp((initial_distance - min(goal_distance)) / initial_distance), 'goal_signal_observed': float(max(reached_goal) >= 0.5), 'goal_signal_physical_agreement': float(max(reached_goal) < 0.5 or (min(goal_distance) <= 0.35 and min((angle_error(value, goal[2]) for value in heading)) <= 0.35)), 'simulation_end_s': time[-1], 'path_length_m': path_length, 'path_efficiency': initial_distance / max(path_length, initial_distance), 'collision_free_fraction': mean(collision), 'minimum_clearance_margin_m': min(clearance), 'clearance_violation_duration_s': active_duration(time, [value < -0.02 for value in clearance]), 'peak_linear_command_mps': max((abs(value) for value in linear_command)), 'peak_angular_command_radps': max((abs(value) for value in angular_command)), 'linear_limit_violation_fraction': mean([abs(value) > max_linear * 1.01 + 1e-06 for value in linear_command]), 'angular_limit_violation_fraction': mean([abs(value) > max_angular * 1.01 + 1e-06 for value in angular_command]), 'turning_radius_violation_fraction': mean([value < minimum_radius * 0.95 for value in radius_values]) if radius_values else 0.0, 'linear_acceleration_p99_mps2': percentile(linear_acceleration, 0.99), 'angular_acceleration_p99_radps2': percentile(angular_acceleration, 0.99), 'maximum_pose_step_m': max(step_distance) if step_distance else 0.0, 'heading_rate_consistency_rms': rms(heading_rate_error), 'command_velocity_delay_error': best_command_delay_error([[a, b] for a, b in zip(linear_velocity, angular_velocity)], command_rows), 'pose_speed_consistency_error': best_pose_speed_error(time, x, y, linear_velocity), 'positive_progress_fraction': mean([value >= -0.02 for value in progress_steps]), 'stall_fraction_before_goal': mean(stalled), 'nonzero_exit_flag_fraction': mean(nonzero_exit), 'replan_request_fraction': mean([value >= 0.5 for value in replan]), 'minimum_last_feasible_index': min(last_feasible), 'map_occupied_fraction': float(row['map_occupied_fraction'])}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    required_outputs = {'time_s', 'robot_state', 'executed_command', 'planner_state', 'collision_free', 'obstacle_clearance_margin_m'}
    all_valid = all((name in rows and bool(rows[name].get('valid')) and (required_outputs <= set(rows[name].get('outputs', {}))) for name in REQUIRED))
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': all_valid, 'reference_unmodified': int(evidence.get('reference_substantive_modifications', -1)) == 0, 'physical_planning_plant_feedback_path': bool(static.get('core_path_qualified'))}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_offroad']
    stress = metrics['kinematic_margin_stress']
    nominal_outputs = rows['nominal_offroad']['outputs']
    detour_outputs = rows['static_map_detour']['outputs']
    alternate_outputs = rows['alternate_start_goal']['outputs']
    heading_outputs = rows['heading_and_goal_shift']['outputs']
    detour_response = normalized_trace_distance(nominal_outputs['robot_state'], detour_outputs['robot_state'])
    alternate_response = normalized_trace_distance(nominal_outputs['robot_state'], alternate_outputs['robot_state'])
    heading_response = normalized_trace_distance(nominal_outputs['robot_state'], heading_outputs['robot_state'])
    constraint_response = abs(nominal['peak_linear_command_mps'] - stress['peak_linear_command_mps']) / max(nominal['peak_linear_command_mps'], 0.1)
    a_parts = {'physical_goal_attainment': (min(low(nominal['final_position_error_m'], 0.2, 2.0), low(nominal['final_heading_error_rad'], 0.15, 0.8)), 0.3), 'collision_free_execution': (high(nominal['collision_free_fraction'], 0.985, 1.0), 0.25), 'complete_progress': (high(nominal['best_progress_fraction'], 0.92, 0.995), 0.15), 'bounded_clearance': (low(nominal['clearance_violation_duration_s'], 0.0, 1.5), 0.1), 'goal_signal_agrees_with_pose': (nominal['goal_signal_physical_agreement'], 0.1), 'nontrivial_closed_loop_motion': (high(nominal['path_length_m'], 20.0, 70.0), 0.1)}
    group_a = weighted(a_parts)
    q_parts = {'linear_command_limit': (low(nominal['linear_limit_violation_fraction'], 0.0, 0.02), 0.15), 'angular_command_limit': (low(nominal['angular_limit_violation_fraction'], 0.0, 0.02), 0.15), 'turning_radius_limit': (low(nominal['turning_radius_violation_fraction'], 0.01, 0.15), 0.2), 'continuous_pose': (low(nominal['maximum_pose_step_m'], 1.8, 5.0), 0.15), 'bicycle_heading_rate_consistency': (low(nominal['heading_rate_consistency_rms'], 0.08, 0.5), 0.15), 'command_to_velocity_consistency': (min(low(nominal['command_velocity_delay_error'], 0.08, 0.5), low(nominal['pose_speed_consistency_error'], 0.08, 0.5)), 0.2)}
    group_q = weighted(q_parts)
    m_parts = {'static_map_planner_recovery_plant_feedback_path': (1.0, 0.3), 'start_goal_causality': (min(high(alternate_response, 0.015, 0.05), high(heading_response, 0.01, 0.035)), 0.2), 'static_map_detour_causality': (high(detour_response, 0.01, 0.08), 0.2), 'constraint_input_causality': (high(constraint_response, 0.01, 0.15), 0.1), 'command_to_plant_feedback': (min(low(nominal['command_velocity_delay_error'], 0.08, 0.5), low(nominal['pose_speed_consistency_error'], 0.08, 0.5)), 0.2)}
    group_m = weighted(m_parts)
    if min(m_parts['start_goal_causality'][0], m_parts['static_map_detour_causality'][0], m_parts['command_to_plant_feedback'][0]) < 0.1:
        group_m = min(group_m, 0.4)
    r_by_scenario: dict[str, float] = {}
    d_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = weighted({'goal_position': (low(values['final_position_error_m'], 0.25, 3.0), 0.25), 'goal_heading': (low(values['final_heading_error_rad'], 0.2, 1.0), 0.1), 'collision_free': (high(values['collision_free_fraction'], 0.98, 1.0), 0.25), 'progress': (high(values['best_progress_fraction'], 0.88, 0.995), 0.15), 'command_bounds': (min(low(values['linear_limit_violation_fraction'], 0.0, 0.02), low(values['angular_limit_violation_fraction'], 0.0, 0.02)), 0.15), 'turning_feasibility': (low(values['turning_radius_violation_fraction'], 0.01, 0.15), 0.1)})
        d_by_scenario[name] = weighted({'starts_at_requested_pose': (min(low(values['start_position_error_m'], 0.05, 1.0), low(values['start_heading_error_rad'], 0.03, 0.5)), 0.15), 'sustained_goal_progress': (high(values['positive_progress_fraction'], 0.55, 0.8), 0.2), 'limited_stall_before_goal': (low(values['stall_fraction_before_goal'], 0.1, 0.5), 0.15), 'local_feasibility_available': (high(values['minimum_last_feasible_index'], 0.0, 1.0), 0.15), 'goal_flag_is_physical': (values['goal_signal_physical_agreement'], 0.15), 'eventual_goal_proximity': (low(values['minimum_goal_distance_m'], 0.25, 3.0), 0.2)})
    group_r = min(r_by_scenario.values())
    group_d = min(d_by_scenario.values())
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D_by_scenario': d_by_scenario, 'derived': {'alternate_start_goal_response': alternate_response, 'heading_goal_shift_response': heading_response, 'static_map_detour_response': detour_response, 'constraint_response': constraint_response}}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xrobo07-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['missing_planner_plant_feedback_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('robot_state', None)
    cases['missing_required_output'] = score(missing_output)['score']
    constant_pose = copy.deepcopy(evidence)
    for row in constant_pose['scenarios']:
        request = row['requested_inputs']
        count = len(row['outputs']['time_s'])
        pose = list(map(float, request['StartPose']))
        row['outputs']['robot_state'] = [pose + [0.0, 0.0] for _ in range(count)]
        row['outputs']['executed_command'] = [[0.0, 0.0] for _ in range(count)]
        row['outputs']['planner_state'] = [[0.0, 0.0, 0.0, 0.0] for _ in range(count)]
    cases['constant_pose_zero_command'] = score(constant_pose)['score']
    direct_line = copy.deepcopy(evidence)
    for row in direct_line['scenarios']:
        request = row['requested_inputs']
        start = list(map(float, request['StartPose']))
        goal = list(map(float, request['GoalPose']))
        count = len(row['outputs']['time_s'])
        for index in range(count):
            fraction = index / max(count - 1, 1)
            row['outputs']['robot_state'][index] = [start[channel] + fraction * (goal[channel] - start[channel]) for channel in range(3)] + [0.0, 0.0]
            row['outputs']['executed_command'][index] = [0.0, 0.0]
        row['outputs']['collision_free'] = [0.0] * count
        row['outputs']['obstacle_clearance_margin_m'] = [-1.0] * count
    cases['direct_interpolation_through_obstacles'] = score(direct_line)['score']
    replay_nominal = copy.deepcopy(evidence)
    nominal = next((row for row in replay_nominal['scenarios'] if row['id'] == 'nominal_offroad'))['outputs']
    for row in replay_nominal['scenarios']:
        if row['id'] != 'nominal_offroad':
            row['outputs'] = copy.deepcopy(nominal)
    cases['nominal_route_replay'] = score(replay_nominal)['score']
    map_ignored = copy.deepcopy(evidence)
    nominal = next((row for row in map_ignored['scenarios'] if row['id'] == 'nominal_offroad'))['outputs']
    detour = next((row for row in map_ignored['scenarios'] if row['id'] == 'static_map_detour'))
    detour['outputs'] = copy.deepcopy(nominal)
    cases['static_map_detour_ignored'] = score(map_ignored)['score']
    disconnected_command = copy.deepcopy(evidence)
    for row in disconnected_command['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['executed_command'] = [[0.0, 0.0] for _ in range(count)]
        for sample in row['outputs']['robot_state']:
            sample[3:5] = [0.0, 0.0]
    cases['commands_disconnected_from_plant'] = score(disconnected_command)['score']
    false_goal = copy.deepcopy(evidence)
    for row in false_goal['scenarios']:
        request = row['requested_inputs']
        pose = list(map(float, request['StartPose']))
        count = len(row['outputs']['time_s'])
        row['outputs']['robot_state'] = [pose + [0.0, 0.0] for _ in range(count)]
        for sample in row['outputs']['planner_state']:
            sample[0] = 1.0
    cases['declared_goal_without_proximity'] = score(false_goal)['score']
    teleport = copy.deepcopy(evidence)
    for row in teleport['scenarios']:
        request = row['requested_inputs']
        start = list(map(float, request['StartPose']))
        goal = list(map(float, request['GoalPose']))
        count = len(row['outputs']['time_s'])
        row['outputs']['robot_state'] = [(start if index < count - 1 else goal) + [0.0, 0.0] for index in range(count)]
        row['outputs']['executed_command'] = [[0.0, 0.0] for _ in range(count)]
    cases['endpoint_teleport'] = score(teleport)['score']
    return {'schema': 'simuverity.f90-xrobo07-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

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
