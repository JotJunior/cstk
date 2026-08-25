#!/bin/sh
# converge-tasks.sh — mecanica deterministica do `tasks.md` para a skill
# `converge` (FR-008, FR-009, FR-010, FR-011, FR-012).
#
# Ref: docs/specs/skill-converge/contracts/converge-interfaces.md §4
#      docs/specs/skill-converge/data-model.md §Entity Gap / §ConvergencePhase
#      docs/specs/skill-converge/research.md Decision 2 (fronteira de
#      idempotencia) + Decision 6 (sem acoplar a agente-00c-runtime)
#      docs/specs/skill-converge/tasks.md tarefa 2.5 (consome normalize()
#      da tarefa 1.1)
#
# Subcomandos:
#
#   converge-tasks.sh next-phase --tasks <tasks.md>
#       Imprime max(FASE N existente) + 1. Distinto de
#       create-tasks/scripts/next-task-id.sh [REAL], que calcula a proxima
#       TAREFA dentro de uma fase, nao a proxima FASE.
#
#   converge-tasks.sh existing-keys --tasks <tasks.md>
#       Imprime (uma por linha) as `converge-key` ja presentes, parseando
#       marcadores `<!-- converge-key: ... -->` gravados por execucoes
#       anteriores. Base do dedup (FR-012). Nao imprime nada (exit 0) se a
#       feature nunca foi convergida.
#
#   converge-tasks.sh append-phase --tasks <tasks.md> --phase-file <novaFase.md>
#       Anexa <novaFase.md> ao FINAL de <tasks.md> (append-only, FR-009).
#       MUST falhar exit 1 SEM ESCREVER se <novaFase.md> estiver vazio
#       (guarda FR-010). Escrita atomica (mktemp + mv), preserva integralmente
#       o conteudo pre-existente (SC-005) — normaliza apenas a whitespace
#       final (newlines finais) para exatamente uma linha em branco antes da
#       fase apendada, texto em si nunca e alterado.
#
#   converge-tasks.sh gap-key --path <p> --type <t> --origin <o>
#       Calcula e imprime UMA gap_key nova:
#       sha256-12(normalize(path) + " " + type + " " + normalize(origin)).
#       Responsabilidade distinta de existing-keys: gap-key CALCULA uma
#       chave a partir de um Gap recem-classificado; existing-keys so LE
#       marcadores ja gravados — nunca se sobrepoem. --type MUST estar no
#       enum fechado (mesmo de severity.sh); fora dele ⇒ exit 2.
#
# --- Reuso obrigatorio de create-tasks/scripts/next-task-id.sh [REAL] ---
# A numeracao INDIVIDUAL das tarefas dentro da fase apendada (task_id =
# "{N}.{M}" sequencial, data-model.md §ConvergenceTask) e responsabilidade
# de QUEM MONTA o <novaFase.md> ANTES de chamar append-phase (a SKILL.md
# agente-driven da FASE 3, ou um fixture de teste que exercite o mesmo
# padrao) — nunca deste script. O padrao correto e invocar
# `next-task-id.sh <N> <arquivo-da-fase-em-construcao>` (nao o tasks.md
# inteiro) apos cada tarefa apendada ao arquivo em construcao: a primeira
# chamada retorna "N.1" (prefixo N ainda ausente ⇒ MAX=0), a segunda
# (apos a 1a tarefa ja estar no arquivo) retorna "N.2", e assim por
# diante — iterativo, sem duplicar logica de numeracao aqui (nao
# reinventar, tasks.md preambulo). append-phase trata <novaFase.md> como
# blob de markdown OPACO ja numerado: nao parseia, nao renumera, so
# valida nao-vazio e anexa. tests/test_converge-tasks.sh demonstra esse
# padrao de reuso fim-a-fim antes de chamar append-phase.
#
# --- Definicao de normalize() (data-model.md, fecha CHK011) ---
# gap_key combina DOIS campos distintos (path, origin), cada um com sua
# propria regra de normalizacao PURAMENTE TEXTUAL (nunca resolve via
# filesystem — distinto de path-contains.sh, que resolve symlinks para
# contencao de blast radius, proposito diferente):
#
#   normalize(path): trim -> remove prefixo "./" -> colapsa "//"+ em "/"
#     -> remove "/" final (exceto raiz "/") -> SEM case-fold (paths sao
#     case-sensitive; macOS e case-insensitive-mas-preserving no
#     filesystem, mas esta e uma comparacao TEXTUAL sobre a string
#     declarada, nao uma resolucao via filesystem).
#
#   normalize(origin): trim -> uppercase do prefixo "FR-"/"fr-"/"Fr-"
#     quando origin e um requisito -> quando origin e um heading de task
#     ("### N.M Titulo..." ou "N.M Titulo..."), reduz a forma "N.M"
#     (remove "### " se presente + todo texto de titulo apos o primeiro
#     token N.M). Idempotente: normalize(normalize(x)) == normalize(x).
#
# Exemplos de equivalencia (mesma gap_key resultante):
#   ./scripts/foo.sh ≡ scripts/foo.sh ≡ scripts//foo.sh
#   fr-007 ≡ FR-007 ≡ Fr-007
#   "### 2.1 scripts/path-contains.sh — contencao... [C]" ≡ "2.1"
#
# --- sha256-12: hash proprio, sem acoplar a agente-00c-runtime/_hash.sh ---
# research.md Decision 6: converge traz mecanica MINIMA e PROPRIA (aqui,
# deteccao Linux/Darwin identica ao padrao ja usado em
# agente-00c-runtime/scripts/_hash.sh e cli/lib/compat.sh) em vez de
# depender de outro skill em modo standalone (FR-014, SC-006 — completa
# sem orquestrador ativo). Duplicacao deliberada de ~10 linhas evita
# acoplar o caminho standalone-critico a outro skill.
#
# EXIT (todos os subcomandos): 0 ok | 1 erro de I/O / entrada invalida
#                               | 2 erro de uso
#
# POSIX sh + awk (ferramentas POSIX canonicas, Constitution II). Zero eval
# sobre conteudo lido/argumentos (SEC-1) — dados untrusted (path/origin de
# um Gap classificado, conteudo pre-existente de tasks.md) sao tratados
# SEMPRE como texto literal via printf '%s'/awk, nunca interpretados como
# codigo. Todas as variaveis quotadas. Sem Bash-isms.

set -eu

_CT_NAME="converge-tasks"

_ct_usage() {
  cat <<'USAGE' >&2
Uso: converge-tasks.sh <subcomando> [flags]

Subcomandos:
  next-phase    --tasks <tasks.md>
  existing-keys --tasks <tasks.md>
  append-phase  --tasks <tasks.md> --phase-file <novaFase.md>
  gap-key       --path <p> --type <missing|partial|contradicts|unrequested> --origin <o>

Exit: 0 ok | 1 erro de I/O / entrada invalida | 2 erro de uso
USAGE
}

_ct_die_usage() {
  printf '%s: %s\n' "$_CT_NAME" "$1" >&2
  exit 2
}

_ct_die_io() {
  printf '%s: %s\n' "$_CT_NAME" "$1" >&2
  exit 1
}

# ---------- normalize(path) / normalize(origin) (data-model.md) ----------

_ct_normalize_path() {
  # $1 = path (dado untrusted, tratado como texto literal via printf '%s')
  printf '%s' "$1" | awk '
    {
      p = $0
      sub(/^[ \t]+/, "", p)
      sub(/[ \t]+$/, "", p)
      sub(/^\.\//, "", p)
      gsub(/\/\/+/, "/", p)
      if (p != "/") sub(/\/$/, "", p)
      print p
    }
  '
}

_ct_normalize_origin() {
  # $1 = origin (dado untrusted, tratado como texto literal via printf '%s')
  printf '%s' "$1" | awk '
    {
      o = $0
      sub(/^[ \t]+/, "", o)
      sub(/[ \t]+$/, "", o)
      # Heading de task: remove prefixo "### " se presente, depois checa
      # se o PRIMEIRO token (delimitado por espaco) casa "N.M" — se sim,
      # reduz a so esse token, descartando todo texto de titulo (nunca
      # fabrica associacao: so reduz o que ja esta literalmente presente).
      sub(/^### /, "", o)
      n = split(o, toks, /[ \t]+/)
      if (n >= 1 && toks[1] ~ /^[0-9]+\.[0-9]+$/) {
        print toks[1]
        next
      }
      # Requisito: uppercase do prefixo FR- (digitos preservados como estao).
      if (o ~ /^[Ff][Rr]-[0-9]+/) {
        sub(/^[Ff][Rr]-/, "FR-", o)
      }
      print o
    }
  '
}

# ---------- sha256-12 (proprio, ver comentario de cabecalho) ----------

_ct_sha256_12() {
  # $1 = string arbitraria (dado untrusted, tratado como texto literal).
  # Imprime 12 chars hex minusculos. Exit 1 se SO nao suportado.
  _ct_os=$(uname -s 2>/dev/null)
  case "$_ct_os" in
    # MINGW*/MSYS*/CYGWIN* (Git Bash & cia no Windows) reusam o mesmo
    # sha256sum do Linux — presente e funcional nesses ambientes (issue #157).
    Linux|MINGW*|MSYS*|CYGWIN*)
      printf '%s' "$1" | sha256sum | awk '{print substr($1,1,12)}'
      ;;
    Darwin)
      printf '%s' "$1" | shasum -a 256 | awk '{print substr($1,1,12)}'
      ;;
    *)
      _ct_die_io "SO nao suportado para sha256: $_ct_os (esperado Linux|Darwin|MINGW*|MSYS*|CYGWIN*)"
      ;;
  esac
}

# ---------- next-phase ----------

_ct_cmd_next_phase() {
  _tasks=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tasks)
        [ "$#" -ge 2 ] || _ct_die_usage "--tasks requer valor"
        _tasks=$2
        shift 2
        ;;
      -h | --help)
        _ct_usage
        exit 0
        ;;
      *) _ct_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_tasks" ] || _ct_die_usage "--tasks e obrigatorio"
  [ -f "$_tasks" ] || _ct_die_io "tasks.md ausente: $_tasks"

  awk '
    /^## FASE [0-9]+/ {
      line = $0
      sub(/^## FASE /, "", line)
      split(line, parts, /[ \t]+/)
      n = parts[1] + 0
      if (n > max) max = n
    }
    END { print max + 1 }
  ' "$_tasks"
}

# ---------- existing-keys ----------

_ct_cmd_existing_keys() {
  _tasks=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tasks)
        [ "$#" -ge 2 ] || _ct_die_usage "--tasks requer valor"
        _tasks=$2
        shift 2
        ;;
      -h | --help)
        _ct_usage
        exit 0
        ;;
      *) _ct_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_tasks" ] || _ct_die_usage "--tasks e obrigatorio"
  [ -f "$_tasks" ] || _ct_die_io "tasks.md ausente: $_tasks"

  awk '
    /<!-- converge-key: [^ ]+ -->/ {
      line = $0
      while (match(line, /<!-- converge-key: [^ ]+ -->/)) {
        seg = substr(line, RSTART, RLENGTH)
        key = seg
        sub(/^<!-- converge-key: /, "", key)
        sub(/ -->$/, "", key)
        print key
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$_tasks"
}

# ---------- append-phase ----------

_ct_cmd_append_phase() {
  _tasks=""
  _phase_file=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tasks)
        [ "$#" -ge 2 ] || _ct_die_usage "--tasks requer valor"
        _tasks=$2
        shift 2
        ;;
      --phase-file)
        [ "$#" -ge 2 ] || _ct_die_usage "--phase-file requer valor"
        _phase_file=$2
        shift 2
        ;;
      -h | --help)
        _ct_usage
        exit 0
        ;;
      *) _ct_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_tasks" ] || _ct_die_usage "--tasks e obrigatorio"
  [ -n "$_phase_file" ] || _ct_die_usage "--phase-file e obrigatorio"
  [ -f "$_tasks" ] || _ct_die_io "tasks.md ausente: $_tasks"
  [ -f "$_phase_file" ] || _ct_die_io "phase-file ausente: $_phase_file"

  # Guarda FR-010: nunca apenda fase vazia — falha SEM escrever.
  if [ ! -s "$_phase_file" ]; then
    _ct_die_io "phase-file vazio, nada apendado (guarda FR-010): $_phase_file"
  fi

  # Append-only (FR-009) via mktemp+mv atomico (mesmo padrao de
  # agente-00c-runtime/scripts/state-rw.sh::_sr_atomic_write) — preserva
  # todo o conteudo pre-existente, nunca trunca tasks.md em caso de falha
  # a meio da escrita.
  #
  # Separador: a substituicao de comando "$(cat -- "$_tasks")" remove TODAS
  # as newlines finais (comportamento POSIX de command substitution) — o
  # "%s\n\n" seguinte repoe exatamente UMA linha em branco antes da fase
  # nova, independente de tasks.md original terminar sem newline, com uma
  # unica newline, ou com varias linhas em branco finais (normaliza os 3
  # casos para o mesmo separador consistente). O conteudo capturado e dado
  # opaco (SEC-1): "%s" nunca reinterpreta `$(...)`/backtick/`;` presentes
  # no texto pre-existente como sintaxe de shell.
  _tmp=$(mktemp -- "${_tasks}.XXXXXX") || _ct_die_io "mktemp falhou em $(dirname -- "$_tasks")"
  if ! _ct_body=$(cat -- "$_tasks" 2>/dev/null); then
    rm -f -- "$_tmp" 2>/dev/null || :
    _ct_die_io "falha ao ler $_tasks"
  fi
  if ! printf '%s\n\n' "$_ct_body" > "$_tmp"; then
    rm -f -- "$_tmp" 2>/dev/null || :
    _ct_die_io "falha ao escrever conteudo normalizado em arquivo temporario"
  fi
  if ! cat -- "$_phase_file" >> "$_tmp"; then
    rm -f -- "$_tmp" 2>/dev/null || :
    _ct_die_io "falha ao apendar phase-file"
  fi
  if ! mv -f -- "$_tmp" "$_tasks"; then
    rm -f -- "$_tmp" 2>/dev/null || :
    _ct_die_io "mv atomico falhou: $_tmp -> $_tasks"
  fi
}

# ---------- gap-key ----------

_ct_cmd_gap_key() {
  _path=""
  _type=""
  _origin=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --path)
        [ "$#" -ge 2 ] || _ct_die_usage "--path requer valor"
        _path=$2
        shift 2
        ;;
      --type)
        [ "$#" -ge 2 ] || _ct_die_usage "--type requer valor"
        _type=$2
        shift 2
        ;;
      --origin)
        [ "$#" -ge 2 ] || _ct_die_usage "--origin requer valor"
        _origin=$2
        shift 2
        ;;
      -h | --help)
        _ct_usage
        exit 0
        ;;
      *) _ct_die_usage "flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_path" ] || _ct_die_usage "--path e obrigatorio"
  [ -n "$_type" ] || _ct_die_usage "--type e obrigatorio"
  [ -n "$_origin" ] || _ct_die_usage "--origin e obrigatorio"

  case "$_type" in
    missing | partial | contradicts | unrequested) ;;
    *) _ct_die_usage "--type fora do enum (missing|partial|contradicts|unrequested): $_type" ;;
  esac

  _np=$(_ct_normalize_path "$_path")
  _no=$(_ct_normalize_origin "$_origin")
  _ct_sha256_12 "${_np} ${_type} ${_no}"
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  _ct_usage
  exit 2
fi

_CT_SUBCMD=$1
shift

case "$_CT_SUBCMD" in
  next-phase) _ct_cmd_next_phase "$@" ;;
  existing-keys) _ct_cmd_existing_keys "$@" ;;
  append-phase) _ct_cmd_append_phase "$@" ;;
  gap-key) _ct_cmd_gap_key "$@" ;;
  -h | --help | help)
    _ct_usage
    exit 0
    ;;
  *) _ct_die_usage "subcomando desconhecido: $_CT_SUBCMD" ;;
esac
