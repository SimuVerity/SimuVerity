"""Pure-offline current scorer for current F90-XMED-03 simulation evidence.

This module never opens a Simulink model and never invokes MATLAB.  It keeps
all current thresholds, weights, non-A/M groups, dynamics logic, and causal diagnostics,
while binding tracking accuracy to A and static architecture/mechanism to M.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable
TASK_ID = 'F90-XMED-03'
EVIDENCE_POLICY_ID = 'simuverity-101-v1:f90-xmed-03:scoring'
POLICY_ID = 'simuverity-101-v1:f90-xmed-03:scoring'
EVIDENCE_SCHEMA = 'simuverity.formal90-xmed03-normalized-evidence.v1'
SCORE_SCHEMA = 'simuverity.formal90-xmed03-offline-score.v1'
RAW_METRICS_SCHEMA = 'simuverity.formal90-xmed03-reference-metrics.v1'
STATIC_AUDIT_SCHEMA = 'simuverity.formal90-xmed03-static-audit.v1'
TASK_ROOT = Path(__file__).resolve().parents[5]
SCENARIOS_PATH = TASK_ROOT / 'official_scenarios.json'
EXPECTED_SCENARIOS = ('nominal_targets', 'compliance_mismatch', 'resistance_mismatch', 'divergent_target_step', 'rapid_low_compliance', 'slow_high_peep', 'crossed_mechanics', 'joint_boundary')
ROBUSTNESS_SCENARIOS = ('compliance_mismatch', 'resistance_mismatch', 'rapid_low_compliance', 'slow_high_peep', 'crossed_mechanics', 'joint_boundary')
STEP_SCENARIOS = ('divergent_target_step', 'rapid_low_compliance', 'slow_high_peep', 'crossed_mechanics', 'joint_boundary')
INPUT_FIELDS = ('target_tv1_initial_mL', 'target_tv1_final_mL', 'target_tv2_initial_mL', 'target_tv2_final_mL', 'target_step_time_s', 'patient1_resistance_cmH2O_per_Lps', 'patient2_resistance_cmH2O_per_Lps', 'patient1_compliance_L_per_cmH2O', 'patient2_compliance_L_per_cmH2O', 'respiratory_rate_bpm', 'peep_cmH2O', 'max_inspiratory_pressure_cmH2O')
PAIR_FIELDS = ('initial_tidal_volume_mL', 'final_tidal_volume_mL', 'initial_target_mL', 'final_target_mL', 'initial_relative_error', 'final_relative_error', 'pressure_peep_cmH2O', 'pressure_pip_cmH2O', 'pressure_max_cmH2O', 'flow_min_Lps', 'flow_max_Lps', 'command_initial_mean', 'command_final_mean', 'command_min', 'command_max')
MATRIX_FIELDS = ('breath_tidal_volume_mL', 'breath_command_mean')
STATIC_CHECKS = ('shared_physical_source', 'two_patient_resistive_mechanics', 'two_patient_compliance_mechanics', 'two_commanded_physical_branch_elements', 'two_measured_feedback_paths', 'physical_pressure_flow_volume_provenance', 'branch_command_output_present')
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.4, 'R': 0.15, 'D': 0.15}
TRACKING_KNOTS = (0.0, 0.03, 0.07, 0.12, 0.2, 0.35, 0.6)
TRACKING_VALUES = (1.0, 1.0, 0.97, 0.9, 0.72, 0.35, 0.0)

def read_json(path: str | Path) -> dict[str, Any]:
    with Path(path).open('r', encoding='utf-8') as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError('JSON root must be an object')
    return value

def write_json(path: str | Path, value: dict[str, Any]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('w', encoding='utf-8', newline='\n') as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False, allow_nan=False)
        handle.write('\n')

def finite(value: Any, default: float=math.nan) -> float:
    if isinstance(value, bool):
        return default
    try:
        converted = float(value)
    except (TypeError, ValueError):
        return default
    return converted if math.isfinite(converted) else default

def is_json_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def clamp(value: float) -> float:
    return min(max(float(value), 0.0), 1.0)

def quality_high(value: Any, good: float, bad: float) -> float:
    metric = finite(value)
    if not math.isfinite(metric):
        return 0.0
    if good <= bad:
        return float(metric >= good)
    return clamp((metric - bad) / (good - bad))

def quality_low(value: Any, good: float, bad: float) -> float:
    metric = finite(value)
    if not math.isfinite(metric):
        return 0.0
    if bad <= good:
        return float(metric <= good)
    return clamp((bad - metric) / (bad - good))

def weighted_mean(items: Iterable[tuple[float, float]]) -> float:
    pairs = list(items)
    denominator = sum((weight for _, weight in pairs))
    if denominator <= 0:
        return 0.0
    return sum((value * weight for value, weight in pairs)) / denominator

def piecewise(value: Any, knots: tuple[float, ...], values: tuple[float, ...]) -> float:
    metric = finite(value)
    if not math.isfinite(metric):
        return 0.0
    if metric <= knots[0]:
        return values[0]
    if metric >= knots[-1]:
        return values[-1]
    for index in range(1, len(knots)):
        if metric <= knots[index]:
            fraction = (metric - knots[index - 1]) / (knots[index] - knots[index - 1])
            return clamp(values[index - 1] + fraction * (values[index] - values[index - 1]))
    return 0.0

def tracking_utility(error: Any) -> float:
    return piecewise(error, TRACKING_KNOTS, TRACKING_VALUES)

def lower_error_utility(error: Any, full_until: float, zero_at: float) -> float:
    return quality_low(error, full_until, zero_at)

def upper_utility(value: Any, full_until: float, zero_at: float) -> float:
    return quality_low(value, full_until, zero_at)

def normalize_inputs(row: dict[str, Any]) -> dict[str, float]:
    result: dict[str, float] = {}
    for field in INPUT_FIELDS:
        raw_value = row.get(field)
        if not is_json_number(raw_value):
            raise ValueError(f'{field} must be finite numeric evidence')
        result[field] = float(raw_value)
    return result

def load_scenario_contract() -> tuple[dict[str, dict[str, float]], list[str]]:
    failures: list[str] = []
    if not SCENARIOS_PATH.is_file():
        return ({}, ['scenario contract is missing'])
    spec = read_json(SCENARIOS_PATH)
    scenarios = spec.get('scenarios')
    if not isinstance(scenarios, list):
        return ({}, failures + ['scenarios must be a JSON array'])
    records: dict[str, dict[str, float]] = {}
    for scenario in scenarios:
        if not isinstance(scenario, dict) or not isinstance(scenario.get('id'), str):
            failures.append('scenario identity is invalid')
            continue
        scenario_id = scenario['id']
        try:
            records[scenario_id] = normalize_inputs(scenario)
        except ValueError as exc:
            failures.append(f'{scenario_id}: {exc}')
    if tuple(records) != EXPECTED_SCENARIOS:
        failures.append('scenario IDs or order changed')
    return (records, failures)
OFFICIAL_INPUTS, SCENARIO_CONTRACT_FAILURES = load_scenario_contract()

def pair(value: Any) -> list[float] | None:
    if not isinstance(value, list) or len(value) != 2:
        return None
    if not all((is_json_number(item) for item in value)):
        return None
    return [float(item) for item in value]

def matrix(value: Any) -> list[list[float]] | None:
    if not isinstance(value, list) or not value:
        return None
    result: list[list[float]] = []
    for raw_row in value:
        converted = pair(raw_row)
        if converted is None:
            return None
        result.append(converted)
    return result

def row_map(rows: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get('id'), str):
            result.setdefault(row['id'], row)
    return result

def gate_evidence(evidence: dict[str, Any], rows: dict[str, dict[str, Any]]) -> tuple[bool, list[str]]:
    failures = list(SCENARIO_CONTRACT_FAILURES)
    if evidence.get('schema') != EVIDENCE_SCHEMA:
        failures.append('evidence schema mismatch')
    if evidence.get('task_id') != TASK_ID:
        failures.append('task_id mismatch')
    if evidence.get('policy_id') != EVIDENCE_POLICY_ID:
        failures.append('policy_id mismatch')
    if evidence.get('extraction_only') is not True:
        failures.append('extraction_only must be literal true')
    if evidence.get('contains_score_or_threshold_decisions') is not False:
        failures.append('contains_score_or_threshold_decisions must be literal false')
    if evidence.get('all_valid') is not True:
        failures.append('all_valid must be literal true')
    if evidence.get('evaluation_subject') not in {'candidate', 'reference'}:
        failures.append('evaluation subject is missing')
    source_contract = evidence.get('source_contract')
    if not isinstance(source_contract, dict):
        failures.append('source_contract must be an object')
    else:
        if source_contract.get('scenario_metrics_schema') != RAW_METRICS_SCHEMA:
            failures.append('runtime scenario-metrics schema mismatch')
        if source_contract.get('static_audit_schema') != STATIC_AUDIT_SCHEMA:
            failures.append('runtime static-audit schema mismatch')
    static_audit = evidence.get('static_audit')
    if not isinstance(static_audit, dict):
        failures.append('static_audit must be an object')
    else:
        checks = static_audit.get('checks')
        if not isinstance(checks, dict):
            failures.append('static_audit.checks must be an object')
        else:
            if tuple(checks) != STATIC_CHECKS:
                failures.append('static audit checks or order changed')
            for name in STATIC_CHECKS:
                if checks.get(name) is not True:
                    failures.append(f'static audit failed: {name}')
        provenance = static_audit.get('required_output_physical_provenance')
        if not isinstance(provenance, list) or len(provenance) != 3 or any((value is not True for value in provenance)):
            failures.append('physical output provenance is incomplete')
        if static_audit.get('pass') is not True:
            failures.append('static_audit.pass must be literal true')
    raw_rows = evidence.get('scenarios')
    if not isinstance(raw_rows, list):
        failures.append('scenarios must be an array')
        raw_rows = []
    if len(raw_rows) != len(EXPECTED_SCENARIOS):
        failures.append('evidence must contain exactly eight scenarios')
    if any((not isinstance(row, dict) for row in raw_rows)):
        failures.append('every scenario must be an object')
    raw_ids = [row.get('id') if isinstance(row, dict) else None for row in raw_rows]
    if raw_ids != list(EXPECTED_SCENARIOS):
        failures.append('scenario IDs or order changed')
    for scenario_id in EXPECTED_SCENARIOS:
        row = rows.get(scenario_id)
        expected_inputs = OFFICIAL_INPUTS.get(scenario_id)
        if row is None:
            failures.append(f'{scenario_id}: missing')
            continue
        if expected_inputs is None:
            failures.append(f'{scenario_id}: absent from scenario contract')
            continue
        if row.get('valid') is not True:
            failures.append(f'{scenario_id}: valid must be literal true')
        try:
            actual_inputs = normalize_inputs(row)
        except ValueError as exc:
            failures.append(f'{scenario_id}: {exc}')
            actual_inputs = {}
        if actual_inputs != expected_inputs:
            failures.append(f'{scenario_id}: current inputs changed')
        for field in PAIR_FIELDS:
            if pair(row.get(field)) is None:
                failures.append(f'{scenario_id}: {field} must be a finite pair')
        breath_tv = matrix(row.get('breath_tidal_volume_mL'))
        breath_command = matrix(row.get('breath_command_mean'))
        if breath_tv is None:
            failures.append(f'{scenario_id}: breath_tidal_volume_mL is invalid')
        if breath_command is None:
            failures.append(f'{scenario_id}: breath_command_mean is invalid')
        if breath_tv is not None and breath_command is not None and (len(breath_tv) != len(breath_command)):
            failures.append(f'{scenario_id}: breath evidence lengths differ')
        rate = finite(row.get('respiratory_rate_bpm'))
        if math.isfinite(rate) and rate > 0 and (breath_tv is not None):
            expected_breaths = math.floor(24.0 / (60.0 / rate))
            if len(breath_tv) != expected_breaths:
                failures.append(f'{scenario_id}: breath count differs from current 24 s run')
        initial_volume = pair(row.get('initial_tidal_volume_mL'))
        final_volume = pair(row.get('final_tidal_volume_mL'))
        initial_target = pair(row.get('initial_target_mL'))
        final_target = pair(row.get('final_target_mL'))
        initial_error = pair(row.get('initial_relative_error'))
        final_error = pair(row.get('final_relative_error'))
        if all((value is not None for value in (initial_volume, final_volume, initial_target, final_target, initial_error, final_error))):
            for patient in range(2):
                expected_initial = abs(initial_volume[patient] - initial_target[patient]) / initial_target[patient]
                expected_final = abs(final_volume[patient] - final_target[patient]) / final_target[patient]
                if abs(initial_error[patient] - expected_initial) > 1e-10:
                    failures.append(f'{scenario_id}: initial relative error inconsistent')
                if abs(final_error[patient] - expected_final) > 1e-10:
                    failures.append(f'{scenario_id}: final relative error inconsistent')
    return (not failures, failures)

def architecture_score(static_audit: dict[str, Any]) -> tuple[float, dict[str, Any]]:
    checks = static_audit.get('checks', {})
    values = [float(checks.get(name) is True) for name in STATIC_CHECKS]
    score = sum(values) / len(values)
    return (score, {'check_names': list(STATIC_CHECKS), 'check_values': values, 'worst_utility': min(values)})

def quality_score(rows: list[dict[str, Any]]) -> tuple[float, dict[str, Any]]:
    details: list[dict[str, Any]] = []
    utilities: list[float] = []
    for row in rows:
        pressure = pair(row['pressure_max_cmH2O']) or [math.nan, math.nan]
        peep = pair(row['pressure_peep_cmH2O']) or [math.nan, math.nan]
        flow_max = pair(row['flow_max_Lps']) or [math.nan, math.nan]
        flow_min = pair(row['flow_min_Lps']) or [math.nan, math.nan]
        command_min = pair(row['command_min']) or [math.nan, math.nan]
        command_max = pair(row['command_max']) or [math.nan, math.nan]
        pressure_limit = finite(row['max_inspiratory_pressure_cmH2O'])
        peep_target = finite(row['peep_cmH2O'])
        pressure_utility = min((upper_utility(value - pressure_limit, 0.5, 5.0) for value in pressure))
        peep_error = max((abs(value - peep_target) / max(peep_target, 1.0) for value in peep))
        peep_utility = lower_error_utility(peep_error, 0.15, 0.7)
        inspiratory_utility = min((clamp(value / 0.1) for value in flow_max))
        expiratory_utility = min((clamp(abs(min(value, 0.0)) / 0.05) for value in flow_min))
        command_utility = float(all((value >= -1e-06 for value in command_min)) and all((value <= 1.0 + 1e-06 for value in command_max)))
        components = (pressure_utility, peep_utility, inspiratory_utility, expiratory_utility, command_utility)
        utility = sum(components) / len(components)
        utilities.append(utility)
        details.append({'id': row['id'], 'pressure_limit_utility': pressure_utility, 'peep_relative_error': peep_error, 'peep_utility': peep_utility, 'inspiratory_flow_utility': inspiratory_utility, 'expiratory_flow_utility': expiratory_utility, 'command_bounds_utility': command_utility, 'scenario_utility': utility})
    worst_index = min(range(len(utilities)), key=utilities.__getitem__)
    return (utilities[worst_index], {'details': details, 'worst_scenario': details[worst_index]['id'], 'worst_scenario_utility': utilities[worst_index], 'high_peep_thresholds_unchanged': True})

def nominal_tracking_score(rows: dict[str, dict[str, Any]]) -> tuple[float, dict[str, Any]]:
    nominal = rows['nominal_targets']
    errors = (pair(nominal['initial_relative_error']) or []) + (pair(nominal['final_relative_error']) or [])
    utilities = [tracking_utility(error) for error in errors]
    return (min(utilities), {'scenario': 'nominal_targets', 'relative_errors': errors, 'utilities': utilities, 'worst_utility': min(utilities)})

def robustness_score(rows: dict[str, dict[str, Any]]) -> tuple[float, dict[str, Any]]:
    details: list[dict[str, Any]] = []
    for scenario_id in ROBUSTNESS_SCENARIOS:
        errors = pair(rows[scenario_id]['final_relative_error']) or []
        patient_utilities = [tracking_utility(error) for error in errors]
        details.append({'id': scenario_id, 'final_relative_errors': errors, 'patient_utilities': patient_utilities, 'scenario_utility': min(patient_utilities)})
    worst = min(details, key=lambda item: item['scenario_utility'])
    return (worst['scenario_utility'], {'details': details, 'worst_scenario': worst['id'], 'worst_scenario_utility': worst['scenario_utility']})

def settling_utility(errors: list[float]) -> tuple[float | None, int | None]:
    if len(errors) < 2:
        return (None, None)
    settling_breath: int | None = None
    for index in range(len(errors)):
        if all((error <= 0.2 for error in errors[index:])):
            settling_breath = index + 1
            break
    if settling_breath is not None:
        table = {1: 1.0, 2: 0.85, 3: 0.7, 4: 0.55, 5: 0.4}
        return (table.get(settling_breath, max(0.0, 0.4 - 0.1 * (settling_breath - 5))), settling_breath)
    improvement = max(errors[0] - min(errors[1:]), 0.0) / max(errors[0], 1e-12)
    return (0.4 * quality_high(improvement, 0.5, 0.0), None)

def dynamic_score(rows: dict[str, dict[str, Any]]) -> tuple[float, dict[str, Any], list[str]]:
    details: list[dict[str, Any]] = []
    gaps: list[str] = []
    for scenario_id in STEP_SCENARIOS:
        row = rows[scenario_id]
        tidal_volume = matrix(row['breath_tidal_volume_mL']) or []
        command = matrix(row['breath_command_mean']) or []
        rate = finite(row['respiratory_rate_bpm'])
        step_time = finite(row['target_step_time_s'])
        period = 60.0 / rate
        pre_indices = [index for index in range(len(tidal_volume)) if (index + 1) * period <= step_time + 1e-09]
        post_indices = [index for index in range(len(tidal_volume)) if index * period >= step_time - 1e-09]
        patient_details: list[dict[str, Any]] = []
        for patient in range(2):
            initial_target = finite(row['target_tv1_initial_mL' if patient == 0 else 'target_tv2_initial_mL'])
            final_target = finite(row['target_tv1_final_mL' if patient == 0 else 'target_tv2_final_mL'])
            target_delta = final_target - initial_target
            post_values = [tidal_volume[index][patient] for index in post_indices]
            post_errors = [abs(value - final_target) / final_target for value in post_values]
            recovery_utility, settling_breath = settling_utility(post_errors)
            components: list[tuple[float, float]] = []
            if recovery_utility is None:
                gaps.append(f'{scenario_id}/patient{patient + 1}: only {len(post_indices)} complete post-step breath; per-breath recovery unavailable')
            else:
                components.append((recovery_utility, 0.5))
            if target_delta > 0:
                overshoot = max((max(value - final_target, 0.0) / abs(target_delta) for value in post_values), default=math.nan)
            else:
                overshoot = max((max(final_target - value, 0.0) / abs(target_delta) for value in post_values), default=math.nan)
            overshoot_utility = quality_low(overshoot, 0.05, 0.5)
            components.append((overshoot_utility, 0.2))
            if pre_indices and post_indices and (target_delta != 0):
                baseline_command = command[pre_indices[-1]][patient]
                direction = 1.0 if target_delta > 0 else -1.0
                aligned_command_change = max((direction * (command[index][patient] - baseline_command) for index in post_indices))
                command_utility = quality_high(aligned_command_change, 0.03, 0.0)
            else:
                baseline_command = math.nan
                aligned_command_change = math.nan
                command_utility = 0.0
            components.append((command_utility, 0.3))
            patient_utility = weighted_mean(components)
            patient_details.append({'patient': patient + 1, 'complete_pre_step_breaths': len(pre_indices), 'complete_post_step_breaths': len(post_indices), 'post_step_relative_errors': post_errors, 'settling_breath_20pct': settling_breath, 'recovery_utility': recovery_utility, 'directed_tidal_volume_overshoot_fraction': overshoot, 'overshoot_utility': overshoot_utility, 'pre_step_command': baseline_command, 'aligned_command_change': aligned_command_change, 'command_response_utility': command_utility, 'patient_utility': patient_utility})
        details.append({'id': scenario_id, 'patients': patient_details, 'scenario_utility': min((item['patient_utility'] for item in patient_details))})
    worst = min(details, key=lambda item: item['scenario_utility'])
    return (worst['scenario_utility'], {'definition': 'Per-breath 20% settling, directed tidal-volume overshoot, and directional branch-command response; final_relative_error is not read by this group.', 'details': details, 'worst_scenario': worst['id'], 'worst_scenario_utility': worst['scenario_utility'], 'uses_final_relative_error': False}, sorted(set(gaps)))

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = row_map(evidence.get('scenarios'))
    gate, gate_failures = gate_evidence(evidence, rows)
    static_audit = evidence.get('static_audit', {})
    if gate:
        A, metrics_a = nominal_tracking_score(rows)
        Q, metrics_q = quality_score(list(rows.values()))
        M, metrics_m = architecture_score(static_audit)
        R, metrics_r = robustness_score(rows)
        D, metrics_d, evidence_gaps = dynamic_score(rows)
        groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
        score = 100.0
        for group, weight in WEIGHTS.items():
            score *= groups[group] ** weight
        shortcut_findings: list[dict[str, Any]] = []
        command_utilities = [patient['command_response_utility'] for scenario in metrics_d['details'] for patient in scenario['patients']]
        if min(command_utilities, default=0.0) < 0.1:
            shortcut_findings.append({'id': 'missing_directional_branch_command_response', 'group': 'D', 'reason': 'a target step lacks a directionally consistent branch-command response'})
        group_metrics = {'A': metrics_a, 'Q': metrics_q, 'M': metrics_m, 'R': metrics_r, 'D': metrics_d}
    else:
        groups = {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}
        score = 0.0
        shortcut_findings = []
        evidence_gaps = []
        group_metrics = {'A': {}, 'Q': {}, 'M': {}, 'R': {}, 'D': {}}
    failures = list(gate_failures)
    failures.extend((item['id'] + ': ' + item['reason'] for item in shortcut_findings))
    return {'schema': SCORE_SCHEMA, 'task_id': TASK_ID, 'policy_id': POLICY_ID, 'score_inputs_valid': gate, 'G': gate, 'score': score, 'groups': groups, 'weights': WEIGHTS, 'aggregation': 'Geometric weighted total; score-bearing multi-scenario groups use their worst scenario.', 'shortcut_findings': shortcut_findings, 'group_metrics': group_metrics, 'evidence_sufficiency': {'D': 'PARTIAL' if evidence_gaps else 'COMPLETE', 'gaps': evidence_gaps + ['saved evidence has no breath-level pressure/flow series, so D makes no transient pressure-overshoot claim', 'saved evidence has breath aggregates rather than raw within-breath traces, so sub-breath response latency is not scored']}, 'duplicate_penalty_audit': {'R_uses_final_relative_error': True, 'D_uses_final_relative_error': False, 'D_inputs': ['breath_tidal_volume_mL', 'breath_command_mean', 'respiratory_rate_bpm', 'target_step_time_s', 'initial and final target values']}, 'failure_reasons': failures}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = score_evidence(read_json(args.evidence))
    write_json(args.output, result)
    print(f"F90_XMED03_OFFLINE_SCORE score={result['score']:.9f} G={int(result['G'])} " + ' '.join((f"{name}={result['groups'][name]:.6f}" for name in ('A', 'Q', 'M', 'R', 'D'))))
if __name__ == '__main__':
    main()
