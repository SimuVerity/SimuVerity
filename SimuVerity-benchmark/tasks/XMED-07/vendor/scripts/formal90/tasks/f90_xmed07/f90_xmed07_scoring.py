"""XMED-07 score formula with its public-output structure gate."""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
METRIC_SCORER_PATH = TASK_DIR / 'f90_xmed07_scoring_core.py'
STRUCTURE_POLICY = TASK_DIR / 'f90_xmed07_structure_policy.py'
def _load(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot load offline dependency: {path.name}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
METRICS = _load(METRIC_SCORER_PATH, 'f90_xmed07_scoring_core_current_current')
POLICY = _load(STRUCTURE_POLICY, 'f90_xmed07_structure_policy_current')

def _evidence_with_structure_decision(evidence: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    if evidence.get('schema') != 'simuverity.f90-xmed07-evidence.v1':
        raise ValueError('XMED07 current scorer requires freshly extracted current evidence')
    contract = evidence.get('evidence_contract_valid')
    if contract is not False:
        raise ValueError('XMED07 evidence does not satisfy the current extraction contract')
    enriched = copy.deepcopy(evidence)
    static = enriched.setdefault('static_audit', {})
    graph = static.get('structure_port_graph')
    if not isinstance(graph, dict):
        raise ValueError('XMED07 current evidence is missing structure_port_graph')
    decision = POLICY.evaluate_structure_graph(graph)
    for field in POLICY.CORE_FIELDS:
        static[field] = bool(decision[field])
    static['motion_state_upstream_qualified'] = bool(decision['motion_state_upstream_qualified'])
    static['delivery_state_upstream_qualified'] = bool(decision['delivery_state_upstream_qualified'])
    static['safety_state_upstream_qualified'] = bool(decision['safety_state_upstream_qualified'])
    static['public_outputs_all_upstream_qualified'] = bool(decision['public_outputs_all_upstream_qualified'])
    static['structure_decision'] = decision
    return (enriched, decision)

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    enriched, decision = _evidence_with_structure_decision(evidence)
    result = METRICS.score(enriched)
    result['schema'] = 'simuverity.f90-xmed07-score.v1'
    result['policy_id'] = 'simuverity-101-v1:f90-xmed-07:scoring'
    result['structure_policy'] = 'f90_xmed07_structure_policy'
    result.setdefault('diagnostics', {})['structure_decision'] = decision
    return result

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    enriched, decision = _evidence_with_structure_decision(evidence)
    cases = {name: METRICS.score(case) for name, case in METRICS.sanity_cases(enriched).items()}
    return {'schema': 'simuverity.f90-xmed07-shortcut-sanity.v1', 'task_id': 'F90-XMED-07', 'case_scores': {name: value['raw_total_score'] for name, value in cases.items()}, 'dimension_level_detection': {name: METRICS.shortcut_case_detected(value) for name, value in cases.items()}, 'pass': all((METRICS.shortcut_case_detected(value) for value in cases.values())), 'details': cases, 'structure_decision': decision}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--shortcut-sanity', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score(evidence)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    if args.shortcut_sanity:
        sanity = shortcut_sanity(evidence)
        args.shortcut_sanity.parent.mkdir(parents=True, exist_ok=True)
        args.shortcut_sanity.write_text(json.dumps(sanity, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
