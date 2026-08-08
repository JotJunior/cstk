# Fixtures: tasks-md/

Fixtures de entrada para testes de `plugins/cstk/skills/review-task/scripts/metrics.sh`.
Cada arquivo exercita um cenario especifico — os valores esperados estao
documentados no proprio fixture (secao final "Contagem esperada").

| Fixture | Cenario | Alvo de teste |
|---------|---------|---------------|
| `empty.md` | arquivo sem checkboxes | caminho "Nenhuma subtarefa" (exit 0, sem erro) |
| `only-done.md` | so `[x]` | pct_done=100, zero pendentes |
| `only-pending.md` | so `[ ]` — **reproduz bug historico** | sem `syntax error` em stderr |
| `mixed.md` | `[ ] [x] [~] [!]` em proporcoes conhecidas | contagens exatas por status |
| `with-phases-tasks.md` | estrutura realista (3 fases, 6 tarefas) | contagem de FASES/TAREFAS/criticidade |

## Como usar

No test_metrics.sh, dentro de uma funcao scenario:

```sh
scenario_foo() {
    fixture "tasks-md" || return 1
    # Agora $TMPDIR_TEST/empty.md, .../only-done.md etc. estao disponiveis
    assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/empty.md" || return 1
    assert_stdout_contains "Nenhuma subtarefa" || return 1
}
```

Nota: a helper `fixture` copia o CONTEUDO de `tests/fixtures/tasks-md/.` para
`$TMPDIR_TEST/`, entao todos os arquivos acima ficam no raiz do tmpdir.
Este README tambem e copiado mas metrics.sh ignora arquivos que nao sao o
alvo passado na linha de comando.
