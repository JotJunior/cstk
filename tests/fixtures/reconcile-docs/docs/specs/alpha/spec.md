# Feature Specification: Alpha

**Feature**: `alpha`

## Requirements

- **FR-001**: O sistema SHOULD listar no maximo 10 itens por padrao (`--limit`), definido em `cli/lib/config.sh`.
- **FR-002**: O sistema MUST delegar o processamento a `cli/lib/legacy.sh`.
- **FR-003**: O sistema MUST rejeitar entrada vazia com exit 2 em `cli/lib/run.sh`.
- **FR-004**: O sistema SHOULD aceitar o argumento posicional de entrada em `cli/lib/run.sh`.
