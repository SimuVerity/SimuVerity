"""Pure offline scorer for complete F90-XMED-08 ECG evidence.

The within-group policy uses two ECG-specific semantics:

* the five public performance aspects within each scenario have equal weight,
  so timing is no longer the uniquely underweighted aspect; and
* D accepts successful transient detection as evidence that conditioning and
  adaptation handled an artifact without requiring the numeric threshold to
  move.  M still independently scores observable threshold adaptation.
"""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path
from typing import Any
import f90_xmed08_scoring_core as base
POLICY_ID = 'simuverity-101-v1:f90-xmed-08:scoring'
SCENARIO_UTILITY_WEIGHTS = [0.2, 0.2, 0.2, 0.2, 0.2]

def scenario_performance(metrics: dict[str, Any]) -> dict[str, Any]:
    detail = base.scenario_performance(metrics)
    utilities = detail['utilities']
    detail['score'] = base.weighted([utilities['event_sensitivity'], utilities['event_precision'], utilities['false_event_control'], utilities['event_latency'], utilities['heart_rate_accuracy']], SCENARIO_UTILITY_WEIGHTS)
    if base.number(metrics.get('detected_event_count'), 0.0) <= 0:
        detail['score'] = 0.0
    detail['within_scenario_formula'] = 'equal 0.20 weights for sensitivity, precision, false-event control, event latency, and heart-rate accuracy'
    return detail

def _identity_failed_gate(receipt: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(receipt)
    result['schema'] = 'simuverity.f90-xmed08-score.v1'
    result['policy_id'] = POLICY_ID
    result['diagnostics']['within_group_policy'] = {'scenario_utility_weights': {'event_sensitivity': 0.2, 'event_precision': 0.2, 'false_event_control': 0.2, 'event_latency': 0.2, 'heart_rate_accuracy': 0.2}, 'D_effective_response_semantics': 'successful scenario performance may demonstrate effective artifact handling without mandatory raw-threshold movement'}
    return result

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    current = base.score_evidence(evidence)
    if not current['G']:
        return _identity_failed_gate(current)
    rows = {str(row.get('id')): row for row in evidence['scenarios']}
    metrics = {name: rows[name]['metrics'] for name in base.REQUIRED}
    scenario_details = {name: scenario_performance(metrics[name]) for name in base.REQUIRED}
    scenario_scores = {name: float(scenario_details[name]['score']) for name in base.REQUIRED}
    all_scenario_scores = [scenario_scores[name] for name in base.REQUIRED]
    A = base.mean(all_scenario_scores)
    Q = float(current['groups']['Q'])
    M = float(current['groups']['M'])
    R = base.worst_mean(all_scenario_scores)
    diagnostics = copy.deepcopy(current['diagnostics'])
    threshold_variability = diagnostics['threshold_variability_scores']
    artifact_visibility = diagnostics['artifact_visibility_scores']
    transient_response = diagnostics['transient_response_scores']
    recovery = diagnostics['recovery_scores']
    hr_accuracy = {name: scenario_details[name]['utilities']['heart_rate_accuracy'] for name in base.REQUIRED}
    effective_dynamic_adaptation = {name: max(threshold_variability[name], scenario_scores[name]) for name in base.REQUIRED}
    effective_transient_response = {name: max(transient_response[name], scenario_scores[name]) for name in base.TRANSIENT_ROWS}
    effective_recovery = {name: max(recovery[name], scenario_scores[name]) for name in base.TRANSIENT_ROWS}
    d_parts = {'artifact_input_is_observed': base.half_worst_mean(list(artifact_visibility.values())), 'effective_dynamic_adaptation': base.worst_mean(list(effective_dynamic_adaptation.values())), 'effective_transient_response': base.worst_mean(list(effective_transient_response.values())), 'effective_recovery': base.worst_mean(list(effective_recovery.values())), 'heart_rate_tracks_full_required_range': base.worst_mean(list(hr_accuracy.values())), 'transient_detection_performance': base.worst_mean([scenario_scores[name] for name in base.TRANSIENT_ROWS])}
    D = base.weighted(list(d_parts.values()), [0.15, 0.2, 0.15, 0.15, 0.15, 0.2])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = base.geometric(groups)
    failures: list[str] = []
    for name in base.REQUIRED:
        if scenario_scores[name] < 0.6:
            failures.append(f'{name} scenario performance {scenario_scores[name]:.6f} below 0.60')
    failures.extend((f'{name} group below 0.60' for name in base.WEIGHTS if groups[name] < 0.6))
    diagnostics.update({'A_aggregation': {'formula': 'equal-weight mean of all six required scenario scores', 'mean': A}, 'R_aggregation': {'formula': '0.60 * worst scenario + 0.40 * all-scenario mean', 'worst': min(all_scenario_scores), 'mean': base.mean(all_scenario_scores), 'score': R}, 'D_utilities': d_parts, 'scenario_scores': scenario_details, 'effective_dynamic_adaptation_scores': effective_dynamic_adaptation, 'effective_transient_response_scores': effective_transient_response, 'effective_recovery_scores': effective_recovery, 'within_group_policy': {'scenario_utility_weights': {'event_sensitivity': 0.2, 'event_precision': 0.2, 'false_event_control': 0.2, 'event_latency': 0.2, 'heart_rate_accuracy': 0.2}, 'D_effective_response_semantics': 'successful scenario performance may demonstrate effective artifact handling without mandatory raw-threshold movement'}})
    return {'schema': 'simuverity.f90-xmed08-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XMED-08', 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'G': True, 'groups': groups, 'score': float(total), 'diagnostics': diagnostics, 'failure_reasons': failures}

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
