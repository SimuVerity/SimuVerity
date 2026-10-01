"""Current XAERO-10 scorer using fixed engineering criteria."""
from __future__ import annotations
import argparse, gzip, json
from pathlib import Path
from typing import Any
import f90_xaero10_intervention_response as intervention_response
TASK_ID = 'F90-XAERO-10'
CRITERIA_SCHEMA = 'simuverity.engineering-criteria.v1'

def read_criteria(path: Path) -> dict[str, Any]:
    path = path.resolve()
    value = json.loads(path.read_text(encoding='utf-8'))
    if value.get('schema') != CRITERIA_SCHEMA or value.get('task_id') != TASK_ID:
        raise ValueError('criteria schema/task mismatch')
    if value.get('runtime_source_reference_required') is not False:
        raise ValueError('criteria must be runtime self-contained')
    value['_bundle_root'] = str(path.parent)
    return value

def target_evidence(criteria: dict[str, Any]) -> dict[str, Any]:
    meta = criteria['scenario_targets']
    root = Path(criteria.get('_bundle_root', Path(__file__).resolve().parent)).resolve()
    payload = (root / meta['payload_file']).resolve()
    if payload.parent != root:
        raise ValueError('criteria payload must remain task-local')
    compressed = payload.read_bytes()
    decoded = gzip.decompress(compressed)
    target = dict(criteria['qualification_targets'])
    target['scenarios'] = json.loads(decoded)['scenario_targets']
    return target

def _criterion_result(result: dict[str, Any], criteria: dict[str, Any]) -> dict[str, Any]:
    metrics = result.get('metrics')
    if isinstance(metrics, dict) and 'reference_intervention_effects' in metrics:
        metrics['criterion_intervention_effect_targets'] = metrics.pop('reference_intervention_effects')
    result.update({'schema': 'simuverity.f90-xaero10-score.criteria.v1', 'scorer_implementation': 'f90_xaero10_scoring', 'criteria_id': criteria['criteria_id'], 'runtime_reference_evidence_read': False, 'target_semantics': 'fixed_engineering_criteria'})
    return result

def score(criteria: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    return _criterion_result(intervention_response.score(target_evidence(criteria), candidate), criteria)

def shortcut_sanity(criteria: dict[str, Any]) -> dict[str, Any]:
    return intervention_response.core.shortcuts(target_evidence(criteria))

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--criteria', required=True, type=Path)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--score-output', type=Path)
    parser.add_argument('--shortcut-sanity', type=Path)
    args = parser.parse_args()
    criteria = read_criteria(args.criteria)
    if args.shortcut_sanity:
        intervention_response.core.write(args.shortcut_sanity, shortcut_sanity(criteria))
    if args.candidate:
        if not args.score_output:
            parser.error('--score-output is required with --candidate')
        output = score(criteria, intervention_response.core.read(args.candidate))
        intervention_response.core.write(args.score_output, output)
    elif args.score_output:
        parser.error('--candidate is required with --score-output')
if __name__ == '__main__':
    main()
