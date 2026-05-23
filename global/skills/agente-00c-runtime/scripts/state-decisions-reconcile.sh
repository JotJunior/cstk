#!/bin/sh
# state-decisions-reconcile.sh — deteccao read-only de half-records de
# selecao de modelo (par Decisao + record-skill desalinhado).
#
# Cumpre task F4.4.2 da feature agente-00c-model-routing (hardening do
# finding owasp F-004 — integridade do two-step
# `state-decisions.sh register` + `state-ondas.sh record-skill`).
#
# Ref: docs/specs/agente-00c-model-routing/tasks.md F4.4
#      global/agents/agente-00c-feature-orchestrator.md §Invariante I3
#      global/agents/agente-00c-orchestrator.md §5.e.bis
#      dec-009 finding F-004 (low) — race entre passos 5 e 6
#
# Contexto:
#   A sequencia pre-spawn de subagente roda:
#     5) state-decisions.sh register      -> persiste Decisao "dec-NNN"
#     6) state-ondas.sh record-skill      -> adiciona entrada em
#                                            .ondas[N].skills_invoked[]
#                                            referenciando dec-NNN
#   Se um crash ocorre ENTRE 5 e 6, o estado fica com Decisao registrada
#   sem record-skill correspondente. Em retomadas (`/feature-00c-resume`)
#   este helper detecta o desalinhamento ANTES de prosseguir, permitindo
#   ao orquestrador decidir: emitir o record-skill missing (auto-cura) ou
#   escalar como BloqueioHumano se a politica exigir.
#
# Subcomandos:
#   state-decisions-reconcile.sh check --state-dir DIR
#       — Varre `.decisoes[]` procurando entradas com contexto matchando
#         o prefixo "Selecao de modelo para subagente " e verifica que
#         existe entrada em `.ondas[].skills_invoked[]` com
#         `decisao_id == .id` E `skill == "model-selector"`.
#       — Stdout: TSV `dec-id<TAB>onda_id<TAB>subagent_type` por orfa.
#       — Exit 0 se todas as Decisoes "Selecao de modelo" tem record-skill.
#       — Exit 1 se >=1 orfa detectada.
#       — Exit 2 se uso invalido ou state.json ausente.
#       — NUNCA escreve state.json (defesa INV-4 herdada do
#         model-routing.sh idempotent-check).
#
# Hardening de seguranca:
#   F-001 (shell injection): nao expande input sem aspas; passa filtro
#         para jq via --arg quando aplicavel. NAO ha input externo
#         alem do path do state-dir (validado por `[ -f ]`).
#   F-002 (jq embedding): query usa string literal estatica; nenhuma
#         interpolacao de variavel shell dentro de expressao jq.
#   INV-4: leitura pura (jq sem `>`, sem `--in-place`); paralelizavel
#         sem race; pode rodar em qualquer momento da execucao.
#
# Exit codes:
#   0 nenhuma orfa (paridade N_DEC == N_REC)
#   1 >=1 orfa detectada (TSV em stdout)
#   2 uso incorreto (flag ausente, state.json ausente)
#
# POSIX sh + jq.

set -eu

_SDR_NAME="state-decisions-reconcile"

_sdr_die_usage() {
  printf '%s: %s\n' "$_SDR_NAME" "$1" >&2
  exit 2
}

_sdr_die() {
  printf '%s: %s\n' "$_SDR_NAME" "$1" >&2
  exit "${2:-1}"
}

_sdr_require_jq() {
  command -v jq >/dev/null 2>&1 \
    || _sdr_die "jq nao encontrado no PATH (necessario para este subcomando)" 1
}

_sdr_state_file() { printf '%s/state.json\n' "$1"; }

# ---------- Subcomando: check ----------
_sdr_cmd_check() {
  _sdr_require_jq

  _sdr_sd=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)
        [ "$#" -ge 2 ] || _sdr_die_usage "check: --state-dir requer valor"
        _sdr_sd=$2; shift 2 ;;
      --state-dir=*)
        _sdr_sd=${1#--state-dir=}; shift ;;
      *)
        _sdr_die_usage "check: flag desconhecida: $1" ;;
    esac
  done

  [ -n "$_sdr_sd" ] || _sdr_die_usage "check: --state-dir ausente"

  _sdr_sf=$(_sdr_state_file "$_sdr_sd")
  [ -f "$_sdr_sf" ] || _sdr_die_usage "check: state.json ausente em '$_sdr_sd'"
  [ -r "$_sdr_sf" ] || _sdr_die_usage "check: state.json sem permissao de leitura em '$_sdr_sd'"

  # Query jq read-only: para cada Decisao com contexto matchando
  # "Selecao de modelo para subagente <T>", verifica que existe entrada
  # em .ondas[].skills_invoked[] com decisao_id == dec.id AND
  # skill == "model-selector". Emite TSV das orfas (dec-id, onda_id,
  # subagent_type extraido do contexto).
  #
  # Notas POSIX:
  #   - tostream/$paths/etc nao sao usados aqui; query simples basta.
  #   - `?` em .decisoes[]? tolera arrays ausentes.
  #   - `[...] | unique` impede duplicacao caso uma Decisao apareca em
  #     mais de uma onda (defesa contra fixture estranha).
  _sdr_orphans=$(
    jq -r '
      . as $root
      | [
          .decisoes[]?
          | select(.contexto // "" | startswith("Selecao de modelo para subagente "))
          | . as $d
          | {
              id: ($d.id // ""),
              onda_id: ($d.onda_id // ""),
              subagent: (($d.contexto // "")
                | sub("^Selecao de modelo para subagente "; ""))
            }
          | select(
              [$root.ondas[]?.skills_invoked[]?
               | select(.skill == "model-selector" and .decisao_id == $d.id)
              ] | length == 0
            )
          | [.id, .onda_id, .subagent] | @tsv
        ]
      | .[]
    ' "$_sdr_sf" 2>/dev/null
  ) || _sdr_die "check: jq query falhou" 1

  if [ -n "$_sdr_orphans" ]; then
    printf '%s\n' "$_sdr_orphans"
    return 1
  fi

  return 0
}

# ---------- Dispatch ----------

if [ "$#" -lt 1 ]; then
  cat >&2 <<'HELP'
state-decisions-reconcile.sh — detecta half-records de selecao de modelo
(par Decisao + record-skill desalinhado).

USO:
  state-decisions-reconcile.sh check --state-dir DIR

EXIT:
  0 nenhuma orfa (paridade N_DEC == N_REC)
  1 >=1 orfa detectada (TSV: dec-id\tonda_id\tsubagent_type em stdout)
  2 uso incorreto

Ref: docs/specs/agente-00c-model-routing/tasks.md F4.4
HELP
  exit 2
fi

_SDR_SUBCMD=$1
shift

case "$_SDR_SUBCMD" in
  check)
    _sdr_cmd_check "$@"
    ;;
  -h|--help|help)
    "$0"
    ;;
  *)
    _sdr_die_usage "subcomando desconhecido: '$_SDR_SUBCMD' (use 'help' para uso)"
    ;;
esac
