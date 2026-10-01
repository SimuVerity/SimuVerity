"""XMECH-03 no-cap scorer with candidate-independent root-level topology recovery."""
from __future__ import annotations
import argparse
import json
import math
from collections import defaultdict, deque
from pathlib import Path
from typing import Any
from xml.etree import ElementTree
from zipfile import ZipFile
import f90_xmech03_group_aggregation as GROUP_SCORING
TASK_DIR = Path(__file__).resolve().parent
SCORING_CORE_PATH = TASK_DIR / 'f90_xmech03_group_aggregation.py'
METRICS_PATH = TASK_DIR / 'f90_xmech03_structure_scoring.py'
GROUPS = tuple(GROUP_SCORING.WEIGHTS)

def _local_tag(element: ElementTree.Element) -> str:
    return element.tag.rsplit('}', 1)[-1]

def _line_endpoints(line: ElementTree.Element) -> list[tuple[str, str, str]]:
    endpoints: list[tuple[str, str, str]] = []
    for node in line.iter():
        if _local_tag(node) != 'P' or not node.text:
            continue
        role = node.attrib.get('Name', '')
        if role not in {'Src', 'Dst'}:
            continue
        value = node.text.strip()
        if '#' not in value:
            continue
        sid, port = value.split('#', 1)
        if sid and port:
            endpoints.append((role, sid, port))
    return endpoints

def root_level_topology(model_path: Path) -> dict[str, Any]:
    with ZipFile(model_path) as archive:
        system = ElementTree.fromstring(archive.read('simulink/systems/system_root.xml'))
    physical_ports: dict[str, set[str]] = defaultdict(set)
    physical_graph: dict[str, set[str]] = defaultdict(set)
    signal_graph: dict[str, set[str]] = defaultdict(set)
    signal_inputs: dict[str, int] = defaultdict(int)
    signal_outputs: dict[str, int] = defaultdict(int)
    for line in (node for node in system.iter() if _local_tag(node) == 'Line'):
        endpoints = _line_endpoints(line)
        if line.attrib.get('LineType') == 'Connection':
            block_ids = [sid for _, sid, _ in endpoints]
            for _, sid, port in endpoints:
                physical_ports[sid].add(port)
            for left in block_ids:
                for right in block_ids:
                    if left != right:
                        physical_graph[left].add(right)
        else:
            sources = [sid for role, sid, _ in endpoints if role == 'Src']
            destinations = [sid for role, sid, _ in endpoints if role == 'Dst']
            for source in sources:
                signal_outputs[source] += 1
                for destination in destinations:
                    signal_graph[source].add(destination)
                    signal_inputs[destination] += 1
    components: list[set[str]] = []
    unseen = set(physical_ports)
    while unseen:
        start = next(iter(unseen))
        component = {start}
        pending = [start]
        unseen.remove(start)
        while pending:
            current = pending.pop()
            for neighbor in physical_graph[current]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    component.add(neighbor)
                    pending.append(neighbor)
        components.append(component)
    largest = max(components, key=len, default=set())
    branch_count = sum((len(physical_ports[node]) >= 3 for node in largest))
    terminal_count = sum((len(physical_ports[node]) == 1 for node in largest))
    measurement_bridges = [node for node in largest if signal_outputs[node] > 0]
    control_bridges = [node for node in largest if signal_inputs[node] > 0]
    feedback_paths = 0
    for source in measurement_bridges:
        reachable = {source}
        pending: deque[str] = deque([source])
        while pending:
            current = pending.popleft()
            for neighbor in signal_graph[current]:
                if neighbor not in reachable:
                    reachable.add(neighbor)
                    pending.append(neighbor)
        feedback_paths += sum((target in reachable for target in control_bridges))
    connected_gate = len(largest) >= 8 and branch_count >= 2 and (terminal_count >= 2)
    feedback_gate = feedback_paths >= 1
    return {'physical_block_count': len(physical_ports), 'largest_connected_physical_component_blocks': len(largest), 'parallel_or_branching_physical_nodes': branch_count, 'physical_terminal_nodes': terminal_count, 'measurement_bridge_nodes': len(measurement_bridges), 'controlled_physical_bridge_nodes': len(control_bridges), 'measurement_to_control_signal_paths': feedback_paths, 'connected_dual_path_gate': connected_gate, 'feedback_connectivity_gate': feedback_gate, 'basis': 'root-system SLX conserving-connection and directed-signal graph'}

def _compatibility(evidence_path: Path, evidence: dict[str, Any]) -> dict[str, Any]:
    static = evidence.get('static_audit', {})
    if static.get('implementation_gate') is True:
        return {'applied': False, 'reason': 'existing_candidate_independent_audit_passed', 'root_level_topology': None}
    model_path = Path(str(evidence.get('model_path', '')))
    if not model_path.is_file():
        return {'applied': False, 'reason': 'candidate_model_unavailable', 'root_level_topology': None}
    try:
        topology = root_level_topology(model_path)
    except (KeyError, OSError, ValueError) as error:
        return {'applied': False, 'reason': f'root_level_topology_unavailable:{type(error).__name__}', 'root_level_topology': None}
    qualifies = bool(topology['connected_dual_path_gate'] and topology['feedback_connectivity_gate'])
    return {'applied': qualifies, 'reason': 'root_level_generic_connectivity_recovered' if qualifies else 'root_level_generic_connectivity_did_not_qualify', 'root_level_topology': topology}

def _json_finite(value: Any) -> Any:
    """Keep diagnostic sentinels JSON-compliant without changing score inputs."""
    if isinstance(value, dict):
        return {key: _json_finite(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_finite(item) for item in value]
    if isinstance(value, float) and (not math.isfinite(value)):
        return None
    return value

def score(evidence_path: Path) -> dict[str, Any]:
    evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    compatibility = _compatibility(evidence_path, evidence)
    original_qualification = GROUP_SCORING.METRICS.qualification
    if compatibility['applied']:
        topology = compatibility['root_level_topology']

        def compatible_qualification(current_evidence: dict[str, Any], failures: list[str]) -> tuple[bool, list[str]]:
            static = current_evidence.setdefault('static_audit', {})
            static['generic_connectivity_audit'] = topology
            static['connected_dual_path_gate'] = True
            static['feedback_connectivity_gate'] = True
            static['implementation_gate'] = bool(static.get('reference_configuration_gate', True))
            return original_qualification(current_evidence, failures)
        GROUP_SCORING.METRICS.qualification = compatible_qualification
    try:
        result = GROUP_SCORING.score(evidence_path)
    finally:
        GROUP_SCORING.METRICS.qualification = original_qualification
    if not bool(result.get('G')) and (not isinstance(result.get('groups'), dict)):
        result['groups'] = {name: 0.0 for name in GROUPS}
    result['schema'] = 'simuverity.f90-xmech03-score.v1'
    result['policy_id'] = 'simuverity-101-v1:f90-xmech-03:scoring'
    result['connectivity_compatibility'] = compatibility
    result['post_total_cap_or_floor'] = False
    return _json_finite(result)

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = score(args.evidence)
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + '\n', encoding='utf-8')
    print(text)
if __name__ == '__main__':
    main()
