#!/usr/bin/env python3
"""Bootstrap or inspect a resumable Codex execution using cstk primitives.

No wave is opened here: hook enforcement is required before autonomous work.
"""

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import uuid

from context import discover_source, prepare


class SessionError(RuntimeError):
    pass


class Session:
    def __init__(self, context, environ=None):
        self.context = context
        self.project = Path(context["project"])
        self.state_dir = Path(context["state_dir"])
        self.scripts = Path(context["runtime_root"]) / "scripts"
        self.env = dict(os.environ if environ is None else environ)
        self.env["AGENTE_00C_STATE_DIR"] = str(self.state_dir)
        self.env["CSTK_KNOWLEDGE_DB"] = context["knowledge_db"]
        self.env["CSTK_LIB"] = str(Path(context["source_root"]) / "cli/lib")
        self.env["CLAUDE_PLUGIN_ROOT"] = str(Path(context["source_root"]) / "plugins/cstk")
        # A running Claude exporter must never be attributed to a Codex wave.
        # Codex usage collection is separate and still pending in this pilot.
        self.env.pop("CLAUDE_CODE_ENABLE_TELEMETRY", None)
        self._locked = False

    def run(self, script, *args, input_text=None):
        if self._locked:
            self.assert_lock_owner()
        result = subprocess.run(["sh", str(self.scripts / script), *map(str, args)],
                                cwd=self.project, env=self.env,
                                capture_output=True, text=True, input=input_text)
        if result.returncode:
            raise SessionError(f"{script} (exit {result.returncode}): "
                               f"{result.stderr.strip() or result.stdout.strip()}")
        return result.stdout

    def assert_lock_owner(self):
        try:
            owner = (self.state_dir / ".lock/owner").read_text()
        except OSError as exc:
            raise SessionError("session lock owner disappeared; refusing mutation") from exc
        recorded = re.search(r"^pid=(\d+)$", owner, re.M)
        if not recorded or int(recorded.group(1)) != os.getpid():
            raise SessionError("session lock owner changed; refusing mutation or release")

    def check_scope(self, require_prerequisites=True):
        self.run("path-guard.sh", "validate-target", "--projeto-alvo-path", self.project)
        expected = self.project / ".claude/feature-00c-state" / self.context["short_name"] if self.context.get("kind", "feature") == "feature" else self.project / ".claude/agente-00c-state"
        if expected != self.state_dir or not expected.resolve().is_relative_to(self.project):
            raise SessionError("state directory escapes the project (symlink or invalid context)")
        for name in ("state.json", "state.json.sha256", "state.db", "state.db-wal", "state.db-shm",
                     ".lock", ".lock/owner", "state-history", ".write-probe", ".gitignore"):
            control = self.state_dir / name
            if control.is_symlink() or not control.resolve().is_relative_to(self.state_dir.resolve()):
                raise SessionError("execution control path escapes state scope or is a symlink: " + name)
        if require_prerequisites and not self.context["prerequisites_ready"]:
            raise SessionError("missing prerequisites: " + ", ".join(
                self.context["missing_prerequisites"]))

    @contextmanager
    def locked(self, abandoned_owner_pid=None, require_prerequisites=True):
        if self._locked:
            raise SessionError("nested session lock")
        self.check_scope(require_prerequisites=require_prerequisites)
        args = ["acquire", "--state-dir", self.state_dir, "--owner-pid", os.getpid()]
        if abandoned_owner_pid is not None:
            # Explicit recovery only: never steal a live, unknown or reused PID.
            owner = (self.state_dir / ".lock/owner").read_text()
            recorded = re.search(r"^pid=(\d+)$", owner, re.M)
            if not recorded or int(recorded.group(1)) != abandoned_owner_pid or abandoned_owner_pid <= 0:
                raise SessionError("abandoned owner PID does not match the lock")
            try:
                os.kill(abandoned_owner_pid, 0)
            except ProcessLookupError:
                pass
            except PermissionError as exc:
                raise SessionError("owner liveness cannot be established") from exc
            else:
                raise SessionError("owner is alive; recovery refused")
            args.append("--force-abandoned")
        self.run("state-lock.sh", *args)
        self._locked = True
        try:
            yield
        finally:
            try:
                self.run("state-lock.sh", "release", "--state-dir", self.state_dir)
            finally:
                self._locked = False

    def read(self):
        return json.loads(self.run("state-rw.sh", "read", "--state-dir", self.state_dir))

    def bootstrap(self, description, canonical_project, model=None):
        if len(description.strip()) < 10:
            raise SessionError("description must contain at least 10 characters")
        if not canonical_project.strip():
            raise SessionError("canonical project identity is required")
        if self.context.get("kind") == "project":
            if canonical_project != self.context["short_name"]:
                raise SessionError("project slug must match canonical project identity")
            with self.locked():
                if self.context["state_exists"] or (self.state_dir / "state.json").exists() or (self.state_dir / "state.db").exists():
                    raise SessionError("execution already exists; use resume")
                feature_dir = self.project / "docs/specs" / canonical_project
                if not feature_dir.resolve().is_relative_to(self.project):
                    raise SessionError("project artifact directory escapes target")
                feature_dir.mkdir(parents=True, exist_ok=True)
                args = ["init", "--state-dir", self.state_dir,
                        "--execucao-id", "project-codex-" + uuid.uuid4().hex,
                        "--projeto-alvo-path", self.project, "--descricao", description,
                        "--canonical-project", canonical_project, "--runtime", "codex",
                        "--toolkit-version", (Path(self.context["source_root"]) / "cli/VERSION").read_text().strip()]
                if model is not None:
                    args += ["--observed-model", model]
                self.run("state-rw.sh", *args)
                return self.validate()
        constitution = Path(self.context["artifacts"]["constitution"]["path"]).read_text()
        version = re.search(r"^\*\*Version\*\*:\s*(\d+\.\d+\.\d+)", constitution, re.M)
        if not version:
            raise SessionError("constitution requires **Version**: X.Y.Z")
        with self.locked():
            if (self.state_dir / "state.json").exists() or (self.state_dir / "state.db").exists():
                raise SessionError("execution already exists; use resume")
            # Re-read prerequisites under the lock; do not freeze stale preflight hashes.
            fresh = prepare(self.project, self.context["short_name"],
                            self.context["source_root"], self.env)
            if fresh["artifacts"] != self.context["artifacts"]:
                raise SessionError("prerequisites changed since preflight; repeat preflight")
            artifacts = fresh["artifacts"]
            args = ["init", "--state-dir", self.state_dir,
                    "--execucao-id", "feat-codex-" + uuid.uuid4().hex,
                    "--projeto-alvo-path", self.project, "--descricao", description,
                    "--short-name", fresh["short_name"],
                    "--canonical-project", canonical_project,
                    "--briefing-path", artifacts["briefing"]["path"],
                    "--briefing-sha256", artifacts["briefing"]["sha256"],
                    "--constitution-path", artifacts["constitution"]["path"],
                    "--constitution-sha256", artifacts["constitution"]["sha256"],
                    "--constitution-version", version.group(1), "--runtime", "codex",
                    "--toolkit-version", (Path(fresh["source_root"]) / "cli/VERSION").read_text().strip()]
            if model is not None:
                args += ["--observed-model", model]
            self.run("state-rw.sh", *args)
            self.run("state-validate.sh", "--state-dir", self.state_dir)
            return self.read()

    def resume(self):
        with self.locked():
            return self.validate()

    def validate(self, allow_open=False, allow_terminal=False, runtime="codex", governance=True):
        """Validate while the caller owns the lock; never repair state here."""
        if not self._locked:
            raise SessionError("validation requires the session lock")
        self.run("state-validate.sh", "--state-dir", self.state_dir)
        state = self.read()
        if self.context.get("kind") == "project":
            enabled = self.run("roadmap-mode.sh", "is-enabled", "--state-dir", self.state_dir).strip()
            self.context["stages"] = self.run("pipeline.sh", "stages", "--mode", "roadmap" if enabled == "true" else "default").splitlines()
        if runtime is not None and (state.get("execution_provenance") or {}).get("runtime") != runtime:
            raise SessionError("runtime mismatch or unknown origin; explicit handoff required")
        if Path(state["execution"]["target_project_path"]).resolve() != self.project:
            raise SessionError("execution belongs to a different project")
        identity = state.get("short_name") if self.context.get("kind", "feature") == "feature" else state["execution"].get("canonical_project")
        if identity != self.context["short_name"]:
            raise SessionError("feature identity mismatch")
        if not allow_terminal and state["execution"]["status"] not in ("em_andamento", "aguardando_humano"):
            raise SessionError("terminal execution cannot be resumed")
        if not allow_open and any(w.get("finished_at") is None for w in state.get("waves", [])):
            raise SessionError("open wave requires reconciliation before resume")
        self.run("state-rw.sh", "sha256-verify", "--state-dir", self.state_dir)
        if not governance:
            return state
        artifacts = prepare(self.project, self.context["short_name"], self.context["source_root"], self.env,
                            self.context.get("kind", "feature"))["artifacts"]
        for name, info in artifacts.items():
            if not Path(info["path"]).resolve().is_relative_to(self.project):
                raise SessionError(f"{name} escapes the target project")
            if self.context.get("kind") == "project":
                recorded = state.get("codex_governance", {}).get(name)
                if recorded is None:
                    continue
            else:
                recorded = state["prerequisites"][name]
            recorded_path = Path(recorded["path"])
            if not recorded_path.is_absolute():
                recorded_path = self.project / recorded_path
            if recorded_path.resolve() != Path(info["path"]).resolve() or recorded["sha256"] != info["sha256"]:
                raise SessionError(f"{name} drift requires reconciliation")
        return state

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("bootstrap", "resume"))
    parser.add_argument("--project", required=True)
    parser.add_argument("--short-name", required=True)
    parser.add_argument("--kind", choices=("feature", "project"), default="feature")
    parser.add_argument("--description")
    parser.add_argument("--canonical-project")
    parser.add_argument("--observed-model", help="Only supply an actually observed model id")
    args = parser.parse_args()
    def interrupt(*_):
        raise KeyboardInterrupt()

    signal.signal(signal.SIGTERM, interrupt)
    try:
        session = Session(prepare(args.project, args.short_name, discover_source(__file__), kind=args.kind))
        if args.mode == "bootstrap":
            if not args.description or not args.canonical_project:
                parser.error("bootstrap requires --description and --canonical-project")
            state = session.bootstrap(args.description, args.canonical_project, args.observed_model)
        else:
            state = session.resume()
        print(json.dumps({"execution_id": state["execution"]["id"],
                          "current_stage": state["current_stage"],
                          "execution_provenance": state["execution_provenance"],
                          "autonomous_ready": False}, ensure_ascii=False, indent=2))
    except (SessionError, OSError, ValueError) as exc:
        parser.exit(1, str(exc) + "\n")
    except KeyboardInterrupt:
        parser.exit(130, "session preparation interrupted; lock released\n")


if __name__ == "__main__":
    main()
