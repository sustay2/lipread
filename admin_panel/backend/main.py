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


FIREBASE_DEFAULTS = {
    "FIREBASE_PROJECT_ID": "lipreadapp",
    "FIREBASE_CLIENT_EMAIL": "firebase-adminsdk-fbsvc@lipreadapp.iam.gserviceaccount.com",
    "FIREBASE_PRIVATE_KEY": (
        "-----BEGIN PRIVATE KEY-----\\n"
        "MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC/SBeF2XFvSBs3\\n"
        "5Q4k7xmpcbBtU9y2INLw1NcCMyUCL7vzS3LIFEwG5B3MWQETtyLfj7zpc05vmDaj\\n"
        "vDCcT7pZPhNfZrdFXRdx6o/5x0ol83ZlGhiIznQeGjU8OBdJO0TH1ZOtBNV6weQD\\n"
        "ktkjyxx56wSzMCbBi5U62OpPdTZuwg5HmWdavxJkIjHWoDtdZJwkHjQow5/xR/cN\\n"
        "W7bbaf3haAgl1Z9cS6Dy87eVgl5oBk/v9p20VdxfQ3FhCi04x8kHNFSYZCUNrWQk\\n"
        "2z0LKGEEzgSGUEzP/ZSRZZa3DyvZcdb2kpodbD0p4HeIq/a75W+OB3Yxhd7FcvHn\\n"
        "DDT16RrpAgMBAAECggEAOP+5irgt9jQtcC2AVn8tTXHEWf+4cEk9smgqHcyxxYIF\\n"
        "5szfykFKGm+VdZQ8HuzepnHFoGcsw1I/TfFBJwMXC4rU6QPJrxC7cMWt24eIT+DJ\\n"
        "sfzhvLqQnXu/y08HmVng+A9rrw4WszrdwDbdH65hsO7YerDpi5kVgfCrebv62WvU\\n"
        "KPEHekunWIclCHfcxocU8t6D6azQPH3nJmpx46iLTUgxuHJECKrtoYq0+F7uB5bi\\n"
        "u/tDEDpQgvgxPSH1I3av4HnV9ZO4wpuep2eKo74AGjOIHm5QrGnbXFXhPGknaJ0J\\n"
        "OLFsdeWnn47fTFj2/3qWxsgtJ0A/UjcPvt5u6BPWdQKBgQDmmRKSBlw9951ICwJS\\n"
        "JgkLdYBrlzc7t66u0ykcb11ND35MaiT3G44IsW253k7Mz0669YIMdTA3zTYKc1XD\\n"
        "blYj4AkQP4qoPsjrR3Nj28OnopCdJzPZDXlwoWzdclVTjldbyVMVmH7LQWL9IIyE\\n"
        "PF5j1sEnP+gnrr8ZrK/oMSSNdwKBgQDUWkmi6MZhzIi4dZKYUTkYm2E5XdM0twwb\\n"
        "JG3t4kV3DVrBsHFmwz0B60o1adyCL9/wffLolWW8GNBTayOwhRaI/kzBCB4AmUyQ\\n"
        "oXGgfHo2HEiRds5WBQyNdcGD85dOSbVFXnnZckW2Udn5n7ajesZEBqy6QlxIOOXro\\n"
        "TjlbQwynwKBgB9dXqtB9jXvghMUfEJULhLC7q6zqK2UtEvPKN5XP2eF3fXi0hhS\\n"
        "RSVljLklRa6R2/GOBxxOrDpKzTjqqxWj4k+K33C4U9HCiG2IEGfasmgQsn7NoD27\\n"
        "mXL6YeZU8MomqDcx0P00+roGsMIhNTufQm9t/GOsS5VqLU/+rwZz+LbNAoGBAMQf\\n"
        "X0MGmbJZpSw36lyjJ4iCeRjyfs6BAL1Qt/astFtwChI5U4MFbqMHHFKYov/aF4mV\\n"
        "yXLmCD/g6wcgPKYbROTheSIOzSbgbsZlVPxT+ste8+blQ0xO/Xjo+QFVSLkVekXHK\\n"
        "+KYl6n7jsXtrFDwY40QXRbpkzFg23j0Pggm3s0hAoGBAJ+Ao5xcka1jcUrf1tFC\\n"
        "d3vudVc7o8XXkdHm/EKW4fIj79mPcYEM9H7nDw88ZK4avrpqH/qdtko59iefaT+C\\n"
        "0BITCQn4aFL1350TumrbE96SnYYM5XpFY47M6Zw45d8LkQqMFj8qodeTyfYu9qVc\\n"
        "NM3k3BLe9599ubLdv8qNs/iI\\n"
        "-----END PRIVATE KEY-----\\n"
    ),
}


def load_env_file(path: pathlib.Path) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        if not line or re.match(r"^\s*#", line):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
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


def apply_firebase_defaults() -> None:
    for key, value in FIREBASE_DEFAULTS.items():
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
    sys.path.insert(0, str(PROJECT_ROOT))
    try:
        from app.app import app  # type: ignore

        return app
    except Exception:
        pass
    try:
        from app.main import app  # type: ignore

        return app
    except Exception as exc:  # pragma: no cover - fatal startup state
        raise RuntimeError(
            "Unable to import FastAPI 'app' instance from app.app or app.main"
        ) from exc


def main() -> None:
    # Step 1: load .env
    load_env_file(ENV_FILE)

    # Step 2: incorporate Dockerfile ENV defaults
    apply_dockerfile_env(DOCKERFILE_PATH)

    # Step 3: ensure firebase defaults
    apply_firebase_defaults()

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
