#!/bin/sh
# jira-map.sh — CRUD atomico sobre o mapeamento local<->Jira do plugin
# cstk-jira (feature cstk-jira, FASE 2 tarefa 2.3).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity SyncMapping (jira-map.tsv,
#      FR-013/FR-014); docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-map.sh`; docs/specs/cstk-jira/tasks.md 2.3.1-2.3.6.
#
# Arquivo: `<cwd>/docs/specs/<feature>/jira-map.tsv`, TAB-separado, 1a linha
# = cabecalho `local_key kind jira_id jira_key state`. Existencia do arquivo
# = feature convertida (data-model.md); ausencia = tratada como "nenhum
# mapeamento" (mesma convencao de tasks.md ausente em jira-tasks.sh: exit 1,
# nao exit 3 — exit 3 fica reservado a ProjectConfig/jira-config.sh FR-017).
#
# Subcomandos:
#   jira-map.sh get --feature F --local-key K
#       — Imprime a linha TSV completa (5 colunas) do local_key K em stdout.
#         Exit 1 se o arquivo ou a chave nao existirem.
#
#   jira-map.sh put --feature F --local-key K --kind KIND --jira-id ID
#                    --jira-key KEY
#       — Insere uma linha nova com state=active, de forma atomica (arquivo
#         temporario colocado no mesmo diretorio + `mv`). KIND restrito a
#         `epic`/`task`/`subtask` (data-model.md). RECUSA (exit 1, nada
#         escrito) se o local_key ja existir no arquivo em QUALQUER estado
#         (active ou orphan) — data-model.md "criacao so para local_key
#         ausente do arquivo" (FR-013/SC-002); reativar um orphan e
#         responsabilidade exclusiva de `relink`, nunca de `put`.
#
#   jira-map.sh mark-orphans --feature F
#       — Compara as chaves `active` do mapeamento contra a saida de
#         `jira-tasks.sh items --feature F` (script irmao, mesmo diretorio).
#         Toda chave `active` ausente de `tasks.md` vira `orphan` (rewrite
#         atomico); o card Jira NUNCA e apagado (FR-012). Imprime em stdout
#         TODAS as linhas com state=orphan apos a atualizacao (novas e
#         preexistentes) para dar o quadro completo a quem decide. Exit 6
#         se houver pelo menos 1 orfao (sinal de decisao humana pendente —
#         contracts/plugin-scripts.md); exit 0 se nenhum.
#
#   jira-map.sh relink --feature F --local-key K --jira-key KEY \
#                       [--new-local-key NK]
#       — Religa um orphan por decisao humana: exige que K exista com
#         state=orphan E que o jira_key armazenado seja EXATAMENTE KEY
#         (confirmacao explicita do operador de qual card esta sendo
#         religado — nao existe --jira-id porque relink nunca troca qual
#         card e apontado, so reativa o mesmo). Recusa (exit 1) se K nao
#         existir, ja estiver active, ou se KEY nao conferir com o
#         jira_key armazenado. Nunca apaga a linha original (FR-012).
#         `--new-local-key NK` (opcional, FR-012/data-model.md renumeracao):
#         em vez de reativar K no lugar, MOVE a linha para NK (a tarefa
#         local foi renumerada, ex.: 2.3->2.4, mas o card Jira e o MESMO —
#         evita o card duplicado que o proximo `convert` criaria se K
#         ficasse orphan para sempre). Recusa (exit 1) se NK ja existir no
#         mapeamento em qualquer estado (mesma disciplina de `put`). Sem
#         `--new-local-key`, comportamento identico ao anterior (reativa o
#         MESMO K). Em ambos os casos, fecha (best-effort, silencioso se
#         ausente) o ConflictRecord PENDENTE `reason=orphan` de (F, K) em
#         `runtime/conflicts.tsv` como `resolution=relinked`
#         (data-model.md ConflictRecord enum `resolution`) — sem isso, o
#         registro pendente continuaria suprimindo conflitos futuros do
#         mesmo par via `_js_conflict_pending_exists` (jira-sync.sh).
#
#   jira-map.sh milestone-get --feature F --name N --project-key K
#       — Imprime a linha TSV completa (5 colunas) de
#         `docs/specs/F/jira-milestones.tsv` cuja chave natural
#         `(project_key, milestone_name)` casa (K, N). Exit 1 se o arquivo
#         ou a chave nao existirem (data-model.md Entity Milestone).
#
#   jira-map.sh milestone-put --feature F --name N --kind round|release \
#                              --project-key K --state current|superseded|blocked \
#                              [--version-id ID]
#       — Upsert atomico por `(project_key, milestone_name)` em
#         `docs/specs/F/jira-milestones.tsv` (r02 FASE 16 task 16.3.4,
#         research.md Decision R2-3/R2-4). `--version-id` e OBRIGATORIO
#         para `--state current`/`superseded` (id devolvido por R12/R13);
#         OPCIONAL (pode ser omitido/vazio) so para `--state blocked`
#         (R12 negado antes de qualquer id existir, data-model.md coluna
#         `jira_version_id`). Ao gravar `current`, rebaixa QUALQUER outra
#         linha `current` do MESMO arquivo para `superseded` no MESMO
#         write (invariante: no maximo 1 `current` por feature) — `blocked`
#         NUNCA mexe em outras linhas (o marco anterior aplicado ao Epic
#         continua vigente ate uma nova resolucao ter sucesso).
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral (mapeamento/chave ausente,
#   insercao recusada); 2 uso incorreto; 6 orfao(s) detectado(s) apos
#   `mark-orphans` (FR-012) — nada foi sobrescrito.
#
# Nenhum host/credencial e tocado por este script (so parseia/reescreve o
# arquivo TSV local versionado da feature). Excecao aditiva: `relink`
# tambem fecha (best-effort) o ConflictRecord pendente correspondente em
# `runtime/conflicts.tsv` — arquivo NAO-versionado (mesmo path que
# jira-sync.sh ja le/escreve), nunca requisicao de rede.

set -eu

_JM_NAME="jira-map"
_JM_KINDS="epic task subtask"

# Mesmo path/schema de `_JS_CONFLICTS_FILE`/`_JS_CONFLICTS_HEADER` em
# jira-sync.sh (nao compartilhado — cada script mantem sua propria copia
# minima, mesmo idioma de `_ji_cred_read` em jira-io.sh). Runtime/nao-
# versionado; so tocado por `relink` (fechamento best-effort, ver acima).
_JM_CONFLICTS_FILE="./.claude/cstk-jira/runtime/conflicts.tsv"

# Newline literal — usado para detectar valores adversariais que tentariam
# injetar uma linha inteira via argumento (--jira-id/--jira-key/--local-key
# vindo de fonte externa). NAO usar "$(printf '\n')": command substitution
# descarta newlines finais e devolveria string vazia (gotcha conhecido —
# um padrao `*""*` casaria QUALQUER string, inclusive as validas).
_JM_NL='
'

_jm_die_usage() { printf '%s: %s\n' "$_JM_NAME" "$1" >&2; exit 2; }
_jm_die()       { printf '%s: %s\n' "$_JM_NAME" "$1" >&2; exit "${2:-1}"; }

_jm_usage() {
  cat <<'HELP'
jira-map.sh — CRUD atomico do mapeamento local<->Jira (jira-map.tsv)

USO:
  jira-map.sh get --feature F --local-key K
      Imprime a linha TSV do local_key K; exit 1 se ausente

  jira-map.sh put --feature F --local-key K --kind epic|task|subtask \
                   --jira-id ID --jira-key KEY
      Insere linha nova (state=active), atomico; recusa local_key ja
      existente em qualquer estado (idempotencia FR-013)

  jira-map.sh mark-orphans --feature F
      Marca orphan as chaves active ausentes de `jira-tasks.sh items`;
      imprime todos os orfaos; exit 6 se houver algum (FR-012)

  jira-map.sh relink --feature F --local-key K --jira-key KEY \
                      [--new-local-key NK]
      Religa um orphan (KEY deve conferir com o jira_key armazenado);
      com --new-local-key, move a linha para NK (renumeracao). Fecha
      (best-effort) o ConflictRecord pendente reason=orphan do par.

  jira-map.sh milestone-get --feature F --name N --project-key K
      Imprime a linha TSV de jira-milestones.tsv para (K, N); exit 1 se
      ausente.

  jira-map.sh milestone-put --feature F --name N --kind round|release \
                             --project-key K --state current|superseded|blocked \
                             [--version-id ID]
      Upsert atomico por (project_key, milestone_name); --version-id
      obrigatorio exceto para --state blocked. Gravar current rebaixa
      qualquer outra current do arquivo para superseded no mesmo write.

  jira-map.sh milestone-id-known --feature F --project-key K --version-id ID
      r02 FASE 16 task 16.4.3 (plan.md SEC-10): exit 0 se ID aparece em
      alguma linha de jira-milestones.tsv com (project_key=K) e
      state em {current, superseded}; exit 1 caso contrario (inclusive
      arquivo ausente). Usado por `jira-sync.sh` ANTES de emitir
      `update.fixVersions` `remove` — nunca remove um id que o sidecar
      versionado da feature nao reconhece mais (evita clobber de marco
      alterado a mao no Jira).

Arquivo: <cwd>/docs/specs/F/jira-map.tsv (TAB-separado, cabecalho na 1a linha)
Arquivo: <cwd>/docs/specs/F/jira-milestones.tsv (idem, chave (project_key, name))

EXIT CODES:
  0 sucesso   1 erro geral   2 uso incorreto   6 orfao(s) apos mark-orphans
HELP
}

# _jm_is_safe_feature VALUE -> mesma allowlist de path de jira-tasks.sh
# (defesa contra path traversal via --feature): charset [A-Za-z0-9_-].
_jm_is_safe_feature() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}

# _jm_is_safe_field VALUE -> exit 0 se VALUE e nao-vazio e nao contem TAB
# nem newline (protege a integridade de linha/coluna do TSV contra
# injecao via argumento).
_jm_is_safe_field() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *"$(printf '\t')"*) return 1 ;;
  esac
  case "$1" in
    *"$_JM_NL"*) return 1 ;;
  esac
  return 0
}

# _jm_script_dir -> diretorio deste script (para localizar jira-tasks.sh
# irmao, usado por mark-orphans; mesmo padrao de jira-tasks.sh->jira-config.sh).
_jm_script_dir() {
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
}

# _jm_map_file FEATURE -> imprime o path do jira-map.tsv da feature.
_jm_map_file() {
  printf '%s\n' "./docs/specs/$1/jira-map.tsv"
}

_JM_HEADER='local_key	kind	jira_id	jira_key	state'

# jira-milestones.tsv (data-model.md Entity Milestone, r02 FASE 16) —
# arquivo/schema DISTINTO de jira-map.tsv (chave natural
# (project_key, milestone_name), nao local_key).
_JM_MILESTONE_HEADER='milestone_name	milestone_kind	jira_version_id	project_key	state'
_JM_MILESTONE_KINDS="round release"
_JM_MILESTONE_STATES="current superseded blocked"

# _jm_milestone_file FEATURE -> imprime o path do jira-milestones.tsv da
# feature (mesmo diretorio de jira-map.tsv, arquivo irmao).
_jm_milestone_file() {
  printf '%s\n' "./docs/specs/$1/jira-milestones.tsv"
}

# --- get -----------------------------------------------------------------

_jm_cmd_get() {
  _jmg_feature=""
  _jmg_key=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)   [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmg_feature="$2"; shift 2 ;;
      --local-key) [ "$#" -ge 2 ] || _jm_die_usage "--local-key requer valor"; _jmg_key="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmg_feature" ] || _jm_die_usage "get requer --feature F"
  [ -n "$_jmg_key" ] || _jm_die_usage "get requer --local-key K"
  _jm_is_safe_feature "$_jmg_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmg_feature"

  _jmg_map=$(_jm_map_file "$_jmg_feature")
  [ -f "$_jmg_map" ] || _jm_die "mapeamento nao encontrado: $_jmg_map" 1

  if _jmg_line=$(awk -F '\t' -v k="$_jmg_key" \
      'NR > 1 && $1 == k { print; f = 1; exit } END { exit (f ? 0 : 1) }' "$_jmg_map"); then
    printf '%s\n' "$_jmg_line"
  else
    _jm_die "local_key nao encontrado no mapeamento: $_jmg_key" 1
  fi
}

# --- put -------------------------------------------------------------------

_jm_cmd_put() {
  _jmp_feature=""
  _jmp_key=""
  _jmp_kind=""
  _jmp_id=""
  _jmp_jkey=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)   [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmp_feature="$2"; shift 2 ;;
      --local-key) [ "$#" -ge 2 ] || _jm_die_usage "--local-key requer valor"; _jmp_key="$2"; shift 2 ;;
      --kind)      [ "$#" -ge 2 ] || _jm_die_usage "--kind requer valor"; _jmp_kind="$2"; shift 2 ;;
      --jira-id)   [ "$#" -ge 2 ] || _jm_die_usage "--jira-id requer valor"; _jmp_id="$2"; shift 2 ;;
      --jira-key)  [ "$#" -ge 2 ] || _jm_die_usage "--jira-key requer valor"; _jmp_jkey="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmp_feature" ] || _jm_die_usage "put requer --feature F"
  _jm_is_safe_feature "$_jmp_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmp_feature"
  _jm_is_safe_field "$_jmp_key" || _jm_die_usage "put requer --local-key K valido (nao-vazio, sem TAB/newline)"
  _jm_is_safe_field "$_jmp_id" || _jm_die_usage "put requer --jira-id ID valido (nao-vazio, sem TAB/newline)"
  _jm_is_safe_field "$_jmp_jkey" || _jm_die_usage "put requer --jira-key KEY valido (nao-vazio, sem TAB/newline)"

  case " $_JM_KINDS " in
    *" $_jmp_kind "*) : ;;
    *) _jm_die_usage "--kind invalido: '$_jmp_kind' (validos: $_JM_KINDS)" ;;
  esac

  _jmp_map=$(_jm_map_file "$_jmp_feature")
  _jmp_dir=$(dirname -- "$_jmp_map")
  [ -d "$_jmp_dir" ] || _jm_die "diretorio da feature nao encontrado: $_jmp_dir" 1

  if [ -f "$_jmp_map" ]; then
    _jmp_existing=$(awk -F '\t' -v k="$_jmp_key" \
      'NR > 1 && $1 == k { print $5; exit }' "$_jmp_map")
    if [ -n "$_jmp_existing" ]; then
      _jm_die "local_key ja mapeado (state=$_jmp_existing): $_jmp_key — insercao recusada (idempotencia FR-013; use 'relink' para reativar um orphan)" 1
    fi
  fi

  _jmp_tmp="$_jmp_map.tmp.$$"
  {
    if [ -f "$_jmp_map" ]; then
      cat "$_jmp_map"
    else
      printf '%s\n' "$_JM_HEADER"
    fi
    printf '%s\t%s\t%s\t%s\tactive\n' "$_jmp_key" "$_jmp_kind" "$_jmp_id" "$_jmp_jkey"
  } > "$_jmp_tmp"
  mv -- "$_jmp_tmp" "$_jmp_map"
}

# --- mark-orphans ----------------------------------------------------------

_jm_cmd_mark_orphans() {
  _jmo_feature=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature) [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmo_feature="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmo_feature" ] || _jm_die_usage "mark-orphans requer --feature F"
  _jm_is_safe_feature "$_jmo_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmo_feature"

  _jmo_map=$(_jm_map_file "$_jmo_feature")
  [ -f "$_jmo_map" ] || _jm_die "mapeamento nao encontrado: $_jmo_map" 1

  _jmo_tasks_script="$(_jm_script_dir)/jira-tasks.sh"
  [ -x "$_jmo_tasks_script" ] || _jm_die "jira-tasks.sh nao encontrado/executavel: $_jmo_tasks_script" 1

  # Captura em variavel (nao em pipeline direto) para preservar o exit code
  # de jira-tasks.sh sob 'set -e' — um pipeline `cmd | cut` mascararia uma
  # falha de `cmd` com o exit 0 de `cut` sobre entrada vazia.
  _jmo_items=$("$_jmo_tasks_script" items --feature "$_jmo_feature") \
    || _jm_die "jira-tasks.sh items falhou para a feature: $_jmo_feature" 1

  _jmo_keys_tmp="$_jmo_map.keys.$$"
  printf '%s\n' "$_jmo_items" | cut -f1 > "$_jmo_keys_tmp"

  _jmo_tmp="$_jmo_map.tmp.$$"
  awk -F '\t' -v OFS='\t' -v keysfile="$_jmo_keys_tmp" '
    BEGIN {
      while ((getline k < keysfile) > 0) keep[k] = 1
      close(keysfile)
    }
    NR == 1 { print; next }
    {
      if ($5 == "active" && !($1 in keep)) $5 = "orphan"
      print
    }
  ' "$_jmo_map" > "$_jmo_tmp"
  rm -f "$_jmo_keys_tmp"
  mv -- "$_jmo_tmp" "$_jmo_map"

  _jmo_orphans=$(awk -F '\t' 'NR > 1 && $5 == "orphan"' "$_jmo_map")
  if [ -n "$_jmo_orphans" ]; then
    printf '%s\n' "$_jmo_orphans"
    exit 6
  fi
  exit 0
}

# --- relink ------------------------------------------------------------

_jm_cmd_relink() {
  _jmr_feature=""
  _jmr_key=""
  _jmr_jkey=""
  _jmr_new_key=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)        [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmr_feature="$2"; shift 2 ;;
      --local-key)      [ "$#" -ge 2 ] || _jm_die_usage "--local-key requer valor"; _jmr_key="$2"; shift 2 ;;
      --jira-key)       [ "$#" -ge 2 ] || _jm_die_usage "--jira-key requer valor"; _jmr_jkey="$2"; shift 2 ;;
      --new-local-key)  [ "$#" -ge 2 ] || _jm_die_usage "--new-local-key requer valor"; _jmr_new_key="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmr_feature" ] || _jm_die_usage "relink requer --feature F"
  _jm_is_safe_feature "$_jmr_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmr_feature"
  _jm_is_safe_field "$_jmr_key" || _jm_die_usage "relink requer --local-key K valido (nao-vazio, sem TAB/newline)"
  _jm_is_safe_field "$_jmr_jkey" || _jm_die_usage "relink requer --jira-key KEY valido (nao-vazio, sem TAB/newline)"
  if [ -n "$_jmr_new_key" ]; then
    _jm_is_safe_field "$_jmr_new_key" \
      || _jm_die_usage "--new-local-key invalido (nao-vazio, sem TAB/newline): $_jmr_new_key"
  fi

  _jmr_map=$(_jm_map_file "$_jmr_feature")
  [ -f "$_jmr_map" ] || _jm_die "mapeamento nao encontrado: $_jmr_map" 1

  _jmr_line=$(awk -F '\t' -v k="$_jmr_key" \
    'NR > 1 && $1 == k { print; exit }' "$_jmr_map")
  [ -n "$_jmr_line" ] || _jm_die "local_key nao encontrado no mapeamento: $_jmr_key" 1

  _jmr_state=$(printf '%s' "$_jmr_line" | cut -f5)
  _jmr_stored_jkey=$(printf '%s' "$_jmr_line" | cut -f4)

  [ "$_jmr_state" = "orphan" ] \
    || _jm_die "local_key nao esta orphan (state=$_jmr_state), nada para religar: $_jmr_key" 1
  [ "$_jmr_stored_jkey" = "$_jmr_jkey" ] \
    || _jm_die "jira-key informado ($_jmr_jkey) nao confere com o mapeado ($_jmr_stored_jkey) para $_jmr_key — relink recusado" 1

  # Renumeracao (--new-local-key, FR-012/data-model.md): move a linha para
  # um local_key NOVO em vez de reativar K no lugar. Recusa se NK ja
  # existir no mapeamento em QUALQUER estado — mesma disciplina de `put`
  # (nunca sobrescreve/duplica uma linha existente). Sem --new-local-key
  # (ou igual a K), comportamento identico ao anterior.
  if [ -n "$_jmr_new_key" ] && [ "$_jmr_new_key" != "$_jmr_key" ]; then
    _jmr_new_exists=$(awk -F '\t' -v nk="$_jmr_new_key" \
      'NR > 1 && $1 == nk { print "1"; exit }' "$_jmr_map")
    [ -z "$_jmr_new_exists" ] \
      || _jm_die "--new-local-key ja existe no mapeamento: $_jmr_new_key" 1
  else
    _jmr_new_key="$_jmr_key"
  fi

  _jmr_tmp="$_jmr_map.tmp.$$"
  awk -F '\t' -v OFS='\t' -v k="$_jmr_key" -v nk="$_jmr_new_key" '
    NR == 1 { print; next }
    { if ($1 == k) { $1 = nk; $5 = "active" } print }
  ' "$_jmr_map" > "$_jmr_tmp"
  mv -- "$_jmr_tmp" "$_jmr_map"

  _jm_close_orphan_conflict "$_jmr_feature" "$_jmr_key"
}

# _jm_close_orphan_conflict FEATURE LOCAL_KEY — fecha, best-effort, o
# ConflictRecord PENDENTE `reason=orphan` de (FEATURE, LOCAL_KEY) em
# `runtime/conflicts.tsv` como `resolution=relinked` (data-model.md Entity
# ConflictRecord). LOCAL_KEY e sempre o local_key ANTIGO (o que estava
# orphan) — e o que consta no ConflictRecord, mesmo quando `relink` moveu a
# linha para um --new-local-key. Sem efeito (retorna 0) se o arquivo nao
# existir ou nao houver registro pendente reason=orphan para o par: a
# renumeracao/reativacao do mapeamento MUST sempre completar mesmo que o
# conflito ja tenha sido fechado por outro caminho, ou nunca tenha existido
# (ex.: orphan marcado direto por `mark-orphans`, sem passar pelo
# processamento de eventos de jira-sync.sh que grava conflicts.tsv).
_jm_close_orphan_conflict() {
  [ -f "$_JM_CONFLICTS_FILE" ] || return 0
  _jmcc_tmp="$_JM_CONFLICTS_FILE.tmp.$$"
  if awk -F '\t' -v OFS='\t' -v f="$1" -v k="$2" '
       NR == 1 { print; next }
       $2 == f && $3 == k && $5 == "orphan" && $6 == "pending" { $6 = "relinked" }
       { print }
     ' "$_JM_CONFLICTS_FILE" > "$_jmcc_tmp"; then
    mv -- "$_jmcc_tmp" "$_JM_CONFLICTS_FILE"
  else
    rm -f "$_jmcc_tmp"
  fi
  return 0
}

# --- milestone-get ---------------------------------------------------------

_jm_cmd_milestone_get() {
  _jmmg_feature=""
  _jmmg_name=""
  _jmmg_pkey=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)     [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmmg_feature="$2"; shift 2 ;;
      --name)        [ "$#" -ge 2 ] || _jm_die_usage "--name requer valor"; _jmmg_name="$2"; shift 2 ;;
      --project-key) [ "$#" -ge 2 ] || _jm_die_usage "--project-key requer valor"; _jmmg_pkey="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmmg_feature" ] || _jm_die_usage "milestone-get requer --feature F"
  _jm_is_safe_feature "$_jmmg_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmmg_feature"
  _jm_is_safe_field "$_jmmg_name" || _jm_die_usage "milestone-get requer --name N valido (nao-vazio, sem TAB/newline)"
  _jm_is_safe_field "$_jmmg_pkey" || _jm_die_usage "milestone-get requer --project-key K valido (nao-vazio, sem TAB/newline)"

  _jmmg_file=$(_jm_milestone_file "$_jmmg_feature")
  [ -f "$_jmmg_file" ] || _jm_die "jira-milestones.tsv nao encontrado: $_jmmg_file" 1

  if _jmmg_line=$(awk -F '\t' -v n="$_jmmg_name" -v pk="$_jmmg_pkey" \
      'NR > 1 && $1 == n && $4 == pk { print; f = 1; exit } END { exit (f ? 0 : 1) }' "$_jmmg_file"); then
    printf '%s\n' "$_jmmg_line"
  else
    _jm_die "marco nao encontrado em jira-milestones.tsv: (project_key=$_jmmg_pkey, name=$_jmmg_name)" 1
  fi
}

# --- milestone-put -----------------------------------------------------------

_jm_cmd_milestone_put() {
  _jmmp_feature=""
  _jmmp_name=""
  _jmmp_kind=""
  _jmmp_vid=""
  _jmmp_pkey=""
  _jmmp_state=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)     [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmmp_feature="$2"; shift 2 ;;
      --name)        [ "$#" -ge 2 ] || _jm_die_usage "--name requer valor"; _jmmp_name="$2"; shift 2 ;;
      --kind)        [ "$#" -ge 2 ] || _jm_die_usage "--kind requer valor"; _jmmp_kind="$2"; shift 2 ;;
      --version-id)  [ "$#" -ge 2 ] || _jm_die_usage "--version-id requer valor"; _jmmp_vid="$2"; shift 2 ;;
      --project-key) [ "$#" -ge 2 ] || _jm_die_usage "--project-key requer valor"; _jmmp_pkey="$2"; shift 2 ;;
      --state)       [ "$#" -ge 2 ] || _jm_die_usage "--state requer valor"; _jmmp_state="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmmp_feature" ] || _jm_die_usage "milestone-put requer --feature F"
  _jm_is_safe_feature "$_jmmp_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmmp_feature"
  _jm_is_safe_field "$_jmmp_name" || _jm_die_usage "milestone-put requer --name N valido (nao-vazio, sem TAB/newline)"
  _jm_is_safe_field "$_jmmp_pkey" || _jm_die_usage "milestone-put requer --project-key K valido (nao-vazio, sem TAB/newline)"

  case " $_JM_MILESTONE_KINDS " in
    *" $_jmmp_kind "*) : ;;
    *) _jm_die_usage "--kind invalido: '$_jmmp_kind' (validos: $_JM_MILESTONE_KINDS)" ;;
  esac
  case " $_JM_MILESTONE_STATES " in
    *" $_jmmp_state "*) : ;;
    *) _jm_die_usage "--state invalido: '$_jmmp_state' (validos: $_JM_MILESTONE_STATES)" ;;
  esac

  # data-model.md coluna jira_version_id: obrigatorio exceto para
  # state=blocked (R12 negado ANTES de qualquer id existir — task 16.3.3).
  if [ "$_jmmp_state" = "blocked" ]; then
    if [ -n "$_jmmp_vid" ]; then
      _jm_is_safe_field "$_jmmp_vid" \
        || _jm_die_usage "--version-id invalido (sem TAB/newline): $_jmmp_vid"
    fi
  else
    _jm_is_safe_field "$_jmmp_vid" \
      || _jm_die_usage "milestone-put --state $_jmmp_state requer --version-id ID valido (nao-vazio, sem TAB/newline)"
  fi

  _jmmp_file=$(_jm_milestone_file "$_jmmp_feature")
  _jmmp_dir=$(dirname -- "$_jmmp_file")
  [ -d "$_jmmp_dir" ] || _jm_die "diretorio da feature nao encontrado: $_jmmp_dir" 1

  _jmmp_tmp="$_jmmp_file.tmp.$$"
  if [ -f "$_jmmp_file" ]; then
    # Upsert por (project_key, name): a linha casada e sobrescrita
    # DIRETO com os valores novos (bypassa o rebaixamento generico
    # abaixo, mesmo que ja fosse current); qualquer OUTRA linha com
    # state=current e rebaixada a superseded SOMENTE quando o write
    # corrente e --state current (task 16.3.4 — blocked nunca mexe em
    # outras linhas, o marco vigente do Epic nao muda so porque uma
    # tentativa de criar um marco NOVO falhou).
    awk -F '\t' -v OFS='\t' -v pk="$_jmmp_pkey" -v nm="$_jmmp_name" \
      -v newkind="$_jmmp_kind" -v newvid="$_jmmp_vid" -v newstate="$_jmmp_state" '
      NR == 1 { print; next }
      {
        if ($4 == pk && $1 == nm) {
          matched = 1
          print nm, newkind, newvid, pk, newstate
          next
        }
        if (newstate == "current" && $5 == "current") { $5 = "superseded" }
        print
      }
      END {
        if (!matched) print nm, newkind, newvid, pk, newstate
      }
    ' "$_jmmp_file" > "$_jmmp_tmp"
  else
    {
      printf '%s\n' "$_JM_MILESTONE_HEADER"
      printf '%s\t%s\t%s\t%s\t%s\n' "$_jmmp_name" "$_jmmp_kind" "$_jmmp_vid" "$_jmmp_pkey" "$_jmmp_state"
    } > "$_jmmp_tmp"
  fi
  mv -- "$_jmmp_tmp" "$_jmmp_file"
}

# --- milestone-id-known -----------------------------------------------------

# _jm_cmd_milestone_id_known --feature F --project-key K --version-id ID —
# r02 FASE 16 task 16.4.3 (plan.md SEC-10, data-model.md SyncMarker
# `written_fix_version_id`): exit 0 SOMENTE se ID aparece em alguma linha de
# jira-milestones.tsv com (project_key=K) e state em {current, superseded};
# exit 1 caso contrario (inclusive arquivo ausente — nunca tratado como
# erro, SEC-10 exige o comportamento mais conservador: sem sidecar, nenhum
# id e "conhecido"). READ-ONLY (nenhuma escrita).
_jm_cmd_milestone_id_known() {
  _jmik_feature=""
  _jmik_pkey=""
  _jmik_vid=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)     [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmik_feature="$2"; shift 2 ;;
      --project-key) [ "$#" -ge 2 ] || _jm_die_usage "--project-key requer valor"; _jmik_pkey="$2"; shift 2 ;;
      --version-id)  [ "$#" -ge 2 ] || _jm_die_usage "--version-id requer valor"; _jmik_vid="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmik_feature" ] || _jm_die_usage "milestone-id-known requer --feature F"
  _jm_is_safe_feature "$_jmik_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmik_feature"
  _jm_is_safe_field "$_jmik_pkey" || _jm_die_usage "milestone-id-known requer --project-key K valido (nao-vazio, sem TAB/newline)"
  _jm_is_safe_field "$_jmik_vid" || _jm_die_usage "milestone-id-known requer --version-id ID valido (nao-vazio, sem TAB/newline)"

  _jmik_file=$(_jm_milestone_file "$_jmik_feature")
  [ -f "$_jmik_file" ] || return 1

  awk -F '\t' -v pk="$_jmik_pkey" -v vid="$_jmik_vid" \
    'NR > 1 && $4 == pk && $3 == vid && ($5 == "current" || $5 == "superseded") { f = 1; exit } END { exit (f ? 0 : 1) }' \
    "$_jmik_file"
}

# --- dispatcher ---------------------------------------------------------

_jm_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_jm_sub" in
  ''|-h|--help|help)
    _jm_usage
    exit 0
    ;;
  get)
    _jm_cmd_get "$@"
    ;;
  put)
    _jm_cmd_put "$@"
    ;;
  mark-orphans)
    _jm_cmd_mark_orphans "$@"
    ;;
  relink)
    _jm_cmd_relink "$@"
    ;;
  milestone-get)
    _jm_cmd_milestone_get "$@"
    ;;
  milestone-put)
    _jm_cmd_milestone_put "$@"
    ;;
  milestone-id-known)
    _jm_cmd_milestone_id_known "$@"
    ;;
  *)
    _jm_die_usage "subcomando desconhecido: $_jm_sub (validos: get, put, mark-orphans, relink, milestone-get, milestone-put, milestone-id-known)"
    ;;
esac
