# Research: orchestrator-slim

**Feature**: `orchestrator-slim` | **Date**: 2026-09-29 | **Spec**: [spec.md](./spec.md)

Todas as afirmacoes abaixo vem de leitura real do repositorio (worktree
`cstk-orchestrator-slim`, HEAD `9f97e99`) ou de saida literal de comando
executado nesta onda. Nada e estimado sem estar rotulado como estimativa.

## Baseline medido (FR-013)

| Arquivo | Bytes (`wc -c`) | Linhas | Ultimo commit que tocou o arquivo |
|---------|-----------------|--------|-----------------------------------|
| `plugins/cstk/agents/agente-00c-orchestrator.md` (O) | 146014 | 2649 | `013c3d1` |
| `plugins/cstk/agents/agente-00c-feature-orchestrator.md` (F) | 104702 | 1891 | `013c3d1` |

Commit de referencia do baseline: `9f97e994d5cde46d1447744c68c9def8da14e6e3`
(HEAD da branch `orchestrator-slim` antes de qualquer edicao dos
orquestradores). O artefato versionado do baseline sera gerado pelo script de
medicao contra esse commit (ver Decision 7).

## Decision 1 — Local das referencias

**Decision**: `plugins/cstk/skills/agente-00c-runtime/references/orchestrators/<orchestrator>/<phase>.md`,
com `<orchestrator>` em `{root, feature}`.

**Rationale** (fontes):
- Skill e instalada como diretorio inteiro, recursivo, sem filtro de extensao:
  `cp -R` em `cli/lib/install.sh:599-600` e `cli/lib/update.sh:551-552`.
  Agente e instalado como `.md` avulso (`install.sh:753,811-815`), portanto
  arquivo irmao de agente nao seria distribuido.
- Tarball de release copia cada skill com `cp -R` sem allowlist de arquivos
  (`scripts/build-release.sh:162-168`); so remove `evals/` (`:245`) e
  `.DS_Store`/`._*` (`:315`). `scripts/profiles.txt.in` lista nomes de skill,
  nao arquivos. Nenhum manifest precisa ser atualizado.
- Plugin nativo: `.claude-plugin/marketplace.json:11` aponta
  `"source": "./plugins/cstk"`; o diretorio fica dentro desse subtree. Scripts
  do runtime ja leem `references/` por caminho relativo a si
  (`bloqueios.sh:81`, `state-decisions.sh:110`, `delivery-tier.sh:93`,
  `model-routing.sh:1042`, `state-db-schema.sh:44`) e hooks/.mcp.json usam
  `${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/...`
  (`plugins/cstk/.mcp.json:6`, `plugins/cstk/hooks/hooks.json:10,22`).
- `agente-00c-runtime` ja e dependencia obrigatoria dos dois orquestradores
  (probe `test -x` em O:276-285 aborta apontando `cstk install`).
- `references/` hoje contem 4 arquivos (17723 bytes) e nenhum teste afirma a
  lista/contagem desse diretorio (so leituras pontuais: `test_bloqueios.sh:877`,
  `test_model-routing.sh:2084`, `test_delivery-tier.sh:24`,
  `test_state-db-schema.sh:3`).

**Limite honesto**: os orquestradores hoje referenciam o runtime por
`~/.claude/skills/agente-00c-runtime/scripts` hardcoded (O:97, F:87, F:1140) e
nao resolvem `CLAUDE_PLUGIN_ROOT`; se essa variavel e visivel ao Bash de um
subagente nao foi determinado a partir do repositorio. As referencias ficam,
portanto, exatamente tao alcancaveis quanto os scripts que os orquestradores
ja exigem — nao mais, nao menos. A resolucao e feita por um helper do proprio
runtime (Decision 3), que reaproveita `_resolve-root.sh` na ordem B
(`strict`, `_resolve-root.sh:34-37`): diretorio-irmao do script,
`${CLAUDE_PLUGIN_ROOT}`, `$HOME/.claude/skills`.

**Alternatives considered**:
- Arquivos irmaos em `plugins/cstk/agents/` — rejeitada: install copia so
  `*.md` de agentes como artefatos individuais; um `.md` extra em `agents/`
  seria instalado como AGENTE (poluindo o catalogo) e o subdiretorio nao seria
  copiado.
- Skill nova dedicada (ex. `orchestrator-refs`) — rejeitada: bumpa contagem de
  skills (`tests/test_doc-counts.sh:33`, `tests/cstk/test_build-release.sh:185`,
  `tests/cstk/test_quickstart-e2e.sh:223`, README) e cria uma segunda
  dependencia de instalacao sem ganho.

## Decision 2 — Granularidade: um arquivo por (orquestrador, fase)

**Decision**: um arquivo por fase por orquestrador, contendo TODO o conteudo
movido que aquela fase exige (inclusive blocos usados em mais de uma fase, ex.
read-back loop em `specify` e `plan`). Blocos que aparecem em mais de um
arquivo ficam entre marcadores `<!-- FRAGMENT:<id>:BEGIN -->` /
`<!-- FRAGMENT:<id>:END -->` e um teste exige que todas as copias do mesmo
`<id>` sejam byte-identicas (mesmo mecanismo ja usado para
`MCP-VS-BASH:BEGIN/END`, `tests/test_orchestrator-allowlist-guard.sh:134-140,680-697`).

**Rationale**: SC-006 limita a no maximo 1 leitura extra por fase percorrida;
dividir o conteudo multi-fase em arquivos separados obrigaria 2+ leituras na
mesma fase. O custo da duplicacao cai so em disco (instalacao), nao no
contexto de onda; a deriva entre copias e barrada por teste.

**Referencia compartilhada entre os dois orquestradores (dec-013)**: criada
SOMENTE para bloco movivel byte-identico nos dois orquestradores. Medicao
nesta onda (comparacao de linhas apos remover a indentacao de 3 espacos do O):

| Secao comparada | Linhas O | Linhas F | Linhas identicas |
|-----------------|----------|----------|------------------|
| model-routing + depth | 427 | 449 | 284 |
| read-back loop | 125 | 100 | 50 |
| camada B | 199 | 127 | 85 |
| quality gates + converge | 208 | 186 | 62 |
| classe estrutural | 51 | 51 | 35 |

Nenhuma secao movivel e byte-identica. Unificar textos divergentes seria
reescrita, proibida por FR-004 (e a paridade prevalece — dec-011). Portanto o
diretorio `references/orchestrators/shared/` so e criado se a deteccao
deterministica de blocos identicos (tarefa de execucao) achar um bloco
contiguo movivel byte-identico; com os dados de hoje ele nao existe. A unica
secao byte-identica (MCP-vs-Bash) roda em 100% das ondas e fica no
prompt-base de ambos (FR-007, sem mudanca).

**Alternatives considered**: (a) arquivo de fragmento por bloco + lista de
leituras por fase — rejeitada por violar SC-006; (b) gerador de arquivos de
fase a partir de fragmentos-fonte — rejeitada: adiciona script de build e
passo de regeneracao sem ganho sobre marcadores + teste, que ja e padrao do
repositorio.

## Decision 3 — Resolucao em runtime e falha segura (FR-009/FR-010)

**Decision**: novo script do runtime
`plugins/cstk/skills/agente-00c-runtime/scripts/orchestrator-refs.sh` (POSIX
sh) com subcomandos `path` e `list` (contrato em
`contracts/orchestrator-refs-cli.md`). O prompt-base resolve o caminho via
`orchestrator-refs.sh path --orchestrator <o> --phase <p>` e le o arquivo com
a tool Read. Exit != 0 ou Read falho => a fase NAO e executada de memoria;
registrar Decisao + bloqueio humano e encerrar a onda (FR-010).

**Rationale**: um unico ponto codifica a ordem de resolucao (reusa
`_resolve-root.sh`) e produz exit code deterministico para o caso "ausente".
O helper resolve relativo a si mesmo, entao funciona em qualquer canal em que
o proprio runtime funcione.

**Alternatives considered**: caminho literal `~/.claude/skills/...` no prompt
— rejeitada: duplica a regra de resolucao em N ponteiros e nao cobre o
subtree do plugin.

## Decision 4 — Stub de secao no prompt-base

**Decision**: toda secao movida deixa no prompt-base um stub com o MESMO
heading/numeracao original (ex. `### 5.e.bis Sequencia pre-spawn de subagente
(model-routing)`) contendo apenas o ponteiro padronizado (Decision 5).

**Rationale** (fonte: inventario de referencias cruzadas): ~29 referencias por
nome/numero de secao em commands/skills/scripts/src, ex. "Quality Gates
complementares" (`commands/feature-00c.md:74-75`, `skills/plan/SKILL.md:208`),
"§5.e.bis" (`scripts/state-decisions-reconcile.sh:11`), "secao 5.b"
(`scripts/pipeline.sh:78,833`, `scripts/state-decisions.sh:407,416`,
`mcp/state-server/src/tools/record_decision.ts:74`), "§5.d.ter"
(`scripts/state-ondas.sh:1164`), "passo 8" e "Loop principal" do F
(`mcp/state-server/src/tools/close_wave.ts:25,32,45,266`) e "passo 3.bis"
(`open_wave.ts:60`). Com o stub, todas continuam resolvendo no prompt-base e o
stub encaminha para a referencia — zero edicao nesses consumidores.

**Fora de escopo (pre-existente, nao introduzido por esta feature)**:
referencias ja inconsistentes hoje — "passo 10.bis" citado para O onde a
ingestao e 9.bis (`commands/agente-00c.md:905,908,913`,
`agente-00c-resume.md:459,462,466`), "§5.e.a" inexistente
(`skills/clarify/SKILL.md:37`), citacoes de linha `feature-00c.md:738` e
`agente-00c.md:497` dentro do bloco MCP-vs-Bash (O:167-168/F:155-156, ja
stale e protegidas por byte-identidade), e citacoes de numero de linha em
specs de outras features (`docs/specs/mcp-elicitation-optins/`,
`orchestrator-mcp-allowlist/`, `cstk-jira/`). Serao registradas como sugestao,
nao corrigidas aqui (escopo).

## Decision 5 — Formato do ponteiro (FR-003)

**Decision**: bloco padronizado com marcador maquina-legivel
`<!-- ORCH-REF: <orchestrator>/<phase> -->` seguido de prosa com (a) fase/
condicao, (b) comando de resolucao do caminho, (c) instrucao de ler ANTES dos
passos da fase e (d) regra de falha FR-010. Formato exato em
`contracts/pointer-format.md`. O marcador permite ao teste de FR-009 listar
todos os caminhos citados sem parsear prosa.

## Decision 6 — Classificacao secao a secao (dec-012)

Criterio: move se (a) NAO roda em 100% das ondas E (b) a onda da fase
continua com ganho liquido (prompt-base novo + referencia da fase < baseline).
Mantem no prompt-base tudo listado em FR-002 e todo conteudo que governa
qualquer onda. Tabelas completas com bytes em `data-model.md` §Inventario de
secoes. Resumo das somas medidas (bytes das secoes movidas, antes de somar os
stubs):

| Orquestrador | Baseline | Movido | Prompt-base projetado* | Reducao projetada* |
|--------------|----------|--------|------------------------|--------------------|
| O | 146014 | 82627 | ~67400 | ~54% |
| F | 104702 | 61519 | ~46200 | ~56% |

**Atualizacao (execute-task 1.2, CHK021)**: o bloco "Finalize terminal" fica
no prompt-base (O: 946 bytes, F: 460 bytes), logo movido = 81681 (O) e 61059
(F); a projecao recalculada (stubs a 650 bytes + secao "Referencias de fase")
esta em `data-model.md` §Projecao: O ~48%, F ~50%. A tabela acima e o valor
original de planejamento, mantido por historico.

\* Projecao = baseline − movido + estimativa de stubs (~250 bytes x 16 stubs
em O, x 12 em F). E ESTIMATIVA de planejamento, nao resultado; o numero
oficial vem do script de medicao apos a implementacao. A margem sobre a meta
de 40% (FR-018: O <= 87608 bytes, F <= 62821 bytes) permite manter no
prompt-base qualquer trecho cuja classificacao se revele duvidosa durante a
execucao, sem arriscar a meta.

## Decision 7 — Medicao (FR-011/FR-012/FR-013/FR-017)

**Decision**: script de desenvolvimento `scripts/measure-orchestrator-prompts.sh`
(POSIX sh, `git show`, `wc`, `awk`), contrato em
`contracts/measure-cli.md`. Relatorios versionados em
`docs/specs/orchestrator-slim/measurements/{baseline,after}.md`.

**Tokens (fato medido nesta onda)**: nao ha contador de tokens Claude
disponivel offline nesta maquina — `python3 -c "import tiktoken"` e
`import anthropic` falham com `ModuleNotFoundError`; `@anthropic-ai/tokenizer`
ausente em `npm ls -g`; `ANTHROPIC_API_KEY` nao definida; nenhum helper de
contagem no repositorio. A API `count_tokens` e rede externa, vedada pelo
Principio IV/blast radius. Portanto, conforme dec-010/FR-011, o gate de
FR-018 cai para **bytes** e o relatorio declara a limitacao. O script aceita
opcionalmente um comando externo de contagem via variavel de ambiente
(`ORCH_TOKEN_COUNTER`) — se ausente, a coluna de tokens sai "indisponivel",
nunca estimada a partir de bytes.

**Observado (knowledge.db, fato medido)**: `~/.claude/cstk/knowledge.db`,
tabela `waves`: 1915 linhas; `otel_total_tokens` nao-nulo em 974;
colunas `otel_subagent_*` em 973; `otel_main_*` em 129; `agent_*` em 58.
Nao existe coluna de tipo de execucao em `executions`; o unico discriminador e
o prefixo de `execution_id` (`feat-*` = feature-00c: 1469 linhas / 909 com
`otel_total_tokens`; `*agente-00c*`: 428 / 65). Nenhuma coluna isola o custo
do system prompt; `otel_subagent_cache_creation_tokens` e o proxy mais
proximo mas inclui resultados de tool e turnos. O relatorio observado reporta
esse proxy por fase (via `waves.stages`), com `n` e cobertura por coluna, e
declara que NAO isola o prompt-base. Periodo "depois" so existe apos instalar
a versao nova e rodar ondas reais; sem essas ondas, "indisponivel" (FR-017).
O acesso a `sqlite3` no script e opcional com fallback "indisponivel"
(Principio II, carve-out 1.1.0, confinado ao unico arquivo do script).

## Decision 8 — Paridade deterministica (FR-006/FR-016)

**Decision**: tres verificacoes automatizadas, todas comparando o baseline
(`git show 9f97e99:<path>`) com o corpus novo (prompt-base + referencias do
mesmo orquestrador):
1. **Preservacao de linhas**: o multiconjunto de linhas nao-vazias do
   baseline (sem indentacao inicial) MUST estar contido no corpus novo; a
   diferenca so pode conter linhas listadas numa allowlist versionada de
   referencias internas reescritas (FR-004 ii), cada uma com justificativa.
2. **Blocos de comando**: conjunto de invocacoes `<script>.sh <subcomando>`
   do runtime extraido dos dois lados; diferenca zero.
3. **Literais contratuais**: arquivo-inventario com os ~100 padroes hoje
   asseridos pelos 11 testes (lista em `data-model.md`), executado contra
   baseline e corpus novo; todos casam nos dois.

**Rationale**: (1) prova FR-004 sem julgamento manual — qualquer passo,
flag ou "REGRA DURA" removido ou reescrito aparece como linha faltante; (2) e
(3) sao os inventarios exigidos por FR-016/FR-006.

## Decision 9 — Migracao dos testes (FR-006)

**Decision**: helper sourceable `tests/lib/orchestrator-corpus.sh` com
`orch_corpus <root|feature>` (imprime prompt-base + referencias, em ordem
estavel) e `orch_ref <root|feature> <phase>`. Os 11 testes passam a greppar o
corpus; asserts posicionais migram para o arquivo onde o trecho passou a
viver, preservando a mesma relacao de ordem (lista por teste em
`data-model.md`). Nenhum padrao e afrouxado. `tests/test_doc-subcommands.sh`
(`DOC_DIRS`, linha 33) passa a incluir `references/orchestrators` para que
invocacoes movidas continuem validadas contra o dispatch real.

## Decision 10 — Linguagem e dependencias

Sem stack nova. Scripts em POSIX sh (`#!/bin/sh`, `set -eu`), ferramentas
canonicas (`awk`, `sed`, `grep`, `wc`, `sort`, `diff`) mais `git` (script de
desenvolvimento em `scripts/`, como `build-release.sh`). Identificadores e
nomes de arquivo em ingles (FR-014); prosa pt-BR.
