#!/bin/sh
# Fixture state-ondas.sh (close_wave): wave-status=open, current-id=onda-013,
# `end` MUTA de verdade o state.json do --state-dir recebido (sobrescreve com
# um marcador "mutated") antes de retornar sucesso — simula o efeito real de
# `_so_cmd_end` (mv + atomic write). Usado para provar que a compensacao
# (restore da pre-imagem) de fato reverte bytes em disco, nao so o retorno da
# tool, quando uma etapa POSTERIOR (sha256-update) falha.
set -eu
_sub=${1:-}
shift || :
_sdir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-dir) _sdir=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$_sub" in
  wave-status) printf 'open\n' ;;
  current-id)  printf 'onda-013\n' ;;
  end)
    [ -n "$_sdir" ] || { printf 'fake-close-wave-ondas-end-mutates: --state-dir ausente\n' >&2; exit 1; }
    printf '{"mutated":true,"waves":[{"id":"onda-013","termination_reason":"concluido"}]}' > "$_sdir/state.json"
    exit 0
    ;;
  *) printf 'fake-close-wave-ondas: subcomando desconhecido: %s\n' "$_sub" >&2; exit 1 ;;
esac
