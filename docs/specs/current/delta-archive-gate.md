# Capability: delta-archive-gate

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-010

A acao de archive MUST ser bloqueada, por padrao, para qualquer feature que nao tenha secao de Delta Requirements — salvo quando um skip explicito for registrado.

*Introduzida por: living-specs (2026-07-28)*

### FR-011

Um skip de delta MUST ser um registro auditavel (quem, quando, por que), distinguivel de uma aplicacao normal de delta em qualquer relatorio ou trilha de auditoria que liste aquele archive.

*Introduzida por: living-specs (2026-07-28)*

### FR-012

O gate da FR-010 MUST ser deterministico (script, nao julgamento de modelo), no mesmo padrao ja adotado pelo toolkit para outros gates de qualidade estrutural (ex.: `requirement-coverage.sh`).

*Introduzida por: living-specs (2026-07-28)*

### FR-013

O gate MUST sinalizar (nao aplicar silenciosamente) qualquer entrada MODIFIED, REMOVED ou RENAMED cujo identificador referenciado nao exista no corpus atual.

*Introduzida por: living-specs (2026-07-28)*

