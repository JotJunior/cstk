# Implementation Plan: Decisoes estruturais exigem gate humano

**Feature**: `structural-decision-human-gate` | **Date**: 2026-08-19 | **Spec**: [spec.md](./spec.md)

## Summary

Fechar as quatro lacunas de governanca da issue #146, que permitiram a um
orquestrador autonomo fixar sozinho a linguagem/runtime de um projeto: (1) o
runtime nao reconhece "classe" de decisao — ter `bloqueio-humano` entre as
opcoes nao significa nada; (2) o Phase 0 da skill `plan` resolve
`NEEDS CLARIFICATION` por inferencia mesmo sem humano na sessao; (3) a coluna
`Impacto` da tabela "Itens a Definir" do briefing e decorativa; (4) o campo
`Target Platform` do plano aceita pendencia sem gate.

**Abordagem tecnica**: estender a entidade Decisao com tres colunas aditivas
(`decision_class`, `structural_axis`, `human_consent_block_id`) e o
BloqueioHumano com uma (`subject_key`), e transformar a regra R2 numa trava de
runtime nas duas portas de escrita (helper POSIX + tool MCP), reusando
exatamente a mecanica ja provada da trava de constitution-conflict. O
consentimento humano e uma **referencia verificavel a um bloqueio respondido** —
nunca o campo de agente, que e texto livre (emenda `dec-024`, resposta ao
`block-001`). Somam-se
dois gates deterministicos e independentes — extracao dos itens de impacto
`Alto` do briefing e verificacao do ambiente alvo no `plan.md` — mais duas
regras de prosa nas skills `plan` e `create-tasks`. As mudancas de leitura
(relatorio, `review-task`, knowledge.db) sao derivadas: nenhuma anomalia e
persistida.

**Alcance real da trava (declarado para o artefato nao ler mais forte do que e)**:
a feature e forte contra **consentimento forjado** e fraca contra **omissao**.

- *Forte*: uma vez que a classe `estrutural` esteja declarada, nao ha como
  registrar escolha concreta sem apontar um BloqueioHumano `respondido` da mesma
  execucao **e do mesmo eixo**, verificado contra o estado no momento do
  registro. Nenhuma string escrita pelo agente satisfaz a condicao — foi
  exatamente o buraco fechado pela emenda `dec-024`. O vinculo de assunto veio
  de uma segunda passada do gate de seguranca sobre a propria emenda (`dec-030`):
  sem ele, o consentimento seria um cheque em branco reaproveitavel entre eixos.
- *Fraca*: R1 so dispara quando `options_considered` **ja** contem token de
  bloqueio humano, e classe ausente e no-op (R4). Um agente que fixe
  linguagem/runtime **sem** listar `bloqueio-humano` entre as opcoes — a forma
  exata da #146 — nao aciona R1, logo nunca precisa de `--classe` e R2/R3 nao
  rodam.

A garantia dura contra omissao vem dos gates deterministicos de US2/US3, que
cobrem `ambiente-alvo` (pelo plano) e o que o briefing marcar como item `Alto`.
Os eixos `stack-frameworks`, `arquitetura` e `persistencia` seguem **sem**
detector proprio — limitacao L1 da spec, excluida desta feature por decisao
explicita do operador em `dec-024` (resposta ao `block-001`), com hardening
rascunhado como issue propria do toolkit. Ver tambem L2 (portas de escrita sem
guarda) na mesma secao da spec.

Ver [research.md](./research.md) (12 decisoes de Phase 0),
[data-model.md](./data-model.md) e [contracts/](./contracts/).

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`, sem bash-isms) para o runtime e os gates; TypeScript 5.x sobre Node >= 22 no servidor MCP (`mcp/state-server/package.json` `engines.node`)
**Primary Dependencies**: `sqlite3` >= 3.45.1 e `jq` — dependencias obrigatorias ja regularizadas nesta camada pelo carve-out do amendment 1.3.0 da constitution; `zod` no servidor MCP. **Nenhuma dependencia nova** e introduzida por esta feature
**Storage**: dual-backend ja existente — `state.db` (SQLite, fonte de verdade transacional) e `state.json`; indice derivado `~/.claude/cstk/knowledge.db`
**Testing**: `tests/run.sh` (harness POSIX; `test_<nome>.sh` por script, gateado por `--check-coverage`) e `node:test` via `npm test` em `mcp/state-server/`
**Target Platform**: CLI local do operador em ambiente POSIX (macOS e Linux) — sem servidor, sem rede. **Fonte**: `docs/constitution.md` Principio II ("rodam em qualquer ambiente POSIX sem setup") e `CLAUDE.md` deste repositorio
**Project Type**: cli — toolkit de skills/commands/agents distribuido como plugin do Claude Code, com binario `cstk` complementar
**Performance Goals**: overhead adicional por `register` limitado a um `PRAGMA table_info` numa operacao que ja paga o spawn de um processo `sqlite3`; extracao dos itens do briefing sem chamada de rede (SC-005)
**Constraints**: POSIX puro nos scripts novos (sem `jq` no parser de briefing e no lookup de eixos); regressao zero na suite existente (FR-005, SC-004); mudanca estritamente aditiva no estado, sem migracao obrigatoria para o operador (FR-013)
**Scale/Scope**: 4 user stories, 14 requisitos funcionais; ~8 arquivos de codigo alterados, 1 script novo, 1 tabela de referencia nova, 2 arquivos de prosa de skill e 2 de prosa de orquestrador

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checar apos Phase 1.*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD aplica-se recursivamente (NON-NEGOTIABLE) | PASS | A feature tem spec ratificada, este plano e backlog subsequente; a propria mudanca de runtime e desenvolvida pela pipeline que ela governa |
| II. Scripts POSIX sh puros, zero dependencia externa (NON-NEGOTIABLE) | PASS | O script novo (`briefing-items.sh`) e o lookup de eixos (funcao interna de `state-decisions.sh`, sem arquivo proprio) sao POSIX puros e **sem** `jq`, seguindo o precedente de `delivery-tier.sh` e `model-routing.sh phase-model-lookup`. O uso de `jq`/`sqlite3` nos arquivos ja existentes permanece dentro do carve-out do amendment 1.3.0; nenhuma dependencia nova e adicionada |
| III. Formato canonico de skill: progressive disclosure, gotchas, description-como-trigger | PASS | As edicoes em `plan/SKILL.md` e `create-tasks/SKILL.md` entram como regra na etapa correspondente e como gotcha; nenhum `description` muda, portanto nenhum trigger de skill e afetado |
| IV. Zero coleta remota de uso ou dados (NON-NEGOTIABLE) | PASS | Nenhuma chamada de rede. O parser de briefing e o gate de plano sao locais e read-only; a knowledge.db permanece local |
| V. Profundidade e reducao de retrabalho acima de metricas de adocao | PASS | A feature **adiciona atrito deliberado** (pausa a execucao) em troca de eliminar o retrabalho de roadmap/briefing/constitution observado na #146. SC-006 protege o outro lado: decisoes operacionais nao podem ganhar bloqueios novos |
| VI. Veracidade de dados — zero fabricacao (NON-NEGOTIABLE) | PASS | E a motivacao da feature. O gate de ambiente alvo **jamais fabrica fonte** — pede fonte e, se ausente, emite aviso (INV-V3). O `research.md` declara explicitamente cada achado de ausencia como verificado por grep exaustivo |

**Re-check pos-Phase 1**: mantido PASS em todos os principios. O design nao
introduziu camada, servico nem dependencia nova; a unica complexidade
acrescentada e a migracao de schema do `state.db`, justificada e limitada na
secao Complexity Tracking.

## Project Structure

### Documentation (this feature)

```
docs/specs/structural-decision-human-gate/
├── spec.md
├── plan.md          # This file
├── research.md      # Phase 0 output
├── data-model.md    # Phase 1 output
├── quickstart.md    # Phase 1 output
└── contracts/       # Phase 1 output
    ├── cli-structural-class.md
    └── mcp-record-decision.md
```

### Source Code (repository root)

Arvore real, restrita aos caminhos que esta feature toca:

```
plugins/cstk/
├── agents/
│   ├── agente-00c-orchestrator.md              # prosa: classe estrutural (FR-006, FR-014)
│   └── agente-00c-feature-orchestrator.md      # prosa: idem + gate de itens Alto (FR-008)
└── skills/
    ├── agente-00c-runtime/
    │   ├── references/
    │   │   └── structural-axis-map.txt         # NOVO — enum de eixos (FR-006)
    │   └── scripts/
    │       ├── state-decisions.sh              # --classe/--eixo/--consentimento + R1..R3, R6 (FR-001..FR-003)
    │       ├── _state-decisions-db.sh          # INSERT com as colunas novas
    │       ├── bloqueios.sh                    # --chave-assunto no register + filtro no list (FR-008)
    │       ├── _bloqueios-db.sh                # INSERT/SELECT com subject_key
    │       ├── _state-rw-db.sh                 # export e upsert das colunas novas
    │       ├── state-db-schema.sh              # NOVO subcomando `ensure` (Decision 3)
    │       ├── briefing-items.sh               # NOVO — extrator de itens Alto (FR-007)
    │       └── report.sh                       # secao 3: classe, eixo, anomalia (FR-012)
    ├── briefing/templates/briefing.md          # (referencia; nao alterado)
    ├── create-tasks/SKILL.md                   # ordenacao do gate de dependencias (FR-011)
    ├── plan/SKILL.md                           # Phase 0 em modo autonomo (FR-009)
    ├── review-task/SKILL.md                    # contagens estruturais/anomalias (FR-012)
    └── validate-documentation/scripts/
        └── validate-sdd.sh                     # 2 findings novos no plan-profile (FR-010)

plugins/cstk/skills/agente-00c-runtime/references/state-db-schema.sql  # DDL: 2 colunas

mcp/state-server/
├── src/
│   ├── tools/record_decision.ts                # 2 campos zod + 3 erros tipados (FR-004)
│   └── runtime/exec.ts                         # FIELD_TO_FLAG_TABLE + McpToolErrorCode
└── test/
    ├── record_decision.test.ts                 # cenarios das regras R1..R3
    └── exec-mapper-parity.test.ts              # gate de paridade (INV-M2)

cli/lib/recall.sh                               # schema 14 -> 15, 2 colunas (FR-012)

tests/
├── test_state-decisions.sh                     # cenarios das regras R1..R3 e R6 (consentimento)
├── test_bloqueios.sh                           # subject_key: register, filtro, dedup, legado NULL
├── test_briefing-items.sh                      # NOVO — obrigatorio por --check-coverage
├── test_state-db-schema.sh                     # cenarios de `ensure`: idempotencia, fail-hard, banco pre-feature
├── test_state-rw.sh                            # projecao das colunas novas no export
├── test_validate-sdd.sh                        # cenarios do ambiente alvo
├── test_report.sh                              # render de classe/eixo/anomalia
└── cstk/test_recall.sh                         # migracao v15 e ingestao
```

**Structure Decision**: nenhuma estrutura nova e criada. A feature se encaixa
inteiramente nos diretorios existentes, seguindo tres precedentes ja
estabelecidos no repositorio: helper POSIX + tabela de referencia versionada em
`references/` (padrao de `delivery-tier.sh` + `tier-gate-map.txt`); trava de
regra na porta de escrita do estado (padrao da trava de constitution-conflict);
e paridade helper <-> tool MCP gateada por teste de mapper. Dois arquivos novos
apenas — o script `briefing-items.sh` (com seu teste obrigatorio) e a tabela
`structural-axis-map.txt`.

## Convencoes de Borda

A feature atravessa quatro camadas, e a divergencia de nomenclatura entre elas e
um risco real (a flag e portuguesa, a coluna e inglesa). Declarado aqui de forma
explicita para nao repetir o modo de falha de drift tardio:

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Flags do helper POSIX | kebab-case, **portugues** (`--classe`, `--eixo`, `--consentimento`, `--chave-assunto`) | parser `case` do proprio script | `plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh`, `bloqueios.sh` |
| Colunas do `state.db` | snake_case, **ingles** (`decision_class`, `structural_axis`, `human_consent_block_id`, `subject_key`) | DDL; regras R1..R3 e R6 no helper (nao como CHECK — vide data-model) | `plugins/cstk/skills/agente-00c-runtime/references/state-db-schema.sql` |
| Campos do `state.json` / export | snake_case, **ingles** (identicos as colunas) | `state-validate.sh` | `_state-rw-db.sh` (projecao de `.decisions[]`) |
| Campos da tool MCP | snake_case, **ingles** (identicos as colunas) | `zod` + `superRefine` | `mcp/state-server/src/tools/record_decision.ts` |
| Valores dos enums | kebab-case, **portugues** (`estrutural`, `linguagem-runtime`) | lista fechada em arquivo de referencia | `references/structural-axis-map.txt` |
| Colunas da knowledge.db | snake_case, **ingles** (espelham o state; `subject_key` **nao** e propagado) | migracao idempotente por `PRAGMA table_info` | `cli/lib/recall.sh` |

**Mapper layer (flag <-> campo <-> coluna)**: a traducao flag-portuguesa para
campo-ingles ja existe e e explicita na constante `FIELD_TO_FLAG_TABLE` de
`mcp/state-server/src/runtime/exec.ts`; os tres campos novos de
`record_decision` entram nela (`--chave-assunto` pertence a
`register_human_block`, nao a `record_decision`).
ORM auto-mapping: **NAO** — todo o mapeamento e explicito, em SQL escrito a mao.

**Validacao**: em ambas as bordas, deliberadamente. `zod` na tool (rejeita antes
de invocar o helper) e validacao POSIX no helper (autoritativa, vale mesmo se a
tool for contornada). Schema compartilhado entre as duas pontas: **nao existe** —
a paridade e garantida por teste (`exec-mapper-parity.test.ts`), nao por tipo
compartilhado; e essa e a razao de INV-M1 ser explicito.

## Complexity Tracking

> Preenchido porque o design introduz uma complexidade que exige justificativa,
> embora nenhum principio da constitution seja violado.

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| Migracao de schema no `state.db` sem existir mecanismo de migracao | Verificado: `state-db-schema.sh` so tem `create`, todo o DDL e `CREATE TABLE IF NOT EXISTS`, e e invocado em apenas dois pontos (`state-rw.sh:553` no `init` e `state-db-migrate.sh:260` na migracao json->db). Sem tratamento, toda execucao ja em andamento quebraria com `no such column` na primeira decisao classificada | Exigir migracao manual do operador foi rejeitado: interromperia execucoes em curso e a feature e nao-retroativa, nao "nao-instalavel a quente". Construir um migrador versionado completo (`user_version`) foi rejeitado por escopo: e divida tecnica propria do `state.db`, e resolve-la aqui triplicaria o blast radius |
| Quatro colunas novas (tres em `decision`, uma em `human_block`) | Cada uma responde uma pergunta distinta que a spec exige responder sem heuristica: `decision_class` (esta decisao e estrutural?), `structural_axis` (qual eixo?), `human_consent_block_id` (quem autorizou?) e `subject_key` (isto ja foi perguntado?). As duas ultimas sao a emenda `dec-024`; sem elas, consentimento e dedup voltariam a ser casamento sobre texto livre, que e o modo de falha da #146 | Coluna unica com valor composto (`estrutural:linguagem-runtime`) foi rejeitada: exigiria parsing em todo leitor e impediria filtro por eixo no indice. Derivar consentimento do campo `agent` foi rejeitado pela propria resposta `dec-024` — e auto-declaracao. Guardar a chave de assunto na Decisao em vez do bloqueio foi rejeitado: exigiria dois saltos para responder "ja perguntei isto?" |
| Regras R1..R3 duplicadas em POSIX e em TypeScript | FR-004 exige paridade helper/tool; a #146 provou que uma unica porta destravada basta para a decisao passar. O helper e a porta autoritativa, a tool e a conveniente | Validar so na tool MCP foi rejeitado: o helper e chamado diretamente pelos orquestradores quando o toolset MCP nao esta disponivel — que e, inclusive, o caso desta propria execucao |

**Divida tecnica registrada (fora de escopo)**: o `state.db` segue sem
versionamento de schema. O `ensure` desta feature e uma migracao pontual
idempotente, nao um migrador geral. Um mecanismo versionado (`user_version` +
migracoes ordenadas) permanece pendente e deve ser feature propria.

**Limitacoes de seguranca declaradas (fora de escopo por decisao do operador)**:
`dec-024`, respondendo ao `block-001`, manteve os 14 FRs como escopo e excluiu
dois findings HIGH desta feature. Ambos estao registrados como L1 e L2 na secao
"Limitacoes declaradas" da spec e rascunhados como issue de hardening do
toolkit, para o operador revisar e publicar:

| Item | O que fica em aberto | Por que nao entra aqui |
|------|----------------------|------------------------|
| L1 | `stack-frameworks`, `arquitetura` e `persistencia` sem detector deterministico proprio — deteccao segue dependendo de o agente declarar a classe quando o eixo nao passa pelo briefing nem pelo plano | Exigiria projetar tres gates novos, cada um com sua fonte de verdade; e feature propria, nao emenda. `dec-024` foi explicito em "emenda, nao expansao" |
| L2 | Escrita direta em arquivo de estado e cliente SQL direto sobre o banco nao passam pelo helper nem pelo guard de comandos; nesse caminho ate a transicao de bloqueio para `respondido` e fabricavel | Fechar exige guarda nas ferramentas de escrita de arquivo (nao so nas de shell), o que muda o modelo de enforcement do toolkit inteiro — blast radius muito alem desta feature |

Registrar assim, e nao "resolver na surdina", e o proprio Principio VI aplicado
ao artefato: o plano declara o que a implementacao vai de fato garantir.
