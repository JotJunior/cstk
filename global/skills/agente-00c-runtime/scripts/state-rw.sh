#!/bin/sh
# state-rw.sh — read/write helpers para state.json do agente-00C.
#
# Ref: docs/specs/agente-00c/contracts/state-schema.md
#      docs/specs/agente-00c/data-model.md
#      docs/specs/agente-00c/spec.md FR-008/FR-017/FR-024/FR-029
#
# Chaves do state.json sao EN (schema-en-migration). Toda leitura/escrita passa
# por _sr_canonicalize_file (rename pt-BR -> EN); states pt-BR vivos sao aceitos
# na entrada e convergem para EN a cada write. Ver
# docs/specs/schema-en-migration/migration-map.md.
#
# Subcomandos:
#   state-rw.sh init  --state-dir DIR --execucao-id ID
#                     --projeto-alvo-path PATH --descricao TEXT
#                     [--stack-json TEXT] [--whitelist-urls JSON-ARRAY]
#                     — modo PROJETO (agente-00c): cria state.json
#                       (current_stage="briefing") + sha256 + state-history/
#   state-rw.sh init  --state-dir DIR --short-name NAME
#                     --projeto-alvo-path PATH --descricao TEXT
#                     --briefing-path P --briefing-sha256 S
#                     --constitution-path P --constitution-sha256 S
#                     --constitution-version V [--key-aspects JSON-ARRAY]
#                     [--execucao-id ID] [--stack-json TEXT] [--whitelist-urls JSON]
#                     — modo FEATURE (feature-00c): emite schema de feature
#                       (short_name + prerequisites + current_stage="specify")
#                       numa unica chamada deterministica. execucao-id
#                       auto-derivado (feat-<short>-<ts>) se omitido.
#   state-rw.sh read  --state-dir DIR
#                     — imprime conteudo atual de state.json em stdout
#   state-rw.sh write --state-dir DIR
#                     — le novo conteudo em stdin, faz backup do anterior em
#                       state-history/onda-<NNN>-<ts>.json, regrava
#                       state.json + state.json.sha256
#   state-rw.sh get   --state-dir DIR --field 'JQ-PATH'
#                     — extrai campo via jq (ex: '.execucao.status')
#   state-rw.sh set   --state-dir DIR --field 'JQ-PATH' --value JSON
#                     — atualiza campo in-place (com backup + sha256)
#   state-rw.sh sha256-update --state-dir DIR
#                     — recalcula state.json.sha256 do state atual
#   state-rw.sh sha256-verify --state-dir DIR
#                     — exit 0 se hash bate, 1 se diverge (FR-029)
#   state-rw.sh path-check --projeto-alvo-path PATH
#                     — valida path: existe (ou cria), e diretorio, gravavel.
#                       NAO valida zonas proibidas — isso e FR-024 (FASE 6.1).
#   state-rw.sh infer-aspectos --state-dir DIR [--projeto-alvo-path PATH]
#                     — infere aspectos tocados pela onda corrente a
#                       partir de git diff --name-only HEAD~1..HEAD,
#                       aplicando matcher fuzzy contra union das 3
#                       camadas de aspectos (iniciais/tecnicos/operacionais).
#                       Stdout: JSON array de aspectos detectados (pode
#                       ser vazio). Nao escreve state.json — caller
#                       decide se chama `set --field
#                       '.ondas[-1].aspectos_chave_tocados' --value ...`.
#                       Ref: docs/specs/agente-00c-evolucao/tasks.md §2.3.
#
# Exit codes:
#   0  sucesso
#   1  erro generico (jq ausente, FS error, validacao falhou)
#   2  uso incorreto (flag invalida, subcomando desconhecido)
#
# POSIX sh + jq + sha256sum/shasum + mkdir/mv/touch + git.

set -eu

_SR_NAME="state-rw"

_sr_die() {
  printf '%s: %s\n' "$_SR_NAME" "$1" >&2
  exit "${2:-1}"
}

_sr_log() {
  printf '%s: %s\n' "$_SR_NAME" "$1" >&2
}

# ---------- Helpers portaveis ----------

# _sr_sha256_file FILE -> hex hash em stdout
_sr_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    _sr_die "sha256sum/shasum ausente — instale coreutils ou perl-shasum" 1
  fi
}

# _sr_iso_now -> timestamp UTC ISO 8601 (Z, sem milis)
_sr_iso_now() {
  # `date -u +%FT%TZ` funciona em GNU e BSD.
  date -u +%FT%TZ
}

# _sr_ts_for_filename -> timestamp safe para nome de arquivo (sem ":")
_sr_ts_for_filename() {
  date -u +%Y%m%dT%H%M%SZ
}

# _sr_require_jq -> aborta se jq ausente
_sr_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    _sr_die "jq nao encontrado no PATH. Instale com 'brew install jq' (macOS) ou 'apt install jq' (Debian/Ubuntu)." 1
  fi
}

# ---------- Canonicalizacao de chaves (schema-en-migration) ----------
#
# Migracao pt-BR -> EN das chaves do state.json. Mecanismo: rename plano
# context-free aplicado recursivamente em TODA leitura/escrita do state.
# pt-BR e aceito na entrada (states vivos), EN e canonico na saida; o arquivo
# converge para EN a cada write. Remover este mapa + os fallbacks na proxima
# MAJOR torna o schema EN-only.
# Spec: docs/specs/schema-en-migration/migration-map.md
#
# Invariante: nenhum par pt->en colide entre containers (verificado no freeze).
_SR_RENAME_MAP='{
  "execucao":"execution","etapa_corrente":"current_stage",
  "proxima_instrucao":"next_instruction","ondas":"waves","decisoes":"decisions",
  "bloqueios_humanos":"human_blocks","orcamentos":"budgets",
  "metricas_acumuladas":"accumulated_metrics",
  "whitelist_urls_externas":"external_urls_whitelist",
  "historico_movimento_circular":"circular_movement_history",
  "aspectos_chave_iniciais":"initial_key_aspects",
  "aspectos_chave_tecnicos":"technical_key_aspects",
  "aspectos_chave_operacionais":"operational_key_aspects",
  "aspectos_chave_tocados":"touched_key_aspects",
  "pre_requisitos":"prerequisites",
  "projeto_alvo_path":"target_project_path",
  "projeto_alvo_descricao":"target_project_description",
  "stack_sugerida":"suggested_stack","motivo_termino":"termination_reason",
  "iniciada_em":"started_at","terminada_em":"finished_at",
  "inicio":"started_at","fim":"finished_at",
  "etapas_executadas":"executed_stages",
  "proxima_onda_agendada_para":"next_wave_scheduled_for",
  "decisao_id":"decision_id","titulo":"title",
  "testes_rodados":"tests_run","testes_passados":"tests_passed",
  "arquivos":"files","arquivos_tocados":"touched_files","origem":"source",
  "score_justificativa":"justification_score",
  "problema_hash":"problem_hash","solucao_hash":"solution_hash",
  "sugestoes":"suggestions","skill_afetada":"affected_skill",
  "diagnostico":"diagnosis","severidade":"severity","proposta":"proposal",
  "criada_em":"created_at","issue_aberta":"issue_opened",
  "escalada_modelo_pendente":"pending_model_escalation",
  "resumo":"summary","resumo_chars":"summary_chars","resumo_max_chars":"summary_max_chars",
  "estrategia":"strategy","gerado_em":"generated_at","gerado_na_onda":"generated_in_wave",
  "tokens_economizados_estimados":"estimated_tokens_saved",
  "eventos":"events","descricao":"description","tipo_invocacao":"invocation_type",
  "proximo_marco_retrospectiva":"next_retrospective_milestone",
  "onda_id":"wave_id",
  "etapa":"stage","agente":"agent","contexto":"context",
  "opcoes_consideradas":"options_considered","escolha":"choice",
  "justificativa":"rationale","evidencia":"evidence",
  "referencias":"references","artefato_originador":"originating_artifact",
  "pergunta":"question","contexto_para_resposta":"context_for_answer",
  "opcoes_recomendadas":"recommended_options","resposta_humana":"human_answer",
  "respondido_em":"answered_at","disparado_em":"triggered_at",
  "recursividade_max":"max_recursion",
  "profundidade_corrente_subagentes":"current_subagent_depth",
  "retro_execucoes_max_por_feature":"max_retro_executions_per_feature",
  "retro_execucoes_consumidas":"retro_executions_consumed",
  "ciclos_max_por_etapa":"max_cycles_per_stage",
  "ciclos_consumidos_etapa_corrente":"cycles_consumed_current_stage",
  "tool_calls_threshold_onda":"tool_calls_threshold_wave",
  "wallclock_threshold_segundos":"wallclock_threshold_seconds",
  "estado_size_threshold_bytes":"state_size_threshold_bytes",
  "tool_calls_onda_corrente":"tool_calls_current_wave",
  "inicio_onda_corrente":"current_wave_start","ondas_total":"waves_total",
  "tempo_wallclock_total_segundos":"wallclock_total_seconds",
  "profundidade_max_atingida":"max_depth_reached",
  "subagentes_spawned":"subagents_spawned","decisoes_total":"decisions_total",
  "bloqueios_humanos_total":"human_blocks_total",
  "sugestoes_skills_globais_total":"global_skill_suggestions_total",
  "issues_toolkit_abertas":"toolkit_issues_opened","ratificados_em":"ratified_at"
}'

# _sr_canonicalize_file FILE -> emite JSON com chaves EN em stdout.
# Renomeia chaves pt-BR -> EN recursivamente. Idempotente sobre docs ja EN.
# `map_values`/`with_entries` (jq >= 1.5) — nao depende de `walk` builtin.
_sr_canonicalize_file() {
  jq --argjson m "$_SR_RENAME_MAP" '
    def _ren:
      if   type == "object" then with_entries(.key |= ($m[.] // .)) | map_values(_ren)
      elif type == "array"  then map(_ren)
      else . end;
    _ren
  ' -- "$1"
}

# ---------- Layout do state-dir ----------

_sr_state_file() { printf '%s/state.json\n' "$1"; }
_sr_sha_file()   { printf '%s/state.json.sha256\n' "$1"; }
_sr_history_dir() { printf '%s/state-history\n' "$1"; }

# _sr_ensure_state_dir DIR -> mkdir -p; abre se imposivel
_sr_ensure_state_dir() {
  if ! mkdir -p -- "$1" 2>/dev/null; then
    _sr_die "nao foi possivel criar state-dir: $1" 1
  fi
  if ! mkdir -p -- "$(_sr_history_dir "$1")" 2>/dev/null; then
    _sr_die "nao foi possivel criar state-history/: $(_sr_history_dir "$1")" 1
  fi
  # Touch test: garante gravabilidade antes de qualquer Write real (2.4.3).
  _sr_touchprobe="$1/.write-probe"
  if ! ( : > "$_sr_touchprobe" ) 2>/dev/null; then
    _sr_die "permissao de escrita negada em $1" 1
  fi
  rm -f -- "$_sr_touchprobe" 2>/dev/null || :
}

# _sr_atomic_write DST CONTENT_FILE -> mv atomico de tmp para DST
_sr_atomic_write() {
  _sr_dst=$1
  _sr_src=$2
  _sr_tmp=$(mktemp -- "${_sr_dst}.XXXXXX") || _sr_die "mktemp falhou em $(dirname -- "$_sr_dst")" 1
  # Captura erros de cp (disco cheio aparece aqui — task 2.4.4).
  if ! cp -- "$_sr_src" "$_sr_tmp"; then
    rm -f -- "$_sr_tmp" 2>/dev/null || :
    _sr_die "I/O error gravando em $_sr_tmp (disco cheio? quota?)" 1
  fi
  if ! mv -f -- "$_sr_tmp" "$_sr_dst"; then
    rm -f -- "$_sr_tmp" 2>/dev/null || :
    _sr_die "mv atomico falhou: $_sr_tmp -> $_sr_dst" 1
  fi
}

# _sr_update_sha STATE_DIR -> regrava state.json.sha256
_sr_update_sha() {
  _sr_sf=$(_sr_state_file "$1")
  _sr_shf=$(_sr_sha_file "$1")
  _sr_h=$(_sr_sha256_file "$_sr_sf")
  printf '%s\n' "$_sr_h" > "$_sr_shf" 2>/dev/null \
    || _sr_die "I/O error gravando $_sr_shf" 1
}

# _sr_next_onda_id STATE_DIR -> proximo numero sequencial de onda (NNN)
_sr_next_onda_id() {
  _sr_require_jq
  _sr_sf=$(_sr_state_file "$1")
  if [ ! -f "$_sr_sf" ]; then
    printf '001\n'
    return 0
  fi
  # Extrai max(waves[].id) numerico. id tem formato "onda-NNN" (valor nao
  # migrado). Fallback (.waves // .ondas) para states pt-BR vivos.
  _sr_max=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) == 0 then 0
      else ([$w[].id // ""] | map(sub("^onda-0*"; "") | tonumber? // 0) | max)
      end' -- "$_sr_sf" 2>/dev/null) || _sr_max=0
  _sr_next=$((_sr_max + 1))
  printf 'onda-%03d\n' "$_sr_next" | sed 's/onda-//'
}

# _sr_backup_current STATE_DIR -> move state.json -> state-history/
# Usa numero da onda corrente (default 001 se ainda nao houver) + ts.
_sr_backup_current() {
  _sr_sf=$(_sr_state_file "$1")
  [ -f "$_sr_sf" ] || return 0
  _sr_hd=$(_sr_history_dir "$1")
  mkdir -p -- "$_sr_hd" 2>/dev/null || _sr_die "nao consegui criar $_sr_hd" 1
  # Determina onda atual via .ondas[-1].id (se existir) — fallback "init".
  _sr_curr_onda="init"
  if command -v jq >/dev/null 2>&1; then
    _sr_curr_onda=$(jq -r '
      ((.waves // .ondas) // []) as $w
      | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end
    ' -- "$_sr_sf" 2>/dev/null) || _sr_curr_onda="init"
  fi
  _sr_ts=$(_sr_ts_for_filename)
  _sr_bk="$_sr_hd/${_sr_curr_onda}-${_sr_ts}.json"
  if ! mv -- "$_sr_sf" "$_sr_bk"; then
    _sr_die "backup falhou: $_sr_sf -> $_sr_bk" 1
  fi
}

# ---------- Subcomandos ----------

_sr_cmd_init() {
  _sd=""
  _ei=""
  _pap=""
  _desc=""
  _stack="null"
  _whitelist="[]"
  # Modo-feature (schema-en-migration): init deterministico de feature — fim do
  # recipe multi-passo (init base + N x set) que produzia states inconsistentes.
  _short=""
  _br_path=""
  _br_sha=""
  _ct_path=""
  _ct_sha=""
  _ct_ver=""
  _key_aspects="[]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)            _sd=$2;          shift 2 ;;
      --execucao-id)          _ei=$2;          shift 2 ;;
      --projeto-alvo-path)    _pap=$2;         shift 2 ;;
      --descricao)            _desc=$2;        shift 2 ;;
      --stack-json)           _stack=$2;       shift 2 ;;
      --whitelist-urls)       _whitelist=$2;   shift 2 ;;
      --short-name)           _short=$2;       shift 2 ;;
      --briefing-path)        _br_path=$2;     shift 2 ;;
      --briefing-sha256)      _br_sha=$2;      shift 2 ;;
      --constitution-path)    _ct_path=$2;     shift 2 ;;
      --constitution-sha256)  _ct_sha=$2;      shift 2 ;;
      --constitution-version) _ct_ver=$2;      shift 2 ;;
      --key-aspects)          _key_aspects=$2; shift 2 ;;
      *) _sr_die "init: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ]   || _sr_die "init: --state-dir obrigatorio" 2
  [ -n "$_pap" ]  || _sr_die "init: --projeto-alvo-path obrigatorio" 2
  [ -n "$_desc" ] || _sr_die "init: --descricao obrigatorio" 2

  _sr_require_jq

  # Modo-feature ativa com --short-name. Exige pre-requisitos completos
  # (feature-00c-preflight.sh MORRE sem prerequisites). execucao-id e
  # auto-derivado (feat-<short>-<ts>) se omitido.
  if [ -n "$_short" ]; then
    [ -n "$_br_path" ] || _sr_die "init: modo-feature exige --briefing-path" 2
    [ -n "$_br_sha" ]  || _sr_die "init: modo-feature exige --briefing-sha256" 2
    [ -n "$_ct_path" ] || _sr_die "init: modo-feature exige --constitution-path" 2
    [ -n "$_ct_sha" ]  || _sr_die "init: modo-feature exige --constitution-sha256" 2
    [ -n "$_ct_ver" ]  || _sr_die "init: modo-feature exige --constitution-version" 2
    if ! printf '%s' "$_key_aspects" | jq -e 'type == "array"' >/dev/null 2>&1; then
      _sr_die "init: --key-aspects precisa ser JSON array (ou omitido)" 2
    fi
    [ -n "$_ei" ] || _ei="feat-${_short}-$(_sr_ts_for_filename)"
  else
    [ -n "$_ei" ] || _sr_die "init: --execucao-id obrigatorio (modo projeto)" 2
  fi

  _sr_ensure_state_dir "$_sd"

  _sr_sf=$(_sr_state_file "$_sd")
  if [ -f "$_sr_sf" ]; then
    _sr_die "init: state.json ja existe em $_sd. Use /agente-00c-abort ou /agente-00c-resume." 1
  fi

  _now=$(_sr_iso_now)
  # Templating via jq (escape automatico). Chaves EN (schema-en-migration);
  # VALORES (status etc.) permanecem pt-BR (escopo: so chaves; enum = follow-up
  # B). $short vazio => modo projeto (current_stage="briefing"); senao feature
  # (short_name + prerequisites + current_stage="specify").
  _tmp=$(mktemp -- "${_sr_sf}.XXXXXX") || _sr_die "mktemp falhou" 1
  jq -n \
    --arg id "$_ei" \
    --arg pap "$_pap" \
    --arg desc "$_desc" \
    --arg now "$_now" \
    --arg short "$_short" \
    --arg brp "$_br_path" \
    --arg brs "$_br_sha" \
    --arg ctp "$_ct_path" \
    --arg cts "$_ct_sha" \
    --arg ctv "$_ct_ver" \
    --argjson stack "$_stack" \
    --argjson wl "$_whitelist" \
    --argjson ka "$_key_aspects" \
    '{ schema_version: "1.0.0" }
    + (if $short != "" then { short_name: $short } else {} end)
    + {
      execution: {
        id: $id,
        target_project_path: $pap,
        target_project_description: $desc,
        suggested_stack: $stack,
        status: "em_andamento",
        termination_reason: null,
        started_at: $now,
        finished_at: null
      }
    }
    + (if $short != ""
       then { prerequisites: {
                briefing: { path: $brp, sha256: $brs },
                constitution: { path: $ctp, sha256: $cts, version: $ctv }
              } }
       else {} end)
    + {
      current_stage: (if $short != "" then "specify" else "briefing" end),
      next_instruction: (if $short != ""
        then "Iniciar etapa specify — invocar skill specify com a descricao da feature."
        else "Iniciar etapa briefing — invocar skill briefing do toolkit com a descricao curta do projeto-alvo." end),
      waves: [],
      decisions: [],
      human_blocks: [],
      budgets: {
        max_recursion: 3,
        current_subagent_depth: 1,
        max_retro_executions_per_feature: 2,
        retro_executions_consumed: 0,
        max_cycles_per_stage: 5,
        cycles_consumed_current_stage: 0,
        tool_calls_threshold_wave: 80,
        wallclock_threshold_seconds: 5400,
        state_size_threshold_bytes: 1048576,
        tool_calls_current_wave: 0,
        current_wave_start: null
      },
      accumulated_metrics: {
        waves_total: 0,
        tool_calls_total: 0,
        wallclock_total_seconds: 0,
        max_depth_reached: 1,
        subagents_spawned: 0,
        decisions_total: 0,
        human_blocks_total: 0,
        global_skill_suggestions_total: 0,
        toolkit_issues_opened: 0
      },
      external_urls_whitelist: $wl,
      circular_movement_history: [],
      initial_key_aspects: $ka
    }' > "$_tmp" || { rm -f -- "$_tmp"; _sr_die "jq init falhou" 1; }
  _sr_atomic_write "$_sr_sf" "$_tmp"
  rm -f -- "$_tmp" 2>/dev/null || :
  _sr_update_sha "$_sd"
  _sr_log "init: estado criado em $_sr_sf"
}

_sr_cmd_read() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _sr_die "read: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "read: --state-dir obrigatorio" 2
  _sr_sf=$(_sr_state_file "$_sd")
  [ -f "$_sr_sf" ] || _sr_die "read: state.json nao existe em $_sd" 1
  # Canonicaliza chaves pt-BR -> EN (schema-en-migration). Degrada para raw se
  # jq ausente ou JSON corrompido (preserva o contrato "imprime o que ha").
  if _sr_canon=$(_sr_canonicalize_file "$_sr_sf" 2>/dev/null); then
    printf '%s\n' "$_sr_canon"
  else
    cat -- "$_sr_sf"
  fi
}

_sr_cmd_write() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _sr_die "write: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "write: --state-dir obrigatorio" 2
  _sr_require_jq
  _sr_ensure_state_dir "$_sd"

  _sr_sf=$(_sr_state_file "$_sd")
  # Le stdin para tmp e valida JSON antes de tocar o estado.
  _new=$(mktemp -- "${_sr_sf}.new.XXXXXX") || _sr_die "mktemp falhou" 1
  if ! cat > "$_new"; then
    rm -f -- "$_new"; _sr_die "I/O lendo stdin" 1
  fi
  if ! jq -e . "$_new" >/dev/null 2>&1; then
    rm -f -- "$_new"; _sr_die "write: stdin nao e JSON valido (jq falhou)" 1
  fi
  # Canonicaliza chaves pt-BR -> EN antes de persistir (schema-en-migration):
  # o arquivo converge para EN a cada write. Degrada para o conteudo original
  # se a canonicalizacao falhar.
  _canon=$(mktemp -- "${_sr_sf}.canon.XXXXXX") || { rm -f -- "$_new"; _sr_die "mktemp falhou" 1; }
  if _sr_canonicalize_file "$_new" > "$_canon" 2>/dev/null; then
    mv -f -- "$_canon" "$_new"
  else
    rm -f -- "$_canon" 2>/dev/null || :
  fi
  # Backup do anterior (se existir) ANTES de sobrescrever (2.3.1).
  _sr_backup_current "$_sd"
  _sr_atomic_write "$_sr_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _sr_update_sha "$_sd"
  _sr_log "write: state.json atualizado em $_sr_sf (backup em state-history/)"
}

_sr_cmd_get() {
  _sd=""
  _f=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      --field)     _f=$2;  shift 2 ;;
      *) _sr_die "get: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "get: --state-dir obrigatorio" 2
  [ -n "$_f" ]  || _sr_die "get: --field obrigatorio (ex: '.execucao.status')" 2
  _sr_require_jq
  _sr_sf=$(_sr_state_file "$_sd")
  [ -f "$_sr_sf" ] || _sr_die "get: state.json ausente em $_sd" 1
  # Canonicaliza (EN) antes de extrair: callers usam paths EN mesmo sobre
  # states pt-BR vivos (schema-en-migration).
  _sr_canonicalize_file "$_sr_sf" | jq -r "$_f"
}

_sr_cmd_set() {
  _sd=""
  _f=""
  _v=""
  _v_set=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      --field)     _f=$2;  shift 2 ;;
      --value)     _v=$2;  _v_set=1; shift 2 ;;
      *) _sr_die "set: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ]   || _sr_die "set: --state-dir obrigatorio" 2
  [ -n "$_f" ]    || _sr_die "set: --field obrigatorio" 2
  [ "$_v_set" = 1 ] || _sr_die "set: --value obrigatorio (JSON valido — strings com aspas)" 2
  _sr_require_jq
  _sr_ensure_state_dir "$_sd"
  _sr_sf=$(_sr_state_file "$_sd")
  [ -f "$_sr_sf" ] || _sr_die "set: state.json ausente em $_sd" 1
  # Valida que --value e JSON parseavel (string raw nao serve — pedimos aspas).
  if ! printf '%s' "$_v" | jq -e . >/dev/null 2>&1; then
    _sr_die "set: --value nao e JSON valido. Strings precisam de aspas: '\"foo\"'." 1
  fi
  _new=$(mktemp -- "${_sr_sf}.new.XXXXXX") || _sr_die "mktemp falhou" 1
  # Canonicaliza o doc inteiro (EN) ANTES de aplicar o set: evita doc misto
  # (set EN sobre arquivo pt-BR criaria container duplicado). --field e EN.
  if ! _sr_canonicalize_file "$_sr_sf" | jq --argjson v "$_v" "$_f = \$v" > "$_new"; then
    rm -f -- "$_new"; _sr_die "set: jq update falhou" 1
  fi
  _sr_backup_current "$_sd"
  _sr_atomic_write "$_sr_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _sr_update_sha "$_sd"
  _sr_log "set: $_f atualizado"
}

_sr_cmd_sha256_update() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _sr_die "sha256-update: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "sha256-update: --state-dir obrigatorio" 2
  _sr_sf=$(_sr_state_file "$_sd")
  [ -f "$_sr_sf" ] || _sr_die "sha256-update: state.json ausente em $_sd" 1
  _sr_update_sha "$_sd"
}

_sr_cmd_sha256_verify() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _sr_die "sha256-verify: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "sha256-verify: --state-dir obrigatorio" 2
  _sr_sf=$(_sr_state_file "$_sd")
  _sr_shf=$(_sr_sha_file "$_sd")
  [ -f "$_sr_sf" ]  || _sr_die "sha256-verify: state.json ausente em $_sd" 1
  [ -f "$_sr_shf" ] || _sr_die "sha256-verify: state.json.sha256 ausente em $_sd" 1
  _stored=$(head -n 1 -- "$_sr_shf" | tr -d '[:space:]')
  _actual=$(_sr_sha256_file "$_sr_sf")
  if [ "$_stored" = "$_actual" ]; then
    return 0
  fi
  printf '%s: hash divergente\n  stored: %s\n  actual: %s\n' "$_SR_NAME" "$_stored" "$_actual" >&2
  exit 1
}

# path-check: validacao de --projeto-alvo-path no nivel filesystem.
# NAO inclui validacao de zonas proibidas (FR-024) — isso e FASE 6.1.
_sr_cmd_path_check() {
  _pap=""
  _create=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2; shift 2 ;;
      --create) _create=1; shift ;;
      *) _sr_die "path-check: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_pap" ] || _sr_die "path-check: --projeto-alvo-path obrigatorio" 2
  if [ -e "$_pap" ] && [ ! -d "$_pap" ]; then
    _sr_die "path-check: caminho aponta para arquivo, nao diretorio: $_pap" 1
  fi
  if [ ! -d "$_pap" ]; then
    if [ "$_create" = 1 ]; then
      mkdir -p -- "$_pap" 2>/dev/null \
        || _sr_die "path-check: nao consegui criar $_pap (permissao? FS read-only?)" 1
    else
      _sr_die "path-check: diretorio nao existe: $_pap (use --create para criar)" 1
    fi
  fi
  # Touch test: gravabilidade antes de qualquer escrita real (2.4.3).
  _probe="$_pap/.agente-00c-write-probe"
  if ! ( : > "$_probe" ) 2>/dev/null; then
    _sr_die "path-check: permissao de escrita negada em $_pap" 1
  fi
  rm -f -- "$_probe" 2>/dev/null || :
}

# _sr_cmd_infer_aspectos: infere aspectos tocados pela onda corrente
# a partir de `git diff --name-only` aplicando matcher fuzzy contra
# union das 3 camadas de aspectos. Stdout: JSON array.
_sr_cmd_infer_aspectos() {
  _sd=""
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)          _sd=$2;  shift 2 ;;
      --projeto-alvo-path)  _pap=$2; shift 2 ;;
      *) _sr_die "infer-aspectos: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "infer-aspectos: --state-dir obrigatorio" 2
  command -v jq >/dev/null 2>&1 || _sr_die "infer-aspectos: jq ausente" 1
  command -v git >/dev/null 2>&1 || _sr_die "infer-aspectos: git ausente" 1

  _sf="$_sd/state.json"
  [ -f "$_sf" ] || _sr_die "infer-aspectos: state.json ausente em $_sd" 1

  # Resolver projeto-alvo: flag explicita > execution.target_project_path
  # (canonicaliza para ler tanto states EN quanto pt-BR vivos).
  if [ -z "$_pap" ]; then
    _pap=$(_sr_canonicalize_file "$_sf" 2>/dev/null | jq -r '.execution.target_project_path // ""')
  fi
  [ -n "$_pap" ] || _sr_die "infer-aspectos: nao consegui resolver projeto-alvo-path" 1
  [ -d "$_pap" ] || _sr_die "infer-aspectos: projeto-alvo nao e diretorio: $_pap" 1

  # Coletar arquivos modificados nesta onda. Estrategia:
  #   1. Se HEAD~1 existe, usa `git diff --name-only HEAD~1..HEAD`
  #   2. Caso contrario (primeira onda, repo sem historico), usa
  #      `git diff --name-only --cached` + `git ls-files --others --exclude-standard`
  _diff=$(
    cd "$_pap" 2>/dev/null || exit 1
    if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
      git diff --name-only HEAD~1..HEAD 2>/dev/null
    else
      git diff --name-only --cached 2>/dev/null
      git ls-files --others --exclude-standard 2>/dev/null
    fi
  ) || _diff=""

  # Aplicar matcher fuzzy: aspecto detectado se token-overlap com paths.
  # Reusa logica do drift.sh (matcher bidirecional + tokens >=3 chars).
  # Le o state canonicalizado (EN) — fallback raw se jq/JSON falhar.
  _sr_canon_state=$(mktemp) || _sr_die "infer-aspectos: mktemp falhou" 1
  if ! _sr_canonicalize_file "$_sf" > "$_sr_canon_state" 2>/dev/null; then
    cp -- "$_sf" "$_sr_canon_state" 2>/dev/null || :
  fi
  printf '%s\n' "$_diff" | jq -R -s --slurpfile state "$_sr_canon_state" '
    def tokenize($s):
      ($s // "")
      | ascii_downcase
      | gsub("[^a-z0-9]+"; " ")
      | split(" ")
      | map(select(length >= 3));

    def matches_aspecto($txt; $aspecto):
      ($txt // "" | ascii_downcase) as $t
      | ($aspecto | ascii_downcase) as $a
      | ($t | contains($a))
        or (
          (tokenize($t)) as $tt
          | (tokenize($aspecto)) as $ta
          | any($tt[]; . as $x | any($ta[]; . == $x))
        );

    ($state[0]) as $st
    | (($st.initial_key_aspects     // []) +
       ($st.technical_key_aspects   // []) +
       ($st.operational_key_aspects // []) | unique) as $aspectos
    | . as $diff
    | $aspectos
      | map(. as $a | select(matches_aspecto($diff; $a)))
      | unique
  '
  rm -f -- "$_sr_canon_state" 2>/dev/null || :
}

# _sr_cmd_migrate: canonicaliza um state.json pt-BR -> EN no lugar
# (schema-en-migration). Idempotente: no-op se ja canonico. Faz backup do
# pt-BR em state-history/ + recalcula sha256. Usado no rollout (migrar os
# states vivos) e como defesa no inicio de cada onda (command-pai) ANTES de
# qualquer direct-writer tocar o estado.
_sr_cmd_migrate() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _sr_die "migrate: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "migrate: --state-dir obrigatorio" 2
  _sr_require_jq
  _sr_sf=$(_sr_state_file "$_sd")
  [ -f "$_sr_sf" ] || _sr_die "migrate: state.json ausente em $_sd" 1
  _sr_mig=$(mktemp -- "${_sr_sf}.mig.XXXXXX") || _sr_die "mktemp falhou" 1
  if ! _sr_canonicalize_file "$_sr_sf" > "$_sr_mig" 2>/dev/null; then
    rm -f -- "$_sr_mig"; _sr_die "migrate: canonicalizacao falhou (JSON invalido?)" 1
  fi
  # Idempotencia: se a forma normalizada (jq -S) ja bate, nada renomeou -> no-op
  # (evita churn de backup/sha em states ja EN).
  if [ "$(jq -S . -- "$_sr_sf" 2>/dev/null)" = "$(jq -S . -- "$_sr_mig" 2>/dev/null)" ]; then
    rm -f -- "$_sr_mig"
    _sr_log "migrate: ja canonico (EN) em $_sr_sf — no-op"
    return 0
  fi
  _sr_backup_current "$_sd"   # preserva snapshot pt-BR em state-history/
  _sr_atomic_write "$_sr_sf" "$_sr_mig"
  rm -f -- "$_sr_mig" 2>/dev/null || :
  _sr_update_sha "$_sd"
  _sr_log "migrate: state canonicalizado para EN (backup pt-BR em state-history/)"
}

# ---------- Dispatch ----------

_sr_print_help() {
  cat >&2 <<'HELP'
state-rw.sh — read/write helpers para state.json do agente-00C.

USO:
  state-rw.sh <subcomando> [flags]

SUBCOMANDOS:
  init           Cria state.json + state.json.sha256 + state-history/
  read           Imprime state.json em stdout
  write          Le novo state em stdin, faz backup + grava + sha256
  get            Extrai campo via jq path
  set            Atualiza campo in-place (com backup)
  sha256-update  Recalcula state.json.sha256
  sha256-verify  Compara hash atual com state.json.sha256 (FR-029)
  path-check     Valida --projeto-alvo-path (existe/cria/gravavel)
  infer-aspectos Infere aspectos tocados via git diff + matcher fuzzy
  migrate        Canonicaliza chaves pt-BR -> EN no lugar (idempotente)

Flags variam por subcomando — consulte cabecalho do script para detalhes.

Dependencias: jq + git (brew install jq | apt install jq).
HELP
}

if [ "$#" -lt 1 ]; then
  _sr_print_help
  exit 2
fi

_sr_subcmd=$1
shift

case "$_sr_subcmd" in
  init)            _sr_cmd_init "$@" ;;
  read)            _sr_cmd_read "$@" ;;
  write)           _sr_cmd_write "$@" ;;
  get)             _sr_cmd_get "$@" ;;
  set)             _sr_cmd_set "$@" ;;
  sha256-update)   _sr_cmd_sha256_update "$@" ;;
  sha256-verify)   _sr_cmd_sha256_verify "$@" ;;
  path-check)      _sr_cmd_path_check "$@" ;;
  infer-aspectos)  _sr_cmd_infer_aspectos "$@" ;;
  migrate)         _sr_cmd_migrate "$@" ;;
  -h|--help|help)  _sr_print_help; exit 0 ;;
  *) _sr_die "subcomando desconhecido: $_sr_subcmd (use --help)" 2 ;;
esac
