# Implementation Plan: Paridade Backend-Agnostica dos Hooks 00C

**Feature**: `hooks-db-parity`
**Spec**: [spec.md](./spec.md)
**Fase**: 1 (Design) — concluida
**Data**: 2026-08-03

## Summary

Os tres hooks do runtime 00C (`pretooluse-bash-guard.sh`,
`posttooluse-tool-call-tick.sh`, `posttooluse-agent-usage.sh`) detectam
"execucao autonoma ativa" lendo `<state-dir>/state.json` diretamente. Desde
o cutover para o backend SQLite (`cstk state enable-sqlite`, linha v6.x),
esse arquivo simplesmente nao existe nos projetos migrados — os tres hooks
concluem "nenhuma execucao ativa" e ficam inertes. Consequencia verificada
empiricamente: a guarda fail-closed vira fail-open (regressao de seguranca
silenciosa) e as metricas de onda ficam zeradas.

**Abordagem tecnica**: extrair a deteccao — hoje **triplicada verbatim** nos
tres arquivos — para um unico helper sourceable
(`scripts/_hook-active-exec.sh`) que resolve o status de forma agnostica ao
backend: `jq` sobre `state.json`, ou uma **query pontual** `SELECT status
FROM execution LIMIT 1` sobre `state.db`. O helper devolve **tri-estado**
(`ativa` / `inativa` / `indeterminada`), permitindo que cada hook aplique
sua propria politica de falha ja existente — fail-closed no guard (FR-003),
fail-open nas metricas (FR-004) — e que FR-007 seja satisfeito (ausencia de
state != state ilegivel).

A escolha da query pontual sobre a materializacao do documento e sustentada
por medicao: 3.79 ms vs 21.79 ms por operacao (research Decision 1). A query
pontual e inclusive **mais barata** que a leitura `jq` do `state.json` que o
hook ja faz hoje (5.17 ms).

## Technical Context

| Campo | Valor |
|-------|-------|
| **Linguagem** | POSIX sh (`#!/bin/sh`), sem Bash-isms |
| **Deps obrigatorias** | nenhuma alem de coreutils POSIX |
| **Deps opcionais** | `jq` (pre-existente nos 3 hooks); `sqlite3` (**nova**, confinada em 1 arquivo — ver Constitution Check) |
| **Deps de teste** | `perl` (`Time::HiRes`) para o gate de latencia — com skip se ausente |
| **Storage** | leitura de `state.json` (`jq`) e `state.db` (tabela `execution`, coluna `status`); nenhum schema novo |
| **Testing** | harness POSIX proprio (`tests/run.sh`); convencao 1:1 script<->teste gateada por `--check-coverage` |
| **Target platform** | macOS + Linux (CI Ubuntu); hosts com ou sem `sqlite3` |
| **Project type** | biblioteca de scripts shell distribuida por catalogo (`cstk install`) + provisionamento por projeto (`cstk install --scope project`) |
| **Performance goals** | ~30 ms (hooks de metrica) e ~177 ms (hook de guarda) — FR-005; gate automatizado com teto de 150 ms / 400 ms (research Decision 3) |
| **Constraints** | exit code sempre `0` nos 3 hooks; stdout vazio nas metricas; nenhum write dentro do documento de estado; `timeout: 5` s imposto pelo harness |
| **Scale/Scope** | 3 hooks + 1 helper novo; 3 testes estendidos + 1 teste novo + extensao do sweep de paridade |

Nenhum campo do Technical Context ficou como unknown: linguagem, testing e
convencoes foram inferidos de `CLAUDE.md`, `docs/constitution.md` e da
leitura direta dos scripts; a stack de estado foi verificada no `state.db`
real desta execucao.

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (secao §Re-check).*

Constitution: `docs/constitution.md` v1.3.0 (ratificada 2026-04-20, ultima
emenda 2026-07-30).

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. SDD aplica-se recursivamente** (NON-NEGOTIABLE) | **PASS** | Feature nasceu de `sug-001`/CHK031 da `state-db-runtime-parity` e segue a pipeline completa: spec ratificada, clarify com 3 perguntas resolvidas, este plan, checklist e tasks a seguir. |
| **II. Scripts POSIX sh puros, zero dep externa** (NON-NEGOTIABLE) | **PASS com carve-out 1.1.0** | Ver analise dedicada abaixo — e o unico principio que exigiu decisao de design. |
| **III. Formato canonico de skill** | **N/A** | Nenhuma skill nova; nenhuma alteracao em `SKILL.md`. Os artefatos tocados sao hooks e scripts do runtime `agente-00c-runtime`. |
| **IV. Zero coleta remota de uso ou dados** (NON-NEGOTIABLE) | **PASS** | Nenhuma chamada de rede introduzida. Os sidecars permanecem locais ao state-dir; o `enforcement-log.jsonl` permanece local ao projeto. Nenhum dado sai da maquina. |
| **V. Profundidade e reducao de retrabalho acima de metricas de adocao** | **PASS** | A correcao ataca a causa-raiz (triplicacao do algoritmo) em vez de aplicar o mesmo patch tres vezes; e fecha a lacuna de deteccao no sweep de paridade (Decision 6) para que a classe de bug nao volte. |
| **VI. Veracidade de dados — zero fabricacao** (NON-NEGOTIABLE) | **PASS** | Todos os numeros de latencia do `research.md` foram medidos nesta maquina nesta onda; o schema SQLite foi lido do `state.db` real; o comportamento de `mode=ro`/`immutable=1` foi verificado empiricamente. Onde a prova empirica nao foi possivel (staleness do `immutable=1` sob escritor concorrente), o documento declara isso explicitamente em vez de afirmar um resultado. |

### Analise do Principio II (dep `sqlite3` nos hooks)

O bloco MUST do Principio II proibe dependencia externa; ha dois carve-outs.

**Carve-out 1.3.0 (dep obrigatoria) e INAPLICAVEL** — sua condicao (a)
restringe a obrigatoriedade a camada de estado transacional e diz
textualmente que "nenhuma outra parte do toolkit (skills de documentacao,
CLI de catalogo, **hooks**) pode exigir a ferramenta como pre-requisito de
funcionamento". Os hooks estao nominalmente excluidos.

**Carve-out 1.1.0 (dep opcional com fallback graceful) APLICA-SE**, com as
tres condicoes cumulativas satisfeitas:

| Condicao | Como e satisfeita | Evidencia |
|----------|-------------------|-----------|
| **(a)** uso opcional com fallback graceful documentado **e verificavel por teste** | Sem `sqlite3`, os hooks seguem 100% funcionais no backend JSON (caminho intocado). No caminho SQLite degradam de forma definida: guard bloqueia (`MECANISMO_FALHOU`), metricas viram no-op silencioso | quickstart Cenarios 5, 6, 9 — automatizados |
| **(b)** codigo que referencia a dep confinado em **UM** arquivo identificavel | Toda mencao a `sqlite3` vive em `scripts/_hook-active-exec.sh`. Os 3 hooks nao referenciam o binario | verificavel por `grep -rn sqlite3 global/skills/agente-00c-runtime/hooks/` => 0 linhas de codigo |
| **(c)** dep declarada na documentacao da feature | Declarada aqui e em `research.md` Decision 5, com caminho do arquivo confinado e descricao do fallback | este documento |

**Nota sobre o `jq` pre-existente**: `jq` ja e referenciado nos tres hooks
hoje, cada um declarando confinamento "a este arquivo". Essa e uma divida
tecnica herdada, **nao** um precedente que autorize um segundo caso de
triplicacao — motivo pelo qual esta feature confina `sqlite3` desde o
inicio. Reduzir a triplicacao do `jq` esta fora do escopo (nao regride nem
agrava).

**Nenhuma violacao de MUST**: `Complexity Tracking` fica vazio.

## Project Structure

### Documentacao (feature dir)

```
docs/specs/hooks-db-parity/
├── spec.md                          # existente (ratificada, clarificada)
├── plan.md                          # este documento
├── research.md                      # Phase 0 — 6 decisions com medicao
├── data-model.md                    # Phase 1 — entidades da deteccao
├── quickstart.md                    # Phase 1 — 13 cenarios de validacao
└── contracts/
    ├── hook-active-exec.md          # contrato do helper novo [PROPOSTA]
    └── hook-io.md                   # contrato de I/O dos 3 hooks [EXISTENTE]
```

### Source code (arvore real do projeto)

```
global/skills/agente-00c-runtime/
├── hooks/
│   ├── pretooluse-bash-guard.sh        # MODIFICADO — deteccao via helper; 2 novos modos MECANISMO_FALHOU
│   ├── posttooluse-tool-call-tick.sh   # MODIFICADO — deteccao via helper; no-op nos novos modos
│   ├── posttooluse-agent-usage.sh      # MODIFICADO — idem
│   └── settings.snippet.json           # INALTERADO — matchers e timeouts preservados
└── scripts/
    ├── _hook-active-exec.sh            # NOVO — deteccao tri-estado, unica mencao a sqlite3
    ├── _state-read.sh                  # INALTERADO — nao usado pelos hooks (research Decision 1)
    ├── _state-rw-db.sh                 # INALTERADO — referencia de paridade (_sr_backend)
    └── bash-guard.sh                   # INALTERADO — regra de bloqueio nunca reimplementada

cli/lib/
└── hooks.sh                            # INALTERADO — nenhum arquivo novo provisionado

tests/
├── test_hook-active-exec.sh            # NOVO — unitario do helper (exigido por --check-coverage)
├── test_pretooluse-bash-guard.sh       # ESTENDIDO — US1 sob SQLite + fail-closed + latencia
├── test_posttooluse-tool-call-tick.sh  # ESTENDIDO — US2 sob SQLite + fail-open + latencia
├── test_posttooluse-agent-usage.sh     # ESTENDIDO — US3 sob SQLite + fail-open + latencia
└── test_state-parity-sweep.sh          # ESTENDIDO — varredura estatica passa a cobrir hooks/
```

Todos os paths acima foram verificados como existentes (exceto os marcados
**NOVO**).

### Distribuicao (sem mecanismo novo)

Os hooks continuam sendo os **mesmos 3 arquivos** provisionados por
`apply_guard_hooks()` em `<projeto>/.claude/hooks/`. O helper novo vive no
catalogo da skill (`~/.claude/skills/agente-00c-runtime/scripts/`) e e
resolvido pela cadeia de candidatos ja usada hoje pelo guard para achar
`bash-guard.sh` e `secrets-filter.sh` (contracts/hook-active-exec.md
§`_resolve_dep`). Nenhuma mudanca em `cli/lib/hooks.sh`.

**Consequencia de sincronizacao** (GOTCHA registrado em `CLAUDE.md`
§Installed vs Source Drift): esta feature toca **apenas catalogo**
(`global/skills/...`), nao o runtime do binario (`cli/lib/*.sh`). O sync
correto e `cstk update` / `cstk install --from <tarball>`; `cstk
self-update` **nao** e necessario. Projetos-alvo que ja tem os hooks
provisionados precisam re-rodar `cstk install --scope project` para receber
os hooks corrigidos.

## Convencoes de Borda

**N/A — single-layer.** Esta feature vive inteiramente numa camada:
scripts POSIX sh executados localmente pelo harness. Nao ha fronteira
backend<->frontend, DB<->DTO nem broker<->consumer; nao ha payload de rede,
nao ha serializacao entre linguagens, nao ha mapper.

As unicas duas fronteiras de dados existentes ja sao contratos fixos e
**inalterados** por esta feature, documentados em `contracts/hook-io.md`:

| Fronteira | Formato | Fonte da verdade | Alterada? |
|-----------|---------|------------------|-----------|
| harness -> hook | JSON em stdin (`cwd`, `tool_name`, `tool_input.*`, `tool_response.*`) — chaves em `snake_case` e `camelCase` conforme o harness emite | doc oficial de hooks do Claude Code | nao |
| hook -> harness | JSON em stdout (`hookSpecificOutput.permissionDecision`) — `camelCase` | mesma | nao |
| hook -> sidecar/log | JSONL local (`snake_case`) | `data-model.md` §WaveTickSidecar / §EnforcementDecisionLog | nao |
| helper -> hook | linha unica TAB-separada + exit code | `contracts/hook-active-exec.md` | **novo** |

## Estrategia de implementacao (ordem sugerida)

Ordem derivada das prioridades da spec (P1 > P2 > P3) e da dependencia
tecnica (helper antes dos consumidores):

| Fase | Entrega | Requisitos | Independentemente testavel |
|------|---------|------------|----------------------------|
| 1 | `_hook-active-exec.sh` + `test_hook-active-exec.sh` | FR-001, FR-002, FR-007 | sim — unitario, sem hooks |
| 2 | `pretooluse-bash-guard.sh` + extensao do teste | FR-003, SC-001 (US1, P1) | sim — quickstart 1, 2, 5, 9 |
| 3 | `posttooluse-tool-call-tick.sh` + extensao | FR-004, SC-002 (US2, P2) | sim — quickstart 3, 6 |
| 4 | `posttooluse-agent-usage.sh` + extensao | FR-004 (US3, P3) | sim — quickstart 3 |
| 5 | Gate de latencia nos 3 testes | FR-005, SC-003 | sim — quickstart 7 |
| 6 | Extensao do `test_state-parity-sweep.sh` a `hooks/` + allowlist | prevencao de regressao | sim — quickstart 11 |

Cada fase e mergeavel isoladamente: apos a fase 2 a regressao de seguranca
(a mais grave) ja esta fechada, mesmo que as metricas sigam zeradas.

## Security Review (gate `owasp-security`, pos-design)

Revisao de desenho (nao ha codigo ainda) contra OWASP Top 10:2025, Agentic
2026 e CWE Top 25:2025. Escopo: os 4 artefatos desta fase.

### Findings

| ID | Sev | Titulo | Mapeamento |
|----|-----|--------|------------|
| SEC-H1 | **High** | Sourcing do helper por caminho derivado do `cwd` amplia a janela de execucao de codigo de "projetos com execucao ativa, em chamadas Bash" para "qualquer projeto, em qualquer tool call" | A03 Supply Chain, A08 Integrity, ASI05 Code Execution |
| SEC-H2 | **High (a verificar)** | Comportamento do harness quando um hook `PreToolUse` estoura o `timeout: 5` e desconhecido — se for "permitir", latencia vira bypass de guarda | A10 Exception Handling, LLM10 Unbounded Consumption |
| SEC-M1 | Medium | URI `file:<dir>/state.db?mode=ro` com path nao-escapado: `?`, `#`, `%` no nome do state-dir corrompem o parsing da URI | CWE-20 |
| SEC-M2 | Medium | Sem `busy_timeout`, contencao transitoria do SQLite vira `MECANISMO_FALHOU` espurio (guard) e perda de metrica (hooks fail-open) | A10, disponibilidade |
| SEC-M3 | Medium | Varredura O(N) com um spawn de processo por state-dir, sem teto — conteudo do repositorio controla a latencia de toda tool call | LLM10, A06 |
| SEC-L1 | Low | `tool-call-ticks.log` criado sem `umask 077` (pre-existente; o sidecar irmao usa) | A02 |
| SEC-L2 | Low | TOCTOU inerente: execucao pode iniciar logo apos a checagem e o comando roda sem guarda | A01 |

### SEC-H1 em detalhe (introduzido por ESTE desenho)

Hoje o `pretooluse-bash-guard.sh` resolve dependencias externas
(`bash-guard.sh`, `secrets-filter.sh`) **apos** confirmar execucao ativa
(L250, depois da deteccao no passo 4). No desenho proposto o helper
**e** a deteccao, logo precisa ser sourceado **antes** dela — em toda
invocacao, em todo projeto. Como o candidato 2 da cadeia de resolucao e
`<cwd>/.claude/skills/agente-00c-runtime/scripts/`, e `cwd` vem do payload
do harness (= diretorio do projeto aberto), um repositorio hostil que
carregue esse caminho consegue execucao de codigo no primeiro tool call —
sem precisar de execucao 00c ativa, e nos tres hooks em vez de so no guard.

**Mitigacoes incorporadas ao desenho** (obrigatorias na implementacao):

1. **Pre-check inline barato antes de qualquer sourcing**: cada hook testa
   a existencia de algum state (`state.json` ou `state.db`) sob
   `.claude/agente-00c-state/` ou `.claude/feature-00c-state/*/` usando
   apenas builtins (`[ -f ]`, `[ -d ]`). Sem nada para sondar, o hook sai
   `0` sem sourcear coisa alguma — que e o caso de 100% das sessoes fora
   de execucao (FR-006).
2. **Inversao da ordem de resolucao para o helper**: `$HOME/.claude/...`
   (escopo global, controlado pelo operador) passa a ser tentado **antes**
   de `<cwd>/.claude/...`. Uma instalacao global valida passa a sombrear
   qualquer arquivo plantado no repositorio. A ordem original de
   `_pbg_resolve_dep` permanece intacta para as deps ja existentes (nao
   regride comportamento).
3. **Fronteira de confianca documentada** no contrato: sourcear a partir do
   `cwd` equivale a confiar no repositorio aberto. Vale para o helper e ja
   valia para `bash-guard.sh`/`secrets-filter.sh`.

Residual aceito: com instalacao apenas escopo `project` e nenhuma global, o
candidato `cwd` volta a ser o unico — situacao identica a de hoje para o
guard. Reduzir isso alem deste ponto exigiria assinatura de artefato, fora
do escopo desta feature.

### SEC-H2 em detalhe (pendencia de verificacao, nao suposicao)

O `settings.snippet.json` registra `"timeout": 5` para os tres hooks. **Nao
foi possivel determinar, com fonte rastreavel, o que o harness faz quando um
hook `PreToolUse` excede esse timeout** — se trata como `deny`, como
`allow`, ou como erro. Se a semantica for "allow", entao qualquer caminho
que empurre o hook alem de 5 s (ver SEC-M3) converte uma degradacao de
performance em **bypass da guarda**, invertendo o fail-closed.

Por Constitution VI, o desenho **nao assume** nenhuma das respostas. A
implementacao MUST, antes de fechar a fase 2 da estrategia:

1. verificar o comportamento na documentacao oficial de hooks do Claude
   Code (fonte rastreavel), e
2. se a semantica for "allow" ou indeterminada, adotar um **auto-teto
   interno** bem abaixo de 5 s: o hook aborta a propria varredura e emite
   `MECANISMO_FALHOU` (fail-closed explicito) em vez de deixar o harness
   decidir por timeout.

### SEC-M1 / M2 / M3 — mitigacoes de implementacao

- **M1**: nao interpolar o path cru na URI. Preferir a forma
  `sqlite3 -readonly <path>` ou validar/escapar `?`, `#`, `%` antes de
  montar `file:...`. Impacto residual e fail-closed (URI malformada =>
  `indeterminada`), mas produz falso positivo de bloqueio.
- **M2**: emitir `PRAGMA busy_timeout=200;` antes do `SELECT`. Precedente
  no repositorio: `_state-db.sh` L77-89 ja usa `busy_timeout` e documenta o
  gotcha do eco do pragma no stdout do CLI (descartar a primeira linha).
- **M3**: enumerar os short-names, ordenar (`LC_ALL=C sort`) e **parar no
  primeiro ativo** em vez de sondar todos e ordenar depois (comportamento
  atual, L82-93/L223-236). O resultado e identico por definicao — o menor
  short-name ativo — com O(1) sondagens no caso comum. Complementar: teto
  defensivo de state-dirs sondados por invocacao, acima do qual o guard
  emite `MECANISMO_FALHOU` e os hooks de metrica viram no-op.

### Pontos positivos confirmados

- SQL constante, sem interpolacao de dado externo (`SELECT status FROM
  execution LIMIT 1`) — sem superficie de injecao.
- Tri-estado e a correcao correta para A10 (fail-closed em excecao): elimina
  o `return allow` implicito que a deteccao binaria produz hoje.
- `secrets-filter.sh scrub` **antes** do truncamento em 500 chars permanece
  intocado (A09/LLM02).
- `immutable=1` corretamente rejeitado — leitura stale numa decisao de
  guarda seria A10.
- Nenhuma rede, nenhum segredo novo, nenhum dado saindo da maquina (A04,
  Principio IV).

## Riscos e mitigacoes

| Risco | Mitigacao | Ref |
|-------|-----------|-----|
| Gate de latencia flakeando em CI | mediana de N=20 + warm-up + teto 5x o orcamento + skip sem `perl`/`sqlite3` | research Decision 3 |
| Host com hooks novos e catalogo stale (helper irresolvivel) | fallback JSON inline preserva comportamento atual quando nao ha `state.db`; bloqueio so atinge projetos ja migrados (que hoje estao sem guarda alguma) | research Decision 5 |
| Regressao no caminho JSON (99% da base instalada) | o caminho `jq`/`state.json` permanece inline e inalterado; a suite existente dos 3 hooks e o piso de nao-regressao | research Decision 2 |
| Leitura stale sob escritor concorrente | `immutable=1` proibido por contrato; `mode=ro` + fallback path direto consultam o WAL | research Decision 1.a |
| Bloqueio total do host por state-dir antigo corrompido | `indeterminada` so vence quando **nenhuma** execucao ativa foi confirmada; a varredura nao curto-circuita | research Decision 4 |

## Re-check de Constitution (pos-Phase 1)

Revalidado apos o design completo:

- **Principio II**: o design manteve a dep `sqlite3` em **um** arquivo
  (`_hook-active-exec.sh`); nenhum Bash-ism foi introduzido nos contratos
  (o helper e especificado como POSIX sh puro, garantia G9). **PASS**.
- **Principio IV**: nenhum contrato desenhado introduz rede ou telemetria.
  **PASS**.
- **Principio V**: o design **reduziu** superficie em vez de aumentar —
  elimina a triplicacao do algoritmo e fecha a lacuna do sweep que deixou o
  bug passar. Nenhuma camada nova alem do helper, que existe justamente
  para satisfazer o carve-out (b). **PASS**.
- **Principio VI**: os contratos marcam explicitamente o que e
  `[EXISTENTE]` (extraido do codigo) e o que e `[PROPOSTA]` (desenhado
  agora), sem afirmar como real nenhuma interface inventada. **PASS**.

Nenhuma violacao de MUST introduzida pelo design.

## Complexity Tracking

Vazio — nenhuma violacao de principio constitucional a justificar. A unica
decisao que tangenciou um MUST (dep `sqlite3`) foi resolvida **dentro** do
carve-out 1.1.0 existente, sem necessidade de emenda a constituicao.

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/hooks-db-parity/plan.md` | Criado |
| `docs/specs/hooks-db-parity/research.md` | Criado |
| `docs/specs/hooks-db-parity/data-model.md` | Criado |
| `docs/specs/hooks-db-parity/quickstart.md` | Criado |
| `docs/specs/hooks-db-parity/contracts/hook-active-exec.md` | Criado |
| `docs/specs/hooks-db-parity/contracts/hook-io.md` | Criado |

## Proximos passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor este plano em backlog executavel
3. `/analyze` — consistencia cross-artifact apos as tasks existirem
