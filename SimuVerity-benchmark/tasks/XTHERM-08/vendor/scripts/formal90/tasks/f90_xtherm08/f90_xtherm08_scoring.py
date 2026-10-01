"""Current mechanism-aware scorer for F90-XTHERM-08."""
from __future__ import annotations
import copy
import importlib.util
import math
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
CURRENT_SCORER = TASK_DIR / 'f90_xtherm08_scoring_core.py'
PHYSICAL_WEIGHT = 0.75
CONTROL_WEIGHT = 0.25

def _load_current() -> ModuleType:
    spec = importlib.util.spec_from_file_location('f90_xtherm08_current', CURRENT_SCORER)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load current XTHERM08 scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
CURRENT = _load_current()

def _strict_total(groups: dict[str, float]) -> float:
    if any((float(groups[name]) <= 0.0 for name in CURRENT.WEIGHTS)):
        return 0.0
    return 100.0 * math.exp(sum((CURRENT.WEIGHTS[name] * math.log(float(groups[name])) for name in CURRENT.WEIGHTS)))

def mechanism_factor(structure: dict[str, Any]) -> float:
    physical = float(structure.get('physical_device_observations_score', 0.0))
    control = float(structure.get('control_loop_observations_score', 0.0))
    return max(0.0, min(1.0, PHYSICAL_WEIGHT * physical + CONTROL_WEIGHT * control))

def apply_confidence(current_result: dict[str, Any], structure: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(current_result)
    if float(result.get('groups', {}).get('G', 0.0)) != 1.0:
        return result
    groups = {key: float(value) for key, value in result['groups'].items()}
    current_m = groups['M']
    factor = mechanism_factor(structure)
    groups['M'] = current_m * factor
    total = _strict_total(groups)
    result.update({'schema': 'simuverity.f90-xtherm08-score.v1', 'policy_id': 'simuverity-101-v1:f90-xtherm-08:scoring', 'groups': groups, 'score': total, 'admission_score_pass': total >= 90.0})
    result.setdefault('diagnostics', {})['mechanism_confidence'] = {'physical_device_observations_score': float(structure['physical_device_observations_score']), 'physical_device_observations_tier': structure['physical_device_observations_tier'], 'control_loop_observations_score': float(structure['control_loop_observations_score']), 'physical_weight': PHYSICAL_WEIGHT, 'control_weight': CONTROL_WEIGHT, 'mechanism_confidence_factor': factor, 'current_dynamic_causality_M': current_m, 'adjusted_M': groups['M'], 'aggregation': 'current_M * (0.75*physical_observations + 0.25*control_observations)', 'post_total_adjustment': 'none'}
    return result

def score_evidence(evidence: dict[str, Any], structure: dict[str, Any]) -> dict[str, Any]:
    if structure.get('schema') != 'simuverity.f90-xtherm08-structure-audit.v1':
        raise ValueError('wrong XTHERM08 structure-audit schema')
    if structure.get('task_id') != 'F90-XTHERM-08':
        raise ValueError('structure audit task mismatch')
    corrected = copy.deepcopy(evidence)
    corrected.setdefault('static_audit', {})['core_path_qualified'] = bool(structure.get('core_semantics_qualified'))
    current_result = CURRENT.score(corrected)
    return apply_confidence(current_result, structure)
