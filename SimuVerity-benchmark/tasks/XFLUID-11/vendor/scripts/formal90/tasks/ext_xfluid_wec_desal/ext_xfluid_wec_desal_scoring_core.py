"""Pure offline scorer for EXT-XFLUID-WEC-DESAL."""
from __future__ import annotations
import argparse
import copy
import json
import math
import sys
from pathlib import Path
from typing import Any
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'shared'))
from ext_scoring_common import strict_weighted_geometric
TASK_ID = 'EXT-XFLUID-WEC-DESAL'
WEIGHTS = {'A': 0.16, 'Q': 0.1, 'M': 0.24, 'C': 0.22, 'R': 0.16, 'D': 0.12}
EXPECTED = {'nominal_sea', 'low_sea', 'high_sea', 'height_intervention'}

def utility(value: float, good: float, bad: float, lower: bool=True) -> float:
    if not math.isfinite(value):
        return 0.0
    if lower:
        if value <= good:
            return 1.0
        if value >= bad:
            return 0.0
        return (bad - value) / (bad - good)
    if value >= good:
        return 1.0
    if value <= bad:
        return 0.0
    return (value - bad) / (good - bad)

def weighted(parts: list[tuple[float, float]]) -> float:
    return sum((w * x for w, x in parts)) / sum((w for w, _ in parts))

def arr(item: dict[str, Any], name: str, width: int) -> np.ndarray:
    value = np.asarray(item.get(name, []), float)
    return value

def signed_sum_error(target: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
    scale = max(float(np.sqrt(np.mean(target ** 2))), float(np.sqrt(np.mean(a ** 2))), float(np.sqrt(np.mean(b ** 2))), 1e-08)
    return float(min((np.sqrt(np.mean((target - sa * a - sb * b) ** 2)) for sa in (-1, 1) for sb in (-1, 1))) / scale)

def abs_correlation(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, float).reshape(-1)
    b = np.asarray(b, float).reshape(-1)
    if a.size != b.size or a.size < 3 or np.std(a) <= 1e-12 or (np.std(b) <= 1e-12):
        return 0.0
    value = float(np.corrcoef(a, b)[0, 1])
    return abs(value) if math.isfinite(value) else 0.0

def structure_qualified_from_behavior(sm: dict[str, dict[str, float]]) -> bool:
    """Implementation-neutral physical-path qualification.

    No official block names or library SourceBlock strings are consulted.  A
    qualifying implementation must expose active mechanics, satisfy the PTO
    power identity and RO split, couple brine to the recovery path, and react
    to the height intervention.
    """
    if set(sm) != EXPECTED:
        return False
    vals = list(sm.values())
    n = sm['nominal_sea']
    h = sm['height_intervention']
    active = min((x.get('activity_utility', 0.0) for x in vals))
    identities = min((min(x.get('power_identity_u', 0.0), x.get('ro_split_u', 0.0), x.get('recovery_coupling_u', 0.0)) for x in vals))
    response = max((abs(h.get(k, 0.0) - n.get(k, 0.0)) / max(abs(n.get(k, 0.0)), 1e-12) for k in ('force_rms', 'power_rms', 'total_feed_rms', 'pressure_rms')))
    return active > 0.2 and identities > 0.2 and (response > 0.015)

def partial_metrics(item: dict[str, Any]) -> dict[str, float]:
    """Use extractor-produced channel-local metrics; absent metrics are zero."""
    defaults = {'power_identity_u': 0.0, 'ro_split_u': 0.0, 'recovery_coupling_u': 0.0, 'activity_utility': 0.0, 'bounded_utility': 0.0, 'startup_u': 0.0, 'force_rms': 0.0, 'power_rms': 0.0, 'total_feed_rms': 0.0, 'pressure_rms': 0.0}
    t = np.asarray(item.get('time_s', []), float).reshape(-1)
    active = t >= 25 if t.size else np.asarray([], bool)
    mech = np.asarray(item.get('desal_mechanical_response', []), float)
    hyd = np.asarray(item.get('desal_hydraulic_response', []), float)
    rec = np.asarray(item.get('desal_recovery_response', []), float)
    if t.size >= 500 and mech.shape == (t.size, 3) and np.all(np.isfinite(mech)):
        v, f, p = (mech[:, 0], mech[:, 1], mech[:, 2])
        expected = v[active] * f[active]
        err = float(np.sqrt(np.mean((p[active] - expected) ** 2)) / max(np.sqrt(np.mean(expected ** 2)), 1.0))
        defaults['power_identity_u'] = utility(err, 0.02, 0.25)
        defaults['force_rms'] = float(np.sqrt(np.mean(f[active] ** 2)))
        defaults['power_rms'] = float(np.sqrt(np.mean(p[active] ** 2)))
    if t.size >= 500 and hyd.shape == (t.size, 4) and np.all(np.isfinite(hyd)):
        salt, perm, brine, pressure = (hyd[:, 0], hyd[:, 1], hyd[:, 2], hyd[:, 3])
        defaults['pressure_rms'] = float(np.sqrt(np.mean(pressure[active] ** 2)))
        defaults['ro_split_u'] = utility(signed_sum_error(np.asarray(item.get('desal_recovery_response', np.zeros((t.size, 3))), float)[:, 1][active] if rec.shape == (t.size, 3) else np.zeros(sum(active)), perm[active], brine[active]), 0.04, 0.3)
    if t.size >= 500 and hyd.shape == (t.size, 4) and (rec.shape == (t.size, 3)) and np.all(np.isfinite(np.c_[hyd, rec])):
        brine = hyd[:, 2]
        pe = rec[:, 0]
        ratio = float(np.sqrt(np.mean(pe[active] ** 2)) / max(np.sqrt(np.mean(brine[active] ** 2)), 1e-12))
        corr = abs_correlation(pe[active], brine[active])
        defaults['recovery_coupling_u'] = weighted([(0.6, utility(corr, 0.9, 0.4, False)), (0.4, utility(abs(ratio - 1), 0.2, 0.8))])
        defaults['total_feed_rms'] = float(np.sqrt(np.mean(rec[active, 1] ** 2)))
    available = [defaults['power_identity_u'], defaults['ro_split_u'], defaults['recovery_coupling_u']]
    defaults['activity_utility'] = sum((x > 0 for x in available)) / 3.0
    defaults['bounded_utility'] = defaults['activity_utility']
    supplied = item.get('partial_metrics', {})
    if isinstance(supplied, dict):
        for k in defaults:
            try:
                v = float(supplied.get(k, defaults[k]))
                defaults[k] = v if math.isfinite(v) else 0.0
            except (TypeError, ValueError):
                pass
    return defaults

def metrics(item: dict[str, Any]) -> dict[str, float]:
    t = np.asarray(item.get('time_s', []), float).reshape(-1)
    if t.size < 500 or t[0] > 1e-08 or t[-1] < 59.9 or np.any(np.diff(t) <= 0) or (np.max(np.diff(t)) > 0.100000001):
        raise ValueError('invalid 0-60 s time coverage')
    mech = arr(item, 'desal_mechanical_response', 3)
    hyd = arr(item, 'desal_hydraulic_response', 4)
    rec = arr(item, 'desal_recovery_response', 3)
    active = t >= 25
    early = t <= 5
    steady = t >= 35
    velocity, force, power = (mech[:, 0], mech[:, 1], mech[:, 2])
    salt, permeate, brine, pressure = (hyd[:, 0], hyd[:, 1], hyd[:, 2], hyd[:, 3])
    pe_feed, total_feed, accumulator = (rec[:, 0], rec[:, 1], rec[:, 2])
    expected_power = velocity[active] * force[active]
    power_error = float(np.sqrt(np.mean((power[active] - expected_power) ** 2)) / max(np.sqrt(np.mean(expected_power ** 2)), 1.0))
    ro_split_error = signed_sum_error(total_feed[active], permeate[active], brine[active])
    recovery_corr = abs_correlation(pe_feed[active], brine[active])
    rms_pe_over_brine = float(np.sqrt(np.mean(pe_feed[active] ** 2)) / max(np.sqrt(np.mean(brine[active] ** 2)), 1e-12))
    recovery_ratio_error = abs(rms_pe_over_brine - 1.0)
    rms = lambda x: float(np.sqrt(np.mean(np.asarray(x)[active] ** 2)))
    activity = {'velocity_rms': rms(velocity), 'force_rms': rms(force), 'power_rms': rms(power), 'saltwater_rms': rms(salt), 'permeate_rms': rms(permeate), 'brine_rms': rms(brine), 'pressure_rms': rms(pressure), 'pe_feed_rms': rms(pe_feed), 'total_feed_rms': rms(total_feed), 'accumulator_rms': rms(accumulator)}
    activity_u = float(np.mean([utility(activity['velocity_rms'], 0.001, 1e-06, False), utility(activity['force_rms'], 1000.0, 1, False), utility(activity['saltwater_rms'], 1e-06, 1e-09, False), utility(activity['permeate_rms'], 1e-07, 1e-10, False), utility(activity['brine_rms'], 1e-07, 1e-10, False), utility(activity['pressure_rms'], 100000.0, 100.0, False), utility(activity['pe_feed_rms'], 1e-07, 1e-10, False), utility(activity['accumulator_rms'], 1e-07, 1e-10, False)]))
    max_force = float(np.max(np.abs(force)))
    max_pressure = float(np.max(np.abs(pressure)))
    max_flow = float(np.max(np.abs(np.c_[salt, permeate, brine, pe_feed, total_feed, accumulator])))
    max_power = float(np.max(np.abs(power)))
    bounded_u = min(utility(max_force, 200000000.0, 1000000000.0), utility(max_pressure, 200000000.0, 1000000000.0), utility(max_flow, 1, 10), utility(max_power, 1000000000.0, 10000000000.0))
    early_activity = float(np.sqrt(np.mean(np.c_[velocity[early], salt[early], permeate[early]] ** 2)))
    steady_activity = float(np.sqrt(np.mean(np.c_[velocity[steady], salt[steady], permeate[steady]] ** 2)))
    startup_ratio = early_activity / max(steady_activity, 1e-12)
    drift = float(abs(np.polyfit(t[steady], pressure[steady], 1)[0]) / max(activity['pressure_rms'], 1.0))
    result = {'power_identity_relative_error': power_error, 'ro_split_relative_error': ro_split_error, 'pressure_exchanger_brine_abs_correlation': recovery_corr, 'pressure_exchanger_to_brine_rms_ratio': rms_pe_over_brine, 'pressure_exchanger_ratio_error': recovery_ratio_error, 'activity_utility': activity_u, 'bounded_utility': bounded_u, 'startup_to_steady_activity_ratio': startup_ratio, 'steady_pressure_relative_drift_per_s': drift, **activity, 'power_identity_u': utility(power_error, 0.02, 0.25), 'ro_split_u': utility(ro_split_error, 0.04, 0.3), 'recovery_coupling_u': weighted([(0.6, utility(recovery_corr, 0.9, 0.4, False)), (0.4, utility(recovery_ratio_error, 0.2, 0.8))]), 'startup_u': weighted([(0.7, utility(startup_ratio, 0.4, 0.95)), (0.3, utility(drift, 0.015, 0.08))])}
    return result

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    failures = []
    stages = evidence.get('stages', {})
    stage_ok = all((stages.get(x) is True for x in ('setup', 'load', 'update', 'compile', 'smoke')))
    scenarios = evidence.get('scenarios', [])
    logs_ok = len(scenarios) == 4 and {str(x.get('id', '')) for x in scenarios} == EXPECTED
    sm = {}
    if logs_ok:
        for item in scenarios:
            simulation_valid = item.get('simulation_valid', item.get('valid')) is True
            if not simulation_valid:
                logs_ok = False
                failures.append(f"scenario_simulation_invalid:{item.get('id', '')}")
                continue
            try:
                sm[str(item['id'])] = metrics(item)
            except (ValueError, KeyError, TypeError):
                sm[str(item['id'])] = partial_metrics(item)
                failures.append(f"partial_public_output:{item.get('id', '')}")
    complete = evidence.get('evidence_complete') is True
    structure_ok = structure_qualified_from_behavior(sm)
    if not stage_ok:
        failures.append('setup_load_update_compile_or_smoke_failed')
    if not structure_ok:
        failures.append('behavioral_mechanical_hydraulic_ro_or_recovery_path_unqualified')
    if not logs_ok:
        failures.append('scenario_or_public_output_contract_failed')
    if not complete:
        failures.append('evidence_not_complete')
    gate = int(stage_ok and logs_ok and complete)
    causal = {}
    if gate:
        vals = list(sm.values())
        nominal = sm['nominal_sea']
        intervention = sm['height_intervention']
        response_keys = ('force_rms', 'power_rms', 'total_feed_rms', 'pressure_rms')
        gains = {key: intervention[key] / max(nominal[key], 1e-12) for key in response_keys}
        changes = {key: abs(intervention[key] - nominal[key]) / max(nominal[key], 1e-12) for key in response_keys}
        causal_u = weighted([(0.55, utility(max(gains.values()), 1.15, 1.02, False)), (0.45, utility(max(changes.values()), 0.12, 0.015, False))])
        groups = {'A': float(np.mean([weighted([(0.45, m['power_identity_u']), (0.35, m['ro_split_u']), (0.2, m['recovery_coupling_u'])]) for m in vals])), 'Q': float(np.mean([weighted([(0.7, m['bounded_utility']), (0.3, m['activity_utility'])]) for m in vals])), 'M': float(np.mean([weighted([(0.3, m['activity_utility']), (0.3, m['ro_split_u']), (0.25, m['recovery_coupling_u']), (0.15, m['power_identity_u'])]) for m in vals])), 'C': causal_u, 'R': float(min((weighted([(0.3, m['power_identity_u']), (0.25, m['ro_split_u']), (0.2, m['recovery_coupling_u']), (0.15, m['activity_utility']), (0.1, m['bounded_utility'])]) for m in vals))), 'D': float(np.mean([m['startup_u'] for m in vals]))}
        causal = {'height_intervention_gains': gains, 'height_intervention_changes': changes}
    else:
        groups = {k: 0.0 for k in WEIGHTS}
    raw = strict_weighted_geometric(gate, groups, WEIGHTS)
    return {'schema': 'simuverity.ext-offline-score.v1', 'task_id': TASK_ID, 'evaluation_policy_id': 'simuverity-101-v1:ext-xfluid-wec-desal:scoring', 'G': gate, 'groups': {k: 100 * v for k, v in groups.items()}, 'groups_normalized': groups, 'group_weights': WEIGHTS, 'raw_score': raw, 'raw_reference_admission_threshold': 90.0, 'normalize_threshold_to_100': False, 'admission_pass': bool(gate and raw >= 90), 'across_groups': 'strict_weighted_geometric_mean', 'strict_zero_rule': True, 'epsilon_floor': False, 'post_total_cap': False, 'scenario_metrics': sm, 'causal_metrics': causal, 'implementation_neutral_path_qualified': structure_ok, 'partial_output_policy': 'missing channels zero only dependent extractor metrics; no reconstruction', 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    base = score_evidence(evidence)
    checks = {}
    missing = copy.deepcopy(evidence)
    missing['scenarios'][0].pop('desal_hydraulic_response', None)
    missing['scenarios'][0]['simulation_valid'] = True
    score = score_evidence(missing)
    checks['required_output_missing_preserves_g_but_loses_score'] = score['G'] == 1 and score['raw_score'] < base['raw_score']
    no_path = copy.deepcopy(evidence)
    for item in no_path['scenarios']:
        item['desal_recovery_response'] = [[0.0, 0.0, 0.0] for _ in item['time_s']]
    score = score_evidence(no_path)
    checks['physical_recovery_bypass_loses_score'] = score['raw_score'] < base['raw_score']
    copied = copy.deepcopy(evidence)
    for item in copied['scenarios']:
        n = len(item['time_s'])
        height = float(item['input']['wave_height_m'])
        item['desal_mechanical_response'] = [[height, height, height] for _ in range(n)]
    score = score_evidence(copied)
    checks['command_copy_loses_score'] = score['raw_score'] < base['raw_score']
    return {'task_id': TASK_ID, 'checks': checks, 'pass': all(checks.values())}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--shortcut-output', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    if args.shortcut_output:
        args.shortcut_output.parent.mkdir(parents=True, exist_ok=True)
        args.shortcut_output.write_text(json.dumps(shortcut_sanity(evidence), indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
