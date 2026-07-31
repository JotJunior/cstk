# Implementation Plan: Fundação state.db

**Feature**: `state-db-foundation` | **Date**: 2026-07-30 | **Spec**: [spec.md](./spec.md)

## Summary

Substituir o `state.json` por um banco SQLite (`state.db`) por projeto como
fonte de verdade transacional das execuções 00c, movendo para a camada de
armazenamento as invariantes que hoje vivem em prosa e em validação
imperativa espalhada por scripts.

**Abordagem técnica** (research.md): CLI `sqlite3` invocado de POSIX sh —
mesmo padrão já em produção em `cli/lib/recall.sh` para o `knowledge.db`;
`PRAGMA journal_mode=WAL` como mecanismo primário de concorrência
(pré-decidido pelo operador em `dec-014`); uma transação `BEGIN IMMEDIATE`
por mutação; invariantes do FR-002 como `CHECK`/`UNIQUE` parcial/`FOREIGN
KEY`/`TRIGGER`; migração em quatro tempos (recusar → construir fora →
verificar → publicar por rename atômico); export derivado `state.json`
(FR-007) protegendo ~24 consumidores existentes sem reescrita.

**A superfície de CLI dos scripts de runtime não muda** — só o backend por
trás dela. Ver [contracts/primitives.md](./contracts/primitives.md) §C1.

---

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`, sem Bash-isms) —
Princípio II da constitution.
**Primary Dependencies**: `sqlite3` (verificado local: `/usr/bin/sqlite3`
3.51.0) — **ver ressalva no Constitution Check**; `jq` (já dependência de
fato: 23 scripts do runtime gateiam nele).
**Storage**: SQLite por projeto, em
`<projeto-alvo>/.claude/{agente-00c-state,feature-00c-state/<short-name>}/state.db`.
WAL ⇒ sidecars `state.db-wal` / `state.db-shm`.
**Testing**: harness POSIX do repo (`tests/run.sh`, ~1100+ cenários);
convenção `tests/test_<nome>.sh` p/ `global/skills/*/scripts/`,
`tests/cstk/test_<nome>.sh` p/ `cli/lib/`; `--check-coverage` falha em
script órfão.
**Target Platform**: macOS/Linux, filesystem local (WAL não é confiável
sobre NFS — aceito: o estado vive dentro do repo de trabalho).
**Project Type**: CLI / biblioteca de scripts — single-layer.
**Performance Goals**: SC-004 — export reflete mutação em <= 5s. Escrita de
estado é da ordem de dezenas de mutações por onda, não throughput sustentado.
**Constraints**: SC-002 (0% de atualização perdida sob escrita concorrente);
SC-003 (0 regressões na suíte para projeto não migrado).
**Scale/Scope**: um banco por projeto; ordem de dezenas a centenas de ondas
e decisões por execução (esta própria execução: 4 ondas, 20 decisões).

---

## Constitution Check

*GATE: deve passar antes do Phase 0. Re-checado após Phase 1 — ver §Re-check.*

Constitution `docs/constitution.md`, **versão 1.2.0** (rodapé: `**Version**:
1.2.0 | **Ratified**: 2026-04-20 | **Last Amended**: 2026-06-18`).

| Princípio | Status | Notas |
|---|---|---|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | Feature conduzida pela pipeline SDD; spec ratificada, clarify concluído, decisões auditadas em `state.json`. O FR-002 **reforça** o Princípio I ao tornar os 5 campos obrigatórios da decisão uma constraint inviolável. |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | **CONDICIONAL — ver ressalva** | Scripts seguem POSIX sh; a dependência `sqlite3` é obrigatória e **sem fallback**. |
| III. Formato canônico de skill | N/A | A feature não cria nem altera skill; mexe no runtime interno (`agente-00c-runtime`) e possivelmente no CLI `cstk`. |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | Tudo local: `state.db` no projeto, `knowledge.db` em `~/.claude/cstk/`. Nenhuma rede introduzida. |
| V. Profundidade > métricas de adoção | PASS | A feature existe para reduzir retrabalho (corrigir a fragilidade do RMW e das invariantes por convenção), não para ampliar adoção. |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | Todo identificador nos artefatos foi extraído por leitura direta das fontes reais, com arquivo/linha; propostas estão marcadas `[PROPOSTA]` e decisões não fechadas como **DECISÃO EM ABERTO**. |

### RESSALVA BLOQUEANTE — Princípio II e a dependência `sqlite3`

**Situação de direito.** O Princípio II é NON-NEGOTIABLE e diz, literalmente
(`docs/constitution.md` L109-110):

> *"Dependencias obrigatorias (sem fallback) permanecem proibidas sob o
> bloco MUST do Principio II."*

O carve-out `#### Optional dependencies with graceful fallback (amendment
1.1.0)` **não cobre** este caso: exige três condições cumulativas, e a (a) é
*"Uso genuinamente opcional com fallback graceful documentado E verificável
— a feature MUST funcionar sem a ferramenta"*. O `state.db` **não pode**
funcionar sem `sqlite3`; não há fallback possível para a fonte de verdade
transacional.

**Portanto**: assumir `sqlite3` como dependência obrigatória exige um
**amendment MINOR dedicado da constitution (1.2.0 → 1.3.0)** que reconheça a
camada de estado transacional como exceção disciplinada.

**Esse amendment NÃO EXISTE hoje.** É **pré-requisito de implementação** e
é conduzido **fora** desta feature: o pipeline `feature-00c`
(`specify → clarify → plan → checklist → create-tasks → execute-task →
review-task`) **não inclui a etapa `constitution`**. Registrado na spec
(§Clarifications, Session 2026-07-30, Q1) e na decisão `dec-020` desta
execução.

**Consequência operacional (MUST):** nenhuma task que implemente escrita ou
leitura do `state.db` pode ser considerada pronta para execução antes do
amendment 1.3.0 ser ratificado. `/create-tasks` MUST materializar isso como
dependência explícita — não como nota de rodapé.

**Fato que reduz — mas não elimina — o risco do amendment**: o runtime de
estado **já** carrega uma dependência obrigatória sem fallback hoje.
`state-rw.sh` L116-118 encerra com exit 1 e mensagem de instalação quando
`jq` está ausente, e 23 scripts do runtime têm o mesmo gate. Ou seja, a
tensão com a leitura literal do Princípio II **pré-existe** a esta feature;
o amendment 1.3.0 regularizaria uma condição já vigente e a estenderia a
`sqlite3`, em vez de abrir precedente inédito. Isso é argumento **para** o
amendment — não substituto dele, e não autoriza prosseguir sem ele.

> Nota de método: a alternativa "documentar a violação em Complexity
> Tracking e seguir" é explicitamente vedada para princípio MUST. O caminho
> adotado é o único disponível: prosseguir com o **plano** (que é
> documentação técnica), carregando a ressalva, e travar a **implementação**
> até a ratificação.

---

## Project Structure

### Documentation (this feature)

```
docs/specs/state-db-foundation/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 — 9 decisões + 1 em aberto (D7-a; D4-a fechada por dec-025)
├── data-model.md        # Phase 1 — schema + constraints do FR-002
├── quickstart.md        # Phase 1 — 7 cenários cobrindo SC-001..SC-006
└── contracts/
    ├── primitives.md    # FR-004 — superfície atual + contrato do backend
    ├── export.md        # FR-007 — export derivado state.json
    └── migration.md     # FR-005 / FR-006 / FR-014 — migração
```

### Source Code (repository root — árvore real, verificada)

```
cstk/
├── cli/
│   ├── cstk                       # binário (dispatch de subcomandos)
│   └── lib/
│       ├── recall.sh              # ingestão knowledge.db (FR-008) — 2702 L
│       ├── 00c-bootstrap.sh       # lê state.json
│       └── …
├── global/
│   ├── agents/
│   │   ├── agente-00c-orchestrator.md
│   │   └── agente-00c-feature-orchestrator.md
│   ├── commands/                  # 6 slash commands 00c
│   └── skills/
│       └── agente-00c-runtime/
│           ├── hooks/             # pretooluse-bash-guard, posttooluse-*
│           └── scripts/           # 35 scripts POSIX (alvo principal)
│               ├── state-rw.sh          # 831 L
│               ├── state-ondas.sh       # 1379 L
│               ├── state-decisions.sh   # 362 L
│               ├── bloqueios.sh         # 370 L
│               ├── spawn-tracker.sh     # 240 L
│               ├── state-validate.sh    # 404 L
│               ├── state-lock.sh        # 172 L
│               └── …
├── docs/
│   ├── constitution.md            # v1.2.0 — amendment 1.3.0 pendente
│   └── specs/
└── tests/
    ├── run.sh                     # harness (~1100+ cenários)
    ├── lib/harness.sh
    ├── test_state-rw.sh           # … um por script
    └── cstk/                      # testes de cli/lib/
```

**Structure Decision**: a feature vive **dentro da estrutura existente** —
nenhum diretório novo de topo. O backend SQLite entra nos scripts de
`global/skills/agente-00c-runtime/scripts/` que já detêm o estado; a
migração ganha script próprio (`state-db-migrate.sh` ou equivalente, ver
[migration.md](./contracts/migration.md) §Nomeação) por causa da colisão com
o subcomando `migrate` **já existente** em `state-rw.sh`; a ingestão SQL→SQL
entra em `cli/lib/recall.sh`, único arquivo que já fala SQLite no CLI.

**Confinamento da dependência**: manter as menções a `sqlite3` no menor
número possível de arquivos identificáveis. Isso não satisfaz o carve-out
1.1.0 sozinho (falta a condição (a), o fallback), mas preserva a condição
(b) — *"grep pelo nome do executável localiza todas as menções"* — que o
amendment 1.3.0 provavelmente vai querer herdar.

---

## Convenções de Borda

**N/A — single-layer.** A feature é biblioteca/CLI POSIX sh local: não há
fronteira backend↔frontend, DTO, payload de API nem serialização entre
serviços — logo não há risco da classe snake_case vs camelCase que motiva
esta seção.

A única fronteira de formato é `state.db` ↔ export `state.json`:

| Camada | Convenção | Validação | Fonte da verdade |
|---|---|---|---|
| Colunas do `state.db` | `snake_case` | `CHECK`/`FK`/`UNIQUE` no schema | [data-model.md](./data-model.md) |
| Chaves do export `state.json` | `snake_case`, **em inglês** | `state-validate.sh` (exit 0) | [contracts/export.md](./contracts/export.md) |
| IDs | `dec-NNN`, `block-NNN`, `onda-NNN` | preservados literalmente | scripts de runtime atuais |

Não há mapper layer nem ORM: a tradução banco↔JSON é explícita no export.
A canonicalização pt-BR→EN das chaves **já é vigente** (`_SR_RENAME_MAP` em
`state-rw.sh`) e o export não a reverte. Consumidor externo (`cstk-panel`)
lê o `knowledge.db`, não o `state.json`.

---

## Ordem de implementação sugerida

Deriva das prioridades da spec e das dependências entre requisitos. Insumo
para `/create-tasks`, não substituto dele.

| Ordem | Escopo | Requisitos | Depende de |
|---|---|---|---|
| **0** | **Amendment 1.3.0 da constitution** | — | **externo à feature; bloqueia tudo abaixo** |
| 1 | Schema + PRAGMAs + constraints | FR-001, FR-002 | 0 |
| 2 | Primitivas de escrita/leitura (paridade de superfície) | FR-003, FR-004, FR-011 | 1 |
| 3 | Seleção de backend (`state.db` vs `state.json`) | FR-012, SC-003 | 2 |
| 4 | Export derivado | FR-007, FR-013-INFRA-BACKUP | 2 |
| 5 | Migração + verificação | FR-005, FR-006, FR-014 | 3, 4 |
| 6 | Verificação de integridade | FR-010 | 1, D4-a (**fechada** — dec-025, opção 1) |
| 7 | Ingestão SQL→SQL | FR-008, FR-009 | 5, **D7-a fechada** |

O passo 4 antes do 5 é deliberado: a verificação campo-a-campo da migração
(M3.2) **usa** o export como comparador, fechando SC-001 sem escrever um
comparador novo.

---

## Decisões em aberto a fechar antes das tasks correspondentes

| # | Decisão | Bloqueia | Onde | Status |
|---|---|---|---|---|
| D4-a | Cobertura de adulteração deliberada (`integrity_check` não detecta edição bem-formada, `sha256-verify` detecta) | FR-010 | research.md Decision 4 | **Fechada** — dec-025 (resposta ao block-002): opção 1, `integrity_check` apenas, regresso aceito |
| D7-a | Forma do acesso na ingestão SQL→SQL (`ATTACH … mode=ro` vs. processo separado) | FR-008 | research.md Decision 7 | Em aberto — fechar em `/create-tasks` |
| E5-a | Gatilho do export (sob demanda / ao fim da onda / ambos) | FR-007 | export.md §E5 | Em aberto — fechar em `/create-tasks` |
| M1-a | `aguardando_humano` é migrável ou recusado? | FR-005 | migration.md §M1 | Em aberto — fechar em `/create-tasks` |
| C8-a | Parâmetros nomeados (`.param set`) disponíveis na versão mínima de `sqlite3`? Se não, `strip_nul`+`sql_escape` é o piso | FR-003, FR-004 | primitives.md §C8 | Em aberto — fechar em `/create-tasks` |

### Achados do gate de segurança (onda-004)

O gate `owasp-security` sobre o desenho produziu 5 findings. Três foram
**remediados no próprio contrato** nesta onda; um é decisão de threat model
escalada ao operador; um é informativo.

| # | Finding | Sev. | Tratamento |
|---|---|---|---|
| S1 | Contratos especificavam SQL sem exigir escape de texto livre de origem LLM (A05/CWE-89; `sqlite3` CLI executa múltiplos statements) | **high** | **Remediado** — primitives.md §C8 (MUST `strip_nul`+`sql_escape`, reusando os helpers de `recall.sh`) + teste obrigatório |
| S2 | Troca de `sha256-verify` por `PRAGMA integrity_check` remove detecção de adulteração bem-formada do rastro de auditoria (A08/A09, ASVS L2 "tamper-evident") | **high** | **Escalado ao operador e respondido** — bloqueio `block-002`, resolvido via `dec-025`: opção 1 (`integrity_check` apenas, regresso aceito, operador local confiável). D4-a fechada. |
| S3 | Permissão de arquivo é ambiente (umask), não imposta; WAL triplica os arquivos e o `-wal` contém transações recentes em claro | **medium** | **Remediado** — primitives.md §C9 (`chmod 600` explícito) |
| S4 | Temporário da migração com nome derivado de PID (symlink/TOCTOU) | **medium** | **Remediado** — primitives.md §C10 + migration.md §M2 (`mktemp`) |
| S5 | Cadeia de propagação: `state.db` adulterado → export → ingestão → `knowledge.db` → read-back loop realimenta prompts futuros (ASI06 memory poisoning) | **medium** | **Informativo** — amplifica o impacto de S2; mitigado se S2 for resolvido. O scrub de segredos na ingestão permanece inalterado. |

Nenhuma delas é `NEEDS CLARIFICATION` de contexto técnico: são escolhas de
design delimitadas, com opções enumeradas e ponto de decisão atribuído.
Registradas para **não** serem decididas silenciosamente na implementação.

---

## Re-check pós-Phase 1

Reavaliação após o design (data-model + contratos + quickstart):

| Verificação | Resultado |
|---|---|
| O design introduziu complexidade não justificada? | **Não.** Nenhum serviço, camada ou processo novo. Uma tabela por entidade **já existente** na spec; a única entidade nova (`migration_run`) é exigida pela auditabilidade do FR-006. `ExportSnapshot` foi deliberadamente **não** modelada como tabela para não duplicar a fonte de verdade. |
| Princípios MUST continuam respeitados? | I, IV, V, VI: PASS, sem alteração. **II: continua CONDICIONAL** — o design não removeu a necessidade do amendment 1.3.0; ao contrário, confirmou-a (o `state.db` é inviável sem `sqlite3`). |
| Superfície pública mudou? | Não — §C1 de primitives.md fixa paridade de subcomandos/flags/exit codes. Uma mudança de comportamento observável foi identificada e declarada: `state-ondas.sh start` com onda aberta passa a **falhar** em vez de duplicar (§C3) — é a correção de um bug, mas precisa constar. |
| Novo risco identificado no design? | Sim, um: trocar `sha256-verify` por `PRAGMA integrity_check` **reduz** a cobertura contra adulteração deliberada. Não silenciado — virou D4-a, escalada como bloqueio humano (`block-002`) e **fechada** via `dec-025` (opção 1, regresso aceito e documentado); o cenário 7.a do quickstart já tem *expected* definido. |

**Veredito**: PASS em todos os princípios exceto o II, que permanece
**CONDICIONAL ao amendment 1.3.0** — pré-requisito externo, bloqueante para
implementação, não para planejamento.

---

## Complexity Tracking

| Violação | Por que necessário | Alternativa simples rejeitada porque |
|---|---|---|
| **Dependência obrigatória em `sqlite3`, sem fallback** (Princípio II, L109-110) — **pendente de amendment 1.2.0 → 1.3.0** | A feature inteira é "usar um banco relacional como fonte de verdade" (FR-001) e "impor invariantes na camada de armazenamento" (FR-002). Não existe fallback: um modo degradado sem `sqlite3` seria o `state.json` de hoje — isto é, a ausência da feature. | *Manter JSON com lock mais rigoroso*: não atende FR-002 (invariantes declarativas) nem FR-011 (leitores concorrentes não-bloqueados); só endurece o mecanismo que a spec identifica como frágil. *Implementar um motor de constraints em sh sobre JSON*: reescreveria mal um banco de dados, com muito mais código e menos garantia. *Tratar `sqlite3` como dep opcional sob o carve-out 1.1.0*: impossível — a condição (a) exige que a feature funcione sem a ferramenta. |
| `sqlite3` fora de um único arquivo (tensão com a condição (b) do carve-out 1.1.0) | O estado é mutado por múltiplos scripts especializados (`state-rw`, `state-ondas`, `state-decisions`, `bloqueios`, `spawn-tracker`). Concentrar todo acesso a banco num só arquivo criaria uma camada de indireção nova entre cada script e seu próprio estado. | *Camada única de acesso*: reduziria menções a `sqlite3` a um arquivo, mas ao custo de um indireção artificial. **Não descartada** — é decisão de granularidade a revisitar em `/create-tasks`, e o amendment 1.3.0 pode torná-la desnecessária ao dispensar a condição (b) para esta camada. |

> Nenhuma outra violação. Esta tabela existe **exclusivamente** por causa da
> ressalva do Princípio II documentada no Constitution Check — e ela **não**
> autoriza prosseguir: o amendment é pré-requisito, não justificativa
> *post-hoc*.

---

## Artefatos

| Arquivo | Status |
|---|---|
| `docs/specs/state-db-foundation/plan.md` | Criado |
| `docs/specs/state-db-foundation/research.md` | Criado |
| `docs/specs/state-db-foundation/data-model.md` | Criado |
| `docs/specs/state-db-foundation/contracts/primitives.md` | Criado |
| `docs/specs/state-db-foundation/contracts/export.md` | Criado |
| `docs/specs/state-db-foundation/contracts/migration.md` | Criado |
| `docs/specs/state-db-foundation/quickstart.md` | Criado |
