# Contract: Migração state.json → state.db (FR-005 / FR-006 / FR-014-INFRA-IDEMP)

**Feature**: `state-db-foundation` | **Phase**: 1
**Status**: `[PROPOSTA — a validar na implementação]` para a interface do
comando. As pré-condições reaproveitam verificadores que já existem e são
fato verificável.

---

## Nomeação — colisão a evitar

`state-rw.sh` **já possui** um subcomando `migrate` (migração de schema
interno do `state.json`). A migração `state.json → state.db` **MUST NOT**
reusar esse nome — dois significados sob o mesmo verbo, no mesmo script, é
armadilha de operador.

Opções `[PROPOSTA]`:

- **A**: script novo dedicado, ex.: `state-db-migrate.sh` no mesmo diretório
  de runtime. Sem colisão; testável isoladamente (`tests/test_state-db-migrate.sh`
  pela convenção do harness).
- **B**: subcomando do `cstk` (ex.: `cstk state migrate --state-dir …`),
  alinhado a FR-005 ("comando explícito do operador") por ser a superfície
  que o operador já usa.

Recomendação: **B para a UX do operador, delegando a A a implementação** —
mantém a lógica testável pelo harness POSIX e dá ao operador um verbo
coerente com o resto do CLI. Decidir na task de FR-005.

---

## M1 — Pré-condições (MUST recusar antes de tocar em qualquer coisa)

A migração MUST recusar, com diagnóstico claro e exit não-zero, se:

| # | Condição | Como verificar | Requisito |
|---|---|---|---|
| 1 | Execução ativa | `.execution.status == "em_andamento"` | FR-005 (literal) |
| 2 | Estado inválido | `state-validate.sh --state-dir <dir>` sai != 0 | FR-005, SC-006 |
| 3 | Integridade divergente | `state-rw.sh sha256-verify --state-dir <dir>` sai != 0 | spec §Edge Cases |
| 4 | `state.json` ausente/ilegível | arquivo não existe ou `jq` não parseia | — |
| 5 | `state.db` já presente | ver M5 (idempotência) | FR-014-INFRA-IDEMP |

**Reaproveitamento deliberado**: a condição 2 já cobre o cenário de SC-006 e
US2 AS-3 (bloqueio humano órfão) — `state-validate.sh` valida que todo
`decision_id` de `.human_blocks[]` existe em `.decisions[].id`. Nenhum
verificador novo precisa ser escrito para atender SC-006.

**Sobre `aguardando_humano`**: FR-005 nomeia explicitamente apenas
`em_andamento`, e admite "concluída, abortada ou pausada". Uma execução em
`aguardando_humano` está pausada — logo é migrável pela letra do requisito.
**DECISÃO EM ABERTO (M1-a)**: confirmar se `aguardando_humano` deve ser
permitido ou recusado por prudência (o lock pode estar retido pelo command
pai). Fechar antes da task de FR-005.

---

## M2 — Sequência (MUST)

Quatro tempos — **recusar → construir fora → verificar → publicar**:

```
1. RECUSAR    aplica M1; qualquer falha ⇒ aborta sem escrever nada
2. CONSTRUIR  cria temporário via `mktemp` no <state-dir> (mesmo filesystem)
              aplica schema + PRAGMAs + insere na ordem de FK
              [MUST usar mktemp, não nome derivado de PID — primitives.md §C10]
3. VERIFICAR  aplica M3; falha ⇒ remove o temporário e aborta
4. PUBLICAR   mv atômico .state.db.tmp.<pid> -> state.db
```

**Ordem de inserção** (imposta pelas FKs): `execution` → `wave` →
`decision` → `human_block` / `skill_invocation` / `task_outcome` /
`event` → `migration_run`.

**IDs preservados**: `dec-NNN`, `block-NNN`, `onda-NNN` entram com o valor
original. Nenhuma renumeração (FR-005: "com seus identificadores e
timestamps originais").

**Por que rename atômico**: garante que um `state.db` visível seja sempre
completo e verificado — é o que sustenta a regra de precedência do FR-006 /
Decision 9 (a mera presença do arquivo pode decidir a fonte de verdade) e o
cenário US2 AS-4 (migração interrompida deixa o projeto operável).

---

## M3 — Verificação pós-migração (MUST, FR-006 / SC-001)

A migração **não** é considerada concluída sem passar em ambas:

### M3.1 — Contagem por entidade

Para cada entidade, `COUNT(*)` no destino MUST igualar o `length` do array
correspondente na origem:

| Origem (jq) | Destino (SQL) |
|---|---|
| `.decisions \| length` | `SELECT COUNT(*) FROM decision` |
| `.waves \| length` | `SELECT COUNT(*) FROM wave` |
| `.human_blocks \| length` | `SELECT COUNT(*) FROM human_block` |
| `.tasks \| length` | `SELECT COUNT(*) FROM task_outcome` |
| `.events \| length` | `SELECT COUNT(*) FROM event` |
| `[.waves[].skills_invoked[]] \| length` | `SELECT COUNT(*) FROM skill_invocation` |

Resultado gravado em `migration_run.counts_source` / `counts_target` como
evidência auditável.

### M3.2 — Comparação campo-a-campo via round-trip

Em vez de escrever um comparador novo, gerar o export
([export.md](./export.md)) a partir do `state.db` recém-construído e
compará-lo com o `state.json` de origem, ambos canonicalizados
(`jq -S .`). Divergência em nome de campo, ID, valor ou aninhamento ⇒
migração recusada.

É literalmente o que SC-001 pede: *"comparação campo-a-campo entre o export
pós-migração e o `state.json` original"*. Efeito colateral virtuoso: a
migração **testa o export** a cada execução — FR-006 e FR-007 se validam
mutuamente.

---

## M4 — Falha e recuperação (MUST, US2 AS-4)

| Ponto de falha | Estado resultante |
|---|---|
| Durante M1 | nada escrito; `state.json` intacto |
| Durante M2 (construção) | só o temporário existe; `state.json` intacto e ainda é a fonte |
| Durante M3 (verificação) | temporário removido; `state.json` intacto |
| Durante M4 (`mv`) | atômico: ou o nome antigo ou o novo, nunca meio-termo |

Em todos os casos o projeto **continua operável** pelo `state.json`
original — nunca fica sem fonte de verdade válida.

**O `state.json` de origem MUST NOT ser apagado pela migração.** Após a
publicação ele passa a ser tratado como export/legado (Decision 9); removê-lo
descartaria a rota de recuperação sem ganho algum.

---

## M5 — Idempotência (MUST, FR-014-INFRA-IDEMP)

**Chave de idempotência**: identidade da execução de origem —
`.execution.id` (o campo que `state-rw.sh init` grava e que a ingestão do
recall já usa como `execution_id`).

Reexecutar a migração sobre um projeto já migrado MUST NOT duplicar nem
corromper (spec US2 AS-2). Garantido por construção: a migração é sempre
**reconstrução completa** a partir da origem seguida de publicação atômica —
nunca append incremental sobre um banco existente.

Comportamento ao encontrar `state.db` pré-existente `[PROPOSTA]`:

- Se `execution.id` do banco existente == `execution.id` da origem ⇒
  reconstruir e republicar (idempotente), **ou** no-op reportando "já
  migrado". Ambos satisfazem AS-2.
- Se diferirem ⇒ **recusar**: é outro projeto/execução no mesmo diretório,
  situação que exige intervenção humana e não deve ser resolvida
  automaticamente.

Toda tentativa — inclusive as recusadas — é registrada em `migration_run`
com `result` ∈ `success` \| `refused` \| `failed` e `diagnostic`.

---

## M6 — O que a migração MUST NOT fazer

- **MUST NOT** rodar automaticamente numa invocação de orquestrador
  (FR-005, literal: "nunca automática ou transparente"). Nenhum caminho de
  `/agente-00c`, `/feature-00c` ou seus resumes pode dispará-la.
- **MUST NOT** "consertar" dados inconsistentes silenciosamente (spec
  §Edge Cases). Recusa e reporta.
- **MUST NOT** escrever no `knowledge.db` (FR-009).
- **MUST NOT** apagar `state.json`, `state.json.sha256` ou `state-history/`.

---

## Cenários de teste (harness POSIX, `tests/test_<nome>.sh`)

| # | Cenário | Requisito |
|---|---|---|
| 1 | `state.json` com N decisões/M ondas/K tasks/J eventos/L bloqueios ⇒ banco com contagens idênticas e IDs/timestamps preservados | US2 AS-1, SC-001 |
| 2 | Migração reexecutada sobre projeto já migrado ⇒ sem duplicação/corrupção | US2 AS-2, FR-014 |
| 3 | Bloqueio humano órfão ⇒ recusa com diagnóstico apontando o registro | US2 AS-3, SC-006 |
| 4 | `status == "em_andamento"` ⇒ recusa | FR-005 |
| 5 | Interrupção após construção e antes da publicação ⇒ `state.json` intacto e operável | US2 AS-4 |
| 6 | `sha256-verify` divergente ⇒ recusa | Edge Cases |
| 7 | Round-trip: export do banco migrado == origem canonicalizada | SC-001, US3 AS-1 |
