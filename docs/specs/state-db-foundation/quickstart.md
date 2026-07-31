# Quickstart / Cenários de Teste: state.db

**Feature**: `state-db-foundation` | **Phase**: 1
**Spec**: [spec.md](./spec.md)

Cenários executáveis que fecham os Success Criteria. Convenção do harness
POSIX do repo (`tests/README.md`): script em `tests/test_<nome>.sh` para
`global/skills/*/scripts/<nome>.sh`, e `tests/cstk/test_<nome>.sh` para
`cli/lib/<nome>.sh`. `./tests/run.sh --check-coverage` falha (exit 1) se um
script novo não tiver teste correspondente.

---

## Ambiente

```sh
sqlite3 --version   # >= 3.38 recomendado (JSON1 para os CHECK do data-model)
jq --version        # já é dep de fato do runtime (23 scripts gateiam nele)
./tests/run.sh --list | head    # confere o harness
```

---

## Cenário 1 — Persistência íntegra e atômica (US1, P1)

**Objetivo**: exercitar cada primitiva de escrita num projeto novo e provar
que as invariantes são impostas pela camada de armazenamento.

1. Criar state dir temporário e inicializar execução (`state-rw.sh init`).
2. Abrir onda → `state-ondas.sh start`.
3. Registrar decisão → `state-decisions.sh register` (7 flags obrigatórias).
4. Registrar bloqueio referenciando a decisão → `bloqueios.sh register`.
5. Registrar task → `state-ondas.sh record-task --outcome pass`.
6. Registrar skill → `state-ondas.sh record-skill --skill X --kind gate`.
7. `spawn-tracker.sh enter` / `leave`.
8. Fechar onda → `state-ondas.sh end --motivo-termino etapa_concluida_avancando`.

**Expected**: cada comando sai 0; `state-validate.sh` sai 0 ao final;
`wave-status` imprime `closed`; `current-id` imprime `onda-001`.

### 1.a — Onda duplicada é rejeitada (US1 AS-1)

1. `state-ondas.sh start` (onda aberta).
2. `state-ondas.sh start` de novo, **sem** fechar a primeira.

**Expected**: a segunda chamada **falha** (exit != 0, stderr explicando
onda já aberta) — `ux_wave_single_open`. Contagem de ondas permanece 1.
**Nunca** duas ondas abertas.

> Regressão que este cenário trava: hoje `start` faz append cego e cria uma
> segunda onda; a proteção existe só como prosa no orquestrador (passo
> 3.bis). Ver [contracts/primitives.md](./contracts/primitives.md) §C3.

### 1.b — Onda fechada uma única vez (FR-002)

1. Fechar a onda (`end --motivo-termino concluido`).
2. Tentar fechar a mesma onda de novo.

**Expected**: segunda chamada falha (`trg_wave_close_once`);
`termination_reason` e `finished_at` permanecem os da primeira.

### 1.c — Decisão sem campo obrigatório é rejeitada (US1 AS-2)

1. `state-decisions.sh register` omitindo `--justificativa`.
2. Escrita direta no banco (`INSERT INTO decision …`) com `rationale` vazio.

**Expected**: (1) exit 1 — paridade com hoje. (2) **também falha**, por
`CHECK (length(rationale) >= 20)`. É o ponto do FR-002: a garantia não
depende de quem chama.

### 1.d — Score 3 sem evidência é rejeitado

1. `INSERT` direto com `justification_score = 3` e `evidence = NULL`.

**Expected**: falha por CHECK. Hoje essa trava existe **apenas** dentro de
`state-decisions.sh register` e é contornável por qualquer outro caminho.

### 1.e — Bloqueio órfão é rejeitado (US1 AS-4)

1. `bloqueios.sh register --decisao-id dec-999` (inexistente).
2. `INSERT INTO human_block` com `decision_id` inexistente, com
   `PRAGMA foreign_keys=ON`.

**Expected**: ambos falham. Sem `foreign_keys=ON` o (2) passaria — por isso
o PRAGMA é MUST por conexão ([primitives.md](./contracts/primitives.md) §C5).

### 1.f — Teto de profundidade (FR-002)

1. `spawn-tracker.sh enter` até depth 3; mais um `enter`.

**Expected**: exit **3** no que excederia o teto, sem gravar — paridade com
`_ST_MAX=3` de hoje, agora com `CHECK` no banco como rede.

---

## Cenário 2 — Escrita concorrente sem atualização perdida (US1 AS-3, SC-002)

1. Inicializar execução e abrir onda.
2. Disparar **em paralelo**: `state-decisions.sh register` (decisão A) e
   `state-ondas.sh record-task` (task B).
3. Aguardar ambos; conferir exit codes.
4. Contar decisões e tasks.

**Expected**: ambos saem 0; a decisão A **e** a task B estão presentes.
Taxa de atualização perdida = **0%** (SC-002). Nenhum estado parcial.

**Variante — dois escritores na mesma entidade**: dois `register`
simultâneos ⇒ duas decisões com IDs distintos (`dec-001`, `dec-002`),
nenhuma sobrescrita.

> Este é o cenário que o mecanismo atual não sustenta: o RMW do
> `state.json` faz read-modify-write do arquivo inteiro; duas escritas
> concorrentes fora do lock perdem uma das duas.

### 2.a — Leitor durante escrita (FR-011)

1. Iniciar uma escrita longa (transação com `sleep` interno).
2. Durante ela, rodar `state-rw.sh get --field '.current_stage'` e
   `bloqueios.sh count --pending-only`.

**Expected**: leituras retornam **imediatamente**, com o último estado
consistente (pré-transação), exit 0. Não bloqueiam nem são bloqueadas — WAL.
Nenhuma leitura parcial.

---

## Cenário 3 — Migração preserva 100% da auditoria (US2, SC-001)

1. Tomar um `state.json` real com N decisões, M ondas, K tasks, J eventos,
   L bloqueios (ex.: o desta própria execução, já com 4 ondas).
2. Rodar a migração.
3. Comparar contagens e conteúdo (round-trip do export vs. origem
   canonicalizada com `jq -S .`).

**Expected**: contagens idênticas; IDs (`dec-NNN`, `block-NNN`, `onda-NNN`),
timestamps e conteúdo preservados; diff canonicalizado vazio. `state.json`
original **intacto**.

### 3.a — Idempotência (US2 AS-2)

1. Rodar a migração de novo sobre o mesmo projeto.

**Expected**: sem duplicação nem corrupção; contagens iguais às de (3).
Registro em `migration_run`.

### 3.b — Dados inconsistentes ⇒ recusa (US2 AS-3, SC-006)

1. Forjar `state.json` com bloqueio humano apontando decisão inexistente.
2. Tentar migrar.

**Expected**: recusa com diagnóstico apontando o registro problemático;
**nenhum** `state.db` produzido. 100% dos casos (SC-006).

### 3.c — Execução ativa ⇒ recusa (FR-005)

1. `state.json` com `.execution.status == "em_andamento"`; migrar.

**Expected**: recusa; mensagem instruindo concluir/abortar/pausar antes.

### 3.d — Interrupção no meio (US2 AS-4)

1. Matar o processo entre a construção e a publicação.
2. Inspecionar o projeto.

**Expected**: `state.json` intacto e operável; nenhum `state.db` **visível**
(só, no pior caso, um temporário `.state.db.tmp.*`). O projeto nunca fica
sem fonte de verdade válida.

---

## Cenário 4 — Export aceito pelos consumidores atuais (US3, SC-004)

1. Gerar o export de um projeto em `state.db`.
2. `state-validate.sh --state-dir <dir>`.

**Expected**: **exit 0** (US3 AS-1). O validador de hoje é o oráculo.

### 4.a — Export reflete mutação nova (US3 AS-2, SC-004)

1. Registrar decisão nova no `state.db`.
2. Regenerar o export; ler `.decisions[-1].id`.

**Expected**: a decisão nova aparece, em **até 5 segundos** (SC-004).

### 4.b — Consumidor legado não percebe diferença (US3 AS-3)

1. Rodar consumidores reais contra o export: `cycles.sh`, `circular.sh`,
   `retro.sh`, `pipeline.sh`, `report.sh` e o hook
   `posttooluse-tool-call-tick.sh`.

**Expected**: comportamento idêntico ao de um `state.json` nativo. Atenção a
E3 de [export.md](./contracts/export.md): chaves **ausentes** (não `null`)
para `canonical_project`/`session_name` quando não fornecidas.

### 4.c — Falha de export não bloqueia o fechamento da onda (Edge Case)

1. Tornar o destino do export não-gravável.
2. Fechar uma onda (`state-ondas.sh end`).

**Expected**: a onda **fecha** no `state.db` (transação commitada); a falha
de export vai para stderr. Degrada, não bloqueia.

---

## Cenário 5 — Ingestão SQL→SQL equivalente (US4, SC-005)

1. Projeto com `state.db` populado; rodar ingestão SQL→SQL.
2. Mesmo projeto: gerar export e rodar a ingestão JQ atual num
   `knowledge.db` separado.
3. Comparar as tabelas resultantes.

**Expected**: mesmas entidades (`decisions`, `waves`, `blocks`, `tasks`,
`events`, `skills`), mesma proveniência (`project`/`feature`/`wave`/data) —
100% de equivalência (SC-005). Atenção: `skills` **exclui** `kind = 'gate'`.

### 5.a — Projeto não migrado segue pelo caminho JSON (US4 AS-2, FR-012)

1. Projeto só com `state.json`; rodar `cstk recall --ingest --state-dir …`.

**Expected**: funciona **sem alteração**. A rota SQL é aditiva.

### 5.b — knowledge.db continua único e derivado (US4 AS-3, FR-009)

**Expected**: nenhum projeto grava no `knowledge.db`; ele permanece global,
derivado e reconstruível por `cstk recall --reindex`.

---

## Cenário 6 — Projeto não migrado inalterado (FR-012, SC-003)

1. Projeto com `state.json` e **sem** `state.db`.
2. Rodar uma onda completa (init → start → decisão → end).
3. `./tests/run.sh` (suíte inteira, ~1100+ cenários).

**Expected**: comportamento observável idêntico ao de hoje; **0 regressões**
atribuíveis a esta feature (SC-003). Este é o cenário de maior risco da
feature — a seleção de backend (§C2) é o ponto único de falha.

> Nota de execução (memória do repo): a suíte completa leva ~12 min; rodar
> em background preso ao processo pai. `--fast` é atalho de dev-loop e não
> substitui o gate de release.

---

## Cenário 7 — Verificação de integridade (FR-010)

1. `state.db` íntegro ⇒ rodar a verificação.
2. Corromper bytes do arquivo ⇒ verificar de novo.

**Expected**: (1) exit 0. (2) exit != 0, corrupção reportada.

### 7.a — Adulteração bem-formada `[D4-a FECHADA — dec-025]`

1. `UPDATE decision SET choice='outra' WHERE id='dec-001';` via `sqlite3`.
2. Rodar a verificação.

**Expected**: exit 0 (`ok`) — comportamento **aceito e documentado**, não um
bug. D4-a (research.md Decision 4) foi fechada pelo operador (bloqueio
`block-002`, resposta `dec-025`) na opção 1: `PRAGMA integrity_check`
sozinho, sem cobertura de adulteração bem-formada, assumindo operador local
confiável. Este cenário existe para **documentar o regresso**, não para
reprová-lo — se um teste automatizado cobrir 7.a, o assert correto é "exit
0 mesmo após edição bem-formada", registrando o limite conhecido do
mecanismo.

---

## Convenções de borda

**N/A — single-layer.** A feature é biblioteca/CLI POSIX sh local: não há
fronteira backend↔frontend, nem DTO, nem payload de API, nem serialização
entre serviços. A única fronteira de formato é `state.db` ↔ export
`state.json`, cujo contrato é [contracts/export.md](./contracts/export.md) e
cujo oráculo é `state-validate.sh`. O consumidor externo (`cstk-panel`) lê o
`knowledge.db`, não o `state.json` — protegido indiretamente por FR-008/009.
