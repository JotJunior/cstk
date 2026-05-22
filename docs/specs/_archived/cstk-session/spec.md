# Feature Specification: cstk session — Sessoes paralelas isoladas via git worktree

**Feature**: `cstk-session`
**Created**: 2026-05-19
**Status**: Implemented (v3.9.0)

## Clarifications

### Session 2026-05-19

- Q: Comportamento de `start` quando branch local existe mas ja mergeada em `main`? → A: Recusar com mensagem; flags `--reset` (recriar do main) e `--reuse` (forcar reutilizacao) destrancam.
- Q: Quais artefatos do `.claude/` NAO copiar para a sessao? → A: `agente-00c-state/`, `agente-00c-archive/`, `agente-00c-report.md`, `agente-00c-suggestions.md`, `settings.local.json`, `agente-00c-whitelist`, `.agente-00c-state.lock`, `insights/`.
- Q: Comportamento de `end` quando `gh` ausente ou nao autenticado? → A: `gh` e opcional em `end` — ausente/unauth pula PR check com warning ("PR check pulado: gh ausente/unauth") e prossegue normalmente.
- Q: Como `list` trata worktrees stale (path no FS nao existe mais)? → A: Mostrar com marcador `STALE` em coluna STATUS + dica de rodape `rode 'git worktree prune' para limpar`.
- Q: Validar blocklist de nomes reservados de sessao? → A: Sim — blocklist hardcoded: `main`, `master`, `trunk`, `head`, `default`, `origin`.
- Q: `end` chamado de dentro da propria worktree-alvo? → A: Recusa com exit 14 + mensagem orientando rodar de outra worktree (principal ou outra sessao).
- Q: `list` chamado de dentro de uma sessao — mostra ela mesma? → A: Inclui a worktree atual na listagem com marcador `CURRENT` na coluna STATUS, alem dos demais marcadores possiveis (`*`, `STALE`).
- Q: Versao minima do `git`? → A: `>=2.36` (Feb-2022) — necessario para campo `prunable` em `git worktree list --porcelain` usado por FR-007.
- Q: `start <name>` quando branch existe em `origin/<name>` mas nao localmente? → A: Criar branch local rastreando `origin/<name>` automaticamente (`git worktree add <path> -b <name> --track origin/<name>`), permitindo retomada de feature compartilhada.
- Q: Politica de falha parcial em `start` (worktree criada, `.claude/` falhou) e em `pr` (push OK, `gh pr create` falhou)? → A: Best-effort com mensagem clara; sem rollback automatico. Operador recebe instrucao concreta de cleanup (`cstk session end <name> --force` ou `git push -d origin <branch>`).
- Q: `start --reset` quando branch existente tem commits NAO mergeados em `main`? → A: Prompt interativo de confirmacao listando os commits que serao descartados; `--force` bypassa o prompt. Se branch e ancestor exato de `main` (zero commits proprios), `--reset` procede sem prompt.

## Contexto

Hoje, ao trabalhar em duas features simultaneamente no mesmo repositorio
(ex: refatorar agente-00c em uma feature E adicionar nova skill em outra),
duas sessoes do Claude Code colidem em:

- working tree (unico checkout — edits de A sao vistos por B)
- HEAD da branch (`git checkout` em A confunde contexto de B)
- `<PAP>/.claude/agente-00c-state/state.json` + lock atomico
- arquivos `report.md` / `suggestions.md` (overwrite mutuo)
- lockfiles (`go.sum`, `package-lock.json`)

A solucao escolhida (apos analise comparativa de Docker, devcontainer,
codespaces, multiplos clones) e usar **`git worktree`**: cria um diretorio
irmao com branch propria, compartilha `.git`, e isola tudo o que precisa
isolar. Esta feature embrulha o fluxo em subcomandos ergonomicos do `cstk`
para tornar o uso diario barato (start em 1 comando, end com seguranca,
PR com 1 comando).

A feature **NAO** introduz Docker, container runtime, nem cloud env —
mantem-se em POSIX shell + git + gh CLI.

> Decisoes de infraestrutura: N/A (feature stateless — sem scheduling,
> sem key rotation, sem refresh policy, sem mutex multi-pod, sem backup).
> Toda persistencia e delegada ao proprio git (worktree metadata em
> `.git/worktrees/`).

## Assumed Defaults

Para evitar excesso de `[NEEDS CLARIFICATION]`, a spec assume defaults
razoaveis. Cada um pode ser revisado no `/clarify`:

| Decisao | Default assumido | Razao |
|---------|------------------|-------|
| Worktree path | `<parent-dir>/<repo-name>-<session-name>` (sibling do repo principal) | Convencao do `git worktree add ..<nome>` da documentacao oficial; nao polui o repo principal com subdir `.worktrees/`. |
| Branch name | `<session-name>` direto (sem prefixo) | Simplicidade. Quem quiser prefixo (`feat/`, `session/`) define `CSTK_SESSION_PREFIX` env var. |
| `.claude/` isolado | `.claude/` da sessao copiado SEM `agente-00c-state/`, `agente-00c-archive/`, `agente-00c-report.md`, `agente-00c-suggestions.md` | Motivacao primaria do isolamento: state do agente-00c. Skills/commands/settings sao compartilhados (Read-only). |
| Tracking de sessoes ativas | Derivado de `git worktree list` (zero state proprio) | Single source of truth = git. Evita drift entre arquivo de metadata custom e realidade do `.git/worktrees/`. |
| Default base branch para PR | `main` | Convencao explicita do projeto (CLAUDE.md raiz). |

## User Scenarios & Testing

### User Story 1 - Iniciar sessao isolada (Priority: P1)

Joao esta no diretorio `~/Projects/meta-gob-ms` trabalhando na branch
`main`. Ele decide comecar uma nova feature `iniciacao-membro` e quer
mante-la totalmente isolada da outra feature em andamento. Ele roda
`cstk session start iniciacao-membro`. O comando cria
`~/Projects/meta-gob-ms-iniciacao-membro/` como worktree com a branch
`iniciacao-membro`, copia o `.claude/` (sem o `agente-00c-state/`),
imprime o caminho criado e instrucao de `cd`. Joao abre nova janela do
Claude Code naquele diretorio e o agente-00c roda com state.json proprio,
sem colidir com o trabalho na `main`.

**Why this priority**: e o MVP. Sem `start`, nao existe sessao para
listar, encerrar ou abrir PR. Esta unica story ja entrega o valor
nuclear (isolamento), porque o usuario pode finalizar manualmente com
`git worktree remove` se as outras stories nao existirem.

**Independent Test**: rodar `cstk session start exemplo` em um repo
limpo deve resultar em (a) worktree criada em path previsivel, (b)
branch `exemplo` criada e checkout-ada nessa worktree, (c) `.claude/`
da sessao **nao** conter `agente-00c-state/`, (d) repo principal
permanece na branch original sem mudancas.

**Acceptance Scenarios**:

> Convencao de numeracao: cenarios principais usam inteiros (1, 2, 3...).
> Variantes diretas de um cenario-base recebem sub-letras (3a, 3b, ...)
> quando exploram regras alternativas da mesma situacao — preservando a
> ligacao mental "caso 3 e suas variantes".

1. **Given** repo limpo na `main`, **When** rodo
   `cstk session start nova-feature`, **Then** worktree criada em
   `<parent>/<repo>-nova-feature/` com branch `nova-feature` (criada
   localmente), exit 0, stdout instrui `cd <path>` e proxima acao.
2. **Given** sessao `nova-feature` ja existe, **When** rodo
   `cstk session start nova-feature` de novo, **Then** exit != 0
   com mensagem "sessao 'nova-feature' ja existe em <path>", sem
   destruir nada.
3. **Given** existe branch local `nova-feature` ja criada em outro
   contexto E cujo HEAD ainda NAO foi mergeado em `main`, **When** rodo
   `cstk session start nova-feature`, **Then** worktree e criada
   usando a branch existente (sem `-b`), permitindo retomar trabalho.
   Stdout indica claramente "branch existente reutilizada".
3a. **Given** existe branch local `nova-feature` cujo HEAD JA foi
   mergeado em `main` (ancestor de `main`), **When** rodo
   `cstk session start nova-feature`, **Then** exit != 0 com mensagem
   "branch 'nova-feature' ja mergeada em main; use --reset para
   recriar do main, ou --reuse para forcar reutilizacao". Sem mudancas.
3b. **Given** mesmo cenario 3a, **When** rodo com `--reset`, **Then**
   branch local e recriada do tip de `main` e worktree e criada.
3c. **Given** mesmo cenario 3a, **When** rodo com `--reuse`, **Then**
   worktree e criada com a branch existente sem recriar (comportamento
   do scenario 3).
3d. **Given** branch `nova-feature` existe em `origin/nova-feature` MAS
   nao localmente, **When** rodo `cstk session start nova-feature`,
   **Then** branch local e criada rastreando `origin/nova-feature`
   (`-b nova-feature --track origin/nova-feature`); worktree criada
   com essa branch. Stdout indica "rastreando origin/nova-feature".
3e. **Given** branch local `nova-feature` tem 5 commits NAO mergeados em
   `main`, **When** rodo `cstk session start nova-feature --reset`,
   **Then** prompt interativo lista os 5 commits e pergunta
   "descartar? [y/N]". Resposta `N`/vazia = aborto sem mudancas. `--force`
   junto = bypass do prompt.
4. **Given** nome contendo path traversal (`../foo` ou `foo/bar`),
   **When** rodo `cstk session start <nome-invalido>`, **Then** exit
   != 0 com mensagem explicando padrao aceito (kebab-case alfanumerico).
5. **Given** diretorio do worktree-alvo ja existe (sem ser worktree
   git), **When** rodo `cstk session start nova-feature`, **Then**
   exit != 0 com mensagem "path destino ocupado: <path>", sem tocar
   no diretorio existente.

---

### User Story 2 - Encerrar sessao com seguranca (Priority: P2)

Joao terminou de trabalhar na feature `iniciacao-membro` (PR mergeado
no GitHub) e quer limpar o worktree localmente. Ele roda `cstk session
end iniciacao-membro`. O comando detecta se ha mudancas nao commitadas
ou nao pushadas, pergunta confirmacao explicita se houver, e so entao
remove o worktree + branch local. Se o PR ainda esta aberto no GitHub,
emite aviso antes da remocao.

**Why this priority**: protege trabalho. Sem `end`, o usuario poderia
correr `git worktree remove` direto e perder commits nao pushados. O
guard-rail justifica a story como independente de `list`/`pr`.

**Independent Test**: rodar `cstk session end exemplo` com mudancas
nao commitadas deve abortar por padrao; com `--force` deve permitir
mesmo assim e remover.

**Acceptance Scenarios**:

1. **Given** sessao `nova-feature` clean (sem mudancas, branch pushada),
   **When** rodo `cstk session end nova-feature`, **Then** worktree
   removido, branch local deletada, exit 0.
2. **Given** sessao com `git status` nao-vazio (mudancas uncommited),
   **When** rodo `cstk session end nova-feature`, **Then** prompt
   interativo: "ha N arquivos modificados — confirmar remocao? [y/N]".
   Resposta `N` ou vazia = aborto sem mudancas.
3. **Given** mesmo cenario anterior, **When** rodo com `--force`,
   **Then** worktree removido sem prompt; mudancas perdidas.
4. **Given** sessao com commits locais nao pushados, **When** rodo
   `cstk session end nova-feature`, **Then** prompt similar avisa "N
   commits nao pushados" antes de remover.
5. **Given** PR aberto no GitHub para essa branch (detectavel via
   `gh pr view`), **When** rodo `cstk session end nova-feature`,
   **Then** prompt adicional: "PR #X ainda aberto — encerrar mesmo
   assim? [y/N]".
6. **Given** sessao inexistente, **When** rodo `cstk session end
   inexistente`, **Then** exit != 0 com mensagem "sessao 'inexistente'
   nao encontrada — rode 'cstk session list'".
7. **Given** estou dentro da worktree da sessao `nova-feature`, **When**
   rodo `cstk session end nova-feature` de la, **Then** exit 14 com
   mensagem "nao e possivel encerrar a sessao atual; rode de outra
   worktree (principal ou outra sessao)". Nenhuma mudanca aplicada.

---

### User Story 3 - Listar sessoes ativas (Priority: P3)

Joao tem 3 sessoes em andamento (`iniciacao-membro`, `oauth2-refresh`,
`fix-flaky-test`) e perdeu o controle de qual esta em que estado. Ele
roda `cstk session list` e ve, em formato tabular, para cada sessao:
nome, branch, path absoluto, dias desde a ultima atividade (mtime do
arquivo mais recente), e indicador visual de mudancas pendentes.

**Why this priority**: visibilidade. Util quando ha 3+ sessoes
simultaneas — abaixo disso, o `git worktree list` ja basta. Independente
de start/end porque pode rodar mesmo em sessoes criadas manualmente
via `git worktree add` (so depende de detectar worktrees do repo).

**Independent Test**: criar manualmente 2 worktrees, rodar `cstk session
list` e validar que ambas aparecem com info correta.

**Acceptance Scenarios**:

1. **Given** zero sessoes ativas, **When** rodo `cstk session list`,
   **Then** stdout "nenhuma sessao ativa" + exit 0 (nao e erro).
2. **Given** 3 worktrees do mesmo repo (alem do principal), **When**
   rodo `cstk session list`, **Then** tabela com 3 linhas, colunas
   `NAME`, `BRANCH`, `PATH`, `IDLE`, `DIRTY` ordenadas por `IDLE`
   crescente (mais ativa primeiro).
3. **Given** uma das worktrees tem mudancas nao commitadas, **When**
   rodo `cstk session list`, **Then** coluna `DIRTY` mostra `*` para
   ela; demais ficam vazias.
4. **Given** flag `--json`, **When** rodo `cstk session list --json`,
   **Then** stdout e JSON array com mesmos campos por sessao
   (script-friendly), incluindo campo `current: true` para a worktree
   atual se rodado de dentro de uma sessao.
5. **Given** estou dentro da worktree `nova-feature` (que e uma sessao),
   **When** rodo `cstk session list`, **Then** linha de `nova-feature`
   tem marcador `CURRENT` na coluna STATUS; demais sessoes listadas
   normalmente.

---

### User Story 4 - Criar PR da sessao para main (Priority: P4)

Joao terminou a feature `iniciacao-membro` na sessao isolada. Ele roda
`cstk session pr iniciacao-membro` de qualquer diretorio. O comando
valida que a branch tem commits a frente de `main`, pushe a branch para
o remote, e dispara `gh pr create` com base `main`. Retorna a URL do PR.

**Why this priority**: atalho ergonomico — o usuario pode fazer
`gh pr create` direto. Justifica como story porque (a) elimina o passo
"em qual diretorio rodar gh?" e (b) valida pre-condicoes que `gh` nao
checa (branch nao tracked, sem commits a frente).

**Independent Test**: criar sessao com 1 commit, rodar `cstk session pr
<name>`, validar push + PR criado com URL retornada.

**Acceptance Scenarios**:

1. **Given** sessao com >=1 commit a frente de `main`, branch nao
   pushada, **When** rodo `cstk session pr nova-feature`, **Then**
   branch pushada para `origin`, PR aberto via `gh pr create --base
   main --head nova-feature`, URL do PR no stdout.
2. **Given** branch ja pushada com PR existente, **When** rodo `cstk
   session pr nova-feature`, **Then** exit 0 com mensagem "PR ja existe
   em <URL>" (idempotente — nao tenta criar de novo).
3. **Given** branch nao tem commits a frente de `main`, **When** rodo
   `cstk session pr nova-feature`, **Then** exit != 0 com mensagem
   "branch nao tem commits novos vs main".
4. **Given** `gh` nao autenticado, **When** rodo `cstk session pr
   nova-feature`, **Then** exit != 0 com mensagem clara apontando
   `gh auth login`.
5. **Given** flag `--draft`, **When** rodo `cstk session pr nova-feature
   --draft`, **Then** PR criado como draft.
6. **Given** flags `--title` e `--body`, **When** rodo com elas, **Then**
   passa para `gh pr create` correspondentemente. Sem flags, deixa o
   `gh` abrir editor interativo ou usar primeiro commit message.

---

### Edge Cases

- Repo nao e git (`.git/` ausente): qualquer subcomando aborta com
  mensagem "diretorio atual nao e repositorio git".
- Repo e um worktree (nao o principal): subcomandos detectam e operam
  no repo principal via `git rev-parse --git-common-dir`. Permitido
  rodar `cstk session list` de dentro de uma sessao.
- Worktree path-destino existe mas e diretorio vazio: comportamento
  identico a "diretorio ocupado" — recusa por seguranca (operador
  precisa remover manualmente para indicar intencao).
- `.claude/agente-00c-state/` ja existe no repo principal (uso comum):
  `start` copia o `.claude/` MAS exclui os 8 artefatos runtime/per-env
  listados em FR-002. State, relatorios, whitelist, locks, insights e
  settings.local sao runtime, nao semente de sessao.
- Nome com caracteres invalidos (espaco, acento, simbolos): validacao
  rejeita; padrao aceito: `^[a-z0-9][a-z0-9-]{0,62}$`.
- Nome em blocklist de reservados (`main`, `master`, `trunk`, `head`,
  `default`, `origin`): validacao rejeita com mensagem citando lista
  completa e sugerindo prefixo (`feat-main` em vez de `main`).
- `end` de dentro da propria worktree-alvo: recusa com exit 14 (FR-018).
  Detectado via `git rev-parse --show-toplevel` == path da worktree
  resolvida por nome.
- Falha parcial em `start` ou `pr` (FR-017): best-effort, sem rollback
  automatico; stderr instrui acao corretiva especifica.
- Operador faz `git worktree remove --force` manualmente (sem usar
  `cstk session end`): proximo `cstk session list` ainda funciona
  (deriva de git, nao mantem state proprio).
- Repo com `main` renomeada (`master`, `trunk`): `end` e `pr` usam
  `git symbolic-ref refs/remotes/origin/HEAD` para descobrir default
  branch real, com fallback para `main` se nao definido.
- Sessao chamada com mesmo nome de branch ja remota (`gh pr create`
  vai pushear): comportamento aceitavel — usuario assume que sabe o
  que faz; `start` ja avisou "branch existente reutilizada".
- **Repo com git submodules (monorepo)**: `start` chama `git worktree
  add` puro, sem `git submodule update --init`. Submodules ficam
  vazios na sessao (so o gitlink `.git` em cada subdir). Se operador
  inicializar manualmente na sessao, o `.git/modules/<nome>` e
  compartilhado com o checkout principal — branch HEAD do submodule
  fica SHARED entre as duas worktrees, quebrando a promessa de
  isolamento para edits dentro do submodule. **Workaround atual**:
  editar codigo de submodule pelo checkout principal, OU abrir
  session SEPARADA dentro do submodule (`cd path/to/submodule &&
  cstk session start ...`). Limitacao documentada no help do
  `cstk session` + issue de tracking aberta no repositorio. **Nao
  e bug do cstk**: limitacao fundamental de como git trata
  submodules em worktrees — para isolamento real seria necessario
  criar worktree do submodule tambem, o que extrapola escopo desta
  feature.

## Requirements

### Functional Requirements

- **FR-001**: `cstk session start <name>` MUST criar git worktree em
  `<parent-of-repo>/<repo-name>-<name>` com branch `<name>` seguindo
  estas regras de resolucao:
  - Branch nao existe local nem em origin → criar nova do tip de default branch.
  - Branch nao existe local MAS existe em `origin/<name>` → criar local
    rastreando origin (`-b <name> --track origin/<name>`).
  - Branch existe local E nao mergeada em default → reutilizar.
  - Branch existe local E ja mergeada em default → recusar a menos que
    `--reset` (recria do default) ou `--reuse` (forca HEAD atual).
  - Se `--reset` for usado E branch tem commits NAO mergeados em default,
    emitir prompt interativo listando commits que serao descartados;
    `--force` bypassa.
- **FR-002**: `cstk session start` MUST copiar `<repo>/.claude/` para
  a sessao excluindo TODOS os seguintes (runtime / per-environment):
  `agente-00c-state/`, `agente-00c-archive/`, `agente-00c-report.md`,
  `agente-00c-suggestions.md`, `settings.local.json`,
  `agente-00c-whitelist`, `.agente-00c-state.lock`, `insights/`.
  Demais arquivos (skills/, commands/, agents/, settings.json) sao
  copiados.
- **FR-003**: `cstk session start` MUST rejeitar com exit != 0 se: nome
  invalido (regex `^[a-z0-9][a-z0-9-]{0,62}$`), nome esta na blocklist
  hardcoded (`main`, `master`, `trunk`, `head`, `default`, `origin`),
  sessao com mesmo nome ja existe, diretorio destino ja existe (mesmo
  que vazio), ou repo atual nao e git.
- **FR-004**: `cstk session end <name>` MUST detectar mudancas nao
  commitadas (`git status --porcelain` nao vazio) ou commits nao pushados
  (compara com `origin/<branch>`) e exigir confirmacao interativa
  ANTES de remover. Flag `--force` bypassa confirmacao.
- **FR-005**: `cstk session end` MUST consultar `gh pr view <branch>
  --json state` e emitir warning se PR `OPEN` antes de remover. Se
  `gh` ausente OU `gh auth status` indicar nao-autenticado, emitir
  warning "PR check pulado: gh ausente/unauth" e prosseguir com o
  cleanup local (a operacao NAO falha por causa do gh).
- **FR-006**: `cstk session end` MUST remover worktree (`git worktree
  remove`) E branch local (`git branch -D`) na ordem correta. Se
  remocao parcial falhar, mensagem indica estado residual exato.
- **FR-007**: `cstk session list` MUST listar todas worktrees do repo
  (incluindo a atual quando rodado de dentro de uma worktree-sessao)
  com colunas NAME (basename do path), BRANCH, PATH (absoluto), IDLE
  (dias desde commit mais recente do branch), STATUS (marcadores
  combinaveis: `CURRENT` se e a worktree atual; `STALE` se path nao
  existe no FS; `*` se ha mudancas; vazio se clean — multiplos
  marcadores separados por `,` ex `CURRENT,*`). A worktree principal
  e sempre excluida (apenas sessoes sao listadas). Se houver pelo menos
  1 STALE, o output termina com rodape "tip: rode 'git worktree prune'
  para limpar worktrees stale".
- **FR-008**: `cstk session list --json` MUST emitir array JSON com
  os mesmos campos, em camelCase (`name`, `branch`, `path`, `idleDays`,
  `dirty`, `stale`, `current`). Rodape de tip e suprimido em modo JSON.
- **FR-009**: `cstk session pr <name>` MUST validar pre-condicoes na
  ordem: (a) sessao existe, (b) branch tem commits a frente de base
  branch, (c) `gh auth status` retorna autenticado. Falha em qualquer
  ponto = exit != 0 com mensagem orientando correcao.
- **FR-010**: `cstk session pr` MUST detectar default branch via
  `git symbolic-ref refs/remotes/origin/HEAD` com fallback para `main`.
- **FR-011**: `cstk session pr` MUST ser idempotente: se PR ja existe
  (`gh pr view <branch>` retorna state OPEN/MERGED), imprime URL existente
  e exit 0 sem criar duplicata.
- **FR-012**: `cstk session pr` MUST repassar flags `--draft`, `--title`,
  `--body`, `--reviewer` para `gh pr create`. Sem flags, deixa `gh`
  decidir (editor interativo ou primeiro commit message).
- **FR-013**: TODOS os subcomandos MUST funcionar a partir de qualquer
  diretorio do repo (principal OU worktree), resolvendo o repo principal
  via `git rev-parse --git-common-dir`.
- **FR-014**: Falha de pre-condicao (`git`/`gh` ausente, repo nao-git,
  rede indisponivel para `gh`) MUST resultar em exit code distinto e
  mensagem identificavel para scripting.
- **FR-015**: TODOS os subcomandos MUST ser idempotentes na seguinte
  acepcao: chamada duplicada nao corrompe estado nem deixa side effect
  parcial. `start` ja existente = no-op com erro claro; `pr` existente
  = no-op com URL; `end` inexistente = erro claro.
- **FR-016**: Subcomandos MUST seguir convencao de exit codes do `cstk`
  ja estabelecida em `cli/cstk` (0 OK, 1 erro, 2 uso incorreto). Novos
  codigos especificos da feature DEVEM ser documentados em
  `contracts/cli-commands.md`.
- **FR-017**: Falhas parciais MUST seguir politica **best-effort com
  mensagem orientativa** — sem rollback automatico. Casos cobertos:
  - `start` falha entre `git worktree add` e `cp -R .claude/`: worktree
    permanece criada, `.claude/` parcial; stderr instrui
    `cstk session end <name> --force` para limpar.
  - `pr` falha em `gh pr create` apos `git push -u origin <branch>`:
    branch pushada permanece; stderr instrui `git push -d origin <branch>`
    para desfazer ou `gh pr create` para retry manual.
  - `end` com falha parcial (FR-006 ja cobre): mensagem indica estado
    residual exato.
- **FR-018**: `end` chamado a partir de dentro da propria worktree-alvo
  MUST recusar com exit 14 + mensagem "nao e possivel encerrar a sessao
  atual; rode de outra worktree (principal ou outra sessao)".

### Key Entities

- **Session**: representa uma sessao paralela de trabalho. Atributos:
  nome (kebab-case unico no repo), branch git associada, path absoluto
  da worktree, estado derivado (clean / dirty / unpushed-commits / pr-open),
  idle-days (mtime do arquivo mais recente). Ciclo de vida: nasce no
  `start`, "morre" no `end` (sem persistencia entre sessoes — single
  source of truth = `.git/worktrees/`).
- **Repo principal**: o checkout original do repositorio, onde
  `<parent>/<repo-name>/` esta. Sessoes sao irmas dele no filesystem.
  Subcomandos resolvem este path via `git rev-parse --git-common-dir`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Desenvolvedor cria nova sessao isolada em <=3 segundos
  (`cstk session start <name>` retorna o prompt) em repos ate ~500MB.
- **SC-002**: Duas sessoes simultaneas no mesmo repo produzem zero
  conflitos observaveis em working tree, branch HEAD, ou
  `.claude/agente-00c-state/` (validado por teste E2E).
- **SC-003**: Desenvolvedor encerra sessao com mudancas nao commitadas
  e NAO perde trabalho — confirmacao bloqueia em 100% dos casos sem
  `--force`.
- **SC-004**: Desenvolvedor lista 5+ sessoes ativas e identifica a
  mais inativa em <=5 segundos olhando o output.
- **SC-005**: Desenvolvedor abre PR direto da sessao sem precisar
  fazer `cd` ate ela — chamada de qualquer diretorio do repo funciona
  em <=10 segundos.
- **SC-006**: 100% das chamadas de subcomando que falham por
  pre-condicao (repo nao-git, gh nao autenticado, nome invalido)
  retornam mensagem que o usuario consegue acionar (cita a acao
  corretiva: "rode gh auth login", "use nome kebab-case").
- **SC-007**: Comando funciona offline para `start`, `list`, `end`.
  Apenas `pr` exige rede (e identifica falha de rede explicitamente).
