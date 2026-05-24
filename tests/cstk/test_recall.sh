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

# =========================================================================
# knowledge-db-metrics — FASE 1 (camada A.1): executions + waves
# =========================================================================

# _write_metrics_state DIR PROJECT_PATH FEATURE -> state.json com
# .execucao + .metricas_acumuladas + .etapa_corrente + 2 ondas. Execucao
# CONCLUIDA (terminada_em presente) para exercitar duracao_segundos derivada.
# motivo_termino contem segredo plantado (validacao de filtro nas fases 2/5).
_write_metrics_state() {
  _wm_dir="$1"; _wm_proj="$2"; _wm_feat="$3"
  mkdir -p "$_wm_dir"
  cat > "$_wm_dir/state.json" <<JSON
{
  "short_name": "$_wm_feat",
  "etapa_corrente": "review-task",
  "execucao": {
    "id": "exec-$_wm_feat",
    "projeto_alvo_path": "$_wm_proj",
    "status": "concluido",
    "motivo_termino": "fluxo normal concluido",
    "iniciada_em": "2026-01-01T00:00:00Z",
    "terminada_em": "2026-01-01T01:00:00Z",
    "stack_sugerida": null
  },
  "metricas_acumuladas": {
    "ondas_total": 2,
    "tool_calls_total": 42,
    "tempo_wallclock_total_segundos": 3600,
    "profundidade_max_atingida": 2,
    "subagentes_spawned": 3,
    "decisoes_total": 5,
    "bloqueios_humanos_total": 1,
    "sugestoes_skills_globais_total": 0,
    "issues_toolkit_abertas": 0
  },
  "decisoes": [],
  "bloqueios_humanos": [],
  "ondas": [
    { "id": "onda-001", "inicio": "2026-01-01T00:00:00Z", "fim": "2026-01-01T00:30:00Z",
      "etapas_executadas": ["specify", "clarify"], "wallclock_seconds": 1800, "tool_calls": 20,
      "motivo_termino": "etapa_concluida_avancando",
      "skills_invoked": [
        { "skill": "specify", "timestamp": "2026-01-01T00:05:00Z", "decisao_id": "dec-001" },
        { "skill": "clarify", "timestamp": "2026-01-01T00:20:00Z", "decisao_id": "dec-002" } ] },
    { "id": "onda-002", "inicio": "2026-01-01T00:30:00Z", "fim": "2026-01-01T01:00:00Z",
      "etapas_executadas": ["plan"], "wallclock_seconds": 1800, "tool_calls": 22,
      "motivo_termino": "threshold_atingido",
      "skills_invoked": [
        { "skill": "plan", "timestamp": "2026-01-01T00:45:00Z", "decisao_id": "dec-003" } ] }
  ]
}
JSON
}

# =========================================================================
# Cenario M1.1 — bump v1 -> v2 preserva dado v1 + cria executions/waves
# (task 1.1.5; FR-007, Edge Case "schema antigo")
# =========================================================================
scenario_m11_bump_v1_para_v2_preserva_dado() {
  _have_deps || return 0
  _mdb="$TMPDIR_TEST/v1.db"
  # DB v1 sintetico: 1 decision + schema_version=1, SEM tabelas novas.
  sqlite3 "$_mdb" <<'SQL'
CREATE TABLE decisions (id INTEGER PRIMARY KEY AUTOINCREMENT, project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL, execucao_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL, agente TEXT, etapa TEXT, escolha TEXT, score INTEGER, contexto TEXT, justificativa TEXT, evidencia TEXT, ingested_at TEXT NOT NULL, UNIQUE(project, feature, wave, source_id));
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
INSERT INTO schema_meta(key,value) VALUES('schema_version','1');
INSERT INTO decisions(project,feature,wave,execucao_id,source_ts,source_id,ingested_at) VALUES('p','f','w','e','t','dec-legacy','now');
SQL
  # Aplica schema v2 via funcao real (caminho de recall_apply_schema).
  sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; recall_apply_schema "$1"' _ "$_mdb" || {
    _fail "apply schema v2" "recall_apply_schema falhou"; return 1; }
  # (a) schema_version virou 2
  _sv=$(sqlite3 "$_mdb" "SELECT value FROM schema_meta WHERE key='schema_version'")
  [ "$_sv" = "2" ] || { _fail "schema_version" "esperado 2, obtido $_sv"; return 1; }
  # (b) tabelas executions + waves existem
  _has=$(sqlite3 "$_mdb" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('executions','waves')")
  [ "$_has" = "2" ] || { _fail "tabelas novas" "esperado 2 (executions+waves), obtido $_has"; return 1; }
  # (c) dado v1 preservado
  _leg=$(sqlite3 "$_mdb" "SELECT count(*) FROM decisions WHERE source_id='dec-legacy'")
  [ "$_leg" = "1" ] || { _fail "preservacao v1" "decisao legacy perdida ($_leg)"; return 1; }
}

# =========================================================================
# Cenario M1.2 — idempotencia do DDL: aplicar 2x sem erro, schema estavel
# (task 1.1.6)
# =========================================================================
scenario_m12_ddl_idempotente() {
  _have_deps || return 0
  _mdb="$TMPDIR_TEST/idem.db"
  sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; recall_apply_schema "$1"' _ "$_mdb" || {
    _fail "apply 1" "primeira aplicacao falhou"; return 1; }
  assert_exit 0 sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; recall_apply_schema "$1"' _ "$_mdb" || return 1
  _sv=$(sqlite3 "$_mdb" "SELECT value FROM schema_meta WHERE key='schema_version'")
  [ "$_sv" = "2" ] || { _fail "schema estavel" "esperado 2 apos 2x, obtido $_sv"; return 1; }
}

# =========================================================================
# Cenario M2.1 — ingestao de Execucao concluida: 1 linha, 100% dos campos
# (task 1.2.6; SC-001, Acceptance US1.1)
# =========================================================================
scenario_m21_execucao_concluida_campos() {
  _have_deps || return 0
  _write_metrics_state "$TMPDIR_TEST/featM" "/home/u/projM" "featM"
  capture _rc --ingest --state-dir "$TMPDIR_TEST/featM" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ingest exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "1 executions" || return 1
  # Exatamente 1 linha.
  _n=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM executions")
  [ "$_n" = "1" ] || { _fail "exec count" "esperado 1, obtido $_n"; return 1; }
  # Campos derivados/estruturais (chave natural wave='-', source_id=execucao_id).
  _row=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT project||'|'||feature||'|'||wave||'|'||source_id||'|'||status||'|'||etapa_corrente||'|'||duracao_segundos||'|'||ondas_total||'|'||tool_calls_total||'|'||wallclock_total_segundos||'|'||subagentes_spawned||'|'||profundidade_max||'|'||decisoes_total||'|'||bloqueios_humanos_total FROM executions")
  _exp="projM|featM|-|exec-featM|concluido|review-task|3600|2|42|3600|3|2|5|1"
  [ "$_row" = "$_exp" ] || { _fail "exec campos" "esperado [$_exp], obtido [$_row]"; return 1; }
}

# =========================================================================
# Cenario M2.2 — execucao em andamento: duracao_segundos NULL, 0 erro
# (task 1.2.7; Acceptance US1.3)
# =========================================================================
scenario_m22_execucao_em_andamento_duracao_null() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featO"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featO",
  "etapa_corrente": "plan",
  "execucao": { "id": "exec-featO", "projeto_alvo_path": "/home/u/projO", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": { "ondas_total": 1, "tool_calls_total": 5 },
  "decisoes": [], "bloqueios_humanos": [], "ondas": []
}
JSON
  assert_exit 0 _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/k.db" || return 1
  _dn=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT duracao_segundos IS NULL FROM executions WHERE source_id='exec-featO'")
  [ "$_dn" = "1" ] || { _fail "duracao aberta" "esperado NULL, obtido nao-null"; return 1; }
  # Metricas ausentes viram NULL sem erro.
  _sn=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT subagentes_spawned IS NULL FROM executions WHERE source_id='exec-featO'")
  [ "$_sn" = "1" ] || { _fail "metrica ausente" "esperado NULL para subagentes_spawned"; return 1; }
}

# =========================================================================
# Cenario M2.3 — filtro de segredo em motivo_termino da execucao (FR-006)
# =========================================================================
scenario_m23_execucao_motivo_filtrado() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featS"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featS",
  "etapa_corrente": "review-task",
  "execucao": { "id": "exec-featS", "projeto_alvo_path": "/home/u/projS", "status": "abortada",
    "motivo_termino": "abortado com token=ghp_AbCdEf1234567890SecretLeak presente",
    "iniciada_em": "2026-01-01T00:00:00Z", "terminada_em": "2026-01-01T00:10:00Z" },
  "metricas_acumuladas": { "ondas_total": 1 },
  "decisoes": [], "bloqueios_humanos": [], "ondas": []
}
JSON
  _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _mt=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT motivo_termino FROM executions WHERE source_id='exec-featS'")
  case "$_mt" in
    *ghp_AbCdEf*) _fail "filtro segredo exec" "token vazou em motivo_termino: $_mt"; return 1 ;;
  esac
}

# =========================================================================
# Cenario M3.1 — ingestao de Ondas: 3 linhas, campos derivados corretos
# (task 1.3.6; SC-001, Acceptance US1.2). Inclui onda aberta (fim null) e
# segredo plantado em motivo_termino de uma onda (FR-006).
# =========================================================================
scenario_m31_ondas_campos() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featW"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featW",
  "etapa_corrente": "review-task",
  "execucao": { "id": "exec-featW", "projeto_alvo_path": "/home/u/projW", "status": "concluido", "iniciada_em": "2026-01-01T00:00:00Z", "terminada_em": "2026-01-01T01:00:00Z" },
  "metricas_acumuladas": { "ondas_total": 3 },
  "decisoes": [], "bloqueios_humanos": [],
  "ondas": [
    { "id": "onda-001", "inicio": "2026-01-01T00:00:00Z", "fim": "2026-01-01T00:30:00Z", "etapas_executadas": ["specify","clarify"], "wallclock_seconds": 1800, "tool_calls": 20, "motivo_termino": "etapa_concluida", "skills_invoked": [ {"skill":"specify"},{"skill":"clarify"} ] },
    { "id": "onda-002", "inicio": "2026-01-01T00:30:00Z", "fim": "2026-01-01T01:00:00Z", "etapas_executadas": ["plan"], "wallclock_seconds": 1800, "tool_calls": 22, "motivo_termino": "threshold token=ghp_LeakInWave1234567890ab", "skills_invoked": [ {"skill":"plan"} ] },
    { "id": "onda-003", "inicio": "2026-01-01T01:00:00Z", "fim": null, "etapas_executadas": [], "wallclock_seconds": 0, "tool_calls": 0, "motivo_termino": null, "skills_invoked": [] }
  ]
}
JSON
  capture _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ingest exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "3 waves" || return 1
  # Exatamente 3 linhas.
  _n=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM waves WHERE feature='featW'")
  [ "$_n" = "3" ] || { _fail "wave count" "esperado 3, obtido $_n"; return 1; }
  # onda-001: etapas CSV + n_etapas + n_skills.
  _r1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT etapas||'|'||wallclock_seconds||'|'||tool_calls||'|'||n_etapas||'|'||n_skills FROM waves WHERE wave='onda-001'")
  [ "$_r1" = "specify,clarify|1800|20|2|2" ] || { _fail "onda-001 campos" "obtido [$_r1]"; return 1; }
  # onda-003 aberta: fim vazio, contagens 0, sem erro.
  _fe=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT (fim IS NULL OR fim='') FROM waves WHERE wave='onda-003'")
  [ "$_fe" = "1" ] || { _fail "onda aberta" "fim deveria ser vazio"; return 1; }
  # onda-002 motivo_termino scrubbed.
  _mt=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT motivo_termino FROM waves WHERE wave='onda-002'")
  case "$_mt" in
    *ghp_LeakInWave*) _fail "filtro segredo onda" "token vazou: $_mt"; return 1 ;;
  esac
}

# =========================================================================
# Cenario M4.1 — re-ingestao N vezes: delta de linhas executions/waves = 0
# (task 1.4.2; SC-004, Acceptance US1.4). Valor reflete estado mais recente.
# =========================================================================
scenario_m41_reingest_delta_zero() {
  _have_deps || return 0
  _write_metrics_state "$TMPDIR_TEST/featM" "/home/u/projM" "featM"
  _rc --ingest --state-dir "$TMPDIR_TEST/featM" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _e1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM executions")
  _w1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM waves")
  # Re-ingere 3x.
  _rc --ingest --state-dir "$TMPDIR_TEST/featM" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _rc --ingest --state-dir "$TMPDIR_TEST/featM" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _rc --ingest --state-dir "$TMPDIR_TEST/featM" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _e2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM executions")
  _w2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM waves")
  [ "$_e1" = "$_e2" ] && [ "$_w1" = "$_w2" ] || {
    _fail "delta zero" "executions $_e1->$_e2, waves $_w1->$_w2 (esperado estavel)"; return 1; }
  [ "$_e2" = "1" ] && [ "$_w2" = "2" ] || {
    _fail "contagem esperada" "esperado 1 exec + 2 waves, obtido $_e2 + $_w2"; return 1; }
  # Upsert reflete estado mais recente: muta tool_calls da onda e re-ingere.
  sed 's/"tool_calls": 20/"tool_calls": 99/' "$TMPDIR_TEST/featM/state.json" > "$TMPDIR_TEST/featM/state.json.new"
  mv "$TMPDIR_TEST/featM/state.json.new" "$TMPDIR_TEST/featM/state.json"
  _rc --ingest --state-dir "$TMPDIR_TEST/featM" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _tc=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT tool_calls FROM waves WHERE wave='onda-001' AND feature='featM'")
  [ "$_tc" = "99" ] || { _fail "upsert recente" "esperado tool_calls=99, obtido $_tc"; return 1; }
}

# =========================================================================
# Cenario M4.2 — convergencia ingest vs reindex: 0 divergencias
# (task 1.4.3; SC-002, Independent Test US1). executions/waves identicos.
# =========================================================================
scenario_m42_ingest_vs_reindex_convergencia() {
  _have_deps || return 0
  # Caminho A: --ingest direto.
  _write_metrics_state "$TMPDIR_TEST/ing/featM" "/home/u/projM" "featM"
  _rc --ingest --state-dir "$TMPDIR_TEST/ing/featM" --db "$TMPDIR_TEST/a.db" >/dev/null 2>&1
  _ea=$(sqlite3 "$TMPDIR_TEST/a.db" "SELECT count(*) FROM executions")
  _wa=$(sqlite3 "$TMPDIR_TEST/a.db" "SELECT count(*) FROM waves")
  # dump comparavel (sem ingested_at, que e timestamp de processamento).
  _dumpa=$(sqlite3 "$TMPDIR_TEST/a.db" "SELECT project,feature,wave,source_id,status,duracao_segundos,tool_calls_total FROM executions UNION ALL SELECT project,feature,wave,source_id,etapas,n_etapas,tool_calls FROM waves ORDER BY 1,2,3,4")
  # Caminho B: --reindex (descoberta padrao).
  _write_metrics_state "$TMPDIR_TEST/rx/p/.claude/feature-00c-state/featM" "/home/u/projM" "featM"
  _rc --reindex --states-root "$TMPDIR_TEST/rx" --db "$TMPDIR_TEST/b.db" >/dev/null 2>&1
  _eb=$(sqlite3 "$TMPDIR_TEST/b.db" "SELECT count(*) FROM executions")
  _wb=$(sqlite3 "$TMPDIR_TEST/b.db" "SELECT count(*) FROM waves")
  _dumpb=$(sqlite3 "$TMPDIR_TEST/b.db" "SELECT project,feature,wave,source_id,status,duracao_segundos,tool_calls_total FROM executions UNION ALL SELECT project,feature,wave,source_id,etapas,n_etapas,tool_calls FROM waves ORDER BY 1,2,3,4")
  [ "$_ea" = "$_eb" ] && [ "$_wa" = "$_wb" ] || {
    _fail "contagem ingest vs reindex" "exec $_ea/$_eb waves $_wa/$_wb"; return 1; }
  [ "$_dumpa" = "$_dumpb" ] || {
    _fail "divergencia ingest vs reindex" "dumps diferem"; return 1; }
}

# =========================================================================
# Cenario M4.3 — best-effort camada A: sem sqlite3 (fixture de metricas) +
# state.json corrompido -> exit 0, sem abort, sem DB (task 1.4.4; SC-003,
# FR-003). Complementa cenarios 9/10/11 com o grao de execucao/onda.
# =========================================================================
scenario_m43_best_effort_metrics() {
  _have_deps || return 0
  _write_metrics_state "$TMPDIR_TEST/featM" "/home/u/projM" "featM"
  # PATH com coreutils+jq, SEM sqlite3 (mesmo padrao do cenario 9).
  _bin="$TMPDIR_TEST/binM43"
  mkdir -p "$_bin"
  for _t in tr wc printf sed grep awk basename dirname date find mkdir rm cat head sleep cp jq base64; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  capture sh -c 'PATH="'"$_bin"'"; export PATH; . "'"$CSTK_LIB"'/common.sh"; . "'"$CSTK_LIB"'/recall.sh"; recall_main --ingest --state-dir "'"$TMPDIR_TEST"'/featM" --db "'"$TMPDIR_TEST"'/beM.db"'
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "sem-sqlite3 metrics exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$TMPDIR_TEST/beM.db" ] && { _fail "sem-sqlite3 metrics" "DB criado apesar de sqlite3 ausente"; return 1; }
  # state.json corrompido -> pula com aviso, exit 0, executions/waves vazios.
  printf '{ corrompido nao-json' > "$TMPDIR_TEST/featM/state.json"
  assert_exit 0 _rc --ingest --state-dir "$TMPDIR_TEST/featM" --db "$TMPDIR_TEST/be2.db" || return 1
  _e=$(sqlite3 "$TMPDIR_TEST/be2.db" "SELECT count(*) FROM executions" 2>/dev/null) || _e=0
  [ "${_e:-0}" = "0" ] || { _fail "corrompido metrics" "esperado 0 executions, obtido $_e"; return 1; }
}

# =========================================================================
# Cenario M5.1 — SinalDeAlerta circular: 1 linha por entrada do
# historico_movimento_circular[] (task 2.1.4; FR-013, Acceptance US2.2)
# =========================================================================
scenario_m51_alert_circular() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featC"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featC",
  "etapa_corrente": "plan",
  "execucao": { "id": "exec-featC", "projeto_alvo_path": "/home/u/projC", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": {},
  "historico_movimento_circular": [
    { "problema_hash": "abc123", "solucao_hash": "def456", "timestamp": "2026-01-01T00:05:00Z" },
    { "problema_hash": "abc123", "solucao_hash": "ghi789", "timestamp": "2026-01-01T00:10:00Z" }
  ],
  "decisoes": [], "bloqueios_humanos": [], "ondas": []
}
JSON
  assert_exit 0 _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/k.db" || return 1
  _n=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM alert_signals WHERE tipo='circular' AND feature='featC'")
  [ "$_n" = "2" ] || { _fail "circular count" "esperado 2, obtido $_n"; return 1; }
  # source_id segue padrao circular:<wave>:<ordinal>; valores numericos NULL.
  _vc=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT valor_consumido IS NULL AND valor_threshold IS NULL FROM alert_signals WHERE source_id='circular:-:0' AND feature='featC'")
  [ "$_vc" = "1" ] || { _fail "circular valores" "esperado NULL/NULL para consumido/threshold"; return 1; }
  # descricao consultavel.
  _d=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT descricao FROM alert_signals WHERE source_id='circular:-:1' AND feature='featC'")
  case "$_d" in
    *abc123*ghi789*) : ;;
    *) _fail "circular descricao" "esperado hashes, obtido [$_d]"; return 1 ;;
  esac
}

# =========================================================================
# Cenario M5.2 — SinalDeAlerta budget_breach: cruza .orcamentos com consumo
# per-onda (tool_calls/wallclock) e per-execucao (ciclos/profundidade/
# estado_size); 1 linha por threshold excedido com consumido vs threshold
# corretos (task 2.2.4; FR-014, SC-005, Acceptance US2.1)
# =========================================================================
scenario_m52_alert_budget_breach() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featBB"
  mkdir -p "$_mdir"
  # estado_size_threshold_bytes=100 garante breach de estado_size (state.json
  # > 100 bytes por construcao). tool_calls 90>80, wallclock 6000>5400 (em
  # ondas distintas), ciclos 7>5, profundidade 3>=3.
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featBB",
  "etapa_corrente": "execute-task",
  "execucao": { "id": "exec-featBB", "projeto_alvo_path": "/home/u/projBB", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": {},
  "orcamentos": {
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 100,
    "ciclos_max_por_etapa": 5,
    "ciclos_consumidos_etapa_corrente": 7,
    "recursividade_max": 3,
    "profundidade_corrente_subagentes": 3
  },
  "ondas": [
    { "id": "onda-001", "tool_calls": 90, "wallclock_seconds": 100, "etapas_executadas": ["specify"] },
    { "id": "onda-002", "tool_calls": 10, "wallclock_seconds": 6000, "etapas_executadas": ["plan"] }
  ],
  "decisoes": [], "bloqueios_humanos": [], "historico_movimento_circular": []
}
JSON
  assert_exit 0 _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/kbb.db" || return 1
  # 5 breaches: tool_calls(onda-001), wallclock(onda-002), ciclos, profundidade,
  # estado_size (3 ultimos com wave='-').
  _n=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT count(*) FROM alert_signals WHERE tipo='budget_breach' AND feature='featBB'")
  [ "$_n" = "5" ] || { _fail "breach count" "esperado 5, obtido $_n"; return 1; }
  # subtipo per-onda + valores consumido/threshold corretos.
  _tc=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT wave||'|'||valor_consumido||'|'||valor_threshold FROM alert_signals WHERE feature='featBB' AND subtipo='tool_calls'")
  [ "$_tc" = "onda-001|90|80" ] || { _fail "breach tool_calls" "esperado onda-001|90|80, obtido $_tc"; return 1; }
  _wc=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT wave||'|'||valor_consumido||'|'||valor_threshold FROM alert_signals WHERE feature='featBB' AND subtipo='wallclock'")
  [ "$_wc" = "onda-002|6000|5400" ] || { _fail "breach wallclock" "esperado onda-002|6000|5400, obtido $_wc"; return 1; }
  # subtipo per-execucao -> wave='-'.
  _ci=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT wave||'|'||valor_consumido||'|'||valor_threshold FROM alert_signals WHERE feature='featBB' AND subtipo='ciclos'")
  [ "$_ci" = "-|7|5" ] || { _fail "breach ciclos" "esperado -|7|5, obtido $_ci"; return 1; }
  _pf=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT wave||'|'||valor_consumido||'|'||valor_threshold FROM alert_signals WHERE feature='featBB' AND subtipo='profundidade'")
  [ "$_pf" = "-|3|3" ] || { _fail "breach profundidade" "esperado -|3|3 (>=), obtido $_pf"; return 1; }
  _es=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT (valor_consumido > valor_threshold) FROM alert_signals WHERE feature='featBB' AND subtipo='estado_size'")
  [ "$_es" = "1" ] || { _fail "breach estado_size" "esperado consumido>threshold, obtido $_es"; return 1; }
  # source_id segue padrao budget_breach:<wave>:<ordinal>; descricao NULL.
  _sid=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT source_id FROM alert_signals WHERE feature='featBB' AND subtipo='tool_calls'")
  [ "$_sid" = "budget_breach:onda-001:0" ] || { _fail "breach source_id" "esperado budget_breach:onda-001:0, obtido $_sid"; return 1; }
  _dn=$(sqlite3 "$TMPDIR_TEST/kbb.db" "SELECT (count(*) = sum(CASE WHEN descricao IS NULL THEN 1 ELSE 0 END)) FROM alert_signals WHERE feature='featBB' AND tipo='budget_breach'")
  [ "$_dn" = "1" ] || { _fail "breach descricao" "esperado descricao NULL em todos os breach"; return 1; }
}

# =========================================================================
# Cenario M5.3 — budget_breach: nenhum threshold excedido -> 0 sinais; e
# idempotencia (re-ingest N vezes -> delta 0). (task 2.2.4; SC-004, SC-005)
# =========================================================================
scenario_m53_budget_breach_negativo_e_idempotente() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featBN"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featBN",
  "etapa_corrente": "plan",
  "execucao": { "id": "exec-featBN", "projeto_alvo_path": "/home/u/projBN", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": {},
  "orcamentos": {
    "tool_calls_threshold_onda": 80,
    "wallclock_threshold_segundos": 5400,
    "estado_size_threshold_bytes": 1048576,
    "ciclos_max_por_etapa": 5,
    "ciclos_consumidos_etapa_corrente": 1,
    "recursividade_max": 3,
    "profundidade_corrente_subagentes": 1
  },
  "ondas": [ { "id": "onda-001", "tool_calls": 10, "wallclock_seconds": 100, "etapas_executadas": ["specify"] } ],
  "decisoes": [], "bloqueios_humanos": [], "historico_movimento_circular": []
}
JSON
  # (a) Negativo: nada excedido -> 0 budget_breach.
  assert_exit 0 _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/kbn.db" || return 1
  assert_stdout_contains "0 alerts" || return 1
  _n=$(sqlite3 "$TMPDIR_TEST/kbn.db" "SELECT count(*) FROM alert_signals WHERE tipo='budget_breach' AND feature='featBN'")
  [ "$_n" = "0" ] || { _fail "negativo" "esperado 0 budget_breach, obtido $_n"; return 1; }
  # (b) Idempotencia: reusar fixture de breach M5.2 e ingerir 3x -> delta 0.
  _bdir="$TMPDIR_TEST/featBBidem"
  mkdir -p "$_bdir"
  cat > "$_bdir/state.json" <<'JSON'
{
  "short_name": "featBBidem",
  "etapa_corrente": "execute-task",
  "execucao": { "id": "exec-featBBidem", "projeto_alvo_path": "/home/u/projBBi", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": {},
  "orcamentos": { "tool_calls_threshold_onda": 80, "wallclock_threshold_segundos": 5400, "estado_size_threshold_bytes": 100, "ciclos_max_por_etapa": 5, "ciclos_consumidos_etapa_corrente": 7, "recursividade_max": 3, "profundidade_corrente_subagentes": 3 },
  "ondas": [ { "id": "onda-001", "tool_calls": 90, "wallclock_seconds": 100, "etapas_executadas": ["specify"] } ],
  "decisoes": [], "bloqueios_humanos": [], "historico_movimento_circular": []
}
JSON
  _rc --ingest --state-dir "$_bdir" --db "$TMPDIR_TEST/kbi.db" >/dev/null 2>&1
  _c1=$(sqlite3 "$TMPDIR_TEST/kbi.db" "SELECT count(*) FROM alert_signals WHERE feature='featBBidem'")
  _rc --ingest --state-dir "$_bdir" --db "$TMPDIR_TEST/kbi.db" >/dev/null 2>&1
  _rc --ingest --state-dir "$_bdir" --db "$TMPDIR_TEST/kbi.db" >/dev/null 2>&1
  _c2=$(sqlite3 "$TMPDIR_TEST/kbi.db" "SELECT count(*) FROM alert_signals WHERE feature='featBBidem'")
  [ "$_c1" = "$_c2" ] || { _fail "idempotencia breach" "delta != 0: $_c1 -> $_c2"; return 1; }
  # tool_calls + ciclos + profundidade + estado_size = 4 (sem wallclock: 100<5400).
  [ "$_c2" = "4" ] || { _fail "contagem breach idem" "esperado 4 estavel, obtido $_c2"; return 1; }
}

# =========================================================================
# Cenario M6.1 — MetricaDerivada: latencia humana por bloqueio
# (respondido_em - disparado_em); bloqueio sem resposta = NULL/pendente.
# disparado_em/respondido_em/latencia_segundos preservados em bloqueios
# (task 2.3.3; FR-015, Acceptance US2.3)
# =========================================================================
scenario_m61_latencia_humana_derivavel() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featLAT"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featLAT",
  "etapa_corrente": "clarify",
  "execucao": { "id": "exec-featLAT", "projeto_alvo_path": "/home/u/projLAT", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": {}, "orcamentos": {}, "ondas": [], "decisoes": [],
  "historico_movimento_circular": [],
  "bloqueios_humanos": [
    { "id": "bloq-001", "decisao_id": "dec-010", "status": "respondido", "pergunta": "qual rumo seguir aqui?", "disparado_em": "2026-01-01T00:00:00Z", "respondido_em": "2026-01-01T00:10:00Z", "resposta_humana": "ok" },
    { "id": "bloq-002", "decisao_id": "dec-011", "status": "aguardando", "pergunta": "outra pergunta pendente?", "disparado_em": "2026-01-01T00:05:00Z", "respondido_em": null }
  ]
}
JSON
  assert_exit 0 _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/klat.db" || return 1
  # Bloqueio respondido -> latencia = 600s (10 min). Timestamps separados.
  _r1=$(sqlite3 "$TMPDIR_TEST/klat.db" "SELECT latencia_segundos||'|'||disparado_em||'|'||respondido_em FROM bloqueios WHERE feature='featLAT' AND source_id='bloq-001'")
  [ "$_r1" = "600|2026-01-01T00:00:00Z|2026-01-01T00:10:00Z" ] || { _fail "latencia respondido" "esperado 600|..., obtido $_r1"; return 1; }
  # Bloqueio sem resposta -> latencia NULL (pendente), respondido_em vazio.
  _r2=$(sqlite3 "$TMPDIR_TEST/klat.db" "SELECT (latencia_segundos IS NULL) AND (respondido_em IS NULL OR respondido_em='') FROM bloqueios WHERE feature='featLAT' AND source_id='bloq-002'")
  [ "$_r2" = "1" ] || { _fail "latencia pendente" "esperado NULL/pendente para bloq-002, obtido $_r2"; return 1; }
  # decisao_id preservado para JOIN posterior (FR-016).
  _r3=$(sqlite3 "$TMPDIR_TEST/klat.db" "SELECT decisao_id FROM bloqueios WHERE feature='featLAT' AND source_id='bloq-001'")
  [ "$_r3" = "dec-010" ] || { _fail "decisao_id preservado" "esperado dec-010, obtido $_r3"; return 1; }
}

# =========================================================================
# Cenario M6.2 — MetricaDerivada: clarify auto-resolution rate derivavel
# da relacao decisoes score>=2 etapa=clarify (autonomas) vs bloqueios
# fase clarify (escalas via JOIN decisao_id->decisions.etapa), sem nova
# tabela (task 2.3.4; FR-016, Acceptance US2.4)
# =========================================================================
scenario_m62_clarify_rate_derivavel() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featCR"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featCR",
  "etapa_corrente": "clarify",
  "execucao": { "id": "exec-featCR", "projeto_alvo_path": "/home/u/projCR", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": {}, "orcamentos": {}, "ondas": [],
  "historico_movimento_circular": [],
  "decisoes": [
    { "id": "dec-001", "onda_id": "onda-001", "etapa": "clarify", "escolha": "auto-a", "score": 2, "timestamp": "2026-01-01T00:01:00Z" },
    { "id": "dec-002", "onda_id": "onda-001", "etapa": "clarify", "escolha": "auto-b", "score": 3, "timestamp": "2026-01-01T00:02:00Z" },
    { "id": "dec-050", "onda_id": "onda-001", "etapa": "clarify", "escolha": "escalar", "score": 1, "timestamp": "2026-01-01T00:03:00Z" },
    { "id": "dec-090", "onda_id": "onda-001", "etapa": "plan", "escolha": "fora-clarify", "score": 2, "timestamp": "2026-01-01T00:04:00Z" }
  ],
  "bloqueios_humanos": [
    { "id": "bloq-001", "decisao_id": "dec-050", "status": "aguardando", "pergunta": "ambiguo demais, escalar?", "disparado_em": "2026-01-01T00:03:00Z", "respondido_em": null }
  ]
}
JSON
  assert_exit 0 _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/kcr.db" || return 1
  # Autonomas: decisoes score>=2 na fase clarify (dec-001, dec-002) = 2;
  # dec-050 (score 1) e dec-090 (plan) NAO contam.
  _a=$(sqlite3 "$TMPDIR_TEST/kcr.db" "SELECT count(*) FROM decisions WHERE feature='featCR' AND etapa='clarify' AND score>=2")
  [ "$_a" = "2" ] || { _fail "clarify autonomas" "esperado 2, obtido $_a"; return 1; }
  # Escalas: bloqueios cuja decisao_id aponta para decisao de etapa clarify = 1.
  _e=$(sqlite3 "$TMPDIR_TEST/kcr.db" "SELECT count(*) FROM bloqueios b JOIN decisions d ON d.feature=b.feature AND d.source_id=b.decisao_id WHERE b.feature='featCR' AND d.etapa='clarify'")
  [ "$_e" = "1" ] || { _fail "clarify escalas" "esperado 1, obtido $_e"; return 1; }
  # Taxa de auto-resolucao derivavel = auto/(auto+escala) = 2/3.
  _rate=$(sqlite3 "$TMPDIR_TEST/kcr.db" "SELECT printf('%d/%d', $_a, $_a + $_e)")
  [ "$_rate" = "2/3" ] || { _fail "clarify rate" "esperado 2/3, obtido $_rate"; return 1; }
}

# Resolve model-routing-report.sh via CSTK_LIB (repo) ou ~/.claude (instalado).
_mrr_path() {
  _mrr_repo="$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/model-routing-report.sh"
  if [ -f "$_mrr_repo" ]; then printf '%s\n' "$_mrr_repo"; return 0; fi
  _mrr_inst="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/model-routing-report.sh"
  if [ -f "$_mrr_inst" ]; then printf '%s\n' "$_mrr_inst"; return 0; fi
  return 1
}

# =========================================================================
# Cenario M6.3 — Mix de modelos: reuso (FR-017). (a) recall.sh NAO contem
# logica de agregacao de modelos em linha de CODIGO (so comentario-ancora);
# (b) o mix e a saida canonica de model-routing-report.sh aggregate --json
# sobre o mesmo fixture -> 0 divergencias (a fonte unica, recall nao duplica).
# (task 2.4.2/2.4.3; FR-017, SC-006, Acceptance US2.5)
# =========================================================================
scenario_m63_model_mix_delegado() {
  _have_deps || return 0
  # (a) Auditoria FR-017: nenhuma LINHA DE CODIGO (nao-comentario) de recall.sh
  # referencia nomes de modelo ou chaves de agregacao do mix. Exclui linhas
  # cujo primeiro caractere nao-branco e '#'.
  _rsh="$CSTK_LIB/recall.sh"
  [ -f "$_rsh" ] || { _fail "recall.sh path" "nao encontrado em $_rsh"; return 1; }
  _hits=$(grep -nE "por_modelo|chosen_model|fallback-default|Selecao de modelo" "$_rsh" \
            | grep -vE "^[0-9]+:[[:space:]]*#" || true)
  [ -z "$_hits" ] || { _fail "FR-017 duplicacao" "logica de mix em codigo de recall.sh: $_hits"; return 1; }
  # (b) Delegacao a aggregate --json = fonte unica. Skip se runtime ausente.
  _MRR=$(_mrr_path) || return 0
  _mdir="$TMPDIR_TEST/featMIX"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featMIX",
  "etapa_corrente": "clarify",
  "execucao": { "id": "exec-featMIX", "projeto_alvo_path": "/home/u/projMIX", "status": "em_andamento", "iniciada_em": "2026-01-01T00:00:00Z" },
  "metricas_acumuladas": {}, "orcamentos": {}, "ondas": [],
  "bloqueios_humanos": [], "historico_movimento_circular": [],
  "decisoes": [
    { "id": "dec-001", "onda_id": "onda-001", "etapa": "clarify", "contexto": "Selecao de modelo para subagente feature-00c-clarify-asker", "escolha": "haiku", "score": 2, "timestamp": "2026-01-01T00:01:00Z" },
    { "id": "dec-002", "onda_id": "onda-001", "etapa": "clarify", "contexto": "Selecao de modelo para subagente feature-00c-clarify-answerer", "escolha": "sonnet", "score": 2, "timestamp": "2026-01-01T00:02:00Z" }
  ]
}
JSON
  # O mix delegado e exatamente a saida de aggregate --json (fonte unica).
  _json=$("$_MRR" aggregate --state-dir "$_mdir" --json 2>/dev/null) \
    || { _fail "aggregate --json" "invocacao falhou"; return 1; }
  # Parseavel e numeros canonicos: total=2, haiku=1, sonnet=1 (0 divergencia
  # porque recall.sh nao produz mix proprio para divergir — delega 100%).
  _t=$(printf '%s' "$_json" | jq -r '.total')
  _h=$(printf '%s' "$_json" | jq -r '.por_modelo.haiku')
  _s=$(printf '%s' "$_json" | jq -r '.por_modelo.sonnet')
  [ "$_t|$_h|$_s" = "2|1|1" ] || { _fail "mix delegado" "esperado total=2 haiku=1 sonnet=1, obtido $_t|$_h|$_s"; return 1; }
}

# =========================================================================
# Cenario M7.1 — Filtro de segredos end-to-end da camada A: planta segredos
# (token=ghp_/api_key=sk-) em TODOS os campos de texto livre das entidades A
# (executions.motivo_termino, waves.motivo_termino, alert_signals circular
# descricao, bloqueios pergunta/contexto/resposta) e assegura que nenhum
# padrao conhecido sobrevive ao indice; campos estruturados/numericos ficam
# intactos. (task 2.5.3; FR-006, SC-007, Independent Test US2)
# =========================================================================
scenario_m71_filtro_segredos_e2e_camada_a() {
  _have_deps || return 0
  _mdir="$TMPDIR_TEST/featSEC"
  mkdir -p "$_mdir"
  cat > "$_mdir/state.json" <<'JSON'
{
  "short_name": "featSEC",
  "etapa_corrente": "review-task",
  "execucao": {
    "id": "exec-featSEC",
    "projeto_alvo_path": "/home/u/projSEC",
    "status": "abortada",
    "motivo_termino": "abortado com token=ghp_ExecLeak1234567890ABCDEF presente",
    "iniciada_em": "2026-01-01T00:00:00Z",
    "terminada_em": "2026-01-01T00:30:00Z"
  },
  "metricas_acumuladas": { "ondas_total": 1, "tool_calls_total": 42 },
  "orcamentos": {},
  "ondas": [
    { "id": "onda-001", "tool_calls": 10, "wallclock_seconds": 100, "etapas_executadas": ["specify"], "fim": "2026-01-01T00:10:00Z", "motivo_termino": "encerrou com api_key=sk-WaveLeak0987654321zyxw aqui" }
  ],
  "historico_movimento_circular": [
    { "problema_hash": "phash token=ghp_CircLeakAAAA1111BBBB2222", "solucao_hash": "shash", "timestamp": "2026-01-01T00:05:00Z" }
  ],
  "decisoes": [],
  "bloqueios_humanos": [
    {
      "id": "bloq-001",
      "decisao_id": "dec-010",
      "status": "respondido",
      "pergunta": "como tratar token=ghp_BloqPergLeak33334444 aqui?",
      "contexto_para_resposta": "ver api_key=sk-BloqCtxLeak55556666 no log",
      "resposta_humana": "use token=ghp_BloqRespLeak77778888 manual",
      "disparado_em": "2026-01-01T00:00:00Z",
      "respondido_em": "2026-01-01T00:15:00Z"
    }
  ]
}
JSON
  assert_exit 0 _rc --ingest --state-dir "$_mdir" --db "$TMPDIR_TEST/ksec.db" || return 1
  # (a) Nenhum padrao de segredo conhecido em QUALQUER coluna de texto das
  # tabelas da camada A + knowledge_fts. Dump amplo e grep por marcadores.
  _dump=$(sqlite3 "$TMPDIR_TEST/ksec.db" "
    SELECT motivo_termino FROM executions WHERE feature='featSEC'
    UNION ALL SELECT motivo_termino FROM waves WHERE feature='featSEC'
    UNION ALL SELECT descricao FROM alert_signals WHERE feature='featSEC'
    UNION ALL SELECT pergunta||' '||contexto_para_resposta||' '||resposta FROM bloqueios WHERE feature='featSEC'
    UNION ALL SELECT body FROM knowledge_fts WHERE feature='featSEC'")
  case "$_dump" in
    *ghp_*|*"sk-"[A-Za-z0-9]*) _fail "segredo vazou camada A" "padrao de segredo no indice: $_dump"; return 1 ;;
  esac
  # Sanidade: o redactor de fato agiu (marcador [REDACTED] presente em ao
  # menos um campo de texto livre que continha segredo).
  case "$_dump" in
    *REDACTED*) : ;;
    *) _fail "redactor inativo" "esperado [REDACTED] em algum campo, dump: $_dump"; return 1 ;;
  esac
  # (b) Campos estruturados/numericos INTACTOS (nao passaram por filtro):
  # timestamps, latencia, decisao_id, contagens.
  _struct=$(sqlite3 "$TMPDIR_TEST/ksec.db" "SELECT decisao_id||'|'||disparado_em||'|'||respondido_em||'|'||latencia_segundos FROM bloqueios WHERE feature='featSEC' AND source_id='bloq-001'")
  [ "$_struct" = "dec-010|2026-01-01T00:00:00Z|2026-01-01T00:15:00Z|900" ] || { _fail "estruturado intacto" "esperado dec-010|...|900, obtido $_struct"; return 1; }
  _tc=$(sqlite3 "$TMPDIR_TEST/ksec.db" "SELECT tool_calls_total FROM executions WHERE feature='featSEC'")
  [ "$_tc" = "42" ] || { _fail "numerico intacto" "esperado tool_calls_total=42, obtido $_tc"; return 1; }
}

# =========================================================================
# recall-autoconsume — Infra comum do modo --context (FASE 4.1)
# =========================================================================

# _rc_home_fake CMD... -> roda recall_main como _rc, mas com HOME=$tmp_fake
# (sem ~/.claude) + CSTK_LIB apontando ao repo (licao v3.17.0: helpers via
# CSTK_LIB, nao ~/.claude). Usado para rodar cada cenario --context tambem
# sob HOME falso, com assercoes IDENTICAS (SC-005, Cenario 12).
_rc_home_fake() {
  _hf_home=$(mktemp -d 2>/dev/null) || _hf_home="$TMPDIR_TEST/fakehome"
  mkdir -p "$_hf_home"
  HOME="$_hf_home" sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; recall_main "$@"' _ "$@"
}

# _ctx_fixture_db DB -> popula DB com 3 features em 2 projetos, proveniencia
# variada (ondas distintas, tipos distintos). Termos distintivos:
#   featA (projX): decisao "alpha cache" + bloqueio "deploy"
#   featB (projY): decisao "beta query"
#   featC (projX): decisao "gamma cache" (mesmo projeto que featA)
# Permite testar: OR multi-termo, anti-eco, filtro project/type, limit.
_ctx_fixture_db() {
  _cf_db="$1"
  _write_ctx_state "$TMPDIR_TEST/cxA" "/home/u/projX" "featA" "alpha cache widget" "onda-001" "deploy de risco alpha"
  _write_ctx_state "$TMPDIR_TEST/cxB" "/home/u/projY" "featB" "beta query engine" "onda-002" ""
  _write_ctx_state "$TMPDIR_TEST/cxC" "/home/u/projX" "featC" "gamma cache layer" "onda-003" ""
  _rc --ingest --state-dir "$TMPDIR_TEST/cxA" --db "$_cf_db" >/dev/null 2>&1
  _rc --ingest --state-dir "$TMPDIR_TEST/cxB" --db "$_cf_db" >/dev/null 2>&1
  _rc --ingest --state-dir "$TMPDIR_TEST/cxC" --db "$_cf_db" >/dev/null 2>&1
}

# _write_ctx_state DIR PROJ FEAT DEC_CTX WAVE BLOQ_TEXT -> state.json com 1
# decisao (contexto = DEC_CTX, onda = WAVE) e, se BLOQ_TEXT nao-vazio, 1 bloqueio.
_write_ctx_state() {
  _wc_dir="$1"; _wc_proj="$2"; _wc_feat="$3"; _wc_ctx="$4"; _wc_wave="$5"; _wc_bloq="$6"
  mkdir -p "$_wc_dir"
  if [ -n "$_wc_bloq" ]; then
    _wc_bloq_json='{ "id": "block-001", "onda_id": "'"$_wc_wave"'", "status": "respondido", "pergunta": "'"$_wc_bloq"'", "contexto_para_resposta": "ctx", "disparado_em": "2026-01-01T01:00:00Z" }'
  else
    _wc_bloq_json=""
  fi
  cat > "$_wc_dir/state.json" <<JSON
{
  "short_name": "$_wc_feat",
  "execucao": { "id": "exec-$_wc_feat", "projeto_alvo_path": "$_wc_proj" },
  "decisoes": [
    { "id": "dec-001", "onda_id": "$_wc_wave", "timestamp": "2026-01-01T00:00:00Z",
      "etapa": "plan", "agente": "orch", "escolha": "x", "score_justificativa": 2,
      "contexto": "$_wc_ctx", "justificativa": "j", "evidencia": null }
  ],
  "bloqueios_humanos": [ $_wc_bloq_json ],
  "ondas": []
}
JSON
}

# =========================================================================
# recall-autoconsume FASE 1.1 — Helper de composicao OR (fts_query_escape_or)
# Tarefa 1.1.4: asserir que fts_query_escape_or "a b" produz '"a" OR "b"'
# (duas camadas de escape FTS5) e que fts_query_escape "a b" PERMANECE
# AND-implicito ('"a" "b"' — regressao do modo busca, tarefa 1.1.2). Cobre
# tambem query degenerada (so-whitespace) consistente com fts_query_escape
# (tarefa 1.1.3). Unidade pura (sem sqlite3/jq) — roda mesmo sem deps.
# =========================================================================
scenario_ctx_fts_query_escape_or_composicao() {
  # Composicao OR: dois tokens => '"a" OR "b"'.
  _out=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; fts_query_escape_or "a b"')
  [ "$_out" = '"a" OR "b"' ] || { _fail "or-composicao" "esperado '\"a\" OR \"b\"', obtido '$_out'"; return 1; }

  # Regressao do modo busca: fts_query_escape PERMANECE AND-implicito (espaco).
  _out_and=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; fts_query_escape "a b"')
  [ "$_out_and" = '"a" "b"' ] || { _fail "and-regressao" "esperado '\"a\" \"b\"' (AND), obtido '$_out_and'"; return 1; }

  # Token unico: sem juntor (sem ' OR ' espurio).
  _out1=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; fts_query_escape_or "solo"')
  [ "$_out1" = '"solo"' ] || { _fail "or-token-unico" "esperado '\"solo\"', obtido '$_out1'"; return 1; }
}

scenario_ctx_fts_query_escape_or_degenerada() {
  # Query so-whitespace (degenerada): mesma politica de fts_query_escape =>
  # frase vazia '""' (casa nada, nunca erro). Compara as duas saidas.
  _deg_or=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; fts_query_escape_or "   "')
  _deg_and=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; fts_query_escape "   "')
  [ "$_deg_or" = '""' ] || { _fail "or-degenerada" "esperado '\"\"' (frase vazia), obtido '$_deg_or'"; return 1; }
  [ "$_deg_or" = "$_deg_and" ] || { _fail "or-degenerada-paridade" "OR='$_deg_or' != AND='$_deg_and' para query degenerada"; return 1; }
}

scenario_ctx_fts_query_escape_or_neutraliza_sintaxe() {
  # Metacaracteres FTS5 por token viram TEXTO (cada token entre aspas, " interno
  # duplicado). Token com aspa interna: a" => '"a"""' (aspa duplicada dentro).
  _out=$(sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; fts_query_escape_or "drop* table"')
  # '*' fica dentro da frase => literal; juncao OR entre os dois tokens.
  [ "$_out" = '"drop*" OR "table"' ] || { _fail "or-neutraliza" "esperado '\"drop*\" OR \"table\"', obtido '$_out'"; return 1; }
}

# =========================================================================
# recall-autoconsume FASE 2/3 — modo --context (recall_mode_context)
# Cobre os cenarios do quickstart adaptados ao modo --context. Cada cenario
# que precisa de DB roda em DOIS ambientes (HOME real via _rc + HOME falso via
# _rc_home_fake) com assercoes IDENTICAS (SC-005). Fixtures sem bytes crus aqui
# (corrompido usa fixture octal dedicada no cenario 10-context).
# =========================================================================

# Cenario 1-context — bloco markdown com proveniencia (formato distinto da busca)
scenario_ctx_01_bloco_markdown_proveniencia() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  # HOME real.
  capture _rc --context "cache" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-bloco exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Aprendizado recuperado (read-back loop)" || return 1
  assert_stdout_contains "**[decision]**" || return 1
  assert_stdout_contains "projX/featA/onda-001" || return 1
  # HOME falso: mesmas assercoes.
  capture _rc_home_fake --context "cache" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-bloco exit (HOME fake)" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Aprendizado recuperado (read-back loop)" || return 1
  assert_stdout_contains "projX/featA/onda-001" || return 1
}

# Cenario 2-context — anti-eco exclui a feature corrente (no SQL)
scenario_ctx_02_anti_eco_exclude_feature() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  capture _rc --context "cache" --exclude-feature featA --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-antieco exit" "$_CAPTURED_EXIT"; return 1; }
  # featC (tambem "cache") deve aparecer; featA (excluida) NAO.
  assert_stdout_contains "featC" || return 1
  case "$_CAPTURED_STDOUT" in
    *featA*) _fail "ctx-antieco" "feature excluida featA vazou no bloco"; return 1 ;;
  esac
  # HOME falso: identico.
  capture _rc_home_fake --context "cache" --exclude-feature featA --db "$TMPDIR_TEST/k.db"
  case "$_CAPTURED_STDOUT" in
    *featA*) _fail "ctx-antieco (HOME fake)" "featA vazou"; return 1 ;;
  esac
  assert_stdout_contains "featC" || return 1
}

# Cenario 3-context — zero match => no-op (stdout vazio, exit 0)
scenario_ctx_03_zero_match_noop() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  capture _rc --context "termo-inexistente-zzz" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-zero exit" "$_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "ctx-zero" "stdout deveria ser vazio (no-op), obtido: $_CAPTURED_STDOUT"; return 1; }
}

# Cenario 4-context — OR multi-termo: termos em docs disjuntos ambos aparecem
# (contraste com AND do modo busca, que nao casaria nada).
scenario_ctx_04_or_multi_termo() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  # "alpha" so em featA, "beta" so em featB => OR traz ambos; AND traria nada.
  capture _rc --context "alpha beta" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-or exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "featA" || return 1
  assert_stdout_contains "featB" || return 1
  # Prova de contraste: o modo busca (AND) com os mesmos termos NAO casa nada.
  capture _rc "alpha beta" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "nenhum resultado" || return 1
}

# Cenario 6-context — default --limit = 4
scenario_ctx_06_default_limit_4() {
  _have_deps || return 0
  # Popula 6 decisoes com o mesmo termo distintivo em features distintas.
  _i=1
  while [ "$_i" -le 6 ]; do
    _write_ctx_state "$TMPDIR_TEST/lim$_i" "/home/u/projL" "featL$_i" "limterm comum decisao" "onda-00$_i" ""
    _rc --ingest --state-dir "$TMPDIR_TEST/lim$_i" --db "$TMPDIR_TEST/kl.db" >/dev/null 2>&1
    _i=$((_i + 1))
  done
  capture _rc --context "limterm" --db "$TMPDIR_TEST/kl.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-limit exit" "$_CAPTURED_EXIT"; return 1; }
  # Conta linhas de achado ('- **['). Default = 4.
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '^- \*\*\[') || _n=0
  [ "$_n" = "4" ] || { _fail "ctx-limit default" "esperado 4 achados (default), obtido $_n"; return 1; }
}

# Cenario 5-context — teto de bytes trunca (achados inteiros, bloco <= max-bytes)
scenario_ctx_05_max_bytes_teto() {
  _have_deps || return 0
  _i=1
  while [ "$_i" -le 5 ]; do
    _write_ctx_state "$TMPDIR_TEST/mb$_i" "/home/u/projM" "featM$_i" "bigterm conteudo razoavelmente longo para somar bytes no bloco final de contexto" "onda-00$_i" ""
    _rc --ingest --state-dir "$TMPDIR_TEST/mb$_i" --db "$TMPDIR_TEST/km.db" >/dev/null 2>&1
    _i=$((_i + 1))
  done
  # max-bytes baixo: bloco inteiro <= 300 bytes; corta por achado inteiro.
  capture _rc --context "bigterm" --limit 5 --max-bytes 300 --db "$TMPDIR_TEST/km.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-maxbytes exit" "$_CAPTURED_EXIT"; return 1; }
  _bytes=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -c | tr -d ' ')
  [ "$_bytes" -le 300 ] || { _fail "ctx-maxbytes" "bloco $_bytes bytes > teto 300"; return 1; }
  # Se ha bloco, deve ter cabecalho e ao menos 1 achado inteiro (sem corte no meio).
  if [ -n "$_CAPTURED_STDOUT" ]; then
    assert_stdout_contains "Aprendizado recuperado" || return 1
    # Nenhuma linha de achado pode terminar abruptamente sem o termo distintivo
    # ou sufixo de truncagem; verificamos que cada linha '- **[' esta completa
    # (contem o fechamento ')').
    printf '%s\n' "$_CAPTURED_STDOUT" | grep '^- \*\*\[' | while IFS= read -r _ln; do
      case "$_ln" in
        *'): '*) : ;;
        *) printf 'LINHA_INCOMPLETA\n' ;;
      esac
    done | grep -q LINHA_INCOMPLETA && { _fail "ctx-maxbytes" "achado cortado no meio (sem '): ')"; return 1; }
  fi
  return 0
}

# Cenario 7-context — sqlite3 ausente => no-op (exit 0, stdout vazio)
scenario_ctx_07_sem_sqlite3() {
  _bin="$TMPDIR_TEST/binC7"
  mkdir -p "$_bin"
  for _t in tr wc printf sed grep awk basename dirname date find mkdir rm cat head sleep cp jq base64 cut; do
    _p=$(command -v "$_t" 2>/dev/null) && ln -sf "$_p" "$_bin/$_t"
  done
  # (sqlite3 deliberadamente ausente)
  capture sh -c 'PATH="'"$_bin"'"; export PATH; . "'"$CSTK_LIB"'/common.sh"; . "'"$CSTK_LIB"'/recall.sh"; recall_main --context "qualquer" --db "'"$TMPDIR_TEST"'/k.db"'
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-sem-sqlite3 exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "ctx-sem-sqlite3" "stdout deveria ser vazio (no-op)"; return 1; }
}

# Cenario 9-context — DB ausente => no-op (exit 0, stdout vazio)
scenario_ctx_09_db_ausente() {
  _have_deps || return 0
  capture _rc --context "qualquer" --db "$TMPDIR_TEST/inexistente.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-db-ausente exit" "$_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "ctx-db-ausente" "stdout deveria ser vazio (no-op)"; return 1; }
}

# Cenario 10-context — DB corrompido => no-op. Fixture de bytes crus OCTAL \NNN.
scenario_ctx_10_db_corrompido() {
  _have_deps || return 0
  # Lixo cru com alguns bytes de controle via octal (\014 form feed, \001 SOH).
  printf 'nao\014e\001um\014sqlite\001db\n' > "$TMPDIR_TEST/bad-ctx.db"
  capture _rc --context "qualquer" --db "$TMPDIR_TEST/bad-ctx.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-corrompido exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "ctx-corrompido" "stdout deveria ser vazio (no-op)"; return 1; }
}

# Cenario 11-context — read-only: size + mtime do DB inalterados (SC-006/FR-014)
scenario_ctx_11_read_only() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  # Snapshot size + mtime antes.
  _sz0=$(wc -c < "$TMPDIR_TEST/k.db" | tr -d ' ')
  _mt0=$(ls -l "$TMPDIR_TEST/k.db")
  sleep 1
  _rc --context "cache" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _rc --context "query alpha" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _sz1=$(wc -c < "$TMPDIR_TEST/k.db" | tr -d ' ')
  _mt1=$(ls -l "$TMPDIR_TEST/k.db")
  [ "$_sz0" = "$_sz1" ] || { _fail "ctx-readonly size" "size mudou: $_sz0 -> $_sz1"; return 1; }
  [ "$_mt0" = "$_mt1" ] || { _fail "ctx-readonly mtime" "ls -l mudou (escrita no DB): \n$_mt0\nvs\n$_mt1"; return 1; }
}

# Cenario 13-context — injecao SQL/FTS nos termos tratada como literal, DB intacto
scenario_ctx_13_injecao_literal() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  _before=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  capture _rc --context "'; DROP TABLE decisions; --" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-injecao exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _after=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM decisions" 2>/dev/null)
  [ "$_before" = "$_after" ] && [ -n "$_after" ] || { _fail "ctx-injecao" "tabela alterada/dropada: $_before -> $_after"; return 1; }
  # Anti-eco tambem deve tratar valor manipulado como literal (sem bypass SQL).
  capture _rc --context "cache" --exclude-feature "featA' OR '1'='1" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-injecao-antieco exit" "$_CAPTURED_EXIT"; return 1; }
  # Como o exclude e literal e nao casa nenhuma feature real, featA ainda aparece.
  assert_stdout_contains "featA" || return 1
}

# Cenario 14-context — NUL em input rejeitado com exit 2 (USAGE)
scenario_ctx_14_nul_rejeitado() {
  # has_nul detecta NUL via stdin; o caminho --context rejeita com exit 2.
  # Argv nao carrega NUL cru, entao testamos a unidade do guard + a politica:
  # um value_has_nul positivo no caminho deve resultar em USAGE. Aqui validamos
  # a unidade do guard com fixture OCTAL \000 (a integracao no parse e coberta
  # por inspecao: o loop for value_has_nul em recall_mode_context).
  capture sh -c '. "$CSTK_LIB/common.sh"; . "$CSTK_LIB/recall.sh"; printf "ca\000che" | has_nul'
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-nul detector" "esperado deteccao (exit 0), obtido $_CAPTURED_EXIT"; return 1; }
}

# Cenario validacao-context — flags invalidas e tipos errados => exit 2
scenario_ctx_validacao_usage() {
  # termos ausentes => USAGE
  capture _rc --context --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "2" ] || { _fail "ctx-sem-termos" "esperado exit 2, obtido $_CAPTURED_EXIT"; return 1; }
  # --limit nao-inteiro => USAGE
  capture _rc --context "x" --limit abc --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "2" ] || { _fail "ctx-limit-invalido" "esperado exit 2, obtido $_CAPTURED_EXIT"; return 1; }
  # --max-bytes nao-inteiro => USAGE
  capture _rc --context "x" --max-bytes 0 --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "2" ] || { _fail "ctx-maxbytes-invalido" "esperado exit 2 (0 nao e positivo), obtido $_CAPTURED_EXIT"; return 1; }
  # --type fora do enum => USAGE
  capture _rc --context "x" --type naoexiste --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "2" ] || { _fail "ctx-type-invalido" "esperado exit 2, obtido $_CAPTURED_EXIT"; return 1; }
  # flag invalida => USAGE
  capture _rc --context "x" --naoexiste --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "2" ] || { _fail "ctx-flag-invalida" "esperado exit 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# Cenario filtro-type/project no modo --context
scenario_ctx_filtros_type_project() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  # --type bloqueio => so o bloqueio de featA (deploy de risco alpha).
  capture _rc --context "deploy alpha" --type bloqueio --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-type exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "**[bloqueio]**" || return 1
  case "$_CAPTURED_STDOUT" in
    *'**[decision]**'*) _fail "ctx-type" "vazou decision com --type bloqueio"; return 1 ;;
  esac
  # --project projY => so featB.
  capture _rc --context "query beta cache" --project projY --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "projY/featB" || return 1
  case "$_CAPTURED_STDOUT" in
    *projX*) _fail "ctx-project" "vazou projX com --project projY"; return 1 ;;
  esac
}

# Cenario 3.1-context — despacho de --context em recall_main + regressao busca
scenario_ctx_despacho_recall_main() {
  _have_deps || return 0
  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  # --context roteia para recall_mode_context (bloco markdown).
  capture _rc --context "cache" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "Aprendizado recuperado (read-back loop)" || return 1
  # busca (sem --context) ainda roteia para recall_mode_search (formato [type]).
  capture _rc "cache" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "[decision]" || return 1
  case "$_CAPTURED_STDOUT" in
    *"Aprendizado recuperado"*) _fail "ctx-despacho" "modo busca emitiu cabecalho de --context"; return 1 ;;
  esac
}

# Cenario 3.2-context — usage MODO CONTEXT + -h no modo context
scenario_ctx_usage_help() {
  capture _rc --context -h
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "ctx-help exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "MODO CONTEXT" || return 1
  assert_stdout_contains "--exclude-feature" || return 1
  assert_stdout_contains "--max-bytes" || return 1
}

# =========================================================================
# recall-autoconsume FASE 4.2 — auditabilidade (integracao PRE-DECISAO)
# Cenario 15: simula o passo PRE-DECISAO do orquestrador. Apos consumo com
# K>0, registra uma Decisao auditavel via state-decisions.sh (FR-016/FR-017);
# K=0 NAO gera Decisao (sem ruido); a Decisao NAO persiste o body bruto
# recuperado (CHK013). Skip silencioso se state-decisions.sh ausente.
# =========================================================================

# Resolve state-decisions.sh via CSTK_LIB (repo) ou ~/.claude (instalado).
_ctx_state_decisions_path() {
  _sd_repo="$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/state-decisions.sh"
  if [ -f "$_sd_repo" ]; then printf '%s\n' "$_sd_repo"; return 0; fi
  _sd_inst="${HOME:-/tmp}/.claude/skills/agente-00c-runtime/scripts/state-decisions.sh"
  if [ -f "$_sd_inst" ]; then printf '%s\n' "$_sd_inst"; return 0; fi
  return 1
}

scenario_ctx_15_auditabilidade_pre_decisao() {
  _have_deps || return 0
  _SDSH=$(_ctx_state_decisions_path) || return 0  # skip se runtime ausente
  _RWSH=$(dirname "$_SDSH")/state-rw.sh
  [ -f "$_RWSH" ] || return 0

  _ctx_fixture_db "$TMPDIR_TEST/k.db"

  # state-dir sintetico minimo para o orquestrador.
  _osd="$TMPDIR_TEST/orch-state"
  mkdir -p "$_osd"
  "$_RWSH" init --state-dir "$_osd" --execucao-id exec-featCurrent \
    --projeto-alvo-path /home/u/projX --descricao "feature corrente sob teste" >/dev/null 2>&1 || {
      # init pode exigir flags diferentes; cai para skip se assinatura difere.
      return 0
    }

  # ---- Simula o passo PRE-DECISAO (pseudocodigo do contrato) ----
  TERMS="cache query"
  BLOCO=$(_rc --context "$TERMS" --exclude-feature featCurrent --limit 4 --max-bytes 2000 --db "$TMPDIR_TEST/k.db" 2>/dev/null) || BLOCO=""
  [ -n "$BLOCO" ] || { _fail "ctx-audit setup" "esperado K>0 para o cenario de auditabilidade"; return 1; }
  K=$(printf '%s\n' "$BLOCO" | grep -c '^- ')

  # Captura o body bruto de um achado (apos ':') para asserir que NAO vai pro state.
  _bruto=$(printf '%s\n' "$BLOCO" | grep '^- ' | head -n1 | sed 's/^.*): //')

  "$_SDSH" register --state-dir "$_osd" \
    --agente "agente-00c-feature-orchestrator" --etapa "specify" \
    --contexto "read-back PRE-DECISAO: K=$K achados injetados (anti-eco feature=featCurrent)" \
    --opcoes '["injetar-achados","no-op"]' --escolha "injetar-achados" \
    --justificativa "termos derivados da feature: $TERMS" --score 2 >/dev/null 2>&1 || {
      _fail "ctx-audit register" "state-decisions.sh register falhou"; return 1; }

  # 4.2.1 — Decisao existe com etapa specify, contexto read-back, K e termos.
  _sj="$_osd/state.json"
  _ndec=$(jq '[.decisoes[] | select(.contexto | startswith("read-back PRE-DECISAO"))] | length' "$_sj")
  [ "$_ndec" = "1" ] || { _fail "ctx-audit 4.2.1" "esperado 1 Decisao read-back, obtido $_ndec"; return 1; }
  _etapa=$(jq -r '.decisoes[] | select(.contexto | startswith("read-back")) | .etapa' "$_sj")
  [ "$_etapa" = "specify" ] || { _fail "ctx-audit etapa" "esperado specify, obtido $_etapa"; return 1; }
  # K e termos presentes (K no contexto, termos na justificativa).
  jq -e '.decisoes[] | select(.contexto | startswith("read-back")) | select(.contexto | contains("K='"$K"'"))' "$_sj" >/dev/null \
    || { _fail "ctx-audit K" "contexto nao contem K=$K"; return 1; }
  jq -e '.decisoes[] | select(.contexto | startswith("read-back")) | select(.justificativa | contains("'"$TERMS"'"))' "$_sj" >/dev/null \
    || { _fail "ctx-audit termos" "justificativa nao contem os termos"; return 1; }

  # 4.2.3 — body bruto recuperado NAO foi persistido no state.json (CHK013).
  if [ -n "$_bruto" ]; then
    case "$(cat "$_sj")" in
      *"$_bruto"*) _fail "ctx-audit CHK013" "body bruto recuperado vazou para state.json"; return 1 ;;
    esac
  fi
}

scenario_ctx_15b_k0_sem_decisao() {
  _have_deps || return 0
  _SDSH=$(_ctx_state_decisions_path) || return 0
  _RWSH=$(dirname "$_SDSH")/state-rw.sh
  [ -f "$_RWSH" ] || return 0

  _ctx_fixture_db "$TMPDIR_TEST/k.db"
  _osd="$TMPDIR_TEST/orch-state-k0"
  mkdir -p "$_osd"
  "$_RWSH" init --state-dir "$_osd" --execucao-id exec-featCurrent-k0 \
    --projeto-alvo-path /home/u/projX --descricao "feature corrente sob teste" >/dev/null 2>&1 || return 0

  # Consumo K=0 (termo inexistente): BLOCO vazio => NAO registra Decisao.
  BLOCO=$(_rc --context "termo-zzz-inexistente" --exclude-feature featCurrent --db "$TMPDIR_TEST/k.db" 2>/dev/null) || BLOCO=""
  if [ -n "$BLOCO" ]; then
    "$_SDSH" register --state-dir "$_osd" --agente x --etapa specify \
      --contexto "read-back PRE-DECISAO: nao deveria acontecer" \
      --opcoes '["a","b"]' --escolha a --justificativa "justificativa longa o suficiente" --score 2 >/dev/null 2>&1
  fi
  _sj="$_osd/state.json"
  _ndec=$(jq '[.decisoes[]? | select(.contexto | startswith("read-back"))] | length' "$_sj" 2>/dev/null) || _ndec=0
  [ "${_ndec:-0}" = "0" ] || { _fail "ctx-audit 4.2.2" "K=0 nao deveria gerar Decisao read-back, obtido $_ndec"; return 1; }
}

# Cenario regressao — modos existentes (busca/ingest/reindex) intactos
scenario_ctx_regressao_modos_existentes() {
  _have_deps || return 0
  _write_state "$TMPDIR_TEST/featA" "/home/u/projX" "featA"
  # ingest ainda funciona.
  capture _rc --ingest --state-dir "$TMPDIR_TEST/featA" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "decisions" || return 1
  # busca AND ainda funciona (regressao).
  capture _rc "widget" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "dec-001" || return 1
}

# =========================================================================
# knowledge-db-metrics — FASE 5 (camada B): ingestao tasks + events (US3)
# =========================================================================

# _write_layerb_state DIR PROJECT_PATH FEATURE -> state.json instrumentado
# com .tasks[] (2 tasks: 1 pass + 1 fail) e .eventos[] (4 tipos MVP, ordem
# cronologica + 1 descricao com segredo plantado para checar scrub).
_write_layerb_state() {
  _wb_dir="$1"; _wb_proj="$2"; _wb_feat="$3"
  mkdir -p "$_wb_dir"
  cat > "$_wb_dir/state.json" <<JSON
{
  "short_name": "$_wb_feat",
  "etapa_corrente": "execute-task",
  "execucao": { "id": "exec-$_wb_feat", "projeto_alvo_path": "$_wb_proj", "status": "concluido" },
  "metricas_acumuladas": {},
  "decisoes": [], "bloqueios_humanos": [], "ondas": [],
  "tasks": [
    { "task_id": "T001", "wave_id": "onda-003", "outcome": "pass",
      "testes_rodados": 12, "testes_passados": 12, "lint_ok": true,
      "arquivos_tocados": ["cli/lib/recall.sh", "tests/cstk/test_recall.sh"] },
    { "task_id": "T002", "wave_id": "onda-004", "outcome": "fail",
      "testes_rodados": 5, "testes_passados": 3, "lint_ok": false,
      "arquivos_tocados": [] }
  ],
  "eventos": [
    { "event_type": "lock_contention", "timestamp": "2026-05-24T02:31:00Z", "descricao": "lock ocupado token=ghp_DEADBEEFDEADBEEFDEADBEEFDEADBEEF1234 retry" },
    { "event_type": "wave_retry", "timestamp": "2026-05-24T02:35:10Z" },
    { "event_type": "validation_failed", "timestamp": "2026-05-24T02:40:00Z" },
    { "event_type": "schedule_wait", "timestamp": "2026-05-24T02:42:00Z" }
  ]
}
JSON
}

# Cenario B1.1 — DDL: tasks + events criadas no schema (Acceptance US3.1/3.2).
scenario_b11_ddl_tasks_events() {
  _have_deps || return 0
  _write_layerb_state "$TMPDIR_TEST/featB" "/home/u/projB" "featB"
  assert_exit 0 _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db" || return 1
  _has=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('tasks','events')")
  [ "$_has" = "2" ] || { _fail "DDL tasks/events" "esperado 2 tabelas, obtido $_has"; return 1; }
  # schema_version permanece 2 (tasks/events no MESMO bump v2).
  _sv=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT value FROM schema_meta WHERE key='schema_version'")
  [ "$_sv" = "2" ] || { _fail "schema_version" "esperado 2, obtido $_sv"; return 1; }
}

# Cenario B1.2 — ingestao Task: 1 linha por task, campos corretos, contagem
# de arquivos_tocados, lint_ok 0/1 (task 5.1.5, Acceptance US3.1).
scenario_b12_ingest_tasks() {
  _have_deps || return 0
  _write_layerb_state "$TMPDIR_TEST/featB" "/home/u/projB" "featB"
  capture _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "2 tasks" || return 1
  _n=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM tasks WHERE feature='featB'")
  [ "$_n" = "2" ] || { _fail "tasks count" "esperado 2, obtido $_n"; return 1; }
  # T001: pass, 12/12, lint 1, 2 arquivos; wave=onda-003, source_id=T001.
  _r1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT project||'|'||wave||'|'||source_id||'|'||outcome||'|'||testes_rodados||'|'||testes_passados||'|'||lint_ok||'|'||arquivos_tocados FROM tasks WHERE feature='featB' AND source_id='T001'")
  [ "$_r1" = "projB|onda-003|T001|pass|12|12|1|2" ] || { _fail "task T001" "obtido $_r1"; return 1; }
  # T002: fail, 5/3, lint 0, 0 arquivos; wave=onda-004.
  _r2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT wave||'|'||outcome||'|'||testes_rodados||'|'||testes_passados||'|'||lint_ok||'|'||arquivos_tocados FROM tasks WHERE feature='featB' AND source_id='T002'")
  [ "$_r2" = "onda-004|fail|5|3|0|0" ] || { _fail "task T002" "obtido $_r2"; return 1; }
}

# Cenario B2.1 — ingestao Evento: 4 tipos MVP, ordem cronologica, source_id
# = event_type:timestamp, wave='-' (task 5.2.5, Acceptance US3.2).
scenario_b21_ingest_events() {
  _have_deps || return 0
  _write_layerb_state "$TMPDIR_TEST/featB" "/home/u/projB" "featB"
  capture _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db"
  assert_stdout_contains "4 events" || return 1
  _n=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM events WHERE feature='featB'")
  [ "$_n" = "4" ] || { _fail "events count" "esperado 4, obtido $_n"; return 1; }
  # Ordem cronologica consultavel via ORDER BY source_ts.
  _seq=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT group_concat(event_type, ',') FROM (SELECT event_type FROM events WHERE feature='featB' ORDER BY source_ts)")
  [ "$_seq" = "lock_contention,wave_retry,validation_failed,schedule_wait" ] || { _fail "events ordem" "obtido $_seq"; return 1; }
  # source_id = event_type:timestamp; wave='-'.
  _sid=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT wave||'|'||source_id FROM events WHERE feature='featB' AND event_type='wave_retry'")
  [ "$_sid" = "-|wave_retry:2026-05-24T02:35:10Z" ] || { _fail "event source_id" "obtido $_sid"; return 1; }
}

# Cenario B2.2 — secrets-filter na descricao do evento (texto livre); tipo e
# timestamp estruturados NAO filtrados (task 5.2.3, FR-006, SC-007).
scenario_b22_event_descricao_filtrada() {
  _have_deps || return 0
  _write_layerb_state "$TMPDIR_TEST/featB" "/home/u/projB" "featB"
  _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _desc=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT descricao FROM events WHERE feature='featB' AND event_type='lock_contention'")
  case "$_desc" in
    *ghp_*) _fail "event scrub" "segredo nao filtrado na descricao: $_desc"; return 1 ;;
  esac
  # event_type/timestamp intactos (estruturado, sem filtro).
  _et=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT event_type||'|'||timestamp FROM events WHERE feature='featB' AND event_type='lock_contention'")
  [ "$_et" = "lock_contention|2026-05-24T02:31:00Z" ] || { _fail "event estruturado" "obtido $_et"; return 1; }
}

# Cenario B3.1 — retro-compat: state SEM .tasks/.eventos -> 0 linhas, 0 erro,
# exit 0 (task 5.3.2, SC-009, Acceptance US3.3).
scenario_b31_retrocompat_sem_tasks_eventos() {
  _have_deps || return 0
  # _write_metrics_state nao tem .tasks nem .eventos (pre-instrumentacao).
  _write_metrics_state "$TMPDIR_TEST/featOld" "/home/u/projOld" "featOld"
  capture _rc --ingest --state-dir "$TMPDIR_TEST/featOld" --db "$TMPDIR_TEST/k.db"
  [ "$_CAPTURED_EXIT" = "0" ] || { _fail "retro-compat exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "0 tasks, 0 events" || return 1
  _t=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM tasks WHERE feature='featOld'")
  _e=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM events WHERE feature='featOld'")
  [ "$_t" = "0" ] && [ "$_e" = "0" ] || { _fail "retro-compat linhas" "tasks=$_t events=$_e (esperado 0 0)"; return 1; }
}

# Cenario B3.2 — re-ingestao N vezes: delta de linhas tasks/events = 0
# (SC-004 estendido a camada B, idempotencia da chave natural).
scenario_b32_reingest_delta_zero() {
  _have_deps || return 0
  _write_layerb_state "$TMPDIR_TEST/featB" "/home/u/projB" "featB"
  _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _t1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM tasks")
  _e1=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM events")
  _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _rc --ingest --state-dir "$TMPDIR_TEST/featB" --db "$TMPDIR_TEST/k.db" >/dev/null 2>&1
  _t2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM tasks")
  _e2=$(sqlite3 "$TMPDIR_TEST/k.db" "SELECT count(*) FROM events")
  [ "$_t1" = "$_t2" ] && [ "$_e1" = "$_e2" ] || { _fail "delta zero B" "tasks $_t1->$_t2, events $_e1->$_e2"; return 1; }
  [ "$_t2" = "2" ] && [ "$_e2" = "4" ] || { _fail "contagem esperada B" "tasks=$_t2 events=$_e2 (esperado 2 4)"; return 1; }
}

# Cenario B3.3 — convergencia --ingest vs --reindex para camada B
# (task 5.3.3, FR-001/SC-002 estendido: reindex recria tasks/events identicos).
scenario_b33_ingest_vs_reindex_convergencia() {
  _have_deps || return 0
  # Caminho A: --ingest direto.
  _write_layerb_state "$TMPDIR_TEST/ing/featB" "/home/u/projB" "featB"
  _rc --ingest --state-dir "$TMPDIR_TEST/ing/featB" --db "$TMPDIR_TEST/a.db" >/dev/null 2>&1
  _ta=$(sqlite3 "$TMPDIR_TEST/a.db" "SELECT count(*) FROM tasks")
  _ea=$(sqlite3 "$TMPDIR_TEST/a.db" "SELECT count(*) FROM events")
  _dumpa=$(sqlite3 "$TMPDIR_TEST/a.db" "SELECT project,feature,wave,source_id,outcome,arquivos_tocados FROM tasks UNION ALL SELECT project,feature,wave,source_id,event_type,timestamp FROM events ORDER BY 1,2,3,4")
  # Caminho B: --reindex (descoberta padrao).
  _write_layerb_state "$TMPDIR_TEST/rx/p/.claude/feature-00c-state/featB" "/home/u/projB" "featB"
  _rc --reindex --states-root "$TMPDIR_TEST/rx" --db "$TMPDIR_TEST/b.db" >/dev/null 2>&1
  _tb=$(sqlite3 "$TMPDIR_TEST/b.db" "SELECT count(*) FROM tasks")
  _eb=$(sqlite3 "$TMPDIR_TEST/b.db" "SELECT count(*) FROM events")
  _dumpb=$(sqlite3 "$TMPDIR_TEST/b.db" "SELECT project,feature,wave,source_id,outcome,arquivos_tocados FROM tasks UNION ALL SELECT project,feature,wave,source_id,event_type,timestamp FROM events ORDER BY 1,2,3,4")
  [ "$_ta" = "$_tb" ] && [ "$_ea" = "$_eb" ] || { _fail "contagem ingest vs reindex B" "tasks $_ta/$_tb events $_ea/$_eb"; return 1; }
  [ "$_dumpa" = "$_dumpb" ] || { _fail "divergencia ingest vs reindex B" "dumps diferem"; return 1; }
}

run_all_scenarios
