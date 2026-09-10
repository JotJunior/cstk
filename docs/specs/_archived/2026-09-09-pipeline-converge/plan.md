# Implementation Plan: pipeline-converge

**Feature**: `pipeline-converge`
**Spec**: [spec.md](./spec.md) (clarificada — 4 perguntas resolvidas)
**Research**: [research.md](./research.md) (16 decisoes)
**Created**: 2026-08-21

## Summary

Emancipar a convergencia (`converge`) de comportamento embutido na prosa dos
orquestradores autonomos para **etapa nomeada e ordenada da pipeline SDD**,
entre `execute-task` e `review-task`, valendo igualmente para execucao
autonoma (`agente-00c`, `feature-00c`) e manual.

A abordagem tecnica tem tres movimentos:

1. **Maquina de etapas**: inserir `converge` em `_PL_STAGES_LIST`
   (`pipeline.sh:96`), de 10 para 11 etapas. Todo o resto — `next-stage`,
   `prev-stage`, `stages`, e o `end --advance` do `state-ondas.sh` — deriva
   automaticamente, sem codigo novo.
2. **Artefato de status**: a skill `converge` passa a gravar
   `docs/specs/<feature>/converge-report.md` (append-only, linha marcadora
   POSIX-parseavel), operado por um script determinístico novo
   `converge-status.sh`. E o que da lastro consultavel — inclusive em execucao
   manual, onde nao existe `state.json` — a "a convergencia mais recente rodou?
   apontou pendencias?".
3. **Soft gate + proveniencia**: `review-task` reporta convergencia pendente
   como finding e exige aceite de risco auditavel (nunca bloqueia); cada
   invocacao registra se foi gate obrigatorio ou avulsa.

A feature **revoga explicitamente** a Decision 5 da feature `skill-converge`
(que manteve `converge` fora da lista) — ver research.md §Decision 13.

## Technical Context

**Language/Version**: POSIX `sh` (scripts) + Markdown (skills, agents, docs)
**Primary Dependencies**: nenhuma nova — apenas `grep`, `sed`, `awk`, `mktemp` e o helper de `sha256` ja usado por `converge-tasks.sh gap-key`
**Storage**: arquivos no repositorio (`docs/specs/<feature>/converge-report.md`); estado transacional 00c inalterado (nenhum campo novo em `state.json`/`state.db`)
**Testing**: harness POSIX do repo (`./tests/run.sh`), com `tests/test_converge-status.sh` novo
**Target Platform**: qualquer ambiente POSIX (matriz real de uso: macOS e Linux) — fonte: `docs/constitution.md` Principio II (NON-NEGOTIABLE), que exige que os scripts "rodam em qualquer ambiente POSIX sem setup"
**Project Type**: cli / toolkit de skills (sem servidor, sem UI)
**Performance Goals**: N/A — operacoes sao leitura/append de um arquivo pequeno por invocacao
**Constraints**: Constitution II proibe `jq` e qualquer dependencia externa em `plugins/cstk/skills/converge/scripts/`; a excecao de dependencia opcional cobre a camada de estado transacional do `agente-00c-runtime`, nao esta skill
**Scale/Scope**: ~1 artefato por feature; ~10 registros por feature ao longo da vida
**Delivery tier**: `cloud-public` (lido de `.delivery_tier` no `state.json` desta execucao) — implica gate `owasp-security` em modo completo
**NEEDS CLARIFICATION**: 0

Inferencias: nao ha `go.mod`/`package.json` na raiz (o `mcp/state-server` tem o
seu, mas nao e tocado por esta feature); `CLAUDE.md` e `docs/constitution.md`
fixam POSIX `sh` como linguagem dos scripts de skill.

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (secao §Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | PASS | feature entra pelo pipeline completo, com `spec.md` clarificada + este `plan.md`; a mudanca altera CONTRATO de skills (`converge`, `review-task`, `execute-task`) e de `pipeline.sh` ⇒ exige bump de versao + nota no `CHANGELOG.md`. Ver §Complexity Tracking |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | PASS | `converge-status.sh` nasce `#!/bin/sh` + `set -eu`, sem `jq` (Decision 4). O diretorio `plugins/cstk/skills/converge/scripts/` **nao** esta coberto pela excecao de dependencia opcional (que e restrita a camada de estado transacional do `agente-00c-runtime`) |
| III. Formato canonico de skill | PASS | mecanica determinística vai para `scripts/` (nunca prosa do `SKILL.md`); `Gotchas` das skills tocadas sera atualizada com as armadilhas reais desta mudanca |
| IV. Zero coleta remota (NON-NEGOTIABLE) | PASS | nenhuma rede; artefato local no repo do usuario |
| V. Profundidade sobre adocao | PASS | a feature reduz retrabalho (drift spec-vs-codigo detectado antes do encerramento), nao gera visibilidade |
| VI. Veracidade de dados (NON-NEGOTIABLE) | PASS | todo comportamento atual citado neste plano e no `research.md` tem path+linha verificado; o contrato do script novo esta marcado `[PROPOSTA — a validar na implementacao]` |

**Nenhum FAIL em MUST.** Prosseguiu para Phase 0.

## Project Structure

### Documentation (this feature)

```
docs/specs/pipeline-converge/
├── spec.md                              # ja existente (clarificada)
├── plan.md                              # este arquivo
├── research.md                          # 16 decisoes
├── data-model.md                        # ConvergenceStatusRecord + PipelineStage
├── quickstart.md                        # cenarios de validacao
└── contracts/
    ├── converge-status-cli.md           # CLI do script novo [PROPOSTA]
    └── pipeline-stage-machine.md        # delta da maquina de etapas
```

### Source Code (repository root)

Arvore real do repositorio, so os pontos tocados. Cada path foi verificado
como existente.

```
plugins/cstk/
├── skills/
│   ├── converge/
│   │   ├── SKILL.md                     # ALTERADO  registra status + --provenance
│   │   └── scripts/
│   │       ├── converge-status.sh       # NOVO      record|latest|check|accept-risk
│   │       └── converge-tasks.sh        # inalterado (helper de digest reusado)
│   ├── execute-task/SKILL.md            # ALTERADO  §Proximos passos -> converge
│   ├── review-task/SKILL.md             # ALTERADO  soft gate + finding converge-pending
│   └── agente-00c-runtime/
│       ├── scripts/
│       │   ├── pipeline.sh              # ALTERADO  _PL_STAGES_LIST + detect-completion
│       │   ├── state-ondas.sh           # AVALIAR   hold de reconcile-wave p/ converge
│       │   └── commit-mode.sh           # ALTERADO  case stage->scope (aditivo)
│       └── references/
│           └── phase-model-map.txt      # ALTERADO  linha converge|profunda|opus
├── agents/
│   ├── agente-00c-orchestrator.md       # ALTERADO  etapa regular (remove gate especial)
│   └── agente-00c-feature-orchestrator.md # ALTERADO  idem
└── commands/
    ├── agente-00c.md                    # ALTERADO  frontmatter/sequencia
    └── feature-00c.md                   # ALTERADO  frontmatter/sequencia

cli/lib/show-tip.sh                      # ALTERADO  _st_phase_to_skill + help

tests/
├── test_pipeline.sh                     # ALTERADO  10 -> 11 etapas (2 cenarios)
├── test_state-ondas.sh                  # ALTERADO  advance/reconcile p/ converge
├── test_converge-orchestrator-gate.sh   # ALTERADO  regex da fronteira
├── test_model-routing.sh                # ALTERADO  _PML_EXPECTED 11 -> 12
└── test_converge-status.sh              # NOVO      cobertura do script novo

docs/
├── sdd-pipeline.md / .pt-BR.md          # ALTERADO  diagrama + tabela
├── agente-00c.md / .pt-BR.md            # ALTERADO  sequencia
├── fluxo-orquestradores-00c.md          # ALTERADO  texto + mermaid (2 blocos)
└── cstk-panel/frontend-brief.md         # ALTERADO  sequencia feature-00c

docs-site/
├── index.md                             # ALTERADO
└── manual/{fluxo-sdd.md,profiles.md}    # ALTERADO  "10 etapas" -> 11

README.md / README.pt-BR.md              # ALTERADO  converge sai de "Complementary"
CONTRIBUTING.md / CONTRIBUTING.pt-BR.md  # ALTERADO  mermaid
CLAUDE.md                                # ALTERADO  bloco SDD Pipeline
CHANGELOG.md                             # ALTERADO  BREAKING + revogacao Decision 5
```

**Sincronizacao (GOTCHA)**: `.claude/agents/*.md` sao copias instaladas e ja
divergem das fontes em `plugins/cstk/agents/`. Editar **sempre** a fonte; a
copia se atualiza por `cstk install --from <tarball>` (catalogo). Ver
§"Installed vs Source Drift" do `CLAUDE.md`.

## Convencoes de Borda

**N/A — single-layer.** A feature nao atravessa fronteira backend↔frontend,
DB↔backend nem broker↔consumer: e composta de scripts POSIX, artefatos
Markdown e documentacao, todos no mesmo processo/camada.

A unica fronteira de dados e o **formato do marcador**
`<!-- converge-status: ... -->`, cuja fonte da verdade unica e
`converge-status.sh` (research.md §Decision 5) — nenhum consumidor reimplementa
o parse:

| Consumidor | Como le | Fonte da verdade |
|-----------|---------|------------------|
| `pipeline.sh detect-completion --stage converge` | `converge-status.sh check` | `converge-status.sh` |
| `review-task` (soft gate) | `converge-status.sh check` | idem |
| `execute-task` (proximos passos) | `converge-status.sh check` | idem |
| orquestradores 00c | `converge-status.sh check` + `state-*.sh` | idem |

## Faseamento sugerido

Ordem derivada de dependencia real (o backlog detalhado sai do
`/create-tasks`):

| Fase | Conteudo | Depende de |
|------|----------|-----------|
| F1 | `converge-status.sh` + `tests/test_converge-status.sh` | — |
| F2 | `pipeline.sh` (lista + `detect-completion`) + atualizacao de `test_pipeline.sh` | F1 |
| F3 | Skill `converge`: gravar status, aceitar `--provenance` | F1 |
| F4 | `execute-task` e `review-task` (proximos passos + soft gate) | F1, F3 |
| F5 | Orquestradores: `converge` como etapa regular (FR-006); ajuste de `test_state-ondas.sh` e `test_converge-orchestrator-gate.sh`; avaliar hold de `reconcile-wave` (research.md §Decision 14) | F2, F3 |
| F6 | Superficies auxiliares: `phase-model-map.txt`, `commit-mode.sh`, `show-tip.sh` (+ testes) | F2 |
| F7 | Documentacao (SC-004): docs, docs-site, README, CONTRIBUTING, CLAUDE.md, CHANGELOG | F1-F6 |

F1 primeiro porque `pipeline.sh`, as skills e os orquestradores todos dependem
do veredito de `check` — implementar qualquer consumidor antes obrigaria a
mockar um contrato ainda instavel.

## Riscos e mitigacoes

| Risco | Impacto | Mitigacao |
|-------|---------|-----------|
| `pipeline.sh` (skill `agente-00c-runtime`) passa a depender de script da skill `converge` | instalacao com catalogo parcial quebraria a maquina de etapas | degradacao tolerante: script ausente ⇒ exit 0 + aviso em stderr (contrato §D2). Precedente de reuso cross-skill ja documentado no `converge-tasks.sh` |
| `reconcile-wave` avanca `converge -> review-task` sem hold | convergencia pendente passa despercebida no caminho de reconciliacao | avaliar hold simetrico em F5 (research.md §Decision 14); o soft gate de `review-task` continua como rede |
| Execucoes 00c em andamento com `current_stage=review-task` | comportamento inesperado no meio de uma execucao | nenhuma releitura retroativa da lista; `review-task` segue etapa valida (contrato §Compatibilidade) |
| SC-004 falha por divergencia pre-existente do `analyze` | criterio insatisfeito por causa alheia a feature | normalizar `analyze` como cross-check lateral nos pontos tocados (research.md §Decision 15) |
| Aceite de risco vira passe livre permanente | drift aceito uma vez nunca mais reavaliado | aceite vinculado ao `tasks-digest`: mudou o backlog, caduca (data-model §State transitions) |

## Revisao de seguranca (gate `owasp-security`, modo completo)

Modo **completo** exigido pelo tier `cloud-public`
(`references/tier-gate-map.txt`: `cloud-public|owasp-security|completo`).
Superficie avaliada: script POSIX que escreve artefato no repositorio +
runtime de orquestrador que decide avanco de etapa por exit code + artefato
lido por agente autonomo.

Todos os findings abaixo foram **fechados neste plano** (mitigacao incorporada
ao desenho antes de avancar), nao adiados para a implementacao.

| # | Finding | Sev. | Ref. | Mitigacao incorporada |
|---|---------|------|------|------------------------|
| F1 | `detect-completion` degrada para **exit 0** quando `converge-status.sh` esta ausente/nao-executavel — fail-**open** num ponto que decide avanco de etapa | HIGH | A10 (Exception Handling), ASI08 | Distinguir os dois casos: **skill `converge` nao instalada** (diretorio `skills/converge/` ausente) ⇒ exit 0 legitimo, etapa nao se aplica; **skill instalada mas script ausente/falho** ⇒ **exit 1 (fail-closed)** + diagnostico em stderr. So a primeira e degradacao aceitavel |
| F2 | `converge-report.md` e conteudo de repositorio (editavel por PR de terceiro) e sera lido por agente autonomo — vetor de injecao indireta de prompt / envenenamento de memoria | HIGH | LLM01, ASI06, ASI09 | (a) `check` parseia **apenas** o marcador por regex ancorada (`^<!-- converge-status: ... -->$`), ignorando toda prosa do arquivo; (b) `check` NUNCA ecoa conteudo do arquivo — so o veredito de vocabulario fechado (`converged`/`pending`/`stale`/`never`/`not-applicable`); (c) `latest`, que imprime a linha literal, e para auditoria humana — as skills e orquestradores consomem `check`, nunca `latest`; (d) quando o conteudo do artefato for exibido a um agente, vale o rotulo **UNTRUSTED** ja padronizado no read-back loop: e DADO, nunca instrucao |
| F3 | `--feature-dir` sem contencao permite escrita fora do repositorio (`../../..`) | MEDIUM | A01, CWE-22 | Reusar `converge/scripts/path-contains.sh` — helper que a propria skill ja possui, canonicaliza symlinks **antes** de checar o prefixo e e fail-closed quando nenhum marcador de raiz e encontrado. Nenhum mecanismo novo |
| F4 | `tasks-digest` pode ser lido como controle de integridade | MEDIUM | A08, Constitution VI | Declarar explicitamente o modelo de confianca: o digest detecta **mudanca**, nao **adulteracao** — e recalculavel por qualquer um, e o artefato e auditavel, nao um controle de seguranca. Nenhum consumidor deve derivar garantia de autenticidade dele |
| F5 | Append via `mktemp`+`mv` sob concorrencia (operador + orquestrador) pode perder registro (lost update); `mv` cross-device nao e atomico | MEDIUM | A06 (Insecure Design), TOCTOU | `mktemp` criado no **mesmo diretorio** do destino (padrao ja adotado em `converge-tasks.sh:303` — `mktemp -- "${_tasks}.XXXXXX"`), garantindo `rename(2)` no mesmo filesystem. Registro perdido e detectavel (append-only + digest), nunca silencioso |
| F6 | Escrita seguindo symlink no destino (`converge-report.md` -> alvo arbitrario) | LOW | CWE-59 | Recusar (exit 2) quando o destino existe e e symlink |
| F7 | Texto livre (`--justificativa`/`--note`) com metacaracteres de shell ou quebra do delimitador (`;`, `-->`, newline) | MEDIUM | A05 (Injection) | Rejeicao na escrita (exit 2) para `;`, `-->` e newline (contrato `converge-status-cli.md`); valores sempre passados como argv, nunca por `eval`; mesma disciplina de quoting ja exigida no repo |
| F8 | Agente autonomo poderia invocar `accept-risk` e se auto-liberar do soft gate — esvaziando o gate que a feature existe para criar | HIGH | ASI02 (Tool Misuse), LLM06 (Excessive Agency) | **Resolvido pela leitura literal da spec**: FR-004 atribui o aceite ao **operador** ("quando o **operador** tiver registrado explicitamente"). Portanto, em execucao autonoma o orquestrador **NUNCA** invoca `accept-risk` por conta propria: emite `bloqueios.sh register` e so registra o aceite apos resposta humana. O agente pode *propor*, jamais *consentir* |

**Nao aplicavel a esta feature** (registrado para evitar releitura futura):
autenticacao/sessao, criptografia, TLS, gestao de segredos, API/BOLA,
desserializacao, SQL — a feature nao introduz rede, credencial, banco nem
endpoint. O unico dado persistido e um marcador de processo em Markdown, sem
PII nem segredo.

## Complexity Tracking

| Violacao / custo | Por que necessario | Alternativa mais simples rejeitada porque |
|------------------|--------------------|-------------------------------------------|
| Alargar `_PL_STAGES_LIST` (10 -> 11), revogando decisao arquitetural registrada | FR-001 + FR-002 exigem a etapa na sequencia oficial, e a clarificacao estendeu a exigencia a execucao manual — gate na prosa do orquestrador nao alcanca quem nao usa orquestrador | manter gate in-phase (estado atual) nao atende US1/US2; criar `--mode` novo deixaria a etapa invisivel na sequencia oficial (research.md §Decision 2, §Decision 13) |
| Artefato novo por feature (`converge-report.md`) | e o unico lugar consultavel em execucao manual; sem ele FR-004 fica sem lastro e `detect-completion` fica arbitrario | marcador dentro do `tasks.md` polui o backlog e colide com o append-only de fases; so `state.json` nao cobre execucao manual (research.md §Decision 3) |
| Script novo `converge-status.sh` | Constitution III exige mecanica determinística em `scripts/`; fonte de verdade unica do formato evita N parsers divergentes | estender `converge-tasks.sh` misturaria backlog com status de processo (research.md §Decision 5) |
| Mudanca de contrato de skills ⇒ bump de versao + CHANGELOG | Constitution I MUST: alterar contrato (output/paths de saida) exige `spec.md` + bump + nota de BREAKING | nao aplicavel — e obrigacao constitucional, nao escolha |

## Re-check de Constitution (pos Phase 1)

| Principio | Status pos-design | Observacao |
|-----------|-------------------|------------|
| I | PASS | artefatos completos; bump + CHANGELOG previstos em F7 |
| II | PASS | design nao introduziu nenhuma dependencia; formato do marcador escolhido justamente para ser `grep`-avel sem `jq` |
| III | PASS | toda a mecanica nova vive em `scripts/`; `SKILL.md` so ganha fluxo e Gotchas |
| IV | PASS | inalterado |
| V | PASS | escopo concentrado em reduzir drift, sem features "de vitrine" |
| VI | PASS | contrato do script novo marcado como PROPOSTA; comportamento existente citado com path+linha |

O design **nao** introduziu camada, servico ou dependencia adicional: um script
POSIX novo, uma linha na lista canonica e um artefato Markdown por feature.

## Artefatos

| Arquivo | Status |
|---------|--------|
| docs/specs/pipeline-converge/plan.md | Criado |
| docs/specs/pipeline-converge/research.md | Criado |
| docs/specs/pipeline-converge/data-model.md | Criado |
| docs/specs/pipeline-converge/contracts/converge-status-cli.md | Criado |
| docs/specs/pipeline-converge/contracts/pipeline-stage-machine.md | Criado |
| docs/specs/pipeline-converge/quickstart.md | Criado |
