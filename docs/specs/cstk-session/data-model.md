# Data Model — cstk-session

A feature deriva 100% do estado mantido pelo git em `.git/worktrees/`.
Nao introduz storage proprio. Esta secao documenta o modelo conceitual
para alinhar a implementacao com a spec.

## Entity: Session

Representa uma sessao paralela de trabalho. Materializada como uma
worktree do git + branch git associada.

### Atributos (derivados)

| Campo | Tipo | Origem | Descricao |
|-------|------|--------|-----------|
| `name` | string | derivado | `basename` do path da worktree, com prefixo `<repo-name>-` removido. Ex: worktree `/home/u/proj-feat-a` → name `feat-a`. |
| `branch` | string | `git worktree list --porcelain` | Branch checked out na worktree. Ex: `feat-a`. |
| `path` | string (abs) | `git worktree list --porcelain` | Path absoluto da worktree. |
| `head_sha` | string | `git worktree list --porcelain` | SHA do HEAD atual. |
| `idle_days` | int | `git log -1 --format=%ct <branch>` | Dias inteiros desde o ultimo commit no branch (commit time epoch). |
| `dirty` | bool | `git -C <path> status --porcelain` | `true` se output nao vazio (mudancas nao commitadas). |
| `unpushed_commits` | int | `git rev-list <branch>..origin/<branch>` ou `--count` | Numero de commits a frente do remote tracking (0 se branch nao trackeada remotamente — caso "branch nova ainda nao pushada"). |
| `stale` | bool | `prunable` field em `git worktree list --porcelain` | `true` se path FS nao existe ou git marcou como prunable. |
| `current` | bool | `git rev-parse --show-toplevel` == `path` | `true` se a worktree atual (de onde `list` foi rodado) e esta sessao. |
| `is_main` | bool | derivado | `true` para a worktree principal (a primeira listada pelo git). Filtrada antes de apresentar. |

### Estados (lifecycle)

```
        (cstk session start)
            |
            v
        +--------+
        | active |---(commit/edit) ----> dirty (status field, not state)
        +--------+
            |
            +---(cstk session pr) -----> pr_open (gh state, not local)
            |
            +---(cstk session end --force) ----+
            |                                  |
            +---(end clean + confirmar) ------>+
                                               v
                                          (removed)
```

Nao ha state machine formal — o estado e derivado a cada query.
"Active" = worktree existe em `.git/worktrees/`. "Removed" = nao existe.

### Invariantes

- **INV-1**: `name` e unico por repo (garantido pelo path do worktree ser
  unico no FS — duas worktrees com mesmo nome implicaria `cp` recusado).
- **INV-2**: `branch` da sessao difere do branch da worktree principal
  (git proibe duas worktrees compartilharem branch — `cannot lock ref`).
- **INV-3**: Stale implica `path` nao existe no FS. List filtra ou
  marca conforme FR-007.
- **INV-4**: `idle_days >= 0`. Se `git log` falhar (branch sem commits),
  trataremos como `idle_days = -1` e exibiremos `-` no output.

### Relacionamentos

| Entidade | Relacao | Cardinalidade |
|----------|---------|----------------|
| Repo principal | hospeda | 1 repo → 0..N Sessions |
| Branch git | implementa | 1 Session ↔ 1 Branch |
| PR GitHub (opcional) | referencia | 1 Session → 0..1 PR aberto |

### Operacoes

| Operacao | Pre-condicao | Pos-condicao | Side effects |
|----------|--------------|--------------|--------------|
| `create(name)` | name valido + nao em blocklist + sessao inexistente + path destino livre | Session existe em `.git/worktrees/<name>` | worktree criada; branch criada/reutilizada; `.claude/` filtrado copiado |
| `read_all()` | repo e git | array de Sessions (excluindo a principal) | nenhum |
| `delete(name, force?)` | sessao existe | sessao removida do git | worktree dir removido; branch local deletada; warnings se dirty/unpushed/pr-open |
| `open_pr(name, flags)` | sessao existe + branch tem commits novos + gh autenticado | PR existe no GitHub | push para origin; gh pr create |

## Naming convention

| Nivel | Padrao | Exemplo |
|-------|--------|---------|
| Session name (input) | `^[a-z0-9][a-z0-9-]{0,62}$`, excluindo blocklist | `iniciacao-membro` |
| Branch name | `<name>` direto (sem prefixo, default) ou `<CSTK_SESSION_PREFIX><name>` se env setada | `iniciacao-membro` ou `feat/iniciacao-membro` |
| Worktree path | `<parent-of-repo>/<repo-name>-<name>` | `/home/jot/Projects/meta-gob-ms-iniciacao-membro` |
| `.claude/` da sessao | `<session-path>/.claude/` | mesmo do worktree path + `/.claude` |
