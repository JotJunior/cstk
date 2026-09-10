# Contract: `state-rounds.sh`

**Status**: `[PROPOSTA — a validar na implementacao]` — script **novo**. Nada
neste arquivo descreve comportamento existente; e o desenho da interface a ser
construida.

**Path**: `plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh`
**Teste obrigatorio**: `tests/test_state-rounds.sh` (senao
`./tests/run.sh --check-coverage` falha com exit 1)

Primitiva POSIX de rotacao de estado terminal para round preservado. Nao decide
nada: recebe ordem, executa de forma recuperavel e reporta. Toda politica
(triagem, confirmacao humana) vive na camada acima.

## Conformidade obrigatoria (Constitution Principio II, NON-NEGOTIABLE)

- `#!/bin/sh` + `set -eu`; sem arrays, `[[ ]]`, `$'...'`, `<<<`, `local`,
  `function`.
- Sem GNU-only: nada de `sed -i` sem sufixo, `stat` no dialeto GNU, `readlink -f`.
  Alvo real: macOS/zsh (dev) **e** Ubuntu (CI).
- Erros em stderr, dados em stdout.
- `sqlite3` e `jq` sao permitidos aqui como **dependencia obrigatoria**: este
  script pertence a camada de estado transacional, coberta pelo carve-out do
  amendment 1.3.0 do Principio II.

## Exit codes (uniformes em todos os subcomandos)

| Code | Significado |
|------|-------------|
| `0` | sucesso |
| `1` | erro generico (FS, sqlite, integridade) |
| `2` | uso incorreto (flag/subcomando invalido, obrigatorio ausente) |
| `3` | pre-condicao nao satisfeita (sem estado a rotacionar; rotacao pendente detectada) |

Alinhado a convencao do runtime: `state-rw.sh` usa `0/1/2` e `state-lock.sh`
acrescenta `3` para pre-condicao.

---

## `state-rounds.sh next-label --state-dir DIR`

Calcula o proximo label sem escrever nada.

### Request

| Flag | Type | Required | Validation |
|------|------|----------|------------|
| `--state-dir` | path | sim | diretorio existente |

### Response (stdout)

Uma linha: o label (`r01` se `rounds/` ausente ou vazio; senao sucessor do maior
label presente, zero-padded em 2 digitos).

### Errors

| Exit | Condicao |
|------|----------|
| `2` | `--state-dir` ausente ou flag desconhecida |
| `1` | `rounds/` ilegivel |

---

## `state-rounds.sh rotate --state-dir DIR [--label LABEL] [--dry-run]`

Move o estado transacional terminal para `rounds/<label>/`. **Idempotencia**: se
houver journal pendente, recusa com exit `3` e instrui `recover` — nunca inicia
uma segunda rotacao sobre uma inacabada.

### Pre-condicoes verificadas (todas antes de qualquer escrita)

1. Existe `state.json` **ou** `state.db` na raiz do state-dir — senao exit `3`.
2. Nao existe `rounds/.rotate-journal` — senao exit `3` (rotacao pendente).
3. O estado esta em status terminal. Verificacao delegada, nao reimplementada:
   `state-lock.sh check-execution-busy --state-dir DIR` — exit `0` para
   `''`/`abortada`/`concluida`; exit `3` para `em_andamento`/`aguardando_humano`.
   O contrato do `rotate` propaga esse `3`.
4. Sob backend `sqlite`: `PRAGMA integrity_check;` retorna exatamente `ok`
   (mesmo criterio de `_state-rw-db.sh:209`) — senao exit `1`, nada movido.

### Sequencia (Decision 1 + Decision 2)

```
a. label  = --label ou next-label
b. backend = sqlite se existe state.db, senao json      (regra de _sr_backend)
b1. ASSERT lock detido: .lock/ existe e .lock/owner casa      -> senao exit 3
b2. ASSERT nao-symlink: state-dir, rounds/, staging, alvo, backups/ (G8)
                                                                -> senao exit 1
b3. elegibilidade de backups/: existe && nao-symlink && nao-vazio
    => anexa `backups` ao FIM do CSV `files` (itens transacionais primeiro)
c. sqlite: PRAGMA wal_checkpoint(TRUNCATE);
   -> exigir coluna 1 (busy) == 0; NUNCA `|| :`                -> senao exit 1
c1. ASSERT state.db-wal ausente ou 0 bytes                     -> senao exit 1
d. escreve rounds/.rotate-journal (phase=staged)   # `files` ja inclui backups
e. mkdir rounds/.<label>.staging   (chmod 700 best-effort)
f. mv -- de cada item de `files` -> staging   (phase=moving)
   `backups` e movido como diretorio, no MESMO staging; re-assere
   `[ ! -L ]` imediatamente antes do mv (G8, fecha janela TOCTOU) e
   `[ -d ] && [ ! -L ]` no staging apos o mv
g. sqlite: remove state.db-wal / state.db-shm residuais (se existirem)
g1. G9: chmod 700 best-effort sobre backups/ no staging, antes do commit
h. re-ASSERT nao-symlink do alvo, imediatamente antes do commit
h1. COMMIT: mv -- rounds/.<label>.staging -> rounds/<label>    [atomico]
    (o commit unico publica estado + snapshots juntos — nao ha segundo
    ponto de commit: FR-001/FR-008)
i. sqlite: PRAGMA integrity_check na copia dentro do round     -> senao exit 1
j. rm rounds/.rotate-journal
```

### Guardas de seguranca obrigatorias

Derivadas do gate `owasp-security` sobre este plano. Cada uma e requisito do
contrato, nao sugestao:

| # | Guarda | Motivo |
|---|--------|--------|
| G1 | checkpoint validado por **coluna 1 (`busy`) == 0**, nunca por exit code | `wal_checkpoint` sai `0` mesmo sem checkpointar (verificado); apagar o `-wal` depois seria perda silenciosa de commits |
| G2 | `state.db-wal` ausente ou 0 bytes antes de apagar sidecars | segunda barreira, independente do PRAGMA |
| G3 | `integrity_check` na copia **dentro do round**, apos o commit | confirma que o preservado abre integro |
| G4 | recusar se state-dir, `rounds/`, staging ou alvo for **symlink** (`[ -L ]`), com re-checagem imediatamente antes do commit | um `rounds` symlinkado tracked levaria a rotacao para fora do state-dir e quebraria a premissa "mesmo filesystem ⇒ rename atomico" (o `.gitignore` com `*` semeado pelo `acquire` nao protege path ja tracked) |
| G5 | `--` em todo `mv`/`rm`/`mkdir` | nomes iniciados por `-` nao viram flag |
| G6 | `rotate` **assere o lock detido** (`.lock/` presente + owner compativel); senao exit `3` | FR-012 nao pode depender so de convencao do chamador — `state-rounds.sh` e primitiva standalone e invocavel diretamente |
| G7 | `chmod 700` best-effort nos diretorios de round e staging | alinha com o `chmod 600` que o runtime ja aplica a `state.db` e sidecars (`_state-db.sh:149-151`); sem isso o round nasce com o umask do processo |
| G8 | recusar `rotate` se `<state-dir>/backups` for **symlink** (`[ -L ]`), antes de qualquer escrita, **e re-assertar `[ ! -L ]` imediatamente antes do `mv`** | paridade com G4: um `backups` symlinkado moveria o link (nao o conteudo) para dentro do round, quebrando o confinamento ao state-dir. A re-assercao fecha a janela TOCTOU entre a avaliacao de elegibilidade e o deslocamento. Apos o `mv`, assertar `[ -d "<staging>/backups" ] && [ ! -L ... ]` (`round-scoped-backups`, achado `owasp-security` low) |
| G9 | `chmod 700` best-effort no `backups/` dentro do staging, antes do commit | paridade com G7. `chmod 700` no diretorio do round **nao e recursivo**: sem G9 o `backups/` preservado mantem as permissoes de escrita herdadas do umask. Conteudo ja e filtrado por `secrets-filter.sh for-backup` na escrita — G9 e defesa em profundidade contra leitura por outro usuario local (`round-scoped-backups`) |

> **Limite conhecido de G6 (registrado, nao resolvido aqui)**: `state-lock.sh
> acquire --force` so recusa quando o PID dono esta **vivo**, e o dono gravado e
> o `$PPID` do shell que adquiriu — tipicamente um shell de tool call de vida
> curta, ja morto no resto da execucao. Logo um `--force` concorrente (usado por
> `/feature-00c-abort`) pode legitimamente tomar o lock no meio da rotacao. G6
> reduz a janela mas nao a fecha; a robustez plena de FR-012 depende de um
> modelo de liveness que o runtime atual nao oferece. Fica como divida
> registrada em `plan.md` §Fora de escopo.

Conjunto movido por backend:

| Backend | Itens movidos |
|---------|---------------|
| `json` | `state.json`, `state.json.sha256` (so se existir), `backups/` (so se elegivel) |
| `sqlite` | `state.db`, `backups/` (so se elegivel) |

**Elegibilidade de `backups/`** (normativa — `round-scoped-backups`, FR-001,
FR-006):

| Estado em disco | Acao |
|-----------------|------|
| ausente | nao entra no journal; `rotate` conclui exit `0` |
| existe e vazio (`ls -A` sem saida) | nao entra no journal; round **NAO** ganha `backups/` vazio; `rotate` conclui exit `0` |
| existe e nao-vazio | entra no journal como ultima entrada de `files`; movido no mesmo staging |
| existe e e symlink | `rotate` **recusa** com exit `1` antes de qualquer escrita (G8) |

**Nunca movidos** (permanecem e seguem sendo escritos pela execucao nova, FR-007):
`state-history/`, `enforcement-log.jsonl`, `commit-baseline.txt`,
`mcp-server.json`, `tool-call-ticks.log`, `wave-agent-usage.jsonl`,
`feature-00c-report.md`, `.lock/`, `.gitignore`.

### Response (stdout)

```
ROUND|<label>|<backend>|<state_file>|<execution_id>|<status>
```

Formato pipe-delimitado, no padrao ja usado por `delta-gate.sh`
(`RESULT|...`) — parseavel com `IFS='|'` sem `jq`.

### `--dry-run`

Executa todas as verificacoes e imprime a linha `ROUND|...` que seria produzida,
**sem** criar journal, staging ou mover arquivo. Exit codes identicos.

### Errors

| Exit | Condicao |
|------|----------|
| `3` | sem estado transacional na raiz; ou execucao nao-terminal; ou journal pendente |
| `2` | flag invalida; `--label` fora de `^r[0-9]{2,}$`; label ja existente |
| `1` | `integrity_check` != `ok`; falha de `mv`/`mkdir`; checkpoint falhou |

Em qualquer saida `!= 0`, o state-dir fica **ou** intacto **ou** com journal que
`recover` resolve. Nunca em estado que exija edicao manual (FR-011).

---

## `state-rounds.sh recover --state-dir DIR [--dry-run]`

Resolve rotacao interrompida. **Idempotente**: sem journal, e no-op com exit `0`.
E o comando unico que SC-006 exige ("resolvida por comando em uma unica
tentativa").

### Matriz de decisao

| Disco | Diagnostico | Acao |
|-------|-------------|------|
| sem journal | nada pendente | no-op |
| journal + `rounds/<label>/` ja existe | commit ocorreu, journal orfao | roll-forward: remove journal |
| journal + staging com todos os `files` | interrompida antes do rename | roll-forward: `mv` staging → `<label>`, remove journal |
| journal + staging incompleto | interrompida durante os `mv` | roll-back: devolve itens a raiz (ver §Roll-back de `backups` abaixo), remove staging + journal |

"Staging completo" = todos os nomes de `files` presentes em `staging`,
dispatch por nome literal (sem inferencia de tipo por `stat`): `backups`
conferido por `[ -d ]`; os demais nomes por `[ -f ]`. Sem dependencia externa.

### Validacao J4 (conjunto fechado de `files`)

O journal so admite os literais `state.json`, `state.json.sha256`, `state.db`,
`backups` — qualquer outro valor aborta com exit `1` ("journal malformado:
arquivo fora do fechado"). O conjunto e **fechado por literais**, nunca por
padrao/glob — ampliar a lista sempre exige editar o `case` explicitamente
(`round-scoped-backups`, guarda contra journal adulterado apontando para
caminhos arbitrarios).

### Roll-back de `backups`

Antes de devolver `backups` do staging para a raiz, o `recover` MUST assertar
`[ ! -e "<state-dir>/backups" ]`:

| Condicao | Acao |
|----------|------|
| destino ausente | `mv -- "<staging>/backups" "<state-dir>/backups"` |
| destino existe (qualquer tipo) | **exit `1`** com diagnostico; nada movido, staging e journal preservados para inspecao |

Motivo (verificado empiricamente em Darwin, `round-scoped-backups`
research.md Decision 5): `mv` de diretorio sobre diretorio existente
**aninha** (`backups/backups/...`) com exit `0` — um sucesso falso que
corromperia o layout do state-dir numa rotina de recuperacao. Merge e
`rm -rf` do destino estao **proibidos** neste caminho.

### Response (stdout)

```
RECOVER|<none|forward|rollback>|<label>
```

### Errors

| Exit | Condicao |
|------|----------|
| `1` | journal ilegivel/malformado; `mv` de recuperacao falhou |
| `2` | flag invalida |

---

## `state-rounds.sh list --state-dir DIR`

Lista os rounds preservados, em ordem lexicografica crescente (que coincide com
a cronologica por construcao do label — Decision 3). Read-only.

### Response (stdout)

Uma linha por round:

```
<label>|<backend>|<state_file>|<execution_id>|<status>|<finished_at>
```

Sem rounds: stdout vazio, exit `0`.

### Errors

| Exit | Condicao |
|------|----------|
| `1` | round com estado ilegivel (linha reportada com `status=unknown`, sem abortar a listagem) |
| `2` | flag invalida |

---

## Invariantes de teste (`tests/test_state-rounds.sh`)

| ID | Invariante | Origem |
|----|------------|--------|
| T-01 | `rotate` sobre state-dir sem estado ⇒ exit `3`, disco intacto | FR-002 |
| T-02 | `rotate` com status `em_andamento` ⇒ exit `3`, estado vivo intocado | FR-003 |
| T-03 | `rotate` com status `abortada` ⇒ exit `0` (terminal legitimo) | FR-020 |
| T-04 | round preservado byte a byte identico ao estado pre-rotacao (`cmp`), backend `json` | SC-002 |
| T-05 | idem backend `sqlite`, apos checkpoint | SC-002, FR-010 |
| T-06 | apos `rotate` sqlite, `rounds/<l>/` **nao contem** `state.db-wal` nem `state.db-shm` (nao mais "so `state.db`" — `backups/` tambem e movido desde `round-scoped-backups`) | Decision 2, v6.4.0; emendado por `round-scoped-backups` |
| T-07 | `rotate` 2x ⇒ `r01` e `r02` coexistem; `r01` inalterado | FR-009, AS-1.5 |
| T-08 | interrupcao apos staging ⇒ `recover` roll-forward, 1 tentativa | FR-011, SC-006 |
| T-09 | interrupcao no meio dos `mv` ⇒ `recover` roll-back, state-dir volta ao original | FR-011 |
| T-10 | `recover` sem journal ⇒ no-op exit `0` (idempotente) | FR-011 |
| T-11 | `rotate` com journal pendente ⇒ exit `3`, nao inicia segunda rotacao | FR-011 |
| T-12 | `--dry-run` nao cria journal/staging nem move arquivo | — |
| T-13 | `integrity_check` != `ok` ⇒ exit `1` sem mover nada | FR-011 |
| T-14 | `next-label` com `r01`..`r09` ⇒ `r10`; ordenacao lexicografica preservada | FR-009 |
| T-15 | artefatos nao-transacionais permanecem na raiz apos `rotate` | FR-007 |
| T-16 | `shellcheck -s sh` sem erro; ausencia de bashismo | Principio II |

Invariantes adicionados pela feature `round-scoped-backups` (`backups/`
passa a ser rotacionado para dentro do round):

| ID | Invariante | Origem |
|----|------------|--------|
| T-17 | `rotate` move `backups/` para dentro do round (happy path, backend `sqlite`); stdout `ROUND\|...` sem campo novo | FR-001, SC-001 |
| T-18 | `backups/` de rounds sucessivos nao colidem — `r01/backups/wave-001.json` preservado apos `r02` rotacionar novo conteudo homonimo | FR-002, SC-001 |
| T-19 | `backups/` ausente ⇒ rotacao normal, `rounds/<l>/backups` nao existe, nenhum erro em stderr | FR-006 |
| T-20 | `backups/` vazio ⇒ nao vira dir vazio no round; permanece na raiz; `recover` pos-rotate ⇒ `RECOVER\|none\|-` | FR-006 |
| T-21 | interrupcao apos staging completo (incluindo `backups/`) ⇒ `recover` roll-forward move `backups/` junto | FR-004, FR-008 |
| T-22 | interrupcao no meio dos `mv` (`backups/` ainda na raiz) ⇒ roll-back preserva `backups/` intacto na raiz | FR-004, FR-008 |
| T-23 | roll-back com `backups/` preexistente na raiz (estado anomalo) ⇒ exit `1`, recusa explicita, anti-aninhamento (`backups/backups/` nunca criado) | FR-004, research.md Decision 5 |
| T-24 | J4 admite `backups` como literal (controle positivo); rejeita caminho arbitrario (`../../etc/passwd`, controle negativo) | FR-004 |
| T-25 | `backups/` symlink ⇒ `rotate` recusa com exit `1` (G8), nada escrito | G8 |
| T-26 | purge do abort (`feature-00c-abort.md` §8, `rm -rf -- "$SD/backups"`) nao toca rounds preservados | FR-005, SC-003 |
| T-27 | `list` inalterado (mesmo numero de campos) com round contendo `backups/` | — |
| T-28 | `backups/` preservado com permissoes `700` (G9), best-effort | G9 |
