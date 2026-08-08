#!/bin/sh
# test_model_selector_zero_rede.sh
#
# Cobre subtarefas 5.1.1 e 5.1.2 da feature `model-selector` (FR-016,
# SC-005, CHK046, CHK047, CHK049). Garante que a skill nao contem
# QUALQUER primitiva de rede em codigo executavel — operacao offline-
# only (Principio IV).
#
# Por que isso e invariante (FR-016, SC-005):
#   A skill `model-selector` precisa rodar em ambientes sem acesso a
#   rede (containers fechados, CI air-gapped, machines de dev offline).
#   Coleta remota tambem viola Principio IV (Blast Radius Confinado) —
#   uma skill local nao deve vazar input do operador para qualquer host
#   externo. A unica forma estatica de garantir isso e regex de
#   primitivas conhecidas: curl, wget, http URLs, nc, /dev/tcp, ssh,
#   getent hosts, dig, host(1).
#
# Mecanismo (CHK049):
#   `grep -rn` estatico sobre `plugins/cstk/skills/model-selector/`,
#   filtrando comentarios shell via `grep -v '^[[:space:]]*#'` (resolve
#   CHK047 — falsos positivos em texto explicativo nao quebram o teste).
#   Sandbox/unshare/strace e overkill para o MVP — uma skill POSIX
#   puro que nao referencia nenhuma primitiva de rede no codigo
#   executavel nao consegue criar conexao alguma.
#
# Cobertura (CHK046 estende as primitivas alem do trio basico curl/
# wget/nc):
#   curl, wget, http (URLs http:// ou https://), nc (netcat),
#   /dev/tcp (bash redirection feature), ssh, getent hosts (dns query
#   via NSS), dig, host (DNS resolvers).
#
# Limitacoes intencionais:
#   - Filtro `grep -v '^[[:space:]]*#'` so descarta comentarios shell
#     que INICIAM a linha com `#` (apos espacos opcionais). Comentarios
#     in-line `cmd # foo` continuam visiveis — proposital, porque
#     `cmd` ainda e executavel.
#   - Filtro NAO entende blocos `<<EOF` de heredoc. Como a skill nao
#     usa heredocs com primitivas de rede, isso e aceitavel para MVP.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_DIR="$REPO_ROOT/plugins/cstk/skills/model-selector"
export SKILL_DIR

# Padrao alvo: alternativas separadas por `\|` (ERE basico para grep -E
# tambem aceita, mas mantemos BRE compativel com grep base POSIX).
NET_PATTERN='curl\|wget\|http\|nc \|/dev/tcp\|ssh \|getent hosts\|dig \|host '

scenario_5_1_1_skill_dir_sem_primitiva_de_rede() {
  if [ ! -d "$SKILL_DIR" ]; then
    _error "skill_dir_ausente" "esperado $SKILL_DIR"
    return 2
  fi
  # grep -rn em TODO o diretorio da skill (SKILL.md, scripts/,
  # references/, examples/). Filtra comentarios shell que comecam com
  # `#` apos whitespace opcional (resolve CHK047).
  _hits=$(grep -rn "$NET_PATTERN" "$SKILL_DIR" 2>/dev/null \
            | grep -v '^[^:]*:[[:space:]]*[0-9][0-9]*:[[:space:]]*#' \
            || true)
  if [ -n "$_hits" ]; then
    _fail "primitiva_de_rede_detectada" \
      "padrao=$NET_PATTERN; matches=$_hits"
    return 1
  fi
}

# Cobertura adicional: scripts/ executavel (foco no caminho hot). O
# scenario acima ja cobre, mas mantemos um especifico para reportar
# violacao distinta caso a violacao seja em codigo (mais grave que em
# doc/exemplos).
scenario_5_1_1_scripts_executavel_sem_primitiva_de_rede() {
  _scripts="$SKILL_DIR/scripts"
  if [ ! -d "$_scripts" ]; then
    _error "scripts_ausentes" "esperado $_scripts"
    return 2
  fi
  _hits=$(grep -rn "$NET_PATTERN" "$_scripts" 2>/dev/null \
            | grep -v '^[^:]*:[[:space:]]*[0-9][0-9]*:[[:space:]]*#' \
            || true)
  if [ -n "$_hits" ]; then
    _fail "primitiva_de_rede_em_scripts_executavel" \
      "padrao=$NET_PATTERN; matches=$_hits"
    return 1
  fi
}

run_all_scenarios
