#!/bin/sh
# bootstrap-docs.sh
# Emite instrucoes para instalar dependencias do site GitHub Pages.
# Este script NAO executa pip install automaticamente — apenas imprime
# os comandos para o operador rodar manualmente (FR-018 do agente-00c).
#
# Uso: sh scripts/bootstrap-docs.sh
set -eu

cat <<'EOF'
# ============================================================
# Bootstrap do site docs-site/ (MkDocs Material)
# ============================================================
#
# 1) Criar venv local (Python >=3.11):
#    python3 -m venv .venv-docs
#    . .venv-docs/bin/activate
#
# 2) Instalar dependencias pinadas:
#    pip install -r requirements-docs.txt
#
# 3) Build determinista:
#    mkdocs build --strict
#
# 4) Servidor local de preview:
#    mkdocs serve
#    # abre em http://127.0.0.1:8000/
#
# 5) Limpar artefatos de build:
#    rm -rf site/
#
# ============================================================
# Nota: em CI (.github/workflows/publish-site.yml), as etapas 1-3
# rodam automaticamente. Este script existe para reproduzir o
# build local sem mistério.
EOF
