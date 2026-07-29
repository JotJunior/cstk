# Infra Checklist: panel-docker

**Purpose**: Validar a qualidade dos requisitos de infraestrutura/operacao do modo
Docker do `cstk serve` — ciclo de vida e idempotencia do container, ergonomia de linha
de comando (composicao de flags existentes) e confiabilidade/paridade de dados — antes
de decompor em tarefas. Dominio customizado (sem `references/infra.md` pronto na skill
`checklist`; itens derivados diretamente dos artefatos da feature).
**Created**: 2026-07-11
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [research.md](../research.md)
· [data-model.md](../data-model.md) · [contracts/cli-docker-mode.md](../contracts/cli-docker-mode.md)

## Ciclo de Vida & Idempotencia (FR-011, FR-012-INFRA-IDEMP)

- [x] CHK001 - A chave de idempotencia (instalacao do modo Docker por host, sem TTL) e
  o momento da reconciliacao (a cada invocacao, nao por expiracao) estao definidos sem
  ambiguidade? [Clareza, Spec §FR-012-INFRA-IDEMP linha 294-297; research.md §Decision 6
  linha 238-240] {auto}
- [x] CHK002 - O comportamento de reconciliacao cobre AMBOS os estados possiveis do
  container remanescente (parado E rodando), nao so um deles? [Completude/Cobertura,
  Spec §FR-012-INFRA-IDEMP linha 291-293; data-model.md §Containerized Panel Instance
  "Reconcile pre-run" linha 78-79] {auto}
- [ ] CHK003 - O criterio para quando a reconciliacao automatica e considerada
  "impossivel" (US4 cenario 2, gatilho da mensagem de erro cstk) esta enumerado com
  condicoes concretas, ou o requisito descreve apenas o comportamento de saida
  ("mensagem acionavel") sem nunca definir QUANDO esse ramo dispara? [Mensurabilidade,
  Spec §User Story 4 Acceptance Scenario 2 linha 203-206; contracts/cli-docker-mode.md
  §Erros linha 57 (repete o outcome, nao o gatilho)] **[Gap]** {auto}
- [x] CHK004 - O encerramento gracioso (Ctrl+C/SIGTERM → `docker stop`) espelha
  explicitamente o grace period e o padrao SIGTERM→espera→SIGKILL ja em producao no
  modo nativo, em vez de introduzir um timeout novo sem justificativa? [Consistencia,
  Spec §FR-011 linha 287-290; research.md §Decision 6 linha 245-249, 254-255 (grace 5s
  == serve.sh L111-117)] {auto}
- [x] CHK005 - O uso de `--init` (tini como PID 1) esta justificado pela presenca de
  DOIS processos no container (painel + encaminhador), deixando claro por que um unico
  processo nao bastaria? [Clareza/Rationale, research.md §Decision 6 linha 251-254]
  {auto}
- [x] CHK006 - O comportamento de interrupcao DURANTE o build/start (antes de `ready`)
  esta definido — container parcial removido pelo nome deterministico, sem orfao — e
  nao apenas coberto para interrupcao apos o painel ja pronto? [Cobertura de Edge Case,
  Spec §Edge Cases linha 228-230; data-model.md §Containerized Panel Instance
  "Interrupcao durante build/start" linha 80-81] {auto}

## Ergonomia de CLI (Composicao de Flags Existentes)

- [x] CHK007 - O pre-flight de runtime (FR-003) especifica a ORDEM exata das checagens
  (binario presente → daemon acessivel) de forma que nenhuma operacao de rede ocorra
  antes de ambas, com criterio mensuravel de tempo (SC-006 <5s)? [Mensurabilidade, Spec
  §FR-003 linha 243-248, §SC-006 linha 339-341; research.md §Decision 5 linha 207-215]
  {auto}
- [x] CHK008 - As mensagens para "docker nao instalado" (FR-003) e "daemon
  inacessivel" (FR-004) sao requeridas como DISTINTAS uma da outra, com criterio
  verificavel de diferenciacao pelo usuario? [Clareza/Mensurabilidade, Spec §FR-004
  linha 249-252; contracts/cli-docker-mode.md §Erros linha 54-55] {auto}
- [ ] CHK009 - O texto de cada mensagem de erro (docker ausente, daemon inacessivel,
  porta em uso, reconciliacao impossivel) tem um criterio operacional para
  "acionavel" (ex.: MUST nomear a ferramenta/causa e sugerir o proximo passo), ou o
  termo fica repetido em FR-003/FR-004/FR-012-INFRA-IDEMP e no contrato sem nunca ser
  quantificado — todas as linhas da tabela de mensagens marcadas `[a fixar]`?
  [Clareza/Mensurabilidade, contracts/cli-docker-mode.md §Erros linha 50-58] **[Gap]**
  {auto}
- [x] CHK010 - A composicao `--docker --update` define semantica de falha
  (indisponibilidade de rede mantem a imagem existente e AINDA sobe o painel,
  best-effort), evitando que uma falha de rede durante `--update` bloqueie a subida?
  [Completude, Spec §User Story 3 Acceptance Scenario 2 linha 160-164;
  contracts/cli-docker-mode.md linha 21] {auto}
- [x] CHK011 - A composicao `--docker --reinstall` esta definida como incondicional
  (remove e reconstroi do zero sempre), com paridade explicita ao comportamento do modo
  nativo? [Consistencia, Spec §User Story 3 Acceptance Scenario 3 linha 165-168;
  contracts/cli-docker-mode.md linha 22] {auto}
- [ ] CHK012 - O Edge Case "usuario combina `--docker` com `--update` e `--reinstall`
  ao mesmo tempo" tem uma regra de precedencia definida (qual flag vence), ou a spec
  apenas levanta a pergunta sem resolve-la em nenhum artefato posterior (research/plan/
  contracts)? [Ambiguidade, Spec §Edge Cases linha 226-227 — nao referenciado em
  nenhuma Decision do research.md nem na tabela de flags do contrato] **[Ambiguity]**
  {auto}
- [x] CHK013 - FR-014 exige que o `--help` documente tanto a flag `--docker` quanto a
  semantica docker-specific de `--update`/`--reinstall` (nao so a existencia da flag)?
  [Completude, Spec §FR-014 linha 303-304; research.md §Decision 5 linha 230-231] {auto}
- [x] CHK014 - Os contratos marcados `[PROPOSTA — a validar na implementacao]`
  (`--docker`, `docker run`) estao claramente distinguidos do contrato REAL ja
  implementado (`--port`/`--host`/`--update`/`--reinstall`/`--help`), evitando que um
  leitor confunda o que ja existe com o que ainda sera construido? [Clareza/
  Consistencia (Constituicao VI), contracts/cli-docker-mode.md linha 5-8, 18] {auto}

## Confiabilidade & Paridade de Dados

- [x] CHK015 - O requisito de paridade de dados (US2/SC-002) define "identicos" com
  criterio objetivamente comparavel (contadores, listas, detalhes de execucao), em vez
  de um termo vago tipo "equivalente"? [Mensurabilidade, Spec §SC-002 linha 326-329;
  quickstart.md §Scenario 4 passo 3-5] {auto}
- [x] CHK016 - O estado "sem dados" (indice ainda nao existe) tem cenario de teste
  dedicado para o modo Docker, e nao e apenas assumido por analogia ao nativo?
  [Cobertura de Cenarios, Spec §User Story 2 Acceptance Scenario 2 linha 124-128;
  quickstart.md §Scenario 5] {auto}
- [x] CHK017 - Existe cenario de teste que verifica a atualizacao AO VIVO do indice de
  conhecimento (nova onda de orquestrador grava enquanto o painel Docker ja esta
  rodando, sem restart) tornando-se visivel no painel containerizado — ou o
  quickstart cobre somente uma comparacao estatica (snapshot) entre os dois modos,
  deixando a Acceptance Scenario 3 de US2 sem cenario de validacao correspondente?
  [Cobertura de Cenarios, Spec §User Story 2 Acceptance Scenario 3 linha 129-132;
  quickstart.md — nenhum dos 10 Scenarios exercita escrita concorrente durante
  execucao] **[Gap resolvido — tasks.md 5.2, dec-061: quickstart.md Scenario 11
  adicionado + validado 2x (producao real: INSERT/DELETE do host 54<->55 refletido
  na proxima requisicao sem restart; automatizado em
  tests/docker/run-panel-docker-smoke.sh::scenario_concurrent_write_visible_without_restart)]** {auto}
- [x] CHK018 - A garantia de que o painel NUNCA falha a inicializacao por causa do
  indice de conhecimento ausente esta redigida como comportamento MUST, e nao como
  expectativa informal? [Clareza/Mensurabilidade, Spec §User Story 2 Acceptance
  Scenario 2 linha 124-128 "nunca uma falha de inicializacao"] {auto}
- [ ] CHK019 - A prioridade P3 atribuida a User Story 4 (reexecucao segura/
  idempotencia) reflete corretamente o apetite de risco do produto para o primeiro
  incremento, dado que uma falha de reconciliacao deixa o usuario com um erro cru de
  runtime ate um fix futuro? [Risco/Priorizacao de negocio, Spec §User Story 4 "Why
  this priority" linha 184-188] {humano}
- [ ] CHK020 - A ausencia de um Success Criterion dedicado ao tempo de primeira
  execucao do modo Docker (download + `npm ci` + `npm run build` dentro do container)
  e aceitavel para este incremento, ou o dono do produto espera um SC de performance de
  primeira-execucao antes do release? [Risco/Priorizacao, Spec §Success Criteria
  (SC-001 a SC-006, nenhum cobre tempo de build); plan.md §Performance Goals linha
  36-37 (so cobre SC-006, runtime ausente)] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`/
  `[Ambiguity]`). Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- Nenhum valor concreto foi inventado: onde a fonte marca `[a fixar]`/`[detalhe de
  execute-task]` (ex.: nome exato do container, comando exato do socat, texto exato de
  mensagem), o item cobra que a decisao seja tomada E validada, nunca presume o valor.

### Follow-up obrigatorio (gap → acao)

| Item | Marcador | Destino |
|------|----------|---------|
| CHK003 | `[Gap]` | `/create-tasks` — tarefa: enumerar as condicoes concretas sob as quais `docker rm -f`/reconciliacao e considerada "impossivel" (ex.: permissao negada, daemon cai no meio da operacao) e mapear cada uma para a mensagem acionavel correspondente. |
| CHK009 | `[Gap]` | `/create-tasks` — tarefa: operacionalizar "mensagem acionavel" com um criterio testavel (ex.: MUST citar a causa raiz + MUST sugerir o proximo comando/link) e fixar o texto exato de cada uma das 5 mensagens da tabela de Erros do contrato. |
| CHK012 | `[Ambiguity]` | Nao reabrir `/clarify` (pipeline autonoma ja avancou de etapa; combinacao de flags e um edge case de baixo raio de acao, nao um risco de seguranca). Rotear para `/create-tasks`: tarefa explicita fixando a regra de precedencia (proposta: `--reinstall` vence sobre `--update` quando ambos presentes, espelhando "reinstall e sempre incondicional" ja definido para o caso isolado) e adicionar cenario de teste cobrindo a combinacao. Decisao de roteamento registrada como Decisao auditavel pelo orquestrador. |
| CHK017 | `[Gap]` | `/create-tasks` — tarefa: adicionar um Scenario 11 ao quickstart.md exercitando escrita concorrente no knowledge.db (nova onda grava) enquanto o painel Docker ja esta `running`, validando visibilidade sem restart (US2 Acceptance Scenario 3). |
| CHK019 | `{humano}` | Decisao do dono do produto antes de `/execute-task`: confirmar que P3 e a prioridade correta para a idempotencia, dado o modo de falha (erro cru de runtime) na ausencia dela. |
| CHK020 | `{humano}` | Decisao do dono do produto: definir (ou explicitamente dispensar) um SC de performance para o tempo de primeira execucao do modo Docker antes do release. |
