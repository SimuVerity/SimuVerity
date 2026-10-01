"""Pure-offline XBATT-07 scorer for the sealed-candidate compatibility route."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XBATT-07'
SCENARIO_IDS = ('nominal_standby', 'drive_precharge_ready', 'drive_precharge_incomplete', 'charge_precharge_ready', 'voltage_temperature_derating', 'overvoltage_overtemperature_fault')
STATE = ['log_bms_state', 'log_charger_state', 'log_inverter_state']
COMMAND = ['log_cmd_PosCntctChgrCmd', 'log_cmd_PreChrgRelayChgrCmd', 'log_cmd_NegCntctChgrCmd', 'log_cmd_PosCntctInvtrCmd', 'log_cmd_PreChrgRelayInvtrCmd', 'log_cmd_NegCntctInvtrCmd']
LIMIT = ['log_limit_DischargeCurrentLimit', 'log_limit_ChargeCurrentLimit']
EXTREMA = ['log_extrema_MinCellVolt', 'log_extrema_MaxCellVolt', 'log_extrema_MinCellTemp', 'log_extrema_MaxCellTemp']
FAULT_HEAD = ['log_critical_fault', 'log_limp_mode']
FAULT = ['log_fault_PackOverCurrFlt', 'log_fault_CellHighTempFlt', 'log_fault_CellLowTempFlt', 'log_fault_VoltSensorFlt', 'log_fault_CellOverVoltFlt', 'log_fault_CellUnderVoltFlt', 'log_fault_ChrgCntctFlt', 'log_fault_InvtrCntctFlt']
ALL = STATE + COMMAND + LIMIT + EXTREMA + FAULT_HEAD + FAULT
DISCRETE = set(STATE + COMMAND + FAULT_HEAD + FAULT)
EXPECTED_AVAILABILITY = {'log_bms_state': True, 'log_charger_state': False, 'log_inverter_state': False, **{name: True for name in COMMAND + LIMIT + EXTREMA}, 'log_critical_fault': True, 'log_limp_mode': False, 'log_fault_PackOverCurrFlt': True, 'log_fault_CellHighTempFlt': True, 'log_fault_CellLowTempFlt': True, 'log_fault_VoltSensorFlt': False, 'log_fault_CellOverVoltFlt': True, 'log_fault_CellUnderVoltFlt': True, 'log_fault_ChrgCntctFlt': False, 'log_fault_InvtrCntctFlt': False}
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.25, 'C': 0.2, 'R': 0.1, 'D': 0.1}

def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding='utf-8-sig'))

def finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def available(item: dict[str, Any], name: str) -> bool:
    log = item.get('logs', {}).get(name, {})
    return log.get('available', True) is True

def values(item: dict[str, Any], name: str) -> list[float] | None:
    if not available(item, name):
        return None
    try:
        raw = item['logs'][name]['data']
        output = [float(value) for value in raw]
    except (KeyError, TypeError, ValueError):
        return None
    return output if output and all((math.isfinite(value) for value in output)) else None

def utility(actual: list[float] | None, expected: list[float] | None, discrete: bool) -> float:
    if actual is None or expected is None or len(actual) != len(expected) or (not actual):
        return 0.0
    if discrete:
        return 100.0 * sum((abs(a - b) < 0.5 for a, b in zip(actual, expected))) / len(expected)
    scale = max(max(expected) - min(expected), max((abs(value) for value in expected)), 1.0)
    rmse = math.sqrt(sum(((a - b) ** 2 for a, b in zip(actual, expected))) / len(expected))
    return max(0.0, 100.0 * (1.0 - rmse / (0.08 * scale)))

def evidence_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(item.get('id')): item for item in evidence.get('scenarios', []) if isinstance(item, dict)}

def compare_group(actual: dict[str, Any], reference: dict[str, Any], names: list[str]) -> tuple[float, list[float], dict[str, list[float]]]:
    actual_map, reference_map = (evidence_map(actual), evidence_map(reference))
    per_scenario: list[float] = []
    per_channel: dict[str, list[float]] = {name: [] for name in names}
    for scenario_id in SCENARIO_IDS:
        candidate = actual_map.get(scenario_id, {})
        golden = reference_map.get(scenario_id, {})
        scores: list[float] = []
        for name in names:
            value = utility(values(candidate, name), values(golden, name), name in DISCRETE)
            scores.append(value)
            per_channel[name].append(value)
        per_scenario.append(sum(scores) / len(scores) if scores else 0.0)
    return (sum(per_scenario) / len(per_scenario) if per_scenario else 0.0, per_scenario, per_channel)

def separation(actual: dict[str, Any], reference: dict[str, Any], names: list[str], pairs: list[tuple[str, str]] | None=None) -> float:
    actual_map, reference_map = (evidence_map(actual), evidence_map(reference))
    ids = list(SCENARIO_IDS)
    pairs = pairs or [(ids[i], ids[j]) for i in range(len(ids)) for j in range(i + 1, len(ids))]
    scores: list[float] = []
    for left, right in pairs:
        for name in names:
            left_ref, right_ref = (values(reference_map[left], name), values(reference_map[right], name))
            if left_ref is None or right_ref is None or len(left_ref) != len(right_ref):
                continue
            ref_delta = math.sqrt(sum(((x - y) ** 2 for x, y in zip(left_ref, right_ref))) / len(left_ref))
            if ref_delta <= 1e-08:
                continue
            left_actual, right_actual = (values(actual_map[left], name), values(actual_map[right], name))
            if left_actual is None or right_actual is None or len(left_actual) != len(right_actual):
                scores.append(0.0)
                continue
            actual_delta = math.sqrt(sum(((x - y) ** 2 for x, y in zip(left_actual, right_actual))) / len(left_actual))
            scores.append(100.0 * min(1.0, actual_delta / ref_delta))
    return sum(scores) / len(scores) if scores else 100.0

def validate_candidate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    for key in ('load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'runtime_model_unchanged', 'evidence_complete'):
        if evidence.get(key) is not True:
            failures.append(key)
    profile = evidence.get('compatibility_profile', {})
    if evidence.get('static_audit', {}).get('core_path_qualified') is not True:
        failures.append('connected dynamic anti-cheat core is not qualified')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return (False, failures + ['scenarios is not an array'])
    if [item.get('id') for item in scenarios if isinstance(item, dict)] != list(SCENARIO_IDS):
        failures.append('official scenario identifiers/order mismatch')
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            failures.append('scenario entry is not an object')
            continue
        scenario_id = str(scenario.get('id', '<missing>'))
        if scenario.get('valid') is not True or scenario.get('simulate_pass') is not True:
            failures.append(f'{scenario_id}: simulation/evidence validity flag failed')
        if scenario.get('output_contract', {}).get('all_required_pass') is not True:
            failures.append(f'{scenario_id}: raw output-container contract failed')
        logs = scenario.get('logs')
        if not isinstance(logs, dict) or set(logs) != set(ALL):
            failures.append(f'{scenario_id}: canonical log set mismatch')
            continue
        for name in ALL:
            log = logs[name]
            if log.get('available') is not EXPECTED_AVAILABILITY[name]:
                failures.append(f'{scenario_id}/{name}: availability mask mismatch')
            if not isinstance(log.get('source'), str) or not log['source']:
                failures.append(f'{scenario_id}/{name}: source identity missing')
            time, data = (log.get('time'), log.get('data'))
            if not isinstance(time, list) or not isinstance(data, list) or len(time) != len(data) or (len(time) < 200):
                failures.append(f'{scenario_id}/{name}: time/data length mismatch')
                continue
            if not all((finite(value) for value in time + data)):
                failures.append(f'{scenario_id}/{name}: nonfinite time/data')
                continue
            time_f = [float(value) for value in time]
            if abs(time_f[0]) > 1e-09 or time_f[-1] < 24.9 or any((right <= left for left, right in zip(time_f, time_f[1:]))):
                failures.append(f'{scenario_id}/{name}: incomplete or nonmonotonic time')
    return (not failures, failures)

def quality(evidence: dict[str, Any]) -> float:
    checks = [scenario.get('valid') is True and scenario.get('output_contract', {}).get('all_required_pass') is True for scenario in evidence.get('scenarios', []) if isinstance(scenario, dict)]
    return 100.0 * sum(checks) / len(SCENARIO_IDS) if len(checks) == len(SCENARIO_IDS) else 0.0

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0.0 for name in WEIGHTS)):
        return 0.0
    return 100.0 * math.exp(sum((WEIGHTS[name] * math.log(groups[name] / 100.0) for name in WEIGHTS)))

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    gate, failures = validate_candidate(candidate)
    output: dict[str, Any] = {'schema': 'simuverity.f90-xbatt07-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1.0 if gate else 0.0, 'weights': WEIGHTS, 'validation_failures': failures}
    if not gate:
        output.update({'groups': {name: 0.0 for name in WEIGHTS}, 'raw_total': 0.0, 'total': 0.0, 'scenario_similarity': [], 'metric_detail': {}, 'failure_reasons': failures})
        return output
    a, a_per, a_channels = compare_group(candidate, reference, STATE + COMMAND + LIMIT)
    m, m_per, m_channels = compare_group(candidate, reference, EXTREMA + LIMIT + FAULT_HEAD + FAULT)
    c, c_per, c_channels = compare_group(candidate, reference, STATE + COMMAND + FAULT_HEAD + FAULT)
    d, d_per, d_channels = compare_group(candidate, reference, STATE + COMMAND)
    _, robust, all_channels = compare_group(candidate, reference, ALL)
    state_sep = separation(candidate, reference, STATE)
    command_sep = separation(candidate, reference, COMMAND)
    limit_sep = separation(candidate, reference, LIMIT)
    extrema_sep = separation(candidate, reference, EXTREMA)
    fault_sep = separation(candidate, reference, FAULT_HEAD + FAULT)
    precharge_pair = separation(candidate, reference, STATE + COMMAND + FAULT_HEAD + FAULT, [('drive_precharge_ready', 'drive_precharge_incomplete')])
    groups = {'A': min(a, state_sep, command_sep, limit_sep), 'Q': quality(candidate), 'M': min(m, limit_sep, extrema_sep, fault_sep), 'C': min(c, state_sep, command_sep, fault_sep, precharge_pair), 'R': min(robust) if robust else 0.0, 'D': min(d, state_sep, command_sep, precharge_pair)}
    raw_total = geometric(groups)
    unavailable = sorted((name for name, present in EXPECTED_AVAILABILITY.items() if not present))
    output.update({'groups': {name: round(value, 6) for name, value in groups.items()}, 'raw_total': round(raw_total, 6), 'total': round(raw_total, 6), 'normalized_from_admission_threshold': False, 'scenario_similarity': [round(value, 6) for value in robust], 'metric_detail': {'A_per_scenario': a_per, 'M_per_scenario': m_per, 'C_per_scenario': c_per, 'D_per_scenario': d_per, 'state_separation': state_sep, 'command_separation': command_sep, 'limit_separation': limit_sep, 'extrema_separation': extrema_sep, 'fault_separation': fault_sep, 'precharge_pair_separation': precharge_pair, 'per_channel': {'A': a_channels, 'M': m_channels, 'C': c_channels, 'D': d_channels, 'all': all_channels}, 'unavailable_components_scored_zero': unavailable}, 'failure_reasons': []})
    return output

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = score(read_json(args.reference), read_json(args.candidate))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
