# Security Requirements Quality Checklist: cstk-plugins

**Purpose**: Validate the QUALITY of the security requirements for the plugin
trust model — integrity/checksum verification, supply chain, third-party code
execution, path traversal/tar-slip, and offline guarantees. Validates whether
the REQUIREMENTS are well-specified, not whether code is secure.
**Created**: 2026-06-08
**Feature**: [spec.md](../spec.md) | [plan.md §Security Threat Model](../plan.md)

## Integrity & Checksum Verification

- [x] CHK001 - Are checksum-verification requirements specified for install time? [Cobertura, Spec §FR-004] {auto}
  - Evidence: FR-004 — bundle checksum MUST be verified against manifest `sha256` BEFORE writing any file; mismatch aborts, removes partial downloads, exits non-zero.
- [x] CHK002 - Are checksum re-verification requirements specified for activation time? [Cobertura, Spec §FR-005] {auto}
  - Evidence: FR-005 — re-verify installed plugin checksum at activation (`--llm`) and on `plugin-list` integrity check; mismatch blocks load and reports `tampered`.
- [x] CHK003 - Is the manifest required-field set specified (name, version, type, schema_version, sha256)? [Completude, Spec §FR-003, §Key Entities] {auto}
  - Evidence: FR-003 + Key Entities enumerate required manifest fields including `sha256` of the bundle (excluding the manifest itself).
- [x] CHK004 - Is the checksum scope unambiguous (which files the digest covers)? [Clareza, Spec §FR-003, Plan §hash_dir] {auto}
  - Evidence: FR-003 — `sha256` is "of the plugin bundle (the set of files delivered by the plugin, excluding the manifest itself)"; plan maps to `hash.sh:hash_dir` (research D2).
- [x] CHK005 - Is the integrity guarantee honestly scoped (detects bundle↔manifest mismatch, NOT upstream compromise)? [Clareza, Assumption, Plan §Security Threat Model] {auto}
  - Evidence: Plan reformulates SC-002 as "detection of bundle↔manifest MISMATCH, not detection of malicious upstream"; self-signed-manifest residual risk documented.

## Supply Chain

- [x] CHK006 - Is the threat model documented and requirements aligned to it? [Traceability, Plan §Security Threat Model] {auto}
  - Evidence: Plan §Security Threat Model documents 4 OWASP high findings (A03/A05/A08/ASI04-05) with explicit mitigations or accepted-residual rationale tied to FRs.
- [x] CHK007 - Are supply-chain attack vectors (no version pinning / TOFU) considered and a stance declared? [Cobertura, Risco, Plan §Security Threat Model, dec-018] {auto}
  - Evidence: "Sem version pinning" finding (A03 high) accepted for MVP with TOFU mitigation (bundle_sha256 recorded in registry); operator approved residual via dec-018.
- [x] CHK008 - Is the origin-trust delegation requirement explicit (default namespace = same trust as toolkit)? [Clareza, Spec §FR-001, Plan §Security Threat Model] {auto}
  - Evidence: FR-001 default base `JotJunior/`; plan states "trust of ORIGIN delegated to GitHub namespace trust model (same trust as the toolkit)".
- [ ] CHK009 - Are requirements defined for warning the user about the TOFU/no-pinning trust boundary in user-facing docs? [Completude, Gap, Plan §Security Threat Model row ASI04] {auto}
  - Gap: Plan states "documentation MUST warn to only install plugins from trusted authors" but no FR captures this user-facing-doc requirement as a tracked deliverable. Candidate for /create-tasks (doc task).

## Path Traversal & Extraction Safety

- [x] CHK010 - Are name-based path-traversal requirements specified before any fs/network op? [Cobertura, Spec §FR-002, §Edge Cases] {auto}
  - Evidence: FR-002 regex rejection before fs/network; Edge Cases explicitly handles `../evil` style names.
- [x] CHK011 - Are tar-slip / archive-extraction safety requirements specified (reject `..`, absolute paths, escaping symlinks)? [Cobertura, Plan §Security Threat Model, dec-014, contracts/cli-commands §5.bis] {auto}
  - Evidence: dec-014 + plan A05/A08 row: `plugin-add` MUST validate every tarball entry (no `/`, no `..`, no escaping symlink) BEFORE extracting into an isolated `mktemp -d`; any out-of-prefix entry aborts (exit 1, cleans tmp). Detailed in contracts/cli-commands §5.bis; Scenario 3b covers.
- [x] CHK012 - Are atomicity/rollback requirements specified to prevent partial-write state? [Completude, Spec §FR-008] {auto}
  - Evidence: FR-008 — staging in tmp; move to store only after checksum passes; on failure/interruption tmp is cleaned and store left unchanged.

## Third-Party Code Execution

- [x] CHK013 - Is the third-party-code-execution risk explicitly acknowledged and its control stated? [Clareza, Assumption, Plan §Security Threat Model row ASI04/ASI05/LLM01, dec-018] {auto}
  - Evidence: Plan row: installing a plugin equals `cp` of arbitrary code; checksum verifies BYTES not SAFETY; no sandbox proposed (incompatible with Princ. II); control = honest trust model + user warning. Operator approved residual via dec-018.
- [x] CHK014 - Is plugin `SKILL.md` classified as untrusted content (indirect prompt injection, LLM01)? [Cobertura, Plan §Security Threat Model row LLM01] {auto}
  - Evidence: Plan states plugin SKILL.md is "NAO-confiavel sob a otica de LLM01 (prompt injection indireta)".
- [ ] CHK015 - Are requirements defined for the activation-time behavior when an activated plugin's skills attempt out-of-scope actions (e.g., write outside project, network)? [Cobertura, Gap, Plan §Security Threat Model] {auto}
  - Gap: The trust model accepts third-party execution, but no requirement constrains or documents the runtime blast-radius of an activated plugin's skills (the existing 00c bash-guard/path-guard apply to orchestrator scripts, not necessarily to plugin-supplied skills). Whether plugin skills inherit the same guards is unspecified. Candidate for /clarify.

## Offline & Network Guarantees

- [x] CHK016 - Is the "network only on explicit plugin-add" requirement specified? [Cobertura, Spec §FR-006, §FR-018] {auto}
  - Evidence: FR-006 — network initiated only on explicit user `plugin-add`, never background/automatic; FR-018 — no lifecycle op makes network requests other than the explicit plugin-add download.
- [x] CHK017 - Are offline guarantees for list/remove/activation specified and measurable? [Mensurabilidade, Spec §FR-018, §SC-006] {auto}
  - Evidence: FR-018 — `plugin-list`/activation work fully offline; SC-006 — user runs `plugin-list` without network and sees correct status, no network call made.
- [x] CHK018 - Is the no-telemetry / zero-remote-collection requirement explicit (Constitution IV)? [Cobertura, Spec §FR-006, Plan §Constitution Check IV] {auto}
  - Evidence: FR-006 cites Constitution Principle IV (zero remote collection); plan Constitution Check IV PASS — "downloads from name-derived URL, NOT from author endpoint nor telemetry".

## Audit & Logging

- [x] CHK019 - Are integrity-failure outcomes (abort + non-zero exit + clear error) specified for each failure mode? [Clareza, Spec §FR-004/FR-012/FR-015, §US1-AS2/AS4] {auto}
  - Evidence: checksum mismatch (FR-004), plugin-not-found on remove (FR-012), not-installed on activate (FR-015) each specify clear error + non-zero exit.
- [ ] CHK020 - Are requirements defined for logging/recording integrity events (install verified, tampered detected) for later audit? [Cobertura, Gap, Spec §FR-016] {auto}
  - Gap: FR-016 records `execution.llm_plugin` in state.json for activation auditability, but there is no requirement to log/record install-time verification results or `tampered` detections beyond the on-demand `plugin-list` status. No persistent integrity audit trail is required. Candidate for /clarify (is this in-scope for MVP?).

## Open Risk Decisions (product/security owner)

- [ ] CHK021 - Is the accepted residual-risk posture (3 HIGH findings accepted: TOFU, self-signed manifest, no sandbox) acceptable for the first public release of a plugin system, or should any mitigation (detached signature / version pinning) be required before GA? [Risco, Plan §Security Threat Model, dec-018] {humano}
  - Note: dec-018 already records operator approval for the MVP pipeline to proceed; this item re-surfaces it as a release-gate decision (MVP-internal vs public-GA may warrant a different bar).
- [ ] CHK022 - Is the absence of a runtime sandbox for plugin skills an acceptable permanent stance, or a documented "MVP-only, revisit" stance with a tracked follow-up? [Risco, Plan §Security Threat Model row ASI04] {humano}
  - Note: Constitution II (POSIX-sh, zero-dep) currently precludes a sandbox; product owner should decide whether to record this as permanent vs future-revisit.

## Notes

- `{auto}` items are resolved by the agent (`[x]` with cited evidence, or marked `[Gap]`/`[Ambiguity]`/`[Conflict]`).
- `{humano}` items remain `[ ]` awaiting product/security-owner decision.
- Open gaps (CHK009, CHK015, CHK020) and risk decisions (CHK021, CHK022) have follow-up destinations in the consolidated gap report.
- The 3 accepted-residual HIGH risks are NOT re-litigated here — dec-018 already approved them; CHK021/CHK022 only surface them as release-gate / permanence decisions.
