"""Criteria-backed, candidate-independent offline scorer for F90-XMECH-08."""
from __future__ import annotations
import argparse
import copy
import gzip
import json
from pathlib import Path
from typing import Any
import f90_xmech08_metric_ownership as METRIC_OWNERSHIP
TASK_ID = 'F90-XMECH-08'
SCORER_IDENTITY = 'f90_xmech08_scoring'
MANIFEST_SCHEMA = 'simuverity.engineering-criteria-manifest.v1'
PAYLOAD_SCHEMA = 'simuverity.engineering-criteria-target-payload.v1'
def load_criteria_bundle(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    path = path.resolve()
    manifest = json.loads(path.read_text(encoding='utf-8'))
    if manifest.get('schema') != MANIFEST_SCHEMA or manifest.get('task_id') != TASK_ID:
        raise ValueError('engineering criteria manifest identity mismatch')
    if manifest.get('runtime_inputs') != ['candidate_evidence', 'engineering_criteria_bundle']:
        raise ValueError('engineering criteria runtime-input contract mismatch')
    contract = manifest.get('scoring_contract', {})
    if contract.get('runtime_reads_source_reference_evidence') is not False:
        raise ValueError('source reference evidence must not be a runtime dependency')
    descriptor = manifest.get('payload', {})
    payload_path = (path.parent / str(descriptor.get('file', ''))).resolve()
    if payload_path.parent != path.parent:
        raise ValueError('criteria payload must remain task-local')
    compressed = payload_path.read_bytes()
    if len(compressed) != descriptor.get('compressed_bytes'):
        raise ValueError('criteria payload byte count mismatch')
    raw = gzip.decompress(compressed)
    if len(raw) != descriptor.get('uncompressed_bytes'):
        raise ValueError('decoded criteria payload byte count mismatch')
    payload = json.loads(raw)
    if payload.get('schema') != PAYLOAD_SCHEMA or payload.get('task_id') != TASK_ID:
        raise ValueError('criteria payload identity mismatch')
    target = copy.deepcopy(payload.get('qualification_target', {}))
    target.update({'task_id': TASK_ID, 'scenarios': payload.get('scenario_targets', [])})
    actual_ids = {str(row.get('id')) for row in target['scenarios']}
    if actual_ids != METRIC_OWNERSHIP.GROUP_RULES.STRUCTURE_SCORING.METRICS.REQUIRED_IDS:
        raise ValueError('criteria target scenario set mismatch')
    return (manifest, target)

def score_candidate(candidate: dict[str, Any], target: dict[str, Any], manifest: dict[str, Any], criteria_path: Path) -> dict[str, Any]:
    result = METRIC_OWNERSHIP.score(candidate, target)
    result.update({'criteria_scorer_identity': SCORER_IDENTITY, 'engineering_criteria_id': manifest['criteria_id'], 'runtime_reference_evidence_read': False})
    return result

def shortcut_sanity(target: dict[str, Any]) -> dict[str, Any]:
    return METRIC_OWNERSHIP.run_shortcut_sanity(target, target)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate_evidence', type=Path)
    parser.add_argument('--criteria', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--shortcut-sanity-output', type=Path)
    args = parser.parse_args()
    manifest, target = load_criteria_bundle(args.criteria)
    candidate = json.loads(args.candidate_evidence.read_text(encoding='utf-8'))
    result = score_candidate(candidate, target, manifest, args.criteria)
    write_json(args.output, result)
    if args.shortcut_sanity_output:
        sanity = shortcut_sanity(target)
        sanity.update({'engineering_criteria_id': manifest['criteria_id'], 'runtime_reference_evidence_read': False})
        write_json(args.shortcut_sanity_output, sanity)
    print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
