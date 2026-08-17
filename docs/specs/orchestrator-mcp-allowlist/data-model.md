# Data Model: Allowlist MCP para orquestradores 00c

**Feature**: `orchestrator-mcp-allowlist` | **Date**: 2026-08-16

> Feature sem persistencia: nao cria tabela, coluna, campo de `state.json`/
> `state.db` nem entrada em `knowledge.db`. As "entidades" abaixo sao
> estruturas **derivadas de arquivos versionados** (frontmatter de agente e
> resultado de parsing), modeladas aqui porque o guard de FR-002 opera sobre
> elas. Nenhuma delas e serializada em disco pelo guard.

## Entity: OrchestratorAgentFile

Arquivo de definicao de agente reconhecido como orquestrador autonomo.

| Campo | Tipo | Origem | Notas |
|-------|------|--------|-------|
| `path` | string | glob `plugins/cstk/agents/*-orchestrator.md` | descoberto por padrao de nome (dec-016) [FONTE: spec.md:212-220] |
| `name` | string | chave `name:` do frontmatter | ex.: `agente-00c-orchestrator` [FONTE: plugins/cstk/agents/agente-00c-orchestrator.md:2] |
| `frontmatter_block` | texto | linhas entre o 1o e o 2o `---` | delimitacao obrigatoria: o parser NUNCA le fora deste bloco (research Decision 4) |
| `allowlist` | `AllowlistDeclaration` | chave `tools:` do frontmatter | ver entidade abaixo |
| `guidance_block` | `GuidanceBlock` \| ausente | entre os marcadores MCP-VS-BASH | ver entidade abaixo |

**Instancias reais no repo hoje** (2 de 7 arquivos de agente)
[FONTE: `ls plugins/cstk/agents/`]:

- `plugins/cstk/agents/agente-00c-orchestrator.md`
- `plugins/cstk/agents/agente-00c-feature-orchestrator.md`

Os outros 5 (`*-clarify-asker`, `*-clarify-answerer` x2 escopos,
`data-veracity-verifier`) NAO casam o padrao e ficam fora do guard.

## Entity: AllowlistDeclaration

Resultado do parsing da chave `tools:` de um `OrchestratorAgentFile`.

| Campo | Tipo | Notas |
|-------|------|-------|
| `declared` | bool | `false` quando a chave `tools:` esta ausente do frontmatter |
| `form` | enum `inline` \| `list` | `inline` = `tools: A, B, C`; `list` = `tools:` + linhas `- A`. O parser suporta as DUAS (research Decision 1/4) |
| `entries` | string[] | nomes normalizados (trim de espacos, entradas vazias descartadas) |
| `native_entries` | string[] | subconjunto de `entries` que NAO comeca com `mcp__` |
| `mcp_entries` | string[] | subconjunto de `entries` que comeca com `mcp__` |

**Estado atual (antes de FR-003)** [FONTE: plugins/cstk/agents/agente-00c-orchestrator.md:4
e plugins/cstk/agents/agente-00c-feature-orchestrator.md:4 — linha identica
nos dois]:

```
declared = true; form = inline
entries        = [Agent, Skill, Bash, Read, Write, Edit, Glob, Grep]
native_entries = [Agent, Skill, Bash, Read, Write, Edit, Glob, Grep]
mcp_entries    = []
```

**Estado alvo (apos FR-003)** — `native_entries` inalterado (FR-003 exige
adicao, "nunca em substituicao" [FONTE: spec.md:221-224]), `mcp_entries` com
as 7 tools (research Decision 5):

```
mcp_entries = [mcp__cstk-state__open_wave, mcp__cstk-state__record_decision,
               mcp__cstk-state__record_skill, mcp__cstk-state__record_task,
               mcp__cstk-state__register_human_block,
               mcp__cstk-state__close_wave, mcp__cstk-state__get_status]
```

### Regra de nomeacao de entrada MCP

`mcp__<server_key>__<tool_name>`, onde:

| Parte | Valor | Fonte da verdade |
|-------|-------|------------------|
| `server_key` | `cstk-state` | `.mcp.json` chave sob `mcpServers` [FONTE: .mcp.json:3] |
| `tool_name` | um dos 7 | `server.registerTool` em [FONTE: mcp/state-server/src/index.ts:153,169,185,201,217,236,252] |

## Entity: GuardVerdict

Resultado da avaliacao de um `OrchestratorAgentFile` pelo guard de FR-002.
Nao persistido — emitido como PASS/FAIL do scenario.

| Campo | Tipo | Notas |
|-------|------|-------|
| `target` | string | `path` do arquivo avaliado |
| `outcome` | enum `pass` \| `fail` | conjunto fechado |
| `violation` | enum \| `null` | `tools_key_absent` \| `empty_allowlist` \| `mcp_only_allowlist` \| `no_orchestrator_found` |

### State transitions (tabela de decisao do guard)

Derivada literalmente de FR-002 e FR-004 (ver research Decision 4):

| `declared` | `entries` | `native_entries` | outcome | violation |
|-----------|-----------|------------------|---------|-----------|
| false | — | — | fail | `tools_key_absent` |
| true | vazio | vazio | fail | `empty_allowlist` |
| true | nao-vazio | vazio | fail | `mcp_only_allowlist` |
| true | nao-vazio | nao-vazio | pass | `null` |

Mais um veredito de nivel de suite, independente de arquivo:

| Condicao | outcome | violation |
|----------|---------|-----------|
| glob `*-orchestrator.md` casa 0 arquivos | fail | `no_orchestrator_found` |

## Entity: GuidanceBlock

Bloco de orientacao MCP-vs-Bash exigido por FR-005/FR-006, duplicado
deliberadamente nos dois orquestradores (dec-017).

| Campo | Tipo | Notas |
|-------|------|-------|
| `begin_marker` | literal | `<!-- MCP-VS-BASH:BEGIN -->` [PROPOSTA — a validar na implementacao] |
| `end_marker` | literal | `<!-- MCP-VS-BASH:END -->` [PROPOSTA — a validar na implementacao] |
| `body` | texto | conteudo entre os marcadores, exclusive |
| `self_contained` | invariante | nao pode conter referencia a um orquestrador especifico (nome do agente, layout de state-dir, command pai) — pre-condicao para a byte-identidade |

### Invariante de paridade (FR-011)

`body(agente-00c-orchestrator.md)` == `body(agente-00c-feature-orchestrator.md)`,
byte a byte apos remocao de whitespace terminal de linha. Divergencia =
FAIL do scenario de paridade [FONTE: spec.md:280-284].

### Conteudo minimo obrigatorio do `body`

Cada item abaixo e um requisito de conteudo verificavel, com a fonte que o
torna obrigatorio:

| # | Conteudo obrigatorio | Fonte |
|---|----------------------|-------|
| 1 | Quando preferir MCP: ha `session_id` no prompt de spawn e a tool esta visivel | FR-005 [FONTE: spec.md:230-235] |
| 2 | Toda chamada apresenta o `session_id` da propria execucao | [FONTE: plugins/cstk/commands/feature-00c.md:737 — "apresentando ESTE session_id em cada chamada"] |
| 3 | Deteccao de indisponibilidade: servidor ausente, tool nao resolvida, sessao nao autenticada, erro pontual com servidor ativo | FR-006 [FONTE: spec.md:236-246] |
| 4 | Erro pontual ⇒ fallback imediato, **0 retries** + 1 confirmacao via `cstk mcp status --live` + Bash no resto da onda | FR-006 / dec-018 [FONTE: plugins/cstk/commands/feature-00c.md:737-739] |
| 5 | Sem `session_id` no prompt ⇒ caminho Bash direto, sem mencionar MCP | [FONTE: plugins/cstk/commands/feature-00c.md:740-741] |
| 6 | O caminho Bash e sempre alternativa segura e NUNCA pausa a onda | FR-006/FR-007 [FONTE: spec.md:247-252] |
| 7 | Mapa das 7 operacoes ⇄ helper POSIX equivalente | FR-005 ("caminho nativo equivalente para a mesma operacao") [FONTE: spec.md:230-235] |
| 8 | `elicitation/create` fora de escopo de uso ativo enquanto FR-010 estiver Deferred | FR-010 [FONTE: spec.md:276-279] |
| 9 | **Nao-exfiltracao do `session_id`**: o token nunca e escrito em artefato, log, mensagem de commit, relatorio, Decisao, nem passado como argumento de qualquer tool que nao seja a propria chamada `mcp__cstk-state__*` | gate `owasp-security` finding F1 (LLM02/LLM07/ASI03); extensao natural de [FONTE: plugins/cstk/commands/feature-00c.md:742-744 — "O token NUNCA e ecoado em stdout/stderr/logs do command — vive apenas no descritor (`chmod 600`) e no prompt do spawn"] |

### Mapa operacao ⇄ caminho nativo (item 7)

Fonte da equivalencia: cada tool delega ao helper POSIX correspondente —
por exemplo `open_wave` "delega para ... `state-ondas.sh start --state-dir <SD>`"
[FONTE: mcp/state-server/src/tools/open_wave.ts:3-6].

| Tool MCP | Helper(s) nativo(s) equivalente(s) | Fonte |
|----------|-----------------------------------|-------|
| `open_wave` | `state-ondas.sh start --state-dir <SD>` | [FONTE: mcp/state-server/src/tools/open_wave.ts:3-6] |
| `close_wave` | `state-ondas.sh end --state-dir <SD> --motivo-termino <M>` (+ `secrets-filter.sh for-backup` e `state-rw.sh sha256-update` no mesmo fechamento) | [FONTE: mcp/state-server/src/tools/close_wave.ts:4-11] |
| `record_skill` | `state-ondas.sh record-skill --state-dir <SD> --skill NAME` | [FONTE: mcp/state-server/src/tools/record_skill.ts:4-6] |
| `record_task` | `state-ondas.sh record-task --state-dir <SD> --task-id --outcome` | [FONTE: mcp/state-server/src/tools/record_task.ts:4-6] |
| `record_decision` | `state-decisions.sh register --state-dir <SD> --agente A --etapa E` | [FONTE: mcp/state-server/src/tools/record_decision.ts:4-6] |
| `register_human_block` | `bloqueios.sh register --state-dir <SD> --decisao-id --pergunta` | [FONTE: mcp/state-server/src/tools/register_human_block.ts:4-6] |
| `get_status` | `state-rw.sh get --field '.execution.status'` / `'.current_stage'` + `state-ondas.sh wave-status` (leituras puras) | [FONTE: mcp/state-server/src/tools/get_status.ts:5-8] |

> Todas as sete linhas foram lidas do cabecalho `// Delega para
> [VERIFICADO...]` do respectivo arquivo de tool — nenhuma foi inferida por
> analogia. `close_wave` e `get_status` delegam a mais de um helper; o bloco
> de orientacao MUST preservar essa nuance em vez de simplificar para 1:1.
