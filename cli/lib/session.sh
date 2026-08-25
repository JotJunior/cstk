# session.sh — comando `cstk session` (sessoes paralelas via git worktree).
#
# Ref: docs/specs/cstk-session/spec.md
#      docs/specs/cstk-session/plan.md
#      docs/specs/cstk-session/contracts/cli-session.md
#
# Funcao exportada:
#   session_main "$@"
#
# Subcomandos (implementados em FASES 2-5; FASE 1 entrega scaffold + helpers):
#   start  — criar worktree + branch + .claude/ filtrado          [FASE 2]
#   list   — listar sessoes ativas                                [FASE 3]
#   end    — remover worktree + branch com guards                 [FASE 4]
#   pr     — abrir PR da branch para default branch via gh        [FASE 5]
#
# Exit codes especificos da feature (alem de 0/1/2 do cstk core):
#   5  — nome invalido (regex ou blocklist)
#   6  — sessao ja existe
#   7  — path destino ocupado por nao-worktree
#   8  — branch ja mergeada (sem --reset/--reuse)
#   9  — sessao nao encontrada (end/pr)
#   10 — usuario cancelou prompt
#   11 — gh nao instalado (pr)
#   12 — gh instalado mas nao autenticado (pr)
#   13 — branch sem commits novos vs default (pr)
#   14 — `end` chamado de dentro da propria worktree-alvo
#   15 — git versao < 2.36 (boot-check)
#
# POSIX sh puro. Constitution II compliance:
#   - Sem bash-isms (sem [[, <<<, arrays, local, function keyword).
#   - Dep opcional `gh` confinada a este arquivo (amendment 1.1.0): usada
#     apenas em `pr` (obrigatoria) e em `end` (opcional com fallback).

if [ -n "${_CSTK_SESSION_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_SESSION_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"

# ==== Exit codes ====

CSTK_SESSION_EXIT_INVALID_NAME=5
CSTK_SESSION_EXIT_ALREADY_EXISTS=6
CSTK_SESSION_EXIT_PATH_OCCUPIED=7
CSTK_SESSION_EXIT_BRANCH_MERGED=8
CSTK_SESSION_EXIT_NOT_FOUND=9
CSTK_SESSION_EXIT_CANCELLED=10
CSTK_SESSION_EXIT_GH_MISSING=11
CSTK_SESSION_EXIT_GH_UNAUTH=12
CSTK_SESSION_EXIT_NO_COMMITS=13
CSTK_SESSION_EXIT_SELF_END=14
CSTK_SESSION_EXIT_GIT_TOO_OLD=15

# ==== Constantes ====

# Versao minima do git (campo `prunable` em `git worktree list --porcelain`).
CSTK_SESSION_MIN_GIT_MAJOR=2
CSTK_SESSION_MIN_GIT_MINOR=36

# Blocklist de nomes reservados (case-insensitive ja garantido por regex
# que so aceita lowercase). Lista hardcoded conforme spec FR-003.
_CSTK_SESSION_BLOCKLIST="main master trunk head default origin"

# Lista de exclusoes ao copiar .claude/ para a sessao (FR-002 + extensao
# 2026-08-24: feature-00c-state — state de execucao e per-worktree; copiar
# states do checkout principal para a sessao confundia a precedencia do
# pretooluse-guard e gerava colisao no `session end`).
# Caminhos/nomes relativos a .claude/ — separados por espaco.
_CSTK_SESSION_CLAUDE_EXCLUDES="agente-00c-state feature-00c-state agente-00c-archive agente-00c-report.md agente-00c-suggestions.md settings.local.json agente-00c-whitelist .agente-00c-state.lock insights"

# Artefatos 00c preservados pelo `session end` ANTES de remover a worktree
# (alem de .claude/feature-00c-state/<short>/, tratado por-feature).
# .claude/ e tipicamente gitignored: os guards dirty/unpushed NAO enxergam
# esses artefatos, e a remocao os destruiria em silencio.
_CSTK_SESSION_STATE_ARTIFACTS="agente-00c-state agente-00c-archive agente-00c-report.md agente-00c-suggestions.md enforcement-log.jsonl"

# ==== Help ====

_session_print_help() {
  cat >&2 <<'HELP'
cstk session — sessoes paralelas isoladas via git worktree.

USO:
  cstk session start <name> [--reset|--reuse] [--force] [--claude]
  cstk session list [--json]
  cstk session pr <name> [--draft] [--title TITLE] [--body BODY] [--reviewer USER]
  cstk session end <name> [--force] [--discard-state]

SUBCOMANDOS:
  start    Cria worktree + branch + copia .claude/ filtrado.
           --reset:  recria branch do default branch (descarta historico
                     local; prompt se ha commits nao-mergeados, --force bypassa).
           --reuse:  forca reutilizar HEAD atual de branch ja mergeada.
           --claude: apos criar a sessao, entra no diretorio e inicia o
                     Claude Code (exec claude). Combinavel com as demais.

  list     Lista sessoes ativas. Marcadores STATUS (combinaveis):
           CURRENT (worktree atual), * (dirty), STALE (path inexistente).
           --json: array JSON em camelCase (script-friendly).

  end      Remove worktree + branch local com guards (prompts para dirty,
           commits nao pushados, PR aberto). --force pula prompts.
           Antes da remocao, PRESERVA os artefatos 00c da worktree
           (.claude/feature-00c-state/<short>/ com state.db/state.json,
           agente-00c-state, report, enforcement-log) copiando-os para o
           .claude/ do checkout principal — colisao vai para
           .claude/session-state-backup/<name>/, nunca sobrescreve.
           Falha de copia bloqueia a remocao (fail-closed).
           --discard-state: descarta deliberadamente esses artefatos.

  pr       Abre PR da branch para default branch via gh. Idempotente:
           se PR existe, retorna URL existente. Flags --draft/--title/
           --body/--reviewer sao repassadas ao `gh pr create`.

LIMITACOES:
  Git submodules NAO sao isolados pela sessao. `cstk session start`
  chama `git worktree add` puro; submodules ficam vazios na sessao
  (so com gitlink `.git`). Se rodar `git submodule update --init`
  dentro da sessao, o `.git` de cada submodule e compartilhado com
  o checkout principal via `.git/modules/<nome>` — branch HEAD do
  submodule e SHARED entre main e sessao. Mudancas no submodule
  feitas na sessao afetam o checkout principal silenciosamente.
  Workaround: edite codigo de submodule pelo checkout principal,
  OU abra session SEPARADA dentro do submodule
  (`cd path/to/submodule && cstk session start ...`).

ENVIRONMENT:
  CSTK_LIB              caminho da biblioteca (setado pelo cstk)

DEPS:
  git >= 2.36 (obrigatoria, para campo `prunable` em worktree list)
  gh           (obrigatoria para `pr`; opcional para `end` — pr-check skippado)

DOCS:
  docs/specs/cstk-session/spec.md
  docs/specs/cstk-session/contracts/cli-session.md

EXIT CODES:
  0   sucesso
  1   erro generico (inclui falhas parciais com stderr orientativo)
  2   uso incorreto
  5   nome invalido (regex ou blocklist)
  6   sessao ja existe
  7   path destino ocupado
  8   branch ja mergeada (sem --reset/--reuse)
  9   sessao nao encontrada
  10  usuario cancelou prompt
  11  gh nao instalado
  12  gh nao autenticado
  13  branch sem commits novos vs default
  14  end chamado de dentro da propria worktree-alvo
  15  git versao < 2.36
HELP
}

# ==== Boot-check: git >= 2.36 ====
#
# Valida que `git --version` >= 2.36 (necessario para campo `prunable` em
# `git worktree list --porcelain` usado por FR-007). Retorna exit 15 se
# inferior. Idempotente — pode ser chamado multiplas vezes.
_session_check_git_version() {
  if ! command -v git >/dev/null 2>&1; then
    log_error "session: git nao encontrado no PATH"
    return 1
  fi
  _gv=$(git --version 2>/dev/null | awk '{print $3}')
  # Parser POSIX: extrai major + minor via cut.
  _maj=$(printf '%s' "$_gv" | cut -d. -f1)
  _min=$(printf '%s' "$_gv" | cut -d. -f2)
  case "$_maj$_min" in
    ''|*[!0-9]*)
      log_error "session: nao foi possivel parsear versao do git: '$_gv'"
      return 1
      ;;
  esac
  if [ "$_maj" -lt "$CSTK_SESSION_MIN_GIT_MAJOR" ] \
     || { [ "$_maj" -eq "$CSTK_SESSION_MIN_GIT_MAJOR" ] \
          && [ "$_min" -lt "$CSTK_SESSION_MIN_GIT_MINOR" ]; }; then
    log_error "session: git $_gv detectado; minimo requerido: ${CSTK_SESSION_MIN_GIT_MAJOR}.${CSTK_SESSION_MIN_GIT_MINOR}"
    log_error "session: campo 'prunable' em 'git worktree list --porcelain' exige >=2.36 (Feb-2022)"
    log_error "session: atualize via: brew upgrade git OU apt install git/sua-distro"
    return "$CSTK_SESSION_EXIT_GIT_TOO_OLD"
  fi
  return 0
}

# ==== Helpers comuns ====

# _session_resolve_repo: imprime path absoluto do repo principal (worktree
# original, nao secundaria). Retorna exit 1 se nao e repo git.
#
# `git rev-parse --git-common-dir` retorna o path do .git/ compartilhado
# (em worktree secundaria, aponta para o .git/ do principal). Resolvemos
# o repo principal subindo um nivel desse path e tornando absoluto.
_session_resolve_repo() {
  if ! _gcd=$(git rev-parse --git-common-dir 2>/dev/null); then
    log_error "session: diretorio atual nao e repositorio git"
    return 1
  fi
  # --git-common-dir pode ser relativo (".git") ou absoluto.
  # Resolver: cd para o dirname e usar `pwd -P` (POSIX physical path —
  # resolve symlinks). Crucial em macOS onde /tmp e symlink para /private/tmp;
  # `git worktree list --porcelain` sempre emite paths canonicos.
  ( cd -- "$_gcd/.." 2>/dev/null && pwd -P ) || {
    log_error "session: nao foi possivel resolver path do repo principal"
    return 1
  }
}

# _session_validate_name <name>: valida nome de sessao em 2 etapas.
# Etapa 1: regex POSIX. Etapa 2: blocklist hardcoded.
# Retorna exit CSTK_SESSION_EXIT_INVALID_NAME (5) em ambos os casos.
_session_validate_name() {
  _name=${1:-}
  if [ -z "$_name" ]; then
    log_error "session: nome de sessao obrigatorio"
    return 2
  fi
  # Regex: alfanumerico lowercase + hifen, comecando com alfanumerico,
  # ate 63 chars no total.
  if ! printf '%s' "$_name" | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$'; then
    log_error "session: nome '$_name' invalido"
    log_error "session: use kebab-case ASCII: [a-z0-9][a-z0-9-]{0,62}"
    return "$CSTK_SESSION_EXIT_INVALID_NAME"
  fi
  # Blocklist: rejeita nomes reservados que confundem o git.
  for _reserved in $_CSTK_SESSION_BLOCKLIST; do
    if [ "$_name" = "$_reserved" ]; then
      log_error "session: nome '$_name' reservado"
      log_error "session: blocklist: $_CSTK_SESSION_BLOCKLIST"
      log_error "session: use prefixo (ex: 'feat-$_name')"
      return "$CSTK_SESSION_EXIT_INVALID_NAME"
    fi
  done
  return 0
}

# _session_default_branch: imprime nome da default branch do remote
# (sem prefixo refs/remotes/origin/). Fallback hardcoded para "main"
# se `origin/HEAD` nao esta setado no repo.
_session_default_branch() {
  if _sr=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "$_sr" | sed 's@^refs/remotes/origin/@@'
    return 0
  fi
  printf 'main\n'
  return 0
}

# _session_session_path <name>: imprime path absoluto da worktree-sessao
# computado como `<parent-of-repo>/<repo-name>-<name>`.
_session_session_path() {
  _name=${1:?_session_session_path: --name required}
  _repo=$(_session_resolve_repo) || return 1
  _parent=$(dirname -- "$_repo")
  _repo_name=$(basename -- "$_repo")
  printf '%s/%s-%s\n' "$_parent" "$_repo_name" "$_name"
}

# _session_find_worktree <name>: localiza worktree de sessao por nome em
# `git worktree list --porcelain`. Imprime 4 linhas:
#   path:<abs-path>
#   branch:<branch-name>
#   head:<sha>
#   prunable:<reason-or-empty>
# Retorna exit 0 se encontrada, exit 1 se nao encontrada.
#
# Implementacao via awk para semantica robusta com substring extraction
# (paths com espaco sao preservados — $2 quebraria neles).
_session_find_worktree() {
  _name=${1:?_session_find_worktree: --name required}
  _target_path=$(_session_session_path "$_name") || return 1
  _result=$(git worktree list --porcelain 2>/dev/null \
    | awk -v target="$_target_path" '
      BEGIN { path=""; head=""; branch=""; prunable="" }
      /^worktree / {
        # Flush previous block if matched
        if (path == target) {
          printf "path:%s\nbranch:%s\nhead:%s\nprunable:%s\n", path, branch, head, prunable
          found=1; exit
        }
        path=substr($0, length("worktree ")+1)
        head=""; branch=""; prunable=""
      }
      /^HEAD / { head=substr($0, length("HEAD ")+1) }
      /^branch refs\/heads\// { branch=substr($0, length("branch refs/heads/")+1) }
      /^prunable/ {
        # "prunable <reason>" or just "prunable"
        if (length($0) > length("prunable ")) {
          prunable=substr($0, length("prunable ")+1)
        } else {
          prunable="prunable"
        }
      }
      END {
        if (path == target && !found) {
          printf "path:%s\nbranch:%s\nhead:%s\nprunable:%s\n", path, branch, head, prunable
        }
      }
    ')
  if [ -z "$_result" ]; then
    return 1
  fi
  printf '%s\n' "$_result"
  return 0
}

# _session_branch_is_merged <branch> <default-branch>: retorna exit 0 se
# <branch> e ancestor de <default-branch> (ja mergeada ou nao divergiu).
# Exit 1 caso contrario.
_session_branch_is_merged() {
  _branch=${1:?_session_branch_is_merged: --branch required}
  _default=${2:?_session_branch_is_merged: --default required}
  git merge-base --is-ancestor "$_branch" "$_default" 2>/dev/null
}

# _session_gh_status: valida disponibilidade do `gh` em 2 passos.
# Imprime e retorna:
#   exit 0  — gh instalado e autenticado
#   exit 11 — gh nao instalado
#   exit 12 — gh instalado mas nao autenticado (inclui credenciais expiradas)
_session_gh_status() {
  if ! command -v gh >/dev/null 2>&1; then
    return "$CSTK_SESSION_EXIT_GH_MISSING"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    return "$CSTK_SESSION_EXIT_GH_UNAUTH"
  fi
  return 0
}

# _session_branch_exists_local <name>: exit 0 se branch local existe.
_session_branch_exists_local() {
  _name=${1:?_session_branch_exists_local: --name required}
  _out=$(git branch --list -- "$_name" 2>/dev/null)
  [ -n "$_out" ]
}

# _session_branch_exists_remote <name>: exit 0 se branch existe em origin.
_session_branch_exists_remote() {
  _name=${1:?_session_branch_exists_remote: --name required}
  git rev-parse --verify "refs/remotes/origin/$_name" >/dev/null 2>&1
}

# _session_prompt_yn <question>: imprime question em stderr e le resposta
# em stdin. Exit 0 se y/Y, exit 1 caso contrario (incluindo vazio).
# Em ambientes nao-interativos (stdin sem TTY ou redirecionado), tambem
# le do stdin — testes injetam via `echo y | ...`.
_session_prompt_yn() {
  _question=${1:?_session_prompt_yn: --question required}
  printf '%s ' "$_question" >&2
  read -r _ans || _ans=""
  case "$_ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# _session_copy_claude_filtered <src> <dst>: copia <src>/.claude/ para <dst>
# excluindo os 9 artefatos runtime/per-env listados em FR-002 (+extensao).
# Estrategia: `cp -R` (POSIX) seguido de `rm -rf` da blocklist. Custo de
# copiar arquivos que serao removidos e baixo (.claude/ tipicamente <50MB).
# Sem rsync (nao POSIX em macOS antigo).
#
# BUGFIX (aninhamento .claude/.claude): quando o repo VERSIONA arquivos de
# .claude/ no git, o `git worktree add` ja materializa <dst> no checkout;
# `cp -R src dst` com dst existente copia src PARA DENTRO de dst (semantica
# POSIX), criando <wt>/.claude/.claude/ — fora do alcance da blocklist.
# Fix: mkdir -p + copia de CONTEUDO (`src/.`), merge idempotente que nunca
# aninha, exista ou nao o destino.
_session_copy_claude_filtered() {
  _src=${1:?_session_copy_claude_filtered: --src required}
  _dst=${2:?_session_copy_claude_filtered: --dst required}
  if [ ! -d "$_src" ]; then
    # Sem .claude/ na origem: nada a copiar (no-op silencioso)
    return 0
  fi
  mkdir -p -- "$_dst" || return 1
  cp -R -- "$_src/." "$_dst" || return 1
  # Defesa contra rm -rf // se $_dst expandir vazio.
  for _pattern in $_CSTK_SESSION_CLAUDE_EXCLUDES; do
    rm -rf -- "${_dst:?}/$_pattern" 2>/dev/null
  done
  return 0
}

# ==== Subcomando: start ====
#
# cstk session start <name> [--reset|--reuse] [--force]
#
# Cria worktree em <parent-of-repo>/<repo-name>-<name> com branch <name>
# resolvida segundo FR-001 (5 regras):
#   1. Sem local / sem origin       → -b <name> <default>          (nova)
#   2. Sem local / com origin       → -b <name> --track origin/<n> (rastreia)
#   3. Local + nao mergeada         → <name>                       (reutiliza)
#   4. Local + ja mergeada          → recusa exit 8 sem flag;
#                                     --reset recria de <default>;
#                                     --reuse usa HEAD atual
#   5. Local + --reset + commits    → prompt p/ confirmar descarte;
#      nao-mergeados                  --force bypassa
#
# Apos worktree criada, copia .claude/ filtrado (FR-002, 9 exclusoes).
# Falha parcial (cp falhou apos worktree criada): stderr orientativo,
# exit 1 (FR-017).
_session_start() {
  # Parse args
  _name=""
  _reset=0
  _reuse=0
  _force=0
  _launch_claude=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reset)  _reset=1; shift ;;
      --reuse)  _reuse=1; shift ;;
      --force)  _force=1; shift ;;
      --claude) _launch_claude=1; shift ;;
      --) shift; break ;;
      -*) log_error "session start: flag desconhecida: $1"; return 2 ;;
      *)
        if [ -z "$_name" ]; then
          _name=$1; shift
        else
          log_error "session start: argumento extra inesperado: $1"
          return 2
        fi
        ;;
    esac
  done

  # Mutex check
  if [ "$_reset" = 1 ] && [ "$_reuse" = 1 ]; then
    log_error "session start: --reset e --reuse sao mutuamente exclusivos"
    return 2
  fi

  # Validar nome (delega exit 5)
  _session_validate_name "$_name" || return $?

  # Resolver paths
  _repo=$(_session_resolve_repo) || return 1
  _session_path=$(_session_session_path "$_name") || return 1

  # Verificar path destino livre (exit 7)
  if [ -e "$_session_path" ]; then
    log_error "session start: path destino ocupado: $_session_path"
    log_error "session start: use outro nome ou remova o diretorio manualmente"
    return "$CSTK_SESSION_EXIT_PATH_OCCUPIED"
  fi

  # Verificar sessao ja existente como worktree (exit 6)
  if _session_find_worktree "$_name" >/dev/null 2>&1; then
    log_error "session start: sessao '$_name' ja existe em $_session_path"
    return "$CSTK_SESSION_EXIT_ALREADY_EXISTS"
  fi

  # Resolver branch (5 regras de FR-001)
  _default=$(_session_default_branch)
  _git_args=""
  _note=""

  if ( cd -- "$_repo" && _session_branch_exists_local "$_name" ); then
    # Branch local existe. Ordem de precedencia: --reset > --reuse > default.
    if [ "$_reset" = 1 ]; then
      # --reset: SEMPRE recria do default branch.
      # Se ha commits nao-mergeados que serao descartados, exige confirmacao
      # (a menos que --force seja passado).
      _unmerged=$(cd -- "$_repo" && git rev-list "$_default..$_name" --count 2>/dev/null)
      _unmerged=${_unmerged:-0}
      if [ "$_unmerged" -gt 0 ] && [ "$_force" = 0 ]; then
        log_warn "session start: '--reset' descartara $_unmerged commit(s) nao-mergeado(s) em '$_name':"
        ( cd -- "$_repo" && git log "$_default..$_name" --oneline ) >&2
        _session_prompt_yn "Confirmar descarte? [y/N]:" || {
          log_error "session start: cancelado pelo usuario"
          return "$CSTK_SESSION_EXIT_CANCELLED"
        }
      fi
      # Recriar branch do default
      ( cd -- "$_repo" && git branch -D "$_name" >/dev/null 2>&1 ) || true
      _git_args="-b $_name $_default"
      _note="(recriada do $_default)"
    elif [ "$_reuse" = 1 ]; then
      _git_args="$_name"
      _note="(existente reutilizada, --reuse)"
    elif ( cd -- "$_repo" && _session_branch_is_merged "$_name" "$_default" ); then
      # Branch ja mergeada sem flag — exit 8
      log_error "session start: branch '$_name' ja mergeada em $_default"
      log_error "session start: use --reset para recriar do $_default, ou --reuse para forcar reutilizar HEAD atual"
      return "$CSTK_SESSION_EXIT_BRANCH_MERGED"
    else
      # Branch local nao mergeada e sem flag — reutilizar (regra 3)
      _git_args="$_name"
      _note="(existente reutilizada)"
    fi
  elif ( cd -- "$_repo" && _session_branch_exists_remote "$_name" ); then
    # Branch existe em origin mas nao local — criar rastreando (regra 2)
    _git_args="-b $_name --track origin/$_name"
    _note="(rastreando origin/$_name)"
  else
    # Branch nova do default (regra 1)
    _git_args="-b $_name $_default"
    _note="(nova)"
  fi

  # Executar git worktree add. POSIX: word-splitting controlado em
  # $_git_args (gerado internamente; $_name ja validado por regex).
  # shellcheck disable=SC2086
  if ! ( cd -- "$_repo" && git worktree add "$_session_path" $_git_args >/dev/null 2>&1 ); then
    log_error "session start: 'git worktree add' falhou"
    log_error "session start: investigue: cd $_repo && git worktree add $_session_path $_git_args"
    return 1
  fi

  # Copiar .claude/ filtrado (FR-002). Falha aqui = falha parcial (FR-017).
  _src_claude="$_repo/.claude"
  _dst_claude="$_session_path/.claude"
  if ! _session_copy_claude_filtered "$_src_claude" "$_dst_claude"; then
    log_error "session start: falha ao copiar .claude/ — worktree criada mas .claude/ pode estar incompleto"
    log_error "session start: para limpar, rode: cstk session end '$_name' --force"
    return 1
  fi

  # Output de sucesso (FR-001 / SC-006). Se --claude foi pedido, omite a
  # linha "Proximo passo" e dispara o launch logo em seguida.
  if [ "$_launch_claude" = 1 ]; then
    cat <<EOF
✓ Sessao '$_name' criada
  branch: $_name $_note
  path:   $_session_path
  .claude/ copiado (excluindo 8 artefatos runtime/per-env)
EOF
  else
    cat <<EOF
✓ Sessao '$_name' criada
  branch: $_name $_note
  path:   $_session_path
  .claude/ copiado (excluindo 8 artefatos runtime/per-env)

Proximo passo: cd $_session_path
EOF
    return 0
  fi

  # --claude: entra no diretorio e dispara o Claude Code (exec).
  # Falha tardia: sessao ja foi criada, entao o exit 1 vem com hint manual.
  if ! command -v claude >/dev/null 2>&1; then
    log_error "session start: --claude usado mas binario 'claude' nao encontrado no PATH"
    log_error "session start: sessao criada com sucesso; instale o Claude Code ou rode manualmente: cd $_session_path && claude"
    return 1
  fi
  if ! cd -- "$_session_path" 2>/dev/null; then
    log_error "session start: --claude usado mas falhou ao entrar em $_session_path"
    log_error "session start: sessao criada; rode manualmente: cd $_session_path && claude"
    return 1
  fi
  printf 'Iniciando Claude Code em %s...\n' "$_session_path"
  exec claude
}

# ==== Subcomando: list ====
#
# cstk session list [--json]
#
# Lista sessoes ativas (worktrees alem da principal) com colunas:
#   NAME / BRANCH / IDLE / STATUS / PATH
#
# STATUS combina marcadores separados por virgula:
#   CURRENT (worktree atual, se rodado de dentro de uma sessao)
#   *       (dirty, mudancas nao commitadas)
#   STALE   (path nao existe no FS — git worktree prunable)
#
# --json: array JSON em camelCase (FR-008), com campo `current: bool`.
#
# Ordenacao: por idle_days ASC (mais ativa primeiro).
# Rodape "tip: rode 'git worktree prune'..." se houver pelo menos 1 STALE
# (suprimido em modo --json).
_session_list() {
  _json=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) _json=1; shift ;;
      --) shift; break ;;
      -*) log_error "session list: flag desconhecida: $1"; return 2 ;;
      *) log_error "session list: argumento inesperado: $1"; return 2 ;;
    esac
  done

  _repo=$(_session_resolve_repo) || return 1
  _repo_name=$(basename -- "$_repo")
  _now=$(date -u +%s)

  # CWD canonico, usado para detectar a worktree atual.
  _cwd=$(pwd -P 2>/dev/null) || _cwd=""

  # Coletar sessoes: parsear `git worktree list --porcelain` via awk.
  # awk emite uma linha por sessao (excluindo principal), formato:
  #   <name><TAB><branch><TAB><path><TAB><head><TAB><prunable>
  # onde <prunable> e "1" ou "0" (booleano string).
  _tab=$(printf '\t')
  _raw=$(git -C "$_repo" worktree list --porcelain 2>/dev/null \
    | awk -v repo="$_repo" -v repo_name="$_repo_name" -v tab="$_tab" '
      function flush() {
        if (path != "" && path != repo) {
          # Derive name: basename(path) com prefixo "<repo-name>-" removido (se aplicavel)
          n = path
          sub(".*/", "", n)
          prefix = repo_name "-"
          if (substr(n, 1, length(prefix)) == prefix) {
            n = substr(n, length(prefix) + 1)
          }
          printf "%s%s%s%s%s%s%s%s%s\n", n, tab, branch, tab, path, tab, head, tab, prunable
        }
      }
      BEGIN { path=""; head=""; branch=""; prunable="0" }
      /^worktree / { flush(); path=substr($0, length("worktree ")+1); head=""; branch=""; prunable="0" }
      /^HEAD / { head=substr($0, length("HEAD ")+1) }
      /^branch refs\/heads\// { branch=substr($0, length("branch refs/heads/")+1) }
      /^prunable/ { prunable="1" }
      END { flush() }
    ')

  if [ -z "$_raw" ]; then
    if [ "$_json" = 1 ]; then
      printf '[]\n'
    else
      printf 'nenhuma sessao ativa\n'
    fi
    return 0
  fi

  # Enriquecer cada linha com idle_days, dirty, current.
  # Output enriquecido (7 colunas separadas por TAB):
  #   <name><T><branch><T><path><T><idle><T><dirty><T><stale><T><current>
  # Estrategia: subshell while escreve em stdout, capturado por $().
  _enriched=$(printf '%s\n' "$_raw" | while IFS="$_tab" read -r _n _b _p _h _pr; do
    [ -n "$_n" ] || continue
    if [ "$_pr" = "1" ]; then
      _stale=1
      _idle=-1
      _dirty=0
    else
      _stale=0
      _ct=$(git -C "$_repo" log -1 --format=%ct "$_b" 2>/dev/null)
      if [ -n "$_ct" ]; then
        _idle=$(( (_now - _ct) / 86400 ))
      else
        _idle=-1
      fi
      _st=$(git -C "$_p" status --porcelain 2>/dev/null)
      if [ -n "$_st" ]; then
        _dirty=1
      else
        _dirty=0
      fi
    fi
    if [ -n "$_cwd" ] && [ "$_p" = "$_cwd" ]; then
      _curr=1
    else
      _curr=0
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$_n" "$_b" "$_p" "$_idle" "$_dirty" "$_stale" "$_curr"
  done)

  # has_stale: derivado do _enriched (coluna 6 == 1 em alguma linha)
  _has_stale=0
  if printf '%s\n' "$_enriched" | awk -F"$_tab" '$6 == 1 { found=1 } END { exit !found }'; then
    _has_stale=1
  fi

  # Ordenar por idle_days ASC (coluna 4).
  _sorted=$(printf '%s\n' "$_enriched" | sort -t"$_tab" -k4,4n)

  if [ "$_json" = 1 ]; then
    # Emit JSON array. Sem jq — usar POSIX printf/sed para escapar strings.
    # name/branch/path: minimal escape (\ e ").
    printf '['
    _first=1
    printf '%s\n' "$_sorted" | while IFS="$_tab" read -r _n _b _p _idle _dirty _stale _curr; do
      [ -n "$_n" ] || continue
      if [ "$_first" = 1 ]; then
        _first=0
      else
        printf ','
      fi
      # Bools JSON
      _dirty_j="false"; [ "$_dirty" = 1 ] && _dirty_j="true"
      _stale_j="false"; [ "$_stale" = 1 ] && _stale_j="true"
      _curr_j="false"; [ "$_curr" = 1 ] && _curr_j="true"
      # Escape simples: \ -> \\ e " -> \" (sed)
      _ne=$(printf '%s' "$_n" | sed 's/\\/\\\\/g; s/"/\\"/g')
      _be=$(printf '%s' "$_b" | sed 's/\\/\\\\/g; s/"/\\"/g')
      _pe=$(printf '%s' "$_p" | sed 's/\\/\\\\/g; s/"/\\"/g')
      printf '{"name":"%s","branch":"%s","path":"%s","idleDays":%s,"dirty":%s,"stale":%s,"current":%s}' \
        "$_ne" "$_be" "$_pe" "$_idle" "$_dirty_j" "$_stale_j" "$_curr_j"
    done
    printf ']\n'
    return 0
  fi

  # Modo tabela humana. Calcular larguras das colunas via awk
  # (POSIX-safe: nao usa loop shell com `[ -gt ]` que estoura set -e).
  _idle_w=4    # "IDLE"
  _status_w=6  # "STATUS"
  _tmp_widths=$(printf '%s\n' "$_sorted" | awk -F"$_tab" '
    BEGIN { nw=4; bw=6 }
    NF >= 2 {
      if (length($1) > nw) nw=length($1)
      if (length($2) > bw) bw=length($2)
    }
    END { printf "%d %d\n", nw, bw }
  ')
  _name_w=$(printf '%s' "$_tmp_widths" | cut -d' ' -f1)
  _branch_w=$(printf '%s' "$_tmp_widths" | cut -d' ' -f2)

  # Cabecalho
  printf '%-*s  %-*s  %-*s  %-*s  %s\n' \
    "$_name_w" "NAME" "$_branch_w" "BRANCH" "$_idle_w" "IDLE" \
    "$_status_w" "STATUS" "PATH"

  printf '%s\n' "$_sorted" | while IFS="$_tab" read -r _n _b _p _idle _dirty _stale _curr; do
    [ -n "$_n" ] || continue
    # Construir STATUS combinando marcadores
    _status=""
    if [ "$_curr" = 1 ]; then
      _status="CURRENT"
    fi
    if [ "$_dirty" = 1 ]; then
      [ -n "$_status" ] && _status="${_status},*" || _status="*"
    fi
    if [ "$_stale" = 1 ]; then
      [ -n "$_status" ] && _status="${_status},STALE" || _status="STALE"
    fi
    # IDLE: "-" se idle=-1 (sem commits), senao "Nd"
    if [ "$_idle" = "-1" ]; then
      _idle_disp="-"
    else
      _idle_disp="${_idle}d"
    fi
    printf '%-*s  %-*s  %-*s  %-*s  %s\n' \
      "$_name_w" "$_n" "$_branch_w" "$_b" "$_idle_w" "$_idle_disp" \
      "$_status_w" "$_status" "$_p"
  done

  # Rodape de tip apenas se ha pelo menos 1 STALE.
  if [ "$_has_stale" = 1 ]; then
    printf '\ntip: rode '\''git worktree prune'\'' para limpar worktrees stale\n'
  fi
  return 0
}

# ==== Subcomando: end ====
#
# cstk session end <name> [--force]
#
# Remove worktree + branch local com guards:
#   1. Detecta self-end (FR-018): rodando de dentro da propria worktree-alvo
#      -> exit 14
#   2. Resolve sessao por nome (exit 9 se nao encontrada)
#   3. Detecta dirty (mudancas nao commitadas)
#   4. Detecta unpushed_commits (commits a frente de origin/<branch>)
#   5. Detecta PR aberto via gh (opcional — pula se gh ausente/unauth, FR-005)
#   6. Se --force NAO passado E (dirty OR unpushed > 0 OR PR aberto):
#      prompt interativo; cancelar = exit 10
#   7. Preserva artefatos 00c da worktree (.claude/feature-00c-state/*,
#      agente-00c-state, report, enforcement-log) copiando para o .claude/
#      do checkout principal ANTES da remocao. Fail-closed: falha de copia
#      aborta sem remover. --discard-state pula (descarte deliberado).
#   8. Executa git worktree remove + git branch -D
#   9. Falha parcial (FR-006): se worktree remove succeed mas branch -D
#      falhou, stderr indica estado residual
# ==== Preservacao de state 00c no `end` ====
#
# `.claude/` e tipicamente gitignored: state.db/state.json, rounds, backups,
# report e enforcement-log de execucoes 00c rodadas na worktree nao tem
# rastro no git — `git worktree remove` os destruiria em silencio. Antes da
# remocao, copia esses artefatos para o .claude/ do checkout principal:
#   - .claude/feature-00c-state/<short>/   (granularidade por feature)
#   - itens de _CSTK_SESSION_STATE_ARTIFACTS
# Colisao (destino ja existe) NUNCA sobrescreve: a copia vai para
# .claude/session-state-backup/<session>/<relpath>. Falha de copia BLOQUEIA
# a remocao (fail-closed) — worktree residual e recuperavel, state deletado
# nao. Descarte deliberado exige --discard-state.
_session_preserve_state() {
  _ps_wt=$1
  _ps_repo=$2
  _ps_session=$3
  _CSTK_SESSION_PRESERVED_COUNT=0
  _ps_src="$_ps_wt/.claude"
  [ -d "$_ps_src" ] || return 0
  if [ -d "$_ps_src/feature-00c-state" ]; then
    for _ps_dir in "$_ps_src/feature-00c-state"/*/; do
      [ -d "$_ps_dir" ] || continue
      _ps_short=$(basename "${_ps_dir%/}")
      _session_preserve_one "${_ps_dir%/}" "feature-00c-state/$_ps_short" \
        "$_ps_repo" "$_ps_session" || return 1
    done
  fi
  for _ps_item in $_CSTK_SESSION_STATE_ARTIFACTS; do
    [ -e "$_ps_src/$_ps_item" ] || continue
    _session_preserve_one "$_ps_src/$_ps_item" "$_ps_item" \
      "$_ps_repo" "$_ps_session" || return 1
  done
  return 0
}

# _session_preserve_one <src-path> <relpath> <repo> <session>
# Copia 1 artefato para <repo>/.claude/<relpath>; se ja existe, para
# <repo>/.claude/session-state-backup/<session>/<relpath>.
_session_preserve_one() {
  _po_src=$1
  _po_rel=$2
  _po_dest="$3/.claude/$_po_rel"
  _po_session=$4
  if [ -e "$_po_dest" ]; then
    _po_dest="$3/.claude/session-state-backup/$_po_session/$_po_rel"
    if [ -e "$_po_dest" ]; then
      log_error "session end: destino de preservacao ja existe: $_po_dest"
      log_error "session end: mova/remova o backup anterior e rode de novo, ou use --discard-state para descartar o state da worktree"
      return 1
    fi
    log_warn "session end: '.claude/$_po_rel' ja existe no checkout principal — copia preservada em $_po_dest"
  fi
  _po_parent=$(dirname "$_po_dest")
  if ! mkdir -p -- "$_po_parent" || ! cp -R -- "$_po_src" "$_po_dest"; then
    log_error "session end: falha ao preservar '.claude/$_po_rel' — worktree NAO sera removida"
    log_error "session end: copie manualmente ou rode com --discard-state (descarta o state)"
    return 1
  fi
  _CSTK_SESSION_PRESERVED_COUNT=$((_CSTK_SESSION_PRESERVED_COUNT + 1))
  return 0
}

_session_end() {
  _name=""
  _force=0
  _discard_state=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --force) _force=1; shift ;;
      --discard-state) _discard_state=1; shift ;;
      --) shift; break ;;
      -*) log_error "session end: flag desconhecida: $1"; return 2 ;;
      *)
        if [ -z "$_name" ]; then
          _name=$1; shift
        else
          log_error "session end: argumento extra inesperado: $1"
          return 2
        fi
        ;;
    esac
  done

  if [ -z "$_name" ]; then
    log_error "session end: nome de sessao obrigatorio"
    return 2
  fi

  _repo=$(_session_resolve_repo) || return 1

  # Resolver sessao (exit 9)
  _info=$(_session_find_worktree "$_name" 2>/dev/null) || {
    log_error "session end: sessao '$_name' nao encontrada"
    log_error "session end: rode 'cstk session list' para ver sessoes ativas"
    return "$CSTK_SESSION_EXIT_NOT_FOUND"
  }
  _wt_path=$(printf '%s\n' "$_info" | awk -F: '/^path:/ { print substr($0, length("path:")+1) }')
  _wt_branch=$(printf '%s\n' "$_info" | awk -F: '/^branch:/ { print substr($0, length("branch:")+1) }')

  # FR-018: Self-end detection. Comparar CWD canonico com path da sessao.
  _cwd=$(pwd -P 2>/dev/null) || _cwd=""
  if [ -n "$_cwd" ] && [ "$_cwd" = "$_wt_path" ]; then
    log_error "session end: nao e possivel encerrar a sessao atual"
    log_error "session end: rode de outra worktree (principal ou outra sessao)"
    return "$CSTK_SESSION_EXIT_SELF_END"
  fi

  # Detectar dirty (apenas se path ainda existe)
  _dirty_count=0
  if [ -d "$_wt_path" ]; then
    _porc=$(git -C "$_wt_path" status --porcelain 2>/dev/null)
    if [ -n "$_porc" ]; then
      # Contar linhas do porcelain (1 linha = 1 arquivo afetado)
      _dirty_count=$(printf '%s\n' "$_porc" | wc -l | tr -d ' ')
    fi
  fi

  # Detectar unpushed commits (commits a frente de origin/<branch>).
  # Pula silenciosamente se origin/<branch> nao existe (branch nunca pushada).
  _unpushed=0
  if [ -d "$_wt_path" ]; then
    if git -C "$_wt_path" rev-parse --verify "refs/remotes/origin/$_wt_branch" >/dev/null 2>&1; then
      _unpushed=$(git -C "$_wt_path" rev-list "origin/$_wt_branch..$_wt_branch" --count 2>/dev/null)
      _unpushed=${_unpushed:-0}
    fi
  fi

  # PR check via gh (FR-005, opcional).
  # Capturar exit code SEM deixar set -e abortar — usar `|| _gh_rc=$?`.
  _pr_open=0
  _pr_url=""
  _gh_rc=0
  _session_gh_status >/dev/null 2>&1 || _gh_rc=$?
  if [ "$_gh_rc" = 0 ]; then
    # gh OK — tentar consultar PR
    _pr_json=$(gh pr view "$_wt_branch" --json state,url 2>/dev/null) || _pr_json=""
    if [ -n "$_pr_json" ]; then
      # Parse manual (sem jq, FR de POSIX puro). Estado pode ser OPEN/MERGED/CLOSED.
      case "$_pr_json" in
        *'"state":"OPEN"'*)
          _pr_open=1
          # Extrair URL via sed
          _pr_url=$(printf '%s' "$_pr_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
          ;;
      esac
    fi
  else
    log_warn "PR check pulado: gh ausente/unauth"
  fi

  # Prompt se ha qualquer warning (e nao --force)
  if [ "$_force" = 0 ] \
     && { [ "$_dirty_count" -gt 0 ] || [ "$_unpushed" -gt 0 ] || [ "$_pr_open" = 1 ]; }; then
    [ "$_dirty_count" -gt 0 ] \
      && log_warn "session end: '$_name' tem $_dirty_count arquivo(s) modificado(s) nao commitado(s)"
    [ "$_unpushed" -gt 0 ] \
      && log_warn "session end: '$_name' tem $_unpushed commit(s) nao pushado(s) para origin/$_wt_branch"
    [ "$_pr_open" = 1 ] \
      && log_warn "session end: PR ainda OPEN no GitHub ($_pr_url)"
    _session_prompt_yn "Confirmar remocao? [y/N]:" || {
      log_error "session end: cancelado pelo usuario"
      return "$CSTK_SESSION_EXIT_CANCELLED"
    }
  fi

  # Preservar artefatos 00c ANTES da remocao (fail-closed). --discard-state
  # pula deliberadamente — unica forma de remover a worktree sem trazer o
  # state para o checkout principal.
  _CSTK_SESSION_PRESERVED_COUNT=0
  if [ "$_discard_state" = 1 ]; then
    if [ -d "$_wt_path/.claude/feature-00c-state" ] \
       || [ -d "$_wt_path/.claude/agente-00c-state" ]; then
      log_warn "session end: --discard-state — artefatos 00c da worktree serao DESCARTADOS"
    fi
  elif [ -d "$_wt_path" ]; then
    _session_preserve_state "$_wt_path" "$_repo" "$_name" || return 1
  fi

  # Remover worktree (com --force se dirty/unpushed e --force foi passado;
  # OU se path nao existe mais — stale precisa de --force)
  _wtr_flags=""
  if [ "$_force" = 1 ] || [ "$_dirty_count" -gt 0 ] || [ ! -d "$_wt_path" ]; then
    _wtr_flags="--force"
  fi
  # shellcheck disable=SC2086
  if ! ( cd -- "$_repo" && git worktree remove $_wtr_flags "$_wt_path" >/dev/null 2>&1 ); then
    log_error "session end: 'git worktree remove' falhou para '$_wt_path'"
    log_error "session end: investigue: git -C $_repo worktree remove --force $_wt_path"
    return 1
  fi

  # Deletar branch local (FR-006). Falha parcial = avisa estado residual.
  if ! ( cd -- "$_repo" && git branch -D "$_wt_branch" >/dev/null 2>&1 ); then
    log_warn "session end: worktree removida MAS branch local '$_wt_branch' nao foi deletada"
    log_warn "session end: rode 'git -C $_repo branch -D $_wt_branch' manualmente"
    return 1
  fi

  cat <<EOF
✓ Sessao '$_name' removida
  worktree: $_wt_path (removida)
  branch:   $_wt_branch (deletada)
EOF
  if [ "${_CSTK_SESSION_PRESERVED_COUNT:-0}" -gt 0 ]; then
    printf '  state:    %s artefato(s) 00c preservado(s) em %s/.claude\n' \
      "$_CSTK_SESSION_PRESERVED_COUNT" "$_repo"
  fi
  return 0
}

# ==== Subcomando: pr ====
#
# cstk session pr <name> [--draft] [--title TITLE] [--body BODY] [--reviewer USER]
#
# Abre PR da branch da sessao para o default branch via gh CLI.
# Ordem de validacao:
#   1. Sessao existe (exit 9 se nao)
#   2. gh instalado (exit 11) e autenticado (exit 12)
#   3. Branch tem commits a frente do default (exit 13 se zero)
#   4. Idempotencia: se PR existe (OPEN/MERGED), retorna URL + exit 0
#   5. Push da branch (idempotente — git nao re-pushe se ja sincronizado)
#   6. gh pr create com flags repassadas
#   7. Falha parcial (FR-017): push OK + gh create falhou → stderr orientativo
_session_pr() {
  _name=""
  _draft=0
  _title=""
  _body=""
  _reviewers=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --draft)    _draft=1; shift ;;
      --title)    _title=${2:?--title exige valor}; shift 2 ;;
      --body)     _body=${2:?--body exige valor}; shift 2 ;;
      --reviewer) _reviewers="$_reviewers ${2:?--reviewer exige valor}"; shift 2 ;;
      --) shift; break ;;
      -*) log_error "session pr: flag desconhecida: $1"; return 2 ;;
      *)
        if [ -z "$_name" ]; then
          _name=$1; shift
        else
          log_error "session pr: argumento extra inesperado: $1"
          return 2
        fi
        ;;
    esac
  done

  if [ -z "$_name" ]; then
    log_error "session pr: nome de sessao obrigatorio"
    return 2
  fi

  _repo=$(_session_resolve_repo) || return 1

  # 1. Sessao existe?
  _info=$(_session_find_worktree "$_name" 2>/dev/null) || {
    log_error "session pr: sessao '$_name' nao encontrada"
    log_error "session pr: rode 'cstk session list' para ver sessoes ativas"
    return "$CSTK_SESSION_EXIT_NOT_FOUND"
  }
  _wt_path=$(printf '%s\n' "$_info" | awk -F: '/^path:/ { print substr($0, length("path:")+1) }')
  _wt_branch=$(printf '%s\n' "$_info" | awk -F: '/^branch:/ { print substr($0, length("branch:")+1) }')

  # 2. Detectar default branch + validar commits a frente (FR-009 ordem: a/b/c).
  # Validar commits ANTES de gh: assim, um operador sem gh autenticado em CI
  # ainda recebe exit 13 (sem commits) se for esse o problema real — gh check
  # vem depois pq e dep externa, validacao local tem precedencia.
  _default=$(_session_default_branch)
  _ahead=$(git -C "$_wt_path" rev-list "$_default..$_wt_branch" --count 2>/dev/null)
  _ahead=${_ahead:-0}
  if [ "$_ahead" = 0 ]; then
    log_error "session pr: branch '$_wt_branch' nao tem commits novos vs '$_default'"
    log_error "session pr: faca pelo menos 1 commit antes de abrir PR"
    return "$CSTK_SESSION_EXIT_NO_COMMITS"
  fi

  # 3. gh instalado + autenticado (capturar exit code sem set -e abort)
  _gh_rc=0
  _session_gh_status >/dev/null 2>&1 || _gh_rc=$?
  case "$_gh_rc" in
    0) ;;
    "$CSTK_SESSION_EXIT_GH_MISSING")
      log_error "session pr: gh CLI nao instalado"
      log_error "session pr: instale: https://cli.github.com"
      return "$CSTK_SESSION_EXIT_GH_MISSING"
      ;;
    "$CSTK_SESSION_EXIT_GH_UNAUTH")
      log_error "session pr: gh nao autenticado (ou credenciais expiradas)"
      log_error "session pr: rode: gh auth login"
      return "$CSTK_SESSION_EXIT_GH_UNAUTH"
      ;;
    *)
      log_error "session pr: erro inesperado em _session_gh_status (exit $_gh_rc)"
      return 1
      ;;
  esac

  # 4. Idempotencia: PR ja existe?
  _existing_json=$(gh pr view "$_wt_branch" --json url,state 2>/dev/null) || _existing_json=""
  if [ -n "$_existing_json" ]; then
    case "$_existing_json" in
      *'"state":"OPEN"'*|*'"state":"MERGED"'*)
        _existing_url=$(printf '%s' "$_existing_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
        printf '✓ PR ja existe: %s\n' "$_existing_url"
        return 0
        ;;
    esac
  fi

  # 5. Push da branch (idempotente — git nao re-pushe se ja sincronizado)
  if ! ( cd -- "$_wt_path" && git push -u origin "$_wt_branch" >/dev/null 2>&1 ); then
    log_error "session pr: 'git push -u origin $_wt_branch' falhou"
    log_error "session pr: investigue: cd $_wt_path && git push -u origin $_wt_branch"
    return 1
  fi

  # 6. gh pr create — construir flags posicionais (POSIX, sem array)
  # Sempre: --base <default> --head <branch>
  # Opcionais: --draft, --title, --body, --reviewer (multiplo)
  # Estrategia POSIX: usar `set --` para construir array de args.
  #
  # `--fill` de fallback: o `gh pr create` nao-interativo EXIGE titulo E
  # corpo. Medido em gh 2.67.0 — com `--head` de branch inexistente, para
  # isolar a validacao de flags de qualquer operacao git:
  #
  #   (sem flags)        -> "must provide `--title` and `--body` (or `--fill`
  #                          or `fill-first` or `--fillverbose`) when not
  #                          running interactively"  [FlagError]
  #   --title T          -> MESMO FlagError (titulo sozinho NAO basta)
  #   --title T --body B -> aceito
  #   --fill             -> aceito (falha so depois, ao computar defaults)
  #   --fill + --title/--body/--draft -> aceito (combinam)
  #
  # Por isso o gatilho e "faltou title OU body", nao "faltaram os dois":
  # `cstk session pr <n> --title foo` cai na MESMA falha do caso sem flag
  # nenhuma. Sem esse fallback o sintoma era push feito + PR nao criado,
  # com o gh cuspindo o help (mesma classe da sug-007 em commit-mode.sh
  # finalize, que so cobria o caso de ambos ausentes).
  set -- --base "$_default" --head "$_wt_branch"
  if [ "$_draft" = 1 ]; then
    set -- "$@" --draft
  fi
  if [ -z "$_title" ] || [ -z "$_body" ]; then
    set -- "$@" --fill
  fi
  if [ -n "$_title" ]; then
    set -- "$@" --title "$_title"
  fi
  if [ -n "$_body" ]; then
    set -- "$@" --body "$_body"
  fi
  if [ -n "$_reviewers" ]; then
    for _rv in $_reviewers; do
      set -- "$@" --reviewer "$_rv"
    done
  fi

  # Capturar URL do gh pr create. gh imprime URL em stdout em caso de sucesso.
  # `|| _create_rc=$?` e OBRIGATORIO: session_main roda sob o `set -eu` do
  # binario e `_x=$(cmd)` herda o exit de `cmd` — sem isso a falha do gh
  # abortava aqui e o ramo de falha parcial (FR-017) abaixo era codigo
  # morto (mesma classe da issue #139 em commit-mode.sh finalize).
  _create_rc=0
  _create_out=$( cd -- "$_wt_path" && gh pr create "$@" 2>&1 ) || _create_rc=$?
  if [ "$_create_rc" != 0 ]; then
    # 7. Falha parcial (FR-017): push ja foi feito, mas create falhou
    log_error "session pr: 'gh pr create' falhou (push ja foi feito)"
    log_error "session pr: stdout do gh: $_create_out"
    log_error "session pr: para retry manual: cd $_wt_path && gh pr create $*"
    log_error "session pr: para desfazer push: git -C $_wt_path push -d origin $_wt_branch"
    return 1
  fi

  # Extrair URL do output do gh (ultima linha que comeca com https://)
  _pr_url=$(printf '%s\n' "$_create_out" | grep -E '^https://' | tail -1)
  if [ -n "$_pr_url" ]; then
    printf '✓ PR criado: %s\n' "$_pr_url"
  else
    # gh nao emitiu URL parseavel — emitir output bruto
    printf '%s\n' "$_create_out"
  fi
  return 0
}

# ==== Dispatch ====

session_main() {
  _sub=${1:-}
  [ "$#" -ge 1 ] && shift || :
  case "$_sub" in
    ''|-h|--help|help)
      _session_print_help
      [ -z "$_sub" ] && return 2
      return 0
      ;;
    start|list|end|pr)
      _session_check_git_version || return $?
      "_session_$_sub" "$@"
      ;;
    *)
      log_error "session: subcomando desconhecido: '$_sub'"
      log_error "session: subcomandos validos: start, list, end, pr"
      return 2
      ;;
  esac
}
