"""Dedicated offline scorer for F90-XROBO-09.

The scorer never launches MATLAB.  It reads a current evidence JSON, derives
all metrics offline, and emits group scores, metric values, shortcut findings
and failure reasons.
reasons.  Simulation/evidence extraction is intentionally separate.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
import numpy as np
GROUP_WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}
EPS = 1e-12

def _clip(value: float) -> float:
    return float(np.clip(value, 0.0, 1.0))

def _lower_better(value: float, full: float, zero: float) -> float:
    if not np.isfinite(value):
        return 0.0
    if zero <= full:
        raise ValueError('zero must exceed full')
    return _clip((zero - value) / (zero - full))

def _higher_better(value: float, zero: float, full: float) -> float:
    if not np.isfinite(value):
        return 0.0
    if full <= zero:
        raise ValueError('full must exceed zero')
    return _clip((value - zero) / (full - zero))

def _weighted_mean(items: list[tuple[float, float]]) -> float:
    weight = sum((w for _, w in items))
    return 0.0 if weight <= 0 else float(sum((v * w for v, w in items)) / weight)

def _weighted_geometric(groups: dict[str, float]) -> float:
    if any((groups[k] <= 0.0 for k in GROUP_WEIGHTS)):
        return 0.0
    return float(math.exp(sum((GROUP_WEIGHTS[k] * math.log(groups[k]) for k in GROUP_WEIGHTS))))

def _array(row: dict[str, Any], name: str, columns: int) -> np.ndarray:
    data = np.asarray(row['outputs'][name], dtype=float)
    if data.ndim == 1:
        data = data[:, None]
    return data

def _polyline_distance(points: np.ndarray, waypoints: np.ndarray) -> np.ndarray:
    if waypoints.shape[0] < 2:
        return np.linalg.norm(points - waypoints[0], axis=1)
    best = np.full(points.shape[0], np.inf)
    for start, end in zip(waypoints[:-1], waypoints[1:]):
        segment = end - start
        denominator = float(segment @ segment)
        if denominator <= EPS:
            candidate = np.linalg.norm(points - start, axis=1)
        else:
            alpha = np.clip((points - start) @ segment / denominator, 0.0, 1.0)
            projection = start + alpha[:, None] * segment
            candidate = np.linalg.norm(points - projection, axis=1)
        best = np.minimum(best, candidate)
    return best

def _polyline_progress(points: np.ndarray, waypoints: np.ndarray) -> np.ndarray:
    """Arc-length coordinate of the nearest point on an ordered polyline."""
    segment_lengths = np.linalg.norm(np.diff(waypoints, axis=0), axis=1)
    cumulative = np.r_[0.0, np.cumsum(segment_lengths)]
    best_distance = np.full(points.shape[0], np.inf)
    best_progress = np.zeros(points.shape[0])
    for index, (start, end) in enumerate(zip(waypoints[:-1], waypoints[1:])):
        segment = end - start
        denominator = float(segment @ segment)
        if denominator <= EPS:
            alpha = np.zeros(points.shape[0])
            candidate = np.linalg.norm(points - start, axis=1)
        else:
            alpha = np.clip((points - start) @ segment / denominator, 0.0, 1.0)
            projection = start + alpha[:, None] * segment
            candidate = np.linalg.norm(points - projection, axis=1)
        update = candidate < best_distance
        best_distance[update] = candidate[update]
        best_progress[update] = cumulative[index] + alpha[update] * segment_lengths[index]
    return best_progress

def _safe_corr(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, dtype=float).reshape(-1)
    b = np.asarray(b, dtype=float).reshape(-1)
    mask = np.isfinite(a) & np.isfinite(b)
    a, b = (a[mask], b[mask])
    if a.size < 10 or np.std(a) <= EPS or np.std(b) <= EPS:
        return 0.0
    return float(abs(np.corrcoef(a, b)[0, 1]))

def _normalized_rmse(actual: np.ndarray, expected: np.ndarray) -> float:
    residual = np.asarray(actual) - np.asarray(expected)
    scale = max(float(np.sqrt(np.mean(np.asarray(expected) ** 2))), 0.15)
    return float(np.sqrt(np.mean(residual ** 2)) / scale)

def _scenario_metrics(row: dict[str, Any]) -> dict[str, float]:
    t = np.asarray(row['outputs']['time_s'], dtype=float)
    vessel = _array(row, 'vessel_state', 14)
    guidance = _array(row, 'guidance_state', 7)
    prop = _array(row, 'propulsion_state', 6)
    traffic = _array(row, 'traffic_state', 30)
    operating = _array(row, 'operating_state', 4)
    requested = row['requested_inputs']
    waypoints = np.asarray(requested['Waypoints_m'], dtype=float)
    xy = vessel[:, :2]
    route_error = _polyline_distance(xy, waypoints)
    route_progress = _polyline_progress(xy, waypoints)
    route_length = float(np.sum(np.linalg.norm(np.diff(waypoints, axis=0), axis=1)))
    desired_distance = float(np.median(guidance[:, 0]) * t[-1])
    physically_available_progress = max(min(route_length, desired_distance), 1.0)
    progress_ratio = float(np.max(route_progress) / physically_available_progress)
    traveled_distance = float(np.sum(np.linalg.norm(np.diff(xy, axis=0), axis=1)))
    distance_efficiency = traveled_distance / max(desired_distance, 1.0)
    final_distance = float(np.linalg.norm(xy[-1] - waypoints[-1]))
    initial_distance = float(np.linalg.norm(xy[0] - waypoints[-1]))
    progress = _clip((initial_distance - final_distance) / max(initial_distance, 1.0))
    steady = t >= max(20.0, 0.25 * t[-1])
    if not np.any(steady):
        steady = np.ones_like(t, dtype=bool)
    desired_speed = guidance[:, 0]
    speed_error = np.abs(vessel[:, 12] - desired_speed)
    dt = np.gradient(t)
    dx = np.gradient(vessel[:, 0], t)
    dy = np.gradient(vessel[:, 1], t)
    yaw = vessel[:, 8]
    expected_dx = np.cos(yaw) * vessel[:, 3] - np.sin(yaw) * vessel[:, 4]
    expected_dy = np.sin(yaw) * vessel[:, 3] + np.cos(yaw) * vessel[:, 4]
    kinematic_error = 0.5 * (_normalized_rmse(dx, expected_dx) + _normalized_rmse(dy, expected_dy))
    separations: list[np.ndarray] = []
    encounter_flags: list[np.ndarray] = []
    active_vessels = 0
    for index in range(3):
        block = traffic[:, index * 10:(index + 1) * 10]
        traffic_xy = block[:, :2]
        movement = float(np.max(np.linalg.norm(traffic_xy - traffic_xy[0], axis=1)))
        nonzero = float(np.max(np.linalg.norm(traffic_xy, axis=1)))
        if movement > 0.1 or nonzero > 1.0:
            active_vessels += 1
            separations.append(np.linalg.norm(xy - traffic_xy, axis=1))
            encounter_flags.append(block[:, 7] > 0.5)
    if separations:
        separation_matrix = np.column_stack(separations)
        min_separation = float(np.min(separation_matrix))
        any_flag = np.any(np.column_stack(encounter_flags), axis=1)
    else:
        min_separation = 0.0
        any_flag = np.zeros(t.size, dtype=bool)
    mode = np.rint(guidance[:, 6]).astype(int)
    avoidance = mode == 3
    if np.any(any_flag):
        planner_alignment = float(np.mean(avoidance[any_flag]))
        flagged_duration = float(np.sum(dt[any_flag]))
        flag_cleared = float(not any_flag[-1])
        last_flag = int(np.flatnonzero(any_flag)[-1])
        post = np.arange(t.size) >= min(last_flag + 1, t.size - 1)
        post_speed_error = float(np.mean(speed_error[post])) if np.any(post) else 10.0
        post_route_error = float(route_error[-1])
    else:
        planner_alignment = 0.0
        flagged_duration = 0.0
        flag_cleared = 0.0
        post_speed_error = 10.0
        post_route_error = float(route_error[-1])
    prop_mean = 0.5 * (prop[:, 2] + prop[:, 3])
    prop_diff = prop[:, 3] - prop[:, 2]
    left_effort = np.sign(prop[:, 2]) * prop[:, 2] ** 2
    right_effort = np.sign(prop[:, 3]) * prop[:, 3] ** 2
    total_effort = left_effort + right_effort
    differential_effort = right_effort - left_effort
    delivered_force = prop[:, 4]
    delivered_moment = prop[:, 5]
    prop_limit_fraction = float(np.mean(np.max(np.abs(prop[:, 2:4]), axis=1) > 102.0))
    prop_step_p99 = float(np.quantile(np.max(np.abs(np.diff(prop[:, 2:4], axis=0)), axis=1), 0.99))
    endpoint_step = float(np.max(np.linalg.norm(np.diff(xy, axis=0), axis=1)))
    return {'route_error_p95_m': float(np.quantile(route_error, 0.95)), 'route_error_final_m': float(route_error[-1]), 'final_waypoint_distance_m': final_distance, 'normalized_progress': progress, 'route_progress_ratio_to_available_distance': progress_ratio, 'traveled_distance_efficiency': distance_efficiency, 'steady_speed_mae_mps': float(np.mean(speed_error[steady])), 'steady_speed_p95_error_mps': float(np.quantile(speed_error[steady], 0.95)), 'max_abs_roll_deg': float(np.rad2deg(np.max(np.abs(vessel[:, 6])))), 'max_abs_pitch_deg': float(np.rad2deg(np.max(np.abs(vessel[:, 7])))), 'max_abs_heave_m': float(np.max(np.abs(vessel[:, 2] - np.median(vessel[steady, 2])))), 'max_abs_yaw_rate_radps': float(np.max(np.abs(vessel[:, 11]))), 'kinematic_normalized_rmse': kinematic_error, 'active_traffic_vessels': float(active_vessels), 'minimum_physical_separation_m': min_separation, 'potential_collision_duration_s': flagged_duration, 'planner_collision_alignment': planner_alignment, 'collision_flag_cleared_by_end': flag_cleared, 'post_encounter_speed_mae_mps': post_speed_error, 'post_encounter_route_error_m': post_route_error, 'avoidance_mode_fraction': float(np.mean(avoidance)), 'desired_yaw_range_rad': float(np.ptp(np.unwrap(guidance[:, 1]))), 'reference_lateral_range_m': float(np.ptp(guidance[:, 3])), 'left_right_propeller_difference_rms': float(np.sqrt(np.mean(prop_diff ** 2))), 'propeller_limit_fraction': prop_limit_fraction, 'propeller_command_step_p99_radps': prop_step_p99, 'largest_position_step_m': endpoint_step, 'thrust_to_propeller_effort_correlation': _safe_corr(prop[:, 0], total_effort), 'moment_to_differential_effort_correlation': _safe_corr(prop[:, 1], differential_effort), 'propeller_effort_to_force_correlation': _safe_corr(total_effort, delivered_force), 'differential_effort_to_moment_correlation': _safe_corr(differential_effort, delivered_moment), 'current_speed_logged_mps': float(np.median(operating[:, 0])), 'desired_speed_logged_mps': float(np.median(guidance[:, 0]))}

def _scenario_performance(m: dict[str, float]) -> float:
    return _weighted_mean([(_lower_better(m['route_error_final_m'], 18.0, 55.0), 0.18), (_higher_better(m['route_progress_ratio_to_available_distance'], 0.35, 0.68), 0.22), (_higher_better(m['traveled_distance_efficiency'], 0.65, 0.9), 0.18), (_lower_better(m['steady_speed_mae_mps'], 0.05, 0.35), 0.18), (_higher_better(m['minimum_physical_separation_m'], 3.0, 10.0), 0.24)])

def _quality_performance(m: dict[str, float]) -> float:
    return _weighted_mean([(_lower_better(m['max_abs_roll_deg'], 8.0, 28.0), 0.22), (_lower_better(m['max_abs_pitch_deg'], 8.0, 28.0), 0.22), (_lower_better(m['max_abs_heave_m'], 0.18, 0.65), 0.12), (_lower_better(m['propeller_limit_fraction'], 0.02, 0.45), 0.18), (_lower_better(m['propeller_command_step_p99_radps'], 6.0, 60.0), 0.14), (_lower_better(m['largest_position_step_m'], 0.35, 2.0), 0.12)])

def _avoidance_performance(m: dict[str, float]) -> float:
    encounter = m['potential_collision_duration_s'] > 0.5
    if not encounter:
        return 0.0
    return _weighted_mean([(_higher_better(m['planner_collision_alignment'], 0.35, 0.75), 0.23), (_higher_better(m['minimum_physical_separation_m'], 3.0, 10.0), 0.25), (m['collision_flag_cleared_by_end'], 0.05), (_lower_better(m['post_encounter_speed_mae_mps'], 0.05, 0.35), 0.15), (_lower_better(m['post_encounter_route_error_m'], 20.0, 55.0), 0.14), (_higher_better(m['desired_yaw_range_rad'], 0.05, 0.3), 0.07), (_higher_better(m['left_right_propeller_difference_rms'], 0.5, 8.0), 0.07), (_higher_better(m['route_progress_ratio_to_available_distance'], 0.35, 0.68), 0.04)])

def _static_gate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    top = ['load_pass', 'update_pass', 'compile_pass', 'nominal_smoke_pass', 'model_closed_without_save']
    for key in top:
        if not bool(evidence.get(key, False)):
            reasons.append(f'{key}=false')
    scenarios = evidence.get('scenarios', [])
    if not scenarios:
        reasons.append('no official scenarios')
    for row in scenarios:
        if not bool(row.get('valid', False)):
            reasons.append(f"scenario {row.get('id', '?')} invalid")
    required_static = ['vessel_platform_present', 'closed_loop_controller_present', 'six_dof_core_present', 'hydrodynamic_core_present', 'hydrostatic_core_present', 'current_crossflow_core_present', 'twin_propeller_thrust_core_present', 'traffic_ground_truth_assessment_present', 'collision_avoidance_planning_present', 'waypoint_guidance_present', 'control_allocation_present', 'controller_to_vessel_connected', 'vessel_feedback_to_controller_connected', 'scenario_to_controller_connected', 'environment_to_vessel_connected']
    audit = evidence.get('static_audit', {})
    for key in required_static:
        if not bool(audit.get(key, False)):
            reasons.append(f'static core missing/disconnected: {key}')
    return (not reasons, reasons)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    gate, reasons = _static_gate(evidence)
    if not gate:
        return {'schema': 'simuverity.f90-xrobo09-score.v1', 'task_id': 'F90-XROBO-09', 'G': 0.0, 'groups': {name: 0.0 for name in GROUP_WEIGHTS}, 'group_weights': GROUP_WEIGHTS, 'raw_score': 0.0, 'shortcut_findings': ['qualification_gate'], 'failure_reasons': reasons, 'scenario_metrics': {}}
    scenario_metrics: dict[str, dict[str, float]] = {}
    rows = evidence['scenarios']
    for row in rows:
        scenario_metrics[str(row['id'])] = _scenario_metrics(row)
    metrics = list(scenario_metrics.values())
    scenario_scores = [_scenario_performance(m) for m in metrics]
    quality_scores = [_quality_performance(m) for m in metrics]
    avoidance_scores = [_avoidance_performance(m) for m in metrics]
    nominal = metrics[0]
    A = _weighted_mean([(_scenario_performance(nominal), 0.65), (_lower_better(nominal['steady_speed_p95_error_mps'], 0.18, 0.75), 0.15), (_higher_better(nominal['minimum_physical_separation_m'], 3.0, 10.0), 0.2)])
    Q = float(min(quality_scores))
    kinematic = min((_lower_better(m['kinematic_normalized_rmse'], 0.08, 0.55) for m in metrics))
    propeller_causality = min((_weighted_mean([(_higher_better(m['thrust_to_propeller_effort_correlation'], 0.25, 0.82), 0.2), (_higher_better(m['moment_to_differential_effort_correlation'], 0.25, 0.82), 0.25), (_higher_better(m['propeller_effort_to_force_correlation'], 0.2, 0.58), 0.25), (_higher_better(m['differential_effort_to_moment_correlation'], 0.25, 0.7), 0.3)]) for m in metrics))
    planner_causality = min((_weighted_mean([(_higher_better(m['planner_collision_alignment'], 0.25, 0.85), 0.45), (_higher_better(m['desired_yaw_range_rad'], 0.04, 0.25), 0.25), (_higher_better(m['left_right_propeller_difference_rms'], 0.5, 8.0), 0.3)]) for m in metrics))
    by_id = scenario_metrics
    nominal_current = by_id.get('crossing_starboard', nominal)
    boundary_current = by_id.get('crossing_current_boundary', nominal)
    nominal_speed = by_id.get('crossing_multiship', nominal)
    reduced_speed = by_id.get('multiship_reduced_speed', nominal)
    current_input_delta = abs(boundary_current['current_speed_logged_mps'] - nominal_current['current_speed_logged_mps'])
    speed_input_delta = abs(reduced_speed['desired_speed_logged_mps'] - nominal_speed['desired_speed_logged_mps'])
    nominal_current_row = next((row for row in rows if row['id'] == 'crossing_starboard'))
    boundary_current_row = next((row for row in rows if row['id'] == 'crossing_current_boundary'))
    nominal_speed_row = next((row for row in rows if row['id'] == 'crossing_multiship'))
    reduced_speed_row = next((row for row in rows if row['id'] == 'multiship_reduced_speed'))
    nominal_current_vessel = _array(nominal_current_row, 'vessel_state', 14)
    boundary_current_vessel = _array(boundary_current_row, 'vessel_state', 14)
    current_behavior_delta = float(np.linalg.norm(nominal_current_vessel[-1, :2] - boundary_current_vessel[-1, :2]))
    nominal_speed_vessel = _array(nominal_speed_row, 'vessel_state', 14)
    reduced_speed_vessel = _array(reduced_speed_row, 'vessel_state', 14)
    speed_behavior_delta = float(abs(np.median(nominal_speed_vessel[-500:, 12]) - np.median(reduced_speed_vessel[-500:, 12])))
    input_application = _weighted_mean([(_higher_better(current_input_delta, 0.02, 0.14), 0.2), (_higher_better(speed_input_delta, 0.05, 0.25), 0.2), (_higher_better(current_behavior_delta, 0.25, 2.0), 0.25), (_higher_better(speed_behavior_delta, 0.05, 0.22), 0.35)])
    M = _weighted_mean([(kinematic, 0.28), (propeller_causality, 0.32), (planner_causality, 0.25), (input_application, 0.15)])
    R = float(min(scenario_scores))
    D = float(min(avoidance_scores))
    groups = {'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    raw = 100.0 * _weighted_geometric(groups)
    shortcut_findings: list[str] = []
    if M < 0.45:
        shortcut_findings.append('weak physical/control causality')
    if propeller_causality < 0.35:
        shortcut_findings.append('missing propeller-to-force/moment causality')
    if input_application < 0.5:
        shortcut_findings.append('official current/speed inputs not applied behaviorally')
    if R < 0.35:
        shortcut_findings.append('failed worst operating condition')
    if D < 0.35:
        shortcut_findings.append('failed avoidance/recovery')
    if min((m['minimum_physical_separation_m'] for m in metrics)) < 2.5:
        shortcut_findings.append('physical near-collision')
    if max((m['largest_position_step_m'] for m in metrics)) > 2.0:
        shortcut_findings.append('discontinuous position trajectory')
    return {'schema': 'simuverity.f90-xrobo09-score.v1', 'task_id': 'F90-XROBO-09', 'G': 1.0, 'groups': groups, 'group_weights': GROUP_WEIGHTS, 'group_aggregation': 'weighted_geometric_mean', 'raw_score': float(raw), 'shortcut_findings': shortcut_findings, 'failure_reasons': reasons, 'group_components': {'A_nominal': A, 'Q_worst_scenario': Q, 'M_kinematic_consistency': kinematic, 'M_propeller_causality': propeller_causality, 'M_planner_causality': planner_causality, 'M_official_input_application': input_application, 'R_worst_scenario': R, 'D_worst_encounter': D}, 'scenario_scores': {row['id']: {'performance': scenario_scores[index], 'quality': quality_scores[index], 'avoidance_recovery': avoidance_scores[index]} for index, row in enumerate(rows)}, 'scenario_metrics': scenario_metrics}

def _shortcut_suite(evidence: dict[str, Any]) -> list[dict[str, Any]]:
    cases: list[tuple[str, dict[str, Any]]] = []
    missing = copy.deepcopy(evidence)
    missing['scenarios'][0]['valid'] = False
    cases.append(('missing_required_output', missing))
    no_six_dof = copy.deepcopy(evidence)
    no_six_dof['static_audit']['six_dof_core_present'] = False
    cases.append(('kinematic_point_mass_without_six_dof_core', no_six_dof))
    no_hydro = copy.deepcopy(evidence)
    no_hydro['static_audit']['hydrodynamic_core_present'] = False
    cases.append(('missing_hydrodynamic_core', no_hydro))
    fixed_prop = copy.deepcopy(evidence)
    for row in fixed_prop['scenarios']:
        prop = np.asarray(row['outputs']['propulsion_state'], dtype=float)
        prop[:, 2:6] = 0.0
        row['outputs']['propulsion_state'] = prop.tolist()
    cases.append(('fixed_zero_propeller_path', fixed_prop))
    ignored_traffic = copy.deepcopy(evidence)
    for row in ignored_traffic['scenarios']:
        guidance = np.asarray(row['outputs']['guidance_state'], dtype=float)
        traffic = np.asarray(row['outputs']['traffic_state'], dtype=float)
        guidance[:, 6] = 1.0
        traffic[:, [7, 17, 27]] = 0.0
        row['outputs']['guidance_state'] = guidance.tolist()
        row['outputs']['traffic_state'] = traffic.tolist()
    cases.append(('traffic_ignored_and_avoidance_disabled', ignored_traffic))
    disconnected = copy.deepcopy(evidence)
    for row in disconnected['scenarios']:
        vessel = np.asarray(row['outputs']['vessel_state'], dtype=float)
        vessel[:, :14] = vessel[0, :14]
        row['outputs']['vessel_state'] = vessel.tolist()
    cases.append(('commands_disconnected_from_vessel_motion', disconnected))
    replay = copy.deepcopy(evidence)
    nominal_outputs = copy.deepcopy(replay['scenarios'][0]['outputs'])
    for row in replay['scenarios'][1:]:
        row['outputs'] = copy.deepcopy(nominal_outputs)
        row['outputs']['time_s'] = evidence['scenarios'][0]['outputs']['time_s']
    cases.append(('nominal_trajectory_replayed_across_scenario_inputs', replay))
    teleport = copy.deepcopy(evidence)
    for row in teleport['scenarios']:
        vessel = np.asarray(row['outputs']['vessel_state'], dtype=float)
        vessel[1:, :2] = vessel[-1, :2]
        row['outputs']['vessel_state'] = vessel.tolist()
    cases.append(('endpoint_teleport', teleport))
    ignored_inputs = copy.deepcopy(evidence)
    source = copy.deepcopy(ignored_inputs['scenarios'][0]['outputs'])
    for row in ignored_inputs['scenarios']:
        if row['id'] in ('crossing_current_boundary', 'multiship_reduced_speed'):
            row['outputs'] = copy.deepcopy(source)
    cases.append(('current_and_speed_inputs_ignored', ignored_inputs))
    return [{'case': name, 'score': score_evidence(mutated)} for name, mutated in cases]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--shortcut-suite', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + '\n', encoding='utf-8')
    else:
        print(text)
    if args.shortcut_suite:
        suite = _shortcut_suite(evidence)
        args.shortcut_suite.parent.mkdir(parents=True, exist_ok=True)
        args.shortcut_suite.write_text(json.dumps(suite, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
