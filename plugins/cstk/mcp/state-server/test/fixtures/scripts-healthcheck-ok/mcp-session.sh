#!/bin/sh
# Fixture: simula mcp-session.sh resolve --state-dir (modo container,
# dec-081) para o teste de integracao end-to-end de healthcheck.ts.
set -eu
_token=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --token) _token=$2; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$_token" != "healthcheck-test-token" ]; then
  printf 'mcp-session: resolve: SESSION_MISMATCH (fixture)\n' >&2
  exit 3
fi
printf 'state_dir=%s\n' "${CSTK_MCP_STATE_DIR:-/data/state}"
printf 'execution_kind=feature-00c\n'
printf 'short_name=state-mcp-server\n'
printf 'target_project_path=/work\n'
printf 'mode=docker\n'
printf 'container=cstk-mcp-state-healthcheck-test\n'
