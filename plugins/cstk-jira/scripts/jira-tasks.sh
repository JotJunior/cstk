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
#   jira-tasks.sh phase-edges --feature F
#       — r02 FASE 18 tarefa 18.3.1 (data-model.md Entity IssueLink;
#         research.md Decision R2-6; contracts/plugin-scripts.md
#         `jira-tasks.sh phase-edges`): imprime uma linha `A<TAB>B` (numeros
#         puros, sem o prefixo "FASE") por aresta `FA --> FB` da secao
#         "## Matriz de Dependencias" de tasks.md — mesmo parser mermaid de
#         `phase-deps`, mas devolvendo TODAS as arestas de uma vez (nao
#         filtrado por uma FASE-alvo). Sem secao Matriz ou sem arestas:
#         stdout vazio, exit 0 (nunca erro).
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

  jira-tasks.sh phase-deps --feature F --phase PHASE
      Imprime uma linha por FASE da qual PHASE depende (rotulo completo,
      extraido da secao "## Matriz de Dependencias" de tasks.md — unica
      fonte real de dependencia deste backlog, FR-001). PHASE e a coluna
      `phase` de `items` (ex.: "FASE 6 - Skills Interativas"). Sem numero de
      fase reconhecivel, sem secao Matriz, ou sem aresta apontando para essa
      fase: stdout vazio, exit 0 (dependencia "quando existir").

  jira-tasks.sh phase-edges --feature F
      Imprime uma linha A<TAB>B (numeros de FASE) por aresta FA --> FB da
      "## Matriz de Dependencias" (mesmo parser de phase-deps). Sem secao/
      arestas: stdout vazio, exit 0.

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

# _jt_cmd_phase_deps --feature F --phase PHASE — feature cstk-jira FASE 10
# tarefa 10.1 (FR-001 "dependencias... quando existirem"). A UNICA fonte real
# e extraivel de dependencia neste backlog e a secao "## Matriz de
# Dependencias" (grafo mermaid FASE-a-FASE, template canonico
# plugins/cstk/skills/create-tasks/templates/tasks.md) — NAO existe
# dependencia por-task no formato do template (Principio VI: nunca inventar
# um campo "depende de N.M" que a fonte nao tem). Por isso esta funcao
# resolve dependencias no nivel de FASE: dado PHASE (coluna `phase` de
# `items`, ex.: "FASE 6 - Skills Interativas"), imprime uma linha por FASE
# da qual ela depende (rotulo completo do node de origem de cada aresta
# "F<M> --> F<N>" onde N e o numero desta FASE). Sem numero de FASE
# reconhecivel, sem secao Matriz, ou sem arestas apontando para N: nenhuma
# linha (silencio, nunca erro — dependencia "quando existir").
_jt_cmd_phase_deps() {
  _jtpd_feature=""
  _jtpd_phase=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _jt_die_usage "--feature requer valor"
        _jtpd_feature="$2"
        shift 2
        ;;
      --phase)
        [ "$#" -ge 2 ] || _jt_die_usage "--phase requer valor"
        _jtpd_phase="$2"
        shift 2
        ;;
      *)
        _jt_die_usage "argumento desconhecido: $1"
        ;;
    esac
  done

  _jt_is_safe_feature "$_jtpd_feature" \
    || _jt_die_usage "--feature invalido (charset [A-Za-z0-9_-]): '$_jtpd_feature'"
  [ -n "$_jtpd_phase" ] || _jt_die_usage "phase-deps requer --phase nao-vazio"

  _jtpd_tasks_file="./docs/specs/$_jtpd_feature/tasks.md"
  [ -f "$_jtpd_tasks_file" ] || _jt_die "tasks.md nao encontrado: $_jtpd_tasks_file" 1

  # Numero da FASE: 2a palavra de "FASE N - <nome>" (ex.: "FASE 6 - Skills
  # Interativas" -> "6"). PHASE sem esse formato -> sem dependencia conhecida
  # (silencio, nao erro: campos vazios de LocalWorkItem — ex.: Epic/Sub-task
  # — chamam phase-deps com string vazia/fora do formato eventualmente).
  _jtpd_num=$(printf '%s' "$_jtpd_phase" | awk '{print $2}')
  case "$_jtpd_num" in
    ''|*[!0-9]*) return 0 ;;
  esac

  awk -v target="$_jtpd_num" '
    BEGIN { in_matrix = 0; in_flow = 0; n_edges = 0 }
    /^## Matriz de Dependencias/ { in_matrix = 1; next }
    in_matrix && /^## / { in_matrix = 0 }
    in_matrix && $0 ~ /^```mermaid/ { in_flow = 1; next }
    in_matrix && in_flow && $0 ~ /^```/ { in_flow = 0; next }
    in_flow && match($0, /^[ \t]*F[0-9]+\[[^]]*\]/) {
      seg = substr($0, RSTART, RLENGTH)
      idend = index(seg, "[")
      id = substr(seg, 1, idend - 1)
      gsub(/[ \t]/, "", id)
      label = substr(seg, idend + 1, length(seg) - idend - 1)
      node_label[id] = label
      next
    }
    in_flow && match($0, /^[ \t]*F[0-9]+[ \t]*-->[ \t]*F[0-9]+/) {
      seg = substr($0, RSTART, RLENGTH)
      arrow = index(seg, "-->")
      from = substr(seg, 1, arrow - 1)
      to = substr(seg, arrow + 3)
      gsub(/[ \t]/, "", from)
      gsub(/[ \t]/, "", to)
      n_edges++
      edge_from[n_edges] = from
      edge_to[n_edges] = to
      next
    }
    END {
      wanted = "F" target
      for (i = 1; i <= n_edges; i++) {
        if (edge_to[i] == wanted && (edge_from[i] in node_label)) {
          print node_label[edge_from[i]]
        }
      }
    }
  ' "$_jtpd_tasks_file"
}

# _jt_cmd_phase_edges --feature F — r02 FASE 18 tarefa 18.3.1 (data-model.md
# Entity IssueLink; research.md Decision R2-6): imprime uma linha `A<TAB>B`
# (numeros PUROS, sem "FASE") por aresta `FA --> FB` da secao "## Matriz de
# Dependencias" — mesmo parser mermaid de `_jt_cmd_phase_deps`, mas sem
# filtrar por FASE-alvo (todas as arestas de uma vez). Sem secao/arestas:
# stdout vazio, exit 0.
_jt_cmd_phase_edges() {
  _jtpe_feature=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _jt_die_usage "--feature requer valor"
        _jtpe_feature="$2"
        shift 2
        ;;
      *)
        _jt_die_usage "argumento desconhecido: $1"
        ;;
    esac
  done

  [ -n "$_jtpe_feature" ] || _jt_die_usage "phase-edges requer --feature F"
  _jt_is_safe_feature "$_jtpe_feature" \
    || _jt_die_usage "--feature invalido (charset [A-Za-z0-9_-]): '$_jtpe_feature'"

  _jtpe_tasks_file="./docs/specs/$_jtpe_feature/tasks.md"
  [ -f "$_jtpe_tasks_file" ] || _jt_die "tasks.md nao encontrado: $_jtpe_tasks_file" 1

  awk '
    BEGIN { in_matrix = 0; in_flow = 0 }
    /^## Matriz de Dependencias/ { in_matrix = 1; next }
    in_matrix && /^## / { in_matrix = 0 }
    in_matrix && $0 ~ /^```mermaid/ { in_flow = 1; next }
    in_matrix && in_flow && $0 ~ /^```/ { in_flow = 0; next }
    in_flow && match($0, /^[ \t]*F[0-9]+[ \t]*-->[ \t]*F[0-9]+/) {
      seg = substr($0, RSTART, RLENGTH)
      arrow = index(seg, "-->")
      from = substr(seg, 1, arrow - 1)
      to = substr(seg, arrow + 3)
      gsub(/[ \t]/, "", from)
      gsub(/[ \t]/, "", to)
      sub(/^F/, "", from)
      sub(/^F/, "", to)
      print from "\t" to
    }
  ' "$_jtpe_tasks_file"
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
  phase-deps)
    _jt_cmd_phase_deps "$@"
    ;;
  phase-edges)
    _jt_cmd_phase_edges "$@"
    ;;
  *)
    _jt_die_usage "subcomando desconhecido: $_jt_sub (validos: items, phase-deps, phase-edges)"
    ;;
esac
