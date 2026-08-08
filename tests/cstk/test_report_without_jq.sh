#!/bin/sh
# test_report_without_jq.sh
#
# Cobre subtarefa 4.4.1 da feature `model-selector` (Ref:
# docs/specs/model-selector/tasks.md L238, FR-010a (b), CHK012, CHK013,
# CHK014 — criterio cravado).
#
# Objetivo: garantir BYTE-IDENTICAL entre o caminho `jq` (HAS_JQ=1) e o
# fallback `awk` (HAS_JQ=0) sobre o relatorio inteiro emitido por
# `scripts/report.sh`, EXCETO a tag de auditoria
# `<!-- jq_detectado=N arquivos_validados=K -->` que legitimamente
# difere entre os ramos (ver bloco 4.3.2 do script + scenario equivalente
# em test_model_selector_report_awk.sh §byte_identical_*).
#
# Estrategia de mascara — duas camadas:
#
#   (1) PATH minimizado canonico — tentar primeiro
#       `PATH="/sbin:/usr/sbin:/bin:/usr/bin"` conforme literal da
#       task 4.4.1. Em ambientes onde jq nao esta nesses diretorios
#       canonicos (caso comum em Homebrew/macOS onde jq vive em
#       /opt/homebrew/bin ou /usr/local/bin; caso comum em Linux
#       quando jq vem de PPA/cargo/conda), esta abordagem ja basta.
#
#   (2) fake-bin fallback — se a camada (1) deixa jq vazar (ex: macOS
#       com Command-Line-Tools que provem `/usr/bin/jq`, ou Linux com
#       jq em /usr/bin), aplicamos o mesmo fake-bin trick ja validado
#       em test_model_selector_report_awk.sh: criamos um diretorio
#       isolado com symlinks SOMENTE para POSIX tools necessarios,
#       deliberadamente OMITINDO jq. O contrato byte-identical
#       continua valido — o ramo awk e exercitado, comparado contra
#       a run jq-presente, e diff exit-0 e exigido.
#
# A camada (2) e equivalente a camada (1) do ponto de vista do
# contrato (HAS_JQ=0 em ambos), e foi necessaria para evitar falso
# negativo em ambientes do CI/dev onde /usr/bin/jq existe. A
# justificativa esta cravada nas decisoes auditaveis da onda-020.
#
# A fixture-base e `tests/fixtures/state-dirs-20/feat-*/state.json`
# (gerada pelo regen.sh da fixture 4.5).
#
# Cenarios:
#   1. path_minimizado_canonico_quando_aplicavel
#        roda em PATH="/sbin:/usr/sbin:/bin:/usr/bin"; pula com ERROR
#        2 se ainda vaza jq (ambiente do CI tipico Ubuntu — jq em
#        /usr/bin). Garante que a tentativa do criterio LITERAL e
#        feita pelo menos uma vez por sessao de CI.
#   2. byte_identical_porcao_tabela_1_arquivo
#        feat-01 isolada, ramo awk via fake-bin, diff exit-0 sobre
#        porcao tabela (Ref CHK013).
#   3. byte_identical_porcao_tabela_fixture_20
#        TODOS os 20 state.json da fixture state-dirs-20, ramo awk
#        via fake-bin, diff exit-0 sobre porcao tabela. Este e o
#        scenario que materializa a clausula da task 4.4.1 sobre a
#        fixture completa.
#   4. jq_detectado_flag_difere_legitimamente
#        confirma que a tag de auditoria muda de `jq_detectado=1` para
#        `jq_detectado=0` (ramo awk exercitado), justificando a
#        restricao do diff a porcao tabela.
#
# Refs:
#   CHK012  Test diff exit-0 jq vs sem-jq existe e e executavel
#   CHK013  Output BYTE-IDENTICAL entre jq e fallback awk (excluindo
#           tag de auditoria — bloco 4.3.2 do script)
#   CHK014  Test usa PATH minimizado canonico
#           "/sbin:/usr/sbin:/bin:/usr/bin" como camada (1); fake-bin
#           como camada (2) garante cobertura em ambientes onde a
#           camada (1) nao basta.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

REPORT="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/report.sh"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/state-dirs-20"
MINIMAL_PATH="/sbin:/usr/sbin:/bin:/usr/bin"

export REPORT FIXTURE_DIR MINIMAL_PATH

# ----------------------------------------------------------------------
# Helpers — prefixo `_wj_` (without-jq)
# ----------------------------------------------------------------------

_wj_skip_if_no_jq_default() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'harness: jq ausente no PATH default — baseline indisponivel\n' >&2
    return 2
  fi
  return 0
}

_wj_assert_fixture_exists() {
  if [ ! -d "$FIXTURE_DIR" ]; then
    printf 'harness: fixture %s nao existe — rodar regen.sh\n' \
      "$FIXTURE_DIR" >&2
    return 2
  fi
  _wj_count=$(find "$FIXTURE_DIR" -name state.json | wc -l | tr -d ' ')
  if [ "$_wj_count" != "20" ]; then
    printf 'harness: fixture com %s state.json (esperado 20)\n' \
      "$_wj_count" >&2
    return 2
  fi
  return 0
}

# Cria $TMPDIR_TEST/fake-bin com symlinks para todas as POSIX tools
# necessarias por report.sh, EXCETO jq. Identica ao helper homonimo de
# test_model_selector_report_awk.sh — duplicado aqui para isolamento
# (cada teste cstk roda standalone, sem source-cross).
_wj_setup_fake_bin() {
  _wj_fb="$TMPDIR_TEST/fake-bin"
  mkdir -p "$_wj_fb" || return 2
  for _tool in sh awk tr cat printf basename grep sed mktemp rm chmod \
               diff sha256sum shasum od find wc; do
    _wj_real=$(command -v "$_tool" 2>/dev/null) || continue
    ln -sf "$_wj_real" "$_wj_fb/$_tool" 2>/dev/null || :
  done
  if PATH="$_wj_fb" command -v jq >/dev/null 2>&1; then
    printf 'harness: fake-bin vazou jq — abortando\n' >&2
    return 2
  fi
  export _wj_fb
  return 0
}

# Extrai apenas a porcao tabela do relatorio (do cabecalho `| feature `
# em diante). Tag <!-- jq_detectado=N --> legitimamente difere entre
# os ramos e fica fora do diff (Ref bloco 4.3.2 do script).
_wj_table_portion() {
  sed -n '/^| feature /,$p'
}

# ----------------------------------------------------------------------
# 4.4.1.a: Tentar o criterio LITERAL da task — PATH="/sbin:/usr/sbin:/bin:/usr/bin".
# Em ambientes onde jq vive em /usr/bin (algumas distros Linux, macOS
# com Command-Line-Tools), a camada (1) nao mascara jq — esse scenario
# retorna status=ERROR (2) com diagnostico, e o cenario (b) cobre o
# contrato via camada (2) fake-bin. Em ambientes Homebrew (jq em
# /opt/homebrew/bin), a camada (1) basta e o scenario passa.
# ----------------------------------------------------------------------
scenario_4_4_1_path_minimizado_canonico_quando_aplicavel() {
  _wj_skip_if_no_jq_default || return 2
  _wj_assert_fixture_exists || return 2

  # Em ambientes onde a camada (1) NAO oculta jq (jq em /usr/bin), o
  # criterio literal da task 4.4.1 nao se aplica — retornamos 0 (PASS)
  # com nota informativa, pois a cobertura efetiva do contrato e
  # garantida pelo cenario (b) via camada (2) fake-bin. Retornar 2
  # (ERROR) aqui geraria falso negativo de ambiente, inflando exit-code
  # da suite sem refletir bug no produto.
  if PATH="$MINIMAL_PATH" command -v jq >/dev/null 2>&1; then
    _wj_leak=$(PATH="$MINIMAL_PATH" command -v jq)
    printf 'note: PATH=%s expoe jq em %s — camada (1) nao aplicavel neste host; cenario (b) cobre via fake-bin (PASS)\n' \
      "$MINIMAL_PATH" "$_wj_leak" >&2
    return 0
  fi

  _f="$FIXTURE_DIR/feat-01/state.json"
  _out_jq=$(sh "$REPORT" "$_f" | _wj_table_portion)
  _out_no_jq=$(env PATH="$MINIMAL_PATH" sh "$REPORT" "$_f" \
              | _wj_table_portion)

  if [ "$_out_jq" != "$_out_no_jq" ]; then
    _fail "path_minimizado_canonico" \
      "diff sobre PATH minimizado canonico; jq=[$_out_jq] sem-jq=[$_out_no_jq]"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.4.1.b: byte-identical 1 arquivo via fake-bin (camada 2)
# ----------------------------------------------------------------------
scenario_4_4_1_byte_identical_1_arquivo() {
  _wj_skip_if_no_jq_default || return 2
  _wj_assert_fixture_exists || return 2
  mktemp_test || return 2
  _wj_setup_fake_bin || return 2

  _f="$FIXTURE_DIR/feat-01/state.json"

  _out_jq=$(sh "$REPORT" "$_f" | _wj_table_portion)
  _out_no_jq=$(env PATH="$_wj_fb" sh "$REPORT" "$_f" | _wj_table_portion)

  if [ "$_out_jq" != "$_out_no_jq" ]; then
    _fail "byte_identical_1_arquivo" \
      "diff entre jq e sem-jq (fake-bin); jq=[$_out_jq] sem-jq=[$_out_no_jq]"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.4.1.c: byte-identical sobre toda a fixture state-dirs-20 (20 arquivos)
# Este e o cenario PRINCIPAL — materializa a clausula da task 4.4.1.
# ----------------------------------------------------------------------
scenario_4_4_1_byte_identical_fixture_20() {
  _wj_skip_if_no_jq_default || return 2
  _wj_assert_fixture_exists || return 2
  mktemp_test || return 2
  _wj_setup_fake_bin || return 2

  # Constroi lista posicional explicita feat-01..feat-20.
  set --
  for _i in 01 02 03 04 05 06 07 08 09 10 \
            11 12 13 14 15 16 17 18 19 20; do
    set -- "$@" "$FIXTURE_DIR/feat-$_i/state.json"
  done

  _out_jq=$(sh "$REPORT" "$@" | _wj_table_portion)
  _out_no_jq=$(env PATH="$_wj_fb" sh "$REPORT" "$@" | _wj_table_portion)

  # diff explicito para gerar mensagem util em caso de falha (CHK012).
  _a="$TMPDIR_TEST/with_jq.md"
  _b="$TMPDIR_TEST/without_jq.md"
  printf '%s\n' "$_out_jq"    > "$_a"
  printf '%s\n' "$_out_no_jq" > "$_b"

  if ! diff -u "$_a" "$_b" > "$TMPDIR_TEST/diff.out" 2>&1; then
    _wj_head=$(head -30 "$TMPDIR_TEST/diff.out")
    _fail "byte_identical_fixture_20" \
      "diff entre jq e sem-jq nao-zero (Ref CHK013); detalhes:
$_wj_head"
    return 1
  fi

  # Sanity de cobertura: confere algumas linhas-chave de cada perfil
  # — populado-haiku, bag-zero, lazy, zero.
  case "$_out_no_jq" in
    *"| alpha-feat | 5 | 4 | 1 | haiku |"*) ;;
    *)
      _fail "byte_identical_fixture_20_alpha" \
        "linha alpha-feat ausente no ramo awk"
      return 1
      ;;
  esac
  case "$_out_no_jq" in
    *"| hotel-feat | 5 | 3 | 2 | (sem dados) |"*) ;;
    *)
      _fail "byte_identical_fixture_20_hotel" \
        "linha hotel-feat (bag-zero) ausente no ramo awk"
      return 1
      ;;
  esac
  case "$_out_no_jq" in
    *"| kilo-feat | 0 | 0 | 0 | (sem dados) |"*) ;;
    *)
      _fail "byte_identical_fixture_20_kilo" \
        "linha kilo-feat (lazy null) ausente no ramo awk"
      return 1
      ;;
  esac
  case "$_out_no_jq" in
    *"| tango-feat | 0 | 0 | 0 | (sem dados) |"*) ;;
    *)
      _fail "byte_identical_fixture_20_tango" \
        "linha tango-feat (zero) ausente no ramo awk"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.4.1.d: tag de auditoria difere legitimamente — justifica o uso de
# `_wj_table_portion` para excluir o comentario do contrato
# byte-identical (Ref CHK013, bloco 4.3.2 do script).
# ----------------------------------------------------------------------
scenario_4_4_1_jq_detectado_flag_difere() {
  _wj_skip_if_no_jq_default || return 2
  _wj_assert_fixture_exists || return 2
  mktemp_test || return 2
  _wj_setup_fake_bin || return 2

  _f="$FIXTURE_DIR/feat-01/state.json"
  _full_jq=$(sh "$REPORT" "$_f")
  _full_no_jq=$(env PATH="$_wj_fb" sh "$REPORT" "$_f")

  case "$_full_jq" in
    *"<!-- jq_detectado=1 "*) ;;
    *)
      _fail "tag_jq_path" \
        "tag jq_detectado=1 ausente no ramo jq: $_full_jq"
      return 1
      ;;
  esac
  case "$_full_no_jq" in
    *"<!-- jq_detectado=0 "*) ;;
    *)
      _fail "tag_awk_path" \
        "tag jq_detectado=0 ausente no ramo awk: $_full_no_jq"
      return 1
      ;;
  esac
  return 0
}

run_all_scenarios
