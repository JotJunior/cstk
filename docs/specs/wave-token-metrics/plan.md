# Implementation Plan: Metricas de Tokens por Spawn de Subagente

**Feature**: `wave-token-metrics` | **Date**: 2026-07-25 | **Spec**: [spec.md](./spec.md)

## Summary

Substituir `tool_calls` — hoje o unico proxy de custo do toolkit, e um proxy
grosseiro (uma tool call de 50 tokens conta igual a uma de 50.000) — por consumo
real de tokens, tool-uses e duracao **por spawn de subagente**, capturado ao
vivo, agregado por onda, persistido no `state.json`, indexado na knowledge.db e
exibido nos relatorios que ja existem.

**Abordagem tecnica** (resolvida no Phase 0, ver [research.md](./research.md)):
o unknown central da spec — "qual payload um hook recebe quando um spawn
completa" — foi resolvido com fonte oficial. A doc do Claude Code documenta
**exatamente este caso de uso**: um hook `PostToolUse` com matcher `Agent`
recebe, em `tool_response`, `totalTokens`, `totalDurationMs`, `totalToolUseCount`,
`usage{input,output,cache_read,cache_creation}` e `resolvedModel`. Nao e preciso
ler o transcript ao vivo.

O desenho reusa integralmente o padrao ja provado do hook de `tool_calls`:
**fail-open absoluto, sidecar append-only por onda, hook nunca toca o
`state.json`**; a agregacao acontece em `state-ondas.sh end`, que ja e o ponto
transacional de fechamento com backup + escrita atomica + rehash.

**Achado que molda o desenho**: medicao nos transcripts reais deste projeto
mostra **52 spawns `async_launched` contra 51 `completed`** — desde a v2.1.198
subagentes rodam em background por default, e o `tool_response` de background
**nao carrega campos de uso**. Ou seja, "metrica indisponivel" nao e edge case
raro: e ~metade dos spawns. Por isso o desenho separa `spawns_total` de
`spawns_with_usage` em todo agregado e trata `null != 0` como invariante de
primeira classe, e nao como detalhe de implementacao.

## Technical Context

**Language/Version**: POSIX `sh` puro (sem bash-isms), conforme Constitution
Principio II. Verificado no repo: todos os scripts sob `global/skills/*/scripts/`
e `cli/lib/` seguem essa disciplina.
**Primary Dependencies**: `jq` (dep opcional confinada, ja usada por hooks e por
`cli/lib/recall.sh`); `sqlite3` (dep opcional confinada a `cli/lib/recall.sh`).
Nenhuma dep nova e introduzida.
**Storage**: `state.json` por execucao (fonte de verdade transacional) + sidecar
JSONL por onda (transitorio) + `~/.claude/cstk/knowledge.db` (SQLite, indice
derivado e reconstruivel).
**Testing**: harness POSIX proprio — `./tests/run.sh` (~1678 cenarios). Convencao
1:1 imposta por `--check-coverage`.
**Target Platform**: macOS + Linux (CI Ubuntu). Sem GNU-only.
**Project Type**: CLI/toolkit — single-layer, sem servidor nem frontend.
**Performance Goals**: N/A quantitativo — nao ha alvo numerico de latencia
definido para esta feature e nenhum sera inventado. A restricao qualitativa e
dura: o hook **MUST NOT** bloquear, atrasar ou reprovar uma tool call
(fail-open). O `timeout: 5` do snippet de settings e o teto ja praticado pelos
hooks existentes.
**Constraints**: (a) hook **MUST NOT** escrever no `state.json` (concorrencia
com writes transacionais); (b) linha do sidecar **MUST** ser curta (< PIPE_BUF)
para manter a atomicidade do append O_APPEND; (c) nenhum dado de uso pode ser
estimado.
**Scale/Scope**: poucos spawns por onda (ordem de unidades); dezenas a centenas
de ondas por execucao. `budget.sh` ja vigia `state_size_threshold_bytes`
(default `1048576`, `budget.sh:97-100`).

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (secao "Re-check").*

Constitution v1.2.0 (`docs/constitution.md`, ratificada 2026-04-20, ultima
emenda 2026-06-18).

| Principio | Status | Notas |
|-----------|--------|-------|
| **I. SDD aplica-se recursivamente** (NON-NEGOTIABLE) | PASS | A feature esta sendo desenvolvida pela propria pipeline SDD: `spec.md` -> `clarify` -> este `plan.md` -> `checklist` -> `create-tasks`. Artefatos versionados em `docs/specs/wave-token-metrics/`. |
| **II. Scripts POSIX sh puros, zero dep externa** (NON-NEGOTIABLE) | PASS (via carve-out 1.1.0) | Ver analise das 3 condicoes cumulativas abaixo. Nenhuma dep nova; `jq`/`sqlite3` ja sao deps opcionais confinadas e pre-existentes. Zero bash-isms. |
| **III. Formato canonico de skill** | N/A / PASS parcial | A feature nao cria skill nova. Toca `review-task/SKILL.md` §4.5 apenas para adicionar uma invocacao de helper, preservando o invariante INV-RT-1 (saida colada verbatim). |
| **IV. Zero coleta remota de uso ou dados** (NON-NEGOTIABLE) | PASS | **Ponto de maior atencao desta feature**: ela mede consumo, que e exatamente o tipo de dado que telemetria coletaria. Mitigacao arquitetural: todo dado permanece **local** — sidecar no state dir do projeto, agregado no `state.json` do projeto, indice em `~/.claude/cstk/knowledge.db`. Nenhum egress, nenhum endpoint, nenhum identificador enviado a lugar algum. O hook nao faz rede. |
| **V. Profundidade e reducao de retrabalho acima de metricas de adocao** | PASS | O objetivo e reduzir retrabalho de decisao (escolher modelo/roteamento com base em custo real em vez de proxy grosseiro), nao produzir numero de vaidade. |
| **VI. Veracidade de dados — zero fabricacao** (NON-NEGOTIABLE) | PASS | E o principio estruturante do desenho, nao um checkbox. Ver detalhamento abaixo. |

### Detalhamento do Principio II (carve-out 1.1.0 — 3 condicoes CUMULATIVAS)

| Condicao | Atendimento |
|----------|-------------|
| (a) uso opcional com fallback graceful documentado **e coberto por teste** | `jq` ausente => hook faz `exit 0` silencioso e a onda segue sem a metrica (fail-open). Coberto pelo Cenario 4 do quickstart e pelo cenario de teste #5 do contrato do hook. `sqlite3` ausente => `cstk recall` ja degrada com aviso e exit 0 (comportamento pre-existente, inalterado). |
| (b) codigo que referencia a dep confinado em UM arquivo identificavel | `jq` no hook novo: confinado a `posttooluse-agent-usage.sh` — mesmo confinamento do hook irmao. `sqlite3`: permanece exclusivo de `cli/lib/recall.sh` (a feature nao o espalha). O helper `wave-usage-report.sh` usa `jq` no mesmo padrao dos demais helpers de runtime ja existentes. |
| (c) dep declarada na documentacao da feature | Declarada aqui (Technical Context + esta tabela) e nos contratos, com caminho confinado e descricao do fallback. |

**Ferramentas banidas** (`ripgrep`, `fd`, `bats`): nenhuma e usada.

### Detalhamento do Principio VI (estruturante)

O risco de fabricacao nesta feature e concreto e de dois tipos, ambos endereçados:

1. **Fabricar o contrato de interface.** Todo campo do payload do harness citado
   nos contratos foi extraido da doc oficial baixada e lida
   (`https://code.claude.com/docs/en/hooks.md`, 2026-07-25) e cruzado com
   transcripts reais. Nenhum nome de campo foi suposto. Contratos EXISTENTES do
   repo citam `arquivo:linha`; contratos NOVOS estao marcados
   `[PROPOSTA — a validar na implementacao]`.
2. **Fabricar o dado medido.** Esta e a superficie mais perigosa: um `0` no
   lugar de um `null` transforma "nao medi" em "medi e deu zero". O desenho
   trata isso como invariante dura, replicada em todas as camadas:
   `null` no sidecar -> `null` no `state.json` -> `NULL` no SQLite (via o helper
   ja existente `recall_int_or_null`) -> a palavra `indisponivel` no relatorio.
   Nao existe caminho de codigo que derive um valor de uso por heuristica.

**Numeros nao inventados**: este plano nao afirma nenhum alvo de performance,
custo em $ ou taxa de overhead. Onde a spec pediria um numero que nao temos, o
plano diz N/A e explica por que.

## Project Structure

### Documentation (this feature)

```
docs/specs/wave-token-metrics/
├── spec.md
├── plan.md                                   # This file
├── research.md                               # Phase 0 output
├── data-model.md                             # Phase 1 output
├── quickstart.md                             # Phase 1 output
└── contracts/
    ├── hook-posttooluse-agent-usage.md       # contrato do hook (entrada = harness)
    └── wave-usage-report.md                  # helper + extensoes de agregacao/relatorio
```

### Source Code (repository root)

Arvore real (verificada no repo), com os pontos de toque marcados:

```
cstk/
├── cli/
│   ├── cstk                                  # binario (dispatch) — sem mudanca
│   └── lib/
│       ├── recall.sh                         # MODIFICAR: schema v9->v10, +9 colunas em waves
│       └── hooks.sh                          # MODIFICAR: apply_guard_hooks() copia o hook novo
├── global/
│   └── skills/
│       ├── agente-00c-runtime/
│       │   ├── hooks/
│       │   │   ├── pretooluse-bash-guard.sh          # inalterado
│       │   │   ├── posttooluse-tool-call-tick.sh     # inalterado (padrao de referencia)
│       │   │   ├── posttooluse-agent-usage.sh        # CRIAR
│       │   │   └── settings.snippet.json             # MODIFICAR: +entrada matcher "Agent"
│       │   └── scripts/
│       │       ├── state-ondas.sh                    # MODIFICAR: agregacao no end + reset do sidecar
│       │       ├── budget.sh                         # inalterado (sem dimensao de token)
│       │       ├── report.sh                         # MODIFICAR: secoes 1 e 2
│       │       ├── model-routing-report.sh           # inalterado (invariante: so le .decisions[])
│       │       └── wave-usage-report.sh              # CRIAR
│       └── review-task/
│           └── SKILL.md                              # MODIFICAR: §4.5 +invocacao do helper
└── tests/
    ├── run.sh                                # MODIFICAR: isencao do teste do hook
    ├── test_posttooluse-agent-usage.sh       # CRIAR
    ├── test_wave-usage-report.sh             # CRIAR
    ├── test_state-ondas.sh                   # ESTENDER
    ├── test_report.sh                        # ESTENDER (se existente)
    └── cstk/
        ├── test_recall.sh                    # ESTENDER (migracao v9->v10)
        └── test_hooks.sh                     # ESTENDER (provisionamento do hook novo)
```

**Structure Decision**: nenhuma estrutura nova. A feature se encaixa nos tres
diretorios que ja tratam do assunto — `hooks/` para captura, `scripts/` para
agregacao/relatorio, `cli/lib/` para indexacao — e reusa os pontos de extensao
existentes em vez de criar caminho paralelo. Duas escolhas merecem registro:

1. **Hook novo dedicado (matcher `Agent`) em vez de estender o hook de ticks
   (matcher `*`)**: o filtro por matcher e feito pelo harness, entao o hook novo
   so roda em spawns, sem custo no caminho quente de toda tool call. Custo
   aceito e declarado: mais uma entrada no snippet de settings e mais uma
   isencao existence-guarded em `tests/run.sh::_is_internal_test` (hooks vivem
   fora de `scripts/` e por isso quebram a regra 1:1 do `--check-coverage` —
   precedente literal ja existe em `tests/run.sh:298-303`).
2. **Helper de relatorio novo em vez de estender `model-routing-report.sh`**:
   aquele script documenta no proprio cabecalho (L5-6) que le **somente**
   `.decisions[]` e nao `.waves`. Fazer-lhe ler `.waves` quebraria o invariante
   que ele publica. Como bonus, um script em `scripts/` ganha teste 1:1
   automatico, sem isencao.

## Convencoes de Borda

**N/A parcial — feature single-layer.** Nao ha borda backend↔frontend, DTO
serializado entre servicos, nem case-style negociavel entre camadas de
aplicacao. As bordas reais sao de dado, e valem estas convencoes:

| Borda | Convencao | Validacao | Fonte da verdade |
|-------|-----------|-----------|------------------|
| Harness -> hook (stdin JSON) | camelCase (`totalTokens`, `resolvedModel`, `agentId`) — **imposto pelo harness, nao negociavel** | `jq` com default (`// null`) em todo acesso | doc oficial `code.claude.com/docs/en/hooks.md` |
| Hook -> sidecar JSONL | snake_case (`total_tokens`, `agent_id`) | linha unica `jq -c` | `contracts/hook-posttooluse-agent-usage.md` §2 |
| Sidecar -> `state.json` | snake_case, EN | `state-validate.sh` + sha256 | `data-model.md` |
| `state.json` -> knowledge.db | snake_case, EN, prefixo `agent_` | `PRAGMA table_info` na migracao | `cli/lib/recall.sh` DDL |
| CLI (flags) | kebab-case (`--state-dir`, `--transcript`, `--dry-run`) | parser do proprio script | helpers existentes do runtime |

**Mapper layer**: a traducao camelCase (harness) -> snake_case (toolkit)
acontece em **um unico lugar** — a expressao `jq` do hook. Nenhuma outra camada
ve os nomes do harness. Isso e deliberado: se o harness renomear um campo, o
raio de mudanca e um arquivo.

**Idioma**: identificadores em ingles (regra global do repo); comentarios e
mensagens ao operador em portugues, como no restante do runtime.

## Fases de implementacao sugeridas

Ordem derivada das prioridades da spec. Detalhamento fica para `/create-tasks`.

| Fase | Escopo | Stories | Entrega verificavel |
|------|--------|---------|---------------------|
| F1 | Hook + sidecar + provisionamento + testes | base de US1 | Cenarios 1, 2, 4 do quickstart |
| F2 | Agregacao em `state-ondas.sh end` + `state.json` | US1 | Cenarios 1, 3 |
| F3 | `wave-usage-report.sh aggregate` + `report.sh` §1/§2 | US1 (FR-005) | Cenarios 3, 5, 11 |
| F4 | knowledge.db v9->v10 + ingestao + migracao | US3 (FR-006) | Cenarios 7, 8 |
| F5 | `review-task` §4.5 (custo x roteamento) | US2 (FR-007) | Cenario 6 |
| F6 | Backfill de transcripts | US4 (FR-010/011) | Cenarios 9, 10 |

F1-F3 entregam o valor central (US1) e sao independentes de F4-F6. F6 e a fase
mais isolada e a unica que depende da heuristica de janela temporal — coerente
com sua prioridade P4 na spec.

## Complexity Tracking

> Preencher APENAS se Constitution Check tem violacoes que precisam justificativa.

**Nenhuma violacao de Constitution.** Todos os principios PASS ou N/A; o carve-out
usado (Principio II, amendment 1.1.0) e um mecanismo previsto na propria
constitution, com as 3 condicoes cumulativas satisfeitas e documentadas acima —
nao e excecao nem trade-off pendente. Nenhuma `Constitution Exception` e
necessaria.

## Riscos

Consolidados em [research.md](./research.md) §"Riscos residuais". Os dois de
maior severidade:

- **R1 — ~50% dos spawns sem usage** (`async_launched`). Nao e mitigavel no
  codigo desta feature: e comportamento default do harness. Mitigacao e de
  *apresentacao*: separar `spawns_total` de `spawns_with_usage` e nunca exibir
  total sem cobertura.
- **R2 — hook nao provisionado no projeto-alvo.** Risco herdado, ja materializado:
  neste proprio repo o hook de `tool_calls` nao esta provisionado, e por isso as
  ondas 001-004 desta execucao registram `tool_calls: 0`. A feature nova herda a
  mesma exposicao. Mitigacao: o relatorio distingue "0 spawns" de "metrica nao
  coletada", e `cstk doctor` e o lugar natural para sinalizar a ausencia.

## Re-check pos-Phase 1

Revalidacao apos o design (Etapa 7):

- **Complexidade introduzida**: 2 arquivos novos (1 hook, 1 helper) + extensoes
  em 6 arquivos existentes. Nenhuma camada, servico ou abstracao nova. Nenhum
  mecanismo de provisionamento, lock ou scheduling novo.
- **Principio II**: o design nao adicionou dep alguma; `sqlite3` continua
  confinado a `cli/lib/recall.sh`.
- **Principio IV**: o design confirma-se local-only — nenhum contrato desenhado
  em Phase 1 tem egress.
- **Principio VI**: reforcado no design (`null` propagado ponta a ponta;
  `recall_int_or_null` obrigatorio; palavra `indisponivel` no relatorio).
- **Veredito**: mantido PASS em todos os principios. Nenhuma violacao nova
  introduzida pelo design.

## Artefatos

| Arquivo | Status |
|---------|--------|
| `docs/specs/wave-token-metrics/plan.md` | Criado |
| `docs/specs/wave-token-metrics/research.md` | Criado |
| `docs/specs/wave-token-metrics/data-model.md` | Criado |
| `docs/specs/wave-token-metrics/quickstart.md` | Criado |
| `docs/specs/wave-token-metrics/contracts/hook-posttooluse-agent-usage.md` | Criado |
| `docs/specs/wave-token-metrics/contracts/wave-usage-report.md` | Criado |

## Proximos Passos

1. `/checklist` — quality gate dos requisitos antes de implementar
2. `/create-tasks` — decompor as fases F1-F6 em backlog executavel
3. `/analyze` — consistencia cross-artifact apos as tasks existirem
