# Backend & async verification

The half that turns a UI test into an integration flow test: asserting the
database, the message queue, and eventually-consistent side effects. Examples
use a Node/TypeScript test harness (Playwright fixtures) with PostgreSQL and
RabbitMQ — the patterns translate to any stack. Credentials always come from
test env vars, never hardcoded.

---

## 1. Database assertions

Query the datastore directly and assert the **persisted, transformed** state —
not a row count, not the API's echo of what you sent. The API can return 201 and
still have rolled back, written the wrong column, or skipped a transform.

```ts
// tests/e2e/fixtures/db.ts
import { Pool } from 'pg';
export type Db = {
  one:  (sql: string, params?: unknown[]) => Promise<any>;
  none: (sql: string, params?: unknown[]) => Promise<void>;
  many: (sql: string, params?: unknown[]) => Promise<any[]>;
  close: () => Promise<void>;
};
export async function makeDb(): Promise<Db> {
  const pool = new Pool({ connectionString: process.env.E2E_DB_URL });
  return {
    one:  async (sql, p) => (await pool.query(sql, p)).rows[0],
    none: async (sql, p) => { await pool.query(sql, p); },
    many: async (sql, p) => (await pool.query(sql, p)).rows,
    close: () => pool.end(),
  };
}
```

```ts
// Positive: the row exists with the EXPECTED, transformed fields
const row = await db.one('select * from customers where email = $1', [email]);
expect(row).toBeTruthy();
expect(row.name).toBe('Ada Lovelace');
expect(row.email).toBe(email.toLowerCase());      // assert the lowercase transform
expect(row.status).toBe('pending');               // assert the default
expect(row.password_hash).not.toBe('plaintext');  // assert it was hashed
expect(row.tenant_id).toBe(expectedTenant);        // assert the FK / scoping

// Negative (validation/error case): the bad submit wrote NOTHING
const dupe = await db.many('select 1 from customers where email = $1', [badEmail]);
expect(dupe).toHaveLength(0);
```

### Cleanup — keep the suite repeatable

```ts
test.afterEach(async ({ db }) => {
  await db.none(`delete from customers where email like 'e2e+%'`); // tagged data only
});
```

Prefer deleting by the run's unique tag/prefix over truncating shared tables.
For destructive flows, wrap in a transaction you roll back, or run against a
disposable schema/database per worker.

---

## 2. Message-queue verification (RabbitMQ)

Three strategies, from strongest end-to-end signal to coarsest. Pick the
deepest one your environment allows; document the choice in the coverage report.

### Strategy A — assert the consumer's side effect (truest E2E)

The most honest proof that the event flowed: observe what the *consumer* did.
If `customer.created` triggers a welcome email, assert the email was enqueued /
sent (via a mail-catcher API, an `outbox` table, etc.). This proves publish +
routing + binding + consume all worked, without coupling the test to broker
internals.

```ts
await expect.poll(
  async () => (await db.many(`select 1 from outbox where type='welcome_email' and to_addr=$1`, [email])).length,
  { timeout: 10_000, message: 'welcome email never enqueued by consumer' },
).toBeGreaterThan(0);
```

### Strategy B — bind a temporary test queue and consume the message

When you need to assert the **message itself** (routing key + payload). Critical
ordering: **declare and bind the temp queue BEFORE the action** that publishes,
or you race the event and miss it.

```ts
// tests/e2e/fixtures/queue.ts
import amqp from 'amqplib';
export type Listener = { next: (o?: { timeoutMs?: number }) => Promise<{ routingKey: string; payload: any }> };
export type Queue = { listen: (routingKey: string, exchange?: string) => Promise<Listener>; close: () => Promise<void> };

export async function makeQueue(): Promise<Queue> {
  const conn = await amqp.connect(process.env.E2E_AMQP_URL!);
  const ch = await conn.createChannel();
  return {
    async listen(routingKey, exchange = 'events') {
      const { queue } = await ch.assertQueue('', { exclusive: true, autoDelete: true });
      await ch.bindQueue(queue, exchange, routingKey);   // bind BEFORE triggering
      const buf: any[] = [];
      await ch.consume(queue, m => { if (m) { buf.push(m); ch.ack(m); } }, { noAck: false });
      return {
        next: ({ timeoutMs = 10_000 } = {}) => waitFor(() => {
          const m = buf.shift();
          if (!m) return undefined;
          return { routingKey: m.fields.routingKey, payload: JSON.parse(m.content.toString()) };
        }, timeoutMs, `no '${routingKey}' message within ${timeoutMs}ms`),
      };
    },
    close: () => conn.close(),
  };
}
```

```ts
// In the spec — bind first, act, then assert:
const listener = await queue.listen('customer.created');
await submitTheForm();                              // the click that publishes
const msg = await listener.next({ timeoutMs: 10_000 });
expect(msg.routingKey).toBe('customer.created');
expect(msg.payload).toMatchObject({ email, name: 'Ada Lovelace' });
```

### Strategy C — RabbitMQ management HTTP API (coarse fallback)

No AMQP client / can't bind a queue? Poll the management API for the message
count on a pre-existing bound queue. Coarser (count, not content; sensitive to
other traffic) but needs only HTTP.

```ts
const base = process.env.E2E_RABBIT_MGMT ?? 'http://guest:guest@localhost:15672';
await expect.poll(async () => {
  const r = await fetch(`${base}/api/queues/%2f/customer_events`);
  return (await r.json()).messages as number;
}, { timeout: 10_000 }).toBeGreaterThan(0);
```

---

## 3. Eventual consistency — bounded polling helper

Async effects (read-model projections, list refreshes, downstream writes) are
not instant. Wait with a bounded predicate; a timeout is a real failure, not
flake to paper over with a longer sleep.

```ts
// generic retry-until-true with a hard ceiling
export async function waitFor<T>(fn: () => Promise<T | undefined> | T | undefined,
                                 timeoutMs = 10_000, msg = 'condition not met'): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const v = await fn();
    if (v !== undefined && v !== false) return v as T;
    if (Date.now() > deadline) throw new Error(`waitFor timeout: ${msg}`);
    await new Promise(r => setTimeout(r, 200));   // poll interval, not a fixed wait
  }
}
```

Playwright's built-in `expect.poll(fn, { timeout })` covers most cases; the
helper above is for non-assertion waits (e.g. block until the consumer caught
up before the next UI step).

```ts
// UI reflects the async projection — poll the UI, don't sleep then check
await expect.poll(async () => {
  await page.reload();
  return page.getByRole('row', { name: /Ada Lovelace/ }).count();
}, { timeout: 15_000, message: 'new customer never appeared in the list' }).toBeGreaterThan(0);
```

---

## 4. Verification checklist per mutating step

For every step that changes state, before calling it done:

- [ ] **UI**: success indicator visible / error indicator for negative cases.
- [ ] **Network**: expected method + URL + status (and *no* call for blocked
      validation cases).
- [ ] **Database**: row present with transformed fields (or absent for negative
      cases); FKs/scoping correct.
- [ ] **Queue**: event observed — via consumer side effect (A), message
      content (B), or count (C); listener bound *before* the action.
- [ ] **Async**: eventually-consistent effects awaited with a bounded poll.
- [ ] **Cleanup**: everything the step created is removed in teardown.

Any box you cannot check because the layer is unreachable is a **documented
coverage gap**, surfaced in the report — not a silently skipped assertion.
