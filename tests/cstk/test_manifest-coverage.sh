#!/bin/sh
# test_manifest-coverage.sh — cobre cli/lib/manifest-coverage.sh
#
# Contrato: docs/specs/doctor-shadowed-scope/contracts/doctor-shadowed-scope-output.md §5, §7
#
#   manifest_name_is_safe <name>            R1
#   manifest_scrub_text <valor>             R3
#   manifest_record_is_valid <line>         R4 (indiretamente, via campo1)
#   manifest_count_data_lines <path>        denominador
#   manifest_within_cap <path>              R5 (teto configuravel, dec-037)
#   manifest_count_recognized <path>        R4 (set -f na iteracao)
#   manifest_coverage_line <path> D N state [motivo]

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

_LIB="$CSTK_LIB/manifest-coverage.sh"

# ==== manifest_name_is_safe (R1) ====

scenario_name_is_safe_aceita_nome_valido() {
  capture sh -c ". $_LIB && manifest_name_is_safe 'release-wave'"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "exit" "nome valido deveria passar: $_CAPTURED_EXIT"; return 1; }
}

scenario_name_is_safe_aceita_nome_com_ponto_underscore() {
  capture sh -c ". $_LIB && manifest_name_is_safe 'foo.bar_baz-1'"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "exit" "nome valido deveria passar: $_CAPTURED_EXIT"; return 1; }
}

scenario_name_is_safe_rejeita_traversal() {
  capture sh -c ". $_LIB && manifest_name_is_safe '../../../.ssh/known_hosts'"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "traversal" "traversal deveria ser rejeitado"; return 1; }
}

scenario_name_is_safe_rejeita_barra() {
  capture sh -c ". $_LIB && manifest_name_is_safe 'foo/bar'"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "barra" "nome com / deveria ser rejeitado"; return 1; }
}

scenario_name_is_safe_rejeita_barra_invertida() {
  capture sh -c ". $_LIB && manifest_name_is_safe 'foo\\\\bar'"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "barra-invertida" "nome com backslash deveria ser rejeitado"; return 1; }
}

scenario_name_is_safe_rejeita_hifen_inicial() {
  capture sh -c ". $_LIB && manifest_name_is_safe '-rf'"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "hifen-inicial" "nome iniciado com - deveria ser rejeitado"; return 1; }
}

scenario_name_is_safe_rejeita_vazio() {
  capture sh -c ". $_LIB && manifest_name_is_safe ''"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "vazio" "nome vazio deveria ser rejeitado"; return 1; }
}

scenario_name_is_safe_rejeita_500_chars() {
  _big=$(awk 'BEGIN { s=""; for (i=0;i<500;i++) s=s"a"; print s }')
  capture sh -c ". $_LIB && manifest_name_is_safe '$_big'"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "500-chars" "nome com 500 chars deveria ser rejeitado (> 64)"; return 1; }
}

scenario_name_is_safe_rejeita_caractere_glob() {
  capture sh -c ". $_LIB && manifest_name_is_safe 'foo*bar'"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "glob" "nome com * deveria ser rejeitado (fora do charset)"; return 1; }
}

# ==== manifest_scrub_text (R3) ====

scenario_scrub_text_remove_esc_cr_bs() {
  _raw=$(printf 'foo\033[31mbar\rbaz\bqux')
  capture sh -c ". $_LIB && manifest_scrub_text \"\$1\"" -- "$_raw"
  case "$_CAPTURED_STDOUT" in
    *"$(printf '\033')"*) _fail "esc" "ESC nao foi removido"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"$(printf '\r')"*) _fail "cr" "CR nao foi removido"; return 1 ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *"$(printf '\b')"*) _fail "bs" "backspace nao foi removido"; return 1 ;;
  esac
  # ESC/CR/BS (bytes de controle) removidos; "[31m" e texto IMPRIMIVEL (parte
  # visual da sequencia ANSI, nao um byte de controle) e MUST permanecer —
  # manifest_scrub_text so remove C0/DEL, nunca reconhece semantica ANSI.
  [ "$_CAPTURED_STDOUT" = "foo[31mbarbazqux" ] || { _fail "conteudo" "esperado foo[31mbarbazqux, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_scrub_text_trunca_64_chars() {
  _big=$(awk 'BEGIN { s=""; for (i=0;i<200;i++) s=s"x"; print s }')
  capture sh -c ". $_LIB && manifest_scrub_text \"\$1\"" -- "$_big"
  _len=${#_CAPTURED_STDOUT}
  [ "$_len" -eq 64 ] || { _fail "truncamento" "esperado 64 chars, obtido $_len"; return 1; }
}

scenario_scrub_text_preserva_texto_normal() {
  capture sh -c ". $_LIB && manifest_scrub_text 'v1.2.3'"
  [ "$_CAPTURED_STDOUT" = "v1.2.3" ] || { _fail "conteudo" "texto normal nao deveria mudar: $_CAPTURED_STDOUT"; return 1; }
}

# ==== manifest_record_is_valid ====

scenario_record_is_valid_aceita_linha_valida() {
  _sha=$(awk 'BEGIN { s=""; for (i=0;i<64;i++) s=s"a"; print s }')
  _line=$(printf 'my-skill\t1.2.3\t%s\t2026-08-27T00:00:00Z' "$_sha")
  capture sh -c ". $_LIB && manifest_record_is_valid \"\$1\"" -- "$_line"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "exit" "linha valida deveria passar: $_CAPTURED_EXIT"; return 1; }
}

scenario_record_is_valid_rejeita_menos_de_4_campos() {
  capture sh -c ". $_LIB && manifest_record_is_valid \"\$1\"" -- "$(printf 'a\tb\tc')"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "campos" "linha com 3 campos deveria ser rejeitada"; return 1; }
}

scenario_record_is_valid_rejeita_sha_invalido() {
  _line=$(printf 'my-skill\t1.2.3\tNOTAHASH\t2026-08-27T00:00:00Z')
  capture sh -c ". $_LIB && manifest_record_is_valid \"\$1\"" -- "$_line"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "sha" "sha invalido deveria ser rejeitado"; return 1; }
}

scenario_record_is_valid_rejeita_sha_curto() {
  _line=$(printf 'my-skill\t1.2.3\taaaa\t2026-08-27T00:00:00Z')
  capture sh -c ". $_LIB && manifest_record_is_valid \"\$1\"" -- "$_line"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "sha-curto" "sha com 4 chars deveria ser rejeitado"; return 1; }
}

scenario_record_is_valid_rejeita_nome_traversal() {
  _sha=$(awk 'BEGIN { s=""; for (i=0;i<64;i++) s=s"a"; print s }')
  _line=$(printf '../../../.ssh/known_hosts\t1.2.3\t%s\t2026-08-27T00:00:00Z' "$_sha")
  capture sh -c ". $_LIB && manifest_record_is_valid \"\$1\"" -- "$_line"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "traversal" "nome traversal deveria ser rejeitado"; return 1; }
}

scenario_record_is_valid_remove_cr_terminal() {
  _sha=$(awk 'BEGIN { s=""; for (i=0;i<64;i++) s=s"a"; print s }')
  _line=$(printf 'my-skill\t1.2.3\t%s\t2026-08-27T00:00:00Z\r' "$_sha")
  capture sh -c ". $_LIB && manifest_record_is_valid \"\$1\"" -- "$_line"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "cr" "linha com CR terminal (CRLF) deveria passar apos strip: $_CAPTURED_EXIT"; return 1; }
}

# ==== manifest_count_data_lines ====

scenario_count_data_lines_sem_newline_final_conta_1() {
  _f="$TMPDIR_TEST/m1"
  printf 'a\tb\tc\td' > "$_f"
  capture sh -c ". $_LIB && manifest_count_data_lines \"\$1\"" -- "$_f"
  [ "$_CAPTURED_STDOUT" = "1" ] || { _fail "contagem" "esperado 1, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_count_data_lines_arquivo_ausente_zero() {
  capture sh -c ". $_LIB && manifest_count_data_lines \"\$1\"" -- "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_STDOUT" = "0" ] || { _fail "ausente" "esperado 0, obtido: $_CAPTURED_STDOUT"; return 1; }
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ausente-exit" "esperado exit 0, obtido: $_CAPTURED_EXIT"; return 1; }
}

scenario_count_data_lines_ignora_comentarios_e_brancas_no_meio() {
  _f="$TMPDIR_TEST/m2"
  {
    printf '# cstk manifest v1\n'
    printf '# schema: comment\n'
    printf 'a\tb\tc\td\n'
    printf '\n'
    printf '# comentario no meio\n'
    printf 'e\tf\tg\th\n'
  } > "$_f"
  capture sh -c ". $_LIB && manifest_count_data_lines \"\$1\"" -- "$_f"
  [ "$_CAPTURED_STDOUT" = "2" ] || { _fail "meio" "esperado 2, obtido: $_CAPTURED_STDOUT"; return 1; }
}

# ==== manifest_within_cap (R5, dec-037: default configuravel) ====

scenario_within_cap_arquivo_pequeno_ok() {
  _f="$TMPDIR_TEST/small"
  printf 'a\tb\tc\td\n' > "$_f"
  capture sh -c ". $_LIB && manifest_within_cap \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "small" "arquivo pequeno nao deveria exceder o teto: $_CAPTURED_EXIT"; return 1; }
}

scenario_within_cap_arquivo_ausente_ok() {
  capture sh -c ". $_LIB && manifest_within_cap \"\$1\"" -- "$TMPDIR_TEST/nao-existe"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ausente" "arquivo ausente nao deveria exceder o teto: $_CAPTURED_EXIT"; return 1; }
}

# Cenario 19 linha 14: manifesto com 10.001 linhas excede o teto default.
scenario_within_cap_excede_por_linhas_default() {
  _f="$TMPDIR_TEST/many-lines"
  awk 'BEGIN { for (i=0;i<10001;i++) print "line" i }' > "$_f"
  capture sh -c ". $_LIB && manifest_within_cap \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "10001-linhas" "10001 linhas deveria exceder o teto default (10000)"; return 1; }
}

# Override configuravel (dec-037: "a suite deve cobrir o default E um override").
scenario_within_cap_override_max_lines_libera_10001() {
  _f="$TMPDIR_TEST/many-lines-2"
  awk 'BEGIN { for (i=0;i<10001;i++) print "line" i }' > "$_f"
  capture sh -c "CSTK_MANIFEST_MAX_LINES=20000 sh -c '. $_LIB && manifest_within_cap \"\$1\"' -- \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "override" "com CSTK_MANIFEST_MAX_LINES=20000, 10001 linhas nao deveria exceder: $_CAPTURED_EXIT"; return 1; }
}

# Cenario 19 linha 15: registro unico de 50 MB sem \n excede o teto por
# bytes-por-linha, e o teto e imposto por LEITURA LIMITADA (head -c) — o
# teste confirma o resultado (exceeded), nao o pico de memoria em si.
scenario_within_cap_excede_por_registro_gigante_sem_newline() {
  _f="$TMPDIR_TEST/giant-record"
  # 50 MB sem newline final (dd evita pathname-expansion/inflar via shell).
  dd if=/dev/zero bs=1048576 count=50 2>/dev/null | tr '\0' 'a' > "$_f"
  capture sh -c ". $_LIB && manifest_within_cap \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "gigante" "registro de 50MB sem newline deveria exceder o teto de bytes/linha"; return 1; }
}

scenario_within_cap_override_max_line_bytes() {
  _f="$TMPDIR_TEST/one-long-line"
  awk 'BEGIN { s=""; for (i=0;i<5000;i++) s=s"a"; print s }' > "$_f"
  # Default (4096) deve exceder.
  capture sh -c ". $_LIB && manifest_within_cap \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "default-exceed" "linha de 5000 bytes deveria exceder o teto default de 4096"; return 1; }
  # Override libera.
  capture sh -c "CSTK_MANIFEST_MAX_LINE_BYTES=8192 sh -c '. $_LIB && manifest_within_cap \"\$1\"' -- \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "override-exceed" "com CSTK_MANIFEST_MAX_LINE_BYTES=8192, linha de 5000 bytes nao deveria exceder"; return 1; }
}

# ==== manifest_count_recognized (R4: set -f na iteracao) ====

# Cenario 9.d: linha de dados contendo "*" -- exatamente 1 iteracao, sem
# inflar o numerador/denominador via pathname expansion.
scenario_count_recognized_asterisco_nao_infla_iteracao() {
  _dir="$TMPDIR_TEST/glob-dir"
  mkdir -p "$_dir"
  # Varios arquivos que um "*" sem set -f expandiria.
  : > "$_dir/aaa.txt"
  : > "$_dir/bbb.txt"
  : > "$_dir/ccc.txt"
  _sha=$(awk 'BEGIN { s=""; for (i=0;i<64;i++) s=s"a"; print s }')
  _f="$_dir/manifest-with-glob"
  printf 'foo*bar\t1.0\t%s\t2026-08-27T00:00:00Z\n' "$_sha" > "$_f"
  capture sh -c "cd '$_dir' && . $_LIB && manifest_count_recognized \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "exit" "cap nao deveria exceder: $_CAPTURED_EXIT / $_CAPTURED_STDERR"; return 1; }
  _d=$(printf '%s' "$_CAPTURED_STDOUT" | awk '{print $1}')
  [ "$_d" = "1" ] || { _fail "denominador" "esperado D=1 (nao inflado por glob), obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_count_recognized_conta_recognized_e_unrecognized() {
  _f="$TMPDIR_TEST/mixed-manifest"
  _sha=$(awk 'BEGIN { s=""; for (i=0;i<64;i++) s=s"a"; print s }')
  {
    printf 'good-one\t1.0\t%s\t2026-08-27T00:00:00Z\n' "$_sha"
    printf '../traversal\t1.0\t%s\t2026-08-27T00:00:00Z\n' "$_sha"
    printf 'malformed-only-3-fields\tv1\tv2\n'
  } > "$_f"
  capture sh -c ". $_LIB && manifest_count_recognized \"\$1\"" -- "$_f"
  [ "$_CAPTURED_STDOUT" = "3 1" ] || { _fail "contagem" "esperado D=3 N=1, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_count_recognized_cap_excedido_propaga_erro() {
  _f="$TMPDIR_TEST/many-lines-3"
  awk 'BEGIN { for (i=0;i<10001;i++) print "line" i }' > "$_f"
  capture sh -c ". $_LIB && manifest_count_recognized \"\$1\"" -- "$_f"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "cap" "deveria devolver exit != 0 quando o teto e excedido"; return 1; }
  [ "$_CAPTURED_STDOUT" = "CAP-EXCEEDED" ] || { _fail "cap-msg" "esperado CAP-EXCEEDED, obtido: $_CAPTURED_STDOUT"; return 1; }
}

# ==== manifest_coverage_line (5 coverage_state) ====

scenario_coverage_line_full() {
  capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' 3 3 full"
  assert_stdout_contains "[full]" || return 1
  assert_stdout_contains "registros no arquivo: 3" || return 1
  assert_stdout_contains "interpretados: 3" || return 1
  assert_stdout_contains "nao interpretados: 0" || return 1
}

scenario_coverage_line_partial() {
  capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' 5 3 partial"
  assert_stdout_contains "[partial]" || return 1
  assert_stdout_contains "nao interpretados: 2" || return 1
}

scenario_coverage_line_unreadable_inclui_motivo() {
  capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' '?' '?' unreadable 'header desconhecido'"
  assert_stdout_contains "[unreadable]" || return 1
  assert_stdout_contains "registros no arquivo: ?" || return 1
  assert_stdout_contains "interpretados: ?" || return 1
  assert_stdout_contains "motivo: header desconhecido" || return 1
}

scenario_coverage_line_absent() {
  capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' 0 0 absent"
  assert_stdout_contains "[absent]" || return 1
  assert_stdout_contains "registros no arquivo: 0" || return 1
  assert_stdout_contains "interpretados: 0" || return 1
  assert_stdout_contains "nao interpretados: 0" || return 1
}

scenario_coverage_line_inconsistent_mostra_numeros_brutos() {
  capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' 2 5 inconsistent"
  assert_stdout_contains "[inconsistent]" || return 1
  assert_stdout_contains "registros no arquivo: 2" || return 1
  assert_stdout_contains "interpretados: 5" || return 1
  assert_stdout_contains "reporte este caso" || return 1
}

# Regressao de mensagem cruzada: "reporte este caso" so pode aparecer em
# inconsistent — nenhum dos outros 4 estados a inclui.
scenario_coverage_line_reporte_este_caso_so_em_inconsistent() {
  for _state_dn in "full:3:3" "partial:5:3" "absent:0:0"; do
    _state=$(printf '%s' "$_state_dn" | cut -d: -f1)
    _d=$(printf '%s' "$_state_dn" | cut -d: -f2)
    _n=$(printf '%s' "$_state_dn" | cut -d: -f3)
    capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' $_d $_n $_state"
    case "$_CAPTURED_STDOUT" in
      *"reporte este caso"*)
        _fail "cruzada" "estado $_state nao deveria conter a nota 'reporte este caso'"
        return 1
        ;;
    esac
  done
  capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' '?' '?' unreadable 'x'"
  case "$_CAPTURED_STDOUT" in
    *"reporte este caso"*) _fail "cruzada-unreadable" "unreadable nao deveria conter a nota"; return 1 ;;
  esac
}

scenario_coverage_line_estado_desconhecido_erro() {
  capture sh -c ". $_LIB && manifest_coverage_line './.claude/agents/.cstk-manifest' 1 1 bogus"
  [ "$_CAPTURED_EXIT" != "0" ] || { _fail "bogus" "estado desconhecido deveria falhar"; return 1; }
}

run_all_scenarios
