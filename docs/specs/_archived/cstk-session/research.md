# Research — cstk-session

Pesquisa para resolver decisoes tecnicas antes do design da Phase 1.
Todos os unknowns que afetariam o data model ou contratos sao
resolvidos aqui.

## Decision 1: Como detectar "branch ja mergeada em main"

**Decision**: Usar `git merge-base --is-ancestor <branch> <default-branch>`.

**Rationale**:
- Exit 0 = `<branch>` e ancestor de `<default-branch>` → ja mergeada (ou nao
  divergiu ainda).
- Exit 1 = nao e ancestor → tem commits proprios = nao mergeada.
- Exit codes claros, sem necessidade de parse de output. Portavel.
- Validacao empirica: `git merge-base --is-ancestor HEAD HEAD` retorna 0.

**Alternatives considered**:
- `git log <branch>..main --oneline | wc -l` — funciona mas exige parse de
  output e pode confundir com `..` vs `...`. Mais complexo.
- `gh pr view <branch> --json state` — depende de gh; perde detecao para
  branches mergeadas localmente sem PR (rebase + push).

**Edge case**: se a branch e ancestor exato do main (zero commits novos),
ainda e tratada como "mergeada". OK conforme spec (FR-001 — `--reset` ou
`--reuse` destrancam).

---

## Decision 2: Como detectar gh ausente vs unauth

**Decision**: Sequencia em 2 passos:
1. `command -v gh >/dev/null 2>&1` — exit 0 = instalado, exit 1 = ausente.
2. `gh auth status >/dev/null 2>&1` — exit 0 = autenticado, exit !=0 = unauth.

**Rationale**:
- `command -v` e POSIX (vs `which`, `type` que tem comportamento divergente).
- `gh auth status` retorna exit code claro (validado empiricamente — retorno 0
  + output em stderr quando autenticado).
- Permite mensagens diferentes para cada caso ("instale gh" vs "rode gh auth login").

**Alternatives considered**:
- Tentar `gh pr view` direto e parsear stderr — fragil, output muda entre
  versoes do gh.
- Cache de status em $TMPDIR — overkill, latencia de `auth status` e
  imperceptivel (<100ms).

---

## Decision 3: Como derivar default branch (main/master/trunk)

**Decision**: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
| sed 's@^refs/remotes/origin/@@'` com fallback hardcoded para `main`.

**Rationale**:
- `origin/HEAD` e o ponteiro canonico do remote para a default branch.
- Setado automaticamente por `git clone` (aponta para o branch default do
  servidor) e por `git remote set-head -a origin`.
- Output: `refs/remotes/origin/main` → `main` apos sed.
- Validacao empirica: confirmou retorno correto neste repo.

**Alternatives considered**:
- `gh repo view --json defaultBranchRef` — exige gh autenticado, transforma
  resolucao de "main vs master" em operacao de rede. Overkill.
- Hardcode `main` sem deteccao — falha em repos com `master` ou `trunk`.
- Listar branches remotas e adivinhar — fragil.

**Fallback**: se `origin/HEAD` nao setado (ex: clone com `--no-checkout` ou
remote sem default branch detectavel), assumir `main`. Quem usa `master`
deve rodar `git remote set-head -a origin` uma vez no repo.

---

## Decision 4: Como detectar worktree stale

**Decision**: `git worktree list --porcelain` ja inclui campo `prunable` para
worktrees cujo path FS nao existe mais OU foram marcadas para prune.

**Rationale**:
- Output do `git worktree list --porcelain`:
  ```
  worktree /path/to/main
  HEAD <sha>
  branch refs/heads/main

  worktree /path/that/disappeared
  HEAD <sha>
  branch refs/heads/feat
  prunable gitdir file points to non-existent location
  ```
- Linha `prunable <reason>` indica stale. Parser simples (loop por blocos
  separados por linha vazia, flag se viu `prunable`).
- Alternativa explicita: `git worktree list --porcelain --verbose` (Git 2.36+)
  da `prunable` automaticamente. Nosso repo tem Git moderno, mas para
  portabilidade vamos preferir presence-check do campo.

**Alternatives considered**:
- `test -d <path>` para cada worktree — funciona mas duplica info que o
  git ja entrega.
- `git worktree prune --dry-run` — output nao-machine-friendly, varia entre
  versoes.

---

## Decision 5: Como calcular IDLE days

**Decision**: Usar `git log -1 --format=%ct <branch>` (commit time epoch) e
calcular `(now - commit_time) / 86400`.

**Rationale**:
- Captura a atividade DO BRANCH, nao do filesystem.
- mtime de arquivos pode estar desatualizado em worktrees recem-criadas
  (cp preserva mtime) ou inflado por touches externos.
- Commit time e a metrica canonica de "ultima coisa que aconteceu nesta
  sessao" em git.
- Implementacao POSIX: `date -u +%s` para epoch now; divisao inteira via
  expansao aritmetica `$((...))`.

**Alternatives considered**:
- mtime do arquivo modificado mais recente — confunde com toques externos
  (IDE, linter, etc).
- `git reflog` — granular demais, captura comandos git que nao sao
  trabalho real.
- Author time (`%at`) — geralmente igual a commit time, mas pode divergir
  em rebases. Commit time mais robusto para "quanto tempo idle".

---

## Decision 6: Como copiar .claude/ excluindo lista

**Decision**: `find` + `cp` em loop. Sem `rsync` (nao garantido em POSIX
puro, nem em macOS antigos consistentemente).

**Rationale**:
- POSIX puro, zero deps.
- Estrutura:
  ```sh
  _src="<repo>/.claude"
  _dst="<session>/.claude"
  mkdir -p "$_dst"
  cd "$_src"
  find . -mindepth 1 \
    -not -path './agente-00c-state*' \
    -not -path './agente-00c-archive*' \
    -not -name 'agente-00c-report.md' \
    -not -name 'agente-00c-suggestions.md' \
    -not -name 'settings.local.json' \
    -not -name 'agente-00c-whitelist' \
    -not -name '.agente-00c-state.lock' \
    -not -path './insights*' \
    -print | cpio -pdm "$_dst" 2>/dev/null
  ```
  Ou alternativa com `cp -R` + cleanup pos:
  ```sh
  cp -R "$_src" "$_dst"
  for pattern in agente-00c-state agente-00c-archive \
    agente-00c-report.md agente-00c-suggestions.md \
    settings.local.json agente-00c-whitelist \
    .agente-00c-state.lock insights; do
    rm -rf "$_dst/$pattern"
  done
  ```
- Preferencia: **cp -R seguido de rm**. Mais legivel, sem risco de
  `find -print | cpio` portability quirks. Custo: copia tudo entao deleta
  alguns, mas `.claude/` tipicamente <50MB.

**Alternatives considered**:
- `rsync --exclude` — nao POSIX, depende de instalacao separada (macOS
  default e versao antiga).
- `tar -X exclude.txt -cf - . | (cd dst && tar xf -)` — complexo, exige
  arquivo de exclude temporario.
- `cpio` — POSIX mas casi extinto em uso pratico, output diferente do que
  operadores esperam.

---

## Decision 7: Onde colocar metadados de sessao (se houver)

**Decision**: ZERO state proprio. Tudo derivado de `git worktree list`.

**Rationale**:
- Spec ja declara isto como Assumed Default. Confirmado: single source of
  truth = git.
- Evita drift entre arquivo de metadata custom e realidade do git
  (sintoma classico do qual o agente-00c sofreu antes do hardening).
- IDLE days e DIRTY status derivados on-demand a cada `list`.

**Alternatives considered**:
- `~/.cstk/sessions.json` com lifecycle — overhead de manter sincronizado.
- `<repo>/.git/cstk-sessions/` — usa git infra mas adiciona um lugar a
  mais para drift.

---

## Decision 8: Estrutura do arquivo `cli/lib/session.sh`

**Decision**: Um arquivo unico em `cli/lib/session.sh` definindo
`session_main` (dispatch interno) + uma funcao por subcomando
(`_session_start`, `_session_list`, `_session_pr`, `_session_end`).
Helpers privados prefixados `_session_helper_*`.

**Rationale**:
- Convencao do cstk: `cli/cstk` chama `<cmd>_main` em `cli/lib/<cmd>.sh`.
- 4 subcomandos compartilham helpers (detectar default branch, validar
  nome, encontrar worktree por nome) — agrupar em 1 arquivo evita
  duplicacao e simplifica testing.
- Tamanho estimado: ~400 linhas (4 subcomandos + 5-6 helpers). Confortavel
  para um arquivo unico.

**Alternatives considered**:
- 1 arquivo por subcomando (`cli/lib/session-start.sh`, etc) — duplica
  helpers ou exige `cli/lib/session-common.sh`. Overhead de manutencao.
- Inline em `cli/cstk` — fere convencao + dificulta teste.

---

## Decision 9: Confinamento de `gh` (conformidade Constitution II amendment 1.1.0)

**Decision**: `gh` e dep opcional confinada em `cli/lib/session.sh`.
3 condicoes do amendment 1.1.0 sao cumpridas:

(a) **Fallback graceful**: `start`, `list`, `end` funcionam SEM `gh`. Apenas
    `pr` requer (e e Story P4, opcional). `end` detecta ausencia e prossegue
    com warning (FR-005). `pr` sem `gh` aborta com exit code distinto e
    mensagem orientando install. Testes automatizados cobrem ambos os casos.

(b) **Confinada em 1 arquivo**: todas as referencias a `gh` ficam em
    `cli/lib/session.sh`. `grep -rn '\bgh\b' cli/lib/` localiza tudo em
    um arquivo.

(c) **Declarada em spec/plan**: spec.md FR-005 + FR-009 + Restricao
    "gh CLI autenticado"; plan.md desta secao 9.

**Rationale**: precedente direto da feature `cstk-cli` que ja usa `jq`
como dep opcional sob a mesma regra.

---

## Decision 10: Validacao de nome (regex + blocklist)

**Decision**: Validacao em 2 etapas:
1. **Regex** `^[a-z0-9][a-z0-9-]{0,62}$` via `printf '%s' "$name" \
   | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$'`. Exit 0 = valido.
2. **Blocklist** hardcoded: rejeita `main master trunk head default origin`
   via case/esac.

**Rationale**:
- Regex POSIX simples, grep -E e POSIX.
- Blocklist via `case "$name" in main|master|trunk|head|default|origin) ;;`
  e POSIX, sem array.
- Mensagens de erro distintas para cada caso (regex falha vs blocklist).

**Alternatives considered**:
- Validacao 100% em `case "$name" in [a-z0-9]*) ...` POSIX glob — funciona
  para regex simples mas perde a clareza do regex completo. Manter grep.
