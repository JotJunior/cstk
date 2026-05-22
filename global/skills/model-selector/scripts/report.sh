#!/bin/sh
# shellcheck shell=sh
#
# report.sh — Esqueleto do relatorio agregado (FASE 4, task 4.1)
#
# Skill: model-selector
# Pipeline: 1..N state.json -> leitura read-only -> (futuras tasks 4.2/4.3)
#           agregacao jq OU fallback awk -> tabela markdown em stdout.
# Status: ESQUELETO APENAS (subtarefas 4.1.1-4.1.4).
#         A logica de agregacao (jq happy-path) entra na task 4.2;
#         o fallback `awk` puro entra na task 4.3; testes de
#         confinamento, equivalencia byte-identical e performance
#         entram em 4.4 com fixtures geradas em 4.5.
#
# Conformidade:
#   - POSIX puro (#!/bin/sh + set -eu, sem bash-isms) — CHK001
#   - `jq` PERMITIDO neste arquivo apenas (carve-out 1.1.0, FR-010a).
#     Nenhum outro script da skill pode invocar jq.
#   - Sem coleta remota; offline-only — Principio IV
#   - Read-only: este script NAO escreve em NENHUM state.json passado
#     como argumento. Saida vai exclusivamente para stdout/stderr.
#
# -----------------------------------------------------------------------
# Exit codes (subtarefa 4.1.4 — invariante testavel via tests/cstk/)
# -----------------------------------------------------------------------
#   0  sucesso — relatorio emitido em stdout (mesmo que vazio quando
#      nenhum state.json contem `metricas_acumuladas.model_selector`
#      populado). Esqueleto atual: emite header markdown placeholder.
#   2  argumento invalido — nenhum arg fornecido, OU ao menos um arg
#      aponta para path que nao existe (arquivo ausente). Stderr recebe
#      mensagem `model-selector-report: ...`.
#   3  arquivo nao legivel — arquivo existe mas sem permissao de leitura
#      (ex: chmod 000). Stderr descreve o path afetado.
#
#   Observacao: separamos 2 (arg invalido / ausente) de 3 (existe-mas-
#   nao-legivel) para que o operador distinga "errei o path" de
#   "problema de filesystem/permissao". Alinha com classify.sh:
#   exit 2 = uso, exit 3 = IO.
#
# -----------------------------------------------------------------------
# Input (FR-012, FR-010a, Decision 5 do research)
# -----------------------------------------------------------------------
#   Forma 1 (paths posicionais):
#     report.sh /path/featA/state.json /path/featB/state.json ...
#   Forma 2 (placeholder para 4.4.3 — `--state-dir <dir>`):
#     NAO IMPLEMENTADO neste esqueleto. Sera adicionado na task que
#     introduzir descoberta de state.json em diretorios. Por enquanto,
#     a flag e desconhecida e cai como path invalido (exit 2).
#
#   Comportamento read-only:
#     Cada path passado e ABERTO apenas para leitura (via `cat > /dev/null`
#     como sonda de legibilidade nesta fase do esqueleto; tasks 4.2/4.3
#     substituem por parsing jq/awk real, ambos tambem read-only).
#     ZERO redirecionamentos de escrita (`>`, `>>`, `tee`, `cp -f`, `mv`)
#     contra qualquer path de input. Validado pelo teste
#     test_model_selector_report_skeleton.sh §zero-escritas.
#
# -----------------------------------------------------------------------
# Deteccao de jq (subtarefa 4.1.2)
# -----------------------------------------------------------------------
#   `command -v jq >/dev/null 2>&1` — POSIX puro, sem bash-isms.
#   Resultado guardado em HAS_JQ (1=presente, 0=ausente). O esqueleto
#   apenas EXPORTA esse flag em modo verbose (stderr); o uso real do
#   flag para selecionar caminho jq vs awk entra nas tasks 4.2 e 4.3.
#
# =======================================================================

set -eu

PROG_NAME="model-selector-report"

# -----------------------------------------------------------------------
# Subtarefa 4.1.2: deteccao de jq via command -v (POSIX puro)
# -----------------------------------------------------------------------
# Guardamos em HAS_JQ para uso pelas tasks 4.2/4.3. Este esqueleto nao
# ramifica logica — apenas deixa a deteccao pronta + auditavel.
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=1
else
    HAS_JQ=0
fi

# -----------------------------------------------------------------------
# Subtarefa 4.1.3: validacao read-only dos paths recebidos
# -----------------------------------------------------------------------
# Regras:
#   - >=1 arg obrigatorio; sem args -> exit 2.
#   - cada arg deve existir como arquivo regular -> caso contrario exit 2.
#   - cada arg deve ser legivel (-r) -> caso contrario exit 3.
#   - sonda read-only: `cat "$path" > /dev/null` confirma legibilidade
#     SEM nunca abrir o arquivo para escrita. As tasks 4.2/4.3 trocam
#     essa sonda por parsing real (tambem read-only).
if [ "$#" -lt 1 ]; then
    printf '%s: pelo menos 1 arquivo state.json e obrigatorio\n' \
        "$PROG_NAME" >&2
    printf '%s: uso: report.sh <state.json> [<state.json> ...]\n' \
        "$PROG_NAME" >&2
    exit 2
fi

for _path in "$@"; do
    if [ ! -e "$_path" ]; then
        printf '%s: arquivo nao encontrado: %s\n' "$PROG_NAME" "$_path" >&2
        exit 2
    fi
    if [ ! -f "$_path" ]; then
        printf '%s: nao e arquivo regular: %s\n' "$PROG_NAME" "$_path" >&2
        exit 2
    fi
    if [ ! -r "$_path" ]; then
        printf '%s: sem permissao de leitura: %s\n' "$PROG_NAME" "$_path" >&2
        exit 3
    fi
    # Sonda read-only final: confirma que o kernel deixa abrir o
    # arquivo para leitura. Redirect `> /dev/null` descarta o conteudo;
    # nenhum dado e gravado de volta ao path de entrada.
    if ! cat -- "$_path" > /dev/null 2>&1; then
        printf '%s: falha de IO ao ler: %s\n' "$PROG_NAME" "$_path" >&2
        exit 3
    fi
done

# -----------------------------------------------------------------------
# Subtarefa 4.1.1: ate aqui, o esqueleto cumpriu seu contrato POSIX
# (shebang + set -eu, validacao de args, deteccao de jq, leitura read-
# only). Header markdown + tag inline `jq_detectado=<0|1>` permanecem
# emitidos ANTES da tabela para auditoria do operador.
# -----------------------------------------------------------------------
printf '# Relatorio agregado model-selector\n'
printf '\n'
printf '<!-- jq_detectado=%d arquivos_validados=%d -->\n' \
    "$HAS_JQ" "$#"
printf '\n'

# =======================================================================
# FASE 4.2 — Caminho `jq` (happy path) — CAMINHO PREFERIDO
# =======================================================================
# Subtarefa 4.2.3: documentacao inline da escolha.
#
# Este e o CAMINHO PREFERIDO para agregacao de
# `metricas_acumuladas.model_selector` (refs: FR-010a (a) — carve-out
# 1.1.0 que autoriza `jq` apenas neste arquivo; Decision 5 do research).
# A task 4.3 implementa um FALLBACK `awk` puro com output BYTE-IDENTICAL,
# selecionado quando `command -v jq` retorna falso (HAS_JQ=0). Em
# ambientes com jq disponivel, este caminho e ~10x mais rapido e ~3x
# mais conciso que o fallback awk, alem de ter cobertura nativa de
# parsing JSON aninhado e tolerancia a campos lazy/ausentes.
#
# Subtarefa 4.2.1: bloco `if HAS_JQ=1` agrega via expressao jq compacta.
# Subtarefa 4.2.2: emite tabela markdown com 5 colunas fixas:
#   feature | sugestoes_total | aceitas | rejeitadas | modelo_final_predominante
# (uma linha por state.json passado como argumento).
#
# Estrategia de agregacao:
#   - 1 invocacao de `jq` POR arquivo de input (loop shell). Razao:
#     `.execucao.short_name` e por-arquivo; processar todos juntos com
#     `jq -s` exigiria correlacao manual de index entre array slurped
#     e $ARGS.positional, sem ganho de performance perceptivel em N<=20
#     state.json (escala alvo, fixture 4.5).
#   - Filtro lazy: `.metricas_acumuladas.model_selector // null` cobre
#     o caso de campo ausente (state.json antigo) E o caso de campo
#     presente mas vazio. Em ambos, emite linha com zeros + rotulo
#     `(sem dados)`.
#   - Rotulo `feature`: prefere `.execucao.short_name`; fallback para
#     `basename "$f" .json` (passado via --arg) quando ausente. Garante
#     tabela legivel mesmo para state.json sem o campo (fixtures de
#     teste, mock manual).
#   - `modelo_final_predominante`: derivado como o MODE de
#     `por_modelo_sugerido` (chave com maior contador). Empate -> chave
#     alfabeticamente menor (sort estavel). Quando TODAS as 4 chaves
#     valem 0, emite `(sem dados)` em vez de uma chave arbitraria —
#     evita falsa impressao de tendencia. O schema (state-extension.md)
#     NAO armazena este campo de forma persistida; ele e derivado em
#     leitura. Rotulo abstrato (haiku|sonnet|opus|manter-atual) sem
#     sufixo de versao — alinhado a FR-002a.
# -----------------------------------------------------------------------
if [ "$HAS_JQ" = "1" ]; then
    # Cabecalho da tabela markdown (5 colunas fixas).
    printf '| feature | sugestoes_total | aceitas | rejeitadas | modelo_final_predominante |\n'
    printf '|---|---:|---:|---:|---|\n'

    for _path in "$@"; do
        _basename=$(basename -- "$_path" .json)
        # Expressao jq compacta — uma linha por arquivo, formato TSV
        # convertido inline para a sintaxe `| col1 | col2 | ... |` da
        # tabela markdown. Tolera lazy null, total zero e rotulos do
        # enum fixo de `por_modelo_sugerido`.
        jq -r --arg fb "$_basename" '
            (.execucao.short_name // $fb) as $feat
            | (.metricas_acumuladas.model_selector // null) as $m
            | if $m == null then
                "| \($feat) | 0 | 0 | 0 | (sem dados) |"
              else
                ($m.por_modelo_sugerido // {}) as $pm
                | (
                    [ ($pm | to_entries[]) ]
                    | sort_by(-.value, .key)
                    | (.[0] // {key:"(sem dados)", value:0})
                    | if .value == 0 then "(sem dados)" else .key end
                  ) as $pred
                | "| \($feat) | \($m.sugestoes_total // 0) | \(($m.por_resultado.aceitas) // 0) | \(($m.por_resultado.rejeitadas) // 0) | \($pred) |"
              end
        ' -- "$_path"
    done

    exit 0
fi

# =======================================================================
# FASE 4.3 — Fallback `awk` puro (HAS_JQ=0) — IMPLEMENTADO EM TASK 4.3
# =======================================================================
# Quando jq nao esta disponivel no PATH, este bloco PRECISA emitir output
# BYTE-IDENTICAL ao caminho jq acima (mesmas 5 colunas, mesma ordem de
# linhas, mesma derivacao de mode com tie-break alfabetico, mesmo rotulo
# `(sem dados)` para totais zero / lazy null). Sera implementado em task
# 4.3 via parsing awk linha-a-linha. Por enquanto, este esqueleto sai
# com exit 0 + tabela vazia + comentario inline para que o esqueleto
# do report continue valido (FR-010a (a)).
printf '| feature | sugestoes_total | aceitas | rejeitadas | modelo_final_predominante |\n'
printf '|---|---:|---:|---:|---|\n'
printf '<!-- fallback awk pendente: task 4.3 -->\n'

exit 0
