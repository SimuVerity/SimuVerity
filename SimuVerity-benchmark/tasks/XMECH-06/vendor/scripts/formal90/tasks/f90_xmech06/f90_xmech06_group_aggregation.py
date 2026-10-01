"""Pure-offline XMECH-06 scorer with critical-mechanism aggregation.

The task-specific evidence-to-utility calculations feed the declared group
aggregation and top-level weights.  This module never starts MATLAB.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import math
from pathlib import Path
from types import ModuleType
from typing import Any
POLICY_ID = 'simuverity-101-v1:f90-xmech-06:scoring'
WEIGHTS = {'A': 0.15, 'Q': 0.1, 'M': 0.3, 'R': 0.15, 'D': 0.3}
CORE_MECHANISM_KEYS = ('connected_static_path', 'active_four_wheel_forces', 'active_suspension', 'force_acceleration_causality')

def _load_policy_core() -> ModuleType:
    path = Path(__file__).with_name('f90_xmech06_scoring_core.py')
    spec = importlib.util.spec_from_file_location('f90_xmech06_scoring_core_pinned', path)
    if spec is None or spec.loader is None:
        raise RuntimeError('XMECH06_current_SCORER_DEPENDENCY_IMPORT_FAILED')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    base = _load_policy_core().score_evidence(evidence)
    base['schema'] = 'simuverity.f90-xmech06-score.v1'
    base['policy_id'] = POLICY_ID
    base['formula'] = 'G*100*A^0.15*Q^0.10*M^0.30*R^0.15*D^0.30'
    if not bool(base.get('G')):
        return base
    diagnostics = base['diagnostics']
    findings = diagnostics['shortcut_findings']
    m_parts = diagnostics['M_utilities']
    d_parts = diagnostics['D_utilities']
    core_min = min((float(m_parts[name]) for name in CORE_MECHANISM_KEYS))
    official_causality = float(m_parts['official_input_causality'])
    mechanism = math.sqrt(max(0.0, core_min) * max(0.0, official_causality))
    dynamics = min((float(value) for value in d_parts.values()))
    groups = dict(base['groups'])
    groups['M'] = mechanism
    groups['D'] = dynamics
    total = 100.0
    for name, weight in WEIGHTS.items():
        total *= max(float(groups[name]), 0.0) ** weight
    diagnostics['M_aggregation'] = {'method': 'sqrt(core_mechanism_min*official_input_causality)', 'core_mechanism_keys': list(CORE_MECHANISM_KEYS), 'core_mechanism_min': core_min, 'official_input_causality': official_causality}
    diagnostics['D_aggregation'] = {'method': 'minimum', 'items': list(d_parts)}
    diagnostics['top_level_weights'] = dict(WEIGHTS)
    failures = [f'{name} group below 0.60' for name in WEIGHTS if float(groups[name]) < 0.6]
    failures.extend((str(item['reason']) for item in findings))
    base['groups'] = groups
    base['score'] = float(total)
    base['admission_score_pass'] = bool(total >= 85.0)
    base['failure_reasons'] = failures
    return base

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'score': result['score'], 'groups': result['groups'], 'out': str(out)}))
if __name__ == '__main__':
    main()
