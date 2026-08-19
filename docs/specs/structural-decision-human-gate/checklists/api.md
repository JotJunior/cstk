# API Checklist: structural-decision-human-gate

**Purpose**: Validar a qualidade dos contratos de interface (CLI POSIX + tool MCP) que esta feature estende — `state-decisions.sh register`, `record_decision`, `briefing-items.sh`, `bloqueios.sh`, `validate-sdd.sh`.
**Created**: 2026-08-19
**Feature**: [spec.md](../spec.md) | [contracts/cli-structural-class.md](../contracts/cli-structural-class.md) | [contracts/mcp-record-decision.md](../contracts/mcp-record-decision.md)

## Contratos e Versionamento

- [x] CHK001 - Cada flag/campo novo esta rotulado inequivocamente como `[EXISTENTE]` ou `[PROPOSTA — a validar na implementacao]`, sem ambiguidade sobre o que ja existe hoje? [Clareza, cli-structural-class.md cabecalho] {auto}
- [x] CHK002 - As flags/campos existentes sao preservados sem alteracao de tipo, obrigatoriedade ou validacao (mudanca estritamente aditiva)? [Compat, cli-structural-class.md "11 flags atuais preservadas"; mcp-record-decision.md linhas 24-34] {auto}
- [x] CHK003 - `briefing-items.sh` e um script novo com teste dedicado exigido pela convencao do repo (`tests/test_briefing-items.sh`, gateado por `--check-coverage`)? [Completude, cli-structural-class.md "Exige tests/test_briefing-items.sh"] {auto}

## Error Handling

- [x] CHK004 - Cada novo codigo de erro (`classe-obrigatoria`, `estrutural-exige-bloqueio`, `consentimento-invalido`, `consentimento-de-outro-assunto`, `eixo-invalido`, `classe-invalida`) tem exit code e descricao definidos sem ambiguidade? [Completude, cli-structural-class.md tabela "Error Responses (novas)"] {auto}
- [x] CHK005 - O contrato declara explicitamente "nada e gravado" para toda recusa (sem escrita parcial seguida de erro)? [Clareza, cli-structural-class.md INV-C3] {auto}
- [x] CHK006 - Os 4 codigos de erro tipados novos do lado MCP (`STRUCTURAL_CLASS_REQUIRED`, `STRUCTURAL_REQUIRES_HUMAN_BLOCK`, `STRUCTURAL_AXIS_INVALID`, `HUMAN_CONSENT_INVALID`) tem paridade semantica 1:1 com os codigos/regras do helper CLI? [Consistencia, mcp-record-decision.md tabela "Error Responses"] {auto}
- [x] CHK007 - A distincao de exit (1 = regra de dominio recusada; 2 = uso incorreto) e aplicada consistentemente aos novos erros (`eixo-invalido`/`classe-invalida` = 2; demais = 1)? [Consistencia, cli-structural-class.md tabela "Error Responses (novas)"] {auto}
- [x] CHK008 - `state-db-schema.sh ensure` declara explicitamente fail-hard (nunca degrada para best-effort) e a justificativa (fonte de verdade transacional)? [Clareza, cli-structural-class.md secao "state-db-schema.sh ensure" "Error Responses"] {auto}
- [x] CHK009 - `briefing-items.sh` declara exit 0 mesmo em todo caso degradado (briefing ausente/ilegivel/sem tabela), delegando a decisao ao orquestrador em vez de falhar a onda? [Clareza, cli-structural-class.md secao briefing-items.sh "Error Responses"] {auto}
- [x] CHK010 - O finding M2 corrigido (distinguir "briefing ausente" de "sem itens Alto", antes ambos stdout vazio) esta descrito com o contraste antes/depois? [Clareza, cli-structural-class.md "Response" de briefing-items.sh] {auto}

## Idempotencia e Efeitos Colaterais

- [x] CHK011 - `state-db-schema.sh ensure` e declarado idempotente (consulta `PRAGMA table_info` antes de `ALTER TABLE`)? [Completude, cli-structural-class.md INV-E1] {auto}
- [x] CHK012 - O contrato declara que `ensure` e puramente aditivo (nunca `DROP`, nunca recriacao, nunca reescrita de linha)? [Completude, cli-structural-class.md INV-E2] {auto}
- [x] CHK013 - O caminho de leitura esta explicitamente isolado de qualquer emissao de DDL (correcao do finding M3), preservando operacoes read-only sem exigir permissao de escrita? [Completude, cli-structural-class.md INV-E3, INV-E4] {auto}

## Validacao de Entrada / Sanitizacao

- [x] CHK014 - Cada celula extraida do briefing por `briefing-items.sh` e saneada (NUL/TAB/CR/LF removidos, whitespace colapsado) antes de compor a linha TSV, prevenindo injecao de colunas extras (finding L1)? [Seguranca, cli-structural-class.md INV-B4] {auto}
- [x] CHK015 - Nenhum campo novo do lado MCP e texto livre — `decision_class`/`structural_axis` sao enum fechado, `human_consent_block_id` e formato de id gerado pelo runtime, `subject_key` tem prefixo fechado + sufixo derivado por funcao pura (fecha superficie de injecao LLM01)? [Seguranca, mcp-record-decision.md INV-M3] {auto}
- [x] CHK016 - A validacao de formato (zod) e explicitamente distinguida da validacao de autoridade/existencia (helper contra o estado) para `human_consent_block_id`, evitando a falsa impressao de que a tool MCP sozinha e suficiente? [Clareza, mcp-record-decision.md INV-M4, secao "Defesa em profundidade"] {auto}

## Consistencia entre Portas (CLI x MCP)

- [x] CHK017 - Existe teste de paridade dedicado (`exec-mapper-parity.test.ts`) que gateia a adicao de campo novo, exigindo entrada em `FIELD_TO_FLAG_TABLE` E a flag literal no codigo-fonte? [Completude, mcp-record-decision.md INV-M2] {auto}
- [x] CHK018 - O mapeamento campo->flag para os 3 campos novos de `record_decision` e para `subject_key`/`register_human_block` esta totalmente especificado (nenhum campo orfao)? [Completude, mcp-record-decision.md "Mapeamento campo -> flag"] {auto}
- [x] CHK019 - O contrato reafirma que nenhum campo novo atravessa shell (execFile com argv array), preservando a garantia SEC-H1 ja documentada no CLAUDE.md do projeto? [Consistencia, mcp-record-decision.md "Mapeamento campo -> flag" ultimo paragrafo] {auto}

## Retrocompatibilidade

- [x] CHK020 - `bloqueios.sh register`/`list` preservam o TSV de `list` sem mudar de colunas (a flag nova so filtra linhas), evitando quebrar consumidores existentes? [Compat, cli-structural-class.md secao bloqueios.sh "Response"] {auto}
- [x] CHK021 - Bloqueios anteriores a esta feature (`subject_key` NULL) tem comportamento de degradacao explicito e seguro (nunca casam, sempre perguntam de novo)? [Compat, cli-structural-class.md INV-K1] {auto}
- [x] CHK022 - `validate-sdd.sh` preserva o formato literal de saida (`FINDING|...`, `RESULT|...`) e nenhum finding existente muda de codigo/severidade/mensagem? [Compat, cli-structural-class.md secao validate-sdd.sh INV-V1] {auto}
- [x] CHK023 - Os dois novos findings de `validate-sdd.sh` sao escopados apenas a `plan.md` (guarda `_is_plan_md`), preservando comportamento para os demais artefatos (`research.md`, `data-model.md`, `quickstart.md`, `contracts/*.md`)? [Compat, cli-structural-class.md INV-V2] {auto}

## Fronteira de Fabricacao (Principio VI)

- [x] CHK024 - O validador de plano e explicitamente proibido de "resolver" ou fabricar fonte — sem link/anchor resolvido, o finding e sempre `warning`, nunca `error`? [Constitution VI, cli-structural-class.md INV-V3] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`)
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto
- Todos os 24 items foram resolviveis por evidencia citavel nos dois contratos
  (`contracts/cli-structural-class.md`, `contracts/mcp-record-decision.md`); os
  contratos sao densos em invariantes explicitas (INV-*), o que reduziu a
  necessidade de items `{humano}` neste dominio.
