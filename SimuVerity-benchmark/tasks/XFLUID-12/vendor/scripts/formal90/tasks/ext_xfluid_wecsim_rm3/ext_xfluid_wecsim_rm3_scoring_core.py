"""Pure offline scorer for EXT-XFLUID-WECSIM-RM3."""
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
TASK_ID = 'EXT-XFLUID-WECSIM-RM3'
WEIGHTS = {'A': 0.18, 'Q': 0.12, 'M': 0.22, 'C': 0.2, 'R': 0.16, 'D': 0.12}
EXPECTED = {'nominal_sea', 'low_sea_low_damping', 'high_sea_high_damping', 'nominal_sea_high_damping'}

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

def arr(item: dict[str, Any], name: str) -> np.ndarray:
    x = np.asarray(item.get(name, []), float)
    return x

def metrics(item: dict[str, Any]) -> dict[str, float]:
    t = np.asarray(item.get('time_s', []), float).reshape(-1)
    if t.size < 400 or t[0] > 1e-09 or t[-1] < 79.9 or np.any(np.diff(t) <= 0) or (np.max(np.diff(t)) > 0.100000001):
        raise ValueError('invalid 0-80 s time coverage')
    body = arr(item, 'rm3_body_response')
    pto = arr(item, 'rm3_pto_response')
    hydro = arr(item, 'rm3_hydrodynamic_response')
    active = t >= 25
    early = t <= 5
    steady = t >= 40
    damp = float(item['input']['pto_damping_n_s_m'])
    deriv_float = np.gradient(body[:, 0], t)
    deriv_spar = np.gradient(body[:, 2], t)
    scale_v = max(float(np.sqrt(np.mean(body[active][:, [1, 3]] ** 2))), 0.001)
    kine = float(np.sqrt(np.mean(np.c_[deriv_float[active] - body[active, 1], deriv_spar[active] - body[active, 3]] ** 2)) / scale_v)
    body_rel = body[:, 0] - body[:, 2] - (body[0, 0] - body[0, 2])
    pto_rel = pto[:, 0] - pto[0, 0]
    rel_pos_a = float(np.sqrt(np.mean((pto_rel[active] - body_rel[active]) ** 2)))
    rel_pos_b = float(np.sqrt(np.mean((pto_rel[active] + body_rel[active]) ** 2)))
    rel_pos = float(min(rel_pos_a, rel_pos_b) / max(np.sqrt(np.mean(pto_rel[active] ** 2)), 0.02))
    rel_vel_a = float(np.sqrt(np.mean((pto[active, 1] - (body[active, 1] - body[active, 3])) ** 2)))
    rel_vel_b = float(np.sqrt(np.mean((pto[active, 1] + (body[active, 1] - body[active, 3])) ** 2)))
    rel_vel = float(min(rel_vel_a, rel_vel_b) / max(np.sqrt(np.mean(pto[active, 1] ** 2)), 0.01))
    expected_force = damp * pto[active, 1]
    force_err = min(np.sqrt(np.mean((pto[active, 2] - expected_force) ** 2)), np.sqrt(np.mean((pto[active, 2] + expected_force) ** 2)))
    force_rel = float(force_err / max(np.sqrt(np.mean(expected_force ** 2)), 1000.0))
    expected_power = damp * pto[active, 1] ** 2
    power_rel = float(np.sqrt(np.mean((pto[active, 3] - expected_power) ** 2)) / max(np.sqrt(np.mean(expected_power ** 2)), 1000.0))
    excitation_rms = float(np.sqrt(np.mean(hydro[active, 1] ** 2)))
    radiation_rms = float(np.sqrt(np.mean(hydro[active, 2] ** 2)))
    restoring_rms = float(np.sqrt(np.mean(hydro[active, 3] ** 2)))
    wave_rms = float(np.sqrt(np.mean(hydro[active, 0] ** 2)))
    heave_rms = float(np.sqrt(np.mean(body[active, 0] ** 2)))
    relvel_rms = float(np.sqrt(np.mean(pto[active, 1] ** 2)))
    force_rms = float(np.sqrt(np.mean(pto[active, 2] ** 2)))
    power_mean = float(np.mean(pto[active, 3]))
    radiation_coupling = abs_correlation(hydro[active, 2], body[active, 1])
    restoring_coupling = abs_correlation(hydro[active, 3], body[active, 0])
    early_wave = float(np.sqrt(np.mean(hydro[early, 0] ** 2)))
    steady_wave = float(np.sqrt(np.mean(hydro[steady, 0] ** 2)))
    early_heave = float(np.sqrt(np.mean(body[early, 0] ** 2)))
    steady_heave = float(np.sqrt(np.mean(body[steady, 0] ** 2)))
    slope = float(abs(np.polyfit(t[steady], body[steady, 0], 1)[0]))
    m = {'kinematic_relative_rmse': kine, 'relative_position_error': rel_pos, 'relative_velocity_error': rel_vel, 'pto_force_law_error': force_rel, 'pto_power_law_error': power_rel, 'excitation_rms_n': excitation_rms, 'radiation_rms_n': radiation_rms, 'restoring_rms_n': restoring_rms, 'wave_rms_m': wave_rms, 'float_heave_rms_m': heave_rms, 'relative_velocity_rms_m_s': relvel_rms, 'pto_force_rms_n': force_rms, 'absorbed_power_mean_w': power_mean, 'radiation_velocity_abs_correlation': radiation_coupling, 'restoring_displacement_abs_correlation': restoring_coupling, 'early_to_steady_wave_ratio': early_wave / max(steady_wave, 1e-09), 'early_to_steady_heave_ratio': early_heave / max(steady_heave, 1e-09), 'steady_heave_drift_m_s': slope, 'max_abs_heave_excursion_m': float(np.max(abs(body[:, [0, 2]] - body[[0], [0, 2]]))), 'max_abs_force_n': float(np.max(abs(np.c_[pto[:, 2], hydro[:, 1:]]))), 'max_abs_power_w': float(np.max(abs(pto[:, 3])))}
    m['kinematic_u'] = weighted([(0.4, utility(kine, 0.04, 0.3)), (0.3, utility(rel_pos, 0.04, 0.3)), (0.3, utility(rel_vel, 0.04, 0.3))])
    m['pto_law_u'] = weighted([(0.45, utility(force_rel, 0.05, 0.35)), (0.55, utility(power_rel, 0.02, 0.2))])
    m['mechanism_u'] = weighted([(0.25, utility(excitation_rms, 10000.0, 100.0, False)), (0.2, utility(radiation_rms, 1000.0, 10, False)), (0.2, utility(restoring_rms, 1000.0, 10, False)), (0.175, utility(radiation_coupling, 0.85, 0.4, False)), (0.175, utility(restoring_coupling, 0.85, 0.4, False))])
    m['bounded_u'] = min(utility(m['max_abs_heave_excursion_m'], 15, 40), utility(m['max_abs_force_n'], 100000000.0, 500000000.0), utility(m['max_abs_power_w'], 500000000.0, 2000000000.0))
    m['startup_u'] = weighted([(0.35, utility(m['early_to_steady_wave_ratio'], 0.45, 0.9)), (0.35, utility(m['early_to_steady_heave_ratio'], 0.55, 1.1)), (0.3, utility(slope, 0.01, 0.08))])
    return m

def abs_correlation(x: np.ndarray, y: np.ndarray) -> float:
    x = np.asarray(x, float).reshape(-1)
    y = np.asarray(y, float).reshape(-1)
    if x.size != y.size or x.size < 3 or np.std(x) <= 1e-12 or (np.std(y) <= 1e-12):
        return 0.0
    value = float(np.corrcoef(x, y)[0, 1])
    return abs(value) if math.isfinite(value) else 0.0

def partial_metrics(item: dict[str, Any]) -> dict[str, float]:
    defaults = {'kinematic_u': 0.0, 'pto_law_u': 0.0, 'mechanism_u': 0.0, 'bounded_u': 0.0, 'startup_u': 0.0, 'excitation_rms_n': 0.0, 'float_heave_rms_m': 0.0, 'pto_force_rms_n': 0.0, 'relative_velocity_rms_m_s': 0.0}
    t = np.asarray(item.get('time_s', []), float).reshape(-1)
    active = t >= 25 if t.size else np.asarray([], bool)
    body = np.asarray(item.get('rm3_body_response', []), float)
    pto = np.asarray(item.get('rm3_pto_response', []), float)
    hyd = np.asarray(item.get('rm3_hydrodynamic_response', []), float)
    if t.size >= 400 and body.shape == (t.size, 4) and (pto.shape == (t.size, 4)) and np.all(np.isfinite(np.c_[body, pto])):
        damp = float(item.get('input', {}).get('pto_damping_n_s_m', 0))
        expected = damp * pto[active, 1]
        ferr = min(np.sqrt(np.mean((pto[active, 2] - expected) ** 2)), np.sqrt(np.mean((pto[active, 2] + expected) ** 2))) / max(np.sqrt(np.mean(expected ** 2)), 1000.0)
        pexpected = damp * pto[active, 1] ** 2
        perr = np.sqrt(np.mean((pto[active, 3] - pexpected) ** 2)) / max(np.sqrt(np.mean(pexpected ** 2)), 1000.0)
        defaults['pto_law_u'] = weighted([(0.45, utility(float(ferr), 0.05, 0.35)), (0.55, utility(float(perr), 0.02, 0.2))])
        defaults['pto_force_rms_n'] = float(np.sqrt(np.mean(pto[active, 2] ** 2)))
        defaults['relative_velocity_rms_m_s'] = float(np.sqrt(np.mean(pto[active, 1] ** 2)))
    if t.size >= 400 and body.shape == (t.size, 4) and (hyd.shape == (t.size, 4)) and np.all(np.isfinite(np.c_[body, hyd])):
        ex = float(np.sqrt(np.mean(hyd[active, 1] ** 2)))
        rad = float(np.sqrt(np.mean(hyd[active, 2] ** 2)))
        rest = float(np.sqrt(np.mean(hyd[active, 3] ** 2)))
        defaults['excitation_rms_n'] = ex
        defaults['float_heave_rms_m'] = float(np.sqrt(np.mean(body[active, 0] ** 2)))
        defaults['mechanism_u'] = weighted([(0.25, utility(ex, 10000.0, 100.0, False)), (0.2, utility(rad, 1000.0, 10, False)), (0.2, utility(rest, 1000.0, 10, False)), (0.175, utility(abs_correlation(hyd[active, 2], body[active, 1]), 0.85, 0.4, False)), (0.175, utility(abs_correlation(hyd[active, 3], body[active, 0]), 0.85, 0.4, False))])
    defaults['bounded_u'] = 1.0 if body.shape == (t.size, 4) and np.all(np.isfinite(body)) else 0.0
    supplied = item.get('partial_metrics', {})
    if isinstance(supplied, dict):
        for k in defaults:
            try:
                v = float(supplied.get(k, defaults[k]))
                defaults[k] = v if math.isfinite(v) else 0.0
            except (TypeError, ValueError):
                pass
    return defaults

def structure_qualified_from_behavior(sm: dict[str, dict[str, float]]) -> bool:
    if set(sm) != EXPECTED:
        return False
    vals = list(sm.values())
    lo = sm['low_sea_low_damping']
    hi = sm['high_sea_high_damping']
    n = sm['nominal_sea']
    hd = sm['nominal_sea_high_damping']
    mechanisms = min((x.get('mechanism_u', 0.0) for x in vals))
    pto = min((x.get('pto_law_u', 0.0) for x in vals))
    wave_gain = hi.get('excitation_rms_n', 0.0) / max(lo.get('excitation_rms_n', 0.0), 1e-09)
    damping_change = abs(hd.get('pto_force_rms_n', 0.0) - n.get('pto_force_rms_n', 0.0)) / max(n.get('pto_force_rms_n', 0.0), 1.0)
    return mechanisms > 0.2 and pto > 0.2 and (wave_gain > 1.05) and (damping_change > 0.01)

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
        failures.append('behavioral_two_body_hydrodynamic_or_pto_path_unqualified')
    if not logs_ok:
        failures.append('scenario_or_public_output_contract_failed')
    if not complete:
        failures.append('evidence_not_complete')
    gate = int(stage_ok and logs_ok and complete)
    if gate:
        vals = list(sm.values())
        nominal = sm['nominal_sea']
        low = sm['low_sea_low_damping']
        high = sm['high_sea_high_damping']
        hd = sm['nominal_sea_high_damping']
        wave_gain = high['excitation_rms_n'] / max(low['excitation_rms_n'], 1e-09)
        response_gain = high['float_heave_rms_m'] / max(low['float_heave_rms_m'], 1e-09)
        damping_force_change = abs(hd['pto_force_rms_n'] - nominal['pto_force_rms_n']) / max(nominal['pto_force_rms_n'], 1)
        damping_velocity_change = abs(hd['relative_velocity_rms_m_s'] - nominal['relative_velocity_rms_m_s']) / max(nominal['relative_velocity_rms_m_s'], 0.0001)
        causal = weighted([(0.35, utility(wave_gain, 1.5, 1.05, False)), (0.25, utility(response_gain, 1.2, 1.02, False)), (0.2, utility(damping_force_change, 0.08, 0.01, False)), (0.2, utility(damping_velocity_change, 0.05, 0.005, False))])
        groups = {'A': float(np.mean([weighted([(0.55, m['kinematic_u']), (0.45, m['pto_law_u'])]) for m in vals])), 'Q': float(np.mean([weighted([(0.65, m['bounded_u']), (0.35, 1.0)]) for m in vals])), 'M': float(np.mean([weighted([(0.7, m['mechanism_u']), (0.3, m['pto_law_u'])]) for m in vals])), 'C': causal, 'R': float(min((weighted([(0.35, m['kinematic_u']), (0.3, m['pto_law_u']), (0.2, m['mechanism_u']), (0.15, m['bounded_u'])]) for m in vals))), 'D': float(np.mean([m['startup_u'] for m in vals]))}
        causal_metrics = {'wave_excitation_gain_high_over_low': wave_gain, 'heave_gain_high_over_low': response_gain, 'damping_force_change_fraction': damping_force_change, 'damping_velocity_change_fraction': damping_velocity_change}
    else:
        groups = {k: 0.0 for k in WEIGHTS}
        causal_metrics = {}
    raw = strict_weighted_geometric(gate, groups, WEIGHTS)
    return {'schema': 'simuverity.ext-offline-score.v1', 'task_id': TASK_ID, 'evaluation_policy_id': 'simuverity-101-v1:ext-xfluid-wecsim-rm3:scoring', 'G': gate, 'groups': {k: 100 * v for k, v in groups.items()}, 'groups_normalized': groups, 'group_weights': WEIGHTS, 'raw_score': raw, 'raw_reference_admission_threshold': 90.0, 'normalize_threshold_to_100': False, 'admission_pass': bool(gate and raw >= 90), 'across_groups': 'strict_weighted_geometric_mean', 'strict_zero_rule': True, 'epsilon_floor': False, 'post_total_cap': False, 'scenario_metrics': sm, 'causal_metrics': causal_metrics, 'implementation_neutral_path_qualified': structure_ok, 'partial_output_policy': 'missing channels zero only dependent extractor metrics; no reconstruction', 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    base = score_evidence(evidence)
    checks = {}
    missing = copy.deepcopy(evidence)
    missing['scenarios'][0].pop('rm3_pto_response', None)
    missing['scenarios'][0]['simulation_valid'] = True
    s = score_evidence(missing)
    checks['required_output_missing_preserves_g_but_loses_score'] = s['G'] == 1 and s['raw_score'] < base['raw_score']
    no_path = copy.deepcopy(evidence)
    for item in no_path['scenarios']:
        item['rm3_pto_response'] = [[0.0, 0.0, 0.0, 0.0] for _ in item['time_s']]
    s = score_evidence(no_path)
    checks['disconnected_pto_loses_score'] = s['raw_score'] < base['raw_score']
    copied = copy.deepcopy(evidence)
    for item in copied['scenarios']:
        body = np.asarray(item['rm3_body_response'], float)
        body[:, :] = float(item['input']['wave_height_m'])
        item['rm3_body_response'] = body.tolist()
    s = score_evidence(copied)
    checks['command_copy_loses_score'] = s['raw_score'] < base['raw_score']
    return {'task_id': TASK_ID, 'checks': checks, 'pass': all(checks.values())}

def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--evidence', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--shortcut-output', type=Path)
    a = p.parse_args()
    e = json.loads(a.evidence.read_text(encoding='utf-8'))
    r = score_evidence(e)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(r, indent=2) + '\n', encoding='utf-8')
    if a.shortcut_output:
        a.shortcut_output.parent.mkdir(parents=True, exist_ok=True)
        a.shortcut_output.write_text(json.dumps(shortcut_sanity(e), indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
