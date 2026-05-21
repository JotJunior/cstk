# Data Model: Agente-00C

Modelo logico das entidades persistidas em disco. Implementacao em JSON
(arquivo unico, `state.json`) — nao ha banco de dados. Schema completo
serializado em `research.md` Decision 3 e `contracts/state-schema.md`.

---

## Entity: Execucao

Instancia unica de pipeline 00C invocada pelo operador.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | PK, formato `exec-<iso8601>-agente-00c-<slug>` | Auto-gerado no inicio |
| projeto_alvo_path | string | NOT NULL, absoluto | Diretorio onde tudo acontece |
| projeto_alvo_descricao | string | NOT NULL, min 10 chars | Argumento da invocacao |
| stack_sugerida | object \| null | Objeto com {linguagem, framework, banco, cache, filas} ou null se omitida | Quando null, clarify-answerer escolhe |
| status | enum | em_andamento \| aguardando_humano \| abortada \| concluida | Transicoes em "State Transitions" abaixo |
| motivo_termino | string \| null | Preenchido quando status sai de em_andamento | Ex: "etapa_concluida_avancando", "loop_em_etapa", "movimento_circular", "aborto_manual", "bug_skill_global", "concluida_com_sucesso" |
| iniciada_em | timestamp ISO8601 | NOT NULL | |
| terminada_em | timestamp ISO8601 \| null | Preenchido em status terminal | |

### Relationships

- Execucao 1:N Onda
- Execucao 1:N Decisao
- Execucao 1:N BloqueioHumano
- Execucao 1:1 EstadoOrquestracao (snapshot vivo)
- Execucao 1:1 Relatorio (gerado ao final)
- Execucao 1:N Sugestao
- Execucao 1:N Issue (subset de Sugestoes que viraram issues)

### State Transitions

```
em_andamento ──(bloqueio humano)──> aguardando_humano
em_andamento ──(gatilho de aborto)──> abortada
em_andamento ──(pipeline conclui)──> concluida
aguardando_humano ──(humano responde)──> em_andamento
aguardando_humano ──(operador desiste)──> abortada
abortada ──(terminal)──> X
concluida ──(terminal)──> X
```

---

## Entity: Onda

Unidade de execucao dentro de uma sessao do Claude Code. Comeca quando o
orquestrador acorda (manualmente ou via schedule), termina quando ele agenda
proxima onda ou conclui a pipeline.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | PK, formato `onda-NNN` (sequencial) | |
| execucao_id | string | FK -> Execucao.id | |
| inicio | timestamp ISO8601 | NOT NULL | Capturado via `date` no inicio |
| fim | timestamp ISO8601 \| null | Preenchido ao fechar onda | |
| etapas_executadas | string[] | Lista de etapas atravessadas nesta onda | |
| tool_calls | int | >= 0 | Contador incrementado pelo orquestrador |
| wallclock_seconds | int | Calculado fim - inicio | |
| motivo_termino | enum | etapa_concluida_avancando \| threshold_proxy_atingido \| bloqueio_humano \| aborto \| concluido | |
| proxima_onda_agendada_para | timestamp ISO8601 \| null | Quando aplicavel | |

### Relationships

- Onda N:1 Execucao
- Onda 1:N Decisao (decisoes tomadas durante esta onda)

---

## Entity: EstadoOrquestracao (snapshot vivo)

Snapshot persistido em disco entre ondas. UM por execucao corrente — sobrescrito
a cada onda; copia historica em `state-history/<onda-id>.json`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| schema_version | string | NOT NULL, formato SemVer | Exigido para validacao na retomada |
| execucao_id | string | FK -> Execucao.id | |
| etapa_corrente | enum | briefing \| constitution \| specify \| clarify \| plan \| checklist \| create-tasks \| execute-task \| review-task \| review-features | |
| proxima_instrucao | string | NOT NULL, min 20 chars | Texto explicito do que executar na proxima onda |
| profundidade_corrente_subagentes | int | 0..3 | Tracker de niveis aninhados |
| retro_execucoes_consumidas | int | 0..2 | Por feature corrente |
| ciclos_consumidos_etapa_corrente | int | 0..5 | Resetado ao mudar de etapa |
| tool_calls_onda_corrente | int | >= 0 | Resetado ao iniciar onda |
| inicio_onda_corrente | timestamp ISO8601 | NOT NULL durante onda | Para computar wallclock |
| whitelist_urls_externas | string[] | Snapshot do arquivo de whitelist + .env | Re-lido a cada inicio de onda |
| historico_movimento_circular | object[] | Buffer deslizante (max 6) de pares (problema, solucao) hashed | Para deteccao de fix-A-quebra-B |

### Constraints

- `schema_version` desconhecido = bloqueio obrigatorio (FR-008)
- `proxima_instrucao` vazia ou ausente = estado invalido = bloqueio
- `profundidade_corrente_subagentes > 3` = invariante violada = aborto

---

## Entity: Decisao

Unidade audit-relevante. Toda escolha do orquestrador ou subagente vira uma
decisao — Principio I (Auditabilidade Total).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | PK, formato `dec-NNN` (sequencial dentro da execucao) | |
| execucao_id | string | FK -> Execucao.id | |
| onda_id | string | FK -> Onda.id | |
| timestamp | timestamp ISO8601 | NOT NULL | |
| etapa | enum | mesma lista de EstadoOrquestracao.etapa_corrente | |
| agente | string | NOT NULL | "orquestrador-00c", "clarify-asker", "clarify-answerer", "executor-task-NNN", etc |
| contexto | string | NOT NULL, min 20 chars | Resumo do problema/situacao em que a decisao foi tomada |
| opcoes_consideradas | string[] | NOT NULL, min 1 item | |
| escolha | string | NOT NULL | Uma das opcoes consideradas, OU "pause-humano" se converteu em bloqueio |
| justificativa | string | NOT NULL, min 20 chars | Cita briefing/constitution/stack quando aplicavel |
| score_justificativa | int 0..3 \| null | Aplicavel a decisoes do clarify-answerer | Ver research.md Decision 6 |
| referencias | string[] | URLs ou paths relativos | Ex: ["briefing.md#3.MVP", "constitution.md#principio-V"] |
| artefato_originador | string \| null | Path relativo do artefato que originou a decisao | Ex: "spec.md", "plan.md" |

### Relationships

- Decisao N:1 Execucao
- Decisao N:1 Onda

### Subtipos por agente

- **Orquestrador**: decisoes de avancar/recuar etapa, spawnar subagente,
  abortar, agendar.
- **Clarify-asker**: decisoes sobre quais perguntas levantar (raras —
  geralmente uma decisao por chamada do asker).
- **Clarify-answerer**: decisoes sobre opcoes (sempre com `score_justificativa`).
- **Executor-task**: decisoes durante execucao de uma task especifica.

---

## Entity: BloqueioHumano

Tipo especial de Decisao que paralisa a pipeline. Modelado como entidade propria
porque tem ciclo de vida (aguardando -> respondido) que Decisao normal nao tem.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | PK, formato `block-NNN` | |
| execucao_id | string | FK -> Execucao.id | |
| decisao_id | string | FK -> Decisao.id | A decisao que disparou o bloqueio |
| pergunta | string | NOT NULL, min 20 chars | Pergunta clara para o humano |
| contexto_para_resposta | string | NOT NULL | Tudo que o humano precisa para responder sem releitura de artefatos |
| opcoes_recomendadas | string[] \| null | Quando o asker conseguiu gerar opcoes | |
| status | enum | aguardando \| respondido \| desistido | |
| resposta_humana | string \| null | Preenchido quando status = respondido | |
| respondido_em | timestamp ISO8601 \| null | | |
| disparado_em | timestamp ISO8601 | NOT NULL | |

### Relationships

- BloqueioHumano N:1 Execucao
- BloqueioHumano 1:1 Decisao (a que originou)

---

## Entity: Sugestao (para skill global)

Registro de melhoria proposta a alguma skill em `~/.claude/skills/`. Persiste
em `<projeto-alvo>/.claude/agente-00c-suggestions.md` (markdown human-readable),
mas o modelo logico aqui descreve o conteudo.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | PK, formato `sug-NNN` | |
| execucao_id | string | FK -> Execucao.id | |
| skill_afetada | string | NOT NULL | Nome da skill (ex: "clarify", "plan") |
| diagnostico | string | NOT NULL, min 50 chars | O que foi observado de errado/melhoravel |
| severidade | enum | informativa \| aviso \| impeditiva | impeditiva => abre issue |
| proposta | string | NOT NULL | Mudanca concreta sugerida |
| referencias | string[] | Paths relativos | Quais artefatos da execucao evidenciam |
| issue_aberta | string \| null | Numero/URL da issue no toolkit, se severidade=impeditiva | |

### Relationships

- Sugestao N:1 Execucao
- Sugestao 0..1:1 Issue (somente impeditivas viram Issue)

---

## Entity: Issue (no toolkit GitHub)

Subset materializado de Sugestao. Aberta automaticamente quando severidade=impeditiva.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| id | string | PK, formato `issue-NNN` | |
| sugestao_id | string | FK -> Sugestao.id | |
| repo | string | NOT NULL, default "JotJunior/claude-ai-tips" | |
| numero_remoto | int \| null | Preenchido apos `gh issue create` retornar | |
| url_remoto | string \| null | URL completa | |
| titulo | string | NOT NULL, formato "[agente-00C] Bug em <skill>: <resumo>" | |
| corpo | string | NOT NULL | Markdown seguindo template de `contracts/issue-template.md` |
| criada_em | timestamp ISO8601 | NOT NULL | |

### Relationships

- Issue 1:1 Sugestao

---

## Entity: Relatorio

Artefato de saida final em `<projeto-alvo>/.claude/agente-00c-report.md`. Tem
6 secoes fixas (definidas em `research.md` Decision 10 e `contracts/report-format.md`).

Modelo logico no estado pode ser representado como:

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| execucao_id | string | FK -> Execucao.id | |
| versao | string | Default "1.0.0" | Schema do relatorio |
| gerado_em | timestamp ISO8601 | NOT NULL | |
| status_no_momento_da_geracao | enum | Mesma de Execucao.status | Pode ser "abortada" para relatorio parcial |
| secoes_obrigatorias_presentes | string[] | Verificavel por SC-001 | Ex: ["resumo_executivo", "linha_do_tempo", "decisoes", "bloqueios", "sugestoes", "licoes"] |

Note: o relatorio em si **nao e persistido como entidade** no estado JSON —
o estado tem todos os dados, e o relatorio e renderizado em markdown sob demanda.
A entidade aqui serve como contrato de "o que tem que estar la".
