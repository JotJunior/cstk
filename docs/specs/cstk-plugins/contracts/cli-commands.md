# Contracts: cstk-plugins — CLI subcommands

Tres novos subcomandos seguindo a convencao de dispatch existente
(`cli/lib/<subcommand>.sh` com funcao `<subcommand_with_underscores>_main`;
hifen vira underscore — vide `cli/cstk` linha ~239
`_main_fn="$(printf '%s' "$_cmd" | sed 's/-/_/g')_main"`).

| Subcommand | Lib file | Main fn | Rede? |
|------------|----------|---------|-------|
| `plugin-add <name>` | `cli/lib/plugin-add.sh` | `plugin_add_main` | SIM (so este; FR-006/FR-018) |
| `plugin-remove <name>` | `cli/lib/plugin-remove.sh` | `plugin_remove_main` | NAO |
| `plugin-list` | `cli/lib/plugin-list.sh` | `plugin_list_main` | NAO |

Helper compartilhado: `cli/lib/plugin-common.sh` (`plugin_common_*`):
resolucao de nome→URL (FR-001), validacao de nome (FR-002), checksum via
`hash_dir`, CRUD do registry, `plugin_resolve_skill_dir` (path-prepending).

---

## Command: `cstk plugin-add <name> [--force]`

**Purpose**: Baixa, verifica integridade e instala um plugin (US1, US4).

### Args / Flags

| Arg/Flag | Type | Required | Validation |
|----------|------|----------|------------|
| `<name>` | string | yes | `^[a-z][a-z0-9-]{0,63}$` (FR-002) — rejeitado ANTES de qualquer fs/rede |
| `--force` | flag | no | Pula o prompt de overwrite quando ja instalado (FR-009) |

### Behavior (ordem)

1. Validar `<name>` (FR-002). Falha → exit 2, sem fs/rede.
2. Resolver URL: `<base>/cstk-plugin-<name>` onde `base` = `CSTK_PLUGIN_REGISTRY`
   env, senao `~/.cstk/config` key `registry`, senao default
   `https://github.com/JotJunior/` (FR-001).
3. Se ja instalado (registry tem `<name>`): mostrar versao instalada. Sem
   `--force`: verificar `[ -t 0 ]` (stdin e TTY?). Se TTY: pedir confirmacao
   interativa; recusa → exit 0 (no-op). Se NAO TTY: abortar com exit 1 e
   mensagem clara pedindo `--force` para uso nao-interativo (FR-009, CHK009
   — safer default: nunca sobrescreve silenciosamente em CI/pipe).
4. Baixar bundle (tarball) para tmp via `http_download` (FR-006).
5. Extrair em staging tmp (`mktemp -d`); ler `plugin-manifest.json`; validar
   shape (data-model §Plugin Manifest, ordem 1-5).
5.bis. **Tar-slip guard (A05/A08, OBRIGATORIO)** — ANTES de materializar
   qualquer arquivo, listar as entradas do tarball (`tar -tf`) e REJEITAR o
   install (exit 1, limpa tmp) se QUALQUER entrada: (i) comeca com `/`
   (path absoluto); (ii) contem componente `..` (traversal); (iii) e um
   symlink/hardlink que resolve para fora do staging. So apos a lista passar,
   extrair COM o cwd fixado no staging (`tar -xf ... -C "$staging"`). Garante
   que nenhum byte do tarball escapa de `~/.claude/cstk/plugins/<name>/`,
   mesmo com checksum ainda nao verificado.
6. Recomputar checksum do bundle (`hash_dir`, excluindo o manifest) e comparar
   com `manifest.sha256` (FR-004). Mismatch → limpar tmp, exit 1 (FR US1-AS2).
7. Mover staging → `~/.claude/cstk/plugins/<name>/` (atomico; FR-008).
8. Upsert no `registry.json` (`bundle_sha256`, `installed_at`, version, type).
9. Reportar sucesso com versao instalada.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Instalado, ou no-op (ja instalado + recusou overwrite) |
| 1 | Erro: checksum mismatch / rede / manifest invalido / schema nao suportado |
| 2 | Uso incorreto: nome invalido / args faltando |

### Error contracts

| Condicao | Mensagem (stderr) | Exit |
|----------|-------------------|------|
| Nome invalido | `cstk plugin-add: nome invalido '<name>' (deve casar ^[a-z][a-z0-9-]{0,63}$)` | 2 |
| Rede offline (US1-AS4) | (de `http.sh`) `http: nao foi possivel resolver host ... (offline?)` + `nenhum estado parcial escrito` | 1 |
| Checksum mismatch (US1-AS2) | `cstk plugin-add: checksum mismatch — esperado <a>, obtido <b>; install abortado, nada escrito` | 1 |
| Schema nao suportado | `cstk plugin-add: unsupported manifest version <N> (atualize o cstk)` | 1 |

---

## Command: `cstk plugin-list [--verify]`

**Purpose**: Lista plugins instalados com status de integridade (US3).
Offline-only (FR-018). SC-004 (<2s).

### Flags

| Flag | Type | Required | Notes |
|------|------|----------|-------|
| `--verify` | flag | no | Re-hash de cada bundle e compara com `bundle_sha256` → status `tampered` se diverge. Sem a flag, status `ok` vem do cache (rapido). |

### Output (plain text, FR-011 — JSON fora de escopo)

```
NAME      VERSION   TYPE   STATUS
codex     1.2.0     llm    ok
lang-dotnet 0.3.1   lang   tampered
```

- Sem plugins → exit 0 + `Nenhum plugin instalado.` (US3-AS4, nao e erro).
- `tampered` so aparece com `--verify` re-hash falho (US3-AS2).

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Listou (inclusive lista vazia) |
| 1 | Registry corrompido |

---

## Command: `cstk plugin-remove <name>`

**Purpose**: Remove um plugin instalado (US3).

### Args

| Arg | Type | Required | Validation |
|-----|------|----------|------------|
| `<name>` | string | yes | FR-002 (rejeita antes de fs) |

### Behavior

1. Validar `<name>` (FR-002).
2. Se nao instalado (sem entrada no registry) → exit 1, erro claro (FR-012).
3. `rm -rf ~/.claude/cstk/plugins/<name>/`. Se `rm -rf` falhar ou for parcial
   (ex: permissao negada em algum arquivo): tentar atomic cleanup (re-verificar
   se o diretorio ainda existe e se a remocao foi completa); se nao-completa,
   reportar estado inconsistente em stderr com exit 1 ("remove parcial: store
   pode estar em estado indeterminado — remova manualmente e re-tente"); NAO
   silenciar o erro.
4. Remover entrada `<name>` do `registry.json`. Se a escrita no registry falhar
   apos o `rm -rf` ter removido o diretorio: reportar estado inconsistente com
   exit 1 ("registry nao atualizado apos rm do diretorio — re-tente plugin-remove
   para limpar o registry"); o plugin store esta limpo mas o registry diverge.
5. Confirmar (US3-AS3).

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Removido |
| 1 | Plugin nao encontrado / erro de IO |
| 2 | Uso incorreto (nome invalido) |
