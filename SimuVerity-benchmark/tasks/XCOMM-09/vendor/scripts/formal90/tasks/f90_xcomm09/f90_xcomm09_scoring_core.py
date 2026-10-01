"""Pure offline scorer for fixed F90-XCOMM-09 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = "simuverity-101-v1:f90-xcomm-09:scoring"
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}
REQUIRED = ['nominal_mcs12_direct', 'snr_margin_mcs12', 'high_mcs14', 'alternate_payload_channel_noise', 'fourier_spatial_mapping']

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def number(value: Any, default: float=math.nan) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result

def json_number(value: float) -> float | None:
    """Keep failure diagnostics strict-JSON without inventing missing evidence."""
    return float(value) if math.isfinite(value) else None

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
    if not values or len(values) != len(weights) or sum(weights) <= 0:
        return 0.0
    return sum((value * weight for value, weight in zip(values, weights))) / sum(weights)

def geometric(groups: dict[str, float]) -> float:
    score = 100.0
    for group, weight in WEIGHTS.items():
        score *= max(float(groups[group]), 0.0) ** weight
    return score

def all_true(mapping: Any) -> bool:
    return isinstance(mapping, dict) and bool(mapping) and all((bool(value) for value in mapping.values()))

def signature(metrics: dict[str, Any]) -> tuple[float, ...]:
    return tuple((number(metrics.get(name)) for name in ('stream1_evm', 'stream2_evm', 'equalized_stream_correlation', 'channel_estimate_rms', 'noise_estimate_mean', 'measured_channel_output_snr_db')))

def signature_distance(left: dict[str, Any], right: dict[str, Any]) -> float:
    a = signature(left)
    b = signature(right)
    if not all((math.isfinite(value) for value in a + b)):
        return 0.0
    return max((abs(x - y) for x, y in zip(a, b)))

def transaction_horizon(rows: dict[str, dict[str, Any]]) -> tuple[bool, dict[str, dict[str, Any]]]:
    diagnostics: dict[str, dict[str, Any]] = {}
    complete = True
    for name in REQUIRED:
        row = rows.get(name, {})
        metrics = row.get('metrics', {})
        requested = number(row.get('requested_inputs', {}).get('packet_transactions', metrics.get('requested_packet_transactions')))
        counts = {'reported': number(metrics.get('reported_compared_packets')), 'manual': number(metrics.get('manual_compared_packets')), 'tx': number(metrics.get('tx_packet_count')), 'rx': number(metrics.get('rx_packet_count'))}
        row_complete = math.isfinite(requested) and requested > 0 and all((math.isfinite(value) and value >= requested for value in counts.values()))
        completed = min(counts.values()) if counts else math.nan
        diagnostics[name] = {'requested_packet_transactions': json_number(requested), 'completed_packet_transactions': json_number(completed), 'counts': {key: json_number(value) for key, value in counts.items()}, 'complete': row_complete}
        complete = complete and row_complete
    return (complete, diagnostics)

def make_receipt(evidence: dict[str, Any], groups: dict[str, float], score: float, failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xcomm09-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XCOMM-09', 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'preferred_reference_score': 90, 'G': bool(groups['G']), 'groups': groups, 'score': float(score), 'admission_score_pass': bool(groups['G'] and score >= 85), 'diagnostics': diagnostics, 'failure_reasons': failures}

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    is_candidate = evidence.get('evaluation_subject') == 'candidate'
    missing = [name for name in REQUIRED if name not in rows or not rows[name].get('valid')]
    horizon_complete, horizon_diagnostics = transaction_horizon(rows)
    if is_candidate:
        structure_qualified = bool(static.get('public_output_sinks_connected'))
        leakage_qualified = bool(static.get('official_channel_state_not_exposed'))
    else:
        structure_qualified = bool(static.get('core_path_qualified'))
        leakage_qualified = bool(static.get('true_channel_leak_absent'))
    gate = bool(evidence.get('load_pass')) and bool(evidence.get('update_pass')) and bool(evidence.get('compile_pass')) and bool(evidence.get('nominal_smoke_pass')) and structure_qualified and leakage_qualified and (not missing) and horizon_complete
    failures: list[str] = []
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not structure_qualified:
        if is_candidate:
            failures.append('one or more declared public output sinks is disconnected')
        else:
            failures.append('causal TGn/AWGN/acquisition/MIMO-recovery path not qualified')
    if not leakage_qualified:
        if is_candidate:
            failures.append('the evaluator boundary exposed official channel state')
        else:
            failures.append('true channel-state leakage is present or not excluded')
    incomplete_horizons = [name for name, row in horizon_diagnostics.items() if not row['complete']]
    if incomplete_horizons:
        failures.append('incomplete fresh packet-transaction horizon: ' + ', '.join(incomplete_horizons))
    if not gate:
        return make_receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, {'transaction_horizon': horizon_diagnostics})
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    nominal = metrics['nominal_mcs12_direct']
    a_parts = {'nominal_reported_per': low(number(nominal['reported_per']), 0.02, 0.35), 'nominal_manual_per': low(number(nominal['manual_per']), 0.02, 0.35), 'nominal_worst_stream_evm': low(number(nominal['worst_stream_evm']), 0.18, 0.6), 'nominal_packet_detection': high(number(nominal['packet_detection_fraction']), 0.75, 0.97)}
    A = weighted(list(a_parts.values()), [0.35, 0.2, 0.3, 0.15])
    denominator_scores = {name: high(min(number(metrics[name]['reported_compared_packets']), number(metrics[name]['manual_compared_packets'])), 32, 60) for name in REQUIRED}
    packet_count_scores = {name: band(min(number(metrics[name]['tx_packet_count']), number(metrics[name]['rx_packet_count'])), 64.0, 2.0, 16.0) for name in REQUIRED}
    q_parts = {'reported_per_internal_consistency': low(max((number(metrics[name]['reported_per_consistency_error']) for name in REQUIRED)), 1e-12, 0.001), 'reported_per_physical_cross_check': low(max((number(metrics[name]['reported_manual_per_difference']) for name in REQUIRED)), 0.02, 0.3), 'complete_packet_horizon': min(packet_count_scores.values()), 'meaningful_packet_denominators': min(denominator_scores.values()), 'finite_receiver_estimates': min((high(number(metrics[name]['channel_estimate_rms']), 1e-09, 0.0001) * high(number(metrics[name]['noise_estimate_mean']), 1e-12, 1e-08) for name in REQUIRED)), 'two_stream_balance': min((low(number(metrics[name]['stream_evm_imbalance']), 0.05, 0.35) for name in REQUIRED))}
    Q = weighted(list(q_parts.values()), [0.2, 0.2, 0.2, 0.15, 0.15, 0.1])
    root_links = static.get('root_causal_links', {})
    acquisition_links = static.get('receiver_acquisition_links', {})
    recovery_links = static.get('recovery_links', {})
    channel_activity = {name: min(high(number(metrics[name]['channel_normalized_difference']), 0.01, 0.12), low(number(metrics[name]['channel_exact_copy_fraction']), 0.01, 0.9)) for name in REQUIRED}
    rank_scores = {name: high(number(metrics[name]['channel_rank2_fraction']), 0.2, 0.9) for name in REQUIRED}
    independent_stream_scores = {name: low(number(metrics[name]['equalized_stream_correlation']), 0.2, 0.98) for name in REQUIRED}
    acquisition_scores = {name: high(number(metrics[name]['packet_detection_fraction']), 0.65, 0.95) for name in REQUIRED}
    if is_candidate:
        causal_path = min(channel_activity.values())
        acquisition_path = min(acquisition_scores.values())
        recovery_path = min(min(rank_scores.values()), min(independent_stream_scores.values()))
        no_channel_leakage = float(bool(static.get('official_channel_state_not_exposed')))
    else:
        causal_path = float(all_true(root_links))
        acquisition_path = float(all_true(acquisition_links))
        recovery_path = float(bool(static.get('receiver_mechanism_blocks_present')) and all_true(recovery_links))
        no_channel_leakage = float(bool(static.get('true_channel_leak_absent')))
    m_parts = {'causal_transmitter_tgn_awgn_receiver_path': causal_path, 'autonomous_acquisition_path': acquisition_path, 'receiver_estimation_and_recovery_path': recovery_path, 'no_true_channel_state_leakage': no_channel_leakage, 'stochastic_channel_has_observable_effect': min(channel_activity.values()), 'rank_two_channel_estimation': min(rank_scores.values()), 'two_distinct_equalized_streams': min(independent_stream_scores.values()), 'packet_acquisition_operates': min(acquisition_scores.values())}
    M = weighted(list(m_parts.values()), [0.15, 0.1, 0.15, 0.1, 0.1, 0.15, 0.15, 0.1])
    scenario_scores: dict[str, float] = {}
    for name in REQUIRED:
        row = metrics[name]
        if name == 'snr_margin_mcs12':
            per_reported = low(number(row['reported_per']), 0.35, 0.85)
            per_manual = low(number(row['manual_per']), 0.35, 0.85)
        else:
            per_reported = low(number(row['reported_per']), 0.03, 0.45)
            per_manual = low(number(row['manual_per']), 0.03, 0.45)
        scenario_scores[name] = weighted([per_reported, per_manual, low(number(row['worst_stream_evm']), 0.2, 0.65), high(number(row['packet_detection_fraction']), 0.65, 0.95), denominator_scores[name], rank_scores[name]], [0.3, 0.15, 0.2, 0.1, 0.1, 0.15])
    R = min(scenario_scores.values())
    nominal_snr = number(nominal['measured_channel_output_snr_db'])
    margin = metrics['snr_margin_mcs12']
    margin_snr = number(margin['measured_channel_output_snr_db'])
    snr_tracking = min(band(nominal_snr, 27.0, 1.5, 5.0), band(margin_snr, 23.0, 1.5, 5.0), band(nominal_snr - margin_snr, 4.0, 1.0, 4.0))
    snr_quality_order = low(max(0.0, number(nominal['reported_per']) - number(margin['reported_per'])), 0.01, 0.15)
    seed = metrics['alternate_payload_channel_noise']
    seed_tx_response = high(max(abs(number(seed['tx_prefix_summary']) - number(nominal['tx_prefix_summary'])), abs(number(seed['tx_suffix_summary']) - number(nominal['tx_suffix_summary']))), 1.0, 500.0)
    seed_rx_response = high(max(abs(number(seed['rx_prefix_summary']) - number(nominal['rx_prefix_summary'])), abs(number(seed['rx_suffix_summary']) - number(nominal['rx_suffix_summary']))), 1.0, 500.0)
    mapping = metrics['fourier_spatial_mapping']
    mapping_response = high(signature_distance(nominal, mapping), 1e-08, 0.001)
    high_mcs = metrics['high_mcs14']
    mcs_response = high(signature_distance(nominal, high_mcs), 1e-08, 0.001)
    d_parts = {'requested_and_measured_snr_track': snr_tracking, 'lower_snr_is_not_artificially_better': snr_quality_order, 'independent_payload_seed_response': seed_tx_response, 'independent_recovered_payload_response': seed_rx_response, 'fourier_mapping_changes_receiver_evidence': mapping_response, 'higher_mcs_changes_receiver_evidence': mcs_response, 'all_declared_modes_remain_functional': min(scenario_scores.values())}
    D = weighted(list(d_parts.values()), [0.2, 0.1, 0.15, 0.15, 0.1, 0.1, 0.2])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = geometric(groups)
    shortcut_findings: list[dict[str, str]] = []
    if not is_candidate and (not all_true(root_links)):
        shortcut_findings.append({'reason': 'missing causal TGn/AWGN link'})
    if not is_candidate and (not static.get('true_channel_leak_absent')):
        shortcut_findings.append({'reason': 'perfect true-channel state reaches receiver'})
    if max((number(metrics[name]['reported_manual_per_difference']) for name in REQUIRED)) > 0.3:
        shortcut_findings.append({'reason': 'reported PER is unsupported by recovered PSDUs'})
    if seed_tx_response <= 0.01:
        shortcut_findings.append({'reason': 'transmitted PSDU is replayed across independent seeds'})
    if seed_rx_response <= 0.01:
        shortcut_findings.append({'reason': 'recovered PSDU is replayed across independent seeds'})
    if min(rank_scores.values()) <= 0.01:
        shortcut_findings.append({'reason': 'receiver does not expose a rank-two channel estimate'})
    if min(independent_stream_scores.values()) <= 0.01:
        shortcut_findings.append({'reason': 'one stream is duplicated as two MIMO streams'})
    if min(channel_activity.values()) <= 0.01:
        shortcut_findings.append({'reason': 'TGn channel is absent or copied through'})
    if mapping_response <= 0.01:
        shortcut_findings.append({'reason': 'spatial-mapping input is fixed or ignored'})
    if mcs_response <= 0.01:
        shortcut_findings.append({'reason': 'MCS input is fixed or ignored'})
    failures.extend((f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    failures.extend((item['reason'] for item in shortcut_findings))
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'R_scenario_scores': scenario_scores, 'D_utilities': d_parts, 'denominator_scores': denominator_scores, 'packet_count_scores': packet_count_scores, 'channel_activity_scores': channel_activity, 'channel_rank_scores': rank_scores, 'independent_stream_scores': independent_stream_scores, 'acquisition_scores': acquisition_scores, 'transaction_horizon': horizon_diagnostics, 'shortcut_findings': shortcut_findings}
    return make_receipt(evidence, groups, total, failures, diagnostics)

def sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}

    def run(name: str, mutant: dict[str, Any]) -> None:
        result = score_evidence(mutant)
        cases[name] = {'score': result['score'], 'G': result['G'], 'pass': result['score'] < 85, 'failure_reasons': result['failure_reasons']}
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'] = [row for row in mutant.get('scenarios', []) if row.get('id') != 'snr_margin_mcs12']
    run('missing_required_evidence', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['static_audit']['core_path_qualified'] = False
    mutant['static_audit']['root_causal_links']['tgn_to_awgn'] = False
    run('missing_tgn_awgn_receiver_path', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['static_audit']['core_path_qualified'] = False
    mutant['static_audit']['receiver_acquisition_links']['waveform_to_recovery'] = False
    run('direct_transmitter_to_decoder_bypass', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['reported_per'] = 0.0
        row['metrics']['reported_packet_errors'] = 0.0
        row['metrics']['reported_per_consistency_error'] = 0.0
        row['metrics']['reported_manual_per_difference'] = 0.7
    run('constant_or_copied_per', mutant)
    mutant = copy.deepcopy(evidence)
    nominal = mutant['scenarios'][0]['metrics']
    seed = mutant['scenarios'][3]['metrics']
    for name in ('tx_prefix_summary', 'tx_suffix_summary', 'rx_prefix_summary', 'rx_suffix_summary'):
        seed[name] = nominal[name]
    run('stored_payload_or_replayed_psdu', mutant)
    mutant = copy.deepcopy(evidence)
    for row in mutant['scenarios']:
        row['metrics']['channel_rank2_fraction'] = 0.0
        row['metrics']['equalized_stream_correlation'] = 1.0
    run('siso_receiver_duplicated_as_two_streams', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['static_audit']['true_channel_leak_absent'] = False
    mutant['static_audit']['true_channel_path_gains_output_disabled'] = False
    run('perfect_true_channel_leakage', mutant)
    mutant = copy.deepcopy(evidence)
    nominal = mutant['scenarios'][0]['metrics']
    for index in (2, 4):
        for name, value in nominal.items():
            if name in mutant['scenarios'][index]['metrics']:
                mutant['scenarios'][index]['metrics'][name] = copy.deepcopy(value)
    run('fixed_mcs_or_spatial_mapping', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'][0]['valid'] = False
    run('empty_or_truncated_packet_evidence', mutant)
    return {'schema': 'simuverity.f90-xcomm09-shortcut-sanity.v1', 'task_id': 'F90-XCOMM-09', 'all_pass': all((case['pass'] for case in cases.values())), 'max_shortcut_score': max((case['score'] for case in cases.values())), 'cases': cases}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf-8')
    summary: dict[str, Any] = {'score': result['score'], 'groups': result['groups'], 'out': str(out)}
    if args.sanity_out:
        sanity = sanity_suite(evidence)
        args.sanity_out.write_text(json.dumps(sanity, indent=2, allow_nan=False), encoding='utf-8')
        summary['sanity'] = {'all_pass': sanity['all_pass'], 'max_shortcut_score': sanity['max_shortcut_score'], 'out': str(args.sanity_out)}
    print(json.dumps(summary, allow_nan=False))
if __name__ == '__main__':
    main()
