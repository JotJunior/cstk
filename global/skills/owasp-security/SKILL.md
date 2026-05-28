---
name: owasp-security
description: 'Security review: OWASP Top 10:2025, ASVS 5.0, Agentic AI 2026, LLM Top 10, API/CICD, NIST 800-63B-4, WebAuthn, OAuth 2.1, FAPI 2.0, post-quantum. Triggers: "security review", "OWASP", "vulnerability check", "auth code", "threat model", "MCP security". Skip for general code review.'
---

# OWASP Security Best Practices Skill

Apply these security standards when writing or reviewing code.

> **Scope & limits.** This skill is a **checklist-guided review assistant** over
> the standards below — useful for sweeping a diff or PR and surfacing
> high-signal findings. It is **not**, and does not replace, a formal audit,
> pentest, or certification: the breadth of the catalog (10+ frameworks) means
> *checklist* coverage, not exhaustive verification. Use it to raise the security
> floor and to prioritize; treat findings as starting points, not verdicts.

## Deep references

This file is the **operational entry point** — quick checklists and code patterns. For deep coverage of any topic below, open the matching file in [`references/`](./references/):

| Topic | File |
|-------|------|
| LLM Top 10:2025 + Agentic 2026 deep dive + MCP security + modern prompt injection + MAESTRO | [`references/llm-agentic.md`](./references/llm-agentic.md) |
| OWASP API Security Top 10:2023 + OWASP CI/CD Top 10 (PPE, OIDC federation, signing) | [`references/api-cicd.md`](./references/api-cicd.md) |
| NIST SP 800-63B-4 + WebAuthn/Passkeys + OAuth 2.1 + FAPI 2.0 | [`references/auth-modern.md`](./references/auth-modern.md) |
| Post-quantum crypto (FIPS 203/204/205) + crypto agility + 2026 secrets management | [`references/crypto-modern.md`](./references/crypto-modern.md) |
| CWE Top 25:2025 + Mobile Top 10:2024 + Kubernetes/Docker Top 10 + EU AI Act mapping | [`references/extras.md`](./references/extras.md) |

The full historical reference document with deeper background on Top 10:2025, ASVS 5.0, and Agentic 2026 is in [`OWASP-2025-2026-Report.md`](./OWASP-2025-2026-Report.md).

## Quick Reference: OWASP Top 10:2025

| # | Vulnerability | Key Prevention |
|---|---------------|----------------|
| A01 | Broken Access Control | Deny by default, enforce server-side, verify ownership |
| A02 | Security Misconfiguration | Harden configs, disable defaults, minimize features |
| A03 | Supply Chain Failures | Lock versions, verify integrity, audit dependencies |
| A04 | Cryptographic Failures | TLS 1.2+, AES-256-GCM, Argon2/bcrypt for passwords |
| A05 | Injection | Parameterized queries, input validation, safe APIs |
| A06 | Insecure Design | Threat model, rate limit, design security controls |
| A07 | Auth Failures | MFA, check breached passwords, secure sessions |
| A08 | Integrity Failures | Sign packages, SRI for CDN, safe serialization |
| A09 | Logging Failures | Log security events, structured format, alerting |
| A10 | Exception Handling | Fail-closed, hide internals, log with context |

## Security Code Review Checklist

When reviewing code, check for these issues:

### Input Handling
- [ ] All user input validated server-side
- [ ] Using parameterized queries (not string concatenation)
- [ ] Input length limits enforced
- [ ] Allowlist validation preferred over denylist

### Authentication & Sessions
- [ ] Passwords hashed with Argon2id / bcrypt cost ≥ 12 (never MD5/SHA1)
- [ ] Passwords ≥ 15 chars at AAL2, no composition rules, no periodic rotation (NIST 800-63B-4)
- [ ] Breached-password check on registration / change (haveibeenpwned k-anonymity API)
- [ ] **Passkeys (WebAuthn)** offered as primary; password as fallback
- [ ] Session tokens ≥ 128 bits entropy; HTTPOnly + Secure + SameSite cookies
- [ ] Sessions invalidated server-side on logout (not just cookie cleared)
- [ ] Reauthentication every 12h / 30min idle for AAL2
- [ ] Step-up auth for high-risk operations
- [ ] OAuth 2.1 baseline (no implicit, no password grant); PKCE everywhere
- [ ] DPoP or mTLS sender-constraining for sensitive APIs
- [ ] FAPI 2.0 for financial / healthcare / government APIs

Deep dive: [`references/auth-modern.md`](./references/auth-modern.md)

### Access Control
- [ ] Check for framework-level auth middleware (e.g., Next.js middleware.ts, proxy.ts, Express middleware) before flagging missing per-route auth
- [ ] Authorization checked on every request
- [ ] Using object references user cannot manipulate
- [ ] Deny by default policy
- [ ] Privilege escalation paths reviewed

### Data Protection
- [ ] Sensitive data encrypted at rest (AES-256-GCM or ChaCha20-Poly1305)
- [ ] TLS 1.2+ everywhere; TLS 1.3 + hybrid PQC for long-lived secrets (HNDL risk)
- [ ] No sensitive data in URLs / logs / error messages / container images
- [ ] **No static long-lived secrets** — prefer OIDC federation, Workload Identity, dynamic credentials
- [ ] Secret scanning (gitleaks / trufflehog) in pre-commit + push protection
- [ ] Crypto-agile design — algorithm IDs on the data, no hard-coded constants
- [ ] PQC migration plan for systems handling secrets that must survive past ~2035

Deep dive: [`references/crypto-modern.md`](./references/crypto-modern.md)

### Error Handling
- [ ] No stack traces exposed to users
- [ ] Fail-closed on errors (deny, not allow)
- [ ] All exceptions logged with context
- [ ] Consistent error responses (no enumeration)

## Secure Code Patterns

### SQL Injection Prevention
```python
# UNSAFE
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")

# SAFE
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
```

### Command Injection Prevention
```python
# UNSAFE
os.system(f"convert {filename} output.png")

# SAFE
subprocess.run(["convert", filename, "output.png"], shell=False)
```

### Password Storage
```python
# UNSAFE
hashlib.md5(password.encode()).hexdigest()

# SAFE
from argon2 import PasswordHasher
PasswordHasher().hash(password)
```

### Access Control
```python
# UNSAFE - No authorization check
@app.route('/api/user/<user_id>')
def get_user(user_id):
    return db.get_user(user_id)

# SAFE - Authorization enforced
@app.route('/api/user/<user_id>')
@login_required
def get_user(user_id):
    if current_user.id != user_id and not current_user.is_admin:
        abort(403)
    return db.get_user(user_id)
```

### Error Handling
```python
# UNSAFE - Exposes internals
@app.errorhandler(Exception)
def handle_error(e):
    return str(e), 500

# SAFE - Fail-closed, log context
@app.errorhandler(Exception)
def handle_error(e):
    error_id = uuid.uuid4()
    logger.exception(f"Error {error_id}: {e}")
    return {"error": "An error occurred", "id": str(error_id)}, 500
```

### Fail-Closed Pattern
```python
# UNSAFE - Fail-open
def check_permission(user, resource):
    try:
        return auth_service.check(user, resource)
    except Exception:
        return True  # DANGEROUS!

# SAFE - Fail-closed
def check_permission(user, resource):
    try:
        return auth_service.check(user, resource)
    except Exception as e:
        logger.error(f"Auth check failed: {e}")
        return False  # Deny on error
```

## LLM & Agentic AI Security

Two complementary OWASP lists apply when building AI-powered systems:

**OWASP Top 10 for LLM Applications 2025** — model-boundary risks:

| ID | Risk | One-line |
|----|------|----------|
| LLM01 | Prompt Injection | Direct or indirect (via tool output / RAG / docs) |
| LLM02 | Sensitive Info Disclosure | PII / secrets leaked via outputs |
| LLM03 | Supply Chain | Compromised models, fine-tunes, LoRA adapters |
| LLM04 | Data / Model Poisoning | Training-data tampering, backdoors |
| LLM05 | Improper Output Handling | Downstream systems trust LLM output unchecked |
| LLM06 | Excessive Agency | Too much functionality / permission / autonomy |
| LLM07 | System Prompt Leakage | System prompts treated as secrets, but extractable |
| LLM08 | Vector / Embedding Weaknesses | RAG poisoning, embedding inversion, cross-tenant leak |
| LLM09 | Misinformation | Hallucinations propagated as fact |
| LLM10 | Unbounded Consumption | Token / resource / cost exhaustion |

**OWASP Top 10 for Agentic Applications 2026** — system-level risks:

| ID | Risk | Mitigation |
|----|------|------------|
| ASI01 | Goal Hijack | Boundaries, output schemas, behavior monitoring |
| ASI02 | Tool Misuse | Least privilege, schemas on I/O, audit |
| ASI03 | Privilege Abuse | Short-lived scoped tokens, delegated identity |
| ASI04 | Supply Chain | Sign packages, sandbox MCP servers, allowlist |
| ASI05 | Code Execution | Sandbox, static analysis, human approval |
| ASI06 | Memory Poisoning | Validate at ingest + retrieve, trust segmentation |
| ASI07 | Inter-Agent Comms | Authenticate, encrypt, message integrity |
| ASI08 | Cascading Failures | Circuit breakers, degradation, isolation |
| ASI09 | Trust Exploitation | Label AI content, verification steps |
| ASI10 | Rogue Agents | Behavior baseline, kill switch, anomaly alerts |

### Modern attack patterns to watch (2025-2026)

- **Indirect prompt injection** — Google reported +32% rise in indirect injection attempts targeting AI browsers / agents (Nov-2025 → Feb-2026). Carriers: web pages, PDFs, calendar invites, emails.
- **Many-shot jailbreaking** — exploits long context (>128k tokens) by stuffing fake "user/assistant" turns. Cap effective context for safety decisions; classify the full assembled prompt.
- **Tool-empowered jailbreaks** — model refuses individual harmful asks but chains tools (`fetch` → `write_file` → `send_email`) where no single call looks malicious. Model **trajectories**, not just calls.

### Agent / LLM Security Checklist

- [ ] User input separated from retrieved / tool-output content in prompt structure
- [ ] Retrieved content treated as untrusted (don't rely on markers alone)
- [ ] No production secrets in system prompts (LLM07 makes them extractable)
- [ ] Output schemas constrain model responses (JSON Schema / function-calling args)
- [ ] Each tool has minimum permissions + input/output schema validation
- [ ] Dangerous tools gated by human approval or policy filter
- [ ] All tool calls audit-logged with session ID + prompt hash + args + result
- [ ] Short-lived scoped credentials; user identity delegated (not just agent identity)
- [ ] MCP servers: OAuth 2.1 + PKCE + RFC 8707 resource indicators + DPoP
- [ ] MCP tool descriptions sanitized (no prompt-injection vector)
- [ ] RAG: trust-level metadata per chunk; per-tenant indices; integrity hashes
- [ ] Behavior baseline + anomaly alerts; kill switch wired up and tested

Deep dive: [`references/llm-agentic.md`](./references/llm-agentic.md)

## ASVS 5.0 Key Requirements

ASVS 5.0 has 17 categories (V1-V17). V15 OAuth/OIDC, V16 Self-Contained Tokens, V17 WebSockets are new in 5.0.

### Level 1 (All Applications)
- Passwords minimum 15 characters at AAL2 (NIST 800-63B-4); 8 at AAL1
- Check against breached password lists (mandatory, was "should" in 800-63B-3)
- Rate limiting on authentication
- Session tokens 128+ bits entropy
- HTTPS everywhere; HSTS

### Level 2 (Sensitive Data)
- All L1 requirements plus:
- Passkeys (WebAuthn) or hardware-bound MFA preferred over TOTP/SMS
- Cryptographic key management with rotation
- Comprehensive security logging (structured, tamper-evident)
- Input validation on all parameters (server-side, schema-based)
- Session monitoring (anomaly detection, step-up auth)

### Level 3 (Critical Systems)
- All L1/L2 requirements plus:
- Hardware security modules for keys
- FAPI 2.0 for high-stakes APIs
- Threat modeling documentation (STRIDE / MAESTRO for AI systems)
- Advanced monitoring and alerting
- Penetration testing validation
- Crypto-agility for post-quantum migration readiness

## API & CI/CD Quick Refs

When the review focuses on **APIs** or **build/deploy pipelines**, the general Top 10 isn't enough. Use the dedicated lists:

**OWASP API Security Top 10:2023** (still current in 2026):
- API1 BOLA · API2 Broken Auth · API3 BOPLA (mass assignment) · API4 Unrestricted Resource Consumption · API5 BFLA · API6 Sensitive Business Flow Abuse · API7 SSRF · API8 Misconfiguration · API9 Improper Inventory · API10 Unsafe Third-Party Consumption

**OWASP CI/CD Top 10**:
- CICD-SEC-1 Flow Control · -2 IAM · -3 Dependency Chain Abuse · -4 Poisoned Pipeline Execution (PPE) · -5 Pipeline-Based Access · -6 Credential Hygiene · -7 System Misconfig · -8 3rd-Party Usage · -9 Artifact Integrity · -10 Logging

Deep dive: [`references/api-cicd.md`](./references/api-cicd.md)

## CWE Top 25:2025 (CISA / MITRE, Dec-2025)

Top 5 most-exploited weaknesses observed in CVEs over 24 months:
1. CWE-79 Cross-site Scripting
2. CWE-787 Out-of-bounds Write
3. CWE-89 SQL Injection
4. CWE-352 CSRF
5. CWE-862 Missing Authorization (+5 positions vs 2024)

Use to prioritize SAST rules and developer training. Full list + OWASP mapping: [`references/extras.md`](./references/extras.md)

## Language-Specific Security Quirks

> **Important:** The examples below are illustrative starting points, not exhaustive. When reviewing code, think like a senior security researcher: consider the language's memory model, type system, standard library pitfalls, ecosystem-specific attack vectors, and historical CVE patterns. Each language has deeper quirks beyond what's listed here.

Different languages have unique security pitfalls. Here are the top 20 languages with key security considerations. **Go deeper for the specific language you're working in:**

---

### JavaScript / TypeScript
**Main Risks:** Prototype pollution, XSS, eval injection
```javascript
// UNSAFE: Prototype pollution
Object.assign(target, userInput)
// SAFE: Use null prototype or validate keys
Object.assign(Object.create(null), validated)

// UNSAFE: eval injection
eval(userCode)
// SAFE: Never use eval with user input
```
**Watch for:** `eval()`, `innerHTML`, `document.write()`, prototype chain manipulation, `__proto__`

---

### Python
**Main Risks:** Pickle deserialization, format string injection, shell injection
```python
# UNSAFE: Pickle RCE
pickle.loads(user_data)
# SAFE: Use JSON or validate source
json.loads(user_data)

# UNSAFE: Format string injection
query = "SELECT * FROM users WHERE name = '%s'" % user_input
# SAFE: Parameterized
cursor.execute("SELECT * FROM users WHERE name = %s", (user_input,))
```
**Watch for:** `pickle`, `eval()`, `exec()`, `os.system()`, `subprocess` with `shell=True`

---

### Java
**Main Risks:** Deserialization RCE, XXE, JNDI injection
```java
// UNSAFE: Arbitrary deserialization
ObjectInputStream ois = new ObjectInputStream(userStream);
Object obj = ois.readObject();

// SAFE: Use allowlist or JSON
ObjectMapper mapper = new ObjectMapper();
mapper.readValue(json, SafeClass.class);
```
**Watch for:** `ObjectInputStream`, `Runtime.exec()`, XML parsers without XXE protection, JNDI lookups

---

### C#
**Main Risks:** Deserialization, SQL injection, path traversal
```csharp
// UNSAFE: BinaryFormatter RCE
BinaryFormatter bf = new BinaryFormatter();
object obj = bf.Deserialize(stream);

// SAFE: Use System.Text.Json
var obj = JsonSerializer.Deserialize<SafeType>(json);
```
**Watch for:** `BinaryFormatter`, `JavaScriptSerializer`, `TypeNameHandling.All`, raw SQL strings

---

### PHP
**Main Risks:** Type juggling, file inclusion, object injection
```php
// UNSAFE: Type juggling in auth
if ($password == $stored_hash) { ... }
// SAFE: Use strict comparison
if (hash_equals($stored_hash, $password)) { ... }

// UNSAFE: File inclusion
include($_GET['page'] . '.php');
// SAFE: Allowlist pages
$allowed = ['home', 'about']; include(in_array($page, $allowed) ? "$page.php" : 'home.php');
```
**Watch for:** `==` vs `===`, `include/require`, `unserialize()`, `preg_replace` with `/e`, `extract()`

---

### Go
**Main Risks:** Race conditions, template injection, slice bounds
```go
// UNSAFE: Race condition
go func() { counter++ }()
// SAFE: Use sync primitives
atomic.AddInt64(&counter, 1)

// UNSAFE: Template injection
template.HTML(userInput)
// SAFE: Let template escape
{{.UserInput}}
```
**Watch for:** Goroutine data races, `template.HTML()`, `unsafe` package, unchecked slice access

---

### Ruby
**Main Risks:** Mass assignment, YAML deserialization, regex DoS
```ruby
# UNSAFE: Mass assignment
User.new(params[:user])
# SAFE: Strong parameters
User.new(params.require(:user).permit(:name, :email))

# UNSAFE: YAML RCE
YAML.load(user_input)
# SAFE: Use safe_load
YAML.safe_load(user_input)
```
**Watch for:** YAML.load, Marshal.load, eval, send with user input, .permit!

---

### Rust
**Main Risks:** Unsafe blocks, FFI boundary issues, integer overflow in release
```rust
// CAUTION: Unsafe bypasses safety
unsafe { ptr::read(user_ptr) }

// CAUTION: Release integer overflow
let x: u8 = 255;
let y = x + 1; // Wraps to 0 in release!
// SAFE: Use checked arithmetic
let y = x.checked_add(1).unwrap_or(255);
```
**Watch for:** `unsafe` blocks, FFI calls, integer overflow in release builds, `.unwrap()` on untrusted input

---

### Swift
**Main Risks:** Force unwrapping crashes, Objective-C interop
```swift
// UNSAFE: Force unwrap on untrusted data
let value = jsonDict["key"]!
// SAFE: Safe unwrapping
guard let value = jsonDict["key"] else { return }

// UNSAFE: Format string
String(format: userInput, args)
// SAFE: Don't use user input as format
```
**Watch for:** force unwrap (!), try!, ObjC bridging, NSSecureCoding misuse

---

### Kotlin
**Main Risks:** Null safety bypass, Java interop, serialization
```kotlin
// UNSAFE: Platform type from Java
val len = javaString.length // NPE if null
// SAFE: Explicit null check
val len = javaString?.length ?: 0

// UNSAFE: Reflection
clazz.getDeclaredMethod(userInput)
// SAFE: Allowlist methods
```
**Watch for:** Java interop nulls (! operator), reflection, serialization, platform types

---

### C / C++
**Main Risks:** Buffer overflow, use-after-free, format string
```c
// UNSAFE: Buffer overflow
char buf[10]; strcpy(buf, userInput);
// SAFE: Bounds checking
strncpy(buf, userInput, sizeof(buf) - 1);

// UNSAFE: Format string
printf(userInput);
// SAFE: Always use format specifier
printf("%s", userInput);
```
**Watch for:** `strcpy`, `sprintf`, `gets`, pointer arithmetic, manual memory management, integer overflow

---

### Scala
**Main Risks:** XML external entities, serialization, pattern matching exhaustiveness
```scala
// UNSAFE: XXE
val xml = XML.loadString(userInput)
// SAFE: Disable external entities
val factory = SAXParserFactory.newInstance()
factory.setFeature("http://xml.org/sax/features/external-general-entities", false)
```
**Watch for:** Java interop issues, XML parsing, `Serializable`, exhaustive pattern matching

---

### R
**Main Risks:** Code injection, file path manipulation
```r
# UNSAFE: eval injection
eval(parse(text = user_input))
# SAFE: Never parse user input as code

# UNSAFE: Path traversal
read.csv(paste0("data/", user_file))
# SAFE: Validate filename
if (grepl("^[a-zA-Z0-9]+\\.csv$", user_file)) read.csv(...)
```
**Watch for:** `eval()`, `parse()`, `source()`, `system()`, file path manipulation

---

### Perl
**Main Risks:** Regex injection, open() injection, taint mode bypass
```perl
# UNSAFE: Regex DoS
$input =~ /$user_pattern/;
# SAFE: Use quotemeta
$input =~ /\Q$user_pattern\E/;

# UNSAFE: open() command injection
open(FILE, $user_file);
# SAFE: Three-argument open
open(my $fh, '<', $user_file);
```
**Watch for:** Two-arg `open()`, regex from user input, backticks, `eval`, disabled taint mode

---

### Shell (Bash)
**Main Risks:** Command injection, word splitting, globbing
```bash
# UNSAFE: Unquoted variables
rm $user_file
# SAFE: Always quote
rm "$user_file"

# UNSAFE: eval
eval "$user_command"
# SAFE: Never eval user input
```
**Watch for:** Unquoted variables, `eval`, backticks, `$(...)` with user input, missing `set -euo pipefail`

---

### Lua
**Main Risks:** Sandbox escape, loadstring injection
```lua
-- UNSAFE: Code injection
loadstring(user_code)()
-- SAFE: Use sandboxed environment with restricted functions
```
**Watch for:** `loadstring`, `loadfile`, `dofile`, `os.execute`, `io` library, debug library

---

### Elixir
**Main Risks:** Atom exhaustion, code injection, ETS access
```elixir
# UNSAFE: Atom exhaustion DoS
String.to_atom(user_input)
# SAFE: Use existing atoms only
String.to_existing_atom(user_input)

# UNSAFE: Code injection
Code.eval_string(user_input)
# SAFE: Never eval user input
```
**Watch for:** `String.to_atom`, `Code.eval_string`, `:erlang.binary_to_term`, ETS public tables

---

### Dart / Flutter
**Main Risks:** Platform channel injection, insecure storage
```dart
// UNSAFE: Storing secrets in SharedPreferences
prefs.setString('auth_token', token);
// SAFE: Use flutter_secure_storage
secureStorage.write(key: 'auth_token', value: token);
```
**Watch for:** Platform channel data, `dart:mirrors`, `Function.apply`, insecure local storage

---

### PowerShell
**Main Risks:** Command injection, execution policy bypass
```powershell
# UNSAFE: Injection
Invoke-Expression $userInput
# SAFE: Avoid Invoke-Expression with user data

# UNSAFE: Unvalidated path
Get-Content $userPath
# SAFE: Validate path is within allowed directory
```
**Watch for:** `Invoke-Expression`, `& $userVar`, `Start-Process` with user args, `-ExecutionPolicy Bypass`

---

### SQL (All Dialects)
**Main Risks:** Injection, privilege escalation, data exfiltration
```sql
-- UNSAFE: String concatenation
"SELECT * FROM users WHERE id = " + userId

-- SAFE: Parameterized query (language-specific)
-- Use prepared statements in ALL cases
```
**Watch for:** Dynamic SQL, `EXECUTE IMMEDIATE`, stored procedures with dynamic queries, privilege grants

---

## Deep Security Analysis Mindset

When reviewing any language, think like a senior security researcher:

1. **Memory Model:** How does the language handle memory? Managed vs manual? GC pauses exploitable?
2. **Type System:** Weak typing = type confusion attacks. Look for coercion exploits.
3. **Serialization:** Every language has its pickle/Marshal equivalent. All are dangerous.
4. **Concurrency:** Race conditions, TOCTOU, atomicity failures specific to the threading model.
5. **FFI Boundaries:** Native interop is where type safety breaks down.
6. **Standard Library:** Historic CVEs in std libs (Python urllib, Java XML, Ruby OpenSSL).
7. **Package Ecosystem:** Typosquatting, dependency confusion, malicious packages.
8. **Build System:** Makefile/gradle/npm script injection during builds.
9. **Runtime Behavior:** Debug vs release differences (Rust overflow, C++ assertions).
10. **Error Handling:** How does the language fail? Silently? With stack traces? Fail-open?

**For any language not listed:** Research its specific CWE patterns, CVE history, and known footguns. The examples above are entry points, not complete coverage.

---

## Gotchas

### Always check for framework-level auth BEFORE flagging missing per-route auth

The most common false positive: flagging a route handler as "no auth check" when auth is enforced globally in middleware (Next.js `middleware.ts`, Express `app.use`, Chi middleware stack, FastAPI dependencies). Read the middleware config before reporting.

### Fail-closed is MANDATORY in permission checks

`return True` in the `except` branch of a permission check is the most critical vulnerability pattern you will see. Auth failure must deny, not grant. This is not a style preference.

### The language examples are starting points, not a complete checklist

Every language has deeper quirks than what is listed (memory model, type system, serialization traps, FFI boundaries, historic CVEs in std lib). For any language you review, apply the deep analysis mindset — do not stop at the top-line examples.

### OWASP Top 10 has versions — use 2025/2026, not 2021

Top 10:2025 reordered and added categories (Supply Chain moved up; Exception Handling is now A10). Citing 2021 rankings gives stale advice. Same applies to ASVS (5.0 is current).

### Input validation is server-side, period

Client-side validation is UX, not security. Every reference to "validated input" in the checklist assumes server-side enforcement. If code only validates in the browser, it is unvalidated.

### Agentic AI threats are not hypothetical

Prompt injection (ASI01), tool misuse (ASI02), memory poisoning (ASI06) are actively exploited in 2026. When reviewing agent code, apply the ASI checklist — do not treat it as forward-looking only. **Indirect** prompt injection (via fetched web pages / docs / tool output) is the dominant vector — it bypasses input-sanitization mindsets built for user-typed prompts.

### Don't require periodic password rotation

NIST SP 800-63B-4 (final 31-Jul-2025) says passwords **SHALL NOT** be required to rotate on a schedule. Rotate only on evidence of compromise. Also: no composition rules ("must have a digit"), no password hints, no knowledge-based recovery. If you see "change your password every 90 days" in a fresh design, flag it.

### Passkeys before generic MFA

When recommending "add MFA", first ask whether passkeys (WebAuthn) fit. Passkeys are phishing-resistant and AAL2 by themselves (with userVerification). Password + TOTP is still relayable via reverse-proxy phishing kits — it's better than nothing, but not the default recommendation for new builds anymore.

### MCP servers need OAuth 2.1 + RFC 8707 + DPoP

MCP authorization spec (Jun-2025) is not optional theory. Tokens must carry resource indicators (RFC 8707) scoped to the specific MCP server, and DPoP sender-constraining prevents stolen-token replay. "Confused deputy" attacks in MCP proxies are the canonical failure mode.

### Start PQC inventory now if you store long-lived secrets

Harvest-now-decrypt-later means anything encrypted today with RSA / ECDH and stored by an adversary is at risk once a sufficient quantum computer arrives (~2030-2035 mainstream estimate). For new systems handling secrets that must remain confidential past 2035, plan crypto-agility now; for systems already in production, inventory and prioritize. FIPS 203/204/205 are the standards.

### LLM Top 10:2025 and Agentic 2026 are complementary, not alternative

A real agent application has BOTH model-boundary risks (LLM Top 10 — prompt injection, output handling, system prompt leakage, RAG poisoning) AND system-level risks (Agentic — tool misuse, privilege abuse, cascading failures). Applying only one list leaves the other surface unreviewed.

## When to Apply This Skill

Use this skill when:
- Writing authentication / authorization code (→ [`references/auth-modern.md`](./references/auth-modern.md))
- Handling user input or external data
- Implementing cryptography or password storage (→ [`references/crypto-modern.md`](./references/crypto-modern.md))
- Reviewing code for security vulnerabilities
- Designing API endpoints (→ [`references/api-cicd.md`](./references/api-cicd.md))
- Building AI agent / LLM / RAG / MCP systems (→ [`references/llm-agentic.md`](./references/llm-agentic.md))
- Configuring CI/CD pipelines or build systems (→ [`references/api-cicd.md`](./references/api-cicd.md))
- Reviewing container / Kubernetes / IaC configs (→ [`references/extras.md`](./references/extras.md))
- Reviewing mobile (iOS / Android) apps (→ [`references/extras.md`](./references/extras.md))
- Planning post-quantum migration (→ [`references/crypto-modern.md`](./references/crypto-modern.md))
- Handling errors and exceptions
- Working with third-party dependencies
- Mapping compliance (EU AI Act, NIST, FAPI) to engineering controls
- **Working in any language** — apply the deep analysis mindset above