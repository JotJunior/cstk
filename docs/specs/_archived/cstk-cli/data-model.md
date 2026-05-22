# Data Model: cstk CLI

Entidades de estado persistente que a CLI lê, escreve ou inspeciona. Projeto e
local (filesystem) — nao ha DB.

## Entity: Manifest

Arquivo texto plain persistido por escopo. Representa o estado oficial do que a CLI
instalou naquele escopo.

**Localizacao:**
- Global: `~/.claude/skills/.cstk-manifest`
- Projeto: `./.claude/skills/.cstk-manifest`

**Formato (TSV com header comentado):**

```
# cstk manifest v1
# schema: <skill-name>\t<toolkit-version>\t<source-sha256>\t<installed-at-iso>
specify	3.2.0	a1b2c3d4...	2026-04-22T14:30:00Z
plan	3.2.0	e5f6g7h8...	2026-04-22T14:30:00Z
```

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| schema_version | int | line 1 comment, parsed by CLI | Single source of truth for parser compat; bump on format change |
| skill_name | string | no tabs, no spaces, unique per manifest | Primary key |
| toolkit_version | string | SemVer (`MAJOR.MINOR.PATCH`) | Tag da release de onde veio |
| source_sha256 | hex string (64 chars) | obrigatorio | SHA-256 do tar determinista da skill NO MOMENTO DA INSTALACAO |
| installed_at | ISO8601 timestamp | UTC | `date -u +%Y-%m-%dT%H:%M:%SZ` |

### Invariantes

- Uma skill aparece no maximo uma vez no manifest (primary key = skill_name).
- `source_sha256` e o hash da skill *como ela era na release* — nao muda com edicoes
  locais. Edicao local = (hash atual do diretorio da skill) != (source_sha256 no
  manifest).
- Se uma skill tem diretorio em disco mas nao tem entrada no manifest: a CLI
  considera "skill de terceiro" (nao tocar).
- Se uma skill tem entrada no manifest mas diretorio nao existe em disco: drift
  detectado por `cstk doctor`, remove entrada no proximo `update --prune`.

### State transitions (por skill)

```
(none)
  |  install
  v
installed-clean  <-->  installed-edited  (detectado por hash mismatch)
  |                      |
  |  update              |  update com --force
  v                      v
installed-clean       installed-clean (sobrescrito)
  |
  |  uninstall / update prune
  v
(none)
```

## Entity: Profile (catalog-side, nao persistido no manifest)

Definicao estatica que vem com o release tarball em `catalog/profiles.txt`. CLI le
mas nunca escreve. Usada para resolver `--profile <name>` → lista de skills.

**Formato (linhas `profile:skill`):**

```
# cstk profiles catalog
# format: <profile-name>:<skill-name> OR <profile-name>:<profile-name> (nested)
sdd:briefing
sdd:constitution
sdd:specify
sdd:clarify
sdd:plan
sdd:checklist
sdd:create-tasks
sdd:analyze
sdd:execute-task
sdd:review-task
complementary:advisor
complementary:bugfix
complementary:create-use-case
complementary:image-generation
complementary:initialize-docs
complementary:apply-insights
complementary:owasp-security
complementary:validate-documentation
complementary:validate-docs-rendered
language-go:<go-skills>
language-dotnet:<dotnet-skills>
all:sdd
all:complementary
all:language-go
all:language-dotnet
```

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| profile_name | string | slug (kebab-case) | Must match `^[a-z][a-z0-9-]*$` |
| member | string | skill-name OR other profile-name | Recursive: resolucao expande perfis referenciados ate set final de skill-names |

### Invariantes

- Grafo de perfis e acyclic. CLI rejeita tarball com ciclo em validation de boot.
- `all` expande para o set completo.

## Entity: Catalog Entry (catalog-side)

Representa uma skill disponivel no tarball da release atual. CLI le; usuario nao
manipula.

**Derivacao**: existencia de `catalog/skills/<skill-name>/SKILL.md` ou
`catalog/language/<lang>/skills/<skill-name>/SKILL.md` no tarball extraido.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| name | string | nome do diretorio | Unique por scope (global vs language) |
| origin | enum | `global` / `language-<lang>` | Derivado do path no tarball |
| files | list | `find <skill-dir> -type f` | Determina o hash |
| has_hook | bool | existe `../hooks/` e `../settings.json` | Relevante para perfis language-* |

## Entity: Lock

Arquivo/diretorio temporario que previne execucoes concorrentes no mesmo escopo.

**Localizacao:**
- Global: `~/.claude/skills/.cstk.lock/` (diretorio)
- Projeto: `./.claude/skills/.cstk.lock/`

**Ciclo de vida:**
1. CLI inicia → `mkdir .cstk.lock` (atomico via POSIX). Se falha: outra instancia
   rodando; abortar.
2. `trap 'rmdir .cstk.lock' EXIT INT TERM` registra limpeza.
3. CLI termina (sucesso ou falha) → `rmdir` remove o lock.
4. Kill -9 deixa lock stale → usuario remove manualmente (`rmdir` na mao); CLI
   instrui isso na mensagem de erro "lock already held".

### Invariantes

- Lock existe = ha ou houve (stale) uma execucao em curso.
- Lock e por escopo, nao global-de-tudo: rodar `cstk install --scope global` em
  paralelo com `cstk install --scope project` em projeto X e OK.

## Entity: Installed CLI

A propria CLI instalada na maquina do usuario. Relevante para self-update.

**Localizacao:**
- Executavel: `~/.local/bin/cstk` (ou `$CSTK_BIN` se setado)
- Biblioteca: `~/.local/share/cstk/lib/*.sh` (ou `$CSTK_LIB` se setado)
- Versao declarada: `~/.local/share/cstk/VERSION` (contem a tag, ex: `3.2.0`)

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| bin_path | path | existe, executavel | Atomic-replace target para self-update |
| lib_dir | path | existe, contem `*.sh` | Replaced pro bloco em self-update |
| installed_version | string | SemVer, lido de VERSION | Comparado com release latest |

### Relationships

- `Manifest.toolkit_version` e `Installed CLI.installed_version` PODEM divergir —
  cenario normal quando usuario roda `self-update` mas ainda nao rodou `update`.
  CLI reporta a divergencia em `doctor` e sugere `update`.

## Relationships sumario

```
Installed CLI  ──reads/writes──▶  Manifest (por scope)
                │
                └──reads (at runtime)──▶  Release tarball (GitHub) ──contains──▶  Profile + Catalog Entries
```

## Entity: Per-path Lock (FASE 12, FR-016h)

Lock per-path criado pelo subcomando `cstk 00c <path>` para impedir invocacoes
concorrentes no mesmo diretorio durante o fluxo interativo.

| Campo | Tipo | Descricao |
|-------|------|-----------|
| Path | filesystem | `<path>/.cstk-00c.lock/` (diretorio vazio criado via `mkdir` atomico) |
| Lifecycle | runtime | Criado apos validacao do path (FR-016b) e antes de qualquer prompt; liberado via `rmdir` no trap EXIT/INT/TERM ou explicitamente antes do `exec claude` |
| Conflito | check | Tentativa de `mkdir` em lock pre-existente falha → cstk 00c aborta com exit 1 e mensagem instrutiva |
| Tipo | runtime-only | NAO persistido no manifest; e estado efemero do fluxo `cstk 00c` |

Notas:
- Lock fica DENTRO do `<path>` (nao em diretorio global) — escopo natural do
  subcomando. Cleanup orfao = `rmdir <path>/.cstk-00c.lock` manualmente.
- Distinto do lock de FR-015 (`<scope>/.cstk.lock`), que protege escopos
  `~/.claude/skills` etc. `cstk 00c` opera em diretorio arbitrario fora desses
  escopos e nao herda esse lock.
- Stale lock pode ocorrer se `cstk 00c` for terminado por SIGKILL (sem trap).
  Detectavel por idade do diretorio `.cstk-00c.lock/` > tempo razoavel; cleanup
  manual aceitavel.

## Entity: Bootstrap Whitelist File (FASE 12, FR-016f)

Arquivo de whitelist de URLs externas escrito pelo `cstk 00c <path>` antes do
`exec claude`, consumido pelo agente-00c-orchestrator via flag `--whitelist`.

| Campo | Tipo | Descricao |
|-------|------|-----------|
| Path | filesystem | `<path>/.agente-00c-whitelist.txt` |
| Format | plain text | Uma URL absoluta por linha (`http://` ou `https://`); SEM comentarios; SEM linhas em branco; LF (Unix line endings) |
| Permissions | mode | `chmod 600` (so owner le/escreve) |
| Created by | `cstk 00c` | Sequencia: prompts -> sanitize/validate cada URL -> escrita atomica via `mktemp + mv` -> chmod 600 |
| Read by | agente-00c-runtime | Orquestrador le via `--whitelist <abs-path>` repassado por `cstk 00c` |
| Lifecycle | persistente | Permanece no `<path>` apos `exec claude`; NAO removido por `cstk 00c` |

Notas:
- Persistencia intencional: o orquestrador pode re-ler durante ondas posteriores
  ou em retomada via `/agente-00c-resume`. Limpeza fica a cargo do operador.
- Validacao de URL no `cstk 00c` espelha a logica de `whitelist-validate.sh` do
  agente-00c-runtime (rejeita patterns overly-broad: `**`, `*://*`, `https://*`
  sem dominio); reimplementada em `cli/lib/00c-bootstrap.sh` por escolha de
  arquitetura (Decision 12 + Clarifications round 2 Q1).
