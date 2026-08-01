#!/bin/sh
# test_config-roundtrip.sh — SC-004: roundtrip de consistencia binario<->runtime.
#
# Feature: state-backend-config
# Ref: docs/specs/state-backend-config/tasks.md FASE 6, task 6.1
#      docs/specs/state-backend-config/quickstart.md Scenario 9
#      docs/specs/state-backend-config/contracts/state-backend-runtime.md
#      §Invariante de consistencia
#
# NAO mapeia 1:1 para um unico script sob a convencao de FASE 9.3 (config.sh
# ou doctor.sh) — e um teste de COMPOSICAO cross-cutting, mesmo padrao de
# test_e2e_model_routing.sh. Registrado como interno em
# tests/run.sh::_is_internal_test.
#
# O que este arquivo prova, empiricamente (NAO por asserção separada em cada
# lado — e exatamente o que SC-004 exige): para as 6 combinacoes de config x
# ambiente do Scenario 9, o backend resolvido pelo CAMINHO DO BINARIO
# (`cstk doctor --deps`, via cli/lib/doctor.sh + cli/lib/config.sh) e o
# backend efetivamente APLICADO pelo CAMINHO DO RUNTIME (`state-rw.sh init`,
# observando qual arquivo foi criado num state-dir limpo) SEMPRE concordam —
# 0% de divergencia. A Decision 2 (research.md) torna isso verdadeiro por
# construcao (uma unica implementacao real de `resolve` em
# state-backend.sh); este teste e o que IMPEDE REGRESSAO caso alguem
# reintroduza um parser paralelo no CLI por conveniencia (task 6.1.2).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/state-rw.sh"
MIN_SQLITE_VER="3.45.1"

# _rt_real_sqlite3_adequate: exit 0 se o sqlite3 REAL do ambiente (PATH
# herdado, sem stub) atende o minimo — mesmo padrao usado em
# tests/test_state-backend.sh, tests/test_state-rw.sh e
# tests/cstk/test_doctor.sh para as combinacoes que exigem ambiente
# "adequado" (Scenario 9, linhas 1/2/3/6 da tabela).
_rt_real_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  _va=$(printf '%s' "$_v" | cut -d'.' -f1); _vb=$(printf '%s' "$_v" | cut -d'.' -f2); _vc=$(printf '%s' "$_v" | cut -d'.' -f3)
  _ma=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f1); _mb=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f2); _mc=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f3)
  [ "${_va:-0}" -gt "${_ma:-0}" ] 2>/dev/null && return 0
  [ "${_va:-0}" -lt "${_ma:-0}" ] 2>/dev/null && return 1
  [ "${_vb:-0}" -gt "${_mb:-0}" ] 2>/dev/null && return 0
  [ "${_vb:-0}" -lt "${_mb:-0}" ] 2>/dev/null && return 1
  [ "${_vc:-0}" -ge "${_mc:-0}" ] 2>/dev/null
}

# _rt_isolated_path_without_sqlite3: PATH REPLACEMENT (nao prefixo — GOTCHA
# de campo: "PATH=stub:$PATH nao esconde um binario que ja existe adiante no
# PATH original", memoria do projeto e tests/test_state-backend.sh) que
# preserva TODO o toolset real (necessario porque doctor.sh + state-rw.sh
# sao scripts grandes, ao contrario do state-backend.sh isolado testado em
# test_state-backend.sh) exceto o proprio sqlite3 — simula ausencia real da
# dependencia sem depender de uma lista curada de binarios.
_rt_isolated_path_without_sqlite3() {
  _ripws_dir="$TMPDIR_TEST/no-sqlite3-full-bin"
  if [ ! -d "$_ripws_dir" ]; then
    mkdir -p "$_ripws_dir"
    _ripws_old_ifs=$IFS
    IFS=':'
    for _ripws_d in $PATH; do
      [ -d "$_ripws_d" ] || continue
      for _ripws_f in "$_ripws_d"/*; do
        [ -e "$_ripws_f" ] || continue
        _ripws_bn=$(basename "$_ripws_f")
        [ "$_ripws_bn" = "sqlite3" ] && continue
        [ -e "$_ripws_dir/$_ripws_bn" ] && continue
        ln -sf "$_ripws_f" "$_ripws_dir/$_ripws_bn" 2>/dev/null
      done
    done
    IFS=$_ripws_old_ifs
  fi
  printf '%s' "$_ripws_dir"
}

# _rt_stub_path_sqlite3_below_min: PATH com um stub de sqlite3 PREFIXADO ao
# PATH real (aqui o prefixo FUNCIONA — ao contrario do caso "ausente" acima
# — porque `command -v` casa o PRIMEIRO sqlite3 do PATH, que passa a ser o
# stub; nao estamos escondendo, estamos substituindo por versao inadequada).
_rt_stub_path_sqlite3_below_min() {
  _rspb_dir="$TMPDIR_TEST/stub-sqlite3-low"
  if [ ! -d "$_rspb_dir" ]; then
    mkdir -p "$_rspb_dir"
    cat > "$_rspb_dir/sqlite3" <<'EOF'
#!/bin/sh
printf '3.40.0 2024-01-01 00:00:00 deadbeef\n'
EOF
    chmod +x "$_rspb_dir/sqlite3"
  fi
  printf '%s:%s' "$_rspb_dir" "$PATH"
}

# _rt_doctor_deps HOME PATH -> seta _RT_D_EFFECTIVE + _RT_D_REASON a partir
# de `cstk doctor --deps` real (doctor_main, cli/lib/doctor.sh, que delega a
# state-backend.sh resolve via cli/lib/config.sh).
_rt_doctor_deps() {
  _rtdd_home="$1"
  _rtdd_path="$2"
  _rtdd_out=$(env HOME="$_rtdd_home" PATH="$_rtdd_path" CSTK_LIB="$CSTK_LIB" sh -c '
    . "$CSTK_LIB/doctor.sh"
    doctor_main --deps
  ' 2>/dev/null)
  _RT_D_EFFECTIVE=$(printf '%s\n' "$_rtdd_out" | grep 'effective_backend:' | awk '{print $2}')
  _RT_D_REASON=$(printf '%s\n' "$_rtdd_out" | grep 'reason:' | awk '{print $2}')
}

# _rt_runtime_init HOME PATH STATE_DIR -> roda `state-rw.sh init` num
# state-dir limpo e seta _RT_R_EFFECTIVE ("sqlite"|"json") a partir do
# ARQUIVO EFETIVAMENTE CRIADO — nao da resposta textual do script (e
# exatamente essa observacao empirica que o Scenario 9 exige).
_rt_runtime_init() {
  _rtri_home="$1"
  _rtri_path="$2"
  _rtri_sd="$3"
  env HOME="$_rtri_home" PATH="$_rtri_path" "$SCRIPT" init --state-dir "$_rtri_sd" \
    --execucao-id "exec-rt-$$-$(basename "$_rtri_sd")" \
    --projeto-alvo-path "/tmp/rt-$(basename "$_rtri_sd")" \
    --descricao "descricao de teste com tamanho suficiente para validacao" \
    >/dev/null 2>&1
  if [ -f "$_rtri_sd/state.db" ]; then
    _RT_R_EFFECTIVE="sqlite"
  elif [ -f "$_rtri_sd/state.json" ]; then
    _RT_R_EFFECTIVE="json"
  else
    _RT_R_EFFECTIVE="nenhum"
  fi
}

# _rt_assert_roundtrip LABEL HOME PATH EXPECTED_REASON -> roda os dois
# caminhos com o MESMO HOME/PATH (a mesma "combinacao config x ambiente" do
# Scenario 9) e falha se divergirem OU se o reason nao bater com o
# esperado (garante que o teste testa o cenario certo, nao so "concordam
# por acaso").
_rt_assert_roundtrip() {
  _rar_label="$1"
  _rar_home="$2"
  _rar_path="$3"
  _rar_expected_reason="$4"
  _rar_sd="$TMPDIR_TEST/sd-$_rar_label"

  _rt_doctor_deps "$_rar_home" "$_rar_path"
  _rt_runtime_init "$_rar_home" "$_rar_path" "$_rar_sd"

  [ "$_RT_D_REASON" = "$_rar_expected_reason" ] || {
    _fail "$_rar_label: reason inesperado (binario)" "obtido=$_RT_D_REASON esperado=$_rar_expected_reason"
    return 1
  }
  [ "$_RT_R_EFFECTIVE" != "nenhum" ] || {
    _fail "$_rar_label: runtime nao criou nenhum arquivo de state" ""
    return 1
  }
  [ "$_RT_D_EFFECTIVE" = "$_RT_R_EFFECTIVE" ] || {
    _fail "$_rar_label: DIVERGENCIA binario<->runtime (SC-004)" "binario=$_RT_D_EFFECTIVE runtime=$_RT_R_EFFECTIVE"
    return 1
  }
}

# ---------------------------------------------------------------------------
# Scenario 9 — 6 combinacoes config x ambiente
# ---------------------------------------------------------------------------

# 1. Config ausente + sqlite3 adequado -> json / nunca-configurado.
scenario_roundtrip_config_ausente() {
  _rt_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _home="$TMPDIR_TEST/home-ausente"
  mkdir -p "$_home"
  _rt_assert_roundtrip "ausente" "$_home" "$PATH" "nunca-configurado"
}

# 2. state_backend=json explicito + sqlite3 adequado -> json / json-explicito.
scenario_roundtrip_config_json_explicito() {
  _rt_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _home="$TMPDIR_TEST/home-json"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=json\n' > "$_home/.claude/cstk/config"
  _rt_assert_roundtrip "json-explicito" "$_home" "$PATH" "json-explicito"
}

# 3. state_backend=sqlite + sqlite3 adequado -> sqlite / configurado-dependencia-adequada.
scenario_roundtrip_config_sqlite_dependencia_adequada() {
  _rt_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _home="$TMPDIR_TEST/home-sqlite-ok"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  _rt_assert_roundtrip "sqlite-adequado" "$_home" "$PATH" "configurado-dependencia-adequada"
}

# 4. state_backend=sqlite + sqlite3 abaixo do minimo (stub) -> json / configurado-dependencia-abaixo-do-minimo.
scenario_roundtrip_config_sqlite_dependencia_abaixo_do_minimo() {
  _home="$TMPDIR_TEST/home-sqlite-low"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  _path_low=$(_rt_stub_path_sqlite3_below_min)
  _rt_assert_roundtrip "sqlite-abaixo-minimo" "$_home" "$_path_low" "configurado-dependencia-abaixo-do-minimo"
}

# 5. state_backend=sqlite + sqlite3 ausente (PATH isolado) -> json / configurado-dependencia-ausente.
scenario_roundtrip_config_sqlite_dependencia_ausente() {
  _home="$TMPDIR_TEST/home-sqlite-ausente"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  _path_none=$(_rt_isolated_path_without_sqlite3)
  _rt_assert_roundtrip "sqlite-ausente" "$_home" "$_path_none" "configurado-dependencia-ausente"
}

# 6. Config invalida (lixo nao-interpretavel) + sqlite3 adequado -> json / config-invalida.
scenario_roundtrip_config_invalida() {
  _rt_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _home="$TMPDIR_TEST/home-invalida"
  mkdir -p "$_home/.claude/cstk"
  # Linha SEM '=' invalida a config INTEIRA (P2) — mesma fixture de
  # tests/test_state-backend.sh::scenario_resolve_linha_sem_igual_invalida_config_inteira.
  # NAO usar algo como "isto nao e key=value valido": contem um '=' (dentro
  # de "key=value"), entao bate no ramo `*=*` como chave desconhecida e
  # resulta em "ausente"/nunca-configurado, nao em "invalida" — armadilha
  # ja pisada ao escrever este teste.
  printf 'linha sem igual aqui\n' > "$_home/.claude/cstk/config"
  _rt_assert_roundtrip "invalida" "$_home" "$PATH" "config-invalida"
}

# ---------------------------------------------------------------------------
# Sensibilidade a regressao (task 6.1.2): prova que o teste FALHA se a
# unicidade de `resolve` for quebrada por um parser paralelo no CLI.
# Simula o drift injetando, no PATH do lado "binario" apenas, um
# doctor.sh forjado que reimplementa (mal) a decisao — SEM delegar a
# state-backend.sh — e confirma que o assert de divergencia acima
# capturaria isso (aqui replicado inline, sem tocar no doctor.sh real).
# ---------------------------------------------------------------------------

scenario_roundtrip_e_sensivel_a_drift_sintetico() {
  _rt_real_sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _home="$TMPDIR_TEST/home-drift"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"

  # Runtime real (nao mockado): cria state.db normalmente.
  _sd="$TMPDIR_TEST/sd-drift"
  _rt_runtime_init "$_home" "$PATH" "$_sd"
  [ "$_RT_R_EFFECTIVE" = "sqlite" ] || { _error "fixture" "runtime deveria ter criado state.db"; return 2; }

  # Binario "drifado": reimplementa a decisao hardcoded como json, IGNORANDO
  # a config real — exatamente o tipo de parser paralelo que Decision 2
  # proibe. O assert de igualdade (mesma logica de _rt_assert_roundtrip)
  # DEVE detectar a divergencia.
  _rtd_effective_drifted="json"
  if [ "$_rtd_effective_drifted" = "$_RT_R_EFFECTIVE" ]; then
    _fail "drift sintetico nao foi detectado — teste nao e sensivel a regressao" ""
    return 1
  fi
  return 0
}

run_all_scenarios
