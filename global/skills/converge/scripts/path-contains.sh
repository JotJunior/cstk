#!/bin/sh
# path-contains.sh — contencao de blast radius para a skill `converge`
# (FR-018).
#
# Ref: docs/specs/skill-converge/contracts/converge-interfaces.md §6
#      docs/specs/skill-converge/tasks.md tarefa 1.2 (resolucao automatica
#      de --root em modo standalone) + tarefa 2.1
#      docs/specs/skill-converge/research.md Decision 6 (helper proprio e
#      minimo, sem acoplar a agente-00c-runtime/path-guard.sh)
#
# Resolve --path (via realpath, fallback POSIX readlink -f / cd+pwd -P —
# Constitution II) e verifica se esta CONTIDO em --root. Canonicaliza
# symlinks ANTES de checar o prefixo (ordem critica — SEC-2): um symlink
# dentro do root que aponta para fora MUST ser detectado, mesmo quando o
# alvo final do path declarado ainda nao existe no disco (ex.:
# root/escape/novo-arquivo.sh, onde "escape" e symlink existente e
# "novo-arquivo.sh" nao existe).
#
# USO:
#   path-contains.sh --path <path> [--root <dir>]
#
# Se --root nao for fornecido (modo standalone, tarefa 1.2.1), resolve
# automaticamente nesta ordem:
#   1. flag --root explicita (vence sempre — coberto acima, aqui e o caso
#      omitido)
#   2. busca ascendente a partir do CWD por `.git` (arquivo ou diretorio —
#      worktrees usam .git como arquivo apontando para o gitdir real)
#   3. fallback: busca ascendente por `docs/constitution.md`
#   4. teto de 20 niveis
#   5. nenhum marcador encontrado ⇒ aborta (fail-closed, nunca assume CWD
#      cego)
#
# EXIT:
#   0  contido (seguro ler) — imprime o path resolvido (absoluto) em stdout
#   1  fora do root, OU path irresolvivel (fail-closed — arquivo NAO deve
#      ser lido; achado missing/inconclusivo)
#   2  erro de uso (flag invalida/ausente, ou --root nao resolvivel/nao
#      existe — familia distinta de exit 1: aqui o root em si nao foi
#      determinado, nao que o path avaliado esta fora dele)
#
# POSIX sh puro. Zero eval sobre conteudo lido (SEC-1). Todas as variaveis
# quotadas. Sem Bash-isms (sem array, sem [[ ]], sem local — usa prefixo
# _pc_ e subshells para isolar escopo).

set -eu

_PC_NAME="path-contains"
_PC_MAX_LEVELS=20

_pc_usage() {
  cat <<'USAGE' >&2
Uso: path-contains.sh --path <path> [--root <dir-projeto-alvo>]

  --path <p>   path declarado a validar (obrigatorio)
  --root <dir> raiz do projeto-alvo; se omitido, resolvido automaticamente
               (.git/ ascendente -> docs/constitution.md ascendente -> abort)

Exit: 0 contido | 1 fora do root / irresolvivel | 2 erro de uso
USAGE
}

_pc_die_usage() {
  printf '%s: %s\n' "$_PC_NAME" "$1" >&2
  exit 2
}

# ---------- Normalizacao lexical (sem tocar o filesystem) ----------

# _pc_lexical_normalize ABS_PATH -> imprime ABS_PATH com componentes "." e
# ".." colapsados, puramente textual. Usado apenas sobre a "cauda" (tail)
# de um path que nao existe no disco — impede que ".." literal sobreviva
# na string final e escape do prefixo do root (fail-closed contra escape
# via cauda irresolvivel). `set -f` isola pathname expansion: um path
# adversarial contendo "*"/"?"/"[" nunca deve ser glob-expandido (SEC-1).
_pc_lexical_normalize() {
  _in=$1
  case "$_in" in
    /*) ;;
    *) return 1 ;;
  esac
  (
    IFS='/'
    set -f
    # Word-splitting em "/" e INTENCIONAL (e como fatiamos os componentes
    # do path); "set -f" acima ja neutraliza pathname expansion (globbing)
    # para este "set --", entao um path adversarial com "*"/"?"/"[" nunca
    # e glob-expandido (SEC-1).
    # shellcheck disable=SC2086
    set -- $_in
    _out=""
    for _seg in "$@"; do
      case "$_seg" in
        '' | '.') continue ;;
        '..') _out=${_out%/*} ;;
        *) _out="$_out/$_seg" ;;
      esac
    done
    [ -n "$_out" ] || _out="/"
    printf '%s\n' "$_out"
  )
}

# ---------- Resolucao de path (realpath com fallback POSIX) ----------

# _pc_resolve_existing ABS_PATH -> imprime o path resolvido (symlinks
# canonicalizados) via realpath -> readlink -f -> cd+pwd -P, nesta ordem.
# So chamada quando ABS_PATH existe no disco. Vazio + exit 1 se nenhuma
# estrategia funcionar (raro).
_pc_resolve_existing() {
  _e=$1
  if command -v realpath >/dev/null 2>&1; then
    _r=$(realpath -- "$_e" 2>/dev/null) && [ -n "$_r" ] && { printf '%s\n' "$_r"; return 0; }
  fi
  if command -v readlink >/dev/null 2>&1; then
    _r=$(readlink -f -- "$_e" 2>/dev/null) && [ -n "$_r" ] && { printf '%s\n' "$_r"; return 0; }
  fi
  if [ -d "$_e" ]; then
    _r=$(cd "$_e" 2>/dev/null && pwd -P) && [ -n "$_r" ] && { printf '%s\n' "$_r"; return 0; }
  fi
  return 1
}

# _pc_resolve PATH -> imprime o path absoluto resolvido em stdout, exit 0.
# Exit 1 se irresolvivel (nenhum ancestral existente dentro do teto de
# niveis — fail-closed, nunca fail-open).
#
# Estrategia:
#   1. torna PATH absoluto textualmente (prefixa CWD se relativo);
#   2. se o path INTEIRO existe, resolve tudo de uma vez (cobre o caso
#      comum e o Scenario 16 quando o symlink e o componente final);
#   3. senao, caminha pelos ancestrais (dirname sucessivo) ate achar um
#      diretorio existente, preservando a cauda inexistente; resolve
#      (canonicaliza symlinks reais de) o ancestral encontrado — cobre
#      Scenario 16 quando o symlink e um componente INTERMEDIARIO e a
#      cauda final ainda nao existe;
#   4. recompoe ancestral-resolvido + cauda e aplica normalizacao lexical
#      na cauda (colapsa "." / ".." — nunca deixa ".." sobreviver).
_pc_resolve() {
  _p=$1
  [ -n "$_p" ] || return 1

  case "$_p" in
    /*) _abs=$_p ;;
    *) _abs="$(pwd -P)/$_p" ;;
  esac

  if [ -e "$_abs" ]; then
    _pc_resolve_existing "$_abs"
    return $?
  fi

  # Caminha ancestrais ate achar um existente, preservando a cauda.
  _walk=$_abs
  _tail=""
  _level=0
  while [ "$_level" -lt "$_PC_MAX_LEVELS" ] && [ ! -e "$_walk" ]; do
    _base=$(basename -- "$_walk")
    if [ -z "$_tail" ]; then
      _tail=$_base
    else
      _tail="$_base/$_tail"
    fi
    _parent=$(dirname -- "$_walk")
    [ "$_parent" = "$_walk" ] && break
    _walk=$_parent
    _level=$((_level + 1))
  done

  [ -e "$_walk" ] || return 1

  _anchor=$(_pc_resolve_existing "$_walk") || return 1
  [ -n "$_anchor" ] || return 1

  if [ -n "$_tail" ]; then
    _pc_lexical_normalize "$_anchor/$_tail"
  else
    printf '%s\n' "$_anchor"
  fi
}

# ---------- Busca ascendente por marcador (resolucao automatica de --root) ----------

# _pc_ascend_find START MARKER -> imprime o dir ancestral (a partir de
# START, incluso) que contem MARKER (arquivo ou diretorio), teto de
# _PC_MAX_LEVELS niveis. Exit 1 se nao encontrado dentro do teto.
_pc_ascend_find() {
  _dir=$1
  _marker=$2
  _level=0
  while [ "$_level" -lt "$_PC_MAX_LEVELS" ]; do
    if [ -e "$_dir/$_marker" ]; then
      printf '%s\n' "$_dir"
      return 0
    fi
    [ "$_dir" = "/" ] && break
    _parent=$(dirname -- "$_dir")
    [ "$_parent" = "$_dir" ] && break
    _dir=$_parent
    _level=$((_level + 1))
  done
  return 1
}

# _pc_auto_root -> resolve --root automaticamente quando a flag nao foi
# passada (tarefa 1.2.1 + contracts §6): .git/ ascendente -> fallback
# docs/constitution.md ascendente -> falha (caller aborta, fail-closed).
_pc_auto_root() {
  _start=$(pwd -P)
  if _found=$(_pc_ascend_find "$_start" ".git"); then
    printf '%s\n' "$_found"
    return 0
  fi
  if _found=$(_pc_ascend_find "$_start" "docs/constitution.md"); then
    printf '%s\n' "$_found"
    return 0
  fi
  return 1
}

# ---------- Parse de flags ----------

_ROOT=""
_PATH_ARG=""

if [ "$#" -eq 0 ]; then
  _pc_usage
  exit 2
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || _pc_die_usage "--root requer valor"
      _ROOT=$2
      shift 2
      ;;
    --path)
      [ "$#" -ge 2 ] || _pc_die_usage "--path requer valor"
      _PATH_ARG=$2
      shift 2
      ;;
    -h | --help)
      _pc_usage
      exit 0
      ;;
    *)
      _pc_die_usage "flag desconhecida: $1"
      ;;
  esac
done

[ -n "$_PATH_ARG" ] || _pc_die_usage "--path e obrigatorio"

# ---------- Resolucao de --root ----------

if [ -z "$_ROOT" ]; then
  _ROOT=$(_pc_auto_root) || _pc_die_usage \
    "--root nao fornecido e nao foi possivel resolver automaticamente (.git ou docs/constitution.md nao encontrados a partir do diretorio atual em ate $_PC_MAX_LEVELS niveis) — passe --root explicitamente"
fi

_root_resolved=$(_pc_resolve "$_ROOT") || _root_resolved=""
[ -n "$_root_resolved" ] || _pc_die_usage "nao foi possivel resolver --root: $_ROOT"
[ -d "$_root_resolved" ] || _pc_die_usage "--root nao existe ou nao e diretorio: $_ROOT (resolvido: $_root_resolved)"

# ---------- Resolucao de --path + checagem de contencao ----------

_path_resolved=$(_pc_resolve "$_PATH_ARG") || _path_resolved=""
if [ -z "$_path_resolved" ]; then
  printf '%s: path irresolvivel (fail-closed, nunca fail-open): %s\n' "$_PC_NAME" "$_PATH_ARG" >&2
  exit 1
fi

if [ "$_path_resolved" = "$_root_resolved" ]; then
  printf '%s\n' "$_path_resolved"
  exit 0
fi
case "$_path_resolved" in
  "$_root_resolved"/*)
    printf '%s\n' "$_path_resolved"
    exit 0
    ;;
esac

printf '%s: path fora do projeto-alvo (blast radius, FR-018) — arquivo NAO sera lido\n' "$_PC_NAME" >&2
printf '  --path: %s\n' "$_PATH_ARG" >&2
printf '  resolvido: %s\n' "$_path_resolved" >&2
printf '  --root resolvido: %s\n' "$_root_resolved" >&2
exit 1
