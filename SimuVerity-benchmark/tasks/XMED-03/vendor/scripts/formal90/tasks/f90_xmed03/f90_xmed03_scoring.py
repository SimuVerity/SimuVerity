"""XMED-03 groups with strict cross-group geometric aggregation."""
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
SOURCE = TASK_DIR / 'f90_xmed03_scoring_core.py'
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.4, 'R': 0.15, 'D': 0.15}

def _load_source() -> ModuleType:
    spec = importlib.util.spec_from_file_location('f90_xmed03_current_pinned', SOURCE)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load XMED-03 SCORING_CORE scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
SCORING_CORE = _load_source()

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
    source = SCORING_CORE.score_evidence(evidence)
    result = copy.deepcopy(source)
    total = strict_geometric(source['G'], source['groups'])
    result.pop('shortcut_findings', None)
    result.update({'schema': 'simuverity.f90-xmed03-score.v1', 'policy_id': 'simuverity-101-v1:f90-xmed-03:scoring', 'score': total, 'raw_total': total, 'total': total, 'aggregation': {'method': 'G_times_strict_weighted_geometric_mean', 'weights': dict(WEIGHTS), 'strict_zero_rule': 'any_applicable_group_zero_means_total_zero', 'post_total_adjustment': 'none'}})
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
