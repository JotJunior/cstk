#!/bin/sh
# mcp-build-lazy.sh — instalacao + build lazy de mcp/state-server, com
# mitigacao de supply chain (R8, severidade HIGH).
#
# Ref: docs/specs/mcp-direct-transport/spec.md FR-004;
#      docs/specs/mcp-direct-transport/plan.md Risco R8 (dec-041/dec-042);
#      docs/specs/mcp-direct-transport/contracts/server-session-resolution.md
#        §4.2 (L-4, L-6);
#      docs/specs/mcp-direct-transport/checklists/requirements.md
#        CHK001, CHK015;
#      docs/specs/mcp-direct-transport/tasks.md FASE 2 task 2.2
#
# PAPEL: garante que <dir>/dist/src/index.js exista, instalando as
# dependencias declaradas em <dir>/package.json e compilando o
# TypeScript quando necessario. Idempotente — se o entrypoint ja existe,
# e um no-op imediato (nem instala nem builda de novo).
#
# MITIGACAO DE SUPPLY CHAIN (R8): o Dockerfile removido nesta feature
# (cli/lib/mcp-docker.sh, FASE 3) tinha a UNICA ocorrencia real, ate
# entao, da protecao "npm ci com scripts de ciclo de vida desativados" —
# `docker build` confinava a instalacao a um container efemero. O build
# lazy deste script roda DIRETO no host, com os privilegios do usuario
# que invoca (sem esse confinamento), entao a mesma protecao e
# OBRIGATORIA aqui, sem excecao:
#   1. instalacao SEMPRE fixada pelo lockfile (nunca resolucao de
#      versoes) — exige package-lock.json presente e sincronizado;
#   2. instalacao SEMPRE com scripts de ciclo de vida (install/
#      preinstall/postinstall) desativados — elimina a superficie de
#      execucao arbitraria de codigo de dependencia no momento do
#      install (A03/ASI04/CICD-SEC-3).
#
# Auditoria empirica (task 2.2.1, executada nesta onda sobre
# mcp/state-server/package-lock.json + node_modules/ resolvidos):
# nenhuma das 116 entradas node_modules/* do lockfile (lockfileVersion 3,
# que marca pacotes com scripts de instalacao via o campo
# "hasInstallScript") declara scripts.install/preinstall/postinstall; zero
# ocorrencias de "hasInstallScript", "gypfile", "binding.gyp",
# "node-gyp" ou "prebuild-install" no lockfile inteiro. Confirmado
# tambem na arvore ja instalada em disco (node_modules/): nenhum
# binding.gyp, nenhum package.json de dependencia direta/transitiva com
# scripts.install/preinstall/postinstall. As duas dependencias diretas
# (@modelcontextprotocol/sdk, zod) e toda a arvore transitiva sao JS
# puro — a flag de mitigacao e segura de aplicar incondicionalmente
# (task 2.2.2: nenhum caso de build nativo encontrado, allowlist
# pontual desnecessaria).
#
# POSIX sh puro. Deps: npm (subcomandos de instalacao fixada por
# lockfile + execucao de script "build" do package.json).
#
# Uso:
#   mcp-build-lazy.sh ensure --dir <path>
#
# Exit codes:
#   0  dist/src/index.js pronto (ja existia, ou build concluido agora) —
#      stdout = path absoluto do entrypoint
#   1  falha: lockfile ausente, npm ausente, instalacao falhou, build
#      falhou, ou entrypoint ainda ausente apos build concluir
#   2  uso incorreto (subcomando/flag desconhecidos, --dir ausente ou
#      inexistente)

set -eu

_MBL_NAME="mcp-build-lazy"

_mbl_die() {
  printf '%s: %s\n' "$_MBL_NAME" "$1" >&2
  exit "${2:-1}"
}

_mbl_usage() {
  cat <<EOF
uso: $_MBL_NAME.sh ensure --dir <path>

Garante que <path>/dist/src/index.js exista: instala as dependencias de
<path> (fixadas por package-lock.json, sem scripts de ciclo de vida) e
roda o build (npm run build) quando o entrypoint ainda nao existe.
Idempotente — no-op se o entrypoint ja existe.
EOF
}

_mbl_cmd="${1:-}"
case "$_mbl_cmd" in
  ensure) shift ;;
  -h|--help|"") _mbl_usage; exit 0 ;;
  *) _mbl_die "subcomando desconhecido: $_mbl_cmd" 2 ;;
esac

_mbl_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      [ $# -ge 2 ] || _mbl_die "--dir exige valor" 2
      _mbl_dir="$2"
      shift 2
      ;;
    *) _mbl_die "opcao desconhecida: $1" 2 ;;
  esac
done

[ -n "$_mbl_dir" ] || _mbl_die "--dir e obrigatorio" 2
[ -d "$_mbl_dir" ] || _mbl_die "diretorio nao encontrado: $_mbl_dir" 2

_mbl_entrypoint="$_mbl_dir/dist/src/index.js"

# Fast path idempotente: build ja pronto (cache de sessoes anteriores em
# ~/.claude/mcp/state-server/) — nem instala, nem builda de novo.
if [ -f "$_mbl_entrypoint" ]; then
  printf '%s\n' "$_mbl_entrypoint"
  exit 0
fi

_mbl_lockfile="$_mbl_dir/package-lock.json"

# Fail-closed explicito (paridade com o build de imagem removido em
# cli/lib/mcp-docker.sh, CHK014): nunca degradar silenciosamente para
# uma instalacao sem lockfile — quebraria a garantia de reprodutibilidade
# que a mitigacao de R8 depende (CHK015).
[ -f "$_mbl_lockfile" ] \
  || _mbl_die "package-lock.json ausente em $_mbl_dir; a instalacao nunca degrada silenciosamente (reprodutibilidade, CHK015)"

command -v npm >/dev/null 2>&1 || _mbl_die "npm nao encontrado no PATH"

# SEC-M4/CHK001/CHK015 (dec-041/dec-042, R8=HIGH — ver auditoria no
# cabecalho deste arquivo): instalacao fixada pelo lockfile (nao
# resolucao de versoes) e com scripts de ciclo de vida desativados.
if ! (cd "$_mbl_dir" && npm ci --ignore-scripts) >&2; then
  _mbl_die "instalacao de dependencias falhou em $_mbl_dir"
fi

if ! npm --prefix "$_mbl_dir" run build >&2; then
  _mbl_die "build (npm run build) falhou em $_mbl_dir"
fi

[ -f "$_mbl_entrypoint" ] \
  || _mbl_die "build concluido mas entrypoint ainda ausente: $_mbl_entrypoint"

printf '%s\n' "$_mbl_entrypoint"
