"""Read-only context contracts for the Codex pilot (stdlib only)."""

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "adapters/codex/skills/feature-00c/scripts/context.py"
SPEC = importlib.util.spec_from_file_location("codex_context", SCRIPT)
context = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(context)


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / "project with spaces"
        (self.project / "docs").mkdir(parents=True)
        (self.project / "docs/briefing.md").write_text("briefing\n")
        (self.project / "docs/constitution.md").write_text("constitution\n")

    def prepare(self, **kwargs):
        with patch.object(context.shutil, "which", return_value="/bin/tool"):
            return context.prepare(self.project, "sample-feature", ROOT,
                                   kwargs.get("env", {"HOME": self.temp.name}))

    def test_read_only_and_canonical_pipeline(self):
        before = sorted(str(p.relative_to(self.project)) for p in self.project.rglob("*"))
        report = self.prepare()
        self.assertTrue(report["prerequisites_ready"])
        self.assertFalse(report["autonomous_ready"])
        self.assertEqual(report["stages"], ["specify", "clarify", "plan", "checklist",
                         "create-tasks", "execute-task", "converge", "review-task"])
        self.assertEqual(before, sorted(str(p.relative_to(self.project))
                                       for p in self.project.rglob("*")))
        self.assertFalse(Path(report["knowledge_db"]).exists())

    def test_shared_database_override_and_unknown_model(self):
        shared = str(Path(self.temp.name) / "shared.db")
        report = self.prepare(env={"CSTK_KNOWLEDGE_DB": shared})
        self.assertEqual(report["knowledge_db"], shared)
        self.assertEqual(report["runtime"], "codex")
        self.assertIsNone(report["model"])

    def test_legacy_briefing_and_hash(self):
        (self.project / "docs/briefing.md").unlink()
        legacy = self.project / "docs/01-briefing-discovery/briefing.md"
        legacy.parent.mkdir()
        legacy.write_bytes(b"legacy")
        report = self.prepare()
        self.assertEqual(report["artifacts"]["briefing"]["sha256"],
                         hashlib.sha256(b"legacy").hexdigest())
        self.assertTrue(report["prerequisites_ready"])

    def test_missing_constitution(self):
        (self.project / "docs/constitution.md").unlink()
        report = self.prepare()
        self.assertFalse(report["prerequisites_ready"])
        self.assertIn("constitution", report["missing_prerequisites"])

    def test_existing_database_state_is_detected_without_modification(self):
        state = self.project / ".claude/feature-00c-state/sample-feature/state.db"
        state.parent.mkdir(parents=True)
        state.write_bytes(b"fixture")
        report = self.prepare()
        self.assertTrue(report["state_exists"])
        self.assertEqual(state.read_bytes(), b"fixture")

    def test_invalid_names_and_non_directory_target(self):
        for name in ("../outside", "a/b", "", "Uppercase", "a;echo"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                context.prepare(self.project, name, ROOT)
        with self.assertRaises(ValueError):
            context.prepare(self.project / "docs/briefing.md", "feature", ROOT)

    def test_missing_dependency_blocks_prerequisites(self):
        with patch.object(context.shutil, "which", return_value=None):
            report = context.prepare(self.project, "sample-feature", ROOT)
        self.assertFalse(report["prerequisites_ready"])
        self.assertIn("jq", report["missing_prerequisites"])

    def test_cli_default_source_and_missing_artifact_exit(self):
        (self.project / "docs/constitution.md").unlink()
        result = subprocess.run(["python3", str(SCRIPT), "--project", str(self.project),
                                 "--short-name", "sample-feature"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(json.loads(result.stdout)["source_root"], str(ROOT))


if __name__ == "__main__":
    unittest.main()
