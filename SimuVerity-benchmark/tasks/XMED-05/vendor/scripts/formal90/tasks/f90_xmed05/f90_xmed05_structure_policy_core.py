#!/usr/bin/env python3
"""Bound-output, exact-port structural policy for XMED-05 evidence current."""

from __future__ import annotations

from collections import deque
from typing import Any, Iterable


OUTPUT_WIDTHS = {"CardiacEGM": 2, "PacingEvents": 8}
DIRECT_CONTAINER = "simulation_output_toworkspace"
LOGGED_CONTAINER = "logsout_exact_element"


def _strings(value: Any) -> tuple[str, ...] | None:
    if isinstance(value, str):
        return (value,) if value else ()
    if not isinstance(value, (list, tuple)) or not all(
        isinstance(item, str) for item in value
    ):
        return None
    return tuple(item for item in value if item)


def _graph_parts(
    graph: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, str], dict[str, set[str]], bool]:
    nodes: dict[str, dict[str, Any]] = {}
    owners: dict[str, str] = {}
    valid = True
    for raw in graph.get("nodes", []):
        if not isinstance(raw, dict):
            valid = False
            continue
        node_id = str(raw.get("id", ""))
        inputs = _strings(raw.get("input_ports", []))
        outputs = _strings(raw.get("output_ports", []))
        if not node_id or node_id in nodes or inputs is None or outputs is None:
            valid = False
            continue
        ports = inputs + outputs
        if len(set(ports)) != len(ports) or any(port in owners for port in ports):
            valid = False
            continue
        nodes[node_id] = raw
        owners.update({port: node_id for port in ports})
    adjacency = {port: set() for port in owners}
    for raw in graph.get("edges", []):
        if not isinstance(raw, (list, tuple)) or len(raw) < 2:
            valid = False
            continue
        source, target = str(raw[0]), str(raw[1])
        if source not in owners or target not in owners or source == target:
            valid = False
            continue
        adjacency[source].add(target)
    return nodes, owners, adjacency, valid


def _path(
    source: str,
    target: str,
    adjacency: dict[str, set[str]],
    owners: dict[str, str],
    forbidden_nodes: Iterable[str] = (),
) -> list[str]:
    if source not in adjacency or target not in adjacency:
        return []
    forbidden = set(str(item) for item in forbidden_nodes)
    queue = deque((source,))
    previous: dict[str, str | None] = {source: None}
    while queue:
        current = queue.popleft()
        for destination in sorted(adjacency[current]):
            if destination != target and owners.get(destination) in forbidden:
                continue
            if destination in previous:
                continue
            previous[destination] = current
            if destination == target:
                result = [target]
                while result[-1] != source:
                    parent = previous[result[-1]]
                    if parent is None:
                        return []
                    result.append(parent)
                return list(reversed(result))
            queue.append(destination)
    return []


def select_output_binding(candidates: Any, width: int) -> dict[str, Any] | None:
    """Select one compat-priority container; never union logging aliases."""

    if not isinstance(candidates, list):
        return None
    rows: list[dict[str, Any]] = []
    for raw in candidates:
        if not isinstance(raw, dict):
            return None
        channels = _strings(raw.get("channel_target_port_ids", []))
        row = {
            "container_kind": str(raw.get("container_kind", "")),
            "container_node_id": str(raw.get("container_node_id", "")),
            "channel_target_port_ids": list(channels or ()),
        }
        if not row["container_kind"] or not row["container_node_id"] or len(
            row["channel_target_port_ids"]
        ) != width:
            return None
        rows.append(row)
    direct = [row for row in rows if row["container_kind"] == DIRECT_CONTAINER]
    if direct:
        return direct[0] if len(direct) == 1 else None
    logged = [row for row in rows if row["container_kind"] == LOGGED_CONTAINER]
    return logged[0] if len(logged) == 1 else None


def _bindings(
    graph: dict[str, Any], nodes: dict[str, dict[str, Any]], owners: dict[str, str]
) -> tuple[dict[str, dict[str, Any]], bool, dict[str, int]]:
    candidates = graph.get("public_output_candidates", {})
    collisions = graph.get("unsupported_direct_name_collisions", {})
    selected: dict[str, dict[str, Any]] = {}
    ignored: dict[str, int] = {}
    valid = isinstance(candidates, dict) and isinstance(collisions, dict)
    for name, width in OUTPUT_WIDTHS.items():
        rows = candidates.get(name, []) if isinstance(candidates, dict) else []
        binding = select_output_binding(rows, width)
        direct_count = sum(
            isinstance(row, dict)
            and str(row.get("container_kind", "")) == DIRECT_CONTAINER
            for row in rows
        ) if isinstance(rows, list) else 0
        logged_count = sum(
            isinstance(row, dict)
            and str(row.get("container_kind", "")) == LOGGED_CONTAINER
            for row in rows
        ) if isinstance(rows, list) else 0
        ignored[name] = logged_count if direct_count else 0
        try:
            collision_count = int(collisions.get(name, 0))
        except (TypeError, ValueError):
            collision_count = -1
        if binding is None or collision_count != 0:
            valid = False
            continue
        if binding["container_node_id"] not in nodes or any(
            port not in owners for port in binding["channel_target_port_ids"]
        ):
            valid = False
            continue
        selected[name] = binding
    if len(selected) != len(OUTPUT_WIDTHS):
        valid = False
    containers = [row["container_node_id"] for row in selected.values()]
    targets = [
        port for row in selected.values() for port in row["channel_target_port_ids"]
    ]
    if len(set(containers)) != len(containers) or len(set(targets)) != len(targets):
        valid = False
    return selected, valid, ignored


def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    nodes, owners, adjacency, graph_valid = _graph_parts(graph)
    selected, bindings_valid, ignored = _bindings(graph, nodes, owners)
    roles = graph.get("selected_roles", {})
    ports = graph.get("role_ports", {})
    roles_valid = isinstance(roles, dict) and isinstance(ports, dict)
    required_roles = (
        "cardiac_response",
        "sensing",
        "ddd_logic",
        "bounded_pacing_delivery",
    )
    role_nodes = {name: str(roles.get(name, "")) for name in required_roles}
    if (
        any(node_id not in nodes for node_id in role_nodes.values())
        or len(set(role_nodes.values())) != len(required_roles)
    ):
        roles_valid = False

    port_widths = {
        "cardiac_response_outputs": 2,
        "sensing_inputs": 2,
        "sensing_outputs": 2,
        "ddd_logic_inputs": 2,
        "ddd_command_outputs": 2,
        "ddd_accepted_outputs": 2,
        "pacing_delivery_inputs": 2,
        "pacing_delivery_outputs": 2,
        "cardiac_response_inputs": 2,
    }
    role_ports: dict[str, tuple[str, ...]] = {}
    for name, width in port_widths.items():
        values = _strings(ports.get(name, [])) if isinstance(ports, dict) else None
        if (
            values is None
            or len(values) != width
            or len(set(values)) != width
            or any(port not in owners for port in values)
        ):
            roles_valid = False
            values = ()
        role_ports[name] = values
    if len({port for values in role_ports.values() for port in values}) < 12:
        roles_valid = False

    all_role_nodes = set(role_nodes.values())

    def paired_paths(source_key: str, target_key: str, source_role: str, target_role: str):
        if not roles_valid:
            return []
        forbidden = all_role_nodes - {role_nodes[source_role], role_nodes[target_role]}
        paths = [
            _path(
                role_ports[source_key][lane],
                role_ports[target_key][lane],
                adjacency,
                owners,
                forbidden,
            )
            for lane in (0, 1)
        ]
        if any(not path for path in paths):
            return []
        middle = [
            {
                owners[port]
                for port in path
                if owners[port] not in {role_nodes[source_role], role_nodes[target_role]}
            }
            for path in paths
        ]
        return paths if middle[0].isdisjoint(middle[1]) else []

    heart_sense = paired_paths(
        "cardiac_response_outputs", "sensing_inputs", "cardiac_response", "sensing"
    )
    sense_logic = paired_paths(
        "sensing_outputs", "ddd_logic_inputs", "sensing", "ddd_logic"
    )
    logic_delivery = paired_paths(
        "ddd_command_outputs",
        "pacing_delivery_inputs",
        "ddd_logic",
        "bounded_pacing_delivery",
    )
    delivery_heart = paired_paths(
        "pacing_delivery_outputs",
        "cardiac_response_inputs",
        "bounded_pacing_delivery",
        "cardiac_response",
    )

    public_paths: dict[str, list[list[str]]] = {}
    if bindings_valid and roles_valid:
        egm_targets = selected["CardiacEGM"]["channel_target_port_ids"]
        event_targets = selected["PacingEvents"]["channel_target_port_ids"]
        sources = {
            "CardiacEGM": role_ports["cardiac_response_outputs"],
            "detected": role_ports["sensing_outputs"],
            "command": role_ports["ddd_command_outputs"],
            "accepted": role_ports["ddd_accepted_outputs"],
            "delivered": role_ports["pacing_delivery_outputs"],
        }
        targets = {
            "CardiacEGM": egm_targets,
            "detected": event_targets[0:2],
            "command": event_targets[2:4],
            "accepted": event_targets[4:6],
            "delivered": event_targets[6:8],
        }
        source_roles = {
            "CardiacEGM": "cardiac_response",
            "detected": "sensing",
            "command": "ddd_logic",
            "accepted": "ddd_logic",
            "delivered": "bounded_pacing_delivery",
        }
        for group in sources:
            source_node = role_nodes[source_roles[group]]
            forbidden = all_role_nodes - {source_node}
            public_paths[group] = [
                _path(source, target, adjacency, owners, forbidden)
                for source, target in zip(sources[group], targets[group])
            ]
    public_pass = bool(public_paths) and all(
        path for paths in public_paths.values() for path in paths
    )

    role_selection = graph.get("name_neutral_role_selection")
    checks = {
        "cardiac_response_to_sensing": bool(heart_sense),
        "sensing_to_ddd_logic": bool(sense_logic),
        "ddd_logic_to_bounded_pacing_delivery": bool(logic_delivery),
        "bounded_pacing_delivery_to_cardiac_response": bool(delivery_heart),
        "bounded_pacing_delivery_verified": graph.get("bounded_pacing_delivery_verified")
        is True,
        "dual_chamber_independence": all(
            bool(paths)
            for paths in (heart_sense, sense_logic, logic_delivery, delivery_heart)
        ),
        "public_output_bindings_unambiguous": bindings_valid,
        "public_output_upstream_qualified": public_pass,
        "port_routing_safe": graph_valid
        and graph.get("port_identity_complete") is True
        and graph.get("bus_creator_selector_all_to_all") is False,
        "name_neutral_role_selection": role_selection is True,
        "identity_fields_safe": not bool(graph.get("candidate_display_names_emitted"))
        and not bool(graph.get("candidate_mask_types_emitted")),
    }
    qualified = roles_valid and all(checks.values())
    return {
        "schema": "simuverity.f90-xmed05-structure-decision.v1",
        "minimum_hybrid_closed_loop_signature": qualified,
        **checks,
        "selected_public_output_bindings": selected,
        "ignored_lower_precedence_logging_alias_counts": ignored,
        "role_blocks_are_distinct": roles_valid,
        "chamber_ports_are_distinct": roles_valid,
        "port_path_witnesses": {
            "cardiac_response_to_sensing": heart_sense,
            "sensing_to_ddd_logic": sense_logic,
            "ddd_to_pacing_delivery": logic_delivery,
            "pacing_delivery_to_cardiac_response": delivery_heart,
            "public_outputs": public_paths,
        },
        "failure_reasons": [name for name, passed in checks.items() if not passed]
        + ([] if roles_valid else ["selected_role_or_port_contract_invalid"]),
        "candidate_logging_aliases_union_with_direct_outputs": False,
    }
