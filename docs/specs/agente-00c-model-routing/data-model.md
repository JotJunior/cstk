# Data Model: agente-00c model-routing

A feature NAO introduz novas tabelas, novos arquivos de estado ou
novos schemas. Ela ESCREVE em estruturas ja existentes no
`state.json` mantido pelos orquestradores `agente-00c` /
`feature-00c`. Este documento descreve as 3 entidades-chave da spec
no formato com que sao persistidas.

## Entity: Decisao de selecao de modelo

Persistida em `state.json` no array `.decisoes[]`, gerenciado por
`~/.claude/skills/agente-00c-runtime/scripts/state-decisions.sh
register`. Formato canonico ja definido pelo schema do `agente-00c-runtime`
— esta feature apenas adota convencoes especificas nos campos.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `id` | string | PK; pattern `^dec-[0-9]{3}$` | Auto-incrementado por `state-decisions.sh` |
| `agente` | string | NOT NULL | `agente-00c-orchestrator` ou `agente-00c-feature-orchestrator` |
| `etapa` | string | NOT NULL | `clarify` (unica etapa que spawna hoje) |
| `onda_id` | string | NOT NULL | `onda-NNN` da onda corrente |
| `contexto` | string | NOT NULL; pattern fixo | `^Selecao de modelo para subagente (?<subagent_type>[a-z0-9-]+)( .*)?$` |
| `opcoes` | JSON array of string | NOT NULL; cardinality 5 | `["haiku","sonnet","opus","manter-atual","fallback-default"]` |
| `escolha` | string | NOT NULL; enum | `haiku` \| `sonnet` \| `opus` \| `manter-atual` \| `fallback-default` |
| `justificativa` | string | NOT NULL; len >= 20 | Inclui sinais literais da skill (FR-006) + nota de truncagem se aplicavel (FR-013) |
| `score` | integer | NOT NULL; 0..3 | Mapeado de score 0..2 da skill via tabela FR-005 |
| `timestamp` | string | NOT NULL; ISO-8601 UTC | Auto-set por `state-decisions.sh` |
| `evidencia` | string | obrigatorio quando score=3; len >= 20 | Trecho literal do bloco `## Sinais detectados` da skill |

### Pattern do campo `contexto`

Formato exato, validado por jq matcher em FR-018:

```
Selecao de modelo para subagente <subagent_type>
```

onde `<subagent_type>` e um dos:

- `agente-00c-clarify-asker`
- `agente-00c-clarify-answerer`
- `feature-00c-clarify-asker`
- `feature-00c-clarify-answerer`

Sufixo opcional apos `<subagent_type>` permite anotacao livre (ex:
`... [truncado 2000+marker+2000]`) sem quebrar a busca via
`startswith`.

### Invariantes

- **Uniqueness**: para um par `(onda_id, subagent_type)`, existe NO
  MAXIMO 1 Decisao registrada (FR-012 — idempotencia em retomadas).
- **Score-evidencia coupling**: `score == 3` IMPLICA
  `length(evidencia) >= 20`; trava enforced por `state-decisions.sh`.
- **Fallback-default semantica**: `escolha == "fallback-default"`
  IMPLICA `score == 0` (FR-008) e `justificativa` contendo prefix
  `fallback:` + razao + ate 200 chars de stderr.

### Relationships

- **Decisao 1:1 Registro de skill invocada**: cada Decisao de selecao
  de modelo tem exatamente 1 entrada correspondente em
  `.ondas[N].skills_invoked[]` referenciando seu `id` (FR-004).

## Entity: Registro de skill invocada

Persistida em `state.json` no array `.ondas[<onda_corrente>].skills_invoked[]`,
gerenciado por `state-ondas.sh record-skill`. Formato ja canonico —
feature apenas usa.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `skill` | string | NOT NULL; enum-like | Valor fixo `"model-selector"` para esta feature |
| `decisao_id` | string | NOT NULL; FK | Referencia o `.id` da Decisao correspondente (formato `dec-NNN`) |
| `timestamp` | string | NOT NULL; ISO-8601 UTC | Auto-set por `state-ondas.sh` |

### Relationships

- **Registro N:1 Onda**: muitos registros pertencem a 1 onda; onda
  e identificada implicitamente pelo path
  `.ondas[<index>].skills_invoked`.
- **Registro 1:1 Decisao**: cada `decisao_id` aparece UMA vez por
  onda no `skills_invoked[]` (sem duplicacao).

## Entity: Template de input por subagent_type

Catalogo deterministico INLINE em
`~/.claude/skills/agente-00c-runtime/scripts/model-routing.sh`. NAO
persistido em estado mutavel — vive no codigo-fonte do helper. Cada
release do toolkit (cstk update) propaga mudancas no catalogo.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `subagent_type_suffix` | string | enum (case do shell) | `asker` ou `answerer` |
| `template_text` | string | <= 1024 chars (margem para 4096) | Formato: `<perfil>. <entradas esperadas>. <saida esperada>.` |
| `version` | implicito (git) | versionado via SemVer do toolkit | Mudancas no template = BREAKING se alterarem classificacao previa |

### Conteudo do catalogo (referencia)

Templates exatos sao codigo-fonte (definidos em
`model-routing.sh template --subagent-type T`):

```
# Pseudocodigo do helper:
case "$subagent_suffix" in
  asker)
    cat <<'EOF'
enumerative scan of spec for ambiguities producing up to 5 questions.
inputs: spec text, briefing summary, constitution principles.
output: JSON list of questions referencing FR/edge case ids.
EOF
    ;;
  answerer)
    cat <<'EOF'
reflective resolution of ambiguity questions against briefing and
constitution producing scored answers.
inputs: question batch + briefing + constitution + spec + prior decisions.
output: JSON list of answers with score and pause-humano flag.
EOF
    ;;
esac
```

### State Transitions

N/A — entidade imutavel em runtime. Mudancas exigem release nova
do toolkit + bump de versao + nota em CHANGELOG.
