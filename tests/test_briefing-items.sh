#!/bin/sh
# test_briefing-items.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/briefing-items.sh
# (feature structural-decision-human-gate, FASE 3, FR-007).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/briefing-items.sh"

_tab() { printf '\t'; }

# ---- P5 / STATUS=briefing-ausente ----

scenario_briefing_ausente_status_e_exit0() {
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/nao-existe.md"
  assert_exit 0 "$SCRIPT" list-high --briefing "$TMPDIR_TEST/nao-existe.md" || return 1
  case "$_CAPTURED_STDOUT" in
    *"STATUS$(_tab)briefing-ausente"*) ;;
    *) _fail "status" "esperado STATUS briefing-ausente, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  assert_stderr_contains "ausente" || return 1
}

# ---- P4 / STATUS=tabela-irreconhecivel (heading presente, lista numerada) ----

scenario_heading_sem_tabela_reconhecivel() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
## Itens a Definir

1. Primeiro item — Alto
2. Segundo item — Medio
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  assert_exit 0 "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md" || return 1
  case "$_CAPTURED_STDOUT" in
    *"STATUS$(_tab)tabela-irreconhecivel"*) ;;
    *) _fail "status" "esperado tabela-irreconhecivel: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  assert_stderr_contains "nao reconhecivel" || return 1
}

scenario_heading_no_fim_do_arquivo_sem_tabela() {
  printf '# Briefing\n\n## Itens a Definir\n' > "$TMPDIR_TEST/b.md"
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  case "$_CAPTURED_STDOUT" in
    *"STATUS$(_tab)tabela-irreconhecivel"*) ;;
    *) _fail "status" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ---- heading ausente do briefing inteiro: sem-itens-alto, SEM aviso ----

scenario_sem_heading_e_sem_itens_alto_silencioso() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
# Briefing sem secao de itens

Nada aqui.
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  assert_exit 0 "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md" || return 1
  case "$_CAPTURED_STDOUT" in
    *"STATUS$(_tab)sem-itens-alto"*) ;;
    *) _fail "status" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
  if [ -n "$_CAPTURED_STDERR" ]; then
    _fail "silencio" "esperava stderr vazio (heading ausente nao e erro), obtido: $_CAPTURED_STDERR"
    return 1
  fi
}

# ---- P1: heading casado ignorando caixa e espacos extras ----

scenario_heading_caixa_e_espacos_extras() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
##   itens A definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Item unico de teste | Dim | Alto |
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  assert_stdout_contains "STATUS$(_tab)ok" || return 1
  assert_stdout_contains "Item unico de teste" || return 1
}

# ---- P2/P3: cabecalho+separadora descartados; impacto pelo token inicial ----

scenario_impacto_por_token_inicial_com_prosa_anexada() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
## Itens a Definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Linguagem e runtime do backend | Stack | Alto — define a interface de retomada |
| Estrategia de cache | Performance | Medio (ambicao de 12 meses) |
| Nome do produto | Marketing | Baixo hoje, sobe depois |
| Persistencia principal | Dados | Alto (define schema) |
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  assert_stdout_contains "Linguagem e runtime do backend" || return 1
  assert_stdout_contains "Persistencia principal" || return 1
  assert_stdout_not_contains "Estrategia de cache" || return 1
  assert_stdout_not_contains "Nome do produto" || return 1
  assert_stdout_contains "STATUS$(_tab)ok" || return 1
}

scenario_impacto_prefixo_nao_casa_palavra_diferente() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
## Itens a Definir

| Item | Dimensao | Impacto |
|---|---|---|
| Item nao deveria contar | Dim | Altoona |
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  assert_stdout_contains "STATUS$(_tab)sem-itens-alto" || return 1
  assert_stdout_not_contains "Item nao deveria contar" || return 1
}

# ---- STATUS=sem-itens-alto: tabela lida, zero itens Alto ----

scenario_tabela_lida_sem_itens_alto() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
## Itens a Definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Apenas item medio | Dim | Medio |
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  assert_exit 0 "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md" || return 1
  assert_stdout_contains "STATUS$(_tab)sem-itens-alto" || return 1
  assert_stdout_not_contains "Apenas item medio" || return 1
}

# ---- P7 / finding L1: sanitizacao de TAB embutido (nao forja coluna) ----

scenario_tab_embutido_nao_forja_coluna_extra() {
  printf '## Itens a Definir\n\n| Item | Dimensao | Impacto |\n|---|---|---|\n| item%scom%stab | dim | Alto |\n' \
    "$(_tab)" "$(_tab)" > "$TMPDIR_TEST/b.md"
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  _data_line=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -v '^STATUS' | head -1)
  _nf=$(printf '%s' "$_data_line" | awk -F'\t' '{print NF}')
  if [ "$_nf" != 3 ]; then
    _fail "colunas" "esperado 3 campos TSV, obtido $_nf: $_data_line"
    return 1
  fi
  case "$_data_line" in
    *"$(_tab)"*"$(_tab)"*"$(_tab)"*)
      _fail "colunas" "TAB embutido sobreviveu, gerou campo a mais: $_data_line"
      return 1
      ;;
  esac
}

# ---- P7: sanitizacao de CR embutido (CRLF) ----

scenario_cr_embutido_sanitizado() {
  printf '## Itens a Definir\r\n\r\n| Item | Dimensao | Impacto |\r\n|---|---|---|\r\n| item com CR | dim | Alto |\r\n' \
    > "$TMPDIR_TEST/b.md"
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  assert_stdout_contains "item com CR" || return 1
  assert_stdout_contains "STATUS$(_tab)ok" || return 1
  case "$_CAPTURED_STDOUT" in
    *"$(printf '\r')"*) _fail "cr" "CR sobreviveu na saida"; return 1 ;;
  esac
}

# ---- INV-B5: determinismo (mesma entrada => mesma chave) ----

scenario_determinismo_mesma_entrada_mesma_chave() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
## Itens a Definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Linguagem e runtime do backend | Stack | Alto |
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  _out1="$_CAPTURED_STDOUT"
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  _out2="$_CAPTURED_STDOUT"
  if [ "$_out1" != "$_out2" ]; then
    _fail "determinismo" "saidas divergentes entre execucoes identicas"
    return 1
  fi
}

scenario_determinismo_entradas_diferentes_chaves_diferentes() {
  cat > "$TMPDIR_TEST/b.md" <<'EOF'
## Itens a Definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Primeiro item distinto | Dim | Alto |
| Segundo item distinto | Dim | Alto |
EOF
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  _k1=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '1p' | cut -f1)
  _k2=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '2p' | cut -f1)
  if [ "$_k1" = "$_k2" ]; then
    _fail "chaves" "itens distintos geraram a mesma chave: $_k1"
    return 1
  fi
}

# ---- truncagem 48 chars + cksum evita colisao de prefixo comum ----

scenario_truncagem_e_cksum_evitam_colisao_prefixo_longo() {
  _long_a="Este e um item MUITO longo que compartilha exatamente os primeiros quarenta e oito caracteres AAA"
  _long_b="Este e um item MUITO longo que compartilha exatamente os primeiros quarenta e oito caracteres BBB"
  {
    printf '## Itens a Definir\n\n| Item | Dimensao | Impacto |\n|---|---|---|\n'
    printf '| %s | Dim | Alto |\n' "$_long_a"
    printf '| %s | Dim | Alto |\n' "$_long_b"
  } > "$TMPDIR_TEST/b.md"
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/b.md"
  _k1=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '1p' | cut -f1)
  _k2=$(printf '%s\n' "$_CAPTURED_STDOUT" | sed -n '2p' | cut -f1)
  if [ "$_k1" = "$_k2" ]; then
    _fail "colisao" "itens longos com prefixo comum de 48+ chars colidiram: $_k1"
    return 1
  fi
  # confirma que os slugs truncados (48 chars) sao de fato identicos —
  # e o cksum (sufixo) que precisa diferenciar.
  _slug1=$(printf '%s' "$_k1" | sed -E 's/-[0-9]+$//')
  _slug2=$(printf '%s' "$_k2" | sed -E 's/-[0-9]+$//')
  if [ "$_slug1" != "$_slug2" ]; then
    _fail "premissa do teste" "slugs truncados deveriam ser iguais: $_slug1 vs $_slug2"
    return 1
  fi
}

# ---- P6: briefing canonico vs legado, mesmo conteudo => mesma chave ----

scenario_briefing_canonico_vs_legado_mesma_chave() {
  mkdir -p "$TMPDIR_TEST/canon" "$TMPDIR_TEST/01-briefing-discovery"
  cat > "$TMPDIR_TEST/canon/briefing.md" <<'EOF'
## Itens a Definir

| Item | Dimensao | Impacto |
|------|----------|---------|
| Linguagem e runtime do backend | Stack | Alto |
EOF
  cp "$TMPDIR_TEST/canon/briefing.md" "$TMPDIR_TEST/01-briefing-discovery/briefing.md"

  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/canon/briefing.md"
  _out_canon="$_CAPTURED_STDOUT"
  capture "$SCRIPT" list-high --briefing "$TMPDIR_TEST/01-briefing-discovery/briefing.md"
  _out_legacy="$_CAPTURED_STDOUT"
  if [ "$_out_canon" != "$_out_legacy" ]; then
    _fail "paridade" "briefing canonico e legado com mesmo conteudo produziram saidas diferentes"
    return 1
  fi
}

# ---- INV-B1: POSIX puro, sem jq — smoke check (grep no fonte) ----

scenario_sem_dependencia_de_jq() {
  # Exclui linhas de comentario (podem mencionar "jq" so para declarar a
  # AUSENCIA da dependencia, INV-B1) — busca por invocacao real do binario.
  if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -qE '(^|[^A-Za-z0-9_])jq([^A-Za-z0-9_]|$)'; then
    _fail "INV-B1" "script invoca jq (deveria ser POSIX puro)"
    return 1
  fi
}

# ---- Uso incorreto: exit 2 ----

scenario_uso_incorreto_sem_briefing_flag() {
  assert_exit 2 "$SCRIPT" list-high || return 1
}

scenario_uso_incorreto_sem_subcomando() {
  assert_exit 2 "$SCRIPT" || return 1
}

scenario_uso_incorreto_flag_desconhecida() {
  assert_exit 2 "$SCRIPT" list-high --flag-inexistente valor || return 1
}

scenario_uso_incorreto_subcomando_desconhecido() {
  assert_exit 2 "$SCRIPT" nao-existe --briefing "$TMPDIR_TEST/b.md" || return 1
}

run_all_scenarios
