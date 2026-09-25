#!/bin/sh
# test_render-presentation.sh — cobre
# plugins/cstk/skills/presentation/scripts/render-presentation.sh.
#
# Ref: docs/specs/presentation/quickstart.md cenarios 8-10
#      docs/specs/presentation/contracts/slide-grammar.md R-01..R-05

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/presentation/scripts/render-presentation.sh"
SCAN="$REPO_ROOT/plugins/cstk/skills/presentation/scripts/scan-project-docs.sh"

_rp_setup() {
  fixture presentation || return 2
  (cd "$TMPDIR_TEST" && sh "$SCAN" inventory --docs docs > inventory.tsv) || return 2
}

_rp_run() {
  _out=${1:-index.html}
  capture sh -c 'cd "$1" && exec sh "$2" --story story.md --inventory inventory.tsv --out "$3"' _ "$TMPDIR_TEST" "$SCRIPT" "$_out"
}

_rp_html() { cat "$TMPDIR_TEST/${1:-index.html}"; }

_rp_edit() {
  sed "$1" "$TMPDIR_TEST/story.md" > "$TMPDIR_TEST/story.tmp" && mv "$TMPDIR_TEST/story.tmp" "$TMPDIR_TEST/story.md"
}

_rp_has() {
  grep -F -q -- "$1" "$TMPDIR_TEST/index.html" || { _fail "html" "HTML nao contem: $1"; return 1; }
}

_rp_hasnt() {
  if grep -F -q -- "$1" "$TMPDIR_TEST/index.html"; then _fail "html" "HTML contem (nao deveria): $1"; return 1; fi
}

scenario_render_fixture() {
  _rp_setup || return 2
  _rp_run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "RENDERED|index.html|slides=14" || return 1
  _n=$(grep -c '<section class="slide ' "$TMPDIR_TEST/index.html")
  [ "$_n" = 14 ] || { _fail "sections" "esperado 14 sections, obtido $_n"; return 1; }
}

scenario_ordem_e_tipos_dos_slides() {
  _rp_setup || return 2
  _rp_run
  _types=$(sed -n 's/.*<section class="slide slide--\([a-z]*\).*/\1/p' "$TMPDIR_TEST/index.html" | tr '\n' ' ')
  [ "$_types" = "cover manifesto briefing constitution chapter spec spec chapter spec spec timeline numbers closing sources " ] \
    || { _fail "order" "ordem inesperada: $_types"; return 1; }
}

scenario_css_e_js_inline_sem_marcadores() {
  _rp_setup || return 2
  _rp_run
  _rp_has "cstk presentation: design system do deck" || return 1
  _rp_has "cstk presentation: comportamento do deck" || return 1
  _rp_hasnt "{{" || return 1
  _rp_has '<html lang="pt-BR">' || return 1
  _rp_has "<title>Atlas</title>" || return 1
}

scenario_sem_recurso_de_rede() {
  _rp_setup || return 2
  printf '\nVeja https://exemplo.com/pagina para detalhes.\n' >> "$TMPDIR_TEST/story.md"
  _rp_run
  if grep -Eq '(src|href)="(https?:)?//|@import|url\((["'"'"'])?(https?:)?//' "$TMPDIR_TEST/index.html"; then
    _fail "network" "HTML referencia recurso de rede"; return 1
  fi
  _rp_has "default-src 'none'" || return 1
  _rp_hasnt "<a href=\"https" || return 1
}

scenario_deterministico() {
  _rp_setup || return 2
  _rp_run a.html
  _rp_run b.html
  cmp -s "$TMPDIR_TEST/a.html" "$TMPDIR_TEST/b.html" || { _fail "determinism" "renders divergiram"; return 1; }
}

scenario_escapa_html() {
  _rp_setup || return 2
  _rp_edit 's/^Menos telas, menos passos.$/Menos <script>alert(1)<\/script> \& mais "foco"./'
  _rp_run
  _rp_has 'Menos &lt;script&gt;alert(1)&lt;/script&gt; &amp; mais &quot;foco&quot;.' || return 1
  _rp_hasnt '<script>alert(1)' || return 1
}

scenario_formatacao_inline() {
  _rp_setup || return 2
  _rp_run
  _rp_has "Autenticação por <strong>link mágico</strong>, sem senha." || return 1
  _rp_edit 's/^Contraste AA em toda tela.$/Use `a*b*c` e *enfase* aqui./'
  _rp_run
  _rp_has 'Use <code>a*b*c</code> e <em>enfase</em> aqui.' || return 1
}

scenario_metricas_resolvidas_do_inventario() {
  _rp_setup || return 2
  _rp_run
  # spec arquivada: 3/3 tarefas, 3 perguntas, converge clean
  _rp_has '<span class="metric__value">3<span class="metric__of">/3</span></span><span class="metric__label">Tarefas</span>' || return 1
  _rp_has '<span class="metric__value">convergida</span>' || return 1
  # numeros do projeto: 4 specs, 5/7 tarefas
  _rp_has '<span class="metric__value">4</span><span class="metric__label">Specs</span>' || return 1
  _rp_has '<span class="metric__value">5<span class="metric__of">/7</span></span>' || return 1
  _rp_has '<span class="metric__value">1.1.0</span><span class="metric__label">Versão</span>' || return 1
}

scenario_valor_ausente_nao_vira_zero() {
  _rp_setup || return 2
  _rp_edit 's/^@metric Estágio | stage$/@metric Tarefas | tasks/'
  _rp_run
  _rp_has '<span class="metric__value"><span class="na">n&atilde;o registrado</span></span><span class="metric__label">Tarefas</span>' || return 1
}

scenario_estagio_e_badge_da_spec() {
  _rp_setup || return 2
  _rp_run
  _rp_has 'data-key="checkout-flow" data-stage="in-progress"' || return 1
  _rp_has '<span class="badge badge--in-progress">Em andamento</span>' || return 1
  _rp_has '<span class="badge badge--implemented">Implementada</span>' || return 1
  _rp_has '<span class="badge badge--living">Spec viva</span>' || return 1
}

scenario_principio_inegociavel_destacado() {
  _rp_setup || return 2
  _rp_run
  _rp_has '<article class="card card--strong">' || return 1
  _rp_has '<h3 class="card__title">II. Dados Verdadeiros</h3>' || return 1
  _rp_has 'Inegoci&aacute;vel' || return 1
}

scenario_timeline_e_indice_de_fontes() {
  _rp_setup || return 2
  _rp_run
  _rp_has '<span class="timeline__date">Origens</span>' || return 1
  _rp_has '<span class="timeline__date">2026-01-10</span>' || return 1
  _rp_has '<span class="timeline__date">Em andamento</span>' || return 1
  _rp_has '<code>docs/specs/current/login.md</code><span>login</span>' || return 1
}

scenario_capitulos_numerados() {
  _rp_setup || return 2
  _rp_run
  _rp_has 'Cap&iacute;tulo 01' || return 1
  _rp_has 'Cap&iacute;tulo 02' || return 1
  # eyebrow da spec = capitulo corrente + data de arquivamento
  _rp_has '<p class="eyebrow">Fundação &middot; 2026-01-10</p>' || return 1
  _rp_has '<p class="eyebrow">Em construção</p>' || return 1
}

scenario_rotulos_em_ingles() {
  _rp_setup || return 2
  _rp_edit 's/^lang: pt-BR$/lang: en/'
  _rp_run
  _rp_has '<html lang="en">' || return 1
  _rp_has 'Chapter 01' || return 1
  _rp_has '<span class="badge badge--in-progress">In progress</span>' || return 1
}

scenario_sem_frontmatter_exit1() {
  _rp_setup || return 2
  _rp_edit '1,7d'
  _rp_run
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  [ ! -f "$TMPDIR_TEST/index.html" ] || { _fail "atomic" "HTML parcial gravado"; return 1; }
}

scenario_sem_argumentos_exit2() {
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "Uso:" || return 1
}

scenario_template_ausente_exit2() {
  _rp_setup || return 2
  mkdir -p "$TMPDIR_TEST/tpl"
  capture sh "$SCRIPT" --story "$TMPDIR_TEST/story.md" --inventory "$TMPDIR_TEST/inventory.tsv" \
    --out "$TMPDIR_TEST/x.html" --templates "$TMPDIR_TEST/tpl"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "template ausente" || return 1
}

run_all_scenarios
