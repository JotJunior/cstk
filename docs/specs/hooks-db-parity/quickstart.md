# Quickstart: validacao da paridade backend-agnostica dos hooks 00C

**Feature**: `hooks-db-parity`
**Fase**: 1 (Design)
**Data**: 2026-08-03

Cenarios de validacao end-to-end. Cada um mapeia para requisitos da spec e
tem contrapartida automatizada em `tests/`. Os comandos assumem `sqlite3`,
`jq` e `perl` disponiveis; onde a ausencia da ferramenta e **o proprio
cenario**, isso esta explicito.

Convencoes usadas abaixo:

```sh
H=global/skills/agente-00c-runtime/hooks
SB=$(mktemp -d)                       # sandbox = "cwd" fornecido ao hook
```

---

## Cenario 0 — Reproduzir o bug (baseline, antes da correcao)

1. Criar sandbox com **uma** execucao `feature-00c` ativa sob backend
   SQLite e nenhum `state.json`:
   ```sh
   mkdir -p "$SB/.claude/feature-00c-state/demo"
   cp <state-dir-sqlite-real>/state.db "$SB/.claude/feature-00c-state/demo/state.db"
   sqlite3 "$SB/.claude/feature-00c-state/demo/state.db" \
     "SELECT status FROM execution LIMIT 1;"     # => em_andamento
   ```
2. Disparar o hook de ticks:
   ```sh
   printf '{"cwd":"%s","tool_name":"Read"}' "$SB" | sh "$H/posttooluse-tool-call-tick.sh"
   ```
3. Disparar o hook de guarda com um comando qualquer:
   ```sh
   printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls -la"}}' "$SB" \
     | sh "$H/pretooluse-bash-guard.sh"
   ```

**Expected (comportamento ATUAL, verificado empiricamente nesta maquina)**:
nenhum `tool-call-ticks.log` e criado; nenhum
`$SB/.claude/enforcement-log.jsonl` e criado; ambos os hooks saem `0` com
stdout vazio. A execucao ativa **nao** foi detectada — esta e a regressao
que a feature corrige (US1, US2).

**Expected (apos a correcao)**: ver Cenarios 1-3.

---

## Cenario 1 — Guarda bloqueia sob backend SQLite (US1, FR-001, SC-001)

1. Sandbox com execucao `feature-00c` ativa sob `state.db` (Cenario 0 passo 1).
2. Submeter um comando **sabidamente bloqueado** pela blocklist vigente:
   ```sh
   printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"sudo rm -rf /"}}' "$SB" \
     | sh "$H/pretooluse-bash-guard.sh"
   ```

**Expected**: stdout contem
`"permissionDecision":"deny"` com `permissionDecisionReason` prefixado por
`REGRA_VIOLADA:`; exit code `0`; uma linha
`"outcome":"blocked-by-rule"` em `$SB/.claude/enforcement-log.jsonl` com
`"detected_execution":"feature-00c"`. A categoria de bloqueio **MUST** ser
identica a produzida pelo mesmo comando num sandbox equivalente com
`state.json` (comparacao direta = o teste de paridade).

---

## Cenario 2 — Comando permitido segue permitido (US1 cenario 2, FR-001)

1. Mesmo sandbox do Cenario 1.
2. Submeter comando dentro da whitelist / nao bloqueado:
   ```sh
   printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls -la"}}' "$SB" \
     | sh "$H/pretooluse-bash-guard.sh"
   ```

**Expected**: stdout **vazio** (nenhum `deny`); exit `0`; uma linha
`"outcome":"allowed"` no `enforcement-log.jsonl`.

---

## Cenario 3 — Ticks e uso de agente gravados sob SQLite (US2, US3, SC-002)

1. Mesmo sandbox.
2. Disparar 5 vezes o hook de ticks:
   ```sh
   i=0; while [ $i -lt 5 ]; do
     printf '{"cwd":"%s","tool_name":"Read"}' "$SB" | sh "$H/posttooluse-tool-call-tick.sh"
     i=$((i+1))
   done
   wc -l < "$SB/.claude/feature-00c-state/demo/tool-call-ticks.log"
   ```
3. Disparar o hook de uso de agente com um `tool_response` completo:
   ```sh
   printf '{"cwd":"%s","tool_name":"Agent","tool_input":{"subagent_type":"Explore"},"tool_response":{"agentId":"a1","status":"completed","totalTokens":1234,"totalToolUseCount":7,"totalDurationMs":4200,"resolvedModel":"sonnet","usage":{"input_tokens":1000,"output_tokens":234}}}' "$SB" \
     | sh "$H/posttooluse-agent-usage.sh"
   wc -l < "$SB/.claude/feature-00c-state/demo/wave-agent-usage.jsonl"
   ```

**Expected**: passo 2 imprime `5`; passo 3 imprime `1`, e a linha e um JSON
valido com `"agent_id":"a1"`, `"status":"completo"`, `"total_tokens":1234`,
`"source":"live"`. Permissao do `wave-agent-usage.jsonl` = `600`. stdout dos
hooks: vazio nas duas etapas.

---

## Cenario 4 — Precedencia determinista atraves dos dois backends (FR-002)

1. Sandbox com **tres** state-dirs simultaneamente ativos:
   - `.claude/agente-00c-state/state.json` com `status: em_andamento`
   - `.claude/feature-00c-state/aaa/state.db` com `status = em_andamento`
   - `.claude/feature-00c-state/bbb/state.json` com `status: em_andamento`
2. Disparar o hook de ticks e inspecionar onde o sidecar foi criado.

**Expected**: o tick e gravado em
`.claude/agente-00c-state/tool-call-ticks.log` — `agente-00c` vence sobre
qualquer `feature-00c`, independentemente do backend.

3. Remover o `agente-00c-state` e repetir.

**Expected**: o tick vai para `.claude/feature-00c-state/aaa/` — menor
short-name em ordem byte-wise (`LC_ALL=C`), mesmo estando sob backend
SQLite enquanto o concorrente esta sob JSON (caso de backend misto,
best-effort per Clarifications).

---

## Cenario 5 — Fail-closed do guard sem `sqlite3` (US1 cenario 3, FR-003)

1. Sandbox com execucao ativa sob `state.db`.
2. Invocar o hook com um `PATH` que **nao** contenha `sqlite3`, preservando
   as demais ferramentas (`jq`, coreutils):
   ```sh
   # PATH sintetico contendo symlinks para tudo EXCETO sqlite3
   printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"ls"}}' "$SB" \
     | PATH="$FAKE_BIN" sh "$H/pretooluse-bash-guard.sh"
   ```

**Expected**: stdout contem `"permissionDecision":"deny"` com prefixo
`MECANISMO_FALHOU:`; exit `0`. **Nunca** stdout vazio (que significaria
"comando liberado").

> Armadilha conhecida do repositorio (registrada em memoria de projeto): um
> `PATH` stub nao esconde binarios que o SUT resolve por caminho absoluto, e
> esvaziar o `PATH` quebra `dirname`/`basename` do proprio script. O teste
> automatizado MUST montar um `PATH` completo **menos** `sqlite3` (diretorio
> de symlinks), nao um `PATH` minimo.

---

## Cenario 6 — Fail-open das metricas sem `sqlite3` (FR-004)

1. Mesmo sandbox e mesmo `PATH` sem `sqlite3` do Cenario 5.
2. Disparar os dois hooks de metrica capturando stdout **e** stderr
   separadamente.

**Expected**: exit `0`; stdout vazio; **stderr vazio**; nenhum sidecar
criado. A subcontagem e silenciosa por contrato — o operador nunca ve
mensagem.

---

## Cenario 7 — Gate automatizado de latencia (FR-005, SC-003)

1. Sandbox com **exatamente um** state-dir SQLite ativo (isola o custo da
   deteccao SQLite do custo O(N) de varrer dirs JSON).
2. Descartar 3 invocacoes de warm-up.
3. Medir 20 invocacoes reais do hook, coletando o tempo de cada uma via
   `perl -MTime::HiRes=time`, e tomar a **mediana**.

**Expected**:

| Hook | Mediana medida (referencia desta maquina) | Teto do gate |
|------|-------------------------------------------|--------------|
| `posttooluse-tool-call-tick.sh` | 12.36 ms | **150 ms** |
| `posttooluse-agent-usage.sh` | mesma ordem do tick | **150 ms** |
| `pretooluse-bash-guard.sh` | 17.36 ms | **400 ms** |

O cenario **falha o build** se a mediana exceder o **teto do gate** (150 ms /
400 ms) — esse teto, e SOMENTE ele, e o criterio de pass/fail (FR-005/SC-003,
CHK012/task 1.5). A coluna "Mediana medida" acima e o **orcamento de
projeto** (~30 ms/~177 ms referenciado em SC-003) — uma referencia de
desenho, NAO um segundo criterio de aceite: um build com mediana de, por
exemplo, 80ms passa o gate (< 150ms) mesmo excedendo o orcamento de projeto
de ~30ms, porque o orcamento e informativo e o teto do gate e o unico
verificavel. Se `sqlite3` ou `perl` estiverem ausentes, o cenario faz
**skip** (nunca fail) — e um gate de performance, nao de disponibilidade de
ferramenta.

### Cenario 7b — Estouro do auto-teto interno de deteccao (FR-003, SEC-H2)

Cobre a quarta classe de falha de mecanismo adicionada a FR-003 (task 1.2 /
CHK006) — distinta do caminho feliz acima, que mede latencia DENTRO do
orcamento.

1. Sandbox com um state-dir SQLite artificialmente lento o bastante para
   estourar o auto-teto interno do helper (ex: `state.db` com lock mantido
   por um processo auxiliar alem do `busy_timeout`, ou um stub de
   `sqlite3`/`jq` que dorme alem do auto-teto — a implementacao concreta do
   auto-teto e definida na FASE 2/3; este cenario e o contrato de aceite que
   ela precisa satisfazer).
2. Disparar `pretooluse-bash-guard.sh`.

**Expected**: o hook emite `MECANISMO_FALHOU` (`deny`), nunca stdout vazio
nem `allow` — o estouro do auto-teto e tratado como falha de mecanismo
(FR-003), igual a dependencia ausente/arquivo corrompido/erro de leitura.
Este e o caminho que prova que o auto-teto funciona como defesa em
profundidade mesmo apos a confirmacao (research.md §"Resultado Fase 0") de
que o timeout do harness ja e fail-closed por si so.

---

## Cenario 8 — Ausencia total de state e fora de escopo (FR-007, FR-006, SC-004)

1. Sandbox **limpo**, sem `.claude/` algum.
2. Disparar os tres hooks.

**Expected**: exit `0` nos tres; stdout e stderr vazios; nenhum arquivo
criado em lugar nenhum (`find "$SB" -type f` retorna vazio). Em particular,
o guard **nao** emite `MECANISMO_FALHOU` — ausencia de state e "fora de
escopo", nao "falha de mecanismo".

3. Repetir com `.claude/feature-00c-state/x/` existente porem **vazio**
   (sem `state.json` e sem `state.db`).

**Expected**: identico ao passo 2.

---

## Cenario 9 — `state.db` corrompido (FR-003, FR-004, FR-007)

1. Sandbox com `.claude/feature-00c-state/demo/state.db` contendo lixo:
   ```sh
   printf 'not a database' > "$SB/.claude/feature-00c-state/demo/state.db"
   ```
2. Disparar o guard e os dois hooks de metrica.

**Expected**: guard emite `MECANISMO_FALHOU` (`deny`); hooks de metrica
saem `0` com stdout **e** stderr vazios e sem criar sidecar. E a distincao
exigida por FR-007: `state.db` presente porem ilegivel **nao** e tratado
como "sem execucao".

---

## Cenario 10 — Execucao terminal nao ativa nada (SC-004)

1. Sandbox com `state.db` cujo `status` seja `concluida`:
   ```sh
   sqlite3 "$SB/.claude/feature-00c-state/demo/state.db" \
     "SELECT status FROM execution LIMIT 1;"     # => concluida
   ```
2. Disparar os tres hooks.

**Expected**: comportamento identico ao Cenario 8 — fora de escopo, zero
efeito. Status `abortada` e equivalente.

---

## Cenario 11 — Varredura estatica de paridade cobre os hooks (Decision 6)

1. Rodar a suite de paridade:
   ```sh
   ./tests/run.sh state-parity-sweep
   ```
2. Introduzir deliberadamente, num hook, uma construcao de path
   `"$dir/state.json"` fora da allowlist e rodar de novo.

**Expected**: passo 1 verde; passo 2 **falha** com diagnostico apontando o
arquivo e a linha. Hoje o passo 2 passaria despercebido — o diretorio
`hooks/` esta fora do alcance da varredura, que e exatamente a razao pela
qual esta regressao chegou a producao.

---

## Cenario 12 — Roundtrip do orcamento de onda sob SQLite (SC-002)

1. Numa execucao real com backend SQLite, abrir uma onda
   (`state-ondas.sh start`).
2. Executar N tool calls.
3. Fechar a onda (`state-ondas.sh end`) e ler o contador de tool calls
   agregado no estado.

**Expected**: o contador reflete N, com tolerancia maxima de **2 ticks
perdidos por onda** (no maximo 1 na abertura, no maximo 1 no fechamento —
quantificado em `spec.md` SC-002/task 1.7, a partir da janela de corrida real
entre o reset/agregacao do sidecar em `state-ondas.sh start`/`end` e um
`append` concorrente do hook). Perda acima de 2 ticks, ou fora dessas duas
bordas, e regressao — mesma margem ja aceita sob backend JSON. Hoje esse
valor e invariavelmente `0` sob SQLite.

> Este e o unico cenario que exige execucao autonoma real; os demais rodam
> com sandboxes sinteticos. Ele valida a integracao ponta a ponta
> hook -> sidecar -> `state-ondas.sh end` -> `budget.sh`.

---

## Mapa cenario x requisito

| Cenario | Requisitos cobertos |
|---------|---------------------|
| 0 | baseline do bug (US1, US2, US3) |
| 1, 2 | FR-001, SC-001 |
| 3 | FR-001, SC-002 |
| 4 | FR-002 |
| 5 | FR-003 |
| 6 | FR-004 |
| 7 | FR-005, SC-003 |
| 7b | FR-003 (estouro do auto-teto interno) |
| 8, 10 | FR-006, FR-007, SC-004 |
| 9 | FR-003, FR-004, FR-007 |
| 11 | prevencao de regressao (research Decision 6) |
| 12 | SC-002 |
