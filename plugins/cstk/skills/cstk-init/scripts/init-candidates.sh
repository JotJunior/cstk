#!/bin/sh
# init-candidates.sh — sinais de evidencia para features candidatas e validacao de nome
# (feature cstk-init, tarefa 4.6).
#
# Contrato: SKILL.md §8 e references/feature-recognition.md.
#
#   init-candidates.sh evidence --root <dir>
#   init-candidates.sh name     --root <dir> --name <short>
#
# evidence — stdout `<signal><TAB><key><TAB><path>` (ordenado, sem duplicatas), exit 0 (1 raiz
#   inexistente). Os sinais sao DERIVADOS do inventario deterministico (init-inventory.sh), so
#   por caminho — o script nunca le conteudo de arquivo do projeto. A definicao de "feature"
#   e semantica e pertence ao modelo/operador (dec-008): o script so fornece evidencia.
#     source-module  diretorio de codigo de 1o e 2o nivel (`src`, `src/billing`);
#                    key = ultimo segmento; tests/docs nao contam
#     test-group     agrupamento de testes: `tests/<X>` (arquivos sob tests|test|__tests__),
#                    ou o diretorio do arquivo para testes ao lado do codigo
#     doc-page       pagina de documentacao sob docs/ (exceto briefing, constitution, legado e
#                    docs/specs/); key = nome sem extensao
#     workspace      pacote com manifesto proprio abaixo da raiz (package.json, go.mod, ...);
#                    key = ultimo segmento do diretorio, path = o manifesto (SEM parsear o
#                    conteudo do manifesto raiz: texto do projeto e dado hostil)
#   Linha final `TRUNCATED<TAB><n>` repassada quando o inventario atingiu o teto: o resultado
#   e PARCIAL (FR-030a).
#
# name — kebab-case `^[a-z0-9]+(-[a-z0-9]+)*$` (senao exit 5, sem consultar o disco);
#   stdout `NAME<TAB><short><TAB><free|exists-active|exists-archived>`; exit 0 free,
#   3 colisao com `docs/specs/<short>` (ativa) ou `docs/specs/_archived/<short>` /
#   `docs/specs/_archived/AAAA-MM-DD-<short>` (arquivada), 1 raiz inexistente, 2 uso.
#
# Seam de teste: INIT_CANDIDATES_INVENTORY_BIN substitui o init-inventory.sh irmao.

set -eu
LC_ALL=C
export LC_ALL

TAB=$(printf '\t')
INVENTORY_MAX=100000

_usage() {
  cat >&2 <<'EOF'
uso:
  init-candidates.sh evidence --root <dir>
  init-candidates.sh name     --root <dir> --name <short>
EOF
}

_die_usage() {
  printf 'init-candidates: %s\n' "$1" >&2
  _usage
  exit 2
}

_printable() {
  printf '%s' "$1" | tr '\001-\037\177' '?'
}

# ---------------------------------------------------------------- evidence

# _is_test_dir_name <seg> — tests | test | __tests__
_is_test_dir_name() {
  case "$1" in tests|test|__tests__) return 0 ;; esac
  return 1
}

# _emit_signals — le linhas `<kind><TAB><path>` do inventario (stdin) e emite os sinais
# (nao ordenados, com duplicatas) em stdout.
_emit_signals() {
  while IFS="$TAB" read -r _kind _path || [ -n "$_kind" ]; do
    [ -n "$_path" ] || continue
    case "$_kind" in
      source-dir)
        [ "$_path" != . ] || continue
        _first=${_path%%/*}
        _is_test_dir_name "$_first" && continue
        case "$_first" in docs) continue ;; esac
        printf 'source-module\t%s\t%s\n' "$_first" "$_first"
        _rest=${_path#*/}
        if [ "$_rest" != "$_path" ]; then
          _second=${_rest%%/*}
          printf 'source-module\t%s\t%s\n' "$_second" "$_first/$_second"
        fi ;;
      test)
        _group=
        _acc=
        _oldifs=$IFS
        IFS=/
        set -f
        # shellcheck disable=SC2086
        set -- $_path
        set +f
        IFS=$_oldifs
        # percorre os segmentos de diretorio (todos menos o ultimo = o arquivo)
        _n=$#
        _i=0
        _found=0
        for _seg in "$@"; do
          _i=$((_i + 1))
          [ "$_i" -lt "$_n" ] || break
          if [ -z "$_acc" ]; then _acc=$_seg; else _acc="$_acc/$_seg"; fi
          if [ "$_found" -eq 0 ] && _is_test_dir_name "$_seg"; then
            _found=1
            _group=$_acc
            # proximo segmento so conta se for diretorio (nao e o arquivo)
            if [ "$((_i + 1))" -lt "$_n" ]; then
              shift "$_i"
              _group="$_acc/$1"
              break
            fi
          fi
        done
        if [ "$_found" -eq 0 ]; then
          # teste ao lado do codigo: agrupa pelo diretorio do arquivo
          _group=${_path%/*}
          [ "$_group" != "$_path" ] || continue
        fi
        printf 'test-group\t%s\t%s\n' "${_group##*/}" "$_group" ;;
      doc)
        case "$_path" in
          docs/briefing.md|docs/constitution.md|docs/01-briefing-discovery/*|docs/specs/*) continue ;;
          docs/*) ;;
          *) continue ;;
        esac
        _b=${_path##*/}
        _b=${_b%.*}
        [ -n "$_b" ] || continue
        printf 'doc-page\t%s\t%s\n' "$_b" "$_path" ;;
      manifest)
        _dir=${_path%/*}
        [ "$_dir" != "$_path" ] || continue
        printf 'workspace\t%s\t%s\n' "${_dir##*/}" "$_path" ;;
      TRUNCATED)
        printf 'TRUNCATED\t%s\t\n' "$_path" ;;
    esac
  done
}

cmd_evidence() {
  _root=$1
  [ -n "$_root" ] || _die_usage "evidence exige --root"
  [ -d "$_root" ] || { printf 'init-candidates: raiz inexistente: %s\n' "$_root" >&2; exit 1; }
  _inv=${INIT_CANDIDATES_INVENTORY_BIN:-}
  if [ -z "$_inv" ]; then
    _inv=$(cd -P -- "$(dirname -- "$0")" && pwd -P)/init-inventory.sh
  fi
  [ -f "$_inv" ] || { printf 'init-candidates: inventario ausente: %s\n' "$(_printable "$_inv")" >&2; exit 1; }

  _out=$(sh "$_inv" inventory --root "$_root" --max-items "$INVENTORY_MAX") || {
    printf 'init-candidates: falha ao montar o inventario\n' >&2; exit 1; }
  _sig=$(printf '%s\n' "$_out" | _emit_signals | LC_ALL=C sort -u)
  # sinais sem a linha TRUNCATED; caracteres de controle (exceto TAB) viram `?`
  printf '%s\n' "$_sig" | while IFS= read -r _l; do
    case "$_l" in
      ''|TRUNCATED"$TAB"*) ;;
      *) printf '%s' "$_l" | tr '\001-\010\012-\037\177' '?'; printf '\n' ;;
    esac
  done
  # TRUNCATED (se houver) vai por ultimo: o resultado e PARCIAL
  printf '%s\n' "$_sig" | while IFS="$TAB" read -r _k _v _rest; do
    if [ "$_k" = TRUNCATED ]; then printf 'TRUNCATED\t%s\n' "$_v"; fi
  done
  exit 0
}

# ---------------------------------------------------------------- name

_valid_kebab() {
  case "$1" in
    ''|-*|*-|*--*|*[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

cmd_name() {
  _root=$1
  _name=$2
  [ -n "$_root" ] || _die_usage "name exige --root"
  [ -n "$_name" ] || _die_usage "name exige --name"
  if ! _valid_kebab "$_name"; then
    printf 'init-candidates: nome invalido (esperado kebab-case ^[a-z0-9]+(-[a-z0-9]+)*$): %s\n' \
      "$(_printable "$_name")" >&2
    exit 5
  fi
  [ -d "$_root" ] || { printf 'init-candidates: raiz inexistente: %s\n' "$_root" >&2; exit 1; }
  _abs=$(cd -P -- "$_root" 2>/dev/null && pwd -P) || {
    printf 'init-candidates: nao foi possivel resolver a raiz: %s\n' "$_root" >&2; exit 1; }

  if [ -e "$_abs/docs/specs/$_name" ] || [ -L "$_abs/docs/specs/$_name" ]; then
    printf 'NAME\t%s\texists-active\n' "$_name"
    exit 3
  fi
  _arch="$_abs/docs/specs/_archived"
  if [ -e "$_arch/$_name" ] || [ -L "$_arch/$_name" ]; then
    printf 'NAME\t%s\texists-archived\n' "$_name"
    exit 3
  fi
  for _e in "$_arch"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"$_name"; do
    if [ -e "$_e" ] || [ -L "$_e" ]; then
      printf 'NAME\t%s\texists-archived\n' "$_name"
      exit 3
    fi
  done
  printf 'NAME\t%s\tfree\n' "$_name"
  exit 0
}

# ---------------------------------------------------------------- main

[ $# -ge 1 ] || _die_usage "subcomando obrigatorio"
SUB=$1
shift

case "$SUB" in
  evidence|name)
    ROOT=
    NAME=
    while [ $# -gt 0 ]; do
      case "$1" in
        --root) [ $# -ge 2 ] || _die_usage "--root exige valor"; ROOT=$2; shift 2 ;;
        --name)
          [ "$SUB" = name ] || _die_usage "--name so vale para o subcomando name"
          [ $# -ge 2 ] || _die_usage "--name exige valor"; NAME=$2; shift 2 ;;
        *) _die_usage "argumento desconhecido: $1" ;;
      esac
    done
    if [ "$SUB" = evidence ]; then cmd_evidence "$ROOT"; else cmd_name "$ROOT" "$NAME"; fi
    ;;
  -h|--help) _usage; exit 0 ;;
  *) _die_usage "subcomando desconhecido: $SUB" ;;
esac
