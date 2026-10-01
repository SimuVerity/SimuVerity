#!/usr/bin/env python3
"""Implementation-neutral graph policy for XMECH-04 evidence.

The policy consumes opaque node identities, trusted semantic capabilities, and
real port edges emitted by the current MATLAB extractor.  Display names and canvas
coordinates are deliberately ignored.
"""

from __future__ import annotations

from collections import deque
from typing import Any, Iterable, Mapping


TRUSTED_PROVENANCE = {
    "trusted_builtin",
    "resolved_library_link",
    "trusted_builtin_or_resolved_library",
    "public_interface_contract",
}


def _capabilities(node: Mapping[str, Any]) -> set[str]:
    value = node.get("capabilities", [])
    if isinstance(value, str):
        values: Iterable[Any] = [value]
    elif isinstance(value, list):
        values = value
    else:
        return set()
    if str(node.get("capability_provenance", "")) not in TRUSTED_PROVENANCE:
        return set()
    return {str(item) for item in values if isinstance(item, str) and item}


def _adjacency(
    edges: list[Mapping[str, Any]], kind: str, *, undirected: bool = False
) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for edge in edges:
        if str(edge.get("kind", "")) != kind:
            continue
        left = str(edge.get("from", ""))
        right = str(edge.get("to", ""))
        if not left or not right or left == right:
            continue
        result.setdefault(left, set()).add(right)
        if undirected:
            result.setdefault(right, set()).add(left)
    return result


def _reachable(adjacency: Mapping[str, set[str]], start: str) -> set[str]:
    seen = {start}
    pending = deque([start])
    while pending:
        current = pending.popleft()
        for target in adjacency.get(current, set()):
            if target in seen:
                continue
            seen.add(target)
            pending.append(target)
    return seen


def _nodes_with(
    node_caps: Mapping[str, set[str]], capability: str
) -> set[str]:
    return {node_id for node_id, caps in node_caps.items() if capability in caps}


def _any_reachable(
    adjacency: Mapping[str, set[str]], starts: Iterable[str], targets: set[str]
) -> set[str]:
    reached: set[str] = set()
    for start in starts:
        reached.update(_reachable(adjacency, start) & targets)
    return reached


def evaluate_structure_graph(graph: Mapping[str, Any]) -> dict[str, Any]:
    """Return fail-closed six-joint closed-loop and log-lineage facts."""

    raw_nodes = graph.get("nodes", [])
    raw_edges = graph.get("edges", [])
    if not isinstance(raw_nodes, list) or not isinstance(raw_edges, list):
        raw_nodes, raw_edges = [], []
    nodes = {
        str(node.get("id", "")): node
        for node in raw_nodes
        if isinstance(node, Mapping) and str(node.get("id", ""))
    }
    edges = [edge for edge in raw_edges if isinstance(edge, Mapping)]
    node_caps = {node_id: _capabilities(node) for node_id, node in nodes.items()}
    signal = _adjacency(edges, "signal")
    physical = _adjacency(edges, "physical", undirected=True)

    joints = _nodes_with(node_caps, "revolute_joint") & _nodes_with(
        node_caps, "computed_motion"
    )
    sensors = _nodes_with(node_caps, "joint_position_sensor") & _nodes_with(
        node_caps, "joint_velocity_sensor"
    )
    controllers = _nodes_with(node_caps, "feedback_controller")
    limiters = _nodes_with(node_caps, "torque_limiter")
    actuators = _nodes_with(node_caps, "torque_actuator")
    state_sinks = _nodes_with(node_caps, "public_joint_state_sink")
    torque_sinks = _nodes_with(node_caps, "public_joint_torque_sink")
    pose_sinks = _nodes_with(node_caps, "public_pose_sink")
    pose_sensors = _nodes_with(node_caps, "physical_pose_sensor")
    rigid_bodies = _nodes_with(node_caps, "rigid_body")

    path_rows: list[dict[str, Any]] = []
    used_sensors: set[str] = set()
    used_actuators: set[str] = set()
    for joint in sorted(joints):
        # A sensor/actuator belongs to a joint only through the joint's direct
        # physical port neighborhood.  Whole-component reachability would let
        # one channel impersonate all six members of a serial mechanism.
        direct_physical = set(physical.get(joint, set())) | {joint}
        joint_sensors = direct_physical & sensors
        joint_actuators = direct_physical & actuators
        feedback_sensors = {
            sensor
            for sensor in joint_sensors
            if _any_reachable(signal, [sensor], controllers)
        }
        state_sources = {
            sensor
            for sensor in feedback_sensors
            if _any_reachable(signal, [sensor], state_sinks)
        }
        valid_pairs: list[tuple[str, str]] = []
        for sensor in feedback_sensors:
            reached_controllers = _any_reachable(signal, [sensor], controllers)
            reached_limiters = _any_reachable(signal, reached_controllers, limiters)
            for limiter in reached_limiters:
                reached_actuators = _any_reachable(signal, [limiter], actuators)
                if not _any_reachable(signal, [limiter], torque_sinks):
                    continue
                for actuator in reached_actuators & joint_actuators:
                    valid_pairs.append((sensor, actuator))
        qualified_path = bool(valid_pairs and state_sources)
        if qualified_path:
            sensor, actuator = valid_pairs[0]
            used_sensors.add(sensor)
            used_actuators.add(actuator)
        else:
            sensor, actuator = "", ""
        path_rows.append(
            {
                "joint_id": joint,
                "qualified": qualified_path,
                "sensor_id": sensor,
                "actuator_id": actuator,
                "state_log_lineage": bool(state_sources),
                "torque_log_lineage": bool(valid_pairs),
            }
        )

    joint_state_lineage_count = sum(
        bool(row["qualified"] and row["state_log_lineage"]) for row in path_rows
    )
    joint_torque_lineage_count = sum(
        bool(row["qualified"] and row["torque_log_lineage"]) for row in path_rows
    )
    closed_loop_count = sum(bool(row["qualified"]) for row in path_rows)

    serial_physical_chain_present = False
    if len(joints) == 6:
        first_joint = next(iter(joints))
        component = _reachable(physical, first_joint)
        serial_physical_chain_present = bool(
            joints.issubset(component) and len(component & rigid_bodies) >= 7
        )

    pose_lineage_present = False
    for pose_sensor in pose_sensors:
        component = _reachable(physical, pose_sensor)
        if joints.issubset(component) and _any_reachable(
            signal, [pose_sensor], pose_sinks
        ):
            pose_lineage_present = True
            break
    if not pose_lineage_present and pose_sinks:
        # A calculated pose is legal when every measured joint lineage reaches
        # the public pose sink; no hidden DH/sign convention is assumed.
        pose_lineage_present = bool(
            len(joints) == 6
            and all(_any_reachable(signal, [sensor], pose_sinks) for sensor in used_sensors)
        )

    checks = {
        "six_revolute_joints": len(joints) == 6,
        "serial_physical_chain": serial_physical_chain_present,
        "six_closed_loop_joint_paths": closed_loop_count == 6,
        "six_independent_measurement_channels": len(used_sensors) == 6,
        "six_independent_actuator_channels": len(used_actuators) == 6,
        "six_joint_state_log_lineages": joint_state_lineage_count == 6,
        "six_joint_torque_log_lineages": joint_torque_lineage_count == 6,
        "physical_pose_log_lineage": pose_lineage_present,
    }
    failures = [name for name, passed in checks.items() if not passed]
    return {
        "qualified": not failures,
        "checks": checks,
        "failure_reasons": failures,
        "revolute_joint_count": len(joints),
        "closed_loop_joint_path_count": closed_loop_count,
        "independent_sensor_count": len(used_sensors),
        "independent_actuator_count": len(used_actuators),
        "joint_state_lineage_count": joint_state_lineage_count,
        "joint_torque_lineage_count": joint_torque_lineage_count,
        "pose_lineage_present": pose_lineage_present,
        "serial_physical_chain_present": serial_physical_chain_present,
        "joint_paths": path_rows,
        "display_names_used": False,
        "canvas_coordinates_used": False,
    }
