#!/bin/sh
set -eu
. "$CSTK_TEST_ROOT/cli/lib/codex-json.sh"
. "$CSTK_TEST_ROOT/cli/lib/codex-common.sh"
if [ "$*" = 'plugin add --help' ]; then exit 0; fi
case "$1 $2 ${3:-}" in
  'plugin marketplace list')
    if [ -f "$CODEX_HOME/test-marketplace" ]; then printf '{"marketplaces":[{"name":"cstk-codex-pilot-local","root":%s}]}\n' "$(cj_quote "$(cat "$CODEX_HOME/test-marketplace")")"
    else printf '{"marketplaces":[]}\n'; fi ;;
  'plugin marketplace add') printf '%s\n' "$4" > "$CODEX_HOME/test-marketplace" ;;
  'plugin marketplace remove') rm "$CODEX_HOME/test-marketplace" ;;
  'plugin add cstk-codex-pilot@cstk-codex-pilot-local')
    _fc_market=$(cat "$CODEX_HOME/test-marketplace")
    _fc_source=$_fc_market/$(cj_get "$(cx_read "$_fc_market/.agents/plugins/marketplace.json")" /plugins/0/source/path)
    _fc_version=$(cj_get "$(cx_read "$_fc_source/plugin.json")" /version)
    _fc_dest=$CODEX_HOME/plugins/cache/cstk-codex-pilot-local/cstk-codex-pilot/$_fc_version
    [ ! -d "$_fc_dest" ] || rm -r "$_fc_dest"
    mkdir -p "$(dirname "$_fc_dest")"; cp -R "$_fc_source" "$_fc_dest"
    _fc_marker='[plugins."cstk-codex-pilot@cstk-codex-pilot-local"]'
    if [ ! -f "$CODEX_HOME/config.toml" ] || ! grep -F "$_fc_marker" "$CODEX_HOME/config.toml" >/dev/null; then printf '\n%s\nenabled = true\n' "$_fc_marker" >> "$CODEX_HOME/config.toml"; fi ;;
  *) exit 2 ;;
esac
