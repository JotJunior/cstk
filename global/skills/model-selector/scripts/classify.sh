#!/bin/sh
# shellcheck shell=sh
#
# classify.sh — Esqueleto do classificador deterministico (FASE 2, task 2.1)
#
# Skill: model-selector
# Pipeline: input textual -> tokens -> match catalogo -> faixa -> rotulo
# Status: ESQUELETO (subtarefas 2.1.1-2.1.4) — logica de classificacao
#         (tokenizacao, match, score, output markdown) entra nas tarefas
#         2.2, 2.3, 2.4 e 2.5 desta FASE.
#
# Conformidade:
#   - POSIX puro (#!/bin/sh + set -eu, sem bash-isms) — CHK001
#   - Sem `jq` no caminho de classificacao — Plan §Project Structure
#   - Sem coleta remota; offline-only — Principio IV
#
# -----------------------------------------------------------------------
# Exit codes (CHK021 — invariante testavel via tests/cstk/)
# -----------------------------------------------------------------------
#   0  sucesso — sugestao emitida em stdout (4 secoes markdown).
#   2  uso incorreto — argumento ausente, mais de 1 arg, ou null-byte
#      detectado no input. Stderr recebe mensagem `model-selector: ...`.
#      (Alinha com contracts/skill-io.md secao "erro de uso".)
#   3  erro de IO — catalogo `references/sinais.md` ausente, ilegivel,
#      ou catalogo vazio/invalido. Stderr descreve o path resolvido.
#      (NOTA: contracts/skill-io.md hoje cita exit 1 para "erro interno"
#      / catalogo ausente — divergencia rastreada na Decisao dec-041
#      desta onda. Esqueleto segue tasks.md L105 que pede exit 3
#      explicitamente; alinhamento final do contrato sera resolvido em
#      uma sub-tarefa de 2.7 ou em refinamento dedicado.)
#
# -----------------------------------------------------------------------
# Input (FR-001, contracts/skill-io.md)
# -----------------------------------------------------------------------
#   Forma 1 (stdin):
#     echo "rode o grep" | classify.sh
#   Forma 2 (arg posicional):
#     classify.sh "rode o grep"
#
#   Precedencia: se houver arg posicional ($# -ge 1), ele vence; stdin
#   so e lida quando $# -eq 0 E stdin NAO e um TTY (heuristica POSIX:
#   `[ ! -t 0 ]`). Isso evita que invocar interativamente sem args
#   trave aguardando input.
#
# -----------------------------------------------------------------------
# Catalogo (FR-003, FR-004, Decision 2 do research)
# -----------------------------------------------------------------------
#   Path: <dir-do-script>/../references/sinais.md
#   Resolvido via `${0%/*}/../references/sinais.md` — POSIX-pure,
#   sem `dirname`, sem `realpath`, sem hardcode absoluto.
#
# =======================================================================

set -eu

# -----------------------------------------------------------------------
# Constantes (rotulos abstratos — dec-005, nunca strings versionadas)
# -----------------------------------------------------------------------
PROG_NAME="model-selector"

# Resolucao do path do catalogo (subtarefa 2.1.4)
# ${0%/*} = remove menor sufixo "/algo" do $0 = diretorio do script.
# Funciona em sh/dash/bash quando $0 contem ao menos uma "/". Quando
# script e executado sem caminho (ex: via PATH como `classify.sh`),
# $0 == "classify.sh" e ${0%/*} == "classify.sh"; tratamos abaixo.
SCRIPT_DIR="${0%/*}"
if [ "$SCRIPT_DIR" = "$0" ]; then
    # $0 nao continha "/": script invocado por nome puro via PATH.
    # Tenta `command -v` para resolver; se falhar, assume cwd.
    RESOLVED="$(command -v -- "$0" 2>/dev/null || printf '%s' "$0")"
    case "$RESOLVED" in
        */*) SCRIPT_DIR="${RESOLVED%/*}" ;;
        *)   SCRIPT_DIR="." ;;
    esac
fi
CATALOG_PATH="${SCRIPT_DIR}/../references/sinais.md"

# -----------------------------------------------------------------------
# Leitura de input (subtarefa 2.1.3)
# -----------------------------------------------------------------------
# Regras:
#   - 0 args + stdin nao-tty  -> ler stdin completo (ate EOF)
#   - 0 args + stdin tty      -> exit 2 (input obrigatorio)
#   - 1 arg                   -> usar $1 literalmente
#   - >1 args                 -> exit 2 (aceita 1 arg apenas)
if [ "$#" -gt 1 ]; then
    printf '%s: aceita exatamente 1 argumento (recebi %d)\n' \
        "$PROG_NAME" "$#" >&2
    exit 2
fi

if [ "$#" -eq 1 ]; then
    INPUT="$1"
else
    if [ -t 0 ]; then
        printf '%s: input obrigatorio (uso: classify.sh "<texto>")\n' \
            "$PROG_NAME" >&2
        exit 2
    fi
    # Le stdin completo. `cat` aqui e portavel; sem `mapfile`/bash-isms.
    INPUT="$(cat)"
fi

# Validacao basica de input (logica completa entra em 2.2)
# Aqui apenas detectamos o caso "input completamente vazio (zero
# chars)" como erro de uso conforme contracts/skill-io.md L37 (input
# vazio -> tratamento especial). A spec define que input vazio gera
# sugestao `manter-atual` score 0, mas isso vive na logica de
# tokenizacao da task 2.2 — esqueleto sinaliza o caso para nao silenciar.
if [ -z "$INPUT" ]; then
    printf '%s: input vazio (uso: classify.sh "<texto>")\n' \
        "$PROG_NAME" >&2
    exit 2
fi

# -----------------------------------------------------------------------
# Validacao do catalogo (subtarefa 2.1.4 — gate de IO)
# -----------------------------------------------------------------------
if [ ! -f "$CATALOG_PATH" ]; then
    printf '%s: catalogo de sinais nao encontrado em %s\n' \
        "$PROG_NAME" "$CATALOG_PATH" >&2
    exit 3
fi

if [ ! -r "$CATALOG_PATH" ]; then
    printf '%s: catalogo sem permissao de leitura em %s\n' \
        "$PROG_NAME" "$CATALOG_PATH" >&2
    exit 3
fi

# =======================================================================
# Logica de classificacao (PLACEHOLDER — entra em 2.2..2.5)
# =======================================================================
# As proximas tarefas implementarao:
#   2.2 Tokenizacao via `tr | tr | sed`
#   2.3 Match `grep -Fxq` contra colunas do catalogo (awk streaming)
#   2.4 Score 0..2 + justificativa + mapeamento faixa->modelo
#   2.5 Output markdown com 4 secoes fixas
#
# Placeholder atual: emite output minimo bem-formado (4 secoes) para
# permitir smoke test do esqueleto sem quebrar invariantes do contrato.
# Sera SUBSTITUIDO integralmente na task 2.5.
# -----------------------------------------------------------------------

cat <<'EOF'
## Sugestao

**modelo**: manter-atual
**score**: 0
**alternativa**: none

## Sinais detectados

(nenhum sinal detectado — esqueleto sem logica de match; ver tasks 2.2-2.5)

## Justificativa

input curto demais para classificacao confiavel (esqueleto FASE 2 task 2.1
sem logica de tokenizacao/match implementada ainda)

## Acao sugerida (operador humano)

`(nenhuma troca sugerida — manter modelo atual)`
EOF

exit 0
