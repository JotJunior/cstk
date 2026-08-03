# Data Model: Paridade Backend-Agnostica dos Hooks 00C

**Feature**: `hooks-db-parity`
**Fase**: 1 (Design)
**Data**: 2026-08-03

> Esta feature **nao cria nem altera nenhum schema persistido**. Ela troca a
> forma como um valor ja existente (`status` da execucao) e lido. As
> entidades abaixo sao, na maioria, estruturas ja em producao — descritas
> aqui porque a deteccao depende delas. Cada entidade indica se e
> `[EXISTENTE]` (verificada no codigo/schema real) ou `[PROPOSTA]` (nova,
> introduzida por esta feature).

## Visao geral

```
                     +---------------------------+
   stdin do harness  |  hook (1 dos 3)           |
   (HookInput) ----->|  pretooluse-bash-guard    |
                     |  posttooluse-tool-call... |
                     |  posttooluse-agent-usage  |
                     +------------+--------------+
                                  | source + chamada
                                  v
                     +---------------------------+
                     | ActiveExecutionProbe      |  [PROPOSTA]
                     | (_hook-active-exec.sh)    |
                     +------+-------------+------+
                            |             |
            backend JSON    |             |   backend SQLite
                            v             v
                +-------------------+  +---------------------+
                | state.json        |  | state.db            |
                | .execution.status |  | execution.status    |
                | [EXISTENTE]       |  | [EXISTENTE]         |
                +-------------------+  +---------------------+
```

---

## Entity: ActiveExecutionProbe [PROPOSTA]

Resultado da deteccao de execucao ativa. Nao e persistido — existe apenas
como valor de retorno (stdout + exit code) do helper
`_hook-active-exec.sh` durante uma invocacao de hook.

| Campo | Tipo | Obrigatorio | Descricao |
|-------|------|-------------|-----------|
| `outcome` | enum `ativa` \| `inativa` \| `indeterminada` | sim | codificado no **exit code** (0 / 1 / 2), nao em stdout |
| `execution_kind` | enum `agente-00c` \| `feature-00c` | so quando `outcome=ativa` | tipo da execucao vencedora da precedencia |
| `state_dir` | string (path absoluto) | so quando `outcome=ativa` | diretorio de estado da execucao vencedora |
| `backend` | enum `json` \| `sqlite` | so quando `outcome=ativa` | backend do state-dir vencedor; informativo para log/diagnostico |

**Serializacao** (stdout, uma unica linha, campos separados por TAB):

```
<execution_kind>\t<state_dir>\t<backend>
```

Quando `outcome != ativa`, stdout e **vazio** — o consumidor distingue os
casos exclusivamente pelo exit code.

### State transitions

```
                 +-- nenhum state-dir candidato --------------> inativa (1)
                 |
 varredura ------+-- todos os candidatos com status terminal --> inativa (1)
 dos state-dirs  |
                 +-- >=1 candidato com status ativo ----------> ativa (0)
                 |
                 +-- 0 ativos E >=1 state.db ilegivel --------> indeterminada (2)
```

Regra de desempate (FR-002, preservada de hoje):

1. `agente-00c` (`.claude/agente-00c-state/`) vence sobre qualquer
   `feature-00c`.
2. Entre `feature-00c` (`.claude/feature-00c-state/<short-name>/`), o menor
   `<short-name>` em ordem byte-wise (`LC_ALL=C sort`) vence.
3. Dentro de UM mesmo state-dir, `state.db` vence sobre `state.json`
   (paridade com `_sr_backend()` em `_state-rw-db.sh:53`).

Precedencia de `ativa` sobre `indeterminada`: um state-dir ilegivel **nao**
curto-circuita a varredura. `indeterminada` so e o resultado final se
nenhuma execucao ativa foi confirmada em nenhum candidato.

### Validation rules

- `outcome=ativa` MUST implicar `state_dir` existente e nao-vazio.
- `execution_kind=agente-00c` MUST implicar `state_dir` terminando em
  `/.claude/agente-00c-state`.
- Status considerados ativos: `em_andamento`, `aguardando_humano`
  (conjunto identico ao ja usado por `_pbg_is_active_status`,
  `_ptt_is_active_status` e `_pau_is_active_status`).
- Status `abortada` e `concluida` MUST resultar em nao-ativo. Ambos sao
  valores do `CHECK` da coluna `execution.status` no schema SQLite real.

---

## Entity: ExecutionStatusSource [EXISTENTE]

Origem do valor de `status`, por backend. Nenhuma alteracao de schema.

### Backend JSON [EXISTENTE]

| Item | Valor |
|------|-------|
| Arquivo | `<state-dir>/state.json` |
| Caminho do campo | `.execution.status` |
| Leitura | `jq -r '.execution.status // ""'` |
| Ausencia do arquivo | equivale a "sem execucao neste dir" |

### Backend SQLite [EXISTENTE]

| Item | Valor |
|------|-------|
| Arquivo | `<state-dir>/state.db` |
| Tabela | `execution` (1 linha por state-dir) |
| Coluna | `status TEXT NOT NULL` |
| Constraint | `CHECK (status IN ('em_andamento','aguardando_humano','abortada','concluida'))` |
| Leitura | `SELECT status FROM execution LIMIT 1;` |
| Abertura | `file:<db>?mode=ro` com fallback para path direto (research Decision 1.a) |

Schema verificado por inspecao direta (`sqlite3 .schema`) do `state.db` real
desta execucao. Colunas vizinhas relevantes para diagnostico futuro (nao
usadas pela deteccao): `current_stage`, `target_project_path`, `short_name`.

---

## Entity: HookInput [EXISTENTE]

JSON entregue pelo harness do Claude Code no **stdin** de cada hook. Campos
efetivamente consumidos pelos tres hooks (verificados no codigo-fonte):

| Campo | Tipo | Consumido por | Uso |
|-------|------|---------------|-----|
| `cwd` | string | os 3 hooks | raiz a partir da qual `.claude/...` e resolvido |
| `tool_name` | string | os 3 hooks | defesa redundante do matcher |
| `tool_input.command` | string | `pretooluse-bash-guard` | comando submetido a `bash-guard.sh check` |
| `tool_input.subagent_type` | string | `posttooluse-agent-usage` | tipo do subagente spawnado |
| `tool_response.*` | objeto | `posttooluse-agent-usage` | `agentId`, `status`, `totalTokens`, `usage.*`, `totalToolUseCount`, `totalDurationMs`, `resolvedModel`, `modelsUsed` |

Esta feature **nao altera** o consumo de nenhum desses campos. Detalhe do
contrato de I/O em `contracts/hook-io.md`.

---

## Entity: EnforcementDecisionLog [EXISTENTE]

Linha JSONL append-only em `<cwd>/.claude/enforcement-log.jsonl`, gravada
apenas pelo `pretooluse-bash-guard.sh` e apenas quando ha execucao ativa
detectada. Campos (de `_pbg_write_log`):

| Campo | Tipo | Notas |
|-------|------|-------|
| `source` | string | `"pretooluse-bash-guard"` |
| `timestamp` | string ISO 8601 UTC | |
| `outcome` | enum | `allowed` \| `blocked-by-rule` \| `blocked-mechanism-failure` |
| `command` | string \| null | passa por `secrets-filter.sh scrub` **antes** de truncar em 500 chars |
| `reason` | string \| null | scrubbed |
| `category` | string \| null | slug da regra violada, ou `mechanism-error` |
| `detected_execution` | string \| null | `agente-00c` \| `feature-00c` |
| `detected_execution_path` | string \| null | path do state consultado |

**Impacto desta feature**: o campo `detected_execution_path` passa a poder
apontar para um `state.db` (hoje sempre um `state.json`). Nenhum campo novo,
nenhuma mudanca de tipo. Consumidores que fazem parse por extensao de
arquivo desse campo precisariam ajustar — nenhum consumidor assim foi
encontrado no repositorio.

---

## Entity: WaveTickSidecar [EXISTENTE]

| Item | Valor |
|------|-------|
| Arquivo | `<state-dir>/tool-call-ticks.log` |
| Formato | 1 linha por tick: timestamp ISO 8601 UTC |
| Escritor | `posttooluse-tool-call-tick.sh` (append `O_APPEND`) |
| Leitor/agregador | `state-ondas.sh end`, `budget.sh check\|status` (`wc -l`) |
| Ciclo de vida | resetado por `state-ondas.sh start` e `end` |

**Impacto desta feature**: passa a ser efetivamente escrito tambem em
state-dirs SQLite (hoje: nunca). Formato inalterado. O sidecar vive **ao
lado** do `state.db`, no mesmo state-dir — nao dentro dele, nao no
documento.

---

## Entity: WaveAgentUsageSidecar [EXISTENTE]

| Item | Valor |
|------|-------|
| Arquivo | `<state-dir>/wave-agent-usage.jsonl` |
| Formato | 1 objeto JSON (SpawnUsage) por linha |
| Permissao | criado sob `umask 077` (0600) + `chmod 600` best-effort |
| Teto | 500 linhas por onda; sentinela `.wave-agent-usage-cap-warned` evita aviso repetido |
| Escritor | `posttooluse-agent-usage.sh` |
| Ciclo de vida | resetado por `state-ondas.sh start`/`end` |

**Impacto desta feature**: idem — passa a ser escrito tambem sob backend
SQLite. Nenhuma mudanca de formato, permissao ou teto.

---

## Nao-entidades (fora de escopo explicito)

- **Nenhuma tabela nova** no `state.db`. A deteccao so **le** a coluna
  `execution.status` ja existente.
- **Nenhum campo novo** no `state.json`.
- **Nenhum arquivo novo dentro do state-dir**. Os unicos artefatos que a
  execucao dos hooks pode criar no state-dir sob backend SQLite sao
  `state.db-shm` / `state.db-wal`, gerados pelo proprio motor SQLite no
  caminho de fallback (research Decision 1.a) — internos do motor, nao
  espelho de estado.
