# Capability: serve-integrity

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-008

O sistema MUST NOT iniciar a execucao de codigo do painel web local a partir de um pacote baixado cuja integridade nao foi confirmada, exceto quando o operador tiver optado explicitamente por prosseguir sem essa confirmacao para aquela execucao especifica.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-009

Quando o dado necessario para confirmar integridade nao esta disponivel para download, o sistema MUST apresentar isso como uma decisao explicita a ser tomada (aceitar o risco ou interromper) — MUST NOT tratar a ausencia do dado como equivalente a uma verificacao bem-sucedida, nem prosseguir apenas com um aviso informativo como acontece hoje.

*Introduzida por: enforced-guards (2026-07-28)*

### FR-010

Quando a integridade confirmada diverge do pacote baixado, o sistema MUST recusar prosseguir, sem oferecer contorno silencioso (este comportamento ja existe hoje e MUST ser preservado pelo escopo desta feature — nenhum caminho de codigo pode tratar divergencia ou ausencia de verificacao como sucesso silencioso).

*Introduzida por: enforced-guards (2026-07-28)*

### FR-011

Uma decisao explicita do operador de prosseguir sem integridade confirmada MUST ficar registrada de forma revisavel posteriormente (o que foi executado sem verificacao e quando).

*Introduzida por: enforced-guards (2026-07-28)*

