"""XROBO-04 scoring with reference-evidence metadata normalization."""
from __future__ import annotations
import copy
import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
SCORING_CORE_PATH = TASK_DIR / 'f90_xrobo04_scoring_core.py'

def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot import SCORING_CORE scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
SCORING_CORE = _load(SCORING_CORE_PATH, 'f90_xrobo04_current_for')

def normalize_reference(evidence: dict[str, Any]) -> dict[str, Any]:
    """Supply the runtime-smoke field when absent from reference evidence."""
    normalized = copy.deepcopy(evidence)
    scenarios = normalized.get('scenarios', [])
    nominal_ok = bool(isinstance(scenarios, list) and scenarios and isinstance(scenarios[0], dict) and (scenarios[0].get('simulation_pass') is True) and (scenarios[0].get('valid') is True))
    normalized['nominal_smoke_pass'] = nominal_ok
    normalized['reference_evidence_normalization'] = {'derived_field': 'nominal_smoke_pass', 'derivation': 'first required scenario simulation_pass && valid'}
    return normalized

def score_candidate(evidence: dict[str, Any]) -> dict[str, Any]:
    result = SCORING_CORE.score_evidence(copy.deepcopy(evidence))
    result['policy_id'] = 'simuverity-101-v1:f90-xrobo-04:scoring'
    result['subject_role'] = 'candidate'
    return result

def score_reference(evidence: dict[str, Any]) -> dict[str, Any]:
    normalized = normalize_reference(evidence)
    result = SCORING_CORE.score_evidence(normalized)
    result['policy_id'] = 'simuverity-101-v1:f90-xrobo-04:scoring'
    result['subject_role'] = 'reference'
    result['reference_evidence_normalization'] = normalized['reference_evidence_normalization']
    return result

def main() -> None:
    if len(sys.argv) != 4 or sys.argv[1] not in {'candidate', 'reference'}:
        raise SystemExit('usage: scorer.py candidate|reference EVIDENCE OUTPUT')
    role, source_name, output_name = sys.argv[1:]
    source = Path(source_name)
    evidence = json.loads(source.read_text(encoding='utf-8-sig'))
    result = score_candidate(evidence) if role == 'candidate' else score_reference(evidence)
    output = Path(output_name)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
