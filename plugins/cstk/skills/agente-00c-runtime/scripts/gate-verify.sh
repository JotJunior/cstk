#!/bin/sh
# gate-verify.sh — gate deterministico de testes antes de avancar de
# execute-task/converge (issue #242).
#
# Problema: o gate de evidencia da execute-task (§8.2) e prosa dirigida ao
# subagente. Uma onda fechava com tasks `[x]` e suite vermelha, e o defeito
# so aparecia ondas depois. Aqui o comando de gate do projeto-alvo e
# EXECUTADO por este helper (nunca relatado por prosa), o exit code real e a
# linha de sumario do runner sao gravados por onda, e `state-ondas.sh end
# --advance` saindo de execute-task/converge consulta `check` antes de
# avancar o ponteiro.
#
# Decisoes de desenho (operador, 2026-11-02):
#   - fonte do comando: opt-in no inicio da execucao, persistido em
#     `.gate_command` no state (resume le sem re-perguntar);
#   - sem comando declarado: DEGRADA com aviso (gate=not-declared), nunca
#     bloqueia — execucoes existentes seguem intactas;
#   - uma execucao por chamada (sem re-run anti-flaky por ora).
#
# Subcomandos:
#   gate-verify.sh set-command --state-dir DIR --command CMD
#       — Valida (nao-vazio, linha unica, <=1000 bytes, passa em
#         bash-guard.sh check-blocklist) e grava `.gate_command`.
#   gate-verify.sh get-command --state-dir DIR
#       — Imprime o comando declarado (vazio se nenhum). Exit 0.
#   gate-verify.sh run --state-dir DIR [--project-path PATH]
#       — Executa o comando na raiz do projeto-alvo (default:
#         .execution.target_project_path) e registra o resultado da ONDA
#         ABERTA no sidecar <DIR>/gate-verify.tsv; saida completa em
#         <DIR>/gate-verify/<wave_id>.log (sobrescrita a cada run).
#         Re-checa o comando contra bash-guard.sh check-blocklist ANTES de
#         executar: o comando roda dentro deste processo, fora do alcance do
#         hook PreToolUse (que so ve `gate-verify.sh run`), e o state pode
#         ter sido editado depois do set-command.
#         Stdout: `gate=<pass|fail|blocked|not-declared> exit=<N|-> wave=<id>`
#         + `summary=<linha>`. Sem comando declarado: registra
#         not-declared e avisa em stderr.
#   gate-verify.sh check --state-dir DIR
#       — Consulta usada por `state-ondas.sh end --advance`: decide se a
#         onda ABERTA (.waves[-1]) pode avancar. Nao executa nada.
#         Stdout: `gate=<pass|fail|blocked|missing|not-declared> ...`.
#
# Sidecar <DIR>/gate-verify.tsv (append-only, uma linha por run):
#   wave_id \t recorded_at \t status \t exit \t summary
# Fora do state (mesmo racional do sidecar de ticks, tool-call-ticks.log):
# nao exige schema novo em nenhum dos dois backends. `summary` passa por
# secrets-filter.sh scrub, perde TAB/CR e e truncado a 300 bytes.
#
# Exit codes:
#   0 gate verde (pass) OU nao declarado (degradado, com aviso)
#   1 erro do helper (state ausente, sem onda aberta, I/O)
#   2 uso incorreto / comando invalido no set-command
#   3 gate vermelho: fail, blocked (comando barrado pelo bash-guard) ou
#     missing (declarado, mas sem run registrado nesta onda) — so `run` e
#     `check`
#
# POSIX sh + jq (via state-rw.sh).

set -eu

_GV_NAME="gate-verify"
_GV_DIR=$(cd "$(dirname -- "$0")" && pwd)
_GV_RW="$_GV_DIR/state-rw.sh"
_GV_GUARD="$_GV_DIR/bash-guard.sh"
_GV_SCRUB="$_GV_DIR/secrets-filter.sh"
_GV_TAB=$(printf '\t')
# Newline literal: `$(printf '\n')` NAO serve — a substituicao de comando
# remove o \n final e o padrao `*""*` casaria qualquer string.
_GV_NL='
'
_GV_CR=$(printf '\r')
_GV_MAX_CMD=1000
_GV_MAX_SUMMARY=300

_gv_die_usage() { printf '%s: %s\n' "$_GV_NAME" "$1" >&2; exit 2; }
_gv_die()       { printf '%s: %s\n' "$_GV_NAME" "$1" >&2; exit "${2:-1}"; }
_gv_warn()      { printf '%s: %s\n' "$_GV_NAME" "$1" >&2; }

_gv_sidecar() { printf '%s/gate-verify.tsv\n' "$1"; }

# _gv_get_field DIR FIELD -> valor cru via state-rw.sh (backend-agnostico);
# null/ausente => vazio.
_gv_get_field() {
  _gvf=$(sh "$_GV_RW" get --state-dir "$1" --field "$2" 2>/dev/null) || _gvf=""
  case "$_gvf" in null) _gvf="" ;; esac
  printf '%s' "$_gvf"
}

_gv_command() { _gv_get_field "$1" '.gate_command // ""'; }

# _gv_open_wave DIR -> id da onda aberta (.waves[-1] sem termination_reason)
# ou vazio.
_gv_open_wave() {
  _gv_get_field "$1" '((.waves // []) | last) as $w | if $w != null and $w.termination_reason == null then $w.id else "" end'
}

# Existencia do estado via interface canonica (state-rw.sh, backend-
# agnostico) — nunca testando o arquivo de um backend especifico
# (test_state-parity-sweep.sh gateia acesso direto).
_gv_require_state() {
  [ -d "$1" ] || _gv_die "state-dir inexistente: $1" 1
  sh "$_GV_RW" get --state-dir "$1" --field '.execution.id' >/dev/null 2>&1 \
    || _gv_die "state ausente/ilegivel em $1" 1
}

# _gv_validate_command CMD -> exit 2 com motivo se invalido.
_gv_validate_command() {
  _gvc=$1
  case "$(printf '%s' "$_gvc" | tr -d ' \t')" in
    '') _gv_die_usage "comando de gate vazio" ;;
  esac
  case "$_gvc" in
    *"$_GV_NL"*|*"$_GV_CR"*) _gv_die_usage "comando de gate deve ser linha unica (sem \\n/\\r)" ;;
  esac
  _gvl=$(printf '%s' "$_gvc" | wc -c | tr -d ' ')
  [ "$_gvl" -le "$_GV_MAX_CMD" ] \
    || _gv_die_usage "comando de gate excede $_GV_MAX_CMD bytes ($_gvl)"
}

# _gv_guard CMD -> exit 0 se bash-guard aceita; 1 se barra (motivo em stderr).
# Ausencia do bash-guard = falha FECHADA (mesma politica do hook PreToolUse).
_gv_guard() {
  [ -f "$_GV_GUARD" ] || { _gv_warn "bash-guard.sh ausente em $_GV_DIR — gate recusado (fail-closed)"; return 1; }
  sh "$_GV_GUARD" check-blocklist --command "$1" >&2
}

# _gv_sanitize_summary -> stdin: linha crua; stdout: linha segura p/ TSV.
_gv_sanitize_summary() {
  _gvs=$(tr -d '\r' | tr '\t' ' ')
  if [ -f "$_GV_SCRUB" ]; then
    _gvs=$(printf '%s\n' "$_gvs" | sh "$_GV_SCRUB" scrub 2>/dev/null) || _gvs="[summary descartado: scrub falhou]"
  fi
  printf '%s' "$_gvs" | head -c "$_GV_MAX_SUMMARY" | tr -d '\n'
}

# _gv_record DIR WAVE STATUS EXIT SUMMARY -> append no sidecar.
_gv_record() {
  _gvr_now=$(date -u +%FT%TZ)
  printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$_gvr_now" "$3" "$4" "$5" >> "$(_gv_sidecar "$1")" \
    || _gv_die "falha ao gravar $(_gv_sidecar "$1")" 1
}

# ---------- set-command ----------

_gv_cmd_set_command() {
  _sd=""; _cmd=""; _cmd_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) [ "$#" -ge 2 ] || _gv_die_usage "--state-dir exige valor"; _sd=$2; shift 2 ;;
      --command)   [ "$#" -ge 2 ] || _gv_die_usage "--command exige valor"; _cmd=$2; _cmd_set=1; shift 2 ;;
      *) _gv_die_usage "set-command: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _gv_die_usage "set-command: --state-dir obrigatorio"
  [ "$_cmd_set" = 1 ] || _gv_die_usage "set-command: --command obrigatorio"
  _gv_validate_command "$_cmd"
  _gv_guard "$_cmd" || _gv_die_usage "set-command: comando barrado pelo bash-guard (blocklist) — gate precisa ser um comando de teste/build, nao de efeito colateral"
  _gv_require_state "$_sd"
  _json=$(jq -n --arg c "$_cmd" '$c') || _gv_die "jq falhou ao serializar o comando" 1
  sh "$_GV_RW" set --state-dir "$_sd" --field '.gate_command' --value "$_json" >/dev/null \
    || _gv_die "set-command: state-rw.sh set falhou" 1
  printf 'gate_command=%s\n' "$_cmd"
}

# ---------- get-command ----------

_gv_cmd_get_command() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) [ "$#" -ge 2 ] || _gv_die_usage "--state-dir exige valor"; _sd=$2; shift 2 ;;
      *) _gv_die_usage "get-command: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _gv_die_usage "get-command: --state-dir obrigatorio"
  _gv_require_state "$_sd"
  _c=$(_gv_command "$_sd")
  [ -z "$_c" ] || printf '%s\n' "$_c"
}

# ---------- run ----------

_gv_cmd_run() {
  _sd=""; _pp=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)    [ "$#" -ge 2 ] || _gv_die_usage "--state-dir exige valor"; _sd=$2; shift 2 ;;
      --project-path) [ "$#" -ge 2 ] || _gv_die_usage "--project-path exige valor"; _pp=$2; shift 2 ;;
      *) _gv_die_usage "run: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _gv_die_usage "run: --state-dir obrigatorio"
  _gv_require_state "$_sd"

  _wave=$(_gv_open_wave "$_sd")
  [ -n "$_wave" ] || _gv_die "run: nenhuma onda aberta em $_sd — o gate e registrado por onda (rode antes do end)" 1

  _cmd=$(_gv_command "$_sd")
  if [ -z "$_cmd" ]; then
    _gv_record "$_sd" "$_wave" "not-declared" "-" ""
    _gv_warn "gate=nao-declarado: nenhum comando de gate declarado (.gate_command) — avanco sem verificacao deterministica de testes; declare com gate-verify.sh set-command"
    printf 'gate=not-declared exit=- wave=%s\nsummary=\n' "$_wave"
    return 0
  fi

  if [ -z "$_pp" ]; then
    _pp=$(_gv_get_field "$_sd" '.execution.target_project_path // ""')
  fi
  [ -n "$_pp" ] && [ -d "$_pp" ] || _gv_die "run: projeto-alvo inexistente: '${_pp}' (use --project-path)" 1

  if ! _gv_guard "$_cmd"; then
    _gv_record "$_sd" "$_wave" "blocked" "-" "comando barrado pelo bash-guard"
    printf 'gate=blocked exit=- wave=%s\nsummary=comando barrado pelo bash-guard\n' "$_wave"
    exit 3
  fi

  mkdir -p "$_sd/gate-verify" || _gv_die "run: mkdir $_sd/gate-verify falhou" 1
  _log="$_sd/gate-verify/$_wave.log"
  _rc=0
  ( cd "$_pp" && sh -c "$_cmd" ) > "$_log" 2>&1 < /dev/null || _rc=$?

  # Linha de sumario = ultima linha nao-vazia da saida (onde runners como
  # go test/pytest/vitest/make imprimem o resultado agregado).
  _summary=$(tr -d '\r' < "$_log" | sed '/^[[:space:]]*$/d' | tail -n 1 | _gv_sanitize_summary)

  if [ "$_rc" = 0 ]; then _status=pass; else _status=fail; fi
  _gv_record "$_sd" "$_wave" "$_status" "$_rc" "$_summary"
  printf 'gate=%s exit=%s wave=%s\nsummary=%s\n' "$_status" "$_rc" "$_wave" "$_summary"
  [ "$_status" = pass ] || exit 3
}

# ---------- check ----------

_gv_cmd_check() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) [ "$#" -ge 2 ] || _gv_die_usage "--state-dir exige valor"; _sd=$2; shift 2 ;;
      *) _gv_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _gv_die_usage "check: --state-dir obrigatorio"
  _gv_require_state "$_sd"

  _wave=$(_gv_open_wave "$_sd")
  _cmd=$(_gv_command "$_sd")
  if [ -z "$_cmd" ]; then
    _gv_warn "gate=nao-declarado: nenhum comando de gate declarado (.gate_command) — avancando sem verificacao deterministica de testes"
    printf 'gate=not-declared wave=%s\n' "${_wave:--}"
    return 0
  fi
  [ -n "$_wave" ] || _gv_die "check: nenhuma onda aberta em $_sd" 1

  _sc=$(_gv_sidecar "$_sd")
  _last=""
  if [ -f "$_sc" ]; then
    _last=$(awk -F "$_GV_TAB" -v w="$_wave" '$1 == w { l = $0 } END { if (l != "") print l }' "$_sc")
  fi
  if [ -z "$_last" ]; then
    printf 'gate=missing wave=%s\n' "$_wave"
    _gv_warn "gate declarado ('$_cmd') mas sem run registrado na onda $_wave — rode gate-verify.sh run antes de avancar"
    exit 3
  fi
  _st=$(printf '%s' "$_last" | cut -f3)
  _rc=$(printf '%s' "$_last" | cut -f4)
  _sm=$(printf '%s' "$_last" | cut -f5-)
  case "$_st" in
    pass)
      printf 'gate=pass exit=%s wave=%s\n' "$_rc" "$_wave"
      return 0 ;;
    not-declared)
      # Run registrado antes do comando ser declarado: o comando atual nunca
      # rodou nesta onda.
      printf 'gate=missing wave=%s\n' "$_wave"
      _gv_warn "ultimo run da onda $_wave foi sem comando declarado — rode gate-verify.sh run de novo"
      exit 3 ;;
    *)
      printf 'gate=%s exit=%s wave=%s summary=%s\n' "$_st" "$_rc" "$_wave" "$_sm"
      exit 3 ;;
  esac
}

# ---------- dispatch ----------

_gv_usage() {
  cat <<'EOF'
Uso: gate-verify.sh set-command --state-dir DIR --command CMD
     gate-verify.sh get-command --state-dir DIR
     gate-verify.sh run         --state-dir DIR [--project-path PATH]
     gate-verify.sh check       --state-dir DIR

Gate deterministico de testes (issue #242): `run` EXECUTA o comando de gate
declarado e registra exit code + linha de sumario na onda aberta; `check`
(consumido por state-ondas.sh end --advance saindo de execute-task/converge)
recusa o avanco quando o ultimo run da onda nao passou.

Exit: 0 verde ou nao-declarado (degradado); 1 erro; 2 uso; 3 gate vermelho.
EOF
}

[ "$#" -ge 1 ] || { _gv_usage >&2; exit 2; }
_GV_SUB=$1
shift
case "$_GV_SUB" in
  set-command) _gv_cmd_set_command "$@" ;;
  get-command) _gv_cmd_get_command "$@" ;;
  run)         _gv_cmd_run "$@" ;;
  check)       _gv_cmd_check "$@" ;;
  -h|--help|help) _gv_usage ;;
  *) _gv_die_usage "subcomando desconhecido: $_GV_SUB" ;;
esac
