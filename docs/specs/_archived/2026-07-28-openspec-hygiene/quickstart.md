# Quickstart: openspec-hygiene

**Feature**: `openspec-hygiene`
**Date**: 2026-07-23

Cenarios de validacao por User Story. Paths de scripts relativos a
raiz do repo cstk.

## Cenario 1 — Gate falha citando o requisito exato (US1, happy-path do gate)

1. Criar fixture `spec.md` com `FR-001` coberto por cenario e `FR-003`
   sem nenhum cenario relacionado (nem ID literal, nem termos-chave no
   corpus).
2. Rodar `global/skills/checklist/scripts/requirement-coverage.sh fixture/spec.md`
3. **Expected**: stdout contem `FINDING|error|fr-no-scenario|` com
   `FR-003` citado e sugestao de correcao; `RESULT|...|errors=1`;
   exit 1.

## Cenario 2 — Gate passa com spec integralmente coberta (US1)

1. Rodar o gate sobre fixture onde todo FR tem cenario associado
   (mistura de fast-path por ID literal e cobertura heuristica).
2. **Expected**: zero linhas `FINDING`; `RESULT|...|errors=0`; exit 0.

## Cenario 3 — Spec sem Functional Requirements passa trivialmente (US1, edge)

1. Rodar o gate sobre fixture sem secao `### Functional Requirements`
   (ou secao vazia).
2. **Expected**: `RESULT|...|requirements=0|covered=0|errors=0`; exit 0.

## Cenario 4 — Fixture real do repo (US1, anti-regressao de heuristica)

1. Rodar o gate sobre `docs/specs/openspec-hygiene/spec.md` (esta
   feature — 17 FRs, todos com cenarios das US1-US4/Edge Cases).
2. **Expected**: exit 0. (Se falhar, a stoplist/threshold precisa de
   calibracao — nao a spec.)

## Cenario 5 — Uso incorreto (US1, error case)

1. Rodar sem argumento; rodar com FILE inexistente; rodar com
   `--min-match 0`.
2. **Expected**: exit 2 em todos, com usage/mensagem em stderr.

## Cenario 6 — Triagem update-vs-nova recomenda atualizar (US2)

1. Com `docs/specs/foo/spec.md` existente, apresentar a `specify` um
   pedido que refina a mesma intencao (mesmos atores/objetivo).
2. **Expected**: ETAPA 0 da skill recomenda atualizar
   `docs/specs/foo/spec.md`, citando o criterio (mesma
   intencao/refinamento) — sem criar diretorio novo.

## Cenario 7 — Triagem recomenda feature nova (US2)

1. Apresentar pedido com atores/capacidade fora da intencao original
   de qualquer spec ativa.
2. **Expected**: recomendacao de nova feature citando o criterio
   (intencao mudou/escopo expandiu); sem spec relacionada, segue
   direto sem overhead (FR-008).

## Cenario 8 — Archive datado (US3)

1. Seguir o passo de arquivamento documentado em
   `review-features/SKILL.md` para a feature `foo-bar` na data D.
2. **Expected**: destino `docs/specs/_archived/<D>-foo-bar/`; dirs
   pre-existentes sem prefixo permanecem intocados; `ls _archived/`
   ordena os novos dirs cronologicamente.

## Cenario 9 — Envelope diagnostico em falha real (US4)

1. Invocar `state-rw.sh sha256-verify` num state-dir com hash
   adulterado (fixture).
2. **Expected**: stderr contem a mensagem legada (`hash divergente...`)
   E a linha `DIAG|error|hash-mismatch|<msg>|<fix>`; os 4 campos
   presentes; `fix` != `message`; exit code inalterado vs hoje.

## Cenario 10 — Codes distintos por condicao (US4)

1. Provocar duas falhas distintas no mesmo script-piloto (ex.:
   `state-rw.sh` com state ausente vs JSON invalido).
2. **Expected**: linhas `DIAG|` com codes diferentes
   (`state-not-found` vs `state-invalid-json`), distinguiveis via
   `cut -d'|' -f3` sem parsing de texto livre.

## Cenario 11 — Script fora de escopo intacto (US4, SC-006)

1. Provocar falha em script fora do escopo-piloto (ex.: `budget.sh`
   com uso incorreto).
2. **Expected**: stderr identico ao formato atual; NENHUMA linha
   `DIAG|`; suite de testes existente verde sem alteracao.

## Cenario 12 — Roundtrip End-to-End

N/A — feature single-layer (scripts POSIX locais + prosa de SKILL.md);
nao ha borda backend↔frontend. A validacao empirica equivalente e o
Cenario 4 (gate rodando sobre spec real do repo) + suite
`./tests/run.sh` completa verde.
