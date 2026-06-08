# Data Model: cstk-plugins

Sem banco de dados. As "entidades" sao artefatos de filesystem (JSON files)
e um campo de `state.json`. Os tipos abaixo descrevem o SHAPE canonico de
cada artefato — a fonte da verdade para os contratos em `contracts/`.

## Entity: Plugin Manifest (`plugin-manifest.json`)

Arquivo na raiz do repositorio do plugin (`cstk-plugin-<name>`), produzido
pelo AUTOR do plugin. Lido e verificado pelo cstk no install/ativacao.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `name` | string | NOT NULL, match `^[a-z][a-z0-9-]{0,63}$` (FR-002); MUST igualar o sufixo do repo (`cstk-plugin-<name>`) | Identidade |
| `version` | string | NOT NULL, SemVer (`MAJOR.MINOR.PATCH`) | Versao do plugin |
| `type` | enum | `llm` \| `lang` (FR-003) | Informativo p/ display + roteamento futuro |
| `schema_version` | integer | NOT NULL, `>= 1`; rejeita se `> PLUGIN_SCHEMA_MAX` (=1) | Forward-compat (research D6) |
| `sha256` | string | NOT NULL, 64 hex chars | Checksum canonico do bundle, computado por `hash_dir` excluindo o proprio manifest (FR-003/FR-004) |
| `skills` | string[] | array de skill names; pode ser vazio | Skills providas/sobrescritas (FR-014) |
| `signature` | string | OPCIONAL, ignorado no MVP | Reservado p/ assinatura futura (research D2) |

### Exemplo

```json
{
  "name": "codex",
  "version": "1.2.0",
  "type": "llm",
  "schema_version": 1,
  "sha256": "3f2a...<64 hex>...e91c",
  "skills": ["specify", "plan", "clarify"]
}
```

### Validacao (ordem, fail-fast)

1. `name` casa `^[a-z][a-z0-9-]{0,63}$` E igual ao `<name>` solicitado.
2. `schema_version` <= `PLUGIN_SCHEMA_MAX` (senao "unsupported manifest version").
3. `type` ∈ {`llm`, `lang`}.
4. `version` casa SemVer.
5. `sha256` tem 64 chars hex.
6. checksum recomputado do bundle == `sha256` (FR-004 — gate de integridade).

## Entity: Plugin Store (diretorio)

Layout user-local. **`~/.claude/cstk/plugins/`** (namespace dedicado;
research D1 — desvia do default literal de FR-007 para evitar colisao com o
sistema nativo de plugins do Claude Code em `~/.claude/plugins/`).

```
~/.claude/cstk/plugins/
├── registry.json                 # indice (Entity: Plugin Registry)
└── <name>/                       # um dir por plugin instalado
    ├── plugin-manifest.json      # copia VERIFICADA do manifest
    └── skills/                   # bundle: skills providas pelo plugin
        └── <skill>/SKILL.md ...
```

### Invariantes

- Nunca escreve em `~/.claude/skills/` (FR-007 MUST).
- `<name>/` so existe se o checksum passou no install (FR-008 atomicidade:
  staging em tmp → move so apos verify).
- Remover um plugin = `rm -rf ~/.claude/cstk/plugins/<name>/` + remover a
  entrada do registry (FR-012).

## Entity: Plugin Registry (`registry.json`)

Indice leve em `~/.claude/cstk/plugins/registry.json`. Cacheia o estado
verificado para `plugin-list` rapido (SC-004) e lookup de ativacao sem
re-scan.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `schema_version` | integer | `>= 1` | Versao do formato do registry |
| `plugins` | object[] | array de entradas | Uma por plugin instalado |
| `plugins[].name` | string | match FR-002 | Chave natural |
| `plugins[].version` | string | SemVer | Do manifest verificado |
| `plugins[].type` | enum | `llm`\|`lang` | Do manifest |
| `plugins[].installed_at` | string | ISO 8601 UTC | Timestamp do install |
| `plugins[].bundle_sha256` | string | 64 hex | Checksum verificado no install (cache p/ status `ok` offline) |

### Exemplo

```json
{
  "schema_version": 1,
  "plugins": [
    {
      "name": "codex",
      "version": "1.2.0",
      "type": "llm",
      "installed_at": "2026-06-08T16:00:00Z",
      "bundle_sha256": "3f2a...e91c"
    }
  ]
}
```

### Status derivado (NAO persistido)

`plugin-list` calcula o status de integridade na hora:
- `ok` — registry presente; sem `--verify`, confia no `bundle_sha256` cacheado.
- `tampered` — com `--verify`, re-hash do bundle != `bundle_sha256` (FR US3-AS2).
- `unknown` — diretorio do plugin existe mas sem entrada no registry (ou
  vice-versa) — estado inconsistente.

## Entity: `--llm` em `state.json` (FR-016)

Campo ADITIVO no `state.json` da pipeline 00c. Gravado via o caminho de
escrita de estado EXISTENTE (sem nova infraestrutura — vide nota da spec
§Success Criteria).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `execution.llm_plugin` | string | default `"claude"` | Valor do `--llm`; `"claude"` = comportamento atual |

### State transitions / resume (FR-016)

```
init com --llm <name>  → execution.llm_plugin = "<name>"
init sem --llm         → execution.llm_plugin = "claude" (no behavior change, SC-003)
resume                 → le execution.llm_plugin; se != "claude":
                           - plugin nao instalado  → bloqueio humano
                           - integridade falha     → bloqueio humano (tampered)
                           - ok                    → re-ativa path-prepending
```

## Relationships

- `Plugin Manifest` 1:1 `Plugin Store/<name>/` — cada dir instalado guarda
  uma copia verificada do manifest.
- `Plugin Registry` 1:N `Plugin Store/<name>/` — o registry indexa todos os
  dirs instalados (`plugins[]`).
- `state.json.execution.llm_plugin` N:1 `Plugin Registry.plugins[].name` —
  uma execucao referencia (no maximo) um plugin pelo nome; `"claude"` = nenhum.
