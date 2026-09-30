# Contract: `scripts/measure-orchestrator-prompts.sh` [implementado — execute-task 2.1]

Script de desenvolvimento (fora do catalogo instalado), POSIX sh.
Dependencias: `git`, `wc`, `awk`, `sort`. `sqlite3` OPCIONAL (so para a secao
observada; ausente => "indisponivel") — Principio II, carve-out 1.1.0,
confinado a este unico arquivo.

## Uso

```
measure-orchestrator-prompts.sh --ref <git-ref> [--observed] [--db PATH]
```

- `--ref`: commit a medir (baseline: `9f97e994d5cde46d1447744c68c9def8da14e6e3`).
  Le os arquivos via `git show <ref>:<path>` — nunca da arvore de trabalho.
- `--observed`: inclui a secao de consumo observado (knowledge.db).
- `--db`: default `$HOME/.claude/cstk/knowledge.db`, aberto com
  `sqlite3 -readonly`.
- `--since DATA` / `--until DATA` (implementado em execute-task 2.1): janela
  `started_at >= since` e `started_at < until`. Sem `--until`, o default e a
  data do commit de `--ref` em UTC (ondas anteriores ao commit — usado no
  baseline); para o periodo "depois", o operador passa `--since` com a data
  do release. Sem `--since`, sem limite inferior.
- Contagem de tokens: se `ORCH_TOKEN_COUNTER` estiver definida, e um comando
  que recebe texto em stdin e imprime um inteiro; o relatorio registra o
  comando usado. Se indefinida => coluna "tokens" = `indisponivel` e o
  relatorio declara "gate de FR-018 avaliado em bytes (dec-010)".
  NUNCA derivar tokens de bytes.

## Saida (Markdown em stdout)

1. Cabecalho: ref medido (sha completo), data UTC, metodo de tokens.
2. Tabela prompt-base: `orchestrator | bytes | tokens`.
3. Tabela por fase: `orchestrator | phase | base_bytes | ref_bytes |
   loaded_bytes (base+ref) | tokens`. No baseline (sem referencias),
   `ref_bytes = 0` e `loaded_bytes = base_bytes` para toda fase.
4. `--observed`: por fase (`waves.stages`) e por grupo de execucao
   (`execution_id` `feat-*` vs `*agente-00c*`): `n` de ondas, cobertura por
   coluna (`otel_total_tokens`, `otel_subagent_cache_creation_tokens`,
   `otel_main_cache_creation_tokens`), mediana so sobre linhas nao-nulas.
   Janela temporal explicita (`--since`/`--until` derivados do ref:
   baseline = ondas antes da data do release; after = ondas depois). Coluna
   sem linha => `indisponivel`. Nota fixa: "cache_creation inclui resultados
   de tool e turnos; nao isola o prompt-base".

Relatorios gerados sao salvos (pelo operador/tarefa) em
`docs/specs/orchestrator-slim/measurements/baseline.md` e `after.md`.

## Entrada para SQL (gate owasp-security, achado S3)

Unicos valores interpolados em SQL sao as datas da janela; MUST casar
`^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)?$` antes do uso,
senao exit 2. Nenhum outro argumento do usuario entra em SQL.

## Exit codes

0 sucesso; 1 erro (ref inexistente, arquivo ausente no ref); 2 uso incorreto.
Ausencia de `sqlite3`/db com `--observed` NAO e erro: secao sai
`indisponivel`.
