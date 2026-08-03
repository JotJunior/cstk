# Quickstart: state-db-runtime-parity

Cenarios de validacao dos fluxos criticos. `SCRIPTS` =
`global/skills/agente-00c-runtime/scripts` (ou copia instalada). Cada cenario
e reproduzido na suite (`tests/`).

## Cenario 1 — Helper de orcamento sob SQLite (US1, happy path)

1. Inicializar state-dir com backend SQLite (`state-rw.sh init` com config
   global `state_backend=sqlite`) e popular (onda via `state-ondas.sh start`).
2. Rodar `budget.sh check --state-dir "$SD"`.
3. **Expected**: avaliacao normal dos thresholds; NENHUMA mensagem
   `state.json ausente`; nenhum `state.json` criado em `$SD` (anti-mirror).

## Cenario 2 — Equivalencia de veredito entre backends (US1/SC-003)

1. Gravar o MESMO estado logico num state-dir JSON e num SQLite.
2. Rodar `cycles.sh check`, `circular.sh detect`, `drift.sh check`,
   `retro.sh check` contra cada um.
3. **Expected**: exit code + semantica de saida identicos nos dois backends.

## Cenario 3 — Promocao terminal multi-campo (US2, happy path + error case)

1. State-dir SQLite com execucao `em_andamento`.
2. Rodar `state-rw.sh set --state-dir "$SD" --field '.execution.status'
   --value '"concluida"' --field '.execution.finished_at' --value '"<ISO>"'`.
3. **Expected**: exit 0; `state-rw.sh get --field '.execution.status'` =
   `concluida`.
4. (Error case) Rodar `set` apenas com `--field '.execution.status' --value
   '"concluida"'` (sem `finished_at` no lote).
5. **Expected**: rejeicao com diagnostico citando a invariante C2 e os campos;
   status permanece `em_andamento` (estado intacto, sem escrita parcial).

## Cenario 4 — Force-acquire de lock orfao (US3)

1. Criar `$SD/.lock/` simulando dono morto.
2. Rodar `state-lock.sh acquire --state-dir "$SD" --force`.
3. **Expected**: exit 0; diagnostico auditavel de aquisicao forcada; lock
   detido pelo chamador. Sem `--force`: exit 3 (inalterado).

## Cenario 5 — Exit contratual do relatorio (US4)

1. State-dir sem `state.json` E sem `state.db`.
2. Rodar `report.sh emit --flavor feature-00c --state-dir "$SD"` e
   `report.sh generate --state-dir "$SD"`.
3. **Expected**: exit 7 nos dois; diagnostico em stderr; demais modos de
   falha (uso, flavor invalido) preservam exits atuais.

## Cenario 6 — Varredura detecta reintroducao (US5)

1. Rodar `tests/run.sh state-parity-sweep` — **Expected**: verde.
2. Introduzir helper sintetico lendo `state.json` direto (fixture do teste).
3. **Expected**: camada estatica falha apontando o arquivo/linha; remover o
   sintetico e a suite volta a verde.

## Roundtrip End-to-End (real, nao mock)

O cenario 1 + 3 encadeados constituem o roundtrip real: `state-rw.sh init`
(escreve `state.db` de verdade) → helpers leem via interface canonica →
promocao terminal multi-campo → `report.sh emit` gera relatorio a partir do
MESMO `state.db` — nenhum fixture JSON intermediario. Compare o shape do
estado lido (`state-rw.sh read`) com o documento canonico esperado pelo
`state-validate.sh`. N/A borda frontend (feature single-layer).
