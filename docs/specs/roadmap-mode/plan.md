# Implementation Plan: roadmap-mode

**Feature**: `roadmap-mode`
**Spec**: [spec.md](./spec.md)
**Created**: 2026-08-14
**Status**: Draft

## Summary

Introduzir no `/agente-00c` um **modo roadmap** opt-in: a pipeline
executa apenas `briefing → constitution → roadmap` e encerra em estado
terminal de sucesso, produzindo `docs/roadmap.md` — a lista ordenada de
features sugeridas, cada uma consumivel diretamente pelo `/feature-00c`.

A abordagem tecnica e **estritamente aditiva**. O achado que define o
desenho: nenhuma das tres mudancas estruturais que pareciam necessarias
de fato e. (a) O flag do modo nao exige migracao de schema — campos
top-level nao modelados ja fazem round-trip pela coluna catch-all
`extra_fields` (verificado por probe empirico). (b) A etapa `roadmap`
nao entra na lista linear de etapas — entra numa lista escopada por
modo, deixando o caminho default byte-identico. (c) O encerramento
terminal nao usa `--advance --terminal-phase` (que e fail-closed por
desenho) e sim `--motivo-termino concluido` + promocao explicita de
status, seguindo o precedente do `reconcile-wave`.

O resultado e uma feature de superficie pequena: 2 helpers POSIX novos,
4 flags aditivas em helpers existentes, prosa condicional em 1 command e
1 orquestrador, e uma secao nova no relatorio de portfolio.

## Technical Context

| Campo | Valor |
|---|---|
| **Linguagem** | POSIX `sh` (helpers de runtime e scripts de skill) + Markdown (prosa de catalogo: commands, agents, skills) |
| **Projeto-alvo** | O proprio toolkit: `/Users/jot/Projects/_lab/Jot/misc/cstk` |
| **Dependencias novas** | **Nenhuma.** Nenhum carve-out de dependencia opcional e invocado |
| **Armazenamento** | Artefato Markdown versionado em git (`docs/roadmap.md`) + 1 campo booleano no estado de execucao |
| **Backends de estado** | JSON e SQLite — ambos suportados sem migracao |
| **Testes** | Harness POSIX do repo (`tests/run.sh`); regra de ouro: todo `.sh` novo em `plugins/cstk/skills/*/scripts/` exige `tests/test_<nome>.sh`, verificavel por `./tests/run.sh --check-coverage` |
| **Plataforma** | macOS/zsh em dev, Linux em CI — sem GNU-ismos (`sed -i` estilo GNU, `timeout`) |
| **Tipo de projeto** | Toolkit CLI + catalogo de skills; single-layer |
| **NEEDS CLARIFICATION** | 0 |

## Constitution Check

*GATE: passou antes do Phase 0. Re-checado apos Phase 1 (§Re-check).*

| Principio | Status | Notas |
|---|---|---|
| **I. SDD aplica-se recursivamente** (MUST) | PASS | A feature tem `spec.md`, e este plano, e sera decomposta em `tasks.md`. Ironicamente reforca o principio: o modo roadmap existe para que projetos grandes sejam particionados em features especificadas individualmente, em vez de uma spec inicial gigante |
| **II. POSIX sh puro, zero dep externa** (MUST) | PASS | Os 2 scripts novos usam apenas `grep`/`sed`/`awk`/`test`. `jq` **nao** e usado em nenhum deles — o parser do roadmap foi desenhado para ser ancoravel em `^` linha a linha justamente por isso (research.md D6). Precedente direto: `aggregate.sh`, jq-free. Nenhum carve-out do amendment 1.1.0 e invocado |
| **III. Formato canonico de skill** (MUST) | PASS | Nenhuma skill nova e criada. A alteracao no `review-features` respeita a anatomia: logica pesada em `scripts/`, `SKILL.md` so aponta. Se a geracao do roadmap vier a ser extraida para skill propria, herda a exigencia de `## Gotchas` |
| **IV. Zero coleta remota** (MUST) | PASS | Nenhuma comunicacao externa. O artefato e local e versionado no projeto-alvo |
| **V. Profundidade > metricas de adocao** (SHOULD) | PASS | A feature ataca retrabalho real (a "feature inicial gigante"), nao adiciona superficie por adicionar |
| **VI. Veracidade de dados** (MUST) | PASS | Ver §Aplicacao do Principio VI |

### Aplicacao do Principio VI

Duas frentes, ambas tratadas explicitamente:

1. **Neste plano**: toda afirmacao sobre o comportamento atual do
   toolkit foi lida do codigo-fonte, com path e linha, ou verificada por
   probe executado (research.md D1). Contratos novos estao marcados
   `[PROPOSTA — a validar na implementacao]`, distintos de descricoes de
   comportamento existente.
2. **No artefato gerado**: `Descricao` e `Justificativa` de uma entrada
   sao **propostas de escopo** — julgamento de design, permitido. Dado
   factual concreto (endpoint, nome de campo de API, valor) exige fonte
   rastreavel; sem fonte, o texto descreve a capacidade sem afirmar
   fatos externos. Regra normativa em
   `contracts/roadmap-artifact.md` §3.4 (FR-008).

## Project Structure

### Documentacao (feature)

```
docs/specs/roadmap-mode/
├── spec.md                            # existente
├── plan.md                            # este documento
├── research.md                        # Phase 0 — 8 decisoes
├── data-model.md                      # Roadmap, EntradaDeRoadmap, flag de modo
├── quickstart.md                      # 10 cenarios de teste
└── contracts/
    ├── roadmap-artifact.md            # formato canonico de docs/roadmap.md
    └── cli-roadmap-mode.md            # superficie CLI (flags e exit codes)
```

### Codigo-fonte (arvore real do repo)

```
plugins/cstk/
├── commands/
│   └── agente-00c.md                  # [MOD] prompt de opt-in + --roadmap-mode no init
├── agents/
│   └── agente-00c-orchestrator.md     # [MOD] pipeline/terminal condicionados ao modo
└── skills/
    ├── agente-00c-runtime/scripts/
    │   ├── roadmap-mode.sh            # [NOVO] is-enabled | set-enabled
    │   ├── state-rw.sh                # [MOD] flag --roadmap-mode no init
    │   ├── pipeline.sh                # [MOD] --mode + arm detect-completion roadmap
    │   ├── state-ondas.sh             # [MOD] passthrough --mode em end --advance
    │   └── report.sh                  # [MOD] secao de roadmap no relatorio final (FR-004)
    └── review-features/
        ├── SKILL.md                   # [MOD] secao de cruzamento roadmap x portfolio
        └── scripts/
            └── roadmap-status.sh      # [NOVO] cruzamento, POSIX puro

tests/
├── test_roadmap-mode.sh               # [NOVO] regra de ouro
├── test_roadmap-status.sh             # [NOVO] regra de ouro
├── test_pipeline.sh                   # [MOD] --mode; assercao das 10 etapas INTACTA
├── test_state-ondas.sh                # [MOD] passthrough --mode
├── test_state-rw.sh                   # [MOD] --roadmap-mode
└── test_command-spawn-*.sh            # [MOD] prose-lint do novo bloco no command
```

**Explicitamente NAO tocados** (consequencia de research.md D1):
`references/state-db-schema.sql`, `_state-rw-db.sh`, `state-db-migrate.sh`.

## Convencoes de Borda

**N/A — single-layer.**

A feature nao atravessa fronteira backend↔frontend, DB↔backend nem
broker↔consumer. Ela produz um artefato Markdown lido por humanos e por
scripts POSIX no **mesmo processo e mesma maquina**; nao ha serializacao
entre linguagens, nao ha DTO, nao ha mapper, nao ha payload de rede.

A unica convencao de nomenclatura relevante e a de identidade da entrada
— **kebab-case** para `short-name` — e ela nao e escolha nova: e imposta
pela regex que o `/feature-00c` ja aplica
(`^[a-z][a-z0-9-]*$`, `plugins/cstk/commands/feature-00c.md:93`). A
fonte da verdade dessa convencao e o command consumidor, e esta
declarada em `contracts/roadmap-artifact.md` §3.1 e §7.

Pelo mesmo motivo, o cenario "Roundtrip End-to-End" do template de
quickstart nao se aplica (registrado em `quickstart.md`).

## Abordagem de implementacao

Ordem sugerida, do nucleo testavel para a prosa que o consome.

### Fase A — Fundacao de estado e pipeline (habilita todo o resto)

1. `state-rw.sh`: flag `--roadmap-mode true|false` no `init`, espelhando
   `--atomic-commit` (mesma validacao, mesmo exit 2, mesmo default
   `false`). Atualizar o header do script para listar a flag nova — e,
   na mesma passagem, `--atomic-commit`, hoje ausente do header.
2. `roadmap-mode.sh` `[NOVO]`: `is-enabled` (stdout `true|false`, **exit
   0 sempre**) e `set-enabled` (0/1/2), espelhando `commit-mode.sh`.
3. `pipeline.sh`: flag `--mode` em `stages`/`next-stage`/`prev-stage`
   com lista escopada `briefing constitution roadmap`; `_PL_STAGES_LIST`
   **inalterada**.
4. `pipeline.sh`: arm `detect-completion --stage roadmap` com a
   validacao estrutural do contrato §6, seguindo o padrao de fallback
   PAP ja usado por `briefing`/`constitution` (artefatos project-level).
5. `state-ondas.sh`: passthrough `--mode` em `end --advance`; `--mode`
   sem `--advance` ⇒ exit 2.

### Fase B — Contrato do artefato

6. Validador estrutural do roadmap (consumido pelo passo 4), com as 8
   regras do contrato §6.
7. `roadmap-status.sh` `[NOVO]`: cruzamento roadmap↔portfolio, POSIX
   puro, saida markdown + `--json`.

### Fase C — Prosa de catalogo

8. `agente-00c.md`: bloco de prompt do opt-in (posicao, default seguro,
   afirmativas, nao-interativo cai no default) + `--roadmap-mode` no
   `init`.
9. `agente-00c-orchestrator.md`: condicionar ao modo — a cadeia de
   etapas descrita, o `--terminal-phase` hardcoded, o gatilho do hook de
   finalize (hoje amarrado a `review-features`) e a prosa de promocao de
   status terminal.
10. `review-features/SKILL.md`: secao de cruzamento, invocando
    `roadmap-status.sh` de forma **best-effort** — projeto sem
    `docs/roadmap.md` produz o relatorio atual, sem falhar. A prosa MUST
    cercar como **UNTRUSTED** qualquer descricao do roadmap reproduzida
    no relatorio (contrato do artefato §9.1).
11. `report.sh`: secao de roadmap no relatorio final (FR-004). O
    gerador de relatorio tem hoje 6 secoes fixas; o modo roadmap
    acrescenta a renderizacao do roadmap (features, ordem, dependencias)
    **condicionada ao modo** — execucao fora do modo mantem o relatorio
    atual inalterado. **Dono da sugestao de entrada unica** (FR-007,
    2a clausula): e esta secao do relatorio que MUST emitir a sugestao
    explicita de considerar a pipeline completa quando o roadmap tem
    exatamente 1 entrada.

> **Reuso de briefing/constitution (FR-002, 2a clausula)**: nenhum passo
> e necessario. O comportamento ja emerge do gate de conclusao existente
> — artefato foundation valido ⇒ etapa concluida ⇒ orquestrador avanca
> sem invocar a skill. Contratado explicitamente em
> `contracts/cli-roadmap-mode.md` §3.2 para que ninguem "implemente" um
> reuso que ja existe.

### Fase D — Testes

11. `tests/test_roadmap-mode.sh` e `tests/test_roadmap-status.sh`
    `[NOVOS]` (regra de ouro; `--check-coverage` falha sem eles).
12. Extensoes **aditivas** em `test_pipeline.sh`, `test_state-ondas.sh`,
    `test_state-rw.sh` e nos prose-lint de command.
13. Cenario 1 do quickstart como gate de nao-regressao.

## Riscos e mitigacoes

| Risco | Mitigacao |
|---|---|
| Regressao silenciosa na pipeline default (SC-003) | `_PL_STAGES_LIST` intocada + assercao existente das 10 etapas preservada **sem edicao**. Se uma assercao existente precisar mudar para passar, a mudanca nao e aditiva — parar e redesenhar (quickstart cenario 1.5) |
| Ponteiro de fase avancar para `specify` em modo roadmap | Passthrough `--mode` no `end --advance` (research.md D8). Sem ele, o fechamento da onda de `constitution` grava a fase errada no mesmo write atomico — falha silenciosa e invisivel ao `reconcile-wave` |
| Parser do roadmap fragil | Formato desenhado para parse por prefixo literal ancorado em `^`, um valor por linha; comandos de extracao de referencia versionados no contrato §4, e quebra-los e mudanca breaking declarada |
| Cruzamento invisivel para feature sem `tasks.md` | Script proprio em vez de estender `aggregate.sh`, que por contrato so enxerga dirs com `tasks.md` (research.md D7); coberto pelo quickstart cenario 8.2 |
| Prosa de catalogo editada mas nao sincronizada com a copia instalada | Drift `installed vs source` e modo de falha conhecido do repo: apos editar catalogo, `cstk install --from <tarball local>`; runtime de `cli/lib` exigiria `self-update` — **nao e o caso aqui**, esta feature nao toca `cli/lib` |
| Roadmap com dado factual inventado nas descricoes | Regra normativa no contrato §3.4 (FR-008); auditavel pelo subagente de veracidade sobre `docs/roadmap.md` antes do encerramento |

## Complexity Tracking

Nenhuma violacao de constitution a justificar. A feature **reduz**
complexidade face ao desenho ingenuo: o probe empirico de research.md D1
eliminou uma migracao de schema em 4 arquivos, e a decisao D2 eliminou a
mudanca na lista de etapas que teria exigido alterar teste existente.

## Re-check de Constitution (pos-Phase 1)

Revalidado apos o design, com atencao aos dois principios de maior risco:

- **Principio II**: o design de contrato (§Decision 6 do research)
  garante parse em `grep`/`sed`/`awk`; nenhum dos 2 scripts novos
  precisa de `jq`. **Continua PASS** — e nao por inercia: foi o
  requisito de parse POSIX que **ditou** o formato do artefato, nao o
  contrario.
- **Principio VI**: o design introduziu um artefato cujo conteudo e
  gerado por LLM — superficie real de fabricacao. Mitigado por regra
  normativa explicita (contrato §3.4) que separa proposta de escopo
  (permitida) de afirmacao factual (exige fonte). **Continua PASS**.
- Nenhuma camada, servico ou dependencia adicional foi introduzida pelo
  design. **Sem novas violacoes.**

## Artefatos

| Arquivo | Status |
|---|---|
| `docs/specs/roadmap-mode/plan.md` | Criado |
| `docs/specs/roadmap-mode/research.md` | Criado |
| `docs/specs/roadmap-mode/data-model.md` | Criado |
| `docs/specs/roadmap-mode/contracts/roadmap-artifact.md` | Criado |
| `docs/specs/roadmap-mode/contracts/cli-roadmap-mode.md` | Criado |
| `docs/specs/roadmap-mode/quickstart.md` | Criado |
