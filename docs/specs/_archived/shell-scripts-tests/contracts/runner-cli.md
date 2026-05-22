# Contract: Test Runner CLI

O entry point unico da suite e `tests/run.sh`, invocavel da raiz do repositorio.

## Sinopse

```
tests/run.sh [OPTIONS] [PATTERN]
```

## Opcoes

| Flag | Default | Descricao |
|------|---------|-----------|
| `-v`, `--verbose` | off | Imprime stdout/stderr de cada scenario mesmo em pass |
| `--check-coverage` | off | Apenas lista scripts orfaos (sem `test_*.sh`); exit 0 se zero orfaos, 1 caso contrario |
| `--list` | off | Apenas lista test cases descobertos, sem executar |
| `-h`, `--help` | — | Imprime esta sinopse e sai 0 |

## Argumentos Posicionais

- `PATTERN` (opcional): substring ou glob aplicado sobre o caminho dos
  test cases para executar subconjunto. Ex: `tests/run.sh metrics` executa
  apenas `tests/test_metrics.sh`.

## Saida (stdout)

Formato TAP-like:

```
1..N
ok 1 - test_metrics.sh :: scenario_tasks_md_vazio
not ok 2 - test_metrics.sh :: scenario_apenas_concluidas
  ---
  command: sh global/skills/review-task/scripts/metrics.sh /tmp/xyz/tasks.md
  exit_code: 2
  expected_exit: 0
  stdout: |
    (conteudo capturado)
  stderr: |
    line 34: syntax error
  ---
ok 3 - test_scaffold.sh :: scenario_dry_run
...

# PASS: 18  FAIL: 1  ERROR: 0  ORPHANS: 0  TIME: 4s
```

Em modo `--check-coverage`:

```
Scripts sem teste correspondente:
  - global/skills/new-skill/scripts/foo.sh

Scripts com teste:
  - global/skills/review-task/scripts/metrics.sh → tests/test_metrics.sh
  - global/skills/create-tasks/scripts/next-task-id.sh → tests/test_next-task-id.sh
  ...
```

## Exit Codes

| Code | Significado |
|------|-------------|
| 0 | Todos os scenarios passaram (orphans emitem warning mas nao bloqueiam) |
| 1 | Pelo menos um scenario falhou ou deu erro |
| 2 | Invocacao invalida (flag desconhecida, PATTERN que nao casa nada) |

## Contrato Interno de um Test Case (`test_*.sh`)

Cada arquivo `tests/test_<script>.sh`:

1. Faz `source tests/lib/harness.sh` logo no inicio (helpers de assercao).
2. Define variavel `SCRIPT` apontando para o script-alvo absoluto.
3. Define pelo menos uma funcao `scenario_<nome>`.
4. Chama `run_all_scenarios` ao final, que descobre as funcoes `scenario_*`
   no escopo atual e executa cada uma em subshell com `$TMPDIR_TEST` proprio.

Nenhum test case deve: rodar `cd` fora do `$TMPDIR_TEST`, escrever fora dele,
depender de rede, ou depender de outro test case.

## Helpers de Assercao (`tests/lib/harness.sh`)

| Funcao | Assinatura | Semantica |
|--------|-----------|-----------|
| `assert_exit` | `assert_exit EXPECTED CMD...` | Roda CMD; falha se exit difere |
| `assert_stdout_contains` | `assert_stdout_contains SUBSTRING` | Testa ultima captura de stdout |
| `assert_stdout_match` | `assert_stdout_match REGEX` | Regex sobre ultima captura |
| `assert_stderr_contains` | `assert_stderr_contains SUBSTRING` | Idem para stderr |
| `assert_no_side_effect` | `assert_no_side_effect` | Falha se houver arquivo modificado fora de `$TMPDIR_TEST` |
| `fixture` | `fixture NAME` | Copia `tests/fixtures/NAME/*` para `$TMPDIR_TEST/` |

Helpers retornam 0 em sucesso, 1 em falha. O harness captura a falha e
converte em `not ok` com contexto (comando, stdout, stderr, exit).
