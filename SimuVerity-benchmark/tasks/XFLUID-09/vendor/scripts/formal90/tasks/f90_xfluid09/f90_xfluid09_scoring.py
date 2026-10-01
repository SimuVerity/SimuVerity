"""Candidate-independent F90-XFLUID-09 scorer without post-total adjustment."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
BASE_PATH = TASK_DIR / 'f90_xfluid09_scoring_core.py'

def _load_base():
    spec = importlib.util.spec_from_file_location('xfluid09_base_current', BASE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load current XFLUID-09 base scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
BASE = _load_base()

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    base = BASE.score(evidence)
    groups = {name: float(value) for name, value in base['groups'].items()}
    qualified = bool(base.get('valid')) and float(base.get('G', 0.0)) == 1.0
    total = float(base['raw_total']) if qualified else 0.0
    result = {key: value for key, value in base.items() if key not in {'policy_id', 'total'}}
    return {**result, 'schema': 'simuverity.f90-xfluid09-score.v1', 'policy_id': 'simuverity-101-v1:f90-xfluid-09:scoring', 'groups': groups, 'group_scores': groups, 'total': total, 'total_score': total, 'post_total_cap_or_floor': False}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = score(json.loads(args.evidence.read_text(encoding='utf-8')))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
