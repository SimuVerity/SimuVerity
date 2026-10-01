#!/usr/bin/env python3
"""XMED-04 current policy for MATLAB JSON rows and same-transform pump branches."""

from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any


TASK_DIR = Path(__file__).resolve().parent
COMPATIBILITY_PATH = TASK_DIR / "f90_xmed04_structure_policy_core.py"
def _load_policy_core() -> ModuleType:
    spec = importlib.util.spec_from_file_location("f90_xmed04_policy", COMPATIBILITY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load XMED04 current policy")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


COMPATIBILITY = _load_policy_core()


def _normalize_matlab_json_graph(graph: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    normalized = copy.deepcopy(graph)
    edges = normalized.get("edges")
    valid = True
    if isinstance(edges, list) and edges and all(isinstance(row, str) for row in edges):
        if len(edges) % 3:
            valid = False
        else:
            row_count = len(edges) // 3
            normalized["edges"] = [
                [edges[index], edges[row_count + index], edges[2 * row_count + index]]
                for index in range(row_count)
            ]
    elif not isinstance(edges, list):
        valid = False
    candidates = normalized.get("public_output_candidates")
    if isinstance(candidates, dict):
        for name, rows in tuple(candidates.items()):
            if isinstance(rows, dict):
                candidates[name] = [rows]
    else:
        valid = False
    return normalized, valid


def _node_ports(row: dict[str, Any], field: str) -> tuple[str, ...]:
    values = COMPATIBILITY._as_strings(row.get(field, []))
    return values or ()


def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(graph, dict):
        graph = {}
    normalized, encoding_valid = _normalize_matlab_json_graph(graph)
    decision = COMPATIBILITY.evaluate_structure_graph(normalized)
    decision["schema"] = "simuverity.f90-xmed04-structure-decision.v1"
    decision["matlab_json_graph_encoding_valid"] = encoding_valid
    if not encoding_valid:
        decision["core_path_qualified"] = False
        decision.setdefault("failure_reasons", []).append(
            "matlab_json_graph_encoding_invalid"
        )
        decision["same_transform_actuation_branch_witnesses"] = []
        return decision

    nodes, owners, adjacency, reverse, graph_valid = COMPATIBILITY._graph_parts(normalized)
    bindings, bindings_valid, _ = COMPATIBILITY._selected_bindings(normalized, nodes, owners)
    if not graph_valid or not bindings_valid:
        decision["same_transform_actuation_branch_witnesses"] = []
        return decision

    observed = bindings["ObservedGlucose_mg_dL"]["anchor_port_id"]
    insulin = bindings["InsulinInfusion_mU_min"]["anchor_port_id"]
    true_glucose = bindings["TrueGlucose_mg_dL"]["anchor_port_id"]
    absorbed = bindings["AbsorbedGlucoseRate_mmol_s"]["anchor_port_id"]
    observed_to_insulin = COMPATIBILITY._path_nodes(
        (observed,), (insulin,), adjacency, reverse, owners
    )

    witnesses: list[dict[str, Any]] = []
    actuation_starts: set[str] = set()
    for node_id in sorted(observed_to_insulin):
        row = nodes[node_id]
        block_type = str(row.get("block_type", "")).lower()
        if block_type in COMPATIBILITY.NON_TRANSFORM_TYPES:
            continue
        outputs = _node_ports(row, "output_ports")
        if not outputs:
            continue
        insulin_outputs = [
            port for port in outputs if insulin in COMPATIBILITY._reachable((port,), adjacency)
        ]
        physiology_outputs = [
            port
            for port in outputs
            if true_glucose in COMPATIBILITY._reachable((port,), adjacency)
        ]
        if not insulin_outputs or not physiology_outputs:
            continue
        witnesses.append(
            {
                "node_id": node_id,
                "insulin_log_output_ports": insulin_outputs,
                "physiology_output_ports": physiology_outputs,
                "same_output_branch": bool(
                    set(insulin_outputs) & set(physiology_outputs)
                ),
            }
        )
        actuation_starts.update(physiology_outputs)

    actuation_to_true = COMPATIBILITY._path_nodes(
        actuation_starts, (true_glucose,), adjacency, reverse, owners
    )
    absorbed_to_true = COMPATIBILITY._path_nodes(
        (absorbed,), (true_glucose,), adjacency, reverse, owners
    )
    dynamic_nodes = {
        node_id
        for node_id, row in nodes.items()
        if str(row.get("block_type", "")).lower() in COMPATIBILITY.DYNAMIC_TYPES
        or bool(str(row.get("sf_block_type", "")).strip())
    }
    physiological_dynamic = dynamic_nodes & actuation_to_true & absorbed_to_true
    branch_pass = bool(witnesses and actuation_to_true)

    decision["role_specific_paths"]["insulin_to_true_glucose"] = branch_pass
    decision["physiological_dynamics"] = bool(physiological_dynamic)
    decision["physiological_dynamic_witnesses"] = sorted(physiological_dynamic)
    decision["same_transform_actuation_branch_witnesses"] = witnesses
    mechanism_fields = (
        "output_bindings_unambiguous",
        "distinct_public_output_anchors",
        "port_routing_safe",
        "meal_absorption_dynamics",
        "physiological_dynamics",
        "sampled_monitor",
        "controller_and_pump_are_distinct_transforms",
        "pump_or_delivery_dynamics",
        "identity_fields_safe",
    )
    decision["core_path_qualified"] = all(
        decision["role_specific_paths"].values()
    ) and all(bool(decision[field]) for field in mechanism_fields)
    failures = [
        name
        for name, passed in decision["role_specific_paths"].items()
        if not passed
    ]
    failures.extend(field for field in mechanism_fields if not decision[field])
    decision["failure_reasons"] = failures
    return decision
