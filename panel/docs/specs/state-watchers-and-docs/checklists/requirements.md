# Requirements Checklist: Watchers de Execução em Andamento e Visualização de Documentação

**Purpose**: Quality gate ("unit tests for English") da qualidade geral dos
requisitos desta feature — completude, clareza, consistência, mensurabilidade —
mais as superfícies de UX (doc-viewer) e contrato de API. Não valida
implementação; valida a qualidade do que a spec/plan escrevem.
**Created**: 2026-07-15
**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md)
**Domínios irmãos**: [security.md](./security.md) · [performance.md](./performance.md)

> IDs `CHK001`–`CHK026` (numeração global única entre os checklists da feature;
> security = `CHK027`+, performance = `CHK044`+).

## Completude de Requisitos

- [x] CHK001 - São os requisitos de detecção de novidade (onda concluída, nova decisão, mudança de status) especificados para AMBOS os status observáveis (`em_andamento` e `aguardando_humano`)? [Completude, Spec §FR-001/FR-003] {auto}
- [x] CHK002 - O mapeamento fixo etapa-SDD → artefato(s) está definido para todas as etapas do pipeline que produzem artefato (specify/clarify/plan/checklist/create-tasks)? [Completude, research Decision 8] {auto}
- [x] CHK003 - Estão definidos requisitos de degradação para cada modo de falha (path não resolvido, path inacessível, ingestão falha, artefato ausente, DB ausente/corrompida)? [Completude, Spec §FR-012, data-model §Degradação] {auto}
- [x] CHK004 - Os requisitos não-funcionais (latência ≤30s, conteúdo UNTRUSTED, observabilidade/frescor) estão cobertos além dos funcionais? [Completude, Spec §SC-001/FR-010/FR-011] {auto}
- [x] CHK005 - As exclusões de escopo (sem WebSocket, sem coluna nova na knowledge.db, sem `--reindex`, sem multi-tenant/RBAC) estão declaradas explicitamente? [Completude, Spec §"Decisões de infraestrutura"/FR-004/FR-008, plan §Scale/Scope] {auto}

## Clareza de Requisitos

- [x] CHK006 - O termo "quase em tempo real" está quantificado com prazo específico? [Clareza, Spec §SC-001 (≤30s)] {auto}
- [x] CHK007 - "Renderizado/formatado" está definido de forma distinta de "texto bruto"? [Clareza, Spec §FR-006, research Decision 6] {auto}
- [x] CHK008 - "Degradar graciosamente" está operacionalizado com sinais concretos (`meta.degraded`/`meta.reason`, nunca 5xx)? [Clareza, Spec §FR-012, data-model §Degradação] {auto}
- [x] CHK009 - "Indicador de frescor consistente com o existente" está ancorado num artefato de referência concreto? [Clareza, Spec §FR-011, research grounding `FreshnessLabel.tsx`/`computeFreshness`] {auto}
- [x] CHK010 - O comportamento de FR-013 ("pausada/reduzida quando não houver execução") está desambiguado (timer segue por-tick, mas tick ocioso não dispara subprocesso)? [Ambiguity, Spec §FR-013, contract watchers §1 (tick ocioso ⇒ nenhum subprocesso)] {auto}

## Consistência de Requisitos

- [x] CHK011 - O requisito de delegação (FR-004: nunca escrita direta; delegar ao `cstk`) é consistente com os Princípios I e IV da constitution? [Consistência, Spec §FR-004, plan §Constitution Check I/IV] {auto}
- [x] CHK012 - A precedência de resolução de caminho ("flag/config > env > default" na constituição/Q1 vs. "env > default" no código real) está reconciliada sem contradição não resolvida? [Conflict, plan §"ponto de honestidade documentado", research Decision 1 (espelha o real env>default)] {auto}
- [x] CHK013 - A terminologia de status (`em_andamento`/`aguardando_humano`/`concluida`/`abortada`) é consistente entre spec, data-model e a fonte real (enum `ExecutionDTO.status`)? [Consistência, data-model §State transitions, research grounding] {auto}

## Qualidade de Critérios de Aceite (Mensurabilidade)

- [x] CHK014 - SC-001 (latência) é objetivamente mensurável e delimita a condição de disparo (o que conta como a mudança "acontecer")? [Mensurabilidade, Spec §SC-001, quickstart Cenário 1] {auto}
- [x] CHK015 - SC-002 ("100% dos artefatos já produzidos") é objetivamente verificável (contável) e delimita "já produzidos"? [Mensurabilidade, Spec §SC-002] {auto}
- [x] CHK016 - SC-003 ("acompanhar integralmente sem abrir editor/terminal") tem fronteira mensurável ("os fluxos cobertos por esta feature")? [Mensurabilidade, Spec §SC-003] {auto}
- [x] CHK017 - SC-004 (frescor por execução observada) é verificável para 100% das execuções observadas? [Mensurabilidade, Spec §SC-004] {auto}

## UX — Doc-Viewer

- [x] CHK018 - O estado "ainda não produzido" está especificado como sucesso sinalizado (`produced:false`/`content:null`), não como erro (404/5xx)? [Cobertura, Spec §FR-007, contract docs-api §"Response 200 ainda não produzido"] {auto}
- [x] CHK019 - O requisito de navegar entre múltiplos artefatos disponíveis (incluindo arquivos extras) está definido? [Cobertura, Spec §FR-005/US2 AC-3/SC-002] {auto}
- [ ] CHK020 - Está definido se a visão de docs deve exibir indicador de frescor do CONTEÚDO do artefato (`mtime` do `.md`), distinto do frescor da execução observada (FR-011)? [Gap, contract docs-api §"Nota de frescor" (ETag do arquivo é [PROPOSTA]; nenhum requisito sobre indicar frescor de conteúdo ao usuário)] {humano}

## Contrato de API

- [x] CHK021 - A superfície nova é especificada como exclusivamente `GET` (nenhum `POST/PUT/PATCH/DELETE`), alinhada ao Princípio I? [Consistência, contract docs-api Invariante 1, plan §Constitution Check I] {auto}
- [x] CHK022 - Os shapes de resposta de erro/degradado (400 traversal; 200 degradado com `meta.reason`) estão especificados? [Completude, contract docs-api §Responses] {auto}
- [x] CHK023 - Os novos valores de `meta.reason` (`project-path-unresolved`/`project-path-inaccessible`) estão definidos e diferenciados dos existentes (`db-missing`/`db-corrupt`/…)? [Clareza, contract docs-api §"Response 200 degradado" (marcados [PROPOSTA])] {auto}

## Cobertura de Edge Cases

- [x] CHK024 - O comportamento com múltiplas execuções em andamento simultâneas (mesma feature / projetos distintos) está especificado no nível de requisito (iteração por execução + limite de concorrência)? [Edge Case, Spec §Edge Cases, contract watchers §1, research Decision 9.3 — o VALOR do cap é [PROPOSTA]] {auto}

## Dependências e Premissas

- [x] CHK025 - A dependência do comando canônico `cstk recall --ingest --state-dir` está documentada e validada contra fonte real? [Completude, research grounding (`cstk recall --help`, v5.18.0), contract watchers §2] {auto}
- [x] CHK026 - A premissa de que o polling do cliente existente (10s, `AUTO_REFRESH_MS`) basta para SC-001 sem alteração está fundamentada em código real? [Assumption→fundamentada, research Decision 5, grounding `apps/web/src/lib/query.ts`] {auto}

## Notes

- Items `{auto}` já vêm resolvidos: `[x]` com citação, ou `[ ]` com marcador (`[Gap]`/`[Ambiguity]`/`[Conflict]`/`[Assumption]`).
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto.
- **Resolução**: 24 `{auto}` verificados `[x]`; 1 item `{humano}` em aberto (CHK020); 0 gaps auto em aberto neste arquivo. Rastreabilidade: 100% (todos citam Spec/research/contract ou marcador).
- **Follow-up**: CHK020 (frescor de conteúdo do doc-viewer) → decisão de escopo do dono do produto antes de `/create-tasks`.
