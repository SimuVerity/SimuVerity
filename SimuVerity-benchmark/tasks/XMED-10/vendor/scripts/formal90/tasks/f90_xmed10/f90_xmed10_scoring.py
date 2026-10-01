"""Pure-offline COMPATIBILITY scorer for complete F90-XMED-10 evidence.

COMPATIBILITY removes the overlap found in GROUP_SCORING.  A measures only complete-run BIS
tracking over the public 900 s interval, normalized by the corresponding
complete-reference scenario.  R retains the SCORING_CORE tail tracking, tail maximum,
physiology-plausibility, and bounded-command checks, but no longer includes
tail stability; terminal stability remains exclusively in D.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
import f90_xmed10_scoring_core as current
POLICY_ID = 'simuverity-101-v1:f90-xmed-10:scoring'
PUBLIC_SIMULATION_TIME_S = 900.0
REFERENCE_FULL_RUN_MAE_BIS = {'nominal_adult_target50': 4.004916412128671, 'young_adult_target50': 3.997991558033314, 'older_adult_target50': 4.10726733545136, 'low_body_mass_target50': 3.9483767370173033, 'high_body_mass_target50': 4.029363380766647, 'nominal_adult_target44': 4.550772391254968}
R_COMPONENT_WEIGHTS = {'tail_tracking': 0.45, 'tail_maximum': 0.2, 'physiology_plausible': 0.1, 'commands_bounded': 0.1}

def reference_ratio_utility(subject_mae: float, reference_mae: float) -> float:
    """Return min(1, reference/subject), with invalid evidence worth zero."""
    if not math.isfinite(subject_mae) or subject_mae < 0.0:
        return 0.0
    if subject_mae == 0.0:
        return 1.0
    return min(1.0, reference_mae / subject_mae)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    receipt = copy.deepcopy(current.score_evidence(evidence))
    receipt['schema'] = 'simuverity.f90-xmed10-score.v1'
    receipt['policy_id'] = POLICY_ID
    receipt['formula'] = 'G*100*A^0.25*Q^0.10*M^0.20*C^0.20*R^0.15*D^0.10'
    if float(receipt.get('G', 0.0)) != 1.0:
        return receipt
    rows = {str(row['id']): row for row in evidence['scenarios']}
    per_scenario = receipt['per_scenario']
    complete_run: dict[str, Any] = {}
    robust: dict[str, Any] = {}
    for scenario_id in current.REQUIRED:
        metrics = rows[scenario_id]['metrics']
        iae = current.number(metrics.get('bis_integral_absolute_error'))
        subject_mae = iae / PUBLIC_SIMULATION_TIME_S
        reference_mae = REFERENCE_FULL_RUN_MAE_BIS[scenario_id]
        tracking_utility = reference_ratio_utility(subject_mae, reference_mae)
        tail_tracking = current.low(current.number(metrics.get('bis_tail_absolute_error')), 0.25, 3.0)
        tail_maximum = current.low(current.number(metrics.get('bis_tail_max_absolute_error')), 0.35, 4.0)
        physiology_plausible = float(metrics.get('physiology_plausible') is True)
        commands_bounded = float(metrics.get('commands_bounded') is True)
        robust_score = current.weighted([tail_tracking, tail_maximum, physiology_plausible, commands_bounded], list(R_COMPONENT_WEIGHTS.values()))
        per_scenario[scenario_id].update({'full_run_integral_absolute_error_BIS_s': iae, 'full_run_mean_absolute_error_BIS': subject_mae, 'reference_full_run_mean_absolute_error_BIS': reference_mae, 'full_run_tracking_utility': tracking_utility, 'regulation_score': tracking_utility, 'robust_score': robust_score})
        complete_run[scenario_id] = {'integral_absolute_error_BIS_s': iae, 'mean_absolute_error_BIS': subject_mae, 'reference_mean_absolute_error_BIS': reference_mae, 'utility': tracking_utility}
        robust[scenario_id] = {'tail_tracking_utility': tail_tracking, 'tail_maximum_utility': tail_maximum, 'physiology_plausible': physiology_plausible, 'commands_bounded': commands_bounded, 'utility': robust_score}
    A = min((complete_run[name]['utility'] for name in current.REQUIRED))
    R = min((robust[name]['utility'] for name in current.REQUIRED))
    groups = dict(receipt['groups'])
    groups['A'] = A
    groups['R'] = R
    total = current.geometric(groups)
    receipt.update({'A': A, 'R': R, 'groups': groups, 'raw_total': total, 'total': total, 'score': total, 'admission_score_pass': bool(groups['G'] and total >= 85.0)})
    audit = {'public_complete_run_duration_s': PUBLIC_SIMULATION_TIME_S, 'aggregation': 'minimum scenario reference-ratio utility', 'per_scenario': complete_run, 'thresholds_or_component_weights_used': False, 'tail_metrics_scored_in_A': False, 'total_cap_applied': False}
    robust_audit = {'aggregation': 'minimum scenario utility', 'component_weights_before_mechanical_normalization': R_COMPONENT_WEIGHTS, 'tail_stability_scored_in_R': False, 'per_scenario': robust}
    for key in ('per_metric', 'metrics'):
        receipt[key]['A_worst_complete_run_reference_ratio'] = A
        receipt[key]['A_complete_run_tracking'] = audit
        receipt[key]['R_worst_scenario_without_stability'] = R
        receipt[key]['R_components'] = robust_audit
    failures = [reason for reason in receipt.get('failure_reasons', []) if reason not in {'A group below 0.60', 'R group below 0.60'}]
    if A < 0.6:
        failures.append('A group below 0.60')
    if R < 0.6:
        failures.append('R group below 0.60')
    receipt['failure_reasons'] = list(dict.fromkeys(failures))
    return receipt

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8-sig'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({'status': result['status'], 'G': result['G'], 'total': result['total'], 'out': str(out)}, ensure_ascii=False))
if __name__ == '__main__':
    main()
