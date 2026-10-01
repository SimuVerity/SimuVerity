"""Pure-offline primitives for future SimuVerity D16 scorers.

This module never imports MATLAB bindings, launches a process, or reads a
candidate model. It consumes only JSON evidence produced by the public
extractor.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Sequence
CONTRACT_ID = 'simuverity_d16_p9_evidence_contract'
EVIDENCE_SCHEMA = 'simuverity.unified-d16-candidate-evidence.v1'
SCORER_RESULT_SCHEMA = 'simuverity.unified-offline-scorer-result.v1'
GROUP_KEYS = ('G', 'A', 'Q', 'M', 'C', 'R', 'D')

class EvidenceContractError(ValueError):
    """The public extractor supplied malformed evidence."""

def rows(value: Any) -> list[dict[str, Any]]:
    if value is None:
        return []
    if isinstance(value, Mapping):
        return [dict(value)]
    if isinstance(value, list):
        return [dict(x) for x in value if isinstance(x, Mapping)]
    return []

def finite(value: Any, default: float=math.nan) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return default
    number = float(value)
    return number if math.isfinite(number) else default

def boolean(value: Any, default: bool=False) -> bool:
    return value if isinstance(value, bool) else default

def text(value: Any, default: str='') -> str:
    return value if isinstance(value, str) else default

def vector(value: Any, length: int | None=None) -> list[float]:
    if not isinstance(value, list):
        result: list[float] = []
    else:
        result = [finite(x) for x in value]
    if length is not None and len(result) != length:
        return [math.nan] * length
    return result

def matrix(value: Any, shape: tuple[int, int]) -> list[list[float]]:
    if not isinstance(value, list) or len(value) != shape[0]:
        return [[math.nan] * shape[1] for _ in range(shape[0])]
    result = [vector(row, shape[1]) for row in value]
    if any((len(row) != shape[1] for row in result)):
        return [[math.nan] * shape[1] for _ in range(shape[0])]
    return result

def clip01(value: Any) -> float:
    number = finite(value, 0.0)
    return min(max(number, 0.0), 1.0)

def clip100(value: Any) -> float:
    number = finite(value, 0.0)
    return min(max(number, 0.0), 100.0)

def anchor(value: Any, x: Sequence[float], y: Sequence[float]) -> float:
    number = finite(value)
    if not math.isfinite(number) or len(x) != len(y) or len(x) < 2:
        return 0.0
    if any((x[i + 1] <= x[i] for i in range(len(x) - 1))):
        raise ValueError('anchor x values must be strictly increasing')
    number = min(max(number, float(x[0])), float(x[-1]))
    for index in range(len(x) - 1):
        lo, hi = (float(x[index]), float(x[index + 1]))
        if number <= hi:
            fraction = (number - lo) / (hi - lo)
            return clip01(float(y[index]) + fraction * (float(y[index + 1]) - float(y[index])))
    return clip01(y[-1])

def worst_anchor(values: Any, x: Sequence[float], y: Sequence[float]) -> float:
    if isinstance(values, (int, float)) and (not isinstance(values, bool)):
        data = [finite(values)]
    elif isinstance(values, list):
        data = [finite(item) for item in values]
    else:
        return 0.0
    if not data or any((not math.isfinite(item) for item in data)):
        return 0.0
    return min((anchor(item, x, y) for item in data))

def weighted(values: Sequence[Any], weights: Sequence[float]) -> float:
    if len(values) != len(weights) or not values:
        return 0.0
    clipped = [clip01(value) for value in values]
    total_weight = sum((float(weight) for weight in weights))
    if total_weight <= 0:
        return 0.0
    return clip01(sum((clipped[index] * float(weights[index]) for index in range(len(clipped)))) / total_weight)

def bottleneck(values: Sequence[Any], weights: Sequence[float]) -> float:
    if len(values) != len(weights) or not values:
        return 0.0
    clipped = [clip01(value) for value in values]
    return clip01(math.sqrt(weighted(clipped, weights) * min(clipped)))

def worst(values: Sequence[Any]) -> float:
    return min((clip01(value) for value in values), default=0.0)

def geometric(groups: Mapping[str, float], exponents: Mapping[str, float]) -> float:
    result = 100.0
    for key, exponent in exponents.items():
        result *= clip01(groups.get(key, 0.0)) ** float(exponent)
    return clip100(result)

def suite(evidence: Mapping[str, Any]) -> dict[str, Any]:
    value = evidence.get('suite')
    return dict(value) if isinstance(value, Mapping) else {}

def nominal(suite_value: Mapping[str, Any]) -> dict[str, Any]:
    value = suite_value.get('nominal')
    return dict(value) if isinstance(value, Mapping) else {}

def scenario_map(suite_value: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    duplicates: set[str] = set()
    for row in rows(suite_value.get('scenario_results')):
        scenario_id = text(row.get('scenario'))
        if not scenario_id:
            continue
        if scenario_id in result:
            duplicates.add(scenario_id)
        result[scenario_id] = row
    for scenario_id in duplicates:
        result[scenario_id] = {}
    return result

def required_scenario_ids(spec: Mapping[str, Any]) -> list[str]:
    return [text(row.get('id')) for row in rows(spec.get('scenarios')) if boolean(row.get('required'), True) and text(row.get('id'))]

def task_measurements(row: Mapping[str, Any]) -> dict[str, Any]:
    value = row.get('task_measurements')
    return dict(value) if isinstance(value, Mapping) else {}

def _unique_by_id(items: Any, item_id: str) -> dict[str, Any] | None:
    hits = [row for row in rows(items) if text(row.get('id')) == item_id]
    return hits[0] if len(hits) == 1 else None

def band_row(row: Mapping[str, Any], band_id: str) -> dict[str, Any] | None:
    return _unique_by_id(row.get('band_measurements'), band_id)

def band_value(row: Mapping[str, Any], band_id: str) -> tuple[float, bool]:
    item = band_row(row, band_id)
    if item is None:
        return (math.nan, False)
    value = finite(item.get('value'))
    return (value, boolean(item.get('valid')) and math.isfinite(value))

def band_utility(row: Mapping[str, Any], band_id: str) -> tuple[float, bool]:
    """Recompute the band curve from its raw value and embedded contract."""
    item = band_row(row, band_id)
    if item is None or not boolean(item.get('valid')):
        return (0.0, False)
    contract = item.get('band_contract')
    if not isinstance(contract, Mapping):
        return (0.0, False)
    value = finite(item.get('value'))
    target = finite(contract.get('target'))
    tol_pass = finite(contract.get('tol_pass'))
    tol_zero = finite(contract.get('tol_zero'))
    curve_p = finite(contract.get('curve_p'), 1.0)
    if not all((math.isfinite(x) for x in (value, target, tol_pass, tol_zero, curve_p))) or tol_pass <= 0 or tol_zero <= tol_pass or (curve_p <= 0):
        return (0.0, False)
    sided = text(contract.get('sided'), 'two').lower()
    if sided == 'lower':
        error = max(0.0, value - target)
    elif sided == 'upper':
        error = max(0.0, target - value)
    else:
        error = abs(value - target)
    if error <= 0:
        quality = 1.0
    elif error <= tol_pass:
        quality = 0.4 + 0.6 * (1.0 - error / tol_pass) ** curve_p
    elif error < tol_zero:
        quality = 0.4 * (tol_zero - error) / (tol_zero - tol_pass)
    else:
        quality = 0.0
    return (clip01(quality), True)

def band_utilities(row: Mapping[str, Any], band_ids: Sequence[str]) -> tuple[list[float], list[bool]]:
    pairs = [band_utility(row, band_id) for band_id in band_ids]
    return ([pair[0] for pair in pairs], [pair[1] for pair in pairs])

def raw_bands_valid(row: Mapping[str, Any], band_ids: Sequence[str]) -> bool:
    return all((band_value(row, band_id)[1] for band_id in band_ids))

def witness_q(row: Mapping[str, Any], require_nonempty: bool=True) -> tuple[float, bool]:
    reports = rows(row.get('witness_reports'))
    if require_nonempty and (not reports):
        return (0.0, False)
    valid = bool(reports) or not require_nonempty
    for report in reports:
        valid = valid and boolean(report.get('evaluated'), True) and boolean(report.get('valid'), True) and boolean(report.get('ok')) and math.isfinite(finite(report.get('observed')))
    return (float(valid), valid)

def witness_row(row: Mapping[str, Any], report_id: str) -> dict[str, Any]:
    report = _unique_by_id(row.get('witness_reports'), report_id)
    if report is None:
        return {'id': report_id, 'found': False, 'observed': math.nan, 'nominal_value': math.nan, 'scenario_value': math.nan}
    values = {'id': report_id, 'found': False, 'observed': finite(report.get('observed')), 'nominal_value': finite(report.get('nominal_value')), 'scenario_value': finite(report.get('scenario_value'))}
    values['found'] = all((math.isfinite(values[key]) for key in ('observed', 'nominal_value', 'scenario_value')))
    return values

def oracle_row(suite_value: Mapping[str, Any], report_id: str) -> dict[str, Any] | None:
    containers: list[Any] = [nominal(suite_value).get('task_oracle_reports'), suite_value.get('task_oracle_reports')]
    hits: list[dict[str, Any]] = []
    for container in containers:
        hits.extend((row for row in rows(container) if text(row.get('id')) == report_id))
    return hits[0] if len(hits) == 1 else None

def oracle_pass(report: Mapping[str, Any] | None) -> bool:
    return bool(report) and all((boolean(report.get('evaluated')), boolean(report.get('valid')), boolean(report.get('ok'))))

def mandatory_qualification_reasons(suite_value: Mapping[str, Any], include_scenarios: bool=False) -> list[str]:
    containers: list[Any] = [nominal(suite_value).get('task_oracle_reports'), suite_value.get('task_oracle_reports')]
    if include_scenarios:
        containers.extend((row.get('task_oracle_reports') for row in rows(suite_value.get('scenario_results'))))
    reasons: list[str] = []
    for container in containers:
        for report in rows(container):
            if not boolean(report.get('mandatory'), True):
                continue
            semantic = text(report.get('semantic_kind')).lower()
            layer = text(report.get('layer')).lower()
            if semantic != 'structure' and layer != 'qualification':
                continue
            if not oracle_pass(report):
                reasons.append('MANDATORY_SEMANTIC_CHECK_FAIL:' + text(report.get('id'), 'missing'))
    return reasons

def semantic_gate(evidence: Mapping[str, Any], expected_scenarios: Sequence[str], *, exact_scenario_contract: bool=True, include_scenario_oracles: bool=False, required_oracle_id: str | None=None) -> tuple[bool, list[str]]:
    suite_value = suite(evidence)
    spec = evidence.get('task_spec')
    spec = dict(spec) if isinstance(spec, Mapping) else {}
    nom = nominal(suite_value)
    reasons: list[str] = []
    if text(nom.get('stage')) != 'simulated':
        reasons.append('NOMINAL_NOT_SIMULATED')
    if not boolean(nom.get('qualification_ok')):
        reasons.append('NOMINAL_QUALIFICATION_FAIL')
    declared = required_scenario_ids(spec)
    expected = list(expected_scenarios)
    contract_ok = set(expected).issubset(set(declared))
    if exact_scenario_contract:
        contract_ok = contract_ok and len(declared) == len(expected)
    if not contract_ok:
        reasons.append(text(evidence.get('benchmark_task_id'), 'D16') + '_REQUIRED_SCENARIO_CONTRACT_MISMATCH')
    scenarios = scenario_map(suite_value)
    for scenario_id in expected:
        row = scenarios.get(scenario_id, {})
        if not row or text(row.get('stage')) != 'simulated' or (not boolean(row.get('qualification_ok'))):
            reasons.append('SCENARIO_QUALIFICATION_FAIL:' + scenario_id)
    reasons.extend(mandatory_qualification_reasons(suite_value, include_scenario_oracles))
    if required_oracle_id and (not oracle_pass(oracle_row(suite_value, required_oracle_id))):
        reasons.append('REQUIRED_TASK_ORACLE_FAIL:' + required_oracle_id)
    return (not reasons, reasons)

def group_scores(groups: Mapping[str, Any], applicable: Iterable[str], reasons: Sequence[str]) -> dict[str, dict[str, Any]]:
    applicable_set = set(applicable)
    result: dict[str, dict[str, Any]] = {}
    for key in GROUP_KEYS:
        is_applicable = key in applicable_set
        value = clip01(groups.get(key, 0.0)) if is_applicable else None
        group_reasons = list(reasons) if key == 'G' and value == 0 else []
        result[key] = {'applicable': is_applicable, 'score': value, 'failure_reasons': group_reasons}
    return result

def make_result(*, task_id: str, policy_id: str, gate: bool, groups: Mapping[str, Any], applicable: Iterable[str], total_score: Any, metrics: Sequence[Mapping[str, Any]], scenarios: Sequence[Mapping[str, Any]], failure_reasons: Sequence[str], score_inputs_valid: bool, policy_status: str='CURRENT') -> dict[str, Any]:
    all_groups = dict(groups)
    all_groups['G'] = 1.0 if gate else 0.0
    reasons = list(dict.fromkeys((str(reason) for reason in failure_reasons)))
    if not score_inputs_valid and 'SCORE_INPUTS_INVALID' not in reasons:
        reasons.append('SCORE_INPUTS_INVALID')
    score = clip100(total_score) if gate and score_inputs_valid else 0.0
    return {'schema': SCORER_RESULT_SCHEMA, 'contract_id': CONTRACT_ID, 'benchmark_task_id': task_id, 'policy_id': policy_id, 'policy_status': policy_status, 'status': 'SCORED', 'failure_attribution': 'candidate' if reasons else 'none', 'protocol_zero_applied': bool(score == 0.0 and reasons), 'total_score': score, 'group_scores': group_scores(all_groups, set(applicable) | {'G'}, reasons), 'metrics': [dict(row) for row in metrics], 'scenarios': [dict(row) for row in scenarios], 'failure_reasons': reasons, 'score_inputs_valid': bool(score_inputs_valid), 'pure_offline': True, 'matlab_started': False, 'candidate_resimulated': False}

def validate_evidence(evidence: Mapping[str, Any], expected_task_id: str) -> None:
    checks = (evidence.get('schema') == EVIDENCE_SCHEMA, evidence.get('contract_id') == CONTRACT_ID, evidence.get('collection_id') == 'd16', evidence.get('benchmark_task_id') == expected_task_id, evidence.get('extraction_only') is True, evidence.get('direct_scorer_called') is False, evidence.get('offline_scoring_started') is False)
    if not all(checks):
        raise EvidenceContractError('D16 evidence identity or extraction-only phase is invalid')
    spec = evidence.get('task_spec')
    if not isinstance(spec, Mapping) or spec.get('id') != expected_task_id:
        raise EvidenceContractError('embedded D16 task spec identity mismatch')
    suite_value = evidence.get('suite')
    if not isinstance(suite_value, Mapping):
        raise EvidenceContractError('D16 suite evidence is missing')
    if suite_value.get('direct_scorer_called') is not False:
        raise EvidenceContractError('MATLAB direct scorer contamination')
    if suite_value.get('score_total_present') is not False:
        raise EvidenceContractError('MATLAB total score contamination')


def json_safe(value: Any) -> Any:
    """Convert non-finite diagnostics to JSON null without changing scores."""
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, Mapping):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    return value

def run_cli(score_function: Callable[[Mapping[str, Any]], dict[str, Any]], expected_task_id: str, scorer_path: str) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--output', required=True)
    arguments = parser.parse_args()
    evidence_path = Path(arguments.evidence).resolve(strict=True)
    output_path = Path(arguments.output).resolve()
    if output_path.exists():
        raise EvidenceContractError('offline scorer output must be fresh')
    with evidence_path.open('r', encoding='utf-8') as handle:
        evidence = json.load(handle)
    validate_evidence(evidence, expected_task_id)
    result = score_function(evidence)
    result = json_safe(result)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(output_path, flags, 384)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8', newline='\n') as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2, allow_nan=False)
            handle.write('\n')
    except Exception:
        try:
            output_path.unlink()
        except OSError:
            pass
        raise
