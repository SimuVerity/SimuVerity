"""Pure offline scorer for F90-XROBO-10 fixed evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XROBO-10'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-10:scoring'
REQUIRED = ['nominal_line_cycle', 'ball_offset_positive', 'ball_offset_negative']
WEIGHTS = {'A': 0.2, 'Q': 0.2, 'M': 0.25, 'R': 0.2, 'D': 0.15}
JOINT_LIMITS = [(-math.pi, math.pi), (-math.pi, math.pi), (-math.pi, math.pi), (-math.radians(20), math.radians(20)), (-math.pi / 2, math.pi / 2), (-math.pi, math.pi)]

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
    if denominator <= 0:
        return 0.0
    return sum((clamp(score) * weight for score, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[name] * math.log(groups[name]) for name in WEIGHTS)))

def event_map(events: list[list[float]]) -> dict[int, dict[int, list[float]]]:
    output: dict[int, dict[int, list[float]]] = {}
    for time, code, instance in events:
        code_i = int(round(code))
        instance_i = int(round(instance))
        output.setdefault(instance_i, {}).setdefault(code_i, []).append(float(time))
    return output

def completed_product_ids(events: list[list[float]]) -> list[int]:
    products: list[int] = []
    for instance, codes in event_map(events).items():
        required = [3, 4, 6, 8]
        if instance <= 0 or not all((code in codes for code in required)):
            continue
        times = [min(codes[code]) for code in required]
        if times == sorted(times):
            products.append(instance)
    return sorted(products)

def first_event_time(events: list[list[float]], code: int) -> float:
    times = [float(row[0]) for row in events if int(round(row[1])) == code]
    return min(times) if times else math.inf

def scenario_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    time = [float(value) for value in outputs['time_s']]
    start_index = next((i for i, value in enumerate(time) if value >= 2.0), 0)
    tracking: list[float] = []
    torque_values: list[float] = []
    saturation: list[bool] = []
    limit_violations: list[bool] = []
    robot_motion_ranges: list[float] = []
    for robot in (1, 2):
        reference = outputs[f'robot{robot}_joint_reference']
        state = outputs[f'robot{robot}_joint_state']
        torque = outputs[f'robot{robot}_joint_torque']
        for joint, (lower, upper) in enumerate(JOINT_LIMITS):
            ref_values = [float(reference[index][joint]) for index in range(start_index, len(time))]
            state_values = [float(state[index][joint]) for index in range(start_index, len(time))]
            scale = max(max(ref_values) - min(ref_values), 0.25)
            tracking.append(rms([reference[index][joint] - state[index][joint] for index in range(start_index, len(time))]) / scale)
            robot_motion_ranges.append(max(state_values) - min(state_values))
            limit_violations.extend((value < lower - 0.01 or value > upper + 0.01 for value in state_values))
        for index in range(start_index, len(time)):
            for value in torque[index]:
                numeric = float(value)
                torque_values.append(numeric)
                saturation.append(abs(numeric) >= 99.9)
    events = outputs['actor_event_log']
    products = completed_product_ids(events)
    line = outputs['line_supervisor']
    task = outputs['task_state']
    r1_shuttles = {int(round(float(sample[13]))) for sample in line if int(round(float(sample[13]))) > 0}
    r2_shuttles = {int(round(float(sample[15]))) for sample in line if int(round(float(sample[15]))) > 0}
    event_codes = {int(round(float(event[1]))) for event in events}
    unload_times = [float(event[0]) for event in events if int(round(float(event[1]))) == 8]
    unload_intervals = [unload_times[index] - unload_times[index - 1] for index in range(1, len(unload_times))]
    interval_cv = statistics_stdev(unload_intervals) / max(mean(unload_intervals), 1e-09) if len(unload_intervals) >= 2 else math.inf
    return {'position_tracking_worst_joint_nrmse': max(tracking), 'position_tracking_mean_joint_nrmse': mean(tracking), 'joint_limit_violation_fraction': mean([float(value) for value in limit_violations]), 'torque_saturation_fraction': mean([float(value) for value in saturation]), 'torque_rms_Nm': rms(torque_values), 'minimum_robot_joint_motion_range_rad': min(sorted(robot_motion_ranges)[-8:]), 'completed_product_count': float(len(products)), 'first_unload_time_s': first_event_time(events, 8), 'required_actor_event_fraction': mean([float(code in event_codes) for code in [1, 2, 3, 4, 5, 6, 7, 8]]), 'robot1_shuttle_coverage': float(len(r1_shuttles)), 'robot2_shuttle_coverage': float(len(r2_shuttles)), 'robot1_task_active_fraction': mean([float(abs(float(sample[0])) > 0.5) for sample in task]), 'robot2_task_active_fraction': mean([float(abs(float(sample[1])) > 0.5) for sample in task]), 'unload_interval_cv': interval_cv, 'later_cycle_started': float(max((float(sample[16]) for sample in line)) >= 4.0), 'finite_fraction': mean([float(math.isfinite(float(value))) for key, matrix in outputs.items() if key not in {'time_s', 'actor_event_log'} for row_values in matrix for value in row_values])}

def statistics_stdev(values: list[float]) -> float:
    center = mean(values)
    return math.sqrt(sum(((value - center) ** 2 for value in values)) / (len(values) - 1))

def normalized_trace_difference(left: list[list[float]], right: list[list[float]], channels: int=6) -> float:
    if len(left) != len(right) or not left:
        return 0.0
    values = [float(left[index][channel]) - float(right[index][channel]) for index in range(len(left)) for channel in range(channels)]
    return rms(values)

def scenario_performance(metrics: dict[str, float]) -> float:
    return weighted({'products': (high(metrics['completed_product_count'], 0.0, 2.0), 0.3), 'actor_sequence': (metrics['required_actor_event_fraction'], 0.2), 'tracking': (low(metrics['position_tracking_worst_joint_nrmse'], 0.08, 0.45), 0.25), 'joint_limits': (low(metrics['joint_limit_violation_fraction'], 0.0, 0.01), 0.15), 'later_cycle': (metrics['later_cycle_started'], 0.1)})

def qualification(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    for field in ['load_pass', 'update_pass', 'compile_pass', 'nominal_smoke_pass']:
        if not evidence.get(field):
            reasons.append(field)
    rows = {row.get('id'): row for row in evidence.get('scenarios', [])}
    for scenario in REQUIRED:
        if scenario not in rows:
            reasons.append(f'missing_scenario:{scenario}')
        elif not rows[scenario].get('valid'):
            reasons.append(f'invalid_scenario:{scenario}')
    return (not reasons, reasons)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    qualified, failures = qualification(evidence)
    if not qualified:
        return {'schema': 'simuverity.f90-xrobo10-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 0.0, 'groups': {name: 0.0 for name in WEIGHTS}, 'raw_score': 0.0, 'raw_not_rescaled': True, 'failure_reasons': failures, 'metrics': {}, 'shortcut_findings': ['qualification_gate']}
    rows = {row['id']: row for row in evidence['scenarios']}
    metrics = {name: scenario_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_line_cycle']
    static = evidence.get('static_audit', {})
    positive_difference = normalized_trace_difference(rows['nominal_line_cycle']['outputs']['robot2_joint_reference'], rows['ball_offset_positive']['outputs']['robot2_joint_reference'])
    negative_difference = normalized_trace_difference(rows['nominal_line_cycle']['outputs']['robot2_joint_reference'], rows['ball_offset_negative']['outputs']['robot2_joint_reference'])
    offset_response = min(positive_difference, negative_difference)
    groups = {'A': weighted({'completed_products': (high(nominal['completed_product_count'], 0.0, 3.0), 0.3), 'first_unload_latency': (low(nominal['first_unload_time_s'], 20.0, 45.0), 0.2), 'actor_event_sequence': (nominal['required_actor_event_fraction'], 0.2), 'four_shuttle_coverage': (min(nominal['robot1_shuttle_coverage'], nominal['robot2_shuttle_coverage']) / 4.0, 0.15), 'both_workcells_active': (min(high(nominal['robot1_task_active_fraction'], 0.01, 0.08), high(nominal['robot2_task_active_fraction'], 0.01, 0.08)), 0.15)}), 'Q': weighted({'position_tracking': (low(max((value['position_tracking_worst_joint_nrmse'] for value in metrics.values())), 0.08, 0.45), 0.5), 'joint_limits': (low(max((value['joint_limit_violation_fraction'] for value in metrics.values())), 0.0, 0.01), 0.2), 'torque_saturation': (low(max((value['torque_saturation_fraction'] for value in metrics.values())), 0.005, 0.05), 0.15), 'finite_dynamic_evidence': (min((value['finite_fraction'] for value in metrics.values())), 0.15)}), 'M': weighted({'static_two_arm_causal_path': (float(bool(static.get('core_path_qualified'))), 0.45), 'nonzero_joint_motion': (high(min((value['minimum_robot_joint_motion_range_rad'] for value in metrics.values())), 0.01, 0.1), 0.15), 'nonzero_torque': (high(min((value['torque_rms_Nm'] for value in metrics.values())), 0.05, 0.5), 0.15), 'physical_actor_events': (min((value['required_actor_event_fraction'] for value in metrics.values())), 0.15), 'ball_location_response': (high(offset_response, 0.003, 0.015), 0.1)}), 'R': min((scenario_performance(value) for value in metrics.values())), 'D': weighted({'repeated_completed_products': (high(min((value['completed_product_count'] for value in metrics.values())), 0.0, 3.0), 0.35), 'later_shuttle_continuity': (min((value['later_cycle_started'] for value in metrics.values())), 0.2), 'cycle_timing_repeatability': (low(max((value['unload_interval_cv'] for value in metrics.values())), 0.05, 0.35), 0.2), 'offset_recovery': (min(scenario_performance(metrics['ball_offset_positive']), scenario_performance(metrics['ball_offset_negative'])), 0.25)})}
    shortcut_findings: list[str] = []
    if not static.get('two_robot_workcells'):
        shortcut_findings.append('missing_one_robot_workcell')
    if not static.get('core_path_qualified'):
        shortcut_findings.append('broken_reference_torque_dynamics_feedback_path')
    if min((value['required_actor_event_fraction'] for value in metrics.values())) < 0.75:
        shortcut_findings.append('missing_physical_actor_transfer_evidence')
    if min((value['completed_product_count'] for value in metrics.values())) < 1.0:
        shortcut_findings.append('no_completed_product')
    if min((value['robot2_shuttle_coverage'] for value in metrics.values())) < 2.0:
        shortcut_findings.append('first_shuttle_only')
    if offset_response < 0.003:
        shortcut_findings.append('ball_offset_ignored')
    if min((value['torque_rms_Nm'] for value in metrics.values())) < 0.05:
        shortcut_findings.append('missing_actuator_torque')
    raw_fraction = geometric(groups)
    return {'schema': 'simuverity.f90-xrobo10-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 1.0, 'groups': groups, 'raw_score': 100.0 * raw_fraction, 'raw_not_rescaled': True, 'failure_reasons': failures, 'metrics': metrics, 'shortcut_findings': shortcut_findings}

def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any]]] = []
    one_arm = copy.deepcopy(evidence)
    one_arm['static_audit']['two_robot_workcells'] = False
    one_arm['static_audit']['core_path_qualified'] = False
    cases.append(('missing_one_robot_workcell', one_arm))
    invalid = copy.deepcopy(evidence)
    invalid['scenarios'][0]['valid'] = False
    cases.append(('missing_required_outputs', invalid))
    constant = copy.deepcopy(evidence)
    for row in constant['scenarios']:
        for robot in (1, 2):
            for key in [f'robot{robot}_joint_reference', f'robot{robot}_joint_state', f'robot{robot}_joint_torque']:
                matrix = row['outputs'][key]
                row['outputs'][key] = [matrix[0][:] for _ in matrix]
    cases.append(('constant_or_prerecorded_joint_motion', constant))
    broken = copy.deepcopy(evidence)
    broken['static_audit']['robot1_torque_to_dynamics'] = False
    broken['static_audit']['core_path_qualified'] = False
    cases.append(('actor_pose_bypass', broken))
    first_shuttle = copy.deepcopy(evidence)
    for row in first_shuttle['scenarios']:
        for sample in row['outputs']['line_supervisor']:
            sample[13] = min(float(sample[13]), 1.0)
            sample[15] = min(float(sample[15]), 1.0)
    cases.append(('first_shuttle_only_replay', first_shuttle))
    no_events = copy.deepcopy(evidence)
    for row in no_events['scenarios']:
        row['outputs']['actor_event_log'] = []
    cases.append(('declared_transfer_without_actor_events', no_events))
    no_offset = copy.deepcopy(evidence)
    nominal = no_offset['scenarios'][0]['outputs']['robot2_joint_reference']
    for row in no_offset['scenarios'][1:]:
        row['outputs']['robot2_joint_reference'] = copy.deepcopy(nominal)
    cases.append(('ball_offset_ignored', no_offset))
    no_unload = copy.deepcopy(evidence)
    for row in no_unload['scenarios']:
        row['outputs']['actor_event_log'] = [event for event in row['outputs']['actor_event_log'] if int(round(float(event[1]))) != 8]
    cases.append(('unloading_declared_without_completed_product', no_unload))
    zero_torque = copy.deepcopy(evidence)
    for row in zero_torque['scenarios']:
        for robot in (1, 2):
            matrix = row['outputs'][f'robot{robot}_joint_torque']
            row['outputs'][f'robot{robot}_joint_torque'] = [[0.0 for _ in sample] for sample in matrix]
    cases.append(('zero_torque_motion', zero_torque))
    results = []
    for name, mutated in cases:
        score = score_evidence(mutated)
        results.append({'id': name, 'raw_score': score['raw_score'], 'groups': score['groups'], 'shortcut_findings': score['shortcut_findings'], 'pass': score['raw_score'] < 85.0})
    return {'schema': 'simuverity.f90-xrobo10-shortcut-sanity.v1', 'task_id': TASK_ID, 'passed': sum((result['pass'] for result in results)), 'total': len(results), 'maximum_shortcut_score': max((result['raw_score'] for result in results)), 'cases': results}

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--shortcut-output', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    write_json(args.output, result)
    if args.shortcut_output is not None:
        write_json(args.shortcut_output, run_shortcut_sanity(evidence))
    print(json.dumps({'task_id': TASK_ID, 'raw_score': result['raw_score'], 'groups': result['groups'], 'shortcut_findings': result['shortcut_findings']}, ensure_ascii=False))
if __name__ == '__main__':
    main()
