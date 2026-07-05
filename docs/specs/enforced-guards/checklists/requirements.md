# Requirements Checklist: enforced-guards

**Purpose**: Valida a QUALIDADE geral dos requisitos (completude, clareza,
consistencia, mensurabilidade, rastreabilidade) da spec + plan — complementa o
checklist security.md. "Unit tests for English."
**Created**: 2026-07-05
**Feature**: [spec.md](../spec.md)

> Legenda: `{auto}` resolvivel contra artefatos; `{humano}` julgamento de
> negocio; marcadores `[Gap]`/`[Ambiguity]`/`[Conflict]`.

## Completude

- [x] CHK026 - Todos os FR funcionais das 3 US tem cobertura (US1: FR-001..007, US2: FR-008..011, US3: FR-012..014, defesa: FR-015..017)? [Completude, Spec §Requirements] {auto} — SIM: 17 FRs agrupados por US + secao defesa em profundidade.
- [x] CHK027 - As declaracoes de fora-de-escopo estao explicitas? [Completude, Spec §Out of Scope] {auto} — SIM: 5 itens (dieta de tarefas, code signing, lista concreta de hosts como suposicao, logica de deteccao interna, UI do painel).
- [x] CHK028 - Requisitos nao-funcionais (performance do hook, seguranca fail-closed, auditabilidade) estao cobertos? [Completude, plan §Technical Context] {auto} — SIM: plan §Performance Goals (~200ms/5s), §Constraints (fail-closed), FR-016 (auditabilidade).
- [x] CHK029 - As 4 Key Entities estao definidas com campos e tipos? [Completude, data-model.md] {auto} — SIM: GuardHookRegistration, EnforcementDecisionLog, IntegrityVerificationOutcome, TrustedHostAllowlist — todas com tabela de campos.

## Clareza e Mensurabilidade

- [x] CHK030 - Cada FR usa verbo imperativo testavel (MUST/MUST NOT)? [Clareza, Spec §Requirements] {auto} — SIM: todos os FR-001..017 usam MUST/MUST NOT.
- [x] CHK031 - Os Success Criteria SC-001..006 sao objetivamente verificaveis (percentuais/contagens, nao adjetivos)? [Mensurabilidade, Spec §Success Criteria] {auto} — SIM: todos usam "100%"/"Zero" com cenario mensuravel; mapeaveis aos Scenarios do quickstart.
- [x] CHK032 - Os SC se ligam a cenarios de teste concretos? [Traceability, quickstart.md] {auto} — SIM: SC-001→Scenario 1, SC-002→5/6/7, SC-003→8, SC-004→9/10, SC-005→log, SC-006→provisioning.
- [x] CHK033 - Valores de design propostos ([PROPOSTA] timeout=5s) estao marcados como decisao de design, nao como fato externo? [Clareza, data-model GuardHookRegistration] {auto} — SIM: data-model marca `timeout [PROPOSTA] 5`; e default de politica, nao dado factual (Constitution VI nao violado).

## Consistencia

- [x] CHK034 - A terminologia enforced vs advisory e consistente entre spec e plan? [Consistencia] {auto} — SIM: ambos usam "enforced" (nova camada) vs "advisory" (existente, preservada) de forma consistente.
- [x] CHK035 - Os requisitos nao contradizem a constitution do projeto? [Constitution Alignment, plan §Constitution Check] {auto} — SIM: plan §Constitution Check todos PASS/N/A; Principio II via carve-out 1.1.0 documentado (jq opcional confinado).
- [ ] CHK036 - O tratamento do `enforcement-log.jsonl` (secrets-filter no campo command) e consistente entre TODAS as secoes do plan? [Conflict, plan §Riscos item 3 vs §Threat Model] {auto} — [Conflict]: plan.md §Riscos item 3 diz "enforcement-log.jsonl sem secrets-filter no campo command ... nao resolvido neste plano", mas §Threat Model + data-model + contract/enforcement-log.md dizem que secrets-filter e MUST (Decision 10, ratificado dec-019). A resolucao pratica e clara (secrets-filter E obrigatorio); create-tasks implementa o MUST e o item de Riscos esta STALE. Registrar task de correcao documental (baixo custo) para eliminar a auto-contradicao.
- [x] CHK037 - O escopo de US3 (so install/self-update/serve, NAO update.sh/list.sh) e consistente entre plan e contract? [Consistencia, contracts/trusted-hosts.md] {auto} — SIM: ambos declaram update.sh/list.sh explicitamente fora do escopo (research Decision 7, debito tecnico nao corrigido aqui).

## Cobertura de Cenarios e Edge Cases

- [x] CHK038 - Happy paths das 3 US tem cenario? [Cobertura, quickstart Scenarios 1/2, 6, 9] {auto} — SIM: Scenario 1/2 (US1 bloqueio+permitido), 6 (US2 bypass), 9 (US3 host confiavel).
- [x] CHK039 - Error/edge paths tem comportamento definido (mecanismo falha, sessao manual, checksum divergente, host invalido, file://)? [Cobertura, Spec §Edge Cases] {auto} — SIM: 5 edge cases na spec + Scenarios 3/4/7/8/10 no quickstart.
- [x] CHK040 - O risco aberto de propagacao do hook a subagentes esta tratado como cenario bloqueante (spike)? [Edge Case, quickstart Scenario 0] {auto} — SIM: Scenario 0 e BLOQUEANTE "roda antes de tudo"; plan §Riscos item 1 exige spike como PRIMEIRA task; ambos os desfechos da bifurcacao sao resultado valido.

## Dependencias e Premissas

- [x] CHK041 - As dependencias dos mecanismos existentes (bash-guard.sh, allowlist rede, checksum) estao explicitas? [Completude, Spec §Dependencies] {auto} — SIM: secao Dependencies lista os 3; plan reforca que a logica de deteccao NAO muda.
- [x] CHK042 - A premissa critica (harness oferece ponto de interceptacao pre-execucao) esta documentada com fonte? [Traceability, plan §Constitution Check VI / research Decision 1] {auto} — SIM: research Decision 1 cita doc oficial `code.claude.com/docs/en/hooks` (verificada via claude-code-guide); premissa registrada em Spec §Dependencies.
- [x] CHK043 - A premissa de que o repo do painel hoje NAO publica dado de integridade esta registrada como estado observado? [Clareza, Spec §Dependencies / plan] {auto} — SIM: Spec §Dependencies "Assume que o repositorio... nao publica o dado de integridade esperado (estado observado)"; US2 contempla como caso comum.

## Rastreabilidade

- [x] CHK044 - User stories se ligam a FRs? [Traceability, Spec] {auto} — SIM: FRs agrupados sob cabecalhos por US (US1/US2/US3 + defesa).
- [x] CHK045 - Os contratos (pretooluse-hook, enforcement-log, trusted-hosts) se ligam a entidades do data-model? [Traceability] {auto} — SIM: pretooluse-hook→GuardHookRegistration+EnforcementDecisionLog; enforcement-log→EnforcementDecisionLog+IntegrityVerificationOutcome; trusted-hosts→TrustedHostAllowlist.
- [ ] CHK046 - A ordenacao/faseamento (US1 e US2 P1, US3 P2) reflete a prioridade correta de entrega para o dono do produto? [Risco, Spec §User Scenarios] {humano} — decisao do dono: spec ja marca US1/US2 P1 e US3 P2 com justificativa ("exposicao mais estreita"); aguardando confirmacao de que US3 pode ficar por ultimo/opcional na primeira entrega.

## Notes

- Items `{auto}` resolvidos: 19 (`[x]` com citacao).
- Items abertos para create-tasks: CHK036 [Conflict] (secrets-filter stale em plan §Riscos — task de correcao documental).
- Item `{humano}`: CHK046 (faseamento US3 P2).
- Gaps/ambiguidades ja capturados no security.md: CHK007 [Gap] (multi-execucao), CHK020 [Ambiguity] (ordem scrub/truncar).
