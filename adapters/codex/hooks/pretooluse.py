#!/usr/bin/env python3
"""Codex local hook: reuse Bash policy and confine apply_patch paths.

This is a guardrail, paired with the Codex workspace sandbox. Hook errors,
hosted tools and stdin transport are not a complete enforcement boundary.
"""

import json
from pathlib import Path
import subprocess
import sys


SOURCE = next((parent for parent in Path(__file__).resolve().parents
               if (parent / "plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh").is_file()),
              Path(__file__).resolve().parent)
RUNTIME = SOURCE / "plugins/cstk/skills/agente-00c-runtime"
CONTROLLER = SOURCE / "skills/feature-00c/scripts"
if not CONTROLLER.is_dir():
    CONTROLLER = SOURCE / "adapters/codex/skills/feature-00c/scripts"
sys.path.insert(0, str(CONTROLLER))
from mcp_bridge import TOOLS, validate


def deny(reason):
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse",
            "permissionDecision": "deny", "permissionDecisionReason": reason}}


def active(project):
    result = subprocess.run(
        ["sh", "-c", '. "$1"; hook_active_exec "$2"', "cstk-codex-hook",
         str(RUNTIME / "scripts/_hook-active-exec.sh"), str(project)],
        capture_output=True, text=True, timeout=3)
    if result.returncode not in (0, 1):
        raise ValueError("execution state cannot be determined")
    return result.returncode == 0


def patch_paths(command):
    if not isinstance(command, str) or not command.startswith("*** Begin Patch\n"):
        raise ValueError("unrecognized patch format")
    paths = []
    for line in command.splitlines():
        for prefix in ("*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "):
            if line.startswith(prefix):
                paths.append(line[len(prefix):])
    if not paths or command.splitlines()[-1] != "*** End Patch":
        raise ValueError("patch contains no recognized file operations")
    return paths


def evaluate(payload):
    if not isinstance(payload, dict) or not isinstance(payload.get("cwd"), str):
        return deny("CSTK: invalid hook envelope")
    project = Path(payload["cwd"]).resolve(strict=True)
    # Hook cwd is the session root. A Bash workdir is never used as policy root.
    if not active(project):
        return {}
    name = payload.get("tool_name")
    args = payload.get("tool_input")
    if not isinstance(args, dict):
        return deny("CSTK: invalid tool input during active execution")
    prefix = "mcp__cstk_pipeline__cstk_"
    if isinstance(name, str) and name.startswith(prefix) and name[len(prefix):] in TOOLS:
        action = name[len(prefix):]
        try:
            validate(args, TOOLS[action])
            if action == "select_execution":
                if "project" in args and Path(args["project"]).resolve(strict=True) != project:
                    return deny("CSTK: MCP target differs from the session project")
        except (OSError, ValueError):
            return deny("CSTK: invalid pipeline MCP arguments")
        # The MCP controller owns state mutations and rechecks lock, identity,
        # opt-ins, evidence and shared gates. Other MCP servers remain refused.
        return {}
    if name == "Bash":
        if args.get("tty") or args.get("interactive"):
            return deny("CSTK: interactive stdin is outside the hook coverage of this pilot")
        command = args.get("command")
        if not isinstance(command, str) or not command.strip():
            return deny("CSTK: missing shell command")
        result = subprocess.run(["sh", str(RUNTIME / "hooks/pretooluse-bash-guard.sh")],
                                input=json.dumps(payload), text=True, capture_output=True,
                                timeout=4)
        if result.returncode:
            return deny("CSTK: shared Bash policy failed")
        return json.loads(result.stdout) if result.stdout.strip() else {}
    if name == "apply_patch":
        for raw in patch_paths(args.get("command")):
            target = Path(raw)
            if not target.is_absolute():
                target = project / target
            target = target.resolve()
            if not target.is_relative_to(project):
                return deny("CSTK: patch escapes the target project")
            relative = target.relative_to(project)
            if relative.parts and relative.parts[0] in (".claude", ".codex", ".git"):
                return deny("CSTK: patch cannot change execution controls or repository metadata")
        return {}
    # Unknown execution paths are refused in the initial local pilot. In
    # particular, JavaScript exec wrappers must not hide shell calls here.
    return deny("CSTK: tool path has not been validated for the local pilot")


def main():
    try:
        output = evaluate(json.load(sys.stdin))
    except (OSError, ValueError, subprocess.SubprocessError):
        output = deny("CSTK: hook mechanism failed; request denied")
    print(json.dumps(output))


if __name__ == "__main__":
    main()
