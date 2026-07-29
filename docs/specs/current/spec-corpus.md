# Capability: spec-corpus

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-006

System MUST manter um corpus canonico descrevendo o comportamento ATUAL do sistema, distinto do historico de mudancas por feature preservado sob `_archived/` — o corpus e ADICIONAL, nunca substitui o archive existente.

*Introduzida por: living-specs (2026-07-28)*

### FR-007

Cada entrada do corpus MUST ser rastreavel ate a(s) feature(s) que a introduziu ou modificou por ultimo (proveniencia).

*Introduzida por: living-specs (2026-07-28)*

### FR-008

A atualizacao do corpus MUST acontecer como parte da acao de archive ja existente, sem exigir um passo manual adicional alem do que o archive ja requer hoje.

*Introduzida por: living-specs (2026-07-28)*

### FR-009

Consultar o corpus MUST responder "como o sistema se comporta hoje" para qualquer capacidade coberta, sem exigir abrir nenhum diretorio sob `_archived/`.

*Introduzida por: living-specs (2026-07-28)*

