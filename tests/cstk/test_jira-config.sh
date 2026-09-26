#!/bin/sh
# test_jira-config.sh — cobre plugins/cstk-jira/scripts/jira-config.sh
# (cstk-jira, FASE 2 tarefa 2.1).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity ProjectConfig, Entity
#      Credential; docs/specs/cstk-jira/contracts/plugin-scripts.md
#      `jira-config.sh`; tasks.md 2.1.1-2.1.5.
#
# Invariantes cobertos:
#   JC-1  get: config ausente -> exit 3 (FR-017)
#   JC-2  get: chave existente -> exit 0 + valor correto em stdout
#   JC-3  get: chave ausente do arquivo -> exit 1
#   JC-4  validate: config valido -> exit 0
#   JC-5  validate: config ausente -> exit 3
#   JC-6  validate: site_host com esquema/porta/path -> exit 1
#   JC-7  validate: status_fail == status_pass -> exit 1, diagnostico cita ambos
#   JC-8  validate: campo obrigatorio ausente -> exit 1, diagnostico cita o campo
#   JC-9  credential-check: arquivo ausente -> exit 4
#   JC-10 credential-check: permissao mais aberta que 0600 -> exit 4, NUNCA
#         imprime o conteudo do arquivo
#   JC-11 credential-check: permissao exata 0600 -> exit 0

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-config.sh"

# _write_valid_config: cria .claude/cstk-jira/config valido em $TMPDIR_TEST/.
_write_valid_config() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  cat > "$TMPDIR_TEST/.claude/cstk-jira/config" <<'EOF'
# config de teste
config_version=1
site_host=example.atlassian.net
project_key=CSTK
board_id=42
issue_type_epic=10000
issue_type_task=10001
issue_type_subtask=10002
status_pending=To Do
status_in_progress=In Progress
status_pass=Done
status_fail=Failed
sync_autonomous=on
EOF
}

scenario_get_config_ausente_exit3() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 3 "$SCRIPT" get site_host || return 1
}

scenario_get_chave_existente_retorna_valor() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  assert_exit 0 "$SCRIPT" get site_host || return 1
  assert_stdout_contains "example.atlassian.net" || return 1
}

scenario_get_chave_ausente_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  assert_exit 1 "$SCRIPT" get chave_que_nao_existe || return 1
}

scenario_validate_config_valido_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_config_ausente_exit3() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 3 "$SCRIPT" validate || return 1
}

scenario_validate_site_host_com_esquema_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  sed 's#site_host=.*#site_host=https://example.atlassian.net/#' \
    "$TMPDIR_TEST/.claude/cstk-jira/config" > "$TMPDIR_TEST/cfg.tmp"
  mv "$TMPDIR_TEST/cfg.tmp" "$TMPDIR_TEST/.claude/cstk-jira/config"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "site_host invalido" || return 1
}

scenario_validate_site_host_com_porta_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  sed 's#site_host=.*#site_host=example.atlassian.net:443#' \
    "$TMPDIR_TEST/.claude/cstk-jira/config" > "$TMPDIR_TEST/cfg.tmp"
  mv "$TMPDIR_TEST/cfg.tmp" "$TMPDIR_TEST/.claude/cstk-jira/config"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "site_host invalido" || return 1
}

scenario_validate_status_fail_igual_status_pass_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  sed 's#status_fail=.*#status_fail=Done#' \
    "$TMPDIR_TEST/.claude/cstk-jira/config" > "$TMPDIR_TEST/cfg.tmp"
  mv "$TMPDIR_TEST/cfg.tmp" "$TMPDIR_TEST/.claude/cstk-jira/config"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "status_fail e status_pass" || return 1
}

scenario_validate_campo_obrigatorio_ausente_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  grep -v '^board_id=' "$TMPDIR_TEST/.claude/cstk-jira/config" > "$TMPDIR_TEST/cfg.tmp"
  mv "$TMPDIR_TEST/cfg.tmp" "$TMPDIR_TEST/.claude/cstk-jira/config"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "board_id" || return 1
}

scenario_credential_check_ausente_exit4() {
  _home="$TMPDIR_TEST/home-ausente"
  mkdir -p "$_home"
  assert_exit 4 env HOME="$_home" "$SCRIPT" credential-check || return 1
}

scenario_credential_check_permissao_aberta_exit4_nunca_imprime_conteudo() {
  _home="$TMPDIR_TEST/home-aberto"
  mkdir -p "$_home/.config/cstk-jira"
  printf 'email=alguem@example.com\napi_token=SEGREDO_NUNCA_DEVE_APARECER\n' \
    > "$_home/.config/cstk-jira/credentials"
  chmod 644 "$_home/.config/cstk-jira/credentials"
  assert_exit 4 env HOME="$_home" "$SCRIPT" credential-check || return 1
  assert_stdout_not_contains "SEGREDO_NUNCA_DEVE_APARECER" || return 1
  assert_stderr_contains "permissao insegura" || return 1
  case "${_CAPTURED_STDERR:-}" in
    *SEGREDO_NUNCA_DEVE_APARECER*)
      _fail "credential_never_printed" "stderr vazou o conteudo da credencial"
      return 1
      ;;
  esac
}

scenario_credential_check_permissao_0600_exit0() {
  _home="$TMPDIR_TEST/home-ok"
  mkdir -p "$_home/.config/cstk-jira"
  printf 'email=alguem@example.com\napi_token=abc123\n' \
    > "$_home/.config/cstk-jira/credentials"
  chmod 600 "$_home/.config/cstk-jira/credentials"
  assert_exit 0 env HOME="$_home" "$SCRIPT" credential-check || return 1
}

run_all_scenarios
