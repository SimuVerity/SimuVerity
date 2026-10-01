"""Pure offline scorer for fixed F90-XCOMM-04 evidence."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = "simuverity-101-v1:f90-xcomm-04:scoring"
REQUIRED = ['nominal', 'low_drive', 'high_drive', 'mild_nonlinearity', 'strong_nonlinearity']
WEIGHTS = {'A': 0.25, 'Q': 0.2, 'M': 0.25, 'R': 0.2, 'D': 0.1}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value) or full <= zero:
        return 0.0
    return clamp((value - zero) / (full - zero))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value) or zero <= full:
        return 0.0
    return clamp((zero - value) / (zero - full))

def interval(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return min(high(value, low_zero, low_full), low(value, high_full, high_zero))

def weighted(values: list[float], weights: list[float]) -> float:
    denominator = sum(weights)
    return 0.0 if denominator <= 0 else sum((value * weight for value, weight in zip(values, weights))) / denominator

def metric(row: dict[str, Any], name: str) -> float:
    return float(row['raw_metrics'][name])

def performance(row: dict[str, Any]) -> tuple[float, dict[str, float]]:
    parts = {'aligned_nmse': low(metric(row, 'pa_nmse_db'), -24.0, -4.0), 'evm': low(metric(row, 'pa_evm_percent'), 6.0, 60.0), 'correlation': high(metric(row, 'pa_correlation'), 0.7, 0.995), 'aclr': high(metric(row, 'pa_aclr_db'), 5.0, 28.0), 'bounded_coefficients': low(metric(row, 'coefficient_max_abs'), 0.5, 4.0)}
    return (weighted(list(parts.values()), [0.3, 0.25, 0.15, 0.2, 0.1]), parts)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    failures: list[str] = []
    for key in ('load_pass', 'update_pass', 'compile_pass'):
        if not bool(evidence.get(key)):
            failures.append(f'{key} is false')
    missing = [name for name in REQUIRED if name not in rows or not bool(rows[name].get('simulation_pass')) or (not bool(rows[name].get('outputs_valid')))]
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not bool(static.get('closed_loop_adaptive_path')):
        failures.append('connected adaptive transmitter evidence is absent')
    if not bool(evidence.get('model_closed_without_save')):
        failures.append('model was not closed without save')
    if failures:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, {}, [])
    nominal = rows['nominal']
    nominal_perf, nominal_parts = performance(nominal)
    a_parts = {'aligned_nmse': low(metric(nominal, 'pa_nmse_db'), -24.0, -4.0), 'evm': low(metric(nominal, 'pa_evm_percent'), 6.0, 60.0), 'correlation': high(metric(nominal, 'pa_correlation'), 0.7, 0.995), 'finite_gain': interval(metric(nominal, 'pa_complex_gain_abs'), 0.01, 0.05, 5.0, 20.0)}
    inband_accuracy = weighted(list(a_parts.values()), [0.35, 0.3, 0.25, 0.1])
    aclr_utility = high(metric(nominal, 'pa_aclr_db'), 5.0, 28.0)
    A = math.sqrt(max(inband_accuracy * aclr_utility, 0.0))
    q_parts = {'aclr': high(metric(nominal, 'pa_aclr_db'), 5.0, 28.0), 'normalized_late_adaptation_error': low(metric(nominal, 'error_late_rms') / max(metric(nominal, 'observed_pa_rms'), 1e-15), 0.15, 0.5), 'bounded_coefficients': low(metric(nominal, 'coefficient_max_abs'), 0.5, 4.0), 'finite_values': high(metric(nominal, 'finite_fraction'), 0.99, 1.0)}
    Q = weighted(list(q_parts.values()), [0.35, 0.3, 0.2, 0.15])
    nominal_tx_rms = max(metric(nominal, 'observed_tx_rms'), 1e-15)
    scale_errors: list[float] = []
    for name in ('low_drive', 'high_drive'):
        requested_ratio = metric(rows[name], 'requested_input_scale')
        observed_ratio = metric(rows[name], 'observed_tx_rms') / nominal_tx_rms
        scale_errors.append(abs(observed_ratio - requested_ratio) / max(requested_ratio, 1e-12))
    input_scale_causality = low(max(scale_errors), 0.01, 0.2)
    mild_row = rows['mild_nonlinearity']
    strong_row = rows['strong_nonlinearity']
    pa_nmse_response = abs(metric(strong_row, 'pa_nmse_db') - metric(mild_row, 'pa_nmse_db'))
    pa_state_response = abs(metric(strong_row, 'coefficient_change_norm') - metric(mild_row, 'coefficient_change_norm'))
    pa_causality = max(high(pa_nmse_response, 0.01, 0.25), high(pa_state_response, 1e-06, 5e-05))
    dpd_activity_ratio = math.sqrt(max(10.0 ** (metric(nominal, 'dpd_relative_error_db') / 10.0), 0.0))
    coefficient_scale = max(metric(nominal, 'coefficient_max_abs'), 1e-12)
    normalized_update = metric(nominal, 'coefficient_update_rms') / coefficient_scale
    normalized_state_change = metric(nominal, 'coefficient_change_norm') / coefficient_scale
    m_parts = {'connected_feedback_and_recirculation': float(bool(static.get('closed_loop_adaptive_path'))), 'predistorter_activity': interval(dpd_activity_ratio, 0.0001, 0.003, 2.0, 8.0), 'coefficient_updates': interval(normalized_update, 1e-08, 1e-06, 1e-05, 0.0001), 'coefficient_state_change': interval(normalized_state_change, 1e-05, 0.0001, 0.005, 0.02), 'input_scale_causality': input_scale_causality, 'pa_nonlinearity_causality': pa_causality}
    M = weighted(list(m_parts.values()), [0.2, 0.15, 0.15, 0.15, 0.15, 0.2])
    scenario_scores: dict[str, float] = {}
    scenario_parts: dict[str, dict[str, float]] = {}
    for name in REQUIRED:
        scenario_scores[name], scenario_parts[name] = performance(rows[name])
    R = min(scenario_scores.values())
    d_scenario: dict[str, float] = {}
    for name in REQUIRED:
        row = rows[name]
        settling = low(metric(row, 'coefficient_settling_ratio'), 0.3, 1.2)
        late_error_stability = low(metric(row, 'error_late_rms') / max(metric(row, 'error_early_rms'), 1e-15), 1.0, 1.5)
        sustained_performance = scenario_scores[name]
        d_scenario[name] = weighted([settling, late_error_stability, sustained_performance], [0.4, 0.3, 0.3])
    D = min(d_scenario.values())
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for name, exponent in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** exponent
    shortcut_findings: list[dict[str, Any]] = []
    diagnostics = {'A_utilities': a_parts, 'A_inband_accuracy': inband_accuracy, 'A_aclr_utility': aclr_utility, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'R_scenario_scores': scenario_scores, 'R_scenario_utilities': scenario_parts, 'D_scenario_scores': d_scenario, 'nominal_performance': nominal_perf, 'nominal_performance_utilities': nominal_parts, 'input_scale_relative_errors': scale_errors, 'pa_nonlinearity_nmse_response_db': pa_nmse_response, 'pa_nonlinearity_state_response': pa_state_response, 'dpd_activity_ratio': dpd_activity_ratio, 'offline_calibration': {'normalized_coefficient_update': normalized_update, 'normalized_coefficient_state_change': normalized_state_change, 'coefficient_update_band': [1e-08, 1e-06, 1e-05, 0.0001], 'coefficient_state_change_band': [1e-05, 0.0001, 0.005, 0.02], 'coefficient_settling_full_zero': [0.3, 1.2], 'late_error_ratio_full_zero': [1.0, 1.5], 'reason': 'The official fixed-point HDL implementation updates its coefficients at quantized sub-micro scale. Dynamic quality is therefore based on nonzero bounded updates, settling, non-divergent late error and sustained RF performance, not monotonic sample-wise error under random OFDM symbols.'}, 'shortcut_findings': shortcut_findings}
    return receipt(evidence, groups, total, [], diagnostics, shortcut_findings)

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, failures: list[str], diagnostics: dict[str, Any], shortcut_findings: list[dict[str, Any]]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xcomm04-score.v1', 'task_id': 'F90-XCOMM-04', 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.25*Q^0.20*M^0.25*R^0.20*D^0.10', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': groups.get('G') == 1.0, 'groups': groups, 'score': total, 'admission_score_pass': bool(groups.get('G') == 1.0 and total >= 85), 'diagnostics': diagnostics, 'shortcut_findings': shortcut_findings, 'failure_reasons': failures}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence_positional', nargs='?')
    parser.add_argument('--evidence')
    parser.add_argument('--output')
    parser.add_argument('--out')
    args = parser.parse_args()
    evidence_name = args.evidence or args.evidence_positional
    if not evidence_name:
        parser.error('an evidence path is required')
    source = Path(evidence_name)
    output_name = args.output or args.out
    output = Path(output_name) if output_name else source.with_name('offline_score.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    result = score_evidence(json.loads(source.read_text(encoding='utf-8')))
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    print(output)
if __name__ == '__main__':
    main()
