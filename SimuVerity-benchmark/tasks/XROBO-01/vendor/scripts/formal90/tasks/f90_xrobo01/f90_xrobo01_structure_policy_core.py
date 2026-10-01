#!/usr/bin/env python3
"""Trusted product/port-network policy for XROBO-01 evidence."""

from __future__ import annotations

from collections import deque
from itertools import combinations
import re
from typing import Any, Iterable


EXPECTED_OUTPUTS = {
    "body_state": 6,
    "contact_state": 4,
    "gait_state": 3,
    "electrical_state": 3,
}
ACCEPTED_INSTANCE_TYPES = {"reference", "simscapemultibodyblock"}
ACCEPTED_LINK_STATUS = {"resolved", "implicit"}
WAVEFORM_BLOCK_TYPES = {
    "clock",
    "constant",
    "fromworkspace",
    "repeatingsequence",
    "signalbuilder",
    "signalgenerator",
    "sine",
    "step",
}


def _text(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()


def _ports(value: Any) -> tuple[str, ...] | None:
    if not isinstance(value, (list, tuple)):
        return None
    if not all(isinstance(item, str) and item for item in value):
        return None
    result = tuple(value)
    return result if len(set(result)) == len(result) else None


def _trusted_product(node: dict[str, Any]) -> bool:
    source = _text(node.get("source_block"))
    root = _text(node.get("library_root"))
    return (
        _text(node.get("block_type")).lower() in ACCEPTED_INSTANCE_TYPES
        and _text(node.get("link_status")).lower() in ACCEPTED_LINK_STATUS
        and bool(source)
        and bool(root)
        and source.split("/", 1)[0] == root
        and node.get("resolved_library_under_matlabroot") is True
        and node.get("source_block_exists") is True
        and bool(_text(node.get("resolved_library_file")))
        and node.get("port_interface_complete") is True
    )


def _roles(node: dict[str, Any]) -> set[str]:
    if not _trusted_product(node):
        return set()
    source = _text(node.get("source_block"))
    source_lower = source.lower()
    leaf = source_lower.rsplit("/", 1)[-1]
    root = _text(node.get("library_root"))
    result: set[str] = set()
    if source == "sm_lib/Joints/Revolute Joint":
        result.add("joint")
    if root == "sm_lib" and source.startswith("sm_lib/Body Elements/") and (
        leaf == "solid" or leaf.endswith(" solid")
    ):
        result.add("solid")
    if root == "ee_lib" and source.startswith("ee_lib/Electromechanical/") and "motor" in leaf:
        result.add("motor")
    if root == "fl_lib" and source.startswith("fl_lib/Mechanical/") and re.search(
        r"\bgear(?:box)?\b|\bgear box\b", leaf
    ):
        result.add("gear")
    if (
        root == "fl_lib"
        and source.startswith("fl_lib/Mechanical/")
        and leaf.endswith("torque sensor")
    ):
        result.add("torque_sensor")
    if source == "sm_lib/Forces and Torques/External Force and Torque":
        result.add("external_force")
    if source == "sm_lib/Frames and Transforms/Transform Sensor":
        result.add("transform_sensor")
    if leaf == "battery" and root in {"batteryecm_lib", "fl_lib", "ee_lib"}:
        result.add("battery")
    if leaf == "capacitor" and root in {"fl_lib", "ee_lib"}:
        result.add("capacitor")
    if leaf == "current sensor" and root in {"fl_lib", "ee_lib"}:
        result.add("current_sensor")
    if leaf == "voltage sensor" and root in {"fl_lib", "ee_lib"}:
        result.add("voltage_sensor")
    if (
        root == "fl_lib"
        and source.startswith("fl_lib/Physical Signals/Functions/")
        and leaf.startswith("ps ")
    ):
        result.add("physical_logic")
    return result


def _parse_graph(graph: dict[str, Any]) -> dict[str, Any]:
    valid = graph.get("schema") == "simuverity.f90-xrobo01-port-network.v1"
    nodes: dict[str, dict[str, Any]] = {}
    owners: dict[str, str] = {}
    input_ports: set[str] = set()
    output_ports: set[str] = set()
    domain_ports: set[str] = set()
    labels: dict[str, str] = {}
    for raw in graph.get("nodes", []):
        if not isinstance(raw, dict):
            valid = False
            continue
        node_id = raw.get("id")
        inputs = _ports(raw.get("signal_input_ports", []))
        outputs = _ports(raw.get("signal_output_ports", []))
        domains = _ports(raw.get("domain_ports", []))
        if (
            not isinstance(node_id, str)
            or not node_id
            or node_id in nodes
            or inputs is None
            or outputs is None
            or domains is None
            or len(set(inputs + outputs + domains)) != len(inputs + outputs + domains)
        ):
            valid = False
            continue
        nodes[node_id] = dict(raw)
        for port in inputs + outputs + domains:
            if port in owners:
                valid = False
            owners[port] = node_id
        input_ports.update(inputs)
        output_ports.update(outputs)
        domain_ports.update(domains)
        raw_labels = raw.get("port_labels", {})
        if not isinstance(raw_labels, dict):
            valid = False
        else:
            for port, label in raw_labels.items():
                if port not in inputs + outputs + domains or not isinstance(label, str):
                    valid = False
                    continue
                labels[port] = _text(label).lower()

    signal_adjacency = {port: set() for port in owners}
    signal_kind: dict[tuple[str, str], set[str]] = {}
    signal_incident: set[str] = set()
    for raw in graph.get("signal_edges", []):
        if not isinstance(raw, (list, tuple)) or len(raw) < 2:
            valid = False
            continue
        source, target = raw[0], raw[1]
        kind = str(raw[2]) if len(raw) > 2 else ""
        if source not in owners or target not in owners:
            valid = False
            continue
        is_transfer = "transfer" in kind
        if is_transfer:
            if source not in input_ports or target not in output_ports or owners[source] != owners[target]:
                valid = False
                continue
        elif source not in output_ports or target not in input_ports:
            # Number-preserving subsystem bridges use an outer input or child
            # output as their evaluator-owned directed boundary endpoints.
            if "hierarchy" not in kind:
                valid = False
                continue
        signal_adjacency[source].add(target)
        signal_kind.setdefault((source, target), set()).add(kind)
        signal_incident.update((source, target))

    physical_adjacency = {port: set() for port in domain_ports}
    physical_incident: set[str] = set()
    for raw in graph.get("physical_edges", []):
        if not isinstance(raw, (list, tuple)) or len(raw) < 2:
            valid = False
            continue
        left, right = raw[0], raw[1]
        if left not in domain_ports or right not in domain_ports:
            valid = False
            continue
        physical_adjacency[left].add(right)
        physical_adjacency[right].add(left)
        physical_incident.update((left, right))

    return {
        "valid": valid and bool(nodes),
        "nodes": nodes,
        "owners": owners,
        "inputs": input_ports,
        "outputs": output_ports,
        "domains": domain_ports,
        "labels": labels,
        "signal": signal_adjacency,
        "signal_kind": signal_kind,
        "signal_incident": signal_incident,
        "physical": physical_adjacency,
        "physical_incident": physical_incident,
    }


def _path(
    starts: Iterable[str],
    targets: Iterable[str],
    adjacency: dict[str, set[str]],
    owners: dict[str, str],
    *,
    forbidden_nodes: set[str] | None = None,
) -> list[str]:
    target_set = {target for target in targets if target in adjacency}
    forbidden = forbidden_nodes or set()
    pending: deque[str] = deque(start for start in starts if start in adjacency)
    predecessor: dict[str, str | None] = {start: None for start in pending}
    while pending:
        current = pending.popleft()
        if current in target_set:
            result: list[str] = []
            cursor: str | None = current
            while cursor is not None:
                result.append(cursor)
                cursor = predecessor[cursor]
            return list(reversed(result))
        for successor in adjacency.get(current, ()):
            if successor in predecessor:
                continue
            if owners.get(successor) in forbidden and successor not in target_set:
                continue
            predecessor[successor] = current
            pending.append(successor)
    return []


def _physical_owner_path(
    start: str,
    target: str,
    parsed: dict[str, Any],
    forbidden: set[str] | None = None,
) -> list[str]:
    witness = _path(
        parsed["nodes"][start].get("domain_ports", []),
        parsed["nodes"][target].get("domain_ports", []),
        parsed["physical"],
        parsed["owners"],
        forbidden_nodes=forbidden,
    )
    owners: list[str] = []
    for port in witness:
        owner = parsed["owners"][port]
        if not owners or owners[-1] != owner:
            owners.append(owner)
    return owners


def _role_map(nodes: dict[str, dict[str, Any]]) -> dict[str, list[str]]:
    result = {
        role: []
        for role in (
            "joint",
            "solid",
            "motor",
            "gear",
            "torque_sensor",
            "external_force",
            "transform_sensor",
            "battery",
            "capacitor",
            "current_sensor",
            "voltage_sensor",
            "physical_logic",
        )
    }
    for node_id, node in nodes.items():
        for role in _roles(node):
            result[role].append(node_id)
    return result


def _joint_configuration(node: dict[str, Any]) -> tuple[bool, bool]:
    raw = node.get("joint_configuration")
    if not isinstance(raw, dict):
        return False, False
    physics = (
        _text(raw.get("torque_actuation_mode")).lower() == "inputtorque"
        and _text(raw.get("motion_actuation_mode")).lower() == "computedmotion"
    )
    sensed = (
        _text(raw.get("sense_position")).lower() == "on"
        and _text(raw.get("sense_velocity")).lower() == "on"
    )
    return physics, sensed


def _labeled_ports(parsed: dict[str, Any], node_id: str, values: set[str], family: str) -> list[str]:
    node = parsed["nodes"][node_id]
    key = {
        "input": "signal_input_ports",
        "output": "signal_output_ports",
        "domain": "domain_ports",
    }[family]
    ports = list(node.get(key, []))
    selected = [port for port in ports if parsed["labels"].get(port, "") in values]
    return selected or ports


def _all_reachable_sources(
    node_ids: Iterable[str], target: str, parsed: dict[str, Any]
) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for node_id in node_ids:
        ports = parsed["nodes"][node_id].get("signal_output_ports", [])
        witness = _path(ports, [target], parsed["signal"], parsed["owners"])
        if witness:
            result[node_id] = witness
    return result


def _all_domain_ports_connected(parsed: dict[str, Any], node_id: str) -> bool:
    ports = parsed["nodes"][node_id].get("domain_ports", [])
    return bool(ports) and all(port in parsed["physical_incident"] for port in ports)


def _public_outputs(graph: dict[str, Any], parsed: dict[str, Any]) -> tuple[dict[str, str], bool]:
    raw = graph.get("public_outputs")
    anchors: dict[str, str] = {}
    valid = isinstance(raw, dict)
    for name, channels in EXPECTED_OUTPUTS.items():
        row = raw.get(name) if isinstance(raw, dict) else None
        if not isinstance(row, dict):
            valid = False
            continue
        node_id = row.get("node_id")
        anchor = row.get("anchor_port_id")
        node = parsed["nodes"].get(node_id) if isinstance(node_id, str) else None
        passed = (
            node is not None
            and _text(node.get("block_type")).lower() == "toworkspace"
            and isinstance(anchor, str)
            and anchor in node.get("signal_input_ports", [])
            and row.get("candidate_count") == 1
            and row.get("timeseries") is True
            and row.get("max_data_points_inf") is True
            and row.get("expected_channels") == channels
            and anchor in parsed["signal_incident"]
        )
        valid = valid and passed
        if passed:
            anchors[name] = anchor
    return anchors, valid and len(anchors) == len(EXPECTED_OUTPUTS)


def _leg_candidates(parsed: dict[str, Any], roles: dict[str, list[str]]) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    contacts = set(roles["external_force"])
    for contact in roles["external_force"]:
        joint_paths: dict[str, list[str]] = {}
        for joint in roles["joint"]:
            witness = _physical_owner_path(
                contact, joint, parsed, contacts - {contact}
            )
            if witness:
                joint_paths[joint] = witness
        for joint_pair in combinations(joint_paths, 2):
            physical_nodes = set(joint_paths[joint_pair[0]]) | set(joint_paths[joint_pair[1]])
            if len(physical_nodes.intersection(roles["solid"])) < 2:
                continue
            transforms = []
            for sensor in roles["transform_sensor"]:
                sensor_path = _physical_owner_path(
                    contact, sensor, parsed, contacts - {contact}
                )
                if sensor_path and len(sensor_path) <= 5:
                    transforms.append((sensor, sensor_path))
            for sensor, sensor_path in transforms:
                for motor in roles["motor"]:
                    motor_inputs = parsed["nodes"][motor].get("signal_input_ports", [])
                    if not motor_inputs:
                        continue
                    sensor_signal = _path(
                        parsed["nodes"][sensor].get("signal_output_ports", []),
                        motor_inputs,
                        parsed["signal"],
                        parsed["owners"],
                    )
                    if not sensor_signal:
                        continue
                    joint_signal: dict[str, dict[str, list[str]]] = {}
                    for joint in joint_pair:
                        q_ports = _labeled_ports(parsed, joint, {"q", "position"}, "output")
                        w_ports = _labeled_ports(parsed, joint, {"w", "velocity"}, "output")
                        q_path = _path(q_ports, motor_inputs, parsed["signal"], parsed["owners"])
                        w_path = _path(w_ports, motor_inputs, parsed["signal"], parsed["owners"])
                        if q_path and w_path:
                            joint_signal[joint] = {"position": q_path, "velocity": w_path}
                    if not joint_signal:
                        continue
                    for gear in roles["gear"]:
                        mechanical = _physical_owner_path(
                            motor,
                            gear,
                            parsed,
                            set(roles["motor"]) - {motor},
                        )
                        if not mechanical or len(mechanical) > 5:
                            continue
                        for torque_sensor in roles["torque_sensor"]:
                            torque_network = _physical_owner_path(
                                gear,
                                torque_sensor,
                                parsed,
                                set(roles["motor"]) - {motor},
                            )
                            if not torque_network or len(torque_network) > 6:
                                continue
                            joint_inputs = [
                                port
                                for joint in joint_pair
                                for port in parsed["nodes"][joint].get(
                                    "signal_input_ports", []
                                )
                            ]
                            actuation = _path(
                                parsed["nodes"][torque_sensor].get(
                                    "signal_output_ports", []
                                ),
                                joint_inputs,
                                parsed["signal"],
                                parsed["owners"],
                            )
                            if not actuation:
                                continue
                            actuated_joint = parsed["owners"].get(actuation[-1], "")
                            if actuated_joint not in joint_signal:
                                continue
                            candidates.append(
                                {
                                    "contact": contact,
                                    "joints": list(joint_pair),
                                    "solids": sorted(
                                        physical_nodes.intersection(roles["solid"])
                                    ),
                                    "transform_sensor": sensor,
                                    "motor": motor,
                                    "gear": gear,
                                    "torque_sensor": torque_sensor,
                                    "actuated_feedback_joint": actuated_joint,
                                    "contact_to_joint_paths": [
                                        joint_paths[value] for value in joint_pair
                                    ],
                                    "contact_to_transform_path": sensor_path,
                                    "motor_to_gear_path": mechanical,
                                    "gear_to_torque_sensor_path": torque_network,
                                    "torque_sensor_to_joint_path": actuation,
                                    "joint_feedback_paths": joint_signal,
                                    "contact_feedback_path": sensor_signal,
                                }
                            )
    return candidates


def _select_legs(candidates: list[dict[str, Any]], count: int = 4) -> list[dict[str, Any]]:
    ordered = sorted(
        candidates,
        key=lambda row: (
            sum(len(path) for path in row["contact_to_joint_paths"]),
            len(row["motor_to_gear_path"]),
            row["contact"],
            row["motor"],
        ),
    )

    def search(
        index: int,
        selected: list[dict[str, Any]],
        used_contacts: set[str],
        used_joints: set[str],
        used_sensors: set[str],
        used_motors: set[str],
        used_gears: set[str],
        used_torque_sensors: set[str],
    ) -> list[dict[str, Any]]:
        if len(selected) == count:
            return selected
        for candidate_index in range(index, len(ordered)):
            row = ordered[candidate_index]
            joints = set(row["joints"])
            if (
                row["contact"] in used_contacts
                or joints.intersection(used_joints)
                or row["transform_sensor"] in used_sensors
                or row["motor"] in used_motors
                or row["gear"] in used_gears
                or row["torque_sensor"] in used_torque_sensors
            ):
                continue
            result = search(
                candidate_index + 1,
                selected + [row],
                used_contacts | {row["contact"]},
                used_joints | joints,
                used_sensors | {row["transform_sensor"]},
                used_motors | {row["motor"]},
                used_gears | {row["gear"]},
                used_torque_sensors | {row["torque_sensor"]},
            )
            if result:
                return result
        return []

    return search(0, [], set(), set(), set(), set(), set(), set())


def _electrical_network(parsed: dict[str, Any], roles: dict[str, list[str]]) -> dict[str, Any]:
    witnesses: dict[str, list[str]] = {}
    required = (
        roles["capacitor"]
        + roles["current_sensor"]
        + roles["voltage_sensor"]
        + roles["motor"]
    )
    selected_battery = ""
    for battery in roles["battery"]:
        if not _all_domain_ports_connected(parsed, battery):
            continue
        starts = parsed["nodes"][battery].get("domain_ports", [])
        rows: dict[str, list[str]] = {}
        for target in required:
            if not _all_domain_ports_connected(parsed, target):
                continue
            witness = _path(
                starts,
                parsed["nodes"][target].get("domain_ports", []),
                parsed["physical"],
                parsed["owners"],
            )
            if witness:
                rows[target] = witness
        reached = set(rows)
        if (
            len(reached.intersection(roles["capacitor"])) >= 1
            and len(reached.intersection(roles["current_sensor"])) >= 2
            and len(reached.intersection(roles["voltage_sensor"])) >= 1
            and len(reached.intersection(roles["motor"])) >= 4
        ):
            selected_battery = battery
            witnesses = rows
            break
    return {
        "pass": bool(selected_battery),
        "battery": selected_battery,
        "paths": witnesses,
        "connected_capacitors": sorted(set(witnesses).intersection(roles["capacitor"])),
        "connected_current_sensors": sorted(set(witnesses).intersection(roles["current_sensor"])),
        "connected_voltage_sensors": sorted(set(witnesses).intersection(roles["voltage_sensor"])),
        "connected_motors": sorted(set(witnesses).intersection(roles["motor"])),
    }


def _output_provenance(
    graph: dict[str, Any], parsed: dict[str, Any], roles: dict[str, list[str]], anchors: dict[str, str]
) -> tuple[dict[str, bool], dict[str, Any], bool]:
    result = {name: False for name in EXPECTED_OUTPUTS}
    witnesses: dict[str, Any] = {name: {} for name in EXPECTED_OUTPUTS}
    if len(anchors) != len(EXPECTED_OUTPUTS):
        return result, witnesses, False

    body_target = anchors["body_state"]
    for sensor in roles["transform_sensor"]:
        if not _all_domain_ports_connected(parsed, sensor):
            continue
        paths = []
        for port in parsed["nodes"][sensor].get("signal_output_ports", []):
            witness = _path([port], [body_target], parsed["signal"], parsed["owners"])
            if witness:
                paths.append(witness)
        if len(paths) >= 6:
            result["body_state"] = True
            witnesses["body_state"] = {"sensor": sensor, "paths": paths}
            break

    contact_paths = _all_reachable_sources(
        [
            sensor
            for sensor in roles["transform_sensor"]
            if _all_domain_ports_connected(parsed, sensor)
        ],
        anchors["contact_state"],
        parsed,
    )
    result["contact_state"] = len(contact_paths) >= 4
    witnesses["contact_state"] = contact_paths

    gait_paths = _all_reachable_sources(
        [
            sensor
            for sensor in roles["transform_sensor"]
            if _all_domain_ports_connected(parsed, sensor)
        ],
        anchors["gait_state"],
        parsed,
    )
    logic_nodes = set(roles["physical_logic"])
    logic_nodes.update(
        node_id
        for node_id, node in parsed["nodes"].items()
        if _text(node.get("block_type")).lower()
        in {
            "chart",
            "logic",
            "memory",
            "multiportswitch",
            "relationaloperator",
            "relay",
            "s-function",
            "stateflow",
            "switch",
            "unitdelay",
        }
        or bool(_text(node.get("semantic_type")))
    )
    gait_with_logic: dict[str, list[str]] = {}
    for sensor, witness in gait_paths.items():
        owner_path = {parsed["owners"].get(port, "") for port in witness}
        edge_kinds = set()
        for left, right in zip(witness, witness[1:]):
            edge_kinds.update(parsed["signal_kind"].get((left, right), set()))
        if owner_path.intersection(logic_nodes) or any("logic" in kind for kind in edge_kinds):
            gait_with_logic[sensor] = witness
    result["gait_state"] = len(gait_with_logic) >= 4
    witnesses["gait_state"] = gait_with_logic

    voltage_paths = _all_reachable_sources(
        [
            sensor
            for sensor in roles["voltage_sensor"]
            if _all_domain_ports_connected(parsed, sensor)
        ],
        anchors["electrical_state"],
        parsed,
    )
    current_paths = _all_reachable_sources(
        [
            sensor
            for sensor in roles["current_sensor"]
            if _all_domain_ports_connected(parsed, sensor)
        ],
        anchors["electrical_state"],
        parsed,
    )
    electrical_network = _electrical_network(parsed, roles)
    connected_voltage = set(electrical_network["connected_voltage_sensors"])
    connected_current = set(electrical_network["connected_current_sensors"])
    result["electrical_state"] = (
        electrical_network["pass"]
        and bool(set(voltage_paths).intersection(connected_voltage))
        and len(set(current_paths).intersection(connected_current)) >= 2
    )
    witnesses["electrical_state"] = {
        "voltage_sensor_paths": voltage_paths,
        "current_sensor_paths": current_paths,
        "physical_network": electrical_network,
    }

    waveform = False
    for node_id, node in parsed["nodes"].items():
        if _text(node.get("block_type")).lower() not in WAVEFORM_BLOCK_TYPES:
            continue
        for target in anchors.values():
            if _path(node.get("signal_output_ports", []), [target], parsed["signal"], parsed["owners"]):
                waveform = True
                break
        if waveform:
            break
    return result, witnesses, waveform


def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    """Reconstruct the strict static gate from evaluator-owned fixed evidence."""
    if not isinstance(graph, dict):
        graph = {}
    parsed = _parse_graph(graph)
    roles = _role_map(parsed["nodes"])
    identity_policy = (
        parsed["valid"]
        and graph.get("port_identity_complete") is True
        and graph.get("hierarchy_bridges_preserve_port_ordinals") is True
        and graph.get("candidate_display_names_emitted") is False
        and graph.get("candidate_mask_or_component_identity_emitted") is False
        and graph.get("candidate_source_type_used_for_identity") is False
        and graph.get("unresolved_reference_metadata_used_for_identity") is False
    )

    joint_physics = []
    joint_feedback = []
    for joint in roles["joint"]:
        node = parsed["nodes"][joint]
        physics, sensed = _joint_configuration(node)
        domain_ports = node.get("domain_ports", [])
        inputs = node.get("signal_input_ports", [])
        outputs = node.get("signal_output_ports", [])
        joint_physics.append(
            physics
            and len(domain_ports) >= 2
            and all(port in parsed["physical_incident"] for port in domain_ports)
            and bool(inputs)
            and all(port in parsed["signal_incident"] for port in inputs)
        )
        joint_feedback.append(
            sensed
            and len(outputs) >= 2
            and all(port in parsed["signal_incident"] for port in outputs)
        )

    leg_witnesses = _select_legs(_leg_candidates(parsed, roles)) if identity_policy else []
    electrical = _electrical_network(parsed, roles)
    anchors, output_contract = _public_outputs(graph, parsed)
    output_provenance, output_witnesses, waveform = _output_provenance(
        graph, parsed, roles, anchors
    )

    mechanism_checks = {
        "articulated_four_leg_plant": (
            identity_policy
            and len(roles["joint"]) >= 8
            and len(roles["solid"]) >= 9
            and len(leg_witnesses) >= 4
        ),
        "computed_torque_joint_physics": (
            len(joint_physics) >= 8 and sum(joint_physics) >= 8
        ),
        "measured_joint_feedback": (
            len(joint_feedback) >= 8 and sum(joint_feedback) >= 8
        ),
        "finite_electromechanical_actuator_chain": (
            len(roles["motor"]) >= 4
            and len(roles["gear"]) >= 4
            and len(roles["torque_sensor"]) >= 4
            and len({row["motor"] for row in leg_witnesses}) >= 4
            and len({row["gear"] for row in leg_witnesses}) >= 4
            and len({row["torque_sensor"] for row in leg_witnesses}) >= 4
        ),
        "four_physical_foot_contacts": (
            len(roles["external_force"]) >= 4
            and len(roles["transform_sensor"]) >= 5
            and len({row["contact"] for row in leg_witnesses}) >= 4
        ),
        "shared_measured_electrical_supply": electrical["pass"],
        "physical_energy_buffer": (
            electrical["pass"] and bool(electrical["connected_capacitors"])
        ),
        "sensor_logic_actuator_branch_ownership": (
            len(leg_witnesses) >= 4
            and len(roles["physical_logic"]) >= 8
            and all(row["joint_feedback_paths"] and row["contact_feedback_path"] for row in leg_witnesses)
        ),
    }
    other_checks = {
        "source_registered": True,
        "complete_timeseries_contract": output_contract,
        "physical_output_provenance": (
            all(output_provenance.values()) and not waveform
        ),
        "self_contained_initialization": graph.get("self_contained_callback") is True,
    }
    checks_by_id = {
        "source_registered": other_checks["source_registered"],
        **mechanism_checks,
        "complete_timeseries_contract": other_checks["complete_timeseries_contract"],
        "physical_output_provenance": other_checks["physical_output_provenance"],
        "self_contained_initialization": other_checks["self_contained_initialization"],
    }
    mechanism_fraction = sum(bool(value) for value in mechanism_checks.values()) / 8.0
    checks = [
        {"id": check_id, "pass": bool(passed), "detail": "current trusted product/port-network predicate"}
        for check_id, passed in checks_by_id.items()
    ]
    return {
        "schema": "simuverity.f90-xrobo01-structure-decision.v1",
        "pass": all(check["pass"] for check in checks),
        "mechanism_fraction": mechanism_fraction,
        "checks": checks,
        "checks_by_id": checks_by_id,
        "identity_policy_pass": identity_policy,
        "counts": {role: len(values) for role, values in roles.items()},
        "trusted_role_nodes": roles,
        "leg_network_witnesses": leg_witnesses,
        "electrical_network_witness": electrical,
        "output_contract_pass": output_contract,
        "output_provenance": output_provenance,
        "output_path_witnesses": output_witnesses,
        "direct_waveform_reaches_public_output": waveform,
        "failure_reasons": [check["id"] for check in checks if not check["pass"]],
        "display_name_used_for_identity": False,
        "candidate_mask_type_used_for_identity": False,
        "candidate_component_path_used_for_identity": False,
        "candidate_source_type_used_for_identity": False,
        "unresolved_reference_metadata_used_for_identity": False,
        "same_parent_subtree_grants_ownership": False,
        "sensor_presence_without_bound_port_path_grants_provenance": False,
    }
