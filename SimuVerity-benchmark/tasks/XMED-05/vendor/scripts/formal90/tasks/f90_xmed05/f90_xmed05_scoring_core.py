"""Dedicated pure-offline scorer for F90-XMED-05 fixed evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = 'simuverity-101-v1:f90-xmed-05:scoring'
REQUIRED = ['normal_delay', 'bradycardia', 'av_block', 'combined_pathology', 'pvc_retrograde_stress', 'extra_vp_reentry_stress']
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

def number(value: Any, default: float=0.0) -> float:
    """Convert MATLAB JSON numbers, including null encodings of Inf, safely."""
    if value is None:
        return default
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def high(value: Any, zero: float, full: float) -> float:
    value = number(value, -math.inf)
    if not math.isfinite(value) or full <= zero:
        return 0.0
    return clamp((value - zero) / (full - zero))

def low(value: Any, full: float, zero: float) -> float:
    value = number(value, math.inf)
    if not math.isfinite(value) or zero <= full:
        return 0.0
    return clamp((zero - value) / (zero - full))

def band(value: Any, low_full: float, high_full: float, low_zero: float, high_zero: float) -> float:
    value = number(value, math.nan)
    if not math.isfinite(value):
        return 0.0
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return high(value, low_zero, low_full)
    return low(value, high_full, high_zero)

def weighted(values: list[float], weights: list[float]) -> float:
    denominator = sum(weights)
    if denominator <= 0:
        return 0.0
    return sum((value * weight for value, weight in zip(values, weights))) / denominator

def event_count(metrics: dict[str, Any], name: str) -> float:
    return number(metrics.get('event_counts', {}).get(name))

def interval(metrics: dict[str, Any], chamber: str, name: str) -> float:
    return number(metrics.get(f'{chamber}_effective_intervals_ms', {}).get(name), math.inf)

def vector_distance(first: Any, second: Any) -> float:
    """Scale-normalized Euclidean distance between numeric profile vectors."""
    if not isinstance(first, list) or not isinstance(second, list):
        return 0.0
    flat_first = flatten(first)
    flat_second = flatten(second)
    if len(flat_first) != len(flat_second) or not flat_first:
        return 0.0
    numerator = math.sqrt(sum(((a - b) ** 2 for a, b in zip(flat_first, flat_second))))
    scale = max(math.sqrt(sum((a * a for a in flat_first))), math.sqrt(sum((b * b for b in flat_second))), 1.0)
    return numerator / scale

def flatten(value: Any) -> list[float]:
    if isinstance(value, list):
        result: list[float] = []
        for item in value:
            result.extend(flatten(item))
        return result
    try:
        scalar = float(value)
    except (TypeError, ValueError):
        return []
    return [scalar] if math.isfinite(scalar) else []

def profile_column(value: Any, index: int) -> list[float]:
    if not isinstance(value, list):
        return []
    result: list[float] = []
    for row in value:
        if not isinstance(row, list) or len(row) <= index:
            return []
        result.append(number(row[index]))
    return result

def operability(metrics: dict[str, Any]) -> tuple[float, dict[str, float]]:
    parts = {'atrial_rate': band(metrics.get('atrial_effective_rate_bpm'), 42.0, 115.0, 20.0, 190.0), 'ventricular_rate': band(metrics.get('ventricular_effective_rate_bpm'), 42.0, 115.0, 20.0, 190.0), 'atrial_continuity': low(interval(metrics, 'atrial', 'maximum'), 1500, 3000), 'ventricular_continuity': low(interval(metrics, 'ventricular', 'maximum'), 1500, 3000), 'atrial_egm': high(metrics.get('atrial_egm_std'), 1e-06, 0.001), 'ventricular_egm': high(metrics.get('ventricular_egm_std'), 1e-06, 0.001), 'finite': float(bool(metrics.get('all_values_finite')))}
    return (weighted(list(parts.values()), [0.17, 0.23, 0.12, 0.18, 0.1, 0.1, 0.1]), parts)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    failures: list[str] = []
    for key in ('load_pass', 'update_pass', 'compile_pass'):
        if not bool(evidence.get(key)):
            failures.append(f'{key} is false')
    missing = [name for name in REQUIRED if name not in rows or not bool(rows[name].get('simulation_pass')) or (not bool(rows[name].get('valid')))]
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not bool(static.get('minimum_hybrid_closed_loop_signature')):
        failures.append('hybrid closed-loop implementation signature not qualified')
    if not bool(evidence.get('model_closed_without_save')):
        failures.append('model was not closed without save')
    gate = not failures
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, {}, [])
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    nominal = metrics['normal_delay']
    a_parts = {'atrial_rate': band(nominal.get('atrial_effective_rate_bpm'), 45.0, 100.0, 25.0, 150.0), 'ventricular_rate': band(nominal.get('ventricular_effective_rate_bpm'), 45.0, 100.0, 25.0, 150.0), 'atrial_continuity': low(interval(nominal, 'atrial', 'maximum'), 1400, 2600), 'ventricular_continuity': low(interval(nominal, 'ventricular', 'maximum'), 1400, 2600), 'atrioventricular_association': high(nominal.get('av_association_fraction'), 0.25, 0.85), 'intrinsic_atrial_preservation': weighted([high(event_count(nominal, 'atrial_sensed'), 0, 4), low(event_count(nominal, 'atrial_pace'), 1, 8)], [0.65, 0.35])}
    A = weighted(list(a_parts.values()), [0.18, 0.22, 0.12, 0.18, 0.15, 0.15])
    duties = nominal.get('event_pulse_duty_fraction', [])
    pace_duty = max([number(value, 1.0) for value in duties[2:4]] if isinstance(duties, list) and len(duties) >= 4 else [1.0])
    q_parts = {'atrial_egm_activity': high(nominal.get('atrial_egm_std'), 1e-06, 0.001), 'ventricular_egm_activity': high(nominal.get('ventricular_egm_std'), 1e-06, 0.001), 'bounded_pulse_duty': low(pace_duty, 0.03, 0.2), 'upper_rate_protection': min(high(interval(nominal, 'atrial', 'minimum'), 180, 300), high(interval(nominal, 'ventricular', 'minimum'), 180, 300)), 'physiological_av_timing': band(nominal.get('av_delay_median_ms'), 40, 450, 0, 800), 'avoid_simultaneous_pacing': low(nominal.get('simultaneous_pace_fraction'), 0.001, 0.05)}
    Q = weighted(list(q_parts.values()), [0.18, 0.18, 0.14, 0.18, 0.17, 0.15])
    scenario_event_profiles = {name: rows[name].get('profiles', {}).get('events', []) for name in REQUIRED}
    condition_differences = [vector_distance(scenario_event_profiles['normal_delay'], scenario_event_profiles[name]) for name in REQUIRED[1:]]
    egm_channel_differences = [vector_distance(profile_column(rows[name].get('profiles', {}).get('egm', []), 0), profile_column(rows[name].get('profiles', {}).get('egm', []), 1)) for name in REQUIRED]
    detected_channel_differences = [vector_distance(profile_column(rows[name].get('profiles', {}).get('events', []), 0), profile_column(rows[name].get('profiles', {}).get('events', []), 1)) for name in REQUIRED]
    sensing_counts = [event_count(item, 'atrial_sensed') + event_count(item, 'ventricular_sensed') for item in metrics.values()]
    command_count = sum((event_count(item, 'atrial_pace') + event_count(item, 'ventricular_pace') for item in metrics.values()))
    delivered_count = sum((event_count(item, 'atrial_delivered') + event_count(item, 'ventricular_delivered') for item in metrics.values()))
    command_delivery = 1.0 if command_count <= 0 else clamp(delivered_count / command_count)
    capture_values: list[float] = []
    for item in metrics.values():
        if event_count(item, 'atrial_delivered') > 0:
            capture_values.append(number(item.get('atrial_capture_fraction')))
        if event_count(item, 'ventricular_delivered') > 0:
            capture_values.append(number(item.get('ventricular_capture_fraction')))
    pacing_capture = sum(capture_values) / len(capture_values) if capture_values else 0.0
    m_parts = {'hybrid_closed_loop_structure': float(bool(static.get('minimum_hybrid_closed_loop_signature'))), 'sensing_activity': high(sum(sensing_counts), 2.0, 20.0), 'pacing_command_delivery': high(command_delivery, 0.4, 0.95), 'pacing_to_cardiac_response': high(pacing_capture, 0.2, 0.75), 'condition_dependent_response': high(max(condition_differences, default=0.0), 0.01, 0.1), 'multiple_condition_responses': high(sum((value >= 0.025 for value in condition_differences)), 1, 4)}
    M = weighted(list(m_parts.values()), [0.18, 0.15, 0.2, 0.22, 0.15, 0.1])
    per_scenario: dict[str, float] = {}
    per_scenario_parts: dict[str, dict[str, float]] = {}
    for name in REQUIRED:
        per_scenario[name], per_scenario_parts[name] = operability(metrics[name])
    R = min(per_scenario.values())
    brady = metrics['bradycardia']
    av_block = metrics['av_block']
    combined = metrics['combined_pathology']
    pvc = metrics['pvc_retrograde_stress']
    reentry = metrics['extra_vp_reentry_stress']
    d_parts = {'bradycardia_lower_rate_support': weighted([band(brady.get('atrial_effective_rate_bpm'), 42, 90, 20, 150), high(event_count(brady, 'atrial_pace'), 0, 3), high(brady.get('atrial_command_delivery_fraction'), 0.4, 0.9)], [0.45, 0.3, 0.25]), 'av_block_ventricular_support': weighted([band(av_block.get('ventricular_effective_rate_bpm'), 42, 100, 20, 160), high(event_count(av_block, 'ventricular_pace'), 0, 3), high(av_block.get('ventricular_command_delivery_fraction'), 0.4, 0.9)], [0.45, 0.3, 0.25]), 'combined_pathology_continuity': weighted([per_scenario['combined_pathology'], high(event_count(combined, 'atrial_pace') + event_count(combined, 'ventricular_pace'), 0, 4)], [0.65, 0.35]), 'pvc_retrograde_bounded_response': weighted([per_scenario['pvc_retrograde_stress'], band(pvc.get('ventricular_effective_rate_bpm'), 35, 130, 15, 190), low(interval(pvc, 'ventricular', 'minimum'), 300, 120)], [0.45, 0.35, 0.2]), 'reentry_bounded_response': weighted([per_scenario['extra_vp_reentry_stress'], band(reentry.get('ventricular_effective_rate_bpm'), 35, 130, 15, 190), low(interval(reentry, 'ventricular', 'minimum'), 300, 120)], [0.45, 0.35, 0.2])}
    D = weighted(list(d_parts.values()), [0.2, 0.25, 0.2, 0.175, 0.175])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for name, exponent in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** exponent
    shortcut_findings: list[dict[str, Any]] = []

    def record_finding(reason: str, triggered: bool) -> None:
        if triggered:
            shortcut_findings.append({'reason': reason})
    record_finding('rhythm conditions do not materially alter event behavior', max(condition_differences, default=0.0) < 0.01)
    record_finding('accepted sensing path is effectively absent', sum(sensing_counts) < 2)
    record_finding('required pacing support is absent in bradycardia or AV block', event_count(brady, 'atrial_pace') < 1 or event_count(av_block, 'ventricular_pace') < 1)
    record_finding('pacing commands are not delivered to the heart', command_count > 0 and command_delivery < 0.4)
    record_finding('delivered pacing lacks timed cardiac response', delivered_count > 0 and pacing_capture < 0.2)
    record_finding('atrial and ventricular evidence channels are copied', max(egm_channel_differences, default=0.0) < 0.01 and max(detected_channel_differences, default=0.0) < 0.01)
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'R_scenario_scores': per_scenario, 'R_scenario_utilities': per_scenario_parts, 'D_utilities': d_parts, 'condition_event_profile_differences': condition_differences, 'egm_channel_differences': egm_channel_differences, 'detected_channel_differences': detected_channel_differences, 'raw_metrics': metrics}
    return receipt(evidence, groups, total, [], diagnostics, shortcut_findings)

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, failures: list[str], diagnostics: dict[str, Any], shortcut_findings: list[dict[str, Any]]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xmed05-score.v1', 'task_id': 'F90-XMED-05', 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'preferred_reference_score': 90, 'G': groups.get('G') == 1.0, 'groups': groups, 'score': total, 'shortcut_findings': shortcut_findings, 'admission_score_pass': bool(groups.get('G') == 1.0 and total >= 85), 'diagnostics': diagnostics, 'failure_reasons': failures}

def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = evidence.get('scenarios', [])
    if len(rows) != len(REQUIRED) or any((not isinstance(row.get('metrics'), dict) or not row.get('metrics') for row in rows)):
        return {'schema': 'simuverity.f90-xmed05-shortcut-sanity.v1', 'task_id': 'F90-XMED-05', 'variants': {}, 'all_rejected': False, 'precondition_error': 'complete valid fixed evidence is required'}
    variants: dict[str, dict[str, Any]] = {}
    disconnected = copy.deepcopy(evidence)
    disconnected['static_audit']['minimum_hybrid_closed_loop_signature'] = False
    variants['disconnected_hybrid_loop'] = disconnected
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['valid'] = False
    variants['missing_required_output'] = missing_output
    no_sensing = copy.deepcopy(evidence)
    for row in no_sensing['scenarios']:
        metrics = row['metrics']
        metrics['event_counts']['atrial_sensed'] = 0
        metrics['event_counts']['ventricular_sensed'] = 0
        metrics['atrial_effective_rate_bpm'] = 0
        metrics['ventricular_effective_rate_bpm'] = 0
    variants['disconnected_sensing'] = no_sensing
    no_delivery = copy.deepcopy(evidence)
    for row in no_delivery['scenarios']:
        metrics = row['metrics']
        metrics['event_counts']['atrial_delivered'] = 0
        metrics['event_counts']['ventricular_delivered'] = 0
        metrics['atrial_command_delivery_fraction'] = 0
        metrics['ventricular_command_delivery_fraction'] = 0
        metrics['atrial_capture_fraction'] = 0
        metrics['ventricular_capture_fraction'] = 0
    variants['disconnected_pacing_actuation'] = no_delivery
    replay = copy.deepcopy(evidence)
    nominal_metrics = copy.deepcopy(replay['scenarios'][0]['metrics'])
    nominal_profiles = copy.deepcopy(replay['scenarios'][0]['profiles'])
    for row in replay['scenarios'][1:]:
        row['metrics'] = copy.deepcopy(nominal_metrics)
        row['profiles'] = copy.deepcopy(nominal_profiles)
    variants['replayed_nominal_behavior'] = replay
    constant_pacing = copy.deepcopy(evidence)
    nominal_metrics = copy.deepcopy(constant_pacing['scenarios'][0]['metrics'])
    nominal_profiles = copy.deepcopy(constant_pacing['scenarios'][0]['profiles'])
    for row in constant_pacing['scenarios']:
        for name in ('atrial_pace', 'ventricular_pace', 'atrial_delivered', 'ventricular_delivered'):
            row['metrics']['event_counts'][name] = nominal_metrics['event_counts'][name]
        row['profiles']['events'] = copy.deepcopy(nominal_profiles['events'])
    variants['condition_independent_constant_pacing'] = constant_pacing
    copied_channels = copy.deepcopy(evidence)
    for row in copied_channels['scenarios']:
        metrics = row['metrics']
        metrics['event_counts']['ventricular_detected'] = metrics['event_counts']['atrial_detected']
        metrics['event_counts']['ventricular_sensed'] = metrics['event_counts']['atrial_sensed']
        metrics['ventricular_egm_std'] = metrics['atrial_egm_std']
        metrics['ventricular_egm_range'] = metrics['atrial_egm_range']
        metrics['ventricular_capture_fraction'] = 0
        for sample in row['profiles']['egm']:
            sample[1] = sample[0]
        for sample in row['profiles']['events']:
            sample[1] = sample[0]
            sample[5] = sample[4]
    variants['copied_atrial_channels'] = copied_channels
    results: dict[str, Any] = {}
    for name, variant in variants.items():
        result = score_evidence(variant)
        results[name] = {'score': result['score'], 'G': result['G'], 'admission_score_pass': result['admission_score_pass'], 'rejected': not result['admission_score_pass']}
    return {'schema': 'simuverity.f90-xmed05-shortcut-sanity.v1', 'task_id': 'F90-XMED-05', 'variants': results, 'all_rejected': all((item['rejected'] for item in results.values()))}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence_positional', nargs='?')
    parser.add_argument('--evidence')
    parser.add_argument('--output')
    parser.add_argument('--out')
    parser.add_argument('--sanity-output')
    args = parser.parse_args()
    evidence_name = args.evidence or args.evidence_positional
    if not evidence_name:
        parser.error('an evidence path is required')
    evidence_path = Path(evidence_name)
    output_name = args.output or args.out
    output_path = Path(output_name) if output_name else evidence_path.with_name('offline_score.json')
    evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    if args.sanity_output:
        sanity_path = Path(args.sanity_output)
        sanity_path.parent.mkdir(parents=True, exist_ok=True)
        sanity_path.write_text(json.dumps(run_shortcut_sanity(evidence), indent=2, ensure_ascii=False), encoding='utf-8')
    print(output_path)
if __name__ == '__main__':
    main()
