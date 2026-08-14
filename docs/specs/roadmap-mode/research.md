# Research: roadmap-mode

**Feature**: `roadmap-mode`
**Fase**: Phase 0 — resolucao de unknowns
**Data**: 2026-08-14

Todas as decisoes abaixo foram apuradas contra o codigo-fonte real do
toolkit (paths + linhas citados) ou por probe empirico executado. Nenhum
valor, flag ou assinatura foi suposto (Constitution VI).

---

## Decision 1 — Persistencia do flag do modo: `extra_fields`, sem migracao de schema

**Decision**: o modo e persistido como campo top-level
`.roadmap_mode_enabled` (booleano) no state, gravado no `init` via nova
flag `--roadmap-mode true|false`. **Nenhuma coluna nova** e criada em
`state.db`.

**Rationale**: o backend SQLite tem conjunto de colunas fixo na tabela
`execution`, mas possui uma coluna catch-all `extra_fields TEXT -- JSON
object` justamente para campos top-level ainda nao modelados. Probe
empirico executado nesta fase (state-dir descartavel, `CSTK_STATE_BACKEND=sqlite`):

```
$ state-rw.sh set --state-dir <tmp> --field '.roadmap_mode_enabled' --value true
state-rw: set: .roadmap_mode_enabled atualizado (backend sqlite)
$ state-rw.sh get --state-dir <tmp> --field '.roadmap_mode_enabled // "ABSENT"'
true
$ sqlite3 <tmp>/state.db "SELECT extra_fields FROM execution;"
{"roadmap_mode_enabled":true}
```

O round-trip preserva o valor e o campo pousa em `extra_fields` sem
qualquer alteracao de DDL. Isso remove do escopo da feature:
`references/state-db-schema.sql`, `_state-rw-db.sh` (3 pontos: INSERT
`_sr_db_insert_execution_from_doc_file`, mapa `_sr_lu_col`,
materializacao JSON) e `state-db-migrate.sh` — que, por espelhar o
INSERT coluna-a-coluna, teria de ser alterado em conjunto.

**Alternatives considered**:

- *Coluna dedicada `roadmap_mode_enabled` (espelhando
  `atomic_commit_enabled`)*: rejeitada. Exigiria migracao de schema
  coordenada em 4 arquivos, com risco da classe de bug ja registrada no
  proprio repo (paridade INSERT vs migrate). Custo desproporcional para
  um booleano cujo unico consumidor e o proprio orquestrador.
- *Sidecar de arquivo no state-dir (precedente `commit-baseline.txt`)*:
  rejeitada. Nao participa do backup filtrado da onda nem do hash de
  integridade do state, e ficaria invisivel ao painel/knowledge.db.

**Ref**: dec-010 (score 3).

---

## Decision 2 — Etapa `roadmap`: lista escopada por modo, nunca na lista linear

**Decision**: `_PL_STAGES_LIST` permanece **intocada** (as mesmas 10
etapas, na mesma ordem). O modo roadmap ganha uma lista propria,
selecionada por flag: `pipeline.sh stages --mode roadmap` →
`briefing constitution roadmap`. Sem `--mode` (ou com `--mode default`),
o comportamento e byte-identico ao atual.

**Rationale**: inserir `roadmap` na lista linear entre `constitution` e
`specify` mudaria a pipeline **default** para
`constitution → roadmap → specify`, o que e regressao direta contra
SC-003 ("execucao sem opt-in produz pipeline identica a atual"). Alem
disso `tests/test_pipeline.sh:57-71` asserta a lista e a ordem exatas
das 10 etapas — a insercao quebraria o teste, e "consertar" o teste
seria mascarar a regressao, nao evita-la.

**Alternatives considered**:

- *Inserir `roadmap` em `_PL_STAGES_LIST`*: rejeitada pelo acima.
- *Nao criar etapa; gerar o roadmap dentro da onda de `constitution`*:
  rejeitada. Perderia o gate de `detect-completion` (nao haveria como o
  orquestrador verificar que o artefato foi de fato produzido antes de
  encerrar) e tornaria o estado `current_stage` mentiroso durante a
  geracao.

**Ref**: dec-011 (score 3).

---

## Decision 3 — Encerramento terminal: `concluido` + promocao explicita, nunca `--advance`

**Decision**: ao concluir a etapa `roadmap`, a onda fecha com
`state-ondas.sh end --motivo-termino concluido` seguido da promocao
explicita de **5 campos** no mesmo write:
`.execution.status="concluida"`,
`.execution.termination_reason="concluido"`,
`.execution.finished_at=<ISO8601>`, `.current_stage="concluida"` e
`.next_instruction=<texto de execucao encerrada>`.

Promover apenas os 3 primeiros deixaria o ponteiro de fase em `roadmap`
com instrucao stale — meio-avanco invisivel ao `reconcile-wave`. O
precedente aplica os 5 numa unica transacao (comentario literal no
codigo: "`write` aplica as 5 mudancas na mesma transacao (C4),
backend-agnostico").

**Rationale**: `--advance --terminal-phase X` e **fail-closed** — quando
a fase corrente ja E a terminal, o helper morre com erro de uso
(`state-ondas.sh:812-814`):

```
end: --advance em fase terminal '<X>' — fechamento terminal usa
--motivo-termino concluido + promocao de status, nunca --advance
```

Ou seja, `--terminal-phase` serve para *impedir* que o ponteiro avance
alem do fim, nao para executar o fim. O precedente real de "pipeline
termina em X" e o branch terminal de `reconcile-wave`
(`state-ondas.sh:1626-1645`), que faz exatamente `end --motivo-termino
concluido` + promocao de status. O modo roadmap segue esse precedente,
passando `roadmap` como fase terminal em vez de `review-features`.

**Alternatives considered**:

- *`end --advance --terminal-phase roadmap`*: rejeitada — falha por
  construcao (evidencia acima).
- *Encerrar via aborto*: rejeitada — contradiz FR-004, que exige estado
  terminal **de sucesso**; aborto sinalizaria falha ao operador e ao
  painel.

**Ref**: dec-012 (score 3).

---

## Decision 4 — Status das entradas do roadmap e DERIVADO, nunca persistido

**Decision**: o campo `status` de uma entrada de roadmap
(`nao-iniciada` | `em-andamento` | `concluida`) **nao e gravado** como
fonte da verdade em `docs/roadmap.md`. E derivado, no momento da
leitura, do cruzamento do `short-name` da entrada com o portfolio em
`docs/specs/<short-name>/`.

**Rationale**: resolve FR-007 (idempotencia) por construcao, em vez de
por disciplina. Se o status fosse persistido, a re-execucao do modo
teria de fazer merge de estado — exatamente a operacao que "sobrescreve
silenciosamente" quando alguem erra. Sendo derivado, nao ha status a
perder: uma re-geracao que reescreva a secao de entradas nao pode
destruir informacao que nunca esteve la. A regra de derivacao:

| Condicao observada no portfolio | Status derivado |
|---|---|
| `docs/specs/<short-name>/` nao existe | `nao-iniciada` |
| diretorio existe, sem `tasks.md`, ou `tasks.md` com pendentes | `em-andamento` |
| `tasks.md` existe e nao tem nenhuma linha pendente | `concluida` |

O que a re-execucao **precisa** preservar e a *identidade* (short-name)
e a *descricao* de entradas ja existentes — tratado na Decision 5.

**Alternatives considered**:

- *Persistir `status:` por entrada*: rejeitada. Cria duas fontes da
  verdade (roadmap vs portfolio) que divergem no primeiro `/feature-00c`
  executado sem reabrir o roadmap.
- *Status persistido apenas como cache com timestamp*: rejeitada —
  complexidade sem consumidor; o cruzamento e barato (um `test -d` e um
  `grep -c` por entrada).

---

## Decision 5 — Idempotencia da re-geracao: short-name como chave de identidade

**Decision**: o `short-name` (kebab-case) e a **chave natural** de uma
entrada. Re-executar o modo roadmap faz merge por essa chave:

- entrada existente (mesmo short-name) → **preservada**: descricao e
  justificativa originais mantidas salvo mudanca deliberada; nunca
  duplicada;
- entrada nova → **anexada**;
- entrada existente cujo short-name ja tem spec em `docs/specs/` →
  preservada e reportada como iniciada (nunca renomeada, nunca
  re-sugerida com nome alternativo);
- entrada antiga que a nova analise considera desnecessaria → **nao e
  apagada**; e marcada e reportada ao operador para decisao.

**Rationale**: FR-007 exige "sem sobrescrita silenciosa e sem
duplicacao". Chave natural estavel + merge aditivo entrega ambos. A
regra "nunca apagar automaticamente" existe porque o roadmap e um
artefato de intencao humana ratificada — remover uma feature planejada e
decisao do operador, nao do gerador.

**Alternatives considered**:

- *Chave por ordem numerica*: rejeitada — a ordem e mutavel por
  natureza (re-priorizacao), logo nao serve de identidade.
- *Sobrescrever o arquivo inteiro a cada geracao*: rejeitada —
  violaria FR-007 literalmente.

---

## Decision 6 — Formato do artefato: parseavel em POSIX puro, sem `jq`

**Decision**: `docs/roadmap.md` e Markdown com um bloco de metadados de
linha fixa por entrada, sob heading canonico
`### <ordem>. <short-name>`. O parsing de referencia usa apenas
`grep`/`sed`/`awk`.

**Rationale**: Constitution II (NON-NEGOTIABLE) bane `jq` em scripts que
acompanham skills. O consumidor do cruzamento (FR-006) vive em
`plugins/cstk/skills/review-features/scripts/`, cujo precedente direto
—`aggregate.sh`— e **jq-free** (grep por `jq` retorna 0 ocorrencias) e
ainda assim emite JSON-lines montado a mao. O formato do roadmap segue o
mesmo padrao de rigor: chaves em linha propria, prefixo literal fixo,
um valor por linha, sem continuacao — o que torna o parse um `sed -n`
determinístico e imune a variacao de formatacao de prosa.

O carve-out de dependencia opcional (amendment 1.1.0) **nao e invocado**:
nao ha necessidade de ferramenta externa alguma.

**Alternatives considered**:

- *YAML frontmatter por entrada*: rejeitado — parsing correto de YAML em
  POSIX puro e inviavel; convidaria a um parser fragil.
- *Tabela Markdown unica*: rejeitada para o corpo — descricao e
  justificativa sao texto de varias frases e ficariam ilegiveis em
  celula. A tabela e mantida como **indice renderizado** (resumo), com o
  corpo canonico em headings.
- *JSON separado (`docs/roadmap.json`)*: rejeitado — o roadmap e
  artefato de leitura humana, irmao de `briefing.md`/`constitution.md`;
  um par md+json criaria drift entre os dois.

---

## Decision 7 — Cruzamento do review-features exige script proprio

**Decision**: o cruzamento roadmap↔portfolio (FR-006) e implementado por
um script novo e dedicado em
`plugins/cstk/skills/review-features/scripts/`, **nao** por extensao de
`aggregate.sh`.

**Rationale**: `aggregate.sh` so enxerga subdiretorios que **contem
`tasks.md`** (documentado no proprio header: "Cada subdiretorio do
DIRETORIO deve conter tasks.md ... para entrar no relatorio"; gotcha
correspondente em `review-features/SKILL.md`, "Features sem `tasks.md`
sao silenciosamente ignoradas"). Uma feature do roadmap que ja foi
iniciada mas ainda esta em `specify`/`plan` — justamente o estado
`em-andamento` que FR-006 precisa reportar — **nao tem `tasks.md`** e
seria invisivel. Estender `aggregate.sh` para incluir dirs sem
`tasks.md` mudaria o contrato de saida de um script ja consumido e
testado (`tests/test_aggregate.sh`), com risco de regressao no relatorio
existente.

**Alternatives considered**:

- *Estender `aggregate.sh`*: rejeitada pelo acima (mudanca de contrato
  de script existente + regressao de teste).
- *Fazer o cruzamento na prosa da SKILL.md, sem script*: rejeitada —
  classificacao deterministica em prosa e exatamente o modo de falha que
  o pre-gate deterministico do `create-tasks` existe para evitar; alem
  disso a regra de ouro do repo pede script + teste.

---

## Decision 8 — Passthrough de `--mode` no avanco de onda

**Decision**: `state-ondas.sh end --advance` ganha passthrough opcional
`--mode <modo>`, repassado a `pipeline.sh next-stage --mode <modo>`.

**Rationale**: o avanco atomico do ponteiro resolve a proxima fase
chamando `pipeline.sh next-stage --current X` **sem** nocao de modo. Em
modo roadmap, fechar a onda de `constitution` resolveria a proxima fase
como `specify` (a lista default), reintroduzindo exatamente a pipeline
que o modo existe para evitar — e gravando esse ponteiro errado no mesmo
write atomico do fechamento. O passthrough e a correcao minima e
localizada; sem `--mode`, o comportamento permanece o atual.

**Alternatives considered**:

- *O orquestrador setar `current_stage`/`next_instruction` por `set`
  avulso em modo roadmap*: rejeitada — a prosa dos orquestradores
  proibe explicitamente avancar fase por `set` avulso (o meio-avanco
  invisivel ao `reconcile-wave` foi um bug real ja corrigido pela
  feature `wave-close-advance`).

---

## Unknowns restantes

Nenhum. Zero `NEEDS CLARIFICATION` pendentes para a Phase 1.
