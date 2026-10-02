#!/usr/bin/env python3
"""Own one supervised wave while the current Codex session executes its phase.

JSONL on stdin/stdout is a transport, not an additional model or scheduler.
EOF/signals close the wave without advancing. A hard kill requires recover.
"""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

from context import discover_source, prepare
from optins import now
from phase import next_phase, pending_blocks
from session import Session, SessionError


class Controller:
    def __init__(self, session):
        self.session = session
        self.wave_id = None
        self.stage = None
        self.closed = False
        self.offered = []
        self.descriptor = None
        self.mode = "default"
        self.terminal = "review-task" if session.context.get("kind", "feature") == "feature" else "review-features"

    def event(self, kind, description):
        state = self.session.read()
        events = state.get("events", []) + [{"event_type": kind, "timestamp": now(),
                                          "description": description}]
        self.session.run("state-rw.sh", "set", "--state-dir", self.session.state_dir,
                         "--field", ".events", "--value", json.dumps(events))

    def assert_owner(self):
        if not self.session._locked or self.closed or not self.wave_id:
            raise SessionError("no owned open wave")
        state = self.session.read()
        if state["current_stage"] != self.stage or not state.get("waves"):
            raise SessionError("phase changed outside the controller")
        last = state["waves"][-1]
        if last["id"] != self.wave_id or last.get("finished_at") is not None:
            raise SessionError("wave changed outside the controller")
        return state

    @contextmanager
    def wave(self):
        with self.session.locked():
            state = self.session.validate()
            if self.session.context.get("kind") == "project":
                enabled = self.session.run("roadmap-mode.sh", "is-enabled", "--state-dir", self.session.state_dir).strip()
                self.mode = "roadmap" if enabled == "true" else "default"
                self.session.context["stages"] = self.session.run("pipeline.sh", "stages", "--mode", self.mode).splitlines()
                self.terminal = self.session.context["stages"][-1]
            feature_dir = self.session.project / "docs/specs" / self.session.context["short_name"]
            if not feature_dir.resolve().is_relative_to(self.session.project):
                raise SessionError("feature directory escapes the target project")
            if state["current_stage"] not in self.session.context["stages"]:
                raise SessionError("phase outside the feature pipeline")
            if pending_blocks(self.session):
                raise SessionError("pending human block must be answered")
            for script, operation in (("cycles.sh", "check"), ("circular.sh", "detect"),
                                      ("drift.sh", "check"), ("retro.sh", "check")):
                self.session.run(script, operation, "--state-dir", self.session.state_dir)
            self.stage = state["current_stage"]
            self.wave_id = self.session.run("state-ondas.sh", "start", "--state-dir",
                                            self.session.state_dir).strip()
            try:
                self.session.run("cycles.sh", "tick", "--state-dir", self.session.state_dir)
                self.session.run("budget.sh", "check", "--state-dir", self.session.state_dir)
                self.descriptor = next_phase(self.session, state=self.session.read())
                if self.stage == "constitution" and self.session.context.get("kind") == "project":
                    result = subprocess.run(["sh", str(self.session.scripts / "pipeline.sh"), "constitution-conflict",
                                             "--projeto-alvo-path", str(self.session.project), "--feature-dir", str(feature_dir)],
                                            cwd=self.session.project, env=self.session.env, capture_output=True, text=True)
                    if result.returncode in (1, 2):
                        try:
                            self.session.run("pipeline.sh", "require-blockade-resolved", "--state-dir", self.session.state_dir,
                                             "--etapa", "constitution")
                        except SessionError:
                            self.block("Conflito entre constitution global e do projeto detectado pelo pre-flight canonico",
                                       "Escolha atualizar-global-via-bump-SemVer, criar-feature-delta-com-sync-impact-report ou abortar-feature-sem-principios-proprios.",
                                       "A constitution existente exige resposta humana antes de executar a skill.",
                                       options=["atualizar-global-via-bump-SemVer", "criar-feature-delta-com-sync-impact-report", "abortar-feature-sem-principios-proprios"])
                            raise SessionError("constitution conflict requires an authorized human response")
                    elif result.returncode:
                        raise SessionError("constitution pre-flight failed")
                if self.stage in ("specify", "plan"):
                    text = self.descriptor.get("precedents") or ""
                    self.offered = re.findall(r"\[source: ([^\]\n]+)\]", text)
                    self.event("recall_consulted", json.dumps({
                        "status": self.descriptor["recall_status"], "sources": self.offered}))
                    self.briefing_gate()
                if self.stage != "roadmap":
                    self.session.run("state-ondas.sh", "record-skill", "--state-dir",
                                     self.session.state_dir, "--skill", self.stage)
                self.descriptor.update(wave_id=self.wave_id, execution_mode="supervised",
                                       metering="manual", precedent_sources=self.offered,
                                       controller_pid=os.getpid())
                yield self.descriptor
            finally:
                if not self.closed:
                    self.close("threshold_proxy_atingido", "Continuar etapa " + self.stage +
                               ": onda interrompida; conferir artefatos antes de continuar.")

    def briefing_gate(self):
        output = self.session.run("briefing-items.sh", "list-high", "--briefing",
                                  self.session.context["artifacts"]["briefing"]["path"])
        lines = output.splitlines()
        status = lines[-1].split("\t", 1)[-1]
        self.descriptor["briefing_gate"] = status
        if status != "ok":
            return
        for line in lines[:-1]:
            key, item, dimension = line.split("\t")
            answered = self.session.run("bloqueios.sh", "list", "--state-dir",
                                        self.session.state_dir, "--status", "respondido",
                                        "--chave-assunto", "briefing-item:" + key)
            if not answered.strip():
                self.block("Item Alto do briefing ainda sem decisao: " + item,
                           "Item Alto do briefing: " + item + " (" + dimension + "). Como decidir?",
                           "Item de impacto Alto precisa de resposta do operador antes da fase.",
                           "briefing-item:" + key)
                raise SessionError("high-impact briefing item requires an operator response")

    def decision(self, context, options, choice, rationale, score=2, evidence=None,
                 references=None, decision_class="operacional", axis=None, consent=None):
        self.assert_owner()
        args = ["register", "--state-dir", self.session.state_dir,
                "--agente", "codex-feature-orchestrator" if self.session.context.get("kind", "feature") == "feature" else "codex-project-orchestrator", "--etapa", self.stage,
                "--contexto", context, "--opcoes", json.dumps(options), "--escolha", choice,
                "--justificativa", rationale, "--score", str(score), "--classe", decision_class]
        for flag, value in (("--evidencia", evidence), ("--eixo", axis),
                            ("--consentimento", consent)):
            if value is not None:
                args.extend((flag, value))
        if references:
            args.extend(("--referencias", json.dumps(references)))
        return self.session.run("state-decisions.sh", *args).strip()

    def block(self, context, question, rationale, subject=None, options=None):
        decision = self.decision(context, options or ["bloqueio-humano-fonte-ausente"],
                                 "pause-humano" if options else "bloqueio-humano-fonte-ausente", rationale, score=0)
        args = ["register", "--state-dir", self.session.state_dir, "--decisao-id", decision,
                "--pergunta", question, "--contexto-para-resposta", context]
        if subject:
            args.extend(("--chave-assunto", subject))
        block = self.session.run("bloqueios.sh", *args).strip()
        self.close("bloqueio_humano", "Responder bloqueio humano e continuar etapa " + self.stage)
        return block

    def complete(self, evidence_paths, rationale, used_sources=None):
        state = self.assert_owner()
        used_sources = used_sources or []
        if any(source not in self.offered for source in used_sources):
            raise SessionError("precedent was not returned in this wave's consultation")
        if pending_blocks(self.session):
            raise SessionError("pending human block prevents completion")
        self.session.validate(allow_open=True)
        self.session.run("budget.sh", "check", "--state-dir", self.session.state_dir)
        if not evidence_paths:
            raise SessionError("completion requires persisted evidence")
        evidence = []
        for raw in evidence_paths:
            path = (self.session.project / raw).resolve(strict=True)
            if not path.is_relative_to(self.session.project) or not path.is_file():
                raise SessionError("evidence must be a file within the target project")
            relative = path.relative_to(self.session.project)
            if relative.parts[0] in (".git", ".claude", ".codex"):
                raise SessionError("execution controls cannot serve as completion evidence")
            evidence.append(str(relative) + " sha256=" + hashlib.sha256(path.read_bytes()).hexdigest())
        feature_dir = self.session.project / "docs/specs" / self.session.context["short_name"]
        self.session.run("pipeline.sh", "detect-completion", "--feature-dir", feature_dir,
                         "--stage", self.stage, "--projeto-alvo-path", self.session.project, "--mode", self.mode)
        if self.stage == "clarify" and self.session.context.get("kind", "feature") == "feature":
            self.session.run("feature-00c-preflight.sh", "check", "--state-dir", self.session.state_dir)
        if self.stage in ("execute-task", "review-task"):
            tasks = (feature_dir / "tasks.md").read_text()
            if re.search(r"^\s*-\s*\[[ ~!]\]", tasks, re.M):
                raise SessionError("unfinished or blocked tasks prevent stage completion")
            self.session.run("state-ondas.sh", "reconcile-tasks", "--state-dir",
                             self.session.state_dir, "--tasks-md", feature_dir / "tasks.md")
        if self.stage == "review-task":
            self.session.run("pipeline.sh", "detect-completion", "--feature-dir", feature_dir,
                             "--stage", "converge")
        decision = self.decision("Verificar conclusao da etapa " + self.stage + " pela pipeline canonica",
                                 ["concluir-etapa", "continuar-etapa"], "concluir-etapa", rationale,
                                 score=3, evidence="Arquivos lidos: " + "; ".join(evidence),
                                 references=used_sources + evidence)
        if used_sources:
            self.event("recall_used", json.dumps({"decision_id": decision, "sources": used_sources}))
        self.session.run("cycles.sh", "reset", "--state-dir", self.session.state_dir)
        if self.session.context.get("kind") == "project" and self.stage in ("briefing", "constitution"):
            fresh = prepare(self.session.project, self.session.context["short_name"], self.session.context["source_root"], self.session.env, "project")
            info = fresh["artifacts"][self.stage]
            if not info["exists"]:
                raise SessionError("root governance artifact must exist before advancing")
            governance = self.session.read().get("codex_governance", {}) | {self.stage: info}
            self.session.run("state-rw.sh", "set", "--state-dir", self.session.state_dir,
                             "--field", ".codex_governance", "--value", json.dumps(governance))
            self.session.context["artifacts"] = fresh["artifacts"]
        if self.stage == self.terminal:
            self.backup()
            self.session.run("state-ondas.sh", "end", "--state-dir", self.session.state_dir,
                             "--motivo-termino", "concluido", "--add-etapa", self.stage)
            self.closed = True
            # Terminal promotion is one canonical atomic set, including SQLite CHECKs.
            args = ["set", "--state-dir", self.session.state_dir]
            for field, value in ((".execution.status", "concluida"),
                                 (".execution.termination_reason", "concluido"),
                                 (".execution.finished_at", now()), (".current_stage", "concluida"),
                                 (".next_instruction", "Execucao concluida — nenhuma proxima etapa.")):
                args += ["--field", field, "--value", json.dumps(value)]
            self.session.run("state-rw.sh", *args)
            return self.after_close()
        return self.close("etapa_concluida_avancando", advance=True)

    def backup(self, snapshot_name=None):
        state = self.session.read()
        filtered = self.session.run("secrets-filter.sh", "for-backup", "--wave-number",
                                    len(state["waves"]), "--env-file", self.session.project / ".env",
                                    input_text=json.dumps(state))
        directory = self.session.state_dir / "backups"
        if not directory.resolve().is_relative_to(self.session.state_dir.resolve()):
            raise SessionError("backup directory escapes state scope")
        directory.mkdir(exist_ok=True)
        name = snapshot_name or self.wave_id
        if not isinstance(name, str) or not re.fullmatch(r"[a-zA-Z0-9_-]+", name):
            raise SessionError("invalid backup name")
        target = directory / (name + ".json")
        if target.is_symlink():
            raise SessionError("backup file is a symlink")
        if target.is_file():
            # A failed end/recovery can reuse the already scrubbed snapshot.
            return
        with target.open("x") as output:
            output.write(filtered)

    def close(self, reason, instruction=None, advance=False):
        self.assert_owner()
        self.backup()
        args = ["end", "--state-dir", self.session.state_dir, "--motivo-termino", reason]
        if instruction:
            args += ["--next-instruction", instruction]
        if advance:
            args += ["--advance", "--terminal-phase", self.terminal, "--add-etapa", self.stage, "--mode", self.mode]
        self.session.run("state-ondas.sh", *args)
        self.closed = True
        return self.after_close()

    def after_close(self):
        root = Path(self.session.context["source_root"])
        status = "ingested"
        try:
            result = subprocess.run(["sh", str(root / "cli/cstk"), "recall", "--ingest",
                                     "--state-dir", str(self.session.state_dir)], cwd=self.session.project,
                                    env=self.session.env, capture_output=True, text=True, timeout=30)
            if result.returncode or result.stderr.strip():
                status = "degraded"
        except (OSError, subprocess.SubprocessError):
            status = "degraded"
        if status == "degraded":
            self.event("knowledge_ingest_degraded", "Indice derivado indisponivel; estado canonico preservado.")
        state = self.session.read()
        flavor = "feature-00c" if self.session.context.get("kind", "feature") == "feature" else "agente-00c"
        report_root = self.session.state_dir if flavor == "feature-00c" else self.session.state_dir.parent
        report_path = report_root / (flavor + "-report.md")
        if not report_path.resolve().is_relative_to(report_root.resolve()):
            raise SessionError("report path escapes execution scope")
        report = self.session.run("report.sh", "emit", "--flavor", flavor,
                                  "--state-dir", self.session.state_dir, "--short-name",
                                  self.session.context["short_name"],
                                  "--final" if state["execution"]["status"] == "concluida" else "--parcial",
                                  "--env-file", self.session.project / ".env").strip()
        return {"wave_id": self.wave_id, "current_stage": state["current_stage"],
                "status": state["execution"]["status"], "knowledge_status": status,
                "report": report, "schedule_intent": "none", "autonomous_ready": False}

    def recover(self, abandoned_owner_pid=None):
        with self.session.locked(abandoned_owner_pid=abandoned_owner_pid):
            state = self.session.validate(allow_open=True)
            if not state.get("waves") or state["waves"][-1].get("finished_at") is not None:
                return {"recovered": False}
            self.wave_id = state["waves"][-1]["id"]
            self.stage = state["current_stage"]
            self.event("wave_retry", "Recuperacao explicita apos interrupcao; fase nao avancada.")
            # A previous attempt may have finished the backup before crashing.
            return self.close("threshold_proxy_atingido", "Continuar etapa " + self.stage +
                              ": recuperada sem inferir conclusao pelos artefatos.")

    def tick(self):
        self.assert_owner()
        ticks = self.session.state_dir / "tool-call-ticks.log"
        if ticks.exists() and ticks.stat().st_size:
            raise SessionError("native ticks observed; manual metering would double count")
        result = self.session.run("state-ondas.sh", "tool-call-tick", "--state-dir", self.session.state_dir)
        self.session.run("budget.sh", "check", "--state-dir", self.session.state_dir)
        return {"tool_calls": result.strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("serve", "resume", "recover"))
    parser.add_argument("--project", required=True)
    parser.add_argument("--short-name", required=True)
    parser.add_argument("--kind", choices=("feature", "project"), default="feature")
    parser.add_argument("--abandoned-owner-pid", type=int,
                        help="Explicit recovery of a lock whose recorded owner is confirmed dead")
    parser.add_argument("--block-id")
    parser.add_argument("--answer", "--resposta-bloqueio")
    parser.add_argument("--response-source")
    args = parser.parse_args()
    if args.abandoned_owner_pid is not None and args.mode != "recover":
        parser.error("--abandoned-owner-pid only applies to recover")
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    def emit(value):
        print(json.dumps(value, ensure_ascii=False), flush=True)
    try:
        session = Session(prepare(args.project, args.short_name, discover_source(__file__), kind=args.kind))
        controller = Controller(session)
        if args.mode == "recover":
            emit(controller.recover(args.abandoned_owner_pid))
            return
        if args.mode == "resume":
            from lifecycle import resume
            result = resume(session, args.block_id, args.answer, args.response_source)
            if result["terminal"] or result["pending_blocks"]:
                emit(result)
                return 5 if result["pending_blocks"] else 0
        with controller.wave() as descriptor:
            emit(descriptor)
            for line in sys.stdin:
                request = json.loads(line)
                action = request.pop("action")
                if action == "complete":
                    emit(controller.complete(**request))
                    break
                if action == "pause":
                    emit(controller.close("threshold_proxy_atingido", request["instruction"]))
                    break
                if action == "block":
                    emit({"block_id": controller.block(**request)})
                    break
                if action == "abort":
                    from lifecycle import abort_owned
                    emit(abort_owned(controller, **request))
                    break
                if action == "decision":
                    emit({"decision_id": controller.decision(**request)})
                elif action == "tick":
                    # Only supervised/manual mode; do not combine with native tick hooks.
                    emit(controller.tick())
                else:
                    raise SessionError("unknown controller action")
    except (SessionError, OSError, ValueError, KeyError, TypeError) as exc:
        parser.exit(1, str(exc) + "\n")
    except KeyboardInterrupt:
        parser.exit(130, "wave interrupted; closed without advancing and lock released\n")


if __name__ == "__main__":
    main()
