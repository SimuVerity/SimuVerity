"""XMED04 graph-plus-behavior mechanism-confidence scorer.

An original structure PASS is scored by the CURRENT_GROUPS
scorer.  A narrow behavioral fallback is allowed only when all missing graph
facts are meal-absorption/sample-monitor representation facts and every
behavioral mechanism utility is full.  Behavior cannot erase the
unverified graph fraction: M is the non-compensatory minimum of the base M
and the fraction of required graph facts directly verified.
"""
from __future__ import annotations
import copy
import importlib.util
import math
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
CURRENT_GROUPS_PATH = TASK_DIR / 'f90_xmed04_scoring_core.py'
ALLOWED_FALLBACK_FAILURES = {'meal_to_absorbed_glucose', 'meal_absorption_dynamics', 'sampled_monitor'}
MECHANISM_FIELDS = ('output_bindings_unambiguous', 'distinct_public_output_anchors', 'port_routing_safe', 'meal_absorption_dynamics', 'physiological_dynamics', 'sampled_monitor', 'controller_and_pump_are_distinct_transforms', 'pump_or_delivery_dynamics', 'identity_fields_safe')
BEHAVIOR_FIELDS = ('meal_mass_conservation', 'absorption_mass_response', 'meal_load_causality', 'patient_weight_causality', 'sensor_sample_causality', 'closed_loop_insulin_response')

def _load_policy_core() -> ModuleType:
    spec = importlib.util.spec_from_file_location('f90_xmed04', CURRENT_GROUPS_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load XMED04 CURRENT_GROUPS scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
CURRENT_GROUPS = _load_policy_core()
PUBLIC_POLICY_ID = 'simuverity-101-v1:f90-xmed-04:scoring'

def _public_result(result: dict[str, Any]) -> dict[str, Any]:
    result['policy_id'] = PUBLIC_POLICY_ID
    return result

def _strict_total(groups: dict[str, float]) -> float:
    if any((float(groups[name]) <= 0.0 for name in CURRENT_GROUPS.WEIGHTS)):
        return 0.0
    return 100.0 * math.exp(sum((CURRENT_GROUPS.WEIGHTS[name] * math.log(float(groups[name])) for name in CURRENT_GROUPS.WEIGHTS)))

def _forced_policy(original: dict[str, Any]):

    def evaluate(_graph: dict[str, Any]) -> dict[str, Any]:
        result = copy.deepcopy(original)
        result['core_path_qualified'] = True
        result['failure_reasons'] = []
        return result
    return evaluate

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    graph = evidence.get('static_audit', {}).get('port_graph')
    if not isinstance(graph, dict):
        raise ValueError('XMED04 scorer requires current graph evidence')
    original = CURRENT_GROUPS.POLICY.evaluate_structure_graph(graph)
    if bool(original.get('core_path_qualified')):
        return _public_result(CURRENT_GROUPS.score_evidence(copy.deepcopy(evidence), require_current_graph=True))
    failures = {str(item) for item in original.get('failure_reasons', [])}
    rows = list(evidence.get('scenarios', []))
    narrow_failure = bool(failures) and failures <= ALLOWED_FALLBACK_FAILURES
    rows_valid = len(rows) == len(CURRENT_GROUPS.METRICS.REQUIRED) and all((isinstance(row, dict) and row.get('valid') is True for row in rows))
    saved = CURRENT_GROUPS.POLICY.evaluate_structure_graph
    CURRENT_GROUPS.POLICY.evaluate_structure_graph = _forced_policy(original)
    try:
        fallback = CURRENT_GROUPS.score_evidence(copy.deepcopy(evidence), require_current_graph=True)
    finally:
        CURRENT_GROUPS.POLICY.evaluate_structure_graph = saved
    utilities = fallback.get('diagnostics', {}).get('M_utilities', {})
    behavior_full = all((float(utilities.get(name, 0.0)) >= 1.0 - 1e-12 for name in BEHAVIOR_FIELDS))
    if not (narrow_failure and rows_valid and behavior_full):
        return _public_result(CURRENT_GROUPS.score_evidence(copy.deepcopy(evidence), require_current_graph=True))
    role_paths = original.get('role_specific_paths', {})
    graph_values = [bool(value) for value in role_paths.values()]
    graph_values.extend((bool(original.get(name)) for name in MECHANISM_FIELDS))
    graph_fraction = sum(graph_values) / len(graph_values)
    groups = dict(fallback['groups'])
    behavior_m = float(groups['M'])
    groups['M'] = min(behavior_m, graph_fraction)
    total = _strict_total(groups)
    result = copy.deepcopy(fallback)
    result['schema'] = 'simuverity.f90-xmed04-score.graph-behavior-confidence.v1'
    result['policy_id'] = PUBLIC_POLICY_ID
    result['groups'] = groups
    result['score'] = total
    result['raw_total'] = total
    result['total'] = total
    result['admission_score_pass'] = bool(total >= 85.0)
    result['mechanism_confidence'] = {'behavior_qualified': True, 'unverified_graph_facts': sorted(failures), 'required_behavior_utilities': {name: float(utilities[name]) for name in BEHAVIOR_FIELDS}, 'verified_graph_fact_count': sum(graph_values), 'required_graph_fact_count': len(graph_values), 'verified_graph_fraction': graph_fraction, 'behavior_M': behavior_m, 'scored_M': groups['M'], 'mechanism_aggregation': 'min(behavior_M, verified_graph_fraction)', 'post_total_adjustment': 'none'}
    return result
