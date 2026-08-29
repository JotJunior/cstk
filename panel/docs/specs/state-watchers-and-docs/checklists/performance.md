# Performance Checklist: Watchers de Execução em Andamento e Visualização de Documentação

**Purpose**: Quality gate da qualidade dos requisitos de PERFORMANCE e
OBSERVABILIDADE do mecanismo de watchers — orçamento de latência SC-001,
idempotência, ociosidade, concorrência/backoff, degradação e frescor. Valida
qualidade de requisito, não a implementação nem números medidos.
**Created**: 2026-07-15
**Feature**: [spec.md](../spec.md) | **Plan**: [plan.md](../plan.md) | **Contract**: [watchers.md](../contracts/watchers.md)
**Domínios irmãos**: [requirements.md](./requirements.md) · [security.md](./security.md)

> IDs `CHK044`–`CHK057`. Vários valores concretos de tuning (cadência, timeout,
> cap de concorrência, duração da ingestão) são **[PROPOSTA]** na research — os
> items abaixo validam se essa condição de "a-medir" está honestamente declarada.

## Targets / Orçamento de Latência (SC-001)

- [x] CHK044 - O orçamento de latência de SC-001 (≤30s) está decomposto em componentes verificáveis (cadência do watcher + ingestão + polling do cliente + render)? [Clareza, research Decision 5] {auto}
- [ ] CHK045 - A premissa de duração da ingestão `cstk recall --ingest` (que sustenta a folga dos 30s) está declarada como NÃO-medida / a-validar, sem ser afirmada como fato? [Assumption, research Decision 5 ("Nenhum número de duração … é afirmado aqui como medido — premissa a validar")] {auto}
- [x] CHK046 - A condição de medição de SC-001 (o que dispara a contagem: onda concluída / nova decisão / transição de status) está especificada? [Clareza, Spec §SC-001, quickstart Cenário 1] {auto}

## Idempotência / Trabalho Redundante (FR-014)

- [x] CHK047 - O requisito de evitar disparo redundante quando o estado subjacente não mudou (via assinatura do `state.json`) está especificado? [Completude, Spec §FR-014, research Decision 4] {auto}
- [x] CHK048 - A chave do cache de assinatura (por state-dir) e sua natureza efêmera (em memória, não persistida — Princípio I) estão definidas? [Clareza, data-model §Watcher Signature Cache, research Decision 4] {auto}

## Ociosidade / Escalabilidade (FR-013, FR-003)

- [x] CHK049 - O requisito de ociosidade sem execução ativa (tick não dispara nenhum subprocesso) está especificado? [Cobertura, Spec §FR-013, contract watchers §1 (passo 2: vazio ⇒ tick ocioso)] {auto}
- [x] CHK050 - O requisito de parar de observar execuções terminais (`concluida`/`abortada`) está especificado com as transições de estado? [Cobertura, Spec §FR-003, data-model §State transitions] {auto}
- [x] CHK051 - O comportamento de escalabilidade com N execuções ativas por tick (limite de concorrência de subprocessos `cstk`) está especificado? [Edge Case, research Decision 9.3, contract watchers §2 — o VALOR do cap é [PROPOSTA]] {auto}

## Degradação / Resiliência (FR-012)

- [x] CHK052 - O requisito de backoff em falha persistente de ingestão (anti loop apertado) está especificado? [Completude, research Decision 9.3, contract watchers §2 (política exata [PROPOSTA])] {auto}
- [x] CHK053 - O requisito de conexão de DB por-tick (abre/fecha; sem conexão de longa duração — Princípio VI) está especificado? [Completude, research Decision 2, contract watchers §1] {auto}
- [x] CHK054 - O requisito de não derrubar o server em falha de subprocesso (degradação sinalizada, não crash) está especificado? [Cobertura, Spec §FR-012, contract watchers §2 (exit≠0/timeout ⇒ log + degradado)] {auto}

## Observabilidade (FR-011)

- [x] CHK055 - O requisito de indicador de frescor por execução observada está especificado e ligado a SC-004 (100% das execuções)? [Cobertura, Spec §FR-011/SC-004] {auto}
- [ ] CHK056 - O escopo da superfície observável de degradação do watcher (campo novo no `meta` do envelope vs. `GET /api/v1/watchers` vs. apenas o sinal FR-012 existente) está definido, ou é decisão deferida? [Ambiguity, contract watchers §3 ("Decisão de escopo a fechar em `/create-tasks`; não é bloqueante")] {humano}

## Julgamento de Tuning (Dono do Produto / Engenharia)

- [ ] CHK057 - Os valores default propostos (`WATCH_INTERVAL_MS`=10s, timeout do subprocesso, cap de concorrência) — todos **[PROPOSTA]** — são aceitáveis pendente de medição empírica antes do release? [Risco, research Decision 5/9 (a validar na implementação)] {humano}

## Notes

- Items `{auto}` já vêm resolvidos: `[x]` com citação, ou `[ ]` com marcador.
- Items `{humano}` ficam `[ ]` aguardando decisão do dono do produto / engenharia.
- **Resolução**: 11 `{auto}` verificados `[x]`; 1 `{auto}` aberto como `[Assumption]` (CHK045 — duração da ingestão, a medir em `/execute-task`); 2 `{humano}` em aberto (CHK056 escopo de observabilidade; CHK057 tuning). Rastreabilidade: 100%.
- **Follow-up**:
  - CHK045 `[Assumption]` → `/execute-task`: medir a duração real de `cstk recall --ingest` e confirmar a folga dos 30s (research Decision 5 já prevê esse ajuste).
  - CHK056 `[Ambiguity]` → decisão de escopo em `/create-tasks` (superfície observável de degradação).
  - CHK057 `{humano}` → dono do produto/engenharia fixa os defaults de tuning após medição.
