"""Lifecycle parity against the real JSON/SQLite runtime and MCP ownership."""

import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import unittest
from unittest.mock import patch

import test_controller as fixtures
import context
import lifecycle
import optins
from controller import Controller
from mcp_bridge import Bridge
from session import Session, SessionError


class LifecycleTests(unittest.TestCase):
    def fixture(self, backend="json", kind="feature", atomic_commit=False):
        fixtures.ControllerTests.setUp(self)
        if backend == "sqlite":
            config = Path(self.env["HOME"]) / ".claude/cstk/config"
            config.parent.mkdir(parents=True)
            config.write_text("state_backend=sqlite\n")
        if kind == "project":
            self.adapter = Session(context.prepare(self.project, "canonical-project", fixtures.fixtures.ROOT,
                                                   self.env, "project"), self.env)
        self.adapter.bootstrap("Add an auditable lifecycle test", "canonical-project")
        optins.collect(self.adapter, atomic_commit, "prose", "Explicit isolated test-fixture response")
        if kind == "project":
            for field, value in (("roadmap_mode", False), ("delivery_tier", "local")):
                optins.collect(self.adapter, value, "prose", "Explicit isolated test-fixture response", field)
        self.bridge = Bridge(self.adapter)
        self.addCleanup(self.bridge.cleanup)
        self.feature = self.project / "docs/specs" / self.adapter.context["short_name"]
        self.feature.mkdir(parents=True, exist_ok=True)

    make_session = fixtures.ControllerTests.make_session

    def block(self, question="Qual e a fonte real do contrato desta feature?"):
        self.bridge.call("cstk_open_wave", {})
        return self.bridge.call("cstk_block", {"context": "A fonte factual do contrato precisa de confirmacao humana",
                                                "question": question,
                                                "rationale": "A fonte nao existe no briefing; o operador precisa informar o contrato."})["block_id"]

    def test_resume_answers_a_real_block_and_dispatches_same_stage_both_backends(self):
        for backend in ("json", "sqlite"):
            with self.subTest(backend=backend):
                self.fixture(backend)
                bid = self.block()
                paused = self.bridge.call("cstk_resume", {})
                self.assertEqual(paused["status"], "aguardando_humano")
                self.assertEqual(paused["pending_blocks"][0]["id"], bid)
                self.assertFalse(self.adapter._locked)
                optin = self.adapter.read()["optin_responses"]
                wave = self.bridge.call("cstk_resume", {"block_id": bid, "answer": "Usar o contrato local documentado em docs/contrato.md",
                                                       "response_source": "Mensagem real identificada como fixture de teste"})
                self.assertEqual(wave["stage"], "specify")
                self.assertEqual(wave["wave_id"], "onda-002")
                self.assertTrue(self.adapter._locked)
                state = self.adapter.read()
                self.assertEqual(state["human_blocks"][0]["status"], "respondido")
                self.assertEqual(state["optin_responses"], optin)
                self.assertEqual(state["events"][-2]["event_type"], "human_response")
                self.bridge.call("cstk_pause", {"instruction": "Continuar a mesma etapa depois da validacao do teste"})

    def test_resume_never_fabricates_or_broadcasts_an_answer(self):
        for backend in ("json", "sqlite"):
            self.fixture(backend)
            bid = self.block()
            did = self.adapter.read()["decisions"][0]["id"]
            with self.adapter.locked():
                self.adapter.run("bloqueios.sh", "register", "--state-dir", self.adapter.state_dir,
                                 "--decisao-id", did, "--pergunta", "Qual e o segundo contrato confirmado pelo operador?",
                                 "--contexto-para-resposta", "Segunda fonte independente")
            before = self.adapter.read()
            for args in ({"answer": "Uma resposta real", "response_source": "Fonte real identificada no teste"},
                         {"block_id": bid, "answer": "", "response_source": "Fonte real identificada no teste"},
                         {"block_id": bid, "answer": "Resposta sem origem"}):
                with self.assertRaises(SessionError):
                    self.bridge.call("cstk_resume", args)
                self.assertEqual(self.adapter.read(), before)
            result = self.bridge.call("cstk_resume", {"block_id": bid, "answer": "Usar a especificacao local do contrato",
                                                      "response_source": "Fonte real identificada no teste"})
            self.assertEqual(len(result["pending_blocks"]), 1)
            self.assertFalse(self.adapter._locked)

    def test_answer_is_idempotent_and_cannot_be_replaced(self):
        self.fixture()
        bid = self.block()
        args = {"block_id": bid, "answer": "Usar o contrato indicado pelo operador",
                "response_source": "Referencia ao operador na fixture de teste"}
        lifecycle.resume(self.adapter, **args)
        state = self.adapter.read()
        lifecycle.resume(self.adapter, **args)
        self.assertEqual(self.adapter.read(), state)
        with self.assertRaisesRegex(SessionError, "replace"):
            lifecycle.resume(self.adapter, **(args | {"answer": "Outra resposta"}))

    def test_abort_open_and_idle_feature_and_project_preserves_artifacts(self):
        for backend in ("json", "sqlite"):
            for kind in ("feature", "project"):
                for opened in (False, True):
                    with self.subTest(backend=backend, kind=kind, opened=opened):
                        self.fixture(backend, kind)
                        artifact = self.feature / "work.md"
                        artifact.write_text("Trabalho existente precisa ser preservado\n")
                        if opened:
                            self.bridge.call("cstk_open_wave", {})
                        result = self.bridge.call("cstk_abort", {"reason": "Operador encerrou a fixture preservando o trabalho"})
                        self.assertTrue(result["aborted"])
                        self.assertEqual(result["status"], "abortada")
                        self.assertEqual(result["commit_status"], "disabled")
                        self.assertTrue(artifact.is_file())
                        self.assertTrue(Path(result["report"]).is_file())
                        self.assertFalse((self.adapter.state_dir / ".lock").exists())
                        state = self.adapter.read()
                        self.assertTrue(state["execution"]["finished_at"])
                        self.assertEqual(len(state["waves"]), 1 if opened else 0)
                        self.assertTrue(all(w["finished_at"] for w in state["waves"]))
                        if opened:
                            self.assertEqual(state["waves"][-1]["termination_reason"], "aborto")
                        self.assertEqual(json.loads((self.adapter.state_dir / "backups/abort-final.json").read_text())["state_snapshot"]["execution"]["status"], "abortada")
                        with sqlite3.connect(self.env["CSTK_KNOWLEDGE_DB"]) as db:
                            self.assertEqual(db.execute("SELECT status FROM executions").fetchone()[0], "abortada")
                        self.assertFalse(self.bridge.call("cstk_abort", {})["aborted"])
                        self.assertEqual(self.adapter.read(), state)
                        self.assertFalse(self.bridge.call("cstk_resume", {})["resumed"])

    def test_abort_and_status_work_despite_deleted_prerequisite(self):
        for backend in ("json", "sqlite"):
            self.fixture(backend)
            (self.project / "docs/briefing.md").unlink()
            self.bridge = Bridge(source_root=fixtures.fixtures.ROOT, environ=self.env)
            self.bridge.call("cstk_select_execution", {"project": str(self.project), "kind": "feature", "short_name": "test-feature"})
            self.assertEqual(self.bridge.call("cstk_status", {})["status"], "em_andamento")
            with self.assertRaisesRegex(SessionError, "missing prerequisites"):
                self.bridge.call("cstk_resume", {})
            self.assertEqual(self.bridge.call("cstk_abort", {})["status"], "abortada")

    def test_abort_refuses_foreign_owner_and_unsafe_backup_paths(self):
        self.fixture()
        before = self.adapter.read()
        with self.adapter.locked():
            with self.assertRaises(SessionError):
                lifecycle.abort(self.make_session())
            self.assertTrue((self.adapter.state_dir / ".lock").exists())
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (outside / "preserve.txt").write_text("preserve")
        (self.adapter.state_dir / "backups").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(SessionError, "backup directory escapes"):
            lifecycle.abort(self.adapter, purge_backups=True)
        self.assertEqual(self.adapter.read(), before)
        self.assertTrue((outside / "preserve.txt").exists())

    def test_lifecycle_refuses_individual_control_file_symlinks(self):
        self.fixture()
        outside = Path(self.temp.name) / "unrelated-sha.txt"
        outside.write_text("Preserve this external file\n")
        marker = self.adapter.state_dir / "state.json.sha256"
        marker.unlink()
        marker.symlink_to(outside)
        with self.assertRaisesRegex(SessionError, "control path escapes"):
            self.bridge.call("cstk_abort", {})
        self.assertEqual(outside.read_text(), "Preserve this external file\n")
        self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_abort_explicit_purge_removes_only_backups(self):
        for backend in ("json", "sqlite"):
            self.fixture(backend)
            self.bridge.call("cstk_open_wave", {})
            result = self.bridge.call("cstk_abort", {"purge_backups": True})
            self.assertTrue(result["aborted"])
            self.assertFalse((self.adapter.state_dir / "backups").exists())
            self.assertTrue(Path(result["report"]).is_file())
            self.assertEqual(self.adapter.read()["execution"]["status"], "abortada")

    def test_abort_filters_secrets_in_final_snapshot_and_report(self):
        self.fixture()
        secret = "fixture-only-secret-abcdef012345"
        (self.project / ".env").write_text("API_TOKEN=" + secret + "\n")
        result = self.bridge.call("cstk_abort", {"reason": "Operador encerrou a fixture com token " + secret})
        self.assertNotIn(secret, (self.adapter.state_dir / "backups/abort-final.json").read_text())
        self.assertNotIn(secret, Path(result["report"]).read_text())

    def test_handoff_preserves_origin_history_and_execution_identity(self):
        for backend in ("json", "sqlite"):
            self.fixture(backend)
            self.bridge.call("cstk_open_wave", {})
            self.bridge.call("cstk_pause", {"instruction": "Continuar depois da transferencia explicitamente autorizada"})
            self.adapter.run("state-rw.sh", "set", "--state-dir", self.adapter.state_dir,
                             "--field", ".execution_provenance", "--value", json.dumps({"runtime": "claude-code", "model": "fixture-claude", "toolkit_version": "legacy"}))
            before = self.adapter.read()
            with self.assertRaisesRegex(SessionError, "runtime mismatch"):
                self.bridge.call("cstk_resume", {})
            args = {"expected_runtime": "claude-code", "response_source": "Operador autorizou handoff nesta fixture de teste",
                    "rationale": "A execucao pausada sera continuada pelo Codex preservando os artefatos e a auditoria."}
            result = self.bridge.call("cstk_handoff", args)
            self.assertTrue(result["handed_off"])
            state = self.adapter.read()
            for field in ("execution", "waves", "prerequisites", "optin_responses", "current_stage"):
                self.assertEqual(state[field], before[field])
            self.assertEqual(state["runtime_handoffs"][0]["previous_provenance"], before["execution_provenance"])
            self.assertIsNone(state["execution_provenance"]["model"])
            self.assertFalse(self.bridge.call("cstk_handoff", args)["handed_off"])
            self.assertEqual(self.bridge.call("cstk_resume", {})["wave_id"], "onda-002")
            self.bridge.cleanup()

    def test_unknown_origin_requires_specific_handoff_and_no_open_wave(self):
        for backend in ("json", "sqlite"):
            self.fixture(backend)
            self.adapter.run("state-rw.sh", "set", "--state-dir", self.adapter.state_dir,
                             "--field", ".execution_provenance", "--value", "null")
            before = self.adapter.read()
            args = {"expected_runtime": "claude-code", "response_source": "Operador autorizou handoff nesta fixture de teste",
                    "rationale": "Continuar o estado legado preservando a origem desconhecida na auditoria."}
            with self.assertRaisesRegex(SessionError, "does not match"):
                self.bridge.call("cstk_handoff", args)
            self.assertEqual(self.adapter.read(), before)
            self.assertTrue(self.bridge.call("cstk_handoff", args | {"expected_runtime": "unattributed"})["handed_off"])
            self.assertIsNone(self.adapter.read()["runtime_handoffs"][0]["previous_provenance"])

    def test_governance_reconcile_requires_exact_reviewed_hashes_both_backends(self):
        for backend in ("json", "sqlite"):
            for kind in ("feature", "project"):
                self.fixture(backend, kind)
                (self.project / "docs/constitution.md").write_text("# Nova constitution\n**Version**: 2.0.0\n")
                before = self.adapter.read()
                fresh = context.prepare(self.project, self.adapter.context["short_name"], fixtures.fixtures.ROOT, self.env, kind)
                hashes = [name + ":" + info["sha256"] for name, info in fresh["artifacts"].items()]
                args = {"expected_hashes": hashes, "response_source": "Operador revisou as mudancas nesta fixture de teste",
                        "rationale": "A nova constitution foi revisada e a feature precisa obedecer aos principios aprovados."}
                with self.assertRaisesRegex(SessionError, "expected hashes"):
                    self.bridge.call("cstk_reconcile_governance", args | {"expected_hashes": []})
                self.assertEqual(self.adapter.read(), before)
                self.assertTrue(self.bridge.call("cstk_reconcile_governance", args)["reconciled"])
                self.assertEqual(self.adapter.read()["governance_reconciliations"][0]["previous"], before.get("prerequisites" if kind == "feature" else "codex_governance", {}))
                self.assertEqual(self.adapter.resume()["execution"]["id"], before["execution"]["id"])

    def test_project_legacy_aspects_can_be_initialized_once_on_resume(self):
        for backend in ("json", "sqlite"):
            self.fixture(backend, "project")
            args = {"init_aspects": ["portabilidade", "auditoria", "conhecimento"],
                    "technical_aspects": ["sqlite"], "operational_aspects": [],
                    "response_source": "Operador informou aspectos na fixture de teste"}
            result = lifecycle.resume(self.adapter, **args)
            self.assertFalse(result["pending_blocks"])
            self.assertEqual(self.adapter.read()["initial_key_aspects"], args["init_aspects"])
            with self.assertRaisesRegex(SessionError, "already recorded"):
                lifecycle.resume(self.adapter, **args)

    def test_reporting_failure_after_abort_does_not_leak_the_owned_lock(self):
        self.fixture()
        self.bridge.call("cstk_open_wave", {})
        with patch.object(Controller, "after_close", side_effect=SessionError("fixture report unavailable")):
            with self.assertRaisesRegex(SessionError, "report unavailable"):
                self.bridge.call("cstk_abort", {})
        self.assertFalse(self.adapter._locked)
        self.assertIsNone(self.bridge.scope)
        self.assertEqual(self.bridge.call("cstk_status", {})["status"], "abortada")

    def test_abort_respects_commit_optin_with_real_scoped_local_commit(self):
        self.fixture(atomic_commit=True)
        def git(*args):
            result = subprocess.run(["git", "-C", str(self.project), *args],
                                    env=self.env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip()
        git("init", "-q")
        git("config", "user.name", "CSTK test fixture")
        git("config", "user.email", "fixture@example.invalid")
        (self.project / ".gitignore").write_text(".claude/\n")
        git("add", ".gitignore", "docs/briefing.md", "docs/constitution.md")
        git("commit", "-qm", "Initial isolated fixture")
        preexisting = self.project / "unrelated.txt"
        preexisting.write_text("Preexisting untracked user work\n")
        initial = git("rev-parse", "HEAD")
        self.bridge.call("cstk_open_wave", {})
        artifact = self.feature / "work.md"
        artifact.write_text("Actual new fixture work\n")
        result = self.bridge.call("cstk_abort", {"reason": "Operador autorizou commits locais nesta fixture"})
        self.assertEqual(result["commit_status"], "completed")
        self.assertNotEqual(git("rev-parse", "HEAD"), initial)
        changed = git("show", "--format=", "--name-only", "HEAD").splitlines()
        self.assertIn("docs/specs/test-feature/work.md", changed)
        self.assertNotIn("unrelated.txt", changed)
        self.assertTrue(preexisting.is_file())

    def test_completed_execution_cannot_be_reopened_or_relabelled_aborted(self):
        for backend in ("json", "sqlite"):
            self.fixture(backend)
            with self.adapter.locked():
                lifecycle.write(self.adapter, {".execution.status": "concluida", ".execution.finished_at": optins.now(),
                                               ".execution.termination_reason": "concluido", ".current_stage": "concluida"})
            before = self.adapter.read()
            self.assertFalse(self.bridge.call("cstk_abort", {"purge_backups": True})["aborted"])
            self.assertFalse(self.bridge.call("cstk_resume", {})["resumed"])
            self.assertEqual(self.adapter.read(), before)

    def test_abort_can_recover_only_the_observed_dead_controller_owner(self):
        self.fixture()
        process = subprocess.Popen([sys.executable, str(fixtures.fixtures.SCRIPTS / "controller.py"), "serve",
                                    "--project", str(self.project), "--short-name", "test-feature"],
                                   env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(json.loads(process.stdout.readline())["stage"], "specify")
            with self.assertRaisesRegex(SessionError, "alive"):
                lifecycle.abort(self.make_session(), abandoned_owner_pid=process.pid)
            process.kill()
            process.communicate(timeout=10)
            with self.assertRaisesRegex(SessionError, "does not match"):
                lifecycle.abort(self.make_session(), abandoned_owner_pid=process.pid + 1000000)
            result = lifecycle.abort(self.make_session(), abandoned_owner_pid=process.pid)
            self.assertEqual(result["status"], "abortada")
            self.assertFalse((self.adapter.state_dir / ".lock").exists())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            for stream in (process.stdin, process.stdout, process.stderr):
                stream.close()

    def test_cli_resume_pending_exit_code_and_abort_portuguese_flags(self):
        self.fixture()
        self.block()
        command = [sys.executable, str(fixtures.fixtures.SCRIPTS / "lifecycle.py")]
        args = ["--project", str(self.project), "--short-name", "test-feature"]
        result = subprocess.run(command + ["resume"] + args, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 5, result.stderr)
        self.assertTrue(json.loads(result.stdout)["pending_blocks"])
        result = subprocess.run(command + ["abort", "--motivo", "Aborto explicito da fixture pela CLI", "--purge-backups"] + args,
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "abortada")


if __name__ == "__main__":
    unittest.main()
