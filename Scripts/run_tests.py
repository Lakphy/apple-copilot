#!/usr/bin/env python3
"""Run Swift tests with an isolated, ephemeral loopback model fixture."""

from __future__ import annotations

import argparse
import json
import os
import selectors
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-only", action="store_true", help="Exclude native macOS view tests")
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="apple-copilot-tests-") as directory:
        print(f"Starting loopback fixture with Python {sys.version.split()[0]} ({sys.executable}).", flush=True)
        server = subprocess.Popen(
            [sys.executable, "-u", str(ROOT / "Scripts/mock_model_server.py"),
             "--port", "0", "--log", str(Path(directory) / "requests.jsonl")],
            cwd=ROOT, stdout=subprocess.PIPE, text=True,
        )
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(server.stdout, selectors.EVENT_READ)
                if not selector.select(timeout=10):
                    status = server.poll()
                    state = "still running" if status is None else f"exited with status {status}"
                    raise RuntimeError(f"The loopback fixture did not become ready within 10 seconds ({state})")
            line = server.stdout.readline()
            if not line:
                raise RuntimeError(f"The loopback fixture exited before reporting readiness (status {server.poll()})")
            ready = json.loads(line)
            if ready.get("ready") is not True:
                raise RuntimeError("The loopback fixture did not report readiness")
            environment = dict(os.environ, COPILOT_STREAM_TEST_URL=ready["base_url"])
            command = ["swift", "test"]
            if arguments.core_only:
                command += ["--filter", "CopilotCoreTests"]
            print("Running Swift tests with the local model fixture.", flush=True)
            return subprocess.run(command, cwd=ROOT, env=environment, check=False).returncode
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
            if server.stdout is not None:
                server.stdout.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError) as error:
        print(f"Test setup failed: {error}", file=sys.stderr)
        sys.exit(1)
