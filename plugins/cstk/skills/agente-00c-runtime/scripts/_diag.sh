#!/bin/sh
# _diag.sh — envelope diagnostico uniforme (DiagnosticEnvelope) para os
# scripts POSIX do runtime (FR-012, FR-013, FR-014, FR-016).
#
# Ref: docs/specs/openspec-hygiene/spec.md FR-012..FR-016
#      docs/specs/openspec-hygiene/contracts/diagnostic-envelope.md
#
# NAO e executavel diretamente. Use (mesmo padrao de _log.sh/_hash.sh):
#   . "$(dirname -- "$0")/_diag.sh"
#   diag_emit <severity> <code> <message> <fix>
#
# Contrato:
#   severity  "error" | "warning" — qualquer outro valor e rejeitado.
#   code      kebab-case estavel por (script, condicao de falha); nao
#             validado por regex aqui (responsabilidade do call-site).
#   message   texto legivel por humano (pt-br permitido). `|` interno e
#             substituido por `/` antes de emitir.
#   fix       instrucao acionavel de proximo passo. MUST NOT ser identica
#             a `message` (FR-013) — rejeitado se igual. `|` interno e
#             substituido por `/`.
#
# Saida: 1 linha em stderr, ADITIVA a qualquer mensagem legada que o
# script chamador ja tenha emitido (FR-015, SC-006 — nunca substitui):
#   DIAG|<severity>|<code>|<message>|<fix>
#
# Zero dependencia de jq (FR-016, Constitution II — POSIX sh puro).
#
# Semantica de falha (best-effort — nunca mascara o erro original):
#   severity invalida, ou fix == message -> diag_emit avisa em stderr e
#   retorna 1 SEM emitir a linha DIAG| (evita envelope malformado). O
#   script chamador ja emitiu sua mensagem legada antes de chamar
#   diag_emit e prossegue para o proprio `exit` normalmente — callers sob
#   `set -eu` devem chamar `diag_emit ... || :` para nao abortar por causa
#   de uma falha de VALIDACAO do envelope (distinta do erro original).

# diag_emit SEVERITY CODE MESSAGE FIX
# Exit: 0 emitido; 1 severity invalida ou fix == message (nada emitido).
diag_emit() {
  _diag_severity="${1:-}"
  _diag_code="${2:-}"
  _diag_message="${3:-}"
  _diag_fix="${4:-}"

  case "$_diag_severity" in
    error|warning) ;;
    *)
      printf 'diag_emit: severity invalida: "%s" (esperado error|warning) — envelope DIAG nao emitido (code=%s)\n' \
        "$_diag_severity" "$_diag_code" >&2
      return 1
      ;;
  esac

  if [ "$_diag_fix" = "$_diag_message" ]; then
    printf 'diag_emit: fix identico a message (code=%s) — MUST NOT repetir a mensagem; envelope DIAG nao emitido\n' \
      "$_diag_code" >&2
    return 1
  fi

  # Escapa `|` interno de message/fix (nao pode quebrar o parsing por
  # campo do consumidor: cut -d'|' -f2-5).
  _diag_esc_message=$(printf '%s' "$_diag_message" | tr '|' '/')
  _diag_esc_fix=$(printf '%s' "$_diag_fix" | tr '|' '/')

  printf 'DIAG|%s|%s|%s|%s\n' \
    "$_diag_severity" "$_diag_code" "$_diag_esc_message" "$_diag_esc_fix" >&2
  return 0
}
