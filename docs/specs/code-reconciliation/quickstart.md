# Quickstart: Code Reconciliation (`reconcile-docs`)

Cenarios de validacao end-to-end. Todos rodam sobre uma fixture versionada
(`tests/fixtures/reconcile-docs/` — [PROPOSTA]: projeto minimo com `docs/specs/`,
`docs/specs/_archived/`, `docs/specs/current/` e codigo shell de brinquedo) copiada para
um diretorio temporario com `git init`. Os cenarios de script sao cobertos pelos
`tests/test_<script>.sh`; os cenarios da skill inteira sao validados manualmente com
`/reconcile-docs` sobre a copia da fixture e, onde indicado, pelos trigger evals.

Verificacao comum "so documentacao" (usada nos cenarios 1, 5, 6 e 7):
`git status --porcelain` na copia da fixture lista apenas arquivos sob
`docs/specs/<feature>/` ou `docs/specs/_archived/<dir>/` com nome da allowlist, e
nenhum sob `docs/specs/current/` (SC-001).

## Scenario 1: Feature ativa com divergencias plantadas (US1, SC-002, SC-004)

1. Na fixture, a feature ativa `alpha` tem: FR SHOULD descrevendo uma flag cujo
   comportamento mudou no codigo; FR citando um arquivo removido; uma flag nova no
   codigo sem FR; um FR MUST contradito pelo codigo.
2. Rodar `/reconcile-docs alpha`.
3. **Expected**: FR SHOULD reescrito com `[reconciled:updated ...]`; FR do arquivo
   removido preservado com `[reconciled:removed ... evidence=absent:...]`; novo
   FR-NNN sequencial com `[reconciled:added ...]`; FR MUST intacto e listado como
   `possible-regression`; cada linha do relatorio cita `arquivo:linha`;
   `reconciliation.md` criado com 1 entrada; `markers.sh lint` passa em todos os
   documentos tocados; verificacao "so documentacao" OK.

## Scenario 2: Idempotencia (FR-012, SC-003)

1. Apos o Scenario 1, rodar `/reconcile-docs alpha` de novo.
2. **Expected**: relatorio "nenhuma divergencia encontrada" (o `possible-regression`
   continua reportado, sem escrita); `git status --porcelain` identico ao do fim do
   Scenario 1; `reconciliation.md` sem entrada nova.

## Scenario 3: Feature arquivada por nome sem data (US1 cenario 3)

1. Fixture tem `docs/specs/_archived/2026-01-15-beta/` e o legado
   `docs/specs/_archived/gamma/`.
2. Rodar `/reconcile-docs beta` e `/reconcile-docs gamma`.
3. **Expected**: ambas localizadas e reconciliadas (`locate-feature.sh` retorna
   `archived`, exit 0).

## Scenario 4: Nome inexistente e nome ambiguo (FR-014) — error case

1. Rodar `/reconcile-docs alph` (nao existe; `alpha` existe).
2. **Expected**: nada alterado; relatorio lista `alpha` como candidata
   (`locate-feature.sh` exit 3).
3. Fixture com `_archived/2026-01-01-delta/` e `_archived/2026-02-01-delta/`, sem ativa;
   rodar `/reconcile-docs delta`.
4. **Expected**: nada alterado; os dois diretorios listados como candidatos (exit 4).

## Scenario 5: Ativa + arquivada homonimas (FR-015)

1. Fixture tem `docs/specs/alpha/` e `docs/specs/_archived/2025-12-01-alpha/`.
2. Rodar `/reconcile-docs alpha`.
3. **Expected**: so a ativa e tocada; relatorio informa a existencia da arquivada.

## Scenario 6: `--all` com falha isolada (US2, FR-013, SC-006)

1. Fixture com 2 ativas + 2 arquivadas, uma delas sem nenhum documento da allowlist
   e outra com `spec.md` ilegivel (permissao 000).
2. Rodar `/reconcile-docs --all`.
3. **Expected**: relatorio consolidado com uma linha por feature localizada
   (`reconciled`/`no-divergence`/`skipped`/`error`); a ilegivel aparece como `error`
   e as demais foram processadas; verificacao "so documentacao" OK.

## Scenario 7: `--dry-run` (US4, FR-011, SC-007)

1. Restaurar a fixture ao estado do Scenario 1 passo 1; rodar
   `/reconcile-docs alpha --dry-run` e `/reconcile-docs --all --dry-run`.
2. **Expected**: relatorio com acoes `proposed-*` (documento, trecho, evidencia);
   `git status --porcelain` vazio; nenhum `reconciliation.md` criado.

## Scenario 8: Guarda de escrita e corpus canonico (FR-006, FR-017) — error case

1. `doc-guard.sh check` com: `docs/specs/current/x.md`; `docs/specs/alpha/tasks.md`;
   `docs/specs/alpha/research.md`; `cli/lib/foo.sh`; simlink
   `docs/specs/alpha/plan.md -> ../../../cli/lib/foo.sh`.
2. **Expected**: todos exit 1 com motivos `living-corpus`, `not-in-allowlist`,
   `not-in-allowlist`, `outside-feature`, `symlink-escape`;
   `docs/specs/alpha/spec.md` e `docs/specs/alpha/contracts/api.md` exit 0.

## Scenario 9: Sem git (FR-016, dec-035)

1. Copia da fixture SEM `git init` (ou `PATH` sem `git`); rodar `/reconcile-docs alpha`.
2. **Expected**: a skill RECUSA gravar e roda como `--dry-run` forcado: relatorio com
   acoes `proposed-*` iguais as do Scenario 1 e aviso `no-git-write-refused`
   (priorizacao e auditoria pos-execucao puladas); nenhum arquivo e criado ou alterado;
   `git-probe.sh status` retorna exit 0 com so `STATUS\tno-git` e
   `git-probe.sh can-write` retorna exit 3 com `WRITE\tdenied-no-git`.

## Scenario 10: Feature sem `spec.md` (Edge Case)

1. Feature `epsilon` com so `plan.md`.
2. Rodar `/reconcile-docs epsilon`.
3. **Expected**: nenhum `spec.md` criado; relatorio informa o documento ausente e
   reconcilia so `plan.md`; divergencia que exigiria novo FR vira `unverifiable`
   (sem `spec.md` nao ha onde numerar).

## Scenario 11: Trigger eval (disambiguacao com `converge`)

1. `tests/trigger-eval/gen-eval-cases.sh` apos adicionar
   `plugins/cstk/skills/reconcile-docs/evals/triggers.jsonl`.
2. **Expected**: casos `plugins/cstk/evals/reconcile-docs/NNN/case.yaml` gerados;
   consultas "documentacao segue o codigo" disparam `reconcile-docs`; consultas
   existentes de `converge` continuam esperando `converge`.

## Scenario 12: Projeto sem constitution (FR-007, CHK007) — error case

1. Copia da fixture SEM `docs/constitution.md` (ou com o arquivo ilegivel, permissao 000);
   `alpha` mantem o FR MUST contradito pelo codigo.
2. Rodar `/reconcile-docs alpha`.
3. **Expected**: a execucao nao falha; o FR MUST da propria feature continua reportado como
   `possible-regression` (sem escrita); nenhum principio de constitution e presumido;
   relatorio traz o aviso `constitution-unavailable`; demais divergencias reconciliadas
   como no Scenario 1.

## Scenario 13: Segredo no codigo citado como evidencia (FR-019, CHK011)

1. Fixture tem, no codigo de brinquedo, um segredo FICTICIO (ex.: atribuicao de uma chave
   de API de mentira) na linha que serve de evidencia para uma divergencia de `alpha`.
2. Rodar `/reconcile-docs alpha`.
3. **Expected**: o documento alterado, o marcador `[reconciled:... evidence=<path>:<line>]`
   e o relatorio trazem so `arquivo:linha`; o valor do segredo nao aparece em nenhum deles
   (`grep` do valor ficticio nos documentos da feature e na saida do relatorio = 0
   ocorrencias).

## Scenario 14: Confirmacao unica no `--all` (FR-020, dec-035)

1. Fixture com git e divergencias em `alpha` (ativa) e `2026-01-15-beta` (arquivada);
   rodar `/reconcile-docs --all` com operador presente.
2. **Expected**: a skill analisa todas as features, exibe o resumo do que mudara em cada
   uma e pede UMA confirmacao antes de gravar; recusada/sem resposta: nada e gravado
   (`git status --porcelain` vazio). Confirmada: grava como no Scenario 1 e o relatorio
   consolidado traz uma linha por feature.
3. Repetir em execucao nao interativa (sem operador presente): cai em `--dry-run`, acoes
   `proposed-*`, nada gravado.

## Medicao de SC-005 (amostragem manual — dec-035, CHK022)

Nao ha teste automatizado nem automacao nova: a medicao e manual, pelo dono do produto, apos
um periodo de uso real da skill.

1. **Amostra**: as reconciliacoes reais gravadas (entradas `## <data>` em
   `docs/specs/*/reconciliation.md` e `docs/specs/_archived/*/reconciliation.md`); a fixture de
   teste e execucoes `--dry-run` NAO contam.
2. **Contagem**: para cada divergencia de acerto pontual (`stale`, `removed`,
   `undocumented`; `possible-regression` e `unverifiable` ficam fora) da amostra, o dono do
   produto verifica se o documento ficou correto sem edicao manual posterior
   (`git log -p -- <doc>` apos a entrada do log mostra se houve edicao manual).
3. **Resultado**: `sem edicao manual / total do denominador`; meta >= 90%.
4. **Se abaixo de 90%**: abrir tarefa de ajuste em `references/` ou `SKILL.md`.

**Estado em 2026-09-30**: 0 reconciliacoes reais (o dogfooding da tarefa 6.4 foi somente
`--dry-run` e nao grava `reconciliation.md`); resultado pendente ate haver amostra.

