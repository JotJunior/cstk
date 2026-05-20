#!/usr/bin/env bash
# smoke-site.sh — Smoke test do build estatico do site MkDocs.
#
# Cria venv isolado, instala deps, roda `mkdocs build --strict`. Util
# como gate manual antes de push (CI roda automaticamente via
# .github/workflows/publish-site.yml).
#
# Uso:
#   ./scripts/smoke-site.sh                  # build em site-smoke/
#   ./scripts/smoke-site.sh --keep-venv      # nao remover .venv-docs ao fim
#   ./scripts/smoke-site.sh --serve          # apos build, roda mkdocs serve
#
# Pre-requisitos:
#   - Python >= 3.10 (testado com 3.11+)
#   - Acesso a PyPI (deps em requirements-docs.txt)
#
# Convencao:
#   - venv local em .venv-docs/ (gitignored)
#   - build em site-smoke/ (gitignored; nao confundir com site/ do CI)
#   - exit 0 = OK; exit !=0 = falha (Python ausente, deps quebradas,
#     mkdocs --strict reclamou)
#
# NAO roda automaticamente em pre-commit — escolha consciente:
#   instalar mkdocs em todo dev box e excessivo para esta feature.
#   CI eh o gate canonico.

set -euo pipefail

# ----------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv-docs"
REQUIREMENTS="$REPO_ROOT/requirements-docs.txt"
SITE_DIR="$REPO_ROOT/site-smoke"
MIN_PY_MAJOR=3
MIN_PY_MINOR=10

KEEP_VENV=0
DO_SERVE=0

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

log() { printf '\033[1;34m[smoke-site]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[smoke-site WARN]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[smoke-site ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ----------------------------------------------------------------------
# Parse args
# ----------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage 0 ;;
        --keep-venv) KEEP_VENV=1 ;;
        --serve) DO_SERVE=1 ;;
        *) err "argumento desconhecido: $1"; usage 1 ;;
    esac
    shift
done

# ----------------------------------------------------------------------
# 1. Verificar Python
# ----------------------------------------------------------------------

if ! command -v python3 >/dev/null 2>&1; then
    err "python3 nao encontrado no PATH"
    exit 2
fi

PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PY_MAJOR="${PY_VER%%.*}"
PY_MINOR="${PY_VER##*.}"

if [ "$PY_MAJOR" -lt "$MIN_PY_MAJOR" ] || { [ "$PY_MAJOR" -eq "$MIN_PY_MAJOR" ] && [ "$PY_MINOR" -lt "$MIN_PY_MINOR" ]; }; then
    err "Python $PY_VER detectado; requer >=$MIN_PY_MAJOR.$MIN_PY_MINOR"
    err "instale Python moderno (pyenv, asdf, brew) e re-execute"
    exit 2
fi

log "Python $PY_VER OK"

# ----------------------------------------------------------------------
# 2. Validar requirements-docs.txt
# ----------------------------------------------------------------------

if [ ! -f "$REQUIREMENTS" ]; then
    err "requirements-docs.txt nao encontrado em $REQUIREMENTS"
    err "deve listar mkdocs, mkdocs-material, mkdocs-gen-files, pymdown-extensions"
    exit 2
fi

# ----------------------------------------------------------------------
# 3. Criar venv (idempotente)
# ----------------------------------------------------------------------

if [ ! -d "$VENV_DIR" ]; then
    log "criando venv em $VENV_DIR"
    python3 -m venv "$VENV_DIR"
else
    log "reutilizando venv existente em $VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# Garantir pip atualizado (mkdocs-material precisa de pip recente)
log "atualizando pip"
python -m pip install --quiet --upgrade pip

log "instalando deps de $REQUIREMENTS"
python -m pip install --quiet -r "$REQUIREMENTS"

# ----------------------------------------------------------------------
# 4. Build com --strict
# ----------------------------------------------------------------------

cd "$REPO_ROOT"

if [ -d "$SITE_DIR" ]; then
    log "removendo build anterior em $SITE_DIR"
    rm -rf "$SITE_DIR"
fi

log "rodando: mkdocs build --strict --site-dir $SITE_DIR"
if mkdocs build --strict --site-dir "$SITE_DIR"; then
    log "build OK — site gerado em $SITE_DIR"
    BUILD_RC=0
else
    err "mkdocs build --strict FALHOU"
    BUILD_RC=1
fi

# ----------------------------------------------------------------------
# 5. (Opcional) servir local
# ----------------------------------------------------------------------

if [ "$DO_SERVE" -eq 1 ] && [ "$BUILD_RC" -eq 0 ]; then
    log "iniciando mkdocs serve em http://127.0.0.1:8000 (Ctrl+C para sair)"
    mkdocs serve
fi

# ----------------------------------------------------------------------
# 6. Cleanup do venv (opcional)
# ----------------------------------------------------------------------

deactivate || true

if [ "$KEEP_VENV" -eq 0 ]; then
    log "removendo venv (use --keep-venv para preservar)"
    rm -rf "$VENV_DIR"
fi

if [ "$BUILD_RC" -ne 0 ]; then
    err "smoke FALHOU"
    exit 1
fi

log "smoke OK"
