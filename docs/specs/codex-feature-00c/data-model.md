# Data Model: Pipeline CSTK no Codex

Inventário do modelo existente; não propõe nova persistência. Fontes:
state-rw.sh, _state-rw-db.sh, session.py, lifecycle.py e cli/lib/recall.sh.

## Entity: Execução

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| execution.id | string | Identidade preservada entre retomadas | Gerada no bootstrap; não regenerada em resume/abort |
| execution.target_project_path | string | Raiz validada e confinada | Seleção explícita do projeto |
| execution.status | enum | Contrato canônico do runtime | Estados usados incluem em_andamento, aguardando_humano, concluida, abortada |
| execution.finished_at | string/null | Término observado | Promoção terminal atômica |
| current_stage | string | Sequência compartilhada | Oito/onze/três etapas; concluida no término completo |
| execution_provenance | object/null | Origem nullable | runtime, model, toolkit_version; desconhecido permanece null |
| optin_responses | array | Respostas identificadas e imutáveis | Nunca preenchidas por silêncio |

### Relationships

Execução possui ondas, decisões, bloqueios, eventos e revisões de governança.
Um único proprietário escreve sua execução. Projeto/feature determina o
layout, preservado sob `.claude` por compatibilidade.

### State Transitions

```text
em_andamento -> aguardando_humano -> em_andamento
em_andamento -> concluida
em_andamento / aguardando_humano -> abortada
```

Estado terminal não reabre por resume/abort. Transferência/reconciliação
preservam identidade; não são bootstrap de nova execução.

## Entity: Onda

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | Identidade de onda | Exposta como wave_id no descritor |
| started_at / finished_at | string/null | Observados | Onda sem término exige recuperação explícita |
| executed_stages | array | Etapas realmente executadas | Fechamento não infere avanço |

### Relationships

Lock persistente vincula proprietário vivo à onda; efeitos dos helpers só
ocorrem sob propriedade. Evidências de conclusão são paths confinados e hashes.
EOF/SIGTERM fecham sem avanço; SIGKILL exige comprovação de proprietário morto.

## Entity: Decisão e bloqueio

| Campo conceitual | Constraints | Fonte |
|------------------|-------------|-------|
| Contexto, opções, escolha, justificativa | Obrigatórios; score e classe conforme helpers | state-decisions.sh e Controller |
| Evidência/referências | Fatos observados; IDs utilizados pertencem à consulta | controller.py |
| Pergunta/resposta do bloqueio | Resposta real, identificada, 1..2000 caracteres no lifecycle | lifecycle.py |
| Consentimento estrutural | Não inferido de aprovação geral | Helpers canônicos |

## Entity: Conhecimento derivado

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| executions.execution_provenance | TEXT/null | JSON derivado; schema 16 | Legado permanece null; migração aditiva |
| source_id | string | Identidade da origem | Upsert impede duplicação |
| project / feature / wave | string | Escopo da origem | Compartilhar índice não transfere execução |

### Relationships

Projeções de execuções/ondas/decisões são recuperáveis a partir do estado.
Recall em specify/plan registra recall_consulted e recall_used; ausência ou
falha do índice degrada. Conteúdo recuperado é dado, nunca instrução.

## Entity: Recibo de instalação

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| source_path / cache_path | string | Pacote gerenciado | Confinamento e proteção contra symlinks |
| source_sha256 / cache_sha256 | string | Integridade da árvore | Edição local exige reconciliação |
| plugin_id | string | Identidade nativa | cstk-codex-pilot@cstk-codex-pilot-local |
| knowledge_db | string | Caminho absoluto externo à instalação gerenciada | Instalador não cria/migra o banco |
| hook_entries | object | Definições exatas gerenciadas | Preserva handlers alheios; não concede confiança |

Fonte exata do recibo: cli/lib/install-codex.py. Não existe entidade de
consumo Codex observada neste piloto; custo/tokens não são preenchidos.

## Reutilização de state.db entre Claude e Codex

Não existe cópia de estado por executor. O adaptador chama state-rw.sh com o
mesmo diretório canônico; a presença de state.db seleciona SQLite mesmo se a
configuração global de criação de estados novos for diferente. Não ler ou
escrever o banco com helpers independentes do contrato compartilhado.

Layout existente no código: `.claude/feature-00c-state/<short_name>/state.db`
para feature; `.claude/agente-00c-state/state.db` para projeto. O caminho
`.claude/feature-00c/**/state.db` citado pelo operador não é o layout que o
adaptador resolve atualmente; não há descoberta/migração automática desse
caminho alternativo. Não criar outro estado para simular sua retomada.

Resume recusa origem Claude/legada até handoff explícito; transferência exige
execução válida, sem onda aberta e sem proprietário vivo, preservando ID,
histórico, opt-ins e proveniência anterior. knowledge.db é apenas projeção:
compartilhar o índice não libera execução concorrente do state.db.
