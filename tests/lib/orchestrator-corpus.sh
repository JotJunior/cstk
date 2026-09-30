#!/bin/sh
# orchestrator-corpus.sh — helper sourceable (POSIX sh) para testes que
# leem os prompts dos orquestradores (agente-00c-orchestrator e
# agente-00c-feature-orchestrator) e as referencias de fase movidas.
#
# Ref: docs/specs/orchestrator-slim/research.md Decision 8/9;
#      docs/specs/orchestrator-slim/data-model.md (ContractInventory)
#
# O "corpus" de um orquestrador = prompt-base + todas as referencias de fase
# existentes do MESMO orquestrador, em ordem estavel (prompt-base primeiro,
# depois as referencias por nome, LC_ALL=C). Testes de literais contratuais
# passam a greppar o corpus; assertos posicionais migram para o arquivo onde o
# trecho passou a viver (orch_ref).
#
# Orquestradores: `root` (agente-00c-orchestrator.md) e `feature`
# (agente-00c-feature-orchestrator.md).
#
# Variaveis (todas com default; sobrescreviveis para mutantes em tmpdir):
#   REPO_ROOT          raiz do repositorio (obrigatoria, ou derivada de $0)
#   ORCH_AGENTS_DIR    dir dos prompts-base (default plugins/cstk/agents)
#   ORCH_REFS_DIR      dir das referencias (default
#                      plugins/cstk/skills/agente-00c-runtime/references/orchestrators)
#   ORCH_BASELINE_REF  commit do baseline de paridade (default 9f97e99...)
#   ORCH_FIXTURES_DIR  dir dos inventarios (default tests/fixtures/orchestrator-slim)

: "${ORCH_BASELINE_REF:=9f97e994d5cde46d1447744c68c9def8da14e6e3}"

_orch_repo_root() {
  printf '%s' "${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
}

_orch_agents_dir() {
  printf '%s' "${ORCH_AGENTS_DIR:-$(_orch_repo_root)/plugins/cstk/agents}"
}

_orch_refs_root() {
  printf '%s' "${ORCH_REFS_DIR:-$(_orch_repo_root)/plugins/cstk/skills/agente-00c-runtime/references/orchestrators}"
}

_orch_fixtures_dir() {
  printf '%s' "${ORCH_FIXTURES_DIR:-$(_orch_repo_root)/tests/fixtures/orchestrator-slim}"
}

# orch_base_name <root|feature> -> nome do arquivo do prompt-base
orch_base_name() {
  case "$1" in
    root) printf '%s' 'agente-00c-orchestrator.md' ;;
    feature) printf '%s' 'agente-00c-feature-orchestrator.md' ;;
    *) return 2 ;;
  esac
}

# orch_base_path <root|feature> -> caminho do prompt-base
orch_base_path() {
  _obp_name=$(orch_base_name "$1") || return 2
  printf '%s/%s' "$(_orch_agents_dir)" "$_obp_name"
}

# orch_refs_dir <root|feature> -> diretorio das referencias do orquestrador
orch_refs_dir() {
  case "$1" in root|feature) ;; *) return 2 ;; esac
  printf '%s/%s' "$(_orch_refs_root)" "$1"
}

# orch_ref_files <root|feature> -> caminhos das referencias existentes (ordem estavel)
orch_ref_files() {
  _orf_dir=$(orch_refs_dir "$1") || return 2
  [ -d "$_orf_dir" ] || return 0
  find "$_orf_dir" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort
}

# orch_ref <root|feature> <phase> -> conteudo da referencia da fase (exit 1 se ausente)
orch_ref() {
  _or_dir=$(orch_refs_dir "$1") || return 2
  [ -f "$_or_dir/$2.md" ] || return 1
  cat "$_or_dir/$2.md"
}

# orch_corpus <root|feature> -> prompt-base + referencias, em ordem estavel
orch_corpus() {
  _oc_base=$(orch_base_path "$1") || return 2
  cat "$_oc_base" || return 1
  orch_ref_files "$1" | while IFS= read -r _oc_f; do
    [ -n "$_oc_f" ] && cat "$_oc_f"
  done
  return 0
}

# orch_baseline <root|feature> -> prompt-base no commit do baseline
orch_baseline() {
  _ob_name=$(orch_base_name "$1") || return 2
  git -C "$(_orch_repo_root)" show "$ORCH_BASELINE_REF:plugins/cstk/agents/$_ob_name"
}

# orch_have_baseline -> exit 0 se o commit do baseline existe neste clone
orch_have_baseline() {
  git -C "$(_orch_repo_root)" cat-file -e "$ORCH_BASELINE_REF^{commit}" 2>/dev/null
}

# orch_norm_lines (stdin -> stdout): linhas nao-vazias sem indentacao inicial
orch_norm_lines() {
  sed -e 's/^[[:space:]]*//' | grep -v '^$' || :
}

# orch_missing_lines <root|feature>
# Linhas (multiconjunto) do baseline ausentes do corpus atual, excluidas as da
# allowlist `rewritten-lines.tsv` (referencias internas reescritas — FR-004 ii).
# Imprime as linhas faltantes; exit 0 se nenhuma, 1 se ha faltantes.
orch_missing_lines() {
  _oml_tmp=$(mktemp -d -t 'orch-corpus.XXXXXX') || return 2
  orch_baseline "$1" | orch_norm_lines | LC_ALL=C sort > "$_oml_tmp/base" || { rm -rf "$_oml_tmp"; return 2; }
  orch_corpus "$1" | orch_norm_lines | LC_ALL=C sort > "$_oml_tmp/corpus" || { rm -rf "$_oml_tmp"; return 2; }
  _oml_allow="$(_orch_fixtures_dir)/rewritten-lines.tsv"
  : > "$_oml_tmp/allow"
  if [ -f "$_oml_allow" ]; then
    awk -F '\t' -v o="$1" '$1 == o { print $2 }' "$_oml_allow" > "$_oml_tmp/allow"
  fi
  LC_ALL=C comm -23 "$_oml_tmp/base" "$_oml_tmp/corpus" | grep -vxF -f "$_oml_tmp/allow" > "$_oml_tmp/missing" || :
  cat "$_oml_tmp/missing"
  _oml_n=$(wc -l < "$_oml_tmp/missing" | tr -d ' ')
  rm -rf "$_oml_tmp"
  [ "$_oml_n" -eq 0 ]
}

# orch_cmd_blocks (stdin -> stdout): invocacoes `<script>.sh <subcomando>`, sort -u
orch_cmd_blocks() {
  grep -oE '[A-Za-z0-9_-]+\.sh[ ]+[a-z][a-z0-9_-]*' | sed -E 's/[ ]+/ /' | LC_ALL=C sort -u || :
}

# orch_fragments_check <refs-dir-de-um-orquestrador>
# Todas as copias de cada bloco FRAGMENT:<id> (BEGIN..END, inclusive) entre os
# arquivos do diretorio MUST ser byte-identicas. Imprime uma linha por violacao
# (id + os dois arquivos); exit 1 se ha violacao, 0 caso contrario.
orch_fragments_check() {
  _ofc_dir=$1
  [ -d "$_ofc_dir" ] || return 0
  _ofc_tmp=$(mktemp -d -t 'orch-frag.XXXXXX') || return 2
  for _ofc_f in "$_ofc_dir"/*.md; do
    [ -f "$_ofc_f" ] || continue
    awk -v out="$_ofc_tmp" -v fn="$(basename "$_ofc_f")" '
      /<!-- FRAGMENT:[a-z0-9-]+:BEGIN -->/ {
        id = $0
        sub(/.*FRAGMENT:/, "", id)
        sub(/:BEGIN.*/, "", id)
        system("mkdir -p \"" out "/" id "\"")
        cur = out "/" id "/" fn
        infrag = 1
        curid = id
      }
      infrag { print > cur }
      /<!-- FRAGMENT:[a-z0-9-]+:END -->/ {
        if (infrag) { close(cur); infrag = 0 }
      }
      END {
        if (infrag) print "FRAGMENT " curid ": BEGIN sem END em " fn > (out "/_unterminated")
      }
    ' "$_ofc_f"
  done
  _ofc_rc=0
  if [ -f "$_ofc_tmp/_unterminated" ]; then
    cat "$_ofc_tmp/_unterminated"
    _ofc_rc=1
  fi
  for _ofc_idd in "$_ofc_tmp"/*/; do
    [ -d "$_ofc_idd" ] || continue
    _ofc_id=$(basename "$_ofc_idd")
    _ofc_first=
    for _ofc_c in "$_ofc_idd"*; do
      [ -f "$_ofc_c" ] || continue
      if [ -z "$_ofc_first" ]; then
        _ofc_first=$_ofc_c
        continue
      fi
      if ! cmp -s "$_ofc_first" "$_ofc_c"; then
        printf 'FRAGMENT %s: %s difere de %s\n' "$_ofc_id" "$(basename "$_ofc_c")" "$(basename "$_ofc_first")"
        _ofc_rc=1
      fi
    done
  done
  rm -rf "$_ofc_tmp"
  return "$_ofc_rc"
}

# orch_mcp_block <arquivo> (stdout): bloco MCP-VS-BASH:BEGIN..END sem espaco final
orch_mcp_block() {
  sed -n '/MCP-VS-BASH:BEGIN/,/MCP-VS-BASH:END/p' "$1" | sed -e 's/[[:space:]]*$//'
}

# orch_corpus_init
# Cria o diretorio temporario dos arquivos de corpus materializados e instala
# trap de limpeza no shell corrente. Chamar UMA vez no topo do teste (fora de
# subshell); scenarios rodam em subshells que herdam _ORCH_CF_DIR.
orch_corpus_init() {
  [ -n "${_ORCH_CF_DIR:-}" ] && [ -d "$_ORCH_CF_DIR" ] && return 0
  _ORCH_CF_DIR=$(mktemp -d -t 'orch-cf.XXXXXX') || return 2
  trap 'rm -rf "$_ORCH_CF_DIR"' EXIT
}

# orch_corpus_file <root|feature> -> caminho de um arquivo com o corpus do
# orquestrador (prompt-base + referencias), utilizavel como alvo de grep/awk
# no lugar do prompt-base. Materializa uma unica vez por orquestrador.
orch_corpus_file() {
  # orch_corpus_init MUST ter sido chamado no shell principal (nao em $(...)).
  [ -n "${_ORCH_CF_DIR:-}" ] && [ -d "$_ORCH_CF_DIR" ] || {
    printf 'orch_corpus_file: chame orch_corpus_init no topo do teste\n' >&2
    return 2
  }
  _ocf_out="$_ORCH_CF_DIR/corpus-$1.md"
  if [ ! -f "$_ocf_out" ]; then
    orch_corpus "$1" > "$_ocf_out.tmp" || return 1
    mv "$_ocf_out.tmp" "$_ocf_out"
  fi
  printf '%s' "$_ocf_out"
}
