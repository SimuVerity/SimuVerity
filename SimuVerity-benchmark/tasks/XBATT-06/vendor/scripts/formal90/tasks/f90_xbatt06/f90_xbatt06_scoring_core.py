"""Pure-offline scorer for F90-XBATT-06 complete JSON evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from statistics import fmean
from typing import Any, Iterable
TASK_ID = 'F90-XBATT-06'
POLICY_ID = "simuverity-101-v1:f90-xbatt-06:scoring"
REQUIRED_SCENARIOS = ['nominal_long_flight', 'cold_short_high_pulse', 'hot_high_rms_flight', 'moderate_profile_high_forecast', 'aged_capacity_long_flight']
GROUP_WEIGHTS = {'A': 0.3, 'Q': 0.1, 'M': 0.25, 'C': 0.1, 'R': 0.15, 'D': 0.1}
EXPECTED_SAMPLES = 2001

def clamp(value: float, low: float=0.0, high: float=100.0) -> float:
    return max(low, min(high, float(value)))

def low_is_good(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if value <= full:
        return 100.0
    if value >= zero:
        return 0.0
    return 100.0 * (zero - value) / (zero - full)

def high_is_good(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if value >= full:
        return 100.0
    if value <= zero:
        return 0.0
    return 100.0 * (value - zero) / (full - zero)

def weighted_mean(parts: Iterable[tuple[float, float]]) -> float:
    pairs = list(parts)
    denominator = sum((weight for _, weight in pairs))
    return 0.0 if denominator <= 0 else sum((value * weight for value, weight in pairs)) / denominator

def weighted_geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in GROUP_WEIGHTS)):
        return 0.0
    return math.exp(sum((GROUP_WEIGHTS[name] * math.log(groups[name] / 100.0) for name in GROUP_WEIGHTS))) * 100.0

def rmse(left: list[float], right: list[float]) -> float:
    if len(left) != len(right) or not left:
        return math.inf
    return math.sqrt(fmean(((float(a) - float(b)) ** 2 for a, b in zip(left, right))))

def max_abs(values: Iterable[float]) -> float:
    items = [abs(float(value)) for value in values]
    return max(items, default=math.inf)

def correlation(left: list[float], right: list[float]) -> float:
    if len(left) != len(right) or len(left) < 2:
        return 0.0
    mean_left, mean_right = (fmean(left), fmean(right))
    numerator = sum(((a - mean_left) * (b - mean_right) for a, b in zip(left, right)))
    left_energy = sum(((a - mean_left) ** 2 for a in left))
    right_energy = sum(((b - mean_right) ** 2 for b in right))
    denominator = math.sqrt(left_energy * right_energy)
    return 0.0 if denominator <= 0 else numerator / denominator

def is_finite_matrix(value: Any, columns: int | None=None) -> bool:
    if not isinstance(value, list) or not value:
        return False
    for row in value:
        if columns is None:
            row = [row]
        elif not isinstance(row, list) or len(row) != columns:
            return False
        try:
            if not all((math.isfinite(float(item)) for item in row)):
                return False
        except (TypeError, ValueError):
            return False
    return True

def output_representation(outputs: dict[str, Any]) -> str:
    core = {name: outputs.get(name) for name in ('battery_input', 'electrical_state', 'identified_3rc', 'rul_state')}
    return json.dumps(core, sort_keys=True, separators=(',', ':'), allow_nan=False)

def scenario_metrics(scenario: dict[str, Any]) -> dict[str, Any]:
    outputs = scenario.get('outputs', {})
    requested = scenario.get('requested_inputs', {})
    time = outputs.get('time_s', [])
    battery = outputs.get('battery_input', [])
    experimental = outputs.get('experimental_voltage_V', [])
    electrical = outputs.get('electrical_state', [])
    identified = outputs.get('identified_3rc', [])
    rul = outputs.get('rul_state', [])
    lengths = [len(value) if isinstance(value, list) else -1 for value in (time, battery, experimental, electrical, identified, rul)]
    containers_valid = lengths == [EXPECTED_SAMPLES] * 6 and is_finite_matrix(time) and is_finite_matrix(battery, 2) and is_finite_matrix(experimental) and is_finite_matrix(electrical, 4) and is_finite_matrix(identified, 8) and is_finite_matrix(rul, 4) and all((float(time[index + 1]) > float(time[index]) for index in range(len(time) - 1)))
    if not containers_valid:
        return {'containers_valid': False, 'sample_counts': lengths, 'accuracy_score': 0.0, 'quality_score': 0.0, 'dynamic_score': 0.0}
    terminal_voltage = [float(row[0]) for row in electrical]
    estimated_voltage = [float(row[1]) for row in electrical]
    plant_soc = [float(row[2]) for row in electrical]
    estimated_soc = [float(row[3]) for row in electrical]
    current = [float(row[0]) for row in battery]
    temperature = [float(row[1]) for row in battery]
    capacity = [float(row[7]) for row in identified]
    consumed = [float(row[0]) for row in rul]
    remaining = [float(row[1]) for row in rul]
    predicted_rul = [float(row[2]) for row in rul]
    safety_margin = [float(row[3]) for row in rul]
    available = float(requested.get('available_capacity_Ah', math.nan))
    deficit = float(requested.get('initial_charge_deficit_Ah', math.nan))
    forecast = float(requested.get('forecast_discharge_current_A', math.nan))
    reserve = float(requested.get('reserve_capacity_Ah', math.nan))
    landing = float(requested.get('required_landing_time_s', math.nan))
    experimental_rmse = rmse(estimated_voltage, [float(v) for v in experimental])
    plant_estimator_rmse = rmse(terminal_voltage, estimated_voltage)
    soc_rmse = rmse(plant_soc, estimated_soc)
    capacity_max_error = max_abs((value - available for value in capacity))
    expected_remaining = [max(available - deficit - value, 0.0) for value in consumed]
    remaining_identity_error = max_abs((a - b for a, b in zip(remaining, expected_remaining)))
    expected_rul = [max(value - reserve, 0.0) * 3600.0 / forecast for value in remaining]
    rul_identity_error = max_abs((a - b for a, b in zip(predicted_rul, expected_rul)))
    expected_safety = [value - landing for value in predicted_rul]
    safety_identity_error = max_abs((a - b for a, b in zip(safety_margin, expected_safety)))
    positive_parameter_fraction = fmean((1.0 if float(value) > 0 else 0.0 for row in identified for value in row[:7]))
    taus = []
    for row in identified:
        taus.extend((float(row[1]) * float(row[2]), float(row[3]) * float(row[4]), float(row[5]) * float(row[6])))
    positive_taus = [value for value in taus if value > 0 and math.isfinite(value)]
    tau_span = max(positive_taus) / min(positive_taus) if positive_taus else 0.0
    third_branch_present = all((float(row[5]) > 0 and float(row[6]) > 0 for row in identified))
    monotonic_violations = fmean((1.0 if predicted_rul[index + 1] > predicted_rul[index] + 1e-06 else 0.0 for index in range(len(predicted_rul) - 1)))
    voltage_span = max(estimated_voltage) - min(estimated_voltage)
    current_voltage_correlation = correlation(current, estimated_voltage)
    temperature_error = max_abs((value - float(requested.get('temperature_K', math.nan)) for value in temperature))
    physical_ranges = min(terminal_voltage + estimated_voltage) > 0.0 and max(terminal_voltage + estimated_voltage) < 100.0 and (min(plant_soc + estimated_soc) >= -0.02) and (max(plant_soc + estimated_soc) <= 1.05) and (min(current) >= -1e-06) and (max(current) <= 150.0) and (min(temperature) >= 250.0) and (max(temperature) <= 350.0) and (min(remaining) >= -1e-08) and (min(capacity) > 0.0)
    accuracy_score = weighted_mean([(low_is_good(experimental_rmse, 0.2, 1.0), 0.25), (low_is_good(plant_estimator_rmse, 0.1, 0.6), 0.2), (low_is_good(soc_rmse, 0.005, 0.08), 0.15), (low_is_good(capacity_max_error, 0.02, 0.5), 0.1), (low_is_good(remaining_identity_error, 0.002, 0.1), 0.1), (low_is_good(rul_identity_error, 0.25, 15.0), 0.1), (low_is_good(safety_identity_error, 0.25, 15.0), 0.1)])
    quality_score = 100.0 if physical_ranges else 0.0
    dynamic_score = weighted_mean([(high_is_good(voltage_span, 0.1, 1.0), 0.4), (high_is_good(-current_voltage_correlation, 0.0, 0.05), 0.25), (low_is_good(monotonic_violations, 0.001, 0.05), 0.25), (high_is_good(max(safety_margin) - min(safety_margin), 10.0, 100.0), 0.1)])
    return {'containers_valid': True, 'sample_counts': lengths, 'time_start_s': float(time[0]), 'time_end_s': float(time[-1]), 'experimental_voltage_rmse_V': experimental_rmse, 'plant_estimator_voltage_rmse_V': plant_estimator_rmse, 'soc_tracking_rmse': soc_rmse, 'capacity_max_abs_error_Ah': capacity_max_error, 'remaining_capacity_identity_max_abs_Ah': remaining_identity_error, 'rul_identity_max_abs_s': rul_identity_error, 'safety_identity_max_abs_s': safety_identity_error, 'parameter_positive_fraction': positive_parameter_fraction, 'tau_span_ratio': tau_span, 'third_rc_branch_present': third_branch_present, 'rul_monotonic_violation_fraction': monotonic_violations, 'voltage_dynamic_span_V': voltage_span, 'current_voltage_correlation': current_voltage_correlation, 'temperature_trace_max_abs_error_K': temperature_error, 'accuracy_score': clamp(accuracy_score), 'quality_score': clamp(quality_score), 'dynamic_score': clamp(dynamic_score)}

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    failures: list[str] = []
    scenarios = evidence.get('scenarios', [])
    ids = [scenario.get('id') for scenario in scenarios]
    exact_scenarios = len(scenarios) == len(REQUIRED_SCENARIOS) and ids == REQUIRED_SCENARIOS
    static = evidence.get('static_audit', {})
    per_scenario = {scenario.get('id', f'unnamed_{index}'): scenario_metrics(scenario) for index, scenario in enumerate(scenarios)}
    containers_valid = exact_scenarios and all((metrics.get('containers_valid', False) for metrics in per_scenario.values()))
    scenario_runtime_valid = exact_scenarios and all((scenario.get('valid') is True and scenario.get('simulation_pass') is True and (scenario.get('required_evidence_pass') is True) for scenario in scenarios))
    static_gate = all((static.get(name) is True for name in ('core_path_qualified', 'current_input_connected_to_plant_and_estimator', 'temperature_input_connected', 'four_native_outputs_present', 'identified_3rc_parameter_fields_present')))
    qualification_checks = {'task_id_matches': evidence.get('task_id') == TASK_ID, 'evidence_complete': evidence.get('evidence_complete') is True, 'load_pass': evidence.get('load_pass') is True, 'update_pass': evidence.get('update_pass') is True, 'compile_pass': evidence.get('compile_pass') is True, 'reference_substantive_modifications_zero': evidence.get('reference_substantive_modifications') == 0, 'required_scenarios_exact_and_ordered': exact_scenarios, 'all_scenarios_simulated_and_valid': scenario_runtime_valid, 'all_required_output_containers_valid': containers_valid, 'static_core_and_input_paths_qualified': static_gate}
    qualification = all(qualification_checks.values())
    failures.extend((name for name, passed in qualification_checks.items() if not passed))
    valid_metrics = list(per_scenario.values())
    if valid_metrics:
        group_a = fmean((float(metrics.get('accuracy_score', 0.0)) for metrics in valid_metrics))
        group_q = min((float(metrics.get('quality_score', 0.0)) for metrics in valid_metrics))
        positive_fraction = min((float(metrics.get('parameter_positive_fraction', 0.0)) for metrics in valid_metrics))
        tau_span = min((float(metrics.get('tau_span_ratio', 0.0)) for metrics in valid_metrics))
        voltage_span = min((float(metrics.get('voltage_dynamic_span_V', 0.0)) for metrics in valid_metrics))
        third_branch = all((metrics.get('third_rc_branch_present') is True for metrics in valid_metrics))
        group_m = weighted_mean([(100.0 if static.get('core_path_qualified') is True else 0.0, 0.4), (100.0 * positive_fraction, 0.25), (high_is_good(tau_span, 3.0, 20.0), 0.2), (100.0 if third_branch and voltage_span >= 0.5 else 0.0, 0.15)])
        representations = [output_representation(scenario.get('outputs', {})) for scenario in scenarios]
        unique_representations = len(set(representations))
        capacity_coupled = max((float(metrics.get('capacity_max_abs_error_Ah', math.inf)) for metrics in valid_metrics)) <= 0.02
        rul_coupled = max((float(metrics.get('rul_identity_max_abs_s', math.inf)) for metrics in valid_metrics)) <= 0.25
        temperature_values = {scenario.get('requested_inputs', {}).get('temperature_K') for scenario in scenarios}
        group_c = weighted_mean([(100.0 if static.get('current_input_connected_to_plant_and_estimator') is True and static.get('temperature_input_connected') is True else 0.0, 0.45), (high_is_good(unique_representations, 1.0, 4.0), 0.2), (100.0 if capacity_coupled else 0.0, 0.15), (100.0 if len(temperature_values) >= 3 else 0.0, 0.1), (100.0 if rul_coupled else 0.0, 0.1)])
        scenario_robustness = {scenario_id: weighted_mean([(float(metrics.get('accuracy_score', 0.0)), 0.75), (float(metrics.get('quality_score', 0.0)), 0.15), (100.0 if metrics.get('third_rc_branch_present') is True else 0.0, 0.1)]) for scenario_id, metrics in per_scenario.items()}
        group_r = min(scenario_robustness.values())
        group_d = min((float(metrics.get('dynamic_score', 0.0)) for metrics in valid_metrics))
    else:
        group_a = group_q = group_m = group_c = group_r = group_d = 0.0
        unique_representations = 0
        third_branch = capacity_coupled = rul_coupled = False
        scenario_robustness = {}
    groups = {name: clamp(value) for name, value in {'A': group_a, 'Q': group_q, 'M': group_m, 'C': group_c, 'R': group_r, 'D': group_d}.items()}
    total = weighted_geometric(groups) if qualification else 0.0
    shortcut_findings: list[str] = []
    if qualification and (not third_branch):
        shortcut_findings.append('missing_or_zero_third_rc_branch')
    if qualification and (not rul_coupled):
        shortcut_findings.append('fabricated_or_disconnected_rul_trace')
    if total < 85.0:
        failures.append('raw_score_below_admission_threshold')
    return {'schema': 'simuverity.f90-xbatt06-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'offline_only': True, 'qualification_gate_G': 1 if qualification else 0, 'qualification_checks': qualification_checks, 'raw_score': total, 'admission_threshold': 85.0, 'reference_pass': qualification and total >= 85.0, 'group_scores': groups, 'group_weights': GROUP_WEIGHTS, 'per_scenario_metrics': per_scenario, 'per_scenario_robustness': scenario_robustness, 'cross_scenario': {'third_rc_present_all_scenarios': third_branch, 'capacity_coupled_all_scenarios': capacity_coupled, 'rul_coupled_all_scenarios': rul_coupled}, 'shortcut_findings': shortcut_findings, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    mutations: list[tuple[str, dict[str, Any]]] = []
    missing_temperature = copy.deepcopy(evidence)
    missing_temperature['static_audit']['temperature_input_connected'] = False
    missing_temperature['static_audit']['core_path_qualified'] = False
    mutations.append(('missing_temperature_input_path', missing_temperature))
    missing_third = copy.deepcopy(evidence)
    for scenario in missing_third['scenarios']:
        for row in scenario['outputs']['identified_3rc']:
            row[5] = 0.0
            row[6] = 0.0
    mutations.append(('missing_third_rc_branch', missing_third))
    copied = copy.deepcopy(evidence)
    nominal_outputs = copy.deepcopy(copied['scenarios'][0]['outputs'])
    for scenario in copied['scenarios'][1:]:
        scenario['outputs'] = copy.deepcopy(nominal_outputs)
    mutations.append(('copied_nominal_outputs_across_scenarios', copied))
    disconnected_rul = copy.deepcopy(evidence)
    for scenario in disconnected_rul['scenarios']:
        for row in scenario['outputs']['rul_state']:
            row[2] = 1000.0
            row[3] = 1000.0
    mutations.append(('fabricated_or_disconnected_rul_trace', disconnected_rul))
    results = []
    for name, mutation in mutations:
        result = score_evidence(mutation)
        results.append({'mutation': name, 'qualification_gate_G': result['qualification_gate_G'], 'raw_score': result['raw_score'], 'shortcut_findings': result['shortcut_findings'], 'rejected_below_85': result['raw_score'] < 85.0})
    return {'schema': 'simuverity.f90-xbatt06-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_mutations_only': True, 'required_mutations': [name for name, _ in mutations], 'all_rejected_below_85': all((item['rejected_below_85'] for item in results)), 'results': results}

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--shortcut-sanity-output', type=Path)
    args = parser.parse_args()
    evidence_bytes = args.evidence.read_bytes()
    evidence = json.loads(evidence_bytes)
    result = score_evidence(evidence)
    result['evidence_path'] = str(args.evidence.resolve())
    write_json(args.output, result)
    if args.shortcut_sanity_output:
        sanity = shortcut_sanity(evidence)
        write_json(args.shortcut_sanity_output, sanity)
        if not sanity['all_rejected_below_85']:
            raise SystemExit('shortcut sanity contract failed')
    print(f"{TASK_ID} G={result['qualification_gate_G']} raw={result['raw_score']:.6f} pass={int(result['reference_pass'])}")
    return 0 if result['reference_pass'] else 2
if __name__ == '__main__':
    raise SystemExit(main())
