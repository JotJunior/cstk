# API & CI/CD Security — Deep Reference

> Companion to [`../SKILL.md`](../SKILL.md). Covers the **OWASP API Security Top 10:2023** (still current in 2026) and **OWASP Top 10 CI/CD Security Risks** (CICD-SEC).

The OWASP Top 10:2025 (general) is broad. API and CI/CD have their **own** Top 10 lists because their attack surfaces are different enough to warrant dedicated guidance.

---

## OWASP API Security Top 10:2023

Released 2023, **still the current version** as of May 2026. No 2025/2026 successor has been published.

| ID | Risk | One-line summary |
|----|------|------------------|
| API1 | Broken Object Level Authorization (BOLA) | User accesses another user's resource by ID swap |
| API2 | Broken Authentication | Weak auth on tokens, JWTs, sessions, API keys |
| API3 | Broken Object Property Level Authorization (BOPLA) | User reads/writes a field they shouldn't (mass assignment + excessive data exposure) |
| API4 | Unrestricted Resource Consumption | No rate / size / cost limits → DoS or bill shock |
| API5 | Broken Function Level Authorization (BFLA) | User calls an admin endpoint via guessable URL |
| API6 | Unrestricted Access to Sensitive Business Flows | Bot abuses checkout, signup, password reset at scale |
| API7 | Server-Side Request Forgery (SSRF) | API fetches an attacker-controlled URL on the server side |
| API8 | Security Misconfiguration | Same as Top 10 A02, applied to API stacks |
| API9 | Improper Inventory Management | Forgotten / old / staging endpoints exposed |
| API10 | Unsafe Consumption of APIs | Trusting third-party API responses without validation |

### API1 — BOLA (most exploited API vuln)

```python
# UNSAFE — accepts user-supplied ID without ownership check
@router.get("/orders/{order_id}")
def get_order(order_id: int, user=Depends(get_current_user)):
    return db.orders.find_by_id(order_id)

# SAFE — scoped by owner
@router.get("/orders/{order_id}")
def get_order(order_id: int, user=Depends(get_current_user)):
    order = db.orders.find_by_id_and_owner(order_id, user.id)
    if not order:
        raise HTTPException(404)
    return order
```

- Never trust IDs from the URL/body for authorization.
- Use opaque IDs (UUIDs) instead of sequential integers — defense in depth, not authorization.
- For nested resources (`/orgs/{org_id}/projects/{project_id}`), verify the chain: user → org → project.

### API3 — BOPLA (mass assignment + excessive exposure)

Two failure modes:

**Excessive data exposure** (read side):
```python
# UNSAFE — returns the whole row, including password_hash, is_admin
return {"user": user.__dict__}

# SAFE — explicit allowlist
return {"user": {"id": user.id, "name": user.name, "email": user.email}}
```

**Mass assignment** (write side):
```python
# UNSAFE — user can send {"is_admin": true} and it sticks
user.update(request.json())

# SAFE — allowlist permitted fields
allowed = {"name", "email"}
updates = {k: v for k, v in request.json().items() if k in allowed}
user.update(updates)
```

Use Pydantic / Zod / strong-typed DTOs with explicit input/output schemas.

### API4 — Unrestricted Resource Consumption

Modern impact: **bill shock** (OpenAI/cloud APIs charge per call), plus traditional DoS.

- Per-IP, per-token, per-user rate limits.
- Request size limits (body, headers, query string).
- Pagination caps (max page size, max offset depth).
- Timeouts on every outbound call.
- Cost ceilings on AI/LLM endpoints (max tokens, max images, max model size).

### API6 — Unrestricted Access to Sensitive Business Flows (NEW in 2023, still relevant)

The endpoint is technically authorized for the user, but the **flow** is being abused at scale: bots scalping concert tickets, bots reserving 10k delivery slots, bots running coupon-stacking checkout loops.

Mitigations:
- Distinguish "is this user allowed?" from "is this rate of usage normal?".
- Device fingerprinting, CAPTCHA on suspicious flows, behavioral biometrics.
- Workflow-level rate limits ("at most 1 checkout per cart per minute").
- Honeypots / canary actions to detect automation.

### API7 — SSRF

```python
# UNSAFE
@router.post("/import")
def import_url(url: str):
    return requests.get(url).text  # attacker: url=http://169.254.169.254/latest/meta-data/

# SAFE — allowlist + resolve + recheck after redirects
import ipaddress, socket
def is_safe(url):
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}: return False
    if parsed.hostname not in ALLOWED_HOSTS: return False
    ip = socket.gethostbyname(parsed.hostname)
    if ipaddress.ip_address(ip).is_private: return False
    return True
```

Block: link-local (169.254.0.0/16), loopback, private ranges, metadata services (cloud IMDS). Disable redirects or revalidate every redirect hop.

### API9 — Improper Inventory Management

Common findings:
- `/api/v1` deprecated but still live, with old vulnerabilities.
- Staging APIs (`staging-api.example.com`) reachable from internet with prod-like data.
- Internal endpoints (`/admin`, `/debug`) exposed via misconfigured gateway.

Maintain an **API inventory**: every endpoint, its owner, its environment, its auth requirements, its data classification. Treat orphaned endpoints as security incidents.

### API10 — Unsafe Consumption of APIs

You call a third-party API. Their response is JSON. You feed it into your DB / template / shell. The third party gets compromised (or was malicious from day one) — now you have RCE.

- Validate third-party responses with strict schemas.
- Escape on output, not on input.
- Treat third-party APIs like user input.
- Pin the third-party host (cert pinning, IP allowlist) where reasonable.

---

## OWASP Top 10 CI/CD Security Risks (CICD-SEC)

Published 2022, still authoritative in 2026. Complements supply-chain coverage in OWASP Top 10:2025 A03 with **operational** detail.

| ID | Risk | One-line summary |
|----|------|------------------|
| CICD-SEC-1 | Insufficient Flow Control Mechanisms | No approvals, no review on critical actions |
| CICD-SEC-2 | Inadequate Identity and Access Management | Stale identities, over-permissive service accounts |
| CICD-SEC-3 | Dependency Chain Abuse | Typosquatting, dependency confusion, namespace hijack |
| CICD-SEC-4 | Poisoned Pipeline Execution (PPE) | Attacker injects code that runs in your pipeline |
| CICD-SEC-5 | Insufficient PBAC (Pipeline-Based Access Controls) | Pipeline can do more than its task should allow |
| CICD-SEC-6 | Insufficient Credential Hygiene | Long-lived secrets, secrets in logs / env / images |
| CICD-SEC-7 | Insecure System Configuration | CI runners, registries, artifact stores misconfigured |
| CICD-SEC-8 | Ungoverned Usage of 3rd Party Services | Random GitHub Actions / Marketplace integrations with broad scopes |
| CICD-SEC-9 | Improper Artifact Integrity Validation | Built artifacts not signed / not verified at deploy |
| CICD-SEC-10 | Insufficient Logging and Visibility | Can't reconstruct what the pipeline did when it broke |

### CICD-SEC-3 — Dependency Chain Abuse (depth)

Three sub-attacks:
- **Typosquatting:** `reqeusts` (typo) instead of `requests` — name lookup grabs the wrong package.
- **Dependency confusion:** internal package name `acme-utils` also published to public registry — public takes precedence in some resolver configs.
- **Namespace hijack:** maintainer abandoned, attacker takes over via expired email.

Mitigations:
- Lock files committed (`package-lock.json`, `pnpm-lock.yaml`, `Pipfile.lock`, `go.sum`).
- Verify integrity hashes on install.
- Private registry as **primary** index for internal packages; fall back to public only for explicit allowlisted names.
- SBOM generation (CycloneDX or SPDX) on every build.
- Automated dependency review (Dependabot, Renovate, Snyk).

### CICD-SEC-4 — Poisoned Pipeline Execution (PPE)

Three forms:

**Direct PPE (D-PPE):** Attacker modifies pipeline config in the repo (e.g., `.github/workflows/`). PR-trigger pipelines that run with secrets on `pull_request_target` are the classic case.

**Indirect PPE (I-PPE):** Attacker modifies files that the pipeline **reads as code** — `package.json` install scripts, `Makefile` targets, `setup.py` — and the pipeline executes them.

**Public PPE (P-PPE):** Forked-PR triggers expose secrets to forks.

```yaml
# UNSAFE — runs untrusted PR code with prod secrets
on:
  pull_request_target:
    types: [opened, synchronize]
jobs:
  ci:
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}  # fetches attacker code
      - run: npm install   # postinstall script runs with secrets
        env:
          DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}

# SAFER — separate untrusted and trusted stages
on: pull_request   # no secrets exposed
jobs:
  ci:
    steps:
      - uses: actions/checkout@v4
      - run: npm install --ignore-scripts
      - run: npm test
```

Mitigations:
- Prefer `pull_request` over `pull_request_target` unless you fully understand the risk.
- Disable install scripts in PR pipelines.
- Use two-stage builds: untrusted PR runs without secrets; deploy stage only after merge to trusted branch.
- Branch protection on the workflow files themselves.

### CICD-SEC-6 — Credential Hygiene (modern practice)

Static long-lived secrets are the legacy pattern. 2026 best practices:

| Pattern | Description |
|---------|-------------|
| **OIDC federation** | Pipeline mints short-lived cloud tokens via OIDC (GitHub Actions ↔ AWS / GCP / Azure). No static cloud keys. |
| **Workload Identity** | Same idea for K8s workloads — pod gets a token bound to its service account. |
| **External Secrets Operator (ESO)** | K8s operator that syncs secrets from vault → ephemeral K8s `Secret`. Rotation handled centrally. |
| **Dynamic database creds** | Vault issues per-session DB creds, expiring in minutes. |
| **Sealed Secrets / SOPS** | If you must commit secrets (GitOps), encrypt them at rest with KMS-backed keys. |

Detection in CI:
- `gitleaks` / `trufflehog` / `detect-secrets` in pre-commit and on push.
- GitHub Secret Scanning + push protection.
- Periodic scan of artifact registry images for embedded secrets.

### CICD-SEC-9 — Artifact Integrity

- **Sigstore / cosign** signs container images and arbitrary artifacts.
- **SLSA** (Supply-chain Levels for Software Artifacts) provides attestation levels (SLSA 1-4).
- Verify signatures at **deploy** time, not just at build time.
- Provenance attestations (in-toto / SLSA provenance) record who built what and how.

```bash
# Sign an image at build time
cosign sign --yes ghcr.io/acme/api:1.2.3

# Verify at deploy time
cosign verify ghcr.io/acme/api:1.2.3 \
  --certificate-identity-regexp 'https://github.com/acme/.*' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

---

## Combined API + CI/CD Review Checklist

### API endpoints
- [ ] BOLA: every resource access scoped by owner / org / tenant
- [ ] BFLA: admin routes guarded by role check, not just by URL secrecy
- [ ] BOPLA: input DTOs allowlist fields; output DTOs allowlist fields
- [ ] Rate limits per IP, per user, per token
- [ ] Pagination caps (max page size, max offset)
- [ ] Outbound HTTP: SSRF guard (allowlist + private IP block + redirect rechecks)
- [ ] Third-party responses validated with schema
- [ ] API inventory: every live endpoint accounted for
- [ ] Deprecated versions removed, not just hidden

### CI/CD pipelines
- [ ] Workflow files protected by branch rules + CODEOWNERS
- [ ] PR-trigger pipelines do not have access to production secrets
- [ ] OIDC federation in use; no long-lived cloud keys in secrets store
- [ ] Lock files committed; integrity hashes verified
- [ ] SBOM generated on every build
- [ ] Container images signed (cosign); verified at deploy
- [ ] Pre-commit + push protection scan for secrets
- [ ] Third-party Actions / Tasks pinned to commit SHA, not floating tags
- [ ] Audit logs retained for build / deploy events

---

## Sources

- [OWASP API Security Top 10:2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [OWASP Top 10 CI/CD Security Risks](https://owasp.org/www-project-top-10-ci-cd-security-risks/)
- [OWASP CI/CD Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/CI_CD_Security_Cheat_Sheet.html)
- [SLSA framework](https://slsa.dev/)
- [Sigstore / cosign](https://www.sigstore.dev/)
- [External Secrets Operator](https://external-secrets.io/)
