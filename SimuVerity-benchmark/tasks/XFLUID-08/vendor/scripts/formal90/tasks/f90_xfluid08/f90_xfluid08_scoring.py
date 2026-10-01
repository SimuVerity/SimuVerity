"""XFLUID-08 current candidate groups with strict geometric aggregation."""
from __future__ import annotations
import copy
import argparse
import importlib.util
import json
import math
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
SOURCE = TASK_DIR / 'f90_xfluid08_candidate_scoring_core.py'
CURRENT_SOURCE = TASK_DIR / 'f90_xfluid08_scoring_core.py'
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}

def _load_source() -> ModuleType:
    spec = importlib.util.spec_from_file_location('f90_xfluid08_candidate_current_pinned', SOURCE)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load XFLUID-08 candidate scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
SOURCE_MODULE = _load_source()

def _load_current_source() -> ModuleType:
    spec = importlib.util.spec_from_file_location('f90_xfluid08_current_pinned', CURRENT_SOURCE)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load XFLUID-08 current scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
CURRENT_MODULE = _load_current_source()

def strict_geometric(gate: object, groups: dict[str, Any]) -> float:
    if float(gate) not in (0.0, 1.0):
        raise ValueError('G must be exactly 0 or 1')
    values = {name: float(groups[name]) for name in WEIGHTS}
    if any((not math.isfinite(value) or value < 0.0 or value > 1.0 for value in values.values())):
        raise ValueError('applicable groups must be finite and in [0, 1]')
    if float(gate) == 0.0 or any((value == 0.0 for value in values.values())):
        return 0.0
    return 100.0 * math.exp(sum((WEIGHTS[name] * math.log(values[name]) for name in WEIGHTS)))

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    prepared = copy.deepcopy(evidence)
    candidate_shape = bool(prepared.get('scenarios')) and all((isinstance(row.get('offline_metrics'), dict) for row in prepared.get('scenarios', [])))
    transition = None
    behavior = None
    if candidate_shape:
        transition = SOURCE_MODULE._attach_transition_metric_compatibility(prepared, CURRENT_MODULE)
        behavior = SOURCE_MODULE._prepare_candidate_evidence(prepared)
    else:
        raw_path = Path(str(prepared['raw_artifact']['path']))
        CURRENT_MODULE.attach_offline_derivations(prepared, raw_path)
    source = CURRENT_MODULE.score(prepared)
    result = copy.deepcopy(source)
    total = strict_geometric(source['G'], source['groups'])
    result.update({'schema': 'simuverity.f90-xfluid08-score.v1', 'policy_id': 'simuverity-101-v1:f90-xfluid-08:scoring', 'score_raw': total, 'score': total, 'total': total, 'admission_pass': bool(source['G'] and total >= float(source['admission_threshold_raw'])), 'evidence_role_compatibility': 'candidate_complete_public_outputs' if candidate_shape else 'reference_evidence_and_complete_raw_artifact', 'total_aggregation': {'method': 'G_times_strict_weighted_geometric_mean', 'weights': dict(WEIGHTS), 'strict_zero_rule': 'any_applicable_group_zero_means_total_zero', 'post_total_adjustment': 'none'}})
    if behavior is not None:
        result['qualification_witnesses'] = behavior
    if transition is not None:
        result['candidate_metric_compatibility'] = transition
    return result

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    result = score_evidence(json.loads(args.evidence.read_text(encoding='utf-8-sig')))
    text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding='utf-8')
    print(text, end='')
if __name__ == '__main__':
    main()
