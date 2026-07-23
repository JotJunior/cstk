# Sessões paralelas (`cstk session`)

> **Trilha avançada** — suporte ao [orquestrador autônomo](./agente-00c.md).

Permite trabalhar em múltiplas features simultaneamente no mesmo repositório sem
colisão de working tree, branch HEAD ou `.claude/agente-00c-state/`. Isola cada
sessão em uma worktree git irmã do repo principal.

```bash
# Iniciar nova sessão (cria worktree + branch + .claude/ filtrado)
cstk session start iniciacao-membro
# → cria <parent>/<repo>-iniciacao-membro/ com branch iniciacao-membro

# Listar sessões ativas
cstk session list
# NAME              BRANCH              IDLE  STATUS   PATH
# iniciacao-membro  iniciacao-membro    0d    CURRENT  /home/jot/Projects/meta-gob-ms-iniciacao-membro
# oauth2-refresh    feat/oauth2         2d    *        /home/jot/Projects/meta-gob-ms-oauth2-refresh

# Abrir PR via gh (idempotente)
cstk session pr iniciacao-membro

# Encerrar sessão (com guards para dirty/unpushed/PR aberto)
cstk session end iniciacao-membro
# Ou forçar sem prompts:
cstk session end iniciacao-membro --force
```

## Subcomandos

- `start <name> [--reset|--reuse] [--force]` — cria worktree + branch + `.claude/`
  filtrado (exclui `agente-00c-state/`, `agente-00c-archive/`, `insights/`,
  `settings.local.json`, `agente-00c-whitelist`, `agente-00c-report.md`,
  `agente-00c-suggestions.md`, `.agente-00c-state.lock`)
- `list [--json]` — tabela com `NAME BRANCH IDLE STATUS PATH`; marcadores
  combináveis `CURRENT,*,STALE`
- `end <name> [--force]` — remove worktree + branch local; prompt se há
  mudanças não commitadas, commits não pushados ou PR aberto
- `pr <name> [--draft] [--title T] [--body B] [--reviewer USER]` — push + abre
  PR via `gh pr create`; idempotente (retorna URL existente se PR já criado)

**Requisitos**: `git >= 2.36`, `gh` (obrigatório só para `pr`; opcional em `end`).

## Documentação completa

- [`specs/_archived/cstk-session/spec.md`](./specs/_archived/cstk-session/spec.md) — user stories, FRs, success criteria
- [`specs/_archived/cstk-session/contracts/cli-session.md`](./specs/_archived/cstk-session/contracts/cli-session.md) — exit codes (5-15), flags, output formats
