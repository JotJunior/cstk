# Security Checklist: Recall Memory Mirror

**Purpose**: Validar qualidade dos requisitos de seguranca — ingestao de conteudo UNTRUSTED
(scrub, injection FTS5/SQL), imutabilidade do `.md` fonte, separacao de tabelas, e rotulagem de
confianca no consumo.
**Created**: 2026-05-27
**Feature**: [spec.md](../spec.md) | Plan: [plan.md](../plan.md) | Research: [research.md](../research.md)

## Protecao de Dados e Scrub

- [x] CHK011 - O `body_scrubbed` e filtrado por `secrets-filter.sh` ANTES do INSERT (nao pos)? [Completude, Spec §FR-005, research.md Decision 5] {auto}
  > Evidencia: Research Decision 5: "`recall_scrub` chamado ANTES de gravar". Contrato Cmd 3 fluxo: `body = recall_scrub(conteudo do .md)` antes do upsert.

- [x] CHK012 - A `description` (1a linha nao-vazia do `.md`) tambem e scrubbed antes de gravar? [Completude, Spec §FR-005, data-model.md] {auto}
  > Evidencia: Research Decision 5: "A descricao tambem e scrubbed." Data-model campo description: "passada por `recall_scrub`".

- [x] CHK013 - O campo `path` (absoluto do `.md`) e reconhecido como estruturado (nao scrubbed), mas passa por `sql_escape`? Risco low documentado? [Clareza, plan.md §Riscos] {auto}
  > Evidencia: Data-model campo path: "passa por `sql_escape` como todo valor". Plan riscos: "`path` poderia conter nome de dir sensivel; aceito por paridade c/ telemetria; registrado." Risco low documentado (dec-011).

- [x] CHK019 - O scrub e aplicado tanto no `--ingest` quanto no `--reindex` (funcao compartilhada)? [Consistencia, Spec §FR-005/FR-009] {auto}
  > Evidencia: Research Decision 6: "a varredura de reindex chama `recall_ingest_memories` (ou helper de baixo nivel compartilhado)". Scrub fica no helper, nao duplicado entre modos.

## Input Validation e Injection

- [x] CHK014 - Conteudo adversarial em `.md` (injection FTS5 / SQL) tem mitigacao documentada? [Completude, Spec §Edge Cases, research.md Decision 5] {auto}
  > Evidencia: Research Decision 5: "body via `recall_scrub` + `sql_escape`; conteudo e documento (nao query), nao precisa fts_phrase_escape". Spec Edge Cases confirma.

- [x] CHK017 - Bytes NUL e de controle em `.md` tem mitigacao por reuso de `strip_nul` existente? [Cobertura, plan.md §Riscos] {auto}
  > Evidencia: Plan riscos: "`strip_nul` (politica de ingestao ja existente) reusado no caminho de memorias; recomendado cobrir em M8/M10." Mitigacao por reuso, nao nova logica.

## Confianca e Rotulagem (Trust Label)

- [x] CHK015 - O requisito de rotulagem UNTRUSTED para conteudo de `memory` no read-back loop esta documentado? [Completude, Spec §FR-005, ASI06/ASI09/LLM01] {auto}
  > Evidencia: Plan riscos: "conteudo `.md` e UNTRUSTED; mitigacao: (a) scrub no ingest; (b) consumidor rotula como UNTRUSTED/nao-autoritativo". Contrato Cmd 1: trust label explicito (ASI09/LLM01).

- [ ] CHK020 - A ausencia de auth no `knowledge.db` local esta documentada como decisao de escopo (ferramenta dev local, sem multi-usuario)? [Assumption, Spec §Constraints C-005] {humano}
  > Contexto: O modelo de ameacas de acesso fisico ao `~/.claude/cstk/knowledge.db` nao esta explicitamente marcado como fora-de-escopo. Para uma ferramenta dev local single-user e razoavel, mas e uma decisao de apetite de risco que cabe ao dono do produto confirmar.

## Imutabilidade e Separacao

- [x] CHK016 - O arquivo `.md` fonte esta protegido contra escrita por requisito MUST explicito? [Completude, Spec §FR-005, C-002] {auto}
  > Evidencia: Spec FR-005: "O arquivo `.md` original MUST permanecer intocado (read-only)". C-002: "acesso e estritamente read-only".

- [x] CHK018 - A separacao entre `memories` e telemetria (C-003) e verificavel e coberta por teste? [Consistencia, Spec §C-003, FR-015] {auto}
  > Evidencia: Spec FR-015 exige teste de criacao da tabela `memories`. Research Decision 1: separacao por design arquitetural (tabela dedicada, `type` discriminador no FTS). O plano de testes M1-M18 cobre isso.

## Notes

- Items `{auto}` resolvidos com evidencia citada; `{humano}` aguarda decisao do dono do produto
- **9 de 10 items passaram** — todos os requisitos de seguranca tecnica estao documentados
- **CHK020** `{humano}`: confirmar que "sem auth no DB local" e decisao consciente de escopo (nao gap nao visto)
- Se CHK020 for confirmado, nenhum gap de seguranca bloqueante neste dominio
