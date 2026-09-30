# Baseline da medicao (antes) — orchestrator-slim

> Artefato versionado da feature (FR-013). Capturado ANTES de qualquer edicao
> dos orquestradores, a partir do commit `9f97e994d5cde46d1447744c68c9def8da14e6e3`.

Comandos usados (na raiz do repositorio):

```sh
sh scripts/measure-orchestrator-prompts.sh --ref 9f97e994d5cde46d1447744c68c9def8da14e6e3 --observed
git show 9f97e994d5cde46d1447744c68c9def8da14e6e3:plugins/cstk/agents/agente-00c-orchestrator.md | wc -c
git show 9f97e994d5cde46d1447744c68c9def8da14e6e3:plugins/cstk/agents/agente-00c-feature-orchestrator.md | wc -c
```

Limitacoes declaradas (FR-017, dec-010): sem contador de tokens offline
(`ORCH_TOKEN_COUNTER` indefinida), a coluna de tokens e `indisponivel` e o gate
de FR-018 e avaliado em bytes. O consumo observado abaixo NAO isola o
prompt-base (nota na propria secao); nenhum numero foi estimado.

# Medicao dos prompts dos orquestradores

- ref: `9f97e994d5cde46d1447744c68c9def8da14e6e3` (`9f97e994d5cde46d1447744c68c9def8da14e6e3`)
- papel: baseline oficial da feature orchestrator-slim (FR-013)
- data UTC da medicao: 2026-09-30T01:32:39Z
- metodo de bytes: `git show <ref>:<path> | wc -c` (bytes do arquivo no commit)
- metodo de tokens: indisponivel (ORCH_TOKEN_COUNTER nao definida; nenhum contador offline no ambiente). Gate de FR-018 avaliado em bytes (dec-010). Tokens NUNCA derivados de bytes.

## Prompt-base

| orchestrator | bytes | tokens |
|---|---|---|
| root | 146014 | indisponivel |
| feature | 104702 | indisponivel |

## Por fase (o que uma onda da fase carrega: prompt-base + 1 referencia)

| orchestrator | phase | base_bytes | ref_bytes | loaded_bytes | tokens |
|---|---|---|---|---|---|
| root | bootstrap | 146014 | 0 | 146014 | indisponivel |
| root | briefing | 146014 | 0 | 146014 | indisponivel |
| root | constitution | 146014 | 0 | 146014 | indisponivel |
| root | roadmap | 146014 | 0 | 146014 | indisponivel |
| root | specify | 146014 | 0 | 146014 | indisponivel |
| root | clarify | 146014 | 0 | 146014 | indisponivel |
| root | plan | 146014 | 0 | 146014 | indisponivel |
| root | checklist | 146014 | 0 | 146014 | indisponivel |
| root | create-tasks | 146014 | 0 | 146014 | indisponivel |
| root | execute-task | 146014 | 0 | 146014 | indisponivel |
| root | converge | 146014 | 0 | 146014 | indisponivel |
| root | review-features | 146014 | 0 | 146014 | indisponivel |
| feature | bootstrap | 104702 | 0 | 104702 | indisponivel |
| feature | specify | 104702 | 0 | 104702 | indisponivel |
| feature | clarify | 104702 | 0 | 104702 | indisponivel |
| feature | plan | 104702 | 0 | 104702 | indisponivel |
| feature | checklist | 104702 | 0 | 104702 | indisponivel |
| feature | create-tasks | 104702 | 0 | 104702 | indisponivel |
| feature | execute-task | 104702 | 0 | 104702 | indisponivel |
| feature | converge | 104702 | 0 | 104702 | indisponivel |
| feature | toolkit-issue | 104702 | 0 | 104702 | indisponivel |

Fases sem arquivo de referencia no ref medido aparecem com `ref_bytes = 0` (no baseline, todas).

## Consumo observado (knowledge.db)

- fonte: tabela `waves` de `~/.claude/cstk/knowledge.db` (somente leitura)
- janela: started_at >= (sem limite) e < 2026-09-30T00:54:22Z
- grupos: `feature-00c` = execution_id `feat-*`; `agente-00c` = execution_id contendo `agente-00c`
- fase = valor exato de `waves.stages`; ondas com varias etapas ou sem etapa ficam em `(multi-etapa ou vazio)`
- cada coluna: `k/n` = ondas com valor / ondas do grupo+fase; mediana so sobre as ondas com valor (n par: media dos dois centrais, truncada); `indisponivel` quando k = 0
- nota: cache_creation inclui resultados de tool e turnos; nao isola o prompt-base

| grupo | fase | n | otel_total_tokens (k/n; mediana) | otel_subagent_cache_creation_tokens (k/n; mediana) | otel_main_cache_creation_tokens (k/n; mediana) |
|---|---|---|---|---|---|
| agente-00c | (multi-etapa ou vazio) | 239 | 20/239; 6355602 | 20/239; 94025 | 1/239; 4103 |
| agente-00c | briefing | 7 | 2/7; 1905255 | 2/7; 26164 | indisponivel (0/7) |
| agente-00c | checklist | 15 | 3/15; 3942312 | 3/15; 72661 | indisponivel (0/15) |
| agente-00c | clarify | 15 | 3/15; 4636299 | 3/15; 51160 | indisponivel (0/15) |
| agente-00c | constitution | 5 | 2/5; 2487718 | 2/5; 55569 | indisponivel (0/5) |
| agente-00c | create-tasks | 15 | 3/15; 6459795 | 3/15; 142235 | indisponivel (0/15) |
| agente-00c | execute-task | 99 | 25/99; 8171965 | 25/99; 94395 | 3/99; 1943 |
| agente-00c | plan | 13 | 5/13; 6317968 | 5/13; 79463 | 1/13; 4724 |
| agente-00c | review-features | 7 | 1/7; 11720424 | 1/7; 118788 | indisponivel (0/7) |
| agente-00c | review-task | 2 | indisponivel (0/2) | indisponivel (0/2) | indisponivel (0/2) |
| agente-00c | specify | 11 | 1/11; 4788870 | 1/11; 218164 | indisponivel (0/11) |
| feature-00c | (multi-etapa ou vazio) | 435 | 223/435; 7300482 | 223/435; 92640 | 32/435; 11328 |
| feature-00c | bugfix | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | bugfix-diagnostico-staging | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | bugfix-staging | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | checklist | 72 | 39/72; 4610005 | 39/72; 65898 | 2/72; 3085 |
| feature-00c | clarify | 97 | 61/97; 2860543 | 61/97; 38860 | 5/97; 3318 |
| feature-00c | converge | 50 | 50/50; 7538217 | 50/50; 90356 | 13/50; 265 |
| feature-00c | create-tasks | 77 | 46/77; 5152303 | 46/77; 78561 | 3/77; 2487 |
| feature-00c | execute-task | 499 | 342/499; 13455670 | 342/499; 128217 | 52/499; 11177 |
| feature-00c | execute-task-3.3 | 1 | 1/1; 2582844 | 1/1; 6162 | indisponivel (0/1) |
| feature-00c | execute-task-3.4 | 1 | 1/1; 17128323 | 1/1; 189792 | indisponivel (0/1) |
| feature-00c | execute-task-diagnostico | 1 | 1/1; 8825681 | 1/1; 104465 | indisponivel (0/1) |
| feature-00c | execute-task-F6.1 | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | execute-task-fase-4 | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | execute-task-fase4 | 2 | indisponivel (0/2) | indisponivel (0/2) | indisponivel (0/2) |
| feature-00c | execute-task-fase5 | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | plan | 113 | 75/113; 11421130 | 75/113; 248528 | 9/113; 11814 |
| feature-00c | review-task | 32 | 21/32; 4016287 | 20/32; 33572 | 3/32; 2218 |
| feature-00c | scan-networks | 1 | 1/1; 31996445 | 1/1; 257647 | indisponivel (0/1) |
| feature-00c | specify | 81 | 47/81; 4558039 | 47/81; 65541 | 5/81; 2132 |
| feature-00c | terminal-close | 1 | 1/1; 899516 | 1/1; 2263 | indisponivel (0/1) |
