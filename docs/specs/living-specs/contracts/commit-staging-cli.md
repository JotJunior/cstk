# Contract: commit-mode.sh — subcomandos snapshot + stage-derived

> **[IMPLEMENTADO — living-specs FASE 5]** — subcomandos `snapshot` e
> `stage-derived` em
> `global/skills/agente-00c-runtime/scripts/commit-mode.sh` (subcomandos
> pre-existentes: `is-enabled | set-enabled | guard-branch | stage-message
> | task-message | finalize` — nenhum fazia staging; o staging amplo vivia
> na prosa dos orquestradores e em `state-ondas.sh::_so_cmd_git_commit`,
> ver research Decision 1).
>
> **Divergencia medida vs proposta original**: `git -c core.quotepath=false
> status --porcelain` (sem `-z`) AINDA envolve em aspas duplas C-style
> qualquer path contendo um espaco — comportamento observado
> empiricamente, independente de `core.quotepath` (que so controla o
> octal-escaping de bytes nao-ASCII, nao a quotacao por espaco). Como
> nomes de arquivo com espaco sao o caso mais comum (nao um edge case
> raro), a implementacao usa `git status --porcelain -z
> --untracked-files=all` (paths NUL-terminados, NUNCA quoted, formato de
> rename tambem NUL-delimitado sem a seta ` -> `) e converte para 1 linha
> por campo via `tr '\0' '\n'` (paths nao contem NUL; newline literal em
> nome de arquivo fica fora de escopo — mesma limitacao aceita pelo
> restante do runtime POSIX). `--untracked-files=all` tambem medido
> como necessario: sem ele, git colapsa um diretorio INTEIRO-untracked
> (ex: uma feature nova sob `docs/specs/`) numa unica entrada `?? dir/`
> em vez de listar cada arquivo — quebrando o casamento por prefixo de
> `--scope-dir` sempre que o primeiro arquivo tocado vive num diretorio
> que ainda nao existe no repo.

**Feature**: `living-specs` | FRs: FR-014, FR-015, FR-016, FR-017

## `snapshot`

```
commit-mode.sh snapshot --state-dir DIR --projeto-alvo-path PATH
```

Captura o conjunto de untracked ATUAL do repo
(`git status --porcelain -z`, entradas `?? `), paths ordenados por `sort`,
e grava em `DIR/commit-baseline.txt` (sidecar — mesmo padrao de
`tool-call-ticks.log`: nunca dentro do `state.json`, nunca versionado).
Sobrescreve baseline anterior (1 baseline por onda; chamado pelo
orquestrador na abertura de onda `execute-task` com atomic habilitado, e
pelo caminho de wave-commit do agente-00c).

Exit: 0 gravado; 1 erro git/IO; 2 uso incorreto.

## `stage-derived`

```
commit-mode.sh stage-derived --state-dir DIR --projeto-alvo-path PATH \
  [--scope-dir REL_DIR]...
```

Computa a CommitAllowlist (data-model) e faz staging explicito:

1. `tracked_changed` = paths com mudanca em arquivos ja rastreados
   (estados de `git status --porcelain -z` exceto `??`).
   **Seguranca (gate owasp pos-plan)**: leitura via
   `git status --porcelain -z` — a variante `-z` nunca quota/escapa paths
   (independe de `core.quotepath`; a variante sem `-z` quota qualquer path
   com espaco em aspas C-style mesmo com `core.quotepath=false`, medido
   empiricamente) e usa formato NUL-delimitado para renames (path novo,
   NUL, path antigo, NUL — sem a seta ` -> ` textual, que so existe no
   formato humano/sem `-z`); parsing ingenuo derrubaria paths legitimos da
   allowlist ou passaria path errado ao `git add --`. Renames tratados
   (staged o path NOVO, path antigo descartado); teste cobre path com
   espaco, char nao-ASCII e rename.
2. `untracked_new` = untracked atuais MENOS `DIR/commit-baseline.txt`
   (`comm -13` sobre listas ordenadas). Baseline AUSENTE => conjunto
   vazio + aviso em stderr (fail-closed: untracked nunca entram sem
   baseline; jamais fallback amplo).
3. `allowlist` = `tracked_changed` + `untracked_new`; se >=1
   `--scope-dir`, filtrada aos paths sob esses prefixos relativos.
4. Allowlist vazia => exit 3, NENHUM `git add` executado (caller pula o
   commit — FR-016, sem commit vazio).
5. Senao: `git add -- <path>` por entrada (paths deletados via
   `git add --` tambem registram a delecao). PROIBIDO `git add -A`,
   `git add .`, `git add --all` em qualquer caminho do codigo (FR-014).

Exit: 0 staged >=1 path; 3 allowlist vazia (nada a commitar); 1 erro git;
2 uso incorreto. Erros emitem `DIAG|` (envelope `_diag.sh`, ja sourceable
same-dir no runtime).

## Regimes de chamada (quem chama, com o que)

| Site (hoje com staging amplo) | Chamada nova |
|-------------------------------|--------------|
| prosa passo 10.qui (etapa) — feature-orchestrator | `stage-derived --scope-dir docs/specs/<feature> --scope-dir .claude/feature-00c-state/<short>` |
| prosa passo 7.bis (task) — feature-orchestrator | `snapshot` na abertura da onda + `stage-derived` (sem scope-dir) |
| prosa equivalente — agente-00c-orchestrator (2 sites) | idem, com state dir `.claude/agente-00c-state` |
| `state-ondas.sh::_so_cmd_git_commit` (`git add -- .`) | delega staging a `stage-derived` (mesma skill dir; sem scope-dir); exit 3 => no-op "nada para commitar" (comportamento atual preservado). O `snapshot` NAO acontece aqui — `state-ondas.sh start` (inicio de TODA onda) chama `commit-mode.sh snapshot` best-effort via `.execution.target_project_path` do proprio `state.json`, exatamente como a Entity UntrackedBaseline ja especificava ("escrito... no inicio da onda"); `git-commit` e a ULTIMA etapa da onda e snapshotar ali mesmo daria diff sempre vazio (zero janela de tempo — divergencia medida vs tasks.md 5.4.1, corrigida sem exigir mudanca de prosa nos orquestradores chamadores) |

## Regressao obrigatoria (FR-017, SC-003)

`tests/test_commit-mode.sh` (existente) ganha cenarios com fixture git
contendo arquivo untracked alheio pre-existente (analogo ao `.pptx` do
incidente):

1. commit de etapa (scope-dirs) => alheio permanece untracked;
2. commit de task (baseline + arquivo novo criado pos-snapshot) => novo
   entra, alheio fica fora;
3. baseline ausente => untracked todos fora + aviso;
4. allowlist vazia => exit 3 e nenhum commit;
5. `state-ondas.sh git-commit` pos-mudanca => alheio fora
   (`tests/test_state-ondas.sh` estendido).
