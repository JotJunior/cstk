#!/usr/bin/env python3
"""Experimental stdio MCP transport for the supervised feature controller.

One server owns one target and at most one open wave. Native plugin wiring
remains gated on verifying the host's MCP tool identity and hook coverage.
"""

import argparse
import json
import os
from pathlib import Path
import signal
import sys

from context import discover_source, prepare
from controller import Controller
from optins import collect
import lifecycle
from session import Session, SessionError


def schema(properties=None, required=()):
    return {"type": "object", "properties": properties or {},
            "required": list(required), "additionalProperties": False}


STRING = {"type": "string"}
TOOLS = {
    "select_execution": schema({"project": STRING, "short_name": STRING, "kind": STRING,
                                "knowledge_db": STRING}, ("short_name", "kind")),
    "context": schema(),
    "bootstrap": schema({"description": STRING, "canonical_project": STRING,
                         "model": STRING}, ("description", "canonical_project")),
    "optin": schema({"value": {"type": ["boolean", "string"]}, "field": STRING, "channel": STRING,
                     "response_source": STRING}, ("value", "channel", "response_source")),
    "open_wave": schema(),
    "status": schema(),
    "resume": schema({key: STRING for key in ("block_id", "answer", "response_source")} |
                     {key: {"type": "array", "items": STRING} for key in
                      ("init_aspects", "technical_aspects", "operational_aspects")}),
    "abort": schema({"reason": STRING, "purge_backups": {"type": "boolean"},
                     "abandoned_owner_pid": {"type": "integer"}}),
    "handoff": schema({key: STRING for key in ("expected_runtime", "response_source", "rationale", "model")} |
                      {"abandoned_owner_pid": {"type": "integer"}},
                      ("expected_runtime", "response_source", "rationale")),
    "reconcile_governance": schema({"expected_hashes": {"type": "array", "items": STRING},
                                    "response_source": STRING, "rationale": STRING},
                                   ("expected_hashes", "response_source", "rationale")),
    "decision": schema({key: STRING for key in
                        ("context", "choice", "rationale", "evidence",
                         "decision_class", "axis", "consent")} |
                       {"score": {"type": "integer"},
                        "options": {"type": "array", "items": STRING},
                        "references": {"type": "array", "items": STRING}},
                       ("context", "options", "choice", "rationale")),
    "complete": schema({"evidence_paths": {"type": "array", "items": STRING},
                        "rationale": STRING,
                        "used_sources": {"type": "array", "items": STRING}},
                       ("evidence_paths", "rationale")),
    "pause": schema({"instruction": STRING}, ("instruction",)),
    "block": schema({key: STRING for key in ("context", "question", "rationale", "subject")} |
                    {"options": {"type": "array", "items": STRING}},
                    ("context", "question", "rationale")),
    "recover": schema({"abandoned_owner_pid": {"type": "integer"}}),
}

DESCRIPTIONS = {
    "select_execution": "Bind this server to the operator's absolute session project and select an existing execution or bootstrap target. Does not create state.",
    "context": "Inspect selected project, canonical runtime paths, prerequisites and knowledge database before opening a wave.",
    "bootstrap": "Create a new Codex execution; refuse to overwrite existing state. Collect real opt-ins before the first wave.",
    "optin": "Record a real initial operator response for atomic_commit, roadmap_mode or delivery_tier. Never infer consent.",
    "status": "Inspect execution identity, runtime, current phase, terminal status and pending human blocks without advancing.",
    "resume": "Resume the persisted pipeline phase and own its wave. Pending blocks return questions; answer only from an actual operator response with its source and block ID.",
    "abort": "Abort the selected execution, including this connection's open wave, preserving artifacts and history and releasing the lock. Purge backups only on explicit operator request.",
    "handoff": "Explicitly transfer a paused Claude or unattributed execution to Codex after operator authorization; preserve previous provenance and execution history.",
    "reconcile_governance": "Apply reviewed briefing and constitution changes only with both observed SHA256 hashes, concrete rationale and operator response source.",
    "open_wave": "Open and own the current pipeline phase until complete, pause, block or abort; returns shared instructions and evidence requirements.",
    "decision": "Record a justified decision in this connection's open wave, applying canonical structural consent and evidence gates.",
    "complete": "Verify real persisted evidence and canonical pipeline gates, close this wave and advance at most one phase. Continue remaining phases until terminal or blocked.",
    "pause": "Close this connection's wave without advancing, preserving a concrete instruction for resumption.",
    "block": "Register a human question and justified blocking decision, then close without advancing. Do not invent an answer.",
    "recover": "Explicitly close an interrupted Codex wave without advancing; an abandoned lock requires the observed matching owner PID proven dead.",
}


def validate(arguments, definition):
    if not isinstance(arguments, dict):
        raise ValueError("arguments must be an object")
    if set(arguments) - set(definition["properties"]):
        raise ValueError("unknown argument")
    if set(definition["required"]) - set(arguments):
        raise ValueError("missing required argument")
    for key, value in arguments.items():
        kind = definition["properties"][key]["type"]
        if isinstance(kind, list):
            if type(value) not in (bool, str):
                raise ValueError("invalid argument type: " + key)
            continue
        valid = {"string": isinstance(value, str), "boolean": type(value) is bool,
                 "integer": type(value) is int,
                 "array": isinstance(value, list) and all(isinstance(x, str) for x in value)}
        if not valid[kind]:
            raise ValueError("invalid argument type: " + key)


class Bridge:
    def __init__(self, session=None, project=None, source_root=None, environ=None):
        self.session = session
        self.project = session.project if session else Path(project).resolve(strict=True) if project else None
        self.source_root = session.context["source_root"] if session else source_root or discover_source(__file__)
        self.env = session.env if session else dict(os.environ if environ is None else environ)
        self.controller = None
        self.scope = None
        self.initialized = False
        self.ready = False

    def cleanup(self):
        scope, self.scope = self.scope, None
        try:
            if scope is not None:
                scope.__exit__(None, None, None)
        finally:
            self.controller = None

    def call(self, name, arguments):
        if not isinstance(name, str) or not name.startswith("cstk_") or name[5:] not in TOOLS:
            raise ValueError("unknown tool")
        action = name[5:]
        validate(arguments, TOOLS[action])
        if action == "select_execution":
            if self.scope is not None:
                raise SessionError("close the owned wave before selecting an execution")
            raw_project = arguments.get("project")
            if raw_project is not None and not Path(raw_project).is_absolute():
                raise SessionError("project must be an explicit absolute path")
            target = Path(raw_project).resolve(strict=True) if raw_project is not None else self.project
            if target is None:
                raise SessionError("select an explicit project path from the operator's session")
            if self.project is not None and target != self.project:
                raise SessionError("server is already bound to another project; restart to change scope")
            env = dict(self.env)
            if "knowledge_db" in arguments:
                database = Path(arguments["knowledge_db"])
                if not database.is_absolute() or database.is_dir():
                    raise SessionError("knowledge_db must be an explicit absolute file path")
                env["CSTK_KNOWLEDGE_DB"] = str(database.resolve())
            candidate = Session(prepare(target, arguments["short_name"], self.source_root,
                                        env, kind=arguments["kind"]), env)
            if Path(candidate.context["knowledge_db"]).resolve().is_relative_to(candidate.state_dir.resolve()):
                raise SessionError("derived knowledge index cannot share the canonical state directory")
            # Selection/abort/status must remain possible if prerequisites disappeared.
            candidate.check_scope(require_prerequisites=False)
            self.session = candidate
            self.project = target
            self.env = candidate.env
            return candidate.context
        if action == "context":
            return self.session.context if self.session else {"project": str(self.project) if self.project else None, "execution_selected": False,
                                                            "autonomous_ready": False}
        if self.session is None:
            raise SessionError("select an execution before changing state")
        if action == "status":
            if self.scope is not None:
                state = self.session.validate(allow_open=True, allow_terminal=True, runtime=None, governance=False)
                return lifecycle.describe(self.session, state)
            return lifecycle.status(self.session)
        if action == "abort":
            if self.scope is None:
                return lifecycle.abort(self.session, **arguments)
            if "abandoned_owner_pid" in arguments:
                raise SessionError("owned wave does not require abandoned-owner recovery")
            try:
                return lifecycle.abort_owned(self.controller, **arguments)
            finally:
                if self.controller.closed:
                    self.cleanup()
        if action in ("resume", "handoff", "reconcile_governance"):
            if self.scope is not None:
                raise SessionError("close the owned wave before changing session setup")
            if action == "handoff":
                return lifecycle.handoff(self.session, **arguments)
            if action == "reconcile_governance":
                return lifecycle.reconcile_governance(self.session, **arguments)
            result = lifecycle.resume(self.session, **arguments)
            if result["terminal"] or result["pending_blocks"]:
                return result
            return self.call("cstk_open_wave", {})
        if action in ("bootstrap", "optin", "recover"):
            if self.scope is not None:
                raise SessionError("close the owned wave before changing session setup")
            if action == "bootstrap":
                return self.session.bootstrap(**arguments)
            if action == "optin":
                return collect(self.session, **arguments)
            return Controller(self.session).recover(**arguments)
        if action == "open_wave":
            if self.scope is not None:
                raise SessionError("a wave is already owned by this server")
            control = Controller(self.session)
            scope = control.wave()
            descriptor = scope.__enter__()
            self.controller, self.scope = control, scope
            return descriptor
        if self.scope is None:
            raise SessionError("open a wave before recording execution")
        if action == "decision":
            return {"decision_id": self.controller.decision(**arguments)}
        try:
            if action == "complete":
                return self.controller.complete(**arguments)
            if action == "block":
                return {"block_id": self.controller.block(**arguments)}
            return self.controller.close("threshold_proxy_atingido", arguments["instruction"])
        finally:
            # Evidence errors keep an open wave; a reporting error after close
            # must still release the writer so resume/abort can inspect it.
            if self.controller.closed:
                self.cleanup()

    def dispatch(self, request):
        if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
            return {"jsonrpc": "2.0", "id": None,
                    "error": {"code": -32600, "message": "Invalid Request"}}
        if "id" not in request:
            if request.get("method") == "notifications/initialized" and self.initialized:
                self.ready = True
            return None
        response = {"jsonrpc": "2.0", "id": request["id"]}
        method, params = request.get("method"), request.get("params", {})
        if not isinstance(params, dict):
            response["error"] = {"code": -32602, "message": "Invalid params"}
        elif method == "initialize":
            self.initialized = True
            version = params.get("protocolVersion")
            response["result"] = {"protocolVersion": version if version in
                                  ("2024-11-05", "2025-03-26", "2025-06-18") else "2025-06-18",
                                  "capabilities": {"tools": {}},
                                  "serverInfo": {"name": "cstk-supervised", "version": "0.1.0"}}
        elif method == "ping":
            response["result"] = {}
        elif not self.ready:
            response["error"] = {"code": -32600, "message": "Initialization required"}
        elif method == "tools/list":
            response["result"] = {"tools": [{"name": "cstk_" + name,
                                            "description": DESCRIPTIONS[name],
                                            "inputSchema": definition}
                                           for name, definition in TOOLS.items()]}
        elif method == "tools/call":
            try:
                result = self.call(params.get("name"), params.get("arguments", {}))
                response["result"] = {"content": [{"type": "text", "text": json.dumps(result)}]}
            except (SessionError, OSError, ValueError, TypeError, KeyError) as exc:
                response["result"] = {"isError": True,
                                      "content": [{"type": "text", "text": str(exc)}]}
        else:
            response["error"] = {"code": -32601, "message": "Method not found"}
        return response


def serve(bridge, source, target):
    try:
        for line in source:
            try:
                response = bridge.dispatch(json.loads(line))
            except (ValueError, RecursionError):
                response = {"jsonrpc": "2.0", "id": None,
                            "error": {"code": -32700, "message": "Parse error"}}
            if response is not None:
                target.write(json.dumps(response) + "\n")
                target.flush()
    finally:
        bridge.cleanup()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", help="Explicit fixed project scope; native plugins bind through select_execution")
    parser.add_argument("--short-name")
    parser.add_argument("--kind", choices=("feature", "project"), default="feature")
    args = parser.parse_args()
    if args.short_name and not args.project:
        parser.error("--short-name requires --project")
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    bridge = Bridge(Session(prepare(args.project, args.short_name, discover_source(__file__), kind=args.kind))) if args.short_name else Bridge(project=args.project)
    try:
        serve(bridge, sys.stdin, sys.stdout)
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
