# Playwright patterns for integration flow tests

Concrete, copy-adaptable patterns for the frontend half of an integration flow
test. Examples are TypeScript (Playwright's primary binding); the concepts map
to the Python/.NET/Java bindings. Adapt names to the project's conventions —
if a config/fixture already exists, **extend it, don't replace it**.

---

## 1. Config: traces, retries, projects

```ts
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,         // a stray test.only fails CI
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? [['html'], ['github']] : 'list',
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:5173',
    trace: 'on-first-retry',            // trace viewer is how you triage layers
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.ts/ },   // logs in once
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], storageState: 'tests/e2e/.auth/user.json' },
      dependencies: ['setup'],          // every test starts authenticated
    },
  ],
});
```

`trace: 'on-first-retry'` keeps runs fast but captures a full timeline (DOM,
network, console) the moment something flakes — open it with
`npx playwright show-trace`.

---

## 2. Authenticate once, reuse the session

Logging in inside every test is slow and couples unrelated tests to the login
UI. Do it once in a setup project and persist `storageState`.

```ts
// tests/e2e/auth.setup.ts
import { test as setup, expect } from '@playwright/test';
const authFile = 'tests/e2e/.auth/user.json';

setup('authenticate', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(process.env.E2E_USER!);
  await page.getByLabel('Senha').fill(process.env.E2E_PASS!);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/dashboard/);     // prove login succeeded
  await page.context().storageState({ path: authFile });
});
```

Gitignore `.auth/`. For multiple roles, save one state file per role and point
separate projects at each. **Exception:** when *login itself* is the flow under
test, drive it explicitly in that spec and do not depend on the setup project.

---

## 3. Locators: semantic first

Order of preference — higher = more robust and accessibility-asserting:

```ts
page.getByRole('button', { name: 'Salvar' })     // best: role + accessible name
page.getByLabel('E-mail')                         // form fields by their <label>
page.getByPlaceholder('seu@email.com')
page.getByText('Cliente criado')
page.getByTestId('customer-row-42')               // last resort for ambiguous nodes
// AVOID: page.locator('.btn.btn-primary > span:nth-child(2)')  — breaks on refactor
```

Scope to a region when text is ambiguous:
`page.getByRole('dialog').getByRole('button', { name: 'Confirmar' })`.

---

## 4. Web-first assertions — never sleep

Auto-retrying assertions wait for the condition (up to the timeout) instead of
racing it. They replace every `waitForTimeout`.

```ts
await expect(page.getByText('Cliente criado')).toBeVisible();
await expect(page).toHaveURL(/\/customers\/\d+/);
await expect(page.getByRole('row')).toHaveCount(3);
await expect(page.getByLabel('E-mail')).toHaveValue('ada@example.com');

// Validation cases — assert the error AND the disabled/blocked state:
await expect(page.getByText('E-mail inválido')).toBeVisible();
await expect(page.getByRole('button', { name: 'Salvar' })).toBeDisabled();

// ❌ NEVER:  await page.waitForTimeout(2000)   // deferred flake
```

---

## 5. Network assertions — the bridge to the backend

Confirm the right API call happened with the right status, and — critically for
validation cases — that bad input fires **no** call.

```ts
// Positive: capture the response triggered by the click
const [res] = await Promise.all([
  page.waitForResponse(r => r.url().endsWith('/customers') && r.request().method() === 'POST'),
  page.getByRole('button', { name: 'Salvar' }).click(),
]);
expect(res.status()).toBe(201);
const body = await res.json();
expect(body.id).toBeTruthy();

// Negative: invalid form must NOT submit. Watch, then assert no hit.
let posted = false;
page.on('request', r => { if (r.method() === 'POST' && r.url().endsWith('/customers')) posted = true; });
await page.getByLabel('E-mail').fill('not-an-email');
await page.getByRole('button', { name: 'Salvar' }).click();
await expect(page.getByText('E-mail inválido')).toBeVisible();
expect(posted).toBe(false);             // client-side validation blocked the write
```

**Mock sparingly.** `page.route` to stub a 500 is great for forcing an error
path you can't reproduce otherwise — but in an *integration* flow test, hitting
the real backend is the point. Mock the edge, not the spine.

---

## 6. Data isolation & unique fixtures

Parallel and repeated runs collide on unique columns unless every run uses fresh
data. Generate it, and tag it for teardown.

```ts
// tests/e2e/fixtures/data.ts
const RUN = `${process.pid}-${Date.now().toString(36)}`;   // unique per worker/run
export const uniq = (tmpl: string) => tmpl.replace('%s', `${RUN}-${counter++}`);
let counter = 0;
// uniq('e2e+%s@example.com')  ->  e2e+12345-abc-0@example.com
export const E2E_TAG = `e2e-${RUN}`;     // stamp records so teardown can find them
```

Use a recognizable prefix (`e2e+…`, `e2e-…`) so leaked rows are greppable and a
nightly cleanup can sweep them.

---

## 7. Fixtures: inject DB/queue helpers into the test

Extend Playwright's `test` so specs receive ready-to-use backend assertion
handles (implemented in `backend-async-verification.md`).

```ts
// tests/e2e/fixtures/test.ts
import { test as base } from '@playwright/test';
import { makeDb, Db } from './db';
import { makeQueue, Queue } from './queue';

export const test = base.extend<{ db: Db; queue: Queue }>({
  db:    async ({}, use) => { const db = await makeDb();    await use(db);    await db.close(); },
  queue: async ({}, use) => { const q  = await makeQueue(); await use(q);     await q.close(); },
});
export const expect = test.expect;
```

Now any spec: `test('...', async ({ page, db, queue }) => { ... })`.

---

## 8. CI wiring

```yaml
# .github/workflows/e2e.yml (sketch)
- run: npx playwright install --with-deps chromium
- run: docker compose -f docker-compose.test.yml up -d   # frontend+api+pg+rabbitmq
- run: npx playwright test
  env:
    E2E_BASE_URL: http://localhost:5173
    E2E_DB_URL: postgres://test:test@localhost:5432/app_test
    E2E_AMQP_URL: amqp://localhost:5672
- uses: actions/upload-artifact@v4
  if: ${{ !cancelled() }}
  with: { name: playwright-report, path: playwright-report/ }
```

Always upload the HTML report / traces so a CI failure is debuggable without a
local repro. If the broker isn't reachable in CI, fall back to side-effect
assertions (see backend reference) and document the gap in the coverage report.
