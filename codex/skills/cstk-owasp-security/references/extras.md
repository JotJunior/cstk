# Extras — CWE Top 25, Mobile, Containers, Regulatory

> Companion to [`../SKILL.md`](../SKILL.md). Short-form references for **CWE Top 25:2025**, **OWASP Mobile Top 10:2024**, **Kubernetes/Docker Top 10**, and **regulatory mappings** (EU AI Act).

These are not deep-dive sections — each is one page of "what changed, where to look, how it maps to OWASP Top 10".

---

## CWE Top 25:2025

CISA / MITRE publish the CWE Top 25 annually. The **2025 edition** was released Dec-2025, based on analysis of ~32k CVEs over 24 months.

### 2025 ranking

| Rank | CWE | Name | Maps to OWASP Top 10:2025 |
|------|-----|------|---------------------------|
| 1 | CWE-79 | Cross-site Scripting | A05 Injection |
| 2 | CWE-787 | Out-of-bounds Write | (memory safety — language-specific) |
| 3 | CWE-89 | SQL Injection | A05 Injection |
| 4 | CWE-352 | Cross-Site Request Forgery | A01 Broken Access Control |
| 5 | CWE-862 | Missing Authorization | A01 Broken Access Control |
| 6 | CWE-22 | Path Traversal | A01 Broken Access Control |
| 7 | CWE-78 | OS Command Injection | A05 Injection |
| 8 | CWE-416 | Use After Free | (memory safety) |
| 9 | CWE-434 | Unrestricted Upload of File with Dangerous Type | A05 Injection / A04 Insecure Design |
| 10 | CWE-94 | Code Injection | A05 Injection |
| 11 | CWE-20 | Improper Input Validation | A05 / A06 |
| 12 | CWE-77 | Command Injection | A05 |
| 13 | CWE-287 | Improper Authentication | A07 Auth Failures |
| 14 | CWE-269 | Improper Privilege Management | A01 |
| 15 | CWE-502 | Deserialization of Untrusted Data | A08 Integrity |
| 16 | CWE-200 | Exposure of Sensitive Information | A02 / A04 |
| 17 | CWE-863 | Incorrect Authorization | A01 |
| 18 | CWE-918 | Server-Side Request Forgery | A10 (was A10:2021) |
| 19 | CWE-119 | Improper Restriction of Operations within Bounds of Memory | (memory safety) |
| 20 | CWE-476 | NULL Pointer Dereference | A10 Exception Handling |
| 21 | CWE-798 | Use of Hard-coded Credentials | A04 Cryptographic / A07 |
| 22 | CWE-190 | Integer Overflow | A06 Insecure Design / language |
| 23 | CWE-400 | Uncontrolled Resource Consumption | A04 Crypto / A06 / API4 |
| 24 | CWE-306 | Missing Authentication for Critical Function | A07 |
| 25 | CWE-862 | (duplicate placeholder — confirm against source) | — |

### Notable 2025 changes vs 2024

- **CWE-862 Missing Authorization** moved up 5 positions — operational reality: authz is harder to test than authn.
- **CWE-79 XSS** retook #1 from CWE-787 (memory safety) after several years.
- **CWE-918 SSRF** entered top 20 again — driven by cloud-metadata-service abuse cases.
- **CWE-352 CSRF** rose despite SameSite=Lax defaults — many APIs accept JSON without SameSite enforcement.

### How to use this list

- **Prioritize testing** for top-10 CWEs in your stack (different languages emphasize different CWEs — memory safety dominates in C/C++, injection/authz in web).
- **Tune SAST rules** to surface these specifically.
- **Train developers** with examples from these CWE entries — each has a CVE list with real exploits.

Source: [CWE Top 25:2025](https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html) · [CISA announcement](https://www.cisa.gov/news-events/alerts/2025/12/11/2025-cwe-top-25-most-dangerous-software-weaknesses)

---

## OWASP Mobile Top 10:2024

The Mobile Top 10 was refreshed in 2024 (previous: 2016). Use alongside **MASVS 2.1** (Mobile Application Security Verification Standard) and **MASTG** (Mobile Application Security Testing Guide).

| ID | Risk |
|----|------|
| M1 | **Improper Credential Usage** — hardcoded creds, weak storage, exposed in logs |
| M2 | **Inadequate Supply Chain Security** — compromised SDKs, vulnerable libs |
| M3 | **Insecure Authentication/Authorization** — weak biometrics, missing server-side checks |
| M4 | **Insufficient Input/Output Validation** — same patterns as web, mobile-specific surface |
| M5 | **Insecure Communication** — missing cert pinning, fallback to HTTP, weak TLS |
| M6 | **Inadequate Privacy Controls** — PII leakage, excessive permissions, tracking |
| M7 | **Insufficient Binary Protections** — no obfuscation, no tamper detection, easy reverse-engineering |
| M8 | **Security Misconfiguration** — debug flags, exported components, intent filters |
| M9 | **Insecure Data Storage** — plaintext in SharedPreferences / NSUserDefaults |
| M10 | **Insufficient Cryptography** — hard-coded keys, weak algos, ECB mode |

### Platform-specific quick wins

**iOS:**
- Keychain for secrets (with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- `NSURLSession` with App Transport Security (ATS) strict
- Disable third-party keyboards on sensitive fields
- `NSFileProtectionComplete` for sensitive files

**Android:**
- EncryptedSharedPreferences / EncryptedFile (androidx.security:security-crypto)
- Network Security Config — pin certs, disable cleartext
- `android:allowBackup="false"` for apps with secrets
- StrictMode in debug builds; Hardware-backed Keystore for keys

### Cert pinning

```kotlin
// Android — OkHttp pinning
val pinner = CertificatePinner.Builder()
    .add("api.acme.com", "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
    .add("api.acme.com", "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=")  // backup pin
    .build()
val client = OkHttpClient.Builder().certificatePinner(pinner).build()
```

Always include at least one **backup pin** so cert rotation doesn't brick the app.

Source: [OWASP Mobile Top 10:2024](https://owasp.org/www-project-mobile-top-10/2023-risks/) · [MASVS](https://mas.owasp.org/MASVS/) · [MASTG](https://mas.owasp.org/MASTG/)

---

## OWASP Kubernetes Top 10 & Docker Top 10

Stable references for container / K8s misconfiguration. Use as A02 Security Misconfiguration deep-dive in containerized stacks.

### Kubernetes Top 10 (selected)

| ID | Risk |
|----|------|
| K01 | Insecure Workload Configurations |
| K02 | Supply Chain Vulnerabilities |
| K03 | Overly Permissive RBAC Configurations |
| K04 | Lack of Centralized Policy Enforcement |
| K05 | Inadequate Logging and Monitoring |
| K06 | Broken Authentication Mechanisms |
| K07 | Missing Network Segmentation Controls |
| K08 | Secrets Management Failures |
| K09 | Misconfigured Cluster Components |
| K10 | Outdated and Vulnerable Kubernetes Components |

### Quick wins for K8s hardening

```yaml
# Pod security baseline
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: api
      image: ghcr.io/acme/api@sha256:...   # digest pin, not tag
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      resources:
        limits: { cpu: "500m", memory: "512Mi" }
        requests: { cpu: "100m", memory: "128Mi" }
```

- Use **Pod Security Standards** (`restricted` profile) via labels or admission policy.
- Enforce **NetworkPolicy** — default deny ingress/egress, explicit allow.
- Use **OPA / Kyverno / Validating Admission Policies** for cluster-wide policy.
- Run **Falco** for runtime security monitoring.

### Docker Top 10 (selected)

- D01: Secure User Mapping (don't run as root)
- D02: Patch Management Strategy
- D03: Network Segmentation and Firewalling
- D04: Secure Defaults and Hardening
- D05: Maintain Security Contexts
- D06: Protect Secrets
- D07: Resource Protection
- D08: Container Image Integrity and Origin
- D09: Follow Immutable Paradigm
- D10: Logging

Build practices:
- Multi-stage builds (final image has no toolchain).
- Distroless or scratch base where possible.
- Sign images (cosign).
- Scan images in CI (Trivy, Grype, Snyk).

Source: [Kubernetes Top 10](https://owasp.org/www-project-kubernetes-top-ten/) · [Docker Top 10](https://owasp.org/www-project-docker-top-10/) · [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

---

## EU AI Act — Compliance Mapping

The EU AI Act entered force phased — general-purpose AI (GPAI) obligations became applicable **2-Aug-2025**. High-risk AI system obligations follow in 2026-2027. Fines: up to **€35M or 7% of global turnover**.

### Risk tiers

| Tier | Examples | Obligations |
|------|----------|-------------|
| **Unacceptable** | Social scoring, manipulative AI, mass biometric surveillance | **Banned** |
| **High-risk** | CV screening, credit scoring, medical devices, education | Risk mgmt, data governance, technical docs, transparency, oversight, accuracy/robustness, registration |
| **Limited risk** | Chatbots, deepfakes | Transparency (must tell user they're talking to AI) |
| **Minimal risk** | Spam filters, video games | No additional rules |
| **GPAI** | Foundation models | Documentation, training-data summaries, copyright compliance; systemic-risk models add cyber/safety eval |

### Security overlap with OWASP

The Act's "accuracy, robustness, cybersecurity" requirement for high-risk systems aligns with:
- **OWASP Top 10 for LLM:2025** — applies to GPAI providers and deployers.
- **OWASP Top 10 for Agentic:2026** — particularly relevant for high-risk autonomous systems.
- **Standard AppSec controls** — authentication, authz, logging, supply chain — apply to any AI-containing product.

### Practical posture for security teams

- Maintain a **model inventory** (what model, what version, what training data summary, what risk tier).
- Implement **logging requirements** that align with the Act's "automatic logging" obligation for high-risk systems.
- Build **transparency hooks** — UI labels for AI content (also aligns with OWASP ASI09).
- Document **risk management** — most overlaps with threat modeling work the security team already does.
- Track **harmonized standards** (CEN/CENELEC JTC 21) as they emerge; they may grant presumption of conformity.

Source: [EU AI Act (Regulation 2024/1689)](https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai) · [AI Office](https://digital-strategy.ec.europa.eu/en/policies/ai-office)

---

## Sources

- [CWE Top 25:2025](https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html)
- [CISA — 2025 CWE Top 25 announcement](https://www.cisa.gov/news-events/alerts/2025/12/11/2025-cwe-top-25-most-dangerous-software-weaknesses)
- [OWASP Mobile Top 10:2024](https://owasp.org/www-project-mobile-top-10/)
- [OWASP MASVS](https://mas.owasp.org/MASVS/)
- [OWASP MASTG](https://mas.owasp.org/MASTG/)
- [OWASP Kubernetes Top 10](https://owasp.org/www-project-kubernetes-top-ten/)
- [OWASP Docker Top 10](https://owasp.org/www-project-docker-top-10/)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [EU AI Act — Regulatory framework](https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai)
- [OWASP Infrastructure as Code Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Infrastructure_as_Code_Security_Cheat_Sheet.html)
