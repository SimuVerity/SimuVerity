"""Criteria-backed, candidate-independent offline scorer for F90-XBATT-09."""
from __future__ import annotations
import argparse
import gzip
import json
from pathlib import Path
from typing import Any
import f90_xbatt09_scoring_core as base
TASK_ID = 'F90-XBATT-09'
SCORER_IMPLEMENTATION = 'f90_xbatt09_scoring'
MANIFEST_SCHEMA = 'simuverity.engineering-criteria-manifest.v1'
PAYLOAD_SCHEMA = 'simuverity.engineering-criteria-target-payload.v1'

def load_criteria_bundle(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    manifest = json.loads(path.read_text(encoding='utf-8'))
    if manifest.get('schema') != MANIFEST_SCHEMA or manifest.get('task_id') != TASK_ID:
        raise ValueError('engineering criteria manifest identity mismatch')
    if manifest.get('runtime_inputs') != ['candidate_evidence', 'engineering_criteria_bundle']:
        raise ValueError('engineering criteria runtime-input contract mismatch')
    contract = manifest.get('scoring_contract', {})
    descriptor = manifest.get('payload', {})
    payload_path = (path.parent / str(descriptor.get('file', ''))).resolve()
    if payload_path.parent != path.parent.resolve():
        raise ValueError('criteria payload must remain task-local')
    compressed = payload_path.read_bytes()
    raw = gzip.decompress(compressed)
    payload = json.loads(raw)
    if payload.get('schema') != PAYLOAD_SCHEMA or payload.get('task_id') != TASK_ID:
        raise ValueError('criteria payload identity mismatch')
    reference = {'task_id': TASK_ID, 'scenarios': payload.get('scenario_targets')}
    valid, failures = base.validate(reference)
    if not valid:
        raise ValueError('invalid criteria target bundle: ' + '; '.join(failures))
    return (manifest, reference)

def score_candidate(candidate: dict[str, Any], reference: dict[str, Any]) -> dict[str, Any]:
    return base.score(reference, candidate)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def add_metadata(result: dict[str, Any], manifest: dict[str, Any]) -> None:
    result.update({'criteria_scorer_implementation': SCORER_IMPLEMENTATION, 'engineering_criteria_id': manifest['criteria_id'], 'runtime_reference_evidence_read': False})

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate_evidence', type=Path)
    parser.add_argument('--criteria', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--shortcut-sanity-output', type=Path)
    args = parser.parse_args()
    manifest, reference = load_criteria_bundle(args.criteria)
    result = score_candidate(base.load_json(args.candidate_evidence), reference)
    add_metadata(result, manifest)
    write_json(args.output, result)
    if args.shortcut_sanity_output:
        sanity = base.shortcut_sanity(reference)
        sanity.update({'engineering_criteria_id': manifest['criteria_id']})
        write_json(args.shortcut_sanity_output, sanity)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
