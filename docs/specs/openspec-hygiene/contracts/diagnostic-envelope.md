# Contract: DiagnosticEnvelope (`_diag.sh`)

> [PROPOSTA — a validar na implementacao] Interface NOVA desenhada por
> esta feature; nao descreve helper existente.

**Helper**: `global/skills/agente-00c-runtime/scripts/_diag.sh`
(sourceable, padrao identico a `_log.sh`/`_hash.sh` — NAO executavel
diretamente).

## API

```sh
. "$(dirname -- "$0")/_diag.sh"
diag_emit <severity> <code> <message> <fix>
```

| Parametro | Constraints |
|-----------|-------------|
| `severity` | `error` \| `warning` |
| `code` | kebab-case ASCII, estavel por (script, condicao de falha), unico dentro do script (spec FR-014) |
| `message` | texto legivel (pt-br permitido); `\|` interno substituido por `/` pelo helper |
| `fix` | instrucao acionavel de proximo passo; MUST NOT repetir `message` (spec FR-013); `\|` interno substituido por `/` |

## Saida (stderr, 1 linha)

```
DIAG|<severity>|<code>|<message>|<fix>
```

Consumo programatico: `grep '^DIAG|' | cut -d'|' -f2-5` — sem parsing
de texto livre (spec FR-014), sem `jq` (spec FR-016, Constitution II).

## Semantica de emissao

- **ADITIVA**: o script migrado MANTEM sua mensagem de erro legada e
  ACRESCENTA a linha `DIAG|` — testes existentes que verificam texto
  literal nao quebram (spec FR-015, SC-006).
- **Fail-fast**: apenas o primeiro erro fatal da invocacao emite
  envelope (Edge Case da spec — sem agregacao de achados).
- Falha do proprio helper nunca mascara o erro original (best-effort:
  se `diag_emit` falhar, a mensagem legada ja saiu).

## Escopo-piloto da migracao (spec FR-012/FR-015; research.md Decision 3)

Exatamente 4 scripts nesta rodada — codes iniciais propostos:

| Script | Condicao de falha | `code` |
|--------|-------------------|--------|
| `state-rw.sh` | state.json ausente | `state-not-found` |
| `state-rw.sh` | JSON invalido / parse | `state-invalid-json` |
| `state-rw.sh` | sha256-verify divergente | `hash-mismatch` |
| `state-lock.sh` | lock ja detido (contention) | `lock-contention` |
| `state-lock.sh` | lock stale detectado | `lock-stale` |
| `state-ondas.sh` | `start` com onda ja aberta | `wave-already-open` |
| `state-ondas.sh` | `end` sem onda aberta | `no-open-wave` |
| `bloqueios.sh` | respond a bloqueio inexistente | `bloqueio-not-found` |

Lista de condicoes por script sera confirmada na implementacao lendo
os paths de erro reais de cada um; codes acima sao a convencao — cada
condicao adicional encontrada ganha code proprio distinto (spec
FR-014). Scripts fora desta tabela: formato de erro atual INALTERADO
(spec FR-015, SC-006).

## Teste (spec FR-017)

- `tests/test__diag.sh` (novo — precedente de naming: `_hash.sh` →
  `test__diag.sh`): emissao dos 4 campos, escape de `|`, severity
  invalida, fix igual a message rejeitado ou avisado.
- Testes existentes dos 4 scripts-piloto: estender com assercao de que
  a linha `DIAG|` aparece em stderr nas condicoes da tabela E que a
  mensagem legada permanece (protecao SC-006).
