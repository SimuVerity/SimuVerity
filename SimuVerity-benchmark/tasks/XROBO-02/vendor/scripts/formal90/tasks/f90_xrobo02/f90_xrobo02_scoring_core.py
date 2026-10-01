"""XROBO-02 score formula with the compile-state implementation-neutral graph."""
from __future__ import annotations
import copy
import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
METRIC_SCORER_PATH = TASK_DIR / 'f90_xrobo02_scoring_core_core.py'
POLICY_PATH = TASK_DIR / 'f90_xrobo02_structure_policy.py'
def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot load offline dependency: {path.name}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
METRICS = _load(METRIC_SCORER_PATH, 'f90_xrobo02')
POLICY = _load(POLICY_PATH, 'f90_xrobo02_policy')

def _compatible_mapping(container: dict[str, Any], name: str) -> dict[str, Any] | None:
    current = container.get(name)
    if isinstance(current, dict):
        return current
    compatible = [(key, value) for key, value in container.items() if key.startswith(name + '_') and isinstance(value, dict)]
    if not compatible:
        return None
    shortest = min(len(key) for key, _ in compatible)
    selected = [value for key, value in compatible if len(key) == shortest]
    return selected[0] if len(selected) == 1 else None

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    if evidence.get('formal_task_id') != 'F90-XROBO-02':
        raise ValueError('XROBO02 task mismatch')
    enriched = copy.deepcopy(evidence)
    facts = enriched.setdefault('facts', {})
    graph = _compatible_mapping(facts, 'implementation_neutral_port_graph')
    if not isinstance(graph, dict):
        raise ValueError('XROBO02 current evidence is missing its neutral port graph')
    decision = POLICY.evaluate_structure_graph(graph)
    static = facts.setdefault('static_audit', {})
    for field in ('joint_count_14', 'all_input_torque', 'all_computed_motion', 'all_position_sensed', 'all_velocity_sensed', 'all_torque_ports_connected', 'controller_present', 'no_prescribed_trajectory_blocks'):
        static[field] = int(decision[field])
    static['implementation_neutral_structure_decision'] = decision
    rows = facts.get('scenario_rows', [])
    rows_valid = bool(rows) and all((isinstance(row, dict) and row.get('valid') is True for row in rows))
    gate = bool(facts.get('platform_valid') and rows_valid and decision['hard_mechanism_gate_pass'])
    facts['score_inputs_valid'] = gate
    facts['hard_mechanism_gate'] = {'pass': bool(decision['hard_mechanism_gate_pass']), 'identity': 'f90-xrobo02-implementation-neutral-gate', 'failed_fields': decision['failure_reasons']}
    facts['gate_reasons'] = [] if gate else ['Implementation-neutral mechanism gate failed: ' + ', '.join(decision['failure_reasons'])]
    groups, value, reasons, utility = METRICS.score(enriched)
    normalized_groups = {name: METRICS.clip(groups.get(name, 0.0)) for name in ('A', 'Q', 'M', 'R', 'D')}
    receipt = {'schema': 'simuverity.formal90-offline-score.v1', 'formal_task_id': enriched['formal_task_id'], 'policy_id': 'simuverity-101-v1:f90-xrobo-02:scoring', 'offline_only': True, 'score_inputs_valid': gate, 'diagnostics_valid': bool(facts.get('diagnostics_valid', gate)), 'G': gate, 'groups': {'G': int(gate), **normalized_groups}, **normalized_groups, 'score': min(max(float(value), 0.0), 100.0), 'gate_reasons': [str(reason) for reason in reasons], 'failure_reasons': [str(reason) for reason in reasons], 'scenarios': facts.get('scenario_rows', []), 'static_audit': static, 'utility_metrics': utility, 'structure_policy': 'f90_xrobo02_structure_policy', 'implementation_neutral_structure_decision': decision}
    return receipt

def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit('usage: f90_xrobo02_scoring_core.py EVIDENCE OUTPUT')
    evidence_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    receipt = score_evidence(evidence)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=False), encoding='utf-8')
if __name__ == '__main__':
    main()
