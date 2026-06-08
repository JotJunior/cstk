#!/bin/sh
# plugin-common.sh — helpers compartilhados para o sistema de plugins cstk.
#
# Funcoes exportadas:
#   plugin_validate_name <name>                      — valida regex FR-002; exit 2 se invalido
#   plugin_resolve_url <name>                        — monta URL base do repositorio do plugin
#   plugin_store_dir <name>                          — retorna path do diretorio do plugin no store
#   plugin_registry_path                             — retorna path do registry.json
#   plugin_registry_init                             — cria registry vazio se nao existe (idempotente)
#   plugin_registry_upsert <name> <ver> <type> <sha256>  — upsert atomico
#   plugin_registry_remove <name>                    — remove entrada
#   plugin_registry_get <name>                       — TSV: name<TAB>ver<TAB>type<TAB>sha256<TAB>installed_at
#   plugin_registry_list                             — lista todas as entradas (mesma linha por plugin)
#   plugin_is_installed <name>                       — exit 0 se instalado, 1 se nao
#   plugin_compute_bundle_checksum <dir>             — SHA-256 do bundle excluindo manifest
#   plugin_verify_manifest <staging_dir>             — valida shape e retorna campos
#   plugin_verify_bundle_checksum <dir> <expected>   — compara checksum; exit 1 em mismatch
#   plugin_resolve_skill_dir <plugin_name> <skill>   — path-prepending FR-014
#
# Convencoes:
#   - Variaveis locais: prefixo _pc_ (POSIX sh nao tem local)
#   - Source guard _CSTK_PLUGIN_COMMON_LOADED
#   - Deps opcionais: jq (carve-out 1.1.0; fallback POSIX grep/sed)
#
# POSIX sh puro. set -eu no entrypoint; este arquivo e sourced.

if [ -n "${_CSTK_PLUGIN_COMMON_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_PLUGIN_COMMON_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/compat.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/hash.sh"

# Versao maxima de schema_version do manifest que este toolkit entende (research D6).
PLUGIN_SCHEMA_MAX=1

# ---------------------------------------------------------------------------
# 2.1 Estrutura e validacao de nome
# ---------------------------------------------------------------------------

# plugin_validate_name <name>
# Valida regex ^[a-z][a-z0-9-]{0,63}$ (FR-002).
# Exit 0 = valido; exit 2 = invalido (mensagem em stderr).
plugin_validate_name() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_validate_name espera 1 argumento\n' >&2
    return 2
  fi
  _pc_name=$1
  # Validar com grep -E em LC_ALL=C para evitar colacao de locale.
  # Regex: ^[a-z][a-z0-9-]{0,63}$ (FR-002)
  # Comprimento: minimo 1 char (a letra inicial), maximo 64 chars total.
  _pc_len=${#_pc_name}
  if [ "$_pc_len" -lt 1 ] || [ "$_pc_len" -gt 64 ]; then
    printf 'plugin: nome invalido %s (comprimento deve ser 1-64)\n' "$_pc_name" >&2
    return 2
  fi
  if printf '%s' "$_pc_name" | LC_ALL=C grep -qE '^[a-z][a-z0-9-]*$' 2>/dev/null; then
    return 0
  fi
  printf 'plugin: nome invalido %s (regra: ^[a-z][a-z0-9-]{0,63}$)\n' "$_pc_name" >&2
  return 2
}

# plugin_resolve_url <name>
# Monta a URL base do repositorio do plugin (sem sufixo de release).
# Retorna na stdout: <base_url>/cstk-plugin-<name>
# Ordem de precedencia (FR-001):
#   1. CSTK_PLUGIN_REGISTRY env
#   2. ~/.cstk/config key "registry"
#   3. hardcoded https://github.com/JotJunior/
plugin_resolve_url() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_resolve_url espera 1 argumento (name)\n' >&2
    return 2
  fi
  _pc_name=$1
  _pc_base=""

  # 1. Env override.
  if [ -n "${CSTK_PLUGIN_REGISTRY:-}" ]; then
    _pc_base="$CSTK_PLUGIN_REGISTRY"
  fi

  # 2. ~/.cstk/config key "registry" (POSIX key=value, uma por linha).
  if [ -z "$_pc_base" ]; then
    _pc_cfg="${HOME}/.cstk/config"
    if [ -f "$_pc_cfg" ]; then
      # grep linha "registry=..." e extrai valor apos o "=".
      _pc_base=$(grep -m1 '^registry=' "$_pc_cfg" 2>/dev/null | cut -d= -f2- || true)
    fi
  fi

  # 3. Fallback hardcoded.
  if [ -z "$_pc_base" ]; then
    _pc_base="https://github.com/JotJunior/"
  fi

  # Garantir que base nao termina com "/" dupla antes de montar.
  _pc_base="${_pc_base%/}"
  printf '%s/cstk-plugin-%s\n' "$_pc_base" "$_pc_name"
}

# plugin_store_dir <name>
# Retorna o path do diretorio do plugin no store (research D1).
# Nao verifica existencia — apenas constroi o path.
plugin_store_dir() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_store_dir espera 1 argumento (name)\n' >&2
    return 2
  fi
  printf '%s/.claude/cstk/plugins/%s\n' "$HOME" "$1"
}

# ---------------------------------------------------------------------------
# 2.2 Registry CRUD
# ---------------------------------------------------------------------------

# plugin_registry_path
# Retorna o path canonico do registry.json.
plugin_registry_path() {
  printf '%s/.claude/cstk/plugins/registry.json\n' "$HOME"
}

# _pc_registry_dir
# Retorna o diretorio pai do registry.json.
_pc_registry_dir() {
  printf '%s/.claude/cstk/plugins\n' "$HOME"
}

# plugin_registry_init
# Cria registry vazio se nao existe; idempotente (FR-008 analogia).
plugin_registry_init() {
  _pc_reg=$(_pc_registry_dir)
  _pc_reg_file=$(plugin_registry_path)
  if [ ! -d "$_pc_reg" ]; then
    mkdir -p -- "$_pc_reg" || {
      printf 'plugin: nao foi possivel criar diretorio do registry: %s\n' "$_pc_reg" >&2
      return 1
    }
  fi
  if [ ! -f "$_pc_reg_file" ]; then
    printf '{"schema_version":1,"plugins":[]}\n' > "$_pc_reg_file" || {
      printf 'plugin: nao foi possivel criar registry.json em %s\n' "$_pc_reg_file" >&2
      return 1
    }
  fi
  return 0
}

# _pc_has_jq — verifica que jq esta disponivel E funcional (parseia JSON minimo).
# Exit 0 se jq operacional; exit 1 se ausente ou nao-funcional.
_pc_has_jq() {
  command -v jq >/dev/null 2>&1 && printf '1' | jq -e . >/dev/null 2>&1
}

# _pc_iso_now — ISO 8601 UTC (via compat.sh iso_now_utc se disponivel).
_pc_iso_now() {
  iso_now_utc 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ
}

# plugin_registry_upsert <name> <version> <type> <bundle_sha256>
# Upsert atomico da entrada do plugin no registry.
# Usa jq se disponivel; fallback POSIX sed/grep para campos flat (research D5).
plugin_registry_upsert() {
  if [ "$#" -ne 4 ]; then
    printf 'plugin: plugin_registry_upsert espera 4 args (name version type sha256)\n' >&2
    return 2
  fi
  _pc_u_name=$1
  _pc_u_ver=$2
  _pc_u_type=$3
  _pc_u_sha=$4
  _pc_u_now=$(_pc_iso_now)

  plugin_registry_init || return 1
  _pc_u_reg=$(plugin_registry_path)

  if _pc_has_jq; then
    # Upsert via jq: remove entrada existente (se houver) e adiciona nova.
    _pc_u_tmp=$(mktemp 2>/dev/null) || {
      printf 'plugin: mktemp falhou em upsert\n' >&2
      return 1
    }
    jq --arg n "$_pc_u_name" --arg v "$_pc_u_ver" --arg t "$_pc_u_type" \
       --arg s "$_pc_u_sha" --arg ts "$_pc_u_now" \
       '.plugins = ([.plugins[] | select(.name != $n)] + [{
           name: $n, version: $v, type: $t,
           installed_at: $ts, bundle_sha256: $s
       }])' "$_pc_u_reg" > "$_pc_u_tmp" || {
      rm -f -- "$_pc_u_tmp"
      printf 'plugin: jq upsert falhou\n' >&2
      return 1
    }
    # Mover atomicamente (mesmo FS).
    mv -- "$_pc_u_tmp" "$_pc_u_reg" || {
      rm -f -- "$_pc_u_tmp"
      printf 'plugin: mv atomico do registry falhou\n' >&2
      return 1
    }
  else
    # Fallback POSIX: o registry e JSON flat (sem aninhamento profundo).
    # Abordagem: reescrever o array plugins reconstruindo linha a linha.
    # Remover entrada existente e adicionar nova ao final.
    _pc_u_tmp=$(mktemp 2>/dev/null) || {
      printf 'plugin: mktemp falhou em upsert (fallback)\n' >&2
      return 1
    }
    # Construir nova entrada JSON (sem jq — formato fixo, sem escape especial).
    _pc_u_entry="  {\"name\":\"${_pc_u_name}\",\"version\":\"${_pc_u_ver}\",\"type\":\"${_pc_u_type}\",\"installed_at\":\"${_pc_u_now}\",\"bundle_sha256\":\"${_pc_u_sha}\"}"

    # Ler o arquivo linha por linha, reconstruir sem a entrada antiga.
    # O registry tem o formato JSON one-object-per-line gerado por jq ou por nos mesmos.
    # Estrategia simples: extrair linhas de objeto exceto a do plugin alvo, montar novo JSON.
    _pc_u_lines=""
    _pc_u_in_arr=0
    while IFS= read -r _pc_u_line; do
      case "$_pc_u_line" in
        *'"plugins"'*'['*)  _pc_u_in_arr=1; continue ;;
        *']'*) _pc_u_in_arr=0; continue ;;
        *'"name"'*"\"${_pc_u_name}\""*)
          # Pular a entrada do plugin alvo (pode ocupar varias linhas).
          # Para simplificar, assumimos que cada entrada do plugin esta numa unica linha
          # (formato gerado por nosso upsert via jq ou por plugin_registry_init).
          continue
          ;;
        *'schema_version'*|*'{'*|*'}'*) continue ;;
        '')  continue ;;
        *)
          if [ "$_pc_u_in_arr" = "1" ]; then
            # linha de objeto de outro plugin
            _pc_u_lines="${_pc_u_lines}${_pc_u_line}
"
          fi
          ;;
      esac
    done < "$_pc_u_reg"

    # Montar novo conteudo
    {
      printf '{"schema_version":1,"plugins":[\n'
      # Entradas existentes (sem trailing comma na ultima — simplificado: aceitar trailing comma)
      if [ -n "$_pc_u_lines" ]; then
        printf '%s' "$_pc_u_lines" | while IFS= read -r _ll; do
          [ -n "$_ll" ] && printf '  %s,\n' "$_ll"
        done
      fi
      printf '%s\n' "$_pc_u_entry"
      printf ']}\n'
    } > "$_pc_u_tmp" || {
      rm -f -- "$_pc_u_tmp"
      printf 'plugin: write fallback registry falhou\n' >&2
      return 1
    }
    mv -- "$_pc_u_tmp" "$_pc_u_reg" || {
      rm -f -- "$_pc_u_tmp"
      return 1
    }
  fi
  return 0
}

# plugin_registry_remove <name>
# Remove entrada do plugin pelo nome; exit 0 se removido, 1 se nao encontrado.
plugin_registry_remove() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_registry_remove espera 1 argumento (name)\n' >&2
    return 2
  fi
  _pc_r_name=$1
  _pc_r_reg=$(plugin_registry_path)

  if [ ! -f "$_pc_r_reg" ]; then
    printf 'plugin: registry nao encontrado em %s\n' "$_pc_r_reg" >&2
    return 1
  fi

  if _pc_has_jq; then
    # Verificar existencia antes de remover.
    _pc_r_count=$(jq --arg n "$_pc_r_name" '[.plugins[] | select(.name == $n)] | length' "$_pc_r_reg" 2>/dev/null || printf '0')
    if [ "${_pc_r_count:-0}" = "0" ]; then
      return 1
    fi
    _pc_r_tmp=$(mktemp 2>/dev/null) || return 1
    jq --arg n "$_pc_r_name" '.plugins = [.plugins[] | select(.name != $n)]' \
       "$_pc_r_reg" > "$_pc_r_tmp" || { rm -f -- "$_pc_r_tmp"; return 1; }
    mv -- "$_pc_r_tmp" "$_pc_r_reg" || { rm -f -- "$_pc_r_tmp"; return 1; }
  else
    # Fallback: verificar presenca via grep.
    if ! grep -q "\"name\":\"${_pc_r_name}\"" "$_pc_r_reg" 2>/dev/null; then
      return 1
    fi
    # Recriar sem a linha do plugin (cada entrada numa linha, gerada por nosso upsert).
    _pc_r_tmp=$(mktemp 2>/dev/null) || return 1
    {
      printf '{"schema_version":1,"plugins":[\n'
      _pc_r_first=1
      while IFS= read -r _pc_r_line; do
        case "$_pc_r_line" in
          *'"name"'*"\"${_pc_r_name}\""*) continue ;;
          *'"name"'*'"'*)
            if [ "$_pc_r_first" = "0" ]; then printf ',\n'; fi
            printf '%s' "$_pc_r_line"
            _pc_r_first=0
            ;;
        esac
      done < "$_pc_r_reg"
      printf '\n]}\n'
    } > "$_pc_r_tmp" || { rm -f -- "$_pc_r_tmp"; return 1; }
    mv -- "$_pc_r_tmp" "$_pc_r_reg" || { rm -f -- "$_pc_r_tmp"; return 1; }
  fi
  return 0
}

# plugin_registry_get <name>
# Retorna linha TSV: name<TAB>version<TAB>type<TAB>bundle_sha256<TAB>installed_at
# Exit 0 se encontrado; exit 1 se ausente.
plugin_registry_get() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_registry_get espera 1 argumento (name)\n' >&2
    return 2
  fi
  _pc_g_name=$1
  _pc_g_reg=$(plugin_registry_path)

  if [ ! -f "$_pc_g_reg" ]; then
    return 1
  fi

  if _pc_has_jq; then
    _pc_g_out=$(jq -r --arg n "$_pc_g_name" \
      '.plugins[] | select(.name == $n) | [.name, .version, .type, .bundle_sha256, .installed_at] | @tsv' \
      "$_pc_g_reg" 2>/dev/null)
    if [ -z "$_pc_g_out" ]; then
      return 1
    fi
    printf '%s\n' "$_pc_g_out"
  else
    # Fallback: grep linha com o nome e extrair campos via sed.
    _pc_g_line=$(grep "\"name\":\"${_pc_g_name}\"" "$_pc_g_reg" 2>/dev/null | head -1)
    if [ -z "$_pc_g_line" ]; then
      return 1
    fi
    # Extrair campos individuais.
    _pc_g_ver=$(printf '%s' "$_pc_g_line" | sed 's/.*"version":"\([^"]*\)".*/\1/')
    _pc_g_type=$(printf '%s' "$_pc_g_line" | sed 's/.*"type":"\([^"]*\)".*/\1/')
    _pc_g_sha=$(printf '%s' "$_pc_g_line" | sed 's/.*"bundle_sha256":"\([^"]*\)".*/\1/')
    _pc_g_ts=$(printf '%s' "$_pc_g_line" | sed 's/.*"installed_at":"\([^"]*\)".*/\1/')
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$_pc_g_name" "$_pc_g_ver" "$_pc_g_type" "$_pc_g_sha" "$_pc_g_ts"
  fi
}

# plugin_registry_list
# Lista todas as entradas do registry; uma linha TSV por plugin.
# Exit 0 mesmo se lista vazia.
plugin_registry_list() {
  _pc_l_reg=$(plugin_registry_path)

  if [ ! -f "$_pc_l_reg" ]; then
    return 0
  fi

  if _pc_has_jq; then
    jq -r '.plugins[] | [.name, .version, .type, .bundle_sha256, .installed_at] | @tsv' \
       "$_pc_l_reg" 2>/dev/null || true
  else
    # Fallback: cada entrada numa linha; extrair campos.
    grep '"name":' "$_pc_l_reg" 2>/dev/null | while IFS= read -r _pc_l_line; do
      _pc_l_n=$(printf '%s' "$_pc_l_line" | sed 's/.*"name":"\([^"]*\)".*/\1/')
      _pc_l_v=$(printf '%s' "$_pc_l_line" | sed 's/.*"version":"\([^"]*\)".*/\1/')
      _pc_l_t=$(printf '%s' "$_pc_l_line" | sed 's/.*"type":"\([^"]*\)".*/\1/')
      _pc_l_s=$(printf '%s' "$_pc_l_line" | sed 's/.*"bundle_sha256":"\([^"]*\)".*/\1/')
      _pc_l_ts=$(printf '%s' "$_pc_l_line" | sed 's/.*"installed_at":"\([^"]*\)".*/\1/')
      printf '%s\t%s\t%s\t%s\t%s\n' "$_pc_l_n" "$_pc_l_v" "$_pc_l_t" "$_pc_l_s" "$_pc_l_ts"
    done
  fi
}

# ---------------------------------------------------------------------------
# 2.3 Checksum e integridade
# ---------------------------------------------------------------------------

# plugin_compute_bundle_checksum <dir>
# Retorna hex SHA-256 do bundle excluindo plugin-manifest.json (research D2).
# Delega a hash_dir de hash.sh com exclusao do manifest.
plugin_compute_bundle_checksum() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_compute_bundle_checksum espera 1 argumento (dir)\n' >&2
    return 2
  fi
  _pc_cb_dir=$1
  if [ ! -d "$_pc_cb_dir" ]; then
    printf 'plugin: diretorio nao existe: %s\n' "$_pc_cb_dir" >&2
    return 1
  fi

  # hash_dir exclui plugin-manifest.json via find customizado.
  # Reimplementamos aqui para poder excluir o manifest, ja que hash_dir
  # hasheia TODOS os arquivos. Usamos o mesmo algoritmo de hash_dir mas
  # com find que exclui plugin-manifest.json.
  (
    cd -- "$_pc_cb_dir" || return 1
    find . -type f ! -name 'plugin-manifest.json' -print | sort | while IFS= read -r _f; do
      _h=$(sha256_file "$_f") || exit 1
      printf '%s  %s\n' "$_h" "$_f"
    done
  ) | sha256_stdin
}

# plugin_verify_manifest <staging_dir>
# Le plugin-manifest.json; valida shape (6 campos obrigatorios — data-model ordem 1-5 + skills).
# Stdout: JSON da entrada se valido.
# Exit 0 = valido; exit 1 = invalido (mensagem em stderr).
plugin_verify_manifest() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_verify_manifest espera 1 argumento (staging_dir)\n' >&2
    return 2
  fi
  _pc_vm_dir=$1
  _pc_vm_mf="$_pc_vm_dir/plugin-manifest.json"

  if [ ! -f "$_pc_vm_mf" ]; then
    printf 'plugin: plugin-manifest.json ausente em %s\n' "$_pc_vm_dir" >&2
    return 1
  fi

  if _pc_has_jq; then
    # Validar com jq — campos obrigatorios: name, version, type, schema_version, sha256, skills.
    _pc_vm_ok=$(jq -r '
      if (.name | type) != "string" then "ERR:name" elif
         (.version | type) != "string" then "ERR:version" elif
         (.type | type) != "string" then "ERR:type" elif
         (.type | test("^(llm|lang)$")) | not then "ERR:type_enum" elif
         (.schema_version | type) != "number" then "ERR:schema_version" elif
         (.sha256 | type) != "string" then "ERR:sha256" elif
         (.sha256 | length) != 64 then "ERR:sha256_len" elif
         (.skills | type) != "array" then "ERR:skills" else
         "OK"
      end
    ' "$_pc_vm_mf" 2>/dev/null) || _pc_vm_ok="ERR:jq"

    case "$_pc_vm_ok" in
      OK) : ;;
      ERR:name)         printf 'plugin: manifest invalido: campo name ausente ou nao string\n' >&2; return 1 ;;
      ERR:version)      printf 'plugin: manifest invalido: campo version ausente ou nao string\n' >&2; return 1 ;;
      ERR:type)         printf 'plugin: manifest invalido: campo type ausente ou nao string\n' >&2; return 1 ;;
      ERR:type_enum)    printf 'plugin: manifest invalido: type deve ser "llm" ou "lang"\n' >&2; return 1 ;;
      ERR:schema_version) printf 'plugin: manifest invalido: schema_version ausente ou nao numero\n' >&2; return 1 ;;
      ERR:sha256)       printf 'plugin: manifest invalido: campo sha256 ausente ou nao string\n' >&2; return 1 ;;
      ERR:sha256_len)   printf 'plugin: manifest invalido: sha256 deve ter 64 chars hex\n' >&2; return 1 ;;
      ERR:skills)       printf 'plugin: manifest invalido: campo skills deve ser array\n' >&2; return 1 ;;
      *)                printf 'plugin: manifest invalido: erro ao parsear\n' >&2; return 1 ;;
    esac

    # Verificar schema_version <= PLUGIN_SCHEMA_MAX.
    _pc_vm_sv=$(jq -r '.schema_version' "$_pc_vm_mf")
    if [ "$_pc_vm_sv" -gt "$PLUGIN_SCHEMA_MAX" ] 2>/dev/null; then
      printf 'plugin: manifest usa schema_version %s; esta versao do toolkit entende ate %s — atualize o toolkit\n' \
        "$_pc_vm_sv" "$PLUGIN_SCHEMA_MAX" >&2
      return 1
    fi

    cat "$_pc_vm_mf"
  else
    # Fallback POSIX: verificar presenca dos 6 campos via grep.
    for _pc_vm_field in '"name"' '"version"' '"type"' '"schema_version"' '"sha256"' '"skills"'; do
      if ! grep -q "$_pc_vm_field" "$_pc_vm_mf" 2>/dev/null; then
        printf 'plugin: manifest invalido: campo %s ausente (sem jq, validacao basica)\n' "$_pc_vm_field" >&2
        return 1
      fi
    done
    # Verificar tipo e comprimento de sha256 (64 hex chars).
    _pc_vm_sha=$(grep '"sha256"' "$_pc_vm_mf" | sed 's/.*"sha256":"\([^"]*\)".*/\1/')
    _pc_vm_sha_len=${#_pc_vm_sha}
    if [ "$_pc_vm_sha_len" -ne 64 ]; then
      printf 'plugin: manifest invalido: sha256 deve ter 64 chars (obtido %d)\n' "$_pc_vm_sha_len" >&2
      return 1
    fi
    cat "$_pc_vm_mf"
  fi
}

# plugin_verify_bundle_checksum <dir> <expected_sha256>
# Recomputa checksum do bundle e compara com expected.
# Exit 0 = ok; exit 1 = mismatch (mensagem clara em stderr, FR-004/US1-AS2).
plugin_verify_bundle_checksum() {
  if [ "$#" -ne 2 ]; then
    printf 'plugin: plugin_verify_bundle_checksum espera 2 args (dir, expected_sha256)\n' >&2
    return 2
  fi
  _pc_vc_dir=$1
  _pc_vc_exp=$2

  _pc_vc_got=$(plugin_compute_bundle_checksum "$_pc_vc_dir") || return 1
  if [ "$_pc_vc_got" != "$_pc_vc_exp" ]; then
    printf 'plugin: checksum mismatch — esperado %s, obtido %s\n' "$_pc_vc_exp" "$_pc_vc_got" >&2
    return 1
  fi
  return 0
}

# plugin_is_installed <name>
# Exit 0 se plugin esta instalado (entrada no registry E diretorio existe).
# Exit 1 se nao instalado.
plugin_is_installed() {
  if [ "$#" -ne 1 ]; then
    printf 'plugin: plugin_is_installed espera 1 argumento (name)\n' >&2
    return 2
  fi
  _pc_ii_name=$1
  _pc_ii_dir=$(plugin_store_dir "$_pc_ii_name")

  # Verificar entrada no registry.
  plugin_registry_get "$_pc_ii_name" >/dev/null 2>/dev/null || return 1

  # Verificar existencia do diretorio.
  [ -d "$_pc_ii_dir" ] || return 1

  return 0
}

# ---------------------------------------------------------------------------
# 2.4 Resolucao de skill (path-prepending)
# ---------------------------------------------------------------------------

# plugin_resolve_skill_dir <plugin_name> <skill>
# Retorna o diretorio da skill considerando path-prepending (FR-014, dec-006).
# Se llm_plugin == "claude": retorna sempre core (SC-003).
# Se plugin instalado tem a skill: retorna ~/.claude/cstk/plugins/<plugin>/skills/<skill>/
# Caso contrario: retorna ~/.claude/skills/<skill>/
plugin_resolve_skill_dir() {
  if [ "$#" -ne 2 ]; then
    printf 'plugin: plugin_resolve_skill_dir espera 2 args (plugin_name, skill)\n' >&2
    return 2
  fi
  _pc_rs_plugin=$1
  _pc_rs_skill=$2

  # SC-003: se plugin e "claude" (default), bypass completo — zero acesso ao store.
  if [ "$_pc_rs_plugin" = "claude" ]; then
    printf '%s/.claude/skills/%s\n' "$HOME" "$_pc_rs_skill"
    return 0
  fi

  # Path-prepending: consultar store do plugin primeiro.
  _pc_rs_plugin_skill="${HOME}/.claude/cstk/plugins/${_pc_rs_plugin}/skills/${_pc_rs_skill}"
  if [ -d "$_pc_rs_plugin_skill" ]; then
    printf '%s\n' "$_pc_rs_plugin_skill"
  else
    printf '%s/.claude/skills/%s\n' "$HOME" "$_pc_rs_skill"
  fi
}
