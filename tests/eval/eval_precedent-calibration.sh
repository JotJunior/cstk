#!/bin/sh
# eval_precedent-calibration.sh — eval NAO-GATEANTE de calibracao do limiar
# de `cstk recall --precedents` sobre a base REAL (~/.claude/cstk/knowledge.db).
#
# Feature: clarify-precedent-source (tasks.md 5.1, quickstart Cenario 8)
# Ref: docs/specs/clarify-precedent-source/research.md §Decision 2 (limiar
#      0.55 calibrado em 2026-09-30) e plan.md P-3 (premissa aberta: corpus
#      dominado por um projeto).
#
# O que faz:
#   1. PARES (5.1.2): reapresenta ao modo `--precedents` a pergunta de um
#      bloco respondido (excluindo o PROPRIO registro da saida) e reporta se o
#      bloco-par foi recuperado. Pares default = os medidos na calibracao
#      (108/112 e 242/251, ids de `blocks.id`). Sobrescreva com
#      EVAL_PAIRS="108:112 242:251".
#   2. DISTRIBUICAO (5.1.3): para uma amostra de blocos respondidos, imprime o
#      histograma do Jaccard dos vizinhos (top-5 por bloco, sem o proprio
#      bloco), nas mesmas faixas da research Decision 2, para voce comparar
#      com a medicao original (1906/57/11/19/20/27/40 pares em 2080).
#
# Limites honestos (leia antes de interpretar):
#   - `blocks.id` e AUTOINCREMENT: um `cstk recall --reindex` renumera. Os ids
#     default sao os da medicao de 2026-09-30; se nao existirem ou apontarem
#     para outro assunto, o par e reportado como "id ausente" — NAO e falha.
#   - O corpus CRESCE; contagens do histograma mudam. O que importa e a FORMA
#     (pico em [0,0.2) e cauda >= 0.7), nao o numero absoluto.
#   - A amostra (EVAL_SAMPLE, default 60 blocos) e menor que a medicao original
#     (416). O histograma e indicativo, nao substitui a recalibracao completa.
#   - Usa o codigo do REPO (cli/lib/recall.sh), nao o binario instalado.
#
# Exit: 0 conforme · 1 divergencia (investigar) · 2 nao avaliavel (sem
# sqlite3, sem knowledge.db, etc. — NAO e reprovacao).
#
# NAO GATEIA RELEASE. Vermelho aqui e sinal para recalibrar o limiar
# (RECALL_PREC_MIN_SIMILARITY), nunca bloqueio automatico.

set -u

_say()  { printf '%s\n' "$*"; }
_skip() { printf 'SKIP: %s\n' "$*" >&2; exit 2; }
_bad()  { printf 'DIVERGENCIA: %s\n' "$*" >&2; }

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

DB="${CSTK_KNOWLEDGE_DB:-$HOME/.claude/cstk/knowledge.db}"
[ -f "$DB" ] || _skip "knowledge.db ausente ($DB) — nada a calibrar"
command -v sqlite3 >/dev/null 2>&1 || _skip "sqlite3 indisponivel"
[ -f "$CSTK_LIB/recall.sh" ] || _skip "cli/lib/recall.sh ausente"

PAIRS="${EVAL_PAIRS:-108:112 242:251}"
SAMPLE="${EVAL_SAMPLE:-60}"

# _prec QUESTION [flags...] -> stdout do modo --precedents (codigo do repo).
_prec() {
  _pq="$1"; shift
  sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; recall_main --precedents "$@"' \
    _ "$_pq" --db "$DB" "$@" 2>/dev/null
}

# _field ID COLUMN -> valor de blocks.COLUMN (vazio se id ausente).
_field() {
  sqlite3 "$DB" "SELECT replace(replace(coalesce($2,''),char(10),' '),char(13),' ') FROM blocks WHERE id = $1 AND status = 'respondido';" 2>/dev/null
}

# _ref ID -> project/feature/source_id do bloco.
_ref() {
  sqlite3 "$DB" "SELECT project || '/' || feature || '/' || source_id FROM blocks WHERE id = $1;" 2>/dev/null
}

_fail=0

_say "== Pares (limiar default do modo; ids de blocks.id) =="
for _pair in $PAIRS; do
  _a=${_pair%%:*}; _b=${_pair##*:}
  _qa=$(_field "$_a" question)
  _refa=$(_ref "$_a"); _refb=$(_ref "$_b")
  if [ -z "$_qa" ] || [ -z "$_refb" ]; then
    _say "par $_a/$_b: id ausente ou nao respondido — ignorado (ids podem ter mudado apos --reindex)"
    continue
  fi
  # Bloco-par tem a mesma pergunta/resposta/data? (duplicata de ingestao colapsa por dedup)
  _same=$(sqlite3 "$DB" "SELECT count(*) FROM blocks x JOIN blocks y ON x.question = y.question AND coalesce(x.answer,'') = coalesce(y.answer,'') AND coalesce(x.answered_at,'') = coalesce(y.answered_at,'') WHERE x.id = $_a AND y.id = $_b;" 2>/dev/null)
  # --limit alto: o proprio registro ocupa uma vaga; excluimos da analise abaixo.
  _out=$(_prec "$_qa" --limit 10 --max-bytes 100000)
  _hit=$(printf '%s\n' "$_out" | grep -F "ref=$_refb " | head -n 1)
  _self=$(printf '%s\n' "$_out" | grep -F "ref=$_refa " | head -n 1)
  if [ -n "$_hit" ]; then
    _sim=$(printf '%s' "$_hit" | sed -n 's/.*similarity=\([0-9.]*\).*/\1/p')
    _say "par $_a/$_b: RECUPERADO ($_refb, similarity=$_sim)"
  elif [ "${_same:-0}" -ge 1 ] && [ -n "$_self" ]; then
    _say "par $_a/$_b: COLAPSADO por dedup (I-3): mesmo question/answer/answered_at do proprio registro (entrada unica)"
  else
    _bad "par $_a/$_b: $_refb NAO recuperado pela pergunta de $_refa"
    _fail=1
  fi
done

_say ""
_say "== Distribuicao de Jaccard dos vizinhos (amostra de ate $SAMPLE blocos) =="
_total=$(sqlite3 "$DB" "SELECT count(*) FROM blocks WHERE status = 'respondido' AND coalesce(answer,'') <> '';" 2>/dev/null)
_total=${_total:-0}
if [ "$_total" -eq 0 ]; then
  _say "nenhum bloco respondido na base — nada a medir"
  exit "$_fail"
fi
_step=$(( _total / SAMPLE ))
[ "$_step" -ge 1 ] || _step=1
_ids=$(sqlite3 "$DB" "SELECT id FROM blocks WHERE status = 'respondido' AND coalesce(answer,'') <> '' AND (id % $_step) = 0 ORDER BY id LIMIT $SAMPLE;" 2>/dev/null)
_n=0
_sims=""
for _id in $_ids; do
  _q=$(_field "$_id" question)
  [ -n "$_q" ] || continue
  _r=$(_ref "$_id")
  _n=$((_n + 1))
  # Vizinhos sem limiar pratico (0.01) e sem o proprio registro.
  _v=$(_prec "$_q" --limit 6 --min-similarity 0.01 --max-bytes 100000 \
        | grep '^- ref=' | grep -v -F "ref=$_r " \
        | sed -n 's/.*similarity=\([0-9.]*\).*/\1/p' | head -n 5)
  _sims="$_sims
$_v"
done
printf '%s\n' "$_sims" | awk -v n="$_n" '
  NF {
    s = $1 + 0; t++
    if (s < 0.2) b[1]++
    else if (s < 0.3) b[2]++
    else if (s < 0.4) b[3]++
    else if (s < 0.5) b[4]++
    else if (s < 0.7) b[5]++
    else if (s < 0.9) b[6]++
    else b[7]++
  }
  END {
    split("[0,0.2) [0.2,0.3) [0.3,0.4) [0.4,0.5) [0.5,0.7) [0.7,0.9) [0.9,1.0]", name, " ")
    printf "blocos consultados: %d · pares vizinho observados: %d\n", n, t
    for (i = 1; i <= 7; i++) printf "  %-10s %d\n", name[i], b[i] + 0
    print "referencia (research Decision 2, 416 blocos, 2080 pares): 1906 / 57 / 11 / 19 / 20 / 27 / 40"
    print "obs.: o modo so devolve vizinhos com Jaccard > 0 dentro do pool FTS de 20; faixa [0,0.2) tende a subcontar."
  }'

if [ "$_fail" -ne 0 ]; then
  _bad "algum par-alvo nao foi recuperado — recalibrar RECALL_PREC_MIN_SIMILARITY (research Decision 2)"
  exit 1
fi
_say ""
_say "OK: pares-alvo conforme; compare o histograma acima com a referencia."
exit 0
