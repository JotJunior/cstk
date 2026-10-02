"""Project bootstrap uses canonical primitives without feature prerequisites."""

import unittest
import subprocess
import test_controller
import test_session as fixtures
import context
import controller
import optins
import session


class ProjectTests(unittest.TestCase):
    setUp = fixtures.SessionTests.setUp
    make_session = fixtures.SessionTests.make_session

    def project_session(self):
        return session.Session(context.prepare(self.project, "canonical-project", fixtures.ROOT,
                                               self.env, kind="project"), self.env)

    def test_project_starts_before_governance_and_requires_all_optins(self):
        (self.project / "docs/briefing.md").unlink()
        (self.project / "docs/constitution.md").unlink()
        adapter = self.project_session()
        state = adapter.bootstrap("Create a complete project pipeline", "canonical-project")
        self.assertEqual(state["current_stage"], "briefing")
        self.assertEqual(len(adapter.context["stages"]), 11)
        self.assertNotIn("short_name", state)
        optins.collect(adapter, False, "prose", "Explicit operator fixture for commits")
        with self.assertRaisesRegex(session.SessionError, "I-2"):
            with controller.Controller(adapter).wave():
                pass
        optins.collect(adapter, False, "prose", "Explicit operator fixture for roadmap", field="roadmap_mode")
        optins.collect(adapter, "local", "prose", "Explicit operator fixture for delivery", field="delivery_tier")
        with controller.Controller(adapter).wave() as descriptor:
            self.assertEqual(descriptor["stage"], "briefing")
            self.assertEqual(descriptor["delivery_tier"], "local")
            self.assertIn("agente-00c-orchestrator.md", descriptor["orchestrator_path"])
        self.assertEqual(self.project_session().resume()["current_stage"], "briefing")

    def test_roadmap_selects_three_canonical_phases(self):
        adapter = self.project_session()
        adapter.bootstrap("Plan project features through roadmap", "canonical-project")
        for field, value in (("atomic_commit", False), ("roadmap_mode", True), ("delivery_tier", "cloud-public")):
            optins.collect(adapter, value, "prose", "Explicit operator response fixture", field=field)
        control = controller.Controller(adapter)
        with control.wave():
            self.assertEqual(adapter.context["stages"], ["briefing", "constitution", "roadmap"])
            self.assertEqual(control.terminal, "roadmap")

    def test_full_project_pipeline_and_governance_drift(self):
        (self.project / "docs/briefing.md").unlink()
        (self.project / "docs/constitution.md").unlink()
        adapter = self.project_session()
        adapter.bootstrap("Develop a complete isolated project", "canonical-project")
        for field, value in (("atomic_commit", False), ("roadmap_mode", False), ("delivery_tier", "local")):
            optins.collect(adapter, value, "prose", "Explicit operator response fixture", field=field)
        feature = self.project / "docs/specs/canonical-project"
        feature.mkdir(parents=True, exist_ok=True)
        for stage in adapter.context["stages"]:
            control = controller.Controller(self.project_session())
            with control.wave() as descriptor:
                self.assertEqual(descriptor["stage"], stage)
                if stage == "briefing":
                    path = self.project / "docs/briefing.md"
                    path.write_text("# Briefing\n## Visao\nFerramenta local\n## Usuarios\nOperador\n## Escopo\nPipeline\n## Prioridades\nAuditoria\n")
                elif stage == "constitution":
                    path = self.project / "docs/constitution.md"
                    path.write_text("# Constitution\n**Version**: 1.0.0\n")
                elif stage == "converge":
                    result = subprocess.run(["sh", str(fixtures.ROOT / "plugins/cstk/skills/converge/scripts/converge-status.sh"),
                                             "record", "--feature-dir", str(feature), "--outcome", "clean", "--provenance", "gate", "--actionable", "0"],
                                            cwd=self.project, env=adapter.env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    path = feature / "converge-report.md"
                else:
                    name = {"specify": "spec.md", "clarify": "spec.md", "plan": "plan.md",
                            "checklist": "checklists/check.md", "create-tasks": "tasks.md", "execute-task": "tasks.md"}.get(stage, stage + ".md")
                    path = feature / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(test_controller.TASKS.replace("[ ]", "[x]") if name == "tasks.md" else "# Reviewed artifact\n")
                control.complete([str(path.relative_to(self.project))], "Actual artifacts were inspected and canonical phase gates passed.")
            if stage == "briefing":
                original = path.read_text()
                path.write_text(original + "drift\n")
                with self.assertRaisesRegex(session.SessionError, "drift"):
                    self.project_session().resume()
                path.write_text(original)
        state = adapter.read()
        self.assertEqual(state["execution"]["status"], "concluida")
        self.assertEqual(len(state["waves"]), 11)
        self.assertEqual(state["waves"][-1]["executed_stages"], ["review-features"])

    def test_existing_constitution_requires_canonical_human_block(self):
        adapter = self.project_session()
        adapter.bootstrap("Develop project with existing principles", "canonical-project")
        for field, value in (("atomic_commit", False), ("roadmap_mode", False), ("delivery_tier", "local")):
            optins.collect(adapter, value, "prose", "Explicit operator response fixture", field=field)
        adapter.run("state-rw.sh", "set", "--state-dir", adapter.state_dir,
                    "--field", ".current_stage", "--value", '"constitution"')
        with self.assertRaisesRegex(session.SessionError, "human response"):
            with controller.Controller(adapter).wave():
                self.fail("constitution skill must not be dispatched")
        state = adapter.read()
        self.assertEqual(state["decisions"][-1]["justification_score"], 0)
        self.assertEqual(len(state["decisions"][-1]["options_considered"]), 3)
        self.assertIsNotNone(state["waves"][-1]["finished_at"])
        self.assertFalse((adapter.state_dir / ".lock").exists())

    def test_full_project_sqlite_pipeline(self):
        from pathlib import Path
        config = Path(self.env["HOME"]) / ".claude/cstk/config"
        config.parent.mkdir(parents=True)
        config.write_text("state_backend=sqlite\n")
        self.test_full_project_pipeline_and_governance_drift()

    def test_full_roadmap_pipeline(self):
        (self.project / "docs/briefing.md").unlink()
        (self.project / "docs/constitution.md").unlink()
        adapter = self.project_session()
        adapter.bootstrap("Create a roadmap for project delivery", "canonical-project")
        for field, value in (("atomic_commit", False), ("roadmap_mode", True), ("delivery_tier", "local")):
            optins.collect(adapter, value, "prose", "Explicit operator response fixture", field=field)
        artifacts = {
            "briefing": "# Briefing\n## Visao\nLocal\n## Usuarios\nOperador\n## Escopo\nRoadmap\n## Prioridades\nAuditoria\n",
            "constitution": "# Constitution\n**Version**: 1.0.0\n",
            "roadmap": "# Roadmap: teste\n**Gerado por**: agente-00c\n**Atualizado em**: 2026-10-02\n\n## Ordem sugerida\n| # | Feature | Depende de | Descricao |\n|---|---|---|---|\n| 1 | `auth-basica` | - | Autenticacao |\n\n## Features\n### 1. auth-basica\n- **short-name**: `auth-basica`\n- **ordem**: 1\n- **depende-de**: -\n\n**Descricao**: Autenticacao local.\n\n**Justificativa**: Controle de acesso.\n",
        }
        for stage, text in artifacts.items():
            control = controller.Controller(self.project_session())
            with control.wave() as descriptor:
                self.assertEqual(descriptor["stage"], stage)
                path = self.project / "docs" / (stage + ".md")
                if stage == "roadmap":
                    entries = self.project / "roadmap-entries.md"
                    entries.write_text(text.split("## Features\n", 1)[1])
                    output = adapter.run("roadmap-write.sh", "write", "--projeto-alvo-path", self.project,
                                         "--input", entries, "--project-name", "canonical-project")
                    control.decision("Persistir entradas pelo helper canonico de roadmap", ["registrar-informativo"],
                                     "registrar-informativo", output, evidence=output)
                else:
                    path.write_text(text)
                control.complete([str(path.relative_to(self.project))], "Persisted roadmap artifacts pass canonical validation before promotion.")
        self.assertEqual(adapter.read()["execution"]["status"], "concluida")
        self.assertEqual(len(adapter.read()["waves"]), 3)
