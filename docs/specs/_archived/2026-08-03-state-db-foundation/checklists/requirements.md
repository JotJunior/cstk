# Requirements Checklist: Fundação state.db

**Purpose**: Validar a qualidade dos requisitos de `state-db-foundation`
(spec.md + plan.md + research.md + data-model.md + contracts/) antes de
`/create-tasks` — completude, clareza, consistência, mensurabilidade,
cobertura de cenários/edge cases, dependências e ambiguidades.
**Created**: 2026-07-30
**Feature**: [spec.md](../spec.md)

## Completude de Requisitos

- [x] CHK001 - Cada uma das 12 FRs numeradas (FR-001..FR-012) tem pelo menos
  um cenário de aceite ou edge case associado? [Completude, Spec §Requirements]
  {auto} — evidência: gate determinístico
  `requirement-coverage.sh docs/specs/state-db-foundation/spec.md` →
  `RESULT|...|requirements=12|covered=12|errors=0` (exit 0, sem `FINDING`).
- [x] CHK002 - As "Decisões de infraestrutura auditáveis" (backup,
  idempotência) têm requisito próprio, e não ficam implícitas nos FRs
  funcionais? [Completude, Spec §FR-013-INFRA-BACKUP, §FR-014-INFRA-IDEMP]
  {auto} — ambos existem como FRs nomeados e rotulados explicitamente como
  categoria de infraestrutura, com as demais categorias do checklist de
  infra (scheduling, rotação de chave, refresh de token, mutex
  multi-réplica) marcadas como N/A explícito, não omitidas.
- [x] CHK003 - Toda entidade citada nos FRs/User Stories (Wave, Decision,
  HumanBlock, TaskOutcome, Event, SkillInvocation, SpawnUsage,
  MigrationRun, ExportSnapshot) tem definição em Key Entities? [Completude,
  Spec §Key Entities] {auto} — as 9 entidades citadas na spec aparecem
  listadas com descrição em `spec.md` §Key Entities, e cada uma tem seção
  própria em `data-model.md` (`execution`, `wave`, `decision`,
  `human_block`, `task_outcome`, `event`, `skill_invocation`,
  `migration_run`, e `ExportSnapshot` deliberadamente não-tabela).
- [ ] CHK004 - Existe um requisito que declare a versão mínima de `sqlite3`
  suportada pela feature (da qual dependem `JSON1`/`json_valid` no schema e
  `.param set` na camada de escrita)? [Gap, Spec §FR-001; data-model.md
  L227-231; contracts/primitives.md §C8] {auto} — **gap real**: o
  `data-model.md` exige `JSON1` (presente por padrão desde SQLite 3.38,
  2022) para as constraints de `decision`, e `contracts/primitives.md`
  §C8 deixa em aberto (C8-a) se `.param set` existe na versão mínima — mas
  nenhum artefato desta feature declara qual é essa versão mínima. Sem
  isso, C8-a e a ressalva de JSON1 não têm piso para ser verificados
  contra. Ação: `/create-tasks` deve gerar uma tarefa de descoberta
  ("determinar versão mínima de `sqlite3` suportada pelo toolkit") antes
  da task de schema.
- [ ] CHK005 - O comando/interface operacional da migração (nome do
  subcomando, flags) está definido, ou só a semântica? [Gap,
  contracts/migration.md] {humano} — `contracts/export.md` §Interface do
  comando marca a assinatura como `[PROPOSTA]` (não fechada); decisão de
  nomenclatura final de CLI é escolha de produto/consistência com os
  scripts existentes, não deriva só da spec.

## Clareza de Requisitos

- [x] CHK006 - FR-002 e FR-003 ("atômica", "não deixa rastro parcial") são
  quantificados com garantia de mecanismo concreto, não só adjetivo vago?
  [Clareza, Spec §FR-003] {auto} — `data-model.md` e
  `contracts/primitives.md` §C4 aterram "atômica" em transação SQLite
  (`BEGIN IMMEDIATE`/commit único por mutação), não deixando o termo como
  aspiração de prosa.
- [x] CHK007 - "Corrupção/adulteração silenciosa" (FR-010) tem escopo
  explícito do que é e não é coberto? [Clareza, Spec §FR-010] {auto} —
  research.md Decision 4 (agora fechada via `dec-025`) declara
  explicitamente que a operação escolhida (`PRAGMA integrity_check`) cobre
  corrupção estrutural mas **não** adulteração bem-formada — o termo do
  FR-010 não fica subespecificado, o limite está documentado com
  honestidade em vez de implícito.
- [x] CHK008 - SC-004 ("em até 5 segundos") é mensurável por teste
  automatizado sem ambiguidade de ponto de partida/chegada? [Mensurabilidade,
  Spec §SC-004] {auto} — `contracts/export.md` §E5 (Frescor) define o
  gatilho e a janela de forma operacional o suficiente para um teste
  cronometrar do commit da mutação até o export refletir a mudança.

## Consistência de Requisitos

- [ ] CHK009 - O número de "campos obrigatórios de auditoria" de uma
  Decision é usado de forma consistente entre spec.md, data-model.md e
  research.md? [Conflict, Spec §FR-002 + §US1 AS-2 + §Key Entities;
  data-model.md L202 e L419; research.md L185] {auto} — **conflito real**:
  `spec.md` (FR-002, US1 AS-2, Key Entities) fala em "**cinco** campos
  obrigatórios de auditoria" mas enumera **seis** termos entre parênteses
  (`agente, etapa, contexto, opções consideradas, escolha, justificativa`).
  `data-model.md` L202 repete "5 campos obrigatórios" como título mas a
  tabela de `CHECK` logo abaixo (L204-217) implementa **seis** constraints
  de não-vacuidade (`agent`, `stage`, `choice`, `context`, `rationale`,
  `options_considered`) — e a linha L419 chama isso de "6 `CHECK` em
  `decision`" para cobrir "os 5 campos obrigatórios", reafirmando a mesma
  inconsistência numérica. `research.md` L185, em contraste, lista **cinco**
  campos (`context, options_considered, choice, rationale, agent` — sem
  `stage`/etapa), o que bate com o runtime real hoje (`state-decisions.sh`
  comentário L163: "Validacao Principio I (5 campos): contexto, opcoes,
  escolha, justificativa, agente" — `--etapa` é obrigatório na CLI mas fora
  da contagem dos "5 campos" de auditoria). A spec e o data-model, portanto,
  divergem entre si e do próprio runtime que estão especificando. Isto não
  é um bloqueio de implementação (o schema em `data-model.md` já implementa
  a superfície certa, 6 CHECKs cobrindo os 6 campos reais incluindo etapa),
  mas o texto prosa da spec deveria dizer "seis" (ou remover "etapa" da
  lista) para não confundir quem lê os FRs isoladamente. Ação: `/clarify`
  ou correção editorial direta na spec antes de `/create-tasks` gerar uma
  task ancorada no número errado.
- [x] CHK010 - A precedência de fonte de verdade entre `state.json` e
  `state.db` (Edge Case) é consistente com FR-012 (projeto não migrado
  continua em JSON)? [Consistência, Spec §Edge Cases + §FR-012] {auto} —
  ambos os trechos concordam: `state.db` com migração verificada sempre
  vence; ausência de `state.db` mantém o comportamento atual sem alteração,
  sem afirmação contraditória entre as duas seções.
- [x] CHK011 - O tratamento do lock de diretório é consistente entre
  FR-011, Edge Cases e a nota de infraestrutura (mutex multi-réplica)?
  [Consistência, Spec §FR-011 + §Edge Cases + nota infra] {auto} — as três
  menções concordam: WAL é o mecanismo primário, o lock de diretório é
  rebaixado a "camada extra opcional", nunca reintroduzido como requisito;
  nenhuma das três contradiz as demais.

## Qualidade de Critérios de Aceite

- [x] CHK012 - SC-001 (100% dos registros preservados na migração) define o
  método de verificação, não só a métrica-alvo? [Mensurabilidade, Spec
  §SC-001] {auto} — o próprio SC-001 nomeia o método ("comparação
  campo-a-campo entre o export pós-migração e o `state.json` original"), e
  `contracts/migration.md` §M3 detalha M3.1 (contagem por entidade) e M3.2
  (comparação campo-a-campo via round-trip) como implementação concreta
  desse método.
- [x] CHK013 - SC-002 ("taxa de atualização perdida é 0%") especifica o
  cenário de carga que o mede? [Mensurabilidade, Spec §SC-002] {auto} — o
  próprio SC-002 declara o cenário ("duas mutações de estado simultâneas no
  mesmo projeto... medido em teste de carga concorrente"), consistente com
  US1 AS-3.
- [x] CHK014 - SC-006 (recusa de migração sobre dados inconsistentes) tem
  exemplo concreto de inconsistência coberta, não só a categoria abstrata?
  [Mensurabilidade, Spec §SC-006] {auto} — SC-006 cita o exemplo "bloqueio
  humano órfão", e `contracts/migration.md` §M1 (Pré-condições) enumera a
  lista completa de checagens que reaproveita `state-validate.sh`.
- [ ] CHK015 - SC-005 ("100% de equivalência num conjunto de projetos de
  amostra") define o que conta como "conjunto de amostra" (tamanho,
  critério de seleção)? [Ambiguity, Spec §SC-005] {humano} — a métrica é
  clara na condição de equivalência, mas "conjunto de projetos de amostra"
  não tem tamanho nem critério mínimo definido na spec; decidir isso é
  escolha de escopo de teste (quantos projetos reais/sintéticos bastam para
  a garantia), não algo que os artefatos técnicos já resolvem.

## Cobertura de Cenários

- [x] CHK016 - Cada User Story (US1..US4) declara um teste independente que
  não depende de nenhuma capability de prioridade inferior? [Cobertura,
  Spec §US1-4 "Independent Test"] {auto} — todas as 4 possuem seção
  "Independent Test" explícita, e as dependências entre stories (US2 exige
  US1 pronta, US3 exige US1+US2, US4 exige US1) são declaradas na própria
  seção "Why this priority" de cada uma, sem contradição entre elas.
- [x] CHK017 - US1 (persistência íntegra) cobre tanto o caminho feliz quanto
  interrupção no meio da mutação (crash/timeout/sinal)? [Cobertura, Spec
  §US1] {auto} — a User Story declara explicitamente "mesmo que uma
  mutação seja interrompida no meio (crash, timeout, sinal)" no corpo, e
  `contracts/primitives.md` §C4 (Transacionalidade) aterra isso em
  `BEGIN`/`COMMIT`/`ROLLBACK` atômico do SQLite.
- [x] CHK018 - US4 (ingestão SQL→SQL) cobre o caso de projeto ainda não
  migrado, sem assumir que todo projeto já está em `state.db`? [Cobertura,
  Spec §US4 AS-2] {auto} — AS-2 cobre exatamente esse caso: "mecanismo
  atual (via JSON) continua funcionando sem alteração — a ingestão
  SQL-para-SQL é aditiva".

## Cobertura de Edge Cases

- [x] CHK019 - O edge case de coexistência `state.json` + `state.db`
  simultâneos tem resolução declarada (não fica em aberto)? [Cobertura,
  Spec §Edge Cases] {auto} — resolvido por referência à Clarifications
  Session 2026-07-30: presença de `state.db` verificado sempre vence.
- [x] CHK020 - O edge case de escrita concorrente entre agente-00c e
  feature-00c tem mecanismo nomeado, não só "resolver depois"? [Cobertura,
  Spec §Edge Cases] {auto} — resolvido via `block-001`/`dec-014`: WAL mode
  nativo do SQLite.
- [x] CHK021 - O edge case de falha da geração do export durante fechamento
  de onda declara explicitamente que a fonte de verdade não fica
  condicionada ao export? [Cobertura, Spec §Edge Cases] {auto} — texto
  explícito: "a falha de export degrada, não bloqueia a fonte de verdade",
  espelhado em `contracts/export.md` §E6.
- [x] CHK022 - O edge case de migração sobre `state.json` corrompido/com
  hash divergente declara o comportamento esperado (recusa, não conserto
  silencioso)? [Cobertura, Spec §Edge Cases] {auto} — texto explícito: "a
  migração deve recusar e reportar, nunca 'consertar' silenciosamente
  dados suspeitos", espelhado em `contracts/migration.md` §M1/§M4.
- [ ] CHK023 - O edge case sobre continuidade dos backups por onda
  (`state-history/`) pós-migração é uma pergunta em aberto no próprio texto
  da spec — foi de fato respondida em algum artefato subsequente? [Gap,
  Spec §Edge Cases (formulado como pergunta, não afirmação)] {auto} — a
  spec formula o item como pergunta ("...eles continuam sendo gerados... ou
  são substituídos...?"), mas a resposta **existe**: research.md Decision 6
  e FR-013-INFRA-BACKUP fecham isto explicitamente (continuam via export
  serializado, sem mecanismo novo). O `[Gap]` é editorial — a pergunta na
  spec deveria ser reescrita como afirmação já resolvida, apontando para
  Decision 6, para não parecer um edge case ainda sem resposta.
- [x] CHK024 - O edge case de ingestão do knowledge.db durante transação em
  andamento no `state.db` do projeto tem garantia de isolamento nomeada?
  [Cobertura, Spec §Edge Cases] {auto} — resolvido via WAL (leitura
  consistente da última transação concluída), consistente com FR-011 e
  `contracts/primitives.md` §C6.

## Requisitos Não-Funcionais

- [x] CHK025 - O requisito de concorrência (FR-011) especifica o mecanismo
  primário sem deixá-lo genérico ("deve suportar concorrência")? [Clareza,
  Spec §FR-011] {auto} — FR-011 nomeia o mecanismo primário (`PRAGMA
  journal_mode=WAL`) e o papel residual do lock de diretório, não fica em
  nível de intenção abstrata.
- [x] CHK026 - Os achados de segurança do gate `owasp-security` da onda-004
  (S1..S5) foram todos endereçados (remediados, escalados ou marcados
  informativos) antes do fechamento desta fase, sem finding `high`/`critical`
  pendente sem tratamento? [Requisito Não-Funcional / Segurança, plan.md
  §Achados do gate de segurança] {auto} — S1 (injeção SQL) e S3/S4 (permissão
  de arquivo, TOCTOU) remediados diretamente nos contratos; S2 (regressão de
  detecção de adulteração) escalado como bloqueio humano `block-002` e
  **respondido** via `dec-025` (opção 1, aceito e documentado) nesta mesma
  onda; S5 é informativo e amplifica S2 (mesma resolução). Nenhum finding
  `high`/`critical` permanece sem uma decisão registrada.
- [ ] CHK027 - Existe um requisito (ou critério de sucesso) que declare o
  overhead de performance aceitável do WAL/transação por mutação face ao
  mecanismo RMW+lock atual, ou a feature assume implicitamente que "mais
  rigoroso" nunca é "mais lento o suficiente para importar"? [Gap] {humano}
  — nenhum FR/SC desta spec fala de latência por mutação individual (só
  SC-004, que é sobre frescor do export, não da escrita primária); decidir
  se vale a pena um SC de performance de escrita é chamada de produto (a
  onda de execução já é limitada por chamadas de LLM, não por I/O local, o
  que pode tornar esse SC desnecessário — mas isso é julgamento, não fato
  extraível dos artefatos).

## Dependências e Premissas

- [x] CHK028 - A dependência externa do amendment de constitution
  (Princípio II, `sqlite3` obrigatório) está declarada como bloqueante e
  fora do escopo do pipeline `feature-00c`, sem ambiguidade sobre quem a
  conduz? [Dependência, Spec §Clarifications Session 2026-07-30 primeiro
  item] {auto} — texto explícito: "Dependência externa a esta feature: o
  amendment da constitution está fora do escopo do pipeline `feature-00c`
  ... precisa ser conduzido separadamente antes de `plan` assumir `sqlite3`
  como mandatório sem ressalva." `plan.md` §Constitution Check reforça:
  Princípio II "CONDICIONAL" enquanto o amendment não for ratificado.
- [ ] CHK029 - As 4 decisões de design deliberadamente abertas para
  `/create-tasks` (D7-a, E5-a, M1-a, C8-a) têm, cada uma, opções enumeradas
  E um requisito/contrato que fica bloqueado até a decisão ser tomada — ou
  alguma delas corre risco de ser esquecida por não ter task-gate
  explícito? [Dependência, plan.md §Decisões em aberto] {humano} — as 4
  têm opções enumeradas e artefato de origem citado (research.md/
  export.md/migration.md/primitives.md), mas apenas D4-a (agora fechada)
  tinha sido escalada como bloqueio humano formal nesta onda; D7-a, E5-a,
  M1-a e C8-a dependem de `/create-tasks` de fato gerar uma task-gate
  dedicada para cada uma antes da task de implementação correspondente —
  julgamento de processo do dono do produto/próxima fase, não algo que os
  artefatos garantem sozinhos.

## Ambiguidades e Conflitos

- [x] CHK030 - D4-a (cobertura de adulteração deliberada) permanece com
  opções em aberto nos artefatos publicados, ou já reflete a decisão
  fechada nesta onda? [Ambiguity — verificação de reconciliação]
  {auto} — **fechada nesta onda**: `research.md` Decision 4,
  `plan.md` (tabela de decisões em aberto, achados do gate S2, re-check
  pós-Phase 1), `quickstart.md` cenário 7.a e `contracts/primitives.md`
  §C7 foram todos atualizados para refletir `dec-025` (opção 1,
  `integrity_check` apenas, regresso aceito e documentado) como
  write-back desta retomada — nenhum desses artefatos ainda apresenta
  D4-a como pendente.
- [ ] CHK031 - D7-a (forma de acesso `ATTACH` vs. processo separado na
  ingestão SQL→SQL) tem trade-off de segurança/simplicidade suficiente
  descrito para o dono do produto decidir sem reabrir a pesquisa, ou falta
  informação (ex.: overhead de processo separado)? [Ambiguity, research.md
  Decision 7 §D7-a] {humano} — as duas opções e o motivo de cada uma
  (`ATTACH` mais direto; processo separado evita escrita acidental) estão
  descritos, mas a escolha entre "mais direto" e "mais defensivo" é
  trade-off de apetite de risco, não fato technical a ser extraído.

## Notes

- Items `{auto}` já vêm resolvidos pelo agente (`[x]` com citação, ou
  marcador `[Gap]`/`[Ambiguity]`/`[Conflict]`).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto.
- **CHK009** é o achado mais acionável deste checklist: a spec fala em
  "cinco campos obrigatórios de auditoria" mas enumera seis termos (inclui
  `etapa`), enquanto `data-model.md`/runtime real usam seis `CHECK`s e
  `research.md` lista cinco campos sem `etapa`. Recomenda-se correção
  editorial na spec (trocar "cinco" por "seis", ou remover `etapa` da
  enumeração) antes de `/create-tasks` gerar uma task ancorada no número.
- **CHK004** e **CHK029** revelam que nenhuma versão mínima de `sqlite3` é
  declarada em lugar nenhum da feature, apesar de duas decisões em aberto
  (C8-a, o JSON1 de `data-model.md`) dependerem dela — vale a pena resolver
  como parte da mesma rodada de fechamento de D7-a/E5-a/M1-a/C8-a em
  `/create-tasks`.
