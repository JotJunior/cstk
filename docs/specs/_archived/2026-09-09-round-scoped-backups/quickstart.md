# Quickstart / Cenarios de Teste: `round-scoped-backups`

**Feature**: `round-scoped-backups` | **Date**: 2026-08-21

Harness alvo: `tests/test_state-rounds.sh` (cenarios existentes T-01..T-16).
Execucao: `./tests/run.sh test_state-rounds` (padrao documentado em
`CLAUDE.md` §Como testar scripts shell). Numeracao dos cenarios NOVOS continua a
existente: **T-17..T-28**.

Convencao usada abaixo: `SD` = state-dir de fixture;
`SR` = `plugins/cstk/skills/agente-00c-runtime/scripts/state-rounds.sh`.
O `rotate` exige lock detido (guarda G6) e status terminal — as fixtures existentes
do arquivo ja montam esse cenario; os novos cenarios reusam o mesmo preparo.

---

## T-17 — Snapshots vao para dentro do round (happy path)

**FR**: FR-001 | **SC**: SC-001

1. Montar `SD` terminal (backend `sqlite`) com `SD/backups/wave-001.json` e
   `SD/backups/wave-002.json` de conteudos distintos.
2. `SR rotate --state-dir "$SD"`.
3. **Expected**: exit `0`; `rounds/r01/backups/wave-001.json` e
   `wave-002.json` existem e sao `cmp`-identicos aos originais;
   `SD/backups` **nao existe mais** na raiz; `rounds/r01/state.db` presente.
4. **Expected**: stdout casa exatamente `ROUND|r01|sqlite|state.db|<id>|<status>`
   (regressao do consumidor `feature-00c.md` 2.bis/7.c — nenhum campo novo).

## T-18 — Dois rounds, mesma numeracao de onda, zero colisao

**FR**: FR-002 | **SC**: SC-001

1. Rotacionar um `SD` com `backups/wave-001.json` de conteudo `A` ⇒ `r01`.
2. Recriar estado terminal + `backups/wave-001.json` de conteudo `B`.
3. `SR rotate --state-dir "$SD"` ⇒ `r02`.
4. **Expected**: `rounds/r01/backups/wave-001.json` continua com `A`
   (`cmp` contra fixture original) e `rounds/r02/backups/wave-001.json` tem `B`.
   Nenhuma sobrescrita entre rounds.

## T-19 — `backups/` ausente: rotacao normal

**FR**: FR-006 | **SC**: SC-004

1. Montar `SD` terminal **sem** `backups/`.
2. `SR rotate --state-dir "$SD"`.
3. **Expected**: exit `0`; `rounds/r01/state.db` presente;
   `rounds/r01/backups` **nao existe**; nenhum erro em stderr sobre ausencia.

## T-20 — `backups/` vazio: nao vira diretorio vazio no round

**FR**: FR-006 | **SC**: SC-004

1. Montar `SD` terminal com `SD/backups/` existente e **vazio**.
2. `SR rotate --state-dir "$SD"`.
3. **Expected**: exit `0`; `rounds/r01/backups` **nao existe**; o diretorio vazio
   permanece na raiz (`SD/backups` ainda e diretorio).
4. **Expected**: journal ja removido; `SR recover --state-dir "$SD"` ⇒
   `RECOVER|none|-`.

## T-21 — Interrupcao apos staging completo ⇒ roll-forward em 1 tentativa

**FR**: FR-004, FR-008 | **SC**: SC-002

1. Simular interrupcao pos-`moving` (mesmo mecanismo do T-08 existente): journal
   com `files` incluindo `backups`, staging contendo `state.db` **e**
   `backups/` completo, `rounds/r01/` ainda inexistente.
2. `SR recover --state-dir "$SD"`.
3. **Expected**: stdout `RECOVER|forward|r01`, exit `0`; `rounds/r01/backups/`
   com os snapshots; journal removido.
4. **Expected**: segunda invocacao de `recover` ⇒ `RECOVER|none|-` (idempotente,
   uma unica tentativa resolveu).

## T-22 — Interrupcao no meio dos `mv` ⇒ roll-back devolve tudo

**FR**: FR-004, FR-008 | **SC**: SC-002

1. Simular interrupcao com `state.db` ja no staging e `backups/` **ainda na
   raiz**; journal `phase=moving` com `files=state.db,backups`.
2. `SR recover --state-dir "$SD"`.
3. **Expected**: stdout `RECOVER|rollback|r01`, exit `0`; `SD/state.db` de volta
   na raiz; `SD/backups/` intacto na raiz; staging e journal removidos;
   `rounds/r01` inexistente.
4. **Expected**: conjunto na raiz `cmp`-identico ao pre-rotacao (nada dividido
   entre raiz e round).

## T-23 — Roll-back com `backups/` preexistente na raiz ⇒ falha explicita

**FR**: FR-004, FR-008 | **Origem**: research.md Decision 5 (evidencia empirica)

1. Montar staging INCOMPLETO contendo `backups/` **e** um `SD/backups/` tambem
   presente na raiz (estado anomalo).
2. `SR recover --state-dir "$SD"`.
3. **Expected**: exit `1` com diagnostico em stderr citando o destino existente.
4. **Expected**: **nenhum** `SD/backups/backups/` criado (assercao anti-aninhamento);
   staging e journal preservados para inspecao.

## T-24 — Journal com entrada fora do conjunto fechado continua rejeitado

**FR**: FR-004 (guarda J4 preservada)

1. Escrever journal a mao com `files=state.db,../../etc/passwd`.
2. `SR recover --state-dir "$SD"`.
3. **Expected**: exit `1`, mensagem "arquivo fora do fechado"; nada movido.
4. **Expected (controle positivo)**: `files=state.db,backups` **e aceito** —
   prova que a ampliacao do conjunto e por literal, nao por relaxamento da guarda.

## T-25 — `backups/` symlink ⇒ `rotate` recusa (G8)

**FR**: FR-001 (guarda G8) | **Origem**: paridade com G4 do contrato base

1. Montar `SD` terminal com `SD/backups` como **symlink** para um diretorio fora
   do state-dir contendo um `wave-001.json`.
2. `SR rotate --state-dir "$SD"`.
3. **Expected**: exit `1`; nenhum journal, nenhum staging, `rounds/r01`
   inexistente; `SD/state.db` intocado; o alvo do symlink intocado.

## T-26 — Purge do abort nao toca rounds preservados

**FR**: FR-005 | **SC**: SC-003

1. Montar `SD` com `rounds/r01/backups/wave-001.json` **e** `SD/backups/wave-001.json`
   (execucao corrente).
2. Executar o purge exatamente como o comando faz:
   `rm -rf -- "$SD/backups"` (linha reproduzida de
   `plugins/cstk/commands/feature-00c-abort.md` §8).
3. **Expected**: `SD/backups` removido; `rounds/r01/backups/wave-001.json`
   **intacto** e `cmp`-identico a fixture.

## T-27 — `list` inalterado com round contendo `backups/`

**FR**: FR-003 (contrato) | **Regressao**

1. Rotacionar um `SD` com snapshots (⇒ `rounds/r01/backups/`).
2. `SR list --state-dir "$SD"`.
3. **Expected**: exit `0`; exatamente uma linha, no formato
   `r01|sqlite|state.db|<id>|<status>|<finished_at>` — a presenca de `backups/`
   nao altera deteccao de backend nem numero de campos.

## T-28 — Snapshots preservados com permissao restritiva (G9)

**FR**: FR-001 | **Origem**: gate `owasp-security` (finding low, defesa em profundidade)

1. Montar `SD` terminal com `SD/backups/wave-001.json` e permissoes permissivas
   (`chmod 755 "$SD/backups"`, `chmod 644 "$SD/backups/wave-001.json"` — o estado
   que os state-dirs reais apresentam hoje).
2. `SR rotate --state-dir "$SD"`.
3. **Expected**: exit `0`; `rounds/r01/backups` com modo `700`.
4. **Nota**: assercao de modo e best-effort (paridade com G7) — em filesystem que
   nao suporte `chmod`, o cenario deve degradar sem falhar a suite, no mesmo
   padrao ja usado pelos cenarios que conferem G7.

---

## T-15 (existente) — emenda, nao cenario novo

`tests/test_state-rounds.sh` cenario `scenario_T15_artefatos_nao_transacionais_permanecem`
hoje asserta `[ -f "$_sd/backups/wave-001.json" ]` apos `rotate`, tratando
"`backups/` foi movido" como falha — o **oposto** de FR-001.

**Emenda**: remover apenas as duas linhas relativas a `backups` (o `mkdir -p
"$_sd/backups"` + `printf` da fixture podem permanecer, uteis como carga do
cenario) e manter integralmente as assercoes de `enforcement-log.jsonl`,
`commit-baseline.txt`, `state-history/`, `.lock/` e a de nao-vazamento
(`[ ! -f "$_sd/rounds/r01/enforcement-log.jsonl" ]`).

## T-16 (existente) — cobre a conformidade POSIX

`shellcheck -s sh` sem erro + ausencia de bashismo continua sendo o gate de
Principio II para todo codigo novo desta feature. Nenhum cenario novo necessario.

---

## Verificacao manual complementar (opcional, nao automatizada)

```
# Em um state-dir real de feature ja reaberta:
state-rounds.sh list --state-dir <SD>
find <SD>/rounds -name 'wave-*.json' | sort
```

**Expected**: cada `rounds/<label>/` com snapshots proprios; nenhum
`wave-NNN.json` orfao na raiz pertencente a round anterior.
