"""Dedicated fixed-evidence scorer for F90-XFLUID-10."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any, Callable
import numpy as np
from scipy.io import loadmat
TASK_ID = 'F90-XFLUID-10'
POLICY_ID = 'simuverity-101-v1:f90-xfluid-10:scoring'
REQUIRED_IDS = {'nominal', 'low_speed', 'high_speed', 'low_fuel', 'high_fuel', 'low_speed_low_fuel', 'high_speed_high_fuel'}
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def lower_better(value: float, full: float, zero: float) -> float:
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return clamp((zero - value) / (zero - full))

def higher_better(value: float, zero: float, full: float) -> float:
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return clamp((value - zero) / (full - zero))

def band_score(value: float, low_zero: float, low_full: float, high_full: float, high_zero: float) -> float:
    if low_full <= value <= high_full:
        return 1.0
    if value < low_full:
        return higher_better(value, low_zero, low_full)
    return lower_better(value, high_full, high_zero)

def weighted_mean(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    if denominator <= 0.0:
        return 0.0
    return sum((clamp(value) * weight for value, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[key] <= 0.0 for key in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[key] * math.log(groups[key]) for key in WEIGHTS)))

def scenario_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row['id']): row for row in evidence.get('scenarios', [])}

def metric(row: dict[str, Any], key: str) -> float:
    return float(row['metrics'][key])

def array_metric(row: dict[str, Any], key: str) -> list[float]:
    value = row['metrics'][key]
    if isinstance(value, list):
        return [float(item) for item in value]
    return [float(value)]

def relative_difference(first: float, second: float) -> float:
    return abs(first - second) / max(0.5 * (abs(first) + abs(second)), 1e-15)

def pulse_events(time: np.ndarray, flow: np.ndarray, analysis_start: float=0.04, boundary_margin: float=0.002) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    smoothed = np.convolve(np.abs(flow), np.ones(5) / 5.0, mode='same')
    analysis = time >= analysis_start
    peak = float(np.max(smoothed[analysis]))
    if not math.isfinite(peak) or peak <= 1e-10:
        return (np.array([]), np.array([]), np.array([]))
    active = (smoothed >= max(0.12 * peak, 1e-09)) & analysis
    edges = np.diff(np.concatenate(([False], active, [False])).astype(int))
    starts = np.flatnonzero(edges == 1)
    stops = np.flatnonzero(edges == -1) - 1
    keep = (stops - starts + 1 >= 3) & (time[starts] >= analysis_start + boundary_margin) & (time[stops] <= time[-1] - boundary_margin)
    starts = starts[keep]
    stops = stops[keep]
    event_times: list[float] = []
    event_volumes: list[float] = []
    event_peaks: list[float] = []
    for start, stop in zip(starts, stops, strict=True):
        segment = np.arange(start, stop + 1)
        local_peak = int(np.argmax(smoothed[segment]))
        event_times.append(float(time[segment[local_peak]]))
        event_volumes.append(float(np.trapezoid(smoothed[segment], time[segment])))
        event_peaks.append(float(np.max(smoothed[segment])))
    return (np.asarray(event_times), np.asarray(event_volumes), np.asarray(event_peaks))

def sample_cv(values: np.ndarray) -> float:
    if values.size <= 1:
        return 0.0
    return float(np.std(values, ddof=1) / max(abs(float(np.mean(values))), 1e-15))

def firing_order_match(ids: list[int]) -> float:
    if len(ids) < 4:
        return 0.0
    expected = np.asarray([1, 3, 4, 2])
    observed = np.asarray(ids)
    scores: list[float] = []
    for shift in range(4):
        pattern = np.resize(np.roll(expected, shift), observed.size)
        scores.append(float(np.mean(observed == pattern)))
    return max(scores)

def refresh_metrics_from_complete_raw(evidence: dict[str, Any], evidence_path: Path) -> int:
    """Recompute pulse-window metrics from complete complete-interval MAT evidence."""
    refreshed = 0
    for row in evidence.get('scenarios', []):
        raw_path = Path(str(row.get('raw_log_path', '')))
        if not raw_path.is_absolute():
            raw_path = evidence_path.parent / raw_path
        if not raw_path.is_file():
            continue
        raw = loadmat(raw_path, squeeze_me=True, struct_as_record=False)
        outputs = raw['outputs']
        time = np.asarray(outputs.time_s, dtype=float).reshape(-1)
        delivery = np.asarray(outputs.injection_delivery, dtype=float)
        counts: list[int] = []
        median_volumes: list[float] = []
        median_peaks: list[float] = []
        per_injector_cv: list[float] = []
        last_drift: list[float] = []
        combined: list[tuple[float, int]] = []
        for injector in range(4):
            times, volumes, peaks = pulse_events(time, delivery[:, injector])
            counts.append(int(times.size))
            median_volumes.append(float(np.median(volumes)) if volumes.size else 0.0)
            median_peaks.append(float(np.median(peaks)) if peaks.size else 0.0)
            per_injector_cv.append(sample_cv(volumes))
            if volumes.size >= 2:
                last_drift.append(float(abs(volumes[-1] - volumes[-2]) / max(abs(float(volumes[-2])), 1e-15)))
            else:
                last_drift.append(1.0)
            combined.extend(((float(t), injector + 1) for t in times))
        combined.sort()
        combined_times = np.asarray([item[0] for item in combined])
        combined_ids = [item[1] for item in combined]
        if combined_times.size >= 3:
            spacing = np.diff(combined_times)
            spacing_cv = sample_cv(spacing)
            event_rate = float((combined_times.size - 1) / max(combined_times[-1] - combined_times[0], 1e-15))
        else:
            spacing_cv = 1.0
            event_rate = 0.0
        metrics = row['metrics']
        volume_array = np.asarray(median_volumes)
        peak_array = np.asarray(median_peaks)
        metrics.update({'pulse_count_per_injector': counts, 'pulse_volume_per_event_m3': median_volumes, 'mean_pulse_volume_m3': float(np.mean(volume_array)), 'pulse_volume_balance_cv': sample_cv(volume_array), 'per_injector_pulse_volume_cv': per_injector_cv, 'maximum_pulse_volume_cv': max(per_injector_cv), 'last_pulse_drift_fraction': last_drift, 'maximum_last_pulse_drift_fraction': max(last_drift), 'peak_flow_per_injector_m3_s': median_peaks, 'peak_flow_balance_cv': sample_cv(peak_array), 'firing_order_match_fraction': firing_order_match(combined_ids), 'combined_event_spacing_cv': spacing_cv, 'combined_event_rate_Hz': event_rate})
        refreshed += 1
    return refreshed

def gate_failure(checks: dict[str, bool]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xfluid10-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 0.0, 'groups': {'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 'group_weights': WEIGHTS, 'score_raw': 0.0, 'shortcut_findings': [], 'admission_threshold_raw': 85.0, 'preferred_reference_score_raw': 90.0, 'admission_pass': False, 'qualification_checks': checks, 'failures': [name for name, passed in checks.items() if not passed]}

def robustness(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    counts = array_metric(row, 'pulse_count_per_injector')
    parts = {'all_four_injectors_pulse': (higher_better(min(counts), 0.5, 2.0), 0.2), 'firing_order': (higher_better(metric(row, 'firing_order_match_fraction'), 0.45, 0.92), 0.25), 'delivered_volume_balance': (lower_better(metric(row, 'pulse_volume_balance_cv'), 0.06, 0.35), 0.2), 'active_plungers': (higher_better(metric(row, 'minimum_plunger_amplitude_m'), 1e-05, 0.0005), 0.1), 'active_needles': (higher_better(metric(row, 'minimum_needle_lift_m'), 1e-07, 2e-05), 0.1), 'physical_injection_pressure': (higher_better(metric(row, 'minimum_peak_chamber_pressure_Pa'), 1000000.0, 8000000.0), 0.15)}
    return (weighted_mean(parts), parts)

def dynamic(row: dict[str, Any]) -> tuple[float, dict[str, tuple[float, float]]]:
    parts = {'plunger_stroke_excursion': (higher_better(metric(row, 'minimum_plunger_amplitude_m'), 0.004, 0.01), 0.35), 'needle_lift_excursion': (higher_better(metric(row, 'minimum_needle_lift_m'), 5e-05, 0.001), 0.35), 'cycle_volume_repeatability': (lower_better(metric(row, 'maximum_pulse_volume_cv'), 0.08, 0.4), 0.1), 'late_cycle_drift': (lower_better(metric(row, 'maximum_last_pulse_drift_fraction'), 0.08, 0.45), 0.075), 'inter_event_timing': (lower_better(metric(row, 'combined_event_spacing_cv'), 0.1, 0.5), 0.075), 'bounded_peak_pressure': (band_score(metric(row, 'maximum_chamber_pressure_Pa'), 1000000.0, 8000000.0, 250000000.0, 400000000.0), 0.05)}
    return (weighted_mean(parts), parts)

def qualification(evidence: dict[str, Any]) -> dict[str, bool]:
    rows = scenario_map(evidence)
    static = evidence.get('static_audit', {})
    causal = static.get('causal_behavior', {})
    counts = static.get('component_counts', {})
    reference = bool(evidence.get('reference_direct_golden'))
    structure_fields = {'compressible_delivery_elements', 'mechanical_storage_elements', 'high_pressure_delivery_paths'}
    fuel_path_supported = bool(static.get('fuel_control_drives_all_pumps')) or bool(causal.get('fuel_response') and static.get('four_injection_pumps') and static.get('each_pump_feeds_its_injector'))
    return {'reference_identity': bool(evidence.get('reference_direct_golden') or evidence.get('evaluation_subject') == 'candidate'), 'source_unchanged': bool(evidence.get('source_unchanged') or evidence.get('evaluation_subject') == 'candidate'), 'evidence_complete': bool(evidence.get('evidence_complete')), 'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'scenario_set': set(rows) == REQUIRED_IDS, 'all_scenarios_valid': set(rows) == REQUIRED_IDS and all((bool(rows[key].get('valid')) for key in REQUIRED_IDS)), 'four_injection_pumps': bool(static.get('four_injection_pumps')), 'four_injectors': bool(static.get('four_injectors')), 'lift_pump_is_physically_connected': bool(static.get('lift_pump_is_physically_connected')), 'fuel_control_drives_all_pumps': fuel_path_supported, 'each_pump_feeds_its_injector': bool(static.get('each_pump_feeds_its_injector')), 'feed_pipe_present': bool(static.get('feed_pipe_present')), 'accumulator_and_relief_present': bool(static.get('accumulator_and_relief_present')), 'reservoir_present': bool(static.get('reservoir_present')), 'neutral_structure_evidence': reference or structure_fields.issubset(counts)}

def structure_utilities(evidence: dict[str, Any]) -> dict[str, float]:
    """Score implementation-neutral physical depth, not candidate block names."""
    if evidence.get('reference_direct_golden'):
        return {'compressible_delivery_depth': 1.0, 'distributed_mechanical_storage': 1.0, 'connected_delivery_paths': 1.0}
    counts = evidence.get('static_audit', {}).get('component_counts', {})
    return {'compressible_delivery_depth': higher_better(float(counts.get('compressible_delivery_elements', 0)), 4.0, 12.0), 'distributed_mechanical_storage': higher_better(float(counts.get('mechanical_storage_elements', 0)), 12.0, 22.0), 'connected_delivery_paths': higher_better(float(counts.get('high_pressure_delivery_paths', 0)), 2.0, 4.0)}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    checks = qualification(evidence)
    if not all(checks.values()):
        return gate_failure(checks)
    rows = scenario_map(evidence)
    nominal = rows['nominal']
    nominal_metrics = nominal['metrics']
    counts = array_metric(nominal, 'pulse_count_per_injector')
    group_a_parts = {'four_active_injectors': (higher_better(min(counts), 0.5, 2.0), 0.05), 'firing_order_1_3_4_2': (higher_better(metric(nominal, 'firing_order_match_fraction'), 0.45, 0.95), 0.1), 'comparable_delivered_volume': (lower_better(metric(nominal, 'pulse_volume_balance_cv'), 0.04, 0.3), 0.05), 'useful_pulse_volume': (higher_better(metric(nominal, 'mean_pulse_volume_m3'), 5e-08, 2.5e-07), 0.35), 'diesel_injection_pressure': (higher_better(metric(nominal, 'minimum_peak_chamber_pressure_Pa'), 10000000.0, 60000000.0), 0.45)}
    group_a = weighted_mean(group_a_parts)
    group_q_parts = {'pulse_volume_balance': (lower_better(metric(nominal, 'pulse_volume_balance_cv'), 0.035, 0.3), 0.25), 'peak_flow_balance': (lower_better(metric(nominal, 'peak_flow_balance_cv'), 0.05, 0.35), 0.15), 'event_spacing_uniformity': (lower_better(metric(nominal, 'combined_event_spacing_cv'), 0.08, 0.45), 0.2), 'pressure_balance': (lower_better(metric(nominal, 'pressure_peak_balance_cv'), 0.05, 0.35), 0.15), 'plunger_amplitude_balance': (lower_better(metric(nominal, 'plunger_amplitude_balance_cv'), 0.03, 0.25), 0.1), 'needle_lift_balance': (lower_better(metric(nominal, 'needle_lift_balance_cv'), 0.05, 0.35), 0.1), 'nonduplicated_flow_traces': (lower_better(metric(nominal, 'maximum_zero_lag_flow_correlation'), 0.45, 0.95), 0.05)}
    group_q = weighted_mean(group_q_parts)
    low_fuel = rows['low_fuel']
    high_fuel = rows['high_fuel']
    low_speed = rows['low_speed']
    high_speed = rows['high_speed']
    fuel_response = relative_difference(metric(low_fuel, 'mean_pulse_volume_m3'), metric(high_fuel, 'mean_pulse_volume_m3'))
    observed_rate_ratio = metric(high_speed, 'combined_event_rate_Hz') / max(metric(low_speed, 'combined_event_rate_Hz'), 1e-12)
    rate_ratio_error = abs(observed_rate_ratio - 1.5) / 1.5
    summarys = {round(metric(row, 'service_summary'), 6) for row in rows.values()}
    structure = structure_utilities(evidence)
    group_m_parts = {'connected_lift_pump_and_four_delivery_paths': (structure['connected_delivery_paths'], 0.15), 'compressible_delivery_path_depth': (structure['compressible_delivery_depth'], 0.3), 'distributed_mechanical_storage': (structure['distributed_mechanical_storage'], 0.25), 'fuel_metering_response': (band_score(fuel_response, 0.015, 0.08, 1.5, 3.0), 0.1), 'speed_to_event_rate_response': (lower_better(rate_ratio_error, 0.08, 0.4), 0.05), 'scenarios_not_replayed': (higher_better(float(len(summarys)), 1.5, 5.0), 0.05), 'nonduplicated_physical_outputs': (lower_better(metric(nominal, 'maximum_zero_lag_flow_correlation'), 0.45, 0.95), 0.1)}
    group_m = weighted_mean(group_m_parts)
    robustness_rows: dict[str, float] = {}
    robustness_parts: dict[str, Any] = {}
    dynamic_rows: dict[str, float] = {}
    dynamic_parts: dict[str, Any] = {}
    for scenario_id, row in rows.items():
        robustness_rows[scenario_id], robustness_parts[scenario_id] = robustness(row)
        dynamic_rows[scenario_id], dynamic_parts[scenario_id] = dynamic(row)
    group_r = min(robustness_rows.values())
    group_d = min(dynamic_rows.values())
    groups = {'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    score_raw = 100.0 * geometric(groups)
    shortcut_findings: list[dict[str, Any]] = []

    def record_shortcut(name: str, condition: bool, cap: float, observed: float) -> None:
        if condition:
            shortcut_findings.append({'name': name, 'group_utility_ceiling': cap, 'observed': float(observed)})
    nominal_order = metric(nominal, 'firing_order_match_fraction')
    nominal_correlation = metric(nominal, 'maximum_zero_lag_flow_correlation')
    record_shortcut('wrong_firing_order', nominal_order < 0.7, 55.0, nominal_order)
    record_shortcut('duplicated_injector_traces', nominal_correlation > 0.96, 45.0, nominal_correlation)
    record_shortcut('fuel_command_ignored', fuel_response < 0.035, 65.0, fuel_response)
    record_shortcut('scenarios_replayed', len(summarys) <= 2, 45.0, float(len(summarys)))
    record_shortcut('one_or_more_scenarios_fail_materially', group_r < 0.3, 60.0, group_r)
    return {'schema': 'simuverity.f90-xfluid10-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'G': 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'group_parts': {'A': group_a_parts, 'Q': group_q_parts, 'M': group_m_parts, 'R_by_scenario': robustness_rows, 'R_parts_by_scenario': robustness_parts, 'D_by_scenario': dynamic_rows, 'D_parts_by_scenario': dynamic_parts}, 'derived': {'fuel_metering_relative_response': fuel_response, 'observed_high_to_low_speed_event_rate_ratio': observed_rate_ratio, 'speed_rate_ratio_relative_error': rate_ratio_error, 'distinct_official_summarys': len(summarys), 'nominal_mean_pulse_volume_m3': float(nominal_metrics['mean_pulse_volume_m3']), 'structure_utilities': structure}, 'shortcut_findings': shortcut_findings, 'score_raw': score_raw, 'admission_threshold_raw': 85.0, 'preferred_reference_score_raw': 90.0, 'admission_pass': score_raw >= 85.0, 'preferred_reference_pass': score_raw >= 90.0, 'qualification_checks': checks, 'failures': []}

def set_metric(evidence: dict[str, Any], scenario_id: str, key: str, value: Any) -> None:
    rows = scenario_map(evidence)
    rows[scenario_id]['metrics'][key] = value

def run_shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: list[tuple[str, float, Callable[[dict[str, Any]], None]]] = []

    def missing_output(mutant: dict[str, Any]) -> None:
        mutant['evidence_complete'] = False

    def fewer_pumps(mutant: dict[str, Any]) -> None:
        mutant['static_audit']['four_injection_pumps'] = False

    def duplicated_traces(mutant: dict[str, Any]) -> None:
        set_metric(mutant, 'nominal', 'maximum_zero_lag_flow_correlation', 1.0)
        set_metric(mutant, 'nominal', 'firing_order_match_fraction', 0.25)
        set_metric(mutant, 'nominal', 'combined_event_spacing_cv', 1.0)

    def wrong_order(mutant: dict[str, Any]) -> None:
        for row in mutant['scenarios']:
            row['metrics']['firing_order_match_fraction'] = 0.25

    def fuel_control_ignored(mutant: dict[str, Any]) -> None:
        rows = scenario_map(mutant)
        nominal = copy.deepcopy(rows['nominal']['metrics'])
        for scenario_id in ('low_fuel', 'high_fuel'):
            rows[scenario_id]['metrics']['mean_pulse_volume_m3'] = nominal['mean_pulse_volume_m3']
            rows[scenario_id]['metrics']['service_summary'] = nominal['service_summary']

    def camshaft_disconnected(mutant: dict[str, Any]) -> None:
        mutant['static_audit']['speed_drives_camshaft'] = False

    def scenario_inputs_ignored(mutant: dict[str, Any]) -> None:
        rows = scenario_map(mutant)
        nominal_metrics = copy.deepcopy(rows['nominal']['metrics'])
        for scenario_id, row in rows.items():
            if scenario_id != 'nominal':
                row['metrics'] = copy.deepcopy(nominal_metrics)

    def lift_pump_bypassed(mutant: dict[str, Any]) -> None:
        mutant['static_audit']['lift_pump_is_physically_connected'] = False
    cases.extend([('missing_required_output', 0.0, missing_output), ('fewer_than_four_physical_pumps', 0.0, fewer_pumps), ('duplicated_or_prescribed_flow_traces', 55.0, duplicated_traces), ('incorrect_firing_order', 55.0, wrong_order), ('fuel_control_ignored', 70.0, fuel_control_ignored), ('camshaft_disconnected', 0.0, camshaft_disconnected), ('scenario_inputs_ignored', 65.0, scenario_inputs_ignored), ('lift_pump_bypassed', 0.0, lift_pump_bypassed)])
    rows: list[dict[str, Any]] = []
    for name, maximum_allowed, mutation in cases:
        mutant = copy.deepcopy(evidence)
        mutation(mutant)
        result = score(mutant)
        observed = float(result['score_raw'])
        rows.append({'id': name, 'score_raw': observed, 'maximum_allowed': maximum_allowed, 'passed': observed <= maximum_allowed + 1e-09})
    return {'schema': 'simuverity.f90-xfluid10-shortcut-sanity.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'case_count': len(rows), 'passed_count': sum((bool(row['passed']) for row in rows)), 'all_passed': all((bool(row['passed']) for row in rows)), 'cases': rows}

def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    temporary.replace(path)

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--sanity-output', type=Path)
    return parser.parse_args()

def main() -> int:
    args = parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    refreshed = refresh_metrics_from_complete_raw(evidence, args.evidence)
    result = score(evidence)
    result['offline_raw_metric_refresh'] = {'scenario_count': refreshed, 'method': 'complete pulse episodes excluding 2 ms analysis-window boundaries', 'simulation_restarted': False}
    sanity = run_shortcut_sanity(evidence)
    if args.output:
        write_json(args.output, result)
    if args.sanity_output:
        write_json(args.sanity_output, sanity)
    if not args.output:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    if not args.sanity_output:
        print(json.dumps(sanity, indent=2, ensure_ascii=False))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
