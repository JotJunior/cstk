"""Hook input/output behavior; does not certify Codex trust or coverage."""

import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

import test_session as fixtures

ROOT = fixtures.ROOT


HOOK = ROOT / "adapters/codex/hooks/pretooluse.py"
SPEC = importlib.util.spec_from_file_location("codex_hook", HOOK)
hook = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hook)


class HookTests(unittest.TestCase):
    setUp = fixtures.SessionTests.setUp
    make_session = fixtures.SessionTests.make_session
    bootstrap = fixtures.SessionTests.bootstrap
    def envelope(self, name, **args):
        return {"cwd": str(self.project), "tool_name": name, "tool_input": args}

    def denied(self, result):
        return result.get("hookSpecificOutput", {}).get("permissionDecision") == "deny"

    def test_bash_reuses_shared_policy(self):
        self.bootstrap()
        self.assertFalse(self.denied(hook.evaluate(self.envelope("Bash", command="git status"))))
        self.assertTrue(self.denied(hook.evaluate(self.envelope("Bash", command="sudo touch /tmp/no"))))
        self.assertTrue(self.denied(hook.evaluate(self.envelope("Bash", command="git status; sudo true"))))
        self.assertTrue(self.denied(hook.evaluate(self.envelope("Bash", command="sh", tty=True))))

    def test_patch_scope_and_controls(self):
        self.bootstrap()
        for path in ("../outside.txt", ".codex/hooks.json", ".claude/feature-00c-state/x/state.json"):
            patch = f"*** Begin Patch\n*** Add File: {path}\n+test\n*** End Patch"
            self.assertTrue(self.denied(hook.evaluate(self.envelope("apply_patch", command=patch))))
        patch = "*** Begin Patch\n*** Add File: src/example.txt\n+test\n*** End Patch"
        self.assertFalse(self.denied(hook.evaluate(self.envelope("apply_patch", command=patch))))

    def test_unknown_wrapper_denied_and_inactive_session_unaffected(self):
        self.assertEqual(hook.evaluate(self.envelope("exec", code="anything")), {})
        self.bootstrap()
        self.assertTrue(self.denied(hook.evaluate(self.envelope("exec", code="anything"))))

    def test_malformed_input_emits_supported_deny(self):
        result = subprocess.run(["python3", str(HOOK)], input="{broken", text=True,
                                capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertTrue(self.denied(json.loads(result.stdout)))

    def test_posttooluse_records_tool_call_without_provider_metrics(self):
        self.bootstrap()
        result = subprocess.run(["python3", str(HOOK.parent / "posttooluse.py")],
                                input=json.dumps(self.envelope("Bash", command="git status")),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        ticks = (self.adapter.state_dir / "tool-call-ticks.log").read_text().splitlines()
        self.assertEqual(len(ticks), 1)
        self.assertNotIn("otel_usage", self.adapter.read())

    def test_mcp_allowlist_checks_server_tool_schema_and_target(self):
        self.bootstrap()
        allowed = "mcp__cstk_pipeline__cstk_context"
        self.assertFalse(self.denied(hook.evaluate(self.envelope(allowed))))
        for name in ("mcp__other__cstk_context", "mcp__cstk_pipeline__shell", "mcp__cstk_pipeline__cstk_unknown"):
            self.assertTrue(self.denied(hook.evaluate(self.envelope(name))))
        self.assertTrue(self.denied(hook.evaluate(self.envelope(allowed, command="sudo true"))))
        name = "mcp__cstk_pipeline__cstk_select_execution"
        self.assertTrue(self.denied(hook.evaluate(self.envelope(name, project=str(self.project.parent), kind="project", short_name="canonical-project"))))
        self.assertFalse(self.denied(hook.evaluate(self.envelope(name, project=str(self.project), kind="project", short_name="canonical-project"))))


if __name__ == "__main__":
    unittest.main()
