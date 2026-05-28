# self-update.sh — comando `cstk self-update`. CRITICAL (FASE 5).
#
# Ref: docs/specs/cstk-cli/contracts/cli-commands.md §self-update
#      docs/specs/cstk-cli/spec.md FR-005, FR-005a, FR-006, FR-006a, FR-010a
#      docs/specs/cstk-cli/research.md Decision 4 (stage-and-rename)
#      docs/specs/cstk-cli/quickstart.md Scenarios 6, 7
#
# Funcao exportada:
#   self_update_main "$@"   — entry point chamado por cli/cstk
#
# Sintaxe (NUNCA aceita --scope — opera sobre a CLI, nao skills):
#   cstk self-update [--check] [--dry-run] [--yes]
#
# Atomicidade par bin+lib (FR-006):
#   Sequencia stage-and-rename (renames POSIX sao atomicos):
#     a. mv $LIB → $LIB.old
#     b. mv $LIB.new → $LIB           ← lib swap
#     c. mv -f $BIN.new → $BIN        ← COMMIT POINT (atomicidade par)
#     d. rm -rf $LIB.old              ← cleanup; falha aqui nao quebra correcao
#
# Estados observaveis apos qualquer kill -9:
#   - Antes de (b): 100% versao antiga
#   - Entre (b) e (c): TRANSIENTE — boot-check em cstk detecta lib_version !=
#     embedded_version e aborta com mensagem pedindo "cstk self-update" para
#     completar a recuperacao. NAO retorna output incorreto.
#   - Apos (c): 100% versao nova
#
# Invariante FR-006a: NAO le nem escreve manifests de skills. Nenhum path
# do tipo `~/.claude/skills/.cstk-manifest` aparece neste arquivo. Por design.
#
# Test hooks (somente para testes de atomicidade):
#   CSTK_TEST_SU_ABORT_AT=after-download|after-stage|between-lib-bin|after-bin
#   Quando setado, o codigo retorna 99 no ponto correspondente, deixando o
#   estado parcial intacto para inspecao do teste. NAO usar em producao.
#
# Exit codes:
#   0  sucesso (ou ja na ultima versao)
#   1  erro geral (rede, checksum, filesystem, install incompleto)
#   2  uso incorreto
#   3  lock detido
#   10 (apenas com --check) update disponivel
#   99 (apenas com CSTK_TEST_SU_ABORT_AT) abort programatico

if [ -n "${_CSTK_SU_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_SU_LOADED=1

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

_su_print_help() {
  cat >&2 <<'HELP'
cstk self-update — atualiza o proprio binario cstk + cli/lib (atomico).

USO:
  cstk self-update [--check] [--dry-run] [--yes]

OPCOES:
  --check        Apenas verifica; imprime "latest:X current:Y"; exit 0/10/1.
  --dry-run      Mostra plano sem modificar nada.
  --yes          Pula confirmacoes (placeholder; sem confirmacoes hoje).

NOTA:
  --scope nao e aceito: self-update opera sobre a CLI instalada, nao sobre
  skills. Use `cstk update` para skills.

ENV (overrides para testes/forks):
  CSTK_BIN              path do binario instalado (default: ~/.local/bin/cstk)
  CSTK_INSTALL_LIB      dir pai da lib (default: ~/.local/share/cstk)
  CSTK_LIB              dir da lib (default: $CSTK_INSTALL_LIB/lib)
  CSTK_RELEASE_URL      URL exata do tarball (skipa GitHub API)
  CSTK_REPO             owner/repo (default: JotJunior/cstk)
HELP
}

self_update_main() {
  _su_reset_state

  if ! _su_parse_args "$@"; then
    return 2
  fi

  if [ "$_su_help" = 1 ]; then
    _su_print_help
    return 0
  fi

  if ! _su_resolve_paths; then
    return 1
  fi

  if ! _su_validate_install; then
    return 1
  fi

  # _su_current_lib = versao reportada pelo arquivo no lib (atomic-com-lib).
  # _su_current_bin = versao embutida no bin que esta rodando AGORA.
  # Em estado normal sao iguais; em transiente (FR-006c) divergem e o caminho
  # de recovery deve fazer o swap mesmo se _su_current_lib ja for == _su_latest.
  _su_current_lib=$(head -n 1 -- "$_su_lib_version_file" 2>/dev/null | tr -d '[:space:]')
  [ -z "$_su_current_lib" ] && _su_current_lib="unknown"
  _su_current_bin=${CSTK_EMBEDDED_VERSION:-unknown}
  _su_current=$_su_current_lib  # "current" user-facing = lib (atomic-com-lib)

  if ! _su_resolve_urls; then
    return 1
  fi

  if ! _su_resolve_latest; then
    return 1
  fi

  # --check mode: reporta lib/bin separadamente quando divergem (transiente).
  if [ "$_su_check" = 1 ]; then
    if [ "$_su_current_bin" != "$_su_current_lib" ]; then
      printf 'latest:%s current:%s (transient: bin=%s)\n' \
        "$_su_latest" "$_su_current_lib" "$_su_current_bin"
      return 10
    fi
    printf 'latest:%s current:%s\n' "$_su_latest" "$_su_current"
    if [ "$_su_latest" = "$_su_current" ]; then
      return 0
    fi
    return 10
  fi

  # No-op apenas se BIN E LIB ambos ja batem com latest. Estado transiente
  # (lib=latest, bin=outro) cai no caminho de swap para completar recovery.
  if [ "$_su_latest" = "$_su_current_lib" ] && [ "$_su_latest" = "$_su_current_bin" ]; then
    log_info "self-update: ja na versao $_su_current — nada a fazer"
    return 0
  fi
  if [ "$_su_current_bin" != "$_su_current_lib" ]; then
    log_warn "self-update: estado transiente detectado (bin=$_su_current_bin lib=$_su_current_lib) — completando recovery"
  fi

  # Lock dedicado de self-update (NAO confunde com lock de skills por scope).
  if [ "$_su_dry_run" != 1 ]; then
    if ! acquire_lock "$_su_lock_path"; then
      return 3
    fi
  fi
  trap '_su_cleanup' EXIT INT TERM

  # Stage download
  _su_staged=$(mktemp -d 2>/dev/null) || {
    log_error "self-update: mktemp -d falhou"
    return 1
  }

  if ! download_and_verify "$_su_tarball_url" "$_su_sha256_url" "$_su_staged"; then
    return 1
  fi

  if _su_test_abort_at after-download; then
    log_warn "self-update: TEST abort apos download"
    return 99
  fi

  if ! _su_locate_cli; then
    return 1
  fi

  if [ "$_su_dry_run" = 1 ]; then
    log_info "[dry-run] self-update: $_su_current → $_su_latest"
    return 0
  fi

  # Build $LIB.new e $BIN.new (irmaos, mesmo filesystem -> rename atomico).
  _su_lib_new="$_su_lib_dir.new"
  _su_bin_new="$_su_bin_path.new"

  if ! _su_stage_new; then
    return 1
  fi

  if _su_test_abort_at after-stage; then
    log_warn "self-update: TEST abort apos stage"
    return 99
  fi

  # Sequencia stage-and-rename. Cada mv POSIX e atomico.
  if ! mv -- "$_su_lib_dir" "$_su_lib_dir.old" 2>/dev/null; then
    log_error "self-update: rename a) lib → lib.old falhou"
    rm -rf -- "$_su_lib_new" "$_su_bin_new" 2>/dev/null
    return 1
  fi

  if ! mv -- "$_su_lib_new" "$_su_lib_dir" 2>/dev/null; then
    log_error "self-update: rename b) lib.new → lib falhou — rollback"
    mv -- "$_su_lib_dir.old" "$_su_lib_dir" 2>/dev/null
    rm -f -- "$_su_bin_new" 2>/dev/null
    return 1
  fi

  if _su_test_abort_at between-lib-bin; then
    log_warn "self-update: TEST abort entre lib e bin (estado transiente — FR-006c)"
    return 99
  fi

  # COMMIT POINT
  if ! mv -f -- "$_su_bin_new" "$_su_bin_path" 2>/dev/null; then
    log_error "self-update: rename c) bin.new → bin falhou — rollback critico"
    rm -rf -- "$_su_lib_dir" 2>/dev/null
    mv -- "$_su_lib_dir.old" "$_su_lib_dir" 2>/dev/null
    return 1
  fi

  if _su_test_abort_at after-bin; then
    log_warn "self-update: TEST abort apos commit"
    return 99
  fi

  # Cleanup pos-commit (falhas aqui nao afetam correcao).
  rm -rf -- "$_su_lib_dir.old" 2>/dev/null || :

  # Atualiza VERSION user-facing (legado em $INSTALL_LIB/VERSION).
  # Esse arquivo e lido por `cstk --version` quando $CSTK_LIB/VERSION nao
  # existe; mantido em sync para compatibilidade.
  printf '%s\n' "$_su_latest" > "$_su_install_root/VERSION" 2>/dev/null || \
    log_warn "self-update: nao consegui atualizar $_su_install_root/VERSION (display only)"

  log_info "self-update: $_su_current → $_su_latest concluido"
  return 0
}

_su_reset_state() {
  _su_help=0
  _su_check=0
  _su_dry_run=0
  _su_yes=0
  _su_bin_path=""
  _su_lib_dir=""
  _su_install_root=""
  _su_lib_version_file=""
  _su_lock_path=""
  _su_from=""
  _su_tarball_url=""
  _su_sha256_url=""
  _su_current=""
  _su_latest=""
  _su_staged=""
  _su_src_bin=""
  _su_src_lib=""
  _su_lib_new=""
  _su_bin_new=""
}

_su_cleanup() {
  if [ -n "${_CSTK_LOCK_DIR:-}" ]; then
    release_lock 2>/dev/null || :
  fi
  if [ -n "${_su_staged:-}" ] && [ -d "$_su_staged" ]; then
    rm -rf -- "$_su_staged" 2>/dev/null || :
  fi
}

_su_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) _su_help=1; shift ;;
      --check) _su_check=1; shift ;;
      --dry-run) _su_dry_run=1; shift ;;
      --yes|-y) _su_yes=1; shift ;;
      --from)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          log_error "self-update: --from exige valor (URL)"
          return 1
        fi
        _su_from=$2; shift 2 ;;
      --from=*)
        _su_from=${1#--from=}; shift ;;
      --scope|--scope=*)
        log_error "self-update: --scope nao e aceito (self-update opera sobre a CLI, nao skills)"
        return 1
        ;;
      --) shift; break ;;
      -*)
        log_error "self-update: flag desconhecida: $1"
        return 1
        ;;
      *)
        log_error "self-update: argumento posicional inesperado: $1"
        return 1
        ;;
    esac
  done
  return 0
}

# _su_resolve_paths: descobre bin, lib, install_root.
_su_resolve_paths() {
  if [ -n "${CSTK_BIN:-}" ]; then
    _su_bin_path=$CSTK_BIN
  else
    _su_bin_path="${HOME:?HOME nao setado}/.local/bin/cstk"
  fi

  if [ -n "${CSTK_LIB:-}" ] && [ "$CSTK_LIB" != "${CSTK_LIB%/lib}" -o -d "${CSTK_LIB}" ]; then
    _su_lib_dir=$CSTK_LIB
  else
    _su_lib_dir="${HOME}/.local/share/cstk/lib"
  fi

  # install_root = parent of lib_dir
  _su_install_root=$(cd -- "$_su_lib_dir/.." 2>/dev/null && pwd) || _su_install_root="$_su_lib_dir/.."
  _su_lib_version_file="$_su_lib_dir/VERSION"
  _su_lock_path="$_su_install_root/.self-update.lock"
  return 0
}

# _su_validate_install: checa que a instalacao existe (FR-005a — self-update
# pressupõe bootstrap previo).
_su_validate_install() {
  if [ ! -f "$_su_bin_path" ]; then
    log_error "self-update: binario nao encontrado em $_su_bin_path"
    log_error "         use o bootstrap (one-liner) para a primeira instalacao"
    return 1
  fi
  if [ ! -d "$_su_lib_dir" ]; then
    log_error "self-update: lib nao encontrada em $_su_lib_dir"
    log_error "         use o bootstrap (one-liner) para a primeira instalacao"
    return 1
  fi
  if [ ! -f "$_su_lib_version_file" ]; then
    log_warn "self-update: $_su_lib_version_file ausente (instalacao pre-FASE-5?)"
    log_warn "         o boot-check ficara em bypass ate o primeiro self-update"
  fi
  return 0
}

# _su_resolve_urls: --from > $CSTK_RELEASE_URL > GitHub API (resolvido em latest).
_su_resolve_urls() {
  if [ -z "$_su_from" ]; then
    _su_from=${CSTK_RELEASE_URL:-}
  fi
  if [ -n "$_su_from" ]; then
    case "$_su_from" in
      http://*|https://*|file://*)
        _su_tarball_url=$_su_from
        _su_sha256_url="${_su_from}.sha256"
        return 0
        ;;
      *)
        log_error "self-update: --from precisa ser URL: $_su_from"
        return 1
        ;;
    esac
  fi
  # API resolution gerada apenas em _su_resolve_latest (precisa do TAG).
  return 0
}

# _su_resolve_latest: descobre tag latest (via API ou inferida do URL).
_su_resolve_latest() {
  if [ -n "$_su_from" ]; then
    # Inferida do filename (cstk-<tag>.tar.gz)
    _su_latest=$(printf '%s' "$_su_from" \
      | sed -n 's|.*/cstk-\([^/]*\)\.tar\.gz$|\1|p')
    if [ -z "$_su_latest" ]; then
      _su_latest="fixture-local"
    fi
    return 0
  fi
  _su_repo=${CSTK_REPO:-JotJunior/cstk}
  _api="https://api.github.com/repos/$_su_repo/releases/latest"
  _resp=$(curl -fsSL --connect-timeout 10 --max-time 60 "$_api" 2>/dev/null) || {
    log_error "self-update: falha ao consultar $_api (offline?)"
    return 1
  }
  _su_latest=$(printf '%s\n' "$_resp" \
    | grep -o '"tag_name":[[:space:]]*"[^"]*"' \
    | head -n 1 \
    | sed 's/.*"\([^"]*\)"$/\1/')
  if [ -z "$_su_latest" ]; then
    log_error "self-update: nao encontrei tag_name em $_api"
    return 1
  fi
  # build-release.sh strip o "v" do filename; tag remota mantem. Match.
  _su_latest_bare=${_su_latest#v}
  _su_tarball_url="https://github.com/$_su_repo/releases/download/$_su_latest/cstk-$_su_latest_bare.tar.gz"
  _su_sha256_url="${_su_tarball_url}.sha256"
  return 0
}

# _su_locate_cli: encontra cli/cstk e cli/lib na arvore extraida.
_su_locate_cli() {
  _su_src_bin=$(find "$_su_staged" -type f -path '*/cli/cstk' 2>/dev/null | head -1)
  _su_src_lib=$(find "$_su_staged" -type d -path '*/cli/lib' 2>/dev/null | head -1)
  if [ -z "$_su_src_bin" ] || [ ! -f "$_su_src_bin" ]; then
    log_error "self-update: tarball nao contem cli/cstk"
    return 1
  fi
  if [ -z "$_su_src_lib" ] || [ ! -d "$_su_src_lib" ]; then
    log_error "self-update: tarball nao contem cli/lib/"
    return 1
  fi
  return 0
}

# _su_stage_new: monta $LIB.new e $BIN.new (sed do CSTK_EMBEDDED_VERSION no bin
# + escrita de VERSION dentro da lib para atomic-com-lib).
_su_stage_new() {
  rm -rf -- "$_su_lib_new" "$_su_bin_new" 2>/dev/null || :

  if ! cp -R -- "$_su_src_lib" "$_su_lib_new"; then
    log_error "self-update: cp -R lib falhou"
    return 1
  fi
  # VERSION dentro da lib (atomic-com-lib swap; FR-006c)
  if ! printf '%s\n' "$_su_latest" > "$_su_lib_new/VERSION"; then
    log_error "self-update: write VERSION na lib.new falhou"
    rm -rf -- "$_su_lib_new" 2>/dev/null
    return 1
  fi
  # Bin: sed CSTK_EMBEDDED_VERSION para o tag novo
  if ! sed "s/^CSTK_EMBEDDED_VERSION=.*/CSTK_EMBEDDED_VERSION=\"$_su_latest\"/" \
       "$_su_src_bin" > "$_su_bin_new"; then
    log_error "self-update: sed CSTK_EMBEDDED_VERSION falhou"
    rm -rf -- "$_su_lib_new" "$_su_bin_new" 2>/dev/null
    return 1
  fi
  if ! chmod +x "$_su_bin_new"; then
    log_error "self-update: chmod +x bin.new falhou"
    rm -rf -- "$_su_lib_new" "$_su_bin_new" 2>/dev/null
    return 1
  fi
  return 0
}

_su_test_abort_at() {
  case "${CSTK_TEST_SU_ABORT_AT:-}" in
    "$1") return 0 ;;
    *) return 1 ;;
  esac
}
