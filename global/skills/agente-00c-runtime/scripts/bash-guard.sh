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
#      push, helm install, etc).
#   2. whitelist enforcement — comandos de rede (curl, wget, gh api/repo,
#      git fetch/clone) tem URL/dominio extraido e checado contra
#      whitelist_urls_externas. Excecao escopada: `gh issue create
#      --repo JotJunior/cstk ...` bypass (ver briefing).
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

  # 2. Package managers no host — bloqueia a menos que prefixado por docker exec/run
  # (`docker exec foo npm install` deve passar)
  if _bg_match '(^|[[:space:];|&])(npm|pnpm|yarn|pip|pip3|gem|brew)[[:space:]]+(install|i|add|update|upgrade)\b'; then
    if ! printf '%s' "$_cmd" | grep -E '\bdocker[[:space:]]+(exec|run)\b' >/dev/null 2>&1; then
      _bg_emit_block "package-manager" "package install no host bloqueado (use 'docker exec/run' como wrapper)"
      return 1
    fi
  fi
  # `go install` / `cargo install`
  if _bg_match '(^|[[:space:];|&])(go|cargo)[[:space:]]+install\b'; then
    if ! printf '%s' "$_cmd" | grep -E '\bdocker[[:space:]]+(exec|run)\b' >/dev/null 2>&1; then
      _bg_emit_block "package-manager" "go/cargo install no host bloqueado"
      return 1
    fi
  fi

  # 3. git push (FR-028 — Constitution §V)
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

Blocklist: sudo, npm/pip/cargo/go/brew install (sem docker prefix), git push,
kubectl apply, terraform apply/destroy, docker push, helm install/upgrade,
aws cli mutativo, gcloud deploy.

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
