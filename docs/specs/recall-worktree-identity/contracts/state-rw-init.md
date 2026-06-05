# Contract: `state-rw.sh init` estendido (flags de proveniencia canonica)

**Feature**: `recall-worktree-identity` | **Date**: 2026-06-05
**Script**: `global/skills/agente-00c-runtime/scripts/state-rw.sh` (`_sr_cmd_init`)
**Consumidores**: commands `/feature-00c` e `/agente-00c` (init do state.json)

## Assinatura estendida

```text
state-rw.sh init --state-dir DIR --projeto-alvo-path PATH --descricao TEXT
                 [--execucao-id ID] [--stack-json JSON] [--whitelist-urls JSON]
                 [--short-name NAME --briefing-path P --briefing-sha256 H
                  --constitution-path P --constitution-sha256 H
                  --constitution-version V [--key-aspects JSON-ARRAY]]
                 [--canonical-project NAME]        # NOVO (opcional)
                 [--session-name NAME]             # NOVO (opcional)
```

## Semantica das flags novas

| Flag | Regra |
|------|-------|
| `--canonical-project NAME` | quando nao-vazia, grava `execution.canonical_project = NAME` no JSON inicial. Quando omitida ou vazia, a CHAVE fica AUSENTE (sem `null`). |
| `--session-name NAME` | quando nao-vazia, grava `execution.session_name = NAME`. Quando omitida ou vazia, chave ausente. Valor tratado como dado textual opaco (sem parsing; pode conter unicode/espacos — edge case da spec). |

Validacao:

- Ambas as flags sao validas nos DOIS modos do init (modo projeto e
  modo feature `--short-name`).
- `--session-name` SEM `--canonical-project` e erro de uso (exit 2):
  sessao sem canonico nao tem semantica (data-model §regras de presenca).
- O init NAO valida o conteudo contra git/filesystem — `state-rw.sh`
  permanece CRUD puro (research Decision 3); a deteccao e responsabilidade
  do chamador (contrato abaixo).

## Contrato do chamador (command pai) — deteccao de worktree

Sequencia POSIX no `/feature-00c` e `/agente-00c` ANTES do init (toda falha =
fallback silencioso, flags omitidas — FR-008):

```sh
1. PAP ja realpath-resolvido (fluxo existente).
2. Se [ -f "$PAP/.git" ]   (worktree: .git e ARQUIVO):
   a. COMMON=$(git -C "$PAP" rev-parse --git-common-dir 2>/dev/null) || COMMON=""
   b. normalizar COMMON para absoluto (prefixar "$PAP/" se relativo)
   c. CANONICAL=$(basename "$(dirname "$COMMON")")
   d. WTBASE=$(basename "$PAP")
      se WTBASE comeca com "${CANONICAL}-": SESSION="${WTBASE#"${CANONICAL}"-}"
      senao: SESSION=""
3. Se [ -d "$PAP/.git" ] (projeto raiz): flags omitidas (ou
   --canonical-project "$(basename "$PAP")" — ambos validos por US3 AC2;
   escolha canonica desta feature: OMITIR, mantendo o state minimo).
4. Passar --canonical-project/--session-name ao init somente quando nao-vazios.
```

## Comportamento (cenarios de aceitacao cobertos)

| Given | Then |
|-------|------|
| init com `--canonical-project cstk --session-name minha-feature` | `.execution.canonical_project == "cstk"` e `.execution.session_name == "minha-feature"` no state.json gerado (US3 AC1) |
| init sem as flags (projeto normal) | nenhuma das duas chaves presente; JSON identico ao pre-feature (US3 AC2/AC3, FR-010) |
| init com `--session-name X` sem `--canonical-project` | exit 2, mensagem de uso em stderr |
| `.git` dir / git ausente / rev-parse falha no chamador | chamador omite flags; init segue normal (FR-008 — silencioso) |

## Compatibilidade

- Chamadas existentes (sem as flags novas) permanecem 100% validas — zero
  mudanca de comportamento (FR-010).
- `state-validate.sh` deve aceitar as chaves novas como OPCIONAIS (sem
  exigi-las em states antigos).
- Testes: `tests/test_state-rw.sh` ganha cenarios para as 4 linhas da tabela
  acima (regra de ouro do repo).
