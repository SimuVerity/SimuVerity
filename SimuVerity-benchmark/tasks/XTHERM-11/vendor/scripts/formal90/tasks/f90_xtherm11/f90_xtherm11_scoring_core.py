"""Pure offline scorer for complete F90-XTHERM-11 CSTR evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = 'simuverity-101-v1:f90-xtherm-11:scoring'
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.2, 'C': 0.2, 'R': 0.15, 'D': 0.15}
REQUIRED = ['nominal', 'elevated_targets_and_feed', 'feed_concentration_depletion', 'hot_feed_ramp', 'warm_coolant_ramp', 'mild_catalyst_and_fouling']

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def number(value: Any, default: float=math.nan) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default

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
    return sum((v * w for v, w in zip(values, weights))) / sum(weights)

def geometric(groups: dict[str, float]) -> float:
    value = 100.0
    for name, weight in WEIGHTS.items():
        value *= max(0.0, float(groups[name])) ** weight
    return value

def all_true(mapping: Any) -> bool:
    return isinstance(mapping, dict) and bool(mapping) and all((bool(v) for v in mapping.values()))

def make_receipt(evidence: dict[str, Any], groups: dict[str, float], score: float, failures: list[str], scenarios: dict[str, Any], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xtherm11-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XTHERM-11', 'formula': 'G*100*A^0.20*Q^0.10*M^0.20*C^0.20*R^0.15*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'preferred_reference_score': 90, 'G': bool(groups.get('G')), 'groups': groups, 'score': float(score), 'admission_score_pass': bool(groups.get('G') and score >= 85), 'per_scenario': scenarios, 'per_metric': diagnostics, 'failure_reasons': failures}

def empty_receipt(evidence: dict[str, Any], failures: list[str]) -> dict[str, Any]:
    groups = {'G': 0.0, **{name: 0.0 for name in WEIGHTS}}
    return make_receipt(evidence, groups, 0.0, failures, {}, {})

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    behavior = evidence.get('behavior_audit', {})
    missing = [name for name in REQUIRED if name not in rows or not rows[name].get('valid')]
    reference_ok = evidence.get('evaluation_subject') in {'reference', 'candidate'}
    gate = bool(evidence.get('evidence_complete') and evidence.get('load_pass') and evidence.get('update_pass') and evidence.get('compile_pass') and evidence.get('nominal_smoke_pass') and reference_ok and static.get('core_path_qualified') and behavior.get('core_behavior_qualified') and (not missing))
    failures: list[str] = []
    if not evidence.get('evidence_complete'):
        failures.append('evidence is not complete')
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not static.get('core_path_qualified'):
        failures.append('coupled reactor and feedback/actuation structure is not qualified')
    if not behavior.get('core_behavior_qualified'):
        failures.append('required inlet, setpoint, or degradation axes are ineffective')
    if not reference_ok:
        failures.append('reference source identity is not preserved')
    if not gate:
        return empty_receipt(evidence, failures)
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    scenario_scores: dict[str, Any] = {}
    for name in REQUIRED:
        m = metrics[name]
        temp_tail = low(number(m.get('temperature_tail_rmse_K')), 2.3, 7.0)
        temp_peak = low(number(m.get('temperature_peak_abs_error_K')), 12.0, 30.0)
        level_tail = low(number(m.get('level_tail_rmse_m')), 0.03, 0.08)
        level_peak = low(number(m.get('level_peak_abs_error_m')), 0.12, 0.3)
        physical = float(bool(m.get('physically_plausible')))
        dual = float(bool(m.get('dynamic_dual_actuation')))
        consistent = float(bool(m.get('control_log_consistent')))
        regulation = weighted([temp_tail, level_tail, temp_peak, level_peak], [0.35, 0.3, 0.15, 0.2])
        robust = weighted([regulation, physical, dual, consistent], [0.65, 0.15, 0.1, 0.1])
        scenario_scores[name] = {'temperature_tail_utility': temp_tail, 'temperature_peak_utility': temp_peak, 'level_tail_utility': level_tail, 'level_peak_utility': level_peak, 'physically_plausible': physical, 'dynamic_dual_actuation': dual, 'control_log_consistent': consistent, 'regulation_score': regulation, 'robust_score': robust}
    A = min((row['regulation_score'] for row in scenario_scores.values()))
    q_parts = {'complete_output_contracts': min((float(all_true(rows[name].get('output_contract', {}))) for name in REQUIRED)), 'complete_signal_artifacts': min((float(bool(rows[name].get('complete_signal_artifact'))) for name in REQUIRED)), 'finite_physical_operation': min((float(bool(metrics[name].get('physically_plausible'))) for name in REQUIRED)), 'control_log_consistency': min((float(bool(metrics[name].get('control_log_consistent'))) for name in REQUIRED)), 'source_or_candidate_identity': float(reference_ok)}
    Q = weighted(list(q_parts.values()), [0.25, 0.2, 0.2, 0.2, 0.15])
    concentration_values = [number(metrics[name].get('concentration_tail_mean_kmol_m3')) for name in REQUIRED]
    concentration_span = max(concentration_values) - min(concentration_values)
    factor_error = max((max(number(metrics[name].get('catalyst_factor_max_error')), number(metrics[name].get('heat_transfer_factor_max_error'))) for name in REQUIRED))
    thermal_correlation = min((number(metrics[name].get('thermal_state_correlation'), 0.0) for name in REQUIRED))
    m_parts = {'four_dynamic_process_states': high(number(static.get('process_state_count')), 2, 4), 'nonlinear_mass_energy_path': high(number(static.get('nonlinear_block_count')), 1, 4), 'thermal_state_coupling': high(thermal_correlation, 0.2, 0.85), 'reaction_concentration_axis': high(concentration_span, 0.015, 0.05), 'official_input_axes': clamp(number(behavior.get('input_axes_effective_count')) / 5.0), 'degradation_factor_fidelity': low(factor_error, 1e-06, 0.02)}
    M = weighted(list(m_parts.values()), [0.18, 0.14, 0.18, 0.18, 0.16, 0.16])
    worst_outlet_change = min((number(metrics[name].get('outlet_flow_change_from_pre_kg_s')) for name in REQUIRED))
    worst_coolant_change = min((number(metrics[name].get('coolant_flow_change_from_pre_kg_s')) for name in REQUIRED))
    c_parts = {'feedback_structure': float(bool(static.get('core_path_qualified'))), 'dynamic_dual_flow_actuation': float(bool(behavior.get('dynamic_dual_actuation'))), 'outlet_flow_response': high(worst_outlet_change, 0.02, 0.15), 'coolant_flow_response': high(worst_coolant_change, 0.1, 0.75), 'closed_loop_regulation': A}
    C = weighted(list(c_parts.values()), [0.2, 0.2, 0.18, 0.18, 0.24])
    R = min((row['robust_score'] for row in scenario_scores.values()))
    temp_slope = max((abs(number(metrics[name].get('temperature_tail_slope_K_s'))) for name in REQUIRED))
    level_slope = max((abs(number(metrics[name].get('level_tail_slope_m_s'))) for name in REQUIRED))
    d_parts = {'terminal_temperature_trend': low(temp_slope, 0.007, 0.03), 'terminal_level_trend': low(level_slope, 1e-05, 5e-05), 'dynamic_dual_actuation': float(bool(behavior.get('dynamic_dual_actuation'))), 'terminal_regulation': A}
    D = weighted(list(d_parts.values()), [0.28, 0.22, 0.2, 0.3])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'C': C, 'R': R, 'D': D}
    total = geometric(groups)
    failures.extend((name + ' group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    diagnostics = {'A_worst_regulation': A, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'C_utilities': c_parts, 'R_worst_scenario': R, 'D_utilities': d_parts, 'concentration_tail_span_kmol_m3': concentration_span, 'minimum_thermal_state_correlation': thermal_correlation, 'maximum_degradation_factor_error': factor_error, 'worst_outlet_flow_change_kg_s': worst_outlet_change, 'worst_coolant_flow_change_kg_s': worst_coolant_change}
    return make_receipt(evidence, groups, total, failures, scenario_scores, diagnostics)

def sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, Any] = {}

    def run(name: str, mutant: dict[str, Any]) -> None:
        receipt = score_evidence(mutant)
        cases[name] = {'score': receipt['score'], 'G': receipt['G'], 'pass': receipt['score'] < 85, 'failure_reasons': receipt['failure_reasons']}
    mutant = copy.deepcopy(evidence)
    mutant['evidence_complete'] = False
    run('uncomplete_or_missing_evidence', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'] = mutant['scenarios'][:-1]
    run('missing_required_scenario', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['static_audit']['core_path_qualified'] = False
    run('missing_feedback_or_dynamic_plant', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['behavior_audit']['input_axes_effective_count'] = 0
    mutant['behavior_audit']['core_behavior_qualified'] = False
    run('replayed_outputs_across_inputs', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['behavior_audit']['dynamic_dual_actuation'] = False
    mutant['behavior_audit']['core_behavior_qualified'] = False
    run('missing_dual_flow_actuation', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'][-1]['metrics']['catalyst_factor_max_error'] = 1.0
    mutant['scenarios'][-1]['metrics']['heat_transfer_factor_max_error'] = 1.0
    run('ignored_degradation_inputs', mutant)
    return {'schema': 'simuverity.f90-xtherm11-shortcut-sanity.v1', 'task_id': 'F90-XTHERM-11', 'all_pass': all((case['pass'] for case in cases.values())), 'max_shortcut_score': max((case['score'] for case in cases.values())), 'cases': cases}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf-8')
    summary: dict[str, Any] = {'score': result['score'], 'groups': result['groups'], 'out': str(out)}
    if args.sanity_out:
        sanity = sanity_suite(evidence)
        args.sanity_out.write_text(json.dumps(sanity, indent=2, allow_nan=False), encoding='utf-8')
        summary['sanity'] = {'all_pass': sanity['all_pass'], 'max_shortcut_score': sanity['max_shortcut_score'], 'out': str(args.sanity_out)}
    print(json.dumps(summary, allow_nan=False))
if __name__ == '__main__':
    main()
