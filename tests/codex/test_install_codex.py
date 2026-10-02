"""Installer isolation, native CLI contract and release distribution."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("codex_installer", ROOT / "cli/lib/install-codex.py")
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)

FAKE_CODEX = r'''
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
if args == ["plugin", "add", "--help"]:
    raise SystemExit(0)
home = pathlib.Path(os.environ["CODEX_HOME"])
if args[:3] == ["plugin", "marketplace", "add"]:
    (home / "test-marketplace.json").write_text(json.dumps(args[3]))
elif args[:3] == ["plugin", "marketplace", "list"]:
    record = home / "test-marketplace.json"
    print(json.dumps({"marketplaces": [{"name": "cstk-codex-pilot-local", "root": json.loads(record.read_text())}] if record.exists() else []}))
elif args[:3] == ["plugin", "marketplace", "remove"]:
    (home / "test-marketplace.json").unlink()
elif args[:2] == ["plugin", "add"]:
    root = pathlib.Path(json.loads((home / "test-marketplace.json").read_text()))
    catalog = json.loads((root / ".agents/plugins/marketplace.json").read_text())
    source = root / catalog["plugins"][0]["source"]["path"]
    version = json.loads((source / "plugin.json").read_text())["version"]
    dest = home / "plugins/cache/cstk-codex-pilot-local/cstk-codex-pilot" / version
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(source, dest)
    config = home / "config.toml"
    original = config.read_text() if config.exists() else ""
    marker = '[plugins."cstk-codex-pilot@cstk-codex-pilot-local"]'
    if marker not in original:
        config.write_text(original + "\n" + marker + "\nenabled = true\n")
else:
    raise SystemExit(2)
'''


class InstallCodexTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "user"
        self.codex_home = self.home / ".codex"
        self.codex_home.mkdir(parents=True)
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        fake = self.bin / "codex"
        fake.write_text("#!" + sys.executable + "\n" + FAKE_CODEX)
        fake.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.codex_home),
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        self.env.pop("CSTK_RELEASE_URL", None)
        self.env.pop("CSTK_KNOWLEDGE_DB", None)

    def command(self, *args, expected=0):
        result = subprocess.run(["sh", str(ROOT / "cli/cstk"), "install", *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def test_dry_run_and_cli_selector_leave_configuration_and_claude_untouched(self):
        result = self.command("--cli=codex", "--dry-run")
        report = json.loads(result.stdout)
        self.assertEqual(report["cli"], "codex")
        self.assertTrue(report["dry_run"])
        self.assertEqual(len(report["skills"]), 6)
        self.assertFalse((self.codex_home / "cstk").exists())
        self.assertFalse((self.home / ".claude").exists())
        self.command("--cli=invalid", expected=2)
        self.command("--cli=codex", "--scope=project", expected=2)
        self.command("--cli=codex", "--profile=complementary", expected=2)
        self.command("--cli=claude", "--codex-home", str(self.codex_home), expected=2)

    def test_install_reinstall_preserve_custom_config_and_share_configured_database(self):
        config = self.codex_home / "config.toml"
        config.write_text('model = "existing-model"\n[plugins."other@team"]\nenabled = true\n')
        existing_hook = {"matcher": "Bash", "hooks": [{"type": "command", "command": "user-custom-handler", "timeout": 10}]}
        (self.codex_home / "hooks.json").write_text(json.dumps({"hooks": {"PreToolUse": [existing_hook]}}))
        claude = self.home / ".claude/skills/custom/SKILL.md"
        claude.parent.mkdir(parents=True)
        claude.write_text("User edited Claude skill\n")
        database = Path(self.temp.name) / "shared.db"
        database.write_bytes(b"Existing database must not be touched by installation")
        for _ in range(2):
            report = json.loads(self.command("--cli", "codex", "--knowledge-db", str(database)).stdout)
            self.assertTrue(report["installed"])
            package = Path(report["plugin_path"])
            self.assertEqual(json.loads((package / "mcp.json").read_text())["mcpServers"]["cstk_pipeline"]["env"]["CSTK_KNOWLEDGE_DB"], str(database))
        replacement = Path(self.temp.name) / "other-shared.db"
        refreshed = json.loads(self.command("--cli=codex", "--knowledge-db", str(replacement)).stdout)
        self.assertEqual(json.loads((Path(refreshed["plugin_path"]) / "mcp.json").read_text())["mcpServers"]["cstk_pipeline"]["env"]["CSTK_KNOWLEDGE_DB"], str(replacement))
        self.assertIn('model = "existing-model"', config.read_text())
        self.assertIn('[plugins."other@team"]', config.read_text())
        hooks = json.loads((self.codex_home / "hooks.json").read_text())["hooks"]
        self.assertEqual(hooks["PreToolUse"][0], existing_hook)
        self.assertEqual(len(hooks["PreToolUse"]), 2)
        self.assertEqual(len(hooks["PostToolUse"]), 1)
        self.assertEqual(json.loads((Path(refreshed["plugin_path"]) / "plugin.json").read_text())["extensions"]["com.openai"]["hooks"], [])
        self.assertEqual(claude.read_text(), "User edited Claude skill\n")
        self.assertEqual(database.read_bytes(), b"Existing database must not be touched by installation")
        self.assertFalse((self.codex_home / "cstk/.install-lock").exists())

    def test_reinstall_refuses_local_cache_edits(self):
        report = json.loads(self.command("--cli=codex").stdout)
        skill = Path(report["plugin_path"]) / "skills/feature-00c-resume/SKILL.md"
        skill.write_text("Actual user edit\n")
        self.command("--cli=codex", expected=4)
        self.assertEqual(skill.read_text(), "Actual user edit\n")

    def test_managed_hook_edits_are_preserved_and_not_duplicated(self):
        self.command("--cli=codex")
        path = self.codex_home / "hooks.json"
        hooks = json.loads(path.read_text())
        hooks["hooks"]["PreToolUse"][0]["hooks"][0]["timeout"] = 99
        path.write_text(json.dumps(hooks))
        self.command("--cli=codex", expected=4)
        self.assertEqual(json.loads(path.read_text()), hooks)

    def test_installation_lock_and_missing_dependency_do_not_change_config(self):
        managed = self.codex_home / "cstk"
        managed.mkdir()
        (managed / ".install-lock").mkdir()
        self.command("--cli=codex", expected=3)
        self.assertFalse((self.codex_home / "config.toml").exists())
        with patch.object(installer.shutil, "which", side_effect=lambda name: None if name == "codex" else "/fixture/" + name):
            with self.assertRaisesRegex(installer.InstallError, "missing.*codex"):
                installer.install(source_tree=ROOT, codex_home=self.codex_home)

    def test_verified_release_contains_installer_and_all_native_assets(self):
        release = Path(self.temp.name) / "release"
        build = subprocess.run(["sh", str(ROOT / "scripts/build-release.sh"), "0.0.0-codex-test", "--out", str(release)],
                               env=self.env, text=True, capture_output=True)
        self.assertEqual(build.returncode, 0, build.stderr)
        archive = release / "cstk-0.0.0-codex-test.tar.gz"
        report = json.loads(self.command("--cli=codex", "--from", archive.as_uri()).stdout)
        self.assertTrue(report["installed"])
        self.assertTrue((Path(report["plugin_path"]) / "cli/lib/install-codex.py").is_file())
        self.assertTrue((Path(report["plugin_path"]) / "skills/agente-00c-abort/SKILL.md").is_file())
        self.assertFalse((self.home / ".claude/skills").exists())


if __name__ == "__main__":
    unittest.main()
