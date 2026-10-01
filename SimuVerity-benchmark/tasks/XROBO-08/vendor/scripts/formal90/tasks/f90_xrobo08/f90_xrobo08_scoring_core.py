"""Pure offline scorer for fixed F90-XROBO-08 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from statistics import fmean, pstdev
from typing import Any
TASK_ID = 'F90-XROBO-08'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-08:scoring'
REQUIRED = ['nominal_offset', 'opposite_quadrant', 'near_edge_recovery', 'initial_velocity_recovery', 'ball_mass_margin', 'contact_friction_margin', 'actuator_derating']
OUTPUT_SHAPES = {'ball_state': 4, 'plate_state': 8, 'actuated_joint_state': 4, 'control_state': 4, 'task_state': 2, 'observation_state': 22}
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

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
    return sum((clamp(value) * weight for value, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[name] * math.log(groups[name]) for name in WEIGHTS)))

def columns(rows: list[list[float]]) -> list[list[float]]:
    return [list(map(float, column)) for column in zip(*rows)]

def rms(values: list[float]) -> float:
    return math.sqrt(fmean([value * value for value in values])) if values else math.nan

def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return math.nan
    position = fraction * (len(ordered) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    mix = position - lower
    return ordered[lower] * (1.0 - mix) + ordered[upper] * mix

def finite(value: Any) -> bool:
    if isinstance(value, (int, float)):
        return math.isfinite(float(value))
    if isinstance(value, list):
        return all((finite(item) for item in value))
    return False

def matrix_shape(value: Any, rows: int, columns_count: int) -> bool:
    return isinstance(value, list) and len(value) == rows and all((isinstance(row, list) and len(row) == columns_count for row in value)) and finite(value)

def qualification(evidence: dict[str, Any]) -> tuple[dict[str, bool], list[str]]:
    checks: dict[str, bool] = {'task_identity': evidence.get('task_id') == TASK_ID, 'load': evidence.get('load_pass') is True, 'update': evidence.get('update_pass') is True, 'compile': evidence.get('compile_pass') is True, 'nominal_smoke': evidence.get('nominal_smoke_pass') is True, 'closed_without_save': evidence.get('model_closed_without_save') is True, 'no_reference_modification': evidence.get('reference_substantive_modifications') == 0}
    audit = evidence.get('static_audit', {})
    checks['physical_closed_loop_core'] = audit.get('core_path_qualified') is True
    rows = {row.get('id'): row for row in evidence.get('scenarios', [])}
    checks['all_required_scenarios'] = set(rows) == set(REQUIRED)
    scenario_valid = checks['all_required_scenarios']
    output_valid = scenario_valid
    input_semantics = scenario_valid
    if scenario_valid:
        for name in REQUIRED:
            row = rows[name]
            scenario_valid &= row.get('valid') is True and row.get('simulation_pass') is True and (row.get('required_evidence_pass') is True) and (row.get('scenario_application_pass') is True)
            outputs = row.get('outputs', {})
            time = outputs.get('time_s')
            requested = row.get('requested_inputs', {})
            output_valid &= isinstance(time, list) and len(time) >= 10 and finite(time) and (abs(float(time[0])) <= 1e-09) and (float(time[-1]) >= float(requested.get('stop_time_s', math.inf)) - 1e-06)
            if output_valid:
                for key, width in OUTPUT_SHAPES.items():
                    output_valid &= matrix_shape(outputs.get(key), len(time), width)
            ball = outputs.get('ball_state', [[math.inf] * 4])
            target = [requested.get('BallInitialX_m', math.inf), requested.get('BallInitialY_m', math.inf), requested.get('BallInitialVX_mps', math.inf), requested.get('BallInitialVY_mps', math.inf)]
            input_semantics &= len(ball) > 0 and all((abs(float(ball[0][index]) - float(target[index])) <= 0.012 for index in range(4)))
            applied = row.get('applied_parameters', {})
            input_semantics &= abs(float(applied.get('ball_mass_kg', math.inf)) - 0.0027 * float(requested.get('BallMassScale', math.inf))) <= 1e-10 and abs(float(applied.get('static_friction', math.inf)) - 0.5 * float(requested.get('ContactFrictionScale', math.inf))) <= 1e-10 and (abs(float(applied.get('corrective_torque_range_Nm', math.inf)) - 0.25 * float(requested.get('TorqueAuthorityScale', math.inf))) <= 1e-10)
    checks['all_scenarios_valid'] = bool(scenario_valid)
    checks['all_required_outputs_valid'] = bool(output_valid)
    checks['scenario_inputs_semantically_effective'] = bool(input_semantics)
    failures = [name for name, passed in checks.items() if not passed]
    return (checks, failures)

def quaternion_tilt(qw: float, qx: float, qy: float, qz: float) -> float:
    roll = math.atan2(2.0 * (qw * qx + qy * qz), 1.0 - 2.0 * (qx * qx + qy * qy))
    pitch = math.asin(max(-1.0, min(1.0, 2.0 * (qw * qy - qz * qx))))
    return math.hypot(roll, pitch)

def sustained_recovery_time(time: list[float], radius: list[float], threshold: float) -> float:
    if len(time) < 2:
        return math.inf
    dt = max(time[1] - time[0], 1e-09)
    count = max(2, round(0.5 / dt))
    for index in range(0, len(time) - count + 1):
        if all((value <= threshold for value in radius[index:index + count])):
            return time[index]
    return math.inf

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    time = list(map(float, outputs['time_s']))
    ball = columns(outputs['ball_state'])
    plate = columns(outputs['plate_state'])
    joint = columns(outputs['actuated_joint_state'])
    control = columns(outputs['control_state'])
    task = columns(outputs['task_state'])
    observation = columns(outputs['observation_state'])
    x, y, vx, vy = ball
    qw, qx, qy, qz, qdw, qdx, qdy, qdz = plate
    j1, dj1, j2, dj2 = joint
    action1, action2, torque1, torque2 = control
    reward, done = task
    radius = [math.hypot(xv, yv) for xv, yv in zip(x, y)]
    speed = [math.hypot(xv, yv) for xv, yv in zip(vx, vy)]
    tilt = [quaternion_tilt(*values) for values in zip(qw, qx, qy, qz)]
    tail_start = max(0, round(0.8 * len(time)))
    tail = list(range(tail_start, len(time)))
    in_plate = [abs(x[index]) <= 0.125 and abs(y[index]) <= 0.125 and (done[index] < 0.5) for index in range(len(time))]
    initial_radius = max(radius[0], 1e-09)
    tail_radius = fmean((radius[index] for index in tail))
    derivative_error: list[float] = []
    derivative_scale: list[float] = []
    for index in range(1, len(time)):
        dt = time[index] - time[index - 1]
        if dt <= 0:
            continue
        measured = [(x[index] - x[index - 1]) / dt, (y[index] - y[index - 1]) / dt]
        reported = [0.5 * (vx[index] + vx[index - 1]), 0.5 * (vy[index] + vy[index - 1])]
        derivative_error.extend((a - b for a, b in zip(measured, reported)))
        derivative_scale.extend(reported)
    applied = row['applied_parameters']
    bias = list(map(float, applied['initial_torque_bias_Nm']))
    authority = float(applied['corrective_torque_range_Nm'])
    actuator_error = [torque1[index] - (bias[0] + authority * action1[index]) for index in range(len(time))] + [torque2[index] - (bias[1] + authority * action2[index]) for index in range(len(time))]
    observation_error = [observation[6][index] - x[index] for index in range(len(time))] + [observation[7][index] - y[index] for index in range(len(time))] + [10.0 * observation[8][index] - vx[index] for index in range(len(time))] + [10.0 * observation[9][index] - vy[index] for index in range(len(time))]
    action_step = [math.hypot(action1[index] - action1[index - 1], action2[index] - action2[index - 1]) for index in range(1, len(time))]
    qnorm_error = [abs(math.sqrt(a * a + b * b + c * c + d * d) - 1.0) for a, b, c, d in zip(qw, qx, qy, qz)]
    return {'initial_radius_m': initial_radius, 'tail_radius_m': tail_radius, 'peak_radius_m': max(radius), 'tail_speed_mps': fmean((speed[index] for index in tail)), 'radius_improvement_fraction': (initial_radius - tail_radius) / initial_radius, 'center_fraction': fmean((value <= 0.04 for value in radius)), 'survival_fraction': fmean(in_plate), 'recovery_time_s': sustained_recovery_time(time, radius, 0.04), 'plate_tilt_rms_deg': math.degrees(rms(tilt)), 'plate_tilt_peak_deg': math.degrees(max(tilt)), 'quaternion_norm_error_peak': max(qnorm_error), 'action_peak': max(max(map(abs, action1)), max(map(abs, action2))), 'action_saturation_fraction': fmean((abs(a) >= 0.98 or abs(b) >= 0.98 for a, b in zip(action1, action2))), 'action_step_p95': percentile(action_step, 0.95), 'action_std': max(pstdev(action1), pstdev(action2)), 'torque_std_Nm': max(pstdev(torque1), pstdev(torque2)), 'joint_rate_rms_radps': rms(dj1 + dj2), 'joint_motion_range_rad': max(max(j1) - min(j1), max(j2) - min(j2)), 'ball_kinematic_relative_error': rms(derivative_error) / max(rms(derivative_scale), 0.01), 'observation_ball_state_rms_error': rms(observation_error), 'actuator_equation_rms_error_Nm': rms(actuator_error), 'mean_objective': fmean(reward), 'done_peak': max(done), 'plate_qd_rms': rms(qdw + qdx + qdy + qdz)}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    checks, failures = qualification(evidence)
    if failures:
        return make_receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, checks, failures)
    rows = {row['id']: row for row in evidence['scenarios']}
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_offset']
    a_parts = {'survival': (high(nominal['survival_fraction'], 0.9, 0.999), 0.25), 'tail_centering': (low(nominal['tail_radius_m'], 0.015, 0.065), 0.25), 'radial_improvement': (high(nominal['radius_improvement_fraction'], 0.3, 0.82), 0.2), 'time_near_center': (high(nominal['center_fraction'], 0.3, 0.82), 0.15), 'plate_attitude': (low(nominal['plate_tilt_rms_deg'], 5.0, 18.0), 0.15)}
    group_a = weighted(a_parts)
    q_parts = {'quaternion_normalization': (min((low(value['quaternion_norm_error_peak'], 0.002, 0.03) for value in metrics.values())), 0.2), 'bounded_plate_tilt': (min((low(value['plate_tilt_peak_deg'], 18.0, 45.0) for value in metrics.values())), 0.25), 'bounded_command': (min((low(value['action_peak'], 1.001, 1.05) for value in metrics.values())), 0.2), 'limited_saturation': (min((low(value['action_saturation_fraction'], 0.06, 0.55) for value in metrics.values())), 0.2), 'command_continuity': (min((low(value['action_step_p95'], 0.25, 1.25) for value in metrics.values())), 0.15)}
    group_q = weighted(q_parts)
    m_parts = {'physical_closed_loop_structure': (1.0, 0.2), 'measured_state_in_observation': (min((low(value['observation_ball_state_rms_error'], 1e-07, 0.002) for value in metrics.values())), 0.2), 'command_to_applied_torque': (min((low(value['actuator_equation_rms_error_Nm'], 1e-07, 0.002) for value in metrics.values())), 0.2), 'ball_position_velocity_consistency': (min((low(value['ball_kinematic_relative_error'], 0.03, 0.3) for value in metrics.values())), 0.15), 'nontrivial_feedback_action': (min((high(value['action_std'], 0.002, 0.035) for value in metrics.values())), 0.1), 'finite_joint_response': (min((weighted({'rate': (high(value['joint_rate_rms_radps'], 0.001, 0.025), 0.5), 'motion': (high(value['joint_motion_range_rad'], 0.002, 0.04), 0.5)}) for value in metrics.values())), 0.15)}
    group_m = weighted(m_parts)
    if min((value['action_std'] for value in metrics.values())) < 1e-05:
        group_m = min(group_m, 0.35)
    r_by_scenario: dict[str, float] = {}
    for name, value in metrics.items():
        r_by_scenario[name] = weighted({'survival': (high(value['survival_fraction'], 0.82, 0.999), 0.35), 'tail_centering': (low(value['tail_radius_m'], 0.022, 0.085), 0.25), 'improvement': (high(value['radius_improvement_fraction'], 0.18, 0.75), 0.2), 'center_fraction': (high(value['center_fraction'], 0.18, 0.7), 0.1), 'plate_boundary': (low(value['peak_radius_m'], 0.115, 0.145), 0.1)})
    group_r = min(r_by_scenario.values())
    near_edge = metrics['near_edge_recovery']
    velocity = metrics['initial_velocity_recovery']
    derated = metrics['actuator_derating']
    d_parts = {'near_edge_survival': (high(near_edge['survival_fraction'], 0.82, 0.999), 0.2), 'near_edge_improvement': (high(near_edge['radius_improvement_fraction'], 0.18, 0.78), 0.2), 'near_edge_recovery_time': (low(near_edge['recovery_time_s'], 4.0, 10.0), 0.1), 'velocity_survival': (high(velocity['survival_fraction'], 0.82, 0.999), 0.15), 'velocity_recovery': (weighted({'tail': (low(velocity['tail_radius_m'], 0.025, 0.085), 0.6), 'speed': (low(velocity['tail_speed_mps'], 0.02, 0.12), 0.4)}), 0.15), 'derated_survival': (high(derated['survival_fraction'], 0.82, 0.999), 0.1), 'derated_centering': (low(derated['tail_radius_m'], 0.025, 0.085), 0.1)}
    group_d = weighted(d_parts)
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'R_by_scenario': r_by_scenario, 'D': d_parts}
    return make_receipt(evidence, groups, total, metrics, diagnostics, checks, [])

def make_receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification_checks: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xrobo08-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification_checks, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['missing_closed_loop_physical_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('ball_state', None)
    cases['missing_required_output'] = score(missing_output)['score']
    direct_ball = copy.deepcopy(evidence)
    direct_ball['static_audit']['spatial_contact_present'] = False
    direct_ball['static_audit']['core_path_qualified'] = False
    cases['direct_ball_position_assignment'] = score(direct_ball)['score']
    no_feedback = copy.deepcopy(evidence)
    no_feedback['static_audit']['observation_to_controller'] = False
    no_feedback['static_audit']['core_path_qualified'] = False
    cases['missing_observation_feedback'] = score(no_feedback)['score']
    inactive = copy.deepcopy(evidence)
    for row in inactive['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['actuated_joint_state'] = [[0.0] * 4 for _ in range(count)]
        row['outputs']['control_state'] = [[0.0] * 4 for _ in range(count)]
    cases['fixed_plate_or_inactive_actuation'] = score(inactive)['score']
    replay = copy.deepcopy(evidence)
    nominal = next((row for row in replay['scenarios'] if row['id'] == 'nominal_offset'))
    for row in replay['scenarios']:
        if row['id'] != 'nominal_offset':
            row['outputs'] = copy.deepcopy(nominal['outputs'])
    cases['replayed_nominal_for_official_conditions'] = score(replay)['score']
    prerecorded = copy.deepcopy(evidence)
    for row in prerecorded['scenarios']:
        count = len(row['outputs']['time_s'])
        action = row['outputs']['control_state'][0][:2]
        torque = row['outputs']['control_state'][0][2:]
        row['outputs']['control_state'] = [action + torque for _ in range(count)]
    cases['prerecorded_constant_action'] = score(prerecorded)['score']
    lost_ball = copy.deepcopy(evidence)
    row = lost_ball['scenarios'][0]
    count = len(row['outputs']['time_s'])
    for index in range(count // 2, count):
        row['outputs']['ball_state'][index][0] = 0.16
        row['outputs']['task_state'][index][1] = 0.0
    cases['success_after_ball_leaves_plate'] = score(lost_ball)['score']
    reward_only = copy.deepcopy(evidence)
    for row in reward_only['scenarios']:
        row['outputs'] = {'time_s': row['outputs']['time_s'], 'task_state': row['outputs']['task_state']}
    cases['objective_without_physical_evidence'] = score(reward_only)['score']
    return {'schema': 'simuverity.f90-xrobo08-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

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
