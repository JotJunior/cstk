"""Opt-in native harness contract test. Does not execute a model or trust hooks."""

import json
import hashlib
import os
from pathlib import Path
import tempfile
import unittest

import test_session
import context as adapter_context
from session import Session
from native_mcp import NativeClient
from mcp_bridge import TOOLS
from native_status import inspect as inspect_hooks


@unittest.skipUnless(os.environ.get("CSTK_NATIVE_TEST_HOME"), "requires an isolated installed plugin")
class NativeMcpTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get("CSTK_NATIVE_INSTALL_DB"), "requires an installer-configured temporary database path")
    def test_installer_mcp_env_reaches_native_server(self):
        with tempfile.TemporaryDirectory() as directory:
            client = NativeClient(directory, os.environ["CSTK_NATIVE_TEST_HOME"])
            try:
                client.initialize()
                if os.environ.get("CSTK_NATIVE_INSTALL_DB"):
                    hooks = inspect_hooks(client.project, os.environ["CSTK_NATIVE_TEST_HOME"])
                    self.assertTrue(hooks["native_hooks_loaded"], hooks)
                    self.assertFalse(hooks["native_hooks_trusted"])
                    self.assertTrue(all(hook["enabled"] for hook in hooks["hooks"]))
                    self.assertFalse(hooks["errors"] or hooks["warnings"])
                thread = client.request("thread/start", {"cwd": client.project, "ephemeral": True,
                                                        "sandbox": "workspace-write", "approvalPolicy": "on-request"})["thread"]["id"]
                client.request("mcpServerStatus/list", {"threadId": thread})
                result = client.request("mcpServer/tool/call", {"threadId": thread, "server": "cstk_pipeline",
                                                               "tool": "cstk_select_execution",
                                                               "arguments": {"project": client.project, "kind": "project", "short_name": "env-project"}})
                self.assertFalse(result.get("isError"), result)
                self.assertEqual(json.loads(result["content"][0]["text"])["knowledge_db"], os.environ["CSTK_NATIVE_INSTALL_DB"])
            finally:
                client.close()

    def test_plugin_connection_scope_i2_and_persistent_wave(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project"
            project.mkdir()
            database = Path(directory) / "knowledge.db"
            client = NativeClient(project, os.environ["CSTK_NATIVE_TEST_HOME"])
            try:
                client.initialize()
                inventory_skills = client.request("skills/list", {"cwds": [client.project], "forceReload": True})
                skills = [skill for item in inventory_skills["data"] for skill in item["skills"]
                          if skill.get("pluginId") == "cstk-codex-pilot@cstk-codex-pilot-local"]
                self.assertEqual({skill["name"] for skill in skills},
                                 {"cstk-codex-pilot:" + name for name in
                                  ("feature-00c", "feature-00c-resume", "feature-00c-abort",
                                   "agente-00c", "agente-00c-resume", "agente-00c-abort")})
                self.assertTrue(all(skill["enabled"] for skill in skills))
                self.assertFalse(any(item["errors"] for item in inventory_skills["data"]))
                thread = client.request("thread/start", {"cwd": client.project, "ephemeral": True,
                                                        "sandbox": "workspace-write", "approvalPolicy": "on-request"})["thread"]["id"]
                inventory = client.request("mcpServerStatus/list", {"threadId": thread})
                server = next(item for item in inventory["data"] if item["name"] == "cstk_pipeline")
                self.assertEqual(server["runtimeStatus"], "connected")
                self.assertEqual(server["pluginId"], "cstk-codex-pilot@cstk-codex-pilot-local")
                self.assertEqual(set(server["tools"]), {"cstk_" + name for name in TOOLS})

                def call(name, arguments=None, error=False):
                    result = client.request("mcpServer/tool/call", {"threadId": thread, "server": "cstk_pipeline",
                                                                   "tool": "cstk_" + name, "arguments": arguments or {}})
                    self.assertEqual(bool(result.get("isError")), error, result)
                    return result["content"][0]["text"] if error else json.loads(result["content"][0]["text"])

                self.assertIsNone(call("context")["project"])
                context = call("select_execution", {"project": client.project, "short_name": "native-project", "kind": "project",
                                                    "knowledge_db": str(database)})
                self.assertEqual(context["knowledge_db"], str(database.resolve()))
                context = call("select_execution", {"project": client.project, "kind": "project", "short_name": "native-project"})
                self.assertEqual(context["knowledge_db"], str(database.resolve()))
                state = call("bootstrap", {"description": "Validate native MCP ownership and canonical gates",
                                           "canonical_project": "native-project"})
                self.assertEqual(state["current_stage"], "briefing")
                self.assertIn("I-2", call("open_wave", error=True))
                state_dir = project / ".claude/agente-00c-state"
                self.assertFalse((state_dir / ".lock").exists())
                for field, value in (("atomic_commit", False), ("roadmap_mode", False), ("delivery_tier", "local")):
                    call("optin", {"field": field, "value": value, "channel": "prose",
                                   "response_source": "Isolated contract-test fixture, not an operator response"})
                wave = call("open_wave")
                self.assertEqual(wave["stage"], "briefing")
                self.assertTrue((state_dir / ".lock").is_dir())
                self.assertIn("owned wave", call("select_execution", {"project": client.project, "kind": "project",
                                                                       "short_name": "native-project"}, error=True))
                self.assertIn("already owned", call("open_wave", error=True))
                result = call("pause", {"instruction": "Continue the same phase after native transport verification"})
                self.assertEqual(result["current_stage"], "briefing")
                self.assertFalse((state_dir / ".lock").exists())
                self.assertTrue(database.is_file())
                self.assertEqual(call("resume")["wave_id"], "onda-002")
                block = call("block", {"context": "A fonte real do contrato ainda precisa ser fornecida na fixture",
                                        "question": "Qual e a fonte real deste contrato na fixture?",
                                        "rationale": "O contrato nao pode ser inventado e requer resposta identificada da fixture."})
                waiting = call("resume")
                self.assertEqual(waiting["pending_blocks"][0]["id"], block["block_id"])
                self.assertFalse((state_dir / ".lock").exists())
                self.assertEqual(call("resume", {"block_id": block["block_id"],
                                                  "answer": "Usar o contrato local indicado pela fixture",
                                                  "response_source": "Isolated contract fixture, not an operator response"})["wave_id"], "onda-003")
                self.assertEqual(call("status")["open_waves"], ["onda-003"])
                aborted = call("abort", {"reason": "Native lifecycle fixture completed preserving canonical history"})
                self.assertEqual(aborted["status"], "abortada")
                self.assertTrue(Path(aborted["report"]).is_file())
                self.assertFalse((state_dir / ".lock").exists())
                self.assertFalse(call("abort")["aborted"])
                self.assertFalse(call("resume")["resumed"])
                # Exercise native handoff/reconciliation on a second execution;
                # the foreign provenance is an explicit transport-test fixture.
                docs = project / "docs"
                docs.mkdir(exist_ok=True)
                (docs / "briefing.md").write_text("# Briefing de fixture nativa\n")
                (docs / "constitution.md").write_text("# Constitution\n**Version**: 1.0.0\n")
                (docs / "specs/native-feature").mkdir(parents=True)
                call("select_execution", {"kind": "feature", "short_name": "native-feature"})
                foreign = call("bootstrap", {"description": "Validate native handoff and governance reconciliation",
                                              "canonical_project": "native-project"})
                call("optin", {"value": False, "channel": "prose",
                               "response_source": "Isolated transport fixture, not an operator response"})
                call("open_wave")
                call("pause", {"instruction": "A fixture vai transferir explicitamente esta execucao pausada"})
                env = dict(os.environ, CSTK_KNOWLEDGE_DB=str(database))
                probe = Session(adapter_context.prepare(project, "native-feature", test_session.ROOT, env), env)
                with probe.locked():
                    probe.run("state-rw.sh", "set", "--state-dir", probe.state_dir,
                              "--field", ".execution_provenance", "--value",
                              json.dumps({"runtime": "claude-code", "model": "fixture-only", "toolkit_version": "legacy"}))
                transfer = call("handoff", {"expected_runtime": "claude-code",
                                            "response_source": "Isolated transport fixture explicitly authorizes handoff",
                                            "rationale": "A fixture valida transferencia explicita sem mudar identidade, ondas ou artefatos."})
                self.assertTrue(transfer["handed_off"])
                self.assertEqual(transfer["execution_id"], foreign["execution"]["id"])
                (docs / "briefing.md").write_text("# Briefing de fixture revisada\n")
                self.assertIn("drift", call("resume", error=True))
                hashes = [name + ":" + hashlib.sha256((docs / (name + ".md")).read_bytes()).hexdigest()
                          for name in ("briefing", "constitution")]
                reconciliation = call("reconcile_governance", {"expected_hashes": hashes,
                                      "response_source": "Isolated fixture explicitly reviewed both governance artifacts",
                                      "rationale": "Os dois arquivos da fixture foram revisados e seus hashes autorizam a reconciliacao."})
                self.assertTrue(reconciliation["reconciled"])
                self.assertEqual(call("resume")["wave_id"], "onda-002")
                self.assertEqual(call("abort", {"purge_backups": True})["status"], "abortada")
                self.assertFalse((probe.state_dir / "backups").exists())
                # Direct app-server MCP RPC is inventory/control validation;
                # absence of a model turn means no claim of tool-hook coverage.
                self.assertFalse(any("hook/" in item.get("method", "") for item in client.notifications))
            finally:
                client.close()
