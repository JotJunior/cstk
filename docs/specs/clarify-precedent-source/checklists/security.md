# Security Checklist: clarify-precedent-source

**Purpose**: Qualidade dos requisitos de trust boundary do precedente cross-project (envenenamento, injecao, vazamento, consumo)
**Created**: 2026-09-30
**Feature**: [spec.md](../spec.md)

> Modo autonomo (feature-00c, onda-006): sem perguntas de escopo. Defaults
> registrados: profundidade Standard; audiencia Reviewer (PR); foco nos 2
> clusters de maior risco (trust boundary do precedente + vazamento
> cross-project).

## Trust boundary e envenenamento

- [x] CHK001 - A spec define que o precedente nao decide sozinho nem somado apenas a "constitution nao violada"? [Completude, Spec §FR-003, §FR-004, §Clarifications gate block-005] {auto}
- [x] CHK002 - A regra de suporte positivo nomeia exatamente quais fontes contam (briefing, spec_corrente/stack_sugerida) e exclui explicitamente o +1 de constitution? [Clareza, Spec §FR-003; Contract answerer-precedents regra 1] {auto}
- [x] CHK003 - O criterio de aceite de "zero decisoes sustentadas por precedente" e mensuravel sobre Decisoes auditadas, incluindo o caso precedente + constitution? [Mensurabilidade, Spec §SC-002] {auto}
- [x] CHK004 - O conteudo recuperado e declarado dado nao-confiavel, com regra de pausa quando ha diretiva embutida? [Completude, Spec §FR-008, §Edge Cases] {auto}
- [x] CHK005 - A regra de correspondencia precedente → opcao esta definida sem ambiguidade entre letra do rotulo e conteudo da opcao? [Ambiguity resolvida nesta onda, Contract answerer-precedents regra 4b] {auto}
- [ ] CHK006 - A procedencia do precedente (bloqueio realmente respondido pelo operador vs state versionado de repo de terceiro ingerido pelo `--reindex`) tem requisito de verificacao, ou o risco residual (recomendacao pre-preenchida a partir de dado forjado) e aceito explicitamente? [Gap, Plan §Revisao de seguranca S-1/S-3] {humano}
- [x] CHK007 - A recomendacao ao operador exige rotulo de origem (projeto/feature/data) e aviso de "historico nao verificado", marcando `[outro projeto]`? [Completude, Plan §S-3; Spec §FR-013 exige rotulo de origem] {auto}

## Vazamento e persistencia

- [x] CHK008 - Existe requisito limitando o que do texto de um precedente de outro projeto pode ser persistido em artefatos do projeto corrente (spec, Decisoes, commits)? [Completude, Plan §S-2; Contract `divergent_precedents.answer_excerpt` <= 120 bytes] {auto}
- [x] CHK009 - A regra de nao-persistencia de S-2 esta na spec (requisito verificavel) ou apenas no plan? [Gap, Spec §FR-007 exige citar id na justificativa mas nao limita texto; Plan §S-2] {auto}
- [x] CHK010 - O conteudo entregue ao answerer e requerido ja filtrado de segredos? [Completude, Spec §FR-008; Data-model §Precedent "scrubbed na ingestao"] {auto}
- [x] CHK011 - O evento auditavel proibe gravar o corpo recuperado? [Clareza, Spec §FR-012; Research §Decision 9] {auto}

## Injecao e superficie de entrada

- [x] CHK012 - As entradas do modo novo (texto da pergunta, `--limit`, `--max-bytes`, `--min-similarity`, `--db`) tem regra de validacao especificada, incluindo NUL e formato do decimal? [Completude, Contract cli-recall-precedents §Request] {auto}
- [x] CHK013 - O modo novo e requerido somente leitura, sem escrita na knowledge.db? [Clareza, Spec §FR-011; Contract cli-recall-precedents I-6] {auto}
- [x] CHK014 - Os limites operacionais do answerer (tools, sem registro de Decisao, sem spawn) sao preservados explicitamente? [Consistencia, Spec §FR-018] {auto}

## Consumo e degradacao

- [x] CHK015 - Os tetos por pergunta (precedentes, bytes, truncamento) estao quantificados com fonte ou declarados como default de design? [Mensurabilidade, Research §Decision 5; pool 20 declarado nao-medido] {auto}
- [x] CHK016 - Todo caminho de degradacao (sqlite3/indice ausente, erro de leitura, K=0) e requerido como no-op sem erro visivel? [Completude, Spec §FR-010; Contract cli-recall-precedents §Error Responses] {auto}
- [ ] CHK017 - O limiar 0.55, calibrado num corpus dominado por um projeto, e aceitavel como risco de falso-positivo (+1 indevido) ate a recalibracao pelo eval? [Assumption, Plan §Premissas P-3; Research §Decision 2] {humano}

## Notes

- Items `{auto}` resolvidos contra spec/plan/contracts com citacao; `{humano}` ficam `[ ]`.
- CHK005 foi aberto como `[Ambiguity]` e resolvido na mesma onda (regra 4b do contrato, com medicao da knowledge.db).
- CHK009 (`[Gap]`) segue para `/create-tasks`: tarefa de requisito para levar a regra S-2 a prosa dos answerers/referencias com verificacao estatica.
  Destino (tasks 1.1.3): regra redigida e frases-ancora A1-A4 definidas em `contracts/answerer-precedents.md` §Regra S-2; aplicada nos answerers (tasks 3.1.5 e 3.2.1), nas referencias (tasks 4.1.4 e 4.2.1) e verificada estaticamente pela task 4.3.1/4.3.2. Marcar `[x]` quando 4.3 cobrir.
- CHK006/CHK017 (`{humano}`) nao bloqueiam o backlog; decidir antes de `/execute-task` das tarefas de answerer.
