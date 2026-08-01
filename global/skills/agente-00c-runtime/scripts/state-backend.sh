#!/bin/sh
# state-backend.sh — fonte unica de leitura/escrita da configuracao global de
# backend de estado (feature state-backend-config, cutover Fase 2).
#
# Ref: docs/specs/state-backend-config/research.md Decision 1, 2, 4, 5, 7, 8
#      docs/specs/state-backend-config/contracts/state-backend-runtime.md
#      docs/specs/state-backend-config/data-model.md §BackendConfig
#      docs/specs/state-backend-config/tasks.md FASE 1-3
#
# E a fonte UNICA de leitura da config `$HOME/.claude/cstk/config` (Decision
# 2). O binario `cstk` (cli/lib/config.sh) DELEGA a este script; NAO
# reimplementa parsing nem logica de decisao de backend — e essa unicidade
# que torna SC-004 (0% de divergencia binario<->runtime) verdadeiro por
# construcao.
#
# Subcomandos:
#   state-backend.sh capability
#       — Imprime o token de capability versionado deste runtime em stdout,
#         exit 0. Read-only. Alvo da checagem ativa de FR-004A.
#
#   state-backend.sh resolve
#       — Le a config + versao de sqlite3 detectada; imprime
#         `effective_backend=sqlite|json` e `reason=<...>` em stdout.
#         SEMPRE exit 0 (contrato de nao-falha, FR-008) — inclusive quando o
#         resultado e o fallback json. Read-only.
#
#   state-backend.sh enable-sqlite
#       — UNICO subcomando que escreve. Verifica, nesta ordem, TODAS antes
#         de qualquer escrita: (1) sqlite3 no PATH, (2) versao >= minima,
#         (3) capability do runtime do catalogo instalado (P8: prioriza
#         catalogo instalado; fallback ao layout de repo so quando o
#         catalogo NAO existe). Falha em qualquer uma ⇒ config
#         byte-a-byte inalterada, exit 3, diagnostico em stderr citando o
#         que foi observado e o que era exigido. Sucesso ⇒ grava
#         `state_backend=sqlite`; idempotente (ja declarado ⇒ no-op, exit 0,
#         sem duplicar linha).
#
# Contrato de parsing (vinculante, contracts/state-backend-runtime.md):
#   P1 NAO usa `.`/`source`/`eval` sobre o arquivo de config.
#   P2 Parse linha a linha, split no PRIMEIRO `=`; `#`/branco ignorados;
#      linha sem `=` marca a config INTEIRA como invalida.
#   P3 Valor validado contra allowlist sqlite|json ANTES de qualquer uso;
#      fora do dominio ⇒ config-invalida ⇒ fallback json.
#   P4 Chave desconhecida e ignorada, nao e erro.
#   P5 Toda expansao de variavel e citada ("$var"), sem excecao.
#   P6 Diretorio criado 700; arquivo de config 600.
#   P7 Escrita via mktemp no MESMO diretorio + mv (write-temp-then-rename).
#   P8 Checagem de capability prioriza o catalogo instalado; MUST reportar
#      qual caminho foi validado (dec-034/CHK010): a linha
#      "state-backend: capability verificado via <origem> (<path>)" e
#      emitida no sucesso e na recusa por runtime incapaz.
#
# Exit codes (mesma familia de `cstk state`, cli/lib/state.sh):
#   0 sucesso (inclusive no-op idempotente / fallback json de resolve)
#   1 falha inesperada (ex.: falha de escrita)
#   2 uso incorreto (subcomando desconhecido)
#   3 recusado por pre-condicao (enable-sqlite: dependencia/capability)
#
# POSIX sh puro. Sem bash-isms. Sem `.`/`source`/`eval` sobre dado externo.

set -eu

_SB_NAME="state-backend"

# research.md Decision 4: piso herdado de state-db-foundation/research.md
# Fase 1 (NAO da constitution — ver correcao de citacao em spec.md FR-003).
_SB_MIN_SQLITE_VERSION="3.45.1"

# research.md Decision 5: token de capability versionado. Bump SEMPRE que
# este script ganhar um subcomando/comportamento que `enable-sqlite`
# (rodando de outro runtime) precise exigir do catalogo instalado.
_SB_CAPABILITY_TOKEN="1"

_SB_HOME="${HOME:-/tmp}"
_SB_CONFIG_DIR="$_SB_HOME/.claude/cstk"
_SB_CONFIG_FILE="$_SB_CONFIG_DIR/config"
_SB_INSTALLED_SCRIPT="$_SB_HOME/.claude/skills/agente-00c-runtime/scripts/state-backend.sh"

_sb_die_usage() { printf '%s: %s\n' "$_SB_NAME" "$1" >&2; exit 2; }
_sb_die()       { printf '%s: %s\n' "$_SB_NAME" "$1" >&2; exit "${2:-1}"; }

_sb_usage() {
  cat <<'HELP'
state-backend.sh — fonte unica da configuracao global de backend de estado

USO:
  state-backend.sh capability       Imprime o token de capability (stdout), exit 0
  state-backend.sh resolve          Resolve o backend efetivo + motivo (stdout), exit 0
  state-backend.sh enable-sqlite    Ativa state_backend=sqlite (unico subcomando que escreve)

Config: $HOME/.claude/cstk/config (key=value, chave 'state_backend' em sqlite|json)

EXIT CODES:
  0 sucesso   1 falha   2 uso incorreto   3 recusado por pre-condicao
HELP
}

# --- Comparacao de versao (research.md Decision 4) -------------------------

# _sb_numeric_field VALUE -> imprime VALUE se for so digitos, senao "0".
# Defesa contra sufixos nao-numericos residuais (ex.: patch com hash).
_sb_numeric_field() {
  case "$1" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$1" ;;
  esac
}

# _sb_version_ge V1 V2 -> exit 0 se V1 >= V2. Comparacao numerica
# campo-a-campo (major.minor.patch) via IFS='.' + expansao de parametro.
# Sem sort -V (nao-POSIX/GNU-only), sem awk (research.md Decision 4).
_sb_version_ge() {
  _sbv_v1="$1"
  _sbv_v2="$2"
  _sbv_oldifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086 # split deliberado, IFS='.' acima
  set -- $_sbv_v1
  IFS="$_sbv_oldifs"
  _sbv_1a=$(_sb_numeric_field "${1:-0}")
  _sbv_1b=$(_sb_numeric_field "${2:-0}")
  _sbv_1c=$(_sb_numeric_field "${3:-0}")

  _sbv_oldifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $_sbv_v2
  IFS="$_sbv_oldifs"
  _sbv_2a=$(_sb_numeric_field "${1:-0}")
  _sbv_2b=$(_sb_numeric_field "${2:-0}")
  _sbv_2c=$(_sb_numeric_field "${3:-0}")

  if [ "$_sbv_1a" -gt "$_sbv_2a" ]; then return 0; fi
  if [ "$_sbv_1a" -lt "$_sbv_2a" ]; then return 1; fi
  if [ "$_sbv_1b" -gt "$_sbv_2b" ]; then return 0; fi
  if [ "$_sbv_1b" -lt "$_sbv_2b" ]; then return 1; fi
  [ "$_sbv_1c" -ge "$_sbv_2c" ]
}

# --- Deteccao de sqlite3 ----------------------------------------------------

# _sb_check_sqlite3 -> seta _SB_SQLITE_PRESENT (yes|no) e _SB_SQLITE_VERSION
# (vazio quando ausente). GOTCHA (research.md Decision 8): sob set -e,
# `x=$(cmd); rc=$?` mata o shell — usa a forma `if x=$(cmd); then`.
_sb_check_sqlite3() {
  if command -v sqlite3 >/dev/null 2>&1; then
    _SB_SQLITE_PRESENT="yes"
    if _sbcs_raw=$(sqlite3 --version 2>/dev/null); then
      _SB_SQLITE_VERSION=$(printf '%s\n' "$_sbcs_raw" | cut -d' ' -f1)
    else
      _SB_SQLITE_VERSION=""
    fi
  else
    _SB_SQLITE_PRESENT="no"
    _SB_SQLITE_VERSION=""
  fi
}

# --- Parsing seguro da config (P1-P5) ---------------------------------------

# _sb_read_config -> seta:
#   _SB_CONFIG_STATE      ausente | invalida | declarado
#   _SB_DECLARED_BACKEND  sqlite | json (so quando declarado)
# NUNCA usa `.`/`source`/`eval` (P1). Parse linha a linha, split no PRIMEIRO
# `=` via expansao de parametro (P2/P5). Config ilegivel (existe mas nao e
# arquivo regular legivel) ⇒ invalida, nunca aborta (contrato de nao-falha).
_sb_read_config() {
  _SB_CONFIG_STATE="ausente"
  _SB_DECLARED_BACKEND=""

  if [ ! -e "$_SB_CONFIG_FILE" ]; then
    return 0
  fi
  if [ ! -f "$_SB_CONFIG_FILE" ] || [ ! -r "$_SB_CONFIG_FILE" ]; then
    _SB_CONFIG_STATE="invalida"
    return 0
  fi

  _sbrc_backend_value=""
  _sbrc_parse_error="no"
  while IFS= read -r _sbrc_line || [ -n "$_sbrc_line" ]; do
    case "$_sbrc_line" in
      ''|'#'*)
        : # linha em branco ou comentario — ignorada (P2)
        ;;
      *=*)
        _sbrc_key=${_sbrc_line%%=*}
        _sbrc_val=${_sbrc_line#*=}
        case "$_sbrc_key" in
          state_backend)
            _sbrc_backend_value="$_sbrc_val" # ultima ocorrencia vence
            ;;
          *)
            : # chave desconhecida — ignorada, arquivo permanece extensivel (P4)
            ;;
        esac
        ;;
      *)
        _sbrc_parse_error="yes" # linha sem '=' invalida a config INTEIRA (P2)
        ;;
    esac
  done < "$_SB_CONFIG_FILE"

  if [ "$_sbrc_parse_error" = "yes" ]; then
    _SB_CONFIG_STATE="invalida"
    return 0
  fi

  if [ -z "$_sbrc_backend_value" ]; then
    _SB_CONFIG_STATE="ausente" # arquivo existe mas sem state_backend
    return 0
  fi

  # P3: valor validado contra allowlist ANTES de qualquer uso.
  case "$_sbrc_backend_value" in
    sqlite|json)
      _SB_CONFIG_STATE="declarado"
      _SB_DECLARED_BACKEND="$_sbrc_backend_value"
      ;;
    *)
      _SB_CONFIG_STATE="invalida" # fora do dominio ⇒ fallback json (P3, FR-008)
      ;;
  esac
}

# --- capability --------------------------------------------------------------

_sb_cmd_capability() {
  printf '%s\n' "$_SB_CAPABILITY_TOKEN"
}

# --- resolve -----------------------------------------------------------------

_sb_cmd_resolve() {
  _sb_read_config
  case "$_SB_CONFIG_STATE" in
    ausente)
      printf 'effective_backend=json\n'
      printf 'reason=nunca-configurado\n'
      ;;
    invalida)
      printf 'effective_backend=json\n'
      printf 'reason=config-invalida\n'
      ;;
    declarado)
      case "$_SB_DECLARED_BACKEND" in
        json)
          printf 'effective_backend=json\n'
          printf 'reason=json-explicito\n'
          ;;
        sqlite)
          _sb_check_sqlite3
          if [ "$_SB_SQLITE_PRESENT" = "yes" ]; then
            if _sb_version_ge "$_SB_SQLITE_VERSION" "$_SB_MIN_SQLITE_VERSION"; then
              printf 'effective_backend=sqlite\n'
              printf 'reason=configurado-dependencia-adequada\n'
            else
              printf 'effective_backend=json\n'
              printf 'reason=configurado-dependencia-abaixo-do-minimo\n'
            fi
          else
            printf 'effective_backend=json\n'
            printf 'reason=configurado-dependencia-ausente\n'
          fi
          ;;
      esac
      ;;
  esac
  return 0 # contrato de nao-falha (FR-008): resolve NUNCA falha
}

# --- capability do catalogo instalado (P8) ----------------------------------

# _sb_own_abs_path -> path absoluto deste proprio script (candidato a
# "arvore-do-repo" quando o catalogo instalado nao existe).
_sb_own_abs_path() {
  _sbop_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || _sbop_dir=$(dirname -- "$0")
  printf '%s/%s\n' "$_sbop_dir" "$(basename -- "$0")"
}

# _sb_check_capability -> seta _SB_CAP_ORIGIN (catalogo-instalado |
# arvore-do-repo), _SB_CAP_PATH (path absoluto inspecionado) e _SB_CAP_OK
# (yes|no). P8: prioriza SEMPRE o catalogo instalado quando existe; layout
# de repo (via $CSTK_LIB, quando exportado pelo caller cli/lib/config.sh —
# variavel OPCIONAL, lida sem impor acoplamento estrutural a cli/lib) so e
# consultado quando o catalogo instalado NAO existe. Reporta o path mesmo
# quando o script nao e encontrado nele — e o proprio sinal de incapacidade
# (Decision 5, caso 1).
_sb_check_capability() {
  if [ -f "$_SB_INSTALLED_SCRIPT" ]; then
    _SB_CAP_ORIGIN="catalogo-instalado"
    _SB_CAP_PATH="$_SB_INSTALLED_SCRIPT"
  elif [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/state-backend.sh" ]; then
    _SB_CAP_ORIGIN="arvore-do-repo"
    _sbcc_dir=$(CDPATH= cd -- "$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts" 2>/dev/null && pwd -P)
    _SB_CAP_PATH="$_sbcc_dir/state-backend.sh"
  else
    _SB_CAP_ORIGIN="arvore-do-repo"
    _SB_CAP_PATH=$(_sb_own_abs_path)
  fi

  _SB_CAP_OK="no"
  if [ -f "$_SB_CAP_PATH" ]; then
    if _sbcc_token=$(sh "$_SB_CAP_PATH" capability 2>/dev/null); then
      if _sb_version_ge "$_sbcc_token" "$_SB_CAPABILITY_TOKEN"; then
        _SB_CAP_OK="yes"
      fi
    fi
  fi
}

# --- escrita atomica e idempotente (P6, P7) ---------------------------------

# _sb_write_config VALUE -> grava state_backend=VALUE em _SB_CONFIG_FILE.
# mktemp NO MESMO diretorio + mv (P7); dir 700, arquivo 600 (P6). Reescreve
# a(s) linha(s) `state_backend=` existente(s) — colapsa para EXATAMENTE UMA
# ocorrencia mesmo se o arquivo (editado a mao) tiver mais de uma. Demais
# linhas (comentarios, chaves desconhecidas) sao preservadas verbatim.
_sb_write_config() {
  _sbwc_val="$1"

  if [ ! -d "$_SB_CONFIG_DIR" ]; then
    mkdir -p -- "$_SB_CONFIG_DIR" || return 1
  fi
  chmod 700 -- "$_SB_CONFIG_DIR" 2>/dev/null || :

  _sbwc_tmp=$(mktemp -- "${_SB_CONFIG_FILE}.XXXXXX") || return 1
  chmod 600 -- "$_sbwc_tmp" 2>/dev/null || :

  _sbwc_written="no"
  if [ -f "$_SB_CONFIG_FILE" ] && [ -r "$_SB_CONFIG_FILE" ]; then
    while IFS= read -r _sbwc_line || [ -n "$_sbwc_line" ]; do
      case "$_sbwc_line" in
        state_backend=*)
          if [ "$_sbwc_written" = "no" ]; then
            printf 'state_backend=%s\n' "$_sbwc_val" >> "$_sbwc_tmp"
            _sbwc_written="yes"
          fi
          # ocorrencias subsequentes de state_backend= sao descartadas —
          # colapsa para uma unica linha (P7, FR-009-INFRA-IDEMP)
          ;;
        *)
          printf '%s\n' "$_sbwc_line" >> "$_sbwc_tmp"
          ;;
      esac
    done < "$_SB_CONFIG_FILE"
  fi
  if [ "$_sbwc_written" = "no" ]; then
    printf 'state_backend=%s\n' "$_sbwc_val" >> "$_sbwc_tmp"
  fi

  mv -- "$_sbwc_tmp" "$_SB_CONFIG_FILE" || { rm -f -- "$_sbwc_tmp"; return 1; }
  return 0
}

# --- enable-sqlite -----------------------------------------------------------

_sb_cmd_enable_sqlite() {
  # (1) sqlite3 presente no PATH
  _sb_check_sqlite3
  if [ "$_SB_SQLITE_PRESENT" != "yes" ]; then
    printf '%s: sqlite3 nao encontrado no PATH (minimo exigido: %s). Instale via seu gerenciador de pacotes (ex.: "brew install sqlite3" no macOS, "apt install sqlite3" no Ubuntu/Debian) e tente novamente.\n' \
      "$_SB_NAME" "$_SB_MIN_SQLITE_VERSION" >&2
    exit 3
  fi

  # (2) versao >= minima exigida
  if ! _sb_version_ge "$_SB_SQLITE_VERSION" "$_SB_MIN_SQLITE_VERSION"; then
    printf '%s: versao de sqlite3 insuficiente (minima exigida: %s; detectada: %s).\n' \
      "$_SB_NAME" "$_SB_MIN_SQLITE_VERSION" "$_SB_SQLITE_VERSION" >&2
    exit 3
  fi

  # (3) capability do runtime do catalogo instalado (P8, FR-004A)
  _sb_check_capability
  if [ "$_SB_CAP_OK" != "yes" ]; then
    printf '%s: capability verificado via %s (%s)\n' "$_SB_NAME" "$_SB_CAP_ORIGIN" "$_SB_CAP_PATH" >&2
    printf '%s: runtime incapaz — rode "cstk update" (catalogo instalado) ou "cstk self-update" (binario) e tente novamente.\n' "$_SB_NAME" >&2
    exit 3
  fi

  # Nenhuma escrita ate aqui — as 3 pre-condicoes passaram (SC-002 por construcao)
  _sb_read_config
  if [ "$_SB_CONFIG_STATE" = "declarado" ] && [ "$_SB_DECLARED_BACKEND" = "sqlite" ]; then
    # Idempotencia (FR-009-INFRA-IDEMP): no-op, config INTOCADA, exit 0.
    printf '%s: capability verificado via %s (%s)\n' "$_SB_NAME" "$_SB_CAP_ORIGIN" "$_SB_CAP_PATH"
    printf '%s: ja ativado (state_backend=sqlite) — nenhuma alteracao necessaria\n' "$_SB_NAME"
    return 0
  fi

  if ! _sb_write_config "sqlite"; then
    _sb_die "falha ao escrever $_SB_CONFIG_FILE" 1
  fi

  printf '%s: capability verificado via %s (%s)\n' "$_SB_NAME" "$_SB_CAP_ORIGIN" "$_SB_CAP_PATH"
  printf '%s: ativado (state_backend=sqlite) em %s\n' "$_SB_NAME" "$_SB_CONFIG_FILE"
  return 0
}

# --- dispatcher ---------------------------------------------------------------

_sb_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_sb_sub" in
  ''|-h|--help|help)
    _sb_usage
    exit 0
    ;;
  capability)
    _sb_cmd_capability "$@"
    ;;
  resolve)
    _sb_cmd_resolve "$@"
    ;;
  enable-sqlite)
    _sb_cmd_enable_sqlite "$@"
    ;;
  *)
    _sb_die_usage "subcomando desconhecido: $_sb_sub (validos: capability, resolve, enable-sqlite)"
    ;;
esac
