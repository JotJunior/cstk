#!/bin/sh
# scaffold.sh — cria a estrutura padrao de documentacao do projeto.
#
# Uso:
#   scripts/scaffold.sh            # cria estrutura em ./docs/
#   scripts/scaffold.sh --dry-run  # apenas mostra o que seria feito
#   scripts/scaffold.sh --force    # sobrescreve READMEs existentes
#
# Idempotente: rodar multiplas vezes nao sobrescreve conteudo (exceto com --force).
# POSIX sh — sem dependencias alem de mkdir/test/printf.

set -eu

DOCS_DIR="docs"
DRY_RUN=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    --dir=*)   DOCS_DIR="${arg#--dir=}" ;;
    -h|--help)
      cat <<'USAGE'
scaffold.sh — cria estrutura padrao de docs/

Opcoes:
  --dry-run   mostra o que seria criado sem escrever
  --force     sobrescreve READMEs existentes
  --dir=PATH  usa PATH em vez de ./docs
  -h, --help  mostra esta ajuda
USAGE
      exit 0
      ;;
    *)
      printf 'Argumento desconhecido: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

# Lista de diretorios a criar (tab-separated: path<TAB>descricao-para-README)
DIRS="
01-briefing-discovery	Documentos iniciais, briefings, requisitos de negocio
02-requisitos-casos-uso	Casos de uso detalhados (UC-*)
03-modelagem-dados	Modelagem de dados, DERs, schemas
04-arquitetura-sistema	Decisoes de arquitetura (ADR-*), diagramas
05-definicao-apis	Contratos de API (REST, gRPC, Webhooks, Messaging)
05-definicao-apis/REST	APIs REST
05-definicao-apis/gRPC	Definicoes gRPC/protobuf
05-definicao-apis/WEBHOOKS	Webhooks
05-definicao-apis/MESSAGING	Mensageria (RabbitMQ, Kafka, etc)
06-ui-ux-design	Wireframes, mockups, guias de estilo
07-plano-testes	Planos e casos de teste
08-operacoes	Runbooks, procedimentos operacionais
09-entregaveis	Release notes, documentos de entrega
"

log() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

ensure_dir() {
  dir="$1"
  if [ ! -d "$dir" ]; then
    log "mkdir: $dir"
    if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$dir"
  fi
  fi
}

ensure_readme() {
  readme="$1"
  title="$2"
  description="$3"

  if [ -f "$readme" ] && [ "$FORCE" -eq 0 ]; then
    return 0
  fi

  log "write README: $readme"
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi

  {
    printf '# %s\n\n' "$title"
    printf '%s\n' "$description"
  } > "$readme"
}

# Cria o diretorio raiz
ensure_dir "$DOCS_DIR"

# Cria subdiretorios e READMEs
printf '%s' "$DIRS" | while IFS="	" read -r subpath desc; do
  [ -z "$subpath" ] && continue
  full="$DOCS_DIR/$subpath"
  ensure_dir "$full"
  title=$(printf '%s' "$subpath" | sed -e 's|.*/||' -e 's/^[0-9]*-//' -e 's/-/ /g')
  ensure_readme "$full/README.md" "$title" "$desc"
done

# README principal
ensure_readme "$DOCS_DIR/README.md" "Documentacao do Projeto" "Estrutura padrao de documentacao gerada por initialize-docs.

| Diretorio | Descricao |
|-----------|-----------|
| 01-briefing-discovery | Documentos iniciais, briefings, requisitos de negocio |
| 02-requisitos-casos-uso | Casos de uso detalhados (UC-*) |
| 03-modelagem-dados | Modelagem de dados, DERs, schemas |
| 04-arquitetura-sistema | Decisoes de arquitetura (ADR-*), diagramas |
| 05-definicao-apis | Contratos de API (REST, gRPC, Webhooks, Messaging) |
| 06-ui-ux-design | Wireframes, mockups, guias de estilo |
| 07-plano-testes | Planos e casos de teste |
| 08-operacoes | Runbooks, procedimentos operacionais |
| 09-entregaveis | Release notes, documentos de entrega |

## Convencoes de Nomenclatura

- UC-XXX-NNN: Caso de Uso
- ADR-NNN: Architectural Decision Record
- DER-XXX: Diagrama Entidade-Relacionamento
- CT-NNN: Test Case
- RB-NNN: Runbook
"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\nDry run completo. Nada foi escrito.\n'
else
  printf '\nEstrutura criada em %s/\n' "$DOCS_DIR"
fi
