from __future__ import annotations

import json
import os
import re
from pathlib import Path, PureWindowsPath
from typing import Any, Iterable, Mapping

from .errors import ContractError
from .jsonutil import load_json
from .types import ExtractorSidecar, TaskDefinition

TASK_ID_RE = re.compile(r"^X[A-Z]+-[A-Z0-9]+(?:-[A-Z0-9]+)*$")
SIDECAR_ROLE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


def discover_repository(explicit: Path | None = None) -> Path:
    candidates: list[Path] = []
    if explicit is not None:
        candidates.append(explicit)
    configured = os.environ.get("SIMUVERITY_ROOT")
    if configured:
        candidates.append(Path(configured))
    candidates.extend([Path.cwd(), *Path.cwd().parents])
    installed_root = Path(__file__).resolve().parents[2]
    candidates.extend([installed_root, installed_root.parent])
    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        if (resolved / "pyproject.toml").is_file() and (resolved / "tasks").is_dir():
            return resolved
    raise ContractError("Cannot locate a SimuVerity repository; pass --repo or set SIMUVERITY_ROOT")


def _relative_path(value: Any, *, field: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ContractError(f"{field} must be a non-empty repository-relative path")
    path = Path(value)
    if path.is_absolute() or PureWindowsPath(value).is_absolute() or ":" in value or ".." in path.parts:
        raise ContractError(f"{field} must not escape the task directory: {value!r}")
    return path


def _resolve_task_path(task_root: Path, value: Any, *, field: str) -> Path:
    relative = _relative_path(value, field=field)
    target = (task_root / relative).resolve()
    try:
        target.relative_to(task_root.resolve())
    except ValueError as exc:
        raise ContractError(f"{field} escapes the task directory") from exc
    return target


def _scorer_binding(raw: Mapping[str, Any]) -> tuple[str, str, str]:
    value = raw.get("scorer", "scorer.py")
    if isinstance(value, str):
        return value, "python", "score"
    if not isinstance(value, Mapping):
        raise ContractError("scorer must be a path or object")
    interface = value.get("entrypoint", "score")
    path = value.get("path", value.get("implementation"))
    function = value.get("function")
    if isinstance(interface, str) and ":" in interface:
        interface_path, interface_function = interface.rsplit(":", 1)
        path = path or interface_path
        function = function or interface_function
    path = path or "scorer.py"
    function = function or (interface if isinstance(interface, str) and "/" not in interface and "\\" not in interface else "score")
    kind = value.get("kind", "python")
    if not all(isinstance(item, str) and item for item in (path, kind, function)):
        raise ContractError("scorer binding is incomplete")
    return path, kind, function


def _extractor_binding(raw: Mapping[str, Any]) -> tuple[str, str, str]:
    value = raw.get("extractor", "extractor")
    if isinstance(value, str):
        path = value
        return path, "python" if path.lower().endswith(".py") else "matlab", Path(path).stem
    if not isinstance(value, Mapping):
        raise ContractError("extractor must be a path or object")
    interface = value.get("entrypoint")
    path = value.get("path")
    function = value.get("function")
    if path is None and isinstance(interface, str) and interface.lower().endswith((".m", ".py")):
        path = interface
        function = function or Path(interface).stem
    path = path or "extractor"
    kind = value.get("kind", "python" if str(path).lower().endswith(".py") else "matlab")
    function = function or (interface if isinstance(interface, str) else "extract_evidence")
    if not all(isinstance(item, str) and item for item in (path, kind, function)):
        raise ContractError("extractor binding is incomplete")
    return path, kind, function


class TaskRepository:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.tasks_root = self.root / "tasks"
        if not self.tasks_root.is_dir():
            raise ContractError(f"Task directory is missing: {self.tasks_root}")

    @classmethod
    def discover(cls, explicit: Path | None = None) -> "TaskRepository":
        return cls(discover_repository(explicit))

    def task_ids(self) -> list[str]:
        found: list[str] = []
        for manifest in self.tasks_root.glob("*/task.json"):
            try:
                found.append(self.load_manifest_id(manifest))
            except ContractError:
                raise
            except Exception as exc:
                raise ContractError(f"Cannot read {manifest}: {exc}") from exc
        if len(found) != len(set(found)):
            duplicates = sorted({item for item in found if found.count(item) > 1})
            raise ContractError(f"Duplicate task IDs: {', '.join(duplicates)}")
        return sorted(found)

    @staticmethod
    def load_manifest_id(path: Path) -> str:
        raw = load_json(path)
        if not isinstance(raw, Mapping):
            raise ContractError(f"Task manifest is not an object: {path}")
        value = raw.get("task_id", raw.get("benchmark_task_id", raw.get("id")))
        if not isinstance(value, str) or not TASK_ID_RE.fullmatch(value):
            raise ContractError(f"Invalid task ID in {path}")
        return value

    def manifests(self) -> Iterable[Path]:
        return self.tasks_root.glob("*/task.json")

    def get(self, task_id: str) -> TaskDefinition:
        matches = [path for path in self.manifests() if self.load_manifest_id(path) == task_id]
        if not matches:
            raise ContractError(f"Unknown task: {task_id}")
        if len(matches) != 1:
            raise ContractError(f"Task ID is not unique: {task_id}")
        return self.load(matches[0])

    def load(self, manifest_path: Path) -> TaskDefinition:
        raw = load_json(manifest_path)
        if not isinstance(raw, Mapping):
            raise ContractError("task.json must contain one JSON object")
        task_id = self.load_manifest_id(manifest_path)
        task_root = manifest_path.parent.resolve()
        public_value = raw.get("public_spec", "public_spec.json")
        system_profile_value = raw.get("system_profile")
        scenarios_value = raw.get("official_scenarios", "official_scenarios.json")
        if isinstance(public_value, Mapping):
            public_value = public_value.get("path")
        if not isinstance(system_profile_value, Mapping):
            raise ContractError(f"{task_id}: system_profile binding is required")
        if system_profile_value.get("schema") != "simuverity.system-profile.v1":
            raise ContractError(f"{task_id}: system_profile schema is invalid")
        system_profile_value = system_profile_value.get("path")
        if isinstance(scenarios_value, Mapping):
            scenarios_value = scenarios_value.get("path")
        scorer_value, scorer_kind, scorer_entrypoint = _scorer_binding(raw)
        scorer_kind = {"python_function": "python"}.get(scorer_kind, scorer_kind)
        if scorer_kind != "python":
            raise ContractError(f"{task_id}: public offline scorers must be Python")
        extractor_value, extractor_kind, extractor_entrypoint = _extractor_binding(raw)
        extractor_kind = {"matlab_function": "matlab", "python_function": "python"}.get(
            extractor_kind, extractor_kind
        )
        if extractor_kind not in {"matlab", "python"}:
            raise ContractError(f"{task_id}: extractor kind must be matlab or python")
        public_path = _resolve_task_path(task_root, public_value, field="public_spec")
        system_profile_path = _resolve_task_path(
            task_root, system_profile_value, field="system_profile.path"
        )
        scenarios_path = _resolve_task_path(task_root, scenarios_value, field="official_scenarios")
        scorer_path = _resolve_task_path(task_root, scorer_value, field="scorer.path")
        extractor_path = _resolve_task_path(task_root, extractor_value, field="extractor.path")
        extractor_binding = raw.get("extractor")
        sidecar_rows = extractor_binding.get("sidecars", []) if isinstance(extractor_binding, Mapping) else []
        if not isinstance(sidecar_rows, list):
            raise ContractError(f"{task_id}: extractor.sidecars must be an array")
        sidecars: list[ExtractorSidecar] = []
        sidecar_roles: set[str] = set()
        sidecar_outputs: set[str] = set()
        for index, item in enumerate(sidecar_rows):
            if not isinstance(item, Mapping):
                raise ContractError(f"{task_id}: extractor.sidecars[{index}] must be an object")
            role = item.get("role")
            kind = item.get("kind")
            producer_value = item.get("path")
            arguments = item.get("arguments")
            output_name = item.get("output")
            expected_schema = item.get("schema")
            if not isinstance(role, str) or not SIDECAR_ROLE_RE.fullmatch(role) or role in sidecar_roles:
                raise ContractError(f"{task_id}: extractor sidecar role is invalid or duplicated")
            if kind != "python":
                raise ContractError(f"{task_id}: extractor sidecars currently require kind=python")
            producer_path = _resolve_task_path(
                task_root, producer_value, field=f"extractor.sidecars[{index}].path"
            )
            if not producer_path.is_file() or producer_path.suffix.lower() != ".py":
                raise ContractError(f"{task_id}: extractor sidecar producer is missing or not Python")
            if (
                not isinstance(arguments, list)
                or not arguments
                or not all(isinstance(value, str) and value for value in arguments)
                or any("{" in value and value not in {"{candidate}", "{output}"} for value in arguments)
            ):
                raise ContractError(f"{task_id}: extractor sidecar arguments are invalid")
            if (
                not isinstance(output_name, str)
                or Path(output_name).name != output_name
                or not output_name.endswith(".json")
                or output_name in sidecar_outputs
            ):
                raise ContractError(f"{task_id}: extractor sidecar output must name one JSON file")
            if not isinstance(expected_schema, str) or not expected_schema:
                raise ContractError(f"{task_id}: extractor sidecar schema is required")
            sidecar_roles.add(role)
            sidecar_outputs.add(output_name)
            sidecars.append(
                ExtractorSidecar(
                    role=role,
                    kind=kind,
                    producer_path=producer_path,
                    arguments=tuple(arguments),
                    output_name=output_name,
                    expected_schema=expected_schema,
                )
            )
        for field, path in (
            ("public_spec", public_path),
            ("system_profile", system_profile_path),
            ("official_scenarios", scenarios_path),
            ("scorer", scorer_path),
        ):
            if not path.is_file():
                raise ContractError(f"{task_id}: {field} is missing: {path}")
        if extractor_kind == "python" and not extractor_path.is_file():
            raise ContractError(f"{task_id}: extractor is missing: {extractor_path}")
        if extractor_kind == "matlab" and not extractor_path.exists():
            raise ContractError(f"{task_id}: extractor is missing: {extractor_path}")
        public_spec = load_json(public_path)
        if not isinstance(public_spec, Mapping):
            raise ContractError(f"{task_id}: public_spec.json must be an object")
        required_model = (
            raw.get("required_model_file")
            or raw.get("candidate_filename")
            or public_spec.get("required_model_file")
            or public_spec.get("candidate_filename")
            or public_spec.get("submission_model")
        )
        if not isinstance(required_model, str) or Path(required_model).name != required_model or not required_model.lower().endswith((".slx", ".mdl")):
            raise ContractError(f"{task_id}: required_model_file must name one .slx or .mdl file")
        policy_id = raw.get("evaluation_policy_id")
        if not isinstance(policy_id, str) or not policy_id.strip():
            raise ContractError(f"{task_id}: evaluation_policy_id is required")
        expected_policy_id = f"simuverity-101-v1:{task_id.casefold()}:scoring"
        if policy_id != expected_policy_id:
            raise ContractError(
                f"{task_id}: evaluation_policy_id must be {expected_policy_id}"
            )
        collection = raw.get("collection") or raw.get("collection_identity")
        if not isinstance(collection, str) or not collection:
            collection = task_id.split("-", 1)[0]
        reference = raw.get("reference", {})
        if not isinstance(reference, Mapping):
            raise ContractError(f"{task_id}: reference must be an object")
        closure = raw.get("candidate_closure", {})
        public_names = raw.get("public_input_names")
        if public_names is None and isinstance(closure, Mapping):
            public_names = closure.get("public_input_names", closure.get("public_base_workspace_inputs"))
        contracts_path = (
            Path(__file__).resolve().parent
            / "runtime"
            / "matlab"
            / "nominal_inputs"
            / "public_input_contracts.json"
        )
        contracts = load_json(contracts_path)
        rows = contracts.get("tasks", []) if isinstance(contracts, Mapping) else []
        matching = [row for row in rows if isinstance(row, Mapping) and row.get("task_id") == task_id]
        if public_names is None:
            if len(matching) != 1:
                raise ContractError(f"{task_id}: public input names are not bound")
            public_names = matching[0].get("public_input_names")
        if not isinstance(public_names, list) or not all(isinstance(name, str) and name for name in public_names):
            raise ContractError(f"{task_id}: public_input_names must be a string array")
        if len(public_names) != len(set(public_names)):
            raise ContractError(f"{task_id}: public_input_names contains duplicates")
        if raw.get("release") == "simuverity-101-v1":
            if len(matching) != 1 or public_names != matching[0].get("public_input_names"):
                raise ContractError(f"{task_id}: public_input_names differ from the current release contract")
        return TaskDefinition(
            task_id=task_id,
            collection=collection,
            root=task_root,
            manifest_path=manifest_path.resolve(),
            public_spec_path=public_path,
            system_profile_path=system_profile_path,
            scenarios_path=scenarios_path,
            scorer_path=scorer_path,
            scorer_entrypoint=scorer_entrypoint,
            extractor_path=extractor_path,
            extractor_kind=extractor_kind,
            extractor_entrypoint=extractor_entrypoint,
            extractor_sidecars=tuple(sidecars),
            evaluation_policy_id=policy_id,
            required_model_file=required_model,
            public_input_names=tuple(public_names),
            reference=reference,
            raw=raw,
        )

    @staticmethod
    def prompt_bytes(task: TaskDefinition) -> bytes:
        spec = load_json(task.public_spec_path)
        prompt = spec.get("prompt") if isinstance(spec, Mapping) else None
        if not isinstance(prompt, str) or not prompt.strip():
            raise ContractError(f"{task.task_id}: public spec has no prompt")
        return prompt.encode("utf-8")

    def summary(self, task: TaskDefinition) -> dict[str, Any]:
        reference_mode = task.reference.get("materialization", task.reference.get("mode", "bundled"))
        return {
            "task_id": task.task_id,
            "collection": task.collection,
            "evaluation_policy_id": task.evaluation_policy_id,
            "required_model_file": task.required_model_file,
            "public_input_names": list(task.public_input_names),
            "reference_materialization": reference_mode,
        }
