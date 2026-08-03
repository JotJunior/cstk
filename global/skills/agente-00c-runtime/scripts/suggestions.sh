#!/bin/sh
# suggestions.sh — registro de Sugestoes para skills globais (FR-020).
#
# Ref: docs/specs/agente-00c/spec.md FR-020
#      docs/specs/agente-00c/data-model.md §Sugestao
#      docs/specs/agente-00c/tasks.md FASE 8.3
#
# Modelo: cada Sugestao identifica uma melhoria proposta a alguma skill em
# `~/.claude/skills/`. 3 severidades: informativa | aviso | impeditiva.
# Apenas impeditivas viram Issue no toolkit (FASE 8.4 — issue.sh).
#
# Sugestoes vivem em DOIS lugares:
#   1. state.json `.suggestions[]` (ground truth, JSON estruturado)
#   2. agente-00c-suggestions.md (export human-readable, regerado a cada
#      register a partir do estado).
#
# Subcomandos:
#   suggestions.sh register --state-dir DIR --suggestions-file FILE
#       --skill SKILL --diagnostico TEXT --severidade SEV --proposta TEXT
#       [--referencias JSON-ARR]
#       — Append em .suggestions; gera id `sug-NNN`; atualiza
#         accumulated_metrics.global_skill_suggestions_total; aplica
#         secrets-filter ao gravar suggestions.md.
#       — Stdout: id da sugestao registrada.
#
#   suggestions.sh list --state-dir DIR [--severidade SEV]
#       — TSV: id\tskill\tseverity\tissue_opened\tdiagnosis_short
#
#   suggestions.sh count --state-dir DIR [--severidade SEV]
#       — Imprime total (filtrado por severidade se passado).
#
#   suggestions.sh next-id --state-dir DIR
#       — Imprime proximo sug-NNN sem registrar.
#
#   suggestions.sh mark-issue --state-dir DIR --suggestion-id SUG --issue URL
#       — Atualiza .suggestions[i].issue_opened com URL/numero retornado por
#         issue.sh create.
#
#   suggestions.sh render-md --state-dir DIR > stdout
#       — Renderiza state.json `.suggestions[]` em markdown estruturado para
#         agente-00c-suggestions.md. Aplique secrets-filter externamente.
#
# Severidades validas: informativa | aviso | impeditiva
#
# Exit codes:
#   0 sucesso
#   1 erro generico
#   2 uso incorreto
#
# POSIX sh + jq.

set -eu

_SG_NAME="suggestions"

# Leitura via interface canonica (state-db-runtime-parity FR-001, lote 2.4):
# materializa documento legivel por jq nos DOIS backends (json/sqlite).
# Mutacoes (register/mark-issue) roteiam por `state-rw.sh set` — que cuida
# de backup + atomic write + sha (json) ou UPDATE (sqlite). O plumbing local
# de escrita (backup/atomic/sha) foi removido no porte.
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_sg_die_usage() { printf '%s: %s\n' "$_SG_NAME" "$1" >&2; exit 2; }
_sg_die()       { printf '%s: %s\n' "$_SG_NAME" "$1" >&2; exit "${2:-1}"; }

_sg_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _sg_die "jq nao encontrado no PATH" 1
}

_sg_iso_now() { date -u +%FT%TZ; }

# _sg_next_sug_id FILE (documento materializado)
_sg_next_sug_id() {
  _sf=$1
  jq -r '
    ((.suggestions // .sugestoes) // []) as $s
    | if ($s | length) == 0 then "sug-001"
    else
      ([$s[].id // ""] | map(sub("^sug-0*"; "") | tonumber? // 0) | max + 1)
      | tostring | "sug-" + (if length == 1 then "00" + . elif length == 2 then "0" + . else . end)
    end' "$_sf" 2>/dev/null
}

_sg_validate_severidade() {
  case "$1" in
    informativa|aviso|impeditiva) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- Subcomandos ----------

_sg_cmd_register() {
  _sd=""
  _sf_md=""
  _skill=""
  _diag=""
  _sev=""
  _prop=""
  _refs="[]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)        _sd=$2;    shift 2 ;;
      --suggestions-file) _sf_md=$2; shift 2 ;;
      --skill)            _skill=$2; shift 2 ;;
      --diagnostico)      _diag=$2;  shift 2 ;;
      --severidade)       _sev=$2;   shift 2 ;;
      --proposta)         _prop=$2;  shift 2 ;;
      --referencias)      _refs=$2;  shift 2 ;;
      *) _sg_die_usage "register: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]    || _sg_die_usage "register: --state-dir obrigatorio"
  [ -n "$_sf_md" ] || _sg_die_usage "register: --suggestions-file obrigatorio"
  [ -n "$_skill" ] || _sg_die_usage "register: --skill obrigatorio"
  [ -n "$_diag" ]  || _sg_die_usage "register: --diagnostico obrigatorio"
  [ -n "$_sev" ]   || _sg_die_usage "register: --severidade obrigatorio"
  [ -n "$_prop" ]  || _sg_die_usage "register: --proposta obrigatorio"
  _sg_require_jq

  _sg_validate_severidade "$_sev" \
    || _sg_die "register: --severidade invalida: $_sev (esperado informativa|aviso|impeditiva)" 2

  # Validacao tamanho minimo (data-model: diagnostico>=50)
  if [ "$(printf '%s' "$_diag" | wc -c | tr -d ' ')" -lt 50 ]; then
    _sg_die "register: --diagnostico < 50 chars (deve ser detalhado o suficiente para acao)" 1
  fi

  # Valida referencias e array
  if ! printf '%s' "$_refs" | jq -e 'type == "array"' >/dev/null 2>&1; then
    _sg_die "register: --referencias precisa ser JSON array" 2
  fi

  # Falha de materializacao sob sqlite (sqlite3 ausente, state.db corrompido)
  # propaga exit+stderr do state-rw.sh read via set -e (FR-012).
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _sg_die "register: state.json ausente em $_sd" 1

  _id=$(_sg_next_sug_id "$_sf")
  _now=$(_sg_iso_now)

  _new_suggs=$(jq -c \
    --arg id "$_id" \
    --arg skill "$_skill" \
    --arg diag "$_diag" \
    --arg sev "$_sev" \
    --arg prop "$_prop" \
    --arg now "$_now" \
    --argjson refs "$_refs" '
    (.suggestions // []) + [{
      id: $id,
      affected_skill: $skill,
      diagnosis: $diag,
      severity: $sev,
      proposal: $prop,
      references: $refs,
      issue_opened: null,
      created_at: $now
    }]' "$_sf") || _sg_die "register: jq update falhou" 1

  "$(_state_read_rw_bin)" set --state-dir "$_sd" \
    --field '.suggestions' --value "$_new_suggs"

  # Contador acumulado: sob backend SQLite ele e DERIVADO no read a partir de
  # .suggestions (extra_fields) — gravar seria recusado pelo set (campo
  # derivado). Sob JSON, preserva o bump historico no documento (FR-004).
  if [ ! -f "$_sd/state.db" ]; then
    _total=$(jq -r '((.accumulated_metrics.global_skill_suggestions_total // 0) + 1)' "$_sf")
    "$(_state_read_rw_bin)" set --state-dir "$_sd" \
      --field '.accumulated_metrics.global_skill_suggestions_total' --value "$_total"
  fi

  # Regenera suggestions.md a partir do estado ATUALIZADO (re-materializa;
  # sem secrets-filter — caller aplica se quiser)
  _sf_after=$(state_read_materialize "$_sd")
  _sg_render_md "$_sf_after" > "$_sf_md.tmp.$$" || {
    rm -f -- "$_sf_md.tmp.$$" 2>/dev/null
    _sg_die "render-md falhou" 1
  }
  mv -f -- "$_sf_md.tmp.$$" "$_sf_md"

  printf '%s\n' "$_id"
}

_sg_cmd_count() {
  _sd=""
  _sev=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)  _sd=$2;  shift 2 ;;
      --severidade) _sev=$2; shift 2 ;;
      *) _sg_die_usage "count: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _sg_die_usage "count: --state-dir obrigatorio"
  _sg_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _sg_die "count: state.json ausente" 1
  if [ -n "$_sev" ]; then
    _sg_validate_severidade "$_sev" \
      || _sg_die "count: --severidade invalida: $_sev" 2
    jq --arg s "$_sev" '(.suggestions // .sugestoes) // [] | map(select((.severity // .severidade) == $s)) | length' "$_sf"
  else
    jq '(.suggestions // .sugestoes) // [] | length' "$_sf"
  fi
}

_sg_cmd_list() {
  _sd=""
  _sev=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)  _sd=$2;  shift 2 ;;
      --severidade) _sev=$2; shift 2 ;;
      *) _sg_die_usage "list: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _sg_die_usage "list: --state-dir obrigatorio"
  _sg_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _sg_die "list: state.json ausente" 1
  jq -r --arg s "$_sev" '
    (.suggestions // .sugestoes) // []
    | map(select($s == "" or (.severity // .severidade) == $s))
    | .[]
    | [.id, (.affected_skill // .skill_afetada), (.severity // .severidade),
       ((.issue_opened // .issue_aberta) // "-"),
       ((.diagnosis // .diagnostico) | .[0:60])] | @tsv
  ' "$_sf"
}

_sg_cmd_next_id() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _sg_die_usage "next-id: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _sg_die_usage "next-id: --state-dir obrigatorio"
  _sg_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _sg_die "next-id: state.json ausente" 1
  _sg_next_sug_id "$_sf"
}

_sg_cmd_mark_issue() {
  _sd=""
  _sf_md=""
  _sug=""
  _issue=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)        _sd=$2;    shift 2 ;;
      --suggestions-file) _sf_md=$2; shift 2 ;;
      --suggestion-id)    _sug=$2;   shift 2 ;;
      --issue)            _issue=$2; shift 2 ;;
      *) _sg_die_usage "mark-issue: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]    || _sg_die_usage "mark-issue: --state-dir obrigatorio"
  [ -n "$_sug" ]   || _sg_die_usage "mark-issue: --suggestion-id obrigatorio"
  [ -n "$_issue" ] || _sg_die_usage "mark-issue: --issue obrigatorio (URL ou numero)"
  _sg_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _sg_die "mark-issue: state.json ausente" 1
  # Valida que sug existe
  _exists=$(jq --arg id "$_sug" '
    (.suggestions // .sugestoes) // [] | map(select(.id == $id)) | length
  ' "$_sf")
  [ "$_exists" -gt 0 ] || _sg_die "mark-issue: $_sug nao encontrada" 1

  _new_suggs=$(jq -c --arg id "$_sug" --arg url "$_issue" '
    .suggestions // [] | map(
      if .id == $id then .issue_opened = $url else . end
    )' "$_sf") || _sg_die "mark-issue: jq update falhou" 1

  "$(_state_read_rw_bin)" set --state-dir "$_sd" \
    --field '.suggestions' --value "$_new_suggs"

  # Contador acumulado: derivado no read sob SQLite (count de issue_opened
  # nao-null em .suggestions); bump so no backend JSON (FR-004).
  if [ ! -f "$_sd/state.db" ]; then
    _total=$(jq -r '((.accumulated_metrics.toolkit_issues_opened // 0) + 1)' "$_sf")
    "$(_state_read_rw_bin)" set --state-dir "$_sd" \
      --field '.accumulated_metrics.toolkit_issues_opened' --value "$_total"
  fi

  # Regenera suggestions.md se path passado (a partir do estado atualizado)
  if [ -n "$_sf_md" ]; then
    _sf_after=$(state_read_materialize "$_sd")
    if _sg_render_md "$_sf_after" > "$_sf_md.tmp.$$"; then
      mv -f -- "$_sf_md.tmp.$$" "$_sf_md" \
        || { rm -f -- "$_sf_md.tmp.$$" 2>/dev/null; _sg_die "mv md falhou" 1; }
    else
      rm -f -- "$_sf_md.tmp.$$" 2>/dev/null
      _sg_die "render-md falhou" 1
    fi
  fi
}

# _sg_render_md FILE (documento materializado) -> markdown de suggestions.md
_sg_render_md() {
  _sf=$1
  jq -r '
    ((.suggestions // .sugestoes) // []) as $sugs
    | "# Sugestoes do Agente-00C — \((.execution.id // .execucao.id))",
    "",
    "Total: \($sugs | length) sugestoes registradas.",
    "",
    (
      if ($sugs | length) == 0 then
        "Nenhuma sugestao registrada nesta execucao."
      else
        $sugs[] |
          "## \(.id) — skill `\(.affected_skill // .skill_afetada)` — severidade: \(.severity // .severidade)",
          "",
          "**Criada em**: \((.created_at // .criada_em) // "?")",
          "",
          "**Issue aberta**: \((.issue_opened // .issue_aberta) // "(nenhuma)")",
          "",
          "**Diagnostico**:",
          "",
          "\(.diagnosis // .diagnostico)",
          "",
          "**Proposta**:",
          "",
          "\(.proposal // .proposta)",
          "",
          "**Referencias**:",
          "",
          ((.references // .referencias) as $refs
           | if ($refs | length) == 0 then "- (sem referencias)"
             else ($refs | map("- " + .) | join("\n")) end),
          "",
          "---",
          ""
      end
    )
  ' "$_sf"
}

_sg_cmd_render_md() {
  _sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sd=$2; shift 2 ;;
      *) _sg_die_usage "render-md: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ] || _sg_die_usage "render-md: --state-dir obrigatorio"
  _sg_require_jq
  _sf=$(state_read_materialize "$_sd")
  [ -f "$_sf" ] || _sg_die "render-md: state.json ausente" 1
  _sg_render_md "$_sf"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
suggestions.sh — registro de Sugestoes para skills globais (FR-020).

USO:
  suggestions.sh register --state-dir DIR --suggestions-file FILE \
    --skill SKILL --diagnostico TEXT --severidade SEV --proposta TEXT \
    [--referencias JSON-ARR]
  suggestions.sh list      --state-dir DIR [--severidade SEV]
  suggestions.sh count     --state-dir DIR [--severidade SEV]
  suggestions.sh next-id   --state-dir DIR
  suggestions.sh mark-issue --state-dir DIR --suggestion-id SUG --issue URL
  suggestions.sh render-md --state-dir DIR

Severidades: informativa | aviso | impeditiva.

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto
HELP
  exit 2
fi

_SG_SUBCMD=$1
shift

case "$_SG_SUBCMD" in
  register)        _sg_cmd_register "$@" ;;
  count)           _sg_cmd_count "$@" ;;
  list)            _sg_cmd_list "$@" ;;
  next-id)         _sg_cmd_next_id "$@" ;;
  mark-issue)      _sg_cmd_mark_issue "$@" ;;
  render-md)       _sg_cmd_render_md "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _sg_die_usage "subcomando desconhecido: $_SG_SUBCMD" ;;
esac
