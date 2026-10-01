"""Pure offline scorer for current F90-XCOMM-05 evidence."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = "simuverity-101-v1:f90-xcomm-05:scoring"
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.15, 'R': 0.35, 'D': 0.2}
REQUIRED = ['nominal_qshb', 'nominal_hbps', 'low_snr', 'fast_channel', 'coarse_grid', 'moderate_combined']

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return clamp((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return clamp((value - zero) / (full - zero))

def weighted(values: list[float], weights: list[float]) -> float:
    return sum((v * w for v, w in zip(values, weights))) / sum(weights)

def compatible_scenario(row: dict[str, Any]) -> bool:
    """Accept either compact steering coordinates or full analog matrices."""
    if not bool(row.get('simulation_pass')):
        return False
    metrics = row.get('metrics')
    if not isinstance(metrics, dict):
        return False
    scalar_metrics = {'tx_stream_count', 'rx_stream_count', 'channel_width', 'tx_digital_width', 'tx_analog_width', 'rx_digital_width', 'rx_analog_width', 'tx_digital_nonzero_fraction', 'rx_digital_nonzero_fraction', 'worst_stream_evm_rms', 'minimum_stream_correlation', 'worst_interstream_leakage_ratio', 'worst_window_evm_rms', 'tail_window_evm_rms', 'channel_update_fraction', 'rx_source_exact_fraction'}
    if any((name not in metrics for name in scalar_metrics)):
        return False
    try:
        if any((not math.isfinite(float(metrics[name])) for name in scalar_metrics)):
            return False
        windows = [float(value) for value in metrics.get('window_evm_rms', [])]
    except (TypeError, ValueError):
        return False
    if not windows or any((not math.isfinite(value) for value in windows)):
        return False
    if not (int(metrics['tx_stream_count']) == 2 and int(metrics['rx_stream_count']) == 2 and (int(metrics['channel_width']) == 1024) and (int(metrics['tx_digital_width']) == 8) and (int(metrics['rx_digital_width']) == 8) and (int(metrics['tx_analog_width']) in {8, 256}) and (int(metrics['rx_analog_width']) in {8, 64})):
        return False
    contract = row.get('output_contract', {})
    for name in ('tx_two_complex_streams', 'rx_two_complex_streams', 'channel_16_by_64', 'tx_digital_4_by_2', 'rx_digital_2_by_4', 'channel_update_scalar'):
        if name in contract and (not bool(contract[name])):
            return False
    return True

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    missing = [name for name in REQUIRED if name not in rows or not compatible_scenario(rows[name])]
    gate = bool(evidence.get('load_pass')) and bool(evidence.get('update_pass')) and bool(evidence.get('compile_pass')) and bool(static.get('core_path_qualified')) and (not missing)
    failures: list[str] = []
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not static.get('core_path_qualified'):
        failures.append('hybrid precoder-channel-combiner path not qualified')
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, {})
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    nominal = metrics['nominal_qshb']
    hbps = metrics['nominal_hbps']
    a_parts = {'worst_stream_evm': low(float(nominal['worst_stream_evm_rms']), 0.2, 0.95), 'minimum_stream_correlation': high(float(nominal['minimum_stream_correlation']), 0.25, 0.9), 'interstream_leakage': low(float(nominal['worst_interstream_leakage_ratio']), 0.18, 0.9), 'second_supported_algorithm': weighted([low(float(hbps['worst_stream_evm_rms']), 0.25, 1.0), high(float(hbps['minimum_stream_correlation']), 0.2, 0.85)], [0.55, 0.45])}
    A = weighted(list(a_parts.values()), [0.35, 0.25, 0.2, 0.2])
    q_parts = {'two_stream_dimensions': float(nominal['tx_stream_count'] == 2 and nominal['rx_stream_count'] == 2), 'channel_dimensions': float(nominal['channel_width'] == 1024), 'tx_hybrid_dimensions': float(nominal['tx_digital_width'] == 8 and nominal['tx_analog_width'] in {8, 256}), 'rx_hybrid_dimensions': float(nominal['rx_digital_width'] == 8 and nominal['rx_analog_width'] in {8, 64}), 'nonzero_digital_weights': min(float(nominal['tx_digital_nonzero_fraction']), float(nominal['rx_digital_nonzero_fraction']))}
    Q = weighted(list(q_parts.values()), [0.2, 0.2, 0.2, 0.2, 0.2])
    update_cadence_scores: dict[str, float] = {}
    for name in REQUIRED:
        requested_block = float(rows[name]['requested_inputs']['ChannelCoherenceSymbols'])
        expected_fraction = 1.0 / max(requested_block, 1.0)
        observed_fraction = float(metrics[name]['channel_update_fraction'])
        relative_error = abs(observed_fraction - expected_fraction) / expected_fraction
        update_cadence_scores[name] = low(relative_error, 0.06, 0.35)
    operating_effect = max((abs(float(metrics[name]['worst_stream_evm_rms']) - float(nominal['worst_stream_evm_rms'])) + abs(float(metrics[name]['minimum_stream_correlation']) - float(nominal['minimum_stream_correlation'])) for name in REQUIRED[1:]))
    m_parts = {'connected_channel_weight_path': float(static.get('core_path_qualified', False)), 'complete_nonzero_hybrid_weights': min(float(nominal['tx_digital_nonzero_fraction']), float(nominal['rx_digital_nonzero_fraction'])), 'processing_block_cadence': min(update_cadence_scores.values()), 'operating_inputs_have_effect': high(operating_effect, 0.005, 0.025)}
    M = weighted(list(m_parts.values()), [0.4, 0.2, 0.25, 0.15])
    scenario_scores: dict[str, float] = {}
    for name in REQUIRED:
        row = metrics[name]
        scenario_scores[name] = weighted([low(float(row['worst_stream_evm_rms']), 0.08, 0.45), high(float(row['minimum_stream_correlation']), 0.85, 0.995), low(float(row['worst_interstream_leakage_ratio']), 0.01, 0.35), low(float(row['worst_window_evm_rms']), 0.1, 0.55)], [0.4, 0.25, 0.15, 0.2])
    R = min(scenario_scores.values())
    recovery_ratios = []
    for name in REQUIRED:
        row = metrics[name]
        recovery_ratios.append(float(row['tail_window_evm_rms']) / max(float(row['worst_window_evm_rms']), 1e-12))
    window_peak_ratios = [max((float(value) for value in metrics[name]['window_evm_rms'])) / max(sum((float(value) for value in metrics[name]['window_evm_rms'])) / len(metrics[name]['window_evm_rms']), 1e-12) for name in REQUIRED]
    d_parts = {'processing_block_cadence': min(update_cadence_scores.values()), 'tail_recovery': low(max(recovery_ratios), 0.88, 1.18), 'window_consistency': low(max(window_peak_ratios), 1.1, 1.4)}
    D = weighted(list(d_parts.values()), [0.4, 0.3, 0.3])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for group, weight in WEIGHTS.items():
        total *= max(groups[group], 0.0) ** weight
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'update_cadence_scores': update_cadence_scores, 'R_scenario_scores': scenario_scores, 'D_utilities': d_parts, 'recovery_ratios': dict(zip(REQUIRED, recovery_ratios)), 'window_peak_ratios': dict(zip(REQUIRED, window_peak_ratios))}
    failures.extend((f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    return receipt(evidence, groups, total, failures, diagnostics)

def receipt(evidence: dict[str, Any], groups: dict[str, float], score: float, failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xcomm05-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XCOMM-05', 'formula': 'G*100*A^0.20*Q^0.10*M^0.15*R^0.35*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': bool(groups['G']), 'groups': groups, 'score': float(score), 'admission_score_pass': bool(groups['G'] and score >= 85), 'diagnostics': diagnostics, 'failure_reasons': failures}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'score': result['score'], 'groups': result['groups'], 'out': str(out)}))
if __name__ == '__main__':
    main()
