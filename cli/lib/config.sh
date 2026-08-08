# config.sh — resolvedor + delegação pura para state-backend.sh
# (feature state-backend-config, FASE 4).
#
# Ref: docs/specs/state-backend-config/research.md Decision 2
#      docs/specs/state-backend-config/tasks.md FASE 4, task 4.1
#      cli/lib/state.sh (`_state_migrate_script_path`, padrao reusado)
#
# Esta lib NAO reimplementa parsing de config nem logica de decisao de
# backend: delega tudo a
# plugins/cstk/skills/agente-00c-runtime/scripts/state-backend.sh (fonte unica de
# leitura/escrita, Decision 2). E essa unicidade que torna SC-004 (0% de
# divergencia binario<->runtime) verdadeiro por construcao.
#
# Resolvedor de 3 camadas (mesmo padrao de `_state_migrate_script_path`,
# cli/lib/state.sh) para localizar `state-backend.sh`:
#   (1) PATH via `command -v`
#   (2) layout de repo relativo a CSTK_LIB
#       ($CSTK_LIB/../../plugins/cstk/skills/agente-00c-runtime/scripts/)
#   (3) layout instalado ($HOME/.claude/skills/agente-00c-runtime/scripts/)
#
# NOTA (nao confundir com P8): este resolvedor decide APENAS onde esta o
# script a invocar para delegacao normal de execucao (mesma ordem usada por
# todo o resto do CLI). A checagem de capability dentro de
# `state-backend.sh enable-sqlite` (P8) prioriza DELIBERADAMENTE o catalogo
# instalado sobre o repo — e uma decisao INTERNA e distinta, documentada em
# contracts/state-backend-runtime.md. As duas nao se sobrepoem: aqui so
# achamos ONDE RODAR o script; o script, uma vez rodando, decide sozinho
# qual runtime valida a capability.
#
# Funcoes exportadas (delegacao pura; repassam argumentos e exit code
# VERBATIM — zero reimplementacao de parsing ou de logica de decisao):
#   config_state_backend_capability [ARGS...]
#   config_state_backend_resolve [ARGS...]
#   config_state_backend_enable_sqlite [ARGS...]
#
# Exit codes (mesma familia de `cstk state` / `state-backend.sh`):
#   0 sucesso   1 falha   2 uso incorreto   3 recusado por pre-condicao
#
# POSIX sh puro. Sem bash-isms.

if [ -n "${_CSTK_CONFIG_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_CONFIG_LOADED=1

# _config_state_backend_script_path -> imprime o caminho de
# state-backend.sh. Mesma logica de 3 camadas e mesma licao de campo de
# `_state_migrate_script_path` (recall_secrets_filter_path em recall.sh):
# testes/CI rodam o CLI da arvore do repo (CSTK_LIB=cli/lib) SEM ter o
# runtime em ~/.claude — resolver SO via ~/.claude passa local e quebra no
# CI fresh-checkout.
_config_state_backend_script_path() {
  if command -v state-backend.sh >/dev/null 2>&1; then
    command -v state-backend.sh
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _cbs_repo="$CSTK_LIB/../../plugins/cstk/skills/agente-00c-runtime/scripts/state-backend.sh"
    if [ -f "$_cbs_repo" ]; then
      printf '%s\n' "$_cbs_repo"
      return 0
    fi
  fi
  _cbs_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/state-backend.sh"
  if [ -f "$_cbs_default" ]; then
    printf '%s\n' "$_cbs_default"
    return 0
  fi
  return 1
}

# _config_delegate SUBCOMANDO [ARGS...] -> resolve o script e invoca o
# subcomando, repassando argumentos e exit code verbatim. Script nao
# encontrado -> diagnostico em stderr + exit 1 (mesmo padrao de
# `state_main` para `migrate`).
_config_delegate() {
  _cd_sub=$1
  shift
  if ! _cd_script=$(_config_state_backend_script_path); then
    printf 'cstk: state-backend.sh nao encontrado.\n' >&2
    printf 'cstk: instale o runtime 00c ("cstk install") ou rode a partir da arvore do repo.\n' >&2
    return 1
  fi
  # `sh "$script"` (em vez de exec direto) evita depender do bit de
  # execucao preservado pelo empacotamento do tarball.
  sh "$_cd_script" "$_cd_sub" "$@"
  return $?
}

config_state_backend_capability() {
  _config_delegate capability "$@"
}

config_state_backend_resolve() {
  _config_delegate resolve "$@"
}

config_state_backend_enable_sqlite() {
  _config_delegate enable-sqlite "$@"
}
