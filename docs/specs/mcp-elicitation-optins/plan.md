# Implementation Plan: Opt-ins iniciais via MCP elicitation (com fallback de prosa)

**Feature**: `mcp-elicitation-optins` | **Date**: 2026-08-17 | **Spec**: [spec.md](./spec.md)

## Summary

Trocar o canal de captura dos tres opt-ins de inicio de execucao (commit
atomico, modo roadmap, finalidade de entrega) de **prosa interpretada pelo
modelo** para um **formulario estruturado MCP** (`elicitation/create`),
mantendo a prosa como fallback integral e sem alterar nenhum default seguro.

**Abordagem tecnica** (consolidada de `research.md`, Decisions 1-13):

1. Uma **8a tool MCP** — `collect_optins` — porta um **unico** formulario com
   os campos aplicaveis ao orquestrador corrente (derivados de
   `ResolvedSession.executionKind`), e persiste as respostas chamando os
   helpers POSIX de escrita pos-init.
2. **Init em duas etapas** no ramo estruturado: o pai cria o estado minimo com
   os defaults seguros e cunha o token; o **orquestrador** dispara o formulario
   como primeiro ato, **antes** de abrir a onda-001 (unico ator que porta as
   tools MCP — dec-030).
3. **Teto de tempo do lado servidor** via `RequestOptions.timeout` do proprio
   SDK, satisfazendo FR-010 sem wrapper caseiro.
4. **Fallback integral** para os blocos de prosa quando o mecanismo nao esta
   disponivel — ramo legado byte-a-byte inalterado.
5. **Revogacao** (por narrowing) da clausula normativa que hoje **proibe**
   `elicitation/create` nos dois orquestradores, com a assercao do guard
   fortalecida no mesmo commit.

### Achados que mudam o desenho (nao sao detalhe de implementacao)

| # | Achado | Consequencia |
|---|--------|--------------|
| A1 | `cstk mcp start` **nao sobe processo** — so cunha token (dec-031) | a etapa (1) do init MUST deixar `.execution.status` ativo, senao **toda** chamada retorna `SESSION_MISMATCH` |
| A2 | `delivery-tier.sh set` **recusa rebaixamento** sem `--allow-downgrade` (dec-037; flag **condicional** por dec-047) | como o init grava o **maior** ordinal, sem a flag o tier so grava em **1 de 4** respostas e falha calado nas outras 3 — mas a flag so acompanha **escolha explicita de ordinal menor** (Invariante C-2); desfecho degradado nao emite `set` |
| A3 | FR-006 x FR-012 **nao se contradizem** (dec-037) | `cloud-public` **e** o nivel mais restritivo (eixo = rigor de gate). Nenhum delta de spec necessario |
| A4 | O guard do item 8 **nao quebra** com a revogacao — fica **cego** | o entregavel e *fortalecer* a assercao, nao *consertar* teste vermelho (§Riscos R3) |
| A5 | `mode=bash-fallback` **nunca e escrito** (dec-034) | nenhum teste pode asseri-lo; discriminador real = token vazio |
| A6 | `roadmap-mode.sh set-enabled` e **write-once** apos ondas | argumento adicional para disparar **antes** de `state-ondas.sh start` |
| A7 | Testes Node **nao rodam em gate algum** (dec-027) | lacuna declarada, nao mascarada; decisao de escopo separada |

## Technical Context

**Language/Version**: TypeScript 5.x/7.x sobre Node >= 22 (servidor MCP,
`mcp/state-server/package.json` `engines.node: ">=22"`); POSIX `sh` puro
(helpers de runtime); Markdown normativo (commands + agents)
**Primary Dependencies**: `@modelcontextprotocol/sdk` `^1.30.0`, `zod` `^4.4.3`
(VERIFICADO em `mcp/state-server/package.json`); `jq` e `sqlite3` na camada de
estado transacional (carve-out constitucional 1.3.0)
**Storage**: `state.json` ou `state.db` conforme backend configurado — acesso
**exclusivo** via helpers do `agente-00c-runtime`, nunca leitura direta
**Testing**: `tests/run.sh` (harness POSIX, `tests/lib/harness.sh`) para as
assercoes gateaveis; `node --test` sobre `dist/test/*.test.js` para o lado
Node — este ultimo **sem gate** hoje (ver §Estrategia de Testes)
**Target Platform**: local, macOS/Linux, dentro da sessao do Claude Code
**Project Type**: toolkit CLI + skills + servidor MCP stdio
**Performance Goals**: N/A — captura de resposta humana, uma vez por execucao
**Constraints**: nenhuma execucao pode travar aguardando resposta (FR-007,
SC-002); teto de tempo default `300000` ms / 5 min (politica de design,
dec-058 — decisao do operador que substitui a proposta original de
`120000` ms); nenhum default seguro muda (FR-006)
**Scale/Scope**: 1 formulario por execucao, <= 3 campos, <= 1 chamada de
elicitation por execucao (retomadas reusam — FR-011)

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.* (re-check em §Re-check)

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | A feature tem `spec.md` clarificada, e este plano + `research.md` + `data-model.md` + `contracts/` + `quickstart.md`. Toda decisao de desenho rastreia a uma Decisao auditada (dec-025..dec-038) |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | Nenhum script novo em `plugins/cstk/skills/**/scripts/`. As mudancas POSIX sao **chamadas** a helpers ja existentes. O codigo TS novo fica confinado a `mcp/state-server/`, camada de estado transacional ja coberta pelo carve-out 1.3.0 (dep obrigatoria `@modelcontextprotocol/sdk` ja vigente desde `state-mcp-server`) — **nenhuma dep nova e introduzida** |
| III. Formato canonico de skill | N/A | A feature nao cria nem altera skills; altera commands, agents e o servidor MCP |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | `elicitation/create` trafega **local**, via stdio, entre servidor e o cliente da propria sessao. Nenhum dado sai da maquina; nenhum endpoint remoto e introduzido |
| V. Profundidade sobre adocao | PASS | Elimina tres pontos de nao-determinismo sobre dados que **governam gates** — reducao de retrabalho, nao visibilidade |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | Todo artefato desta fase separa **VERIFICADO** (arquivo:linha) de **[PROPOSTA — a validar na implementacao]**. Tres itens de renderizacao nao medidos estao marcados; a premissa central tem cenario bloqueante (`quickstart.md` Scenario 0). Duas afirmacoes herdadas foram **corrigidas** (FR-013 e dec-032) em vez de propagadas |

### Correcoes de premissa exigidas pelo Principio VI

O Principio VI se aplica **tambem** aos artefatos desta feature. Quatro
afirmacoes previas nao sobreviveram a leitura da fonte:

1. **FR-013 da spec** afirma que as tres primitivas de escrita "ate esta
   feature nao tinham chamador ativo". Vale para **duas**
   (`commit-mode.sh set-enabled`, `roadmap-mode.sh set-enabled`); `delivery-tier.sh set`
   **ja tem** chamadores (`agente-00c.md:433`, `agente-00c-resume.md:214/218`).
   Para o tier a mudanca e de **ORDEM**, nao de mecanismo (dec-026/dec-035).
   → **Delta de spec recomendado** (nao bloqueante para implementar).
2. **dec-032** afirma que a revogacao quebra a suite. A leitura literal do
   teste mostra que ela **nao quebra** se o literal for preservado — o risco
   real e a assercao ficar cega (§Riscos R3, `contracts/optin-capture-order.md` §6.1).
3. **FR-012 da spec e o Edge Case em `spec.md:197-208`** citam
   `mode=bash-fallback` como o sinal de que o servidor falhou ao subir. E o
   **mesmo defeito** que este plano manda corrigir em `feature-00c.md:711` e
   `agente-00c.md:470`: `research.md` Decision 10 mostra que nenhum caminho de
   codigo emite esse valor (`mcp.sh:708-709` grava **sempre** `direct`).
   Corrigir nos commands e deixar de pe na spec propagaria o dado falso.
   → **Delta de spec recomendado**: trocar por "token vazio / descritor
   ausente" nos dois pontos.
4. **A contagem de testes Node** foi afirmada como 17 na primeira redacao
   deste plano; a contagem real e **16**
   (`ls mcp/state-server/test/*.test.ts | wc -l` → `16`). Corrigido. Registrado
   aqui porque foi uma violacao do Principio VI cometida **por esta fase**,
   detectada pelos proprios gates — o registro e o que impede que se repita.

## Project Structure

### Documentation (this feature)

```
docs/specs/mcp-elicitation-optins/
├── spec.md
├── plan.md                              # This file
├── research.md                          # Phase 0 (consolida dec-025..dec-038)
├── data-model.md                        # Phase 1
├── quickstart.md                        # Phase 1
└── contracts/                           # Phase 1
    ├── mcp-tool-collect-optins.md       # a 8a tool MCP
    └── optin-capture-order.md           # ordem pai <-> orquestrador
```

### Source Code (repository root)

Arvore **real** (paths verificados). `[NOVO]` / `[EDIT]` marcam o alcance:

```
cstk/
├── mcp/state-server/
│   ├── package.json                     # engines.node >=22, sdk ^1.30.0
│   ├── src/
│   │   ├── index.ts                     [EDIT] registrar a 8a tool
│   │   ├── tools/
│   │   │   ├── get_status.ts            # padrao de envelope a espelhar
│   │   │   └── collect_optins.ts        [NOVO] formulario + persistencia
│   │   ├── session/resolve.ts           # ResolvedSession.executionKind (sem edit)
│   │   ├── runtime/exec.ts              # runHelper/execFile shell:false (sem edit)
│   │   └── runtime/sanitize.ts          # sanitizeForLlmContext (sem edit)
│   └── test/
│       └── collect_optins.test.ts       [NOVO] — SEM gate hoje (dec-027)
├── plugins/cstk/
│   ├── commands/
│   │   ├── agente-00c.md                [EDIT] ramo de init em 2 etapas + stale :470
│   │   ├── agente-00c-resume.md         [EDIT] idempotencia de retomada
│   │   ├── feature-00c.md               [EDIT] idem + stale :711
│   │   └── feature-00c-resume.md        [EDIT] idem
│   ├── agents/
│   │   ├── agente-00c-orchestrator.md            [EDIT] frontmatter + item 8 (:187)
│   │   └── agente-00c-feature-orchestrator.md    [EDIT] frontmatter + item 8 (:175-177)
│   └── skills/agente-00c-runtime/scripts/
│       ├── commit-mode.sh               # set-enabled — sem edit, ganha 1o caller
│       ├── roadmap-mode.sh              # set-enabled — sem edit, ganha 1o caller
│       └── delivery-tier.sh             # set — sem edit; caller passa --allow-downgrade so no rebaixamento aceito
└── tests/
    ├── run.sh                           [EDIT] registrar o test novo em _is_internal_test
    ├── test_orchestrator-allowlist-guard.sh  [EDIT] _required 8 tools + item 8 nao-cego
    └── test_command-spawn-optin-elicitation.sh [NOVO] ordem + ramos + stale
```

**Structure Decision**: nenhuma estrutura nova. O codigo TS novo entra como
**mais uma tool** no diretorio `src/tools/` ja existente (7 arquivos irmaos), e
o teste POSIX novo entra na familia `test_command-spawn-*.sh` ja consolidada.
Zero diretorio criado, zero camada adicionada — a feature e uma troca de canal
sobre infraestrutura ja provisionada.

## Convencoes de Borda

A feature atravessa **quatro** camadas com convencoes de nomenclatura
distintas. Declarar a fonte da verdade de cada uma e o que impede o drift de
case (ver `quickstart.md` Scenario 8).

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Wire MCP (`elicitation/create`) | camelCase (`requestedSchema`, `enumNames`) | schema do SDK | `@modelcontextprotocol/sdk` `types.d.ts` — **imposto, nao escolhido** |
| Envelope de tool (server → orquestrador) | snake_case (`session_id`, `applied_value`) | `zod` no `inputSchema` | `mcp/state-server/src/tools/*.ts` (padrao das 7 tools) |
| Campos de estado | snake_case (`atomic_commit_enabled`, `delivery_tier`) | helpers do runtime | `state-rw.sh:536-538` (VERIFICADO) |
| Flags de helper POSIX | kebab-case (`--state-dir`, `--allow-downgrade`) | parser do proprio script | `commit-mode.sh` / `roadmap-mode.sh` / `delivery-tier.sh` |
| Tokens de enum de dominio | kebab-case (`cloud-public`, `internal-network`) | `case` do `delivery-tier.sh` | `delivery-tier.sh:100-107` (VERIFICADO) |

**Mapper layer (wire ↔ estado)**: `mcp/state-server/src/tools/collect_optins.ts`
e o **unico** ponto de traducao. Responsavel por: `ElicitResult.content`
(camelCase, wire) → argumentos de helper (kebab-case) → campos de estado
(snake_case). ORM auto-mapping: **NAO** — mapeamento explicito, como nas 7
tools existentes.

**Validacao zod**: apenas na borda de **entrada** da tool (`session_id`). A
saida do `elicitInput` ja vem validada pelo proprio SDK contra o
`requestedSchema` enviado; re-validar seria duplicar a fonte da verdade.

## Estrategia de Testes

### Camada gateada (POSIX — `tests/run.sh`)

Reusa a familia `test_command-spawn-*.sh` (assercao textual em `.md` via
`assert_exit` + `grep`, harness `tests/lib/harness.sh`). Precedentes diretos:
`test_command-spawn-delivery-tier.sh` (enum de 4 valores, mapeamento de
tokens, escopo negativo), `test_command-spawn-roadmap-mode.sh` (default
seguro, nao-interativo, no-reprompt) e
`test_command-spawn-mcp-lifecycle.sh:62-68` (**assercao de ORDEM por numero de
linha** — modelo direto para o init em duas etapas do FR-012).

`tests/test_command-spawn-optin-elicitation.sh` **[NOVO]** cobre:

- ordem do ramo estruturado: `init` < `mcp start` < spawn < `collect_optins` <
  `state-ondas.sh start` (assercao por numero de linha)
- ramo legado preservado: prosa **antes** do init nos 4 commands
- ausencia da string `mode=bash-fallback` como assercao (A5)
- correcao dos comentarios stale (`feature-00c.md:711`, `agente-00c.md:470`)
- **condicionalidade** de `--allow-downgrade` na chamada do tier (A2 + dec-047):
  presente so no rebaixamento aceito; ausente na elevacao/no-op; **nenhuma**
  chamada de `set` nos desfechos degradados (assercao sobre o argv capturado —
  `quickstart.md` Scenario 1b)
- escopo negativo: `feature-00c*` nao oferece campo de tier

Registrar em `tests/run.sh::_is_internal_test` (nao ha script `.sh` de skill
correspondente — evita falso positivo no `--check-coverage`). Atencao ao lint
de classe `test_command-prompt-noninteractive-lint.sh`.

`tests/test_orchestrator-allowlist-guard.sh` **[EDIT]**: `_required` com 8
tools, cenario renomeado, e a assercao do item 8 deixando de ser presenca de
token (§Riscos R3). Validado por **teste de mutacao** (`quickstart.md`
Scenario 9.3).

### Camada NAO gateada (Node) — lacuna declarada (dec-027)

VERIFICADO hoje: `ls .github/workflows/` → 3 arquivos (`publish-site.yml`,
`release.yml`, `shellcheck.yml`); `grep -rin node .github/workflows/` → **zero
linhas**; `grep -nE "mcp/state-server|npm test|node --test" tests/run.sh` →
**sem match**.

Consequencia honesta: toda a logica de elicitation (montagem do formulario,
teto de tempo, mapeamento accept/decline/cancel/timeout) vive no lado Node, que
e a metade **nao gateada** do repo. `collect_optins.test.ts` sera escrito e
rodara sob `npm test` manual — isso e **intencao verificavel, nao cobertura**.

**Decisao de escopo separada** (nao premissa silenciosa desta feature): criar
`.github/workflows/node.yml` **ou** wirar `npm test` em `tests/run.sh`. Ambos
sao mudancas de infraestrutura de CI com alcance muito maior que esta feature
(passariam a gatear os 16 `*.test.ts` existentes de uma vez, com risco de
descobrir vermelho pre-existente). Recomendacao: abrir como feature propria.

### Validacao empirica bloqueante

`quickstart.md` Scenario 0 MUST rodar **antes** de qualquer implementacao. E o
unico teste da premissa nao medida de que o desenho depende.

## Resultado dos gates de qualidade (onda-005)

| Gate | Veredito | critical | high | medium | low |
|------|----------|----------|------|--------|-----|
| `validate-documentation` (plan-profile) | findings | 0 | 3 | 3 | 2 |
| `owasp-security` | findings | 0 | **2** | 6 | 3 |
| `data-veracity-verifier` (Principio VI) | has_unsourced | — | — | 5 citacoes | — |

### Re-execucao dos gates (onda-006, pos-decisao humana)

| Gate | Veredito | critical | high | medium | low |
|------|----------|----------|------|--------|-----|
| `validate-documentation` (plan-profile) | pass | 0 | 0 | 0 | 0 |
| `owasp-security` | findings | 0 | **0** | 3 | 0 |

`validate-sdd.sh --sdd-plan` retornou `errors=0|warnings=0` nos **6** artefatos.
A camada semantica achou 3 defeitos **introduzidos por esta propria onda**, os
tres corrigidos antes do fechamento: duas citacoes off-by-one
(`cli-delivery-tier.md:141-142`, `test_command-spawn-delivery-tier.sh:87-90`) e
a afirmacao herdada "`message` e medido como renderizado", que nao tinha fonte
citavel e virou premissa explicita do Scenario 0.

Os **2 HIGH estao fechados**. Os 3 MEDIUM do gate de seguranca sao **novos** e
ja estao endereçados no texto (viram tarefa no `create-tasks`, nenhum some):

- **M6** — cap de chamadas de `collect_optins` por execucao, **elevado de LOW**:
  com o disparo de coleta permitido ao orquestrador, o cap passa a ser o
  controle contra prompt-spam por injecao indireta (fadiga de consentimento,
  ASI01);
- **M7** — regra **2** do INV-4 ("mudanca de tier so **entre ondas**, via
  `/agente-00c-resume`") conflita com a gravacao no init; a emenda MUST
  admitir a coleta de inicio de execucao como segunda janela legitima;
- **M8** — regra **3** do INV-4 (`delivery-tier-unattended-change`) nao
  reconhece `.optin_responses[]` com `channel: "structured"` como evidencia de
  consentimento; sem a emenda, **toda** captura estruturada vira alarme falso —
  e o desfecho provavel sob pressao seria afrouxar justamente o controle de
  deteccao que sustenta o F5.

**Ja aplicado nesta onda**: as 5 correcoes de citacao do auditor de veracidade
(4 numeros de linha + a contagem 17→16); a regra de terminalidade R-1/R-2/R-3
(`data-model.md`); a primitiva de escrita e o comportamento sob SQLite
(`data-model.md` §Primitiva de escrita); os deltas de spec 3 e 4 acima.

**RESOLVIDO na onda-006 — decisao humana ao `block-002` aplicada**: os **2
findings HIGH** do gate de seguranca. Regra dura do gate: severidade `high` em
`owasp-security` exige BloqueioHumano; eram decisoes de governanca, nao de
implementacao. Respostas do operador e onde cada uma pousou:

- **H1 — consentimento para rebaixar `delivery_tier`** (dec-047). A advertencia
  de risco vai no campo **`message`** da elicitation — o unico texto cuja
  renderizacao esta medida — e **nao** em `title`/`description` (nao medidos,
  R4). `--allow-downgrade` passa a ser **condicional**: so quando
  `outcome === "accepted"` **e** o ordinal da resposta e **menor** que o
  vigente. Corolario que fecha o finding: **os defaults seguros nao sao
  rebaixamento** — cancel por ausencia, cancel por teto de tempo e decline
  **nunca** emitem `set`. Aplicado em: `contracts/mcp-tool-collect-optins.md`
  (§Campo `message` + Invariante C-2), `contracts/optin-capture-order.md` §3.3
  (mesma regra no ramo de prosa), `data-model.md` §Ordinal, `research.md`
  Decision 4 (emendada) e `quickstart.md` **Scenario 1b** (as tres faces:
  menor ⇒ com flag; igual/maior ⇒ sem flag; degradado ⇒ nenhum `set`).
- **H2 — conflito com a INV-4 do `delivery-tier`** (dec-048): **emendar** o
  INV-4, nao revogar. O invariante material e "o orquestrador nao **escolhe** o
  valor do tier" — e no desenho ele nao escolhe: o valor nasce fora do contexto
  do modelo (servidor pede → cliente renderiza → operador escolhe → servidor
  grava). O vetor que o proprio §2.2 nomeia (injecao indireta) pode no maximo
  fazer o orquestrador **disparar a pergunta**, nunca **responde-la**. A
  reescrita proposta da regra 1 de `cli-delivery-tier.md` §2.2 esta em
  `contracts/mcp-tool-collect-optins.md`
  §[PROPOSTA — emenda a `cli-delivery-tier.md` INV-4], marcada como proposta
  porque e contrato de **outra** feature — **nao foi editado nesta onda**.

**Entregavel obrigatorio de H2 para o `create-tasks`** (tarefa unica, os dois
itens no **mesmo commit**, senao a emenda vira texto sem gate):

1. reescrever as regras **1, 2 e 3** de
   `docs/specs/delivery-tier/contracts/cli-delivery-tier.md` §2.2 conforme a
   proposta (regra 1: proibir a **escolha**/set direto, permitir disparo de
   coleta mediada; regra 2: admitir a coleta de **inicio de execucao** como
   segunda janela legitima; regra 3: aceitar a entrada
   `.optin_responses[]` com `channel: "structured"` como evidencia de
   consentimento). Regra 4 inalterada;
2. ajustar `tests/test_command-spawn-delivery-tier.sh:87-90`
   (`scenario_resume_documenta_inv4_operador`) para asserir a distincao
   **escolha/set direto** x **disparo de coleta mediada**, em vez de casar
   apenas a frase antiga `'por iniciativa do proprio orquestrador'`.

**MEDIUM/LOW de seguranca a endereçar no `create-tasks`** (nao bloqueantes,
mas nenhum deve sumir): binding de identidade da execucao no `message` (M1);
linha no `enforcement-log.jsonl` por decisao de opt-in (M2); allowlist
explicita de tokens no mapper antes de montar argv (M3); guarda mecanica da
Invariante I-2 no `start`/`open_wave` (M4); clamp de
`MCP_ELICIT_TIMEOUT_MS` (M5, ex.: 5s–300s — sem clamp, um valor alto contradiz
FR-007/SC-002); `secrets-filter.sh scrub` no `reason` persistido (L1); cap de
chamadas de `collect_optins` por execucao (**M6** — elevado de LOW para MEDIUM
na onda-006: com a emenda do INV-4 permitindo o **disparo** de coleta pelo
orquestrador, o cap deixa de ser higiene e passa a ser o controle que limita
prompt-spam induzido por injecao indireta, i.e. fadiga de consentimento —
ASI01); allowlist de tools autorizadas
a chamar `elicitInput` (L3).

**Pendencias do gate documental para o `create-tasks`**: assert de paridade
textual prosa↔formulario (FR-002, M2) e assertiva observavel para SC-001 (M3).

## Riscos

| # | Risco | Severidade | Mitigacao |
|---|-------|------------|-----------|
| R1 | Harness nao renderiza `elicitation/create` originado de **subagente** | **Alta** — invalida o desenho | **MEDIDO (dec-071)**: `quickstart.md` Scenario 0 executado pelo operador — formulario apareceu, `message` renderizou integral. Premissa confirmada, risco encerrado |
| R2 | `--allow-downgrade` esquecido ⇒ tier grava em 1 de 4 casos, **calado** | **Alta** — defeito silencioso em dado que governa gate | Assercao dedicada no teste POSIX + `quickstart.md` Scenario 1 usa `local` (ordinal 0), o caso que expoe o defeito |
| R2b | `--allow-downgrade` **incondicional** ⇒ caminho de rebaixamento sempre armado, inclusive sem escolha do operador | **Alta** — consentimento (finding HIGH H1) | Invariante C-2 condicional (dec-047) + `quickstart.md` Scenario 1b, que asserta sobre o **argv capturado** (assercao negativa "nenhum `set` no desfecho degradado" nao e verificavel pelo valor final) |
| R3 | Item 8 revogado com literal preservado ⇒ guard **verde e cego** | Media — perda de sinal, nao quebra visivel | Assercao reforcada + **teste de mutacao** obrigatorio (Scenario 9.3). Verde na mutacao = entregavel nao cumprido |
| R4 | `title`/`description`/`default` nao renderizarem ⇒ texto de FR-002 nao chega ao operador | Media (fechado) | **MEDIDO (dec-071)**: os tres renderizam (`title`→rotulo, `description`→subtexto, `default`→pre-aplicado); `message` tambem renderiza integral. Consequencia nao prevista: `enum` renderiza colapsado (seta para expandir) e `delivery_tier` com `default` esconde o `required` visivel — dois ajustes de contrato aplicados na FASE 3 (`message` avisa da seta; `delivery_tier` sem `default` no schema) |
| R5 | Ramo degradado com round-trip de spawn extra confundir com travamento | Baixa | Aviso unico em stderr (`failed`) + o pai prossegue automaticamente; SC-002 preservado |
| R6 | Regressao no ramo legado ao "uniformizar" os dois ramos | Media | `contracts/optin-capture-order.md` §4 e explicito: legado **byte-a-byte** inalterado; teste dedicado |
| R7 | Logica central sem gate (A7) | Media | Declarada, nao mascarada. Assercoes gateaveis concentradas na camada POSIX |

## Re-check (pos-Phase 1)

Revalidacao apos o design, conforme ETAPA 7:

- **Principio II**: o design **nao** introduziu script POSIX novo nem dep nova.
  A unica dep tocada (`@modelcontextprotocol/sdk`) ja e obrigatoria da camada de
  estado transacional desde `state-mcp-server`. **PASS mantido.**
- **Principio IV**: `elicitation/create` e stdio local entre servidor e cliente
  da propria sessao; o design nao adicionou nenhum destino remoto. **PASS mantido.**
- **Principio VI**: o design **aumentou** a superficie de afirmacao (um contrato
  de tool inteiro). Mitigado com rotulagem por bloco, cenario de validacao
  bloqueante e duas correcoes de premissa herdada. **PASS mantido.**
- **Complexidade introduzida**: 1 tool nova + 1 campo de estado aditivo + 1
  ramo condicional. Nenhuma camada, nenhum servico, nenhum diretorio novo.
  Nao requer entrada em Complexity Tracking.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa.

**N/A** — nenhuma violacao de principio MUST. Nenhuma dependencia nova, nenhum
script fora do padrao POSIX, nenhuma camada adicional.
