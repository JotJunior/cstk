# install.sh — comando `cstk install`.
#
# Ref: docs/specs/cstk-cli/contracts/cli-commands.md §install
#      docs/specs/cstk-cli/spec.md FR-001/002/007/009/011/012
#      docs/specs/cstk-cli/quickstart.md Scenario 1
#
# Funcao exportada:
#   install_main "$@"   — entry point chamado por cli/cstk
#
# Sintaxe:
#   cstk install [SKILL...] [--profile NAME] [--scope global|project]
#                [--from URL] [--dry-run] [--yes] [--interactive] [--help]
#
# Resolucao de URL (--from):
#   - URL absoluta (https:// ou file://) -> usada como tarball_url;
#     sha256_url e tarball_url + ".sha256". http:// e REJEITADO (MITM
#     anularia o checksum de mesma origem).
#   - Sem --from: cai em $CSTK_RELEASE_URL (escape hatch para fixtures de teste);
#     se ausente, consulta GitHub API /releases/latest e monta a URL do asset
#     conforme convencao de naming do build (cstk-<bare-version>.tar.gz).
#     $CSTK_REPO override permite apontar para um fork.
#
# Hooks de language-* (FR-009b/c/d): integracao em FASE 7.2; install desta
# fase apenas copia skills.
#
# Modo interativo (FR-009): integracao em FASE 8.1.5; install aceita a flag
# mas reporta nao-implementado com exit 2 ate la.
#
# Exit codes (POSIX + contract):
#   0 sucesso (ou dry-run completo)
#   1 erro geral (rede, filesystem, checksum, catalog malformado)
#   2 uso incorreto (flag invalida, profile/skill desconhecido, --interactive)
#   3 lock detido por outro processo
#
# POSIX sh + tar/curl/find/cp. Sourceia common, compat, http, lock, tarball,
# hash, manifest, profiles do mesmo cli/lib/.

if [ -n "${_CSTK_INSTALL_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_INSTALL_LOADED=1

# shellcheck source=/dev/null
. "${CSTK_LIB:?CSTK_LIB must be set}/common.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/compat.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/http.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/trusted-hosts.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/lock.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/tarball.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/hash.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/manifest.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/profiles.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/hooks.sh"
# shellcheck source=/dev/null
. "${CSTK_LIB}/ui.sh"

_install_print_help() {
  cat >&2 <<'HELP'
cstk install — instala skills do toolkit em escopo global ou de projeto.

USO:
  cstk install [SKILL...] [--profile NAME] [--scope global|project]
               [--from URL] [--dry-run] [--yes] [--interactive]

ARGS:
  SKILL...       Cherry-pick por nome (uniao com --profile, se ambos).

OPCOES:
  --profile N    Perfil declarado no catalog. Default: sdd.
  --scope S      global (~/.claude/skills/) ou project (./.claude/skills/).
                 Default: global.
  --from URL     URL do tarball (.tar.gz). Default: $CSTK_RELEASE_URL ou,
                 se ausente, consulta GitHub API /releases/latest. $CSTK_REPO
                 override aponta para um fork (default JotJunior/cstk).
  --dry-run      Mostra plano sem escrever nada.
  --yes          Pula confirmacoes interativas.
  --interactive  Seletor numerado em TTY (FASE 8 — nao implementado ainda).
  --help         Imprime esta mensagem.

PROFILES DISPONIVEIS:
  sdd            (default) Pipeline Spec-Driven Development sequencial:
                 briefing, constitution, specify, clarify, plan, checklist,
                 create-tasks, analyze, execute-task, review-task.
  complementary  Skills de uso pontual (sem sequencia): advisor, bugfix,
                 apply-insights, owasp-security,
                 validate-documentation, validate-docs-rendered.
  all            Todas as skills do catalog (uniao de sdd + complementary
                 + qualquer skill nova em plugins/cstk/skills/).

EXEMPLOS:
  cstk install                                # profile sdd (default)
  cstk install --profile complementary        # so as complementares
  cstk install --profile all                  # tudo
  cstk install advisor bugfix                 # cherry-pick por nome
  cstk install --from file:///tmp/release/cstk-v0.1.0.tar.gz
  cstk install specify plan --profile sdd --dry-run
  cstk install --scope project --from URL
HELP
}

# install_main: entry point. Argumentos parseados e fluxo orquestrado em
# fases (parse -> URL -> stage -> selecao -> apply -> summary).
install_main() {
  _install_reset_state

  if ! _install_parse_args "$@"; then
    return 2
  fi

  if [ "$_install_help" = 1 ]; then
    _install_print_help
    return 0
  fi

  if [ "$_install_interactive" = 1 ]; then
    if ! require_tty; then
      return 2
    fi
  fi

  if ! _install_resolve_scope_dir; then
    return 1
  fi

  if ! _install_resolve_urls; then
    return 1
  fi

  if ! _install_validate_project_scope; then
    return 1
  fi

  # Stage download em tempdir privado. Trap garante cleanup mesmo em interrupt.
  _install_staged=$(mktemp -d 2>/dev/null) || {
    log_error "install: mktemp -d falhou"
    return 1
  }
  trap '_install_cleanup' EXIT INT TERM

  if ! download_and_verify "$_install_tarball_url" "$_install_sha256_url" "$_install_staged"; then
    return 1
  fi

  if ! _install_locate_catalog; then
    return 1
  fi

  if [ "$_install_interactive" = 1 ]; then
    if ! _install_resolve_selection_interactive; then
      return 2
    fi
  else
    if ! _install_resolve_selection; then
      return 2
    fi
  fi

  if [ -z "$_install_selection" ]; then
    log_warn "install: nenhuma skill selecionada"
    _install_emit_summary
    return 0
  fi

  # Lock + scope dir creation (skip em dry-run; nada e escrito).
  if [ "$_install_dry_run" != 1 ]; then
    if ! mkdir -p -- "$_install_scope_dir" 2>/dev/null; then
      log_error "install: nao foi possivel criar $_install_scope_dir"
      return 1
    fi
    if ! acquire_lock "$_install_scope_dir/.cstk.lock"; then
      return 3
    fi
    # acquire_lock substitui o trap; re-instala combinacao (release + cleanup).
    trap '_install_cleanup' EXIT INT TERM
  fi

  _install_now=$(iso_now_utc)
  _install_manifest_path=$(manifest_default_path "$_install_scope") || {
    log_error "install: nao consegui resolver manifest path"
    return 1
  }

  # Itera selecao. for-loop com IFS=newline para nao perder counters em
  # subshell (pipe-based while-read teria esse bug).
  _install_old_ifs=$IFS
  IFS='
'
  for _install_skill in $_install_selection; do
    IFS=$_install_old_ifs
    _install_process_skill "$_install_skill" || {
      log_error "install: falha ao processar $_install_skill"
      return 1
    }
    IFS='
'
  done
  IFS=$_install_old_ifs

  # FASE 7.2: integracao de hooks language-* (FR-009b/c/d)
  _install_apply_hooks_if_needed

  # agente-00c FASE 1.2: distribui catalog/commands/ e catalog/agents/ alem
  # de skills. Sao .md soltos (1 arquivo = 1 artefato), instalados sempre
  # (sem filtro de profile) porque sao infraestrutura global do toolkit.
  _install_apply_extra_kinds

  # state-mcp-server: fonte de build do servidor MCP (catalog/mcp/state-server
  # -> ~/.claude/mcp/state-server, caminho 3 de _mcp_context_dir em
  # cli/lib/mcp.sh). Sem isto, `cstk mcp start` em ambiente instalado nunca
  # acha o contexto de build e degrada sempre para bash-fallback.
  _install_apply_mcp_server

  _install_emit_summary
  return 0
}

# _install_reset_state: zera variaveis globais entre invocacoes (testes
# podem chamar install_main multiplas vezes via dot-source).
_install_reset_state() {
  _install_help=0
  _install_interactive=0
  _install_dry_run=0
  _install_yes=0
  _install_scope=global
  _install_profile=""
  _install_explicit_skills=""
  _install_from=""
  _install_tarball_url=""
  _install_sha256_url=""
  _install_scope_dir=""
  _install_staged=""
  _install_catalog_dir=""
  _install_release_version=""
  _install_selection=""
  _install_manifest_path=""
  _install_now=""
  _install_hook_state=""
  _install_guard_hook_state=""
  _install_count_installed=0
  _install_count_updated=0
  _install_count_preserved=0
  _install_count_missing=0
  _install_count_commands_installed=0
  _install_count_commands_updated=0
  _install_count_commands_preserved=0
  _install_count_agents_installed=0
  _install_count_agents_updated=0
  _install_count_agents_preserved=0
}

_install_cleanup() {
  if [ -n "${_CSTK_LOCK_DIR:-}" ]; then
    release_lock 2>/dev/null || :
  fi
  if [ -n "${_install_staged:-}" ] && [ -d "$_install_staged" ]; then
    rm -rf -- "$_install_staged" 2>/dev/null || :
  fi
}

# _install_parse_args: traduz argv em variaveis _install_*. Aceita flags em
# qualquer ordem; --profile/--scope/--from exigem valor; demais sao booleanas.
_install_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) _install_help=1; shift ;;
      --interactive|-i) _install_interactive=1; shift ;;
      --dry-run) _install_dry_run=1; shift ;;
      --yes|-y) _install_yes=1; shift ;;
      --profile)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          log_error "install: --profile exige valor"
          return 1
        fi
        _install_profile=$2
        shift 2
        ;;
      --profile=*)
        _install_profile=${1#--profile=}
        if [ -z "$_install_profile" ]; then
          log_error "install: --profile= sem valor"
          return 1
        fi
        shift
        ;;
      --scope)
        if [ "$#" -lt 2 ]; then
          log_error "install: --scope exige valor (global|project)"
          return 1
        fi
        case "$2" in
          global|project) _install_scope=$2 ;;
          *) log_error "install: --scope invalido: $2 (use global|project)"; return 1 ;;
        esac
        shift 2
        ;;
      --scope=*)
        _install_scope=${1#--scope=}
        case "$_install_scope" in
          global|project) ;;
          *) log_error "install: --scope invalido: $_install_scope"; return 1 ;;
        esac
        shift
        ;;
      --from)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          log_error "install: --from exige valor (URL ou tag)"
          return 1
        fi
        _install_from=$2
        shift 2
        ;;
      --from=*)
        _install_from=${1#--from=}
        shift
        ;;
      --) shift; break ;;
      -*)
        log_error "install: flag desconhecida: $1"
        return 1
        ;;
      *)
        # SKILL cherry-pick. Concatena com newline para sort -u depois.
        if [ -z "$_install_explicit_skills" ]; then
          _install_explicit_skills=$1
        else
          _install_explicit_skills="$_install_explicit_skills
$1"
        fi
        shift
        ;;
    esac
  done

  # Posicionais apos `--`.
  while [ "$#" -gt 0 ]; do
    if [ -z "$_install_explicit_skills" ]; then
      _install_explicit_skills=$1
    else
      _install_explicit_skills="$_install_explicit_skills
$1"
    fi
    shift
  done

  # Default profile = sdd quando nada e informado (FR-009).
  if [ -z "$_install_profile" ] && [ -z "$_install_explicit_skills" ]; then
    _install_profile=sdd
  fi
  return 0
}

# _install_resolve_scope_dir: traduz scope -> path.
_install_resolve_scope_dir() {
  case "$_install_scope" in
    global)
      _install_scope_dir="${HOME:?HOME nao setado}/.claude/skills"
      ;;
    project)
      _install_scope_dir="./.claude/skills"
      ;;
    *)
      log_error "install: scope invalido (bug interno): $_install_scope"
      return 1
      ;;
  esac
  return 0
}

# _install_validate_project_scope: heuristica para evitar instalar em CWD
# que claramente nao e projeto. Skipa em --yes ou em scope=global.
_install_validate_project_scope() {
  if [ "$_install_scope" != project ]; then
    return 0
  fi
  if [ "$_install_yes" = 1 ]; then
    return 0
  fi
  # Indicadores de projeto (algum precisa estar presente no CWD).
  if [ -d ./.git ] || [ -f ./package.json ] || [ -f ./go.mod ] \
     || [ -f ./Cargo.toml ] || [ -f ./pyproject.toml ] \
     || [ -f ./requirements.txt ] || [ -f ./pom.xml ] \
     || [ -f ./Gemfile ] || [ -f ./CLAUDE.md ] || [ -d ./.claude ]; then
    return 0
  fi
  log_error "install: CWD nao parece ser um projeto (sem .git/, package.json, go.mod, etc.)"
  log_error "         re-execute com --yes para confirmar instalacao em $(pwd)"
  return 1
}

# _install_resolve_urls: define _install_tarball_url + _install_sha256_url.
# Prioridade:
#   1. --from URL (http/https/file)            — uso explicito
#   2. $CSTK_RELEASE_URL (env)                 — escape hatch p/ fixtures
#   3. consulta API GitHub /releases/latest    — caso default
_install_resolve_urls() {
  if [ -z "$_install_from" ]; then
    _install_from=${CSTK_RELEASE_URL:-}
  fi

  # Caso 3: nada explicito -> consulta API
  if [ -z "$_install_from" ]; then
    _install_repo=${CSTK_REPO:-JotJunior/cstk}
    _install_api="https://api.github.com/repos/$_install_repo/releases/latest"
    log_info "install: consultando ultima release de $_install_repo via API GitHub..."
    _install_api_resp=$(curl -fsSL --connect-timeout 10 --max-time 60 \
      "$_install_api" 2>/dev/null) || {
      log_error "install: falha ao consultar $_install_api (offline?)"
      log_error "         use --from <url> ou \$CSTK_RELEASE_URL como alternativa"
      return 1
    }
    _install_tag=$(printf '%s\n' "$_install_api_resp" \
      | grep -o '"tag_name":[[:space:]]*"[^"]*"' \
      | head -n 1 \
      | sed 's/.*"\([^"]*\)"$/\1/')
    if [ -z "$_install_tag" ]; then
      log_error "install: tag_name nao encontrado em $_install_api"
      return 1
    fi
    # build-release.sh strip o "v" do filename; tag mantem. Match.
    _install_tag_bare=${_install_tag#v}
    _install_tarball_url="https://github.com/$_install_repo/releases/download/$_install_tag/cstk-$_install_tag_bare.tar.gz"
    _install_sha256_url="${_install_tarball_url}.sha256"
    log_info "install: ultima release: $_install_tag"
    return 0
  fi

  # Casos 1 + 2: URL explicita
  case "$_install_from" in
    https://*|file://*)
      # US3/enforced-guards FR-012/FR-013: host confiavel checado ANTES de
      # qualquer download. file:// e isento (FR-014); trusted_host_check
      # cuida da distincao internamente.
      if ! trusted_host_check "$_install_from"; then
        return 1
      fi
      _install_tarball_url=$_install_from
      _install_sha256_url="${_install_from}.sha256"
      ;;
    http://*)
      # http em texto plano permite MITM trocar tarball E .sha256 juntos
      # (checksum de mesma origem nao protege contra origem adulterada).
      log_error "install: --from http:// rejeitado (MITM anula o checksum de mesma origem); use https:// ou file://"
      return 1
      ;;
    *)
      log_error "install: --from precisa ser URL (https:// file://); recebido: $_install_from"
      log_error "         para baixar a ultima release automaticamente, omita --from"
      return 1
      ;;
  esac
  return 0
}

# _install_locate_catalog: encontra catalog/ na arvore extraida e valida
# presenca de VERSION + profiles.txt.
_install_locate_catalog() {
  # find -maxdepth e BSD/GNU; coerente com tests/run.sh.
  _install_catalog_dir=$(find "$_install_staged" -maxdepth 3 -type d -name catalog 2>/dev/null | head -1)
  if [ -z "$_install_catalog_dir" ] || [ ! -d "$_install_catalog_dir" ]; then
    log_error "install: catalog/ nao encontrado no tarball"
    return 1
  fi
  if [ ! -f "$_install_catalog_dir/VERSION" ]; then
    log_error "install: $_install_catalog_dir/VERSION ausente"
    return 1
  fi
  if [ ! -f "$_install_catalog_dir/profiles.txt" ]; then
    log_error "install: $_install_catalog_dir/profiles.txt ausente"
    return 1
  fi
  _install_release_version=$(head -n 1 -- "$_install_catalog_dir/VERSION" | tr -d '[:space:]')
  if [ -z "$_install_release_version" ]; then
    log_error "install: $_install_catalog_dir/VERSION vazio"
    return 1
  fi
  return 0
}

# _install_resolve_selection: combina cherry-pick explicito + profile,
# dedupa e ordena. Resultado em $_install_selection (uma skill por linha).
_install_resolve_selection() {
  _install_resolved_profile=""
  if [ -n "$_install_profile" ]; then
    _install_resolved_profile=$(resolve_profile "$_install_catalog_dir/profiles.txt" "$_install_profile") || {
      return 1
    }
  fi
  _install_selection=$(
    {
      [ -n "$_install_explicit_skills" ] && printf '%s\n' "$_install_explicit_skills"
      [ -n "$_install_resolved_profile" ] && printf '%s\n' "$_install_resolved_profile"
    } | awk 'NF>0' | sort -u
  )
  return 0
}

# _install_list_catalog_skills: enumera skills disponiveis no catalog.
# Inclui: catalog/skills/* + catalog/language/*/skills/*.
# Stdout: nomes de skills, uma por linha, sort -u.
_install_list_catalog_skills() {
  {
    if [ -d "$_install_catalog_dir/skills" ]; then
      find "$_install_catalog_dir/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | while IFS= read -r _ilcs_d; do basename "$_ilcs_d"; done
    fi
    if [ -d "$_install_catalog_dir/language" ]; then
      for _ilcs_lang in "$_install_catalog_dir/language"/*; do
        [ -d "$_ilcs_lang/skills" ] || continue
        find "$_ilcs_lang/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
          | while IFS= read -r _ilcs_d; do basename "$_ilcs_d"; done
      done
    fi
  } | sort -u
}

# _install_resolve_selection_interactive: alternativa a _install_resolve_selection
# quando --interactive esta ativo. Renderiza menu via ui.sh, le input do usuario,
# resolve para set de skills e popula $_install_selection.
_install_resolve_selection_interactive() {
  _irsi_skills_list=$(_install_list_catalog_skills)
  if [ -z "$_irsi_skills_list" ]; then
    log_error "install: catalog vazio (nenhuma skill em $_install_catalog_dir/{skills,language})"
    return 1
  fi
  _irsi_resolved=$(ui_select_interactive \
    "$_install_catalog_dir/profiles.txt" "$_irsi_skills_list" install) || return 1
  _install_selection=$(printf '%s\n' "$_irsi_resolved" | awk 'NF>0' | sort -u)
  return 0
}

# _install_find_skill_src: imprime path da skill no catalog (skills/ ou
# language/*/skills/), ou nada se ausente.
_install_find_skill_src() {
  _isfs_skill=$1
  if [ -d "$_install_catalog_dir/skills/$_isfs_skill" ]; then
    printf '%s\n' "$_install_catalog_dir/skills/$_isfs_skill"
    return 0
  fi
  if [ -d "$_install_catalog_dir/language" ]; then
    for _isfs_lang in "$_install_catalog_dir/language"/*; do
      [ -d "$_isfs_lang/skills/$_isfs_skill" ] || continue
      printf '%s\n' "$_isfs_lang/skills/$_isfs_skill"
      return 0
    done
  fi
  return 1
}

# _install_process_skill: deteccao de estado (3 ramos) + acao correspondente.
_install_process_skill() {
  _ips_skill=$1
  _ips_src=$(_install_find_skill_src "$_ips_skill") || _ips_src=""
  if [ -z "$_ips_src" ]; then
    log_warn "install: skill desconhecida no catalog: $_ips_skill"
    _install_count_missing=$((_install_count_missing + 1))
    return 0
  fi

  _ips_dst="$_install_scope_dir/$_ips_skill"

  # Ramo 1: nao existe em disco -> install fresh
  # Ramo 2: existe em disco e esta no manifest -> overwrite (treat as update)
  # Ramo 3: existe em disco e nao esta no manifest -> preserve (FR-007)
  if [ ! -e "$_ips_dst" ]; then
    _install_apply "$_ips_skill" "$_ips_src" "$_ips_dst" install
    return $?
  fi

  if lookup_entry "$_install_manifest_path" "$_ips_skill" >/dev/null 2>&1; then
    _install_apply "$_ips_skill" "$_ips_src" "$_ips_dst" update
    return $?
  fi

  log_warn "install: preservando skill nao-manifestada (third-party): $_ips_skill"
  _install_count_preserved=$((_install_count_preserved + 1))
  return 0
}

# _install_apply: executa copia + manifest upsert (ou apenas reporta em dry-run).
_install_apply() {
  _ia_skill=$1
  _ia_src=$2
  _ia_dst=$3
  _ia_action=$4

  if [ "$_install_dry_run" = 1 ]; then
    log_info "[dry-run] $_ia_action: $_ia_skill"
  else
    rm -rf -- "$_ia_dst" 2>/dev/null || :
    if ! cp -R -- "$_ia_src" "$_ia_dst"; then
      log_error "install: cp -R falhou para $_ia_skill"
      return 1
    fi
    _ia_sha=$(hash_dir "$_ia_dst") || {
      log_error "install: hash_dir falhou para $_ia_skill"
      return 1
    }
    if ! upsert_entry "$_install_manifest_path" "$_ia_skill" \
                      "$_install_release_version" "$_ia_sha" "$_install_now"; then
      log_error "install: upsert manifest falhou para $_ia_skill"
      return 1
    fi
  fi

  case "$_ia_action" in
    install) _install_count_installed=$((_install_count_installed + 1)) ;;
    update)  _install_count_updated=$((_install_count_updated + 1)) ;;
  esac
  return 0
}

# _install_apply_hooks_if_needed: integra hooks de language-* (FR-009b/c/d)
# E o guard-hook de enforced-guards (task 2.5.1 — US1, independente do
# profile escolhido).
#
# Decisao por scope (ambos os ramos abaixo, mesma regra FR-009c/Decision 9):
#   --scope=project + profile=language-X          -> instala hooks/ + merge settings
#   --scope=project + skill agente-00c-runtime    -> apply_guard_hooks()
#   --scope=global   (qualquer caso acima)          -> skip hooks + warn omitted
#
# Sub-passos do ramo language-* (inalterado desta feature):
#   1. Localiza catalog/language/<lang>/{hooks/,settings.json}
#   2. Copia hooks/ para $scope_dir/../hooks/  (i.e. ./.claude/hooks/)
#   3. Settings: merge_settings se jq disponivel, senao print_paste_block
#
# Ramo novo (guard-hook): delega inteiramente a apply_guard_hooks() em
# hooks.sh — reusa a MESMA mecanica de merge/paste, nenhum mecanismo de
# distribuicao novo (FR-017). Estado proprio (_install_guard_hook_state)
# para nao colidir com _install_hook_state (ramo language-*, independente).
#
# Em --dry-run: reporta plano via log_info, nao escreve.
_install_apply_hooks_if_needed() {
  if [ "$_install_scope" = global ]; then
    # _install_hook_state so e setado quando o profile e language-* (paridade
    # EXATA com o comportamento pre-enforced-guards — regressao encontrada
    # empiricamente via scenario_install_profile_nao_language_sem_hooks_no_summary:
    # setar incondicionalmente aqui vazava "hooks: omitted" no summary de
    # QUALQUER profile em scope=global, nao so language-*).
    case "$_install_profile" in
      language-*)
        log_warn "install: hooks de $_install_profile omitidos em scope=global (FR-009c)"
        _install_hook_state="omitted"
        ;;
    esac
    if printf '%s\n' "$_install_selection" | grep -Fxq -- "agente-00c-runtime"; then
      log_warn "install: guard-hooks (enforced-guards) omitidos em scope=global (FR-009c)"
      _install_guard_hook_state="omitted"
    fi
    return 0
  fi

  case "$_install_profile" in
    language-*) _install_apply_language_hooks ;;
  esac

  if printf '%s\n' "$_install_selection" | grep -Fxq -- "agente-00c-runtime"; then
    _agh_claude_root="${_install_scope_dir%/skills}"
    _agh_src_dir="$_install_catalog_dir/skills/agente-00c-runtime/hooks"
    _install_guard_hook_state=$(apply_guard_hooks "$_agh_src_dir" "$_agh_claude_root" "$_install_dry_run")
  fi

  return 0
}

# _install_apply_language_hooks: corpo original do ramo language-* de
# _install_apply_hooks_if_needed, extraido para funcao propria para que o
# guard-hook (acima) possa rodar independentemente do profile. Comportamento
# 100% inalterado desta feature.
_install_apply_language_hooks() {
  _ahin_lang=${_install_profile#language-}
  _ahin_lang_dir="$_install_catalog_dir/language/$_ahin_lang"
  if [ ! -d "$_ahin_lang_dir" ]; then
    log_warn "install: catalog/language/$_ahin_lang ausente — hooks skipped"
    _install_hook_state="not-applicable"
    return 0
  fi

  _ahin_hooks_src="$_ahin_lang_dir/hooks"
  _ahin_settings_src="$_ahin_lang_dir/settings.json"
  # claude_root = scope_dir/.. (ex: ./.claude/skills/.. = ./.claude/)
  _ahin_claude_root="${_install_scope_dir%/skills}"
  _ahin_hooks_dst="$_ahin_claude_root/hooks"
  _ahin_settings_dst="$_ahin_claude_root/settings.json"

  # Copia hooks/ se existir
  if [ -d "$_ahin_hooks_src" ]; then
    if [ "$_install_dry_run" = 1 ]; then
      log_info "[dry-run] hooks: copiaria $_ahin_hooks_src → $_ahin_hooks_dst"
    else
      if ! mkdir -p -- "$_ahin_hooks_dst" 2>/dev/null; then
        log_error "install: nao consegui criar $_ahin_hooks_dst"
        _install_hook_state="error"
        return 0
      fi
      cp -R -- "$_ahin_hooks_src"/. "$_ahin_hooks_dst"/ || {
        log_error "install: cp -R hooks falhou"
        _install_hook_state="error"
        return 0
      }
    fi
  fi

  # Settings.json: merge ou paste
  if [ ! -f "$_ahin_settings_src" ]; then
    log_info "install: $_ahin_settings_src ausente — sem settings.json para integrar"
    _install_hook_state="hooks-only"
    return 0
  fi

  if [ "$_install_dry_run" = 1 ]; then
    if detect_jq; then
      log_info "[dry-run] settings: mesclaria $_ahin_settings_src → $_ahin_settings_dst (jq)"
      _install_hook_state="merged"
    else
      log_info "[dry-run] settings: imprimiria paste-block (jq ausente)"
      _install_hook_state="paste-instructed"
    fi
    return 0
  fi

  if detect_jq; then
    if merge_settings "$_ahin_settings_dst" "$_ahin_settings_src"; then
      _install_hook_state="merged"
    else
      _install_hook_state="error"
    fi
  else
    print_paste_block "$_ahin_settings_dst" "$_ahin_settings_src"
    _install_hook_state="paste-instructed"
  fi
  return 0
}

# _install_apply_extra_kinds: instala commands e agents (1 .md = 1 artefato).
#
# Sempre instala TODOS os .md em catalog/<kind>/ — sem filtro de profile,
# porque commands e agents sao infraestrutura global do toolkit, nao skills.
# 3 ramos por arquivo (espelha _install_process_skill):
#   1. nao existe em disco        -> install fresh
#   2. existe + esta no manifest  -> overwrite (update)
#   3. existe + nao no manifest   -> preserve (third-party)
_install_apply_extra_kinds() {
  for _iaek_kind in commands agents; do
    _install_apply_kind "$_iaek_kind"
  done
}

# _install_apply_kind: itera catalog/<kind>/*.md e processa cada um.
#
# Usa manifest dedicado por kind (~/.claude/<kind>/.cstk-manifest) — schema
# identico ao de skills, reaproveitando manifest.sh sem alteracao.
# _install_apply_mcp_server: espelha catalog/mcp/state-server no destino
# instalado (~/.claude/mcp/state-server). Conteudo versionado com a release
# (fonte de build da imagem do servidor, consumida pelo helper confinado de
# container + npm ci dentro da imagem);
# sem manifest por arquivo: replace atomico do diretorio inteiro (rm+cp),
# mesmo espirito do provisionamento de hooks. Escopo global apenas — o
# resolve de _mcp_context_dir so olha ~/.claude. Catalogo sem mcp/ (release
# antiga) = no-op silencioso.
_install_apply_mcp_server() {
  _iams_src="$_install_catalog_dir/mcp/state-server"
  [ -d "$_iams_src" ] && [ -f "$_iams_src/package.json" ] || return 0
  [ "$_install_scope" = "global" ] || return 0

  _iams_dst="${HOME:?HOME nao setado}/.claude/mcp/state-server"
  if [ "$_install_dry_run" = 1 ]; then
    log_info "[dry-run] mcp/state-server -> $_iams_dst"
    return 0
  fi
  mkdir -p -- "${_iams_dst%/state-server}"
  rm -rf -- "$_iams_dst"
  cp -R -- "$_iams_src" "$_iams_dst"
  log_info "mcp/state-server instalado em $_iams_dst"
  return 0
}

_install_apply_kind() {
  _iak_kind=$1
  _iak_src_dir="$_install_catalog_dir/$_iak_kind"
  if [ ! -d "$_iak_src_dir" ]; then
    return 0
  fi

  # dest = scope_dir/../<kind>  (ex: ~/.claude/skills/.. = ~/.claude/, depois /commands)
  case "$_install_scope" in
    global)  _iak_dst_dir="${HOME:?HOME nao setado}/.claude/$_iak_kind" ;;
    project) _iak_dst_dir="./.claude/$_iak_kind" ;;
    *)
      log_error "install: scope invalido em apply_kind (bug): $_install_scope"
      return 1
      ;;
  esac

  _iak_manifest=$(manifest_default_path "$_install_scope" "$_iak_kind") || {
    log_error "install: manifest_default_path falhou para kind=$_iak_kind"
    return 1
  }

  # Itera .md soltos. Sem .md no catalog -> nada a fazer (silencio).
  _iak_has_any=0
  for _iak_src in "$_iak_src_dir"/*.md; do
    [ -f "$_iak_src" ] || continue
    _iak_has_any=1
    _iak_name=$(basename -- "$_iak_src" .md)
    _iak_dst="$_iak_dst_dir/$_iak_name.md"

    # Dry-run: reporta plano sem escrever
    if [ "$_install_dry_run" = 1 ]; then
      if [ ! -e "$_iak_dst" ]; then
        log_info "[dry-run] $_iak_kind install: $_iak_name"
        _install_bump_extra_counter "$_iak_kind" install
      elif lookup_entry "$_iak_manifest" "$_iak_name" >/dev/null 2>&1; then
        log_info "[dry-run] $_iak_kind update: $_iak_name"
        _install_bump_extra_counter "$_iak_kind" update
      else
        log_warn "[dry-run] $_iak_kind preserve (third-party): $_iak_name"
        _install_bump_extra_counter "$_iak_kind" preserved
      fi
      continue
    fi

    # Cria dir destino sob demanda — antes de qualquer escrita.
    if ! mkdir -p -- "$_iak_dst_dir" 2>/dev/null; then
      log_error "install: nao foi possivel criar $_iak_dst_dir"
      return 1
    fi

    # Ramo 3: existe e nao esta no manifest -> preserve
    if [ -e "$_iak_dst" ] && ! lookup_entry "$_iak_manifest" "$_iak_name" >/dev/null 2>&1; then
      log_warn "install: preservando $_iak_kind nao-manifestado (third-party): $_iak_name"
      _install_bump_extra_counter "$_iak_kind" preserved
      continue
    fi

    # Ramo 1 ou 2: copia + manifest upsert
    _iak_action=install
    [ -e "$_iak_dst" ] && _iak_action=update
    if ! cp -- "$_iak_src" "$_iak_dst"; then
      log_error "install: cp falhou para $_iak_kind/$_iak_name"
      return 1
    fi
    _iak_sha=$(hash_file "$_iak_dst") || {
      log_error "install: hash_file falhou para $_iak_kind/$_iak_name"
      return 1
    }
    if ! upsert_entry "$_iak_manifest" "$_iak_name" \
                      "$_install_release_version" "$_iak_sha" "$_install_now"; then
      log_error "install: upsert manifest falhou para $_iak_kind/$_iak_name"
      return 1
    fi
    _install_bump_extra_counter "$_iak_kind" "$_iak_action"
  done

  # Sem nenhum .md em catalog/<kind>/ -> retorno limpo, sem barulho.
  if [ "$_iak_has_any" = 0 ]; then
    return 0
  fi
  return 0
}

# _install_bump_extra_counter <kind> <action>
# Action: install | update | preserved
_install_bump_extra_counter() {
  case "$1.$2" in
    commands.install)   _install_count_commands_installed=$((_install_count_commands_installed + 1)) ;;
    commands.update)    _install_count_commands_updated=$((_install_count_commands_updated + 1)) ;;
    commands.preserved) _install_count_commands_preserved=$((_install_count_commands_preserved + 1)) ;;
    agents.install)     _install_count_agents_installed=$((_install_count_agents_installed + 1)) ;;
    agents.update)      _install_count_agents_updated=$((_install_count_agents_updated + 1)) ;;
    agents.preserved)   _install_count_agents_preserved=$((_install_count_agents_preserved + 1)) ;;
  esac
}

# _install_emit_summary: bloco em stderr conforme contract §install.
_install_emit_summary() {
  _ies_prefix=""
  if [ "$_install_dry_run" = 1 ]; then
    _ies_prefix="(dry-run) "
  fi
  {
    printf '==> %scstk install summary\n' "$_ies_prefix"
    printf '  installed: %d\n' "$_install_count_installed"
    printf '  updated: %d\n' "$_install_count_updated"
    printf '  preserved (third-party): %d\n' "$_install_count_preserved"
    printf '  missing from catalog: %d\n' "$_install_count_missing"
    printf '  scope: %s\n' "$_install_scope"
    printf '  toolkit version: %s\n' "${_install_release_version:-?}"
    if [ -n "$_install_hook_state" ]; then
      printf '  hooks: %s\n' "$_install_hook_state"
    fi
    if [ -n "$_install_guard_hook_state" ]; then
      printf '  guard-hooks: %s\n' "$_install_guard_hook_state"
    fi
    _ies_cmd_total=$((_install_count_commands_installed + _install_count_commands_updated + _install_count_commands_preserved))
    if [ "$_ies_cmd_total" -gt 0 ]; then
      printf '  commands: installed=%d updated=%d preserved=%d\n' \
        "$_install_count_commands_installed" \
        "$_install_count_commands_updated" \
        "$_install_count_commands_preserved"
    fi
    _ies_ag_total=$((_install_count_agents_installed + _install_count_agents_updated + _install_count_agents_preserved))
    if [ "$_ies_ag_total" -gt 0 ]; then
      printf '  agents: installed=%d updated=%d preserved=%d\n' \
        "$_install_count_agents_installed" \
        "$_install_count_agents_updated" \
        "$_install_count_agents_preserved"
    fi
  } >&2
}
