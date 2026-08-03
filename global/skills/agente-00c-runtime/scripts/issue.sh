#!/bin/sh
# issue.sh — abertura automatica de issue no toolkit GitHub (FR-021).
#
# Ref: docs/specs/agente-00c/spec.md FR-021
#      docs/specs/agente-00c/contracts/issue-template.md
#      docs/specs/agente-00c/threat-model.md T4 (privacidade)
#      docs/specs/agente-00c/tasks.md FASE 8.4
#
# Excecao escopada ao Principio V (blast radius confinado): apenas
# `gh issue create --repo JotJunior/cstk`. Nao sobe relatorio
# nem estado — somente bug report curado.
#
# Subcomandos:
#   issue.sh create --state-dir DIR --suggestion-id SUG
#       --skill SKILL --diagnostico TEXT --proposta TEXT
#       [--por-que-impeditivo TEXT] [--reproducao TEXT]
#       [--env-file FILE] [--dry-run]
#       — Aplica template de issue-template.md, abre issue via gh,
#         atualiza state via suggestions.sh mark-issue.
#       — Defesa em profundidade: secrets-filter aplicado 2x
#         (no build do body + antes do gh create).
#       — Dedup via gh issue list --search com hash 8-chars do diagnostico
#         normalizado (lowercase + colapsa whitespace + sha256 + cut).
#       — Labels obrigatorias: agente-00c, bug, skill-global. Se nao
#         existirem, cria-as antes do issue create.
#       — `--dry-run` imprime body + comando que SERIA executado, NAO
#         abre issue real.
#
#   issue.sh check-duplicate --skill SKILL --diagnostico TEXT
#       — Calcula hash, faz gh issue list --search, retorna URL da issue
#         existente em stdout (e exit 0), OU exit 1 se nao ha duplicata.
#
#   issue.sh hash --diagnostico TEXT
#       — Imprime hash 8-chars do diagnostico normalizado (debug).
#
# Excessao do toolkit-repo hardcoded:
#   _ISH_REPO=JotJunior/cstk
#
# Exit codes:
#   0 sucesso (issue criada OU duplicata encontrada)
#   1 erro generico (gh ausente, sem internet, rate limit)
#   2 uso incorreto
#
# POSIX sh + jq + gh (GitHub CLI).

set -eu

_ISH_NAME="issue"
_ISH_REPO="JotJunior/cstk"

# Leitura via interface canonica (state-db-runtime-parity FR-001, lote 2.4):
# materializa documento legivel por jq nos DOIS backends (json/sqlite).
# issue.sh nao escreve estado diretamente — o registro da issue no state
# delega a `suggestions.sh mark-issue` (ja portado, roteia por state-rw set).
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/_state-read.sh"
trap state_read_cleanup EXIT INT TERM

_ish_die_usage() { printf '%s: %s\n' "$_ISH_NAME" "$1" >&2; exit 2; }
_ish_die()       { printf '%s: %s\n' "$_ISH_NAME" "$1" >&2; exit "${2:-1}"; }

_ish_require_gh() {
  command -v gh >/dev/null 2>&1 \
    || _ish_die "gh CLI nao encontrada. Instale com 'brew install gh' + autentique com 'gh auth login'" 1
}

_ish_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _ish_die "jq nao encontrado no PATH" 1
}

# _ish_normalize TEXT -> texto normalizado (lowercase, whitespace colapsado)
_ish_normalize() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed -e 's/^ *//' -e 's/ *$//'
}

# _ish_hash TEXT -> primeiros 8 chars do SHA-256 do texto normalizado
_ish_hash() {
  _norm=$(_ish_normalize "$1")
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$_norm" | sha256sum | cut -c 1-8
  else
    printf '%s' "$_norm" | shasum -a 256 | cut -c 1-8
  fi
}

# _ish_get_state STATE_DIR -> populates _ISH_EXEC_ID, _ISH_PAP, _ISH_SF etc.
# Falha de materializacao sob sqlite propaga exit+stderr do read (FR-012).
_ish_get_state() {
  _ISH_SF=$(state_read_materialize "$1")
  [ -f "$_ISH_SF" ] || _ish_die "state.json ausente em $1" 1
  _sf=$_ISH_SF
  _ISH_EXEC_ID=$(jq -r '(.execution // .execucao).id' "$_sf")
  _ISH_PAP=$(jq -r '(.execution // .execucao) | (.target_project_path // .projeto_alvo_path)' "$_sf")
  _ISH_PROJ_DESC=$(jq -r '(.execution // .execucao) | (.target_project_description // .projeto_alvo_descricao)' "$_sf")
  _ISH_ETAPA=$(jq -r '(.current_stage // .etapa_corrente)' "$_sf")
  _ISH_ONDA=$(jq -r '((.waves // .ondas) // []) as $w | if ($w | length) > 0 then ($w[-1].id // "init") else "init" end' "$_sf")
}

# _ish_apply_secrets STDIN env_file -> filtra secrets via secrets-filter.sh
# Caller passa --env-file ou string vazia.
_ish_apply_secrets() {
  _env=$1
  _sf_script="$(dirname -- "$0")/secrets-filter.sh"
  if [ ! -x "$_sf_script" ]; then
    cat
    return 0
  fi
  if [ -n "$_env" ] && [ -f "$_env" ]; then
    "$_sf_script" scrub --env-file "$_env"
  else
    "$_sf_script" scrub
  fi
}

# _ish_build_body STATE_DIR SUGID SKILL DIAG PROP IMPED REP ENV
# Imprime corpo da issue em stdout (com filtro de secrets aplicado 1x).
# Caller aplica filtro novamente antes do gh create (defense in depth).
_ish_build_body() {
  _sd=$1; _sug=$2; _skill=$3; _diag=$4; _prop=$5; _imped=$6; _rep=$7; _env=$8
  _ish_get_state "$_sd"
  _now=$(date -u +%FT%TZ)

  # Sumario das decisoes recentes que evidenciam o bug (max 5) — le do
  # documento materializado por _ish_get_state (interface canonica).
  _rel_decs=$(jq -r '
    ((.decisions // .decisoes) // []) | reverse | .[0:5]
    | map("- Decisao `\(.id)`: \((.context // .contexto) | .[0:100])")
    | join("\n")
  ' "$_ISH_SF")
  [ -z "$_rel_decs" ] && _rel_decs="- (nenhuma decisao registrada ainda)"

  # Reproducao default — orquestrador pode passar via --reproducao
  if [ -z "$_rep" ]; then
    _rep="(orquestrador deve enriquecer com observacao especifica passando --reproducao)"
  fi
  if [ -z "$_imped" ]; then
    _imped="(orquestrador deve enriquecer com analise de impeditividade passando --por-que-impeditivo)"
  fi

  cat <<BODY | _ish_apply_secrets "$_env"
> Issue aberta automaticamente pelo agente-00C durante execucao
> \`$_ISH_EXEC_ID\` em \`$_now\`.

## Skill afetada

**Nome**: \`$_skill\`
**Caminho instalado**: \`~/.claude/skills/$_skill/\`
**Versao** (se identificavel via SKILL.md frontmatter): nao informada

## Diagnostico

$_diag

## Reproducao

A execucao do agente-00C que detectou o bug:

- ID: \`$_ISH_EXEC_ID\`
- Projeto-alvo: $_ISH_PROJ_DESC
- Etapa: \`$_ISH_ETAPA\`
- Onda: \`$_ISH_ONDA\`

Decisoes relevantes que evidenciam o bug:

$_rel_decs

$_rep

## Por que e impeditivo

$_imped

## Proposta de correcao

$_prop

## Anexos

- Path do relatorio (no projeto-alvo, NAO anexado a esta issue):
  \`$_ISH_PAP/.claude/agente-00c-report.md\`
- Path da sugestao detalhada:
  \`$_ISH_PAP/.claude/agente-00c-suggestions.md#$_sug\`
- Path do estado no momento da deteccao (backup):
  \`$_ISH_PAP/.claude/agente-00c-state/state-history/$_ISH_ONDA-<timestamp>.json\`

> Estes anexos vivem na maquina do operador. Esta issue NAO uploada o
> relatorio nem o estado — alinhado com Principio IV do toolkit (zero
> coleta remota).

---

🤖 Aberta automaticamente pelo agente-00C
BODY
}

# _ish_ensure_labels — cria labels (idempotente; falhas silenciosas)
_ish_ensure_labels() {
  for _lbl in agente-00c bug skill-global; do
    gh label create "$_lbl" --repo "$_ISH_REPO" --color CCCCCC --force >/dev/null 2>&1 || :
  done
}

# _ish_check_duplicate SKILL DIAG -> stdout: URL da existente; exit 0 se duplicata
_ish_check_duplicate() {
  _ish_require_gh
  _hash=$(_ish_hash "$2")
  # Search por skill + hash. gh imprime list em formato tabular; jq parseia
  _existing=$(gh issue list --repo "$_ISH_REPO" --state open \
    --search "agente-00C $1 $_hash" \
    --json number,url,title 2>/dev/null \
    | jq -r --arg s "$1" --arg h "$_hash" '
      .[] | select(.title | (contains($s) and contains($h)))
      | .url
    ' 2>/dev/null | head -1) || _existing=""
  if [ -n "$_existing" ]; then
    printf '%s\n' "$_existing"
    return 0
  fi
  return 1
}

_ish_cmd_create() {
  _sd=""
  _sug=""
  _skill=""
  _diag=""
  _prop=""
  _imped=""
  _rep=""
  _env=""
  _dry=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)            _sd=$2;    shift 2 ;;
      --suggestion-id)        _sug=$2;   shift 2 ;;
      --skill)                _skill=$2; shift 2 ;;
      --diagnostico)          _diag=$2;  shift 2 ;;
      --proposta)             _prop=$2;  shift 2 ;;
      --por-que-impeditivo)   _imped=$2; shift 2 ;;
      --reproducao)           _rep=$2;   shift 2 ;;
      --env-file)             _env=$2;   shift 2 ;;
      --dry-run)              _dry=1;    shift ;;
      *) _ish_die_usage "create: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sd" ]    || _ish_die_usage "create: --state-dir obrigatorio"
  [ -n "$_sug" ]   || _ish_die_usage "create: --suggestion-id obrigatorio"
  [ -n "$_skill" ] || _ish_die_usage "create: --skill obrigatorio"
  [ -n "$_diag" ]  || _ish_die_usage "create: --diagnostico obrigatorio"
  [ -n "$_prop" ]  || _ish_die_usage "create: --proposta obrigatorio"
  _ish_require_jq

  # Dedup check
  if _existing=$(_ish_check_duplicate "$_skill" "$_diag"); then
    printf '%s: duplicata encontrada — %s\n' "$_ISH_NAME" "$_existing" >&2
    printf '%s\n' "$_existing"
    return 0
  fi

  # Build title (skill + hash + resumo curto da diag — primeiras palavras)
  _hash=$(_ish_hash "$_diag")
  _resumo=$(printf '%s' "$_diag" | tr '\n' ' ' | cut -c 1-60)
  _title="[agente-00C] Bug em $_skill ($_hash): $_resumo"

  # Build body (com filtro de secrets aplicado 1x via _ish_apply_secrets)
  _body=$(_ish_build_body "$_sd" "$_sug" "$_skill" "$_diag" "$_prop" "$_imped" "$_rep" "$_env")
  # Trunca body se ultrapassar limite (~4000 chars)
  _bsize=$(printf '%s' "$_body" | wc -c | tr -d ' ')
  if [ "$_bsize" -gt 4000 ]; then
    _body=$(printf '%s' "$_body" | cut -c 1-3900)
    _body="$_body

[CORTADO em 4000 chars — ver relatorio local em <PAP>/.claude/agente-00c-report.md]"
  fi

  # Defense in depth: aplica secrets-filter NOVAMENTE antes do gh create
  _body_safe=$(printf '%s' "$_body" | _ish_apply_secrets "$_env")

  if [ "$_dry" = 1 ]; then
    printf '=== DRY-RUN ===\n'
    printf 'Title: %s\n' "$_title"
    printf 'Repo: %s\n' "$_ISH_REPO"
    printf 'Labels: agente-00c,bug,skill-global\n'
    printf '\n=== BODY ===\n%s\n' "$_body_safe"
    return 0
  fi

  _ish_require_gh
  _ish_ensure_labels

  # gh issue create. Captura URL retornado.
  _url=$(printf '%s' "$_body_safe" \
    | gh issue create --repo "$_ISH_REPO" \
        --title "$_title" \
        --label "agente-00c,bug,skill-global" \
        --body-file - 2>&1) || {
    printf '%s: gh issue create falhou:\n%s\n' "$_ISH_NAME" "$_url" >&2
    _ish_die "issue creation falhou — registre no suggestions.md como ERRO" 1
  }

  # Atualiza state via suggestions.sh mark-issue
  _sg_script="$(dirname -- "$0")/suggestions.sh"
  if [ -x "$_sg_script" ]; then
    "$_sg_script" mark-issue --state-dir "$_sd" --suggestion-id "$_sug" \
      --issue "$_url" >/dev/null 2>&1 || :
  fi

  printf '%s\n' "$_url"
}

_ish_cmd_check_duplicate() {
  _skill=""
  _diag=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skill)       _skill=$2; shift 2 ;;
      --diagnostico) _diag=$2;  shift 2 ;;
      *) _ish_die_usage "check-duplicate: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_skill" ] || _ish_die_usage "check-duplicate: --skill obrigatorio"
  [ -n "$_diag" ]  || _ish_die_usage "check-duplicate: --diagnostico obrigatorio"
  if _existing=$(_ish_check_duplicate "$_skill" "$_diag"); then
    printf '%s\n' "$_existing"
    exit 0
  fi
  exit 1
}

_ish_cmd_hash() {
  _diag=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --diagnostico) _diag=$2; shift 2 ;;
      *) _ish_die_usage "hash: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_diag" ] || _ish_die_usage "hash: --diagnostico obrigatorio"
  _ish_hash "$_diag"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
issue.sh — abertura automatica de issue no toolkit GitHub (FR-021).

USO:
  issue.sh create --state-dir DIR --suggestion-id SUG --skill SKILL \
    --diagnostico TEXT --proposta TEXT \
    [--por-que-impeditivo TEXT] [--reproducao TEXT] \
    [--env-file FILE] [--dry-run]
  issue.sh check-duplicate --skill SKILL --diagnostico TEXT
  issue.sh hash --diagnostico TEXT

Toolkit-repo hardcoded: JotJunior/cstk (excecao escopada ao
Principio V — bug report curado, sem upload de relatorio/estado).

EXIT:
  0 sucesso (issue criada OU duplicata encontrada)
  1 erro generico (gh ausente, sem internet, rate limit)
  2 uso incorreto
HELP
  exit 2
fi

_ISH_SUBCMD=$1
shift

case "$_ISH_SUBCMD" in
  create)            _ish_cmd_create "$@" ;;
  check-duplicate)   _ish_cmd_check_duplicate "$@" ;;
  hash)              _ish_cmd_hash "$@" ;;
  -h|--help|help)    exit 0 ;;
  *) _ish_die_usage "subcomando desconhecido: $_ISH_SUBCMD" ;;
esac
