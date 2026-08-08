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
# hooks.sh referencia jq sob o carve-out da Constitution (amendment 1.1.0);
# setup.sh reusa hooks_main/apply_guard_hooks de la — nenhum mecanismo de
# merge JSON novo (FASE 3, contracts/cli-setup.md §2.4). hooks.sh ja
# sourcea plugin-detect.sh (outro arquivo com uso confinado de jq, feature
# claude-plugin-packaging FASE 6) — plugin_enabled/plugin_hooks_present
# ficam disponiveis aqui transitivamente; sourceado de novo abaixo so por
# clareza de dependencia direta (guard idempotente, no-op).
. "${CSTK_LIB}/hooks.sh"
# shellcheck source=./plugin-detect.sh
. "${CSTK_LIB}/plugin-detect.sh"
# shellcheck source=./config.sh
# config.sh delega puramente a state-backend.sh (fonte unica de decisao de
# backend, Decision 2 de state-backend-config) — setup.sh reusa
# config_state_backend_resolve/enable_sqlite de la (FASE 4, contracts/
# cli-setup.md §3). Nenhuma logica de parsing/decisao nova aqui.
. "${CSTK_LIB}/config.sh"
# shellcheck source=./doctor.sh
# doctor.sh fornece _doctor_deps_run, reusada COMO TEXTO DE DIAGNOSTICO
# quando a area state-backend fica unavailable (task 4.4.1) — nenhuma
# reimplementacao de deteccao de sqlite3/jq.
. "${CSTK_LIB}/doctor.sh"
# shellcheck source=./mcp.sh
# mcp.sh e a lib DONA da area MCP (contracts/cli-setup.md §4) — setup.sh
# reusa _mcp_registration_status (deteccao, FASE 2.3) e _mcp_cmd_install
# (aplicacao) de la, sem duplicar parsing de .mcp.json nem invocar docker
# diretamente (FASE 5, task 5.2/5.3).
. "${CSTK_LIB}/mcp.sh"

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
  --verbose              Mostra o progresso detalhado de cada area (status
                          detectado, decisoes, instrucoes de telemetria).
                          Sem ela, o wizard mostra apenas as perguntas, uma
                          linha [OK] por area bem-sucedida e o summary;
                          erros e avisos aparecem sempre.

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
  _SU_VERBOSE=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        _SU_DRY_RUN=1
        shift
        ;;
      --verbose)
        _SU_VERBOSE=1
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
# (cli/lib -> ../../plugins/cstk/skills/agente-00c-runtime/scripts); (3) layout
# instalado em ~/.claude. Necessario porque testes/CI rodam o CLI da
# arvore do repo (CSTK_LIB=cli/lib) sem o runtime em ~/.claude.
_setup_hooks_status_script_path() {
  if command -v guard-hooks-status.sh >/dev/null 2>&1; then
    command -v guard-hooks-status.sh
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _shs_repo="$CSTK_LIB/../../plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh"
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

# _setup_otel_script_path -> mesma cadeia de resolucao de
# _setup_hooks_status_script_path (command -v -> fallback relativo a
# CSTK_LIB -> fallback $HOME/.claude), agora para `otel-usage.sh`
# (FASE 6, contracts/cli-setup.md §5.1). Ecoa o path em stdout; exit 1 se
# nao encontrado em nenhuma das 3 fontes.
_setup_otel_script_path() {
  if command -v otel-usage.sh >/dev/null 2>&1; then
    command -v otel-usage.sh
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _sot_repo="$CSTK_LIB/../../plugins/cstk/skills/agente-00c-runtime/scripts/otel-usage.sh"
    if [ -f "$_sot_repo" ]; then
      printf '%s\n' "$_sot_repo"
      return 0
    fi
  fi
  _sot_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/otel-usage.sh"
  if [ -f "$_sot_default" ]; then
    printf '%s\n' "$_sot_default"
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

# _setup_info MSG — linha de progresso/detalhe: visivel apenas com
# --verbose. O default e silencioso (pedido do operador, 2026-08-07):
# sucesso mostra so as perguntas + uma linha [OK] por area; erros e avisos
# (log_error/log_warn) aparecem SEMPRE, independente de --verbose.
_setup_info() {
  if [ "${_SU_VERBOSE:-0}" = 1 ]; then
    log_info "$1"
  fi
  return 0
}

# _setup_area_ok NAME OUTCOME [NOTE] — linha compacta de sucesso da area,
# em stderr (progresso, nao dado — Constitution II), com [OK] a esquerda.
# Areas failed NUNCA passam por aqui: o caminho de erro ja logou o
# diagnostico completo via log_error.
_setup_area_ok() {
  case "$2" in
    already-configured) _sao_label="ja configurado" ;;
    applied)            _sao_label="aplicado" ;;
    skipped)            _sao_label="pulado" ;;
    *)                  _sao_label="$2" ;;
  esac
  if [ -n "${3:-}" ]; then
    printf '[OK] %s — %s (%s)\n' "$1" "$_sao_label" "$3" >&2
  else
    printf '[OK] %s — %s\n' "$1" "$_sao_label" >&2
  fi
  return 0
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

  # Dedup plugin-vence (FR-005, contracts/cli-plugin-awareness.md §cstk
  # setup) — MESMA regra de tres condicoes de hooks_main install (cli/lib/
  # hooks.sh): so pula a etapa quando plugin_enabled E plugin_hooks_present
  # (achado F4/dec-027: habilitado nao implica funcional). Roda ANTES da
  # deteccao classica para nao gastar 3 chamadas a guard-hooks-status.sh
  # quando o plugin ja resolve tudo.
  if plugin_enabled cstk; then
    if plugin_hooks_present cstk; then
      _SU_HOOKS_OUTCOME="already-configured"
      _SU_HOOKS_OUTCOME_REASON="plugin 'cstk' habilitado e ja provê hooks/hooks.json — etapa de hooks pulada (dedup, plugin vence)"
      _setup_info "setup: [hooks] $_SU_HOOKS_OUTCOME_REASON"
      return 0
    else
      _setup_info "setup: [hooks] plugin 'cstk' habilitado mas hooks/hooks.json NAO encontrado no install path — instalacao do plugin parece incompleta (F4); prosseguindo com deteccao classica"
    fi
  fi

  _setup_detect_hooks_area "$_srh_pap"

  _setup_info "setup: [hooks] status atual (obrigatorios) = $_SU_HOOKS_MANDATORY_STATUS"
  if [ -n "$_SU_HOOKS_MANDATORY_REASON" ]; then
    _setup_info "setup: [hooks] motivo: $_SU_HOOKS_MANDATORY_REASON"
  fi
  _setup_info "setup: [hooks] loose usage (opt-in, escolha distinta — FR-008): $_SU_HOOKS_LOOSE_STATUS"

  case "$_SU_HOOKS_MANDATORY_STATUS" in
    configured)
      _SU_HOOKS_OUTCOME="already-configured"
      _SU_HOOKS_OUTCOME_REASON=""
      _setup_info "setup: [hooks] ja configurado — nenhuma chamada de aplicacao (I1)."
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
    _setup_info "setup: [hooks] preview — instalaria os hooks obrigatorios (nao aplicado)."
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
    _setup_info "setup: [hooks] recusado — hooks obrigatorios NAO instalados."
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
      _setup_info "setup: [hooks] aplicado (merged)."
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

# ============================================================================
# Area de state backend (FASE 4 — tasks.md; contract em
# contracts/cli-setup.md §3; data-model.md Entity ConfigurationArea, linha
# `state-backend`, e Nota "unavailable").
#
# **Investigacao empirica (task 4.1)**: os 6 valores de `reason=`
# produzidos por `_sb_cmd_resolve` (state-backend.sh:234-269) foram
# enumerados rodando `resolve` nos 4 cenarios exigidos (nunca-configurado,
# `state_backend=json` explicito, `state_backend=sqlite` explicito, config
# ausente) sobre um `HOME` sandboxado real:
#   nunca-configurado                          (config ausente OU sem a chave)
#   config-invalida                            (linha sem `=`)
#   json-explicito                             (`state_backend=json`)
#   configurado-dependencia-adequada           (`state_backend=sqlite` + sqlite3 >= 3.45.1)
#   configurado-dependencia-abaixo-do-minimo   (`state_backend=sqlite` + sqlite3 < 3.45.1 — via codigo, `_sb_version_ge`)
#   configurado-dependencia-ausente            (`state_backend=sqlite` + sqlite3 ausente do PATH — via codigo)
# Nenhum valor alem destes 6 e produzido pelo case fechado de
# `_sb_cmd_resolve` (verificado por leitura de state-backend.sh:234-269) —
# nunca inventado (Constitution VI).
#
# **`config_state_backend_capability`** (cli/lib/config.sh:90) NAO checa
# sqlite3 — imprime `_SB_CAPABILITY_TOKEN` fixo ("1", state-backend.sh:72),
# um identificador de versao do RUNTIME usado so internamente por
# `enable-sqlite` (P8, checagem de catalogo instalado). Nao e a fonte para
# detectar dependencia ausente/abaixo do minimo — essa informacao ja vem
# EMBUTIDA no `reason=` de `resolve` quando o backend foi declarado
# sqlite (o caminho `declarado -> sqlite` de `_sb_cmd_resolve` chama
# `_sb_check_sqlite3` internamente). Portanto a area NUNCA chama
# `capability` para decidir status — o mapeamento abaixo e suficiente e
# nao duplica logica de decisao (Decision 2).
#
# **Mapeamento reason -> status** (reconcilia data-model.md com a US2 AC3
# — "escolha deliberada de manter o backend legado NAO e migrada nem
# reportada como not-configured"):
#   nunca-configurado, config-invalida                    -> not-configured (nenhuma escolha feita ainda)
#   json-explicito, configurado-dependencia-adequada       -> configured   (escolha explicita e funcional — inclui US2 AC3)
#   configurado-dependencia-ausente,
#   configurado-dependencia-abaixo-do-minimo               -> unavailable  (escolha sqlite feita, dependencia quebrada; um `enable-sqlite` recusaria com exit 3 sem nenhuma escrita — data-model.md Nota "unavailable")
# ============================================================================

# _setup_state_backend_status_from_reason REASON -> stdout:
# configured|not-configured|unavailable. Fail-closed (I5): reason fora do
# dominio conhecido (runtime futuro/desconhecido) NUNCA vira 'configured'.
_setup_state_backend_status_from_reason() {
  case "$1" in
    nunca-configurado | config-invalida)
      printf 'not-configured\n'
      ;;
    json-explicito | configurado-dependencia-adequada)
      printf 'configured\n'
      ;;
    configurado-dependencia-ausente | configurado-dependencia-abaixo-do-minimo)
      printf 'unavailable\n'
      ;;
    *)
      printf 'unavailable\n'
      ;;
  esac
}

# _setup_detect_state_backend_area -> preenche globais:
#   _SU_SB_EFFECTIVE  sqlite|json (cru de resolve)
#   _SU_SB_REASON     motivo cru de resolve
#   _SU_SB_STATUS     configured|not-configured|unavailable
_setup_detect_state_backend_area() {
  _SU_SB_EFFECTIVE="json"
  _SU_SB_REASON="config_state_backend_resolve indisponivel"
  _SU_SB_STATUS="unavailable"

  if ! _sdsb_out=$(config_state_backend_resolve 2>/dev/null); then
    return 0
  fi
  if [ -z "$_sdsb_out" ]; then
    return 0
  fi

  _sdsb_old_ifs=$IFS
  IFS='
'
  for _sdsb_line in $_sdsb_out; do
    case "$_sdsb_line" in
      effective_backend=*) _SU_SB_EFFECTIVE=${_sdsb_line#effective_backend=} ;;
      reason=*) _SU_SB_REASON=${_sdsb_line#reason=} ;;
    esac
  done
  IFS=$_sdsb_old_ifs

  _SU_SB_STATUS=$(_setup_state_backend_status_from_reason "$_SU_SB_REASON")
  return 0
}

# _setup_run_state_backend_area PROJECT_PATH MODE DRY_RUN
#
# Orquestra a area 'state-backend' de ponta a ponta (FASE 4):
#   1. Deteccao read-only (sempre roda, mesmo em --dry-run) — task 4.2.1
#   2. FR-017: rotulo de ESCOPO GLOBAL exibido SEMPRE, antes de qualquer
#      decisao e mesmo em --dry-run — task 4.2.3
#   3. `unavailable` -> outcome=failed, ZERO chamada de aplicacao (mesmo
#      padrao I6 de hooks); diagnostico de `_doctor_deps_run` anexado —
#      task 4.3.3/4.4.1
#   4. `configured` -> outcome=already-configured, ZERO chamada (I1) —
#      cobre tanto sqlite funcional quanto json deliberado (US2 AC3)
#   5. `not-configured` -> decide: interativo pergunta sempre; `--yes`
#      SO aplica quando reason indica ausencia de configuracao (task
#      4.1.3 + achado SEC-04 — opt-in equivalente ao de loose-usage: o
#      aviso FR-017 explicito + o escopo restrito a "nunca decidiu nada"
#      sao o sinal equivalente; nunca migra json-explicito nem re-tenta
#      dependencia quebrada, que ja caiu em unavailable acima)
#
# Preenche _SU_SB_OUTCOME (already-configured|applied|skipped|failed) e
# _SU_SB_OUTCOME_REASON (motivo legivel).
_setup_run_state_backend_area() {
  _srsb_pap=$1
  _srsb_mode=$2
  _srsb_dry=$3

  _setup_detect_state_backend_area

  # FR-017 — rotulo de escopo GLOBAL antes de qualquer decisao, SEMPRE que
  # uma escrita global e possivel ou previewada (status not-configured,
  # inclusive em --dry-run) e sempre em --verbose. Quando ja configurado /
  # unavailable nenhuma escrita e possivel — em modo silencioso o rotulo
  # seria ruido sem acao associada (ajuste de UX 2026-08-07; intencao do
  # FR-017 preservada: o aviso precede toda escrita global possivel). As
  # outras 3 areas NAO carregam este rotulo.
  if [ "${_SU_VERBOSE:-0}" = 1 ] || [ "$_SU_SB_STATUS" = "not-configured" ]; then
    log_info "setup: [state-backend] ESCOPO GLOBAL — esta area escreve em \$HOME/.claude/cstk/config e vale para TODOS os projetos desta maquina, nao apenas $_srsb_pap."
  fi
  _setup_info "setup: [state-backend] status atual = $_SU_SB_STATUS (effective_backend=$_SU_SB_EFFECTIVE, reason=$_SU_SB_REASON)"

  case "$_SU_SB_STATUS" in
    configured)
      _SU_SB_OUTCOME="already-configured"
      _SU_SB_OUTCOME_REASON=""
      _setup_info "setup: [state-backend] ja configurado — nenhuma chamada de aplicacao (I1)."
      return 0
      ;;
    unavailable)
      _SU_SB_OUTCOME="failed"
      _SU_SB_OUTCOME_REASON="$_SU_SB_REASON"
      log_error "setup: [state-backend] $_SU_SB_REASON"
      if command -v _doctor_deps_run >/dev/null 2>&1; then
        # `_doctor_deps_run` retorna exit 1 quando ha anomalia — que e
        # EXATAMENTE o caso em que estamos exibindo o diagnostico. Nao
        # usar `|| _srsb_diag=""` aqui: sob `||`, a atribuicao ja
        # concluida seria sobrescrita por string vazia so por causa do
        # exit != 0 do lado direito, apagando o proprio texto que
        # queremos mostrar.
        if _srsb_diag=$(_doctor_deps_run 2>/dev/null); then :; else :; fi
        if [ -n "$_srsb_diag" ]; then
          log_error "setup: [state-backend] diagnostico (cstk doctor --deps):"
          printf '%s\n' "$_srsb_diag" >&2
        fi
      fi
      log_error "setup: [state-backend] nenhuma chamada de aplicacao sera feita."
      return 0
      ;;
  esac

  # not-configured a partir daqui.
  if [ "$_srsb_dry" = 1 ]; then
    _SU_SB_OUTCOME="skipped"
    _SU_SB_OUTCOME_REASON="preview: nenhuma alteracao aplicada"
    _setup_info "setup: [state-backend] preview — ativaria state_backend=sqlite em \$HOME/.claude/cstk/config (escopo global, nao aplicado)."
    return 0
  fi

  _srsb_accept=0
  if [ "$_srsb_mode" = "interactive" ]; then
    if _setup_prompt_yn "setup: [state-backend] ativar backend sqlite GLOBALMENTE (\$HOME/.claude/cstk/config, afeta todos os projetos)? [y/N]"; then
      _srsb_accept=1
    fi
  else
    # --yes (non-interactive): SEC-04 — so aplica quando reason indica
    # AUSENCIA de configuracao (task 4.1.3); preserva US2 AC3 (json
    # deliberado nunca migra) e nunca re-tenta dependencia quebrada
    # (unavailable, tratado acima).
    case "$_SU_SB_REASON" in
      nunca-configurado | config-invalida)
        _srsb_accept=1
        ;;
    esac
  fi

  if [ "$_srsb_accept" != 1 ]; then
    _SU_SB_OUTCOME="skipped"
    _SU_SB_OUTCOME_REASON="recusado pelo usuario, ou --yes sem sinal equivalente de opt-in (SEC-04) para reason=$_SU_SB_REASON"
    _setup_info "setup: [state-backend] nao aplicado — $_SU_SB_OUTCOME_REASON"
    return 0
  fi

  if _srsb_apply_out=$(config_state_backend_enable_sqlite 2>&1); then
    _srsb_rc=0
  else
    _srsb_rc=$?
  fi

  if [ "$_srsb_rc" = 0 ]; then
    _SU_SB_OUTCOME="applied"
    _SU_SB_OUTCOME_REASON=""
    _setup_info "setup: [state-backend] aplicado (state_backend=sqlite, escopo global)."
  else
    _SU_SB_OUTCOME="failed"
    _SU_SB_OUTCOME_REASON="enable-sqlite falhou (exit $_srsb_rc): $_srsb_apply_out"
    log_error "setup: [state-backend] $_SU_SB_OUTCOME_REASON"
    if [ "$_srsb_rc" = 3 ] && command -v _doctor_deps_run >/dev/null 2>&1; then
      # Ver comentario acima (case unavailable) — nao usar `|| X=""` aqui,
      # apagaria o diagnostico capturado quando `_doctor_deps_run` sinaliza
      # anomalia via exit 1.
      if _srsb_diag=$(_doctor_deps_run 2>/dev/null); then :; else :; fi
      if [ -n "$_srsb_diag" ]; then
        log_error "setup: [state-backend] diagnostico (cstk doctor --deps):"
        printf '%s\n' "$_srsb_diag" >&2
      fi
    fi
  fi
  return 0
}

# ============================================================================
# Area de MCP (FASE 5 — tasks.md; contract em contracts/cli-setup.md §4;
# data-model.md Entity ConfigurationArea, linha `mcp`).
#
# Reusa `_mcp_registration_status` (cli/lib/mcp.sh, FASE 2.3) para
# deteccao e `_mcp_cmd_install` (cli/lib/mcp.sh) para aplicacao — NENHUMA
# reimplementacao de parsing de .mcp.json nem de invocacao de docker
# aqui (mesmo principio de state-backend reusar config_state_backend_*).
# ============================================================================

# _setup_run_mcp_area PROJECT_PATH MODE DRY_RUN
#
# Orquestra a area 'mcp' de ponta a ponta (FASE 5):
#   1. Deteccao read-only via _mcp_registration_status (sempre roda, mesmo
#      em --dry-run) — task 5.1.1
#   2. Apresentacao do status ANTES de oferecer a acao (FR-002) — task 5.1.2
#   3. `configured` -> outcome=already-configured, ZERO chamada (I1) —
#      task 5.2.1
#   4. `divergent` -> outcome=failed, ZERO chamada de aplicacao (I6,
#      FR-016), com remediacao em DUAS etapas — task 5.3 (nunca
#      already-configured, nunca sobrescrita silenciosa: `_mcp_cmd_install`
#      faz merge com o target vencendo, entao uma entrada divergente
#      SOBREVIVE a um novo install — contracts/cli-setup.md §4.1)
#   5. `not-configured` -> decide (prompt interativo ou default de --yes,
#      que SEMPRE aplica — FR-015, sem opt-in distinto como state-backend);
#      aplica `cstk mcp install` MESMO sem Docker detectado, emitindo
#      aviso claro (task 5.2.3) — o registro fica inerte sem Docker, mas
#      o start das execucoes ja degrada sozinho para bash-fallback
#
# Preenche _SU_MCP_OUTCOME (already-configured|applied|skipped|failed) e
# _SU_MCP_OUTCOME_REASON (motivo legivel; nao vazio em failed e nos
# avisos pendentes de applied — task 5.2.4/5.2.5, mesmo tratamento de
# 3.2.3/3.2.5 para a area de hooks).
_setup_run_mcp_area() {
  _srm_pap=$1
  _srm_mode=$2
  _srm_dry=$3

  if ! _srm_status=$(_mcp_registration_status "$_srm_pap"); then
    _srm_status="divergent"
  fi

  # FR-002 — status exibido ANTES de qualquer decisao de acao.
  _setup_info "setup: [mcp] status atual = $_srm_status"

  case "$_srm_status" in
    configured)
      _SU_MCP_OUTCOME="already-configured"
      _SU_MCP_OUTCOME_REASON=""
      _setup_info "setup: [mcp] ja configurado — nenhuma chamada de aplicacao (I1)."
      return 0
      ;;
    divergent)
      _SU_MCP_OUTCOME="failed"
      _SU_MCP_OUTCOME_REASON="entrada mcpServers.cstk-state em $_srm_pap/.mcp.json aponta para fora do catalogo do toolkit"
      log_error "setup: [mcp] $_SU_MCP_OUTCOME_REASON"
      log_error "setup: [mcp] remediacao (duas etapas — 'cstk mcp install' NAO sobrescreve entrada divergente, o merge faz o target vencer): (1) remova a entrada mcpServers.cstk-state de $_srm_pap/.mcp.json; (2) so entao rode 'cstk mcp install --project-path $_srm_pap'."
      log_error "setup: [mcp] nenhuma chamada de aplicacao sera feita (I6)."
      return 0
      ;;
  esac

  # not-configured a partir daqui.
  if [ "$_srm_dry" = 1 ]; then
    _SU_MCP_OUTCOME="skipped"
    _SU_MCP_OUTCOME_REASON="preview: nenhuma alteracao aplicada"
    _setup_info "setup: [mcp] preview — registraria mcpServers.cstk-state em $_srm_pap/.mcp.json (nao aplicado)."
    return 0
  fi

  _srm_accept=1
  if [ "$_srm_mode" = "interactive" ]; then
    if ! _setup_prompt_yn "setup: [mcp] registrar o servidor de estado MCP (mcpServers.cstk-state) agora? [y/N]"; then
      _srm_accept=0
    fi
  fi
  # --yes (non-interactive): FR-015 — SEMPRE tenta aplicar como default
  # recomendado, mesmo sem Docker detectado (sem opt-in distinto, ao
  # contrario da area state-backend).

  if [ "$_srm_accept" != 1 ]; then
    _SU_MCP_OUTCOME="skipped"
    _SU_MCP_OUTCOME_REASON="recusado pelo usuario"
    _setup_info "setup: [mcp] recusado — mcpServers.cstk-state NAO registrado."
    return 0
  fi

  # FR-015/task 5.2.3 — SOMENTE `command -v docker` para o TEXTO do
  # aviso; NUNCA invocar docker funcionalmente aqui (mcp-docker.sh e o
  # UNICO ponto autorizado, e nao e chamado por esta area).
  _srm_docker_warning=""
  if ! command -v docker >/dev/null 2>&1; then
    _srm_docker_warning="Docker nao encontrado no PATH — o registro ficara INERTE ate Docker estar disponivel; execucoes 00c degradam sozinhas para bash-fallback nesse meio-tempo."
  fi

  if _srm_install_out=$(_mcp_cmd_install --project-path "$_srm_pap" 2>&1); then
    _srm_rc=0
  else
    _srm_rc=$?
  fi

  if [ "$_srm_rc" = 0 ]; then
    _SU_MCP_OUTCOME="applied"
    _SU_MCP_OUTCOME_REASON=""
    _setup_info "setup: [mcp] aplicado (mcpServers.cstk-state registrado)."

    # task 5.2.4 — jq ausente cai em print_paste_block (exit 0 preservado
    # por _mcp_cmd_install); mesmo tratamento de 3.2.3 (hooks
    # paste-instructed): applied com aviso de acao manual pendente, nunca
    # applied cego.
    case "$_srm_install_out" in
      *"jq ausente"*)
        _SU_MCP_OUTCOME_REASON="jq ausente — registro em .mcp.json exige colagem manual (bloco impresso acima); sem isso o servidor MCP NAO fica registrado"
        log_warn "setup: [mcp] $_SU_MCP_OUTCOME_REASON"
        ;;
    esac

    if [ -n "$_srm_docker_warning" ]; then
      if [ -n "$_SU_MCP_OUTCOME_REASON" ]; then
        _SU_MCP_OUTCOME_REASON="$_SU_MCP_OUTCOME_REASON; $_srm_docker_warning"
      else
        _SU_MCP_OUTCOME_REASON="$_srm_docker_warning"
      fi
      log_warn "setup: [mcp] $_srm_docker_warning"
    fi
  else
    _SU_MCP_OUTCOME="failed"
    _SU_MCP_OUTCOME_REASON="cstk mcp install falhou (exit $_srm_rc): $_srm_install_out"
    log_error "setup: [mcp] $_SU_MCP_OUTCOME_REASON"
  fi
  return 0
}

# ============================================================================
# Area de Telemetria (FASE 6 — tasks.md; contract em contracts/cli-setup.md
# §5; data-model.md Entity ConfigurationArea, linha `telemetry`).
#
# 100% READ-ONLY (FR-012): esta area NUNCA escreve em nenhum arquivo — nem
# no projeto, nem em ~/.zshrc, nem em qualquer outro lugar. So diagnostica
# (delegando a `otel-usage.sh preflight`, script ja existente do catalogo —
# nenhuma reimplementacao de deteccao de porta/exporter aqui) e exibe os
# valores EXATOS citados de README.md ("Real per-wave cost"), nunca
# inventados (Constitution VI). Outcome `applied` e INALCANCAVEL nesta area
# (task 6.1.3) — so already-configured|skipped|failed.
# ============================================================================

# _setup_show_telemetry_instructions STATUS -> imprime em stderr as
# instrucoes/valores EXATOS de ativacao citados de README.md (task 6.1.2).
# Nunca escreve em arquivo algum — so texto informativo.
_setup_show_telemetry_instructions() {
  case "$1" in
    port-conflict)
      log_warn "setup: [telemetry] a porta do exporter esta ocupada por OUTRO processo — o consumo DESTA sessao nao sera medido enquanto isso."
      ;;
    exporter-down)
      log_warn "setup: [telemetry] telemetria habilitada mas nada responde no endpoint — o consumo NAO sera medido nesta sessao."
      ;;
    unverified)
      log_warn "setup: [telemetry] o endpoint responde mas a propriedade do exporter nao pode ser confirmada (lsof ausente ou sem visibilidade) — pode ser esta sessao ou outra."
      ;;
    *)
      _setup_info "setup: [telemetry] telemetria desligada nesta sessao."
      ;;
  esac
  _setup_info "setup: [telemetry] para ativar, exporte estas variaveis na sua sessao de shell ANTES de rodar 'claude' (README.md, secao 'Real per-wave cost'):"
  _setup_info "setup: [telemetry]   export CLAUDE_CODE_ENABLE_TELEMETRY=1"
  _setup_info "setup: [telemetry]   export OTEL_METRICS_EXPORTER=prometheus"
  _setup_info "setup: [telemetry] o exporter local escuta em 127.0.0.1:9464 por padrao — nada sai da maquina."
  _setup_info "setup: [telemetry] mais de um processo Claude Code ao mesmo tempo? So UM pode usar a porta fixa 9464. De a cada processo sua propria porta com OTEL_EXPORTER_PROMETHEUS_PORT (porta sorteada) + CSTK_OTEL_ENDPOINT (URL correspondente) — README.md documenta um wrapper 'claude()' de exemplo para ~/.zshrc que sorteia porta livre a cada lancamento."
  _setup_info "setup: [telemetry] este wizard NAO escreve nada disso por voce (FR-012) — a ativacao e sempre manual, fora do diretorio do projeto."
}

# _setup_run_telemetry_area PROJECT_PATH MODE DRY_RUN
#
# Orquestra a area 'telemetry' de ponta a ponta (FASE 6):
#   1. Deteccao read-only via `otel-usage.sh preflight` (sempre roda,
#      inclusive em --dry-run — nao ha nada a aplicar de qualquer forma)
#   2. Apresentacao do status ANTES de qualquer instrucao adicional (FR-002)
#   3. script `otel-usage.sh` nao encontrado -> outcome=failed (mesmo
#      padrao das demais areas quando a dependencia delegada esta ausente)
#   4. `status=ok` (medicao confirmada ativa PARA ESTA sessao — o dono da
#      porta e ancestral do processo corrente) -> outcome
#      already-configured, ZERO chamada de aplicacao (nao existe chamada de
#      aplicacao possivel aqui — I1 trivialmente satisfeita)
#   5. `status=disabled|port-conflict|exporter-down|unverified` -> NUNCA
#      already-configured (nao ha confirmacao solida de medicao ativa desta
#      sessao especifica — Constitution VI, nunca afirmar o que nao foi
#      confirmado) -> outcome=skipped (data-model.md "Area telemetry
#      diagnosticada e nao ativa" -> skipped, reason "diagnostico exibido;
#      ativacao e manual (FR-012)"), sempre seguido das instrucoes exatas
#      de ativacao (task 6.1.2)
#   6. saida inesperada (sem token `status=`, ou exit fora do vocabulario
#      documentado do preflight) -> outcome=failed, citando a saida crua
#      como evidencia (nunca inventar interpretacao)
#
# MODE/DRY_RUN sao aceitos so por simetria de assinatura com as demais
# _setup_run_*_area — nenhum dos dois muda o comportamento desta area (nao
# ha decisao de usuario nem aplicacao possivel: 100% read-only sempre).
#
# Preenche _SU_TEL_OUTCOME (already-configured|skipped|failed) e
# _SU_TEL_OUTCOME_REASON (motivo legivel).
_setup_run_telemetry_area() {
  _srt_pap=$1
  _srt_mode=$2
  _srt_dry=$3

  _setup_info "setup: [telemetry] area 100% read-only (FR-012, project-path=$_srt_pap, mode=$_srt_mode, dry-run=$_srt_dry) — nenhuma escrita e feita em nenhum caso."

  if ! _srt_script=$(_setup_otel_script_path); then
    _SU_TEL_OUTCOME="failed"
    _SU_TEL_OUTCOME_REASON="nao foi possivel localizar otel-usage.sh (rode 'cstk install' ou 'cstk update' antes)"
    log_error "setup: [telemetry] $_SU_TEL_OUTCOME_REASON"
    return 0
  fi

  if _srt_out=$(sh "$_srt_script" preflight 2>/dev/null); then
    _srt_rc=0
  else
    _srt_rc=$?
  fi

  # FR-002 — status exibido ANTES de qualquer instrucao/decisao.
  _setup_info "setup: [telemetry] status atual = $_srt_out"

  _srt_status=""
  case "$_srt_out" in
    status=*)
      _srt_status=${_srt_out#status=}
      _srt_status=${_srt_status%% *}
      ;;
  esac

  case "$_srt_status" in
    ok)
      _SU_TEL_OUTCOME="already-configured"
      _SU_TEL_OUTCOME_REASON=""
      _setup_info "setup: [telemetry] medicao confirmada ativa para esta sessao — nenhuma acao necessaria."
      ;;
    disabled | port-conflict | exporter-down | unverified)
      _SU_TEL_OUTCOME="skipped"
      if [ "${_SU_VERBOSE:-0}" = 1 ]; then
        _SU_TEL_OUTCOME_REASON="diagnostico exibido; ativacao e manual (FR-012)"
      else
        _SU_TEL_OUTCOME_REASON="ativacao e manual (FR-012); instrucoes: cstk setup --verbose"
      fi
      _setup_show_telemetry_instructions "$_srt_status"
      ;;
    *)
      _SU_TEL_OUTCOME="failed"
      _SU_TEL_OUTCOME_REASON="otel-usage.sh preflight saida inesperada (exit $_srt_rc): $_srt_out"
      log_error "setup: [telemetry] $_SU_TEL_OUTCOME_REASON"
      ;;
  esac
  return 0
}

# ============================================================================
# SetupRunSummary (FASE 7 — tasks.md; contract em contracts/cli-setup.md §1
# "Saida (stdout)"; data-model.md Entity AreaOutcome).
#
# Toda a orquestracao acima (`_setup_run_*_area`) loga PROGRESSO/diagnostico
# via log_info/log_warn/log_error — ou seja, sempre em STDERR
# (cli/lib/common.sh). O summary final e DADO DE SAIDA (Constitution II:
# "mensagens de erro em stderr, saida de dados em stdout" — task 7.1.3), por
# isso usa `printf` direto para stdout, nunca log_*.
# ============================================================================

# _setup_print_summary_line AREA OUTCOME SCOPE REASON -> uma linha em
# stdout no formato `<area>  <outcome>  [escopo]  [motivo]`
# (contracts/cli-setup.md §1). SCOPE/REASON vazios sao omitidos (task
# 7.1.2 — `[escopo]` so aparece na linha de state-backend).
_setup_print_summary_line() {
  _spsl_line="$1  $2"
  [ -n "$3" ] && _spsl_line="$_spsl_line  $3"
  [ -n "$4" ] && _spsl_line="$_spsl_line  $4"
  printf '%s\n' "$_spsl_line"
}

# _setup_print_run_summary -> imprime em stdout (a) a declaracao de escopo
# da verificacao (achado SEC-07/CHK009, task 7.2.1: os 3 hooks obrigatorios
# de `_GH_HOOKS` foram verificados; NENHUMA outra entrada do
# `settings.json`/`.mcp.json` foi auditada — CHK016 permanece {humano},
# fora de escopo desta feature) e (b) o `SetupRunSummary` (FR-010): uma
# linha por area, na ordem fixa de FR-001.
_setup_print_run_summary() {
  printf 'setup: escopo da verificacao — apenas os 3 hooks obrigatorios de _GH_HOOKS (pretooluse-bash-guard.sh, posttooluse-tool-call-tick.sh, posttooluse-agent-usage.sh) foram verificados nesta execucao. Demais entradas de .claude/settings.json, e entradas de .mcp.json alem de mcpServers.cstk-state, NAO foram auditadas — nenhuma garantia e feita sobre elas.\n'
  printf '\n'
  _setup_print_summary_line "hooks" "$_SU_HOOKS_OUTCOME" "" "$_SU_HOOKS_OUTCOME_REASON"
  _setup_print_summary_line "state-backend" "$_SU_SB_OUTCOME" "global" "$_SU_SB_OUTCOME_REASON"
  _setup_print_summary_line "mcp" "$_SU_MCP_OUTCOME" "" "$_SU_MCP_OUTCOME_REASON"
  _setup_print_summary_line "telemetry" "$_SU_TEL_OUTCOME" "" "$_SU_TEL_OUTCOME_REASON"
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
  _setup_info "setup: pre-condicoes OK (mode=$_su_mode, project-path=$_SU_PROJECT_PATH)."

  _setup_run_hooks_area "$_SU_PROJECT_PATH" "$_su_mode" "$_SU_DRY_RUN"
  _setup_info "setup: [hooks] outcome=$_SU_HOOKS_OUTCOME"
  if [ "$_SU_HOOKS_OUTCOME" != "failed" ]; then
    _setup_area_ok "hooks" "$_SU_HOOKS_OUTCOME" "$_SU_HOOKS_OUTCOME_REASON"
  fi

  _setup_run_state_backend_area "$_SU_PROJECT_PATH" "$_su_mode" "$_SU_DRY_RUN"
  _setup_info "setup: [state-backend] outcome=$_SU_SB_OUTCOME"
  if [ "$_SU_SB_OUTCOME" != "failed" ]; then
    _setup_area_ok "state-backend" "$_SU_SB_OUTCOME" "$_SU_SB_OUTCOME_REASON"
  fi

  _setup_run_mcp_area "$_SU_PROJECT_PATH" "$_su_mode" "$_SU_DRY_RUN"
  _setup_info "setup: [mcp] outcome=$_SU_MCP_OUTCOME"
  if [ "$_SU_MCP_OUTCOME" != "failed" ]; then
    _setup_area_ok "mcp" "$_SU_MCP_OUTCOME" "$_SU_MCP_OUTCOME_REASON"
  fi

  _setup_run_telemetry_area "$_SU_PROJECT_PATH" "$_su_mode" "$_SU_DRY_RUN"
  _setup_info "setup: [telemetry] outcome=$_SU_TEL_OUTCOME"
  if [ "$_SU_TEL_OUTCOME" != "failed" ]; then
    _setup_area_ok "telemetry" "$_SU_TEL_OUTCOME" "$_SU_TEL_OUTCOME_REASON"
  fi

  # FR-010/FASE 7 — SetupRunSummary consolidado, SEMPRE impresso ao final,
  # inclusive quando alguma area falhou (quickstart Scenario 7, SC-005:
  # "summary lista as 4 areas" mesmo com falha parcial).
  _setup_print_run_summary

  if [ "$_SU_HOOKS_OUTCOME" = "failed" ] || [ "$_SU_SB_OUTCOME" = "failed" ] \
    || [ "$_SU_MCP_OUTCOME" = "failed" ] || [ "$_SU_TEL_OUTCOME" = "failed" ]; then
    return 1
  fi
  return 0
}
