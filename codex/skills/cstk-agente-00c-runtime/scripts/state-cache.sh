#!/bin/sh
# state-cache.sh — cache de artefatos foundational (briefing, constitution)
# em state.json do agente-00c. Reduz overhead de re-leitura em ondas N>1.
#
# Ref: docs/specs/agente-00c-artifact-cache/spec.md FR-CACHE-001..017A
#      docs/specs/agente-00c-artifact-cache/plan.md §API Contracts
#      docs/specs/agente-00c-artifact-cache/tasks.md T1.1-T1.7
#
# Subcomandos:
#   state-cache.sh ensure --state-dir DIR --artifact briefing|constitution
#       --source-path PATH
#     — Calcula sha256, decide estrategia (passthrough se chars<threshold,
#       senao resumo), gera resumo via heuristica extractiva, atualiza
#       state.json. Exit 0 sucesso; 1 source ausente; 2 erro fatal.
#
#   state-cache.sh get-resumo --state-dir DIR --artifact briefing|constitution
#     — Imprime resumo em stdout se cache hit (estrategia=resumo + sha256
#       confirmado). Exit 0 hit; 1 miss; 2 erro fatal.
#
#   state-cache.sh check-drift --state-dir DIR --artifact briefing|constitution
#     — Compara sha256 registrado vs hash atual em disco. Exit 0 sem drift;
#       1 drift MINOR/PATCH; 2 drift MAJOR; 3 erro fatal.
#
#   state-cache.sh invalidate --state-dir DIR --artifact briefing|constitution
#       --razao TEXT
#     — Zera campo do cache; registra Decisao via state-decisions.sh.
#
#   state-cache.sh metrics-bump --state-dir DIR --tipo hit|miss-drift|miss-disabled
#       [--chars-economizados N]
#     — Incrementa contador em .accumulated_metrics.cache.<tipo>.
#
#   state-cache.sh status --state-dir DIR --artifact briefing|constitution
#     — Imprime JSON com estado completo do cache. Exit 0 sempre que
#       state.json eh valido.
#
# Exit codes:
#   0 sucesso (ou cache hit em get-resumo)
#   1 erro recuperavel (miss, source ausente, drift MINOR)
#   2 drift MAJOR (em check-drift) ou erro fatal noutros subcomandos
#   3 erro fatal em check-drift
#
# POSIX sh + jq + sha256 wrapper.

set -eu

_SC_NAME="state-cache"
_SC_DIR=$(cd "$(dirname -- "$0")" && pwd)

# Helpers sourceaveis
. "$_SC_DIR/_hash.sh"

_sc_die_usage() { printf '%s: %s\n' "$_SC_NAME" "$1" >&2; exit 2; }
_sc_die() {      printf '%s: %s\n' "$_SC_NAME" "$1" >&2; exit "${2:-2}"; }

_sc_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    _sc_die "jq nao encontrado no PATH (brew install jq | apt install jq)" 2
  fi
}

_sc_iso_now() { date -u +%FT%TZ; }
_sc_state_file() { printf '%s/state.json\n' "$1"; }

# Defaults (FR-CACHE-007)
_SC_PASSTHROUGH_DEFAULT=3000
_SC_RESUMO_MAX_DEFAULT=2000
_SC_RATIO_DEFAULT="0.25"

# _sc_config STATE_DIR FIELD DEFAULT
#   Le .config.cache.<FIELD> do state.json com fallback DEFAULT.
_sc_config() {
  _sf=$(_sc_state_file "$1")
  _field=$2
  _default=$3
  [ -f "$_sf" ] || { printf '%s\n' "$_default"; return 0; }
  _val=$(jq -r --arg f "$_field" '.config.cache[$f] // empty' "$_sf" 2>/dev/null || true)
  [ -n "$_val" ] && printf '%s\n' "$_val" || printf '%s\n' "$_default"
}

# _sc_validate_artifact NAME
_sc_validate_artifact() {
  case "${1:-}" in
    briefing|constitution) return 0 ;;
    *) _sc_die "artifact invalido: '${1:-}' (esperado: briefing|constitution)" 2 ;;
  esac
}

# _sc_cache_field ARTIFACT -> nome do campo top-level no state.json
_sc_cache_field() {
  case "$1" in
    briefing)     printf 'briefing_cache' ;;
    constitution) printf 'constitution_cache' ;;
  esac
}

# _sc_atomic_set STATE_DIR JQ_FILTER
#   Aplica JQ_FILTER sobre state.json em tmp, depois mv atomico.
_sc_atomic_set() {
  _sd=$1
  _filter=$2
  _sf=$(_sc_state_file "$_sd")
  [ -f "$_sf" ] || _sc_die "state.json ausente em $_sd" 2
  _tmp=$(mktemp -- "${_sf}.XXXXXX") || _sc_die "mktemp falhou" 2
  jq "$_filter" "$_sf" >"$_tmp" || { rm -f -- "$_tmp"; _sc_die "jq filter falhou" 2; }
  mv -f -- "$_tmp" "$_sf" || { rm -f -- "$_tmp"; _sc_die "mv atomico falhou" 2; }
}

# _sc_summarize RESUMO_MAX
#   Le stdin (texto markdown), imprime resumo extractivo em stdout.
#   Algoritmo (FR-CACHE-005, decidido em clarify Q1):
#     1. Extrai linhas com `^## ` ou `^### ` (preserva ordem + hierarquia)
#     2. Para cada heading, anexa a primeira linha de corpo nao-vazia logo abaixo
#     3. Se output excede RESUMO_MAX, dropa `### H3` em ordem inversa ate caber
#     4. Output deterministico (mesma entrada = mesma saida byte-a-byte)
_sc_summarize() {
  _max=$1
  awk -v MAX="$_max" '
    BEGIN { n = 0 }
    /^##[ #]/ {
      # capturar tipo (h2 ou h3+)
      level = 2
      if ($0 ~ /^### /) level = 3
      if ($0 ~ /^#### /) next  # h4+ ignorado
      heading[n] = $0
      level_arr[n] = level
      body[n] = ""
      n++
      next
    }
    NR > 0 && n > 0 && body[n-1] == "" {
      # primeira linha nao-vazia de corpo apos heading
      _line = $0
      sub(/^[ \t]+/, "", _line)
      sub(/[ \t]+$/, "", _line)
      if (_line != "") {
        body[n-1] = _line
      }
    }
    END {
      # 1a passada: monta output completo
      out = ""
      for (i = 0; i < n; i++) {
        out = out heading[i] "\n"
        if (body[i] != "") out = out body[i] "\n"
      }
      # 2a passada: se excede MAX, dropa H3 em ordem inversa
      if (length(out) > MAX) {
        for (i = n - 1; i >= 0; i--) {
          if (level_arr[i] == 3) {
            heading[i] = ""
            body[i] = ""
            # remonta
            out = ""
            for (j = 0; j < n; j++) {
              if (heading[j] != "") {
                out = out heading[j] "\n"
                if (body[j] != "") out = out body[j] "\n"
              }
            }
            if (length(out) <= MAX) break
          }
        }
      }
      printf "%s", out
    }
  '
}

# ==== Subcomando: ensure ====
_sc_cmd_ensure() {
  _sd="" _art="" _src=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)   _sd=$2;  shift 2 ;;
      --artifact)    _art=$2; shift 2 ;;
      --source-path) _src=$2; shift 2 ;;
      *) _sc_die_usage "ensure: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]  || _sc_die_usage "ensure: --state-dir obrigatorio"
  [ -n "$_art" ] || _sc_die_usage "ensure: --artifact obrigatorio"
  [ -n "$_src" ] || _sc_die_usage "ensure: --source-path obrigatorio"
  _sc_validate_artifact "$_art"
  _sc_require_jq

  if [ ! -r "$_src" ]; then
    printf '%s: ensure: source ausente ou nao legivel: %s\n' "$_SC_NAME" "$_src" >&2
    return 1
  fi

  _sf=$(_sc_state_file "$_sd")
  [ -f "$_sf" ] || _sc_die "ensure: state.json ausente em $_sd" 2

  _sha=$(_hash_sha256_file "$_src")
  _chars=$(wc -c <"$_src" | awk '{print $1}')
  _threshold=$(_sc_config "$_sd" passthrough_threshold_chars "$_SC_PASSTHROUGH_DEFAULT")
  # Config key (schema-en-migration §3.9d): summary_max_chars (EN) com fallback
  # ao pt-BR resumo_max_chars. Pega o EN; se vazio, tenta o pt-BR legado.
  _resumo_max=$(_sc_config "$_sd" summary_max_chars "")
  [ -n "$_resumo_max" ] || _resumo_max=$(_sc_config "$_sd" resumo_max_chars "$_SC_RESUMO_MAX_DEFAULT")
  _now=$(_sc_iso_now)
  _onda=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w | length)
    else 1
    end' "$_sf")

  if [ "$_chars" -lt "$_threshold" ]; then
    _estrategia="passthrough"
    _resumo=""
    _resumo_chars=0
  else
    _estrategia="resumo"
    _resumo=$(_sc_summarize "$_resumo_max" <"$_src")
    # Aplicar secrets-filter (FR-CACHE-006)
    _scrub="$_SC_DIR/secrets-filter.sh"
    if [ -x "$_scrub" ]; then
      _resumo=$(printf '%s' "$_resumo" | "$_scrub" scrub 2>/dev/null || printf '%s' "$_resumo")
    fi
    _resumo_chars=$(printf '%s' "$_resumo" | wc -c | awk '{print $1}')
  fi

  _field=$(_sc_cache_field "$_art")

  # Encode resumo como string JSON valida (jq -Rs faz: aspas + escape)
  _resumo_json=$(printf '%s' "$_resumo" | jq -Rs .)
  _sf=$(_sc_state_file "$_sd")
  _tmp=$(mktemp -- "${_sf}.XXXXXX") || _sc_die "mktemp falhou" 2
  # WRITER (schema-en-migration §3.9d + idiom §4.1): chaves EN no state.json.
  # resumo->summary, resumo_chars->summary_chars, estrategia->strategy,
  # gerado_em->generated_at, gerado_na_onda->generated_in_wave.
  # Containers/folhas source_* = KEEP (ja EN). VALOR de strategy = KEEP.
  jq --arg src "$_src" \
     --arg sha "$_sha" \
     --argjson chars "$_chars" \
     --argjson resumo "$_resumo_json" \
     --argjson resumo_chars "$_resumo_chars" \
     --arg estrategia "$_estrategia" \
     --arg now "$_now" \
     --argjson onda "$_onda" \
     ".${_field} = {
        source_path: \$src,
        source_sha256: \$sha,
        source_chars: \$chars,
        summary: \$resumo,
        summary_chars: \$resumo_chars,
        strategy: \$estrategia,
        generated_at: \$now,
        generated_in_wave: \$onda
      }" "$_sf" >"$_tmp" || { rm -f -- "$_tmp"; _sc_die "ensure: jq filter falhou" 2; }
  mv -f -- "$_tmp" "$_sf" || { rm -f -- "$_tmp"; _sc_die "ensure: mv atomico falhou" 2; }

  printf '%s: ensure: %s cache populado (estrategia=%s, source_chars=%d, resumo_chars=%d)\n' \
    "$_SC_NAME" "$_art" "$_estrategia" "$_chars" "$_resumo_chars" >&2
  return 0
}

# ==== Subcomando: get-resumo ====
_sc_cmd_get_resumo() {
  _sd="" _art=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;  shift 2 ;;
      --artifact)  _art=$2; shift 2 ;;
      *) _sc_die_usage "get-resumo: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]  || _sc_die_usage "get-resumo: --state-dir obrigatorio"
  [ -n "$_art" ] || _sc_die_usage "get-resumo: --artifact obrigatorio"
  _sc_validate_artifact "$_art"
  _sc_require_jq

  _sf=$(_sc_state_file "$_sd")
  [ -f "$_sf" ] || { printf '%s: state.json ausente\n' "$_SC_NAME" >&2; return 2; }

  # READER (schema-en-migration §4.3): path EN + fallback (.en // .pt).
  # VALOR "resumo" da strategy = KEEP (follow-up B).
  _field=$(_sc_cache_field "$_art")
  _estrat=$(jq -r "(.${_field}.strategy // .${_field}.estrategia) // \"\"" "$_sf")
  if [ "$_estrat" != "resumo" ]; then
    return 1
  fi

  _src=$(jq -r ".${_field}.source_path // \"\"" "$_sf")
  _registered_sha=$(jq -r ".${_field}.source_sha256 // \"\"" "$_sf")
  if [ -z "$_src" ] || [ -z "$_registered_sha" ]; then
    return 1
  fi
  if [ ! -r "$_src" ]; then
    return 1  # source desapareceu — caller cai em fallback
  fi
  _current_sha=$(_hash_sha256_file "$_src")
  if [ "$_current_sha" != "$_registered_sha" ]; then
    return 1  # drift entre check inicial e consumo (TOCTOU-safe double-check)
  fi
  jq -r "(.${_field}.summary // .${_field}.resumo) // \"\"" "$_sf"
  return 0
}

# ==== Subcomando: check-drift ====
_sc_cmd_check_drift() {
  _sd="" _art=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;  shift 2 ;;
      --artifact)  _art=$2; shift 2 ;;
      *) _sc_die_usage "check-drift: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]  || _sc_die_usage "check-drift: --state-dir obrigatorio"
  [ -n "$_art" ] || _sc_die_usage "check-drift: --artifact obrigatorio"
  _sc_validate_artifact "$_art"
  _sc_require_jq

  _sf=$(_sc_state_file "$_sd")
  [ -f "$_sf" ] || { printf '%s: state.json ausente\n' "$_SC_NAME" >&2; return 3; }

  _field=$(_sc_cache_field "$_art")
  _src=$(jq -r ".${_field}.source_path // \"\"" "$_sf")
  _registered_sha=$(jq -r ".${_field}.source_sha256 // \"\"" "$_sf")
  _registered_chars=$(jq -r ".${_field}.source_chars // 0" "$_sf")

  if [ -z "$_src" ] || [ -z "$_registered_sha" ]; then
    # Sem cache populado — nao ha drift (vazio = sem expectativa)
    return 0
  fi
  if [ ! -r "$_src" ]; then
    printf '%s: source desapareceu: %s\n' "$_SC_NAME" "$_src" >&2
    return 2  # tratar como drift MAJOR (arquivo sumiu)
  fi

  _current_sha=$(_hash_sha256_file "$_src")
  if [ "$_current_sha" = "$_registered_sha" ]; then
    return 0  # sem drift
  fi

  # Detectar MAJOR para constitution: mudanca no primeiro digito da version
  if [ "$_art" = "constitution" ]; then
    _new_ver=$(grep -E '^\*\*Version\*\*:' "$_src" 2>/dev/null | sed -E 's/.*\*\*Version\*\*: ([0-9]+)\.[0-9]+\.[0-9]+.*/\1/' | head -1)
    _old_ver=$(jq -r ".${_field}.version // \"\"" "$_sf" | cut -d. -f1)
    if [ -n "$_new_ver" ] && [ -n "$_old_ver" ] && [ "$_new_ver" != "$_old_ver" ]; then
      return 2  # MAJOR
    fi
  fi

  # Detectar MAJOR via >50% mudanca de chars
  _current_chars=$(wc -c <"$_src" | awk '{print $1}')
  _diff=$((_current_chars - _registered_chars))
  if [ "$_diff" -lt 0 ]; then _diff=$((-_diff)); fi
  if [ "$_registered_chars" -gt 0 ]; then
    _percent=$((_diff * 100 / _registered_chars))
    if [ "$_percent" -gt 50 ]; then
      return 2  # MAJOR
    fi
  fi

  return 1  # MINOR/PATCH
}

# ==== Subcomando: invalidate ====
_sc_cmd_invalidate() {
  _sd="" _art="" _razao=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;    shift 2 ;;
      --artifact)  _art=$2;   shift 2 ;;
      --razao)     _razao=$2; shift 2 ;;
      *) _sc_die_usage "invalidate: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]    || _sc_die_usage "invalidate: --state-dir obrigatorio"
  [ -n "$_art" ]   || _sc_die_usage "invalidate: --artifact obrigatorio"
  [ -n "$_razao" ] || _sc_die_usage "invalidate: --razao obrigatorio"
  _sc_validate_artifact "$_art"
  _sc_require_jq

  _field=$(_sc_cache_field "$_art")
  _sc_atomic_set "$_sd" ".${_field} = null"

  # Registrar Decisao auditavel (FR-CACHE-011) — best-effort: se state-decisions.sh
  # disponivel, registra; senao apenas warning em stderr.
  _decs="$_SC_DIR/state-decisions.sh"
  if [ -x "$_decs" ]; then
    "$_decs" register --state-dir "$_sd" \
      --agente "state-cache" \
      --etapa "cache-invalidacao" \
      --contexto "Invalidacao manual de ${_art}_cache: $_razao" \
      --opcoes '["regenerar","manter-stale","abortar"]' \
      --escolha "regenerar" \
      --justificativa "Politica FR-CACHE-009: invalidacao registrada para auditoria; cache sera repopulado na proxima invocacao de ensure" \
      >/dev/null 2>&1 || \
      printf '%s: invalidate: aviso — state-decisions.sh falhou em registrar Decisao\n' "$_SC_NAME" >&2
  fi
  printf '%s: invalidate: %s cache zerado\n' "$_SC_NAME" "$_art" >&2
  return 0
}

# ==== Subcomando: metrics-bump ====
_sc_cmd_metrics_bump() {
  _sd="" _tipo="" _chars=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)            _sd=$2;    shift 2 ;;
      --tipo)                 _tipo=$2;  shift 2 ;;
      --chars-economizados)   _chars=$2; shift 2 ;;
      *) _sc_die_usage "metrics-bump: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]   || _sc_die_usage "metrics-bump: --state-dir obrigatorio"
  [ -n "$_tipo" ] || _sc_die_usage "metrics-bump: --tipo obrigatorio"
  _sc_require_jq

  _ratio=$(_sc_config "$_sd" tokens_per_char_ratio "$_SC_RATIO_DEFAULT")

  case "$_tipo" in
    hit)
      _tokens=$(awk -v c="$_chars" -v r="$_ratio" 'BEGIN { printf "%d", c * r }')
      # WRITER (schema-en-migration §3.9d): grava EN estimated_tokens_saved.
      # READ-MODIFY-WRITE: o seed do contador cai no fallback pt-BR
      # (tokens_economizados_estimados) p/ nao zerar metrica de state legado.
      # tokens_cache_hits = KEEP (folha tokens_cache_*). VALOR nunca tocado.
      _sc_atomic_set "$_sd" "
        .accumulated_metrics.cache.tokens_cache_hits =
          ((.accumulated_metrics.cache.tokens_cache_hits // 0) + 1)
        | .accumulated_metrics.cache.estimated_tokens_saved =
          (((.accumulated_metrics.cache.estimated_tokens_saved // .accumulated_metrics.cache.tokens_economizados_estimados) // 0) + $_tokens)
      "
      ;;
    miss-drift)
      _sc_atomic_set "$_sd" ".accumulated_metrics.cache.tokens_cache_misses_drift =
        ((.accumulated_metrics.cache.tokens_cache_misses_drift // 0) + 1)"
      ;;
    miss-disabled)
      _sc_atomic_set "$_sd" ".accumulated_metrics.cache.tokens_cache_misses_disabled =
        ((.accumulated_metrics.cache.tokens_cache_misses_disabled // 0) + 1)"
      ;;
    *)
      _sc_die_usage "metrics-bump: --tipo invalido: '$_tipo' (esperado: hit|miss-drift|miss-disabled)"
      ;;
  esac
  return 0
}

# ==== Subcomando: status ====
_sc_cmd_status() {
  _sd="" _art=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2;  shift 2 ;;
      --artifact)  _art=$2; shift 2 ;;
      *) _sc_die_usage "status: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]  || _sc_die_usage "status: --state-dir obrigatorio"
  [ -n "$_art" ] || _sc_die_usage "status: --artifact obrigatorio"
  _sc_validate_artifact "$_art"
  _sc_require_jq

  _sf=$(_sc_state_file "$_sd")
  [ -f "$_sf" ] || _sc_die "state.json ausente em $_sd" 2

  _field=$(_sc_cache_field "$_art")
  jq ".${_field} // null" "$_sf"
  return 0
}

# ==== Dispatcher ====
_sc_main() {
  [ "$#" -gt 0 ] || _sc_die_usage "subcomando obrigatorio (ensure|get-resumo|check-drift|invalidate|metrics-bump|status)"
  _cmd=$1; shift
  case "$_cmd" in
    ensure)        _sc_cmd_ensure        "$@" ;;
    get-resumo)    _sc_cmd_get_resumo    "$@" ;;
    check-drift)   _sc_cmd_check_drift   "$@" ;;
    invalidate)    _sc_cmd_invalidate    "$@" ;;
    metrics-bump)  _sc_cmd_metrics_bump  "$@" ;;
    status)        _sc_cmd_status        "$@" ;;
    --help|-h)     sed -n '2,40p' "$0" ;;
    *) _sc_die_usage "subcomando desconhecido: $_cmd" ;;
  esac
}

_sc_main "$@"
