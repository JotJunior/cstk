#!/bin/sh
# Fixture: simula delivery-tier.sh get/set, gravando o argv de CADA chamada
# `set` (uma linha por chamada) em $FAKE_ARGV_FILE — usado para afirmar sobre
# a presenca/ausencia condicional de `--allow-downgrade` (Invariante C-2,
# dec-047), no espirito de `quickstart.md` Scenario 1b ("asserta sobre o argv
# capturado"). `get` sempre devolve "cloud-public" (tier vigente do init).
set -eu
_cmd="${1:-}"
shift || true
case "$_cmd" in
  get)
    printf 'cloud-public\n'
    ;;
  set)
    if [ -n "${FAKE_ARGV_FILE:-}" ]; then
      printf '%s\n' "$*" >> "$FAKE_ARGV_FILE"
    fi
    exit 0
    ;;
  *)
    printf 'fake-collect-optins-delivery-tier-captures-argv: subcomando desconhecido: %s\n' "$_cmd" >&2
    exit 1
    ;;
esac
