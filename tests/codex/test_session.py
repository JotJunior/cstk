"""Real shared-runtime tests; state and knowledge databases stay in tempdirs."""

import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "adapters/codex/skills/feature-00c/scripts"
sys.path.insert(0, str(SCRIPTS))
import context
import session
import phase


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / "project"
        (self.project / "docs").mkdir(parents=True)
        (self.project / "docs/briefing.md").write_text("# Briefing\n")
        (self.project / "docs/constitution.md").write_text("# Constitution\n**Version**: 1.0.0\n")
        self.env = dict(os.environ, HOME=str(Path(self.temp.name) / "home"),
                        CSTK_KNOWLEDGE_DB=str(Path(self.temp.name) / "knowledge.db"))
        self.adapter = self.make_session()

    def make_session(self):
        return session.Session(context.prepare(self.project, "test-feature", ROOT, self.env), self.env)

    def bootstrap(self, model=None):
        return self.adapter.bootstrap("Add a test feature", "canonical-project", model)

    def test_bootstrap_and_resume_preserve_identity_and_release_lock(self):
        state = self.bootstrap()
        self.assertEqual(state["execution_provenance"]["runtime"], "codex")
        self.assertIsNone(state["execution_provenance"]["model"])
        self.assertEqual(state["current_stage"], "specify")
        self.assertEqual(state["waves"], [])
        resumed = self.make_session().resume()
        self.assertEqual(resumed, state)
        self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_source_installation_and_provider_telemetry_are_isolated(self):
        contaminated = dict(self.env, CSTK_LIB="/another-installation",
                            CLAUDE_PLUGIN_ROOT="/another-plugin",
                            CLAUDE_CODE_ENABLE_TELEMETRY="1")
        adapter = session.Session(self.adapter.context, contaminated)
        self.assertEqual(adapter.env["CSTK_LIB"], str(ROOT / "cli/lib"))
        self.assertEqual(adapter.env["CLAUDE_PLUGIN_ROOT"], str(ROOT / "plugins/cstk"))
        self.assertNotIn("CLAUDE_CODE_ENABLE_TELEMETRY", adapter.env)
        self.assertEqual(contaminated["CLAUDE_CODE_ENABLE_TELEMETRY"], "1")

    def test_existing_execution_not_overwritten(self):
        state = self.bootstrap()
        with self.assertRaisesRegex(session.SessionError, "already exists"):
            self.bootstrap()
        self.assertEqual(self.adapter.read(), state)
        self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_failure_and_interrupt_release_lock(self):
        for failure in (RuntimeError("test"), KeyboardInterrupt()):
            with self.assertRaises(type(failure)):
                with self.adapter.locked():
                    raise failure
            self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_contention_does_not_release_other_owner(self):
        with self.adapter.locked():
            with self.assertRaises(session.SessionError):
                with self.make_session().locked():
                    pass
            self.assertTrue((self.adapter.state_dir / ".lock").is_dir())

    def test_changed_lock_owner_is_never_released_or_mutated(self):
        with self.assertRaisesRegex(session.SessionError, "owner changed"):
            with self.adapter.locked():
                owner = self.adapter.state_dir / ".lock/owner"
                owner.write_text("pid=1\nacquired_at=fixture\n")
                with self.assertRaisesRegex(session.SessionError, "owner changed"):
                    self.adapter.run("state-rw.sh", "set", "--state-dir", self.adapter.state_dir,
                                     "--field", ".current_stage", "--value", '"plan"')
        self.assertTrue((self.adapter.state_dir / ".lock").exists())
        self.assertFalse(self.adapter._locked)

    def test_symlink_escape_rejected_without_write(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (self.project / ".claude").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(session.SessionError, "escapes"):
            self.bootstrap()
        self.assertEqual(list(outside.iterdir()), [])

    def test_resume_blocks_drift_and_preserves_state(self):
        state = self.bootstrap()
        (self.project / "docs/briefing.md").write_text("changed")
        with self.assertRaisesRegex(session.SessionError, "drift"):
            self.make_session().resume()
        self.assertEqual(self.adapter.read(), state)
        self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_cross_runtime_handoff_requires_explicit_migration(self):
        self.bootstrap()
        self.adapter.run("state-rw.sh", "set", "--state-dir", self.adapter.state_dir,
                         "--field", ".execution_provenance.runtime", "--value", '"claude-code"')
        with self.assertRaisesRegex(session.SessionError, "runtime mismatch"):
            self.make_session().resume()

    def test_ingest_provenance_idempotent_and_legacy_nullable(self):
        state = self.bootstrap("observed-model-for-test")
        cli = ROOT / "cli/cstk"
        for _ in range(2):
            result = subprocess.run(["sh", str(cli), "recall", "--ingest", "--state-dir",
                                     str(self.adapter.state_dir)], env=self.env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        with sqlite3.connect(self.env["CSTK_KNOWLEDGE_DB"]) as db:
            rows = db.execute("SELECT execution_id, execution_provenance FROM executions").fetchall()
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0][0], state["execution"]["id"])
            self.assertEqual(json.loads(rows[0][1]), state["execution_provenance"])
            self.assertEqual(db.execute("SELECT value FROM schema_meta WHERE key='schema_version'").fetchone()[0], "16")

    def test_sqlite_bootstrap_resume_and_provenance_projection(self):
        config = Path(self.env["HOME"]) / ".claude/cstk/config"
        config.parent.mkdir(parents=True)
        config.write_text("state_backend=sqlite\n")
        state = self.bootstrap("observed-sqlite-model")
        self.assertTrue((self.adapter.state_dir / "state.db").is_file())
        self.assertFalse((self.adapter.state_dir / "state.json").exists())
        self.assertEqual(self.make_session().resume(), state)
        subprocess.run(["sh", str(ROOT / "cli/cstk"), "recall", "--ingest", "--state-dir",
                        str(self.adapter.state_dir)], env=self.env, capture_output=True, check=True)
        with sqlite3.connect(self.env["CSTK_KNOWLEDGE_DB"]) as db:
            value = db.execute("SELECT execution_provenance FROM executions").fetchone()[0]
            self.assertEqual(json.loads(value), state["execution_provenance"])

    def test_v15_migration_preserves_legacy_rows(self):
        # Model an existing v15 index using its original schema (only the
        # changed table is needed; the real migration creates other tables).
        with sqlite3.connect(self.env["CSTK_KNOWLEDGE_DB"]) as db:
            db.executescript("""
                CREATE TABLE schema_meta(key TEXT PRIMARY KEY, value TEXT);
                INSERT INTO schema_meta VALUES('schema_version','15');
                CREATE TABLE executions(id INTEGER PRIMARY KEY, project TEXT, feature TEXT,
                  wave TEXT, execution_id TEXT, source_ts TEXT, source_id TEXT, status TEXT,
                  termination_reason TEXT, current_stage TEXT, started_at TEXT, finished_at TEXT,
                  duration_seconds INTEGER, suggested_stack TEXT, waves_total INTEGER,
                  tool_calls_total INTEGER, wallclock_total_seconds INTEGER, subagents_spawned INTEGER,
                  max_depth INTEGER, decisions_total INTEGER, human_blocks_total INTEGER,
                  skill_suggestions_total INTEGER, toolkit_issues_opened INTEGER, session TEXT,
                  target_project_path TEXT, ingested_at TEXT,
                  UNIQUE(project,feature,wave,source_id));
                INSERT INTO executions(project,feature,wave,execution_id,source_ts,source_id,ingested_at)
                  VALUES('old-project','old-feature','-','legacy-id','t','legacy-id','t');
            """)
        self.bootstrap()
        for _ in range(2):
            subprocess.run(["sh", str(ROOT / "cli/cstk"), "recall", "--ingest", "--state-dir",
                            str(self.adapter.state_dir)], env=self.env, capture_output=True, check=True)
        with sqlite3.connect(self.env["CSTK_KNOWLEDGE_DB"]) as db:
            self.assertEqual(db.execute("SELECT execution_provenance FROM executions WHERE execution_id='legacy-id'").fetchone(), (None,))
            self.assertEqual(db.execute("SELECT count(*) FROM executions").fetchone()[0], 2)

    def test_phase_resolves_shared_instructions_without_advancing_state(self):
        state = self.bootstrap()
        report = phase.next_phase(self.make_session())
        self.assertEqual(report["stage"], "specify")
        self.assertTrue(Path(report["skill_path"]).is_file())
        self.assertTrue(Path(report["phase_reference"]).is_file())
        self.assertFalse(report["autonomous_ready"])
        self.assertEqual(self.adapter.read(), state)

    def test_resume_refuses_open_wave_without_closing_it(self):
        self.bootstrap()
        self.adapter.run("state-rw.sh", "set", "--state-dir", self.adapter.state_dir,
                         "--field", ".optin_responses", "--value",
                         '[{"field":"atomic_commit","outcome":"declined","channel":"test",'
                         '"recorded_at":"2026-10-02T00:00:00Z","applied_value":false}]')
        self.adapter.run("state-ondas.sh", "start", "--state-dir", self.adapter.state_dir)
        state = self.adapter.read()
        with self.assertRaisesRegex(session.SessionError, "open wave"):
            self.make_session().resume()
        self.assertEqual(self.adapter.read(), state)

    def test_prerequisites_changed_between_context_and_bootstrap(self):
        (self.project / "docs/briefing.md").write_text("changed after preflight")
        with self.assertRaisesRegex(session.SessionError, "changed since preflight"):
            self.bootstrap()
        self.assertFalse((self.adapter.state_dir / "state.json").exists())
        self.assertFalse((self.adapter.state_dir / ".lock").exists())

    def test_audited_decision_retrieved_with_execution_provenance(self):
        state = self.bootstrap()
        with self.adapter.locked():
            self.adapter.run("state-decisions.sh", "register", "--state-dir", self.adapter.state_dir,
                             "--agente", "codex-feature-orchestrator", "--etapa", "plan",
                             "--contexto", "Escolher estrategia de cache para widget-portable",
                             "--opcoes", '["cache-local","sem-cache"]', "--escolha", "cache-local",
                             "--justificativa", "A constitution permite cache local para consultas repetidas",
                             "--score", "2")
        subprocess.run(["sh", str(ROOT / "cli/cstk"), "recall", "--ingest", "--state-dir",
                        str(self.adapter.state_dir)], env=self.env, capture_output=True, check=True)
        result = subprocess.run(["sh", str(ROOT / "cli/cstk"), "recall", "--context", "widget-portable"],
                                env=self.env, capture_output=True, text=True, check=True)
        self.assertIn("cache-local", result.stdout)
        with sqlite3.connect(self.env["CSTK_KNOWLEDGE_DB"]) as db:
            row = db.execute("""SELECT d.agent, d.context, d.choice, d.rationale,
                              json_extract(e.execution_provenance,'$.runtime')
                              FROM decisions d JOIN executions e
                              ON e.execution_id=d.execution_id AND e.project=d.project
                              WHERE e.execution_id=?""", (state["execution"]["id"],)).fetchone()
            self.assertEqual(row[0], "codex-feature-orchestrator")
            self.assertEqual(row[-1], "codex")
            self.assertTrue(all(row))


if __name__ == "__main__":
    unittest.main()
