# Quickstart: Allowlist MCP para orquestradores 00c

**Feature**: `orchestrator-mcp-allowlist` | **Date**: 2026-08-16

Cenarios de validacao. Os cenarios 1-4 rodam na suite POSIX (automatizados).
Os cenarios 5-6 sao **manuais** e exigem harness vivo + Docker — ver
research Decision 10.

---

## Cenario 1 — A premissa errada nao bloqueia mais (FR-001, SC-005)

1. Aplicar FR-003 (adicionar as 7 tools `mcp__cstk-state__*` ao frontmatter
   dos 2 orquestradores).
2. Rodar `./tests/run.sh orchestrator`.

**Expected**: verde. Nenhum scenario falha pela mera presenca de `mcp__*`
no frontmatter — os dois scenarios revogados
(`scenario_orchestrator_agente_nao_lista_tool_mcp` e
`scenario_orchestrator_feature_nao_lista_tool_mcp`, hoje em
[tests/test_orchestrator-mcp-fallback.sh:59-75]) nao existem mais.

**Contra-prova de que o teste antigo era inerte** (rodar ANTES da remocao,
opcional): adicionar `mcp__cstk-state__get_status` a linha inline `tools:`
e rodar a suite — ela passa mesmo assim, porque a ERE `^\s*-\s*mcp__`
[tests/test_orchestrator-mcp-fallback.sh:61] so casa a forma de lista.

---

## Cenario 2 — Guard bloqueia allowlist so-MCP (FR-002, SC-003)

1. Criar fixture temporaria (`mktemp -d`) com um arquivo
   `x-orchestrator.md` cujo frontmatter seja
   `tools: mcp__cstk-state__open_wave, mcp__cstk-state__get_status`.
2. Apontar o guard para o diretorio da fixture.

**Expected**: FAIL com violacao `mcp_only_allowlist`.

3. Repetir com a mesma allowlist na **forma de lista YAML**
   (`tools:` + linha `- mcp__cstk-state__open_wave`).

**Expected**: FAIL identico — o guard novo cobre as duas formas.

4. Repetir com `tools:` sem nenhuma entrada.

**Expected**: FAIL com `empty_allowlist`.

---

## Cenario 3 — Guard aprova allowlist mista (FR-002 AS-3, FR-004)

1. Fixture com `tools: Bash, mcp__cstk-state__open_wave`.

**Expected**: PASS.

2. Rodar o guard contra os arquivos REAIS do repo apos FR-003.

**Expected**: PASS nos 2 orquestradores; `Bash` presente em ambos
(FR-004); as 7 tools presentes em ambos (FR-003).

---

## Cenario 4 — Paridade da orientacao (FR-011)

1. Editar o bloco entre `<!-- MCP-VS-BASH:BEGIN -->` e
   `<!-- MCP-VS-BASH:END -->` em **apenas um** dos dois orquestradores
   (ex.: trocar uma palavra).
2. Rodar `./tests/run.sh orchestrator-allowlist`.

**Expected**: FAIL do `scenario_guidance_block_paridade`, com diff
apontando a linha divergente.

3. Reverter a edicao.

**Expected**: PASS.

---

## Cenario 5 — [MANUAL] Degradacao graciosa com MCP ausente (FR-007, SC-001)

Preserva o invariante SC-004 da feature `state-mcp-server`
[FONTE: spec.md:299-304].

1. Garantir Docker parado (ou `cstk mcp stop --state-dir <SD>`).
2. Iniciar uma execucao autonoma real: `/feature-00c <alguma-feature>`.
3. Observar o prompt de spawn: sem token, o command NAO menciona MCP
   [FONTE: plugins/cstk/commands/feature-00c.md:740-741].

**Expected**: a onda completa normalmente via helpers Bash. Nenhum
bloqueio humano, nenhuma intervencao manual, nenhuma mensagem de erro de
MCP visivel ao operador. As tools `mcp__cstk-state__*` aparecem na
allowlist do agente mas nao resolvem — e sao descartadas em silencio
(research Decision 2, item 2).

---

## Cenario 6 — [MANUAL] Roteamento por token no caminho real (FR-008, SC-004)

Este e o unico cenario que fecha FR-008: exige **chamada real originada de
um subagente orquestrador**, o que a suite POSIX nao produz
(research Decision 10).

**Pre-condicoes**: Docker disponivel; `cstk mcp status --live` reporta
`mode=docker`/`status=active`; DUAS execucoes 00c ativas com state-dirs
distintos (A e B).

### 6a — Token correto e aceito

1. Spawnar o orquestrador da execucao A (o command pai injeta o
   `session_id` de A no prompt
   [FONTE: plugins/cstk/commands/feature-00c.md:734-739]).
2. Fazer o orquestrador chamar `mcp__cstk-state__get_status` apresentando o
   `session_id` de A.

**Expected**: chamada aceita; resposta reflete o estado de A. `state.json`/
`state.db` de B intocado (comparar sha256 antes/depois).

### 6b — Token de outra execucao e rejeitado

1. Repetir a chamada apresentando o `session_id` de **B** a partir do
   orquestrador de A.

**Expected**: `SESSION_MISMATCH`, fail-closed. Nenhum state-dir alterado.

### 6c — Token ausente e rejeitado

1. Repetir sem `session_id`.

**Expected**: rejeicao (o schema exige `session_id` nao-vazio
[FONTE: mcp/state-server/src/tools/open_wave.ts:31-33 — `session_id:
z.string().min(1, "session_id obrigatorio")`]). Nenhum state-dir alterado.

### Registro do resultado

O resultado deste cenario MUST ser registrado como Decisao auditavel com
`--score 3` e `--evidencia` contendo **saida literal observada** das tres
chamadas. Sem a saida literal, registrar `--score 0` e NAO afirmar FR-008
como satisfeito (Principio VI / guard anti-confabulacao).

---

## Cenario 7 — [MANUAL] Erro pontual com servidor ativo (FR-006, dec-018)

1. Com o servidor ativo, provocar falha de UMA chamada (ex.: parar o
   container entre duas chamadas da mesma onda).

**Expected**: o orquestrador NAO tenta novamente. Faz 1 confirmacao via
`cstk mcp status --live` e comuta para Bash pelo **resto da onda**
[FONTE: plugins/cstk/commands/feature-00c.md:737-739]. A onda fecha
normalmente; nenhum bloqueio humano.

---

## Fora de escopo desta rodada

`elicitation/create` (FR-010, Deferred) — nenhum cenario de validacao e
definido aqui, por decisao explicita da spec [FONTE: spec.md:266-279].
Nota factual: nenhuma das 7 tools do `cstk-state` depende de elicitation
(research Decision 9), entao os cenarios 5-7 nao sao afetados pelo defer.
