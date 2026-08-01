# state.sh — subcomando `cstk state` (feature state-db-foundation, FASE 6).
#
# Ref: docs/specs/state-db-foundation/contracts/migration.md §Nomeacao
#      (dec-034: "B para a UX do operador, delegando a A a implementacao")
#
# Esta lib NAO implementa migracao: ela e a SUPERFICIE DE OPERADOR que delega
# a global/skills/agente-00c-runtime/scripts/state-db-migrate.sh, mantendo a
# logica testavel pelo harness POSIX do runtime e dando ao operador um verbo
# coerente com o resto do CLI.
#
# Por que `cstk state migrate` e nao `state-rw.sh migrate`: este ultimo JA
# EXISTE com outro significado (migracao do schema interno do state.json,
# pt-BR -> EN). Dois sentidos sob o mesmo verbo e armadilha de operador.
#
# Subcomandos:
#   cstk state migrate --state-dir DIR   — migra state.json -> state.db
#   cstk state enable-sqlite             — ativa state_backend=sqlite na
#                                           config global (feature
#                                           state-backend-config, FASE 4)
#
# `enable-sqlite` delega a cli/lib/config.sh (que por sua vez delega a
# global/skills/agente-00c-runtime/scripts/state-backend.sh) — mesma
# disciplina de delegacao pura de `migrate`: zero logica de decisao aqui.
#
# Exit codes (repassados VERBATIM do script delegado, para o operador poder
# distinguir "recusado" de "falhou"):
#   0 sucesso   1 falha   2 uso incorreto   3 recusado por pre-condicao (M1
#   para migrate; dependencia/capability ausente para enable-sqlite)
#
# POSIX sh puro. Sem bash-isms.

if [ -n "${_CSTK_STATE_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_STATE_LOADED=1

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
  # shellcheck source=./common.sh
  . "$CSTK_LIB/common.sh"
fi

if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/config.sh" ]; then
  # shellcheck source=./config.sh
  . "$CSTK_LIB/config.sh"
fi

# _state_migrate_script_path -> imprime o caminho de state-db-migrate.sh.
# Procura, em ordem: (1) PATH; (2) layout repo/CLI relativo a CSTK_LIB
# (cli/lib -> ../../global/skills/agente-00c-runtime/scripts); (3) layout
# instalado em ~/.claude/skills/agente-00c-runtime/scripts.
#
# A camada (2) e essencial fora de uma instalacao: testes e CI rodam o CLI da
# arvore do repo (CSTK_LIB=cli/lib) SEM ter o runtime em ~/.claude. Mesmo
# padrao (e mesma licao de campo) de recall_secrets_filter_path em recall.sh:
# resolver SO via ~/.claude passa local e quebra no CI fresh-checkout.
_state_migrate_script_path() {
  if command -v state-db-migrate.sh >/dev/null 2>&1; then
    command -v state-db-migrate.sh
    return 0
  fi
  if [ -n "${CSTK_LIB:-}" ]; then
    _sm_repo="$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/state-db-migrate.sh"
    if [ -f "$_sm_repo" ]; then
      printf '%s\n' "$_sm_repo"
      return 0
    fi
  fi
  _sm_default="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/state-db-migrate.sh"
  if [ -f "$_sm_default" ]; then
    printf '%s\n' "$_sm_default"
    return 0
  fi
  return 1
}

_state_usage() {
  cat <<'HELP'
cstk state — operacoes sobre o estado transacional de execucoes 00c

USO:
  cstk state migrate --state-dir DIR   Migra <DIR>/state.json para <DIR>/state.db
  cstk state enable-sqlite             Ativa state_backend=sqlite na config
                                        global (~/.claude/cstk/config)

MIGRATE:
  Migracao EXPLICITA e nunca automatica (FR-005). Recusa se a execucao estiver
  ativa (status em_andamento), se o estado for invalido, se a integridade do
  state.json divergir, ou se ja existir um state.db de outra execucao.
  O state.json de origem e sempre PRESERVADO como export/legado.

ENABLE-SQLITE:
  Ativa o backend SQLite para NOVAS inicializacoes de execucao 00c
  (state-rw.sh init). Verifica, nesta ordem, ANTES de qualquer escrita:
  sqlite3 no PATH, versao >= 3.45.1, e capability do runtime do catalogo
  instalado. Qualquer falha ⇒ config byte-a-byte inalterada, exit
  recusado por pre-condicao. Idempotente: se ja ativado, no-op, exit 0.

EXIT CODES:
  0 sucesso   1 falha   2 uso incorreto   3 recusado por pre-condicao
HELP
}

state_main() {
  _st_sub="${1:-}"
  [ "$#" -ge 1 ] && shift || :

  case "$_st_sub" in
    ''|-h|--help|help)
      _state_usage
      return 0
      ;;
    migrate)
      if ! _st_script=$(_state_migrate_script_path); then
        printf 'cstk state: state-db-migrate.sh nao encontrado.\n' >&2
        printf 'cstk state: instale o runtime 00c ("cstk install") ou rode a partir da arvore do repo.\n' >&2
        return 1
      fi
      # Delegacao pura: flags e exit code repassados verbatim. `sh "$script"`
      # (em vez de exec direto) evita depender do bit de execucao preservado
      # pelo empacotamento do tarball.
      sh "$_st_script" migrate "$@"
      return $?
      ;;
    enable-sqlite)
      if ! command -v config_state_backend_enable_sqlite >/dev/null 2>&1; then
        printf 'cstk state: cli/lib/config.sh nao carregado (CSTK_LIB indisponivel?).\n' >&2
        return 1
      fi
      # Delegacao pura via cli/lib/config.sh -> state-backend.sh
      # enable-sqlite; argumentos e exit code repassados verbatim.
      config_state_backend_enable_sqlite "$@"
      return $?
      ;;
    *)
      printf 'cstk state: subcomando desconhecido: %s\n' "$_st_sub" >&2
      printf 'Subcomandos validos: migrate, enable-sqlite\n' >&2
      return 2
      ;;
  esac
}
