"""No-post-total scorer for F90-XMECH-05 with public core gates."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
BASE_PATH = TASK_DIR / 'f90_xmech05_scoring_core.py'
CORE_QUALIFICATION_REASONS = {'missing_or_inadequate_multibody_contact_structure', 'nominal_mission_not_completed', 'lift_or_tilt_mechanism_inactive', 'wheel_contact_evidence_missing'}

def _load_base():
    spec = importlib.util.spec_from_file_location('xmech05_base_current', BASE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load current XMECH-05 base scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
BASE = _load_base()

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    base = BASE.score_evidence(evidence)
    groups = {name: float(value) for name, value in base['groups'].items()}
    source_rows = list(base.get('shortcut_findings', []))
    source_reasons = {str(row.get('reason', '')) for row in source_rows if isinstance(row, dict)}
    qualification_reasons = sorted(source_reasons & CORE_QUALIFICATION_REASONS)
    gate = int(base.get('G', 0))
    if qualification_reasons:
        gate = 0
    pre_qualification_total = 100.0 * BASE.geometric(groups)
    total = pre_qualification_total if gate == 1 else 0.0
    failures = list(base.get('failure_reasons', []))
    failures.extend((reason for reason in qualification_reasons if reason not in failures))
    return {**{key: value for key, value in base.items() if key not in {'G', 'score_raw', 'shortcut_findings', 'failure_reasons'}}, 'schema': 'simuverity.f90-xmech05-offline-score.v1', 'policy_id': 'simuverity-101-v1:f90_xmech-05:scoring', 'G': gate, 'groups': groups, 'group_scores': groups, 'score_raw': total, 'total_score': total, 'pre_qualification_geometric_total': pre_qualification_total, 'admission_pass': gate == 1 and total >= 85.0, 'failure_reasons': failures, 'qualification_reasons': qualification_reasons, 'post_total_cap_or_floor': False}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = score_evidence(json.loads(args.evidence.read_text(encoding='utf-8')))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f"F90-XMECH-05 offline G={result['G']} score={result['score_raw']:.4f} pass={int(result['admission_pass'])}")
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
