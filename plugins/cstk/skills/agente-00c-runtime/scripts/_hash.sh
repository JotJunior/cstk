#!/bin/sh
# _hash.sh — wrapper sourceable de sha256 cross-platform (FR-CACHE-016A).
#
# Ref: docs/specs/agente-00c-artifact-cache/spec.md FR-CACHE-016A
#      docs/specs/agente-00c-artifact-cache/plan.md §Decisao "cross-platform hash"
#
# NAO eh executavel diretamente. Use:
#   . "$(dirname -- "$0")/_hash.sh"
#   _hash_sha256_file <path>    # imprime 64 chars hex de sha256(<path>)
#   _hash_sha256_stdin          # le stdin, imprime sha256 do conteudo
#
# Plataformas suportadas v1:
#   - Linux (GNU coreutils): usa `sha256sum`
#   - Darwin/macOS (BSD):    usa `shasum -a 256`
#
# Outros SOs (BSD nao-darwin, Alpine sem coreutils): exit 2 com mensagem.
# Algoritmo SHA-256 (FIPS 180-4) garante mesmo output em ambos os binarios.

# _hash_sha256_file PATH
#   PATH: arquivo a hashear.
# stdout: 64 chars hex (sha256 do conteudo do arquivo).
# Exit: 0 sucesso; 1 arquivo ausente/nao-legivel; 2 SO nao suportado.
_hash_sha256_file() {
  _hash_path="${1:-}"
  if [ -z "$_hash_path" ]; then
    printf 'erro: _hash_sha256_file: path nao fornecido\n' >&2
    return 1
  fi
  if [ ! -r "$_hash_path" ]; then
    printf 'erro: _hash_sha256_file: arquivo nao legivel: %s\n' "$_hash_path" >&2
    return 1
  fi
  _hash_os=$(uname -s 2>/dev/null)
  case "$_hash_os" in
    Linux)
      sha256sum -- "$_hash_path" | awk '{print $1}'
      ;;
    Darwin)
      shasum -a 256 -- "$_hash_path" | awk '{print $1}'
      ;;
    *)
      printf 'erro: SO nao suportado para sha256: %s (esperado: Linux|Darwin)\n' "$_hash_os" >&2
      return 2
      ;;
  esac
}

# _hash_sha256_stdin — le stdin, imprime sha256 do conteudo.
# Exit: 0 sucesso; 2 SO nao suportado.
_hash_sha256_stdin() {
  _hash_os=$(uname -s 2>/dev/null)
  case "$_hash_os" in
    Linux)  sha256sum | awk '{print $1}' ;;
    Darwin) shasum -a 256 | awk '{print $1}' ;;
    *)
      printf 'erro: SO nao suportado para sha256: %s\n' "$_hash_os" >&2
      return 2
      ;;
  esac
}
