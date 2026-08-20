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
# docs/specs/_archived/2026-08-08-schema-en-migration/migration-map.md.
#
# Subcomandos:
#   state-rw.sh init  --state-dir DIR --execucao-id ID
#                     --projeto-alvo-path PATH --descricao TEXT
#                     [--stack-json TEXT] [--whitelist-urls JSON-ARRAY]
#                     [--canonical-project NAME] [--session-name NAME]
#                     — modo PROJETO (agente-00c): cria state.json
#                       (current_stage="briefing") + sha256 + state-history/
#   state-rw.sh init  --state-dir DIR --short-name NAME
#                     --projeto-alvo-path PATH --descricao TEXT
#                     --briefing-path P --briefing-sha256 S
#                     --constitution-path P --constitution-sha256 S
#                     --constitution-version V [--key-aspects JSON-ARRAY]
#                     [--execucao-id ID] [--stack-json TEXT] [--whitelist-urls JSON]
#                     [--canonical-project NAME] [--session-name NAME]
#                     — modo FEATURE (feature-00c): emite schema de feature
#                       (short_name + prerequisites + current_stage="specify")
#                       numa unica chamada deterministica. execucao-id
#                       auto-derivado (feat-<short>-<ts>) se omitido.
#                     Flags de proveniencia canonica (feature recall-worktree-identity):
#                       --canonical-project NAME  — quando nao-vazio, grava
#                         .execution.canonical_project no JSON. Omitido = chave ausente.
#                       --session-name NAME — quando nao-vazio, grava
#                         .execution.session_name no JSON. Omitido = chave ausente.
#                         Requer --canonical-project (exit 2 se omitido).
#                     Flags de modo opt-in (ambas aceitas nos dois modos, PROJETO e FEATURE):
#                       --atomic-commit true|false — grava .atomic_commit_enabled
#                         (default false; feature atomic-commit-pr).
#                       --roadmap-mode true|false — grava .roadmap_mode_enabled
#                         (default false; feature roadmap-mode). Valor fora de
#                         true|false ⇒ exit 2, sem escrever estado.
#                       --delivery-tier TOKEN — grava .delivery_tier, top-level,
#                         sempre presente (default cloud-public; feature
#                         delivery-tier). TOKEN fora do enum
#                         local|internal-network|cloud-internal|cloud-public
#                         ⇒ exit 2, sem escrever estado.
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
_SR_DIR=$(cd "$(dirname -- "$0")" && pwd)

# Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015 — escopo-piloto).
# shellcheck source=./_diag.sh
. "$_SR_DIR/_diag.sh"

# Backend dual (feature state-db-foundation, FASE 3 task 3.2): presenca de
# <state-dir>/state.db seleciona SQLite; senao, backend JSON (comportamento
# historico, intacto abaixo). Ver contracts/primitives.md §C1/C2.
# shellcheck source=./_state-db.sh
. "$_SR_DIR/_state-db.sh"
# shellcheck source=./_state-rw-db.sh
. "$_SR_DIR/_state-rw-db.sh"

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
# Spec: docs/specs/_archived/2026-08-08-schema-en-migration/migration-map.md
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
  # Semeia .gitignore "*" no state-dir: estado e runtime/transacional e NUNCA
  # deve ser versionado (repo trackeando state.json foi o gatilho do bug
  # .claude/.claude em v5.11.1). Best-effort + idempotente: nao sobrescreve
  # .gitignore existente (respeita customizacao do operador) nem aborta o
  # init se a escrita falhar.
  if [ ! -e "$1/.gitignore" ]; then
    printf '*\n' > "$1/.gitignore" 2>/dev/null || :
  fi
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
  # Flags de proveniencia canonica (feature recall-worktree-identity, FR-001/FR-002).
  # Quando nao-vazias, gravam .execution.canonical_project / .execution.session_name.
  # Quando omitidas, as chaves ficam AUSENTES (sem null) — FR-010.
  _canonical_project=""
  _session_name=""
  # Modo atomic-commit (feature atomic-commit-pr): opt-in para commit por etapa/task.
  # Omitido => false (retro-compativel). Valor deve ser "true" ou "false".
  _atomic_commit="false"
  # Modo roadmap (feature roadmap-mode): opt-in para pipeline enxuta
  # briefing->constitution->roadmap. Omitido => false (retro-compativel).
  # Valor deve ser "true" ou "false" (espelha --atomic-commit).
  _roadmap_mode="false"
  # Tier de entrega (feature delivery-tier, contracts/cli-delivery-tier.md
  # §5): finalidade declarada do produto, calibra profundidade da pipeline.
  # Omitido => default cloud-public (profundidade plena, zero regressao).
  # Valor fora do enum de 4 tokens => _sr_die exit 2 SEM escrever estado.
  _delivery_tier="cloud-public"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)            _sd=$2;                   shift 2 ;;
      --execucao-id)          _ei=$2;                   shift 2 ;;
      --projeto-alvo-path)    _pap=$2;                  shift 2 ;;
      --descricao)            _desc=$2;                 shift 2 ;;
      --stack-json)           _stack=$2;                shift 2 ;;
      --whitelist-urls)       _whitelist=$2;            shift 2 ;;
      --short-name)           _short=$2;                shift 2 ;;
      --briefing-path)        _br_path=$2;              shift 2 ;;
      --briefing-sha256)      _br_sha=$2;               shift 2 ;;
      --constitution-path)    _ct_path=$2;              shift 2 ;;
      --constitution-sha256)  _ct_sha=$2;               shift 2 ;;
      --constitution-version) _ct_ver=$2;               shift 2 ;;
      --key-aspects)          _key_aspects=$2;          shift 2 ;;
      --canonical-project)    _canonical_project=$2;   shift 2 ;;
      --session-name)         _session_name=$2;         shift 2 ;;
      --atomic-commit)
        case "$2" in
          true|false) _atomic_commit=$2; shift 2 ;;
          *) _sr_die "init: --atomic-commit aceita apenas 'true' ou 'false'" 2 ;;
        esac
        ;;
      --roadmap-mode)
        case "$2" in
          true|false) _roadmap_mode=$2; shift 2 ;;
          *) _sr_die "init: --roadmap-mode aceita apenas 'true' ou 'false'" 2 ;;
        esac
        ;;
      --delivery-tier)
        case "$2" in
          local|internal-network|cloud-internal|cloud-public) _delivery_tier=$2; shift 2 ;;
          *) _sr_die "init: --delivery-tier aceita apenas local|internal-network|cloud-internal|cloud-public" 2 ;;
        esac
        ;;
      *) _sr_die "init: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ]   || _sr_die "init: --state-dir obrigatorio" 2
  [ -n "$_pap" ]  || _sr_die "init: --projeto-alvo-path obrigatorio" 2
  [ -n "$_desc" ] || _sr_die "init: --descricao obrigatorio" 2

  # Validacao: --session-name requer --canonical-project (data-model §regras de presenca)
  if [ -n "$_session_name" ] && [ -z "$_canonical_project" ]; then
    _sr_die "init: --session-name requer --canonical-project (sessao sem canonico nao tem semantica)" 2
  fi

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

  # feature state-backend-config, FASE 5 (task 5.1.1): resolve o backend
  # EFETIVO ANTES das guardas de criacao abaixo — decide qual arquivo esta
  # funcao vai criar quando NENHUM dos dois (state.db/state.json) existe
  # ainda. Best-effort: state-backend.sh e sibling de state-rw.sh no mesmo
  # dir do runtime ($_SR_DIR); resolve SEMPRE sai 0 (contrato de nao-falha,
  # FR-008) — ausencia do script ou qualquer falha de leitura degrada para
  # o fallback historico "json" sem abortar init (config ausente/invalida
  # nunca quebra a inicializacao, quickstart.md Scenario 7).
  _sr_effective_backend="json"
  if [ -f "$_SR_DIR/state-backend.sh" ]; then
    if _sr_sb_out=$(sh "$_SR_DIR/state-backend.sh" resolve 2>/dev/null); then
      _sr_sb_eb=$(printf '%s\n' "$_sr_sb_out" | grep '^effective_backend=' | head -n 1)
      [ "$_sr_sb_eb" = "effective_backend=sqlite" ] && _sr_effective_backend="sqlite"
    fi
  fi

  # C2 (herdado de state-db-foundation) + FASE 5: se um state.db ja existe
  # (projeto migrado, OU ja inicializado sob backend sqlite), recusa em vez
  # de criar um state.json paralelo que nunca seria a fonte de verdade
  # (C2/Decision 9) — guarda preservada INTACTA independente da config
  # global (FR-006, task 5.1.2).
  if [ -f "$(_sr_db_file "$_sd")" ]; then
    _sr_die "init: state.db ja existe em $_sd (projeto migrado para backend SQLite) — init nao se aplica; use os subcomandos normais (state-ondas.sh etc.) diretamente." 1
  fi

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
    --arg canonical_project "$_canonical_project" \
    --arg session_name "$_session_name" \
    --argjson atomic_commit "$_atomic_commit" \
    --argjson roadmap_mode "$_roadmap_mode" \
    --arg delivery_tier "$_delivery_tier" \
    '{ schema_version: "1.0.0" }
    + (if $short != "" then { short_name: $short } else {} end)
    + {
      execution: (
        {
          id: $id,
          target_project_path: $pap,
          target_project_description: $desc,
          suggested_stack: $stack,
          status: "em_andamento",
          termination_reason: null,
          started_at: $now,
          finished_at: null
        }
        + (if $canonical_project != "" then { canonical_project: $canonical_project } else {} end)
        + (if $session_name != "" then { session_name: $session_name } else {} end)
      )
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
      initial_key_aspects: $ka,
      atomic_commit_enabled: $atomic_commit,
      roadmap_mode_enabled: $roadmap_mode,
      delivery_tier: $delivery_tier
    }' > "$_tmp" || { rm -f -- "$_tmp"; _sr_die "jq init falhou" 1; }

  # feature state-backend-config, FASE 5 (task 5.1.3/5.1.5): backend
  # efetivo sqlite -> cria state.db diretamente (schema canonico +
  # PRAGMA WAL + permissoes via state-db-schema.sh create) e popula a
  # execucao via INSERT direto — NUNCA passa por state.json/migracao. O
  # doc acima (mesmo template do caminho json) e usado so como FONTE dos
  # valores do INSERT; o arquivo $_tmp em si nunca vira state.json aqui.
  if [ "$_sr_effective_backend" = "sqlite" ]; then
    _sr_db_target=$(_sr_db_file "$_sd")
    # GOTCHA busy_timeout (research.md Decision 8): descarta stdout do
    # sqlite3 CLI acionado por state-db-schema.sh — nao captura para
    # variavel (evitaria contaminar qualquer leitura por 'PRAGMA
    # busy_timeout' ecoado). Aqui so o exit code importa.
    if ! "$_SR_DIR/state-db-schema.sh" create --db "$_sr_db_target" >/dev/null 2>&1; then
      rm -f -- "$_tmp"
      _sr_die "init: falha ao criar schema em $_sr_db_target" 1
    fi
    # feature structural-decision-human-gate (task 1.2.4, INV-E3): `create`
    # e CREATE TABLE IF NOT EXISTS — nao acrescenta coluna [NOVO] a uma
    # tabela ja existente. `ensure` cobre o caso de `init` apontar para um
    # state.db pre-existente criado antes desta feature.
    if ! "$_SR_DIR/state-db-schema.sh" ensure --db "$_sr_db_target" >/dev/null 2>&1; then
      rm -f -- "$_tmp"
      _sr_die "init: falha ao garantir schema aditivo (ensure) em $_sr_db_target" 1
    fi
    if ! _sr_db_insert_execution_from_doc_file "$_sr_db_target" "$_tmp"; then
      rm -f -- "$_tmp" "$_sr_db_target" 2>/dev/null || :
      _sr_die "init: INSERT da execution falhou em $_sr_db_target" 1
    fi
    rm -f -- "$_tmp" 2>/dev/null || :
    _sr_log "init: estado (SQLite) criado em $_sr_db_target"
    return 0
  fi

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
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _sr_require_jq
    _sr_db_read "$_sd"
    return 0
  fi
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

  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _wr_doc=$(mktemp) || _sr_die "mktemp falhou" 1
    if ! cat > "$_wr_doc"; then
      rm -f -- "$_wr_doc"; _sr_die "write: I/O lendo stdin" 1
    fi
    if ! jq -e . "$_wr_doc" >/dev/null 2>&1; then
      rm -f -- "$_wr_doc"
      diag_emit error state-invalid-json "write: stdin nao e JSON valido (jq falhou)" \
        "corrija o JSON de entrada (jq -e . <arquivo> para localizar o erro de sintaxe) e tente novamente" || :
      _sr_die "write: stdin nao e JSON valido (jq falhou)" 1
    fi
    _wr_doc_content=$(cat -- "$_wr_doc")
    rm -f -- "$_wr_doc"
    _sr_db_write_document "$_sd" "$_wr_doc_content"
    _sr_log "write: state.db atualizado em $(_sr_db_file "$_sd")"
    return 0
  fi

  _sr_ensure_state_dir "$_sd"

  _sr_sf=$(_sr_state_file "$_sd")
  # Le stdin para tmp e valida JSON antes de tocar o estado.
  _new=$(mktemp -- "${_sr_sf}.new.XXXXXX") || _sr_die "mktemp falhou" 1
  if ! cat > "$_new"; then
    rm -f -- "$_new"; _sr_die "I/O lendo stdin" 1
  fi
  if ! jq -e . "$_new" >/dev/null 2>&1; then
    rm -f -- "$_new"
    diag_emit error state-invalid-json "write: stdin nao e JSON valido (jq falhou)" \
      "corrija o JSON de entrada (jq -e . <arquivo> para localizar o erro de sintaxe) e tente novamente" || :
    _sr_die "write: stdin nao e JSON valido (jq falhou)" 1
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
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _sr_db_read "$_sd" | jq -r "$_f"
    return 0
  fi
  _sr_sf=$(_sr_state_file "$_sd")
  if [ ! -f "$_sr_sf" ]; then
    diag_emit error state-not-found "get: state.json ausente em $_sd" \
      "rode state-rw.sh init (ou o command-pai /agente-00c, /feature-00c) para criar o state antes de get" || :
    _sr_die "get: state.json ausente em $_sd" 1
  fi
  # Canonicaliza (EN) antes de extrair: callers usam paths EN mesmo sobre
  # states pt-BR vivos (schema-en-migration).
  _sr_canonicalize_file "$_sr_sf" | jq -r "$_f"
}

# set — mutacao pontual (1 par) ou lote multi-campo atomico (N pares).
# Multi-campo (state-db-runtime-parity FR-005/FR-006, contracts/
# runtime-interfaces.md §1): N pares --field/--value aplicados atomicamente
# (JSON: 1 write do documento; SQLite: 1 transacao). 1 par = comportamento
# anterior inalterado (retrocompat FR-004). Semantica do parser:
# - `--value` sem `--field` previo => exit 2 (uso);
# - `--field` sem `--value` ao fim => exit 2 (uso);
# - `--field` repetido com par pendente sobrescreve o pendente (continuidade
#   com o last-wins de flags do parser anterior);
# - MESMO --field em pares completos repetidos no lote => LAST-WINS na ordem
#   de aplicacao (CHK009), NAO erro de uso.
_sr_cmd_set() {
  _sd=""
  _f=""
  _v=""
  _f_set=0
  _n=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      --field)     _f=$2; _f_set=1; shift 2 ;;
      --value)
        [ "$_f_set" = 1 ] || _sr_die "set: --value sem --field previo" 2
        # Acumula o par em variaveis indexadas (POSIX sh sem arrays; eval
        # seguro — rhs referencia variavel, nunca interpola conteudo).
        eval "_sr_set_f_$_n=\$_f"
        eval "_sr_set_v_$_n=\$2"
        _n=$((_n + 1))
        _f=""
        _f_set=0
        shift 2 ;;
      *) _sr_die "set: flag desconhecida: $1" 2 ;;
    esac
  done
  [ -n "$_sd" ] || _sr_die "set: --state-dir obrigatorio" 2
  [ "$_f_set" = 0 ] || _sr_die "set: --value obrigatorio (JSON valido — strings com aspas)" 2
  [ "$_n" -gt 0 ] || _sr_die "set: --field obrigatorio" 2
  _sr_require_jq
  # Valida que TODO --value e JSON parseavel ANTES de qualquer escrita
  # (all-or-nothing — FR-006). SEM `-e`: jq -e retorna 1 para output falsy
  # (null/false), que SAO valores JSON validos e legitimos (ex.:
  # `.briefing_cache = null` do state-cache.sh invalidate;
  # `.atomic_commit_enabled = false`). Parse invalido segue detectado:
  # jq sem -e retorna exit 2 em erro de sintaxe.
  if [ "$_n" -eq 1 ]; then
    eval "_f=\$_sr_set_f_0"
    eval "_v=\$_sr_set_v_0"
    if ! printf '%s' "$_v" | jq . >/dev/null 2>&1; then
      _sr_die "set: --value nao e JSON valido. Strings precisam de aspas: '\"foo\"'." 1
    fi
    if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
      _sr_db_set "$_sd" "$_f" "$_v"
      _sr_log "set: $_f atualizado (backend sqlite)"
      return 0
    fi
    _sr_ensure_state_dir "$_sd"
    _sr_sf=$(_sr_state_file "$_sd")
    [ -f "$_sr_sf" ] || _sr_die "set: state.json ausente em $_sd" 1
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
    return 0
  fi

  # ---- Lote multi-campo (N >= 2) ----
  _pairs='[]'
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    eval "_f=\$_sr_set_f_$_i"
    eval "_v=\$_sr_set_v_$_i"
    if ! printf '%s' "$_v" | jq . >/dev/null 2>&1; then
      _sr_die "set: --value do campo '$_f' nao e JSON valido. Strings precisam de aspas: '\"foo\"'." 1
    fi
    _pairs=$(printf '%s' "$_pairs" | jq -c --arg f "$_f" --argjson v "$_v" '. + [{f:$f,v:$v}]') \
      || _sr_die "set: falha ao acumular o par '$_f' do lote" 1
    _i=$((_i + 1))
  done
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _sr_db_set_multi "$_sd" "$_pairs"
    _sr_log "set: $_n campos atualizados atomicamente (backend sqlite)"
    return 0
  fi
  _sr_ensure_state_dir "$_sd"
  _sr_sf=$(_sr_state_file "$_sd")
  [ -f "$_sr_sf" ] || _sr_die "set: state.json ausente em $_sd" 1
  # Todos os setpaths num UNICO pipeline jq = 1 write do documento (FR-005);
  # aplicacao sequencial em ordem de par => last-wins de campo duplicado.
  _filter=""
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    eval "_f=\$_sr_set_f_$_i"
    _filter="${_filter:+$_filter | }$_f = \$__sr_pairs[$_i].v"
    _i=$((_i + 1))
  done
  _new=$(mktemp -- "${_sr_sf}.new.XXXXXX") || _sr_die "mktemp falhou" 1
  if ! _sr_canonicalize_file "$_sr_sf" | jq --argjson __sr_pairs "$_pairs" "$_filter" > "$_new"; then
    rm -f -- "$_new"; _sr_die "set: jq update multi-campo falhou (nenhum campo foi escrito)" 1
  fi
  _sr_backup_current "$_sd"
  _sr_atomic_write "$_sr_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _sr_update_sha "$_sd"
  _sr_log "set: $_n campos atualizados atomicamente"
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
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    # C7 (dec-025): sob SQLite nao ha hash derivado a manter — a verificacao
    # de integridade passa a ser `PRAGMA integrity_check` (sha256-verify).
    # sha256-update vira no-op (mesmo exit 0, mesma superficie de comando).
    [ -f "$(_sr_db_file "$_sd")" ] || _sr_die "sha256-update: state.db ausente em $_sd" 1
    _sr_log "sha256-update: no-op sob backend SQLite (C7 — integridade via PRAGMA integrity_check)"
    return 0
  fi
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
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _sr_db_integrity_check "$_sd" || exit 1
    return 0
  fi
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
  diag_emit error hash-mismatch "sha256-verify: hash divergente (stored=$_stored actual=$_actual)" \
    "state.json foi adulterado ou o .sha256 esta desatualizado — rode state-rw.sh sha256-update se a mudanca foi legitima, senao investigue tampering" || :
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

  # Materializa o documento de estado UMA vez, backend-aware (issues
  # #118/#119/#121/#124: a checagem hardcoded de state.json deixava o
  # subcomando cego ao backend state.db, enquanto get/set ja despacham).
  # Sob SQLite o read ja devolve o documento canonico EN; sob JSON
  # canonicaliza (fallback raw se jq/JSON falhar — mesmo contrato do read).
  _sr_canon_state=$(mktemp) || _sr_die "infer-aspectos: mktemp falhou" 1
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    if ! _sr_db_read "$_sd" > "$_sr_canon_state"; then
      rm -f -- "$_sr_canon_state" 2>/dev/null || :
      _sr_die "infer-aspectos: falha lendo state.db em $_sd" 1
    fi
  else
    _sf=$(_sr_state_file "$_sd")
    if [ ! -f "$_sf" ]; then
      rm -f -- "$_sr_canon_state" 2>/dev/null || :
      _sr_die "infer-aspectos: state.json ausente em $_sd" 1
    fi
    if ! _sr_canonicalize_file "$_sf" > "$_sr_canon_state" 2>/dev/null; then
      cp -- "$_sf" "$_sr_canon_state" 2>/dev/null || :
    fi
  fi

  # Resolver projeto-alvo: flag explicita > execution.target_project_path.
  if [ -z "$_pap" ]; then
    _pap=$(jq -r '.execution.target_project_path // ""' "$_sr_canon_state" 2>/dev/null)
  fi
  if [ -z "$_pap" ]; then
    rm -f -- "$_sr_canon_state" 2>/dev/null || :
    _sr_die "infer-aspectos: nao consegui resolver projeto-alvo-path" 1
  fi
  if [ ! -d "$_pap" ]; then
    rm -f -- "$_sr_canon_state" 2>/dev/null || :
    _sr_die "infer-aspectos: projeto-alvo nao e diretorio: $_pap" 1
  fi

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
  # Le o documento ja materializado (canonico EN) acima.
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
  # Backend SQLite (issue #124): nao ha state.json pt-BR a canonicalizar —
  # o schema do state.db ja e EN por construcao. No-op explicito em vez do
  # erro enganoso "state.json ausente".
  if [ "$(_sr_backend "$_sd")" = "sqlite" ]; then
    _sr_log "migrate: backend sqlite (state.db) em $_sd — nada a canonicalizar, no-op"
    return 0
  fi
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
