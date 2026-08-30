# API Checklist: Human Bridge (Intervencoes)

**Purpose**: Validar a qualidade do contrato HTTP `/api/v1/bridge/*` (primeira
superficie nao-`GET` do painel) e da tool MCP `ask_operator` como
REQUISITOS — completude de shape, error handling, idempotencia,
versionamento e coerencia entre as duas fronteiras (HTTP e MCP).
**Created**: 2026-08-29
**Feature**: [`../spec.md`](../spec.md) · [`../plan.md`](../plan.md) ·
[`../contracts/panel-bridge-api.md`](../contracts/panel-bridge-api.md) ·
[`../contracts/mcp-tool-ask-operator.md`](../contracts/mcp-tool-ask-operator.md)

## Completude de Contrato

- [x] CHK001 - As quatro rotas (`POST create`, `GET poll`, `GET list`, `POST answer`) tem request e response especificados com status code para cada desfecho documentado, nao so para o caminho feliz? [Completude, contract §4/§5/§6/§7] {auto}
- [ ] CHK002 - O principio geral de degradacao ("`bridge.db` ausente/ilegivel responde `200` com `meta.degraded=true`, nunca `5xx` por condicao de dado", contract §3) e reconciliado, explicitamente, com as rotas de ESCRITA (`create`/`answer`) — cujo proprio proposito e persistir um dado que nao existiria para devolver? O §4 (response `201`) e o §7 (respostas `200/400/404/409`) nao descrevem qual shape um `create`/`answer` degradado retornaria (`data.questionId` seria omitido? a chamada viraria `unavailable` do ponto de vista do MCP mesmo com o painel HTTP respondendo `200`?). [Gap, contract §3 vs §4/§7] {auto}
- [x] CHK003 - O mapeamento de `state` HTTP (`open|answered|declined|expired`) para `outcome` do envelope MCP (`answered|declined|timeout|unavailable|failed`) e exaustivo e mutuamente exclusivo, incluindo um caso catch-all para excecao nao prevista? [Completude, contract §5 tabela "qualquer outra excecao -> failed"] {auto}
- [x] CHK004 - A ausencia deliberada do outcome `absent` nesta superficie (presente em `collect_optins`, ausente aqui) esta registrada como diferenca intencional, evitando que uma revisao futura a leia como esquecimento? [Consistencia, contract §5 "Nao existe absent nesta superficie... diferenca deliberada"] {auto}

## Convencao de Case e Mappers

- [x] CHK005 - A fronteira de case (snake_case no DB e no envelope MCP, camelCase no HTTP) esta especificada campo-a-campo, com exatamente um arquivo-mapper nomeado por fronteira (nao "em algum lugar do codigo")? [Consistencia, Plan §"Convencoes de Borda"; contract §2] {auto}
- [x] CHK006 - O precedente que justifica `camelCase` no HTTP (`routes/tasks.ts`) e citado com exemplos literais de campo, em vez de "seguir o padrao do painel" generico e nao-verificavel? [Clareza, contract §2 "executionId: r.execution_id, testsRun: r.tests_run..."] {auto}
- [x] CHK007 - Esta explicito que NAO ha ORM/auto-mapping em nenhuma das duas fronteiras, e que essa e uma escolha deliberada (nao uma lacuna a preencher depois)? [Clareza, contract §2 "ORM / auto-mapping: NAO"] {auto}

## Idempotencia e Validacao de Servidor

- [x] CHK008 - A idempotencia da rota `answer` (FR-016/SC-006) e especificada como invariante atomica de banco (`UPDATE ... WHERE resolution IS NULL AND expires_at > ?`, `changes === 1` -> `200`, `changes === 0` -> `409`), fechando a janela de corrida de um `SELECT`-then-`UPDATE`? [Mensurabilidade, contract §7] {auto}
- [x] CHK009 - Esta explicito que a validacao de `value` contra `options` (FR-005) e responsabilidade do SERVIDOR, mesmo que a UI ja restrinja as opcoes exibidas ("uma UI e uma sugestao; a rota e a regra")? [Clareza, contract §7 tabela + nota] {auto}
- [x] CHK010 - O `404` (questionId desconhecido) na rota de poll e tratado, do lado do cliente MCP, como `failed` — distinto de uma falha de conexao na criacao (`unavailable`) — preservando dois modos de "o painel nao respondeu" que precisam continuar diferenciaveis em `.operator_answers[]`? [Consistencia, contract §5 "o cliente MCP trata como failed (nao como unavailable)"] {auto}

## Paginacao, Query Params e Auto-refresh

- [x] CHK011 - A rota de listagem exige paginacao obrigatoria reusando um helper ja validado (`safeParsePagination`), em vez de introduzir uma segunda logica de paginacao no mesmo painel? [Consistencia, contract §6] {auto}
- [x] CHK012 - Os query params da listagem (`state`, `project`, `limit`/`offset`) tem um default explicito para o caso "nenhum parametro informado" (`state=open`), evitando que "sem filtro" tenha dois significados possiveis (tudo vs so aberto)? [Clareza, contract §6] {auto}
- [x] CHK013 - O intervalo de auto-refresh da fila (FR-013) reusa uma cadencia ja adotada em outra tela do painel, em vez de introduzir um terceiro valor de polling no mesmo produto (alem dos 1500ms de poll da tool e do teto do servidor)? [Consistencia, contract §9 "no padrao ja adotado pela tela de sessoes"] {auto}

## Cliente Web (Mutacao)

- [x] CHK014 - Esta especificado, com evidencia concreta (nao suposicao), por que o cliente HTTP existente (`fetchApi`) NAO pode ser reusado para a mutacao de resposta (aplica ETag/cache incondicionalmente, colidiria com FR-016/SC-006)? [Clareza, contract §8 "[VERIFICADO: apps/web/src/lib/api.ts:58-113]"] {auto}
- [x] CHK015 - A funcao de mutacao nova (`mutateApi()`) tem escopo explicito do que ela NAO deve herdar (nenhuma camada de ETag/cache) e o que ela DEVE fazer apos sucesso (invalidacao explicita do cache da fila)? [Completude, contract §8] {auto}
- [x] CHK016 - Esta reconhecido que esse defeito de cache (ETag incondicional numa mutacao) nao apareceria em teste com mock, e que por isso o roundtrip real e obrigatorio no `quickstart.md`? [Cobertura, contract §8 "esse defeito nao aparece em teste com mock"] {auto}

## Timeouts e Relogio

- [x] CHK017 - O timeout da chamada de criacao (`BRIDGE_CREATE_TIMEOUT_MS = 5000`), que dobra como sinal de indisponibilidade (FR-021), e um valor concreto e distinto da cadencia de polling (1500ms) e do teto do servidor (`MCP_ASK_TIMEOUT_MS`) — os tres relogios da feature nao compartilham acidentalmente uma constante? [Mensurabilidade, contract §4/§5; Plan §"Constraints de relogio"] {auto}
- [x] CHK018 - `timeoutMs` no payload de criacao e descrito, sem ambiguidade, como a janela JA RESOLVIDA pelo servidor MCP (nunca o valor cru pedido pelo agente), deixando claro que o painel apenas transporta esse numero? [Clareza, contract §4 "timeoutMs e a janela EFETIVA, nunca o valor cru"] {auto}

## Validacao Zod nas Duas Bordas

- [x] CHK019 - A validacao por schema (Zod) e exigida nos DOIS lados da fronteira HTTP (request no painel, response no cliente web e no cliente MCP), e nao so na entrada? [Cobertura, Plan §"Convencoes de Borda" "Validacao Zod: em ambas as bordas"] {auto}
- [x] CHK020 - Esta explicito que o servidor MCP mantem um schema Zod PROPRIO, espelhado (nao importa `shared-types` do painel, por serem repos/instalacoes distintos), e que a divergencia entre os dois e coberta por um cenario de teste que compara o payload real chave a chave? [Consistencia, Plan §"Convencoes de Borda" ultimo paragrafo] {auto}

## Notes

- **CHK002 e o unico `[Gap]` deste dominio** — vira acao explicita:
  antes de `/create-tasks` fechar o backlog de implementacao, `plan.md`/
  `contracts/panel-bridge-api.md` MUST ganhar uma linha reconciliando o
  principio geral de degradacao (§3) com o shape de resposta das duas rotas
  de escrita (§4/§7). Ate la, a implementacao das rotas `create`/`answer`
  NAO deve assumir silenciosamente "degradado = 200 vazio" nem "degradado =
  nunca acontece nestas rotas" — qualquer uma das duas e uma decisao de
  design que ainda nao foi escrita.
- Nenhum outro `[Gap]`/`[Conflict]` foi encontrado — os 20 items restantes
  citam evidencia literal do contrato ja fechado.
