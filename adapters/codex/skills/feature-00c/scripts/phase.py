#!/usr/bin/env python3
"""Resolve the next cstk phase from a validated, resumable execution."""

import argparse
import json
from pathlib import Path
import subprocess

from context import discover_source, prepare
from session import Session, SessionError


def pending_blocks(session):
    return int(session.run("bloqueios.sh", "count", "--state-dir", session.state_dir,
                           "--pending-only").strip())


def next_phase(session, query=None, state=None):
    state = session.resume() if state is None else state
    stage = state["current_stage"]
    if stage not in session.context["stages"]:
        raise SessionError("execution stage is outside the feature pipeline")
    if pending_blocks(session):
        raise SessionError("pending human block must be answered before the next phase")
    root = Path(session.context["source_root"])
    skill = root / "plugins/cstk/skills" / stage / "SKILL.md"
    if not skill.is_file() and stage != "roadmap":
        raise SessionError("stage skill is missing from the source checkout")
    # review-task has its instructions in the base orchestrator; the other
    # phases have shared references resolved with the strict runtime helper.
    reference = None
    kind = session.context.get("kind", "feature")
    if stage not in ("review-task", "review-features"):
        reference = session.run("orchestrator-refs.sh", "path", "--orchestrator", "feature" if kind == "feature" else "root",
                                "--phase", stage).strip()
    result = {"execution_id": state["execution"]["id"], "stage": stage,
              "skill_path": str(skill) if stage != "roadmap" else None, "phase_reference": reference,
              "orchestrator_path": str(root / "plugins/cstk/agents" / ("agente-00c-feature-orchestrator.md" if kind == "feature" else "agente-00c-orchestrator.md")),
              "runtime_root": session.context["runtime_root"],
              "feature_dir": str(session.project / "docs/specs" / session.context["short_name"]),
              "knowledge_db": session.context["knowledge_db"],
              "precedents": None, "recall_status": "not_requested",
              "autonomous_ready": False}
    if kind == "project" and stage in ("briefing", "specify", "plan"):
        result["delivery_tier"] = session.run("delivery-tier.sh", "get", "--state-dir", session.state_dir).strip()
    if stage in ("specify", "plan"):
        terms = query or state["execution"]["target_project_description"]
        try:
            recalled = subprocess.run(
                ["sh", str(root / "cli/cstk"), "recall", "--context", terms,
                 "--exclude-feature", session.context["short_name"], "--limit", "4",
                 "--include-source-ids"],
                cwd=session.project, env=session.env, capture_output=True, text=True, timeout=15)
            result["precedents"] = recalled.stdout if recalled.returncode == 0 else None
            # recall is best-effort; warning stderr is a degradation even
            # when the CLI intentionally returns zero.
            result["recall_status"] = "degraded" if recalled.returncode or recalled.stderr.strip() else "queried"
        except (OSError, subprocess.SubprocessError):
            result["recall_status"] = "degraded"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--short-name", required=True)
    parser.add_argument("--kind", choices=("feature", "project"), default="feature")
    parser.add_argument("--query")
    args = parser.parse_args()
    try:
        ctx = prepare(args.project, args.short_name, discover_source(__file__), kind=args.kind)
        print(json.dumps(next_phase(Session(ctx), args.query), ensure_ascii=False, indent=2))
    except (SessionError, OSError, ValueError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    main()
