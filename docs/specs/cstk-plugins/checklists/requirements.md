# Requirements Quality Checklist: cstk-plugins

**Purpose**: Validate the QUALITY of the cstk-plugins requirements (completeness,
clarity, consistency, measurability, scenario/edge coverage, traceability) —
"unit tests for English", not implementation tests.
**Created**: 2026-06-08
**Feature**: [spec.md](../spec.md)

## Completeness

- [x] CHK001 - Are functional requirements documented for every user story (install, activate, manage, lang-plugin)? [Completude, Spec §US1–US4, FR-001..FR-018] {auto}
  - Evidence: US1→FR-001/002/004/008/009; US2→FR-013/014/015; US3→FR-010/011/012; US4 reuses FR-001..FR-009 flow. All four stories have backing FRs.
- [x] CHK002 - Are non-functional requirements (security, performance, offline) covered? [Completude, Spec §SC-002/SC-004/SC-006, FR-005/FR-006/FR-018] {auto}
  - Evidence: Security = FR-003..FR-005 + plan §Security Threat Model; performance = SC-001 (<60s)/SC-004 (<2s); offline = FR-018 + SC-006.
- [x] CHK003 - Is out-of-scope explicitly declared? [Completude, Spec §FR-011, §Success Criteria note] {auto}
  - Evidence: FR-011 declares machine-readable/JSON output out of scope; SC note declares "no new infrastructure / no scheduling". Version-pinning + detached signature declared as future extensions in plan §Security Threat Model.
- [ ] CHK004 - Is the plugin **uninstall/cleanup contract** fully specified (registry entry + files + partial-remove failure mode)? [Completude, Gap] {auto}
  - Gap: FR-012 covers files + registry update + not-found exit, but does NOT specify behavior on a *partial* removal failure (e.g., some files deleted, registry write fails). Edge case "remove during running pipeline" is covered; mid-remove crash is not. Candidate for /create-tasks or /clarify.

## Clarity

- [x] CHK005 - Does every functional requirement use a testable imperative (MUST/SHOULD/MAY)? [Clareza, Spec §FR-001..FR-018] {auto}
  - Evidence: All 18 FRs use MUST/MAY consistently (e.g., FR-002 "MUST match", FR-001 "MAY override").
- [x] CHK006 - Is the plugin-name pattern quantified (not "valid name")? [Clareza, Spec §FR-002] {auto}
  - Evidence: FR-002 gives the exact regex `^[a-z][a-z0-9-]{0,63}$` and states it is checked before any fs/network op.
- [x] CHK007 - Are integrity-status values an enumerated closed set (not vague "status")? [Clareza, Spec §FR-011, §Key Entities] {auto}
  - Evidence: FR-011 + US3-AS1 enumerate `ok | tampered | unknown`. Plugin Type enum `llm | lang` also closed (Key Entities).
- [x] CHK008 - Are the hosting-base default and override mechanism unambiguous? [Clareza, Spec §FR-001, §Clarifications dec-005] {auto}
  - Evidence: Default `https://github.com/JotJunior/`; override via `CSTK_PLUGIN_REGISTRY` env or `~/.cstk/config` key=value; precedence ("default always used when neither present") stated.
- [ ] CHK009 - Is the `--force` vs interactive-confirm precedence for re-install fully unambiguous when stdin is non-interactive (CI/piped)? [Clareza, Ambiguity, Spec §FR-009] {auto}
  - Ambiguity: FR-009 says "interactive prompt OR --force" but does not define behavior when no TTY is present and `--force` is absent (abort? default-no?). Candidate for /clarify.

## Consistency

- [x] CHK010 - Do requirements align without conflicts (store path, immutable core catalog)? [Consistencia, Spec §FR-007, Plan §Re-check pos-Phase 1] {auto}
  - Evidence: FR-007 store-path literal (`~/.claude/plugins/`) is reconciled in plan (`~/.claude/cstk/plugins/`, research D1) while preserving the FR-007 MUST (never write to `~/.claude/skills/`). Plan flags this as the single contract deviation and justifies it. Consistent intent; see CHK022.
- [x] CHK011 - Is terminology consistent (manifest filename, store, registry)? [Consistencia, Spec §Key Entities, Plan §Storage] {auto}
  - Evidence: `plugin-manifest.json`, "plugin store", "plugin registry"/`registry.json` used consistently across spec + plan + data-model.
- [x] CHK012 - Do requirements not contradict the constitution principles? [Constitution Alignment, Plan §Constitution Check] {auto}
  - Evidence: Plan Constitution Check table: I/II/IV all PASS (II with carve-out, IV honored — network only on explicit plugin-add). NON-NEG principles II & IV satisfied.

## Measurability

- [x] CHK013 - Are success criteria objectively verifiable with thresholds? [Mensurabilidade, Spec §SC-001..SC-006] {auto}
  - Evidence: SC-001 <60s; SC-004 <2s; SC-002 100% deterministic; SC-005 shellcheck zero-warning. All have numeric/binary thresholds.
- [x] CHK014 - Can SC-003 (zero-regression default path) be turned into an automated test? [Mensurabilidade, Spec §SC-003, FR-013] {auto}
  - Evidence: SC-003 framed as "indistinguishable from current pipeline when no --llm"; FR-013 anchors it ("--llm claude or no flag = identical"). Testable via existing suite run with/without flag.
- [ ] CHK015 - Is SC-001 (<60s end-to-end) measurable independent of network variance the toolkit cannot control? [Mensurabilidade, Ambiguity, Spec §SC-001] {auto}
  - Ambiguity: SC-001 says "on a normal broadband connection" — the threshold mixes toolkit time with uncontrolled network download time. Whether the 60s budget is toolkit-only or includes download is not separated. Minor; candidate for /clarify.

## Scenario Coverage

- [x] CHK016 - Are happy paths documented for all subcommands? [Cobertura, Spec §US1-AS1, §US2-AS1, §US3-AS1/AS3] {auto}
  - Evidence: Acceptance scenarios cover add-success, activate-success, list-success, remove-success.
- [x] CHK017 - Are error paths defined (checksum mismatch, network down, plugin-not-installed, unsupported manifest version)? [Cobertura, Spec §US1-AS2/AS4, §US2-AS3/AS4, §Edge Cases, FR-015] {auto}
  - Evidence: checksum-mismatch (AS2), network-unreachable (AS4), not-installed-on-activate (US2-AS3 + FR-015), unsupported manifest schema_version (Edge Cases).
- [x] CHK018 - Are concurrency/lifecycle edge cases covered (remove during running pipeline)? [Cobertura, Edge Case, Spec §Edge Cases] {auto}
  - Evidence: Edge Cases explicitly defines "plugin-remove while pipeline running with --llm <plugin>" (running pipeline not interrupted; store entry removed).

## Dependencies & Assumptions

- [x] CHK019 - Are external/optional dependencies explicit with fallbacks? [Completude, Plan §Optional-dep registry, Spec §FR-017] {auto}
  - Evidence: `sha256sum`/`shasum` and `jq` declared optional with documented+tested fallback (plan carve-out table conditions a/b/c); FR-017 states graceful degradation documented and tested.
- [x] CHK020 - Is the trust assumption (TOFU / GitHub-namespace trust) documented? [Clareza, Assumption, Plan §Security Threat Model, dec-018] {auto}
  - Evidence: Plan §Security Threat Model documents TOFU and "trust delegated to GitHub namespace"; operator approved residual risk via dec-018.

## Traceability

- [x] CHK021 - Do user stories link to functional requirements and success criteria? [Traceability, Spec §US1–US4] {auto}
  - Evidence: Each story has Independent Test + Acceptance Scenarios that map to FRs (see CHK001); SCs reference FRs (SC-002→FR-004, SC-006→FR-018).

## Ambiguities & Open Decisions

- [ ] CHK022 - Should FR-007's literal store path (`~/.claude/plugins/`) be amended in the spec to match the plan's chosen path (`~/.claude/cstk/plugins/`, research D1) to remove the documented spec↔plan divergence? [Conflict, Spec §FR-007 vs Plan §Storage] {humano}
  - Note: Intent is consistent (core catalog stays immutable) but the literal default path differs between spec and plan. Product owner should decide whether to backfill the spec wording. Decision-of-record, not a blocker.
- [ ] CHK023 - Is the MVP scope boundary (no version-pinning, no detached signature, no JSON output) acceptable for first release, or should any be pulled in? [Risco, Spec §FR-011, Plan §Security Threat Model] {humano}
  - Note: Risk/priority trade-off owned by the product owner.

## Notes

- `{auto}` items are resolved by the agent (`[x]` with cited evidence, or marked `[Gap]`/`[Ambiguity]`/`[Conflict]`).
- `{humano}` items remain `[ ]` awaiting product-owner decision.
- Open gaps/ambiguities (CHK004, CHK009, CHK015, CHK022) have follow-up destinations in the consolidated gap report.
