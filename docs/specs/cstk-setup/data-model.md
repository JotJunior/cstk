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
| `status` | enum | `configured` \| `not-configured` \| `divergent` \| `unavailable` | Vocabulario da spec (FR-002); apurado fresco a cada run (FR-013) |
| `status_reason` | string | pode ser vazio | Motivo legivel — obrigatorio quando `status` e `unavailable` ou `divergent` (neste, carrega a remediacao) |
| `applicable` | bool | — | `false` para `telemetry` (FR-012 proibe aplicar) |
| `outcome` | enum | ver `AreaOutcome` | Preenchido ao fim do passo da area |

### Fonte de `status` por area (delegada — nunca reimplementada)

| `id` | Fonte read-only | Mapeamento para `status` |
|------|-----------------|--------------------------|
| `hooks` | **3 chamadas SEPARADAS** (achado SEC-03 — NUNCA combinadas): (1) baseline `guard-hooks-status.sh check --projeto-alvo-path PATH --quiet` (contrato §2.1 [EXISTENTE]); (2) `... --quiet --verify-registration` (contrato §2.3 [PROPOSTA]); (3) `... --quiet --include-loose-usage` (contrato §2.2 [PROPOSTA], alimenta so `loose_usage_status` em `HooksAreaDetail`, nunca esta linha) | Veredito base vem **sempre** de (1), que todo runtime instalado suporta: exit 0 → `configured`; exit 1 → `not-configured` (inclui `stale`, ver nota). Chamada (2) so pode **escalar**, nunca substituir silenciosamente o veredito de (1): 5a coluna `divergent` em qualquer hook obrigatorio → `divergent` (precede (1)); 5a coluna `indeterminate` em qualquer hook obrigatorio (inclusive por (2) sair exit 2 em runtime antigo, contrato §2.3) → `unavailable` (precede (1) — I5; nunca herda o `configured`/`not-configured` de (1)) |
| `state-backend` | `config_state_backend_resolve` (`cli/lib/config.sh:94`) | `effective_backend=sqlite` → `configured`; `effective_backend=json` → `not-configured` (com `reason=` do proprio resolve em `status_reason`) |
| `mcp` | `_mcp_registration_status <project-path>` ([PROPOSTA], `cli/lib/mcp.sh` — ver `contracts/cli-setup.md` §4.1) | `configured` (chave `cstk-state` presente **e** `command` apontando para um `mcp-launch.sh` do catalogo) / `divergent` (chave presente, `command` fora do catalogo ou indeterminavel) / `not-configured` (chave ausente) |
| `telemetry` | `otel-usage.sh preflight` (`otel-usage.sh:469`) | medicao ativa → `configured`; senao → `not-configured` |

> **Nota `stale`**: a 3a coluna do TSV do `guard-hooks-status.sh`
> (`current|stale|unknown`) faz "presente + registrado" NAO significar
> configurado. `stale` = copia do projeto diverge do catalogo, e o proprio
> `check` retorna exit 1 nesse caso (`_gh_cmd_check`, linhas 238-244).
> O wizard herda esse veredito: `stale` → `not-configured`.

> **Nota `divergent` (FR-016)**: distingue "a configuracao **nomeia** o
> controle" de "a configuracao **executa** o controle do catalogo". Para
> `hooks`, a 4a coluna do TSV ja compara o **conteudo** do arquivo com o
> catalogo (`cmp` byte-a-byte) — mas o **registro** e apenas presenca
> textual do basename no `settings.json` (`_gh_registered`,
> `guard-hooks-status.sh:119-127`), entao um registro que cita o basename
> e invoca outro programa e hoje indistinguivel de um legitimo. Para
> `mcp`, a deteccao originalmente desenhada era so a presenca da chave
> `cstk-state`. Em ambos, `divergent` NUNCA pode colapsar para
> `configured`: e o unico status que sinaliza um controle de seguranca
> possivelmente subvertido.
>
> **Fail-closed (invariante I5)**: jamais `configured` sob ambiguidade —
> mas ha DUAS ambiguidades distintas, com destinos diferentes no enum
> fechado de `status`/`mandatory_status` (`configured | not-configured |
> divergent | unavailable` — **nao ha valor `indeterminate` neste enum**,
> so na 5a coluna do TSV):
>
> - **Confirmacao positiva de nao-canonico** — a 5a coluna leu uma linha
>   real e concluiu que o registro nao bate com o fragmento canonico →
>   `divergent`. O custo de um falso `divergent` e um aviso com
>   remediacao; a garantia e "detectamos algo que nao reconhecemos".
> - **Impossibilidade de verificar** — layout do JSON que impeca atribuir
>   o registro (minificado), fonte de deteccao sem suporte a extensao
>   (runtime antigo, exit 2 em `_gh_die_usage` — mesmo caminho do
>   quickstart Scenario 15 variante 4), path irresolvivel: a 5a coluna
>   e/ou a chamada inteira retorna `indeterminate`, e **isso mapeia para
>   `unavailable`** no `status`/`mandatory_status` (achado SEC-02) —
>   nunca para `divergent` (nao houve confirmacao de nada) e nunca para
>   `configured`/`not-configured` herdado da chamada baseline (essa
>   heranca silenciosa era exatamente o fail-open do achado SEC-02: sem
>   mapeamento explicito, um implementador podia ignorar a 5a coluna
>   indeterminada e reportar o exit 0/1 cru da chamada baseline).
>
> Em ambos os casos o custo aceito e um falso aviso (`divergent` ou
> `unavailable`) com remediacao/motivo; o custo rejeitado e a falsa
> garantia de `configured` que este requisito existe para eliminar.

> **Nota `unavailable`**: dependencia faltando ou fonte de deteccao
> inutilizavel — ex. `sqlite3` ausente/abaixo de
> `_SB_MIN_SQLITE_VERSION="3.45.1"` (`state-backend.sh:67`), caso em que
> `enable-sqlite` recusaria com exit 3 (linhas 358-370) — **e tambem** o
> caso de `hooks` cuja 5a coluna (`--verify-registration`) resolveu
> `indeterminate` para algum hook obrigatorio (achado SEC-02, ver
> invariante I5 acima): a autenticidade do registro nao pode ser
> confirmada nem refutada, entao a area nunca anuncia `configured`. Area
> `unavailable` ainda e exibida e ainda entra no summary (FR-009/FR-010).

---

## Entity: HooksAreaDetail

Sub-estrutura da area `hooks`. Existe porque FR-008 exige que o hook
opt-in de loose usage seja uma escolha **distinta** da dos hooks
obrigatorios.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `mandatory_status` | enum | `configured` \| `not-configured` \| `divergent` \| `unavailable` | Base = exit da chamada **baseline** (sem flags) sobre os 3 hooks de `_GH_HOOKS` (`guard-hooks-status.sh:104-107`); a chamada `--verify-registration` (separada — SEC-03) so escala: `divergent` precede a base (FR-016), `indeterminate` precede a base e vira `unavailable` (SEC-02) — nunca ambas na mesma chamada da base |
| `mandatory_detail` | TSV lines | 3 linhas | `<arquivo>\t<present\|missing>\t<registered\|unregistered>\t<current\|stale\|unknown>\t<canonical\|divergent\|indeterminate>` — a 5a coluna so aparece com `--verify-registration` |
| `divergent_hooks` | lines | pode ser vazio | Basenames cuja 5a coluna != `canonical`; alimenta a remediacao exibida |
| `loose_usage_status` | enum | `configured` \| `not-configured` \| `divergent` \| `indeterminate` | `indeterminate` quando a fonte de deteccao nao suporta a consulta — ver research.md Decision 3 |
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
| `status=unavailable` | `failed`, `reason` = `status_reason` (dependencia ausente **ou**, para `hooks`, registro nao-verificavel — SEC-02) |
| `status=divergent` | `failed`, `reason` = remediacao (FR-016); **nenhuma** chamada de aplicacao — ver nota abaixo |
| Area `telemetry` diagnosticada e nao ativa | `skipped`, `reason` = "diagnostico exibido; ativacao e manual (FR-012)" |

> **Por que `divergent` → `failed`, e nao `applied` apos "corrigir"**: o
> wizard nao tem como corrigir, e nao deve tentar. Os comandos de
> aplicacao fazem merge com **o target vencendo** — `merge_settings` roda
> `jq -s '.[0] * .[1]'` com "Source primeiro, target segundo => target
> vence em conflitos" (`cli/lib/hooks.sh`), e `cstk mcp install` declara
> "entrada ja presente e equivalente => idempotente, exit 0"
> (`cli/lib/mcp.sh:800-802`). Logo **re-rodar `cstk hooks install` /
> `cstk mcp install` sobre uma entrada divergente NAO a substitui**: a
> entrada existente sobrevive ao merge. A remediacao correta, e a unica
> que o wizard deve imprimir, e em duas etapas: **(1)** remover a entrada
> divergente do `.claude/settings.json` / `.mcp.json`, **(2)** rodar
> `cstk hooks install --project-path <PATH>` / `cstk mcp install
> --project-path <PATH>` para reescrever a canonica.
>
> Mapear para `failed` tambem propaga exit `1` (`SetupRunSummary`), o que
> impede um run com controle de seguranca subvertido de terminar com o
> mesmo exit de um run limpo — requisito de SC-006.

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
   ├─────> divergent ──────────────────────────> failed   (remediacao; sem aplicacao)
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
- **I5 (FR-016, fail-closed)**: nenhuma transicao leva `divergent` a
  `already-configured` ou `applied`, em nenhum modo — inclusive `--yes`.
  Toda ambiguidade de apuracao resolve para `divergent`.
- **I6 (FR-016)**: a partir de `divergent` nao ha chamada de comando de
  aplicacao. O wizard nao sobrescreve o que nao reconhece; so relata e
  instrui.

---

## Defaults sob `--yes` (consolidado — CHK005)

Tabela unica "area → o que `--yes` (mode=non-interactive) de fato faz
quando a area esta `not-configured`", substituindo a dispersao anterior
em quatro locais (comentarios de `cli/lib/setup.sh` por area + esta
entidade + `tasks.md`). So se aplica a partir de `not-configured`:
`configured` nunca aplica (I1), e `divergent`/`unavailable` nunca aplicam
(I5/I6) — em nenhum modo, `--yes` incluido.

| `id` | Default sob `--yes` | Fonte (arquivo:linha) |
|------|----------------------|------------------------|
| `hooks` (obrigatorios) | **Sempre aplica** — `_srh_accept_mandatory` permanece `1` fora do `mode=interactive` (nenhum gate adicional) | `cli/lib/setup.sh:482-487` |
| `hooks` → `loose_usage` (opt-in) | **Sempre recusa** (`_srh_with_loose` permanece `0` fora do `mode=interactive`) — unica sub-area cujo default recomendado e "nao" | `cli/lib/setup.sh:498-503`; `data-model.md` linha `loose_usage_choice` acima |
| `state-backend` | **Condicional ao `reason`** (task 4.1.3/4.3.2, achado SEC-04): aplica so quando `reason` prova AUSENCIA de escolha previa (`nunca-configurado` ou `config-invalida`); qualquer outro `reason` (ex.: `json-explicito`) => nao aplica, preserva US2 AC3 | `cli/lib/setup.sh:725-734` |
| `mcp` | **Sempre aplica** — `_srm_accept` permanece `1` fora do `mode=interactive`; tenta `_mcp_cmd_install` mesmo sem Docker detectado (`command -v docker` so gera o TEXTO do aviso, nunca bloqueia — FR-015), sem opt-in distinto (ao contrario de `state-backend`) | `cli/lib/setup.sh:842-865` |
| `telemetry` | **N/A** — area 100% read-only (FR-012); `--yes` nao tem efeito nenhum, so o diagnostico de `otel-usage.sh preflight` e exibido; `applied` e INALCANCAVEL nesta area em qualquer modo | `cli/lib/setup.sh:973-978` |

> Nenhum destes defaults e overridable por flag dedicada (FR-018 — ver
> `contracts/cli-setup.md` §1, "Flags"): a unica alavanca de modo e a
> precedencia `--dry-run` > `--yes` > interativo (FR-006).
