#!/bin/sh
# shellcheck shell=sh
#
# classify.sh — Classificador deterministico (FASE 2, tasks 2.1 + 2.2)
#
# Skill: model-selector
# Pipeline: input textual -> tokens -> match catalogo -> faixa -> rotulo
# Status: ESQUELETO + TOKENIZACAO (subtarefas 2.1.1-2.1.4 + 2.2.1-2.2.6).
#         Match contra catalogo, score e output final entram nas tasks
#         2.3, 2.4 e 2.5 desta FASE.
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
    # Caminho 1: arg posicional. Note que o shell POSIX trunca $1 no
    # primeiro NUL antes mesmo do script receber — `${#1}` para "abc\0def"
    # = 3. Logo, NUL via $1 e indetectavel aqui, mas tambem inofensivo:
    # o byte nunca chega no buffer. Subtarefa 2.2.3 mira stdin.
    INPUT="$1"
    INPUT_HAD_NULL=0
else
    if [ -t 0 ]; then
        printf '%s: input obrigatorio (uso: classify.sh "<texto>")\n' \
            "$PROG_NAME" >&2
        exit 2
    fi
    # Caminho 2: stdin. Materializa em tmpfile ANTES de command
    # substitution porque `$(cat)` em POSIX trunca no primeiro NUL —
    # perderiamos a evidencia para a subtarefa 2.2.3. Tmpfile permite
    # detectar NUL via byte-count comparativo.
    INPUT_TMP=$(mktemp -t model-selector.XXXXXX) \
        || { printf '%s: mktemp falhou\n' "$PROG_NAME" >&2; exit 3; }
    # Cleanup garantido em qualquer saida.
    # shellcheck disable=SC2064  # expansao early intencional ($INPUT_TMP fixo)
    trap "rm -f -- '$INPUT_TMP'" EXIT INT TERM HUP
    cat > "$INPUT_TMP"

    # Subtarefa 2.2.3: rejeitar NUL no stdin. Compara byte-count bruto
    # com byte-count apos `tr -d '\0'`. Diferenca = havia NUL.
    _BYTES_RAW=$(wc -c < "$INPUT_TMP" | tr -d ' ')
    _BYTES_NONULL=$(tr -d '\0' < "$INPUT_TMP" | wc -c | tr -d ' ')
    if [ "$_BYTES_RAW" != "$_BYTES_NONULL" ]; then
        printf '%s: input contem null-byte (rejeitado)\n' \
            "$PROG_NAME" >&2
        exit 2
    fi
    INPUT_HAD_NULL=0
    INPUT=$(cat -- "$INPUT_TMP")
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
# Subtarefa 2.2.5: truncamento de input >4096 chars
# -----------------------------------------------------------------------
# Limite cravado em contracts/skill-io.md L40. Stderr emite warning
# estruturado (`model-selector: warning: ...`) sem ofuscar o output
# principal em stdout. Truncamento e ANTES da tokenizacao para evitar
# trabalho desnecessario em buffers gigantes.
_INPUT_LEN=${#INPUT}
if [ "$_INPUT_LEN" -gt 4096 ]; then
    printf '%s: warning: input truncado de %s para 4096 chars\n' \
        "$PROG_NAME" "$_INPUT_LEN" >&2
    INPUT=$(printf '%s' "$INPUT" | cut -c 1-4096)
fi

# -----------------------------------------------------------------------
# Subtarefa 2.2.1 + 2.2.2: tokenizacao + filtro de tokens vazios
# -----------------------------------------------------------------------
# Pipeline exato (literal de tasks.md L113):
#   tr ' ' '\n'                  separa em linhas por espaco
#   tr '[:upper:]' '[:lower:]'   lowercase ASCII
#   sed 's/[^a-z0-9]//g'         strip de non-alnum (resolve CHK062)
# Apos isso, `grep -v '^$'` remove tokens vazios (subtarefa 2.2.2).
#
# Subtarefa 2.2.6: input e tratado como string unica via `printf '%s'`
# SEM `eval`, SEM `sh -c "$INPUT"`. Metacaracteres `$`, `\``, `;`, `&&`
# viram bytes literais que o `sed` strip de non-alnum elimina junto
# com pontuacao normal — resolve CHK059 sem branch especial.
TOKENS=$(printf '%s' "$INPUT" \
    | tr ' ' '\n' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]//g' \
    | grep -v '^$' || true)

# Conta tokens. `grep -v` pode retornar 1 se zero matches — `|| true`
# acima cobre. Aqui `wc -l` da N (assumindo trailing newline padrao do
# pipeline; se TOKENS vazio, wc -l = 0).
if [ -z "$TOKENS" ]; then
    TOKEN_COUNT=0
else
    TOKEN_COUNT=$(printf '%s\n' "$TOKENS" | wc -l | tr -d ' ')
fi

# -----------------------------------------------------------------------
# Subtarefa 2.2.4: fail-safe <3 tokens
# -----------------------------------------------------------------------
# Decision 7 do research + dec-006: input com menos de 3 tokens nao
# fornece sinal estatistico suficiente para classificar — emite
# sugestao `manter-atual` score 0 SEM warning ruidoso em stderr
# (operador ve o output normal em stdout). Variavel FAIL_SAFE_REASON
# sera consumida pelas tasks 2.4/2.5 ao montar justificativa final.
FAIL_SAFE=0
FAIL_SAFE_REASON=""
if [ "$TOKEN_COUNT" -lt 3 ]; then
    FAIL_SAFE=1
    FAIL_SAFE_REASON="input com $TOKEN_COUNT token(s) apos sanitizacao (<3 = limite minimo)"
fi

# Exportar para o restante da pipeline classificatoria (placeholder
# atual nao usa, mas tasks 2.3-2.5 consumirao TOKENS, TOKEN_COUNT e
# FAIL_SAFE).
export TOKENS TOKEN_COUNT FAIL_SAFE FAIL_SAFE_REASON INPUT_HAD_NULL

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

if [ "$FAIL_SAFE" = "1" ]; then
    # Caminho explicito de fail-safe (subtarefa 2.2.4) — emite output
    # bem-formado com `manter-atual` score 0 e justificativa citando
    # contagem de tokens. Sem warning em stderr.
    cat <<EOF
## Sugestao

**modelo**: manter-atual
**score**: 0
**alternativa**: none

## Sinais detectados

(nenhum sinal detectado — fail-safe ativado: $FAIL_SAFE_REASON)

## Justificativa

$FAIL_SAFE_REASON; classificador requer >=3 tokens validos para emitir
sugestao com score >=1.

## Acao sugerida (operador humano)

\`(nenhuma troca sugerida — manter modelo atual)\`
EOF
    exit 0
fi

# Placeholder para tasks 2.3-2.5 (match/score/output final). Aqui o
# input ja foi tokenizado com sucesso (>=3 tokens) — proxima task fara
# o match contra catalogo.
cat <<EOF
## Sugestao

**modelo**: manter-atual
**score**: 0
**alternativa**: none

## Sinais detectados

(match contra catalogo nao implementado — tasks 2.3-2.5; tokens=$TOKEN_COUNT)

## Justificativa

esqueleto FASE 2 tasks 2.1+2.2 completas (tokenizacao funcional);
logica de match/score/output final entra em 2.3/2.4/2.5.

## Acao sugerida (operador humano)

\`(nenhuma troca sugerida — manter modelo atual)\`
EOF

exit 0
