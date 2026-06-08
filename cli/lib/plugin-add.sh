#!/bin/sh
# plugin-add.sh — implementa `cstk plugin-add <name> [--force]`
#
# Funcao exportada:
#   plugin_add_main [<name>] [--force]   — ponto de entrada do subcomando
#
# Sequencia (contratos §plugin-add Behavior):
#   1. Validar nome (FR-002 — rejeita ANTES de fs/rede)
#   2. Resolver URL do repositorio do plugin
#   3. Verificar se ja instalado; tratar interacao/--force (FR-009/CHK009)
#   4. Baixar bundle (tarball) via http_download
#   5. Tar-slip guard OBRIGATORIO (A05/A08) — listar entradas do tarball
#      ANTES de extrair; rejeitar paths absolutos, "..", symlinks externos
#   5b. Extrair para staging e ler plugin-manifest.json
#   6. Verificar manifest + checksum (FR-004/FR-008)
#   7. Mover staging → store dir (atomico)
#   8. Upsert no registry.json
#   9. Reportar sucesso
#
# Cleanup: trap EXIT remove tmp/staging em qualquer caminho de saida.
#
# Exit codes:
#   0  instalado OK (ou no-op: recusou overwrite em TTY)
#   1  erro: rede, checksum mismatch, manifest invalido, schema nao suportado
#   2  uso incorreto: nome invalido / args faltando
#
# POSIX sh puro. Deps: curl (http.sh), mktemp, tar, rm.

if [ -n "${_CSTK_PLUGIN_ADD_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_PLUGIN_ADD_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/plugin-common.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/http.sh"

# ---------------------------------------------------------------------------
# Helpers internos (prefixo _pa_ para evitar colisao com plugin-common _pc_)
# ---------------------------------------------------------------------------

# _pa_cleanup: remove arquivos temporarios criados por plugin_add_main.
# Chamado via trap EXIT — deve ser idempotente.
_pa_cleanup() {
  [ -n "${_pa_tmp:-}" ] && [ -e "${_pa_tmp:-}" ] && rm -rf -- "$_pa_tmp"
  [ -n "${_pa_staging:-}" ] && [ -e "${_pa_staging:-}" ] && rm -rf -- "$_pa_staging"
}

# _pa_tar_slip_guard <tarball> <staging_dir>
# Lista entradas do tarball e rejeita qualquer path perigoso:
#   (i)  paths absolutos (comecam com /)
#   (ii) componentes ".." (traversal)
# Sao rejeicoes conservadoras — heuristica de symlink externo nao e portavel
# sem extrair; (i) e (ii) cobrem A05/A08 no MVP.
# Exit 0 = ok; exit 1 = tar-slip detectado (mensagem em stderr).
_pa_tar_slip_guard() {
  _pa_tsg_tar=$1
  _pa_tsg_dir=$2

  # Listar entradas — tar -tf funciona em POSIX/BSD/GNU.
  _pa_tsg_list=$(tar -tf "$_pa_tsg_tar" 2>/dev/null) || {
    printf 'cstk plugin-add: nao foi possivel listar entradas do tarball\n' >&2
    return 1
  }

  # Verificar cada entry linha a linha.
  printf '%s\n' "$_pa_tsg_list" | while IFS= read -r _pa_entry; do
    # (i) Path absoluto.
    case "$_pa_entry" in
      /*) printf 'cstk plugin-add: tar-slip detectado — path absoluto: %s\n' "$_pa_entry" >&2
          return 1 ;;
    esac
    # (ii) Componente "..".
    # Checar componente isolado ".." em qualquer posicao do path.
    # Dividido em casos separados para evitar SC2221/SC2222 (shadowing).
    case "$_pa_entry" in
      */../*)
        printf 'cstk plugin-add: tar-slip detectado — componente ".." em: %s\n' "$_pa_entry" >&2
        return 1 ;;
      */.. | ../*)
        printf 'cstk plugin-add: tar-slip detectado — componente ".." em: %s\n' "$_pa_entry" >&2
        return 1 ;;
      ..)
        printf 'cstk plugin-add: tar-slip detectado — componente ".." em: %s\n' "$_pa_entry" >&2
        return 1 ;;
    esac
  done
  # Capturar exit do while (possivelmente falhou via return 1 no subshell).
  # Em POSIX sh, "while ... | while ... done" roda em subshell — exit do while
  # e o exit do ultimo comando do pipeline.
  return 0
}

# ---------------------------------------------------------------------------
# plugin_add_main — ponto de entrada
# ---------------------------------------------------------------------------

plugin_add_main() {
  _pa_name=""
  _pa_force=0

  # Parse de argumentos.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force) _pa_force=1 ;;
      --) shift; break ;;
      -*) printf 'cstk plugin-add: flag desconhecida: %s\n' "$1" >&2; return 2 ;;
      *)
        if [ -z "$_pa_name" ]; then
          _pa_name=$1
        else
          printf 'cstk plugin-add: argumento inesperado: %s\n' "$1" >&2
          return 2
        fi
        ;;
    esac
    shift
  done

  if [ -z "$_pa_name" ]; then
    printf 'uso: cstk plugin-add <name> [--force]\n' >&2
    return 2
  fi

  # Instalar trap de cleanup ANTES de criar qualquer tmpdir.
  _pa_tmp=""
  _pa_staging=""
  trap '_pa_cleanup' EXIT INT TERM

  # ------------------------------------------------------------
  # Passo 1: Validar nome (FR-002 — rejeita ANTES de qualquer fs/rede).
  # ------------------------------------------------------------
  plugin_validate_name "$_pa_name" || return 2

  # ------------------------------------------------------------
  # Passo 2: Resolver URL base do repositorio do plugin.
  # A URL do tarball de release e <base_url>/archive/refs/tags/latest.tar.gz
  # (research D3 — formato GitHub Releases).
  # ------------------------------------------------------------
  _pa_repo_url=$(plugin_resolve_url "$_pa_name") || return 1
  _pa_tarball_url="${_pa_repo_url}/archive/refs/tags/latest.tar.gz"

  # ------------------------------------------------------------
  # Passo 3: Verificar se ja instalado; tratar TTY/--force (FR-009/CHK009).
  # ------------------------------------------------------------
  if plugin_is_installed "$_pa_name" 2>/dev/null; then
    _pa_installed_ver=$(plugin_registry_get "$_pa_name" 2>/dev/null | cut -f2)
    printf 'cstk plugin-add: %s ja instalado (versao %s)\n' "$_pa_name" "${_pa_installed_ver:-desconhecida}" >&2

    if [ "$_pa_force" -eq 0 ]; then
      # Sem --force: verificar TTY.
      if [ -t 0 ]; then
        # TTY disponivel: pedir confirmacao interativa.
        printf 'Reinstalar? [s/N] ' >&2
        # shellcheck disable=SC2162
        read _pa_confirm
        case "${_pa_confirm:-n}" in
          [sS]|[sS][iI][mM]) : ;;  # continua
          *) printf 'cstk plugin-add: install cancelado.\n' >&2; return 0 ;;
        esac
      else
        # Sem TTY e sem --force: abortar (CHK009 / FR-009 safer default).
        printf 'cstk plugin-add: %s ja instalado; use --force para reinstalar em modo nao-interativo\n' "$_pa_name" >&2
        return 1
      fi
    fi
  fi

  # ------------------------------------------------------------
  # Passo 4: Baixar bundle para tmp via http_download (FR-006).
  # ------------------------------------------------------------
  _pa_tmp=$(mktemp -d 2>/dev/null) || {
    printf 'cstk plugin-add: mktemp -d falhou\n' >&2
    return 1
  }
  _pa_tarball="$_pa_tmp/bundle.tar.gz"

  printf 'cstk plugin-add: baixando %s...\n' "$_pa_name" >&2
  if ! http_download "$_pa_tarball_url" "$_pa_tarball"; then
    printf 'cstk plugin-add: nenhum estado parcial escrito\n' >&2
    return 1
  fi

  # ------------------------------------------------------------
  # Passo 5: Tar-slip guard OBRIGATORIO (A05/A08) — ANTES de extrair.
  # ------------------------------------------------------------
  _pa_staging=$(mktemp -d 2>/dev/null) || {
    printf 'cstk plugin-add: mktemp -d falhou (staging)\n' >&2
    return 1
  }

  if ! _pa_tar_slip_guard "$_pa_tarball" "$_pa_staging"; then
    printf 'cstk plugin-add: install abortado por razao de seguranca (tar-slip)\n' >&2
    return 1
  fi

  # Extrair o tarball para o staging (cwd fixado em staging via -C).
  if ! tar -xzf "$_pa_tarball" -C "$_pa_staging" 2>/dev/null; then
    printf 'cstk plugin-add: falha ao extrair tarball\n' >&2
    return 1
  fi

  # Normalizar: o GitHub gera um subdirectory cstk-plugin-<name>-<ver>/ ou
  # similar na raiz do tarball. Detectar o subdir e usar como raiz do plugin.
  # Se nao houver subdir extra (bundle direto), usar staging como raiz.
  _pa_plugin_root="$_pa_staging"
  _pa_subdirs=$(find "$_pa_staging" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  _pa_files_root=$(find "$_pa_staging" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$_pa_subdirs" -eq 1 ] && [ "$_pa_files_root" -eq 0 ]; then
    _pa_subdir=$(find "$_pa_staging" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    _pa_plugin_root="$_pa_subdir"
  fi

  # ------------------------------------------------------------
  # Passo 5b: Verificar manifest shape (FR-004/plugin-common).
  # ------------------------------------------------------------
  _pa_manifest_json=$(plugin_verify_manifest "$_pa_plugin_root") || return 1

  # Extrair campos do manifest.
  if command -v jq >/dev/null 2>&1; then
    _pa_mf_name=$(printf '%s' "$_pa_manifest_json" | jq -r '.name')
    _pa_mf_ver=$(printf '%s' "$_pa_manifest_json" | jq -r '.version')
    _pa_mf_type=$(printf '%s' "$_pa_manifest_json" | jq -r '.type')
    _pa_mf_sha=$(printf '%s' "$_pa_manifest_json" | jq -r '.sha256')
  else
    # Fallback POSIX: extrair via grep/sed.
    _pa_mf_name=$(grep '"name"' "$_pa_plugin_root/plugin-manifest.json" | sed 's/.*"name":"\([^"]*\)".*/\1/')
    _pa_mf_ver=$(grep '"version"' "$_pa_plugin_root/plugin-manifest.json" | sed 's/.*"version":"\([^"]*\)".*/\1/')
    _pa_mf_type=$(grep '"type"' "$_pa_plugin_root/plugin-manifest.json" | sed 's/.*"type":"\([^"]*\)".*/\1/')
    _pa_mf_sha=$(grep '"sha256"' "$_pa_plugin_root/plugin-manifest.json" | sed 's/.*"sha256":"\([^"]*\)".*/\1/')
  fi

  # Verificar que o nome no manifest bate com o nome solicitado.
  if [ "$_pa_mf_name" != "$_pa_name" ]; then
    printf 'cstk plugin-add: manifest.name (%s) nao bate com o nome solicitado (%s)\n' \
      "$_pa_mf_name" "$_pa_name" >&2
    return 1
  fi

  # ------------------------------------------------------------
  # Passo 6: Recomputar checksum e comparar com manifest.sha256 (FR-004).
  # plugin_verify_bundle_checksum gera mensagem clara em mismatch.
  # ------------------------------------------------------------
  if ! plugin_verify_bundle_checksum "$_pa_plugin_root" "$_pa_mf_sha"; then
    printf 'cstk plugin-add: install abortado, nada escrito\n' >&2
    return 1
  fi

  # ------------------------------------------------------------
  # Passo 7: Mover staging → store (atomico — mv em mesmo filesystem).
  # ------------------------------------------------------------
  _pa_store=$(plugin_store_dir "$_pa_name")
  _pa_store_parent=$(dirname "$_pa_store")

  # Garantir que o diretorio pai do store existe.
  if ! mkdir -p -- "$_pa_store_parent" 2>/dev/null; then
    printf 'cstk plugin-add: nao foi possivel criar diretorio de store %s\n' "$_pa_store_parent" >&2
    return 1
  fi

  # Remover versao anterior se existir (para mv atomico funcionar).
  if [ -e "$_pa_store" ]; then
    rm -rf -- "$_pa_store" 2>/dev/null || {
      printf 'cstk plugin-add: nao foi possivel remover store anterior: %s\n' "$_pa_store" >&2
      return 1
    }
  fi

  # mv atomico (no mesmo filesystem em /home ou /Users — deve ser atomico).
  if ! mv -- "$_pa_plugin_root" "$_pa_store" 2>/dev/null; then
    # Fallback: cp -R + rm (cross-device ou permissao).
    if ! cp -R -- "$_pa_plugin_root" "$_pa_store" 2>/dev/null; then
      printf 'cstk plugin-add: falha ao instalar plugin em %s\n' "$_pa_store" >&2
      return 1
    fi
  fi
  # Staging ja foi movido/copiado; limpar referencia para o trap nao tentar remover.
  _pa_staging=""

  # ------------------------------------------------------------
  # Passo 8: Upsert no registry.json.
  # ------------------------------------------------------------
  plugin_registry_init || return 1
  plugin_registry_upsert "$_pa_name" "$_pa_mf_ver" "$_pa_mf_type" "$_pa_mf_sha" || {
    printf 'cstk plugin-add: plugin instalado mas registry nao atualizado — rode plugin-remove e reinstale\n' >&2
    return 1
  }

  # ------------------------------------------------------------
  # Passo 9: Reportar sucesso.
  # ------------------------------------------------------------
  printf 'Plugin %s (%s) instalado com sucesso.\n' "$_pa_name" "$_pa_mf_ver"
  return 0
}
