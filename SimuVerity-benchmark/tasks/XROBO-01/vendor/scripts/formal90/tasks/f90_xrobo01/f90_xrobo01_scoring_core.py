"""XROBO-01 formula with the GROUP_SCORING public-contract structure gate."""
from __future__ import annotations
import copy
import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
METRIC_SCORER_PATH = TASK_DIR / 'f90_xrobo01_scoring_core_core.py'
STRUCTURE_POLICY = TASK_DIR / 'f90_xrobo01_structure_policy.py'
def _load(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot load offline dependency: {path.name}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
METRICS = _load(METRIC_SCORER_PATH, 'f90_xrobo01_scoring_core_core')
POLICY = _load(STRUCTURE_POLICY, 'f90_xrobo01_structure_policy')

def _scenario_rows_valid(facts: dict[str, Any]) -> bool:
    rows = facts.get('scenario_rows')
    return isinstance(rows, list) and bool(rows) and all((isinstance(row, dict) and row.get('valid') is True for row in rows))

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

def evidence_with_structure_decision(evidence: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    if evidence.get('formal_task_id') != 'F90-XROBO-01':
        raise ValueError('XROBO01 task mismatch')
    enriched = copy.deepcopy(evidence)
    facts = enriched.get('facts')
    if not isinstance(facts, dict):
        raise ValueError('XROBO01 facts object missing')
    audit = facts.get('static_audit')
    if not isinstance(audit, dict):
        raise ValueError('XROBO01 GROUP_SCORING static audit missing')
    graph = _compatible_mapping(audit, 'port_network')
    if not isinstance(graph, dict):
        raise ValueError('XROBO01 trusted port network missing')
    decision = POLICY.evaluate_structure_graph(graph)
    audit['pass'] = bool(decision['pass'])
    audit['mechanism_fraction'] = float(decision['mechanism_fraction'])
    audit['checks'] = copy.deepcopy(decision['checks'])
    audit['check_count'] = len(decision['checks'])
    audit['checks_passed'] = sum((row['pass'] for row in decision['checks']))
    audit['counts'] = copy.deepcopy(decision['counts'])
    audit['actuator_paths'] = copy.deepcopy(decision['actuator_path_witnesses'])
    audit['output_logs'] = copy.deepcopy(decision['output_path_witnesses'])
    audit['structure_decision'] = decision
    platform = facts.get('platform_valid') is True
    scenarios = _scenario_rows_valid(facts)
    facts['score_inputs_valid'] = platform and scenarios and decision['pass']
    reasons: list[str] = []
    if not platform:
        raw = facts.get('gate_reasons', [])
        if isinstance(raw, (str, int, float, bool)):
            raw = [raw]
        if isinstance(raw, list):
            reasons.extend((str(value) for value in raw if str(value)))
        if not reasons:
            reasons.append('Evaluator/platform failure')
    elif not scenarios:
        reasons.append('One or more scenarios invalid')
    reasons.extend((f'static:{reason}' for reason in decision['failure_reasons']))
    facts['gate_reasons'] = reasons
    facts['static_audit'] = audit
    enriched['facts'] = facts
    return (enriched, decision)

def score(evidence: dict[str, Any]) -> tuple[dict[str, float], float, dict[str, Any], list[str]]:
    enriched, decision = evidence_with_structure_decision(evidence)
    groups, value, diagnostics, reasons = METRICS.score(enriched)
    diagnostics = dict(diagnostics)
    diagnostics['structure_decision'] = decision
    return (groups, value, diagnostics, reasons)

def main() -> int:
    arguments = METRICS.parser('F90-XROBO-01').parse_args()
    evidence = METRICS.load_evidence(arguments.evidence, 'F90-XROBO-01')
    enriched, decision = evidence_with_structure_decision(evidence)
    groups, value, diagnostics, reasons = METRICS.score(enriched)
    receipt = METRICS.base_receipt(arguments.evidence, enriched, groups, value, policy_id='simuverity-101-v1:f90-xrobo-01:scoring', gate_reasons=reasons)
    receipt.update({'scenario_rows': enriched['facts'].get('scenario_rows', []), 'static_audit': enriched['facts'].get('static_audit', {}), 'pair_diagnostics': diagnostics, 'structure_decision': decision, 'scoring_configuration': 'current-groups'})
    METRICS.write_receipt(arguments.output, receipt)
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
