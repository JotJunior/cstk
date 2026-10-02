#!/usr/bin/env python3
"""Ask the installed Codex harness about hooks; never grant trust or run a model."""

import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import time


def inspect(project, codex_home=None, executable="codex"):
    env = dict(os.environ)
    home = Path(codex_home or env.get("CODEX_HOME") or Path.home() / ".codex").resolve()
    if codex_home is not None:
        home = Path(codex_home).resolve(strict=True)
        env["CODEX_HOME"] = str(home)
    process = subprocess.Popen([executable, "app-server", "--stdio"], env=env,
                               cwd=project, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, bufsize=1)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    def send(message):
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()
    def response(identifier):
        end = time.monotonic() + 20
        while time.monotonic() < end:
            for key, _ in selector.select(1):
                line = key.fileobj.readline()
                if not line:
                    raise RuntimeError("Codex app-server closed before the response")
                value = json.loads(line)
                if value.get("id") == identifier:
                    if "error" in value:
                        raise RuntimeError("Codex capability request rejected: " + str(value["error"]))
                    return value["result"]
        raise RuntimeError("Codex app-server capability request timed out")
    try:
        send({"id": 1, "method": "initialize", "params": {
            "clientInfo": {"name": "cstk-native-status", "version": "0.1.0"},
            "capabilities": {"experimentalApi": True}}})
        response(1)
        send({"method": "initialized", "params": {}})
        send({"id": 2, "method": "hooks/list", "params": {"cwds": [str(project)]}})
        entries = response(2)["data"]
        receipt = home / "cstk/install.json"
        registered = json.loads(receipt.read_text()).get("hook_entries", {}) if receipt.is_file() else {}
        commands = {handler["command"] for entry in registered.values() for handler in entry["hooks"]}
        hooks = [hook for entry in entries for hook in entry["hooks"]
                 if hook.get("pluginId") == "cstk-codex-pilot@cstk-codex-pilot-local"
                 or hook.get("command") in commands]
        loaded = {hook["eventName"] for hook in hooks} >= {"preToolUse", "postToolUse"}
        trusted = loaded and all(hook["trustStatus"] in ("trusted", "managed") and hook["enabled"]
                                 for hook in hooks)
        return {"project": str(project), "native_hooks_loaded": loaded,
                "native_hooks_trusted": trusted, "hooks": hooks,
                "errors": [error for entry in entries for error in entry["errors"]],
                "warnings": [warning for entry in entries for warning in entry["warnings"]],
                "autonomous_ready": False,
                "next_step": "Validate real tool coverage" if trusted else "Review the plugin with /hooks in Codex"}
    finally:
        selector.close()
        process.stdin.close()
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--codex-home", help="Use a previously prepared isolated installation")
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(Path(args.project).resolve(strict=True), args.codex_home),
                         ensure_ascii=False, indent=2))
    except (OSError, ValueError, RuntimeError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    main()
