# Contract: commit-mode.sh — subcomandos snapshot + stage-derived

> **[PROPOSTA — a validar na implementacao]** — subcomandos NOVOS em
> `global/skills/agente-00c-runtime/scripts/commit-mode.sh` (522 linhas
> hoje; subcomandos existentes verificados: `is-enabled | set-enabled |
> guard-branch | stage-message | task-message | finalize` — NENHUM faz
> staging hoje; o staging amplo vive na prosa dos orquestradores e em
> `state-ondas.sh::_so_cmd_git_commit`, ver research Decision 1).

**Feature**: `living-specs` | FRs: FR-014, FR-015, FR-016, FR-017

## `snapshot`

```
commit-mode.sh snapshot --state-dir DIR --projeto-alvo-path PATH
```

Captura o conjunto de untracked ATUAL do repo
(`git status --porcelain`, linhas `?? `), paths ordenados por `sort`, e
grava em `DIR/commit-baseline.txt` (sidecar — mesmo padrao de
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
   (estados de `git status --porcelain` exceto `??`).
   **Seguranca (gate owasp pos-plan)**: leitura via
   `git -c core.quotepath=false status --porcelain` — porcelain v1 aplica
   quoting C-style a paths com caracteres especiais e usa formato
   `old -> new` em renames; parsing ingenuo derrubaria paths legitimos da
   allowlist ou passaria path errado ao `git add --`. Renames tratados
   (staged o path NOVO); teste cobre path com espaco e char nao-ASCII.
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
| `state-ondas.sh::_so_cmd_git_commit` (`git add -- .`) | delega staging a `stage-derived` (mesma skill dir); exit 3 => no-op "nada para commitar" (comportamento atual preservado) |

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
