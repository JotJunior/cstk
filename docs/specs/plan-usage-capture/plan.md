# Implementation Plan: Captura de Uso do Plano via Statusline (Plan Usage Capture)

**Feature**: `plan-usage-capture` | **Date**: 2026-08-10 | **Spec**: [spec.md](./spec.md)

## Summary

Dar ao operador visibilidade do quanto do limite de plano (`/usage`, janelas
`five_hour`/`seven_day`) ja foi consumido, **sem exigir credencial OAuth** —
a unica via observada que expoe esse dado sem token e o payload que o
harness Claude Code alimenta no stdin do comando de `statusLine`
(memoria `reference_statusline_usage_payload.md`, campo `rate_limits`).

Abordagem tecnica, em duas camadas (mais enxuta que `loose-usage-capture`,
que precisa de sidecar intermediario porque a fonte la e um scrape HTTP
caro — aqui o dado ja chega de graca a cada render):

1. **Captura**: script novo `statusline-plan-usage.sh`, configurado como
   `statusLine.command` no `settings.json` do harness — mecanismo distinto
   do array `hooks.PostToolUse[]` ja gerenciado por `cli/lib/hooks.sh`.
   Le o payload do stdin, extrai `rate_limits.five_hour`/`seven_day`,
   aplica throttle (2 casas decimais contra o ultimo registro do escopo) e
   insere direto em `plan_usage` — sem sidecar intermediario. Pass-through
   obrigatorio do stdout (research.md Decision 2) para nao apagar a UI de
   quem ja tem statusline customizada.
2. **Persistencia + Consulta**: tabela nova `plan_usage` no `knowledge.db`
   (migracao aditiva v13 -> v14) + subcomando novo `cstk plan-usage`
   (+ `history`), com a camada SQL delegada a `cli/lib/recall.sh`
   (unico arquivo autorizado a `sqlite3` — mesmo confinamento de
   `loose-usage-capture`).

Fio condutor: **ausencia TOTAL de `rate_limits` nunca gera linha em
`plan_usage` (dec-029) — a ausencia de linha E o estado "nao medido",
apresentado assim na leitura, nunca fabricado como `0`** (Constitution VI
/ User Story 3) — e toda ponta (captura sem `jq`, sem `sqlite3`, payload
malformado) degrada em pass-through silencioso, jamais bloqueando a
sessao do operador.

## Technical Context

**Language/Version**: POSIX `sh` (shebang `#!/bin/sh`), Constitution
Principio II. Sem Bash-isms.
**Primary Dependencies**:
- `jq` — dep OPCIONAL com fallback fail-open (research.md Decision 3),
  reuso do carve-out ja vigente em `cli/lib/recall.sh`/`cli/lib/usage.sh`;
- `sqlite3` — confinado a `cli/lib/recall.sh` (research.md Decision 6);
  OPCIONAL na captura (fail-open), a consulta via `cstk plan-usage`
  segue a mesma degradacao ja documentada em `contracts/cli-usage.md`
  para `cstk usage`.
**Storage**: `~/.claude/cstk/knowledge.db` (SQLite, indice) — versao real
verificada nesta onda: `RECALL_SCHEMA_VERSION = 13` (`grep -n
RECALL_SCHEMA_VERSION cli/lib/recall.sh`). Sem arquivo sidecar
intermediario (diferenca deliberada vs `loose-usage-capture` — ver
research.md Decision 4).
**Testing**: harness POSIX proprio (`tests/run.sh`). Convencao: hook em
`plugins/cstk/skills/agente-00c-runtime/hooks/` -> `tests/test_<n>.sh`
(precedente: `tests/test_posttooluse-loose-usage.sh`); lib em `cli/lib/`
-> `tests/cstk/test_<n>.sh` (precedente: `tests/cstk/test_usage.sh`).
**Target Platform**: macOS e Linux, ambiente local do operador. Sem
servidor, sem container, sem rede externa (o dado ja chega no stdin do
proprio processo local — nem sequer um scrape loopback como
`otel-usage.sh`).
**Project Type**: CLI + entry-point de statusline (single-process, local).
**Performance Goals**: caminho quente (render sem mudanca de
`rate_limits`) sem I/O de rede; teto implicito e o de qualquer
`statusLine.command` do harness (nao documentado numericamente pelo
harness; o design nao introduz nenhuma chamada bloqueante — 1 query SQL
condicional no maximo).
**Constraints**: `statusline-plan-usage.sh` NUNCA sai com codigo != 0;
stdout SEMPRE contem o texto a renderizar (research.md Decision 2) — o
unico dos dois requisitos de nao-regressao desta feature que nao vem
diretamente de um FR da spec, e sim de uma condicao de viabilidade de
instalacao (ver research.md Decision 2 para o racional completo).
**Scale/Scope**: um operador, N sessoes simultaneas. Volume de linhas em
`plan_usage` proporcional a (renders com `rate_limits` presente x
mudancas reais alem do throttle) — ordem de grandeza de dezenas por
sessao longa, muito menor que `loose_usage` (que grana por modelo x
segmento).

Nenhum `NEEDS CLARIFICATION` remanescente: os 5 pontos abertos foram
fechados na etapa `clarify` (dec-008, dec-009, dec-013, dec-014, dec-015 —
dec-015 corrigiu dec-010 de epoch para TEXT ISO em `captured_at`/
`ingested_at`; registrados em `spec.md` §Clarifications) e as decisoes de
design puramente tecnicas (sem impacto em requisito visivel ao operador)
foram fechadas no Phase 0 ([research.md](./research.md), Decisions 1-8).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 — ver
§Re-check.*

Constitution: `docs/constitution.md` **v1.3.0**.

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (MUST) | PASS | Feature entra pela pipeline completa: `spec.md` + `clarify` + este `plan.md`; `tasks.md` na proxima etapa. Contrato de CLI novo (`cstk plan-usage`) exige nota no CHANGELOG (MINOR — capacidade nova). |
| II. POSIX sh puro, zero dep externa (MUST) | PASS **com carve-outs ja vigentes, nao novos** | `jq` (research.md Decision 3) e `sqlite3` (research.md Decision 6) reusam carve-outs ja declarados em `loose-usage-capture`/`cstk-cli` — nenhuma dep obrigatoria nova introduzida. |
| III. Formato canonico de skill | N/A (com dever de doc) | Nao cria skill nova. Toca a skill interna `agente-00c-runtime` (script novo em `hooks/`) — documentado em `contracts/statusline-hook.md`, sem `SKILL.md` novo a produzir. |
| IV. Zero coleta remota (MUST) | PASS — caso mais simples que `loose-usage-capture` | A fonte e o **stdin do proprio processo local** alimentado pelo harness — nao ha sequer um scrape loopback (`otel-usage.sh` le HTTP `127.0.0.1`; esta feature nao faz nenhuma chamada de rede, nem local). Nenhum artefato sai do filesystem local (`~/.claude/cstk/knowledge.db`). |
| V. Profundidade sobre adocao (SHOULD) | PASS | Fecha o ponto cego de "quando vou bater o limite do plano" sem exigir OAuth — nenhum requisito de visibilidade externa. |
| VI. Veracidade de dados / zero fabricacao (MUST) | PASS | Ausencia TOTAL de `rate_limits` nunca gera linha (dec-029, FR-002) — nenhum `0`/`NULL` fabricado; leitura mostra "nao medido". `resets_at` nunca reinterpretado como string (FR-003); `used_percentage` persistido sem arredondar (FR-004); nenhum campo alem de `five_hour`/`seven_day` e capturado (FR-006) — os campos que exigem OAuth simplesmente nao tem coluna. |

**GATE**: nenhum FAIL em principio MUST. Prosseguir autorizado.

## Project Structure

### Documentation (this feature)

```
docs/specs/plan-usage-capture/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md     # Phase 1 output
├── quickstart.md      # Phase 1 output
└── contracts/          # Phase 1 output
    ├── cli-plan-usage.md
    └── statusline-hook.md
```

### Source Code (repository root)

Arvore real do repositorio (`ls cli/lib/`, `ls
plugins/cstk/skills/agente-00c-runtime/hooks/` verificados nesta onda),
com marcacao do que muda:

```
cli/
├── cstk                                      # MODIFICA: dispatch + help do subcomando `plan-usage`
└── lib/
    ├── recall.sh                             # MODIFICA: RECALL_SCHEMA_VERSION 13->14 + DDL de `plan_usage`
    └── plan-usage.sh                         # NOVO: logica de `cstk plan-usage` (+ `history` + `ingest --stdin`), SQL delegado a recall.sh
plugins/cstk/skills/agente-00c-runtime/
└── hooks/
    ├── posttooluse-loose-usage.sh            # INTACTO (molde de referencia — disciplina fail-open/throttle)
    ├── posttooluse-tool-call-tick.sh         # INTACTO
    ├── settings.snippet.json                 # INTACTO
    └── statusline-plan-usage.sh              # NOVO: entry-point de statusLine.command
tests/
├── test_statusline-plan-usage.sh             # NOVO (convencao de hooks/entry-points)
└── cstk/
    ├── test_plan-usage.sh                    # NOVO (convencao cli/lib)
    └── test_recall.sh                        # ESTENDE: migracao v14
```

**Structure Decision**: nenhum diretorio novo de topo. A feature se
encaixa em duas superficies existentes (lib do CLI, indice
`knowledge.db`) e adiciona um unico ponto de entrada novo
(`statusline-plan-usage.sh`) porque o mecanismo `statusLine.command` nao
tem overlap com nenhum hook ja registrado — nao ha como reusar
`posttooluse-*.sh` sem inventar um payload que o harness nunca emite ali.
Ao contrario de `loose-usage-capture`, nao ha diretorio de sidecar novo:
o dado ja chega pronto no stdin a cada render, entao a captura escreve
direto no indice.

## Convencoes de Borda

A feature atravessa 2 fronteiras (payload da statusline -> hook ->
CLI/DB), logo a secao se aplica.

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|-------------------|
| Payload da statusline (JSON) | `snake_case` (`session_id`, `rate_limits`, `used_percentage`, `resets_at`) | Schema observado, nao inferido | Memoria `reference_statusline_usage_payload.md` |
| Colunas SQLite (`plan_usage`) | `snake_case` | DDL; sem `UNIQUE` de chave natural (append-only, research.md Decision 4) | `cli/lib/recall.sh` (DDL), `data-model.md` |
| Flags de CLI | `kebab-case` (`--scope`, `--limit`, `--since`, `--json`, `--db`) | Parser explicito com `*)` ⇒ exit 2 | `contracts/cli-plan-usage.md` |
| Saida `--json` | `snake_case` nas chaves, `null` para ausencia | — | `contracts/cli-plan-usage.md` |
| Variaveis de ambiente | `SCREAMING_SNAKE_CASE` com prefixo `CSTK_` | — | `CSTK_STATUSLINE_INNER_COMMAND` `[PROPOSTA]` (research.md Decision 2) |

**Mapper layer (payload ↔ DB)**: `statusline-plan-usage.sh` `[PROPOSTA]`
e o unico tradutor — extrai os 3 campos consumidos do payload
(`session_id`, `workspace.*`, `rate_limits.*`) e chama `cstk plan-usage
ingest --stdin` (que delega o INSERT a `cli/lib/recall.sh`). Sem ORM;
SQL escrito a mao, como todo `recall.sh`.

**Validacao de payload**: sem Zod (projeto shell). Equivalente e a
checagem estrutural feita por `jq -e '.rate_limits'` — ausencia da chave
(`jq` retorna erro/null) e tratada como "sem `rate_limits`", nao como
erro fatal (Edge Case da spec, User Story 3).

**Prefixo `CSTK_`**: mesma disciplina de `loose-usage-capture`
(`research.md` daquela feature, Decision 3) — qualquer variavel de
configuracao nova desta feature usa o prefixo `CSTK_`.

## Re-check de Constitution (pos-Phase 1)

| Pergunta | Resposta |
|----------|----------|
| O design introduziu complexidade nao justificada? | Nao. Zero servico novo, zero daemon, zero diretorio de topo, zero sidecar (mais simples que `loose-usage-capture` porque o dado ja chega pronto no stdin). |
| Algum MUST deixou de ser respeitado apos o design? | Nao. O ponto de risco era `sqlite3`/`jq` escaparem do confinamento — resolvido pela delegacao a `recall.sh` e pelo confinamento por arquivo (research.md Decisions 3 e 6). |
| O design criou caminho que fabrica dado? | Nao. `rate_limits` ausente por completo ⇒ nenhuma linha inserida (dec-029); nenhum campo fora de `five_hour`/`seven_day` ganha coluna. |
| O design mantem a sessao do operador intocada? | Sim — MAS com uma condicao nova em relacao ao molde `PostToolUse`: o pass-through obrigatorio de stdout (research.md Decision 2) e o mecanismo que garante isso aqui, porque `statusLine.command` (diferente de um hook) tem OUTPUT visivel ao operador a cada render; falhar em pass-through quebraria a UI, nao so a captura. |

**Veredito do re-check**: PASS. Nenhuma linha de Complexity Tracking
necessaria.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam
> justificativa

Nao aplicavel — Constitution Check e re-check passaram sem violacao. Os
dois carve-outs invocados (`jq` opcional; confinamento de `sqlite3`) sao
reuso de mecanismos ja declarados por features anteriores
(`loose-usage-capture`, `cstk-cli`), nao excecoes novas que exijam sunset.

## Revisao de Seguranca (gate `owasp-security`)

Revisao de design (nao ha codigo ainda — gate roda sobre `plan.md` +
`contracts/*.md`). Superficie analisada: (1) parse de JSON arbitrario do
stdin da statusline via `jq`; (2) INSERT em `plan_usage` via
`cli/lib/recall.sh`; (3) subcomando CLI `cstk plan-usage` local.

| Vetor (OWASP) | Achado | Mitigacao MANDATORIA no design |
|----------------|--------|----------------------------------|
| A05 Injection (SQL) | O payload da statusline e, em ultima instancia, controlado pelo processo do harness — mas `session_id`/`project_path` sao strings de origem externa ao script e NAO devem ser concatenadas cru em SQL | `statusline-plan-usage.sh`/`cli/lib/plan-usage.sh` MUST escapar todo valor extraido do payload via `sql_escape` (`cli/lib/recall.sh` linha 223, `s/'/''/g`) antes de compor qualquer `INSERT INTO plan_usage`, e MUST usar `recall_apply_sql_with_retry` (linha 2393) — **mesmo caminho ja usado por `usage.sh` para `loose_usage`**, nao um novo |
| A05 Injection (comando, `jq` parse) | `jq` e um parser JSON seguro por construcao (nao interpreta o conteudo como codigo); risco residual so existe se um valor extraido for reusado depois em `eval`/interpolação de shell sem aspas | Nenhum valor extraido do payload MUST ser passado a `eval`, `sh -c`, ou interpolado sem aspas duplas em comando algum — regra ja coberta pela disciplina POSIX geral do Principio II (variaveis sempre entre aspas) |
| A02 Security Misconfiguration / exposicao de dado local | `session_id`/`project_path` ficam em texto plano em `plan_usage`, no mesmo `knowledge.db` que ja guarda dado equivalente (`loose_usage.project_path`, `executions.session`) | Nenhuma mitigacao NOVA necessaria — `recall_normalize_db_perms` (linha 691, `chmod 600`) ja se aplica ao arquivo `knowledge.db` inteiro, cobrindo `plan_usage` automaticamente por ser a mesma base; nenhuma tabela tem permissao por-tabela em SQLite |
| A09 Logging Failures | Erros de captura (jq/sqlite3 ausente, INSERT falho) nao devem vazar para stdout (contaminaria a UI da statusline) nem para logs persistentes com dado sensivel | `statusline-plan-usage.sh` MUST descartar erros de captura silenciosamente ou envia-los so a stderr (nunca stdout) — ja coberto pelo contrato de pass-through (`contracts/statusline-hook.md` §Contrato de saida) |
| Principio IV (Zero Coleta Remota) | Nenhum ponto do design faz requisicao de rede — fonte e o stdin do proprio processo local | PASS sem mitigacao adicional (mais simples que `loose-usage-capture`, que ao menos faz scrape loopback) |
| LLM01/ASI09 (dado nao-confiavel tratado como instrucao) | N/A neste design — o payload da statusline e consumido apenas como DADO (campos JSON especificos extraidos por caminho fixo), nunca interpretado como instrucao/prompt para um LLM | N/A |

**Veredito**: nenhum achado `critical`/`high` — todos os vetores tem
mitigacao ja disponivel por reuso de helper existente (`sql_escape`,
`recall_apply_sql_with_retry`, `recall_normalize_db_perms`), sem
necessidade de mecanismo novo. `create-tasks` MUST incluir uma task
explicita para o uso de `sql_escape` no INSERT de `plan_usage` (nao e
opcional — e o unico ponto do design que precisa de codigo novo
respeitando um padrao ja existente, em vez de so reusar algo pronto).

## Riscos conhecidos

| Risco | Origem | Mitigacao no design |
|-------|--------|-----------------------|
| `statusLine.command` e uma chave UNICA no `settings.json` — instalar esta feature sem cuidado apaga a statusline customizada de quem ja tem uma | Observado nesta onda (nenhum precedente de codigo; so o GOTCHA da memoria) | Pass-through obrigatorio via `CSTK_STATUSLINE_INNER_COMMAND` (research.md Decision 2); mecanismo de instalacao exato fica para `create-tasks` decompor, mas o contrato de pass-through ja esta fixado aqui |
| `rate_limits` so aparece apos 1a resposta de API completar — feature instalada numa sessao nova pode parecer "sem dado" por um tempo | Memoria, GOTCHA 1 | Documentado em `contracts/statusline-hook.md` e no Cenario 2 do `quickstart.md`; comportamento correto (nenhuma linha ate a 1a resposta completar, leitura mostra "nao medido"), nao um bug |
| Testar exige fixture via stdin, nao sessao real (`claude -p` nao dispara statusline) | Memoria, GOTCHA 4 | research.md Decision 8; `tests/test_statusline-plan-usage.sh` segue o precedente de `test_posttooluse-loose-usage.sh` |
