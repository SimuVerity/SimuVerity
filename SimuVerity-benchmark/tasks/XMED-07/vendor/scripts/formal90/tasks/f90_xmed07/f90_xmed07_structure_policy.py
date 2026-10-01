#!/usr/bin/env python3
"""Compat-bound exact-port public-output policy for XMED-07 evidence current."""

from __future__ import annotations

from collections import deque
from typing import Any, Iterable


OUTPUT_NAMES = ("motion_state", "delivery_state", "safety_state")
DIRECT_CONTAINER = "simulation_output_toworkspace"
LOGGED_CONTAINER = "logsout_exact_element"
CAUSAL_FIELDS = (
    "command_to_supervisor",
    "supervisor_to_motor_controller",
    "motor_controller_to_actuator",
    "speed_to_motor_controller",
    "speed_to_occlusion_detector",
    "force_to_occlusion_detector",
    "occlusion_detector_to_supervisor",
    "remaining_to_supervisor",
    "controller_components",
)
PHYSICAL_FIELDS = (
    "main_chain",
    "upstream_flow_sensor",
    "patient_flow_sensor",
    "occlusion_source",
)
CORE_FIELDS = (
    "top_command_to_software",
    "top_software_to_motor_plant",
    "top_plant_feedback_to_software",
    "software_reference_to_motor_controller",
    "measured_speed_to_motor_controller",
    "measured_speed_to_occlusion_detector",
    "load_force_to_occlusion_detector",
    "occlusion_to_supervisory",
    "remaining_units_to_supervisory",
    "physical_motor_present",
    "physical_transmission_present",
    "physical_slide_present",
    "physical_reservoir_present",
    "physical_delivery_line_present",
    "physical_patient_boundary_present",
    "physical_upstream_flow_sensor_present",
    "physical_patient_flow_sensor_present",
    "native_occlusion_source_present",
    "controller_component_models_present",
)


def _strings(value: Any) -> tuple[str, ...] | None:
    if isinstance(value, str):
        return (value,) if value else ()
    if not isinstance(value, (list, tuple)) or not all(
        isinstance(item, str) and item for item in value
    ):
        return None
    return tuple(value)


def _graph_parts(
    graph: dict[str, Any],
) -> tuple[
    dict[str, dict[str, Any]],
    dict[str, str],
    dict[str, set[str]],
    bool,
]:
    nodes: dict[str, dict[str, Any]] = {}
    owners: dict[str, str] = {}
    valid = graph.get("schema") == "simuverity.f90-xmed07-port-graph.v1"
    for raw in graph.get("nodes", []):
        if not isinstance(raw, dict):
            valid = False
            continue
        node_id = raw.get("id")
        inputs = _strings(raw.get("input_ports", []))
        outputs = _strings(raw.get("output_ports", []))
        if (
            not isinstance(node_id, str)
            or not node_id
            or node_id in nodes
            or inputs is None
            or outputs is None
            or len(set(inputs + outputs)) != len(inputs + outputs)
        ):
            valid = False
            continue
        nodes[node_id] = {
            "id": node_id,
            "block_type": str(raw.get("block_type", "")),
            "input_ports": inputs,
            "output_ports": outputs,
        }
        for port in inputs + outputs:
            if port in owners:
                valid = False
            owners[port] = node_id
    adjacency = {port: set() for port in owners}
    for raw in graph.get("edges", []):
        if not isinstance(raw, (list, tuple)) or len(raw) < 2:
            valid = False
            continue
        source, target = raw[0], raw[1]
        if not isinstance(source, str) or not isinstance(target, str):
            valid = False
            continue
        if source not in owners or target not in owners:
            valid = False
            continue
        adjacency[source].add(target)
    return nodes, owners, adjacency, valid and bool(nodes)


def _path(
    starts: Iterable[str],
    targets: Iterable[str],
    adjacency: dict[str, set[str]],
    owners: dict[str, str],
    forbidden_owners: set[str] | None = None,
) -> list[str]:
    target_set = {target for target in targets if target in owners}
    forbidden = forbidden_owners or set()
    pending: deque[str] = deque(start for start in starts if start in owners)
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


def _candidate_valid(
    candidate: Any,
    kind: str,
    nodes: dict[str, dict[str, Any]],
    owners: dict[str, str],
) -> bool:
    if not isinstance(candidate, dict) or candidate.get("container_kind") != kind:
        return False
    node_id = candidate.get("container_node_id")
    anchor = candidate.get("anchor_port_id")
    if not isinstance(node_id, str) or not isinstance(anchor, str):
        return False
    node = nodes.get(node_id)
    if node is None or owners.get(anchor) != node_id:
        return False
    if kind == DIRECT_CONTAINER:
        return (
            node["block_type"].lower() == "toworkspace"
            and anchor in node["input_ports"]
            and len(node["input_ports"]) == 1
        )
    return anchor in node["output_ports"]


def _select_public_bindings(
    graph: dict[str, Any],
    nodes: dict[str, dict[str, Any]],
    owners: dict[str, str],
) -> tuple[dict[str, dict[str, Any]], dict[str, int], bool]:
    candidates = graph.get("public_output_candidates")
    collisions = graph.get("unsupported_direct_name_collisions")
    if not isinstance(candidates, dict) or not isinstance(collisions, dict):
        return {}, {}, False
    selected: dict[str, dict[str, Any]] = {}
    ignored: dict[str, int] = {}
    valid = True
    for name in OUTPUT_NAMES:
        rows = candidates.get(name)
        collision = collisions.get(name)
        if not isinstance(rows, list) or not isinstance(collision, int) or collision < 0:
            valid = False
            continue
        direct = [row for row in rows if _candidate_valid(row, DIRECT_CONTAINER, nodes, owners)]
        logged = [row for row in rows if _candidate_valid(row, LOGGED_CONTAINER, nodes, owners)]
        if collision:
            valid = False
            continue
        if direct:
            if len(direct) != 1:
                valid = False
                continue
            selected[name] = dict(direct[0])
            ignored[name] = len(logged)
        elif len(logged) == 1:
            selected[name] = dict(logged[0])
            ignored[name] = 0
        else:
            valid = False
    anchors = [row.get("anchor_port_id") for row in selected.values()]
    valid = valid and len(selected) == len(OUTPUT_NAMES) and len(set(anchors)) == len(anchors)
    return selected, ignored, valid


def _source_groups(
    graph: dict[str, Any], owners: dict[str, str]
) -> tuple[dict[str, list[tuple[str, ...]]], bool]:
    raw = graph.get("public_output_source_ports")
    result: dict[str, list[tuple[str, ...]]] = {}
    valid = isinstance(raw, dict)
    for name in OUTPUT_NAMES:
        groups = raw.get(name) if isinstance(raw, dict) else None
        parsed: list[tuple[str, ...]] = []
        if not isinstance(groups, list) or len(groups) != 4:
            valid = False
            result[name] = parsed
            continue
        for group in groups:
            ports = _strings(group)
            if ports is None or not ports or any(port not in owners for port in ports):
                valid = False
                parsed.append(())
            else:
                parsed.append(ports)
        result[name] = parsed
    return result, valid


def _facts(graph: dict[str, Any]) -> tuple[dict[str, bool], dict[str, bool], bool]:
    causal_raw = graph.get("current_causal_facts")
    physical_raw = graph.get("current_physical_facts")
    causal: dict[str, bool] = {}
    physical: dict[str, bool] = {}
    valid = isinstance(causal_raw, dict) and isinstance(physical_raw, dict)
    for name in CAUSAL_FIELDS:
        value = causal_raw.get(name) if isinstance(causal_raw, dict) else None
        if not isinstance(value, bool):
            valid = False
        causal[name] = value is True
    for name in PHYSICAL_FIELDS:
        value = physical_raw.get(name) if isinstance(physical_raw, dict) else None
        if not isinstance(value, bool):
            valid = False
        physical[name] = value is True
    return causal, physical, valid


def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    """Return current static fields using only extracted evidence."""
    if not isinstance(graph, dict):
        graph = {}
    nodes, owners, adjacency, graph_valid = _graph_parts(graph)
    selected, ignored, bindings_valid = _select_public_bindings(graph, nodes, owners)
    sources, sources_valid = _source_groups(graph, owners)
    causal, physical, facts_valid = _facts(graph)

    public_paths: dict[str, list[list[str]]] = {}
    public_passes: dict[str, bool] = {}
    if bindings_valid and sources_valid:
        for name in OUTPUT_NAMES:
            target = [str(selected[name]["anchor_port_id"])]
            group_owners = [
                {owners[port] for port in group if port in owners}
                for group in sources[name]
            ]
            rows: list[list[str]] = []
            for index, group in enumerate(sources[name]):
                forbidden = set().union(
                    *(group_owners[other] for other in range(4) if other != index)
                )
                rows.append(_path(group, target, adjacency, owners, forbidden))
            public_paths[name] = rows
            public_passes[name] = all(bool(row) for row in rows)
    else:
        public_passes = {name: False for name in OUTPUT_NAMES}

    motion = public_passes.get("motion_state", False)
    delivery = public_passes.get("delivery_state", False)
    safety = public_passes.get("safety_state", False)
    port_safety = (
        graph_valid
        and graph.get("port_identity_complete") is True
        and graph.get("bus_creator_selector_all_to_all") is False
        and not bool(graph.get("candidate_display_names_emitted"))
        and not bool(graph.get("candidate_mask_types_emitted"))
    )
    structure_contract = bindings_valid and sources_valid and facts_valid and port_safety

    core = {
        "top_command_to_software": causal["command_to_supervisor"] and motion,
        "top_software_to_motor_plant": causal["motor_controller_to_actuator"] and motion,
        "top_plant_feedback_to_software": causal["speed_to_motor_controller"] and motion,
        "software_reference_to_motor_controller": causal[
            "supervisor_to_motor_controller"
        ]
        and motion,
        "measured_speed_to_motor_controller": causal["speed_to_motor_controller"]
        and motion,
        "measured_speed_to_occlusion_detector": causal[
            "speed_to_occlusion_detector"
        ]
        and safety,
        "load_force_to_occlusion_detector": causal["force_to_occlusion_detector"]
        and safety,
        "occlusion_to_supervisory": causal["occlusion_detector_to_supervisor"]
        and safety,
        "remaining_units_to_supervisory": causal["remaining_to_supervisor"]
        and safety,
        "physical_motor_present": physical["main_chain"],
        "physical_transmission_present": physical["main_chain"],
        "physical_slide_present": physical["main_chain"],
        "physical_reservoir_present": physical["main_chain"],
        "physical_delivery_line_present": physical["main_chain"] and delivery,
        "physical_patient_boundary_present": physical["main_chain"],
        "physical_upstream_flow_sensor_present": physical["upstream_flow_sensor"]
        and delivery,
        "physical_patient_flow_sensor_present": physical["patient_flow_sensor"]
        and delivery,
        "native_occlusion_source_present": physical["occlusion_source"]
        and delivery
        and safety,
        "controller_component_models_present": causal["controller_components"],
    }
    if not structure_contract:
        core = {name: False for name in CORE_FIELDS}
    qualified = all(core.values())
    return {
        "schema": "simuverity.f90-xmed07-structure-decision.v1",
        **core,
        "core_static_causal_path": qualified,
        "motion_state_upstream_qualified": motion and structure_contract,
        "delivery_state_upstream_qualified": delivery and structure_contract,
        "safety_state_upstream_qualified": safety and structure_contract,
        "public_outputs_all_upstream_qualified": (
            motion and delivery and safety and structure_contract
        ),
        "public_output_bindings_unambiguous": bindings_valid,
        "public_output_source_contract_valid": sources_valid,
        "port_routing_safe": port_safety,
        "fact_contract_valid": facts_valid,
        "selected_public_output_bindings": selected,
        "ignored_lower_precedence_logging_alias_counts": ignored,
        "port_path_witnesses": public_paths,
        "failure_reasons": [
            name
            for name, passed in {
                "public_output_bindings_unambiguous": bindings_valid,
                "public_output_source_contract_valid": sources_valid,
                "motion_state_upstream_qualified": motion,
                "delivery_state_upstream_qualified": delivery,
                "safety_state_upstream_qualified": safety,
                "port_routing_safe": port_safety,
                "fact_contract_valid": facts_valid,
            }.items()
            if not passed
        ],
        "nested_or_top_level_outport_grants_public_binding": False,
        "candidate_logging_aliases_union_with_direct_outputs": False,
    }
