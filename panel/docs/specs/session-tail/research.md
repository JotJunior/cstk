# Research: Session Tail

Documento produzido no Phase 0 do `/plan`. Resolve os `NEEDS CLARIFICATION` do
Technical Context antes do design.

> **Nota de veracidade (Principio VI da constituicao global / "jamais inventar
> dados")**: toda afirmacao sobre o formato do armazenamento de sessoes do
> Claude Code neste documento foi extraida de arquivos reais em
> `~/.claude/projects/` durante a onda-004, e a sonda esta citada em
> **Evidence** na decisao correspondente. Nenhum nome de campo aqui foi
> suposto. Campos que a sonda NAO encontrou estao marcados como ausentes,
> nunca preenchidos por plausibilidade.

---

## Decision 1: Fonte de descoberta das sessoes

**Decision**: Varredura direta do sistema de arquivos em
`~/.claude/projects/<slug>/<sessionId>.jsonl`, sem qualquer participacao da
`knowledge.db`.

**Rationale**: as sessoes vivas do Claude Code nao existem na `knowledge.db` —
ela indexa execucoes do `agente-00c`/`feature-00c`, nao sessoes do harness. A
varredura do filesystem e a unica fonte que contem o dado. Consequencia
arquitetural relevante: **esta feature nao abre a `knowledge.db` em nenhum
caminho de codigo**, o que torna o Principio I trivialmente satisfeito (nao ha
conexao a ser aberta em modo errado) e desacopla a trilha de sessoes de
qualquer degradacao do corpus.

**Evidence**: `~/.claude/projects` existe com 69 diretorios de projeto
(`ls ~/.claude/projects | wc -l` → 69) e 299 arquivos `.jsonl`
(`find ~/.claude/projects -name '*.jsonl' -maxdepth 2 | wc -l` → 299). Nenhum codigo do repositorio le esses arquivos hoje: grep por `.jsonl`
e `claude/projects` em `apps/server/src`, `apps/web/src` e `packages/` retorna
apenas uma string de fixture nao relacionada em
`packages/shared-types/src/__tests__/parity.test.ts:256`.

**Alternatives considered**:
- *Ler da `knowledge.db`*: rejeitado — o dado nao esta la (ver Decision 3).
- *Exigir configuracao manual da lista de sessoes*: rejeitado por FR-001, que
  proibe configuracao manual de quais sessoes existem.

---

## Decision 2: Identidade da sessao — o nome do arquivo E o `sessionId`

**Decision**: o identificador unico da sessao (FR-004) e o UUID que da nome ao
arquivo `.jsonl`, e ele e confirmavel pelo conteudo. O roteamento
(`GET /sessions/:sessionId/tail`, rota web `/sessions/:sessionId`) usa esse
UUID, nunca um `executionId`.

**Rationale**: satisfaz FR-004 diretamente. O UUID e globalmente unico por
construcao e nao colide entre projetos — ao contrario de `executionId`, que a
memoria do projeto ja registrou como **nao unico entre projetos**. Como o nome
do arquivo carrega a identidade, resolver uma sessao por id nao exige varrer
conteudo: basta localizar o arquivo.

**Evidence**: em
`~/.claude/projects/-Users-jot-Projects--lab-Jot-misc-cstk-panel/331ab8ca-29a6-4dcc-8d7b-d1d72e2a4549.jsonl`,
`jq -r '.sessionId' | sort -u` retorna um unico valor,
`331ab8ca-29a6-4dcc-8d7b-d1d72e2a4549`, identico ao basename do arquivo.

**Alternatives considered**:
- *Indexar por `executionId`*: rejeitado por FR-004 e pelo cenario 3 da US2.

---

## Decision 3: Associacao sessao → execucao autonoma NAO e implementada

**Decision**: o campo "execucao de agente autonomo" de FR-002 fica **ausente**
nesta feature. Nenhum `executionId` e exibido na listagem de sessoes.

**Rationale**: **nao existe join verificado** entre um `.jsonl` de sessao e uma
linha de `executions` na `knowledge.db`. A coluna `executions.session` NAO
contem UUID de sessao — contem o *short-name* da execucao. Inventar uma
associacao (por proximidade de timestamp, por projeto, por heuristica de nome)
produziria vinculo falso apresentado como verdadeiro, exatamente o que o
Principio VI proibe. FR-002 ja hedgeia o campo com "quando disponivel", entao
omiti-lo esta em conformidade com a spec.

**Evidence** (todas via `sqlite3 "file:$HOME/.claude/cstk/knowledge.db?mode=ro"`):
`SELECT DISTINCT session FROM executions` retorna valores como
`show-tips`, `dynamic-forms`, `product-management`, `elastic-apm`,
`api-go-core` — short-names, nao UUIDs. Varredura de colunas
(`sqlite_master JOIN pragma_table_info` filtrando `name LIKE '%session%'`)
retorna exatamente tres: `executions.session`, `waves.session` e
`plan_usage.session_id`.

**Nota (caminho que EXISTE, mas fica fora do escopo)**: `plan_usage.session_id`
*e* de fato o UUID de sessao do Claude Code — sonda: `SELECT DISTINCT session_id FROM
plan_usage WHERE session_id IS NOT NULL` retorna 66 ids, e um laco procurando
`find ~/.claude/projects -name "$id.jsonl"` para cada um encontrou arquivo
correspondente para os 66 (0 orfaos). Essa tabela tambem carrega `project` e
`project_path`. Porem: (a) ela liga sessao a *cota de plano*, nao a execucao;
(b) sua captura e OPT-IN (`cstk statusline install`), cobrindo 66 de 299
sessoes; (c) usa-la introduziria dependencia da `knowledge.db` que a Decision 1
deliberadamente evita. Fica registrada aqui como caminho conhecido para uma
feature futura, **nao** como algo a implementar agora.

**Alternatives considered**:
- *Correlacionar por projeto + janela de tempo*: rejeitado — heuristica sem
  fonte, produz vinculo fabricado.
- *Usar `plan_usage` como ponte*: rejeitado nesta feature pelos tres motivos
  acima; reavaliavel depois.

---

## Decision 4: Associacao sessao → projeto vem do `.cwd` do transcript

**Decision**: o caminho do projeto de uma sessao e lido do campo `cwd` da
primeira linha do proprio `.jsonl` que o possua. O nome do diretorio-slug e
usado apenas como chave de agrupamento opaca, **nunca** revertido para um path.

**Rationale**: o slug do diretorio e uma transformacao **lossy e irreversivel**
— `/`, `_` e `.` colapsam todos para `-`, entao des-slugificar e ambiguo por
construcao. O `cwd` gravado dentro do arquivo e o path literal, sem perda.
Ressalva importante: `cwd` **varia dentro da mesma sessao** (o agente pode
operar em subdiretorios), por isso a regra e "primeira ocorrencia" (o cwd de
lancamento), nao "qualquer ocorrencia".

**Evidence**: no arquivo `331ab8ca-...jsonl`, `jq -r '.cwd' | sort -u` retorna 4
valores distintos: `/Users/jot/Projects/_lab/Jot/misc/cstk-panel`,
`.../apps/web`, `.../apps/web/src`, `.../apps/web/src/styles`. Perda do slug
comprovada em `-private-var-folders-f4-1-17mccd63xb45st9-q1rpz40000gp-T-cstk-eval-rw-b-XXXXXX-w6PJGuA63K`,
cujo `cwd` real e
`/private/var/folders/f4/1_17mccd63xb45st9_q1rpz40000gp/T/cstk-eval-rw-b.XXXXXX.w6PJGuA63K`
(`_` e `.` viraram `-`). Disponibilidade: em amostra de 40 arquivos, 40 tinham
`cwd` dentro das 50 primeiras linhas (0 vazios).

**Alternatives considered**:
- *Des-slugificar o nome do diretorio*: rejeitado, ambiguo (evidencia acima).
- *Usar o ultimo `cwd`*: rejeitado — reflete onde o agente estava por ultimo,
  nao a que projeto a sessao pertence.

---

## Decision 5: Guard de path proprio, confinado em `~/.claude/projects`

**Decision**: criar `apps/server/src/lib/sessions-root.ts`, com resolucao e
confinamento proprios cuja raiz permitida e o diretorio de sessoes. **Nao**
reusar nem afrouxar `validateProjectRootPath`.

**Rationale**: o guard existente lista `~/.claude` como zona **proibida** —
reusa-lo rejeitaria 100% das sessoes. Remover `~/.claude` de `FORBIDDEN_ZONES`
enfraqueceria o guard para todos os consumidores atuais, que dependem dele
justamente para nao vazar de `~/.claude`: seria trocar seguranca existente por
conveniencia de feature nova. O desenho correto e um guard **mais estreito**,
nao um guard existente afrouxado: raiz unica (`~/.claude/projects`, override por
`CSTK_SESSIONS_ROOT`), `realpathSync` no candidato e na raiz, e rejeicao de
qualquer caminho que nao permaneca sob a raiz apos resolucao de symlink.

**Evidence**: `apps/server/src/lib/project-root.ts` linhas 30-40 definem
`FORBIDDEN_ZONES` contendo literalmente `${HOME}${sep}.claude`. Consumidores
confirmados por grep: `apps/server/src/routes/executions.ts:22` e
`apps/server/src/routes/docs.ts:30` importam `resolveProjectRoot`;
`apps/server/src/watchers/ingest-watcher.ts:42` importa
`validateProjectRootPath`.

**Alternatives considered**:
- *Remover `~/.claude` da denylist*: rejeitado — regressao de seguranca para
  tres consumidores atuais.
- *Reusar o guard como esta*: impossivel, rejeita tudo.

---

## Decision 6: Liveness derivada do `mtime`, janela de 5 minutos

**Decision**: uma sessao e "viva" quando `now - mtime(arquivo) <= LIVE_WINDOW_MS`,
default 5 minutos (`CSTK_SESSION_LIVE_WINDOW_MS`). O atributo e **derivado e
volatil**, calculado a cada resposta.

**Rationale**: SC-004 fixa 5 minutos de inatividade como a janela. O `mtime` e o
unico sinal de atividade disponivel sem abrir o arquivo — e o Claude Code
apenda no `.jsonl` a cada evento, entao `mtime` acompanha a atividade real.
Usar o `timestamp` da ultima linha exigiria ler e parsear o fim de todo arquivo
a cada ciclo de listagem (299 arquivos), custo desnecessario para o mesmo sinal.
Como o atributo e derivado, FR-003 determina explicitamente que ele **nao
gateia** a leitura do tail.

**Alternatives considered**:
- *`timestamp` da ultima linha*: rejeitado por custo; equivalente em sinal.
- *Detectar processo vivo (lock/pid)*: rejeitado — nao ha artefato de processo
  verificado sob `~/.claude/projects`, e supor um violaria o Principio VI.

---

## Decision 7: Watcher NOVO e SEPARADO, com cache em memoria

**Decision**: `apps/server/src/watchers/sessions-watcher.ts`, modulo novo
seguindo o **padrao** de `ingest-watcher.ts` (polling via `setInterval`,
assinatura por `statSync().mtimeMs`, factory `startSessionsWatcher(opts)`
retornando `{ stop }`, timer `.unref()`, degradacao silenciosa em diretorio
ausente), em instancia **separada**.

**Rationale**: FR-011 exige reuso do padrao, nao da instancia. As raizes
observadas divergem (state dirs de execucao vs `~/.claude/projects`), os ciclos
de vida divergem e os modos de falha divergem; compartilhar instancia acoplaria
a ingestao da `knowledge.db` a uma falha na descoberta de sessoes, e vice-versa.
O watcher mantem um indice em memoria (`sessionId → metadados`) para que
`GET /sessions` responda a partir do cache em vez de varrer 299 arquivos por
requisicao — e o que sustenta SC-001 (5s).

**Nota de simplificacao**: o `ingest-watcher` delega a um subprocesso
(`cstk recall --ingest`) e por isso carrega timeout de subprocesso e cache de
binario. O watcher de sessoes **nao** tem subprocesso — apenas `readdirSync` +
`statSync`. O padrao e herdado; a complexidade de subprocesso, nao.

**Evidence**: `apps/server/src/watchers/ingest-watcher.ts` usa
`DEFAULT_WATCH_INTERVAL_MS = 5_000` com `setInterval`, `computeSignature` sobre
`statSync(...).mtimeMs`, factory `startIngestWatcher(opts): WatcherHandle`,
`discoverStateDirsInRoot()` com `readdirSync` em try/catch retornando `[]` em
diretorio ausente, e e ligado em `apps/server/src/index.ts` (~95-116) com
`server.addHook('onClose', ...)` chamando `stop()`.

**Alternatives considered**:
- *Estender a instancia do `ingest-watcher`*: rejeitado por FR-011 (a propria
  spec ja resolveu isso no clarify Q5).
- *`chokidar` / `fs.watch`*: rejeitado — o projeto ja escolheu polling, e
  `fs.watch` em 69 diretorios tem comportamento inconsistente entre
  plataformas.
- *Varrer sob demanda, sem cache*: rejeitado — 299 `statSync` por requisicao,
  com auto-refresh de 10s, pressiona SC-001 sem necessidade.

---

## Decision 8: Leitura do tail por janela de bytes a partir do fim do arquivo

**Decision**: abrir o arquivo, obter o tamanho via `fstat`, ler **apenas** os
ultimos `min(size, TAIL_READ_WINDOW_BYTES)` bytes (proposta: 1 MiB), descartar o
primeiro fragmento (potencialmente uma linha cortada ao meio pela janela),
dividir por `\n` e selecionar as ultimas N linhas completas.

**Rationale**: resolve tres requisitos de uma vez. (a) FR-006: jamais carrega o
arquivo inteiro — ha transcripts de 3,7 MB em disco hoje. (b) Escrita
concorrente (edge case da spec): ler ate o tamanho capturado no `fstat` significa
consumir apenas bytes ja gravados; um append em andamento simplesmente nao
entra nesta resposta. (c) Nunca trava nem corrompe: e leitura posicional, sem
lock.

**Evidence de necessidade**: `ls -la ~/.claude/projects/-Users-jot-Projects--lab-Jot-misc-cstk-panel/*.jsonl`
mostra `5567f0c1-0816-4664-8186-3a7276d36846.jsonl` com 3.710.915 bytes, alem de
outros entre 479.274 e 1.266.437 bytes.
Carregar o arquivo inteiro para devolver 200 linhas seria desperdicio de uma
ordem de grandeza.

**Alternatives considered**:
- *Ler o arquivo inteiro e cortar*: rejeitado por FR-006 e pelo tamanho real.
- *Streaming linha a linha do inicio*: rejeitado — custo proporcional ao
  historico inteiro para devolver o fim dele.

---

## Decision 9: Teto DUPLO — linhas e bytes — e obrigatorio

**Decision**: a resposta e limitada por dois tetos independentes, ambos
aplicados: N linhas (default 200, clamp em 1000) **e** um orcamento total de
bytes do conteudo emitido (proposta: 256 KiB). Alem disso, o texto de uma
entrada individual e truncado em um teto proprio (proposta: 8 KiB), sinalizado
por campo booleano na entrada.

**Rationale**: FR-006 exige o teto de bytes explicitamente porque **o teto de
linhas sozinho nao e guarda suficiente** — uma unica linha `.jsonl` pode conter
megabytes (o `tool_result` de um dump de arquivo e uma linha so). Sem o teto por
entrada, 200 linhas poderiam legitimamente somar dezenas de MB. A selecao
acumula do mais recente para o mais antigo e para no primeiro teto atingido,
devolvendo quantas entradas couberam.

**Evidence**: itens de conteudo do tipo `tool_result` e `tool_use` existem no
arquivo real (57 de cada em 400 linhas amostradas), e `tool_use` carrega o campo
`input` — o vetor natural para uma linha gigante.

**Nota**: os valores 1 MiB / 256 KiB / 8 KiB / 1000 sao **[PROPOSTA — a validar
na implementacao]**: sao politica de design desta feature, nao dado factual
observado. O que e requisito e a *existencia* dos tetos (FR-006), nao a
magnitude.

---

## Decision 10: Linha malformada e pulada e contada, nunca fatal

**Decision**: cada linha da janela e parseada individualmente com
`JSON.parse` em try/catch. Falha de parse incrementa um contador
`skippedLines` devolvido no payload; o processamento continua.

**Rationale**: FR-003a determina exatamente isso — pular, continuar, e
**expor a contagem** ao chamador; proibido truncar em silencio ou abortar a
requisicao. Expor a contagem e o que diferencia "nao havia mais nada" de
"havia, mas nao deu para ler", que e a mesma disciplina de honestidade do
Principio III (nao apresentar parcial como completo).

**Evidence de que linhas heterogeneas sao a norma**: `.type` tem 17 valores
distintos no arquivo real (`assistant` 121, `user` 67, `attachment` 59,
`bridge-session` 19, `mode` 18, `permission-mode` 18, `last-prompt` 18,
`ai-title` 17, `frame-link` 15, `file-history-snapshot` 8, `system` 7,
`queue-operation` 6, `artifact-comment-monitor` 4, `artifact-autoreact-ledger` 3,
`cost-state` 2, `file-history-delta` 1, `atis-latch` 17 em 400 linhas), e nem
toda linha carrega `.message` — a ultima linha do arquivo amostrado e
`type: "system"` sem `message`.

**Alternatives considered**:
- *Abortar a requisicao na primeira linha invalida*: rejeitado por FR-003a — uma
  escrita concorrente em andamento tornaria o tail indisponivel justamente nas
  sessoes mais ativas, que sao as que o operador mais quer ver.
- *Pular em silencio, sem contador*: rejeitado — apresentaria resultado parcial
  como completo, indistinguivel de "o historico acabou aqui".

---

## Decision 11: Envelope reusado com `db = null`; frescor da sessao vai no dado

**Decision**: as rotas usam `wrap(data, opts, config.dbPath, null)` de
`apps/server/src/lib/envelope.ts`, como toda rota do painel. O frescor da
sessao (`lastActivityAt`) e exposto como **campo de dado**, nao em
`meta.freshness`.

**Rationale**: `wrap` ja aceita `db=null` por desenho (Principio II) e devolve
`freshness: { mtime: '', maxIngestedAt: '' }`. Isso e honesto para estas rotas:
elas nao tem snapshot de corpus por tras, entao o frescor **do corpus** e
genuinamente vazio, e nao deve ser preenchido com o mtime de um `.jsonl` — seria
apresentar o frescor de uma coisa como se fosse o de outra. O frescor real que
importa ao operador (quando a sessao teve atividade) e um atributo da sessao e
viaja como dado tipado. Reusar `wrap` tambem preserva o Principio IV: o
envelope tem dono, nao se reimplementa.

**Evidence**: `apps/server/src/lib/envelope.ts` — `wrap` ramifica em
`if (db !== null) ... else freshness = { mtime: '', maxIngestedAt: '' }`, e
`wrapDegraded(reason, dbPath)` ja chama `wrap(null, {...}, dbPath, null)`.
`MetaSchema.reason` e `z.string().nullable()`, entao motivos novos de degradacao
nao quebram o schema Zod; apenas o union TS `DegradedReason` em
`packages/shared-types/src/envelope.ts` precisa ganhar os novos literais.

**Alternatives considered**:
- *Preencher `meta.freshness.mtime` com o mtime do `.jsonl`*: rejeitado — o campo
  descreve o frescor do indice do corpus; preenche-lo com o de outra fonte
  apresentaria o frescor de uma coisa como se fosse o de outra.
- *Criar um envelope proprio para estas rotas*: rejeitado pelo Principio IV (o
  envelope tem dono) e por quebrar o `fetchApi`, que valida toda resposta com
  `ApiEnvelopeSchema`.

---

## Decision 12: `refetchInterval` por hook (override do default global)

**Decision**: a listagem de sessoes usa `refetchInterval` explicito no
`useQuery` do hook (proposta: 5s), sobrepondo o default global de 10s.

**Rationale**: FR-002 exige auto-atualizacao via `refetchInterval` do
`@tanstack/react-query`, mecanismo que ja existe no painel. Herdar o default
global de 10s ja satisfaz o requisito; o override existe porque a janela de
liveness e de 5 minutos e o operador espera uma trilha "ao vivo" mais reativa
que uma tela de historico. E um padrao novo no repositorio (hoje nenhum hook
sobrepoe o default) e por isso fica registrado aqui explicitamente, com
`refetchIntervalInBackground: false` preservado.

**Evidence**: `apps/web/src/lib/query.ts` define `AUTO_REFRESH_MS = 10_000` como
default do `QueryClient`, com `refetchIntervalInBackground: false` e
`refetchOnWindowFocus: false`. Nenhum hook em `apps/web/src/lib/hooks.ts`
sobrepoe `refetchInterval` hoje.

**Alternatives considered**:
- *SSE / WebSocket*: rejeitado no clarify (Q3) — superficie nova sem ganho
  proporcional.
- *Refresh manual*: rejeitado no clarify — mostra estado velho como atual.

---

## Decision 13: Renderizacao do transcript — variante multi-linha de `TextRaw`

**Decision**: o texto de cada entrada do tail e renderizado por um componente
novo `TextBlockRaw` em `apps/web/src/components/TextBlockRaw.tsx`, irmao de
`TextRaw`, que preserva quebras de linha (`<pre>` com `white-space: pre-wrap`)
mantendo a mesma garantia de escaping (children React, jamais
`dangerouslySetInnerHTML`).

**Rationale**: FR-005 e o Principio V exigem texto literal. `TextRaw` ja e a
convencao para conteudo UNTRUSTED, mas renderiza em `<span>` de linha unica e
trunca com reticencias — inadequado para um transcript multi-linha, que perderia
a estrutura. O componente novo herda a garantia de seguranca (o escaping vem do
React, nao do elemento) e muda apenas a apresentacao. Nao e duplicacao de logica
de dono (Principio IV): e a mesma politica em outra forma de bloco.

**Evidence**: `apps/web/src/components/TextRaw.tsx` expoe
`{ value, mono?, className?, maxLength? }`, renderiza dentro de `<span>` e
trunca com `…` + `title`. Nao existe variante de bloco no repositorio.

**Alternatives considered**:
- *Reusar `TextRaw` como esta*: rejeitado — `<span>` de linha unica com
  truncamento por reticencias destroi a estrutura de um transcript multi-linha.
- *Renderizar `<pre>` cru na tela, sem componente*: rejeitado — dispersa a
  garantia de escaping do Principio V por varias telas em vez de concentra-la
  num componente auditavel.
- *Renderizar markdown do transcript*: rejeitado — interpretar markup de conteudo
  UNTRUSTED e exatamente o que FR-005 proibe.

---

## Decision 14: Restricao lexical imposta pelo gate `lint:readonly-check`

**Decision**: nenhum arquivo sob `apps/server/src` — **incluindo comentarios e
strings** — pode conter as palavras `insert`, `update`, `delete`, `create`,
`drop` ou `alter` imediatamente seguidas de espaco, em qualquer caixa.
Comentarios desta feature usam formulacoes alternativas ("recomputar",
"renovar o indice", "remover", "montar").

**Rationale**: o gate e um `grep` cego, nao um parser de SQL — ele nao sabe
distinguir um comentario em portugues de um comando. Como esta feature trata de
auto-refresh e de um indice em memoria, as palavras "update" e "create"
apareceriam naturalmente em comentarios e quebrariam o baseline verde com um
diagnostico enganoso ("mutation verbs found") para uma feature que nao emite
nenhum SQL.

**Evidence**: comando em `package.json`:
`grep -rniE '\b(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER)[[:space:]]' apps/server/src`.
Sonda executada: um arquivo contendo apenas `// update interval do refetch` casa
o padrao. Baseline atual: `npm run lint:readonly-check` → `OK: no mutation verbs`.
O mesmo invariante e coberto de forma mais completa por
`apps/server/test/lib/readonly.test.ts`.

**Alternatives considered**:
- *Afrouxar o padrao do gate para casar so SQL real*: rejeitado — enfraqueceria
  um invariante de seguranca de todo o servidor para acomodar comentarios desta
  feature; o gate cego e barato e conservador de proposito.
- *Escrever os comentarios em ingles*: rejeitado — nao resolve (o padrao e
  case-insensitive e as palavras sao inglesas), e contraria a convencao de
  comentarios em portugues do repositorio.
