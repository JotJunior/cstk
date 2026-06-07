#!/bin/sh
# state-decisions.sh — registro de Decisoes (Principio I — Auditabilidade Total).
#
# Ref: docs/specs/agente-00c/spec.md FR-010
#      docs/specs/agente-00c/data-model.md §Decisao
#      docs/specs/agente-00c/constitution.md §I
#      docs/specs/agente-00c/tasks.md FASE 3.2
#
# Subcomandos:
#   state-decisions.sh register --state-dir DIR
#       --agente A --etapa S
#       --contexto T --opcoes JSON-ARR --escolha STR --justificativa STR
#       [--score N] [--evidencia STR] [--referencias JSON-ARR]
#       [--artefato-originador STR]
#       — Valida 5 campos obrigatorios (contexto>=20, opcoes >=1, escolha,
#         justificativa>=20, agente). Falta = exit 1 (sem auto-correcao).
#       — Score 3 (decide_sem_clarificar) EXIGE --evidencia >=20 chars com
#         comando + fragmento literal do output (FR-EVI-001, ref licoes
#         pos-execucao §4.6/§5.5). Sem evidencia, exit 1. Para evitar
#         convicção sem prova, score 3 nao pode ser atribuido em modo
#         "tenho certeza" — apenas com `tsc --noEmit`, `vitest -t`,
#         `grep -r`, inspecao de `package.json` ou similar registrado.
#       — Gera id `dec-NNN` sequencial dentro da execucao.
#       — Linka a `wave_id` da onda corrente (.waves[-1].id; init = "init").
#       — Append em .decisions; persiste via state-rw write (com backup).
#       — Atualiza accumulated_metrics.decisions_total.
#
#   state-decisions.sh count --state-dir DIR [--agente A]
#       — Imprime total de decisoes (filtrado por agente, opcional).
#
#   state-decisions.sh next-id --state-dir DIR
#       — Imprime proximo dec-NNN sem registrar.
#
#   state-decisions.sh list --state-dir DIR [--agente A] [--etapa S]
#       — Lista TSV: id\twave_id\tagent\tstage\tchoice
#
# Exit codes:
#   0 sucesso
#   1 violacao Principio I OU erro generico
#   2 uso incorreto
#
# POSIX sh + jq.

set -eu

_SD_NAME="state-decisions"

_sd_die_usage() {
  printf '%s: %s\n' "$_SD_NAME" "$1" >&2
  exit 2
}

_sd_die() {
  printf '%s: %s\n' "$_SD_NAME" "$1" >&2
  exit "${2:-1}"
}

_sd_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    _sd_die "jq nao encontrado no PATH (brew install jq | apt install jq)" 1
  fi
}

_sd_iso_now() { date -u +%FT%TZ; }

_sd_state_file() { printf '%s/state.json\n' "$1"; }

# _sd_next_dec_id STATE_DIR -> proximo dec-NNN baseado em max(.decisions[].id)
_sd_next_dec_id() {
  _sf=$(_sd_state_file "$1")
  [ -f "$_sf" ] || _sd_die "next-id: state.json ausente em $1" 1
  _max=$(jq -r '
    ((.decisions // .decisoes) // []) as $d
    | if ($d | length) == 0 then 0
      else ([$d[].id // ""] | map(sub("^dec-0*"; "") | tonumber? // 0) | max)
      end' "$_sf" 2>/dev/null) || _max=0
  _next=$((_max + 1))
  printf 'dec-%03d\n' "$_next"
}

# _sd_current_onda_id STATE_DIR -> id da onda corrente (.waves[-1].id) ou "init"
_sd_current_onda_id() {
  _sf=$(_sd_state_file "$1")
  jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w[-1].id // "init")
      else "init"
      end' "$_sf" 2>/dev/null
}

# _sd_atomic_write DST CONTENT_FILE
_sd_atomic_write() {
  _dst=$1
  _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _sd_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _sd_die "I/O cp tmp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _sd_die "mv atomico falhou" 1; }
}

# _sd_update_sha STATE_DIR
_sd_update_sha() {
  _sf=$(_sd_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

# _sd_backup_current STATE_DIR (mesma semantica de state-rw)
_sd_backup_current() {
  _sf=$(_sd_state_file "$1")
  [ -f "$_sf" ] || return 0
  _hd="$1/state-history"
  mkdir -p -- "$_hd" 2>/dev/null || _sd_die "mkdir state-history falhou" 1
  _curr=$(_sd_current_onda_id "$1") || _curr="init"
  _ts=$(date -u +%Y%m%dT%H%M%SZ)
  _bk="$_hd/${_curr}-${_ts}.json"
  mv -- "$_sf" "$_bk" || _sd_die "backup falhou" 1
}

# ---------- Subcomandos ----------

_sd_cmd_register() {
  _sdir=""
  _ag=""
  _et=""
  _ctx=""
  _ops=""
  _esc=""
  _just=""
  _score="null"
  _refs="[]"
  _arto="null"
  _evi=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)            _sdir=$2; shift 2 ;;
      --agente)               _ag=$2;   shift 2 ;;
      --etapa)                _et=$2;   shift 2 ;;
      --contexto)             _ctx=$2;  shift 2 ;;
      --opcoes)               _ops=$2;  shift 2 ;;
      --escolha)              _esc=$2;  shift 2 ;;
      --justificativa)        _just=$2; shift 2 ;;
      --score)                _score=$2; shift 2 ;;
      --evidencia)            _evi=$2;  shift 2 ;;
      --referencias)          _refs=$2;  shift 2 ;;
      --artefato-originador)  _arto=$2;  shift 2 ;;
      *) _sd_die_usage "register: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _sd_die_usage "register: --state-dir obrigatorio"
  [ -n "$_ag" ]   || _sd_die_usage "register: --agente obrigatorio"
  [ -n "$_et" ]   || _sd_die_usage "register: --etapa obrigatorio"
  [ -n "$_ctx" ]  || _sd_die_usage "register: --contexto obrigatorio"
  [ -n "$_ops" ]  || _sd_die_usage "register: --opcoes obrigatorio (JSON array)"
  [ -n "$_esc" ]  || _sd_die_usage "register: --escolha obrigatorio"
  [ -n "$_just" ] || _sd_die_usage "register: --justificativa obrigatorio"
  _sd_require_jq

  # Validacao Principio I (5 campos): contexto>=20, opcoes >=1 item, escolha
  # nao-vazia, justificativa>=20, agente nao-vazio. Erros sao "violacao",
  # nao "uso" — exit 1.
  if [ "$(printf '%s' "$_ctx" | wc -c | tr -d ' ')" -lt 20 ]; then
    _sd_die "register: violacao Principio I — contexto < 20 chars" 1
  fi
  if [ "$(printf '%s' "$_just" | wc -c | tr -d ' ')" -lt 20 ]; then
    _sd_die "register: violacao Principio I — justificativa < 20 chars" 1
  fi
  if ! printf '%s' "$_ops" | jq -e 'type == "array" and length >= 1' >/dev/null 2>&1; then
    _sd_die "register: violacao Principio I — opcoes_consideradas precisa ser JSON array com >=1 item" 1
  fi
  if ! printf '%s' "$_refs" | jq -e 'type == "array"' >/dev/null 2>&1; then
    _sd_die "register: --referencias precisa ser JSON array" 2
  fi
  # score aceita "null" ou numero 0..3
  case "$_score" in
    null) ;;
    0|1|2|3) ;;
    *) _sd_die "register: --score deve ser null|0|1|2|3 (recebido $_score)" 2 ;;
  esac

  # Score 3 (decide_sem_clarificar) EXIGE evidencia empirica (FR-EVI-001).
  # Razao: 3 falsos positivos `score=3` documentados (sug-037, dec-048,
  # dec-123/dec-126) onde agente afirmou premissa tecnica falsa sem rodar
  # tsc/test/grep. Trilha auditava conviccao, nao evidencia.
  if [ "$_score" = 3 ]; then
    if [ -z "$_evi" ]; then
      _sd_die "register: violacao Principio I — score=3 (decide_sem_clarificar) EXIGE --evidencia com comando + fragmento literal do output (sem evidencia, score maximo permitido e 2)" 1
    fi
    if [ "$(printf '%s' "$_evi" | wc -c | tr -d ' ')" -lt 20 ]; then
      _sd_die "register: violacao Principio I — --evidencia < 20 chars (precisa conter comando executado + fragmento do output literal)" 1
    fi
  fi

  # Trava FR-CONST-PREFLIGHT: decisao pre-flight de constitution-conflict
  # (exit=2 do pipeline.sh) e identificada pela presenca das 3 opcoes
  # canonicas em --opcoes. Quando detectada, exige score=0 (pause-humano)
  # + registro de BloqueioHumano via bloqueios.sh ANTES da invocacao da
  # skill constitution. Razao: dec-004 do projeto github-pages-cstk-manual
  # detectou exit=2 corretamente, listou as 3 opcoes corretamente, mas
  # decidiu sozinho em Auto Mode (score=2) e invocou a skill sem aguardar
  # decisao humana — bypassando o protocolo descrito em orchestrator.md
  # secao 5.b. Esta trava fecha esse caminho no runtime.
  if printf '%s' "$_ops" | jq -e '
    type == "array"
    and (index("atualizar-global-via-bump-SemVer") != null)
    and (index("criar-feature-delta-com-sync-impact-report") != null)
    and (index("abortar-feature-sem-principios-proprios") != null)
  ' >/dev/null 2>&1; then
    if [ "$_score" != 0 ]; then
      _sd_die "register: violacao protocolo constitution-conflict — opcoes contem as 3 strings canonicas do BloqueioHumano pre-flight (atualizar-global-via-bump-SemVer, criar-feature-delta-com-sync-impact-report, abortar-feature-sem-principios-proprios), portanto esta e a decisao pre-flight obrigatoria e EXIGE --score 0 (pause-humano). Voce passou score=$_score. Sequencia correta: (1) state-decisions.sh register --score 0 --escolha pause-humano ...; (2) bloqueios.sh register --decisao-id <dec-NNN> ...; (3) aguardar humano responder; (4) pipeline.sh require-blockade-resolved; (5) Skill(constitution). Ver orchestrator.md secao 5.b." 1
    fi
  fi

  _sf=$(_sd_state_file "$_sdir")
  [ -f "$_sf" ] || _sd_die "register: state.json ausente em $_sdir" 1

  _id=$(_sd_next_dec_id "$_sdir")
  _onda=$(_sd_current_onda_id "$_sdir")
  _now=$(_sd_iso_now)

  # Monta a decisao via jq (escape automatico).
  _new_state=$(mktemp) || _sd_die "mktemp falhou" 1
  jq \
    --arg id "$_id" \
    --arg onda "$_onda" \
    --arg ts "$_now" \
    --arg etapa "$_et" \
    --arg agente "$_ag" \
    --arg ctx "$_ctx" \
    --arg esc "$_esc" \
    --arg just "$_just" \
    --argjson opcoes "$_ops" \
    --argjson refs "$_refs" \
    --argjson score "$_score" \
    --arg arto "$_arto" \
    --arg evi "$_evi" \
    '
    .decisions += [{
      id: $id,
      wave_id: $onda,
      timestamp: $ts,
      stage: $etapa,
      agent: $agente,
      context: $ctx,
      options_considered: $opcoes,
      choice: $esc,
      rationale: $just,
      justification_score: $score,
      evidence: (if $evi == "" then null else $evi end),
      references: $refs,
      originating_artifact: (if $arto == "null" then null else $arto end)
    }]
    | .accumulated_metrics.decisions_total = ((.accumulated_metrics.decisions_total // 0) + 1)
    ' "$_sf" > "$_new_state" || { rm -f -- "$_new_state"; _sd_die "jq update falhou" 1; }

  _sd_backup_current "$_sdir"
  _sd_atomic_write "$_sf" "$_new_state"
  rm -f -- "$_new_state" 2>/dev/null || :
  _sd_update_sha "$_sdir"
  printf '%s\n' "$_id"  # stdout: id da decisao registrada
}

_sd_cmd_count() {
  _sdir=""
  _ag=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      --agente)    _ag=$2;   shift 2 ;;
      *) _sd_die_usage "count: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _sd_die_usage "count: --state-dir obrigatorio"
  _sd_require_jq
  _sf=$(_sd_state_file "$_sdir")
  [ -f "$_sf" ] || _sd_die "count: state.json ausente" 1
  if [ -n "$_ag" ]; then
    jq --arg a "$_ag" '((.decisions // .decisoes) // []) | map(select((.agent // .agente) == $a)) | length' "$_sf"
  else
    jq '((.decisions // .decisoes) // []) | length' "$_sf"
  fi
}

_sd_cmd_next_id() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _sd_die_usage "next-id: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _sd_die_usage "next-id: --state-dir obrigatorio"
  _sd_require_jq
  _sd_next_dec_id "$_sdir"
}

_sd_cmd_list() {
  _sdir=""
  _ag=""
  _et=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      --agente)    _ag=$2;   shift 2 ;;
      --etapa)     _et=$2;   shift 2 ;;
      *) _sd_die_usage "list: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _sd_die_usage "list: --state-dir obrigatorio"
  _sd_require_jq
  _sf=$(_sd_state_file "$_sdir")
  [ -f "$_sf" ] || _sd_die "list: state.json ausente" 1
  jq -r --arg a "$_ag" --arg e "$_et" '
    ((.decisions // .decisoes) // [])
    | map(select((($a == "") or ((.agent // .agente) == $a)) and (($e == "") or ((.stage // .etapa) == $e))))
    | .[]
    | [.id, (.wave_id // .onda_id), (.agent // .agente), (.stage // .etapa), (.choice // .escolha)] | @tsv
  ' "$_sf"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
state-decisions.sh — registra Decisoes auditaveis (Principio I).

USO:
  state-decisions.sh register --state-dir DIR --agente A --etapa S \
    --contexto T --opcoes JSON-ARR --escolha STR --justificativa STR \
    [--score N] [--evidencia STR] [--referencias JSON-ARR] \
    [--artefato-originador STR]
  state-decisions.sh count --state-dir DIR [--agente A]
  state-decisions.sh next-id --state-dir DIR
  state-decisions.sh list --state-dir DIR [--agente A] [--etapa S]

NOTA: --score 3 EXIGE --evidencia (>=20 chars) com comando empirico
executado + fragmento literal do output. Sem evidencia empirica,
score maximo permitido e 2 (FR-EVI-001).

EXIT:
  0 sucesso
  1 violacao Principio I OU erro generico
  2 uso incorreto
HELP
  exit 2
fi

_SD_SUBCMD=$1
shift

case "$_SD_SUBCMD" in
  register)        _sd_cmd_register "$@" ;;
  count)           _sd_cmd_count "$@" ;;
  next-id)         _sd_cmd_next_id "$@" ;;
  list)            _sd_cmd_list "$@" ;;
  -h|--help|help)  exec sh -c "exit 0" ;;
  *) _sd_die_usage "subcomando desconhecido: $_SD_SUBCMD" ;;
esac
