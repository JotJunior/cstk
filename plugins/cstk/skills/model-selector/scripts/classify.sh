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
# Logica de classificacao
# =======================================================================
# Status:
#   2.1 esqueleto + path do catalogo                              [DONE]
#   2.2 tokenizacao (tr | tr | sed | grep -v '^$') + fail-safe    [DONE]
#   2.3 match contra catalogo (awk streaming + grep -Fxq)         [DONE]
#   2.4 score 0..2 + justificativa + mapeamento faixa->modelo     [TODO]
#   2.5 output markdown final (4 secoes fixas)                    [TODO]
# -----------------------------------------------------------------------

if [ "$FAIL_SAFE" = "1" ]; then
    # Caminho explicito de fail-safe (subtarefa 2.2.4) — emite output
    # bem-formado com `manter-atual` score 0 e justificativa citando
    # contagem de tokens. Sem warning em stderr.
    #
    # Atende tambem 2.4: score=0, modelo=manter-atual, alternativa=none
    # — invariantes garantidas neste branch sem precisar atravessar a
    # logica de score abaixo.
    #
    # Output segue subtarefa 2.5.1: 4 secoes markdown FIXAS na ordem
    # `## Modelo Sugerido` -> `## Score` -> `## Justificativa` ->
    # `## Alternativa`. Linhas grep-able (`^rasa=`, `^score=`) ficam
    # dentro da secao `## Score` para preservar compat com testes
    # 2.3/2.4 que usam `grep -E '^rasa='` / `grep -E '^score='`.
    cat <<EOF
## Modelo Sugerido

manter-atual

## Score

0

rasa=0 media=0 profunda=0 faixa=indeterminado
score=0 modelo=manter-atual alternativa=none

## Justificativa

$FAIL_SAFE_REASON; classificador requer >=3 tokens validos para emitir
sugestao com score >=1. Nenhum sinal detectado.

## Alternativa

none
EOF
    exit 0
fi

# -----------------------------------------------------------------------
# Subtarefa 2.3.1: parsing awk streaming do catalogo
# -----------------------------------------------------------------------
# Extrai (termo, faixa, peso) das linhas de dados de references/sinais.md.
# Regras:
#   - Ignorar header (`| termo | faixa | peso |`) — heuristica: pular a
#     primeira linha de pipe encontrada (NR>1 nao basta porque ha
#     conteudo pre-tabela no md; usamos $2 != "termo" como filtro).
#   - Ignorar separator (`|---|---|---|`) — filtrado por `!/^\|---/`
#     que cobre `|---`, `| ---`, etc.
#   - Trim de whitespace nas 3 colunas relevantes ($2, $3, $4 — o
#     campo $1 e o vazio antes do primeiro `|`).
#   - Output: 3 colunas separadas por `|` (formato interno). Listas
#     pareadas TERMS (newline-separated) e META (newline-separated
#     "faixa|peso", indices alinhados ao TERMS) sao geradas em pos-pro
#     para permitir `grep -Fxq` rapido sobre TERMS.
# Output do awk = uma linha por sinal: "termo|faixa|peso"
CATALOG=$(awk -F'|' '
    /^\|---/ { next }
    /^\|/ {
        t = $2; f = $3; p = $4
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
        if (t == "termo" || t == "") next
        if (f != "rasa" && f != "media" && f != "profunda") next
        if (p == "") p = "1"
        print t "|" f "|" p
    }
' "$CATALOG_PATH")

if [ -z "$CATALOG" ]; then
    printf '%s: catalogo vazio (esperado >=15 sinais MVP)\n' \
        "$PROG_NAME" >&2
    exit 3
fi

# Lista apenas de termos (uma por linha) para alimentar `grep -Fxq`.
CATALOG_TERMS=$(printf '%s\n' "$CATALOG" | awk -F'|' '{print $1}')

# -----------------------------------------------------------------------
# Subtarefa 2.3.2: match exato `grep -Fxq` por token
# Subtarefa 2.3.3: contadores por faixa (somatorio de pesos)
# -----------------------------------------------------------------------
# Para cada token do input, verifica `grep -Fxq` contra CATALOG_TERMS.
# Se matched, extrai faixa+peso da linha correspondente em CATALOG
# (grep -E "^${token}\|" — anchor + delimitador previne substring).
#
# A lista MATCHED acumula em formato "termo|faixa|peso" — consumida
# pelas tasks 2.4 (score/justificativa) e 2.5 (Sinais detectados).
#
# Deduplicacao: se o mesmo token aparece N vezes no input, conta UMA
# vez (operador escreve "rode rode rode" nao deve inflar score). A
# regra de uniq garante 1 contribuicao por termo distinto.

COUNT_RASA=0
COUNT_MEDIA=0
COUNT_PROFUNDA=0
MATCHED=""

# Tokens unicos (dedup preservando ordem de primeira ocorrencia).
# `awk '!seen[$0]++'` e POSIX e estavel — preferido sobre `sort | uniq`
# que destrombaria ordem (irrelevante aqui, mas mantemos para previsibilidade).
UNIQ_TOKENS=$(printf '%s\n' "$TOKENS" | awk '!seen[$0]++')

# Itera por tokens unicos via `while read`. IFS isolado para nao
# quebrar em tokens com espacos (nao ocorre apos sanitizacao, mas e
# defensivo).
OLD_IFS="$IFS"
IFS='
'
for tok in $UNIQ_TOKENS; do
    # `grep -Fxq` = fixed-string, exact-line, quiet — match exato.
    if printf '%s\n' "$CATALOG_TERMS" | grep -Fxq -- "$tok"; then
        # Match: extrair linha do CATALOG com anchor + delimitador.
        # `grep -E "^${tok}\|"` evita substring (tok="rode" nao casa
        # com hipotetica linha "roder|..."). Como `tok` veio de tokens
        # ASCII-only [a-z0-9]+, nao ha metacaracter regex perigoso.
        _row=$(printf '%s\n' "$CATALOG" | grep -E "^${tok}\|" | head -n 1)
        _faixa=$(printf '%s' "$_row" | awk -F'|' '{print $2}')
        _peso=$(printf '%s' "$_row" | awk -F'|' '{print $3}')

        # Acumular no contador da faixa correspondente.
        case "$_faixa" in
            rasa)     COUNT_RASA=$((COUNT_RASA + _peso)) ;;
            media)    COUNT_MEDIA=$((COUNT_MEDIA + _peso)) ;;
            profunda) COUNT_PROFUNDA=$((COUNT_PROFUNDA + _peso)) ;;
        esac

        # Registrar na lista de matched (consumido por 2.4/2.5).
        if [ -z "$MATCHED" ]; then
            MATCHED="$_row"
        else
            MATCHED="$MATCHED
$_row"
        fi
    fi
done
IFS="$OLD_IFS"

# -----------------------------------------------------------------------
# Subtarefa 2.3.4: regra de conservadorismo FR-005
# -----------------------------------------------------------------------
# FR-005: "em caso de matches em faixas distintas, vence a faixa MAIS
# PROFUNDA". Implementacao:
#   - profunda > media > rasa (ordem de profundidade)
#   - "vencer" = ter pelo menos 1 match (count > 0); a faixa de maior
#     profundidade entre as nao-zero vence
#   - empate de contagem (ex: rasa=2 media=2) -> ainda vence a MAIS
#     PROFUNDA das duas (media neste caso), per FR-005
#   - se TODAS forem zero, FAIXA_VENCEDORA=indeterminado (delegado a
#     2.4/2.5 para mapear -> manter-atual). Como ja passamos do
#     fail-safe (>=3 tokens), pode ocorrer aqui se nenhum token bateu
#     no catalogo (input com 3+ palavras nao listadas).
if [ "$COUNT_PROFUNDA" -gt 0 ]; then
    FAIXA_VENCEDORA="profunda"
elif [ "$COUNT_MEDIA" -gt 0 ]; then
    FAIXA_VENCEDORA="media"
elif [ "$COUNT_RASA" -gt 0 ]; then
    FAIXA_VENCEDORA="rasa"
else
    FAIXA_VENCEDORA="indeterminado"
fi

# Exportar para tasks 2.4 e 2.5.
export CATALOG CATALOG_TERMS MATCHED \
       COUNT_RASA COUNT_MEDIA COUNT_PROFUNDA FAIXA_VENCEDORA

# =======================================================================
# Subtarefa 2.4 — score, justificativa, mapeamento faixa->modelo + fallback
# =======================================================================
# Regra de score (2.4.1, dec-006):
#   0 sinais matched      -> score=0
#   1 sinal matched       -> score=1
#   >=2 sinais matched    -> score=2  (TETO absoluto — 2.4.2)
#
# "sinais matched" = numero TOTAL de termos distintos do catalogo
# que bateram com tokens do input (somatorio de COUNT_RASA + COUNT_MEDIA
# + COUNT_PROFUNDA — como dedup ja foi feita em 2.3 e peso default e 1,
# este somatorio reflete contagem de termos distintos. Caso operador
# customize o catalogo com peso>1, a regra continua valida pelo
# espirito: "mais evidencias = mais confianca" — mas TETO 2 cobre o
# caso ja).
#
# Caso especial: FAIXA_VENCEDORA="indeterminado" (zero matches) sempre
# produz score=0 e modelo=manter-atual independentemente do somatorio
# (defensivo: se MATCHED esta vazio, score nao pode ser >0).
# -----------------------------------------------------------------------

MATCH_TOTAL=$((COUNT_RASA + COUNT_MEDIA + COUNT_PROFUNDA))

if [ "$MATCH_TOTAL" -le 0 ]; then
    SCORE=0
elif [ "$MATCH_TOTAL" -eq 1 ]; then
    SCORE=1
else
    SCORE=2
fi

# -----------------------------------------------------------------------
# Subtarefa 2.4.2: assercao defensiva — score NUNCA pode escapar [0..2].
# -----------------------------------------------------------------------
# Esta e a ultima linha de defesa. Se alguma futura mudanca quebrar a
# regra acima (ex: alguem reintroduzir score=3 por engano), o script
# falha LOUD com exit 3 (erro interno) — preferimos crash a emitir
# sugestao falsa para o operador.
if [ "$SCORE" -lt 0 ] || [ "$SCORE" -gt 2 ]; then
    printf '%s: erro interno — score fora da faixa [0..2] (obtido %s)\n' \
        "$PROG_NAME" "$SCORE" >&2
    exit 3
fi

# -----------------------------------------------------------------------
# Subtarefa 2.4.4: mapa faixa -> modelo (rotulo ABSTRATO — dec-005)
# Subtarefa 2.4.5: mapa modelo -> alternativa de fallback (Decision 9)
# -----------------------------------------------------------------------
# Tier-mapping fixo (rotulos abstratos; nunca strings versionadas
# da forma `claude-<familia>-<N>-<M>` — invariante CHK044, validado
# por test_model_selector_no_concrete_version.sh em 2.5.3).
#
# Defensivo extra: se SCORE=0 OU FAIXA_VENCEDORA="indeterminado", o
# resultado e SEMPRE manter-atual (independente do mapa) — operador
# nao deve trocar modelo sem sinal estatistico.
if [ "$SCORE" -eq 0 ] || [ "$FAIXA_VENCEDORA" = "indeterminado" ]; then
    MODELO="manter-atual"
else
    case "$FAIXA_VENCEDORA" in
        rasa)     MODELO="haiku" ;;
        media)    MODELO="sonnet" ;;
        profunda) MODELO="opus" ;;
        *)        MODELO="manter-atual" ;;  # safety net
    esac
fi

case "$MODELO" in
    haiku)        ALTERNATIVA="sonnet" ;;
    sonnet)       ALTERNATIVA="haiku" ;;
    opus)         ALTERNATIVA="sonnet" ;;
    manter-atual) ALTERNATIVA="none" ;;
    *)            ALTERNATIVA="none" ;;
esac

# -----------------------------------------------------------------------
# Subtarefa 2.4.3: justificativa em texto livre
# -----------------------------------------------------------------------
# Cita literalmente:
#   - cada sinal detectado (termo + faixa)
#   - contagens por faixa
#   - regra aplicada (FR-005 quando empate cross-faixa; teto 2 quando >2)
#
# Formato: prosa curta de 1-3 linhas, sem placeholders, sem TODO.
# Tarefa 2.5 ira embrulhar essa string na secao "## Justificativa" do
# output markdown final — aqui construimos o texto puro.

if [ "$MATCH_TOTAL" -eq 0 ]; then
    JUSTIFICATIVA="nenhum sinal do catalogo detectado nos $TOKEN_COUNT tokens validos do input; sem evidencia para sugerir troca de modelo (rasa=0 media=0 profunda=0)."
else
    # Monta lista "termo (faixa)" separada por virgula a partir de MATCHED
    # (formato "termo|faixa|peso" por linha). awk POSIX-safe.
    _SINAIS_TEXTO=$(printf '%s\n' "$MATCHED" \
        | awk -F'|' 'NF>=2 {
            if (out != "") out = out ", "
            out = out $1 " (" $2 ")"
          }
          END { print out }')

    # Sufixo explicativo da regra aplicada — distingue caso conservador
    # (cross-faixa) do caso uni-faixa, e cita teto quando aplicavel.
    _NAO_ZERO=0
    [ "$COUNT_RASA" -gt 0 ]     && _NAO_ZERO=$((_NAO_ZERO + 1))
    [ "$COUNT_MEDIA" -gt 0 ]    && _NAO_ZERO=$((_NAO_ZERO + 1))
    [ "$COUNT_PROFUNDA" -gt 0 ] && _NAO_ZERO=$((_NAO_ZERO + 1))

    if [ "$_NAO_ZERO" -ge 2 ]; then
        _REGRA="regra FR-005 aplicada (sinais em faixas distintas -> vence a mais profunda: $FAIXA_VENCEDORA)"
    else
        _REGRA="sinais consistentes em faixa unica ($FAIXA_VENCEDORA)"
    fi

    if [ "$MATCH_TOTAL" -gt 2 ]; then
        _REGRA="$_REGRA; TETO 2 aplicado (score teto, dec-006)"
    fi

    JUSTIFICATIVA="sinais detectados: $_SINAIS_TEXTO; contagens rasa=$COUNT_RASA media=$COUNT_MEDIA profunda=$COUNT_PROFUNDA; $_REGRA."
fi

# Exportar para task 2.5 (output markdown final).
export SCORE MODELO ALTERNATIVA JUSTIFICATIVA MATCH_TOTAL

# -----------------------------------------------------------------------
# Subtarefa 2.5.1: output markdown definitivo com 4 secoes FIXAS.
# -----------------------------------------------------------------------
# Estrutura obrigatoria do bloco (na ordem exata):
#   ## Modelo Sugerido    -> rotulo abstrato (haiku|sonnet|opus|manter-atual)
#   ## Score              -> int 0..2 + linhas grep-able preservadas
#   ## Justificativa      -> prosa construida em 2.4.3
#   ## Alternativa        -> rotulo abstrato (sonnet|haiku|none)
#
# Subtarefa 2.5.2: rotulos no output SAO sempre abstratos. O mapa
# faixa->modelo (2.4.4) e modelo->alternativa (2.4.5) emite apenas as
# strings literais haiku/sonnet/opus/manter-atual/none — nunca uma
# versao concreta da forma `claude-<familia>-<N>-<M>`. Validado por
# test_model_selector_no_concrete_version.sh (subtarefa 2.5.3).
#
# As linhas `rasa=N media=N profunda=N faixa=X` e
# `score=N modelo=X alternativa=Y` ficam DENTRO da secao `## Score`
# para preservar compat com:
#   - tests/cstk/test_model_selector_match.sh   (grep -E '^rasa=')
#   - tests/cstk/test_model_selector_score.sh   (grep -E '^score=')
# Ambos os greps usam line-anchor; basta que comecem em coluna 0.
# -----------------------------------------------------------------------
cat <<EOF
## Modelo Sugerido

$MODELO

## Score

$SCORE

rasa=$COUNT_RASA media=$COUNT_MEDIA profunda=$COUNT_PROFUNDA faixa=$FAIXA_VENCEDORA
score=$SCORE modelo=$MODELO alternativa=$ALTERNATIVA

## Justificativa

$JUSTIFICATIVA

## Alternativa

$ALTERNATIVA
EOF

# -----------------------------------------------------------------------
# Re-checagem defensiva final (2.4.2): garante que NADA neste arquivo
# poderia ter mutado SCORE acima de 2 depois do calculo.
# -----------------------------------------------------------------------
if [ "$SCORE" -lt 0 ] || [ "$SCORE" -gt 2 ]; then
    printf '%s: erro interno pos-output — score=%s fora de [0..2]\n' \
        "$PROG_NAME" "$SCORE" >&2
    exit 3
fi

exit 0
