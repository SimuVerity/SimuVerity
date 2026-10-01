from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from ..errors import InfrastructureError
from ..jsonutil import load_json, write_json_exclusive
from ..types import TaskDefinition


def run_offline_scorer(
    task: TaskDefinition,
    *,
    evidence_path: Path,
    output_root: Path,
    context: dict[str, Any],
) -> dict[str, Any]:
    output_root.mkdir(parents=True, exist_ok=False)
    context_path = output_root / "context.json"
    score_path = output_root / "score.json"
    write_json_exclusive(context_path, context)
    environment = os.environ.copy()
    for name in (
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "AZURE_OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "MATLAB_PREFDIR",
        "SIMULINK_CACHE_FOLDER",
        "SIMULINK_CODEGEN_FOLDER",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "FTP_PROXY",
    ):
        environment.pop(name, None)
    environment["SIMUVERITY_OFFLINE_SCORING"] = "1"
    command = [
        sys.executable,
        "-I",
        str(Path(__file__).with_name("offline_worker.py")),
        "--scorer",
        str(task.scorer_path),
        "--entrypoint",
        task.scorer_entrypoint,
        "--evidence",
        str(evidence_path),
        "--context",
        str(context_path),
        "--output",
        str(score_path),
    ]
    completed = subprocess.run(command, env=environment, cwd=output_root, capture_output=True, text=True, encoding="utf-8")
    (output_root / "stdout.log").write_text(completed.stdout, encoding="utf-8", newline="\n")
    (output_root / "stderr.log").write_text(completed.stderr, encoding="utf-8", newline="\n")
    if completed.returncode != 0 or not score_path.is_file():
        raise InfrastructureError(f"Offline scorer failed with exit code {completed.returncode}")
    value = load_json(score_path)
    if not isinstance(value, dict):
        raise InfrastructureError("Offline scorer returned an invalid result")
    return value
