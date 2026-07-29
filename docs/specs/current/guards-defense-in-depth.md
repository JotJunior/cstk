# Capability: guards-defense-in-depth

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-015

Nenhuma das tres frentes desta feature MUST remover ou enfraquecer uma checagem de seguranca ja existente — todas sao camadas adicionadas sobre o comportamento atual (blocklist/whitelist, verificacao de checksum, rejeicao de `http://`).

*Introduzida por: enforced-guards (2026-07-28)*

### FR-016

Toda vez que a interceptacao enforced (US1) bloquear um comando, ou que uma verificacao de integridade (US2) resultar em bypass explicito, ou que um download for rejeitado por host fora da allowlist (US3), o evento MUST ficar registrado de forma auditavel e revisavel — nao apenas visivel momentaneamente em terminal (Principio I, Auditabilidade total).

*Introduzida por: enforced-guards (2026-07-28)*

### FR-017

A adocao desta feature por um projeto-alvo MUST ocorrer atraves do fluxo normal de instalacao/atualizacao do toolkit ja usado para outras capacidades (mesmo modelo de distribuicao existente) — MUST NOT introduzir um segundo mecanismo de distribuicao paralelo.

*Introduzida por: enforced-guards (2026-07-28)*

