"""Current fixed-engineering-criteria scorer for F90-XAERO-09."""
from __future__ import annotations
import argparse
import copy
import gzip
import importlib.util
import json
from pathlib import Path
from typing import Any
_SOURCE_PATH = Path(__file__).with_name('f90_xaero09_scoring_core.py')
_SOURCE_SPEC = importlib.util.spec_from_file_location('f90_xaero09_scoring_core_module', _SOURCE_PATH)
if _SOURCE_SPEC is None or _SOURCE_SPEC.loader is None:
    raise RuntimeError(f'Cannot load {_SOURCE_PATH}')
_SOURCE = importlib.util.module_from_spec(_SOURCE_SPEC)
_SOURCE_SPEC.loader.exec_module(_SOURCE)
TASK_ID = 'F90-XAERO-09'
CRITERIA_SCHEMA = 'simuverity.engineering-criteria.v1'
CRITERIA_ID = 'simuverity-101-v1:f90-xaero-09:engineering-criteria'
PAYLOAD_FILENAME = 'f90_xaero09_engineering_criteria_targets.json.gz'
METRIC_KEYS = ('final_relative_attitude_rad', 'jet_activity_mean', 'tail_rate_rms_rad_s', 'jet_switch_count')

def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode('utf-8')

def project_authority_to_target_evidence(authority: dict[str, Any]) -> dict[str, Any]:
    rows = []
    for source_row in authority['scenarios']:
        rows.append({'id': source_row['id'], 'time_s': copy.deepcopy(source_row['time_s']), 'attitude_state': copy.deepcopy(source_row['attitude_state']), 'phase_plane_state': copy.deepcopy(source_row['phase_plane_state']), 'rcs_state': copy.deepcopy(source_row['rcs_state']), 'metrics': {key: copy.deepcopy(source_row['metrics'][key]) for key in METRIC_KEYS}, 'valid': source_row['valid']})
    target = {key: authority[key] for key in ('task_id', 'load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'evidence_complete')}
    target['scenarios'] = rows
    return target

def read_criteria(path: Path) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding='utf-8'))
    if manifest.get('schema') != CRITERIA_SCHEMA:
        raise ValueError('criteria schema mismatch')
    if manifest.get('task_id') != TASK_ID or manifest.get('criteria_id') != CRITERIA_ID:
        raise ValueError('criteria identity mismatch')
    if manifest.get('runtime_source_reference_required') is not False:
        raise ValueError('criteria runtime contract requires source evidence')
    if manifest.get('runtime_reference_model_access') is not False:
        raise ValueError('criteria runtime contract permits model access')
    metadata = manifest.get('scenario_targets', {})
    if metadata.get('payload_file') != PAYLOAD_FILENAME:
        raise ValueError('criteria payload filename mismatch')
    if metadata.get('payload_codec') != 'gzip-json':
        raise ValueError('criteria payload codec mismatch')
    payload_path = (path.resolve().parent / PAYLOAD_FILENAME).resolve()
    if payload_path.parent != path.resolve().parent:
        raise ValueError('criteria payload escapes task-local directory')
    compressed = payload_path.read_bytes()
    if len(compressed) < 10 or int.from_bytes(compressed[4:8], 'little') != 0:
        raise ValueError('criteria payload gzip mtime is not zero')
    try:
        decoded = gzip.decompress(compressed)
    except OSError as exception:
        raise ValueError('criteria payload gzip decode failed') from exception
    target_bundle = json.loads(decoded.decode('utf-8'))
    if canonical(target_bundle) != decoded:
        raise ValueError('criteria payload is not canonical UTF-8 JSON')
    loaded = copy.deepcopy(manifest)
    loaded['_criteria_path'] = str(path.resolve())
    loaded['_payload_path'] = str(payload_path)
    loaded['_decoded_target_bundle'] = target_bundle
    return loaded

def target_evidence(criteria: dict[str, Any]) -> dict[str, Any]:
    target_bundle = criteria.get('_decoded_target_bundle')
    if not isinstance(target_bundle, dict):
        raise ValueError('criteria bundle was not loaded by read_criteria')
    decoded = canonical(target_bundle)
    scenarios = target_bundle.get('scenario_targets')
    if not isinstance(scenarios, list):
        raise ValueError('decoded target scenarios are missing')
    qualifications = criteria.get('qualification_targets', {})
    target = {key: copy.deepcopy(value) for key, value in qualifications.items()}
    target['scenarios'] = copy.deepcopy(scenarios)
    valid, failures = _SOURCE.validate(target)
    if not valid:
        raise ValueError('fixed criteria validation failed: ' + ';'.join(failures))
    return target

def score(criteria: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(_SOURCE.score(target_evidence(criteria), candidate))
    result['schema'] = 'simuverity.f90-xaero09-score.v1'
    result['criteria_id'] = CRITERIA_ID
    result['runtime_reference_evidence_read'] = False
    result['target_semantics'] = 'fixed_engineering_criteria'
    causal_metrics = result.get('causal_metrics')
    if isinstance(causal_metrics, dict) and 'reference' in causal_metrics:
        causal_metrics['criterion_targets'] = causal_metrics.pop('reference')
    return result

def shortcut_sanity(criteria: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(_SOURCE.shortcuts(target_evidence(criteria)))
    result['schema'] = 'simuverity.f90-xaero09-shortcut-sanity.v1'
    result['criteria_id'] = CRITERIA_ID
    return result

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--criteria', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--score-output', type=Path)
    parser.add_argument('--shortcut-sanity-output', type=Path)
    args = parser.parse_args()
    criteria = read_criteria(args.criteria)
    result = score(criteria, _SOURCE.read(args.candidate))
    if args.score_output:
        _SOURCE.write(args.score_output, result)
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False))
    if args.shortcut_sanity_output:
        _SOURCE.write(args.shortcut_sanity_output, shortcut_sanity(criteria))
if __name__ == '__main__':
    main()
