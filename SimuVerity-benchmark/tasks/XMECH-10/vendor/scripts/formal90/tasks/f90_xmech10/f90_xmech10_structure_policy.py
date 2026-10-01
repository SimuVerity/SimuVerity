"""Pure-offline topology policy for XMECH-10 port-graph evidence current."""
from __future__ import annotations
from collections import defaultdict
from typing import Any

def _node_capabilities(graph: dict[str, Any]) -> dict[str, frozenset[str]]:
    result: dict[str, frozenset[str]] = {}
    for row in graph.get('nodes', []):
        if not isinstance(row, dict):
            continue
        node_id = str(row.get('id', ''))
        values = row.get('capabilities', [])
        if not node_id or node_id in result or (not isinstance(values, list)):
            continue
        result[node_id] = frozenset((str(value) for value in values))
    return result

def _edges(graph: dict[str, Any], known: set[str]) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    physical: dict[str, set[str]] = defaultdict(set)
    signal: dict[str, set[str]] = defaultdict(set)
    for row in graph.get('edges', []):
        if not isinstance(row, dict):
            continue
        left = str(row.get('from', ''))
        right = str(row.get('to', ''))
        kind = str(row.get('kind', ''))
        if left not in known or right not in known or left == right:
            continue
        if kind == 'physical':
            physical[left].add(right)
            physical[right].add(left)
        elif kind == 'signal':
            signal[left].add(right)
    return (physical, signal)

def _with_capability(nodes: dict[str, frozenset[str]], capability: str) -> set[str]:
    return {node_id for node_id, values in nodes.items() if capability in values}

def _arm_candidates(source: str, nodes: dict[str, frozenset[str]], physical: dict[str, set[str]], signal: dict[str, set[str]]) -> list[tuple[str, str, str, str, str, str]]:
    hbridges = _with_capability(nodes, 'hbridge')
    motors = _with_capability(nodes, 'motor')
    transmissions = _with_capability(nodes, 'transmission')
    joints = _with_capability(nodes, 'joint')
    sensors = _with_capability(nodes, 'sensor')
    controllers = _with_capability(nodes, 'controller')
    rows: list[tuple[str, str, str, str, str, str]] = []
    for hbridge in sorted(physical.get(source, set()) & hbridges):
        for motor in sorted(physical.get(hbridge, set()) & motors):
            for transmission in sorted(physical.get(motor, set()) & transmissions):
                for joint in sorted(physical.get(transmission, set()) & joints):
                    for sensor in sorted(physical.get(joint, set()) & sensors):
                        for controller in sorted(signal.get(sensor, set()) & controllers):
                            if hbridge in signal.get(controller, set()):
                                rows.append((hbridge, motor, transmission, joint, sensor, controller))
    return rows

def _maximum_disjoint_paths(rows: list[tuple[str, ...]], used: frozenset[str]=frozenset()) -> list[tuple[str, ...]]:
    if not rows:
        return []
    best: list[tuple[str, ...]] = []
    for index, row in enumerate(rows):
        row_nodes = frozenset(row)
        if row_nodes & used:
            continue
        tail = _maximum_disjoint_paths(rows[index + 1:], used | row_nodes)
        candidate = [row, *tail]
        if len(candidate) > len(best):
            best = candidate
    return best

def _finger_candidates(nodes: dict[str, frozenset[str]], physical: dict[str, set[str]], signal: dict[str, set[str]]) -> list[tuple[str, str, str, str, str]]:
    joints = _with_capability(nodes, 'finger_joint')
    friction = _with_capability(nodes, 'friction')
    loads = _with_capability(nodes, 'electrical_load')
    sensors = _with_capability(nodes, 'sensor')
    controllers = _with_capability(nodes, 'controller')
    rows: list[tuple[str, str, str, str, str]] = []
    for joint in sorted(joints):
        for friction_node in sorted(physical.get(joint, set()) & friction):
            for load in sorted(physical.get(friction_node, set()) & loads):
                for sensor in sorted(physical.get(joint, set()) & sensors):
                    for controller in sorted(signal.get(sensor, set()) & controllers):
                        if load in signal.get(controller, set()):
                            rows.append((joint, friction_node, load, sensor, controller))
    return rows

def _contact_path(nodes: dict[str, frozenset[str]], physical: dict[str, set[str]]) -> bool:
    payloads = _with_capability(nodes, 'free_payload')
    contacts = _with_capability(nodes, 'compliant_contact')
    grippers = _with_capability(nodes, 'gripper_body')
    return any((contact in physical.get(payload, set()) and bool(physical.get(contact, set()) & grippers) for payload in payloads for contact in contacts))

def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    """Validate connected capability paths without candidate names or positions."""
    nodes = _node_capabilities(graph)
    physical, signal = _edges(graph, set(nodes))
    best_arm: list[tuple[str, ...]] = []
    best_source = ''
    for source in sorted(_with_capability(nodes, 'dc_source')):
        selected = _maximum_disjoint_paths(_arm_candidates(source, nodes, physical, signal))
        if len(selected) > len(best_arm):
            best_arm = selected
            best_source = source
    finger_paths = _maximum_disjoint_paths([tuple(row) for row in _finger_candidates(nodes, physical, signal)])
    contact = _contact_path(nodes, physical)
    checks = {'five_connected_arm_axis_paths': len(best_arm) >= 5, 'two_connected_finger_paths': len(finger_paths) >= 2, 'compliant_contact_path': contact}
    return {'schema': 'simuverity.f90-xmech10-structure-policy.v1', 'qualified': all(checks.values()), 'arm_axis_path_count': len(best_arm), 'finger_path_count': len(finger_paths), 'compliant_contact_path': contact, 'checks': checks, 'failures': [name for name, passed in checks.items() if not passed]}
