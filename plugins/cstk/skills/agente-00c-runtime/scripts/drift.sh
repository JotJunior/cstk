#!/bin/sh
# drift.sh — drift detection / goal alignment (FR-027).
#
# Ref: docs/specs/agente-00c/spec.md FR-027
#      docs/specs/agente-00c/threat-model.md T4
#      docs/specs/agente-00c/tasks.md FASE 5.4
#      docs/specs/agente-00c-evolucao/tasks.md §1.2 (refactor pos-execucao)
#
# Modelo: na primeira onda o orquestrador extrai aspectos-chave do
# projeto-alvo e grava em 3 camadas:
#
#   .initial_key_aspects     — UCs / objetivos de produto (obrigatorio)
#   .technical_key_aspects   — backbone tecnico (auth, sessao, db, infra)
#   .operational_key_aspects — fases operacionais (runbooks, CI/CD)
#
# A cada onda, `drift.sh check` decide se a execucao esta desviada
# olhando uma JANELA MOVEL das ultimas 12 ondas (configuravel via
# DRIFT_WINDOW_SIZE). Uma onda e "tocada" se:
#   a) Qualquer decisao da onda menciona qualquer aspecto (qualquer
#      camada), via match bidirecional (texto contem aspecto OU aspecto
#      contem token do texto, ambos case-insensitive, tokens >=3 chars).
#   b) OU `.waves[i].touched_key_aspects` foi populado explicitamente
#      (via `drift.sh mark-touched` quando inferencia falha).
#
# Thresholds default (sobre untouched na janela):
#   < 5  : OK (exit 0)
#   5..7 : WARN (exit 0, stderr)
#   >= 8 : ABORT desvio_de_finalidade (exit 3)
#
# A janela movel substitui o gatilho antigo "5 ondas consecutivas =
# abort", que classificava backbone tecnico legitimo (ex: FASE 4.x infra)
# como desvio mesmo quando intercalado com UCs de produto.
#
# Subcomandos:
#   drift.sh init --state-dir DIR --aspectos JSON-ARRAY
#                 [--tecnicos JSON-ARRAY] [--operacionais JSON-ARRAY]
#                 [--force]
#       — Grava aspectos no estado. `--aspectos` (iniciais) e obrigatorio,
#         3..7 strings nao-vazias. `--tecnicos` e `--operacionais` sao
#         opcionais, 0..7 strings cada. Falha se ja foi inicializado
#         (a menos que --force seja passado).
#
#   drift.sh check --state-dir DIR
#       — Avalia janela movel de ondas. Stdout: numero de ondas SEM
#         aspecto na janela. Exit 0 (ok/warn), exit 3 (abort).
#
#   drift.sh key-aspects --state-dir DIR [--camada iniciais|tecnicos|operacionais|all]
#       — Lista aspectos em stdout (um por linha). Default: all.
#         (alias deprecado: `aspectos` — schema-en-migration.)
#
#   drift.sh extract --text TEXT [--max N]
#       — Extrai 1..N keywords (default 7) de texto cru. NAO le state.json.
#         Deterministico (lowercase + split + stopwords pt/en + dedupe + top-N).
#         Stdout: JSON array. Usado pelo command-pai p/ derivar --key-aspects.
#
#   drift.sh mark-touched --state-dir DIR --aspecto X
#       — Registra que a onda corrente tocou aspecto X explicitamente.
#         Usado quando inferencia automatica via decisoes falhar.
#
#   drift.sh debug --state-dir DIR [--onda ID]
#       — Diagnostico: lista aspectos por camada + para cada onda
#         (ou onda especifica), mostra quais aspectos foram detectados
#         e por qual mecanismo (decisao vs mark-touched).
#
# Exit codes:
#   0 alinhado (ou warn)
#   1 erro generico
#   2 uso incorreto
#   3 desvio_de_finalidade — aborto
#
# POSIX sh + jq.

set -eu

# Leitura de estado via interface canonica (state-db-runtime-parity FR-001):
# usada pelos subcomandos LEITORES (check). Subcomandos mutadores (init,
# mark-touched) seguem no builder direto — fora do escopo do porte 2.1.3.
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_DR_NAME="drift"
_DR_WINDOW_SIZE="${DRIFT_WINDOW_SIZE:-12}"
_DR_WARN_THRESHOLD="${DRIFT_WARN_THRESHOLD:-5}"
_DR_ABORT_THRESHOLD="${DRIFT_ABORT_THRESHOLD:-8}"

_dr_die_usage() { printf '%s: %s\n' "$_DR_NAME" "$1" >&2; exit 2; }
_dr_die()       { printf '%s: %s\n' "$_DR_NAME" "$1" >&2; exit "${2:-1}"; }

_dr_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _dr_die "jq nao encontrado no PATH" 1
}

_dr_state_file() { printf '%s/state.json\n' "$1"; }

_dr_atomic_write() {
  _dst=$1; _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _dr_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _dr_die "I/O cp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _dr_die "mv" 1; }
}

_dr_update_sha() {
  _sf=$(_dr_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

# _dr_validate_aspectos_array JSON-STR MIN MAX LABEL
# Exit 0 valido; 1 invalido (escreve mensagem em stderr).
_dr_validate_aspectos_array() {
  _arr=$1; _min=$2; _max=$3; _label=$4
  if ! printf '%s' "$_arr" | jq -e "
    type == \"array\"
    and length >= $_min and length <= $_max
    and all(.[]; type == \"string\" and (. | length) > 0)
  " >/dev/null 2>&1; then
    _dr_die "init: $_label precisa ser JSON array com $_min..$_max strings nao-vazias" 1
  fi
}

_dr_cmd_init() {
  _sd=""
  _asp=""
  _tec="[]"
  _ope="[]"
  _force=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)    _sd=$2;  shift 2 ;;
      --aspectos)     _asp=$2; shift 2 ;;
      --tecnicos)     _tec=$2; shift 2 ;;
      --operacionais) _ope=$2; shift 2 ;;
      --force)        _force=1; shift ;;
      *) _dr_die_usage "init: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]  || _dr_die_usage "init: --state-dir obrigatorio"
  [ -n "$_asp" ] || _dr_die_usage "init: --aspectos obrigatorio (JSON array de strings)"
  _dr_require_jq

  _sf=$(_dr_state_file "$_sd")
  [ -f "$_sf" ] || _dr_die "init: state.json ausente em $_sd" 1

  _dr_validate_aspectos_array "$_asp" 3 7 "--aspectos"
  _dr_validate_aspectos_array "$_tec" 0 7 "--tecnicos"
  _dr_validate_aspectos_array "$_ope" 0 7 "--operacionais"

  # Verifica se ja foi inicializado. Com --force, sobrescreve; sem,
  # falha (congelado pos-primeira-onda como antes).
  _existing=$(jq -r '(.initial_key_aspects // .aspectos_chave_iniciais) // [] | length' "$_sf")
  if [ "$_existing" -gt 0 ] && [ "$_force" -eq 0 ]; then
    _dr_die "init: initial_key_aspects ja foi gravado ($_existing aspectos). Use --force para sobrescrever (relaxado para retomada de execucoes legadas com aspectos=null)." 1
  fi

  # Writer (schema-en-migration): grava chaves EN. Confia em EN-on-disk
  # (migrate defensivo do command-pai no inicio da onda).
  _new_state=$(mktemp) || _dr_die "mktemp falhou" 1
  jq \
    --argjson a "$_asp" \
    --argjson t "$_tec" \
    --argjson o "$_ope" \
    '
    .initial_key_aspects     = $a
    | .technical_key_aspects   = $t
    | .operational_key_aspects = $o
    ' "$_sf" > "$_new_state" \
    || { rm -f -- "$_new_state"; _dr_die "jq update falhou" 1; }
  _dr_atomic_write "$_sf" "$_new_state"
  rm -f -- "$_new_state" 2>/dev/null || :
  _dr_update_sha "$_sd"
}

# Programa jq compartilhado pelas funcoes check/debug:
# define todos os aspectos (union das 3 camadas) e a funcao de match
# bidirecional via tokens.
_dr_jq_lib() {
  cat <<'JQ'
def all_aspectos:
  (((.initial_key_aspects     // .aspectos_chave_iniciais)     // []) +
   ((.technical_key_aspects   // .aspectos_chave_tecnicos)     // []) +
   ((.operational_key_aspects // .aspectos_chave_operacionais) // []))
  | unique;

# Tokeniza string em palavras alfanumericas >= 3 chars, lowercase.
def tokenize($s):
  ($s // "")
  | ascii_downcase
  | gsub("[^a-z0-9]+"; " ")
  | split(" ")
  | map(select(length >= 3));

# Match bidirecional case-insensitive:
#   1. texto inteiro (lowercased) CONTEM aspecto inteiro (lowercased)
#   2. OU qualquer token do texto e igual a qualquer token do aspecto
#      (cobre o caso "mcp-jira" vs "integracao-bidirecional-mcp-jira")
def matches_aspecto($txt; $aspecto):
  ($txt // "" | ascii_downcase) as $t
  | ($aspecto | ascii_downcase) as $a
  | ($t | contains($a))
    or (
      (tokenize($t)) as $tt
      | (tokenize($aspecto)) as $ta
      | any($tt[]; . as $x | any($ta[]; . == $x))
    );

# Para uma decisao, retorna lista de aspectos detectados (qualquer
# aspecto que dispare match contra contexto/escolha/justificativa).
def aspectos_hit_in_dec($dec; $aspectos):
  $aspectos
  | map(. as $a
        | select(matches_aspecto($dec.context // $dec.contexto; $a)
                 or matches_aspecto($dec.choice // $dec.escolha; $a)
                 or matches_aspecto($dec.rationale // $dec.justificativa; $a)));

# Para uma onda, retorna { hits_decisao: [...], hits_marcado: [...] }.
def aspectos_hit_in_onda($onda; $decs; $aspectos):
  ($decs | map(select((.wave_id // .onda_id) == $onda.id))) as $wave_decs
  | ($wave_decs | map(aspectos_hit_in_dec(.; $aspectos)) | flatten | unique) as $hd
  | ((($onda.touched_key_aspects // $onda.aspectos_chave_tocados) // []) | unique) as $hm
  | { hits_decisao: $hd, hits_marcado: $hm };

# Onda esta "tocada" se hits_decisao OR hits_marcado tem ao menos 1 item.
def onda_tocada($onda; $decs; $aspectos):
  (aspectos_hit_in_onda($onda; $decs; $aspectos))
  | (.hits_decisao | length) + (.hits_marcado | length) > 0;
JQ
}

# _dr_count_untouched_in_window STATE_FILE WINDOW_SIZE
# Stdout: numero de ondas SEM aspecto na janela das ultimas N ondas.
_dr_count_untouched_in_window() {
  _sf=$1; _win=$2
  _lib=$(_dr_jq_lib)
  jq -r --argjson win "$_win" "
    $_lib

    all_aspectos as \$aspectos
    | ((.waves // .ondas) // []) as \$ondas
    | ((.decisions // .decisoes) // []) as \$decs
    | if (\$aspectos | length) == 0 then 0
      else
        (\$ondas | length) as \$total
        | (if \$total > \$win then \$ondas[(\$total - \$win):] else \$ondas end) as \$window
        | \$window
          | map(select(onda_tocada(.; \$decs; \$aspectos) | not))
          | length
      end
  " "$_sf"
}

_dr_cmd_check() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _dr_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _dr_die_usage "check: --state-dir obrigatorio"
  _dr_require_jq
  # Materializa via _state-read.sh (json: proprio state.json; sqlite: tmp).
  # Falha do read sob sqlite propaga via set -e (FR-012).
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _dr_die "check: state.json ausente" 1

  _aspectos_count=$(jq -r '
    (((.initial_key_aspects // .aspectos_chave_iniciais) // []) +
     ((.technical_key_aspects // .aspectos_chave_tecnicos) // []) +
     ((.operational_key_aspects // .aspectos_chave_operacionais) // []))
    | unique | length
  ' "$_sf")
  if [ "$_aspectos_count" = 0 ]; then
    printf '0\n'
    printf '%s: aspectos_chave (todas camadas) vazios — drift check desabilitado.\n' "$_DR_NAME" >&2
    return 0
  fi

  _untouched=$(_dr_count_untouched_in_window "$_sf" "$_DR_WINDOW_SIZE")
  printf '%s\n' "$_untouched"

  if [ "$_untouched" -ge "$_DR_ABORT_THRESHOLD" ]; then
    printf '%s: desvio_de_finalidade — %s ondas sem tocar aspectos-chave em janela de %s (abort >= %s)\n' \
      "$_DR_NAME" "$_untouched" "$_DR_WINDOW_SIZE" "$_DR_ABORT_THRESHOLD" >&2
    exit 3
  fi
  if [ "$_untouched" -ge "$_DR_WARN_THRESHOLD" ]; then
    printf '%s: AVISO — %s ondas sem tocar aspectos-chave em janela de %s (warn >= %s, abort >= %s)\n' \
      "$_DR_NAME" "$_untouched" "$_DR_WINDOW_SIZE" "$_DR_WARN_THRESHOLD" "$_DR_ABORT_THRESHOLD" >&2
  fi
  exit 0
}

_dr_cmd_aspectos() {
  _sd=""
  _cam="all"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      --camada)    _cam=$2; shift 2 ;;
      *) _dr_die_usage "aspectos: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _dr_die_usage "aspectos: --state-dir obrigatorio"
  _dr_require_jq
  _sf=$(_dr_state_file "$_sd")
  [ -f "$_sf" ] || _dr_die "aspectos: state.json ausente" 1

  # --camada VALUES (iniciais/tecnicos/operacionais) sao valores de flag (nao
  # migrados; follow-up B). Apenas as CHAVES JSON lidas viram EN (+fallback).
  case "$_cam" in
    iniciais)     jq -r '(.initial_key_aspects     // .aspectos_chave_iniciais)     // [] | .[]' "$_sf" ;;
    tecnicos)     jq -r '(.technical_key_aspects   // .aspectos_chave_tecnicos)     // [] | .[]' "$_sf" ;;
    operacionais) jq -r '(.operational_key_aspects // .aspectos_chave_operacionais) // [] | .[]' "$_sf" ;;
    all)
      jq -r '
        (((.initial_key_aspects     // .aspectos_chave_iniciais)     // []) +
         ((.technical_key_aspects   // .aspectos_chave_tecnicos)     // []) +
         ((.operational_key_aspects // .aspectos_chave_operacionais) // []))
        | unique | .[]
      ' "$_sf"
      ;;
    *) _dr_die_usage "key-aspects: --camada deve ser iniciais|tecnicos|operacionais|all" ;;
  esac
}

_dr_cmd_mark_touched() {
  _sd=""
  _aspecto=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;        shift 2 ;;
      --aspecto)   _aspecto=$2;   shift 2 ;;
      *) _dr_die_usage "mark-touched: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]        || _dr_die_usage "mark-touched: --state-dir obrigatorio"
  [ -n "$_aspecto" ]   || _dr_die_usage "mark-touched: --aspecto obrigatorio"
  _dr_require_jq

  _sf=$(_dr_state_file "$_sd")
  [ -f "$_sf" ] || _dr_die "mark-touched: state.json ausente" 1

  _has_onda=$(jq -r '((.waves // .ondas) // []) | length' "$_sf")
  if [ "$_has_onda" -eq 0 ]; then
    _dr_die "mark-touched: nenhuma onda existe em state.json (chame state-ondas.sh start primeiro)" 1
  fi

  # Writer (schema-en-migration): grava chave EN (.waves[-1].touched_key_aspects).
  # Confia em EN-on-disk (migrate defensivo do command-pai).
  _new_state=$(mktemp) || _dr_die "mktemp falhou" 1
  jq --arg a "$_aspecto" '
    .waves[-1].touched_key_aspects =
      ((.waves[-1].touched_key_aspects // []) + [$a] | unique)
  ' "$_sf" > "$_new_state" \
    || { rm -f -- "$_new_state"; _dr_die "jq update falhou" 1; }
  _dr_atomic_write "$_sf" "$_new_state"
  rm -f -- "$_new_state" 2>/dev/null || :
  _dr_update_sha "$_sd"
}

_dr_cmd_debug() {
  _sd=""
  _onda=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;   shift 2 ;;
      --onda)      _onda=$2; shift 2 ;;
      *) _dr_die_usage "debug: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _dr_die_usage "debug: --state-dir obrigatorio"
  _dr_require_jq
  _sf=$(_dr_state_file "$_sd")
  [ -f "$_sf" ] || _dr_die "debug: state.json ausente" 1

  _lib=$(_dr_jq_lib)
  jq -r --arg only "$_onda" "
    $_lib

    \"=== aspectos_chave (por camada) ===\",
    \"iniciais: \"     + (((.initial_key_aspects     // .aspectos_chave_iniciais)     // []) | join(\", \")),
    \"tecnicos: \"     + (((.technical_key_aspects   // .aspectos_chave_tecnicos)     // []) | join(\", \")),
    \"operacionais: \" + (((.operational_key_aspects // .aspectos_chave_operacionais) // []) | join(\", \")),
    \"\",
    \"=== ondas (janela=$_DR_WINDOW_SIZE, warn>=$_DR_WARN_THRESHOLD untouched, abort>=$_DR_ABORT_THRESHOLD untouched) ===\",
    (
      all_aspectos as \$aspectos
      | ((.decisions // .decisoes) // []) as \$decs
      | ((.waves // .ondas) // [])
        | map(select(\$only == \"\" or .id == \$only))
        | .[]
        | . as \$o
        | aspectos_hit_in_onda(\$o; \$decs; \$aspectos) as \$h
        | (if (\$h.hits_decisao | length) + (\$h.hits_marcado | length) > 0
            then \"TOUCHED\"
            else \"untouched\"
           end) as \$state
        | \"\\(\$o.id) [\\(\$state)] decisao=\\(\$h.hits_decisao | join(\",\")) marcado=\\(\$h.hits_marcado | join(\",\"))\"
    )
  " "$_sf"
}

# _dr_cmd_extract: extrai keywords de texto cru (NAO le state.json).
# Substitui o `drift.sh extract` fantasma que os docs do command-pai chamavam
# sem implementacao. Deterministico: lowercase, split em nao-alfanumerico,
# tokens >= 3 chars, remove stopwords (pt+en), dedupe preservando ordem,
# top-N (default 7). Stdout: JSON array (pode ser vazio). Usado pelo
# command-pai feature-00c para derivar --key-aspects do state-rw.sh init.
_dr_cmd_extract() {
  _text=""
  _text_set=0
  _max=7
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --text) _text=$2; _text_set=1; shift 2 ;;
      --max)  _max=$2;  shift 2 ;;
      *) _dr_die_usage "extract: flag desconhecida: $1" ;;
    esac
  done
  [ "$_text_set" = 1 ] || _dr_die_usage "extract: --text obrigatorio"
  case "$_max" in ''|*[!0-9]*) _dr_die_usage "extract: --max deve ser inteiro positivo" ;; esac
  [ "$_max" -ge 1 ] || _dr_die_usage "extract: --max deve ser >= 1"
  _dr_require_jq
  printf '%s' "$_text" | jq -R -s --argjson max "$_max" '
    ["a","o","os","as","e","de","da","do","das","dos","em","no","na","nos",
     "nas","um","uma","uns","umas","para","por","com","sem","que","se","ao",
     "aos","ou","the","of","and","to","in","on","for","with","without",
     "that","this","is","are","be","or","an","at","by","as"] as $stop
    | ascii_downcase
    | gsub("[^a-z0-9]+"; " ")
    | split(" ")
    | map(select(length >= 3 and (. as $w | ($stop | index($w)) | not)))
    | reduce .[] as $w ([]; if index($w) then . else . + [$w] end)
    | .[0:$max]
  '
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<HELP
drift.sh — drift detection / goal alignment (FR-027).

USO:
  drift.sh init         --state-dir DIR --aspectos JSON-ARRAY
                        [--tecnicos JSON-ARRAY] [--operacionais JSON-ARRAY]
                        [--force]
  drift.sh check        --state-dir DIR
  drift.sh key-aspects  --state-dir DIR [--camada iniciais|tecnicos|operacionais|all]
                        (alias deprecado: "aspectos")
  drift.sh extract      --text TEXT [--max N]   (keywords de texto cru; nao le state)
  drift.sh mark-touched --state-dir DIR --aspecto X
  drift.sh debug        --state-dir DIR [--onda ID]

Janela movel: ${_DR_WINDOW_SIZE} ultimas ondas. Untouched na janela:
  >= ${_DR_WARN_THRESHOLD} = warn (exit 0 + stderr)
  >= ${_DR_ABORT_THRESHOLD} = abort exit 3 (desvio_de_finalidade)

Override via env: DRIFT_WINDOW_SIZE, DRIFT_WARN_THRESHOLD,
DRIFT_ABORT_THRESHOLD.
HELP
  exit 2
fi

_DR_SUBCMD=$1
shift

case "$_DR_SUBCMD" in
  init)            _dr_cmd_init "$@" ;;
  check)           _dr_cmd_check "$@" ;;
  key-aspects)     _dr_cmd_aspectos "$@" ;;
  aspectos)        printf '%s: subcomando "aspectos" deprecado — use "key-aspects" (schema-en-migration; removido na proxima major).\n' "$_DR_NAME" >&2
                   _dr_cmd_aspectos "$@" ;;
  extract)         _dr_cmd_extract "$@" ;;
  mark-touched)    _dr_cmd_mark_touched "$@" ;;
  debug)           _dr_cmd_debug "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _dr_die_usage "subcomando desconhecido: $_DR_SUBCMD" ;;
esac
