# Data Model: Human Bridge (Intervencoes)

**Feature**: `human-bridge` | **Fase**: Phase 1 | **Data**: 2026-08-29

Legenda de veracidade conforme [`research.md`](research.md): `[MEDIDO]` /
`[VERIFICADO]` / `[PROPOSTA — a validar na implementacao]`.

Ha **duas** persistencias nesta feature, com donos, ciclos de vida e
autoridades diferentes. Confundi-las e a falha que a emenda 2.0.0 da
constitution do painel existe para impedir.

| Store | Dono | Autoridade | Ciclo de vida |
|-------|------|-----------|---------------|
| `bridge.db` | painel (`apps/server`) | **transporte** — nunca fonte da verdade | por intervencao, sem expurgo (FR-020) |
| `.operator_answers[]` | agente (servidor MCP, via runtime cstk) | **registro canonico** (FR-012) | por execucao, append-only |

---

## Achado de seguranca que define o modelo: o `session_id` NAO atravessa a fronteira HTTP

O `session_id` das tools `mcp__cstk-state__*` e um **token de capacidade**
(>= 128 bits CSPRNG). O toolkit ja o trata como segredo em toda fronteira:
`[VERIFICADO: mcp/state-server/src/runtime/exec.ts:111]` —
`const SENSITIVE_FLAGS: ReadonlySet<string> = new Set(["--token"]);` — com
redacao inclusive na mensagem de erro reconstruida internamente pelo `execFile`
`[VERIFICADO: exec.ts:142-143, 176-179]`.

Gravar esse token em `bridge.db` e envia-lo por HTTP para exibicao numa fila
seria exfiltracao direta: `bridge.db` e um arquivo em disco, sem cifra, lido por
uma UI. **O modelo abaixo evita isso por construcao**, e nao por disciplina de
quem implementa.

**Como a clausula "toda resposta e roteada por `session_id`, nunca por
`execution_id`" (constitution do painel, Principio I) e honrada mesmo assim**:
o roteamento acontece **inteiramente dentro da chamada MCP**, antes de qualquer
HTTP. A tool recebe o token, `resolveSession()` resolve fail-closed o `stateDir`
daquela execucao `[VERIFICADO: mcp/state-server/src/session/resolve.ts:40-49,
`SessionMismatchError` ... "NUNCA cai em fallback para 'a execucao ativa mais
provavel'"]`, e a resposta e gravada NAQUELE `stateDir`. O painel nao roteia nada:
ele e uma caixa-postal indexada por `questionId`, e o `questionId` so e conhecido
pela chamada que o criou. Consequencia direta: SC-005 ("0% das respostas
aplicadas a sessao diferente") e satisfeito por construcao, nao por teste.

**Identidade de EXIBICAO** (FR-014) usa campos nao-secretos ja disponiveis no
retorno de `resolveSession` — `targetProjectPath`, `shortName`, `executionKind`
`[VERIFICADO: resolve.ts:31-37, interface com os campos stateDir/executionKind/
shortName/targetProjectPath/mode/container]`. Nenhum deles e o token.

---

## Entity: Intervention (`bridge.db`)

Store: `~/.claude/cstk/bridge.db` (override `CSTK_BRIDGE_DB`) — Decision 2 de
`research.md`. Tabela `interventions` `[PROPOSTA — a validar na implementacao]`.

| Coluna (snake_case) | Tipo | Null? | Notas |
|---------------------|------|-------|-------|
| `question_id` | TEXT | NOT NULL | **PK**. CSPRNG gerado pelo painel na criacao. Unico correlator entre MCP e painel. |
| `project_path` | TEXT | NOT NULL | Identidade de exibicao (FR-014). Nunca usado para roteamento. |
| `project` | TEXT | NOT NULL | `basename(project_path)`, denormalizado para a fila. |
| `short_name` | TEXT | NULL | Feature, quando `execution_kind = feature-00c`. |
| `execution_kind` | TEXT | NOT NULL | `agente-00c` \| `feature-00c`. |
| `kind` | TEXT | NOT NULL | CHECK `IN ('choice','confirm','text')` — enum fechado (FR-004). |
| `question` | TEXT | NOT NULL | Texto exibido. **UNTRUSTED** (Principio V do painel): vem de agente. |
| `options_json` | TEXT | NULL | Array JSON; NOT NULL sse `kind='choice'`. Enum fechado das respostas aceitas (FR-005). |
| `default_value` | TEXT | NOT NULL | Valor seguro. Guardado so para exibicao ("o que acontece se ninguem responder"); quem o **aplica** e o servidor MCP (C-4). |
| `resolution` | TEXT | NULL | CHECK `IN ('answered','declined')`. **So o operador escreve.** `timeout`/`unavailable`/`failed` NUNCA aparecem aqui — ver "Estados derivados". |
| `applied_value` | TEXT | NULL | Token de desfecho escolhido pelo operador. NOT NULL sse `resolution` NOT NULL. |
| `untrusted_text` | TEXT | NULL | So em `kind='text'` + `resolution='answered'`. Ja escrubado e truncado na ENTRADA (R-TEXT-2/R-TEXT-3). |
| `expires_at` | TEXT | NOT NULL | ISO 8601 UTC. `created_at + MCP_ASK_TIMEOUT_MS` efetivo daquela chamada. |
| `created_at` | TEXT | NOT NULL | ISO 8601 UTC. Origem de "ha quanto tempo espera" (FR-014). |
| `resolved_at` | TEXT | NULL | ISO 8601 UTC. NOT NULL sse `resolution` NOT NULL. |

Indices `[PROPOSTA]`: `idx_interventions_open ON interventions(expires_at) WHERE resolution IS NULL`
(fila de pendentes) e `idx_interventions_created ON interventions(created_at DESC)`
(ordenacao da fila por tempo de espera).

### Estados derivados — por que `timeout` nao e coluna

O estado exibido NAO e uma coluna; e derivado na leitura:

```
resolution IS NOT NULL        -> 'answered' | 'declined'   (decisao humana ativa)
now >= expires_at             -> 'expired'                 (ninguem respondeu)
caso contrario                -> 'open'
```

**Rationale (FR-011 + FR-012 + FR-020)**: se `timeout` fosse coluna, alguem teria
de escreve-la — e isso exigiria ou uma rotina periodica (**proibida por FR-020**)
ou um `UPDATE` disparado por um `GET` (efeito colateral escondido numa leitura).
Derivar de `expires_at` entrega FR-011 ("nunca confundir decisao humana com
aplicacao automatica") de forma mais forte: uma linha com `resolution IS NULL`
**nao consegue** ser lida como decisao humana, porque nao ha valor la para ler.

Os desfechos `timeout`, `unavailable` e `failed` sao registrados **do lado do
agente**, em `.operator_answers[]` — que e onde FR-012 diz que a verdade mora.
`bridge.db` nao sabe que a sessao seguiu; nao precisa saber.

**"Inalcancavel"** (Edge Case "projeto que nao existe mais"): derivado na
exibicao verificando se `project_path` ainda existe em disco. A linha continua
visivel (nao esconder historico); a acao de responder fica desabilitada.

### State transitions

```
              POST /bridge/interventions
                        |
                        v
                    [ open ] ------ now >= expires_at ------> [ expired ] (derivado)
                     |    |                                        |
   POST .../answer   |    | POST .../answer (declined)             | POST .../answer
   (resolution=      |    |                                        v
    answered)        |    |                                    409 REJEITADO
                     v    v                                    (FR-016)
              [ answered ] [ declined ]  ---- 2a tentativa ---> 409 REJEITADO
```

**Transicao unica e irreversivel**: `open -> answered|declined` acontece por
`UPDATE ... WHERE question_id = ? AND resolution IS NULL` com verificacao de
`changes === 1` `[PROPOSTA]`. O segundo escritor concorrente ve `changes === 0` e
recebe `409` — e assim que o Edge Case "duas pessoas respondendo ao mesmo tempo"
("a primeira resposta valida vence") vira invariante de banco em vez de corrida.

---

## Entity: OperatorAnswer (`.operator_answers[]`, state da execucao)

Array irmao top-level no `state.json`/`state.db` da execucao, **append-only**
(contrato §7). Sob backend SQLite cai no catch-all `execution.extra_fields`,
reconciliado no `read` — mesmo precedente ja em producao de `.suggestions`.

**Primitiva de escrita — sem script novo, sem dep nova**:

```
state-rw.sh set --state-dir <SD> --field '.operator_answers' --value <json-array>
```

Le `.operator_answers // []`, concatena, reescreve. Consequencia: **nenhuma**
edicao em `_state-rw-db.sh`, nenhum helper POSIX novo, nenhuma dependencia nova —
o Principio II da constitution raiz segue **PASS** sem carve-out.

**NUNCA `.optin_responses[]`**: aquele array tem chave natural `(execution, field)`
com enum fechado de campos e e lido pela guarda que recusa abrir a onda-001
(Invariante I-2). Polui-lo com perguntas arbitrarias quebraria a guarda.

Shape — os **mesmos 6 campos** de `StoredOptinResponse`
`[VERIFICADO: mcp/state-server/src/tools/collect_optins.ts:328-334 —
field/channel/outcome/applied_value/recorded_at/reason]`, com `field` -> `question_id`,
mais um setimo campo:

| Campo (snake_case) | Tipo | Null? | Notas |
|--------------------|------|-------|-------|
| `question_id` | string | NOT NULL | Correlator; casa com `interventions.question_id`. |
| `channel` | string | NOT NULL | **`"panel"`** nesta superficie (invariante C-5). `panel-hook` fica reservado as superficies 2 e 3. |
| `outcome` | enum | NOT NULL | `answered` \| `declined` \| `timeout` \| `unavailable` \| `failed`. **Nao existe `absent`** nesta superficie (contrato §5). |
| `applied_value` | string | NOT NULL | Valor efetivamente aplicado. Em `kind='text'` carrega o **token de desfecho**, nunca o texto (R-TEXT-1). |
| `recorded_at` | string | NOT NULL | ISO 8601 UTC. |
| `reason` | string \| null | NULL ok | Motivo da degradacao. Escrubado + truncado a 2048 bytes. |
| `untrusted_text` | string \| null | NULL ok | **Campo adicional.** So em `kind='text'` + `outcome='answered'`. Ja escrubado (R-TEXT-3) e truncado (R-TEXT-2). |

### Regras de leitura (identicas as de `.optin_responses[]`, para nao criar um segundo dialeto)

- **R-1 (precedencia)**: vence o registro de maior `recorded_at`.
- **R-2 (terminalidade)**: `unavailable` e `failed` sao **NAO-terminais** (ninguem
  chegou a ser perguntado de fato); `answered`, `declined` e `timeout` sao
  **terminais**.

### C-4 — gravado ANTES do retorno, em todo desfecho

`default_value` e aplicado em **todo** desfecho `!= answered`, e o registro em
`.operator_answers[]` e gravado **antes** de a tool retornar. Nunca trava, nunca
fica sem rastro. Combinado com C-1 (degradacao retorna `outcome:"accepted"` no
envelope de tool), o orquestrador nunca ve erro e nunca precisa reter ou repetir.

### Trilha de auditoria

**1** linha em `<projeto-alvo>/.claude/enforcement-log.jsonl` por resposta
persistida, com `source: "mcp-ask-operator"`, best-effort, **nunca lanca**
`[VERIFICADO: mesmo contrato de `appendOptinDecisionRecord`,
mcp/state-server/src/audit/log.ts:189-202, com `source: "mcp-collect-optins"`]`.
O valor ja escrubado alimenta a linha — **nunca um segundo subprocesso de scrub**
`[VERIFICADO: collect_optins.ts:394-408, "Aplicado UMA vez; o valor ja escrubado
tambem alimenta a linha de enforcement-log.jsonl (M2) abaixo, sem rodar um
segundo subprocesso"]`.

---

## Teto de texto livre: 2048 bytes, reusando orcamento existente

`untrusted_text` e truncado por budget de **bytes UTF-8**, nao por contagem de
caracteres, reusando a constante ja existente
`[VERIFICADO: mcp/state-server/src/audit/log.ts:66, `const REASON_MAX_BYTES = 2048; // 2 KiB`]`
em vez de introduzir numero novo. Ordem obrigatoria do pipeline de entrada
(R-TEXT-3, uma unica passagem):

```
texto cru do operador
  -> strip de caracteres de controle
  -> secrets-filter.sh scrub        (UMA vez; e este valor que persiste)
  -> truncateUtf8ByteBudget(2048)
  -> persiste em bridge.db  E  em .operator_answers[]  E  na linha de audit
```

**Correcao factual sobre a cobertura do scrub** — ver Decision 0 de `research.md`.
As duas lacunas citadas no contrato (`password=hunter2` em claro; blocos PEM
intactos) foram **fechadas** `[MEDIDO 2026-08-29]`. As tres defesas
complementares permanecem obrigatorias porque o scrub e um filtro por heuristica
de padrao — cobre o que reconhece, e nao ha prova de que reconheca tudo. "Passou
pelo scrub" continua NAO significando "nao contem segredo".

---

## Relacionamentos

```
ResolvedSession (memoria do processo MCP, NUNCA persistida no painel)
      | token de capacidade -> stateDir  [fail-closed, resolve.ts]
      v
Intervention (bridge.db)  --- question_id (1:1) --->  OperatorAnswer (.operator_answers[])
      ^                                                        ^
      | POST/GET por questionId                                | escrita pelo AGENTE
      |                                                        |
  painel (transporte)                                    fonte da verdade (FR-012)
```

A seta so aponta para fora do painel. Nao existe caminho em que `bridge.db`
alimente `knowledge.db`, `state.json` ou qualquer tela de observabilidade
(FR-017, FR-018).

---

## FR-018 — isolamento do corpus: verdadeiro hoje, exige guard de regressao

**Por que e verdadeiro hoje** `[VERIFICADO]`:
- `cstk recall --reindex` varre raizes procurando `state.json`/`state-history` e
  `~/.claude/projects/*/memory/` (`cli/lib/recall.sh:235, :3456, :3521`); `--db`
  aponta explicitamente para `knowledge.db` (`recall.sh:177-188`). Um `.db` irmao
  nunca e alvo de varredura.
- Nenhuma projecao de ingestao le a chave `.operator_answers` — a leitura de
  `extra_fields` e **por chave conhecida** (foi assim que `.suggestions` precisou
  de fix dedicado na 8.0.1 para passar a ser ingerido).

**Por que isso nao basta**: ambos os fatos sao propriedades acidentais do codigo
atual, nao invariantes declaradas. Um `--reindex` futuro que passe a globbar
`~/.claude/cstk/*.db`, ou uma ingestao generica de `extra_fields`, quebraria
FR-018 em silencio. O plano exige **teste de regressao explicito**: apos
`--ingest` + `--reindex` sobre uma execucao com `.operator_answers[]` populado e
`bridge.db` presente, nenhuma tabela da `knowledge.db` contem o `question_id`, o
`untrusted_text` nem o texto da pergunta.
