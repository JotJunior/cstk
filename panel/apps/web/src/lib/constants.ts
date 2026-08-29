/**
 * Etapas do pipeline SDD na ordem canonica (10 etapas).
 *
 * ATENCAO — esta lista e ACOPLADA ao pipeline do cstk e nao se atualiza
 * sozinha. Quando o toolkit insere uma etapa e esta lista nao acompanha, o
 * sintoma NAO e um erro: e a barra de progresso inteira ficar CINZA, porque
 * `indexOf(etapaCorrente)` devolve -1 e nenhuma etapa satisfaz `i < idx` nem
 * `i === idx` (ver `stageStates` em components/PipelineProgress.tsx).
 *
 * Ja aconteceu duas vezes:
 *   1. marcadores terminais (`concluida`/`abortada`) gravados como etapa —
 *      resolvido acendendo pelo STATUS, nao pelo indice;
 *   2. `converge`, inserida entre `execute-task` e `review-task` pela feature
 *      `pipeline-converge` do cstk — a barra apagou para toda execucao que
 *      chegou nessa etapa.
 *
 * O caso (2) e o caso geral e continua em aberto por construcao: o painel nao
 * tem como saber de uma etapa que ainda nao existe. Ao adicionar etapa aqui,
 * confira tambem os indices nos testes de `PipelineProgress`.
 */
export const SDD_STAGES = [
  'briefing', 'constitution', 'specify', 'clarify', 'plan',
  'checklist', 'create-tasks', 'execute-task', 'converge', 'review-task',
] as const;

export type SddStage = (typeof SDD_STAGES)[number];
