# Research: Allowlist MCP para orquestradores 00c

**Feature**: `orchestrator-mcp-allowlist` | **Date**: 2026-08-16
**Spec**: [spec.md](./spec.md)

## Regra de proveniencia deste documento (Principio VI)

Cada afirmacao factual abaixo carrega um dos tres rotulos:

- **[FONTE: path:linha]** — arquivo do repo LIDO nesta onda; a citacao e
  literal ou uma parafrase fiel do trecho referenciado.
- **[SONDAGEM]** — resultado de sondagem empirica desta sessao; identifica
  o artefato do harness que sustenta a afirmacao e, quando o transcript
  bruto NAO foi persistido, diz isso explicitamente.
- **[PROPOSTA — a validar na implementacao]** — desenho novo proposto por
  este plano; ainda NAO existe no repo e NAO deve ser lido como
  comportamento real.

---

## Decision 1 — O guard atual e revogado, e ja era estruturalmente inerte

**Decision**: remover os dois scenarios textuais de
`tests/test_orchestrator-mcp-fallback.sh` que proibem `mcp__*` no
frontmatter, e substitui-los por um guard de composicao de allowlist
(FR-001, FR-002).

**Rationale**:

O guard vigente vive em dois scenarios
[FONTE: tests/test_orchestrator-mcp-fallback.sh:59-66 e :68-75]. Ambos
aplicam a mesma expressao:

```sh
if grep -Eq '^\s*-\s*mcp__' "$AGENT_ORCH"; then
```

[FONTE: tests/test_orchestrator-mcp-fallback.sh:61 e :70]

Essa ERE casa a forma de **lista YAML** (`- mcp__algo`). O frontmatter
real dos dois orquestradores usa a forma **inline**:

- `tools: Agent, Skill, Bash, Read, Write, Edit, Glob, Grep`
  [FONTE: plugins/cstk/agents/agente-00c-orchestrator.md:4]
- `tools: Agent, Skill, Bash, Read, Write, Edit, Glob, Grep`
  [FONTE: plugins/cstk/agents/agente-00c-feature-orchestrator.md:4]

Consequencia factual: o guard atual **nunca falharia** se alguem
adicionasse `mcp__cstk-state__record_decision` a linha inline — a ERE nao
casa esse formato. Ele so protegia contra a forma de lista, que nenhum
dos 7 arquivos de agente usa
[FONTE: `grep -n '^tools:' plugins/cstk/agents/*.md` — os 7 arquivos usam
forma inline: agente-00c-clarify-answerer.md:5, agente-00c-clarify-asker.md:5,
agente-00c-feature-orchestrator.md:4, agente-00c-orchestrator.md:4,
data-veracity-verifier.md:5, feature-00c-clarify-answerer.md:5,
feature-00c-clarify-asker.md:5].

Portanto a revogacao nao remove protecao efetiva: ela **troca uma
protecao inerte contra a premissa errada por uma protecao ativa sobre a
garantia real** (FR-007). O guard novo MUST parsear as duas formas, sob
pena de repetir o mesmo ponto cego.

**Alternatives considered**:

- *Corrigir a ERE do guard antigo para tambem casar a forma inline*:
  rejeitado — consertaria a deteccao, mas manteria a premissa errada
  (proibir `mcp__*`), que e exatamente o que FR-001 revoga.
- *Deixar o guard antigo e adicionar o novo ao lado*: rejeitado — os dois
  seriam mutuamente contraditorios assim que FR-003 adicionasse as tools
  ao frontmatter; a suite ficaria vermelha por construcao.

---

## Decision 2 — Base empirica que sustenta a inversao da premissa

**Decision**: adotar como regra do guard "allowlist nunca vazia E nunca
composta exclusivamente por `mcp__*`", em vez de "allowlist sem `mcp__*`".

**Rationale**:

O harness de sondagem desta sessao vive em
`<scratchpad>/fase0/` (fora do repo; diretorio de trabalho temporario da
sessao). Ele contem quatro definicoes de subagente-sonda, cada uma
isolando uma composicao de allowlist:

| Sonda | Allowlist declarada | Fonte |
|-------|---------------------|-------|
| `probe-sub` | **so-MCP** (`mcp__probe__ping, mcp__probe__ask_tier`) | [SONDAGEM: fase0/.claude/agents/probe-sub.md:4] |
| `probe-sub-noallow` | **so-nativa** (`Skill, Bash, Read, Write, Edit, Glob, Grep`) — espelha o frontmatter atual dos orquestradores | [SONDAGEM: fase0/.claude/agents/probe-sub-noallow.md:4] |
| `probe-sub-misto` | **mista** (`Bash, Read, Glob, Grep, mcp__probe__ping, mcp__probe__ask_tier`) | [SONDAGEM: fase0/.claude/agents/probe-sub-misto.md:4] |
| `probe-many` | **mista com 25 tools MCP** (`Bash` + `mcp__many__t01..t25`) | [SONDAGEM: fase0/.claude/agents/probe-many.md:4] |

Achados:

1. **Allowlist so-MCP e recusada antes do spawn.** Esta e a afirmacao
   central que inverte a premissa. **Ressalva de proveniencia
   (Principio VI):** o transcript bruto dessa sonda NAO foi persistido no
   harness — o diretorio `fase0/` contem `A2.log`, `A3.log`, `A4.log`,
   `many.log` e `B-probeB-accepts.log`, mas nenhum log da execucao
   so-MCP. A afirmacao esta registrada em prosa na spec ja ratificada
   [FONTE: docs/specs/orchestrator-mcp-allowlist/spec.md:14-20: "o que de
   fato quebra a garantia e uma allowlist composta **somente** por tools
   `mcp__*` (sem nenhuma tool nativa de fallback) — nesse caso o subagente
   e recusado antes mesmo de ser spawnado"] e e herdada dali, nao
   re-verificada nesta onda. O plano NAO depende do texto exato da
   mensagem de recusa: FR-002 exige apenas que a configuracao so-MCP seja
   bloqueada pelo guard, o que e verificavel sem o transcript.

2. **Allowlist mista e segura mesmo com o servidor MCP ausente**: a tool
   nao-resolvida e descartada em silencio e o caminho nativo continua
   funcionando [FONTE: spec.md:18-20]. A sonda `probe-sub-misto` foi
   construida exatamente para isso: instrui `echo FALLBACK_BASH_OK` via
   Bash e, se `mcp__probe__ping` nao existir, responder `MCP_AUSENTE` e
   seguir "sem erro" [SONDAGEM: fase0/.claude/agents/probe-sub-misto.md:7-13].
   Mesma ressalva do item 1: o transcript dessa execucao nao foi
   persistido.

3. **Allowlist so-nativa nunca alcanca o servidor** — evidencia direta e
   persistida: `A4.log` (execucao da sonda `probe-sub-noallow`) registra
   `initialize` + `tools/list` e **zero** mensagens `tools/call`
   [SONDAGEM: fase0/A4.log — contagem `grep -c 'tools/call'` = 0],
   enquanto `A2.log` e `A3.log` registram 1 `tools/call` cada. Isso e a
   medida do defeito que a feature conserta: com o frontmatter atual, um
   orquestrador nunca emite uma chamada ao servidor.

4. **Nenhum teto observado ate 25 tools MCP + 1 nativa** — evidencia
   direta e persistida: `many.log` registra `tools/call` para `t17`
   [SONDAGEM: fase0/many.log, linha 5: `{"method":"tools/call","params":{"name":"t17",...}}`],
   com a allowlist de 25 tools declarada em
   [SONDAGEM: fase0/.claude/agents/probe-many.md:4]. Sustenta FR-009
   [FONTE: spec.md:257-265]. As 7 tools do `cstk-state` sao ~28% dessa
   margem observada.

**Alternatives considered**:

- *Re-executar as sondas so-MCP e mista nesta onda para persistir o
  transcript*: rejeitado para esta rodada — exige sessao interativa do
  harness e nao muda nenhuma decisao de desenho (o guard bloqueia a
  configuracao so-MCP independentemente do texto da recusa). Registrado
  como lacuna de proveniencia conhecida, nao como suposicao.

---

## Decision 3 — Deteccao de orquestrador por padrao de nome

**Decision**: o guard descobre seus alvos por glob
`plugins/cstk/agents/*-orchestrator.md`, nunca por lista hardcodeada.

**Rationale**: decisao ja tomada e ratificada (dec-016)
[FONTE: spec.md:164-176 (`## Clarifications`) e FR-002 em spec.md:212-220].
A verificacao empirica registrada na propria spec mostra que o padrao casa
exatamente 2 dos 7 arquivos de agente e nenhum outro
[FONTE: spec.md:169-174]. Confirmado nesta onda por leitura direta do
diretorio: os 7 arquivos sao `agente-00c-clarify-answerer.md`,
`agente-00c-clarify-asker.md`, `agente-00c-feature-orchestrator.md`,
`agente-00c-orchestrator.md`, `data-veracity-verifier.md`,
`feature-00c-clarify-answerer.md`, `feature-00c-clarify-asker.md`
[FONTE: `ls plugins/cstk/agents/`].

**Anti-ponto-cego obrigatorio**: um glob que nao casa nada faz o guard
passar vacuamente. O guard MUST falhar quando o glob resolve para **zero**
arquivos [PROPOSTA — a validar na implementacao]. Isso espelha a
disciplina ja adotada no proprio harness, onde cada isencao de cobertura e
"existence-guarded" e volta a ser orfao real se a fonte sumir
[FONTE: tests/run.sh:565-569 — "Anti-ponto-cego: cada entrada exige que o
teste cobridor EXISTA em disco. Se ele for removido/renomeado, o script
volta a ser flagado como orfao"].

**Alternatives considered**:

- *Lista hardcodeada dos 2 arquivos*: rejeitado por dec-016 — nao
  generaliza para um terceiro orquestrador futuro.
- *Deteccao por conteudo (ex: presenca de `Loop principal`)*: rejeitado —
  acopla o guard a prosa interna do agente, que muda com frequencia.

---

## Decision 4 — Parser de frontmatter: as duas formas, sem jq

**Decision**: o guard extrai a allowlist parseando o bloco de frontmatter
em POSIX sh + `awk`/`sed`, suportando **forma inline** (`tools: A, B, C`) e
**forma de lista YAML** (`tools:` seguido de linhas `- A`), sem depender de
`jq` nem de parser YAML externo. [PROPOSTA — a validar na implementacao]

**Rationale**:

1. Suportar as duas formas e o que impede a repeticao do ponto cego da
   Decision 1. Hoje o repo so usa a forma inline, mas nada obriga isso a
   permanecer verdade.
2. `jq` nao parseia YAML. Introduzir um parser YAML violaria o Principio II
   [FONTE: docs/constitution.md:79 — "II. Scripts POSIX sh Puros, Zero
   Dependencia Externa (NON-NEGOTIABLE)"].
3. O teste que hospeda o guard antigo aborta cedo quando `jq` esta ausente
   [FONTE: tests/test_orchestrator-mcp-fallback.sh:52-55 — "jq ausente —
   pulando suite", `exit 0`]. Um guard estrutural que so roda quando `jq`
   existe e um guard que pode nao rodar. O guard novo, sem `jq`, roda
   sempre — estritamente melhor.

**Regra de veredito** [PROPOSTA — a validar na implementacao], derivada
literalmente de FR-002 e FR-004:

| Condicao da allowlist resolvida | Veredito | Fonte da regra |
|---------------------------------|----------|----------------|
| chave `tools:` ausente do frontmatter | **FAIL** | FR-004 exige "pelo menos uma tool nativa ... no proprio frontmatter `tools:` a qualquer momento" [FONTE: spec.md:225-229] |
| conjunto vazio (`tools:` presente, sem entradas) | **FAIL** | FR-002 [FONTE: spec.md:212-215] |
| so entradas `mcp__*` (zero nativas) | **FAIL** | FR-002 [FONTE: spec.md:212-215] |
| mista (>=1 nativa e >=1 `mcp__*`) | **PASS** | FR-002 / Acceptance Scenario 3 [FONTE: spec.md:41-43] |
| so entradas nativas (zero `mcp__*`) | **PASS** | FR-002 falha "quando, e somente quando" vazio OU so-MCP [FONTE: spec.md:212-215] |
| glob de orquestradores casa zero arquivos | **FAIL** | anti-ponto-cego (Decision 3) |

Nota sobre a ultima linha "so-nativas = PASS": e o estado atual do repo
antes de FR-003. O guard e sobre **seguranca de fallback**, nao sobre
obrigar a presenca de MCP; a presenca das 7 tools e coberta por um assert
separado (FR-003), nao pelo guard de FR-002.

**Alternatives considered**:

- *Usar `jq` sobre um YAML→JSON convertido*: rejeitado — nenhuma
  ferramenta de conversao esta no conjunto de dependencias permitido; o
  carve-out de dependencia obrigatoria da constitution e restrito a camada
  de estado transacional [FONTE: docs/constitution.md:136-139].
- *Regex unica sobre o arquivo inteiro*: rejeitado — casaria ocorrencias de
  `mcp__` na prosa do agente (que esta feature vai justamente adicionar na
  secao de orientacao), produzindo falso-positivo. O parser MUST se
  restringir ao bloco de frontmatter delimitado pelos dois `---`.

---

## Decision 5 — As 7 tools e o prefixo exato do frontmatter

**Decision**: as entradas a adicionar ao frontmatter dos dois
orquestradores sao, exatamente:

```
mcp__cstk-state__open_wave, mcp__cstk-state__record_decision,
mcp__cstk-state__record_skill, mcp__cstk-state__record_task,
mcp__cstk-state__register_human_block, mcp__cstk-state__close_wave,
mcp__cstk-state__get_status
```

**Rationale** (composicao `mcp__<server-key>__<tool-name>`):

- **server-key = `cstk-state`**: e a chave sob `mcpServers` no `.mcp.json`
  do projeto [FONTE: .mcp.json:3 — `"cstk-state": { "type": "stdio", ... }`],
  registrada por `cli/lib/mcp.sh` [FONTE: cli/lib/mcp.sh:46 — "`mcpServers.cstk-state`
  no `.mcp.json` do projeto-alvo"].
- **tool-names**: os 7 nomes vem do registro central do servidor
  [FONTE: mcp/state-server/src/index.ts:153 `"record_skill"`, :169
  `"record_decision"`, :185 `"open_wave"`, :201 `"record_task"`, :217
  `"register_human_block"`, :236 `"get_status"`, :252 `"close_wave"`], e
  cada um tem arquivo proprio em `mcp/state-server/src/tools/`
  [FONTE: `ls mcp/state-server/src/tools/` — close_wave.ts, get_status.ts,
  open_wave.ts, record_decision.ts, record_skill.ts, record_task.ts,
  register_human_block.ts].
- **A forma composta ja e afirmada pelo repo**: os commands que spawnam os
  orquestradores ja instruem "Prefira as tools mcp__cstk-state__*
  (open_wave, record_decision, record_skill, record_task,
  register_human_block, close_wave, get_status)"
  [FONTE: plugins/cstk/commands/feature-00c.md:734-736 e
  plugins/cstk/commands/agente-00c.md:493-495]. Ou seja: o prompt de spawn
  ja manda usar tools que a allowlist nunca expos — a lacuna exata que
  FR-003 fecha.

**Alternatives considered**:

- *Adicionar so um subconjunto (ex: sem `get_status`)*: rejeitado — FR-003
  e SC-002 exigem as sete [FONTE: spec.md:305-309]; e FR-009 ja
  estabeleceu que nao ha pressao de teto para 7.

---

## Decision 6 — Onde vive o guard novo, e o custo de superficie no harness

**Decision**: criar **um** arquivo de teste novo,
`tests/test_orchestrator-allowlist-guard.sh`, hospedando o guard de FR-002,
os asserts de FR-003/FR-004 e o teste de paridade de FR-011; e adicionar
uma entrada correspondente em `_is_internal_test` de `tests/run.sh`.
[PROPOSTA — a validar na implementacao]

**Rationale**:

1. **Nenhum `.sh` novo de produto e criado.** A feature edita 2 arquivos
   markdown de agente e mexe em testes — nao adiciona script em
   `plugins/cstk/skills/*/scripts/` nem em `cli/lib/`. Logo a regra de
   cobertura 1:1 ("todo `.sh` novo exige `test_<nome>.sh`") **nao** e
   acionada do lado dos scripts.

2. **Mas ha um custo de superficie no outro lado do orphan-check**, e ele e
   facil de esquecer: `_compute_orphans` tambem lista **tests sem script
   correspondente** e falha o `--check-coverage` com exit 1
   [FONTE: tests/run.sh:612-624 — laco "Tests sem script"; e
   tests/run.sh:72 — "1  Pelo menos um FAIL ou ERROR (ou --check-coverage
   detectou orfao)"]. Um arquivo `tests/test_orchestrator-allowlist-guard.sh`
   nao casa nenhum script em `/scripts/` ou `/cli/lib/`, entao **sera
   flagado como orfao** a menos que ganhe um ramo em `_is_internal_test`
   [FONTE: tests/run.sh:190 e o laco em :616-618 que pula os internos].

   O padrao a seguir e o "existence-guarded", ja usado por varios ramos
   equivalentes que asseguram prosa de agente — por exemplo
   `test_orchestrator-turn-completion.sh` e
   `test_converge-orchestrator-gate.sh`, ambos condicionados a
   `[ -f "$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md" ]`
   [FONTE: tests/run.sh, corpo de `_is_internal_test`]. A entrada nova deve
   ser guardada pela existencia do diretorio `plugins/cstk/agents` ou de um
   dos orquestradores, para voltar a ser orfao real se a fonte sumir.

3. **Custo de documentacao: zero.** `test_doc-counts.sh` guarda contagem de
   skills e referencias no README, e declara explicitamente que **nao**
   guarda a contagem de scenarios da suite
   [FONTE: tests/test_doc-counts.sh:9 — "Por que NAO guardamos a contagem
   de scenarios da suite"]. Adicionar scenarios nao bumpa numero em doc.

4. **Descoberta de scenarios e automatica**: o arquivo de teste termina com
   `run_all_scenarios "$0"` [FONTE: tests/test_orchestrator-mcp-fallback.sh:245],
   entao funcoes `scenario_*` novas sao coletadas sem registro manual.

**Alternatives considered**:

- *Estender `tests/test_orchestrator-mcp-fallback.sh` com os scenarios
  novos* (zero arquivos novos, zero edicao em `run.sh`): rejeitado por
  clareza de propriedade. Aquele arquivo passa a ter uma unica
  responsabilidade coerente apos a revogacao — provar que uma execucao
  headless completa via Bash puro com `cstk mcp start` falhando
  [FONTE: tests/run.sh, ramo `test_orchestrator-mcp-fallback.sh` de
  `_is_internal_test`, que descreve o teste como "hibrido textual+funcional
  ... e que uma execucao headless/cron completa via Bash puro"]. Misturar
  ali um guard de composicao de allowlist mantem o arquivo com duas
  finalidades e dificulta a leitura do que foi revogado. O custo evitado
  (1 ramo em `_is_internal_test`) e baixo e o padrao e trilhado.
- *Dois arquivos separados (guard + paridade)*: rejeitado — dobraria o
  custo de `_is_internal_test` sem ganho; ambos operam sobre os mesmos
  arquivos-alvo descobertos pelo mesmo glob.

---

## Decision 7 — Delimitacao e paridade do bloco de orientacao (FR-005/FR-006/FR-011)

**Decision**: a secao de orientacao MCP-vs-Bash e delimitada em cada
orquestrador por marcadores de comentario HTML estaveis
(`<!-- MCP-VS-BASH:BEGIN -->` / `<!-- MCP-VS-BASH:END -->`), e o conteudo
entre eles MUST ser **byte-identico** nos dois arquivos, verificado por
`diff` no teste de paridade. Consequencia de desenho: o bloco NAO pode
conter nenhuma referencia especifica a um dos dois orquestradores (nome do
agente, layout de state-dir, nome do command pai) — deve falar de "este
orquestrador" e de `$AGENTE_00C_STATE_DIR`.
[PROPOSTA — a validar na implementacao]

**Rationale**:

- A duplicacao e deliberada e ja decidida (dec-017): secao autocontida em
  cada arquivo, nunca ponteiro para doc externo, porque o agente le a
  propria definicao no spawn e um ponteiro custaria um Read adicional que
  pode ser ignorado em runtime [FONTE: spec.md:177-185].
- O mitigante exigido pela propria clarificacao e "um teste de paridade
  entre os dois blocos" [FONTE: spec.md:184-185, e FR-011 em spec.md:280-284].
- Marcadores explicitos batem delimitacao por heading: headings sao
  reescritos com frequencia na prosa dos orquestradores, e um teste que
  depende do texto do heading quebra por motivo errado. Comentario HTML e
  invisivel na renderizacao e estavel.
- Byte-identidade torna o teste trivial e deterministico (`diff` dos dois
  extratos), sem heuristica de normalizacao — que e onde testes de paridade
  costumam apodrecer.

**Alternatives considered**:

- *Comparar por heading `## ...` ate o proximo `## `*: rejeitado — acopla o
  teste ao texto do heading.
- *Permitir divergencia controlada (ex: normalizar nomes de agente antes de
  comparar)*: rejeitado — abriria a porta para divergencia semantica
  silenciosa, exatamente o que FR-011 existe para impedir. E mais simples
  proibir referencia especifica dentro do bloco.

---

## Decision 8 — Semantica de fallback: 0 retries, herdada do contrato vigente

**Decision**: a orientacao prescreve fallback imediato para Bash, sem
retry, em **todos** os modos de indisponibilidade — inclusive erro pontual
de uma chamada com o servidor ativo (dec-018).

**Rationale**: nao e preferencia nova; e o contrato ja documentado e
vigente no repo, com texto identico nos dois commands de spawn:

> "em erro de transporte, contrato de queda mid-onda (0 retries + 1
> confirmacao via cstk mcp status --live) e comutacao para Bash no resto da
> onda."
> [FONTE: plugins/cstk/commands/feature-00c.md:737-739 e
> plugins/cstk/commands/agente-00c.md:496-498 — texto literal identico nos
> dois arquivos]

Os mesmos commands ja definem o caso "sem token": "`_mcp_token` vazio
(`bash-fallback` / sem descritor) ⇒ NAO mencione MCP no prompt; o
orquestrador segue o caminho Bash (zero regressao, SC-004)"
[FONTE: plugins/cstk/commands/feature-00c.md:740-741 e
plugins/cstk/commands/agente-00c.md:499-500]. A secao de orientacao replica
essa semantica do lado do agente, fechando o circuito: hoje o command manda
preferir tools que o agente nao enxerga.

**Alternatives considered**:

- *Retry com backoff*: rejeitado por dec-018 — exigiria emendar os dois
  commands e contradiria o contrato ja documentado [FONTE: spec.md:186-197].

---

## Decision 9 — FR-010 (elicitation) fica fora do escopo de implementacao

**Decision**: nenhum comportamento e desenhado para `elicitation/create`
nesta rodada. O plano registra FR-010 como Deferred e a secao de orientacao
declara explicitamente que os orquestradores autonomos NAO devem invocar
operacoes que dependam de elicitation enquanto a fonte estiver pendente.

**Rationale**: a propria spec o marca "**Deferred — fonte pendente**",
determina que ele "NAO MUST bloquear as demais FRs desta feature", e proibe
supor comportamento sem a medicao (Principio VI)
[FONTE: spec.md:266-279]. A medicao esta em curso fora do escopo desta
execucao [FONTE: spec.md:271-273].

Nota factual do que ja se sabe, sem extrapolar: nenhuma das 7 tools do
`cstk-state` usa elicitation — o schema de entrada de `open_wave`, por
exemplo, e apenas `{ session_id: string }`
[FONTE: mcp/state-server/src/tools/open_wave.ts:31-33]. As tools de
elicitation observadas na sondagem (`ask_tier`, `ask_rich`) pertencem ao
servidor de sonda descartavel `probe`, nao ao `cstk-state`
[SONDAGEM: fase0/B-probeB-accepts.log — `tools/list` do servidor `probe`
responde `ping`, `ask_tier`, `ask_rich`]. Portanto FR-010 nao bloqueia
FR-003: as 7 tools que entram na allowlist nao dependem de elicitation.

**Alternatives considered**:

- *Remover FR-010 da spec*: rejeitado — a instrucao desta onda e explicita
  em nao remove-lo.
- *Desenhar um timeout provisorio*: rejeitado — seria suposicao sem fonte,
  violando Principio VI [FONTE: docs/constitution.md:235 — "VI. Veracidade
  de Dados — Zero Fabricacao (NON-NEGOTIABLE)"].

---

## Decision 10 — Validacao de sessao (FR-008/SC-004) e manual, nao automatizavel na suite

**Decision**: FR-008 e validado por um cenario manual documentado em
`quickstart.md`, executado uma vez com o servidor MCP ativo, e NAO por um
scenario de `tests/run.sh`.

**Rationale**:

- FR-008 exige "pelo menos uma chamada real originada de um subagente
  orquestrador" [FONTE: spec.md:253-256]. "Originada de um subagente" implica
  um spawn real do harness — a suite POSIX nao spawna subagentes.
- O caminho depende de Docker: o servidor roda em container dedicado por
  execucao, e quando Docker esta indisponivel o modo vira `bash-fallback`
  [FONTE: CLAUDE.md §"Servidor MCP de estado (`cstk mcp`)"]. Um scenario de
  suite que dependesse disso seria flaky por ambiente.
- O mecanismo de rejeicao ja existe e ja tem cobertura automatizada
  propria (`SESSION_MISMATCH`, fail-closed, sem fallback para "a execucao
  ativa mais provavel") [FONTE: CLAUDE.md §"Servidor MCP de estado", e
  `mcp/state-server/src/session/resolve.ts` referenciado por
  mcp/state-server/src/tools/open_wave.ts:20-23]. FR-008 nao pede novo
  mecanismo: pede a **primeira validacao pelo caminho real**, que e por
  natureza um exercicio manual pontual.

**Alternatives considered**:

- *Marcar FR-008 como scenario da suite*: rejeitado — introduziria
  dependencia de Docker no gate de release, contrariando a disciplina de
  degradacao graciosa do repo.
