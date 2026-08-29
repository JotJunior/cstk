#!/bin/sh
# readonly-check.sh — gate automatizado do Principio I da constitution
# ("Read-Only sobre o Corpus"). Procura verbos de mutacao SQL no codigo do
# back-end.
#
# POR QUE ESTE SCRIPT EXISTE E NAO E UM GREP INLINE
#
# A versao anterior era um `grep -rniE` direto no package.json e tinha dois
# defeitos, ambos medidos:
#
#   1. FALSO-POSITIVO: por ser case-insensitive e sem nocao de sintaxe, um
#      COMENTARIO contendo a palavra "update" reprovava o gate. Medido:
#      `// Este comentario menciona update` => FAIL. Isso treina a equipe a
#      ignorar a saida do gate, que e pior que nao ter gate.
#
#   2. RELATORIO CEGO: imprimia "OK: no mutation verbs" sem dizer QUANTOS
#      arquivos leu. "OK" vindo de lugar nenhum nao distingue "varri 120
#      arquivos e nao achei nada" de "nao varri nada". Um gate que reporta
#      sucesso sem declarar cobertura e a classe de defeito mais recorrente
#      que encontramos neste toolkit (ver docs/constitution.md, Principio I,
#      clausula Testavel).
#
# ESTREITAMENTO DE ESCOPO (feature human-bridge, task 3.1.9 — constitution
# 2.0.0, Sync Impact Report da emenda 2026-08-26)
#
#   A constitution 2.0.0 introduziu a "excecao da Ponte": uma UNICA conexao
#   read-write (`db/bridge.ts`) e rotas nao-GET confinadas a
#   `/api/v1/bridge/*` (`routes/bridge.ts`). Variar `apps/server/src` INTEIRO
#   por verbo de mutacao reprovaria o PRIMEIRO commit legitimo desses dois
#   arquivos — daí a instrucao textual da emenda: "restringe a varredura a
#   apps/server/src/db/queries/** e exige, em contrapartida, duas
#   verificacoes novas". Este script MUST estreitar no MESMO commit do
#   primeiro codigo de `bridge/`, nunca antes (deixaria o commit reprovado)
#   nem depois (janela sem gate).
#
#   O que isso significa na pratica: a varredura de VERBOS (Check 1) passa a
#   cobrir so a camada de LEITURA pura (`db/queries/**`, que nunca deveria
#   conter INSERT/UPDATE/DELETE/CREATE/DROP/ALTER) — e NAO mais
#   `db/bridge.ts`/`routes/bridge.ts`, que agora tem autorizacao textual para
#   escrever. A cobertura que se perde ali e recuperada pelas DUAS
#   verificacoes compensatorias exigidas pela propria emenda:
#
#     Check 2 — a UNICA conexao `new Database(...)` SEM `readonly: true` em
#               todo `apps/server/src` MUST ser `db/bridge.ts`. Qualquer
#               outro arquivo abrindo o SQLite sem `readonly: true` e uma
#               segunda conexao rw nao autorizada.
#     Check 3 — nenhuma rota fora de `routes/bridge.ts` registra metodo
#               nao-GET (`.post(`/`.put(`/`.patch(`/`.delete(`). Enquanto
#               isso valer, TODA superficie de escrita HTTP do painel esta,
#               por construcao, sob `/api/v1/bridge/*`.
#
#   Comentario em linha (`//`/`*` no inicio da linha) continua NAO reprovando
#   o Check 1 — comentario nao executa SQL. Comentario no FIM da linha
#   (apos codigo) CONTINUA reprovando, de proposito: na duvida, reprovar.
set -eu

SCOPE_QUERIES="${1:-apps/server/src/db/queries}"
SRC_ROOT="${2:-apps/server/src}"
VERBS='INSERT|UPDATE|DELETE|CREATE|DROP|ALTER'
AUTHORIZED_RW_FILE='db/bridge.ts'
AUTHORIZED_NONGET_FILE='routes/bridge.ts'

overall_fail=0

# ---------------------------------------------------------------------------
# Check 1 — verbos de mutacao na camada de leitura pura (db/queries/**)
# ---------------------------------------------------------------------------
if [ ! -d "$SCOPE_QUERIES" ]; then
  printf 'readonly-check: escopo inexistente: %s\n' "$SCOPE_QUERIES" >&2
  exit 2
fi

files1=$(find "$SCOPE_QUERIES" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) | wc -l | tr -d ' ')
hits1=$(grep -rniE "\\b($VERBS)[[:space:]]" "$SCOPE_QUERIES" || true)

if [ -z "$hits1" ]; then
  printf 'OK[1]: 0 verbos de mutacao em %s arquivos sob %s\n' "$files1" "$SCOPE_QUERIES"
else
  code_hits1=$(printf '%s\n' "$hits1" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*)' || true)
  comment_hits1=$(printf '%s\n' "$hits1" | grep -cE '^[^:]+:[0-9]+:[[:space:]]*(//|\*)' || true)

  if [ -z "$code_hits1" ]; then
    printf 'OK[1]: 0 verbos de mutacao em codigo, %s arquivos sob %s (%s ocorrencia(s) em comentario, ignoradas)\n' \
      "$files1" "$SCOPE_QUERIES" "$comment_hits1"
  else
    printf 'FAIL[1]: verbo de mutacao em codigo de %s (camada de leitura pura, %s arquivos varridos)\n' \
      "$SCOPE_QUERIES" "$files1" >&2
    printf '%s\n' "$code_hits1" >&2
    printf '\nSe a ocorrencia estiver dentro de um comentario no FIM da linha, o gate\nreprova de proposito — mova o comentario para linha propria.\n' >&2
    overall_fail=1
  fi
fi

# ---------------------------------------------------------------------------
# Check 2 — a UNICA conexao read-write aponta para db/bridge.ts
# ---------------------------------------------------------------------------
if [ ! -d "$SRC_ROOT" ]; then
  printf 'readonly-check: escopo inexistente: %s\n' "$SRC_ROOT" >&2
  exit 2
fi

db_open_files=$(grep -rlE 'new[[:space:]]+Database[[:space:]]*\(' "$SRC_ROOT" --include='*.ts' --include='*.tsx' 2>/dev/null || true)
rw_offenders=""
for f in $db_open_files; do
  case "$f" in
    *"$AUTHORIZED_RW_FILE") continue ;;
  esac
  if ! grep -qE 'readonly[[:space:]]*:[[:space:]]*true' "$f"; then
    rw_offenders="${rw_offenders}${f}
"
  fi
done

if [ -n "$rw_offenders" ]; then
  printf 'FAIL[2]: conexao read-write fora de %s (Principio I, "unica conexao rw")\n' "$AUTHORIZED_RW_FILE" >&2
  printf '%s' "$rw_offenders" >&2
  overall_fail=1
else
  printf 'OK[2]: unica conexao read-write autorizada e %s\n' "$AUTHORIZED_RW_FILE"
fi

# ---------------------------------------------------------------------------
# Check 3 — toda rota fora de /api/v1/bridge/* responde so a GET
# ---------------------------------------------------------------------------
ROUTES_DIR="$SRC_ROOT/routes"
nonget_offenders=""
if [ -d "$ROUTES_DIR" ]; then
  hits3=$(grep -rnE '\.(post|put|patch|delete)\(' "$ROUTES_DIR" --include='*.ts' --include='*.tsx' 2>/dev/null || true)
  if [ -n "$hits3" ]; then
    nonget_offenders=$(printf '%s\n' "$hits3" | grep -v "$AUTHORIZED_NONGET_FILE" || true)
  fi
fi

if [ -n "$nonget_offenders" ]; then
  printf 'FAIL[3]: rota nao-GET fora de %s\n' "$AUTHORIZED_NONGET_FILE" >&2
  printf '%s\n' "$nonget_offenders" >&2
  overall_fail=1
else
  printf 'OK[3]: nenhuma rota nao-GET fora de %s\n' "$AUTHORIZED_NONGET_FILE"
fi

if [ "$overall_fail" -ne 0 ]; then
  exit 1
fi

exit 0
