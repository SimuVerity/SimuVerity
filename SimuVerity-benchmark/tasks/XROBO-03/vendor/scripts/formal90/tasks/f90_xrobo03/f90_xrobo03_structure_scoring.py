"""Current pure-Python offline scorer for F90-XROBO-03.

The scorer consumes fixed JSON evidence only. It does not import a MATLAB
package, open a Simulink model, or launch an external process.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable
FORMAL_ID = 'F90-XROBO-03'
POLICY_ID = 'simuverity-101-v1:f90-xrobo-03:scoring'
COMPATIBLE_EVIDENCE_POLICY_IDS = {POLICY_ID}
EVIDENCE_SCHEMA = 'simuverity.f90-xrobo03-evidence.v1'
SCORE_SCHEMA = 'simuverity.f90-xrobo03-offline-score.v1'
THRESHOLD_CONFIGURATION = 'task-specific'
TASK_ROOT = Path(__file__).resolve().parents[5]
SCENARIOS_PATH = TASK_ROOT / 'official_scenarios.json'
INPUT_FIELDS = ('initial_body_height_m', 'initial_forward_velocity_mps', 'initial_vertical_velocity_mps', 'torso_mass_kg', 'ground_friction_scale', 'ground_stiffness_npm', 'ground_damping_nspm', 'joint_torque_limit_nm')
EXPECTED_SCENARIOS = ('nominal', 'low_friction_heavy', 'compliant_downward_recovery', 'stiff_forward_start', 'friction_derated_pair', 'payload_heavy_pair')
RANGE_SCENARIOS = ('nominal', 'low_friction_heavy', 'compliant_downward_recovery', 'stiff_forward_start')
GROUP_WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}
REQUIRED_ROW_METRICS = ('duration_s', 'samples', 'forward_displacement_m', 'mean_forward_speed_mps', 'positive_forward_fraction', 'min_body_height_m', 'height_ripple_m', 'max_abs_roll_rad', 'max_abs_pitch_rad', 'lateral_drift_m', 'yaw_drift_rad', 'body_kinematic_closure_rms_mps', 'joint_angle_max_abs_rad', 'joint_speed_max_abs_radps', 'action_max_abs', 'action_range', 'torque_max_abs_nm', 'torque_range_nm', 'action_torque_closure_relative_rms', 'control_effort_rms_nm', 'positive_normal_force_fraction_4', 'min_contact_transitions_4', 'minimum_landing_count_4', 'friction_force_rms_n')
STATIC_AUDIT_FIELDS = ('dynamic_block_count', 'physical_joint_count', 'spatial_contact_count', 'actuated_joint_count', 'physical_sensor_count', 'constant_or_workspace_output_count')

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

def is_json_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and (not isinstance(value, bool)) and math.isfinite(float(value))

def finite(value: Any, default: float=math.nan) -> float:
    if not is_json_number(value):
        return default
    return float(value)

def json_number(value: Any) -> float | None:
    number = finite(value)
    return number if math.isfinite(number) else None

def nonfinite_paths(value: Any, prefix: str='$') -> list[str]:
    """Find non-finite numeric tokens anywhere in parsed JSON evidence."""
    failures: list[str] = []
    if isinstance(value, float) and (not math.isfinite(value)):
        failures.append(prefix)
    elif isinstance(value, dict):
        for key, item in value.items():
            failures.extend(nonfinite_paths(item, f'{prefix}.{key}'))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            failures.extend(nonfinite_paths(item, f'{prefix}[{index}]'))
    return failures

def normalized_inputs(value: Any) -> dict[str, float]:
    if not isinstance(value, dict) or set(value) != set(INPUT_FIELDS):
        raise ValueError('requested_inputs must contain exactly the public inputs')
    result: dict[str, float] = {}
    for field in INPUT_FIELDS:
        item = value[field]
        if not is_json_number(item):
            raise ValueError(f'{field} must be a finite JSON number')
        result[field] = float(item)
    return result

def load_scenario_contract() -> tuple[dict[str, dict[str, Any]], list[str]]:
    failures: list[str] = []
    spec = read_json(SCENARIOS_PATH)
    if spec.get('task_id') != FORMAL_ID:
        failures.append('scenario contract task_id mismatch')
    raw_scenarios = spec.get('scenarios')
    if not isinstance(raw_scenarios, list):
        return ({}, ['scenario contract must contain an array'])
    records: dict[str, dict[str, Any]] = {}
    for raw in raw_scenarios:
        if not isinstance(raw, dict):
            failures.append('scenario contract contains a non-object scenario')
            continue
        scenario_id = raw.get('id')
        scenario_class = raw.get('class')
        if not isinstance(scenario_id, str) or not isinstance(scenario_class, str):
            failures.append('scenario identity must be text')
            continue
        try:
            inputs = normalized_inputs({field: raw.get(field) for field in INPUT_FIELDS})
        except ValueError as exc:
            failures.append(f'{scenario_id}: invalid inputs: {exc}')
            continue
        if scenario_id in records:
            failures.append(f'scenario contract has a duplicate: {scenario_id}')
        records[scenario_id] = {'id': scenario_id, 'class': scenario_class, 'requested_inputs': inputs}
    if tuple(records) != EXPECTED_SCENARIOS:
        failures.append('scenario order or IDs mismatch')

    def one_factor_pair(left_id: str, right_id: str, changed_field: str) -> bool:
        if left_id not in records or right_id not in records:
            return False
        left = records[left_id]['requested_inputs']
        right = records[right_id]['requested_inputs']
        return all((left[field] != right[field] if field == changed_field else left[field] == right[field] for field in INPUT_FIELDS))
    if not one_factor_pair('nominal', 'friction_derated_pair', 'ground_friction_scale'):
        failures.append('friction pair is not a one-factor pair')
    if not one_factor_pair('nominal', 'payload_heavy_pair', 'torso_mass_kg'):
        failures.append('payload pair is not a one-factor pair')
    return (records, failures)
EXPECTED_RECORDS, SCENARIO_CONTRACT_FAILURES = load_scenario_contract()

def quality_low(value: Any, good: float, bad: float) -> float:
    metric_value = finite(value)
    if not math.isfinite(metric_value):
        return 0.0
    if bad <= good:
        return float(metric_value <= good)
    return min(max((bad - metric_value) / (bad - good), 0.0), 1.0)

def quality_high(value: Any, good: float, bad: float) -> float:
    metric_value = finite(value)
    if not math.isfinite(metric_value):
        return 0.0
    if good <= bad:
        return float(metric_value >= good)
    return min(max((metric_value - bad) / (good - bad), 0.0), 1.0)

def weighted_mean(items: Iterable[tuple[float, float]]) -> float:
    pairs = list(items)
    denominator = sum((weight for _, weight in pairs))
    if denominator <= 0.0:
        return 0.0
    return sum((value * weight for value, weight in pairs)) / denominator

def metric(metric_id: str, value: Any, score: float, group: str, definition: str) -> dict[str, Any]:
    return {'id': metric_id, 'group': group, 'value': json_number(value), 'score': min(max(float(score), 0.0), 1.0), 'definition': definition, 'threshold_configuration': THRESHOLD_CONFIGURATION}

def row_map(rows: Any) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    if not isinstance(rows, list):
        return result
    for row in rows:
        if not isinstance(row, dict):
            continue
        scenario_id = row.get('id')
        if isinstance(scenario_id, str) and scenario_id not in result:
            result[scenario_id] = row
    return result

def minimum(rows: Iterable[dict[str, Any]], field: str) -> float:
    values = [finite(row.get(field)) for row in rows]
    finite_values = [value for value in values if math.isfinite(value)]
    return min(finite_values) if finite_values else math.nan

def maximum(rows: Iterable[dict[str, Any]], field: str) -> float:
    values = [finite(row.get(field)) for row in rows]
    finite_values = [value for value in values if math.isfinite(value)]
    return max(finite_values) if finite_values else math.nan

def relative_delta(left: Any, right: Any, floor: float=1e-09) -> float:
    left_value = finite(left)
    right_value = finite(right)
    if not math.isfinite(left_value) or not math.isfinite(right_value):
        return math.nan
    return abs(right_value - left_value) / max(abs(left_value), abs(right_value), floor)

def gate_direct_reference(evidence: dict[str, Any], failures: list[str]) -> None:
    if evidence.get('evaluation_subject') != 'reference':
        failures.append('direct reference requires the reference subject role')
    integrity = evidence.get('direct_reference_integrity')
    if not isinstance(integrity, dict):
        failures.append('direct_reference_integrity must be a JSON object')
        return
    for field in ('unchanged', 'closed_without_save'):
        if integrity.get(field) is not True:
            failures.append(f'direct_reference_integrity.{field} must be literal true')
    if integrity.get('model_saved') is not False:
        failures.append('direct_reference_integrity.model_saved must be literal false')
    if not is_json_number(integrity.get('substantive_adjustments')) or float(integrity['substantive_adjustments']) != 0.0:
        failures.append('direct_reference_integrity.substantive_adjustments must be zero')

def gate_evidence(evidence: dict[str, Any], rows: dict[str, dict[str, Any]]) -> tuple[bool, list[str]]:
    failures = list(SCENARIO_CONTRACT_FAILURES)
    if evidence.get('schema') != EVIDENCE_SCHEMA:
        failures.append('evidence schema mismatch')
    if evidence.get('formal_id') != FORMAL_ID:
        failures.append('formal_id mismatch')
    evidence_policy = evidence.get('policy_id')
    if evidence_policy not in COMPATIBLE_EVIDENCE_POLICY_IDS:
        failures.append('evidence policy identity is not compatible')
    if evidence.get('extraction_only') is not True:
        failures.append('extraction_only must be literal true')
    if evidence.get('contains_score_or_threshold_decisions') is not False:
        failures.append('contains_score_or_threshold_decisions must be literal false')
    nonfinite = nonfinite_paths(evidence)
    if nonfinite:
        failures.append('evidence contains nonfinite JSON numbers: ' + ', '.join(nonfinite[:12]))
    adapter = evidence.get('adapter')
    if adapter not in ('candidate_submission', 'standard_public_outputs', 'reference_direct'):
        failures.append('adapter is not an allowed literal')
    if adapter == 'reference_direct':
        gate_direct_reference(evidence, failures)
    for field in ('load_pass', 'update_pass', 'compile_pass'):
        if evidence.get(field) is not True:
            failures.append(f'{field} must be literal true')
    static_audit = evidence.get('static_audit')
    if not isinstance(static_audit, dict):
        failures.append('static_audit must be a JSON object')
    else:
        for field in STATIC_AUDIT_FIELDS:
            if not is_json_number(static_audit.get(field)):
                failures.append(f'static_audit.{field} must be a finite JSON number')
    raw_rows = evidence.get('scenarios')
    if not isinstance(raw_rows, list):
        failures.append('scenarios must be a JSON array')
        raw_rows = []
    if len(raw_rows) != len(EXPECTED_SCENARIOS):
        failures.append(f'scenarios must contain exactly {len(EXPECTED_SCENARIOS)} rows')
    if any((not isinstance(row, dict) for row in raw_rows)):
        failures.append('every scenario row must be a JSON object')
    raw_ids = [row.get('id') if isinstance(row, dict) else None for row in raw_rows]
    if raw_ids != list(EXPECTED_SCENARIOS):
        failures.append('scenario IDs or order do not match official_scenarios.json')
    text_ids = [scenario_id for scenario_id in raw_ids if isinstance(scenario_id, str) and scenario_id]
    duplicates = sorted((scenario_id for scenario_id in set(text_ids) if text_ids.count(scenario_id) > 1))
    if duplicates:
        failures.append('duplicate scenarios: ' + ', '.join(duplicates))
    for scenario_id in EXPECTED_SCENARIOS:
        row = rows.get(scenario_id)
        expected = EXPECTED_RECORDS.get(scenario_id)
        if row is None:
            failures.append(f'{scenario_id}: missing scenario object')
            continue
        if expected is None:
            failures.append(f'{scenario_id}: absent from scenario contract')
            continue
        if row.get('class') != expected['class']:
            failures.append(f'{scenario_id}: class mismatch')
        try:
            actual_inputs = normalized_inputs(row.get('requested_inputs'))
        except ValueError as exc:
            failures.append(f'{scenario_id}: requested_inputs invalid: {exc}')
            actual_inputs = None
        if actual_inputs != expected['requested_inputs']:
            failures.append(f'{scenario_id}: requested_inputs mismatch')
        for field in ('valid', 'simulation_pass', 'output_contract_pass', 'finite_pass', 'scenario_applied'):
            if row.get(field) is not True:
                failures.append(f'{scenario_id}: {field} must be literal true')
        duration = row.get('duration_s')
        if not is_json_number(duration) or abs(float(duration) - 10.0) > 1e-09:
            failures.append(f'{scenario_id}: scenario must complete the full 10 s')
        samples = row.get('samples')
        if not is_json_number(samples) or float(samples) < 2.0 or (not float(samples).is_integer()):
            failures.append(f'{scenario_id}: samples must be an integer of at least two')
        missing_metrics = [field for field in REQUIRED_ROW_METRICS if not is_json_number(row.get(field))]
        if missing_metrics:
            failures.append(f'{scenario_id}: missing or nonfinite metrics: ' + ', '.join(missing_metrics))
    return (not failures, failures)

def score_group_a(nominal: dict[str, Any]) -> tuple[float, list[dict[str, Any]]]:
    values = [metric('nominal_forward_displacement_m', nominal.get('forward_displacement_m'), quality_high(nominal.get('forward_displacement_m'), 2.0, 0.3), 'A', '10 s world-x torso displacement'), metric('nominal_mean_forward_speed_mps', nominal.get('mean_forward_speed_mps'), quality_high(nominal.get('mean_forward_speed_mps'), 0.2, 0.03), 'A', 'mean measured torso world-x speed'), metric('nominal_positive_forward_fraction', nominal.get('positive_forward_fraction'), quality_high(nominal.get('positive_forward_fraction'), 0.85, 0.5), 'A', 'fraction of samples with positive measured forward speed'), metric('nominal_min_body_height_m', nominal.get('min_body_height_m'), quality_high(nominal.get('min_body_height_m'), 0.55, 0.3), 'A', 'minimum measured torso height over the nominal run')]
    weights = (0.35, 0.25, 0.2, 0.2)
    return (weighted_mean(((item['score'], weight) for item, weight in zip(values, weights))), values)

def score_group_q(scenario_rows: list[dict[str, Any]]) -> tuple[float, list[dict[str, Any]]]:
    torque_ratio = max((finite(row.get('torque_max_abs_nm')) / max(finite(row.get('requested_inputs', {}).get('joint_torque_limit_nm')), 1e-09) for row in scenario_rows), default=math.nan)
    values = [metric('worst_height_ripple_m', maximum(scenario_rows, 'height_ripple_m'), quality_low(maximum(scenario_rows, 'height_ripple_m'), 0.18, 0.55), 'Q', 'largest peak-to-peak torso-height ripple'), metric('worst_abs_roll_rad', maximum(scenario_rows, 'max_abs_roll_rad'), quality_low(maximum(scenario_rows, 'max_abs_roll_rad'), 0.18, 0.65), 'Q', 'largest absolute torso roll'), metric('worst_abs_pitch_rad', maximum(scenario_rows, 'max_abs_pitch_rad'), quality_low(maximum(scenario_rows, 'max_abs_pitch_rad'), 0.2, 0.65), 'Q', 'largest absolute torso pitch'), metric('worst_lateral_drift_m', maximum(scenario_rows, 'lateral_drift_m'), quality_low(maximum(scenario_rows, 'lateral_drift_m'), 0.2, 0.9), 'Q', 'largest absolute lateral torso drift'), metric('worst_yaw_drift_rad', maximum(scenario_rows, 'yaw_drift_rad'), quality_low(maximum(scenario_rows, 'yaw_drift_rad'), 0.2, 0.9), 'Q', 'largest absolute yaw drift'), metric('worst_joint_angle_abs_rad', maximum(scenario_rows, 'joint_angle_max_abs_rad'), quality_low(maximum(scenario_rows, 'joint_angle_max_abs_rad'), 1.8, 2.8), 'Q', 'largest absolute measured joint angle'), metric('worst_joint_speed_abs_radps', maximum(scenario_rows, 'joint_speed_max_abs_radps'), quality_low(maximum(scenario_rows, 'joint_speed_max_abs_radps'), 10.0, 25.0), 'Q', 'largest absolute measured joint speed'), metric('worst_action_abs', maximum(scenario_rows, 'action_max_abs'), quality_low(maximum(scenario_rows, 'action_max_abs'), 1.0, 1.25), 'Q', 'largest normalized controller action'), metric('worst_torque_to_limit_ratio', torque_ratio, quality_low(torque_ratio, 1.01, 1.2), 'Q', 'largest applied torque divided by the scenario torque limit'), metric('worst_control_effort_rms_nm', maximum(scenario_rows, 'control_effort_rms_nm'), quality_low(maximum(scenario_rows, 'control_effort_rms_nm'), 6.0, 10.0), 'Q', 'largest eight-channel RMS joint-torque effort')]
    return (weighted_mean(((item['score'], 1.0) for item in values)), values)

def score_group_m(scenario_rows: list[dict[str, Any]], static_audit: dict[str, Any]) -> tuple[float, list[dict[str, Any]]]:
    values = [metric('dynamic_block_count', static_audit.get('dynamic_block_count'), quality_high(static_audit.get('dynamic_block_count'), 1.0, 0.0), 'M', 'existence of a connected dynamic mechanism; block count is not treated as a quality proxy'), metric('physical_joint_count', static_audit.get('physical_joint_count'), quality_high(static_audit.get('physical_joint_count'), 8.0, 3.0), 'M', 'physical multibody joint count'), metric('spatial_contact_count', static_audit.get('spatial_contact_count'), quality_high(static_audit.get('spatial_contact_count'), 4.0, 1.0), 'M', 'spatial foot-ground contact count'), metric('actuated_joint_count', static_audit.get('actuated_joint_count'), quality_high(static_audit.get('actuated_joint_count'), 8.0, 3.0), 'M', 'torque-actuated physical joint count'), metric('physical_sensor_count', static_audit.get('physical_sensor_count'), quality_high(static_audit.get('physical_sensor_count'), 12.0, 3.0), 'M', 'physical state or force sensor count'), metric('constant_or_workspace_output_count', static_audit.get('constant_or_workspace_output_count'), quality_low(static_audit.get('constant_or_workspace_output_count'), 0.0, 4.0), 'M', 'standardized outputs sourced directly from constants or replay'), metric('worst_body_kinematic_closure_rms_mps', maximum(scenario_rows, 'body_kinematic_closure_rms_mps'), quality_low(maximum(scenario_rows, 'body_kinematic_closure_rms_mps'), 0.03, 0.25), 'M', 'finite-difference body-position versus logged velocity closure'), metric('worst_action_torque_closure_relative_rms', maximum(scenario_rows, 'action_torque_closure_relative_rms'), quality_low(maximum(scenario_rows, 'action_torque_closure_relative_rms'), 0.02, 0.2), 'M', 'normalized-action to physical-torque closure'), metric('minimum_action_range', minimum(scenario_rows, 'action_range'), quality_high(minimum(scenario_rows, 'action_range'), 0.7, 0.05), 'M', 'smallest observed action range across scenarios'), metric('minimum_torque_range_nm', minimum(scenario_rows, 'torque_range_nm'), quality_high(minimum(scenario_rows, 'torque_range_nm'), 7.0, 0.5), 'M', 'smallest observed applied-torque range'), metric('minimum_four_foot_normal_force_fraction', minimum(scenario_rows, 'positive_normal_force_fraction_4'), quality_high(minimum(scenario_rows, 'positive_normal_force_fraction_4'), 0.22, 0.02), 'M', 'minimum positive-normal-force fraction among all four feet'), metric('minimum_contact_transitions_4', minimum(scenario_rows, 'min_contact_transitions_4'), quality_high(minimum(scenario_rows, 'min_contact_transitions_4'), 8.0, 1.0), 'M', 'minimum contact-state transition count among all four feet'), metric('minimum_landing_count_4', minimum(scenario_rows, 'minimum_landing_count_4'), quality_high(minimum(scenario_rows, 'minimum_landing_count_4'), 3.0, 0.0), 'M', 'minimum landing count among all four feet'), metric('minimum_friction_force_rms_n', minimum(scenario_rows, 'friction_force_rms_n'), quality_high(minimum(scenario_rows, 'friction_force_rms_n'), 0.5, 0.02), 'M', 'smallest measured spatial-contact friction-force RMS')]
    weights = (0.7, 1.0, 1.0, 1.0, 0.8, 0.8, 1.2, 1.3, 0.8, 0.8, 1.0, 0.8, 0.8, 0.7)
    return (weighted_mean(((item['score'], weight) for item, weight in zip(values, weights))), values)

def stress_scenario_score(row: dict[str, Any]) -> tuple[float, list[dict[str, Any]]]:
    scenario_id = str(row.get('id', 'unknown'))
    values = [metric(f'{scenario_id}_forward_displacement_m', row.get('forward_displacement_m'), quality_high(row.get('forward_displacement_m'), 1.5, 0.2), 'R', 'stress-scenario forward progress'), metric(f'{scenario_id}_positive_forward_fraction', row.get('positive_forward_fraction'), quality_high(row.get('positive_forward_fraction'), 0.75, 0.4), 'R', 'stress-scenario positive-forward-speed fraction'), metric(f'{scenario_id}_minimum_height_m', row.get('min_body_height_m'), quality_high(row.get('min_body_height_m'), 0.5, 0.25), 'R', 'stress-scenario upright-support height'), metric(f'{scenario_id}_attitude_envelope_rad', max(finite(row.get('max_abs_roll_rad')), finite(row.get('max_abs_pitch_rad'))), quality_low(max(finite(row.get('max_abs_roll_rad')), finite(row.get('max_abs_pitch_rad'))), 0.25, 0.8), 'R', 'worst stress-scenario roll or pitch magnitude'), metric(f'{scenario_id}_lateral_drift_m', row.get('lateral_drift_m'), quality_low(row.get('lateral_drift_m'), 0.4, 1.2), 'R', 'stress-scenario lateral drift'), metric(f'{scenario_id}_four_foot_force_fraction', row.get('positive_normal_force_fraction_4'), quality_high(row.get('positive_normal_force_fraction_4'), 0.18, 0.02), 'R', 'worst-foot positive normal-force fraction'), metric(f'{scenario_id}_minimum_contact_transitions', row.get('min_contact_transitions_4'), quality_high(row.get('min_contact_transitions_4'), 5.0, 0.0), 'R', 'worst-foot contact transitions'), metric(f'{scenario_id}_body_closure', row.get('body_kinematic_closure_rms_mps'), quality_low(row.get('body_kinematic_closure_rms_mps'), 0.08, 0.35), 'R', 'stress-scenario measured-body kinematic closure'), metric(f'{scenario_id}_action_torque_closure', row.get('action_torque_closure_relative_rms'), quality_low(row.get('action_torque_closure_relative_rms'), 0.05, 0.25), 'R', 'stress-scenario action-to-torque closure')]
    weights = (1.2, 0.8, 1.2, 1.0, 0.6, 1.0, 0.7, 0.8, 1.0)
    return (weighted_mean(((item['score'], weight) for item, weight in zip(values, weights))), values)

def score_group_r(rows: dict[str, dict[str, Any]]) -> tuple[float, list[dict[str, Any]], list[dict[str, Any]]]:
    details: list[dict[str, Any]] = []
    metrics: list[dict[str, Any]] = []
    for scenario_id in RANGE_SCENARIOS:
        score, scenario_metrics = stress_scenario_score(rows[scenario_id])
        details.append({'id': scenario_id, 'score': score})
        metrics.extend(scenario_metrics)
    return (min((detail['score'] for detail in details), default=0.0), metrics, details)

def score_group_d(rows: dict[str, dict[str, Any]]) -> tuple[float, list[dict[str, Any]], dict[str, Any]]:
    nominal = rows['nominal']
    friction = rows['friction_derated_pair']
    payload = rows['payload_heavy_pair']
    friction_deltas = {'friction_force_relative_delta': relative_delta(nominal.get('friction_force_rms_n'), friction.get('friction_force_rms_n')), 'forward_displacement_relative_delta': relative_delta(nominal.get('forward_displacement_m'), friction.get('forward_displacement_m')), 'control_effort_relative_delta': relative_delta(nominal.get('control_effort_rms_nm'), friction.get('control_effort_rms_nm'))}
    friction_effect = friction_deltas['friction_force_relative_delta']
    friction_causal_score = quality_high(friction_effect, 0.03, 0.01)
    friction_behavior_score, _ = stress_scenario_score(friction)
    friction_score = weighted_mean(((friction_causal_score, 0.35), (friction_behavior_score, 0.65)))
    payload_height_delta = abs(finite(payload.get('min_body_height_m')) - finite(nominal.get('min_body_height_m')))
    payload_height_relative_delta = payload_height_delta / max(abs(finite(nominal.get('min_body_height_m'))), 1e-09)
    payload_deltas = {'control_effort_relative_delta': relative_delta(nominal.get('control_effort_rms_nm'), payload.get('control_effort_rms_nm')), 'forward_displacement_relative_delta': relative_delta(nominal.get('forward_displacement_m'), payload.get('forward_displacement_m')), 'minimum_height_absolute_delta_m': payload_height_delta, 'minimum_height_relative_delta': payload_height_relative_delta}
    payload_effect = max(payload_deltas['control_effort_relative_delta'], payload_deltas['forward_displacement_relative_delta'], payload_deltas['minimum_height_relative_delta'])
    payload_causal_score = quality_high(payload_effect, 0.03, 0.01)
    payload_behavior_score, _ = stress_scenario_score(payload)
    payload_score = weighted_mean(((payload_causal_score, 0.35), (payload_behavior_score, 0.65)))
    comparisons = {'friction_pair': {'scenario_ids': ['nominal', 'friction_derated_pair'], **friction_deltas, 'effect_magnitude': friction_effect, 'causal_score': friction_causal_score, 'behavior_score': friction_behavior_score, 'score': friction_score}, 'payload_pair': {'scenario_ids': ['nominal', 'payload_heavy_pair'], **payload_deltas, 'effect_magnitude': payload_effect, 'causal_score': payload_causal_score, 'behavior_score': payload_behavior_score, 'score': payload_score}}
    metrics = [metric('friction_pair_response', comparisons['friction_pair']['effect_magnitude'], friction_score, 'D', 'measurable physical-friction ownership with useful locomotion retained; larger degradation is not rewarded'), metric('payload_pair_response', comparisons['payload_pair']['effect_magnitude'], payload_score, 'D', 'measurable payload ownership with useful locomotion retained; larger degradation is not rewarded')]
    return (weighted_mean(((friction_score, 0.5), (payload_score, 0.5))), metrics, comparisons)

def shortcut_findings(rows: dict[str, dict[str, Any]], static_audit: dict[str, Any], group_m: float, comparisons: dict[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    scenario_rows = list(rows.values())
    dynamic_blocks = finite(static_audit.get('dynamic_block_count'), 0.0)
    constant_outputs = finite(static_audit.get('constant_or_workspace_output_count'), 0.0)
    if dynamic_blocks < 1.0 or constant_outputs >= 2.0:
        findings.append({'id': 'static_or_replayed_outputs', 'reason': 'no connected dynamic state or multiple standardized outputs are direct constants/workspace replay'})
    topology = {'physical_joint_count': finite(static_audit.get('physical_joint_count'), 0.0), 'spatial_contact_count': finite(static_audit.get('spatial_contact_count'), 0.0), 'actuated_joint_count': finite(static_audit.get('actuated_joint_count'), 0.0), 'physical_sensor_count': finite(static_audit.get('physical_sensor_count'), 0.0)}
    missing_topology = [name for name, floor in (('physical_joint_count', 8.0), ('spatial_contact_count', 4.0), ('actuated_joint_count', 8.0), ('physical_sensor_count', 4.0)) if topology[name] < floor]
    if missing_topology:
        findings.append({'id': 'missing_articulated_multibody_mechanism', 'reason': 'insufficient topology: ' + ', '.join(missing_topology)})
    body_closure = maximum(scenario_rows, 'body_kinematic_closure_rms_mps')
    if not math.isfinite(body_closure) or body_closure > 0.25:
        findings.append({'id': 'disconnected_body_kinematics', 'reason': 'logged torso velocity is inconsistent with measured torso position dynamics'})
    action_closure = maximum(scenario_rows, 'action_torque_closure_relative_rms')
    action_range = minimum(scenario_rows, 'action_range')
    torque_range = minimum(scenario_rows, 'torque_range_nm')
    if not math.isfinite(action_closure) or action_closure > 0.2 or action_range < 0.05 or (torque_range < 0.5):
        findings.append({'id': 'disconnected_or_inactive_action_torque_path', 'reason': 'eight-channel actions do not causally close onto active physical joint torques'})
    normal_fraction = minimum(scenario_rows, 'positive_normal_force_fraction_4')
    transitions = minimum(scenario_rows, 'min_contact_transitions_4')
    landings = minimum(scenario_rows, 'minimum_landing_count_4')
    if normal_fraction <= 0.02 or transitions < 1.0 or landings < 1.0:
        findings.append({'id': 'missing_four_foot_contact_participation', 'reason': 'at least one foot lacks physical support/contact cycles'})
    friction_effect = finite(comparisons.get('friction_pair', {}).get('effect_magnitude'))
    if not math.isfinite(friction_effect) or friction_effect < 0.01:
        findings.append({'id': 'ineffective_friction_pair', 'reason': 'one-factor friction derating does not measurably change contact, effort, or body motion'})
    payload_effect = finite(comparisons.get('payload_pair', {}).get('effect_magnitude'))
    if not math.isfinite(payload_effect) or payload_effect < 0.01:
        findings.append({'id': 'ineffective_payload_pair', 'reason': 'one-factor torso-mass increase does not measurably change effort or body motion'})
    if group_m < 0.35:
        findings.append({'id': 'mechanism_group_failure', 'reason': 'mechanism and causal-closure group is too weak'})
    return findings

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = row_map(evidence.get('scenarios'))
    gate, gate_failures = gate_evidence(evidence, rows)
    static_audit = evidence.get('static_audit', {})
    if not isinstance(static_audit, dict):
        static_audit = {}
    if gate:
        group_a, metrics_a = score_group_a(rows['nominal'])
        group_q, metrics_q = score_group_q(list(rows.values()))
        group_m, metrics_m = score_group_m(list(rows.values()), static_audit)
        group_r, metrics_r, range_details = score_group_r(rows)
        group_d, metrics_d, comparisons = score_group_d(rows)
        comparisons['range_scenario_details'] = range_details
        groups = {'G': 1.0, 'A': group_a, 'Q': group_q, 'M': group_m, 'R': group_r, 'D': group_d}
        raw_total = 100.0 * sum((groups[group] * weight for group, weight in GROUP_WEIGHTS.items()))
        findings = shortcut_findings(rows, static_audit, group_m, comparisons)
        total = raw_total
        all_metrics = metrics_a + metrics_q + metrics_m + metrics_r + metrics_d
    else:
        groups = {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}
        raw_total = 0.0
        total = 0.0
        comparisons = {}
        findings = []
        all_metrics = []
    failures = list(gate_failures)
    failures.extend((f"{item['id']}: utility={item['score']:.3f}" for item in all_metrics if item['score'] < 0.35))
    failures.extend((item['id'] + ': ' + item['reason'] for item in findings))
    return {'schema': SCORE_SCHEMA, 'formal_id': FORMAL_ID, 'policy_id': POLICY_ID, 'threshold_configuration': THRESHOLD_CONFIGURATION, 'valid': gate, 'score_inputs_valid': gate, 'G': gate, 'groups': groups, 'group_weights': GROUP_WEIGHTS, 'raw_total': raw_total, 'total': total, 'score': total, 'metrics': all_metrics, 'paired_comparisons': comparisons, 'shortcut_findings': findings, 'failures': failures}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    evidence = read_json(args.evidence)
    result = score_evidence(evidence)
    write_json(args.output, result)
    print(f"F90_XROBO03_OFFLINE_SCORE total={result['total']:.6f} G={int(result['G'])}")
if __name__ == '__main__':
    main()
