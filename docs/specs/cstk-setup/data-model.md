# Data Model: cstk-setup

Esta feature **nao tem persistencia**. FR-013 (INFRA-IDEMP) proibe
explicitamente qualquer flag persistido de "setup ja rodou": a idempotencia
vem de re-checar o status vivo de cada area a cada invocacao. Portanto o
modelo abaixo descreve **estruturas em memoria** durante um unico run —
variaveis de shell POSIX e linhas de saida, nao tabelas.

> **Nota de representacao**: `cli/lib` roda POSIX sh puro (Constitution
> II) — sem arrays. As colecoes abaixo sao representadas como linhas de
> texto acumuladas em variavel (registro por linha, campos separados por
> TAB), o mesmo formato TSV que `guard-hooks-status.sh check` ja emite
> (contrato no cabecalho, linhas 49-60).

---

## Entity: ConfigurationArea

Uma das quatro areas que o wizard percorre. A ordem e **fixa** (FR-001) e
e a propria ordem de apresentacao.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `id` | enum | `hooks` \| `state-backend` \| `mcp` \| `telemetry` | Ordem fixa de apresentacao (FR-001); `hooks` primeiro |
| `label` | string | NOT NULL | Texto exibido ao usuario (pt-br permitido — CLAUDE.md: mensagens podem ser pt-br) |
| `status` | enum | `configured` \| `not-configured` \| `unavailable` | Vocabulario da spec (FR-002); apurado fresco a cada run (FR-013) |
| `status_reason` | string | pode ser vazio | Motivo legivel — obrigatorio quando `status=unavailable` |
| `applicable` | bool | — | `false` para `telemetry` (FR-012 proibe aplicar) |
| `outcome` | enum | ver `AreaOutcome` | Preenchido ao fim do passo da area |

### Fonte de `status` por area (delegada — nunca reimplementada)

| `id` | Fonte read-only | Mapeamento para `status` |
|------|-----------------|--------------------------|
| `hooks` | `guard-hooks-status.sh check --projeto-alvo-path PATH --quiet` (contrato linhas 49-60) | exit 0 → `configured`; exit 1 → `not-configured` (inclui `stale`, ver nota); exit 2 → `unavailable` |
| `state-backend` | `config_state_backend_resolve` (`cli/lib/config.sh:94`) | `effective_backend=sqlite` → `configured`; `effective_backend=json` → `not-configured` (com `reason=` do proprio resolve em `status_reason`) |
| `mcp` | chave `cstk-state` presente em `<project>/.mcp.json` (alvo escrito por `cli/lib/mcp.sh:847`, bloco 864-865) | presente → `configured`; ausente → `not-configured` |
| `telemetry` | `otel-usage.sh preflight` (`otel-usage.sh:469`) | medicao ativa → `configured`; senao → `not-configured` |

> **Nota `stale`**: a 3a coluna do TSV do `guard-hooks-status.sh`
> (`current|stale|unknown`) faz "presente + registrado" NAO significar
> configurado. `stale` = copia do projeto diverge do catalogo, e o proprio
> `check` retorna exit 1 nesse caso (`_gh_cmd_check`, linhas 238-244).
> O wizard herda esse veredito: `stale` → `not-configured`.

> **Nota `unavailable`**: reservado para dependencia faltando ou fonte de
> deteccao inutilizavel — ex. `sqlite3` ausente/abaixo de
> `_SB_MIN_SQLITE_VERSION="3.45.1"` (`state-backend.sh:67`), caso em que
> `enable-sqlite` recusaria com exit 3 (linhas 358-370). Area
> `unavailable` ainda e exibida e ainda entra no summary (FR-009/FR-010).

---

## Entity: HooksAreaDetail

Sub-estrutura da area `hooks`. Existe porque FR-008 exige que o hook
opt-in de loose usage seja uma escolha **distinta** da dos hooks
obrigatorios.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `mandatory_status` | enum | `configured` \| `not-configured` \| `unavailable` | Derivado do exit do `check` sobre os 3 hooks de `_GH_HOOKS` (`guard-hooks-status.sh:104-107`) |
| `mandatory_detail` | TSV lines | 3 linhas | `<arquivo>\t<present\|missing>\t<registered\|unregistered>\t<current\|stale\|unknown>` |
| `loose_usage_status` | enum | `configured` \| `not-configured` \| `indeterminate` | `indeterminate` quando a fonte de deteccao nao suporta a consulta — ver research.md Decision 3 |
| `loose_usage_choice` | enum | `apply` \| `skip` | Default em `--yes` e **`skip`** (opt-in preservado: `--with-loose-usage` e default off, `cli/lib/hooks.sh:513,543`) |

### Relationships

- `ConfigurationArea{id=hooks}` 1:1 `HooksAreaDetail`
- As demais tres areas nao tem sub-estrutura.

---

## Entity: AreaOutcome

Resultado de uma area apos seu passo. FR-010 fixa o conjunto: applied /
already configured / skipped by user / failed (com motivo).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `area_id` | enum | FK logica → `ConfigurationArea.id` | |
| `outcome` | enum | `applied` \| `already-configured` \| `skipped` \| `failed` | Conjunto fechado de FR-010 |
| `reason` | string | NOT NULL quando `outcome=failed` | Motivo legivel; inclui o exit code da fonte quando houver |
| `source_exit` | int | opcional | Exit code cru do comando delegado — rastreabilidade |

### Regras de derivacao

| Situacao | `outcome` |
|----------|-----------|
| `status=configured` na deteccao previa | `already-configured` (e **nenhuma** chamada de aplicacao — FR-003) |
| Usuario respondeu nao (ou default `skip` em `--yes`) | `skipped` |
| `--dry-run` ativo | `skipped`, com `reason` = "preview: nenhuma alteracao aplicada" |
| Aplicacao retornou exit 0 | `applied` |
| Aplicacao retornou exit != 0 | `failed`, `reason` cita o exit e o comando |
| `status=unavailable` | `failed`, `reason` = `status_reason` (dependencia ausente) |
| Area `telemetry` diagnosticada e nao ativa | `skipped`, `reason` = "diagnostico exibido; ativacao e manual (FR-012)" |

> **`telemetry` nunca produz `applied`** — decorre de FR-012 (ver
> research.md Decision 8). Forcar `applied` ali seria afirmar uma
> configuracao que o wizard nao realizou.

---

## Entity: SetupRunSummary

O relatorio de fim de run (FR-010). Impresso em **todos** os caminhos de
saida que chegaram a percorrer areas — interativo, `--yes`, `--dry-run`,
e runs parcialmente falhos (SC-005).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `project_path` | path | NOT NULL | Raiz de repo git validada (FR-011) |
| `mode` | enum | `interactive` \| `non-interactive` \| `preview` | `preview` vence `non-interactive` (FR-006) |
| `outcomes` | AreaOutcome[4] | exatamente 4 | Uma entrada por area de FR-001, na ordem fixa |
| `exit_code` | int | `0` \| `1` | `1` se algum `outcome=failed` — ver research.md Decision 9 |

### Relationships

- `SetupRunSummary` 1:N `AreaOutcome` (N = 4, fixo)
- `AreaOutcome` 1:1 `ConfigurationArea` por `area_id`

---

## State Transitions

Ciclo de vida de uma `ConfigurationArea` dentro de um run:

```
detect ──> configured ─────────────────────────> already-configured
   │
   ├─────> unavailable ────────────────────────> failed
   │
   └─────> not-configured ──┬─ preview ────────> skipped
                            ├─ declined ───────> skipped
                            └─ accepted ──┬────> applied      (exit 0)
                                          └────> failed       (exit != 0)
```

Invariantes:

- **I1 (FR-003)**: nenhuma transicao a partir de `configured` chama
  comando de aplicacao. Um projeto totalmente configurado atravessa as 4
  areas sem uma unica escrita.
- **I2 (FR-013)**: `detect` roda a cada invocacao, sempre. Nao ha estado
  carregado de run anterior.
- **I3 (FR-009)**: a transicao de uma area para `failed` nao altera a
  transicao de nenhuma outra — as 4 sao independentes.
- **I4 (FR-004)**: em `mode=preview`, `applied` e inalcancavel para todas
  as areas.
