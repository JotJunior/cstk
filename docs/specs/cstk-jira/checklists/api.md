# API Checklist: cstk-jira

**Purpose**: validar a qualidade dos requisitos de contrato REST/MCP do
Jira (endpoints, campos, error handling, idempotencia, versionamento) antes
de `create-tasks`.
**Created**: 2026-09-24
**Feature**: [spec.md](../spec.md) | [plan.md](../plan.md) | [contracts/jira-rest.md](../contracts/jira-rest.md) | [contracts/rovo-mcp.md](../contracts/rovo-mcp.md)

## Completude e Rastreabilidade de Contrato

- [x] CHK001 - Sao todos os 11 endpoints REST usados pelo motor (R1-R11) documentados com metodo+path+fonte oficial citavel, sem excecao? [Completude, Spec Contracts jira-rest.md R1-R11] {auto}
- [x] CHK002 - Cada campo de corpo/resposta que o motor de fato le/escreve (`fields.project.id`, `fields.issuetype.id`, `fields.summary`, `fields.parent`, `fields.description` ADF, `transition.id`, `fields.status`, `fields.summary` de leitura) tem fonte oficial rastreavel (schema OpenAPI ou exemplo oficial), em vez de suposicao de nome/formato? [Completude/Veracidade, Contracts jira-rest.md L84-160] {auto}
- [x] CHK003 - Os campos marcados apenas "(exemplo)" no OpenAPI (fora do schema formal) tem um passo de reconferencia BLOQUEANTE com criterio de aceite mensuravel antes de o codigo depender deles, em vez de so uma nota informativa? [Mensurabilidade, Plan.md Constitution Check linha VI + Quickstart Cenario 6] {auto}
- [x] CHK004 - Os itens `RECONFERIR` (`fields.status`, `fields.issuetype`, `fields.updated`) tem criterio de aceite verificavel objetivamente (comparar nome/tipo do campo contra a resposta REAL de uma chamada observada), em vez de ficarem como observacao solta sem teste associado? [Mensurabilidade, Contracts jira-rest.md L130-136 + Quickstart Cenario 6: "100% dos campos usados pelo motor existem na resposta real com o nome do contrato"] {auto}
- [x] CHK005 - E' explicito que `statusCategory.key` (sem enum normativo nas fontes oficiais) NUNCA e usado para decisao de sync — so `status_*` configurado por nome/id — evitando dependencia de um valor nao documentado? [Consistencia/Veracidade, Contracts jira-rest.md L162-163] {auto}
- [x] CHK006 - O mapeamento issueType->hierarquia (Epic/Task/Sub-task), cujo `hierarchyLevel` de Epic e `NAO ENCONTRADO` nas fontes, exige confirmacao explicita do operador durante o setup ANTES de qualquer criacao de issue, em vez de o sistema inferir/adivinhar o valor? [Gap->Edicao, Contracts jira-rest.md L190-193] {auto} — **Resolvido nesta onda**: gap real (a confirmacao ja estava desenhada no contrato como PROPOSTA mas nao propagada para o fluxo). Corrigido via edicao de `plan.md` (fluxo 1 Setup) e `quickstart.md` (Cenario 3, novo passo 4) nesta mesma onda — ver dec-037.
- [x] CHK007 - `fields.updated` (tipo NAO determinavel) e o endpoint de changelog (`NAO ENCONTRADO`) sao efetivamente usados por algum requisito funcional do motor (deteccao de conflito, ordenacao)? [Consistencia/Veracidade, data-model.md L180-185] {auto} — Nao: `data-model.md` "Deteccao de conflito (FR-011)" usa SOMENTE `sha256(titulo)` + `status` (campos com fonte/schema oficial via R3), nunca `updated`/changelog. O design ja evita depender de campo sem fonte para logica funcional; nenhuma edicao necessaria.

## Consistencia e Error Handling

- [x] CHK008 - E' o subconjunto de metodos permitidos (`GET`/`POST`/`PUT`, sem `DELETE`) consistente entre spec (FR-012), plan (Complexity Tracking/SEC) e contrato (`jira-rest.md` "Metodos proibidos")? [Consistencia, Spec FR-012 + Contracts L36 + Plan.md SEC table] {auto}
- [x] CHK009 - Sao os codigos de erro HTTP (400/401/403/404/409/413/422/429) mapeados a um comportamento de sistema especifico e nao-ambiguo para CADA operacao que os retorna, sem dois tratamentos incompativeis para o mesmo codigo? [Completude/Conflict, Contracts jira-rest.md "Validacao de credencial" vs Plan.md Test Strategy] {auto} — **[Conflict] encontrado e corrigido nesta onda**: `plan.md` tratava `401`/`403` uniformemente como `auth_failed` em 3 locais, mas `contracts/jira-rest.md` ("Validacao de credencial") afirma que `403` em R1/R2 e erro de PERMISSAO, nao de credencial — reconfigurar credenciais seria diagnostico enganoso. Corrigido: `401` => `auth_failed`; `403` em R1/R2 => `permission_denied` (diagnostico distinto); `403` nas demais operacoes (sem fonte que os distinga) segue `auth_failed` ate nova fonte. Ver dec-038 e `plan.md` L187/208/240 apos edicao.
- [x] CHK010 - E' o requisito de idempotencia (FR-013/SC-002) verificavel objetivamente (10 execucoes seguidas => 0 duplicatas) em vez de apenas declarativo? [Mensurabilidade, SC-002 + Quickstart Cenario 4 passo 3] {auto}
- [x] CHK011 - Existe criterio de aceite que distingue "issue ja existe (idempotente)" de "issue precisa ser atualizada (FR-003)" usando SOMENTE o mapeamento local (`jira-map.tsv`), nunca busca JQL textual por titulo? [Clareza, Plan.md fluxo 2 Convert + Contracts SEC-3] {auto}
- [x] CHK012 - E' o comportamento do caminho MCP (Rovo) vs REST especificado de forma que ambos produzam o MESMO efeito observavel (mesmo mapeamento, mesmo SyncMarker), evitando dois comportamentos divergentes conforme o mecanismo disponivel no ambiente? [Consistencia, Plan.md Arquitetura A1] {auto}
- [x] CHK013 - Os parametros de tool MCP nao documentados estaticamente (`rovo-mcp.md` "NAO ENCONTRADO") tem requisito explicito de que a skill MUST ler o `inputSchema` real em vez de usar nomes de memoria? [Veracidade, Contracts rovo-mcp.md "Parametros de entrada das tools"] {auto}
- [x] CHK014 - O limite de rate limit (20 escritas/2s por issue, research Decision 3) e refletido num requisito de serializacao de escritas (lock de drain) com criterio verificavel (nunca 2 escritas concorrentes na mesma issue)? [Mensurabilidade, Contracts hooks.md "Drenar" + `runtime/.drain.lock/`] {auto}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`/`[Conflict]` seguido da correcao aplicada nesta onda).
- CHK006 e CHK009 revelaram gaps/conflitos REAIS entre `contracts/` e `plan.md`/`quickstart.md`; ambos foram corrigidos por edicao direta dos artefatos nesta mesma onda (dec-037, dec-038), nao deixados so como observacao no checklist.
- `/create-tasks` MUST gerar tarefa de teste dedicada para CHK004/CHK007/CHK009 (cenario 6 do quickstart + teste de contrato que distingue 401 de 403 em R1/R2).
