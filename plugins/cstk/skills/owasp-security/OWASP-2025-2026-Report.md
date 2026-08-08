# OWASP Security Best Practices 2025-2026

A comprehensive guide to the latest OWASP security standards for developers building secure applications.

> Operational quick-reference lives in [`SKILL.md`](./SKILL.md); deep topical references live in [`references/`](./references/). This file is the historical reference document covering all major OWASP lists side-by-side.

---

## Table of Contents

1. [OWASP Top 10:2025](#owasp-top-102025)
2. [OWASP API Security Top 10:2023](#owasp-api-security-top-102023)
3. [OWASP Top 10 CI/CD Security Risks](#owasp-top-10-cicd-security-risks)
4. [OWASP ASVS 5.0.0](#owasp-asvs-500)
5. [OWASP Top 10 for LLM Applications 2025](#owasp-top-10-for-llm-applications-2025)
6. [OWASP Top 10 for Agentic Applications 2026](#owasp-top-10-for-agentic-applications-2026)
7. [NIST SP 800-63B-4 Highlights](#nist-sp-800-63b-4-highlights)
8. [Post-Quantum Cryptography](#post-quantum-cryptography)
9. [CWE Top 25:2025](#cwe-top-252025)
10. [Key Security Principles](#key-security-principles)
11. [Sources and References](#sources-and-references)

---

## OWASP Top 10:2025

Released at OWASP Global AppSec EU Barcelona 2025, based on analysis of 175,000+ CVEs and 2.8 million applications tested.

### Summary Table

| Rank | Category | Change from 2021 |
|------|----------|------------------|
| A01 | Broken Access Control | Unchanged #1 |
| A02 | Security Misconfiguration | Up from #5 |
| A03 | Software Supply Chain Failures | **NEW** (expanded from A06:2021) |
| A04 | Cryptographic Failures | Down from #2 |
| A05 | Injection | Down from #3 |
| A06 | Insecure Design | Down from #4 |
| A07 | Identification and Authentication Failures | Unchanged #7 |
| A08 | Software and Data Integrity Failures | Unchanged #8 |
| A09 | Security Logging and Monitoring Failures | Unchanged #9 |
| A10 | Mishandling of Exceptional Conditions | **NEW** |

---

### A01:2025 – Broken Access Control

**Description:** Access control enforces policies that prevent users from acting outside their intended permissions. Failures lead to unauthorized data disclosure, modification, or destruction.

**Common Vulnerabilities:**
- Bypassing access control by modifying URLs, application state, or HTML pages
- Allowing primary key changes to access others' records (IDOR)
- Privilege escalation (acting as admin while logged in as user)
- Missing access control for POST, PUT, DELETE APIs
- CORS misconfiguration allowing unauthorized API access

**Prevention:**
```python
# BAD: No authorization check
@app.route('/api/user/<user_id>')
def get_user(user_id):
    return db.get_user(user_id)

# GOOD: Authorization enforced
@app.route('/api/user/<user_id>')
@login_required
def get_user(user_id):
    if current_user.id != user_id and not current_user.is_admin:
        abort(403)
    return db.get_user(user_id)
```

**Mitigation Strategies:**
1. Deny access by default (allowlist approach)
2. Implement access control once, reuse throughout application
3. Enforce record ownership instead of accepting user-supplied IDs
4. Disable directory listing and remove sensitive files from web roots
5. Log access control failures and alert on repeated attempts
6. Rate limit API access to minimize automated attack damage

---

### A02:2025 – Security Misconfiguration

**Description:** Applications are vulnerable when security hardening is missing, cloud permissions are improperly configured, unnecessary features are enabled, or default accounts remain active.

**Common Vulnerabilities:**
- Missing security hardening across the application stack
- Unnecessary features enabled (ports, services, pages, accounts)
- Default credentials unchanged
- Error handling revealing stack traces
- Outdated or vulnerable software components
- Insecure cloud storage permissions (S3 buckets public)

**Prevention:**
```yaml
# BAD: Debug mode in production
DEBUG=True
SECRET_KEY="development-key"

# GOOD: Production hardened
DEBUG=False
SECRET_KEY="${RANDOM_SECRET_FROM_VAULT}"
ALLOWED_HOSTS=["app.example.com"]
SECURE_SSL_REDIRECT=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
```

**Mitigation Strategies:**
1. Automated, repeatable hardening process across environments
2. Minimal platform without unnecessary features or frameworks
3. Regularly review and update configurations (cloud permissions, patches)
4. Segmented application architecture with secure separation
5. Send security directives (CSP, HSTS, X-Frame-Options)
6. Automated verification of configurations in all environments

---

### A03:2025 – Software Supply Chain Failures

**Description:** NEW category highlighting risks from third-party dependencies, compromised build pipelines, and insecure package management. Expanded from 2021's component vulnerabilities focus.

**Common Vulnerabilities:**
- Using components with known vulnerabilities
- Dependency confusion attacks
- Typosquatting in package registries
- Compromised CI/CD pipelines
- Unsigned or unverified packages
- Lack of software bill of materials (SBOM)

**Prevention:**
```bash
# BAD: Installing without verification
npm install some-package

# GOOD: Lock versions, verify integrity, audit
npm install some-package@1.2.3 --save-exact
npm audit
npm audit signatures
```

```json
// package-lock.json with integrity hashes
{
  "dependencies": {
    "lodash": {
      "version": "4.17.21",
      "integrity": "sha512-v2kDEe57lecT..."
    }
  }
}
```

**Mitigation Strategies:**
1. Maintain inventory of all components (SBOM)
2. Remove unused dependencies and features
3. Continuously monitor for vulnerabilities (Dependabot, Snyk)
4. Obtain components from official sources over secure links
5. Sign packages and verify signatures
6. Ensure CI/CD pipelines have proper access controls and audit logs
7. Use lock files and verify integrity hashes

---

### A04:2025 – Cryptographic Failures

**Description:** Failures related to cryptography that lead to exposure of sensitive data. Includes weak algorithms, improper key management, and missing encryption.

**Common Vulnerabilities:**
- Transmitting data in clear text (HTTP, SMTP, FTP)
- Using deprecated algorithms (MD5, SHA1, DES)
- Weak or default cryptographic keys
- Missing certificate validation
- Using encryption without authenticated modes
- Insufficient entropy for random number generation

**Prevention:**
```python
# BAD: Weak hashing
import hashlib
password_hash = hashlib.md5(password.encode()).hexdigest()

# GOOD: Modern password hashing
from argon2 import PasswordHasher
ph = PasswordHasher()
password_hash = ph.hash(password)

# BAD: ECB mode
from Crypto.Cipher import AES
cipher = AES.new(key, AES.MODE_ECB)

# GOOD: Authenticated encryption
from cryptography.fernet import Fernet
cipher = Fernet(key)
```

**Mitigation Strategies:**
1. Classify data by sensitivity; apply controls accordingly
2. Don't store sensitive data unnecessarily
3. Encrypt all data in transit (TLS 1.2+) and at rest
4. Use strong, current algorithms (AES-256-GCM, Argon2, bcrypt)
5. Encrypt with authenticated modes (GCM, CCM)
6. Generate keys randomly; store securely (HSM, vault)
7. Disable caching for sensitive responses

---

### A05:2025 – Injection

**Description:** Injection occurs when untrusted data is sent to an interpreter as part of a command or query. Includes SQL, NoSQL, OS, LDAP, and expression language injection.

**Common Vulnerabilities:**
- User input not validated, filtered, or sanitized
- Dynamic queries without parameterization
- Hostile data used in ORM search parameters
- Direct concatenation of user input in commands

**Prevention:**
```python
# BAD: SQL Injection vulnerable
query = f"SELECT * FROM users WHERE id = {user_id}"
cursor.execute(query)

# GOOD: Parameterized query
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

# BAD: Command injection
os.system(f"convert {filename} output.png")

# GOOD: Use safe APIs, avoid shell
subprocess.run(["convert", filename, "output.png"], shell=False)
```

```javascript
// BAD: NoSQL injection
db.users.find({ username: req.body.username })

// GOOD: Validate type
if (typeof req.body.username !== 'string') throw new Error();
db.users.find({ username: req.body.username })
```

**Mitigation Strategies:**
1. Use safe APIs with parameterized interfaces
2. Validate all input using allowlists
3. Escape special characters for specific interpreters
4. Use LIMIT and pagination to prevent mass disclosure
5. Implement positive server-side input validation

---

### A06:2025 – Insecure Design

**Description:** Flaws in design and architecture that cannot be fixed by perfect implementation. Represents missing or ineffective security controls at the design phase.

**Common Vulnerabilities:**
- Missing rate limiting on sensitive operations
- No account lockout for failed authentication
- Lack of tenant isolation in multi-tenant systems
- Missing fraud detection controls
- Insufficient trust boundaries

**Prevention:**
```python
# BAD: No rate limiting on password reset
@app.route('/password-reset', methods=['POST'])
def password_reset():
    send_reset_email(request.form['email'])
    return "Email sent"

# GOOD: Rate limiting and verification
from flask_limiter import Limiter
limiter = Limiter(app)

@app.route('/password-reset', methods=['POST'])
@limiter.limit("3 per hour")
def password_reset():
    email = request.form['email']
    if not is_valid_email_format(email):
        abort(400)
    # Use consistent timing to prevent enumeration
    send_reset_email_async(email)
    return "If account exists, email was sent"
```

**Mitigation Strategies:**
1. Establish secure development lifecycle with security experts
2. Create and use secure design patterns library
3. Threat modeling for authentication, access control, business logic
4. Integrate security language in user stories
5. Implement tenant isolation and resource limits
6. Limit resource consumption per user/service

---

### A07:2025 – Identification and Authentication Failures

**Description:** Confirmation of user identity, authentication, and session management is critical. Weaknesses allow attackers to compromise passwords, keys, or session tokens.

**Common Vulnerabilities:**
- Permitting weak or well-known passwords
- Using weak credential recovery (knowledge-based answers)
- Plain text or weakly hashed passwords
- Missing or ineffective MFA
- Exposing session IDs in URLs
- Not properly invalidating sessions on logout

**Prevention:**
```python
# Password strength requirements
import re
def validate_password(password):
    if len(password) < 12:
        return False
    if password in COMMON_PASSWORDS:  # Check against breach lists
        return False
    return True

# Session management
@app.route('/logout')
@login_required
def logout():
    session.clear()  # Clear server-side session
    response = redirect('/')
    response.delete_cookie('session')
    return response
```

**Mitigation Strategies:**
1. Implement MFA to prevent automated attacks
2. Avoid shipping with default credentials
3. Check passwords against known breached password lists
4. Align password policies with NIST 800-63b
5. Harden against enumeration attacks (consistent responses)
6. Limit failed login attempts with exponential backoff
7. Use server-side, secure session manager; regenerate IDs after login

---

### A08:2025 – Software and Data Integrity Failures

**Description:** Code and infrastructure that doesn't protect against integrity violations. Includes insecure deserialization, trusting unsigned updates, and CI/CD without verification.

**Common Vulnerabilities:**
- Applications relying on untrusted CDNs or repositories
- Auto-update without integrity verification
- Insecure deserialization of untrusted data
- CI/CD pipelines without proper access controls
- Unsigned or unverified code deployments

**Prevention:**
```html
<!-- BAD: CDN without integrity -->
<script src="https://cdn.example.com/lib.js"></script>

<!-- GOOD: Subresource Integrity -->
<script src="https://cdn.example.com/lib.js"
        integrity="sha384-abc123..."
        crossorigin="anonymous"></script>
```

```python
# BAD: Unsafe deserialization
import pickle
data = pickle.loads(user_input)

# GOOD: Safe serialization with validation
import json
data = json.loads(user_input)
validate_schema(data)
```

**Mitigation Strategies:**
1. Use digital signatures to verify software/data from expected source
2. Ensure dependencies are from trusted repositories
3. Use software supply chain security tools (OWASP Dependency-Check)
4. Review code and configuration changes
5. Ensure CI/CD has proper segregation, configuration, and access control
6. Don't send unsigned/unencrypted serialized data to untrusted clients

---

### A09:2025 – Security Logging and Monitoring Failures

**Description:** Without logging and monitoring, breaches cannot be detected. Insufficient logging, detection, monitoring, and response allows attackers to persist.

**Common Vulnerabilities:**
- Auditable events not logged (logins, failed logins, transactions)
- Warnings and errors generate unclear log messages
- Logs only stored locally
- Alerting thresholds not set or ineffective
- Penetration tests don't trigger alerts
- Application can't detect active attacks in real-time

**Prevention:**
```python
import logging
from datetime import datetime

# Configure structured logging
logging.basicConfig(
    format='%(asctime)s %(levelname)s %(name)s %(message)s',
    level=logging.INFO
)
logger = logging.getLogger('security')

@app.route('/login', methods=['POST'])
def login():
    user = authenticate(request.form['username'], request.form['password'])
    if user:
        logger.info(f"LOGIN_SUCCESS user={user.id} ip={request.remote_addr}")
        return redirect('/dashboard')
    else:
        logger.warning(f"LOGIN_FAILURE username={request.form['username']} ip={request.remote_addr}")
        return "Invalid credentials", 401
```

**Mitigation Strategies:**
1. Log all login, access control, and server-side validation failures
2. Generate logs in format consumable by log management solutions
3. Encode log data correctly to prevent injection attacks
4. Ensure high-value transactions have audit trail with integrity controls
5. Establish effective monitoring and alerting
6. Create incident response and recovery plan (NIST 800-61r2)

---

### A10:2025 – Mishandling of Exceptional Conditions

**Description:** NEW category addressing failures in handling errors, edge cases, and unexpected states. Poor exception handling can leak information or cause security failures.

**Common Vulnerabilities:**
- Exposing stack traces to users
- Inconsistent error handling between components
- Fail-open behavior (allowing access on error)
- Resource exhaustion without graceful degradation
- Race conditions in error paths
- Incomplete transaction rollbacks

**Prevention:**
```python
# BAD: Leaking information
@app.errorhandler(Exception)
def handle_error(e):
    return str(e), 500  # Exposes internal details

# GOOD: Secure error handling
@app.errorhandler(Exception)
def handle_error(e):
    error_id = uuid.uuid4()
    logger.exception(f"Error {error_id}: {e}")
    return {"error": "An error occurred", "id": str(error_id)}, 500
```

```python
# BAD: Fail-open
def check_permission(user, resource):
    try:
        return authorization_service.check(user, resource)
    except Exception:
        return True  # Fail-open!

# GOOD: Fail-closed
def check_permission(user, resource):
    try:
        return authorization_service.check(user, resource)
    except Exception as e:
        logger.error(f"Auth check failed: {e}")
        return False  # Fail-closed
```

**Mitigation Strategies:**
1. Design for failure: expect and handle all error conditions
2. Implement fail-closed (deny by default) on errors
3. Use structured exception handling with appropriate granularity
4. Never expose internal errors to end users
5. Log all exceptions with context for debugging
6. Test error handling paths as thoroughly as happy paths
7. Implement circuit breakers for external dependencies

---

## OWASP API Security Top 10:2023

Released 2023, **still the current version** as of May 2026. APIs are a sufficiently distinct attack surface to warrant their own list, complementing the general Top 10:2025.

| ID | Risk | Summary |
|----|------|---------|
| API1 | Broken Object Level Authorization (BOLA) | User accesses another user's resource by guessing/swapping the ID |
| API2 | Broken Authentication | Weak JWT, sessions, API key handling |
| API3 | Broken Object Property Level Authorization (BOPLA) | Mass assignment + excessive data exposure |
| API4 | Unrestricted Resource Consumption | Missing rate / size / cost limits |
| API5 | Broken Function Level Authorization (BFLA) | User calls admin endpoint via URL guessing |
| API6 | Unrestricted Access to Sensitive Business Flows | Bot abuse of checkout, signup, password reset |
| API7 | Server-Side Request Forgery (SSRF) | API fetches attacker-controlled URL |
| API8 | Security Misconfiguration | API-stack equivalent of Top 10 A02 |
| API9 | Improper Inventory Management | Forgotten / old / staging endpoints exposed |
| API10 | Unsafe Consumption of APIs | Trusting third-party API responses without validation |

**Key insight:** BOLA (API1) is consistently the most-exploited API weakness in published incidents. Every resource access must be scoped to the owner, not just "is the user logged in?".

Deep coverage: [`references/api-cicd.md`](./references/api-cicd.md)

---

## OWASP Top 10 CI/CD Security Risks

Published 2022, still authoritative in 2026. Provides operational depth that the general Top 10:2025 A03 (Software Supply Chain Failures) covers only at a high level.

| ID | Risk |
|----|------|
| CICD-SEC-1 | Insufficient Flow Control Mechanisms |
| CICD-SEC-2 | Inadequate Identity and Access Management |
| CICD-SEC-3 | Dependency Chain Abuse |
| CICD-SEC-4 | Poisoned Pipeline Execution (PPE) |
| CICD-SEC-5 | Insufficient PBAC (Pipeline-Based Access Controls) |
| CICD-SEC-6 | Insufficient Credential Hygiene |
| CICD-SEC-7 | Insecure System Configuration |
| CICD-SEC-8 | Ungoverned Usage of 3rd Party Services |
| CICD-SEC-9 | Improper Artifact Integrity Validation |
| CICD-SEC-10 | Insufficient Logging and Visibility |

**Modern best practices:**
- **OIDC federation** instead of static cloud keys (GitHub Actions ↔ AWS/GCP/Azure).
- **Sigstore / cosign** for image signing; **SLSA** attestations for provenance.
- **External Secrets Operator** for K8s; **HashiCorp Vault** dynamic credentials.
- **Branch protection on workflow files**; CODEOWNERS for `.github/workflows/`.
- **Separate untrusted and trusted stages** — PR pipelines without secrets; deploy stage only after merge.

Deep coverage: [`references/api-cicd.md`](./references/api-cicd.md)

---

## OWASP ASVS 5.0.0

The Application Security Verification Standard (ASVS) 5.0.0 was released May 30, 2025. It provides ~350 security requirements across 17 categories with three verification levels.

### Verification Levels

| Level | Use Case | Description |
|-------|----------|-------------|
| L1 | All applications | Basic security controls for low-risk applications |
| L2 | Most applications | Standard security for applications handling sensitive data |
| L3 | High-value targets | Advanced security for critical infrastructure, healthcare, finance |

### ASVS Categories

1. **V1: Architecture, Design & Threat Modeling**
2. **V2: Authentication**
3. **V3: Session Management**
4. **V4: Access Control**
5. **V5: Input Validation**
6. **V6: Stored Cryptography**
7. **V7: Error Handling & Logging**
8. **V8: Data Protection**
9. **V9: Communication**
10. **V10: Malicious Code**
11. **V11: Business Logic**
12. **V12: Files and Resources**
13. **V13: API and Web Services**
14. **V14: Configuration**
15. **V15: OAuth and OIDC** (New in 5.0)
16. **V16: Self-Contained Tokens** (New in 5.0)
17. **V17: WebSockets** (New in 5.0)

### Key Requirements Examples

**Authentication (V2):**
- V2.1.1: User passwords SHALL be at least 12 characters (NIST 800-63B-4 raises this to 15 for AAL2)
- V2.1.6: Passwords SHALL be checked against breached password lists (now mandatory in 800-63B-4)
- V2.2.1: Anti-automation controls SHALL prevent credential stuffing
- V2.5.2: Password recovery SHALL NOT reveal if account exists
- V2.x: Periodic password rotation SHALL NOT be required (800-63B-4) — rotate only on compromise
- V2.x: Knowledge-based authentication answers SHALL NOT be used for recovery

**Session Management (V3):**
- V3.2.1: Session tokens SHALL have at least 128 bits of entropy
- V3.3.1: Sessions SHALL be invalidated on logout
- V3.4.1: Cookie-based tokens SHALL have Secure attribute set

**Access Control (V4):**
- V4.1.1: Access control SHALL be enforced server-side
- V4.2.1: Sensitive data SHALL only be accessible to authorized users
- V4.3.1: Directory browsing SHALL be disabled

**Cryptography (V6):**
- V6.2.1: All cryptographic modules SHALL fail securely
- V6.4.1: Keys SHALL be generated using approved random generators
- V6.4.2: Keys SHALL be stored securely (HSM, vault)

---

## OWASP Top 10 for LLM Applications 2025

Published by the OWASP GenAI Security Project. Covers model-boundary risks — the threats that surface at the LLM input/output interface and at training-data / embedding-store layers.

**LLM Top 10:2025 and Agentic 2026 are complementary, not alternatives.** LLM Top 10 covers model-level concerns; Agentic 2026 covers system-level concerns when an LLM is wrapped into an autonomous agent. Real agent applications must consider both.

### Summary Table

| ID | Risk | One-line |
|----|------|----------|
| LLM01 | Prompt Injection | Direct or indirect (via tool output / RAG / fetched docs) |
| LLM02 | Sensitive Information Disclosure | PII / secrets / proprietary data leaked via outputs |
| LLM03 | Supply Chain | Compromised foundation models, fine-tunes, LoRA adapters |
| LLM04 | Data and Model Poisoning | Training / fine-tuning data tampered, backdoors implanted |
| LLM05 | Improper Output Handling | Downstream systems trust LLM output without validation |
| LLM06 | Excessive Agency | LLM granted more authority than the task requires |
| LLM07 | System Prompt Leakage | **NEW** — system prompts treated as secrets, but exfiltrated |
| LLM08 | Vector and Embedding Weaknesses | **NEW** — RAG / embedding-store attacks (poisoning, inversion, cross-tenant) |
| LLM09 | Misinformation | Confident hallucinations propagated as fact |
| LLM10 | Unbounded Consumption | Token / resource / cost exhaustion via crafted prompts |

### LLM01 — Prompt Injection (depth)

Two attack vectors:
- **Direct:** user crafts input that overrides system prompt instructions.
- **Indirect:** model ingests attacker-controlled content (web page, PDF, calendar invite, email, tool output) that contains hidden instructions.

Google reported a **+32% increase in indirect prompt injection attempts** targeting AI browsing/agent stacks between Nov-2025 and Feb-2026. Indirect injection is now the dominant variant in the wild.

Mitigations:
- Separate user input from retrieved/tool-output content in the prompt structure.
- Use output schema constraints (JSON Schema, function-calling args) to limit blast radius.
- Spotlight retrieved data with markers but **never rely on markers alone**.
- Require human-in-the-loop for irreversible actions.
- Log full prompt + retrieved context + tool args for incident response.

### LLM07 — System Prompt Leakage (NEW)

The system prompt is **not** a secret store. Assume it will leak via prompt injection, summarization attacks, or side channels.

```
# UNSAFE: secrets in system prompt
SYSTEM: "You are a support agent. Backend API key is sk-prod-abc123."

# SAFE: capability, not secret
SYSTEM: "You are a support agent. Use the `get_order` tool when asked."
# Tool implementation holds the secret in env/vault, not in the prompt.
```

### LLM08 — Vector and Embedding Weaknesses (NEW)

RAG systems introduce a new attack surface:
- **Poisoning:** attacker writes malicious instructions or biased content into your knowledge base.
- **Inversion:** embeddings can sometimes be inverted to reconstruct source text — PII in embeddings is PII at rest.
- **Cross-tenant leakage:** shared indices can leak across tenants via query expansion.

Mitigations: access-control on chunks at retrieval time, integrity hashes on ingested documents, per-tenant indices (or strict metadata filters), trust-level metadata per chunk.

Deep coverage: [`references/llm-agentic.md`](./references/llm-agentic.md)

---

## OWASP Top 10 for Agentic Applications 2026

Released December 2025, this framework addresses security risks specific to AI agents, multi-agent systems, and autonomous applications.

### Summary Table

| ID | Risk | Description |
|----|------|-------------|
| ASI01 | Agent Goal Hijack | Prompt injection alters agent's core objectives |
| ASI02 | Tool Misuse | Legitimate tools used in unintended/unsafe ways |
| ASI03 | Identity & Privilege Abuse | Credential escalation across agent interactions |
| ASI04 | Supply Chain Vulnerabilities | Compromised plugins, MCP servers, or dependencies |
| ASI05 | Unexpected Code Execution | Unsafe code generation or execution by agents |
| ASI06 | Memory & Context Poisoning | Manipulation of RAG systems or agent memory |
| ASI07 | Insecure Inter-Agent Communication | Spoofing or tampering between agent systems |
| ASI08 | Cascading Failures | Error propagation across interconnected systems |
| ASI09 | Human-Agent Trust Exploitation | Social engineering through AI-generated content |
| ASI10 | Rogue Agents | Compromised or malicious agents within systems |

---

### ASI01: Agent Goal Hijack

**Description:** Attackers use prompt injection to alter an agent's intended goals, making it serve malicious purposes while appearing to function normally.

**Attack Vectors:**
- Direct prompt injection in user inputs
- Indirect injection via compromised data sources
- Hidden instructions in documents, websites, or emails
- Multi-turn conversation manipulation

**Prevention:**
- Implement strict input sanitization and filtering
- Use structured output formats to limit agent responses
- Establish clear goal boundaries with system prompts
- Monitor for goal deviation through behavioral analysis
- Implement human-in-the-loop for sensitive operations

---

### ASI02: Tool Misuse

**Description:** Agents with access to tools (APIs, databases, file systems) may use them in unintended ways due to malicious instructions or flawed reasoning.

**Attack Vectors:**
- Tricking agents into executing harmful commands
- Using tools with elevated privileges
- Chaining tool calls to achieve unauthorized outcomes
- Exploiting ambiguous tool descriptions

**Prevention:**
- Apply principle of least privilege to all tool access
- Implement fine-grained permissions per tool
- Validate all tool inputs and outputs
- Create tool usage policies and enforce them
- Log all tool invocations for audit

---

### ASI03: Identity & Privilege Abuse

**Description:** Agents may inherit, accumulate, or escalate privileges beyond what's appropriate, especially in multi-agent or long-running contexts.

**Attack Vectors:**
- Credential theft through prompt injection
- Session token exposure
- Privilege escalation through tool chaining
- Identity confusion in multi-agent systems

**Prevention:**
- Use short-lived, scoped credentials
- Implement identity verification between agents
- Don't pass raw credentials through agent context
- Audit privilege usage patterns
- Implement credential rotation

---

### ASI04: Supply Chain Vulnerabilities

**Description:** Compromised plugins, MCP servers, or third-party integrations introduce vulnerabilities into agent systems.

**Attack Vectors:**
- Malicious MCP server implementations
- Typosquatting in plugin registries
- Compromised update mechanisms
- Backdoored agent frameworks

**Prevention:**
- Verify plugin/server authenticity and signatures
- Maintain inventory of all integrations
- Sandbox third-party components
- Monitor for anomalous behavior from integrations
- Use allowlists for permitted plugins

---

### ASI05: Unexpected Code Execution

**Description:** Agents that generate or execute code may be tricked into running malicious code.

**Attack Vectors:**
- Code injection through prompts
- Malicious code in retrieved context
- Unsafe code execution environments
- Bypassing code review through obfuscation

**Prevention:**
- Execute generated code in sandboxed environments
- Implement static analysis before execution
- Limit code execution capabilities
- Require human approval for sensitive operations
- Use allowlists for permitted operations

---

### ASI06: Memory & Context Poisoning

**Description:** Attackers corrupt agent memory, RAG databases, or context to influence future behavior.

**Attack Vectors:**
- Injecting malicious content into vector databases
- Manipulating conversation history
- Poisoning knowledge bases
- Exploiting context window limitations

**Prevention:**
- Validate and sanitize all stored content
- Implement content integrity verification
- Segment memory by trust level
- Regular audits of stored knowledge
- Implement memory decay/expiration

---

### ASI07: Insecure Inter-Agent Communication

**Description:** Communication between agents may be vulnerable to interception, spoofing, or tampering.

**Attack Vectors:**
- Man-in-the-middle attacks on agent communication
- Agent identity spoofing
- Message tampering
- Replay attacks

**Prevention:**
- Authenticate all agent communications
- Encrypt inter-agent messages
- Implement message integrity verification
- Use secure channels for agent orchestration
- Validate agent identities cryptographically

---

### ASI08: Cascading Failures

**Description:** Errors in one agent or component propagate through interconnected systems, causing widespread failures.

**Attack Vectors:**
- Triggering errors that cascade through agent chains
- Resource exhaustion in one agent affecting others
- Error handling that exposes sensitive information
- Retry storms from failed operations

**Prevention:**
- Implement circuit breakers between agents
- Design for graceful degradation
- Isolate agent failures
- Rate limit inter-agent calls
- Monitor for cascade patterns

---

### ASI09: Human-Agent Trust Exploitation

**Description:** Attackers leverage the trust humans place in AI agents to conduct social engineering attacks.

**Attack Vectors:**
- AI-generated phishing content
- Impersonation through agent responses
- Trust exploitation via helpful-seeming agents
- Deceptive multi-turn conversations

**Prevention:**
- Clear labeling of AI-generated content
- User education on AI limitations
- Verification steps for sensitive actions
- Maintain human oversight for critical decisions
- Implement suspicious behavior detection

---

### ASI10: Rogue Agents

**Description:** Agents that have been compromised or are acting maliciously, either through external attack or flawed design.

**Attack Vectors:**
- Agent compromise through injection attacks
- Malicious agent deployment
- Agent behavior modification
- Insider threats via agent systems

**Prevention:**
- Monitor agent behavior for anomalies
- Implement agent authentication and authorization
- Regular security audits of agent systems
- Kill switches for agent operations
- Behavioral baselines and deviation detection

---

## NIST SP 800-63B-4 Highlights

NIST's Digital Identity Guidelines (Section B — Authentication) reached **Final 31-Jul-2025**, superseding 800-63B-3. The revision materially changes password and session guidance.

### Key changes vs 800-63B-3

| Rule | Old (-3) | Current (-4) |
|------|----------|--------------|
| Minimum length (user-chosen) | 8 chars | **15 chars** at AAL2, 8 at AAL1 |
| Composition rules ("must have digit") | Discouraged | **SHALL NOT impose** |
| Periodic rotation | Discouraged | **SHALL NOT require** unless compromised |
| Breached-password check | SHOULD | **SHALL** check |
| Password hints / KBA recovery | Allowed | **SHALL NOT** offer |
| Paste in password field | Should allow | **SHALL allow** |

### Authenticator Assurance Levels

| AAL | Requirement |
|-----|-------------|
| AAL1 | Single-factor — password OR a single authenticator |
| AAL2 | Two-factor — password + something else, OR a multi-factor authenticator (e.g., passkey with userVerification) |
| AAL3 | AAL2 + hardware-bound + phishing-resistant (verifier impersonation resistance) |

**Key 800-63B-4 change:** syncable authenticators (passkeys synced across iCloud Keychain, Google Password Manager, 1Password) now **explicitly qualify as AAL2** when the sync fabric meets spec requirements.

### Session Monitoring (new Section 5.3)

Required at AAL2:
- Reauthentication every 12 hours OR after 30 minutes of inactivity
- Concurrent session limits for high-risk roles
- Continuous evaluation — detect impossible travel, anomalous privilege use; step-up auth or terminate
- Session binding to TLS channel or device-bound key (DPoP, mTLS)

### Recovery flows

- **SHALL NOT** use knowledge-based answers ("mother's maiden name").
- **SHOULD** support recovery via a second registered authenticator.
- **SHALL** require AAL-equivalent verification for recovery.
- **SHOULD** notify user out-of-band when recovery completes.

Deep coverage: [`references/auth-modern.md`](./references/auth-modern.md)

---

## Post-Quantum Cryptography

NIST finalized post-quantum cryptography (PQC) standards on **13-Aug-2024**:

| FIPS | Algorithm | Type | Replaces |
|------|-----------|------|----------|
| 203 | ML-KEM (CRYSTALS-Kyber) | Key encapsulation | RSA-OAEP, ECDH for key exchange |
| 204 | ML-DSA (CRYSTALS-Dilithium) | Digital signature | RSA, ECDSA for general signing |
| 205 | SLH-DSA (SPHINCS+) | Digital signature | Hash-based backup for ML-DSA |
| 206 (draft) | FN-DSA (FALCON) | Digital signature | Smaller sigs than ML-DSA |

### Why migrate now

**Harvest-now-decrypt-later (HNDL):** an attacker captures encrypted traffic today and stores it; decrypts in 10-15 years when quantum is ready. Anything sensitive past ~2035 should already be PQ-protected in transit.

### Timeline

- **2024-08-13:** FIPS 203/204/205 published.
- **2025-12:** CISA/NSA published migration guidance.
- **2030-01-02:** TLS 1.3 + PQC hybrid **mandatory** for US-government national-security systems (per CNSA 2.0).
- **~2030-2035:** Vulnerable algorithms (RSA, ECDSA, classical DH) deprecated phase-by-phase per NIST IR 8547.

### What to do today

1. **Inventory** every place using RSA / ECDSA / ECDH / DH (TLS certs, JWT signing, code-signing, SSH/GPG).
2. **Adopt crypto agility** — algorithm IDs on the data, no hard-coded constants.
3. **Hybrid TLS** — combine ECDHE + ML-KEM (X25519+ML-KEM-768 is the canonical hybrid). OpenSSL 3.5+, BoringSSL, AWS-LC support this.
4. **Prefer larger symmetric keys** — AES-256-GCM > AES-128-GCM; SHA-384/512 > SHA-256 where size permits.
5. **Don't roll your own PQC** — use vetted libraries (liboqs, BoringSSL, AWS-LC).
6. **Don't migrate to PQC-only** — hybrid is the right transitional posture until PQC implementations mature.

Deep coverage: [`references/crypto-modern.md`](./references/crypto-modern.md)

---

## CWE Top 25:2025

CISA / MITRE publish the CWE Top 25 annually based on analysis of CVEs. The **2025 edition** was released Dec-2025 (based on ~32k CVEs over 24 months).

### Top 10 (2025)

| Rank | CWE | Name | Maps to OWASP Top 10:2025 |
|------|-----|------|---------------------------|
| 1 | CWE-79 | Cross-site Scripting | A05 Injection |
| 2 | CWE-787 | Out-of-bounds Write | (memory safety) |
| 3 | CWE-89 | SQL Injection | A05 Injection |
| 4 | CWE-352 | Cross-Site Request Forgery | A01 Broken Access Control |
| 5 | CWE-862 | Missing Authorization | A01 Broken Access Control |
| 6 | CWE-22 | Path Traversal | A01 Broken Access Control |
| 7 | CWE-78 | OS Command Injection | A05 Injection |
| 8 | CWE-416 | Use After Free | (memory safety) |
| 9 | CWE-434 | Unrestricted Upload of Dangerous Type | A05 / A06 |
| 10 | CWE-94 | Code Injection | A05 Injection |

### Notable 2025 changes vs 2024

- **CWE-862 Missing Authorization** moved up 5 positions — operational reality: authz is harder to test than authn.
- **CWE-79 XSS** retook #1 from CWE-787 (memory safety).
- **CWE-918 SSRF** entered top 20 again (cloud-metadata abuse).
- **CWE-352 CSRF** rose despite SameSite=Lax defaults (JSON APIs without enforcement).

Full mapping: [`references/extras.md`](./references/extras.md)

---

## Key Security Principles

### Defense in Depth
Layer multiple security controls so that if one fails, others provide protection.

### Least Privilege
Grant minimum permissions necessary for functionality. Regularly review and revoke unnecessary access.

### Fail Secure
When errors occur, default to a secure state. Deny access rather than allow it when uncertain.

### Zero Trust
Never trust, always verify. Authenticate and authorize every request regardless of source.

### Secure by Default
Ship products with secure defaults. Require explicit action to reduce security.

### Input Validation
Validate all input on the server side. Use allowlists over denylists.

### Output Encoding
Encode output based on context (HTML, JavaScript, SQL, etc.) to prevent injection.

### Keep Security Simple
Complex security is often bypassed. Prefer simple, understandable controls.

---

## Sources and References

### Official OWASP Resources
- [OWASP Top 10:2025](https://owasp.org/Top10/)
- [OWASP API Security Top 10:2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [OWASP Top 10 CI/CD Security Risks](https://owasp.org/www-project-top-10-ci-cd-security-risks/)
- [OWASP ASVS 5.0](https://github.com/OWASP/ASVS)
- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/llm-top-10/)
- [OWASP Top 10 for Agentic Applications 2026](https://genai.owasp.org/)
- [OWASP Mobile Top 10:2024](https://owasp.org/www-project-mobile-top-10/)
- [OWASP MASVS](https://mas.owasp.org/MASVS/)
- [OWASP Kubernetes Top 10](https://owasp.org/www-project-kubernetes-top-ten/)
- [OWASP Docker Top 10](https://owasp.org/www-project-docker-top-10/)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [OWASP CI/CD Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/CI_CD_Security_Cheat_Sheet.html)

### Authentication & Identity
- [NIST SP 800-63B-4 (Final, 31-Jul-2025)](https://csrc.nist.gov/pubs/sp/800/63/b/4/final)
- [NIST SP 800-63B-4 HTML](https://pages.nist.gov/800-63-4/sp800-63b.html)
- [WebAuthn Level 3 (W3C)](https://www.w3.org/TR/webauthn-3/)
- [Passkey Central](https://www.passkeycentral.org/)
- [OAuth 2.1 draft](https://datatracker.ietf.org/doc/draft-ietf-oauth-v2-1/)
- [RFC 9449 — DPoP](https://datatracker.ietf.org/doc/html/rfc9449)
- [FAPI 2.0 Security Profile Final (19-Feb-2025)](https://openid.net/specs/fapi-security-profile-2_0-final.html)

### Cryptography & Supply Chain
- [NIST Post-Quantum Cryptography Project](https://csrc.nist.gov/projects/post-quantum-cryptography)
- [NIST IR 8547 (initial public draft)](https://csrc.nist.gov/pubs/ir/8547/ipd)
- [FIPS 203 — ML-KEM](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.203.pdf)
- [FIPS 204 — ML-DSA](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.204.pdf)
- [FIPS 205 — SLH-DSA](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.205.pdf)
- [Sigstore / cosign](https://www.sigstore.dev/)
- [SLSA framework](https://slsa.dev/)
- [External Secrets Operator](https://external-secrets.io/)

### AI & Agentic Security
- [MCP Security Best Practices](https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices)
- [Auth0 — MCP Spec Update](https://auth0.com/blog/mcp-specs-update-all-about-auth/)
- [Google — Prompt Injection Attacks](https://blog.google/security/prompt-injections-web/)
- [Anthropic — Many-Shot Jailbreaking](https://www.anthropic.com/research/many-shot-jailbreaking)
- [Cloud Security Alliance — MAESTRO Threat Modeling](https://cloudsecurityalliance.org/blog/2025/02/06/agentic-ai-threat-modeling-framework-maestro)

### Regulatory
- [EU AI Act (Regulation 2024/1689)](https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai)

### Industry Analysis
- [GitLab: OWASP Top 10 2025 - What's Changed and Why It Matters](https://about.gitlab.com/blog/)
- [Aikido: OWASP Top 10 for Agentic Applications Guide](https://www.aikido.dev/blog/)
- [Security Boulevard: OWASP 2025 Analysis](https://securityboulevard.com/)

### Standards and Guidelines
- [NIST SP 800-61r2: Incident Handling Guide](https://csrc.nist.gov/publications/detail/sp/800-61/rev-2/final)
- [CWE Top 25:2025](https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html)
- [CISA — 2025 CWE Top 25 announcement](https://www.cisa.gov/news-events/alerts/2025/12/11/2025-cwe-top-25-most-dangerous-software-weaknesses)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

---

*Last updated: May 2026*