#!/bin/sh
# state-ondas.sh — gerencia ciclo de vida de Ondas (FASE 3.4).
#
# Ref: docs/specs/agente-00c/data-model.md §Onda
#      docs/specs/agente-00c/spec.md FR-009
#      docs/specs/agente-00c/research.md Decision 1
#      docs/specs/agente-00c/tasks.md FASE 3.4
#
# Subcomandos:
#   state-ondas.sh start --state-dir DIR
#       — Append nova Onda em .ondas com:
#           id = onda-NNN sequencial
#           inicio = ISO now
#           etapas_executadas = []
#           tool_calls = 0
#         Reseta .orcamentos.tool_calls_onda_corrente = 0 e
#         .orcamentos.inicio_onda_corrente = inicio.
#         Stdout: id da nova onda.
#
#   state-ondas.sh end --state-dir DIR --motivo-termino MOTIVO
#                      [--proxima-agendada-para ISO]
#                      [--add-etapa STAGE]
#       — Atualiza ultima Onda (.ondas[-1]) com fim/wallclock_seconds/
#         tool_calls/motivo_termino/proxima_onda_agendada_para. Atualiza
#         metricas_acumuladas (ondas_total += 1, tool_calls_total +=
#         tool_calls da onda, tempo_wallclock_total_segundos += wallclock).
#         --add-etapa pode ser passada N vezes para append em etapas_executadas.
#
#   state-ondas.sh tool-call-tick --state-dir DIR
#       — Incrementa .orcamentos.tool_calls_onda_corrente (1 unidade).
#         Stdout: novo total da onda.
#
#   state-ondas.sh current-id --state-dir DIR
#       — Imprime .ondas[-1].id (ou "init" se nao ha onda).
#
#   state-ondas.sh record-skill --state-dir DIR --skill NAME
#                               [--decisao-id DEC-NNN]
#       — Registra invocacao da skill na onda corrente. Append em
#         .ondas[-1].skills_invoked = [..., { skill, timestamp, decisao_id }].
#         Permite review-task auditar "etapa X foi marcada completa mas a
#         skill Y nunca foi invocada via tool Skill" — defesa contra o
#         padrao da execucao-fonte onde orquestrador gerou artefatos
#         in-process sem chamar a skill canonica (dec-014: tasks.md sem
#         create-tasks invocada).
#         Idempotente para a mesma combinacao (skill + decisao_id na mesma
#         onda) — re-registro nao duplica entrada.
#         Stdout: numero total de skills invocadas nesta onda.
#
#   state-ondas.sh record-task --state-dir DIR --task-id ID --outcome pass|fail
#                              [--titulo T] [--wave-id ID] [--testes-rodados N]
#                              [--testes-passados N] [--lint-ok true|false]
#                              [--arquivos JSON] [--origem TAG] [--if-absent]
#       — Upsert idempotente de UMA entrada em .tasks[] (chave = task_id).
#         Caminho de escrita auditado (substitui o jq hand-rolled que vivia
#         na prosa dos orquestradores). Default sobrescreve; --if-absent so
#         insere se ausente. Stdout: total de entradas em .tasks[].
#
#   state-ondas.sh reconcile-tasks --state-dir DIR --tasks-md PATH
#                                  [--wave-id ID] [--dry-run]
#       — Rede de seguranca deterministica: le tasks.md e back-filla em
#         .tasks[] (via record-task --if-absent) toda task CONCLUIDA (heading
#         `### N.M` com todas as subtarefas-checkbox `[x]`) que esteja
#         faltando. NAO grava tasks pendentes/bloqueadas (sem outcome final).
#         Idempotente. Stdout: nº back-filled; --dry-run lista os faltantes.
#
#   state-ondas.sh git-commit --state-dir DIR --projeto-alvo-path PATH
#                             --motivo MOTIVO [--onda-id ID]
#       — Faz `git add .` + `git commit -m 'chore(agente-00c): onda <ID> - <MOTIVO>'`
#         dentro de --projeto-alvo-path. NUNCA push (Principio V).
#         Idempotente: se nao ha mudancas para commitar, retorna 0 sem erro.
#         Sem fail-soft: se git nao existe / dir nao e repo, exit 1.
#
# Exit codes:
#   0 sucesso
#   1 erro generico (state ausente, git falhou)
#   2 uso incorreto
#
# POSIX sh + jq + git (apenas em git-commit).

set -eu

_SO_NAME="state-ondas"

_so_die_usage() { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; exit 2; }
_so_die()       { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; exit "${2:-1}"; }
_so_log()       { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; }

_so_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _so_die "jq nao encontrado no PATH" 1
}

_so_iso_now() { date -u +%FT%TZ; }
_so_state_file() { printf '%s/state.json\n' "$1"; }

_so_atomic_write() {
  _dst=$1; _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _so_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _so_die "I/O cp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _so_die "mv" 1; }
}

_so_update_sha() {
  _sf=$(_so_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

_so_backup_current() {
  _sf=$(_so_state_file "$1")
  [ -f "$_sf" ] || return 0
  _hd="$1/state-history"
  mkdir -p -- "$_hd" 2>/dev/null || _so_die "mkdir state-history falhou" 1
  _curr=$(jq -r '
    if (.ondas // []) | length > 0 then (.ondas[-1].id // "init") else "init" end
  ' "$_sf" 2>/dev/null) || _curr="init"
  _ts=$(date -u +%Y%m%dT%H%M%SZ)
  _bk="$_hd/${_curr}-${_ts}.json"
  mv -- "$_sf" "$_bk" || _so_die "backup falhou" 1
}

_so_next_onda_num() {
  _sf=$(_so_state_file "$1")
  jq -r '
    if (.ondas // []) | length == 0 then 1
    else (([.ondas[].id // ""] | map(sub("^onda-0*"; "") | tonumber? // 0) | max) + 1)
    end' "$_sf" 2>/dev/null
}

# ---------- Subcomandos ----------

_so_cmd_start() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "start: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "start: --state-dir obrigatorio"
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "start: state.json ausente em $_sdir" 1

  _num=$(_so_next_onda_num "$_sdir")
  _id=$(printf 'onda-%03d' "$_num")
  _now=$(_so_iso_now)

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq --arg id "$_id" --arg ts "$_now" '
    .ondas += [{
      id: $id,
      inicio: $ts,
      fim: null,
      etapas_executadas: [],
      tool_calls: 0,
      wallclock_seconds: 0,
      motivo_termino: null,
      proxima_onda_agendada_para: null,
      skills_invoked: []
    }]
    | .orcamentos.tool_calls_onda_corrente = 0
    | .orcamentos.inicio_onda_corrente = $ts
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_backup_current "$_sdir"
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  printf '%s\n' "$_id"
}

# Calcula wallclock em segundos entre dois timestamps ISO.
# Implementa fallback portavel: tenta `date -d` (GNU), depois `date -j -f` (BSD).
_so_wallclock() {
  _start=$1
  _fim=$2
  if _se=$(date -u -d "$_start" +%s 2>/dev/null) && _fe=$(date -u -d "$_fim" +%s 2>/dev/null); then
    printf '%s\n' "$((_fe - _se))"
    return 0
  fi
  if _se=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_start" +%s 2>/dev/null) \
     && _fe=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_fim" +%s 2>/dev/null); then
    printf '%s\n' "$((_fe - _se))"
    return 0
  fi
  printf '0\n'
  return 1
}

_so_cmd_end() {
  _sdir=""
  _motivo=""
  _proxima="null"
  _etapas=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)             _sdir=$2; shift 2 ;;
      --motivo-termino)        _motivo=$2; shift 2 ;;
      --proxima-agendada-para) _proxima=$2; shift 2 ;;
      --add-etapa)             _etapas="$_etapas
$2"; shift 2 ;;
      *) _so_die_usage "end: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]   || _so_die_usage "end: --state-dir obrigatorio"
  [ -n "$_motivo" ] || _so_die_usage "end: --motivo-termino obrigatorio"
  case "$_motivo" in
    etapa_concluida_avancando|threshold_proxy_atingido|bloqueio_humano|aborto|concluido) ;;
    *) _so_die "end: motivo invalido: $_motivo" 2 ;;
  esac
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "end: state.json ausente em $_sdir" 1

  _now=$(_so_iso_now)
  _start=$(jq -r 'if (.ondas // []) | length > 0 then (.ondas[-1].inicio // "") else "" end' "$_sf")
  [ -n "$_start" ] || _so_die "end: nao ha onda em andamento" 1
  _wc=$(_so_wallclock "$_start" "$_now") || true
  _tc=$(jq -r '.orcamentos.tool_calls_onda_corrente // 0' "$_sf")

  # Monta JSON array das etapas adicionais (uma por linha, ignora linhas vazias).
  _etapas_json=$(printf '%s\n' "$_etapas" \
    | sed '/^$/d' \
    | jq -R . \
    | jq -s .)

  _proxima_json="null"
  if [ "$_proxima" != "null" ]; then
    _proxima_json="\"$_proxima\""
  fi

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg now "$_now" \
    --arg motivo "$_motivo" \
    --argjson wc "$_wc" \
    --argjson tc "$_tc" \
    --argjson etapas "$_etapas_json" \
    --argjson prox "$_proxima_json" '
    (.ondas[-1] |= (
      .fim = $now
      | .wallclock_seconds = $wc
      | .tool_calls = $tc
      | .motivo_termino = $motivo
      | .proxima_onda_agendada_para = $prox
      | .etapas_executadas += $etapas
    ))
    | .metricas_acumuladas.ondas_total = ((.metricas_acumuladas.ondas_total // 0) + 1)
    | .metricas_acumuladas.tool_calls_total = ((.metricas_acumuladas.tool_calls_total // 0) + $tc)
    | .metricas_acumuladas.tempo_wallclock_total_segundos =
        ((.metricas_acumuladas.tempo_wallclock_total_segundos // 0) + $wc)
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_backup_current "$_sdir"
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  _so_log "end: onda finalizada (motivo=$_motivo, wallclock=${_wc}s, tool_calls=$_tc)"
}

_so_cmd_tool_call_tick() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "tool-call-tick: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "tool-call-tick: --state-dir obrigatorio"
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "tool-call-tick: state.json ausente" 1

  _curr=$(jq -r '.orcamentos.tool_calls_onda_corrente // 0' "$_sf")
  _next=$((_curr + 1))

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq --argjson n "$_next" '.orcamentos.tool_calls_onda_corrente = $n' "$_sf" > "$_new" \
    || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }
  # tool-call-tick e operacao de alta frequencia; backup so a cada 10 ticks
  # para nao explodir state-history/. Em ticks intermediarios o atomic_write
  # ja sobrescreve via `mv -f` — nao precisa rm.
  if [ "$((_next % 10))" = 0 ]; then
    _so_backup_current "$_sdir"
  fi
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  printf '%s\n' "$_next"
}

_so_cmd_record_skill() {
  _sdir=""
  _skill=""
  _dec=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)  _sdir=$2;  shift 2 ;;
      --skill)      _skill=$2; shift 2 ;;
      --decisao-id) _dec=$2;   shift 2 ;;
      *) _so_die_usage "record-skill: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]  || _so_die_usage "record-skill: --state-dir obrigatorio"
  [ -n "$_skill" ] || _so_die_usage "record-skill: --skill obrigatorio"
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "record-skill: state.json ausente em $_sdir" 1

  # Verifica que existe onda em andamento
  _has_onda=$(jq -r 'if (.ondas // []) | length > 0 then "yes" else "no" end' "$_sf")
  [ "$_has_onda" = "yes" ] || _so_die "record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)" 1

  _now=$(_so_iso_now)
  _dec_json="null"
  if [ -n "$_dec" ]; then
    _dec_json=$(printf '%s' "$_dec" | jq -R .)
  fi

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg skill "$_skill" \
    --arg ts "$_now" \
    --argjson dec "$_dec_json" '
    (.ondas[-1].skills_invoked //= [])
    | (.ondas[-1].skills_invoked |=
        (if (any(.[]; .skill == $skill and (.decisao_id // null) == $dec))
         then .
         else . + [{
           skill: $skill,
           timestamp: $ts,
           decisao_id: $dec
         }]
         end))
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  _count=$(jq -r '.ondas[-1].skills_invoked | length' "$_sf")
  printf '%s\n' "$_count"
}

# record-task: upsert idempotente de UMA entrada em .tasks[] (top-level).
# Chave natural dentro de um state.json (= uma execucao) = task_id. Substitui
# o snippet jq hand-rolled que vivia SO na prosa dos orquestradores (§5.d.ter):
# caminho de escrita auditado, atomico (state-history backup + sha256),
# idempotente. Diferente de record-skill, NAO exige onda em andamento —
# .tasks[] e top-level e pode ser gravado tambem na fase review-task.
#
# Default = UPSERT (sobrescreve a entrada existente com dados frescos — usado
# pelo execute-task, que conhece o outcome real). --if-absent = so insere se
# AUSENTE (no-op se ja existe; usado pelo back-fill reconcile-tasks, para nao
# clobberar uma entrada real com uma derivada).
#
# Campos `recorded_at`/`origem` sao ADITIVOS — a ingestao knowledge.db
# (recall.sh) seleciona apenas os 8 campos do contrato layer-b e ignora o
# resto; servem para o review-task distinguir entradas reais de back-filled.
# Stdout: total de entradas em .tasks[] apos a operacao.
_so_cmd_record_task() {
  _sdir=""; _tid=""; _ttl=""; _wid=""; _oc=""
  _tr="0"; _tp="0"; _lk=""; _af="[]"; _origem=""; _ifabsent="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)       _sdir=$2; shift 2 ;;
      --task-id)         _tid=$2;  shift 2 ;;
      --titulo)          _ttl=$2;  shift 2 ;;
      --wave-id)         _wid=$2;  shift 2 ;;
      --outcome)         _oc=$2;   shift 2 ;;
      --testes-rodados)  _tr=$2;   shift 2 ;;
      --testes-passados) _tp=$2;   shift 2 ;;
      --lint-ok)         _lk=$2;   shift 2 ;;
      --arquivos)        _af=$2;   shift 2 ;;
      --origem)          _origem=$2; shift 2 ;;
      --if-absent)       _ifabsent="yes"; shift ;;
      *) _so_die_usage "record-task: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "record-task: --state-dir obrigatorio"
  [ -n "$_tid" ]  || _so_die_usage "record-task: --task-id obrigatorio"
  [ -n "$_oc" ]   || _so_die_usage "record-task: --outcome obrigatorio"
  case "$_oc" in pass|fail) : ;; *) _so_die_usage "record-task: --outcome deve ser pass|fail" ;; esac
  case "$_tr" in ''|*[!0-9]*) _so_die_usage "record-task: --testes-rodados deve ser inteiro >= 0" ;; esac
  case "$_tp" in ''|*[!0-9]*) _so_die_usage "record-task: --testes-passados deve ser inteiro >= 0" ;; esac
  [ "$_tp" -le "$_tr" ] || _so_die_usage "record-task: --testes-passados ($_tp) > --testes-rodados ($_tr)"
  case "$_lk" in
    true|1)  _lk_json=true ;;
    false|0) _lk_json=false ;;
    '')      _lk_json=null ;;
    *) _so_die_usage "record-task: --lint-ok deve ser true|false (ou vazio)" ;;
  esac
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "record-task: state.json ausente em $_sdir" 1
  printf '%s' "$_af" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || _so_die_usage "record-task: --arquivos deve ser um array JSON (ex: '[]')"

  # wave-id default = onda corrente (proveniencia best-effort)
  if [ -z "$_wid" ]; then
    _wid=$(jq -r 'if (.ondas // []) | length > 0 then (.ondas[-1].id // "") else "" end' "$_sf" 2>/dev/null) || _wid=""
  fi

  _now=$(_so_iso_now)
  _origem_json=null
  [ -n "$_origem" ] && _origem_json=$(printf '%s' "$_origem" | jq -R .)

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg tid "$_tid" --arg ttl "$_ttl" --arg wid "$_wid" --arg oc "$_oc" \
    --argjson tr "$_tr" --argjson tp "$_tp" --argjson lk "$_lk_json" \
    --argjson af "$_af" --arg ts "$_now" --argjson origem "$_origem_json" \
    --arg ifabsent "$_ifabsent" '
    (.tasks //= [])
    | {task_id:$tid, titulo:$ttl, wave_id:$wid, outcome:$oc,
       testes_rodados:$tr, testes_passados:$tp, lint_ok:$lk,
       arquivos_tocados:$af, recorded_at:$ts, origem:$origem} as $e
    | if any(.tasks[]; .task_id == $tid)
      then (if $ifabsent == "yes" then .
            else .tasks |= map(if .task_id == $tid then $e else . end) end)
      else .tasks += [$e]
      end
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "record-task: jq update falhou" 1; }

  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  jq -r '(.tasks // []) | length' "$_sf"
}

# reconcile-tasks: rede de seguranca DETERMINISTICA contra perda de tasks.
# Le tasks.md (fonte de verdade do backlog) e garante que toda TASK CONCLUIDA
# tenha entrada em .tasks[]. Uma task = heading `### N.M {Titulo}`; esta
# CONCLUIDA quando tem >=1 subtarefa-checkbox e TODAS marcadas `[x]`. Tasks
# pendentes/em-andamento/bloqueadas NAO sao gravadas (nao ha outcome final —
# evita fabricar pass/fail). Back-fill via record-task --if-absent: NUNCA
# clobbera entrada real ja gravada pelo execute-task. Idempotente.
#
# Stdout (default): numero de tasks back-filled nesta chamada.
# --dry-run: NAO escreve; imprime os task_id que SERIAM back-filled (um por
#   linha) — usado pelo gate de completude do review-task.
_so_cmd_reconcile_tasks() {
  _rc_sdir=""; _rc_md=""; _rc_wid=""; _rc_dry="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _rc_sdir=$2; shift 2 ;;
      --tasks-md)  _rc_md=$2;   shift 2 ;;
      --wave-id)   _rc_wid=$2;  shift 2 ;;
      --dry-run)   _rc_dry="yes"; shift ;;
      *) _so_die_usage "reconcile-tasks: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_rc_sdir" ] || _so_die_usage "reconcile-tasks: --state-dir obrigatorio"
  [ -n "$_rc_md" ]   || _so_die_usage "reconcile-tasks: --tasks-md obrigatorio"
  _so_require_jq
  _rc_sf=$(_so_state_file "$_rc_sdir")
  [ -f "$_rc_sf" ] || _so_die "reconcile-tasks: state.json ausente em $_rc_sdir" 1
  [ -f "$_rc_md" ] || _so_die "reconcile-tasks: tasks.md ausente: $_rc_md" 1

  if [ -z "$_rc_wid" ]; then
    _rc_wid=$(jq -r 'if (.ondas // []) | length > 0 then (.ondas[-1].id // "") else "" end' "$_rc_sf" 2>/dev/null) || _rc_wid=""
  fi

  # task_ids ja presentes em .tasks[] (snapshot)
  _rc_exfile=$(mktemp) || _so_die "mktemp falhou" 1
  jq -r '(.tasks // [])[].task_id // empty' "$_rc_sf" > "$_rc_exfile" 2>/dev/null || :

  # awk: parseia tasks.md -> emite "id<TAB>titulo" para cada task CONCLUIDA
  # ainda AUSENTE de .tasks[]. O seen-set vem do primeiro arquivo (_rc_exfile);
  # comparamos por FILENAME (nao FNR==NR) porque o exfile pode estar VAZIO
  # (.tasks[] ainda sem entradas) — FNR==NR falharia consumindo o tasks.md
  # inteiro como seen-set.
  _rc_missing=$(awk -v exf="$_rc_exfile" '
    { sub(/\r$/, "") }
    FILENAME == exf { seen[$0] = 1; next }
    function flush() {
      if (cur != "" && nsub > 0 && ndone == nsub && !(cur in seen)) {
        print cur "\t" titulo
      }
      cur = ""; titulo = ""; nsub = 0; ndone = 0
    }
    /^#/ {
      flush()
      if ($0 ~ /^### /) {
        line = $0; sub(/^### +/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          cur = id
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); sub(/[ \t]*\[[CAM]\][ \t]*$/, "", t)
          gsub(/\t/, " ", t)
          titulo = t
        }
      }
      next
    }
    /^- \[.\] / {
      if (cur != "") {
        st = substr($0, 4, 1)
        nsub++
        if (st == "x" || st == "X") ndone++
      }
      next
    }
    END { flush() }
  ' "$_rc_exfile" "$_rc_md")
  rm -f -- "$_rc_exfile" 2>/dev/null || :

  if [ -z "$_rc_missing" ]; then
    [ "$_rc_dry" = "yes" ] || printf '0\n'
    return 0
  fi

  if [ "$_rc_dry" = "yes" ]; then
    printf '%s\n' "$_rc_missing" | cut -f1
    return 0
  fi

  # Loop via here-doc (roda no shell corrente, nao em subshell — contador
  # persiste). record-task usa vars sem prefixo _rc_, entao nao colide com
  # _rc_id/_rc_ttl/_rc_count/_rc_missing do loop.
  _rc_count=0
  while IFS="$(printf '\t')" read -r _rc_id _rc_ttl; do
    [ -n "$_rc_id" ] || continue
    _so_cmd_record_task --state-dir "$_rc_sdir" --task-id "$_rc_id" \
      --titulo "$_rc_ttl" --wave-id "$_rc_wid" --outcome pass \
      --testes-rodados 0 --testes-passados 0 \
      --arquivos '[]' --origem reconcile --if-absent >/dev/null \
      || _so_die "reconcile-tasks: record-task falhou para $_rc_id" 1
    _rc_count=$((_rc_count + 1))
  done <<EOF
$_rc_missing
EOF
  printf '%s\n' "$_rc_count"
}

_so_cmd_current_id() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "current-id: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "current-id: --state-dir obrigatorio"
  _so_require_jq
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "current-id: state.json ausente" 1
  jq -r '
    if (.ondas // []) | length > 0 then (.ondas[-1].id // "init") else "init" end
  ' "$_sf"
}

# git-commit: faz commit local no projeto-alvo (NUNCA push — Principio V).
_so_cmd_git_commit() {
  _sdir=""
  _pap=""
  _motivo=""
  _onda=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)         _sdir=$2; shift 2 ;;
      --projeto-alvo-path) _pap=$2;  shift 2 ;;
      --motivo)            _motivo=$2; shift 2 ;;
      --onda-id)           _onda=$2; shift 2 ;;
      *) _so_die_usage "git-commit: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]   || _so_die_usage "git-commit: --state-dir obrigatorio"
  [ -n "$_pap" ]    || _so_die_usage "git-commit: --projeto-alvo-path obrigatorio"
  [ -n "$_motivo" ] || _so_die_usage "git-commit: --motivo obrigatorio"
  command -v git >/dev/null 2>&1 || _so_die "git-commit: git nao encontrado no PATH" 1
  [ -d "$_pap" ] || _so_die "git-commit: projeto-alvo-path nao existe: $_pap" 1
  if [ ! -d "$_pap/.git" ]; then
    _so_die "git-commit: $_pap nao e repositorio git (init manual antes)" 1
  fi
  if [ -z "$_onda" ]; then
    _onda=$(_so_cmd_current_id --state-dir "$_sdir")
  fi
  # Sanitiza motivo: remove newlines + limita a 100 chars
  _motivo_safe=$(printf '%s' "$_motivo" | tr '\n\r' '  ' | cut -c 1-100)
  # Add ALL changes (estado + artefatos da pipeline). Sem -A para nao incluir
  # paths fora de cwd; usamos -- "$_pap" se necessario.
  ( cd -- "$_pap" \
    && git add -- . \
    && if git diff --cached --quiet; then
         _so_log "git-commit: nada para commitar (no-op)"
       else
         git commit -m "chore(agente-00c): $_onda - $_motivo_safe" >/dev/null \
           || _so_die "git commit falhou em $_pap" 1
         _so_log "git-commit: commit feito ($_onda)"
       fi
  ) || exit 1
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
state-ondas.sh — ciclo de vida de Ondas (FASE 3.4).

USO:
  state-ondas.sh start          --state-dir DIR
  state-ondas.sh end            --state-dir DIR --motivo-termino MOTIVO
                                [--proxima-agendada-para ISO]
                                [--add-etapa STAGE]...
  state-ondas.sh tool-call-tick --state-dir DIR
  state-ondas.sh record-skill   --state-dir DIR --skill NAME
                                [--decisao-id DEC-NNN]
  state-ondas.sh record-task    --state-dir DIR --task-id ID --outcome pass|fail
                                [--titulo T] [--wave-id ID] [--testes-rodados N]
                                [--testes-passados N] [--lint-ok true|false]
                                [--arquivos JSON-ARRAY] [--origem TAG] [--if-absent]
  state-ondas.sh reconcile-tasks --state-dir DIR --tasks-md PATH
                                [--wave-id ID] [--dry-run]
  state-ondas.sh current-id     --state-dir DIR
  state-ondas.sh git-commit     --state-dir DIR --projeto-alvo-path PATH
                                --motivo MOTIVO [--onda-id ID]

Motivos validos para `end`:
  etapa_concluida_avancando | threshold_proxy_atingido | bloqueio_humano |
  aborto | concluido

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto

NUNCA `git push` — Principio V (Blast Radius Confinado).
HELP
  exit 2
fi

_SO_SUBCMD=$1
shift

case "$_SO_SUBCMD" in
  start)            _so_cmd_start "$@" ;;
  end)              _so_cmd_end "$@" ;;
  tool-call-tick)   _so_cmd_tool_call_tick "$@" ;;
  record-skill)     _so_cmd_record_skill "$@" ;;
  record-task)      _so_cmd_record_task "$@" ;;
  reconcile-tasks)  _so_cmd_reconcile_tasks "$@" ;;
  current-id)       _so_cmd_current_id "$@" ;;
  git-commit)       _so_cmd_git_commit "$@" ;;
  -h|--help|help)   exit 0 ;;
  *) _so_die_usage "subcomando desconhecido: $_SO_SUBCMD" ;;
esac
