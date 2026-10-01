"""Pure offline scorer for current F90-XCOMM-06 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = "simuverity-101-v1:f90-xcomm-06:scoring"
WEIGHTS = {'A': 0.25, 'Q': 0.15, 'M': 0.25, 'R': 0.2, 'D': 0.15}
REQUIRED = ['nominal_triangle', 'noise_margin', 'negative_carrier', 'phase_quadrant', 'ramp_timing', 'moderate_combined']

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if zero <= full:
        raise ValueError('low utility requires zero > full')
    return clamp((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if full <= zero:
        raise ValueError('high utility requires full > zero')
    return clamp((value - zero) / (full - zero))

def weighted(values: list[float], weights: list[float]) -> float:
    return sum((value * weight for value, weight in zip(values, weights))) / sum(weights)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    missing = [name for name in REQUIRED if name not in rows or not rows[name].get('valid')]
    gate = bool(evidence.get('load_pass')) and bool(evidence.get('update_pass')) and bool(evidence.get('compile_pass')) and bool(evidence.get('nominal_smoke_pass')) and bool(static.get('core_path_qualified')) and (not missing)
    failures: list[str] = []
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not static.get('core_path_qualified'):
        failures.append('end-to-end transmitter-channel-receiver path not qualified')
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, {})
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    nominal = metrics['nominal_triangle']
    a_parts = {'reported_ber': low(float(nominal['reported_ber']), 1e-05, 0.02), 'payload_bit_accuracy': high(float(nominal['bit_accuracy']), 0.95, 0.9995), 'synchronized_constellation': low(float(nominal['rx_synchronized_evm']), 0.2, 0.65), 'valid_frame_recovery': high(float(nominal['post_acquisition_valid_fraction']), 0.6, 0.95)}
    A = weighted(list(a_parts.values()), [0.35, 0.3, 0.2, 0.15])
    denominator_scores = {name: high(float(metrics[name]['reported_compared_bit_count']), 10000, 150000) for name in REQUIRED}
    physical_error_count_scores = {name: 1.0 - abs(float(metrics[name]['reported_error_count']) - float(metrics[name]['calculated_error_count'])) / max(float(metrics[name]['reported_error_count']), float(metrics[name]['calculated_error_count']), 1.0) for name in REQUIRED}
    q_parts = {'physical_error_count_agreement': min(physical_error_count_scores.values()), 'worst_constellation_evm': low(max((float(metrics[name]['rx_synchronized_evm']) for name in REQUIRED)), 0.24, 0.7), 'worst_residual_cfo': low(max((float(metrics[name]['residual_cfo_hz']) for name in REQUIRED)), 8.0, 180.0), 'ber_denominator_integrity': min(denominator_scores.values()), 'frame_continuity': high(min((float(metrics[name]['post_acquisition_valid_fraction']) for name in REQUIRED)), 0.55, 0.95)}
    Q = weighted(list(q_parts.values()), [0.3, 0.175, 0.175, 0.175, 0.175])
    channel_active_scores = {name: weighted([low(float(metrics[name]['channel_exact_copy_fraction']), 0.01, 0.95), high(float(metrics[name]['channel_normalized_difference']), 0.02, 0.2)], [0.55, 0.45]) for name in REQUIRED}
    delay_profile_scores = {name: delay_profile_utility(rows[name], metrics[name]) for name in REQUIRED}
    bit_cross_check_scores = {name: weighted([low(abs(float(metrics[name]['calculated_ber']) - float(metrics[name]['reported_ber'])), 0.008, 0.05), low(abs(float(metrics[name]['tx_prefix_summary']) - float(metrics[name]['rx_prefix_summary'])), 80.0, 400.0), physical_error_count_scores[name]], [0.1, 0.1, 0.8]) for name in REQUIRED}
    tx_prefixes = [float(metrics[name]['tx_prefix_summary']) for name in REQUIRED]
    rx_prefixes = [float(metrics[name]['rx_prefix_summary']) for name in REQUIRED]
    payload_response = min(high(max(tx_prefixes) - min(tx_prefixes), 20.0, 120.0), high(max(rx_prefixes) - min(rx_prefixes), 20.0, 120.0))
    m_parts = {'connected_end_to_end_path': float(static.get('core_path_qualified', False)), 'impaired_channel_is_active': min(channel_active_scores.values()), 'actual_delay_profiles': min(delay_profile_scores.values()), 'payload_shift_has_causal_effect': payload_response, 'reported_ber_matches_physical_bits': min(bit_cross_check_scores.values())}
    M = weighted(list(m_parts.values()), [0.15, 0.15, 0.15, 0.15, 0.4])
    scenario_scores: dict[str, float] = {}
    for name in REQUIRED:
        row = metrics[name]
        scenario_scores[name] = weighted([low(float(row['reported_ber']), 0.0001, 0.05), high(float(row['bit_accuracy']), 0.92, 0.998), high(float(row['post_acquisition_valid_fraction']), 0.5, 0.92), low(float(row['rx_synchronized_evm']), 0.25, 0.75), low(float(row['residual_cfo_hz']), 10.0, 220.0), high(delay_profile_scores[name], 0.45, 0.9)], [0.25, 0.2, 0.15, 0.15, 0.1, 0.15])
    R = min(scenario_scores.values())
    worst_acquisition = max((float(metrics[name]['acquisition_fraction']) for name in REQUIRED))
    worst_invalid_run = max((float(metrics[name]['longest_post_acquisition_invalid_fraction']) for name in REQUIRED))
    d_parts = {'cold_start_acquisition': low(worst_acquisition, 0.03, 0.3), 'post_acquisition_continuity': low(worst_invalid_run, 0.01, 0.2), 'tracking_under_delay_motion': high(min((float(metrics[name]['post_acquisition_valid_fraction']) for name in ['ramp_timing', 'nominal_triangle', 'moderate_combined'])), 0.55, 0.95), 'ramp_and_triangle_delay_realized': min((delay_profile_scores[name] for name in ['ramp_timing', 'nominal_triangle', 'moderate_combined']))}
    D = weighted(list(d_parts.values()), [0.3, 0.25, 0.25, 0.2])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for group, weight in WEIGHTS.items():
        total *= max(groups[group], 0.0) ** weight
    shortcut_findings: list[dict[str, str]] = []
    if min((float(metrics[name]['reported_compared_bit_count']) for name in REQUIRED)) <= 0:
        shortcut_findings.append({'reason': 'zero compared-bit denominator'})
    if min((float(metrics[name]['channel_exact_copy_fraction']) for name in REQUIRED)) > 0.99:
        shortcut_findings.append({'reason': 'transmitter bypasses the impaired channel'})
    if all((float(metrics[name]['frame_valid_fraction']) > 0.999 and float(metrics[name]['acquisition_fraction']) == 0.0 for name in REQUIRED)):
        shortcut_findings.append({'reason': 'frame-valid output is permanently asserted'})
    if max(rx_prefixes) - min(rx_prefixes) < 1e-09 and max(tx_prefixes) - min(tx_prefixes) > 20:
        shortcut_findings.append({'reason': 'decoded payload ignores the public payload shift'})
    if min(delay_profile_scores.values()) < 0.2:
        shortcut_findings.append({'reason': 'time-varying delay input is ignored or fixed'})
    if max((float(metrics[name]['residual_cfo_hz']) for name in ['negative_carrier', 'phase_quadrant', 'moderate_combined'])) > 300:
        shortcut_findings.append({'reason': 'carrier correction does not cover the declared offsets'})
    if min(bit_cross_check_scores.values()) < 0.2:
        shortcut_findings.append({'reason': 'reported BER is not supported by the physical bit streams'})
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'channel_active_scores': channel_active_scores, 'delay_profile_scores': delay_profile_scores, 'bit_cross_check_scores': bit_cross_check_scores, 'physical_error_count_scores': physical_error_count_scores, 'R_scenario_scores': scenario_scores, 'D_utilities': d_parts, 'worst_acquisition_fraction': worst_acquisition, 'worst_post_acquisition_invalid_fraction': worst_invalid_run, 'shortcut_findings': shortcut_findings}
    failures.extend((f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    failures.extend((item['reason'] for item in shortcut_findings))
    return receipt(evidence, groups, total, failures, diagnostics)

def delay_profile_utility(row: dict[str, Any], metrics: dict[str, Any]) -> float:
    """Score only motion observable inside the current evidence horizon."""
    requested = row['requested_inputs']
    step = float(requested['TimingStep_samples_per_frame'])
    span = float(requested['TimingSpan_samples'])
    samples = max(int(metrics['frame_valid_sample_count']), 1)
    observable_span = min(span, step * max(samples - 1, 0))
    observed_span = float(metrics['delay_span_samples'])
    observed_step = float(metrics['delay_step_median_samples'])
    span_score = low(abs(observed_span - observable_span), 0.05, 0.5)
    step_score = low(abs(observed_step - step) / max(step, 1e-12), 0.05, 0.5)
    turns = int(metrics['delay_turn_count'])
    profile = str(requested['TimingProfile'])
    reaches_boundary = step * max(samples - 1, 0) >= span - 0.5 * step
    if profile == 'Triangle' and reaches_boundary:
        shape_score = float(turns >= 1)
    else:
        shape_score = float(turns == 0)
    return weighted([span_score, step_score, shape_score], [0.4, 0.35, 0.25])

def receipt(evidence: dict[str, Any], groups: dict[str, float], score: float, failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xcomm06-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XCOMM-06', 'formula': 'G*100*A^0.25*Q^0.15*M^0.25*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': bool(groups['G']), 'groups': groups, 'score': float(score), 'admission_score_pass': bool(groups['G'] and score >= 85), 'diagnostics': diagnostics, 'failure_reasons': failures}

def sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}

    def run(name: str, mutant: dict[str, Any]) -> None:
        result = score_evidence(mutant)
        cases[name] = {'score': result['score'], 'G': result['G'], 'pass': result['score'] < 85, 'failure_reasons': result['failure_reasons']}
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'] = [row for row in mutant.get('scenarios', []) if row.get('id') != 'noise_margin']
    run('missing_required_scenario', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['channel_exact_copy_fraction'] = 1.0
        row['metrics']['channel_normalized_difference'] = 0.0
    run('channel_bypass', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['reported_compared_bit_count'] = 0.0
        row['metrics']['reported_error_count'] = 0.0
        row['metrics']['reported_ber'] = 0.0
    run('empty_ber_denominator', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['frame_valid_fraction'] = 1.0
        row['metrics']['post_acquisition_valid_fraction'] = 1.0
        row['metrics']['acquisition_fraction'] = 0.0
    run('forced_frame_valid', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['delay_profile_match'] = 0.0
        row['metrics']['delay_span_samples'] = 0.0
        row['metrics']['delay_step_median_samples'] = 0.0
        row['metrics']['delay_turn_count'] = 0
    run('fixed_delay', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        if row['id'] in {'negative_carrier', 'phase_quadrant', 'moderate_combined'}:
            row['metrics']['residual_cfo_hz'] = 1000.0
    run('fixed_carrier_correction', mutant)
    mutant = copy.deepcopy(evidence)
    first_summary = mutant['scenarios'][0]['metrics']['rx_prefix_summary']
    for row in mutant['scenarios']:
        row['metrics']['rx_prefix_summary'] = first_summary
    run('hardcoded_payload', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['static_audit']['core_path_qualified'] = False
    run('missing_core_mechanism', mutant)
    return {'schema': 'simuverity.f90-xcomm06-shortcut-sanity.v1', 'task_id': 'F90-XCOMM-06', 'all_pass': all((case['pass'] for case in cases.values())), 'max_shortcut_score': max((case['score'] for case in cases.values())), 'cases': cases}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    summary: dict[str, Any] = {'score': result['score'], 'groups': result['groups'], 'out': str(out)}
    if args.sanity_out:
        sanity = sanity_suite(evidence)
        args.sanity_out.write_text(json.dumps(sanity, indent=2), encoding='utf-8')
        summary['sanity'] = {'all_pass': sanity['all_pass'], 'max_shortcut_score': sanity['max_shortcut_score'], 'out': str(args.sanity_out)}
    print(json.dumps(summary))
if __name__ == '__main__':
    main()
