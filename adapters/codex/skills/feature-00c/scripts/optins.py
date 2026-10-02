#!/usr/bin/env python3
"""Record an explicit operator response before the first feature wave."""

import argparse
from datetime import datetime, timezone
import json

from context import discover_source, prepare
from session import Session, SessionError


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def collect(session, value, channel, response_source, field="atomic_commit"):
    if field not in ("atomic_commit", "roadmap_mode", "delivery_tier"):
        raise SessionError("unknown opt-in field")
    if field != "atomic_commit" and session.context.get("kind") != "project":
        raise SessionError("project opt-in requires project execution")
    valid = value in ("local", "internal-network", "cloud-internal", "cloud-public") if field == "delivery_tier" else type(value) is bool
    if not valid or channel not in ("structured", "prose"):
        raise SessionError("explicit value and observed response channel required")
    encoded = value if field == "delivery_tier" else str(value).lower()
    if not isinstance(response_source, str) or len(response_source.strip()) < 10:
        raise SessionError("reference to the actual operator response required")
    with session.locked():
        state = session.validate()
        responses = state.get("optin_responses", [])
        previous = [r for r in responses if r.get("field") == field]
        if previous and (previous[-1].get("outcome") not in ("failed", "unavailable")
                         or previous[-1].get("channel") == "prose"):
            if previous[-1].get("applied_value") != encoded:
                raise SessionError("opt-in already resolved; changing it requires explicit reconciliation")
            return previous[-1]
        if state.get("waves"):
            raise SessionError("initial opt-ins must be collected before the first wave")
        helper = {"atomic_commit": "commit-mode.sh", "roadmap_mode": "roadmap-mode.sh", "delivery_tier": "delivery-tier.sh"}[field]
        extra = ["--allow-downgrade"] if field == "delivery_tier" else []
        session.run(helper, "set" if field == "delivery_tier" else "set-enabled", "--state-dir", session.state_dir,
                    "--value", encoded, *extra)
        response = {"field": field, "channel": channel, "outcome": "accepted",
                    "applied_value": encoded, "recorded_at": now(), "reason": None,
                    "response_source": response_source}
        session.run("state-rw.sh", "set", "--state-dir", session.state_dir,
                    "--field", ".optin_responses", "--value", json.dumps(responses + [response]))
        return response


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--short-name", required=True)
    parser.add_argument("--kind", choices=("feature", "project"), default="feature")
    parser.add_argument("--field", choices=("atomic_commit", "roadmap_mode", "delivery_tier"), default="atomic_commit")
    values = parser.add_mutually_exclusive_group(required=True)
    values.add_argument("--atomic-commit", choices=("true", "false"))
    values.add_argument("--value")
    parser.add_argument("--channel", choices=("structured", "prose"), required=True)
    parser.add_argument("--response-source", required=True)
    args = parser.parse_args()
    raw = args.atomic_commit if args.atomic_commit is not None else args.value
    if args.atomic_commit is not None and args.field != "atomic_commit":
        parser.error("--atomic-commit only applies to atomic_commit")
    if args.field != "delivery_tier" and raw not in ("true", "false"):
        parser.error("boolean opt-ins require true or false")
    try:
        session = Session(prepare(args.project, args.short_name, discover_source(__file__), kind=args.kind))
        print(json.dumps(collect(session, raw if args.field == "delivery_tier" else raw == "true", args.channel,
                                 args.response_source, field=args.field), ensure_ascii=False))
    except (SessionError, OSError, ValueError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    main()
