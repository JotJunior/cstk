# Requirements Checklist: feature-reopen

**Purpose**: Validar a qualidade dos requisitos de `spec.md` (completude,
clareza, consistencia, mensurabilidade, cobertura) apos a reconciliacao com
a resposta do operador ao `block-001` (dec-022) — sem re-decidir os dois
pontos ja fechados (desvio constitucional do `gh`; escopo do backend).
**Created**: 2026-08-11
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [research.md](../research.md)

## Completude de Requisitos

- [x] CHK001 - O gate deterministico de cobertura FR-para-cenario roda sem
      findings pendentes? [Completude] {auto}
      Evidencia: `requirement-coverage.sh docs/specs/feature-reopen/spec.md`
      → `RESULT|...|requirements=22|covered=22|errors=0` (rodado nesta onda).
- [x] CHK002 - O contrato de CLI (subcomando/flags/exit-codes/stdout) da nova
      sonda de trabalho pendente (`commit-mode.sh`, FR-021, Decision 9) esta
      especificado em algum artefato, e nao so mencionado em prosa?
      [Completude, Spec §FR-021] {auto}
      **[Gap]**: `research.md` Decision 9 diz apenas "subcomando novo" sem
      nomea-lo; `plan.md` T-50..T-53 e `data-model.md::PendingWorkProbe`
      descrevem o COMPORTAMENTO (branch nao mesclada, skip nao-fatal,
      `--` separador) mas nenhum arquivo define o nome exato do subcomando,
      suas flags (`--branch`? posicional? `--state-dir`?), exit codes nem o
      formato de stdout parseavel — diferente de `state-rounds.sh`, que tem
      `contracts/state-rounds.md` inteiro dedicado. Busca confirmatoria:
      `grep -rn "pending-work-probe\|probe-pending-work\|commit-mode.sh.*probe"
      docs/specs/feature-reopen/*.md docs/specs/feature-reopen/contracts/*.md`
      → so 1 ocorrencia (a propria prosa da Decision 9). **Destino**:
      `/create-tasks` — a tarefa que implementa o item 4 do Escopo do
      trabalho (`plan.md`) deve incluir a definicao explicita da interface
      (nome do subcomando, flags, exit codes, stdout) como parte do trabalho,
      idealmente com um contrato dedicado espelhando `state-rounds.md`.
- [x] CHK003 - Todo FR que MUST preservar algo "intacto"/"integro" (FR-007,
      SC-002) tem mecanismo de verificacao objetiva declarado (nao so a
      promessa textual)? [Completude, Spec §FR-007, §SC-002] {auto}
      Evidencia: `plan.md` T-04/T-05 ("round preservado byte a byte identico
      (`cmp`)" nos dois backends); `data-model.md` define `sha256`/`cmp` como
      mecanismo de verificacao do Round.
- [x] CHK004 - O edge case "descricao de incremento vazia ou longa demais"
      (spec.md Edge Cases) tem resposta declarada em algum artefato, mesmo
      que a resposta seja "reusa validacao ja existente"? [Completude,
      Spec §Edge Cases] {auto}
      Evidencia: `contracts/reopen-flow.md` linha 25 — a ordem de execucao
      lista "1..5 pre-flight existente (path-guard, **sanitize**, briefing,
      constitution, coexistencia agente-00c)" ANTES do ramo de reabertura
      (item 6); a sanitizacao de `descricao_curta` (<=500 chars, vazio
      rejeitado) e responsabilidade do pre-flight ja existente e reutilizada
      sem mudanca — nao e uma decisao nova desta feature.
- [x] CHK005 - O `## Delta Requirements` no fim de `spec.md` usa um
      capability-slug ja existente no corpus (`docs/specs/current/`) em vez
      de fragmentar um conceito equivalente? [Completude, Consistencia,
      Spec §Delta Requirements] {auto}
      Evidencia: `docs/specs/current/spec-corpus.md` existe (FR-006..FR-009,
      introduzidos por `living-specs`); `spec.md` declara
      `### Capability: spec-corpus` com `FR-013` em `#### ADDED`, mesmo id
      usado na secao `### Functional Requirements` (regra 4 do contrato
      `delta-section-format.md`) — reuso correto, nao um slug novo
      redundante.

## Clareza de Requisitos

- [x] CHK006 - "Trabalho pendente nao integrado" (FR-021) esta quantificado
      com criterio verificavel, nao um termo vago? [Clareza, Spec §FR-021]
      {auto}
      Evidencia: FR-021 + Clarifications Session 2026-08-11 definem
      literalmente os dois sinais: "branch associada ainda nao mesclada na
      branch default" + "status de proposta de merge aberta, quando
      disponivel" — ambos com fonte de verificacao nomeada em
      `research.md` Decision 9 (`git symbolic-ref`, `gh pr view`).
- [x] CHK007 - "Estado terminal" (usado em FR-003, FR-007, FR-020) tem
      definicao unica e nao-ambigua reusada em toda a spec? [Clareza,
      Consistencia] {auto}
      Evidencia: enum fechado `concluida`/`abortada` (data-model.md Entity
      Round `status`); `state-lock.sh check-execution-busy` (existente,
      citado em `contracts/reopen-flow.md` passo 6.a #2) ja distingue esses
      dois valores de `em_andamento`/`aguardando_humano` — nao ha definicao
      paralela ou conflitante em nenhum outro artefato.
- [x] CHK008 - A numeracao de rounds (`r01`, `r02`, ...) tem o
      comportamento em escala (>99 rounds da MESMA feature) declarado, em
      vez de deixado implicito? [Clareza, Spec §FR-009] {auto}
      Evidencia: `research.md` Decision 3 declara explicitamente o limite
      (`r99` → `r100` quebra ordenacao lexicografica) como "condicao
      documentada como limite conhecido, nao tratada em codigo", com
      justificativa empirica (nenhuma das 26 execucoes de referencia foi
      reaberta ainda). Nao e um requisito omitido — e um limite aceito e
      citado (tambem em `plan.md` §Riscos).
- [x] CHK009 - O termo "identico independentemente da forma de persistencia"
      (FR-010) esta escopado ao COMPORTAMENTO OBSERVAVEL da rotacao (nao ao
      formato de arquivo entre rounds distintos da mesma linhagem)? [Clareza,
      Spec §FR-010] {auto}
      Evidencia: reconciliado nesta onda — `research.md` Decision 14
      (reescrita) deixa explicito que FR-010 nao amarra o backend da
      execucao nova ao do round anterior; linhagem com backend misto e
      "comportamento intencional", nao violacao de FR-010. Antes da
      reconciliacao esta leitura era ambigua (a redacao original de
      Decision 14 tratava linhagem mista como quebra de FR-010) — corrigido
      por dec-024 nesta mesma onda.

## Consistencia de Requisitos

- [x] CHK010 - A tabela "Escopo do trabalho" do `plan.md` bate 1:1 com os
      artefatos apos a reconciliacao (nenhum item orfao apontando para uma
      decisao ja revogada)? [Consistencia] {auto}
      Evidencia: a linha "10 | Heranca de backend do round anterior
      (Decision 14)" foi removida do `plan.md` nesta onda (nao ha mais
      trabalho de heranca a fazer); `T-35` foi reescrito para validar
      ausencia de heranca, nao presenca; `Fora de escopo` ganhou entrada
      explicita para `--backend`.
- [x] CHK011 - O status do Principio II no Constitution Check de `plan.md`
      reflete a condicao (b) do carve-out 1.1.0 nao satisfeita, em vez de
      `PASS` puro? [Consistencia, Principio VI] {auto}
      Evidencia: linha da tabela alterada nesta onda para
      `CONDICIONAL — desvio pre-existente declarado`; paragrafo "Resultado
      do gate" e "Re-check" atualizados no mesmo sentido (nao ha mais
      inconsistencia entre a tabela dizer `PASS` e o texto abaixo dizer
      "NAO SATISFEITA").
- [x] CHK012 - `quickstart.md` cobre explicitamente os dois sentidos de
      linhagem com backend misto (round `json` + execucao nova `sqlite`, e
      o inverso), nao so os dois backends isolados? [Consistencia, Cobertura,
      Spec §FR-010] {auto}
      Evidencia: `Scenario 19` (novo, adicionado nesta onda) cobre 19a
      (json→sqlite, caso comum: 21/26 execucoes de referencia sao json e a
      config global atual resolve sqlite) e 19b (sqlite→json, inverso).
- [x] CHK013 - `FR-018` ("rounds preservados MUST NOT ser interpretados
      como execucoes ativas por nenhum leitor de estado") e consistente com
      o mecanismo real de deteccao de execucao ativa usado pelo hook de
      guarda (`_hook-active-exec.sh`)? [Consistencia, Spec §FR-018] {auto}
      Evidencia: `_hook-active-exec.sh` (`$HOME/.claude/skills/
      agente-00c-runtime/scripts/_hook-active-exec.sh`, funcao de deteccao)
      itera `<feature-root>/*/` (um nivel) e testa `<dir>/state.json` /
      `<dir>/state.db` **na raiz do state-dir** — nunca recursivo em
      `rounds/<label>/`. Como `Round` (data-model.md) vive exclusivamente
      sob `rounds/<label>/`, ele estruturalmente nao pode ser confundido
      com execucao ativa por esse leitor especifico; a mesma raiz-apenas se
      aplica a `state-ondas.sh wave-status`/`budget.sh` (mesma convencao de
      state-dir usada em toda a runtime).
- [ ] CHK014 - Ha algum leitor de estado FORA do runtime `agente-00c-runtime`
      (ex.: script de terceiros, integracao futura do painel) que varra
      `.claude/feature-00c-state/**/state.json` de forma recursiva e possa
      colidir com `rounds/`? [Consistencia, Spec §FR-018] {humano}
      Sem evidencia disponivel nesta onda de leitores externos ao runtime —
      depende de inventario que so o operador tem (ex.: scripts internos do
      cstk-panel ainda nao publicados). Deixado para o dono do produto
      confirmar antes do release, nao bloqueia `create-tasks`.

## Qualidade de Criterios de Aceite (Success Criteria)

- [x] CHK015 - Cada Success Criterion (SC-001..SC-007) e mensuravel sem
      depender de detalhe de implementacao? [Mensurabilidade, Spec
      §Success Criteria] {auto}
      Evidencia: todos os 7 usam quantificadores objetivos e observaveis do
      ponto de vista do operador — "zero edicao manual" (SC-001), "100%
      byte a byte identicos" (SC-002), "zero duplicatas" (SC-003), "26
      execucoes do repositorio de referencia" (SC-004, numero concreto e
      citavel), "sem abrir a spec existente" (SC-005), "uma unica tentativa"
      (SC-006), "cai para zero" (SC-007). Nenhum menciona nome de
      script/campo interno.
- [x] CHK016 - SC-004 ("funciona para as 26 execucoes ja concluidas do
      repositorio de referencia") e uma alegacao verificavel, nao uma
      estimativa? [Mensurabilidade, Principio VI, Spec §SC-004] {auto}
      Evidencia: a Contexto (spec.md linha 14-16) cita a contagem com
      metodo (`.claude/feature-00c-state/` — 26 diretorios, 21 json + 5
      sqlite) auditada nesta e na onda anterior (dec-021 corrigiu uma
      contagem anterior errada de specs arquivadas, mostrando que a
      disciplina de recontagem empirica ja foi exercida nesta feature).

## Cobertura de Cenarios e Edge Cases

- [x] CHK017 - Cada Edge Case listado em `spec.md` tem pelo menos um FR ou
      cenario de quickstart que o resolve (nenhum edge case orfao)?
      [Cobertura, Spec §Edge Cases] {auto}
      Evidencia: spec arquivada→FR-013/Scenario 9; execucao abortada→
      FR-020/Scenario 7; rotacao interrompida→FR-011/Scenario 12;
      concorrencia→FR-012/Scenario 13; branch/PR pendente→FR-021/Scenario
      17; spec editada a mao→coberto implicitamente por FR-013 passo 7.d
      ("`docs/specs/<short>/` ja existente e nao-vazio ⇒ nao sobrescreve");
      descricao vazia/longa→CHK004 acima; muitas reaberturas sucessivas→
      Scenario 4 + CHK008 (limite de numeracao).
- [x] CHK018 - Os dois backends (`json`/`sqlite`) tem paridade de cobertura
      em TODOS os cenarios criticos (nao so nos dois cenarios "backend"
      dedicados)? [Cobertura, Spec §FR-010] {auto}
      Evidencia: `plan.md` T-27 ("`.previous_round` legivel nos dois
      backends"), T-04/T-05 (preservacao byte-a-byte nos dois backends),
      `contracts/recall-rounds.md` "Mudanca 2: paridade de backend no
      `--reindex`" — a paridade e tratada como invariante transversal, nao
      isolada em Scenario 1/2.
- [x] CHK019 - O caminho de recusa (FR-002, FR-003) tem cenario cobrindo
      AMBOS os estados nao-terminais (`em_andamento` E
      `aguardando_humano`), nao so um deles? [Cobertura, Spec §FR-003]
      {auto}
      Evidencia: `quickstart.md` Scenario 6 passo 3 testa explicitamente os
      dois: "Repetir com `status = aguardando_humano`" apos testar
      `em_andamento`.

## Dependencias e Premissas

- [x] CHK020 - A feature declara explicitamente do que NAO depende
      (amendment de constitution, migracao de schema, consolidacao de
      adapter) para reduzir escopo de risco? [Dependencias, Spec
      §Contexto] {auto}
      Evidencia: `plan.md` §Fora de escopo lista amendment de constitution
      (nao necessario), migracao de `schema_version` (nao necessaria),
      regularizacao do `gh` (fora de escopo, dec-022) e `--backend`/heranca
      (fora de escopo, dec-022) — todas com justificativa e ligadas a
      Decisions do `research.md`.
- [x] CHK021 - As duas decisoes do operador em resposta ao `block-001`
      (dec-022) estao propagadas para TODOS os artefatos que as citavam
      antes da reconciliacao (nao apenas no artefato onde a duvida surgiu)?
      [Consistencia, Rastreabilidade] {auto}
      Evidencia: verificado nesta onda — `research.md` (Decision 14
      reescrita), `plan.md` (tabela Escopo, T-35, Constitution Check,
      Fora de escopo — 4 pontos), `contracts/reopen-flow.md` (T-35),
      `quickstart.md` (Scenario 19 + intro). `grep -rn "heranca de backend"`
      pos-edicao retorna 1 unica ocorrencia (o bullet que DESCREVE a
      decisao tomada, nao mais uma proposta ativa).

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou
  marcador `[Gap]`/`[Ambiguity]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto
  (CHK014 — inventario de leitores externos ao runtime).
- `[Gap]` presente: CHK002 (contrato de CLI da sonda de trabalho pendente) —
  destino: `/create-tasks`, tarefa do item 4 do Escopo do trabalho.
