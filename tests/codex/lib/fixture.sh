#!/bin/sh
# Shared POSIX fixtures; all projects, HOME, knowledge and installs are temporary.
TESTS_ROOT=${TESTS_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)}
REPO_ROOT=${REPO_ROOT:-$(CDPATH='' cd -- "$TESTS_ROOT/.." && pwd -P)}
. "$TESTS_ROOT/lib/harness.sh"
T_SCRIPTS=$REPO_ROOT/adapters/codex/skills/feature-00c/scripts
T_RUNTIME=$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts

t_select() {
  T_PROJECT=$(CDPATH='' cd -- "$TMPDIR_TEST" && pwd -P)/project
  HOME=$TMPDIR_TEST/home; CSTK_KNOWLEDGE_DB=$TMPDIR_TEST/knowledge.db
  export HOME CSTK_KNOWLEDGE_DB
  mkdir -p "$HOME" "$T_PROJECT/docs"
  git -C "$T_PROJECT" init -q
  printf '# Briefing\nLocal audited feature\n' > "$T_PROJECT/docs/briefing.md"
  printf '# Constitution\n**Version**: 1.0.0\n' > "$T_PROJECT/docs/constitution.md"
  if [ "${2:-json}" = sqlite ]; then mkdir -p "$HOME/.claude/cstk"; printf 'state_backend=sqlite\n' > "$HOME/.claude/cstk/config"; fi
  CX_ENTRY_DIR=$T_SCRIPTS
  . "$T_SCRIPTS/_entry.sh"
  set +eu
  trap 'cx_cleanup; _cleanup_tmpdir' 0
  T_KIND=${1:-feature}
  t_good select_execution "$(printf '{"project":%s,"short_name":"test-feature","kind":%s}' "$(cj_quote "$T_PROJECT")" "$(cj_quote "$T_KIND")")" || return
  T_FEATURE=$T_PROJECT/docs/specs/test-feature
}
t_call() { CX_ARGS=$2; cx_action "$1"; }
t_good() {
  if [ "$#" = 1 ]; then capture t_call "$1" '{}'; else capture t_call "$1" "$2"; fi
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "$1" "$_CAPTURED_STDERR"; return 1; }
}
t_bad() {
  if [ "$#" = 1 ]; then capture t_call "$1" '{}'; else capture t_call "$1" "$2"; fi
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "$1" 'expected refusal'; return 1; }
}
t_bootstrap() { t_good bootstrap '{"description":"Create an audited local feature","canonical_project":"test-feature"}'; }
t_ready() {
  t_select "${1:-feature}" "${2:-json}" || return
  if [ "${3:-}" = bare ]; then rm "$T_PROJECT/docs/briefing.md" "$T_PROJECT/docs/constitution.md"; fi
  t_bootstrap || return
  t_good optin '{"value":false,"field":"atomic_commit","channel":"prose","response_source":"Actual operator fixture response"}' || return
  if [ "$T_KIND" = project ]; then
    t_good optin "$(printf '{"value":%s,"field":"roadmap_mode","channel":"prose","response_source":"Actual operator fixture response"}' "${4:-false}")" || return
    t_good optin '{"value":"local","field":"delivery_tier","channel":"prose","response_source":"Actual operator fixture response"}' || return
  fi
}
t_state() { sh "$T_RUNTIME/state-rw.sh" read --state-dir "$CX_STATE"; }
t_field() { sh "$T_RUNTIME/state-rw.sh" set --state-dir "$CX_STATE" --field "$1" --value "$2"; }
t_expect() {
  _te_value=$(cj_get "$(t_state)" "$1")
  [ "$_te_value" = "$2" ] || { _fail state "pointer $1: expected $2, got $_te_value"; return 1; }
}
t_evidence() {
  mkdir -p "$(dirname -- "$T_FEATURE/$1")"
  printf '# Reviewed artifact\nEvidence of completed phase.\n' > "$T_FEATURE/$1"
}
t_tasks() {
  mkdir -p "$T_FEATURE"
  cat > "$T_FEATURE/tasks.md" <<'EOF'
# Tarefas: teste
## FASE 1 - Implementacao
### 1.1 Funcao `[C]`
- [ ] 1.1.1 Implementar funcao
## Matriz de Dependencias
```mermaid
flowchart TD
F1
```
## Resumo Quantitativo
| Fase | T |
## Escopo Coberto
Funcao local
## Escopo Excluido
Publicacao
EOF
}
t_finish() { t_good complete "$(printf '{"evidence_paths":[%s],"rationale":"Actual artifacts inspected and canonical phase gates passed."}' "$(cj_quote "$1")")"; }
t_pause() { t_good pause '{"instruction":"Continue the current phase with verified artifacts."}'; }
t_pipeline() {
  _tp_stages=$(cj_each "$CX_CONTEXT" /stages)
  while IFS= read -r _tp_stage; do
    _tp_stage=$(cj_get "$_tp_stage")
    t_good open_wave || return
    [ "$CX_STAGE" = "$_tp_stage" ] || return 1
    case "$_tp_stage" in
      briefing) printf '# Briefing\n## Visao\nFerramenta local\n## Usuarios\nOperador\n## Escopo\nPipeline\n## Prioridades\nAuditoria\n' > "$T_PROJECT/docs/briefing.md"; _tp_path=docs/briefing.md ;;
      constitution) printf '# Constitution\n**Version**: 1.0.0\n' > "$T_PROJECT/docs/constitution.md"; _tp_path=docs/constitution.md ;;
      specify|clarify) t_evidence spec.md; _tp_path=docs/specs/test-feature/spec.md ;;
      plan) t_evidence plan.md; _tp_path=docs/specs/test-feature/plan.md ;;
      checklist) t_evidence checklists/check.md; _tp_path=docs/specs/test-feature/checklists/check.md ;;
      create-tasks|execute-task)
        t_tasks; _tp_path=docs/specs/test-feature/tasks.md
        if [ "$_tp_stage" = execute-task ]; then
          t_bad complete "$(printf '{"evidence_paths":[%s],"rationale":"Actual task evidence checked before completion."}' "$(cj_quote "$_tp_path")")" || return
          sed 's/\[ \]/[x]/g' "$T_FEATURE/tasks.md" > "$T_FEATURE/tasks.tmp"; mv "$T_FEATURE/tasks.tmp" "$T_FEATURE/tasks.md"
        fi ;;
      converge) (cd "$T_PROJECT" && sh "$REPO_ROOT/plugins/cstk/skills/converge/scripts/converge-status.sh" record --feature-dir "$T_FEATURE" --outcome clean --provenance gate --actionable 0) >/dev/null || return; _tp_path=docs/specs/test-feature/converge-report.md ;;
      roadmap)
        mkdir -p "$T_FEATURE"
        cat > "$T_PROJECT/docs/roadmap.md" <<'ROADMAP'
# Roadmap: teste
**Gerado por**: agente-00c
**Atualizado em**: 2026-10-03

## Ordem sugerida
| # | Feature | Depende de | Descricao |
|---|---|---|---|
| 1 | `auth-basica` | - | Autenticacao |

## Features
### 1. auth-basica
- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Autenticacao local.

**Justificativa**: Controle de acesso.
ROADMAP
        _tp_path=docs/roadmap.md ;;
      *) t_evidence "$_tp_stage.md"; _tp_path=docs/specs/test-feature/$_tp_stage.md ;;
    esac
    t_finish "$_tp_path" || return
  done <<EOF
$_tp_stages
EOF
  t_expect /execution/status concluida || return
  [ ! -d "$CX_STATE/.lock" ] && [ ! -d "$T_PROJECT/.claude/.cstk-codex-wave-lock" ]
}
