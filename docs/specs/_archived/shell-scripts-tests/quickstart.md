# Quickstart: shell-scripts-tests

Cenarios end-to-end que validam a feature. Executados manualmente apos a
implementacao para confirmar que cada user story da spec esta atendida.

## Scenario 1: Happy path — suite roda verde em repo limpo

1. A partir da raiz do repositorio, executar `tests/run.sh`.
2. Observar saida TAP com `ok N` para cada scenario dos 5 scripts.
3. **Expected**:
   - Linha final `# PASS: X  FAIL: 0  ERROR: 0  ORPHANS: 0  TIME: <30s`
   - Exit code 0
   - `git status` limpo (nenhum artefato criado fora de tmpdirs)

## Scenario 2: Regressao do bug historico de metrics.sh

1. Reverter temporariamente o fix de `metrics.sh` (trocar `|| VAR=0` pelo
   antigo `|| printf '0'` em um dos contadores).
2. Executar `tests/run.sh metrics`.
3. **Expected**:
   - Pelo menos um `not ok` apontando scenario de `test_metrics.sh` com
     tasks.md sem matches de algum tipo de checkbox
   - Bloco de contexto mostra `stderr: ... syntax error`
   - Exit code 1
4. Restaurar o fix.
5. Executar `tests/run.sh metrics` novamente.
6. **Expected**: tudo verde, exit 0.

## Scenario 3: Error path — argumento faltando

1. Criar um test case novo ou inspecionar o existente que cobre "script
   invocado sem argumentos".
2. Executar `tests/run.sh` focando apenas nesse caso.
3. **Expected**:
   - `ok` no scenario que verifica "sai com exit !=0 e imprime mensagem de uso"
   - A mensagem capturada em stderr contem "Uso:" (ou equivalente esperado
     pelo contrato do script)

## Scenario 4: Determinismo — duas execucoes consecutivas

1. Rodar `tests/run.sh` duas vezes seguidas, redirecionando para arquivos.
2. Comparar com `diff` ignorando apenas a linha de `TIME:`.
3. **Expected**: diff vazio (exceto tempo total, que pode variar em ms).

## Scenario 5: Isolamento — `git status` limpo

1. Rodar `tests/run.sh`.
2. Rodar `git status --porcelain`.
3. **Expected**: saida vazia (nenhum arquivo criado ou modificado dentro do
   working tree).

## Scenario 6: Cobertura — deteccao de script orfao

1. Criar stub `global/skills/new-skill/scripts/foo.sh` com `#!/bin/sh\nexit 0`.
2. NAO criar `tests/test_foo.sh` correspondente.
3. Executar `tests/run.sh --check-coverage`.
4. **Expected**:
   - Saida lista `global/skills/new-skill/scripts/foo.sh` como orfao
   - Exit code 1 (neste modo `--check-coverage`, orfao bloqueia; na suite
     normal e apenas warning)
5. Remover o stub.

## Scenario 7: Subconjunto por PATTERN

1. Executar `tests/run.sh next-task-id`.
2. **Expected**:
   - Apenas scenarios de `tests/test_next-task-id.sh` rodam
   - Sumario final reflete a contagem reduzida
   - Exit code 0 (se esse test case passa)

## Scenario 8: Tempo total dentro do orcamento

1. Executar `time tests/run.sh` em maquina de desenvolvimento tipica.
2. **Expected**: tempo real < 30s (SC-003).

## Scenario 9: Interrupcao nao vaza tmpdir

1. Executar `tests/run.sh` e pressionar Ctrl+C no meio.
2. Verificar `ls /tmp/` (ou `echo $TMPDIR`).
3. **Expected**: nenhum diretorio `tests-*` orfao sobra no tmpdir do sistema
   (trap EXIT/INT/TERM limpou).
