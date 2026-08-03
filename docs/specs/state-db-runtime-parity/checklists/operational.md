# Operational Checklist: state-db-runtime-parity

**Purpose**: Quality gate dos requisitos operacionais — porte dos 15
leitores (criterio de pronto por script), migracao sem regressao do backend
JSON, anti-mirror e varredura dinamica.
**Created**: 2026-08-02
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md)

> IDs CHK020-CHK032 (continuacao da sequencia unica da feature).

## Escopo e criterio de pronto do porte (FR-001/FR-002/FR-011)

- [x] CHK020 - O escopo do porte enumera NOMINALMENTE todos os leitores (manifest de 15: 14 do runtime + `cli/lib/00c-bootstrap.sh`)? [Completude, Spec §FR-001] {auto} — evidencia: FR-001 lista budget, cycles, circular, drift, retro, suggestions, wave-usage-report, model-routing, model-routing-report, state-cache, state-validate, state-decisions-reconcile, issue, pipeline (14) + bootstrap (15).
- [x] CHK021 - Existe criterio de pronto POR SCRIPT (nao apenas global): cada leitor com cenario SQLite no proprio teste, sem "state.json ausente", com veredito equivalente? [Mensurabilidade, Spec §FR-001/FR-002/FR-011; Plan §F2] {auto} — evidencia: FR-011 (teste por script tocado, `--check-coverage` verde) + plan F2 "cenarios sqlite nos testes de cada script (FR-011)".
- [x] CHK022 - A equivalencia de veredito dos 6 helpers de controle e objetivamente mensuravel (exit code + semantica de saida, mesmo estado logico nos 2 backends)? [Mensurabilidade, Spec §FR-002; §SC-003] {auto} — evidencia: FR-002 "veredito equivalente (exit code + semantica de saida)"; SC-003 "0 divergencias nos cenarios de equivalencia da suite".
- [x] CHK025 - O achado de codigo real fora do manifest (checagem de execucao ativa do subcomando `check` do lock) tem destino definido no porte? [Cobertura, Spec §FR-010/Edge Cases; Plan §F2] {auto} — evidencia: edge case "entra no porte" + plan F2 "state-lock.sh check-execution-busy".
- [x] CHK028 - A ordem de dependencia entre o helper de leitura (F1, com teste) e o porte dos leitores (F2) esta definida, impedindo porte sem helper testado? [Dependencias, Plan §Fases 1-2] {auto} — evidencia: plan §Fases "ordem por dependencia", F1 = helper + teste antes de F2 = porte.

## Migracao sem regressao do backend JSON (FR-004)

- [x] CHK024 - A retrocompatibilidade JSON tem criterio de verificacao definido (suite existente de cada script roda INALTERADA sob JSON)? [Mensurabilidade, Spec §FR-004; Plan §Riscos] {auto} — evidencia: plan §Riscos "regressao JSON (FR-004) coberta por suite existente — os testes atuais de cada script rodam inalterados sob JSON".
- [x] CHK029 - O custo operacional da materializacao (1 `state-rw.sh read` extra por invocacao de helper) esta documentado como ACEITO com justificativa (helpers rodam 1x por onda; caminho JSON zero-overhead)? [Assumption, Plan §Riscos] {auto} — evidencia: plan.md:126-129.
- [x] CHK026 - O comportamento sobre state-dir vazio/nao-inicializado esta definido como agnostico de backend (mesmo diagnostico contratual de hoje)? [Cobertura, Spec §Edge Cases] {auto} — evidencia: edge case "mesmo comportamento contratual de hoje ... agnostico de backend".
- [x] CHK027 - O caso de state-dir com AMBOS `state.json` e `state.db` define resolucao deterministica pela regra ja estabelecida na fundacao (nunca mistura leituras)? [Cobertura, Spec §Edge Cases] {auto} — evidencia: primeiro edge case da spec.

## Anti-mirror e varredura (FR-003/FR-009/SC-004)

- [x] CHK023 - O anti-mirror esta coberto como requisito (FR-003, nenhum fluxo materializa espelho) E como verificacao automatica pos-varredura (SC-004, US1 AS4)? [Consistencia, Spec §FR-003/SC-004] {auto} — evidencia: FR-003 + SC-004 "verificacao automatica pos-varredura" + FR-009a "criar espelho `state.json` pos-varredura" como condicao de falha.
- [x] CHK032 - A fixture "state-dir SQLite populado" da varredura dinamica especifica as entidades minimas (ondas? decisoes? bloqueios? tasks?) para que os 15 leitores exercitem caminho real e nao vazio-trivial? [Resolvido, Research Decision 5] {auto} — resolvido na FASE 1/1.1.3 (onda-006): research.md §"Fixture minima da varredura dinamica (CHK032)" — 9 passos via primitivas (init com >=3 key-aspects; 1 onda fechada + 1 aberta; 2 decisoes incl. roteamento + record-skill; 1 bloqueio respondido; 2 pushes circulares; 1 retro consumida — SIM, retro.sh exige; 1 sugestao; 1 record-task; 1 metrics-bump). drift EXIGE key_aspects; retro EXIGE retro-execucao consumida. Aterrado em sonda de campos por script (onda-006).

## Fluxo dogfooding e conclusao (SC-002)

- [x] CHK030 - O criterio de aceitacao da execucao completa sob SQLite e observavel (SC-002: zero workarounds manuais "read | transform | write")? [Mensurabilidade, Spec §SC-002] {auto} — evidencia: SC-002 quantifica "zero intervencoes do tipo read | transform | write feitas a mao".
- [x] CHK031 - A exclusao dos hooks do escopo (Out of Scope) deve ganhar gatilho/prioridade para a feature dedicada (hoje o hook de tick nunca dispara sob SQLite)? [Dependencias, Spec §Out of Scope; dec-010] {humano} — RESPONDIDO (block-002 → dec-069, score 3): operador escolheu `priorizar-feature-de-hooks`. Feature dedicada priorizada (short-name sugerido: `hooks-db-parity`), dono: operador; gatilho: proxima `/feature-00c` apos release desta feature. Sugestao formal registrada via `suggestions.sh register` (task 6.4.3) com escopo minimo: porte de `posttooluse-tool-call-tick.sh` e `pretooluse-bash-guard.sh` para deteccao backend-agnostica de execucao ativa, com requisito de latencia (~30ms tick / ~177ms bash-guard).

## Notes

- `{humano}` em aberto: nenhum — CHK031 respondido via block-002/dec-069 (onda-015).
- `[Gap]` CHK032 resolvido na FASE 1/1.1.3 (onda-006) — ver item acima.
- Itens `{auto}` resolvidos com citacao de spec/plan/contract.
