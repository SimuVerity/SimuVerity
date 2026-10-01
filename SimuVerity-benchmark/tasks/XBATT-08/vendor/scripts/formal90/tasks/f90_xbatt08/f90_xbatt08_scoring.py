"""Criteria-backed, candidate-independent offline scorer for F90-XBATT-08."""
from __future__ import annotations
import argparse
import copy
import gzip
import json
from pathlib import Path
from typing import Any
import f90_xbatt08_scoring_core as core
TASK_ID = 'F90-XBATT-08'
SCORER_IMPLEMENTATION = 'f90_xbatt08_scoring'
MANIFEST_SCHEMA = 'simuverity.engineering-criteria-manifest.v1'
PAYLOAD_SCHEMA = 'simuverity.engineering-criteria-target-payload.v1'

def load_criteria_bundle(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    manifest = json.loads(path.read_text(encoding='utf-8'))
    if manifest.get('schema') != MANIFEST_SCHEMA or manifest.get('task_id') != TASK_ID:
        raise ValueError('engineering criteria manifest identity mismatch')
    if manifest.get('runtime_inputs') != ['candidate_evidence', 'engineering_criteria_bundle']:
        raise ValueError('engineering criteria runtime-input contract mismatch')
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
    valid, failures = core.validate(reference)
    if not valid:
        raise ValueError('invalid criteria target bundle: ' + '; '.join(failures))
    return (manifest, reference)

def score_candidate(candidate: dict[str, Any], reference: dict[str, Any]) -> dict[str, Any]:
    return core.score(reference, candidate)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def iter_shortcut_variants(reference: dict[str, Any]):
    missing = copy.deepcopy(reference)
    del missing['scenarios'][0]['logs']['storage_power']
    yield ('missing_storage_power', missing)
    fixed = copy.deepcopy(reference)
    mapped = core.scenario_map(fixed)
    for sid in core.SCENARIO_IDS[1:]:
        core.replace_logs(mapped[sid], mapped['baseline_all'])
    yield ('fixed_outputs_across_scenarios', fixed)
    for name, left, right in (('strategy_without_physical_effect', 'baseline_all', 'selected_default'), ('ultracap_mass_without_physical_effect', 'light_ultracap_all', 'heavy_ultracap_all'), ('battery_mass_without_physical_effect', 'light_battery_selected', 'heavy_battery_selected')):
        variant = copy.deepcopy(reference)
        mapped = core.scenario_map(variant)
        core.replace_logs(mapped[right], mapped[left])
        yield (name, variant)
    disconnected = copy.deepcopy(reference)
    for scenario in disconnected['scenarios']:
        for log_name in ('storage_current', 'storage_power'):
            width = len(scenario['logs'][log_name]['channels'])
            count = len(scenario['logs'][log_name]['time'])
            scenario['logs'][log_name]['data'] = [[0.0] * width for _ in range(count)]
    yield ('disconnected_storage_paths', disconnected)

def shortcut_sanity(reference: dict[str, Any]) -> dict[str, Any]:
    cases = []
    for name, variant in iter_shortcut_variants(reference):
        scored = core.score(reference, variant)
        cases.append({'id': name, 'raw_score': scored['raw_score'], 'gate': scored['gate'], 'group_scores': scored['group_scores'], 'failure_reasons': scored['failure_reasons'], 'passed_below_admission_threshold': scored['raw_score'] < 85.0})
    return {'schema': 'simuverity.f90-xbatt08-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'admission_threshold_raw': 85.0, 'cases': cases, 'maximum_shortcut_raw_score': max((item['raw_score'] for item in cases)), 'all_shortcuts_below_threshold': all((item['passed_below_admission_threshold'] for item in cases))}

def add_metadata(result: dict[str, Any], candidate_path: Path, criteria_path: Path, manifest: dict[str, Any]) -> None:
    result.update({'scorer_implementation': SCORER_IMPLEMENTATION, 'engineering_criteria_id': manifest['criteria_id'], 'runtime_reference_evidence_read': False})

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('candidate_evidence', type=Path)
    parser.add_argument('--criteria', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--shortcut-sanity-output', type=Path)
    args = parser.parse_args()
    manifest, reference = load_criteria_bundle(args.criteria)
    result = score_candidate(core.load_json(args.candidate_evidence), reference)
    add_metadata(result, args.candidate_evidence, args.criteria, manifest)
    write_json(args.output, result)
    if args.shortcut_sanity_output:
        sanity = shortcut_sanity(reference)
        sanity.update({'engineering_criteria_id': manifest['criteria_id']})
        write_json(args.shortcut_sanity_output, sanity)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
