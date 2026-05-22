#!/bin/sh
# test_report_jq_confinement.sh
#
# Cobre subtarefa 4.4.2 da feature `model-selector` (Ref:
# docs/specs/model-selector/tasks.md L239, FR-010a (b), CHK009,
# CHK050, CHK051, CHK053).
#
# Objetivo: garantir que `jq` so aparece em CODIGO EXECUTAVEL de UM
# UNICO arquivo da skill — `global/skills/model-selector/scripts/report.sh`.
# Qualquer outro arquivo executavel (`*.sh`) que carregue `jq` em
# linha NAO-comentario constitui violacao do carve-out 1.1.0 e falha
# o teste.
#
# Definicao operacional de "codigo executavel":
#   - Linha em arquivo `.sh` sob `global/skills/model-selector/`
#   - QUE NAO comece com `#` (apos eventual whitespace), ou seja:
#     `grep -nE '\bjq\b' <arquivos> | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'`
#   - SKILL.md (markdown) e references/*.md (markdown) NAO contam como
#     codigo executavel — mencoes textuais ali sao legitimas (ex: texto
#     "skill e POSIX-pura sem jq" no Quickstart). CHK053 confirma que
#     CHANGELOG/README/docs ficam fora do escopo desta verificacao.
#   - Comentarios shell (`#`) em qualquer `.sh` ficam fora — o ponto e
#     INVOCACAO de jq, nao narrativa sobre jq.
#
# Estrategia: usa `grep -rn` para listar todas as ocorrencias do regex
# `\bjq\b` no escopo executavel, filtra linhas-comentario, deduplica
# por arquivo, e exige que a unica entrada restante seja exatamente
# `scripts/report.sh`.
#
# Cenarios:
#   1. exatamente_um_arquivo_invoca_jq
#        Lista deduplicada por arquivo deve ter cardinalidade 1.
#   2. arquivo_unico_e_report_sh
#        O unico arquivo da lista deve ter basename `report.sh`.
#   3. nenhuma_invocacao_executavel_em_classify_sh
#        Garantia explicita de que `classify.sh` (caminho de
#        classificacao) nao invoca jq mesmo em codigo nao-comentado —
#        protege contra regressao do FR-010a.
#   4. mencao_textual_em_skill_md_permanece_permitida
#        Smoke: confirma que a mencao em SKILL.md NAO falha o teste
#        — markdown e excluido do escopo executavel deliberadamente.
#
# Refs:
#   CHK009  jq aparece em exatamente 1 arquivo executavel da skill
#   CHK050  Test mecaniza grep + filtro de comentarios + dedup por arquivo
#   CHK051  Exit 0 se cardinalidade == 1; exit 1 se != 1
#   CHK053  SKILL.md, references/*.md, CHANGELOG.md, README.md
#           excluidos do escopo executavel

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_DIR="$REPO_ROOT/global/skills/model-selector"
export SKILL_DIR

# ----------------------------------------------------------------------
# Helpers — prefixo `_cf_` (confinement)
# ----------------------------------------------------------------------

# Lista arquivos `.sh` sob $SKILL_DIR que contem `jq` em linha
# NAO-comentario. Saida: uma linha por arquivo (paths relativos a
# $REPO_ROOT), sem duplicatas.
_cf_executable_jq_files() {
  # Escopo executavel canonico = scripts/*.sh
  # (a skill nao tem outros .sh executaveis hoje, mas o regex e
  # generico — pega qualquer .sh sob skill_dir/).
  find "$SKILL_DIR" -type f -name '*.sh' -print 2>/dev/null \
    | while IFS= read -r _path; do
        # grep -n imprime LINHA:CONTEUDO; descartamos linhas cuja
        # primeira coluna nao-espaco e `#` (comentario shell).
        _hits=$(grep -nE '\bjq\b' -- "$_path" 2>/dev/null \
                | grep -vE ':[[:space:]]*#' || true)
        if [ -n "$_hits" ]; then
          printf '%s\n' "$_path"
        fi
      done \
    | sort -u
}

# ----------------------------------------------------------------------
# 4.4.2.a: cardinalidade 1 — exatamente 1 arquivo executavel invoca jq.
# ----------------------------------------------------------------------
scenario_4_4_2_exatamente_um_arquivo_invoca_jq() {
  _cf_list=$(_cf_executable_jq_files)
  _cf_count=$(printf '%s\n' "$_cf_list" | sed '/^$/d' | wc -l | tr -d ' ')

  if [ "$_cf_count" = "0" ]; then
    _fail "cardinalidade_zero" \
      "nenhum arquivo executavel invoca jq — esperado exatamente 1 (scripts/report.sh). Lista: <vazia>"
    return 1
  fi
  if [ "$_cf_count" -gt 1 ]; then
    _fail "cardinalidade_maior_que_1" \
      "mais de 1 arquivo executavel invoca jq (esperado 1=report.sh). Lista:
$_cf_list"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.4.2.b: arquivo unico = scripts/report.sh
# ----------------------------------------------------------------------
scenario_4_4_2_arquivo_unico_e_report_sh() {
  _cf_list=$(_cf_executable_jq_files)
  _cf_first=$(printf '%s\n' "$_cf_list" | sed '/^$/d' | head -n 1)

  if [ -z "$_cf_first" ]; then
    _fail "arquivo_unico_vazio" \
      "lista de arquivos executaveis com jq vazia — esperado scripts/report.sh"
    return 1
  fi

  case "$_cf_first" in
    *"/scripts/report.sh") ;;
    *)
      _fail "arquivo_unico_nao_report_sh" \
        "arquivo executavel com jq nao e scripts/report.sh; obtido: $_cf_first"
      return 1
      ;;
  esac
  return 0
}

# ----------------------------------------------------------------------
# 4.4.2.c: classify.sh nao invoca jq em codigo executavel
# (regressao guard — FR-010a). Mencoes em comentario sao toleradas
# desde que o regex de filtro `:[[:space:]]*#` esteja consistente.
# ----------------------------------------------------------------------
scenario_4_4_2_classify_sh_sem_invocacao_executavel() {
  _cf_path="$SKILL_DIR/scripts/classify.sh"
  if [ ! -f "$_cf_path" ]; then
    _fail "classify_ausente" \
      "scripts/classify.sh nao existe — pre-condicao da skill violada"
    return 1
  fi
  _cf_hits=$(grep -nE '\bjq\b' -- "$_cf_path" 2>/dev/null \
             | grep -vE ':[[:space:]]*#' || true)
  if [ -n "$_cf_hits" ]; then
    _fail "classify_invoca_jq" \
      "classify.sh invoca jq em codigo executavel — viola FR-010a:
$_cf_hits"
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 4.4.2.d: mencao textual em SKILL.md permanece permitida — markdown
# fora do escopo executavel (CHK053). Esse cenario confirma que a
# heuristica do helper NAO inclui .md por engano. Falsa positivo aqui
# = regressao silenciosa do filtro.
# ----------------------------------------------------------------------
scenario_4_4_2_skill_md_textual_permitido() {
  _cf_skill="$SKILL_DIR/SKILL.md"
  if [ ! -f "$_cf_skill" ]; then
    _fail "skill_md_ausente" \
      "SKILL.md ausente — pre-condicao violada"
    return 1
  fi
  # Mencao textual existe? (caso contrario, este scenario perde proposito)
  if ! grep -q 'jq' -- "$_cf_skill"; then
    printf 'note: SKILL.md nao menciona jq textualmente — scenario tautologico\n' >&2
    return 0
  fi
  # Helper NAO deve incluir SKILL.md na lista (escopo = *.sh only).
  _cf_list=$(_cf_executable_jq_files)
  case "$_cf_list" in
    *"SKILL.md"*)
      _fail "skill_md_indevido_na_lista" \
        "SKILL.md apareceu na lista de arquivos executaveis com jq — filtro do helper esta quebrado"
      return 1
      ;;
    *)
      ;;
  esac
  return 0
}

run_all_scenarios
