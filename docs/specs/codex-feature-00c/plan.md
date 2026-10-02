# Implementation Plan: Pipeline CSTK no Codex

**Feature**: `codex-feature-00c` | **Date**: 2026-10-02 | **Spec**: [spec.md](spec.md)

## Summary

Seis entradas 00c no Codex, instalação específica, pipeline compartilhada,
estado exclusivo e conhecimento derivado auditável. O código existente usa
`adapters/codex`, helpers canônicos `plugins/cstk` e plugin/MCP nativo.

Plano retrospectivo da implementação observada: Constitution Check **FAIL**.
Pesquisa, modelo e contratos abaixo documentam código existente; não são
avanço de novo design através de gate reprovado. Aceite real permanece aberto.

## Technical Context

**Language/Version**: POSIX sh no runtime; Python 3 no adaptador, hooks, builder e instalador. Instalador não declara versão mínima Python; teste observado usa `/opt/homebrew/bin/python3`.
**Primary Dependencies**: instalador exige `codex`, `python3`, `jq`, `sqlite3`; stdlib Python, sem pip. Harness observado: Codex CLI 0.160.0.
**Storage**: JSON/SQLite canônicos; knowledge.db derivado schema 16; evidências, backups e relatórios locais.
**Testing**: unittest em `tests/codex`, grupos shell, contratos MCP/app-server isolados e gates documentais CSTK.
**Target Platform**: Codex local observado em macOS; App/IDE/cloud precisam de evidência própria.
**Project Type**: toolkit/CLI, plugin nativo e orquestração supervisionada.
**Performance Goals**: sem SLA novo; respeitar orçamento/chamadas do runtime. Tempos de testes não são metas de produto.
**Constraints**: escritor único; opt-ins reais; confiança não automática; conhecimento best-effort; modelo desconhecido nullable; preservar personalizações.
**Scale/Scope**: seis skills, quinze ferramentas MCP, oito/onze/três etapas; nenhum scheduler ou segundo modelo implícito.

## Constitution Check

*GATE: conformidade antes de novo design/implementação. Revisão do código
existente contra constitution 1.3.0 em 2026-10-02.*

| Princípio | Status | Notas |
|-----------|--------|-------|
| I — SDD recursivo | FAIL histórico; reparação documental realizada | Implementação antecedeu spec.md; padronização não reescreve cronologia. Novos incrementos exigem artefatos upstream. |
| II — Scripts POSIX/dependências | FAIL | Python obrigatório em hooks/instalador/adaptador está fora dos carve-outs vigentes. FASE 7 exige decisão de redesenho/emenda. |
| III — Formato de skill | FAIL | Seis SKILL.md do adaptador sem seção Gotchas; reparação na FASE 7. |
| IV — Zero coleta remota | PASS no escopo inspecionado | Adaptador não adiciona coleta; sessão remove atribuição do exportador Claude. Download de release não é telemetria. |
| V — Profundidade | PASS | Reutilização, retomada e precedentes atendem direção pedida pelo operador. |
| VI — Veracidade | PASS na documentação normalizada | Contratos extraídos do código; resultados associados aos logs; nenhum aceite real presumido. |

O pedido de compatibilidade não foi registrado como aprovação de emenda
específica. A [proposta de governança](contracts/governance-proposal.md)
apresenta um caminho revisável; nenhuma emenda foi aplicada. Ver
[review.md](review.md) e o backlog de convergência.

## Project Structure

### Documentation (this feature)

```text
docs/specs/codex-feature-00c/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md
├── checklists/requirements.md
├── contracts/workflows.md
├── contracts/installation.md
├── contracts/governance-proposal.md
├── support-matrix.md
├── native-acceptance.md
├── dogfood-session-2026-10-02.md
├── validation.md
├── review.md
├── converge-report.md
└── evidence/
    ├── implementation-history.md
    └── documentation-gates.txt
```

### Source Code (repository root)

```text
adapters/codex/plugin.json
adapters/codex/mcp.json
adapters/codex/hooks/
adapters/codex/skills/
plugins/cstk/skills/agente-00c-runtime/scripts/
cli/lib/install-codex.py
cli/lib/install.sh
cli/lib/recall.sh
scripts/build-codex-plugin.py
scripts/build-release.sh
tests/codex/
tests/cstk/
```

**Structure Decision**: um repositório, sem duplicar runtime/regras/templates.
Layout `.claude` do estado é preservado por compatibilidade, não identidade do
executor. Fork e mudança de layout ficam fora da entrega.

## Convenções de Borda

| Camada | Case style | Validação | Fonte da verdade |
|--------|------------|-----------|------------------|
| MCP/JSONL | snake_case | schema fechado, lock, identidade, gates | mcp_bridge.py, controller.py no adaptador |
| Estado JSON | contrato do runtime | state-validate.sh, integridade | state-rw.sh no runtime |
| Estado SQLite | SQL + extra_fields | transação/exportação normalizada | _state-rw-db.sh no runtime |
| Índice derivado | executions.execution_provenance nullable | migração aditiva/upsert por origem | cli/lib/recall.sh |
| Hooks | envelope do harness | allowlist/paths/schema observados | adapters/codex/hooks/ |

**Mapper layer**: Session traduz chamadas para helpers; recall.sh projeta
estado no índice. Sem ORM ou frontend. Contratos em
[workflows](contracts/workflows.md) e [instalação](contracts/installation.md).

## Estratégia de validação

1. Preservar evidências anteriores e limites em [validation.md](validation.md).
2. Validar requisitos, template, rastreabilidade e renderização com scripts CSTK.
3. Resolver conformidade da FASE 7 e reavaliar Constitution Check.
4. Obter opt-ins reais/revisar hooks em ambientes temporários; executar entrega funcional, retomada e aborto.
5. Conferir índice/proveniência, concluir revisão externa e atualizar aceite/matriz.

Descoberta/fixtures não certificam proteção em turno real. Revisão documental
standalone não cria estado/onda 00c nem grava no knowledge.db global.

## Complexity Tracking

| Violação | Por que surgiu | Alternativa a avaliar |
|----------|----------------|-----------------------|
| II: Python obrigatório fora do carve-out | Adaptador usa stdlib para transporte persistente/schema/instalação | Emenda delimitada aprovada ou redesenho POSIX; justificativa técnica não concede exceção. |
| III: Gotchas ausentes | Entradas entregues sem seção canônica | Completar seis skills e validar empacotamento. |
| I: ausência inicial de spec | Plano/backlog tratados como diário | Preservar histórico; próximos incrementos começam pela spec. |

O quadro registra conflitos, não aprova exceções a MUST.


## Incremento: visibilidade no painel — FR-019

Pedido do operador em 2026-10-02. Registrar execução retrospectiva, com
started_at do cadastro atual e zero ondas anteriores; preservar as escolhas
iniciais ainda pendentes. Preservar resultados documentados nos metadados,
não tempos/custos inventados. Helpers compartilhados permanecem fonte de verdade.
O schema exige uma onda real para `task_outcome.wave_id`; o registro retroativo
mantém o backlog em `retrospective_registration.documented_subtasks` e em
tasks.md, disponível na aba de documentos. Não importar outcomes com onda fictícia.

O painel atual aceita schema 2..15 e descobre apenas state.json. O incremento
aceita schema 16 aditivo e usa assinatura state.db + WAL para detectar commits
sem checkpoint; JSON mantém seu comportamento. Não abrir/escrever SQLite no
watcher: usar somente stat e delegar cstk recall --ingest. Tests do painel
cobrem regressões. O cadastro exige primeira ingestão no índice configurado;
visibilidade de painel já em execução depende de carregar o build atualizado.
Conflitos constitucionais anteriores permanecem abertos e não autorizam onda.
