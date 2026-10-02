"""MCP transport preserves canonical ownership across independent requests."""

import io
import json
import unittest
from pathlib import Path

import test_controller as fixtures
from mcp_bridge import Bridge, TOOLS, serve
from session import SessionError


class BridgeTests(unittest.TestCase):
    setUp = fixtures.ControllerTests.setUp
    make_session = fixtures.ControllerTests.make_session
    bootstrap = fixtures.ControllerTests.bootstrap
    ready = fixtures.ControllerTests.ready

    def test_protocol_negotiation_validation_and_errors(self):
        bridge = Bridge(self.adapter)
        response = bridge.dispatch({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
        self.assertIn("error", response)
        response = bridge.dispatch({"jsonrpc": "2.0", "id": 2, "method": "initialize",
                                    "params": {"protocolVersion": "2025-06-18"}})
        self.assertEqual(response["result"]["protocolVersion"], "2025-06-18")
        self.assertIsNone(bridge.dispatch({"jsonrpc": "2.0", "method": "notifications/initialized"}))
        response = bridge.dispatch({"jsonrpc": "2.0", "id": 3, "method": "tools/list"})
        self.assertEqual({tool["name"] for tool in response["result"]["tools"]},
                         {"cstk_" + name for name in TOOLS})
        response = bridge.dispatch({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
                                    "params": {"name": "cstk_context", "arguments": {"command": "sh"}}})
        self.assertTrue(response["result"]["isError"])
        target = io.StringIO()
        serve(bridge, io.StringIO("invalid json\n"), target)
        self.assertEqual(json.loads(target.getvalue())["error"]["code"], -32700)

    def test_wave_ownership_spans_calls_and_cleanup_never_advances(self):
        self.ready()
        bridge = Bridge(self.adapter)
        try:
            self.assertEqual(bridge.call("cstk_open_wave", {})["stage"], "specify")
            with self.assertRaises(SessionError):
                with self.make_session().locked():
                    pass
            with self.assertRaisesRegex(SessionError, "already owned"):
                bridge.call("cstk_open_wave", {})
            with self.assertRaises((SessionError, OSError)):
                bridge.call("cstk_complete", {"evidence_paths": ["missing.md"],
                                              "rationale": "Inspect actual evidence before completing"})
            self.assertTrue(self.adapter._locked)
        finally:
            bridge.cleanup()
        state = self.make_session().resume()
        self.assertEqual(state["current_stage"], "specify")
        self.assertIsNotNone(state["waves"][-1]["finished_at"])
        self.assertFalse((self.adapter.state_dir / ".lock").exists())
        bridge.cleanup()

    def test_eof_closes_open_wave(self):
        self.ready()
        bridge = Bridge(self.adapter)
        bridge.call("cstk_open_wave", {})
        serve(bridge, io.StringIO(""), io.StringIO())
        self.assertFalse(self.adapter._locked)
        self.assertEqual(self.make_session().resume()["current_stage"], "specify")

    def test_unbound_plugin_requires_explicit_project_and_preserves_scope(self):
        bridge = Bridge(source_root=fixtures.fixtures.ROOT, environ=self.env)
        self.assertIsNone(bridge.call("cstk_context", {})["project"])
        with self.assertRaisesRegex(SessionError, "explicit project"):
            bridge.call("cstk_select_execution", {"kind": "project", "short_name": "canonical-project"})
        database = Path(self.temp.name) / "shared.db"
        result = bridge.call("cstk_select_execution", {"project": str(self.project), "kind": "project", "short_name": "canonical-project",
                                                      "knowledge_db": str(database)})
        self.assertEqual(result["project"], str(self.project.resolve()))
        self.assertEqual(result["knowledge_db"], str(database.resolve()))
        repeated = bridge.call("cstk_select_execution", {"kind": "project", "short_name": "canonical-project"})
        self.assertEqual(repeated["knowledge_db"], str(database.resolve()))
        other = Path(self.temp.name) / "other"
        other.mkdir()
        with self.assertRaisesRegex(SessionError, "another project"):
            bridge.call("cstk_select_execution", {"project": str(other), "kind": "project", "short_name": "another"})

    def test_selection_cannot_replace_an_owned_wave(self):
        self.ready()
        bridge = Bridge(self.adapter)
        try:
            bridge.call("cstk_open_wave", {})
            with self.assertRaisesRegex(SessionError, "owned wave"):
                bridge.call("cstk_select_execution", {"kind": "feature", "short_name": "test-feature"})
            self.assertTrue(self.adapter._locked)
        finally:
            bridge.cleanup()
