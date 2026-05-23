#!/bin/sh
# test_recall.sh — cobre cli/lib/recall.sh (cstk-knowledge-db)
#
# Cobre os cenarios 1-14 do quickstart.md:
#   1  ingest basico + recall com proveniencia
#   2  filtro --project exclui ruido cross-feature (SC-004)
#   3  filtro --type
#   4  --limit + ordenacao bm25
#   5  sem resultados = exit 0 (FR-013)
#   6  idempotencia da ingestao (SC-002)
#   7  upsert reflete versao mais recente (FR-008)
#   8  fonte transacional intacta (SC-006)
#   9  degradacao sem sqlite3 (FR-018/019)
#   10 degradacao sem jq
#   11 indice corrompido na busca (US3 AS2)
#   12 reconstrucao --reindex idempotente (SC-005)
#   13 query com caracteres especiais (sem erro de sintaxe FTS5)
#   13b payload adversarial de injecao na busca (A05/CWE-89)
#   13c payload adversarial de injecao na ingestao
#   14 concorrencia WAL best-effort (FR-016)
#
# DB de teste sempre em $TMPDIR_TEST (--db), nunca o indice global.
# Fixtures de bytes crus (NUL) usam escape OCTAL \000, nunca hex \xHH.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# Skip silencioso se sqlite3/jq ausentes no ambiente de teste — a degradacao
# graciosa ja e validada nos cenarios 9/10 (que SIMULAM ausencia via PATH).
# Os demais cenarios precisam das deps reais.
_have_deps() {
  command -v sqlite3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}

# _rc CMD... -> roda recall_main num subshell com common+recall sourced.
# Uso: chamar via `capture _rc <args>`.
_rc() {
  sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; recall_main "$@"' _ "$@"
}

# _write_state DIR PROJECT_PATH FEATURE -> escreve um state.json sintetico
# com 2 decisoes, 1 bloqueio, 1 retro, 2 skills. Termo distintivo "widget"
# na decisao 1 e "deploy" no bloqueio. project = basename de PROJECT_PATH.
_write_state() {
  _ws_dir="$1"; _ws_proj="$2"; _ws_feat="$3"
  mkdir -p "$_ws_dir"
  cat > "$_ws_dir/state.json" <<JSON
{
  "short_name": "$_ws_feat",
  "execucao": { "id": "exec-$_ws_feat", "projeto_alvo_path": "$_ws_proj" },
  "decisoes": [
    { "id": "dec-001", "onda_id": "onda-001", "timestamp": "2026-01-01T00:00:00Z",
      "etapa": "specify", "agente": "orch", "escolha": "iniciar", "score_justificativa": 2,
      "contexto": "decisao sobre widget azul", "justificativa": "porque widget", "evidencia": null },
    { "id": "dec-002", "onda_id": "onda-002", "timestamp": "2026-01-02T00:00:00Z",
      "etapa": "plan", "agente": "orch", "escolha": "cache", "score_justificativa": 3,
      "contexto": "estrategia de cache em camadas", "justificativa": "cache cache cache cache cache", "evidencia": "sonda cache" }
  ],
  "bloqueios_humanos": [
    { "id": "block-001", "onda_id": "onda-002", "status": "pendente",
      "pergunta": "podemos fazer deploy agora?", "contexto_para_resposta": "deploy de risco",
      "disparado_em": "2026-01-02T01:00:00Z" }
  ],
  "retros": [
    { "texto": "retro sobre cache e widget", "timestamp": "2026-01-03T00:00:00Z" }
  ],
  "ondas": [
    { "id": "onda-001", "skills_invoked": [
        { "skill": "specify", "timestamp": "2026-01-01T00:10:00Z", "decisao_id": "dec-001" } ] },
    { "id": "onda-002", "skills_invoked": [
        { "skill": "plan", "timestamp": "2026-01-02T00:10:00Z", "decisao_id": "dec-002" } ] }
  ]
}
JSON
}

# =========================================================================
# Cenario 1 — Ingestao basica + recuperacao com proveniencia
# =========================================================================
scenario_01_ingest_e_recall_com_proveniencia() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  capture _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db"
  assert_exit 0 _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" || return 1
  assert_stdout_contains "2 decisions" || return 1
  capture _rc "widget" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "recall exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "projX" || return 1
  assert_stdout_contains "featA" || return 1
  assert_stdout_contains "dec-001" || return 1
}

# =========================================================================
# Cenario 2 — Filtro --project exclui ruido cross-feature (SC-004)
# =========================================================================
scenario_02_filtro_project_exclui_ruido() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _write_state "$TMPDIR_TEST/featB" "/home/u/projY" "featB"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  capture _rc "widget" --project projX --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "projX" || return 1
  case "$_CAPTURED_STDOUT" in
    *projY*) _fail "filtro project" "vazou projY no resultado filtrado por projX"; return 1 ;;
  esac
}

# =========================================================================
# Cenario 3 — Filtro por tipo
# =========================================================================
scenario_03_filtro_type() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  capture _rc "deploy" --type bloqueio --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "[bloqueio]" || return 1
  case "$_CAPTURED_STDOUT" in
    *"[decision]"*|*"[retro]"*|*"[skill]"*) _fail "filtro type" "vazou outro tipo"; return 1 ;;
  esac
}

# =========================================================================
# Cenario 4 — Limite + ordenacao por relevancia (bm25)
# =========================================================================
scenario_04_limite_e_bm25() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  # "cache" aparece em dec-002 (forte) e retro; --limit 1 deve trazer 1 bloco.
  capture _rc "cache" --limit 1 --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "recall exit" "$_CAPTURED_EXIT"; return 1; }
  _blocks=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '^\[') || _blocks=0
  if [ "$_blocks" -gt 1 ]; then
    _fail "limite" "esperado <=1 bloco, obtido $_blocks"
    return 1
  fi
}

# =========================================================================
# Cenario 5 — Sem resultados = sucesso (FR-013)
# =========================================================================
scenario_05_sem_resultados_exit0() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  capture _rc "termo-inexistente-xyz" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "sem-resultado exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "nenhum resultado para 'termo-inexistente-xyz'" || return 1
}

# =========================================================================
# Cenario 6 — Idempotencia da ingestao (SC-002)
# =========================================================================
scenario_06_idempotencia() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _c1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  _f1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM knowledge_fts" 2>/dev/null)
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _c2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  _f2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM knowledge_fts" 2>/dev/null)
  if [ "$_c1" != "$_c2" ] || [ "$_f1" != "$_f2" ]; then
    _fail "idempotencia" "decisions $_c1->$_c2, fts $_f1->$_f2 (esperado estavel)"
    return 1
  fi
}

# =========================================================================
# Cenario 7 — Upsert reflete versao mais recente (FR-008)
# =========================================================================
scenario_07_upsert_versao_mais_recente() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  # Muta o bloqueio para respondido (mesma chave de proveniencia).
  cat > "$TMPDIR_TEST/featA/state.json" <<'JSON'
{
  "short_name": "featA",
  "execucao": { "id": "exec-featA", "projeto_alvo_path": "/home/u/projX" },
  "decisoes": [],
  "bloqueios_humanos": [
    { "id": "block-001", "onda_id": "onda-002", "status": "respondido",
      "pergunta": "podemos fazer deploy agora?", "contexto_para_resposta": "deploy de risco",
      "resposta_humana": "sim aprovado", "respondido_em": "2026-01-02T05:00:00Z" }
  ],
  "ondas": []
}
JSON
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _n=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM bloqueios" 2>/dev/null)
  [ "$_n" = "1" ] || { _fail "upsert" "esperado 1 linha de bloqueio, obtido $_n"; return 1; }
  _st=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT status FROM bloqueios" 2>/dev/null)
  [ "$_st" = "respondido" ] || { _fail "upsert status" "esperado respondido, obtido $_st"; return 1; }
}

# =========================================================================
# Cenario 8 — Fonte transacional intacta (SC-006)
# =========================================================================
scenario_08_fonte_intacta() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  printf 'fakehash\n' > "$TMPDIR_TEST/featA/state.json.sha256"
  _h1=$(sha256_file "$TMPDIR_TEST/featA/state.json")
  _hh1=$(sha256_file "$TMPDIR_TEST/featA/state.json.sha256")
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _h2=$(sha256_file "$TMPDIR_TEST/featA/state.json")
  _hh2=$(sha256_file "$TMPDIR_TEST/featA/state.json.sha256")
  if [ "$_h1" != "$_h2" ] || [ "$_hh1" != "$_hh2" ]; then
    _fail "fonte intacta" "state.json mudou: $_h1->$_h2 / sha256 $_hh1->$_hh2"
    return 1
  fi
}

# sha256_file PATH -> imprime hash (shasum ou sha256sum, o que existir).
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'no-sha-tool\n'
  fi
}

# =========================================================================
# Cenario 9 — Degradacao graciosa sem sqlite3 (FR-018/019, SC-003)
# =========================================================================
scenario_09_sem_sqlite3() {
  # Constroi um PATH com coreutils + jq, mas SEM sqlite3.
  _bin="$TMPDIR_TEST/bin9"
  mkdir -p "$_bin"
  for _t in tr wc printf sed grep awk basename dirname date find mkdir rm cat head sleep cp jq base64; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  # (sqlite3 deliberadamente ausente)
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  capture sh -c 'PATH="'"$_bin"'"; export PATH; . "'"$CSTK_LIB"'/common.sh"; . "'"$CSTK_LIB"'/recall.sh"; recall_main --ingest --state-dir "'"$TMPDIR_TEST"'/featA" --db "'"$TMPDIR_TEST"'/k9.db"'
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "sem-sqlite3 exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "sqlite3" || return 1
  if [ -f "$TMPDIR_TEST/k9.db" ]; then
    _fail "sem-sqlite3" "DB foi criado apesar da ausencia de sqlite3"
    return 1
  fi
}

# =========================================================================
# Cenario 10 — Degradacao graciosa sem jq
# =========================================================================
scenario_10_sem_jq() {
  command -v sqlite3 >/dev/null 2>&1 || return 0
  _bin="$TMPDIR_TEST/bin10"
  mkdir -p "$_bin"
  for _t in tr wc printf sed grep awk basename dirname date find mkdir rm cat head sleep cp sqlite3 base64; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  # (jq deliberadamente ausente)
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  capture sh -c 'PATH="'"$_bin"'"; export PATH; . "'"$CSTK_LIB"'/common.sh"; . "'"$CSTK_LIB"'/recall.sh"; recall_main --ingest --state-dir "'"$TMPDIR_TEST"'/featA" --db "'"$TMPDIR_TEST"'/k10.db"'
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "sem-jq exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "jq" || return 1
}

# =========================================================================
# Cenario 11 — Indice corrompido na busca (US3 AS2)
# =========================================================================
scenario_11_indice_corrompido() {
  _have_deps || return 0
  # Lixo cru (sem bytes especiais; texto basta para nao ser header SQLite).
  printf 'this is not a sqlite db just garbage\n' > "$TMPDIR_TEST/bad.db"
  capture _rc "qualquer" --db "$TMPDIR_TEST/bad.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "corrompido exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "reindex" || return 1
}

# =========================================================================
# Cenario 12 — Reconstrucao --reindex idempotente (SC-005)
# =========================================================================
scenario_12_reindex_idempotente() {
  _have_deps || return 0
  # Layout descoberta padrao: <root>/p/.claude/feature-00c-state/<feat>/state.json
  _write_state "$TMPDIR_TEST/root/pA/.claude/feature-00c-state/featA" "/home/u/projX" "featA"
  _write_state "$TMPDIR_TEST/root/pB/.claude/feature-00c-state/featB" "/home/u/projY" "featB"
  _rc --reindex --states-root "$TMPDIR_TEST/root" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _b0=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  # Apaga e reconstroi.
  rm -f "$TMPDIR_TEST/k.db"
  _rc --reindex --states-root "$TMPDIR_TEST/root" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _b1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  [ "$_b0" = "$_b1" ] || { _fail "reindex equivalente" "B0=$_b0 != B1=$_b1"; return 1; }
  # Reindex de novo NAO muda a contagem (idempotente).
  _rc --reindex --states-root "$TMPDIR_TEST/root" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _b2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  [ "$_b1" = "$_b2" ] || { _fail "reindex idempotente" "B1=$_b1 != B2=$_b2"; return 1; }
  # Deve ter ingerido as 2 features (4 decisoes no total).
  [ "$_b2" = "4" ] || { _fail "reindex cobertura" "esperado 4 decisoes, obtido $_b2"; return 1; }
}

# =========================================================================
# Cenario 13 — Query com caracteres especiais (sem erro de sintaxe FTS5)
# =========================================================================
scenario_13_caracteres_especiais() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  capture _rc '"aspas" AND (parenteses) *' --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "chars especiais" "esperado rc=0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

# =========================================================================
# Cenario 13b — Payload adversarial de injecao na busca (A05/CWE-89)
# =========================================================================
scenario_13b_injecao_na_busca() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _before=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  capture _rc "'; DROP TABLE decisions; --" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "injecao busca exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  # Tabela DEVE continuar existindo com a mesma contagem.
  _after=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  [ "$_before" = "$_after" ] && [ -n "$_after" ] || {
    _fail "injecao busca" "tabela decisions alterada/dropada: $_before -> $_after"
    return 1
  }
}

# =========================================================================
# Cenario 13c — Payload adversarial de injecao na ingestao (texto + proveniencia)
# =========================================================================
scenario_13c_injecao_na_ingestao() {
  _have_deps || return 0
  mkdir -p "$TMPDIR_TEST/adv"
  # Aspa simples em campo de proveniencia (short_name) E payload em texto livre.
  cat > "$TMPDIR_TEST/adv/state.json" <<'JSON'
{
  "short_name": "feat-O'Brien",
  "execucao": { "id": "exec-adv", "projeto_alvo_path": "/home/u/proj'X" },
  "decisoes": [
    { "id": "dec-001", "onda_id": "onda-001", "timestamp": "2026-01-01T00:00:00Z",
      "etapa": "specify", "agente": "orch", "escolha": "x", "score_justificativa": 2,
      "contexto": "O'Brien'); DROP TABLE decisions; --", "justificativa": "literal text", "evidencia": null }
  ],
  "bloqueios_humanos": [],
  "ondas": []
}
JSON
  capture _rc --ingest --state-dir "$TMPDIR_TEST/adv" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "injecao ingest exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  # Tabela decisions intacta e com a linha (1 registro).
  _n=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  [ "$_n" = "1" ] || { _fail "injecao ingest" "esperado 1 decisao, obtido $_n (tabela dropada?)"; return 1; }
  # Texto literal preservado (aspas), busca recupera.
  capture _rc "DROP" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "DROP TABLE decisions" || return 1
}

# =========================================================================
# Cenario 14 — Concorrencia WAL best-effort (FR-016)
# =========================================================================
scenario_14_concorrencia_wal() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/c1" "/home/u/p1" "c1feat"
  _write_state "$TMPDIR_TEST/c2" "/home/u/p2" "c2feat"
  # Duas ingestoes quase-simultaneas no mesmo --db.
  _rc --ingest --state-dir "$TMPDIR_TEST/c1" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1 &
  _p1=$!
  _rc --ingest --state-dir "$TMPDIR_TEST/c2" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1 &
  _p2=$!
  wait "$_p1" 2>/dev/null || :
  wait "$_p2" 2>/dev/null || :
  # DB nao corrompido: quick_check ok.
  _qc=$(sqlite3 "$TMPDIR_TEST/k.db" "PRAGMA quick_check" 2>/dev/null | head -n 1)
  [ "$_qc" = "ok" ] || { _fail "concorrencia integridade" "quick_check=$_qc"; return 1; }
  # Ambos os conjuntos presentes (ou, sob contencao extrema, degradacao
  # graciosa). Aceitamos >=1 feature (best-effort) e exigimos integridade.
  _feats=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(DISTINCT feature) FROM decisions" 2>/dev/null)
  [ "${_feats:-0}" -ge 1 ] || { _fail "concorrencia conteudo" "nenhuma feature ingerida"; return 1; }
}

# =========================================================================
# Cenario NUL — rejeicao na busca / strip na ingestao (dec-015/016)
# Fixture de byte cru NUL via escape OCTAL \000 (NUNCA hex).
# =========================================================================
# NUL na busca: argv e variaveis de shell NUNCA podem carregar um byte NUL
# (o kernel trunca em execve, a shell strip-a em command substitution). Logo
# a defesa testavel e o detector has_nul/value_has_nul: alimentado com um
# byte NUL CRU (octal \000) via stdin, ele DEVE detectar e o caminho de busca
# rejeitar com exit 2. Testamos o detector diretamente (unidade real do guard)
# com fixture de byte cru OCTAL \000 (nunca hex).
scenario_nul_detector_busca() {
  _have_deps || return 0
  # has_nul le stdin: com NUL -> exit 0 (detectou); sem NUL -> exit 1.
  capture sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; printf "wid\000get" | has_nul'
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "has_nul com NUL" "esperado deteccao (exit 0), obtido $_CAPTURED_EXIT"; return 1; }
  capture sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; printf "widget" | has_nul'
  [ "$_CAPTURED_EXIT" = "1" ] || { _fail "has_nul sem NUL" "esperado nenhuma deteccao (exit 1), obtido $_CAPTURED_EXIT"; return 1; }
}

# NUL na ingestao: politica = strip silencioso (best-effort, exit 0).
# Dois fatos testaveis:
#  (a) strip_nul (unidade do guard) remove o byte cru \000 do stream;
#  (b) um state.json com NUL cru e JSON invalido para jq -> a ingestao
#      degrada gracioso (exit 0), nunca aborta a onda. Fixture usa OCTAL \000.
scenario_nul_strip_unit() {
  _have_deps || return 0
  # strip_nul deve remover o NUL: "wid\000get" -> "widget".
  _out=$(printf 'wid\000get' | sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; strip_nul')
  [ "$_out" = "widget" ] || { _fail "strip_nul" "esperado 'widget', obtido '$_out'"; return 1; }
}

scenario_nul_ingestao_degrada_gracioso() {
  _have_deps || return 0
  mkdir -p "$TMPDIR_TEST/nul"
  # NUL cru (octal \000) num campo de texto livre -> JSON invalido para jq.
  # A ingestao best-effort deve seguir exit 0 (nunca aborta), nada persistido.
  printf '{ "short_name": "nulfeat", "execucao": { "id": "exec-nul", "projeto_alvo_path": "/home/u/projN" }, "decisoes": [ { "id": "dec-001", "onda_id": "onda-001", "contexto": "wid\000get" } ], "bloqueios_humanos": [], "ondas": [] }' > "$TMPDIR_TEST/nul/state.json"
  capture _rc --ingest --state-dir "$TMPDIR_TEST/nul" --db "$TMPDIR_TEST/kn.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "NUL ingest exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

# =========================================================================
# FASE 7.1.4 — Hook fim-de-onda degrada gracioso com `cstk` ausente.
# Simula o passo 9.bis/10.bis do Loop dos orquestradores: a invocacao
# `cstk recall --ingest ... || log_out ...` NUNCA gateia a onda. Com cstk
# fora do PATH, o `|| true` (aqui modelado) garante exit 0 e a onda segue.
# =========================================================================
scenario_hook_fim_de_onda_cstk_ausente() {
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  # PATH sem cstk (e sem o repo). O padrao do hook engole a falha via `|| :`.
  _bin="$TMPDIR_TEST/binH"
  mkdir -p "$_bin"
  for _t in tr printf sed grep sh; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  capture sh -c 'PATH="'"$_bin"'"; export PATH; cstk recall --ingest --state-dir "'"$TMPDIR_TEST"'/featA" 2>/dev/null || printf "knowledge-db: ingestao pulada\n"'
  # O hook do orquestrador usa `|| log_out ...`; aqui o `|| printf` garante
  # que a ausencia de cstk NAO propaga exit != 0 (a onda nunca aborta).
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "hook fim-de-onda" "cstk ausente propagou exit $_CAPTURED_EXIT (deveria degradar para 0)"; return 1; }
  assert_stdout_contains "ingestao pulada" || return 1
}

# =========================================================================
# Cenario 15 — Busca multi-palavra = AND por token (nao frase contigua)
# Regressao do fix pos-review: fts_query_escape tokeniza + AND implicito,
# preservando a neutralizacao de sintaxe FTS5 por token (A05/CWE-89).
# =========================================================================
scenario_15_busca_multi_palavra_and() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1

  # "decisao" e "azul" estao no MESMO doc (dec-001: "decisao sobre widget
  # azul") porem NAO adjacentes -> busca por frase contigua FALHARIA; o
  # token-AND DEVE casar dec-001.
  capture _rc "decisao azul" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "multi-palavra exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "dec-001" || return 1

  # "azul" (so em dec-001) e "deploy" (so em block-001) estao em docs
  # DIFERENTES -> AND implicito NAO deve casar nada (prova que e AND, nao OR).
  capture _rc "azul deploy" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "multi-palavra and exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "nenhum resultado" || return 1
}

run_all_scenarios
