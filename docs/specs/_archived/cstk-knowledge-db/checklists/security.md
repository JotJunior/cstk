# Security Checklist: cstk Knowledge DB

**Purpose**: Validar a QUALIDADE dos requisitos de seguranca da feature
`cstk-knowledge-db` — completude, clareza, testabilidade e ausencia de
ambiguidade. Cobre injection (A05/CWE-89), os 2 hardenings ratificados em
dec-015 (--limit integer-validate; NUL bytes), filtragem de segredos,
privacidade local e degradacao graciosa. Valida os REQUISITOS, nao o codigo.
**Created**: 2026-05-23
**Feature**: [spec.md](../spec.md) | [cstk-recall.md](../contracts/cstk-recall.md) | [ingest-helper.md](../contracts/ingest-helper.md)

## Input Validation & Injection (A05 / CWE-89)

- [ ] CHK001 - O requisito de que NENHUMA entrada do usuario seja interpolada crua na sintaxe SQL/FTS5 esta declarado de forma absoluta (sem excecoes)? [Completude, Spec §Edge Cases / cstk-recall §4]
- [ ] CHK002 - A obrigacao de escaping de DUAS camadas (SQL `'`→`''` E FTS5 frase `"`→`""`) esta especificada como cumulativa e nao alternativa? [Clareza, cstk-recall §4]
- [ ] CHK003 - O requisito define explicitamente que o `sqlite3` CLI NAO oferece bind nativo via argv, justificando por que escaping (e nao bind) e a defesa primaria? [Completude, cstk-recall §4]
- [ ] CHK004 - Os operadores FTS5 a serem neutralizados pela camada de frase (`*`, `:`, `^`, `-`, parenteses, AND/OR/NOT) estao enumerados explicitamente no requisito? [Clareza, cstk-recall §4]
- [ ] CHK005 - O requisito de escaping cobre TODOS os campos extraidos na ingestao, incluindo proveniencia (ex: `projeto_alvo_path`, `source_id`), nao apenas texto livre? [Completude, ingest-helper §6]
- [ ] CHK006 - Existe um requisito mensuravel de que payloads adversariais (`'; DROP TABLE ...; --`) sejam armazenados/comparados literalmente sem efeito de injecao? [Mensurabilidade, cstk-recall §134 / ingest-helper §6]

## Hardening dec-015 — `--limit` integer-validate

- [ ] CHK007 - O requisito distingue claramente que `--limit` e integer-validado (rejeitar) e NAO string-escapado, com justificativa (LIMIT recebe inteiro sintatico)? [Clareza, cstk-recall §72-74]
- [ ] CHK008 - O padrao de validacao de `--limit` esta especificado de forma verificavel (`^[1-9][0-9]*$`) e o conjunto de rejeitos exemplificado (`5; DROP`, `abc`, `-1`, `0`, `1.5`, vazio)? [Mensurabilidade, cstk-recall §85-86]
- [ ] CHK009 - O comportamento em valor invalido de `--limit` (exit 2, antes de compor o SQL) esta definido sem ambiguidade? [Clareza, cstk-recall §Exit codes]
- [ ] CHK010 - Existe requisito de cobertura de teste para `--limit` nao-inteiro como cenario de aceite? [Cobertura, cstk-recall §Cenarios de aceite]

## Hardening dec-015 — NUL bytes

- [ ] CHK011 - O requisito de tratamento de NUL bytes cobre TODOS os inputs do usuario em `recall` (`<query>`, `--project`, `--type`, `--db`)? [Completude, cstk-recall §4a]
- [ ] CHK012 - O requisito de tratamento de NUL bytes na ingestao cobre TODOS os valores extraidos (texto livre E proveniencia)? [Completude, ingest-helper §6]
- [ ] CHK013 - A justificativa do risco de NUL (truncamento de string em C / sqlite3 CLI / jq, possivel bypass de filtro) esta declarada no requisito? [Clareza, cstk-recall §4a / ingest-helper §6]
- [ ] CHK014 - A assimetria de politica esta especificada sem conflito — `recall` rejeita (exit 2) no boundary CLI; `ingest` stripa (exit 0, best-effort)? [Consistencia, cstk-recall §4a vs ingest-helper §6]
- [ ] CHK015 - O requisito garante que NUL nunca chega intacto a camada SQL/FTS5, independentemente da politica escolhida? [Completude, cstk-recall §4a / ingest-helper §6]
- [ ] CHK016 - Existe requisito de fixture de teste com byte cru NUL em escape OCTAL (`\000`, nunca hex) cobrindo texto livre e proveniencia? [Cobertura, ingest-helper §Cenarios / Spec §FR-022]

## Secrets / Data Protection (FR-017)

- [ ] CHK017 - O requisito de scrub de segredos especifica EXATAMENTE quais campos sao filtrados (texto livre: justificativa/contexto/evidencia, pergunta/contexto-para-resposta, texto de retros)? [Clareza, Spec §FR-017]
- [ ] CHK018 - O requisito especifica explicitamente quais campos NAO passam pelo filtro (ids, scores, timestamps, proveniencia, nomes de skill) e por que (preservar chave de upsert)? [Completude, Spec §FR-017 / FR-007]
- [ ] CHK019 - O requisito de confinamento do uso de `secrets-filter.sh` a um unico arquivo (`cli/lib/recall.sh`) esta declarado e rastreado ao Principio II? [Consistencia, Spec §FR-017 / FR-020]
- [ ] CHK020 - Existe requisito mensuravel de que dado sensivel em texto livre seja scrubbed enquanto a chave de proveniencia permanece intacta (edge case "dado sensivel")? [Mensurabilidade, Spec §Edge Cases]

## Privacy / Local-only (Principio IV)

- [ ] CHK021 - O requisito de que NENHUM dado seja transmitido para fora do ambiente local esta declarado de forma absoluta? [Completude, Spec §FR-017]
- [ ] CHK022 - O requisito confirma zero rede / zero servidor como invariante da feature (nao apenas como detalhe de implementacao)? [Clareza, plan §Technical Context]

## Graceful Degradation as Security Invariant (FR-018, FR-019)

- [ ] CHK023 - O requisito define que falha da camada de conhecimento NUNCA aborta uma onda do orquestrador, cobrindo: dep ausente, indice corrompido, dir nao-gravavel, lock persistente? [Completude, Spec §FR-018]
- [ ] CHK024 - O requisito de degradacao graciosa exige cobertura por teste automatizado (FR-019), nao apenas afirmacao? [Mensurabilidade, Spec §FR-019]
- [ ] CHK025 - A semantica de exit codes esta consistente entre os dois contracts — exit 0 para degradacao graciosa, exit 2 reservado a erro de USO? [Consistencia, cstk-recall §Exit codes / ingest-helper §Exit codes]

## Concurrency Safety (FR-016)

- [ ] CHK026 - O requisito de seguranca de escritas concorrentes (WAL + busy_timeout + retry/backoff) esta especificado de forma a impedir corrupcao OU perda de registro? [Completude, Spec §FR-016]
- [ ] CHK027 - O requisito proibe explicitamente reaproveitar o lock transacional do runtime (`state-lock.sh`) e justifica (evitar acoplamento/estagnacao)? [Clareza, Spec §FR-016 / ingest-helper §7]

## Ambiguities & Gaps

- [ ] CHK028 - Para NUL byte na ingestao, ha ambiguidade entre "strip" no contract e a possibilidade de NUL em campo-chave de upsert corromper a identidade de proveniencia? [Ambiguity, ingest-helper §6 vs FR-007]
- [ ] CHK029 - O requisito define o comportamento quando `secrets-filter.sh` esta ausente/falha (a propria ferramenta de scrub e dependencia)? [Gap, Spec §FR-017]

## Notes

- Marcar items concluidos com `[x]`
- Items numerados sequencialmente (CHK001+) para referencia cruzada
- Foco: injection (A05/CWE-89), hardenings dec-015, scrub de segredos, degradacao graciosa
