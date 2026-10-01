"""XROBO-02 structure-compatible groups with strict geometric total.

Candidate evidence uses an implementation-neutral audit, while reference
evidence uses a direct Simscape joint audit.  Both audits are
reduced to the same eight canonical mechanism facts and then passed through
the same metric/group formula and strict weighted geometric aggregation,
with no epsilon floor and no post-total cap.
"""
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
METRICS_PATH = TASK_DIR / 'f90_xrobo02_scoring_core_core.py'
GROUP_SCORING_PATH = TASK_DIR / 'f90_xrobo02_scoring_core.py'
CANONICAL_AUDIT_FIELDS = ('joint_count_14', 'all_input_torque', 'all_computed_motion', 'all_position_sensed', 'all_velocity_sensed', 'all_torque_ports_connected', 'controller_present', 'no_prescribed_trajectory_blocks')
WEIGHTS = {'A': 0.15, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.25}

def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot import dependency: {path}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
METRICS = _load(METRICS_PATH, 'f90_xrobo02_current_for')
GROUP_SCORING = _load(GROUP_SCORING_PATH, 'f90_xrobo02_current_for')

def strict_geometric_total(gate: bool, groups: dict[str, float | None]) -> float:
    if not gate:
        return 0.0
    values: list[tuple[float, float]] = []
    for name, weight in WEIGHTS.items():
        value = groups.get(name)
        if value is None:
            continue
        score = float(value)
        if not math.isfinite(score) or score < 0.0 or score > 1.0:
            raise ValueError(f'invalid {name} group score: {score}')
        if score <= 0.0:
            return 0.0
        values.append((score, weight))
    weight_sum = sum((weight for _, weight in values))
    if not values or weight_sum <= 0.0:
        raise ValueError('no applicable positive-weight groups')
    return 100.0 * math.exp(sum((weight / weight_sum * math.log(score) for score, weight in values)))

def _finish(*, role: str, groups: dict[str, float], gate: bool, scenarios: list[dict[str, Any]], static_audit: dict[str, Any], utility_metrics: dict[str, Any], gate_reasons: list[str]) -> dict[str, Any]:
    normalized = {name: float(groups.get(name, 0.0)) for name in ('A', 'Q', 'M', 'R', 'D')}
    all_groups: dict[str, float | None] = {'G': float(bool(gate)), **normalized, 'C': None}
    total = strict_geometric_total(gate, all_groups)
    return {'schema': 'simuverity.f90-xrobo02-score.v1', 'formal_task_id': 'F90-XROBO-02', 'policy_id': 'simuverity-101-v1:f90-xrobo-02:scoring', 'subject_role': role, 'offline_only': True, 'score_inputs_valid': bool(gate), 'diagnostics_valid': bool(gate), 'G': bool(gate), 'A': normalized['A'], 'Q': normalized['Q'], 'M': normalized['M'], 'C': None, 'R': normalized['R'], 'D': normalized['D'], 'groups': all_groups, 'group_weights': dict(WEIGHTS), 'score': total, 'raw_total': total, 'total': total, 'failure_reasons': list(gate_reasons), 'gate_reasons': list(gate_reasons), 'scenarios': copy.deepcopy(scenarios), 'static_audit': copy.deepcopy(static_audit), 'utility_metrics': copy.deepcopy(utility_metrics), 'canonical_mechanism_audit': {field: int(bool(static_audit.get(field, 0))) for field in CANONICAL_AUDIT_FIELDS}, 'total_aggregation': {'method': 'G_times_weighted_geometric_mean', 'formula': 'G*100*product(group_score^(weight/sum_applicable_weights))', 'strict_zero_rule': 'any_applicable_group_le_zero_means_total_zero', 'not_applicable_groups_excluded': True, 'epsilon_floor': 'none', 'post_group_score_cap': 'none'}}

def score_candidate(evidence: dict[str, Any]) -> dict[str, Any]:
    base = GROUP_SCORING.score_evidence(copy.deepcopy(evidence))
    gate = bool(base['G'])
    groups = {name: float(base['groups'][name]) for name in ('A', 'Q', 'M', 'R', 'D')}
    return _finish(role='candidate', groups=groups, gate=gate, scenarios=list(base.get('scenarios', [])), static_audit=dict(base.get('static_audit', {})), utility_metrics=dict(base.get('utility_metrics', {})), gate_reasons=list(base.get('gate_reasons', [])))

def score_reference(reference_receipt: dict[str, Any]) -> dict[str, Any]:
    if reference_receipt.get('schema') != 'simuverity.f90-xrobo02-score.v1':
        raise ValueError('reference must use the direct-audit current receipt')
    rows = reference_receipt.get('scenarios')
    audit = reference_receipt.get('static_audit')
    if not isinstance(rows, list) or len(rows) != 5 or (not all((isinstance(row, dict) and row.get('valid') is True for row in rows))):
        raise ValueError('reference direct-audit scenarios are incomplete')
    if not isinstance(audit, dict) or not all((bool(audit.get(field)) for field in CANONICAL_AUDIT_FIELDS)):
        raise ValueError('reference direct physical audit is incomplete')
    evidence = {'formal_task_id': 'F90-XROBO-02', 'group_weights': dict(WEIGHTS), 'facts': {'scenario_rows': copy.deepcopy(rows), 'static_audit': copy.deepcopy(audit), 'score_inputs_valid': True, 'gate_reasons': []}}
    groups, _source_total, reasons, utility = METRICS.score(evidence)
    return _finish(role='reference', groups={name: float(groups[name]) for name in ('A', 'Q', 'M', 'R', 'D')}, gate=True, scenarios=rows, static_audit=audit, utility_metrics=utility, gate_reasons=list(reasons))

def main() -> None:
    if len(sys.argv) != 4 or sys.argv[1] not in {'candidate', 'reference'}:
        raise SystemExit('usage: f90_xrobo02_scoring.py candidate|reference INPUT OUTPUT')
    role, input_name, output_name = sys.argv[1:]
    input_path = Path(input_name)
    data = json.loads(input_path.read_text(encoding='utf-8'))
    result = score_candidate(data) if role == 'candidate' else score_reference(data)
    output_path = Path(output_name)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
