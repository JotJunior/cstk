# Modern Cryptography & Secrets — Deep Reference

> Companion to [`../SKILL.md`](../SKILL.md). Covers **post-quantum cryptography (PQC)** migration, **crypto agility**, and **2026 secrets management** patterns.

Two structural shifts since the SKILL.md base coverage:

1. **NIST finalized PQC algorithms in Aug-2024** (FIPS 203/204/205). The "harvest now, decrypt later" risk window for current public-key crypto is closing. Any system that stores ciphertexts that must remain confidential past ~2030 should start migration **now**.
2. **Static secrets are legacy.** 2026 best practice is dynamic, short-lived, automatically rotated, and never persisted into images / repos / env files.

---

## Post-Quantum Cryptography (PQC)

### The threat model

A sufficiently large quantum computer would break:
- **RSA, ECDSA, ECDH, DH** — all public-key crypto in use today.

Symmetric crypto (AES, SHA-2/3) is **not** broken — Grover's algorithm halves effective key length, so AES-128 → AES-64 effective. Practical mitigation: use AES-256 everywhere, no algorithm swap needed.

**Harvest now, decrypt later (HNDL):** an attacker captures encrypted traffic today, stores it, decrypts in 10-15 years when quantum is ready. Anything sensitive past 2035 should already be PQ-protected in transit.

### NIST PQC standards (Aug-2024)

| FIPS | Algorithm | Type | Use |
|------|-----------|------|-----|
| **203** | ML-KEM (CRYSTALS-Kyber) | Key encapsulation | Replaces RSA/ECDH for key exchange |
| **204** | ML-DSA (CRYSTALS-Dilithium) | Digital signature | Replaces RSA/ECDSA for general signing |
| **205** | SLH-DSA (SPHINCS+) | Digital signature | Hash-based; backup for ML-DSA failure |
| **206** (draft) | FN-DSA (FALCON) | Digital signature | Smaller sigs than ML-DSA where size matters |

### Timeline

- **2024-08-13:** FIPS 203/204/205 published.
- **2025-12:** CISA/NSA published inventory and migration guidance lists.
- **2030-01-02:** TLS 1.3 + PQC hybrid **mandatory** for US-government national-security systems.
- **~2030-2035:** NIST IR 8547 — deprecation of vulnerable algorithms (RSA, ECDSA, etc.) phased.

### What to do today

**1. Inventory.** Find every place using RSA, ECDSA, ECDH, DH:
- TLS certs (most CA chains still RSA / ECDSA).
- JWT signing (RS256, ES256).
- Code-signing certs, package signing.
- Token sender-constraining (DPoP keys).
- E2E protocols (Signal-like).
- SSH keys, GPG keys.

**2. Adopt crypto agility.** Code should accept algorithm identifiers and not hard-code RSA / ECDSA.

```python
# UNSAFE — hard-coded
def sign(data, private_key):
    return rsa.sign(data, private_key, "SHA-256")

# SAFE — algorithm passed through
def sign(data, key, alg):
    if alg == "RS256": return rsa.sign(data, key, "SHA-256")
    if alg == "ES256": return ecdsa.sign(data, key, "SHA-256")
    if alg == "ML-DSA-65": return ml_dsa.sign(data, key)
    raise ValueError(f"Unsupported algorithm: {alg}")
```

**3. Hybrid TLS.** Modern TLS stacks support **hybrid key exchange** — combine ECDHE + ML-KEM so a quantum break of one doesn't break the session. OpenSSL 3.5+, BoringSSL, AWS-LC, Cloudflare's stack support hybrid X25519+ML-KEM-768 as of 2025. Enable when the toolchain supports it; cost is ~1-2KB extra in ClientHello.

**4. Prefer larger symmetric keys.** AES-256-GCM > AES-128-GCM. SHA-384 / SHA-512 over SHA-256 for new design where size permits.

**5. Don't roll your own PQC.** Use vetted libraries (liboqs, BoringSSL, AWS-LC). Reference implementations from NIST submissions are not constant-time and not safe for production.

### What NOT to do

- Don't migrate immediately to PQC-only — the algorithms are new, implementation bugs are likely. Hybrid (classical + PQC) is the right transitional posture.
- Don't ignore the problem because "quantum is far away." Long-lived secrets (signing CAs, root keys, encrypted backups) are at risk today via HNDL.
- Don't trust marketing claims of "quantum-safe" without checking the actual algorithm.

Source: [NIST PQC project](https://csrc.nist.gov/projects/post-quantum-cryptography) · [NIST IR 8547 (draft)](https://csrc.nist.gov/pubs/ir/8547/ipd) · [CISA PQC guidance](https://www.cisa.gov/quantum)

---

## Secrets Management 2026

### The problem with static secrets

A static secret (long-lived API key in `.env`, in K8s `Secret`, in a CI/CD store) has:
- Unbounded blast radius if leaked.
- No automatic rotation.
- Often shared across environments and services.
- Detected as "the secret" by every static scanner, increasing exposure surface.

### Modern patterns

| Pattern | Description | When to use |
|---------|-------------|-------------|
| **Workload Identity / OIDC federation** | Workload mints short-lived cloud tokens via OIDC. Zero static cloud keys. | All cloud workloads (AWS / GCP / Azure / K8s) |
| **Dynamic database credentials** | Vault issues per-session DB user/pass, expiring in minutes. | Any service-to-DB connection |
| **External Secrets Operator (ESO)** | K8s operator that syncs from vault → K8s Secret. Rotation centralized. | K8s deployments |
| **SOPS / Sealed Secrets** | Encrypt secrets at rest in git (KMS-backed). | GitOps repositories |
| **AWS Secrets Manager / GCP Secret Manager / Vault** | Centralized secret store with audit, rotation, fine-grained access. | All secret types |

### Workload Identity (the most impactful shift)

GitHub Actions → AWS:
```yaml
# No AWS_ACCESS_KEY_ID stored as GitHub secret
permissions:
  id-token: write   # mints OIDC token
  contents: read
jobs:
  deploy:
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123:role/deploy-role
          aws-region: us-east-1
          # GH Actions presents OIDC token, AWS trusts it,
          # mints temporary STS creds (1 hour)
```

Trust policy on the AWS role pins the GitHub org/repo/branch — only that specific workflow can assume the role.

### Secret scanning in CI

Pre-commit hooks + push-protection + scheduled scans:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
```

GitHub: enable **Secret Scanning** + **Push Protection** on all repos. They block known-token patterns at `git push` time, before the secret hits the remote.

### Rotation strategy

- **Static secrets:** rotate on a schedule (30/60/90 days) AND on any suspected exposure event.
- **Dynamic secrets:** auto-rotate, often per-session. No human action needed.
- **Service accounts:** prefer Workload Identity; if static keys necessary, rotate via automation.
- **Recovery codes / break-glass:** stored offline (HSM, paper in a safe), used only with audit trail.

### What to check in a code review

- [ ] No secrets in repo (`git log -p | grep -iE 'api_key|secret|token'`)
- [ ] No secrets in container images (`docker history <image>`, scan layers)
- [ ] No secrets in logs (structured log fields filtered)
- [ ] No secrets in error messages / stack traces
- [ ] No secrets in environment of child processes that don't need them
- [ ] Secrets fetched at runtime from vault, not at build time
- [ ] Service uses workload identity where the platform supports it
- [ ] Secret-rotation procedure documented and tested

---

## Crypto Agility — Design Principles

Even setting aside PQC, building crypto-agile systems pays back when:
- A library has a CVE (heartbleed, ROCA, etc.) and you need to swap algorithms fast.
- A regulator deprecates an algorithm (SHA-1, RSA-1024).
- Your threat model changes (new adversary tier).

### Patterns

**1. Algorithm identifier on the data.** Encrypted blobs / signed tokens carry an explicit alg ID. Decoder dispatches by ID; doesn't assume.

```
ciphertext = alg_id || iv || ct || tag
                ^- "AES-256-GCM", "ChaCha20-Poly1305", etc.
```

**2. Versioned key sets.** Keys have IDs and rotation. Verify against any active key; sign with the current one.

**3. No hard-coded constants.** `KEY_SIZE`, `HASH`, `CIPHER` come from config, not literals.

**4. Test the "swap" path.** CI test that exercises rotation: encrypt with v1, swap to v2, decrypt v1 still works during transition, finally retire v1.

**5. Crypto library abstraction.** Wrap operations in your own thin interface so you can swap the implementation. Don't leak `cryptography.hazmat` types through your codebase.

---

## Sources

- [NIST Post-Quantum Cryptography](https://csrc.nist.gov/projects/post-quantum-cryptography)
- [NIST IR 8547 (initial public draft) — Transition to PQC](https://csrc.nist.gov/pubs/ir/8547/ipd)
- [FIPS 203 — ML-KEM](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.203.pdf)
- [FIPS 204 — ML-DSA](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.204.pdf)
- [FIPS 205 — SLH-DSA](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.205.pdf)
- [CISA PQC guidance](https://www.cisa.gov/quantum)
- [External Secrets Operator](https://external-secrets.io/)
- [GitHub OIDC for cloud providers](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments)
- [HashiCorp Vault — Dynamic Secrets](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [Sigstore / cosign](https://www.sigstore.dev/)
