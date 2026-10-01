from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .repository import TaskRepository


def is_matlab_r2025a(value: str) -> bool:
    """Accept MATLAB's documented release spellings, but no other release."""

    return re.fullmatch(r"R?2025A", value.strip(), flags=re.IGNORECASE) is not None


def _version(command: str, arguments: list[str]) -> dict[str, Any]:
    path = shutil.which(command)
    if not path:
        return {"ok": False, "path": "", "version": ""}
    try:
        completed = subprocess.run(
            [path, *arguments], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20
        )
        text = (completed.stdout or completed.stderr).strip().splitlines()
        return {"ok": completed.returncode == 0, "path": path, "version": text[0] if text else ""}
    except Exception as exc:
        return {"ok": False, "path": path, "version": str(exc)}


def run_doctor(repository: TaskRepository) -> dict[str, Any]:
    checks = {
        "windows": {"ok": os.name == "nt", "value": platform.platform()},
        "powershell_7": _version("pwsh", ["-NoLogo", "-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"]),
        "matlab": _version("matlab", ["-batch", "disp(version('-release'))"]),
        "codex": _version("codex", ["--version"]),
        "claude_code": _version("claude", ["--version"]),
    }
    matlab_release = str(checks["matlab"].get("version", ""))
    checks["matlab_r2025a"] = {
        "ok": is_matlab_r2025a(matlab_release),
        "value": matlab_release,
    }
    try:
        task_count = len(repository.task_ids())
        registry = {"ok": task_count == 101, "task_count": task_count}
    except Exception as exc:
        registry = {"ok": False, "task_count": 0, "error": str(exc)}
    checks["registry_101"] = registry
    required = ("windows", "powershell_7", "matlab_r2025a", "registry_101")
    return {
        "schema": "simuverity.doctor.v1",
        "status": "PASS" if all(checks[name]["ok"] for name in required) else "FAIL",
        "checks": checks,
        "local_mode_only": True,
        "os_isolation_configured": False,
    }
