"""Public scorer entry point for XTHERM-05.

The implementation is ordinary readable Python stored in this task directory.
"""
from __future__ import annotations

import importlib
import importlib.abc
import importlib.util
import inspect
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

_SOURCE_FILES = {'formal90_scoring_core': 'vendor/scripts/formal90/formal90_scoring_core.py', 'f90_xtherm05_scoring_core': 'vendor/scripts/formal90/tasks/f90_xtherm05/f90_xtherm05_scoring_core.py', 'f90_xtherm05_mechanism_scoring': 'vendor/scripts/formal90/tasks/f90_xtherm05/f90_xtherm05_mechanism_scoring.py', 'f90_xtherm05_scoring': 'vendor/scripts/formal90/tasks/f90_xtherm05/f90_xtherm05_scoring.py'}
_FINAL_MODULE = 'f90_xtherm05_scoring'
_PUBLIC_BRIDGE = {'mode': 'function'}



class _TaskSourceFinder(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    """Resolve this task's scorer modules from their checked-in source files."""

    _simuverity_task_source_finder = True

    def find_spec(self, fullname, path=None, target=None):
        short = fullname.rsplit(".", 1)[-1]
        if short in _SOURCE_FILES:
            return importlib.util.spec_from_loader(fullname, self)
        return None

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        short = module.__name__.rsplit(".", 1)[-1]
        source_path = (Path(__file__).parent / _SOURCE_FILES[short]).resolve()
        task_root = Path(__file__).parent.resolve()
        if task_root not in source_path.parents:
            raise ValueError(f"Scorer source escapes the task directory: {source_path}")
        module.__file__ = str(source_path)
        source = source_path.read_bytes()
        exec(compile(source, str(source_path), "exec"), module.__dict__)


_FINDER = _TaskSourceFinder()


def _activate_sources() -> None:
    sys.meta_path[:] = [
        item
        for item in sys.meta_path
        if not getattr(item, "_simuverity_task_source_finder", False)
    ]
    sys.meta_path.insert(0, _FINDER)


def _load_source_module(name: str):
    if name not in _SOURCE_FILES:
        raise KeyError(f"Unknown scorer source module: {name}")
    _activate_sources()
    for module_name in _SOURCE_FILES:
        sys.modules.pop(module_name, None)
    return importlib.import_module(name)


def _module():
    return _load_source_module(_FINAL_MODULE)

def _json_file(path: str | Path) -> dict[str, Any]:
    value = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"JSON object required: {path}")
    return value


def _context_dict(context: Any | None) -> dict[str, Any]:
    return dict(context) if isinstance(context, dict) else {}

def _effective_evidence(
    evidence: Any, context: dict[str, Any]
) -> tuple[Any, Path | None]:
    source = context.get("score_evidence_path") or context.get("evidence_path")
    if not source:
        return evidence, None
    path = Path(str(source))
    if not path.is_file():
        raise FileNotFoundError(f"Score evidence file does not exist: {path}")
    if context.get("score_evidence_path"):
        evidence = _json_file(path)
    return evidence, path

def _payload_paths() -> list[tuple[str, Path]]:
    manifest_path = Path(__file__).parent / "scorer" / "manifest.json"
    if not manifest_path.is_file():
        return []
    manifest = _json_file(manifest_path)
    rows: list[tuple[str, Path]] = []
    for item in manifest.get("payload_files", []):
        if not isinstance(item, dict) or not item.get("public_path"):
            continue
        rows.append((str(item.get("source_name", "")), Path(__file__).parent / str(item["public_path"])))
    return rows

def _criteria_path() -> Path:
    candidates = [
        path for name, path in _payload_paths()
        if "criteria" in name.lower()
        and name.lower().endswith(".json")
        and "target" not in name.lower()
    ]
    if len(candidates) != 1:
        raise ValueError(f"expected one public engineering-criteria manifest, found {len(candidates)}")
    if not candidates[0].is_file():
        raise FileNotFoundError(candidates[0])
    return candidates[0]

def _optional_json_context(context: dict[str, Any], *names: str) -> dict[str, Any] | None:
    for name in names:
        value = context.get(name)
        if isinstance(value, dict):
            return dict(value)
        if value:
            return _json_file(Path(str(value)))
    return None


def _path_value(value: Any, dotted: str) -> Any:
    current = value
    for name in dotted.split("."):
        if not isinstance(current, dict) or name not in current:
            raise KeyError(dotted)
        current = current[name]
    return current

def _evidence_groups(evidence: Any) -> dict[str, Any]:
    if isinstance(evidence, dict):
        direct = evidence.get("groups")
        if isinstance(direct, dict) and "G" in direct:
            return dict(direct)
    preprocessor = _PUBLIC_BRIDGE.get("preprocessor")
    if not isinstance(preprocessor, dict):
        raise ValueError("group scorer requires declared public preprocessor metadata")
    module = _load_source_module(str(preprocessor["module"]))
    function = getattr(module, str(preprocessor["function"]))
    native = function(evidence)
    if preprocessor.get("result") == "groups_tuple" and isinstance(native, (tuple, list)) and native and isinstance(native[0], dict):
        groups = dict(native[0])
    elif isinstance(native, dict) and isinstance(native.get("groups"), dict):
        groups = dict(native["groups"])
    else:
        raise TypeError("public group preprocessor returned an unsupported value")
    groups["G"] = _path_value(evidence, str(preprocessor["gate_path"]))
    return groups

def _route_matches(evidence: Any, condition: Any) -> bool:
    if not isinstance(evidence, dict) or not isinstance(condition, dict) or not condition.get("path"):
        return False
    try:
        value = _path_value(evidence, str(condition["path"]))
    except KeyError:
        return False
    if "equals" in condition:
        return value == condition["equals"]
    if "endswith" in condition:
        return isinstance(value, str) and value.endswith(str(condition["endswith"]))
    return False

def _criteria_target(module: Any) -> dict[str, Any]:
    reader = getattr(module, "read_criteria", None)
    target = getattr(module, "target_evidence", None)
    if not callable(reader) or not callable(target):
        raise TypeError("final scorer does not expose its public criteria target loader")
    return target(reader(_criteria_path()))

def _criteria_reference(module: Any) -> dict[str, Any]:
    loader = getattr(module, "load_criteria_bundle", None)
    if not callable(loader):
        raise TypeError("final scorer does not expose its public criteria reference loader")
    loaded = loader(_criteria_path())
    if not isinstance(loaded, (tuple, list)) or len(loaded) < 2 or not isinstance(loaded[1], dict):
        raise TypeError("criteria reference loader returned an unsupported value")
    return loaded[1]

def _route_argument(token: Any, final_module: Any, evidence: Any) -> Any:
    if token == "evidence":
        return evidence
    if token == "criteria_target":
        return _criteria_target(final_module)
    if token == "criteria_reference":
        return _criteria_reference(final_module)
    if isinstance(token, dict) and "literal" in token:
        return token["literal"]
    if isinstance(token, dict) and "module" in token:
        return _load_source_module(str(token["module"]))
    if isinstance(token, dict) and "evidence_field" in token:
        return _path_value(evidence, str(token["evidence_field"]))
    raise TypeError(f"unsupported representation-route argument: {token!r}")

def _invoke_representation_route(final_module: Any, evidence: Any) -> Any:
    for route in _PUBLIC_BRIDGE.get("representation_routes", []):
        if not isinstance(route, dict) or not _route_matches(evidence, route.get("when")):
            continue
        module = _load_source_module(str(route["module"]))
        function = getattr(module, str(route["function"]), None)
        if not callable(function):
            raise TypeError("declared representation-compatible scorer function is unavailable")
        arguments = [_route_argument(token, final_module, evidence) for token in route.get("args", [])]
        return function(*arguments)
    return _MISSING

_MISSING = object()

def _argument_value(
    name: str,
    evidence: Any,
    evidence_path: Path | None,
    context: dict[str, Any],
) -> Any:
    lowered = name.lower()
    if lowered in {"evidence", "e", "value", "candidate", "candidate_evidence", "source"}:
        return evidence
    if lowered == "context":
        return context
    if lowered == "criteria":
        return _json_file(_criteria_path())
    if lowered in {"path", "evidence_path"}:
        if evidence_path is None:
            raise ValueError(f"{name} requires evidence_path in scorer context")
        return evidence_path
    if lowered in {"requested_subject", "subject", "evidence_role", "role"}:
        return str(context.get("subject") or "candidate")
    if lowered == "evidence_bundle":
        return _optional_json_context(context, "evidence_bundle", "evidence_bundle_path")
    if lowered == "loaded_override":
        return None
    if lowered in {"structure", "structure_audit"}:
        value = _optional_json_context(context, "structure", "structure_audit", "structure_path", "structure_audit_path")
        if value is None and isinstance(evidence, dict) and isinstance(evidence.get("structure_audit"), dict):
            value = dict(evidence["structure_audit"])
        if value is None:
            raise ValueError("structure-aware scorer requires evaluator-owned structure audit context")
        return value
    if lowered == "groups":
        return _evidence_groups(evidence)
    if lowered == "reference":
        value = _optional_json_context(context, "reference", "reference_evidence", "reference_evidence_path")
        if value is None:
            raise ValueError("paired scorer requires evaluator-owned reference evidence context")
        return value
    return _MISSING

def _invoke_function(module: Any, evidence: Any, evidence_path: Path | None, context: dict[str, Any]) -> Any:
    preferred = _PUBLIC_BRIDGE.get("function")
    names = [preferred] if preferred else ["score_evidence", "score", "score_evidence_groups", "compute_score"]
    function = next((getattr(module, name, None) for name in names if name and callable(getattr(module, name, None))), None)
    if function is None:
        raise TypeError("Current scorer exposes no public in-process scoring function")
    positional: list[Any] = []
    keywords: dict[str, Any] = {}
    for parameter in inspect.signature(function).parameters.values():
        if parameter.kind in {inspect.Parameter.VAR_POSITIONAL, inspect.Parameter.VAR_KEYWORD}:
            continue
        value = _argument_value(parameter.name, evidence, evidence_path, context)
        if parameter.name.lower() == "criteria":
            reader = getattr(module, "read_criteria", None)
            if callable(reader):
                value = reader(_criteria_path())
        if value is _MISSING:
            if parameter.default is not inspect.Parameter.empty:
                continue
            raise TypeError(f"unsupported current scorer input: {parameter.name}")
        if parameter.kind is inspect.Parameter.POSITIONAL_ONLY:
            positional.append(value)
        else:
            keywords[parameter.name] = value
    return function(*positional, **keywords)

def _invoke_cli(module: Any, evidence_path: Path | None, context: dict[str, Any]) -> Any:
    if evidence_path is None:
        raise ValueError("file-oriented scorer requires evidence_path in scorer context")
    main = getattr(module, "main", None)
    if not callable(main):
        raise TypeError("declared file-oriented scorer has no callable main")
    with tempfile.TemporaryDirectory(prefix="simuverity-score-") as temporary:
        root = Path(temporary)
        output = root / "score.json"
        output_dir = root / "score-output"
        criteria = _criteria_path() if any("{criteria}" in item for item in _PUBLIC_BRIDGE.get("argv", [])) else None
        structure = context.get("structure_audit_path") or context.get("structure_path") or ""
        values = {
            "evidence": str(evidence_path),
            "output": str(output),
            "output_dir": str(output_dir),
            "criteria": str(criteria or ""),
            "subject": str(context.get("subject") or "candidate"),
            "evidence_bundle": str(context.get("evidence_bundle_path") or ""),
            "structure": str(structure),

        }
        argv = [str(item).format_map(values) for item in _PUBLIC_BRIDGE.get("argv", [])]
        old_argv = sys.argv[:]
        returned: Any = None
        try:
            sys.argv = [str(Path(__file__).name), *argv]
            try:
                returned = main()
            except SystemExit as exc:
                if exc.code not in (None, 0):
                    raise
        finally:
            sys.argv = old_argv
        if _PUBLIC_BRIDGE.get("result") == "file" and output.is_file():
            return _json_file(output)
        result_name = _PUBLIC_BRIDGE.get("result_file")
        if result_name and (output_dir / str(result_name)).is_file():
            return _json_file(output_dir / str(result_name))
        if isinstance(returned, dict):
            return returned
        raise RuntimeError("file-oriented scorer did not materialize its declared score output")

def score(evidence: Any, context: Any | None = None) -> Any:
    """Score fixed evidence with the exact checked-in scorer implementation."""
    context_value = _context_dict(context)
    evidence_value, evidence_path = _effective_evidence(evidence, context_value)
    module = _module()
    routed = _invoke_representation_route(module, evidence_value)
    if routed is not _MISSING:
        return routed
    if _PUBLIC_BRIDGE.get("mode") == "cli":
        return _invoke_cli(module, evidence_path, context_value)
    return _invoke_function(module, evidence_value, evidence_path, context_value)

def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> Any:
    """Evaluate a fixed evidence file and materialize the public score JSON."""
    source = Path(evidence_path)
    result = score(
        _json_file(source),
        {"evidence_path": str(source)},
    )
    Path(output_path).write_text(
        json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    return result
