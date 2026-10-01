"""F90-XBATT-02 scorer with complete metrics and group-owned penalties."""
from __future__ import annotations
import copy
import math
import f90_xbatt02_scoring_core as base
TASK_ID = 'F90-XBATT-02'
POLICY_ID = "simuverity-101-v1:f90-xbatt-02:scoring"
APPLICABLE = ('A', 'Q', 'M', 'R', 'D')

def strict_geometric_total(gate: object, groups: dict, weights: dict) -> float:
    if not bool(gate):
        return 0.0
    values = {name: float(groups[name]) for name in APPLICABLE}
    if any((not math.isfinite(value) or value < 0.0 or value > 1.0 for value in values.values())):
        raise ValueError('applicable group utility must be finite and in [0,1]')
    if any((value == 0.0 for value in values.values())):
        return 0.0
    positive_weights = {name: float(weights[name]) for name in APPLICABLE}
    if any((not math.isfinite(weight) or weight <= 0.0 for weight in positive_weights.values())):
        raise ValueError('applicable group weight must be finite and positive')
    weight_sum = sum(positive_weights.values())
    if not math.isclose(weight_sum, 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError('applicable group weights must sum to one')
    return 100.0 * math.exp(sum((positive_weights[name] * math.log(values[name]) for name in APPLICABLE)))

def score(evidence: dict):
    current_groups, _source_total, reasons, diagnostics = base.score(evidence)
    groups = copy.deepcopy(current_groups)
    cap_findings = list(diagnostics.get('findings', []))
    penalties = []
    for finding in cap_findings:
        if finding in {'PACK_ELECTRICAL_CORE_PATH_MISSING', 'PUMP_AUXILIARY_POWER_PATH_MISSING', 'THERMAL_COOLANT_CORE_PATH_MISSING', 'FINITE_RESPONSE_POLARIZATION_STATE_MISSING'}:
            groups['M'] = 0.0
            penalties.append({'finding': finding, 'group': 'M'})
    gate = bool(evidence.get('facts', {}).get('score_inputs_valid', False))
    weights = evidence['group_weights']
    total = strict_geometric_total(gate, groups, weights)
    clean = copy.deepcopy(diagnostics)
    clean.pop('findings', None)
    clean['raw_total'] = total
    clean['anti_shortcut_findings'] = cap_findings
    clean['anti_shortcut_group_penalties'] = penalties
    clean['aggregation'] = {'method': 'G_times_strict_weighted_geometric_mean', 'applicable_groups': list(APPLICABLE), 'zero_group_rule': 'any applicable zero group makes total zero', 'epsilon_floor': 'none', 'post_total_cap_or_floor': 'none'}
    return (groups, total, reasons, clean)

def zero_group_sanity() -> dict:
    weights = {'A': 0.18, 'Q': 0.12, 'M': 0.34, 'R': 0.2, 'D': 0.16}
    cases = {}
    for name in APPLICABLE:
        groups = {group: 1.0 for group in APPLICABLE}
        groups[name] = 0.0
        cases[name] = strict_geometric_total(True, groups, weights)
    assert all((value == 0.0 for value in cases.values()))
    return {'policy_id': POLICY_ID, 'cases': cases, 'all_zero': True}

def receipt(evidence_path, evidence: dict, groups: dict, total: float, reasons: list) -> dict:
    gate = bool(evidence['facts'].get('score_inputs_valid', False))
    normalized = {'G': int(gate), **{name: float(groups[name]) for name in APPLICABLE}}
    return {'schema': 'simuverity.formal90-offline-score.v1', 'formal_task_id': TASK_ID, 'policy_id': POLICY_ID, 'offline_only': True, 'evidence_path': str(evidence_path.resolve()), 'score_inputs_valid': gate, 'diagnostics_valid': bool(evidence['facts'].get('diagnostics_valid', gate)), 'G': gate, 'groups': normalized, 'A': normalized['A'], 'Q': normalized['Q'], 'M': normalized['M'], 'R': normalized['R'], 'D': normalized['D'], 'score': float(total), 'gate_reasons': list(reasons), 'failure_reasons': list(reasons)}

def main() -> None:
    args = base.parser(TASK_ID).parse_args()
    evidence = base.load_evidence(args.evidence, TASK_ID)
    groups, total, reasons, diagnostics = score(evidence)
    output = receipt(args.evidence, evidence, groups, total, reasons)
    output.update({'scenario_rows': evidence['facts'].get('scenario_rows', []), 'metric_values': {'physical_suite': evidence['facts'].get('physical_suite', {}), 'causal_pairs': evidence['facts'].get('causal_pairs', {})}, 'utility_metrics': diagnostics, 'zero_group_sanity': zero_group_sanity()})
    base.write_receipt(args.output, output)
if __name__ == '__main__':
    main()
