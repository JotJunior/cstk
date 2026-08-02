# API Checklist: state-mcp-server (contrato das tools MCP)

**Purpose**: validar a QUALIDADE dos requisitos do contrato de ferramentas MCP
de mutacao de estado — completude do conjunto de tools, clareza das rejeicoes,
mensurabilidade dos criterios de aceite e cobertura da borda Node ↔ POSIX.
NAO valida implementacao (nao ha codigo).
**Created**: 2026-08-01
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [contracts/mcp-tools.md](../contracts/mcp-tools.md)
**Numeracao**: CHK001–CHK027 (IDs unicos por feature; continuam em `security.md` e `operational.md`)

## Completude do conjunto de tools

- [x] CHK001 - O requisito enumera nominalmente TODAS as categorias de mutacao que devem ter tool correspondente? [Completude, Spec §FR-001] {auto} — FR-001 lista 6 categorias (decisao auditavel, abrir onda, fechar onda, resultado de task, bloqueio humano, invocacao de skill/gate).
- [x] CHK002 - Ha correspondencia 1:1 entre as categorias de FR-001 e as tools do contrato, sem tool orfa nem categoria sem tool? [Consistencia, contracts/mcp-tools.md §Tool:*] {auto} — 6 tools definidas: `record_decision`, `open_wave`, `close_wave`, `record_task`, `register_human_block`, `record_skill`.
- [x] CHK003 - O contrato declara explicitamente o que NAO vira tool, evitando expansao implicita de escopo? [Completude, contracts/mcp-tools.md §Nao-tools (fora de escopo deliberado)] {auto}
- [x] CHK004 - Ha requisito definindo evolucao/versionamento do contrato de tools (o que acontece quando um `inputSchema` muda e um orquestrador antigo chama a versao nova)? [Gap] {auto} — resolvido na task 3.5: `contracts/mcp-tools.md` §Versionamento de contrato (SemVer via `SERVER_VERSION`; aditivo=PATCH/MINOR, breaking=MAJOR+CHANGELOG; SDK valida schema antes do handler ⇒ falha deterministica, nunca silenciosa).

## Clareza e nao-ambiguidade

- [x] CHK005 - O formato de resposta comum esta definido para TODAS as tools, cobrindo aceite e rejeicao? [Clareza, contracts/mcp-tools.md §Forma geral] {auto} — campos `outcome`, `reason`, `stage`, `result`.
- [x] CHK006 - O ponto de falha de uma rejeicao e atribuivel a exatamente um estagio, sem sobreposicao? [Clareza, contracts/mcp-tools.md §Forma geral] {auto} — `stage` ∈ `schema|precondition|delegation|null`.
- [x] CHK007 - O criterio de "motivo acionavel" de FR-009 e objetivamente verificavel? [Ambiguity, Spec §FR-009] {auto} — resolvido na task 3.3: `contracts/mcp-tools.md` §Criterio de equivalencia de `reason` (FR-009 / CHK007) define 3 condicoes verificaveis (cobertura de invariante 1:1 com citacao, preservacao do identificador via padrao `${code}: ${diagnostico-do-helper}`, estagio correto) + teste de conformidade nao subjetivo.
- [x] CHK008 - O limiar de "evidencia" que FR-002 exige para score 3 esta quantificado em algum artefato, e nao apenas nomeado? [Clareza, Spec §FR-002 + plan.md §Summary(1)] {auto} — plan fixa "score 3 ⇒ evidencia >= 20 chars", herdado da trava ja existente em `state-decisions.sh`.
- [x] CHK009 - A chave que torna `record_task` idempotente esta explicita (e nao apenas "por identificador de task")? [Clareza, contracts/mcp-tools.md §record_task §Base da idempotencia] {auto} — PK `(execution_id, task_id)` em `task_outcome` [VERIFICADO]; resposta expoe `result.operation` ∈ `inserted|updated` como evidencia do upsert.
- [x] CHK010 - Os identificadores (`session_id`, `task_id`, `wave_id`) tem regra de formato declarada, em vez de serem texto livre? [Clareza, contracts/mcp-tools.md §SEC-M2] {auto} — allowlist por regex no `inputSchema`; nenhum id pode iniciar com `-`.

## Consistencia entre artefatos

- [x] CHK011 - As convencoes de borda (case style e idioma) estao tabeladas por camada, com uma unica fonte de verdade por camada? [Consistencia, plan.md §Convencoes de Borda] {auto} — payload `snake_case`/ingles, flags dos helpers `--kebab-case`/portugues, colunas `snake_case`/ingles.
- [x] CHK012 - Existe um unico ponto autorizado a traduzir campo da tool → flag do helper? [Consistencia, plan.md §Convencoes de Borda] {auto} — `mcp/state-server/src/runtime/exec.ts`, tabela explicita (`evidence` → `--evidencia`, `rationale` → `--justificativa`), sem mapeamento automatico.
- [x] CHK013 - Cada tool declara para qual primitiva POSIX delega, com as flags correspondentes? [Rastreabilidade, contracts/mcp-tools.md §Tool:* "Delega para [VERIFICADO]"] {auto}

## Cobertura de rejeicoes e edge cases

- [x] CHK014 - O conjunto de codigos de erro comuns a todas as tools esta enumerado e fechado? [Completude, contracts/mcp-tools.md §Erros comuns] {auto} — `SESSION_MISMATCH`, `EXECUTION_TERMINAL`, `HELPER_FAILED`, alem dos especificos por tool.
- [x] CHK015 - O requisito cobre chamada fora de ordem (registrar task sem onda aberta) exigindo rejeicao sem side-effect parcial? [Cobertura, Spec §Edge Cases + contracts §record_task `NO_OPEN_WAVE` + quickstart Scenario 3] {auto}
- [ ] CHK016 - Toda invariante citada por FR-009 tem codigo de rejeicao correspondente no contrato? [Gap, Spec §FR-009 vs contracts/mcp-tools.md §record_task §Errors] {auto} — FR-009 cita "registrar task referenciando uma onda inexistente" como invariante a rejeitar, mas `record_task` aceita `wave_id` opcional (default: onda corrente) e enumera apenas `NO_OPEN_WAVE` (ausencia de onda aberta) e `TESTS_PASSED_EXCEEDS_RUN` — nao ha codigo para `wave_id` explicito inexistente.
- [x] CHK017 - Ha requisito para o caso de mutacao sobre execucao ja terminal? [Cobertura, contracts/mcp-tools.md §Erros comuns] {auto} — `EXECUTION_TERMINAL` para `status ∈ abortada|concluida`.
- [x] CHK018 - O risco de campo OPCIONAL que existe no schema mas nunca chega ao helper (falha silenciosa) tem cobertura de cenario declarada? [Cobertura de edge cases, plan.md §Convencoes de Borda + §Riscos(5) + quickstart Scenario 9] {auto} — Scenario 9 preenche todos os opcionais e compara campo a campo nos dois backends.
- [x] CHK019 - As pos-condicoes que compoem a atomicidade de `close_wave` estao enumeradas exaustivamente? [Completude, Spec §FR-003] {auto} — motivo de termino, hash recalculado, backup gerado.
- [x] CHK020 - O "nunca parcialmente fechada" tem criterio observavel definido, e nao so a afirmacao de atomicidade? [Mensurabilidade, plan.md §Fases F4 + quickstart Scenario 5] {auto} — atomicidade por pre-imagem + compensacao (research D3), verificada pelo Scenario 5.

## Requisitos nao-funcionais do contrato

- [x] CHK021 - Ha requisito limitando o que a saida do helper devolve ao contexto do LLM? [NFR, contracts/mcp-tools.md §SEC-M1] {auto} — strip de caracteres de controle, teto 2 KiB, rotulo de dado.
- [x] CHK022 - A ausencia de teto de chamadas por tool/sessao esta declarada como decisao (pos-MVP), e nao omitida? [Assumption, plan.md §SEC-L1 + contracts §SEC-L1] {auto} — declarada como recomendacao pos-MVP; `budget.sh` orca a onda, nao a tool.
- [x] CHK023 - A dependencia de validacao de schema (JSON Schema cru vs Zod) esta declarada com impacto e acao definidos caso a premissa nao se confirme? [Assumption, research.md §Spike S4] {auto} — "Fixar Zod como dependencia (afeta `package.json`, nao o desenho)"; a premissa permanece **[NAO-VERIFICADO]** ate o spike S4 da F0 (ver `operational.md` CHK071).

## Criterios de aceite

- [x] CHK024 - SC-002 e mensuravel sem acesso a implementacao? [Mensurabilidade, Spec §SC-002] {auto} — "100% das tentativas ... rejeitadas no momento da chamada, nunca chegando a persistir".
- [x] CHK025 - SC-001 define o conjunto sobre o qual a taxa "cai a zero" e medida? [Ambiguity, Spec §SC-001] {auto} — resolvido na task 3.4: `spec.md` §SC-001 quantifica 15 execucoes de teste (Scenarios 1-9 de `quickstart.md`, excluindo os spikes 0.1-0.3; Scenarios 1/2/3/4/5/9 × 2 backends + Scenarios 6/7/8 × 1 backend) e o criterio de zero (2 rodadas completas sem sintoma).
- [ ] CHK026 - O nivel de detalhe do `reason` devolvido ao LLM (stderr do helper, scrubbed e limitado a 2 KiB) e aceitavel frente ao risco de realimentar o contexto (LLM05), ou deve ser reduzido a codigo de erro? {humano}
- [ ] CHK027 - As 6 tools sao o escopo correto do MVP, ou alguma das operacoes hoje listadas como "nao-tool" deveria entrar antes do primeiro uso real? {humano}

## Notes

- Items `{auto}` foram resolvidos contra os artefatos com citacao; `[x]` sem citacao nao vale.
- Items `{humano}` aguardam decisao do dono do produto antes de `execute-task`.
- Destino dos abertos: `[Gap]` → `create-tasks`; `[Ambiguity]`/`[Conflict]` → `clarify` ou amendment na spec.
- Gate deterministico `requirement-coverage.sh` sobre `spec.md`: `requirements=17|covered=17|errors=0` (exit 0) — nenhum FR sem cenario associado.
