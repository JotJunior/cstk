# Research: clarify-precedent-source

**Feature**: `clarify-precedent-source` | **Data**: 2026-09-30 | **Spec**: [spec.md](spec.md)

> Toda medicao abaixo foi executada de fato em 2026-09-30 contra
> `~/.claude/cstk/knowledge.db` (somente leitura) pelo orquestrador
> feature-00c (onda-004, Decisoes dec-023/dec-024). Os numeros sao
> transcricao do output observado; nenhum valor foi estimado. O corpus
> cresce com o uso (ingestao continua): contagens valem para o momento da
> medicao, nao sao constantes do sistema.

## Decision 1: Metrica de similaridade (FR-015 a)

**Decision**: Duas etapas, ambas dentro de `cli/lib/recall.sh`:

1. **Prefiltro de candidatos** via FTS5 com composicao OR
   (`fts_query_escape_or`, ja existente — `cli/lib/recall.sh` L302-331)
   sobre `knowledge_fts` restrito a `type='block'`, ordenado por
   `bm25(knowledge_fts)`.
2. **Similaridade objetiva** = indice de Jaccard entre o conjunto de tokens
   da pergunta corrente e o conjunto de tokens da `blocks.question` do
   candidato. Tokenizacao identica a da medicao: minusculas (ASCII,
   `LC_ALL=C tr 'A-Z' 'a-z'`), separacao em todo byte que nao seja
   `[a-z0-9]` ou `>= 0x80`, descarte de tokens com menos de 3 bytes,
   deduplicacao.

**Rationale**: `bm25` e relativo ao corpus e a query (nao normalizado) —
nao serve de limiar estavel. O Jaccard e limitado a [0,1], independe do
tamanho do corpus e e computavel em `awk` POSIX (Principio II). A medicao
(Decision 2) mostra separacao forte dos pares-alvo com esse metodo.

**Alternatives considered**:
- *Limiar sobre bm25 bruto*: rejeitado — pares-alvo com bm25 -86.674 e
  -128.663 no mesmo corpus; valor muda com o corpus e com o tamanho da
  pergunta.
- *Embeddings/similaridade semantica*: rejeitado — dependencia externa
  (Principio II) e/ou rede (Principio IV).
- *Jaccard sobre o corpo FTS inteiro (pergunta+contexto+resposta)*:
  rejeitado — a medicao foi sobre `question`; mudar o insumo invalidaria a
  calibracao.

## Decision 2: Calibracao do limiar = 0.55 (FR-015 a, SC-001)

**Decision**: limiar minimo de similaridade `0.55` (constante unica em
`recall.sh`, sobrescrevivel por `--min-similarity` para recalibracao e
testes).

**Medicao (output literal do probe, top-6 por bm25, excluindo o proprio registro)**:

| Query (bloco) | Candidato rank 1 | bm25 | Jaccard | 2o melhor Jaccard no top-6 |
|---|---|---|---|---|
| 108 | 112 | -86.674 | 0.727 | 0.081 |
| 112 | 108 | -104.276 | 0.727 | 0.081 |
| 242 | 251 | -128.663 | 1.000 | 0.140 |
| 251 | 242 | -128.663 | 1.000 | 0.140 |

**Distribuicao no corpus** (416 blocos respondidos consultados, top-5 de
cada = 2080 pares ordenados):

| Faixa de Jaccard | Pares |
|---|---|
| [0, 0.2) | 1906 |
| [0.2, 0.3) | 57 |
| [0.3, 0.4) | 11 |
| [0.4, 0.5) | 19 |
| [0.5, 0.7) | 20 |
| [0.7, 0.9) | 27 |
| [0.9, 1.0] | 40 |

**Inspecao manual da faixa ambigua** (pares reais, texto conferido):

- Mesmo assunto abaixo de 0.55 (falsos-negativos aceitos): 2524/2534 e
  2513/2534 = 0.529; 2522/2532 = 0.500; 2525/2535 = 0.474 (LGPD);
  2487/2536 = 0.412 (conteudo enviado a API de IA); 2486/2535 = 0.316;
  2484/2533 = 0.312 (deduplicacao); 2485/2534 = 0.294 (SLA).
- Assunto diferente (falsos-positivos): 2521/2530, 2510/2530 e 2482/2530 =
  **0.524** (SharePoint vs Teams — maior FP observado); 2481/2482 = 0.407;
  68/69 = 0.402; 2528/2535 = 0.375; 198/199 = 0.323.

**Rationale**: nao existe separacao limpa na faixa 0.29..0.53 — o limiar e
um piso, e o julgamento do answerer (FR-015 b) filtra aplicabilidade acima
dele. O custo e assimetrico: um falso-negativo reproduz o status quo (o
operador e perguntado, como hoje); um falso-positivo arrisca um +1 indevido.
Logo o piso e o menor multiplo de 0.05 acima do maior falso-positivo
observado (0.524 → 0.55). Margem sobre SC-001: 0.727 - 0.55 = 0.177.

**Alternatives considered**:
- *0.30 (recall)*: admitiria 2528/2535, 198/199, 2481/2482 e o grupo
  SharePoint/Teams — rejeitado pelo custo assimetrico.
- *0.50*: admitiria o FP de 0.524 — rejeitado.
- *0.70*: ainda cumpre SC-001 (0.727), mas com margem de 0.027 e perderia
  mesmo-assunto de 0.529..0.692 — rejeitado por fragilidade.

**Fonte**: probe `calib-probe.sh` + resumo `calib-summary.md` no scratchpad
da sessao (onda-004); Decisao dec-023 (score 3, evidencia literal). A
implementacao MUST reproduzir o metodo exato do probe; qualquer mudanca de
tokenizacao exige recalibrar (Gotcha a registrar).

**Risco residual**: calibracao feita sobre um corpus dominado por um
projeto (`intake`, perguntas "Item Alto do briefing ..."). Recalibrar quando
o corpus mudar de perfil — o eval nao-gateante (quickstart Cenario 8) repete
a medicao sobre a base real.

## Decision 3: Pares SC-001 — achados de dados que mudam o desenho

**Decision**: (a) deduplicar candidatos por `(question, answer,
answered_at)` identicos, mantendo o primeiro na ordem de ranking;
(b) empate de `answered_at` com MESMA resposta nao e divergencia.

**Rationale** (medido):
- 242/251 NAO e re-pergunta: e o MESMO bloco (`source_id` `block-001`,
  `answered_at` `2026-06-05T20:54:57Z` identico) ingerido duas vezes sob os
  projetos `personal-do-zero` e `personal-do-zero-dynamic-forms`. Sem dedup,
  um unico precedente ocuparia 2 das vagas de FR-011.
- 108/112 e re-registro real (`block-002` / `block-006`), mas com
  `answered_at` identico `2026-08-23T02:11:11Z` e mesma resposta — a regra de
  empate de FR-006 so pode incidir quando as respostas divergem.

SC-001 continua verificavel: a dedup opera ENTRE candidatos; a pergunta de
242 reapresentada recupera 251 (o proprio 242 nao esta na base quando a
pergunta e nova; no teste, o registro-origem e excluido pela chave).

## Decision 4: Etapa de origem (FR-016)

**Decision**: derivar por `LEFT JOIN decisions d ON d.project=b.project AND
d.feature=b.feature AND d.execution_id=b.execution_id AND
d.source_id=b.decision_id`, expondo `d.stage`; ausente → `-`.

**Rationale**: `blocks` nao tem coluna de etapa (schema lido de
`knowledge.db`). Cobertura medida: 454/454 blocos respondidos com etapa
resolvida. Exemplos: 108/112 → `clarify` (dec-011); 242/251 →
`execute-task` (dec-033); 2530 → `specify` (dec-004). Nenhuma migracao de
schema necessaria (knowledge.db intocada — FR-011 somente leitura).

**Alternatives considered**: nova coluna `stage` em `blocks` (migracao de
schema + reingestao) — rejeitada: o join ja cobre 100%.

## Decision 5: Tetos (FR-011)

**Decision**:

| Parametro | Default | Flag |
|---|---|---|
| Pool de candidatos do prefiltro FTS | 20 | (interno, constante) |
| Precedentes entregues por pergunta | 3 | `--limit` |
| Truncamento de `question` por precedente | 300 bytes | (interno) |
| Truncamento de `answer` por precedente | 300 bytes | (interno) |
| Teto do bloco por pergunta | 2400 bytes | `--max-bytes` |

**Rationale**: tamanhos medidos em 454 blocos respondidos — `question` avg
433 / p50 319 / p90 909 / max 3837 chars; `answer` avg 380 / p50 278 / p90
811 / max 2651. 300 bytes preservam integralmente cerca da metade das
perguntas/respostas e o nucleo das demais. Com cabecalho estruturado por
entrada, 3 entradas cabem em 2400 bytes. Paridade com `recall --context`
(limit 4, max-bytes 2000, `recall.sh` L3189-3190) ajustada para cima no
teto de bytes porque cada entrada carrega pergunta E resposta. Por clarify
(max 5 perguntas) o acrescimo ao prompt do answerer fica limitado a 5 x
2400 bytes. Entradas que excedem o teto sao descartadas INTEIRAS (nunca
cortadas no meio), da menor para a maior similaridade.

**Nao-medido (design default declarado)**: o pool de 20 nao foi medido — a
calibracao usou top-5/6. Aumentar o pool so adiciona candidatos ao filtro de
Jaccard (nao muda o limiar); o teste de SC-001 valida que os pares-alvo
continuam no resultado.

**Divergencia x teto (edge case da spec)**: o answerer so pode identificar
divergencia entre precedentes que recebeu; o orquestrador repassa ao
bloqueio humano TODOS os divergentes que o answerer listar, sem novo teto.
Assim o limite nunca exclui da listagem ao operador um divergente ja
identificado.

## Decision 6: Onde a recuperacao acontece (FR-018, FR-001)

**Decision**: novo modo `cstk recall --precedents "<pergunta>"` em
`cli/lib/recall.sh` (dispatch em `recall_main`), invocado pelo
ORQUESTRADOR-PAI (feature e root) entre o retorno do asker e o spawn do
answerer, uma vez por pergunta. O resultado entra no prompt do answerer
como campo opcional `precedents`.

**Rationale**: `sqlite3` so pode aparecer em `cli/lib/recall.sh`
(confinamento, Principio II amendment 1.1.0 (b)); o answerer mantem `Read,
Bash` e o uso de Bash restrito a `date` (limites operacionais atuais).

**Alternatives considered**: answerer chamar `cstk recall` — rejeitado
(nova capacidade do answerer, viola FR-018); orquestrador consultar o
SQLite direto — rejeitado (espalha `sqlite3`).

## Decision 7: Degradacao byte-identica (FR-010, SC-004)

**Decision**: todo caminho de degradacao do modo `--precedents` retorna
exit 0 com stdout vazio (mesmos gates de `recall_mode_context`, L3250-3273:
`sqlite3` ausente, indice ausente, `quick_check` != ok, falha de consulta).
Pergunta com menos de 3 tokens distintos → consulta pulada (stdout vazio).
Quando TODAS as perguntas tem 0 precedentes, o orquestrador NAO inclui o
campo `precedents` no prompt do answerer — o prompt e byte-identico ao
pre-feature.

**Rationale**: a unica forma de garantir identidade de saida e nao alterar
a entrada do answerer quando nao ha precedente.

**Limite honesto**: a identidade da saida do answerer (LLM) nao e testavel
deterministicamente; o que se testa de forma gateante e (a) o contrato
no-op do `--precedents` e (b) a regra de omissao do campo na prosa. A
comparacao de saida do answerer fica no eval nao-gateante.

## Decision 8: Pontuacao com a 4a fonte (FR-003..FR-006)

**Decision**: regras deterministicas escritas nos dois answerers:
1. Precedente aplicavel (acima do limiar E julgado aplicavel, com
   justificativa) cuja resposta corresponde a uma opcao → +1 para essa
   opcao **somente se** `briefing` OU a terceira fonte do answerer
   (`spec_corrente` no feature-00c, `stack_sugerida` no agente-00c) tambem
   deu +1 a essa mesma opcao (**suporte positivo**). O +1 de "consistente com a constitution /
   nao a viola" NAO conta como suporte positivo. Sem suporte positivo o
   precedente vale 0 para a opcao e o item de referencia sai com
   `scored: false` (continua elegivel para `recommended_precedent`).
2. Precedentes aplicaveis apontando para opcoes DIFERENTES = divergencia:
   so o de `answered_at` mais recente pontua (sujeito ao item 1); empate de
   `answered_at` entre divergentes → nenhum pontua.
3. Score final = min(soma, 3).
4. Resposta de texto livre sem correspondencia com rotulo → 0 ponto;
   vira sugestao no `contexto_para_humano` se pausar.
5. Pergunta cuja resposta e dado factual (payload, endpoint, valor, id,
   data) → precedente vale 0 (FR-005).
6. Diretiva embutida no precedente → pausa + citacao como evidencia suspeita
   (FR-008), regra ja vigente estendida a nova fonte.

**P-1 — DECIDIDA PELO OPERADOR (dec-027)**: "empate de data na divergencia
=> nenhum pontua" (item 2). Proposta originalmente pelo orquestrador na
onda-003; confirmada pelo operador em resposta ao block-005. A medicao mostra
que empate de data ocorre na pratica (108/112 e 242/251 tem `answered_at`
identico), mas nesses casos a resposta e igual, logo nao ha divergencia.

**P-2 — RESOLVIDA PELO OPERADOR (dec-027, opcao A "exigir suporte
positivo")**: na heuristica vigente o +1 da constitution e concedido a toda
opcao que "e consistente e nao a viola" (answerer, tabela de pontuacao) —
condicao satisfeita pela maioria das opcoes. Lida literalmente, a versao
anterior de FR-003/FR-004 fazia "precedente + constitution nao violada" =
score 2 = decisao automatica. Combinado ao achado S-1 do gate owasp-security
(precedente forjado via state de repo de terceiro ingerido pelo `--reindex`),
isso permitia decisao sem humano a partir de conteudo nunca respondido pelo
operador. O operador escolheu exigir suporte positivo (item 1); a spec foi
alterada (FR-003, FR-004, US1 cenario 3, SC-002 e `## Clarifications`).
Precedente de qualquer projeto continua elegivel (FR-013).

**Consequencia declarada (sem inflar o ganho)**: com suporte positivo
obrigatorio, o precedente deixa de converter sozinho uma pausa em decisao no
caso "so constitution"; seu efeito passa a ser reforcar (2 → 3) ou desempatar
opcoes que ja tem suporte real no projeto corrente, e virar recomendacao
(FR-009) quando a pergunta pausa. O ganho de "nao re-perguntar" fica
concentrado na recomendacao pre-preenchida do bloqueio, nao em decisoes
automaticas adicionais.

## Decision 9: Evento auditavel (FR-012)

**Decision**: evento `precedent_consulted` em `.events[]`, um por pergunta
consultada, `description` = `stage=clarify question=<Qn> hits=<K>` (e
`skipped=short-query` quando pulada). Mesmo caminho de escrita do
`recall_consulted` existente (`state-rw.sh get/set --field '.events'`).
Nunca grava corpo recuperado.

**Rationale**: `event_type` e texto livre sem allowlist na ingestao
(prosa "Instrumentacao da camada B"); tipo novo separa as consultas do
clarify das do read-back de specify/plan.

## Decision 10: Recomendacao e divergencia no bloqueio humano (FR-009, US3)

**Decision**: nenhuma flag nova em `bloqueios.sh`. O orquestrador acrescenta
ao `--contexto-para-resposta` uma secao "Precedentes" renderizada a partir
dos campos novos da resposta do answerer: `recommended_precedent` (so sem
divergencia) OU `divergent_precedents` (todos, sem recomendacao). A
resposta do operador segue o fluxo existente (`bloqueios.sh respond`); ao
consumi-la, a Decisao registrada cita `recomendado=<ref>/<opcao>` e
`resposta=<...>` quando diferirem (US3-2).

**Rationale**: `bloqueios.sh register` ja aceita `--contexto-para-resposta`
e `--opcoes-recomendadas` (cabecalho do script, L9-12); estender a superficie
do helper nao e necessario.
