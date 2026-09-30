# Medicao depois — orchestrator-slim

> Artefato versionado da feature (FR-013). Capturado a partir do commit
> `3f860e047207bb8a64e6e43cac611f6bc6a13dbd` (HEAD apos as FASES 5 e 6; os prompts-base nao mudaram desde entao).
> Comparar com `baseline.md` (commit `9f97e994d5cde46d1447744c68c9def8da14e6e3`).

Comandos usados (na raiz do repositorio):

```sh
sh scripts/measure-orchestrator-prompts.sh --ref HEAD --observed
sh scripts/measure-orchestrator-prompts.sh --ref HEAD
git show HEAD:plugins/cstk/agents/agente-00c-orchestrator.md | wc -c
git show HEAD:plugins/cstk/agents/agente-00c-feature-orchestrator.md | wc -c
```

## Conferencia das metas (FR-018, SC-001, SC-006) — em bytes

| item | baseline | depois | meta | resultado |
|---|---|---|---|---|
| prompt-base de O (`agente-00c-orchestrator.md`) | 146014 | 78553 | <= 87608 | atingida (reducao de 46.2%) |
| prompt-base de F (`agente-00c-feature-orchestrator.md`) | 104702 | 55658 | <= 62821 | atingida (reducao de 46.8%) |
| O: maior `loaded_bytes` por fase (base + 1 referencia; fase `clarify`) | 146014 | 108427 | < 146014 | atingida (0 de 12 fases acima do baseline; pior caso 25.7% abaixo) |
| F: maior `loaded_bytes` por fase (base + 1 referencia; fase `clarify`) | 104702 | 81333 | < 104702 | atingida (0 de 9 fases acima do baseline; pior caso 22.3% abaixo) |

Metodo: `bytes = git show <ref>:<path> | wc -c`; `loaded_bytes` = prompt-base +
UMA referencia da fase (regra de leitura unica por fase, SC-006). A meta de FR-018
foi avaliada em BYTES porque nao ha contador de tokens offline (dec-010). Nenhuma
meta ficou sem ser atingida, portanto nao ha registro de "meta nao atingida" (FR-017).

## Limitacoes declaradas (FR-017, dec-010, SC-005)

- **Tokens indisponivel offline**: `ORCH_TOKEN_COUNTER` indefinida; a coluna de tokens e
  `indisponivel` e nenhum valor foi derivado de bytes. Esta medicao NAO afirma
  reducao de tokens; afirma reducao de bytes carregados.
- **Consumo observado NAO e "depois"**: a secao `--observed` abaixo cobre so ondas iniciadas
  ANTES do commit medido (janela `< data do commit`), isto e, ondas rodadas com os prompts
  anteriores ou intermediarios desta feature. A janela nao inclui ondas posteriores ao commit e
  nenhuma comparacao observada antes/depois foi feita; por isso nenhuma reducao de consumo
  observado (otel) e declarada. Todo numero observado traz `n` (ondas do grupo+fase), cobertura
  `k/n` por coluna e a fonte (tabela `waves` da knowledge.db).
- O consumo observado nao isola o prompt-base (o `cache_creation` inclui resultados de tool e
  turnos), conforme nota na propria secao.

# Medicao dos prompts dos orquestradores

- ref: `HEAD` (`3f860e047207bb8a64e6e43cac611f6bc6a13dbd`)
- data UTC da medicao: 2026-09-30T02:21:02Z
- metodo de bytes: `git show <ref>:<path> | wc -c` (bytes do arquivo no commit)
- metodo de tokens: indisponivel (ORCH_TOKEN_COUNTER nao definida; nenhum contador offline no ambiente). Gate de FR-018 avaliado em bytes (dec-010). Tokens NUNCA derivados de bytes.

## Prompt-base

| orchestrator | bytes | tokens |
|---|---|---|
| root | 78553 | indisponivel |
| feature | 55658 | indisponivel |

## Por fase (o que uma onda da fase carrega: prompt-base + 1 referencia)

| orchestrator | phase | base_bytes | ref_bytes | loaded_bytes | tokens |
|---|---|---|---|---|---|
| root | bootstrap | 78553 | 6374 | 84927 | indisponivel |
| root | briefing | 78553 | 3035 | 81588 | indisponivel |
| root | constitution | 78553 | 3118 | 81671 | indisponivel |
| root | roadmap | 78553 | 9332 | 87885 | indisponivel |
| root | specify | 78553 | 20753 | 99306 | indisponivel |
| root | clarify | 78553 | 29874 | 108427 | indisponivel |
| root | plan | 78553 | 20750 | 99303 | indisponivel |
| root | checklist | 78553 | 3131 | 81684 | indisponivel |
| root | create-tasks | 78553 | 12904 | 91457 | indisponivel |
| root | execute-task | 78553 | 7102 | 85655 | indisponivel |
| root | converge | 78553 | 4142 | 82695 | indisponivel |
| root | review-features | 78553 | 3144 | 81697 | indisponivel |
| feature | bootstrap | 55658 | 5899 | 61557 | indisponivel |
| feature | specify | 55658 | 19815 | 75473 | indisponivel |
| feature | clarify | 55658 | 25675 | 81333 | indisponivel |
| feature | plan | 55658 | 19812 | 75470 | indisponivel |
| feature | checklist | 55658 | 3149 | 58807 | indisponivel |
| feature | create-tasks | 55658 | 10624 | 66282 | indisponivel |
| feature | execute-task | 55658 | 6678 | 62336 | indisponivel |
| feature | converge | 55658 | 4052 | 59710 | indisponivel |
| feature | toolkit-issue | 55658 | 1877 | 57535 | indisponivel |

Fases sem arquivo de referencia no ref medido aparecem com `ref_bytes = 0` (no baseline, todas).

## Consumo observado (knowledge.db)

- fonte: tabela `waves` de `~/.claude/cstk/knowledge.db` (somente leitura)
- janela: started_at >= (sem limite) e < 2026-09-30T02:12:36Z
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
| feature-00c | (multi-etapa ou vazio) | 436 | 224/436; 7292161 | 224/436; 92401 | 32/436; 11328 |
| feature-00c | bugfix | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | bugfix-diagnostico-staging | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | bugfix-staging | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | checklist | 73 | 40/73; 4529556 | 40/73; 65211 | 2/73; 3085 |
| feature-00c | clarify | 97 | 61/97; 2860543 | 61/97; 38860 | 5/97; 3318 |
| feature-00c | converge | 50 | 50/50; 7538217 | 50/50; 90356 | 13/50; 265 |
| feature-00c | create-tasks | 78 | 47/78; 5072000 | 47/78; 78362 | 3/78; 2487 |
| feature-00c | execute-task | 502 | 345/502; 13395218 | 345/502; 127581 | 52/502; 11177 |
| feature-00c | execute-task-3.3 | 1 | 1/1; 2582844 | 1/1; 6162 | indisponivel (0/1) |
| feature-00c | execute-task-3.4 | 1 | 1/1; 17128323 | 1/1; 189792 | indisponivel (0/1) |
| feature-00c | execute-task-diagnostico | 1 | 1/1; 8825681 | 1/1; 104465 | indisponivel (0/1) |
| feature-00c | execute-task-F6.1 | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | execute-task-fase-4 | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | execute-task-fase4 | 2 | indisponivel (0/2) | indisponivel (0/2) | indisponivel (0/2) |
| feature-00c | execute-task-fase5 | 1 | indisponivel (0/1) | indisponivel (0/1) | indisponivel (0/1) |
| feature-00c | plan | 114 | 76/114; 12123979 | 76/114; 249601 | 9/114; 11814 |
| feature-00c | review-task | 32 | 21/32; 4016287 | 20/32; 33572 | 3/32; 2218 |
| feature-00c | scan-networks | 1 | 1/1; 31996445 | 1/1; 257647 | indisponivel (0/1) |
| feature-00c | specify | 81 | 47/81; 4558039 | 47/81; 65541 | 5/81; 2132 |
| feature-00c | terminal-close | 1 | 1/1; 899516 | 1/1; 2263 | indisponivel (0/1) |
