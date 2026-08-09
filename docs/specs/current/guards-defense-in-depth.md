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

A adocao das guardas por um projeto-alvo MUST ocorrer atraves de um dos fluxos de distribuicao oficiais do toolkit ja documentados — o classico (`cstk install`/`cstk update`) e, a partir desta feature, tambem o plugin nativo do Claude Code — MUST NOT introduzir um terceiro mecanismo de distribuicao paralelo fora desses dois, nem um caminho que contorne a auditabilidade/consistencia de qualquer um dos dois. A adicao do caminho plugin nao e um mecanismo concorrente nao-governado: e uma segunda forma OFICIAL de entregar o mesmo conteudo auditavel, com garantias equivalentes em efeito, com mecanismos e responsaveis distintos, documentados por caminho (FR-015/FR-016 desta capability permanecem intactas nos dois caminhos; ver tabela abaixo). **Modelo de integridade por caminho de distribuicao** (achado F1 do gate `owasp-security` sobre o `plan`, MEDIUM, aceito com correcao textual — dec-026/dec-027, onda-004): os dois caminhos sao **comparaveis em forca de protecao, mas nao identicos em mecanismo**. Afirmar "o mesmo conjunto de garantias" seria, ele proprio, uma violacao do Principio VI (veracidade de dados) — por isso a redacao acima descreve equivalencia em EFEITO, nunca em mecanismo: | Garantia | Caminho classico | Caminho plugin | |----------|------------------|----------------| | Verificacao de integridade | `sha256` do tarball, fail-closed (`serve-integrity`) | Pin por `gitCommitSha` registrado pelo harness | | Origem confiavel | Allowlist fixa `CSTK_TRUSTED_RELEASE_HOSTS` (match exato, nao-overridable) | Repo git declarado no marketplace + confianca do harness | | Transporte | `http://` MUST ser rejeitado — politica que o proprio toolkit aplica e pode enforcar (`trusted-hosts.sh`) | HTTPS do provedor git — fato observado do mecanismo do harness; **nao** e uma politica que o toolkit impoe ou pode enforcar, ao contrario do caminho classico | | Consentimento | Comando explicito do operador | Tela "Will install" + dialogo de confianca do harness | | Quem aplica a garantia | Codigo do proprio cstk | Harness do Claude Code | Nenhum dos dois caminhos e "mais seguro" que o outro — cada um e auditavel dentro do que o respectivo responsavel (toolkit vs harness) efetivamente controla e pode enforcar.

*Introduzida por: enforced-guards (2026-07-28)*
*Ultima modificacao: claude-plugin-packaging (2026-08-09)*

