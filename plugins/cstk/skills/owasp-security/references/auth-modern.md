# Modern Authentication — Deep Reference

> Companion to [`../SKILL.md`](../SKILL.md). Covers **NIST SP 800-63B-4** (final 31-Jul-2025), **WebAuthn L3 / Passkeys**, **OAuth 2.1**, and **FAPI 2.0**.

The shape of "good auth" changed materially in 2024-2025. The big shifts:

1. **Passwords are not the primary factor anymore.** Passkeys (WebAuthn syncable authenticators) are now recognized as AAL2 by NIST and are the default sign-in on Google, Apple, Microsoft consumer accounts.
2. **Periodic password rotation is dead.** NIST 800-63B-4 explicitly says passwords SHALL NOT require rotation unless compromised.
3. **OAuth 2.0 is superseded by OAuth 2.1** for new development — implicit and password grants are gone.
4. **High-value APIs need FAPI 2.0** (financial-grade, but applicable to any high-stakes resource).

---

## NIST SP 800-63B-4 (Final, 31-Jul-2025)

NIST's Digital Identity Guidelines, Section B (Authentication). This revision **supersedes 800-63B Rev 3** and significantly changes password and session guidance.

### Password rules (Section 5.1.1)

| Rule | 800-63B-3 (old) | 800-63B-4 (current) |
|------|-----------------|---------------------|
| Minimum length (user-chosen) | 8 chars | **15 chars** for L2+, 8 for L1 |
| Maximum length | At least 64 | At least 64 |
| Composition rules ("must have a digit") | Discouraged | **SHALL NOT impose** |
| Periodic rotation | Discouraged | **SHALL NOT require** unless evidence of compromise |
| Breached-password check | SHOULD | **SHALL** check against known-breached lists |
| Password hints / KBA recovery | Allowed | **SHALL NOT** offer hints or knowledge-based recovery |
| Paste in password field | Should allow | **SHALL allow** |
| ASCII restriction | — | **SHALL accept** all printable ASCII + Unicode |

```python
# UNSAFE — legacy rules
def validate_password(pw):
    if len(pw) < 8: return False
    if not any(c.isdigit() for c in pw): return False  # NIST: SHALL NOT impose
    if not any(c.isupper() for c in pw): return False  # NIST: SHALL NOT impose
    return True

# SAFE — NIST 800-63B-4 aligned
def validate_password(pw):
    if len(pw) < 15: return False                       # AAL2 minimum
    if len(pw) > 128: return False                      # DoS guard, not policy
    if is_breached(pw): return False                    # haveibeenpwned API or local k-anonymity list
    return True
```

### Authenticator Assurance Levels (AAL)

| AAL | Requirement |
|-----|-------------|
| AAL1 | Single-factor — password OR a single hardware/software authenticator |
| AAL2 | Two-factor — password + something else, OR a single **multi-factor** authenticator (e.g., passkey) |
| AAL3 | AAL2 + hardware-bound authenticator + verifier impersonation resistance (phishing-resistant) |

**Key 800-63B-4 change:** syncable authenticators (passkeys synced across iCloud Keychain, Google Password Manager, 1Password, etc.) now **explicitly qualify as AAL2** when the sync fabric meets the spec's requirements. Previously this was contested.

### Session Management (NEW Section 5.3)

800-63B-4 added a dedicated section on session monitoring. Required at AAL2:

- **Reauthentication** every 12 hours OR after 30 minutes of inactivity.
- **Concurrent session limits** for high-risk roles.
- **Continuous evaluation** — monitor session for indicators of compromise (impossible travel, sudden privilege use, anomalous patterns) and step-up auth or terminate.
- **Session binding** — bind session token to a TLS channel or device-bound key (DPoP, mTLS, token-binding).

```python
# Session record (Redis / DB)
session = {
    "user_id": "...",
    "issued_at": "...",
    "last_active": "...",
    "aal": "AAL2",
    "device_fingerprint": "...",
    "ip_geohash": "...",
    "step_up_for": [],          # operations that need reauth
    "dpop_jkt": "..."           # DPoP public key thumbprint
}
```

### Recovery flows

- **SHALL NOT** use knowledge-based answers ("mother's maiden name") for recovery.
- **SHOULD** support recovery via a second registered authenticator.
- **SHALL** require AAL-equivalent verification for recovery (don't downgrade).
- **SHOULD** notify user out-of-band when recovery completes.

Source: [NIST SP 800-63B-4 Final](https://csrc.nist.gov/pubs/sp/800/63/b/4/final) · [HTML version](https://pages.nist.gov/800-63-4/sp800-63b.html)

---

## WebAuthn / Passkeys

**WebAuthn Level 3** entered Working Draft Jan-2025. Passkeys (FIDO2 credentials synced across devices) are now the **default** sign-in on major consumer platforms.

### Why passkeys beat passwords + TOTP

| Property | Password+TOTP | Passkey |
|----------|---------------|---------|
| Phishable | ✗ (creds + TOTP can be relayed) | ✓ (origin-bound — cannot be relayed) |
| Server-side breach impact | High (hashes leak) | Low (only public keys stored) |
| User friction | High (type, paste, copy code) | Low (biometric / PIN) |
| Recovery | Often KBA (insecure) | Sync fabric + recovery code |
| Cross-device | Manual | Automatic via sync fabric |

### Server-side requirements

```python
# Registration (server creates challenge, returns options)
options = {
    "rp": {"id": "acme.com", "name": "Acme"},
    "user": {"id": user.webauthn_id, "name": user.email, "displayName": user.name},
    "challenge": secrets.token_bytes(32),
    "pubKeyCredParams": [
        {"type": "public-key", "alg": -7},   # ES256
        {"type": "public-key", "alg": -257}, # RS256
    ],
    "authenticatorSelection": {
        "residentKey": "preferred",          # passkey (discoverable credential)
        "userVerification": "preferred",
    },
    "attestation": "none",                   # privacy default
    "timeout": 60_000,
}

# On verify, check:
# - challenge matches what server issued
# - origin matches RP origin (phishing resistance!)
# - userVerification flag = true when policy requires
# - signature verifies against stored public key
# - sign count is monotonically increasing (clone detection)
```

### Common pitfalls

- **Forgetting origin check** — passkey is bound to `https://acme.com`, but server accepts any origin in the verification → phishing protection lost.
- **Allowing cross-origin iframes** — set `publickey-credentials-get` Permissions-Policy header.
- **Not storing the credential ID list per user** — needed for the `allowCredentials` array on sign-in.
- **Treating passkeys as single-factor** — passkey **with userVerification** is AAL2 by itself; passkey without UV is only single-factor.

### Migration strategy

1. Allow passkey registration in account settings (additive).
2. Encourage adoption — banner on next login.
3. After threshold % of users have a passkey, default sign-in to passkey, password as fallback.
4. Eventually: passwordless by default; password only for legacy/recovery.

Source: [WebAuthn L3 spec](https://www.w3.org/TR/webauthn-3/) · [Passkey Central](https://www.passkeycentral.org/)

---

## OAuth 2.1

OAuth 2.1 (draft, near-final) consolidates 10+ years of RFCs and BCPs into one spec. Use for **all new development**; OAuth 2.0 references stay valid via citation.

### Removed from 2.0

- **Implicit grant** — gone (token in URL fragment was a leak risk).
- **Resource Owner Password Credentials grant** — gone (defeats the point of OAuth).
- **Bearer tokens in query string** — gone (leaks via Referer / logs).

### Mandatory in 2.1

- **PKCE** for all clients (public and confidential).
- **Exact-match redirect URIs** — no wildcards, no partial.
- **Refresh token rotation + sender-constraining** (DPoP or mTLS).

### Token sender-constraining (DPoP — RFC 9449)

Bearer tokens are bearer — anyone who steals one can use it. **DPoP** binds the token to a client-held key: each request signs a JWT proving possession of the key.

```http
GET /api/orders HTTP/1.1
Authorization: DPoP eyJhbGciOi...
DPoP: eyJ0eXAiOiJkcG9wK2p3dCIsImFsZyI6IkVTMjU2IiwianRrIjoiM...
```

The `DPoP` header is a fresh JWT signed by the client's key, with claims `htu` (URL), `htm` (method), `iat`, `jti`. Server validates: signature, URL/method match, jti not replayed, key thumbprint matches the `jkt` claim in the access token.

Stolen access token alone → useless without the matching private key.

Source: [OAuth 2.1 draft](https://datatracker.ietf.org/doc/draft-ietf-oauth-v2-1/) · [RFC 9449 DPoP](https://datatracker.ietf.org/doc/html/rfc9449)

---

## FAPI 2.0 (Financial-grade API)

FAPI 2.0 **Security Profile Final** published 19-Feb-2025 by the OpenID Foundation; **Message Signing Final** Aug-2025. The standard for high-stakes APIs — banking, healthcare, government — and increasingly any API where unauthorized access would cause material harm.

### FAPI 2.0 mandatory requirements

| Mechanism | Why |
|-----------|-----|
| **PAR (Pushed Authorization Requests, RFC 9126)** | Auth request sent server-to-server; never in browser URL. Prevents tampering. |
| **PKCE** | Public client protection. |
| **Sender-constrained tokens (DPoP or mTLS)** | Stolen tokens useless. |
| **Authorization code flow only** | No implicit, no hybrid. |
| **JAR (JWT-Secured Authorization Request, RFC 9101)** | Request itself signed. |
| **Strict redirect URI matching** | No wildcards. |
| **Refresh token rotation** | Each use issues a new refresh; old becomes invalid. |
| **OAuth 2.1 baseline** | All 2.1 requirements apply. |

### FAPI 2.0 Message Signing (advanced)

For non-repudiation: request **and** response are signed JWS. Client signs request, server signs response, both can prove what was exchanged. Required for some open-banking jurisdictions.

### When to require FAPI 2.0

- Banking, payments, brokerage
- Healthcare records (HIPAA-equivalent)
- Government / identity services
- Any B2B API where the resource is high-value (signing keys, deployment access, large financial movements)
- Open-data ecosystems (Open Banking, Open Insurance, Open Energy)

For internal APIs, FAPI is usually overkill; OAuth 2.1 + DPoP is enough.

Source: [FAPI 2.0 Security Profile Final](https://openid.net/specs/fapi-security-profile-2_0-final.html) · [FAPI 2.0 conformance tests](https://openid.net/fapi2-0-final-conformance-tests-available/)

---

## Modern Auth Review Checklist

### Passwords (if still used)
- [ ] Minimum 15 chars at AAL2, 8 at AAL1
- [ ] No composition rules ("must have digit/upper/etc")
- [ ] Maximum length ≥ 64
- [ ] No periodic rotation requirement
- [ ] Checked against breached-password list
- [ ] All printable ASCII + Unicode accepted
- [ ] Paste allowed in password field
- [ ] Hashed with Argon2id / bcrypt cost ≥ 12

### Multi-factor / Passkeys
- [ ] Passkeys offered as first-class option
- [ ] Origin / RP ID verified on every WebAuthn ceremony
- [ ] User verification flag enforced for AAL2 claims
- [ ] Sign count monotonicity checked (clone detection)
- [ ] No KBA recovery; second authenticator or out-of-band code

### Sessions
- [ ] Token ≥ 128 bits entropy
- [ ] HTTPOnly + Secure + SameSite=Lax (or Strict)
- [ ] Reauthentication every 12h / 30min idle for AAL2
- [ ] Session bound to TLS channel (DPoP / mTLS) for sensitive operations
- [ ] Server-side invalidation on logout
- [ ] Step-up auth required for high-risk operations
- [ ] Anomaly monitoring (impossible travel, sudden privilege use)

### OAuth / OIDC
- [ ] OAuth 2.1 baseline (no implicit, no password grant)
- [ ] PKCE on all flows (public AND confidential clients)
- [ ] Exact-match redirect URIs (no wildcards)
- [ ] DPoP or mTLS for sender-constraining
- [ ] Refresh token rotation enabled
- [ ] Short access-token lifetime (5-15 min)
- [ ] Long refresh-token lifetime only with rotation + bind

### High-value APIs (FAPI 2.0)
- [ ] PAR (Pushed Authorization Requests) in use
- [ ] JAR (signed request objects)
- [ ] Sender-constrained tokens (DPoP/mTLS) — mandatory
- [ ] Message signing where non-repudiation required
- [ ] Conformance tested against OpenID FAPI 2.0 suite

---

## Sources

- [NIST SP 800-63B-4 Final](https://csrc.nist.gov/pubs/sp/800/63/b/4/final)
- [NIST SP 800-63B-4 HTML](https://pages.nist.gov/800-63-4/sp800-63b.html)
- [WebAuthn Level 3 (W3C)](https://www.w3.org/TR/webauthn-3/)
- [Passkey Central](https://www.passkeycentral.org/)
- [OAuth 2.1 draft](https://datatracker.ietf.org/doc/draft-ietf-oauth-v2-1/)
- [RFC 9449 — DPoP](https://datatracker.ietf.org/doc/html/rfc9449)
- [RFC 9126 — PAR](https://datatracker.ietf.org/doc/html/rfc9126)
- [RFC 9101 — JAR](https://datatracker.ietf.org/doc/html/rfc9101)
- [FAPI 2.0 Security Profile Final](https://openid.net/specs/fapi-security-profile-2_0-final.html)
- [FAPI 2.0 Conformance Tests](https://openid.net/fapi2-0-final-conformance-tests-available/)
