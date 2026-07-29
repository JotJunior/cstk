# Contract: requirement-coverage.sh CLI

> [PROPOSTA — a validar na implementacao] Interface NOVA desenhada por
> esta feature; nao descreve script existente.

**Script**: `global/skills/checklist/scripts/requirement-coverage.sh`
**Instalado em**: `~/.claude/skills/checklist/scripts/requirement-coverage.sh`
**Padrao seguido**: `validate-sdd.sh` / `validate-tasks-template.sh`
(`FINDING|` + `RESULT|`, exit 0/1/2, POSIX sh `set -eu`)

## Uso

```
requirement-coverage.sh FILE [--min-match N]
```

| Argumento | Obrigatorio | Descricao |
|-----------|-------------|-----------|
| `FILE` | sim | path de um `spec.md` no formato do template `feature-spec.md` |
| `--min-match N` | nao | minimo de termos-chave distintos do requisito que devem aparecer no corpus de cenarios para considera-lo coberto pela heuristica (default: `2`; inteiro >= 1) |

## Algoritmo (normativo)

1. Extrair IDs + enunciados: linhas `- **FR-NNN**:` sob a secao
   `### Functional Requirements` (enunciado = texto do item, incluindo
   linhas de continuacao ate o proximo item ou fim de secao).
2. Montar corpus de cenarios: texto de todos os blocos
   `**Acceptance Scenarios**:` (todas as User Stories) + secao
   `### Edge Cases`, normalizado (lowercase, pontuacao removida).
3. Para cada FR, na ordem:
   a. **Fast-path**: corpus cita `FR-NNN` literal → coberto.
   b. **Heuristica** (spec FR-005): termos-chave = tokens do enunciado
      com comprimento >= 5, normalizados, menos stoplist embutida
      (termos genericos pt/en — ex.: `sistema`, `system`, `deve`,
      `usuario`, `campo`, `formato`, `arquivo`, `script`, `feature`;
      lista final calibrada na implementacao contra as specs reais do
      repo). Coberto se >= `min(--min-match, total_de_termos)` termos
      distintos aparecem no corpus (piso 1 quando o enunciado tem
      menos termos elegiveis que `--min-match`).
   c. Nao coberto → `FINDING|error|fr-no-scenario|...`.

## Saida (stdout)

```
FINDING|error|fr-no-scenario|FR-003 sem cenario associado — adicionar Acceptance Scenario ou Edge Case cobrindo os termos centrais de FR-003
RESULT|<FILE>|requirements=<T>|covered=<C>|errors=<N>
```

- Uma linha `FINDING` por requisito sem cobertura (ID exato — spec
  FR-003; mensagem inclui fix acionavel — SC-002).
- `RESULT` sempre emitido: `requirements` = FRs declarados, `covered`
  = cobertos, `errors` = gaps.
- Spec sem nenhum FR: `RESULT|<FILE>|requirements=0|covered=0|errors=0`,
  exit 0 (spec FR-004).

## Exit codes

| Exit | Significado |
|------|-------------|
| 0 | zero gaps (inclui caso degenerado sem FRs) |
| 1 | >= 1 requisito sem cenario associado |
| 2 | uso incorreto / FILE inexistente / `--min-match` invalido |

## Invocadores (spec FR-002)

- Skill `specify` — ETAPA 4 (VALIDACAO), antes de reportar sucesso.
- Skill `checklist` — antes de reportar conclusao bem-sucedida.
- Registro em execucao autonoma: `state-ondas.sh record-skill --skill
  requirement-coverage --kind gate` (script deterministico, nao tool
  Skill).

## Teste (spec FR-017)

`tests/test_requirement-coverage.sh` — cenarios minimos: gap unico
citando ID exato; spec integralmente coberta (exit 0); spec sem FRs
(exit 0 trivial); fast-path por citacao literal de ID; cobertura via
heuristica sem ID; `--min-match` invalido (exit 2); FILE ausente
(exit 2); fixture real do repo (esta propria spec).
