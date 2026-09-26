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
# ESCOPO ATE AGORA (FASE 4 completa): `plan`/`convert` (US1, 4.1), `enqueue`/
# `drain` (US3, 4.2) e `status`/`resolve` (4.3 — resolucao humana de
# ConflictRecord). `jira-map.sh mark-orphans`/`relink` (4.4) seguem sendo
# scripts irmaos invocados por `drain` (mark-orphans) e documentados aqui
# como caminho de UX para orfaos (`status` cita `relink`; `resolve` NUNCA
# religa — isso e exclusivo de `jira-map.sh relink`).
#
# `status [--feature F]` (4.3.1): resumo LOCAL (sem rede) do outbox
# (contagem por status + detalhe de `auth_failed`), dos `ConflictRecord`
# pendentes (`runtime/conflicts.tsv`) e dos cards `orphan` de cada
# `jira-map.tsv` (todas as features sob `docs/specs/*/` quando `--feature`
# e omitido). Nenhum campo exibido vem de uma chamada ao Jira — so TSVs
# locais ja escritos por `enqueue`/`drain`/`convert` — por isso nao ha
# conteudo a rotular como UNTRUSTED (nenhum titulo/texto do Jira e lido ou
# exibido por este subcomando; checklists/security.md CHK005 nao se aplica
# aqui, so as skills que efetivamente leem/exibem texto do Jira).
#
# `resolve --feature F --local-key K --choice keep_jira|overwrite|ignored`
# (4.3.2): fecha o `ConflictRecord` PENDENTE de (F, K) — resolucao e SEMPRE
# decisao humana, nunca automatica (data-model.md). `keep_jira`/`ignored` so
# atualizam a coluna `resolution` (nenhuma escrita no Jira, nenhum evento
# novo). `overwrite` reenfileira (via `enqueue`, mesma funcao interna) um
# NOVO `OutboxEvent` com o `desired_state` do ultimo evento `conflict`
# daquele par — o proximo `drain` tenta de novo e, sem novo conflito,
# sobrescreve o Jira com o estado local. Erro (exit 1) se nao existir
# ConflictRecord `pending` para o par informado — nunca inventa um.
#
# `drain` implementa deteccao de conflito (4.2.3/4.2.4, SyncMarker via R6) e
# transicao de status (4.2.5, R4) desde a onda-022 (dec-081 fechou o gap de
# R6 — `contracts/jira-rest.md` R6 confirma o envelope `{key,value}` por
# OpenAPI oficial + roundtrip real contra o Jira Cloud de teste). Para cada
# evento `queued`: le titulo+status atuais (R3) e o SyncMarker (R6 GET); se
# ausente (404, `marker_missing`) ou divergente (sha256 do titulo OU status,
# `manual_edit`) do que o plugin gravou por ultimo, gera `ConflictRecord`
# (`runtime/conflicts.tsv`) e NUNCA sobrescreve (FR-011). Sem conflito:
# resolve `transition.id` via R5, executa R4, regrava o SyncMarker via R6
# PUT. Serializacao de escritas por issue (4.2.7): o lock de drain e GLOBAL
# ao projeto (so um drain roda por vez em todo o projeto), o que ja impede 2
# escritas concorrentes em qualquer issue sem precisar de lock adicional
# por-issue. 4.4.1 (`mark-orphans` como parte do drain) tambem esta
# integrado aqui — ver `_js_cmd_drain`.
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
      Processa o outbox da feature sob lock GLOBAL do projeto
      (`runtime/.drain.lock/`, `mkdir` atomico — lock ocupado: sai exit 0
      sem processar). Compacta eventos `done`; roda `jira-map.sh
      mark-orphans` (4.4.1, pura leitura local); se houver QUALQUER evento
      `auth_failed` da feature, nao faz nenhuma chamada nova (FR-016).
      Para cada evento `queued`: detecta conflito via SyncMarker (R6) —
      `marker_missing`/`manual_edit` viram `ConflictRecord`
      (`runtime/conflicts.tsv`) e NUNCA sobrescrevem (FR-011); sem
      conflito, transiciona (R4/R5) e regrava o SyncMarker (R6 PUT).
      auth_failed em qualquer chamada real interrompe o processamento do
      restante do lote nesta chamada (credencial invalida vale para todas).

  jira-sync.sh status [--feature F]
      Resumo LOCAL (sem rede), legivel pelo operador: contagem do outbox
      por status (queued/deferred/conflict/auth_failed) + detalhe dos
      eventos auth_failed; ConflictRecord pendentes (runtime/conflicts.tsv);
      cards orphan de cada jira-map.tsv. Sem --feature, agrega TODAS as
      features sob docs/specs/*/.

  jira-sync.sh resolve --feature F --local-key K \
                        --choice keep_jira|overwrite|ignored
      Fecha um ConflictRecord PENDENTE por decisao SEMPRE humana (nunca
      automatica): keep_jira/ignored so fecham o registro (nenhuma escrita);
      overwrite reenfileira (enqueue) um novo evento com o desired_state do
      ultimo evento `conflict` daquele par, para o proximo drain sobrescrever
      o Jira. Exit 1 se nao existir ConflictRecord pendente para (F, K).

  Card orfao (task local removida/renumerada)? `resolve` NUNCA religa — use:
      jira-map.sh relink --feature F --local-key K --jira-key KEY
  para reativar o mapeamento por decisao humana explicita (CHK012).

Le <cwd>/docs/specs/F/tasks.md (+ spec.md) e <cwd>/docs/specs/F/jira-map.tsv.

EXIT CODES:
  0 sucesso   1 erro geral (inclui: resolve sem ConflictRecord pendente para
                             o par informado)
  2 uso incorreto   3 ProjectConfig ausente
  4 credencial ausente/incompleta/auth_failed   5 dependencia ausente
                                                 (convert; drain com eventos
                                                 queued exige jq/cliente
                                                 HTTP/sha256sum-shasum)
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

# Entity ConflictRecord (data-model.md) — nunca sobrescrito automaticamente;
# resolucao e SEMPRE decisao humana (jira-sync.sh resolve, FASE 4.3).
_JS_CONFLICTS_FILE="./.claude/cstk-jira/runtime/conflicts.tsv"
_JS_CONFLICTS_HEADER='detected_at	feature	local_key	jira_key	reason	resolution'

# Chave da entity property do SyncMarker (data-model.md) — DESIGN do
# plugin, nao dado externo.
_JS_MARKER_PROPERTY_KEY="cstk-jira.sync"

# _js_script_dir -> diretorio deste script (para localizar os irmaos
# jira-config.sh/jira-tasks.sh/jira-map.sh/jira-io.sh — mesmo padrao de
# _jt_script_dir/_jm_script_dir/_ji_script_dir).
_js_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

# _js_set_event_status EVENT_ID STATUS [ATTEMPTS] — 4.2.3-4.2.5: reescreve
# a linha do OutboxEvent (coluna 8, `status`; coluna 7, `attempts`, so se
# ATTEMPTS vier nao-vazio) via awk, tmp+mv atomico (mesmo padrao de
# compactacao 4.2.8). NUNCA remove linhas (isso e responsabilidade exclusiva
# da compactacao de eventos `done` no PROXIMO drain).
_js_set_event_status() {
  _jses_id="$1"
  _jses_status="$2"
  _jses_attempts="${3:-}"
  _jses_tmp="$_JS_OUTBOX_FILE.tmp.$$"
  awk -F '\t' -v OFS='\t' -v id="$_jses_id" -v st="$_jses_status" -v att="$_jses_attempts" '
    NR == 1 { print; next }
    $1 == id {
      if (att != "") { $7 = att }
      $8 = st
    }
    { print }
  ' "$_JS_OUTBOX_FILE" > "$_jses_tmp"
  mv -- "$_jses_tmp" "$_JS_OUTBOX_FILE"
}

# _js_conflict_pending_exists FEATURE LOCAL_KEY -> exit 0 se ja existe um
# ConflictRecord com resolution=pending para o mesmo par (evita duplicar o
# mesmo conflito a cada drain enquanto o operador nao resolve — FASE 4.3
# `resolve`).
_js_conflict_pending_exists() {
  [ -f "$_JS_CONFLICTS_FILE" ] || return 1
  awk -F '\t' -v f="$1" -v k="$2" \
    'NR > 1 && $2 == f && $3 == k && $6 == "pending" { found=1 } END { exit !found }' \
    "$_JS_CONFLICTS_FILE"
}

# _js_append_conflict FEATURE LOCAL_KEY JIRA_KEY REASON — grava um
# ConflictRecord (data-model.md), append-only, resolution inicial sempre
# `pending` (resolucao e SEMPRE decisao humana, FASE 4.3 `resolve`).
_js_append_conflict() {
  _jsac_dir=$(dirname -- "$_JS_CONFLICTS_FILE")
  mkdir -p "$_jsac_dir" || _js_die "falha ao criar diretorio runtime: $_jsac_dir" 1
  _jsac_tmp="$_JS_CONFLICTS_FILE.tmp.$$"
  {
    if [ -f "$_JS_CONFLICTS_FILE" ]; then
      cat "$_JS_CONFLICTS_FILE"
    else
      printf '%s\n' "$_JS_CONFLICTS_HEADER"
    fi
    printf '%s\t%s\t%s\t%s\t%s\tpending\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4"
  } > "$_jsac_tmp"
  mv -- "$_jsac_tmp" "$_JS_CONFLICTS_FILE"
}

# _js_conflict_row FEATURE LOCAL_KEY — imprime a linha TSV COMPLETA (6
# colunas) do ConflictRecord com resolution=pending para o par (F, K), ou
# nada se ausente (FASE 4.3 `resolve`/`status`). No maximo 1 linha esperada
# — `_js_conflict_pending_exists` impede um 2o `pending` para o mesmo par.
_js_conflict_row() {
  [ -f "$_JS_CONFLICTS_FILE" ] || return 0
  awk -F '\t' -v f="$1" -v k="$2" \
    'NR > 1 && $2 == f && $3 == k && $6 == "pending" { print; exit }' \
    "$_JS_CONFLICTS_FILE"
}

# _js_close_conflict FEATURE LOCAL_KEY RESOLUTION — reescreve a coluna
# `resolution` (6) da linha `pending` de (F, K) para RESOLUTION, atomico
# (tmp + mv, mesmo padrao de `_js_set_event_status`). Retorna 1 (sem
# escrever nada) se nenhuma linha `pending` casar — chamador MUST tratar
# como erro, nunca inventar um fechamento (FASE 4.3 `resolve`).
_js_close_conflict() {
  _jscc_tmp="$_JS_CONFLICTS_FILE.tmp.$$"
  if awk -F '\t' -v OFS='\t' -v f="$1" -v k="$2" -v res="$3" '
       NR == 1 { print; next }
       $2 == f && $3 == k && $6 == "pending" { $6 = res; matched = 1 }
       { print }
       END { exit (matched ? 0 : 1) }
     ' "$_JS_CONFLICTS_FILE" > "$_jscc_tmp"; then
    mv -- "$_jscc_tmp" "$_JS_CONFLICTS_FILE"
    return 0
  fi
  rm -f "$_jscc_tmp"
  return 1
}

# _js_last_conflict_desired_state FEATURE LOCAL_KEY — imprime o
# `desired_state` do evento outbox `conflict` MAIS RECENTE (ultima ocorrencia
# na ordem do arquivo) para (F, K); retorna 1 se nenhum existir. Usado por
# `resolve --choice overwrite` (FASE 4.3.2) para reenfileirar o MESMO estado
# desejado que originou o conflito — nunca inventa um valor novo (Principio
# VI: sem fonte, sem escrita).
_js_last_conflict_desired_state() {
  [ -f "$_JS_OUTBOX_FILE" ] || return 1
  awk -F '\t' -v f="$1" -v k="$2" '
    NR > 1 && $3 == f && $4 == k && $8 == "conflict" { ds = $5 }
    END { if (ds != "") { print ds; exit 0 } exit 1 }
  ' "$_JS_OUTBOX_FILE"
}

# _js_orphan_rows [FEATURE] — imprime `feature\tlocal_key\tjira_key` para
# toda linha state=orphan de docs/specs/<feature>/jira-map.tsv; sem FEATURE,
# varre TODAS as features sob docs/specs/*/ (FASE 4.3.1 `status`). Leitura
# pura (nunca reescreve jira-map.tsv — isso e exclusivo de `jira-map.sh
# mark-orphans`/`relink`).
_js_orphan_rows() {
  _jso_filter="${1:-}"
  for _jso_mf in ./docs/specs/*/jira-map.tsv; do
    [ -f "$_jso_mf" ] || continue
    _jso_feat=$(basename "$(dirname -- "$_jso_mf")")
    if [ -n "$_jso_filter" ] && [ "$_jso_feat" != "$_jso_filter" ]; then
      continue
    fi
    awk -F '\t' -v feat="$_jso_feat" \
      'NR > 1 && $5 == "orphan" { print feat "\t" $1 "\t" $4 }' \
      "$_jso_mf"
  done
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
  _jsc_title_sh="$_jsc_dir/jira-title.sh"

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
        _jsc_summary=$("$_jsc_title_sh" compose --kind epic --title "$_jsc_title")
        ;;
      task)
        _jsc_issuetype_id="$_jsc_issuetype_task"
        _jsc_epic_line=$("$_jsc_map" get --feature "$_jsc_feature" --local-key "$_jsc_feature") \
          || _js_die "Epic ainda nao mapeado ao tentar criar a task $_jsc_key (era esperado ja criado)" 1
        _jsc_parent_key=$(printf '%s' "$_jsc_epic_line" | cut -f4)
        _jsc_summary=$("$_jsc_title_sh" compose --kind task --phase "$_jsc_phase" \
          --local-key "$_jsc_key" --title "$_jsc_title")
        ;;
      subtask)
        _jsc_issuetype_id="$_jsc_issuetype_subtask"
        _jsc_parent_local=${_jsc_key%.*}
        _jsc_parent_line=$("$_jsc_map" get --feature "$_jsc_feature" --local-key "$_jsc_parent_local") \
          || _js_die "Task pai ($_jsc_parent_local) ainda nao mapeada ao tentar criar a sub-task $_jsc_key" 1
        _jsc_parent_key=$(printf '%s' "$_jsc_parent_line" | cut -f4)
        _jsc_summary=$("$_jsc_title_sh" compose --kind subtask --title "$_jsc_title")
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

# _js_process_one_event ROW — 4.2.3/4.2.4/4.2.5 (US3, FR-004/005/011/018,
# resolve dec-079/dec-081): processa UM OutboxEvent `queued` ja lido em ROW
# (linha TSV completa do outbox). Le titulo+status atuais da issue (R3) e o
# SyncMarker (R6, `contracts/jira-rest.md` R6 — envelope `{key,value}`
# confirmado por OpenAPI + roundtrip onda-022); se ausente (404) ou
# divergente do que o plugin gravou por ultimo (sha256 do titulo OU status),
# gera ConflictRecord e NAO escreve (FR-011 — nunca sobrescreve
# silenciosamente). Sem conflito: resolve `transition.id` via R5 comparando
# `to.name` ao status alvo (ProjectConfig `status_*`), executa R4, regrava o
# SyncMarker via R6 PUT (overwrite total do `value`, `contracts/jira-rest.md`
# R6 — nao e merge). Serializacao de escritas (4.2.7): o lock de drain e
# GLOBAL ao projeto (`_JS_DRAIN_LOCK_DIR`, `_js_cmd_drain` abaixo) — so um
# processo de drain roda por vez em todo o projeto, o que ja impede 2
# escritas concorrentes na MESMA issue (ou em qualquer issue) sem precisar de
# serializacao adicional por-issue.
# Efeitos colaterais: reescreve o status do evento em `_JS_OUTBOX_FILE` via
# `_js_set_event_status`; pode gravar `_JS_CONFLICTS_FILE`. Retorna (via
# `_JSPE_BREAK`) `yes` quando o chamador MUST parar de processar novos
# eventos nesta chamada de drain (auth_failed — credencial invalida para
# TODAS as chamadas subsequentes, nao so para este evento).
_js_process_one_event() {
  _jspe_row="$1"
  _JSPE_BREAK="no"

  _jspe_eid=$(printf '%s' "$_jspe_row" | cut -f1)
  _jspe_lkey=$(printf '%s' "$_jspe_row" | cut -f4)
  _jspe_dstate=$(printf '%s' "$_jspe_row" | cut -f5)
  _jspe_attempts=$(printf '%s' "$_jspe_row" | cut -f7)

  if [ "$_jspe_lkey" = "*" ]; then
    printf '%s: reconciliacao de feature inteira (local_key=*) ainda nao implementada (FASE 4.2, fora desta tarefa) — evento %s permanece na fila\n' \
      "$_JS_NAME" "$_jspe_eid" >&2
    return 0
  fi

  if ! _jspe_mline=$("$_jsd_map" get --feature "$_jsd_feature" --local-key "$_jspe_lkey" 2>/dev/null); then
    printf '%s: local_key %s sem mapeamento — evento %s permanece na fila\n' \
      "$_JS_NAME" "$_jspe_lkey" "$_jspe_eid" >&2
    return 0
  fi
  _jspe_jkey=$(printf '%s' "$_jspe_mline" | cut -f4)
  _jspe_mstate=$(printf '%s' "$_jspe_mline" | cut -f5)

  # 4.4 (FR-012): orfao nunca e sobrescrito — vira ConflictRecord
  # (reason=orphan) ate o operador religar (jira-map.sh relink).
  if [ "$_jspe_mstate" = "orphan" ]; then
    _js_conflict_pending_exists "$_jsd_feature" "$_jspe_lkey" \
      || _js_append_conflict "$_jsd_feature" "$_jspe_lkey" "$_jspe_jkey" orphan
    _js_set_event_status "$_jspe_eid" conflict
    return 0
  fi

  case "$_jspe_dstate" in
    pending)     _jspe_target="$_jsd_status_pending" ;;
    in_progress) _jspe_target="$_jsd_status_in_progress" ;;
    pass)        _jspe_target="$_jsd_status_pass" ;;
    fail)        _jspe_target="$_jsd_status_fail" ;;
    *)
      printf '%s: desired_state %s sem status alvo mapeado — evento %s permanece na fila\n' \
        "$_JS_NAME" "$_jspe_dstate" "$_jspe_eid" >&2
      return 0
      ;;
  esac

  # R3 — titulo + status atuais.
  if ! _jspe_issue_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspe_jkey?fields=summary,status" --op R3 2>/dev/null); then
    _jspe_ec=$?
    if [ "$_jspe_ec" -eq 4 ]; then
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    return 0
  fi
  _jspe_cur_summary=$(printf '%s' "$_jspe_issue_resp" | "$_jsd_io" json-get '.fields.summary')
  _jspe_cur_status=$(printf '%s' "$_jspe_issue_resp" | "$_jsd_io" json-get '.fields.status.name')
  _jspe_cur_sha=$(printf '%s' "$_jspe_cur_summary" | "$_jsd_io" sha256-stdin)

  # R6 GET — SyncMarker. 404 (marker_missing) passa por `request` como
  # sucesso (exit 0, corpo = erro do Jira, sem uso) — o unico jeito de
  # distinguir "marker ausente" de "marker presente" e ler o `http_status`
  # que `request` sempre emite em stderr (contrato ja documentado no
  # cabecalho de jira-io.sh, nao uma classificacao nova/inventada).
  _jspe_err_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6err.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  if _jspe_prop_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspe_jkey/properties/$_JS_MARKER_PROPERTY_KEY" --op R6 2>"$_jspe_err_file"); then
    _jspe_prop_ec=0
  else
    _jspe_prop_ec=$?
  fi
  _jspe_prop_status=$(grep '^http_status=' "$_jspe_err_file" | tail -n 1 | cut -d= -f2)
  rm -f "$_jspe_err_file"

  if [ "$_jspe_prop_ec" -ne 0 ]; then
    if [ "$_jspe_prop_ec" -eq 4 ]; then
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    return 0
  fi

  _jspe_conflict="no"
  _jspe_conflict_reason=""
  if [ "$_jspe_prop_status" = "404" ]; then
    _jspe_conflict="yes"
    _jspe_conflict_reason="marker_missing"
  else
    _jspe_written_sha=$(printf '%s' "$_jspe_prop_resp" | "$_jsd_io" json-get '.value.written_summary_sha256')
    _jspe_written_status=$(printf '%s' "$_jspe_prop_resp" | "$_jsd_io" json-get '.value.written_status')
    if [ "$_jspe_cur_sha" != "$_jspe_written_sha" ] || [ "$_jspe_cur_status" != "$_jspe_written_status" ]; then
      _jspe_conflict="yes"
      _jspe_conflict_reason="manual_edit"
    fi
  fi

  if [ "$_jspe_conflict" = "yes" ]; then
    _js_conflict_pending_exists "$_jsd_feature" "$_jspe_lkey" \
      || _js_append_conflict "$_jsd_feature" "$_jspe_lkey" "$_jspe_jkey" "$_jspe_conflict_reason"
    _js_set_event_status "$_jspe_eid" conflict
    return 0
  fi

  # Sem conflito, ja no status alvo: nada a transicionar; o SyncMarker ja
  # bate (sem conflito significa written_status == status atual == alvo).
  if [ "$_jspe_cur_status" = "$_jspe_target" ]; then
    _js_set_event_status "$_jspe_eid" "done"
    return 0
  fi

  # R5 — resolver transition.id cujo to.name bate o status alvo. Filtro FIXO
  # (nenhum texto livre entra no programa jq — SEC-3); o alvo e comparado
  # depois, em awk, via -v (dado, nao programa).
  if ! _jspe_trans_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspe_jkey/transitions" --op R5 2>/dev/null); then
    _jspe_ec=$?
    if [ "$_jspe_ec" -eq 4 ]; then
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    return 0
  fi
  _jspe_trans_tsv=$(printf '%s' "$_jspe_trans_resp" | "$_jsd_io" json-get '.transitions[] | [.id, .to.name] | @tsv')
  _jspe_trans_id=$(printf '%s\n' "$_jspe_trans_tsv" | awk -F '\t' -v want="$_jspe_target" '$2 == want { print $1; exit }')
  if [ -z "$_jspe_trans_id" ]; then
    printf '%s: nenhuma transicao disponivel para o status alvo "%s" na issue %s — evento %s permanece na fila (config de workflow?)\n' \
      "$_JS_NAME" "$_jspe_target" "$_jspe_jkey" "$_jspe_eid" >&2
    return 0
  fi

  # R4 — executar a transicao.
  _jspe_trans_body=$("$_jsd_io" json-build transition --transition-id "$_jspe_trans_id")
  _jspe_trans_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r4body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jspe_trans_body" > "$_jspe_trans_body_file"
  if "$_jsd_io" request POST "/rest/api/3/issue/$_jspe_jkey/transitions" \
      --body-file "$_jspe_trans_body_file" --op R4 >/dev/null 2>/dev/null; then
    rm -f "$_jspe_trans_body_file"
  else
    _jspe_ec=$?
    rm -f "$_jspe_trans_body_file"
    if [ "$_jspe_ec" -eq 4 ]; then
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    return 0
  fi

  # R6 PUT — regravar o SyncMarker com o novo written_summary_sha256/
  # written_status/written_at (titulo nao mudou nesta operacao — so o
  # status; o hash gravado e o do titulo ATUAL, que e o mesmo de antes).
  # Nota (limitacao conhecida, aceita nesta tarefa): se este PUT falhar
  # apos a transicao R4 ja ter sido aplicada, o evento fica `deferred` e o
  # PROXIMO drain repete a transicao inteira (R3/R6-get/R5/R4) — a issue ja
  # estara no status alvo, o que faria a deteccao de conflito comparar
  # status atual != written_status antigo e reportar `manual_edit`
  # indevidamente. Nao resolvido aqui (exigiria idempotencia mais fina);
  # aceito porque a janela e estreita (R6 PUT so falha por auth_failed/
  # deferred, ja raros) e o operador sempre pode `resolve --choice
  # keep_jira` para destravar (FASE 4.3).
  _jspe_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _jspe_marker_body=$("$_jsd_io" json-build marker --local-key "$_jspe_lkey" --feature "$_jsd_feature" \
    --written-summary-sha256 "$_jspe_cur_sha" --written-status "$_jspe_target" --written-at "$_jspe_now")
  _jspe_marker_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jspe_marker_body" > "$_jspe_marker_body_file"
  if "$_jsd_io" request PUT "/rest/api/3/issue/$_jspe_jkey/properties/$_JS_MARKER_PROPERTY_KEY" \
      --body-file "$_jspe_marker_body_file" --op R6 >/dev/null 2>/dev/null; then
    rm -f "$_jspe_marker_body_file"
    _js_set_event_status "$_jspe_eid" "done" "$((_jspe_attempts + 1))"
  else
    _jspe_ec=$?
    rm -f "$_jspe_marker_body_file"
    if [ "$_jspe_ec" -eq 4 ]; then
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
  fi
  return 0
}

# _js_cmd_drain --feature F — 4.2.2-4.2.8 (US3, FR-004/005/011/016/018):
# processa o outbox da feature sob lock GLOBAL do projeto
# (`runtime/.drain.lock/`, `mkdir` atomico — contracts/hooks.md "Drenar").
# Lock ocupado: sai exit 0 IMEDIATAMENTE sem tocar o outbox (proximo
# gatilho de drain reprocessa). Sob o lock, NESTA ORDEM: (1) compacta
# eventos `done` (4.2.8); (2) `jira-map.sh mark-orphans` (4.4.1 — pura
# leitura local de tasks.md + rewrite de estado, NUNCA rede, por isso roda
# mesmo quando o gate auth_failed abaixo bloquearia chamadas novas); (3)
# gate FR-016 — QUALQUER evento `auth_failed` da feature bloqueia toda
# chamada de rede nova ate reconfiguracao; (4) para cada evento `queued` da
# feature, `_js_process_one_event` (4.2.3-4.2.5 acima) — para na primeira
# ocorrencia de `auth_failed` (credencial invalida para TODAS as chamadas
# subsequentes, nao so para o evento corrente).
_js_cmd_drain() {
  _jsd_feature=$(_js_parse_feature_arg "$@")

  _jsd_dir="$(_js_script_dir)"
  _jsd_config="$_jsd_dir/jira-config.sh"
  _jsd_map="$_jsd_dir/jira-map.sh"
  _jsd_io="$_jsd_dir/jira-io.sh"
  _jsd_map_file="./docs/specs/$_jsd_feature/jira-map.tsv"

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

  # 4.4.1 — mark-orphans e pura leitura/rewrite LOCAL (nunca rede): roda
  # sempre que o mapeamento da feature existir, independente do resto do
  # outbox. `mark-orphans` sai 6 quando ha orfaos (informativo, nao erro) e
  # 1 se o mapeamento nao existir (ja coberto pelo `-f` abaixo) — nenhum dos
  # dois deve derrubar o drain.
  if [ -f "$_jsd_map_file" ]; then
    "$_jsd_map" mark-orphans --feature "$_jsd_feature" >/dev/null 2>&1 || :
  fi

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

  _jsd_queued_ids=$(awk -F '\t' -v f="$_jsd_feature" \
    'NR > 1 && $3 == f && $8 == "queued" { print $1 }' "$_JS_OUTBOX_FILE")
  [ -n "$_jsd_queued_ids" ] || exit 0

  # 4.2.3-4.2.5: ProjectConfig valido e um pre-requisito de TODO o lote (o
  # site/credencial/mapeamento de status sao os mesmos para todos os
  # eventos desta feature) — invalido/ausente => nenhum evento e tocado,
  # diagnostico em stderr, drain sai limpo (exit 0, mesma filosofia
  # fail-open de hook das demais falhas deste script).
  if ! "$_jsd_config" validate >/dev/null 2>&1; then
    printf '%s: ProjectConfig invalido/ausente — eventos permanecem na fila: %s\n' \
      "$_JS_NAME" "$(printf '%s' "$_jsd_queued_ids" | tr '\n' ' ')" >&2
    exit 0
  fi
  _jsd_status_pending=$("$_jsd_config" get status_pending)
  _jsd_status_in_progress=$("$_jsd_config" get status_in_progress)
  _jsd_status_pass=$("$_jsd_config" get status_pass)
  _jsd_status_fail=$("$_jsd_config" get status_fail)

  # Loop sobre um arquivo (nao um pipe) para os IDs: um `while read` num
  # pipe roda em subshell (POSIX) — inofensivo aqui porque cada iteracao so
  # PRECISA ler o outbox corrente (ja mutado pela iteracao anterior via
  # `_js_set_event_status`, que reescreve o arquivo diretamente, nao uma
  # copia em memoria).
  _jsd_ids_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-ids.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s\n' "$_jsd_queued_ids" > "$_jsd_ids_file"
  while IFS= read -r _jsd_eid; do
    [ -n "$_jsd_eid" ] || continue
    _jsd_row=$(awk -F '\t' -v id="$_jsd_eid" '$1 == id { print; exit }' "$_JS_OUTBOX_FILE")
    [ -n "$_jsd_row" ] || continue
    _js_process_one_event "$_jsd_row"
    if [ "$_JSPE_BREAK" = "yes" ]; then
      break
    fi
  done < "$_jsd_ids_file"
  rm -f "$_jsd_ids_file"

  exit 0
}

# --- status --------------------------------------------------------------

# _js_cmd_status [--feature F] — 4.3.1 (checklists/ux.md CHK011): resumo
# LOCAL (sem rede, sem jq/cliente HTTP) legivel pelo operador, agregando 3
# fontes: outbox (contagem por status + detalhe de auth_failed), conflitos
# PENDENTES (ConflictRecord) e cards orphan de cada jira-map.tsv. Sem
# --feature, agrega TODAS as features (outbox/conflicts filtram pela coluna
# `feature`; orfaos varrem docs/specs/*/). Nenhum texto lido do Jira e
# exibido aqui (so chaves/enums/timestamps ja gravados localmente) — por
# isso nao ha rotulo UNTRUSTED a aplicar (checklists/security.md CHK005 e
# escopo das skills que efetivamente leem/exibem titulo/descricao do Jira).
_js_cmd_status() {
  _jss_feature=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _js_die_usage "--feature requer valor"
        _jss_feature="$2"; shift 2 ;;
      *)
        _js_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  if [ -n "$_jss_feature" ]; then
    _js_is_safe_feature "$_jss_feature" \
      || _js_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jss_feature"
  fi

  if [ -n "$_jss_feature" ]; then
    printf '=== jira-sync status (feature=%s) ===\n' "$_jss_feature"
  else
    printf '=== jira-sync status (todas as features) ===\n'
  fi

  printf '\n-- Outbox (fila de eventos, runtime/outbox.tsv) --\n'
  if [ -f "$_JS_OUTBOX_FILE" ]; then
    _jss_q=$(awk -F '\t' -v f="$_jss_feature" 'NR>1 && (f=="" || $3==f) && $8=="queued"     { c++ } END { print c+0 }' "$_JS_OUTBOX_FILE")
    _jss_d=$(awk -F '\t' -v f="$_jss_feature" 'NR>1 && (f=="" || $3==f) && $8=="deferred"   { c++ } END { print c+0 }' "$_JS_OUTBOX_FILE")
    _jss_c=$(awk -F '\t' -v f="$_jss_feature" 'NR>1 && (f=="" || $3==f) && $8=="conflict"   { c++ } END { print c+0 }' "$_JS_OUTBOX_FILE")
    _jss_a=$(awk -F '\t' -v f="$_jss_feature" 'NR>1 && (f=="" || $3==f) && $8=="auth_failed"{ c++ } END { print c+0 }' "$_JS_OUTBOX_FILE")
    printf 'queued=%s deferred=%s conflict=%s auth_failed=%s\n' "$_jss_q" "$_jss_d" "$_jss_c" "$_jss_a"
    if [ "$_jss_a" != "0" ]; then
      printf '\nEventos auth_failed (drain bloqueado ate reconfigurar credencial — jira-setup, FR-016):\n'
      printf 'feature\tlocal_key\tevent_id\tattempts\n'
      awk -F '\t' -v f="$_jss_feature" \
        'NR>1 && (f=="" || $3==f) && $8=="auth_failed" { print $3 "\t" $4 "\t" $1 "\t" $7 }' \
        "$_JS_OUTBOX_FILE"
    fi
  else
    printf '(vazio — outbox.tsv nao existe)\n'
  fi

  printf '\n-- Conflitos pendentes (runtime/conflicts.tsv) --\n'
  if [ -f "$_JS_CONFLICTS_FILE" ]; then
    _jss_pending=$(awk -F '\t' -v f="$_jss_feature" 'NR>1 && (f=="" || $2==f) && $6=="pending" { c++ } END { print c+0 }' "$_JS_CONFLICTS_FILE")
    if [ "$_jss_pending" != "0" ]; then
      printf 'feature\tlocal_key\tjira_key\treason\tdetected_at\n'
      awk -F '\t' -v f="$_jss_feature" \
        'NR>1 && (f=="" || $2==f) && $6=="pending" { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $1 }' \
        "$_JS_CONFLICTS_FILE"
      printf '(resolver com: jira-sync.sh resolve --feature F --local-key K --choice keep_jira|overwrite|ignored)\n'
    else
      printf '(nenhum conflito pendente)\n'
    fi
  else
    printf '(nenhum — conflicts.tsv nao existe)\n'
  fi

  printf '\n-- Cards orfaos (jira-map.tsv state=orphan) --\n'
  _jss_orph_rows=$(_js_orphan_rows "$_jss_feature")
  if [ -n "$_jss_orph_rows" ]; then
    printf 'feature\tlocal_key\tjira_key\n'
    printf '%s\n' "$_jss_orph_rows"
    printf '(religar com: jira-map.sh relink --feature F --local-key K --jira-key KEY)\n'
  else
    printf '(nenhum)\n'
  fi
}

# --- resolve ---------------------------------------------------------------

# _js_cmd_resolve --feature F --local-key K --choice keep_jira|overwrite|
# ignored — 4.3.2 (data-model.md ConflictRecord, resolucao SEMPRE humana):
# fecha o ConflictRecord PENDENTE de (F, K). keep_jira/ignored so atualizam
# `resolution` (nenhuma escrita/enqueue); overwrite reenfileira (via
# `_js_cmd_enqueue`, mesma funcao interna usada pelo subcomando `enqueue`)
# um NOVO OutboxEvent com o desired_state do ultimo evento `conflict`
# daquele par — o proximo `drain` tenta de novo e, sem novo conflito,
# sobrescreve o Jira (contracts/plugin-scripts.md `resolve`). Erro (exit 1)
# se nao existir ConflictRecord pendente para o par — nunca fabrica um
# fechamento nem um desired_state (Principio VI).
_js_cmd_resolve() {
  _jsr_feature=""
  _jsr_key=""
  _jsr_choice=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _js_die_usage "--feature requer valor"
        _jsr_feature="$2"; shift 2 ;;
      --local-key)
        [ "$#" -ge 2 ] || _js_die_usage "--local-key requer valor"
        _jsr_key="$2"; shift 2 ;;
      --choice)
        [ "$#" -ge 2 ] || _js_die_usage "--choice requer valor"
        _jsr_choice="$2"; shift 2 ;;
      *)
        _js_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jsr_feature" ] || _js_die_usage "resolve requer --feature F"
  _js_is_safe_feature "$_jsr_feature" \
    || _js_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jsr_feature"
  _js_is_safe_field "$_jsr_key" \
    || _js_die_usage "resolve requer --local-key K valido (nao-vazio, sem TAB/newline)"
  case "$_jsr_choice" in
    keep_jira|overwrite|ignored) : ;;
    *) _js_die_usage "--choice invalido: '$_jsr_choice' (validos: keep_jira, overwrite, ignored)" ;;
  esac

  [ -f "$_JS_CONFLICTS_FILE" ] \
    || _js_die "nenhum ConflictRecord encontrado (conflicts.tsv nao existe) para feature=$_jsr_feature local_key=$_jsr_key" 1
  _jsr_row=$(_js_conflict_row "$_jsr_feature" "$_jsr_key")
  [ -n "$_jsr_row" ] \
    || _js_die "nenhum ConflictRecord PENDENTE para feature=$_jsr_feature local_key=$_jsr_key" 1
  _jsr_jkey=$(printf '%s' "$_jsr_row" | cut -f4)
  _jsr_reason=$(printf '%s' "$_jsr_row" | cut -f5)

  if [ "$_jsr_choice" = "overwrite" ]; then
    if ! _jsr_ds=$(_js_last_conflict_desired_state "$_jsr_feature" "$_jsr_key"); then
      _js_die "nao foi possivel determinar desired_state original para reenfileirar (nenhum evento outbox 'conflict' encontrado para feature=$_jsr_feature local_key=$_jsr_key)" 1
    fi
    _jsr_new_eid=$(_js_cmd_enqueue --feature "$_jsr_feature" --local-key "$_jsr_key" \
      --state "$_jsr_ds" --source manual)
  fi

  _js_close_conflict "$_jsr_feature" "$_jsr_key" "$_jsr_choice" \
    || _js_die "falha ao fechar ConflictRecord (corrida concorrente com outro drain/resolve?) para feature=$_jsr_feature local_key=$_jsr_key" 1

  case "$_jsr_choice" in
    overwrite)
      printf 'resolve: conflito fechado (feature=%s local_key=%s jira_key=%s reason=%s escolha=overwrite) — evento reenfileirado (event_id=%s desired_state=%s) para o proximo drain sobrescrever o Jira\n' \
        "$_jsr_feature" "$_jsr_key" "$_jsr_jkey" "$_jsr_reason" "$_jsr_new_eid" "$_jsr_ds"
      ;;
    keep_jira)
      printf 'resolve: conflito fechado (feature=%s local_key=%s jira_key=%s reason=%s escolha=keep_jira) — estado atual do Jira mantido, nenhuma escrita realizada\n' \
        "$_jsr_feature" "$_jsr_key" "$_jsr_jkey" "$_jsr_reason"
      ;;
    ignored)
      printf 'resolve: conflito fechado (feature=%s local_key=%s jira_key=%s reason=%s escolha=ignored) — registro apenas encerrado, nenhuma acao tomada\n' \
        "$_jsr_feature" "$_jsr_key" "$_jsr_jkey" "$_jsr_reason"
      ;;
  esac
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
  status)
    _js_cmd_status "$@"
    ;;
  resolve)
    _js_cmd_resolve "$@"
    ;;
  *)
    _js_die_usage "subcomando desconhecido: $_js_sub (validos: plan, convert, enqueue, drain, status, resolve)"
    ;;
esac
