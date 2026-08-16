# Implementation Plan: Allowlist MCP para orquestradores 00c

**Feature**: `orchestrator-mcp-allowlist` | **Date**: 2026-08-16
**Spec**: [spec.md](./spec.md)

## Summary

Os dois orquestradores autonomos do toolkit nao conseguem chamar o servidor
MCP de estado — nao por indisponibilidade do servidor, mas porque nenhuma
tool `mcp__cstk-state__*` consta do proprio frontmatter `tools:`
[FONTE: plugins/cstk/agents/agente-00c-orchestrator.md:4 e
plugins/cstk/agents/agente-00c-feature-orchestrator.md:4]. Os commands que
os spawnam ja mandam "Prefira as tools mcp__cstk-state__*"
[FONTE: plugins/cstk/commands/feature-00c.md:734-736 e
plugins/cstk/commands/agente-00c.md:493-495] — instruindo o uso de tools
que a allowlist nunca expos.

A abordagem tem quatro movimentos, nesta ordem:

1. **Revogar a premissa errada** (FR-001): remover os dois scenarios que
   proibem `mcp__*` no frontmatter
   [FONTE: tests/test_orchestrator-mcp-fallback.sh:59-75]. Achado do
   Phase 0: esse guard ja era **estruturalmente inerte** — sua ERE
   `^\s*-\s*mcp__` [FONTE: :61 e :70] so casa a forma de lista YAML,
   enquanto os 7 arquivos de agente do repo usam a forma inline. Ele nunca
   teria barrado a mudanca que proibia (research Decision 1).
2. **Substituir por um guard sobre a garantia real** (FR-002/FR-012):
   allowlist de orquestrador nunca vazia e nunca so-MCP, com alvos
   descobertos por glob `*-orchestrator.md` (dec-016) e parser que cobre as
   DUAS formas de YAML, sem `jq`.
3. **Expor as 7 tools** (FR-003/FR-004): adicionar
   `mcp__cstk-state__{open_wave,record_decision,record_skill,record_task,register_human_block,close_wave,get_status}`
   ao frontmatter dos dois agentes, preservando integralmente as 8 tools
   nativas atuais.
4. **Documentar a decisao de caminho** (FR-005/FR-006/FR-011): bloco
   autocontido e byte-identico nos dois agentes, delimitado por marcadores
   estaveis, prescrevendo fallback imediato sem retry (dec-018).

FR-010 (elicitation) permanece **Deferred** e nao recebe desenho nesta
rodada, por determinacao da propria spec [FONTE: spec.md:266-279].

## Technical Context

**Language/Version**: POSIX `sh` (harness de testes) + Markdown com
frontmatter YAML (definicoes de agente). Nenhum codigo de aplicacao muda.
**Primary Dependencies**: nenhuma nova. O guard usa apenas `sh`, `awk`,
`sed`, `grep` — deliberadamente **sem `jq`** (research Decision 4).
**Storage**: N/A — feature nao persiste dado (ver `data-model.md`).
**Testing**: harness proprio do repo, `./tests/run.sh`
[FONTE: CLAUDE.md §"Como testar scripts shell"].
**Target Platform**: macOS/Linux; sem dependencia de GNU-only.
**Project Type**: toolkit de skills/agents distribuido como catalogo +
plugin nativo do Claude Code.
**Performance Goals**: N/A — guard estatico sobre 2 arquivos; custo
desprezivel no gate de release.
**Constraints**: (a) o guard NAO pode depender de `jq`, sob pena de virar
no-op quando `jq` falta, como acontece hoje no arquivo que hospeda o guard
antigo [FONTE: tests/test_orchestrator-mcp-fallback.sh:52-55]; (b) FR-008
exige validacao por chamada real originada de subagente, o que exige Docker
e nao pode entrar no gate de release (research Decision 10).
**Scale/Scope**: 2 arquivos de agente editados, 1 arquivo de teste editado,
1 arquivo de teste criado, 1 ramo adicionado em `tests/run.sh`.

## Constitution Check

*GATE: passou antes do Phase 0; re-checado apos Phase 1 (secao RE-CHECK).*

Constitution `docs/constitution.md` v1.3.0 [FONTE: docs/constitution.md:6].

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD aplica-se recursivamente (NON-NEGOTIABLE) [FONTE: :58] | PASS | A mudanca do toolkit passa pela propria pipeline: spec ratificada → este plan → tasks → execucao auditada. |
| II. Scripts POSIX sh puros, zero dependencia externa (NON-NEGOTIABLE) [FONTE: :79] | PASS | O guard e POSIX sh + `awk`/`sed`. Nenhuma dep nova; **remove** de fato a dependencia de `jq` que hoje faz o guard antigo ser pulado quando `jq` falta [FONTE: tests/test_orchestrator-mcp-fallback.sh:52-55]. |
| III. Formato canonico de skill [FONTE: :170] | N/A | Nenhuma skill e criada ou alterada; a mudanca e em `agents/` e `tests/`. |
| IV. Zero coleta remota (NON-NEGOTIABLE) [FONTE: :195] | PASS | Nada e transmitido. O servidor MCP e local (stdio, container local) [FONTE: .mcp.json:4-5 — `"type": "stdio"`]. |
| V. Profundidade acima de metricas de adocao [FONTE: :215] | PASS | A feature troca um guard cerimonial por um guard que protege a garantia real; nao adiciona superficie de marketing. |
| VI. Veracidade de dados — zero fabricacao (NON-NEGOTIABLE) [FONTE: :235] | PASS | Todo dado factual deste plano carrega rotulo `[FONTE: path:linha]`, `[SONDAGEM]` ou `[PROPOSTA]`. Duas lacunas de proveniencia foram declaradas em vez de mascaradas: os transcripts das sondas so-MCP e mista nao foram persistidos (research Decision 2). |

**Sem violacoes** → `Complexity Tracking` fica vazio.

## Project Structure

### Documentation (this feature)

```
docs/specs/orchestrator-mcp-allowlist/
├── spec.md                                  # ja existente (onda-002/003)
├── plan.md                                  # This file
├── research.md                              # Phase 0 output
├── data-model.md                            # Phase 1 output
├── quickstart.md                            # Phase 1 output
└── contracts/
    └── orchestrator-allowlist-guard.md      # Phase 1 output
```

### Source Code (repository root)

Arvore real, com o papel de cada path nesta feature:

```
plugins/cstk/
├── agents/
│   ├── agente-00c-orchestrator.md            # EDITA: frontmatter :4 + bloco de orientacao
│   ├── agente-00c-feature-orchestrator.md    # EDITA: frontmatter :4 + bloco de orientacao
│   ├── agente-00c-clarify-asker.md           # inalterado (nao casa o glob)
│   ├── agente-00c-clarify-answerer.md        # inalterado
│   ├── feature-00c-clarify-asker.md          # inalterado
│   ├── feature-00c-clarify-answerer.md       # inalterado
│   └── data-veracity-verifier.md             # inalterado
└── commands/
    ├── agente-00c.md                         # LE (fonte do contrato :493-500), nao edita
    └── feature-00c.md                        # LE (fonte do contrato :734-741), nao edita

mcp/state-server/src/
├── index.ts                                  # LE (nomes das 7 tools, :153-252), nao edita
└── tools/*.ts                                # LE (mapa de delegacao), nao edita

tests/
├── test_orchestrator-mcp-fallback.sh         # EDITA: remove :59-75 + comentario :24
├── test_orchestrator-allowlist-guard.sh      # CRIA [PROPOSTA]
└── run.sh                                    # EDITA: ramo em _is_internal_test

.mcp.json                                     # LE (server key `cstk-state`, :3), nao edita
```

**Structure Decision**: um unico arquivo de teste novo hospeda guard
(FR-002), asserts de allowlist (FR-003/FR-004) e paridade (FR-011), em vez
de estender o teste existente ou criar dois arquivos. Justificativa completa
em research Decision 6; em resumo: preserva a responsabilidade unica do
`test_orchestrator-mcp-fallback.sh` (fallback headless funcional) e paga um
unico ramo em `_is_internal_test`, seguindo o padrao existence-guarded ja
trilhado por `test_orchestrator-turn-completion.sh` e
`test_converge-orchestrator-gate.sh` [FONTE: tests/run.sh, corpo de
`_is_internal_test`].

**Nenhum `.sh` de produto e criado** — logo a regra de cobertura 1:1
("todo `.sh` novo em `plugins/cstk/skills/*/scripts/` ou `cli/lib/` exige
`test_<nome>.sh`") nao e acionada. O custo de superficie esta no **outro
lado** do orphan-check: `_compute_orphans` tambem lista "tests sem script
correspondente" e faz `--check-coverage` sair com `1`
[FONTE: tests/run.sh:612-624 e :72]. Sem o ramo em `_is_internal_test`, o
gate de release quebra. Este e o item mais facil de esquecer da feature e
esta explicitado como task propria.

## Convencoes de Borda

Feature majoritariamente single-layer (markdown + POSIX sh), mas existe UMA
borda real e ela e a origem do bug: o nome da tool no frontmatter e uma
string composta a partir de duas fontes independentes que precisam
concordar.

| Elemento | Convencao | Fonte da verdade |
|----------|-----------|------------------|
| `server_key` do MCP | kebab-case (`cstk-state`) | `.mcp.json` chave sob `mcpServers` [FONTE: .mcp.json:3]; registrada por [FONTE: cli/lib/mcp.sh:46] |
| `tool_name` do MCP | snake_case (`record_decision`) | `server.registerTool` [FONTE: mcp/state-server/src/index.ts:153,169,185,201,217,236,252] |
| Entrada no frontmatter | `mcp__<server_key>__<tool_name>` | composicao; ja afirmada literalmente em [FONTE: plugins/cstk/commands/feature-00c.md:734-736] |
| Tools nativas | PascalCase (`Bash`, `Read`, `Agent`) | frontmatter atual [FONTE: plugins/cstk/agents/agente-00c-orchestrator.md:4] |
| Forma do `tools:` | inline, separado por `, ` | convencao de fato nos 7 agentes; o guard aceita as duas formas mesmo assim (research Decision 4) |

**Mapper layer**: N/A — nao ha DTO nem serializacao. A "traducao" e a regra
de composicao do nome acima.

**Validacao**: estatica, pelo guard de FR-002/FR-003. Nao ha validacao de
runtime que detecte um `server_key` errado — uma tool mal-nomeada
simplesmente nao resolve e cai no fallback Bash silenciosamente. Isso e
consistente com FR-007, mas significa que **o guard estatico e a unica
rede** contra typo no nome da tool; por isso `scenario_allowlist_declara_as_7_tools_mcp`
compara contra a lista literal derivada de `index.ts`, nao contra um regex
`mcp__cstk-state__.*`.

## Fases de implementacao

| Fase | Conteudo | FRs | Bloqueia |
|------|----------|-----|----------|
| A | Guard novo (`tests/test_orchestrator-allowlist-guard.sh`) com fixtures, exercitando as duas formas de YAML | FR-002, FR-012 | — |
| B | Ramo em `_is_internal_test` de `tests/run.sh`; `./tests/run.sh --check-coverage` verde | FR-012 | A |
| C | Revogacao dos 2 scenarios antigos + comentario de cabecalho | FR-001 | A (guard novo antes de remover o antigo, para nao ficar sem rede) |
| D | Frontmatter dos 2 agentes: +7 tools MCP, nativas intactas | FR-003, FR-004 | A, C |
| E | Bloco de orientacao MCP-vs-Bash nos 2 agentes (byte-identico) | FR-005, FR-006, FR-011 | A |
| F | Suite completa verde (`./tests/run.sh`) | SC-005 | A-E |
| G | Validacao manual FR-008/SC-004 + degradacao graciosa (quickstart 5-7) | FR-008 | D, E |

Ordem A→C e deliberada: o guard novo entra em vigor **antes** da revogacao
do antigo, para que nenhum commit intermediario deixe os orquestradores sem
protecao sobre a composicao da allowlist.

## Riscos e mitigacoes

| Risco | Mitigacao | Fonte |
|-------|-----------|-------|
| O guard novo repetir o ponto cego do antigo (cobrir so uma forma de YAML) | fixtures obrigatorias nas duas formas | contracts §Casos negativos |
| Glob `*-orchestrator.md` deixar de casar (rename) e o guard passar vacuamente | `scenario_orchestrator_glob_nao_vazio` falha com 0 alvos | research Decision 3 |
| Bloco de orientacao divergir entre os 2 agentes | `scenario_guidance_block_paridade` (byte-identidade) | FR-011 |
| Esquecer o ramo em `_is_internal_test` e quebrar o gate de release | task propria na Fase B + `--check-coverage` explicito | [FONTE: tests/run.sh:612-624] |
| Typo em `mcp__cstk-state__*` degradar em silencio para Bash | assert contra lista literal das 7 tools, nao regex | §Convencoes de Borda |
| Drift catalogo↔instalado (fix "funciona no repo mas nao na sessao") | apos merge, sincronizar catalogo (`cstk install`/`cstk update`) — `agents/` e catalogo, nao runtime do binario | [FONTE: CLAUDE.md §"Installed vs Source Drift" — GOTCHA install vs self-update] |

## Postura de seguranca (gate `owasp-security`, pos-plan)

Escopo revisado: expansao da allowlist de 2 subagentes autonomos para incluir
7 tools MCP que MUTAM estado, servidor stdio local em container, autorizacao
por token de capacidade. Lentes: OWASP LLM Top 10:2025 + Agentic 2026.

**Delta de privilegio da feature = zero (nao-obvio, e importante).** Poderia
parecer que FR-003 amplia a agencia dos orquestradores (LLM06 Excessive
Agency / ASI02 Tool Misuse). Nao amplia: os dois agentes ja tem `Bash` no
frontmatter [FONTE: plugins/cstk/agents/agente-00c-orchestrator.md:4] e ja
invocam diretamente os MESMOS helpers para os quais as 7 tools delegam
(`state-ondas.sh`, `state-decisions.sh`, `bloqueios.sh`, `state-rw.sh` — ver
`data-model.md` §Mapa). As tools MCP sao um caminho **mais estreito** para um
**subconjunto** do que o Bash ja permite: schema-validado
[FONTE: mcp/state-server/src/tools/open_wave.ts:31-33], escopado por sessao
[FONTE: mcp/state-server/src/session/resolve.ts:169-174] e auditado
[FONTE: mcp/state-server/src/audit/log.ts]. Um revisor futuro nao deve ler
esta feature como expansao de privilegio.

**Nenhuma regressao pela revogacao do guard antigo.** O guard removido era
inerte (research Decision 1) e sua intencao — preservar a degradacao graciosa
— passa a ser protegida pelo mecanismo que de fato a sustenta (fallback
nativo sempre presente, FR-002/FR-004), nao por uma proibicao que nunca
disparava.

**Retorno de tool como dado, nao instrucao (LLM01/LLM05/ASI09)**: mitigacao
ja existente e reusada, nao redesenhada — o `stderr` dos helpers e tratado
como dado potencialmente influenciado por conteudo lido pelo LLM e passa por
saneamento antes de voltar ao contexto
[FONTE: mcp/state-server/src/runtime/sanitize.ts:1-13].

### Findings

| # | Sev. | Finding | Tratamento nesta feature |
|---|------|---------|--------------------------|
| F1 | **medium** | O `session_id` e entregue ao orquestrador **dentro do prompt de spawn** [FONTE: plugins/cstk/commands/feature-00c.md:742-744], ou seja, vive no contexto do LLM. O agente le conteudo nao-confiavel do repo durante specify/plan; uma injecao indireta poderia induzi-lo a escrever o token num artefato, log ou argumento de comando (LLM02 / LLM07 / ASI03). O contrato vigente cobre o **command** ("nunca ecoado em stdout/stderr/logs do command"), mas nada prescrevia a regra do lado do **agente** — e esta feature e a primeira a dar ao agente uma razao para manusear o token. | **CORRIGIDO no desenho**: item 9 obrigatorio no bloco de orientacao (`data-model.md` §Conteudo minimo) + `scenario_guidance_block_regra_nao_exfiltracao` no guard (`contracts/`). |
| F2 | low | Comparacao do token de sessao usa igualdade de string simples (`session.token === presentedSessionId`) [FONTE: mcp/state-server/src/session/resolve.ts:169-174] — nao e constant-time (CWE-208, canal lateral de temporizacao). Pre-existente; esta feature nao o introduz, mas e o que torna o caminho alcancavel a partir dos orquestradores pela primeira vez. Explorabilidade baixa no modelo de ameaca real: transporte stdio local, token de 256 bits de `/dev/urandom` [FONTE: cli/lib/mcp.sh:379 — `od -An -N32 -tx1 /dev/urandom`], exigindo co-residencia local e medicao precisa. | **Fora de escopo desta rodada** (o plano nao altera `mcp/state-server/`). Registrado como follow-up conhecido, nao como divida silenciosa. |
| F3 | low | `/dev/urandom` indisponivel aborta a geracao do token com exit 1 [FONTE: cli/lib/mcp.sh:375-379] — fail-closed correto. Sem acao. | Nenhuma. |

**Veredito do gate**: nenhum finding `critical` ou `high` → sem BloqueioHumano
obrigatorio. F1 foi corrigido no proprio desenho antes do fechamento da onda.

## Fora de escopo (explicito)

- **FR-010 / `elicitation/create`**: Deferred por determinacao da spec
  [FONTE: spec.md:266-279]. Nenhum comportamento e desenhado, nenhum
  cenario de validacao e criado, e o FR **nao e removido**. A medicao que o
  resolveria esta em curso fora desta execucao. O bloco de orientacao
  declara elicitation fora de uso ativo enquanto isso.
  Nota factual que sustenta o nao-bloqueio: nenhuma das 7 tools do
  `cstk-state` depende de elicitation (research Decision 9).
- **Alterar os commands `agente-00c.md` / `feature-00c.md`**: eles ja
  carregam o contrato correto; esta feature alinha o AGENTE ao contrato ja
  documentado, nao o contrario.
- **Alterar o servidor MCP** (`mcp/state-server/`): nenhuma tool nova,
  nenhum schema alterado.

## RE-CHECK (pos-Phase 1)

Re-avaliacao apos o design estar completo:

- **Complexidade introduzida**: 1 arquivo de teste + 1 ramo em `run.sh`.
  Nenhuma camada, servico ou dependencia nova. Principio II segue integral —
  o design inclusive **reduz** dependencia (guard sem `jq`).
- **Principio I**: os 5 artefatos da pipeline existem e sao rastreaveis
  entre si (spec ↔ plan ↔ research ↔ data-model ↔ contracts ↔ quickstart).
- **Principio VI**: as duas lacunas de proveniencia (transcripts das sondas
  so-MCP e mista) estao declaradas explicitamente em research Decision 2 e
  nao sustentam sozinhas nenhuma decisao de desenho — o guard bloqueia a
  configuracao so-MCP independentemente do texto da recusa observada.
- **Veredito**: PASS, sem excecao a registrar.

## Complexity Tracking

> Sem violacoes de constitution. Tabela intencionalmente vazia.
