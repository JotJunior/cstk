# Quickstart: fix-validate-stderr-noise

Cenarios end-to-end que validam a feature apos implementacao.

## Scenario 1: Stderr limpo em docs validos (caso motivador)

1. A partir da raiz do repositorio, executar:
   `sh global/skills/validate-docs-rendered/scripts/validate.sh tests/fixtures/docs-site/valid 2>/tmp/stderr.out`
2. Inspecionar `/tmp/stderr.out`.
3. **Expected**:
   - Arquivo vazio OU contem apenas mensagens de logica intencional do
     script (nenhuma linha comecando com `/.../validate.sh: line N: [: `).
   - Especificamente: `grep -c "integer expression expected" /tmp/stderr.out`
     retorna 0.

## Scenario 2: Suite completa continua verde

1. Executar `./tests/run.sh`.
2. **Expected**:
   - Saida final `# PASS: X  FAIL: 0  ERROR: 0  ORPHANS: 0  TIME: Ns`
     com X = 44 + N novos scenarios desta feature (minimo 1, provavelmente 1).
   - Exit code 0.

## Scenario 3: Regressao detecta retorno do bug

1. Reverter UMA das duas ocorrencias do fix em `validate.sh` (ex: linha 244
   de `ERRORS=$(...) || ERRORS=0` de volta para `ERRORS=$(... || printf '0')`).
2. Executar `./tests/run.sh validate`.
3. **Expected**:
   - `not ok` em `scenario_stderr_limpo_em_docs_validos` com bloco YAML
     mostrando que stderr capturado contem "integer expression expected".
   - Exit 1.
4. Restaurar o fix.
5. Executar `./tests/run.sh validate` novamente.
6. **Expected**: todos scenarios de test_validate.sh passam, exit 0.

## Scenario 4: Contrato externo preservado

1. Executar `sh global/skills/validate-docs-rendered/scripts/validate.sh tests/fixtures/docs-site/broken-mermaid`.
2. **Expected**:
   - Exit code 1 (houve ERROs).
   - stdout contem `### Findings` + linhas `| ... | ERRO | Mermaid | ...`.
   - stdout contem `- Corrigir 2 ERRO(s) antes de commitar`.
   - Ou seja, comportamento externo e **identico** ao pre-fix — a mudanca
     afeta apenas stderr (e, como efeito colateral positivo, a tabela de
     Resumo no stdout deixa de mostrar `"0\n0"` em linhas poluidas).

## Scenario 5: Todas as 4 fixtures — stderr limpo

1. Para cada fixture em `tests/fixtures/docs-site/{valid,broken-mermaid,broken-link,broken-frontmatter}`:

   ```sh
   sh global/skills/validate-docs-rendered/scripts/validate.sh <fixture> 2>/tmp/stderr.out
   grep -c "integer expression expected" /tmp/stderr.out
   ```

2. **Expected**: em todos os 4 casos, o grep retorna 0. SC-002 da spec
   validado quantitativamente.
