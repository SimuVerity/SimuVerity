"""Pure-offline scorer for F90-XBATT-10; reads complete JSON evidence only."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XBATT-10'
SCENARIO_IDS = ('baseline', 'heavy_mass', 'low_soc', 'low_power_heavy', 'high_power_heavy', 'regen_off')
LOG_SPEC = {'vehicle': (['drive_cycle_speed_kph', 'vehicle_speed_kph', 'vehicle_acceleration_mps2', 'vehicle_distance_km'], ['km/h', 'km/h', 'm/s^2', 'km']), 'motor': (['torque_Nm', 'speed_rpm', 'mechanical_power_kW'], ['N*m', 'rpm', 'kW']), 'battery': (['voltage_V', 'current_A', 'power_kW', 'soc_fraction'], ['V', 'A', 'kW', '1']), 'controls': (['torque_command_Nm', 'brake_command', 'throttle_percent', 'brake_percent'], ['N*m', '1', '%', '%'])}
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.25, 'C': 0.2, 'R': 0.1, 'D': 0.1}
PAIR_SPEC = {'vehicle_mass': ('baseline', 'heavy_mass', (('vehicle', 1), ('vehicle', 2), ('motor', 0), ('motor', 2), ('battery', 1), ('battery', 2))), 'initial_soc': ('baseline', 'low_soc', (('battery', 0), ('battery', 1), ('battery', 3))), 'power_rating': ('low_power_heavy', 'high_power_heavy', (('vehicle', 1), ('motor', 0), ('motor', 1), ('motor', 2), ('battery', 1))), 'regenerative_braking': ('baseline', 'regen_off', (('motor', 0), ('motor', 2), ('battery', 1), ('battery', 2), ('controls', 1)))}

def load_json(path: Path) -> dict[str, Any]:
    with path.open('r', encoding='utf-8') as handle:
        return json.load(handle)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def rows(data: Any, width: int) -> list[list[float]]:
    if not isinstance(data, list):
        raise ValueError('data is not an array')
    if width == 1 and (not data or finite_number(data[0])):
        return [[float(value)] for value in data]
    result = []
    for row in data:
        if not isinstance(row, list) or len(row) != width or (not all((finite_number(value) for value in row))):
            raise ValueError('data row width or finiteness mismatch')
        result.append([float(value) for value in row])
    return result

def validate(evidence: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    scenarios = evidence.get('scenarios')
    if not isinstance(scenarios, list):
        return (False, failures + ['scenarios is not an array'])
    ids = [s.get('id') for s in scenarios if isinstance(s, dict)]
    if len(ids) != len(SCENARIO_IDS) or sorted(ids) != sorted(SCENARIO_IDS):
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
            if not isinstance(time, list) or len(time) < 100 or (not all((finite_number(v) for v in time))):
                failures.append(f'{sid}/{log_name}: time vector is short or nonfinite')
                continue
            time = [float(v) for v in time]
            if abs(time[0]) > 1e-09 or abs(time[-1] - 12.0) > 1e-06:
                failures.append(f'{sid}/{log_name}: time coverage must be exactly 0--12 s')
            if any((b <= a for a, b in zip(time, time[1:]))):
                failures.append(f'{sid}/{log_name}: time is not strictly increasing')
            try:
                matrix = rows(log.get('data'), len(channels))
            except ValueError as exc:
                failures.append(f'{sid}/{log_name}: {exc}')
                continue
            if len(matrix) != len(time):
                failures.append(f'{sid}/{log_name}: data length differs from time length')
    return (not failures, failures)

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {s['id']: s for s in evidence['scenarios']}

def channel(log: dict[str, Any], index: int) -> list[float]:
    return [row[index] for row in rows(log['data'], len(log['channels']))]

def rms(values: list[float]) -> float:
    return math.sqrt(sum((v * v for v in values)) / max(len(values), 1))

def scale(values: list[float]) -> float:
    return max(rms(values), max(map(abs, values)) * 0.1, 1e-09)

def similarity(reference: list[float], candidate: list[float], sharpness: float=4.0) -> float:
    return 100.0 * math.exp(-sharpness * rms([a - b for a, b in zip(reference, candidate)]) / scale(reference))

def derivative(values: list[float]) -> list[float]:
    return [b - a for a, b in zip(values, values[1:])]

def mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def ratio_utility(reference_value: float, candidate_value: float) -> float:
    if reference_value <= 1e-12 or candidate_value <= 1e-12:
        return 100.0 if reference_value <= 1e-12 and candidate_value <= 1e-12 else 0.0
    ratio = candidate_value / reference_value
    return 100.0 * min(ratio, 1.0 / ratio)

def pair_score(ref: dict[str, dict[str, Any]], cand: dict[str, dict[str, Any]], left: str, right: str, signals: tuple[tuple[str, int], ...]) -> tuple[float, dict[str, float]]:
    rd: list[float] = []
    cd: list[float] = []
    for log_name, index in signals:
        rl, rr = (channel(ref[left]['logs'][log_name], index), channel(ref[right]['logs'][log_name], index))
        cl, cr = (channel(cand[left]['logs'][log_name], index), channel(cand[right]['logs'][log_name], index))
        normalizer = max(scale(rl), scale(rr))
        rd.extend(((b - a) / normalizer for a, b in zip(rl, rr)))
        cd.extend(((b - a) / normalizer for a, b in zip(cl, cr)))
    rs, cs = (rms(rd), rms(cd))
    magnitude = ratio_utility(rs, cs)
    shape = similarity(rd, cd, sharpness=2.0)
    score_value = math.sqrt(max(magnitude, 0.0) * max(shape, 0.0))
    return (score_value, {'reference_normalized_separation': rs, 'candidate_normalized_separation': cs, 'magnitude_utility': magnitude, 'score': score_value})

def score(reference_evidence: dict[str, Any], candidate_evidence: dict[str, Any]) -> dict[str, Any]:
    gate_ok, gate_failures = validate(candidate_evidence)
    result: dict[str, Any] = {'schema': 'simuverity.f90-xbatt10-offline-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'weights': WEIGHTS, 'gate': {'G': 1 if gate_ok else 0, 'passed': gate_ok, 'failures': gate_failures}}
    if not gate_ok:
        result.update({'group_scores': {g: 0.0 for g in WEIGHTS}, 'scenario_scores': [], 'causal_pairs': {}, 'raw_score': 0.0, 'score_eligible': False, 'failure_reasons': gate_failures})
        return result
    ref, cand = (scenario_map(reference_evidence), scenario_map(candidate_evidence))
    per_scenario = []
    channel_scores: dict[str, dict[str, float]] = {}
    for sid in SCENARIO_IDS:
        scores = {}
        for log_name, (channels, _) in LOG_SPEC.items():
            for index, channel_name in enumerate(channels):
                key = f'{log_name}.{channel_name}'
                scores[key] = similarity(channel(ref[sid]['logs'][log_name], index), channel(cand[sid]['logs'][log_name], index))
        channel_scores[sid] = scores
        per_scenario.append({'id': sid, 'score': mean(list(scores.values())), 'channels': scores})
    accuracy_keys = ('vehicle.vehicle_speed_kph', 'vehicle.vehicle_acceleration_mps2', 'vehicle.vehicle_distance_km', 'motor.torque_Nm', 'motor.speed_rpm', 'motor.mechanical_power_kW', 'battery.voltage_V', 'battery.current_A', 'battery.power_kW', 'battery.soc_fraction')
    accuracy = mean([channel_scores[sid][key] for sid in SCENARIO_IDS for key in accuracy_keys])
    mechanism_similarity = mean([channel_scores[sid][key] for sid in SCENARIO_IDS for key in ('motor.mechanical_power_kW', 'battery.current_A', 'battery.power_kW')])
    activity_scores = []
    consistency_scores = []
    regen_scores = []
    for sid in SCENARIO_IDS:
        for log_name, index in (('motor', 2), ('battery', 1), ('battery', 2)):
            rv, cv = (channel(ref[sid]['logs'][log_name], index), channel(cand[sid]['logs'][log_name], index))
            activity_scores.append(ratio_utility(max(map(abs, rv)), max(map(abs, cv))))
        rt, rw, rp = (channel(ref[sid]['logs']['motor'], i) for i in (0, 1, 2))
        ct, cw, cp = (channel(cand[sid]['logs']['motor'], i) for i in (0, 1, 2))
        rcalc = [t * w * 2.0 * math.pi / 60.0 / 1000.0 for t, w in zip(rt, rw)]
        ccalc = [t * w * 2.0 * math.pi / 60.0 / 1000.0 for t, w in zip(ct, cw)]
        consistency_scores.append(similarity([a - b for a, b in zip(rp, rcalc)], [a - b for a, b in zip(cp, ccalc)], sharpness=2.0))
        if sid != 'regen_off':
            rneg, cneg = (sum((max(-v, 0.0) for v in rp)), sum((max(-v, 0.0) for v in cp)))
            regen_scores.append(ratio_utility(rneg, cneg))
    activity, consistency, regenerative = (mean(activity_scores), mean(consistency_scores), mean(regen_scores))
    mechanism = 0.55 * mechanism_similarity + 0.2 * activity + 0.15 * consistency + 0.1 * regenerative
    causal_pairs = {}
    for name, (left, right, signals) in PAIR_SPEC.items():
        _, details = pair_score(ref, cand, left, right, signals)
        causal_pairs[name] = details
    pair_values = [v['score'] for v in causal_pairs.values()]
    causal = 0.7 * min(pair_values) + 0.3 * mean(pair_values)
    robustness = min((item['score'] for item in per_scenario))
    dynamics = mean([similarity(derivative(channel(ref[sid]['logs'][log], idx)), derivative(channel(cand[sid]['logs'][log], idx)), sharpness=2.0) for sid in SCENARIO_IDS for log, idx in (('vehicle', 1), ('vehicle', 2), ('motor', 0), ('motor', 2), ('battery', 1), ('battery', 2))])
    groups = {'A': accuracy, 'Q': 100.0, 'M': mechanism, 'C': causal, 'R': robustness, 'D': dynamics}
    raw_score = 0.0 if any((v <= 0 for v in groups.values())) else 100.0 * math.exp(sum((WEIGHTS[g] * math.log(groups[g] / 100.0) for g in WEIGHTS)))
    failures = [f'{name} input has no adequate causal physical effect' for name, details in causal_pairs.items() if details['score'] < 20.0]
    if activity < 20.0 or regenerative < 20.0:
        failures.append('connected battery-motor regenerative energy activity is absent')
    result.update({'group_scores': {g: round(v, 9) for g, v in groups.items()}, 'scenario_scores': per_scenario, 'mechanism_metrics': {'trajectory_similarity': mechanism_similarity, 'activity_utility': activity, 'motor_power_consistency_utility': consistency, 'regenerative_energy_utility': regenerative}, 'causal_pairs': causal_pairs, 'raw_score': round(raw_score, 9), 'score_eligible': True, 'failure_reasons': failures})
    return result

def replace_logs(target: dict[str, Any], source: dict[str, Any]) -> None:
    target['logs'] = copy.deepcopy(source['logs'])

def shortcut_variants(reference: dict[str, Any]) -> dict[str, dict[str, Any]]:
    variants = {}
    missing = copy.deepcopy(reference)
    del missing['scenarios'][0]['logs']['battery']
    variants['missing_battery_log'] = missing
    fixed = copy.deepcopy(reference)
    fm = scenario_map(fixed)
    for sid in SCENARIO_IDS[1:]:
        replace_logs(fm[sid], fm['baseline'])
    variants['fixed_outputs_across_scenarios'] = fixed
    for name, left, right in (('mass_without_effect', 'baseline', 'heavy_mass'), ('soc_without_effect', 'baseline', 'low_soc'), ('power_rating_without_effect', 'low_power_heavy', 'high_power_heavy'), ('regen_flag_without_effect', 'baseline', 'regen_off')):
        variant = copy.deepcopy(reference)
        vm = scenario_map(variant)
        replace_logs(vm[right], vm[left])
        variants[name] = variant
    disconnected = copy.deepcopy(reference)
    for scenario in disconnected['scenarios']:
        for log_name, indices in (('motor', (0, 2)), ('battery', (1, 2))):
            matrix = rows(scenario['logs'][log_name]['data'], len(scenario['logs'][log_name]['channels']))
            for row in matrix:
                for idx in indices:
                    row[idx] = 0.0
            scenario['logs'][log_name]['data'] = matrix
    variants['disconnected_energy_path'] = disconnected
    return variants

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--shortcut-sanity', type=Path)
    args = parser.parse_args()
    reference = load_json(args.reference)
    reference_ok, failures = validate(reference)
    if not reference_ok:
        raise SystemExit('invalid complete reference evidence: ' + '; '.join(failures))
    candidate = load_json(args.candidate)
    result = score(reference, candidate)
    write_json(args.output, result)
    if args.shortcut_sanity:
        cases = []
        for name, variant in shortcut_variants(reference).items():
            case = score(reference, variant)
            cases.append({'id': name, 'raw_score': case['raw_score'], 'gate': case['gate'], 'group_scores': case['group_scores'], 'failure_reasons': case['failure_reasons'], 'passed_below_admission_threshold': case['raw_score'] < 85.0})
        maximum = max((case['raw_score'] for case in cases))
        write_json(args.shortcut_sanity, {'schema': 'simuverity.f90-xbatt10-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'admission_threshold_raw': 85.0, 'cases': cases, 'maximum_shortcut_raw_score': maximum, 'all_shortcuts_below_threshold': all((case['passed_below_admission_threshold'] for case in cases))})
if __name__ == '__main__':
    main()
