"""XMED-04 non-compensatory, all-scenario pure-offline scorer."""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
METRIC_SCORER_PATH = TASK_DIR / 'f90_xmed04_scoring_core_core.py'
POLICY_PATH = TASK_DIR / 'f90_xmed04_structure_policy.py'
WEIGHTS = {'A': 0.1, 'Q': 0.1, 'M': 0.35, 'R': 0.3, 'D': 0.15}
FORMULA = 'G*100*A^0.10*Q^0.10*M^0.35*R^0.30*D^0.15'

def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot load offline dependency: {path.name}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
METRICS = _load(METRIC_SCORER_PATH, 'f90_xmed04_current_for')
POLICY = _load(POLICY_PATH, 'f90_xmed04_policy_current_for')

def _prepare_evidence(evidence: dict[str, Any], *, require_current_graph: bool) -> tuple[dict[str, Any], str]:
    schema = evidence.get('schema')
    if require_current_graph and schema != 'simuverity.f90-xmed04-evidence.v1':
        raise ValueError('XMED04 current candidate scoring requires current evidence')
    if schema not in {'simuverity.f90-xmed04-evidence.v1', 'simuverity.f90-xmed04-evidence.v1'}:
        raise ValueError('XMED04 current scorer received unsupported evidence')
    enriched = copy.deepcopy(evidence)
    static = enriched.setdefault('static_audit', {})
    if schema == 'simuverity.f90-xmed04-evidence.v1':
        graph = static.get('port_graph')
        if not isinstance(graph, dict):
            raise ValueError('XMED04 current evidence is missing port_graph')
        decision = POLICY.evaluate_structure_graph(graph)
        static['core_path_qualified'] = bool(decision['core_path_qualified'])
        static['structure_decision'] = decision
        return (enriched, 'f90_xmed04_structure_policy')
    if not bool(static.get('core_path_qualified')):
        raise ValueError('reference evidence lacks a qualified core path')
    return (enriched, 'reference_static_audit')

def score_evidence(evidence: dict[str, Any], *, require_current_graph: bool=True) -> dict[str, Any]:
    enriched, structure_policy = _prepare_evidence(evidence, require_current_graph=require_current_graph)
    receipt = METRICS.score_evidence(enriched)
    base_groups = copy.deepcopy(receipt['groups'])
    receipt['schema'] = 'simuverity.f90-xmed04-score.v1'
    receipt['policy_id'] = 'simuverity-101-v1:f90-xmed-04:scoring'
    receipt['formula'] = FORMULA
    receipt['structure_policy'] = structure_policy
    if not receipt.get('G'):
        return receipt
    summaries = receipt['diagnostics']['raw_summaries']
    q_scenario_utilities: dict[str, dict[str, float]] = {}
    q_scenario_scores: dict[str, float] = {}
    bounded_insulin: dict[str, float] = {}
    for name in METRICS.REQUIRED:
        summary = summaries[name]
        parts = {'sensor_fidelity': METRICS.low(float(summary['sensor_rmse_mg_dL']), 4.0, 35.0), 'nonnegative_insulin': METRICS.high(float(summary['insulin_min_mU_min']), -1.0, 0.0), 'glucose_variability': METRICS.low(float(summary['glucose_cv']), 0.2, 0.8), 'nonconstant_insulin': METRICS.high(float(summary['insulin_std_mU_min']), 0.02, 0.5)}
        q_scenario_utilities[name] = parts
        q_scenario_scores[name] = METRICS.weighted(list(parts.values()), [0.6, 0.1, 0.1, 0.1])
        bounded_insulin[name] = METRICS.low(float(summary['insulin_max_mU_min']), 200.0, 1000.0)
    Q = min(q_scenario_scores.values())
    m_utilities = receipt['diagnostics']['M_utilities']
    M = min((float(value) for value in m_utilities.values()))
    source_r = receipt['diagnostics']['R_scenario_scores']
    R = min(min((float(value) for value in source_r.values())), min(bounded_insulin.values()))
    groups = {'G': 1.0, 'A': float(base_groups['A']), 'Q': Q, 'M': M, 'R': R, 'D': float(base_groups['D'])}
    total = 100.0
    for name, exponent in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** exponent
    receipt['groups'] = groups
    receipt['score'] = total
    receipt['admission_score_pass'] = bool(total >= 85.0)
    receipt['diagnostics'].update({'base_formula_groups': base_groups, 'Q_scenario_utilities': q_scenario_utilities, 'Q_scenario_scores': q_scenario_scores, 'Q_aggregation': 'minimum_across_required_scenarios', 'M_aggregation': 'minimum', 'bounded_insulin_scenario_utilities': bounded_insulin, 'R_aggregation': 'minimum_of_scenario_safety_and_worst_case_bounded_insulin'})
    return receipt

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence')
    parser.add_argument('--out')
    parser.add_argument('--allow-reference-static-audit', action='store_true', help='accept current reference evidence without a current port graph')
    args = parser.parse_args()
    source = Path(args.evidence)
    output = Path(args.out) if args.out else source.with_name('offline_score.json')
    result = score_evidence(json.loads(source.read_text(encoding='utf-8')), require_current_graph=not args.allow_reference_static_audit)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    print(output)
if __name__ == '__main__':
    main()
