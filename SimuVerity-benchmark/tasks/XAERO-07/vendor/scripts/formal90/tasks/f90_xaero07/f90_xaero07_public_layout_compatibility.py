"""XAERO-07 scorer for canonical and documented partial public layouts."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from typing import Any
import f90_xaero07_component_availability as component_availability
import f90_xaero07_group_aggregation as group_aggregation
TASK_ID = component_availability.TASK_ID
PUBLIC_WIDTHS = {'flight_distance': 1, 'battery_state': 3, 'motor_current': 1, 'low_voltage_load_power': 3}
SOURCE_WIDTHS = {'flight_distance': 1, 'battery_state': 3, 'motor_current': 1, 'low_voltage_load_power': 1}

def _identity_ok(log: dict[str, Any], width: int, canonical: bool) -> bool:
    availability = log.get('availability')
    sources = log.get('sources')
    if canonical and availability is None and (sources is None):
        return True
    if isinstance(availability, bool) and width == 1:
        mask = [availability]
    elif isinstance(availability, list) and len(availability) == width:
        mask = [item is True for item in availability]
    else:
        return False
    if canonical and (not all(mask)):
        return False
    return width == 1 and isinstance(sources, str) or (isinstance(sources, list) and len(sources) == width)

def _uses_partial_public_layout(evidence: dict[str, Any]) -> bool:
    """Recognize the documented partial layout from its public signal contract."""
    scenarios = component_availability.core.scenario_map(evidence)
    if not scenarios:
        return False
    for scenario in scenarios.values():
        logs = scenario.get('logs', {})
        battery = logs.get('battery_state', {})
        loads = logs.get('low_voltage_load_power', {})
        if int(battery.get('channels', 0)) != 3 or int(loads.get('channels', 0)) != 1:
            return False
        availability = battery.get('availability')
        if availability != [True, False, False]:
            return False
    return True

def gate(evidence: dict[str, Any], path: Path) -> tuple[bool, list[str], dict[str, Any]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('wrong_task_id')
    for key in ('load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'runtime_model_unchanged', 'evidence_complete'):
        if evidence.get(key) is not True:
            failures.append(key)
    profile = evidence.get('compatibility_profile')
    canonical = False
    if not profile:
        canonical = evidence.get('schema') == 'simuverity.f90-xaero07-fixed-evidence.v1'
        widths = PUBLIC_WIDTHS
        if not canonical:
            failures.append('unsupported_public_identity_profile')
    elif _uses_partial_public_layout(evidence):
        widths = SOURCE_WIDTHS
    elif profile.get('id') == 'xaero07-public-extra-derived' and profile.get('raw_widths') == [1, 4, 1, 4] and (profile.get('semantic_mapping_qualified') is True):
        canonical = True
        widths = PUBLIC_WIDTHS
    else:
        widths = PUBLIC_WIDTHS
        failures.append('unsupported_public_identity_profile')
    audit = evidence.get('static_audit', {})
    if audit.get('core_path_qualified') is not True:
        failures.append('anti_cheat:connected_dynamic_core')
    if evidence.get('open_plant_not_fcc_or_ndi') is not True:
        failures.append('anti_cheat:invalid_closed_loop_claim')
    scenarios = component_availability.core.scenario_map(evidence)
    if list(scenarios) != component_availability.SCENARIOS:
        failures.append('scenario_set_or_order')
    for sid in component_availability.SCENARIOS:
        scenario = scenarios.get(sid)
        if not scenario or scenario.get('valid') is not True:
            failures.append(f'{sid}:invalid')
            continue
        logs = scenario.get('logs', {})
        if set(logs) != component_availability.LOGS:
            failures.append(f'{sid}:output_contract')
            continue
        for name, width in widths.items():
            log = logs[name]
            if int(log.get('channels', 0)) != width or int(log.get('samples', 0)) < 100:
                failures.append(f'{sid}:{name}_shape')
            if not _identity_ok(log, width, canonical):
                failures.append(f'{sid}:{name}_identity_map')
        data_path = path.parent / scenario.get('data_file', '')
        if not data_path.is_file():
            failures.append(f'{sid}:missing_data_file')
        if scenario.get('metrics', {}).get('all_finite') is not True:
            failures.append(f'{sid}:nonfinite')
    axes = component_availability.core.axes(scenarios)
    return (not failures, failures, axes)

def score(evidence: dict[str, Any], path: Path, evidence_role: str='candidate') -> dict[str, Any]:
    original_gate = component_availability.gate
    component_availability.gate = gate
    try:
        result = group_aggregation.score(evidence, path, evidence_role=evidence_role)
    finally:
        component_availability.gate = original_gate
    result['schema'] = 'simuverity.f90-xaero07-offline-score.v1'
    result['public_semantic_contract'] = {'identity_specific_routes': False, 'canonical_profile': 'behaviorally_proven_extra_derived_channels', 'partial_profile': 'public_signal_availability_layout', 'post_total_cap': 'none'}
    return result

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('output_dir', type=Path)
    parser.add_argument('--evidence-role', choices=('candidate', 'reference'), default='candidate')
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    result = score(evidence, args.evidence, evidence_role=args.evidence_role)
    (args.output_dir / 'score.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()
