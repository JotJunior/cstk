# Requirements Checklist: Human Bridge (Intervencoes)

**Purpose**: Validar a qualidade geral dos 22 FRs de `spec.md` — completude,
clareza, consistencia, mensurabilidade dos Success Criteria, e disciplina
de veracidade (Principio VI) nos itens deliberadamente deferidos ao plano.
**Created**: 2026-08-29
**Feature**: [`../spec.md`](../spec.md) · [`../plan.md`](../plan.md)

## Gate deterministico: cobertura FR <-> Cenario

Rodado sobre `spec.md` via
`plugins/cstk/skills/checklist/scripts/requirement-coverage.sh`:

```
RESULT|docs/specs/human-bridge/spec.md|requirements=22|covered=22|errors=0
```

Exit 0, zero `FINDING`. Os 22 FRs tem pelo menos um cenario/edge case
associado — nenhum item `[Gap]` originado deste gate.

- [x] CHK001 - Todos os 22 FRs tem cobertura de cenario de aceite ou edge case, confirmada pelo gate deterministico acima (nao por inspecao manual)? [Mensurabilidade, gate `requirement-coverage.sh` — `covered=22/22`] {auto}

## Clareza e Forca Normativa

- [x] CHK002 - Todos os 22 FRs usam MUST/MUST NOT de forma consistente, sem "deveria"/"pode" que leia como opcional mas seja na pratica obrigatorio? [Clareza, Spec §Requirements] {auto}
- [x] CHK003 - O unico requisito com garantia parcial declarada (FR-008, filtragem "best-effort") esta redigido de forma que a diferenca de forca normativa em relacao aos MUST vizinhos (FR-006/FR-007) seja explicita, nao inferida? [Clareza, Spec FR-007 vs FR-008] {auto}
- [x] CHK004 - Termos de tempo intencionalmente vagos na spec ("intervalo curto, ordem de 1-2 segundos" em FR-019) estao acompanhados de um deferimento EXPLICITO para `plan.md` (nao deixados vagos sem destino), e o plano de fato fixou o valor (1500ms)? [Clareza, Spec FR-019 "Valor exato... fica em aberto para plan.md"; Plan §Summary "polling curto (1500 ms)"] {auto}

## Consistencia Entre Requisitos

- [x] CHK005 - FR-011 (distinguir resposta ativa de valor automatico) e FR-009/FR-010 (fallback automatico por prazo/indisponibilidade) sao consistentes entre si — o mecanismo que aplica o fallback tambem e o que alimenta a distincao exigida por FR-011, sem uma terceira via não coberta? [Consistencia, Spec FR-009/FR-010/FR-011] {auto}
- [x] CHK006 - FR-012 (fila nunca vira fonte de verdade) e coerente com FR-018 (registros da Ponte fora do acervo de conhecimento cross-projeto) — as duas apontam na mesma direcao: a Ponte e transporte operacional de curta duracao, nunca acervo? [Consistencia, Spec FR-012/FR-018] {auto}
- [x] CHK007 - FR-020 (sem expurgo automatico na v1) nao contradiz FR-017 (degradacao isolada do armazenamento) — um armazenamento que cresce indefinidamente ainda assim MUST degradar isoladamente se corrompido, e a spec nao confunde as duas garantias? [Consistencia, Spec FR-017/FR-020] {auto}

## Success Criteria — Mensurabilidade

- [x] CHK008 - Os 6 Success Criteria sao formulados como resultados observaveis e tecnologicamente agnosticos (percentuais, tempo em segundos), sem vazamento de detalhe de implementacao (nome de tabela, nome de rota)? [Mensurabilidade, Spec §Success Criteria] {auto}
- [x] CHK009 - SC-002 (resposta reflete em ate 10s) e verificavel sem ambiguidade sobre o que conta como "inicio" e "fim" da medicao (envio da resposta -> sessao de origem ve o desfecho)? [Clareza, Spec SC-002] {auto}
- [x] CHK010 - SC-005/SC-006 (isolamento entre sessoes; nao-duplicidade de efeito) sao tratados no plano como invariantes ESTRUTURAIS do desenho (decorrencia do roteamento por `session_id` e da condicao atomica de UPDATE), nao apenas como metas a validar por teste de carga isolado? [Mensurabilidade, Plan §"Os tres achados que mudaram o desenho" item 2; contract §7] {auto}

## Cobertura de Cenarios e Edge Cases

- [x] CHK011 - Cada uma das 3 User Stories declara um "Independent Test" que nao depende da implementacao completa das demais stories para ser executado isoladamente? [Cobertura, Spec §User Scenarios] {auto}
- [x] CHK012 - Os 7 Edge Cases listados tem, cada um, um desfecho esperado explicito (nao apenas a pergunta "o que acontece se...", mas a resposta)? [Cobertura, Spec §Edge Cases] {auto}
- [x] CHK013 - O Edge Case de "projeto removido do disco" (pendencia continua visivel, marcada como inalcancavel) tem um mecanismo de design correspondente e coerente no nivel de contrato (campo `reachable`), sem contradizer o texto da spec? [Consistencia, Spec §Edge Cases; contract §6 campo `reachable`] {auto}

## Disciplina de Veracidade (Principio VI) nos Itens Deferidos

- [x] CHK014 - Os quatro itens que a spec deliberadamente deferiu para `plan.md` (nome do endpoint, nome da env var, intervalo de polling, shape do payload) foram de fato resolvidos no plano/contrato com o rotulo `[PROPOSTA — a validar na implementacao]`, e nenhum deles foi silenciosamente promovido a `[VERIFICADO]` sem evidencia de codigo? [Principio VI, Spec §Clarifications; Plan §Legenda de veracidade + contract "Este contrato inteiro e PROPOSTA... exceto onde uma linha traz VERIFICADO explicito"] {auto}
- [x] CHK015 - As duas correcoes factuais registradas durante o plano (lacunas do scrub ja fechadas; medicao de `secrets-filter.sh`) foram aplicadas retroativamente ao contrato de entrada (`mcp-tool-ask-operator.md`), em vez de deixar uma afirmacao desatualizada coexistir com a correcao nova? [Principio VI, Plan §"Os tres achados que mudaram o desenho" item 1 — "Aplicado ao contrato na onda-005"] {auto}

## Dependencias, Premissas e Escopo

- [x] CHK016 - A spec declara explicitamente (`Delta Requirements: Skip`) que nenhuma capacidade documentada em `docs/specs/current/` e alterada/removida/renomeada, e essa afirmacao e consistente com o restante do artefato (feature aditiva, sem menção a remoção de capacidade existente)? [Consistencia, Spec §Delta Requirements] {auto}
- [x] CHK017 - As "Decisoes de infraestrutura" resumidas ao final da secao de Requirements (nota apos FR-022) mapeiam corretamente cada FR para a categoria de politica que ela cobre (timeout/fallback, idempotencia, mecanismo de espera, retencao, deteccao de indisponibilidade, descoberta de URL), sem categoria orfa nem FR sem categoria? [Consistencia, Spec nota pos-FR-022] {auto}

## Decisoes Ja Fechadas Pelo Operador — Nao Reabrir

As perguntas abaixo ja foram decididas nesta execucao e NAO sao reabertas
por este checklist; citadas aqui apenas para registrar que a checagem de
consistencia foi feita:

- [x] CHK018 - Mecanismo de espera = polling curto (nao long-poll), decidido em `dec-015`/`block-001`? [Spec §Clarifications Q2; `dec-015`] {auto}
- [x] CHK019 - Retencao sem expurgo automatico na v1, decidido em `dec-016`/`block-002`? [Spec §Clarifications Q3; `dec-016`] {auto}
- [x] CHK020 - Deteccao de indisponibilidade via reuso da chamada de criacao, decidido em `dec-017`/`block-003`? [Spec §Clarifications Q4; `dec-017`] {auto}
- [x] CHK021 - Descoberta de base URL via default fixo + env var, decidido em `dec-018`/`block-004`? [Spec §Clarifications Q5; `dec-018`] {auto}
- [x] CHK022 - Politica de autonomia do `ask_operator` (piso 60s + auditoria, opcao D), decidido em `dec-031`/`block-005`? [Plan §"Resolucao de F1"; `dec-031`] {auto}

## Escopo em Aberto (dono do produto)

- [ ] CHK023 - O crescimento ilimitado de `bridge.db` sem expurgo (FR-020) permanece aceitavel como caracteristica de v1 no horizonte de uso esperado, ou merece um follow-up pre-comprometido? [Risco de produto — duplicado do CHK021 de `security.md`, listado aqui por completude de dominio] {humano}

## Notes

- **{auto} resolvidos**: 22 (todos com citacao)
- **{humano} aguardando decisao**: 1 (CHK023 — mesma pergunta que CHK022 de `security.md`; o dono do produto responde uma vez, vale para os dois checklists)
- **Gaps abertos**: 0 neste dominio (o unico `[Gap]` da rodada esta em `api.md` CHK002)

### Proximos Passos

- CHK023 (e o correspondente CHK021/CHK022 de `security.md`) ficam para o
  dono do produto decidir antes ou durante `/execute-task` — nao bloqueiam
  `/create-tasks`.
- `api.md` CHK002 (`[Gap]`) DEVE virar uma tarefa explicita em
  `/create-tasks`: reconciliar o principio de degradacao (contract §3) com
  o shape de resposta das rotas de escrita (§4/§7) ANTES de qualquer
  codigo de `bridge/routes.ts` ser escrito.
- `/create-tasks` — decompor a implementacao em backlog.
