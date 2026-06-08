#!/bin/sh
# plugin-list.sh — implementa `cstk plugin-list [--verify]`
#
# Funcao exportada:
#   plugin_list_main [--verify]   — ponto de entrada do subcomando
#
# Comportamento (contracts §plugin-list Behavior):
#   - Le o registry via plugin_registry_list (offline-only, FR-018, SC-006)
#   - Se vazio → exit 0 + "Nenhum plugin instalado." (US3-AS4)
#   - Para cada plugin: exibe linha NAME  VERSION  TYPE  STATUS (FR-011)
#   - Status sem --verify: "ok" do cache (SC-004 <2s)
#   - Status com --verify: re-hash + "tampered" se diverge (US3-AS2, FR-005)
#   - Status "unknown" se diretorio existe mas sem registry (ou vice-versa)
#
# Exit codes:
#   0  listou (inclusive lista vazia)
#   1  registry corrompido
#   2  uso incorreto
#
# NENHUMA chamada de rede ocorre em nenhum caminho (FR-018, SC-006).
#
# POSIX sh puro.

if [ -n "${_CSTK_PLUGIN_LIST_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_PLUGIN_LIST_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/plugin-common.sh"

# ---------------------------------------------------------------------------
# plugin_list_main — ponto de entrada
# ---------------------------------------------------------------------------

plugin_list_main() {
  _pl_verify=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --verify) _pl_verify=1 ;;
      --) shift; break ;;
      -*) printf 'cstk plugin-list: flag desconhecida: %s\n' "$1" >&2; return 2 ;;
      *)  printf 'cstk plugin-list: argumento inesperado: %s\n' "$1" >&2; return 2 ;;
    esac
    shift
  done

  # Inicializar registry se necessario (idempotente) antes de ler.
  plugin_registry_init 2>/dev/null || true

  # Ler lista de plugins.
  _pl_list=$(plugin_registry_list 2>/dev/null) || {
    printf 'cstk plugin-list: erro ao ler registry\n' >&2
    return 1
  }

  # Verificar se lista esta vazia (sem linhas de dados).
  if [ -z "$_pl_list" ]; then
    printf 'Nenhum plugin instalado.\n'
    return 0
  fi

  # Cabecalho.
  printf '%-20s  %-10s  %-6s  %s\n' "NAME" "VERSION" "TYPE" "STATUS"

  # Processar cada linha: NAME<TAB>VERSION<TAB>TYPE<TAB>SHA256<TAB>INSTALLED_AT
  printf '%s\n' "$_pl_list" | while IFS='	' read -r _pl_name _pl_ver _pl_type _pl_sha _pl_installed_at; do
    # Pular linhas em branco.
    [ -z "$_pl_name" ] && continue

    _pl_status="ok"

    # Verificar se o diretorio do plugin existe.
    _pl_dir=$(plugin_store_dir "$_pl_name" 2>/dev/null)
    if [ ! -d "$_pl_dir" ]; then
      # Entrada no registry mas diretorio ausente.
      _pl_status="unknown"
    elif [ "$_pl_verify" -eq 1 ]; then
      # Re-hash do bundle para detectar tampering (US3-AS2, FR-005).
      # plugin_verify_bundle_checksum: exit 0 = ok, exit 1 = mismatch.
      if ! plugin_verify_bundle_checksum "$_pl_dir" "$_pl_sha" 2>/dev/null; then
        _pl_status="tampered"
      fi
    fi

    printf '%-20s  %-10s  %-6s  %s\n' "$_pl_name" "${_pl_ver:-?}" "${_pl_type:-?}" "$_pl_status"
  done

  return 0
}
