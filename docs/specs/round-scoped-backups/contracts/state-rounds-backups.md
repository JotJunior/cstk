# Contract Delta: `state-rounds.sh` passa a rotacionar `backups/`

**Feature**: `round-scoped-backups` | **Date**: 2026-08-21
**Contrato base (REAL, em vigor)**:
[`docs/specs/feature-reopen/contracts/state-rounds.md`](../../feature-reopen/contracts/state-rounds.md)
**Implementacao (REAL, em vigor)**:
`plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh`

> **Natureza deste documento**: e um **DELTA**, nao uma segunda fonte de verdade.
> Descreve as emendas que a implementacao desta feature MUST aplicar ao contrato
> base. Tudo marcado `[PROPOSTA]` ainda NAO existe no codigo; tudo descrito como
> "hoje" foi lido no arquivo real citado. Ao fim da implementacao, as emendas
> vivem no contrato base e este arquivo permanece como registro do delta.

---

## 1. Assinaturas de CLI: inalteradas

Nenhum subcomando, flag ou formato de stdout muda.

| Superficie | Hoje | Depois |
|------------|------|--------|
| `next-label --state-dir DIR` | `<label>` | identico |
| `rotate --state-dir DIR [--label L] [--dry-run]` | `ROUND\|<label>\|<backend>\|<state_file>\|<execution_id>\|<status>` | **identico** |
| `recover --state-dir DIR [--dry-run]` | `RECOVER\|<none\|forward\|rollback>\|<label>` | identico |
| `list --state-dir DIR` | `<label>\|<backend>\|<state_file>\|<execution_id>\|<status>\|<finished_at>` | identico |
| Exit codes | `0` / `1` / `2` / `3` | identicos |

**Restricao dura**: o consumidor `plugins/cstk/commands/feature-00c.md` (secao
2.bis, passo 7.c) faz parsing da linha `ROUND|...`. Nenhum campo pode ser
adicionado, removido ou reordenado — inclusive `<state_file>`, que continua
nomeando **o arquivo de estado transacional** (`state.db` ou `state.json`), nunca
`backups`.

---

## 2. Emenda: tabela "Conjunto movido por backend"

**Hoje** (contrato base §Conjunto movido por backend):

| Backend | Arquivos |
|---------|----------|
| `json` | `state.json`, `state.json.sha256` (o `.sha256` so se existir) |
| `sqlite` | `state.db` (apenas) |

**[PROPOSTA] Depois**:

| Backend | Itens movidos |
|---------|---------------|
| `json` | `state.json`, `state.json.sha256` (so se existir), `backups/` (so se elegivel) |
| `sqlite` | `state.db`, `backups/` (so se elegivel) |

**Elegibilidade de `backups/`** (normativa):

| Estado em disco | Acao |
|-----------------|------|
| ausente | nao entra no journal; `rotate` conclui exit `0` |
| existe e vazio (`ls -A1` sem saida) | nao entra no journal; round **NAO** ganha `backups/` vazio; `rotate` conclui exit `0` |
| existe e nao-vazio | entra no journal como ultima entrada de `files`; movido no mesmo staging |
| existe e e symlink | `rotate` **recusa** com exit `1` antes de qualquer escrita (G8) |

---

## 3. Emenda: lista "Nunca movidos"

**Hoje**: `state-history/`, `backups/`, `enforcement-log.jsonl`,
`commit-baseline.txt`, `mcp-server.json`, `tool-call-ticks.log`,
`wave-agent-usage.jsonl`, `feature-00c-report.md`, `.lock/`, `.gitignore`.

**[PROPOSTA] Depois**: identica, **menos `backups/`** — que passa a ser movido
quando elegivel. Os outros nove itens permanecem na raiz e seguem sendo escritos
pela execucao nova (FR-007 da `feature-reopen`).

---

## 4. Emenda: sequencia do `rotate`

Alteracoes sobre a sequencia documentada (passos `a`..`j` do contrato base):

```
b2. ASSERT nao-symlink: state-dir, rounds/, staging, alvo
    [PROPOSTA] + backups/ (G8)                                -> senao exit 1
...
[PROPOSTA] b3. elegibilidade de backups/: existe && nao-symlink && nao-vazio
           => anexa `backups` ao fim do CSV `files`
d.  escreve rounds/.rotate-journal (phase=staged)   # `files` ja inclui backups
f.  mv -- de cada item de `files` -> staging   (phase=moving)
    [PROPOSTA] `backups` e movido como diretorio, no MESMO staging
h1. COMMIT: mv -- rounds/.<label>.staging -> rounds/<label>    [atomico]
    (inalterado: o commit unico publica estado + snapshots juntos)
```

Invariante de atomicidade (FR-001/FR-008): **nao ha segundo ponto de commit**. Ou
o `rename(2)` do passo `h1` ocorreu — e o round tem estado + snapshots — ou nao
ocorreu e o `recover` resolve por roll-forward/roll-back.

---

## 5. Emenda: `recover`

### 5.1 Validacao J4 (conjunto fechado de `files`)

| Hoje | [PROPOSTA] Depois |
|------|-------------------|
| `state.json` \| `state.json.sha256` \| `state.db` | `state.json` \| `state.json.sha256` \| `state.db` \| `backups` |

Qualquer outro valor continua abortando com exit `1` ("journal malformado:
arquivo fora do fechado"). O conjunto permanece **fechado por literais** — nao
vira padrao/glob.

### 5.2 Definicao de "staging completo"

| Hoje | [PROPOSTA] Depois |
|------|-------------------|
| todos os nomes de `files` presentes por `[ -f ]` | `backups` conferido por `[ -d ]`; demais por `[ -f ]` |

### 5.3 Roll-back de `backups`

**[PROPOSTA] Normativo**: antes de devolver `backups` do staging para a raiz, o
`recover` MUST assertar `[ ! -e "<state-dir>/backups" ]`.

| Condicao | Acao |
|----------|------|
| destino ausente | `mv -- "<staging>/backups" "<state-dir>/backups"` |
| destino existe (qualquer tipo) | **exit `1`** com diagnostico; nada movido, staging e journal preservados para inspecao |

Motivo (verificado empiricamente em `Darwin`, ver research.md Decision 5): `mv`
de diretorio sobre diretorio existente **aninha** (`backups/backups/...`) com exit
`0` — um sucesso falso que corromperia o layout do state-dir numa rotina de
recuperacao. Merge e `rm -rf` do destino estao **proibidos** neste caminho.

### 5.4 Matriz de decisao

Inalterada em estrutura; so a definicao de "staging completo" muda (§5.2):

| Disco | Diagnostico | Acao |
|-------|-------------|------|
| sem journal | nada pendente | no-op |
| journal + `rounds/<label>/` ja existe | commit ocorreu, journal orfao | roll-forward: remove journal |
| journal + staging completo | interrompida antes do rename | roll-forward: `mv` staging → `<label>` |
| journal + staging incompleto | interrompida durante os `mv` | roll-back: devolve itens a raiz (§5.3), remove staging + journal |

---

## 6. Emenda: guardas de seguranca

**[PROPOSTA] Guardas novas**, adicionadas a tabela G1..G7 do contrato base:

| # | Guarda | Motivo |
|---|--------|--------|
| G8 | recusar `rotate` se `<state-dir>/backups` for **symlink** (`[ -L ]`), antes de qualquer escrita, **e re-assertar `[ ! -L ]` imediatamente antes do `mv`** | paridade com G4: um `backups` symlinkado moveria o link (nao o conteudo) para dentro do round, quebrando o confinamento ao state-dir e a premissa "mesmo filesystem ⇒ rename atomico". A re-assercao fecha a janela TOCTOU entre a avaliacao de elegibilidade e o deslocamento — mesmo padrao que o contrato base ja exige para o alvo do commit ("re-ASSERT nao-symlink do alvo, imediatamente antes do commit"). Apos o `mv`, assertar `[ -d "<staging>/backups" ] && [ ! -L ... ]`. |
| G9 | `chmod 700` best-effort no `backups/` dentro do staging | paridade com G7. `chmod 700` no diretorio do round **nao e recursivo**: sem G9 o `backups/` preservado mantem as permissoes de escrita herdadas do umask. Verificado nos state-dirs reais deste repo: `drwxr-xr-x` no diretorio e `-rw-r--r--` nos `wave-NNN.json` (o `mkdir(backupDir, { recursive: true })` de `mcp/state-server/src/tools/close_wave.ts` nao passa `mode`). Conteudo ja e filtrado por `secrets-filter.sh for-backup` na escrita — G9 e defesa em profundidade contra leitura por outro usuario local, alinhada ao `chmod 600` que `_state-db.sh` ja aplica ao `state.db`. |

Guardas G1..G7 permanecem integralmente em vigor. G5 (`--` em todo
`mv`/`rm`/`mkdir`) aplica-se tambem aos comandos novos que manipulam `backups`.

---

## 7. Emenda: invariante T-06

| Hoje | [PROPOSTA] Depois |
|------|-------------------|
| "apos `rotate` sqlite, `rounds/<l>/` contem **so** `state.db`; nenhum `-wal`/`-shm`" | "apos `rotate` sqlite, `rounds/<l>/` **nao contem** `state.db-wal` nem `state.db-shm`" |

A intencao real de T-06 (Decision 2 da `feature-reopen`, v6.4.0) e impedir que
sidecars WAL — derivados e divergentes entre macOS e Ubuntu — entrem no round.
A formulacao "contem so `state.db`" era uma consequencia do conjunto movido da
epoca, nao o objetivo. O comentario correspondente em `state-rounds.sh` (bloco
`# T-06:` que precede o `rm -f -- "$_RT_TARGET/state.db-wal" ...`) MUST ser
reescrito na mesma direcao.

---

## 8. Fora do escopo deste delta

| Item | Situacao |
|------|----------|
| Escritores de snapshot (orquestradores, `mcp/state-server/src/tools/close_wave.ts`, `feature-00c-abort.md`) | **sem mudanca** — continuam gravando em `<state-dir>/backups/wave-NNN.json` (FR-007) |
| `--purge-backups` do `feature-00c-abort` | **sem mudanca de codigo** — ja escopado a `"$AGENTE_00C_STATE_DIR/backups"`; passa a ter teste de regressao (FR-005) |
| Rounds rotacionados antes desta feature | **sem backfill** — decisao de clarify registrada na spec; perda historica irrecuperavel documentada |
