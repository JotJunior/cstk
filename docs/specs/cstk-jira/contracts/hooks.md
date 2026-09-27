# Contract: hooks do plugin cstk-jira (`plugins/cstk-jira/hooks/hooks.json`)

Implementa o gatilho do sync autonomo (arquitetura A1 / dec-020; FR-005,
FR-018-INFRA-SCHED) e a guarda de exclusao (FR-012).

## Fontes

| Fato usado | Fonte |
|------------|-------|
| Plugin declara hooks em `hooks/hooks.json`, ativos quando o plugin esta habilitado | https://code.claude.com/docs/en/hooks-guide.md — "Plugin `hooks/hooks.json` \| When plugin is enabled" |
| `matcher` e regex JavaScript nao-ancorada; casa tools MCP por padrao `mcp__.*__<tool>` | mesma pagina — "Other characters trigger JavaScript regex evaluation (unanchored)"; "match across servers with a pattern like `mcp__.*__write.*`" |
| stdin do hook traz `session_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input` | mesma pagina — "`hook_event_name`, `tool_name`, `tool_input`: the arguments Claude passed to the tool" |
| `tool_input.command` para a tool Bash | uso local observado: `plugins/cstk/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh` L371 |
| `timeout` em segundos; hooks casados rodam em paralelo; `exit 2` bloqueia a acao | hooks-guide — "runs all matching hooks in parallel"; "`exit 2` is the only code that blocks on its own" |
| `"async": true` roda o hook em background sem bloquear; timeout nao e aplicado a async | hooks-guide — "`async: true` to run in background without blocking"; "Not enforced for async" |
| `${CLAUDE_PLUGIN_ROOT}` no comando do hook | uso local observado: `plugins/cstk/hooks/hooks.json` |
| Argumentos do `record_task` MCP: `task_id`, `outcome` (`pass`/`fail`) | `plugins/cstk/mcp/state-server/src/tools/record_task.ts` L59-62 |
| Flags do caminho Bash: `state-ondas.sh record-task ... --task-id ID --outcome pass\|fail` e `state-ondas.sh end` | `plugins/cstk/skills/agente-00c-runtime/scripts/state-ondas.sh` L111, L1184-1187 (record-task); L23 (end) |
| Execucao ativa marcada pelo diretorio `<state-dir>/.lock/` (dono grava `owner`) | `plugins/cstk/skills/agente-00c-runtime/scripts/state-lock.sh` L10-11, L170 |

`NAO ENCONTRADO` na doc oficial: schema completo de `tool_response` do
PostToolUse e se um processo filho de hook async sobrevive ao hook. Por isso o
contrato abaixo NAO depende de `tool_response` nem de processo orfao.

## Entradas do `hooks.json` [DESIGN deste plano]

| Evento | matcher (regex) | Script | async | Papel |
|--------|-----------------|--------|-------|-------|
| `PreToolUse` | `mcp__.*__(deleteJiraIssue\|executeDestructive)` | `hooks/pretooluse-jira-deny-destructive.sh` | nao | FR-012: bloqueia (exit 2) exclusao via Rovo MCP, qualquer prefixo de instalacao |
| `PostToolUse` | `mcp__.*__record_task` | `hooks/posttooluse-jira-sync.sh task` | sim | enfileira outcome da task e drena |
| `PostToolUse` | `mcp__.*__close_wave` | `hooks/posttooluse-jira-sync.sh wave` | sim | reconcilia a feature e drena (garante SC-003 "ate o fim da onda") |
| `PostToolUse` | `Bash` | `hooks/posttooluse-jira-sync.sh bash` | sim | caminho Bash dos orquestradores: so age se `tool_input.command` contem `state-ondas.sh record-task` ou `state-ondas.sh end` |

A guarda `PreToolUse` tambem nega por prefixo qualquer nome terminado em
`deleteJiraIssue`, porque o prefixo da tool depende de como o usuario
instalou o Rovo MCP (research Decision 1).

## Comportamento de `posttooluse-jira-sync.sh`

POSIX sh, sem `jq`/cliente HTTP no proprio arquivo (carve-out 1.1.0,
condicao b: so `scripts/jira-io.sh` referencia essas ferramentas).

1. **No-op de inatividade (FR-017, SC-006)** — primeira instrucao: se
   `<cwd>/.claude/cstk-jira/config` nao existe OU `sync_autonomous=off`, exit 0
   silencioso, stdout vazio, sem ler stdin alem do necessario, sem checar deps.
2. **Resolucao da execucao ativa**: exatamente um diretorio
   `<cwd>/.claude/feature-00c-state/<short>/.lock/` => feature = `<short>`;
   `<cwd>/.claude/agente-00c-state/.lock/` => feature = nome canonico do
   projeto (mesma derivacao usada pelo orquestrador: `.execution.canonical_project`
   com fallback `basename(target_project_path)` —
   `plugins/cstk/agents/agente-00c-orchestrator.md` L690-702, lido
   READ-ONLY). Zero ou mais de um candidato => no-op + linha em
   `runtime/hook.log`.
3. **Filtro de feature convertida**: sem `docs/specs/<feature>/jira-map.tsv` =>
   no-op (feature nunca convertida — US1 e pre-requisito do US3).
4. **Enfileirar** OutboxEvent (`data-model.md`) com `task_id`/`outcome`
   extraidos do `tool_input` (modo `task`/`bash`) ou `reconcile` (modo `wave`).
5. **Drenar** via `scripts/jira-sync.sh drain --feature <f>` com lock proprio
   (`runtime/.drain.lock/`, `mkdir` atomico): escritas serializadas por
   projeto (research Decision 3: transicoes simultaneas na mesma issue
   falham). Lock ocupado => sai; o proximo gatilho drena. O diagnostico de
   stderr do drain (gate `auth_failed`/FR-016, ProjectConfig invalido,
   conflito detectado) e anexado a `runtime/hook.log` (nao descartado) —
   FASE 12 tarefa 12.7.1.
5.bis **Resumo** (`data-model.md` Entity ConflictRecord — "consumido ...
   pelo resumo emitido pelo hook no fechamento de onda"; task 13.4.1): apos
   o drain, um `scripts/jira-sync.sh status --feature <f>` (100% LOCAL, sem
   rede/titulo do Jira) alimenta uma linha de resumo em `runtime/hook.log`
   quando `deferred`/`auth_failed` do outbox OU `pending` de ConflictRecords
   nao estao todos zerados. A contagem de conflito (`conflict=N` na linha
   de resumo) vem do `pending=N` de ConflictRecords PENDENTES
   (`runtime/conflicts.tsv`, exposto por `jira-sync.sh status`), NUNCA do
   `conflict=` do outbox: esse `pending=N` cobre TODA origem de conflito
   (drain direto, reconcile via `close_wave`, `convert`) e nunca acusa um
   conflito ja fechado por `resolve` (qualquer `--choice`) so porque um
   evento outbox `conflict` remanescente ainda existe. Sinaliza credencial
   expirada ou conflito pendente sem exigir `jira-sync status` manual.
6. **Fail-open absoluto**: qualquer falha => exit 0. O hook NUNCA bloqueia,
   atrasa ou falha a tool do orquestrador e NUNCA escreve no state da execucao
   (mesma politica de `posttooluse-tool-call-tick.sh`, que documenta a corrida
   com writes transacionais).
7. **Nao-exfiltracao**: `tool_input` do `record_task`/`close_wave` carrega
   `session_id` (token de capacidade do servidor de estado). O hook le SO
   `task_id`/`outcome`; nunca grava, loga ou repassa `session_id`.

## Comportamento de `pretooluse-jira-deny-destructive.sh`

Politica INVERSA (guarda, nao metrica): casou => mensagem em stderr citando
FR-012 e `exit 2`. Sem `<cwd>/.claude/cstk-jira/config` a guarda e no-op
(exit 0): quem instalou o plugin mas nunca o configurou pode estar usando o
Rovo MCP para outros fins, e bloquear exclusao ali seria mudanca de
comportamento vedada por FR-017/SC-006.

## Round r02 (2026-09-26) — mudancas (FR-023, FR-024, FR-020..FR-025)

`[PROPOSTA — a validar na implementacao]`, ADITIVO ao desenho acima.

**`hooks.json` — entrada nova**

| Evento | matcher (regex) | Script | async | Papel |
|--------|-----------------|--------|-------|-------|
| `PreToolUse` | `mcp__.*__createJiraProject` | `hooks/pretooluse-jira-deny-destructive.sh` (modo `project-create`) | nao | FR-024: nega (exit 2) criacao de projeto via Rovo MCP quando ha execucao 00c ATIVA no cwd (mesma deteccao de `.lock` do passo 2 abaixo) E o plugin esta configurado. Sessao interativa sem execucao ativa: nao interfere (o prompt de permissao do proprio Claude Code + a confirmacao da skill `jira-setup` sao o gate) |

Limite honesto: sem ProjectConfig a guarda segue no-op (FR-017/SC-006 — o
plugin nao pode mudar o comportamento de quem nunca o configurou), entao o
PRIMEIRO setup dentro de uma execucao autonoma depende da regra da skill
(`jira-setup` nunca cria em contexto autonomo, devolve o pedido de gate ao
orquestrador) e do `create-project` exigir `--consent-block`.

**`posttooluse-jira-sync.sh` — passos alterados**

- **Passo 1 (inatividade)**: o teste de existencia usa
  `jira-config.sh resolve-path` (cwd, senao worktree principal — FR-023).
  Sem `git` no PATH, so o cwd e considerado (sem fallback, sem erro).
- **Passo 2 (execucao ativa)**: inalterado. FR-023 NAO exige branch novo:
  cada execucao paralela do roadmap roda na propria worktree, com 1 `.lock`
  no proprio cwd => resolve a propria `short_name` => sincroniza o proprio
  Epic. Sem roadmap, caso base FR-001.
- **Passo 4 (modo `wave`)**: o evento `reconcile` tambem executa, no drain,
  a reaplicacao do marco corrente ao Epic, o ajuste de `phase-<N>` e
  `jira-sync.sh links` (`plugin-scripts.md` r02). Modo `task`/`bash`:
  inalterado (so transicao de status — nada de marco/label/link por task,
  para nao multiplicar escritas por `record_task`).
- **Passo 5.bis (resumo)**: a linha de resumo passa a incluir
  `milestone=` quando `unresolved`/`blocked:*` e `links_unrepresentable=`/
  `links_stale=` quando > 0 — mesma regra de omissao no caminho feliz.

Inalterados: fail-open absoluto (passo 6), nao-exfiltracao de `session_id`
(passo 7), nenhuma escrita no state da execucao, o hook NUNCA cria projeto
nem responde gate humano (so enfileira/drena sync dentro de projeto ja
configurado).
