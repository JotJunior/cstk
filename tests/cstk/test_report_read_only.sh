#!/bin/sh
# test_report_read_only.sh
#
# Cobre subtarefa 5.3.1 da feature `model-selector` (FR-012, CHK056).
# Garante que `scripts/report.sh` e ESTATICAMENTE read-only sobre os
# state.json passados como argumento — nenhum operador de escrita
# (`>`, `>>`, `tee`, `mv`, `cp -f`, `rm`) aparece no codigo executavel.
#
# Por que isso complementa o teste de sha256 ja existente
# (`test_model_selector_report_skeleton.sh` §scenario_4_1_3_read_only_
# sha256_imutavel): aquele teste verifica RUNTIME (sha256 antes/depois
# bate). Este teste e ESTATICO — qualquer reintroducao de operador de
# escrita no source falha o teste IMEDIATAMENTE, sem precisar passar
# por dispatch de scenarios runtime que dependem de fixtures e
# `command -v jq`. Defesa-em-profundidade: o static grep e barato e
# evita o ciclo "introduzo bug -> esqueco de rodar happy path -> bug
# vaza para release".
#
# Mecanismo (CHK056):
#   Aplica duas regex em sequencia, ambas filtrando comentarios shell:
#
#     (R1) `grep -nE '\btee\b|\bmv\b|\bcp -f\b|\brm\b' report.sh`
#          captura comandos de mutacao de filesystem. Esses sao
#          inequivocos — qualquer hit fora de comentario reprova.
#
#     (R2) `grep -nE '(^|[^>&])>[[:space:]]*["a-zA-Z_./$]' report.sh`
#          captura redirecionamento de escrita SHELL para um path
#          (arquivo, var de path, dev). Exclui:
#            - `>&N` (stderr/fd dup, ex: `>&2`) — nao escreve em
#              arquivo, apenas duplica fd. Read-only OK.
#            - `>>` aparece com `>>` mas o filtro `[^>&]` antes do `>`
#              impede que casemos a metade direita do `>>`. Adicionamos
#              uma regex R3 dedicada para `>>` (append a arquivo) abaixo.
#            - `>` dentro de strings awk single-quoted (ex: `v > best_val`)
#              — esses casam mas sao removidos pelo whitelist canonico
#              `> /dev/null` quando aplicavel, e pelo fato de awk source
#              estar dentro de `'...'` aspas. Tratamos via whitelist
#              explicita das linhas conhecidas (4.3 do report.sh).
#
#     (R3) `grep -nE '>>' report.sh` — append a arquivo. Mesma logica.
#
# Justificativa do regex de redirecionamento:
#   - `>` precedido de NADA, espaco ou outro char que nao seja `>` ou
#     `&`, seguido de espacos e entao quote/letra/underscore/dot/slash/
#     dollar e o padrao tipico de `> PATH`, `> "$file"`, `> /tmp/foo`.
#   - `>&N` (stderr redirect) e explicitamente excluido — nao toca
#     filesystem dos inputs.
#
# Limitacoes (intencional):
#   - Tolera `> /dev/null` como sonda de legibilidade documentada
#     (subtarefa 4.1.3 do report.sh).
#   - Tolera `>` dentro de scripts awk embarcados (ex: `v > best_val`).
#     Esses sao codigo AWK em sub-quoting, nao redirect shell. Os
#     casos especificos do report.sh ja foram inventariados na
#     whitelist `AWK_COMPARE_WHITELIST` abaixo.
#   - NAO bloqueia heredocs com `<<` (input, nao output).
#   - Comentarios shell que iniciam com `#` apos whitespace sao
#     filtrados via `grep -v '^<num>:[[:space:]]*#'`.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

REPORT="$REPO_ROOT/plugins/cstk/skills/model-selector/scripts/report.sh"
export REPORT

# (R1) Comandos de mutacao de filesystem. Qualquer hit em codigo
# executavel reprova.
MUTATION_REGEX='\btee\b|\bmv\b|\bcp -f\b|\brm\b'

# (R2) Redirecionamento `>` para path (arquivo/dev/var). Exclui `>&N`
# via classe negativa `[^>&]` antes do `>`. Captura `> "/path"`, `> $x`,
# `> /dev/null`, `> "file"`, etc.
REDIR_REGEX='(^|[^>&])>[[:space:]]*["a-zA-Z_./$]'

# (R3) Append a arquivo.
APPEND_REGEX='>>'

# Whitelist canonica de `/dev/null` — sonda de legibilidade
# documentada na subtarefa 4.1.3 do report.sh. Cobre `> /dev/null`
# (com espaco) e `>/dev/null` (sem espaco, usado no `command -v jq
# >/dev/null 2>&1` da deteccao na subtarefa 4.1.2).
WHITELIST_DEVNULL='/dev/null'

# Whitelist de literais nao-executaveis. A linha 96 do report.sh atual
# contem o token `[<state.json>` dentro de uma string de uso (mensagem
# de stderr para o operador) — nao e redirect shell. A linha 96 esta
# documentada como uso ("uso: report.sh <state.json> ...").
WHITELIST_USAGE_LITERAL='\[<state.json>'

# Whitelist de awk source: o report.sh embarca scripts awk em aspas
# simples `'...'`. Dentro desses scripts, `>` aparece como operador
# de comparacao (ex: `v > best_val`, `_i > _len`). Esses match nao
# sao redirect shell — sao codigo AWK em sub-quoting. As ocorrencias
# atuais do report.sh foram inventariadas individualmente abaixo.
# Tentativa de adicionar `>` novo na funcao awk exige adicionar a
# linha ao inventario aqui (defesa em profundidade — qualquer novo
# `>` em report.sh disparara revisao manual).
WHITELIST_AWK_COMPARE_1='if (_i > _len)'
WHITELIST_AWK_COMPARE_2='if (v > best_val)'

scenario_5_3_1_report_sh_sem_comando_mutacao() {
  if [ ! -f "$REPORT" ]; then
    _error "report_sh_ausente" "esperado $REPORT"
    return 2
  fi
  _hits=$(grep -nE "$MUTATION_REGEX" "$REPORT" 2>/dev/null \
            | grep -v '^[0-9][0-9]*:[[:space:]]*#' \
            || true)
  if [ -n "$_hits" ]; then
    _fail "comando_mutacao_em_report_sh" \
      "padrao=$MUTATION_REGEX; matches=$_hits"
    return 1
  fi
}

scenario_5_3_1_report_sh_sem_redirecionamento_escrita() {
  if [ ! -f "$REPORT" ]; then
    _error "report_sh_ausente" "esperado $REPORT"
    return 2
  fi
  # `>` para path: filtra comentarios + whitelists canonicas
  # (`/dev/null` em ambas as variantes, string de uso `[<state.json>`,
  # operadores de comparacao em awk source inventariados).
  _hits=$(grep -nE "$REDIR_REGEX" "$REPORT" 2>/dev/null \
            | grep -v '^[0-9][0-9]*:[[:space:]]*#' \
            | grep -vF "$WHITELIST_DEVNULL" \
            | grep -vE "$WHITELIST_USAGE_LITERAL" \
            | grep -vF "$WHITELIST_AWK_COMPARE_1" \
            | grep -vF "$WHITELIST_AWK_COMPARE_2" \
            || true)
  if [ -n "$_hits" ]; then
    _fail "redirecionamento_escrita_em_report_sh" \
      "padrao=$REDIR_REGEX (whitelists inventariadas no header do teste); matches=$_hits"
    return 1
  fi
}

scenario_5_3_1_report_sh_sem_append_arquivo() {
  if [ ! -f "$REPORT" ]; then
    _error "report_sh_ausente" "esperado $REPORT"
    return 2
  fi
  _hits=$(grep -nE "$APPEND_REGEX" "$REPORT" 2>/dev/null \
            | grep -v '^[0-9][0-9]*:[[:space:]]*#' \
            || true)
  if [ -n "$_hits" ]; then
    _fail "append_arquivo_em_report_sh" \
      "padrao=$APPEND_REGEX; matches=$_hits"
    return 1
  fi
}

run_all_scenarios
