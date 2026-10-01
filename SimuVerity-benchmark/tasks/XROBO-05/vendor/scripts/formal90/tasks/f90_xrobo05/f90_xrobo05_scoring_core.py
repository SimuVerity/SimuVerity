"""Pure offline scorer for fixed F90-XROBO-05 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XROBO-05'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-05:scoring'
REQUIRED = ['native_nominal_dual_step', 'moderate_heading_boundary', 'moderate_depth_boundary', 'current_magnitude_boundary', 'current_direction_boundary', 'reduced_propulsive_authority']
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def quantile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return math.nan
    position = fraction * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    mix = position - lower
    return ordered[lower] * (1 - mix) + ordered[upper] * mix

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
    if denominator <= 0:
        return 0.0
    return sum((clamp(score) * weight for score, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[name] * math.log(groups[name]) for name in WEIGHTS)))

def columns(rows: list[list[float]]) -> list[list[float]]:
    return [list(map(float, column)) for column in zip(*rows)]

def wrap_pi(value: float) -> float:
    return (value + math.pi) % (2 * math.pi) - math.pi

def relative_change(value: float, baseline: float) -> float:
    return abs(value - baseline) / max(abs(baseline), 1e-09)

def settling_time(time: list[float], error: list[float], start: float, tolerance: float) -> float:
    minimum_samples = max(2, round(15.0 / max(time[1] - time[0], 1e-09)))
    candidates = [index for index, value in enumerate(time) if value >= start]
    for index in candidates:
        end = min(len(time), index + minimum_samples)
        if end - index == minimum_samples and all((abs(error[j]) <= tolerance for j in range(index, end))):
            return time[index] - start
    return math.inf

def kinematic_consistency(time: list[float], state: list[list[float]]) -> tuple[float, float]:
    values = columns(state)
    u, v, w, p, q, r, north, east, down, roll, pitch, yaw = values
    position_errors: list[float] = []
    attitude_errors: list[float] = []
    position_scale: list[float] = []
    attitude_scale: list[float] = []
    for index in range(1, len(time)):
        dt = time[index] - time[index - 1]
        if dt <= 0:
            continue
        phi = 0.5 * (roll[index] + roll[index - 1])
        theta = 0.5 * (pitch[index] + pitch[index - 1])
        psi = 0.5 * (yaw[index] + yaw[index - 1])
        ub = 0.5 * (u[index] + u[index - 1])
        vb = 0.5 * (v[index] + v[index - 1])
        wb = 0.5 * (w[index] + w[index - 1])
        pb = 0.5 * (p[index] + p[index - 1])
        qb = 0.5 * (q[index] + q[index - 1])
        rb = 0.5 * (r[index] + r[index - 1])
        cphi, sphi = (math.cos(phi), math.sin(phi))
        ctheta, stheta = (math.cos(theta), math.sin(theta))
        cpsi, spsi = (math.cos(psi), math.sin(psi))
        ctheta_safe = math.copysign(max(abs(ctheta), 1e-05), ctheta)
        predicted_position = [cpsi * ctheta * ub + (cpsi * stheta * sphi - spsi * cphi) * vb + (spsi * sphi + cpsi * cphi * stheta) * wb, spsi * ctheta * ub + (cphi * cpsi + sphi * stheta * spsi) * vb + (cphi * stheta * spsi - cpsi * sphi) * wb, -stheta * ub + ctheta * sphi * vb + ctheta * cphi * wb]
        measured_position = [(north[index] - north[index - 1]) / dt, (east[index] - east[index - 1]) / dt, (down[index] - down[index - 1]) / dt]
        predicted_attitude = [pb + sphi * math.tan(theta) * qb + cphi * math.tan(theta) * rb, cphi * qb - sphi * rb, sphi / ctheta_safe * qb + cphi / ctheta_safe * rb]
        measured_attitude = [wrap_pi(roll[index] - roll[index - 1]) / dt, wrap_pi(pitch[index] - pitch[index - 1]) / dt, wrap_pi(yaw[index] - yaw[index - 1]) / dt]
        position_errors.extend((measured - predicted for measured, predicted in zip(measured_position, predicted_position)))
        attitude_errors.extend((measured - predicted for measured, predicted in zip(measured_attitude, predicted_attitude)))
        position_scale.extend(predicted_position)
        attitude_scale.extend(predicted_attitude)
    return (rms(position_errors) / max(rms(position_scale), 0.1), rms(attitude_errors) / max(rms(attitude_scale), 0.01))

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    requested = row['requested_inputs']
    time = list(map(float, outputs['time_s']))
    reference = columns(outputs['reference_state'])
    vehicle_rows = outputs['vehicle_state']
    vehicle = columns(vehicle_rows)
    actuation = columns(outputs['actuation_state'])
    environment = columns(outputs['environment_state'])
    heading_raw, heading_shaped, depth_raw, depth_filtered = reference
    u, v, w, p, q, r, north, east, down, roll, pitch, yaw = vehicle
    rudder, stern, pitch_command, propeller = actuation
    current_speed, current_direction, speed = environment
    heading_error = [wrap_pi(yaw[index] - heading_shaped[index]) for index in range(len(time))]
    depth_error = [down[index] - depth_filtered[index] for index in range(len(time))]
    heading_final_error = [wrap_pi(value - math.radians(float(requested['HeadingCommand_deg']))) for value in yaw]
    depth_final_error = [value - float(requested['DepthCommand_m']) for value in down]
    heading_step = float(requested['HeadingStepTime_s'])
    depth_step = float(requested['DepthStepTime_s'])
    heading_eval = [index for index, value in enumerate(time) if value >= heading_step + 60.0]
    depth_eval = [index for index, value in enumerate(time) if value >= depth_step + 80.0]
    tail = [index for index, value in enumerate(time) if value >= 360.0]
    active = [index for index, value in enumerate(time) if value >= 20.0]
    position_kinematics, attitude_kinematics = kinematic_consistency(time, vehicle_rows)
    heading_amplitude = abs(float(requested['HeadingCommand_deg']) - float(requested['HeadingInitial_deg']))
    depth_amplitude = abs(float(requested['DepthCommand_m']) - float(requested['DepthInitial_m']))
    return {'heading_input_error_deg': max((abs(heading_raw[index] - (float(requested['HeadingInitial_deg']) if time[index] < heading_step else float(requested['HeadingCommand_deg']))) for index in range(len(time)))), 'depth_input_error_m': max((abs(depth_raw[index] - (float(requested['DepthInitial_m']) if time[index] < depth_step else float(requested['DepthCommand_m']))) for index in range(len(time)))), 'current_speed_input_error_mps': max((abs(value - float(requested['CurrentSpeed_mps'])) for value in current_speed)), 'current_direction_input_error_rad': max((abs(wrap_pi(value - math.radians(float(requested['CurrentDirection_deg'])))) for value in current_direction)), 'propeller_input_error_rpm': max((abs(value - float(requested['PropellerSpeed_rpm'])) for value in propeller)), 'heading_rmse_deg': math.degrees(rms([heading_error[index] for index in heading_eval])), 'heading_tail_error_deg': math.degrees(abs(mean([heading_error[index] for index in tail]))), 'heading_peak_error_after_60s_deg': math.degrees(max((abs(heading_error[index]) for index in heading_eval))), 'heading_settling_s': settling_time(time, heading_final_error, heading_step, math.radians(3.0)), 'heading_response_amplitude_deg': math.degrees(max(yaw) - min(yaw)), 'heading_command_amplitude_deg': heading_amplitude, 'depth_rmse_m': rms([depth_error[index] for index in depth_eval]), 'depth_tail_error_m': abs(mean([depth_error[index] for index in tail])), 'depth_peak_error_after_80s_m': max((abs(depth_error[index]) for index in depth_eval)), 'depth_settling_s': settling_time(time, depth_final_error, depth_step, 1.0), 'depth_response_amplitude_m': max(down) - min(down), 'depth_command_amplitude_m': depth_amplitude, 'rudder_peak_deg': math.degrees(max((abs(value) for value in rudder))), 'stern_peak_deg': math.degrees(max((abs(value) for value in stern))), 'rudder_active_rms_deg': math.degrees(rms([rudder[index] for index in active])), 'stern_active_rms_deg': math.degrees(rms([stern[index] for index in active])), 'rudder_saturation_fraction': mean([abs(rudder[index]) >= math.radians(19.9) for index in active]), 'stern_saturation_fraction': mean([abs(stern[index]) >= math.radians(19.9) for index in active]), 'pitch_command_peak_deg': math.degrees(max((abs(value) for value in pitch_command))), 'roll_peak_deg': math.degrees(max((abs(value) for value in roll))), 'pitch_peak_deg': math.degrees(max((abs(value) for value in pitch))), 'yaw_rate_peak_degps': math.degrees(max((abs(value) for value in r))), 'pitch_rate_peak_degps': math.degrees(max((abs(value) for value in q))), 'mean_speed_mps': mean([speed[index] for index in active]), 'minimum_speed_mps': min((speed[index] for index in active)), 'surge_mean_mps': mean([u[index] for index in active]), 'lateral_velocity_rms_mps': rms([v[index] for index in active]), 'vertical_velocity_rms_mps': rms([w[index] for index in active]), 'north_endpoint_m': north[-1], 'east_endpoint_m': east[-1], 'down_endpoint_m': down[-1], 'position_kinematic_relative_rmse': position_kinematics, 'attitude_kinematic_relative_rmse': attitude_kinematics, 'tail_state_drift': max((abs(values[tail[-1]] - values[tail[0]]) for values in [u, v, w, p, q, r, roll, pitch]))}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    required_outputs = {'time_s', 'reference_state', 'vehicle_state', 'actuation_state', 'environment_state'}
    scenarios_valid = all((name in rows and bool(rows[name].get('valid')) and (required_outputs <= set(rows[name].get('outputs', {}))) for name in REQUIRED))
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': scenarios_valid, 'reference_unmodified': int(evidence.get('reference_substantive_modifications', -1)) == 0, 'physical_dual_loop_6dof_path': bool(static.get('core_path_qualified'))}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['native_nominal_dual_step']
    heading_case = metrics['moderate_heading_boundary']
    depth_case = metrics['moderate_depth_boundary']
    current_speed_case = metrics['current_magnitude_boundary']
    current_direction_case = metrics['current_direction_boundary']
    propulsion_case = metrics['reduced_propulsive_authority']
    a_parts = {'heading_tracking': (low(nominal['heading_rmse_deg'], 2.0, 12.0), 0.3), 'heading_tail': (low(nominal['heading_tail_error_deg'], 1.0, 8.0), 0.1), 'depth_tracking': (low(nominal['depth_rmse_m'], 0.6, 4.0), 0.3), 'depth_tail': (low(nominal['depth_tail_error_m'], 0.3, 2.5), 0.1), 'attitude_bounds': (min(low(nominal['roll_peak_deg'], 15.0, 35.0), low(nominal['pitch_peak_deg'], 20.0, 40.0)), 0.1), 'forward_motion': (high(nominal['minimum_speed_mps'], 0.1, 0.8), 0.1)}
    group_a = weighted(a_parts)
    q_parts = {'rudder_limit': (low(nominal['rudder_peak_deg'], 20.0, 22.0), 0.15), 'stern_limit': (low(nominal['stern_peak_deg'], 20.0, 22.0), 0.15), 'position_kinematics': (low(nominal['position_kinematic_relative_rmse'], 0.03, 0.3), 0.2), 'attitude_kinematics': (low(nominal['attitude_kinematic_relative_rmse'], 0.03, 0.3), 0.2), 'coupled_lateral_state': (high(nominal['lateral_velocity_rms_mps'], 0.005, 0.05), 0.1), 'coupled_vertical_state': (high(nominal['vertical_velocity_rms_mps'], 0.005, 0.05), 0.1), 'bounded_rates': (min(low(nominal['yaw_rate_peak_degps'], 15.0, 40.0), low(nominal['pitch_rate_peak_degps'], 15.0, 40.0)), 0.1)}
    group_q = weighted(q_parts)
    all_inputs = [values[key] for values in metrics.values() for key in ('heading_input_error_deg', 'depth_input_error_m', 'current_speed_input_error_mps', 'current_direction_input_error_rad', 'propeller_input_error_rpm')]
    heading_response = abs(heading_case['down_endpoint_m'] - nominal['down_endpoint_m'])
    depth_response = abs(depth_case['down_endpoint_m'] - nominal['down_endpoint_m'])
    current_speed_response = max(abs(current_speed_case['east_endpoint_m'] - nominal['east_endpoint_m']), abs(current_speed_case['north_endpoint_m'] - nominal['north_endpoint_m']), abs(current_speed_case['heading_rmse_deg'] - nominal['heading_rmse_deg']))
    current_direction_response = max(abs(current_direction_case['east_endpoint_m'] - nominal['east_endpoint_m']), abs(current_direction_case['north_endpoint_m'] - nominal['north_endpoint_m']), abs(current_direction_case['heading_rmse_deg'] - nominal['heading_rmse_deg']))
    propulsion_response = nominal['mean_speed_mps'] - propulsion_case['mean_speed_mps']
    m_parts = {'static_reference_controller_actuator_6dof_path': (1.0, 0.25), 'all_scenario_inputs_applied': (low(max(all_inputs), 1e-08, 0.001), 0.1), 'heading_loop_causality': (min(high(heading_case['heading_response_amplitude_deg'], 0.6 * heading_case['heading_command_amplitude_deg'], 0.9 * heading_case['heading_command_amplitude_deg']), high(heading_case['rudder_active_rms_deg'], 0.1, 1.0)), 0.12), 'depth_loop_causality': (min(high(depth_case['depth_response_amplitude_m'], 0.6 * depth_case['depth_command_amplitude_m'], 0.9 * depth_case['depth_command_amplitude_m']), high(depth_case['stern_active_rms_deg'], 0.1, 1.0), high(depth_response, 2.0, 6.0)), 0.13), 'current_magnitude_causality': (high(current_speed_response, 0.5, 5.0), 0.13), 'current_direction_causality': (high(current_direction_response, 0.5, 5.0), 0.13), 'propulsive_authority_causality': (high(propulsion_response, 0.05, 0.2), 0.14)}
    group_m = weighted(m_parts)
    critical_mechanism = [m_parts['all_scenario_inputs_applied'][0], m_parts['heading_loop_causality'][0], m_parts['depth_loop_causality'][0], m_parts['current_magnitude_causality'][0], m_parts['current_direction_causality'][0], m_parts['propulsive_authority_causality'][0], q_parts['position_kinematics'][0], q_parts['attitude_kinematics'][0]]
    if min(critical_mechanism) < 0.1:
        group_m = min(group_m, 0.4)
    r_by_scenario: dict[str, float] = {}
    d_by_scenario: dict[str, float] = {}
    for name, values in metrics.items():
        r_by_scenario[name] = weighted({'heading_tracking': (low(values['heading_rmse_deg'], 3.0, 18.0), 0.25), 'depth_tracking': (low(values['depth_rmse_m'], 1.0, 6.0), 0.25), 'attitude_bounds': (min(low(values['roll_peak_deg'], 20.0, 45.0), low(values['pitch_peak_deg'], 25.0, 45.0)), 0.15), 'control_limits': (min(low(values['rudder_peak_deg'], 20.0, 22.0), low(values['stern_peak_deg'], 20.0, 22.0)), 0.15), 'forward_authority': (high(values['minimum_speed_mps'], 0.05, 0.6), 0.2)})
        d_by_scenario[name] = weighted({'heading_recovery': (low(values['heading_settling_s'], 100.0, 260.0), 0.25), 'depth_recovery': (low(values['depth_settling_s'], 120.0, 200.0), 0.25), 'heading_late_excursion': (low(values['heading_peak_error_after_60s_deg'], 5.0, 20.0), 0.15), 'depth_late_excursion': (low(values['depth_peak_error_after_80s_m'], 1.5, 6.0), 0.15), 'limited_saturation': (min(low(values['rudder_saturation_fraction'], 0.05, 0.4), low(values['stern_saturation_fraction'], 0.05, 0.4)), 0.1), 'bounded_cross_axis': (min(low(values['roll_peak_deg'], 20.0, 45.0), low(values['pitch_peak_deg'], 25.0, 45.0)), 0.1)})
    group_r = min(r_by_scenario.values())
    group_d = min(d_by_scenario.values())
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D_by_scenario': d_by_scenario, 'derived': {'heading_boundary_depth_endpoint_change_m': heading_response, 'depth_boundary_depth_endpoint_change_m': depth_response, 'current_magnitude_response': current_speed_response, 'current_direction_response': current_direction_response, 'reduced_propulsion_speed_drop_mps': propulsion_response}}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xrobo05-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['missing_6dof_or_closed_loop_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('vehicle_state', None)
    cases['missing_required_output'] = score(missing_output)['score']
    constant_pose = copy.deepcopy(evidence)
    for row in constant_pose['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['vehicle_state'] = [[0.0] * 12 for _ in range(count)]
        for sample in row['outputs']['environment_state']:
            sample[2] = 0.0
    cases['constant_or_replayed_pose'] = score(constant_pose)['score']
    kinematic_assignment = copy.deepcopy(evidence)
    for row in kinematic_assignment['scenarios']:
        reference = row['outputs']['reference_state']
        for index, sample in enumerate(row['outputs']['vehicle_state']):
            sample[:] = [0.0] * 12
            sample[8] = reference[index][3]
            sample[11] = reference[index][1]
        for sample in row['outputs']['actuation_state']:
            sample[0:3] = [0.0, 0.0, 0.0]
    cases['kinematic_pose_assignment'] = score(kinematic_assignment)['score']
    heading_only = copy.deepcopy(evidence)
    for row in heading_only['scenarios']:
        for sample in row['outputs']['vehicle_state']:
            sample[8] = 0.0
        for sample in row['outputs']['actuation_state']:
            sample[1:3] = [0.0, 0.0]
    cases['heading_only_controller'] = score(heading_only)['score']
    depth_only = copy.deepcopy(evidence)
    for row in depth_only['scenarios']:
        for sample in row['outputs']['vehicle_state']:
            sample[11] = 0.0
        for sample in row['outputs']['actuation_state']:
            sample[0] = 0.0
    cases['depth_only_controller'] = score(depth_only)['score']
    disconnected_current = copy.deepcopy(evidence)
    nominal = next((row for row in disconnected_current['scenarios'] if row['id'] == 'native_nominal_dual_step'))
    nominal_vehicle = copy.deepcopy(nominal['outputs']['vehicle_state'])
    nominal_actuation = copy.deepcopy(nominal['outputs']['actuation_state'])
    for row in disconnected_current['scenarios']:
        if row['id'] in {'current_magnitude_boundary', 'current_direction_boundary'}:
            row['outputs']['vehicle_state'] = copy.deepcopy(nominal_vehicle)
            row['outputs']['actuation_state'] = copy.deepcopy(nominal_actuation)
    cases['disconnected_current_inputs'] = score(disconnected_current)['score']
    fixed_surfaces = copy.deepcopy(evidence)
    for row in fixed_surfaces['scenarios']:
        for sample in row['outputs']['actuation_state']:
            sample[0:3] = [0.0, 0.0, 0.0]
    cases['fixed_control_surfaces'] = score(fixed_surfaces)['score']
    ignored_inputs = copy.deepcopy(evidence)
    nominal_outputs = next((row for row in ignored_inputs['scenarios'] if row['id'] == 'native_nominal_dual_step'))['outputs']
    for row in ignored_inputs['scenarios']:
        if row['id'] != 'native_nominal_dual_step':
            row['outputs'] = copy.deepcopy(nominal_outputs)
    cases['ignored_scenario_inputs'] = score(ignored_inputs)['score']
    return {'schema': 'simuverity.f90-xrobo05-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

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
