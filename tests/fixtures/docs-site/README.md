# Fixtures: docs-site/

Fixtures de entrada para testes de `plugins/cstk/skills/validate-docs-rendered/scripts/validate.sh`.
Cada subdiretorio isola UM tipo de problema (ou zero, no caso de `valid/`)
para que o teste possa afirmar exatamente qual checagem disparou o erro.

| Fixture | Conteudo | Esperado |
|---------|----------|----------|
| `valid/` | `doc.md` + `target.md` — todos os checks passam | exit 0, stdout "0 ERROs", sem mensagens de ERRO |
| `broken-mermaid/` | `sequenceDiagram` com `Alice`/`Bob` nao declarados | exit 1, ERRO em Mermaid |
| `broken-link/` | link para `./nao-existe.md` | exit 1, ERRO "Arquivo nao encontrado" |
| `broken-frontmatter/` | `---` aberto sem fechar | exit 1, ERRO "Abre com `---` mas nao fecha" |

## Como usar

No test_validate.sh:

```sh
scenario_docs_validos() {
    fixture "docs-site/valid" || return 1
    assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST" || return 1
}

scenario_mermaid_quebrado() {
    fixture "docs-site/broken-mermaid" || return 1
    assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST" || return 1
    assert_stdout_contains "Mermaid" || return 1
}
```

## Principio de um-problema-por-fixture

Cada fixture contem EXATAMENTE UM tipo de erro (ou zero). Isso garante
que o teste pode afirmar especificamente qual checagem disparou. Fixtures
multi-erro sao ambiguos — se o script reporta "2 ERROs", o teste nao sabe
se os dois eram do tipo esperado ou se faltou um e sobrou outro.
