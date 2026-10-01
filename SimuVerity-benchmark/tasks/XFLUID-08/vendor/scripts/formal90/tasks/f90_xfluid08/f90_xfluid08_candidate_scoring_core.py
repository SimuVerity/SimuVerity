"""Candidate-compatible offline entry for F90-XFLUID-08.

Candidate extraction already derives the current scorer's metric dictionary
from complete task-specific public matrices. This entry derives candidate
qualification from those public multi-scenario dynamics, then invokes the
unchanged score and shortcut-sanity functions without requiring the
direct-reference MAT-v7.3 aggregate.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import math
from pathlib import Path
from typing import Any
import numpy as np
REQUIRED_IDS = {'native_profile_1_nominal_inventory', 'native_profile_2_nominal_inventory', 'native_profile_3_nominal_inventory', 'native_profile_2_low_inventory', 'native_profile_3_high_inventory'}

def _load_current():
    path = Path(__file__).with_name('f90_xfluid08_scoring_core.py')
    spec = importlib.util.spec_from_file_location('f90_xfluid08_current', path)
    if spec is None or spec.loader is None:
        raise RuntimeError('could not load current XFLUID08 scorer')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def _vector(value: Any) -> list[float]:
    return [float(item) for item in value] if isinstance(value, list) else [float(value)]

def _metrics(row: dict[str, Any]) -> dict[str, Any]:
    return row.get('offline_metrics', row['metrics'])

def _behavioral_signatures(evidence: dict[str, Any]) -> dict[str, Any]:
    """Derive qualification from public multi-scenario dynamics, not names."""
    rows = {str(row['id']): row for row in evidence.get('scenarios', [])}
    result: dict[str, Any] = {'causal_fuel_path': False, 'redundant_transfer_path': False, 'closed_loop_pump_speed': False, 'active_transfer_branch_count': 0, 'closed_loop_branch_count': 0, 'maximum_inventory_evolution_m3': 0.0}
    if set(rows) != REQUIRED_IDS or not all((bool(rows[key].get('valid')) for key in REQUIRED_IDS)):
        return result
    metrics = [_metrics(rows[key]) for key in sorted(REQUIRED_IDS)]
    branch_flow = [0.0] * 4
    branch_pressure = [0.0] * 4
    branch_shaft = [0.0] * 4
    branch_hydraulic = [0.0] * 4
    branch_speed_range = [0.0] * 4
    branch_correlation = [0.0] * 4
    inventory_evolution = 0.0
    feed = 0.0
    for metric in metrics:
        for target, key in ((branch_flow, 'pump_mass_flow_kg_s_late'), (branch_pressure, 'pump_pressure_rise_mpa_late'), (branch_shaft, 'pump_shaft_power_w_late'), (branch_hydraulic, 'pump_hydraulic_power_w_late'), (branch_speed_range, 'pump_measured_speed_range_rpm'), (branch_correlation, 'pump_command_speed_abs_correlation')):
            values = _vector(metric[key])
            for index in range(4):
                target[index] = max(target[index], abs(values[index]))
        inventory_evolution = max(inventory_evolution, *(abs(float(metric[f'{tank}_volume_end_m3']) - float(metric[f'{tank}_volume_start_m3'])) for tank in ('left', 'center', 'right')))
        feed = max(feed, abs(float(metric['engine_feed_mass_flow_kg_s_late'])))
    active = [branch_flow[index] > 0.0001 and branch_pressure[index] > 0.005 and (branch_shaft[index] > 1.0) and (branch_hydraulic[index] > 1.0) for index in range(4)]
    closed_loop = [branch_speed_range[index] > 300.0 and branch_correlation[index] > 0.2 for index in range(4)]
    active_count = sum(active)
    closed_loop_count = sum(closed_loop)
    result.update({'causal_fuel_path': bool(active_count >= 1 and feed > 0.05 and (inventory_evolution > 0.05)), 'redundant_transfer_path': active_count == 4, 'closed_loop_pump_speed': closed_loop_count == 4, 'active_transfer_branch_count': active_count, 'closed_loop_branch_count': closed_loop_count, 'maximum_inventory_evolution_m3': inventory_evolution})
    return result

def _prepare_candidate_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    behavior = _behavioral_signatures(evidence)
    audit = evidence.setdefault('static_audit', {})
    audit.update({'qualification_basis': 'public_multiscenario_behavior', 'causal_fuel_path_signature': behavior['causal_fuel_path'], 'redundant_transfer_signature': behavior['redundant_transfer_path'], 'closed_loop_pump_speed_signature': behavior['closed_loop_pump_speed'], 'behavioral_witnesses': behavior})
    return behavior

def _attach_transition_metric_compatibility(evidence: dict[str, Any], current: Any) -> dict[str, Any]:
    """Derive omitted current metrics from already-complete public waveforms."""
    derived_rows: list[dict[str, Any]] = []
    for row in evidence.get('scenarios', []):
        metric = _metrics(row)
        required = {'maximum_command_transition_settling_time_s', 'command_transition_settling_event_count'}
        if required.issubset(metric):
            continue
        outputs = row.get('outputs', {})
        if not isinstance(outputs, dict):
            raise ValueError('candidate evidence lacks complete public outputs')
        time = np.asarray(outputs.get('time_s'), dtype=float).reshape(-1)
        speed = np.asarray(outputs.get('pump_speed_state'), dtype=float)
        grid = np.arange(math.ceil(float(time[0])), math.floor(float(time[-1])) + 1.0, 1.0)
        if grid.size < 5:
            raise ValueError('complete public output interval is too short')
        transition_times: list[float] = []
        for column in range(4):
            command = np.interp(grid, time, speed[:, 2 * column])
            measured = np.interp(grid, time, speed[:, 2 * column + 1])
            transition_times.extend(current._settling_times(grid, command, measured))
        maximum = max(transition_times) if transition_times else -1.0
        metric.setdefault('maximum_command_transition_settling_time_s', maximum)
        metric.setdefault('command_transition_settling_event_count', len(transition_times))
        derived_rows.append({'scenario_id': str(row.get('id', '')), 'settled_transition_count': len(transition_times), 'maximum_settling_time_s': maximum})
    return {'schema': 'simuverity.f90-xfluid08-candidate-metric-compat.v1', 'method': 'current 1 s settling derivation over complete pump_speed_state', 'source': 'complete public outputs.time_s and outputs.pump_speed_state', 'derived_fields': ['command_transition_settling_event_count', 'maximum_command_transition_settling_time_s'], 'derived_rows': derived_rows, 'simulation_restarted': False}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--sanity-out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    if not all((isinstance(row.get('offline_metrics'), dict) for row in evidence.get('scenarios', []))):
        raise ValueError('candidate evidence lacks task-specific offline metrics')
    current = _load_current()
    transition_compatibility = _attach_transition_metric_compatibility(evidence, current)
    behavior = _prepare_candidate_evidence(evidence)
    result = current.score(evidence)
    result['qualification_witnesses'] = behavior
    result['candidate_metric_compatibility'] = transition_compatibility
    text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    if args.sanity_out:
        sanity = current.run_shortcut_sanity(evidence)
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(json.dumps(sanity, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(text)
if __name__ == '__main__':
    main()
