#!/bin/sh
# bash-guard.sh — pre-validacao de comandos Bash (FR-018 + FR-028 + SC-008).
#
# Ref: docs/specs/agente-00c/spec.md FR-018 (whitelist), FR-028 (push/deploy)
#      docs/specs/agente-00c/threat-model.md T2, T5
#      docs/specs/agente-00c/constitution.md §V (Blast Radius Confinado)
#      docs/specs/agente-00c/tasks.md FASE 6.4 + 6.9
#
# Defesa em duas camadas:
#   1. blocklist regex — comandos que NUNCA podem rodar (sudo, package
#      managers no host, git push, kubectl apply, terraform apply, docker
#      push, helm install, git reset --hard, git clean -f, rm -rf fora de
#      areas temporarias, sqlite3 mutativo na knowledge.db, pipe de
#      curl/wget para shell, etc).
#   2. whitelist enforcement — comandos de rede (curl, wget, gh api/repo,
#      git fetch/clone) tem URL/dominio extraido e checado contra
#      external_urls_whitelist. Excecao escopada: `gh issue create
#      --repo JotJunior/cstk ...` bypass (ver briefing).
#
# Analise por SEGMENTO (split em `;|&`): o bypass historico de package
# manager ("basta 'docker run' coexistir em qualquer trecho") foi fechado —
# o prefixo docker exec/run precisa estar no MESMO segmento do install.
# Limitacao documentada: extracao de alvos de `rm` nao parseia quoting;
# caminhos via variavel ($VAR/...) passam — o guard e defesa em
# profundidade, nao sandbox.
#
# Subcomandos:
#   bash-guard.sh check-blocklist --command "CMD"
#       — Exit 0 se OK; exit 1 com motivo + padrao matched se bloqueado.
#       — NAO tem dependencia em state.json (defesa em profundidade
#         independente; pode ser invocada sem contexto de execucao).
#
#   bash-guard.sh check-whitelist --command "CMD" --whitelist-file FILE
#       — Para comandos de rede, extrai URL e checa contra whitelist.
#       — Exit 0 se nao e comando de rede OU URL na whitelist.
#       — Exit 1 se URL fora da whitelist (com mensagem clara).
#       — Excecao gh-issue-toolkit hardcoded.
#
#   bash-guard.sh check --command "CMD" --whitelist-file FILE
#       — Encadeia check-blocklist + check-whitelist.
#       — Exit 0 se ambos passam; exit 1 se algum bloqueia.
#
# Exit codes:
#   0 OK
#   1 violacao (blocklist OR whitelist)
#   2 uso incorreto
#
# POSIX sh + grep -E.

set -eu

_BG_NAME="bash-guard"
# Toolkit repo onde gh issue create e excecao escopada (briefing FR-021)
_BG_TOOLKIT_REPO="JotJunior/cstk"

_bg_die_usage() { printf '%s: %s\n' "$_BG_NAME" "$1" >&2; exit 2; }

# ---------- Blocklist ----------
#
# Regex aplicadas em sequencia. Cada padrao matched = bloqueio com motivo.
# Padroes empilhados em case statement para evitar dependencia em grep -E
# em todos os subcomandos.
_bg_check_blocklist_cmd() {
  _cmd=$1

  # Helper: testa regex via grep -E sobre o comando
  _bg_match() {
    printf '%s' "$_cmd" | grep -E "$1" >/dev/null 2>&1
  }

  # 1. sudo (FR-018, qualquer posicao)
  if _bg_match '(^|[[:space:];|&])sudo([[:space:]]|$)'; then
    _bg_emit_block "sudo" "qualquer uso de sudo bloqueado (FR-018)"
    return 1
  fi

  # 2. Package managers no host — bloqueia a menos que o PROPRIO segmento
  # comece com docker exec/run (`docker exec foo npm install` passa).
  # Segment-aware: fecha o bypass em que a mera coexistencia de
  # "docker run" liberava o comando inteiro (`npm install x; docker run y`).
  if _bg_pkg_violation '(^|[[:space:]])(npm|pnpm|yarn|pip|pip3|gem|brew)[[:space:]]+(install|i|add|update|upgrade)\b'; then
    _bg_emit_block "package-manager" "package install no host bloqueado (use 'docker exec/run' como wrapper no MESMO segmento)"
    return 1
  fi
  # `go install` / `cargo install`
  if _bg_pkg_violation '(^|[[:space:]])(go|cargo)[[:space:]]+install\b'; then
    _bg_emit_block "package-manager" "go/cargo install no host bloqueado"
    return 1
  fi

  # 3. git push (FR-028 — Constitution §V)
  # NOTA (atomic-commit-pr): raw `git push` permanece BLOQUEADO aqui, inclusive
  # no modo atomic-commit. O push confinado do modo atomic ocorre EXCLUSIVAMENTE
  # via `cstk session pr` (invocado por `commit-mode.sh finalize`), que nao
  # passa por este guard — e o unico caminho aprovado para push/PR automatizado.
  # NAO altere a regex abaixo sem revisao de seguranca (FR-028 / Constitution §V).
  if _bg_match '(^|[[:space:];|&])git[[:space:]]+push\b'; then
    _bg_emit_block "git-push" "git push bloqueado em qualquer remote (Principio V)"
    return 1
  fi

  # 4. Deploy externo (FR-028)
  if _bg_match '(^|[[:space:];|&])kubectl[[:space:]]+(apply|create|delete|patch|replace)\b'; then
    _bg_emit_block "kubectl" "kubectl mutativo bloqueado (use kubectl get/describe)"
    return 1
  fi
  if _bg_match '(^|[[:space:];|&])terraform[[:space:]]+(apply|destroy)\b'; then
    _bg_emit_block "terraform" "terraform apply/destroy bloqueado (use terraform plan)"
    return 1
  fi
  if _bg_match '(^|[[:space:];|&])aws[[:space:]]+[a-z0-9-]+[[:space:]]+(create|deploy|put-|update-|delete-)'; then
    _bg_emit_block "aws-cli" "aws cli mutativo bloqueado"
    return 1
  fi
  if _bg_match '(^|[[:space:];|&])gcloud[[:space:]]+[a-z0-9-]+[[:space:]]+deploy\b'; then
    _bg_emit_block "gcloud" "gcloud deploy bloqueado"
    return 1
  fi
  if _bg_match '(^|[[:space:];|&])docker[[:space:]]+push\b'; then
    _bg_emit_block "docker-push" "docker push bloqueado"
    return 1
  fi
  if _bg_match '(^|[[:space:];|&])docker-compose[[:space:]]+push\b'; then
    _bg_emit_block "docker-compose-push" "docker-compose push bloqueado"
    return 1
  fi
  if _bg_match '(^|[[:space:];|&])helm[[:space:]]+(install|upgrade|uninstall)\b'; then
    _bg_emit_block "helm" "helm install/upgrade/uninstall bloqueado"
    return 1
  fi

  # 5. Destrutivos de working tree / historico local (revisao 5.15.0 —
  # Constitution §V, Blast Radius Confinado: destroem trabalho
  # nao-commitado sem caminho de reversao).
  if _bg_match '(^|[[:space:];|&])git[[:space:]]+reset[[:space:]][^;|&]*--hard'; then
    _bg_emit_block "git-reset-hard" "git reset --hard bloqueado (destroi trabalho nao-commitado; use git stash)"
    return 1
  fi
  if _bg_match '(^|[[:space:];|&])git[[:space:]]+clean[[:space:]][^;|&]*-[A-Za-z]*f'; then
    _bg_emit_block "git-clean" "git clean com -f bloqueado (destroi untracked; inspecione com git clean -n)"
    return 1
  fi

  # 6. rm recursivo+forcado fora de areas temporarias (segment-aware).
  if ! _bg_check_rm_segments; then
    return 1
  fi

  # 7. Mutacao crua da knowledge.db via sqlite3. O indice e DERIVADO
  # (reconstituivel via cstk recall --reindex); escrita legitima ocorre
  # apenas dentro de cli/lib/recall.sh — nunca via sqlite3 avulso.
  if _bg_match '(^|[[:space:];|&])sqlite3[[:space:]][^;|&]*knowledge\.db'; then
    if printf '%s' "$_cmd" | grep -Ei '((^|[^A-Za-z])(insert|update|delete|drop|alter|replace|vacuum)([^A-Za-z]|$)|\.(restore|import)([^A-Za-z]|$))' >/dev/null 2>&1; then
      _bg_emit_block "sqlite3-knowledge-db" "sqlite3 mutativo na knowledge.db bloqueado (indice derivado; use cstk recall --ingest/--reindex)"
      return 1
    fi
  fi

  # 8. Pipe de downloader direto para shell — bloqueado mesmo com dominio
  # na whitelist (a whitelist valida a ORIGEM, nao o que se executa).
  if _bg_match '(^|[[:space:];|&])(curl|wget)[^;&]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash)([[:space:]]|$)'; then
    _bg_emit_block "pipe-to-shell" "pipe de curl/wget para shell bloqueado (baixe, inspecione e execute em passos separados)"
    return 1
  fi

  return 0
}

# ---------- Helpers segment-aware (revisao 5.15.0) ----------

# _bg_segments: divide $_cmd em segmentos (split em ; | &), um por linha.
_bg_segments() {
  printf '%s' "$_cmd" | tr ';|&' '\n\n\n'
}

# _bg_pkg_violation ERE -> 0 (violacao) se ALGUM segmento casa o padrao de
# install SEM comecar com docker exec/run.
_bg_pkg_violation() {
  _bg_segments \
    | grep -E "$1" 2>/dev/null \
    | grep -Ev '^[[:space:]]*docker[[:space:]]+(exec|run)[[:space:]]' \
    >/dev/null 2>&1
}

# _bg_rm_seg_check SEGMENTO -> 1 (bloqueio, ja emitido) quando o segmento e
# um `rm` com flags recursiva E forcada apontando para fora de areas
# temporarias. Alvos proibidos: `~`, `$HOME`, `..`, `.git` e caminho
# absoluto fora de /tmp//private/tmp//var/folders//private/var/folders/.
# rm -rf RELATIVO (build dirs) segue permitido. Sem parsing de quoting —
# caminho via variavel passa (limitacao documentada no cabecalho).
_bg_rm_seg_check() {
  _seg=$1
  printf '%s' "$_seg" | grep -E '(^|[[:space:]])rm[[:space:]]' >/dev/null 2>&1 || return 0
  printf '%s' "$_seg" | grep -E '(^|[[:space:]])(-[A-Za-z]*[rR][A-Za-z]*|--recursive)([[:space:]]|$)' >/dev/null 2>&1 || return 0
  printf '%s' "$_seg" | grep -E '(^|[[:space:]])(-[A-Za-z]*f[A-Za-z]*|--force)([[:space:]]|$)' >/dev/null 2>&1 || return 0

  if printf '%s' "$_seg" | grep -E '(^|[[:space:]])(~($|/)|\$HOME)' >/dev/null 2>&1 \
     || printf '%s' "$_seg" | grep -E '(^|[[:space:]/])\.\.(/|[[:space:]]|$)' >/dev/null 2>&1 \
     || printf '%s' "$_seg" | grep -E '(^|[[:space:]/])\.git(/|[[:space:]]|$)' >/dev/null 2>&1; then
    _bg_emit_block "rm-rf" "rm recursivo+forcado em ~, \$HOME, .. ou .git bloqueado (Constitution §V)"
    return 1
  fi
  _rm_toks=$(printf '%s' "$_seg" | grep -oE '(^|[[:space:]])/[^[:space:]]*' 2>/dev/null | sed 's/^[[:space:]]*//')
  [ -n "$_rm_toks" ] || return 0
  _rm_old_ifs=$IFS
  IFS='
'
  for _tok in $_rm_toks; do
    case "$_tok" in
      /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) : ;;
      *)
        IFS=$_rm_old_ifs
        _bg_emit_block "rm-rf" "rm recursivo+forcado em caminho absoluto fora de areas temporarias bloqueado: $_tok"
        return 1
        ;;
    esac
  done
  IFS=$_rm_old_ifs
  return 0
}

# _bg_check_rm_segments -> aplica _bg_rm_seg_check a cada segmento de $_cmd.
_bg_check_rm_segments() {
  _rm_segs=$(_bg_segments)
  _rm_loop_ifs=$IFS
  IFS='
'
  for _rm_seg in $_rm_segs; do
    IFS=$_rm_loop_ifs
    if ! _bg_rm_seg_check "$_rm_seg"; then
      return 1
    fi
    IFS='
'
  done
  IFS=$_rm_loop_ifs
  return 0
}

_bg_emit_block() {
  printf '%s: BLOQUEADO — categoria=%s — %s\n' "$_BG_NAME" "$1" "$2" >&2
}

# ---------- Whitelist ----------

# _bg_extract_urls CMD -> imprime cada URL/dominio encontrado, uma por linha
_bg_extract_urls() {
  _cmd=$1
  # Regex grosseiro mas pratico: captura http(s)?://host[:port][/path] OU
  # ssh-style git@host:path
  printf '%s' "$_cmd" | grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&'"'"'()*+,;=%-]+' 2>/dev/null || :
}

# _bg_url_matches_pattern URL PATTERN -> 0 se match
# Suporta globos simples no formato Decision 5: `https://host/**`,
# `https://*.host/path*`, etc. Conversao: `**` -> `.*`, `*` -> `[^/]*`.
_bg_url_matches_pattern() {
  _url=$1
  _pat=$2
  # Escape de pontos
  _re=$(printf '%s' "$_pat" \
    | sed -e 's/[][\\.+^$|(){}?]/\\&/g' \
          -e 's/\*\*/<DBLSTAR>/g' \
          -e 's/\*/[^\/]*/g' \
          -e 's/<DBLSTAR>/.*/g')
  printf '%s' "$_url" | grep -E "^${_re}$" >/dev/null 2>&1
}

# _bg_url_in_whitelist URL FILE -> 0 se OK (whitelist permite)
_bg_url_in_whitelist() {
  _url=$1
  _wl=$2
  [ -f "$_wl" ] || return 1
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      ''|\#*) continue ;;
    esac
    _line=$(printf '%s' "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$_line" ] && continue
    if _bg_url_matches_pattern "$_url" "$_line"; then
      return 0
    fi
  done < "$_wl"
  return 1
}

# _bg_is_gh_toolkit_issue CMD -> 0 se e gh issue create no repo do toolkit
# Excecao escopada (briefing FR-021). Apenas issue create, apenas no repo
# do toolkit.
_bg_is_gh_toolkit_issue() {
  _cmd=$1
  printf '%s' "$_cmd" \
    | grep -E "(^|[[:space:]])gh[[:space:]]+issue[[:space:]]+create[[:space:]].*--repo[[:space:]]+${_BG_TOOLKIT_REPO}([[:space:]]|$)" \
    >/dev/null 2>&1
}

# _bg_is_network_command CMD -> 0 se comando faz chamada externa
_bg_is_network_command() {
  _cmd=$1
  if printf '%s' "$_cmd" | grep -E '(^|[[:space:];|&])(curl|wget|gh[[:space:]]+(api|browse|repo[[:space:]]+(clone|view|create)|issue[[:space:]]+(create|edit|comment|close)|pr[[:space:]]+(create|edit|merge|close))|git[[:space:]]+(fetch|pull|clone))\b' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

_bg_check_whitelist_cmd() {
  _cmd=$1
  _wl=$2

  # Excecao escopada: gh issue create --repo JotJunior/cstk passa
  if _bg_is_gh_toolkit_issue "$_cmd"; then
    return 0
  fi

  # Nao e comando de rede -> nao aplica
  if ! _bg_is_network_command "$_cmd"; then
    return 0
  fi

  # Extrai URLs. Se nenhuma encontrada (ex: `gh repo clone owner/repo` sem
  # URL explicita), construa URL implicita para `gh ... owner/repo`.
  _urls=$(_bg_extract_urls "$_cmd")
  if [ -z "$_urls" ]; then
    # Tenta extrair --repo OWNER/NAME (gh issue/pr/repo create/etc)
    _flag_repo=$(printf '%s' "$_cmd" | grep -oE -- '--repo[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1)
    if [ -n "$_flag_repo" ]; then
      _slug=$(printf '%s' "$_flag_repo" | grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
      [ -n "$_slug" ] && _urls="https://github.com/$_slug"
    fi
  fi
  if [ -z "$_urls" ]; then
    # Tenta extrair owner/repo posicional (gh repo clone/view, gh api repos/...)
    _gh_repo=$(printf '%s' "$_cmd" | grep -oE 'gh[[:space:]]+(repo|api)[[:space:]]+(clone[[:space:]]+|view[[:space:]]+|repos/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1)
    if [ -n "$_gh_repo" ]; then
      _slug=$(printf '%s' "$_gh_repo" | grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
      [ -n "$_slug" ] && _urls="https://github.com/$_slug"
    fi
  fi
  if [ -z "$_urls" ]; then
    printf '%s: BLOQUEADO — comando de rede sem URL identificavel; rejeitado por seguranca\n' "$_BG_NAME" >&2
    printf '  comando: %s\n' "$_cmd" >&2
    return 1
  fi

  # Cada URL precisa estar na whitelist
  _OLD_IFS=$IFS
  IFS='
'
  for _u in $_urls; do
    IFS=$_OLD_IFS
    if ! _bg_url_in_whitelist "$_u" "$_wl"; then
      printf '%s: BLOQUEADO — URL fora da whitelist: %s\n' "$_BG_NAME" "$_u" >&2
      printf '  comando: %s\n' "$_cmd" >&2
      printf '  whitelist: %s\n' "$_wl" >&2
      return 1
    fi
    IFS='
'
  done
  IFS=$_OLD_IFS
  return 0
}

# ---------- Subcomandos ----------

_bg_cmd_check_blocklist() {
  _cmd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --command) _cmd=$2; shift 2 ;;
      *) _bg_die_usage "check-blocklist: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_cmd" ] || _bg_die_usage "check-blocklist: --command obrigatorio"
  if ! _bg_check_blocklist_cmd "$_cmd"; then
    exit 1
  fi
  exit 0
}

_bg_cmd_check_whitelist() {
  _cmd=""
  _wl=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --command)        _cmd=$2; shift 2 ;;
      --whitelist-file) _wl=$2; shift 2 ;;
      *) _bg_die_usage "check-whitelist: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_cmd" ] || _bg_die_usage "check-whitelist: --command obrigatorio"
  [ -n "$_wl" ]  || _bg_die_usage "check-whitelist: --whitelist-file obrigatorio"
  if ! _bg_check_whitelist_cmd "$_cmd" "$_wl"; then
    exit 1
  fi
  exit 0
}

_bg_cmd_check() {
  _cmd=""
  _wl=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --command)        _cmd=$2; shift 2 ;;
      --whitelist-file) _wl=$2; shift 2 ;;
      *) _bg_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_cmd" ] || _bg_die_usage "check: --command obrigatorio"
  [ -n "$_wl" ]  || _bg_die_usage "check: --whitelist-file obrigatorio"
  if ! _bg_check_blocklist_cmd "$_cmd"; then
    exit 1
  fi
  if ! _bg_check_whitelist_cmd "$_cmd" "$_wl"; then
    exit 1
  fi
  exit 0
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
bash-guard.sh — pre-validacao de comandos Bash (FR-018 + FR-028).

USO:
  bash-guard.sh check-blocklist --command "CMD"
  bash-guard.sh check-whitelist --command "CMD" --whitelist-file FILE
  bash-guard.sh check           --command "CMD" --whitelist-file FILE

Blocklist: sudo, npm/pip/cargo/go/brew install (sem docker exec/run no MESMO
segmento), git push, kubectl apply, terraform apply/destroy, docker push,
helm install/upgrade, aws cli mutativo, gcloud deploy, git reset --hard,
git clean -f, rm -rf fora de areas temporarias (~, $HOME, .., .git, absoluto
fora de /tmp e afins), sqlite3 mutativo na knowledge.db, pipe curl/wget->shell.

Nota atomic-commit: raw `git push` permanece bloqueado mesmo no modo atomic-commit.
O push confinado ocorre SOMENTE via `cstk session pr` (commit-mode.sh finalize),
que nao passa por este guard — caminho aprovado e isolado (FR-028 / Constitution §V).

Whitelist: comandos de rede (curl/wget/gh/git fetch/clone) checados contra
whitelist; excecao escopada: gh issue create --repo JotJunior/cstk.

EXIT:
  0 OK
  1 violacao (blocklist OR whitelist)
  2 uso incorreto
HELP
  exit 2
fi

_BG_SUBCMD=$1
shift

case "$_BG_SUBCMD" in
  check-blocklist) _bg_cmd_check_blocklist "$@" ;;
  check-whitelist) _bg_cmd_check_whitelist "$@" ;;
  check)           _bg_cmd_check "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _bg_die_usage "subcomando desconhecido: $_BG_SUBCMD" ;;
esac
