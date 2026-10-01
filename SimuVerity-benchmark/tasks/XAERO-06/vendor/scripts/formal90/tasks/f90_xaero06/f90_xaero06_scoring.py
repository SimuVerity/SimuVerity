"""XAERO06 no-cap scorer with performance/qualification separation.

Technical evidence validity is limited to a runnable core model, the public
output interface, a complete nominal record, and a recorded attempt for every
required scenario.  Finite but poor flight performance and a official-scenario
numerical failure are scored in their owning groups instead of invalidating
the evidence before offline scoring.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any
import f90_xaero06_scoring_core as core
POLICY_ID = "simuverity-101-v1:f90-xaero-06:scoring"
WEIGHTS = core.WEIGHTS
REQUIRED_SCENARIOS = core.REQUIRED_SCENARIOS
TECHNICAL_OUTPUT_FIELDS = ('landing_state_nonempty', 'landing_state_finite', 'guidance_nonempty', 'surface_command_nonempty', 'surface_position_nonempty', 'landing_state_width_16', 'guidance_width_3', 'surface_command_width_6', 'surface_position_width_6', 'all_required_timeseries_finite', 'complete_run_starts_at_zero', 'mission_horizon_present')
PERFORMANCE_OUTPUT_FIELDS = ('position_and_altitude_dynamic', 'airdata_dynamic', 'guidance_dynamic', 'surface_command_dynamic', 'surface_position_dynamic')

def strict_geometric(groups: dict[str, float]) -> float:
    values = {name: float(groups[name]) for name in WEIGHTS}
    if any((not math.isfinite(value) or not 0.0 <= value <= 1.0 for value in values.values())):
        raise ValueError('group scores must be finite and in [0, 1]')
    if any((value <= 0.0 for value in values.values())):
        return 0.0
    return 100.0 * math.exp(sum((WEIGHTS[name] * math.log(values[name]) for name in WEIGHTS)))

def row_error_id(row: dict[str, Any]) -> str:
    error = row.get('error')
    if not isinstance(error, dict):
        return 'UNSPECIFIED_SCENARIO_FAILURE'
    return str(error.get('id') or error.get('identifier') or 'UNSPECIFIED_SCENARIO_FAILURE')

def scenario_attempted(row: dict[str, Any]) -> bool:
    if row.get('execution_attempted') is True:
        return True
    if row.get('simulation_pass') is True:
        return True
    error = row.get('error')
    return isinstance(error, dict) and any((bool(str(error.get(key, ''))) for key in ('id', 'identifier', 'message')))

def technical_output_valid(row: dict[str, Any]) -> bool:
    explicit = row.get('technical_evidence_valid')
    if isinstance(explicit, bool):
        return explicit
    if row.get('simulation_pass') is not True:
        return False
    contract = row.get('output_contract')
    return isinstance(contract, dict) and all((contract.get(name) is True for name in TECHNICAL_OUTPUT_FIELDS))

def metric_row_available(row: dict[str, Any]) -> bool:
    return technical_output_valid(row) and isinstance(row.get('metrics'), dict)

def pfq_qualification(evidence: dict[str, Any], rows: dict[str, dict[str, Any]]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    for name in ('evidence_complete', 'load_pass', 'update_pass', 'compile_pass', 'nominal_smoke_pass', 'score_inputs_valid', 'diagnostics_valid'):
        if evidence.get(name) is not True:
            failures.append(f'{name}=false')
    if core.evaluation_subject(evidence) not in {'candidate', 'reference'}:
        failures.append('unsupported evaluation_subject')
    missing = [name for name in REQUIRED_SCENARIOS if name not in rows]
    if missing:
        failures.append('missing scenarios: ' + ', '.join(missing))
    unattempted = [name for name in REQUIRED_SCENARIOS if name in rows and (not scenario_attempted(rows[name]))]
    if unattempted:
        failures.append('unattempted scenarios: ' + ', '.join(unattempted))
    nominal = rows.get('nominal_autoland')
    if nominal is None or not technical_output_valid(nominal):
        failures.append('nominal public output contract is not technically valid')
    if not core.core_static_pass(evidence):
        failures.append('closed-loop guidance-actuator-aerodynamic-6DOF path failed')
    return (not failures, failures)

def score_complete_evidence(result: dict[str, Any]) -> dict[str, Any]:
    """Apply group-owned findings and strict aggregation to complete evidence."""
    gate = bool(result['G'])
    diagnostics = result.setdefault('diagnostics', {})
    findings = [str(item.get('reason', item)) if isinstance(item, dict) else str(item) for item in diagnostics.pop('shortcut_findings', [])]
    groups = {name: float(result['groups'][name]) for name in WEIGHTS}
    penalties: list[dict[str, str]] = []
    for finding in findings:
        if finding in {'workspace inputs are not applied', 'nominal trajectory is replayed across official inputs'}:
            groups['R'] = 0.0
            penalties.append({'finding': finding, 'group': 'R'})
        elif finding in {'surface command bypasses bounded dynamic actuator evidence', 'surface command is constant or prescribed', 'endpoint-only descent lacks dynamic guidance evidence'}:
            groups['D'] = 0.0
            penalties.append({'finding': finding, 'group': 'D'})
    total = strict_geometric(groups) if gate else 0.0
    result['schema'] = 'simuverity.f90-xaero06-score.pfq.v1'
    result['policy_id'] = POLICY_ID
    result['score_inputs_valid'] = gate
    result['diagnostics_valid'] = gate
    result['groups'] = {'G': 1.0 if gate else 0.0, **groups}
    result['score'] = total
    result['total'] = total
    result['weights'] = dict(WEIGHTS)
    result['admission_score_pass'] = bool(gate and total >= 85.0)
    diagnostics['anti_shortcut_findings'] = findings
    diagnostics['anti_shortcut_group_penalties'] = penalties
    diagnostics['pfq_mode'] = 'complete_evidence'
    result['total_aggregation'] = total_aggregation()
    return result

def performance_failure_reasons(rows: dict[str, dict[str, Any]]) -> list[str]:
    reasons: list[str] = []
    for name in REQUIRED_SCENARIOS:
        row = rows[name]
        if row.get('simulation_pass') is not True:
            reasons.append(f'SCENARIO_SIMULATION_FAILED:{name}:{row_error_id(row)}')
            continue
        contract = row.get('output_contract')
        if not isinstance(contract, dict):
            continue
        for field in PERFORMANCE_OUTPUT_FIELDS:
            if contract.get(field) is False:
                reasons.append(f'PERFORMANCE_CONTRACT_FAILED:{name}:{field}')
    return reasons

def applied_inputs_match(row: dict[str, Any]) -> bool:
    requested = row.get('requested_inputs')
    applied = row.get('applied_inputs')
    metrics = row.get('metrics')
    if not isinstance(applied, dict) and isinstance(metrics, dict):
        applied = metrics.get('applied_inputs')
    if not isinstance(requested, dict) or not isinstance(applied, dict):
        return False
    keys = ('InitialAirspeedScale', 'InitialBankOffset_deg', 'VehicleMassScale', 'WindSeverityScale')
    try:
        return all((abs(float(requested[key]) - float(applied[key])) <= 1e-09 for key in keys))
    except (KeyError, TypeError, ValueError):
        return False

def score_partial(evidence: dict[str, Any], rows: dict[str, dict[str, Any]]) -> dict[str, Any]:
    gate, failures = pfq_qualification(evidence, rows)
    if not gate:
        return result_receipt(evidence, False, {name: 0.0 for name in WEIGHTS}, {}, [], failures)
    available = {name: rows[name]['metrics'] for name in REQUIRED_SCENARIOS if metric_row_available(rows[name])}
    nominal = available['nominal_autoland']
    failed = [name for name in REQUIRED_SCENARIOS if name not in available]
    failures.extend(performance_failure_reasons(rows))
    terminal_completion = {name: core.terminal_completion_utility(available[name]) if name in available else 0.0 for name in REQUIRED_SCENARIOS}
    worst_terminal_completion = min(terminal_completion.values())
    a_utilities = {'downrange_progress': core.high_good(nominal['downrange_progress_fraction'], 0.85, 0.98), 'terminal_altitude': core.low_good(abs(nominal['terminal_altitude_m']), 20.0, 250.0), 'terminal_sink_rate': core.low_good(nominal['terminal_sink_rate_mps'], 3.5, 10.0), 'terminal_speed': core.band_good(nominal['terminal_speed_mps'], 30.0, 45.0, 105.0, 130.0), 'flare_demand_change': core.high_good(abs(nominal['late_alpha_demand_change_deg']), 0.15, 1.5)}
    nominal_primary = core.weighted_mean(a_utilities, {'downrange_progress': 0.25, 'terminal_altitude': 0.2, 'terminal_sink_rate': 0.25, 'terminal_speed': 0.15, 'flare_demand_change': 0.15})
    A = core.weighted_mean({'nominal_primary_accuracy': nominal_primary, 'worst_required_terminal_completion': worst_terminal_completion}, {'nominal_primary_accuracy': 0.8, 'worst_required_terminal_completion': 0.2})
    q_utilities: dict[str, dict[str, float]] = {}
    q_scores: dict[str, float] = {}
    for name in REQUIRED_SCENARIOS:
        if name not in available:
            q_utilities[name] = {'numerically_complete': 0.0}
            q_scores[name] = 0.0
            continue
        item = available[name]
        utilities = {'roll_envelope': core.low_good(item['maximum_abs_roll_deg'], 8.0, 30.0), 'pitch_envelope': core.low_good(item['maximum_abs_pitch_deg'], 30.0, 50.0), 'body_rate_envelope': core.low_good(item['maximum_abs_body_rate_radps'], 0.35, 1.2), 'alpha_lower_bound': core.high_good(item['minimum_alpha_deg'], -13.0, -9.5), 'alpha_upper_bound': core.low_good(item['maximum_alpha_deg'], 29.0, 36.0), 'beta_envelope': core.low_good(item['maximum_abs_beta_deg'], 5.0, 11.0), 'actuator_tracking': core.low_good(item['surface_tracking_rmse_deg'], 1.0, 7.0), 'limited_saturation': core.low_good(item['surface_saturation_fraction'], 0.02, 0.2)}
        q_utilities[name] = utilities
        q_scores[name] = core.weighted_mean(utilities)
    Q = min(q_scores.values())
    requested_applied = all((applied_inputs_match(rows[name]) for name in REQUIRED_SCENARIOS))
    summarys = {round(float(item['flight_state_summary']), 6) for item in available.values()}
    actuator_lag = bool(available) and all((0.002 <= float(item['surface_tracking_peak_deg']) <= 20.0 for item in available.values()))
    m_utilities = {**core.static_mechanism_utilities(evidence), 'requested_inputs_applied': float(requested_applied), 'scenarios_change_state': core.high_good(len(summarys), 2.0, 5.0), 'guidance_is_dynamic': min((core.high_good(item['guidance_activity_deg'], 0.05, 0.5) for item in available.values())), 'surface_command_is_dynamic': min((core.high_good(item['surface_command_activity_deg'], 0.05, 0.5) for item in available.values())), 'bounded_actuator_lag_witness': float(actuator_lag)}
    M = core.weighted_mean(m_utilities)
    r_utilities: dict[str, dict[str, float]] = {}
    r_scores: dict[str, float] = {}
    for name in REQUIRED_SCENARIOS:
        if name not in available:
            r_utilities[name] = {'numerically_complete': 0.0}
            r_scores[name] = 0.0
            continue
        item = available[name]
        utilities = {'downrange_progress': core.high_good(item['downrange_progress_fraction'], 0.8, 0.96), 'terminal_altitude': core.low_good(abs(item['terminal_altitude_m']), 30.0, 300.0), 'terminal_sink': core.low_good(item['terminal_sink_rate_mps'], 4.0, 11.0), 'terminal_roll': core.low_good(item['terminal_abs_roll_deg'], 2.5, 15.0), 'terminal_speed': core.band_good(item['terminal_speed_mps'], 25.0, 40.0, 115.0, 140.0), 'alpha_table_support': min(core.high_good(item['minimum_alpha_deg'], -14.0, -10.0), core.low_good(item['maximum_alpha_deg'], 30.0, 38.0)), 'sideslip_table_support': core.low_good(item['maximum_abs_beta_deg'], 7.0, 12.0)}
        r_utilities[name] = utilities
        r_scores[name] = core.weighted_mean(utilities)
    R = min(r_scores.values())
    bank = available.get('bank_angle_recovery')
    d_utilities = {'nominal_terminal_sink_reduction': core.high_good(nominal['terminal_sink_reduction_fraction'], 0.02, 0.45), 'worst_terminal_sink_reduction': min((core.high_good(available[name]['terminal_sink_reduction_fraction'], 0.0, 0.35) if name in available else 0.0 for name in REQUIRED_SCENARIOS)), 'bank_perturbation_recovery': core.low_good(bank['bank_recovery_time_s'], 6.0, 25.0) if bank is not None else 0.0, 'terminal_bank_recovered': core.low_good(bank['terminal_abs_roll_deg'], 1.0, 8.0) if bank is not None else 0.0, 'flare_guidance_response': core.high_good(abs(nominal['late_alpha_demand_change_deg']), 0.1, 1.2), 'dynamic_surface_response': min((core.high_good(available[name]['surface_tracking_peak_deg'], 0.002, 0.15) if name in available else 0.0 for name in REQUIRED_SCENARIOS))}
    dynamic_mean = core.weighted_mean(d_utilities)
    D = core.weighted_mean({'dynamic_response_mean': dynamic_mean, 'worst_required_terminal_completion': worst_terminal_completion}, {'dynamic_response_mean': 0.75, 'worst_required_terminal_completion': 0.25})
    groups = {'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    diagnostics = {'pfq_mode': 'performance-failure-separated', 'available_metric_scenarios': list(available), 'failed_metric_scenarios': failed, 'A_utilities': a_utilities, 'Q_scenario_scores': q_scores, 'Q_utilities': q_utilities, 'M_utilities': m_utilities, 'R_scenario_scores': r_scores, 'R_utilities': r_utilities, 'D_utilities': d_utilities, 'terminal_completion_by_scenario': terminal_completion, 'post_total_cap': 'none'}
    scenario_results = [{'scenario_id': name, 'simulation_pass': rows[name].get('simulation_pass') is True, 'technical_evidence_valid': technical_output_valid(rows[name]), 'performance_failure': rows[name].get('simulation_pass') is not True or any((rows[name].get('output_contract', {}).get(field) is False for field in PERFORMANCE_OUTPUT_FIELDS)), 'Q': q_scores[name], 'R': r_scores[name], 'terminal_completion': terminal_completion[name]} for name in REQUIRED_SCENARIOS]
    return result_receipt(evidence, True, groups, diagnostics, scenario_results, failures)

def total_aggregation() -> dict[str, Any]:
    return {'method': 'G_times_strict_weighted_geometric_mean', 'formula': 'G*100*product(group_score^weight)', 'epsilon_floor': 'none', 'strict_zero_rule': 'any_applicable_group_le_zero_means_total_zero', 'post_group_score_cap': 'none', 'performance_failure_and_qualification_separated': True}

def result_receipt(evidence: dict[str, Any], gate: bool, groups: dict[str, float], diagnostics: dict[str, Any], scenarios: list[dict[str, Any]], failures: list[str]) -> dict[str, Any]:
    total = strict_geometric(groups) if gate else 0.0
    return {'schema': 'simuverity.f90-xaero06-score.pfq.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XAERO-06', 'formula': 'G*100*A^0.20*Q^0.10*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'score_inputs_valid': bool(gate), 'diagnostics_valid': bool(gate), 'G': bool(gate), 'groups': {'G': 1.0 if gate else 0.0, **groups}, 'score': total, 'total': total, 'weights': dict(WEIGHTS), 'admission_threshold': 85, 'admission_score_pass': bool(gate and total >= 85.0), 'diagnostics': diagnostics, 'metrics': diagnostics, 'scenarios': scenarios, 'failure_reasons': list(dict.fromkeys(failures)), 'total_aggregation': total_aggregation()}

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = core.scenario_map(evidence)
    gate, failures = pfq_qualification(evidence, rows)
    if not gate:
        return result_receipt(evidence, False, {name: 0.0 for name in WEIGHTS}, {}, [], failures)
    if all((metric_row_available(rows[name]) for name in REQUIRED_SCENARIOS)):
        complete_input = copy.deepcopy(evidence)
        complete_input['evidence_complete'] = True
        complete_input['score_inputs_valid'] = True
        complete_input['diagnostics_valid'] = True
        for name in REQUIRED_SCENARIOS:
            complete_input_row = next((row for row in complete_input['scenarios'] if str(row.get('id')) == name))
            complete_input_row['valid'] = True
            output_contract = complete_input_row.get('output_contract')
            if isinstance(output_contract, dict):
                for field in PERFORMANCE_OUTPUT_FIELDS:
                    if field in output_contract:
                        output_contract[field] = True
        return score_complete_evidence(core.score_evidence(complete_input))
    return score_partial(evidence, rows)

def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write('\n')

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8-sig'))
    result = score_evidence(evidence)
    if args.out:
        write_json(args.out, result)
    print(json.dumps({'score': result['score'], 'groups': result['groups'], 'policy_id': result['policy_id']}, ensure_ascii=False))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())
