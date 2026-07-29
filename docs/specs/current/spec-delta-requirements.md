# Capability: spec-delta-requirements

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-001

Autores de spec MUST ser capazes de declarar, dentro da spec da feature, uma secao de Delta Requirements com quatro tipos de entrada — ADDED, MODIFIED, REMOVED e RENAMED — usando o mesmo esquema de identificador (`FR-NNN`) ja usado na secao de Requirements da propria spec.

*Introduzida por: living-specs (2026-07-28)*

### FR-002

Uma entrada ADDED MUST, ao a feature ser arquivada, se tornar uma nova entrada no corpus canonico.

*Introduzida por: living-specs (2026-07-28)*

### FR-003

Uma entrada MODIFIED MUST, ao a feature ser arquivada, substituir a entrada correspondente do corpus (casada por identificador) pelo novo texto, preservando o identificador.

*Introduzida por: living-specs (2026-07-28)*

### FR-004

Uma entrada REMOVED MUST, ao a feature ser arquivada, retirar a entrada correspondente do corpus como comportamento atual, preservando um registro rastreavel da remocao (nunca um desaparecimento silencioso do historico).

*Introduzida por: living-specs (2026-07-28)*

### FR-005

Uma entrada RENAMED MUST, ao a feature ser arquivada, aposentar o identificador antigo e registrar o novo identificador para a mesma entrada do corpus, sem perder a rastreabilidade historica da entrada.

*Introduzida por: living-specs (2026-07-28)*

