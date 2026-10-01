"""Pure offline scorer for fixed F90-XMED-07 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XMED-07'
POLICY_ID = 'simuverity-101-v1:f90-xmed-07:scoring'
REQUIRED = ['nominal_normal_bolus', 'slow_large_normal_bolus', 'quick_bolus_profile', 'basal_delivery', 'high_backpressure_basal', 'moderate_restriction_no_alarm', 'severe_occlusion']
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}

def clamp(value: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return min(1.0, max(0.0, value))

def number(value: Any, default: float=math.nan) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result

def low(value: Any, full: float, zero: float) -> float:
    value = number(value)
    if not math.isfinite(value):
        return 0.0
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clamp((zero - value) / (zero - full))

def high(value: Any, zero: float, full: float) -> float:
    value = number(value)
    if not math.isfinite(value):
        return 0.0
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clamp((value - zero) / (full - zero))

def band(value: Any, lower_zero: float, lower_full: float, upper_full: float, upper_zero: float) -> float:
    value = number(value)
    if not math.isfinite(value):
        return 0.0
    return min(high(value, lower_zero, lower_full), low(value, upper_full, upper_zero))

def weighted(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    if denominator <= 0:
        return 0.0
    return clamp(sum((clamp(score) * weight for score, weight in parts.values())) / denominator)

def geometric(groups: dict[str, float]) -> float:
    score = 0.0
    for name, weight in WEIGHTS.items():
        value = clamp(groups[name])
        if value <= 0:
            return 0.0
        score += weight * math.log(value)
    return math.exp(score)

def audit_true(audit: dict[str, Any], names: list[str]) -> bool:
    return all((bool(audit.get(name, False)) for name in names))

def trapezoid(time: list[float], values: list[float]) -> float:
    return sum((0.5 * (values[index] + values[index - 1]) * (time[index] - time[index - 1]) for index in range(1, len(time))))

def percentile(values: list[float], fraction: float) -> float:
    values = sorted(values)
    if not values:
        return math.nan
    position = (len(values) - 1) * fraction
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return values[lower]
    blend = position - lower
    return values[lower] * (1.0 - blend) + values[upper] * blend

def normalized_metrics(row: dict[str, Any]) -> dict[str, Any]:
    """Recompute score metrics from full logs after the native start transient.

    The source's hydraulic network starts with a short pressure equalization
    pulse before command activation at 1 s.  The complete trace remains in
    evidence, but dose and peak-quality metrics are evaluated from 1 s onward
    so that initialization displacement is not counted as commanded delivery.
    """
    result = copy.deepcopy(row['metrics'])
    outputs = row['outputs']
    time = [number(value) for value in outputs['time_s']]
    motion = outputs['motion_state']
    delivery = outputs['delivery_state']
    safety = outputs['safety_state']
    baseline = next((index for index, value in enumerate(time) if value >= 1.0), 0)
    evaluation = range(baseline, len(time))
    reference = [number(item[0], 0.0) for item in motion]
    speed = [number(item[1], 0.0) for item in motion]
    piston = [number(item[3], 0.0) for item in motion]
    upstream_flow = [number(item[0], 0.0) for item in delivery]
    patient_flow = [number(item[1], 0.0) for item in delivery]
    pressure = [number(item[2], 0.0) for item in delivery]
    patient_cumulative = [number(item[3], 0.0) for item in delivery]
    force = [number(item[0], 0.0) for item in safety]
    alarm = [number(item[1], 0.0) for item in safety]
    remaining = [number(item[3], 0.0) for item in safety]
    upstream_cumulative = [number(value, 0.0) for value in outputs['derived']['upstream_cumulative_units']]
    reference_peak = max((abs(reference[index]) for index in evaluation))
    active_threshold = max(0.0001, 0.02 * reference_peak)
    active = [index for index in evaluation if abs(reference[index]) > active_threshold]
    if active:
        errors = [abs(speed[index] - reference[index]) for index in active]
        tracking_rmse = math.sqrt(sum((error * error for error in errors)) / len(errors))
        reference_rms = math.sqrt(sum((reference[index] ** 2 for index in active)) / len(active))
        relative_rmse = tracking_rmse / max(reference_rms, 1e-12)
        tracking_p95 = percentile(errors, 0.95)
        active_flow_mean = sum((patient_flow[index] for index in active)) / len(active)
    else:
        tracking_rmse = math.nan
        relative_rmse = math.nan
        tracking_p95 = math.nan
        active_flow_mean = math.nan
    area_mm2 = math.pi * (0.472 * 25.4) ** 2 / 4.0
    volume_per_unit_mm3 = 15.0
    lead_mm_per_motor_rev = 1.0 / 24.0 * 25.4 / 216.0
    target_rate = [max(reference[index], 0.0) / 60.0 * lead_mm_per_motor_rev * area_mm2 / volume_per_unit_mm3 for index in evaluation]
    target_units = trapezoid([time[index] for index in evaluation], target_rate)
    piston_units = max(0.0, (piston[-1] - piston[baseline]) * area_mm2 / volume_per_unit_mm3)
    patient_units = max(0.0, patient_cumulative[-1] - patient_cumulative[baseline])
    upstream_units = max(0.0, upstream_cumulative[-1] - upstream_cumulative[baseline])
    alarm_onset = number(result.get('occlusion_alarm_onset_s'))
    if math.isfinite(alarm_onset):
        alarm_index = next((index for index, value in enumerate(time) if value >= alarm_onset), len(time) - 1)
        post_alarm_units = max(0.0, patient_cumulative[-1] - patient_cumulative[alarm_index])
        post_alarm_reference = [abs(reference[index]) for index, value in enumerate(time) if value >= alarm_onset + 2.0]
        post_alarm_reference_max = max(post_alarm_reference) if post_alarm_reference else math.nan
    else:
        post_alarm_units = math.nan
        post_alarm_reference_max = math.nan
    active_mask = [abs(reference[index]) > active_threshold for index in evaluation]
    transitions = sum((int(active_mask[index] and (not active_mask[index - 1])) for index in range(1, len(active_mask))))
    occlusion_onset = number(row.get('requested_inputs', {}).get('occlusion_onset_s'))
    occlusion_fraction = number(row.get('requested_inputs', {}).get('occlusion_fraction'), 0.0)
    if occlusion_fraction > 0.0 and math.isfinite(occlusion_onset):
        pre_flow = [max(patient_flow[index], 0.0) for index, value in enumerate(time) if occlusion_onset - 10.0 <= value <= occlusion_onset]
        late_flow = [max(patient_flow[index], 0.0) for index, value in enumerate(time) if value >= time[-1] - 10.0]
        post_occlusion_flow_ratio = sum(late_flow) / max(1, len(late_flow)) / max(max(pre_flow, default=0.0), 1e-09)
    else:
        post_occlusion_flow_ratio = math.nan
    result.update({'reference_speed_peak_RPM': reference_peak, 'measured_speed_peak_RPM': max((abs(speed[index]) for index in evaluation)), 'motor_tracking_rmse_RPM': tracking_rmse, 'motor_tracking_relative_rmse': relative_rmse, 'motor_tracking_p95_error_RPM': tracking_p95, 'active_delivery_transition_count': transitions, 'target_motion_equivalent_units': target_units, 'upstream_delivered_units': upstream_units, 'patient_delivered_units': patient_units, 'piston_displacement_equivalent_units': piston_units, 'patient_to_target_relative_error': abs(patient_units - target_units) / max(target_units, 1e-09), 'piston_to_target_relative_error': abs(piston_units - target_units) / max(target_units, 1e-09), 'patient_to_piston_relative_error': abs(patient_units - piston_units) / max(piston_units, 1e-09), 'upstream_to_patient_relative_error': abs(upstream_units - patient_units) / max(upstream_units, 1e-09), 'patient_flow_mean_active_mm3_per_min': active_flow_mean, 'patient_flow_peak_mm3_per_min': max((patient_flow[index] for index in evaluation)), 'line_pressure_peak_Pa': max((pressure[index] for index in evaluation)), 'load_force_peak_N': max((force[index] for index in evaluation)), 'post_alarm_delivered_units': post_alarm_units, 'post_alarm_reference_speed_max_RPM': post_alarm_reference_max, 'alarm_fraction': sum((alarm[index] > 0.5 for index in evaluation)) / max(1, len(time) - baseline), 'remaining_units_initial': remaining[baseline], 'remaining_units_final': remaining[-1], 'remaining_units_change': remaining[-1] - remaining[baseline], 'startup_exclusion_s': time[baseline], 'post_occlusion_flow_ratio': post_occlusion_flow_ratio})
    result.update(copy.deepcopy(row.get('metrics_override', {})))
    return result

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id', '')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    core_static = ['top_command_to_software', 'top_software_to_motor_plant', 'top_plant_feedback_to_software', 'software_reference_to_motor_controller', 'measured_speed_to_motor_controller', 'measured_speed_to_occlusion_detector', 'load_force_to_occlusion_detector', 'occlusion_to_supervisory', 'remaining_units_to_supervisory', 'physical_motor_present', 'physical_transmission_present', 'physical_slide_present', 'physical_reservoir_present', 'physical_delivery_line_present', 'physical_patient_boundary_present', 'physical_upstream_flow_sensor_present', 'physical_patient_flow_sensor_present', 'native_occlusion_source_present', 'controller_component_models_present']
    qualification = {'load': bool(evidence.get('load_pass', False)), 'update': bool(evidence.get('update_pass', False)), 'compile': bool(evidence.get('compile_pass', False)), 'required_scenario_ids': all((name in rows for name in REQUIRED)), 'all_scenarios_valid': all((bool(rows.get(name, {}).get('valid', False)) for name in REQUIRED)), 'core_static_causal_path': audit_true(static, core_static), 'reference_unmodified': int(evidence.get('reference_substantive_modifications', -1)) == 0}
    failures = [name for name, passed in qualification.items() if not passed]
    if failures:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, failures)
    metrics = {name: normalized_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal_normal_bolus']
    large = metrics['slow_large_normal_bolus']
    quick = metrics['quick_bolus_profile']
    basal = metrics['basal_delivery']
    backpressure = metrics['high_backpressure_basal']
    moderate = metrics['moderate_restriction_no_alarm']
    severe = metrics['severe_occlusion']
    a_parts = {'motor_speed_tracking': (low(nominal['motor_tracking_relative_rmse'], 0.2, 0.5), 0.15), 'piston_follows_reference_motion': (low(nominal['piston_to_target_relative_error'], 0.08, 0.35), 0.25), 'patient_delivery_follows_motion': (low(nominal['patient_to_target_relative_error'], 0.15, 0.65), 0.35), 'physical_volume_consistency': (low(nominal['patient_to_piston_relative_error'], 0.2, 0.75), 0.25)}
    group_a = weighted(a_parts)
    no_fault_names = REQUIRED[:6]
    q_parts = {'motor_voltage_quality': (min((low(metrics[name]['motor_voltage_peak_V'], 5.0, 12.0) for name in no_fault_names)), 0.2), 'line_pressure_quality': (min((low(metrics[name]['line_pressure_peak_Pa'], 6000000.0, 15000000.0) for name in no_fault_names)), 0.2), 'load_force_quality': (min((low(metrics[name]['load_force_peak_N'], 35.0, 90.0) for name in no_fault_names)), 0.15), 'no_false_occlusion': (min((low(metrics[name]['alarm_fraction'], 0.0, 0.02) for name in no_fault_names)), 0.25), 'hydraulic_path_consistency': (min((low(metrics[name]['upstream_to_patient_relative_error'], 0.2, 0.8) for name in no_fault_names if metrics[name]['target_motion_equivalent_units'] > 0.0001)), 0.2)}
    group_q = weighted(q_parts)
    normal_command_effect = abs(large['target_motion_equivalent_units'] - nominal['target_motion_equivalent_units'])
    normal_delivery_effect = abs(large['patient_delivered_units'] - nominal['patient_delivered_units'])
    basal_command_effect = abs(backpressure['target_motion_equivalent_units'] - basal['target_motion_equivalent_units'])
    basal_delivery_effect = abs(backpressure['patient_delivered_units'] - basal['patient_delivered_units'])
    severe_force_rise = severe['load_force_peak_N'] - moderate['load_force_peak_N']
    severe_pressure_rise = severe['line_pressure_peak_Pa'] - moderate['line_pressure_peak_Pa']
    m_parts = {'measured_motor_feedback_path': (float(bool(static['measured_speed_to_motor_controller']) and bool(static['top_plant_feedback_to_software'])), 0.18), 'physical_motor_to_patient_path': (float(bool(static['physical_motor_present']) and bool(static['physical_transmission_present']) and bool(static['physical_slide_present']) and bool(static['physical_reservoir_present']) and bool(static['physical_delivery_line_present'])), 0.18), 'occlusion_feedback_path': (float(bool(static['load_force_to_occlusion_detector']) and bool(static['occlusion_to_supervisory'])), 0.14), 'remaining_drug_feedback_path': (float(bool(static['remaining_units_to_supervisory'])), 0.1), 'normal_command_causality': (min(high(normal_command_effect, 0.05, 0.4), high(normal_delivery_effect, 0.02, 0.2)), 0.12), 'basal_command_and_load_causality': (max(high(basal_command_effect, 0.002, 0.01), high(basal_delivery_effect, 0.001, 0.01)), 0.08), 'restriction_to_physical_response': (max(high(severe_force_rise, 0.5, 3.0), high(severe_pressure_rise, 100000.0, 1000000.0)), 0.1), 'physical_remaining_supervision': (float(bool(static['remaining_units_to_supervisory'])), 0.1)}
    group_m = weighted(m_parts)
    scenario_parts: dict[str, dict[str, tuple[float, float]]] = {}
    scenario_scores: dict[str, float] = {}
    for name in REQUIRED:
        item = metrics[name]
        if name in ('nominal_normal_bolus', 'slow_large_normal_bolus', 'quick_bolus_profile'):
            parts = {'tracking': (low(item['motor_tracking_relative_rmse'], 0.2, 0.55), 0.15), 'piston_motion': (low(item['piston_to_target_relative_error'], 0.1, 0.45), 0.3), 'patient_delivery': (low(item['patient_to_target_relative_error'], 0.2, 0.8), 0.4), 'no_false_alarm': (low(item['alarm_fraction'], 0.0, 0.03), 0.15)}
        elif name in ('basal_delivery', 'high_backpressure_basal'):
            parts = {'physical_low_rate_motion': (high(item['piston_displacement_equivalent_units'], 0.002, 0.02), 0.3), 'patient_delivery_present': (high(item['patient_delivered_units'], 0.002, 0.02), 0.3), 'hydraulic_path_consistency': (low(item['patient_to_piston_relative_error'], 0.1, 0.5), 0.25), 'no_false_alarm': (low(item['alarm_fraction'], 0.0, 0.03), 0.15)}
        elif name == 'moderate_restriction_no_alarm':
            parts = {'no_false_alarm': (low(item['alarm_fraction'], 0.0, 0.03), 0.35), 'tracking': (low(item['motor_tracking_relative_rmse'], 0.2, 0.55), 0.15), 'physical_delivery': (low(item['patient_to_target_relative_error'], 0.3, 0.95), 0.3), 'restriction_remains_physically_coupled': (low(item['patient_to_piston_relative_error'], 0.15, 0.6), 0.2)}
        elif name == 'severe_occlusion':
            parts = {'alarm_detected': (float(math.isfinite(number(item['occlusion_alarm_onset_s']))), 0.35), 'detection_delay': (low(item['occlusion_detection_delay_s'], 20.0, 45.0), 0.25), 'physical_pressure_response': (high(item['line_pressure_peak_Pa'], 250000.0, 500000.0), 0.2), 'patient_flow_curtailment': (low(item['post_occlusion_flow_ratio'], 0.05, 0.3), 0.2)}
        scenario_parts[name] = parts
        scenario_scores[name] = weighted(parts)
    group_r = min(scenario_scores.values())
    quick_transition_advantage = quick['active_delivery_transition_count'] - nominal['active_delivery_transition_count']
    basal_active_fraction = number(rows['basal_delivery']['outputs']['safety_state'][-1][2], 0.0)
    d_parts = {'normal_and_quick_modes_distinct': (high(quick_transition_advantage, 0.0, 2.0), 0.16), 'basal_motion_present': (high(basal['target_motion_equivalent_units'], 0.002, 0.01), 0.12), 'severe_occlusion_detected': (float(math.isfinite(number(severe['occlusion_alarm_onset_s']))), 0.18), 'severe_occlusion_physical_response': (min(high(severe_force_rise, 5.0, 30.0), high(severe_pressure_rise, 50000.0, 250000.0)), 0.18), 'restriction_discrimination': (min(low(moderate['alarm_fraction'], 0.0, 0.03), float(math.isfinite(number(severe['occlusion_alarm_onset_s'])))), 0.16), 'remaining_drug_supervision_connected': (float(bool(static['remaining_units_to_supervisory'])), 0.14), 'backpressure_response': (high(abs(backpressure['line_pressure_peak_Pa'] - basal['line_pressure_peak_Pa']), 10000.0, 50000.0), 0.06)}
    group_d = weighted(d_parts)
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'D': d_parts, 'R_by_scenario': scenario_scores, 'R_parts_by_scenario': scenario_parts, 'paired_effects': {'normal_command_units_delta': normal_command_effect, 'normal_patient_delivery_delta': normal_delivery_effect, 'basal_command_units_delta': basal_command_effect, 'basal_patient_delivery_delta': basal_delivery_effect, 'severe_minus_moderate_force_peak_N': severe_force_rise, 'severe_minus_moderate_pressure_peak_Pa': severe_pressure_rise, 'basal_active_final_flag': basal_active_fraction}}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xmed07-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': float(groups.get('G', 0.0)), 'group_scores': {name: 100.0 * float(groups.get(name, 0.0)) for name in ('A', 'Q', 'M', 'R', 'D')}, 'raw_total_score': float(total), 'qualification': qualification, 'failure_reasons': failures, 'metrics': metrics, 'diagnostics': diagnostics, 'aggregation': {'within_group': 'weighted arithmetic mean', 'critical_multiscenario': '100 percent minimum', 'across_groups': 'weighted geometric mean', 'weights': WEIGHTS}}

def sanity_cases(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    cases: dict[str, dict[str, Any]] = {}
    missing_feedback = copy.deepcopy(evidence)
    missing_feedback['static_audit']['measured_speed_to_motor_controller'] = False
    cases['missing_measured_speed_feedback'] = missing_feedback
    independent_flow = copy.deepcopy(evidence)
    independent_flow['static_audit']['physical_transmission_present'] = False
    cases['independent_flow_without_transmission'] = independent_flow
    scripted_alarm = copy.deepcopy(evidence)
    moderate = next((row for row in scripted_alarm['scenarios'] if row['id'] == 'moderate_restriction_no_alarm'))
    severe = next((row for row in scripted_alarm['scenarios'] if row['id'] == 'severe_occlusion'))
    moderate_metrics = normalized_metrics(moderate)
    severe['metrics_override'] = {'load_force_peak_N': moderate_metrics['load_force_peak_N'], 'line_pressure_peak_Pa': moderate_metrics['line_pressure_peak_Pa'], 'post_occlusion_flow_ratio': 1.0}
    cases['scripted_alarm_without_physical_response'] = scripted_alarm
    ignore_occlusion = copy.deepcopy(evidence)
    severe = next((row for row in ignore_occlusion['scenarios'] if row['id'] == 'severe_occlusion'))
    severe['metrics_override'] = {'occlusion_alarm_onset_s': None, 'occlusion_detection_delay_s': None, 'post_alarm_reference_speed_max_RPM': 1000.0, 'post_alarm_delivered_units': 1.0}
    cases['occlusion_ignored'] = ignore_occlusion
    always_alarm = copy.deepcopy(evidence)
    for row in always_alarm['scenarios']:
        row['metrics_override'] = {'alarm_fraction': 1.0}
        if row['id'] != 'severe_occlusion':
            row['metrics_override']['occlusion_alarm_onset_s'] = 1.0
    cases['always_alarm'] = always_alarm
    fixed_flow = copy.deepcopy(evidence)
    nominal = next((row for row in fixed_flow['scenarios'] if row['id'] == 'nominal_normal_bolus'))
    nominal_metrics = normalized_metrics(nominal)
    for row in fixed_flow['scenarios']:
        if row['id'] != 'nominal_normal_bolus':
            for name in ('target_motion_equivalent_units', 'patient_delivered_units', 'piston_displacement_equivalent_units', 'patient_to_target_relative_error', 'piston_to_target_relative_error', 'patient_to_piston_relative_error'):
                row.setdefault('metrics_override', {})[name] = copy.deepcopy(nominal_metrics[name])
    cases['fixed_or_replayed_delivery'] = fixed_flow
    low_flag = copy.deepcopy(evidence)
    low_flag['static_audit']['remaining_units_to_supervisory'] = False
    cases['low_remaining_disconnected'] = low_flag
    return cases

def shortcut_case_detected(result: dict[str, Any]) -> bool:
    """Require a mutated shortcut to appear in a scored dimension, not via a total cap."""
    groups = result.get('group_scores', {})
    return float(result.get('G', 0.0)) == 0.0 or any(
        float(groups.get(name, 0.0)) < 100.0 for name in ('A', 'Q', 'M', 'R', 'D')
    )

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--shortcut-sanity', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score(evidence)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    if args.shortcut_sanity:
        cases = {name: score(case) for name, case in sanity_cases(evidence).items()}
        sanity = {'schema': 'simuverity.f90-xmed07-shortcut-sanity.v1', 'task_id': TASK_ID, 'case_scores': {name: value['raw_total_score'] for name, value in cases.items()}, 'dimension_level_detection': {name: shortcut_case_detected(value) for name, value in cases.items()}, 'pass': all((shortcut_case_detected(value) for value in cases.values())), 'details': cases}
        args.shortcut_sanity.parent.mkdir(parents=True, exist_ok=True)
        args.shortcut_sanity.write_text(json.dumps(sanity, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
