"""Pure offline scorer current for complete F90-XMED-08 ECG evidence.

Evidence completeness is enforced by the evaluator-owned evidence bundle
before this scorer is invoked. The task-local ``evidence_complete``
field is intentionally ignored because older extractors mixed technical
evidence validity with detector performance.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = 'simuverity-101-v1:f90-xmed-08:scoring'
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}
REQUIRED = ['recorded_82_clean', 'synthetic_45_baseline', 'synthetic_60_mains', 'synthetic_160_emg', 'synthetic_220_motion', 'recorded_82_combined']
ARTIFACT_ROWS = REQUIRED[1:]
TRANSIENT_ROWS = ['synthetic_220_motion', 'recorded_82_combined']
SUPPORTED_SCHEMAS = {'simuverity.f90-xmed08-evidence.v1', 'simuverity.f90-xmed08-evidence.v1', 'simuverity.f90-xmed08-evidence.v1'}
TECHNICAL_OUTPUT_FLAGS = ('all_required_timeseries_finite', 'source_horizon_complete', 'detector_horizon_complete', 'detector_sample_count_complete', 'aligned_detector_outputs')
REQUIRED_METRICS = ('event_sensitivity', 'event_precision', 'false_events_per_minute', 'observed_median_hr_bpm', 'observed_hr_absolute_error_bpm', 'detected_event_count', 'matched_event_count', 'event_hr_output_difference_bpm', 'event_interval_hr_bpm', 'threshold_mean', 'threshold_coefficient_of_variation', 'threshold_clean_difference_ratio', 'artifact_rms_mv', 'clean_signal_summary', 'observed_event_summary', 'transient_threshold_response_ratio', 'threshold_recovery_relative_error')

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def number(value: Any, default: float=math.nan) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result

def is_finite_number(value: Any) -> bool:
    return math.isfinite(number(value))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value) or zero <= full:
        return 0.0
    return clamp((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value) or full <= zero:
        return 0.0
    return clamp((value - zero) / (full - zero))

def weighted(values: list[float], weights: list[float]) -> float:
    if not values or len(values) != len(weights) or sum(weights) <= 0:
        return 0.0
    return sum((value * weight for value, weight in zip(values, weights))) / sum(weights)

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0

def worst_mean(values: list[float], worst_weight: float=0.6) -> float:
    """Worst-case-heavy aggregation required by the current contract."""
    if not values:
        return 0.0
    return worst_weight * min(values) + (1.0 - worst_weight) * mean(values)

def half_worst_mean(values: list[float]) -> float:
    if not values:
        return 0.0
    return 0.5 * min(values) + 0.5 * mean(values)

def geometric(groups: dict[str, float]) -> float:
    score = 100.0
    for group, weight in WEIGHTS.items():
        score *= max(float(groups[group]), 0.0) ** weight
    return score

def truth_count(metrics: dict[str, Any]) -> float:
    for key in ('truth_event_count', 'clean_event_count'):
        value = number(metrics.get(key))
        if math.isfinite(value):
            return value
    return math.nan

def technical_output_complete(row: dict[str, Any]) -> bool:
    contract = row.get('output_contract')
    if not isinstance(contract, dict):
        return False
    for branch_name in ('clean', 'observed'):
        branch = contract.get(branch_name)
        if not isinstance(branch, dict):
            return False
        if not all((bool(branch.get(flag)) for flag in TECHNICAL_OUTPUT_FLAGS)):
            return False
    return True

def metrics_complete(row: dict[str, Any]) -> bool:
    metrics = row.get('metrics')
    if not isinstance(metrics, dict):
        return False
    if not math.isfinite(truth_count(metrics)) or truth_count(metrics) <= 0:
        return False
    if not all((is_finite_number(metrics.get(key)) for key in REQUIRED_METRICS)):
        return False
    matched = number(metrics.get('matched_event_count'), 0.0)
    latency = number(metrics.get('p95_absolute_latency_seconds'))
    return matched <= 0 or math.isfinite(latency)

def scenario_performance(metrics: dict[str, Any]) -> dict[str, Any]:
    sensitivity = number(metrics.get('event_sensitivity'), 0.0)
    precision = number(metrics.get('event_precision'), 0.0)
    false_rate = number(metrics.get('false_events_per_minute'), math.inf)
    latency = number(metrics.get('p95_absolute_latency_seconds'), math.inf)
    observed_hr = number(metrics.get('observed_median_hr_bpm'), 0.0)
    hr_error = number(metrics.get('observed_hr_absolute_error_bpm'), math.inf)
    detected = number(metrics.get('detected_event_count'), 0.0)
    matched = number(metrics.get('matched_event_count'), 0.0)
    sensitivity_u = high(sensitivity, 0.65, 0.95)
    precision_u = high(precision, 0.65, 0.95)
    detection_support = max(sensitivity_u, precision_u)
    false_rate_u = low(false_rate, 0.5, 8.0) * detection_support
    latency_u = low(latency, 0.06, 0.15) * detection_support if matched > 0 else 0.0
    heart_rate_u = low(hr_error, 3.0, 20.0) if detected >= 2 and observed_hr > 0 else 0.0
    utilities = {'event_sensitivity': sensitivity_u, 'event_precision': precision_u, 'false_event_control': false_rate_u, 'event_latency': latency_u, 'heart_rate_accuracy': heart_rate_u}
    score = weighted(list(utilities.values()), [0.3, 0.25, 0.15, 0.1, 0.2])
    if detected <= 0:
        score = 0.0
    reasons: list[str] = []
    if detected <= 0:
        reasons.append(f'no detected events (0/{int(round(truth_count(metrics)))} truth events)')
    if sensitivity_u < 1.0:
        reasons.append(f'event sensitivity {sensitivity:.6g}')
    if precision_u < 1.0:
        reasons.append(f'event precision {precision:.6g}')
    if false_rate_u < 1.0 and detected > 0:
        reasons.append(f'false-event rate {false_rate:.6g}/min')
    if latency_u < 1.0 and matched > 0:
        reasons.append(f'p95 event latency {latency:.6g} s')
    if heart_rate_u < 1.0:
        reasons.append(f'heart-rate output {observed_hr:.6g} bpm; absolute error {hr_error:.6g} bpm')
    return {'score': score, 'utilities': utilities, 'raw': {'truth_event_count': truth_count(metrics), 'detected_event_count': detected, 'matched_event_count': matched, 'event_sensitivity': sensitivity, 'event_precision': precision, 'false_events_per_minute': false_rate, 'p95_absolute_latency_seconds': latency if math.isfinite(latency) else None, 'observed_median_hr_bpm': observed_hr, 'observed_hr_absolute_error_bpm': hr_error}, 'deductions': reasons}

def event_hr_coherence(metrics: dict[str, Any]) -> float:
    detected = number(metrics.get('detected_event_count'), 0.0)
    observed_hr = number(metrics.get('observed_median_hr_bpm'), 0.0)
    event_hr = number(metrics.get('event_interval_hr_bpm'), 0.0)
    if detected < 2 or observed_hr <= 0 or event_hr <= 0:
        return 0.0
    return low(number(metrics.get('event_hr_output_difference_bpm')), 4.0, 30.0)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    scenario_list = evidence.get('scenarios')
    if not isinstance(scenario_list, list):
        scenario_list = []
    rows: dict[str, dict[str, Any]] = {}
    duplicate_ids: list[str] = []
    for row in scenario_list:
        if not isinstance(row, dict):
            continue
        scenario_id = str(row.get('id', ''))
        if scenario_id in rows:
            duplicate_ids.append(scenario_id)
        rows[scenario_id] = row
    missing = [name for name in REQUIRED if name not in rows]
    simulation_failures = [name for name in REQUIRED if name in rows and (not rows[name].get('simulation_pass'))]
    technical_failures = [name for name in REQUIRED if name in rows and (not technical_output_complete(rows[name]))]
    metric_failures = [name for name in REQUIRED if name in rows and (not metrics_complete(rows[name]))]
    truth_source = str(evidence.get('truth_source') or '').lower()
    no_cheating = evidence.get('candidate_output_used_as_truth') is not True and evidence.get('contains_score_decisions') is not True and ('candidate_output' not in truth_source)
    gate_checks = {'task_identity': evidence.get('task_id') == 'F90-XMED-08', 'supported_evidence_schema': evidence.get('schema') in SUPPORTED_SCHEMAS, 'load_pass': bool(evidence.get('load_pass')), 'update_pass': bool(evidence.get('update_pass')), 'compile_pass': bool(evidence.get('compile_pass')), 'nominal_smoke_pass': bool(evidence.get('nominal_smoke_pass')), 'required_scenarios_present_once': not missing and (not duplicate_ids), 'required_scenario_simulations_pass': not simulation_failures, 'required_outputs_finite_complete_aligned': not technical_failures, 'required_metrics_scorable': not metric_failures, 'no_candidate_truth_or_score_decisions': no_cheating}
    gate = all(gate_checks.values())
    failures: list[str] = []
    if missing:
        failures.append('missing required scenarios: ' + ', '.join(missing))
    if duplicate_ids:
        failures.append('duplicate required scenarios: ' + ', '.join(duplicate_ids))
    if simulation_failures:
        failures.append('failed simulations: ' + ', '.join(simulation_failures))
    if technical_failures:
        failures.append('incomplete/nonfinite/misaligned required outputs: ' + ', '.join(technical_failures))
    if metric_failures:
        failures.append('unscorable evidence metrics: ' + ', '.join(metric_failures))
    if not no_cheating:
        failures.append('candidate output was used as truth or evidence contains score decisions')
    for check, passed in gate_checks.items():
        if not passed and (not failures):
            failures.append(f'qualification check failed: {check}')
    base_diagnostics: dict[str, Any] = {'evidence_authority': 'evaluator-owned evidence bundle', 'task_local_evidence_complete_ignored': evidence.get('evidence_complete'), 'row_valid_ignored_for_qualification': True, 'name_based_static_audit_used': False, 'gate_checks': gate_checks}
    if not gate:
        return make_receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, base_diagnostics)
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    scenario_details = {name: scenario_performance(metrics[name]) for name in REQUIRED}
    scenario_scores = {name: float(scenario_details[name]['score']) for name in REQUIRED}
    all_scenario_scores = [scenario_scores[name] for name in REQUIRED]
    A = mean(all_scenario_scores)
    denominator_scores = {name: high(truth_count(metrics[name]), 3.0, 10.0) for name in REQUIRED}
    coherence_scores = {name: event_hr_coherence(metrics[name]) for name in REQUIRED}
    q_parts = {'technical_output_integrity': 1.0, 'valid_truth_denominators': min(denominator_scores.values()), 'event_heart_rate_consistency': worst_mean(list(coherence_scores.values()))}
    Q = weighted(list(q_parts.values()), [0.4, 0.2, 0.4])
    threshold_variability = {name: high(number(metrics[name].get('threshold_coefficient_of_variation')), 0.005, 0.04) for name in REQUIRED}
    artifact_visibility = {name: high(number(metrics[name].get('artifact_rms_mv')), 0.002, 0.02) for name in ARTIFACT_ROWS}
    source_summarys = [number(metrics[name].get('clean_signal_summary')) for name in REQUIRED]
    hr_accuracy = {name: scenario_details[name]['utilities']['heart_rate_accuracy'] for name in REQUIRED}
    m_parts = {'threshold_is_time_varying': half_worst_mean(list(threshold_variability.values())), 'artifact_reaches_conditioned_input': half_worst_mean(list(artifact_visibility.values())), 'distinct_physiology_inputs': high(max(source_summarys) - min(source_summarys), 10.0, 1000.0), 'heart_rate_tracks_required_physiology': worst_mean(list(hr_accuracy.values())), 'event_sequence_supports_heart_rate': worst_mean(list(coherence_scores.values()))}
    M = weighted(list(m_parts.values()), [0.25, 0.15, 0.15, 0.25, 0.2])
    R = worst_mean(all_scenario_scores)
    transient_response = {name: high(number(metrics[name].get('transient_threshold_response_ratio')), 0.005, 0.08) for name in TRANSIENT_ROWS}
    recovery = {name: transient_response[name] * low(number(metrics[name].get('threshold_recovery_relative_error')), 0.1, 0.8) for name in TRANSIENT_ROWS}
    d_parts = {'artifact_input_is_observed': half_worst_mean(list(artifact_visibility.values())), 'adaptive_threshold_varies_over_time': half_worst_mean(list(threshold_variability.values())), 'transient_threshold_response': worst_mean(list(transient_response.values())), 'threshold_recovers_after_transient': worst_mean(list(recovery.values())), 'heart_rate_tracks_full_required_range': worst_mean(list(hr_accuracy.values())), 'transient_detection_performance': worst_mean([scenario_scores[name] for name in TRANSIENT_ROWS])}
    D = weighted(list(d_parts.values()), [0.15, 0.2, 0.15, 0.15, 0.15, 0.2])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = geometric(groups)
    for name in REQUIRED:
        if scenario_scores[name] < 0.6:
            failures.append(f'{name} scenario performance {scenario_scores[name]:.6f} below 0.60')
    failures.extend((f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    diagnostics = {**base_diagnostics, 'A_aggregation': {'formula': 'equal-weight mean of all six required scenario scores', 'mean': A}, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'R_aggregation': {'formula': '0.60 * worst scenario + 0.40 * all-scenario mean', 'worst': min(all_scenario_scores), 'mean': mean(all_scenario_scores), 'score': R}, 'D_utilities': d_parts, 'scenario_scores': scenario_details, 'denominator_scores': denominator_scores, 'event_hr_coherence_scores': coherence_scores, 'threshold_variability_scores': threshold_variability, 'artifact_visibility_scores': artifact_visibility, 'transient_response_scores': transient_response, 'recovery_scores': recovery}
    return make_receipt(evidence, groups, total, failures, diagnostics)

def make_receipt(evidence: dict[str, Any], groups: dict[str, float], score: float, failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xmed08-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XMED-08', 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'G': bool(groups['G']), 'groups': groups, 'score': float(score), 'diagnostics': diagnostics, 'failure_reasons': failures}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf-8')
    print(json.dumps({'score': result['score'], 'groups': result['groups'], 'out': str(out)}, allow_nan=False))
if __name__ == '__main__':
    main()
