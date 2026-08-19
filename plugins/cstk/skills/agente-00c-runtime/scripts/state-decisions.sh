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
#   state-decisions.sh mark-invalid --state-dir DIR --decisao-id dec-NNN
#       --motivo TEXT(>=20) [--agente A]
#       — Issue #144: caminho SUPORTADO para desautorizar uma Decisao
#         malformada/errada SEM tocar a linha original (Decisoes sao
#         append-only — Principio I). Registra uma NOVA Decisao via
#         `register` com a convencao deterministica:
#           contexto   = "INVALIDACAO de dec-NNN: <motivo>"
#           opcoes     = ["manter-dec-NNN","invalidar-dec-NNN"]
#           escolha    = "invalidar-dec-NNN"
#           justif.    = <motivo>
#           artefato-originador = "dec-NNN"   (score ausente = humano)
#         Leitores (report.sh secao 3) detectam o par
#         (originating_artifact == dec-NNN AND choice == invalidar-dec-NNN)
#         e renderizam a original como INVALIDADA. Backend-agnostico
#         (passa por register => state-rw). Recusa: decisao inexistente,
#         ja invalidada, ou que e ela mesma uma invalidacao (exit 1).
#         stdout: id da Decisao de invalidacao.
#
# Exit codes:
#   0 sucesso
#   1 violacao Principio I OU erro generico
#   2 uso incorreto
#
# POSIX sh + jq.

set -eu

_SD_NAME="state-decisions"
_SD_DIR=$(cd "$(dirname -- "$0")" && pwd)

# Backend dual (feature state-db-foundation, FASE 3 task 3.4): presenca de
# <state-dir>/state.db seleciona SQLite; senao, backend JSON (comportamento
# historico, intacto abaixo). Ver contracts/primitives.md §C1/C2. Reusa os
# primitivos ja testados de _state-rw-db.sh (_sr_backend/_sr_db_file/
# _sr_exec_id/_sr_sql_quote) em vez de duplica-los — mesmo racional de C8
# para sql_escape/strip_nul.
# shellcheck source=./_state-db.sh
. "$_SD_DIR/_state-db.sh"
# shellcheck source=./_state-rw-db.sh
. "$_SD_DIR/_state-rw-db.sh"
# shellcheck source=./_state-decisions-db.sh
. "$_SD_DIR/_state-decisions-db.sh"

_sd_die_usage() {
  printf '%s: %s\n' "$_SD_NAME" "$1" >&2
  exit 2
}

_sd_die() {
  printf '%s: %s\n' "$_SD_NAME" "$1" >&2
  exit "${2:-1}"
}

# Shim para _state-rw-db.sh (_sr_exec_id/_sr_sql_quote nao chamam _sr_die em
# seus caminhos normais, mas o shim protege contra qualquer caminho de erro
# latente sem duplicar a logica de _sd_die).
_sr_die() { _sd_die "$1" "${2:-1}"; }

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
  # Strip de CR + guard numerico (paridade com bloqueios.sh#_bl_next_block_id,
  # issues #122/#123): jq nativo do Windows emite CRLF e o \r residual
  # corromperia a aritmetica.
  _max=$(jq -r '
    ((.decisions // .decisoes) // []) as $d
    | if ($d | length) == 0 then 0
      else ([$d[].id // ""] | map(sub("^dec-0*"; "") | tonumber? // 0) | max)
      end' "$_sf" 2>/dev/null | tr -d '\r')
  case "$_max" in '' | *[!0-9]*) _max=0 ;; esac
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
  # Issue #141: forma de cada elemento. Aceita string nao-vazia OU objeto
  # estruturado {rotulo|label: string nao-vazia, descricao?} — o formato que
  # o clarify-asker emite em opcoes_recomendadas e que a prosa do
  # orquestrador passa verbatim em --opcoes. Qualquer outra coisa (numero,
  # null, array, objeto sem rotulo) e rejeitada aqui, com mensagem clara, em
  # vez de ser gravada e quebrar o report.sh generate depois.
  if ! printf '%s' "$_ops" | jq -e '
        all(.[];
          (type == "string" and length > 0)
          or (type == "object" and (((.rotulo // .label) | type) == "string") and (((.rotulo // .label) | length) > 0)))
      ' >/dev/null 2>&1; then
    _sd_die "register: violacao Principio I — cada item de --opcoes precisa ser string nao-vazia ou objeto {rotulo|label: string nao-vazia, descricao?}" 1
  fi
  if ! printf '%s' "$_refs" | jq -e 'type == "array"' >/dev/null 2>&1; then
    _sd_die "register: --referencias precisa ser JSON array" 2
  fi
  # Mesma regra de forma para --referencias (report.sh ja renderiza string
  # ou objeto chave=valor; numero/null/array quebrariam o to_entries).
  if ! printf '%s' "$_refs" | jq -e 'all(.[]; (type == "string" and length > 0) or (type == "object" and length > 0))' >/dev/null 2>&1; then
    _sd_die "register: cada item de --referencias precisa ser string nao-vazia ou objeto nao-vazio" 2
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

  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _sd_db_register "$_sdir" "$_ag" "$_et" "$_ctx" "$_ops" "$_esc" "$_just" \
      "$_score" "$_evi" "$_refs" "$_arto"
    return 0
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
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _sd_db_count "$_sdir" "$_ag"
    return 0
  fi
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
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _sd_db_next_id "$_sdir"
    return 0
  fi
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
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _sd_db_list "$_sdir" "$_ag" "$_et"
    return 0
  fi
  _sf=$(_sd_state_file "$_sdir")
  [ -f "$_sf" ] || _sd_die "list: state.json ausente" 1
  jq -r --arg a "$_ag" --arg e "$_et" '
    ((.decisions // .decisoes) // [])
    | map(select((($a == "") or ((.agent // .agente) == $a)) and (($e == "") or ((.stage // .etapa) == $e))))
    | .[]
    | [.id, (.wave_id // .onda_id), (.agent // .agente), (.stage // .etapa), (.choice // .escolha)] | @tsv
  ' "$_sf"
}

# ---------- subcomando: mark-invalid (issue #144) ----------
_sd_cmd_mark_invalid() {
  _sdir=""
  _did=""
  _motivo=""
  _ag="operador"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)  _sdir=$2;   shift 2 ;;
      --decisao-id) _did=$2;    shift 2 ;;
      --motivo)     _motivo=$2; shift 2 ;;
      --agente)     _ag=$2;     shift 2 ;;
      *) _sd_die_usage "mark-invalid: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]   || _sd_die_usage "mark-invalid: --state-dir obrigatorio"
  [ -n "$_did" ]    || _sd_die_usage "mark-invalid: --decisao-id obrigatorio"
  [ -n "$_motivo" ] || _sd_die_usage "mark-invalid: --motivo obrigatorio"
  case "$_did" in dec-[0-9][0-9][0-9]*) ;; *) _sd_die_usage "mark-invalid: --decisao-id invalido (esperado dec-NNN): '$_did'" ;; esac
  if [ "$(printf '%s' "$_motivo" | wc -c | tr -d ' ')" -lt 20 ]; then
    _sd_die "mark-invalid: --motivo < 20 chars (Principio I — justificativa auditavel)" 1
  fi
  _sd_require_jq

  # Documento materializado nos dois backends (interface canonica de leitura).
  _mi_doc=$(sh "$_SD_DIR/state-rw.sh" read --state-dir "$_sdir") \
    || _sd_die "mark-invalid: falha ao ler estado em $_sdir" 1
  _mi_orig=$(printf '%s' "$_mi_doc" | jq -c --arg id "$_did" '
    ((.decisions // .decisoes) // []) | map(select(.id == $id)) | .[0] // empty')
  [ -n "$_mi_orig" ] || _sd_die "mark-invalid: decisao '$_did' nao encontrada" 1
  _mi_orig_choice=$(printf '%s' "$_mi_orig" | jq -r '(.choice // .escolha) // ""')
  case "$_mi_orig_choice" in
    invalidar-dec-*) _sd_die "mark-invalid: '$_did' e ela mesma uma invalidacao (escolha '$_mi_orig_choice') — invalidacao nao se encadeia; registre nova Decisao normal se a invalidacao foi indevida" 1 ;;
  esac
  _mi_prev=$(printf '%s' "$_mi_doc" | jq -r --arg id "$_did" '
    ((.decisions // .decisoes) // [])
    | map(select(((.originating_artifact // .artefato_originador) == $id)
                 and ((.choice // .escolha) == ("invalidar-" + $id))))
    | .[0].id // empty')
  [ -z "$_mi_prev" ] || _sd_die "mark-invalid: '$_did' ja invalidada por $_mi_prev" 1
  _mi_stage=$(printf '%s' "$_mi_orig" | jq -r '(.stage // .etapa) // "desconhecida"')

  _sd_cmd_register --state-dir "$_sdir" \
    --agente "$_ag" --etapa "$_mi_stage" \
    --contexto "INVALIDACAO de $_did: $_motivo" \
    --opcoes "[\"manter-$_did\",\"invalidar-$_did\"]" \
    --escolha "invalidar-$_did" \
    --justificativa "$_motivo" \
    --artefato-originador "$_did"
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
  state-decisions.sh mark-invalid --state-dir DIR --decisao-id dec-NNN \
    --motivo TEXT(>=20) [--agente A]     # issue #144: invalidacao append-only

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
  mark-invalid)    _sd_cmd_mark_invalid "$@" ;;
  -h|--help|help)  exec sh -c "exit 0" ;;
  *) _sd_die_usage "subcomando desconhecido: $_SD_SUBCMD" ;;
esac
