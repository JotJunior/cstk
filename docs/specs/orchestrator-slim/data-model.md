# Data Model: orchestrator-slim

**Feature**: `orchestrator-slim` | **Date**: 2026-09-29

Feature sem dados persistentes novos (nenhuma tabela, coluna ou campo de
state). As "entidades" sao artefatos de texto versionados e os inventarios
usados como prova de paridade.

## Entity: PromptBase

Arquivo do agente carregado inteiro a cada spawn de onda.

| Campo | Valor |
|-------|-------|
| paths | `plugins/cstk/agents/agente-00c-orchestrator.md` (O), `plugins/cstk/agents/agente-00c-feature-orchestrator.md` (F) |
| baseline_bytes | O=146014, F=104702 (`wc -c`, commit `9f97e99`) |
| target_max_bytes (FR-018, 40%) | O <= 87608, F <= 62821 |
| invariantes | frontmatter `tools:` intacto; bloco `MCP-VS-BASH:BEGIN/END` byte-identico entre O e F; secoes de FR-002 presentes; um stub por secao movida |

## Entity: PhaseReference

| Campo | Tipo | Regra |
|-------|------|-------|
| orchestrator | enum `root` \| `feature` | `root` = O, `feature` = F |
| phase | enum (tabela abaixo) | token kebab-case em ingles |
| path | string | `plugins/cstk/skills/agente-00c-runtime/references/orchestrators/<orchestrator>/<phase>.md` |
| sections | lista | secoes movidas, na ordem original do baseline |
| fragments | lista de `<id>` | blocos entre `<!-- FRAGMENT:<id>:BEGIN/END -->`, byte-identicos entre todas as copias |

Fases/condicoes com arquivo (so existe arquivo onde ha conteudo movido):

| phase | Quando e lido | root | feature |
|-------|---------------|------|---------|
| `bootstrap` | primeira invocacao (onda-001) e re-spawn pos-fallback de opt-ins | sim | sim |
| `briefing` | etapa `briefing` | sim | — |
| `constitution` | etapa `constitution` | sim | — |
| `roadmap` | etapa `roadmap` (modo roadmap) | sim | — |
| `specify` | etapa `specify` | sim | sim |
| `clarify` | etapa `clarify` | sim | sim |
| `plan` | etapa `plan` | sim | sim |
| `checklist` | etapa `checklist` | sim | sim |
| `create-tasks` | etapa `create-tasks` | sim | sim |
| `execute-task` | etapa `execute-task` | sim | sim |
| `converge` | etapa `converge` | sim | sim |
| `review-features` | etapa `review-features` | sim | — |
| `toolkit-issue` | sugestao com severidade `impeditiva` | — | sim |

Estados: nao ha transicao de estado em runtime; o arquivo e somente leitura.

## Entity: SectionStub

Stub deixado no prompt-base no lugar de cada secao movida.

| Campo | Regra |
|-------|-------|
| heading | identico ao heading/numeracao original (preserva referencias cruzadas por nome — research Decision 4) |
| marker | `<!-- ORCH-REF: <orchestrator>/<phase> -->` (um por fase citada) |
| body | ponteiro padronizado (`contracts/pointer-format.md`) — nenhuma regra nova |

## Entity: ContractInventory

Arquivos versionados sob `tests/fixtures/orchestrator-slim/`:

| Arquivo | Conteudo | Uso |
|---------|----------|-----|
| `contract-literals.tsv` | `<orchestrator>\t<grep-flags>\t<pattern>\t<source-test:line>` — todos os padroes positivos hoje asseridos pelos 11 testes | casar no baseline E no corpus novo (FR-006) |
| `contract-negatives.tsv` | mesmo formato de `contract-literals.tsv` — padroes NEGATIVOS (8 linhas) | ausentes do baseline E do corpus inteiro (FR-006) |
| `command-blocks.baseline.txt` | invocacoes `<script>.sh <subcomando>` extraidas do baseline, `sort -u`, por orquestrador | diff zero contra o corpus novo (FR-016) |
| `rewritten-lines.tsv` | `<orchestrator>\t<linha-baseline>\t<justificativa>` | allowlist da verificacao de preservacao de linhas (so referencias internas reescritas — FR-004 ii) |

Padroes NEGATIVOS (hoje: `\$\([^)]*\bcase\b` em O+F, `Gate incondicional .converge` em O+F,
`delivery_tier`/`delivery-tier` em F) passam a ser asseridos como ausentes do
corpus inteiro do orquestrador (prompt-base + referencias), nunca so do
prompt-base.

## Inventario de secoes — Orquestrador raiz (O)

Bytes medidos com `awk` somando `length+1` por linha no baseline `9f97e99`.
"100%" = roda em toda onda.

| Secao (linhas) | Bytes | 100%? | Decisao | Destino |
|----------------|-------|-------|---------|---------|
| preambulo + frontmatter (1-39) | 2461 | sim | manter | — |
| Sistema canonico de tracking (40-66) | 1385 | sim | manter | — |
| Principios MUST (67-85) | 984 | sim | manter (FR-002) | — |
| Inputs do contexto (86-94) | 392 | sim | manter (FR-002) | — |
| Primitivas operacionais (95-129) | 4742 | sim | manter (FR-002) | — |
| Orientacao MCP-vs-Bash (130-204) | 4876 | sim | manter (FR-007) | — |
| Init de aspectos-chave (205-245) | 1635 | nao (onda-001) | mover | bootstrap |
| Fronteira command↔orquestrador (246-266) | 1198 | sim | manter (FR-002) | — |
| Pre-flight da execucao (267-299) | 1381 | nao | manter (contem o probe do runtime, pre-requisito para ler qualquer referencia) | — |
| Contrato de conclusao de turno (300-335) | 2064 | sim | manter (FR-002) | — |
| Disciplina de output (336-353) | 991 | sim | manter (FR-002) | — |
| Loop: passo 1 (356-361) | 293 | sim | manter | — |
| Loop: 1.bis opt-ins MCP (362-428) | 4525 | nao (onda-001) | mover | bootstrap |
| Loop: passos 2, 2.bis, 3, 4 (429-478) | 2308 | sim | manter | — |
| Loop: 5 cabecalho (479-495) | 1066 | sim | manter | — |
| 5.a Briefing (496-512) | 754 | nao | mover | briefing |
| 5.b Constitution (513-574) | 2901 | nao | mover | constitution |
| 5.b.bis Roadmap (575-656) | 4862 | nao | mover | roadmap |
| 5.c Create-tasks (657-681) | 1271 | nao | mover | create-tasks |
| 5.d Demais skills (682-717) | 1991 | parcial | manter (orienta a escolha de skill em qualquer etapa) | — |
| 5.d.quater Tier de entrega (718-757) | 1970 | nao | mover (fragmento) | briefing, specify, plan |
| 5.d.bis Read-back loop (758-882) | 6983 | nao | mover (fragmento) | specify, plan |
| 5.d.ter camada B: `.tasks[]` + commit por task (883-1024) | 7663 | nao | mover | execute-task |
| 5.d.ter camada B: `.events[]`, custo em tokens, retro-compat (1025-1081) | 3038 | sim (`schedule_wait`/`validation_failed` em toda onda) | manter | — |
| 5.e Dois atores (clarify) (1082-1185) | 5716 | nao | mover | clarify |
| 5.e.bis Pre-spawn model-routing (1186-1612) | 21029 | nao | mover | clarify |
| 5.f Quality Gates complementares (1613-1755) | 8425 | nao | mover (fragmento) | specify, plan, create-tasks |
| 5.f.bis Etapa converge (1756-1820) | 3929 | nao | mover | converge |
| 5.f.ter Gate delta-gate (1821-1876) | 2924 | nao | mover | review-features |
| 6 Detectar conclusao (1877-1945) | 3480 | sim | manter | — |
| 7, 8, 9, 9.bis (1946-2015) | 4149 | sim | manter | — |
| 9.ter Commit atomico por etapa, sem o bloco Finalize terminal (2016-2066) | 2836 | nao | mover (fragmento `stage-commit-hook`) | specify, clarify, plan, checklist, create-tasks |
| 9.ter Finalize terminal (FR-008) + paragrafo Modo roadmap (2067-2085) | 946 | nao (onda terminal), sem fase com referencia propria | manter (decisao 1.2, FR-002/FR-005) | — |
| 9.quater Encerramento terminal roadmap (2087-2164) | 4258 | nao | mover | roadmap |
| 10-13 (2165-2346) | 9854 | sim | manter | — |
| Score-de-decisao (2347-2460) | 6345 | sim (toda Decisao) | manter | — |
| Classe estrutural (2461-2511) | 2967 | sim | manter | — |
| Warm-up de permissoes (2512-2531) | 1004 | sim | manter | — |
| Pausas longas / `/schedule` (2532-2567) | 1515 | parcial (passo 11) | manter | — |
| Defesa em profundidade (2568-2642) | 4538 | sim | manter | — |
| Estado atual (2643-2649) | 313 | sim | manter | — |

Soma movida: 81681 bytes (82627 do inventario original menos 946 do bloco
Finalize terminal, mantido no prompt-base — decisao da tarefa 1.2, CHK021).

## Inventario de secoes — Orquestrador de feature (F)

| Secao (linhas) | Bytes | 100%? | Decisao | Destino |
|----------------|-------|-------|---------|---------|
| preambulo (1-43) | 2651 | sim | manter | — |
| Sistema canonico de tracking (44-57) | 720 | sim | manter | — |
| Principios MUST (58-72) | 774 | sim | manter | — |
| Inputs (73-83) | 489 | sim | manter | — |
| Primitivas (84-117) | 2927 | sim | manter | — |
| Orientacao MCP-vs-Bash (118-192) | 4876 | sim | manter (FR-007) | — |
| Fronteira (193-214) | 1256 | sim | manter | — |
| Pre-flight da execucao, incl. 3.bis opt-ins (215-331) | 7275 | nao (onda-001) | mover | bootstrap |
| Contrato de conclusao de turno (332-367) | 2079 | sim | manter | — |
| Disciplina de output (368-385) | 991 | sim | manter | — |
| Loop principal, exceto 7.bis e 10.qui (386-646) | 8706 | sim | manter | — |
| Loop 7.bis commit por task (478-533) | 3139 | nao | mover | execute-task |
| Loop 10.qui commit por etapa, sem o bloco Finalize terminal (574-626) | 2907 | nao | mover (fragmento `stage-commit-hook`) | specify, clarify, plan, checklist, create-tasks |
| Loop 10.qui Finalize terminal (FR-008) (627-637) | 460 | nao (onda terminal), sem fase com referencia propria | manter (decisao 1.2, FR-002/FR-005) | — |
| Invariante retomada/onda fechada (647-672) | 1514 | sim | manter | — |
| Camada B: `.tasks[]` (683-744) | 3310 | nao | mover | execute-task |
| Camada B: cabecalho, `.events[]`, custo, retro-compat (673-682, 745-799) | 3494 | sim | manter | — |
| Passo PRE-DECISAO read-back (800-899) | 5257 | nao | mover (fragmento) | specify, plan |
| Mediacao clarify (900-951) | 2330 | nao | mover | clarify |
| Sequencia pre-spawn model-routing (952-1326) | 17343 | nao | mover | clarify |
| Subagent depth invariant: cabecalho (1327-1340) | 691 | sim (qualquer spawn) | manter | — |
| Subagent depth: cap defensivo (1341-1400) | 2855 | nao | mover | clarify |
| Quality Gates complementares, exceto converge (1401-1521) | 7398 | nao | mover (fragmento) | specify, plan, create-tasks |
| Quality Gates: etapa converge (1522-1586) | 3828 | nao | mover | converge |
| Sugestoes para skills globais (1587-1614) | 1346 | sim (passo 10.qua) | manter | — |
| Retrospectiva por marco (1615-1655) | 2150 | sim (regra "NAO chame" vale em toda onda) | manter | — |
| Gh issue exclusivo (1656-1690) | 1648 | nao | mover | toolkit-issue |
| Score de decisao (1691-1740) | 3166 | sim | manter | — |
| Classe estrutural (1741-1791) | 2986 | sim | manter | — |
| Gate de itens Alto do briefing (1792-1858) | 3769 | nao | mover (fragmento) | specify, plan |
| Defesa em profundidade (1859-1871) | 1145 | sim | manter | — |
| Anti-padroes (1872-1891) | 1222 | sim | manter (FR-002) | — |

Soma movida: 61059 bytes (61519 do inventario original menos 460 do bloco
Finalize terminal, mantido no prompt-base — decisao da tarefa 1.2, CHK021).

Os limites de linha acima sao do baseline e servem de guia; o limite exato
de cada corte e conferido na execucao pela verificacao de preservacao de
linhas (research Decision 8). Qualquer trecho cuja classificacao se revele
errada (ex. roda em toda onda) volta ao prompt-base — a margem sobre a meta
(research Decision 6) absorve isso.

## Decisao: destino do bloco "Finalize terminal" (CHK021)

O bloco `commit-mode.sh finalize` (push + PR do modo atomic-commit) roda na
onda terminal (`review-features` em O, `review-task` em F). Em F nao existe
referencia `review-task`, e em O `review-features` so recebe o delta-gate
(5.f.ter); mover o bloco para o fragmento `stage-commit-hook` o deixaria fora
da leitura da onda terminal (regressao de FR-005). Decisao: o bloco permanece
NO PROMPT-BASE, fora do fragmento, em ambos os orquestradores. Medido no
baseline `9f97e99`: O linhas 2067-2075 (bloco, 379 bytes) e 2077-2085
(paragrafo "Modo roadmap", 567 bytes) = 946 bytes; F linhas 627-637 = 460
bytes. O paragrafo "Modo roadmap" de O acompanha o bloco por descrever o
gatilho/ordem do mesmo finalize (a sequencia de 4 passos vive em
`root/roadmap.md`, 9.quater). O teste de paridade afirma a presenca de
`commit-mode.sh finalize` no prompt-base de O e de F.

## Projecao da reducao (estimativa de planejamento, recalculada)

Formula: `baseline − movido + stubs`, com estimativa conservadora de 650
bytes por stub (o exemplo do contrato `pointer-format.md` mede ~506 bytes;
stubs de fragmento com varios marcadores sao maiores) e ~1000 bytes para a
secao "Referencias de fase". O valor oficial vem do script de medicao.

| Orquestrador | Baseline | Movido | Stubs (n x 650) + secao | Prompt-base projetado | Reducao projetada | Limite FR-018 |
|--------------|----------|--------|-------------------------|-----------------------|-------------------|---------------|
| O | 146014 | 81681 | 10400 + 1000 | ~75733 | ~48% | <= 87608 |
| F | 104702 | 61059 | 7800 + 1000 | ~52443 | ~50% | <= 62821 |

A margem sobre o limite (~11800 bytes em O, ~10400 em F) preserva a
alcancabilidade da meta com o bloco Finalize terminal no prompt-base.

## Testes que dependem do texto (migracao — research Decision 9)

| Teste | Orq. | Tipo de assert | Migracao |
|-------|------|----------------|----------|
| `tests/test_orchestrator-turn-completion.sh` | O, F | LIT | corpus (secoes ficam no prompt-base; grep no corpus cobre) |
| `tests/test_orchestrator-spawn-model-apply.sh` | O, F | LIT + NEG | corpus; NEG no corpus inteiro |
| `tests/test_orchestrator-evidence-grounding.sh` | O, F | LIT | corpus |
| `tests/test_converge-orchestrator-gate.sh` | O, F | LIT + NEG | corpus; NEG no corpus inteiro |
| `tests/test_data-veracity-verifier.sh` | O, F | LIT | corpus |
| `tests/test_roadmap-mode.sh` | O | POS ancorado em heading | ordem `commit-mode.sh finalize` < `concluido_roadmap` asserida dentro de `root/roadmap.md` a partir do heading |
| `tests/test_command-spawn-optin-elicitation.sh` | O, F | POS + LIT + NEG | ordem: ponteiro `bootstrap` no prompt-base antes de `2. **Onda nova**` (O) / `4. **Iniciar onda**` (F) + `**primeiro ato**` presente em `bootstrap.md`; LIT/NEG no corpus |
| `tests/test_command-spawn-optin-degradation.sh` | O, F | LIT | corpus |
| `tests/test_command-spawn-delivery-tier.sh` | F | NEG | corpus inteiro de F |
| `tests/test_model-routing.sh` (`scenario_doc_feature_orchestrator_sequencia_pre_spawn`) | F | contagem + POS + LIT | `feature/clarify.md` (ultimo `invoke` antes do ultimo `enter`) |
| `tests/test_orchestrator-allowlist-guard.sh` | O, F | frontmatter + marcadores | sem mudanca (tudo fica no prompt-base) |
| `tests/test_doc-subcommands.sh` | — | varredura de `DOC_DIRS` | incluir `plugins/cstk/skills/agente-00c-runtime/references/orchestrators` |
