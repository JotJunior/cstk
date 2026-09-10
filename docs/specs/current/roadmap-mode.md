# Capability: roadmap-mode

> Comportamento ATUAL do sistema para esta capability. Gerado/atualizado
> exclusivamente por delta-merge.sh na acao de archive — nao editar a mao.

## Requirements

### FR-001

`/agente-00c` MUST oferecer o modo roadmap via pergunta interativa no inicio da execucao (mesmo padrao do opt-in atomic-commit), com default = pipeline completa atual; execucao nao-interativa MUST cair no default sem bloquear (zero regressao).

*Introduzida por: roadmap-mode (2026-09-09)*

### FR-002

Em modo roadmap, a pipeline MUST executar somente briefing → constitution → geracao do roadmap, reaproveitando briefing e constitution ja ratificados quando existirem; as etapas de implementacao (specify, clarify, plan, checklist, create-tasks, execute-task, review-task) MUST NOT executar nesta execucao.

*Introduzida por: roadmap-mode (2026-09-09)*

### FR-003

O roadmap MUST ser persistido como artefato canonico do projeto-alvo (`docs/roadmap.md`), contendo por entrada: nome curto kebab-case, descricao acionavel, ordem sugerida de execucao, dependencias entre features e justificativa da necessidade.

*Introduzida por: roadmap-mode (2026-09-09)*

### FR-004

Apos gerar o roadmap, a execucao MUST encerrar em estado terminal de sucesso, com o roadmap incluso no relatorio final — o encerramento e o resultado esperado do modo, nao um aborto. O encerramento MUST ser distinguivel de uma conclusao de pipeline completa por um `termination_reason` de execucao proprio e normativo (`concluido_roadmap`, `contracts/cli-roadmap-mode.md` §5.2) — sem essa distincao, SC-001 nao e mensuravel por consumidores derivados.

*Introduzida por: roadmap-mode (2026-09-09)*

### FR-009

A producao/escrita de `docs/roadmap.md` MUST ser responsabilidade de um componente dedicado (`roadmap-write.sh`), acionado pelo `agente-00c-orchestrator` ao concluir a redacao do conteudo do roadmap dentro da etapa `roadmap`, ANTES do encerramento terminal da execucao. O conteudo MUST passar pelo filtro de segredos do runtime (`secrets-filter.sh`) imediatamente antes da escrita, com politica fail-closed: se o filtro estiver ausente, a escrita MUST ser abortada — nunca escrever sem filtrar.

*Introduzida por: roadmap-mode (2026-09-09)*

