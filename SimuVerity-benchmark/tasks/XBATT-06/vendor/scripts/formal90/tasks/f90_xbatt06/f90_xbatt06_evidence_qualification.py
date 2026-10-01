"""Pure-offline scorer for complete F90-XBATT-06 evidence.

G covers evidence integrity, runtime completeness, and anti-cheat checks.
Reference-only observations are not applicable to candidates, while structure
and causal-path findings are scored in M and C.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import math
from pathlib import Path
from statistics import fmean
from typing import Any
TASK_ID = 'F90-XBATT-06'
POLICY_ID = "simuverity-101-v1:f90-xbatt-06:scoring"
TASK_ROOT = Path(__file__).resolve().parent
SOURCE_SCORER = TASK_ROOT / 'f90_xbatt06_scoring_core.py'
_spec = importlib.util.spec_from_file_location('f90_xbatt06_metric_helpers', SOURCE_SCORER)
if _spec is None or _spec.loader is None:
    raise RuntimeError('Unable to load the F90-XBATT-06 core metric helpers')
_core = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_core)
REQUIRED_SCENARIOS = list(_core.REQUIRED_SCENARIOS)
GROUP_WEIGHTS = dict(_core.GROUP_WEIGHTS)

def _subject(evidence: dict[str, Any], requested: str) -> str:
    if requested in {'candidate', 'reference'}:
        return requested
    return 'reference' if 'reference_substantive_modifications' in evidence else 'candidate'

def _complete(evidence: dict[str, Any]) -> bool:
    return evidence.get('evidence_complete') is True or evidence.get('evidence_complete') is True

def _gate(evidence: dict[str, Any], subject: str) -> tuple[bool, dict[str, bool], dict[str, bool | str], dict[str, dict[str, Any]]]:
    scenarios = evidence.get('scenarios', [])
    ids = [scenario.get('id') for scenario in scenarios if isinstance(scenario, dict)]
    exact_scenarios = len(scenarios) == len(REQUIRED_SCENARIOS) and ids == REQUIRED_SCENARIOS
    per_scenario = {scenario.get('id', f'unnamed_{index}'): _core.scenario_metrics(scenario) for index, scenario in enumerate(scenarios) if isinstance(scenario, dict)}
    containers_valid = exact_scenarios and all((metrics.get('containers_valid', False) for metrics in per_scenario.values()))
    scenario_runtime_valid = exact_scenarios and all((scenario.get('valid') is True and scenario.get('simulation_pass') is True and (scenario.get('required_evidence_pass') is True) for scenario in scenarios))
    checks = {'task_id_matches': evidence.get('task_id') == TASK_ID, 'evidence_complete': _complete(evidence), 'load_pass': evidence.get('load_pass') is True, 'update_pass': evidence.get('update_pass') is True, 'compile_pass': evidence.get('compile_pass') is True, 'required_scenarios_exact_and_ordered': exact_scenarios, 'all_scenarios_simulated_and_valid': scenario_runtime_valid, 'all_required_outputs_finite_complete_and_aligned': containers_valid, 'anti_cheat_no_score_decisions_in_evidence': evidence.get('contains_score_decisions') is not True}
    reference_only: dict[str, bool | str] = {'reference_substantive_modifications_zero': 'N/A'}
    if subject == 'reference':
        reference_only['reference_substantive_modifications_zero'] = evidence.get('reference_substantive_modifications') == 0
    passed = all(checks.values()) and all((value is True for value in reference_only.values() if value != 'N/A'))
    return (passed, checks, reference_only, per_scenario)

def _performance(evidence: dict[str, Any], per_scenario: dict[str, dict[str, Any]]) -> tuple[dict[str, float], dict[str, Any], dict[str, float]]:
    static = evidence.get('static_audit', {})
    valid_metrics = list(per_scenario.values())
    group_a = fmean((float(metrics.get('accuracy_score', 0.0)) for metrics in valid_metrics))
    group_q = min((float(metrics.get('quality_score', 0.0)) for metrics in valid_metrics))
    positive_fraction = min((float(metrics.get('parameter_positive_fraction', 0.0)) for metrics in valid_metrics))
    tau_span = min((float(metrics.get('tau_span_ratio', 0.0)) for metrics in valid_metrics))
    voltage_span = min((float(metrics.get('voltage_dynamic_span_V', 0.0)) for metrics in valid_metrics))
    third_branch = all((metrics.get('third_rc_branch_present') is True for metrics in valid_metrics))
    m_components = {'core_path_qualified': 100.0 if static.get('core_path_qualified') is True else 0.0, 'positive_3rc_parameter_fraction': 100.0 * positive_fraction, 'three_time_scale_span': _core.high_is_good(tau_span, 3.0, 20.0), 'third_branch_with_voltage_dynamics': 100.0 if third_branch and voltage_span >= 0.5 else 0.0}
    group_m = _core.weighted_mean([(m_components['core_path_qualified'], 0.4), (m_components['positive_3rc_parameter_fraction'], 0.25), (m_components['three_time_scale_span'], 0.2), (m_components['third_branch_with_voltage_dynamics'], 0.15)])
    scenarios = evidence.get('scenarios', [])
    representations = [_core.output_representation(scenario.get('outputs', {})) for scenario in scenarios]
    unique_representations = len(set(representations))
    capacity_coupled = max((float(metrics.get('capacity_max_abs_error_Ah', math.inf)) for metrics in valid_metrics)) <= 0.02
    rul_coupled = max((float(metrics.get('rul_identity_max_abs_s', math.inf)) for metrics in valid_metrics)) <= 0.25
    temperature_values = {scenario.get('requested_inputs', {}).get('temperature_K') for scenario in scenarios}
    c_components = {'current_and_temperature_input_paths': 100.0 if static.get('current_input_connected_to_plant_and_estimator') is True and static.get('temperature_input_connected') is True else 0.0, 'scenario_output_diversity': _core.high_is_good(unique_representations, 1.0, 4.0), 'capacity_input_coupling': 100.0 if capacity_coupled else 0.0, 'temperature_intervention_coverage': 100.0 if len(temperature_values) >= 3 else 0.0, 'rul_identity_coupling': 100.0 if rul_coupled else 0.0}
    group_c = _core.weighted_mean([(c_components['current_and_temperature_input_paths'], 0.45), (c_components['scenario_output_diversity'], 0.2), (c_components['capacity_input_coupling'], 0.15), (c_components['temperature_intervention_coverage'], 0.1), (c_components['rul_identity_coupling'], 0.1)])
    scenario_robustness = {scenario_id: _core.weighted_mean([(float(metrics.get('accuracy_score', 0.0)), 0.75), (float(metrics.get('quality_score', 0.0)), 0.15), (100.0 if metrics.get('third_rc_branch_present') is True else 0.0, 0.1)]) for scenario_id, metrics in per_scenario.items()}
    group_r = min(scenario_robustness.values())
    group_d = min((float(metrics.get('dynamic_score', 0.0)) for metrics in valid_metrics))
    groups = {name: _core.clamp(value) for name, value in {'A': group_a, 'Q': group_q, 'M': group_m, 'C': group_c, 'R': group_r, 'D': group_d}.items()}
    components = {'M': m_components, 'C': c_components}
    cross_scenario = {'third_rc_present_all_scenarios': third_branch, 'capacity_coupled_all_scenarios': capacity_coupled, 'rul_coupled_all_scenarios': rul_coupled}
    return (groups, {'group_components': components, 'cross_scenario': cross_scenario}, scenario_robustness)

def score_evidence(evidence: dict[str, Any], requested_subject: str='auto') -> dict[str, Any]:
    subject = _subject(evidence, requested_subject)
    passed, checks, reference_only, per_scenario = _gate(evidence, subject)
    failures = [name for name, value in checks.items() if not value]
    failures.extend((name for name, value in reference_only.items() if value is False))
    if passed:
        groups, metrics, scenario_robustness = _performance(evidence, per_scenario)
        raw_total = _core.weighted_geometric(groups)
        cross = metrics['cross_scenario']
        shortcut_findings: list[str] = []
        if not cross['third_rc_present_all_scenarios']:
            shortcut_findings.append('missing_or_zero_third_rc_branch')
        if not cross['rul_coupled_all_scenarios']:
            shortcut_findings.append('fabricated_or_disconnected_rul_trace')
        total = raw_total
    else:
        groups = {name: 0.0 for name in GROUP_WEIGHTS}
        metrics = {'group_components': {}, 'cross_scenario': {}}
        scenario_robustness = {}
        raw_total = 0.0
        total = 0.0
        shortcut_findings = []
    normalized_groups = {name: round(float(groups[name]), 9) for name in GROUP_WEIGHTS}
    raw_total = round(float(raw_total), 9)
    total = round(float(total), 9)
    scenario_rows = {scenario_id: {'metrics': values, 'robustness_score': scenario_robustness.get(scenario_id)} for scenario_id, values in per_scenario.items()}
    result: dict[str, Any] = {'schema': 'simuverity.f90-xbatt06-offline-score.v1', 'status': 'SCORED' if passed else 'INELIGIBLE_EVIDENCE', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'subject': subject, 'G': 1 if passed else 0, 'A': normalized_groups['A'], 'Q': normalized_groups['Q'], 'M': normalized_groups['M'], 'C': normalized_groups['C'], 'R': normalized_groups['R'], 'D': normalized_groups['D'], 'raw_total': raw_total, 'total': total, 'groups': normalized_groups, 'metrics': metrics, 'scenarios': scenario_rows, 'weights': GROUP_WEIGHTS, 'gate': {'G': 1 if passed else 0, 'passed': passed, 'checks': checks, 'reference_only_checks': reference_only, 'failures': failures}, 'shortcut_findings': shortcut_findings, 'offline_only': True, 'matlab_invoked': False, 'score_eligible': passed, 'scoring_completed': passed, 'failure_reasons': failures, 'qualification_gate_G': 1 if passed else 0, 'qualification_checks': checks, 'group_scores': normalized_groups, 'group_weights': GROUP_WEIGHTS, 'per_scenario_metrics': per_scenario, 'per_scenario_robustness': scenario_robustness, 'raw_score': total}
    return result

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

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
    write_json(args.output, result)
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
