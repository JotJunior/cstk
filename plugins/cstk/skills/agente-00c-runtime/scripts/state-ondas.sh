#!/bin/sh
# state-ondas.sh — gerencia ciclo de vida de Ondas (FASE 3.4).
#
# Ref: docs/specs/agente-00c/data-model.md §Onda
#      docs/specs/agente-00c/spec.md FR-009
#      docs/specs/agente-00c/research.md Decision 1
#      docs/specs/agente-00c/tasks.md FASE 3.4
#
# Subcomandos:
#   state-ondas.sh start --state-dir DIR
#       — Append nova Onda em .waves com:
#           id = onda-NNN sequencial
#           started_at = ISO now
#           executed_stages = []
#           tool_calls = 0
#         Reseta .budgets.tool_calls_current_wave = 0 e
#         .budgets.current_wave_start = started_at. Tambem reseta os
#         sidecares de tick (tool-call-ticks.log) e de uso de agente
#         (wave-agent-usage.jsonl + sentinela de cap) — janela da onda nova
#         comeca zerada (wave-token-metrics FASE 3, task 3.1.1).
#         Stdout: id da nova onda.
#
#   state-ondas.sh end --state-dir DIR --motivo-termino MOTIVO
#                      [--proxima-agendada-para ISO]
#                      [--add-etapa STAGE]
#                      [--next-instruction TEXT]
#                      [--advance [--advance-from PHASE] [--terminal-phase PHASE]]
#       — Atualiza ultima Onda (.waves[-1]) com finished_at/wallclock_seconds/
#         tool_calls/termination_reason/next_wave_scheduled_for. Atualiza
#         accumulated_metrics (waves_total += 1, tool_calls_total +=
#         tool_calls da onda, wallclock_total_seconds += wallclock).
#         tool_calls da onda = .budgets.tool_calls_current_wave (ticks
#         manuais) + linhas do sidecar tool-call-ticks.log (ticks do hook
#         PostToolUse) — sidecar resetado apos o fechamento.
#         --add-etapa pode ser passada N vezes para append em executed_stages.
#         Cada valor DEVE ser um token de etapa ([A-Za-z0-9._-], ate 64
#         chars, sem espaco/prosa) — o knowledge.db deriva waves.stages e
#         n_stages deste campo, e um resumo narrativo gravado aqui corrompe
#         o indice (caso real: 3 ondas com prosa de conclusao e n_stages=1).
#         Resumo de onda pertence a Decisao (state-decisions.sh register),
#         nunca a executed_stages. Valor invalido => erro de uso ANTES de
#         qualquer write (fail-closed).
#         --next-instruction grava .next_instruction NO MESMO write atomico
#         (dispensa o `state-rw.sh set` separado ANTES de end — que deixava
#         backup/sha defasados, ja que `end` tambem escreve no state.json).
#         --advance (wave-close-advance FR-001..004) avanca o PONTEIRO
#         INTEIRO no mesmo write atomico do fechamento: resolve a proxima
#         fase de .current_stage via pipeline.sh next-stage e grava
#         .current_stage = <proxima> + .next_instruction = "Iniciar etapa
#         <proxima>." (template; --next-instruction sobrescreve so o
#         TEXTO). --advance-from PHASE pina a fase de origem
#         explicitamente (uso interno do reconcile-wave --phase; default
#         = .current_stage). Valida SOMENTE com --motivo-termino
#         etapa_concluida_avancando; --terminal-phase PHASE (mesma
#         semantica do reconcile-wave: feature-00c=review-task,
#         agente-00c=review-features) faz fase corrente == PHASE falhar
#         fail-closed ANTES de qualquer write — fechamento terminal usa
#         --motivo-termino concluido + promocao de status, nunca
#         --advance. Elimina a classe do meio-avanco (current_stage
#         avancado com next_instruction stale — invisivel ao
#         reconcile-wave, que da noop em onda fechada).
#         Tambem agrega o sidecar wave-agent-usage.jsonl (hook
#         posttooluse-agent-usage.sh, wave-token-metrics FASE 3) em
#         .waves[-1].agent_usage (WaveUsage: spawns_total/with_usage/
#         unavailable + somas de tokens/tool-uses/duracao, `null` quando
#         nao observado — NUNCA `0` fabricado) e .waves[-1].agent_spawns
#         (array bruto de SpawnUsage). Sem sidecar/spawns nesta onda =>
#         agent_usage null, agent_spawns []. Incrementa
#         .accumulated_metrics.agent_spawns_total/
#         agent_spawns_with_usage_total (sempre int) e agent_tokens_total/
#         agent_tool_use_count_total/agent_duration_ms_total (int|null,
#         ficam intactos quando a onda nao contribui dado). Sidecar
#         resetado apos a agregacao (mesmo ciclo de vida do sidecar de
#         ticks).
#
#   state-ondas.sh tool-call-tick --state-dir DIR
#       — Incrementa .budgets.tool_calls_current_wave (1 unidade).
#         Stdout: novo total da onda (SO o campo do state; nao inclui o
#         sidecar do hook). Caminho MANUAL/legado: o mecanismo primario de
#         contagem e o hook posttooluse-tool-call-tick.sh (sidecar
#         append-only) — nao use os dois em paralelo na mesma execucao ou
#         cada call contara em dobro.
#
#   state-ondas.sh current-id --state-dir DIR
#       — Imprime .waves[-1].id (ou "init" se nao ha onda).
#
#   state-ondas.sh record-skill --state-dir DIR --skill NAME
#                               [--decisao-id DEC-NNN] [--kind skill|gate]
#       — Registra invocacao da skill na onda corrente. Append em
#         .waves[-1].skills_invoked = [..., { skill, timestamp, decision_id,
#         kind }]. --kind (default: skill) separa SKILLS reais (invocadas
#         via tool Skill) de GATES deterministicos de script
#         (validate-tasks-template.sh etc.); entradas kind=gate sao
#         auditaveis no state.json mas NAO entram na metrica de skills da
#         knowledge.db (a ingestao filtra) — antes, gates e ate comandos de
#         build/lint poluiam a tabela `skills` como se fossem skills.
#         Permite review-task auditar "etapa X foi marcada completa mas a
#         skill Y nunca foi invocada via tool Skill" — defesa contra o
#         padrao da execucao-fonte onde orquestrador gerou artefatos
#         in-process sem chamar a skill canonica (dec-014: tasks.md sem
#         create-tasks invocada).
#         Idempotente para a mesma combinacao (skill + decisao_id na mesma
#         onda) — re-registro nao duplica entrada.
#         Stdout: numero total de skills invocadas nesta onda.
#
#   state-ondas.sh record-task --state-dir DIR --task-id ID --outcome pass|fail
#                              [--titulo T] [--wave-id ID] [--testes-rodados N]
#                              [--testes-passados N] [--lint-ok true|false]
#                              [--arquivos JSON] [--origem TAG] [--if-absent]
#       — Upsert idempotente de UMA entrada em .tasks[] (chave = task_id).
#         Caminho de escrita auditado (substitui o jq hand-rolled que vivia
#         na prosa dos orquestradores). Default sobrescreve; --if-absent so
#         insere se ausente. Stdout: total de entradas em .tasks[].
#
#   state-ondas.sh reconcile-tasks --state-dir DIR --tasks-md PATH
#                                  [--wave-id ID] [--dry-run]
#       — Rede de seguranca deterministica: le tasks.md e back-filla em
#         .tasks[] (via record-task --if-absent) toda task CONCLUIDA (heading
#         `### N.M` com todas as subtarefas-checkbox `[x]`) que esteja
#         faltando. NAO grava tasks pendentes/bloqueadas (sem outcome final).
#         Idempotente. Stdout: nº back-filled; --dry-run lista os faltantes.
#
#   state-ondas.sh wave-status --state-dir DIR
#       — Imprime o estado da ULTIMA onda (.waves[-1]):
#           "open"   se termination_reason == null (onda nao fechada)
#           "closed" se termination_reason != null
#           "none"   se nao ha onda
#         Primitiva idempotente que distingue "orquestrador fechou a onda"
#         de "orquestrador parou cedo e deixou a onda aberta" — sem ela, a
#         rede de seguranca do command pai (reconcile-wave) nao pode evitar
#         double-count em `end`.
#
#   state-ondas.sh reconcile-wave --state-dir DIR
#                                 [--phase PHASE] [--tasks-md PATH]
#                                 [--terminal-phase PHASE] [--dry-run]
#       — REDE DE SEGURANCA do command pai contra o bug recorrente "o
#         orquestrador retorna SEM fechar a onda nem emitir Schedule intent"
#         (ver "Contrato de conclusao de turno" no orchestrator .md). Faz a
#         recuperacao deterministica de UMA onda aberta, IDEMPOTENTE:
#           - se wave-status != "open" -> NO-OP (stdout "noop (<status>)",
#             exit 0). Esta guarda e o que torna seguro o pai chamar
#             reconcile-wave A CADA onda sem double-count em accumulated_metrics.
#           - se "open":
#               1. resolve a fase (--phase ou .current_stage)
#               2. fase == execute-task + --tasks-md -> reconcile-tasks
#                  (back-fill .tasks[] best-effort)
#               3. record-skill --skill <fase> (idempotente)
#               4. deriva proxima fase via pipeline.sh next-stage (ou
#                  --terminal-phase: feature-00c=review-task,
#                  agente-00c=review-features — sem isso pipeline.sh
#                  avancaria review-task->review-features erroneamente):
#                  - ha proxima  -> end(etapa_concluida_avancando) +
#                                   avanca current_stage/next_instruction
#                  - terminal    -> end(concluido) + promove
#                                   .execution.status=concluida (+ reason/
#                                   finished_at) + current_stage=concluida
#         --dry-run descreve a acao sem escrever. Stdout em recuperacao:
#         "reconciled (phase=... motivo=... [next=...|terminal])".
#
#   state-ondas.sh export-snapshot --state-dir DIR
#       — Export derivado (FASE 5 — state-db-foundation, FR-007/
#         FR-013-INFRA-BACKUP, contracts/export.md, dec-032 E5-a): gera um
#         `state.json` equivalente via `state-rw.sh read` (Opcao A do
#         contrato, backend-agnostico) e grava em
#         state-history/export-<wave-id-ou-init>-<timestamp>.json (escrita
#         atomica via mktemp+mv; sufixo aleatorio do mktemp preservado no
#         nome final, evita colisao entre chamadas no mesmo segundo UTC).
#         Gatilho SOB DEMANDA — o gatilho
#         AUTOMATICO equivalente roda dentro de `end` sob backend SQLite
#         (mesmo ponto conceitual onde o backup de state-history/ acontece
#         hoje sob backend JSON via `_so_backup_current`; ver E6: falha no
#         export MUST NOT reverter nem impedir o fechamento da onda).
#         Stdout: path do snapshot gerado. Exit 1 com diagnostico em stderr
#         se a geracao falhar (jq ausente, read falhou, I/O).
#
#   state-ondas.sh git-commit --state-dir DIR --projeto-alvo-path PATH
#                             --motivo MOTIVO [--onda-id ID]
#       — Delega o staging a `commit-mode.sh stage-derived` (allowlist
#         derivada do baseline de untracked capturado por `commit-mode.sh
#         snapshot` — living-specs FASE 5, FR-014..FR-017), NUNCA `git add
#         .`/`git add -A`/`git add --all`, depois `git commit -m
#         'chore(agente-00c): onda <ID> - <MOTIVO>'` dentro de
#         --projeto-alvo-path. NUNCA push (Principio V).
#         Idempotente: se nao ha mudancas para commitar, retorna 0 sem erro.
#         Sem fail-soft: se git nao existe / dir nao e repo, exit 1.
#
# Exit codes:
#   0 sucesso
#   1 erro generico (state ausente, git falhou)
#   2 uso incorreto
#
# POSIX sh + jq + git (apenas em git-commit).

set -eu

_SO_NAME="state-ondas"
_SO_DIR=$(cd "$(dirname -- "$0")" && pwd)

# Envelope diagnostico aditivo (openspec-hygiene FR-012/FR-015 — escopo-piloto).
# Nota: o contrato propos 2 codes (wave-already-open, no-open-wave), mas a
# leitura do codigo real (task 4.4.1) confirmou que "start" NAO tem guarda
# fatal para onda-ja-aberta (nao-idempotente por desenho — cabe ao CALLER
# checar `wave-status` antes, ver contrato "GUARDA ANTI-DUPLICACAO" no
# agente-00c-feature-orchestrator.md). Migrado apenas `no-open-wave`, real
# em 2 pontos de falha: `end` (nenhuma onda para fechar) e `record-skill`
# (nenhuma onda para registrar a skill).
# shellcheck source=./_diag.sh
. "$_SO_DIR/_diag.sh"

# Backend dual (feature state-db-foundation, FASE 3 task 3.3): presenca de
# <state-dir>/state.db seleciona SQLite; senao, backend JSON (comportamento
# historico, intacto abaixo). Ver contracts/primitives.md §C1/C2. Reusa os
# primitivos ja testados de _state-rw-db.sh (_sr_backend/_sr_db_file/
# _sr_exec_id/_sr_sql_quote) em vez de duplica-los — mesmo racional de C8
# para sql_escape/strip_nul.
# shellcheck source=./_state-db.sh
. "$_SO_DIR/_state-db.sh"
# shellcheck source=./_state-rw-db.sh
. "$_SO_DIR/_state-rw-db.sh"
# shellcheck source=./_state-ondas-db.sh
. "$_SO_DIR/_state-ondas-db.sh"

_so_die_usage() { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; exit 2; }
_so_die()       { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; exit "${2:-1}"; }
_so_log()       { printf '%s: %s\n' "$_SO_NAME" "$1" >&2; }

# Shim para _state-rw-db.sh (funcoes reusadas como _sr_exec_id/_sr_sql_quote
# nao chamam _sr_die em seus caminhos normais, mas o shim protege contra
# qualquer caminho de erro latente sem duplicar a logica de _so_die).
_sr_die() { _so_die "$1" "${2:-1}"; }

_so_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _so_die "jq nao encontrado no PATH" 1
}

_so_iso_now() { date -u +%FT%TZ; }
_so_state_file() { printf '%s/state.json\n' "$1"; }

# Token de etapa valido para executed_stages: identificador curto tipo
# "specify" / "execute-task-F3.1". Prosa (espaco, pontuacao narrativa,
# acento, newline) NAO e etapa — o knowledge.db deriva waves.stages e
# n_stages deste campo. LC_ALL=C evita que ranges casem acentuados em
# locale pt_BR.
_so_is_stage_token() {
  _t=$1
  [ -n "$_t" ] || return 1
  # newline embutido viraria 2+ etapas no split por linha de `end`.
  _nl='
'
  case "$_t" in *"$_nl"*) return 1 ;; esac
  printf '%s' "$_t" | LC_ALL=C grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
}

# Diretorio do proprio script — resolve scripts irmaos (pipeline.sh, state-rw.sh)
# usados por reconcile-wave. Deriva de $0 (mesmo padrao de model-routing.sh).
_so_self_dir() {
  CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P
}

_so_atomic_write() {
  _dst=$1; _src=$2
  _tmp=$(mktemp -- "${_dst}.XXXXXX") || _so_die "mktemp falhou" 1
  cp -- "$_src" "$_tmp" || { rm -f -- "$_tmp"; _so_die "I/O cp" 1; }
  mv -f -- "$_tmp" "$_dst" || { rm -f -- "$_tmp"; _so_die "mv" 1; }
}

_so_update_sha() {
  _sf=$(_so_state_file "$1")
  _shf="$1/state.json.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    _h=$(sha256sum -- "$_sf" | awk '{print $1}')
  else
    _h=$(shasum -a 256 -- "$_sf" | awk '{print $1}')
  fi
  printf '%s\n' "$_h" > "$_shf"
}

_so_backup_current() {
  _sf=$(_so_state_file "$1")
  [ -f "$_sf" ] || return 0
  _hd="$1/state-history"
  mkdir -p -- "$_hd" 2>/dev/null || _so_die "mkdir state-history falhou" 1
  _curr=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end
  ' "$_sf" 2>/dev/null) || _curr="init"
  _ts=$(date -u +%Y%m%dT%H%M%SZ)
  _bk="$_hd/${_curr}-${_ts}.json"
  mv -- "$_sf" "$_bk" || _so_die "backup falhou" 1
}

# _so_export_snapshot DIR -> Export derivado (FASE 5, contracts/export.md
# Opcao A — reusa `state-rw.sh read`, backend-agnostico: funciona tanto sob
# state.db quanto sob state.json). Grava snapshot atomico (mktemp + mv) em
# state-history/export-<wave-id-ou-init>-<timestamp>.json. Imprime o path
# gerado em stdout no sucesso.
#
# NUNCA falha alto: qualquer erro (self-dir irresolvivel, state-rw.sh
# ausente, read falhou, JSON invalido, I/O) loga via _so_log e retorna 1 —
# jamais chama _so_die. E6 (contracts/export.md, MUST): quem decide se a
# falha e fatal e o CALLER — o gatilho automatico em `_so_db_end` roda isto
# APOS o COMMIT que fechou a onda (a fonte de verdade ja esta segura;
# degradar aqui nunca reverte nem bloqueia esse fechamento), enquanto o
# subcomando `export-snapshot` (uso explicito/sob-demanda) converte a falha
# em exit 1 porque ali e um pedido direto do operador.
_so_export_snapshot() {
  _oes_sdir=$1
  _oes_selfdir=$(_so_self_dir) \
    || { _so_log "export-snapshot: nao foi possivel resolver o diretorio de scripts"; return 1; }
  _oes_rw="$_oes_selfdir/state-rw.sh"
  [ -f "$_oes_rw" ] || { _so_log "export-snapshot: state-rw.sh ausente ($_oes_rw)"; return 1; }

  _oes_hd="$_oes_sdir/state-history"
  mkdir -p -- "$_oes_hd" 2>/dev/null \
    || { _so_log "export-snapshot: mkdir state-history falhou"; return 1; }

  _oes_doc=$(sh "$_oes_rw" read --state-dir "$_oes_sdir" 2>/dev/null) \
    || { _so_log "export-snapshot: state-rw.sh read falhou"; return 1; }
  [ -n "$_oes_doc" ] || { _so_log "export-snapshot: documento gerado por read esta vazio"; return 1; }
  printf '%s' "$_oes_doc" | jq -e . >/dev/null 2>&1 \
    || { _so_log "export-snapshot: documento gerado por read nao e JSON valido"; return 1; }

  _oes_label=$(printf '%s' "$_oes_doc" | jq -r '((.waves // [])[-1].id // "init")' 2>/dev/null) \
    || _oes_label="init"
  case "$_oes_label" in ''|null) _oes_label="init" ;; esac
  _oes_ts=$(date -u +%Y%m%dT%H%M%SZ)
  # mktemp gera o componente aleatorio de unicidade — 2 chamadas no MESMO
  # segundo UTC (granularidade de $_oes_ts, sem fracao portavel em sh/date)
  # com a mesma onda aberta colidiriam se o destino final nao carregasse
  # esse sufixo. Mantemos o nome gerado pelo proprio mktemp (dentro de
  # state-history/) em vez de descarta-lo apos o mv, como C10 (primitives.md)
  # ja recomenda para nomes nao-derivados-de-PID.
  _oes_tmp=$(mktemp -- "$_oes_hd/.export-tmp-XXXXXX") \
    || { _so_log "export-snapshot: mktemp falhou"; return 1; }
  _oes_rand=${_oes_tmp##*-}
  _oes_dst="$_oes_hd/export-${_oes_label}-${_oes_ts}-${_oes_rand}.json"
  printf '%s\n' "$_oes_doc" > "$_oes_tmp" \
    || { rm -f -- "$_oes_tmp"; _so_log "export-snapshot: I/O ao gravar snapshot"; return 1; }
  mv -f -- "$_oes_tmp" "$_oes_dst" \
    || { rm -f -- "$_oes_tmp"; _so_log "export-snapshot: mv falhou"; return 1; }
  printf '%s\n' "$_oes_dst"
  return 0
}

_so_cmd_export_snapshot() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "export-snapshot: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "export-snapshot: --state-dir obrigatorio"
  _so_require_jq
  _so_export_snapshot "$_sdir" \
    || _so_die "export-snapshot: falha ao gerar o snapshot (ver diagnostico acima)" 1
}

_so_next_onda_num() {
  _sf=$(_so_state_file "$1")
  jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) == 0 then 1
    else (([$w[].id // ""] | map(sub("^onda-0*"; "") | tonumber? // 0) | max) + 1)
    end' "$_sf" 2>/dev/null
}

# ---------- Sidecar de ticks (hook PostToolUse) ----------
#
# O hook posttooluse-tool-call-tick.sh NAO pode fazer read-modify-write no
# state.json (dispara concorrente aos writes transacionais do orquestrador —
# risco de clobber); ele appenda 1 linha por tool call em
# <state-dir>/tool-call-ticks.log. Aqui esse sidecar e AGREGADO (end soma ao
# campo .budgets.tool_calls_current_wave, que segue existindo para ticks
# manuais via `tool-call-tick`) e RESETADO (start e end delimitam a janela
# de contagem da onda). budget.sh faz a mesma soma mid-onda.

_so_ticks_file() { printf '%s/tool-call-ticks.log\n' "$1"; }

# _so_ticks_count DIR -> nº de linhas do sidecar (0 se ausente/ilegivel).
_so_ticks_count() {
  _tf=$(_so_ticks_file "$1")
  [ -f "$_tf" ] || { printf '0\n'; return 0; }
  _n=$(wc -l < "$_tf" 2>/dev/null | tr -d '[:space:]') || _n=0
  case "$_n" in
    '' | *[!0-9]*) printf '0\n' ;;
    *) printf '%s\n' "$_n" ;;
  esac
}

# _so_ticks_reset DIR -> remove o sidecar (best-effort; hook recria no
# proximo tick). Ticks appendados na exata fronteira do reset se perdem —
# aceitavel para proxy de custo.
_so_ticks_reset() {
  rm -f -- "$(_so_ticks_file "$1")" 2>/dev/null || :
}

# ---------- Sidecar de uso de agente (hook PostToolUse/Agent) ----------
#
# Espelha o sidecar de ticks acima (wave-token-metrics FASE 3,
# data-model.md §Sidecar). O hook posttooluse-agent-usage.sh NAO toca o
# state.json (mesma razao: concorrencia com writes transacionais); appenda
# 1 linha JSON (SpawnUsage) por spawn em <state-dir>/wave-agent-usage.jsonl.
# Aqui esse sidecar e AGREGADO (end soma em .waves[-1].agent_usage /
# .accumulated_metrics.agent_*) e RESETADO (start/end delimitam a janela,
# junto com o sentinela de cap .wave-agent-usage-cap-warned).

_so_agent_usage_file() { printf '%s/wave-agent-usage.jsonl\n' "$1"; }
_so_agent_usage_cap_sentinel() { printf '%s/.wave-agent-usage-cap-warned\n' "$1"; }

# _so_agent_usage_reset DIR -> remove o sidecar + sentinela de cap
# (best-effort; hook recria no proximo spawn). Mesma tolerancia de fronteira
# do sidecar de ticks.
_so_agent_usage_reset() {
  rm -f -- "$(_so_agent_usage_file "$1")" 2>/dev/null || :
  rm -f -- "$(_so_agent_usage_cap_sentinel "$1")" 2>/dev/null || :
}

# _so_agent_usage_read DIR -> stdout: array JSON de SpawnUsage validos.
# Resiliente a sidecar ausente (=> "[]") e a linhas corrompidas dentro do
# arquivo: usa o idioma `inputs | fromjson?` (jq -R -n) para descartar
# SILENCIOSAMENTE linhas que nao parseiam como JSON, em vez de abortar o
# arquivo inteiro (jq -c 'inputs' pararia no primeiro erro de parse).
# Degradacao graciosa (Principio VI: nunca fabrica dado, apenas ignora o
# que nao pode ler) — jamais falha `end`.
_so_agent_usage_read() {
  _auf=$(_so_agent_usage_file "$1")
  [ -f "$_auf" ] || { printf '[]\n'; return 0; }
  _out=$(jq -R -n '[inputs | fromjson?]' "$_auf" 2>/dev/null) || _out=""
  case "$_out" in
    '') printf '[]\n' ;;
    *)  printf '%s\n' "$_out" ;;
  esac
}

# ---------- Telemetria OTel (consumo real da onda) ----------
#
# Complementa (nao substitui) o sidecar de agent-usage. O hook
# posttooluse-agent-usage.sh so enxerga o que o spawn devolve, e o spawn do
# orquestrador ENVOLVE a onda — seu tool_result chega depois do `end`, e o
# consumo dele nunca era capturado. Os contadores OTel sao incrementados a
# cada API request, entao um snapshot no start e outro no end fecham essa
# lacuna independentemente de quando o spawn retorna.
#
# 100% best-effort: sem `CLAUDE_CODE_ENABLE_TELEMETRY=1` +
# `OTEL_METRICS_EXPORTER=prometheus` no ambiente, tudo isto e no-op e a onda
# roda exatamente como antes.

_so_otel_script() { printf '%s/otel-usage.sh\n' "$(_so_self_dir)"; }

# ---------------------------------------------------------------------------
# Hook marco-aware de retrospectiva proativa (a cada 25 ondas).
#
# Antes vivia SO como prosa em agente-00c-orchestrator.md passo 10: dependia
# do orquestrador lembrar de calcular `waves.length % 25` e disparar. Mesma
# classe de falha das guardas advisory que a feature enforced-guards fechou —
# e falhou de fato: mcp-project-scafold chegou a 31 ondas sem NENHUMA Decisao
# de marco registrada. Aqui o gatilho e deterministico: quem fecha a onda
# calcula e dispara.
#
# Regra de disparo (self-healing): dispara quando `waves.length >=
# next_retrospective_milestone` (default 25 quando o campo esta ausente), e
# nao apenas na igualdade exata. Assim um marco pulado por onda terminada em
# bloqueio/aborto ainda dispara na onda seguinte, em vez de se perder ate o
# proximo multiplo de 25.
#
# Motivos que NAO disparam: bloqueio_humano (ja ha bloqueio pendente — dois
# bloqueios competindo confundem a resposta do operador), aborto e concluido
# (execucao encerrada; retro proativa nao tem para onde levar). Nesses casos
# `next_retrospective_milestone` fica INTACTO de proposito, para o marco
# disparar na proxima onda que de fato avancar.
#
# Best-effort por contrato: qualquer falha aqui (script irmao ausente,
# validacao de Principio I, I/O) vira aviso em stderr e NUNCA falha `end` —
# fechar a onda e a operacao critica, registrar o marco nao e. Com a
# milestone intacta, a proxima onda tenta de novo.
# ---------------------------------------------------------------------------
_so_retro_milestone_step() { printf '25\n'; }

# Ecoa "1" se a onda recem-fechada cruzou o marco e o motivo permite disparo.
_so_retro_milestone_due() {
  _rm_sf=$1; _rm_motivo=$2
  case "$_rm_motivo" in
    etapa_concluida_avancando|threshold_proxy_atingido) ;;
    *) return 1 ;;
  esac
  _rm_step=$(_so_retro_milestone_step)
  _rm_len=$(jq -r '((.waves // .ondas) // []) | length' "$_rm_sf" 2>/dev/null) || return 1
  case "$_rm_len" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_rm_len" -gt 0 ] || return 1
  _rm_next=$(jq -r '
    (.next_retrospective_milestone // .proximo_marco_retrospectiva) // ""
    | tostring' "$_rm_sf" 2>/dev/null) || _rm_next=""
  case "$_rm_next" in ''|null|*[!0-9]*) _rm_next="$_rm_step" ;; esac
  [ "$_rm_len" -ge "$_rm_next" ] || return 1
  return 0
}

_so_retro_milestone_fire() {
  _rm_sdir=$1
  _rm_sf=$(_so_state_file "$_rm_sdir")
  _rm_dir=$(_so_self_dir) || return 0
  _rm_dec_sh="$_rm_dir/state-decisions.sh"
  _rm_blo_sh="$_rm_dir/bloqueios.sh"
  _rm_rw_sh="$_rm_dir/state-rw.sh"
  for _rm_f in "$_rm_dec_sh" "$_rm_blo_sh" "$_rm_rw_sh"; do
    if [ ! -x "$_rm_f" ] && [ ! -f "$_rm_f" ]; then
      _so_log "end: hook de marco pulado (script irmao ausente: $_rm_f)"
      return 0
    fi
  done

  _rm_step=$(_so_retro_milestone_step)
  _rm_len=$(jq -r '((.waves // .ondas) // []) | length' "$_rm_sf" 2>/dev/null) || return 0
  case "$_rm_len" in ''|*[!0-9]*) return 0 ;; esac
  _rm_etapa=$(jq -r '(.current_stage // .etapa_corrente) // "execute-task"' "$_rm_sf" 2>/dev/null) \
    || _rm_etapa="execute-task"
  case "$_rm_etapa" in ''|null) _rm_etapa="execute-task" ;; esac

  _rm_dec=$(sh "$_rm_dec_sh" register --state-dir "$_rm_sdir" \
    --agente "orquestrador-00c" --etapa "$_rm_etapa" \
    --score 0 \
    --contexto "Marco de $_rm_len ondas atingido - proposta de retro proativa (gatilho deterministico de state-ondas.sh end)" \
    --opcoes '["solicitar-retro","prosseguir-sem-retro"]' \
    --escolha "solicitar-retro" \
    --justificativa "Execucao longa: marcos a cada $_rm_step ondas forcam aprendizado de meta-padroes e deteccao de desvio de proposito antes do fim da execucao." \
    2>/dev/null) || _rm_dec=""
  if [ -z "$_rm_dec" ]; then
    _so_log "end: hook de marco pulado (falha ao registrar Decisao; marco continua pendente)"
    return 0
  fi

  _rm_blk=$(sh "$_rm_blo_sh" register --state-dir "$_rm_sdir" \
    --decisao-id "$_rm_dec" \
    --pergunta "Atingimos $_rm_len ondas. Revisar padroes acumulados (retrospectiva de marco) antes de continuar?" \
    --contexto-para-resposta "Marcos a cada $_rm_step ondas ajudam a detectar falsos positivos recorrentes, loops de etapa e desvios de finalidade antes do fim da execucao. Responder 'nao-continuar' prossegue sem custo." \
    --opcoes-recomendadas '["sim-rodar-retro","nao-continuar"]' \
    2>/dev/null) || _rm_blk=""
  if [ -z "$_rm_blk" ]; then
    _so_log "end: hook de marco parcial ($_rm_dec registrada, bloqueio falhou; marco continua pendente)"
    return 0
  fi

  # So agora avanca a milestone: com Decisao E bloqueio no state, o marco
  # esta de fato consumido e nao pode redisparar na proxima onda.
  _rm_new=$(( (_rm_len / _rm_step + 1) * _rm_step ))
  sh "$_rm_rw_sh" set --state-dir "$_rm_sdir" \
    --field '.next_retrospective_milestone' --value "$_rm_new" >/dev/null 2>&1 \
    || _so_log "end: marco disparado ($_rm_dec/$_rm_blk) mas falhou ao gravar next_retrospective_milestone=$_rm_new"

  _so_log "end: marco de $_rm_len ondas — retrospectiva proposta ($_rm_dec/$_rm_blk); proximo marco=$_rm_new"
}

# _so_otel_snapshot DIR PHASE — nunca falha a onda.
_so_otel_snapshot() {
  _ots=$(_so_otel_script)
  [ -f "$_ots" ] || return 0
  sh "$_ots" snapshot --state-dir "$1" --phase "$2" >/dev/null 2>&1 || :
  return 0
}

# _so_otel_delta DIR [REASON_FILE] -> stdout: JSON do consumo da onda, ou
# `null`. `null` significa AUSENTE (telemetria desligada, snapshot
# faltando, processo trocou no meio) — nunca zero fabricado.
#
# REASON_FILE (opcional): caminho onde o motivo da ausencia e depositado
# como slug de uma linha (vazio/intocado quando a onda foi medida). O
# motivo sempre existiu, mas so no aviso em prosa que o `2>/dev/null`
# abaixo descarta — o operador ficava com um "s/ dado" mudo no painel.
#
# O ARQUIVO E DO CHAMADOR, de proposito: `end` invoca esta funcao dentro de
# `$( )`, ou seja, num SUBSHELL — qualquer variavel global assinalada aqui
# morreria junto com ele. Arquivo atravessa a fronteira; variavel nao.
_so_otel_delta() {
  _od_dir=$1
  _od_rf=${2:-}
  [ -n "$_od_rf" ] && : > "$_od_rf" 2>/dev/null

  # _od_reason SLUG -> deposita o motivo (no-op sem REASON_FILE).
  _od_reason() { [ -n "$_od_rf" ] && printf '%s\n' "$1" > "$_od_rf" 2>/dev/null; return 0; }

  _ots=$(_so_otel_script)
  [ -f "$_ots" ] || { _od_reason "sem-script"; printf 'null\n'; return 0; }

  if [ -n "$_od_rf" ]; then
    _od=$(sh "$_ots" delta --state-dir "$_od_dir" --reason-file "$_od_rf" 2>/dev/null) || _od=""
  else
    _od=$(sh "$_ots" delta --state-dir "$_od_dir" 2>/dev/null) || _od=""
  fi

  # Valida como JSON com jq. NAO usar glob de printaveis (`*[!\ -~]*`):
  # ele casa newline, entao qualquer JSON multi-linha virava `null`.
  if [ -z "$_od" ] || ! printf '%s' "$_od" | jq -e . >/dev/null 2>&1; then
    # `null` legitimo do delta ja depositou o slug; aqui cobrimos so a
    # saida invalida (contrato quebrado), que o delta nao classifica.
    [ -n "$_od_rf" ] && [ ! -s "$_od_rf" ] && _od_reason "saida-invalida"
    printf 'null\n'
    return 0
  fi

  case "$_od" in
    null) [ -n "$_od_rf" ] && [ ! -s "$_od_rf" ] && _od_reason "nao-classificado" ;;
    *) [ -n "$_od_rf" ] && : > "$_od_rf" 2>/dev/null ;;
  esac
  printf '%s\n' "$_od"
}

# _so_otel_reason_read FILE -> slug depositado (vazio se nao ha motivo).
_so_otel_reason_read() {
  [ -n "${1:-}" ] || return 0
  [ -s "$1" ] || return 0
  head -n 1 "$1" 2>/dev/null | tr -d '[:space:]'
}

# _so_otel_reset DIR — descarta os snapshots da onda encerrada para nao
# casar o start de uma onda com o end da seguinte.
_so_otel_reset() {
  rm -f -- "$1/otel-start.tsv" "$1/otel-end.tsv" 2>/dev/null || :
}

# ---------- Subcomandos ----------

_so_cmd_start() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "start: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "start: --state-dir obrigatorio"
  _so_require_jq
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _so_db_start "$_sdir"
    return 0
  fi
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "start: state.json ausente em $_sdir" 1

  _num=$(_so_next_onda_num "$_sdir")
  _id=$(printf 'onda-%03d' "$_num")
  _now=$(_so_iso_now)

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq --arg id "$_id" --arg ts "$_now" '
    .waves += [{
      id: $id,
      started_at: $ts,
      finished_at: null,
      executed_stages: [],
      tool_calls: 0,
      wallclock_seconds: 0,
      termination_reason: null,
      next_wave_scheduled_for: null,
      skills_invoked: []
    }]
    | .budgets.tool_calls_current_wave = 0
    | .budgets.current_wave_start = $ts
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_backup_current "$_sdir"
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  # Janela de contagem do sidecar comeca zerada junto com a onda (ticks
  # entre o end anterior e este start pertencem a fechamento/overhead do
  # orquestrador, nao a onda nova).
  _so_ticks_reset "$_sdir"
  # Idem para o sidecar de uso de agente (wave-token-metrics FASE 3,
  # task 3.1.1): spawns entre o end anterior e este start ficam fora da
  # onda nova; mesma tolerancia de fronteira do sidecar de ticks.
  _so_agent_usage_reset "$_sdir"

  # Baseline de untracked (living-specs FASE 5, FR-014/data-model.md
  # UntrackedBaseline: "escrito por commit-mode.sh snapshot no inicio da
  # onda"). Best-effort: git-commit (passo 10 de toda onda) delega a
  # `stage-derived`, que so inclui untracked NOVOS desde este baseline —
  # capturar aqui, ANTES de qualquer trabalho da onda mutar o repo, e o
  # UNICO ponto onde "pre-existente" (alheio) vs "novo desta onda" pode
  # ser distinguido corretamente. Nunca bloqueia `start`: ausencia de git,
  # de target_project_path, ou de commit-mode.sh apenas deixa o baseline
  # ausente (git-commit cai no fail-closed existente, sem regressao no
  # ciclo de vida da onda).
  _so_start_snapshot_baseline "$_sdir"

  # Baseline de consumo real (telemetria OTel). Os contadores sao
  # cumulativos por sessao, entao o delta start->end e o consumo DESTA
  # onda — inclusive o do proprio orquestrador, que o sidecar de spawn
  # nunca conseguiu capturar. No-op sem telemetria ligada.
  _so_otel_reset "$_sdir"
  _so_otel_snapshot "$_sdir" start

  printf '%s\n' "$_id"
}

# Best-effort: deriva o projeto-alvo do proprio state.json e chama
# commit-mode.sh snapshot. Isolado em funcao propria para nunca poluir o
# fluxo principal de start com `set -e` (toda falha aqui e silenciosa).
_so_start_snapshot_baseline() {
  _ssb_sdir="$1"
  # Invalida o baseline da onda ANTERIOR antes de qualquer early-return:
  # se a captura desta onda falhar (best-effort), o arquivo fica AUSENTE e
  # stage-derived cai no fail-closed (untracked fora do staging). Sem isso,
  # um baseline stale sobrevive e tudo que ficou untracked desde aquela
  # onda antiga "vaza" como novo e e staged no wave-commit (issue #49).
  rm -f "$_ssb_sdir/commit-baseline.txt" 2>/dev/null || :
  command -v git >/dev/null 2>&1 || return 0

  # Le via state-rw.sh get (backend-safe: funciona sob JSON e SQLite sem
  # branch aqui — state-rw.sh ja faz a selecao de backend internamente).
  # Antes lia .execution.target_project_path via jq direto no state.json,
  # o que quebrava silenciosamente sob backend SQLite (arquivo ausente).
  _ssb_selfdir=$(_so_self_dir) || return 0
  _ssb_rw="$_ssb_selfdir/state-rw.sh"
  [ -f "$_ssb_rw" ] || return 0
  _ssb_pap=$(sh "$_ssb_rw" get --state-dir "$_ssb_sdir" --field '.execution.target_project_path' 2>/dev/null) || _ssb_pap=""
  case "$_ssb_pap" in ''|null) return 0 ;; esac
  [ -d "$_ssb_pap" ] || return 0

  _ssb_cm="$_ssb_selfdir/commit-mode.sh"
  [ -f "$_ssb_cm" ] || return 0

  sh "$_ssb_cm" snapshot --state-dir "$_ssb_sdir" --projeto-alvo-path "$_ssb_pap" \
    >/dev/null 2>&1 || _so_log "start: snapshot de baseline nao gravado (best-effort, sem impacto na onda)"
  return 0
}

# Calcula wallclock em segundos entre dois timestamps ISO.
# Implementa fallback portavel: tenta `date -d` (GNU), depois `date -j -f` (BSD).
_so_wallclock() {
  _start=$1
  _fim=$2
  if _se=$(date -u -d "$_start" +%s 2>/dev/null) && _fe=$(date -u -d "$_fim" +%s 2>/dev/null); then
    printf '%s\n' "$((_fe - _se))"
    return 0
  fi
  if _se=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_start" +%s 2>/dev/null) \
     && _fe=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_fim" +%s 2>/dev/null); then
    printf '%s\n' "$((_fe - _se))"
    return 0
  fi
  printf '0\n'
  return 1
}

_so_cmd_end() {
  _sdir=""
  _motivo=""
  _proxima="null"
  _etapas=""
  _next_instr=""
  _next_instr_set=0
  _advance=0
  _adv_from=""
  _adv_terminal=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)             _sdir=$2; shift 2 ;;
      --motivo-termino)        _motivo=$2; shift 2 ;;
      --proxima-agendada-para) _proxima=$2; shift 2 ;;
      --next-instruction)      _next_instr=$2; _next_instr_set=1; shift 2 ;;
      --advance)               _advance=1; shift ;;
      --advance-from)          _adv_from=$2; shift 2 ;;
      --terminal-phase)        _adv_terminal=$2; shift 2 ;;
      --add-etapa)
        _so_is_stage_token "$2" || _so_die_usage \
          "end: --add-etapa aceita token de etapa ([A-Za-z0-9._-], ate 64 chars, sem espaco/prosa); recebido: '$2'. Resumo de onda vai em Decisao (state-decisions.sh register), nao em executed_stages."
        _etapas="$_etapas
$2"; shift 2 ;;
      *) _so_die_usage "end: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]   || _so_die_usage "end: --state-dir obrigatorio"
  [ -n "$_motivo" ] || _so_die_usage "end: --motivo-termino obrigatorio"
  if [ "$_next_instr_set" = 1 ] && [ -z "$_next_instr" ]; then
    _so_die_usage "end: --next-instruction nao aceita valor vazio"
  fi
  case "$_motivo" in
    etapa_concluida_avancando|threshold_proxy_atingido|bloqueio_humano|aborto|concluido) ;;
    *) _so_die "end: motivo invalido: $_motivo" 2 ;;
  esac
  if [ -n "$_adv_terminal" ] && [ "$_advance" = 0 ]; then
    _so_die_usage "end: --terminal-phase so faz sentido junto de --advance"
  fi
  if [ -n "$_adv_from" ] && [ "$_advance" = 0 ]; then
    _so_die_usage "end: --advance-from so faz sentido junto de --advance"
  fi

  # --advance (wave-close-advance FR-001..004): resolve a proxima fase
  # ANTES de qualquer write (fail-closed) e injeta o avanco do ponteiro no
  # mesmo write atomico do fechamento — os dois backends recebem
  # _adv_next resolvido, nunca recalculam.
  _adv_next=""
  if [ "$_advance" = 1 ]; then
    [ "$_motivo" = "etapa_concluida_avancando" ] || _so_die_usage \
      "end: --advance so e valida com --motivo-termino etapa_concluida_avancando (recebido: $_motivo)"
    _adv_selfdir=$(_so_self_dir) || _adv_selfdir="."
    _adv_pipeline="$_adv_selfdir/pipeline.sh"
    _adv_rw="$_adv_selfdir/state-rw.sh"
    [ -f "$_adv_pipeline" ] || _so_die "end: pipeline.sh nao encontrado em $_adv_selfdir (necessario para --advance)" 1
    [ -f "$_adv_rw" ]       || _so_die "end: state-rw.sh nao encontrado em $_adv_selfdir (necessario para --advance)" 1
    # --advance-from pina a fase de origem explicitamente (reconcile-wave
    # --phase, semantica "o pai fixa a fase"); default = .current_stage.
    if [ -n "$_adv_from" ]; then
      _adv_cur=$_adv_from
    else
      _adv_cur=$(sh "$_adv_rw" get --state-dir "$_sdir" --field '.current_stage' 2>/dev/null) || _adv_cur=""
      case "$_adv_cur" in null) _adv_cur="" ;; esac
      [ -n "$_adv_cur" ] || _so_die "end: --advance nao resolveu .current_stage (estado ausente/corrompido?)" 1
    fi
    if [ -n "$_adv_terminal" ] && [ "$_adv_cur" = "$_adv_terminal" ]; then
      _so_die_usage "end: --advance em fase terminal '$_adv_cur' — fechamento terminal usa --motivo-termino concluido + promocao de status, nunca --advance"
    fi
    _adv_next=$(sh "$_adv_pipeline" next-stage --current "$_adv_cur" 2>/dev/null) || _adv_next=""
    [ -n "$_adv_next" ] || _so_die_usage \
      "end: --advance sem proxima etapa a partir de '$_adv_cur' (fase terminal ou desconhecida do pipeline)"
    # Template deterministico; --next-instruction sobrescreve so o TEXTO
    # (FR-004 — o avanco de current_stage ocorre do mesmo jeito).
    if [ "$_next_instr_set" = 0 ]; then
      _next_instr="Iniciar etapa $_adv_next."
      _next_instr_set=1
    fi
  fi
  _so_require_jq
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _so_db_end "$_sdir" "$_motivo" "$_proxima" "$_etapas" "$_next_instr_set" "$_next_instr" "$_adv_next"
    return 0
  fi
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "end: state.json ausente em $_sdir" 1

  _now=$(_so_iso_now)
  _start=$(jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then (($w[-1].started_at // $w[-1].inicio) // "") else "" end
  ' "$_sf")
  if [ -z "$_start" ]; then
    diag_emit error no-open-wave "end: nao ha onda em andamento" \
      "rode state-ondas.sh start antes de end, ou confira se .waves ja foi fechado por outra chamada" || :
    _so_die "end: nao ha onda em andamento" 1
  fi
  _wc=$(_so_wallclock "$_start" "$_now") || true
  # tool_calls da onda = campo do state (ticks manuais via tool-call-tick)
  # + sidecar do hook PostToolUse (ver "Sidecar de ticks" acima).
  _tc_field=$(jq -r '(.budgets.tool_calls_current_wave // .orcamentos.tool_calls_onda_corrente) // 0' "$_sf")
  _tc_side=$(_so_ticks_count "$_sdir")
  _tc=$((_tc_field + _tc_side))

  # Monta JSON array das etapas adicionais (uma por linha, ignora linhas vazias).
  _etapas_json=$(printf '%s\n' "$_etapas" \
    | sed '/^$/d' \
    | jq -R . \
    | jq -s .)

  _proxima_json="null"
  if [ "$_proxima" != "null" ]; then
    _proxima_json="\"$_proxima\""
  fi

  # Agregacao do sidecar de uso de agente (wave-token-metrics FASE 3,
  # data-model.md §"Entity: Consumo Agregado da Onda"). Resiliente a
  # sidecar ausente/corrompido — nunca falha `end` (Principio VI: so
  # agrega o que foi de fato observado, nunca fabrica o resto).
  _au_spawns_json=$(_so_agent_usage_read "$_sdir")

  # Consumo real da onda via OTel. O snapshot final tem de sair ANTES do
  # write — e enquanto o processo Claude Code ainda vive, ja que o exporter
  # Prometheus e in-process e some junto com ele.
  _so_otel_snapshot "$_sdir" end
  # Arquivo de motivo criado AQUI (fora do `$( )`): a funcao roda em
  # subshell e nao consegue devolver o slug por variavel.
  _otel_rf=$(mktemp 2>/dev/null) || _otel_rf=""
  _otel_json=$(_so_otel_delta "$_sdir" "$_otel_rf")
  case "$_otel_json" in ''|null) _otel_json="null" ;; esac
  # Motivo da ausencia (vazio quando medido). Chave achatada na onda,
  # mesmo padrao ja usado por `.waves[-1].touched_key_aspects` (drift.sh)
  # — sob backend SQLite o equivalente vai para a coluna `extra_fields`.
  _otel_reason=$(_so_otel_reason_read "$_otel_rf")
  [ -n "$_otel_rf" ] && rm -f -- "$_otel_rf" 2>/dev/null
  _otel_reason_json="null"
  if [ "$_otel_json" = "null" ] && [ -n "$_otel_reason" ]; then
    _otel_reason_json=$(printf '%s' "$_otel_reason" | jq -Rs .) || _otel_reason_json="null"
  fi

  # .next_instruction gravado DENTRO do mesmo write atomico do fechamento
  # da onda. Antes exigia um `state-rw.sh set` separado, e como `end`
  # tambem escreve no state.json, seguir a ordem literal backup -> hash ->
  # end do prompt do orquestrador deixava backup/hash defasados. Aqui
  # backup/atomic-write/sha rodam UMA vez, depois de tudo.
  _next_instr_json="null"
  if [ "$_next_instr_set" = 1 ]; then
    _next_instr_json=$(printf '%s' "$_next_instr" | jq -Rs .) \
      || _so_die "end: falha ao serializar --next-instruction" 1
  fi

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --argjson otel "$_otel_json" \
    --argjson otel_reason "$_otel_reason_json" \
    --argjson next_instr "$_next_instr_json" \
    --arg adv "$_adv_next" \
    --arg now "$_now" \
    --arg motivo "$_motivo" \
    --argjson wc "$_wc" \
    --argjson tc "$_tc" \
    --argjson etapas "$_etapas_json" \
    --argjson prox "$_proxima_json" \
    --argjson spawns "$_au_spawns_json" '
    ($spawns) as $sp
    | ($sp | length) as $au_total
    | ([$sp[] | select(.status != "indisponivel")] | length) as $au_with_usage
    | ($au_total - $au_with_usage) as $au_unavailable
    | def sum_field(f): ([$sp[] | select(f != null) | f]) as $vals
        | if ($vals | length) > 0 then ($vals | add) else null end;
      (if $au_total > 0 then {
          spawns_total: $au_total,
          spawns_with_usage: $au_with_usage,
          spawns_unavailable: $au_unavailable,
          total_tokens: sum_field(.total_tokens),
          input_tokens: sum_field(.input_tokens),
          output_tokens: sum_field(.output_tokens),
          cache_read_input_tokens: sum_field(.cache_read_input_tokens),
          cache_creation_input_tokens: sum_field(.cache_creation_input_tokens),
          tool_use_count: sum_field(.tool_use_count),
          duration_ms: sum_field(.duration_ms)
        } else null end) as $au
    | def add_null(existing; delta): if delta == null then existing else ((existing // 0) + delta) end;
      (.waves[-1] |= (
        .finished_at = $now
        | .wallclock_seconds = $wc
        | .tool_calls = $tc
        | .termination_reason = $motivo
        | .next_wave_scheduled_for = $prox
        | .executed_stages += $etapas
        | .agent_usage = $au
        | .agent_spawns = $sp
        | .otel_usage = $otel
        | (if $otel_reason != null then .otel_absent_reason = $otel_reason else . end)
      ))
      | .accumulated_metrics.waves_total = ((.accumulated_metrics.waves_total // 0) + 1)
      | .accumulated_metrics.tool_calls_total = ((.accumulated_metrics.tool_calls_total // 0) + $tc)
      | .accumulated_metrics.wallclock_total_seconds =
          ((.accumulated_metrics.wallclock_total_seconds // 0) + $wc)
      | .accumulated_metrics.agent_spawns_total =
          ((.accumulated_metrics.agent_spawns_total // 0) + $au_total)
      | .accumulated_metrics.agent_spawns_with_usage_total =
          ((.accumulated_metrics.agent_spawns_with_usage_total // 0) + $au_with_usage)
      | .accumulated_metrics.agent_tokens_total =
          add_null(.accumulated_metrics.agent_tokens_total; $au.total_tokens)
      | .accumulated_metrics.agent_tool_use_count_total =
          add_null(.accumulated_metrics.agent_tool_use_count_total; $au.tool_use_count)
      | .accumulated_metrics.agent_duration_ms_total =
          add_null(.accumulated_metrics.agent_duration_ms_total; $au.duration_ms)
      | (if $next_instr != null then .next_instruction = $next_instr else . end)
      | (if $adv != "" then .current_stage = $adv else . end)
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_backup_current "$_sdir"
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  # Sidecares consumidos por esta onda; zeram para nao vazar para a proxima.
  _so_ticks_reset "$_sdir"
  _so_agent_usage_reset "$_sdir"
  _so_otel_reset "$_sdir"
  _so_log "end: onda finalizada (motivo=$_motivo, wallclock=${_wc}s, tool_calls=$_tc)"

  # Hook marco-aware — DEPOIS do write/sha da onda, porque registra Decisao e
  # bloqueio com writes atomicos proprios. Best-effort: nao altera o exit de
  # `end`. Ver bloco de comentario em _so_retro_milestone_fire.
  if [ "${CSTK_RETRO_MILESTONE_DISABLED:-0}" != 1 ] \
     && _so_retro_milestone_due "$_sf" "$_motivo"; then
    _so_retro_milestone_fire "$_sdir" || :
  fi
}

_so_cmd_tool_call_tick() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "tool-call-tick: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "tool-call-tick: --state-dir obrigatorio"
  _so_require_jq
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _so_db_tool_call_tick "$_sdir"
    return 0
  fi
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "tool-call-tick: state.json ausente" 1

  _curr=$(jq -r '(.budgets.tool_calls_current_wave // .orcamentos.tool_calls_onda_corrente) // 0' "$_sf")
  _next=$((_curr + 1))

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq --argjson n "$_next" '.budgets.tool_calls_current_wave = $n' "$_sf" > "$_new" \
    || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }
  # tool-call-tick e operacao de alta frequencia; backup so a cada 10 ticks
  # para nao explodir state-history/. Em ticks intermediarios o atomic_write
  # ja sobrescreve via `mv -f` — nao precisa rm.
  if [ "$((_next % 10))" = 0 ]; then
    _so_backup_current "$_sdir"
  fi
  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  printf '%s\n' "$_next"
}

_so_cmd_record_skill() {
  _sdir=""
  _skill=""
  _dec=""
  _kind="skill"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)  _sdir=$2;  shift 2 ;;
      --skill)      _skill=$2; shift 2 ;;
      --decisao-id) _dec=$2;   shift 2 ;;
      --kind)       _kind=$2;  shift 2 ;;
      *) _so_die_usage "record-skill: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]  || _so_die_usage "record-skill: --state-dir obrigatorio"
  [ -n "$_skill" ] || _so_die_usage "record-skill: --skill obrigatorio"
  case "$_kind" in
    skill|gate) ;;
    *) _so_die_usage "record-skill: --kind deve ser skill|gate (recebido: $_kind)" ;;
  esac
  _so_require_jq
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _so_db_record_skill "$_sdir" "$_skill" "$_dec" "$_kind"
    return 0
  fi
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "record-skill: state.json ausente em $_sdir" 1

  # Verifica que existe onda em andamento
  _has_onda=$(jq -r 'if ((.waves // .ondas) // []) | length > 0 then "yes" else "no" end' "$_sf")
  if [ "$_has_onda" != "yes" ]; then
    diag_emit error no-open-wave "record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)" \
      "rode state-ondas.sh start antes de record-skill" || :
    _so_die "record-skill: nenhuma onda em andamento (rode state-ondas.sh start primeiro)" 1
  fi

  _now=$(_so_iso_now)
  _dec_json="null"
  if [ -n "$_dec" ]; then
    _dec_json=$(printf '%s' "$_dec" | jq -R .)
  fi

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg skill "$_skill" \
    --arg ts "$_now" \
    --arg kind "$_kind" \
    --argjson dec "$_dec_json" '
    (.waves[-1].skills_invoked //= [])
    | (.waves[-1].skills_invoked |=
        (if (any(.[]; .skill == $skill and ((.decision_id // .decisao_id) // null) == $dec))
         then .
         else . + [{
           skill: $skill,
           timestamp: $ts,
           decision_id: $dec,
           kind: $kind
         }]
         end))
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "jq update falhou" 1; }

  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  _count=$(jq -r '((.waves // .ondas)[-1].skills_invoked) | length' "$_sf")
  printf '%s\n' "$_count"
}

# record-task: upsert idempotente de UMA entrada em .tasks[] (top-level).
# Chave natural dentro de um state.json (= uma execucao) = task_id. Substitui
# o snippet jq hand-rolled que vivia SO na prosa dos orquestradores (§5.d.ter):
# caminho de escrita auditado, atomico (state-history backup + sha256),
# idempotente. Diferente de record-skill, NAO exige onda em andamento —
# .tasks[] e top-level e pode ser gravado tambem na fase review-task.
#
# Default = UPSERT (sobrescreve a entrada existente com dados frescos — usado
# pelo execute-task, que conhece o outcome real). --if-absent = so insere se
# AUSENTE (no-op se ja existe; usado pelo back-fill reconcile-tasks, para nao
# clobberar uma entrada real com uma derivada).
#
# Campos `recorded_at`/`source` sao ADITIVOS — a ingestao knowledge.db
# (recall.sh) seleciona apenas os 8 campos do contrato layer-b e ignora o
# resto; servem para o review-task distinguir entradas reais de back-filled.
# Stdout: total de entradas em .tasks[] apos a operacao.
_so_cmd_record_task() {
  _sdir=""; _tid=""; _ttl=""; _wid=""; _oc=""
  _tr="0"; _tp="0"; _lk=""; _af="[]"; _origem=""; _ifabsent="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)       _sdir=$2; shift 2 ;;
      --task-id)         _tid=$2;  shift 2 ;;
      --titulo)          _ttl=$2;  shift 2 ;;
      --wave-id)         _wid=$2;  shift 2 ;;
      --outcome)         _oc=$2;   shift 2 ;;
      --testes-rodados)  _tr=$2;   shift 2 ;;
      --testes-passados) _tp=$2;   shift 2 ;;
      --lint-ok)         _lk=$2;   shift 2 ;;
      --arquivos)        _af=$2;   shift 2 ;;
      --origem)          _origem=$2; shift 2 ;;
      --if-absent)       _ifabsent="yes"; shift ;;
      *) _so_die_usage "record-task: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "record-task: --state-dir obrigatorio"
  [ -n "$_tid" ]  || _so_die_usage "record-task: --task-id obrigatorio"
  # task_id = nivel do heading de TAREFA no tasks.md ("### N.M"), NUNCA o
  # nivel de subtarefa/checkbox (N.M.K). Aviso e nao erro: gravar no nivel
  # errado ja aconteceu em campo (7 record-task em N.M.K numa execucao, so
  # descoberto depois pelo reconcile-tasks do review-task) e daqui nao ha
  # como saber o nivel correto sem o tasks.md — logo, sinalizamos sem
  # bloquear.
  case "$_tid" in
    *.*.*)
      _so_log "record-task: AVISO — --task-id '$_tid' tem 3+ niveis; esperado N.M (heading '### N.M' do tasks.md), nao N.M.K (subtarefa/checkbox)"
      ;;
  esac
  [ -n "$_oc" ]   || _so_die_usage "record-task: --outcome obrigatorio"
  case "$_oc" in pass|fail) : ;; *) _so_die_usage "record-task: --outcome deve ser pass|fail" ;; esac
  case "$_tr" in ''|*[!0-9]*) _so_die_usage "record-task: --testes-rodados deve ser inteiro >= 0" ;; esac
  case "$_tp" in ''|*[!0-9]*) _so_die_usage "record-task: --testes-passados deve ser inteiro >= 0" ;; esac
  [ "$_tp" -le "$_tr" ] || _so_die_usage "record-task: --testes-passados ($_tp) > --testes-rodados ($_tr)"
  case "$_lk" in
    true|1)  _lk_json=true ;;
    false|0) _lk_json=false ;;
    '')      _lk_json=null ;;
    *) _so_die_usage "record-task: --lint-ok deve ser true|false (ou vazio)" ;;
  esac
  _so_require_jq
  printf '%s' "$_af" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || _so_die_usage "record-task: --arquivos deve ser um array JSON (ex: '[]')"
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _so_db_record_task "$_sdir" "$_tid" "$_ttl" "$_wid" "$_oc" "$_tr" "$_tp" "$_lk_json" "$_af" "$_origem" "$_ifabsent"
    return 0
  fi
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "record-task: state.json ausente em $_sdir" 1

  # wave-id default = onda corrente (proveniencia best-effort)
  if [ -z "$_wid" ]; then
    _wid=$(jq -r '((.waves // .ondas) // []) as $w | if ($w | length) > 0 then ($w[-1].id // "") else "" end' "$_sf" 2>/dev/null) || _wid=""
  fi

  _now=$(_so_iso_now)
  _origem_json=null
  [ -n "$_origem" ] && _origem_json=$(printf '%s' "$_origem" | jq -R .)

  _new=$(mktemp) || _so_die "mktemp falhou" 1
  jq \
    --arg tid "$_tid" --arg ttl "$_ttl" --arg wid "$_wid" --arg oc "$_oc" \
    --argjson tr "$_tr" --argjson tp "$_tp" --argjson lk "$_lk_json" \
    --argjson af "$_af" --arg ts "$_now" --argjson origem "$_origem_json" \
    --arg ifabsent "$_ifabsent" '
    (.tasks //= [])
    | {task_id:$tid, title:$ttl, wave_id:$wid, outcome:$oc,
       tests_run:$tr, tests_passed:$tp, lint_ok:$lk,
       touched_files:$af, recorded_at:$ts, source:$origem} as $e
    | if any(.tasks[]; .task_id == $tid)
      then (if $ifabsent == "yes" then .
            else .tasks |= map(if .task_id == $tid then $e else . end) end)
      else .tasks += [$e]
      end
  ' "$_sf" > "$_new" || { rm -f -- "$_new"; _so_die "record-task: jq update falhou" 1; }

  _so_atomic_write "$_sf" "$_new"
  rm -f -- "$_new" 2>/dev/null || :
  _so_update_sha "$_sdir"
  jq -r '(.tasks // []) | length' "$_sf"
}

# reconcile-tasks: rede de seguranca DETERMINISTICA contra perda de tasks.
# Le tasks.md (fonte de verdade do backlog) e garante que toda TASK CONCLUIDA
# tenha entrada em .tasks[]. Uma task = heading `### N.M {Titulo}`; esta
# CONCLUIDA quando tem >=1 subtarefa-checkbox e TODAS marcadas `[x]`. Tasks
# pendentes/em-andamento/bloqueadas NAO sao gravadas (nao ha outcome final —
# evita fabricar pass/fail). Back-fill via record-task --if-absent: NUNCA
# clobbera entrada real ja gravada pelo execute-task. Idempotente.
#
# Tambem CURA titulos vazios: entradas ja presentes em .tasks[] com
# title=="" (sintoma de onda execute-task longa gravada em lote sem
# --titulo) recebem o titulo do heading em tasks.md (fonte rastreavel,
# nunca inventada). Nao toca tests_run/tests_passed (sem fonte por task ->
# nao fabrica). So fora de --dry-run; nao afeta a contagem de stdout.
#
# Stdout (default): numero de tasks back-filled nesta chamada.
# --dry-run: NAO escreve; imprime os task_id que SERIAM back-filled (um por
#   linha) — usado pelo gate de completude do review-task.
_so_cmd_reconcile_tasks() {
  _rc_sdir=""; _rc_md=""; _rc_wid=""; _rc_dry="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _rc_sdir=$2; shift 2 ;;
      --tasks-md)  _rc_md=$2;   shift 2 ;;
      --wave-id)   _rc_wid=$2;  shift 2 ;;
      --dry-run)   _rc_dry="yes"; shift ;;
      *) _so_die_usage "reconcile-tasks: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_rc_sdir" ] || _so_die_usage "reconcile-tasks: --state-dir obrigatorio"
  [ -n "$_rc_md" ]   || _so_die_usage "reconcile-tasks: --tasks-md obrigatorio"
  _so_require_jq
  [ -f "$_rc_md" ] || _so_die "reconcile-tasks: tasks.md ausente: $_rc_md" 1
  if [ "$(_sr_backend "$_rc_sdir")" = "sqlite" ]; then
    _so_db_reconcile_tasks "$_rc_sdir" "$_rc_md" "$_rc_wid" "$_rc_dry"
    return 0
  fi
  _rc_sf=$(_so_state_file "$_rc_sdir")
  [ -f "$_rc_sf" ] || _so_die "reconcile-tasks: state.json ausente em $_rc_sdir" 1

  if [ -z "$_rc_wid" ]; then
    _rc_wid=$(jq -r '((.waves // .ondas) // []) as $w | if ($w | length) > 0 then ($w[-1].id // "") else "" end' "$_rc_sf" 2>/dev/null) || _rc_wid=""
  fi

  # --- Cura de titulos vazios -------------------------------------------
  # Entradas ja presentes em .tasks[] com title vazio/null (sintoma de onda
  # execute-task longa que gravou record-task em lote sem --titulo) recebem
  # o titulo do heading correspondente em tasks.md. A FONTE e rastreavel
  # (heading do backlog) — nunca inventada (Principio VI). Roda so fora de
  # --dry-run e NAO altera a contagem de back-fill (contrato de stdout
  # preservado: continua sendo o nº de tasks AUSENTES back-filled abaixo).
  if [ "$_rc_dry" != "yes" ]; then
    # Mapa id->titulo a partir de tasks.md em DUAS granularidades, porque
    # as ondas gravam tasks ora no nivel do heading (### N.M Titulo), ora no
    # nivel do checkbox (- [x] N.M.K texto). Heading tem precedencia sobre
    # checkbox para o mesmo id (na pratica nao colidem: heading e N.M,
    # checkbox e N.M.K). Em ambos os casos a FONTE e o backlog — rastreavel,
    # nunca inventado (Principio VI).
    _rc_titlemap=$(awk '
      { sub(/\r$/, "") }
      /^### / {
        line = $0; sub(/^### +/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); sub(/[ \t]*\[[CAM]\][ \t]*$/, "", t)
          gsub(/\t/, " ", t); gsub(/  +/, " ", t)
          sub(/^ +/, "", t); sub(/ +$/, "", t)
          if (t != "") heading[id] = t
        }
        next
      }
      /^- \[.\] / {
        line = $0; sub(/^- \[.\][ \t]+/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); gsub(/\t/, " ", t); gsub(/  +/, " ", t)
          sub(/^ +/, "", t); sub(/ +$/, "", t)
          if (t != "" && !(id in checkbox)) checkbox[id] = t
        }
        next
      }
      END {
        for (k in checkbox) if (!(k in heading)) print k "\t" checkbox[k]
        for (k in heading) print k "\t" heading[k]
      }
    ' "$_rc_md")
    if [ -n "$_rc_titlemap" ]; then
      _rc_mapjson=$(printf '%s\n' "$_rc_titlemap" \
        | jq -R 'split("\t") | {(.[0]): .[1]}' 2>/dev/null \
        | jq -s 'add' 2>/dev/null) || _rc_mapjson=""
      if [ -n "$_rc_mapjson" ]; then
        _rc_heal=$(mktemp) || _so_die "mktemp falhou" 1
        if jq --argjson m "$_rc_mapjson" '
              .tasks = ((.tasks // []) | map(
                if ((.title // "") == "") and (($m[.task_id] // null) != null)
                then .title = $m[.task_id] else . end))
            ' "$_rc_sf" > "$_rc_heal" 2>/dev/null \
            && ! cmp -s "$_rc_heal" "$_rc_sf"; then
          _so_atomic_write "$_rc_sf" "$_rc_heal"
          _so_update_sha "$_rc_sdir"
        fi
        rm -f -- "$_rc_heal" 2>/dev/null || :
      fi
    fi
  fi

  # task_ids ja presentes em .tasks[] (snapshot)
  _rc_exfile=$(mktemp) || _so_die "mktemp falhou" 1
  jq -r '(.tasks // [])[].task_id // empty' "$_rc_sf" > "$_rc_exfile" 2>/dev/null || :

  # awk: parseia tasks.md -> emite "id<TAB>titulo" para cada task CONCLUIDA
  # ainda AUSENTE de .tasks[]. O seen-set vem do primeiro arquivo (_rc_exfile);
  # comparamos por FILENAME (nao FNR==NR) porque o exfile pode estar VAZIO
  # (.tasks[] ainda sem entradas) — FNR==NR falharia consumindo o tasks.md
  # inteiro como seen-set.
  _rc_missing=$(awk -v exf="$_rc_exfile" '
    { sub(/\r$/, "") }
    FILENAME == exf { seen[$0] = 1; next }
    function flush() {
      if (cur != "" && nsub > 0 && ndone == nsub && !(cur in seen)) {
        print cur "\t" titulo
      }
      cur = ""; titulo = ""; nsub = 0; ndone = 0
    }
    /^#/ {
      flush()
      if ($0 ~ /^### /) {
        line = $0; sub(/^### +/, "", line)
        split(line, a, /[ \t]+/); id = a[1]
        if (id ~ /^[0-9]+(\.[0-9]+)+(-bis(\.[0-9]+)*)?$/) {
          cur = id
          t = line; sub(/^[^ \t]+[ \t]+/, "", t)
          gsub(/`/, "", t); sub(/[ \t]*\[[CAM]\][ \t]*$/, "", t)
          gsub(/\t/, " ", t)
          titulo = t
        }
      }
      next
    }
    /^- \[.\] / {
      if (cur != "") {
        st = substr($0, 4, 1)
        nsub++
        if (st == "x" || st == "X") ndone++
      }
      next
    }
    END { flush() }
  ' "$_rc_exfile" "$_rc_md")
  rm -f -- "$_rc_exfile" 2>/dev/null || :

  if [ -z "$_rc_missing" ]; then
    [ "$_rc_dry" = "yes" ] || printf '0\n'
    return 0
  fi

  if [ "$_rc_dry" = "yes" ]; then
    printf '%s\n' "$_rc_missing" | cut -f1
    return 0
  fi

  # Loop via here-doc (roda no shell corrente, nao em subshell — contador
  # persiste). record-task usa vars sem prefixo _rc_, entao nao colide com
  # _rc_id/_rc_ttl/_rc_count/_rc_missing do loop.
  _rc_count=0
  while IFS="$(printf '\t')" read -r _rc_id _rc_ttl; do
    [ -n "$_rc_id" ] || continue
    _so_cmd_record_task --state-dir "$_rc_sdir" --task-id "$_rc_id" \
      --titulo "$_rc_ttl" --wave-id "$_rc_wid" --outcome pass \
      --testes-rodados 0 --testes-passados 0 \
      --arquivos '[]' --origem reconcile --if-absent >/dev/null \
      || _so_die "reconcile-tasks: record-task falhou para $_rc_id" 1
    _rc_count=$((_rc_count + 1))
  done <<EOF
$_rc_missing
EOF
  printf '%s\n' "$_rc_count"
}

_so_cmd_current_id() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _so_die_usage "current-id: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _so_die_usage "current-id: --state-dir obrigatorio"
  _so_require_jq
  if [ "$(_sr_backend "$_sdir")" = "sqlite" ]; then
    _so_db_current_id "$_sdir"
    return 0
  fi
  _sf=$(_so_state_file "$_sdir")
  [ -f "$_sf" ] || _so_die "current-id: state.json ausente" 1
  jq -r '
    ((.waves // .ondas) // []) as $w
    | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end
  ' "$_sf"
}

# git-commit: faz commit local no projeto-alvo (NUNCA push — Principio V).
_so_cmd_git_commit() {
  _sdir=""
  _pap=""
  _motivo=""
  _onda=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)         _sdir=$2; shift 2 ;;
      --projeto-alvo-path) _pap=$2;  shift 2 ;;
      --motivo)            _motivo=$2; shift 2 ;;
      --onda-id)           _onda=$2; shift 2 ;;
      *) _so_die_usage "git-commit: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]   || _so_die_usage "git-commit: --state-dir obrigatorio"
  [ -n "$_pap" ]    || _so_die_usage "git-commit: --projeto-alvo-path obrigatorio"
  [ -n "$_motivo" ] || _so_die_usage "git-commit: --motivo obrigatorio"
  command -v git >/dev/null 2>&1 || _so_die "git-commit: git nao encontrado no PATH" 1
  [ -d "$_pap" ] || _so_die "git-commit: projeto-alvo-path nao existe: $_pap" 1
  # Worktree-safe: em git worktree o `.git` e um ARQUIVO (`gitdir: ...`), nao
  # diretorio — `[ -d .git ]` daria falso-negativo e quebraria `cstk session`.
  # `rev-parse` cobre repo normal, worktree e submodulo (mesma checagem de
  # commit-mode.sh).
  if ! git -C "$_pap" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _so_die "git-commit: $_pap nao e repositorio git (init manual antes)" 1
  fi
  if [ -z "$_onda" ]; then
    _onda=$(_so_cmd_current_id --state-dir "$_sdir")
  fi
  # Sanitiza motivo: remove newlines + limita a 100 chars
  _motivo_safe=$(printf '%s' "$_motivo" | tr '\n\r' '  ' | cut -c 1-100)

  # Staging por allowlist derivada (living-specs FASE 5, FR-014):
  # delega a commit-mode.sh stage-derived em vez de `git add -- .` — o
  # wave-commit pode tocar qualquer path do repo (sem --scope-dir), mas o
  # staging fica explicito por allowlist (tracked mudados + untracked
  # NOVOS desde o ultimo snapshot da onda), nunca staging amplo.
  _sog_selfdir=$(_so_self_dir) || _sog_selfdir="."
  _sog_cm="$_sog_selfdir/commit-mode.sh"
  [ -f "$_sog_cm" ] || _so_die "git-commit: commit-mode.sh nao encontrado em $_sog_selfdir" 1

  # O baseline (commit-baseline.txt) e capturado no INICIO da onda por
  # `state-ondas.sh start` (best-effort, via .execution.target_project_path
  # do proprio state.json — data-model.md UntrackedBaseline: "escrito...
  # no inicio da onda"). Snapshotar aqui, no momento do commit (fim da
  # onda), seria tarde demais: todo trabalho da onda ja teria acontecido,
  # entao o baseline capturaria o MESMO untracked que stage-derived tentaria
  # marcar como "novo" — diff sempre vazio. Se `start` nao gravou baseline
  # (target_project_path ausente/invalido, git ausente), stage-derived cai
  # no fail-closed documentado: untracked fica fora, tracked segue incluido.
  _sog_stage_rc=0
  sh "$_sog_cm" stage-derived --state-dir "$_sdir" --projeto-alvo-path "$_pap" \
    || _sog_stage_rc=$?

  if [ "$_sog_stage_rc" = 3 ]; then
    # Allowlist vazia: preserva o comportamento atual de "nada para
    # commitar" (no-op), sem quebrar o contrato existente.
    _so_log "git-commit: nada para commitar (no-op)"
    return 0
  fi
  [ "$_sog_stage_rc" = 0 ] || _so_die "git-commit: stage-derived falhou (exit $_sog_stage_rc) em $_pap" 1

  ( cd -- "$_pap" \
    && if git diff --cached --quiet; then
         _so_log "git-commit: nada para commitar (no-op)"
       else
         git commit -m "chore(agente-00c): $_onda - $_motivo_safe" >/dev/null \
           || _so_die "git commit falhou em $_pap" 1
         _so_log "git-commit: commit feito ($_onda)"
       fi
  ) || exit 1
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
state-ondas.sh — ciclo de vida de Ondas (FASE 3.4).

USO:
  state-ondas.sh start          --state-dir DIR
  state-ondas.sh end            --state-dir DIR --motivo-termino MOTIVO
                                [--proxima-agendada-para ISO]
                                [--add-etapa STAGE]...
                                [--next-instruction TEXT]
  state-ondas.sh tool-call-tick --state-dir DIR
  state-ondas.sh record-skill   --state-dir DIR --skill NAME
                                [--decisao-id DEC-NNN]
  state-ondas.sh record-task    --state-dir DIR --task-id ID --outcome pass|fail
                                [--titulo T] [--wave-id ID] [--testes-rodados N]
                                [--testes-passados N] [--lint-ok true|false]
                                [--arquivos JSON-ARRAY] [--origem TAG] [--if-absent]
  state-ondas.sh reconcile-tasks --state-dir DIR --tasks-md PATH
                                [--wave-id ID] [--dry-run]
  state-ondas.sh current-id     --state-dir DIR
  state-ondas.sh git-commit     --state-dir DIR --projeto-alvo-path PATH
                                --motivo MOTIVO [--onda-id ID]

Motivos validos para `end`:
  etapa_concluida_avancando | threshold_proxy_atingido | bloqueio_humano |
  aborto | concluido

EXIT:
  0 sucesso
  1 erro generico
  2 uso incorreto

NUNCA `git push` — Principio V (Blast Radius Confinado).
HELP
  exit 2
fi

_so_cmd_wave_status() {
  _ws_sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _ws_sdir=$2; shift 2 ;;
      *) _so_die_usage "wave-status: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_ws_sdir" ] || _so_die_usage "wave-status: --state-dir obrigatorio"
  _so_require_jq
  if [ "$(_sr_backend "$_ws_sdir")" = "sqlite" ]; then
    _so_db_wave_status "$_ws_sdir"
    return 0
  fi
  _ws_sf=$(_so_state_file "$_ws_sdir")
  [ -f "$_ws_sf" ] || _so_die "wave-status: state.json ausente em $_ws_sdir" 1
  jq -r '
    ((.waves // .ondas) // []) as $w
    | if   ($w | length) == 0                  then "none"
      elif ($w[-1].termination_reason // null) == null then "open"
      else "closed" end
  ' "$_ws_sf"
}

_so_cmd_reconcile_wave() {
  _rcw_sdir=""; _rcw_phase=""; _rcw_md=""; _rcw_dry="no"; _rcw_terminal=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)      _rcw_sdir=$2; shift 2 ;;
      --phase)          _rcw_phase=$2; shift 2 ;;
      --tasks-md)       _rcw_md=$2; shift 2 ;;
      --terminal-phase) _rcw_terminal=$2; shift 2 ;;
      --dry-run)        _rcw_dry="yes"; shift ;;
      *) _so_die_usage "reconcile-wave: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_rcw_sdir" ] || _so_die_usage "reconcile-wave: --state-dir obrigatorio"
  _so_require_jq
  # Existencia do estado — backend-aware (task 3.3): state.json so existe
  # sob backend JSON; sob SQLite o arquivo fonte de verdade e state.db.
  if [ "$(_sr_backend "$_rcw_sdir")" = "sqlite" ]; then
    [ -f "$(_sr_db_file "$_rcw_sdir")" ] || _so_die "reconcile-wave: state.db ausente em $_rcw_sdir" 1
  else
    _rcw_sf=$(_so_state_file "$_rcw_sdir")
    [ -f "$_rcw_sf" ] || _so_die "reconcile-wave: state.json ausente em $_rcw_sdir" 1
  fi

  _rcw_selfdir=$(_so_self_dir) || _rcw_selfdir="."
  _rcw_pipeline="$_rcw_selfdir/pipeline.sh"
  _rcw_rw="$_rcw_selfdir/state-rw.sh"
  [ -f "$_rcw_rw" ] || _so_die "reconcile-wave: state-rw.sh nao encontrado em $_rcw_selfdir" 1

  # Guarda de idempotencia: so recupera onda ABERTA. Onda fechada/inexistente
  # = no-op (exit 0). E o que torna seguro o pai chamar a CADA onda sem
  # double-count em accumulated_metrics (que `end` incrementa por chamada).
  # Via _so_cmd_wave_status (ja dispatcha por backend) em vez de jq direto
  # no arquivo — o jq inline so funcionava sob backend JSON.
  _rcw_status=$(_so_cmd_wave_status --state-dir "$_rcw_sdir")
  if [ "$_rcw_status" != "open" ]; then
    printf 'noop (%s)\n' "$_rcw_status"
    return 0
  fi

  # Resolve a fase que a onda rodou. current_stage == fase corrente ate o
  # fechamento (init grava current_stage = fase a rodar; o avanco do ponteiro
  # so ocorre ao fechar a onda). --phase permite ao pai fixar explicitamente.
  # Via state-rw.sh get (backend-aware) em vez de jq direto no arquivo.
  if [ -z "$_rcw_phase" ]; then
    _rcw_phase=$(sh "$_rcw_rw" get --state-dir "$_rcw_sdir" --field '.current_stage' 2>/dev/null) || _rcw_phase=""
    case "$_rcw_phase" in null) _rcw_phase="" ;; esac
  fi
  [ -n "$_rcw_phase" ] || _so_die "reconcile-wave: nao foi possivel resolver a fase (--phase ou .current_stage)" 1

  # Proxima fase do pipeline (vazio = fase terminal). A terminalidade depende
  # do FLAVOR: feature-00c termina em review-task; agente-00c em review-features.
  # pipeline.sh next-stage usa a lista COMPLETA (agente-00c), entao para
  # feature-00c o pai passa --terminal-phase review-task — quando a fase
  # corrente == terminal-phase, tratamos como terminal (next vazio) sem
  # consultar pipeline.sh (que avancaria erroneamente para review-features).
  if [ -n "$_rcw_terminal" ] && [ "$_rcw_phase" = "$_rcw_terminal" ]; then
    _rcw_next=""
  elif [ -f "$_rcw_pipeline" ]; then
    _rcw_next=$(sh "$_rcw_pipeline" next-stage --current "$_rcw_phase" 2>/dev/null) || _rcw_next=""
  else
    _rcw_next=""
  fi

  if [ "$_rcw_dry" = "yes" ]; then
    if [ -n "$_rcw_next" ]; then
      printf 'would reconcile: phase=%s -> next=%s motivo=etapa_concluida_avancando\n' "$_rcw_phase" "$_rcw_next"
    else
      printf 'would reconcile: phase=%s (terminal) -> status=concluida motivo=concluido\n' "$_rcw_phase"
    fi
    return 0
  fi

  # 1. execute-task: back-fill .tasks[] (senao recall ingere 0 tasks). Best-effort.
  if [ "$_rcw_phase" = "execute-task" ] && [ -n "$_rcw_md" ]; then
    _so_cmd_reconcile_tasks --state-dir "$_rcw_sdir" --tasks-md "$_rcw_md" >/dev/null 2>&1 || :
  fi

  # 2. registrar a skill da fase (idempotente) — senao some do audit.
  _so_cmd_record_skill --state-dir "$_rcw_sdir" --skill "$_rcw_phase" >/dev/null 2>&1 || :

  # 3+4. fechar a onda E avancar o ponteiro (fail-loud: end usa _so_die/exit).
  # Ramo com proxima fase usa `end --advance` (wave-close-advance FR-005):
  # fechamento + current_stage + next_instruction saem do MESMO write
  # atomico — um crash entre "fechar" e "avancar" nao pode mais deixar
  # onda fechada com ponteiro stale (a variante que a guarda de
  # idempotencia acima tornaria invisivel). O texto proprio da rede de
  # seguranca entra via --next-instruction (FR-004: sobrescreve so o
  # texto; o avanco de fase ocorre igual).
  if [ -n "$_rcw_next" ]; then
    _rcw_motivo="etapa_concluida_avancando"
    _rcw_instr=$(printf 'Iniciar etapa %s — retomada pela rede de seguranca do command pai (onda anterior fechada sem Schedule intent).' "$_rcw_next")
    # --advance-from pina a MESMA fase ja resolvida acima (--phase do pai
    # ou .current_stage) — garante next identico ao _rcw_next do stdout.
    _so_cmd_end --state-dir "$_rcw_sdir" --motivo-termino "$_rcw_motivo" \
      --advance --advance-from "$_rcw_phase" \
      --next-instruction "$_rcw_instr" >/dev/null
  else
    _rcw_motivo="concluido"
    _so_cmd_end --state-dir "$_rcw_sdir" --motivo-termino "$_rcw_motivo" >/dev/null
    # Promocao a status terminal via read-patch-write ATOMICO (uma unica
    # transacao), NAO 5 `set` sequenciais: sob backend sqlite a CHECK de
    # execution (status IN ('abortada','concluida') <=> finished_at NOT
    # NULL) rejeita qualquer estado intermediario onde status=concluida e
    # finished_at ainda esta NULL (ou vice-versa) — nenhuma ordem de sets
    # de UMA coluna por vez consegue transitar (status=em_andamento,
    # finished_at=NULL) -> (status=concluida, finished_at=<ts>) sem passar
    # por um estado invalido. `write` aplica as 5 mudancas na mesma
    # transacao (C4), backend-agnostico (funciona identico sob JSON).
    _rcw_now=$(_so_iso_now)
    _rcw_doc=$(sh "$_rcw_rw" read --state-dir "$_rcw_sdir") \
      || _so_die "reconcile-wave: read falhou ao promover status terminal" 1
    _rcw_patched=$(printf '%s' "$_rcw_doc" | jq --arg now "$_rcw_now" '
      .execution.status = "concluida"
      | .execution.termination_reason = "concluido"
      | .execution.finished_at = $now
      | .current_stage = "concluida"
      | .next_instruction = "Execucao concluida — nenhuma proxima etapa."
    ') || _so_die "reconcile-wave: jq falhou ao promover status terminal" 1
    printf '%s' "$_rcw_patched" | sh "$_rcw_rw" write --state-dir "$_rcw_sdir" >/dev/null \
      || _so_die "reconcile-wave: write falhou ao promover status terminal" 1
  fi

  if [ -n "$_rcw_next" ]; then
    printf 'reconciled (phase=%s motivo=%s next=%s)\n' "$_rcw_phase" "$_rcw_motivo" "$_rcw_next"
  else
    printf 'reconciled (phase=%s motivo=%s terminal)\n' "$_rcw_phase" "$_rcw_motivo"
  fi
}

_SO_SUBCMD=$1
shift

case "$_SO_SUBCMD" in
  start)            _so_cmd_start "$@" ;;
  end)              _so_cmd_end "$@" ;;
  tool-call-tick)   _so_cmd_tool_call_tick "$@" ;;
  record-skill)     _so_cmd_record_skill "$@" ;;
  record-task)      _so_cmd_record_task "$@" ;;
  reconcile-tasks)  _so_cmd_reconcile_tasks "$@" ;;
  wave-status)      _so_cmd_wave_status "$@" ;;
  reconcile-wave)   _so_cmd_reconcile_wave "$@" ;;
  current-id)       _so_cmd_current_id "$@" ;;
  export-snapshot)  _so_cmd_export_snapshot "$@" ;;
  git-commit)       _so_cmd_git_commit "$@" ;;
  -h|--help|help)   exit 0 ;;
  *) _so_die_usage "subcomando desconhecido: $_SO_SUBCMD" ;;
esac
