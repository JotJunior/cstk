#!/bin/sh
# Fixture de teste: simula mcp-session.sh resolve --state-dir (modo direto)
# com sucesso, mas so se `--state-dir` de fato aparecer no argv (prova que
# resolveActiveSession usou o locator certo quando a opcao `stateDir` e
# passada explicitamente, em vez de --project-path). Ate mcp-direct-transport
# FASE 1, `stateDir` vinha de CSTK_MCP_STATE_DIR (modo container, dec-081);
# apos a FASE 1, vem do cache `token -> state_dir` de `resolveSessionForCall`
# (cache-hit). Usado apenas por test/resolve.test.ts via injecao de
# --helperPath.
set -eu

_has_state_dir=0
_state_dir_value=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir)
      _has_state_dir=1
      _state_dir_value=$2
      shift 2
      ;;
    --project-path)
      printf 'fake-mcp-session-ok-container-mode: --project-path nao deveria ter sido usado no modo container\n' >&2
      exit 1
      ;;
    *) shift ;;
  esac
done

if [ "$_has_state_dir" -ne 1 ]; then
  printf 'fake-mcp-session-ok-container-mode: --state-dir ausente do argv\n' >&2
  exit 1
fi

printf 'state_dir=%s\n' "$_state_dir_value"
printf 'execution_kind=feature-00c\n'
printf 'short_name=state-mcp-server\n'
printf 'target_project_path=/work\n'
printf 'mode=docker\n'
printf 'container=cstk-mcp-state-test\n'
