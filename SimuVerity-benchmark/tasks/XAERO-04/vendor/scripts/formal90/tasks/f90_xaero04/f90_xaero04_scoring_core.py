"""Dedicated pure-offline scorer for F90-XAERO-04 VTOLApp evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XAERO-04'
POLICY_ID = "simuverity-101-v1:f90-xaero-04:scoring"
REQUIRED = {'hover_nominal', 'hover_payload_boundary', 'transition_wind', 'forward_transition', 'transition_payload_wind', 'fixed_wing_turn'}
TRANSITION_SCENARIOS = ('transition_wind', 'forward_transition', 'transition_payload_wind')
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value) or zero <= full:
        return 0.0
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clamp((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value) or full <= zero:
        return 0.0
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clamp((value - zero) / (full - zero))

def weighted(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    if denominator <= 0:
        return 0.0
    return sum((clamp(score) * weight for score, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[key] <= 0 for key in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS)))

def flatten(value: Any) -> list[float]:
    if isinstance(value, list):
        result: list[float] = []
        for item in value:
            result.extend(flatten(item))
        return result
    return [float(value)]

def profile_difference(first: Any, second: Any) -> float:
    a = flatten(first)
    b = flatten(second)
    count = min(len(a), len(b))
    if count == 0:
        return 0.0
    a, b = (a[:count], b[:count])
    numerator = math.sqrt(sum(((x - y) ** 2 for x, y in zip(a, b))))
    denominator = max(math.sqrt(sum((x * x for x in a))), math.sqrt(sum((x * x for x in b))), 1e-06)
    return numerator / denominator

def percentile(values: list[float], percent: float) -> float:
    finite = sorted((value for value in values if math.isfinite(value)))
    if not finite:
        return math.inf
    index = (len(finite) - 1) * percent / 100.0
    lower_index = math.floor(index)
    upper_index = math.ceil(index)
    if lower_index == upper_index:
        return finite[lower_index]
    fraction = index - lower_index
    return finite[lower_index] * (1.0 - fraction) + finite[upper_index] * fraction

def profile_matrix(value: Any) -> list[list[float]]:
    if not isinstance(value, list):
        return []
    result: list[list[float]] = []
    for row in value:
        if isinstance(row, list):
            result.append([float(item) for item in row])
    return result

def robust_motion_metrics(row: dict[str, Any]) -> dict[str, float]:
    vehicle = profile_matrix(row['profiles']['vehicle'])
    actuator = profile_matrix(row['profiles']['actuator'])
    roll_pitch = [abs(sample[index]) for sample in vehicle for index in (6, 7) if len(sample) > index]
    body_rates = [math.sqrt(sum((sample[index] ** 2 for index in (9, 10, 11)))) for sample in vehicle if len(sample) > 11]
    normalized_steps: list[float] = []
    if len(actuator) >= 2:
        channel_count = min((len(sample) for sample in actuator))
        for channel in range(channel_count):
            values = [sample[channel] for sample in actuator]
            span = max(values) - min(values)
            if span <= 1e-09:
                continue
            normalized_steps.extend((abs(values[index] - values[index - 1]) / span for index in range(1, len(values))))
    return {'roll_pitch_p99_rad': percentile(roll_pitch, 99.0), 'body_rate_norm_p99_radps': percentile(body_rates, 99.0), 'actuator_normalized_step_p95': percentile(normalized_steps, 95.0)}

def final_target_altitude_error(row: dict[str, Any]) -> float:
    profile = row.get('requested_inputs', {}).get('MissionProfile', [])
    if not profile or len(profile[-1]) < 4:
        return math.inf
    target_altitude = -float(profile[-1][3])
    actual_altitude = float(row['metrics']['final_altitude_m'])
    return abs(actual_altitude - target_altitude)

def rows(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row['id']): row for row in evidence.get('scenarios', [])}

def scenario_evidence_valid(row: dict[str, Any]) -> bool:
    """Accept a native event-terminated mission when its complete trace was logged."""
    requested = float(row.get('requested_inputs', {}).get('SimulationDuration_s', 0.0))
    minimum_end = min(5.0, requested)
    counts = row.get('sample_counts', {})
    required_counts = (int(counts.get(name, 0)) for name in ('PositionTracking', 'TransitionState', 'VehicleState', 'ActuatorCommand'))
    return bool(row.get('simulation_pass')) and bool(row.get('required_evidence_pass')) and (float(row.get('end_time_s', 0.0)) >= minimum_end - 1e-06) and all((count >= 2 for count in required_counts))

def scenario_operability(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    metric = row['metrics']
    robust = robust_motion_metrics(row)
    mission_kind = int(row['requested_inputs']['MissionKind'])
    if mission_kind == 1:
        tracking = low(float(metric['tail_position_error_rms_m']), 7.0, 35.0)
        progress = high(float(metric['maximum_altitude_m']), 5.0, 15.0)
        dynamic_actuation = high(float(metric['dynamic_actuator_channel_fraction']), 0.4, 0.6)
    elif mission_kind == 2:
        tracking = low(float(metric['transition_altitude_loss_m']), 18.0, 50.0)
        progress = high(float(metric['transition_airspeed_gain_mps']), 2.0, 9.0)
        dynamic_actuation = high(float(metric['dynamic_actuator_channel_fraction']), 0.65, 0.9)
    else:
        tracking = low(final_target_altitude_error(row), 6.0, 25.0)
        progress = high(float(metric['path_travel_m']), 20.0, 100.0)
        dynamic_actuation = high(float(metric['dynamic_actuator_channel_fraction']), 0.65, 0.9)
    parts = {'mission_progress': (progress, 0.2), 'tracking': (tracking, 0.2), 'bounded_attitude': (low(robust['roll_pitch_p99_rad'], 0.75, 1.3), 0.15), 'bounded_body_rate': (low(robust['body_rate_norm_p99_radps'], 1.8, 5.0), 0.1), 'finite_vehicle_state': (1.0 if bool(metric['all_values_finite']) else 0.0, 0.1), 'dynamic_actuation': (dynamic_actuation, 0.15), 'limited_command_jumps': (low(robust['actuator_normalized_step_p95'], 0.2, 0.55), 0.1)}
    return (weighted(parts), parts)

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    by_id = rows(evidence)
    static = evidence.get('static_audit', {})
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'scenario_set': set(by_id) == REQUIRED, 'all_scenarios_valid': set(by_id) == REQUIRED and all((scenario_evidence_valid(by_id[key]) for key in REQUIRED)), 'dynamic_vtol_evidence': bool(static.get('minimum_dynamic_vtol_signature')), 'closed_without_save': bool(evidence.get('model_closed_without_save'))}
    gate = all(qualification.values())
    if not gate:
        return {'schema': 'simuverity.f90-xaero04-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 0.0, 'groups': {key: 0.0 for key in WEIGHTS}, 'group_weights': WEIGHTS, 'score_raw': 0.0, 'admission_threshold_raw': 85.0, 'preferred_reference_target_raw': 90.0, 'admission_pass': False, 'qualification_checks': qualification, 'failures': [key for key, value in qualification.items() if not value]}
    nominal = by_id['hover_nominal']
    nm = nominal['metrics']
    nominal_robust = robust_motion_metrics(nominal)
    a_parts = {'hover_tracking_rms': (low(float(nm['tail_position_error_rms_m']), 5.0, 30.0), 0.25), 'hover_terminal_error': (low(float(nm['terminal_position_error_m']), 6.0, 35.0), 0.15), 'takeoff_altitude': (high(float(nm['maximum_altitude_m']), 6.0, 16.0), 0.2), 'bounded_attitude': (low(nominal_robust['roll_pitch_p99_rad'], 0.35, 0.9), 0.15), 'bounded_body_rate': (low(nominal_robust['body_rate_norm_p99_radps'], 1.2, 3.5), 0.1), 'meaningful_path_motion': (high(float(nm['path_travel_m']), 8.0, 30.0), 0.15)}
    hover_primary_accuracy = weighted(a_parts)
    q_parts = {'finite_outputs': (1.0 if all((bool(by_id[key]['metrics']['all_values_finite']) for key in REQUIRED)) else 0.0, 0.15), 'actuator_channel_activity': (high(sum((float(by_id[key]['metrics']['dynamic_actuator_channel_fraction']) for key in REQUIRED)) / len(REQUIRED), 0.5, 0.85), 0.2), 'actuator_continuity': (low(max((robust_motion_metrics(by_id[key])['actuator_normalized_step_p95'] for key in REQUIRED)), 0.2, 0.55), 0.2), 'front_tilt_pair_consistency': (low(float(nm['front_tilt_pair_rms_difference']), 0.1, 0.4), 0.1), 'limited_command_edge_residence': (low(sum((float(by_id[key]['metrics']['actuator_edge_residence_fraction']) for key in REQUIRED)) / len(REQUIRED), 0.45, 0.8), 0.1), 'distinct_command_and_measurement': (low(float(nm['command_copy_fraction']), 0.8, 0.9999), 0.15), 'smooth_vehicle_motion': (low(max((float(by_id[key]['metrics']['velocity_step_p99_mps']) for key in REQUIRED)), 0.9, 2.5), 0.1)}
    group_q = weighted(q_parts)
    payload = by_id['hover_payload_boundary']
    wind = by_id['transition_wind']
    transition = by_id['forward_transition']
    transition_wind = by_id['transition_payload_wind']
    fixed_wing = by_id['fixed_wing_turn']
    payload_response = max(profile_difference(nominal['profiles']['actuator'], payload['profiles']['actuator']), profile_difference(nominal['profiles']['vehicle'], payload['profiles']['vehicle']))
    wind_response = max(profile_difference(transition['profiles']['vehicle'], wind['profiles']['vehicle']), profile_difference(transition['profiles']['actuator'], wind['profiles']['actuator']))
    transition_response = max(profile_difference(nominal['profiles']['vehicle'], transition['profiles']['vehicle']), profile_difference(nominal['profiles']['actuator'], transition['profiles']['actuator']))
    combined_response = max(profile_difference(wind['profiles']['vehicle'], transition_wind['profiles']['vehicle']), profile_difference(wind['profiles']['actuator'], transition_wind['profiles']['actuator']))
    fixed_wing_response = max(profile_difference(nominal['profiles']['vehicle'], fixed_wing['profiles']['vehicle']), profile_difference(nominal['profiles']['actuator'], fixed_wing['profiles']['actuator']))
    tm = transition['metrics']
    m_parts = {'full_tiltrotor_mechanism': (1.0 if bool(static.get('full_tiltrotor_mechanism')) else 0.0, 0.2), 'closed_loop_feedback_mechanism': (1.0 if bool(static.get('closed_loop_feedback_mechanism')) else 0.0, 0.15), 'payload_causal_response': (high(payload_response, 0.002, 0.035), 0.1), 'wind_causal_response': (high(wind_response, 0.003, 0.055), 0.12), 'forward_transition_response': (high(transition_response, 0.04, 0.2), 0.1), 'transition_tilt_and_airspeed': (min(high(float(tm['front_tilt_range_rad']), 0.1, 0.75), high(float(tm['transition_airspeed_gain_mps']), 2.0, 10.0)), 0.13), 'combined_condition_response': (high(combined_response, 0.002, 0.035), 0.08), 'fixed_wing_mode_response': (high(fixed_wing_response, 0.05, 0.25), 0.12)}
    group_m = weighted(m_parts)
    scenario_scores: dict[str, float] = {}
    scenario_parts: dict[str, Any] = {}
    for key in sorted(REQUIRED):
        scenario_scores[key], scenario_parts[key] = scenario_operability(by_id[key])
    transition_retention = {key: low(float(by_id[key]['metrics']['transition_altitude_loss_m']), 8.0, 35.0) for key in TRANSITION_SCENARIOS}
    transition_retention_worst = min(transition_retention.values())
    transition_airspeed_worst = min((high(float(by_id[key]['metrics']['transition_airspeed_gain_mps']), 2.0, 10.0) for key in TRANSITION_SCENARIOS))
    transition_tilt_worst = min((high(float(by_id[key]['metrics']['front_tilt_range_rad']), 0.1, 0.8) for key in TRANSITION_SCENARIOS))
    transition_completion = min(transition_retention_worst, transition_airspeed_worst, transition_tilt_worst)
    fixed_wing_parts = scenario_parts['fixed_wing_turn']
    fixed_wing_primary_accuracy = min(float(fixed_wing_parts['mission_progress'][0]), float(fixed_wing_parts['tracking'][0]))
    a_mission_utilities = {'hover_primary_accuracy': hover_primary_accuracy, 'transition_altitude_retention_worst': transition_retention_worst, 'fixed_wing_primary_accuracy': fixed_wing_primary_accuracy}
    group_a = weighted({name: (utility, 1.0) for name, utility in a_mission_utilities.items()})
    scenario_operability_worst = min(scenario_scores.values())
    group_r = weighted({'worst_complete_scenario_operability': (scenario_operability_worst, 0.5), 'worst_transition_altitude_retention': (transition_retention_worst, 0.5)})
    wind_metric = wind['metrics']
    fixed_metric = fixed_wing['metrics']
    combined_metric = transition_wind['metrics']
    d_parts = {'hover_takeoff_response': (high(float(nm['maximum_altitude_m']), 5.0, 15.0), 0.15), 'wind_error_recovery': (high(float(wind_metric['tracking_recovery_fraction']), 0.02, 0.55), 0.15), 'transition_completion_bottleneck': (transition_completion, 0.5), 'combined_service_continuity': (low(float(combined_metric['actuator_normalized_step_p99']), 0.2, 0.8), 0.1), 'fixed_wing_turn_progress': (high(float(fixed_metric['path_travel_m']), 25.0, 120.0), 0.1)}
    group_d = weighted(d_parts)
    zero_transition_retention = [key for key, utility in transition_retention.items() if utility <= 0.0]
    groups = {'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    raw = 100.0 * geometric(groups)
    shortcut_findings: list[dict[str, str]] = []
    if float(nm['command_copy_fraction']) > 0.9999:
        shortcut_findings.append({'id': 'position_command_copied_to_measurement'})
    if min((float(by_id[key]['metrics']['dynamic_actuator_channel_fraction']) for key in REQUIRED)) < 0.15:
        shortcut_findings.append({'id': 'constant_or_missing_actuator_channels'})
    replay_difference = max(payload_response, wind_response, transition_response, combined_response, fixed_wing_response)
    if replay_difference < 0.001:
        shortcut_findings.append({'id': 'nominal_output_replayed'})
    if float(tm['front_tilt_range_rad']) < 0.08 or float(tm['transition_airspeed_gain_mps']) < 1.5:
        shortcut_findings.append({'id': 'missing_forward_transition'})
    if payload_response < 0.001 and wind_response < 0.001:
        shortcut_findings.append({'id': 'payload_and_wind_ignored'})
    if not bool(static.get('full_tiltrotor_mechanism')):
        shortcut_findings.append({'id': 'missing_tiltrotor_mechanism'})
    return {'schema': 'simuverity.f90-xaero04-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score_raw': raw, 'admission_threshold_raw': 85.0, 'preferred_reference_target_raw': 90.0, 'admission_pass': raw >= 85.0, 'qualification_checks': qualification, 'details': {'A': {'hover_parts': a_parts, 'mission_utilities': a_mission_utilities, 'aggregation': 'equal-weight three required mission modes'}, 'Q': q_parts, 'M': {'parts': m_parts, 'causal_response': {'payload': payload_response, 'wind': wind_response, 'transition': transition_response, 'combined_service': combined_response, 'fixed_wing': fixed_wing_response}}, 'R': {'aggregation': 'equal-weight arithmetic blend of worst complete-scenario operability and worst required transition retention', 'by_scenario': scenario_scores, 'parts': scenario_parts, 'scenario_operability_worst': scenario_operability_worst, 'transition_retention_worst': transition_retention_worst}, 'D': d_parts, 'transition_retention': {'utility_by_scenario': transition_retention, 'zero_utility_scenarios': zero_transition_retention, 'worst_utility': transition_retention_worst, 'airspeed_worst_utility': transition_airspeed_worst, 'tilt_worst_utility': transition_tilt_worst, 'completion_bottleneck': transition_completion}}, 'shortcut_findings': shortcut_findings, 'failures': list(dict.fromkeys([item['id'] for item in shortcut_findings] + (['transition_altitude_retention_failed'] if zero_transition_retention else [])))}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any], float]] = []
    missing = copy.deepcopy(evidence)
    missing['scenarios'][0]['valid'] = False
    missing['scenarios'][0]['required_evidence_pass'] = False
    cases.append(('missing_required_output', missing, 0.0))
    disconnected = copy.deepcopy(evidence)
    disconnected['static_audit']['minimum_dynamic_vtol_signature'] = False
    cases.append(('missing_dynamic_vtol', disconnected, 0.0))
    copied = copy.deepcopy(evidence)
    copied_nominal = rows(copied)['hover_nominal']
    copied_nominal['metrics']['command_copy_fraction'] = 1.0
    copied_nominal['metrics']['tail_position_error_rms_m'] = 0.0
    copied_nominal['metrics']['terminal_position_error_m'] = 0.0
    cases.append(('command_copied_to_measurement', copied, 55.0))
    constant = copy.deepcopy(evidence)
    for row in constant['scenarios']:
        row['metrics']['dynamic_actuator_channel_fraction'] = 0.0
    cases.append(('constant_actuators', constant, 65.0))
    replay = copy.deepcopy(evidence)
    nominal_profiles = copy.deepcopy(rows(replay)['hover_nominal']['profiles'])
    for row in replay['scenarios']:
        row['profiles'] = copy.deepcopy(nominal_profiles)
    cases.append(('nominal_output_replayed', replay, 60.0))
    no_transition = copy.deepcopy(evidence)
    transition = rows(no_transition)['forward_transition']['metrics']
    transition['front_tilt_range_rad'] = 0.0
    transition['transition_airspeed_gain_mps'] = 0.0
    cases.append(('missing_forward_transition', no_transition, 70.0))
    lost_altitude = copy.deepcopy(evidence)
    for scenario_id in TRANSITION_SCENARIOS:
        rows(lost_altitude)[scenario_id]['metrics']['transition_altitude_loss_m'] = 35.0
    cases.append(('transition_altitude_retention_failed', lost_altitude, 85.0))
    ignored = copy.deepcopy(evidence)
    ignored_rows = rows(ignored)
    nominal_profiles = copy.deepcopy(ignored_rows['hover_nominal']['profiles'])
    ignored_rows['hover_payload_boundary']['profiles'] = copy.deepcopy(nominal_profiles)
    ignored_rows['transition_wind']['profiles'] = copy.deepcopy(ignored_rows['forward_transition']['profiles'])
    cases.append(('payload_and_wind_ignored', ignored, 65.0))
    results = []
    for case_id, mutated, required_maximum in cases:
        scored = score(mutated)
        raw = float(scored['score_raw'])
        results.append({'id': case_id, 'score_raw': raw, 'required_maximum': required_maximum, 'pass': raw <= required_maximum + 1e-09 and raw < 85.0})
    return {'schema': 'simuverity.f90-xaero04-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': results, 'all_rejected': all((item['pass'] for item in results))}

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--sanity-output', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score(evidence)
    write_json(args.output, result)
    if args.sanity_output:
        write_json(args.sanity_output, shortcut_sanity(evidence))
    print(f"{TASK_ID} G={result['G']:.0f} raw={float(result['score_raw']):.6f}")
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
