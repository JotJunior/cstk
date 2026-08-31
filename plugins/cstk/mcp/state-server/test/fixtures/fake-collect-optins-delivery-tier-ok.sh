#!/bin/sh
# Fixture: simula delivery-tier.sh get/set. `get` sempre devolve
# "cloud-public" (tier vigente do init, INV-1); `set` sempre sucesso,
# independente de --allow-downgrade estar presente ou nao (o teste que
# precisa afirmar sobre o argv usa um fixture dedicado que grava argv em
# arquivo — ver fake-collect-optins-delivery-tier-captures-argv.sh).
set -eu
_cmd="${1:-}"
shift || true
case "$_cmd" in
  get) printf 'cloud-public\n' ;;
  set) exit 0 ;;
  *) printf 'fake-collect-optins-delivery-tier-ok: subcomando desconhecido: %s\n' "$_cmd" >&2; exit 1 ;;
esac
