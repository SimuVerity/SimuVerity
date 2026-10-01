from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as stream:
        return json.load(stream)


def write_json_exclusive(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    handle = os.open(path, flags, 0o600)
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(canonical_json_bytes(value))
    except BaseException:
        try:
            path.unlink(missing_ok=True)
        finally:
            raise


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_bytes(canonical_json_bytes(value))
    os.replace(temporary, path)
