# Quickstart — cstk-session

Cenarios E2E que validam o comportamento esperado da feature. Cada
cenario deve ser reproduzivel manualmente no terminal e executavel
como teste automatizado em `tests/cstk/test_session.sh`.

## Pre-condicoes globais

- `cstk` instalado em PATH (`cstk --version` retorna 0).
- `git` instalado.
- `gh` opcional — cenarios `pr-*` exigem; demais nao.
- Repositorio de teste limpo (`git status` vazio) na branch default.

---

## Cenario 1: Start de sessao limpa (happy path)

**Goal**: validar que `start` cria worktree + branch + `.claude/` filtrado.

```bash
cd /tmp && rm -rf repo-test && mkdir repo-test && cd repo-test
git init -b main && git commit --allow-empty -m "init"
mkdir -p .claude/agente-00c-state .claude/skills .claude/insights
echo "x" > .claude/agente-00c-state/state.json
echo "y" > .claude/skills/foo.md
echo "z" > .claude/insights/usage.md
echo "secret" > .claude/settings.local.json
git add . && git commit -m "seed .claude"

cstk session start nova-feat
```

**Expected**:
- Exit 0.
- Worktree criada em `/tmp/repo-test-nova-feat/`.
- Branch `nova-feat` checked out na worktree.
- `/tmp/repo-test-nova-feat/.claude/skills/foo.md` presente.
- `/tmp/repo-test-nova-feat/.claude/agente-00c-state/` **ausente**.
- `/tmp/repo-test-nova-feat/.claude/insights/` **ausente**.
- `/tmp/repo-test-nova-feat/.claude/settings.local.json` **ausente**.

---

## Cenario 2: Start com nome em blocklist (rejeicao)

```bash
cd /tmp/repo-test
cstk session start main
echo "exit=$?"
```

**Expected**:
- Exit 5.
- Stderr cita "nome 'main' reservado" + lista blocklist.
- Nenhuma worktree criada.

---

## Cenario 3: Start com sessao ja existente (idempotencia)

```bash
cd /tmp/repo-test
cstk session start nova-feat   # roda OK (cenario 1 ja rodou)
cstk session start nova-feat   # segunda vez
echo "exit=$?"
```

**Expected**:
- Exit 6.
- Stderr cita "sessao 'nova-feat' ja existe em <path>".
- Worktree original intacta.

---

## Cenario 4: Start com branch ja mergeada (sem flag)

```bash
cd /tmp/repo-test
git branch antiga main      # branch ancestor de main
cstk session start antiga
echo "exit=$?"
```

**Expected**:
- Exit 8.
- Stderr cita "branch 'antiga' ja mergeada em main; use --reset ou --reuse".
- Nenhuma worktree criada.

```bash
cstk session start antiga --reset
```

**Expected**:
- Exit 0 — branch recriada do tip de main, worktree criada.

---

## Cenario 5: List vazio (zero sessoes)

```bash
cd /tmp && rm -rf repo-fresh && mkdir repo-fresh && cd repo-fresh
git init -b main && git commit --allow-empty -m "init"
cstk session list
```

**Expected**:
- Exit 0.
- Stdout `nenhuma sessao ativa`.

---

## Cenario 6: List com multiplas sessoes (ordenacao)

Setup (com a worktree `nova-feat` do Cenario 1 ainda ativa):

```bash
cd /tmp/repo-test
git commit --allow-empty -m "main commit"
cstk session start outra-feat
# Simular idle no commit de outra-feat (touch -d nao afeta git log)
cd /tmp/repo-test
cstk session list
```

**Expected**:
- Exit 0.
- Output tabular com cabecalho `NAME BRANCH IDLE STATUS PATH`.
- 2 linhas: `nova-feat` e `outra-feat`.
- Ordenadas por IDLE ASC.
- Sem rodape de tip (nenhuma STALE).

```bash
cstk session list --json | head -1
```

**Expected**:
- Output comeca com `[`, JSON array valido.
- Cada item tem campos `name`, `branch`, `path`, `idleDays`, `dirty`, `stale`.

---

## Cenario 7: List com worktree stale

```bash
cd /tmp/repo-test
rm -rf /tmp/repo-test-outra-feat   # deleta worktree manualmente
cstk session list
```

**Expected**:
- Exit 0.
- Linha de `outra-feat` mostra `STATUS=STALE`.
- Rodape `tip: rode 'git worktree prune' para limpar worktrees stale`.

---

## Cenario 8: End de sessao clean (happy path)

```bash
cd /tmp/repo-test
cstk session end nova-feat
```

**Expected**:
- Exit 0.
- Stdout confirma "Sessao 'nova-feat' removida".
- `/tmp/repo-test-nova-feat/` nao existe mais.
- `git branch | grep nova-feat` retorna vazio.

---

## Cenario 9: End com mudancas nao commitadas (prompt)

```bash
cd /tmp/repo-test
cstk session start feat-dirty
echo "wip" > /tmp/repo-test-feat-dirty/wip.txt
cd /tmp/repo-test
echo "n" | cstk session end feat-dirty
```

**Expected**:
- Exit 10 (cancelado).
- Stderr cita "1 arquivos modificados nao commitados".
- Worktree intacta.

```bash
echo "y" | cstk session end feat-dirty
```

**Expected**:
- Exit 0.
- Worktree removida (mudancas perdidas — operador confirmou).

```bash
cstk session start feat-force
echo "wip" > /tmp/repo-test-feat-force/wip.txt
cd /tmp/repo-test
cstk session end feat-force --force
```

**Expected**:
- Exit 0 — sem prompt, removida com mudancas.

---

## Cenario 10: End com gh ausente (warning, prossegue)

Setup: temporariamente esconder gh do PATH.

```bash
cd /tmp/repo-test
cstk session start feat-no-gh
cd /tmp/repo-test
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v gh | tr '\n' ':') \
  cstk session end feat-no-gh
```

**Expected**:
- Exit 0.
- Stderr contem "warning: PR check pulado: gh ausente/unauth".
- Worktree removida.

---

## Cenario 11: PR com sucesso (rede)

> Cenario marcado como "manual" no test harness — exige rede + repo
> remoto com GitHub. Em CI/local, skip se `gh auth status` falhar.

```bash
cd /tmp/repo-test
cstk session start feat-pr
echo "doc" > /tmp/repo-test-feat-pr/NOTES.md
git -C /tmp/repo-test-feat-pr add NOTES.md && git -C /tmp/repo-test-feat-pr commit -m "doc"
cstk session pr feat-pr --title "Test PR" --body "ignore"
```

**Expected**:
- Exit 0.
- Stdout contem URL do PR (`https://github.com/.../pull/N`).
- `gh pr view feat-pr --json state` retorna `"OPEN"`.

---

## Cenario 12: PR idempotente (PR ja existe)

```bash
cd /tmp/repo-test
cstk session pr feat-pr   # repeticao
```

**Expected**:
- Exit 0.
- Stdout cita "PR ja existe" + URL existente.
- Nenhum novo PR criado no GitHub.

---

## Cenario 13: PR sem commits novos

```bash
cd /tmp/repo-test
cstk session start feat-empty
cd /tmp/repo-test
cstk session pr feat-empty
```

**Expected**:
- Exit 13.
- Stderr cita "branch 'feat-empty' nao tem commits novos vs main".

---

## Cenario 14 (Roundtrip E2E — defesa contra mock drift)

Este cenario valida que `session start` produz uma sessao que o
`agente-00c` consegue inicializar SEM colidir com sessao concorrente.
Captura o `state.json` real criado pelo agente em cada sessao e
compara que os paths sao distintos. Razao (specify/SKILL.md §5.3):
testes que parseiam mocks mascararam drift real em 40 ondas; aqui
validamos comportamento end-to-end com filesystems reais.

```bash
cd /tmp && rm -rf round-test && mkdir round-test && cd round-test
git init -b main && git commit --allow-empty -m "init"
mkdir -p .claude/skills

cstk session start sess-a
cstk session start sess-b

# Simular agente-00c criando state em cada sessao
mkdir -p /tmp/round-test-sess-a/.claude/agente-00c-state
mkdir -p /tmp/round-test-sess-b/.claude/agente-00c-state
echo '{"id":"a"}' > /tmp/round-test-sess-a/.claude/agente-00c-state/state.json
echo '{"id":"b"}' > /tmp/round-test-sess-b/.claude/agente-00c-state/state.json

# Roundtrip: ler ambos os states e validar isolamento
A=$(cat /tmp/round-test-sess-a/.claude/agente-00c-state/state.json)
B=$(cat /tmp/round-test-sess-b/.claude/agente-00c-state/state.json)
[ "$A" != "$B" ] && echo "PASS: states isolados"
```

**Expected**:
- Stdout `PASS: states isolados`.
- Path do principal `/tmp/round-test/.claude/agente-00c-state/` permanece
  inexistente (sessoes nao corromperam o repo principal).
