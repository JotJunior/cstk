#!/bin/sh
# plugin-remove.sh — implementa `cstk plugin-remove <name>`
#
# Funcao exportada:
#   plugin_remove_main <name>   — ponto de entrada do subcomando
#
# Comportamento (contracts §plugin-remove Behavior):
#   1. Validar nome (FR-002 — rejeita antes de fs)
#   2. Se nao instalado → exit 1, erro claro (FR-012)
#   3. rm -rf do store dir; tratamento de falha parcial (tarefa 1.4)
#   4. Remover entrada do registry; reportar inconsistencia se falhar
#   5. Confirmar remocao (US3-AS3)
#
# Exit codes:
#   0  removido
#   1  plugin nao encontrado / erro de IO / inconsistencia
#   2  uso incorreto (nome invalido)
#
# NENHUMA chamada de rede (FR-018).
#
# POSIX sh puro.

if [ -n "${_CSTK_PLUGIN_REMOVE_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_PLUGIN_REMOVE_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/plugin-common.sh"

# ---------------------------------------------------------------------------
# plugin_remove_main — ponto de entrada
# ---------------------------------------------------------------------------

plugin_remove_main() {
  _pr_name=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --) shift; break ;;
      -*) printf 'cstk plugin-remove: flag desconhecida: %s\n' "$1" >&2; return 2 ;;
      *)
        if [ -z "$_pr_name" ]; then
          _pr_name=$1
        else
          printf 'cstk plugin-remove: argumento inesperado: %s\n' "$1" >&2
          return 2
        fi
        ;;
    esac
    shift
  done

  if [ -z "$_pr_name" ]; then
    printf 'uso: cstk plugin-remove <name>\n' >&2
    return 2
  fi

  # ------------------------------------------------------------
  # Passo 1: Validar nome (FR-002 — rejeita antes de qualquer fs).
  # ------------------------------------------------------------
  plugin_validate_name "$_pr_name" || return 2

  # ------------------------------------------------------------
  # Passo 2: Verificar se instalado (FR-012).
  # ------------------------------------------------------------
  if ! plugin_is_installed "$_pr_name" 2>/dev/null; then
    printf 'cstk plugin-remove: plugin nao instalado: %s\n' "$_pr_name" >&2
    return 1
  fi

  _pr_store=$(plugin_store_dir "$_pr_name")

  # ------------------------------------------------------------
  # Passo 3: Remover diretorio do store com tratamento de falha parcial.
  # (tarefa 1.4: falha parcial → reportar estado inconsistente, exit 1)
  # ------------------------------------------------------------
  _pr_rm_ok=1
  if rm -rf -- "$_pr_store" 2>/dev/null; then
    _pr_rm_ok=0
  fi

  # Verificar se o diretorio ainda existe (rm parcial).
  if [ "$_pr_rm_ok" -ne 0 ] || [ -e "$_pr_store" ]; then
    printf 'cstk plugin-remove: remocao parcial — store pode estar em estado indeterminado: %s\n' \
      "$_pr_store" >&2
    printf 'cstk plugin-remove: remova manualmente e re-tente.\n' >&2
    return 1
  fi

  # ------------------------------------------------------------
  # Passo 4: Remover entrada do registry.
  # Se falhar apos rm do diretorio: reportar inconsistencia (tarefa 1.4).
  # ------------------------------------------------------------
  if ! plugin_registry_remove "$_pr_name" 2>/dev/null; then
    printf 'cstk plugin-remove: registry nao atualizado apos rm do diretorio — re-tente plugin-remove para limpar o registry\n' >&2
    return 1
  fi

  # ------------------------------------------------------------
  # Passo 5: Confirmar remocao (US3-AS3).
  # ------------------------------------------------------------
  printf 'Plugin %s removido.\n' "$_pr_name"
  return 0
}
