#!/bin/sh
# Fixture de teste: simula mcp-session.sh resolve com sucesso, emitindo os
# 6 campos obrigatorios do descritor. Usado apenas por test/resolve.test.ts
# via injecao de --helperPath (nao e o mcp-session.sh real).
set -eu
printf 'state_dir=/data/state\n'
printf 'execution_kind=feature-00c\n'
printf 'short_name=state-mcp-server\n'
printf 'target_project_path=/work\n'
printf 'mode=docker\n'
printf 'container=cstk-mcp-state-test\n'
