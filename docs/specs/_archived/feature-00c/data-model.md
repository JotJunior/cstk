# Data Model: Feature-00C

Documento Phase 1 do `/plan`. Modela as entidades persistidas (filesystem
local) e suas relacoes. Sem banco de dados — tudo e arquivo JSON ou
markdown sob `<projeto-alvo>/.claude/feature-00c-state/<short-name>/`.

---

## Entity: Execucao-de-feature

Representa uma instancia de pipeline `/feature-00c` em um projeto-alvo,
para uma feature especifica (identificada por `short_name`).

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `id` | string (ULID) | sim | gerado na invocacao; estavel ate o fim |
| `short_name` | string (kebab-case) | sim | identificador da feature (espelha `docs/specs/<short_name>/`) |
| `projeto_alvo_path` | string (path absoluto) | sim | resolvido via realpath na invocacao |
| `descricao_curta` | string (<= 500 chars) | sim | passada pelo operador; sanitizada |
| `status` | enum | sim | `em_andamento` \| `aguardando_humano` \| `abortada` \| `concluida` |
| `motivo_termino` | string | nao | obrigatorio quando status != `em_andamento` |
| `iniciada_em` | ISO 8601 | sim | timestamp UTC |
| `terminada_em` | ISO 8601 | nao | preenchido em status terminal |

**State transitions**:

```
[invocacao]
   ↓
em_andamento ──→ aguardando_humano ──→ em_andamento (apos resume)
   │                   │
   │                   ↓
   ↓               abortada
concluida           ↑
   │                │
   └────────────────┘ (aborto a partir de qualquer estado nao-terminal)
```

Estados terminais: `concluida`, `abortada`. Status `aguardando_humano`
e bloqueante mas reversivel via `/feature-00c-resume`.

---

## Entity: Onda

Unidade de execucao dentro de uma sessao do Claude Code. Multiplas
ondas formam uma execucao completa.

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `numero` | int (monotonico) | sim | wave-001, wave-002, ... |
| `iniciada_em` | ISO 8601 | sim | |
| `terminada_em` | ISO 8601 | sim ao final | |
| `fase_inicial` | string | sim | fase em que a onda comecou |
| `fase_final` | string | sim ao final | fase em que terminou |
| `tool_calls` | int | sim | contador da onda |
| `wallclock_segundos` | int | sim ao final | |
| `decisoes_registradas` | array<id> | sim | ids das decisoes geradas |
| `skills_invoked` | array<{skill, timestamp}> | sim | espelhando `project_agente00c_skills_tracking` |
| `proxima_instrucao` | string | sim | instrucao serializada para a proxima onda |
| `motivo_fim` | enum | sim | `threshold_atingido` \| `bloqueio_humano` \| `aborto` \| `concluido` |

Ondas sao append-only — uma onda finalizada nao e modificada
retroativamente. Toda mudanca de estado posterior vira nova onda.

---

## Entity: Estado de Orquestracao (`state.json`)

Snapshot persistido em
`<projeto-alvo>/.claude/feature-00c-state/<short_name>/state.json`.
Contem TUDO necessario para retomada cross-sessao.

```json
{
  "schema_version": "1.0.0",
  "execucao": {
    "id": "01HXYZ...",
    "short_name": "user-auth",
    "projeto_alvo_path": "/home/jot/Projects/myapp",
    "descricao_curta": "Adicionar login via email/senha",
    "descricao_aspectos_chave": ["autenticacao", "email", "senha", "login"],
    "status": "em_andamento",
    "motivo_termino": null,
    "iniciada_em": "2026-05-20T14:00:00Z",
    "terminada_em": null
  },
  "pre_requisitos": {
    "briefing": {
      "path": "docs/01-briefing-discovery/briefing.md",
      "sha256": "abc123..."
    },
    "constitution": {
      "path": "docs/constitution.md",
      "sha256": "def456...",
      "version": "1.1.0"
    }
  },
  "pipeline": {
    "fase_corrente": "execute-task",
    "fases_concluidas": ["specify", "clarify", "plan", "checklist", "create-tasks"],
    "retros_consumidas": 0,
    "ciclos_por_fase": {"specify": 1, "clarify": 2, "plan": 1, "execute-task": 3}
  },
  "execute_task_progress": {
    "tasks_concluidas": ["T001", "T002", "T003"],
    "task_corrente": "T004"
  },
  "ondas": [
    {
      "numero": 1,
      "iniciada_em": "2026-05-20T14:00:00Z",
      "terminada_em": "2026-05-20T14:42:00Z",
      "fase_inicial": "specify",
      "fase_final": "clarify",
      "tool_calls": 47,
      "wallclock_segundos": 2520,
      "decisoes_registradas": ["dec-001", "dec-002"],
      "skills_invoked": [
        {"skill": "specify", "timestamp": "2026-05-20T14:01:00Z"},
        {"skill": "clarify", "timestamp": "2026-05-20T14:25:00Z"}
      ],
      "proxima_instrucao": "Continue clarify; 2 perguntas pendentes",
      "motivo_fim": "threshold_atingido"
    }
  ],
  "subagent_depth_atual": 1,
  "decisoes": [/* array de Decisao */],
  "bloqueios_humanos": [/* array de BloqueioHumano */],
  "configuracao": {
    "whitelist_urls_adicionais": [],
    "skills_aliases": {}
  }
}
```

**Schema versioning**: `schema_version` segue SemVer. Mudancas
compativeis = MINOR (orquestrador le ambos); incompativeis = MAJOR
(bloqueio com diagnostico de migracao). Hoje: `1.0.0`.

---

## Entity: Decisao

Unidade audit-relevante registrada em `state.json` (campo `decisoes`).
Cinco campos obrigatorios + 4 auxiliares.

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `id` | string | sim | `dec-NNN`, monotonico |
| **`contexto_fase`** | string | sim | fase ativa quando a decisao foi tomada |
| **`opcoes_consideradas`** | array<string> | sim | min 1; respostas multi-choice ou alternativas |
| **`escolha_feita`** | string | sim | uma das opcoes |
| **`justificativa`** | string | sim | razao em termos de briefing/constitution/spec |
| **`agente_responsavel`** | string | sim | `agente-00c-feature-orchestrator`, `feature-00c-clarify-answerer`, etc |
| `timestamp` | ISO 8601 | sim | sempre obrigatorio |
| `score_justificativa` | int (0..3) | condicional | obrigatorio para clarify-answerer |
| `referencias` | array<string> | condicional | `>= 1` quando justifica cita briefing/constitution/spec |
| `artefato_originador` | string (path) | nao | quando aplicavel |
| `kind` | enum | nao | tipo da Decisao para auditoria por `/review-task`. Valores: `clarify-answer`, `phase-transition`, `gate-finding`, `gate_skipped`, `human-block-resolved`, `manual-abort`. Default = `clarify-answer` quando ausente |

Decisao com qualquer dos 5 obrigatorios faltando = violacao de
Principio I (auditabilidade) e bloqueio.

**Valores de `kind` adicionados pela §"Quality Gates complementares"
do agente-00c-feature-orchestrator** (alinhamento com PR #6 do
toolkit):
- `gate-finding`: Decisao registrando finding `critical`/`high` de um
  gate (`validate-documentation`, `owasp-security`,
  `validate-docs-rendered`). Escolha tipica: `aceitar-risco-com-justificativa`,
  `corrigir-agora`, `escalar-para-humano`.
- `gate_skipped`: Decisao registrando skip auditavel de um gate
  (escolha = `skip-com-justificativa`). `/review-task` audita
  features com >2 skips sem justificativa solida como
  `quality-gate-bypass`.

---

## Entity: BloqueioHumano

Tipo especial de Decisao que paralisa a pipeline ate intervencao do
operador.

| Campo | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `id` | string | sim | `blq-NNN` |
| `pergunta` | string | sim | o que precisa de resposta humana |
| `contexto` | string | sim | suficiente para resposta sem reler artefatos |
| `opcoes_sugeridas` | array<string> | nao | apresentadas no relatorio parcial |
| `status` | enum | sim | `aguardando` \| `respondido` |
| `resposta_humana` | string | nao | preenchida via `/feature-00c-resume --resposta-bloqueio` |
| `respondido_em` | ISO 8601 | nao | |
| `decisao_resultante_id` | string | nao | id da Decisao gerada apos resposta |

**Lifecycle**: criado com `aguardando` → operador responde via resume →
status vira `respondido` + cria-se uma Decisao referente. Bloqueios
nao sao removidos do array; ficam para audit.

---

## Entity: Backup por Onda (`backups/wave-NNN.json`)

Snapshot do state.json ao final de cada onda. Filtrado por
secrets-filter.sh antes da gravacao (Decision 6 do research).

```json
{
  "wave_number": 7,
  "captured_at": "2026-05-20T15:42:00Z",
  "state_sha256_self": "ghi789...",
  "state_snapshot": { /* state.json filtrado */ }
}
```

Hash auto-registrado (`state_sha256_self`) e calculado sobre o conteudo
filtrado do `state_snapshot`, NAO sobre o state.json operacional. Permite
detectar corrupcao retroativa.

Retencao: TODAS as ondas (decisao do `/clarify`). Limpeza so via
`/feature-00c-abort --purge-backups`.

---

## Entity: Relatorio (`feature-00c-report.md`)

Markdown gerado ao final de qualquer execucao (sucesso, aborto, pausa).
Conteudo detalhado em `contracts/report-format.md`.

**Localizacao**:
`<projeto-alvo>/.claude/feature-00c-state/<short_name>/feature-00c-report.md`

**Estrutura**: 6 secoes em ordem fixa (FR-018):
1. Resumo Executivo
2. Linha do Tempo
3. Decisoes
4. Bloqueios Humanos
5. Sugestoes para Skills Globais
6. Licoes Aprendidas

Filtrado por `secrets-filter.sh` antes de gravar.

---

## Entity: Sugestao para Skill Global

Append-only em `<projeto-alvo>/.claude/feature-00c-suggestions.md`.
Compartilhado entre execucoes de features distintas no mesmo projeto.

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | `sug-NNN` | monotonico no arquivo |
| `feature_origem` | string | short_name da feature que originou |
| `skill_afetada` | string | nome da skill |
| `severidade` | enum | `informativa` \| `aviso` \| `impeditiva` |
| `diagnostico` | string | o que aconteceu |
| `proposta` | string | sugestao de melhoria |
| `link_relatorio` | string | path para feature-00c-report.md que originou |
| `criada_em` | ISO 8601 | |

Severidade `impeditiva` dispara abertura automatica de issue no toolkit
(FR-029 + agente-00c FR-021 herdado).

---

## Entity: Issue no Toolkit

Criada via `gh issue create` em `JotJunior/cstk` quando
severidade da sugestao = `impeditiva`. Template estruturado herdado
do agente-00c.

| Campo | Tipo | Notas |
|-------|------|-------|
| `numero` | int | retornado por `gh` |
| `url` | string | https URL |
| `template_section_skill` | string | skill afetada |
| `template_section_diagnostico` | string | filtrado por secrets-filter |
| `template_section_proposta` | string | filtrado por secrets-filter |
| `link_relatorio_sanitizado` | string | path local (NAO upload do relatorio) |

Filtros de secrets aplicados em diagnostico + proposta antes da chamada
ao `gh`.

---

## Relacionamentos

```
Execucao 1 ──< * Onda
Execucao 1 ──< * Decisao
Execucao 1 ──< * BloqueioHumano
Execucao 1 ──< 1 Relatorio
Execucao 1 ──< * Backup
Execucao 1 ──< * Sugestao  (sugestoes podem ser compartilhadas no projeto)
Sugestao(severidade=impeditiva) 1 ──< 0..1 Issue

BloqueioHumano 1 ──< 0..1 Decisao  (gerada quando respondido)
```

---

## Invariants

1. **Auditabilidade**: nenhuma Decisao sem os 5 campos obrigatorios.
2. **Append-only**: ondas, decisoes, bloqueios sao append-only —
   nunca editar retroativamente.
3. **Hash integrity**: `state.json.sha256` sempre sincronizado com
   `state.json` ao final da onda.
4. **Namespace isolation**: tudo da feature-00c vive sob
   `feature-00c-state/<short_name>/`, exceto suggestions (compartilhada
   no projeto).
5. **Backup parity**: para cada onda registrada em `state.ondas[]`,
   existe `backups/wave-NNN.json` correspondente.
6. **Secrets-free output**: report.md, suggestions.md, backup files e
   issue body sao filtrados antes da gravacao/envio. State.json
   operacional NAO e filtrado.
