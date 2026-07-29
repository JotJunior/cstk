# Capability: atomic-commit-staging

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-014

O staging de commits automaticos do modo atomic-commit (por etapa e por task, em execucao autonoma) MUST usar uma allowlist explicita de caminhos derivada dos artefatos tocados pelo passo/task corrente — MUST NOT usar staging amplo (equivalente a "adicionar tudo do working tree").

*Introduzida por: living-specs (2026-07-28)*

### FR-015

Quando um arquivo untracked alheio ao passo/task corrente estiver presente no working tree no momento do commit automatico, ele MUST NOT ser incluido no commit gerado, independentemente do tipo de arquivo.

*Introduzida por: living-specs (2026-07-28)*

### FR-016

Quando a allowlist de um passo/task for vazia, nenhum commit MUST ser criado para aquele passo/task (sem commits vazios, sem fallback para staging amplo).

*Introduzida por: living-specs (2026-07-28)*

### FR-017

O cenario que causou o incidente original (arquivo untracked alheio presente durante commit atomico de etapa) MUST ter cobertura de teste de regressao automatizada.

*Introduzida por: living-specs (2026-07-28)*

