#!/bin/sh
# jira-sync.sh — motor de sincronizacao do plugin cstk-jira: converte uma
# feature local (spec + tasks.md) em Epic > Task > Sub-task no Jira Cloud e
# (fases futuras) drena o outbox de mudancas de estado (cstk-jira, FASE 4
# tarefa 4.1 "plan/convert").
#
# Ref: docs/specs/cstk-jira/spec.md US1; docs/specs/cstk-jira/plan.md fluxo 2
#      "Convert"; docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-sync.sh`; docs/specs/cstk-jira/contracts/jira-rest.md R1 (criar
#      issue) + nota "Resolucao do project.id"; data-model.md Entity
#      LocalWorkItem/SyncMapping; tasks.md 4.1.1-4.1.7.
#
# ESCOPO ATE AGORA (tarefas 4.1 + 4.2 parcial): `plan`/`convert` (US1, FASE
# 4.1 completa) e `enqueue`/`drain` (US3, FASE 4.2 PARCIAL — 4.2.1/4.2.2/
# 4.2.6/4.2.8). `status`/`resolve`/`relink` sao FASE 4.3, fora do escopo.
#
# `drain` NAO implementa ainda deteccao de conflito (4.2.3/4.2.4, SyncMarker
# via R6) nem transicao de status (4.2.5, R4): o corpo de resposta de
# `GET .../properties/{propertyKey}` (R6) NAO tem confirmacao de roundtrip
# real em `contracts/jira-rest.md` (so os LIMITES de tamanho da propriedade
# estao CONFIRMADO; o shape exato da resposta segue sem fonte citavel) — por
# Principio VI (Zero Fabricacao) o motor nao decide esse shape sem uma fonte
# (roundtrip real ou doc oficial explicito). Eventos `queued` permanecem na
# fila (proximo `drain` os reconsidera); nenhuma chamada de rede e feita para
# eles nesta tarefa. Serializacao de escritas por issue (4.2.7, rate limit)
# tambem fica para quando a transicao real existir.
#
# Subcomandos:
#
#   jira-sync.sh plan --feature F
#       — Dry-run: projeta `jira-tasks.sh items --feature F` contra
#         `docs/specs/F/jira-map.tsv` (se existir) e imprime em stdout, uma
#         linha TSV por item:
#             action  kind  local_key  jira_key  detail
#         `action` em `create` (local_key ausente do mapeamento — seria
#         criado por `convert`), `update` (mapeado `active`; `detail` traz
#         `target_status=<status Jira mapeado de ProjectConfig>`, projetado
#         SOMENTE a partir do `local_state` local — nao consulta o Jira, ver
#         nota de escopo abaixo) ou `orphan` (mapeado `active` mas ausente de
#         `tasks.md`, OU ja marcado `orphan` no arquivo — nunca reescreve o
#         arquivo; quem materializa a marca e `jira-map.sh mark-orphans`).
#         Termina com uma linha `conflicts n-a - - <nota>`: deteccao real de
#         conflito (SyncMarker vs. estado remoto) exige leitura de entity
#         property (R6) e e responsabilidade de `drain` (FASE 4.2, ainda nao
#         implementada nesta tarefa) — `plan` nunca inventa um veredito de
#         conflito sem essa fonte (Principio VI).
#         NENHUMA escrita (nem `jira-map.tsv`, nem rede) — so requer
#         `jira-config.sh`/`jira-tasks.sh`/`jira-map.sh` (POSIX puro, sem
#         `jq`/cliente HTTP).
#         Pre-condicao: `jira-config.sh validate` (propaga exit 3 se
#         ProjectConfig ausente, exit 1 se invalido).
#
#   jira-sync.sh convert --feature F
#       — US1: cria Epic (se ausente do mapeamento), depois cada Task
#         (`parent`=Epic), depois cada Sub-task da Task (`parent`=Task),
#         gravando `jira-map.tsv` IMEDIATAMENTE apos cada resposta de
#         criacao (4.1.3) — antes de processar o proximo item. Reexecucao:
#         busca por presenca no mapeamento (NUNCA por titulo/JQL); item ja
#         mapeado (`active` OU `orphan`) e pulado sem nenhuma chamada de
#         criacao (FR-014, SC-002).
#         Pre-condicoes COMPLETAS antes da 1a escrita (US1 cenario 3):
#           1. `jira-io.sh deps-check`        (jq + cliente HTTP no PATH)
#           2. `jira-config.sh validate`      (ProjectConfig completo)
#           3. `jira-config.sh credential-check` (arquivo 0600 presente)
#           4. `GET /rest/api/3/myself`       (credencial aceita pelo Jira)
#         Qualquer uma falhando aborta ANTES de tocar `jira-map.tsv` — nao
#         ha caminho de codigo entre essas 4 checagens e a 1a criacao.
#         Resolucao de `fields.project.id`: ProjectConfig so guarda
#         `project_key` (nao `project_id` — data-model.md nao define esse
#         campo); o corpo de R1 exige `id` (unica forma confirmada em
#         roundtrip real — `contracts/jira-rest.md` R1). Por isso `convert`
#         resolve o id UMA VEZ por execucao via `GET /rest/api/3/project/
#         {project_key}` (mesmo endpoint citado em `contracts/jira-rest.md`
#         logo apos R1, "Resolucao do project.id") — nunca supoe/cacheia o
#         valor num campo de config inexistente.
#         Corpo de cada issue via `jira-io.sh json-build issue` (SEC-3:
#         summary/titulo sempre via `jq --arg`, nunca concatenacao); ids/
#         keys sempre validados pela allowlist SEC-1 antes de qualquer
#         interpolacao (delegado a `json-build`/`request`, que ja recusam
#         valor fora do charset).
#         Titulo (`fields.summary`): Epic usa o titulo tal-e-qual; Task usa
#         `[FASE N] N.M <titulo>` (data-model.md, campos phase+local_key+
#         title ja saem separados de `jira-tasks.sh items` — este script e o
#         responsavel por compor a string final); Sub-task usa o titulo
#         tal-e-qual (data-model.md nao especifica prefixo para sub-task).
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral; 2 uso incorreto; 3
#   ProjectConfig ausente (propagado); 4 credencial ausente/incompleta/
#   auth_failed (propagado); 5 dependencia ausente (propagado, so em
#   `convert`).
#
# Este arquivo NUNCA invoca `jq`/cliente HTTP diretamente — todo acesso a
# rede ou a JSON passa por `jira-io.sh` (unico ponto autorizado, carve-out
# 1.1.0 / Principio II).

set -eu

_JS_NAME="jira-sync"

_js_die_usage() { printf '%s: %s\n' "$_JS_NAME" "$1" >&2; exit 2; }
_js_die()       { printf '%s: %s\n' "$_JS_NAME" "$1" >&2; exit "${2:-1}"; }

_js_usage() {
  cat <<'HELP'
jira-sync.sh — motor de sincronizacao local<->Jira do plugin cstk-jira

USO:
  jira-sync.sh plan --feature F
      Dry-run local (sem rede/escrita): lista create/update/orphan
      previstos + nota sobre conflitos (deteccao completa em `drain`).

  jira-sync.sh convert --feature F
      Cria Epic/Task/Sub-task no Jira (US1), gravando jira-map.tsv item a
      item; idempotente por presenca no mapeamento (FR-013/FR-014).

  jira-sync.sh enqueue --feature F --local-key K --state S --source SRC
      Acrescenta um OutboxEvent (append-only) em
      <cwd>/.claude/cstk-jira/runtime/outbox.tsv. S em pending/in_progress/
      pass/fail/reconcile; SRC em hook-record-task/hook-close-wave/manual.

  jira-sync.sh drain --feature F
      Processa o outbox da feature sob lock proprio (`runtime/.drain.lock/`,
      `mkdir` atomico — lock ocupado: sai exit 0 sem processar). Compacta
      eventos `done`; se houver QUALQUER evento `auth_failed` da feature, nao
      faz nenhuma chamada nova (FR-016). Deteccao de conflito/transicao real
      (SyncMarker/R4/R6) ainda NAO implementada nesta tarefa (ver nota de
      escopo no topo do arquivo) — eventos `queued` permanecem na fila.

Le <cwd>/docs/specs/F/tasks.md (+ spec.md) e <cwd>/docs/specs/F/jira-map.tsv.

EXIT CODES:
  0 sucesso   1 erro geral   2 uso incorreto   3 ProjectConfig ausente
  4 credencial ausente/incompleta/auth_failed   5 dependencia ausente (convert)
HELP
}

# _js_is_safe_feature VALUE -> mesma allowlist de path dos scripts irmaos
# (jira-tasks.sh/jira-map.sh): charset [A-Za-z0-9_-], nao-vazio.
_js_is_safe_feature() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# Newline literal — mesmo padrao/motivo de jira-map.sh _JM_NL (deteccao de
# injecao de linha via argumento; "$(printf '\n')" descarta o \n final e
# quebraria o case abaixo).
_JS_NL='
'

# _js_is_safe_field VALUE -> nao-vazio e sem TAB/newline (protege a
# integridade de linha/coluna do outbox.tsv contra injecao via argumento —
# mesma funcao de jira-map.sh _jm_is_safe_field, duplicada aqui porque
# jira-sync.sh nao importa funcoes de jira-map.sh, so o invoca como binario).
_js_is_safe_field() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *"$(printf '\t')"*) return 1 ;;
  esac
  case "$1" in
    *"$_JS_NL"*) return 1 ;;
  esac
  return 0
}

# Entity OutboxEvent (data-model.md) — fila local de sync, append-only com
# compactacao no drain (4.2.8). Arquivo compartilhado entre features (coluna
# `feature` filtra); lock de drain e GLOBAL ao projeto (contracts/hooks.md
# "Drenar": escritas serializadas por um unico `runtime/.drain.lock/`).
_JS_OUTBOX_FILE="./.claude/cstk-jira/runtime/outbox.tsv"
_JS_OUTBOX_HEADER='event_id	created_at	feature	local_key	desired_state	source	attempts	status'
_JS_DRAIN_LOCK_DIR="./.claude/cstk-jira/runtime/.drain.lock"

# _js_script_dir -> diretorio deste script (para localizar os irmaos
# jira-config.sh/jira-tasks.sh/jira-map.sh/jira-io.sh — mesmo padrao de
# _jt_script_dir/_jm_script_dir/_ji_script_dir).
_js_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

_js_parse_feature_arg() {
  _jspf_feature=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _js_die_usage "--feature requer valor"
        _jspf_feature="$2"
        shift 2
        ;;
      *)
        _js_die_usage "argumento desconhecido: $1"
        ;;
    esac
  done
  [ -n "$_jspf_feature" ] || _js_die_usage "requer --feature F"
  _js_is_safe_feature "$_jspf_feature" \
    || _js_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jspf_feature"
  printf '%s' "$_jspf_feature"
}

# --- plan ------------------------------------------------------------------

_js_cmd_plan() {
  _jsp_feature=$(_js_parse_feature_arg "$@")

  _jsp_dir="$(_js_script_dir)"
  _jsp_config="$_jsp_dir/jira-config.sh"
  _jsp_tasks="$_jsp_dir/jira-tasks.sh"
  _jsp_map="$_jsp_dir/jira-map.sh"

  # Pre-condicao: ProjectConfig valido (propaga exit 3 ausente / exit 1
  # invalido). plan NUNCA exige jq/cliente HTTP (so consulta local).
  "$_jsp_config" validate

  _jsp_status_pending=$("$_jsp_config" get status_pending)
  _jsp_status_in_progress=$("$_jsp_config" get status_in_progress)
  _jsp_status_pass=$("$_jsp_config" get status_pass)
  _jsp_status_fail=$("$_jsp_config" get status_fail)

  _jsp_items=$("$_jsp_tasks" items --feature "$_jsp_feature") \
    || _js_die "jira-tasks.sh items falhou para a feature: $_jsp_feature" 1

  _jsp_map_file="./docs/specs/$_jsp_feature/jira-map.tsv"

  printf '%s\n' "$_jsp_items" | while IFS= read -r _jsp_line; do
    [ -n "$_jsp_line" ] || continue
    _jsp_key=$(printf '%s' "$_jsp_line" | cut -f1)
    _jsp_kind=$(printf '%s' "$_jsp_line" | cut -f2)
    _jsp_state=$(printf '%s' "$_jsp_line" | cut -f5)
    _jsp_title=$(printf '%s' "$_jsp_line" | cut -f6)

    if _jsp_mline=$("$_jsp_map" get --feature "$_jsp_feature" --local-key "$_jsp_key" 2>/dev/null); then
      _jsp_jkey=$(printf '%s' "$_jsp_mline" | cut -f4)
      _jsp_mstate=$(printf '%s' "$_jsp_mline" | cut -f5)
      if [ "$_jsp_mstate" = "orphan" ]; then
        printf 'orphan\t%s\t%s\t%s\tja-marcado-orphan-relink-pendente\n' \
          "$_jsp_kind" "$_jsp_key" "$_jsp_jkey"
        continue
      fi
      case "$_jsp_state" in
        pending)     _jsp_target="$_jsp_status_pending" ;;
        in_progress) _jsp_target="$_jsp_status_in_progress" ;;
        pass)        _jsp_target="$_jsp_status_pass" ;;
        fail)        _jsp_target="$_jsp_status_fail" ;;
        *)           _jsp_target="desconhecido" ;;
      esac
      printf 'update\t%s\t%s\t%s\ttarget_status=%s (projetado do local_state; nao consulta o Jira)\n' \
        "$_jsp_kind" "$_jsp_key" "$_jsp_jkey" "$_jsp_target"
    else
      printf 'create\t%s\t%s\t-\t%s\n' "$_jsp_kind" "$_jsp_key" "$_jsp_title"
    fi
  done

  # Orfaos: chaves active no mapeamento ausentes de tasks.md — leitura pura
  # (NUNCA invoca jira-map.sh mark-orphans, que reescreveria o arquivo).
  if [ -f "$_jsp_map_file" ]; then
    _jsp_keys_tmp=$(mktemp "${TMPDIR:-/tmp}/jira-sync-keys.XXXXXX") \
      || _js_die "falha ao criar arquivo temporario" 1
    printf '%s\n' "$_jsp_items" | cut -f1 > "$_jsp_keys_tmp"
    awk -F '\t' -v keysfile="$_jsp_keys_tmp" '
      BEGIN { while ((getline k < keysfile) > 0) keep[k] = 1; close(keysfile) }
      NR > 1 && $5 == "active" && !($1 in keep) {
        print "orphan\t" $2 "\t" $1 "\t" $4 "\tactive-no-mapeamento-mas-ausente-de-tasks.md"
      }
      NR > 1 && $5 == "orphan" && !($1 in keep) {
        print "orphan\t" $2 "\t" $1 "\t" $4 "\tja-marcado-orphan-relink-pendente"
      }
    ' "$_jsp_map_file"
    rm -f "$_jsp_keys_tmp"
  fi

  printf 'conflicts\tn-a\t-\t-\tdeteccao completa (SyncMarker/R6) e responsabilidade de jira-sync.sh drain (FASE 4.2)\n'
}

# --- convert -----------------------------------------------------------------

_js_cmd_convert() {
  _jsc_feature=$(_js_parse_feature_arg "$@")

  _jsc_dir="$(_js_script_dir)"
  _jsc_config="$_jsc_dir/jira-config.sh"
  _jsc_tasks="$_jsc_dir/jira-tasks.sh"
  _jsc_map="$_jsc_dir/jira-map.sh"
  _jsc_io="$_jsc_dir/jira-io.sh"

  # Pre-condicoes COMPLETAS (US1 cenario 3) — cada uma e um comando simples
  # sob 'set -e': falha aqui aborta o script INTEIRO com o MESMO exit code
  # do subcomando delegado, antes de tocar jira-map.tsv.
  "$_jsc_io" deps-check
  "$_jsc_config" validate
  "$_jsc_config" credential-check
  "$_jsc_io" request GET /rest/api/3/myself >/dev/null

  _jsc_project_key=$("$_jsc_config" get project_key)
  "$_jsc_io" validate-segment "$_jsc_project_key"
  _jsc_project_resp=$("$_jsc_io" request GET "/rest/api/3/project/$_jsc_project_key" 2>/dev/null) \
    || _js_die "falha ao resolver project.id via GET /rest/api/3/project/$_jsc_project_key" 1
  _jsc_project_id=$(printf '%s' "$_jsc_project_resp" | "$_jsc_io" json-get '.id')
  [ -n "$_jsc_project_id" ] || _js_die "resposta de GET project sem campo id" 1

  _jsc_issuetype_epic=$("$_jsc_config" get issue_type_epic)
  _jsc_issuetype_task=$("$_jsc_config" get issue_type_task)
  _jsc_issuetype_subtask=$("$_jsc_config" get issue_type_subtask)

  _jsc_items=$("$_jsc_tasks" items --feature "$_jsc_feature") \
    || _js_die "jira-tasks.sh items falhou para a feature: $_jsc_feature" 1

  _jsc_map_file="./docs/specs/$_jsc_feature/jira-map.tsv"
  _jsc_feature_dir=$(dirname -- "$_jsc_map_file")
  [ -d "$_jsc_feature_dir" ] || _js_die "diretorio da feature nao encontrado: $_jsc_feature_dir" 1

  printf '%s\n' "$_jsc_items" | while IFS= read -r _jsc_line; do
    [ -n "$_jsc_line" ] || continue
    _jsc_key=$(printf '%s' "$_jsc_line" | cut -f1)
    _jsc_kind=$(printf '%s' "$_jsc_line" | cut -f2)
    _jsc_phase=$(printf '%s' "$_jsc_line" | cut -f3)
    _jsc_title=$(printf '%s' "$_jsc_line" | cut -f6)

    # Idempotencia (FR-014/SC-002): local_key ja presente no mapeamento
    # (active OU orphan) -> pula, NENHUMA chamada de criacao.
    if "$_jsc_map" get --feature "$_jsc_feature" --local-key "$_jsc_key" >/dev/null 2>&1; then
      continue
    fi

    _jsc_parent_key=""
    case "$_jsc_kind" in
      epic)
        _jsc_issuetype_id="$_jsc_issuetype_epic"
        _jsc_summary="$_jsc_title"
        ;;
      task)
        _jsc_issuetype_id="$_jsc_issuetype_task"
        _jsc_epic_line=$("$_jsc_map" get --feature "$_jsc_feature" --local-key "$_jsc_feature") \
          || _js_die "Epic ainda nao mapeado ao tentar criar a task $_jsc_key (era esperado ja criado)" 1
        _jsc_parent_key=$(printf '%s' "$_jsc_epic_line" | cut -f4)
        _jsc_phase_tag=$(printf '%s' "$_jsc_phase" | awk '{print $1, $2}')
        _jsc_summary="[$_jsc_phase_tag] $_jsc_key $_jsc_title"
        ;;
      subtask)
        _jsc_issuetype_id="$_jsc_issuetype_subtask"
        _jsc_parent_local=${_jsc_key%.*}
        _jsc_parent_line=$("$_jsc_map" get --feature "$_jsc_feature" --local-key "$_jsc_parent_local") \
          || _js_die "Task pai ($_jsc_parent_local) ainda nao mapeada ao tentar criar a sub-task $_jsc_key" 1
        _jsc_parent_key=$(printf '%s' "$_jsc_parent_line" | cut -f4)
        _jsc_summary="$_jsc_title"
        ;;
      *)
        _js_die "kind desconhecido retornado por jira-tasks.sh items: $_jsc_kind" 1
        ;;
    esac

    if [ -n "$_jsc_parent_key" ]; then
      _jsc_body=$("$_jsc_io" json-build issue --project-id "$_jsc_project_id" \
        --issuetype-id "$_jsc_issuetype_id" --summary "$_jsc_summary" \
        --parent-key "$_jsc_parent_key")
    else
      _jsc_body=$("$_jsc_io" json-build issue --project-id "$_jsc_project_id" \
        --issuetype-id "$_jsc_issuetype_id" --summary "$_jsc_summary")
    fi

    _jsc_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-body.XXXXXX") \
      || _js_die "falha ao criar arquivo temporario de corpo da requisicao" 1
    printf '%s' "$_jsc_body" > "$_jsc_body_file"

    # Nota: NAO usar 'if ! _jsc_resp=$(...); then' aqui — o operador '!'
    # reescreve $? para o valor NEGADO (0/1) da condicao, mascarando o exit
    # code real de jira-io.sh dentro do 'then'. Usando 'if cmd; then ok;
    # else ...; fi' (sem negacao), o primeiro comando do 'else' ve o $?
    # genuino da falha.
    if _jsc_resp=$("$_jsc_io" request POST /rest/api/3/issue \
        --body-file "$_jsc_body_file" --op R1); then
      rm -f "$_jsc_body_file"
    else
      _jsc_ec=$?
      rm -f "$_jsc_body_file"
      _js_die "falha ao criar issue para $_jsc_key (jira-io.sh exit $_jsc_ec)" "$_jsc_ec"
    fi

    _jsc_new_id=$(printf '%s' "$_jsc_resp" | "$_jsc_io" json-get '.id')
    _jsc_new_key=$(printf '%s' "$_jsc_resp" | "$_jsc_io" json-get '.key')
    [ -n "$_jsc_new_id" ] && [ -n "$_jsc_new_key" ] \
      || _js_die "resposta de criacao sem id/key para $_jsc_key" 1

    "$_jsc_map" put --feature "$_jsc_feature" --local-key "$_jsc_key" \
      --kind "$_jsc_kind" --jira-id "$_jsc_new_id" --jira-key "$_jsc_new_key" \
      || _js_die "issue $_jsc_new_key criada no Jira mas falha ao gravar jira-map.tsv para $_jsc_key — religar manualmente (jira-map.sh put)" 1
  done
}

# --- enqueue -----------------------------------------------------------

# _js_cmd_enqueue --feature F --local-key K --state S --source SRC — 4.2.1
# (US3, FR-004/018): acrescenta um OutboxEvent (append-only) ao outbox
# compartilhado do projeto. S (desired_state) e SRC (source) sao enums
# fechados (data-model.md Entity OutboxEvent). local-key aceita `*`
# (data-model.md: "reconciliar a feature inteira"), so exige nao-vazio e
# ausencia de TAB/newline (mesma disciplina de jira-map.sh). Escrita atomica
# (arquivo temporario no mesmo diretorio + `mv`, mesmo padrao de
# jira-map.sh put). Imprime o `event_id` gerado em stdout.
_js_cmd_enqueue() {
  _jse_feature=""
  _jse_key=""
  _jse_state=""
  _jse_source=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _js_die_usage "--feature requer valor"
        _jse_feature="$2"; shift 2 ;;
      --local-key)
        [ "$#" -ge 2 ] || _js_die_usage "--local-key requer valor"
        _jse_key="$2"; shift 2 ;;
      --state)
        [ "$#" -ge 2 ] || _js_die_usage "--state requer valor"
        _jse_state="$2"; shift 2 ;;
      --source)
        [ "$#" -ge 2 ] || _js_die_usage "--source requer valor"
        _jse_source="$2"; shift 2 ;;
      *)
        _js_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jse_feature" ] || _js_die_usage "enqueue requer --feature F"
  _js_is_safe_feature "$_jse_feature" \
    || _js_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jse_feature"
  _js_is_safe_field "$_jse_key" \
    || _js_die_usage "enqueue requer --local-key K valido (nao-vazio, sem TAB/newline; aceita '*' para reconciliar a feature inteira)"

  case "$_jse_state" in
    pending|in_progress|pass|fail|reconcile) : ;;
    *) _js_die_usage "--state invalido: '$_jse_state' (validos: pending, in_progress, pass, fail, reconcile)" ;;
  esac
  case "$_jse_source" in
    hook-record-task|hook-close-wave|manual) : ;;
    *) _js_die_usage "--source invalido: '$_jse_source' (validos: hook-record-task, hook-close-wave, manual)" ;;
  esac

  _jse_dir=$(dirname -- "$_JS_OUTBOX_FILE")
  mkdir -p "$_jse_dir" || _js_die "falha ao criar diretorio do outbox: $_jse_dir" 1

  # seq: contador simples baseado no numero de linhas ja gravadas (so para
  # tornar event_id legivel/unico dentro do mesmo pid+segundo; NAO e usado
  # para nenhuma logica de idempotencia/lock — so o lock de drain serializa).
  _jse_seq=1
  if [ -f "$_JS_OUTBOX_FILE" ]; then
    _jse_seq=$(($(awk -F '\t' 'NR > 1' "$_JS_OUTBOX_FILE" | wc -l | tr -d ' ') + 1))
  fi
  _jse_event_id="$(date -u +%s)-$$-${_jse_seq}"
  _jse_created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  _jse_tmp="$_JS_OUTBOX_FILE.tmp.$$"
  {
    if [ -f "$_JS_OUTBOX_FILE" ]; then
      cat "$_JS_OUTBOX_FILE"
    else
      printf '%s\n' "$_JS_OUTBOX_HEADER"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t0\tqueued\n' \
      "$_jse_event_id" "$_jse_created_at" "$_jse_feature" "$_jse_key" \
      "$_jse_state" "$_jse_source"
  } > "$_jse_tmp"
  mv -- "$_jse_tmp" "$_JS_OUTBOX_FILE"

  printf '%s\n' "$_jse_event_id"
}

# --- drain ---------------------------------------------------------------

# _js_cmd_drain --feature F — 4.2.2/4.2.6/4.2.8 (US3, FR-004/005/016/018):
# processa o outbox da feature sob lock GLOBAL do projeto
# (`runtime/.drain.lock/`, `mkdir` atomico — contracts/hooks.md "Drenar").
# Lock ocupado: sai exit 0 IMEDIATAMENTE sem tocar o outbox (proximo
# gatilho de drain reprocessa). Sob o lock: compacta eventos `done` (4.2.8);
# se QUALQUER evento `auth_failed` da feature estiver presente, nao faz
# NENHUMA chamada nova (regra dura FR-016 — nunca repetir silenciosamente
# tentativas que falham) e sai. Deteccao de conflito (SyncMarker/R6) e
# transicao real (R4) SAO FASE 4.2.3-4.2.5, NAO implementadas aqui (ver nota
# de escopo no topo do arquivo — shape de resposta de R6 sem fonte citavel,
# Principio VI): eventos `queued` permanecem na fila.
_js_cmd_drain() {
  _jsd_feature=$(_js_parse_feature_arg "$@")

  _jsd_lock_parent=$(dirname -- "$_JS_DRAIN_LOCK_DIR")
  mkdir -p "$_jsd_lock_parent" || _js_die "falha ao criar diretorio runtime: $_jsd_lock_parent" 1

  if ! mkdir "$_JS_DRAIN_LOCK_DIR" 2>/dev/null; then
    # 4.2.2: lock ocupado -> outro drain em andamento. Sai sem erro; o
    # proximo gatilho (hook/skill) drena os eventos pendentes.
    exit 0
  fi
  trap 'rmdir -- "$_JS_DRAIN_LOCK_DIR" 2>/dev/null || :' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  [ -f "$_JS_OUTBOX_FILE" ] || exit 0

  # 4.2.8: compactacao — remove eventos `done` (o outbox nao cresce
  # indefinidamente). Rewrite atomico (tmp no mesmo diretorio + mv).
  _jsd_tmp="$_JS_OUTBOX_FILE.tmp.$$"
  awk -F '\t' -v OFS='\t' '
    NR == 1 { print; next }
    $8 != "done" { print }
  ' "$_JS_OUTBOX_FILE" > "$_jsd_tmp"
  mv -- "$_jsd_tmp" "$_JS_OUTBOX_FILE"

  # 4.2.6: regra dura — qualquer evento auth_failed presente PARA ESTA
  # FEATURE bloqueia toda chamada nova ate reconfiguracao (jira-setup).
  _jsd_auth_failed=$(awk -F '\t' -v f="$_jsd_feature" \
    'NR > 1 && $3 == f && $8 == "auth_failed" { print; exit }' "$_JS_OUTBOX_FILE")
  if [ -n "$_jsd_auth_failed" ]; then
    printf '%s: evento auth_failed presente para a feature %s — nenhuma chamada nova ate reconfiguracao (FR-016)\n' \
      "$_JS_NAME" "$_jsd_feature" >&2
    exit 0
  fi

  _jsd_queued=$(awk -F '\t' -v f="$_jsd_feature" \
    'NR > 1 && $3 == f && $8 == "queued" { print $1 }' "$_JS_OUTBOX_FILE")
  if [ -n "$_jsd_queued" ]; then
    printf '%s: deteccao de conflito/transicao (R4/R6, tarefas 4.2.3-4.2.5) ainda nao implementada — eventos permanecem na fila: %s\n' \
      "$_JS_NAME" "$(printf '%s' "$_jsd_queued" | tr '\n' ' ')" >&2
  fi

  exit 0
}

# --- dispatcher ---------------------------------------------------------

_js_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_js_sub" in
  ''|-h|--help|help)
    _js_usage
    exit 0
    ;;
  plan)
    _js_cmd_plan "$@"
    ;;
  convert)
    _js_cmd_convert "$@"
    ;;
  enqueue)
    _js_cmd_enqueue "$@"
    ;;
  drain)
    _js_cmd_drain "$@"
    ;;
  *)
    _js_die_usage "subcomando desconhecido: $_js_sub (validos: plan, convert, enqueue, drain)"
    ;;
esac
