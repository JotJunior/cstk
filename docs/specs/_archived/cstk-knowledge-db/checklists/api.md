# API / Contracts Checklist: cstk Knowledge DB

**Purpose**: Validar a QUALIDADE dos requisitos de contrato/CLI da feature
`cstk-knowledge-db` — completude, clareza, consistencia e testabilidade dos
contratos `cstk recall`, `--ingest` e `--reindex`. Cobre flags, exit codes,
proveniencia, idempotencia de upsert e degradacao. Valida REQUISITOS, nao codigo.
**Created**: 2026-05-23
**Feature**: [spec.md](../spec.md) | [cstk-recall.md](../contracts/cstk-recall.md) | [ingest-helper.md](../contracts/ingest-helper.md)

## Contrato — Modo busca (`cstk recall <query>`)

- [ ] CHK001 - Todas as flags do modo busca (`--project`, `--type`, `--limit`, `--db`) tem obrigatoriedade, default e descricao especificados sem ambiguidade? [Completude, cstk-recall §Modo busca]
- [ ] CHK002 - O conjunto de valores aceitos por `--type` esta especificado como enum fechado (`decision`|`bloqueio`|`retro`|`skill`)? [Clareza, cstk-recall §Modo busca]
- [ ] CHK003 - O requisito de resolucao de default do `--db` (`$CSTK_KNOWLEDGE_DB` → `~/.claude/cstk/knowledge.db`) esta definido sem ambiguidade de precedencia? [Clareza, cstk-recall §Modo busca]
- [ ] CHK004 - O requisito de "nenhum resultado = sucesso (exit 0)" esta declarado explicitamente, distinguindo de erro? [Completude, Spec §FR-013 / cstk-recall §7]
- [ ] CHK005 - O formato de saida com proveniencia (projeto, feature, onda, data, trecho) esta especificado de forma verificavel — legivel E parseavel para inspecao? [Mensurabilidade, Spec §FR-011 / cstk-recall §6]

## Contrato — Modo ingestao (`--ingest`)

- [ ] CHK006 - O requisito enumera exatamente as quatro classes extraidas (`decisoes[]`, `bloqueios_humanos[]`, `retro`, `ondas[].skills_invoked[]`) e suas tabelas-alvo? [Completude, Spec §FR-005 / ingest-helper §4]
- [ ] CHK007 - Os campos de proveniencia comum (`execucao.id`, `short_name`, `projeto_alvo_path`, id da onda, timestamp) estao especificados para todos os registros? [Completude, Spec §FR-003 / ingest-helper §4]
- [ ] CHK008 - O requisito de "fonte intacta" (FR-009) esta declarado de forma verificavel por hash byte-a-byte antes/depois? [Mensurabilidade, Spec §FR-009 / SC-006 / ingest-helper §8]
- [ ] CHK009 - O requisito define o comportamento sobre `state.json` parcial/nao-terminal (processar apenas registros presentes, sem assumir completude)? [Cobertura, Spec §Edge Cases / ingest-helper §Cenarios]

## Idempotencia / Upsert (FR-007, FR-008, SC-002)

- [ ] CHK010 - A chave de identidade de upsert (tupla projeto+feature+onda+tipo+id) esta especificada de forma unica e nao-ambigua? [Clareza, Spec §FR-007 / Key Entities]
- [ ] CHK011 - O requisito distingue claramente upsert (refletir versao mais recente) de insert-only para registros que mudaram (ex: bloqueio respondido)? [Clareza, Spec §FR-008 / §Edge Cases]
- [ ] CHK012 - O requisito de idempotencia e mensuravel — "reingerir N vezes => contagem estavel"? [Mensurabilidade, Spec §SC-002 / ingest-helper §Idempotencia]
- [ ] CHK013 - Para o FTS5, a estrategia de upsert (DELETE por proveniencia+source_id seguido de INSERT na mesma transacao) esta especificada sem ambiguidade transacional? [Clareza, ingest-helper §6]

## Contrato — Modo reconstrucao (`--reindex`)

- [ ] CHK014 - As flags de reindex (`--states-root`, `--db`) tem obrigatoriedade, default e descricao especificados? [Completude, cstk-recall §Modo reconstrucao]
- [ ] CHK015 - O requisito de descoberta de fontes (`**/.claude/feature-00c-state/*/state.json` e `**/.claude/agente-00c-state/state.json`) esta especificado sem ambiguidade de escopo? [Clareza, cstk-recall §Modo reconstrucao]
- [ ] CHK016 - O requisito de equivalencia de conteudo entre reindex e ingestao incremental e mensuravel (mesma consulta => mesmo conjunto)? [Mensurabilidade, Spec §FR-015 / SC-005]
- [ ] CHK017 - A idempotencia de reindex repetido (sem duplicatas) esta declarada como requisito verificavel? [Mensurabilidade, Spec §FR-015 / cstk-recall §Cenarios]

## Exit Codes & Error Contract

- [ ] CHK018 - A tabela de exit codes esta completa e consistente entre busca, ingestao e reindex (0 = sucesso/degradacao; 2 = uso incorreto)? [Consistencia, cstk-recall §Exit codes / ingest-helper §Exit codes]
- [ ] CHK019 - O requisito declara explicitamente que NAO existe exit nao-zero por falha de runtime da camada (toda falha operacional => exit 0 + aviso)? [Clareza, ingest-helper §Exit codes]
- [ ] CHK020 - As condicoes de exit 2 estao enumeradas exaustivamente (flag invalida, `--type` fora do enum, `--limit` nao-inteiro, NUL quando politica=rejeitar)? [Completude, cstk-recall §Exit codes]

## Observabilidade / Saida

- [ ] CHK021 - O contrato de stdout (resumo `ingested: N decisions, ...`) vs stderr (avisos de degradacao) esta especificado de forma consistente? [Consistencia, ingest-helper §Saida]
- [ ] CHK022 - As mensagens de degradacao graciosa (sqlite3 ausente, DB ausente/corrompido, sugestao de --reindex) estao especificadas com conteudo verificavel? [Clareza, cstk-recall §Comportamento]

## Cobertura de cenarios de aceite

- [ ] CHK023 - Cada cenario de aceite (US1 AS1-AS4, US2 AS1-AS4, US3 AS1-AS3, US4 AS1-AS2) tem mapeamento explicito para comportamento de contrato? [Cobertura, cstk-recall §Cenarios / ingest-helper §Cenarios]
- [ ] CHK024 - Os edge cases (caracteres especiais, --limit nao-inteiro, NUL byte) estao representados nas tabelas de cenarios de aceite dos contracts? [Cobertura, cstk-recall §Cenarios / ingest-helper §Cenarios]

## Ambiguities & Gaps

- [ ] CHK025 - Ha definicao de como `--reindex` decide o `--states-root` quando a flag e omitida ("descoberta padrao") — o requisito e suficientemente especifico para teste? [Ambiguity, cstk-recall §Modo reconstrucao]
- [ ] CHK026 - O requisito define o comportamento quando `cstk` esta ausente do PATH na invocacao pelo runtime (degradacao no lado do chamador)? [Gap, ingest-helper §Invocacao]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente (CHK001+) para referencia cruzada
- Foco: contratos CLI, exit codes, proveniencia, idempotencia de upsert
