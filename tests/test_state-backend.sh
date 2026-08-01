#!/bin/sh
# test_state-backend.sh — cobre global/skills/agente-00c-runtime/scripts/state-backend.sh.
#
# Ref: docs/specs/state-backend-config/tasks.md FASE 2 (2.1.5, 2.2.6, 2.3.2,
#      2.4.3), FASE 3 (3.1.5, 3.2.5); quickstart.md Scenarios 2, 2.5, 2.6,
#      2.7, 3, 4, 4.5, 5, 5.5.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SB="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-backend.sh"
MIN_VER="3.45.1"

# _sb_real_sqlite3_adequate: exit 0 se sqlite3 real estiver no PATH e >= MIN_VER.
# Cenarios que precisam de um sqlite3 REAL adequado (nao stub) fazem skip
# gracioso (return 0, sem FAIL) quando o ambiente nao oferece isso — mesmo
# padrao ja usado noutros arquivos da suite para prereqs opcionais.
_sb_real_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  _va=$(printf '%s' "$_v" | cut -d'.' -f1); _vb=$(printf '%s' "$_v" | cut -d'.' -f2); _vc=$(printf '%s' "$_v" | cut -d'.' -f3)
  _ma=$(printf '%s' "$MIN_VER" | cut -d'.' -f1); _mb=$(printf '%s' "$MIN_VER" | cut -d'.' -f2); _mc=$(printf '%s' "$MIN_VER" | cut -d'.' -f3)
  [ "${_va:-0}" -gt "${_ma:-0}" ] 2>/dev/null && return 0
  [ "${_va:-0}" -lt "${_ma:-0}" ] 2>/dev/null && return 1
  [ "${_vb:-0}" -gt "${_mb:-0}" ] 2>/dev/null && return 0
  [ "${_vb:-0}" -lt "${_mb:-0}" ] 2>/dev/null && return 1
  [ "${_vc:-0}" -ge "${_mc:-0}" ] 2>/dev/null
}

# _sb_isolated_bin_dir: cria (por TMPDIR_TEST) um dir com symlinks para os
# binarios externos que state-backend.sh (e o proprio harness/capture)
# precisam para rodar — EXCLUINDO deliberadamente sqlite3. GOTCHA (memoria
# do projeto): um PATH="stub:$PATH" nao esconde um binario que ja existe
# adiante no PATH original; a unica forma robusta e compor um PATH NOVO
# contendo apenas symlinks explicitos para os binarios necessarios.
_sb_isolated_bin_dir() {
  _sbibd="$TMPDIR_TEST/no-sqlite3-bin"
  if [ ! -d "$_sbibd" ]; then
    mkdir -p "$_sbibd"
    for _sbcmd in cut mktemp mv chmod mkdir rm dirname basename cat sh; do
      _sbcmd_path=$(command -v "$_sbcmd" 2>/dev/null) || continue
      ln -sf "$_sbcmd_path" "$_sbibd/$_sbcmd"
    done
  fi
  printf '%s' "$_sbibd"
}

# ---------------------------------------------------------------------------
# FASE 2.1 — Parsing seguro (P1, P2, P5)
# ---------------------------------------------------------------------------

scenario_resolve_config_ausente_e_nunca_configurado() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home"
  HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "effective_backend=json" || return 1
  assert_stdout_contains "reason=nunca-configurado" || return 1
}

scenario_resolve_comentario_e_linha_em_branco_ignoradas() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf '# comentario inicial\n\nstate_backend=json\n' > "$_home/.claude/cstk/config"
  HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "effective_backend=json" || return 1
  assert_stdout_contains "reason=json-explicito" || return 1
}

scenario_resolve_linha_sem_igual_invalida_config_inteira() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\nlinha sem igual aqui\n' > "$_home/.claude/cstk/config"
  HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "effective_backend=json" || return 1
  assert_stdout_contains "reason=config-invalida" \
    || { _fail "config inteira deveria ser invalida mesmo com state_backend valido presente" "$_CAPTURED_STDOUT"; return 1; }
}

# ---------------------------------------------------------------------------
# FASE 2.2 — Validacao de valor e allowlist (P3, P4) — quickstart 2.5/2.6/2.7
# ---------------------------------------------------------------------------

# Scenario 2.5 (quickstart): payload de injecao na config nunca e executado.
scenario_payload_de_injecao_nunca_e_executado() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  _canary="$TMPDIR_TEST/pwned"
  printf 'state_backend=$(touch %s)\n' "$_canary" > "$_home/.claude/cstk/config"
  HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "reason=config-invalida" \
    || { _fail "payload de injecao deveria cair fora da allowlist -> config-invalida" "$_CAPTURED_STDOUT"; return 1; }
  assert_stdout_contains "effective_backend=json" || return 1
  if [ -e "$_canary" ]; then
    _fail "seguranca" "payload de injecao FOI EXECUTADO — canary '$_canary' existe"
    return 1
  fi
}

# Scenario 2.6 (quickstart): valor sintaticamente valido porem fora da allowlist.
scenario_valor_fora_da_allowlist_vira_config_invalida() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=mysql\n' > "$_home/.claude/cstk/config"
  HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "reason=config-invalida" || return 1
  assert_stdout_contains "effective_backend=json" || return 1
}

# Scenario 2.7 (quickstart): chave desconhecida e ignorada, nao quebra o parse.
scenario_chave_desconhecida_e_ignorada() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf 'chave_nova=valor\nstate_backend=json\n' > "$_home/.claude/cstk/config"
  HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "effective_backend=json" || return 1
  assert_stdout_contains "reason=json-explicito" \
    || { _fail "chave desconhecida nao deveria invalidar a config" "$_CAPTURED_STDOUT"; return 1; }
}

# ---------------------------------------------------------------------------
# FASE 2.3 — resolve: 6 valores do dominio de reason
# ---------------------------------------------------------------------------

scenario_resolve_declarado_sqlite_dependencia_adequada() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "effective_backend=sqlite" || return 1
  assert_stdout_contains "reason=configurado-dependencia-adequada" || return 1
}

scenario_resolve_declarado_sqlite_dependencia_abaixo_do_minimo() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  _stub="$TMPDIR_TEST/stub-low"
  mkdir -p "$_stub"
  cat > "$_stub/sqlite3" <<'EOF'
#!/bin/sh
printf '3.40.0 2024-01-01 00:00:00 deadbeef\n'
EOF
  chmod +x "$_stub/sqlite3"
  PATH="$_stub:$PATH" HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "effective_backend=json" || return 1
  assert_stdout_contains "reason=configurado-dependencia-abaixo-do-minimo" || return 1
}

scenario_resolve_declarado_sqlite_dependencia_ausente() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  _isolated=$(_sb_isolated_bin_dir)
  PATH="$_isolated" HOME="$_home" capture "$SB" resolve
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "effective_backend=json" || return 1
  assert_stdout_contains "reason=configurado-dependencia-ausente" || return 1
}

# ---------------------------------------------------------------------------
# FASE 2.4 — capability
# ---------------------------------------------------------------------------

scenario_capability_imprime_token_e_exit_0() {
  capture "$SB" capability
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ -n "$_CAPTURED_STDOUT" ] || { _fail "capability" "stdout vazio"; return 1; }
}

scenario_dispatcher_subcomando_desconhecido_exit_2() {
  capture "$SB" bogus-subcommand
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------------------------------------------------------------------------
# FASE 3.1 — enable-sqlite: pre-condicoes e mensagens de recusa
# ---------------------------------------------------------------------------

# Scenario 2 (quickstart): recusa por dependencia abaixo do minimo.
scenario_enable_sqlite_recusa_versao_baixa_config_inalterada() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=json\n' > "$_home/.claude/cstk/config"
  _before=$(cat "$_home/.claude/cstk/config")
  _stub="$TMPDIR_TEST/stub-low2"
  mkdir -p "$_stub"
  cat > "$_stub/sqlite3" <<'EOF'
#!/bin/sh
printf '3.40.0 2024-01-01 00:00:00 deadbeef\n'
EOF
  chmod +x "$_stub/sqlite3"
  PATH="$_stub:$PATH" HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "exit" "esperado nao-zero, obtido 0"; return 1; }
  assert_stderr_contains "3.45.1" || return 1
  assert_stderr_contains "3.40.0" \
    || { _fail "mensagem deveria citar a versao detectada" "$_CAPTURED_STDERR"; return 1; }
  _after=$(cat "$_home/.claude/cstk/config")
  [ "$_before" = "$_after" ] || { _fail "config deveria permanecer byte-a-byte identica" "antes=[$_before] depois=[$_after]"; return 1; }
}

# Scenario 3 (quickstart): recusa por dependencia ausente. GOTCHA: PATH
# isolado (nao apenas prefixado) para de fato esconder sqlite3.
scenario_enable_sqlite_recusa_sqlite3_ausente() {
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  _isolated=$(_sb_isolated_bin_dir)
  PATH="$_isolated" HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "exit" "esperado nao-zero, obtido 0"; return 1; }
  assert_stderr_contains "3.45.1" || return 1
  assert_stderr_contains "sqlite3" || return 1
  [ -e "$_home/.claude/cstk/config" ] && { _fail "config" "nao deveria ter sido criada"; return 1; }
  return 0
}

# Scenario 4 (quickstart): recusa por runtime do catalogo incapaz.
scenario_enable_sqlite_recusa_runtime_incapaz() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/skills/agente-00c-runtime/scripts"
  cat > "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh" <<'EOF'
#!/bin/sh
# runtime anterior a esta feature: nao reconhece 'capability'
printf 'subcomando desconhecido\n' >&2
exit 2
EOF
  chmod +x "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh"
  HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "exit" "esperado nao-zero, obtido 0"; return 1; }
  assert_stderr_contains "cstk update" || return 1
  assert_stderr_contains "capability verificado via catalogo-instalado" \
    || { _fail "P8: mensagem deveria citar o caminho validado" "$_CAPTURED_STDERR"; return 1; }
  [ -e "$_home/.claude/cstk/config" ] && { _fail "config" "nao deveria ter sido criada"; return 1; }
  return 0
}

# Scenario 4.5 (quickstart, CHK009): coexistencia repo + catalogo instalado
# com capabilities DIVERGENTES — o catalogo instalado (incapaz) MUST
# prevalecer sobre o repo (capaz), mesmo que o repo sozinho ativaria com
# sucesso. Prova de que P8 nao e so ordem de fallback, e sim prioridade.
scenario_enable_sqlite_recusa_coexistencia_divergente_catalogo_prevalece() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/skills/agente-00c-runtime/scripts"
  cat > "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh" <<'EOF'
#!/bin/sh
printf 'subcomando desconhecido\n' >&2
exit 2
EOF
  chmod +x "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh"

  _fakerepo="$TMPDIR_TEST/fakerepo"
  mkdir -p "$_fakerepo/cli/lib" "$_fakerepo/global/skills/agente-00c-runtime/scripts"
  cp "$SB" "$_fakerepo/global/skills/agente-00c-runtime/scripts/state-backend.sh"
  chmod +x "$_fakerepo/global/skills/agente-00c-runtime/scripts/state-backend.sh"

  CSTK_LIB="$_fakerepo/cli/lib" HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" != 0 ] \
    || { _fail "exit" "catalogo instalado incapaz deveria recusar mesmo com repo capaz disponivel via CSTK_LIB"; return 1; }
  assert_stderr_contains "capability verificado via catalogo-instalado" \
    || { _fail "P8: catalogo instalado deveria ter prioridade sobre o repo" "$_CAPTURED_STDERR"; return 1; }
}

# Decision 5, caso 3: script do catalogo reconhece 'capability' mas reporta
# um token ABAIXO do minimo exigido — mesma decisao (recusar) que os outros
# 2 casos (ausente / subcomando nao reconhecido), ja cobertos acima.
scenario_enable_sqlite_recusa_token_capability_abaixo_do_minimo() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/skills/agente-00c-runtime/scripts"
  cat > "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh" <<'EOF'
#!/bin/sh
case "$1" in
  capability) printf '0\n'; exit 0 ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$_home/.claude/skills/agente-00c-runtime/scripts/state-backend.sh"
  HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "exit" "esperado nao-zero, obtido 0"; return 1; }
  assert_stderr_contains "capability verificado via catalogo-instalado" || return 1
  [ -e "$_home/.claude/cstk/config" ] && { _fail "config" "nao deveria ter sido criada"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# FASE 3.2 — escrita atomica e idempotente (P6, P7)
# ---------------------------------------------------------------------------

scenario_enable_sqlite_sucesso_happy_path_cria_config() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home"
  HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  [ -f "$_home/.claude/cstk/config" ] || { _fail "config" "nao foi criada"; return 1; }
  grep -q '^state_backend=sqlite$' "$_home/.claude/cstk/config" \
    || { _fail "config" "esperado state_backend=sqlite, obtido: $(cat "$_home/.claude/cstk/config")"; return 1; }
}

# Scenario 5 (quickstart): idempotencia — exatamente uma linha, sem duplicar.
scenario_enable_sqlite_idempotente_sem_duplicar_linha() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home"
  HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a ativacao" "$_CAPTURED_STDERR"; return 1; }
  HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a ativacao (idempotente)" "$_CAPTURED_STDERR"; return 1; }
  _n=$(grep -c '^state_backend=' "$_home/.claude/cstk/config")
  [ "$_n" = 1 ] || { _fail "idempotencia" "esperado 1 linha state_backend=, obtido $_n"; return 1; }
}

# Scenario 5.5 (quickstart, CHK013): permissoes 700/600 e ausencia de
# residuo temporario apos uma execucao normal.
scenario_enable_sqlite_permissoes_700_600_sem_residuo() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home"
  HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }

  if stat -f '%Lp' "$_home/.claude/cstk" >/dev/null 2>&1; then
    _dir_perm=$(stat -f '%Lp' "$_home/.claude/cstk")
    _file_perm=$(stat -f '%Lp' "$_home/.claude/cstk/config")
  else
    _dir_perm=$(stat -c '%a' "$_home/.claude/cstk")
    _file_perm=$(stat -c '%a' "$_home/.claude/cstk/config")
  fi
  [ "$_dir_perm" = "700" ] || { _fail "permissao do diretorio" "esperado 700, obtido $_dir_perm"; return 1; }
  [ "$_file_perm" = "600" ] || { _fail "permissao do arquivo" "esperado 600, obtido $_file_perm"; return 1; }

  _residual=$(find "$_home/.claude/cstk" -name 'config.*' 2>/dev/null)
  [ -z "$_residual" ] || { _fail "residuo" "arquivo temporario residual: $_residual"; return 1; }
}

scenario_enable_sqlite_reescreve_declarado_json_para_sqlite() {
  _sb_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_VER"; return 0; }
  _home="$TMPDIR_TEST/home"
  mkdir -p "$_home/.claude/cstk"
  printf '# comentario preservado\nchave_extra=valor\nstate_backend=json\n' > "$_home/.claude/cstk/config"
  HOME="$_home" capture "$SB" enable-sqlite
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_STDERR"; return 1; }
  _n=$(grep -c '^state_backend=' "$_home/.claude/cstk/config")
  [ "$_n" = 1 ] || { _fail "linhas state_backend=" "esperado 1, obtido $_n"; return 1; }
  grep -q '^state_backend=sqlite$' "$_home/.claude/cstk/config" || { _fail "valor" "nao foi reescrito para sqlite"; return 1; }
  grep -q '^# comentario preservado$' "$_home/.claude/cstk/config" || { _fail "comentario" "nao foi preservado"; return 1; }
  grep -q '^chave_extra=valor$' "$_home/.claude/cstk/config" || { _fail "chave desconhecida" "nao foi preservada"; return 1; }
}

run_all_scenarios
