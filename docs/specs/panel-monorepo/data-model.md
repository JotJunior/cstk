# Data Model: panel-monorepo

**Feature**: `panel-monorepo` | **Data**: 2026-08-28

Esta feature e uma migracao de repositorio e pipeline de release. Nao introduz
schema de banco nem persistencia nova. As "entidades" abaixo sao artefatos e
identificadores ja existentes, cujo **ciclo de vida** muda — e e isso que
precisa estar explicito.

---

## Entity: Pacote de release

Arquivo baixavel publicado dentro de uma release versionada.

| Campo | Tipo | Origem | Notas |
|---|---|---|---|
| `browser_download_url` | string (URL) | API GitHub, `assets[]` | unico campo do asset consumido pelo `serve` |
| `basename` | string | derivado da URL | discriminador de componente (§Regras) |
| `sibling_sha256` | string (URL) \| ausente | `browser_download_url + ".sha256"` | presenca e condicao de `verified` |

### Regras de identidade

| Componente | Padrao de basename | Produtor |
|---|---|---|
| toolkit | `cstk-<bare>.tar.gz` | `scripts/build-release.sh` (`release.yml:80`) |
| painel | `cstk-panel-<bare>.tar.gz` | `git archive HEAD:panel` (passo novo) |

`cstk-` e prefixo proprio de `cstk-panel-`: a discriminacao MUST usar o prefixo
longo. Ver `contracts/serve-asset-selection.md` §3.2 invariante I1.

### State transitions (do ponto de vista do `serve`)

```
candidato --(prefixo casa + sibling .sha256 existe)--> selecionado
selecionado --(host na allowlist)--> baixado        | else: rejeitado-host
baixado --(sha256 confere)--> verificado            | else: mismatch-blocked
verificado --(package.json presente pos-extracao)--> instalado
verificado --(package.json ausente)--> wrong-payload-blocked   [PROPOSTA]
```

O estado `wrong-payload-blocked` e a novidade de FR-009: hoje a transicao final
falha, mas sem deixar registro.

---

## Entity: Identidade de projeto

Nome logico sob o qual historico de execucoes e specs sao rastreados.
Independente da localizacao no repositorio.

| Camada | Fonte | Condicao de uso |
|---|---|---|
| 1 | `.execution.canonical_project` (congelado no init) | quando nao-vazio |
| 2 | `basename(dirname(git rev-parse --git-common-dir))` | somente se `.git` e **arquivo** (worktree) |
| 3 | `basename(target_project_path)` | fallback final |

Fonte: `recall_derive_canonical` / `recall_derive_canonical_from_path` em
`cli/lib/recall.sh`.

### Transicao provocada por esta feature

| Momento | PAP | Camada aplicada | Identidade |
|---|---|---|---|
| antes da migracao | `<...>/cstk-panel` | 3 | `cstk-panel` |
| depois, **sem** a flag | `<repo>/panel` | 3 | `panel` — **orfa** |
| depois, **com** a flag | `<repo>/panel` | 1 | `cstk-panel` — continuidade |

A camada 2 nao se aplica: o `.git` do monorepo e diretorio, nao arquivo.

**Invariante (FR-020)**: execucoes iniciadas de `panel/` MUST registrar
`canonical_project = "cstk-panel"`. Sem isso, `UNIQUE(project, feature, wave,
source_id)` da knowledge.db passa a discriminar por um `project` diferente do
historico, e as 7 execucoes anteriores deixam de ser resolvidas pelo painel.

**Acoplamento obrigatorio (regra dura, `ingest-derivation.md` §4)**: o
`EXCLUDE_FEATURE` do anti-eco em `agente-00c-orchestrator.md` deriva da mesma
expressao. Muda na mesma entrega.

---

## Entity: Estado de execucao (escopo de diretorio)

| Propriedade | Valor |
|---|---|
| Localizacao | `<PAP>/.claude/feature-00c-state/<short-name>/` |
| Resolucao | por PAP, **nao** por repositorio |
| Consumidor sensivel | `_hook-active-exec.sh` (uma execucao ativa por diretorio de escopo, teto `_HAE_MAX_DIRS=100`) |

Transicao: states do painel passam de `<...>/cstk-panel/.claude/` para
`<repo>/panel/.claude/`; states do cstk permanecem em `<repo>/.claude/`.
Nenhuma mistura (FR-021).

---

## Entity: Aviso de transicao

| Campo | Valor | Estado |
|---|---|---|
| Canal | elemento estatico na UI do painel | `[PROPOSTA]` |
| Ativacao | presente no bundle a partir da release-ponte | `[PROPOSTA]` |
| Rede | nenhuma (Principio IV) | `[PROPOSTA]` |
| Persistencia | visivel enquanto o bundle da release-ponte estiver instalado | `[PROPOSTA]` |

Nao e canal: release notes (FR-022 — `serve` nunca as exibe).

---

## Entity: Governanca (constituicao) por raiz de projeto

| Projeto | Caminho | Versao |
|---|---|---|
| toolkit | `docs/constitution.md` | 1.3.0 |
| painel | `panel/docs/constitution.md` | 2.0.2 |

Regra de nao-colisao: o detector compara `<PAP>/docs/constitution.md` contra
`<FD>/constitution.md` e **nunca varre subdiretorios**. Cada constituicao so e
vista por execucoes cujo PAP e a raiz do seu proprio projeto. Ver `research.md`
Decision 7.
