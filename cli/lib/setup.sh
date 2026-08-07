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
# shellcheck source=./hooks.sh
# hooks.sh e o UNICO arquivo autorizado a referenciar jq (Constitution
# carve-out); setup.sh reusa hooks_main/apply_guard_hooks de la — nenhum
# mecanismo de merge JSON novo (FASE 3, contracts/cli-setup.md §2.4).
. "${CSTK_LIB}/hooks.sh"

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

# ============================================================================
# Area de hooks (FASE 3 — docs/specs/cstk-setup/tasks.md; contract em
# contracts/cli-setup.md §2; data-model.md Entity ConfigurationArea/
# HooksAreaDetail).
# ============================================================================

# _setup_hooks_status_script_path -> imprime o caminho de
# guard-hooks-status.sh. Mesmo padrao de 3 camadas de
# _mcp_runtime_script_path (cli/lib/mcp.sh) / _state_migrate_script_path
# (cli/lib/state.sh): (1) PATH; (2) layout de repo relativo a CSTK_LIB
# (cli/lib -> ../../global/skills/agente-00c-runtime/scripts); (3) layout
# instalado em ~/.claude. Necessario porque testes/CI rodam o CLI da
# arvore do repo (CSTK_LIB=cli/lib) sem o runtime em ~/.claude.
_setup_hooks_status_script_path() {
  if command -v guard-hooks-status.sh >/dev/null 2>&1; then
    command -v guard-hooks-status.sh
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _shs_repo="$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/guard-hooks-status.sh"
    if [ -f "$_shs_repo" ]; then
      printf '%s\n' "$_shs_repo"
      return 0
    fi
  fi
  _shs_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/guard-hooks-status.sh"
  if [ -f "$_shs_default" ]; then
    printf '%s\n' "$_shs_default"
    return 0
  fi
  return 1
}

# _setup_prompt_yn QUESTION -> pergunta em stderr, le resposta em stdin.
# Exit 0 se y/Y/yes/YES; 1 caso contrario (inclusive vazio/EOF). Mesmo
# padrao de _session_prompt_yn (cli/lib/session.sh:333-343).
_setup_prompt_yn() {
  printf '%s ' "$1" >&2
  read -r _spy_ans 2>/dev/null || _spy_ans=""
  case "$_spy_ans" in
    y | Y | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

# _setup_detect_hooks_area PROJECT_PATH
#
# 3 chamadas SEPARADAS a guard-hooks-status.sh (achado SEC-03 —
# contracts/cli-setup.md §2.1-2.3): (1) baseline sem flags; (2)
# --verify-registration isolada; (3) --include-loose-usage isolada.
# NUNCA combinadas numa unica invocacao — um runtime antigo que rejeita
# UMA flag (exit 2) nao pode perder o veredito basico que ele SABE
# responder. 100% read-only (nunca escreve nada).
#
# Preenche globais:
#   _SU_HOOKS_MANDATORY_STATUS  configured|not-configured|divergent|unavailable
#   _SU_HOOKS_MANDATORY_REASON  motivo legivel (vazio quando configured)
#   _SU_HOOKS_DIVERGENT_NAMES   basenames divergentes, espaco-separado
#   _SU_HOOKS_LOOSE_STATUS      configured|not-configured|indeterminate
#
# Regra de escalada (I5 do data-model, achados SEC-01/SEC-02): a chamada
# --verify-registration so pode ESCALAR o veredito da baseline, nunca
# substitui-lo silenciosamente:
#   - qualquer hook com 5a coluna "divergent" -> status=divergent
#     (precede a baseline)
#   - senao, qualquer hook cuja 5a coluna seja "indeterminate" E cuja
#     3a coluna (a MESMA chamada) seja "registered" -> status=unavailable
#     (ambiguidade REAL: algo esta registrado mas a forma canonica nao
#     pode ser confirmada — o caso citado no contrato e o settings.json
#     minificado). Um hook "indeterminate" cuja 3a coluna e "unregistered"
#     NAO escala: e o caso trivial "nada para autenticar" (settings.json
#     ausente ou hook nunca mencionado) — _gh_verify_registration usa o
#     MESMO grep -F que _gh_registered para decidir isso, entao os dois
#     vereditos sao consistentes por construcao. Escalar aqui produziria
#     `unavailable` para TODO projeto ainda nao configurado, contradizendo
#     quickstart.md Scenario 1 (projeto novo, sem settings.json, MUST
#     oferecer configurar hooks — nao reportar "indisponivel").
#   - a chamada --verify-registration inteira com exit 2 (flag rejeitada
#     por runtime desatualizado) -> unavailable incondicional, sem colunas
#     para inspecionar (contrato §2.3).
_setup_detect_hooks_area() {
  _sdh_pap=$1
  _SU_HOOKS_MANDATORY_STATUS="unavailable"
  _SU_HOOKS_MANDATORY_REASON="nao foi possivel localizar guard-hooks-status.sh (rode 'cstk install' ou 'cstk update' antes)"
  _SU_HOOKS_DIVERGENT_NAMES=""
  _SU_HOOKS_LOOSE_STATUS="indeterminate"

  if ! _sdh_script=$(_setup_hooks_status_script_path); then
    return 0
  fi

  # (1) baseline — SEM flags (contracts/cli-setup.md §2.1)
  if _sdh_baseline_out=$(sh "$_sdh_script" check --projeto-alvo-path "$_sdh_pap" --quiet 2>/dev/null); then
    _sdh_baseline_rc=0
  else
    _sdh_baseline_rc=$?
  fi
  case "$_sdh_baseline_rc" in
    0)
      _SU_HOOKS_MANDATORY_STATUS="configured"
      _SU_HOOKS_MANDATORY_REASON=""
      ;;
    1)
      _SU_HOOKS_MANDATORY_STATUS="not-configured"
      _SU_HOOKS_MANDATORY_REASON="um ou mais hooks obrigatorios ausentes, nao registrados ou desatualizados"
      ;;
    *)
      _SU_HOOKS_MANDATORY_STATUS="unavailable"
      _SU_HOOKS_MANDATORY_REASON="guard-hooks-status.sh check (baseline) retornou uso incorreto (exit $_sdh_baseline_rc)"
      ;;
  esac

  # (2) --verify-registration — SEPARADA (achado SEC-03, §2.3, FR-016)
  if _sdh_verify_out=$(sh "$_sdh_script" check --projeto-alvo-path "$_sdh_pap" --quiet --verify-registration 2>/dev/null); then
    _sdh_verify_rc=0
  else
    _sdh_verify_rc=$?
  fi
  if [ "$_sdh_verify_rc" = 2 ]; then
    _SU_HOOKS_MANDATORY_STATUS="unavailable"
    _SU_HOOKS_MANDATORY_REASON="verificacao de autenticidade do registro indisponivel (runtime desatualizado) — nao foi possivel confirmar nem refutar"
  else
    _sdh_divergent=""
    _sdh_ambiguous=0
    while IFS='	' read -r _h _pf _rg _fr _vr; do
      [ -n "$_h" ] || continue
      case "$_vr" in
        divergent)
          _sdh_divergent="${_sdh_divergent:+$_sdh_divergent }$_h"
          ;;
        indeterminate)
          [ "$_rg" = "registered" ] && _sdh_ambiguous=1
          ;;
      esac
    done <<SDHVR
$_sdh_verify_out
SDHVR
    if [ -n "$_sdh_divergent" ]; then
      _SU_HOOKS_MANDATORY_STATUS="divergent"
      _SU_HOOKS_DIVERGENT_NAMES="$_sdh_divergent"
      _SU_HOOKS_MANDATORY_REASON="registro nao-canonico detectado para: $_sdh_divergent"
    elif [ "$_sdh_ambiguous" = 1 ]; then
      _SU_HOOKS_MANDATORY_STATUS="unavailable"
      _SU_HOOKS_MANDATORY_REASON="autenticidade do registro nao pode ser confirmada nem refutada (layout do settings.json impede atribuicao por linha)"
    fi
  fi

  # (3) --include-loose-usage — SEPARADA (§2.2); alimenta SO
  # loose_usage_status, NUNCA a linha acima (hook obrigatorio).
  if _sdh_loose_out=$(sh "$_sdh_script" check --projeto-alvo-path "$_sdh_pap" --quiet --include-loose-usage 2>/dev/null); then
    _sdh_loose_rc=0
  else
    _sdh_loose_rc=$?
  fi
  if [ "$_sdh_loose_rc" = 2 ]; then
    _SU_HOOKS_LOOSE_STATUS="indeterminate"
  else
    _sdh_loose_line=$(printf '%s\n' "$_sdh_loose_out" | awk -F'\t' '$1=="posttooluse-loose-usage.sh"{print;exit}')
    if [ -z "$_sdh_loose_line" ]; then
      _SU_HOOKS_LOOSE_STATUS="indeterminate"
    else
      _sdh_l_present=$(printf '%s' "$_sdh_loose_line" | awk -F'\t' '{print $2}')
      _sdh_l_reg=$(printf '%s' "$_sdh_loose_line" | awk -F'\t' '{print $3}')
      _sdh_l_fresh=$(printf '%s' "$_sdh_loose_line" | awk -F'\t' '{print $4}')
      if [ "$_sdh_l_present" = "present" ] && [ "$_sdh_l_reg" = "registered" ] && [ "$_sdh_l_fresh" != "stale" ]; then
        _SU_HOOKS_LOOSE_STATUS="configured"
      else
        _SU_HOOKS_LOOSE_STATUS="not-configured"
      fi
    fi
  fi
  return 0
}

# _setup_classify_hooks_install_stderr STDERR_TEXT ->
# merged|paste-instructed|hooks-only|not-applicable|error|unknown
#
# `hooks_main install` (cli/lib/hooks.sh) so expoe exit code (0 para
# merged/paste-instructed/hooks-only; 1 para not-applicable/error) — os 5
# estados internos de apply_guard_hooks nao chegam ao caller por outro
# canal. Esta funcao INTERPRETA o texto de log ja documentado e estavel
# que hooks_main emite para cada estado (cli/lib/hooks.sh, case
# `$_hooks_state` em `hooks_main`) — nao reimplementa a decisao de estado,
# so classifica o relatorio que o proprio delegado ja produziu (task
# 3.2.3): garante que `paste-instructed`/`hooks-only` (jq ausente /
# catalogo incompleto) nunca virem `applied` silencioso no wizard.
_setup_classify_hooks_install_stderr() {
  case "$1" in
    *"provisionados e registrados em"* | *"provisionaria os hooks 00c em"*)
      printf 'merged\n'
      ;;
    *"REGISTRO em settings.json"*)
      printf 'paste-instructed\n'
      ;;
    *"settings.snippet.json ausente no catalogo"*)
      printf 'hooks-only\n'
      ;;
    *"catalogo nao trouxe os hooks 00c"*)
      printf 'not-applicable\n'
      ;;
    *"falha ao provisionar"*)
      printf 'error\n'
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

# _setup_run_hooks_area PROJECT_PATH MODE DRY_RUN
#
# Orquestra a area 'hooks' de ponta a ponta (FASE 3):
#   1. Deteccao read-only (sempre roda, mesmo em --dry-run)
#   2. Apresentacao do status ANTES de oferecer a acao (FR-002)
#   3. `divergent`/`unavailable` -> outcome=failed, ZERO chamada de
#      aplicacao (I6, FR-016) — falha fechada com remediacao em 2 etapas
#   4. `configured` -> outcome=already-configured, ZERO chamada (I1, FR-003)
#   5. `not-configured` -> decide (prompt interativo ou default de --yes)
#      a instalacao dos hooks obrigatorios E, como escolha DISTINTA
#      (FR-008), a do hook opt-in de loose usage (default skip)
#
# Preenche _SU_HOOKS_OUTCOME (already-configured|applied|skipped|failed) e
# _SU_HOOKS_OUTCOME_REASON (motivo legivel; nao vazio em failed e nos
# avisos pendentes de applied — task 3.2.3).
_setup_run_hooks_area() {
  _srh_pap=$1
  _srh_mode=$2
  _srh_dry=$3

  _setup_detect_hooks_area "$_srh_pap"

  log_info "setup: [hooks] status atual (obrigatorios) = $_SU_HOOKS_MANDATORY_STATUS"
  if [ -n "$_SU_HOOKS_MANDATORY_REASON" ]; then
    log_info "setup: [hooks] motivo: $_SU_HOOKS_MANDATORY_REASON"
  fi
  log_info "setup: [hooks] loose usage (opt-in, escolha distinta — FR-008): $_SU_HOOKS_LOOSE_STATUS"

  case "$_SU_HOOKS_MANDATORY_STATUS" in
    configured)
      _SU_HOOKS_OUTCOME="already-configured"
      _SU_HOOKS_OUTCOME_REASON=""
      log_info "setup: [hooks] ja configurado — nenhuma chamada de aplicacao (I1)."
      return 0
      ;;
    divergent | unavailable)
      _SU_HOOKS_OUTCOME="failed"
      _SU_HOOKS_OUTCOME_REASON="$_SU_HOOKS_MANDATORY_REASON"
      log_error "setup: [hooks] $_SU_HOOKS_MANDATORY_REASON"
      if [ "$_SU_HOOKS_MANDATORY_STATUS" = "divergent" ]; then
        log_error "setup: [hooks] remediacao (duas etapas — reescrever por cima NAO substitui o divergente, o merge faz o target vencer): (1) remova a entrada divergente de $_srh_pap/.claude/settings.json; (2) so entao rode 'cstk hooks install --project-path $_srh_pap'."
      fi
      log_error "setup: [hooks] nenhuma chamada de aplicacao sera feita (I6)."
      return 0
      ;;
  esac

  # not-configured a partir daqui.
  if [ "$_srh_dry" = 1 ]; then
    _SU_HOOKS_OUTCOME="skipped"
    _SU_HOOKS_OUTCOME_REASON="preview: nenhuma alteracao aplicada"
    log_info "setup: [hooks] preview — instalaria os hooks obrigatorios (nao aplicado)."
    return 0
  fi

  _srh_accept_mandatory=1
  if [ "$_srh_mode" = "interactive" ]; then
    if ! _setup_prompt_yn "setup: [hooks] instalar os hooks obrigatorios agora? [y/N]"; then
      _srh_accept_mandatory=0
    fi
  fi
  if [ "$_srh_accept_mandatory" != 1 ]; then
    _SU_HOOKS_OUTCOME="skipped"
    _SU_HOOKS_OUTCOME_REASON="recusado pelo usuario"
    log_info "setup: [hooks] recusado — hooks obrigatorios NAO instalados."
    return 0
  fi

  # Escolha DISTINTA (FR-008, US4) do hook opt-in de loose usage. Default
  # em --yes = skip (data-model.md loose_usage_choice — unica sub-area
  # cujo default recomendado e "nao").
  _srh_with_loose=0
  if [ "$_srh_mode" = "interactive" ]; then
    if _setup_prompt_yn "setup: [hooks] tambem habilitar captura de consumo avulso (loose usage, opt-in, default nao)? [y/N]"; then
      _srh_with_loose=1
    fi
  fi

  if ! _srh_err_file=$(mktemp 2>/dev/null); then
    _SU_HOOKS_OUTCOME="failed"
    _SU_HOOKS_OUTCOME_REASON="mktemp falhou ao preparar captura de diagnostico de 'hooks install'"
    log_error "setup: [hooks] $_SU_HOOKS_OUTCOME_REASON"
    return 0
  fi

  if [ "$_srh_with_loose" = 1 ]; then
    if hooks_main install --project-path "$_srh_pap" --with-loose-usage 2>"$_srh_err_file"; then
      _srh_rc=0
    else
      _srh_rc=$?
    fi
  else
    if hooks_main install --project-path "$_srh_pap" 2>"$_srh_err_file"; then
      _srh_rc=0
    else
      _srh_rc=$?
    fi
  fi
  _srh_stderr=$(cat "$_srh_err_file" 2>/dev/null) || _srh_stderr=""
  rm -f "$_srh_err_file" 2>/dev/null || :

  _srh_state=$(_setup_classify_hooks_install_stderr "$_srh_stderr")

  case "$_srh_state" in
    merged)
      _SU_HOOKS_OUTCOME="applied"
      _SU_HOOKS_OUTCOME_REASON=""
      log_info "setup: [hooks] aplicado (merged)."
      ;;
    paste-instructed)
      _SU_HOOKS_OUTCOME="applied"
      _SU_HOOKS_OUTCOME_REASON="jq ausente — registro em settings.json exige colagem manual (bloco impresso acima); sem isso os hooks NAO rodam"
      log_warn "setup: [hooks] $_SU_HOOKS_OUTCOME_REASON"
      ;;
    hooks-only)
      _SU_HOOKS_OUTCOME="applied"
      _SU_HOOKS_OUTCOME_REASON="settings.snippet.json ausente no catalogo — hooks copiados mas NAO registrados; atualize o catalogo (cstk update)"
      log_warn "setup: [hooks] $_SU_HOOKS_OUTCOME_REASON"
      ;;
    not-applicable)
      _SU_HOOKS_OUTCOME="failed"
      _SU_HOOKS_OUTCOME_REASON="catalogo local nao trouxe os hooks 00c (exit $_srh_rc)"
      log_error "setup: [hooks] $_SU_HOOKS_OUTCOME_REASON"
      ;;
    error | unknown)
      _SU_HOOKS_OUTCOME="failed"
      _SU_HOOKS_OUTCOME_REASON="hooks install falhou (exit $_srh_rc)"
      log_error "setup: [hooks] $_SU_HOOKS_OUTCOME_REASON"
      ;;
  esac
  return 0
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
  # orquestracao das demais 3 areas (state-backend, mcp, telemetry) e o
  # SetupRunSummary consolidado sao adicionados nas FASES 4-7 do backlog
  # (docs/specs/cstk-setup/tasks.md) — esta versao (FASE 3) cobre
  # dispatch + pre-condicoes + area de hooks.
  log_info "setup: pre-condicoes OK (mode=$_su_mode, project-path=$_SU_PROJECT_PATH)."

  _setup_run_hooks_area "$_SU_PROJECT_PATH" "$_su_mode" "$_SU_DRY_RUN"
  log_info "setup: [hooks] outcome=$_SU_HOOKS_OUTCOME"

  log_info "setup: areas restantes (state-backend, mcp, telemetry) ainda nao implementadas nesta versao (FASE 3 de 8)."

  if [ "$_SU_HOOKS_OUTCOME" = "failed" ]; then
    return 1
  fi
  return 0
}
