"""Pure offline scorer for fixed F90-XBATT-04 evidence."""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from statistics import median
from typing import Any
TASK_ID = 'F90-XBATT-04'
POLICY_ID = "simuverity-101-v1:f90-xbatt-04:scoring"
REQUIRED = ['nominal', 'cold_charge', 'warm_cycle', 'higher_charge_rate', 'lower_upper_cutoff', 'raised_lower_cutoff', 'moderate_cold_rate']
WEIGHTS = {'A': 0.1, 'Q': 0.05, 'M': 0.5, 'R': 0.1, 'D': 0.25}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan

def rms(values: list[float]) -> float:
    return math.sqrt(mean([value * value for value in values]))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return (zero - value) / (zero - full)

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return (value - zero) / (full - zero)

def weighted(parts: dict[str, tuple[float, float]]) -> float:
    denominator = sum((weight for _, weight in parts.values()))
    if denominator <= 0:
        return 0.0
    return sum((clamp(score) * weight for score, weight in parts.values())) / denominator

def geometric(groups: dict[str, float]) -> float:
    if any((groups[name] <= 0 for name in WEIGHTS)):
        return 0.0
    return math.exp(sum((WEIGHTS[name] * math.log(groups[name]) for name in WEIGHTS)))

def columns(rows: list[list[float]]) -> list[list[float]]:
    return [list(map(float, column)) for column in zip(*rows)]

def quantile(values: list[float], fraction: float) -> float:
    if not values:
        return math.nan
    ordered = sorted(values)
    index = fraction * (len(ordered) - 1)
    lower_index = int(math.floor(index))
    upper_index = int(math.ceil(index))
    if lower_index == upper_index:
        return ordered[lower_index]
    mix = index - lower_index
    return ordered[lower_index] * (1 - mix) + ordered[upper_index] * mix

def monotonic_violation(values: list[float], direction: str) -> float:
    scale = max(max(map(abs, values)), 1e-12)
    tolerance = 1e-08 * scale
    changes = [values[i] - values[i - 1] for i in range(1, len(values))]
    if direction == 'nondecreasing':
        return mean([change < -tolerance for change in changes])
    return mean([change > tolerance for change in changes])

def row_metrics(row: dict[str, Any]) -> dict[str, float]:
    outputs = row['outputs']
    requested = row['requested_inputs']
    time = list(map(float, outputs['time_s']))
    voltage, current, temperature, cycles = columns(outputs['electrical_state'])
    soc, positive, ocv, negative = columns(outputs['electrochemical_state'])
    film, porosity, soh, sei_loss, plating_loss = columns(outputs['ageing_state'])
    vmax = float(requested['Vmax'])
    vmin = float(requested['Vmin'])
    ic = float(requested['Ic'])
    discharge = float(requested['Id'])
    positive_phase = [i for i, value in enumerate(current) if value > 0.15]
    negative_phase = [i for i, value in enumerate(current) if value < -0.15]
    rest_phase = [i for i, value in enumerate(current) if abs(value) <= 0.1]
    cc_charge = [current[i] for i in positive_phase if voltage[i] <= vmax - 0.03]
    cc_discharge = [current[i] for i in negative_phase if voltage[i] >= vmin + 0.03]
    cv_current = [current[i] for i in positive_phase if abs(voltage[i] - vmax) <= 0.015]
    cycle_events = []
    prior = cycles[0]
    for index, value in enumerate(cycles[1:], 1):
        if value >= prior + 0.5:
            cycle_events.append(time[index])
        prior = value
    cycle_durations = [cycle_events[i] - cycle_events[i - 1] for i in range(1, len(cycle_events))]
    duration_cv = math.nan if len(cycle_durations) < 3 or mean(cycle_durations) == 0 else math.sqrt(mean([(value - mean(cycle_durations)) ** 2 for value in cycle_durations])) / mean(cycle_durations)
    return {'completed_cycles': max(cycles), 'duration_s': time[-1] - time[0], 'voltage_min_V': min(voltage), 'voltage_max_V': max(voltage), 'upper_cutoff_error_V': abs(max(voltage) - vmax), 'lower_cutoff_error_V': abs(min(voltage) - vmin), 'cc_charge_current_A': median(cc_charge) if cc_charge else math.nan, 'cc_discharge_current_A': median(cc_discharge) if cc_discharge else math.nan, 'charge_current_relative_error': abs(median(cc_charge) - ic) / max(abs(ic), 1e-09) if cc_charge else math.inf, 'discharge_current_relative_error': abs(median(cc_discharge) - discharge) / max(abs(discharge), 1e-09) if cc_discharge else math.inf, 'cv_current_taper_A': quantile(cv_current, 0.9) - quantile(cv_current, 0.1) if len(cv_current) >= 3 else 0.0, 'positive_phase_fraction': len(positive_phase) / len(time), 'negative_phase_fraction': len(negative_phase) / len(time), 'rest_phase_fraction': len(rest_phase) / len(time), 'surface_soc_min': min(soc), 'surface_soc_max': max(soc), 'temperature_min_K': min(temperature), 'temperature_max_K': max(temperature), 'temperature_rise_K': max(temperature) - float(requested['ambient_temperature_K']), 'potential_identity_rmse_V': rms([voltage[i] - (positive[i] - negative[i]) for i in range(len(time))]), 'soh_identity_rmse': rms([soh[i] - (1.0 - sei_loss[i] - plating_loss[i]) for i in range(len(time))]), 'film_growth_um': film[-1] - film[0], 'porosity_loss': porosity[0] - porosity[-1], 'soh_loss': soh[0] - soh[-1], 'sei_loss_final': sei_loss[-1], 'plating_loss_final': plating_loss[-1], 'film_monotonic_violation': monotonic_violation(film, 'nondecreasing'), 'porosity_monotonic_violation': monotonic_violation(porosity, 'nonincreasing'), 'soh_monotonic_violation': monotonic_violation(soh, 'nonincreasing'), 'minimum_soh': min(soh), 'minimum_porosity': min(porosity), 'cycle_duration_cv': duration_cv, 'cycle_event_count': float(len(cycle_events))}

def score(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    required_outputs = {'time_s', 'electrical_state', 'electrochemical_state', 'ageing_state'}
    scenarios_valid = all((name in rows and bool(rows[name].get('valid')) and (required_outputs <= set(rows[name].get('outputs', {}))) for name in REQUIRED))
    qualification = {'load': bool(evidence.get('load_pass')), 'update': bool(evidence.get('update_pass')), 'compile': bool(evidence.get('compile_pass')), 'nominal_smoke': bool(evidence.get('nominal_smoke_pass')), 'exact_scenario_set': set(rows) == set(REQUIRED), 'all_scenarios_valid': scenarios_valid, 'connected_dynamic_candidate_path': bool(static.get('core_path_qualified'))}
    gate = all(qualification.values())
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, {}, qualification, [name for name, passed in qualification.items() if not passed])
    metrics = {name: row_metrics(rows[name]) for name in REQUIRED}
    nominal = metrics['nominal']
    nominal_cycles = float(rows['nominal']['requested_inputs']['number_of_cycles'])
    a_parts = {'cycle_completion': (high(nominal['completed_cycles'], nominal_cycles - 1.0, nominal_cycles), 0.15), 'upper_voltage_cutoff': (low(nominal['upper_cutoff_error_V'], 0.03, 0.15), 0.15), 'lower_voltage_cutoff': (low(nominal['lower_cutoff_error_V'], 0.05, 0.2), 0.15), 'cc_charge_current': (low(nominal['charge_current_relative_error'], 0.05, 0.25), 0.15), 'cc_discharge_current': (low(nominal['discharge_current_relative_error'], 0.05, 0.25), 0.15), 'cv_current_taper': (high(nominal['cv_current_taper_A'], 0.15, 0.75), 0.15), 'all_five_phases': (min(high(nominal['positive_phase_fraction'], 0.01, 0.05), high(nominal['negative_phase_fraction'], 0.01, 0.05), high(nominal['rest_phase_fraction'], 0.01, 0.05)), 0.1)}
    group_a = weighted(a_parts)
    q_parts = {'terminal_potential_identity': (low(nominal['potential_identity_rmse_V'], 0.02, 0.1), 0.2), 'soh_decomposition_identity': (low(nominal['soh_identity_rmse'], 1e-06, 0.001), 0.2), 'film_growth_direction': (low(nominal['film_monotonic_violation'], 0.005, 0.1), 0.1), 'porosity_loss_direction': (low(nominal['porosity_monotonic_violation'], 0.005, 0.1), 0.1), 'soh_loss_direction': (low(nominal['soh_monotonic_violation'], 0.005, 0.1), 0.1), 'finite_soc': (min(high(nominal['surface_soc_min'], -0.1, -0.02), low(nominal['surface_soc_max'], 1.02, 1.1)), 0.1), 'finite_temperature': (min(high(nominal['temperature_min_K'], 250.0, 270.0), low(nominal['temperature_max_K'], 340.0, 380.0)), 0.1), 'both_ageing_paths_active': (min(high(nominal['sei_loss_final'], 1e-10, 1e-06), high(nominal['plating_loss_final'], 1e-10, 1e-06)), 0.1)}
    group_q = weighted(q_parts)
    cold = metrics['cold_charge']
    warm = metrics['warm_cycle']
    rate = metrics['higher_charge_rate']
    upper = metrics['lower_upper_cutoff']
    lower = metrics['raised_lower_cutoff']
    combined = metrics['moderate_cold_rate']
    duration_scale = max(nominal['duration_s'], 1.0)
    nominal_plating = max(abs(nominal['plating_loss_final']), 1e-12)
    nominal_sei = max(abs(nominal['sei_loss_final']), 1e-12)
    m_utilities = {'thermal_dynamics_present': high(nominal['temperature_rise_K'], 5.0, 12.0), 'cold_plating_response': high((cold['plating_loss_final'] - nominal['plating_loss_final']) / nominal_plating, 0.01, 0.03), 'warm_sei_response': high((warm['sei_loss_final'] - nominal['sei_loss_final']) / nominal_sei, 0.02, 0.08), 'charge_rate_response': high(max(abs(rate['temperature_max_K'] - nominal['temperature_max_K']), 1000.0 * abs(rate['soh_loss'] - nominal['soh_loss'])), 0.01, 0.5), 'upper_cutoff_response': high((nominal['duration_s'] - upper['duration_s']) / duration_scale, 0.01, 0.05), 'lower_cutoff_response': high((nominal['duration_s'] - lower['duration_s']) / duration_scale, 0.002, 0.01), 'combined_response': high(max(abs(combined['temperature_max_K'] - nominal['temperature_max_K']), 1000.0 * abs(combined['soh_loss'] - nominal['soh_loss'])), 0.01, 0.5)}
    m_parts = {name: (value, 1.0) for name, value in m_utilities.items()}
    m_mean = mean(list(m_utilities.values()))
    m_bottleneck = min(m_utilities.values())
    group_m = 0.3 * m_mean + 0.7 * m_bottleneck
    r_by_scenario: dict[str, float] = {}
    d_by_scenario: dict[str, float] = {}
    d_parts_by_scenario: dict[str, dict[str, tuple[float, float]]] = {}
    for name, values in metrics.items():
        expected = float(rows[name]['requested_inputs']['number_of_cycles'])
        r_by_scenario[name] = weighted({'completion': (high(values['completed_cycles'], expected - 1.0, expected), 0.25), 'soc_bounds': (min(high(values['surface_soc_min'], -0.1, -0.02), low(values['surface_soc_max'], 1.02, 1.1)), 0.2), 'temperature_bounds': (min(high(values['temperature_min_K'], 250.0, 270.0), low(values['temperature_max_K'], 350.0, 390.0)), 0.2), 'minimum_soh': (high(values['minimum_soh'], 0.7, 0.9), 0.2), 'minimum_porosity': (high(values['minimum_porosity'], 0.1, 0.2), 0.15)})
        requested_charge_current = abs(float(rows[name]['requested_inputs']['Ic']))
        d_parts_by_scenario[name] = {'cycle_events': (high(values['cycle_event_count'], expected - 2.0, expected - 1.0), 0.15), 'repeatability': (low(values['cycle_duration_cv'], 0.01, 0.06), 0.45), 'cv_taper': (high(values['cv_current_taper_A'] / max(requested_charge_current, 1e-12), 0.15, 0.5), 0.3), 'phase_coverage': (min(high(values['positive_phase_fraction'], 0.01, 0.05), high(values['negative_phase_fraction'], 0.01, 0.05), high(values['rest_phase_fraction'], 0.01, 0.05)), 0.1)}
        d_by_scenario[name] = weighted(d_parts_by_scenario[name])
    group_r = min(r_by_scenario.values())
    group_d = min(d_by_scenario.values())
    groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
    total = 100.0 * geometric(groups)
    diagnostics = {'A': a_parts, 'Q': q_parts, 'M': m_parts, 'M_aggregation': {'mean': m_mean, 'critical_bottleneck': m_bottleneck, 'mean_weight': 0.3, 'critical_bottleneck_weight': 0.7}, 'R_by_scenario': r_by_scenario, 'D_by_scenario': d_by_scenario, 'D_parts_by_scenario': d_parts_by_scenario}
    return receipt(evidence, groups, total, metrics, diagnostics, qualification, [])

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], diagnostics: dict[str, Any], qualification: dict[str, bool], failures: list[str]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xbatt04-score.v1', 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'policy_status': 'CURRENT', 'formula': 'G*100*A^0.10*Q^0.05*M^0.50*R^0.10*D^0.25', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85.0, 'G': groups.get('G') == 1.0, 'groups': groups, 'group_weights': WEIGHTS, 'score': total, 'admission_score_pass': groups.get('G') == 1.0 and total >= 85.0, 'qualification_checks': qualification, 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, float] = {}
    missing_core = copy.deepcopy(evidence)
    missing_core['static_audit']['core_path_qualified'] = False
    cases['missing_core'] = score(missing_core)['score']
    missing_output = copy.deepcopy(evidence)
    missing_output['scenarios'][0]['outputs'].pop('ageing_state', None)
    cases['missing_required_output'] = score(missing_output)['score']
    nonageing = copy.deepcopy(evidence)
    for row in nonageing['scenarios']:
        count = len(row['outputs']['time_s'])
        row['outputs']['ageing_state'] = [[0.005, 0.3, 1.0, 0.0, 0.0] for _ in range(count)]
    cases['nonageing_cell'] = score(nonageing)['score']
    copied_soh = copy.deepcopy(evidence)
    nominal = next((row for row in copied_soh['scenarios'] if row['id'] == 'nominal'))
    nominal_ageing = nominal['outputs']['ageing_state']
    for row in copied_soh['scenarios']:
        row['outputs']['ageing_state'] = copy.deepcopy(nominal_ageing)
    cases['copied_soh_across_inputs'] = score(copied_soh)['score']
    fixed_current = copy.deepcopy(evidence)
    for row in fixed_current['scenarios']:
        requested = row['requested_inputs']
        for sample in row['outputs']['electrical_state']:
            sample[1] = float(requested['Ic'])
    cases['fixed_current_without_cccv'] = score(fixed_current)['score']
    disconnected_thermal = copy.deepcopy(evidence)
    for row in disconnected_thermal['scenarios']:
        ambient = float(row['requested_inputs']['ambient_temperature_K'])
        for sample in row['outputs']['electrical_state']:
            sample[2] = ambient
    cases['disconnected_thermal_state'] = score(disconnected_thermal)['score']
    ignored_inputs = copy.deepcopy(evidence)
    nominal_outputs = next((row for row in ignored_inputs['scenarios'] if row['id'] == 'nominal'))['outputs']
    for row in ignored_inputs['scenarios']:
        if row['id'] != 'nominal':
            row['outputs'] = copy.deepcopy(nominal_outputs)
    cases['ignored_scenario_inputs'] = score(ignored_inputs)['score']
    return {'schema': 'simuverity.f90-xbatt04-shortcut-sanity.v1', 'task_id': TASK_ID, 'cases': cases, 'maximum_shortcut_score': max(cases.values()), 'pass': all((value < 85.0 for value in cases.values()))}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    output = args.out or args.evidence.with_name('offline_score.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(score(evidence), indent=2, ensure_ascii=False), encoding='utf-8')
    if args.sanity_out:
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(json.dumps(shortcut_sanity(evidence), indent=2, ensure_ascii=False), encoding='utf-8')
    print(output)
if __name__ == '__main__':
    main()
