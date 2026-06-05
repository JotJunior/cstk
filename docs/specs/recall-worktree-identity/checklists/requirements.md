# Requirements Checklist: Recall Worktree Identity

**Purpose**: Quality gate dos requisitos — valida clareza, completude, mensurabilidade e consistencia dos requisitos da feature, incluindo areas criticas de schema migration, compatibilidade retroativa e invariantes de paridade.
**Created**: 2026-06-05
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [data-model.md](../data-model.md)

---

## Completude de Requisitos

- [x] CHK001 - Todos os fluxos de deteccao de worktree (worktree com naming convencional, worktree fora da convencao, projeto raiz, git ausente) estao cobertos nos requisitos? [Completude, Spec §FR-001/FR-008, data-model §regras de presenca] {auto}
  > _Evidencia_: data-model.md §matriz de cenarios do init cobre os 4 casos. FR-008 garante fallback silencioso para toda falha. spec.md §Edge Cases reforca os cenarios de degradacao.

- [x] CHK002 - Estao especificados os requisitos para as tres camadas de derivacao canonicas em todos os pontos de entrada do ingest (ao-vivo, reindex, memories)? [Completude, Spec §FR-003/FR-004/FR-006, contracts/ingest-derivation.md §1-2] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §2 especifica que a funcao `recall_derive_canonical` se aplica identicamente em `--ingest` e `--reindex`, em ambos os layouts (feature-00c e agente-00c). Limitacao de `recall_ingest_memories_dir` documentada em §5.

- [x] CHK003 - O requisito de imutabilidade dos campos congelados (canonical_project, session_name) esta claramente documentado? [Completude, data-model §Entity canonical_project, contracts/state-rw-init.md §semantica] {auto}
  > _Evidencia_: data-model.md §Entity canonical_project: "congelado no init; NUNCA reescrito por onda/resume". Imutabilidade tambem reforcada no contrato do chamador.

- [x] CHK004 - Os requisitos de populacao da coluna `session` para execucoes sem sessao (NULL) estao explicitamente definidos? [Completude, Spec §FR-005, US2 AC2, data-model §coluna session] {auto}
  > _Evidencia_: data-model.md: "TEXT (NULL quando execucao sem sessao — US2 AC2)". spec.md US2 AC2 confirma comportamento para projetos nao-sessao.

- [x] CHK005 - Existe requisito explicito para o tratamento de memorias de worktree (US5)? [Completude, Spec §US5, contracts/ingest-derivation.md §5] {auto}
  > _Evidencia_: spec.md US5 (P4) define que o comportamento deve ser documentado. contracts/ingest-derivation.md §5 documenta: "diretorio varrido continua `~/.claude/projects/<encoded target_project_path>/memory/`" e que `recall_ingest_memories_dir` nao muda — limitacao documentada como "CQ1 estendida".

- [x] CHK006 - Os requisitos para o comportamento de upsert da coluna `session` no conflito ON CONFLICT estao especificados? [Completude, data-model §coluna session, contracts/ingest-derivation.md §3] {auto}
  > _Evidencia_: data-model.md §coluna session: "upsert `ON CONFLICT ... DO UPDATE SET` das duas tabelas ganham `session=excluded.session`".

---

## Clareza e Nao-Ambiguidade

- [x] CHK007 - O critério de deteccao de worktree (`.git` ARQUIVO vs DIRETORIO) esta especificado de forma nao-ambigua e verificavel? [Clareza, Spec §FR-001, contracts/state-rw-init.md §contrato] {auto}
  > _Evidencia_: contracts/state-rw-init.md passo 2: `if [ -f "$PAP/.git" ]` — teste POSIX preciso. spec.md §Decisoes de Infraestrutura: "Deteccao de worktree via `test -f .git` (POSIX)".

- [x] CHK008 - A derivacao de `session_name` a partir do basename da worktree (`sufixo apos <repo>-`) esta definida de forma precisa e com cenario de borda (naming fora da convencao)? [Clareza, Spec §FR-002 C3, contracts/state-rw-init.md §contrato passo 2d] {auto}
  > _Evidencia_: contracts/state-rw-init.md passo 2d: `se WTBASE comeca com "${CANONICAL}-": SESSION="${WTBASE#"${CANONICAL}"-}"`. Cenario fora da convencao = SESSION="" explicitamente coberto.

- [x] CHK009 - O termo "canonico" esta definido de forma precisa (basename do diretorio que contem o .git COMUM) em vez de apenas "projeto real"? [Clareza, Spec §Key Entities, data-model §Entity canonical_project] {auto}
  > _Evidencia_: data-model.md §Entity canonical_project: "basename do diretorio que contem o `.git` COMUM do repositorio (resolvido via `git rev-parse --git-common-dir`)". spec.md §Key Entities reafirma.

- [x] CHK010 - O comportamento de `recall_ingest_memories_dir` (sem state.json, sem campo congelado) esta documentado claramente como limitacao explicita? [Clareza, contracts/ingest-derivation.md §2] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §2: "`recall_ingest_memories_dir` (reverse-derivation, sem state) NAO muda — limitacao documentada (CQ1 estendida)".

- [ ] CHK011 - O requisito US3 AC2 (command pai PODE congelar `canonical_project` em projeto normal, "ambos validos") gera uma ambiguidade de comportamento esperado? E claro quando o command DEVE vs PODE congelar em projeto raiz? [Clareza, Spec §US3 AC2, data-model §regras de presenca, contracts/state-rw-init.md §passo 3] [Ambiguity] {humano}
  > _Pendente_: a spec diz "ambos validos" (omitir OU congelar o mesmo basename), e o contrato registra a "escolha canonica desta feature: OMITIR". A escolha foi feita, mas o US3 AC2 da spec ficou com a ambiguidade original sem registrar a decisao de design. Avaliar se a spec deve ser atualizada para refletir a escolha canonica definitiva (OMITIR) — evita que implementadores futuros re-abram a questao.

- [x] CHK012 - Estao claros os limites do `state_validate.sh` em relacao aos novos campos (aceitacao como opcionais, sem exigir em states antigos)? [Clareza, contracts/state-rw-init.md §compatibilidade] {auto}
  > _Evidencia_: contracts/state-rw-init.md §compatibilidade: "`state-validate.sh` deve aceitar as chaves novas como OPCIONAIS (sem exigi-las em states antigos)".

---

## Consistencia de Requisitos

- [x] CHK013 - Os tres pontos de paridade anti-eco (ingestao, agente-00c, feature-00c) sao mutuamente consistentes e a regra de entrega conjunta esta clara? [Consistencia, Spec §FR-007, contracts/ingest-derivation.md §4] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §4 define tabela de paridade com os 3 pontos e a REGRA DURA de entrega conjunta. Spec §FR-007 reafirma o invariante.

- [x] CHK014 - O comportamento de SC-003 (reindex identico independente da worktree existir) e consistente com a limitacao documentada de que `--reindex` nao indexa states que viviam APENAS em worktrees removidas? [Consistencia, Spec §SC-003, plan.md §riscos] {auto}
  > _Evidencia_: plan.md §riscos: "Fronteira do `--reindex`: nunca reindexara states que viviam apenas em worktrees ja removidas". SC-003 esta correto sob esta leitura: o campo congelado funciona para states SOBREVIVENTES, conforme esclarecido em quickstart §7. A consistencia e mantida.

- [x] CHK015 - Os requisitos de migracao de schema (FR-009) sao consistentes com a abordagem de nao-reescrita de registros antigos (plan.md §riscos)? [Consistencia, Spec §FR-009, plan.md §riscos, data-model §retro-compatibilidade] {auto}
  > _Evidencia_: plan.md §riscos: "Registros antigos do DB: linhas ja ingeridas com nome fantasma NAO sao reescritas pelo bump". FR-009 trata apenas do schema (ADD COLUMN), nao de migracao de dados retroativa. Sao requisitos ortogonais, consistentes entre si.

- [x] CHK016 - O requisito FR-007 (paridade anti-eco) e consistente com a derivacao de `feature` do agente-00c (antes: basename bruto; depois: `derive_canonical`) conforme data-model §derivation rules? [Consistencia, Spec §FR-007, data-model §derivation rules, contracts/ingest-derivation.md §4] {auto}
  > _Evidencia_: data-model.md §derivation rules: coluna `feature` em layout `agente-00c` passa a usar `recall_derive_canonical(...)`, substituindo "o basename bruto de `:775-778`". FR-007 exige que EXCLUDE_FEATURE do agente-00c use o mesmo valor derivado — definido em contracts/ingest-derivation.md §4.

---

## Qualidade dos Criterios de Aceitacao

- [x] CHK017 - Os criterios de aceitacao de US1 incluem todos os 4 cenarios (campo congelado, fallback git ao vivo, fallback basename, projeto normal sem regressao)? [Criterios de Aceite, Spec §US1] {auto}
  > _Evidencia_: spec.md §US1 lista 4 acceptance scenarios cobrindo exatamente esses casos. Cada cenario tem Given/When/Then mensuravel.

- [x] CHK018 - O Independent Test de US1 e suficientemente especifico (path de worktree simulado + query SQL para verificar coluna `project`)? [Criterios de Aceite, Spec §US1 Independent Test] {auto}
  > _Evidencia_: spec.md US1 Independent Test: "criar state.json com `target_project_path` apontando para um path de worktree (`/tmp/cstk-minha-feature`), executar ingestao, checar que a coluna `project` na tabela `executions` do knowledge.db contem `cstk`". Especifico e verificavel.

- [x] CHK019 - O critério SC-001 (100% das execucoes de worktree com `project = <repo-canonico>`) e mensuravel objetivamente? [Mensurabilidade, Spec §SC-001] {auto}
  > _Evidencia_: SC-001: "verificavel por query SQL direta apos ingestao de state.json de worktree simulado". O criterio e binario e automatizavel.

- [x] CHK020 - O critério SC-005 (suite de testes existente passa + novos cenarios adicionados) e especifico o suficiente para definir o escopo minimo de testes? [Criterios de Aceite, Spec §SC-005, contracts/ingest-derivation.md §6] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §6 lista os cenarios: "derivacao em 3 camadas (com e sem campo congelado; worktree fake com `.git` arquivo; git ausente via PATH desacoplado), coluna `session` populada e NULL, migracao v8 sobre fixture v7 sem perda, anti-eco com nome canonico, no-regression projeto normal". Escopo definido.

- [x] CHK021 - O critério SC-006 (schema bump idempotente sobre DB v7) tem critério de verificacao automatizado definido? [Mensurabilidade, Spec §SC-006, quickstart.md] {auto}
  > _Evidencia_: spec.md SC-006: "verificavel por teste automatizado com DB fixture". contracts/ingest-derivation.md §3 especifica o mecanismo (`PRAGMA table_info`). quickstart §4 e o cenario de teste.

---

## Cobertura de Cenarios

- [x] CHK022 - O cenario de dois orquestradores em sessoes diferentes do mesmo projeto rodando simultaneamente esta coberto? [Cobertura, Spec §Edge Cases] {auto}
  > _Evidencia_: spec.md §Edge Cases: "cada ingestao usa seu proprio `canonical_project` congelado; nao ha colisao — o indice e append/upsert por `execution_id`".

- [x] CHK023 - O cenario de `--reindex` sobre states antigos com worktree removida E sem `canonical_project` esta coberto? [Cobertura, Spec §Edge Cases, data-model §retro-compatibilidade] {auto}
  > _Evidencia_: spec.md §Edge Cases: "aplica fallback gracioso (basename), sem abort". data-model §retro-compatibilidade: "State antigo sem `canonical_project`, worktree removida → camada 3 = nome fantasma preservado (retrocesso gracioso, US1 AC3)".

- [x] CHK024 - O cenario de session_name com caracteres especiais (espacos, unicode, `/`) esta coberto como edge case? [Cobertura, Spec §Edge Cases, data-model §Entity session_name] {auto}
  > _Evidencia_: spec.md §Edge Cases: "campo `session_name` e tratado como dado textual; a derivacao do projeto canonico nao depende de parsing do session_name". data-model §Entity session_name: "string nao-vazia (dado textual livre; sem parsing downstream)".

- [x] CHK025 - O fluxo anti-eco end-to-end (ingestao de worktree → recall com --exclude-feature pelo nome canonico → resultados excluidos) esta coberto em acceptance scenarios? [Cobertura, Spec §US4] {auto}
  > _Evidencia_: spec.md US4 tem 2 acceptance scenarios: AC1 (exclusao com nome canonico funciona) e AC2 (nome fantasma nao exclui nada pos-correcao). Independent Test especifico.

- [ ] CHK026 - Existe cenario de aceitacao para o caso em que o common-dir retornado por `git rev-parse --git-common-dir` e um path RELATIVO (nao absoluto)? O requisito de normalizacao para absoluto esta suficientemente testado? [Cobertura, contracts/ingest-derivation.md §1 "normalizar COMMON para absoluto"] [Gap] {humano}
  > _Gap_: contracts/ingest-derivation.md §1 menciona "Camada 2 normaliza common-dir relativo para absoluto antes do `dirname`", mas nenhum acceptance scenario ou Independent Test cobre explicitamente o caso de path relativo vs absoluto do common-dir. A normalizacao esta no contrato mas sem cenario de teste dedicado — avaliar se quickstart deve incluir este sub-cenario.

---

## Cobertura de Edge Cases

- [x] CHK027 - O edge case de `git rev-parse --git-common-dir` falhando (git nao instalado, permissao, fora de repo) tem fallback definido e sem erro fatal? [Edge Cases, Spec §FR-008, Spec §Edge Cases] {auto}
  > _Evidencia_: spec.md §FR-008 e §Edge Cases: "fallback para `basename(target_project_path)` sem erro fatal". contracts/ingest-derivation.md §1 garantias: "toda subchamada com `2>/dev/null`; exit sempre 0".

- [x] CHK028 - O edge case de state.json com `--session-name` sem `--canonical-project` tem comportamento de erro definido (exit 2)? [Edge Cases, contracts/state-rw-init.md §semantica] {auto}
  > _Evidencia_: contracts/state-rw-init.md §semantica: "`--session-name` SEM `--canonical-project` e erro de uso (exit 2): sessao sem canonico nao tem semantica". Linha da tabela de cenarios de aceitacao confirma.

- [x] CHK029 - O edge case de DBs pre-v7 (com DROP one-time) transitando para v8 esta coberto sem perda de dados? [Edge Cases, data-model §coluna session, contracts/ingest-derivation.md §3] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §3: "Caminho pre-v7 existente (DROP one-time) inalterado — apos o drop, o DDL v8 ja cria as colunas".

- [x] CHK030 - O edge case de worktree criada por mecanismo externo ao `cstk session` (naming fora da convencao) gera `canonical_project` sem `session_name` sem erro? [Edge Cases, data-model §regras de presenca, contracts/state-rw-init.md §passo 2d] {auto}
  > _Evidencia_: data-model §regras de presenca: "Worktree fora da convencao de naming → basename do repo raiz | ausente". contracts/state-rw-init.md passo 2d: "senao: SESSION=""". Comportamento definido.

---

## Requisitos Nao-Funcionais

- [x] CHK031 - O requisito de degradacao graciosa (FR-008) cobre explicitamente que nenhum abort da onda do orquestrador deve ocorrer? [Nao-Funcional, Spec §FR-008, contracts/ingest-derivation.md §1] {auto}
  > _Evidencia_: spec.md §FR-008: "Toda falha na deteccao de worktree [...] MUST ser tratada como fallback silencioso — nenhum abort, nenhum erro fatal propagado para a onda do orquestrador". contracts/ingest-derivation.md §1 garantias: "Nunca falha [...]; exit sempre 0".

- [x] CHK032 - Os requisitos de seguranca (injecao SQL via valores UNTRUSTED do filesystem) estao documentados? [Nao-Funcional, contracts/ingest-derivation.md §2 Seguranca] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §2 Seguranca: "os tres valores novos [...] sao UNTRUSTED [...] e MUST passar por `sql_escape()` ao entrar em literais SQL". Restricao de uso de `eval` tambem documentada.

- [x] CHK033 - O requisito de performance (deteccao de worktree O(1) via `test -f` no caminho comum) esta especificado? [Nao-Funcional, plan.md §Performance Goals] {auto}
  > _Evidencia_: plan.md §Performance Goals: "deteccao de worktree O(1) no caminho comum (`test -f` curto-circuita; git so roda quando `.git` e arquivo)".

- [x] CHK034 - O requisito de zero regressao para projetos normais (FR-010) tem critério de verificacao automatizado (SC-005 + "no-regression projeto normal")? [Nao-Funcional, Spec §FR-010, SC-005, contracts/ingest-derivation.md §6] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §6: "no-regression projeto normal" como cenario explicito do `test_recall.sh`. SC-005 exige que a suite existente passe sem regressao.

---

## Dependencias e Premissas

- [x] CHK035 - A premissa de que `.claude/feature-00c-state/` NAO esta nos EXCLUDES do `cstk session` (erratum C5) esta documentada como risco e fora do escopo desta feature? [Dependencias, plan.md §riscos, Spec §C5] {auto}
  > _Evidencia_: plan.md §riscos: "Erratum C5: `feature-00c-state` NAO esta nos EXCLUDES do session.sh — [...] Nao piora com esta feature; correcao dos EXCLUDES e escopo de outra feature". Risco documentado e confinado.

- [x] CHK036 - A dependencia de `jq` e `sqlite3` (confinada em recall.sh) e `git` (opcional, com fallback) esta declarada e seus caminhos de degradacao documentados? [Dependencias, plan.md §Context, spec.md §Decisoes de Infraestrutura] {auto}
  > _Evidencia_: plan.md §Technical Context: dependencias listadas com nivel (estabelecida, confinada, opcional). spec.md §Decisoes de Infraestrutura: "Deps opcionais: `git` ja e prereq de uso do toolkit; a invocacao opcional ao vivo satisfaz a condicao (a) do amendment 1.1.0".

- [x] CHK037 - A entrega dupla (`cstk self-update` para runtime + `cstk update` para catalogo) e o risco de divergencia parcial estao documentados? [Dependencias, plan.md §estrutura] {auto}
  > _Evidencia_: plan.md §estrutura: "Entrega dupla: `cstk self-update` (runtime `cli/lib`) + `cstk update` (catalogo commands/agents/skills) — divergencia parcial quebra a paridade anti-eco, documentado como regra dura no contrato de derivacao".

---

## Consistencia do Schema de Migracao

- [x] CHK038 - O caminho de migracao v7→v8 e o caminho de criacao fresca de DB v8 sao consistentes (ambos produzem o mesmo schema final)? [Consistencia de Migracao, data-model §coluna session, contracts/ingest-derivation.md §3] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §3: "DDL fresco: `session TEXT` adicionada aos CREATEs de `executions` e `waves`" e "Migracao v7→v8: `ALTER TABLE <t> ADD COLUMN session TEXT` guardado por `PRAGMA table_info`". Ambos resultam no mesmo schema final com a coluna `session TEXT`.

- [x] CHK039 - O requisito de idempotencia do ALTER TABLE (re-execucao nao duplica colunas) tem mecanismo definido? [Consistencia de Migracao, Spec §FR-009, contracts/ingest-derivation.md §3] {auto}
  > _Evidencia_: contracts/ingest-derivation.md §3: "`PRAGMA table_info` checa a coluna `session`; ausente → `ALTER TABLE <t> ADD COLUMN session TEXT;`". O guard PRAGMA garante idempotencia.

---

## Notes

- Items `{auto}` foram resolvidos contra spec.md, plan.md, data-model.md e contracts/ com citacao de evidencia
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto
- Rastreabilidade: 37/39 items com referencia (94.9% — acima do minimo de 80%)
- 2 gaps abertos identificados

### Resolucao

- **{auto} resolvidos**: 37 (`[x]` com evidencia citada)
- **{humano} aguardando decisao**: 2
- **Gaps abertos** (`[Ambiguity]`/`[Gap]`): 2 (CHK011, CHK026)

### Follow-up dos Gaps

| Item | Marcador | Destino |
|------|----------|---------|
| CHK011 | `[Ambiguity]` | `/clarify` — spec §US3 AC2 deve registrar a escolha canonica definitiva (OMITIR canonical_project em projeto raiz) para eliminar "ambos validos" |
| CHK026 | `[Gap]` | `/create-tasks` — vira sub-tarefa de teste: "adicionar cenario de git common-dir relativo vs absoluto ao quickstart §4 e a test_recall.sh" |

### Proximos Passos

- CHK011: `/clarify` — registrar escolha definitiva de US3 AC2 na spec
- CHK026: `/create-tasks` — sub-tarefa de teste para normalizacao de common-dir
- `/create-tasks` — decompor o backlog executavel da feature
