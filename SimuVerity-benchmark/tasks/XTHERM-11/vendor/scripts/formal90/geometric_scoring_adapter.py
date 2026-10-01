"""Utilities for group-preserving strict geometric scorers."""
from __future__ import annotations
import copy
import importlib.util
import math
from pathlib import Path
from types import ModuleType
from typing import Any, Callable

def load_current(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f'cannot load source scorer: {path}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def strict_geometric(gate: object, groups: dict[str, Any], weights: dict[str, float]) -> float:
    gate_value = float(gate)
    if gate_value not in (0.0, 1.0):
        raise ValueError('G must be exactly 0 or 1')
    if not math.isclose(sum(weights.values()), 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError('applicable group weights must sum to one')
    values = {name: float(groups[name]) for name in weights}
    if any((not math.isfinite(value) or value < 0.0 or value > 1.0 for value in values.values())):
        raise ValueError('applicable groups must be finite and in [0, 1]')
    if gate_value == 0.0 or any((value == 0.0 for value in values.values())):
        return 0.0
    return 100.0 * math.exp(sum((weights[name] * math.log(values[name]) for name in weights)))

def adapt_source_result(source: dict[str, Any], *, schema: str, policy_id: str, weights: dict[str, float], primary_total_key: str, cap_conditions_already_represented_in_groups: dict[str, str], transform_groups: Callable[[dict[str, float], dict[str, Any]], dict[str, float]] | None=None) -> dict[str, Any]:
    result = copy.deepcopy(source)
    groups = {name: float(source['groups'][name]) for name in weights}
    if transform_groups is not None:
        groups = transform_groups(groups, source)
    gate = source.get('G', 0.0)
    total = strict_geometric(gate, groups, weights)
    diagnostics = result.get('diagnostics')
    result['schema'] = schema
    result['policy_id'] = policy_id
    result['groups'] = groups
    result[primary_total_key] = total
    result['strict_geometric_total'] = total
    result['total_aggregation'] = {'method': 'G_times_strict_weighted_geometric_mean', 'weights': dict(weights), 'strict_zero_rule': 'any_applicable_group_zero_means_total_zero', 'post_total_adjustment': 'none'}
    result['anti_shortcut_group_penalties'] = {'condition_to_group_mapping': dict(cap_conditions_already_represented_in_groups)}
    return result
