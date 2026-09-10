# Spikes da human-bridge — por que URL mode foi descartado

**TL;DR**: o desenho original da human-bridge era ancorado em `elicitation/create`
com `mode:"url"` — o servidor mandaria o operador ao painel e fecharia com
`notifications/elicitation/complete`. **Isso nao funciona**: o cliente Claude Code
nao anuncia a capability `url`. Medido em 2026-08-27 contra claude-code **2.1.247**
com `@modelcontextprotocol/sdk` **1.30.0**. Se alguem propuser URL mode de novo,
leia este arquivo antes — o codigo de url mode EXISTE no cliente, o que torna a
proposta plausivel a leitura e falsa na pratica.

## O que foi medido

### 1. URL mode: capability ausente, chamada morre no servidor

Capabilities reais do cliente, lidas com `getClientCapabilities()` de dentro de um
servidor MCP stdio real (`server-form-caps.mjs`):

```json
{"elicitation":{"form":{}},"roots":{"listChanged":true}}
```

So `form`. Nao ha sub-capability `url`. O proprio SDK gateia nisso — literal em
`@modelcontextprotocol/sdk/dist/esm/server/index.js:340-345`:

```js
async elicitInput(params, options) {
    const mode = (params.mode ?? 'form');
    switch (mode) {
        case 'url': {
            if (!this._clientCapabilities?.elicitation?.url) {
                throw new Error('Client does not support url elicitation.');
```

Resultado de `server-url-mode.mjs`, que emite `mode:"url"`:

```
SPIKE_RESULT={"kind":"throw","name":"Error","code":null,
              "message":"Client does not support url elicitation."}
```

A chamada **nao chega a virar trafego de protocolo** — morre no servidor.
Consequencia: `notifications/elicitation/complete` e o correlator `elicitationId`
sao inalcancaveis por esse caminho.

> **A armadilha que custou uma rodada**: o binario do cliente **contem** o handler
> de url mode (discriminador `mode==="url"`, `waitingState:{actionLabel:"Skip
> confirmation"}`, handler de `notifications/elicitation/complete`, log
> `Ignoring completion notification for unknown elicitation:`). Ler essas strings
> e concluir "o cliente suporta" foi **erro de metodo**: presenca de codigo nao e
> capability negociada. Infraestrutura presente e desligada continua desligada.

### 2. Hooks `Elicitation` / `ElicitationResult` existem e funcionam

Sao a via viva para resolver uma elicitation **fora da TUI**. Em `claude -p`
(headless, que sozinho responde `cancel` na hora) o hook resolveu sem UI nenhuma:

```
SPIKE_RESULT={"kind":"envelope","action":"accept","content":{"answer":"RESPOSTA-DO-HOOK"}}
```

- **Registro** (`.claude/settings.json`): `{"hooks":{"Elicitation":[{"matcher":
  "<nome-do-servidor-mcp>","hooks":[{"type":"command","command":"<script>"}]}]}}`.
  O `matcher` casa o **nome do servidor MCP**, nao a tool.
- **Entrada** (stdin JSON): ver `hook-input.sample.json` — chaves reais capturadas.
  Em form mode, `url` e `elicitation_id` sao **omitidos**; nao ha id de elicitation
  de graca.
- **Saida**: `{"hookSpecificOutput":{"hookEventName":"Elicitation","action":
  "accept","content":{...}}}`. O parser ignora em silencio se o stdout nao comeca
  com `{`, se `hookEventName` diverge, ou se falta `action`; `action:"decline"` e
  `decision:"block"` viram erro bloqueante.

Este caminho e a **superficie 3** da human-bridge (elicitations levantadas por
outros servidores MCP). Nao e a fundacao — ver o contrato da superficie 1 em
[`../contracts/mcp-tool-ask-operator.md`](../contracts/mcp-tool-ask-operator.md).

### 3. Relogios de uma tool bloqueante comum (`server-blocking.mjs`)

Uma tool que simplesmente **nao retorna** nao precisa de elicitation nem de hook.
Dois relogios do cliente, com mensagens **distinguiveis**:

| Relogio | Mensagem literal | Comportamento |
|---------|------------------|---------------|
| Teto total | `MCP server "spike-block" tool "spike_block" timed out after 8s` | timer real, dispara cravado no valor de `"timeout"` do `.mcp.json` |
| Ociosidade | `... sent no response or progress for 30s; aborting. If this server is configured in your MCP settings, set a per-server "timeout" (ms) to allow longer silent runs for just this server; otherwise set CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT (ms) globally (0 disables).` | granularidade de ~30s |

Medicoes:

| # | Setup | Resultado |
|---|-------|-----------|
| M1 | `"timeout":8000`, tool dorme 30s | abortou em **8s**, mensagem `timed out after 8s` |
| M2 | `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT=10000`, tool dorme 90s | abortou aos **30s**, mensagem reportando **30s** (nao 10s) |
| M3 | sem env var, tool dorme 30s | **completou** (`SPIKE_BLOCK_DONE after=30004ms`) |
| M4 | `"timeout":60000` + `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT=10000` (hostil), tool dorme 45s | **completou** — o `timeout` por servidor levanta OS DOIS relogios |
| M5 | sem env var e sem `timeout`, tool dorme 31,7 min | abortou aos **1815s** (`for 1815s; aborting`); wall-clock da sessao 1824s |

Conclusoes que viraram requisito no contrato:

1. **Por default quem governa e a ociosidade** (M5 confirma 1800000 ms para stdio);
   o teto total default e efetivamente sem teto e nunca morde.
2. **O watchdog tem overshoot de ate ~30s** (M2 e M5: 30s quando configurado 10s;
   1815s quando o teto e 1800s) e a mensagem imprime o silencio **decorrido**, nao
   o valor configurado. Daqui sai a folga minima de 60000 ms da R-CLOCK-2.
3. **O botao certo e o `timeout` por servidor no `.mcp.json`** (M4), nunca a env
   var global.

### 4. Relogio do servidor vence hook lento

Servidor com `{timeout:20000}` (via `RequestOptions.timeout` do SDK) e hook dormindo
25s: `MCP error -32001: Request timed out`, wall-clock 33s. Confirma que a
discriminacao contratual sobrevive — envelope retornado => `absent`; excecao
`-32001` => `timeout` — e que o teto do hook precisa ser menor que o do servidor.

## Como reproduzir

Estes arquivos sao **descartaveis** e nao fazem parte do toolkit: nao sao
empacotados, nao tem teste, nao entram no `--check-coverage`. Para rodar, e preciso
um `node_modules` com `@modelcontextprotocol/sdk` (o de `mcp/state-server/` serve):

```sh
SPIKE=$(mktemp -d)
cp docs/specs/human-bridge/spikes/*.mjs "$SPIKE/"
ln -s "$PWD/mcp/state-server/node_modules" "$SPIKE/node_modules"

cat > "$SPIKE/mcp.json" <<JSON
{"mcpServers":{"spike-block":{"type":"stdio","command":"node",
 "args":["$SPIKE/server-blocking.mjs"]}}}
JSON

mkdir -p "$SPIKE/proj" && cd "$SPIKE/proj"
claude -p 'Chame spike_block com sleep_ms=30000 uma unica vez.' \
  --mcp-config "$SPIKE/mcp.json" --strict-mcp-config \
  --allowedTools 'mcp__spike-block__spike_block'
```

Acrescente `"timeout": <ms>` na entrada do servidor para exercitar o teto total, e
prefixe `CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT=<ms>` para exercitar a ociosidade.

> Nota de ambiente: `timeout(1)` do GNU nao existe no macOS — use o timeout da
> ferramenta que invoca, nao um wrapper de shell.
