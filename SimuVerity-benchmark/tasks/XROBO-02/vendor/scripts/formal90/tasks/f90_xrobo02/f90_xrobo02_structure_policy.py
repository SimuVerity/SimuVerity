#!/usr/bin/env python3
"""Implementation-neutral XROBO-02 structure decision from a port graph."""

from __future__ import annotations

from collections import defaultdict, deque
from typing import Any, Iterable


OUTPUT_WIDTHS = {
    "joint_state": 28,
    "end_effector_pose": 12,
    "joint_torque": 14,
    "coordination_state": 4,
}
INPUT_WIDTHS = {
    "left_target_rad": 7,
    "right_target_rad": 7,
    "move_duration": 1,
    "shared_payload_mass": 1,
    "torque_limit_scale": 1,
    "disturbance_torque_nm": 14,
    "disturbance_start": 1,
}
DYNAMIC_TYPES = {
    "integrator",
    "discreteintegrator",
    "statespace",
    "discretestatespace",
    "transferfcn",
    "discretetransferfcn",
}
ROUTING_TYPES = {
    "buscreator",
    "busselector",
    "datatypeconversion",
    "demux",
    "from",
    "goto",
    "inport",
    "mux",
    "outport",
    "ratetransition",
    "reshape",
    "selector",
    "signalconversion",
}
SOURCE_TYPES = {
    "clock",
    "constant",
    "fromworkspace",
    "ground",
    "inport",
    "repeatingsequence",
    "signalbuilder",
    "signaleditor",
    "step",
}
SINK_TYPES = {"scope", "terminator", "toworkspace"}


def _strings(value: Any) -> tuple[str, ...]:
    if isinstance(value, str):
        return (value,)
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return tuple(value)
    return ()


def _widths(value: Any, count: int) -> tuple[int, ...]:
    if isinstance(value, (int, float)) and count == 1:
        value = [value]
    if not isinstance(value, list) or len(value) != count:
        return ()
    widths: list[int] = []
    for item in value:
        if not isinstance(item, (int, float)) or int(item) != item or int(item) < 1:
            return ()
        widths.append(int(item))
    return tuple(widths)


def _normalize_edges(value: Any) -> tuple[list[tuple[str, str, str]], bool]:
    if not isinstance(value, list):
        return [], False
    if value and all(isinstance(item, str) for item in value):
        if len(value) % 3:
            return [], False
        row_count = len(value) // 3
        value = [
            [value[index], value[row_count + index], value[2 * row_count + index]]
            for index in range(row_count)
        ]
    rows: list[tuple[str, str, str]] = []
    for row in value:
        if isinstance(row, dict):
            source = row.get("source_port_id")
            target = row.get("target_port_id")
            kind = row.get("kind", "")
        elif isinstance(row, list) and len(row) == 3:
            source, target, kind = row
        else:
            return [], False
        if not all(isinstance(item, str) and item for item in (source, target, kind)):
            return [], False
        rows.append((source, target, kind))
    return rows, True


def _graph_parts(graph: dict[str, Any]):
    raw_nodes = graph.get("nodes", [])
    if isinstance(raw_nodes, dict):
        raw_nodes = [raw_nodes]
    if not isinstance(raw_nodes, list):
        raw_nodes = []
    nodes: dict[str, dict[str, Any]] = {}
    owners: dict[str, str] = {}
    port_widths: dict[str, int] = {}
    valid = True
    for row in raw_nodes:
        if not isinstance(row, dict):
            valid = False
            continue
        node_id = row.get("id")
        inputs = _strings(row.get("input_ports", []))
        outputs = _strings(row.get("output_ports", []))
        input_widths = _widths(row.get("input_widths", []), len(inputs))
        output_widths = _widths(row.get("output_widths", []), len(outputs))
        if (
            not isinstance(node_id, str)
            or not node_id
            or node_id in nodes
            or len(set(inputs + outputs)) != len(inputs + outputs)
            or (inputs and not input_widths)
            or (outputs and not output_widths)
        ):
            valid = False
            continue
        nodes[node_id] = row
        for port, width in zip(inputs + outputs, input_widths + output_widths):
            if port in owners:
                valid = False
            owners[port] = node_id
            port_widths[port] = width
    edges, edges_valid = _normalize_edges(graph.get("edges", []))
    adjacency: dict[str, set[str]] = defaultdict(set)
    for source, target, _ in edges:
        if source not in owners or target not in owners:
            valid = False
            continue
        adjacency[source].add(target)
    return nodes, owners, port_widths, adjacency, valid and edges_valid


def _node_type(row: dict[str, Any]) -> str:
    return str(row.get("block_type", "")).lower()


def _ports(row: dict[str, Any], field: str) -> tuple[str, ...]:
    return _strings(row.get(field, []))


def _path(
    starts: Iterable[str],
    targets: Iterable[str],
    adjacency: dict[str, set[str]],
    owners: dict[str, str],
    blocked_nodes: set[str] | None = None,
    routing_only: bool = False,
    nodes: dict[str, dict[str, Any]] | None = None,
) -> list[str]:
    starts = tuple(port for port in starts if port in owners)
    target_set = {port for port in targets if port in owners}
    blocked_nodes = blocked_nodes or set()
    if not starts or not target_set:
        return []
    queue = deque(starts)
    previous: dict[str, str | None] = {port: None for port in starts}
    while queue:
        port = queue.popleft()
        if port in target_set:
            result: list[str] = []
            while port is not None:
                result.append(port)
                port = previous[port]
            return list(reversed(result))
        for target in adjacency.get(port, ()):
            if target in previous or owners[target] in blocked_nodes:
                continue
            if routing_only and target not in target_set:
                owner = owners[target]
                if nodes is None or _node_type(nodes[owner]) not in ROUTING_TYPES:
                    continue
            previous[target] = port
            queue.append(target)
    return []


def _routing_path(starts, targets, adjacency, owners, nodes) -> list[str]:
    return _path(
        starts,
        targets,
        adjacency,
        owners,
        routing_only=True,
        nodes=nodes,
    )


def _source_rows(graph: dict[str, Any], owners: dict[str, str], widths: dict[str, int]):
    raw = graph.get("public_input_source_ports", {})
    if not isinstance(raw, dict):
        return {}, False
    result: dict[str, tuple[str, ...]] = {}
    valid = True
    for name, expected_width in INPUT_WIDTHS.items():
        ports = _strings(raw.get(name, []))
        if not ports or any(port not in owners or widths.get(port) != expected_width for port in ports):
            valid = False
        result[name] = ports
    return result, valid


def _output_rows(graph: dict[str, Any], owners: dict[str, str], widths: dict[str, int]):
    raw = graph.get("public_output_bindings", {})
    if not isinstance(raw, dict):
        return {}, False
    result: dict[str, str] = {}
    valid = True
    for name, expected_width in OUTPUT_WIDTHS.items():
        row = raw.get(name)
        if not isinstance(row, dict):
            valid = False
            continue
        anchor = row.get("anchor_port_id")
        declared = row.get("compiled_width")
        if (
            not isinstance(anchor, str)
            or anchor not in owners
            or widths.get(anchor) != expected_width
            or declared != expected_width
        ):
            valid = False
            continue
        result[name] = anchor
    return result, valid and len(result) == len(OUTPUT_WIDTHS)


def _transform_candidates(nodes: dict[str, dict[str, Any]]) -> list[str]:
    return [
        node_id
        for node_id, row in nodes.items()
        if _node_type(row) not in DYNAMIC_TYPES | ROUTING_TYPES | SOURCE_TYPES | SINK_TYPES
        and _ports(row, "input_ports")
        and _ports(row, "output_ports")
    ]


def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(graph, dict):
        graph = {}
    nodes, owners, widths, adjacency, graph_valid = _graph_parts(graph)
    sources, sources_valid = _source_rows(graph, owners, widths)
    outputs, outputs_valid = _output_rows(graph, owners, widths)
    transforms = _transform_candidates(nodes)

    state_witnesses: list[dict[str, Any]] = []
    dynamic_nodes = [
        node_id for node_id, row in nodes.items() if _node_type(row) in DYNAMIC_TYPES
    ]
    for velocity_id in dynamic_nodes:
        velocity = nodes[velocity_id]
        velocity_inputs = _ports(velocity, "input_ports")
        velocity_outputs = _ports(velocity, "output_ports")
        if not velocity_inputs or not velocity_outputs or widths.get(velocity_outputs[0]) != 14:
            continue
        for position_id in dynamic_nodes:
            if position_id == velocity_id:
                continue
            position = nodes[position_id]
            position_inputs = _ports(position, "input_ports")
            position_outputs = _ports(position, "output_ports")
            if not position_inputs or not position_outputs or widths.get(position_outputs[0]) != 14:
                continue
            integration_path = _routing_path(
                velocity_outputs, position_inputs, adjacency, owners, nodes
            )
            if not integration_path:
                continue
            state_path_q = _routing_path(
                position_outputs,
                (outputs.get("joint_state", ""),),
                adjacency,
                owners,
                nodes,
            )
            state_path_qd = _routing_path(
                velocity_outputs,
                (outputs.get("joint_state", ""),),
                adjacency,
                owners,
                nodes,
            )
            if state_path_q and state_path_qd:
                state_witnesses.append(
                    {
                        "velocity_state_node": velocity_id,
                        "position_state_node": position_id,
                        "velocity_to_position": integration_path,
                        "position_to_joint_state": state_path_q,
                        "velocity_to_joint_state": state_path_qd,
                    }
                )

    torque_witnesses: list[dict[str, Any]] = []
    pose_witnesses: list[dict[str, Any]] = []
    for state in state_witnesses:
        velocity_id = state["velocity_state_node"]
        position_id = state["position_state_node"]
        velocity = nodes[velocity_id]
        position = nodes[position_id]
        qd_inputs = _ports(velocity, "input_ports")
        qd_outputs = _ports(velocity, "output_ports")
        q_outputs = _ports(position, "output_ports")

        for plant_id in transforms:
            plant = nodes[plant_id]
            plant_inputs = _ports(plant, "input_ports")
            plant_outputs = _ports(plant, "output_ports")
            acceleration_path = _routing_path(
                plant_outputs, qd_inputs, adjacency, owners, nodes
            )
            q_to_plant = _routing_path(q_outputs, plant_inputs, adjacency, owners, nodes)
            qd_to_plant = _routing_path(qd_outputs, plant_inputs, adjacency, owners, nodes)
            disturbance_to_plant = _path(
                sources.get("disturbance_torque_nm", ()),
                plant_inputs,
                adjacency,
                owners,
                {position_id, velocity_id},
            )
            payload_to_plant = _path(
                sources.get("shared_payload_mass", ()),
                plant_inputs,
                adjacency,
                owners,
                {position_id, velocity_id},
            )
            if not all((acceleration_path, q_to_plant, qd_to_plant, disturbance_to_plant, payload_to_plant)):
                continue

            for controller_id in transforms:
                if controller_id == plant_id:
                    continue
                controller = nodes[controller_id]
                controller_inputs = _ports(controller, "input_ports")
                controller_outputs = _ports(controller, "output_ports")
                if not any(widths.get(port) == 14 for port in controller_outputs):
                    continue
                torque_to_plant = _routing_path(
                    controller_outputs, plant_inputs, adjacency, owners, nodes
                )
                torque_to_log = _routing_path(
                    controller_outputs,
                    (outputs.get("joint_torque", ""),),
                    adjacency,
                    owners,
                    nodes,
                )
                q_feedback = _routing_path(q_outputs, controller_inputs, adjacency, owners, nodes)
                qd_feedback = _routing_path(qd_outputs, controller_inputs, adjacency, owners, nodes)
                target_left = _path(
                    sources.get("left_target_rad", ()),
                    controller_inputs,
                    adjacency,
                    owners,
                    {plant_id, position_id, velocity_id},
                )
                target_right = _path(
                    sources.get("right_target_rad", ()),
                    controller_inputs,
                    adjacency,
                    owners,
                    {plant_id, position_id, velocity_id},
                )
                torque_limit = _path(
                    sources.get("torque_limit_scale", ()),
                    controller_inputs,
                    adjacency,
                    owners,
                    {plant_id, position_id, velocity_id},
                )
                if all(
                    (
                        torque_to_plant,
                        torque_to_log,
                        q_feedback,
                        qd_feedback,
                        target_left,
                        target_right,
                        torque_limit,
                    )
                ):
                    torque_witnesses.append(
                        {
                            **state,
                            "plant_transform_node": plant_id,
                            "controller_transform_node": controller_id,
                            "controller_torque_to_plant": torque_to_plant,
                            "controller_torque_to_public_log": torque_to_log,
                            "position_feedback": q_feedback,
                            "velocity_feedback": qd_feedback,
                            "disturbance_to_plant": disturbance_to_plant,
                            "plant_acceleration_to_velocity_state": acceleration_path,
                        }
                    )

        for transform_id in transforms:
            transform = nodes[transform_id]
            inputs = _ports(transform, "input_ports")
            transform_outputs = _ports(transform, "output_ports")
            q_to_transform = _routing_path(q_outputs, inputs, adjacency, owners, nodes)
            pose_path = _routing_path(
                transform_outputs,
                (outputs.get("end_effector_pose", ""),),
                adjacency,
                owners,
                nodes,
            )
            coordination_path = _routing_path(
                transform_outputs,
                (outputs.get("coordination_state", ""),),
                adjacency,
                owners,
                nodes,
            )
            if q_to_transform and pose_path and coordination_path:
                pose_witnesses.append(
                    {
                        "position_state_node": position_id,
                        "kinematics_transform_node": transform_id,
                        "position_to_kinematics": q_to_transform,
                        "kinematics_to_pose": pose_path,
                        "kinematics_to_coordination": coordination_path,
                    }
                )

    prescribed_ports = _strings(graph.get("connected_prescribed_source_output_ports", []))
    no_prescribed = not prescribed_ports and not any(
        bool(row.get("prescribed_source")) and _ports(row, "output_ports")
        for row in nodes.values()
    )
    public_outputs_from_state = bool(state_witnesses and pose_witnesses and torque_witnesses)
    joint_count = bool(
        state_witnesses
        and sources_valid
        and all(
            widths.get(port) == 7
            for name in ("left_target_rad", "right_target_rad")
            for port in sources.get(name, ())
        )
    )
    structural_flags = {
        "joint_count_14": int(joint_count),
        "all_input_torque": int(bool(torque_witnesses)),
        "all_computed_motion": int(bool(torque_witnesses and state_witnesses and no_prescribed)),
        "all_position_sensed": int(bool(torque_witnesses)),
        "all_velocity_sensed": int(bool(torque_witnesses)),
        "all_torque_ports_connected": int(bool(torque_witnesses)),
        "controller_present": int(bool(torque_witnesses)),
        "no_prescribed_trajectory_blocks": int(no_prescribed),
    }
    metadata_checks = {
        "graph_valid": graph_valid,
        "compiled_update_succeeded": graph.get("compiled_update_succeeded") is True,
        "port_identity_complete": graph.get("port_identity_complete") is True,
        "compiled_widths_complete": graph.get("compiled_widths_complete") is True,
        "public_output_bindings_unambiguous": graph.get("public_output_bindings_unambiguous") is True
        and outputs_valid,
        "public_input_bindings_complete": graph.get("public_input_bindings_complete") is True
        and sources_valid,
        "identity_fields_safe": graph.get("candidate_display_names_emitted") is False
        and graph.get("candidate_mask_types_emitted") is False,
        "public_outputs_from_dynamic_state": public_outputs_from_state,
    }
    gate = all(structural_flags.values()) and all(metadata_checks.values())
    return {
        "schema": "simuverity.f90-xrobo02-structure-decision.v1",
        "hard_mechanism_gate_pass": gate,
        **structural_flags,
        **metadata_checks,
        "state_chain_witnesses": state_witnesses,
        "torque_closed_loop_witnesses": torque_witnesses,
        "pose_and_coordination_witnesses": pose_witnesses,
        "failure_reasons": [
            name
            for name, passed in {**structural_flags, **metadata_checks}.items()
            if not bool(passed)
        ],
        "implementation_route_required": "none",
        "product_joint_identity_required": False,
    }

