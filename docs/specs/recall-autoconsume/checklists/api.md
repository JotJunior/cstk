# API / Contract Checklist: recall-autoconsume

**Purpose**: Validar a QUALIDADE dos requisitos do contrato do modo
`cstk recall --context` (a "API" da feature e a CLI/contrato de saida). Foco na
clareza, completude e testabilidade do contrato de flags + formato de saida —
nao na implementacao. "Unit tests for English."
**Created**: 2026-05-23
**Feature**: [spec.md](../spec.md) · [contracts/cstk-recall-context.md](../contracts/cstk-recall-context.md)

## Contrato de modo e flags

- [ ] CHK001 - A spec define que `--context` e um modo DISTINTO de `busca`,
  `--ingest` e `--reindex`, e que adiciona-lo NAO altera o comportamento dos modos
  existentes (camada aditiva)? [Completude, Spec §FR-001, §FR-019]
- [ ] CHK002 - Sao especificadas todas as flags do modo (`--limit`,
  `--exclude-feature`, `--type`, `--project`, `--db`, `--max-bytes`) com seus
  defaults e semantica? [Completude, Spec §FR-004, §FR-006]
- [ ] CHK003 - O default de `--limit` e quantificado dentro da faixa pequena
  definida (3-5; plan fixa 4) e o requisito justifica a escolha como controle de
  ruido? [Clareza, Spec §FR-004]
- [ ] CHK004 - O requisito de teto de tamanho `--max-bytes` (default 2000) e
  quantificado e descreve a interacao entre o teto por NUMERO de achados e o teto
  por TAMANHO total (qual prevalece quando colidem)? [Clareza, Spec §FR-006]
- [ ] CHK005 - Os requisitos definem o comportamento para valores invalidos de
  flag (`--limit` nao-numerico/negativo, `--max-bytes` zero, `--type` desconhecido)
  — rejeicao explicita vs no-op? [Edge Case, Gap]

## Formato de saida (ContextBlock)

- [ ] CHK006 - A spec especifica que a saida e um BLOCO MARKDOWN enxuto, de
  formato ESTAVEL e parseavel/injetavel, distinto do formato verboso do modo busca?
  [Clareza, Spec §FR-001, §US2]
- [ ] CHK007 - Cada achado tem requisito de proveniencia COMPLETA e compacta
  (projeto, feature, onda, data), com formato 1-linha/achado definido? [Completude, Spec §FR-003]
- [ ] CHK008 - O requisito de ordenacao por relevancia (`bm25 ASC`, mais relevante
  primeiro) e explicito e consistente com a decisao de NAO aplicar piso de bm25
  (FR-007)? [Consistencia, Spec §FR-007]
- [ ] CHK009 - A spec define o contrato de saida para o caso de zero achados:
  stdout VAZIO + exit de sucesso (no-op), em vez de bloco vazio ou mensagem? [Clareza, Spec §FR-012, §US2-3]

## Composicao de termos (OR) e derivacao

- [ ] CHK010 - O requisito de composicao dos termos esta resolvido (OR, nao AND
  implicito) com justificativa empirica registrada (AND=0 matches, OR=43) e
  rastreavel ao plan/research? [Clareza, Spec §FR-009, plan §Summary]
- [ ] CHK011 - A spec define a fonte primaria (`aspectos_chave_iniciais`) vs
  fallback (`descricao_curta`) e a condicao EXATA de fallback (aspectos vazio/
  degenerado), sem concatenar ambos por padrao? [Clareza, Spec §FR-009]
- [ ] CHK012 - O teto de termos (<=8) e o passo de `fts_query_escape` reaproveitado
  sao requisitos explicitos e mensuraveis? [Mensurabilidade, Spec §FR-009, §FR-002]
- [ ] CHK013 - O requisito de NAO duplicar logica de escaping/query (reaproveitar
  `fts_query_escape` + `recall_resolve_db`) e verificavel (ex: grep por logica
  duplicada)? [Mensurabilidade, Spec §FR-002]

## Anti-eco e filtros

- [ ] CHK014 - O contrato `--exclude-feature` define inequivocamente o criterio de
  match de proveniencia que omite registros da feature corrente (SC-002 = 0% eco)?
  [Clareza, Spec §FR-005]
- [ ] CHK015 - Os filtros reaproveitados (`--type`, `--project`) tem semantica
  consistente com os filtros ja existentes do modo busca (FR-012 da spec
  arquivada)? [Consistencia, Spec §FR-004]

## Degradacao no contrato

- [ ] CHK016 - A spec define o contrato de exit/stdout para cada modo de
  degradacao (sem `sqlite3`, sem `jq`, db ausente, db corrompido, "database is
  locked"): sempre exit de sucesso + stdout vazio + sem stack trace? [Cobertura, Spec §FR-012, §US3]
- [ ] CHK017 - O requisito de resolucao de helpers via `CSTK_LIB` (nao so
  `~/.claude`) faz parte do CONTRATO testavel com `HOME` falso (SC-005)? [Mensurabilidade, Spec §FR-020, §SC-005]

## Integracao orquestrador (consumidor do contrato)

- [ ] CHK018 - A spec especifica que o passo PRE-DECISAO so consome o modo nas
  fases `specify` e `plan` (FR-010), com o contrato de quando NAO chamar tao claro
  quanto o de quando chamar? [Clareza, Spec §FR-010]
- [ ] CHK019 - O requisito define como o orquestrador passa a feature corrente ao
  `--exclude-feature` (FR-011) de forma que a exclusao anti-eco seja efetiva na
  pratica do consumidor, nao apenas no modo isolado? [Cobertura, Spec §FR-011]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente para referencia
- O contrato formal vive em `contracts/cstk-recall-context.md`; este checklist
  valida se os REQUISITOS que originam o contrato sao completos e nao-ambiguos.
