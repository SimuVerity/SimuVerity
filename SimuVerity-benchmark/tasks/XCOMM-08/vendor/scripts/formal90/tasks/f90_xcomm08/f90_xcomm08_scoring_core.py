"""Pure offline scorer for current F90-XCOMM-08 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = "simuverity-101-v1:f90-xcomm-08:scoring"
WEIGHTS = {'A': 0.25, 'Q': 0.15, 'M': 0.25, 'R': 0.2, 'D': 0.15}
REQUIRED = ['nominal', 'lower_snr', 'transition_snr', 'high_snr', 'alternate_seed_nominal', 'alternate_seed_boundary']

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

def band(value: float, target: float, full_error: float, zero_error: float) -> float:
    return low(abs(value - target), full_error, zero_error)

def weighted(values: list[float], weights: list[float]) -> float:
    return sum((v * w for v, w in zip(values, weights))) / sum(weights)

def effective_snr_error(metrics: dict[str, Any]) -> float:
    """Account for the measured OFDM power relative to AWGN's 1/2048 setting."""
    scaled_power = max(float(metrics['ofdm_scaled_average_power']), 1e-12)
    expected_measured_snr = float(metrics['requested_snr_db']) + 10.0 * math.log10(scaled_power)
    return abs(float(metrics['actual_channel_snr_db']) - expected_measured_snr)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    missing = [name for name in REQUIRED if name not in rows or not rows[name].get('valid')]
    gate = bool(evidence.get('load_pass')) and bool(evidence.get('update_pass')) and bool(evidence.get('compile_pass')) and bool(evidence.get('nominal_smoke_pass')) and bool(static.get('core_path_qualified')) and (not missing)
    failures: list[str] = []
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not static.get('core_path_qualified'):
        failures.append('complete connected coded-OFDM path not qualified')
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, {})
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    nominal = metrics['nominal']
    a_parts = {'outer_ber': low(float(nominal['outer_reported_ber']), 1e-07, 0.015), 'aligned_byte_accuracy': high(float(nominal['aligned_byte_accuracy']), 0.97, 0.9999), 'aligned_packet_accuracy': high(float(nominal['aligned_packet_accuracy']), 0.7, 0.995), 'outer_denominator': high(float(nominal['outer_reported_compared_bit_count']), 10000, 300000)}
    A = weighted(list(a_parts.values()), [0.35, 0.3, 0.2, 0.15])
    q_parts = {'64qam_evm': low(max((float(metrics[name]['qam_rms_evm_to_64qam']) for name in REQUIRED)), 1e-08, 0.15), '64qam_normalized_power': band(float(nominal['qam_average_power']), 1.0, 0.04, 0.3), '64qam_occupancy': high(min((float(metrics[name]['qam_occupied_points']) for name in REQUIRED)), 40, 60), 'ofdm_carrier_contract': weighted([band(float(nominal['ofdm_active_carrier_count']), 1512, 2, 150), high(float(nominal['ofdm_guard_null_fraction']), 0.8, 0.99), band(float(nominal['ofdm_scaled_average_power']), 0.79, 0.08, 0.35)], [0.4, 0.3, 0.3]), 'actual_snr': low(max((effective_snr_error(metrics[name]) for name in REQUIRED)), 0.4, 2.0)}
    Q = weighted(list(q_parts.values()), [0.2, 0.15, 0.15, 0.3, 0.2])
    source_summarys = [float(metrics[name]['source_summary']) for name in REQUIRED]
    recovered_summarys = [float(metrics[name]['recovered_summary']) for name in REQUIRED]
    channel_active = {name: weighted([low(float(metrics[name]['channel_exact_copy_fraction']), 0.01, 0.95), low(effective_snr_error(metrics[name]), 0.4, 2.0)], [0.4, 0.6]) for name in REQUIRED}
    dimension_scores = {name: weighted([band(float(metrics[name]['source_width']), 188, 0, 2), band(float(metrics[name]['rs_codeword_width']), 204, 0, 2), band(float(metrics[name]['inner_coded_width']), 2176, 0, 64), band(float(metrics[name]['qam_width']), 1512, 0, 16), band(float(metrics[name]['tx_ofdm_width']), 2048, 0, 16), band(float(metrics[name]['recovered_width']), 188, 0, 2)], [0.15, 0.15, 0.2, 0.15, 0.2, 0.15]) for name in REQUIRED}
    m_parts = {'connected_complete_path': float(static.get('core_path_qualified', False)), 'stage_dimensions': min(dimension_scores.values()), 'outer_code_is_active': high(min((float(metrics[name]['rs_parity_variation']) for name in REQUIRED)), 1.0, 15.0), 'soft_information_is_real': weighted([high(min((float(metrics[name]['soft_metric_standard_deviation']) for name in REQUIRED)), 0.05, 0.5), high(min((float(metrics[name]['soft_metric_unique_rounded']) for name in REQUIRED)), 4, 25), high(min((float(metrics[name]['soft_metric_nonbinary_fraction']) for name in REQUIRED)), 0.1, 0.8)], [0.35, 0.3, 0.35]), 'channel_is_active': min(channel_active.values()), 'seeds_change_physical_payload': min(high(max(source_summarys) - min(source_summarys), 100, 5000), high(max(recovered_summarys) - min(recovered_summarys), 100, 5000))}
    M = weighted(list(m_parts.values()), [0.2, 0.2, 0.15, 0.15, 0.15, 0.15])
    scenario_scores: dict[str, float] = {}
    for name in REQUIRED:
        row = metrics[name]
        scenario_scores[name] = weighted([low(float(row['outer_reported_ber']), 1e-06, 0.03), high(float(row['aligned_byte_accuracy']), 0.94, 0.999), high(float(row['aligned_packet_accuracy']), 0.4, 0.98), high(float(row['outer_reported_compared_bit_count']), 10000, 250000), low(effective_snr_error(row), 0.4, 2.0), channel_active[name]], [0.3, 0.2, 0.15, 0.15, 0.1, 0.1])
    R = min(scenario_scores.values())
    d_parts = {'outer_delay_alignment': low(max((abs(float(metrics[name]['packet_alignment_lag_frames']) - 17) for name in REQUIRED)), 1, 8), 'inner_warmup': low(max((float(metrics[name]['inner_first_comparison_fraction']) for name in REQUIRED)), 0.03, 0.25), 'outer_warmup': low(max((float(metrics[name]['outer_first_comparison_fraction']) for name in REQUIRED)), 0.05, 0.3), 'denominator_monotonic': float(all((bool(metrics[name]['inner_denominator_monotonic']) and bool(metrics[name]['outer_denominator_monotonic']) for name in REQUIRED))), 'post_warmup_stability': low(max((float(metrics[name]['outer_tail_ber_span']) for name in REQUIRED)), 0.0005, 0.02)}
    D = weighted(list(d_parts.values()), [0.25, 0.15, 0.2, 0.15, 0.25])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for group, weight in WEIGHTS.items():
        total *= max(groups[group], 0.0) ** weight
    shortcut_findings: list[dict[str, str]] = []
    if min((float(metrics[name]['outer_reported_compared_bit_count']) for name in REQUIRED)) <= 0:
        shortcut_findings.append({'reason': 'empty final BER denominator'})
    if max((float(metrics[name]['channel_exact_copy_fraction']) for name in REQUIRED)) > 0.99:
        shortcut_findings.append({'reason': 'AWGN channel is bypassed or inert'})
    if max(source_summarys) - min(source_summarys) < 1e-09:
        shortcut_findings.append({'reason': 'source seed does not change transmitted packets'})
    if max(recovered_summarys) - min(recovered_summarys) < 1e-09:
        shortcut_findings.append({'reason': 'recovered packets are stored or seed-invariant'})
    if m_parts['soft_information_is_real'] < 0.15:
        shortcut_findings.append({'reason': 'required soft demapper is absent or hard-decision only'})
    if min(dimension_scores.values()) < 0.2:
        shortcut_findings.append({'reason': 'required coded-OFDM scale is not implemented'})
    if max((float(metrics[name]['outer_reported_ber']) for name in REQUIRED)) >= min((float(metrics[name]['inner_reported_ber']) for name in REQUIRED)) and all((abs(float(metrics[name]['outer_reported_ber']) - float(metrics[name]['inner_reported_ber'])) < 1e-12 for name in REQUIRED)):
        shortcut_findings.append({'reason': 'outer decoder adds no independently evidenced recovery stage'})
    if min((float(metrics[name]['aligned_compared_bytes']) for name in REQUIRED)) <= 0:
        shortcut_findings.append({'reason': 'no physical packet stream supports the reported BER'})
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'dimension_scores': dimension_scores, 'channel_active_scores': channel_active, 'effective_snr_errors_db': {name: effective_snr_error(metrics[name]) for name in REQUIRED}, 'R_scenario_scores': scenario_scores, 'D_utilities': d_parts, 'shortcut_findings': shortcut_findings}
    failures.extend((f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    failures.extend((item['reason'] for item in shortcut_findings))
    return receipt(evidence, groups, total, failures, diagnostics)

def receipt(evidence: dict[str, Any], groups: dict[str, float], score: float, failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xcomm08-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XCOMM-08', 'formula': 'G*100*A^0.25*Q^0.15*M^0.25*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': bool(groups['G']), 'groups': groups, 'score': float(score), 'admission_score_pass': bool(groups['G'] and score >= 85), 'diagnostics': diagnostics, 'failure_reasons': failures}

def sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}

    def run(name: str, mutant: dict[str, Any]) -> None:
        result = score_evidence(mutant)
        cases[name] = {'score': result['score'], 'G': result['G'], 'pass': result['score'] < 85, 'failure_reasons': result['failure_reasons']}
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'] = [row for row in mutant.get('scenarios', []) if row.get('id') != 'lower_snr']
    run('missing_required_scenario', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['static_audit']['core_path_qualified'] = False
    run('missing_core_chain', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['outer_reported_compared_bit_count'] = 0.0
        row['metrics']['outer_reported_error_count'] = 0.0
        row['metrics']['outer_reported_ber'] = 0.0
    run('copied_zero_ber_without_denominator', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['channel_exact_copy_fraction'] = 1.0
        row['metrics']['channel_normalized_difference'] = 0.0
    run('channel_bypass', mutant)
    mutant = copy.deepcopy(evidence)
    summary = mutant['scenarios'][0]['metrics']['source_summary']
    recovered = mutant['scenarios'][0]['metrics']['recovered_summary']
    for row in mutant['scenarios']:
        row['metrics']['source_summary'] = summary
        row['metrics']['recovered_summary'] = recovered
    run('stored_seed_invariant_packets', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['soft_metric_standard_deviation'] = 0.0
        row['metrics']['soft_metric_unique_rounded'] = 2
        row['metrics']['soft_metric_nonbinary_fraction'] = 0.0
    run('hard_decision_placeholder', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        inner = row['metrics']['inner_reported_ber']
        row['metrics']['outer_reported_ber'] = inner
        row['metrics']['inner_to_outer_ber_reduction'] = 0.0
    run('receiver_stops_after_inner_decoder', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['valid'] = False
    run('empty_or_invalid_logs', mutant)
    return {'schema': 'simuverity.f90-xcomm08-shortcut-sanity.v1', 'task_id': 'F90-XCOMM-08', 'all_pass': all((case['pass'] for case in cases.values())), 'max_shortcut_score': max((case['score'] for case in cases.values())), 'cases': cases}

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
