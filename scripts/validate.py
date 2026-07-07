#!/usr/bin/env python3
"""Static validation for redsalt-minion."""
from __future__ import annotations

import py_compile
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:  # pragma: no cover
    print(f"ERROR: PyYAML is required for validation: {exc}", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "README.md",
    "docs/architecture.md",
    "docs/operations.md",
    "docs/security.md",
    "configs/minion.d/99-redsalt.conf.example",
    "configs/grains.example",
    "scripts/bootstrap-minion.sh",
    "scripts/render-pillar.py",
    "tests/test_repo_static.py",
    "Makefile",
]
SUPPORTED_ROLES = {"base", "docker", "nvidia", "llm_vllm"}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def check_required() -> None:
    missing = [path for path in REQUIRED if not (ROOT / path).exists()]
    if missing:
        fail("missing required files: " + ", ".join(missing))


def check_yaml_examples() -> None:
    for rel in ["configs/minion.d/99-redsalt.conf.example", "configs/grains.example"]:
        path = ROOT / rel
        try:
            yaml.safe_load(path.read_text())
        except Exception as exc:
            fail(f"YAML parse failed for {rel}: {exc}")


def check_shell_syntax() -> None:
    for path in (ROOT / "scripts").glob("*.sh"):
        result = subprocess.run(["bash", "-n", str(path)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode != 0:
            fail(f"shell syntax failed for {path.relative_to(ROOT)}:\n{result.stdout}")


def check_python_syntax() -> None:
    for path in (ROOT / "scripts").glob("*.py"):
        try:
            py_compile.compile(str(path), doraise=True)
        except Exception as exc:
            fail(f"Python syntax failed for {path.relative_to(ROOT)}: {exc}")


def check_render_pillar() -> None:
    result = subprocess.run(
        [sys.executable, "scripts/render-pillar.py", "--minion-id", "example-vllm-node", "--roles", "base,docker,nvidia,llm_vllm"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        fail(f"render-pillar.py failed:\n{result.stdout}")
    data = yaml.safe_load(result.stdout)
    roles = data.get("roles") or {}
    if set(roles) != SUPPORTED_ROLES:
        fail(f"rendered roles {sorted(roles)} != expected {sorted(SUPPORTED_ROLES)}")
    for role in SUPPORTED_ROLES:
        if roles.get(role) is not True:
            fail(f"rendered role {role} should be true for vLLM example")
    if data.get("vllm", {}).get("service_name") != "vllm-openai":
        fail("rendered vLLM defaults missing service_name vllm-openai")


def check_no_private_key_material() -> None:
    forbidden = [
        "BEGIN " + "OPENSSH PRIVATE KEY",
        "BEGIN " + "RSA PRIVATE KEY",
        "PRIVATE " + "KEY-----",
    ]
    skip_dirs = {".git", "__pycache__", ".pytest_cache"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(part in skip_dirs for part in path.parts):
            continue
        text = path.read_text(errors="ignore")
        for marker in forbidden:
            if marker in text:
                fail(f"private key marker found in {path.relative_to(ROOT)}")


def main() -> int:
    check_required()
    check_yaml_examples()
    check_shell_syntax()
    check_python_syntax()
    check_render_pillar()
    check_no_private_key_material()
    print("redsalt-minion validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
