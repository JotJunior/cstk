# Quickstart: Session Tail

Cenarios que validam a implementacao end-to-end. Executados contra o servidor
**de verdade**, nunca contra mock ou fixture.

> **Onde verificar**: use `npm run dev` na raiz — sobe o Vite na porta `5173` e
> o servidor Fastify na porta `3001`, com a API em `/api/v1`. **Nao** verifique
> na porta `8080`: aquela e do `cstk serve` global, que serve um bundle proprio
> e nao reflete as mudancas locais.

Nos comandos abaixo, `$API` designa a base local do servidor Fastify
(`http://` + `localhost:3001` + `/api/v1`) e `$WEB` a base do Vite
(`http://` + `localhost:5173`). Exportar antes de comecar:

```sh
export API="http://localhost:3001/api/v1"
export WEB="http://localhost:5173"
```

---

## Scenario 1: Listar sessoes vivas (happy path — US1)

1. Garantir que ha ao menos uma sessao do Claude Code com atividade recente
   (a propria sessao que executa este passo serve).
2. `npm run dev` na raiz do repositorio.
3. `curl -s "$API/sessions" | jq '.data.total, (.data.sessions[0] | keys)'`
4. Abrir `$WEB/#/sessions` no navegador.
5. **Expected**: `data.total >= 1`; cada item traz `sessionId`, `projectPath`,
   `projectSlug`, `lastActivityAt`, `live`, `sizeBytes`; `meta.degraded` e
   `false`. A tela lista a sessao com o projeto a que pertence.

## Scenario 2: Nenhuma sessao viva (estado vazio — US1 cenario 2 / SC-003)

1. `CSTK_SESSION_LIVE_WINDOW_MS=1 npm run dev` (janela de 1 ms — nada e "vivo").
2. `curl -s -o /dev/null -w '%{http_code}\n' "$API/sessions?live=true"`
3. `curl -s "$API/sessions?live=true" | jq '{total: .data.total, degraded: .meta.degraded}'`
4. **Expected**: status `200`; `total: 0`; `sessions: []`; **`degraded: false`** —
   vazio nao e degradacao. A tela mostra o estado vazio, nunca pagina de erro.

## Scenario 3: Raiz de sessoes ausente (degradacao — FR-008 / Principio II)

1. `CSTK_SESSIONS_ROOT=/tmp/nao-existe-sessions npm run dev`
2. `curl -s -o /dev/null -w '%{http_code}\n' "$API/sessions"`
3. `curl -s "$API/sessions" | jq '{data: .data, reason: .meta.reason, degraded: .meta.degraded}'`
4. **Expected**: status **`200`** (jamais `5xx`); `data: null`;
   `degraded: true`; `reason: "sessions-root-missing"`. A tela mostra o estado
   degradado, distinto do vazio do Scenario 2.

## Scenario 4: Tail de uma sessao (US2)

1. Capturar um id real:
   `SID=$(curl -s "$API/sessions?live=false" | jq -r '.data.sessions[0].sessionId')`
2. `curl -s "$API/sessions/$SID/tail?lines=50" | jq '{returned: .data.returnedLines, skipped: .data.skippedLines, truncBytes: .data.truncatedByBytes, window: .data.windowTruncated}'`
3. **Expected**: `200`; `returnedLines <= 50`; `skippedLines` presente como
   numero (mesmo que `0` — FR-003a exige o campo, nao apenas o comportamento);
   entradas em ordem cronologica ascendente.

## Scenario 5: Tail de sessao NAO viva (FR-003)

1. Encontrar uma sessao com `live: false`:
   `SID=$(curl -s "$API/sessions?live=false" | jq -r '[.data.sessions[] | select(.live == false)][0].sessionId')`
2. `curl -s "$API/sessions/$SID/tail" | jq '{degraded: .meta.degraded, live: .data.live, n: .data.returnedLines}'`
3. **Expected**: `degraded: false`; `live: false`; `returnedLines > 0` — o
   conteudo **e servido normalmente**. Liveness nunca gateia leitura de conteudo
   ja gravado.

## Scenario 6: Transcript gigante respeita os dois tetos (FR-006)

1. Escolher o maior transcript disponivel:
   `SID=$(curl -s "$API/sessions?live=false" | jq -r '[.data.sessions[] | select(.sizeBytes > 1000000)][0].sessionId')`
   (na maquina de referencia existe um `.jsonl` de 3.710.915 bytes)
2. Medir o tamanho da resposta:
   `curl -s "$API/sessions/$SID/tail?lines=1000" | wc -c`
3. `curl -s "$API/sessions/$SID/tail?lines=1000" | jq '{truncBytes: .data.truncatedByBytes, window: .data.windowTruncated}'`
4. **Expected**: a resposta e ordens de grandeza menor que o arquivo; o teto de
   bytes e observavel na resposta (`truncatedByBytes` ou `windowTruncated` em
   `true`); nenhuma resposta contem o arquivo inteiro.

## Scenario 7: Linha malformada e pulada e contada (FR-003a)

1. Preparar uma raiz de teste isolada:
   `mkdir -p /tmp/st-fixture/-tmp-proj`
2. Montar um `.jsonl` com uma linha valida, uma linha quebrada e outra valida —
   por exemplo tres linhas onde a do meio e `{"type":"user",` (JSON incompleto).
   Nomear o arquivo com um UUID valido.
3. `CSTK_SESSIONS_ROOT=/tmp/st-fixture npm run dev`
4. `curl -s "$API/sessions/<uuid>/tail" | jq '{returned: .data.returnedLines, skipped: .data.skippedLines}'`
5. **Expected**: `200`; `returnedLines: 2`; **`skippedLines: 1`**. A requisicao
   nao aborta e o corte nao e silencioso.

> Este e o unico cenario que constroi um arquivo sintetico — porque exige uma
> condicao de corrupcao que nao se pode provocar sob demanda num transcript
> real. Ele testa o **parser**, nao o contrato de borda; o contrato continua
> validado contra dado real nos Scenarios 1-6 e 9.

## Scenario 8: Path traversal e rejeitado (Principio I / guard proprio)

1. `curl -s -o /dev/null -w '%{http_code}\n' "$API/sessions/..%2F..%2F..%2F..%2Fetc%2Fpasswd/tail"`
2. `curl -s "$API/sessions/..%2F..%2Fetc%2Fpasswd/tail" | jq '{data: .data, reason: .meta.reason}'`
3. **Expected**: `200` com `data: null` e `reason` em
   `session-rejected` / `session-not-found`. **Nenhum** byte de fora de
   `~/.claude/projects` no payload. Repetir com um symlink dentro da raiz
   apontando para fora — mesmo resultado.

## Scenario 9: Roundtrip End-to-End (OBRIGATORIO — backend↔frontend)

Valida que o payload **real** do backend casa com o contrato de
`contracts/sessions-api.md` e com o tipo consumido pelo front-end.
**Nao use mock. Nao use fixture. Nao parseie um objeto de teste.**

> **Por que este cenario nao e formalidade**: este repositorio ja carregou um
> drift `snake_case` vs `camelCase` que sobreviveu 40 ondas porque toda a suite
> parseava mocks e fixtures — `tsc` e `vitest` ficaram verdes o tempo todo
> enquanto o payload real divergia do tipo. Suite verde nao prova borda correta;
> **so o payload real prova**. Some-se a isso a definicao DUPLA de DTO deste
> repo (interface manual + schema Zod): editar so um dos dois passa no
> typecheck e quebra em runtime, e este cenario e o que expoe isso.

1. Subir o backend de verdade: `npm run dev` (Fastify na porta `3001`).
2. Capturar o payload real em disco, sem intermediarios:
   ```sh
   curl -s "$API/sessions" > /tmp/st-real-list.json
   SID=$(jq -r '.data.sessions[0].sessionId' /tmp/st-real-list.json)
   curl -s "$API/sessions/$SID/tail?lines=20" > /tmp/st-real-tail.json
   ```
3. Conferir **nomes e caixa** dos campos contra `contracts/sessions-api.md`:
   ```sh
   jq -r '.data.sessions[0] | keys_unsorted[]' /tmp/st-real-list.json
   jq -r '.data | keys_unsorted[]' /tmp/st-real-tail.json
   jq -r '.data.entries[0] | keys_unsorted[]' /tmp/st-real-tail.json
   ```
   Nenhuma chave pode vir em `snake_case`. Atencao especial a `sessionId`: o
   arquivo `.jsonl` de origem contem **as duas formas** (`sessionId` e
   `session_id`) na mesma linha — se a conversao vazar a forma snake para o
   DTO, e exatamente aqui que aparece.
4. Conferir **tipos**, sem coercao silenciosa:
   ```sh
   jq -r '.data.sessions[0] | to_entries[] | "\(.key): \(.value|type)"' /tmp/st-real-list.json
   jq -r '.data.entries[0] | to_entries[] | "\(.key): \(.value|type)"' /tmp/st-real-tail.json
   ```
   `sizeBytes`/`returnedLines`/`skippedLines` MUST ser `number` (nunca `string`);
   `live`/`textTruncated`/`truncatedByBytes` MUST ser `boolean` (nunca `"true"`).
5. Parsear o payload real com o schema Zod **de producao** (o mesmo que o
   front-end usa), nao com uma copia local:
   ```sh
   node --input-type=module -e "
     import { readFileSync } from 'node:fs';
     import { ApiEnvelopeSchema, SessionsListDTOSchema, SessionTailDTOSchema }
       from './packages/shared-types/dist/index.js';
     ApiEnvelopeSchema(SessionsListDTOSchema)
       .parse(JSON.parse(readFileSync('/tmp/st-real-list.json','utf8')));
     ApiEnvelopeSchema(SessionTailDTOSchema)
       .parse(JSON.parse(readFileSync('/tmp/st-real-tail.json','utf8')));
     console.log('roundtrip OK');
   "
   ```
   (rodar `npm run build -w @cstk-panel/shared-types` antes, se `dist/` estiver
   desatualizado)
6. Conferir a **paridade das duas definicoes** — o modo de falha proprio deste
   repo: os campos da interface manual e os do schema Zod MUST coincidir.
   ```sh
   grep -n -A20 'interface SessionSummaryDTO' packages/shared-types/src/entities.ts
   grep -n -A20 'SessionSummaryDTOSchema'     packages/shared-types/src/schemas/entities.ts
   npm run test -w @cstk-panel/shared-types
   ```
7. Abrir `$WEB/#/sessions` e a tela de detalhe de uma sessao; confirmar no
   console do navegador que **nao ha erro de parse do Zod** (o `fetchApi` valida
   toda resposta com `ApiEnvelopeSchema`).
8. **Expected**: zero divergencia entre (a) o payload real capturado nos
   arquivos `/tmp/st-real-*.json`, (b) o contrato declarado em
   `contracts/sessions-api.md`, (c) a interface manual em `entities.ts`,
   (d) o schema Zod em `schemas/entities.ts` e (e) o consumo no navegador.
   Qualquer divergencia detectada AQUI custa uma onda; detectada tarde, custa
   dezenas.

## Scenario 10: Conteudo UNTRUSTED e renderizado literal (FR-005 / SC-005)

1. Localizar (ou preparar numa raiz de fixture, como no Scenario 7) uma sessao
   cujo transcript contenha markup ativo — por exemplo um bloco
   `<script>alert(1)</script>` ou `<img onerror=...>` dentro do texto.
2. Abrir a tela de detalhe dessa sessao no navegador.
3. Inspecionar o DOM do bloco de transcript.
4. **Expected**: o markup aparece como **texto visivel**, e no DOM esta como
   `textContent` de um `<pre>` — nao ha elemento `<script>`/`<img>` criado, nao
   ha execucao, nenhum `dangerouslySetInnerHTML` no caminho. Nenhuma diretiva
   embutida no transcript altera o comportamento da tela.

## Scenario 11: Nada foi escrito (FR-009 / FR-010 / Principio I)

1. Registrar o estado anterior:
   ```sh
   find ~/.claude/projects -name '*.jsonl' -newermt '-1 minute' | wc -l
   md5 ~/.claude/cstk/knowledge.db
   ls -la ~/.claude/projects/*/ | md5
   ```
2. Exercitar a feature: abrir a listagem, abrir 3 sessoes, deixar o auto-refresh
   rodar por ~2 minutos.
3. Repetir os comandos do passo 1.
4. `npm run lint:readonly-check`
5. **Expected**: nenhum `.jsonl` com `mtime` alterado pela navegacao; hash da
   `knowledge.db` inalterado; gate imprime **`OK: no mutation verbs`**;
   `grep -rn "'POST'\|'PUT'\|'PATCH'" apps/server/src/routes/sessions.ts`
   retorna vazio.

## Scenario 12: Segredo no transcript nao chega ao navegador (block-004 / §Seguranca de Conteudo)

**Ramo A — cstk disponivel (`scrubMode: 'cstk+internal'`)**

1. Numa raiz de fixture (como no Scenario 7), preparar um `.jsonl` cujo texto de
   uma entrada contenha, em linhas distintas:
   - `AKIAIOSFODNN7EXAMPLE`
   - `Authorization: Bearer abc.def.ghi`
   - `password=hunter2`  (valor curto — 7 caracteres)
   - um bloco `-----BEGIN RSA PRIVATE KEY-----` ... `-----END RSA PRIVATE KEY-----`
2. `curl -s 'http://localhost:3001/api/v1/sessions/<uuid>/tail' | jq -r '.data.entries[].text'`
3. **Expected**: nenhum dos quatro valores aparece em claro. `data.scrubMode` e
   `'cstk+internal'`. O bloco de chave privada foi redigido **inteiro**, nao
   apenas a primeira linha.
4. **Expected (o ponto do cenario)**: `password=hunter2` **tambem** esta
   redigido. O filtro do cstk sozinho o deixa passar — a regra de atribuicao
   exige valor com 20+ caracteres — e e o redactor interno encadeado que o pega.
   Se este valor aparecer em claro, o passo 2 da cadeia nao esta rodando quando o
   cstk esta presente.

**Ramo B — cstk ausente (`scrubMode: 'internal'`)**

5. Apontar `CSTK_SECRETS_FILTER` para um caminho inexistente e reiniciar o
   servidor.
6. Repetir o passo 2.
7. **Expected**: resposta `200` normal, `degraded: false`, `data.scrubMode` e
   `'internal'`, e os quatro valores continuam redigidos. A ausencia do cstk
   degrada a qualidade do scrub — **nunca** o desativa, nunca serve cru, nunca
   quebra a tela.

**Ramo C — subprocesso falha no meio**

8. Apontar `CSTK_SECRETS_FILTER` para um script que escreve algumas linhas em
   stdout e entao sai com `exit 1`.
9. Repetir o passo 2.
10. **Expected**: a saida parcial do script e **descartada**; o redactor interno
    roda sobre a entrada original; nenhum valor sensivel em claro;
    `scrubMode: 'internal'`; nenhum `5xx`.

**Ramo D — cobertura da listagem**

11. `curl -s 'http://localhost:3001/api/v1/sessions' | jq '.data.sessions[0], .data.scrubMode'`
12. **Expected**: `scrubMode` presente; `projectPath` e `projectSlug` sao
    strings ja redigidas (um `cwd` contendo, por exemplo, `.../token=<40 chars>/...`
    aparece com `[REDACTED]`). O scrub nao e privilegio da rota de tail.

**Ramo E — o scrub e do servidor, nao do cliente**

13. `grep -rn "REDACTED" apps/web/src/` → **vazio**. Nenhuma logica de redacao
    vive no front-end; se vivesse, o segredo ja teria trafegado.

**Ramo F — conteudo EXATO do log em falha do subprocesso (CHK012, plan.md
achado LOW "Vazamento por log")**

14. Repetir o Ramo C (script que sai `exit 1` apos escrever stdout parcial
    contendo, de proposito, um segredo — ex. `password=hunter2-vazou-no-stdout`)
    e capturar a saida de log do servidor (stderr/arquivo de log conforme
    config atual) para esta requisicao.
15. **Expected — o log contem EXATAMENTE dois campos e nenhum outro**:
    `{ "exitCode": 1, "timedOut": false }` (nomes de campo ilustrativos; o
    formato real segue o logger do servidor, mas o CONJUNTO de dados e
    fechado a estes dois). **Nao aparece no log**: o conteudo enviado ao
    subprocesso (stdin), a saida parcial do subprocesso (stdout, mesmo que
    truncada), nem `stderr` bruto do subprocesso. Em particular, a string
    `password=hunter2-vazou-no-stdout` do passo 14 **MUST NOT** aparecer em
    lugar nenhum do log — se aparecer, o cenario reprovou.
16. Repetir os passos 14-15 com um script que **dorme alem do
    `CSTK_SECRETS_FILTER_TIMEOUT_MS`** em vez de sair com `exit 1`.
17. **Expected**: mesmo par de campos, agora `{ "exitCode": null, "timedOut":
    true }` (ou equivalente do logger real) — o codigo de saida e
    inaplicavel/nulo porque o processo foi morto por timeout, nao terminou
    sozinho; novamente, nenhum conteudo de stdin/stdout/stderr no log.

## Scenario 12.1: Entrada patologica no redactor interno — teto de tempo medido (CHK009/CHK010, plan.md achado MEDIUM "ReDoS no redactor interno")

**Objetivo**: provar, com numero medido nesta maquina de referencia (nao
suposto), que a abordagem escolhida (padroes ancorados + maquina de estados
linha-a-linha) e ordens de magnitude mais rapida que a alternativa proibida
(regex guloso com quantificador aninhado) sobre o mesmo tipo de entrada
adversarial.

Ambiente da medicao: macOS (Darwin 25.5.0), `node --version` → `v24.19.0`,
script de probe descartavel executado via
`node redos-probe.js` (nao versionado — apenas medicao, sem codigo de
producao nesta FASE).

1. **Padrao proibido** (o que o redactor **nao pode** usar):
   `/^(a+)+$/` — quantificador aninhado classico (CWE-1333) — testado contra
   `'a'.repeat(N) + '!'` (o `!` final forca backtracking completo por nao
   casar):

   | N (chars) | Tempo medido |
   |-----------|--------------|
   | 20 | 30.661 ms |
   | 24 | 78.711 ms |
   | 28 | 1251.788 ms |

   **Expected**: crescimento super-linear visivel a olho nu (~16x de tempo
   para +4 chars de entrada, entre N=24 e N=28) — a assinatura do backtracking
   catastrofico. Extrapolando a mesma razao, um `sessionId`/transcript
   adversarial de poucas centenas de caracteres neste padrao travaria o
   processo Node por minutos a horas — inaceitavel para uma rota servida por
   requisicao.

2. **Padrao ancorado equivalente, sem aninhamento**: `/^a+$/` contra a MESMA
   familia de entrada, incluindo tamanhos de producao realistas:

   | N (chars) | Tempo medido |
   |-----------|--------------|
   | 20 | 0.056 ms |
   | 24 | 0.038 ms |
   | 28 | 0.001 ms |
   | 1.000.000 | 0.882 ms |
   | 5.000.000 | 5.707 ms |

   **Expected**: tempo linear e proximo de zero mesmo a 5.000.000 de
   caracteres — nunca cresce de forma explosiva com o tamanho da entrada.

3. **Maquina de estados linha-a-linha para o bloco `BEGIN...PRIVATE KEY`**
   (a abordagem real do redactor), contra um blob adversarial de ~5 MB com um
   bloco de chave privada no meio de ruido:

   **Expected medido**: `input bytes=5243045 -> 12.290 ms`,
   `contains-marker=true` (bloco foi redigido), `contains-raw-key=false`
   (nenhum fragmento da chave sobrevive em claro).

**Teto de regressao a documentar no PR de implementacao (tarefa 3.1)**: o
redactor real, sobre um blob adversarial de ate 5 MB (o teto de bytes da
janela de tail, FR-006), MUST completar em **menos de 100 ms** nesta classe de
maquina — teto com folga de ~8x sobre o medido acima (12.29 ms), nao um numero
redondo inventado. Se a implementacao real medir acima disso, a tarefa 3.1
reabre com o numero medido, nao com este teto.

4. Teto (revisao de artefato): confirmar que os tres numeros acima (linhas 1-3)
   tem o comando/ambiente que os gerou citado ao lado — nenhum numero aparece
   sem a medicao que o produziu (Principio VI).

## Scenario 12.2: Matriz positiva/negativa do scrub (CHK003/CHK005, plan.md §Cobertura medida do filtro do cstk)

**Objetivo**: o `{20,}` piso de comprimento na regra de atribuicao do
`secrets-filter.sh` existe para evitar falso-positivo em prosa comum; o
redactor interno encadeado enfrenta o mesmo dilema, agravado por servir
transcript **e** prosa de conversa no mesmo campo `text`. Um teste que so
mede cobertura (positivos) passa com um redactor que tambem destroi prosa
legitima (falsos positivos). Este cenario coloca os dois conjuntos **lado a
lado**, com entrada e saida esperada explicitas para cada linha — e o
criterio de aceite que a tarefa 3.1 (redactor interno) e o Scenario 12
(Ramos A/B) MUST satisfazer.

**Casos que DEVEM ser redigidos** (positivos — entrada por linha isolada,
saida esperada apos a cadeia `cstk scrub` → redactor interno):

| # | Entrada (linha isolada) | Saida esperada |
|---|--------------------------|-----------------|
| P1 | `password=hunter2` (7 chars — abaixo do piso `{20,}` do cstk) | `password=[REDACTED]` (redigido pelo redactor interno, nao pelo cstk) |
| P2 | `-----BEGIN RSA PRIVATE KEY-----`\n`MIIEowIBAAKCAQEA...`\n`-----END RSA PRIVATE KEY-----` (bloco completo, corpo arbitrario) | bloco inteiro substituido por um unico `[REDACTED]` — nenhuma linha do corpo sobrevive |
| P3 | `Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abcdefghijklmnop.zzzzzzzzzzzzzzzz` (token longo) | `Authorization: Bearer [REDACTED]` |
| P4 | `AKIAIOSFODNN7EXAMPLE` (chave AWS, formato `AKIA` + 16 chars) | `[REDACTED-AWS-KEY]` |

**Casos que NAO PODEM ser redigidos** (negativos — a mesma cadeia aplicada a
prosa legitima de conversa; qualquer redacao aqui e um falso-positivo que
reprova o cenario):

| # | Entrada (linha isolada) | Saida esperada |
|---|--------------------------|-----------------|
| N1 | `o campo password e obrigatorio neste formulario` | identica, sem `[REDACTED]` — nao ha `password=<valor>`, so a palavra em prosa |
| N2 | `o token de acesso expira em 1 hora` | identica, sem `[REDACTED]` — mencao a "token" sem valor de segredo ao lado |
| N3 | `nao existe segredo aqui` | identica, sem `[REDACTED]` — palavra "secret"/"segredo" em sentido comum, sem atribuicao `secret=<valor>` |

**Expected**: rodar as 4 linhas positivas (P1-P4) e as 3 linhas negativas
(N1-N3) através da MESMA cadeia de scrub (`cstk scrub` → redactor interno)
produz exatamente as saidas da tabela — nenhuma das P1-P4 escapa em claro
(cobertura), e nenhuma das N1-N3 e alterada (nao ha destruicao de prosa). O
teste de implementacao (tarefa 3.1) MUST cobrir as 7 linhas como casos
individuais, nao apenas os 4 positivos.

---

## Baseline a nao regredir

Antes de considerar a feature concluida, os quatro comandos abaixo MUST estar
verdes. O baseline de entrada informado na abertura desta feature era de **755
testes passando**; esse numero **nao foi reconfirmado por execucao da suite
nesta onda** — rode `npm test` e ancore o numero real antes de usa-lo como
referencia de regressao:

```sh
npm run typecheck            # limpo
npm test                     # baseline de entrada + os testes novos
npm run lint:readonly-check  # "OK: no mutation verbs"
npm run build                # shared-types -> server -> web
```

Zero rotas nao-`GET` no repositorio fora de `/api/v1/bridge/*`.
