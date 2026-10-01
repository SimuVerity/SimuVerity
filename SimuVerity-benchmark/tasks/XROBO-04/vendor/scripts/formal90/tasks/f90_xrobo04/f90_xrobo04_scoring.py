"""XROBO-04 scorer with direction-neutral low-friction energy response."""
from __future__ import annotations
import copy
import importlib.util
import json
import math
import sys
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
GROUP_SCORING_PATH = TASK_DIR / 'f90_xrobo04_reference_compatibility.py'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-04:scoring'
ADMISSION_THRESHOLD = 90.0

def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot import GROUP_SCORING scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
GROUP_SCORING = _load(GROUP_SCORING_PATH, 'f90_xrobo04_current_for')

def _energy_per_m(summary: dict[str, Any]) -> float | None:
    energy = GROUP_SCORING.SCORING_CORE.number(summary.get('final_energy_Wh'))
    distance = GROUP_SCORING.SCORING_CORE.number(summary.get('distance_travelled_m'))
    if not math.isfinite(energy) or not math.isfinite(distance) or distance <= 0.0:
        return None
    value = energy / distance
    return value if math.isfinite(value) else None

def derive_friction_energy_response(evidence: dict[str, Any], existing_slip_response: float, terrain_response: float) -> dict[str, Any]:
    rows = {str(row['id']): row['summary'] for row in evidence['scenarios']}
    nominal = rows['nominal_path1_uneven']
    low_friction = rows['path1_low_friction']
    nominal_energy_per_m = _energy_per_m(nominal)
    low_friction_energy_per_m = _energy_per_m(low_friction)
    valid_ratio = nominal_energy_per_m is not None and low_friction_energy_per_m is not None and (nominal_energy_per_m > 0.0) and (low_friction_energy_per_m >= 0.0)
    energy_change = abs(low_friction_energy_per_m / nominal_energy_per_m - 1.0) if valid_ratio else None
    energy_utility = GROUP_SCORING.SCORING_CORE.high(energy_change, 0.05, 0.5) if energy_change is not None else 0.0
    slip_utility = GROUP_SCORING.SCORING_CORE.clamp(existing_slip_response)
    friction_response = max(slip_utility, energy_utility)
    return {'executed': True, 'nominal_energy_per_m_Wh_per_m': nominal_energy_per_m, 'low_friction_energy_per_m_Wh_per_m': low_friction_energy_per_m, 'absolute_relative_energy_change': energy_change, 'energy_response_zero_point': 0.05, 'energy_response_full_point': 0.5, 'energy_utility': energy_utility, 'existing_slip_response': slip_utility, 'friction_response': friction_response, 'multi_condition_contact_response': min(GROUP_SCORING.SCORING_CORE.clamp(terrain_response), friction_response), 'invalid_ratio_falls_back_to_energy_utility_zero': not valid_ratio}

def _apply(evidence: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    result['schema'] = 'simuverity.f90-xrobo04-score.v1'
    result['policy_id'] = POLICY_ID
    result['admission_threshold'] = ADMISSION_THRESHOLD
    result['preferred_reference_score'] = ADMISSION_THRESHOLD
    result['admission_score_pass'] = bool(result['G'] and result['total'] >= ADMISSION_THRESHOLD)
    if not result['G']:
        result.setdefault('per_metric', {})['friction_energy_response'] = {'executed': False, 'energy_utility': 0.0, 'reason': 'qualification_gate_failed'}
        return result
    m_parts = dict(result['per_metric']['M_behavioral_utilities'])
    response = derive_friction_energy_response(evidence, m_parts['friction_intervention_response'], m_parts['terrain_intervention_response'])
    m_parts['friction_intervention_response'] = response['friction_response']
    m_parts['multi_condition_contact_response'] = response['multi_condition_contact_response']
    result['per_metric']['M_behavioral_utilities'] = m_parts
    result['per_metric']['friction_energy_response'] = response
    result['groups']['M'] = GROUP_SCORING.SCORING_CORE.weighted(m_parts, {'terrain_intervention_response': 0.2, 'friction_intervention_response': 0.15, 'multi_condition_contact_response': 0.2, 'physical_motion_energy_coupling': 0.2, 'mobile_manipulation_mission': 0.25})
    result['M'] = result['groups']['M']
    total = GROUP_SCORING.SCORING_CORE.geometric(result['groups'])
    result['raw_total'] = total
    result['total'] = total
    result['score'] = total
    result['admission_score_pass'] = bool(total >= ADMISSION_THRESHOLD)
    old_group_failures = {name + ' group below 0.60' for name in GROUP_SCORING.SCORING_CORE.WEIGHTS}
    failures = [reason for reason in result['failure_reasons'] if reason not in old_group_failures]
    failures.extend((name + ' group below 0.60' for name in GROUP_SCORING.SCORING_CORE.WEIGHTS if result['groups'][name] < 0.6))
    result['failure_reasons'] = list(dict.fromkeys(failures))
    return result

def score_candidate(evidence: dict[str, Any]) -> dict[str, Any]:
    return _apply(evidence, GROUP_SCORING.score_candidate(copy.deepcopy(evidence)))

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    """Candidate-scoring alias used by task-local wrappers."""
    return score_candidate(evidence)

def score_reference(evidence: dict[str, Any]) -> dict[str, Any]:
    return _apply(evidence, GROUP_SCORING.score_reference(copy.deepcopy(evidence)))

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
