"""Pure-offline SCORING_CORE scorer for F90-XMED-10 complete evidence.

The evaluator-owned evidence bundle is authoritative. This task
scorer evaluates evidence integrity and engineering performance only; it does
not launch MATLAB, re-simulate, or use the source task-level evidence_complete
flag, which mixed performance and structure into qualification.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = 'simuverity-101-v1:f90-xmed-10:scoring'
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.2, 'C': 0.2, 'R': 0.15, 'D': 0.1}
REQUIRED = ('nominal_adult_target50', 'young_adult_target50', 'older_adult_target50', 'low_body_mass_target50', 'high_body_mass_target50', 'nominal_adult_target44')

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def number(value: Any, default: float=math.nan) -> float:
    try:
        converted = float(value)
    except (TypeError, ValueError):
        return default
    return converted if math.isfinite(converted) else default

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

def geometric(groups: dict[str, float]) -> float:
    total = 100.0
    for name, weight in WEIGHTS.items():
        total *= clamp(groups[name]) ** weight
    return total

def all_true(value: Any) -> bool:
    return isinstance(value, dict) and bool(value) and all((item is True for item in value.values()))

def integrity_gate(evidence: dict[str, Any]) -> tuple[bool, list[str], dict[str, Any]]:
    failures: list[str] = []
    runtime = {name: evidence.get(name) is True for name in ('load_pass', 'update_pass', 'compile_pass', 'nominal_smoke_pass')}
    if not all(runtime.values()):
        failures.append('load/update/compile/nominal-smoke integrity failed')
    smoke_contract = all_true(evidence.get('nominal_smoke_contract'))
    if not smoke_contract:
        failures.append('nominal smoke required outputs are incomplete or invalid')
    scenario_list = evidence.get('scenarios', [])
    rows = {str(row.get('id')): row for row in scenario_list if isinstance(row, dict) and isinstance(row.get('id'), str)}
    exact_scenarios = len(scenario_list) == len(REQUIRED) and set(rows) == set(REQUIRED)
    if not exact_scenarios:
        failures.append('required official scenario set is missing, duplicated, or changed')
    simulation_pass = exact_scenarios
    output_contract_pass = exact_scenarios
    artifact_pass = exact_scenarios
    if exact_scenarios:
        for name in REQUIRED:
            row = rows[name]
            simulation_pass = simulation_pass and row.get('simulation_pass') is True
            output_contract_pass = output_contract_pass and row.get('valid') is True and all_true(row.get('output_contract'))
            artifact_pass = artifact_pass and isinstance(row.get('complete_signal_artifact'), str) and bool(row['complete_signal_artifact'])
    if not simulation_pass:
        failures.append('one or more required scenario simulations failed')
    if not output_contract_pass:
        failures.append('required outputs are missing, nonfinite, incomplete, truncated, or misaligned')
    if not artifact_pass:
        failures.append('complete signal artifacts are missing')
    identity_pass = evidence.get('evaluation_subject') in {'candidate', 'reference'}
    if not identity_pass:
        failures.append('candidate/reference evidence identity is invalid')
    score_free = evidence.get('contains_score_decisions') is not True
    if not score_free:
        failures.append('evidence extraction contains score decisions')
    anti_cheat_preconditions = artifact_pass and score_free
    if not anti_cheat_preconditions:
        failures.append('task evidence is not ready for scoring')
    passed = all(runtime.values()) and smoke_contract and simulation_pass and output_contract_pass and identity_pass and anti_cheat_preconditions
    diagnostics = {'runtime': runtime, 'nominal_smoke_output_contract_pass': smoke_contract, 'exact_required_scenarios': exact_scenarios, 'all_required_simulations_pass': simulation_pass, 'required_outputs_finite_complete_aligned': output_contract_pass, 'candidate_or_reference_identity_pass': identity_pass, 'score_free_evidence': score_free, 'scoring_preconditions_pass': anti_cheat_preconditions}
    return (passed, list(dict.fromkeys(failures)), diagnostics)

def make_receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, failures: list[str], scenarios: dict[str, Any], metrics: dict[str, Any], status: str) -> dict[str, Any]:
    receipt: dict[str, Any] = {'schema': 'simuverity.f90-xmed10-score.v1', 'status': status, 'policy_id': POLICY_ID, 'task_id': 'F90-XMED-10', 'formula': 'G*100*A^0.25*Q^0.10*M^0.20*C^0.20*R^0.15*D^0.10', 'score_is_raw_not_rescaled': True, 'admission_threshold': 90, 'preferred_reference_score': 90, 'valid': True, 'score_inputs_valid': bool(groups['G']), 'diagnostics_valid': True, 'qualification_pass': bool(groups['G']), 'G': groups['G'], 'A': groups['A'], 'Q': groups['Q'], 'M': groups['M'], 'C': groups['C'], 'R': groups['R'], 'D': groups['D'], 'groups': groups, 'raw_total': float(total), 'total': float(total), 'score': float(total), 'admission_score_pass': bool(groups['G'] and total >= 90), 'per_scenario': scenarios, 'per_metric': metrics, 'metrics': metrics, 'failure_reasons': list(dict.fromkeys(failures))}
    return receipt

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    gate, failures, integrity = integrity_gate(evidence)
    if not gate:
        groups = {'G': 0.0, **{name: 0.0 for name in WEIGHTS}}
        return make_receipt(evidence, groups, 0.0, failures, {}, {'integrity': integrity}, 'QUALIFICATION_FAILED')
    rows = {str(row['id']): row for row in evidence['scenarios']}
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    static = evidence.get('static_audit', {})
    behavior = evidence.get('behavior_audit', {})
    scenario_scores: dict[str, Any] = {}
    for name in REQUIRED:
        values = metrics[name]
        tracking = low(number(values.get('bis_tail_absolute_error')), 0.25, 3.0)
        tail_max = low(number(values.get('bis_tail_max_absolute_error')), 0.35, 4.0)
        stability = low(number(values.get('bis_tail_std')), 0.03, 0.5)
        plausible = float(values.get('physiology_plausible') is True)
        bounded = float(values.get('commands_bounded') is True)
        scenario_scores[name] = {'tracking_utility': tracking, 'tail_max_utility': tail_max, 'tail_stability_utility': stability, 'physiology_plausible': plausible, 'commands_bounded': bounded, 'regulation_score': weighted([tracking, tail_max, stability], [0.5, 0.25, 0.25]), 'robust_score': weighted([tracking, tail_max, stability, plausible, bounded], [0.45, 0.2, 0.15, 0.1, 0.1])}
    A = min((row['regulation_score'] for row in scenario_scores.values()))
    contracts = {name: float(all_true(rows[name].get('output_contract'))) for name in REQUIRED}
    signal_artifacts = {name: float(bool(rows[name].get('complete_signal_artifact'))) for name in REQUIRED}
    reference_or_candidate = float(evidence.get('evaluation_subject') in {'reference', 'candidate'})
    q_parts = {'complete_output_contracts': min(contracts.values()), 'complete_signal_artifacts': min(signal_artifacts.values()), 'finite_plausible_physiology': min((float(metrics[name].get('physiology_plausible') is True) for name in REQUIRED)), 'bounded_nonnegative_commands': min((float(metrics[name].get('commands_bounded') is True) for name in REQUIRED)), 'source_or_candidate_identity': reference_or_candidate}
    Q = weighted(list(q_parts.values()), [0.25, 0.2, 0.2, 0.2, 0.15])
    physiology_summaries = [number(metrics[name].get('physiology_summary')) for name in REQUIRED]
    physiology_span = (max(physiology_summaries) - min(physiology_summaries)) / max(abs(physiology_summaries[0]), 1e-06)
    m_parts = {'dynamic_patient_path': float(static.get('dynamic_patient_path_present') is True), 'age_axis_response': high(number(behavior.get('age_axis_relative_response')), 0.005, 0.1), 'weight_axis_response': high(number(behavior.get('weight_axis_relative_response')), 0.005, 0.04), 'distinct_multivariable_physiology': high(physiology_span, 0.005, 0.05), 'physiological_outputs_remain_plausible': q_parts['finite_plausible_physiology']}
    M = weighted(list(m_parts.values()), [0.2, 0.2, 0.2, 0.2, 0.2])
    nominal = metrics['nominal_adult_target50']
    deeper = metrics['nominal_adult_target44']
    target_bis_delta = abs(number(deeper.get('bis_tail_mean')) - number(nominal.get('bis_tail_mean')))
    target_command_delta = max(abs(number(deeper.get('propofol_peak_mg_s')) - number(nominal.get('propofol_peak_mg_s'))), abs(number(deeper.get('remifentanil_peak_ug_s')) - number(nominal.get('remifentanil_peak_ug_s'))))
    target_gain_error = abs(target_bis_delta - 6.0)
    connected_control_structure = min(float(static.get('feedback_connection_present') is True), float(static.get('dual_drug_actuator_path_present') is True))
    c_parts = {'connected_feedback_and_dual_actuator_path': connected_control_structure, 'dynamic_dual_drug_actuation': float(behavior.get('dynamic_dual_actuation') is True), 'target_changes_bis': high(target_bis_delta, 3.0, 5.5), 'target_changes_command': high(target_command_delta, 0.05, 0.25), 'target_response_gain': low(target_gain_error, 0.25, 3.0)}
    C = weighted(list(c_parts.values()), [0.2, 0.2, 0.2, 0.2, 0.2])
    R = min((row['robust_score'] for row in scenario_scores.values()))
    settling = {name: low(number(metrics[name].get('bis_settling_time_s')), 380, 720) for name in REQUIRED}
    induction = {name: low(number(metrics[name].get('bis_induction_to_target_plus5_s')), 90, 240) for name in REQUIRED}
    terminal = {name: low(number(metrics[name].get('bis_tail_std')), 0.03, 0.5) for name in REQUIRED}
    d_parts = {'worst_settling': min(settling.values()), 'worst_induction': min(induction.values()), 'worst_terminal_stability': min(terminal.values())}
    D = weighted(list(d_parts.values()), [0.5, 0.25, 0.25])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'C': C, 'R': R, 'D': D}
    total = geometric(groups)
    failures.extend((name + ' group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    if behavior.get('age_axis_effective') is not True:
        failures.append('age-axis physiology response is weak')
    if behavior.get('weight_axis_effective') is not True:
        failures.append('weight-axis physiology response is weak')
    if behavior.get('target_axis_effective') is not True:
        failures.append('BIS-target response is weak')
    if behavior.get('dynamic_dual_actuation') is not True:
        failures.append('dual-drug actuation is not dynamic')
    diagnostics = {'integrity': integrity, 'A_worst_regulation': A, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'C_utilities': c_parts, 'R_worst_scenario': R, 'D_utilities': d_parts, 'settling_utilities': settling, 'induction_utilities': induction, 'terminal_stability_utilities': terminal, 'target_bis_delta': target_bis_delta, 'target_command_peak_delta': target_command_delta}
    return make_receipt(evidence, groups, total, failures, scenario_scores, diagnostics, 'SCORED')

def targeted_sanity_suite(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, Any] = {}

    def record(name: str, mutant: dict[str, Any]) -> None:
        receipt = score_evidence(mutant)
        cases[name] = {'G': receipt['G'], 'total': receipt['total'], 'groups': receipt['groups']}
    mutant = copy.deepcopy(evidence)
    mutant['evidence_complete'] = False
    mutant['behavior_audit']['age_axis_effective'] = False
    mutant['behavior_audit']['age_axis_relative_response'] = 0.0
    record('weak_age_axis_does_not_clear_G', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'] = mutant['scenarios'][:-1]
    record('missing_required_scenario_clears_G', mutant)
    mutant = copy.deepcopy(evidence)
    mutant['static_audit']['feedback_connection_present'] = False
    mutant['static_audit']['dual_drug_actuator_path_present'] = False
    record('missing_structure_scores_in_C_not_G', mutant)
    return {'schema': 'simuverity.f90-xmed10-targeted-sanity.v1', 'task_id': 'F90-XMED-10', 'cases': cases}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8-sig'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf-8')
    summary: dict[str, Any] = {'status': result['status'], 'G': result['G'], 'total': result['total'], 'out': str(out)}
    if args.sanity_out:
        sanity = targeted_sanity_suite(evidence)
        args.sanity_out.write_text(json.dumps(sanity, indent=2, allow_nan=False), encoding='utf-8')
        summary['sanity_out'] = str(args.sanity_out)
    print(json.dumps(summary, allow_nan=False))
if __name__ == '__main__':
    main()
