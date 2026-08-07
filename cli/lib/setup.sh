#!/bin/sh
# setup.sh — subcomando `cstk setup` (feature cstk-setup): wizard guiado
# que percorre, em ordem fixa, as quatro areas de configuracao
# recomendadas de um projeto (hooks obrigatorios + loose-usage opt-in
# aninhado, backend de estado global, registro MCP de estado,
# telemetria), delegando toda deteccao/aplicacao aos comandos dedicados
# ja existentes (guard-hooks-status.sh, cli/lib/state.sh, cli/lib/mcp.sh,
# otel-usage.sh). Esta lib NUNCA reimplementa deteccao/aplicacao — so
# orquestra e apresenta.
#
# Ref: docs/specs/cstk-setup/spec.md FR-004 a FR-018
#      docs/specs/cstk-setup/contracts/cli-setup.md §1
#      docs/specs/cstk-setup/plan.md "Pontos de edicao em cli/cstk", Riscos
#      docs/specs/cstk-setup/quickstart.md Scenarios 1-18
#
# **NEUTRALIZACAO DE EXIT SOB `set -eu` (Risco 2 do plan.md, FR-009)**:
# esta lib e SOURCEADA (`. "$_lib_file"`) no MESMO shell de `cli/cstk`, que
# roda `set -eu` desde a primeira linha. Uma falha ou dependencia
# indisponivel em UMA area NUNCA MUST derrubar o wizard inteiro (FR-009:
# "each area's outcome is independent") — logo toda chamada de funcao de
# aplicacao/deteccao de area MUST ser neutralizada explicitamente, nunca
# invocada "nua":
#
#   # CORRETO — neutraliza antes de decidir o outcome da area
#   if ! _su_area_result=$(_setup_apply_hooks "$PROJECT_PATH"); then
#     _su_rc=$?
#     ...
#   fi
#
#   # ou, quando so o exit code importa:
#   _setup_apply_mcp "$PROJECT_PATH" || _su_rc=$?
#
#   # ERRADO — sob set -eu, exit != 0 de _setup_apply_state_backend aqui
#   # mata o processo inteiro e as areas seguintes (MCP, telemetria) nunca
#   # rodam, violando FR-009 silenciosamente:
#   _setup_apply_state_backend "$PROJECT_PATH"
#
# Cada `if ! fn; then ...` / `fn || rc=$?` isola exatamente UMA area; o
# restante do wizard prossegue com o outcome dela marcado `failed` no
# SetupRunSummary (FR-010), nunca abortando as demais.
#
# Exit codes (contracts/cli-setup.md §1 "Exit codes", alinhado as
# constantes de cli/cstk:30-33):
#   0 run completo (inclui areas puladas/ja-configuradas e --dry-run)
#   1 pelo menos uma area terminou em `failed`
#   2 uso incorreto (flag desconhecida)
#   3 recusa por pre-condicao: fora de raiz de repo git (FR-011), ou
#     terminal nao-interativo sem --dry-run/--yes (FR-007)
#
# Pre-condicoes (contracts/cli-setup.md §1 "Pre-condicoes"), nesta ordem:
#   1. FR-011 — `[ -e "$PROJECT_PATH/.git" ]` (arquivo OU diretorio;
#      git worktree conta, pois `.git` de worktree e um arquivo-ponteiro).
#      Falha -> exit 3, ZERO escrita.
#   2. FR-007 — em mode=interactive, TTY obrigatorio via `require_tty`
#      (cli/lib/ui.sh). Falha -> exit 3 apontando --dry-run/--yes.
#
# Precedencia de modo (FR-006, contracts/cli-setup.md §1):
#   --dry-run presente            -> mode=preview        (nada aplicado)
#   --yes presente, sem --dry-run -> mode=non-interactive
#   nenhum dos dois               -> mode=interactive     (exige TTY)
#
# Flags deliberadamente ausentes (FR-018): nao ha --catalog nem
# equivalente; nenhuma flag de override de catalogo e repassada aos
# comandos delegados. Qualquer flag desconhecida -> exit 2 (uso incorreto).
#
# POSIX sh puro. Sem bash-isms. Deps: as das libs sourceadas (common.sh,
# ui.sh) + test/printf/case built-in.

if [ -n "${_CSTK_SETUP_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_SETUP_LOADED=1

set -eu

# shellcheck source=./common.sh
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"
# shellcheck source=./ui.sh
. "${CSTK_LIB}/ui.sh"

_setup_usage() {
  cat <<'HELP'
cstk setup — wizard guiado de configuracao (hooks, backend de estado,
             MCP de estado, telemetria) para um projeto-alvo

USO:
  cstk setup [--dry-run] [--yes] [--project-path PATH]

FLAGS:
  --dry-run              Preview: mostra o status e o que seria aplicado
                          em cada area, sem escrever nada. Precede --yes
                          se ambas forem passadas.
  --yes                  Nao-interativo: aplica o default recomendado de
                          cada area ainda nao configurada, sem prompt.
  --project-path PATH    Raiz do projeto-alvo (default: diretorio atual).
                          MUST ser raiz de repositorio git.

Sem nenhuma flag de modo, roda interativo (exige TTY) e pergunta area a
area. Sem TTY e sem --dry-run/--yes, falha rapido em vez de bloquear
esperando input (FR-007).

AREAS (ordem fixa): hooks, state-backend, mcp, telemetry.

EXIT CODES:
  0 run completo   1 alguma area falhou   2 uso incorreto
  3 recusado por pre-condicao (fora de repo git, ou sem TTY/--dry-run/--yes)
HELP
}

# _setup_parse_args ARGS...
# Preenche as variaveis globais (prefixo _SU_): _SU_PROJECT_PATH,
# _SU_DRY_RUN (0|1), _SU_YES (0|1), _SU_HELP (0|1).
# Retorno: 0 OK; 2 flag desconhecida ou argumento faltando (uso incorreto).
_setup_parse_args() {
  _SU_PROJECT_PATH="$PWD"
  _SU_DRY_RUN=0
  _SU_YES=0
  _SU_HELP=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        _SU_DRY_RUN=1
        shift
        ;;
      --yes)
        _SU_YES=1
        shift
        ;;
      --project-path)
        if [ "$#" -lt 2 ]; then
          log_error "setup: --project-path requer um valor"
          return 2
        fi
        _SU_PROJECT_PATH="$2"
        shift 2
        ;;
      -h|--help)
        _SU_HELP=1
        shift
        ;;
      *)
        log_error "setup: flag desconhecida: $1"
        log_error "setup: tente 'cstk setup --help'"
        return 2
        ;;
    esac
  done
  return 0
}

# _setup_resolve_mode -> stdout: "preview" | "non-interactive" | "interactive"
# Precedencia FR-006: --dry-run vence --yes; sem nenhuma das duas, interactive.
_setup_resolve_mode() {
  if [ "$_SU_DRY_RUN" = 1 ]; then
    printf 'preview\n'
  elif [ "$_SU_YES" = 1 ]; then
    printf 'non-interactive\n'
  else
    printf 'interactive\n'
  fi
}

# _setup_check_git_root PROJECT_PATH -> 0 se PROJECT_PATH e raiz de repo git
# (FR-011: `.git` arquivo OU diretorio; worktrees contam). 1 caso contrario.
# Pure/read-only — nao escreve nada.
_setup_check_git_root() {
  [ -e "$1/.git" ]
}

setup_main() {
  if ! _setup_parse_args "$@"; then
    return 2
  fi

  if [ "$_SU_HELP" = 1 ]; then
    _setup_usage
    return 0
  fi

  # Pre-condicao 1 (FR-011) — ANTES de qualquer outra coisa, zero escrita
  # em caso de recusa.
  if ! _setup_check_git_root "$_SU_PROJECT_PATH"; then
    log_error "setup: '$_SU_PROJECT_PATH' nao parece raiz de um repositorio git (sem .git)."
    log_error "setup: rode a partir da raiz do projeto-alvo, ou passe --project-path."
    return 3
  fi

  _su_mode=$(_setup_resolve_mode)

  # Pre-condicao 2 (FR-007) — so se aplica em modo interativo.
  if [ "$_su_mode" = "interactive" ]; then
    if ! require_tty; then
      log_error "setup: terminal nao-interativo detectado."
      log_error "setup: use --dry-run (preview) ou --yes (aplica defaults) em vez do modo interativo."
      return 3
    fi
  fi

  # A partir daqui: pre-condicoes satisfeitas, modo resolvido. A
  # orquestracao das 4 areas (hooks, state-backend, mcp, telemetry) e o
  # SetupRunSummary sao adicionados nas FASES 3-7 do backlog
  # (docs/specs/cstk-setup/tasks.md) — este skeleton (FASE 1) cobre
  # apenas dispatch + pre-condicoes.
  log_info "setup: pre-condicoes OK (mode=$_su_mode, project-path=$_SU_PROJECT_PATH)."
  log_info "setup: areas de configuracao ainda nao implementadas nesta versao (FASE 1 de 8)."
  return 0
}
