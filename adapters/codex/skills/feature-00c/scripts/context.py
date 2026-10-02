#!/usr/bin/env python3
"""Prepare read-only context for the local Codex feature-00c pilot."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def discover_source(anchor):
    """Find assets anchored to this script, in a checkout or built package."""
    for candidate in Path(anchor).resolve().parents:
        if (candidate / "plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh").is_file() and (candidate / "cli/VERSION").is_file():
            return candidate
    raise ValueError("cannot locate bundled cstk runtime and CLI")


def artifact(path):
    if not path.is_file():
        return {"path": str(path), "exists": False, "sha256": None}
    return {"path": str(path), "exists": True,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def prepare(project, short_name, source_root, environ=None, kind="feature"):
    env = os.environ if environ is None else environ
    project = Path(project).resolve(strict=True)
    source_root = Path(source_root).resolve(strict=True)
    if not project.is_dir():
        raise ValueError("project must be a directory")
    if kind not in ("feature", "project"):
        raise ValueError("kind must be feature or project")
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", short_name):
        raise ValueError("short-name must be kebab-case without path separators")
    runtime = source_root / "plugins/cstk/skills/agente-00c-runtime"
    pipeline = runtime / "scripts/pipeline.sh"
    if not pipeline.is_file():
        raise ValueError("source-root does not contain the shared cstk runtime")
    result = subprocess.run(["sh", str(pipeline), "stages"],
                            capture_output=True, text=True, check=True)
    stages = result.stdout.splitlines()
    start, end = (stages.index("specify"), stages.index("review-task")) if kind == "feature" else (0, len(stages) - 1)
    briefing = project / "docs/briefing.md"
    if not briefing.is_file():
        briefing = project / "docs/01-briefing-discovery/briefing.md"
    artifacts = {"briefing": artifact(briefing),
                 "constitution": artifact(project / "docs/constitution.md")}
    missing = [name for name, info in artifacts.items() if not info["exists"]] if kind == "feature" else []
    dependencies = {name: shutil.which(name) is not None
                    for name in ("sh", "jq", "sqlite3", "cstk")}
    missing += [name for name in ("sh", "jq") if not dependencies[name]]
    db = env.get("CSTK_KNOWLEDGE_DB") or str(
        Path(env.get("HOME") or "/tmp") / ".claude/cstk/knowledge.db")
    state_dir = project / ".claude/feature-00c-state" / short_name if kind == "feature" else project / ".claude/agente-00c-state"
    return {
        "adapter_version": 1, "runtime": "codex", "model": None, "kind": kind,
        "source_root": str(source_root), "runtime_root": str(runtime),
        "project": str(project), "short_name": short_name,
        "state_dir": str(state_dir), "state_exists": (state_dir / "state.json").is_file()
        or (state_dir / "state.db").is_file(),
        "artifacts": artifacts, "stages": stages[start:end + 1],
        "knowledge_db": db, "knowledge_best_effort": True,
        "dependencies": dependencies, "missing_prerequisites": missing,
        "prerequisites_ready": not missing, "autonomous_ready": False,
        "implemented_capabilities": ["supervised_wave_controller", "explicit_optin_capture",
                                     "precedent_audit", "native_hook_discovery",
                                     "resume_with_human_response", "audited_abort",
                                     "explicit_runtime_handoff", "governance_reconciliation"],
        "pending_capabilities": ["codex_hook_trust_and_coverage",
                                 "native_end_to_end_validation", "claude_cross_review"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--short-name", required=True)
    parser.add_argument("--kind", choices=("feature", "project"), default="feature")
    parser.add_argument("--source-root", type=Path,
                        default=discover_source(__file__))
    args = parser.parse_args()
    try:
        context = prepare(args.project, args.short_name, args.source_root, kind=args.kind)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.error(str(exc))
    print(json.dumps(context, ensure_ascii=False, indent=2))
    return 0 if context["prerequisites_ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
