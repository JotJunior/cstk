#!/bin/sh
# state-validate.sh — validacao de schema + invariantes do state.json (FR-008).
#
# Ref: docs/specs/agente-00c/contracts/state-schema.md §Regras de validacao
#      docs/specs/agente-00c/spec.md FR-008
#      docs/specs/agente-00c/constitution.md §III (Idempotencia de Retomada)
#
# Sintaxe:
#   state-validate.sh --state-dir DIR
#
# Comportamento:
#   1. Le state.json. Se nao parseavel = exit 1 com diagnostico.
#   2. Verifica presenca + tipo de cada campo obrigatorio.
#   3. Aplica invariantes (profundidade <= 3, ciclos <= 5, retros <= 2).
#   4. Verifica consistencia de status x finished_at.
#   5. Verifica que cada Decisao tem 5 campos preenchidos (Principio I).
#   6. Verifica que cada BloqueioHumano referencia uma Decisao existente.
#   7. Verifica que external_urls_whitelist e array de strings nao vazias.
#
# IMPORTANTE: NAO faz auto-correcao. Falha = bloqueio puro (Principio III).
#
# Schema EN (schema-en-migration): READ-ONLY sobre state.json — todas as
# leituras usam chaves EN com fallback pt-BR (.en // .pt) para aceitar states
# pt-BR vivos. NAO escreve state.json. Ver docs/specs/schema-en-migration/.
# VALORES de enum (status, etapa, strategy) permanecem pt-BR (follow-up B). As
# folhas do subsistema de cache (§3.9d: estrategia->strategy, resumo_chars->
# summary_chars, gerado_em->generated_at, gerado_na_onda->generated_in_wave)
# sao lidas EN-first + fallback pt-BR — par coordenado com state-cache.sh. O
# cache nao entra no canonicalizer de state-rw (leitura direta com fallback).
#
# Exit codes:
#   0 valido
#   1 invalido (lista de violacoes em stderr)
#   2 uso incorreto
#
# POSIX sh + jq.

set -eu

_SV_NAME="state-validate"

_sv_die_usage() {
  printf '%s: %s\n' "$_SV_NAME" "$1" >&2
  exit 2
}

_sv_emit_error() {
  printf '%s: VIOLACAO: %s\n' "$_SV_NAME" "$1" >&2
}

_sv_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s: jq nao encontrado no PATH. Instale com brew/apt.\n' "$_SV_NAME" >&2
    exit 1
  fi
}

# ---------- Parse de args ----------

_SV_STATE_DIR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir) _SV_STATE_DIR=$2; shift 2 ;;
    -h|--help)
      cat >&2 <<'HELP'
state-validate.sh — valida state.json segundo FR-008.

USO:
  state-validate.sh --state-dir DIR

EXIT:
  0 valido
  1 invalido (violacoes em stderr)
  2 uso incorreto

Lista de checagens:
  1. Arquivo existe e e JSON parseavel.
  2. schema_version = "1.0.0".
  3. Campos obrigatorios presentes (execution.*, current_stage, next_instruction,
     waves, decisions, human_blocks, budgets.*, external_urls_whitelist).
  4. status x finished_at consistentes (terminal => finished_at != null).
  5. current_subagent_depth <= 3.
  6. cycles_consumed_current_stage <= 5.
  7. retro_executions_consumed <= 2.
  8. Cada Decisao tem 5 campos: context, options_considered (>=1),
     choice, rationale, agent.
  9. Cada BloqueioHumano referencia uma Decisao existente (decision_id).
 10. external_urls_whitelist e array de strings nao-vazias.

Schema EN com fallback pt-BR (.en // .pt): states pt-BR vivos ainda validam.
HELP
      exit 0
      ;;
    *) _sv_die_usage "flag desconhecida: $1" ;;
  esac
done

[ -n "$_SV_STATE_DIR" ] || _sv_die_usage "--state-dir obrigatorio"

_SV_FILE="$_SV_STATE_DIR/state.json"
_sv_require_jq

# 1. Existe e parseavel
if [ ! -f "$_SV_FILE" ]; then
  _sv_emit_error "state.json nao existe em $_SV_STATE_DIR"
  exit 1
fi
if ! jq -e . "$_SV_FILE" >/dev/null 2>&1; then
  _sv_emit_error "state.json nao e JSON parseavel"
  exit 1
fi

# Coleta violacoes em $_SV_VIOL (multilinha). Imprime tudo no fim.
_SV_VIOL=""
_sv_add() { _SV_VIOL="$_SV_VIOL
$1"; }

# 2. schema_version
_v=$(jq -r '.schema_version // ""' "$_SV_FILE")
if [ "$_v" != "1.0.0" ]; then
  _sv_add "schema_version desconhecido: \"$_v\" (esperado \"1.0.0\")"
fi

# 3. Campos obrigatorios estruturais
# READER (schema-en-migration): path EN + fallback pt-BR. Assinatura:
#   _check_field EN-PATH KIND [PT-PATH]
# Quando PT-PATH e omitido, a chave ja e neutra/EN (ex: .schema_version) ou o
# fallback se faz no nivel do container (.execution // .execucao) — para folhas
# de containers renomeados passamos o path pt-BR equivalente explicitamente.
_check_field() {
  _path=$1
  _kind=$2  # string|object|array|number
  _fallback=${3:-}
  if [ -n "$_fallback" ]; then
    _expr="($_path) // ($_fallback)"
  else
    _expr="($_path)"
  fi
  _t=$(jq -r "($_expr) | type" "$_SV_FILE" 2>/dev/null) || _t="null"
  case "$_kind:$_t" in
    string:string) ;;
    object:object) ;;
    array:array) ;;
    number:number) ;;
    *)
      _sv_add "campo obrigatorio ausente ou tipo errado: $_path (esperado $_kind, obtido $_t)"
      ;;
  esac
}

_check_field '.execution'                          object '.execucao'
_check_field '.execution.id'                       string '.execucao.id'
_check_field '.execution.target_project_path'      string '.execucao.projeto_alvo_path'
_check_field '.execution.target_project_description' string '.execucao.projeto_alvo_descricao'
_check_field '.execution.status'                   string '.execucao.status'
_check_field '.execution.started_at'               string '.execucao.iniciada_em'
_check_field '.current_stage'                       string '.etapa_corrente'
_check_field '.next_instruction'                    string '.proxima_instrucao'
_check_field '.waves'                               array '.ondas'
_check_field '.decisions'                           array '.decisoes'
_check_field '.human_blocks'                        array '.bloqueios_humanos'
_check_field '.budgets'                             object '.orcamentos'
_check_field '.budgets.current_subagent_depth'      number '.orcamentos.profundidade_corrente_subagentes'
_check_field '.budgets.cycles_consumed_current_stage' number '.orcamentos.ciclos_consumidos_etapa_corrente'
_check_field '.budgets.retro_executions_consumed'   number '.orcamentos.retro_execucoes_consumidas'
_check_field '.external_urls_whitelist'             array '.whitelist_urls_externas'

# 3b. Campos opcionais de proveniencia canonica (feature recall-worktree-identity).
# Presentes SOMENTE em execucoes em worktrees cstk-session; ausentes em projetos
# normais. Estados pre-feature permanecem validos (retro-compat — FR-010).
# Validar APENAS quando presentes: devem ser string se existirem.
_check_optional_string() {
  _path=$1
  _t=$(jq -r "($_path) | type" "$_SV_FILE" 2>/dev/null) || _t="null"
  case "$_t" in
    string|null) ;;  # null = ausente = ok
    *)
      _sv_add "campo opcional com tipo inesperado: $_path (esperado string ou ausente, obtido $_t)"
      ;;
  esac
}
_check_optional_string '.execution.canonical_project'
_check_optional_string '.execution.session_name'

# 4. status x finished_at
# READER: chaves EN + fallback pt-BR. VALORES de status (enum) permanecem pt-BR.
_st=$(jq -r '(.execution.status // .execucao.status) // ""' "$_SV_FILE")
_te=$(jq -r '(.execution.finished_at // .execucao.terminada_em) // null' "$_SV_FILE")
case "$_st" in
  abortada|concluida)
    if [ "$_te" = "null" ]; then
      _sv_add "status terminal (\"$_st\") mas execution.finished_at e null"
    fi
    ;;
  em_andamento|aguardando_humano)
    if [ "$_te" != "null" ]; then
      _sv_add "status nao-terminal (\"$_st\") mas execution.finished_at preenchido (\"$_te\")"
    fi
    ;;
  "")
    : # ja reportado pelo _check_field acima
    ;;
  *)
    _sv_add "execution.status invalido: \"$_st\" (esperado em_andamento|aguardando_humano|abortada|concluida)"
    ;;
esac

# 5/6/7. Invariantes numericas
# READER: path EN + fallback pt-BR (4o arg opcional).
_check_max() {
  _path=$1
  _max=$2
  _label=$3
  _fallback=${4:-}
  if [ -n "$_fallback" ]; then
    _expr="($_path) // ($_fallback) // 0"
  else
    _expr="($_path) // 0"
  fi
  _val=$(jq -r "$_expr" "$_SV_FILE" 2>/dev/null) || _val=0
  # Garante numerico
  case "$_val" in
    ''|*[!0-9-]*) return 0 ;;  # ja reportado por _check_field
  esac
  if [ "$_val" -gt "$_max" ]; then
    _sv_add "$_label violado: $_path = $_val > $_max"
  fi
}

_check_max '.budgets.current_subagent_depth'        3 "Invariante FR-013 (max 3 niveis de subagentes)" '.orcamentos.profundidade_corrente_subagentes'
_check_max '.budgets.cycles_consumed_current_stage' 5 "Invariante FR-014.a (max 5 ciclos sem progresso)" '.orcamentos.ciclos_consumidos_etapa_corrente'
_check_max '.budgets.retro_executions_consumed'     2 "Invariante FR-006 (max 2 retro-execucoes)" '.orcamentos.retro_execucoes_consumidas'

# 8. Decisoes: 5 campos preenchidos
# READER: container + folhas EN com fallback pt-BR (.en // .pt).
_dec_total=$(jq '((.decisions // .decisoes) // []) | length' "$_SV_FILE" 2>/dev/null) || _dec_total=0
if [ "$_dec_total" -gt 0 ]; then
  _missing=$(jq -r '
    ((.decisions // .decisoes) // [])[]? | select(
      ((.context // .contexto) | type) != "string" or ((.context // .contexto) | length) == 0 or
      ((.options_considered // .opcoes_consideradas) | type) != "array" or ((.options_considered // .opcoes_consideradas) | length) == 0 or
      ((.choice // .escolha) | type) != "string" or ((.choice // .escolha) | length) == 0 or
      ((.rationale // .justificativa) | type) != "string" or ((.rationale // .justificativa) | length) == 0 or
      ((.agent // .agente) | type) != "string" or ((.agent // .agente) | length) == 0
    ) | .id // "<sem-id>"
  ' "$_SV_FILE" 2>/dev/null) || _missing=""
  if [ -n "$_missing" ]; then
    # Lista decisoes incompletas (uma por linha)
    _OLD_IFS=$IFS
    IFS='
'
    for _id in $_missing; do
      IFS=$_OLD_IFS
      _sv_add "Decisao $_id viola Principio I (algum dos 5 campos vazio: context, options_considered, choice, rationale, agent)"
      IFS='
'
    done
    IFS=$_OLD_IFS
  fi
fi

# 9. BloqueioHumano: cada um referencia Decisao existente
# READER: containers e folhas EN com fallback pt-BR.
_block_total=$(jq '((.human_blocks // .bloqueios_humanos) // []) | length' "$_SV_FILE" 2>/dev/null) || _block_total=0
if [ "$_block_total" -gt 0 ]; then
  _orphan=$(jq -r '
    ((.decisions // .decisoes) // []) as $D
    | ($D | map(.id)) as $ids
    | ((.human_blocks // .bloqueios_humanos) // [])[]?
      | (.decision_id // .decisao_id) as $d
      | select(($d | type) != "string" or ($ids | index($d) == null))
      | .id // "<sem-id>"
  ' "$_SV_FILE" 2>/dev/null) || _orphan=""
  if [ -n "$_orphan" ]; then
    _OLD_IFS=$IFS
    IFS='
'
    for _bid in $_orphan; do
      IFS=$_OLD_IFS
      _sv_add "BloqueioHumano $_bid referencia decision_id inexistente"
      IFS='
'
    done
    IFS=$_OLD_IFS
  fi
fi

# 10. external_urls_whitelist: array de strings nao-vazias
# READER: chave EN + fallback pt-BR.
_wl_bad=$(jq -r '
  ((.external_urls_whitelist // .whitelist_urls_externas) // []) | to_entries[]?
  | select((.value | type) != "string" or (.value | length) == 0)
  | .key
' "$_SV_FILE" 2>/dev/null) || _wl_bad=""
if [ -n "$_wl_bad" ]; then
  _sv_add "external_urls_whitelist contem entrada(s) invalida(s) (nao-string ou string vazia) em indice(s): $(printf '%s' "$_wl_bad" | tr '\n' ' ')"
fi

# 11. Cache de artefatos (FR-CACHE-017) — valida invariantes quando os
#     campos briefing_cache / constitution_cache estao presentes (nao-null).
# READER (schema-en-migration §3.9d): folhas de cache migradas para EN com
# fallback pt-BR (.en // .pt) — par coordenado com state-cache.sh (writer):
#   estrategia->strategy, resumo_chars->summary_chars, gerado_em->generated_at,
#   gerado_na_onda->generated_in_wave (resumo->summary, resumo_max_chars->
#   summary_max_chars, tokens_economizados_estimados->estimated_tokens_saved
#   nao sao lidas aqui). Containers *_cache + source_path/source_sha256/
#   source_chars ja eram EN (keep). VALORES de strategy
#   (resumo|passthrough|desabilitado) permanecem pt-BR (follow-up B). O
#   container de ondas (.waves) tambem tem fallback abaixo.
_validate_cache_field() {
  _cf=$1  # ex: briefing_cache | constitution_cache
  _present=$(jq -r "if .${_cf} == null then \"absent\" else \"present\" end" "$_SV_FILE" 2>/dev/null) || _present="absent"
  [ "$_present" = "present" ] || return 0

  # source_sha256: hex de 64 chars
  _sha=$(jq -r ".${_cf}.source_sha256 // \"\"" "$_SV_FILE" 2>/dev/null) || _sha=""
  _shalen=${#_sha}
  if [ "$_shalen" != "64" ]; then
    _sv_add "FR-CACHE-017: ${_cf}.source_sha256 deve ter 64 chars hex (got $_shalen)"
  else
    case "$_sha" in
      *[!0-9a-f]*)
        _sv_add "FR-CACHE-017: ${_cf}.source_sha256 contem caracter nao-hex"
        ;;
    esac
  fi

  # strategy: enum {resumo, passthrough, desabilitado}
  # READER: chave EN (strategy) + fallback pt-BR (estrategia). VALORES do enum
  # permanecem pt-BR (follow-up B).
  _est=$(jq -r "(.${_cf}.strategy // .${_cf}.estrategia) // \"\"" "$_SV_FILE" 2>/dev/null) || _est=""
  case "$_est" in
    resumo|passthrough|desabilitado) : ;;
    *) _sv_add "FR-CACHE-017: ${_cf}.strategy invalido: \"$_est\" (esperado: resumo|passthrough|desabilitado)" ;;
  esac

  # summary_chars <= source_chars
  # READER: source_chars ja EN (keep); summary_chars (EN) + fallback resumo_chars.
  _src_c=$(jq -r ".${_cf}.source_chars // 0" "$_SV_FILE" 2>/dev/null) || _src_c=0
  _res_c=$(jq -r "(.${_cf}.summary_chars // .${_cf}.resumo_chars) // 0" "$_SV_FILE" 2>/dev/null) || _res_c=0
  case "$_src_c" in ''|*[!0-9]*) _src_c=0 ;; esac
  case "$_res_c" in ''|*[!0-9]*) _res_c=0 ;; esac
  if [ "$_res_c" -gt "$_src_c" ]; then
    _sv_add "FR-CACHE-017: ${_cf}.summary_chars ($_res_c) > source_chars ($_src_c)"
  fi

  # generated_at: ISO-8601 (formato YYYY-MM-DDTHH:MM:SSZ)
  # READER: chave EN (generated_at) + fallback pt-BR (gerado_em).
  _ger=$(jq -r "(.${_cf}.generated_at // .${_cf}.gerado_em) // \"\"" "$_SV_FILE" 2>/dev/null) || _ger=""
  case "$_ger" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *) _sv_add "FR-CACHE-017: ${_cf}.generated_at nao eh ISO-8601 (got \"$_ger\")" ;;
  esac

  # generated_in_wave: >= 1 e <= numero da onda corrente (ou >=1 se sem ondas)
  # READER: chave EN (generated_in_wave) + fallback pt-BR (gerado_na_onda);
  # .waves tambem com fallback (.ondas).
  _gon=$(jq -r "(.${_cf}.generated_in_wave // .${_cf}.gerado_na_onda) // 0" "$_SV_FILE" 2>/dev/null) || _gon=0
  _ondas_total=$(jq -r '((.waves // .ondas) // []) | length' "$_SV_FILE" 2>/dev/null) || _ondas_total=0
  case "$_gon" in ''|*[!0-9]*) _gon=0 ;; esac
  case "$_ondas_total" in ''|*[!0-9]*) _ondas_total=0 ;; esac
  if [ "$_gon" -lt 1 ]; then
    _sv_add "FR-CACHE-017: ${_cf}.generated_in_wave ($_gon) deve ser >= 1"
  fi
  # generated_in_wave pode ser ate ondas_total+1 (cache populado antes do start da onda atual)
  _max_onda=$((_ondas_total + 1))
  if [ "$_gon" -gt "$_max_onda" ]; then
    _sv_add "FR-CACHE-017: ${_cf}.generated_in_wave ($_gon) > ondas_total+1 ($_max_onda)"
  fi
}

_validate_cache_field briefing_cache
_validate_cache_field constitution_cache

# ---------- Veredicto ----------

if [ -z "$_SV_VIOL" ]; then
  exit 0
fi

# Imprime cada violacao (omitindo a linha em branco do head)
printf '%s\n' "$_SV_VIOL" | sed '/^$/d' | while IFS= read -r _line; do
  _sv_emit_error "$_line"
done
exit 1
