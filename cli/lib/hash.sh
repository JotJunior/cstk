# hash.sh — hash determinista de diretorio via manifest canonico ordenado.
#
# Funcoes exportadas:
#   hash_dir  <dir>   — imprime SHA-256 de um manifest ordenado do conteudo
#   hash_file <file>  — imprime SHA-256 do arquivo (wrapper sobre sha256_file)
#
# Estrategia (portavel mac + linux):
#   1. Lista TODOS os arquivos regulares sob <dir> via find -type f
#   2. Ordena os paths relativos via sort -- garante ordem deterministica
#   3. Para cada arquivo, imprime linha "<sha256>  <relpath>"
#   4. Hash SHA-256 dessa saida textual
#
# Rejeicao de alternativas:
#   - `tar --sort=name --owner=0 ...` e GNU-only; BSD tar do macOS nao suporta.
#     Esta abordagem manifest-canonico e equivalente semanticamente e funciona
#     em qualquer sistema com find + sort + sha256*.
#   - `mtime`/`inode` nao fazem parte do hash — mudanca de permissoes ou
#     timestamps nao afeta; so conteudo + path relativo importam. E o desejado
#     para detectar edicoes de CONTEUDO.
#
# Deps: find, sort, printf; compat.sh (sha256_file, sha256_stdin).
#
# POSIX sh puro.

if [ -n "${_CSTK_HASH_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_HASH_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/compat.sh"

hash_file() {
  if [ "$#" -ne 1 ]; then
    printf 'hash: hash_file espera 1 argumento (arquivo)\n' >&2
    return 2
  fi
  if [ ! -f "$1" ]; then
    printf 'hash: arquivo nao existe: %s\n' "$1" >&2
    return 1
  fi
  sha256_file "$1"
}

# hash_dir_catalog DIR -> hash de conteudo COMPARAVEL entre os dois
# caminhos de distribuicao (catalogo classico x catalogo do plugin).
#
# Por que nao dava para usar `hash_dir` aqui: os dois caminhos carregam
# conjuntos de arquivos DIFERENTES por construcao, entao o hash cru nunca
# empata e o `cstk doctor` reportava `diverged` para sempre — falso
# positivo que gateava o exit e nao tinha acao possivel.
#
#   - `evals/`        fixtures dev-only, REMOVIDAS do tarball por
#                     scripts/build-release.sh ("Remover fixtures dev-only
#                     (evals/) do catalogo distribuido"). O plugin vem do
#                     repo git e as carrega; o classico, nunca.
#   - `.cstk-manifest` bookkeeping do proprio cstk, so no classico.
#   - `.DS_Store`     lixo do Finder (macOS), some quando some.
#
# Excluir isso preserva o sinal REAL: se SKILL.md/scripts divergirem
# (plugin stale, classico stale), o hash continua diferente.
#
# `hash_dir` fica INTOCADO de proposito — ele alimenta `source_sha256` no
# manifest, e mudar sua saida marcaria todas as skills instaladas como
# EDITED de uma vez.
# Nomes das skills a comparar chegam por STDIN (um por linha) — so elas
# entram no hash. `~/.claude/skills/` e espaco COMPARTILHADO: hashear o
# diretorio inteiro faz qualquer skill de terceiro (plugin da Anthropic,
# skill local do operador) divergir dois catalogos que estao identicos no
# que o cstk possui.
#
# Um nome ausente no diretorio simplesmente nao contribui — se ele existe
# de um lado e falta do outro, os hashes divergem, que e o sinal REAL
# (skill removida/adicionada entre as duas distribuicoes).
hash_dir_catalog() {
  if [ "$#" -ne 1 ]; then
    printf 'hash: hash_dir_catalog espera 1 argumento (diretorio)\n' >&2
    return 2
  fi
  if [ ! -d "$1" ]; then
    printf 'hash: diretorio nao existe: %s\n' "$1" >&2
    return 1
  fi
  _hash_cat_target=$1
  _hash_cat_names=$(cat)
  (
    cd -- "$_hash_cat_target" || return 1
    printf '%s\n' "$_hash_cat_names" | sort | while IFS= read -r _n; do
      [ -n "$_n" ] || continue
      [ -d "./$_n" ] || continue
      find "./$_n" -type f -print | sort | while IFS= read -r _f; do
        case "$_f" in
          */evals/*) continue ;;
          */.DS_Store) continue ;;
        esac
        _h=$(sha256_file "$_f") || exit 1
        printf '%s  %s\n' "$_h" "$_f"
      done
    done
  ) | sha256_stdin
}

hash_dir() {
  # POSIX sh NAO tem local vars — prefixo _hash_ para evitar colisao.
  if [ "$#" -ne 1 ]; then
    printf 'hash: hash_dir espera 1 argumento (diretorio)\n' >&2
    return 2
  fi
  if [ ! -d "$1" ]; then
    printf 'hash: diretorio nao existe: %s\n' "$1" >&2
    return 1
  fi
  _hash_target=$1
  # Gera manifest canonico e hasheia. Variaveis dentro do subshell (cd + find)
  # sao isoladas — nao precisam de prefixo.
  (
    cd -- "$_hash_target" || return 1
    find . -type f -print | sort | while IFS= read -r _f; do
      _h=$(sha256_file "$_f") || exit 1
      printf '%s  %s\n' "$_h" "$_f"
    done
  ) | sha256_stdin
}
