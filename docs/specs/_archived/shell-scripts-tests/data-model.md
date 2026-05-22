# Data Model: shell-scripts-tests

Este plano nao envolve banco de dados nem schema persistente. As "entidades"
abaixo sao artefatos conceituais que aparecem no sistema de arquivos; o
modelo existe para fixar vocabulario e formato.

## Entity: Test Case

Um arquivo `test_*.sh` que exercita um unico script sob teste.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| file_path | path | `tests/test_<script>.sh` | Convencao de nome casa com o script-alvo |
| target_script | path | absoluto a partir do repo | Script que este teste exercita |
| scenarios | list\<Scenario\> | >=1 | Definidos como funcoes `scenario_*` dentro do arquivo |

### Relationships

- **Test Case** 1:1 **Target Script** (um arquivo de teste cobre um unico script;
  multiplos cenarios para o mesmo script ficam dentro do mesmo arquivo).
- **Test Case** 1:N **Scenarios** (funcoes internas ao arquivo).

## Entity: Scenario

Um cenario individual dentro de um test case — uma combinacao de (entrada,
expectativa).

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| name | string | snake_case, prefixo `scenario_` | Ex: `scenario_tasks_md_vazio` |
| setup | shell function | opcional | Prepara fixtures em `$TMPDIR_TEST` |
| invocation | command | obrigatorio | O comando sob teste (ex: `sh "$SCRIPT" arg1`) |
| expected_exit | int | 0..255 | Exit code esperado |
| expected_stdout_match | regex ou literal | opcional | Pattern ou substring em stdout |
| expected_stderr_match | regex ou literal | opcional | Pattern ou substring em stderr |
| expected_no_side_effect | bool | default true | Se true, verifica que nada foi criado fora de `$TMPDIR_TEST` |

### State Transitions

Cada scenario passa por:

```
pending → running → (pass | fail | error)
```

- **pass**: exit_code casou, matches bateram, sem side effect proibido.
- **fail**: alguma expectativa nao bateu — reportada com contexto completo.
- **error**: setup falhou ou o teste crashou antes de produzir veredito
  (distinto de fail para nao confundir bug do teste com bug do script).

## Entity: Fixture

Arquivos de entrada versionados que os cenarios copiam para `$TMPDIR_TEST`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| path | path | `tests/fixtures/<topic>/...` | Organizados por topico, nao por teste |
| purpose | string | comentario no arquivo ou README | Para que serve este fixture |
| owned_by | list\<Test Case\> | informativo | Lista de testes que usam |

### Relationships

- **Fixture** N:M **Scenario** (fixtures sao reutilizaveis; um scenario pode
  compor multiplas fixtures).

## Entity: Run Report

Saida consolidada de uma execucao da suite. Nao persiste em disco por padrao
(so stdout/stderr); pode ser redirecionada para arquivo pelo usuario.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| total_scripts | int | >=0 | Scripts cobertos nesta run |
| total_scenarios | int | >=0 | Soma de scenarios executados |
| passed | int | >=0 | |
| failed | int | >=0 | |
| errored | int | >=0 | |
| orphans | list\<path\> | pode ser vazia | Scripts sem `test_*.sh` correspondente |
| total_time_seconds | float | | Medido via `date +%s` antes/depois |
| exit_code | int | 0 ou 1 | 0 sse `failed==0 AND errored==0` (orphans nao bloqueiam) |
