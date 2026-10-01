#!/usr/bin/env python3
"""Bound-output, port-level structural policy for XMED-04 evidence current."""

from __future__ import annotations

from collections import deque
from typing import Any, Iterable


REQUIRED_OUTPUTS = (
    "MealCarbohydrateRate_g_s",
    "AbsorbedGlucoseRate_mmol_s",
    "TrueGlucose_mg_dL",
    "ObservedGlucose_mg_dL",
    "InsulinInfusion_mU_min",
)

DYNAMIC_TYPES = {
    "delay",
    "discretefilter",
    "discreteintegrator",
    "discretestatespace",
    "discretetransferfcn",
    "integrator",
    "memory",
    "s-function",
    "statespace",
    "transportdelay",
    "transferfcn",
    "unitdelay",
    "variabletransportdelay",
}

SAMPLED_TYPES = {
    "delay",
    "discretefilter",
    "discreteintegrator",
    "discretestatespace",
    "discretetransferfcn",
    "ratetransition",
    "unitdelay",
    "zeroorderhold",
}

NON_TRANSFORM_TYPES = {
    "buscreator",
    "busselector",
    "clock",
    "constant",
    "demux",
    "from",
    "goto",
    "ground",
    "inport",
    "mux",
    "outport",
    "scope",
    "subsystem",
    "terminator",
    "toworkspace",
}

DIRECT_CONTAINER = "simulation_output_toworkspace"
LOGGED_CONTAINER = "logsout_exact_element"
REFERENCE_LOGGED_CONTAINER = "reference_logsout_exact_element"


def _as_strings(value: Any) -> tuple[str, ...] | None:
    if isinstance(value, str):
        return (value,) if value else ()
    if not isinstance(value, (list, tuple)) or not all(
        isinstance(item, str) for item in value
    ):
        return None
    return tuple(item for item in value if item)


def _graph_parts(
    graph: dict[str, Any],
) -> tuple[
    dict[str, dict[str, Any]],
    dict[str, str],
    dict[str, set[str]],
    dict[str, set[str]],
    bool,
]:
    nodes: dict[str, dict[str, Any]] = {}
    owner: dict[str, str] = {}
    valid = True
    for raw in graph.get("nodes", []):
        if not isinstance(raw, dict):
            valid = False
            continue
        node_id = str(raw.get("id", ""))
        input_ports = _as_strings(raw.get("input_ports", []))
        output_ports = _as_strings(raw.get("output_ports", []))
        if not node_id or node_id in nodes or input_ports is None or output_ports is None:
            valid = False
            continue
        ports = input_ports + output_ports
        if len(set(ports)) != len(ports) or any(port in owner for port in ports):
            valid = False
            continue
        nodes[node_id] = raw
        owner.update({port: node_id for port in ports})

    adjacency = {port: set() for port in owner}
    reverse = {port: set() for port in owner}
    for raw in graph.get("edges", []):
        if not isinstance(raw, (list, tuple)) or len(raw) < 2:
            valid = False
            continue
        source, target = str(raw[0]), str(raw[1])
        if source not in owner or target not in owner or source == target:
            valid = False
            continue
        adjacency[source].add(target)
        reverse[target].add(source)
    return nodes, owner, adjacency, reverse, valid


def _reachable(starts: Iterable[str], adjacency: dict[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    pending = deque(str(item) for item in starts)
    while pending:
        port = pending.popleft()
        if port in seen or port not in adjacency:
            continue
        seen.add(port)
        pending.extend(adjacency[port] - seen)
    return seen


def port_reachable(graph: dict[str, Any], source: str, target: str) -> bool:
    """Expose exact evaluator-owned port reachability for focused tests."""

    _, _, adjacency, _, valid = _graph_parts(graph)
    return valid and str(target) in _reachable((str(source),), adjacency)


def select_output_binding(candidates: Any) -> dict[str, str] | None:
    """Mirror compat precedence without unioning lower-priority aliases."""

    if not isinstance(candidates, list):
        return None
    normalized: list[dict[str, str]] = []
    for raw in candidates:
        if not isinstance(raw, dict):
            return None
        row = {
            "container_kind": str(raw.get("container_kind", "")),
            "container_node_id": str(raw.get("container_node_id", "")),
            "anchor_port_id": str(raw.get("anchor_port_id", "")),
        }
        if not all(row.values()):
            return None
        normalized.append(row)

    direct = [row for row in normalized if row["container_kind"] == DIRECT_CONTAINER]
    if direct:
        return direct[0] if len(direct) == 1 else None
    logged = [row for row in normalized if row["container_kind"] == LOGGED_CONTAINER]
    if logged:
        return logged[0] if len(logged) == 1 else None
    reference = [
        row
        for row in normalized
        if row["container_kind"] == REFERENCE_LOGGED_CONTAINER
    ]
    return reference[0] if len(reference) == 1 else None


def _selected_bindings(
    graph: dict[str, Any], nodes: dict[str, dict[str, Any]], owner: dict[str, str]
) -> tuple[dict[str, dict[str, str]], bool, dict[str, int]]:
    raw_candidates = graph.get("public_output_candidates", {})
    collisions = graph.get("unsupported_direct_name_collisions", {})
    selected: dict[str, dict[str, str]] = {}
    ignored_aliases: dict[str, int] = {}
    valid = isinstance(raw_candidates, dict) and isinstance(collisions, dict)
    for output_name in REQUIRED_OUTPUTS:
        rows = raw_candidates.get(output_name, []) if isinstance(raw_candidates, dict) else []
        binding = select_output_binding(rows)
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
        ignored_aliases[output_name] = logged_count if direct_count else 0
        try:
            collision_count = int(collisions.get(output_name, 0))
        except (TypeError, ValueError):
            collision_count = -1
        if collision_count != 0 or binding is None:
            valid = False
            continue
        if (
            binding["container_node_id"] not in nodes
            or binding["anchor_port_id"] not in owner
        ):
            valid = False
            continue
        if (
            binding["container_kind"] == REFERENCE_LOGGED_CONTAINER
            and graph.get("reference_subject") is not True
        ):
            valid = False
            continue
        selected[output_name] = binding

    if len(selected) != len(REQUIRED_OUTPUTS):
        valid = False
    container_ids = [row["container_node_id"] for row in selected.values()]
    anchor_ids = [row["anchor_port_id"] for row in selected.values()]
    if len(set(container_ids)) != len(container_ids) or len(set(anchor_ids)) != len(anchor_ids):
        valid = False
    return selected, valid, ignored_aliases


def _path_nodes(
    starts: Iterable[str],
    ends: Iterable[str],
    adjacency: dict[str, set[str]],
    reverse: dict[str, set[str]],
    owner: dict[str, str],
) -> set[str]:
    ports = _reachable(starts, adjacency) & _reachable(ends, reverse)
    return {owner[port] for port in ports if port in owner}


def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    """Evaluate bound public outputs on an evaluator-owned directed port graph."""

    nodes, owner, adjacency, reverse, graph_valid = _graph_parts(graph)
    bindings, bindings_valid, ignored_aliases = _selected_bindings(graph, nodes, owner)
    anchors = {
        name: bindings[name]["anchor_port_id"]
        for name in REQUIRED_OUTPUTS
        if name in bindings
    }

    def has_path(left: str, right: str) -> bool:
        return (
            left in anchors
            and right in anchors
            and anchors[right] in _reachable((anchors[left],), adjacency)
        )

    role_paths = {
        "meal_to_absorbed_glucose": has_path(
            "MealCarbohydrateRate_g_s", "AbsorbedGlucoseRate_mmol_s"
        ),
        "absorbed_glucose_to_true_glucose": has_path(
            "AbsorbedGlucoseRate_mmol_s", "TrueGlucose_mg_dL"
        ),
        "true_glucose_to_observed_glucose": has_path(
            "TrueGlucose_mg_dL", "ObservedGlucose_mg_dL"
        ),
        "observed_glucose_to_insulin": has_path(
            "ObservedGlucose_mg_dL", "InsulinInfusion_mU_min"
        ),
        "insulin_to_true_glucose": has_path(
            "InsulinInfusion_mU_min", "TrueGlucose_mg_dL"
        ),
    }

    dynamic_nodes = {
        node_id
        for node_id, row in nodes.items()
        if str(row.get("block_type", "")).lower() in DYNAMIC_TYPES
        or bool(str(row.get("sf_block_type", "")).strip())
    }
    sampled_nodes = {
        node_id
        for node_id, row in nodes.items()
        if str(row.get("block_type", "")).lower() in SAMPLED_TYPES
    }
    transform_nodes = {
        node_id
        for node_id, row in nodes.items()
        if int(row.get("signal_in", 0) or 0) > 0
        and int(row.get("signal_out", 0) or 0) > 0
        and str(row.get("block_type", "")).lower() not in NON_TRANSFORM_TYPES
    }

    def on_paths(left: str, right: str) -> set[str]:
        if left not in anchors or right not in anchors:
            return set()
        return _path_nodes(
            (anchors[left],), (anchors[right],), adjacency, reverse, owner
        )

    absorption_dynamic = dynamic_nodes & on_paths(
        "MealCarbohydrateRate_g_s", "AbsorbedGlucoseRate_mmol_s"
    )
    absorbed_to_true = on_paths(
        "AbsorbedGlucoseRate_mmol_s", "TrueGlucose_mg_dL"
    )
    insulin_to_true = on_paths("InsulinInfusion_mU_min", "TrueGlucose_mg_dL")
    physiological_dynamic = dynamic_nodes & absorbed_to_true & insulin_to_true
    sampled_monitor = sampled_nodes & on_paths(
        "TrueGlucose_mg_dL", "ObservedGlucose_mg_dL"
    )
    observed_to_insulin = on_paths(
        "ObservedGlucose_mg_dL", "InsulinInfusion_mU_min"
    )
    controller_and_pump = transform_nodes & observed_to_insulin
    pump_dynamic = dynamic_nodes & observed_to_insulin

    identity_safe = not bool(graph.get("candidate_display_names_emitted")) and not bool(
        graph.get("candidate_mask_types_emitted")
    )
    port_contract_safe = (
        graph_valid
        and bool(graph.get("port_identity_complete"))
        and graph.get("bus_creator_selector_all_to_all") is False
        and graph.get("bus_routing_mode") == "exact_element_routes_or_safe_barrier"
    )
    mechanisms = {
        "output_bindings_unambiguous": bindings_valid,
        "distinct_public_output_anchors": bindings_valid,
        "port_routing_safe": port_contract_safe,
        "meal_absorption_dynamics": bool(absorption_dynamic),
        "physiological_dynamics": bool(physiological_dynamic),
        "sampled_monitor": bool(sampled_monitor),
        "controller_and_pump_are_distinct_transforms": len(controller_and_pump) >= 2,
        "pump_or_delivery_dynamics": bool(pump_dynamic),
        "identity_fields_safe": identity_safe,
    }
    qualified = all(role_paths.values()) and all(mechanisms.values())
    failures = [name for name, passed in role_paths.items() if not passed]
    failures.extend(name for name, passed in mechanisms.items() if not passed)
    return {
        "schema": "simuverity.f90-xmed04-structure-decision.v1",
        "core_path_qualified": qualified,
        "role_specific_paths": role_paths,
        **mechanisms,
        "selected_public_output_bindings": bindings,
        "ignored_lower_precedence_logging_alias_counts": ignored_aliases,
        "meal_absorption_dynamic_witnesses": sorted(absorption_dynamic),
        "physiological_dynamic_witnesses": sorted(physiological_dynamic),
        "sampled_monitor_witnesses": sorted(sampled_monitor),
        "controller_pump_transform_witnesses": sorted(controller_and_pump),
        "pump_dynamic_witnesses": sorted(pump_dynamic),
        "failure_reasons": failures,
        "display_name_used_for_role_discovery": False,
        "mask_type_used_for_role_discovery": False,
        "candidate_logging_aliases_union_with_direct_outputs": False,
    }
