# Feature Specification: Paridade do runtime 00c com o backend SQLite

**Feature**: `state-db-runtime-parity`
**Created**: 2026-08-02
**Status**: Draft

> Contexto: as fases 1/2 do cutover `state.json` -> `state.db`
> (`state-db-foundation`, `state-backend-config`) portaram os 4 escritores
> nucleo (state-rw, state-ondas, state-decisions, bloqueios). O restante do
> runtime 00c ainda le o arquivo `state.json` diretamente e, sob um state-dir
> SQLite, degrada silenciosamente ou falha ("state.json ausente", exit 1) —
> evidencia de campo: dec-001 da execucao `document-templates` (meta-gob-ms),
> onde budget/cycles/circular/drift/retro/suggestions ficaram inertes durante
> uma execucao inteira. Esta feature fecha essa lacuna de paridade.

## Clarifications

### Session 2026-08-02

- Q: FR-007 — implementar `state-lock.sh acquire --force` ou emendar o
  contrato do `/feature-00c-abort`? → A: Implementar `--force`
  (dec-007, score 3). O contrato shipado ja invoca a flag em bloco
  executavel (`feature-00c-abort.md:91`) e prosa normativa; o substituto
  (release + acquire em 2 chamadas do caller) tem a MESMA janela de race
  (rmdir+mkdir nao-atomicos) porem sem primitiva unica auditavel. O
  `--force` confina a janela num unico script com diagnostico auditavel;
  SIGTERM + grace period permanece pre-condicao obrigatoria (nunca
  primeiro recurso — ver Edge Cases).
- Q: FR-005 — qual a assinatura da escrita multi-campo atomica? → A:
  Estender `state-rw.sh set` para aceitar N pares `--field F --value V`
  repetidos, aplicados atomicamente: backend JSON = um unico write do
  documento com todos os setpaths; backend SQLite = lote unico
  transacional. Um par = comportamento atual inalterado (retrocompat
  FR-004; interface unica, US2 AS3). Sem subcomando novo (dec-008).
- Q: FR-009 — o que constitui a varredura anti-regressao e seu criterio
  de pass/fail? → A: Duas camadas (dec-009): (a) DINAMICA — manifest
  explicito dos 15 leitores do FR-001 executados contra state-dir SQLite
  populado; falha em "state.json ausente", falha por backend, ou espelho
  `state.json` criado pos-varredura (SC-004); (b) ESTATICA — scan dos
  scripts do runtime por referencia a `state.json` em codigo real fora
  da allowlist de prosa (FR-010). A camada estatica e o que detecta
  helper NOVO fora do manifest (US5 AS2).
- Q: Os hooks (`posttooluse-tool-call-tick.sh`, `pretooluse-bash-guard.sh`)
  que detectam execucao ativa lendo `state.json` direto entram no porte?
  → A: NAO — feature separada (dec-010; criterio de expansao de escopo:
  sinalizar, nao forcar). A camada de hooks tem constraints proprios
  (regra dura de nao tocar o state por concorrencia PostToolUse,
  provisionamento distinto via `--scope project`). Exclusao registrada
  em Out of Scope abaixo.
- Q: FR-008 — o exit 7 contratual aplica so a `report.sh emit` ou tambem
  a `generate`? → A: Aos DOIS subcomandos (dec-011, score 3): ambos tem
  hoje o mesmo modo de falha "estado ausente" com exit 1 generico
  (`report.sh:452` e `:552`) e o contrato nao distingue subcomando — a
  classe de falha e uma so.

### Out of Scope (registrado em clarify)

- Porte dos hooks do runtime (`posttooluse-tool-call-tick.sh`,
  `pretooluse-bash-guard.sh`) para deteccao de execucao ativa
  backend-agnostica: fica para feature dedicada (evidencia da lacuna:
  `posttooluse-tool-call-tick.sh:70,84-85` le `state.json` via jq
  direto; sob state-dir SQLite o hook nunca dispara). Esta feature NAO
  altera hooks.

## User Scenarios & Testing

### User Story 1 - Guardas e helpers de leitura funcionam sob SQLite (Priority: P1)

Como operador de execucoes autonomas 00c num projeto cujo state-dir usa o
backend SQLite, quero que TODOS os helpers do runtime que leem estado
(orcamento, detectores de loop/circularidade/drift, retro, sugestoes,
relatorios de uso, roteamento de modelo, cache de artefatos, validacao de
schema, reconciliacao de decisoes, abertura de issue, pipeline e bootstrap)
funcionem exatamente como funcionam sob o backend JSON — para que uma
execucao em dogfooding SQLite tenha as mesmas protecoes (orcamento de onda,
gatilhos de aborto, auditoria) que uma execucao classica.

**Why this priority**: e o nucleo da paridade — sem isso, toda execucao
SQLite roda SEM orcamento e SEM detectores de aborto (guardas de seguranca
desligadas silenciosamente), o pior modo de falha possivel para um agente
autonomo.

**Independent Test**: inicializar um state-dir com backend SQLite, popular
estado (ondas, decisoes), invocar cada helper leitor e verificar que nenhum
reporta ausencia de `state.json` e que cada veredito e identico ao produzido
sobre um state-dir JSON com o mesmo estado logico.

**Acceptance Scenarios**:

1. **Given** um state-dir SQLite populado com execucao `em_andamento`,
   **When** o helper de orcamento (`budget.sh check`) e invocado, **Then**
   ele avalia os thresholds (tool calls, wallclock, tamanho de estado)
   normalmente, sem erro de "state.json ausente".
2. **Given** o mesmo estado logico gravado em um state-dir JSON e em um
   state-dir SQLite, **When** os detectores `cycles.sh check`,
   `circular.sh detect`, `drift.sh check` e `retro.sh check` rodam contra
   cada um, **Then** o veredito (exit code + saida) e equivalente nos dois
   backends.
3. **Given** um state-dir SQLite, **When** `suggestions.sh register`,
   `wave-usage-report.sh`, `model-routing.sh idempotent-check`,
   `model-routing-report.sh aggregate`, `state-cache.sh get-resumo`,
   `state-validate.sh`, `state-decisions-reconcile.sh check`, `issue.sh` e
   `pipeline.sh` sao invocados, **Then** cada um le o estado pela interface
   canonica de leitura e completa sua funcao sem abrir `state.json`
   diretamente.
4. **Given** um state-dir SQLite, **When** qualquer helper portado executa,
   **Then** NENHUM arquivo espelho `state.json` e criado no state-dir
   (anti-mirror: espelho stale poderia virar canonico se a config de
   backend regredir).
5. **Given** um state-dir JSON classico (retrocompatibilidade), **When** os
   mesmos helpers rodam, **Then** o comportamento permanece identico ao
   anterior a esta feature.

---

### User Story 2 - Fechamento de execucao com escrita multi-campo atomica (Priority: P2)

Como orquestrador (ou comando pai) encerrando uma execucao sob backend
SQLite, quero promover o estado terminal — status final junto com o
timestamp de encerramento (e motivo, quando aplicavel) — numa UNICA operacao
de escrita, porque o modelo de consistencia do backend exige os campos
interdependentes no mesmo write; escritas sequenciais campo-a-campo sao
rejeitadas pela regra de consistencia (status terminal exige `finished_at`
preenchido no mesmo estado).

**Why this priority**: sem escrita multi-campo, NENHUMA execucao SQLite
consegue ser promovida a `concluida`/`abortada` pelos caminhos documentados
— o workaround de campo (read | jq | write do documento inteiro) e fragil e
nao-auditavel como primitiva.

**Independent Test**: num state-dir SQLite com execucao `em_andamento`,
executar a nova escrita multi-campo promovendo `status=concluida` +
`finished_at` juntos e verificar sucesso; executar a MESMA promocao via dois
`set` sequenciais e verificar que a rejeicao (quando ocorrer) preserva o
estado integro.

**Acceptance Scenarios**:

1. **Given** execucao `em_andamento` em backend SQLite, **When** a escrita
   multi-campo grava `status` terminal + `finished_at` (+
   `termination_reason` quando aplicavel) numa unica operacao, **Then** a
   operacao conclui com sucesso e o estado resultante e consistente.
2. **Given** uma tentativa de escrita (single ou multi-campo) que violaria
   uma invariante de consistencia do estado, **When** o backend rejeita,
   **Then** o helper reporta diagnostico claro (qual invariante, quais
   campos) e o estado permanece intacto (sem escrita parcial).
3. **Given** um state-dir JSON, **When** a mesma escrita multi-campo e
   usada, **Then** ela funciona de forma equivalente (interface unica para
   os dois backends).

---

### User Story 3 - Abort executavel fim-a-fim (force-acquire do lock) (Priority: P3)

Como operador abortando uma execucao 00c travada, quero que o fluxo de
abort documentado funcione de ponta a ponta: o contrato do abort
(`/feature-00c-abort`, FR-025) prescreve SIGTERM + grace period e, como
fallback, um force-acquire do lock (`state-lock.sh acquire ... --force`) —
mas essa opcao `--force` NAO existe na implementacao atual do lock. O
comando referenciado pelo contrato precisa existir e se comportar como
documentado, ou o contrato precisa ser emendado com justificativa
registrada.

**Why this priority**: o abort e o freio de emergencia do operador; um
fallback documentado que nao existe descobre-se exatamente no pior momento
(execucao travada que nao responde SIGTERM).

**Independent Test**: simular lock detido por processo morto, executar o
fluxo de fallback do abort e verificar que o force-acquire toma o lock e o
abort conclui (estado terminal + relatorio parcial) sem intervencao manual.

**Acceptance Scenarios**:

1. **Given** um lock detido cujo processo dono ja morreu, **When** o
   fallback de force-acquire do abort e executado, **Then** o lock e
   adquirido e o fluxo de abort prossegue ate o estado terminal.
2. **Given** a decisao de implementar `--force` OU emendar o contrato,
   **When** a feature conclui, **Then** contrato e implementacao estao
   alinhados (zero referencia a opcao inexistente) e a decisao esta
   registrada com justificativa auditavel.

---

### User Story 4 - Exit codes contratuais do relatorio (Priority: P4)

Como consumidor programatico do gerador de relatorio (comandos de
abort/resume que distinguem falhas), quero que a falha por estado ausente
retorne o exit code CONTRATUAL: o contrato de invocacao do feature-00c
documenta exit 7 para falha na geracao do relatorio com estado preservado,
mas a implementacao atual retorna exit 1 generico — impossibilitando o
chamador de distinguir "estado ausente/relatorio falhou" de erro generico.

**Why this priority**: menor blast radius do escopo; ainda assim, exit
codes contratuais errados quebram automacao de quem os consome.

**Independent Test**: invocar a geracao de relatorio contra um state-dir
sem estado e verificar exit code 7 (alinhado ao contrato), com os demais
exit codes preservados.

**Acceptance Scenarios**:

1. **Given** um state-dir sem estado (nem JSON nem SQLite), **When**
   `report.sh emit` e invocado, **Then** retorna o exit code contratual 7
   com diagnostico em stderr.
2. **Given** os demais modos de falha (uso incorreto, secao faltando),
   **When** invocados, **Then** os exit codes existentes permanecem
   inalterados (retrocompatibilidade de contrato).

---

### User Story 5 - Varredura anti-regressao da classe inteira (Priority: P5)

Como mantenedor do toolkit, quero um teste de varredura que execute CADA
helper do runtime contra um state-dir SQLite populado e falhe se QUALQUER um
reportar "state.json ausente" (ou degradar silenciosamente) — para que a
classe de bug "helper novo le state.json direto" nunca seja reintroduzida
por uma feature futura.

**Why this priority**: e a rede de seguranca que transforma o porte pontual
(US1) em garantia permanente; sem ela, o proximo helper adicionado ao
runtime repete o padrao antigo sem ninguem notar.

**Independent Test**: rodar o cenario de varredura na suite; introduzir
artificialmente um helper que le `state.json` direto e verificar que a
varredura o detecta e falha.

**Acceptance Scenarios**:

1. **Given** um state-dir SQLite populado pela varredura, **When** cada
   helper leitor do runtime e executado contra ele, **Then** a varredura
   passa somente se nenhum helper reportar ausencia de `state.json` nem
   falhar por backend.
2. **Given** um helper hipotetico reintroduzindo leitura direta de
   `state.json`, **When** a varredura roda, **Then** ela falha apontando o
   helper especifico.

---

### Edge Cases

- State-dir com AMBOS `state.json` e `state.db` presentes: helpers leem via
  interface canonica, que resolve o backend pela regra ja estabelecida na
  fundacao (deterministico; nunca mistura leituras dos dois).
- `sqlite3` ausente no host ao operar um state-dir SQLite: helper falha
  RAPIDO com diagnostico citando a dependencia (carve-out do amendment
  1.3.0 da constitution) — nunca degrada silenciosamente nem cai para
  leitura de um `state.json` inexistente.
- Escrita multi-campo com combinacao que AINDA viola invariante (ex.:
  status terminal sem `finished_at` no mesmo lote): rejeicao com
  diagnostico, estado intacto.
- Force-acquire do lock quando o processo dono ainda esta VIVO: fallback e
  precedido de SIGTERM + grace period conforme contrato do abort; o
  force-acquire nao pode ser o primeiro recurso.
- Referencias residuais a `state.json` que sao apenas comentario/mensagem
  (secrets-filter, mensagens de log do bootstrap): permanecem — a auditoria
  distingue codigo real de prosa. Achado ja verificado: a checagem de
  execucao ativa do lock (`state-lock.sh`, subcomando `check`) le
  `state.json` em CODIGO real, nao comentario — entra no porte.
- Helper leitor rodando contra state-dir vazio/nao-inicializado: mesmo
  comportamento contratual de hoje (diagnostico de estado ausente), agnostico
  de backend.

## Requirements

### Functional Requirements

- **FR-001**: Todo helper do runtime 00c que le estado de execucao MUST
  obter os dados exclusivamente pela interface canonica de leitura
  backend-agnostica (a mesma usada pelos escritores nucleo ja portados),
  nunca abrindo o arquivo `state.json` diretamente. Escopo do porte:
  `budget.sh`, `cycles.sh`, `circular.sh`, `drift.sh`, `retro.sh`,
  `suggestions.sh`, `wave-usage-report.sh`, `model-routing.sh`,
  `model-routing-report.sh`, `state-cache.sh`, `state-validate.sh`,
  `state-decisions-reconcile.sh`, `issue.sh`, `pipeline.sh` (runtime) e
  `cli/lib/00c-bootstrap.sh` (CLI).
- **FR-002**: Os helpers de controle de execucao (`budget.sh`, `cycles.sh`,
  `circular.sh`, `drift.sh`, `retro.sh`, `suggestions.sh`) MUST produzir,
  sob backend SQLite, veredito equivalente (exit code + semantica de saida)
  ao que produzem sob backend JSON para o mesmo estado logico.
- **FR-003**: O sistema MUST NOT materializar espelho `state.json` num
  state-dir SQLite, em nenhum fluxo (porte, leitura, teste) — um espelho
  stale poderia virar canonico se a config de backend regredir.
- **FR-004**: O comportamento dos helpers sobre state-dir JSON MUST
  permanecer inalterado (retrocompatibilidade integral do backend classico).
- **FR-005**: A primitiva de escrita de estado MUST suportar atualizacao
  multi-campo atomica (varios campos num unico write), permitindo promover
  status terminal + `finished_at` (+ `termination_reason`) sem estado
  intermediario que viole as invariantes de consistencia do backend.
  Assinatura (dec-008): `state-rw.sh set` aceita N pares
  `--field F --value V` repetidos, aplicados atomicamente — backend JSON
  num unico write do documento; backend SQLite num lote unico
  transacional. Um unico par preserva o comportamento atual (FR-004).
  O MESMO `--field` repetido no lote segue semantica LAST-WINS na ordem
  de aplicacao (nao erro de uso): dedup textual nao capta equivalencia
  semantica de paths jq, e o parser atual ja faz last-wins para flags
  repetidas (CHK009; rationale completo no contract §1).
- **FR-006**: Quando uma escrita (single ou multi-campo) violar invariante
  de consistencia do estado, o sistema MUST rejeitar com diagnostico
  (invariante + campos envolvidos) e deixar o estado intacto — sem escrita
  parcial.
- **FR-007**: O fluxo de abort MUST ser executavel fim-a-fim:
  `state-lock.sh acquire --force` MUST ser implementado conforme ja
  referenciado pelo contrato do abort (FR-025 do feature-00c) — remove o
  lock detido e o readquire numa unica invocacao auditavel, emitindo
  diagnostico que registra a aquisicao forcada. O `--force` MUST
  permanecer restrito ao fluxo de abort apos SIGTERM + grace period
  (nunca primeiro recurso); `acquire` sem `--force` mantem o
  comportamento atual byte-identico. [Decisao: dec-007, Clarifications
  2026-08-02.]
- **FR-008**: A geracao de relatorio sem estado disponivel MUST retornar o
  exit code contratual 7 (contrato de invocacao do feature-00c, "falha na
  geracao do relatorio: exit 7 + estado preservado"), preservando os demais
  exit codes existentes. Aplica-se aos DOIS subcomandos de `report.sh`
  com esse modo de falha (`generate` e `emit`) — mesma classe de falha,
  mesmo exit code (dec-011).
- **FR-009**: A suite de testes MUST incluir uma varredura anti-regressao
  em duas camadas (dec-009): (a) DINAMICA — executa cada helper do
  manifest explicito de leitores (a lista do FR-001) contra um state-dir
  SQLite populado e falha se qualquer helper reportar ausencia de
  `state.json`, falhar por backend, ou criar espelho `state.json`
  pos-varredura; (b) ESTATICA — scan dos scripts do runtime que falha em
  referencia a `state.json` em codigo real fora da allowlist de prosa
  (FR-010), detectando helpers novos fora do manifest (US5 AS2).
- **FR-010**: As referencias residuais a `state.json` fora da lista de
  porte MUST ser auditadas e classificadas: prosa (comentarios, mensagens
  de log — ex.: `secrets-filter.sh`, mensagem de erro do bootstrap)
  permanece; codigo real (ex.: a checagem de execucao ativa do subcomando
  `check` do lock) MUST ser portado junto.
- **FR-011**: Todo script tocado pela feature MUST manter/ganhar teste na
  convencao do repositorio (`tests/` ou `tests/cstk/`), com a checagem de
  cobertura de scripts (`--check-coverage`) verde.
- **FR-012**: Sob state-dir SQLite com `sqlite3` ausente no host, cada
  helper MUST falhar rapido com diagnostico citando a dependencia (conforme
  carve-out da camada de estado transacional, amendment 1.3.0 da
  constitution) — nunca degradar silenciosamente.

> Decisoes de infraestrutura: N/A alem do mutex ja existente (lock local
> por diretorio, coberto por FR-007); sem scheduling novo, criptografia,
> tokens externos ou multi-replica.

### Key Entities

- **StateStore**: o estado de uma execucao 00c, hoje persistivel em dois
  backends (documento JSON ou banco SQLite); a interface canonica de
  leitura/escrita e o UNICO ponto de acesso legitimo.
- **RuntimeHelper**: script POSIX do runtime que consome o StateStore para
  uma funcao especifica (orcamento, detectores, relatorios, roteamento,
  cache, validacao, reconciliacao, issue, pipeline, bootstrap).
- **LockHandle**: mutex de state-dir; ganha (ou tem contratualmente
  removida) a aquisicao forcada usada pelo fluxo de abort.
- **SweepScenario**: cenario de teste que percorre todos os RuntimeHelpers
  contra um StateStore SQLite populado (rede anti-regressao da classe).

## Success Criteria

### Measurable Outcomes

- **SC-001**: 100% dos helpers leitores do runtime executam contra um
  state-dir SQLite populado sem reportar "state.json ausente" (varredura
  anti-regressao verde na suite).
- **SC-002**: Uma execucao 00c completa (inicializacao -> ondas -> estado
  terminal) sobre backend SQLite conclui sem nenhum workaround manual de
  estado (zero intervencoes do tipo "read | transform | write" feitas a
  mao).
- **SC-003**: Todo veredito de helper de controle e identico entre os dois
  backends para o mesmo estado logico (0 divergencias nos cenarios de
  equivalencia da suite).
- **SC-004**: Zero arquivos `state.json` espelho criados em state-dirs
  SQLite em toda a suite (verificacao automatica pos-varredura).
- **SC-005**: O fluxo de abort com fallback de force-acquire conclui sem
  intervencao manual no cenario de lock orfao (processo dono morto).
- **SC-006**: O exit code de falha por estado ausente na geracao de
  relatorio confere com o contrato (7) em 100% das invocacoes do cenario.
- **SC-007**: Checagem de cobertura de scripts da suite permanece verde
  (nenhum script tocado sem teste correspondente).

## Delta Requirements

**Skip**: comportamento alterado (leitura de estado dos helpers 00c e
primitivas de escrita/lock) nao esta documentado no corpus canonico
`docs/specs/current/` — a camada de estado pertence as specs ativas
`state-db-foundation`/`state-backend-config`, ainda nao arquivadas no
corpus; nao ha capability ativa a modificar. — agente-00c-feature-orchestrator, 2026-08-02
