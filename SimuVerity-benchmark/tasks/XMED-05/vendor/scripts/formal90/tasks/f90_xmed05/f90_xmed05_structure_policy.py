"""XMED-05 current policy: preserve MATLAB JSON graph rows before current semantics."""
from __future__ import annotations
import copy
import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any
TASK_DIR = Path(__file__).resolve().parent
GROUP_SCORING_PATH = TASK_DIR / 'f90_xmed05_structure_policy_core.py'

def _load_policy_core() -> ModuleType:
    spec = importlib.util.spec_from_file_location('f90_xmed05_policy_current_current', GROUP_SCORING_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('cannot load current XMED05 current policy')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
GROUP_SCORING = _load_policy_core()

def _normalize_matlab_json_graph(graph: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    normalized = copy.deepcopy(graph)
    edges = normalized.get('edges')
    valid = True
    if isinstance(edges, list) and edges and all((isinstance(row, str) for row in edges)):
        if len(edges) % 3:
            valid = False
        else:
            row_count = len(edges) // 3
            normalized['edges'] = [[edges[index], edges[row_count + index], edges[2 * row_count + index]] for index in range(row_count)]
    elif not isinstance(edges, list):
        valid = False
    candidates = normalized.get('public_output_candidates')
    if isinstance(candidates, dict):
        for name, rows in tuple(candidates.items()):
            if isinstance(rows, dict):
                candidates[name] = [rows]
    else:
        valid = False
    return (normalized, valid)

def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(graph, dict):
        graph = {}
    normalized, encoding_valid = _normalize_matlab_json_graph(graph)
    decision = GROUP_SCORING.evaluate_structure_graph(normalized)
    decision['schema'] = 'simuverity.f90-xmed05-structure-decision.v1'
    decision['matlab_json_graph_encoding_valid'] = encoding_valid
    decision['matlab_nx3_cell_edges_restored'] = isinstance(graph.get('edges'), list) and bool(graph.get('edges')) and all((isinstance(row, str) for row in graph['edges'])) and encoding_valid
    if not encoding_valid:
        decision['minimum_hybrid_closed_loop_signature'] = False
        decision.setdefault('failure_reasons', []).append('matlab_json_graph_encoding_invalid')
    return decision
