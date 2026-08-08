#!/bin/sh
# secrets-filter.sh — filtro de secrets em report/suggestions/issue (FR-030).
#
# Ref: docs/specs/agente-00c/spec.md FR-030
#      docs/specs/agente-00c/threat-model.md T4
#      docs/specs/agente-00c/tasks.md FASE 6.6
#      docs/specs/agente-00c-evolucao/tasks.md §1.3 (allow-list pos-execucao)
#
# Le stdin, escreve stdout com substituicao de cada match por [REDACTED].
# Aplica em ordem (cada padrao independente, nao excludente):
#
#   1. Tokens com palavra-chave proxima:
#      `(token|key|secret|password|pwd|auth|api_key|access_key)\s*[:=]\s*"?[A-Za-z0-9_-]{20,}"?`
#      → reduz falsos positivos (hashes git, UUIDs sem contexto NAO sao filtrados)
#   2. AWS access keys: `AKIA[A-Z0-9]{16,}`
#   3. Bearer tokens: `Bearer\s+[A-Za-z0-9._-]+`
#   4. Basic auth em URLs: `https?://[^:]+:[^@]+@`
#   5. Valores de chaves do .env do projeto-alvo (carregado via --env-file),
#      EXCETO:
#      a) chaves listadas na allow-list (`.secrets-filter-ignore` global do
#         script + opcional override `--ignore-file FILE`). Suporta wildcard
#         de sufixo (`PUBLIC_*` casa `PUBLIC_API_URL`, etc).
#      b) valores curtos (<30 chars) que matchem padrao slug
#         (`^[A-Za-z0-9_.-]+$`) — identificadores publicos por design
#         (SAML_ISSUER, COOKIE_DOMAIN, etc) raramente sao secrets.
#
# Subcomandos:
#   secrets-filter.sh scrub [--env-file FILE] [--ignore-file FILE]
#       — Le stdin, aplica filtros, escreve stdout.
#       — `--env-file` opcional (se ausente, pula passo 5).
#       — `--ignore-file` opcional (override do allow-list default).
#         Se ausente, descobre automaticamente:
#         (a) `<dir-do-script>/.secrets-filter-ignore` (baseline);
#         (b) `<dir-de-FILE>/.claude/agente-00c-state/secrets-filter-ignore`
#             (override do projeto-alvo, se existir).
#
#   secrets-filter.sh check [--env-file FILE] [--ignore-file FILE]
#       — Le stdin. Exit 0 se NAO contem secrets; exit 1 se contem (com
#         conteudo dos matches em stderr — nao em stdout para evitar leak
#         em pipelines).
#
# Exit codes:
#   0 sucesso (scrub) ou nenhum secret encontrado (check)
#   1 secret detectado em check
#   2 uso incorreto
#
# POSIX sh + sed/grep/awk.

set -eu

_SF_NAME="secrets-filter"

_sf_die_usage() { printf '%s: %s\n' "$_SF_NAME" "$1" >&2; exit 2; }

# Marcador unico usado durante substituicao multi-passo
_SF_MARK="[REDACTED]"

# _sf_script_dir → diretorio absoluto do script (para localizar .secrets-filter-ignore baseline)
_sf_script_dir() {
  # POSIX-friendly: dirname do $0 resolvido
  _d=$(dirname -- "$0")
  (cd "$_d" 2>/dev/null && pwd) || printf '%s' "$_d"
}

# _sf_resolve_ignore_files EXPLICIT_IGNORE ENV_FILE
# Imprime caminhos de allow-list (1 por linha) em ordem de carga.
# Sem args, retorna apenas o baseline (se existir).
_sf_resolve_ignore_files() {
  _explicit=$1
  _envf=$2
  _base="$(_sf_script_dir)/.secrets-filter-ignore"
  [ -f "$_base" ] && printf '%s\n' "$_base"
  if [ -n "$_envf" ] && [ -f "$_envf" ]; then
    _proj_dir=$(dirname -- "$_envf")
    _proj_ignore="$_proj_dir/.claude/agente-00c-state/secrets-filter-ignore"
    [ -f "$_proj_ignore" ] && printf '%s\n' "$_proj_ignore"
  fi
  if [ -n "$_explicit" ] && [ -f "$_explicit" ]; then
    printf '%s\n' "$_explicit"
  fi
}

# _sf_key_allowed KEY IGNORE_FILES_LIST
# Exit 0 se KEY esta na allow-list; 1 caso contrario.
# Suporta match exato ou wildcard de sufixo (`PUBLIC_*`).
_sf_key_allowed() {
  _key=$1
  _files=$2
  [ -z "$_files" ] && return 1
  printf '%s\n' "$_files" | while IFS= read -r _ig_file; do
    [ -z "$_ig_file" ] && continue
    [ -f "$_ig_file" ] || continue
    while IFS= read -r _pat || [ -n "$_pat" ]; do
      # Pula comentarios e linhas vazias
      case "$_pat" in
        ''|\#*) continue ;;
      esac
      # Trim whitespace
      _pat=$(printf '%s' "$_pat" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
      [ -z "$_pat" ] && continue
      # Wildcard de sufixo
      case "$_pat" in
        *\*)
          _prefix=${_pat%\*}
          case "$_key" in
            "${_prefix}"*) printf 'allow\n'; return 0 ;;
          esac
          ;;
        *)
          [ "$_key" = "$_pat" ] && { printf 'allow\n'; return 0; }
          ;;
      esac
    done < "$_ig_file"
  done | grep -q '^allow$'
}

# _sf_value_looks_public VAL
# Exit 0 se VAL parece identificador publico (slug curto); 1 caso contrario.
# Criterio:
#   1. <30 chars
#   2. match `^[A-Za-z0-9_.-]+$` (apenas chars slug-friendly)
#   3. contem ao menos um SEPARADOR (`-`, `_`, ou `.`) — descarta strings
#      como "mysupersecretpwd" (passphrase), "abcdef1234567890" (hex
#      anonimo) ou "Tk7zPpQv9XwYbL" (token alfanumerico). Slugs
#      publicos por design (tenant-abc-123, projeto.foo.v1, v1_release)
#      sempre tem pelo menos 1 separador.
_sf_value_looks_public() {
  _val=$1
  _len=$(printf '%s' "$_val" | wc -c | tr -d ' ')
  [ "$_len" -lt 30 ] || return 1
  printf '%s' "$_val" | grep -qE '^[A-Za-z0-9_.-]+$' || return 1
  printf '%s' "$_val" | grep -qE '[-_.]' || return 1
  return 0
}

# _sf_apply_filters STDIN-via-pipe ENV_FILE [IGNORE_FILE]
# Imprime stdin filtrado em stdout. Aplicacao em sequencia via tempfiles
# (mais simples e portavel que multiplas substituicoes em sed -e).
_sf_apply_filters() {
  _env=$1
  _explicit_ig=${2:-}
  _ignore_files=$(_sf_resolve_ignore_files "$_explicit_ig" "$_env")
  _t1=$(mktemp); _t2=$(mktemp)
  cat > "$_t1"

  # Ordem: especificos primeiro (rules com formato unico), generico ultimo.
  # Caso contrario, o regex generico de token mascararia AKIA/Bearer com
  # [REDACTED] genenrico e perderia o tipo do secret.

  # 1. AWS access keys (formato unico)
  sed -E 's/AKIA[A-Z0-9]{16,}/[REDACTED-AWS-KEY]/g' "$_t1" > "$_t2"
  mv "$_t2" "$_t1"; _t2=$(mktemp)

  # 2. Bearer tokens (formato unico)
  sed -E 's/Bearer[[:space:]]+[A-Za-z0-9._=+\/-]+/Bearer [REDACTED]/g' "$_t1" > "$_t2"
  mv "$_t2" "$_t1"; _t2=$(mktemp)

  # 3. Basic auth em URLs (https://user:pass@host -> https://[REDACTED]@host)
  sed -E 's,(https?://)[^:[:space:]]+:[^@[:space:]]+@,\1[REDACTED]@,g' "$_t1" > "$_t2"
  mv "$_t2" "$_t1"; _t2=$(mktemp)

  # 4. Tokens genericos com palavra-chave proxima (proximidade reduz falsos
  #    positivos). Regex: (KEY) WS* [:=] WS* "?" [A-Za-z0-9...]{20,} "?".
  if sed -E -e 's/((token|key|secret|password|pwd|auth|api_?key|access_?key)[[:space:]]*[:=][[:space:]]*"?)[A-Za-z0-9_=+\/-]{20,}("?)/\1[REDACTED]\3/Ig' \
    "$_t1" > "$_t2" 2>/dev/null; then
    mv "$_t2" "$_t1"
    _t2=$(mktemp)
  fi

  # 5. Valores de .env (se passado), respeitando allow-list e heuristica slug.
  if [ -n "$_env" ] && [ -f "$_env" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
      # Pula vazias/comentarios
      case "$_line" in
        ''|\#*) continue ;;
      esac
      # Remove `export ` opcional
      _l=$(printf '%s' "$_line" | sed -E 's/^export[[:space:]]+//')
      # Captura KEY e VALOR
      _key=$(printf '%s' "$_l" | sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p')
      _val=$(printf '%s' "$_l" | sed -nE 's/^[A-Za-z_][A-Za-z0-9_]*=//p')
      [ -z "$_key" ] && continue
      [ -z "$_val" ] && continue
      # Remove aspas externas
      _val=$(printf '%s' "$_val" | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')
      # Comprimentos < 8 sao ignorados (high false-positive rate)
      _len=$(printf '%s' "$_val" | wc -c | tr -d ' ')
      [ "$_len" -lt 8 ] && continue
      # Allow-list explicita por chave (SAML_ISSUER, PUBLIC_*, etc)
      if _sf_key_allowed "$_key" "$_ignore_files"; then
        continue
      fi
      # Heuristica slug publico: valor curto e sem caracteres especiais
      if _sf_value_looks_public "$_val"; then
        continue
      fi
      # Escape de metacaracteres BRE + delimitador `/` para casar o valor
      # como literal. Usa BRE (sed sem -E) de proposito: em ERE, `+ ? ( ) { } |`
      # tambem sao metacaracteres e NAO sao cobertos por este escape — um valor
      # iniciado por `+` (ex.: numero E.164 +5527...) viraria operador de
      # repeticao invalido e abortaria com "repetition-operator operand invalid".
      # Em BRE esses chars sao literais, entao o escape de `] \ / $ * . ^ [`
      # e suficiente.
      _esc=$(printf '%s' "$_val" | sed 's/[]\/$*.^[]/\\&/g')
      sed "s/${_esc}/[REDACTED-ENV]/g" "$_t1" > "$_t2"
      mv "$_t2" "$_t1"; _t2=$(mktemp)
    done < "$_env"
  fi

  cat "$_t1"
  rm -f -- "$_t1" "$_t2" 2>/dev/null || :
}

_sf_cmd_scrub() {
  _env=""
  _ig=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env-file)    _env=$2; shift 2 ;;
      --ignore-file) _ig=$2;  shift 2 ;;
      *) _sf_die_usage "scrub: flag desconhecida: $1" ;;
    esac
  done
  _sf_apply_filters "$_env" "$_ig"
}

_sf_cmd_check() {
  _env=""
  _ig=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env-file)    _env=$2; shift 2 ;;
      --ignore-file) _ig=$2;  shift 2 ;;
      *) _sf_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  # Aplica filtros e compara com original
  _orig=$(mktemp); _filt=$(mktemp)
  cat > "$_orig"
  # Re-injetar via pipe
  _sf_apply_filters "$_env" "$_ig" < "$_orig" > "$_filt"
  if cmp -s "$_orig" "$_filt"; then
    rm -f -- "$_orig" "$_filt"
    exit 0
  fi
  printf '%s: SECRETS DETECTADOS no input\n' "$_SF_NAME" >&2
  rm -f -- "$_orig" "$_filt"
  exit 1
}

# _sf_cmd_for_backup
#   Le state.json em stdin, aplica filtros (incluindo passo 5 se --env-file),
#   computa SHA-256 do conteudo filtrado e emite envelope JSON em stdout:
#     {wave_number, captured_at, state_sha256_self, state_snapshot}
#   Hash e calculado SOBRE O CONTEUDO FILTRADO (state_snapshot), nao sobre
#   o state original. Implementa FR-029 §extensao + FR-034 (Decision 6).
_sf_cmd_for_backup() {
  _env=""
  _ig=""
  _wave=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env-file)     _env=$2;  shift 2 ;;
      --ignore-file)  _ig=$2;   shift 2 ;;
      --wave-number)  _wave=$2; shift 2 ;;
      *) _sf_die_usage "for-backup: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_wave" ] || _sf_die_usage "for-backup: --wave-number obrigatorio"
  # Validar que wave-number e inteiro nao-negativo
  case "$_wave" in
    ''|*[!0-9]*) _sf_die_usage "for-backup: --wave-number invalido: $_wave (esperado inteiro >=0)" ;;
  esac

  _filt=$(mktemp)
  _sf_apply_filters "$_env" "$_ig" > "$_filt"
  # Hash do conteudo filtrado
  _sha=$(sha256sum < "$_filt" | awk '{print $1}')
  _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Construir envelope JSON. state_snapshot e o JSON filtrado (parseado
  # como objeto, nao como string). jq --slurpfile carrega como array;
  # acessa primeiro elemento.
  if ! jq -n \
       --argjson wave "$_wave" \
       --arg ts "$_ts" \
       --arg sha "$_sha" \
       --slurpfile state "$_filt" \
       '{wave_number: $wave, captured_at: $ts, state_sha256_self: $sha, state_snapshot: ($state[0] // null)}' 2>/dev/null; then
    rm -f -- "$_filt"
    printf '%s: falha ao montar envelope JSON (state.json invalido?)\n' "$_SF_NAME" >&2
    exit 1
  fi
  rm -f -- "$_filt"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
secrets-filter.sh — filtro de secrets em report/suggestions/issue (FR-030).

USO:
  secrets-filter.sh scrub [--env-file FILE] [--ignore-file FILE]   < input > output
  secrets-filter.sh check [--env-file FILE] [--ignore-file FILE]   < input

Aplica em sequencia: tokens com palavra-chave proxima, AWS keys, Bearer
tokens, basic auth em URLs, valores de .env (se --env-file) — respeitando
allow-list de chaves publicas (`.secrets-filter-ignore` global + override
opcional via --ignore-file ou auto-descoberta em
`<env-dir>/.claude/agente-00c-state/secrets-filter-ignore`).

EXIT (check):
  0 nenhum secret detectado
  1 secret detectado
HELP
  exit 2
fi

_SF_SUBCMD=$1
shift

case "$_SF_SUBCMD" in
  scrub)           _sf_cmd_scrub "$@" ;;
  check)           _sf_cmd_check "$@" ;;
  for-backup)      _sf_cmd_for_backup "$@" ;;
  -h|--help|help)  exit 0 ;;
  *) _sf_die_usage "subcomando desconhecido: $_SF_SUBCMD" ;;
esac
