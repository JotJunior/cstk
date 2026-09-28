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
#   JC-12 resolve-path: config local presente -> imprime path ABSOLUTO do
#         cwd, exit 0 (r02 FASE 20 tarefa 20.1.1)
#   JC-13 resolve-path: sem config local, worktree principal com config ->
#         imprime o path ABSOLUTO da principal (git-common-dir); NENHUMA
#         escrita ocorre la (task 20.1.4)
#   JC-14 resolve-path: sem config nos dois lugares -> exit 3
#   JC-15 resolve-path: sem git no PATH e sem config local -> exit 3, SEM
#         tentar o fallback (fora de repo git o resultado e o mesmo)
#   JC-16 get/validate tambem resolvem via worktree principal (nao duplicam
#         a regra de resolve-path — task 20.1.2/plugin-scripts.md)
#   JC-17 mutation: reverter resolve-path para GRAVAR no path resolvido da
#         principal (em vez de tratar como somente-leitura) faz o teste de
#         "nenhuma escrita na principal" falhar (task 20.1.5)

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

# _jc_setup_worktree: cria um repo git minimo em $TMPDIR_TEST/main (commit
# inicial SEM ProjectConfig, para que o config nao seja rastreado/herdado
# pelo checkout do worktree) e um worktree linkado em $TMPDIR_TEST/wt.
# Identidade LOCAL do repo (mesmo racional de test_parallel-launch.sh::
# _pl_git_repo — CI nao tem ~/.gitconfig). Retorna (via variaveis globais
# do chamador) nada; o chamador usa $TMPDIR_TEST/main e $TMPDIR_TEST/wt.
_jc_setup_worktree() {
  mkdir -p "$TMPDIR_TEST/main"
  (
    cd "$TMPDIR_TEST/main" || exit 1
    git init -q .
    git config user.email "test@test.local"
    git config user.name "cstk test"
    printf 'x\n' > README.md
    git add README.md
    git commit -q -m init
    git worktree add -q -b jc-test-branch "$TMPDIR_TEST/wt" HEAD
  )
}

# _jc_path_without_git: PATH com APENAS um diretorio de shims contendo
# symlinks para os comandos que o SUT/harness precisam — `git`
# deliberadamente de fora (mesmo racional de test_parallel-launch.sh::
# _pl_path_without_tmux; feedback_test_path_stub_cannot_hide_usrbin: so um
# allowlist explicito garante ausencia — prefixar PATH nao esconde um
# binario que tambem exista em /usr/bin via outro segmento).
_jc_path_without_git() {
  _shim="$TMPDIR_TEST/nogit-bin"
  mkdir -p "$_shim"
  for _c in sh env sed awk grep mkdir rm cat mktemp chmod ln find sort head tail tr wc cut dirname basename mv; do
    _p=$(command -v "$_c" 2>/dev/null) || continue
    [ -e "$_shim/$_c" ] || ln -s "$_p" "$_shim/$_c" 2>/dev/null || :
  done
  printf '%s' "$_shim"
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

# ==== validate: enums/allowlists r02 (data-model.md ProjectConfig
# "Validation rules (novas)" — r02 FASE 21 tarefa 21.4) ====
#
#   JC-18..24 milestone_mode/labels_enabled/fix_versions_on_subtask/
#             links_enabled/project_create: 1 cenario por chave (valor
#             valido, invalido, ausente = valido/default)
#   JC-25..27 milestone_release: SEC-6 valido/invalido/ausente
#   JC-28..30 link_type_id: SEC-1 valido/invalido/ausente
#   JC-31     mutation: remover a checagem de UM enum (milestone_mode)
#             MUST fazer o teste de invalido falhar (script mutante aceita
#             valor fora do enum)

# _append_config_line: acrescenta KEY=VALUE ao config valido de teste
# (config JA escrito por _write_valid_config).
_append_config_line() {
  printf '%s\n' "$1" >> "$TMPDIR_TEST/.claude/cstk-jira/config"
}

scenario_validate_milestone_mode_valido_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "milestone_mode=off"
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_milestone_mode_invalido_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "milestone_mode=Auto"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "milestone_mode" || return 1
}

scenario_validate_milestone_mode_ausente_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_labels_enabled_valido_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "labels_enabled=off"
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_labels_enabled_invalido_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "labels_enabled=yes"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "labels_enabled" || return 1
}

scenario_validate_fix_versions_on_subtask_valido_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "fix_versions_on_subtask=on"
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_fix_versions_on_subtask_invalido_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "fix_versions_on_subtask=maybe"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "fix_versions_on_subtask" || return 1
}

scenario_validate_links_enabled_valido_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "links_enabled=off"
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_links_enabled_invalido_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "links_enabled=1"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "links_enabled" || return 1
}

scenario_validate_project_create_valido_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "project_create=never"
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_project_create_invalido_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "project_create=always"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "project_create" || return 1
}

scenario_validate_milestone_release_valido_sec6_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "milestone_release=1.2.3"
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_milestone_release_invalido_sec6_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "milestone_release=../etc"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "milestone_release" || return 1
}

scenario_validate_milestone_release_ausente_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_link_type_id_valido_sec1_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "link_type_id=10003"
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_validate_link_type_id_invalido_sec1_exit1() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "link_type_id=10003;drop"
  assert_exit 1 "$SCRIPT" validate || return 1
  assert_stderr_contains "link_type_id" || return 1
}

scenario_validate_link_type_id_ausente_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  assert_exit 0 "$SCRIPT" validate || return 1
}

# JS-mutation 21.4.2: reverter a checagem de UM enum (milestone_mode)
# MUST fazer este teste falhar — o mutante aceita valor fora do enum.
scenario_mutation_21_4_2_remove_enum_check_fails() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  _append_config_line "milestone_mode=Auto"

  _mut="$TMPDIR_TEST/jira-config.sh.mut"
  cp "$SCRIPT" "$_mut"
  grep -qF '_jc_check_enum milestone_mode "$_jcv_file" auto off' "$_mut" \
    || { _fail "mutant_stale" "anchor da checagem de milestone_mode nao encontrado (script mudou?)"; return 1; }
  sed 's/_jc_check_enum milestone_mode "\$_jcv_file" auto off//' \
    "$_mut" > "$_mut.tmp" && mv "$_mut.tmp" "$_mut"
  chmod +x "$_mut"

  # controle: original REJEITA (exit 1).
  assert_exit 1 "$SCRIPT" validate || return 1

  # mutante: sem a checagem, ACEITA o valor invalido (exit 0) — a
  # regressao que este teste MUST detectar.
  _mut_exit=0
  "$_mut" validate >/dev/null 2>&1 || _mut_exit=$?
  [ "$_mut_exit" = "0" ] \
    || { _fail "mutant_no_effect" "esperado regressao: mutante deveria aceitar milestone_mode invalido (exit 0), obtido $_mut_exit"; return 1; }
  return 0
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

# ==== resolve-path (r02 FASE 20 tarefa 20.1) ====

scenario_resolve_path_config_local_exit0() {
  cd "$TMPDIR_TEST" || return 1
  _write_valid_config
  assert_exit 0 "$SCRIPT" resolve-path || return 1
  assert_stdout_contains ".claude/cstk-jira/config" || return 1
  # SEMPRE absoluto (20.1.2 depende disso — chamadores resolvem de um
  # subshell com cwd diferente do processo pai).
  case "$_CAPTURED_STDOUT" in
    /*) : ;;
    *) _fail "resolve_path_absoluto" "esperado path absoluto, obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_resolve_path_worktree_principal_fallback_sem_escrita() {
  _jc_setup_worktree
  mkdir -p "$TMPDIR_TEST/main/.claude/cstk-jira"
  printf 'config_version=1\nsite_host=principal.atlassian.net\n' \
    > "$TMPDIR_TEST/main/.claude/cstk-jira/config"
  _before=$(cat "$TMPDIR_TEST/main/.claude/cstk-jira/config")

  cd "$TMPDIR_TEST/wt" || return 1
  assert_exit 0 "$SCRIPT" resolve-path || return 1
  assert_stdout_contains "$TMPDIR_TEST/main/.claude/cstk-jira/config" || return 1

  # get delega a MESMA resolucao (nao duplica a regra — JC-16)
  assert_exit 0 "$SCRIPT" get site_host || return 1
  assert_stdout_contains "principal.atlassian.net" || return 1

  # nenhuma escrita ocorreu na principal nem localmente no worktree
  _after=$(cat "$TMPDIR_TEST/main/.claude/cstk-jira/config")
  [ "$_before" = "$_after" ] \
    || { _fail "resolve_path_readonly" "config da worktree principal foi mutado"; return 1; }
  [ -e "$TMPDIR_TEST/wt/.claude" ] \
    && { _fail "resolve_path_no_local_write" "resolve-path/get criaram .claude no worktree sem config local"; return 1; }
  return 0
}

scenario_resolve_path_validate_via_worktree_principal() {
  _jc_setup_worktree
  mkdir -p "$TMPDIR_TEST/main/.claude/cstk-jira"
  cat > "$TMPDIR_TEST/main/.claude/cstk-jira/config" <<'EOF'
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
  cd "$TMPDIR_TEST/wt" || return 1
  assert_exit 0 "$SCRIPT" validate || return 1
}

scenario_resolve_path_ausente_nos_dois_exit3() {
  _jc_setup_worktree
  cd "$TMPDIR_TEST/wt" || return 1
  assert_exit 3 "$SCRIPT" resolve-path || return 1
}

scenario_resolve_path_sem_git_no_path_exit3() {
  _jc_setup_worktree
  mkdir -p "$TMPDIR_TEST/main/.claude/cstk-jira"
  printf 'config_version=1\nsite_host=principal.atlassian.net\n' \
    > "$TMPDIR_TEST/main/.claude/cstk-jira/config"
  cd "$TMPDIR_TEST/wt" || return 1
  _fake=$(_jc_path_without_git)
  # sanity: git realmente inalcancavel sob este PATH (nao um falso-negativo
  # por prefixar em vez de allowlist — feedback_test_path_stub_cannot_hide_usrbin)
  env PATH="$_fake" sh -c 'command -v git' >/dev/null 2>&1 \
    && { _fail "shim_stale" "git ainda alcancavel sob o PATH reduzido"; return 1; }
  assert_exit 3 env PATH="$_fake" "$SCRIPT" resolve-path || return 1
}

# ==== 20.1.5: mutation — reverter resolve-path para GRAVAR na principal ====

scenario_mutation_20_1_5_resolve_path_grava_na_principal() {
  _jc_setup_worktree
  mkdir -p "$TMPDIR_TEST/main/.claude/cstk-jira"
  printf 'config_version=1\nsite_host=principal.atlassian.net\n' \
    > "$TMPDIR_TEST/main/.claude/cstk-jira/config"
  _before=$(cat "$TMPDIR_TEST/main/.claude/cstk-jira/config")

  # controle: original nao muta o config da principal.
  (cd "$TMPDIR_TEST/wt" && "$SCRIPT" resolve-path) >/dev/null 2>&1
  _after_control=$(cat "$TMPDIR_TEST/main/.claude/cstk-jira/config")
  [ "$_before" = "$_after_control" ] \
    || { _fail "controle_readonly" "original ja mutava o config da principal"; return 1; }

  # mutante: apos confirmar a existencia do config da principal, GRAVA nele
  # em vez de so ler (regressao que 20.1.5 exige detectar).
  _mut="$TMPDIR_TEST/jira-config.sh.mut"
  cp "$SCRIPT" "$_mut"
  grep -qF '[ -f "$_jcrc_principal_config" ] || return 1' "$_mut" \
    || { _fail "mutant_stale" "anchor de resolve-path nao encontrado (script mudou?)"; return 1; }
  sed 's@\[ -f "\$_jcrc_principal_config" \] || return 1@[ -f "$_jcrc_principal_config" ] || return 1; printf "MUTANT-WRITE\\n" >> "$_jcrc_principal_config"@' \
    "$_mut" > "$_mut.tmp" && mv "$_mut.tmp" "$_mut"
  grep -qF 'MUTANT-WRITE' "$_mut" \
    || { _fail "mutant_apply" "sed nao aplicou a mutacao em resolve-path"; return 1; }
  chmod +x "$_mut"

  (cd "$TMPDIR_TEST/wt" && "$_mut" resolve-path) >/dev/null 2>&1
  _after_mutant=$(cat "$TMPDIR_TEST/main/.claude/cstk-jira/config")
  [ "$_before" != "$_after_mutant" ] \
    || { _fail "mutant_no_effect" "esperado regressao: mutante deveria ter gravado na principal, mas nao gravou"; return 1; }
  return 0
}

run_all_scenarios
