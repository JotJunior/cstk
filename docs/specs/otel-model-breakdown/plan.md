# Implementation Plan: OTel Model Breakdown na knowledge.db

**Feature**: `otel-model-breakdown` | **Date**: 2026-07-28 | **Spec**: [spec.md](./spec.md)

## Summary

Hoje o snapshot de telemetria OTel gravado por onda em
`.waves[].otel_usage` do `state.json` carrega duas dimensoes que se perdem
por completo na ingestao da knowledge.db: (1) custo e tokens **por modelo**
(`by_model`) e (2) o breakdown de tokens por tipo — entrada, saida, leitura de
cache, criacao de cache — **por fonte** (`by_source.main` vs
`by_source.subagent`). Sem elas nao ha como responder "quanto do gasto desta
feature foi opus vs sonnet" nem calcular taxa de acerto de cache, a nao ser
lendo `state.json` onda a onda.

**Abordagem**: migracao **aditiva** de schema da knowledge.db, v11 -> v12,
inteiramente confinada a `cli/lib/recall.sh`:

- tabela nova `wave_model_usage`, grao onda x modelo, com `model` gravado como
  **string bruta** do snapshot (sem normalizacao para alias canonico);
- 8 colunas aditivas nullable em `waves` para o breakdown por fonte;
- ingestao alimentada por um **loop de extracao proprio** (o loop atual de
  ondas nao comporta colecao de tamanho variavel);
- backfill automatico via `--reindex`, que ja recria o banco do zero.

Ausencia de dado sempre vira `NULL`, jamais zero fabricado. Nenhuma coluna ou
tabela existente e removida, renomeada ou alterada.

## Technical Context

**Language/Version**: POSIX `sh` (shebang `#!/bin/sh`, `set -eu`) — restricao do
Principio II da constitution. Nenhum Bash-ism.
**Primary Dependencies**: `sqlite3` e `jq` como **dependencias opcionais com
fallback graceful**, ja confinadas a `cli/lib/recall.sh` (regime do amendment
1.1.0 do Principio II). Nenhuma dep nova.
**Storage**: SQLite em `~/.claude/cstk/knowledge.db` — indice **derivado e
descartavel**, reconstruivel via `--reindex` a partir dos `state.json` em disco.
O `state.json` transacional nao e tocado por esta feature (somente leitura).
**Testing**: harness POSIX proprio — `tests/cstk/test_recall.sh`, executado por
`./tests/run.sh test_recall`.
**Target Platform**: macOS e Linux (CI Ubuntu). Sem GNU-ismos.
**Project Type**: CLI tool / biblioteca shell (`cstk`).
**Performance Goals**: N/A — corpus da ordem de dezenas de linhas por execucao;
nenhum indice secundario necessario (Decision 8 do research).
**Constraints**: migracao aditiva e idempotente; degradacao graciosa obrigatoria
(dep ausente nunca aborta a onda do orquestrador); sintaxe SQL em ingles,
comentarios em pt-br.
**Scale/Scope**: 1 arquivo de runtime alterado (`cli/lib/recall.sh`), 1 arquivo
de teste estendido (`tests/cstk/test_recall.sh`). Sem NEEDS CLARIFICATION
pendentes.

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 — ver §Re-check.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature tem spec ratificada + clarify concluido; este plan, data-model, research e quickstart completam a cadeia antes de qualquer codigo. |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | Toda mudanca em `cli/lib/recall.sh`, que ja opera sob o carve-out do amendment 1.1.0. As tres condicoes cumulativas seguem satisfeitas — ver §Conformidade com o amendment 1.1.0. |
| III. Formato canonico de skill | N/A | Feature nao cria nem altera skill; mexe em `cli/lib/`. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Dado permanece 100% local (`~/.claude/cstk/knowledge.db`). Nenhuma transmissao; a feature so LE um snapshot ja gravado localmente. |
| V. Profundidade acima de metricas de adocao | PASS | Objetivo e reduzir retrabalho de auditoria de custo, nao inflar numero de features. |
| VI. Veracidade de dados — zero fabricacao (NON-NEGOTIABLE) | PASS | E o eixo central da feature: FR-004 exige NULL para ausencia. Todos os valores citados nos artefatos foram lidos do corpus real e conferidos aritmeticamente. |

### Conformidade com o amendment 1.1.0 (deps opcionais)

| Condicao | Como e satisfeita |
|----------|-------------------|
| (a) opcional com fallback verificavel | `recall_have_sqlite3` (`recall.sh:343`) e `recall_have_jq` (`recall.sh:346`) ja guardam a entrada de cada modo (ingest em `:1982`/`:1986`, reindex em `:2378`/`:2382`). O codigo novo roda dentro desses modos, logo herda o fallback. Coberto pelo Cenario 6 do quickstart. |
| (b) confinada a UM arquivo | Toda a mudanca de runtime fica em `cli/lib/recall.sh`. `grep -rl 'sqlite3' cli/lib/` deve continuar retornando so esse arquivo. |
| (c) declarada na doc da feature | Declarada aqui e em `research.md` (Decision 10). |

## Project Structure

### Documentation (this feature)

```
docs/specs/otel-model-breakdown/
├── spec.md          # Ratificada, com Clarifications
├── plan.md          # This file
├── research.md      # Phase 0 — 10 decisoes
├── data-model.md    # Phase 1 — schema v11->v12
└── quickstart.md    # Phase 1 — 9 cenarios contra corpus real
```

Sem `contracts/`: a feature nao expoe interface externa nova. O "contrato" e o
schema SQLite, documentado em `data-model.md`.

### Source Code (repository root)

```
cli/
├── cstk                    # binario (dispatch) — NAO alterado
└── lib/
    └── recall.sh           # UNICO arquivo de runtime alterado
tests/
└── cstk/
    └── test_recall.sh      # estendido (novos cenarios + 12 assercoes de versao)
```

Pontos de alteracao em `cli/lib/recall.sh` (anchors verificados na fonte):

| # | Local | Alteracao |
|---|-------|-----------|
| 1 | `:115` | `RECALL_SCHEMA_VERSION=11` -> `12` |
| 2 | `:496-529` (DDL de `waves`) | +8 colunas INTEGER nullable |
| 3 | apos `:602` (DDL) | `CREATE TABLE IF NOT EXISTS wave_model_usage (...)` |
| 4 | apos `:770` (bloco v10->v11) | bloco ALTER idempotente v11->v12, reusando `_as_wcols` de `:724` |
| 5 | `:1130-1138` (jq de waves) | +8 campos de `by_source.main`/`.subagent` no array posicional |
| 6 | `:1163-1167` (leitura por indice) | +8 leituras `.[23]`..`.[30]` + `recall_int_or_null` |
| 7 | `:1189-1191` (INSERT waves) | +8 colunas nas **tres** listas (colunas, VALUES, DO UPDATE SET) |
| 8 | novo bloco proximo a `:1195` | loop de extracao proprio para `wave_model_usage` (padrao `tasks`/`events`) |
| 9 | `:1735` (agregacao de totais) | `RECALL_TOTAL_WAVE_MODEL` |
| 10 | `:2014` e `:2454` | +1 contador nas duas format strings de sumario |
| 11 | `:2007-2008` e `:2411-2412` | inicializacao do contador novo |

**Structure Decision**: manter tudo em `recall.sh` em vez de extrair um modulo
novo. Razao dupla: (i) o Principio II exige que a dep opcional fique confinada a
um unico arquivo grep-avel — extrair criaria um SEGUNDO arquivo com `sqlite3`/
`jq` e violaria a condicao (b); (ii) o padrao de ingestao (extracao jq ->
base64 -> loop -> SQL acumulado em `_isj_sql`) e coeso e local. O arquivo cresce,
mas a alternativa quebra invariante constitucional.

## Convencoes de Borda

A feature nao tem borda backend<->frontend, mas TEM uma borda real de
convencao de nomes: **JSON do snapshot OTel -> colunas SQLite**. Declarar
explicitamente evita exatamente o tipo de drift que a secao existe para prevenir.

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Snapshot OTel em `state.json` (`by_source.*`) | snake_case, **sem** sufixo `_tokens` (`input`, `output`, `cache_read`, `cache_creation`) | nenhuma (dado ja gravado) | `state-ondas.sh:676` (unico ponto de escrita) |
| Snapshot OTel em `state.json` (`by_model`) | chave = string bruta do modelo, valor `{cost_usd, total_tokens}` | nenhuma | idem |
| Colunas SQLite (`waves`) | snake_case **com** prefixo `otel_` e sufixo `_tokens` | `PRAGMA table_info` no bloco de migracao | `data-model.md` §Wave (extensao) |
| Colunas SQLite (`wave_model_usage`) | snake_case ingles | `UNIQUE(project, feature, wave, source_id)` | `data-model.md` §WaveModelUsage |

**Mapper layer**: nao ha ORM. O mapeamento JSON -> coluna e explicito e vive em
UM lugar: a expressao `jq` da ingestao (`recall.sh:1130+`) que le a chave do JSON,
mais a lista de colunas do `INSERT` (`recall.sh:1189`). ORM auto-mapping: **NAO**.

**Ponto de atencao**: os nomes divergem de proposito
(`cache_read` -> `otel_main_cache_read_tokens`). Essa traducao e assimetrica e
manual; um erro nela produz coluna silenciosamente NULL (a expressao `//` do jq
converte chave inexistente em `""` -> `NULL`, sem erro). Por isso os Cenarios 2
e 3 do quickstart assertam **valores exatos** do corpus real, nao apenas
"nao-nulo" — e a unica forma de flagrar um mapeamento trocado.

**Validacao de tipo**: `recall_int_or_null` (`recall.sh:850`) para tokens,
`recall_real_or_null` (`recall.sh:862`) para custo em USD (fracionario).

## Riscos e Dependencias de Release

### R1 — Bump de schema quebra o cstk-panel instalado (ALTO, verificado)

O painel valida `schema_meta.schema_version` contra uma **allowlist fechada** e
degrada com `schema-mismatch` quando o valor esta fora dela. Evidencia direta na
copia instalada (`.panel-version` = `v0.19.2`):

- `apps/server/src/config.ts:31`:
  `export const DEFAULT_SCHEMA_VERSIONS = ['2','3','4','5','6','7','8','9','10','11'] as const;`
- `apps/server/src/db/open.ts:146`:
  `if (schemaVersion === undefined || !supported.includes(schemaVersion)) { ... }`

`openDb(...)` e chamado em praticamente toda rota da API (overview, metrics,
executions, features, tasks, alerts, events, search, health...). Com o banco em
`12`, o painel inteiro degrada.

**Mitigacao imediata** (sem alterar o painel): a allowlist e configuravel por
env CSV — `resolveSchemaVersions()` (`config.ts:76-81`) le `CSTK_SCHEMA_VERSIONS`.
Rodar `CSTK_SCHEMA_VERSIONS=2,3,4,5,6,7,8,9,10,11,12 cstk serve` restabelece o
painel sem release nova.

**Fix definitivo**: adicionar `'12'` a `DEFAULT_SCHEMA_VERSIONS` no repo
`cstk-panel` e publicar release — trabalho **fora deste repositorio** e fora do
escopo desta feature, mas que deve ser agendado junto do release do cstk. Como o
comentario do proprio painel diz que as versoes sao aditivas e "os recursos
novos aparecem so quando a tabela/coluna esta presente", adicionar `12` a lista
e suficiente; nao ha mudanca de leitura obrigatoria.

**Nao bloqueia esta feature**: o painel e consumidor downstream opcional. Mas
publicar o bump sem avisar geraria "painel quebrou do nada".

### R2 — Edicao das 12 assercoes de versao nos testes (MEDIO)

`tests/cstk/test_recall.sh` compara `schema_version` contra `"11"` em 12 linhas
(611, 656, 678, 1879, 2195, 2285, 3035, 3161, 3216, 3265, 3337, 3474). Um `sed`
global `11`->`12` atingiria numeros nao relacionados e textos de mensagem.
Edicao dirigida, linha a linha. Detalhe em `research.md` Decision 9.

### R3 — GOTCHA de distribuicao (BAIXO, conhecido)

`cstk install` / `cstk update` **nao** atualizam `cli/lib/`. Validar a mudanca
exige `cstk self-update --from "file://$PWD/dist/cstk-X.Y.Z-dev.tar.gz"`.
Sem isso, o codigo antigo continua rodando e o teste manual da falso-negativo.

## Tratamento do nome do modelo (seguranca)

O nome do modelo e o unico valor **de origem externa** introduzido por esta
feature: vem do endpoint de telemetria OTel, atravessa `state.json` e chega a
uma string literal SQL. Duas decisoes explicitas:

**1. Escape SQL — OBRIGATORIO.** O valor DEVE passar por `sql_escape`
(`recall.sh:202`, que duplica cada aspa simples via `sed "s/'/''/g"`) nas
**duas** posicoes em que aparece: coluna `model` e coluna `source_id`. Omitir o
escape em qualquer uma delas seria injecao de SQL a partir de um label de
metrica. Todos os `INSERT` do arquivo ja seguem esse padrao — manter.

**1.bis. Higiene de bytes — `strip_nul`.** Como todos os campos lidos dos loops
de ingestao (`recall.sh:1145-1167`, `:1604-1611`, `:1648-1650`), o valor
extraido DEVE passar por `strip_nul` (`recall.sh:334`, `tr -d '\000'`). Byte NUL
em argumento de shell trunca silenciosamente a string.

**1.ter. `wave_model_usage` NAO alimenta `knowledge_fts` — FRONTEIRA DE
SEGURANCA.** Nenhuma tabela de metrica alimenta o indice FTS: o proprio arquivo
documenta isso para `tasks` (`recall.sh:1581`) e `events` (`recall.sh:1635`). Os
unicos tipos indexados em `knowledge_fts` sao `decision`, `block`, `retro`,
`skill`, `suggestion`, `memory` e `circular`.

Isso importa muito mais do que parece: `knowledge_fts` e a fonte do
`cstk recall --context`, cujo resultado e **injetado no prompt** dos
orquestradores no read-back loop (passo PRE-DECISAO das fases `specify`/`plan`).
Manter a tabela nova FORA do FTS garante que o label de modelo — valor de
origem externa — **nunca alcance um contexto de LLM**, fechando por construcao
a superficie de prompt injection indireta (LLM01) e de envenenamento de memoria
(ASI06). A implementacao NAO deve adicionar `wave_model_usage` ao
`knowledge_fts`; fazer isso seria abrir essa superficie.

**2. Filtro de segredos — NAO se aplica.** O nome do modelo NAO passa por
`recall_scrub`. Criterio ja estabelecido no arquivo: campos de **texto livre**
sao scrubbed (`title` em `recall.sh:1614`, `description` em `:1655`), campos
**estruturados** nao — o comentario em `recall.sh:1653-1654` afirma
explicitamente que "event_type e timestamp sao estruturados e NAO passam pelo
filtro". Um identificador de modelo e estruturado, da mesma classe que
`event_type`. Passa-lo pelo filtro arriscaria mutilar o identificador (e a
fidelidade da string bruta e requisito — FR-001).

## Complexity Tracking

Nenhuma violacao de constitution. Tabela nao se aplica.

Registro de complexidade **aceita e justificada** (nao e violacao):

| Escolha | Por que | Alternativa rejeitada porque |
|---------|---------|------------------------------|
| Redundancia entre `otel_subagent_tokens` (total) e as 4 colunas de parcela do subagent | FR-009 exige que consultas existentes sigam funcionando | Substituir a coluna antiga pelas parcelas quebraria consumidores atuais |
| `model` duplicado em `source_id` | Reusa o preambulo de 6 colunas e a constraint UNIQUE comuns a todas as tabelas de metrica | Constraint dedicada divergiria do padrao das outras 11 tabelas |

## Re-check de Constitution (pos-Phase 1)

Reavaliado apos o design, com atencao ao que o design INTRODUZIU:

- **Principio II**: o design nao adiciona nenhum arquivo novo nem nova dep;
  `grep -rl 'sqlite3' cli/lib/` continua apontando so `recall.sh`. Condicoes
  (a), (b) e (c) do amendment 1.1.0 seguem satisfeitas. **PASS**
- **Principio VI**: o design reforca o principio — a mecanica NULL-vs-zero foi
  verificada na fonte (`//` do jq preserva `0` legitimo; `recall_*_or_null`
  converte vazio em `NULL`) e ganhou cenarios de teste com assercao explicita de
  `IS NULL` sobre caso real do corpus. **PASS**
- **Principio IV**: nenhuma nova superficie de rede; a descoberta do R1 e
  leitura local de codigo. **PASS**
- **Complexidade introduzida**: nenhuma camada, servico ou indice novo. Uma
  tabela e 8 colunas, todas aditivas. **PASS**

Nenhum principio MUST em FAIL. Nenhuma `Constitution Exception` necessaria.

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/otel-model-breakdown/plan.md` | Criado |
| `docs/specs/otel-model-breakdown/research.md` | Criado |
| `docs/specs/otel-model-breakdown/data-model.md` | Criado |
| `docs/specs/otel-model-breakdown/quickstart.md` | Criado |
| `docs/specs/otel-model-breakdown/contracts/` | N/A — sem interface externa nova |

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor em backlog executavel
3. `/analyze` — consistencia cross-artifact apos as tasks
