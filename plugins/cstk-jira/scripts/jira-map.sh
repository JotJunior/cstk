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
#   jira-map.sh relink --feature F --local-key K --jira-key KEY
#       — Religa um orphan por decisao humana: exige que K exista com
#         state=orphan E que o jira_key armazenado seja EXATAMENTE KEY
#         (confirmacao explicita do operador de qual card esta sendo
#         religado — nao existe --jira-id porque relink nunca troca qual
#         card e apontado, so reativa o mesmo). Recusa (exit 1) se K nao
#         existir, ja estiver active, ou se KEY nao conferir com o
#         jira_key armazenado. Nunca apaga a linha original (FR-012).
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral (mapeamento/chave ausente,
#   insercao recusada); 2 uso incorreto; 6 orfao(s) detectado(s) apos
#   `mark-orphans` (FR-012) — nada foi sobrescrito.
#
# Nenhum host/credencial e tocado por este script (so parseia/reescreve o
# arquivo TSV local versionado da feature).

set -eu

_JM_NAME="jira-map"
_JM_KINDS="epic task subtask"

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

  jira-map.sh relink --feature F --local-key K --jira-key KEY
      Religa um orphan (KEY deve conferir com o jira_key armazenado)

Arquivo: <cwd>/docs/specs/F/jira-map.tsv (TAB-separado, cabecalho na 1a linha)

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
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --feature)   [ "$#" -ge 2 ] || _jm_die_usage "--feature requer valor"; _jmr_feature="$2"; shift 2 ;;
      --local-key) [ "$#" -ge 2 ] || _jm_die_usage "--local-key requer valor"; _jmr_key="$2"; shift 2 ;;
      --jira-key)  [ "$#" -ge 2 ] || _jm_die_usage "--jira-key requer valor"; _jmr_jkey="$2"; shift 2 ;;
      *) _jm_die_usage "argumento desconhecido: $1" ;;
    esac
  done
  [ -n "$_jmr_feature" ] || _jm_die_usage "relink requer --feature F"
  _jm_is_safe_feature "$_jmr_feature" \
    || _jm_die_usage "--feature invalido (charset [A-Za-z0-9_-]): $_jmr_feature"
  _jm_is_safe_field "$_jmr_key" || _jm_die_usage "relink requer --local-key K valido (nao-vazio, sem TAB/newline)"
  _jm_is_safe_field "$_jmr_jkey" || _jm_die_usage "relink requer --jira-key KEY valido (nao-vazio, sem TAB/newline)"

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

  _jmr_tmp="$_jmr_map.tmp.$$"
  awk -F '\t' -v OFS='\t' -v k="$_jmr_key" '
    NR == 1 { print; next }
    { if ($1 == k) $5 = "active"; print }
  ' "$_jmr_map" > "$_jmr_tmp"
  mv -- "$_jmr_tmp" "$_jmr_map"
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
  *)
    _jm_die_usage "subcomando desconhecido: $_jm_sub (validos: get, put, mark-orphans, relink)"
    ;;
esac
