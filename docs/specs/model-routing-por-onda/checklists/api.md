# API/Contract Checklist: model-routing-por-onda

**Purpose**: validar a QUALIDADE dos requisitos do contrato de CLI dos subcomandos
(`wave-select`, `phase-model-lookup`), do mapa fase→modelo e da integração de spawn
— não a implementação deles.
**Created**: 2026-05-24
**Feature**: [spec.md](../spec.md)

## Completude do contrato de I/O

- [ ] CHK001 - O formato de saída de `wave-select` está especificado para TODOS os resultados possíveis (haiku/sonnet/opus/manter-atual)? [Completude, contracts/wave-select.md]
- [ ] CHK002 - Os exit codes estão definidos para todas as condições (sucesso, fallback, uso incorreto), e está explícito que indisponibilidade do model-selector nunca gera exit ≠ 0? [Completude, Spec §FR-006]
- [ ] CHK003 - O contrato define quando `--task-text` é usado vs ignorado (só execute-task)? [Clareza, contracts/wave-select.md]
- [ ] CHK004 - O comportamento de `phase-model-lookup` para fase desconhecida está especificado (→ manter-atual)? [Completude, data-model.md]
- [ ] CHK005 - O formato do arquivo `phase-model-map.txt` (colunas, enums de faixa/modelo) está definido sem ambiguidade? [Clareza, data-model.md]

## Versionamento e compatibilidade

- [x] CHK006 - FR-014 diz "default versionado" — o mecanismo de versionar o mapa fase→modelo está definido (onde mora a versão, como evolui)? [Gap, Spec §FR-014] → resolvido FR-020
- [x] CHK007 - A coexistência com Decisões de model-routing legadas (audit-only, escolha=fallback-default) está especificada — o agregador trata ambos os formatos? [Gap, Spec §FR-012] → resolvido FR-021
- [ ] CHK008 - O requisito de BREAKING/MAJOR (FR-017) especifica o que exatamente muda no contrato observável para quem consome as Decisões? [Clareza, Spec §FR-017]

## Consistência de campos da Decisão

- [ ] CHK009 - Os campos da DecisãoDeRoteamentoPorOnda (sugerido, aplicado, origem, score) estão enumerados de forma consistente entre spec, data-model e contract? [Consistência, data-model.md]
- [ ] CHK010 - O enum de `origem` (mapa/refino/override-operador/fallback) é exaustivo e mutuamente exclusivo? [Clareza, data-model.md]
- [ ] CHK011 - A regra "sugerido≠aplicado só com origem∈{override,fallback}" (SC-006) é consistente com todos os fluxos descritos no state-transition? [Consistência, Spec §SC-006]

## Idempotência e integração de spawn

- [ ] CHK012 - O requisito de idempotência por onda (FR-008) especifica a chave (onda) e o que conta como "já decidido"? [Clareza, Spec §FR-008]
- [ ] CHK013 - A integração de command especifica que `manter-atual` → omitir o param `model` (não passar string "manter-atual" ao spawn)? [Clareza, contracts/wave-select.md]
- [ ] CHK014 - O requisito de aplicar model no spawn de clarify (FR-003) define a condição exata (score≥2 E não-fallback E spawn real ocorre)? [Completude, Spec §FR-003]
- [ ] CHK015 - O comportamento na degradação inline do clarify (FR-004) está especificado como "não aplicar + sem Decisão órfã"? [Completude, Spec §FR-004]

## Mensurabilidade dos critérios

- [ ] CHK016 - SC-008 (taxa de indeterminado ≤25%) define o corpus de referência de forma que a métrica seja objetivamente verificável? [Mensurabilidade, Spec §SC-008]
- [ ] CHK017 - SC-001 (redução ≥30% no tempo de ondas mecânicas) define o baseline de comparação de forma reproduzível? [Mensurabilidade, Spec §SC-001]
- [ ] CHK018 - Os subcomandos novos têm requisito explícito de cobertura de teste (convenção orphan-check)? [Completude, plan.md §Project Structure]

## Notes

- Marcar items concluídos com `[x]`.
- CHK006 e CHK007 são gaps prováveis — vale resolver antes de `/create-tasks`.
</content>
