# Contract — `cstk session` CLI

Contrato dos 4 subcomandos da feature `cstk-session`. Aderente ao
padrao de exit codes do `cstk` definido em `cli/cstk:35-40`
(`CSTK_EXIT_OK=0`, `CSTK_EXIT_ERROR=1`, `CSTK_EXIT_USAGE=2`,
`CSTK_EXIT_LOCK=3`, `CSTK_EXIT_LOCAL_EDIT=4`).

## Comando: `cstk session start <name>`

Cria worktree + branch + `.claude/` filtrado.

### Sinopse

```
cstk session start <name> [--reset|--reuse]
```

### Argumentos

| Arg | Tipo | Obrigatorio | Default |
|-----|------|-------------|---------|
| `<name>` | string (regex `^[a-z0-9][a-z0-9-]{0,62}$`) | sim | — |
| `--reset` | flag | nao | falso |
| `--reuse` | flag | nao | falso |

`--reset` e `--reuse` sao mutuamente exclusivos. Ambos passados = exit 2.

### Comportamento

1. Validar nome (regex + blocklist `main|master|trunk|head|default|origin`).
2. Resolver `git rev-parse --git-common-dir` para encontrar repo principal.
3. Calcular paths: `<parent>/<repo-name>-<name>` para worktree.
4. Verificar pre-condicoes (paths livres, branch nao mergeada se sem flags).
5. Criar worktree via `git worktree add <path> -b <branch>` (nova) ou
   `git worktree add <path> <branch>` (existente).
6. Copiar `.claude/` excluindo lista FR-002.
7. Imprimir instrucao de `cd`.

### Exit codes

| Code | Significado |
|------|-------------|
| 0 | Sessao criada |
| 1 | Erro generico (git falhou, IO falhou) — inclui falha parcial (worktree criada mas `.claude/` incompleto; stderr instrui cleanup via `cstk session end <name> --force`) |
| 2 | Uso incorreto (flags conflitantes, nome ausente) |
| 5 | Nome invalido (regex ou blocklist) |
| 6 | Sessao ja existe |
| 7 | Path destino ocupado por nao-worktree |
| 8 | Branch ja mergeada (sem `--reset`/`--reuse`) |
| 10 | Usuario cancelou prompt do `--reset` (commits seriam descartados) |
| 15 | `git` versao <2.36 (boot-check) |

### Stdout (sucesso)

```
✓ Sessao 'iniciacao-membro' criada
  branch: iniciacao-membro (nova)
  path:   /home/jot/Projects/meta-gob-ms-iniciacao-membro
  .claude/ copiado (8 exclusoes aplicadas)

Proximo passo: cd /home/jot/Projects/meta-gob-ms-iniciacao-membro
```

### Stderr (erros)

```
cstk session start: nome 'iniciacao_membro' invalido (use kebab-case: [a-z0-9-])
```

```
cstk session start: nome 'main' reservado (blocklist: main, master, trunk, head, default, origin); use prefixo como 'feat-main'
```

```
cstk session start: sessao 'iniciacao-membro' ja existe em /home/jot/Projects/meta-gob-ms-iniciacao-membro
```

```
cstk session start: branch 'iniciacao-membro' ja mergeada em main; use --reset para recriar do main, ou --reuse para forcar reutilizacao
```

---

## Comando: `cstk session list`

Lista sessoes ativas com status.

### Sinopse

```
cstk session list [--json]
```

### Comportamento

1. Resolver repo principal.
2. Parsear `git worktree list --porcelain`.
3. Para cada worktree (exceto principal):
   - Extrair name, branch, path, head_sha.
   - Calcular `idle_days` via `git log -1 --format=%ct`.
   - Calcular `dirty` via `git -C <path> status --porcelain`.
   - Detectar `stale` via campo `prunable`.
4. Ordenar por `idle_days` ASC (mais ativa primeiro).
5. Imprimir tabela ou JSON.

### Exit codes

| Code | Significado |
|------|-------------|
| 0 | Listagem feita (mesmo se zero sessoes) |
| 1 | Erro generico (repo nao-git, etc) |

### Stdout (tabela, default)

```
NAME              BRANCH              IDLE  STATUS         PATH
iniciacao-membro  iniciacao-membro    0d    CURRENT,*      /home/jot/Projects/meta-gob-ms-iniciacao-membro
oauth2-refresh    feat/oauth2         2d                   /home/jot/Projects/meta-gob-ms-oauth2-refresh
old-feat          old-feat            12d   STALE          /home/jot/Projects/meta-gob-ms-old-feat

tip: rode 'git worktree prune' para limpar worktrees stale
```

Coluna `STATUS` (marcadores combinaveis, separados por virgula):
- `CURRENT` = e a worktree atual (quando `list` rodado de dentro de uma sessao)
- `*` = `dirty` (mudancas nao commitadas)
- `STALE` = path nao existe no FS
- vazio = clean e nao-atual

### Stdout (JSON, `--json`)

```json
[
  {
    "name": "iniciacao-membro",
    "branch": "iniciacao-membro",
    "path": "/home/jot/Projects/meta-gob-ms-iniciacao-membro",
    "idleDays": 0,
    "dirty": true,
    "stale": false,
    "current": true
  },
  {
    "name": "old-feat",
    "branch": "old-feat",
    "path": "/home/jot/Projects/meta-gob-ms-old-feat",
    "idleDays": 12,
    "dirty": false,
    "stale": true,
    "current": false
  }
]
```

### Stdout (zero sessoes)

```
nenhuma sessao ativa
```

(exit 0)

---

## Comando: `cstk session end <name>`

Remove worktree + branch local com guards.

### Sinopse

```
cstk session end <name> [--force]
```

### Comportamento

1. Resolver sessao por nome (encontrar worktree em `git worktree list`).
2. Se nao encontrada: exit 9.
3. Detectar `dirty` (`git -C status --porcelain`).
4. Detectar `unpushed_commits` (`git -C rev-list <branch>..origin/<branch> --count`).
5. Detectar PR aberto via `gh pr view <branch> --json state` (opcional — pula se gh ausente/unauth).
6. Se `--force` nao passado E (dirty OU unpushed > 0 OU pr_open): prompt interativo.
7. Remover worktree via `git worktree remove <path>` (sem `--force` se clean).
8. Deletar branch local via `git branch -D <branch>`.
9. Imprimir confirmacao.

### Exit codes

| Code | Significado |
|------|-------------|
| 0 | Sessao removida |
| 1 | Erro generico |
| 2 | Uso incorreto |
| 9 | Sessao nao encontrada |
| 10 | Usuario cancelou prompt (resposta != y) |
| 14 | Rodado de dentro da propria worktree-alvo (recusa) |

### Stdout (sucesso)

```
✓ Sessao 'iniciacao-membro' removida
  worktree: /home/jot/Projects/meta-gob-ms-iniciacao-membro (removida)
  branch:   iniciacao-membro (deletada)
```

### Stderr (prompts)

```
⚠ Sessao 'iniciacao-membro' tem 3 arquivos modificados nao commitados.
⚠ Sessao 'iniciacao-membro' tem 2 commits nao pushados para origin/iniciacao-membro.
⚠ PR #42 ainda OPEN no GitHub (https://github.com/owner/repo/pull/42).
Confirmar remocao? [y/N]
```

### Stderr (gh ausente)

```
warning: PR check pulado: gh ausente/unauth
```

(processo continua normalmente)

---

## Comando: `cstk session pr <name>`

Abre PR via `gh` da branch da sessao para o default branch.

### Sinopse

```
cstk session pr <name> [--draft] [--title TITLE] [--body BODY] [--reviewer USER]
```

### Comportamento

1. Resolver sessao por nome. Se nao encontrada: exit 9.
2. Resolver default branch via `git symbolic-ref refs/remotes/origin/HEAD`.
3. Validar `gh` instalado E autenticado. Se nao: exit 11 ou 12.
4. Validar branch tem commits a frente do default: `git -C <path> rev-list <default>..<branch> --count > 0`.
5. Se PR ja existe (`gh pr view <branch> --json url,state`): imprime URL existente, exit 0.
6. Push da branch se nao pushada: `git -C <path> push -u origin <branch>`.
7. `gh pr create --base <default> --head <branch>` repassando flags.
8. Imprimir URL do PR.

### Exit codes

| Code | Significado |
|------|-------------|
| 0 | PR criado OU ja existia (idempotente) |
| 1 | Erro generico — inclui falha parcial (`git push` OK + `gh pr create` falhou; stderr instrui retry manual ou `git push -d origin <branch>` para desfazer) |
| 2 | Uso incorreto |
| 9 | Sessao nao encontrada |
| 11 | `gh` nao instalado |
| 12 | `gh` instalado mas nao autenticado (inclui credenciais expiradas — gh trata como unauth) |
| 13 | Branch sem commits novos |

### Stdout (sucesso)

```
✓ PR criado: https://github.com/owner/repo/pull/42
```

### Stdout (PR ja existe)

```
✓ PR ja existe: https://github.com/owner/repo/pull/42
```

(exit 0 — idempotente)

### Stderr (gh nao instalado)

```
cstk session pr: gh CLI nao instalado. Instale: https://cli.github.com
```

### Stderr (gh nao autenticado)

```
cstk session pr: gh nao autenticado. Rode: gh auth login
```

### Stderr (branch sem commits)

```
cstk session pr: branch 'iniciacao-membro' nao tem commits novos vs main
```

---

## Comando: `cstk session` (sem subcomando)

Imprime help curto + lista de subcomandos. Exit 2.

### Stdout

```
cstk session — sessoes paralelas isoladas via git worktree

USO:
  cstk session start <name> [--reset|--reuse]
  cstk session list [--json]
  cstk session pr <name> [--draft] [--title T] [--body B] [--reviewer U]
  cstk session end <name> [--force]

Help detalhado: cstk help session
```
