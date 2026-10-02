"""Exercise full canonical lifecycle and interruption without a second model."""

import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import signal
import unittest

import test_session as fixtures

sys.path.insert(0, str(fixtures.SCRIPTS))
import controller
import optins
from session import SessionError


TASKS = """# Tarefas: teste
## FASE 1 - Implementacao
### 1.1 Funcao `[C]`
- [ ] 1.1.1 Implementar funcao
## Matriz de Dependencias
```mermaid
flowchart TD
F1
```
## Resumo Quantitativo
| Fase | T |
## Escopo Coberto
Funcao local
## Escopo Excluido
Publicacao
"""


class ControllerTests(unittest.TestCase):
    setUp = fixtures.SessionTests.setUp
    make_session = fixtures.SessionTests.make_session
    bootstrap = fixtures.SessionTests.bootstrap

    def ready(self):
        self.bootstrap()
        optins.collect(self.adapter, False, "structured", "explicit fixture operator response")
        self.feature = self.project / "docs/specs/test-feature"
        self.feature.mkdir(parents=True)

    def evidence(self, name, text="# Artefato de teste\n"):
        path = self.feature / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return str(path.relative_to(self.project))

    def finish(self, control, path, sources=None):
        return control.complete([path], "Os artefatos foram inspecionados e os gates reais da etapa passaram.", sources)

    def test_first_wave_requires_real_optin_and_never_leaks_lock(self):
        self.bootstrap()
        with self.assertRaisesRegex(SessionError, "I-2"):
            with controller.Controller(self.adapter).wave():
                pass
        self.assertEqual(self.adapter.read()["waves"], [])
        self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_optin_explicit_false_is_recorded_idempotently_and_cannot_change(self):
        self.bootstrap()
        response = optins.collect(self.adapter, False, "prose", "actual operator message reference")
        self.assertEqual(response["applied_value"], "false")
        self.assertEqual(optins.collect(self.make_session(), False, "prose", "same operator message reference"), response)
        with self.assertRaisesRegex(SessionError, "already resolved"):
            optins.collect(self.adapter, True, "prose", "different operator message reference")
        with self.assertRaises(SessionError):
            optins.collect(self.adapter, None, "prose", "no actual response received")
        self.assertEqual(len(self.adapter.read()["optin_responses"]), 1)

    def test_interruption_closes_without_advance_then_resumes(self):
        self.ready()
        control = controller.Controller(self.adapter)
        with self.assertRaises(KeyboardInterrupt):
            with control.wave() as descriptor:
                self.assertEqual(descriptor["stage"], "specify")
                with self.assertRaises(SessionError):
                    with self.make_session().locked():
                        pass
                raise KeyboardInterrupt()
        state = self.make_session().resume()
        self.assertEqual(state["current_stage"], "specify")
        self.assertIsNotNone(state["waves"][-1]["finished_at"])
        with controller.Controller(self.make_session()).wave() as descriptor:
            self.assertEqual(descriptor["wave_id"], "onda-002")

    def test_missing_artifact_or_unknown_precedent_never_advances(self):
        self.ready()
        path = self.evidence("evidence.md")
        with controller.Controller(self.adapter).wave() as descriptor:
            self.assertEqual(descriptor["precedent_sources"], [])
            control = controller.Controller(self.adapter)
            # A second controller does not own the wave merely because the session is locked.
            with self.assertRaisesRegex(SessionError, "owned"):
                control.complete([path], "An adequately detailed fixture rationale")
        control = controller.Controller(self.make_session())
        with control.wave():
            with self.assertRaisesRegex(SessionError, "not returned"):
                self.finish(control, path, ["decision/invented/source"])
            with self.assertRaisesRegex(SessionError, "pipeline.sh"):
                self.finish(control, path)
        self.assertEqual(self.adapter.read()["current_stage"], "specify")

    def test_full_pipeline_json_and_sqlite_with_pending_task_gate(self):
        for backend in ("json", "sqlite"):
            with self.subTest(backend=backend):
                self.setUp()
                if backend == "sqlite":
                    config = Path(self.env["HOME"]) / ".claude/cstk/config"
                    config.parent.mkdir(parents=True)
                    config.write_text("state_backend=sqlite\n")
                self.ready()
                for stage, name in (("specify", "spec.md"), ("clarify", "spec.md"),
                                    ("plan", "plan.md"), ("checklist", "checklists/check.md"),
                                    ("create-tasks", "tasks.md"), ("execute-task", "tasks.md"),
                                    ("converge", "converge-report.md"), ("review-task", "review.md")):
                    control = controller.Controller(self.make_session())
                    with control.wave() as descriptor:
                        self.assertEqual(descriptor["stage"], stage)
                        if stage == "create-tasks":
                            path = self.evidence(name, TASKS)
                        elif stage == "execute-task":
                            path = str((self.feature / name).relative_to(self.project))
                            with self.assertRaises(SessionError):
                                self.finish(control, path)
                            (self.feature / name).write_text(TASKS.replace("[ ]", "[x]"))
                        elif stage == "converge":
                            result = subprocess.run(["sh", str(fixtures.ROOT / "plugins/cstk/skills/converge/scripts/converge-status.sh"),
                                "record", "--feature-dir", str(self.feature), "--outcome", "clean",
                                "--provenance", "gate", "--actionable", "0"], cwd=self.project,
                                env=self.adapter.env, capture_output=True, text=True)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            path = str((self.feature / name).relative_to(self.project))
                        else:
                            path = self.evidence(name)
                        result = self.finish(control, path)
                state = self.adapter.read()
                self.assertEqual(state["execution"]["status"], "concluida")
                self.assertEqual(len(state["waves"]), 8)
                self.assertTrue(all(w["finished_at"] for w in state["waves"]))
                self.assertEqual([w["executed_stages"] for w in state["waves"]],
                                 [[stage] for stage in self.adapter.context["stages"]])
                self.assertEqual(len(state["decisions"]), 8)
                self.assertEqual(state["current_stage"], "concluida")
                self.assertEqual(result["schedule_intent"], "none")
                self.assertTrue(Path(result["report"]).is_file())
                with sqlite3.connect(self.env["CSTK_KNOWLEDGE_DB"]) as db:
                    self.assertEqual(db.execute("SELECT status FROM executions").fetchone()[0], "concluida")
                    self.assertEqual(db.execute("SELECT count(*) FROM waves").fetchone()[0], 8)

    def test_recall_sources_are_audited_and_only_returned_ids_can_be_used(self):
        self.ready()
        # Feed an independent execution into the shared derived index.
        other_project = Path(self.temp.name) / "other-project"
        (other_project / "docs").mkdir(parents=True)
        (other_project / "docs/briefing.md").write_text("# Briefing\n")
        (other_project / "docs/constitution.md").write_text("**Version**: 1.0.0\n")
        import context
        import session
        other = session.Session(context.prepare(other_project, "cache-source", fixtures.ROOT, self.env), self.env)
        other.bootstrap("Add test feature cache", "other-project")
        other.run("state-decisions.sh", "register", "--state-dir", other.state_dir,
                  "--agente", "claude-feature-orchestrator", "--etapa", "plan",
                  "--contexto", "Add a test feature with portable cache", "--opcoes", '["reuse-cache"]',
                  "--escolha", "reuse-cache", "--justificativa", "A local cache is sufficient for the fixture", "--score", "2")
        subprocess.run(["sh", str(fixtures.ROOT / "cli/cstk"), "recall", "--ingest", "--state-dir", str(other.state_dir)],
                       env=self.env, check=True, capture_output=True)
        control = controller.Controller(self.adapter)
        with control.wave() as descriptor:
            sources = descriptor["precedent_sources"]
            self.assertTrue(any("cache-source" in source and "dec-001" in source for source in sources))
            self.finish(control, self.evidence("spec.md"), sources)
        state = self.adapter.read()
        self.assertEqual([e["event_type"] for e in state["events"]], ["recall_consulted", "recall_used"])
        self.assertTrue(all(source in state["decisions"][-1]["references"] for source in sources))

    def test_hard_interruption_recovery_is_explicit_and_idempotent(self):
        self.ready()
        self.adapter.run("state-ondas.sh", "start", "--state-dir", self.adapter.state_dir)
        with self.assertRaisesRegex(SessionError, "open wave"):
            self.make_session().resume()
        control = controller.Controller(self.make_session())
        result = control.recover()
        self.assertEqual(result["current_stage"], "specify")
        self.assertEqual(controller.Controller(self.make_session()).recover(), {"recovered": False})
        self.assertEqual(len(self.adapter.read()["waves"]), 1)

    def start_transport(self):
        process = subprocess.Popen([sys.executable, str(fixtures.SCRIPTS / "controller.py"), "serve",
                                   "--project", str(self.project), "--short-name", "test-feature"],
                                  env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                process.kill()
                process.wait()
            for pipe in (process.stdin, process.stdout, process.stderr):
                pipe.close()
        self.addCleanup(cleanup)
        descriptor = json.loads(process.stdout.readline())
        self.assertEqual(descriptor["controller_pid"], process.pid)
        return process

    def test_native_process_sigterm_closes_wave_and_releases_lock(self):
        self.ready()
        process = self.start_transport()
        with self.assertRaisesRegex(SessionError, "does not match"):
            controller.Controller(self.make_session()).recover(process.pid + 1000000)
        process.send_signal(signal.SIGTERM)
        _, err = process.communicate(timeout=20)
        self.assertEqual(process.returncode, 130, err)
        state = self.make_session().resume()
        self.assertEqual(state["current_stage"], "specify")
        self.assertIsNotNone(state["waves"][-1]["finished_at"])

    def test_killed_owner_requires_explicit_pid_and_live_owner_is_never_stolen(self):
        self.ready()
        process = self.start_transport()
        with self.assertRaisesRegex(SessionError, "alive"):
            controller.Controller(self.make_session()).recover(process.pid)
        process.kill()
        process.communicate(timeout=10)
        with self.assertRaises(SessionError):
            controller.Controller(self.make_session()).recover()
        result = controller.Controller(self.make_session()).recover(process.pid)
        self.assertEqual(result["current_stage"], "specify")
        self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_manual_metering_and_budget_prevent_advance(self):
        self.ready()
        control = controller.Controller(self.adapter)
        with control.wave():
            self.assertEqual(control.tick()["tool_calls"], "1")
            (self.adapter.state_dir / "tool-call-ticks.log").write_text("native-tick\n")
            with self.assertRaisesRegex(SessionError, "double count"):
                control.tick()
            self.adapter.run("state-rw.sh", "set", "--state-dir", self.adapter.state_dir,
                             "--field", ".budgets.tool_calls_threshold_wave", "--value", "1")
            with self.assertRaisesRegex(SessionError, "budget.sh"):
                self.finish(control, self.evidence("spec.md"))
        self.assertEqual(self.adapter.read()["current_stage"], "specify")

    def test_human_block_closes_wave_and_prevents_dispatch(self):
        self.ready()
        control = controller.Controller(self.adapter)
        with control.wave():
            control.block("Fonte factual indisponivel para completar a especificacao",
                          "Qual e a fonte real do contrato?",
                          "O briefing nao fornece a fonte; inventar o contrato nao seria auditavel.")
        with self.assertRaisesRegex(SessionError, "pending human"):
            with controller.Controller(self.make_session()).wave():
                pass
        import phase
        with self.assertRaisesRegex(SessionError, "pending human"):
            phase.next_phase(self.make_session())

    def test_feature_symlink_escape_is_rejected_before_opening_wave(self):
        self.bootstrap()
        optins.collect(self.adapter, False, "prose", "actual fixture operator response")
        outside = Path(self.temp.name) / "outside-feature"
        outside.mkdir()
        (self.project / "docs/specs").mkdir()
        (self.project / "docs/specs/test-feature").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(SessionError, "feature directory escapes"):
            with controller.Controller(self.adapter).wave():
                pass
        self.assertEqual(self.adapter.read()["waves"], [])
        self.assertEqual(list(outside.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
