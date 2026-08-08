**English** · [Português (pt-BR)](./THIRD-PARTY-NOTICES.pt-BR.md)

# Third-Party Notices & Acknowledgments

`cstk` is distributed under the MIT license (see [LICENSE](./LICENSE)). This file
acknowledges third-party works that inspired or were partially adapted in this
toolkit, and reproduces the required license notices.

The grouping below is by **level of obligation**: mandatory (the license requires
preserving the notice), courtesy (conceptual inspiration, no legal requirement)
and factual references (public standards cited, with no reproduction of protected
text).

---

## 1. Mandatory — adapted code/templates

### GitHub Spec Kit

Parts of this toolkit's Spec-Driven Development pipeline — the vocabulary of steps
(`constitution` → `specify` → `clarify` → `plan` → `tasks` → `analyze`) and, in
particular, the **constitution template** in
`plugins/cstk/skills/constitution/templates/constitution.md` (structure
`## Core Principles` / `### [PRINCIPLE_N_NAME]`, footer
`**Version** | **Ratified** | **Last Amended**`, `[NEEDS CLARIFICATION]` markers
and "Sync Impact Report") — are **adapted** from the **GitHub Spec Kit** project.

- Project: <https://github.com/github/spec-kit>
- License: MIT

```
MIT License

Copyright GitHub, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

> Reproduced verbatim from the upstream `LICENSE`
> (<https://github.com/github/spec-kit/blob/main/LICENSE>), which declares no year.

---

## 2. Courtesy — conceptual inspiration (no legal requirement)

These projects influenced the **design** of skills/conventions, with no
reproduction of code or text. The acknowledgment is made in good faith, not out of
a license obligation.

- **obra/superpowers** (Jesse Vincent) — <https://github.com/obra/superpowers> —
  inspired `description`/anti-shortcut patterns and skill structure. MIT license.
- **Anthropic Claude Code** — scaffolding conventions for skills, commands and
  agents (`SKILL.md` format, frontmatter, triggers). Public documentation.

---

## 3. Factual references — public standards cited

The `owasp-security` skill **does not reproduce protected text** from these
standards: it uses category names and rankings (facts) with its own prose and code
examples, and already cites each source in the `## Sources` sections of the
reference files. Listed here for transparency:

- OWASP Top 10:2025, API Security Top 10:2023, CI/CD Top 10, ASVS 5.0, Top 10 for
  LLM Applications 2025, Top 10 for Agentic Applications 2026, Mobile/Kubernetes/
  Docker Top 10 — © OWASP Foundation (original content under CC BY-SA; here only
  factual taxonomies are referenced).
- MITRE CWE Top 25:2025 · NIST SP 800-63B-4, FIPS 203/204/205, IR 8547 ·
  IETF OAuth 2.1, RFC 9449/9126/9101 · W3C WebAuthn L3 · OpenID FAPI 2.0 ·
  Cloud Security Alliance MAESTRO · EU AI Act.

---

*Found a missing or incorrect attribution? Open an issue — we'll fix it.*
