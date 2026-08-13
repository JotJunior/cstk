# Feature Specification: Avanco atomico do ponteiro no fechamento de onda

**Feature**: `wave-close-advance`
**Created**: 2026-08-13
**Status**: Draft

## Contexto

O contrato de resume dos orquestradores 00c continua a execucao a partir
de `.next_instruction` ("sempre continua de `.next_instruction`" —
agente-00c-feature-orchestrator.md, Fronteira command↔orquestrador). O
avanco do ponteiro ao fechar uma onda, porem, e hoje DOIS writes
desacoplados que ninguem valida juntos:

1. `state-rw.sh set --field '.current_stage'` (avanca a fase);
2. `state-ondas.sh end --next-instruction` (opcional) OU um segundo
   `set` de `.next_instruction`.

O proprio `reconcile-wave` documenta a lacuna: "avancar ponteiro (...)
`end` NAO faz isto" (state-ondas.sh, passo 4 do reconcile). Nada no
runtime rejeita o estado intermediario — `state-validate.sh` so checa
que `next_instruction` EXISTE como string, nao coerencia com a etapa.

Caso real observado (2026-08-13): o orquestrador fechou a onda-001
avancando `current_stage` para `clarify`, mas deixou `next_instruction`
= "Iniciar etapa specify". Um resume fiel ao contrato re-executaria a
etapa concluida e sobrescreveria o `spec.md`. A variante escapa do
`reconcile-wave` POR CONSTRUCAO: a guarda de idempotencia e binaria
sobre o estado da onda (`wave-status != open` ⇒ `noop (closed)`), entao
onda fechada com ponteiro incoerente e invisivel para a rede de
seguranca.

O mesmo risco existe DENTRO do reconcile-wave atual: ele fecha a onda
(`end`) e so DEPOIS avanca o ponteiro em dois `set` separados — um crash
entre os writes produz exatamente a variante invisivel (onda fechada +
ponteiro stale).

Precedente da casa: `--next-instruction` foi adicionado ao `end`
justamente para eliminar um `set` separado que deixava backup/sha
defasados (comentario em state-ondas.sh). Esta feature completa o
movimento: o avanco INTEIRO do ponteiro (fase + instrucao) entra no
mesmo write atomico do fechamento.

## User Scenarios & Testing

### US1 — Orquestrador fecha onda avancando de fase

Ao concluir a etapa da onda, o orquestrador chama
`state-ondas.sh end --motivo-termino etapa_concluida_avancando
--advance [--terminal-phase P]`. `current_stage` e `next_instruction`
saem coerentes do MESMO write do fechamento — nao existe janela nem
sequencia de chamadas que produza o meio-avanco.

### US2 — Orquestrador pausa no meio de uma etapa

Onda fechada com `threshold_proxy_atingido` (etapa NAO concluida): o
orquestrador NAO usa `--advance`; usa `--next-instruction "Continuar
etapa X ..."` como hoje. `current_stage` nao muda.

### US3 — Rede de seguranca do command pai

`reconcile-wave` recupera onda aberta usando o MESMO caminho atomico
(end + advance num write) — o crash entre "fechar" e "avancar" deixa de
existir tambem na recuperacao.

## Requirements

### FR-001

`state-ondas.sh end` MUST aceitar a flag `--advance`, valida SOMENTE com
`--motivo-termino etapa_concluida_avancando` (qualquer outro motivo ⇒
erro de uso, exit 2, ANTES de qualquer write).

### FR-002

Com `--advance`, o `end` MUST resolver a proxima fase a partir de
`.current_stage` via `pipeline.sh next-stage` e gravar, NO MESMO write
atomico do fechamento da onda (transacao C4 sob SQLite; unico
jq+atomic-write sob JSON): `.current_stage = <proxima>` e
`.next_instruction = "Iniciar etapa <proxima>."` (template
deterministico).

### FR-003

`--terminal-phase PHASE` MUST ser aceita junto de `--advance` (mesma
semantica do reconcile-wave: feature-00c termina em `review-task`;
agente-00c em `review-features`). Se `.current_stage` == terminal-phase,
ou `pipeline.sh next-stage` nao resolve proxima fase, o `end --advance`
MUST falhar fail-closed (exit != 0, estado intacto) — fechamento
terminal usa `--motivo-termino concluido` + promocao de status, nunca
`--advance`.

### FR-004

`--next-instruction TEXT` combinada com `--advance` MUST sobrescrever
apenas o TEXTO da instrucao (o avanco de `current_stage` ocorre do mesmo
jeito) — preserva instrucoes ricas ("Iniciar etapa execute-task —
continuar da task 2.3") sem reabrir a janela de dois writes.

### FR-005

`reconcile-wave` MUST usar o caminho `end --advance` no ramo de
recuperacao com proxima fase (substituindo o `end` + dois `set`
separados), mantendo o texto de instrucao proprio da rede de seguranca
via FR-004. O ramo terminal (promocao de status) permanece como esta
(ja e um read-patch-write atomico proprio).

### FR-006

Paridade de backend (invariante da state-db-runtime-parity): o
comportamento de `--advance` MUST ser identico sob `state.json` e
`state.db`, coberto por cenarios de teste nos DOIS backends.

### FR-007

A prosa dos dois orquestradores (passo de fechamento de onda) MUST
instruir o uso de `end --advance` quando a etapa concluiu, eliminando a
instrucao vaga de "avancar a fase" por writes avulsos.

### FR-008

Paridade Bash↔MCP: a tool `close_wave` do servidor MCP de estado MUST
expor os campos opcionais `advance` (boolean) e `terminal_phase`
(token), repassados como `--advance`/`--terminal-phase` ao
`state-ondas.sh end` — sem isso o caminho MCP nao consegue cumprir o
contrato do FR-007. A validacao semantica (motivo compativel, fase
terminal) permanece no helper (fonte unica de regra).

## Success Criteria

- **SC-001**: apos QUALQUER fechamento de onda com avanco (orquestrador
  ou reconcile-wave), `next_instruction` referencia a mesma etapa de
  `current_stage` — nao existe sequencia de chamadas do runtime que
  produza o par incoerente.
- **SC-002**: `end --advance` com fase terminal ou motivo invalido falha
  SEM tocar o estado (fail-closed).
- **SC-003**: zero mudanca de comportamento para chamadas `end` sem
  `--advance` (compat total com orquestradores/testes existentes).

## Out of Scope

- Reparo retroativo de ponteiro stale em ondas JA fechadas (opcao 2 da
  analise — reconcile de onda closed); pode virar feature futura se o
  padrao reaparecer em states antigos.
- Mudanca do contrato de resume (opcao 3 — derivar instrucao de
  `current_stage` tratando `next_instruction` como advisory).
- Validacao de coerencia em `state-validate.sh` (o campo continua
  free-text; a coerencia passa a ser garantida por construcao no
  produtor).
