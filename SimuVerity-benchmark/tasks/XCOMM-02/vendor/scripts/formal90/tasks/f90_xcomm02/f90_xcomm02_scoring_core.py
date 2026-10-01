"""Pure offline scorer for fixed F90-XCOMM-02 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
WEIGHTS = {'A': 0.15, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.2}
REQUIRED = ['nominal', 'mirrored', 'close_strong_interferer', 'low_snr_edge', 'loading_robustness']
POLICY_ID = "simuverity-101-v1:f90-xcomm-02:scoring"

def _clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def _q_low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if zero <= full:
        raise ValueError('q_low requires zero > full')
    return _clamp((zero - value) / (zero - full))

def _q_high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if full <= zero:
        raise ValueError('q_high requires full > zero')
    return _clamp((value - zero) / (full - zero))

def _weighted(values: list[float], weights: list[float]) -> float:
    total = sum(weights)
    return 0.0 if total <= 0 else sum((v * w for v, w in zip(values, weights))) / total

def _scenario_performance(metric: dict[str, Any]) -> tuple[float, dict[str, float]]:
    parts = {'qpsk_preservation': _q_low(float(metric['qpsk_decision_evm']), 0.12, 0.55), 'distortionless_response': _q_low(float(metric['target_response_error_median']), 0.01, 0.15), 'interferer_suppression': _q_high(float(metric['interferer_null_depth_db_median']), 5.0, 22.0), 'finite_stream': float(bool(metric['all_native_values_finite']))}
    return (_weighted(list(parts.values()), [0.35, 0.25, 0.3, 0.1]), parts)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    missing = [name for name in REQUIRED if name not in rows or not bool(rows[name].get('valid'))]
    gate_reasons: list[str] = []
    if not bool(evidence.get('load_pass')):
        gate_reasons.append('reference did not load')
    if not bool(evidence.get('update_pass')):
        gate_reasons.append('model update failed')
    if not bool(evidence.get('compile_pass')):
        gate_reasons.append('model compile failed')
    if not bool(static.get('core_path_qualified')):
        gate_reasons.append('connected covariance-to-weight-to-output path was not qualified')
    if not bool(static.get('fixed_point_evidence')):
        gate_reasons.append('fixed-point/HDL-compatible implementation evidence is missing')
    if missing:
        gate_reasons.append('invalid required scenarios: ' + ', '.join(missing))
    gate = not gate_reasons and bool(evidence.get('model_closed_without_save')) and bool(evidence.get('initfcn', {}).get('disabled_in_loaded_model_only'))
    if not bool(evidence.get('model_closed_without_save')):
        gate_reasons.append('source model was not confirmed closed without save')
    if not bool(evidence.get('initfcn', {}).get('disabled_in_loaded_model_only')):
        gate_reasons.append('in-memory InitFcn isolation was not confirmed')
    if not gate:
        return _receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, gate_reasons, {})
    metrics = {name: rows[name]['summary'] for name in REQUIRED}
    nominal = metrics['nominal']
    scenario_scores: dict[str, float] = {}
    scenario_parts: dict[str, dict[str, float]] = {}
    for name in REQUIRED:
        scenario_scores[name], scenario_parts[name] = _scenario_performance(metrics[name])
    a_parts = {'nominal_qpsk_preservation': _q_low(float(nominal['qpsk_decision_evm']), 0.12, 0.55), 'nominal_target_response': _q_low(float(nominal['target_response_error_median']), 0.01, 0.15)}
    A = _weighted(list(a_parts.values()), [0.6, 0.4])
    q_parts = {'nominal_null_depth': _q_high(float(nominal['interferer_null_depth_db_median']), 5.0, 22.0), 'bounded_noise_gain': _q_low(float(nominal['weight_noise_gain_max']), 1.5, 4.0), 'covariance_fixed_point_agreement': _q_low(float(nominal['covariance_relative_rmse']), 0.02, 0.18), 'loaded_covariance_fixed_point_agreement': _q_low(float(nominal['loaded_covariance_relative_rmse']), 0.02, 0.18), 'finite_and_unsaturated': float(bool(nominal['all_native_values_finite'])) * _q_low(float(nominal['output_peak']), 2.0, 24.0), 'fixed_point_implementation': float(bool(static.get('fixed_point_evidence')))}
    Q = _weighted(list(q_parts.values()), [0.25, 0.1, 0.15, 0.15, 0.1, 0.25])
    distinct_weights = []
    base_real = [float(v) for v in nominal['final_weight_real']]
    base_imag = [float(v) for v in nominal['final_weight_imag']]
    for name in REQUIRED[1:]:
        row_real = [float(v) for v in metrics[name]['final_weight_real']]
        row_imag = [float(v) for v in metrics[name]['final_weight_imag']]
        distance = math.sqrt(sum(((a - b) ** 2 + (c - d) ** 2 for a, b, c, d in zip(base_real, row_real, base_imag, row_imag))))
        distinct_weights.append(distance)
    nominal_output_count = float(nominal['output_valid_count'])
    gap_metric = metrics['loading_robustness']
    invalid_count = float(gap_metric['input_invalid_sample_count'])
    observed_output_deficit = nominal_output_count - float(gap_metric['output_valid_count'])
    if invalid_count > 0:
        output_count_relative_error = abs(observed_output_deficit - invalid_count) / invalid_count
    else:
        output_count_relative_error = math.inf
    gap_output_count_causality = _q_low(output_count_relative_error, 0.05, 0.5)
    gap_covariance_agreement = _q_low(float(gap_metric['covariance_relative_rmse']), 0.02, 0.18)
    valid_gap_adaptation = _weighted([gap_output_count_causality, gap_covariance_agreement], [0.65, 0.35])
    m_parts = {'connected_streaming_mechanism': float(bool(static['core_path_qualified'])), 'measured_covariance_match': _q_low(max((float(metrics[name]['covariance_relative_rmse']) for name in REQUIRED)), 0.02, 0.18), 'loaded_matrix_solve_residual': _q_low(max((float(metrics[name]['solve_residual_max']) for name in REQUIRED)), 0.03, 0.25), 'distortionless_normalization': _q_low(max((float(metrics[name]['target_response_error_median']) for name in REQUIRED)), 0.01, 0.15), 'scenario_dependent_weights': _q_high(min(distinct_weights), 0.01, 0.15), 'valid_gap_adaptation': valid_gap_adaptation}
    M = _weighted(list(m_parts.values()), [0.2, 0.15, 0.2, 0.2, 0.1, 0.15])
    R = min(scenario_scores.values())
    update_intervals = [float(metrics[name]['median_weight_update_interval']) for name in REQUIRED]
    median_update_interval = sorted(update_intervals)[len(update_intervals) // 2]
    cadence_spread = max((abs(value - median_update_interval) / max(median_update_interval, 1.0) for value in update_intervals))
    minimum_update_count = min((float(metrics[name]['weight_update_count']) for name in REQUIRED))
    gap_update_reduction = float(nominal['weight_update_count']) - float(gap_metric['weight_update_count'])
    d_parts = {'first_weight_latency': _q_low(float(nominal['first_weight_valid_tick']), 5000.0, 7000.0), 'first_output_latency': _q_low(float(nominal['first_output_valid_tick']), 5000.0, 7000.0), 'cross_scenario_update_interval_consistency': _q_low(cadence_spread, 0.02, 0.15), 'successive_window_stability': _q_low(float(nominal['successive_weight_change_tail']), 0.08, 0.6), 'multiple_adaptation_updates': _q_high(minimum_update_count, 2.0, 8.0), 'valid_gap_reduces_updates': _q_high(gap_update_reduction, 0.0, 2.0)}
    D = _weighted(list(d_parts.values()), [0.15, 0.15, 0.25, 0.15, 0.15, 0.15])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for name, weight in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** weight
    shortcut_findings: dict[str, float] = {}
    if m_parts['scenario_dependent_weights'] < 0.1:
        shortcut_findings['fixed_or_scenario_invariant_weights'] = 55.0
    if gap_output_count_causality < 0.25:
        shortcut_findings['InputValid_not_causally_respected'] = 60.0
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'R_scenario_scores': scenario_scores, 'R_scenario_utilities': scenario_parts, 'D_utilities': d_parts, 'scenario_weight_distances_from_nominal': dict(zip(REQUIRED[1:], distinct_weights)), 'valid_gap_witness': {'invalid_input_samples': invalid_count, 'observed_output_valid_deficit': observed_output_deficit, 'output_count_relative_error': output_count_relative_error, 'output_count_causality_utility': gap_output_count_causality, 'gap_covariance_agreement_utility': gap_covariance_agreement}, 'cadence_witness': {'per_scenario_median_intervals': dict(zip(REQUIRED, update_intervals)), 'median_interval': median_update_interval, 'relative_spread': cadence_spread, 'minimum_update_count': minimum_update_count, 'gap_update_reduction': gap_update_reduction}, 'shortcut_findings': shortcut_findings}
    failures = [f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6]
    failures.extend((f'shortcut finding: {name}' for name in shortcut_findings))
    return _receipt(evidence, groups, total, metrics, failures, diagnostics)

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    """Score three evidence-level shortcuts against the current observations."""
    cases: dict[str, dict[str, Any]] = {}
    float_only = copy.deepcopy(evidence)
    float_only['static_audit']['fixed_point_evidence'] = False
    cases['float_only'] = score_evidence(float_only)
    fixed_weights = copy.deepcopy(evidence)
    rows = {str(row.get('id')): row for row in fixed_weights.get('scenarios', [])}
    nominal = rows['nominal']['summary']
    for name in REQUIRED[1:]:
        rows[name]['summary']['final_weight_real'] = copy.deepcopy(nominal['final_weight_real'])
        rows[name]['summary']['final_weight_imag'] = copy.deepcopy(nominal['final_weight_imag'])
    cases['fixed_weights'] = score_evidence(fixed_weights)
    ignores_valid = copy.deepcopy(evidence)
    rows = {str(row.get('id')): row for row in ignores_valid.get('scenarios', [])}
    rows['loading_robustness']['summary']['output_valid_count'] = rows['nominal']['summary']['output_valid_count']
    rows['loading_robustness']['summary']['weight_update_count'] = rows['nominal']['summary']['weight_update_count']
    cases['ignores_InputValid'] = score_evidence(ignores_valid)
    compact = {name: {'score': result['score'], 'G': result['G'], 'groups': result['groups'], 'failure_reasons': result['failure_reasons']} for name, result in cases.items()}
    limits = {'float_only': 0.0, 'fixed_weights': 60.0, 'ignores_InputValid': 65.0}
    passed = {name: compact[name]['score'] <= limit for name, limit in limits.items()}
    return {'schema': 'simuverity.f90-xcomm02-shortcut-sanity.v1', 'policy_id': POLICY_ID, 'cases': compact, 'maximum_allowed_scores': limits, 'case_pass': passed, 'all_pass': all(passed.values())}

def _receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xcomm02-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XCOMM-02', 'formula': 'G*100*A^0.15*Q^0.15*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': bool(groups.get('G', 0.0) == 1.0), 'groups': groups, 'score': total, 'admission_score_pass': bool(groups.get('G', 0.0) == 1.0 and total >= 85.0), 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence')
    parser.add_argument('--out')
    parser.add_argument('--shortcut-sanity-out')
    args = parser.parse_args()
    evidence_path = Path(args.evidence)
    evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    receipt = score_evidence(evidence)
    output = Path(args.out) if args.out else evidence_path.with_name('offline_score.json')
    output.write_text(json.dumps(receipt, indent=2, ensure_ascii=False), encoding='utf-8')
    sanity = None
    if args.shortcut_sanity_out:
        sanity = shortcut_sanity(evidence)
        Path(args.shortcut_sanity_out).write_text(json.dumps(sanity, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'score': receipt['score'], 'groups': receipt['groups'], 'out': str(output), 'shortcut_sanity_all_pass': None if sanity is None else sanity['all_pass']}))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
