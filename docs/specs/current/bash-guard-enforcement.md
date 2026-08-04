# Capability: bash-guard-enforcement

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-001

O sistema MUST interceptar todo comando Bash emitido durante uma execucao autonoma (`agente-00c`/`feature-00c`) em um ponto anterior a execucao do comando, validando-o contra o mesmo conjunto de regras de bloqueio e de permissao de rede ja em vigor hoje.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-002

Quando um comando viola as regras, o sistema MUST impedir sua execucao e MUST expor um motivo claro e acionavel, equivalente em qualidade ao que a checagem manual ja produz hoje.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-003

Quando um comando nao viola nenhuma regra, o sistema MUST permitir sua execucao sem exigir passo manual adicional do operador ou do orquestrador, e sem atraso perceptivel no fluxo normal.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-004

A interceptacao MUST ser provisionada automaticamente pelo fluxo normal de instalacao/atualizacao do toolkit em um projeto-alvo — o operador MUST NOT precisar de um passo manual nao-documentado para ativa-la depois de atualizar o toolkit.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-005

As invocacoes advisory ja existentes (a propria prosa dos orquestradores chamando a checagem antes de comandos sensiveis) MUST permanecer em vigor apos esta feature — a interceptacao automatica e uma camada adicional de defesa em profundidade, nao uma substituicao que remove a camada atual.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-006

A interceptacao automatica MUST validar comandos Bash apenas quando originados de uma execucao ativa de `agente-00c`/`feature-00c` (deteccao via presenca de state/lock da execucao, **independente do backend de persistencia configurado — `state.json` ou `state.db`**) — sessoes interativas comuns do operador no mesmo projeto-alvo MUST NOT ser afetadas ou interceptadas por esta feature, mesmo apos a protecao estar provisionada, em qualquer backend (escopo restrito, opcao A; resolvido via bloqueio block-001/decisao dec-012 da feature `enforced-guards`).

*Introduzida por: enforced-guards (2026-07-28)*
*Ultima modificacao: hooks-db-parity (2026-08-04)*

### FR-007

Quando o proprio mecanismo de checagem falhar internamente ao processar um comando (erro inesperado do script de checagem, dependencia ausente, bug — distinto de uma violacao de regra conhecida), o sistema MUST BLOQUEAR o comando por padrao (fail-closed), tratando a falha do mecanismo como equivalente a "comando nao autorizado", nunca como passagem livre. O bloqueio MUST expor um motivo distinguivel de um bloqueio por violacao de regra (identificando que foi o proprio mecanismo de checagem que falhou), para diagnostico rapido pelo operador.

*Introduzida por: enforced-guards (2026-07-28)*

