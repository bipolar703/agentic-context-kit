#!/usr/bin/env python3
"""Enforce the kit's container hardening policy on docker-compose.yml.

Reads the fully resolved Compose model (anchors, merges, and env interpolation
applied) from `docker compose config --format json`. Falls back to PyYAML when
Docker is unavailable. Standard library only unless the fallback is used.

Usage:
    python3 scripts/verify-hardening.py            # resolve via docker compose
    python3 scripts/verify-hardening.py --json f   # check a pre-rendered model

Exit codes: 0 = policy satisfied, 1 = violations found, 2 = could not load model.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
COMPOSE_FILE = ROOT / "docker-compose.yml"
DOCKER_SOCK = "/var/run/docker.sock"
# Services allowed to touch the Docker API, and how.
SOCKET_PROXY = "docker-socket-proxy"
LOOPBACK = {"127.0.0.1", "::1", "localhost"}


def load_model(json_path: str | None) -> dict[str, Any]:
    if json_path:
        return json.loads(Path(json_path).read_text(encoding="utf-8"))
    if shutil.which("docker"):
        proc = subprocess.run(
            ["docker", "compose", "-f", str(COMPOSE_FILE), "--profile", "gateway",
             "config", "--format", "json"],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        if proc.returncode == 0:
            return json.loads(proc.stdout)
        print(f"docker compose config failed:\n{proc.stderr}", file=sys.stderr)
        sys.exit(2)
    try:
        import yaml  # type: ignore[import-untyped]
    except ImportError:
        print("Need Docker (preferred) or PyYAML to load the Compose model.", file=sys.stderr)
        sys.exit(2)
    print("warning: docker not found; using PyYAML with basic ${VAR:-default} interpolation",
          file=sys.stderr)
    return yaml.safe_load(interpolate(COMPOSE_FILE.read_text(encoding="utf-8")))


def interpolate(text: str) -> str:
    """Minimal Compose-style interpolation: ${VAR}, ${VAR:-default}, ${VAR-default}."""
    env = dict(os.environ)
    dotenv = ROOT / ".env"
    if dotenv.exists():
        for line in dotenv.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                env.setdefault(key.strip(), val.strip())

    def repl(m: re.Match[str]) -> str:
        var, op, default = m.group(1), m.group(2), m.group(3) or ""
        val = env.get(var)
        if op == ":-":
            return val if val else default
        if op == "-":
            return val if val is not None else default
        return val or ""

    return re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:?-)([^}]*))?\}", repl, text)


def volume_parts(vol: Any) -> tuple[str, str, bool]:
    """Return (source, target, read_only) for long or short volume syntax."""
    if isinstance(vol, dict):
        return str(vol.get("source", "")), str(vol.get("target", "")), bool(vol.get("read_only", False))
    parts = str(vol).split(":")
    src = parts[0]
    tgt = parts[1] if len(parts) > 1 else parts[0]
    mode = parts[2] if len(parts) > 2 else "rw"
    return src, tgt, "ro" in mode.split(",")


def port_host_ip(port: Any) -> str:
    if isinstance(port, dict):
        return str(port.get("host_ip", ""))
    text = str(port)
    # "127.0.0.1:8811:8811" -> host_ip is first field when 3 fields
    fields = text.split(":")
    return fields[0] if len(fields) >= 3 else ""


def check(model: dict[str, Any]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    services: dict[str, dict[str, Any]] = model.get("services", {})
    if not services:
        return ["no services found"], warnings

    for name, svc in services.items():
        e = lambda msg, n=name: errors.append(f"{n}: {msg}")  # noqa: E731
        is_stdio_tier = not svc.get("profiles")

        # Universal controls
        if svc.get("read_only") is not True:
            e("read_only must be true")
        if "ALL" not in [c.upper() for c in svc.get("cap_drop", [])]:
            e("cap_drop must include ALL")
        if svc.get("cap_add"):
            e(f"cap_add is not allowed ({svc['cap_add']})")
        if svc.get("privileged"):
            e("privileged is not allowed")
        sec = [str(s).replace("=", ":") for s in svc.get("security_opt", [])]
        if not any(s in ("no-new-privileges", "no-new-privileges:true") for s in sec):
            e("security_opt must include no-new-privileges:true")
        for key in ("pid", "ipc", "network_mode"):
            if str(svc.get(key, "")) == "host":
                e(f"{key}: host is not allowed")
        for port in svc.get("ports", []) or []:
            if port_host_ip(port) not in LOOPBACK:
                e(f"published port must bind to loopback, got {port}")

        # Docker socket: only the proxy, and only read-only.
        for vol in svc.get("volumes", []) or []:
            src, _tgt, ro = volume_parts(vol)
            if src == DOCKER_SOCK:
                if name != SOCKET_PROXY:
                    e(f"mounts {DOCKER_SOCK}; route Docker API access through {SOCKET_PROXY}")
                elif not ro:
                    e(f"{DOCKER_SOCK} must be mounted read-only")

        # Stdio tier: strict sandbox
        if is_stdio_tier:
            if svc.get("network_mode") != "none":
                e("stdio-tier servers must use network_mode: none")
            if svc.get("ports"):
                e("stdio-tier servers must not publish ports")
            if not svc.get("user"):
                e("stdio-tier servers must set user (host UID:GID)")
            if svc.get("tty"):
                e("tty must be false (a TTY corrupts JSON-RPC framing)")
            if not svc.get("stdin_open"):
                e("stdin_open must be true for stdio transport")
            if not svc.get("mem_limit"):
                e("mem_limit must be set")
            if not svc.get("pids_limit"):
                e("pids_limit must be set")
            vols = svc.get("volumes", []) or []
            if len(vols) != 1:
                e(f"expected exactly one volume (the workspace), found {len(vols)}")
            for vol in vols:
                _src, tgt, ro = volume_parts(vol)
                if tgt != "/workspace":
                    e(f"volume target must be /workspace, got {tgt}")
                elif not ro:
                    warnings.append(f"{name}: workspace is mounted read-write (WORKSPACE_MODE=rw)")

    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", help="path to a pre-rendered `docker compose config --format json`")
    args = parser.parse_args()

    model = load_model(args.json)
    errors, warnings = check(model)
    for w in warnings:
        print(f"WARN  {w}")
    for err in errors:
        print(f"FAIL  {err}")
    if errors:
        print(f"\nhardening policy: {len(errors)} violation(s)")
        return 1
    print(f"hardening policy: OK ({len(model.get('services', {}))} services checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
