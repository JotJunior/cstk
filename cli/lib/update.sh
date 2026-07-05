# update.sh — comando `cstk update`.
#
# Ref: docs/specs/cstk-cli/contracts/cli-commands.md §update
#      docs/specs/cstk-cli/spec.md FR-003/008/009a/011/012
#      docs/specs/cstk-cli/quickstart.md Scenarios 2 (idempotencia SC-002), 3 (--force)
#
# Funcao exportada:
#   update_main "$@"   — entry point chamado por cli/cstk
#
# Sintaxe:
#   cstk update [SKILL...] [--scope global|project] [--force] [--keep] [--prune]
#               [--from URL] [--dry-run] [--yes] [--help]
#
# Politica de conflito (FR-008):
#   - Skill clean (hash atual == source_sha256 do manifest):
#     - Se release content == manifest content: zero writes (idempotencia SC-002)
#     - Se release diferente: atualiza
#   - Skill com edicao local (hash diverge):
#     - Sem flag: skip + adiciona a lista; exit 4 ao final
#     - --force: sobrescreve + atualiza manifest
#     - --keep: skip silencioso
#
# --prune: skills no manifest ausentes do catalog viram candidatas a remocao;
# pede confirmacao em TTY (skip com --yes).
#
# Exit codes:
#   0 sucesso
#   1 erro geral
#   2 uso incorreto (flags conflitantes, skill nao instalada, etc.)
#   3 lock detido
#   4 skip por edicao local sem --force/--keep (sinal pra CI; FR-008)

if [ -n "${_CSTK_UPDATE_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_UPDATE_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/compat.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/http.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/lock.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/tarball.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/hash.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/manifest.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/ui.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/hooks.sh"

_update_print_help() {
  cat >&2 <<'HELP'
cstk update — atualiza skills, commands e agents ja instalados.

USO:
  cstk update [SKILL...] [--scope global|project] [--force] [--keep] [--prune]
              [--from URL] [--dry-run] [--yes] [--interactive]

ARGS:
  SKILL...       Restringe update de skills a este subset (default: tudo no
                 manifest). Commands/agents sao sempre processados (sao
                 infraestrutura global do toolkit, sem cherry-pick).

OPCOES:
  --scope S      global ou project (default: global).
  --force        Sobrescreve skills/commands/agents com edicao local ou
                 third-party (FR-008). Caminho de recuperacao quando o
                 manifest dedicado por kind foi perdido em upgrades historicos.
  --keep         Mantem edicoes locais sem warning (FR-008).
  --prune        Remove skills do manifest ausentes do catalog (pede confirmacao).
  --from URL     URL do tarball (.tar.gz). Default: $CSTK_RELEASE_URL ou,
                 se ausente, consulta GitHub API /releases/latest.
  --dry-run      Mostra plano sem escrever.
  --yes          Pula confirmacao do --prune.
  --interactive  Seletor numerado em TTY (lista skills do manifest).

EXIT CODES:
  4  Pelo menos um artefato (skill/command/agent) foi pulado por edicao
     local sem --force/--keep.

EXEMPLOS:
  cstk update --from file:///tmp/release/cstk-v0.2.0.tar.gz
  cstk update --force               # sobrescreve edits locais e third-party
  cstk update --prune --yes         # limpa skills removidas do catalog
HELP
}

update_main() {
  _update_reset_state

  if ! _update_parse_args "$@"; then
    return 2
  fi

  if [ "$_update_help" = 1 ]; then
    _update_print_help
    return 0
  fi

  if [ "$_update_force" = 1 ] && [ "$_update_keep" = 1 ]; then
    log_error "update: --force e --keep sao mutuamente exclusivos"
    return 2
  fi

  if [ "$_update_interactive" = 1 ]; then
    if ! require_tty; then
      return 2
    fi
  fi

  if ! _update_resolve_scope_dir; then
    return 1
  fi
  if ! _update_resolve_urls; then
    return 1
  fi

  _update_manifest_path=$(manifest_default_path "$_update_scope") || {
    log_error "update: nao consegui resolver manifest path"
    return 1
  }

  # Manifest ausente = nada instalado nesse scope; nada a fazer.
  if [ ! -f "$_update_manifest_path" ]; then
    log_warn "update: manifest ausente em $_update_manifest_path (nada instalado em scope=$_update_scope)"
    _update_emit_summary
    return 0
  fi

  _update_staged=$(mktemp -d 2>/dev/null) || {
    log_error "update: mktemp -d falhou"
    return 1
  }
  trap '_update_cleanup' EXIT INT TERM

  if ! download_and_verify "$_update_tarball_url" "$_update_sha256_url" "$_update_staged"; then
    return 1
  fi
  if ! _update_locate_catalog; then
    return 1
  fi
  if ! _update_resolve_targets; then
    return 2
  fi

  if [ -z "$_update_targets" ] && [ "$_update_prune" != 1 ]; then
    # Manifest de skills vazio nao impede processar commands/agents (extras
    # tem manifest dedicado por kind, independente do principal).
    log_info "update: nenhuma skill a atualizar; verificando commands/agents..."
  fi

  # Lock (skip em dry-run; nada e escrito).
  if [ "$_update_dry_run" != 1 ]; then
    if ! acquire_lock "$_update_scope_dir/.cstk.lock"; then
      return 3
    fi
    trap '_update_cleanup' EXIT INT TERM
  fi

  _update_now=$(iso_now_utc)

  _update_old_ifs=$IFS
  IFS='
'
  for _update_skill in $_update_targets; do
    IFS=$_update_old_ifs
    _update_process_skill "$_update_skill" || {
      log_error "update: falha processando $_update_skill"
      return 1
    }
    IFS='
'
  done
  IFS=$_update_old_ifs

  # enforced-guards task 2.5.2 (Decision 9): update.sh hoje nao tocava hooks
  # em nenhum caso (achado da research.md) — reprovisiona o guard-hook de
  # US1 quando a skill agente-00c-runtime esta entre os alvos desta
  # atualizacao, para que "atualizar o toolkit" tambem cubra FR-004/SC-006.
  _update_apply_guard_hooks_if_needed

  if [ "$_update_prune" = 1 ]; then
    _update_do_prune || return 1
  fi

  # Espelha install: atualiza commands/agents (.md soltos em catalog/<kind>/).
  # Sao infraestrutura global do toolkit, processados sempre — sem filtro de
  # profile ou cherry-pick de skills.
  _update_apply_extra_kinds || return 1

  _update_emit_summary

  if [ "$_update_count_skipped_edits" -gt 0 ] \
     || [ "$_update_count_commands_skipped_edits" -gt 0 ] \
     || [ "$_update_count_agents_skipped_edits" -gt 0 ]; then
    return 4
  fi
  return 0
}

_update_reset_state() {
  _update_help=0
  _update_dry_run=0
  _update_yes=0
  _update_force=0
  _update_keep=0
  _update_prune=0
  _update_interactive=0
  _update_scope=global
  _update_explicit_skills=""
  _update_from=""
  _update_tarball_url=""
  _update_sha256_url=""
  _update_scope_dir=""
  _update_staged=""
  _update_catalog_dir=""
  _update_release_version=""
  _update_manifest_path=""
  _update_targets=""
  _update_now=""
  _update_orphans=""
  _update_guard_hook_state=""
  _update_skipped_list=""
  _update_count_updated=0
  _update_count_uptodate=0
  _update_count_kept=0
  _update_count_skipped_edits=0
  _update_count_pruned=0
  _update_count_orphan=0
  _update_count_missing_disk=0
  _update_count_missing_manifest=0
  _update_count_commands_installed=0
  _update_count_commands_updated=0
  _update_count_commands_uptodate=0
  _update_count_commands_kept=0
  _update_count_commands_skipped_edits=0
  _update_count_commands_preserved=0
  _update_count_agents_installed=0
  _update_count_agents_updated=0
  _update_count_agents_uptodate=0
  _update_count_agents_kept=0
  _update_count_agents_skipped_edits=0
  _update_count_agents_preserved=0
}

_update_cleanup() {
  if [ -n "${_CSTK_LOCK_DIR:-}" ]; then
    release_lock 2>/dev/null || :
  fi
  if [ -n "${_update_staged:-}" ] && [ -d "$_update_staged" ]; then
    rm -rf -- "$_update_staged" 2>/dev/null || :
  fi
}

_update_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) _update_help=1; shift ;;
      --dry-run) _update_dry_run=1; shift ;;
      --yes|-y) _update_yes=1; shift ;;
      --force) _update_force=1; shift ;;
      --keep) _update_keep=1; shift ;;
      --prune) _update_prune=1; shift ;;
      --interactive|-i) _update_interactive=1; shift ;;
      --scope)
        if [ "$#" -lt 2 ]; then
          log_error "update: --scope exige valor (global|project)"
          return 1
        fi
        case "$2" in
          global|project) _update_scope=$2 ;;
          *) log_error "update: --scope invalido: $2"; return 1 ;;
        esac
        shift 2
        ;;
      --scope=*)
        _update_scope=${1#--scope=}
        case "$_update_scope" in
          global|project) ;;
          *) log_error "update: --scope invalido: $_update_scope"; return 1 ;;
        esac
        shift
        ;;
      --from)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          log_error "update: --from exige valor (URL)"
          return 1
        fi
        _update_from=$2
        shift 2
        ;;
      --from=*)
        _update_from=${1#--from=}
        shift
        ;;
      --) shift; break ;;
      -*)
        log_error "update: flag desconhecida: $1"
        return 1
        ;;
      *)
        if [ -z "$_update_explicit_skills" ]; then
          _update_explicit_skills=$1
        else
          _update_explicit_skills="$_update_explicit_skills
$1"
        fi
        shift
        ;;
    esac
  done
  while [ "$#" -gt 0 ]; do
    if [ -z "$_update_explicit_skills" ]; then
      _update_explicit_skills=$1
    else
      _update_explicit_skills="$_update_explicit_skills
$1"
    fi
    shift
  done
  return 0
}

_update_resolve_scope_dir() {
  case "$_update_scope" in
    global) _update_scope_dir="${HOME:?HOME nao setado}/.claude/skills" ;;
    project) _update_scope_dir="./.claude/skills" ;;
    *) log_error "update: scope invalido (bug interno)"; return 1 ;;
  esac
  return 0
}

# _update_resolve_urls: define _update_tarball_url + _update_sha256_url.
# Mesma prioridade de install: --from > $CSTK_RELEASE_URL > API GitHub.
_update_resolve_urls() {
  if [ -z "$_update_from" ]; then
    _update_from=${CSTK_RELEASE_URL:-}
  fi

  if [ -z "$_update_from" ]; then
    _update_repo=${CSTK_REPO:-JotJunior/cstk}
    _update_api="https://api.github.com/repos/$_update_repo/releases/latest"
    log_info "update: consultando ultima release de $_update_repo via API GitHub..."
    _update_api_resp=$(curl -fsSL --connect-timeout 10 --max-time 60 \
      "$_update_api" 2>/dev/null) || {
      log_error "update: falha ao consultar $_update_api (offline?)"
      log_error "        use --from <url> ou \$CSTK_RELEASE_URL como alternativa"
      return 1
    }
    _update_tag=$(printf '%s\n' "$_update_api_resp" \
      | grep -o '"tag_name":[[:space:]]*"[^"]*"' \
      | head -n 1 \
      | sed 's/.*"\([^"]*\)"$/\1/')
    if [ -z "$_update_tag" ]; then
      log_error "update: tag_name nao encontrado em $_update_api"
      return 1
    fi
    _update_tag_bare=${_update_tag#v}
    _update_tarball_url="https://github.com/$_update_repo/releases/download/$_update_tag/cstk-$_update_tag_bare.tar.gz"
    _update_sha256_url="${_update_tarball_url}.sha256"
    log_info "update: ultima release: $_update_tag"
    return 0
  fi

  case "$_update_from" in
    http://*|https://*|file://*)
      _update_tarball_url=$_update_from
      _update_sha256_url="${_update_from}.sha256"
      ;;
    *)
      log_error "update: --from precisa ser URL: $_update_from"
      log_error "        para usar a ultima release automaticamente, omita --from"
      return 1
      ;;
  esac
  return 0
}

_update_locate_catalog() {
  _update_catalog_dir=$(find "$_update_staged" -maxdepth 3 -type d -name catalog 2>/dev/null | head -1)
  if [ -z "$_update_catalog_dir" ] || [ ! -d "$_update_catalog_dir" ]; then
    log_error "update: catalog/ nao encontrado no tarball"
    return 1
  fi
  if [ ! -f "$_update_catalog_dir/VERSION" ]; then
    log_error "update: $_update_catalog_dir/VERSION ausente"
    return 1
  fi
  _update_release_version=$(head -n 1 -- "$_update_catalog_dir/VERSION" | tr -d '[:space:]')
  if [ -z "$_update_release_version" ]; then
    log_error "update: VERSION vazio"
    return 1
  fi
  return 0
}

# _update_resolve_targets: define lista de skills a processar.
# Sem args = todas do manifest. Com args = subset; valida que cada uma esta
# instalada (senao exit 2 com lista clara). Com --interactive, abre seletor
# numerado sobre as skills do manifest.
_update_resolve_targets() {
  _all=$(read_manifest "$_update_manifest_path" | awk -F'\t' 'NF>=1 {print $1}')

  if [ "$_update_interactive" = 1 ]; then
    if [ -z "$_all" ]; then
      log_warn "update --interactive: manifest vazio em $_update_manifest_path"
      _update_targets=""
      return 0
    fi
    _urt_resolved=$(ui_select_interactive "" "$_all" update) || return 1
    _update_targets=$(printf '%s\n' "$_urt_resolved" | awk 'NF>0' | sort -u)
    return 0
  fi

  if [ -z "$_update_explicit_skills" ]; then
    _update_targets=$_all
    return 0
  fi

  _missing=""
  _urt_old_ifs=$IFS
  IFS='
'
  for _esk in $_update_explicit_skills; do
    IFS=$_urt_old_ifs
    if ! printf '%s\n' "$_all" | grep -Fxq -- "$_esk"; then
      if [ -z "$_missing" ]; then
        _missing=$_esk
      else
        _missing="$_missing $_esk"
      fi
    fi
    IFS='
'
  done
  IFS=$_urt_old_ifs

  if [ -n "$_missing" ]; then
    log_error "update: skill(s) nao instalada(s) no scope $_update_scope: $_missing"
    return 1
  fi
  _update_targets=$_update_explicit_skills
  return 0
}

_update_find_skill_src() {
  _ufs_skill=$1
  if [ -d "$_update_catalog_dir/skills/$_ufs_skill" ]; then
    printf '%s\n' "$_update_catalog_dir/skills/$_ufs_skill"
    return 0
  fi
  if [ -d "$_update_catalog_dir/language" ]; then
    for _ufs_lang in "$_update_catalog_dir/language"/*; do
      [ -d "$_ufs_lang/skills/$_ufs_skill" ] || continue
      printf '%s\n' "$_ufs_lang/skills/$_ufs_skill"
      return 0
    done
  fi
  return 1
}

_update_process_skill() {
  _ups_skill=$1

  _entry=$(lookup_entry "$_update_manifest_path" "$_ups_skill") || {
    # Acontece se manifest mudou entre resolve_targets e este loop (race).
    log_warn "update: skill nao esta no manifest: $_ups_skill"
    _update_count_missing_manifest=$((_update_count_missing_manifest + 1))
    return 0
  }
  _stored_sha=$(printf '%s\n' "$_entry" | awk -F'\t' '{print $3}')

  _ups_dst="$_update_scope_dir/$_ups_skill"
  if [ ! -d "$_ups_dst" ]; then
    log_warn "update: skill no manifest mas dir ausente: $_ups_skill (sugira cstk doctor)"
    _update_count_missing_disk=$((_update_count_missing_disk + 1))
    return 0
  fi

  _ups_src=$(_update_find_skill_src "$_ups_skill") || _ups_src=""
  if [ -z "$_ups_src" ]; then
    # Skill removida do catalog -> candidata a prune
    _update_count_orphan=$((_update_count_orphan + 1))
    if [ "$_update_prune" = 1 ]; then
      _update_orphans="$_update_orphans
$_ups_skill"
    else
      log_warn "update: skill removida do catalog: $_ups_skill (use --prune para remover)"
    fi
    return 0
  fi

  _current_hash=$(hash_dir "$_ups_dst") || return 1
  _release_hash=$(hash_dir "$_ups_src") || return 1

  if [ "$_current_hash" = "$_stored_sha" ]; then
    # Clean (sem edit local). Compara com release.
    if [ "$_release_hash" = "$_stored_sha" ]; then
      # Idempotente — zero writes (SC-002). Manifest fica intocado (mtime
      # preservado).
      _update_count_uptodate=$((_update_count_uptodate + 1))
      return 0
    fi
    _update_apply "$_ups_skill" "$_ups_src" "$_ups_dst" "$_release_hash" updated
    return $?
  fi

  # Edicao local detectada
  if [ "$_update_force" = 1 ]; then
    _update_apply "$_ups_skill" "$_ups_src" "$_ups_dst" "$_release_hash" updated
    return $?
  fi
  if [ "$_update_keep" = 1 ]; then
    _update_count_kept=$((_update_count_kept + 1))
    return 0
  fi
  log_warn "update: edicao local em $_ups_skill (use --force para sobrescrever, --keep para silenciar)"
  _update_count_skipped_edits=$((_update_count_skipped_edits + 1))
  _update_skipped_list="$_update_skipped_list
$_ups_skill"
  return 0
}

_update_apply() {
  _ua_skill=$1
  _ua_src=$2
  _ua_dst=$3
  _ua_new_sha=$4
  _ua_action=$5

  if [ "$_update_dry_run" = 1 ]; then
    log_info "[dry-run] $_ua_action: $_ua_skill"
  else
    rm -rf -- "$_ua_dst" 2>/dev/null || :
    if ! cp -R -- "$_ua_src" "$_ua_dst"; then
      log_error "update: cp -R falhou para $_ua_skill"
      return 1
    fi
    if ! upsert_entry "$_update_manifest_path" "$_ua_skill" \
                       "$_update_release_version" "$_ua_new_sha" "$_update_now"; then
      log_error "update: upsert manifest falhou para $_ua_skill"
      return 1
    fi
  fi
  case "$_ua_action" in
    updated) _update_count_updated=$((_update_count_updated + 1)) ;;
  esac
  return 0
}

# _update_apply_guard_hooks_if_needed: reprovisiona o hook PreToolUse/Bash
# de enforced-guards (US1) quando a skill agente-00c-runtime esta entre os
# alvos desta atualizacao (Decision 9 — update.sh historicamente nao tocava
# hooks; achado da research.md. FR-004/SC-006 exige que "atualizar" tambem
# (re)provisione, nao so a instalacao inicial).
#
# Escopo project apenas — --scope global pula (mesma regra de
# _install_apply_hooks_if_needed/FR-009c/Decision 9).
#
# Delega inteiramente a apply_guard_hooks() (cli/lib/hooks.sh), nenhum
# mecanismo de merge/paste proprio.
_update_apply_guard_hooks_if_needed() {
  _update_guard_hook_state=""

  if [ "$_update_scope" = global ]; then
    if printf '%s\n' "$_update_targets" | grep -Fxq -- "agente-00c-runtime"; then
      log_warn "update: guard-hooks (enforced-guards) omitidos em scope=global (FR-009c)"
      _update_guard_hook_state="omitted"
    fi
    return 0
  fi

  printf '%s\n' "$_update_targets" | grep -Fxq -- "agente-00c-runtime" || return 0

  _ugh_claude_root="${_update_scope_dir%/skills}"
  _ugh_src_dir="$_update_catalog_dir/skills/agente-00c-runtime/hooks"
  _update_guard_hook_state=$(apply_guard_hooks "$_ugh_src_dir" "$_ugh_claude_root" "$_update_dry_run")
  return 0
}

_update_do_prune() {
  if [ -z "$_update_orphans" ]; then
    return 0
  fi
  _orphan_list=$(printf '%s\n' "$_update_orphans" | awk 'NF>0' | sort -u)
  _orphan_n=$(printf '%s\n' "$_orphan_list" | wc -l | awk '{print $1}')

  if [ "$_update_yes" != 1 ] && [ -t 0 ]; then
    log_info "update --prune: $_orphan_n skill(s) ausentes do catalog:"
    printf '%s\n' "$_orphan_list" | sed 's/^/  - /' >&2
    printf 'Confirmar remocao? [y/N] ' >&2
    read _ans 2>/dev/null || _ans=""
    case "$_ans" in
      y|Y|yes|YES|s|S|sim|SIM) ;;
      *)
        log_warn "update --prune: cancelado pelo usuario"
        return 0
        ;;
    esac
  fi

  _udp_old_ifs=$IFS
  IFS='
'
  for _orphan in $_orphan_list; do
    IFS=$_udp_old_ifs
    if [ "$_update_dry_run" = 1 ]; then
      log_info "[dry-run] prune: $_orphan"
    else
      rm -rf -- "$_update_scope_dir/$_orphan" 2>/dev/null || :
      remove_entry "$_update_manifest_path" "$_orphan" || return 1
    fi
    _update_count_pruned=$((_update_count_pruned + 1))
    IFS='
'
  done
  IFS=$_udp_old_ifs
  return 0
}

# _update_apply_extra_kinds: atualiza commands e agents (.md soltos).
#
# Espelha _install_apply_extra_kinds em install.sh, mas com semantica de
# update: detecta edits locais, respeita --force/--keep, reporta uptodate
# quando release_hash == stored_sha (idempotencia SC-002).
_update_apply_extra_kinds() {
  for _uaek_kind in commands agents; do
    _update_apply_kind "$_uaek_kind" || return 1
  done
  return 0
}

# _update_apply_kind <kind>: itera catalog/<kind>/*.md e processa cada um.
#
# Ramos (espelha _update_process_skill com adicao do ramo "preserve
# third-party" especifico de extra_kinds):
#   - nao existe em disco                              -> install fresh
#   - existe, no manifest, clean, release==manifest    -> uptodate (zero writes)
#   - existe, no manifest, clean, release!=manifest    -> updated
#   - existe, no manifest, edit local + --force        -> updated (overwrite)
#   - existe, no manifest, edit local + --keep         -> kept
#   - existe, no manifest, edit local (default)        -> skipped_edits + exit 4
#   - existe, fora do manifest + --force               -> updated (overwrite third-party)
#   - existe, fora do manifest (default)               -> preserved (warn)
_update_apply_kind() {
  _uak_kind=$1
  _uak_src_dir="$_update_catalog_dir/$_uak_kind"
  if [ ! -d "$_uak_src_dir" ]; then
    return 0
  fi

  # dest = scope_dir/../<kind>  (ex: ~/.claude/skills/.. = ~/.claude/, depois /commands)
  case "$_update_scope" in
    global)  _uak_dst_dir="${HOME:?HOME nao setado}/.claude/$_uak_kind" ;;
    project) _uak_dst_dir="./.claude/$_uak_kind" ;;
    *)
      log_error "update: scope invalido em apply_kind (bug): $_update_scope"
      return 1
      ;;
  esac

  _uak_manifest=$(manifest_default_path "$_update_scope" "$_uak_kind") || {
    log_error "update: manifest_default_path falhou para kind=$_uak_kind"
    return 1
  }

  for _uak_src in "$_uak_src_dir"/*.md; do
    [ -f "$_uak_src" ] || continue
    _uak_name=$(basename -- "$_uak_src" .md)
    _uak_dst="$_uak_dst_dir/$_uak_name.md"
    _uak_release_hash=$(hash_file "$_uak_src") || return 1

    # Ramo 1: nao existe em disco -> install fresh
    if [ ! -e "$_uak_dst" ]; then
      _update_apply_kind_write "$_uak_kind" "$_uak_name" \
        "$_uak_src" "$_uak_dst" "$_uak_dst_dir" "$_uak_manifest" \
        "$_uak_release_hash" installed || return 1
      continue
    fi

    _uak_current_hash=$(hash_file "$_uak_dst") || return 1

    if lookup_entry "$_uak_manifest" "$_uak_name" >/dev/null 2>&1; then
      _uak_entry=$(lookup_entry "$_uak_manifest" "$_uak_name")
      _uak_stored_sha=$(printf '%s\n' "$_uak_entry" | awk -F'\t' '{print $3}')

      if [ "$_uak_current_hash" = "$_uak_stored_sha" ]; then
        # Clean (sem edit local). Compara com release.
        if [ "$_uak_release_hash" = "$_uak_stored_sha" ]; then
          # Idempotente — zero writes
          _update_bump_extra_counter "$_uak_kind" uptodate
          continue
        fi
        _update_apply_kind_write "$_uak_kind" "$_uak_name" \
          "$_uak_src" "$_uak_dst" "$_uak_dst_dir" "$_uak_manifest" \
          "$_uak_release_hash" updated || return 1
        continue
      fi

      # Edicao local detectada
      if [ "$_update_force" = 1 ]; then
        _update_apply_kind_write "$_uak_kind" "$_uak_name" \
          "$_uak_src" "$_uak_dst" "$_uak_dst_dir" "$_uak_manifest" \
          "$_uak_release_hash" updated || return 1
        continue
      fi
      if [ "$_update_keep" = 1 ]; then
        _update_bump_extra_counter "$_uak_kind" kept
        continue
      fi
      log_warn "update: edicao local em $_uak_kind/$_uak_name (use --force para sobrescrever, --keep para silenciar)"
      _update_bump_extra_counter "$_uak_kind" skipped_edits
      continue
    fi

    # Sem manifest entry -> third-party. Sobrescreve so com --force.
    if [ "$_update_force" = 1 ]; then
      _update_apply_kind_write "$_uak_kind" "$_uak_name" \
        "$_uak_src" "$_uak_dst" "$_uak_dst_dir" "$_uak_manifest" \
        "$_uak_release_hash" updated || return 1
      continue
    fi
    log_warn "update: preservando $_uak_kind/$_uak_name (fora do manifest; use --force para sobrescrever)"
    _update_bump_extra_counter "$_uak_kind" preserved
  done

  return 0
}

# _update_apply_kind_write <kind> <name> <src> <dst> <dst_dir> <manifest> <new_sha> <counter_action>
# Encapsula a escrita (cp + upsert manifest). Em dry-run, apenas reporta.
_update_apply_kind_write() {
  _uakw_kind=$1
  _uakw_name=$2
  _uakw_src=$3
  _uakw_dst=$4
  _uakw_dst_dir=$5
  _uakw_manifest=$6
  _uakw_new_sha=$7
  _uakw_action=$8

  if [ "$_update_dry_run" = 1 ]; then
    log_info "[dry-run] $_uakw_kind $_uakw_action: $_uakw_name"
    _update_bump_extra_counter "$_uakw_kind" "$_uakw_action"
    return 0
  fi

  if ! mkdir -p -- "$_uakw_dst_dir" 2>/dev/null; then
    log_error "update: nao foi possivel criar $_uakw_dst_dir"
    return 1
  fi
  if ! cp -- "$_uakw_src" "$_uakw_dst"; then
    log_error "update: cp falhou para $_uakw_kind/$_uakw_name"
    return 1
  fi
  if ! upsert_entry "$_uakw_manifest" "$_uakw_name" \
                    "$_update_release_version" "$_uakw_new_sha" "$_update_now"; then
    log_error "update: upsert manifest falhou para $_uakw_kind/$_uakw_name"
    return 1
  fi
  _update_bump_extra_counter "$_uakw_kind" "$_uakw_action"
  return 0
}

# _update_bump_extra_counter <kind> <action>
# Actions: installed | updated | uptodate | kept | skipped_edits | preserved
_update_bump_extra_counter() {
  case "$1.$2" in
    commands.installed)      _update_count_commands_installed=$((_update_count_commands_installed + 1)) ;;
    commands.updated)        _update_count_commands_updated=$((_update_count_commands_updated + 1)) ;;
    commands.uptodate)       _update_count_commands_uptodate=$((_update_count_commands_uptodate + 1)) ;;
    commands.kept)           _update_count_commands_kept=$((_update_count_commands_kept + 1)) ;;
    commands.skipped_edits)  _update_count_commands_skipped_edits=$((_update_count_commands_skipped_edits + 1)) ;;
    commands.preserved)      _update_count_commands_preserved=$((_update_count_commands_preserved + 1)) ;;
    agents.installed)        _update_count_agents_installed=$((_update_count_agents_installed + 1)) ;;
    agents.updated)          _update_count_agents_updated=$((_update_count_agents_updated + 1)) ;;
    agents.uptodate)         _update_count_agents_uptodate=$((_update_count_agents_uptodate + 1)) ;;
    agents.kept)             _update_count_agents_kept=$((_update_count_agents_kept + 1)) ;;
    agents.skipped_edits)    _update_count_agents_skipped_edits=$((_update_count_agents_skipped_edits + 1)) ;;
    agents.preserved)        _update_count_agents_preserved=$((_update_count_agents_preserved + 1)) ;;
  esac
}

_update_emit_summary() {
  _ues_prefix=""
  if [ "$_update_dry_run" = 1 ]; then
    _ues_prefix="(dry-run) "
  fi
  {
    printf '==> %scstk update summary\n' "$_ues_prefix"
    printf '  updated: %d\n' "$_update_count_updated"
    printf '  already up-to-date: %d\n' "$_update_count_uptodate"
    printf '  kept (--keep): %d\n' "$_update_count_kept"
    printf '  skipped (local edits): %d\n' "$_update_count_skipped_edits"
    if [ "$_update_count_skipped_edits" -gt 0 ]; then
      printf '%s\n' "$_update_skipped_list" | awk 'NF>0' | sed 's/^/    - /' >&2
    fi
    printf '  removed (pruned): %d\n' "$_update_count_pruned"
    printf '  orphan (in manifest, not in catalog): %d\n' "$_update_count_orphan"
    printf '  scope: %s\n' "$_update_scope"
    printf '  toolkit version: %s\n' "${_update_release_version:-?}"
    if [ -n "$_update_guard_hook_state" ]; then
      printf '  guard-hooks: %s\n' "$_update_guard_hook_state"
    fi
    _ues_cmd_total=$((_update_count_commands_installed + _update_count_commands_updated + _update_count_commands_uptodate + _update_count_commands_kept + _update_count_commands_skipped_edits + _update_count_commands_preserved))
    if [ "$_ues_cmd_total" -gt 0 ]; then
      printf '  commands: installed=%d updated=%d uptodate=%d kept=%d skipped=%d preserved=%d\n' \
        "$_update_count_commands_installed" \
        "$_update_count_commands_updated" \
        "$_update_count_commands_uptodate" \
        "$_update_count_commands_kept" \
        "$_update_count_commands_skipped_edits" \
        "$_update_count_commands_preserved"
    fi
    _ues_ag_total=$((_update_count_agents_installed + _update_count_agents_updated + _update_count_agents_uptodate + _update_count_agents_kept + _update_count_agents_skipped_edits + _update_count_agents_preserved))
    if [ "$_ues_ag_total" -gt 0 ]; then
      printf '  agents: installed=%d updated=%d uptodate=%d kept=%d skipped=%d preserved=%d\n' \
        "$_update_count_agents_installed" \
        "$_update_count_agents_updated" \
        "$_update_count_agents_uptodate" \
        "$_update_count_agents_kept" \
        "$_update_count_agents_skipped_edits" \
        "$_update_count_agents_preserved"
    fi
    if [ "$_update_count_skipped_edits" -gt 0 ] \
       || [ "$_update_count_commands_skipped_edits" -gt 0 ] \
       || [ "$_update_count_agents_skipped_edits" -gt 0 ]; then
      printf '  next: cstk update --force  (to overwrite edited skills/commands/agents)\n'
    fi
    if [ "$_update_count_commands_preserved" -gt 0 ] \
       || [ "$_update_count_agents_preserved" -gt 0 ]; then
      printf '  note: %d third-party file(s) preserved; use --force to overwrite\n' \
        "$((_update_count_commands_preserved + _update_count_agents_preserved))"
    fi
  } >&2
}
