---
name: e2e-integration-flow
description: 'Author and run full-stack E2E integration tests with Playwright — drive the UI through a complete feature flow and verify the effects at EVERY layer (UI, network/API, database, message queue, side effects). Triggers: "e2e", "teste e2e", "integration test", "teste de integração", "playwright", "validar fluxo completo", "end-to-end". Skip for a quick manual smoke check (use verify) or debugging one known bug (use bugfix).'
argument-hint: "[feature/flow to test, or path to its spec/UC]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Edit
  - Write
  - Agent
  - TaskCreate
  - TaskUpdate
---

# E2E Integration Flow Skill

Author and run **end-to-end integration tests** that prove a feature actually
works across the whole stack — not just that a button is clickable, but that
every meaningful action produces the right effect at every layer it touches:
**UI → network/API → database → message queue → downstream side effects**.

The driver is **Playwright** (browser automation for the frontend). The
differentiator is that Playwright is only the *entry point*: each UI step is
paired with assertions in the layers behind it. A test that fills a form and
sees a toast is a UI test. A test that fills a form, sees the toast, confirms
the row landed in the database with the right fields, **and** confirms the
`user.created` event reached the queue — that is an integration flow test.

> **Scope & limits.** This skill builds and runs *automated functional
> integration tests*. It is not a load/performance test, not a security
> pentest (use `owasp-security`), and not a substitute for unit tests. It
> assumes you can reach a running stack (frontend + backend + datastores) in a
> test/staging environment. Stack-agnostic core with concrete defaults —
> adapt commands and selectors to the project you are in.

## Arguments

`$ARGUMENTS` is the feature/flow to test (e.g. "cadastro de cliente", "checkout
com cupom") or a path to its spec/UC (e.g. `docs/specs/cadastro/spec.md`,
`docs/02-requisitos-casos-uso/UC-CAD-001.md`). If empty, ask what flow to cover
and whether a spec/UC exists.

---

## The mental model: a flow is a chain of contracts

Most flaky, low-value e2e suites fail because they treat the UI as the whole
system. The fix is to think of the feature as an ordered **flow contract**:

> For each user action, there is an **observable consequence in one or more
> layers**. The test asserts that consequence — at the deepest layer that is
> practical — before moving to the next action.

A registration flow is not "click, type, click". It is:

| # | User action | UI effect | Network | Database | Queue / async | Downstream |
|---|-------------|-----------|---------|----------|---------------|------------|
| 1 | Log in | redirect to dashboard | `POST /auth` 200 + cookie | session row (opt) | — | — |
| 2 | Open "New customer" | form renders | `GET /form-meta` 200 | — | — | — |
| 3 | Submit invalid email | inline error, no submit | **no** `POST` fired | **no** new row | — | — |
| 4 | Submit valid form | success toast, redirect | `POST /customers` 201 | `customers` row w/ fields | `customer.created` on exchange | welcome email enqueued |
| 5 | (async) | list shows new customer | `GET /customers` includes it | — | consumer ACKed | email sent |

Building this table **first** is the core of the skill. It turns a vague "test
the registration" into a precise, layered set of assertions — and it exposes
exactly which verifications are missing in a typical UI-only test.

---

## Step 0 — Detect context & prerequisites

Before writing a line of test code, establish the ground truth. Do not assume.

1. **Find the flow's source of truth.** If a spec/UC path was given, read it —
   user stories, FRs, business rules (RN), and especially the validation rules
   and the events. If none, look in `docs/specs/*/spec.md`,
   `docs/02-requisitos-casos-uso/UC-*.md`, or ask the user to describe the
   happy path and the rules.
2. **Locate the running stack & how tests reach it.** Base URL of the frontend,
   API base URL, test database connection, message-broker access. Check for
   `.env.test`, `docker-compose.*.yml`, `playwright.config.*`, existing
   `e2e/`/`tests/e2e/` folders, CI workflow.
3. **Inventory what already exists.** Is Playwright installed
   (`npx playwright --version`)? Is there a config, an auth-setup project,
   fixtures, a seeded test user? **Reuse the project's conventions** — do not
   reinvent a harness that already exists.
4. **Confirm verification access.** Can the test environment query the DB
   directly? Reach the broker (AMQP port or RabbitMQ management API)? If a layer
   is unreachable, you will assert its *observable proxy* instead (e.g. assert
   the email was sent rather than the queue message) — note the gap explicitly.

Capture findings as a short context block. If a prerequisite is missing
(no test DB, no broker access, frontend not buildable), surface it now — a
flow test you cannot verify end-to-end is worth flagging before writing it.

For a multi-step flow, create tasks (TaskCreate) to track each segment.

---

## Step 1 — Build the flow contract

Produce the table above for the target flow. One row per user action.

- Derive actions from the **happy path** of the spec/UC.
- For each action, fill every layer column that applies. Leave `—` where a
  layer genuinely isn't touched (that is information, not laziness).
- For the **deepest practical layer** of each action, mark it as the *primary
  assertion* — that is what makes the step trustworthy. UI assertions alone are
  necessary but never sufficient for the steps that mutate state.
- Pull the **field-level expectations** from the spec: which fields persist,
  their transformed values (trimmed, lowercased, hashed), defaults, FKs.
- Pull the **events** from the spec/code: exact routing key / topic, payload
  shape, which consumer reacts and its side effect.

This table is the test plan. Keep it in the test file as a comment or in a
sibling `FLOW.md` so the coverage is auditable.

---

## Step 2 — Build the test matrix (cases, not just the path)

A flow has more than its happy path. Expand each form/decision point into cases:

| Category | What to cover | Example |
|----------|---------------|---------|
| **Happy path** | The full flow end-to-end, all layers verified | valid registration persists + emits event |
| **Field validation** | Every rule from the spec: required, format, length, uniqueness, cross-field | empty name, bad email, duplicate CPF, password mismatch |
| **Boundary / edge** | Min/max, special chars, unicode, very long input, leading/trailing space | 255-char name, emoji, `"  a@b.co  "` trims |
| **Error paths** | Backend rejects (409/422/500), network failure, timeout | duplicate → 409 surfaces a friendly error, no row, no event |
| **Authz / state** | Wrong role, unauthenticated, already-done | logged-out user redirected to login |
| **Idempotency / async** | Double-submit, eventual consistency, retry | double-click submits once; list reflects new row after consumer runs |

For each validation case assert the **negative space** too: an invalid submit
must produce **no** network call (or a 4xx that creates **no** DB row and **no**
event). Forgetting the negative assertion is the most common hole — the UI
shows an error *and* the bad data still got written.

---

## Step 3 — Set up the harness (reuse first)

Goal: deterministic, isolated, fast-to-debug tests. Key pillars (deep patterns
in [`references/playwright-patterns.md`](./references/playwright-patterns.md)):

- **Auth once, reuse everywhere.** A Playwright *setup project* logs in and
  saves `storageState`; flow tests start authenticated. Never log in inside
  every test unless login *is* the flow under test.
- **Data isolation.** Generate unique test data per run (a run id + faker), so
  parallel/repeat runs never collide on unique fields. Tag created records so
  teardown can find them.
- **Deterministic environment.** Pin the base URL, seed required reference data,
  and prefer a dedicated test DB/vhost you can safely write to and clean.
- **Backend assertion helpers.** Thin fixtures that the test can call to query
  the DB and to assert/await queue messages — see Step 5. Keep DB/broker creds
  in test env, never hardcoded.
- **Trace on failure.** Enable `trace: 'on-first-retry'`, screenshots and video
  on failure — the trace viewer is how you triage which layer broke.

If the project already has a config/auth-setup/fixtures, extend them. Only
scaffold from scratch when nothing exists.

---

## Step 4 — Implement the UI steps (web-first, no sleeps)

Translate the flow contract into Playwright, one action → assertion pair at a
time. The non-negotiables:

- **Semantic, user-facing locators.** `getByRole`, `getByLabel`,
  `getByPlaceholder`, `getByText` — they survive refactors and assert
  accessibility. Use `data-testid` only as a last resort for ambiguous nodes.
- **Web-first assertions only.** `await expect(locator).toBeVisible()`,
  `toHaveText`, `toHaveURL` — they auto-retry until the condition holds.
  **Never** `waitForTimeout`/fixed sleeps; they are the #1 source of flake.
- **Assert the network where it matters.** `waitForResponse`/`expect(response)`
  to confirm the API was hit with the right status — bridges UI to backend. For
  the *negative* validation cases, assert the request was **never** sent.
- **One flow per test, readable as prose.** Steps in order, each with its
  assertion. Use `test.step()` to label segments so failures point at the right
  action.

```ts
test('register customer — persists and emits customer.created', async ({ page, db, queue }) => {
  const email = uniq('e2e+%s@example.com');           // unique per run
  const listener = await queue.listen('customer.created'); // bind BEFORE acting

  await test.step('open form', async () => {
    await page.getByRole('link', { name: 'Novo cliente' }).click();
    await expect(page.getByRole('heading', { name: 'Novo cliente' })).toBeVisible();
  });

  await test.step('submit valid form', async () => {
    await page.getByLabel('Nome').fill('Ada Lovelace');
    await page.getByLabel('E-mail').fill(email);
    const [res] = await Promise.all([
      page.waitForResponse(r => r.url().endsWith('/customers') && r.request().method() === 'POST'),
      page.getByRole('button', { name: 'Salvar' }).click(),
    ]);
    expect(res.status()).toBe(201);
    await expect(page.getByText('Cliente criado')).toBeVisible();
  });

  await test.step('verify database', async () => {
    const row = await db.one('select * from customers where email = $1', [email]);
    expect(row.name).toBe('Ada Lovelace');     // assert the persisted, transformed fields
  });

  await test.step('verify event reached the queue', async () => {
    const msg = await listener.next({ timeoutMs: 10_000 }); // poll, never sleep
    expect(msg.routingKey).toBe('customer.created');
    expect(msg.payload.email).toBe(email);
  });
});
```

---

## Step 5 — Verify the backend & async layers

This is what separates an integration flow test from a UI test. Deep recipes in
[`references/backend-async-verification.md`](./references/backend-async-verification.md).

- **Database.** Query directly (the project's client / `psql` / a pg fixture).
  Assert the row **exists with the expected, transformed fields** — not just a
  count. For negative cases assert it does **not** exist. Always clean up what
  the test created (afterEach/afterAll, or a tagged teardown).
- **Message queue (RabbitMQ et al.).** Prefer asserting the **observable side
  effect** of the consumer (the truest end-to-end signal). When you need to
  assert the message itself, **bind a temporary test queue to the exchange
  before triggering the action**, then poll-consume with a timeout. The
  management HTTP API (message counts) is a coarser fallback. Never assert with
  a fixed sleep — poll until present or timeout.
- **Eventual consistency.** Async effects (list updates, projections, emails)
  need a bounded retry: `expect.poll(...)` / a `waitFor(predicate, timeout)`
  helper. State the timeout; if it's exceeded, that's a real failure, not flake.
- **Isolation discipline.** Unique data + teardown keeps the suite repeatable.
  A test that passes once and fails on re-run almost always leaked state.

---

## Step 6 — Run, triage by layer, stabilize

```bash
npx playwright test            # full run
npx playwright test --ui       # watch/debug interactively
npx playwright show-trace ...  # open the trace of a failed run
npx playwright test -g "register customer"   # one flow
```

Triage failures **by the layer that broke**, using the flow contract as the map:

- UI assertion failed but network 2xx + DB row present → selector/timing issue
  in the test, not the app.
- Network 4xx/5xx → backend rejected; read the response body; is the test data
  or the app at fault?
- UI + network fine, DB row missing → persistence bug (transaction rollback,
  wrong column) — a real find the UI alone would have hidden.
- DB fine, no queue message / consumer side effect → publisher or binding bug —
  the highest-value catch of this whole skill.

Stabilize before declaring done: re-run the suite (`--repeat-each=3` on the new
specs) to flush flake. A test that isn't repeatable isn't a test.

---

## Step 7 — Report coverage & gaps

Close with a concise report (not just "tests pass"):

- **Flow coverage map**: the contract table with ✅/❌ per layer per step —
  what is actually asserted vs. left as a gap (e.g. "queue checked via side
  effect only; broker not directly reachable in CI").
- **Matrix coverage**: which categories from Step 2 have cases; what's deferred.
- **Real findings**: any layer mismatch the tests exposed (these are bugs, route
  them to `bugfix`).
- **Run command + CI note**: how to run locally and whether it's wired into CI.

---

## Golden rules

1. **The UI is the trigger, not the proof.** Any step that mutates state earns a
   backend assertion. A green UI over a silent persistence/event bug is the
   exact failure mode this skill exists to prevent.
2. **Build the flow contract before the code.** The table is the test plan and
   the coverage report.
3. **Assert the negative space.** Invalid input must produce no write and no
   event — assert the absence, not only the error message.
4. **No fixed sleeps, ever.** Web-first assertions and bounded polling. Sleeps
   are deferred flake.
5. **Isolated & repeatable.** Unique data in, teardown out. If it can't run
   twice, it's not done.
6. **Bind listeners before acting.** Subscribe to the queue / start waiting for
   the response *before* the click that produces it, or you race the event.
7. **Reuse the project's harness.** Auth setup, fixtures, config conventions —
   extend, don't reinvent.

## When NOT to use this skill

- A quick "does it load / does this one change work" manual check → `verify`.
- Investigating a single reported bug → `bugfix`.
- Validating requirement/spec quality (not runtime behavior) → `checklist` /
  `analyze`.
- Security review of the flow → `owasp-security`.

## References

- [`references/playwright-patterns.md`](./references/playwright-patterns.md) —
  config, auth-state reuse, fixtures, locators, web-first assertions, network
  interception, data isolation, CI wiring.
- [`references/backend-async-verification.md`](./references/backend-async-verification.md)
  — direct DB assertions & cleanup, RabbitMQ verification (temp-queue bind,
  management API, side-effect proof), eventual-consistency polling helpers.
