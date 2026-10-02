"""Portable source/runtime resolution in an isolated built pilot package."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/build-codex-plugin.py"
SPEC = importlib.util.spec_from_file_location("codex_builder", SCRIPT)
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class PackageTests(unittest.TestCase):
    def test_built_context_and_hook_resolve_bundled_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            package = builder.build(ROOT, Path(temp) / "package with spaces")
            project = Path(temp) / "project"
            (project / "docs").mkdir(parents=True)
            (project / "docs/briefing.md").write_text("briefing")
            (project / "docs/constitution.md").write_text("constitution")
            result = subprocess.run(["python3", str(package / "skills/feature-00c/scripts/context.py"),
                                     "--project", str(project), "--short-name", "test"],
                                    capture_output=True, text=True, check=True)
            report = json.loads(result.stdout)
            self.assertEqual(report["source_root"], str(package))
            self.assertTrue(Path(report["runtime_root"]).is_relative_to(package))
            self.assertTrue((package / "skills/agente-00c/SKILL.md").is_file())
            for name in ("feature-00c-resume", "feature-00c-abort", "agente-00c-resume", "agente-00c-abort"):
                self.assertTrue((package / "skills" / name / "SKILL.md").is_file())
            portable = json.loads((package / "plugin.json").read_text())
            compatibility = json.loads((package / ".codex-plugin/plugin.json").read_text())
            self.assertEqual(portable["version"], compatibility["version"])
            self.assertEqual(portable["extensions"]["com.openai"]["hooks"], "./hooks/hooks.json")
            mcp = json.loads((package / "mcp.json").read_text())
            self.assertEqual(mcp["mcpServers"]["cstk_pipeline"]["args"][0], "${PLUGIN_ROOT}/skills/feature-00c/scripts/mcp_bridge.py")
            hook = subprocess.run(["python3", str(package / "hooks/pretooluse.py")],
                                  input=json.dumps({"cwd": str(project), "tool_name": "Bash",
                                                    "tool_input": {"command": "git status"}}),
                                  text=True, capture_output=True, check=True)
            self.assertEqual(json.loads(hook.stdout), {})
            marketplace = json.loads((package / ".agents/plugins/marketplace.json").read_text())
            self.assertEqual(marketplace["plugins"][0]["source"]["path"], "./")
            with self.assertRaisesRegex(ValueError, "already exists"):
                builder.build(ROOT, package)

    def test_reject_output_inside_source_tree_before_copying(self):
        with self.assertRaises(ValueError):
            builder.build(ROOT, ROOT / "adapters/codex/invalid-recursive-output")


if __name__ == "__main__":
    unittest.main()
