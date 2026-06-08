#!/bin/sh
# test_plugin-common.sh — cobre cli/lib/plugin-common.sh
#
# Contrato:
#   plugin_validate_name   — regex FR-002
#   plugin_resolve_url     — prioridade env > ~/.cstk/config > hardcoded
#   plugin_store_dir       — ~/.claude/cstk/plugins/<name>
#   plugin_registry_*      — CRUD do registry.json (jq + fallback)
#   plugin_is_installed    — registry + diretorio
#   plugin_compute_bundle_checksum — SHA-256 excluindo manifest
#   plugin_verify_manifest — shape validation (6 campos)
#   plugin_verify_bundle_checksum  — compara checksum
#   plugin_resolve_skill_dir       — path-prepending FR-014

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# ---------------------------------------------------------------------------
# 2.1 Validacao de nome
# ---------------------------------------------------------------------------

scenario_validate_name_valido() {
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_validate_name codex"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "validate_name_valido" "exit $_CAPTURED_EXIT para nome valido 'codex'"
    return 1
  fi
}

scenario_validate_name_valido_com_numero() {
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_validate_name my-plugin-2"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "validate_name_valido_com_numero" "exit $_CAPTURED_EXIT para 'my-plugin-2'"
    return 1
  fi
}

scenario_validate_name_invalido_uppercase() {
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_validate_name Codex"
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "validate_name_invalido_uppercase" "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_validate_name_invalido_traversal() {
  capture sh -c '. '"$CSTK_LIB"'/plugin-common.sh && plugin_validate_name "../evil"'
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "validate_name_invalido_traversal" "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_validate_name_invalido_underline() {
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_validate_name my_plugin"
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "validate_name_invalido_underline" "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_validate_name_invalido_comeca_numero() {
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_validate_name 2plugin"
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "validate_name_invalido_comeca_numero" "exit esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_validate_name_invalido_longo() {
  # 65 chars comecando com 'a': invalido (max 64)
  # Construir string de 65 'a' de forma portavel
  _n=$(printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')  # 66 chars
  _n=$(printf '%s' "$_n" | cut -c1-65)
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_validate_name '$_n'"
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "validate_name_invalido_longo" "exit esperado 2 para nome de 65 chars, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2.1 Resolucao de URL
# ---------------------------------------------------------------------------

scenario_resolve_url_default() {
  _home="$TMPDIR_TEST/home"
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_resolve_url codex"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "resolve_url_default exit" "$_CAPTURED_EXIT"
    return 1
  fi
  if [ "$_CAPTURED_STDOUT" != "https://github.com/JotJunior/cstk-plugin-codex" ]; then
    _fail "resolve_url_default valor" "obtido: $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_resolve_url_env_override() {
  _home="$TMPDIR_TEST/home"
  capture sh -c "HOME='$_home' CSTK_PLUGIN_REGISTRY='https://example.com/org' . $CSTK_LIB/plugin-common.sh && plugin_resolve_url myplug"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "resolve_url_env exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ "$_CAPTURED_STDOUT" != "https://example.com/org/cstk-plugin-myplug" ]; then
    _fail "resolve_url_env valor" "obtido: $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_resolve_url_config_file() {
  _home="$TMPDIR_TEST/home2"
  mkdir -p "$_home/.cstk"
  printf 'registry=https://myregistry.example.com/plugins\n' > "$_home/.cstk/config"
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_resolve_url codex"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "resolve_url_config exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  if [ "$_CAPTURED_STDOUT" != "https://myregistry.example.com/plugins/cstk-plugin-codex" ]; then
    _fail "resolve_url_config valor" "obtido: $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_resolve_url_env_tem_prioridade_sobre_config() {
  _home="$TMPDIR_TEST/home3"
  mkdir -p "$_home/.cstk"
  printf 'registry=https://config.example.com/\n' > "$_home/.cstk/config"
  capture sh -c "HOME='$_home' CSTK_PLUGIN_REGISTRY='https://env.example.com/' . $CSTK_LIB/plugin-common.sh && plugin_resolve_url test"
  if [ "$_CAPTURED_STDOUT" != "https://env.example.com/cstk-plugin-test" ]; then
    _fail "resolve_url_prioridade" "env deve ter prioridade; obtido: $_CAPTURED_STDOUT"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2.1 Store dir
# ---------------------------------------------------------------------------

scenario_store_dir() {
  _home="$TMPDIR_TEST/home"
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_store_dir codex"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "store_dir exit" "$_CAPTURED_EXIT"
    return 1
  fi
  _expected="$_home/.claude/cstk/plugins/codex"
  if [ "$_CAPTURED_STDOUT" != "$_expected" ]; then
    _fail "store_dir valor" "obtido: $_CAPTURED_STDOUT; esperado: $_expected"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2.2 Registry CRUD
# ---------------------------------------------------------------------------

scenario_registry_init_cria_se_nao_existe() {
  _home="$TMPDIR_TEST/home4"
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_init"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_init exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  _reg="$_home/.claude/cstk/plugins/registry.json"
  if [ ! -f "$_reg" ]; then
    _fail "registry_init arquivo" "registry.json nao criado em $_reg"
    return 1
  fi
  if ! grep -q '"schema_version"' "$_reg"; then
    _fail "registry_init conteudo" "schema_version ausente"
    return 1
  fi
}

scenario_registry_init_idempotente() {
  _home="$TMPDIR_TEST/home5"
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_init" >/dev/null 2>&1
  _reg="$_home/.claude/cstk/plugins/registry.json"
  printf '{"schema_version":1,"plugins":[{"name":"test","version":"1.0.0","type":"llm","installed_at":"2026-01-01T00:00:00Z","bundle_sha256":"abcd"}]}\n' > "$_reg"
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_init" >/dev/null 2>&1
  if ! grep -q '"test"' "$_reg"; then
    _fail "registry_init_idempotente" "segunda chamada sobrescreveu o registry"
    return 1
  fi
}

scenario_registry_upsert_e_get() {
  _home="$TMPDIR_TEST/home6"
  _sha=$(printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_upsert codex 1.2.0 llm '$_sha'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_upsert exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_get codex"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_get exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *codex*1.2.0*llm*) : ;;
    *)
      _fail "registry_get conteudo" "TSV nao contem campos esperados: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
}

scenario_registry_get_ausente_exit1() {
  _home="$TMPDIR_TEST/home7"
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_init" >/dev/null 2>&1
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_get naoexiste"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "registry_get_ausente" "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_registry_upsert_sobrescreve() {
  _home="$TMPDIR_TEST/home8"
  _sha1=$(printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  _sha2=$(printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_upsert codex 1.0.0 llm '$_sha1'" >/dev/null 2>&1
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_upsert codex 1.1.0 llm '$_sha2'" >/dev/null 2>&1
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_get codex"
  case "$_CAPTURED_STDOUT" in
    *1.1.0*) : ;;
    *)
      _fail "registry_upsert_sobrescreve" "versao 1.1.0 nao encontrada: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
}

scenario_registry_remove_existente() {
  _home="$TMPDIR_TEST/home9"
  _sha=$(printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_upsert codex 1.0.0 llm '$_sha'" >/dev/null 2>&1
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_remove codex"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_remove exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_get codex"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "registry_remove: ainda presente" "exit esperado 1 apos remocao, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_registry_remove_ausente_exit1() {
  _home="$TMPDIR_TEST/home10"
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_init" >/dev/null 2>&1
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_remove naoexiste"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "registry_remove_ausente" "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_registry_list_vazia() {
  _home="$TMPDIR_TEST/home11"
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_init" >/dev/null 2>&1
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_list"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_list_vazia exit" "$_CAPTURED_EXIT"
    return 1
  fi
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "registry_list_vazia stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_registry_list_multiplos() {
  _home="$TMPDIR_TEST/home12"
  _sha=$(printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_upsert codex 1.0.0 llm '$_sha'" >/dev/null 2>&1
  sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_upsert dotnet 2.0.0 lang '$_sha'" >/dev/null 2>&1
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_list"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_list_multiplos exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *codex*) : ;;
    *)
      _fail "registry_list_multiplos" "codex ausente: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDOUT" in
    *dotnet*) : ;;
    *)
      _fail "registry_list_multiplos" "dotnet ausente: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Fallback sem jq (PATH com stub que falha)
# ---------------------------------------------------------------------------

scenario_registry_upsert_fallback_sem_jq() {
  _home="$TMPDIR_TEST/home13"
  _stubdir="$TMPDIR_TEST/stub_bin"
  mkdir -p "$_stubdir"
  printf '#!/bin/sh\nexit 127\n' > "$_stubdir/jq"
  chmod +x "$_stubdir/jq"
  _sha=$(printf 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
  capture env PATH="$_stubdir:$PATH" sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_upsert myplugin 0.1.0 llm '$_sha'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_upsert_fallback_sem_jq" "exit $_CAPTURED_EXIT sem jq; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  capture env PATH="$_stubdir:$PATH" sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_registry_get myplugin"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "registry_get_fallback_sem_jq" "exit $_CAPTURED_EXIT sem jq; stderr=$_CAPTURED_STDERR"
    return 1
  fi
  case "$_CAPTURED_STDOUT" in
    *myplugin*) : ;;
    *)
      _fail "registry_get_fallback_sem_jq conteudo" "obtido: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 2.3 Checksum e integridade
# ---------------------------------------------------------------------------

scenario_compute_bundle_checksum_exclui_manifest() {
  _bundle="$TMPDIR_TEST/bundle14"
  mkdir -p "$_bundle/skills/specify"
  printf 'skill content\n' > "$_bundle/skills/specify/SKILL.md"
  printf '{"name":"test","sha256":"deadbeef","version":"1.0.0"}\n' > "$_bundle/plugin-manifest.json"

  _h1=$(sh -c ". $CSTK_LIB/plugin-common.sh && plugin_compute_bundle_checksum '$_bundle'")
  # Mudar conteudo do manifest — hash nao deve mudar
  printf '{"name":"test","sha256":"changed","version":"2.0.0"}\n' > "$_bundle/plugin-manifest.json"
  _h2=$(sh -c ". $CSTK_LIB/plugin-common.sh && plugin_compute_bundle_checksum '$_bundle'")

  if [ "$_h1" != "$_h2" ]; then
    _fail "compute_bundle_checksum_exclui_manifest" "hash mudou ao alterar manifest (nao deveria): $_h1 vs $_h2"
    return 1
  fi

  # Mudar conteudo do skill — hash DEVE mudar
  printf 'skill content changed\n' > "$_bundle/skills/specify/SKILL.md"
  _h3=$(sh -c ". $CSTK_LIB/plugin-common.sh && plugin_compute_bundle_checksum '$_bundle'")
  if [ "$_h1" = "$_h3" ]; then
    _fail "compute_bundle_checksum_sensivel_a_skill" "hash nao mudou ao alterar skill content"
    return 1
  fi
}

scenario_verify_manifest_valido() {
  _bundle="$TMPDIR_TEST/bundle_mf_ok"
  mkdir -p "$_bundle"
  _sha=$(printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  printf '{"name":"codex","version":"1.0.0","type":"llm","schema_version":1,"sha256":"%s","skills":["specify"]}\n' \
    "$_sha" > "$_bundle/plugin-manifest.json"

  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_verify_manifest '$_bundle'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "verify_manifest_valido exit" "$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_verify_manifest_ausente_exit1() {
  _bundle="$TMPDIR_TEST/bundle_mf_absent"
  mkdir -p "$_bundle"
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_verify_manifest '$_bundle'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "verify_manifest_ausente" "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_verify_manifest_sha256_curto_exit1() {
  _bundle="$TMPDIR_TEST/bundle_mf_bad_sha"
  mkdir -p "$_bundle"
  printf '{"name":"codex","version":"1.0.0","type":"llm","schema_version":1,"sha256":"tooshort","skills":[]}\n' \
    > "$_bundle/plugin-manifest.json"
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_verify_manifest '$_bundle'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "verify_manifest_sha256_curto" "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_verify_manifest_type_invalido_exit1() {
  _bundle="$TMPDIR_TEST/bundle_mf_bad_type"
  mkdir -p "$_bundle"
  _sha=$(printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  printf '{"name":"codex","version":"1.0.0","type":"invalid_type","schema_version":1,"sha256":"%s","skills":[]}\n' \
    "$_sha" > "$_bundle/plugin-manifest.json"
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_verify_manifest '$_bundle'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "verify_manifest_type_invalido" "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_verify_bundle_checksum_match() {
  _bundle="$TMPDIR_TEST/bundle_cs_ok"
  mkdir -p "$_bundle/skills/specify"
  printf 'content\n' > "$_bundle/skills/specify/SKILL.md"
  _sha=$(sh -c ". $CSTK_LIB/plugin-common.sh && plugin_compute_bundle_checksum '$_bundle'")
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_verify_bundle_checksum '$_bundle' '$_sha'"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "verify_bundle_checksum_match" "exit $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

scenario_verify_bundle_checksum_mismatch() {
  _bundle="$TMPDIR_TEST/bundle_cs_bad"
  mkdir -p "$_bundle/skills/specify"
  printf 'content\n' > "$_bundle/skills/specify/SKILL.md"
  _fake_sha=$(printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
  capture sh -c ". $CSTK_LIB/plugin-common.sh && plugin_verify_bundle_checksum '$_bundle' '$_fake_sha'"
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "verify_bundle_checksum_mismatch" "exit esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *mismatch*) : ;;
    *)
      _fail "verify_bundle_checksum_mismatch msg" "mensagem de mismatch ausente: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

scenario_degradacao_sem_sha256() {
  # Sem sha256sum nem shasum: a verificacao de integridade falha graciosamente.
  # Comportamento: plugin_compute_bundle_checksum retorna string vazia (pipe
  # sha256sum|awk mascara o exit code de sha256sum). Em seguida,
  # plugin_verify_bundle_checksum compara "" != <expected_real_sha256> => mismatch
  # => exit 1. Isso garante que o sistema NAO instala silenciosamente (Scenario 8).
  _bundle="$TMPDIR_TEST/bundle_no_sha"
  mkdir -p "$_bundle/skills"
  printf 'x\n' > "$_bundle/skills/s.txt"

  _stubdir="$TMPDIR_TEST/stub_nosha"
  mkdir -p "$_stubdir"
  for _cmd in sha256sum shasum; do
    printf '#!/bin/sh\nexit 127\n' > "$_stubdir/$_cmd"
    chmod +x "$_stubdir/$_cmd"
  done

  # Com sha256 ausente, o checksum computado sera vazio ou invalido.
  # Um checksum real nao vai casar com ele => verify_bundle_checksum deve falhar.
  _real_sha=$(sh -c ". $CSTK_LIB/plugin-common.sh && plugin_compute_bundle_checksum '$_bundle'")

  # Verificar: com os stubs, verify_bundle_checksum(<dir>, <sha_real>) deve falhar.
  # O <sha_real> calculado com sha256sum real sera diferente do vazio/invalido dos stubs.
  capture env PATH="$_stubdir:$PATH" \
    sh -c ". $CSTK_LIB/plugin-common.sh && plugin_verify_bundle_checksum '$_bundle' '$_real_sha'"
  if [ "$_CAPTURED_EXIT" = "0" ]; then
    _fail "degradacao_sem_sha256" "sem sha256sum, verify deveria falhar mas saiu com 0"
    return 1
  fi
  # O sistema nao instalou silenciosamente — verificacao falhou como esperado.
}

# ---------------------------------------------------------------------------
# 2.4 Resolucao de skill (path-prepending)
# ---------------------------------------------------------------------------

scenario_resolve_skill_claude_bypass() {
  _home="$TMPDIR_TEST/home17"
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_resolve_skill_dir claude specify"
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "resolve_skill_claude exit" "$_CAPTURED_EXIT"
    return 1
  fi
  _expected="$_home/.claude/skills/specify"
  if [ "$_CAPTURED_STDOUT" != "$_expected" ]; then
    _fail "resolve_skill_claude valor" "obtido: $_CAPTURED_STDOUT; esperado: $_expected"
    return 1
  fi
}

scenario_resolve_skill_plugin_presente() {
  _home="$TMPDIR_TEST/home18"
  mkdir -p "$_home/.claude/cstk/plugins/codex/skills/specify"
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_resolve_skill_dir codex specify"
  _expected="$_home/.claude/cstk/plugins/codex/skills/specify"
  if [ "$_CAPTURED_STDOUT" != "$_expected" ]; then
    _fail "resolve_skill_plugin_presente" "obtido: $_CAPTURED_STDOUT; esperado: $_expected"
    return 1
  fi
}

scenario_resolve_skill_plugin_sem_skill_fallback_core() {
  _home="$TMPDIR_TEST/home19"
  mkdir -p "$_home/.claude/cstk/plugins/codex/skills/specify"
  capture sh -c "HOME='$_home' . $CSTK_LIB/plugin-common.sh && plugin_resolve_skill_dir codex plan"
  _expected="$_home/.claude/skills/plan"
  if [ "$_CAPTURED_STDOUT" != "$_expected" ]; then
    _fail "resolve_skill_fallback_core" "obtido: $_CAPTURED_STDOUT; esperado: $_expected"
    return 1
  fi
}

run_all_scenarios
