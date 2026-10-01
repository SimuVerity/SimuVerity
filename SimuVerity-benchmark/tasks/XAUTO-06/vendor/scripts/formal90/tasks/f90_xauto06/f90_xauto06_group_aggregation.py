"""F90-XAUTO-06 scorer with complete groups and strict aggregation.

M combines connected powertrain structure with power-split activity.  D blends
final recovery with regenerative activity, and anti-shortcut findings belong to
their corresponding engineering groups.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
import f90_xauto06_scoring_core as base
POLICY_ID = "simuverity-101-v1:f90-xauto-06:scoring"
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.1, 'D': 0.3}
APPLICABLE = tuple(WEIGHTS)

def strict_geometric_total(gate: object, groups: dict) -> float:
    if not bool(gate):
        return 0.0
    values = {name: float(groups[name]) for name in APPLICABLE}
    if any((not math.isfinite(value) or value < 0.0 or value > 1.0 for value in values.values())):
        raise ValueError('applicable group utility must be finite and in [0,1]')
    if any((value == 0.0 for value in values.values())):
        return 0.0
    if any((not math.isfinite(float(WEIGHTS[name])) or float(WEIGHTS[name]) <= 0.0 for name in APPLICABLE)):
        raise ValueError('applicable group weight must be finite and positive')
    weight_sum = sum(WEIGHTS.values())
    if not math.isclose(weight_sum, 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError('applicable group weights must sum to one')
    return 100.0 * math.exp(sum((WEIGHTS[name] * math.log(values[name]) for name in APPLICABLE)))

def score(evidence: dict) -> dict:
    result = copy.deepcopy(base.score(evidence))
    groups = copy.deepcopy(result['groups'])
    penalties = []
    audit = evidence.get('static_audit', {})
    headline = result.get('headline_metrics', {})
    mechanism_flags = [bool(audit.get('engine_present')), bool(audit.get('mg1_present')), bool(audit.get('mg2_present')), bool(audit.get('battery_present')), bool(audit.get('dcdc_present')), bool(audit.get('planetary_power_split_present')), bool(audit.get('vehicle_present')), bool(audit.get('feedback_path_connected'))]
    groups['M'] = 0.65 * (sum((float(value) for value in mechanism_flags)) / len(mechanism_flags)) + 0.35 * base.good_high(float(headline.get('minimum_power_split_activity_fraction', 0.0)), 0.04, 0.3)
    groups['D'] = 0.25 * float(headline.get('final_recovery_utility', 0.0)) + 0.75 * float(headline.get('regenerative_activity_utility', 0.0))
    if result['G'] and (not bool(audit.get('core_powertrain_connected'))):
        groups['M'] = 0.0
        penalties.append({'finding': 'CORE_POWERTRAIN_PATH_MISSING', 'group': 'M'})
    if result['G'] and (float(headline.get('worst_speed_rmse_kph', 0.0)) > 15.0 or min((float(row['metrics']['speed_reference_excursion_kph']) for row in evidence.get('scenarios', []) if row.get('valid'))) < 10.0):
        groups['R'] = 0.0
        penalties.append({'finding': 'DECLARED_SPEED_RANGE_RESPONSE_MISSING', 'group': 'R'})
    if result['G'] and float(headline.get('minimum_regen_activity_fraction', 1.0)) < 0.02:
        groups['D'] = 0.0
        penalties.append({'finding': 'REGENERATIVE_BRAKING_ACTIVITY_MISSING', 'group': 'D'})
    result['groups'] = groups
    total = strict_geometric_total(result['G'], groups)
    result.update({'policy_id': POLICY_ID, 'group_weights': WEIGHTS, 'aggregation': 'G times strict weighted geometric mean over A/Q/M/R/D; no epsilon, floor, post-total cap or override', 'raw_total': total, 'total': total, 'total_aggregation': {'method': 'G_times_strict_weighted_geometric_mean', 'applicable_groups': list(APPLICABLE), 'strict_zero_rule': 'any_applicable_group_zero_means_total_zero', 'epsilon_floor': 'none', 'post_total_cap_floor_or_override': 'none'}, 'anti_shortcut_group_penalties': penalties})
    return result

def zero_group_sanity() -> dict:
    cases = {}
    for name in APPLICABLE:
        groups = {group: 1.0 for group in APPLICABLE}
        groups[name] = 0.0
        cases[name] = strict_geometric_total(True, groups)
    assert all((value == 0.0 for value in cases.values()))
    return {'policy_id': POLICY_ID, 'cases': cases, 'all_zero': True}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence')
    parser.add_argument('--output', required=True)
    parser.add_argument('--zero-group-sanity-output')
    args = parser.parse_args()
    evidence = json.loads(Path(args.evidence).read_text(encoding='utf-8'))
    Path(args.output).write_text(json.dumps(score(evidence), indent=2) + '\n', encoding='utf-8')
    if args.zero_group_sanity_output:
        Path(args.zero_group_sanity_output).write_text(json.dumps(zero_group_sanity(), indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
