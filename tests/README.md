# Suite de Testes para Scripts Shell

Suite automatizada que valida o comportamento dos scripts POSIX em
`plugins/cstk/skills/**/scripts/`. Nasceu do bug historico em `metrics.sh` e
segue o principio de "nao commita sem teste para script novo".

## Quickstart

```bash
# Rodar toda a suite
./tests/run.sh

# Rodar apenas um subconjunto (filtro por substring no path)
./tests/run.sh metrics
./tests/run.sh next

# Suite rapida (pula a allowlist de tests lentos — ~1/3 do tempo)
./tests/run.sh --fast

# So os tests lentos (integration/e2e/binario/muitos-scenarios)
./tests/run.sh --slow

# Listar scenarios sem executar (respeita PATTERN e --fast/--slow)
./tests/run.sh --list

# Distribuicao de scenarios por arquivo (desc) + total
./tests/run.sh --stats

# Verificar cobertura (scripts sem teste, tests sem script)
./tests/run.sh --check-coverage

# Ajuda completa
./tests/run.sh --help
```

**Tempo tipico**: alguns minutos para a suite completa (~1100 scenarios; o
numero exato e nao-deterministico porque alguns tests sao gerados sob demanda
— rode `./tests/run.sh --list | grep -c "::"` para o total atual, ou
`./tests/run.sh --stats` para a quebra por arquivo). A contagem de **skills**
(e a listagem delas no README) e guardada contra drift por
`tests/test_doc-counts.sh`.

## Suite rapida vs completa (`--fast` / `--slow`)

No dev-loop, `--fast` pula a **allowlist de tests lentos** e roda em ~1/3 do
tempo. A allowlist vive em `run.sh::_is_slow_test` e foi **derivada de medicao**
(nao de categoria): cada `test_*.sh` foi cronometrado e os com tempo de parede
> ~5s entraram. Em 2026-05-24 eram 11 (somando ~177s de ~260s da suite):

| Test | ~Tempo | Por que e lento |
|------|--------|-----------------|
| `test_recall.sh` | ~82s | sqlite/FTS, 66 scenarios |
| `test_session.sh` | ~18s | worktree/git, 60 scenarios |
| `test_model-routing.sh` | ~16s | 99 scenarios |
| `test_drift.sh` | ~13s | manifest/hash diffing |
| `test_self-update.sh` | ~11s | tarballs + binario cstk |
| `test_quickstart-e2e.sh` | ~9s | e2e lifecycle da CLI |
| `test_00c-bootstrap.sh` | ~8s | bootstrap do orquestrador |
| `test_update-extra-kinds.sh` | ~6s | install+manifest+doctor |
| `test_e2e_model_routing.sh` | ~5s | e2e do pipeline agente-00c |
| `test_update.sh` | ~5s | update.sh + doctor |
| `test_model_selector_corpus.sh` | ~5s | corpus de 45 entradas |

> **Importante**: `--fast` e atalho de dev-loop, NAO substitui a suite completa.
> O gate de release (`.github/workflows/release.yml`) roda `./tests/run.sh`
> inteiro. Reavalie a allowlist se o perfil de tempo mudar:
> `for f in tests/test_*.sh tests/cstk/test_*.sh; do \`
> `  s=$(date +%s); sh "$f" >/dev/null 2>&1; printf '%5ds  %s\n' "$(($(date +%s)-s))" "$f"; done | sort -rn`

`--fast` e `--slow` sao mutuamente exclusivos (exit 2) e compoem com PATTERN e
com `--list`/`--stats`/run. `--check-coverage` ignora o filtro de velocidade
(cobertura sempre enxerga todos os tests).

## Arquitetura

```
tests/
├── run.sh                   # Entry point — parse de args, dispatch, sumario
├── lib/
│   └── harness.sh           # Biblioteca de assercoes (source'ada pelos tests)
├── fixtures/                # Dados de entrada versionados
│   ├── tasks-md/            # Para metrics.sh + next-task-id.sh
│   ├── docs-site/           # Para validate.sh
│   └── _harness-smoke/      # Fixture minima usada pelo self-test do harness
├── test_harness.sh          # Self-test dos assertion helpers (interno)
├── test_smoke.sh            # Smoke test de descoberta (interno)
├── test_metrics.sh          # Cobre review-task/metrics.sh
├── test_next-task-id.sh     # Cobre create-tasks/next-task-id.sh
├── test_scaffold.sh         # Cobre initialize-docs/scaffold.sh
└── test_validate.sh         # Cobre validate-docs-rendered/validate.sh
```

## Saida (formato TAP-like)

```
# test_metrics.sh
ok 1 - test_metrics.sh :: scenario_apenas_concluidas
ok 2 - test_metrics.sh :: scenario_apenas_pendentes
not ok 3 - test_metrics.sh :: scenario_mixed
  ---
  assert: assert_exit
  message: esperado exit=0, obtido exit=2
  command: sh /.../metrics.sh /tmp/shell-tests.XXXXXX/mixed.md
  exit_code: 2
  stdout: |
    (conteudo capturado)
  stderr: |
    (conteudo capturado)
  ---
...

# PASS: 42  FAIL: 1  ERROR: 0  ORPHANS: 0  TIME: 4s
```

Em falha, o bloco YAML-ish contem tudo para reproduzir manualmente:
copie o `command:` e execute — vai ver o mesmo stdout/stderr/exit.

## Exit codes do runner

| Code | Significado |
|------|-------------|
| 0 | Todos PASS (orfaos no modo normal sao warning, nao bloqueiam) |
| 1 | Pelo menos um FAIL ou ERROR (ou `--check-coverage` com orfao) |
| 2 | Invocacao invalida (flag desconhecida, PATTERN sem match) |

## Status trichotomico

| Status | Quando |
|--------|--------|
| **PASS** | Scenario executou e todas as assercoes passaram |
| **FAIL** | Scenario executou mas o script sob teste comportou-se diferente do esperado |
| **ERROR** | O harness ou o ambiente impediu a avaliacao (ex: `mktemp` ausente, setup crashou) |

Exit 0 requer `FAIL=0 AND ERROR=0`. ERRORs nao sao mascarados como FAILs —
permitem diagnosticar bug-do-teste vs bug-do-script-sob-teste.

## Adicionar teste para script novo

1. Script-alvo existe em `plugins/cstk/skills/<skill>/scripts/<nome>.sh`.
2. Criar `tests/test_<nome>.sh` (convencao estrita — `--check-coverage`
   depende dela).
3. Estrutura minima:

   ```sh
   #!/bin/sh
   # test_<nome>.sh — cobre plugins/cstk/skills/<skill>/scripts/<nome>.sh

   TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
   REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

   . "$TESTS_ROOT/lib/harness.sh"

   SCRIPT="$REPO_ROOT/plugins/cstk/skills/<skill>/scripts/<nome>.sh"

   scenario_happy_path() {
       assert_exit 0 sh "$SCRIPT" arg1 arg2 || return 1
       assert_stdout_contains "esperado" || return 1
   }

   scenario_sem_argumento() {
       assert_exit 2 sh "$SCRIPT" || return 1
       assert_stderr_contains "Uso:" || return 1
   }

   run_all_scenarios
   ```

4. NAO usar `set -eu` no test file — o harness sinaliza via return
   codes, e `set -e` mataria scenarios que testam condicoes FAIL
   deliberadas.

5. Rodar `./tests/run.sh <nome>` para verificar que so o teste novo
   executa. Depois `./tests/run.sh --check-coverage` deve reportar
   "Cobertura completa: zero orfaos."

## Helpers do harness

Definidos em `tests/lib/harness.sh`, disponiveis apos `. harness.sh`:

### Gestao de tmpdir

| Funcao | Descricao |
|--------|-----------|
| `mktemp_test` | Cria `$TMPDIR_TEST` (mktemp -d) + trap EXIT/INT/TERM. Automatico por scenario via `run_all_scenarios`. |

### Captura

| Funcao | Descricao |
|--------|-----------|
| `capture CMD [ARGS...]` | Executa CMD, preenche `_CAPTURED_STDOUT`, `_CAPTURED_STDERR`, `_CAPTURED_EXIT`. |

### Assercoes

| Funcao | Uso | Retorno |
|--------|-----|---------|
| `assert_exit EXPECTED CMD...` | Executa CMD, compara exit | 0 PASS / 1 FAIL / 2 ERROR |
| `assert_stdout_contains SUBSTRING` | Substring em stdout capturado | 0 / 1 |
| `assert_stderr_contains SUBSTRING` | Substring em stderr capturado | 0 / 1 |
| `assert_stdout_match REGEX` | Regex ERE sobre stdout | 0 / 1 |
| `assert_no_side_effect` | Git status inalterado desde inicio do scenario | 0 / 1 |

### Fixtures

| Funcao | Descricao |
|--------|-----------|
| `fixture NAME` | Copia `tests/fixtures/NAME/.` para `$TMPDIR_TEST/` |

### Reportagem de erro

| Funcao | Uso |
|--------|-----|
| `_error CAUSE MESSAGE` | Marca scenario como ERROR (pre-requisito ausente, nao FAIL) |

### Descoberta

| Funcao | Descricao |
|--------|-----------|
| `run_all_scenarios` | Descobre funcoes `scenario_*` no test file (via grep em `$0`) e executa cada uma em subshell isolada com tmpdir proprio |

## Convencoes

- **`set -eu` e proibido em test files.** O harness sinaliza falha via
  return codes explicitos (`|| return 1` apos cada assert). `set -e`
  mataria scenarios que validam FAIL esperado; `set -u` quebra acesso
  defensivo a `_CAPTURED_*` antes da primeira captura.

- **Scenarios retornam 0/1/2.** 0 = PASS, 1 = FAIL, 2 = ERROR. O
  `run_all_scenarios` interpreta e emite a linha TAP correspondente.

- **Fixtures sao read-only.** Nunca modifique fixtures em um scenario —
  elas sao copiadas para `$TMPDIR_TEST` antes de cada uso, opere no
  tmpdir.

- **Zero Bash-isms.** Consti­tution Principio II — POSIX sh puro. Sem
  `[[ ]]`, `local`, `function`, arrays, `<<<`, `$'...'`.

## Fixtures disponiveis

Documentacao detalhada em `tests/fixtures/<grupo>/README.md`:

- [tasks-md/](./fixtures/tasks-md/README.md) — empty, only-done,
  only-pending, mixed, with-phases-tasks
- [ucs/](./fixtures/ucs/README.md) — empty, with-auth, multi-domain
- [docs-site/](./fixtures/docs-site/README.md) — valid, broken-mermaid,
  broken-link, broken-frontmatter

## Troubleshooting

**"nenhum test case casa o padrao: X"** — o PATTERN nao bate nenhum
path de test_*.sh. Veja `./tests/run.sh --list` para lista completa.

**Testes que falham apenas na minha maquina** — geralmente e diferenca
no `/bin/sh` do sistema. A iteracao atual exercita apenas o shell
apontado por `/bin/sh` (macOS: bash em modo POSIX; Debian: dash). Bugs
especificos de bash/zsh/dash estao fora do escopo atual.

**Tmpdir persistiu apos interrupcao** — raro, mas possivel se o
processo foi morto com `kill -9` (que nao dispara traps). Limpe com
`rm -rf /tmp/shell-tests.*`.

## Referencias

- Spec: [`docs/specs/shell-scripts-tests/spec.md`](../docs/specs/_archived/shell-scripts-tests/spec.md)
- Plano: [`docs/specs/shell-scripts-tests/plan.md`](../docs/specs/_archived/shell-scripts-tests/plan.md)
- Contrato do runner: [`docs/specs/shell-scripts-tests/contracts/runner-cli.md`](../docs/specs/_archived/shell-scripts-tests/contracts/runner-cli.md)
- Decisoes tecnicas: [`docs/specs/shell-scripts-tests/research.md`](../docs/specs/_archived/shell-scripts-tests/research.md)
