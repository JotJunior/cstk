# Implementation Plan: Transporte MCP direto (sem container, resolucao por chamada)

**Feature**: `mcp-direct-transport` | **Date**: 2026-08-16 | **Spec**: [spec.md](./spec.md)

## Summary

O servidor MCP de estado hoje **recusa registrar qualquer tool** sem um
token de capacidade no boot — e o token so passa a existir **depois** que
uma execucao autonoma ja comecou. Resultado observado em 3 projetos
distintos: `connected — no tools`. Esta feature inverte o ponto de
resolucao: o servidor passa a **registrar todas as tools na
inicializacao** e a **resolver/validar a sessao a cada chamada**,
eliminando o container Docker do caminho do transporte.

**Abordagem tecnica** (fundamentada em 14 Decisions empiricas — ver
[research.md](./research.md)):

1. **Servidor**: remover `resolveActiveSession` do `bootstrap()`; resolver
   por chamada, com cache **apenas** de `token -> state_dir` e
   **revalidacao integral** via modo direto a cada chamada.
2. **Empacotamento**: `dist/` via **build lazy no host**, cacheado em
   `~/.claude/mcp/state-server`, herdando o padrao ja em producao do
   painel web (`cstk serve`).
3. **Launcher**: `exec` no processo `node` real, sem exigir token;
   degrada para **idle** (nunca falha) quando o build nao esta disponivel.
4. **CLI**: `start` deixa de subir container e passa a so preparar a
   sessao; `status`/`stop` sao **no-change funcional**; `gc` **sobrevive**
   para recolher o passivo Docker legado.
5. **Commands pai**: remover a condicao `mode == "docker"` da injecao do
   token — sem isso, toda chamada morreria em `SESSION_MISMATCH`.

O escopo real e menor do que "remover Docker" sugere: a auditoria mostrou
que `stop`/`gc`/`status` **ja sao majoritariamente agnosticos**, e que as
7 tools usam da sessao apenas `stateDir` e `token`.

## Technical Context

**Language/Version**: TypeScript (servidor, `engines.node >= 22`) + POSIX
sh (CLI/runtime) + prosa Markdown (commands). Fonte: `package.json`.
**Primary Dependencies**: `@modelcontextprotocol/sdk ^1.30.0`, `zod ^4.4.3`;
dev: `typescript ^7.0.2`, `@types/node ^22.20.0`. Fonte: `package.json`.
**Storage**: filesystem — descritor `<state-dir>/mcp-server.json`
(`chmod 600`); estado transacional em `state.json`/`state.db` acessado
**exclusivamente** via helpers POSIX.
**Testing**: `node --test` sobre `dist/test/*.test.js` (15 arquivos
`*.test.ts`) + harness POSIX `tests/run.sh`. **Ver Risco R2**: os testes
do servidor **nao rodam em CI**.
**Target Platform**: macOS/Linux local (dev workstation). Sem deploy.
**Project Type**: CLI + servidor MCP local (stdio), componente **opcional**
do toolkit.
**Performance Goals**: nao ha meta numerica na spec. Restricao derivada
(research Decision 2): a resolucao por chamada MUST ser O(1) descritores no
caso comum, nao O(N execucoes).
**Constraints**: POSIX sh puro nos scripts (Principio II); tarball de
release MUST permanecer na ordem de 1,0M (research Decision 5); zero
coleta remota (Principio IV).
**Scale/Scope**: 7 tools, 5 arquivos de codigo tocados + 2 commands, 1
script removido.

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 — ver §Re-check.*

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. SDD recursivo** (MUST) | **PASS** | Feature nao-trivial com `spec.md` + `plan.md`; `tasks.md` na proxima etapa. Mudanca de contrato (FR-012 revoga FR-010 da feature-base) exige nota de BREAKING no CHANGELOG — registrado como entrega obrigatoria |
| **II. POSIX sh puro** (MUST) | **PASS com ressalva pre-existente** | Os scripts tocados seguem POSIX. **Ressalva**: `cli/lib/mcp.sh` declara no cabecalho (`:52-53`, `:96-98`) que "NUNCA chama `jq` diretamente" (carve-out 1.1.0 condicao b), mas o chama em `:335`, `:446`, `:610` — `grep -c '\bjq\b'` = 30. Divergencia **pre-existente**, nao introduzida aqui; ver Risco R5 |
| **II — carve-out obrigatorio (1.3.0)** | **N/A** | O servidor MCP **nao** e a camada de estado transacional; ele **delega** a ela. Node/npm sao dep de um componente **opcional** com degradacao graciosa (contrato L-5) |
| **III. Formato canonico de skill** | **N/A** | Nenhuma skill criada/alterada |
| **IV. Zero coleta remota** (MUST) | **PASS** | Nenhuma telemetria. O build lazy faz fetch de **registry npm** — fetch de dependencia de build sob acao do operador, nao endpoint do autor. Precedente identico ja aceito: `cstk serve` |
| **V. Profundidade sobre adocao** | **PASS** | Feature corrige mecanismo quebrado (retrabalho real medido em 3 projetos), sem valor de marketing |
| **VI. Veracidade de dados** (MUST) | **PASS** | Todo campo/contrato marcado `[REAL]` tem path+linha; todo desenho novo marcado `[PROPOSTA — a validar na implementacao]`. A regressao SEC-H2 e **declarada**, sem alegacao de paridade (research Decision 9) |

**Nenhum FAIL em principio MUST.** A ressalva do Principio II e
pre-existente, documentada e fora de escopo — nao um opt-out tacito
(Decision Framework item 4).

## Project Structure

### Documentation (this feature)

```
docs/specs/mcp-direct-transport/
├── spec.md
├── plan.md                                    # This file
├── research.md                                # Phase 0 — 14 Decisions empiricas
├── data-model.md                              # Phase 1
├── quickstart.md                              # Phase 1 — 11 cenarios
└── contracts/                                 # Phase 1
    ├── server-session-resolution.md
    └── cli-mcp-lifecycle.md
```

### Source Code (repository root)

Arvore **real**, verificada nesta onda:

```
mcp/state-server/                              # CATALOGO (~/.claude)
├── package.json                               # engines.node>=22; main dist/src/index.js
├── tsconfig.json
├── .gitignore                                 # node_modules/ (L1), dist/ (L2)
├── src/
│   ├── index.ts                               # ALVO PRINCIPAL: bootstrap() L114-268
│   ├── session/resolve.ts                     # resolveActiveSession L103; matchesResolvedSession L169
│   ├── runtime/exec.ts                        # DEFAULT_SCRIPTS_DIR L144; ENFORCEMENT_LOG L298
│   ├── runtime/{identifiers,sanitize}.ts
│   ├── audit/log.ts                           # appendAuditRecord L111 — nunca chamado
│   ├── healthcheck.ts                         # avaliar remocao (era do container)
│   └── tools/                                 # 7 tools — CONTRATO INALTERADO
│       ├── open_wave.ts  record_decision.ts  record_skill.ts
│       ├── record_task.ts  register_human_block.ts
│       └── get_status.ts  close_wave.ts
└── test/                                      # 15 *.test.ts — NAO rodam em CI (R2)

cli/lib/                                       # RUNTIME (~/.local)
├── mcp.sh                                     # start/status/stop/gc/install
├── mcp-docker.sh                              # A REMOVER (research Decision 11)
└── serve.sh                                   # PADRAO A HERDAR: L127 majors, L160 preflight

plugins/cstk/skills/agente-00c-runtime/scripts/  # CATALOGO (~/.claude)
├── mcp-launch.sh                              # L123 project path; L128-130 idle
└── mcp-session.sh                             # L130 fail-closed; L196-205 modo direto

plugins/cstk/commands/                         # CATALOGO
├── agente-00c.md                              # L487 — condicao mode=="docker" (FR-013)
└── feature-00c.md                             # L728 — idem

tests/
├── test_mcp-launch.sh  test_mcp-session.sh
├── test_command-spawn-mcp-lifecycle.sh        # L121,L125 codificam contrato ANTIGO
├── test_orchestrator-mcp-fallback.sh
├── run.sh                                     # L58,L72 check-coverage; L168 mapeamento
└── cstk/
    ├── test_mcp.sh
    └── test_mcp-docker.sh                     # SAI JUNTO com o script (R1)

scripts/build-release.sh                       # L258-263 — tarball leva fonte, nunca build
```

**Structure Decision**: nenhuma estrutura nova. A feature opera **dentro**
do layout existente, removendo um arquivo (`cli/lib/mcp-docker.sh`) e seu
teste. O unico artefato novo em disco e o **cache de build**
(`~/.claude/mcp/state-server/{node_modules,dist}`), gerado em runtime e
fora do repositorio.

## Convencoes de Borda

A feature atravessa **3 camadas** (TypeScript ↔ POSIX sh ↔ prosa de
command), logo a secao **nao** e N/A.

| Borda | Formato | Validacao | Fonte da verdade |
|-------|---------|-----------|------------------|
| Argumentos de tool MCP | `snake_case` (`session_id`, `state_dir`) | Zod nos handlers | `mcp/state-server/src/tools/*.ts` [REAL] |
| Descritor `mcp-server.json` | `snake_case` (10 campos) | `jq -n` na escrita | `cli/lib/mcp.sh:457-468` [REAL] |
| Simbolos internos TypeScript | `camelCase` (`session.stateDir`, `session.token`) | `tsc` | `src/session/resolve.ts` [REAL] |
| stdout do `cstk mcp` | `chave=valor`, uma por linha | consumo textual pelos commands | `cli/lib/mcp.sh:69-75` [REAL] |
| Variaveis de ambiente | `SCREAMING_SNAKE` com prefixo `CSTK_MCP_` / `MCP_` | leitura direta de `env` | `contracts/server-session-resolution.md` §3 |

**Mapper layer (JSON ↔ TS)**: `src/runtime/exec.ts` — mapeia campo ↔ flag
↔ coluna na fronteira Node → POSIX, via `execFile`/argv array (**nunca**
shell). Existe teste de paridade dedicado: `test/exec-mapper-parity.test.ts`
[REAL].

**Validacao Zod**: apenas na borda de **entrada** (argumentos de tool). A
resposta e montada pelo servidor, nao validada por schema.

**Regra dura preservada**: nenhum campo de texto livre atravessa shell —
`execFile` com argv array elimina a classe de command injection nessa
borda ([REAL], SEC-H1 da feature-base).

## Fases de Implementacao

Sequenciamento **por camada**, com o cutover por ultimo. Fatiar por User
Story falharia: as 3 stories compartilham **um unico ponto de corte
fisico** (research Decision 13).

| Fase | Entrega | Observavel ao operador? | Depende de |
|------|---------|-------------------------|------------|
| **F1** | Servidor: tools registradas no boot; resolucao por chamada + cache `token->state_dir`; atualizar comentario de `maxToolCalls` | **Nao** (sem launcher novo, nada muda) | — |
| **F2** | Build lazy: resolucao de `dist/`, preflight de Node herdado de `serve.sh`, cache em `~/.claude/mcp/state-server` | **Nao** | F1 |
| **F3** | CLI: `start` sem Docker (FR-006/010/014); remover `cli/lib/mcp-docker.sh` **+** `tests/cstk/test_mcp-docker.sh` no MESMO commit; preservar o minimo que `gc` usa (FR-015) | **Nao** | F1 |
| **F4** | Commands: remover condicao `mode == "docker"` nos **dois** (FR-013) | **Nao** | — |
| **F5** | **CUTOVER**: launcher faz `exec node` sem exigir token (FR-004/005/012) | **SIM** — unico passo que torna a mudanca visivel | F1, F2, F3, F4 |
| **F6** | Testes: reescrever os 2 cenarios de `test_command-spawn-mcp-lifecycle.sh` para o contrato novo; cobrir resolucao por chamada e multi-sessao | — | F5 |
| **F7** | Docs: CHANGELOG com nota de BREAKING (FR-012 revoga FR-010 da feature-base); atualizar §MCP do `CLAUDE.md` | — | F5 |

**Invariante de sequenciamento**: **nenhuma** fase antes de F5 muda o
comportamento observado pelo operador. Isso e deliberado — impede o estado
intermediario enganoso em que `/mcp` lista as 7 tools mas toda chamada
morre em `SESSION_MISMATCH` (research Decision 13).

**Gate de aceite de cada fase**: cenario 0 do [quickstart.md](./quickstart.md)
(`npm test` + `tests/run.sh --check-coverage`), obrigatorio porque **nao ha
gate automatico em CI** (Risco R2).

## Riscos e Mitigacoes

| # | Risco | Impacto | Mitigacao |
|---|-------|---------|-----------|
| **R1** | Remover `cli/lib/mcp-docker.sh` orfana `tests/cstk/test_mcp-docker.sh`; `tests/run.sh --check-coverage` sai **1** | Suite vermelha entre commits, bisect quebrado | Os dois arquivos saem no **MESMO commit** (F3). Allowlist de "internos" **rejeitada**: mentiria sobre a natureza do arquivo e corromperia o sinal do `--check-coverage` (research Decision 11) |
| **R2** | **Os 15 `*.test.ts` NAO rodam em CI** — nenhum dos 3 workflows tem Node/npm. A feature reescreve exatamente o caminho coberto por `index.test.ts`/`resolve.test.ts` | Regressao pode passar no merge sem nenhum gate automatico | **Nao ha gate — isto e declarado, nao contornado.** Mitigacao: `npm test` local vira passo **obrigatorio** (quickstart cenario 0) e criterio de aceite de cada fase. Adicionar CI ficou **fora de escopo** (acoplaria o release POSIX-puro a toolchain Node por um componente opcional — research Decision 12); registrado como candidato a feature propria |
| **R3** | Ordem de corte errada cria estado em que o operador **acha** que funciona e nao funciona | Perda de confianca no mecanismo que a feature existe para restaurar | Fases por camada com cutover em F5; F4 (commands) **antes** de F5 (research Decision 13) |
| **R4** | Atualizar so uma metade da instalacao (runtime x catalogo) | Launcher novo contra `cstk mcp start` antigo gravando `mode=docker` — falha confusa | Ambas MUST ser atualizadas: `cstk self-update --from` (runtime) **e** `cstk install --from` (catalogo). Documentado em F7 e research Decision 6 |
| **R5** | `cli/lib/mcp.sh` viola o proprio cabecalho sobre confinamento de `jq` (carve-out II-b) | Constitution Check do arquivo sob edicao seria falso se marcado PASS silencioso | **Declarado** no Constitution Check. Correcao **fora de escopo** (refatoracao sem FR); registrada como recomendacao ao mantenedor (dec-036) |
| **R6** | Recorte entre "codigo Docker que `gc` ainda usa" (FR-015) e "codigo que so o `start` usava" nao foi verificado linha a linha | F3 pode remover demais (quebra `gc`) ou de menos (mantem codigo morto) | Marcado **[PROPOSTA]** em `contracts/cli-mcp-lifecycle.md` §5.1; MUST ser validado com o codigo em maos antes de executar F3 |
| **R7** | Primeira execucao numa maquina exige `npm` + rede (build lazy) | Sessao sem tools ate o build concluir | Contrato **L-5**: launcher degrada para **idle** com motivo explicito, nunca falha a sessao. Cenario 9 do quickstart valida |
| **R8** | **Supply chain do build lazy** (A03 / ASI04 / LLM03): `npm ci` no host executa lifecycle scripts (`postinstall`) de toda a arvore transitiva **com os privilegios do usuario**. Antes, o `npm ci` rodava dentro do `docker build` — script malicioso ficava confinado a imagem; agora alcanca `$HOME` (incl. `~/.claude`, credenciais) | Comprometimento de dependencia vira execucao de codigo no host | **[PROPOSTA — a validar na implementacao]** usar `npm ci --ignore-scripts` no build lazy (as 2 deps diretas sao JS puro — **a validar** que nenhuma dep transitiva exige build nativo) e fixar a instalacao pelo `package-lock.json` ja versionado. **Severidade: HIGH** (corrigido em dec-041, onda-006 — o rebaixamento original a MEDIUM citava `cli/lib/serve.sh:574` como precedente de "postura ja aceita", mas essa linha **tambem** invoca o gerenciador de pacotes **sem** `--ignore-scripts`; verificado por grep no repo inteiro, a UNICA ocorrencia real da flag hoje e `cli/lib/mcp-docker.sh:169`, dentro do Dockerfile que **esta propria feature remove**. Nao ha controle equivalente em producao hoje, e a remocao do Dockerfile **elimina a unica ocorrencia atual da protecao no repo** ate a mitigacao proposta acima ser implementada e validada) |
| **R9** | **Confusao de sessao por descritor deslocado** (A01 / ASI03): o cache `token -> state_dir` e revalidado, mas a revalidacao compara `session_id`; se um descritor for **copiado/restaurado de backup** para outro state-dir, um token legitimo poderia autorizar mutacao no state-dir errado | Mutacao no state-dir nao pretendido | **[PROPOSTA — a validar na implementacao]** na revalidacao, conferir tambem que o campo `state_dir` **de dentro** do descritor bate com o diretorio de onde ele foi lido. O campo ja existe ([REAL] `mcp.sh:461`), o custo e uma comparacao de string, e detecta descritor deslocado |
| **R10** | **DoS cross-sessao pelo teto de chamadas** (LLM10 / ASI08): com 1 processo : N sessoes, uma execucao ruidosa esgota `maxToolCalls` e as **demais sessoes do mesmo processo** passam a ser rejeitadas — impossivel no modelo 1:1 anterior | Degradacao que atinge execucao inocente | Impacto limitado a **degradacao**, nao falha: a rejeicao ja instrui comutar para o caminho Bash ([REAL] `index.ts:146`), que continua funcional. MUST ser documentado junto com T-1; contador por sessao segue fora de escopo (research Decision 1) |

## Postura de Seguranca: ganho e perda lado a lado

Declaracao exigida pelo Principio VI. **Nao ha alegacao de paridade.**

| Aspecto | Antes | Depois | Veredito |
|---------|-------|--------|----------|
| Confinamento de filesystem (SEC-H2) | flags do `docker run` (`mcp-docker.sh:333-342`) | processo herda o filesystem do usuario | **REGRESSAO declarada** |
| Cobertura de teste de SEC-H2 | `test_mcp-docker.sh:389`, `:486` | **nenhuma** — nao ha mecanismo equivalente a testar | **PERDA declarada** |
| Token em identificador observavel | sufixo do nome do container (`docker ps`) | nao existe container | **GANHO** (FR-009) |
| Autorizacao por token | fail-closed uma vez no boot | fail-closed **a cada chamada** | escopo mais fino |
| Superficie de infra | daemon Docker no caminho critico | processo local, sem daemon | reducao |
| Trilha de auditoria | ja desligada (`appendAuditRecord` nunca chamado) | **inalterada** — gap pre-existente | neutro, **documentado** |

### Resultado do gate `owasp-security`

Revisao do desenho (nao do codigo — ele ainda nao existe) sob OWASP Top
10:2025, LLM Top 10:2025 e Agentic (ASI) 2026.

| Finding | Categoria | Severidade | Tratamento |
|---------|-----------|------------|------------|
| Perda de confinamento por montagens | ASI02/ASI03 | **MEDIUM** | ja declarado (tabela acima); autorizacao por token permanece como controle |
| Supply chain do `npm ci` no host | A03 / ASI04 / LLM03 | **HIGH** | **R8** — corrigido em dec-041 (precedente citado estava invertido); mitigacao proposta, ainda nao implementada |
| Descritor deslocado / restaurado de backup | A01 / ASI03 | **MEDIUM** | **R9** — novo, mitigacao proposta |
| DoS cross-sessao pelo teto de chamadas | LLM10 / ASI08 | **MEDIUM** | **R10** — novo, degradacao com fallback |
| Token em identificador observavel | ASI03 | **RESOLVIDO** | FR-009 elimina o vetor |
| Fail-closed por chamada | A01/A10 | **PASS** | preservado e com escopo mais fino |
| Ausencia de gate de CI no caminho de autorizacao | CICD-SEC-1 | **MEDIUM** | **R2** — `resolve.test.ts` e justamente um dos que nao rodam em CI |

**Um finding HIGH: R8** (corrigido em dec-041, onda-006; nenhum CRITICAL).
A avaliacao original desta gate (dec-039, onda-005) rebaixou o supply
chain do build lazy para MEDIUM citando `cli/lib/serve.sh:574` como
precedente de "postura ja aceita pelo toolkit". **A citacao estava
invertida**: verificado por grep no repo inteiro (`cli/`, `scripts/`,
`.github/`), essa mesma linha invoca o gerenciador de pacotes **sem**
`--ignore-scripts` — nao ha protecao equivalente em producao hoje. A
UNICA ocorrencia real da flag no repo e `cli/lib/mcp-docker.sh:169`, no
Dockerfile que **esta propria feature remove** (F3) — ou seja, a feature
nao "segue uma postura ja protegida", ela **elimina a unica instancia da
protecao que existe hoje** ate a mitigacao proposta em R8 ser implementada
e validada. O rebaixamento foi revertido; R8 volta a HIGH. Ver dec-039
(decisao original, agora corrigida) e dec-041 (correcao, com evidencia).

**Mudanca de eixo do modelo de ameaca**: o confinamento deixa de ser do
**PROCESSO** e passa a ser da **AUTORIZACAO** — todo caminho de mutacao
segue passando pelos helpers POSIX, que so tocam o `state_dir` resolvido
pelo token apresentado na chamada. Contexto que **nao anula** a perda: o
adversario do modelo original ja era o conteudo lido pelo LLM, nao o
proprio servidor.

## Mudanca de contrato (BREAKING)

| Contrato | Antes | Depois |
|----------|-------|--------|
| Vida do **processo** | coextensivo com a **execucao**, sobrevive a pausas (FR-010 da feature-base) | coextensivo com a **sessao do harness** (FR-012 desta spec) |
| Vida da **sessao MCP** (descritor + token) | coextensiva com a execucao | **inalterada** — sobrevive a pausas no disco |
| Cardinalidade processo : sessao | **1 : 1** (um container por execucao) | **1 : N** |
| Semantica de `maxToolCalls` | teto por execucao | teto por **processo / sessao do harness** |

Os 2 cenarios de `tests/test_command-spawn-mcp-lifecycle.sh:121,125` que
afirmam sobrevivencia a pausa **passam a mentir** e MUST ser reescritos em
F6 — senao a mudanca fica sem teste que a proteja.

## Complexity Tracking

Nenhuma violacao de principio MUST exige justificativa. A ressalva do
Principio II (R5) e **pre-existente** e nao decorre de complexidade
introduzida por este plano.

| Item | Natureza | Tratamento |
|------|----------|------------|
| `jq` nao-confinado em `cli/lib/mcp.sh` | divergencia pre-existente cabecalho x codigo | declarada (R5, dec-036); correcao fora de escopo |
| `appendAuditRecord` nunca chamado | gap pre-existente da feature-base | declarado (research Decision 4); fora de escopo |
| Ausencia de CI para `mcp/` | lacuna de gate pre-existente | declarada (R2); mitigada por gate manual |

## Re-check de Constitution (pos-Phase 1)

| Verificacao | Resultado |
|-------------|-----------|
| O design introduziu complexidade nao justificada? | **Nao** — remove um caminho inteiro (Docker) e adiciona uma unica estrutura em memoria (cache `token->state_dir`), sem TTL nem invalidacao |
| Principios MUST continuam respeitados? | **Sim** — I, IV, VI PASS; II PASS com ressalva pre-existente declarada |
| Algum artefato afirma dado nao verificado? | **Nao** — auditoria dos 5 artefatos: todo item factual tem `[REAL]` + path/linha, ou `[PROPOSTA — a validar na implementacao]` |
| Novo servico/camada? | **Nao** |

---

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/mcp-direct-transport/plan.md` | Criado |
| `docs/specs/mcp-direct-transport/research.md` | Criado |
| `docs/specs/mcp-direct-transport/data-model.md` | Criado |
| `docs/specs/mcp-direct-transport/contracts/server-session-resolution.md` | Criado |
| `docs/specs/mcp-direct-transport/contracts/cli-mcp-lifecycle.md` | Criado |
| `docs/specs/mcp-direct-transport/quickstart.md` | Criado |

**Constitution**: PASS (com 1 ressalva pre-existente declarada)
**NEEDS CLARIFICATION restantes**: 0
