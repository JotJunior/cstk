#!/bin/sh
# jira-tasks.sh — projeta docs/specs/<feature>/tasks.md (+ spec.md) no
# formato LocalWorkItem do plugin cstk-jira (feature cstk-jira, FASE 2
# tarefa 2.2).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity LocalWorkItem (derivado,
#      nao persistido); docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-tasks.sh`; docs/specs/cstk-jira/tasks.md 2.2.1-2.2.6; template
#      canonico plugins/cstk/skills/create-tasks/templates/tasks.md.
#
# Subcomandos:
#   jira-tasks.sh items --feature F [--outcomes-file FILE] [--stage STAGE]
#       — Le `<cwd>/docs/specs/F/tasks.md` (e, se existir,
#         `<cwd>/docs/specs/F/spec.md` para o titulo do Epic) e imprime em
#         stdout uma linha TSV por item (Epic + Tasks + Sub-tasks):
#             local_key  kind  phase  criticality  local_state  title
#         --outcomes-file FILE: TSV opcional `task_id<TAB>outcome`
#           (outcome = pass|fail), fonte do "outcome registrado da task
#           (record_task/record-task)" que TEM PRECEDENCIA sobre os
#           checkboxes na derivacao de local_state de uma task
#           (data-model.md). Quem grava esse arquivo (jira-sync.sh/hooks,
#           FASE 4/5) fica fora do escopo desta tarefa — aqui so o formato
#           de leitura e fixado.
#         --stage STAGE: quando presente, consulta
#           `jira-config.sh get "stage_status.STAGE"` (mesmo cwd de
#           ProjectConfig) para o local_state do Epic; ausencia do config
#           ou da chave (exit != 0 de jira-config.sh) e tratada como "nao
#           configurado" — cai na regra de agregacao por tasks.
#
# Nota sobre tasks.md 2.2.5 ("Titulo do Epic prefixado por fase
# `[FASE N] N.M <titulo>`"): o padrao `[FASE N] N.M <titulo>` so faz
# sentido para uma TASK (tem N.M — o Epic nao tem), o que bate com o
# resto da propria frase de data-model.md ("dependencias/criticidade
# entram na descricao da Task"); a palavra "Epic" ali diverge do
# restante do enunciado. O campo `title` de LocalWorkItem e definido em
# data-model.md como "texto do heading/checkbox" (sem prefixo); os
# ingredientes para montar `[FASE N] N.M <titulo>` (phase + local_key +
# title) ja saem como colunas separadas desta TSV — compor a string
# final do `fields.summary` do Jira e responsabilidade de quem constroi
# o corpo REST (FASE 3.5.2 `json-build`/FASE 4.1.3 `convert`), nao deste
# script de projecao local pura.
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral (tasks.md/outcomes-file
#   ausente); 2 uso incorreto.
#
# Nenhum host/credencial e tocado por este script (so parseia arquivos
# locais versionados da feature).

set -eu

_JT_NAME="jira-tasks"

_jt_die_usage() { printf '%s: %s\n' "$_JT_NAME" "$1" >&2; exit 2; }
_jt_die()       { printf '%s: %s\n' "$_JT_NAME" "$1" >&2; exit "${2:-1}"; }

_jt_usage() {
  cat <<'HELP'
jira-tasks.sh — projeta tasks.md/spec.md da feature em LocalWorkItem (TSV)

USO:
  jira-tasks.sh items --feature F [--outcomes-file FILE] [--stage STAGE]
      Imprime: local_key  kind  phase  criticality  local_state  title
      (uma linha por Epic/Task/Sub-task, TAB-separado)

Le <cwd>/docs/specs/F/tasks.md (obrigatorio) e <cwd>/docs/specs/F/spec.md
(opcional, titulo do Epic).

EXIT CODES:
  0 sucesso   1 erro geral (tasks.md/outcomes-file ausente)   2 uso incorreto
HELP
}

# _jt_is_safe_feature VALUE -> exit 0 se VALUE e seguro para compor um path
# (charset [A-Za-z0-9_-] apenas — mesma disciplina de allowlist do resto do
# plugin, aplicada aqui em defesa de path traversal via --feature).
_jt_is_safe_feature() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# _jt_script_dir -> diretorio deste script (para localizar jira-config.sh
# irmao; scripts do plugin ficam sempre colocados no disco do usuario).
_jt_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

_jt_cmd_items() {
  _jti_feature=""
  _jti_outcomes_file=""
  _jti_stage=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _jt_die_usage "--feature requer valor"
        _jti_feature="$2"
        shift 2
        ;;
      --outcomes-file)
        [ "$#" -ge 2 ] || _jt_die_usage "--outcomes-file requer valor"
        _jti_outcomes_file="$2"
        shift 2
        ;;
      --stage)
        [ "$#" -ge 2 ] || _jt_die_usage "--stage requer valor"
        _jti_stage="$2"
        shift 2
        ;;
      *)
        _jt_die_usage "argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_jti_feature" ] || _jt_die_usage "items requer --feature F"
  _jt_is_safe_feature "$_jti_feature" \
    || _jt_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jti_feature"

  _jti_tasks_file="./docs/specs/$_jti_feature/tasks.md"
  _jti_spec_file="./docs/specs/$_jti_feature/spec.md"

  [ -f "$_jti_tasks_file" ] || _jt_die "tasks.md nao encontrado: $_jti_tasks_file"

  if [ -n "$_jti_outcomes_file" ] && [ ! -f "$_jti_outcomes_file" ]; then
    _jt_die "outcomes-file nao encontrado: $_jti_outcomes_file"
  fi

  # Titulo do Epic: "# Feature Specification: <Titulo>" (spec.md, template
  # canonico); ausente ou sem essa linha -> usa o proprio short-name.
  _jti_epic_title="$_jti_feature"
  if [ -f "$_jti_spec_file" ]; then
    _jti_from_spec=$(sed -n 's/^# Feature Specification: *//p' "$_jti_spec_file" | head -n 1)
    [ -n "$_jti_from_spec" ] && _jti_epic_title="$_jti_from_spec"
  fi

  # stage_status.<stage> (Epic override): delega a jira-config.sh (mesmo
  # cwd de ProjectConfig); ausencia de config/chave = "nao configurado".
  _jti_stage_override=""
  if [ -n "$_jti_stage" ]; then
    _jti_cfg_script="$(_jt_script_dir)/jira-config.sh"
    if [ -x "$_jti_cfg_script" ]; then
      _jti_stage_override=$("$_jti_cfg_script" get "stage_status.$_jti_stage" 2>/dev/null) || _jti_stage_override=""
    fi
  fi

  awk -v feature="$_jti_feature" \
      -v epic_title="$_jti_epic_title" \
      -v stage_override="$_jti_stage_override" \
      -v outcomes_file="$_jti_outcomes_file" '
    BEGIN {
      FS = "\t"
      if (outcomes_file != "") {
        while ((getline oline < outcomes_file) > 0) {
          n = split(oline, ofields, "\t")
          if (n >= 2 && ofields[1] != "") outcome[ofields[1]] = ofields[2]
        }
        close(outcomes_file)
      }
      cur_phase = ""
      have_task = 0
      n_out = 0
      cur_sub_count = 0
      n_tasks_total = 0
      n_tasks_pass = 0
      n_tasks_active = 0
    }

    # extract_crit(s): retorna s sem o tag final `` `[C|A|M]` `` (e sem
    # espacos residuais); deixa a letra encontrada em _crit ("" se nenhum
    # tag presente). Tag real do template: backtick + colchete + letra +
    # colchete + backtick (ex.: `` `[C]` ``) — nao so backtick+letra+backtick.
    function extract_crit(s,   letter) {
      _crit = ""
      if (match(s, /`\[[CAM]\]`[ \t]*$/)) {
        letter = substr(s, RSTART + 2, 1)
        _crit = letter
        s = substr(s, 1, RSTART - 1)
      }
      sub(/[ \t]+$/, "", s)
      return s
    }

    function mapbox(b) {
      if (b == "x") return "pass"
      if (b == "~") return "in_progress"
      if (b == "!") return "fail"
      return "pending"
    }

    function flush_task(   state, i) {
      if (!have_task) return
      if (cur_task_key in outcome) {
        state = outcome[cur_task_key]
      } else if (cur_sub_n == 0) {
        state = "pending"
      } else if (cur_sub_fail > 0) {
        state = "fail"
      } else if (cur_sub_pass == cur_sub_n) {
        state = "pass"
      } else if (cur_sub_prog > 0 || (cur_sub_pass > 0 && cur_sub_pending > 0)) {
        state = "in_progress"
      } else {
        state = "pending"
      }
      n_tasks_total++
      if (state == "pass") n_tasks_pass++
      if (state == "pass" || state == "in_progress") n_tasks_active++
      out[n_out++] = cur_task_key "\ttask\t" cur_phase "\t" cur_task_crit "\t" state "\t" cur_task_title
      for (i = 0; i < cur_sub_count; i++) out[n_out++] = sub_lines[i]
      have_task = 0
      cur_sub_count = 0
      cur_sub_n = 0; cur_sub_pass = 0; cur_sub_fail = 0; cur_sub_prog = 0; cur_sub_pending = 0
    }

    { sub(/\r$/, "", $0) }

    /^## FASE [0-9]+/ {
      flush_task()
      line = $0
      sub(/^## /, "", line)
      cur_phase = extract_crit(line)
      next
    }

    /^### [0-9]+\.[0-9]+[ \t]/ {
      flush_task()
      line = $0
      sub(/^### /, "", line)
      keyend = index(line, " ")
      cur_task_key = substr(line, 1, keyend - 1)
      rest = substr(line, keyend + 1)
      cur_task_title = extract_crit(rest)
      cur_task_crit = _crit
      have_task = 1
      cur_sub_count = 0
      cur_sub_n = 0; cur_sub_pass = 0; cur_sub_fail = 0; cur_sub_prog = 0; cur_sub_pending = 0
      next
    }

    /^- \[[ x~!]\] [0-9]+\.[0-9]+\.[0-9]+[ \t]/ {
      line = $0
      box = substr(line, 4, 1)
      rest = substr(line, 7)
      keyend = index(rest, " ")
      subkey = substr(rest, 1, keyend - 1)
      subtitle = rest
      sub(/^[0-9]+\.[0-9]+\.[0-9]+[ \t]+/, "", subtitle)
      state = mapbox(box)
      cur_sub_n++
      if (state == "pass") cur_sub_pass++
      else if (state == "fail") cur_sub_fail++
      else if (state == "in_progress") cur_sub_prog++
      else cur_sub_pending++
      sub_lines[cur_sub_count++] = subkey "\tsubtask\t" cur_phase "\t\t" state "\t" subtitle
      next
    }

    # Qualquer outro heading nivel 2 (Matriz de Dependencias, Resumo
    # Quantitativo, Escopo Coberto/Excluido) fecha a janela de continuacao
    # de subtask e encerra a task pendente — essas secoes nao fazem parte
    # do LocalWorkItem.
    /^## / {
      flush_task()
      cur_phase = ""
      next
    }

    # Continuacao de descricao de subtask (linha indentada que segue
    # imediatamente um "- [ ] N.M.K ...", sem heading/bullet/linha em
    # branco entre elas — convencao do template de create-tasks). So
    # aplica enquanto ha uma subtask ja bufferizada nesta task.
    /^[ \t]+[^ \t]/ {
      if (cur_sub_count > 0) {
        line = $0
        sub(/^[ \t]+/, "", line)
        sub_lines[cur_sub_count - 1] = sub_lines[cur_sub_count - 1] " " line
      }
      next
    }

    END {
      flush_task()
      if (stage_override != "") {
        epic_state = stage_override
      } else if (n_tasks_total > 0 && n_tasks_pass == n_tasks_total) {
        epic_state = "pass"
      } else if (n_tasks_active > 0) {
        epic_state = "in_progress"
      } else {
        epic_state = "pending"
      }
      print feature "\tepic\t\t\t" epic_state "\t" epic_title
      for (i = 0; i < n_out; i++) print out[i]
    }
  ' "$_jti_tasks_file"
}

# --- dispatcher ---------------------------------------------------------

_jt_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_jt_sub" in
  ''|-h|--help|help)
    _jt_usage
    exit 0
    ;;
  items)
    _jt_cmd_items "$@"
    ;;
  *)
    _jt_die_usage "subcomando desconhecido: $_jt_sub (validos: items)"
    ;;
esac
