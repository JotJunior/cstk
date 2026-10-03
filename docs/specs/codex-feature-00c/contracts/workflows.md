# Contracts: Workflows Codex 00c

**Fonte**: schemas TOOLS e Bridge.call em
`adapters/codex/skills/feature-00c/scripts/mcp-bridge.sh`; lifecycle.sh,
controller.sh, optins.sh e Session. Campos abaixo extraídos do código em
2026-10-02. Não são uma API proposta nem aliases de commands Claude.

## Entradas nativas

Seis skills: feature-00c, feature-00c-resume, feature-00c-abort, agente-00c,
agente-00c-resume, agente-00c-abort. Namespace observado em skills/list:
`cstk-codex-pilot:<nome>`. Seleção nativa pelo menu de skills; não há garantia
de slash alias curto. Sem ferramenta Skill/Agent presumida.

## Ferramentas no servidor cstk_pipeline

| Ferramenta | Campos obrigatórios | Campos opcionais |
|------------|---------------------|------------------|
| cstk_select_execution | `short_name`, `kind` | `project`, `knowledge_db` |
| cstk_context | nenhum | nenhum |
| cstk_bootstrap | `description`, `canonical_project` | `model` |
| cstk_optin | `value`, `channel`, `response_source` | `field` |
| cstk_open_wave | nenhum | nenhum |
| cstk_status | nenhum | nenhum |
| cstk_resume | nenhum | `block_id`, `answer`, `response_source`, `init_aspects`, `technical_aspects`, `operational_aspects` |
| cstk_abort | nenhum | `reason`, `purge_backups`, `abandoned_owner_pid` |
| cstk_handoff | `expected_runtime`, `response_source`, `rationale` | `model`, `abandoned_owner_pid` |
| cstk_reconcile_governance | `expected_hashes`, `response_source`, `rationale` | nenhum |
| cstk_decision | `context`, `options`, `choice`, `rationale` | `evidence`, `decision_class`, `axis`, `consent`, `score`, `references` |
| cstk_complete | `evidence_paths`, `rationale` | `used_sources` |
| cstk_pause | `instruction` | nenhum |
| cstk_block | `context`, `question`, `rationale` | `subject`, `options` |
| cstk_recover | nenhum | `abandoned_owner_pid` |

Schemas são objetos fechados (additionalProperties=false). Campos são
strings, exceto arrays de strings (options/references/evidence_paths/
used_sources/aspectos/expected_hashes), boolean purge_backups, integer score/
abandoned_owner_pid e value boolean|string. Validações semânticas ocorrem no
bridge/lifecycle/helpers, não apenas nos schemas.

## Regras de seleção, propriedade e retorno

- Seleção exige project absoluto na primeira chamada, kind feature|project e short_name kebab-case; knowledge_db, se informado, é absoluto. Servidor fica vinculado ao primeiro projeto até reiniciar. Seleção não cria estado.
- context é inspeção; bootstrap cria somente uma execução inexistente e não abre onda.
- optin exige resposta real e channel prose|structured; field default atomic_commit. Projetos também exigem roadmap_mode e delivery_tier (local|internal-network|cloud-internal|cloud-public).
- open_wave/resume devolvem descritor com stage, skill_path, phase_reference, wave_id e proprietário; mantêm lock entre chamadas. Sem bloco/terminal, resume abre a etapa persistida.
- resume com bloqueios retorna pending_blocks sem onda; answer tem 1..2000 caracteres e response_source identifica a resposta. Omitir block_id só se existe exatamente um bloqueio pendente.
- complete verifica evidence_paths relativos confinados, justificativa, fontes e gates; avança no máximo uma etapa. Continuar a pipeline é responsabilidade da sessão.
- pause/block fecham sem avanço; abort fecha como abortada e preserva artefatos. purge_backups exige pedido real. Estados terminais retornam resumed=false/aborted=false.
- handoff exige expected_runtime claude-code|unattributed, source e rationale; preserva execução. reconcile_governance exige briefing:<sha256> e constitution:<sha256> revisados e source real.
- recover não toma lock vivo; abandoned_owner_pid precisa coincidir com proprietário observado e comprovadamente morto.

Retorno MCP usa content com JSON textual e isError em falhas. Formatos
particulares de cada retorno são os emitidos pelo código; não se afirma um
payload uniforme além desse envelope observado. Chamadas RPC diretas não
certificam hooks de um turno de modelo.

## Fallback de terminal

controller.sh serve/resume mantém stdin/stdout JSONL persistente; ações são
decision, tick, block, pause, complete e abort. EOF/SIGTERM fecham sem avanço.
Scripts lifecycle.sh status/resume/abort/handoff/reconcile-governance têm os
mesmos gates; lifecycle resume prepara, controller resume abre onda.

## Caminho de estado e interoperabilidade

Um único state.db por execução, compartilhado entre executores mediante
handoff. Feature usa `.claude/feature-00c-state/<short_name>/`; projeto usa
`.claude/agente-00c-state/`. state-rw.sh escolhe SQLite pela presença do banco.
Não existe estado paralelo em .codex, nem sincronização de cópias. O layout
alternativo `.claude/feature-00c/**/state.db` não é descoberto automaticamente
no adaptador atual. Proveniência distingue executor; `.claude` no caminho
não atribui execução ao Claude.
