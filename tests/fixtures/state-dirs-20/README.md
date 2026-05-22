# Fixture `state-dirs-20`

**Origem**: Tarefa 4.5 (FASE 4) — `docs/specs/model-selector/tasks.md`
**Refs**: SC-003, Plan §Project Structure, CHK018, CHK016, CHK017

## Proposito

Conjunto canonico de 20 arquivos `state.json` mockados usados pelo teste
de performance `tests/cstk/test_report_performance.sh` (subtarefa 4.4.3)
para medir a mediana wallclock de `scripts/report.sh` sobre 5 runs.

Tambem reutilizavel por testes de equivalencia byte-identical
(4.4.1) e confinamento (4.4.2) quando precisarem de massa pseudo-real
(state.json acima do tamanho minimo de validacao).

## Estrutura

```
tests/fixtures/state-dirs-20/
├── README.md            (este arquivo)
├── feat-01/state.json   (perfil P1 — haiku-dominante,  populado)
├── feat-02/state.json   (perfil P2 — sonnet-dominante, populado)
├── feat-03/state.json   (perfil P3 — opus-dominante,   populado)
├── feat-04/state.json   (perfil P4 — manter-atual,     populado)
├── feat-05/state.json   (perfil P5 — alto volume haiku, populado)
├── feat-06/state.json   (perfil P6 — alto volume sonnet,populado)
├── feat-07/state.json   (perfil P7 — tie-break alfabetico, populado)
├── feat-08/state.json   (perfil P8 — bag-zero, populado)
├── feat-09/state.json   (perfil P9 — haiku/sonnet misto, populado)
├── feat-10/state.json   (perfil P10 — opus/sonnet misto, populado)
├── feat-11/state.json   (perfil L1 — lazy: sem model_selector)
├── feat-12/state.json   (perfil L2 — lazy: sem model_selector)
├── feat-13/state.json   (perfil L3 — lazy: sem model_selector)
├── feat-14/state.json   (perfil L4 — lazy: sem model_selector)
├── feat-15/state.json   (perfil L5 — lazy: sem model_selector)
├── feat-16/state.json   (perfil Z1 — zero sugestoes — total=0)
├── feat-17/state.json   (perfil Z2 — zero sugestoes — total=0)
├── feat-18/state.json   (perfil Z3 — zero sugestoes — total=0)
├── feat-19/state.json   (perfil Z4 — zero sugestoes — total=0)
└── feat-20/state.json   (perfil Z5 — zero sugestoes — total=0)
```

## Invariantes (Ref CHK018, criterio cravado)

| Invariante | Valor |
|------------|-------|
| Total de state.json | **exatamente 20** |
| Tamanho minimo por arquivo | **>= 2KB** (2048 bytes) |
| Tamanho maximo por arquivo | **<= 10KB** (10240 bytes) |
| State.json com `metricas_acumuladas.model_selector` populado | **>= 5** (na pratica: 10 — perfis P1..P10) |
| State.json com `metricas_acumuladas.model_selector` ausente (lazy) | 5 (perfis L1..L5) |
| State.json com `model_selector.sugestoes_total = 0` | 5 (perfis Z1..Z5) |

Cada `state.json` tem entre **3 e 10 decisoes** em `state.decisoes`
(mock plausivel) para empurrar o tamanho acima de 2KB sem ultrapassar
10KB. Decisoes nao sao consumidas pelo `report.sh` — sao padding util
para refletir o tamanho medio observado em projetos reais.

## Distribuicao por modo (perfis populados P1..P10)

| feat | modelo predominante | sugestoes_total | aceitas | rejeitadas |
|------|---------------------|-----------------|---------|------------|
| feat-01 | haiku | 5 | 4 | 1 |
| feat-02 | sonnet | 6 | 5 | 1 |
| feat-03 | opus | 4 | 3 | 1 |
| feat-04 | manter-atual | 3 | 2 | 1 |
| feat-05 | haiku | 12 | 11 | 1 |
| feat-06 | sonnet | 10 | 8 | 2 |
| feat-07 | haiku (tie-break haiku=3,sonnet=3) | 6 | 5 | 1 |
| feat-08 | (sem dados) (bag zero, total>0) | 5 | 3 | 2 |
| feat-09 | haiku (haiku=4,sonnet=2) | 6 | 6 | 0 |
| feat-10 | opus (opus=3,sonnet=2) | 5 | 4 | 1 |

## Como regenerar

```sh
sh tests/fixtures/state-dirs-20/regen.sh   # script idempotente
```

Apos regerar, validar invariante de tamanho:

```sh
find tests/fixtures/state-dirs-20 -name state.json -exec wc -c {} \; \
  | awk '{if($1<2048||$1>10240){print "FAIL "$0;exit 1}} END{print "OK"}'
```

## Uso pelos testes

- `tests/cstk/test_report_performance.sh` (4.4.3): roda
  `sh report.sh <todos os 20>` 5 vezes; mediana < 500ms
- `tests/cstk/test_report_without_jq.sh` (4.4.1): mascara `jq` via
  PATH minimizado e exige `diff exit-0` byte-identical sobre a porcao
  tabela (Ref CHK012/CHK013/CHK014)
- `tests/cstk/test_report_jq_confinement.sh` (4.4.2): nao consome a
  fixture, mas referencia este README como criterio de aceitacao
