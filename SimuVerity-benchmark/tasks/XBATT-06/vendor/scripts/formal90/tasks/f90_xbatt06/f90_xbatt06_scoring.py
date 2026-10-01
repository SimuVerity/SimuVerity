"""Strict-geometric scorer for complete F90-XBATT-06 evidence.

Missing 3RC behavior is represented in M and R, copied official outputs in C,
and disconnected RUL behavior in A/C.  The total is the strict weighted
geometric mean of the applicable groups.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
import f90_xbatt06_evidence_qualification as evidence_qualification
TASK_ID = evidence_qualification.TASK_ID
POLICY_ID = "simuverity-101-v1:f90-xbatt-06:scoring"
GROUP_WEIGHTS = dict(evidence_qualification.GROUP_WEIGHTS)

def strict_geometric(groups: dict[str, float], weights: dict[str, float]) -> float:
    if not weights:
        raise ValueError('at least one applicable group is required')
    if any((not math.isfinite(float(weight)) or float(weight) <= 0.0 for weight in weights.values())):
        raise ValueError('group weights must be finite and positive')
    if not math.isclose(sum(weights.values()), 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError('applicable group weights must sum to one')
    values = {name: float(groups[name]) for name in weights}
    if any((not math.isfinite(value) or value < 0.0 or value > 100.0 for value in values.values())):
        raise ValueError('group scores must be finite and in [0, 100]')
    if any((value == 0.0 for value in values.values())):
        return 0.0
    return 100.0 * math.exp(sum((weights[name] * math.log(values[name] / 100.0) for name in weights)))

def score_evidence(evidence: dict[str, Any], requested_subject: str='auto') -> dict[str, Any]:
    result = copy.deepcopy(evidence_qualification.score_evidence(evidence, requested_subject))
    gate = bool(result['G'])
    groups = {name: float(result['groups'][name]) for name in GROUP_WEIGHTS}
    total = strict_geometric(groups, GROUP_WEIGHTS) if gate else 0.0
    result['schema'] = 'simuverity.f90-xbatt06-offline-score.v1'
    result['policy_id'] = POLICY_ID
    result['status'] = 'SCORED' if gate else 'INELIGIBLE_EVIDENCE'
    result['raw_total'] = total
    result['total'] = total
    result['raw_score'] = total
    result['score'] = total
    result['reference_pass'] = bool(gate and total >= 85.0)
    result['total_aggregation'] = {'method': 'G_times_strict_weighted_geometric_mean', 'applicable_groups': list(GROUP_WEIGHTS), 'strict_zero_rule': 'any_applicable_group_zero_means_total_zero', 'epsilon_floor': 'none', 'post_total_cap_floor_or_override': 'none'}
    return result

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--subject', choices=('auto', 'candidate', 'reference'), default='auto')
    args = parser.parse_args()
    evidence_bytes = args.evidence.read_bytes()
    evidence = json.loads(evidence_bytes)
    result = score_evidence(evidence, args.subject)
    result['evidence_path'] = str(args.evidence.resolve())
    evidence_qualification.write_json(args.output, result)
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
