# Research: Pipeline CSTK no Codex

Inventário retrospectivo, alinhado ao template de plan. A revisão de
a implementação anterior tinha FAIL constitucional. O mantenedor escolheu
redesenho POSIX em 2026-10-03; resultados atuais em validation-posix.md.

## Decision 1: Repositório e fonte canônica

**Decision**: manter o mesmo repositório e branch; adaptador separado, helpers/templates compartilhados.
**Rationale**: operador escolheu branch nesta conversa; compartilhar regras preserva decisões e evita drift entre executores.
**Alternatives considered**: fork independente; duplicação do runtime. Não adotados no escopo pedido.
**Evidence**: AGENTS.md, adapters/codex/skills/feature-00c/SKILL.md e context.sh (descoberta do source_root).

## Decision 2: Pipeline supervisionada e propriedade

**Decision**: controlador possui lock durante uma onda; papéis semânticos executam na sessão atual.
**Rationale**: evita dois escritores e não presume ferramentas de agente, modelos ou scheduler inexistentes no host.
**Alternatives considered**: pipeline separada por executor; agendamento implícito. Não implementados.
**Evidence**: session.sh, controller.sh, mcp-bridge.sh e tests/codex/test_controller.sh.

## Decision 3: Conhecimento derivado e proveniência

**Decision**: JSON/SQLite canônicos; knowledge.db compartilhável, schema 16 com execution_provenance nullable.
**Rationale**: memória deve enriquecer/auditar sem transferir propriedade nem invalidar estado quando indisponível.
**Alternatives considered**: conhecimento como fonte de verdade; inferir executor/modelo de texto. Recusados.
**Evidence**: cli/lib/recall.sh, _state-rw-db.sh e tests/codex/test_knowledge.sh.

## Decision 4: Instalação nativa e hooks

**Decision**: plugin/MCP nativos; instalador mescla dois hooks na camada user e desativa os hooks redundantes no manifest instalado.
**Rationale**: diagnóstico do CLI 0.160.0 não listou hooks só pelo manifest. Comandos apontam ao pacote imutável por hash; confiança continua revisão humana.
**Alternatives considered**: presumir descoberta pelo manifest; confiar automaticamente. Não adotados.
**Evidence**: cli/lib/install-codex.sh, native-status.sh, logs de instalação/nativo em validation.md.
**Official source**: [Hooks](https://learn.chatgpt.com/docs/hooks), [Plugins](https://learn.chatgpt.com/docs/plugins). Nova sessão após instalar; revisão em /hooks.

## Decision 5: Contratos extraídos e evidência graduada

**Decision**: documentar schemas reais e distinguir unitários, descoberta nativa e uso semântico.
**Rationale**: Constitution VI proíbe assinatura ou resultado fabricado; RPC direto sem modelo não dispara hooks de turnos.
**Alternatives considered**: declarar 100% de suporte por fixtures; preencher opt-in com resposta de teste. Recusados.
**Evidence**: mcp-bridge.sh, native-mcp.sh, teste nativo e dogfood-session-2026-10-02.md.

## Decisão estrutural: redesenho POSIX

O mantenedor escolheu a reescrita em 2026-10-03, sem emenda. Shell/awk
implementam as fronteiras JSON, transporte, instalação e hooks; o runtime
compartilhado conserva seus helpers. A conformidade atual e os limites
observados são registrados em validation-posix.md. O conflito da implementação
anterior permanece documentado em review.md.
