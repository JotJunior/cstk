#!/usr/bin/env python3
"""Inspect plugin MCP inventory in an ephemeral native thread, without a model turn."""

import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import time


class NativeClient:
    def __init__(self, project, codex_home, executable="codex"):
        self.project = str(Path(project).resolve(strict=True))
        self.process = subprocess.Popen([executable, "app-server", "--stdio"],
                                        cwd=self.project, env=dict(os.environ, CODEX_HOME=str(Path(codex_home).resolve(strict=True))),
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.identifier = 0
        self.notifications = []

    def send(self, value):
        self.process.stdin.write((json.dumps(value) + "\n").encode())
        self.process.stdin.flush()

    def request(self, method, params, timeout=30):
        self.identifier += 1
        identifier = self.identifier
        self.send({"id": identifier, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if b"\n" not in self.buffer:
                if not self.selector.select(min(1, max(0, deadline - time.monotonic()))):
                    continue
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError("native app-server closed before responding")
                self.buffer += chunk
            while b"\n" in self.buffer:
                raw, self.buffer = self.buffer.split(b"\n", 1)
                value = json.loads(raw)
                if value.get("id") == identifier and ("result" in value or "error" in value):
                    if "error" in value:
                        raise RuntimeError(str(value["error"]))
                    return value["result"]
                if "id" in value and "method" in value:
                    # Never synthesize user approval to make a probe pass.
                    self.send({"id": value["id"], "error": {"code": -32000, "message": "Read-only probe cannot grant approval"}})
                self.notifications.append(value)
        raise RuntimeError("native request timed out: " + method)

    def initialize(self):
        self.request("initialize", {"clientInfo": {"name": "cstk-native-mcp", "version": "0.1.0"},
                                    "capabilities": {"experimentalApi": True}})
        self.send({"method": "initialized", "params": {}})

    def close(self):
        self.selector.close()
        self.process.stdin.close()
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdout.close()


def inspect(project, codex_home):
    client = NativeClient(project, codex_home)
    try:
        client.initialize()
        thread = client.request("thread/start", {"cwd": client.project, "ephemeral": True,
                                                "sandbox": "workspace-write", "approvalPolicy": "on-request"})
        identifier = thread["thread"]["id"]
        inventory = client.request("mcpServerStatus/list", {"threadId": identifier})
        connected = any(server.get("name") == "cstk_pipeline" and server.get("runtimeStatus") == "connected"
                        and server.get("pluginId") == "cstk-codex-pilot@cstk-codex-pilot-local"
                        for server in inventory["data"])
        return {"project": client.project, "inventory": inventory,
                "native_mcp_connected": connected,
                "notifications": client.notifications, "model_turn_executed": False,
                "autonomous_ready": False}
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--codex-home", required=True)
    args = parser.parse_args()
    try:
        result = inspect(args.project, args.codex_home)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["native_mcp_connected"] else 1
    except (OSError, ValueError, RuntimeError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
