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
# (4.3.2, efeito DURAVEL desde FASE 12 tarefa 12.1.1): fecha o
# `ConflictRecord` PENDENTE de (F, K) — resolucao e SEMPRE decisao humana,
# nunca automatica (data-model.md). `keep_jira` rebaseline o SyncMarker
# (R3+R6 PUT) para o titulo+status ATUAIS da issue, para que o
# drain/reconcile seguinte NAO reabra o MESMO conflito contra o marker
# antigo; `ignored` so atualiza a coluna `resolution` (nenhuma escrita no
# Jira). `overwrite` rebaseline o marker (mesmo mecanismo) e reenfileira
# (via `enqueue`, mesma funcao interna) um NOVO `OutboxEvent` — o
# `desired_state` vem do ultimo evento outbox `conflict` do par, ou, na
# ausencia dele (conflitos vindos de reconciliacao `local_key=*` ou de
# `convert`), do `local_state` ATUAL via `jira-tasks.sh items` — o proximo
# `drain` transiciona de fato, sobrescrevendo o Jira com o estado local.
# Erro (exit 1) se nao existir ConflictRecord `pending` para o par, se
# nenhuma fonte resolver um `desired_state`, ou se o rebaseline (R3/R6)
# falhar — nunca inventa um fechamento nem um `desired_state` (Principio
# VI); nesses casos o conflito permanece pendente.
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
# Reconciliacao da feature inteira (`local_key=*`, FR-004, feature cstk-jira
# FASE 10 tarefa 10.3): o hook `posttooluse-jira-sync.sh` (modo `wave`)
# enfileira um evento `local_key=* desired_state=reconcile` a cada
# `close_wave`. `_js_process_reconcile_event` expande esse evento em UM item
# por `jira-tasks.sh items --feature F` (Epic + Tasks + Sub-tasks,
# `local_state` ja derivado dos checkboxes/agregacao) e processa cada item
# ja mapeado (`active`) pelo MESMO fluxo R3/R6-GET/conflito/R5/R4/R6-PUT de
# um evento direto — item ainda nao convertido (sem `jira-map.tsv`) e
# ignorado. Conflito em um item NUNCA impede os demais (`ConflictRecord` por
# item, FR-011); `auth_failed` em qualquer chamada interrompe a
# reconciliacao inteira (mesmo gate FR-016 de um evento direto). Sem
# `auth_failed`/`deferred` em nenhum item, o evento `*` vira `done`
# (compactado no PROXIMO `drain` — a proxima reconciliacao nasce de um NOVO
# evento `*`, sempre com o estado local mais recente).
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
      r02 FASE 16 task 16.4.1: se milestone_mode=auto, roda `milestone
      ensure` ANTES da 1a criacao; Epic/Task recebem o marco resolvido via
      --fix-version-id (Sub-task so se fix_versions_on_subtask=on); marco
      blocked aborta a criacao de itens NOVOS (exit 7) sem afetar
      transicoes de itens ja mapeados.

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
      r02 FASE 16 task 16.4.2: no evento `reconcile` (local_key=*), o item
      Epic tambem reaplica o marco corrente via update.fixVersions add/
      remove (SEC-10: remove so se o id antigo ainda constar no sidecar
      jira-milestones.tsv como current/superseded; divergencia vira
      ConflictRecord milestone_drift, nunca remocao forcada).

  jira-sync.sh status [--feature F]
      Resumo LOCAL (sem rede), legivel pelo operador: contagem do outbox
      por status (queued/deferred/conflict/auth_failed) + detalhe dos
      eventos auth_failed; ConflictRecord pendentes (runtime/conflicts.tsv);
      cards orphan de cada jira-map.tsv. Sem --feature, agrega TODAS as
      features sob docs/specs/*/. Com --feature (r02 FASE 16 task 16.4.4):
      linha grep-avel milestone=<nome|unresolved|off|blocked:nome>.

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

  jira-sync.sh requeue-auth-failed [--feature F]
      Devolve eventos `auth_failed` a `queued` (data-model.md OutboxEvent
      auth_failed->queued) apos reconfiguracao bem-sucedida da credencial
      (chamado por `jira-setup.sh write-config`). Sem --feature, reenfileira
      para TODAS as features (credencial e global ao projeto). Idempotente;
      sem eventos auth_failed, imprime contagem 0 e sai exit 0.

  jira-sync.sh resolve-state-field --dir D --field F
      Le o campo F (top-level ou caminho pontuado, ex:
      "execution.canonical_project") de D/state.json (grep/sed puro, pela
      chave folha do caminho) ou, se D/state.db existir, delega ao
      `state-rw.sh` do runtime agente-00c-runtime quando localizavel
      (CSTK_LIB ou ~/.claude/skills/agente-00c-runtime/scripts) — UNICO
      ponto do plugin que le um campo de estado; nunca invoca sqlite3
      diretamente (Constitution II carve-out 1.1.0, task 13.1.1). `--field`
      passa por allowlist dedicada ([A-Za-z0-9_.], sem "." inicial/final
      nem ".." consecutivo) ANTES de qualquer leitura — recusa exit 2 sem
      tocar disco (task 14.1.1). Reusado pelo hook
      `posttooluse-jira-sync.sh` para `execution.canonical_project`. String
      vazia (exit 0) sem state.json/state.db ou sem runtime localizavel.

  jira-sync.sh milestone resolve --feature F
      r02 FASE 16 (FR-020/FR-021, research.md Decision R2-1): resolve o
      nome/tipo do marco (Fix Version) SEM rede. Ordem: milestone_mode=off
      -> `status=off`; round ativo (.previous_round.round, cross-checado
      contra o numero de diretorios rounds/rNN) -> `name=<F>-rNN`
      `kind=round`; senao milestone_release de ProjectConfig ou o 1o
      heading `## [X.Y.Z]` do CHANGELOG.md (SE for o mais alto) ->
      `name=<versao>` `kind=release`; nada resolvido -> `status=unresolved`.
      SEMPRE exit 0 (estado nao-resolvido nao e erro).

  jira-sync.sh milestone ensure --feature F
      r02 FASE 16.3 (FR-020/FR-021, research.md Decision R2-3/R2-4):
      garante a Fix Version do marco resolvido. off/unresolved -> mesmo
      passthrough de `milestone resolve`, sem rede. Resolvido: R13 +
      casamento exato (reusa `id`) senao R12 (createVersion); `400` em R12
      refaz R13 UMA vez e reusa se achar (corrida entre worktrees), senao
      `status=deferred` (exit 1, nada gravado); `403`/`404` em R12 grava
      `state=blocked` em jira-milestones.tsv (via jira-map.sh
      milestone-put) e sai exit 7 (nenhuma issue nova ate reconfiguracao).

Le <cwd>/docs/specs/F/tasks.md (+ spec.md) e <cwd>/docs/specs/F/jira-map.tsv.

EXIT CODES:
  0 sucesso   1 erro geral (inclui: resolve sem ConflictRecord pendente para
                             o par informado; milestone ensure deferred)
  2 uso incorreto   3 ProjectConfig ausente
  4 credencial ausente/incompleta/auth_failed   5 dependencia ausente
                                                 (convert; drain com eventos
                                                 queued exige jq/cliente
                                                 HTTP/sha256sum-shasum)
  7 milestone ensure: permission_denied (403/404 em R12) -> state=blocked
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

# _js_is_valid_field_path VALUE -> allowlist DEDICADA do `--field` de
# `resolve-state-field` (task 14.1.1): so aceita `[A-Za-z0-9_.]`, sem `.`
# inicial/final e sem `..` consecutivo — mais restrita que
# `_js_is_safe_field` (que so barra TAB/newline; permanece em uso nas
# chaves de outbox/conflicts, cujo charset e mais permissivo por design).
# Aceita caminho pontuado (`execution.canonical_project`) para leitura
# aninhada nos dois backends de `_js_resolve_state_field`. Recusa sem
# tocar disco (o dispatcher chama isto ANTES de qualquer leitura).
_js_is_valid_field_path() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9_.]*) return 1 ;;
  esac
  case "$1" in
    .*|*.|*..*) return 1 ;;
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

# Sidecar de outcomes de record_task (FASE 12 tarefa 12.4.1, data-model.md
# LocalWorkItem outcome precedence / US3 cenarios 2-3): persiste, por
# feature, o outcome (`pass`/`fail`) do ULTIMO evento direto de record_task
# enfileirado para cada task_id — arquivo global compartilhado entre
# features (mesmo padrao do outbox/conflicts, coluna `feature` filtra).
# `jira-tasks.sh items --outcomes-file` (`contracts/plugin-scripts.md`) ja
# da precedencia a este outcome sobre os checkboxes agregados (kind=task,
# `flush_task()`); sem persistir aqui e sem passar a flag em
# `_js_process_reconcile_event`, a reconciliacao `local_key=*` (enfileirada
# pelo hook a cada `close_wave`) derivava SO dos checkboxes e podia desfazer
# o outcome que o proprio record_task acabou de levar ao Jira (achado
# 12.4). NUNCA gravado para `local_key=*` (evento de reconciliacao nao
# carrega um task_id real). Nunca versionado (mesma regra do
# outbox/conflicts, `runtime/.gitignore` = `*`).
_JS_OUTCOMES_FILE="./.claude/cstk-jira/runtime/task-outcomes.tsv"
_JS_OUTCOMES_HEADER='feature	task_id	outcome'

# Sidecar de retry_after (FASE 12 tarefa 12.2.1, achado 12.2): NAO e um
# campo novo de OutboxEvent (data-model.md nao ganha coluna — escopo
# minimo, nenhum `cut -f`/header existente muda). So guarda, por
# event_id, o epoch (segundos, `date -u +%s`) a partir do qual o evento
# `deferred` volta a ser elegivel para o drain — populado SOMENTE quando
# `jira-io.sh` emitiu `retry_after=<n>` em stderr (429 com header
# `Retry-After`); evento sem linha aqui e elegivel IMEDIATAMENTE no
# proximo drain (mesmo efeito de antes desta tarefa para deferred sem
# Retry-After — rede/timeout genericos). Nunca versionado
# (`runtime/.gitignore` = `*`, mesma regra do outbox/conflicts).
_JS_DEFERRED_FILE="./.claude/cstk-jira/runtime/deferred-retry.tsv"
_JS_DEFERRED_HEADER='event_id	available_at_epoch'

# Chave da entity property do SyncMarker (data-model.md) — DESIGN do
# plugin, nao dado externo.
_JS_MARKER_PROPERTY_KEY="cstk-jira.sync"

# Texto FIXO enviado como `description` de R12 (createVersion) — DESIGN do
# plugin (rotulo, nao dado lido do Jira; contracts/jira-rest.md R12 exige
# texto FIXO, nunca eco de texto remoto). r02 FASE 16 task 16.3.1.
_JS_MILESTONE_DESCRIPTION="Marco gerenciado pelo plugin cstk-jira (cstk-jira-plugin) — nao editar manualmente."

# _js_json_str JSON KEY -> valor de um campo string simples ("key":"value"),
# 1a ocorrencia. Mesma tecnica de hooks/posttooluse-jira-sync.sh
# `_pjs_json_str` (grep/sed puros — carve-out 1.1.0 condicao b, jq fica
# exclusivo de jira-io.sh).
_js_json_str() {
  printf '%s\n' "$1" | tr -d '\n' \
    | sed -n 's/.*"'"$2"'"[ 	]*:[ 	]*"\([^"]*\)".*/\1/p' | head -n 1
}

# _js_runtime_state_rw -> path do helper `state-rw.sh` do runtime
# `agente-00c-runtime`, se localizavel (task 13.1.1 / Constitution II
# carve-out 1.1.0: elimina o uso direto de `sqlite3` no plugin — quem detem
# essa dependencia, sob o carve-out 1.3.0 RESTRITO ao proprio runtime, e o
# `state-rw.sh`; este script so o CONSOME de fora, nunca reimplementa
# leitura de SQLite). Ordem de fontes (a 1a que existir vence):
# `$CSTK_LIB/../skills/agente-00c-runtime/scripts` (instalacao do toolkit
# apontada pela variavel ja usada pelo `cli/lib` do proprio cstk) ou
# `~/.claude/skills/agente-00c-runtime/scripts` (instalacao global padrao).
# String vazia se nenhuma existir — o chamador trata como "runtime
# indisponivel" (mesmo efeito pratico de "sqlite3 ausente do PATH" antes
# desta mudanca: sem override, nunca inventa um valor). Nunca escreve nada.
_js_runtime_state_rw() {
  if [ -n "${CSTK_LIB:-}" ] \
     && [ -r "$CSTK_LIB/../skills/agente-00c-runtime/scripts/state-rw.sh" ]; then
    printf '%s\n' "$CSTK_LIB/../skills/agente-00c-runtime/scripts/state-rw.sh"
    return 0
  fi
  if [ -r "$HOME/.claude/skills/agente-00c-runtime/scripts/state-rw.sh" ]; then
    printf '%s\n' "$HOME/.claude/skills/agente-00c-runtime/scripts/state-rw.sh"
    return 0
  fi
  return 0
}

# _js_resolve_state_field DIR FIELD -> valor de um campo (top-level ou
# caminho pontuado, ex: "execution.canonical_project") de DIR/state.json
# (grep/sed puro via `_js_json_str`, sem dependencia nova — a leitura nao
# rastreia nesting, entao usa so o ULTIMO SEGMENTO do caminho como chave de
# busca dentro do objeto pai, ver comentario abaixo) ou, quando so
# DIR/state.db existir, delegado ao `state-rw.sh` do runtime
# (`_js_runtime_state_rw`) QUANDO localizavel — este passa o caminho
# pontuado INTEIRO (`.$_jsrsf_field`), que o `state-rw.sh get` ja resolve
# nativamente contra qualquer nivel de aninhamento — UNICO ponto do plugin
# (task 13.1.1, corrigido pela 14.1.1 para aceitar caminho pontuado nos
# DOIS backends) que resolve um campo de estado a partir de qualquer um dos
# dois backends; `_js_resolve_stage` (abaixo) e o hook
# `posttooluse-jira-sync.sh` (via subcomando `resolve-state-field`)
# reutilizam esta funcao/subcomando em vez de duplicar a logica. Sem
# state.json, sem state.db, ou sem runtime localizavel para o ramo
# state.db: string vazia (chamador trata como "sem valor" — Principio VI,
# nunca inventa). Nunca escreve nada.
_js_resolve_state_field() {
  _jsrsf_dir="$1"
  _jsrsf_field="$2"
  if [ -f "$_jsrsf_dir/state.json" ]; then
    # Ultimo segmento do caminho pontuado: `_js_json_str` casa a chave em
    # QUALQUER nivel do JSON flat (sem rastrear o objeto pai), entao um
    # caminho como "execution.canonical_project" so precisa da chave folha
    # "canonical_project" para achar o valor correto (achado 14.1.1: o bug
    # real era passar o campo top-level errado ao state.db, nao o parsing
    # do state.json em si).
    case "$_jsrsf_field" in
      *.*) _jsrsf_leaf=${_jsrsf_field##*.} ;;
      *)   _jsrsf_leaf=$_jsrsf_field ;;
    esac
    _js_json_str "$(cat "$_jsrsf_dir/state.json" 2>/dev/null)" "$_jsrsf_leaf" 2>/dev/null
    return 0
  fi
  [ -f "$_jsrsf_dir/state.db" ] || return 0
  _jsrsf_rw=$(_js_runtime_state_rw) || return 0
  [ -n "$_jsrsf_rw" ] || return 0
  _jsrsf_val=$("$_jsrsf_rw" get --state-dir "$_jsrsf_dir" --field ".$_jsrsf_field" 2>/dev/null) || return 0
  [ -n "$_jsrsf_val" ] || return 0
  [ "$_jsrsf_val" = "null" ] && return 0
  printf '%s\n' "$_jsrsf_val"
  return 0
}

# _js_resolve_stage FEATURE -> etapa corrente (`current_stage`) da execucao
# ativa, READ-ONLY (FASE 12 tarefa 12.8.1; data-model.md ProjectConfig
# `stage_status.<stage>` / US2 cenario 1). Mesma convencao de namespace do
# hook (`contracts/hooks.md` "Resolucao da execucao ativa"): FEATURE e o
# MESMO short-name de `docs/specs/FEATURE`, que por convencao do plugin e
# tambem o de `.claude/feature-00c-state/FEATURE` quando essa execucao
# existe. Ordem de fontes (a 1a que existir vence, nunca as duas
# combinadas): feature-00c (pipeline desta feature) -> agente-00c
# (pipeline do projeto inteiro). Sem nenhuma das duas, ou sem
# `current_stage` legivel, imprime string vazia — o chamador trata vazio
# como "sem override" (mesmo efeito de `stage_status.<stage>` ausente do
# ProjectConfig, nunca inventa uma etapa). Nunca escreve nada.
_js_resolve_stage() {
  _jsrs_feature="$1"
  _jsrs_dir=""
  if [ -f "./.claude/feature-00c-state/$_jsrs_feature/state.json" ] \
     || [ -f "./.claude/feature-00c-state/$_jsrs_feature/state.db" ]; then
    _jsrs_dir="./.claude/feature-00c-state/$_jsrs_feature"
  elif [ -f "./.claude/agente-00c-state/state.json" ] \
     || [ -f "./.claude/agente-00c-state/state.db" ]; then
    _jsrs_dir="./.claude/agente-00c-state"
  else
    return 0
  fi
  _js_resolve_state_field "$_jsrs_dir" current_stage
  return 0
}

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
  # FASE 12 tarefa 12.2.1: qualquer transicao de status LIMPA o sidecar de
  # retry_after — se o chamador quer persistir um novo retry_after (evento
  # continua/volta a `deferred`), ele chama `_js_set_retry_after` DEPOIS
  # desta funcao (ordem ja seguida em todos os call-sites). Sem isso, um
  # evento que sai de `deferred` para `done`/`conflict`/`auth_failed`
  # deixaria uma linha orfa no sidecar (cresce sem necessidade, e um evento
  # de outbox REUTILIZAR o mesmo event_id — nunca acontece hoje, mas nao ha
  # motivo para depender disso).
  _js_clear_retry_after "$_jses_id"
}

# _js_clear_retry_after EVENT_ID — remove a linha (se existir) do sidecar
# de retry_after (12.2.1). No-op silencioso se o sidecar nao existir ou o
# event_id nao tiver linha.
_js_clear_retry_after() {
  [ -f "$_JS_DEFERRED_FILE" ] || return 0
  _jcra_tmp="$_JS_DEFERRED_FILE.tmp.$$"
  awk -F '\t' -v OFS='\t' -v id="$1" '
    NR == 1 { print; next }
    $1 != id { print }
  ' "$_JS_DEFERRED_FILE" > "$_jcra_tmp"
  mv -- "$_jcra_tmp" "$_JS_DEFERRED_FILE"
}

# _js_set_retry_after EVENT_ID RETRY_AFTER_SECONDS — 12.2.1 (data-model.md
# OutboxEvent "deferred -> queued: proximo gatilho de drain (respeita
# Retry-After)"): upsert (append-only por reescrita completa, mesmo padrao
# tmp+mv de `_js_set_event_status`) da linha `event_id\tavailable_at_epoch`
# no sidecar, com `available_at_epoch = agora + RETRY_AFTER_SECONDS`.
# RETRY_AFTER_SECONDS vazio/nao-numerico -> no-op (evento fica elegivel
# IMEDIATAMENTE no proximo drain — nenhum Retry-After foi informado pelo
# Jira, nunca inventa um valor default). Chamado SEMPRE apos
# `_js_set_event_status EVENT_ID deferred ...` (que acabou de limpar
# qualquer linha antiga do mesmo event_id).
_js_set_retry_after() {
  _jsra_id="$1"
  _jsra_secs="${2:-}"
  case "$_jsra_secs" in
    ''|*[!0-9]*) return 0 ;;
  esac
  _jsra_now=$(date -u +%s)
  _jsra_avail=$((_jsra_now + _jsra_secs))
  _jsra_dir=$(dirname -- "$_JS_DEFERRED_FILE")
  mkdir -p "$_jsra_dir" || _js_die "falha ao criar diretorio runtime: $_jsra_dir" 1
  _jsra_tmp="$_JS_DEFERRED_FILE.tmp.$$"
  {
    if [ -f "$_JS_DEFERRED_FILE" ]; then
      awk -F '\t' -v id="$_jsra_id" 'NR == 1 || $1 != id { print }' "$_JS_DEFERRED_FILE"
    else
      printf '%s\n' "$_JS_DEFERRED_HEADER"
    fi
    printf '%s\t%s\n' "$_jsra_id" "$_jsra_avail"
  } > "$_jsra_tmp"
  mv -- "$_jsra_tmp" "$_JS_DEFERRED_FILE"
}

# _js_extract_retry_after ERR_FILE — le a linha `retry_after=<n>` (se
# houver) de um arquivo de stderr capturado de `jira-io.sh request`
# (mesmo contrato ja usado para `http_status=`/`classification=`,
# `contracts/plugin-scripts.md`). Imprime vazio se ausente — nunca
# inventa um valor (Principio VI).
_js_extract_retry_after() {
  [ -f "$1" ] || { printf ''; return 0; }
  grep '^retry_after=' "$1" 2>/dev/null | tail -n 1 | cut -d= -f2
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

# _js_close_conflict_outbox_events FEATURE LOCAL_KEY — task 13.3.1
# (data-model.md OutboxEvent "conflict --> [*]: operador decide (jira-sync
# resolve)"): fecha (status=done) TODO evento outbox com status=`conflict`
# do par (F, K). `resolve` e SEMPRE quem decide o destino de um conflito
# (FASE 4.3, qualquer --choice) — sem isto, o evento outbox que originou o
# conflito ficava `conflict` PARA SEMPRE (nenhuma compactacao remove
# `conflict`, so `done`), e `_js_last_conflict_desired_state` (usado por
# `overwrite`) continuava enxergando esse evento mesmo depois do conflito
# ja fechado — um 2o conflito no MESMO par podia ser mascarado pelo
# desired_state do conflito ANTERIOR ja resolvido. Mapeia para `done` (nao
# um status novo) para que a PROXIMA compactacao de drain (4.2.8) tambem
# remova estes eventos do outbox, mesmo efeito pratico do `[*]` terminal do
# data-model. Idempotente (sem eventos `conflict` casando, no-op; arquivo
# ausente, no-op).
_js_close_conflict_outbox_events() {
  _jscoe_feature="$1"
  _jscoe_key="$2"
  [ -f "$_JS_OUTBOX_FILE" ] || return 0
  _jscoe_tmp="$_JS_OUTBOX_FILE.tmp.$$"
  awk -F '\t' -v OFS='\t' -v f="$_jscoe_feature" -v k="$_jscoe_key" '
    NR == 1 { print; next }
    $3 == f && $4 == k && $8 == "conflict" { $8 = "done" }
    { print }
  ' "$_JS_OUTBOX_FILE" > "$_jscoe_tmp"
  mv -- "$_jscoe_tmp" "$_JS_OUTBOX_FILE"
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

# _js_rebaseline_marker IO FEATURE LOCAL_KEY JIRA_KEY — feature cstk-jira
# FASE 12 tarefa 12.1.1 (FR-011 / task 4.3.2 / task 4.3.4 `resolve`): le o
# titulo+status+descricao ATUAIS da issue (R3, mesma leitura que `drain`/
# `convert` ja fazem) e regrava o SyncMarker (R6 PUT) com ESSES valores —
# nunca inventa um estado, so espelha o que a issue tem agora. Efeito: a
# proxima deteccao de conflito (drain/reconcile/`_js_maybe_update_mapped_issue`)
# compara contra um marker que bate o estado atual, logo NAO reabre o
# MESMO conflito (`resolve --choice keep_jira`/`overwrite`, FASE 12.1).
# task 13.2.1 (FR-011 / data-model SyncMarker written_description_sha256):
# quando a issue carrega descricao composta (`fields.description` nao-vazio
# — so Task/Sub-task com criticidade/dependencias, mesma extracao de
# `_js_maybe_update_mapped_issue`), o marker rebaselinado grava
# `written_description_sha256` do texto ATUAL (nao do valor anterior) —
# "aceitar o Jira como esta" (keep_jira) ou "estabelecer a nova baseline
# antes de reenfileirar" (overwrite) precisam refletir a descricao REAL da
# issue, nunca uma baseline antiga nem a ausencia da chave (que faria a
# proxima `convert` tratar a descricao como "sem baseline" e sobrescrever
# uma edicao manual em silencio). Issue sem descricao: a chave continua
# omitida (nada a proteger).
# Imprime o status atual (stdout) em sucesso — reuso pelo chamador sem 2a
# leitura R3. Falha (R3 ou R6 PUT) -> diagnostico em stderr, marker
# intocado, retorna 1 — chamador NUNCA deve fechar o ConflictRecord como
# se o rebaseline tivesse funcionado (senao o proximo drain reabriria o
# conflito ja fechado, silenciosamente).
_js_rebaseline_marker() {
  _jrm_io="$1"
  _jrm_feature="$2"
  _jrm_lkey="$3"
  _jrm_jkey="$4"

  if _jrm_resp=$("$_jrm_io" request GET "/rest/api/3/issue/$_jrm_jkey?fields=summary,status,description" --op R3 2>/dev/null); then
    :
  else
    printf '%s: falha ao ler estado atual de %s (R3) para rebaselinear o SyncMarker\n' \
      "$_JS_NAME" "$_jrm_jkey" >&2
    return 1
  fi
  _jrm_summary=$(printf '%s' "$_jrm_resp" | "$_jrm_io" json-get '.fields.summary')
  _jrm_status=$(printf '%s' "$_jrm_resp" | "$_jrm_io" json-get '.fields.status.name')
  _jrm_description=$(printf '%s' "$_jrm_resp" | "$_jrm_io" json-get \
    '.fields.description.content[0].content[0].text? // ""')
  _jrm_sha=$(printf '%s' "$_jrm_summary" | "$_jrm_io" sha256-stdin)
  _jrm_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  set -- marker --local-key "$_jrm_lkey" --feature "$_jrm_feature" \
    --written-summary-sha256 "$_jrm_sha" --written-status "$_jrm_status" --written-at "$_jrm_now"
  if [ -n "$_jrm_description" ]; then
    _jrm_desc_sha=$(printf '%s' "$_jrm_description" | "$_jrm_io" sha256-stdin)
    set -- "$@" --written-description-sha256 "$_jrm_desc_sha"
  fi
  _jrm_body=$("$_jrm_io" json-build "$@")
  _jrm_bf=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jrm_body" > "$_jrm_bf"
  if "$_jrm_io" request PUT "/rest/api/3/issue/$_jrm_jkey/properties/$_JS_MARKER_PROPERTY_KEY" \
      --body-file "$_jrm_bf" --op R6 >/dev/null 2>/dev/null; then
    rm -f "$_jrm_bf"
    printf '%s' "$_jrm_status"
    return 0
  fi
  rm -f "$_jrm_bf"
  printf '%s: falha ao gravar SyncMarker rebaselinado para %s (R6 PUT)\n' \
    "$_JS_NAME" "$_jrm_jkey" >&2
  return 1
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

# --- milestone (r02 FASE 16, FR-020/FR-021) --------------------------------

# _js_round_token_ok TOKEN — SEC-11: TOKEN MUST casar `^r[0-9]{2,}$`
# (research.md Decision R2-1/R2-1 SEC-11, tasks.md 16.2.3). POSIX puro
# (case + bracket expression): `r[0-9][0-9]*` exige 'r' seguido de AO MENOS
# 2 digitos; o `case` seguinte confere que TODO o restante apos o 'r' e so
# digitos (rejeita "r01x", que o glob acima sozinho aceitaria).
_js_round_token_ok() {
  case "$1" in
    r[0-9][0-9]*) : ;;
    *) return 1 ;;
  esac
  _jsrt_rest=${1#r}
  case "$_jsrt_rest" in
    *[!0-9]*) return 1 ;;
  esac
  return 0
}

# _js_semver_ok VALUE — SEC-11: aproximacao POSIX (sem regex estendida) de
# `^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$` (tasks.md 16.2.2,
# research.md Decision R2-1 regra 3). major/minor/patch MUST ser so digitos;
# sufixo pre-release/build (apos '-' ou '+') e opcional, charset
# [0-9A-Za-z.-], nao-vazio quando presente.
_js_semver_ok() {
  _jssv_v="$1"
  [ -n "$_jssv_v" ] || return 1
  _jssv_major=${_jssv_v%%.*}
  _jssv_after_major=${_jssv_v#*.}
  [ "$_jssv_after_major" != "$_jssv_v" ] || return 1
  case "$_jssv_major" in ''|*[!0-9]*) return 1 ;; esac

  _jssv_minor=${_jssv_after_major%%.*}
  _jssv_after_minor=${_jssv_after_major#*.}
  [ "$_jssv_after_minor" != "$_jssv_after_major" ] || return 1
  case "$_jssv_minor" in ''|*[!0-9]*) return 1 ;; esac

  _jssv_patch_and_suffix="$_jssv_after_minor"
  case "$_jssv_patch_and_suffix" in
    *[-+]*)
      _jssv_patch=${_jssv_patch_and_suffix%%[-+]*}
      _jssv_suffix=${_jssv_patch_and_suffix#"$_jssv_patch"}
      case "$_jssv_suffix" in
        -*|+*) : ;;
        *) return 1 ;;
      esac
      _jssv_suffix_body=${_jssv_suffix#?}
      [ -n "$_jssv_suffix_body" ] || return 1
      case "$_jssv_suffix_body" in *[!0-9A-Za-z.-]*) return 1 ;; esac
      ;;
    *)
      _jssv_patch="$_jssv_patch_and_suffix"
      ;;
  esac
  case "$_jssv_patch" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}

# _js_cmd_milestone_resolve --feature F — 16.2 (research.md Decision R2-1):
# resolve o nome/tipo do marco (Fix Version) da feature, SEM rede (so le
# ProjectConfig + state da execucao + CHANGELOG.md). Ordem (1a regra que
# produzir nome vence, nunca combinadas):
#   1. milestone_mode=off (ProjectConfig)                    -> status=off
#   2. round ativo (.previous_round.round via
#      resolve-state-field, cross-checado contra
#      `1 + numero de dirs rounds/r[0-9][0-9]*`)              -> kind=round
#   3. sem round ativo: milestone_release (ProjectConfig,
#      SEC-6) ou 1o heading `## [X.Y.Z]` do CHANGELOG.md
#      (SE for o mais alto — `[Unreleased]` no topo = ainda
#      sem nome)                                              -> kind=release
#   4. nada resolvido                                         -> status=unresolved
# Saida (contracts/plugin-scripts.md `milestone resolve`): resolvido ->
# `name=<N>` + `kind=<round|release>`; nao resolvido -> `name=` (vazia) +
# `status=<unresolved|off>`. SEMPRE exit 0 (estado nao-resolvido/off nao e
# erro — o chamador de `convert`/`drain` decide o que fazer). Nunca chuta:
# divergencia de contagem de rounds ou formato invalido => unresolved
# (Principio VI).
_js_cmd_milestone_resolve() {
  _jsmr_feature=$(_js_parse_feature_arg "$@")

  _jsmr_dir="$(_js_script_dir)"
  _jsmr_config="$_jsmr_dir/jira-config.sh"

  "$_jsmr_config" validate

  _jsmr_mode=$("$_jsmr_config" get milestone_mode 2>/dev/null) || _jsmr_mode="auto"
  [ -n "$_jsmr_mode" ] || _jsmr_mode="auto"

  if [ "$_jsmr_mode" = "off" ]; then
    printf 'name=\n'
    printf 'status=off\n'
    return 0
  fi

  # 2. round ativo — mesma resolucao de diretorio de _js_resolve_stage,
  # mas so a fonte feature-00c (rounds sao por FEATURE, nunca do
  # agente-00c que cobre o projeto inteiro).
  _jsmr_state_dir=""
  if [ -f "./.claude/feature-00c-state/$_jsmr_feature/state.json" ] \
     || [ -f "./.claude/feature-00c-state/$_jsmr_feature/state.db" ]; then
    _jsmr_state_dir="./.claude/feature-00c-state/$_jsmr_feature"
  fi

  _jsmr_prev_round=""
  if [ -n "$_jsmr_state_dir" ]; then
    _jsmr_prev_round=$(_js_resolve_state_field "$_jsmr_state_dir" "previous_round.round") || _jsmr_prev_round=""
  fi

  if [ -n "$_jsmr_prev_round" ]; then
    if _js_round_token_ok "$_jsmr_prev_round"; then
      _jsmr_prev_num=${_jsmr_prev_round#r}
      _jsmr_dircount=0
      if [ -d "$_jsmr_state_dir/rounds" ]; then
        for _jsmr_rd in "$_jsmr_state_dir"/rounds/r[0-9][0-9]*; do
          [ -d "$_jsmr_rd" ] || continue
          _jsmr_dircount=$((_jsmr_dircount + 1))
        done
      fi
      # Descarta zeros a esquerda via parameter expansion (POSIX puro, sem
      # `10#` de base aritmetica — SC3052/nao-portavel): evita que o shell
      # interprete "08"/"09" como octal invalido na aritmetica abaixo.
      _jsmr_prev_num_dec="$_jsmr_prev_num"
      while [ "${_jsmr_prev_num_dec#0}" != "$_jsmr_prev_num_dec" ] \
            && [ "${#_jsmr_prev_num_dec}" -gt 1 ]; do
        _jsmr_prev_num_dec=${_jsmr_prev_num_dec#0}
      done
      _jsmr_prev_num_dec=$((_jsmr_prev_num_dec + 0))
      if [ "$_jsmr_prev_num_dec" -eq "$_jsmr_dircount" ]; then
        _jsmr_next_num=$((_jsmr_prev_num_dec + 1))
        _jsmr_next_nn=$(printf '%02d' "$_jsmr_next_num")
        printf 'name=%s-r%s\n' "$_jsmr_feature" "$_jsmr_next_nn"
        printf 'kind=round\n'
        return 0
      fi
      printf 'name=\n'
      printf 'status=unresolved\n'
      return 0
    fi
    printf 'name=\n'
    printf 'status=unresolved\n'
    return 0
  fi

  # 3. release (sem round ativo): milestone_release override PRIMEIRO.
  _jsmr_release=$("$_jsmr_config" get milestone_release 2>/dev/null) || _jsmr_release=""
  if [ -n "$_jsmr_release" ]; then
    if _js_semver_ok "$_jsmr_release"; then
      printf 'name=%s\n' "$_jsmr_release"
      printf 'kind=release\n'
      return 0
    fi
    printf 'name=\n'
    printf 'status=unresolved\n'
    return 0
  fi

  # Sem override: 1o heading `## [X.Y.Z]` do CHANGELOG.md da raiz do
  # projeto-alvo (cwd) — o heading mais alto pela convencao Keep a
  # Changelog (mais novo no topo).
  _jsmr_changelog="./CHANGELOG.md"
  _jsmr_heading_name=""
  if [ -f "$_jsmr_changelog" ]; then
    _jsmr_heading_line=$(grep -m1 '^## \[' "$_jsmr_changelog" 2>/dev/null) || _jsmr_heading_line=""
    if [ -n "$_jsmr_heading_line" ]; then
      _jsmr_heading_name=$(printf '%s\n' "$_jsmr_heading_line" | sed -n 's/^## \[\([^]]*\)\].*/\1/p')
    fi
  fi

  if [ -z "$_jsmr_heading_name" ] || [ "$_jsmr_heading_name" = "Unreleased" ]; then
    printf 'name=\n'
    printf 'status=unresolved\n'
    return 0
  fi

  if _js_semver_ok "$_jsmr_heading_name"; then
    printf 'name=%s\n' "$_jsmr_heading_name"
    printf 'kind=release\n'
    return 0
  fi

  printf 'name=\n'
  printf 'status=unresolved\n'
  return 0
}

# _js_milestone_r13_match IO_PATH PROJECT_KEY NAME — r02 FASE 16 task 16.3.1
# (contracts/jira-rest.md R13): lista as Fix Versions do projeto (rota
# NAO-paginada) e casa `name` por IGUALDADE EXATA local. O filtro de
# `json-get` e SEMPRE fixo (`.[] | [.id, .name] | @tsv`) — NAME nunca entra
# no FILTER do jq (mesma disciplina do resto do arquivo, nenhum json-get
# interpola dado externo no filtro); o casamento exato acontece no awk via
# `-v` (mesma tecnica de jira-map.sh). Imprime o `id` em stdout e retorna 0
# se achou; retorna 1 (stdout vazio) se a lista nao tem esse nome. Falha de
# rede/HTTP de R13 propaga via `_js_die` (sem classificacao especial para
# --op R13 no contrato — passthrough do exit code de jira-io.sh).
_js_milestone_r13_match() {
  _jml_io="$1"
  _jml_pkey="$2"
  _jml_name="$3"
  _jml_resp=$("$_jml_io" request GET "/rest/api/3/project/$_jml_pkey/versions" --op R13 2>/dev/null) \
    || _js_die "falha ao listar Fix Versions do projeto $_jml_pkey (R13)" 1
  _jml_tsv=$(printf '%s' "$_jml_resp" | "$_jml_io" json-get '.[] | [.id, .name] | @tsv')
  _jml_id=$(printf '%s\n' "$_jml_tsv" | awk -F '\t' -v n="$_jml_name" '$2 == n { print $1; exit }')
  [ -n "$_jml_id" ] || return 1
  printf '%s' "$_jml_id"
  return 0
}

# _js_cmd_milestone_ensure --feature F — r02 FASE 16 task 16.3
# (research.md Decision R2-3/R2-4; contracts/plugin-scripts.md
# `milestone ensure`): garante que a Fix Version do marco resolvido por
# `milestone resolve` exista no Jira, com idempotencia via R13 antes de
# criar via R12. Sem rede quando o marco NAO esta resolvido (`off`/
# `unresolved`) — reusa o MESMO contrato de saida de `milestone resolve`
# (`name=`/`status=`), permitindo o chamador (`convert`, FASE 16.4) invocar
# `ensure` sem checar `resolve` antes.
#
# Fluxo em rede (so quando resolvido, name+kind):
#   1. R13 + casamento exato -> achou: reusa `id`, grava state=current,
#      `status=current`, exit 0.
#   2. Nao achou -> R12 (createVersion, description FIXA do plugin):
#        201 -> grava state=current, `status=current`, exit 0.
#        400 (version_conflict_or_invalid) -> refaz R13 UMA vez (task
#          16.3.2, nunca uma 2a R12 sem reler antes): achou agora (corrida
#          entre worktrees, FR-023) -> reusa `id`, state=current, exit 0;
#          continua sem achar -> `status=deferred`, NADA gravado no
#          sidecar (proxima chamada tenta de novo), exit 1.
#        403/404 (jira-io.sh classifica exit 7 permission_denied) -> grava
#          state=blocked (SEM jira_version_id — nada foi criado, task
#          16.3.3), `status=blocked`, exit 7. Quem decide suspender a
#          criacao de issues novas e o CHAMADOR (`convert`, FASE 16.4) —
#          `ensure` so reporta e persiste o estado.
_js_cmd_milestone_ensure() {
  _jsme_feature=$(_js_parse_feature_arg "$@")

  _jsme_dir="$(_js_script_dir)"
  _jsme_config="$_jsme_dir/jira-config.sh"
  _jsme_io="$_jsme_dir/jira-io.sh"
  _jsme_map="$_jsme_dir/jira-map.sh"

  _jsme_resolved=$(_js_cmd_milestone_resolve --feature "$_jsme_feature")
  _jsme_name=$(printf '%s\n' "$_jsme_resolved" | sed -n 's/^name=//p')
  _jsme_kind=$(printf '%s\n' "$_jsme_resolved" | sed -n 's/^kind=//p')
  _jsme_passthrough_status=$(printf '%s\n' "$_jsme_resolved" | sed -n 's/^status=//p')

  if [ -z "$_jsme_name" ]; then
    # off ou unresolved (resolve nunca emite name= vazio com kind=
    # preenchido) — passthrough sem rede, mesmo contrato de saida de
    # `milestone resolve`.
    printf 'name=\n'
    printf 'status=%s\n' "$_jsme_passthrough_status"
    return 0
  fi

  "$_jsme_io" deps-check
  "$_jsme_config" validate
  "$_jsme_config" credential-check

  _jsme_project_key=$("$_jsme_config" get project_key)
  "$_jsme_io" validate-segment "$_jsme_project_key"

  _jsme_project_resp=$("$_jsme_io" request GET "/rest/api/3/project/$_jsme_project_key" 2>/dev/null) \
    || _js_die "falha ao resolver project.id via GET /rest/api/3/project/$_jsme_project_key" 1
  _jsme_project_id=$(printf '%s' "$_jsme_project_resp" | "$_jsme_io" json-get '.id')
  [ -n "$_jsme_project_id" ] || _js_die "resposta de GET project sem campo id" 1

  if _jsme_id=$(_js_milestone_r13_match "$_jsme_io" "$_jsme_project_key" "$_jsme_name"); then
    "$_jsme_map" milestone-put --feature "$_jsme_feature" --name "$_jsme_name" \
      --kind "$_jsme_kind" --version-id "$_jsme_id" \
      --project-key "$_jsme_project_key" --state current
    printf 'name=%s\n' "$_jsme_name"
    printf 'status=current\n'
    return 0
  fi

  _jsme_body=$("$_jsme_io" json-build version --name "$_jsme_name" \
    --project-id "$_jsme_project_id" --description "$_JS_MILESTONE_DESCRIPTION")
  _jsme_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r12body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jsme_body" > "$_jsme_body_file"

  # Nota: 'if CMD; then ok; else _ec=$?; ...' (com 'else' explicito, sem
  # negacao) — preserva o exit code genuino de jira-io.sh. Sem 'else', o
  # exit status de um 'if' cuja condicao falha e SEMPRE 0 por definicao
  # POSIX quando nenhum ramo executa ("If no compound-list is executed,
  # the exit status shall be zero") — ler "$?" DEPOIS do 'fi' captura esse
  # zero espurio, nunca o exit code real do comando que falhou (mesmo
  # padrao/motivo do resto do arquivo, ver comentario em _js_cmd_convert).
  if _jsme_resp=$("$_jsme_io" request POST /rest/api/3/version \
      --body-file "$_jsme_body_file" --op R12); then
    rm -f "$_jsme_body_file"
    _jsme_new_id=$(printf '%s' "$_jsme_resp" | "$_jsme_io" json-get '.id')
    [ -n "$_jsme_new_id" ] || _js_die "resposta de R12 sem campo id" 1
    "$_jsme_map" milestone-put --feature "$_jsme_feature" --name "$_jsme_name" \
      --kind "$_jsme_kind" --version-id "$_jsme_new_id" \
      --project-key "$_jsme_project_key" --state current
    printf 'name=%s\n' "$_jsme_name"
    printf 'status=current\n'
    return 0
  else
    _jsme_ec=$?
    rm -f "$_jsme_body_file"
  fi

  if [ "$_jsme_ec" -eq 7 ]; then
    "$_jsme_map" milestone-put --feature "$_jsme_feature" --name "$_jsme_name" \
      --kind "$_jsme_kind" --version-id "" \
      --project-key "$_jsme_project_key" --state blocked
    printf 'name=%s\n' "$_jsme_name"
    printf 'status=blocked\n'
    printf '%s: sem permissao para criar a Fix Version "%s" (Administer Jira/Administer Projects) — marco gravado como blocked; defina milestone_mode=off ou ajuste a credencial (R2-4)\n' \
      "$_JS_NAME" "$_jsme_name" >&2
    exit 7
  fi

  if [ "$_jsme_ec" -eq 1 ]; then
    # 400 em R12 (version_conflict_or_invalid) — refaz R13 UMA vez (task
    # 16.3.2: nunca repete R12 sem reler R13 antes).
    if _jsme_id2=$(_js_milestone_r13_match "$_jsme_io" "$_jsme_project_key" "$_jsme_name"); then
      "$_jsme_map" milestone-put --feature "$_jsme_feature" --name "$_jsme_name" \
        --kind "$_jsme_kind" --version-id "$_jsme_id2" \
        --project-key "$_jsme_project_key" --state current
      printf 'name=%s\n' "$_jsme_name"
      printf 'status=current\n'
      return 0
    fi
    printf 'name=%s\n' "$_jsme_name"
    printf 'status=deferred\n'
    printf '%s: R12 devolveu 400 para "%s" e o nome nao apareceu na releitura de R13 — marco fica deferred (nenhuma gravacao no sidecar), proxima chamada tenta de novo\n' \
      "$_JS_NAME" "$_jsme_name" >&2
    exit 1
  fi

  _js_die "falha ao criar Fix Version \"$_jsme_name\" (jira-io.sh exit $_jsme_ec)" "$_jsme_ec"
}

# _js_reconcile_epic_milestone FEATURE EPIC_JKEY WRITTEN_FIX_VERSION_ID —
# r02 FASE 16 task 16.4.2/16.4.3 (research.md Decision R2-2; plan.md SEC-10;
# data-model.md SyncMarker `written_fix_version_id`): reaplica o marco
# CORRENTE ao Epic via `update.fixVersions` add/remove (R14), chamado a cada
# `drain` (evento `local_key=* desired_state=reconcile`) SO para o item
# `kind=epic`. Reusa `_js_cmd_milestone_ensure` (mesma resolucao/
# idempotencia de `convert` — R13 + casamento exato, senao R12).
#
# Contrato de saida: imprime (stdout, SEM newline) o valor de
# written_fix_version_id que o CHAMADOR deve gravar no proximo R6 PUT do
# marker (pode ser igual a WRITTEN_FIX_VERSION_ID quando nada mudou). Exit
# sempre 0 exceto falha de rede no R2 final (repassa o exit code de
# jira-io.sh — o chamador decide auth_failed/deferred, mesmo padrao do
# resto do arquivo); qualquer falha ANTES do R2 (milestone ensure
# indisponivel, R13/R12 fora do ar) degrada SILENCIOSAMENTE para "nada
# muda nesta passada" (imprime WRITTEN_FIX_VERSION_ID inalterado, exit 0) —
# o proximo `drain` tenta de novo, nunca quebra a reconciliacao de status
# do mesmo item.
#
# Ramos (nenhuma chamada de rede de fixVersions fora do ultimo):
#   - milestone_mode=off: no-op, written inalterado.
#   - marco nao `current` (unresolved/deferred/blocked): no-op — blocked/
#     deferred NUNCA forcam remocao do marco ja aplicado (R2-4: so suspende
#     CRIACAO de itens novos, nunca desfaz o que ja esta certo no Epic).
#   - marco `current` e id == WRITTEN_FIX_VERSION_ID: idempotente, no-op.
#   - marco `current` e id != WRITTEN_FIX_VERSION_ID: SEC-10 — `remove` do
#     id antigo SO e emitido se `jira-map.sh milestone-id-known` confirma
#     que WRITTEN_FIX_VERSION_ID ainda consta no sidecar (current/
#     superseded) daquela feature; WRITTEN_FIX_VERSION_ID vazio (1a
#     aplicacao pos-convert sem marco, ou Epic pre-r02) -> so `add`, sem
#     `remove`. Divergencia (marker aponta um id que sumiu do sidecar) ->
#     `ConflictRecord milestone_drift`, ZERO chamadas de `update.fixVersions`
#     — NUNCA remocao forcada (mesma garantia de `manual_edit`/
#     `marker_missing`, so que para o marco em vez do titulo/status).
_js_reconcile_epic_milestone() {
  _jrem_feature="$1"
  _jrem_jkey="$2"
  _jrem_written="$3"

  _jrem_dir="$(_js_script_dir)"
  _jrem_config="$_jrem_dir/jira-config.sh"
  _jrem_io="$_jrem_dir/jira-io.sh"
  _jrem_map="$_jrem_dir/jira-map.sh"

  _jrem_mode=$("$_jrem_config" get milestone_mode 2>/dev/null) || _jrem_mode="auto"
  [ -n "$_jrem_mode" ] || _jrem_mode="auto"
  if [ "$_jrem_mode" != "auto" ]; then
    printf '%s' "$_jrem_written"
    return 0
  fi

  # `|| :` (mesma tecnica de `_js_cmd_convert`): qualquer exit nao-zero de
  # `milestone ensure` (blocked=7, deferred=1, ou uma falha de rede que caia
  # em `_js_die` dentro de `_js_milestone_r13_match`) e absorvido aqui — o
  # status impresso (ou a ausencia dele) decide o ramo abaixo, nunca o exit
  # code.
  _jrem_resolved=$(_js_cmd_milestone_ensure --feature "$_jrem_feature" 2>/dev/null) || :
  _jrem_name=$(printf '%s\n' "$_jrem_resolved" | sed -n 's/^name=//p')
  _jrem_status=$(printf '%s\n' "$_jrem_resolved" | sed -n 's/^status=//p')

  if [ "$_jrem_status" != "current" ] || [ -z "$_jrem_name" ]; then
    printf '%s' "$_jrem_written"
    return 0
  fi

  _jrem_pkey=$("$_jrem_config" get project_key 2>/dev/null) || _jrem_pkey=""
  if [ -z "$_jrem_pkey" ]; then
    printf '%s' "$_jrem_written"
    return 0
  fi
  if ! _jrem_mline=$("$_jrem_map" milestone-get --feature "$_jrem_feature" \
      --name "$_jrem_name" --project-key "$_jrem_pkey" 2>/dev/null); then
    printf '%s' "$_jrem_written"
    return 0
  fi
  _jrem_new_id=$(printf '%s' "$_jrem_mline" | cut -f3)
  if [ -z "$_jrem_new_id" ] || [ "$_jrem_new_id" = "$_jrem_written" ]; then
    printf '%s' "$_jrem_written"
    return 0
  fi

  _jrem_do_remove="no"
  if [ -n "$_jrem_written" ]; then
    if "$_jrem_map" milestone-id-known --feature "$_jrem_feature" \
        --project-key "$_jrem_pkey" --version-id "$_jrem_written" 2>/dev/null; then
      _jrem_do_remove="yes"
    else
      # SEC-10: marker aponta um id que o sidecar nao reconhece mais ->
      # ConflictRecord, NUNCA remocao forcada. O marco novo tambem NAO e
      # aplicado nesta passada (evita acumular 2 versoes no Epic — "nunca
      # os dois" da Clarification); o proximo drain tenta de novo apos
      # resolucao humana.
      _js_conflict_pending_exists "$_jrem_feature" "$_jrem_feature" \
        || _js_append_conflict "$_jrem_feature" "$_jrem_feature" "$_jrem_jkey" milestone_drift
      printf '%s' "$_jrem_written"
      return 0
    fi
  fi

  set -- --add-fix-version-id "$_jrem_new_id"
  [ "$_jrem_do_remove" = "yes" ] && set -- "$@" --remove-fix-version-id "$_jrem_written"
  _jrem_body=$("$_jrem_io" json-build issue-update "$@")
  _jrem_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r2fvbody.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jrem_body" > "$_jrem_body_file"
  if "$_jrem_io" request PUT "/rest/api/3/issue/$_jrem_jkey" \
      --body-file "$_jrem_body_file" --op R2 >/dev/null 2>/dev/null; then
    rm -f "$_jrem_body_file"
    printf '%s' "$_jrem_new_id"
    return 0
  fi
  _jrem_ec=$?
  rm -f "$_jrem_body_file"
  printf '%s' "$_jrem_written"
  return "$_jrem_ec"
}

# _js_cmd_milestone MODE [ARGS...] — dispatcher interno de `milestone`.
# MODE em {resolve, ensure} (16.2/16.3) — allowlist FECHADA, mesmo estilo
# de `_ji_cmd_json_build`.
_js_cmd_milestone() {
  _jsm_mode="${1:-}"
  if [ "$#" -ge 1 ]; then
    shift
  fi
  case "$_jsm_mode" in
    resolve)
      _js_cmd_milestone_resolve "$@"
      ;;
    ensure)
      _js_cmd_milestone_ensure "$@"
      ;;
    '')
      _js_die_usage "milestone requer MODE (resolve, ensure)"
      ;;
    *)
      _js_die_usage "milestone: MODE desconhecido: $_jsm_mode (validos: resolve, ensure)"
      ;;
  esac
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

# _js_build_task_description TASKS_SH FEATURE CRITICALITY PHASE — feature
# cstk-jira FASE 10 tarefa 10.1 (FR-001: Tasks devem espelhar "fases,
# dependencias e criticidade quando existirem"). So chamada para kind=task
# (data-model.md: "dependencias/criticidade entram na descricao da Task" —
# Epic/Sub-task nao carregam esses campos no LocalWorkItem). Compoe um texto
# livre simples (sem estrutura ADF alem do paragrafo unico que
# `json-build issue --description` ja monta): "Criticidade: X" e/ou
# "Depende de: FASE A; FASE B" (fonte: `jira-tasks.sh phase-deps`, unica
# fonte real de dependencia deste backlog — nunca inventa dependencia
# por-task, que a fonte nao tem). Ambos os campos sao opcionais ("quando
# existirem"): CRITICALITY vazia e/ou phase-deps vazio -> trecho
# correspondente omitido; os dois vazios -> stdout vazio (chamador NAO passa
# --description ao json-build, mantendo o corpo de R1 identico ao anterior).
_js_build_task_description() {
  _jbtd_tasks_sh="$1"
  _jbtd_feature="$2"
  _jbtd_crit="$3"
  _jbtd_phase="$4"

  _jbtd_deps=$("$_jbtd_tasks_sh" phase-deps --feature "$_jbtd_feature" --phase "$_jbtd_phase") \
    || _jbtd_deps=""
  _jbtd_deps_line=""
  if [ -n "$_jbtd_deps" ]; then
    _jbtd_deps_line=$(printf '%s' "$_jbtd_deps" | tr '\n' ';' | sed 's/;$//' | sed 's/;/; /g')
  fi

  _jbtd_out=""
  if [ -n "$_jbtd_crit" ]; then
    _jbtd_out="Criticidade: $_jbtd_crit"
  fi
  if [ -n "$_jbtd_deps_line" ]; then
    if [ -n "$_jbtd_out" ]; then
      _jbtd_out="$_jbtd_out | Depende de: $_jbtd_deps_line"
    else
      _jbtd_out="Depende de: $_jbtd_deps_line"
    fi
  fi

  printf '%s' "$_jbtd_out"
}

# _js_maybe_update_mapped_issue IO FEATURE LOCAL_KEY JIRA_KEY NEW_SUMMARY
#   NEW_DESCRIPTION — feature cstk-jira FASE 10 tarefa 10.2 (FR-003), FASE 11
# tarefa 11.3.1 (FR-011), FASE 12 tarefa 12.5.1 (achado 12.5): item JA
# mapeado (`active`) cujo titulo E/OU descricao local pode ter mudado desde
# a ultima sync — ANTES de 12.5.1, uma mudanca SO de criticidade/
# dependencias (NEW_DESCRIPTION muda, NEW_SUMMARY nao) nunca era detectada
# (early-exit so olhava o summary), entao `fields.description` nunca era
# atualizado sozinho. NEW_DESCRIPTION vazio (Epic/Sub-task, ou Task sem
# criticidade/dependencias) desliga TODA a checagem de descricao — nenhuma
# chamada extra de rede, mesmo comportamento de antes de 12.5.1. Quando
# NEW_DESCRIPTION e nao-vazio, le tambem `fields.description` (R3
# `fields=summary,status,description` — mesmo mecanismo generico de
# `fields=` ja usado para summary/status, contracts/jira-rest.md R3) e
# extrai o texto do UNICO paragrafo ADF que este plugin sempre compos
# (`_js_build_task_description`, paragrafo unico sem formatacao — uma
# descricao com estrutura ADF diferente, editada manualmente, simplesmente
# nao bate o hash abaixo e vira conflito, nunca e mal-interpretada).
# Detecta divergencia contra o SyncMarker com a MESMA logica de conflito de
# `_js_process_one_event`/4.2.3 (FR-011 — nunca sobrescrever
# silenciosamente): le titulo+status(+descricao) atuais da issue (R3) e o
# SyncMarker (R6); marker ausente (`marker_missing`) ou titulo/status
# atuais divergentes do que o plugin gravou por ultimo (`manual_edit`,
# sha256(titulo) != written_summary_sha256 OU status_atual !=
# written_status — como os dois caminhos de drain ja fazem) -> ConflictRecord
# (mesmo arquivo/fluxo de `resolve` da FASE 4.3), NUNCA escreve. Quando ha
# componente de descricao E o marker ja tem uma baseline
# (`written_description_sha256` nao-vazio — markers antigos, de antes de
# 12.5.1, ou Epic/Sub-task/Task sem descricao nunca tem essa chave), a
# descricao ATUAL tambem precisa bater o hash gravado, senao vira
# `manual_edit` (protege edicao manual da descricao no Jira, nao so do
# titulo). Marker SEM baseline de descricao (chave ausente): nenhuma
# checagem de conflito de descricao (bootstrap — a 1a atualizacao bem-
# sucedida grava o hash para as proximas). Sem conflito e NEW_SUMMARY ==
# summary atual E (sem componente de descricao OU NEW_DESCRIPTION == texto
# atual) -> nada a fazer (no-op silencioso, comum: maioria dos itens de uma
# re-conversao nao mudou; esta funcao nunca sincroniza STATUS, so conteudo).
# Havendo qualquer divergencia de conteudo (summary E/OU description) sem
# conflito -> local venceu: PUT R2 (fields.summary sempre + fields.description
# quando NEW_DESCRIPTION nao-vazio) e regrava o SyncMarker com os novos
# hashes, preservando written_status do marker anterior (esta funcao so
# muda conteudo, nunca status). Falha de rede/permissao durante a
# checagem/escrita: diagnostico em stderr, item pulado SEM abortar o
# `convert` inteiro (itens novos continuam sendo criados normalmente).
_js_maybe_update_mapped_issue() {
  _jsu_io="$1"
  _jsu_feature="$2"
  _jsu_lkey="$3"
  _jsu_jkey="$4"
  _jsu_new_summary="$5"
  _jsu_new_description="$6"

  _jsu_has_desc="no"
  [ -n "$_jsu_new_description" ] && _jsu_has_desc="yes"

  _jsu_fields="summary,status"
  [ "$_jsu_has_desc" = "yes" ] && _jsu_fields="summary,status,description"

  if _jsu_issue_resp=$("$_jsu_io" request GET "/rest/api/3/issue/$_jsu_jkey?fields=$_jsu_fields" --op R3 2>/dev/null); then
    :
  else
    printf '%s: falha ao ler issue %s para checar atualizacao (FR-003) — item pulado, mapeamento/SyncMarker inalterados\n' \
      "$_JS_NAME" "$_jsu_jkey" >&2
    return 0
  fi
  _jsu_cur_summary=$(printf '%s' "$_jsu_issue_resp" | "$_jsu_io" json-get '.fields.summary')
  _jsu_cur_status=$(printf '%s' "$_jsu_issue_resp" | "$_jsu_io" json-get '.fields.status.name')
  _jsu_cur_description=""
  if [ "$_jsu_has_desc" = "yes" ]; then
    _jsu_cur_description=$(printf '%s' "$_jsu_issue_resp" | "$_jsu_io" json-get \
      '.fields.description.content[0].content[0].text? // ""')
  fi

  # Nada mudou localmente (summary composto agora == summary atual do Jira
  # E, quando ha componente de descricao, a descricao composta agora ==
  # descricao atual do Jira) -> no-op, sem sequer ler o SyncMarker
  # (economiza 1 chamada de rede por item inalterado — o caso comum de uma
  # re-conversao). Esta funcao nunca escreve status, entao divergencia de
  # status sozinha (sem conteudo mudado) nao ha o que proteger aqui.
  _jsu_content_changed="no"
  [ "$_jsu_cur_summary" != "$_jsu_new_summary" ] && _jsu_content_changed="yes"
  if [ "$_jsu_has_desc" = "yes" ] && [ "$_jsu_cur_description" != "$_jsu_new_description" ]; then
    _jsu_content_changed="yes"
  fi
  [ "$_jsu_content_changed" = "yes" ] || return 0

  _jsu_cur_sha=$(printf '%s' "$_jsu_cur_summary" | "$_jsu_io" sha256-stdin)

  _jsu_err_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6err.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  if _jsu_prop_resp=$("$_jsu_io" request GET "/rest/api/3/issue/$_jsu_jkey/properties/$_JS_MARKER_PROPERTY_KEY" --op R6 2>"$_jsu_err_file"); then
    _jsu_prop_ec=0
  else
    _jsu_prop_ec=$?
  fi
  _jsu_prop_status=$(grep '^http_status=' "$_jsu_err_file" | tail -n 1 | cut -d= -f2)
  rm -f "$_jsu_err_file"

  if [ "$_jsu_prop_ec" -ne 0 ]; then
    printf '%s: falha ao ler SyncMarker de %s para checar atualizacao (FR-003) — item pulado, mapeamento/SyncMarker inalterados\n' \
      "$_JS_NAME" "$_jsu_jkey" >&2
    return 0
  fi

  if [ "$_jsu_prop_status" = "404" ]; then
    _js_conflict_pending_exists "$_jsu_feature" "$_jsu_lkey" \
      || _js_append_conflict "$_jsu_feature" "$_jsu_lkey" "$_jsu_jkey" marker_missing
    return 0
  fi

  _jsu_written_sha=$(printf '%s' "$_jsu_prop_resp" | "$_jsu_io" json-get '.value.written_summary_sha256')
  _jsu_written_status=$(printf '%s' "$_jsu_prop_resp" | "$_jsu_io" json-get '.value.written_status')
  _jsu_conflict="no"
  if [ "$_jsu_cur_sha" != "$_jsu_written_sha" ] || [ "$_jsu_cur_status" != "$_jsu_written_status" ]; then
    _jsu_conflict="yes"
  fi
  # 12.5.1: baseline de descricao SO existe em markers gravados por esta
  # tarefa (bootstrap — marker antigo/sem componente de descricao nunca tem
  # `written_description_sha256`, entao nao ha o que comparar ainda; a
  # atualizacao segue pelo caminho normal e estabelece a baseline abaixo).
  _jsu_written_desc_sha=""
  if [ "$_jsu_has_desc" = "yes" ]; then
    _jsu_written_desc_sha=$(printf '%s' "$_jsu_prop_resp" | "$_jsu_io" json-get '.value.written_description_sha256? // ""')
    if [ -n "$_jsu_written_desc_sha" ]; then
      _jsu_cur_desc_sha=$(printf '%s' "$_jsu_cur_description" | "$_jsu_io" sha256-stdin)
      [ "$_jsu_cur_desc_sha" != "$_jsu_written_desc_sha" ] && _jsu_conflict="yes"
    fi
  fi
  if [ "$_jsu_conflict" = "yes" ]; then
    # FR-011 (11.3.1/12.5.1): titulo E/OU status E/OU descricao no Jira ja
    # divergem do que o plugin gravou por ultimo (edicao/transicao manual
    # desde a ultima sync) -> conflito, NUNCA sobrescrever silenciosamente,
    # mesmo que o conteudo local tambem tenha mudado — mesma condicao (sha
    # OU status) que os dois caminhos de drain ja aplicam
    # (`_js_process_one_event`/`_js_process_reconcile_event`), estendida
    # aqui ao hash da descricao quando ha baseline.
    _js_conflict_pending_exists "$_jsu_feature" "$_jsu_lkey" \
      || _js_append_conflict "$_jsu_feature" "$_jsu_lkey" "$_jsu_jkey" manual_edit
    return 0
  fi

  # Seguro: titulo, status e (quando ha baseline) descricao no Jira sao
  # EXATAMENTE o que o plugin gravou por ultimo — a divergencia e so local
  # -> local vence. R2 (so os campos que mudam; description sempre que
  # NEW_DESCRIPTION for nao-vazio, mesmo que so ELA tenha mudado).
  set -- issue-update --summary "$_jsu_new_summary"
  if [ -n "$_jsu_new_description" ]; then
    set -- "$@" --description "$_jsu_new_description"
  fi
  _jsu_body=$("$_jsu_io" json-build "$@")
  _jsu_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r2body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jsu_body" > "$_jsu_body_file"
  if "$_jsu_io" request PUT "/rest/api/3/issue/$_jsu_jkey" \
      --body-file "$_jsu_body_file" --op R2 >/dev/null 2>/dev/null; then
    rm -f "$_jsu_body_file"
  else
    _jsu_ec=$?
    rm -f "$_jsu_body_file"
    printf '%s: falha ao atualizar summary de %s via R2 (exit %s) — mapeamento/SyncMarker inalterados, tentar novamente na proxima convert\n' \
      "$_JS_NAME" "$_jsu_jkey" "$_jsu_ec" >&2
    return 0
  fi

  # Regravar o SyncMarker com o(s) novo(s) hash(es) — written_status
  # PRESERVADO (esta funcao nunca muda status, so conteudo; status e
  # responsabilidade exclusiva de drain/_js_process_one_event). 12.5.1:
  # quando ha componente de descricao, grava tambem
  # `written_description_sha256` do NOVO texto — estabelece/atualiza a
  # baseline para a proxima checagem (bootstrap de markers antigos sem essa
  # chave incluido: a partir daqui passam a te-la). Mesma limitacao aceita
  # de _js_process_one_event: se este PUT falhar apos o R2 ja aplicado, a
  # proxima checagem pode reportar manual_edit indevido ate o operador
  # `resolve --choice keep_jira`.
  _jsu_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _jsu_new_sha=$(printf '%s' "$_jsu_new_summary" | "$_jsu_io" sha256-stdin)
  set -- --local-key "$_jsu_lkey" --feature "$_jsu_feature" \
    --written-summary-sha256 "$_jsu_new_sha" --written-status "$_jsu_written_status" --written-at "$_jsu_now"
  if [ -n "$_jsu_new_description" ]; then
    _jsu_new_desc_sha=$(printf '%s' "$_jsu_new_description" | "$_jsu_io" sha256-stdin)
    set -- "$@" --written-description-sha256 "$_jsu_new_desc_sha"
  fi
  _jsu_marker_body=$("$_jsu_io" json-build marker "$@")
  _jsu_marker_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jsu_marker_body" > "$_jsu_marker_body_file"
  if "$_jsu_io" request PUT "/rest/api/3/issue/$_jsu_jkey/properties/$_JS_MARKER_PROPERTY_KEY" \
      --body-file "$_jsu_marker_body_file" --op R6 >/dev/null 2>/dev/null; then
    rm -f "$_jsu_marker_body_file"
  else
    rm -f "$_jsu_marker_body_file"
    printf '%s: summary de %s atualizado mas falha ao regravar SyncMarker — proxima checagem pode reportar manual_edit indevido (resolve --choice keep_jira destrava)\n' \
      "$_JS_NAME" "$_jsu_jkey" >&2
  fi
  return 0
}

# _js_write_initial_marker IO FEATURE LOCAL_KEY JIRA_KEY SUMMARY
#   [DESCRIPTION] [FIX_VERSION_ID] — feature cstk-jira FASE 11 tarefa 11.1.1 (FR-011,
# plan.md Fluxo 2 "Convert" grava SyncMarker; data-model.md: "Gravado em
# cada issue sincronizada"). Sem isto, o 1o `drain` de qualquer issue
# recem-criada lia R6=404 e virava `marker_missing` (ConflictRecord) em
# vez de transicionar (converge FASE 11 achado 11.1). `fields.summary`/
# `fields.status` de R1 (sucesso) so tem `id`/`key`/`self`
# (contracts/jira-rest.md R1) — o status inicial NAO vem da resposta de
# criacao, exige R3 dedicado (fields=status; o summary ja e conhecido: e
# exatamente SUMMARY, o que este script acabou de enviar no corpo de R1 —
# sem round-trip, mesma fonte que os R6 PUT de
# `_js_process_one_event`/`_js_maybe_update_mapped_issue` usam para o
# hash). DESCRIPTION (FASE 12 tarefa 12.5.1, opcional — so `kind=task` com
# criticidade/dependencias): quando nao-vazio, grava tambem
# `written_description_sha256` no marker, estabelecendo a baseline que
# `_js_maybe_update_mapped_issue` compara depois; description ja foi
# enviada tal-e-qual no corpo de R1 (mesma fonte, sem round-trip). Falha em
# R3 ou no R6 PUT: diagnostico em stderr, retorna 0 SEM abortar `convert`
# nem desfazer a criacao (issue e jira-map.tsv ja gravados) — a proxima
# `drain` detecta o SyncMarker ausente (404) e reporta `marker_missing`, o
# mesmo efeito de um R6 PUT que tivesse falhado aqui. FIX_VERSION_ID (r02
# FASE 16 task 16.4.1, opcional — so quando o chamador aplicou um marco
# NESTA criacao E o item e o Epic, data-model.md SyncMarker
# `written_fix_version_id`: "so no Epic"): quando nao-vazio, grava tambem
# `written_fix_version_id` no marker, estabelecendo a baseline que
# `_js_reconcile_epic_milestone` compara depois.
_js_write_initial_marker() {
  _jwim_io="$1"
  _jwim_feature="$2"
  _jwim_lkey="$3"
  _jwim_jkey="$4"
  _jwim_summary="$5"
  _jwim_description="${6:-}"
  _jwim_fix_version_id="${7:-}"

  if _jwim_issue_resp=$("$_jwim_io" request GET "/rest/api/3/issue/$_jwim_jkey?fields=status" --op R3 2>/dev/null); then
    :
  else
    printf '%s: falha ao ler status inicial de %s para gravar o SyncMarker (FR-011) — issue criada mas SyncMarker ausente; a proxima drain vai reportar marker_missing\n' \
      "$_JS_NAME" "$_jwim_jkey" >&2
    return 0
  fi
  _jwim_status=$(printf '%s' "$_jwim_issue_resp" | "$_jwim_io" json-get '.fields.status.name')

  _jwim_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _jwim_sha=$(printf '%s' "$_jwim_summary" | "$_jwim_io" sha256-stdin)
  set -- --local-key "$_jwim_lkey" --feature "$_jwim_feature" \
    --written-summary-sha256 "$_jwim_sha" --written-status "$_jwim_status" --written-at "$_jwim_now"
  if [ -n "$_jwim_description" ]; then
    _jwim_desc_sha=$(printf '%s' "$_jwim_description" | "$_jwim_io" sha256-stdin)
    set -- "$@" --written-description-sha256 "$_jwim_desc_sha"
  fi
  if [ -n "$_jwim_fix_version_id" ]; then
    set -- "$@" --written-fix-version-id "$_jwim_fix_version_id"
  fi
  _jwim_marker_body=$("$_jwim_io" json-build marker "$@")
  _jwim_marker_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jwim_marker_body" > "$_jwim_marker_body_file"
  if "$_jwim_io" request PUT "/rest/api/3/issue/$_jwim_jkey/properties/$_JS_MARKER_PROPERTY_KEY" \
      --body-file "$_jwim_marker_body_file" --op R6 >/dev/null 2>/dev/null; then
    rm -f "$_jwim_marker_body_file"
  else
    _jwim_ec=$?
    rm -f "$_jwim_marker_body_file"
    printf '%s: issue %s criada mas falha ao gravar o SyncMarker inicial (R6 PUT, exit %s) — a proxima drain/reconcile vai reportar marker_missing (conflito); destravar com resolve --choice keep_jira\n' \
      "$_JS_NAME" "$_jwim_jkey" "$_jwim_ec" >&2
  fi
  return 0
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

  # r02 FASE 16 task 16.4.1 (research.md Decision R2-2/R2-3/R2-4): antes da
  # 1a criacao, garante o marco (Fix Version) corrente via `milestone
  # ensure` — SO quando milestone_mode=auto (default). `milestone ensure`
  # ja e no-op de rede quando o marco nao esta resolvido (off/unresolved).
  # Chamado DIRETO (nao via subshell) seria a forma mais simples, mas
  # precisamos capturar name=/status= mesmo quando a funcao termina com
  # `exit 7` (blocked) — por isso via `$(...)`: o `exit` so derruba o
  # SUBSHELL da substituicao, preservando o stdout ja impresso ANTES do
  # exit e o exit code em `$?` (mesmo padrao de captura sem negacao usado
  # no resto do arquivo).
  _jsc_milestone_mode=$("$_jsc_config" get milestone_mode 2>/dev/null) || _jsc_milestone_mode="auto"
  [ -n "$_jsc_milestone_mode" ] || _jsc_milestone_mode="auto"
  _jsc_milestone_name=""
  _jsc_milestone_status=""
  _jsc_milestone_id=""
  if [ "$_jsc_milestone_mode" = "auto" ]; then
    # `|| :` — a mesma tecnica de _js_cmd_status abaixo: sob `set -e`, um
    # exit nao-zero (blocked=7, deferred=1) dentro da substituicao NAO deve
    # abortar `convert` aqui (a decisao de abortar so acontece mais abaixo,
    # por item, quando o marco esta de fato blocked e ha item novo a criar).
    _jsc_milestone_resolved=$(_js_cmd_milestone_ensure --feature "$_jsc_feature") || :
    _jsc_milestone_name=$(printf '%s\n' "$_jsc_milestone_resolved" | sed -n 's/^name=//p')
    _jsc_milestone_status=$(printf '%s\n' "$_jsc_milestone_resolved" | sed -n 's/^status=//p')
    if [ "$_jsc_milestone_status" = "current" ] && [ -n "$_jsc_milestone_name" ]; then
      if _jsc_milestone_line=$("$_jsc_map" milestone-get --feature "$_jsc_feature" \
          --name "$_jsc_milestone_name" --project-key "$_jsc_project_key" 2>/dev/null); then
        _jsc_milestone_id=$(printf '%s' "$_jsc_milestone_line" | cut -f3)
      fi
    fi
  fi
  _jsc_fix_versions_on_subtask=$("$_jsc_config" get fix_versions_on_subtask 2>/dev/null) \
    || _jsc_fix_versions_on_subtask="off"
  [ -n "$_jsc_fix_versions_on_subtask" ] || _jsc_fix_versions_on_subtask="off"

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
    _jsc_crit=$(printf '%s' "$_jsc_line" | cut -f4)
    _jsc_title=$(printf '%s' "$_jsc_line" | cut -f6)

    # Idempotencia (FR-014/SC-002): local_key ja presente no mapeamento
    # (active OU orphan) -> NENHUMA chamada de criacao. `orphan` pula de
    # imediato (removido/renumerado — religar e decisao humana explicita via
    # `jira-map.sh relink`, FASE 4.3/4.4, nunca uma atualizacao automatica
    # aqui). `active` segue para compor summary/description (case abaixo) e
    # so entao decide criar vs. atualizar (FR-003, feature cstk-jira FASE 10
    # tarefa 10.2 — ver _js_maybe_update_mapped_issue).
    _jsc_map_line=""
    _jsc_already_mapped="no"
    if _jsc_map_line=$("$_jsc_map" get --feature "$_jsc_feature" --local-key "$_jsc_key" 2>/dev/null); then
      _jsc_already_mapped="yes"
      _jsc_mapped_state=$(printf '%s' "$_jsc_map_line" | cut -f5)
      if [ "$_jsc_mapped_state" = "orphan" ]; then
        continue
      fi
    fi

    _jsc_parent_key=""
    _jsc_description=""
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
        # FR-001: descricao da Task com criticidade e dependencias, quando
        # existirem (feature cstk-jira FASE 10 tarefa 10.1) — ver
        # _js_build_task_description acima.
        _jsc_description=$(_js_build_task_description "$_jsc_tasks" "$_jsc_feature" \
          "$_jsc_crit" "$_jsc_phase")
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

    # FR-003 (feature cstk-jira FASE 10 tarefa 10.2): item JA mapeado
    # (`active`) -> NENHUMA criacao; delega a checagem de divergencia/
    # atualizacao (R2, respeitando FR-011) a _js_maybe_update_mapped_issue e
    # segue para o proximo item.
    if [ "$_jsc_already_mapped" = "yes" ]; then
      _jsc_mapped_jkey=$(printf '%s' "$_jsc_map_line" | cut -f4)
      _js_maybe_update_mapped_issue "$_jsc_io" "$_jsc_feature" "$_jsc_key" "$_jsc_mapped_jkey" \
        "$_jsc_summary" "$_jsc_description"
      continue
    fi

    # r02 FASE 16 task 16.4.1 (research.md Decision R2-4): marco blocked
    # (permission_denied ao tentar criar a Fix Version) SUSPENDE a criacao
    # de itens NOVOS desta feature — transicoes de issues JA mapeadas (ramo
    # acima) nao dependem do marco e continuam normalmente.
    if [ "$_jsc_milestone_status" = "blocked" ]; then
      _js_die "marco de Fix Version bloqueado (permission_denied, R2-4) — criacao de itens novos suspensa para $_jsc_key; ajuste a credencial (Administer Jira/Administer Projects) ou defina milestone_mode=off" 7
    fi

    # r02 FASE 16 task 16.4.1 (research.md Decision R2-2): Epic e Task
    # recebem o marco corrente SEMPRE que resolvido ("quando aplicavel" de
    # FR-020); Sub-task so quando fix_versions_on_subtask=on (campo
    # presente na tela de criacao do tipo Sub-task, R8/setup).
    _jsc_apply_fixver=""
    if [ -n "$_jsc_milestone_id" ]; then
      case "$_jsc_kind" in
        epic|task) _jsc_apply_fixver="$_jsc_milestone_id" ;;
        subtask)
          [ "$_jsc_fix_versions_on_subtask" = "on" ] && _jsc_apply_fixver="$_jsc_milestone_id"
          ;;
      esac
    fi

    set -- --project-id "$_jsc_project_id" --issuetype-id "$_jsc_issuetype_id" \
      --summary "$_jsc_summary"
    if [ -n "$_jsc_parent_key" ]; then
      set -- "$@" --parent-key "$_jsc_parent_key"
    fi
    if [ -n "$_jsc_description" ]; then
      set -- "$@" --description "$_jsc_description"
    fi
    if [ -n "$_jsc_apply_fixver" ]; then
      set -- "$@" --fix-version-id "$_jsc_apply_fixver"
    fi
    _jsc_body=$("$_jsc_io" json-build issue "$@")

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

    # 11.1.1 (FR-011): SyncMarker inicial — sem isto, o 1o drain desta issue
    # leria R6=404 e cairia em marker_missing. r02 FASE 16 task 16.4.1/16.4.2
    # (data-model.md SyncMarker `written_fix_version_id`: "so no Epic",
    # R2-2) — Task/Sub-task recebem o marco na CRIACAO mas NUNCA carregam
    # `written_fix_version_id` no marker (nunca sao remarcadas depois).
    _jsc_marker_fixver=""
    [ "$_jsc_kind" = "epic" ] && _jsc_marker_fixver="$_jsc_apply_fixver"
    _js_write_initial_marker "$_jsc_io" "$_jsc_feature" "$_jsc_key" "$_jsc_new_key" \
      "$_jsc_summary" "$_jsc_description" "$_jsc_marker_fixver"
  done
}

# --- outcomes (FASE 12 tarefa 12.4.1) -------------------------------------

# _js_set_task_outcome FEATURE TASK_ID OUTCOME — upsert (mesmo padrao
# tmp+mv de `_js_set_retry_after`) da linha `feature\ttask_id\toutcome` no
# sidecar `_JS_OUTCOMES_FILE`, substituindo qualquer linha anterior do
# MESMO (feature, task_id) — so o outcome MAIS RECENTE importa (um
# record_task posterior sempre vence).
_js_set_task_outcome() {
  _jsto_feature="$1"
  _jsto_tid="$2"
  _jsto_outcome="$3"
  _jsto_dir=$(dirname -- "$_JS_OUTCOMES_FILE")
  mkdir -p "$_jsto_dir" || _js_die "falha ao criar diretorio runtime: $_jsto_dir" 1
  _jsto_tmp="$_JS_OUTCOMES_FILE.tmp.$$"
  {
    if [ -f "$_JS_OUTCOMES_FILE" ]; then
      awk -F '\t' -v f="$_jsto_feature" -v t="$_jsto_tid" \
        'NR == 1 || !($1 == f && $2 == t) { print }' "$_JS_OUTCOMES_FILE"
    else
      printf '%s\n' "$_JS_OUTCOMES_HEADER"
    fi
    printf '%s\t%s\t%s\n' "$_jsto_feature" "$_jsto_tid" "$_jsto_outcome"
  } > "$_jsto_tmp"
  mv -- "$_jsto_tmp" "$_JS_OUTCOMES_FILE"
}

# _js_outcomes_file_for_feature FEATURE -> imprime o path de um arquivo
# temporario (formato TASK_ID\tOUTCOME, 2 colunas, sem cabecalho — o unico
# formato que `jira-tasks.sh items --outcomes-file` exige) com as linhas do
# sidecar global `_JS_OUTCOMES_FILE` filtradas para FEATURE. Sempre cria o
# arquivo (mesmo vazio, quando a feature nao tem nenhum outcome persistido
# ou o sidecar global ainda nao existe) para o chamador poder passar
# `--outcomes-file` incondicionalmente, sem ramificar. Chamador MUST
# remover o arquivo retornado apos o uso (mktemp, nunca limpo
# automaticamente por esta funcao).
_js_outcomes_file_for_feature() {
  _jsoff_feature="$1"
  _jsoff_tmp=$(mktemp "${TMPDIR:-/tmp}/jira-sync-outcomes.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  if [ -f "$_JS_OUTCOMES_FILE" ]; then
    awk -F '\t' -v f="$_jsoff_feature" \
      'NR > 1 && $1 == f { print $2 "\t" $3 }' "$_JS_OUTCOMES_FILE" > "$_jsoff_tmp"
  fi
  printf '%s\n' "$_jsoff_tmp"
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

  # 12.4.1: outcome direto de record_task (pass/fail, local_key != '*')
  # ganha precedencia sobre os checkboxes na PROXIMA reconciliacao
  # (`_js_process_reconcile_event` filtra este sidecar via
  # `_js_outcomes_file_for_feature`) — nunca para o evento `*`
  # (reconciliacao inteira da feature, que nao carrega um task_id real).
  # task 13.3.1: gravado SOMENTE para --source hook-record-task — o unico
  # source que carrega um outcome REAL de `record_task`/`record-task`
  # (LocalWorkItem outcome precedence, data-model.md). `enqueue --source
  # manual --state pass|fail` (usado por `resolve --choice overwrite` para
  # reenfileirar um desired_state ja derivado — nao um outcome novo) e
  # `hook-close-wave` (reconciliacao `local_key=*`, sempre filtrado acima)
  # NUNCA devem gravar aqui — antes desta correcao, um `overwrite` ou
  # qualquer `enqueue --source manual --state pass|fail` avulso sobrepunha
  # em silencio o outcome REAL da ultima `record_task`, invertendo a
  # precedencia que 12.4.1 existe para garantir.
  case "$_jse_state" in
    pass|fail)
      if [ "$_jse_key" != "*" ] && [ "$_jse_source" = "hook-record-task" ]; then
        _js_set_task_outcome "$_jse_feature" "$_jse_key" "$_jse_state"
      fi
      ;;
  esac

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
# _js_process_reconcile_event EID ATTEMPTS — FASE 10 tarefa 10.3 (FR-004,
# US3 cenario 1): expande um OutboxEvent `local_key=*` (reconciliacao da
# feature inteira, enfileirado pelo hook a cada `close_wave`) num item por
# LocalWorkItem (`jira-tasks.sh items --feature F`, `local_state` ja
# derivado — Epic + Tasks + Sub-tasks) e processa CADA item ja mapeado
# (`active` em `jira-map.tsv`) pelo mesmo nucleo R3/R6-GET/conflito/R5/R4/
# R6-PUT usado por um evento direto (duplicado aqui de proposito, prefixo
# `_jspr_`, em vez de refatorar `_js_process_one_event` — reduz o raio de
# regressao sobre os cenarios ja cobertos de evento direto). Item sem
# mapeamento (ainda nao convertido) e item mapeado `orphan` sao tratados
# como em `_js_process_one_event` (orphan vira ConflictRecord). Idempotente:
# item ja no status alvo nao gera R4. Conflito em um item NUNCA impede o
# processamento dos demais (ConflictRecord por item, FR-011) — so
# `auth_failed` interrompe TODA a reconciliacao (mesmo gate FR-016,
# `_JSPE_BREAK`). Loop sobre um ARQUIVO (nao um pipe) para os itens — mesmo
# motivo documentado em `_js_cmd_drain`: um `while read` num pipe roda em
# subshell POSIX, o que perderia `_JSPE_BREAK`/`_jspr_had_deferred` ao
# sair do loop. FASE 12 tarefa 12.4.1: `jira-tasks.sh items` e chamado com
# `--outcomes-file` (sidecar `_JS_OUTCOMES_FILE`, filtrado para
# `$_jsd_feature` via `_js_outcomes_file_for_feature`) — o outcome mais
# recente de `record_task` tem precedencia sobre os checkboxes agregados
# (data-model.md LocalWorkItem outcome precedence), evitando que esta
# reconciliacao desfizesse o outcome que o proprio record_task acabou de
# levar ao Jira.
_js_process_reconcile_event() {
  _jspr_eid="$1"
  _jspr_attempts="$2"

  # 12.4.1: outcome de record_task (sidecar `_JS_OUTCOMES_FILE`, filtrado
  # para esta feature) tem precedencia sobre os checkboxes na derivacao de
  # `local_state` (`jira-tasks.sh items --outcomes-file`, kind=task) — sem
  # isto, esta reconciliacao podia desfazer o outcome que o proprio
  # record_task acabou de levar ao Jira (achado 12.4).
  # 12.8.1: `--stage` (etapa corrente, READ-ONLY via `_js_resolve_stage`)
  # habilita `stage_status.<stage>` (data-model.md ProjectConfig / US2
  # cenario 1) para o Epic — omitido quando nao ha execucao ativa legivel
  # (mesmo efeito de "nao configurado" em `jira-tasks.sh items`).
  _jspr_outcomes_file=$(_js_outcomes_file_for_feature "$_jsd_feature")
  _jspr_stage=$(_js_resolve_stage "$_jsd_feature")
  if [ -n "$_jspr_stage" ]; then
    _jspr_items=$("$_jsd_tasks" items --feature "$_jsd_feature" \
      --outcomes-file "$_jspr_outcomes_file" --stage "$_jspr_stage" 2>/dev/null)
    _jspr_items_ok=$?
  else
    _jspr_items=$("$_jsd_tasks" items --feature "$_jsd_feature" \
      --outcomes-file "$_jspr_outcomes_file" 2>/dev/null)
    _jspr_items_ok=$?
  fi
  if [ "$_jspr_items_ok" -ne 0 ]; then
    rm -f "$_jspr_outcomes_file"
    printf '%s: jira-tasks.sh items falhou para %s — evento %s permanece na fila\n' \
      "$_JS_NAME" "$_jsd_feature" "$_jspr_eid" >&2
    return 0
  fi
  rm -f "$_jspr_outcomes_file"

  _jspr_items_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-reconcile-items.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s\n' "$_jspr_items" > "$_jspr_items_file"

  _jspr_had_deferred="no"

  while IFS= read -r _jspr_line; do
    [ -n "$_jspr_line" ] || continue
    _jspr_lkey=$(printf '%s' "$_jspr_line" | cut -f1)
    _jspr_kind=$(printf '%s' "$_jspr_line" | cut -f2)
    _jspr_lstate=$(printf '%s' "$_jspr_line" | cut -f5)

    # Item sem mapeamento (ainda nao convertido): nada a reconciliar no
    # Jira, ignorado silenciosamente (so itens `active` tem issue criada).
    if ! _jspr_mline=$("$_jsd_map" get --feature "$_jsd_feature" --local-key "$_jspr_lkey" 2>/dev/null); then
      continue
    fi
    _jspr_jkey=$(printf '%s' "$_jspr_mline" | cut -f4)
    _jspr_mstate=$(printf '%s' "$_jspr_mline" | cut -f5)

    # 4.4 (FR-012): orfao nunca e sobrescrito — vira ConflictRecord, mas
    # NUNCA interrompe os demais itens (FR-011 e por item, nao global).
    if [ "$_jspr_mstate" = "orphan" ]; then
      _js_conflict_pending_exists "$_jsd_feature" "$_jspr_lkey" \
        || _js_append_conflict "$_jsd_feature" "$_jspr_lkey" "$_jspr_jkey" orphan
      continue
    fi

    case "$_jspr_lstate" in
      pending)     _jspr_target="$_jsd_status_pending" ;;
      in_progress) _jspr_target="$_jsd_status_in_progress" ;;
      pass)        _jspr_target="$_jsd_status_pass" ;;
      fail)        _jspr_target="$_jsd_status_fail" ;;
      *)
        # 12.8.1 (data-model.md ProjectConfig stage_status.<stage> / US2
        # cenario 1): quando `--stage` foi passado acima E o item e o Epic
        # (kind=epic), um local_state fora do enum pending/in_progress/
        # pass/fail e o VALOR do override — nome de status Jira REAL
        # escolhido pelo operador em jira-setup (`jira-tasks.sh items`
        # END{} "epic_state = stage_override"), nunca um erro. Tratar como
        # status alvo DIRETO (sem passar pelo mapeamento pending/
        # in_progress/pass/fail -> status_*). Qualquer outro kind com
        # local_state fora do enum nunca deveria ocorrer (tasks/subtasks
        # so saem de jira-tasks.sh com um dos 4 enums) — permanece
        # ignorado.
        if [ "$_jspr_kind" = "epic" ] && [ -n "$_jspr_lstate" ]; then
          _jspr_target="$_jspr_lstate"
        else
          continue
        fi
        ;;
    esac

    # R3 — titulo + status atuais (mesma disciplina de captura de $? sem
    # negacao de _js_process_one_event/8.3.1-8.3.2: "if CMD; then ok; else
    # _ec=$?; ..." preserva o exit code genuino de jira-io.sh).
    if _jspr_issue_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspr_jkey?fields=summary,status" --op R3 2>/dev/null); then
      :
    else
      _jspr_ec=$?
      if [ "$_jspr_ec" -eq 4 ]; then
        _JSPE_BREAK="yes"
        break
      fi
      _jspr_had_deferred="yes"
      continue
    fi
    _jspr_cur_summary=$(printf '%s' "$_jspr_issue_resp" | "$_jsd_io" json-get '.fields.summary')
    _jspr_cur_status=$(printf '%s' "$_jspr_issue_resp" | "$_jsd_io" json-get '.fields.status.name')
    _jspr_cur_sha=$(printf '%s' "$_jspr_cur_summary" | "$_jsd_io" sha256-stdin)

    # R6 GET — SyncMarker (mesmo padrao de http_status via stderr: 404 puro
    # e sucesso do ponto de vista de jira-io.sh, so o http_status distingue).
    _jspr_err_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6err.XXXXXX") \
      || _js_die "falha ao criar arquivo temporario" 1
    if _jspr_prop_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspr_jkey/properties/$_JS_MARKER_PROPERTY_KEY" --op R6 2>"$_jspr_err_file"); then
      _jspr_prop_ec=0
    else
      _jspr_prop_ec=$?
    fi
    _jspr_prop_status=$(grep '^http_status=' "$_jspr_err_file" | tail -n 1 | cut -d= -f2)
    rm -f "$_jspr_err_file"

    if [ "$_jspr_prop_ec" -ne 0 ]; then
      if [ "$_jspr_prop_ec" -eq 4 ]; then
        _JSPE_BREAK="yes"
        break
      fi
      _jspr_had_deferred="yes"
      continue
    fi

    _jspr_conflict="no"
    _jspr_conflict_reason=""
    if [ "$_jspr_prop_status" = "404" ]; then
      _jspr_conflict="yes"
      _jspr_conflict_reason="marker_missing"
    else
      _jspr_written_sha=$(printf '%s' "$_jspr_prop_resp" | "$_jsd_io" json-get '.value.written_summary_sha256')
      _jspr_written_status=$(printf '%s' "$_jspr_prop_resp" | "$_jsd_io" json-get '.value.written_status')
      # task 13.2.1 (FR-011 / data-model SyncMarker written_description_sha256):
      # carrega adiante a baseline de descricao ja lida (R6 GET acima) para
      # o R6 PUT desta transicao de status NUNCA apagar a protecao contra
      # sobrescrita de descricao editada manualmente no Jira (o PUT
      # substitui o valor inteiro da propriedade — sem isto, a proxima
      # `convert` tratava a ausencia da chave como "sem baseline" e
      # sobrescrevia a descricao em silencio).
      _jspr_written_desc_sha=$(printf '%s' "$_jspr_prop_resp" | "$_jsd_io" json-get '.value.written_description_sha256? // ""')
      # r02 FASE 16 task 16.4.2 (data-model.md SyncMarker
      # `written_fix_version_id`, "so no Epic"): carrega adiante a baseline
      # atual — mesma disciplina de `written_description_sha256` acima (o
      # R6 PUT substitui o valor inteiro da propriedade).
      _jspr_written_fixver=$(printf '%s' "$_jspr_prop_resp" | "$_jsd_io" json-get '.value.written_fix_version_id? // ""')
      if [ "$_jspr_cur_sha" != "$_jspr_written_sha" ] || [ "$_jspr_cur_status" != "$_jspr_written_status" ]; then
        _jspr_conflict="yes"
        _jspr_conflict_reason="manual_edit"
      fi
    fi

    if [ "$_jspr_conflict" = "yes" ]; then
      _js_conflict_pending_exists "$_jsd_feature" "$_jspr_lkey" \
        || _js_append_conflict "$_jsd_feature" "$_jspr_lkey" "$_jspr_jkey" "$_jspr_conflict_reason"
      continue
    fi

    # r02 FASE 16 task 16.4.2 (research.md Decision R2-2): reaplica o marco
    # CORRENTE ao Epic, independente do status alvo — roda ANTES da
    # idempotencia de status porque o marco pode mudar (round r01 -> r02)
    # mesmo quando o Epic ja esta no status alvo (idempotencia de status e
    # idempotencia de marco sao dimensoes independentes).
    _jspr_milestone_changed="no"
    if [ "$_jspr_kind" = "epic" ]; then
      _jspr_new_fixver=$(_js_reconcile_epic_milestone "$_jsd_feature" "$_jspr_jkey" "${_jspr_written_fixver:-}")
      if [ "$_jspr_new_fixver" != "${_jspr_written_fixver:-}" ]; then
        _jspr_written_fixver="$_jspr_new_fixver"
        _jspr_milestone_changed="yes"
      fi
    fi

    # Idempotencia (FR-004/10.3): ja no status alvo E sem mudanca de marco
    # -> no-op, sem R5/R4/R6-PUT. Marco mudou mas status ja e o alvo -> so
    # regrava o marker (sem R4/R5) com o written_fix_version_id novo.
    if [ "$_jspr_cur_status" = "$_jspr_target" ]; then
      if [ "$_jspr_milestone_changed" != "yes" ]; then
        continue
      fi
      _jspr_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      set -- marker --local-key "$_jspr_lkey" --feature "$_jsd_feature" \
        --written-summary-sha256 "$_jspr_cur_sha" --written-status "$_jspr_cur_status" --written-at "$_jspr_now"
      [ -n "${_jspr_written_desc_sha:-}" ] && set -- "$@" --written-description-sha256 "$_jspr_written_desc_sha"
      [ -n "${_jspr_written_fixver:-}" ] && set -- "$@" --written-fix-version-id "$_jspr_written_fixver"
      _jspr_marker_body=$("$_jsd_io" json-build "$@")
      _jspr_marker_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6body.XXXXXX") \
        || _js_die "falha ao criar arquivo temporario" 1
      printf '%s' "$_jspr_marker_body" > "$_jspr_marker_body_file"
      if "$_jsd_io" request PUT "/rest/api/3/issue/$_jspr_jkey/properties/$_JS_MARKER_PROPERTY_KEY" \
          --body-file "$_jspr_marker_body_file" --op R6 >/dev/null 2>/dev/null; then
        rm -f "$_jspr_marker_body_file"
      else
        _jspr_ec=$?
        rm -f "$_jspr_marker_body_file"
        if [ "$_jspr_ec" -eq 4 ]; then
          _JSPE_BREAK="yes"
          break
        fi
        _jspr_had_deferred="yes"
      fi
      continue
    fi

    # R5 — resolver transition.id cujo to.name bate o status alvo.
    if _jspr_trans_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspr_jkey/transitions" --op R5 2>/dev/null); then
      :
    else
      _jspr_ec=$?
      if [ "$_jspr_ec" -eq 4 ]; then
        _JSPE_BREAK="yes"
        break
      fi
      _jspr_had_deferred="yes"
      continue
    fi
    _jspr_trans_tsv=$(printf '%s' "$_jspr_trans_resp" | "$_jsd_io" json-get '.transitions[] | [.id, .to.name] | @tsv')
    _jspr_trans_id=$(printf '%s\n' "$_jspr_trans_tsv" | awk -F '\t' -v want="$_jspr_target" '$2 == want { print $1; exit }')
    if [ -z "$_jspr_trans_id" ]; then
      printf '%s: nenhuma transicao disponivel para o status alvo "%s" na issue %s (item %s) — reconciliacao segue para os demais itens\n' \
        "$_JS_NAME" "$_jspr_target" "$_jspr_jkey" "$_jspr_lkey" >&2
      continue
    fi

    # R4 — executar a transicao.
    _jspr_trans_body=$("$_jsd_io" json-build transition --transition-id "$_jspr_trans_id")
    _jspr_trans_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r4body.XXXXXX") \
      || _js_die "falha ao criar arquivo temporario" 1
    printf '%s' "$_jspr_trans_body" > "$_jspr_trans_body_file"
    if "$_jsd_io" request POST "/rest/api/3/issue/$_jspr_jkey/transitions" \
        --body-file "$_jspr_trans_body_file" --op R4 >/dev/null 2>/dev/null; then
      rm -f "$_jspr_trans_body_file"
    else
      _jspr_ec=$?
      rm -f "$_jspr_trans_body_file"
      if [ "$_jspr_ec" -eq 4 ]; then
        _JSPE_BREAK="yes"
        break
      fi
      _jspr_had_deferred="yes"
      continue
    fi

    # R6 PUT — regravar o SyncMarker com o novo written_status/sha256.
    # task 13.2.1: preserva `written_description_sha256` (lido acima do
    # marker atual) — o PUT substitui o valor inteiro da propriedade, entao
    # omiti-lo apagaria a baseline de protecao da descricao. task 16.4.2:
    # mesma disciplina para `written_fix_version_id` (ja atualizado acima
    # por `_js_reconcile_epic_milestone`, se aplicavel).
    _jspr_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    set -- marker --local-key "$_jspr_lkey" --feature "$_jsd_feature" \
      --written-summary-sha256 "$_jspr_cur_sha" --written-status "$_jspr_target" --written-at "$_jspr_now"
    [ -n "${_jspr_written_desc_sha:-}" ] && set -- "$@" --written-description-sha256 "$_jspr_written_desc_sha"
    [ -n "${_jspr_written_fixver:-}" ] && set -- "$@" --written-fix-version-id "$_jspr_written_fixver"
    _jspr_marker_body=$("$_jsd_io" json-build "$@")
    _jspr_marker_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6body.XXXXXX") \
      || _js_die "falha ao criar arquivo temporario" 1
    printf '%s' "$_jspr_marker_body" > "$_jspr_marker_body_file"
    if "$_jsd_io" request PUT "/rest/api/3/issue/$_jspr_jkey/properties/$_JS_MARKER_PROPERTY_KEY" \
        --body-file "$_jspr_marker_body_file" --op R6 >/dev/null 2>/dev/null; then
      rm -f "$_jspr_marker_body_file"
    else
      _jspr_ec=$?
      rm -f "$_jspr_marker_body_file"
      if [ "$_jspr_ec" -eq 4 ]; then
        _JSPE_BREAK="yes"
        break
      fi
      _jspr_had_deferred="yes"
    fi
  done < "$_jspr_items_file"
  rm -f "$_jspr_items_file"

  if [ "$_JSPE_BREAK" = "yes" ]; then
    _js_set_event_status "$_jspr_eid" auth_failed "$((_jspr_attempts + 1))"
    return 0
  fi

  if [ "$_jspr_had_deferred" = "yes" ]; then
    _js_set_event_status "$_jspr_eid" deferred "$((_jspr_attempts + 1))"
  else
    _js_set_event_status "$_jspr_eid" "done" "$((_jspr_attempts + 1))"
  fi
  return 0
}

_js_process_one_event() {
  _jspe_row="$1"
  _JSPE_BREAK="no"

  _jspe_eid=$(printf '%s' "$_jspe_row" | cut -f1)
  _jspe_lkey=$(printf '%s' "$_jspe_row" | cut -f4)
  _jspe_dstate=$(printf '%s' "$_jspe_row" | cut -f5)
  _jspe_attempts=$(printf '%s' "$_jspe_row" | cut -f7)

  if [ "$_jspe_lkey" = "*" ]; then
    _js_process_reconcile_event "$_jspe_eid" "$_jspe_attempts"
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

  # R3 — titulo + status atuais. Mesmo padrao de R1/R4/R6 (comentario acima,
  # "sem negacao"): sob 'set -eu', a condicao de um 'if' (com ou sem '!') e
  # sempre isenta de errexit, mas "if ! var=$(cmd)" faz `$?` refletir o NOT
  # logico do pipeline (sempre 0 ao entrar no 'then'), nunca o exit code
  # real de jira-io.sh — bug que impedia auth_failed (401/403) de ser
  # detectado aqui, degradando sempre para `deferred` (achado 8.3.1/8.3.2,
  # onda-032). `if CMD; then ok; else _ec=$?; ...` (sem negacao) preserva o
  # exit code genuino no primeiro comando do 'else'.
  _jspe_r3_err=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r3err.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  if _jspe_issue_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspe_jkey?fields=summary,status" --op R3 2>"$_jspe_r3_err"); then
    rm -f "$_jspe_r3_err"
  else
    _jspe_ec=$?
    if [ "$_jspe_ec" -eq 4 ]; then
      rm -f "$_jspe_r3_err"
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    # 12.2.1: 429 com Retry-After -> persiste no sidecar (nunca inventa um
    # valor quando ausente — evento fica elegivel no PROXIMO drain, mesmo
    # efeito de antes desta tarefa para deferred sem Retry-After).
    _jspe_retry_after=$(_js_extract_retry_after "$_jspe_r3_err")
    rm -f "$_jspe_r3_err"
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    _js_set_retry_after "$_jspe_eid" "$_jspe_retry_after"
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

  if [ "$_jspe_prop_ec" -ne 0 ]; then
    if [ "$_jspe_prop_ec" -eq 4 ]; then
      rm -f "$_jspe_err_file"
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _jspe_retry_after=$(_js_extract_retry_after "$_jspe_err_file")
    rm -f "$_jspe_err_file"
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    _js_set_retry_after "$_jspe_eid" "$_jspe_retry_after"
    return 0
  fi
  rm -f "$_jspe_err_file"

  _jspe_conflict="no"
  _jspe_conflict_reason=""
  if [ "$_jspe_prop_status" = "404" ]; then
    _jspe_conflict="yes"
    _jspe_conflict_reason="marker_missing"
  else
    _jspe_written_sha=$(printf '%s' "$_jspe_prop_resp" | "$_jsd_io" json-get '.value.written_summary_sha256')
    _jspe_written_status=$(printf '%s' "$_jspe_prop_resp" | "$_jsd_io" json-get '.value.written_status')
    # task 13.2.1: baseline de descricao lida do marker atual, carregada
    # adiante para o R6 PUT desta transicao (ver nota no R6 PUT abaixo).
    _jspe_written_desc_sha=$(printf '%s' "$_jspe_prop_resp" | "$_jsd_io" json-get '.value.written_description_sha256? // ""')
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
  # depois, em awk, via -v (dado, nao programa). Captura de $? sem negacao
  # (mesmo bug/fix de R3 acima — onda-032, 8.3.1/8.3.2): a condicao de um
  # 'if' e isenta de 'set -eu' com ou sem '!', mas so a forma sem negacao
  # preserva o exit code genuino no 'else'.
  _jspe_r5_err=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r5err.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  if _jspe_trans_resp=$("$_jsd_io" request GET "/rest/api/3/issue/$_jspe_jkey/transitions" --op R5 2>"$_jspe_r5_err"); then
    rm -f "$_jspe_r5_err"
  else
    _jspe_ec=$?
    if [ "$_jspe_ec" -eq 4 ]; then
      rm -f "$_jspe_r5_err"
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _jspe_retry_after=$(_js_extract_retry_after "$_jspe_r5_err")
    rm -f "$_jspe_r5_err"
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    _js_set_retry_after "$_jspe_eid" "$_jspe_retry_after"
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
  _jspe_r4_err=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r4err.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  if "$_jsd_io" request POST "/rest/api/3/issue/$_jspe_jkey/transitions" \
      --body-file "$_jspe_trans_body_file" --op R4 >/dev/null 2>"$_jspe_r4_err"; then
    rm -f "$_jspe_trans_body_file" "$_jspe_r4_err"
  else
    _jspe_ec=$?
    rm -f "$_jspe_trans_body_file"
    if [ "$_jspe_ec" -eq 4 ]; then
      rm -f "$_jspe_r4_err"
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _jspe_retry_after=$(_js_extract_retry_after "$_jspe_r4_err")
    rm -f "$_jspe_r4_err"
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    _js_set_retry_after "$_jspe_eid" "$_jspe_retry_after"
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
  # task 13.2.1: preserva `written_description_sha256` (lido acima) — o PUT
  # substitui o valor inteiro da propriedade, entao omiti-lo apagaria a
  # baseline de protecao da descricao editada manualmente no Jira.
  _jspe_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  set -- marker --local-key "$_jspe_lkey" --feature "$_jsd_feature" \
    --written-summary-sha256 "$_jspe_cur_sha" --written-status "$_jspe_target" --written-at "$_jspe_now"
  [ -n "${_jspe_written_desc_sha:-}" ] && set -- "$@" --written-description-sha256 "$_jspe_written_desc_sha"
  _jspe_marker_body=$("$_jsd_io" json-build "$@")
  _jspe_marker_body_file=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6body.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  printf '%s' "$_jspe_marker_body" > "$_jspe_marker_body_file"
  _jspe_r6put_err=$(mktemp "${TMPDIR:-/tmp}/jira-sync-r6puterr.XXXXXX") \
    || _js_die "falha ao criar arquivo temporario" 1
  if "$_jsd_io" request PUT "/rest/api/3/issue/$_jspe_jkey/properties/$_JS_MARKER_PROPERTY_KEY" \
      --body-file "$_jspe_marker_body_file" --op R6 >/dev/null 2>"$_jspe_r6put_err"; then
    rm -f "$_jspe_marker_body_file" "$_jspe_r6put_err"
    _js_set_event_status "$_jspe_eid" "done" "$((_jspe_attempts + 1))"
  else
    _jspe_ec=$?
    rm -f "$_jspe_marker_body_file"
    if [ "$_jspe_ec" -eq 4 ]; then
      rm -f "$_jspe_r6put_err"
      _js_set_event_status "$_jspe_eid" auth_failed "$((_jspe_attempts + 1))"
      _JSPE_BREAK="yes"
      return 0
    fi
    _jspe_retry_after=$(_js_extract_retry_after "$_jspe_r6put_err")
    rm -f "$_jspe_r6put_err"
    _js_set_event_status "$_jspe_eid" deferred "$((_jspe_attempts + 1))"
    _js_set_retry_after "$_jspe_eid" "$_jspe_retry_after"
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
# chamada de rede nova ate reconfiguracao; (4) seleciona os elegiveis —
# `queued` SEMPRE, `deferred` cujo retry_after (sidecar, 12.2.1) ja
# decorreu (data-model.md "deferred --> queued: proximo gatilho de
# drain") — nada elegivel encerra aqui (exit 0); (5) `jira-io.sh
# deps-check` (12.3.1/achado 12.3 — ANTES de tocar qualquer evento
# elegivel: sem jq/cliente HTTP, exit 5 com diagnostico, ZERO eventos
# tocados, contracts/plugin-scripts.md exit 5 carve-out 1.1.0 (a)); (6)
# ProjectConfig valido; (7) para cada evento elegivel, `_js_process_one_event`
# (4.2.3-4.2.5 acima) — para na primeira ocorrencia de `auth_failed`
# (credencial invalida para TODAS as chamadas subsequentes, nao so para o
# evento corrente).
_js_cmd_drain() {
  _jsd_feature=$(_js_parse_feature_arg "$@")

  _jsd_dir="$(_js_script_dir)"
  _jsd_config="$_jsd_dir/jira-config.sh"
  _jsd_map="$_jsd_dir/jira-map.sh"
  _jsd_io="$_jsd_dir/jira-io.sh"
  _jsd_tasks="$_jsd_dir/jira-tasks.sh"
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

  # 12.2.1 (achado 12.2): elegivel = `queued` SEMPRE, OU `deferred` cujo
  # `available_at_epoch` (sidecar `_JS_DEFERRED_FILE`) ja passou (ou nao
  # tem linha no sidecar — deferred sem Retry-After, elegivel de imediato).
  # Antes desta tarefa so `queued` era selecionado: um unico 429/5xx/timeout
  # deixava o evento `deferred` PARA SEMPRE (nenhum codigo o promovia de
  # volta), contrariando data-model.md "deferred --> queued: proximo
  # gatilho de drain".
  _jsd_now_epoch=$(date -u +%s)
  _jsd_queued_ids=$(awk -F '\t' -v f="$_jsd_feature" -v now="$_jsd_now_epoch" -v deferf="$_JS_DEFERRED_FILE" '
    BEGIN {
      _n = 0
      while ((getline dline < deferf) > 0) {
        _n++
        if (_n == 1) { continue }
        split(dline, da, "\t")
        avail[da[1]] = da[2] + 0
      }
      close(deferf)
    }
    NR > 1 && $3 == f && $8 == "queued" { print $1; next }
    NR > 1 && $3 == f && $8 == "deferred" {
      if (!($1 in avail) || avail[$1] <= now) { print $1 }
    }
  ' "$_JS_OUTBOX_FILE")
  [ -n "$_jsd_queued_ids" ] || exit 0

  # FASE 12 tarefa 12.3.1 (achado 12.3, contracts/plugin-scripts.md exit 5
  # carve-out 1.1.0 (a)): deps-check ANTES de tocar o 1o evento elegivel.
  # Sem isto, `jira-io.sh request` (que ja chama deps-check internamente,
  # `_ji_cmd_request` linha inicial) so falhava na 1a chamada de rede REAL
  # (dentro de `_js_process_one_event`) — e o exit 5 caia no ramo generico
  # dessa funcao (so trata exit=4 como auth_failed), degradando o evento
  # para `deferred` silenciosamente (drain terminava exit 0), quando o
  # contrato exige "o que degrada e o sync AUTONOMO, que sai com exit 5 +
  # diagnostico e mantem os eventos no outbox para o proximo jira-sync
  # interativo" — SEM mudar o status de nenhum evento. Sem wrapper: sob
  # `set -eu`, falha aqui propaga o exit 5 + mensagem GENUINA de
  # jira-io.sh (mesma convencao de `_jsd_config validate`/`_js_cmd_plan`);
  # o trap EXIT ja instalado no topo desta funcao libera o lock igual.
  "$_jsd_io" deps-check

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

  # r02 FASE 16 task 16.4.4 (contracts/plugin-scripts.md `status` r02):
  # linha grep-avel `milestone=<nome|unresolved|off|blocked:nome>` — SO
  # emitida com `--feature` (o marco e por feature; sem --feature nao ha um
  # unico valor a mostrar). Inteiramente LOCAL/sem rede: `milestone resolve`
  # nao faz chamadas de rede, `jira-config.sh get`/`jira-map.sh milestone-get`
  # so leem arquivos locais.
  if [ -n "$_jss_feature" ]; then
    _jss_m_resolved=$(_js_cmd_milestone_resolve --feature "$_jss_feature" 2>/dev/null) || _jss_m_resolved=""
    _jss_m_name=$(printf '%s\n' "$_jss_m_resolved" | sed -n 's/^name=//p')
    _jss_m_status=$(printf '%s\n' "$_jss_m_resolved" | sed -n 's/^status=//p')
    if [ -n "$_jss_m_name" ]; then
      _jss_m_dir="$(_js_script_dir)"
      _jss_m_state=""
      if _jss_m_pkey=$("$_jss_m_dir/jira-config.sh" get project_key 2>/dev/null) && [ -n "$_jss_m_pkey" ]; then
        if _jss_m_line=$("$_jss_m_dir/jira-map.sh" milestone-get --feature "$_jss_feature" \
            --name "$_jss_m_name" --project-key "$_jss_m_pkey" 2>/dev/null); then
          _jss_m_state=$(printf '%s' "$_jss_m_line" | cut -f5)
        fi
      fi
      if [ "$_jss_m_state" = "blocked" ]; then
        printf 'milestone=blocked:%s\n' "$_jss_m_name"
      else
        printf 'milestone=%s\n' "$_jss_m_name"
      fi
    else
      printf 'milestone=%s\n' "${_jss_m_status:-unresolved}"
    fi
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
  else
    _jss_pending=0
  fi
  # task 13.4.1 (FR-016 / data-model ConflictRecord "resumo emitido pelo
  # hook"): linha grep-avel `pending=N`, contando ConflictRecords PENDENTES
  # (resolution=pending) do proprio conflicts.tsv — inclui os originados em
  # reconcile/convert (que nunca geram evento outbox `conflict`) e exclui
  # os ja resolvidos (resolution vira keep_jira/overwrite/ignored em
  # `_js_close_conflict`, chamado por QUALQUER `--choice` de `resolve`).
  # E a fonte que o hook `posttooluse-jira-sync.sh` consome para o resumo
  # pos-drain, em vez da contagem `conflict=` do outbox (que so via eventos
  # e nunca "esquecia" um conflito ja fechado por causa de 13.3.1).
  printf 'pending=%s\n' "$_jss_pending"
  if [ "$_jss_pending" != "0" ]; then
    printf 'feature\tlocal_key\tjira_key\treason\tdetected_at\n'
    awk -F '\t' -v f="$_jss_feature" \
      'NR>1 && (f=="" || $2==f) && $6=="pending" { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $1 }' \
      "$_JS_CONFLICTS_FILE"
    printf '(resolver com: jira-sync.sh resolve --feature F --local-key K --choice keep_jira|overwrite|ignored)\n'
  else
    printf '(nenhum conflito pendente)\n'
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
# fecha o ConflictRecord PENDENTE de (F, K) com efeito DURAVEL (FASE 12
# tarefa 12.1.1 — achado 12.1: antes desta tarefa, `keep_jira`/`overwrite`
# so mexiam na coluna `resolution`, deixando o SyncMarker intocado; o
# PROXIMO drain/reconcile repetia a MESMA comparacao contra o marker
# antigo e reabria o conflito). Agora:
#   - `keep_jira`: rebaselineia o SyncMarker (`_js_rebaseline_marker`, R3+
#     R6 PUT) para o titulo+status ATUAIS da issue — "aceitar o Jira como
#     esta" passa a significar que a proxima deteccao NAO reabre o mesmo
#     conflito (nenhuma escrita de conteudo, so o marker de controle).
#   - `overwrite`: rebaselineia o marker (mesmo mecanismo — necessario
#     para que o EVENTO REENFILEIRADO abaixo nao seja detectado como o
#     MESMO manual_edit no proximo drain) e reenfileira (via
#     `_js_cmd_enqueue`) um NOVO OutboxEvent com o desired_state a
#     aplicar. Fonte do desired_state, em ordem: (1) ultimo evento outbox
#     `conflict` do par (conflitos originados de `drain`/reconcile diretos
#     via evento); (2) fallback — `local_state` ATUAL de
#     `jira-tasks.sh items` (conflitos originados de `_js_process_reconcile_event`
#     ou de `_js_maybe_update_mapped_issue`/convert NUNCA geram esse
#     evento outbox — achado 12.1 "overwrite nunca funciona para
#     conflitos vindos de reconcile/convert"). Ambas as fontes sao dados
#     REAIS ja lidos pelo proprio plugin — nunca um valor fabricado
#     (Principio VI). Erro (exit 1) se nenhuma das duas fontes resolver um
#     desired_state, ou se o rebaseline (R3/R6) falhar — o conflito
#     PERMANECE pendente nesses casos, nunca fechado as cegas.
#   - `ignored`: inalterado — so fecha o registro, nenhuma rede.
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

  if [ "$_jsr_choice" = "keep_jira" ] || [ "$_jsr_choice" = "overwrite" ]; then
    _jsr_dir="$(_js_script_dir)"
    _jsr_io="$_jsr_dir/jira-io.sh"
    _jsr_tasks="$_jsr_dir/jira-tasks.sh"
    _jsr_config="$_jsr_dir/jira-config.sh"
    # Sem wrapper: sob `set -eu`, falha aqui propaga o exit code + mensagem
    # GENUINOS de jira-config.sh (3 ausente / 1 invalido) — mesma convencao
    # de `_js_cmd_plan`/`_js_cmd_convert` (nunca mascarar com exit 1 fixo).
    "$_jsr_config" validate
  fi

  if [ "$_jsr_choice" = "overwrite" ]; then
    # task 13.3.1: so aceita o desired_state de um evento outbox `conflict`
    # AINDA nao resolvido — `_js_last_conflict_desired_state` filtra por
    # status=conflict, e `_js_close_conflict_outbox_events` (abaixo, ao fim
    # desta funcao) fecha (status=done) todo evento conflict do par assim
    # que o operador resolve; um conflito ANTERIOR ja resolvido, portanto,
    # nunca e mais visto por esta chamada (achado 13.3: antes desta tarefa,
    # o evento conflict do conflito ANTERIOR ficava conflict para sempre e
    # podia ser reusado indevidamente por um overwrite posterior).
    if _jsr_ds=$(_js_last_conflict_desired_state "$_jsr_feature" "$_jsr_key"); then
      :
    else
      # Fallback (achado 12.1, corrigido 13.3.1): conflitos originados de
      # reconcile (`_js_process_reconcile_event`) ou de convert
      # (`_js_maybe_update_mapped_issue`) nunca gravam evento outbox
      # 'conflict' com este local_key. Deriva o desired_state do
      # local_state ATUAL via `jira-tasks.sh items` — mesma derivacao
      # (outcomes-file com precedencia de record_task + stage_status do
      # Epic) que `_js_process_reconcile_event` ja usa (12.4.1/12.8.1),
      # nunca um valor inventado nem divergente da reconciliacao.
      _jsr_outcomes_file=$(_js_outcomes_file_for_feature "$_jsr_feature")
      _jsr_stage=$(_js_resolve_stage "$_jsr_feature")
      if [ -n "$_jsr_stage" ]; then
        _jsr_ds=$("$_jsr_tasks" items --feature "$_jsr_feature" \
          --outcomes-file "$_jsr_outcomes_file" --stage "$_jsr_stage" 2>/dev/null \
          | awk -F '\t' -v k="$_jsr_key" '$1 == k { print $5; exit }')
      else
        _jsr_ds=$("$_jsr_tasks" items --feature "$_jsr_feature" \
          --outcomes-file "$_jsr_outcomes_file" 2>/dev/null \
          | awk -F '\t' -v k="$_jsr_key" '$1 == k { print $5; exit }')
      fi
      rm -f "$_jsr_outcomes_file"
      [ -n "$_jsr_ds" ] \
        || _js_die "nao foi possivel determinar desired_state (nem evento outbox 'conflict' pendente, nem local_state atual via jira-tasks.sh items) para feature=$_jsr_feature local_key=$_jsr_key" 1
    fi

    _js_rebaseline_marker "$_jsr_io" "$_jsr_feature" "$_jsr_key" "$_jsr_jkey" >/dev/null \
      || _js_die "falha ao rebaselinear o SyncMarker antes do overwrite — conflito NAO fechado, tente novamente" 1

    _jsr_new_eid=$(_js_cmd_enqueue --feature "$_jsr_feature" --local-key "$_jsr_key" \
      --state "$_jsr_ds" --source manual)
  fi

  if [ "$_jsr_choice" = "keep_jira" ]; then
    _js_rebaseline_marker "$_jsr_io" "$_jsr_feature" "$_jsr_key" "$_jsr_jkey" >/dev/null \
      || _js_die "falha ao rebaselinear o SyncMarker — conflito NAO fechado, tente novamente" 1
  fi

  # task 13.3.1 (data-model.md OutboxEvent "conflict --> [*]"): TODA
  # resolucao (qualquer --choice) encerra o(s) evento(s) outbox `conflict`
  # do par — nunca deixa um evento conflict "vivo" para sempre. Roda ANTES
  # de fechar o ConflictRecord (abaixo); a ordem entre os dois nao importa
  # para `overwrite` (o NOVO evento reenfileirado acima nasce `queued`,
  # nunca `conflict` — nao e afetado por este fechamento).
  _js_close_conflict_outbox_events "$_jsr_feature" "$_jsr_key"

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

# _js_cmd_requeue_auth_failed [--feature F] — FASE 12 tarefa 12.6.1
# (data-model.md OutboxEvent "auth_failed --> queued: operador reconfigura
# (jira-setup)"): devolve TODOS os eventos `auth_failed` (opcionalmente
# filtrados por --feature) a `queued`, para que o proximo drain os
# reprocesse. Chamado por `jira-setup.sh write-config` apos reconfiguracao
# bem-sucedida — a credencial (`.claude/cstk-jira/config` /
# `${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials`) e GLOBAL ao
# projeto (nao por feature), entao sem --feature reenfileira para todas as
# features do outbox compartilhado (mesmo arquivo, coluna `feature`
# filtra). `attempts` NUNCA e resetado (data-model.md nao especifica reset;
# nao inventa esse comportamento). Idempotente: sem eventos auth_failed
# (outbox ausente ou vazio de auth_failed), imprime contagem 0 e sai exit 0
# — nunca falha por "nada para fazer" (aditivo, nao gateia jira-setup).
_js_cmd_requeue_auth_failed() {
  _jsraf_feature=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)
        [ "$#" -ge 2 ] || _js_die_usage "requeue-auth-failed: --feature requer valor"
        _jsraf_feature="$2"
        shift 2
        ;;
      *)
        _js_die_usage "requeue-auth-failed: argumento desconhecido: $1"
        ;;
    esac
  done

  if [ -n "$_jsraf_feature" ] && ! _js_is_safe_feature "$_jsraf_feature"; then
    _js_die_usage "requeue-auth-failed: --feature invalido: $_jsraf_feature"
  fi

  if [ ! -f "$_JS_OUTBOX_FILE" ]; then
    printf 'requeue-auth-failed: 0 evento(s) auth_failed reenfileirado(s) (outbox inexistente)\n'
    return 0
  fi

  _jsraf_ids=$(awk -F '\t' -v f="$_jsraf_feature" '
    NR > 1 && $8 == "auth_failed" && (f == "" || $3 == f) { print $1 }
  ' "$_JS_OUTBOX_FILE")

  if [ -z "$_jsraf_ids" ]; then
    printf 'requeue-auth-failed: 0 evento(s) auth_failed reenfileirado(s)\n'
    return 0
  fi

  _jsraf_count=0
  for _jsraf_id in $_jsraf_ids; do
    _js_set_event_status "$_jsraf_id" queued
    _jsraf_count=$((_jsraf_count + 1))
  done
  printf 'requeue-auth-failed: %s evento(s) auth_failed reenfileirado(s) para queued\n' "$_jsraf_count"
}

# _js_cmd_resolve_state_field --dir DIR --field FIELD — task 13.1.1
# (Constitution II carve-out 1.1.0): subcomando fino sobre
# `_js_resolve_state_field`, para que QUALQUER call-site do plugin que
# precise ler um campo (top-level ou aninhado, ex: "execution.
# canonical_project") de um state.json/state.db (hoje: o hook
# `posttooluse-jira-sync.sh`, para `execution.canonical_project` — 14.1.1)
# delegue a este UNICO ponto em vez de reimplementar a leitura (e, no ramo
# state.db, reimplementar `sqlite3`). `--field` passa por allowlist DEDICADA
# (`_js_is_valid_field_path`, task 14.1.1: `[A-Za-z0-9_.]`, sem `.`
# inicial/final/`..` consecutivo) ANTES de qualquer leitura — recusa exit 2
# sem tocar disco. Imprime string vazia (exit 0) quando o campo nao existe/
# o runtime nao esta localizavel — nunca falha o chamador nesse caso.
_js_cmd_resolve_state_field() {
  _jsrsf_cmd_dir=""
  _jsrsf_cmd_field=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dir)   _jsrsf_cmd_dir=$2;   shift 2 ;;
      --field) _jsrsf_cmd_field=$2; shift 2 ;;
      *) _js_die_usage "resolve-state-field: flag desconhecida: $1" ;;
    esac
  done
  _js_is_safe_field "$_jsrsf_cmd_dir" \
    || _js_die_usage "resolve-state-field: --dir obrigatorio e sem TAB/newline"
  _js_is_valid_field_path "$_jsrsf_cmd_field" \
    || _js_die_usage "resolve-state-field: --field obrigatorio, charset [A-Za-z0-9_.], sem '.' inicial/final nem '..' consecutivo"
  _js_resolve_state_field "$_jsrsf_cmd_dir" "$_jsrsf_cmd_field"
  return 0
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
  requeue-auth-failed)
    _js_cmd_requeue_auth_failed "$@"
    ;;
  resolve-state-field)
    _js_cmd_resolve_state_field "$@"
    ;;
  milestone)
    _js_cmd_milestone "$@"
    ;;
  *)
    _js_die_usage "subcomando desconhecido: $_js_sub (validos: plan, convert, enqueue, drain, status, resolve, requeue-auth-failed, resolve-state-field, milestone)"
    ;;
esac
