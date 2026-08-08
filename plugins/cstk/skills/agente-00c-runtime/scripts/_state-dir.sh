#!/bin/sh
# _state-dir.sh — Helper sourceable para resolucao de path de estado.
#
# Ref: docs/specs/feature-00c/spec.md FR-008, FR-011
#      docs/specs/feature-00c/research.md Decision 1
#      docs/specs/feature-00c/plan.md FASE 1 task 1.2.1
#
# NAO e executavel diretamente. Use:
#   . "$(dirname -- "$0")/_state-dir.sh"
#   _sd_resolve "${1:-}"        # imprime path resolvido, exit 0 se OK
#
# Contrato:
#   1. Se --state-dir DIR foi passado, ele tem precedencia. Use --state-dir="$@".
#   2. Se AGENTE_00C_STATE_DIR esta definido e nao-vazio no env, usa-o.
#   3. Caso contrario, exit 1 com mensagem em stderr.
#
# NUNCA aplica fallback silencioso para path historico. Erro claro >
# comportamento silencioso (Principio I do toolkit: auditabilidade).

# _sd_resolve EXPLICIT_DIR
#   EXPLICIT_DIR: valor de --state-dir DIR vindo do caller, ou string vazia.
# Imprime path resolvido em stdout. Exit 0 sucesso, 1 erro.
_sd_resolve() {
  _sd_explicit="${1:-}"
  if [ -n "$_sd_explicit" ]; then
    printf '%s' "$_sd_explicit"
    return 0
  fi
  if [ -n "${AGENTE_00C_STATE_DIR:-}" ]; then
    printf '%s' "$AGENTE_00C_STATE_DIR"
    return 0
  fi
  printf 'erro: --state-dir nao fornecido e AGENTE_00C_STATE_DIR vazio\n' >&2
  return 1
}

# _sd_require_dir DIR
#   DIR: path resolvido por _sd_resolve.
# Valida que DIR existe e e um diretorio gravavel. Exit 0 ok, 1 erro.
_sd_require_dir() {
  _sd_d="${1:-}"
  if [ -z "$_sd_d" ]; then
    printf 'erro: _sd_require_dir chamado com path vazio\n' >&2
    return 1
  fi
  if [ ! -d "$_sd_d" ]; then
    printf 'erro: state-dir nao existe ou nao e diretorio: %s\n' "$_sd_d" >&2
    return 1
  fi
  if [ ! -w "$_sd_d" ]; then
    printf 'erro: state-dir nao gravavel: %s\n' "$_sd_d" >&2
    return 1
  fi
  return 0
}

# _sd_flavor_to_report_name FLAVOR
#   FLAVOR: agente-00c | feature-00c
# Imprime nome canonico do arquivo de relatorio para o flavor.
_sd_flavor_to_report_name() {
  case "${1:-agente-00c}" in
    agente-00c)  printf 'agente-00c-report.md' ;;
    feature-00c) printf 'feature-00c-report.md' ;;
    *)
      printf 'erro: flavor desconhecido: %s (esperado: agente-00c|feature-00c)\n' "$1" >&2
      return 1
      ;;
  esac
}

# _sd_flavor_to_suggestions_name FLAVOR
#   FLAVOR: agente-00c | feature-00c
# Imprime nome canonico do arquivo de sugestoes para o flavor.
_sd_flavor_to_suggestions_name() {
  case "${1:-agente-00c}" in
    agente-00c)  printf 'agente-00c-suggestions.md' ;;
    feature-00c) printf 'feature-00c-suggestions.md' ;;
    *)
      printf 'erro: flavor desconhecido: %s\n' "$1" >&2
      return 1
      ;;
  esac
}
