#!/bin/sh
# jira-config.sh — leitura/validacao de ProjectConfig e checagem de
# Credential do plugin cstk-jira (feature cstk-jira, FASE 2 tarefa 2.1).
#
# Ref: docs/specs/cstk-jira/data-model.md Entity ProjectConfig "Resolucao do
#      arquivo (FR-023)", Entity Credential; docs/specs/cstk-jira/contracts/
#      plugin-scripts.md `jira-config.sh`; docs/specs/cstk-jira/contracts/
#      hooks.md (path do config relativo ao cwd); r02 FASE 20 tarefa 20.1.
#
# Subcomandos:
#   jira-config.sh get KEY
#       — Le o ProjectConfig no caminho EFETIVO (ver `resolve-path` abaixo;
#         key=value, `#`/linha em branco ignorados); imprime o valor de KEY
#         em stdout. Exit 3 se nenhum dos dois arquivos existir (FR-017 —
#         plugin inativo, chamador trata como no-op); exit 1 se KEY nao
#         existir no arquivo resolvido.
#
#   jira-config.sh validate
#       — Confere presenca de todos os campos obrigatorios de ProjectConfig
#         no caminho EFETIVO (`resolve-path`), `site_host` como hostname puro
#         (sem esquema/path/porta/userinfo) e `status_fail != status_pass`.
#         r02 FASE 21 tarefa 21.4.1 (data-model.md ProjectConfig "Validation
#         rules (novas)"): tambem valida, quando PRESENTES (ausente/vazia
#         continua valida — ADITIVO), os enums `milestone_mode` (auto/off),
#         `labels_enabled`/`fix_versions_on_subtask`/`links_enabled`
#         (on/off) e `project_create` (gated/never); `milestone_release`
#         contra a allowlist SEC-6 (`^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$`);
#         `link_type_id` contra a allowlist SEC-1 (`[A-Za-z0-9_-]`).
#         Exit 3 se nenhum arquivo existir; exit 1 com diagnostico em stderr
#         no primeiro problema encontrado; exit 0 (sem stdout) se tudo
#         valido.
#
#   jira-config.sh resolve-path
#       — r02 FASE 20 tarefa 20.1.1 (data-model.md ProjectConfig "Resolucao
#         do arquivo (FR-023)"; research.md Decision R2-8): imprime em
#         stdout o caminho ABSOLUTO EFETIVO do ProjectConfig — `<cwd>/
#         .claude/cstk-jira/config` quando existe; ausente => `<worktree
#         principal>/.claude/cstk-jira/config` via `git rev-parse
#         --path-format=absolute --git-common-dir` (SOMENTE LEITURA, este
#         script NUNCA grava no caminho da principal); ausente nos dois =>
#         exit 3 (plugin inativo, FR-017). SEMPRE absoluto (mesmo quando o
#         caminho local resolve) — chamadores tipicamente resolvem o config
#         de dentro de um subshell `cd "$cwd" && ... resolve-path` e usam o
#         resultado DEPOIS, ja de volta no cwd original do processo; um
#         path relativo apontaria para o lugar errado ali. Sem `git` no
#         PATH, ou fora de um repositorio git, o fallback e simplesmente
#         pulado (SEM erro dedicado por isso) — o resultado final continua
#         exit 3 se o cwd tambem nao tiver config. O fallback so roda quando
#         `CSTK_JIRA_CONFIG`
#         NAO foi explicitamente definido pelo chamador (override de teste
#         aponta para um caminho especifico — nunca implica "va procurar em
#         outro lugar"). `get`/`validate` usam a MESMA resolucao (nunca
#         duplicam a regra) — e assim que `jira-sync.sh`/`jira-io.sh`/
#         `jira-setup.sh` (que so chamam `jira-config.sh get`/`validate`,
#         nunca leem o arquivo diretamente) ganham o fallback de graca, sem
#         precisar de mudanca propria.
#
#   jira-config.sh credential-check
#       — Confere existencia e permissao exata 0600 do arquivo de
#         credencial (`${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials`).
#         NUNCA imprime o conteudo do arquivo. Exit 4 se ausente ou com
#         permissao diferente de 0600 (FR-016); exit 0 se ok.
#
# Convencoes (Principio II / contracts/plugin-scripts.md):
#   `#!/bin/sh`, `set -eu`, sem bash-isms; dados em stdout, diagnostico em
#   stderr. Exit codes: 0 sucesso; 1 erro geral; 2 uso incorreto; 3 plugin
#   inativo/nao configurado; 4 credencial ausente/rejeitada; 5 dependencia
#   ausente (nao usado neste script); 6 conflito/orfao (nao usado neste
#   script).
#
# Nenhum host/credencial e aceito por argumento (host vem de
# ProjectConfig.site_host, credencial de Credential — data-model.md).

set -eu

_JC_NAME="jira-config"

# CONFIG_FILE e relativo ao cwd por padrao (mesma convencao de
# contracts/hooks.md "<cwd>/.claude/cstk-jira/config") — script NUNCA aceita
# project-dir por argumento. `CSTK_JIRA_CONFIG` (override apenas para uso
# interno de testes) aponta para um caminho EXATO — quando definida, NUNCA
# ativa o fallback de `_jc_resolve_config_path` (r02 FASE 20 tarefa 20.1.1).
_JC_CONFIG_FILE="${CSTK_JIRA_CONFIG:-./.claude/cstk-jira/config}"

# Caminho da credencial: unico arquivo global por maquina (data-model.md
# Entity Credential), nunca por argumento.
_JC_CRED_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials"

_jc_die_usage() { printf '%s: %s\n' "$_JC_NAME" "$1" >&2; exit 2; }
_jc_die()       { printf '%s: %s\n' "$_JC_NAME" "$1" >&2; exit "${2:-1}"; }

_jc_usage() {
  cat <<'HELP'
jira-config.sh — leitura/validacao de ProjectConfig + checagem de Credential

USO:
  jira-config.sh get KEY             Le uma chave do config efetivo (stdout); exit 3 se ausente
  jira-config.sh validate            Valida campos obrigatorios + regras (data-model.md)
  jira-config.sh resolve-path        Imprime o caminho efetivo do ProjectConfig (cwd, senao worktree principal)
  jira-config.sh credential-check    Confere existencia + permissao 0600 da credencial

Config: <cwd>/.claude/cstk-jira/config; ausente => <worktree principal>/.claude/cstk-jira/config
        (via 'git rev-parse --git-common-dir', somente leitura); ausente nos dois => plugin inativo.
Credencial: ${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials (0600)

EXIT CODES:
  0 sucesso   1 erro geral   2 uso incorreto   3 plugin inativo/config ausente
  4 credencial ausente/rejeitada
HELP
}

# _jc_resolve_config_path -> imprime em stdout o caminho EFETIVO do
# ProjectConfig e retorna 0; retorna 1 (sem imprimir nada) se nenhum dos
# dois arquivos existir. r02 FASE 20 tarefa 20.1.1 (data-model.md
# ProjectConfig "Resolucao do arquivo (FR-023)"; research.md Decision R2-8).
#
# Ordem: (1) $_JC_CONFIG_FILE (cwd por padrao, ou o path exato de
# CSTK_JIRA_CONFIG quando definida); (2) SO quando CSTK_JIRA_CONFIG NAO foi
# definida pelo chamador, tenta a worktree principal via
# `git rev-parse --path-format=absolute --git-common-dir` (SOMENTE LEITURA
# — esta funcao nunca cria nem grava nesse caminho, so confere existencia).
# Sem `git` no PATH, ou fora de um repositorio git, ou dentro do proprio
# checkout principal (onde `--git-common-dir` aponta para o `.git` local, ja
# coberto pelo passo 1) — o fallback e pulado silenciosamente, sem
# diagnostico proprio (o exit 3 final de `get`/`validate`/`resolve-path` ja
# cobre "plugin inativo").
_jc_resolve_config_path() {
  if [ -f "$_JC_CONFIG_FILE" ]; then
    printf '%s\n' "$_JC_CONFIG_FILE"
    return 0
  fi

  [ -z "${CSTK_JIRA_CONFIG:-}" ] || return 1

  command -v git >/dev/null 2>&1 || return 1

  _jcrc_common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ -n "$_jcrc_common_dir" ] || return 1
  _jcrc_principal_root=$(dirname -- "$_jcrc_common_dir")
  _jcrc_principal_config="$_jcrc_principal_root/.claude/cstk-jira/config"

  [ -f "$_jcrc_principal_config" ] || return 1
  printf '%s\n' "$_jcrc_principal_config"
  return 0
}

# _jc_read_raw KEY FILE -> imprime o valor de KEY em FILE, ou nada se
# ausente. Retorno: 0 sempre (ausencia de KEY nao e erro desta funcao — o
# chamador decide o exit code). Parse linha a linha, split no PRIMEIRO '=';
# '#'/branco ignorados (mesmo contrato de state-backend.sh P2, adaptado:
# aqui chave desconhecida nao invalida o arquivo inteiro, so nao casa).
_jc_read_raw() {
  _jcrr_key="$1"
  _jcrr_file="$2"
  _jcrr_found="no"
  while IFS= read -r _jcrr_line || [ -n "$_jcrr_line" ]; do
    case "$_jcrr_line" in
      ''|'#'*)
        : # linha em branco ou comentario — ignorada
        ;;
      *=*)
        _jcrr_k=${_jcrr_line%%=*}
        _jcrr_v=${_jcrr_line#*=}
        if [ "$_jcrr_k" = "$_jcrr_key" ]; then
          printf '%s\n' "$_jcrr_v"
          _jcrr_found="yes"
        fi
        ;;
      *)
        : # linha sem '=' — ignorada (nao invalida o arquivo, diferente de P2)
        ;;
    esac
  done < "$_jcrr_file"
  [ "$_jcrr_found" = "yes" ]
}

_jc_cmd_resolve_path() {
  if ! _jcrp_effective=$(_jc_resolve_config_path); then
    _jc_die "config ausente: nem $_JC_CONFIG_FILE nem a worktree principal (plugin inativo)" 3
  fi
  # SEMPRE absoluto: a worktree principal ja vem absoluta (via
  # --path-format=absolute), mas o caminho local (`_JC_CONFIG_FILE`) e
  # relativo por padrao ("./.claude/cstk-jira/config") — resolve-path e
  # feito para ser consumido por OUTRO processo/cwd (ex.: hooks que
  # resolvem o config num subshell `cd "$cwd" && jira-config.sh
  # resolve-path` e depois usam o resultado FORA daquele subshell, ja de
  # volta no cwd original do processo). Um path relativo vazaria esse
  # detalhe e apontaria para o lugar errado (bug real medido r02 FASE 20
  # tarefa 20.1.2: `grep` no `sync_autonomous` lia um arquivo inexistente
  # relativo ao cwd do hook, nao ao cwd resolvido).
  case "$_jcrp_effective" in
    /*) printf '%s\n' "$_jcrp_effective" ;;
    ./*) printf '%s/%s\n' "$(pwd)" "${_jcrp_effective#./}" ;;
    *) printf '%s/%s\n' "$(pwd)" "$_jcrp_effective" ;;
  esac
  return 0
}

_jc_cmd_get() {
  [ "$#" -ge 1 ] || _jc_die_usage "get requer KEY"
  _jcg_key="$1"
  _jcg_file=$(_jc_resolve_config_path) \
    || _jc_die "config ausente: nem $_JC_CONFIG_FILE nem a worktree principal (plugin inativo)" 3
  if ! _jc_read_raw "$_jcg_key" "$_jcg_file"; then
    _jc_die "chave nao encontrada: $_jcg_key" 1
  fi
  return 0
}

# Campos obrigatorios de ProjectConfig (data-model.md, coluna Obrigatorio
# = "sim"; stage_status.<stage> e opcional, fora desta lista).
_JC_REQUIRED_FIELDS="config_version site_host project_key board_id \
issue_type_epic issue_type_task issue_type_subtask \
status_pending status_in_progress status_pass status_fail sync_autonomous"

# _jc_is_bare_hostname VALUE -> exit 0 se VALUE e um hostname puro (sem
# esquema, path, porta ou userinfo) — charset [A-Za-z0-9.-] apenas, que ja
# exclui ':', '/', '@' e espacos por construcao.
_jc_is_bare_hostname() {
  case "$1" in
    '') return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9.-]*) return 1 ;;
  esac
  return 0
}

# _jc_check_enum FIELD FILE ALLOWED... — r02 FASE 21 tarefa 21.4.1
# (data-model.md ProjectConfig "Validation rules (novas)"): chave AUSENTE
# ou VAZIA continua valida (o DEFAULT documentado e aplicado por quem LE,
# nunca por este script — ADITIVO, nao quebra config r01/r02 sem as
# chaves novas); chave PRESENTE com valor fora de ALLOWED... => exit 1
# citando a chave.
_jc_check_enum() {
  _jce_field="$1"
  _jce_file="$2"
  shift 2
  _jce_val=$(_jc_read_raw "$_jce_field" "$_jce_file" 2>/dev/null) || _jce_val=""
  [ -z "$_jce_val" ] && return 0
  for _jce_allowed in "$@"; do
    [ "$_jce_val" = "$_jce_allowed" ] && return 0
  done
  _jc_die "valor invalido para $_jce_field (esperado um de: $*, obtido '$_jce_val')" 1
}

_jc_cmd_validate() {
  _jcv_file=$(_jc_resolve_config_path) \
    || _jc_die "config ausente: nem $_JC_CONFIG_FILE nem a worktree principal (plugin inativo)" 3

  for _jcv_field in $_JC_REQUIRED_FIELDS; do
    _jcv_val=$(_jc_read_raw "$_jcv_field" "$_jcv_file" 2>/dev/null) || _jcv_val=""
    if [ -z "$_jcv_val" ]; then
      _jc_die "campo obrigatorio ausente ou vazio: $_jcv_field" 1
    fi
  done

  _jcv_site_host=$(_jc_read_raw site_host "$_jcv_file")
  if ! _jc_is_bare_hostname "$_jcv_site_host"; then
    _jc_die "site_host invalido (esperado hostname puro, sem esquema/path/porta/userinfo): $_jcv_site_host" 1
  fi

  _jcv_status_pass=$(_jc_read_raw status_pass "$_jcv_file")
  _jcv_status_fail=$(_jc_read_raw status_fail "$_jcv_file")
  if [ "$_jcv_status_pass" = "$_jcv_status_fail" ]; then
    _jc_die "status_fail e status_pass sao iguais ('$_jcv_status_pass') — crie um status distinto no workflow do projeto Jira para representar falha" 1
  fi

  # r02 FASE 21 tarefa 21.4.1 (data-model.md ProjectConfig "Validation
  # rules (novas)" + plan.md Convencoes de Borda SEC-6/SEC-1): chaves
  # novas opcionais — ausente/vazia continua valida (default aplicado por
  # quem le); presente fora do enum/allowlist => exit 1 citando a chave.
  _jc_check_enum milestone_mode "$_jcv_file" auto off
  _jc_check_enum labels_enabled "$_jcv_file" on off
  _jc_check_enum fix_versions_on_subtask "$_jcv_file" on off
  _jc_check_enum links_enabled "$_jcv_file" on off
  _jc_check_enum project_create "$_jcv_file" gated never

  # SEC-6: milestone_release, quando presente, casa
  # ^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$ (mesma allowlist de
  # jira-io.sh validate-version-name).
  _jcv_milestone_release=$(_jc_read_raw milestone_release "$_jcv_file" 2>/dev/null) || _jcv_milestone_release=""
  if [ -n "$_jcv_milestone_release" ]; then
    case "$_jcv_milestone_release" in
      [A-Za-z0-9]*) : ;;
      *) _jc_die "milestone_release fora da allowlist SEC-6 (^[A-Za-z0-9][A-Za-z0-9._-]{0,254}\$) — deve comecar com alfanumerico: '$_jcv_milestone_release'" 1 ;;
    esac
    _jcv_mr_len=${#_jcv_milestone_release}
    if [ "$_jcv_mr_len" -gt 255 ]; then
      _jc_die "milestone_release excede 255 caracteres (SEC-6)" 1
    fi
    case "$_jcv_milestone_release" in
      *[!A-Za-z0-9._-]*)
        _jc_die "milestone_release fora da allowlist SEC-6 (^[A-Za-z0-9][A-Za-z0-9._-]{0,254}\$): '$_jcv_milestone_release'" 1
        ;;
    esac
  fi

  # SEC-1: link_type_id, quando presente, casa a allowlist FECHADA
  # [A-Za-z0-9_-] (mesma allowlist de jira-io.sh validate-segment).
  _jcv_link_type_id=$(_jc_read_raw link_type_id "$_jcv_file" 2>/dev/null) || _jcv_link_type_id=""
  if [ -n "$_jcv_link_type_id" ]; then
    case "$_jcv_link_type_id" in
      *[!A-Za-z0-9_-]*)
        _jc_die "link_type_id fora da allowlist SEC-1 ([A-Za-z0-9_-]): '$_jcv_link_type_id'" 1
        ;;
    esac
  fi

  return 0
}

_jc_cmd_credential_check() {
  if [ ! -f "$_JC_CRED_FILE" ]; then
    _jc_die "credencial ausente: $_JC_CRED_FILE" 4
  fi
  # GNU (-c) primeiro, fallback BSD (-f) — mesma ordem de cli/lib/recall.sh
  # (BSD stat falha limpo em '-c' e cai no '-f'; a ordem inversa e o gotcha
  # ja documentado no projeto).
  _jccc_mode=$(stat -c '%a' -- "$_JC_CRED_FILE" 2>/dev/null) \
    || _jccc_mode=$(stat -f '%Lp' -- "$_JC_CRED_FILE" 2>/dev/null) \
    || _jccc_mode=""
  if [ -z "$_jccc_mode" ]; then
    _jc_die "nao foi possivel determinar a permissao de $_JC_CRED_FILE" 4
  fi
  if [ "$_jccc_mode" != "600" ]; then
    _jc_die "credencial com permissao insegura (esperado 0600, obtido 0$_jccc_mode): $_JC_CRED_FILE" 4
  fi
  return 0
}

# --- dispatcher ---------------------------------------------------------

_jc_sub="${1:-}"
[ "$#" -ge 1 ] && shift || :

case "$_jc_sub" in
  ''|-h|--help|help)
    _jc_usage
    exit 0
    ;;
  get)
    _jc_cmd_get "$@"
    ;;
  validate)
    _jc_cmd_validate "$@"
    ;;
  resolve-path)
    _jc_cmd_resolve_path "$@"
    ;;
  credential-check)
    _jc_cmd_credential_check "$@"
    ;;
  *)
    _jc_die_usage "subcomando desconhecido: $_jc_sub (validos: get, validate, resolve-path, credential-check)"
    ;;
esac
