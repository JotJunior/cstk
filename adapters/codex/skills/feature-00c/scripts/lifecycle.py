#!/usr/bin/env python3
"""Audited resume, abort and explicit handoff for both canonical state backends."""

import argparse
import json
from pathlib import Path
import re
import shutil
import signal

from context import discover_source, prepare
from controller import Controller
from optins import now
from session import Session, SessionError


TERMINAL = {"concluida", "abortada"}


def write(session, fields):
    if not session._locked:
        raise SessionError("lifecycle mutation requires the session lock")
    if ".events" in fields:
        # Canonical document write is one transaction on SQLite; multi-set
        # deliberately rejects mixing normalized arrays and scalar columns.
        state = session.read()
        for field, value in fields.items():
            parts = field.lstrip(".").split(".")
            parent = state
            for part in parts[:-1]:
                parent = parent.setdefault(part, {})
            parent[parts[-1]] = value
        session.run("state-rw.sh", "write", "--state-dir", session.state_dir,
                    input_text=json.dumps(state, ensure_ascii=False))
        return
    args = ["set", "--state-dir", session.state_dir]
    for field, value in fields.items():
        args += ["--field", field, "--value", json.dumps(value, ensure_ascii=False)]
    session.run("state-rw.sh", *args)


def operator_source(source):
    if not isinstance(source, str) or len(source.strip()) < 10:
        raise SessionError("reference to the actual operator response required")


def audit(session, action, details):
    Controller(session).event(action, json.dumps(details, ensure_ascii=False))


def decision(session, action, rationale, references=None):
    if not isinstance(rationale, str) or len(rationale.strip()) < 20:
        raise SessionError("a concrete rationale of at least 20 characters is required")
    state = session.read()
    args = ["register", "--state-dir", session.state_dir, "--agente", "codex-lifecycle-orchestrator",
            "--etapa", state["current_stage"], "--contexto", "Operacao explicita de ciclo de vida: " + action,
            "--opcoes", json.dumps([action, "preservar-estado"]), "--escolha", action,
            "--justificativa", rationale, "--score", "2"]
    if references:
        args += ["--referencias", json.dumps(references)]
    return session.run("state-decisions.sh", *args).strip()


def describe(session, state):
    return {"execution_id": state["execution"]["id"], "kind": session.context.get("kind", "feature"),
            "short_name": session.context["short_name"], "status": state["execution"]["status"],
            "current_stage": state["current_stage"], "next_instruction": state.get("next_instruction"),
            "execution_provenance": state.get("execution_provenance"),
            "pending_blocks": [b for b in state.get("human_blocks", []) if b["status"] == "aguardando"],
            "open_waves": [w["id"] for w in state.get("waves", []) if w.get("finished_at") is None],
            "waves_total": len(state.get("waves", [])), "terminal": state["execution"]["status"] in TERMINAL,
            "knowledge_db": session.context["knowledge_db"], "autonomous_ready": False}


def status(session):
    # Inspection also works for another runtime, terminal state or missing governance.
    with session.locked(require_prerequisites=False):
        return describe(session, session.validate(allow_open=True, allow_terminal=True,
                                                  runtime=None, governance=False))


def resume(session, block_id=None, answer=None, response_source=None,
           init_aspects=None, technical_aspects=None, operational_aspects=None):
    if answer is None and (block_id is not None or (response_source is not None and init_aspects is None)):
        raise SessionError("block_id and response_source require an actual answer")
    if answer is not None:
        operator_source(response_source)
        if not answer.strip() or len(answer) > 2000:
            raise SessionError("human answer must contain 1..2000 characters")
    if any(x is not None for x in (init_aspects, technical_aspects, operational_aspects)):
        if session.context.get("kind") != "project" or init_aspects is None:
            raise SessionError("aspect initialization requires a project and init_aspects")
        operator_source(response_source)
        for values, low in ((init_aspects, 3), (technical_aspects or [], 0), (operational_aspects or [], 0)):
            if not isinstance(values, list) or not low <= len(values) <= 7 or any(
                    not isinstance(x, str) or not x.strip() for x in values):
                raise SessionError("invalid aspect list (initial: 3..7; technical/operational: 0..7)")
    with session.locked(require_prerequisites=False):
        state = session.validate(allow_terminal=True, runtime=None, governance=False)
        if state["execution"]["status"] in TERMINAL:
            return describe(session, state) | {"resumed": False}
        session.check_scope()
        session.validate()  # Governance must be reconciled before responding/dispatching.
        changed = False
        if init_aspects is not None and state.get("initial_key_aspects"):
            raise SessionError("initial aspects already recorded; refusing replacement")
        if answer is not None:
            pending = [b for b in state.get("human_blocks", []) if b["status"] == "aguardando"]
            if block_id is None:
                if len(pending) != 1:
                    raise SessionError("an explicit block_id is required unless exactly one block is pending")
                block_id = pending[0]["id"]
            block = next((b for b in state.get("human_blocks", []) if b["id"] == block_id), None)
            if block is None:
                raise SessionError("unknown block_id")
            if block["status"] == "respondido":
                if block.get("human_answer") != answer:
                    raise SessionError("block already answered; refusing to replace the operator response")
            elif block["status"] != "aguardando":
                raise SessionError("block is not pending")
            else:
                session.run("bloqueios.sh", "respond", "--state-dir", session.state_dir,
                            "--block-id", block_id, "--resposta", answer)
                did = decision(session, "registrar-resposta-humana",
                               "Resposta recebida do operador para o bloqueio " + block_id +
                               "; o conteudo foi preservado sem inferir conclusao da etapa.", [block_id, response_source])
                audit(session, "human_response", {"block_id": block_id, "decision_id": did,
                                                  "response_source": response_source})
                changed = True
        if init_aspects is not None:
            session.run("drift.sh", "init", "--state-dir", session.state_dir,
                        "--aspectos", json.dumps(init_aspects), "--tecnicos", json.dumps(technical_aspects or []),
                        "--operacionais", json.dumps(operational_aspects or []))
            did = decision(session, "inicializar-aspectos-legados",
                           "O operador forneceu aspectos para habilitar a verificacao de finalidade antes da retomada.",
                           [response_source])
            audit(session, "aspects_initialized", {"decision_id": did, "response_source": response_source})
            changed = True
        if changed:
            Controller(session).after_close()
        return describe(session, session.read()) | {"resumed": True}


def backups_scope(session):
    directory = session.state_dir / "backups"
    if directory.is_symlink() or not directory.resolve().is_relative_to(session.state_dir.resolve()):
        raise SessionError("backup directory escapes state scope")
    if directory.exists() and not directory.is_dir():
        raise SessionError("backup directory is not a directory")
    return directory


def abort_owned(control, reason="aborto manual", purge_backups=False):
    session = control.session
    # Abort is available even when a prerequisite disappeared or drifted.
    state = session.validate(allow_open=True, allow_terminal=True, runtime=None, governance=False)
    directory = backups_scope(session)
    if not isinstance(reason, str) or not reason.strip() or len(reason) > 2000:
        raise SessionError("abort reason must contain 1..2000 characters")
    if state["execution"]["status"] in TERMINAL:
        return describe(session, state) | {"aborted": False}
    session.validate(allow_open=True, governance=False)
    last = state.get("waves", [])[-1] if state.get("waves") else None
    if last and last.get("finished_at") is None:
        control.wave_id, control.stage = last["id"], state["current_stage"]
        control.assert_owner()
        control.backup()
    else:
        control.stage = state["current_stage"]
    did = decision(session, "abortar-execucao", "O operador solicitou encerrar esta execucao: " + reason)
    if last and last.get("finished_at") is None:
        session.run("state-ondas.sh", "end", "--state-dir", session.state_dir,
                    "--motivo-termino", "aborto", "--next-instruction", "Execucao abortada: " + reason)
        control.closed = True
    events = session.read().get("events", []) + [{"event_type": "execution_aborted", "timestamp": now(),
               "description": json.dumps({"reason": reason, "decision_id": did, "purge_backups": purge_backups})}]
    write(session, {".execution.status": "abortada", ".execution.finished_at": now(),
                    ".execution.termination_reason": reason, ".next_instruction": "Execucao abortada: " + reason,
                    ".events": events})
    control.closed = True
    control.backup(snapshot_name="abort-final")
    if purge_backups and directory.exists():
        shutil.rmtree(directory)
    result = control.after_close()
    result["aborted"] = True
    # A persisted commit opt-in is respected; no implicit staging or push.
    if session.run("commit-mode.sh", "is-enabled", "--state-dir", session.state_dir).strip() == "true":
        try:
            session.run("state-ondas.sh", "git-commit", "--state-dir", session.state_dir,
                        "--projeto-alvo-path", session.project, "--motivo", reason)
            result["commit_status"] = "completed"
        except SessionError as exc:
            audit(session, "abort_commit_degraded", {"error": str(exc)})
            result["commit_status"] = "degraded"
            # Refresh derived artifacts to include the failure, without undoing abort.
            result.update(control.after_close())
    else:
        result["commit_status"] = "disabled"
    return result


def abort(session, reason="aborto manual", purge_backups=False, abandoned_owner_pid=None):
    with session.locked(abandoned_owner_pid=abandoned_owner_pid, require_prerequisites=False):
        return abort_owned(Controller(session), reason, purge_backups)


def handoff(session, expected_runtime, response_source, rationale, model=None, abandoned_owner_pid=None):
    operator_source(response_source)
    if expected_runtime not in ("claude-code", "unattributed"):
        raise SessionError("handoff source must be claude-code or explicitly unattributed")
    with session.locked(abandoned_owner_pid=abandoned_owner_pid):
        state = session.validate(runtime=None)
        before = state.get("execution_provenance")
        actual = (before or {}).get("runtime") or "unattributed"
        if actual == "codex":
            previous = state.get("runtime_handoffs", [])
            if previous and previous[-1]["from_runtime"] == expected_runtime and previous[-1]["response_source"] == response_source:
                return describe(session, state) | {"handed_off": False}
            raise SessionError("execution is already owned by Codex")
        if actual != expected_runtime:
            raise SessionError("handoff runtime does not match the recorded origin")
        did = decision(session, "transferir-execucao-para-codex", rationale, [response_source])
        transfer = {"from_runtime": actual, "to_runtime": "codex", "previous_provenance": before,
                    "response_source": response_source, "rationale": rationale, "decision_id": did, "timestamp": now()}
        fresh = {"runtime": "codex", "model": model,
                 "toolkit_version": (Path(session.context["source_root"]) / "cli/VERSION").read_text().strip()}
        fields = {".execution_provenance": fresh, ".runtime_handoffs": state.get("runtime_handoffs", []) + [transfer],
                  ".events": session.read().get("events", []) + [{"event_type": "runtime_handoff", "timestamp": now(),
                                                                "description": json.dumps(transfer)}]}
        if session.context.get("kind") == "project":
            fields[".codex_governance"] = {name: info for name, info in session.context["artifacts"].items()
                                          if info["exists"]}
        write(session, fields)
        # No stage, wave, opt-in or prior decision is rewritten by the transfer.
        Controller(session).after_close()
        return describe(session, session.read()) | {"handed_off": True}


def reconcile_governance(session, expected_hashes, response_source, rationale):
    operator_source(response_source)
    with session.locked():
        state = session.validate(governance=False)
        fresh = prepare(session.project, session.context["short_name"], session.context["source_root"],
                        session.env, session.context.get("kind", "feature"))["artifacts"]
        actual = sorted(name + ":" + info["sha256"] for name, info in fresh.items() if info["exists"])
        if sorted(expected_hashes) != actual or len(actual) != 2:
            raise SessionError("expected hashes must match both current governance artifacts")
        for info in fresh.values():
            if not Path(info["path"]).resolve().is_relative_to(session.project):
                raise SessionError("governance artifact escapes project scope")
        version = re.search(r"^\*\*Version\*\*:\s*(\d+\.\d+\.\d+)",
                            Path(fresh["constitution"]["path"]).read_text(), re.M)
        if not version:
            raise SessionError("constitution requires **Version**: X.Y.Z")
        field = ".prerequisites" if session.context.get("kind", "feature") == "feature" else ".codex_governance"
        before = state.get(field[1:], {})
        replacement = before | {name: info | ({"version": version.group(1)} if name == "constitution" else {})
                                 for name, info in fresh.items()}
        did = decision(session, "reconciliar-governanca", rationale, expected_hashes + [response_source])
        entry = {"timestamp": now(), "previous": before, "current": replacement,
                 "response_source": response_source, "rationale": rationale, "decision_id": did}
        write(session, {field: replacement, ".governance_reconciliations": state.get("governance_reconciliations", []) + [entry]})
        session.context["artifacts"] = fresh
        audit(session, "governance_reconciled", entry)
        session.validate()
        Controller(session).after_close()
        return describe(session, session.read()) | {"reconciled": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("status", "resume", "abort", "handoff", "reconcile-governance"))
    parser.add_argument("--project", "--projeto", required=True)
    parser.add_argument("--short-name", required=True)
    parser.add_argument("--kind", choices=("feature", "project"), default="feature")
    parser.add_argument("--block-id")
    parser.add_argument("--answer", "--resposta-bloqueio")
    parser.add_argument("--response-source")
    parser.add_argument("--reason", "--motivo", default="aborto manual")
    parser.add_argument("--purge-backups", action="store_true")
    parser.add_argument("--abandoned-owner-pid", type=int)
    parser.add_argument("--expected-runtime")
    parser.add_argument("--observed-model")
    parser.add_argument("--rationale")
    parser.add_argument("--expected-hash", action="append")
    parser.add_argument("--init-aspects", "--init-aspectos", type=json.loads)
    parser.add_argument("--technical-aspects", "--init-aspectos-tecnicos", type=json.loads)
    parser.add_argument("--operational-aspects", "--init-aspectos-operacionais", type=json.loads)
    args = parser.parse_args()
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        session = Session(prepare(args.project, args.short_name, discover_source(__file__), kind=args.kind))
        if args.mode == "status":
            result = status(session)
        elif args.mode == "resume":
            result = resume(session, args.block_id, args.answer, args.response_source,
                            args.init_aspects, args.technical_aspects, args.operational_aspects)
        elif args.mode == "abort":
            result = abort(session, args.reason, args.purge_backups, args.abandoned_owner_pid)
        elif args.mode == "handoff":
            result = handoff(session, args.expected_runtime, args.response_source, args.rationale,
                             args.observed_model, args.abandoned_owner_pid)
        else:
            result = reconcile_governance(session, args.expected_hash or [], args.response_source, args.rationale)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if args.mode == "resume" and result["pending_blocks"]:
            return 5
    except (SessionError, OSError, ValueError, TypeError) as exc:
        parser.exit(1, str(exc) + "\n")
    except KeyboardInterrupt:
        parser.exit(130, "lifecycle operation interrupted; lock released\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
