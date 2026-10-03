#!/bin/sh
# Build self-contained native assets using the same POSIX release toolchain.
set -eu
REPO_ROOT=${REPO_ROOT:-$(CDPATH='' cd -P -- "$(dirname -- "$0")/.." && pwd -P)}
. "$REPO_ROOT/cli/lib/codex-json.sh"
. "$REPO_ROOT/cli/lib/codex-common.sh"
[ "$#" = 2 ] && [ "$1" = --out ] || { cx_fail 'Uso: build-codex-plugin.sh --out DIR' 2; exit 2; }
_bc_output=$(cx_path "$2")
[ ! -e "$_bc_output" ] && [ ! -L "$_bc_output" ] || { cx_fail 'output already exists'; exit 1; }
for _bc_tree in plugins/cstk cli adapters/codex docs/specs/codex-feature-00c; do
  ! cx_within "$REPO_ROOT/$_bc_tree" "$_bc_output" || { cx_fail 'output inside a copied source tree'; exit 1; }
done
[ -f "$REPO_ROOT/adapters/codex/.codex-plugin/plugin.json" ] || { cx_fail 'missing adapter manifest'; exit 1; }
mkdir -p -- "$(dirname -- "$_bc_output")"
cp -R -- "$REPO_ROOT/adapters/codex" "$_bc_output"
mkdir -p -- "$_bc_output/plugins" "$_bc_output/docs/specs"
cp -R -- "$REPO_ROOT/plugins/cstk" "$_bc_output/plugins/cstk"
cp -R -- "$REPO_ROOT/cli" "$_bc_output/cli"
cp -R -- "$REPO_ROOT/docs/specs/codex-feature-00c" "$_bc_output/docs/specs/codex-feature-00c"
find "$_bc_output" -type d \( -name node_modules -o -name dist -o -name __pycache__ \) -prune -exec rm -r -- {} +
find "$_bc_output" -type f \( -name '*.pyc' -o -name .DS_Store \) -exec rm -f -- {} +
sed 's|../../docs/specs/codex-feature-00c/|docs/specs/codex-feature-00c/|g' "$_bc_output/README.md" > "$_bc_output/.README.tmp"
mv -- "$_bc_output/.README.tmp" "$_bc_output/README.md"
mkdir -p -- "$_bc_output/.agents/plugins"
printf '%s\n' '{"name":"cstk-codex-pilot-local","interface":{"displayName":"cstk Codex pilot (experimental)"},"plugins":[{"name":"cstk-codex-pilot","source":{"source":"local","path":"./"},"policy":{"installation":"AVAILABLE","authentication":"ON_INSTALL"},"category":"Productivity"}]}' > "$_bc_output/.agents/plugins/marketplace.json"
printf '%s\n' "$_bc_output"
