# 00c-bootstrap.sh — subcomando `cstk 00c <path>` (FASE 12).
#
# Bootstrap interativo de um projeto-alvo do agente-00C: cria diretorio,
# coleta parametros do `/agente-00c` via prompts e invoca `claude` ja com
# a slash command montada (auto-submetida como primeiro turno).
#
# Ref: docs/specs/cstk-cli/spec.md §US-5 + FR-016..FR-016h + SC-008/009
#      docs/specs/cstk-cli/plan.md §FASE 12 — Plano do subcomando
#      docs/specs/cstk-cli/research.md Decisions 11-14
#      docs/specs/cstk-cli/contracts/cstk-00c.md
#      docs/specs/cstk-cli/quickstart.md Scenarios 13-16
#
# IMPORTANTE: a logica de path-guard, sanitize e whitelist-validate aqui
# **espelha** os scripts canonicos em
# `global/skills/agente-00c-runtime/scripts/*.sh`. Por decisao arquitetural
# (Clarifications 2026-05-09 round 2 Q1), `cstk` reimplementa essa logica
# em `cli/lib/` por ser camada inferior ao runtime (instalador vs instalado);
# divergencias futuras passam por PR review explicito.
#
# Funcao publica:
#   bootstrap_00c_main "$@"   — dispatcher invoca via cli/cstk
#
# Helpers privados (prefixo _00c_): documentados inline.
#
# POSIX sh puro. Deps: mkdir, rmdir, cd, dirname, basename, printf, sed,
# grep, awk, command, read, trap, exec, claude (runtime), jq (runtime),
# realpath ou readlink (com fallback POSIX).

if [ -n "${_CSTK_00C_BOOTSTRAP_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_00C_BOOTSTRAP_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"

# ==== Constantes ====

_00C_LOCK_NAME=".cstk-00c.lock"
_00C_WHITELIST_NAME=".agente-00c-whitelist.txt"
_00C_DESC_MIN=10
_00C_DESC_MAX=500

# Exit codes (alinhado com contracts/cstk-00c.md).
_00C_EXIT_OK=0
_00C_EXIT_ERROR=1
_00C_EXIT_USAGE=2
_00C_EXIT_INTERRUPT=130

# State global (POSIX sh sem locals). Inicializado em bootstrap_00c_main.
_00c_arg_path=""
_00c_arg_yes=0
_00c_arg_llm="claude"    # default: catalogo core (SC-003 zero regressao)
_00c_resolved_path=""
_00c_lock_dir=""
_00c_descricao=""
_00c_stack=""
_00c_whitelist=""
_00c_whitelist_file=""
_00c_slash_command=""

# ==== Public entry point ====

bootstrap_00c_main() {
  _00c_reset_state
  _00c_parse_args "$@" || return $?

  _00c_check_tty || return $?
  _00c_validate_path || return $?
  _00c_acquire_lock || return $?
  # Apos lock acquire, qualquer exit (incluindo Ctrl+C) libera via trap.

  _00c_check_dir_empty || return $?
  _00c_check_deps || return $?

  # Gate de plugin LLM (FR-015): se --llm != "claude", validar antes de
  # qualquer operacao de estado (state-rw.sh init ainda nao ocorreu aqui;
  # o init acontece dentro do /agente-00c slash command no claude).
  _00c_check_llm_plugin || return $?

  _00c_read_descricao || return $?
  _00c_read_stack || return $?
  _00c_read_whitelist || return $?

  _00c_dry_run_preview
  # Confirm retorna 0 = confirm, !=0 = cancel. Cancel mapeia para exit 0
  # (operador cancelou nao e erro — alinhado com contracts/cstk-00c.md).
  if ! _00c_confirm_final; then
    return 0
  fi

  _00c_persist_whitelist || return $?
  _00c_exec_claude
  # Nao retorna em caminho feliz (exec substitui processo).
  # Se exec falhar, propaga via return.
  return $?
}

# ==== State management ====

_00c_reset_state() {
  _00c_arg_path=""
  _00c_arg_yes=0
  _00c_arg_llm="claude"
  _00c_resolved_path=""
  _00c_lock_dir=""
  _00c_descricao=""
  _00c_stack=""
  _00c_whitelist=""
  _00c_whitelist_file=""
  _00c_slash_command=""
}

# ==== _00c_parse_args ====

_00c_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --yes)
        _00c_arg_yes=1
        ;;
      --llm)
        if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
          log_error "00c: --llm requer um argumento <nome>"
          return "$_00C_EXIT_USAGE"
        fi
        shift
        _00c_arg_llm=$1
        ;;
      --help|-h)
        _00c_print_help
        exit "$_00C_EXIT_OK"
        ;;
      --)
        shift
        if [ "$#" -gt 0 ]; then
          _00c_arg_path=$1
        fi
        break
        ;;
      -*)
        log_error "00c: flag desconhecida: $1"
        log_error "Tente: cstk 00c --help"
        return "$_00C_EXIT_USAGE"
        ;;
      *)
        if [ -n "$_00c_arg_path" ]; then
          log_error "00c: muitos argumentos posicionais (apenas <path> e aceito)"
          return "$_00C_EXIT_USAGE"
        fi
        _00c_arg_path=$1
        ;;
    esac
    shift
  done

  if [ -z "$_00c_arg_path" ]; then
    log_error "00c: <path> e obrigatorio"
    log_error "Uso: cstk 00c <path> [--yes]"
    return "$_00C_EXIT_USAGE"
  fi

  return 0
}

# ==== _00c_print_help ====

_00c_print_help() {
  cat <<'HELP'
cstk 00c — Bootstrap interativo de projeto-alvo do agente-00C

USO:
  cstk 00c <path> [--yes] [--llm <nome>]

ARGUMENTOS:
  <path>    Path para o novo projeto-alvo (absoluto ou relativo ao CWD).
            Deve ser path NOVO ou diretorio vazio. Para retomar execucao
            existente, use `/agente-00c-resume --projeto-alvo-path <path>`
            diretamente no claude.

FLAGS:
  --yes       Pula apenas o prompt final de confirmacao e o prompt de
              auto-install. NAO pula validacoes de path/TTY/deps.
  --llm <n>   Plugin LLM a usar (default: "claude" — catalogo core; zero
              regressao). Se nao "claude", o plugin deve estar instalado
              (`cstk plugin-add <nome>`) e integro (checksum verificado
              antes de qualquer operacao de estado).
  --help      Imprime esta ajuda e sai.

PRE-REQUISITOS:
  - TTY interativo (fluxo NAO automatizavel via pipe; aborta com exit 2)
  - `claude` no PATH (Claude Code CLI)
  - `jq` no PATH (validacao de stack JSON; dep do agente-00c-runtime)
  - Artefatos do agente-00C instalados (auto-prompt para `cstk install`
    se ausentes): `~/.claude/commands/agente-00c.md`,
    `~/.claude/skills/agente-00c-runtime/scripts/state-rw.sh` (+x),
    `~/.claude/agents/agente-00c-orchestrator.md`.

FLUXO (5 passos):
  1. Validar <path> (rejeita zonas de sistema, traversal, dir nao-vazio)
  2. Criar dir + lock per-path (`<path>/.cstk-00c.lock/`)
  3. Prompts interativos: descricao, stack (JSON, opcional), whitelist
  4. Dry-run preview com confirmacao final
  5. exec claude com /agente-00c <args> auto-submetido

PROMPTS [Y/n] aceitam:
  Y/y/yes/sim/s/S/Enter         para SIM
  n/N/no/nao/Ctrl+D             para NAO

EXIT CODES:
  0    Sucesso (handed off via exec ao claude OU operador cancelou no prompt final)
  1    Erro de runtime (dep ausente, install falhou, lock conflito, dir nao-vazio)
  2    Uso incorreto (arg faltando, path invalido, TTY ausente)
  130  Ctrl+C durante prompts (POSIX 128 + SIGINT)

EXEMPLO:
  cstk 00c ./meu-poc
  # ... prompts interativos ...
  # claude inicia com /agente-00c "<descricao>" --projeto-alvo-path .

DOCUMENTACAO COMPLETA:
  docs/specs/cstk-cli/spec.md §US-5 + FR-016..FR-016h
  docs/specs/cstk-cli/contracts/cstk-00c.md
HELP
}

# ==== _00c_check_tty (FR-016a, research.md Decision 13) ====

_00c_check_tty() {
  # Bypass apenas para testes (CI dos proprios testes).
  if [ "${CSTK_00C_FORCE_TTY:-0}" = 1 ]; then
    return 0
  fi
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    log_error "00c: cstk 00c requer TTY interativo — fluxo nao automatizavel via pipe"
    log_error "Rode em terminal interativo. Stderr pode ser redirecionado."
    return "$_00C_EXIT_USAGE"
  fi
  return 0
}

# ==== _00c_realpath (research.md Decision 12) ====
#
# Espelha logica de `agente-00c-runtime/scripts/path-guard.sh::_pg_resolve`.
# Resolve path com symlinks (mesmo se path nao existe ainda) usando
# `realpath -m` (GNU) ou fallback POSIX via `cd -P`.
_00c_realpath() {
  _rp_in=$1
  [ -n "$_rp_in" ] || return 1

  # Tentar GNU realpath -m (aceita paths inexistentes).
  if command -v realpath >/dev/null 2>&1; then
    if realpath -m -- "$_rp_in" 2>/dev/null; then
      return 0
    fi
  fi

  # Fallback POSIX: resolve dirname via cd -P, concatena basename.
  _rp_parent=$(dirname -- "$_rp_in")
  _rp_base=$(basename -- "$_rp_in")
  if [ -d "$_rp_parent" ]; then
    _rp_abs_parent=$(cd -P -- "$_rp_parent" 2>/dev/null && pwd)
    if [ -n "$_rp_abs_parent" ]; then
      printf '%s/%s\n' "$_rp_abs_parent" "$_rp_base"
      return 0
    fi
  fi

  # Parent nao existe ainda: torna absoluto sem resolver symlinks.
  case "$_rp_in" in
    /*) printf '%s\n' "$_rp_in" ;;
    *)  printf '%s/%s\n' "$(pwd)" "$_rp_in" ;;
  esac
  return 0
}

# ==== _00c_validate_path (FR-016b) ====
#
# Espelha logica de `agente-00c-runtime/scripts/path-guard.sh::validate-target`.
# Rejeita: vazio, traversal `..`, zonas de sistema (lista canonica fechada).
_00c_validate_path() {
  _vp_raw=$_00c_arg_path

  if [ -z "$_vp_raw" ]; then
    log_error "00c: <path> vazio"
    return "$_00C_EXIT_USAGE"
  fi

  # Rejeita componentes `..` (path traversal).
  case "/$_vp_raw/" in
    */../*|*/..)
      log_error "00c: <path> contem '..' (path traversal nao permitido): $_vp_raw"
      return "$_00C_EXIT_USAGE"
      ;;
  esac

  # Resolve simbolos via realpath portavel.
  _vp_resolved=$(_00c_realpath "$_vp_raw") || {
    log_error "00c: nao foi possivel resolver path: $_vp_raw"
    return "$_00C_EXIT_USAGE"
  }

  # Lista canonica de zonas proibidas. Espelha path-guard.sh:_pg_forbidden_zones.
  # Inclui formas canonica (/etc) e resolvida no macOS (/private/etc).
  _vp_forbidden=$(cat <<EOF
/
/etc
/usr
/bin
/sbin
/boot
/proc
/sys
/var/log
/var/db
/var/run
/var/lib
/private/etc
/private/usr
/private/bin
/private/sbin
/private/var/log
/private/var/db
/private/var/run
/private/var/lib
/System
/Library
${HOME:?HOME nao setado}
${HOME}/.ssh
${HOME}/.gnupg
${HOME}/.aws
${HOME}/.config/claude
EOF
)

  # Verifica match exato OU prefixo seguido de `/`.
  # IMPORTANTE: $HOME (exato) e tratado como exact-only — alinhado com o
  # intent do `~` no spec (rejeitar `cstk 00c ~` mas permitir `~/projetos/poc`).
  # Outras zonas (/etc, ~/.ssh) usam exact-or-prefix (rejeita paths dentro).
  _vp_home_resolved=$(_00c_realpath "$HOME") || _vp_home_resolved="$HOME"
  _vp_old_ifs=$IFS
  IFS='
'
  for _vp_zone in $_vp_forbidden; do
    [ -n "$_vp_zone" ] || continue

    # Resolve a zona tambem (defesa T2 — zonas que tambem tem symlink).
    if [ -e "$_vp_zone" ]; then
      _vp_zone_resolved=$(_00c_realpath "$_vp_zone") || _vp_zone_resolved="$_vp_zone"
    else
      _vp_zone_resolved=$_vp_zone
    fi

    # Match exato.
    if [ "$_vp_resolved" = "$_vp_zone" ] || [ "$_vp_resolved" = "$_vp_zone_resolved" ]; then
      IFS=$_vp_old_ifs
      log_error "00c: <path> aponta para zona de sistema proibida: $_vp_resolved"
      log_error "Escolha um diretorio em \$HOME (ex: ~/projetos/poc, ./meu-poc)"
      return "$_00C_EXIT_USAGE"
    fi

    # Match prefixo (path/* esta dentro da zona) — exceto para $HOME (exato).
    if [ "$_vp_zone" = "$HOME" ] || [ "$_vp_zone_resolved" = "$_vp_home_resolved" ]; then
      continue
    fi
    case "$_vp_resolved" in
      "$_vp_zone"/*|"$_vp_zone_resolved"/*)
        IFS=$_vp_old_ifs
        log_error "00c: <path> esta dentro de zona de sistema proibida ($_vp_zone): $_vp_resolved"
        log_error "Escolha um diretorio em \$HOME (ex: ~/projetos/poc, ./meu-poc)"
        return "$_00C_EXIT_USAGE"
        ;;
    esac
  done
  IFS=$_vp_old_ifs

  _00c_resolved_path=$_vp_resolved
  return 0
}

# ==== _00c_acquire_lock (FR-016h, research.md Decision 14) ====

_00c_acquire_lock() {
  _00c_lock_dir="$_00c_resolved_path/$_00C_LOCK_NAME"

  # Garante que o diretorio pai (do lock) existe — mas apenas se path
  # resolvido NAO existe ainda. Se ja existe (e e dir), mkdir e idempotente.
  if [ ! -d "$_00c_resolved_path" ]; then
    if ! mkdir -p -- "$_00c_resolved_path" 2>/dev/null; then
      log_error "00c: falha ao criar diretorio: $_00c_resolved_path"
      return "$_00C_EXIT_ERROR"
    fi
    chmod 700 -- "$_00c_resolved_path" 2>/dev/null || :
  fi

  # mkdir atomico (POSIX). Se ja existe, falha = lock detido por outro.
  if ! mkdir -- "$_00c_lock_dir" 2>/dev/null; then
    log_error "00c: outra instancia de cstk 00c em andamento em $_00c_resolved_path"
    log_error "Se for stale lock, remova manualmente: rmdir $_00c_lock_dir"
    _00c_lock_dir=""  # nao tente liberar lock que nao adquirimos
    return "$_00C_EXIT_ERROR"
  fi

  # Trap split (issue #2):
  # - EXIT: cleanup (release_lock) em qualquer caminho de saida.
  # - INT/TERM: chama `exit 130/143` explicitamente. Sem o `exit`, o trap
  #   apenas roda mas o sinal e consumido — `read -r` no loop de prompts
  #   retorna empty e o while de validacao prossegue, deixando o usuario
  #   "preso" no prompt apos Ctrl+C. `exit` dispara o trap EXIT na sequencia.
  trap '_00c_release_lock' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  return 0
}

# ==== _00c_release_lock (FR-016h) ====

_00c_release_lock() {
  if [ -n "$_00c_lock_dir" ] && [ -d "$_00c_lock_dir" ]; then
    rmdir -- "$_00c_lock_dir" 2>/dev/null || :
  fi
  _00c_lock_dir=""
}

# ==== _00c_check_dir_empty (FR-016b) ====

_00c_check_dir_empty() {
  # Lista o conteudo do <path> excluindo o lock que acabamos de criar.
  # Se houver QUALQUER outro arquivo, abortar (sem prompt).
  _cde_count=$(find "$_00c_resolved_path" -mindepth 1 -maxdepth 1 \
                  ! -name "$_00C_LOCK_NAME" 2>/dev/null | wc -l | tr -d ' ')

  if [ "${_cde_count:-0}" -gt 0 ]; then
    log_error "00c: $_00c_resolved_path ja existe e nao esta vazio."
    log_error "cstk 00c so opera em paths novos ou vazios."
    log_error "Para retomar execucao existente do agente-00C, use:"
    log_error "  /agente-00c-resume --projeto-alvo-path $_00c_resolved_path"
    log_error "(diretamente no claude)"
    return "$_00C_EXIT_ERROR"
  fi
  return 0
}

# ==== _00c_check_deps (FR-016d) ====

_00c_check_deps() {
  # (a) claude no PATH
  if ! command -v claude >/dev/null 2>&1; then
    log_error "00c: Claude Code CLI nao encontrado no PATH"
    log_error "Instale via: npm install -g @anthropic-ai/claude-code"
    log_error "Documentacao: https://docs.claude.com/claude-code/setup"
    return "$_00C_EXIT_ERROR"
  fi

  # (b) jq no PATH e funcional. Usa `jq --version` (funcional check) ao
  # inves de apenas `command -v jq` para detectar jq quebrado/stub em testes
  # e tambem capturar instalacoes corrompidas em producao.
  if ! jq --version >/dev/null 2>&1; then
    log_error "00c: jq nao encontrado no PATH"
    case "$(uname -s 2>/dev/null)" in
      Darwin) log_error "Instale via: brew install jq" ;;
      Linux)  log_error "Instale via: apt install jq (ou yum/dnf install jq)" ;;
      *)      log_error "Instale jq pelo gerenciador de pacotes do seu OS" ;;
    esac
    log_error "jq e dependencia do agente-00c-runtime (operacoes em state.json)"
    return "$_00C_EXIT_ERROR"
  fi

  # (c) Artefatos do agente-00C instalados: command + runtime + 3 agents.
  # Sanity de instalacao precisa cobrir as tres camadas — checar apenas o
  # command deixa passar instalacoes parciais (ex.: profile sdd antigo que
  # nao incluia runtime) que so falham em runtime quando o orquestrador
  # chama state-rw.sh, ja dentro de uma onda.
  _cd_home="${HOME:?HOME nao setado}"
  _cd_cmd_path="$_cd_home/.claude/commands/agente-00c.md"
  _cd_runtime_probe="$_cd_home/.claude/skills/agente-00c-runtime/scripts/state-rw.sh"
  _cd_orchestrator_path="$_cd_home/.claude/agents/agente-00c-orchestrator.md"
  _cd_missing=""
  [ -f "$_cd_cmd_path" ] || _cd_missing="$_cd_missing command"
  # Runtime: arquivo precisa existir E ser executavel — script sem +x
  # silenciosamente falha quando invocado via Bash.
  [ -x "$_cd_runtime_probe" ] || _cd_missing="$_cd_missing runtime"
  [ -f "$_cd_orchestrator_path" ] || _cd_missing="$_cd_missing orchestrator"

  if [ -n "$_cd_missing" ]; then
    log_info "00c: instalacao incompleta detectada (faltando:$_cd_missing)"
    _00c_prompt_install || return $?
  fi

  return 0
}

# ==== _00c_prompt_install (FR-016d c) ====

_00c_prompt_install() {
  if [ "$_00c_arg_yes" = 1 ]; then
    _pi_answer="Y"
  else
    printf 'Artefatos do agente-00c ausentes ou incompletos. Instalar agora via "cstk install"? [Y/n] ' >&2
    if ! IFS= read -r _pi_answer; then
      # EOF / Ctrl+D = N
      _pi_answer="n"
    fi
  fi

  case "$_pi_answer" in
    ''|Y|y|yes|YES|sim|SIM|s|S)
      log_info "Executando 'cstk install' em foreground..."
      ;;
    *)
      log_error "00c: cstk 00c requer comando agente-00c instalado."
      log_error "Rode 'cstk install' manualmente e tente novamente."
      return "$_00C_EXIT_ERROR"
      ;;
  esac

  # Resolver caminho do bin cstk. Usar variavel CSTK_BIN para testes.
  _pi_cstk_bin="${CSTK_BIN:-cstk}"

  # Capturar saida para classificar erro (lock conflito vs outro motivo).
  _pi_out_file=$(mktemp -t cstk-00c-install.XXXXXX) || {
    log_error "00c: mktemp falhou"
    return "$_00C_EXIT_ERROR"
  }
  set +e
  "$_pi_cstk_bin" install >"$_pi_out_file" 2>&1
  _pi_rc=$?
  set -e

  # Imprime saida do install em foreground (operador ve progresso).
  cat "$_pi_out_file" >&2 || :

  if [ "$_pi_rc" -eq 0 ]; then
    rm -f "$_pi_out_file"
    return 0
  fi

  # Detecta conflito de lock (FR-015) por padrao na saida (alinhado com
  # cli/lib/lock.sh::acquire_lock que emite mensagem com a palavra "lock").
  if grep -qiE 'lock|outra instancia|already running' "$_pi_out_file" 2>/dev/null; then
    rm -f "$_pi_out_file"
    log_error "00c: outro cstk install em andamento."
    log_error "Aguarde, depois rode 'cstk 00c $_00c_arg_path' novamente."
    return "$_00C_EXIT_ERROR"
  fi

  # Falha generica (rede, sha mismatch, disco). Propagar exit code + razao.
  _pi_reason=$(tail -n 5 "$_pi_out_file" 2>/dev/null | tr -d '\n' | head -c 300)
  rm -f "$_pi_out_file"
  log_error "00c: cstk install falhou (exit code $_pi_rc): $_pi_reason"
  log_error "Diretorio criado em $_00c_resolved_path PERMANECE (sem rollback)."
  log_error "Para retry manual, rode: cstk install --force"
  return "$_00C_EXIT_ERROR"
}

# ==== _00c_read_descricao (FR-016c a) ====
#
# Espelha sanitize.sh::limit-length + check-length, com validacao de
# caracteres permitidos (printable unicode, sem `\n`/`$`/`` ` ``).
_00c_read_descricao() {
  while :; do
    printf 'Descricao curta do POC/MVP (10-500 chars): ' >&2
    if ! IFS= read -r _rd_input; then
      # Ctrl+D = abort
      log_error "00c: input encerrado prematuramente"
      return "$_00C_EXIT_INTERRUPT"
    fi

    # Comprimento.
    _rd_len=${#_rd_input}
    if [ "$_rd_len" -lt "$_00C_DESC_MIN" ]; then
      log_warn "Descricao muito curta ($_rd_len chars). Minimo: $_00C_DESC_MIN."
      continue
    fi
    if [ "$_rd_len" -gt "$_00C_DESC_MAX" ]; then
      log_warn "Descricao muito longa ($_rd_len chars). Maximo: $_00C_DESC_MAX."
      continue
    fi

    # Caracteres proibidos: $, ` (backtick) e quaisquer controles invisiveis.
    case "$_rd_input" in
      *\$*) log_warn "Descricao contem '\$' (proibido para evitar expansao shell)."; continue ;;
      *\`*) log_warn "Descricao contem backtick (proibido para evitar expansao shell)."; continue ;;
    esac

    # Rejeita controles invisiveis (bytes < 0x20 exceto LF que e do read).
    # tr -d '[:print:][:space:]' deixa apenas caracteres NAO-printable+NAO-space.
    # read ja remove o LF final, entao o input nao deve ter \n. Mas pode ter \t.
    _rd_filtered=$(printf '%s' "$_rd_input" | tr -d '[:print:][:space:]' 2>/dev/null || true)
    if [ -n "$_rd_filtered" ]; then
      log_warn "Descricao contem caracteres de controle invisiveis (rejeitado)."
      continue
    fi
    case "$_rd_input" in
      *"	"*) log_warn "Descricao contem tab (rejeitado)."; continue ;;
    esac

    _00c_descricao=$_rd_input
    return 0
  done
}

# ==== _00c_read_stack (FR-016c b) ====

_00c_read_stack() {
  while :; do
    printf 'Stack-sugerida em JSON (Enter para pular): ' >&2
    if ! IFS= read -r _rs_input; then
      log_error "00c: input encerrado prematuramente"
      return "$_00C_EXIT_INTERRUPT"
    fi

    if [ -z "$_rs_input" ]; then
      _00c_stack=""
      return 0
    fi

    # Valida via jq -e .  (jq presente — ja verificado em check_deps).
    if printf '%s' "$_rs_input" | jq -e . >/dev/null 2>&1; then
      # Compactar em uma linha via jq -c (FR-016g).
      _00c_stack=$(printf '%s' "$_rs_input" | jq -c .)
      return 0
    fi

    log_warn "JSON invalido. Exemplo: {\"runtime\":\"node20\",\"ui\":\"react\"}"
  done
}

# ==== _00c_validate_url ====
#
# Espelha global/skills/agente-00c-runtime/scripts/whitelist-validate.sh:50-100.
# Retorno 0 = URL valida; 1 = invalida (mensagem em stderr).
_00c_validate_url() {
  _vu_url=$1

  # Trim whitespace.
  _vu_url=$(printf '%s' "$_vu_url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # 1. Vazio.
  if [ -z "$_vu_url" ]; then
    return 1
  fi

  # 2. Rejeita ** puro.
  if [ "$_vu_url" = "**" ]; then
    log_warn "URL invalida: '**' puro sem dominio (cobre tudo)"
    return 1
  fi

  # 3. Rejeita *://* (scheme glob).
  case "$_vu_url" in
    '*://'*)
      log_warn "URL invalida: scheme com glob ('*://*') — exija http(s) explicito"
      return 1
      ;;
  esac

  # 4. Exige scheme http(s).
  case "$_vu_url" in
    http://*|https://*) ;;
    *)
      log_warn "URL invalida: sem scheme http(s):// explicito"
      return 1
      ;;
  esac

  # 5. Extrai host (entre :// e proximo /).
  _vu_rest=${_vu_url#*://}
  _vu_host=${_vu_rest%%/*}
  if [ -z "$_vu_host" ]; then
    log_warn "URL invalida: host vazio"
    return 1
  fi

  # 6. Rejeita host puro * ou [*].
  case "$_vu_host" in
    '*'|'[*]'|'[*]:'*)
      log_warn "URL invalida: host '*' ou '[*]' cobre qualquer dominio"
      return 1
      ;;
  esac

  # 7. Wildcard no host so como prefixo *.dominio.tld.
  case "$_vu_host" in
    *'*'*)
      case "$_vu_host" in
        '*.'?*'.'?*) ;;  # OK: *.foo.com, *.foo.bar.com
        *)
          log_warn "URL invalida: wildcard no host fora do padrao '*.dominio.tld'"
          return 1
          ;;
      esac
      ;;
  esac

  return 0
}

# ==== _00c_read_whitelist (FR-016c c) ====

_00c_read_whitelist() {
  printf 'Whitelist de URLs externas (uma por linha, linha vazia para terminar; Enter agora para pular): ' >&2
  _00c_whitelist=""

  while :; do
    if ! IFS= read -r _rw_line; then
      # Ctrl+D = encerra captura (mantem o que ja foi capturado).
      break
    fi

    # Linha vazia encerra captura.
    if [ -z "$_rw_line" ]; then
      break
    fi

    if _00c_validate_url "$_rw_line"; then
      if [ -z "$_00c_whitelist" ]; then
        _00c_whitelist=$_rw_line
      else
        _00c_whitelist="$_00c_whitelist
$_rw_line"
      fi
      printf '  + %s\n  Proxima URL (linha vazia para terminar): ' "$_rw_line" >&2
    else
      printf '  Tente de novo (linha vazia para terminar): ' >&2
    fi
  done
  return 0
}

# ==== _00c_check_llm_plugin (FR-015 — gate pre-state-init) ====
#
# Se --llm == "claude" (default): no-op — zero mudanca no comportamento atual (SC-003).
# Se --llm != "claude": validar que o plugin esta instalado E com checksum OK
# antes de criar qualquer estado. Falha antes de `state-rw.sh init`.
#
# Requer que plugin-common.sh ja tenha sido sourced quando chamado com llm != claude.
# Como bootstrap e invocado via dispatcher (cli/cstk), e dispatcher faz source de
# plugin-common.sh apenas para plugin-add|list|remove; para 00c precisamos fazer
# source direto aqui se necessario.
_00c_check_llm_plugin() {
  # SC-003: default claude — zero regressao.
  if [ "$_00c_arg_llm" = "claude" ]; then
    return 0
  fi

  # Validar nome do LLM plugin (mesma regra FR-002).
  _clp_name=$_00c_arg_llm

  # Source plugin-common.sh se ainda nao carregado.
  if [ -z "${_CSTK_PLUGIN_COMMON_LOADED:-}" ]; then
    _clp_common="${CSTK_LIB}/plugin-common.sh"
    if [ ! -f "$_clp_common" ]; then
      log_error "00c: --llm requer plugin-common.sh em $CSTK_LIB (ausente)"
      return "$_00C_EXIT_ERROR"
    fi
    # shellcheck source=/dev/null
    . "$_clp_common"
  fi

  # Validar nome via plugin_validate_name (FR-002).
  if ! plugin_validate_name "$_clp_name" 2>/dev/null; then
    log_error "00c: --llm '$_clp_name' nao e um nome de plugin valido (^[a-z][a-z0-9-]{0,63}\$)"
    return "$_00C_EXIT_USAGE"
  fi

  # Verificar instalacao (registry + diretorio).
  if ! plugin_is_installed "$_clp_name" 2>/dev/null; then
    log_error "00c: plugin LLM '$_clp_name' nao esta instalado."
    log_error "Instale primeiro: cstk plugin-add $_clp_name"
    return "$_00C_EXIT_ERROR"
  fi

  # Re-verificar checksum (FR-005 — integridade na ativacao).
  _clp_store=$(plugin_store_dir "$_clp_name")
  _clp_manifest="$_clp_store/plugin-manifest.json"
  if [ ! -f "$_clp_manifest" ]; then
    log_error "00c: plugin '$_clp_name' sem plugin-manifest.json em $_clp_store"
    return "$_00C_EXIT_ERROR"
  fi
  _clp_expected=$(grep '"bundle_sha256"' "$_clp_manifest" 2>/dev/null \
                   | sed 's/.*"bundle_sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ -z "$_clp_expected" ]; then
    log_error "00c: plugin '$_clp_name' manifest sem campo bundle_sha256"
    return "$_00C_EXIT_ERROR"
  fi
  if ! plugin_verify_bundle_checksum "$_clp_store" "$_clp_expected" 2>/dev/null; then
    log_error "00c: plugin '$_clp_name' falhou na verificacao de checksum (tampered?)"
    log_error "Reinstale: cstk plugin-add --force $_clp_name"
    return "$_00C_EXIT_ERROR"
  fi

  log_info "00c: plugin LLM '$_clp_name' verificado OK; path-prepending ativo."
  return 0
}

# ==== _00c_escape_sq (FR-016g) ====
#
# Escape canonico shell single-quote: cada `'` -> `'\''`.
# Espelha agente-00c-runtime/scripts/sanitize.sh::escape-commit-msg.
_00c_escape_sq() {
  _es_in=$1
  printf '%s' "$_es_in" | sed "s/'/'\\\\''/g"
}

# ==== _00c_persist_whitelist (FR-016f) ====
#
# Escrita atomica via mktemp + mv, chmod 600.
_00c_persist_whitelist() {
  _00c_whitelist_file="$_00c_resolved_path/$_00C_WHITELIST_NAME"

  if [ -z "$_00c_whitelist" ]; then
    # Sem whitelist: nao criar arquivo (sera passado sem --whitelist).
    _00c_whitelist_file=""
    return 0
  fi

  _pw_tmp=$(mktemp -t cstk-00c-whitelist.XXXXXX) || {
    log_error "00c: mktemp falhou"
    return "$_00C_EXIT_ERROR"
  }
  printf '%s\n' "$_00c_whitelist" > "$_pw_tmp"
  chmod 600 -- "$_pw_tmp" 2>/dev/null || :

  if ! mv -- "$_pw_tmp" "$_00c_whitelist_file"; then
    log_error "00c: falha ao persistir whitelist em $_00c_whitelist_file"
    rm -f -- "$_pw_tmp"
    return "$_00C_EXIT_ERROR"
  fi

  return 0
}

# ==== _00c_dry_run_preview (FR-016e) ====

_00c_dry_run_preview() {
  # Monta a slash command que sera invocada (string para preview e exec).
  _00c_build_slash_command

  {
    printf '\n'
    printf '=== cstk 00c — Resumo da invocacao ===\n'
    printf 'Path:        %s\n' "$_00c_resolved_path"
    printf 'Descricao:   %s\n' "$_00c_descricao"
    printf 'LLM Plugin:  %s\n' "${_00c_arg_llm:-claude}"
    if [ -n "$_00c_stack" ]; then
      printf 'Stack:       %s\n' "$_00c_stack"
    else
      printf 'Stack:       —\n'
    fi
    if [ -n "$_00c_whitelist" ]; then
      _drp_count=$(printf '%s\n' "$_00c_whitelist" | grep -c .)
      printf 'Whitelist:   %d URL(s) -> %s\n' "$_drp_count" "$_00c_whitelist_file"
    else
      printf 'Whitelist:   — (sem URLs externas)\n'
    fi
    printf '\nComando que sera invocado:\n'
    printf '  claude "%s"\n' "$_00c_slash_command"
    printf '\n'
  } >&2
}

# ==== _00c_build_slash_command ====
#
# Monta a string que sera passada como UM unico argumento para claude:
# /agente-00c '<desc>' [--stack '<json>'] [--whitelist <abs>] --projeto-alvo-path '<abs>'
#
# Aspas simples ao redor de <desc>, <json>, <abs> protegem espacos e chars
# especiais; conteudo interno ja e escapado via _00c_escape_sq (`'` -> `'\''`).
# Stack JSON (ex: `{"runtime":"go"}`) tem aspas DUPLAS internas, mas como o
# wrapping e single-quote, isso passa intacto para o argv recebido por claude.
# A invocacao usa `exec claude "$_00c_slash_command"` (sem eval) — o claude
# recebe a string inteira como argv[1].
_00c_build_slash_command() {
  _bsc_desc_esc=$(_00c_escape_sq "$_00c_descricao")
  _bsc_cmd="/agente-00c '$_bsc_desc_esc'"

  if [ -n "$_00c_stack" ]; then
    _bsc_stack_esc=$(_00c_escape_sq "$_00c_stack")
    _bsc_cmd="$_bsc_cmd --stack '$_bsc_stack_esc'"
  fi

  if [ -n "$_00c_whitelist_file" ]; then
    _bsc_cmd="$_bsc_cmd --whitelist $_00c_whitelist_file"
  fi

  # Encaminhar --llm apenas quando nao for o default "claude" (SC-003).
  if [ "${_00c_arg_llm:-claude}" != "claude" ]; then
    _bsc_cmd="$_bsc_cmd --llm '$_00c_arg_llm'"
  fi

  _bsc_path_esc=$(_00c_escape_sq "$_00c_resolved_path")
  _bsc_cmd="$_bsc_cmd --projeto-alvo-path '$_bsc_path_esc'"

  _00c_slash_command=$_bsc_cmd
}

# ==== _00c_confirm_final (FR-016e) ====

_00c_confirm_final() {
  if [ "$_00c_arg_yes" = 1 ]; then
    return 0
  fi

  printf 'Confirmar invocacao do claude com a slash command acima? [Y/n] ' >&2
  if ! IFS= read -r _cf_answer; then
    log_info "Cancelado (Ctrl+D)."
    return 1  # cancel
  fi

  case "$_cf_answer" in
    ''|Y|y|yes|YES|sim|SIM|s|S)
      return 0  # confirm
      ;;
    *)
      log_info "Cancelado pelo operador."
      return 1  # cancel
      ;;
  esac
}

# ==== _00c_exec_claude (FR-016f) ====
#
# (1) cd para o path; (2) release lock explicito (Decision 14); (3) exec claude.
_00c_exec_claude() {
  if ! cd -- "$_00c_resolved_path" 2>/dev/null; then
    log_error "00c: falha em cd para $_00c_resolved_path"
    return "$_00C_EXIT_ERROR"
  fi

  # Re-monta o slash command com whitelist em path absoluto (apos cd, o
  # path original do whitelist ja era absoluto via _00c_resolved_path,
  # entao continua valido).
  _00c_build_slash_command

  # Remove o trap (release explicito) — claude nao deve receber trap herdado.
  _00c_release_lock
  trap - EXIT INT TERM

  # exec substitui o processo cstk pelo claude. Passa o slash command como
  # argv[1] do claude (UMA string contendo `/agente-00c '...' --stack '...'
  # --projeto-alvo-path '...'`). O claude e responsavel por interpretar
  # essa string como slash command auto-submetida (research.md Decision 11).
  # Sem `eval`: as aspas dentro da string sao literais.
  exec claude "$_00c_slash_command"

  # Se exec falhou (claude nao executou), propagar.
  log_error "00c: exec claude falhou (claude nao iniciou)"
  return "$_00C_EXIT_ERROR"
}
