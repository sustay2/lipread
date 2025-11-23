"""
Entry point for running the FastAPI admin backend outside Docker while
keeping Docker compatibility.
"""
from __future__ import annotations

import os
import pathlib
import re
import sys
from typing import Iterable, Tuple

import uvicorn


BASE_DIR = pathlib.Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR
ENV_FILE = PROJECT_ROOT / ".env"
DOCKERFILE_PATH = PROJECT_ROOT / "Dockerfile"


FIREBASE_KEYS = {
    "FIREBASE_PROJECT_ID",
    "FIREBASE_CLIENT_EMAIL",
    "FIREBASE_PRIVATE_KEY",
}


def parse_env_file(path: pathlib.Path) -> dict[str, str]:
    if not path.exists():
        return {}
    parsed: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if not line or re.match(r"^\s*#", line):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key:
            parsed[key] = value
    return parsed


ENV_FILE_VALUES = parse_env_file(ENV_FILE)


def firebase_defaults_from_env_values(env_values: dict[str, str]) -> dict[str, str]:
    return {key: value for key, value in env_values.items() if key in FIREBASE_KEYS and value}


def load_env_file(path: pathlib.Path, cached_values: dict[str, str] | None = None) -> None:
    values = cached_values if cached_values is not None else parse_env_file(path)
    for key, value in values.items():
        if key and key not in os.environ:
            os.environ[key] = value


def parse_dockerfile_env(dockerfile: pathlib.Path) -> Iterable[Tuple[str, str]]:
    if not dockerfile.exists():
        return []
    env_pattern = re.compile(r"^\s*ENV\s+(.*)$", re.IGNORECASE)
    entries: list[Tuple[str, str]] = []
    for raw_line in dockerfile.read_text().splitlines():
        match = env_pattern.match(raw_line)
        if not match:
            continue
        payload = match.group(1).strip()
        # ENV KEY value or ENV key1=value1 key2=value2
        parts = []
        if "=" in payload and not payload.split()[0].startswith("$"):
            # handle key=value forms separated by spaces
            for token in re.split(r"\s+", payload):
                if "=" in token:
                    k, v = token.split("=", 1)
                    parts.append((k, v))
        else:
            tokens = payload.split(None, 1)
            if len(tokens) == 2:
                parts.append((tokens[0], tokens[1]))
        entries.extend(parts)
    return entries


def apply_dockerfile_env(dockerfile: pathlib.Path) -> None:
    for key, value in parse_dockerfile_env(dockerfile):
        if key and key not in os.environ:
            os.environ[key] = value


def apply_firebase_defaults(defaults: dict[str, str]) -> None:
    for key, value in defaults.items():
        if not os.environ.get(key):
            os.environ[key] = value


def running_in_docker() -> bool:
    if os.environ.get("RUNNING_IN_DOCKER"):
        return True
    if pathlib.Path("/.dockerenv").exists():
        return True
    try:
        cgroup = pathlib.Path("/proc/1/cgroup")
        if cgroup.exists() and "docker" in cgroup.read_text():
            return True
    except OSError:
        pass
    return False


def locate_app():
    """Locate the FastAPI ``app`` instance regardless of invocation path."""

    candidate_roots = [PROJECT_ROOT, PROJECT_ROOT.parent, PROJECT_ROOT.parent.parent]
    for path in candidate_roots:
        path_str = str(path)
        if path_str not in sys.path:
            sys.path.insert(0, path_str)

    module_candidates = [
        "app.app",
        "app.main",
        "backend.app.main",
        "backend.app.app",
        "admin_panel.backend.app.main",
        "admin_panel.backend.app.app",
    ]

    for module_name in module_candidates:
        try:
            module = __import__(module_name, fromlist=["app"])
            app_instance = getattr(module, "app", None)
            if app_instance is not None:
                return app_instance
        except Exception:
            continue

    # As a final fallback, load the app module directly from the expected file path
    # to avoid import issues caused by unexpected working directories or Python paths.
    app_main_path = PROJECT_ROOT / "app" / "main.py"
    if app_main_path.exists():
        import importlib.util

        spec = importlib.util.spec_from_file_location("backend_app_main", app_main_path)
        if spec and spec.loader:
            module = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = module
            spec.loader.exec_module(module)  # type: ignore[call-arg]
            app_instance = getattr(module, "app", None)
            if app_instance is not None:
                return app_instance

    raise RuntimeError(
        "Unable to import FastAPI 'app' instance. Tried: " + ", ".join(module_candidates)
    )


def main() -> None:
    # Step 1: load .env
    load_env_file(ENV_FILE, ENV_FILE_VALUES)
    firebase_defaults = firebase_defaults_from_env_values(ENV_FILE_VALUES)

    # Step 2: incorporate Dockerfile ENV defaults
    apply_dockerfile_env(DOCKERFILE_PATH)

    # Step 3: ensure firebase defaults
    apply_firebase_defaults(firebase_defaults)

    # Step 4: detect docker
    in_docker = running_in_docker()

    app = locate_app()

    reload_flag = os.environ.get("UVICORN_RELOAD", "")
    reload_enabled = reload_flag.lower() in {"1", "true", "yes"} and not in_docker

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        reload=reload_enabled,
        log_level=os.environ.get("UVICORN_LOG_LEVEL", "info"),
    )


if __name__ == "__main__":
    main()
