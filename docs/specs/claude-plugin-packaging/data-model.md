# Data Model: Empacotamento do cstk como Plugin do Claude Code

> **Regra de veracidade aplicada (Constitution VI)**: os nomes de campo
> abaixo estao classificados. `[REAL]` = observado em arquivo real no
> ambiente (fontes S1-S6 de `research.md`). `[PROPOSTA]` = artefato novo
> que esta feature vai criar, a validar na implementacao. Nenhum campo de
> plataforma foi suposto.

## Entity: Plugin Manifest `[REAL — schema; PROPOSTA — valores do cstk]`

Arquivo: `plugins/<plugin>/.claude-plugin/plugin.json`

Schema observado em manifestos oficiais (S2) e no uso do marketplace (S1).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `name` | string | **obrigatorio** | Identificador do plugin. Valores desta feature: `cstk`, `cstk-language-go` |
| `description` | string | opcional | Presente em `plugin-dev` (S2) |
| `author` | object | opcional | `{name, email}` — forma observada em S2 |
| `version` | string | **opcional** | Observado como chave de entrada de marketplace (S1). NAO e fonte confiavel de alinhamento — ver `Installation Alignment Report` |

**Campos deliberadamente NAO declarados**: o formato define diretorios
convencionais na raiz do plugin (`skills/`, `commands/`, `agents/`,
`hooks/`, S8). Os manifestos reais inspecionados (S2, ex. `plugin-dev`)
**nao enumeram** esses diretorios no JSON — a descoberta e por convencao de
layout. Declarar um campo de "entry points" seria inventar schema.

## Entity: Marketplace Listing `[REAL]`

Arquivo: `.claude-plugin/marketplace.json` (raiz do repo cstk)

Schema observado em S1 (marketplace oficial da Anthropic, 284 entradas).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `$schema` | string | opcional | Presente em S1 |
| `name` | string | obrigatorio | Nome do marketplace. Valor: `cstk` |
| `owner` | object | obrigatorio | `{name, email}` (S1) |
| `description` | string | opcional | |
| `plugins` | array | obrigatorio | **Exatamente 2 entradas** (FR-003) |

### Sub-entity: `plugins[]` `[REAL]`

Chaves observadas em uso real (S1): `name`, `description`, `author`,
`category`, `source`, `homepage`, `version`, `displayName`, `keywords`,
`tags`, `strict`, `skills`, `lspServers`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `name` | string | obrigatorio | `cstk` \| `cstk-language-go` |
| `description` | string | obrigatorio na pratica | Presente em 100% das entradas de S1 |
| `author` | object | opcional | |
| `source` | string \| object | obrigatorio | **Ver formas abaixo** |
| `category` | string | opcional | Valores observados em S1: `security`, `design`, `development` |
| `version` | string | opcional | Em lockstep com a tag SemVer (FR-003) |
| `homepage` | string | opcional | |

**Formas de `source` observadas em S1** (todas reais):

| Forma | Estrutura | Uso |
|-------|-----------|-----|
| String relativa | `"./plugins/agent-sdk-dev"` | Plugin no **proprio repo** do marketplace — **forma escolhida por esta feature** |
| `git-subdir` | `{source, url, path, ref, sha}` | Plugin em repo de terceiro, subdiretorio |
| git raiz | `{source, url, sha}` | Plugin em repo de terceiro, raiz |
| github | `{source:"github", repo, commit, sha}` | Referencia por owner/repo |

Valores desta feature: `"./plugins/cstk"` e `"./plugins/cstk-language-go"`.

## Entity: Hooks Registration `[REAL — schema]`

Arquivo: `plugins/cstk/hooks/hooks.json`

Schema observado em S3 (`hookify`, `claude-security`, `ralph-loop`).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `description` | string | opcional | Presente em S3 |
| `hooks` | object | obrigatorio | Mapa `<EventName> -> array` |
| `hooks.<Event>[].matcher` | string | opcional | Regex/glob. Ausente = todos |
| `hooks.<Event>[].hooks[].type` | string | obrigatorio | Valor observado: `"command"` |
| `hooks.<Event>[].hooks[].command` | string | obrigatorio | Comando de shell; usa `${CLAUDE_PLUGIN_ROOT}` |
| `hooks.<Event>[].hooks[].timeout` | number | opcional | Segundos. Observado: `10` (S3); classico cstk usa `5` (S7) |

### Mapeamento classico → plugin

| Evento | Matcher | Command classico `[REAL S7]` | Command plugin `[PROPOSTA]` |
|--------|---------|------------------------------|------------------------------|
| `PreToolUse` | `Bash` | `"$CLAUDE_PROJECT_DIR"/.claude/hooks/pretooluse-bash-guard.sh` | `sh "${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks/pretooluse-bash-guard.sh"` |
| `PostToolUse` | `*` | `"$CLAUDE_PROJECT_DIR"/.claude/hooks/posttooluse-tool-call-tick.sh` | `sh "${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks/posttooluse-tool-call-tick.sh"` |
| `PostToolUse` | `Agent` | `"$CLAUDE_PROJECT_DIR"/.claude/hooks/posttooluse-agent-usage.sh` | `sh "${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks/posttooluse-agent-usage.sh"` |

> `posttooluse-loose-usage.sh` **nao entra** (opt-in explicito — research.md
> Decision 2). Invocacao via `sh "<path>"` cobre A5 (bit `+x` pode nao
> sobreviver a materializacao do cache); forma observada em S3.

## Entity: Distribution Path `[conceitual]`

Um dos dois caminhos pelos quais o catalogo chega ao ambiente. Nao e um
arquivo — e o estado derivado que o diagnostico reporta.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `kind` | enum | `classic` \| `plugin` | |
| `present` | bool | — | `classic`: existe `~/.claude/skills/`; `plugin`: instalado **e** habilitado |
| `root` | path | — | `classic`: `~/.claude/skills`; `plugin`: `installPath` de S4 |
| `content_hash` | string | — | `hash_dir` do catalogo (mecanismo ja existente, S7) |

### Sinais de deteccao `[REAL]`

| Sinal | Fonte | Campo |
|-------|-------|-------|
| Instalado | `~/.claude/plugins/installed_plugins.json` (S4) | `.plugins["cstk@<mkt>"][].installPath`, `.scope`, `.version` |
| Habilitado | `~/.claude/settings.json` (S6) | `.enabledPlugins["cstk@<mkt>"] == true` |
| Marketplace conhecido | `~/.claude/plugins/known_marketplaces.json` (S5) | `.<nome>.installLocation`, `.<nome>.source` |

> **Invariante verificada**: instalado ≠ habilitado. Em S4/S6 os 3 plugins
> instalados estao com `enabledPlugins == false`. Ambos os sinais MUST ser
> exigidos (research.md Decision 4).

### State Transitions

```
ausente → instalado(enabled=false) → habilitado → [desabilitado | removido]
                                         │
                                         └─ so aqui o dedup FR-005 se aplica
```

## Entity: Installation Alignment Report `[PROPOSTA]`

Saida de diagnostico do `cstk doctor` (FR-008). Artefato novo desta feature.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `classic` | DistributionPath | — | |
| `plugin` | DistributionPath | — | |
| `status` | enum | ver abaixo | Derivado |
| `remediation` | string | opcional | Acao concreta quando divergente |

### Estados de `status`

| Valor | Condicao | Reporte |
|-------|----------|---------|
| `classic-only` | so classico presente | Normal (SC-006) — sem ruido |
| `plugin-only` | so plugin presente | Normal |
| `aligned` | ambos presentes, `content_hash` igual | OK |
| `diverged` | ambos presentes, hash diferente | Aponta **qual** esta desatualizado + remediacao |
| `duplicated-hooks` | plugin habilitado **e** snippet classico em `settings.json` do projeto | Remediacao: remover registro classico (plugin vence, FR-005) |
| `undetermined` | registros nativos ilegiveis/ausentes | Degrada para `classic-only`; nunca erro fatal |

> `diverged` nao afirma "qual e mais novo" por timestamp: sem metadado
> confiavel de versao (S4 mostra `version: "unknown"`), o relatorio compara
> o hash de cada caminho contra o hash do catalogo do repo/tag corrente e
> reporta qual **difere** — sem inventar ordenacao temporal.
