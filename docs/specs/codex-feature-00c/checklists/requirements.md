# Requirements Checklist: Pipeline CSTK no Codex

**Purpose**: qualidade de escopo, requisitos, cenários e critérios; não teste do código.
**Created**: 2026-10-02
**Feature**: [spec.md](../spec.md)

## Completude

- [x] CHK001 - As seis entradas e a seleção de instalação estão explicitadas? [Completude, Spec FR-001..002; Story 1] {auto}
- [x] CHK002 - As sequências de feature/projeto/roadmap têm limites identificados? [Completude, Spec FR-005..006; Story 2] {auto}
- [x] CHK003 - Retomada, bloqueio e aborto possuem critérios observáveis? [Completude, Spec FR-009..012; Story 3] {auto}
- [x] CHK004 - Conhecimento compartilhado e transferência estão diferenciados? [Completude, Spec FR-013..016; Stories 4..5] {auto}

## Clareza e consistência

- [x] CHK005 - A ausência de resposta está diferenciada de consentimento negativo? [Clareza, Spec FR-008; Edge Cases] {auto}
- [x] CHK006 - Conclusão de etapa exige evidência e gate, não apenas existência de arquivo? [Clareza, Spec FR-007; Story 2 cenário 4] {auto}
- [x] CHK007 - Estado terminal e repetição estão definidos para resume/abort? [Consistência, Spec FR-009..011; Edge Cases] {auto}
- [x] CHK008 - Proveniência/métricas desconhecidas têm regra sem fabricação? [Clareza, Spec FR-014; Story 4 cenário 3] {auto}

## Cenários e critérios de aceite

- [x] CHK009 - Cada FR tem cenário ou edge case com referência explícita? [Cobertura, Spec User Scenarios & Testing; Functional Requirements] {auto}
- [x] CHK010 - Outcomes medem ações/resultados e não linguagem/framework? [Mensurabilidade, Spec SC-001..006] {auto}
- [x] CHK011 - Descoberta, fixtures e homologação real são diferenciadas? [Consistência, Spec FR-017; Story 6] {auto}
- [x] CHK012 - Preservação de personalizações e falhas de instalação estão especificadas? [Cobertura, Spec FR-003; Story 1; Edge Cases] {auto}

## Dependências, segurança e governança

- [x] CHK013 - Escritor único, confinamento e recuperação explícita estão definidos? [Segurança, Spec FR-012; Story 3 cenário 4] {auto}
- [x] CHK014 - Revisão humana das proteções é independente de instalação/opt-ins? [Segurança, Spec FR-004; Story 1 cenário 3] {auto}
- [x] CHK015 - Conflito de governança tem critério de resolução em vez de aprovação implícita? [Completude, Spec FR-018; Plan Constitution Check] {auto}
- [ ] CHK016 - Qual alternativa deve resolver a regra constitucional do adaptador? [Decisão, Plan Constitution Check II; contracts/governance-proposal.md; task 7.1] {humano}

## Notes

15 itens automáticos resolvidos contra os artefatos citados; um humano aberto.
CHK016 virou tarefa de governança 7.1; não é marcação de homologação nem pedido
redundante de autorização para editar documentos. Nenhum item humano foi
marcado pelo agente. Perguntas de opt-in do piloto não são checklists de qualidade.
