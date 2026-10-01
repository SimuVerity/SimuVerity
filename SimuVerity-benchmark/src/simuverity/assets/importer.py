from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
import uuid
from dataclasses import replace
from pathlib import Path, PureWindowsPath
from typing import Any, Mapping

from ..errors import ContractError, InfrastructureError
from ..jsonutil import load_json, write_json_exclusive
from ..types import TaskDefinition


def _remove_runtime_tree(path: Path) -> None:
    """Remove one exact evaluator-owned temporary tree."""

    resolved = path.resolve()
    if resolved.parent == resolved:
        raise ValueError("Refusing to remove a filesystem root as an evaluator temp tree")
    cleanup_path: str | Path = resolved
    if os.name == "nt":
        value = str(resolved)
        if not value.startswith("\\\\?\\"):
            value = "\\\\?\\UNC\\" + value[2:] if value.startswith("\\\\") else "\\\\?\\" + value
        cleanup_path = value

    def ignore_disappeared(_function, _name, exception_info) -> None:
        error = exception_info[1]
        if isinstance(error, FileNotFoundError) or getattr(error, "winerror", None) == 3:
            return
        raise error.with_traceback(exception_info[2])

    for attempt in range(100):
        if not os.path.exists(cleanup_path):
            return
        for current, directories, files in os.walk(
            cleanup_path, topdown=False, followlinks=False
        ):
            for name in [*files, *directories]:
                item = Path(current) / name
                try:
                    item.chmod(item.stat().st_mode | stat.S_IWUSR)
                except OSError:
                    pass
        try:
            shutil.rmtree(cleanup_path, onerror=ignore_disappeared)
            return
        except OSError as error:
            retryable = getattr(error, "winerror", None) == 145 or error.errno == 39
            if not retryable or attempt == 99:
                raise
            time.sleep(0.05)


def default_asset_root(release: str = "simuverity-101-v1") -> Path:
    local = os.environ.get("LOCALAPPDATA")
    base = Path(local) if local else Path.home() / "AppData" / "Local"
    return base / "SimuVerity" / "assets" / release


def _relative(value: Any, field: str) -> Path:
    if (
        not isinstance(value, str)
        or not value
        or Path(value).is_absolute()
        or PureWindowsPath(value).is_absolute()
        or ":" in value
    ):
        raise ContractError(f"{field} must be a repository-relative path")
    result = Path(value.replace("\\", "/"))
    if result.as_posix() != value.replace("\\", "/") or any(
        part in {"", ".", ".."} for part in result.parts
    ):
        raise ContractError(f"{field} escapes its declared root")
    return result


def _matlab_literal(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def _matlab_function_name(path: Path) -> str:
    text = path.read_text(encoding="utf-8-sig", errors="replace")[:4096]
    match = re.search(r"function\s+(?:\w+\s*=\s*)?([A-Za-z]\w*)\s*\(", text)
    if not match:
        raise ContractError(f"Cannot determine MATLAB transform entrypoint: {path}")
    return match.group(1)


def _file_rows(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in sorted((item for item in root.rglob("*") if item.is_file()), key=lambda p: p.as_posix()):
        rows.append(
            {
                "path": path.relative_to(root).as_posix(),
                "size_bytes": path.stat().st_size,
            }
        )
    return rows


def _verify_rows(root: Path, rows: Any, *, path_key: str) -> list[Path]:
    if not isinstance(rows, list):
        raise ContractError("File inventory must be an array")
    resolved: list[Path] = []
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, Mapping):
            raise ContractError("File inventory entries must be objects")
        relative = _relative(row.get(path_key), f"files[].{path_key}")
        text = relative.as_posix()
        if text in seen:
            raise ContractError(f"Duplicate file inventory path: {text}")
        seen.add(text)
        path = root / relative
        if not path.is_file():
            raise InfrastructureError(f"Declared file is missing: {text}")
        expected_size = row.get("size_bytes")
        if expected_size is not None and (
            not isinstance(expected_size, int)
            or isinstance(expected_size, bool)
            or expected_size < 0
            or path.stat().st_size != expected_size
        ):
            raise InfrastructureError(f"Declared file size differs: {text}")
        resolved.append(path)
    return resolved


def _verify_expected_names(root: Path, names: Any) -> None:
    if not isinstance(names, list) or not all(
        isinstance(name, str) and Path(name).name == name for name in names
    ):
        raise ContractError("Importer expected_source_filenames must be a filename array")
    missing = [name for name in names if not (root / name).is_file()]
    if missing:
        raise InfrastructureError("Importer output is missing: " + ", ".join(missing))


def _validation_contract(reference: Mapping[str, Any], recipe: Mapping[str, Any]) -> dict[str, Any]:
    validation = recipe.get("validation", {})
    if not isinstance(validation, Mapping):
        validation = {}
    entrypoint = reference.get("entrypoint", validation.get("reference_entrypoint"))
    expected_score = reference.get("expected_score", validation.get("expected_reference_score"))
    expected_scenarios = reference.get(
        "expected_valid_scenarios", validation.get("expected_valid_scenario_count")
    )
    tolerance = reference.get("score_tolerance", validation.get("score_tolerance", 1e-9))
    scenario_contract = reference.get("scenario_contract", {})
    if not isinstance(scenario_contract, Mapping):
        scenario_contract = {}
    ready = (
        isinstance(entrypoint, str)
        and bool(entrypoint)
        and isinstance(expected_score, (int, float))
        and not isinstance(expected_score, bool)
        and isinstance(expected_scenarios, int)
        and not isinstance(expected_scenarios, bool)
        and expected_scenarios > 0
        and isinstance(tolerance, (int, float))
        and not isinstance(tolerance, bool)
        and tolerance >= 0
    )
    return {
        "entrypoint": entrypoint,
        "expected_score": expected_score,
        "expected_valid_scenarios": expected_scenarios,
        "expected_scenario_ids": scenario_contract.get("expected_ids"),
        "nominal_scenario_id": scenario_contract.get("nominal_scenario_id"),
        "score_tolerance": tolerance,
        "ready": ready,
    }


def _scenario_is_valid(row: Any) -> bool:
    if not isinstance(row, Mapping):
        return False
    for name in ("valid", "evidence_valid", "score_inputs_valid"):
        if isinstance(row.get(name), bool):
            return bool(row[name])
    status = row.get("status")
    if isinstance(status, str):
        return status.upper() in {"PASS", "PASSED", "VALID", "OK", "COMPLETED", "SCORED"}
    return True


def _scenario_identifier(row: Any) -> str | None:
    if not isinstance(row, Mapping):
        return None
    values = {
        str(row[name])
        for name in ("id", "scenario_id", "scenario")
        if isinstance(row.get(name), str) and row[name]
    }
    if len(values) > 1:
        raise InfrastructureError("Reference row has conflicting scenario identifiers")
    return next(iter(values), None)


def _reference_scenario_rows(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    if not isinstance(value, Mapping):
        raise InfrastructureError("Reference score has no per-scenario rows")
    rows: list[Any] = []
    for mapping_id, payload in value.items():
        if not isinstance(mapping_id, str) or not mapping_id or not isinstance(payload, Mapping):
            raise InfrastructureError("Reference score has invalid id-keyed scenario rows")
        row = dict(payload)
        embedded = _scenario_identifier(row)
        if embedded is None:
            row["id"] = mapping_id
        elif embedded != mapping_id:
            raise InfrastructureError("Reference scenario identifier conflicts with its mapping key")
        rows.append(row)
    return rows


def validate_reference_score(receipt: Mapping[str, Any], contract: Mapping[str, Any]) -> dict[str, Any]:
    if not contract.get("ready"):
        raise ContractError("Reference validation contract is incomplete")
    if receipt.get("evidence_complete") is not True or not isinstance(receipt.get("score"), Mapping):
        raise InfrastructureError("Reference evaluation did not produce complete scored evidence")
    score = receipt["score"]
    if score.get("G") is not True:
        raise InfrastructureError("Reference failed qualification gate G")
    total = score.get("total")
    if not isinstance(total, (int, float)) or isinstance(total, bool):
        raise InfrastructureError("Reference score is missing")
    expected = float(contract["expected_score"])
    tolerance = float(contract["score_tolerance"])
    if abs(float(total) - expected) > tolerance:
        raise InfrastructureError(
            f"Reference total differs: expected {expected:.17g}, observed {float(total):.17g}"
        )
    scenarios = _reference_scenario_rows(score.get("scenarios"))
    expected_ids = contract.get("expected_scenario_ids")
    if expected_ids is not None:
        if (
            not isinstance(expected_ids, list)
            or not expected_ids
            or any(not isinstance(item, str) or not item for item in expected_ids)
            or len(set(expected_ids)) != len(expected_ids)
            or len(expected_ids) != int(contract["expected_valid_scenarios"])
        ):
            raise ContractError("Reference scenario contract has invalid expected_ids")
        expected_set = set(expected_ids)
        accepted_extra = {"nominal"}
        nominal = contract.get("nominal_scenario_id")
        if isinstance(nominal, str) and nominal:
            accepted_extra.add(nominal)
        seen: set[str] = set()
        valid: set[str] = set()
        for row in scenarios:
            identifier = _scenario_identifier(row)
            if identifier is None or identifier in seen:
                raise InfrastructureError("Reference scenario identifiers are missing or duplicated")
            seen.add(identifier)
            if identifier in expected_set:
                if _scenario_is_valid(row):
                    valid.add(identifier)
            elif identifier not in accepted_extra:
                raise InfrastructureError(f"Reference has unexpected scenario: {identifier}")
        valid_count = len(valid)
    else:
        valid_count = sum(_scenario_is_valid(row) for row in scenarios)
    if valid_count != int(contract["expected_valid_scenarios"]):
        raise InfrastructureError(
            f"Reference valid-scenario count differs: expected {contract['expected_valid_scenarios']}, observed {valid_count}"
        )
    return {"G": True, "total": float(total), "valid_scenario_count": valid_count}


def _validate_direct_reference(task: TaskDefinition) -> dict[str, Any]:
    reference = task.reference
    manifest_path = task.root / _relative(
        reference.get("manifest", "reference/manifest.json"), "reference.manifest"
    )
    manifest = load_json(manifest_path)
    if (
        not isinstance(manifest, Mapping)
        or manifest.get("schema") != "simuverity.direct-reference-manifest.v1"
        or manifest.get("task_id") != task.task_id
    ):
        raise ContractError(f"{task.task_id}: direct reference manifest is invalid")
    rows = manifest.get("files")
    if not isinstance(rows, list) or not rows or manifest.get("file_count") != len(rows):
        raise ContractError(f"{task.task_id}: direct reference inventory is invalid")
    _verify_rows(task.root, rows, path_key="path")
    entry_text = reference.get("entrypoint")
    if entry_text != manifest.get("entrypoint"):
        raise ContractError(f"{task.task_id}: task and reference manifest entrypoints differ")
    entrypoint = task.root / _relative(entry_text, "reference.entrypoint")
    source_root = task.root / _relative(reference.get("path"), "reference.path")
    if not entrypoint.is_file():
        raise InfrastructureError(f"{task.task_id}: reference entrypoint is missing")
    try:
        entrypoint_relative = entrypoint.relative_to(source_root)
    except ValueError as exc:
        raise ContractError(f"{task.task_id}: reference entrypoint is outside its closure") from exc
    return {
        "source_root": source_root.resolve(),
        "entrypoint_relative": entrypoint_relative,
        "file_count": len(rows),
    }


def _run_reference_validation(
    task: TaskDefinition,
    *,
    source_root: Path,
    entrypoint_relative: Path,
    contract: Mapping[str, Any],
    work_root: Path,
) -> dict[str, Any]:
    reference_model = source_root / entrypoint_relative
    if not reference_model.is_file():
        raise InfrastructureError(f"Reference entrypoint is missing: {entrypoint_relative.as_posix()}")
    validation_submission = work_root / "validation_submission"
    shutil.copytree(source_root, validation_submission)
    candidate_name = reference_model.name
    candidate = validation_submission / candidate_name
    staged_reference = validation_submission / entrypoint_relative
    if staged_reference.resolve() != candidate.resolve():
        shutil.copy2(staged_reference, candidate)
    from ..evaluation.pipeline import evaluate_submission

    evaluation_task = replace(task, required_model_file=candidate_name)
    evaluation = evaluate_submission(
        evaluation_task,
        submission_root=validation_submission,
        output_parent=work_root / "evaluations",
        generation_run_id=f"assetref_{uuid.uuid4().hex[:20]}",
        scoring_run_id=f"assetval_{uuid.uuid4().hex[:20]}",
        evaluator_asset_root=validation_submission,
        evaluation_subject="reference",
    )
    validated = validate_reference_score(evaluation, contract)
    return {"evaluation": evaluation, "validated": validated}


def _load_recipe(task: TaskDefinition) -> tuple[Path, Mapping[str, Any], Path, str]:
    reference = task.reference
    recipe_path = task.root / _relative(reference.get("recipe"), "reference.recipe")
    recipe = load_json(recipe_path)
    if not isinstance(recipe, Mapping) or recipe.get("task_id") != task.task_id:
        raise ContractError(f"{task.task_id}: importer recipe is invalid")
    transform = recipe_path.parent / _relative(recipe.get("transform"), "recipe.transform")
    if not transform.is_file():
        raise ContractError(f"{task.task_id}: importer transform is missing")
    return recipe_path, recipe, transform, _matlab_function_name(transform)


def _verify_materialized(
    root: Path, *, reference: Mapping[str, Any], recipe: Mapping[str, Any]
) -> Path:
    discovery = recipe.get("discovery", {})
    if isinstance(discovery, Mapping):
        names = discovery.get("expected_source_filenames")
        if names is not None:
            _verify_expected_names(root, names)
        rows = discovery.get("expected_files")
        if isinstance(rows, list):
            if all(isinstance(row, Mapping) and "path" in row for row in rows):
                path_key = "path"
            elif all(isinstance(row, Mapping) and "name" in row for row in rows):
                path_key = "name"
            else:
                raise ContractError("Importer expected_files must use one path field")
            _verify_rows(root, rows, path_key=path_key)
    entrypoint = root / _relative(reference.get("entrypoint"), "reference.entrypoint")
    if not entrypoint.is_file():
        raise InfrastructureError("Materialized reference entrypoint is missing")
    return entrypoint


def resolve_reference_asset_root(
    task: TaskDefinition, *, asset_root: Path | None = None
) -> Path:
    """Resolve reference support without exposing it to generation."""

    reference = task.reference
    mode = str(reference.get("materialization", "bundled"))
    if mode == "bundled":
        root = task.root / _relative(reference.get("path"), "reference.path")
        if not root.is_dir():
            raise ContractError(f"{task.task_id}: bundled reference root is missing")
        return root.resolve()
    if mode != "local_importer":
        raise ContractError(f"Unsupported reference materialization: {mode}")
    recipe_path, recipe, _transform, _entrypoint = _load_recipe(task)
    del recipe_path
    release = str(recipe.get("release", task.raw.get("release", "simuverity-101-v1")))
    base = (asset_root or default_asset_root(release)).resolve()
    task_root = (base / task.task_id).resolve()
    try:
        task_root.relative_to(base)
    except ValueError as exc:
        raise ContractError("Asset destination escaped the configured cache") from exc
    receipt_path = task_root / "asset_receipt.json"
    receipt = load_json(receipt_path) if receipt_path.is_file() else None
    if (
        not isinstance(receipt, Mapping)
        or receipt.get("schema") != "simuverity.reference-asset-receipt.v1"
        or receipt.get("status") != "READY"
        or receipt.get("task_id") != task.task_id
    ):
        raise ContractError(
            f"{task.task_id}: reference assets are not READY; run 'simuverity assets prepare {task.task_id}' first"
        )
    files = task_root / "files"
    _verify_materialized(files, reference=reference, recipe=recipe)
    return files


def _write_ready_receipts(
    temporary: Path,
    *,
    task: TaskDefinition,
    mode: str,
    files: Path,
    validated: Mapping[str, Any],
) -> None:
    rows = _file_rows(files)
    write_json_exclusive(
        temporary / "materialization_manifest.json",
        {
            "schema": "simuverity.reference-materialization.v1",
            "task_id": task.task_id,
            "entrypoint": f"files/{task.reference['entrypoint']}",
            "file_count": len(rows),
            "files": rows,
        },
    )
    write_json_exclusive(
        temporary / "reference_validation.json",
        {
            "schema": "simuverity.reference-validation.v1",
            "task_id": task.task_id,
            "evaluation_policy_id": task.evaluation_policy_id,
            "G": validated["G"],
            "total": validated["total"],
            "valid_scenario_count": validated["valid_scenario_count"],
        },
    )
    write_json_exclusive(
        temporary / "asset_receipt.json",
        {
            "schema": "simuverity.reference-asset-receipt.v1",
            "status": "READY",
            "task_id": task.task_id,
            "release": task.raw.get("release", "simuverity-101-v1"),
            "mode": mode,
            "entrypoint": f"files/{task.reference['entrypoint']}",
            "reference_regression_complete": True,
        },
    )


def _prepare_bundled_reference(
    task: TaskDefinition, *, dry_run: bool
) -> dict[str, Any]:
    closure = _validate_direct_reference(task)
    contract = _validation_contract(task.reference, {})
    plan = {
        "schema": "simuverity.reference-asset-plan.v1",
        "task_id": task.task_id,
        "mode": "bundled",
        "entrypoint": task.reference.get("entrypoint"),
        "file_count": closure["file_count"],
        "would_start_matlab": not dry_run,
    }
    if dry_run:
        return plan
    work_root = Path(tempfile.mkdtemp(prefix="sv-ref-"))
    try:
        result = _run_reference_validation(
            task,
            source_root=closure["source_root"],
            entrypoint_relative=closure["entrypoint_relative"],
            contract=contract,
            work_root=work_root,
        )
        return {
            **plan,
            "status": "READY",
            "would_start_matlab": True,
            **result["validated"],
        }
    finally:
        _remove_runtime_tree(work_root)


def _prepare_importer_reference(
    task: TaskDefinition,
    *,
    asset_root: Path | None,
    matlab_executable: str,
    dry_run: bool,
    evidence_bundle_path: Path | None,
    materialized_root: Path | None,
) -> dict[str, Any]:
    recipe_path, recipe, transform, transform_entrypoint = _load_recipe(task)
    contract = _validation_contract(task.reference, recipe)
    release = str(recipe.get("release", task.raw.get("release", "simuverity-101-v1")))
    base = (asset_root or default_asset_root(release)).resolve()
    destination = (base / task.task_id).resolve()
    try:
        destination.relative_to(base)
    except ValueError as exc:
        raise ContractError("Asset destination escaped the configured cache") from exc
    plan = {
        "schema": "simuverity.reference-asset-plan.v1",
        "task_id": task.task_id,
        "mode": "local_importer",
        "release": release,
        "entrypoint": task.reference.get("entrypoint"),
        "would_start_matlab": evidence_bundle_path is None and not dry_run,
        "reference_validation_ready": contract["ready"],
        "expected_reference_score": contract["expected_score"],
    }
    if dry_run:
        return plan
    if destination.exists():
        files = resolve_reference_asset_root(task, asset_root=asset_root)
        del files
        return {**plan, "status": "READY", "cache_reused": True, "would_start_matlab": False}

    base.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".sv-", dir=base))
    files = temporary / "files"
    try:
        if evidence_bundle_path is None:
            helper = (
                Path(__file__).resolve().parents[1]
                / "runtime"
                / "matlab"
                / "simuverity_prepare_importer.m"
            )
            import_receipt = temporary / "import_receipt.json"
            expression = (
                f"addpath({_matlab_literal(helper.parent)},'-begin');"
                f"simuverity_prepare_importer({_matlab_literal(recipe_path)},"
                f"{_matlab_literal(transform)},{_matlab_literal(transform_entrypoint)},"
                f"{_matlab_literal(files)},{_matlab_literal(import_receipt)});"
            )
            completed = subprocess.run(
                [matlab_executable, "-batch", expression],
                cwd=temporary,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            (temporary / "stdout.log").write_text(completed.stdout, encoding="utf-8", newline="\n")
            (temporary / "stderr.log").write_text(completed.stderr, encoding="utf-8", newline="\n")
            if completed.returncode != 0 or not import_receipt.is_file():
                raise InfrastructureError(f"Reference importer failed with exit code {completed.returncode}")
            _verify_materialized(files, reference=task.reference, recipe=recipe)
            result = _run_reference_validation(
                task,
                source_root=files,
                entrypoint_relative=_relative(task.reference.get("entrypoint"), "reference.entrypoint"),
                contract=contract,
                work_root=temporary / "validation",
            )
            validated = result["validated"]
            mode = "local_importer"
            _remove_runtime_tree(temporary / "validation")
        else:
            if materialized_root is None:
                raise ContractError("Offline resume requires a materialized reference root")
            source = materialized_root.resolve()
            if not source.is_dir():
                raise ContractError("Offline resume materialized root is missing")
            shutil.copytree(source, files)
            _verify_materialized(files, reference=task.reference, recipe=recipe)
            from ..evaluation.pipeline import rescore_evidence

            evaluation = rescore_evidence(
                task,
                evidence_bundle_path=evidence_bundle_path,
                output_parent=temporary / "rescoring",
                scoring_run_id=f"assetrescore_{uuid.uuid4().hex[:20]}",
            )
            validated = validate_reference_score(evaluation, contract)
            mode = "local_importer_offline_resume"
            _remove_runtime_tree(temporary / "rescoring")

        _write_ready_receipts(
            temporary, task=task, mode=mode, files=files, validated=validated
        )
        temporary.replace(destination)
    except BaseException as exc:
        if hasattr(exc, "add_note"):
            exc.add_note(f"Failed importer retained at {temporary}")
        raise
    return {
        **plan,
        "status": "READY",
        "cache_reused": False,
        "would_start_matlab": evidence_bundle_path is None,
        "receipt_path": str(destination / "asset_receipt.json"),
    }


def prepare_reference_asset(
    task: TaskDefinition,
    *,
    asset_root: Path | None = None,
    matlab_executable: str = "matlab",
    dry_run: bool = False,
    evidence_bundle_path: Path | None = None,
    materialized_root: Path | None = None,
) -> dict[str, Any]:
    if (evidence_bundle_path is None) != (materialized_root is None):
        raise ContractError("Offline importer resume requires both paths")
    if dry_run and evidence_bundle_path is not None:
        raise ContractError("Offline importer resume cannot be combined with --dry-run")
    mode = str(task.reference.get("materialization", "bundled"))
    if mode == "bundled":
        if evidence_bundle_path is not None:
            raise ContractError("Bundled references do not use the importer resume path")
        return _prepare_bundled_reference(task, dry_run=dry_run)
    if mode == "local_importer":
        return _prepare_importer_reference(
            task,
            asset_root=asset_root,
            matlab_executable=matlab_executable,
            dry_run=dry_run,
            evidence_bundle_path=evidence_bundle_path,
            materialized_root=materialized_root,
        )
    raise ContractError(f"Unsupported reference materialization: {mode}")
