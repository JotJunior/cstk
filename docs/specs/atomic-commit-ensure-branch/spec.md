# Feature Specification: Garantia de branch para o modo atomic-commit

**Feature**: `atomic-commit-ensure-branch`
**Created**: 2026-08-13
**Status**: Draft

## Contexto

O modo atomic-commit (feature `atomic-commit-pr`) e opt-in no inicio de
cada execucao `agente-00c`/`feature-00c`. Quando habilitado, o
orquestrador comita por etapa e por task — mas TODO commit passa antes
pelo `commit-mode.sh guard-branch` (FR-005 da atomic-commit-pr), que
recusa (exit 3, nao-fatal) quando `HEAD` esta na branch default. O
orquestrador entao pula o commit silenciosamente ("skip silencioso").

Caso real observado (execucao feature-00c em projeto-alvo na branch
`main`, 2026-08-13): o operador habilitou atomic-commit, a onda-001
concluiu `specify`, o guard-branch bloqueou o commit da etapa e o
`spec.md` so foi capturado pela rede de seguranca do command pai
(commit local do passo 6 do contrato). O padrao se repetiria em TODAS as
ondas seguintes: o modo escolhido pelo operador nunca opera, sem nenhum
aviso no momento da escolha.

A causa nao e o guard-branch (que esta correto como defesa) — e a
ausencia de qualquer passo que garanta uma branch nao-default ANTES de a
execucao comecar, no unico momento em que ha um humano presente para
consentir: o prompt de opt-in.

### Por que NAO um tool MCP

Avaliado e descartado:

1. O servidor MCP de estado e opcional e degradavel por desenho
   (SC-004 da state-mcp-server): sem Docker, tudo cai em
   `mode=bash-fallback`. Uma garantia nao pode morar numa camada que
   desaparece silenciosamente.
2. O confinamento do container (FR-013) monta APENAS state-dir, scripts
   `ro` e enforcement-log — deliberadamente NAO monta a working tree do
   projeto. Um tool que muta git exigiria montar o repo `rw`,
   contradizendo o modelo de seguranca.
3. A branch precisa existir UMA vez, antes do spawn do orquestrador —
   exatamente o momento do preflight do command pai, nao uma chamada de
   tool em runtime.

## User Scenarios & Testing

### US1 — Operador habilita atomic-commit estando na branch default

Operador invoca `/feature-00c` (ou `/agente-00c`) com `HEAD` em `main` e
responde "sim" ao prompt de atomic-commit. O command pai cria (ou troca
para) a branch de feature ANTES do init do estado; todas as ondas
seguintes comitam normalmente (guard-branch exit 0).

### US2 — Operador habilita atomic-commit ja numa branch de trabalho

Operador ja esta em `feature/minha-feature` (ex.: via `cstk session
start`). O passo de garantia e no-op observavel (reporta a branch
corrente) e nada muda.

### US3 — Retomada/reopen herdam a garantia

`/feature-00c-resume`, `/agente-00c-resume` e o modo `--reopen` (que
herdam `.atomic_commit_enabled` sem re-promptar, FR-022 da
feature-reopen) re-executam a garantia de forma idempotente antes de
spawnar o orquestrador — cobre o caso do operador que voltou manualmente
para `main` entre ondas.

## Requirements

### FR-001

`commit-mode.sh` MUST ganhar o subcomando `ensure-branch
--projeto-alvo-path PATH --short-name NAME [--prefix PREFIX/]` (prefix
default `feature/`; `/feature-00c` usa o default e `/agente-00c` passa
`--prefix agente-00c/`), que garante `HEAD` fora da branch default do
repo em PATH:

- `HEAD` ja fora da default (mesma regra de resolucao de default do
  `guard-branch`: `origin/HEAD` autoritativo quando ha remote; convencao
  `main`/`master` sem remote) ⇒ no-op; stdout `noop <branch-corrente>`,
  exit 0.
- `HEAD` na default e a branch `feature/<short-name>` NAO existe ⇒ criar
  e trocar (`git checkout -b`); stdout `created feature/<short-name>`,
  exit 0.
- `HEAD` na default e `feature/<short-name>` JA existe ⇒ trocar para ela
  (`git checkout`); stdout `switched feature/<short-name>`, exit 0.

### FR-002

`ensure-branch` MUST ser fail-loud nos erros: git ausente no PATH, PATH
nao e repositorio git, ou o checkout falhou (ex.: working tree com
conflito) ⇒ exit 1 com motivo em stderr. Flag faltando ou `--short-name`
invalido ⇒ exit 2 (erro de uso). Nenhum estado e mutado em caminho de
erro alem do que o proprio `git checkout` reportou.

### FR-003

`--short-name` MUST ser validado como token (`[A-Za-z0-9._-]`, ate 64
chars, sem espaco/prosa) ANTES de qualquer invocacao git — mesmo padrao
fail-closed do `--add-etapa` de `state-ondas.sh`.

### FR-004

Os commands `/feature-00c` e `/agente-00c` MUST invocar `ensure-branch`
quando (e somente quando) o modo atomic-commit resulta habilitado no
init — imediatamente apos o prompt de opt-in (ou apos a heranca do round
anterior no modo `--reopen`), ANTES do `state-rw.sh init`. O texto do
prompt MUST avisar que habilitar cria/troca para a branch de feature
quando `HEAD` esta na default. Para `/agente-00c` (sem short-name), o
nome MUST derivar do mesmo identificador ja usado pelo `stage-message`
(descricao do projeto normalizada), prefixado `agente-00c/`.

### FR-005

Os commands de resume (`/feature-00c-resume`, `/agente-00c-resume`) MUST
invocar `ensure-branch` (idempotente) antes de spawnar o orquestrador
quando `commit-mode.sh is-enabled` retorna `true`.

### FR-006

Falha do `ensure-branch` nos commands MUST ser reportada ao operador com
a saida do git e a remediacao (`cstk session start <nome>` como
alternativa de isolamento total); no fluxo interativo o operador decide
entre corrigir e prosseguir sem atomic-commit (`_atomic=false`); nos
fluxos sem prompt (resume/reopen) a falha vira aviso e a execucao segue
— o guard-branch existente permanece como defesa em profundidade
(skip por onda), NUNCA e removido.

## Success Criteria

- **SC-001**: habilitar atomic-commit numa execucao iniciada em `main`
  produz commits por etapa/task a partir da onda-001, sem intervencao
  manual de branch.
- **SC-002**: `ensure-branch` e idempotente — duas invocacoes seguidas
  produzem o mesmo estado final e exit 0.
- **SC-003**: nenhuma mudanca de comportamento quando o modo
  atomic-commit esta desabilitado (caminho opt-out intocado, SC-006 da
  atomic-commit-pr preservado).

## Out of Scope

- Tool MCP de mutacao git (ver "Por que NAO um tool MCP").
- Push/PR da branch criada (ja coberto por `commit-mode.sh finalize`).
- Remocao ou afrouxamento do `guard-branch` (FR-005 da atomic-commit-pr
  permanece integral).
- `cstk session start` automatico (worktree e mais pesado; permanece
  como remediacao sugerida, nao como pre-requisito).
