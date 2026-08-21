# Data Model: Escopar `backups/` na rotacao de round

**Feature**: `round-scoped-backups` | **Date**: 2026-08-21

Esta feature nao introduz banco, tabela nem schema novo. O "modelo de dados" e o
layout do state-dir em disco e o registro de transacao (journal) que descreve uma
rotacao em andamento. Todos os campos abaixo foram lidos em
`plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh` (funcoes
`_sr_write_journal`, `_sr_journal_field`, `_sr_staging_complete`) — nenhum e
proposto sem origem.

---

## Entity: `JournalDeRotacao`

Arquivo `<state-dir>/rounds/.rotate-journal`. Formato `chave=valor`, uma por
linha, lido por parser proprio linha-a-linha (`_sr_journal_field`, regra J1 do
contrato — NUNCA `.`/`source`/`eval`). Escrito inteiro a cada transicao (nao e
append).

| Campo | Tipo | Origem | Muda nesta feature? |
|-------|------|--------|---------------------|
| `label` | string `^r[0-9]{2,}$` | `_sr_write_journal` arg 2 | Nao |
| `backend` | enum `json` \| `sqlite` | `_sr_write_journal` arg 3 | Nao |
| `files` | CSV de nomes | `_sr_write_journal` arg 4 | **Sim** — pode conter `backups` |
| `staging` | string `rounds/.<label>.staging` | `_sr_write_journal` (derivado do label) | Nao |
| `phase` | enum `staged` \| `moving` | `_sr_write_journal` arg 5 | Nao |
| `started_at` | ISO 8601 UTC | `_sr_write_journal` arg 6 | Nao |

### Regra de validacao do campo `files` (J4)

Conjunto **fechado** — qualquer valor fora dele faz o `recover` abortar com exit
`1` (guarda contra journal adulterado apontando para caminhos arbitrarios).

| Antes | Depois |
|-------|--------|
| `state.json`, `state.json.sha256`, `state.db` | `state.json`, `state.json.sha256`, `state.db`, **`backups`** |

O tipo de cada entrada e derivado do nome (Decision 2 do research):

| Entrada | Tipo em disco | Predicado de presenca no staging |
|---------|---------------|----------------------------------|
| `state.json` | arquivo | `[ -f ]` |
| `state.json.sha256` | arquivo | `[ -f ]` |
| `state.db` | arquivo | `[ -f ]` |
| `backups` | diretorio | `[ -d ]` |

### State transitions

```
(sem journal)
     |  rotate: escreve journal
     v
  phase=staged  ──── mv dos itens de `files` ───▶  phase=moving
     |                                                  |
     | recover: staging incompleto                      | recover: staging completo
     | => ROLL-BACK                                      | => ROLL-FORWARD
     v                                                  v
(sem journal, itens na raiz)                    (sem journal, round publicado)
                          ▲                              ▲
                          └──── rotate: commit + rm journal ─┘
```

Sem mudanca de maquina de estados: a feature so amplia o conjunto de itens que
transitam por ela.

---

## Entity: `ConjuntoMovido`

Lista ordenada de itens deslocados por UMA rotacao. Materializada em memoria como
`_RT_FILES_CSV` no `rotate` e persistida no campo `files` do journal.

| Backend | Itens transacionais | Item de snapshots (novo) |
|---------|---------------------|--------------------------|
| `json` | `state.json`, `state.json.sha256` (o `.sha256` so se existir) | `backups` (so se elegivel) |
| `sqlite` | `state.db` | `backups` (so se elegivel) |

**Elegibilidade de `backups`** (Decision 3):

| Condicao em disco | Entra no CSV? | Efeito no round |
|-------------------|---------------|-----------------|
| Ausente | Nao | round sem `backups/` |
| Existe, vazio | Nao | round sem `backups/`; dir vazio permanece na raiz |
| Existe, nao-vazio | Sim | round contem `backups/` com o conteudo integral |
| Existe, e symlink | Nao — `rotate` **recusa** (exit `1`, G8) | nada movido |

Ordem no CSV: itens transacionais primeiro, `backups` por ultimo. Consequencia
util para o roll-back: o item mais volumoso e o ultimo a sair da raiz e o
primeiro candidato a nao ter saido numa interrupcao.

---

## Entity: `RoundPreservado`

Diretorio `<state-dir>/rounds/<label>/`, `chmod 700` best-effort (G7).

| Conteudo | Antes | Depois |
|----------|-------|--------|
| `state.db` (backend sqlite) | sempre | sempre |
| `state.json` (+ `.sha256`, se existia) (backend json) | sempre | sempre |
| `state.db-wal` / `state.db-shm` | **nunca** (T-06) | **nunca** (T-06 mantida) |
| `backups/` | nunca | **quando elegivel na rotacao** |

`state-rounds.sh list` deriva backend e metadados do round por
`[ -f "$round/state.db" ]` / `[ -f "$round/state.json" ]` — a presenca de
`backups/` nao interfere nessa deteccao nem no formato de saida
`<label>|<backend>|<state_file>|<execution_id>|<status>|<finished_at>`.

---

## Entity: `DiretorioDeSnapshots`

`<state-dir>/backups/`, populado durante a execucao com `wave-NNN.json`
(saida filtrada por `secrets-filter.sh for-backup`).

| Aspecto | Regra |
|---------|-------|
| Quem escreve | prosa dos orquestradores; `mcp/state-server/src/tools/close_wave.ts`; `plugins/cstk/commands/feature-00c-abort.md` |
| Onde escreve | `<state-dir>/backups/wave-NNN.json` — **inalterado** (FR-007) |
| Numeracao | reinicia em `wave-001.json` a cada execucao nova (causa da colisao da issue #150) |
| Ciclo de vida | movido para dentro do round na rotacao (esta feature); apagado por `--purge-backups` no abort **somente na raiz** (FR-005) |

**Isolamento de colisao**: apos a rotacao, `rounds/r01/backups/wave-001.json` e
`<state-dir>/backups/wave-001.json` sao caminhos distintos — a reinicializacao da
numeracao deixa de sobrescrever historico (FR-002/SC-001).

---

## Layout resultante (exemplo, backend sqlite, apos 2 reaberturas)

```
<state-dir>/
├── state.db                      # execucao corrente (3o round, ainda nao rotacionado)
├── backups/                      # snapshots da execucao corrente
│   └── wave-001.json
├── rounds/
│   ├── r01/
│   │   ├── state.db
│   │   └── backups/              # NOVO — snapshots do 1o round
│   │       ├── wave-001.json
│   │       └── wave-011.json
│   └── r02/
│       ├── state.db
│       └── backups/              # NOVO — snapshots do 2o round
│           └── wave-001.json
├── state-history/                # nunca movido
├── enforcement-log.jsonl         # nunca movido
├── commit-baseline.txt           # nunca movido
└── .lock/                        # nunca movido
```
