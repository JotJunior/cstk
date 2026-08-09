# Implementation Plan: Captura de Consumo Avulso de Uso (Loose Usage Capture)

**Feature**: `loose-usage-capture` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

## Summary

Dar ao operador visibilidade do consumo de tokens/custo por modelo das sessoes
**avulsas** do Claude Code — as que acontecem fora de qualquer execucao das
pipelines SDD `agente-00c`/`feature-00c` — para poder compara-lo, no mesmo
projeto, com o consumo ja medido das pipelines (mix de modelos + custo blended
por milhao de tokens).

Abordagem tecnica, em tres camadas, cada uma reusando um padrao ja em producao
no toolkit:

1. **Captura**: hook `PostToolUse` dedicado (`posttooluse-loose-usage.sh`),
   moldado em `posttooluse-tool-call-tick.sh`, com throttle por intervalo e
   com a deteccao de execucao ativa de `_hook-active-exec.sh` usada em
   **polaridade invertida** — captura quando NAO ha pipeline ativa, o que
   implementa simultaneamente o gatilho periodico (FR-003) e a exclusao de
   dupla contagem (FR-004).
2. **Persistencia**: snapshots TSV por processo/segmento sob
   `~/.claude/cstk/loose-usage/`, escritos por `otel-usage.sh snapshot` **sem
   nenhuma alteracao no script** (os nomes de arquivo e o formato ja batem);
   ingestao posterior numa tabela NOVA do `knowledge.db` (migracao aditiva
   v12 -> v13).
3. **Consulta**: subcomando novo `cstk usage` (+ `cstk usage compare`), com a
   camada SQL delegada aos helpers de `cli/lib/recall.sh` para preservar o
   confinamento de dependencia.

Fio condutor de toda a feature: **ausencia de metrica e `null`/"nao medido",
nunca zero** (Constitution VI) — e cada ponta degrada em no-op silencioso,
jamais bloqueando a sessao do operador (FR-007).

## Technical Context

**Language/Version**: POSIX `sh` (shebang `#!/bin/sh`), conforme Constitution
Principio II. Sem Bash-isms.
**Primary Dependencies**:
- `curl` — ja usado por `otel-usage.sh` (`_ou_have_curl`, linha 136), com
  degradacao se ausente;
- `awk`, `sed`, `sort`, `mktemp` — POSIX canonicos;
- `jq` — dep OPCIONAL com fail-open no hook (mesmo carve-out do molde,
  linha 68) e ja presente em `cli/lib/recall.sh`;
- `sqlite3` — confinado a `cli/lib/recall.sh` (nao adicionar novo arquivo que
  o invoque);
- `lsof` — OPCIONAL, so para `owner_pid`; ja confinado a `otel-usage.sh`
  (`_ou_port_owner`, linha 443, com `command -v lsof || return 1`).

**Storage**: (a) arquivos TSV sob `~/.claude/cstk/loose-usage/` (fonte);
(b) `~/.claude/cstk/knowledge.db` (SQLite, indice derivado) — versao real
verificada nesta onda: `schema_version = 12`.
**Testing**: harness POSIX proprio (`tests/run.sh`). Convencao de mapeamento:
script em `global/skills/<X>/scripts/` -> `tests/test_<n>.sh`; lib em
`cli/lib/` -> `tests/cstk/test_<n>.sh`. Hooks seguem `tests/test_<n>.sh`
(precedente: `tests/test_pretooluse-bash-guard.sh`).
**Target Platform**: macOS e Linux, ambiente local do operador. Sem servidor,
sem container, sem rede externa.
**Project Type**: CLI + runtime de hooks (single-process, local).
**Performance Goals**: caminho quente do hook (tick fora do intervalo de
throttle) sem I/O de rede e sem sourcing de dependencia; teto de execucao do
hook e o `timeout: 5` do registro no harness, e o pior caso de scrape e
`--max-time 3` (`otel-usage.sh` linha 150).
**Constraints**: o hook NUNCA escreve `state.json`/`state.db` nem abre o
`knowledge.db`; stdout/stderr sempre vazios; exit sempre `0`.
**Scale/Scope**: um operador, N projetos, ate poucas sessoes simultaneas por
projeto. Volume de linhas em `loose_usage` proporcional a
(processos x segmentos x modelos) — ordem de grandeza de dezenas por dia.

Nenhum `NEEDS CLARIFICATION` remanescente: os quatro pontos abertos foram
fechados na etapa clarify (dec-005..dec-008, registrados em `spec.md`
§Clarifications) e os demais foram resolvidos no Phase 0
([research.md](./research.md), Decisions 1-11).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 — ver §Re-check.*

Constitution: `docs/constitution.md` **v1.3.0**.

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (MUST) | PASS | Feature nao-trivial entrando pela pipeline completa: `spec.md` + `clarify` + este `plan.md`; `tasks.md` na proxima etapa. Contrato de CLI novo (`cstk usage`) exige nota no CHANGELOG (MINOR — capacidade nova, nada removido/renomeado). |
| II. POSIX sh puro, zero dep externa (MUST) | PASS **com carve-outs declarados** | Ver bloco dedicado abaixo. |
| III. Formato canonico de skill | N/A (com dever de doc) | A feature nao cria skill nova. Toca a skill interna `agente-00c-runtime` (hook novo) — a documentacao do runtime deve mencionar o hook, mas nao ha novo `SKILL.md` a produzir. |
| IV. Zero coleta remota (MUST) | PASS **apos analise explicita** | Ver bloco dedicado abaixo. |
| V. Profundidade sobre adocao (SHOULD) | PASS | Fecha um ponto cego real de custo do operador; nenhum requisito de visibilidade externa. |
| VI. Veracidade de dados / zero fabricacao (MUST) | PASS | Toda ausencia e `null`/"nao medido"; as guardas de ambiguidade do `delta` (mais de uma sessao cresceu, exporter trocou, formato antigo) sao herdadas e imprimem `null`; `owner_pid` indeterminavel grava `unknown`; `indeterminada` do helper nunca vira captura. |

### Principio II — carve-outs aplicaveis (condicoes declaradas aqui, cumprindo (c))

Duas subsecoes da Constitution sao invocadas:

**(1) Optional dependencies with graceful fallback (amendment 1.1.0)** — para
`jq` e `lsof`:

| Condicao | Como e satisfeita |
|----------|-------------------|
| (a) opcional com fallback verificavel | `jq` ausente ⇒ hook faz no-op (exit 0) e a captura simplesmente nao ocorre; `lsof` ausente ⇒ `owner_pid=unknown`, captura segue. Ambos cobertos por cenario de teste. |
| (b) confinada a um arquivo identificavel | `jq` no hook novo (arquivo unico) e em `cli/lib/recall.sh` (ja existente); `lsof` permanece exclusivamente em `otel-usage.sh`. |
| (c) declarada na doc da feature | Este bloco + [research.md](./research.md) Decisions 3 e 7. |

**(2) `sqlite3`** permanece sob o confinamento ja vigente: `cli/lib/usage.sh`
`[PROPOSTA]` **nao** invoca `sqlite3` — delega aos helpers de
`cli/lib/recall.sh`.

A disciplina esta escrita no proprio codigo — `cli/lib/serve-docker.sh`
linhas 11-13: *"Mesma disciplina de `cli/lib/hooks.sh` (unico arquivo
autorizado a `jq`) e `cli/lib/recall.sh` (unico arquivo autorizado a
`sqlite3`)"*.

**Estado real medido nesta onda** (para nao inventar um invariante mais limpo
do que a realidade): `grep -l 'sqlite3' cli/lib/*.sh` retorna **5** arquivos —
`recall.sh`, `doctor.sh`, `mcp-docker.sh`, `serve-docker.sh`, `state.sh`. A
leitura linha a linha separa os casos:

| Arquivo | Natureza das ocorrencias |
|---------|--------------------------|
| `recall.sh` | Unico que **abre um banco** (`sqlite3 -- "$db"`, `-cmd '.timeout 5000'`, etc.) |
| `doctor.sh` | So diagnostico de dependencia: `command -v sqlite3` e `sqlite3 --version` — nunca abre banco |
| `state.sh`, `mcp-docker.sh` | Apenas comentario/texto de ajuda |
| `serve-docker.sh` | Comentario + o nome do pacote npm `better-sqlite3` (outro binario) |

Invariante correto a preservar (e o que a revisao deve checar), ja que o
`grep -l` simples produz falsos positivos. A forma abaixo foi **executada
nesta onda** e retorna exatamente `cli/lib/recall.sh` — exigir espaco depois
de `--` e o que exclui o `sqlite3 --version` de diagnostico do `doctor.sh`
(linha 438):

```sh
# Arquivos que ABREM banco via sqlite3 — deve continuar sendo so recall.sh
grep -nE '(^|[^-[:alnum:]_])sqlite3[[:space:]]+(-cmd[[:space:]]|--[[:space:]])' cli/lib/*.sh
```

Sem a delegacao de `usage.sh` a `recall.sh`, esse conjunto cresceria e a
condicao (b) seria violada.

### Principio IV — analise explicita (nao e carimbo)

O Principio IV proibe requisicao de rede "para endpoint de telemetria,
analytics, feature-flag remoto, ou servico de erro". Esta feature **le** um
endpoint de telemetria. A analise, item a item:

- **Destino**: `127.0.0.1` (loopback), servidor do proprio processo do Claude
  Code do operador. Nenhum pacote deixa a maquina.
- **Direcao**: leitura do proprio consumo; nao ha envio de dado a terceiros.
- **Beneficiario**: o operador, sobre a propria sessao. O rationale do
  Principio IV protege o usuario de coleta pelo AUTOR do toolkit ("cegueira
  operacional do autor sobre adocao" e o custo aceito) — aqui nao ha autor no
  circuito.
- **Artefatos**: permanecem no filesystem local (`~/.claude/cstk/`), sem
  upload automatico — o bullet literal do Principio IV sobre artefatos e
  satisfeito.
- **Precedente vigente**: `otel-usage.sh` faz exatamente esse scrape desde a
  linha v5.28+ e a whitelist do proprio `bash-guard`
  (`.claude/agente-00c-whitelist`, linhas 1-7) documenta o endpoint loopback
  como permitido com a justificativa "Nada sai da maquina".

**Veredito**: PASS. Esta feature nao amplia a superficie de rede existente —
consome a mesma fonte local ja consumida. Um FAIL exigiria envio para fora do
ambiente local, que nao ocorre em nenhum caminho do design.

**GATE**: nenhum FAIL em principio MUST. Prosseguir autorizado.

## Project Structure

### Documentation (this feature)

```
docs/specs/loose-usage-capture/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/       # Phase 1 output
    ├── cli-usage.md
    └── hook-loose-usage.md
```

### Source Code (repository root)

Arvore real do repositorio, com marcacao do que muda:

```
cli/
├── cstk                                   # MODIFICA: dispatch + help do subcomando `usage`
└── lib/
    ├── recall.sh                          # MODIFICA: RECALL_SCHEMA_VERSION 12->13 + DDL da tabela nova
    ├── hooks.sh                           # MODIFICA: flag opt-in --with-loose-usage
    └── usage.sh                           # NOVO: logica de `cstk usage` (SQL delegado a recall.sh)
global/skills/agente-00c-runtime/
├── hooks/
│   ├── posttooluse-tool-call-tick.sh      # INTACTO (molde de referencia)
│   ├── posttooluse-agent-usage.sh         # INTACTO
│   ├── pretooluse-bash-guard.sh           # INTACTO
│   ├── settings.snippet.json              # INTACTO (guard hooks obrigatorios)
│   ├── posttooluse-loose-usage.sh         # NOVO: hook de captura avulsa
│   └── settings.loose-usage.snippet.json  # NOVO: registro opt-in, separado
└── scripts/
    ├── otel-usage.sh                      # INTACTO no caminho principal (snapshot/delta reusados como estao)
    └── _hook-active-exec.sh               # INTACTO (consumido com polaridade invertida)
tests/
├── test_posttooluse-loose-usage.sh        # NOVO (convencao de hooks)
└── cstk/
    ├── test_usage.sh                      # NOVO (convencao cli/lib)
    ├── test_recall.sh                     # ESTENDE: migracao v13
    └── test_hooks.sh                      # ESTENDE: flag opt-in
```

**Structure Decision**: nenhum diretorio novo de topo. A feature se encaixa
nas tres superficies existentes — hooks do runtime, libs do CLI e o indice
`knowledge.db` — porque cada uma ja tem um precedente direto do que precisa
ser feito (hook de metrica fail-open; subcomando de consulta; migracao aditiva
de schema). Criar uma superficie nova custaria mais em manutencao do que
resolve. O unico caminho novo de dados e o diretorio de sidecar
`~/.claude/cstk/loose-usage/`, deliberadamente fora de qualquer repositorio:
uso avulso nao pertence a nenhum projeto versionado.

## Convencoes de Borda

A feature atravessa 3 fronteiras (exporter -> hook -> sidecar -> CLI/DB), logo
a secao se aplica (nao e single-layer).

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Labels do exporter Prometheus | `snake_case` (`session_id`, `query_source`) + valores `camelCase` em `type` (`cacheRead`, `cacheCreation`) | Allowlist de 4 labels no parse | Parse: `otel-usage.sh` `_ou_parse`, linhas 170-197. Os literais `cacheRead`/`cacheCreation` aparecem no consumidor, linhas 387-388 (bloco `jq` de `_ou_cmd_delta`) — o parse nao enumera valores de `type`, so extrai o label |
| Sidecar TSV do segmento | 5 colunas TAB-separadas, sem cabecalho de nomes (so `# session_id`) | Guarda `NF != 5` ⇒ `legacy` ⇒ exit 3 ⇒ `null` | `otel-usage.sh` linhas 317-331 |
| Sidecar `meta.tsv` | `snake_case` nas chaves | Leitura tolerante a chave desconhecida (ignora) | `data-model.md` §LooseUsageProcess |
| Colunas SQLite (`loose_usage`) | `snake_case` | DDL + `UNIQUE(process_key, segment_id, model)` | `cli/lib/recall.sh` (DDL), `data-model.md` |
| Flags de CLI | `kebab-case` (`--project`, `--since`, `--with-loose-usage`) | Parser explicito com `*)` ⇒ exit 2 | `contracts/cli-usage.md` |
| Saida `--json` | `snake_case` nas chaves | — | `contracts/cli-usage.md` |
| Variaveis de ambiente | `SCREAMING_SNAKE_CASE` com prefixo `CSTK_` | — | `CSTK_OTEL_ENDPOINT` (existente), `CSTK_LOOSE_USAGE_INTERVAL_S` `[PROPOSTA]` |

**Mapper layer (sidecar ↔ DB)**: `cli/lib/usage.sh` `[PROPOSTA]` e o unico
tradutor. Responsabilidades: varrer `~/.claude/cstk/loose-usage/*/seg-*/`,
invocar `otel-usage.sh delta --state-dir <segmento>`, converter o JSON
`by_model` em linhas de `loose_usage` e fazer UPSERT pela chave natural.
ORM auto-mapping: **NAO** (SQL escrito a mao, como todo o `recall.sh`).

**Validacao de payload**: nao ha Zod (projeto shell). O equivalente e a guarda
estrutural do `delta`: `NF != 5` ⇒ formato antigo ⇒ `null`. O contrato de
saida do `delta` (`session_id`, `total_cost_usd`, `total_tokens`, `by_source`,
`by_model`) esta em `otel-usage.sh` linhas 370-405 e e consumido literalmente,
sem renomear campo — evitando por construcao o drift de nomes que a secao de
Convencoes de Borda existe para prevenir.

**Prefixo `CSTK_` e proposital** (research.md Decision 3): variaveis com
prefixo `OTEL_` foram observadas AUSENTES no ambiente do subprocesso do
harness, enquanto `CSTK_OTEL_ENDPOINT` estava presente. Qualquer configuracao
nova desta feature usa o prefixo `CSTK_`.

## Re-check de Constitution (pos-Phase 1)

Revalidacao apos o design estar fechado:

| Pergunta | Resposta |
|----------|----------|
| O design introduziu complexidade nao justificada? | Nao. Zero servico novo, zero daemon, zero diretorio de topo. Os dois artefatos novos (1 hook + 1 lib) sao o minimo para separar captura de consulta. |
| Algum MUST deixou de ser respeitado apos o design? | Nao. O ponto de risco era `sqlite3` escapar do confinamento — resolvido pela delegacao de `usage.sh` a `recall.sh` (invariante grep-avel). |
| O design criou caminho que fabrica dado? | Nao. Foram identificados 4 pontos de ausencia (endpoint fora do ar, atribuicao ambigua, `owner_pid` indeterminavel, categoria sem linhas) e todos resolvem em `null`/`unknown`/"nao medido". |
| O design mantem a sessao do operador intocada (FR-007)? | Sim. Hook com exit sempre `0`, stdout/stderr vazios, throttle O(1) no caminho quente e teto de 3 s no scrape. |

**Veredito do re-check**: PASS. Nenhuma linha de Complexity Tracking
necessaria.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa

Nao aplicavel — Constitution Check e re-check passaram sem violacao. Os dois
carve-outs invocados (deps opcionais `jq`/`lsof`; confinamento de `sqlite3`)
sao mecanismos previstos pela propria Constitution (Decision Framework item 4:
"subsecoes de carve-out ... sao mecanismo valido de conformidade"), nao
excecoes que exijam sunset.

## Riscos conhecidos (herdados, nao introduzidos)

| Risco | Origem | Mitigacao no design |
|-------|--------|---------------------|
| Disputa da porta fixa `9464` entre processos | `otel-usage.sh` linhas 40-52 (caso real 2026-07-29) | A ancora e `CSTK_OTEL_ENDPOINT` com porta dinamica por processo; sem essa variavel o hook faz no-op em vez de medir a sessao errada |
| Exporter com multiplas sessoes ⇒ atribuicao ambigua | `otel-usage.sh` linhas 81-103 (caso real 2026-07-28) | Guarda de `delta` herdada: mais de uma sessao cresceu ⇒ `null`, nunca chute |
| Subcontagem do avulso na transicao para pipeline ativa | Decisao de design (research.md Decision 6) | Aceita e documentada: erro sempre no sentido conservador, limitado a 1 intervalo por transicao. SC-002 tem prioridade sobre completude do avulso |
| Verificacao manual via `Bash` bloqueada pelo `bash-guard` | Observado nesta onda (research.md Decision 11) | Cenarios do quickstart usam `--endpoint file://...`; runtime da feature nao e afetado (hooks nao passam por `PreToolUse`) |
