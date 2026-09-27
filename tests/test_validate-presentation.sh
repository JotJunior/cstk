#!/bin/sh
# test_validate-presentation.sh — cobre
# plugins/cstk/skills/presentation/scripts/validate-presentation.sh.
#
# Ref: docs/specs/presentation/quickstart.md cenarios 5-7
#      docs/specs/presentation/contracts/slide-grammar.md G-01..G-10

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/presentation/scripts/validate-presentation.sh"
SCAN="$REPO_ROOT/plugins/cstk/skills/presentation/scripts/scan-project-docs.sh"

# _vp_setup -> copia a fixture e gera inventory.tsv no tmpdir.
_vp_setup() {
  fixture presentation || return 2
  (cd "$TMPDIR_TEST" && sh "$SCAN" inventory --docs docs > inventory.tsv) || return 2
}

# _vp_run -> valida story.md do tmpdir (cwd = tmpdir, root = .)
_vp_run() {
  capture sh -c 'cd "$1" && exec sh "$2" --story story.md --inventory inventory.tsv' _ "$TMPDIR_TEST" "$SCRIPT"
}

# _vp_edit SED_EXPR -> aplica edicao portavel (sem sed -i) na story.
_vp_edit() {
  sed "$1" "$TMPDIR_TEST/story.md" > "$TMPDIR_TEST/story.tmp" && mv "$TMPDIR_TEST/story.tmp" "$TMPDIR_TEST/story.md"
}

_vp_expect_fail() {
  _vp_run
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "$1" || return 1
}

scenario_story_valida_exit0() {
  _vp_setup || return 2
  _vp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "RESULT|slides=14|specs=4/4|errors=0|warnings=0" || return 1
}

scenario_spec_sem_slide() {
  _vp_setup || return 2
  mkdir -p "$TMPDIR_TEST/docs/specs/search"
  printf '# Feature Specification: Busca\n' > "$TMPDIR_TEST/docs/specs/search/spec.md"
  (cd "$TMPDIR_TEST" && sh "$SCAN" inventory --docs docs > inventory.tsv)
  _vp_expect_fail "spec sem slide: search" || return 1
  assert_stdout_contains "specs=4/5" || return 1
}

scenario_key_desconhecida() {
  _vp_setup || return 2
  _vp_edit 's|key=checkout-flow|key=checkout-inventado|'
  _vp_expect_fail "key desconhecida: checkout-inventado" || return 1
}

scenario_key_duplicada() {
  _vp_setup || return 2
  _vp_edit 's|key=current/login|key=checkout-flow|'
  _vp_expect_fail "key duplicada: checkout-flow" || return 1
}

scenario_spec_com_tres_secoes() {
  _vp_setup || return 2
  _vp_edit '/^### Como foi implementada$/,/^Em andamento/d'
  _vp_expect_fail "esperado 4 secoes ###, obtido 3" || return 1
}

scenario_metric_chave_inventada() {
  _vp_setup || return 2
  _vp_edit 's/^@metric Specs | specs$/@metric Clientes | clientes-ativos/'
  _vp_expect_fail "@metric chave invalida: clientes-ativos" || return 1
}

scenario_metric_de_spec_fora_do_escopo() {
  _vp_setup || return 2
  _vp_edit 's/^@metric Specs | specs$/@metric Estagio | stage/'
  _vp_expect_fail "@metric chave invalida: stage" || return 1
}

scenario_slide_factual_sem_source() {
  _vp_setup || return 2
  _vp_edit '/^@source docs\/briefing.md$/d'
  _vp_expect_fail "slide briefing sem @source" || return 1
}

scenario_source_inexistente() {
  _vp_setup || return 2
  _vp_edit 's|^@source docs/briefing.md$|@source docs/nao-existe.md|'
  _vp_expect_fail "@source inexistente: docs/nao-existe.md" || return 1
}

scenario_placeholder() {
  _vp_setup || return 2
  _vp_edit 's/^Menos telas, menos passos.$/TODO escrever/'
  _vp_expect_fail "placeholder: TODO" || return 1
}

scenario_palavra_todos_nao_e_placeholder() {
  _vp_setup || return 2
  _vp_edit 's/^Menos telas, menos passos.$/TODOS os passos importam./'
  _vp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "TODOS nao deveria ser placeholder; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_tipo_desconhecido() {
  _vp_setup || return 2
  _vp_edit 's/^<!-- slide: manifesto -->$/<!-- slide: agradecimentos -->/'
  _vp_expect_fail "tipo de slide desconhecido: agradecimentos" || return 1
}

scenario_diretiva_desconhecida() {
  _vp_setup || return 2
  _vp_edit 's/^@timeline$/@grafico vendas/'
  _vp_expect_fail "diretiva desconhecida: @grafico" || return 1
}

scenario_cover_fora_da_primeira_posicao() {
  _vp_setup || return 2
  _vp_edit 's/^<!-- slide: cover -->$/<!-- slide: manifesto -->/; s/^<!-- slide: closing -->$/<!-- slide: cover -->/'
  _vp_expect_fail "cover deve ser o primeiro slide" || return 1
  assert_stderr_contains "falta slide closing" || return 1
}

scenario_sources_ausente() {
  _vp_setup || return 2
  _vp_edit 's/^<!-- slide: sources -->$/<!-- slide: closing -->/'
  _vp_expect_fail "sources deve aparecer exatamente uma vez" || return 1
}

scenario_frontmatter_sem_lang() {
  _vp_setup || return 2
  _vp_edit '/^lang: pt-BR$/d'
  _vp_expect_fail "frontmatter: lang obrigatorio" || return 1
}

scenario_frontmatter_lang_invalido() {
  _vp_setup || return 2
  _vp_edit 's/^lang: pt-BR$/lang: es/'
  _vp_expect_fail "lang deve ser pt-BR ou en" || return 1
}

scenario_sem_frontmatter() {
  _vp_setup || return 2
  _vp_edit '1,7d'
  _vp_expect_fail "frontmatter" || return 1
}

scenario_mensagem_com_numero_de_linha() {
  _vp_setup || return 2
  _vp_edit 's/^@metric Specs | specs$/@metric Clientes | clientes/'
  _vp_run
  printf '%s\n' "$_CAPTURED_STDERR" | grep -Eq '^story\.md:[0-9]+: @metric chave invalida: clientes$' \
    || { _fail "format" "mensagem sem FILE:LINHA: $_CAPTURED_STDERR"; return 1; }
}

scenario_comentario_antes_do_primeiro_slide_ok() {
  _vp_setup || return 2
  _vp_edit 's/^<!-- slide: cover -->$/<!-- gerado pela skill presentation -->\
<!-- slide: cover -->/'
  _vp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "comentario nao deveria reprovar; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_texto_fora_de_slide() {
  _vp_setup || return 2
  _vp_edit 's/^<!-- slide: cover -->$/Texto solto\
<!-- slide: cover -->/'
  _vp_expect_fail "conteudo fora de slide" || return 1
}

# ---------- linguagem de produto (G-11..G-13) ----------

_vp_tech() {
  _vp_setup || return 2
  _vp_edit "s|^Menos telas, menos passos.\$|$1|"
  _vp_expect_fail "tecniques: $2" || return 1
}

scenario_tecniques_codigo_entre_crases() {
  _vp_tech 'Rode `make build` para gerar.' "codigo" || return 1
}

scenario_tecniques_url() {
  _vp_tech 'Veja https://exemplo.com/docs para detalhes.' 'url "https://exemplo.com/docs"' || return 1
}

scenario_tecniques_endpoint() {
  _vp_tech 'O painel chama GET /api/reservas a cada minuto.' 'endpoint "GET /api/reservas"' || return 1
}

scenario_tecniques_flag() {
  _vp_tech 'Basta passar --force para seguir.' 'flag "--force"' || return 1
}

scenario_tecniques_caminho() {
  _vp_tech 'A regra vive em docs/regras para todos.' 'caminho "docs/regras"' || return 1
}

scenario_tecniques_arquivo() {
  _vp_tech 'Tudo fica no config.json do projeto.' 'arquivo "config.json"' || return 1
}

scenario_barra_simples_nao_e_caminho() {
  _vp_setup || return 2
  _vp_edit 's|^Menos telas, menos passos.$|Menos telas e/ou passos, entrada/saida clara.|'
  _vp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "e/ou nao deveria reprovar; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_source_e_tag_podem_ter_tecniques() {
  _vp_setup || return 2
  _vp_edit 's|^@tag Expiração automática$|@tag `sqlite3` e config.json|'
  _vp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "@tag nao deveria reprovar; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_jargao_e_aviso_nao_bloqueante() {
  _vp_setup || return 2
  _vp_edit 's|^Menos telas, menos passos.$|Menos telas, com um backend enxuto.|'
  _vp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "aviso nao deveria bloquear; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains 'aviso: termo tecnico "backend"' || return 1
  assert_stdout_contains "errors=0|warnings=1" || return 1
}

scenario_vocabulary_suprime_aviso() {
  _vp_setup || return 2
  _vp_edit 's|^Menos telas, menos passos.$|Menos telas, com um backend enxuto.|; s|^vocabulary: checkout$|vocabulary: checkout, Backend|'
  _vp_run
  assert_stdout_contains "errors=0|warnings=0" || return 1
}

scenario_jargao_com_traducao_continua_aviso() {
  # a traducao curta e responsabilidade do redator; o aviso lembra de conferir
  _vp_setup || return 2
  _vp_edit 's|^Menos telas, menos passos.$|Os dados ficam no SQLite, um banco de dados de bolso que funciona sem internet.|'
  _vp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains 'termo tecnico "sqlite"' || return 1
}

scenario_mais_de_tres_tags() {
  _vp_setup || return 2
  _vp_edit 's|^@tag Expiração automática$|@tag A\
@tag B\
@tag C|'
  _vp_expect_fail "slide com 4 @tag (maximo 3)" || return 1
}

scenario_glossario_inexistente_exit2() {
  _vp_setup || return 2
  capture sh -c 'cd "$1" && exec sh "$2" --story story.md --inventory inventory.tsv --jargon nada.txt' _ "$TMPDIR_TEST" "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sem_argumentos_exit2() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
}

scenario_story_inexistente_exit2() {
  : > "$TMPDIR_TEST/inv.tsv"
  assert_exit 2 sh "$SCRIPT" --story "$TMPDIR_TEST/nada.md" --inventory "$TMPDIR_TEST/inv.tsv" || return 1
}

run_all_scenarios
