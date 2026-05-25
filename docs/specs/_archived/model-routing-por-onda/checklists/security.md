# Security Checklist: model-routing-por-onda

**Purpose**: validar a QUALIDADE dos requisitos de segurança — input untrusted ao
classificador, override do operador, manuseio de path e conteúdo sensível em
Decisões. Não testa a implementação da mitigação.
**Created**: 2026-05-24
**Feature**: [spec.md](../spec.md)

## Input untrusted ao model-selector

- [x] CHK019 - A spec exige explicitamente que `--task-text` (vindo de descrição de tarefa, potencialmente arbitrária) seja tratado como untrusted na fronteira do refino (shell injection, NUL bytes)? [Gap, Spec §FR-019] → resolvido FR-022
- [x] CHK020 - O requisito reusa as mitigações F-001/F-002 da feature original (jq --arg, sem expansão sem aspas) de forma declarada, não implícita? [Clareza, research.md D5] → resolvido FR-022
- [x] CHK021 - Está especificado o limite de tamanho do `--task-text` (truncamento) para conter consumo excessivo? [Gap, contracts/wave-select.md] → resolvido FR-022

## Validação do override do operador

- [x] CHK022 - O valor do override (`model-override:<x>`) tem requisito de validação contra o enum {haiku,sonnet,opus} — rejeitando string arbitrária? [Gap, data-model.md] → resolvido FR-023
- [x] CHK023 - Está definido o que acontece se o operador registrar um override com modelo inválido (→ fallback? erro? ignorado)? [Gap, Spec §FR-016] → resolvido FR-023
- [x] CHK024 - O escopo do override é limitado a uma onda específica (não vaza para ondas seguintes não-intencionadas)? [Clareza, data-model.md] → resolvido FR-023

## Manuseio de modelo e path

- [ ] CHK025 - O requisito de validar o modelo antes de passar ao spawn (toda sugestão inválida → manter-atual) cobre TODAS as origens (mapa, refino, override)? [Completude, Spec §SC-007]
- [x] CHK026 - A resolução do path de `phase-model-map.txt` tem requisito de confinamento (sem path traversal, sem aceitar path arbitrário do operador)? [Gap, contracts/wave-select.md] → resolvido FR-024

## Conteúdo sensível em Decisões

- [x] CHK027 - Está especificado que a descrição da tarefa armazenada em `justificativa`/`sinais_text` da Decisão pode conter dado sensível e qual o tratamento (scrub na ingestão recall já existe; e no state.json)? [Gap, Spec §FR-007] → resolvido FR-025
- [ ] CHK028 - O requisito de degradação graciosa (FR-006/FR-019) garante que falha de segurança/validação nunca aborta a onda nem vaza stderr bruto não-sanitizado? [Consistência, Spec §FR-019]

## Privilégio e auditabilidade

- [ ] CHK029 - O contrato suggest-only está expresso como requisito de segurança (sistema nunca troca modelo sem Decisão auditável; operador sempre pode override)? [Clareza, Spec §FR-005]
- [ ] CHK030 - Toda aplicação de modelo (auto/refino/override/fallback) tem requisito de trilha auditável (Decisão + origem), sem caminho silencioso? [Completude, Spec §FR-007, §SC-006]

## Notes

- Marcar items concluídos com `[x]`.
- Cluster de maior risco: validação do override (CHK022-024) e untrusted task-text
  (CHK019-021) — gaps que a feature original não cobre no novo ponto de uso.
</content>
