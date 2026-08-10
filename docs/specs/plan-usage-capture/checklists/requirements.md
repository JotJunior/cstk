# Requirements Checklist: Plan Usage Capture

**Purpose**: Quality gate dos requisitos (spec.md + plan.md + data-model.md +
contracts/*.md + quickstart.md) antes de `create-tasks`. Domain generico
("requirements") — a feature mistura CLI (`api`-like) e schema de dados, sem
um dominio unico dominante.
**Created**: 2026-08-10
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Cada campo do payload consumido (`session_id`,
  `workspace.current_dir`/`project_dir`, `rate_limits.five_hour.*`,
  `rate_limits.seven_day.*`) tem requisito funcional + coluna de destino
  definidos? [Completude, Spec §FR-001/FR-009, Data-Model tabela `plan_usage`,
  Contract statusline-hook.md linhas 26-32] {auto}
- [ ] CHK002 - O texto literal de FR-006 (MUST NOT capturar
  `seven_day_opus`/`seven_day_sonnet`/`extra_usage`) cobre TODOS os campos
  que `contracts/statusline-hook.md` (linhas 34-36) e `plan.md` §Constitution
  Check (linha ~93, principio VI) citam como excluidos "por FR-006"
  (`.model`, `.cost`, `.context_window`, `.exceeds_200k_tokens`, `.thinking`,
  `.effort`, `.output_style`, `.version`)? **Nao** — FR-006 so menciona
  literalmente os 3 campos que exigem OAuth; os demais 8 campos citados no
  contrato nunca aparecem no texto de FR-006 nem em nenhum outro FR/Edge
  Case de `spec.md`. [Ambiguity, Spec §FR-006 vs Contract statusline-hook.md
  §linha 34-36] {auto}
- [ ] CHK003 - Existe requisito funcional ou Edge Case cobrindo o
  comportamento de instalacao quando o operador ja possui um
  `statusLine.command` customizado no `settings.json` (risco de sobrescrita
  documentado APENAS em `plan.md` §Riscos conhecidos, nunca em `spec.md`)?
  **Nao** — a mitigacao (`CSTK_STATUSLINE_INNER_COMMAND`, research.md
  Decision 2) ja esta desenhada no nivel de plano, mas nunca virou FR/Edge
  Case rastreavel em `spec.md`. [Gap, Spec §Edge Cases (ausente) vs
  Plan.md §Riscos conhecidos linha ~230] {auto}
- [ ] CHK004 - O comportamento de resiliencia best-effort/fail-open
  (`jq` ausente, `sqlite3`/`knowledge.db` indisponivel, payload malformado,
  nunca atrasar/bloquear a renderizacao da statusline) esta declarado como
  requisito testavel em `spec.md`, ou so em `contracts/statusline-hook.md`
  §Comportamento de captura (linhas 56-70) e `quickstart.md` Cenario 7?
  **So no plano/contrato** — `spec.md` nao tem FR/Edge Case equivalente,
  apesar de este comportamento ser parte do "Independent Test" implicito da
  User Story 1 (a statusline continuar funcionando mesmo com falha de
  captura). [Gap, Spec §Requirements (ausente)] {auto}
- [x] CHK005 - As colunas deliberadamente ausentes do schema (`feature`,
  `wave`, `execution_id`) tem racional citavel e auditavel? [Completude,
  Data-Model §Colunas deliberadamente ausentes linhas 43-48] {auto}
- [x] CHK006 - O gap de numeracao FR-012 → FR-014 (com `FR-013-INFRA-SCHED`
  no lugar de `FR-013`) tem explicacao textual que evita parecer erro de
  digitacao? [Completude, Spec § linhas 204-213 "Decisoes de
  infraestrutura"] {auto}

## Clareza de Requisitos

- [x] CHK007 - FR-010 (throttle) define precisamente a tolerancia numerica
  (2 casas decimais) e a base de comparacao (ULTIMO registro persistido do
  escopo, sem janela temporal)? [Clareza, Spec §FR-010 + Clarifications
  linhas 11-12] {auto}
- [x] CHK008 - FR-002/FR-003/FR-004 distinguem claramente ausencia (`NULL`)
  de valor real, sem depender de termo vago tipo "indisponivel" sem
  definicao operacional? [Clareza, Spec §FR-002/FR-003/FR-004, Edge Cases
  linhas 113-125] {auto}
- [ ] CHK009 - **[CRITICAL]** O comportamento para "rate_limits ausente do
  payload" e o MESMO em todos os artefatos que o descrevem? **Nao —
  CONFLITO real entre artefatos**:
  - `spec.md` FR-002 (linhas 147-150): "MUST persistir `NULL`... **nunca**
    `0`" — linguagem MUST de persistencia, implica um registro E gravado.
  - `spec.md` SC-002 (linha 238-240): "o dado persistido e explicitamente
    ausente (NULL)" — de novo, implica que algo FOI persistido.
  - `spec.md` User Story 3, Acceptance Scenario 2 (linhas 103-107): espera
    que o historico contenha "capturas sem dado" distinguiveis das com
    dado real — so faz sentido se essas capturas viram linhas na tabela.
  - `data-model.md` linhas 69-80 (tabela "Ausencia explicita vs valor
    real"): explicito — "o segundo caso [ausencia de `rate_limits`] gera
    uma linha com `NULL` explicito".
  - **CONTRADIZ** `contracts/statusline-hook.md` linha 60: "`.rate_limits`
    ausente no payload → Pass-through normal; **NENHUM INSERT** (nao e
    'captura com NULL' — e 'sessao sem nenhuma resposta de API')".
  - **CONTRADIZ** `quickstart.md` Cenario 2, passo 2 (linha 22): "**nenhuma
    linha nova** em `plan_usage`" apos processar payload sem `rate_limits`.

  4 referencias em `spec.md`+`data-model.md` dizem "insere linha com NULL";
  2 referencias em `contracts/`+`quickstart.md` dizem "nao insere nada".
  Isto NAO e um caso trivial de "spec vence, corrigir o plano" — inserir
  uma linha NULL a CADA render antes da 1a resposta de API (statusline
  renderiza por evento, nao por polling — research.md Decision 1, ~2x/2min)
  colide com FR-010 (ver CHK010): sem regra de comparacao NULL-vs-NULL, o
  throttle nao dedupe essas linhas e a tabela cresce sem limite ate a
  1a resposta de API completar. E plausivel que a escolha do plano
  ("nenhum INSERT quando ausente") tenha sido deliberada para evitar esse
  flooding, mas isso contradiz o texto MUST de FR-002/SC-002 sem
  documentar a excecao em lugar nenhum. [Conflict, Spec §FR-002/SC-002/
  User-Story-3 vs Contract statusline-hook.md §linha 60 vs Quickstart.md
  §Cenario 2] {auto}
- [ ] CHK010 - FR-010 (throttle) define o comportamento de comparacao
  quando o ULTIMO registro persistido do escopo tem `used_percentage`/
  `resets_at` = `NULL` e a nova captura tambem chega com `rate_limits`
  ausente (NULL vs NULL)? **Nao** — o texto de FR-010 so define a
  tolerancia para valores numericos reais ("bate ate a 2a casa decimal");
  nao ha clausula para o caso NULL. Diretamente relevante para resolver
  CHK009: se a decisao for "sempre inserir NULL" (lado spec.md), falta
  aqui a regra que evita flooding. [Gap, Spec §FR-010] {auto}

## Consistencia de Requisitos

- [x] CHK011 - As 5 respostas da secao `## Clarifications` (Session
  2026-08-10) estao todas refletidas em FRs correspondentes (throttle
  tolerancia/janela → FR-010; dimensao projeto/sessao → FR-009; formato
  `captured_at`/`ingested_at` → FR-014; flags de historico → FR-008)?
  [Consistencia, Spec §Clarifications linhas 9-15 vs FR-008/009/010/014]
  {auto}
- [x] CHK012 - O `CHECK IN ('five_hour','seven_day')` de `data-model.md`
  (linha 28) e consistente com FR-005 (escopos tratados como series
  distintas) e com o default `--scope` (ambos, separados) de
  `contracts/cli-plan-usage.md` (linha 71)? [Consistencia, Spec §FR-005,
  Data-Model linha 28, Contract cli-plan-usage.md linha 71] {auto}
- [x] CHK013 - `plan.md` §Constitution Check (linha ~89) confirma que os
  carve-outs de `jq`/`sqlite3` sao REUSO de carve-outs ja vigentes
  (`loose-usage-capture`/`cstk-cli`), nao uma excecao nova ao Principio II
  (POSIX puro)? [Consistencia, Plan.md §Constitution Check linha 89,
  Research.md Decision 3/6] {auto}

## Qualidade de Criterios de Aceite / Mensurabilidade

- [x] CHK014 - Cada Success Criterion (SC-001..SC-005) e objetivamente
  verificavel sem instrumentacao adicional (ex.: "ausencia de chamada de
  rede" para SC-005, "100% dos horarios interpretaveis como epoch" para
  SC-004)? [Mensurabilidade, Spec §Success Criteria linhas 234-249] {auto}
- [x] CHK015 - Os 7 cenarios de `quickstart.md` cobrem 1:1 os SC-001..
  SC-005 (Cenario 1→SC-001, Cenario 2→SC-002, Cenario 4→SC-003, Cenario
  5→SC-004, Cenario 6→SC-005) mais 2 cenarios adicionais de robustez
  (Cenario 3 throttle/FR-010, Cenario 7 deps ausentes)? [Traceability,
  Quickstart.md linhas 7-74] {auto}
- [ ] CHK016 - O Cenario 2 do `quickstart.md`, que e o teste de aceite de
  SC-002, esta escrito de forma consistente com a redacao de SC-002 (ver
  CHK009 — mesmo conflito, agora do lado "teste de aceite")? **Nao** —
  mesma raiz do CHK009: o passo 2 do Cenario 2 ("nenhuma linha nova") nao
  bate com "o dado persistido e explicitamente ausente (NULL)" de SC-002.
  [Conflict, Quickstart.md §Cenario 2 vs Spec §SC-002] {auto}

## Cobertura de Cenarios / Edge Cases

- [x] CHK017 - Happy path (User Story 1, captura + consulta) e Edge Cases
  de ausencia/formato/ruido de float/throttle estao todos cobertos por
  Acceptance Scenarios ou Edge Cases dedicados? [Cobertura, Spec §User
  Story 1 + Edge Cases linhas 111-138] {auto}
- [x] CHK018 - O gate deterministico `requirement-coverage.sh` confirma que
  todos os 13 requisitos numerados (`FR-001..FR-012`, `FR-014`) tem pelo
  menos um cenario associado? [Cobertura] {auto} — evidencia:
  `RESULT|.../spec.md|requirements=13|covered=13|errors=0`, exit=0.
- [x] CHK019 - Testabilidade sem sessao interativa real (`claude -p` nao
  dispara a statusline) esta coberta tanto como requisito (FR-012) quanto
  como mecanismo concreto de teste (`quickstart.md`, todos os 7 cenarios
  via fixture stdin)? [Cobertura, Spec §FR-012, Research.md Decision 8]
  {auto}
- [ ] CHK020 - Existe cenario cobrindo concorrencia (duas invocacoes do
  script de statusline em paralelo, ex.: renders simultaneos de duas
  janelas do terminal na mesma sessao) escrevendo no `knowledge.db` ao
  mesmo tempo? **Nao** — nenhum FR/Edge Case/cenario de `quickstart.md`
  aborda concorrencia de escrita; `plan.md`/`research.md` tambem nao
  mencionam locking/retry para este caminho especifico (so
  `recall_apply_sql_with_retry`, citado no gate de seguranca do plan.md,
  sem cenario de teste dedicado). [Gap, Spec §Edge Cases (ausente)] {auto}

## Requisitos Nao-Funcionais

- [x] CHK021 - Requisito de zero coleta remota (Principio IV) e testavel e
  tem cenario dedicado? [NFR, Spec §FR-011, Quickstart.md §Cenario 6] {auto}
- [ ] CHK022 - Ha requisito ou budget explicito de latencia/overhead
  aceitavel adicionado pela captura por render da statusline (ex.: "captura
  MUST adicionar no maximo Xms por render")? **Nao** — `contracts/
  statusline-hook.md` linha 69 menciona "nenhuma chamada de rede, throttle
  O(1)" como caracteristica de design, mas nao ha numero/threshold
  verificavel em nenhum artefato. [Gap, Plan.md/Contract (sem numero)] {auto}
- [x] CHK023 - Persistencia local exclusiva (Principio IV) e migracao
  aditiva de schema (sem `ALTER`/`DROP`) estao ambas evidenciadas com
  comando/linha real, nao suposicao? [Mensurabilidade, Data-Model
  §Migracao linhas 61-67 — `RECALL_SCHEMA_VERSION` 13→14 medido via
  `grep -n RECALL_SCHEMA_VERSION cli/lib/recall.sh`] {auto}

## Dependencias e Premissas

- [x] CHK024 - As dependencias opcionais confinadas (`jq`, `sqlite3`) tem
  fallback definido para quando estao ausentes (captura pulada, pass-through
  intacto, exit sempre 0)? [Completude, Contract statusline-hook.md §linhas
  63-64, Quickstart.md §Cenario 7] {auto}
- [x] CHK025 - A premissa de que `statusLine.command` e uma chave UNICA no
  `settings.json` (nao um array, ao contrario de `hooks.PostToolUse[]`) foi
  verificada empiricamente, nao suposta? [Assumption, Research.md Decision
  1 linhas 10-25 — `grep -n statusLine` no repo inteiro = zero ocorrencias
  previas] {auto}

## Ambiguidades e Conflitos — Decisao do Dono do Produto

- [ ] CHK026 - **[Escopo / regressao de rascunho original]** A exclusao de
  `.cost` e `.context_window` do payload (fora de escopo desde FR-006, sem
  coluna equivalente no schema — `data-model.md` nao lista nenhuma coluna
  `session_cost_usd`/`session_input_tokens`/etc.) e uma reducao deliberada
  frente ao rascunho de schema que o operador produziu ANTES desta feature
  comecar, que continha as colunas: `session_cost_usd`,
  `session_input_tokens`, `session_output_tokens`,
  `cache_read_input_tokens`, `cache_creation_input_tokens` e `model_id`.
  Consequencia colateral verificada: a regra nao-negociavel do plano de
  onda "(d) rate_limits e gauge da CONTA; cost/context_window sao
  cumulativos da SESSAO — agregar com MAX, jamais SUM" ficou sem objeto nos
  artefatos (nenhuma coluna cumulativa de custo/contexto e persistida por
  esta feature). **Pergunta ao dono do produto**: a exclusao de `.cost`/
  `.context_window` (e das 5 colunas correlatas do rascunho original) foi
  intencional para esta feature, ficando reservada para uma feature futura
  dedicada a custo/tokens de sessao? Ou deveria ser reincluida agora,
  antes de `create-tasks` gerar o backlog de schema? Se confirmado o corte:
  a regra (d) fica formalmente N/A para `plan-usage-capture` (documentar
  isso explicitamente evita reabrir a duvida numa proxima revisao). [Spec
  §FR-006, Data-Model.md (colunas ausentes), fora do rascunho original do
  operador] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]`/`[Ambiguity]`/`[Conflict]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- **Achado mais critico desta rodada**: CHK009/CHK010/CHK016 descrevem o
  MESMO conflito sob 3 angulos (requisito, throttle, cenario de teste) — o
  comportamento de "rate_limits ausente" diverge entre `spec.md`/
  `data-model.md` (inserir linha com NULL) e `contracts/statusline-hook.md`/
  `quickstart.md` (nao inserir nada). Isto precisa ser resolvido via
  `/clarify` (ou correcao direta do plano, se o operador confirmar qual
  lado esta certo) ANTES de `create-tasks` decompor a tarefa de ingestao —
  as duas leituras geram implementacoes e testes de aceite incompativeis.
