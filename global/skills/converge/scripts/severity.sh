#!/bin/sh
# severity.sh — funcao pura de severidade para a skill `converge`
# (FR-006, FR-020).
#
# Ref: docs/specs/skill-converge/contracts/converge-interfaces.md §5
#      docs/specs/skill-converge/research.md Decision 3 (tabela)
#      docs/specs/skill-converge/data-model.md §Entity Gap (severity) +
#      §Derivação origin→story_priority (fecha CHK018 — priority=null/none
#      nunca escala para HIGH por omissao)
#      docs/specs/skill-converge/tasks.md tarefa 2.4
#
# USO:
#   severity.sh --type <missing|partial|contradicts|unrequested> \
#               --priority <P1|P2|P3|none> --must-violated <true|false>
#
# Funcao PURA: mesma entrada -> mesma saida, sem I/O de arquivo, sem estado,
# sem dependencia externa. Imprime em stdout exatamente uma linha:
# CRITICAL|HIGH|MEDIUM|LOW.
#
# --- Tabela de decisao (avaliada NESTA ordem — primeira que casa vence) ---
# research.md §Decision 3 + data-model.md §Derivação origin→story_priority:
#
#   1. --must-violated=true                        -> CRITICAL
#      Domina TUDO, inclusive `unrequested` (CHK023, tasks.md 2.4.3): a
#      regra "MUST vence tudo" nunca degrada para a linha 4 so porque o
#      tipo e `unrequested`. Avaliada PRIMEIRO, sem excecao.
#   2. --type=unrequested                           -> LOW (qualquer priority)
#      Codigo a mais e revisao, nao bloqueio (FR-020) — sempre LOW quando
#      nao ha violacao de MUST, independente de --priority.
#   3. --type em {missing,partial,contradicts}
#      + --priority=P1                              -> HIGH
#   4. --type em {missing,partial,contradicts}
#      + --priority em {P2,P3,none}                 -> MEDIUM
#      `none` (sem User Story associada — data-model.md: "nenhuma story
#      referencia o FR/task com confianca razoavel") cai no MESMO balde
#      conservador de P2/P3: a AUSENCIA de vinculo com P1 NUNCA escala
#      para HIGH por omissao (regra explicita do data-model.md, fecha
#      CHK018) — tratar `none` como HIGH seria inventar um sinal de alta
#      prioridade que a fonte nao afirma (Constitution VI).
#
# `partial` recebe a MESMA severidade que `missing`/`contradicts` na mesma
# prioridade (research.md: deferido pela FR-020, decidido aqui — um path
# parcialmente implementado numa story P1 e tao bloqueante quanto ausente).
#
# EXIT:
#   0  sucesso (imprime severidade)
#   2  erro de uso (flag ausente/desconhecida, ou valor fora do enum fechado)
#
# POSIX sh puro. Zero I/O de arquivo, zero eval, zero dependencia externa —
# superficie minima por design (3 flags enum-fechadas, validadas contra
# conjunto fechado antes de qualquer decisao). Todas as variaveis quotadas.
# Sem Bash-isms.

set -eu

_SV_NAME="severity"

_sv_usage() {
  cat <<'USAGE' >&2
Uso: severity.sh --type <missing|partial|contradicts|unrequested> \
                  --priority <P1|P2|P3|none> --must-violated <true|false>

Imprime em stdout exatamente uma linha: CRITICAL | HIGH | MEDIUM | LOW
Exit: 0 sucesso | 2 erro de uso (flag ausente ou valor fora do enum)
USAGE
}

_sv_die_usage() {
  printf '%s: %s\n' "$_SV_NAME" "$1" >&2
  exit 2
}

# ---------- Parse de flags ----------

_TYPE=""
_PRIORITY=""
_MUST=""

if [ "$#" -eq 0 ]; then
  _sv_usage
  exit 2
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --type)
      [ "$#" -ge 2 ] || _sv_die_usage "--type requer valor"
      _TYPE=$2
      shift 2
      ;;
    --priority)
      [ "$#" -ge 2 ] || _sv_die_usage "--priority requer valor"
      _PRIORITY=$2
      shift 2
      ;;
    --must-violated)
      [ "$#" -ge 2 ] || _sv_die_usage "--must-violated requer valor"
      _MUST=$2
      shift 2
      ;;
    -h | --help)
      _sv_usage
      exit 0
      ;;
    *)
      _sv_die_usage "flag desconhecida: $1"
      ;;
  esac
done

[ -n "$_TYPE" ] || _sv_die_usage "--type e obrigatorio"
[ -n "$_PRIORITY" ] || _sv_die_usage "--priority e obrigatorio"
[ -n "$_MUST" ] || _sv_die_usage "--must-violated e obrigatorio"

case "$_TYPE" in
  missing | partial | contradicts | unrequested) ;;
  *) _sv_die_usage "--type fora do enum (missing|partial|contradicts|unrequested): $_TYPE" ;;
esac

case "$_PRIORITY" in
  P1 | P2 | P3 | none) ;;
  *) _sv_die_usage "--priority fora do enum (P1|P2|P3|none): $_PRIORITY" ;;
esac

case "$_MUST" in
  true | false) ;;
  *) _sv_die_usage "--must-violated fora do enum (true|false): $_MUST" ;;
esac

# ---------- Tabela de decisao (ordem importa — primeira que casa vence) ----------

if [ "$_MUST" = "true" ]; then
  printf 'CRITICAL\n'
  exit 0
fi

if [ "$_TYPE" = "unrequested" ]; then
  printf 'LOW\n'
  exit 0
fi

if [ "$_PRIORITY" = "P1" ]; then
  printf 'HIGH\n'
  exit 0
fi

# --type em {missing, partial, contradicts} + --priority em {P2, P3, none}
printf 'MEDIUM\n'
exit 0
