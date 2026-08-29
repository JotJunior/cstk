# API Checklist: Session Tail

**Purpose**: Validar a qualidade dos requisitos de contrato das duas rotas
novas (`GET /api/v1/sessions`, `GET /api/v1/sessions/:sessionId/tail`) — nao a
implementacao.
**Created**: 2026-08-27
**Feature**: `docs/specs/session-tail/spec.md`, `contracts/sessions-api.md`

## Contrato e envelope

- [x] CHK024 - O contrato define, para as duas rotas, o envelope de resposta completo (campos de sucesso e de degradacao) com tipos explicitos por campo, nao apenas prosa descritiva? [Completude, contracts/sessions-api.md "Response 200 — data"/"degradada"] {auto}
- [x] CHK025 - Os requisitos de degradacao (`degraded`, `reason`) enumeram um conjunto **fechado** de motivos possiveis por rota (`sessions-root-missing`, `sessions-root-unreadable` na listagem; mais `session-not-found`, `session-rejected`, `session-scrub-failed` no tail), permitindo teste exaustivo de cada ramo? [Mensurabilidade, contracts/sessions-api.md] {auto}
- [x] CHK026 - O requisito de "nunca 4xx/5xx por condicao de dado" e consistente entre as duas rotas (mesma tabela, mesma redacao), sem uma rota permitir excecao implicita que a outra nao permite? [Consistencia, contracts/sessions-api.md ambas rotas "Nao ha respostas de erro"] {auto}

## Parametros e validacao de entrada

- [x] CHK027 - O parametro `lines` da rota de tail tem clamp e default explicitos e mensuraveis (inteiro 1..1000, default 200, "clamp silencioso") em vez de "um numero razoavel de linhas"? [Mensurabilidade, contracts/sessions-api.md "GET .../tail Request"] {auto}
- [ ] CHK028 - O comportamento de clamp silencioso (`lines` fora de 1..1000) esta refletido em algum cenario de aceite testavel (o que a resposta contem quando o cliente pede `lines=99999`), ou fica apenas descrito na tabela de parametros sem cenario correspondente no spec.md/quickstart? [Cobertura de Cenarios, Gap] {humano}
- [ ] CHK029 - O requisito de validacao do `sessionId` (formato UUID) antes de qualquer resolucao de arquivo esta amarrado a uma resposta degradada especifica e testavel (`session-rejected` ou `session-not-found`?) para o caso de um `sessionId` sintaticamente invalido — ou essa ramificacao ainda nao esta claramente distinta das demais causas de `session-rejected`? [Ambiguity, contracts/sessions-api.md "Validation: UUID"] {humano}

## Consistencia de campos entre rotas

- [ ] CHK030 - O campo `scrubMode` (`'cstk+internal'` \| `'internal'`) tem exatamente a mesma semantica e os mesmos dois valores possiveis nas duas rotas, evitando drift de enum entre listagem e tail? [Consistencia, contracts/sessions-api.md ambas rotas linha `scrubMode`] {auto}
- [x] CHK031 - O requisito documenta explicitamente a divergencia de nomenclatura `sessionId`/`session_id` coexistindo no mesmo arquivo `.jsonl` de origem, e qual campo o servidor MUST usar (evitando que uma implementacao futura leia o campo errado por acidente)? [Clareza, plan.md §Convencoes de Borda linha "sessionId e session_id coexistem"] {auto}
- [ ] CHK032 - Existe requisito/teste de paridade explicito entre a definicao de DTO no cliente e no servidor (dupla definicao mencionada no risco residual do plan.md), com um cenario de aceite nomeado, ou o risco fica citado sem virar um item verificavel de "definition of done"? [Mensurabilidade, plan.md §Re-check "Risco residual"] {humano}

## Roteamento por identificador (FR-004)

- [x] CHK033 - O requisito de roteamento declara, sem ambiguidade, que o path da rota de tail usa exclusivamente o identificador **da propria sessao**, nunca o identificador de execucao — mesmo quando dois projetos compartilham o mesmo identificador de execucao? [Clareza, spec.md FR-004, US2 cenario 3] {auto}
- [ ] CHK034 - Ha um cenario de aceite concreto (dado real ou sintetico) demonstrando duas sessoes com o mesmo `executionId` e verificando que a rota abre a sessao correta pelo `sessionId`, ou o cenario 3 da US2 descreve a garantia em prosa sem um exemplo de dado concreto rastreavel a uma fonte (arquivo real observado)? [Cobertura de Cenarios, Assumption] {humano}

## Linhas malformadas (FR-003a)

- [x] CHK035 - O requisito declara um campo de resposta explicito e tipado para contagem de linhas puladas (`skippedLines: number`), tornando o requisito "sinalizar ao operador quantas linhas foram puladas" objetivamente verificavel? [Mensurabilidade, contracts/sessions-api.md campo `skippedLines`, spec.md FR-003a] {auto}
- [ ] CHK036 - Existe criterio definindo o que conta como "linha malformada" (JSON invalido? campo obrigatorio ausente? ambos?) de forma verificavel, ou o requisito usa apenas o termo generico "malformada/parcial" sem definir o criterio de deteccao? [Clareza, Ambiguity, spec.md FR-003a] {humano}

## Auto-refresh (FR-002)

- [x] CHK037 - O requisito de auto-atualizacao especifica o mecanismo exato (`refetchInterval` do `@tanstack/react-query`, ja existente no painel) em vez de "atualizar automaticamente", tornando-o verificavel por revisao de codigo e nao apenas por observacao de comportamento? [Mensurabilidade, spec.md FR-002, Clarifications Q3] {auto}
- [ ] CHK038 - O intervalo concreto do `refetchInterval` (quantos segundos/ms) esta especificado em algum artefato (spec/plan/contract), ou fica implicito/a definir na implementacao sem criterio de aceite mensuravel — o que impediria testar SC-001 (5s) de forma determinada? [Mensurabilidade, Gap] {humano}

## Notes

- Items `{auto}` ja vem resolvidos pelo agente (`[x]` com citacao, ou marcador `[Gap]`/`[Ambiguity]`).
- Items `{humano}` ficam `[ ]` aguardando decisao do dono do produto.
- CHK029/CHK036/CHK038 sao os `[Gap]`/`[Ambiguity]` de maior valor para o `/create-tasks`: definem criterio de deteccao (linha malformada), amarram validacao de UUID a uma resposta degradada especifica, e fixam o intervalo de refetch que sustenta SC-001.
- CHK028/CHK034 pedem cenario de aceite concreto para comportamentos ja descritos em prosa (clamp de `lines`, colisao de `executionId`) — sem cenario rastreavel, o requisito nao vira teste automatizavel no create-tasks.
