"""XMED-05 current formula with MATLAB JSON graph preservation."""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
METRIC_SCORER_PATH = TASK_DIR / 'f90_xmed05_scoring_core.py'
POLICY_PATH = TASK_DIR / 'f90_xmed05_structure_policy.py'
def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot load offline dependency: {path.name}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
METRICS = _load(METRIC_SCORER_PATH, 'f90_xmed05_current_current')
POLICY = _load(POLICY_PATH, 'f90_xmed05_policy_current_current')

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    if evidence.get('schema') != 'simuverity.f90-xmed05-evidence.v1':
        raise ValueError('XMED05 current scorer requires complete current evidence')
    enriched = copy.deepcopy(evidence)
    static = enriched.setdefault('static_audit', {})
    graph = static.get('structure_port_graph')
    if not isinstance(graph, dict):
        raise ValueError('XMED05 current evidence is missing structure_port_graph')
    decision = POLICY.evaluate_structure_graph(graph)
    static['minimum_hybrid_closed_loop_signature'] = bool(decision['minimum_hybrid_closed_loop_signature'])
    static['structure_decision'] = decision
    receipt = METRICS.score_evidence(enriched)
    receipt['schema'] = 'simuverity.f90-xmed05-score.v1'
    receipt['structure_policy'] = 'f90_xmed05_structure_policy'
    receipt.setdefault('diagnostics', {})['structure_decision'] = decision
    receipt['complete_evidence_reused_without_matlab'] = True
    return receipt

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence')
    parser.add_argument('--out')
    args = parser.parse_args()
    source = Path(args.evidence)
    output = Path(args.out) if args.out else source.with_name('offline_score.json')
    result = score_evidence(json.loads(source.read_text(encoding='utf-8')))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    print(output)
if __name__ == '__main__':
    main()
