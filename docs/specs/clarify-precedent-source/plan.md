# Implementation Plan: clarify-precedent-source

**Feature**: `clarify-precedent-source` | **Data**: 2026-09-30 | **Spec**: [spec.md](spec.md)

## Summary

Adicionar "precedente do operador" como 4a fonte de evidencia dos
clarify-answerers (`agente-00c` e `feature-00c`). O orquestrador-pai
consulta, por pergunta, um modo novo somente-leitura `cstk recall
--precedents` (em `cli/lib/recall.sh`): prefiltro FTS5 OR sobre bloqueios
respondidos + similaridade Jaccard dos tokens da pergunta com limiar
calibrado em **0.55** contra a base real (research Decision 2). Os
precedentes chegam ao answerer como campo opcional `precedents`; o answerer
soma +1 a opcao concordante (teto 3) somente quando `briefing` ou
`spec_corrente`/`stack_sugerida` tambem a apoiam positivamente (dec-027 —
"constitution nao violada" nao basta), nunca decide so por precedente, nunca
aceita dado factual de precedente e, ao pausar, anexa recomendacao (sem
divergencia) ou lista todos os divergentes (com divergencia). Toda
degradacao e no-op com prompt byte-identico.

## Technical Context

| Campo | Valor |
|---|---|
| Linguagem | POSIX sh (`cli/lib/recall.sh`); prosa Markdown (agentes e referencias de fase) |
| Dependencias | `sqlite3` (ja opcional e confinado a `cli/lib/recall.sh`); `awk`/`tr`/`sort` POSIX para tokenizacao e Jaccard |
| Storage | `~/.claude/cstk/knowledge.db` somente leitura (tabelas `blocks`, `decisions`, `knowledge_fts`); `.events[]` do state da execucao via helpers existentes |
| Testes | `tests/run.sh` — extensao de `tests/cstk/test_recall.sh`; teste estatico interno novo; eval nao-gateante em `tests/eval/` |
| Plataforma | macOS + Linux (sem GNU-only; `stat`/`sed -i` nao usados) |
| Restricoes | `sqlite3` so em `recall.sh`; answerer mantem `Read, Bash` (Bash so `date`); sintaxe nova em ingles; nenhuma escrita na knowledge.db |
| Escopo de orquestradores | Layout v10.11.0 (orchestrator-slim): mediacao clarify em `plugins/cstk/skills/agente-00c-runtime/references/orchestrators/{feature,root}/clarify.md` |
| NEEDS CLARIFICATION | 0 (nenhum eixo estrutural tocado — stack/persistencia/arquitetura herdadas) |

**Target Platform**: qualquer ambiente POSIX local do operador onde rodam o binario `cstk` e o harness Claude Code (herdado do briefing L79 "roda em qualquer ambiente POSIX sem setup" e do Principio II da constitution; sem eixo estrutural novo)

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 (abaixo).*

| Principio | Status | Notas |
|---|---|---|
| I. SDD recursivo | PASS | spec + clarify concluidos; plan e tasks nesta pipeline |
| II. POSIX sh / deps | PASS | Codigo novo so em `cli/lib/recall.sh` (POSIX); `sqlite3` segue dep OPCIONAL confinada (amendment 1.1.0: fallback no-op testado — quickstart Cenario 5; confinamento em arquivo unico; declarada aqui) |
| III. Formato de skill | N/A | Nenhuma SKILL.md alterada (agentes e referencias de fase) |
| IV. Zero coleta remota | PASS | Leitura local de `~/.claude/cstk/knowledge.db`; nenhuma rede |
| V. Profundidade | PASS | Reduz re-perguntas ao operador (retrabalho) |
| VI. Zero fabricacao | PASS | Limiar e tetos derivados de medicao real citada (research Decisions 2, 5); precedente proibido de fornecer dado factual (FR-005); pool de 20 declarado como default nao-medido |

## Project Structure

### Documentation (this feature)

```text
docs/specs/clarify-precedent-source/
├── spec.md
├── plan.md                              # este arquivo
├── research.md                          # medicao + 10 decisoes
├── data-model.md
├── quickstart.md                        # 9 cenarios
└── contracts/
    ├── cli-recall-precedents.md         # [PROPOSTA] modo --precedents
    └── answerer-precedents.md           # [PROPOSTA] extensao do contrato do answerer
```

### Source Code (repository root)

Caminhos verificados no HEAD da branch (178c5ac — merge local de
`origin/main` v10.11.0 feito pelo command pai com aprovacao do operador,
dec-028): as referencias de fase `references/orchestrators/{feature,root}/
clarify.md` e `scripts/orchestrator-refs.sh` ja existem na branch.

```text
cli/lib/recall.sh                                   # RUNTIME: recall_mode_precedents + dispatch + usage
cli/cstk                                            # RUNTIME: help de recall menciona --precedents
plugins/cstk/agents/feature-00c-clarify-answerer.md # CATALOGO: 4a fonte
plugins/cstk/agents/agente-00c-clarify-answerer.md  # CATALOGO: 4a fonte (paridade)
plugins/cstk/skills/agente-00c-runtime/references/orchestrators/feature/clarify.md  # CATALOGO
plugins/cstk/skills/agente-00c-runtime/references/orchestrators/root/clarify.md     # CATALOGO
tests/cstk/test_recall.sh                           # cenarios precedents_* (1-6)
tests/test_clarify-precedent-prose.sh               # NOVO, interno (Cenario 7) + registro em _is_internal_test
tests/eval/eval_precedent-calibration.sh            # NOVO, eval nao-gateante (Cenario 8)
CHANGELOG.md                                        # entrada MINOR com as duas metades
docs/agente-00c.md                                  # nota de usuario sobre a 4a fonte
```

### Sequencia de implementacao

(A sincronizacao com `origin/main` prevista em dec-024 ja foi feita —
merge 178c5ac, dec-028 — e NAO entra no backlog.)

1. Runtime: `recall_mode_precedents` + testes 1-6 (TDD).
2. Catalogo: answerers (regras de pontuacao) + referencias de clarify
   (consulta, evento, omissao, bloqueio com precedentes) + teste estatico.
3. Eval de calibracao + docs (CHANGELOG, docs/agente-00c.md).

### Duas metades da instalacao (FR-017)

| Metade | Arquivos | Como atualizar a copia instalada |
|---|---|---|
| Runtime do binario | `cli/lib/recall.sh`, `cli/cstk` | `cstk self-update --from <tarball>` (atualiza `~/.local`) |
| Catalogo | agentes answerer + referencias de fase | `cstk update` ou `cstk install --from <tarball>` (atualiza `~/.claude`) |

Atualizar so o catalogo deixa o orquestrador chamando `--precedents` num
binario antigo: `recall_main` cai no modo busca (a flag desconhecida no
modo busca → exit 2), o orquestrador trata como K=0 e segue — degradacao
segura, mas a feature fica inerte. Documentar no CHANGELOG.

## Convencoes de Borda

N/A — single-layer (CLI local + prosa de agentes). Unica borda de dados:
texto do `--precedents` (stdout) → campo `precedents` do prompt do answerer
→ JSON de resposta; formatos em `contracts/`. Chaves JSON novas em ingles;
chaves legadas do answerer (`pergunta_id`, `referencias`, `fonte`...)
preservadas para compatibilidade.

## Premissas e decisoes do operador

| ID | Premissa / decisao | Status | Efeito no desenho |
|---|---|---|---|
| P-1 | Empate de `answered_at` entre precedentes DIVERGENTES → nenhum pontua (FR-006) | **Decidida pelo operador** (dec-027, block-005) | Regra 2 do contrato do answerer, sem alteracao |
| P-2 | "Precedente + constitution nao violada" = score 2 = decisao automatica | **Rejeitada pelo operador** (dec-027, opcao A "exigir suporte positivo") | Precedente so soma com suporte positivo de `briefing` ou `spec_corrente`/`stack_sugerida`; spec alterada (FR-003, FR-004, US1-3, SC-002) |
| P-3 | Limiar 0.55 calibrado num corpus dominado por um projeto | Premissa aberta (research Decision 2) | Recalibrar via eval (Cenario 8) |

Implicacao para testes: o teste estatico de prosa (Cenario 7) passa a exigir,
nos dois answerers, a regra de suporte positivo e a frase de que o +1 de
constitution nao conta como suporte positivo; o Cenario 9 (manual/eval)
inclui o caso "so constitution + precedente" com esperado `scored: false`.

## Riscos

- Corpus da knowledge.db com duplicatas de ingestao (worktree/projeto
  renomeado) — mitigado pela dedup (research Decision 3).
- Tokenizacao divergente entre probe e implementacao invalida a
  calibracao — mitigado por teste que fixa o metodo e Gotcha no codigo.
- Precedente com diretiva embutida — tratado como dado (FR-008), rotulo
  UNTRUSTED em nivel de codigo.

## Revisao de seguranca (gate owasp-security, onda-004)

| ID | Sev. | Achado | Mitigacao |
|---|---|---|---|
| S-1 | HIGH | **Precedente envenenado (ASI06/LLM01) decide sem humano.** `recall --reindex` varre `*/.claude/feature-00c-state/*/state.json` sob a raiz (`cli/lib/recall.sh` L3475): um repo de terceiro clonado com state versionado forjado injeta bloqueios `respondido` cujas "respostas do operador" nunca vieram do operador. Somado a P-2 (precedente + constitution nao violada = score 2), um precedente forjado sem nenhuma diretiva explicita (logo sem disparar FR-008) decide sozinho no clarify | **Resolvido pelo operador (block-005 → dec-027, opcao A)**: suporte POSITIVO obrigatorio — o precedente so soma quando `briefing` ou `spec_corrente`/`stack_sugerida` tambem apoiam a opcao; "constitution nao violada" nao basta. O precedente so reforca/desempata uma fonte real do projeto corrente; um precedente forjado passa a no maximo virar recomendacao rotulada (S-3), nunca decisao. Precedente de outro projeto segue elegivel (FR-013) |
| S-2 | MEDIUM | **Vazamento cross-project (LLM02).** Texto de bloqueio do projeto A (scrubbed so de segredos, nao de dado de negocio) entra no prompt do answerer do projeto B e pode ser copiado para `spec.md`/Decisoes/estado de B — artefatos commitados (modo atomic-commit) e possivelmente empurrados para o repo de outro cliente | Regra no answerer e nas referencias: artefatos persistidos do projeto corrente citam precedente SO por `block_ref` + opcao; texto do precedente nunca vai para `spec.md` nem `--justificativa`; o unico texto persistido e o `answer_excerpt` (<= 120 bytes) na listagem de divergentes do bloqueio, exigido por FR-006 |
| S-3 | MEDIUM | **Ancoragem do operador (ASI09).** Recomendacao "confirme com um gesto" pode ser carimbada sem leitura, inclusive se o precedente for forjado (S-1) | Secao "Precedentes" do bloqueio sempre mostra projeto/feature/data de origem e marca `[outro projeto]` quando `project` != projeto corrente; texto fixo "recomendacao derivada de historico, nao verificada" |
| S-4 | LOW | Injecao SQL/FTS5 no modo novo | Reuso de `fts_phrase_escape` + `sql_escape` + `validate_limit`; `--min-similarity` validado por regex antes de qualquer interpolacao; tokens so `[a-z0-9]` e bytes >= 0x80; somente `recall_query_sql` (leitura) |
| S-5 | LOW | Consumo (LLM10) | Tetos: 3 precedentes x 2400 bytes por pergunta, max 5 perguntas por clarify |

S-4 e S-5 ja cobertos pelo desenho. S-2 e S-3 incorporados como requisitos
de implementacao (tasks). S-1 resolvido pelo operador (regra de suporte
positivo, requisito de implementacao nos dois answerers).

## Complexity Tracking

Nenhuma violacao de constitution. Duplicacao deliberada dos gates de
degradacao de `recall_mode_context` dentro de `recall_mode_precedents`
(mesma justificativa ja registrada no codigo: extrair helper espalharia
`sqlite3`; aceitavel reusar funcoes internas do proprio `recall.sh`).

## Re-check de constitution (pos-design)

Sem nova camada, servico ou dependencia. `sqlite3` continua em um unico
arquivo; nenhum Bash-ism exigido (Jaccard em `awk`); nenhuma rede; nenhum
numero sem fonte (todos os valores de calibracao/tetos citam medicao ou
estao declarados como default de design). Resultado: PASS.
