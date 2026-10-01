"""Pure-offline scorer for F90-XBATT-08.

The scorer reads complete JSON evidence only.  It never imports MATLAB, opens a
model, or starts a simulation.  Reference normalization is fixed by the
supplied complete reference evidence.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XBATT-08'
SCENARIO_IDS = ('baseline_all', 'selected_default', 'light_ultracap_all', 'heavy_ultracap_all', 'light_battery_selected', 'heavy_battery_selected')
LOG_SPEC = {'vehicle_speed': (['vehicle_speed_kph'], ['km/hr']), 'traction': (['motor_torque_Nm', 'motor_speed_rad_s', 'motor_mechanical_power_W'], ['N*m', 'rad/s', 'W']), 'storage_voltage': (['battery_voltage_V', 'ultracapacitor_voltage_V', 'dc_bus_voltage_V'], ['V', 'V', 'V']), 'storage_current': (['battery_current_A', 'ultracapacitor_current_A'], ['A', 'A']), 'storage_power': (['battery_power_W', 'ultracapacitor_power_W'], ['W', 'W'])}
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.25, 'C': 0.2, 'R': 0.1, 'D': 0.1}
PAIR_SPEC = {'strategy': ('baseline_all', 'selected_default', (('traction', 0), ('traction', 2), ('storage_current', 0), ('storage_current', 1), ('storage_power', 0), ('storage_power', 1))), 'ultracapacitor_mass': ('light_ultracap_all', 'heavy_ultracap_all', (('vehicle_speed', 0), ('traction', 0), ('traction', 2), ('storage_current', 1), ('storage_power', 1))), 'battery_mass': ('light_battery_selected', 'heavy_battery_selected', (('vehicle_speed', 0), ('traction', 0), ('traction', 2), ('storage_current', 0), ('storage_power', 0)))}

def load_json(path: Path) -> dict[str, Any]:
    with path.open('r', encoding='utf-8') as handle:
        return json.load(handle)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n'
    path.write_text(text, encoding='utf-8')

def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def rows(data: Any, width: int) -> list[list[float]]:
    if not isinstance(data, list):
        raise ValueError('data is not an array')
    if width == 1 and (not data or finite_number(data[0])):
        return [[float(value)] for value in data]
    output: list[list[float]] = []
    for row in data:
        if not isinstance(row, list) or len(row) != width or (not all((finite_number(value) for value in row))):
            raise ValueError('data row width or finiteness mismatch')
        output.append([float(value) for value in row])
    return output

def validate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return (False, failures + ['scenarios is not an array'])
    ids = [scenario.get('id') for scenario in scenarios if isinstance(scenario, dict)]
    if sorted(ids) != sorted(SCENARIO_IDS) or len(ids) != len(SCENARIO_IDS):
        failures.append('scenario identifiers are incomplete, duplicated, or unexpected')
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            failures.append('scenario entry is not an object')
            continue
        sid = str(scenario.get('id', '<missing>'))
        if scenario.get('valid') is not True:
            failures.append(f'{sid}: evaluator validity flag is not true')
        logs = scenario.get('logs')
        if not isinstance(logs, dict) or set(logs) != set(LOG_SPEC):
            failures.append(f'{sid}: required log set mismatch')
            continue
        end_times: list[float] = []
        for log_name, (channels, units) in LOG_SPEC.items():
            log = logs.get(log_name)
            if not isinstance(log, dict):
                failures.append(f'{sid}/{log_name}: log is not an object')
                continue
            if log.get('channels') != channels:
                failures.append(f'{sid}/{log_name}: channel order mismatch')
            if log.get('units') != units:
                failures.append(f'{sid}/{log_name}: unit order mismatch')
            time = log.get('time')
            if not isinstance(time, list) or len(time) < 100 or (not all((finite_number(value) for value in time))):
                failures.append(f'{sid}/{log_name}: time vector is short or nonfinite')
                continue
            time_values = [float(value) for value in time]
            if abs(time_values[0]) > 1e-09 or not 80.0 <= time_values[-1] <= 100.0:
                failures.append(f'{sid}/{log_name}: time coverage is outside 0 to 80--100 s')
            if any((right <= left for left, right in zip(time_values, time_values[1:]))):
                failures.append(f'{sid}/{log_name}: time is not strictly increasing')
            try:
                matrix = rows(log.get('data'), len(channels))
            except ValueError as exc:
                failures.append(f'{sid}/{log_name}: {exc}')
                continue
            if len(matrix) != len(time_values):
                failures.append(f'{sid}/{log_name}: data length differs from time length')
            end_times.append(time_values[-1])
        if end_times and max(end_times) - min(end_times) > 1e-06:
            failures.append(f'{sid}: logs do not share one completion time')
    return (not failures, failures)

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {scenario['id']: scenario for scenario in evidence['scenarios']}

def channel(log: dict[str, Any], index: int) -> tuple[list[float], list[float]]:
    width = len(log['channels'])
    matrix = rows(log['data'], width)
    return ([float(value) for value in log['time']], [row[index] for row in matrix])

def resample(log: dict[str, Any], index: int, count: int=201) -> list[float]:
    time, values = channel(log, index)
    duration = time[-1]
    target = [duration * position / (count - 1) for position in range(count)]
    output: list[float] = []
    cursor = 0
    for sample_time in target:
        while cursor + 1 < len(time) and time[cursor + 1] < sample_time:
            cursor += 1
        if cursor + 1 >= len(time):
            output.append(values[-1])
            continue
        left_time, right_time = (time[cursor], time[cursor + 1])
        fraction = (sample_time - left_time) / (right_time - left_time)
        output.append(values[cursor] + fraction * (values[cursor + 1] - values[cursor]))
    return output

def rms(values: list[float]) -> float:
    return math.sqrt(sum((value * value for value in values)) / max(len(values), 1))

def reference_scale(values: list[float]) -> float:
    return max(rms(values), max((abs(value) for value in values)) * 0.1, 1e-09)

def similarity(reference: list[float], candidate: list[float], sharpness: float=4.0) -> float:
    error = rms([actual - expected for expected, actual in zip(reference, candidate)])
    return 100.0 * math.exp(-sharpness * error / reference_scale(reference))

def derivative(values: list[float]) -> list[float]:
    return [right - left for left, right in zip(values, values[1:])]

def ratio_utility(reference_value: float, candidate_value: float) -> float:
    if reference_value <= 1e-12 or candidate_value <= 1e-12:
        return 100.0 if reference_value <= 1e-12 and candidate_value <= 1e-12 else 0.0
    ratio = candidate_value / reference_value
    return 100.0 * min(ratio, 1.0 / ratio)

def both_signs(values: list[float]) -> bool:
    tolerance = max(max((abs(value) for value in values)) * 1e-05, 1e-06)
    return any((value > tolerance for value in values)) and any((value < -tolerance for value in values))

def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def causal_pair_score(reference: dict[str, dict[str, Any]], candidate: dict[str, dict[str, Any]], left_id: str, right_id: str, signals: tuple[tuple[str, int], ...]) -> tuple[float, dict[str, float]]:
    reference_differences: list[float] = []
    candidate_differences: list[float] = []
    for log_name, index in signals:
        ref_left = resample(reference[left_id]['logs'][log_name], index)
        ref_right = resample(reference[right_id]['logs'][log_name], index)
        cand_left = resample(candidate[left_id]['logs'][log_name], index)
        cand_right = resample(candidate[right_id]['logs'][log_name], index)
        scale = max(reference_scale(ref_left), reference_scale(ref_right), 1e-09)
        reference_differences.extend([(right - left) / scale for left, right in zip(ref_left, ref_right)])
        candidate_differences.extend([(right - left) / scale for left, right in zip(cand_left, cand_right)])
    reference_separation = rms(reference_differences)
    candidate_separation = rms(candidate_differences)
    magnitude = ratio_utility(reference_separation, candidate_separation)
    shape = similarity(reference_differences, candidate_differences, sharpness=2.0)
    score = math.sqrt(max(magnitude, 0.0) * max(shape, 0.0))
    return (score, {'reference_normalized_separation': reference_separation, 'candidate_normalized_separation': candidate_separation, 'magnitude_utility': magnitude, 'score': score})

def score(reference_evidence: dict[str, Any], candidate_evidence: dict[str, Any]) -> dict[str, Any]:
    gate_ok, gate_failures = validate(candidate_evidence)
    result: dict[str, Any] = {'schema': 'simuverity.f90-xbatt08-offline-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'weights': WEIGHTS, 'gate': {'G': 1 if gate_ok else 0, 'passed': gate_ok, 'failures': gate_failures}}
    if not gate_ok:
        result.update({'group_scores': {group: 0.0 for group in WEIGHTS}, 'scenario_scores': [], 'causal_pairs': {}, 'raw_score': 0.0, 'score_eligible': False, 'failure_reasons': gate_failures})
        return result
    reference = scenario_map(reference_evidence)
    candidate = scenario_map(candidate_evidence)
    channel_scores: dict[str, dict[str, float]] = {}
    scenario_scores: list[dict[str, Any]] = []
    for sid in SCENARIO_IDS:
        scores: dict[str, float] = {}
        for log_name, (channels, _) in LOG_SPEC.items():
            for index, channel_name in enumerate(channels):
                key = f'{log_name}.{channel_name}'
                scores[key] = similarity(resample(reference[sid]['logs'][log_name], index), resample(candidate[sid]['logs'][log_name], index))
        channel_scores[sid] = scores
        scenario_scores.append({'id': sid, 'score': mean(list(scores.values())), 'channels': scores})
    accuracy_keys = ('vehicle_speed.vehicle_speed_kph', 'traction.motor_torque_Nm', 'traction.motor_speed_rad_s', 'traction.motor_mechanical_power_W', 'storage_voltage.battery_voltage_V', 'storage_voltage.ultracapacitor_voltage_V', 'storage_voltage.dc_bus_voltage_V')
    accuracy = mean([channel_scores[sid][key] for sid in SCENARIO_IDS for key in accuracy_keys])
    storage_keys = ('storage_current.battery_current_A', 'storage_current.ultracapacitor_current_A', 'storage_power.battery_power_W', 'storage_power.ultracapacitor_power_W')
    storage_similarity = mean([channel_scores[sid][key] for sid in SCENARIO_IDS for key in storage_keys])
    activity_scores: list[float] = []
    bidirectional_scores: list[float] = []
    for sid in SCENARIO_IDS:
        for log_name in ('storage_current', 'storage_power'):
            for index in (0, 1):
                ref_values = resample(reference[sid]['logs'][log_name], index)
                cand_values = resample(candidate[sid]['logs'][log_name], index)
                activity_scores.append(ratio_utility(max(map(abs, ref_values)), max(map(abs, cand_values))))
                bidirectional_scores.append(100.0 if both_signs(cand_values) else 0.0)
    activity = mean(activity_scores)
    bidirectional = mean(bidirectional_scores)
    mechanism = 0.75 * storage_similarity + 0.15 * activity + 0.1 * bidirectional
    causal_pairs: dict[str, dict[str, float]] = {}
    for name, (left_id, right_id, signals) in PAIR_SPEC.items():
        _, details = causal_pair_score(reference, candidate, left_id, right_id, signals)
        causal_pairs[name] = details
    pair_scores = [details['score'] for details in causal_pairs.values()]
    causal = 0.7 * min(pair_scores) + 0.3 * mean(pair_scores)
    robustness = min((item['score'] for item in scenario_scores))
    dynamic_scores: list[float] = []
    for sid in SCENARIO_IDS:
        for log_name, index in (('traction', 0), ('traction', 2), ('storage_current', 0), ('storage_current', 1), ('storage_power', 0), ('storage_power', 1)):
            dynamic_scores.append(similarity(derivative(resample(reference[sid]['logs'][log_name], index)), derivative(resample(candidate[sid]['logs'][log_name], index)), sharpness=2.0))
    dynamics = 0.85 * mean(dynamic_scores) + 0.15 * bidirectional
    groups = {'A': accuracy, 'Q': 100.0, 'M': mechanism, 'C': causal, 'R': robustness, 'D': dynamics}
    if any((value <= 0.0 for value in groups.values())):
        raw_score = 0.0
    else:
        raw_score = 100.0 * math.exp(sum((WEIGHTS[group] * math.log(groups[group] / 100.0) for group in WEIGHTS)))
    failure_reasons: list[str] = []
    for name, details in causal_pairs.items():
        if details['score'] < 20.0:
            failure_reasons.append(f'{name} input has no adequate causal physical effect')
    if activity < 20.0 or bidirectional < 50.0:
        failure_reasons.append('hybrid-storage physical activity or bidirectional energy flow is absent')
    result.update({'group_scores': {name: round(value, 9) for name, value in groups.items()}, 'scenario_scores': scenario_scores, 'mechanism_metrics': {'storage_trajectory_similarity': storage_similarity, 'storage_activity_utility': activity, 'bidirectional_fraction_score': bidirectional}, 'causal_pairs': causal_pairs, 'raw_score': round(raw_score, 9), 'score_eligible': True, 'failure_reasons': failure_reasons})
    return result

def replace_logs(target: dict[str, Any], source: dict[str, Any]) -> None:
    target['logs'] = copy.deepcopy(source['logs'])
    target['lap_completion_s'] = source.get('lap_completion_s')

def shortcut_variants(reference_evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    variants: dict[str, dict[str, Any]] = {}
    missing = copy.deepcopy(reference_evidence)
    del missing['scenarios'][0]['logs']['storage_power']
    variants['missing_storage_power'] = missing
    fixed = copy.deepcopy(reference_evidence)
    fixed_map = scenario_map(fixed)
    baseline = fixed_map['baseline_all']
    for sid in SCENARIO_IDS[1:]:
        replace_logs(fixed_map[sid], baseline)
    variants['fixed_outputs_across_scenarios'] = fixed
    no_strategy = copy.deepcopy(reference_evidence)
    no_strategy_map = scenario_map(no_strategy)
    replace_logs(no_strategy_map['selected_default'], no_strategy_map['baseline_all'])
    variants['strategy_without_physical_effect'] = no_strategy
    no_cap = copy.deepcopy(reference_evidence)
    no_cap_map = scenario_map(no_cap)
    replace_logs(no_cap_map['heavy_ultracap_all'], no_cap_map['light_ultracap_all'])
    variants['ultracap_mass_without_physical_effect'] = no_cap
    no_battery = copy.deepcopy(reference_evidence)
    no_battery_map = scenario_map(no_battery)
    replace_logs(no_battery_map['heavy_battery_selected'], no_battery_map['light_battery_selected'])
    variants['battery_mass_without_physical_effect'] = no_battery
    disconnected = copy.deepcopy(reference_evidence)
    for scenario in disconnected['scenarios']:
        for log_name in ('storage_current', 'storage_power'):
            width = len(scenario['logs'][log_name]['channels'])
            count = len(scenario['logs'][log_name]['time'])
            scenario['logs'][log_name]['data'] = [[0.0] * width for _ in range(count)]
    variants['disconnected_storage_paths'] = disconnected
    return variants

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--shortcut-sanity', type=Path)
    args = parser.parse_args()
    reference = load_json(args.reference)
    reference_ok, reference_failures = validate(reference)
    if not reference_ok:
        raise SystemExit('invalid complete reference evidence: ' + '; '.join(reference_failures))
    candidate = load_json(args.candidate)
    result = score(reference, candidate)
    write_json(args.output, result)
    if args.shortcut_sanity:
        cases = []
        for name, variant in shortcut_variants(reference).items():
            case_score = score(reference, variant)
            cases.append({'id': name, 'raw_score': case_score['raw_score'], 'gate': case_score['gate'], 'group_scores': case_score['group_scores'], 'failure_reasons': case_score['failure_reasons'], 'passed_below_admission_threshold': case_score['raw_score'] < 85.0})
        maximum = max((case['raw_score'] for case in cases))
        sanity = {'schema': 'simuverity.f90-xbatt08-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'admission_threshold_raw': 85.0, 'cases': cases, 'maximum_shortcut_raw_score': maximum, 'all_shortcuts_below_threshold': all((case['passed_below_admission_threshold'] for case in cases))}
        write_json(args.shortcut_sanity, sanity)
if __name__ == '__main__':
    main()
