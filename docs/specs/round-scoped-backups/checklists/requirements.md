# Requirements Checklist: round-scoped-backups

**Purpose**: Validar a qualidade dos requisitos (completude, clareza,
consistencia, mensurabilidade, cobertura, rastreabilidade) da correcao da
issue #150 (escopar `backups/` na rotacao de round) — nao testa a
implementacao ainda inexistente.
**Created**: 2026-08-21
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) |
[research.md](../research.md) |
[contracts/state-rounds-backups.md](../contracts/state-rounds-backups.md)

**Dominio unico (requirements)**: a feature e um script POSIX interno
(`state-rounds.sh`), sem UI, sem API HTTP e sem superficie propria de
autenticacao/autorizacao — os riscos de seguranca residuais (TOCTOU de
symlink, permissoes de leitura local) ja foram varridos pelo gate
`owasp-security` na onda-003 (fase `plan`; achados G8/G9 registrados em
`plan.md` §Riscos e mitigacoes com severidade `low`, defesa em
profundidade). Um segundo dominio (`security`/`performance`) nao
agregaria: nao ha superficie nova a auditar alem do que o gate ja cobriu.

## Completude de Requisitos

- [x] CHK001 - Os requisitos funcionais cobrem tanto o caminho de
  movimentacao (`rotate`) quanto o de recuperacao (`recover`) da
  rotacao interrompida? [Completude, Spec §FR-001, FR-004] {auto}
  — Confirmado: FR-001 rege `rotate` ("mover o diretorio inteiro... na
  MESMA operacao"), FR-004 rege `recover` ("mecanismo de recuperacao...
  MUST suportar mover um diretorio inteiro").
- [x] CHK002 - Riscos/requisitos nao-funcionais (atomicidade sob
  interrupcao, symlink, permissoes) estao documentados fora da User
  Story principal, no plano tecnico? [Completude, Plan §Riscos e
  mitigacoes] {auto} — Tabela de 8 riscos com mitigacao e cenario de
  teste associado a cada um.
- [x] CHK003 - Ha declaracao explicita de fora-de-escopo para o caso
  historico da issue #150 (rounds ja rotacionados sem snapshots)?
  [Completude, Spec §Clarifications; Plan §Fora de escopo] {auto} —
  Clarification Q1 registra "fora de escopo — perda irrecuperavel
  documentada, sem mecanismo de backfill".
- [x] CHK004 - As demais exclusoes de escopo (guarda nova no
  `--purge-backups`, compactacao/retencao de snapshots, G6 lock
  liveness) estao listadas com motivo, nao apenas omitidas? [Completude,
  Plan §Fora de escopo] {auto} — 5 linhas na tabela, cada uma com
  coluna "Motivo" preenchida.

## Clareza de Requisitos

- [x] CHK005 - Cada FR usa verbo MUST/MUST NEVER testavel, sem "deveria"
  ou linguagem de intencao? [Clareza, Spec §FR-001..FR-008] {auto} —
  Todas as 8 linhas comecam com "O sistema MUST" (FR-005 usa "MUST
  NEVER" para a restricao negativa).
- [x] CHK006 - O termo "elegivel" (backups so entra no conjunto movido
  se elegivel) esta quantificado com criterio objetivo, nao deixado
  vago? [Clareza, Spec §FR-006; Contract §2 tabela de Elegibilidade]
  {auto} — Tabela normativa com 4 estados de disco (ausente / vazio /
  nao-vazio / symlink) e a acao exata para cada um.
- [x] CHK007 - Placeholders (`TODO`, `TKTK`, `[NEEDS CLARIFICATION]`)
  foram resolvidos no spec.md e no plan.md? [Clareza] {auto} — Nenhuma
  ocorrencia em spec.md; plan.md §Technical Context afirma
  explicitamente "Nenhum `NEEDS CLARIFICATION`: nao ha eixo estrutural
  aberto".

## Consistencia de Requisitos

- [x] CHK008 - FR-001 (mover) e FR-006 (concluir sem erro quando
  ausente/vazio) sao consistentes entre si sobre QUANDO mover, sem
  contradizer um ao outro? [Consistencia, Spec §FR-001, FR-006] {auto}
  — FR-006 e uma excecao explicita e nao-conflitante de FR-001
  ("quando... ausente ou vazio... concluir a rotacao normalmente").
- [x] CHK009 - A terminologia ("round preservado", "snapshot de onda",
  "conjunto movido"/"nunca movidos") e usada de forma consistente entre
  spec.md, plan.md, research.md e o contrato delta? [Consistencia]
  {auto} — Os quatro artefatos reusam os mesmos termos; o contrato
  delta explicita a migracao de `backups/` da lista "Nunca movidos"
  para "Conjunto movido por backend" (Contract §2).
- [x] CHK010 - Os requisitos evitam contradizer os principios MUST da
  constitution do projeto (POSIX puro, zero dependencia nova, zero
  coleta remota, veracidade de dados)? [Constitution Alignment, Plan
  §Constitution Check] {auto} — Gate "Constitution Check" do plan.md
  marca PASS nos 4 principios NON-NEGOTIABLE aplicaveis (I, II, IV, VI).

## Qualidade de Criterios de Aceite / Mensurabilidade

- [x] CHK011 - SC-001..SC-004 sao objetivamente verificaveis (percentual
  de colisao, numero de tentativas de recuperacao, percentual de
  snapshots intactos)? [Mensurabilidade, Spec §Success Criteria] {auto}
  — Todos os 4 SC citam um numero ou condicao binaria verificavel (ex:
  "0% de colisao", "uma unica tentativa", "100% dos snapshots").
- [x] CHK012 - Os criterios de aceite de cada User Story podem ser
  transformados em teste automatizado sem interpretacao adicional?
  [Mensurabilidade, Spec §Acceptance Scenarios] {auto} — Confirmado
  pelo mapeamento 1:1 documentado em quickstart.md (T-17..T-28), com
  Given/When/Then reproduzido em passos shell executaveis.

## Cobertura de Cenarios

- [x] CHK013 - O happy path (US1: snapshots preservados apos reabertura)
  esta documentado com Given/When/Then e priorizacao de risco
  explicita? [Cobertura, Spec §User Story 1] {auto} — Presente, com
  "Why this priority" citando a perda real da issue #150 (ondas 1-11).
- [x] CHK014 - O caminho de erro/interrupcao (rotacao interrompida no
  meio do deslocamento de `backups/`) tem comportamento esperado
  definido, nao apenas mencionado? [Cobertura, Spec §Edge Cases linha
  1; Research Decision 5] {auto} — Edge case exige "todo movido ou
  nenhum movido, com uma unica tentativa"; Research Decision 5
  documenta o mecanismo (assercao de destino inexistente + exit 1)
  com evidencia empirica de aninhamento do `mv`.
- [x] CHK015 - Os 3 edge cases estruturais (ausencia/vazio de
  `backups/`, rounds pre-existentes sem snapshots, purge sem round
  preservado) estao cobertos por FR e por cenario de teste correspondente?
  [Edge Case, Spec §Edge Cases; Quickstart T-19, T-20, T-26] {auto} —
  Mapeamento 1:1 confirmado (T-19/T-20 para FR-006, T-26 para FR-005).
- [x] CHK016 - O gate deterministico de cobertura de requisitos
  (`requirement-coverage.sh`) confirma que todo FR tem cenario
  associado no spec.md? [Cobertura, gate `requirement-coverage.sh`]
  {auto} — Executado nesta onda:
  `RESULT|docs/specs/round-scoped-backups/spec.md|requirements=8|covered=8|errors=0`
  (exit 0, zero `FINDING`).

## Requisitos Nao-Funcionais

- [x] CHK017 - Os riscos de seguranca de defesa-em-profundidade
  identificados pelo gate `owasp-security` (TOCTOU de symlink G8,
  permissao de leitura local G9) foram promovidos a comportamento
  normativo verificavel (contrato + cenario de teste), mesmo sem virar
  FR numerado a mais na spec? [Consistencia, Plan §Riscos; Contract §2
  tabela de Elegibilidade linha "symlink"; Quickstart T-25, T-28]
  {auto} — G8 esta na tabela normativa do contrato delta (nao apenas
  em prosa de risco) e tem cenario de teste dedicado (T-25); G9 tem
  T-28. Nao e um gap — e um requisito de seguranca capturado no nivel
  de contrato tecnico em vez de FR de spec, escolha consistente com o
  restante do documento (FR-001..FR-008 descrevem comportamento
  funcional observavel pelo operador; G8/G9 sao guardas internas de
  implementacao).
- [x] CHK018 - A restricao de performance (custo dominante = um
  `rename(2)`, sem meta de latencia numerica) esta justificada em vez
  de simplesmente omitida? [Clareza, Plan §Technical Context
  "Performance Goals"] {auto} — Explicitamente marcado "N/A" com
  justificativa ("rotacao ocorre uma vez por reabertura de feature"),
  nao e uma omissao silenciosa.

## Dependencias e Premissas

- [x] CHK019 - Dependencias externas (sqlite3/jq) sao explicitas quanto
  a nao adicionarem dependencia NOVA (distinto de dependencia ja
  existente)? [Completude, Plan §Technical Context "Primary
  Dependencies"] {auto} — "esta feature nao adiciona nenhuma dep nova",
  com a fonte do carve-out (amendment 1.3.0 do Principio II) citada.
- [x] CHK020 - A premissa "mesmo filesystem ⇒ `rename(2)` atomico" que
  sustenta toda a garantia de atomicidade esta documentada, nao apenas
  presumida implicitamente? [Clareza, Research Decision 1; Plan
  §Constitution Check linha II] {auto} — Premissa citada explicitamente
  em Research Decision 1 ("Rationale") e reforcada no risco de G8
  (Research Decision 6: resolver o symlink quebraria essa premissa).
- [x] CHK021 - Ha fallback/comportamento definido quando a premissa de
  elegibilidade falha (symlink detectado)? [Completude, Spec via
  Research Decision 6; Contract §2] {auto} — `rotate` recusa com exit
  `1` antes de qualquer escrita, sem incluir a entrada no journal —
  comportamento explicito, nao um caminho nao-definido.

## Rastreabilidade

- [x] CHK022 - Cada User Story se liga a pelo menos um FR numerado?
  [Traceability] {auto} — US1→FR-001/002/003/007 (preservacao +
  contrato + local de escrita); US2→FR-005 (purge restrito); US3→FR-006
  (ausencia/vazio nao quebra).
- [x] CHK023 - O contrato delta referencia explicitamente os FRs que
  emenda, em vez de reescrever regras desacopladas da spec?
  [Traceability, Contract §2, §3] {auto} — A tabela de elegibilidade e
  precedida do texto "[PROPOSTA]" e mapeia diretamente para FR-001/
  FR-006; a secao de guardas cita FR-001/FR-004/FR-008 por numero.
- [x] CHK024 - Os riscos do plan.md se ligam a decisions do research.md
  ou a FRs especificos, em vez de flutuarem sem origem rastreavel?
  [Traceability, Plan §Riscos e mitigacoes] {auto} — Todas as 8 linhas
  da tabela de riscos citam pelo menos um cenario de teste (T-NN) ou
  guarda (G8/G9) como mitigacao verificavel.

## Ambiguidades e Conflitos

- [x] CHK025 - Marcacoes `[NEEDS CLARIFICATION]` foram resolvidas em
  todos os artefatos (spec, plan, research)? [Ambiguity] {auto} —
  Zero ocorrencias nos 5 arquivos de `docs/specs/round-scoped-backups/`
  (confirmado por grep nesta onda).
- [x] CHK026 - Requisitos com interpretacao multipla (ex: "conjunto
  movido" antes/depois da mudanca) foram refinados com tabela
  antes/depois explicita? [Ambiguity, Contract §2] {auto} — Contrato
  delta apresenta tabela "Hoje" vs "[PROPOSTA] Depois" lado a lado,
  eliminando ambiguidade de interpretacao.

## Decisao de risco/negocio pendente

- [x] CHK027 - A perda historica irrecuperavel dos snapshots de rounds
  ja rotacionados antes desta correcao (issue #150, ondas 1-11) foi
  formalmente aceita pelo dono do produto como permanente, sem
  expectativa futura de mecanismo de backfill? [Risco, Spec
  §Clarifications Q1] {humano} — A spec registra a decisao de
  clarify, mas a aceitacao de que a perda e definitiva (vs. "ainda
  nao decidimos investir em backfill") e julgamento de apetite de
  risco do dono do produto, nao verificavel so com os artefatos.
  **Resolvido 2026-08-21**: dono do produto aceitou formalmente via
  prompt interativo do command pai (/feature-00c) — perda historica
  permanente, sem backfill futuro. Evidencia: dec-036 no state da
  execucao round-scoped-backups + commit desta marcacao.

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao).
  Nenhum gap/ambiguidade/conflito foi encontrado nos artefatos desta
  feature — spec, plan, research, data-model, quickstart e contrato
  delta convergem entre si e citam evidencia rastreavel para toda
  afirmacao concreta (Constitution VI).
- Item `{humano}` (CHK027) fica `[ ]` aguardando decisao explicita do
  dono do produto — nao e um defeito da feature, e um julgamento de
  risco de negocio que os artefatos corretamente delegam a um humano.
- Gate deterministico `requirement-coverage.sh`: exit 0, 8/8 FRs com
  cenario associado — nenhum `[Gap]` adicional gerado por este gate
  (ver CHK016).
