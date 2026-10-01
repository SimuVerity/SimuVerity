#!/usr/bin/env python3
"""Offline connected-circulation policy for candidate F90-XMED-02 current.

The MATLAB auditor owns graph extraction from Simscape conserving ports.
This module deliberately ignores display names and source component-count
thresholds.  It decides only from the extracted, labeled physical graph.
"""

from __future__ import annotations

from collections import Counter
from typing import Callable, Iterable


POLICY_ID = 'simuverity-101-v1:f90-xmed-02:scoring'
GRAPH_SCHEMA = "simuverity.f90-xmed02-circulation-graph.v1"
ROLES = ("resistive", "inertance", "valve", "flow_sensor", "actuator")
MAX_EDGES = 256
MAX_SEARCH_STATES = 50_000


def _empty_witness() -> dict:
    return {
        "pass": False,
        "edge_ids": [],
        "net_ids": [],
        "role_counts": {role: 0 for role in ROLES},
        "compliance_net_count": 0,
        "search_exhausted": False,
    }


def _string_set(value: object) -> set[str]:
    if not isinstance(value, list):
        return set()
    return {item for item in value if isinstance(item, str) and item}


def _normalize_graph(graph: object) -> tuple[dict | None, list[str]]:
    reasons: list[str] = []
    if not isinstance(graph, dict) or graph.get("schema") != GRAPH_SCHEMA:
        return None, ["missing_or_invalid_circulation_graph"]
    for flag in ("graph_valid", "identity_valid", "conserving_port_graph_valid"):
        if graph.get(flag) is not True:
            reasons.append(f"circulation_graph_{flag}_false")

    raw_edges = graph.get("transport_edges")
    if not isinstance(raw_edges, list) or not raw_edges or len(raw_edges) > MAX_EDGES:
        reasons.append("invalid_transport_edge_collection")
        raw_edges = []
    edges: list[dict] = []
    seen_ids: set[str] = set()
    for raw in raw_edges:
        if not isinstance(raw, dict):
            reasons.append("malformed_transport_edge")
            continue
        edge_id = raw.get("id")
        net_a = raw.get("net_a")
        net_b = raw.get("net_b")
        owner = raw.get("owner")
        raw_roles = raw.get("roles")
        valid = (
            isinstance(edge_id, str)
            and bool(edge_id)
            and edge_id not in seen_ids
            and isinstance(owner, str)
            and bool(owner)
            and isinstance(net_a, str)
            and bool(net_a)
            and isinstance(net_b, str)
            and bool(net_b)
            and net_a != net_b
            and isinstance(raw_roles, list)
            and bool(raw_roles)
        )
        raw_roles_valid = isinstance(raw_roles, list) and all(
            isinstance(role, str) for role in raw_roles
        )
        roles = tuple(sorted(set(raw_roles))) if raw_roles_valid else ()
        if (
            not valid
            or not roles
            or any(role not in ROLES for role in roles)
            or len(roles) != len(raw_roles)
        ):
            reasons.append("malformed_transport_edge")
            continue
        seen_ids.add(edge_id)
        edges.append(
            {
                "id": edge_id,
                "owner": owner,
                "net_a": net_a,
                "net_b": net_b,
                "roles": roles,
            }
        )

    reference_nets = _string_set(graph.get("reference_nets"))
    compliance_nets = _string_set(graph.get("compliance_nets")) - reference_nets
    pressure_sensor_nets = _string_set(graph.get("pressure_sensor_nets")) - reference_nets
    feedback_edge = graph.get("feedback_actuator_edge_id")
    if not isinstance(feedback_edge, str) or not feedback_edge:
        reasons.append("missing_feedback_actuator_edge")
        feedback_edge = ""
    if graph.get("feedback_path_has_dynamic_control") is not True:
        reasons.append("missing_dynamic_pressure_feedback")

    normalized = {
        "edges": edges,
        "reference_nets": reference_nets,
        "compliance_nets": compliance_nets,
        "pressure_sensor_nets": pressure_sensor_nets,
        "feedback_edge": feedback_edge,
    }
    return normalized, reasons


def _cycle_summary(edges: list[dict], indices: Iterable[int], compliance_nets: set[str]) -> dict:
    selected = [edges[index] for index in indices]
    role_counts: Counter[str] = Counter()
    nets: set[str] = set()
    for edge in selected:
        role_counts.update(edge["roles"])
        nets.update((edge["net_a"], edge["net_b"]))
    return {
        "pass": False,
        "edge_ids": [edge["id"] for edge in selected],
        "net_ids": sorted(nets),
        "role_counts": {role: role_counts[role] for role in ROLES},
        "compliance_net_count": len(nets & compliance_nets),
        "search_exhausted": False,
    }


def _find_cycle(
    edges: list[dict],
    candidate_indices: Iterable[int],
    compliance_nets: set[str],
    predicate: Callable[[dict], bool],
    reference_nets: set[str],
) -> dict:
    witness = _empty_witness()
    usable = [
        index
        for index, edge in enumerate(edges)
        if edge["net_a"] not in reference_nets and edge["net_b"] not in reference_nets
    ]
    usable_set = set(usable)
    states = 0
    for excluded in candidate_indices:
        if excluded not in usable_set:
            continue
        edge = edges[excluded]
        start, target = edge["net_a"], edge["net_b"]
        stack: list[tuple[str, tuple[str, ...], tuple[int, ...]]] = [(start, (start,), ())]
        while stack:
            node, visited, path = stack.pop()
            states += 1
            if states > MAX_SEARCH_STATES:
                witness["search_exhausted"] = True
                return witness
            if node == target and path:
                summary = _cycle_summary(edges, (excluded, *path), compliance_nets)
                if predicate(summary):
                    summary["pass"] = True
                    return summary
                continue
            for next_index in reversed(usable):
                if next_index == excluded or next_index in path:
                    continue
                next_edge = edges[next_index]
                if next_edge["net_a"] == node:
                    other = next_edge["net_b"]
                elif next_edge["net_b"] == node:
                    other = next_edge["net_a"]
                else:
                    continue
                if other in visited:
                    continue
                stack.append((other, (*visited, other), (*path, next_index)))
    return witness


def _main_predicate(summary: dict) -> bool:
    counts = summary["role_counts"]
    heart_or_valves = counts["actuator"] >= 2 or counts["valve"] >= 4
    return (
        heart_or_valves
        and counts["resistive"] >= 2
        and counts["inertance"] >= 2
        and counts["flow_sensor"] >= 2
        and summary["compliance_net_count"] >= 3
    )


def _ecmo_predicate(summary: dict) -> bool:
    counts = summary["role_counts"]
    return (
        counts["actuator"] >= 1
        and counts["resistive"] >= 1
        and counts["flow_sensor"] >= 1
        and summary["compliance_net_count"] >= 2
    )


def assess_circulation(graph: object) -> dict:
    """Return a deterministic, JSON-safe connected-topology decision."""
    normalized, reasons = _normalize_graph(graph)
    if normalized is None:
        return {
            "policy_id": POLICY_ID,
            "pass": False,
            "reasons": reasons,
            "main_circulation": _empty_witness(),
            "ecmo_feedback_branch": _empty_witness(),
            "pressure_measurements": {"pass": False, "anchored_net_count": 0, "net_ids": []},
        }

    edges = normalized["edges"]
    compliance_nets = normalized["compliance_nets"]
    reference_nets = normalized["reference_nets"]
    main = _find_cycle(
        edges,
        range(len(edges)),
        compliance_nets,
        _main_predicate,
        reference_nets,
    )
    feedback_indices = [
        index
        for index, edge in enumerate(edges)
        if edge["id"] == normalized["feedback_edge"] and "actuator" in edge["roles"]
    ]
    ecmo = _find_cycle(
        edges,
        feedback_indices,
        compliance_nets,
        _ecmo_predicate,
        reference_nets,
    )
    pressure_nets = sorted(normalized["pressure_sensor_nets"] & compliance_nets)
    pressure = {
        "pass": len(pressure_nets) >= 3,
        "anchored_net_count": len(pressure_nets),
        "net_ids": pressure_nets,
    }

    if not main["pass"]:
        reasons.append("missing_closed_systemic_pulmonary_circulation")
    if not ecmo["pass"]:
        reasons.append("missing_closed_feedback_actuated_ecmo_branch")
    if not pressure["pass"]:
        reasons.append("insufficient_compliance_anchored_pressure_measurements")
    if main["search_exhausted"] or ecmo["search_exhausted"]:
        reasons.append("circulation_graph_search_exhausted")
    passed = not reasons and main["pass"] and ecmo["pass"] and pressure["pass"]
    if not passed and "missing_or_unproved_connected_circulation_topology" not in reasons:
        reasons.append("missing_or_unproved_connected_circulation_topology")
    return {
        "policy_id": POLICY_ID,
        "pass": passed,
        "reasons": list(dict.fromkeys(reasons)),
        "main_circulation": main,
        "ecmo_feedback_branch": ecmo,
        "pressure_measurements": pressure,
    }


__all__ = ["GRAPH_SCHEMA", "POLICY_ID", "assess_circulation"]
