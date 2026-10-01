from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..errors import ContractError
from ..jsonutil import write_json_exclusive

IDENTITY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def reserve_identity(repository_root: Path, *, kind: str, identity: str, task_id: str) -> Path:
    if kind not in {"generation", "scoring"} or not IDENTITY_RE.fullmatch(identity):
        raise ContractError(f"Invalid {kind} identity: {identity}")
    registry = repository_root.resolve() / ".simuverity" / "identities" / kind
    path = registry / f"{identity}.json"
    record: dict[str, Any] = {
        "schema": "simuverity.run-identity-reservation.v1",
        "kind": kind,
        "identity": identity,
        "task_id": task_id,
        "reserved_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    try:
        write_json_exclusive(path, record)
    except FileExistsError as exc:
        raise ContractError(f"{kind.title()} identity has already been used: {identity}") from exc
    return path
