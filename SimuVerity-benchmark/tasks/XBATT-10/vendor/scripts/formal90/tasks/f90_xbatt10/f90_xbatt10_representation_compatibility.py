"""Pure-offline XBATT-10 scorer with trace-proven compatibility masks."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XBATT-10'
SCENARIO_IDS = ('baseline', 'heavy_mass', 'low_soc', 'low_power_heavy', 'high_power_heavy', 'regen_off')
LOG_SPEC = {'vehicle': (['drive_cycle_speed_kph', 'vehicle_speed_kph', 'vehicle_acceleration_mps2', 'vehicle_distance_km'], ['km/h', 'km/h', 'm/s^2', 'km']), 'motor': (['torque_Nm', 'speed_rpm', 'mechanical_power_kW'], ['N*m', 'rpm', 'kW']), 'battery': (['voltage_V', 'current_A', 'power_kW', 'soc_fraction'], ['V', 'A', 'kW', '1']), 'controls': (['torque_command_Nm', 'brake_command', 'throttle_percent', 'brake_percent'], ['N*m', '1', '%', '%'])}
EXPECTED_AVAILABILITY = {'vehicle': [False, True, False, False], 'motor': [True, True, True], 'battery': [True, True, True, True], 'controls': [True, False, False, False]}
MISSING_REASONS = {'vehicle.drive_cycle_speed_kph': 'raw vehicle contains actual speed only; evaluator input is not a candidate output', 'vehicle.vehicle_acceleration_mps2': 'no trace-proven raw acceleration channel', 'vehicle.vehicle_distance_km': 'no trace-proven raw distance channel', 'controls.brake_command': 'raw controls channel 3 is brake force in N, not canonical brake command', 'controls.throttle_percent': 'no trace-proven raw throttle-percent channel', 'controls.brake_percent': 'raw controls channel 4 is the regeneration flag, not canonical brake percent'}
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.25, 'C': 0.2, 'R': 0.1, 'D': 0.1}
ACCURACY_KEYS = (('vehicle', 1), ('vehicle', 2), ('vehicle', 3), ('motor', 0), ('motor', 1), ('motor', 2), ('battery', 0), ('battery', 1), ('battery', 2), ('battery', 3))
DYNAMIC_KEYS = (('vehicle', 1), ('vehicle', 2), ('motor', 0), ('motor', 2), ('battery', 1), ('battery', 2))
PAIR_SPEC = {'vehicle_mass': ('baseline', 'heavy_mass', (('vehicle', 1), ('vehicle', 2), ('motor', 0), ('motor', 2), ('battery', 1), ('battery', 2))), 'initial_soc': ('baseline', 'low_soc', (('battery', 0), ('battery', 1), ('battery', 3))), 'power_rating': ('low_power_heavy', 'high_power_heavy', (('vehicle', 1), ('motor', 0), ('motor', 1), ('motor', 2), ('battery', 1))), 'regenerative_braking': ('baseline', 'regen_off', (('motor', 0), ('motor', 2), ('battery', 1), ('battery', 2), ('controls', 1)))}

def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding='utf-8-sig'))

def finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def matrix(data: Any, width: int) -> list[list[float]]:
    if not isinstance(data, list):
        raise ValueError('data is not an array')
    if width == 1 and (not data or finite(data[0])):
        return [[float(value)] for value in data]
    output: list[list[float]] = []
    for row in data:
        if not isinstance(row, list) or len(row) != width or (not all((finite(value) for value in row))):
            raise ValueError('data row width or finiteness mismatch')
        output.append([float(value) for value in row])
    return output

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(item.get('id')): item for item in evidence.get('scenarios', []) if isinstance(item, dict)}

def component_name(log_name: str, index: int) -> str:
    return f'{log_name}.{LOG_SPEC[log_name][0][index]}'

def availability(log: dict[str, Any], width: int, *, reference: bool) -> list[bool]:
    raw = log.get('availability')
    if raw is None and reference:
        return [True] * width
    if isinstance(raw, bool) and width == 1:
        return [raw]
    if isinstance(raw, list) and len(raw) == width:
        return [item is True for item in raw]
    return []

def component_values(scenario: dict[str, Any], log_name: str, index: int, *, reference: bool) -> list[float] | None:
    try:
        log = scenario['logs'][log_name]
        width = len(LOG_SPEC[log_name][0])
        mask = availability(log, width, reference=reference)
        if len(mask) != width or not mask[index]:
            return None
        return [row[index] for row in matrix(log['data'], width)]
    except (KeyError, TypeError, ValueError, IndexError):
        return None

def rms(values: list[float]) -> float:
    return math.sqrt(sum((value * value for value in values)) / max(len(values), 1))

def scale(values: list[float]) -> float:
    return max(rms(values), max(map(abs, values), default=0.0) * 0.1, 1e-09)

def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def similarity(reference: list[float] | None, candidate: list[float] | None, sharpness: float=4.0) -> float:
    if reference is None or candidate is None or (not reference) or (len(reference) != len(candidate)):
        return 0.0
    error = rms([left - right for left, right in zip(reference, candidate)])
    return 100.0 * math.exp(-sharpness * error / scale(reference))

def derivative(values: list[float] | None) -> list[float] | None:
    if values is None:
        return None
    return [right - left for left, right in zip(values, values[1:])]

def ratio_utility(reference_value: float, candidate_value: float) -> float:
    if reference_value <= 1e-12 or candidate_value <= 1e-12:
        return 100.0 if reference_value <= 1e-12 and candidate_value <= 1e-12 else 0.0
    ratio = candidate_value / reference_value
    return 100.0 * min(ratio, 1.0 / ratio)

def validate_reference(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('reference task_id mismatch')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return (False, failures + ['reference scenarios is not an array'])
    if [item.get('id') for item in scenarios if isinstance(item, dict)] != list(SCENARIO_IDS):
        failures.append('reference official scenario identifiers/order mismatch')
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            failures.append('reference scenario entry is not an object')
            continue
        sid = str(scenario.get('id', '<missing>'))
        logs = scenario.get('logs')
        if not isinstance(logs, dict) or set(logs) != set(LOG_SPEC):
            failures.append(f'reference {sid}: canonical log set mismatch')
            continue
        for log_name, (channels, units) in LOG_SPEC.items():
            log = logs[log_name]
            if log.get('channels') != channels or log.get('units') != units:
                failures.append(f'reference {sid}/{log_name}: canonical identity mismatch')
            try:
                time = [float(value) for value in log['time']]
                rows = matrix(log['data'], len(channels))
            except (KeyError, TypeError, ValueError):
                failures.append(f'reference {sid}/{log_name}: invalid time/data')
                continue
            if len(time) != len(rows) or len(time) < 100 or (not all((math.isfinite(value) for value in time))):
                failures.append(f'reference {sid}/{log_name}: incomplete time/data')
    return (not failures, failures)

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
        sid = str(scenario.get('id', '<missing>'))
        if scenario.get('valid') is not True or scenario.get('simulation_pass') is not True:
            failures.append(f'{sid}: simulation/evidence validity flag failed')
        if scenario.get('output_contract', {}).get('all_required_pass') is not True:
            failures.append(f'{sid}: raw output-container contract failed')
        logs = scenario.get('logs')
        if not isinstance(logs, dict) or set(logs) != set(LOG_SPEC):
            failures.append(f'{sid}: canonical log set mismatch')
            continue
        for log_name, (channels, units) in LOG_SPEC.items():
            log = logs[log_name]
            width = len(channels)
            if log.get('channels') != channels or log.get('units') != units:
                failures.append(f'{sid}/{log_name}: canonical identity mismatch')
            if availability(log, width, reference=False) != EXPECTED_AVAILABILITY[log_name]:
                failures.append(f'{sid}/{log_name}: availability mask mismatch')
            sources = log.get('sources')
            if not isinstance(sources, list) or len(sources) != width or (not all((isinstance(value, str) and value for value in sources))):
                failures.append(f'{sid}/{log_name}: source identities missing')
            try:
                time = [float(value) for value in log['time']]
                rows = matrix(log['data'], width)
            except (KeyError, TypeError, ValueError):
                failures.append(f'{sid}/{log_name}: invalid or nonfinite time/data')
                continue
            if len(time) != len(rows) or len(time) < 100 or (not all((math.isfinite(value) for value in time))):
                failures.append(f'{sid}/{log_name}: incomplete time/data')
                continue
            if abs(time[0]) > 1e-09 or abs(time[-1] - 12.0) > 1e-06 or any((right <= left for left, right in zip(time, time[1:]))):
                failures.append(f'{sid}/{log_name}: incomplete or nonmonotonic 0--12 s time')
    return (not failures, failures)

def pair_signal_score(reference: dict[str, dict[str, Any]], candidate: dict[str, dict[str, Any]], left: str, right: str, log_name: str, index: int) -> dict[str, Any]:
    key = component_name(log_name, index)
    rl = component_values(reference[left], log_name, index, reference=True)
    rr = component_values(reference[right], log_name, index, reference=True)
    cl = component_values(candidate[left], log_name, index, reference=False)
    cr = component_values(candidate[right], log_name, index, reference=False)
    if rl is None or rr is None:
        return {'metric': key, 'score': 0.0, 'reason': 'reference component unavailable or malformed'}
    if cl is None or cr is None:
        return {'metric': key, 'score': 0.0, 'reason': MISSING_REASONS.get(key, 'candidate component unavailable')}
    normalizer = max(scale(rl), scale(rr))
    reference_delta = [(b - a) / normalizer for a, b in zip(rl, rr)]
    candidate_delta = [(b - a) / normalizer for a, b in zip(cl, cr)]
    ref_size, cand_size = (rms(reference_delta), rms(candidate_delta))
    magnitude = ratio_utility(ref_size, cand_size)
    shape = similarity(reference_delta, candidate_delta, sharpness=2.0)
    value = math.sqrt(max(magnitude, 0.0) * max(shape, 0.0))
    return {'metric': key, 'score': value, 'reference_normalized_separation': ref_size, 'candidate_normalized_separation': cand_size, 'magnitude_utility': magnitude, 'reason': ''}

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0.0 for name in WEIGHTS)):
        return 0.0
    return 100.0 * math.exp(sum((WEIGHTS[name] * math.log(groups[name] / 100.0) for name in WEIGHTS)))

def score(reference_evidence: dict[str, Any], candidate_evidence: dict[str, Any]) -> dict[str, Any]:
    reference_ok, reference_failures = validate_reference(reference_evidence)
    gate_ok, gate_failures = validate_candidate(candidate_evidence)
    failures = reference_failures + gate_failures
    base: dict[str, Any] = {'schema': 'simuverity.f90-xbatt10-offline-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1.0 if reference_ok and gate_ok else 0.0, 'gate': {'G': 1 if reference_ok and gate_ok else 0, 'passed': reference_ok and gate_ok, 'failures': failures}, 'weights': WEIGHTS}
    if not reference_ok or not gate_ok:
        groups = {name: 0.0 for name in WEIGHTS}
        base.update({**groups, 'group_scores': groups, 'raw_total': 0.0, 'raw_score': 0.0, 'total': 0.0, 'score_eligible': False, 'scenario_scores': [], 'metric_detail': {}, 'failure_reasons': failures})
        return base
    reference = scenario_map(reference_evidence)
    candidate = scenario_map(candidate_evidence)
    per_scenario: list[dict[str, Any]] = []
    scores: dict[str, dict[str, float]] = {}
    availability_by_metric: dict[str, bool] = {}
    for sid in SCENARIO_IDS:
        metric_rows: dict[str, dict[str, Any]] = {}
        scores[sid] = {}
        for log_name, (channels, _) in LOG_SPEC.items():
            for index, _ in enumerate(channels):
                key = component_name(log_name, index)
                actual = component_values(candidate[sid], log_name, index, reference=False)
                expected = component_values(reference[sid], log_name, index, reference=True)
                present = actual is not None
                value = similarity(expected, actual) if present else 0.0
                scores[sid][key] = value
                availability_by_metric[key] = present
                metric_rows[key] = {'score': round(value, 9), 'available': present, 'reason': '' if present else MISSING_REASONS.get(key, 'candidate component unavailable')}
        per_scenario.append({'id': sid, 'score': round(mean([row['score'] for row in metric_rows.values()]), 9), 'metrics': metric_rows})
    accuracy_values = [scores[sid][component_name(log, index)] for sid in SCENARIO_IDS for log, index in ACCURACY_KEYS]
    accuracy = mean(accuracy_values)
    component_count = sum((len(channels) for channels, _ in LOG_SPEC.values()))
    available_count = sum(availability_by_metric.values())
    quality = 100.0 * available_count / component_count
    mechanism_keys = (('motor', 2), ('battery', 1), ('battery', 2))
    mechanism_similarity = mean([scores[sid][component_name(log, index)] for sid in SCENARIO_IDS for log, index in mechanism_keys])
    activity_scores: list[float] = []
    consistency_scores: list[float] = []
    regenerative_scores: list[float] = []
    for sid in SCENARIO_IDS:
        for log_name, index in mechanism_keys:
            ref_values = component_values(reference[sid], log_name, index, reference=True)
            cand_values = component_values(candidate[sid], log_name, index, reference=False)
            if ref_values is None or cand_values is None:
                activity_scores.append(0.0)
            else:
                activity_scores.append(ratio_utility(max(map(abs, ref_values)), max(map(abs, cand_values))))
        ref_torque = component_values(reference[sid], 'motor', 0, reference=True)
        ref_speed = component_values(reference[sid], 'motor', 1, reference=True)
        ref_power = component_values(reference[sid], 'motor', 2, reference=True)
        cand_torque = component_values(candidate[sid], 'motor', 0, reference=False)
        cand_speed = component_values(candidate[sid], 'motor', 1, reference=False)
        cand_power = component_values(candidate[sid], 'motor', 2, reference=False)
        if None in (ref_torque, ref_speed, ref_power, cand_torque, cand_speed, cand_power):
            consistency_scores.append(0.0)
        else:
            assert ref_torque is not None and ref_speed is not None and (ref_power is not None)
            assert cand_torque is not None and cand_speed is not None and (cand_power is not None)
            ref_calculated = [t * w * 2.0 * math.pi / 60.0 / 1000.0 for t, w in zip(ref_torque, ref_speed)]
            cand_calculated = [t * w * 2.0 * math.pi / 60.0 / 1000.0 for t, w in zip(cand_torque, cand_speed)]
            consistency_scores.append(similarity([a - b for a, b in zip(ref_power, ref_calculated)], [a - b for a, b in zip(cand_power, cand_calculated)], sharpness=2.0))
        if sid != 'regen_off':
            if ref_power is None or cand_power is None:
                regenerative_scores.append(0.0)
            else:
                regenerative_scores.append(ratio_utility(sum((max(-value, 0.0) for value in ref_power)), sum((max(-value, 0.0) for value in cand_power))))
    activity = mean(activity_scores)
    consistency = mean(consistency_scores)
    regenerative = mean(regenerative_scores)
    mechanism = 0.55 * mechanism_similarity + 0.2 * activity + 0.15 * consistency + 0.1 * regenerative
    causal_pairs: dict[str, Any] = {}
    pair_values: list[float] = []
    for name, (left, right, pair_components) in PAIR_SPEC.items():
        signal_rows = [pair_signal_score(reference, candidate, left, right, log_name, index) for log_name, index in pair_components]
        value = mean([row['score'] for row in signal_rows])
        causal_pairs[name] = {'score': value, 'signals': signal_rows}
        pair_values.append(value)
    causal = 0.7 * min(pair_values) + 0.3 * mean(pair_values)
    robustness = min((item['score'] for item in per_scenario))
    dynamic_scores = []
    for sid in SCENARIO_IDS:
        for log_name, index in DYNAMIC_KEYS:
            dynamic_scores.append(similarity(derivative(component_values(reference[sid], log_name, index, reference=True)), derivative(component_values(candidate[sid], log_name, index, reference=False)), sharpness=2.0))
    dynamics = mean(dynamic_scores)
    groups = {'A': accuracy, 'Q': quality, 'M': mechanism, 'C': causal, 'R': robustness, 'D': dynamics}
    raw_total = geometric(groups)
    missing = [{'metric': key, 'reason': MISSING_REASONS[key], 'score': 0.0} for key in sorted(MISSING_REASONS)]
    performance_reasons = [f'{name} intervention has weak or absent causal physical effect' for name, row in causal_pairs.items() if row['score'] < 20.0]
    if activity < 20.0 or regenerative < 20.0:
        performance_reasons.append('connected battery-motor regenerative energy activity is weak or absent')
    rounded_groups = {name: round(value, 9) for name, value in groups.items()}
    base.update({**rounded_groups, 'group_scores': rounded_groups, 'raw_total': round(raw_total, 9), 'raw_score': round(raw_total, 9), 'total': round(raw_total, 9), 'score_eligible': True, 'scenario_scores': per_scenario, 'metric_detail': {'accuracy_metric_positions': [component_name(log, index) for log, index in ACCURACY_KEYS], 'dynamic_metric_positions': [component_name(log, index) for log, index in DYNAMIC_KEYS], 'output_component_completeness': {'available': available_count, 'total': component_count, 'score': quality}, 'mechanism': {'trajectory_similarity': mechanism_similarity, 'activity_utility': activity, 'motor_power_consistency_utility': consistency, 'regenerative_energy_utility': regenerative}, 'causal_pairs': causal_pairs, 'unavailable_components_scored_zero': missing}, 'failure_reasons': performance_reasons + [f"{row['metric']}: {row['reason']}" for row in missing]})
    return base

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = score(read_json(args.reference), read_json(args.candidate))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
