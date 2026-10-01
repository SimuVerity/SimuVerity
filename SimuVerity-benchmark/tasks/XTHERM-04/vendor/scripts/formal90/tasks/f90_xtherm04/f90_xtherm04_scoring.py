"""JSON-waveform compatible, implementation-neutral XTHERM-04 scorer.

The scorer derives offline metrics from complete JSON arrays or the declared
raw artifact, applies the engineering thresholds and weights, treats two
name-based static signatures as M
components (zero when unproved), and uses strict geometric aggregation with
no post-total cap.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from geometric_scoring_adapter import adapt_source_result, load_current
SOURCE = Path(__file__).with_name('f90_xtherm04_scoring_core.py')
METRICS = load_current(SOURCE, 'xtherm04_current_source_for')
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}
MAPPING = {'thermo-fluid causality': 'M', 'official condition realization': 'M/R', 'house dynamics': 'A/R/D', 'heat and power dynamics': 'Q/M', 'physical reversal': 'M/R'}

def _derive_json_rows(evidence: dict) -> None:
    step_s = 10.0
    for row in evidence.get('scenarios', []):
        existing = row.get('offline_metrics')
        if isinstance(existing, dict) and existing:
            continue
        outputs = row.get('outputs', {})
        time = np.asarray(outputs['time_s'], dtype=float).reshape(-1)
        thermal = np.asarray(outputs['thermal_state'], dtype=float)
        control = np.asarray(outputs['hvac_control'], dtype=float)
        heat = np.asarray(outputs['heat_flow_state'], dtype=float)
        power = np.asarray(outputs['power_cop_state'], dtype=float)
        refrigerant = np.asarray(outputs['refrigerant_state'], dtype=float)
        error = np.abs(thermal[:, 1] - thermal[:, 0])
        after_hour = time >= 3600.0
        active = (control[:, 2] > 0.05) & (power[:, 3] > 0.1)
        heating = active & (control[:, 0] > 0.8)
        cooling = active & (control[:, 0] < -0.8)
        stable_active = heating | cooling
        mode_cop: list[float] = []
        physical_consistency: list[float] = []
        energy_closure: list[float] = []
        for is_heating, mask in ((True, heating), (False, cooling)):
            if int(np.count_nonzero(mask)) < 10:
                continue
            cop = np.abs(heat[mask, 1]) / np.maximum(power[mask, 3], 1e-06)
            mode_cop.append(float(np.median(cop)))
            if is_heating:
                consistent = (refrigerant[mask, 4] > 0) & (refrigerant[mask, 5] < 0) & (refrigerant[mask, 0] > refrigerant[mask, 1]) & (heat[mask, 1] < 0)
            else:
                consistent = (refrigerant[mask, 4] > 0) & (refrigerant[mask, 5] > 0) & (refrigerant[mask, 1] > refrigerant[mask, 0]) & (heat[mask, 1] > 0)
            physical_consistency.append(float(np.mean(consistent)))
            closure = np.abs(np.abs(np.abs(heat[mask, 0]) - np.abs(heat[mask, 1])) - power[mask, 0]) / np.maximum(power[mask, 0], 0.2)
            energy_closure.extend(closure.tolist())
        valve_consistency = float(np.mean(np.abs(control[stable_active, 1] - control[stable_active, 0]) <= 0.2)) if np.any(stable_active) else 0.0
        significant_flow = active & (np.abs(refrigerant[:, 4]) > 0.005)
        flow_ratio_error = float(np.median(np.abs(np.abs(refrigerant[significant_flow, 5]) / np.maximum(np.abs(refrigerant[significant_flow, 4]), 1e-06) - 1.0))) if np.any(significant_flow) else 1.0
        initial_recovery = METRICS._first_sustained(time, error <= 1.0, 600.0, step_s)
        heat_indices = np.flatnonzero(control[:, 0] > 0.8)
        cool_indices = np.flatnonzero(control[:, 0] < -0.8)
        reversal_recovery = -1.0
        if heat_indices.size and cool_indices.size:
            reversal_index = max(int(heat_indices[0]), int(cool_indices[0]))
            relative = time[reversal_index:] - time[reversal_index]
            reversal_recovery = METRICS._first_sustained(relative, error[reversal_index:] <= 1.0, 600.0, step_s)
        requested = row['requested_inputs']
        derived = copy.deepcopy(row.get('metrics', {}))
        derived.update({'actual_setpoint_degC': float(np.median(thermal[:, 0])), 'actual_house_initial_degC': float(thermal[0, 1]), 'actual_ambient_initial_degC': float(thermal[0, 2]), 'actual_ambient_final_degC': float(thermal[-1, 2]), 'comfort_fraction_after_1h': float(np.mean(error[after_hour] <= 1.5)), 'p95_absolute_temperature_error_after_1h_degC': float(np.quantile(error[after_hour], 0.95)), 'final_absolute_temperature_error_degC': float(error[-1]), 'house_temperature_dynamic_range_degC': float(np.ptp(thermal[:, 1])), 'heating_active_fraction': float(np.mean(heating)), 'cooling_active_fraction': float(np.mean(cooling)), 'compressor_command_dynamic_range': float(np.ptp(control[:, 2])), 'compressor_command_power_abs_correlation': METRICS._correlation(control[active, 2], power[active, 0]), 'mode_valve_consistency_fraction': valve_consistency, 'mode_flow_pressure_heat_consistency_fraction': min(physical_consistency) if physical_consistency else 0.0, 'worst_mode_median_cop': min(mode_cop) if mode_cop else 0.0, 'energy_closure_p90_relative': float(np.quantile(energy_closure, 0.9)) if energy_closure else 1.0, 'compressor_exv_mass_flow_ratio_error': flow_ratio_error, 'maximum_refrigerant_pressure_mpa': float(np.max(refrigerant[:, :2])), 'minimum_refrigerant_pressure_mpa': float(np.min(refrigerant[:, :2])), 'median_active_pressure_separation_mpa': float(np.median(np.abs(refrigerant[stable_active, 0] - refrigerant[stable_active, 1]))) if np.any(stable_active) else 0.0, 'compressor_power_dynamic_range_kw': float(np.ptp(power[:, 0])), 'indoor_heat_flow_dynamic_range_kw': float(np.ptp(heat[:, 1])), 'median_active_compressor_command': float(np.median(control[active, 2])) if np.any(active) else 0.0, 'initial_recovery_time_s': initial_recovery, 'mode_reversal_recovery_time_s': reversal_recovery, 'mode_reversal_present': bool(heat_indices.size and cool_indices.size), 'finite_fraction': float(np.mean(np.isfinite(np.column_stack([thermal, control, heat, power, refrigerant])))), 'requested_T_set_degC': float(requested['T_set_degC']), 'requested_T_house_init_degC': float(requested['T_house_init_degC']), 'requested_T_ambient_cold_degC': float(requested['T_ambient_cold_degC']), 'requested_T_ambient_hot_degC': float(requested['T_ambient_hot_degC']), 'offline_derivation_method': 'f90-xtherm04-json-uniform-time'})
        row['offline_metrics'] = derived
    evidence['offline_derivation'] = {'method': 'f90-xtherm04-json-uniform-time', 'source': 'complete score-free JSON waveforms', 'uniform_time_step_s': step_s, 'steady_evaluation_start_s': 3600.0}

def score_evidence(evidence: dict) -> dict:
    prepared = copy.deepcopy(evidence)
    rows = prepared.get('scenarios', [])
    if rows and all((isinstance(row.get('offline_metrics'), dict) and row.get('offline_metrics') for row in rows)):
        pass
    elif rows and all((isinstance(row.get('outputs'), dict) and row.get('outputs', {}).get('time_s') for row in rows)):
        _derive_json_rows(prepared)
    else:
        raw = Path(str(prepared.get('raw_artifact', {}).get('path', '')))
        if not raw.is_file():
            raise ValueError('neither complete JSON waveforms nor the pinned raw artifact are available')
        METRICS.attach_offline_derivations(prepared, raw)
    original_static = dict(prepared.get('static_audit', {}))
    prepared.setdefault('static_audit', {})['thermo_fluid_path_signature'] = True
    prepared['static_audit']['closed_loop_temperature_signature'] = True
    source = METRICS.score(prepared)
    if source.get('G') != 1.0:
        return adapt_source_result(source, schema='simuverity.f90-xtherm04-score.v1', policy_id='simuverity-101-v1:f90-xtherm-04:scoring', weights=WEIGHTS, primary_total_key='score_raw', cap_conditions_already_represented_in_groups=MAPPING)
    parts = source['details']['M']['parts']
    parts['static_thermo_fluid_chain'] = (float(bool(original_static.get('thermo_fluid_path_signature'))), 0.15)
    parts['closed_loop_temperature_path'] = (float(bool(original_static.get('closed_loop_temperature_signature'))), 0.15)
    source['groups']['M'] = METRICS.weighted_mean(parts)
    result = adapt_source_result(source, schema='simuverity.f90-xtherm04-score.v1', policy_id='simuverity-101-v1:f90-xtherm-04:scoring', weights=WEIGHTS, primary_total_key='score_raw', cap_conditions_already_represented_in_groups=MAPPING)
    result['observed_static_audit'] = original_static
    result['qualification_policy'] = {'G': 'load/update/compile and complete five-scenario output evidence', 'unproved_static_signatures': 'zero only their M components'}
    return result

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('output', nargs='?', type=Path)
    parser.add_argument('--out', dest='output_flag', type=Path)
    parser.add_argument('--output', dest='output_long', type=Path)
    args = parser.parse_args()
    output = args.output_long or args.output_flag or args.output
    result = score_evidence(json.loads(args.evidence.read_text(encoding='utf-8-sig')))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + '\n'
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding='utf-8')
    else:
        print(text, end='')
if __name__ == '__main__':
    main()
