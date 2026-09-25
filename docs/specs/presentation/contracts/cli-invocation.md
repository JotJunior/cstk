# Contract: Invocacao de `/presentation` e dos scripts

Convencao comum: dados em stdout, diagnostico em stderr. Exit `0`
sucesso, `1` violacao/erro de conteudo, `2` uso incorreto ou arquivo de
entrada inexistente.

## `/presentation`

```
/presentation [--docs <dir>] [--out <dir>] [--lang pt-BR|en] [--render-only] [--full]
```

| Flag | Default | Efeito |
|------|---------|--------|
| `--docs` | `docs` | raiz das docs a varrer |
| `--out` | `docs/presentation` | destino de `story.md`, `inventory.tsv`, `index.html` |
| `--lang` | idioma do briefing (pt-BR se ausente) | idioma do texto e dos rotulos |
| `--render-only` | off | so valida e renderiza; nao toca `story.md` nem `inventory.tsv` |
| `--full` | off | ignora o diff e reescreve a story inteira |

## `scan-project-docs.sh`

```
scan-project-docs.sh inventory [--docs DIR]
scan-project-docs.sh diff --old FILE --new FILE
```

- `inventory`: imprime o inventario (formato em `data-model.md`). Exit 2
  se `DIR` nao existe. Diretorio sem briefing, constitution ou specs nao
  e erro: os registros correspondentes so nao aparecem (`totals` sempre
  aparece).
- `diff`: imprime `estado<TAB>tipo<TAB>chave` para `briefing`,
  `constitution` e cada `spec`, ordenado por tipo e chave. Exit 2 se um
  dos arquivos nao existe.

## `validate-presentation.sh`

```
validate-presentation.sh --story FILE --inventory FILE [--root DIR]
```

- `--root`: base para resolver `@source` (default: diretorio atual).
- Violacoes em stderr, uma por linha, `FILE:LINHA: mensagem`; ultima
  linha em stdout: `RESULT|slides=N|specs=C/T|errors=E`.
- Exit 0 sem violacao, 1 com violacao, 2 uso.

## `render-presentation.sh`

```
render-presentation.sh --story FILE --inventory FILE --out FILE [--templates DIR]
```

- `--templates`: default `<dir-do-script>/../templates`; precisa de
  `presentation.html`, `theme.css`, `deck.js`.
- Escreve em arquivo temporario e move para `--out` (nunca deixa HTML
  parcial). Imprime `RENDERED|<out>|slides=N` em stdout.
- Nao valida semantica (papel do validador); falha com exit 1 apenas se
  a story nao tem frontmatter ou nenhum slide.
