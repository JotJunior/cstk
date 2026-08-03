#!/bin/sh
# feature-00c-preflight.sh — pre-flight check entre fases `spec → plan`
# do orquestrador-de-feature (FR-010A).
#
# Ref: docs/specs/feature-00c/spec.md FR-010A, FR-PRE-004, FR-013
#      docs/specs/feature-00c/research.md Decision 4
#      docs/specs/feature-00c/tasks.md FASE 2 task 2.1
#
# Auditoria empirica (vide research.md Decision 4 + scripts/_audit-paths.md):
# o agente-00c `pipeline.sh constitution-conflict` opera a nivel de PATH
# (existencia de constitution.md por feature). Para feature-00c — que
# NAO cria constitution.md por feature — o pre-flight relevante e:
#
#   1. Validar que briefing.sha256 + constitution.sha256 registrados em
#      state.json batem com os arquivos em disco (FR-PRE-004). Detectar
#      MAJOR vs MINOR/PATCH no version drift.
#   2. Chamar pipeline.sh constitution-conflict para diagnostico (espera
#      exit 0 quando feature nao tem constitution propria).
#   3. Emitir JSON estruturado com findings + exit code agregado.
#
# Uso:
#   feature-00c-preflight.sh check --state-dir DIR
#       — executa pre-flight completo. Output JSON em stdout.
#       — Exit 0 = OK; 1 = drift/conflito; 2 = uso incorreto / I/O erro.
#
# Output JSON:
#   {
#     "ok": bool,
#     "findings": [
#       {"kind": "briefing_hash_drift|constitution_hash_drift|constitution_major_drift|constitution_conflict",
#        "severity": "warn|error",
#        "current_sha": "...",
#        "recorded_sha": "...",
#        "detail": "..."}
#     ]
#   }

set -eu

_FP_NAME="feature-00c-preflight"

# Materializacao de estado backend-agnostica via helper comum
# _state-read.sh (state-db-runtime-parity FASE 2 lote 2.6 — substitui a
# copia local do padrao a06e747/v6.2.2). JSON: path direto do
# state.json; SQLite (state.db): tmp 0600 fora do state-dir. Falha de
# materializacao propaga via set -e (FR-012) em vez do antigo fallback
# mudo para o state.json.
# shellcheck source=./_state-read.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_fp_die_usage() { printf '%s: %s\n' "$_FP_NAME" "$1" >&2; exit 2; }
_fp_die_io()    { printf '%s: %s\n' "$_FP_NAME" "$1" >&2; exit 2; }

# _fp_sha256 FILE -> imprime sha256 hex em stdout
_fp_sha256() {
  if [ ! -f "$1" ]; then
    return 1
  fi
  sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

# _fp_major_changed OLD_VER NEW_VER -> exit 0 se MAJOR mudou, 1 caso contrario
_fp_major_changed() {
  _old_major=$(printf '%s' "$1" | cut -d. -f1)
  _new_major=$(printf '%s' "$2" | cut -d. -f1)
  [ "$_old_major" != "$_new_major" ]
}

_fp_cmd_check() {
  _state_dir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _state_dir=$2; shift 2 ;;
      *) _fp_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_state_dir" ] || _fp_die_usage "check: --state-dir obrigatorio"
  [ -d "$_state_dir" ] || _fp_die_io   "check: state-dir nao existe ou nao e dir: $_state_dir"

  # Backend-agnostico (fix pos-6.2.1: com backend sqlite este check era
  # INERTE — "state.json ausente" e a validacao de drift FR-PRE-004 nunca
  # rodava nas retomadas). Materializacao delegada ao helper comum
  # _state-read.sh (json E sqlite); ausencia de estado morre no check -f.
  _state_file=$(state_read_materialize "$_state_dir")
  [ -f "$_state_file" ] || _fp_die_io "check: estado ausente em $_state_dir (nem state.db nem state.json)"

  # Extrair campos de prerequisites (FR-PRE-004). Reader-fallback EN->pt (schema-en-migration).
  _br_path=$(jq -r '(.prerequisites.briefing.path // .pre_requisitos.briefing.path) // empty' "$_state_file" 2>/dev/null)
  _br_sha=$(jq  -r '(.prerequisites.briefing.sha256 // .pre_requisitos.briefing.sha256) // empty' "$_state_file" 2>/dev/null)
  _ct_path=$(jq -r '(.prerequisites.constitution.path // .pre_requisitos.constitution.path) // empty' "$_state_file" 2>/dev/null)
  _ct_sha=$(jq  -r '(.prerequisites.constitution.sha256 // .pre_requisitos.constitution.sha256) // empty' "$_state_file" 2>/dev/null)
  _ct_ver=$(jq  -r '(.prerequisites.constitution.version // .pre_requisitos.constitution.version) // empty' "$_state_file" 2>/dev/null)
  _projeto=$(jq -r '(.execution.target_project_path // .execucao.projeto_alvo_path) // empty' "$_state_file" 2>/dev/null)

  if [ -z "$_br_path" ] || [ -z "$_br_sha" ] || [ -z "$_ct_path" ] || [ -z "$_ct_sha" ]; then
    _fp_die_io "check: state.json sem campos prerequisites completos (FR-PRE-004)"
  fi
  [ -n "$_projeto" ] || _fp_die_io "check: state.json sem execution.target_project_path"

  # Resolver paths absolutos relativos ao projeto-alvo
  case "$_br_path" in /*) _br_abs="$_br_path" ;; *) _br_abs="$_projeto/$_br_path" ;; esac
  case "$_ct_path" in /*) _ct_abs="$_ct_path" ;; *) _ct_abs="$_projeto/$_ct_path" ;; esac

  # Coletar findings em arquivos temporarios (linhas JSON)
  _findings_file=$(mktemp)
  _ok=true

  # Briefing hash
  if [ ! -f "$_br_abs" ]; then
    printf '{"kind":"briefing_missing","severity":"error","detail":"briefing.md nao encontrado em %s"}\n' "$_br_abs" >> "$_findings_file"
    _ok=false
  else
    _br_now=$(_fp_sha256 "$_br_abs")
    if [ "$_br_now" != "$_br_sha" ]; then
      printf '{"kind":"briefing_hash_drift","severity":"error","current_sha":"%s","recorded_sha":"%s","detail":"briefing.md alterado entre ondas"}\n' "$_br_now" "$_br_sha" >> "$_findings_file"
      _ok=false
    fi
  fi

  # Constitution hash + version
  if [ ! -f "$_ct_abs" ]; then
    printf '{"kind":"constitution_missing","severity":"error","detail":"constitution.md nao encontrado em %s"}\n' "$_ct_abs" >> "$_findings_file"
    _ok=false
  else
    _ct_now=$(_fp_sha256 "$_ct_abs")
    if [ "$_ct_now" != "$_ct_sha" ]; then
      # Detectar nova versao no rodape
      _ct_ver_now=$(grep -E '^\*\*Version\*\*:\s*[0-9]+\.[0-9]+\.[0-9]+' "$_ct_abs" 2>/dev/null | head -1 | sed -E 's/.*Version[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
      [ -n "$_ct_ver_now" ] || _ct_ver_now="$_ct_ver"
      # Major bump = bloqueio compulsorio
      if [ -n "$_ct_ver" ] && [ -n "$_ct_ver_now" ] && _fp_major_changed "$_ct_ver" "$_ct_ver_now"; then
        printf '{"kind":"constitution_major_drift","severity":"error","current_sha":"%s","recorded_sha":"%s","current_version":"%s","recorded_version":"%s","detail":"constitution mudou MAJOR entre ondas — bloqueio compulsorio"}\n' "$_ct_now" "$_ct_sha" "$_ct_ver_now" "$_ct_ver" >> "$_findings_file"
        _ok=false
      else
        printf '{"kind":"constitution_hash_drift","severity":"warn","current_sha":"%s","recorded_sha":"%s","current_version":"%s","recorded_version":"%s","detail":"constitution mudou MINOR/PATCH entre ondas — aviso, pergunta opcional"}\n' "$_ct_now" "$_ct_sha" "$_ct_ver_now" "$_ct_ver" >> "$_findings_file"
        # MINOR/PATCH nao quebra ok
      fi
    fi
  fi

  # Pipeline constitution-conflict (forward-compat / consistencia com 00c)
  _pl="$(dirname -- "$0")/pipeline.sh"
  if [ -x "$_pl" ] || [ -f "$_pl" ]; then
    # feature-dir do feature-00c = docs/specs/<short>/ no projeto-alvo
    _short=$(jq -r '(.execution.short_name // .execucao.short_name) // empty' "$_state_file" 2>/dev/null)
    _fdir="$_projeto/docs/specs/$_short"
    if [ -n "$_short" ] && [ -d "$_fdir" ]; then
      if ! sh "$_pl" constitution-conflict --feature-dir "$_fdir" --projeto-alvo-path "$_projeto" >/dev/null 2>&1; then
        _pl_exit=$?
        if [ "$_pl_exit" = "1" ]; then
          printf '{"kind":"constitution_conflict","severity":"error","detail":"pipeline.sh constitution-conflict reportou conflito raiz vs feature"}\n' >> "$_findings_file"
          _ok=false
        fi
        # exit 2 (alerta pre-skill) nao aplicavel a feature-00c que nao cria constitution propria — silencioso
      fi
    fi
  fi

  # Montar JSON final
  if [ "$_ok" = "true" ]; then
    _ok_json="true"
  else
    _ok_json="false"
  fi

  # Construir array de findings
  if [ -s "$_findings_file" ]; then
    _findings_arr=$(jq -s '.' "$_findings_file")
  else
    _findings_arr="[]"
  fi
  rm -f -- "$_findings_file"

  jq -n \
    --argjson ok "$_ok_json" \
    --argjson findings "$_findings_arr" \
    '{ok: $ok, findings: $findings}'

  [ "$_ok" = "true" ] && exit 0
  exit 1
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
feature-00c-preflight.sh — pre-flight check antes da fase plan (FR-010A).

USO:
  feature-00c-preflight.sh check --state-dir DIR

Valida:
  - briefing.sha256 (FR-PRE-004): bate com arquivo em disco?
  - constitution.sha256 + version: bate? MAJOR drift = error; MINOR/PATCH = warn.
  - constitution-conflict (pipeline.sh): roda forward-compat com 00c.

Output JSON em stdout: {ok: bool, findings: [...]}

EXIT:
  0 = ok (sem drift critico)
  1 = drift detectado / conflito
  2 = uso incorreto / I/O erro
HELP
  exit 2
fi

_FP_SUBCMD=$1
shift

case "$_FP_SUBCMD" in
  check)           _fp_cmd_check "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _fp_die_usage "subcomando desconhecido: $_FP_SUBCMD" ;;
esac
