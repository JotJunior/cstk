#!/bin/sh
# test_model-routing-report.sh — cobre
# global/skills/agente-00c-runtime/scripts/model-routing-report.sh.
#
# Feature: agente-00c-model-routing
# Ref: docs/specs/agente-00c-model-routing/spec.md FR-018, SC-003, US-3
#      docs/specs/agente-00c-model-routing/tasks.md F5.1 (5.1.1..5.1.3)
#      Decisao dec-006 (jq real-time sobre .decisoes[], sem campo agregado)
#
# Cobertura:
#   F5.1.1 (subcomando aggregate):
#     - dispatch: sem args -> exit 2 + USO em stderr
#     - dispatch: subcomando desconhecido -> exit 2
#     - aggregate sem --state-dir -> exit 2 + USO
#     - aggregate com --state-dir inexistente -> exit 1
#     - aggregate --json em fixture vazia -> total=0 + 0% fallback
#   F5.1.2 (invariante read-only IR-1):
#     - audit estatico: sem `jq -i`, sem redirecionamento `> $state_file`
#     - smoke: state.json sha256 estavel pos-invocacao
#   F5.1.3 (correcao do agregado em fixture com 8 selecoes):
#     - JSON contem total=8, haiku=4, sonnet=3, fallback-default=1
#     - fallback_pct=12.5%
#     - breakdown por_subagent_type=2 entradas (asker, answerer)
#     - decisao noise (contexto fora do prefixo) e ignorada
#     - Markdown contem cabecalho canonico + 8 linhas + Sumario
#   IR-2 (idempotencia):
#     - 3 invocacoes consecutivas com mesmo input produzem stdout identico
#       (byte-a-byte) — payload sem timestamps
#   IR-3 (Principio II POSIX):
#     - shebang #!/bin/sh + set -eu + sem bash-isms obvios
#   schema-en-migration (idiom §6):
#     - reader canonico em chaves EN (.decisions/.context/.choice/.rationale/
#       .wave_id/.stage/.justification_score) — fixture inline 100% EN
#     - back-compat: fixture pt-BR equivalente -> mesmo agregado (fallback
#       .en // .pt). Keys de OUTPUT (por_modelo/ondas.*/linhas) ficam pt-BR
#       (FOLLOW-UP D) e sao aseridas como tal.
#
# Convencao de exit code de scenario (interpretada pelo runner):
#   0 PASS, 1 FAIL, 2 ERROR (pre-req faltando — jq ausente, mktemp falhou)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/agente-00c-runtime/scripts/model-routing-report.sh"

# ---------- helpers locais ----------

_mrr_have_jq() {
  command -v jq >/dev/null 2>&1
}

# Copia o fixture canonico de selecoes (8 decisoes + 1 noise) para
# $TMPDIR_TEST/state.json. Retorna 0 ou 2 (ERROR se faltou pre-req).
#
# BACK-COMPAT (schema-en-migration, idiom §6): os fixtures compartilhados
# (state-with-selecao-decisoes.json, state-with-routing-onda-*.json) usam
# chaves pt-BR (.decisoes/.contexto/.escolha/.justificativa/.onda_id/
# .score_justificativa/.etapa). Mante-los em pt-BR exercita o READER-FALLBACK
# (.en // .pt) do helper a cada cenario que os carrega — prova de regressao
# de back-compat. O caminho EN-canonico e exercitado por
# scenario_aggregate_en_keys_reader_canonico (fixture inline em EN).
_mrr_load_selecao_fixture() {
  _src="$TESTS_ROOT/fixtures/state-with-selecao-decisoes.json"
  [ -f "$_src" ] || { _error "fixture_missing" "fixture state-with-selecao-decisoes.json nao encontrada"; return 2; }
  cp "$_src" "$TMPDIR_TEST/state.json" || { _error "fixture_copy_fail" "falha ao copiar fixture"; return 2; }
  return 0
}

# Copia um fixture nomeado de tests/fixtures para $TMPDIR_TEST/state.json.
# Usado pelos cenarios FASE 6 (DecisoesDeRoteamentoPorOnda).
_mrr_load_named_fixture() {
  _src="$TESTS_ROOT/fixtures/$1"
  [ -f "$_src" ] || { _error "fixture_missing" "fixture $1 nao encontrada"; return 2; }
  cp "$_src" "$TMPDIR_TEST/state.json" || { _error "fixture_copy_fail" "falha ao copiar fixture $1"; return 2; }
  return 0
}

# ==== Dispatch ====

scenario_sem_args_exit_2_e_usage_em_stderr() {
  capture sh "$SCRIPT"
  assert_exit 2 sh "$SCRIPT" || return 1
  assert_stderr_contains "USO:" || return 1
  assert_stderr_contains "aggregate" || return 1
}

scenario_subcomando_desconhecido_exit_2() {
  capture sh "$SCRIPT" bogus-subcmd-xyz
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "subcomando desconhecido" || return 1
  assert_stderr_contains "bogus-subcmd-xyz" || return 1
}

scenario_help_flag_short_long_e_help_subcmd() {
  capture sh "$SCRIPT" -h
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (-h)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1

  capture sh "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (--help)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "USO:" || return 1

  capture sh "$SCRIPT" help
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (help)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== F5.1.1: aggregate dispatch ====

scenario_aggregate_sem_state_dir_exit_2() {
  capture sh "$SCRIPT" aggregate
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit=2 (sem --state-dir)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--state-dir obrigatorio" || return 1
}

scenario_aggregate_state_dir_inexistente_exit_1() {
  mktemp_test || return 2
  # Diretorio sem state.json.
  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST/nope"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit=1 (sem state.json)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "state.json nao encontrado" || return 1
}

scenario_aggregate_state_vazio_total_0() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  # state.json minimo sem nenhuma Decisao (schema EN canonico).
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{ "schema_version": 1, "decisions": [] }
JSON
  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }
  # total deve ser 0 e fallback_pct deve ser "0.0%".
  _total=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total')
  [ "$_total" = "0" ] || { _fail "total=0" "obtido $_total"; return 1; }
  _pct=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.fallback_pct')
  [ "$_pct" = "0.0%" ] || { _fail "fallback_pct=0.0%" "obtido $_pct"; return 1; }
}

# ==== F5.1.3: agregado correto em fixture com 8 selecoes ====

scenario_aggregate_fixture_json_contagens_corretas() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_selecao_fixture || return $?

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  # 1 decisao noise (dec-999-noise) deve ser ignorada — total deve ser 8.
  _total=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total')
  [ "$_total" = "8" ] || { _fail "total=8" "obtido $_total (noise deveria ser filtrada)"; return 1; }

  # Counts por modelo.
  _haiku=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo.haiku')
  _sonnet=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo.sonnet')
  _opus=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo.opus')
  _man=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo["manter-atual"]')
  _fb=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo["fallback-default"]')
  [ "$_haiku" = "4" ]  || { _fail "haiku=4"  "obtido $_haiku";  return 1; }
  [ "$_sonnet" = "3" ] || { _fail "sonnet=3" "obtido $_sonnet"; return 1; }
  [ "$_opus" = "0" ]   || { _fail "opus=0"   "obtido $_opus";   return 1; }
  [ "$_man" = "0" ]    || { _fail "manter-atual=0" "obtido $_man"; return 1; }
  [ "$_fb" = "1" ]     || { _fail "fallback-default=1" "obtido $_fb"; return 1; }

  # fallback_pct = 1/8 = 12.5%.
  _pct=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.fallback_pct')
  [ "$_pct" = "12.5%" ] || { _fail "fallback_pct=12.5%" "obtido $_pct"; return 1; }

  # Breakdown por_subagent_type: exatamente 2 entradas.
  _nst=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_subagent_type | keys | length')
  [ "$_nst" = "2" ] || { _fail "por_subagent_type tem 2 entradas" "obtido $_nst"; return 1; }

  # Asker so tem haiku=4; answerer tem sonnet=3 + fallback-default=1.
  _ah=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_subagent_type["agente-00c-clarify-asker"].haiku')
  _ws=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_subagent_type["agente-00c-clarify-answerer"].sonnet')
  _wf=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_subagent_type["agente-00c-clarify-answerer"]["fallback-default"]')
  [ "$_ah" = "4" ] || { _fail "asker.haiku=4" "obtido $_ah"; return 1; }
  [ "$_ws" = "3" ] || { _fail "answerer.sonnet=3" "obtido $_ws"; return 1; }
  [ "$_wf" = "1" ] || { _fail "answerer.fallback-default=1" "obtido $_wf"; return 1; }
}

# ==== schema-en-migration: READER canonico em chaves EN ====
#
# Espelho minimo da agregacao (legado + por-onda) sobre um state.json com
# chaves EN-canonicas (.decisions/.context/.choice/.rationale/.wave_id/
# .justification_score/.stage). Prova que o helper LE o schema migrado sem
# depender do fallback pt-BR. Complementa os fixtures pt-BR compartilhados
# (que exercitam o fallback). As keys de OUTPUT do agregado (por_modelo,
# ondas.*, linhas) permanecem pt-BR (FOLLOW-UP D) — asseridas como tal.
scenario_aggregate_en_keys_reader_canonico() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  # Fixture inline 100% EN: 1 legada (haiku) + 2 por-onda (mapa/override) +
  # 1 noise. Sem nenhuma chave pt-BR -> exercita exclusivamente o path EN.
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "schema_version": 1,
  "execution": { "id": "fx-en", "status": "em_andamento" },
  "waves": [],
  "decisions": [
    { "id": "dec-001", "wave_id": "onda-001", "stage": "clarify",
      "agent": "agente-00c-orchestrator",
      "context": "Selecao de modelo para subagente agente-00c-clarify-asker",
      "choice": "haiku", "rationale": "asker enumerativo", "justification_score": 3 },
    { "id": "dec-w1", "wave_id": "onda-003", "stage": "model-routing",
      "agent": "agente-00c-feature-orchestrator",
      "context": "Selecao de modelo para onda 3 (fase plan)",
      "choice": "model:opus",
      "rationale": "sugerido=opus aplicado=opus origem=mapa | faixa profunda",
      "justification_score": 0 },
    { "id": "dec-w2", "wave_id": "onda-005", "stage": "model-routing",
      "agent": "agente-00c-feature-orchestrator",
      "context": "Selecao de modelo para onda 5 (fase execute-task)",
      "choice": "model:opus",
      "rationale": "sugerido=haiku aplicado=opus origem=override-operador | forcado",
      "justification_score": 2 },
    { "id": "dec-999-noise", "wave_id": "onda-001", "stage": "specify",
      "agent": "agente-00c-orchestrator",
      "context": "Decisao NAO relacionada a selecao — deve ser ignorada",
      "choice": "a", "rationale": "noise", "justification_score": 3 }
  ]
}
JSON

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  # Bloco legado: 1 Decisao "subagente" (haiku); noise ignorada.
  _total=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total')
  [ "$_total" = "1" ] || { _fail "legado total=1 (EN reader)" "obtido $_total"; return 1; }
  _haiku=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo.haiku')
  [ "$_haiku" = "1" ] || { _fail "legado haiku=1 (EN reader)" "obtido $_haiku"; return 1; }

  # A linha legada deve refletir os VALORES lidos das chaves EN
  # (.stage/.wave_id/.choice/.justification_score). Output keys = pt-BR.
  _l_etapa=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.linhas[0].etapa')
  _l_onda=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.linhas[0].onda')
  _l_modelo=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.linhas[0].modelo')
  _l_score=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.linhas[0].score')
  [ "$_l_etapa" = "clarify" ]   || { _fail "linha.etapa=clarify (lido de .stage EN)" "obtido $_l_etapa"; return 1; }
  [ "$_l_onda" = "onda-001" ]   || { _fail "linha.onda=onda-001 (lido de .wave_id EN)" "obtido $_l_onda"; return 1; }
  [ "$_l_modelo" = "haiku" ]    || { _fail "linha.modelo=haiku (lido de .choice EN)" "obtido $_l_modelo"; return 1; }
  [ "$_l_score" = "3" ]         || { _fail "linha.score=3 (lido de .justification_score EN)" "obtido $_l_score"; return 1; }

  # Bloco por-onda: 2 Decisoes; aplicado opus=2; mapa=1, override=1.
  _wt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.total')
  [ "$_wt" = "2" ] || { _fail "ondas.total=2 (EN reader)" "obtido $_wt"; return 1; }
  _ao=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_modelo_aplicado.opus')
  [ "$_ao" = "2" ] || { _fail "aplicado opus=2 (EN reader)" "obtido $_ao"; return 1; }
  _om=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_origem.mapa')
  _oov=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_origem["override-operador"]')
  [ "$_om" = "1" ]  || { _fail "origem mapa=1 (EN reader)" "obtido $_om"; return 1; }
  [ "$_oov" = "1" ] || { _fail "origem override-operador=1 (EN reader)" "obtido $_oov"; return 1; }

  # override (haiku->opus) diverge e e ROTULADA; mapa (opus->opus) nao diverge.
  _div=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias')
  _drot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_rotuladas')
  _dsem=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_sem_rotulo')
  [ "$_div" = "1" ]  || { _fail "divergencias=1 (EN reader)" "obtido $_div"; return 1; }
  [ "$_drot" = "1" ] || { _fail "divergencias_rotuladas=1 (EN reader)" "obtido $_drot"; return 1; }
  [ "$_dsem" = "0" ] || { _fail "divergencias_sem_rotulo=0 (EN reader)" "obtido $_dsem"; return 1; }
}

# ==== schema-en-migration: BACK-COMPAT explicito (fixture pt-BR) ====
#
# Prova direta do reader-fallback (.en // .pt): um state.json com chaves
# 100% pt-BR (.decisoes/.contexto/.choice... em pt) deve produzir o MESMO
# agregado. Espelha o fixture EN acima para garantir paridade pt<->en.
scenario_aggregate_pt_keys_reader_fallback() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  cat > "$TMPDIR_TEST/state.json" <<'JSON'
{
  "schema_version": 1,
  "execucao": { "id": "fx-pt", "status": "em_andamento" },
  "ondas": [],
  "decisoes": [
    { "id": "dec-001", "onda_id": "onda-001", "etapa": "clarify",
      "agente": "agente-00c-orchestrator",
      "contexto": "Selecao de modelo para subagente agente-00c-clarify-asker",
      "escolha": "haiku", "justificativa": "asker enumerativo", "score_justificativa": 3 },
    { "id": "dec-w1", "onda_id": "onda-003", "etapa": "model-routing",
      "agente": "agente-00c-feature-orchestrator",
      "contexto": "Selecao de modelo para onda 3 (fase plan)",
      "escolha": "model:opus",
      "justificativa": "sugerido=opus aplicado=opus origem=mapa | faixa profunda",
      "score_justificativa": 0 },
    { "id": "dec-w2", "onda_id": "onda-005", "etapa": "model-routing",
      "agente": "agente-00c-feature-orchestrator",
      "contexto": "Selecao de modelo para onda 5 (fase execute-task)",
      "escolha": "model:opus",
      "justificativa": "sugerido=haiku aplicado=opus origem=override-operador | forcado",
      "score_justificativa": 2 },
    { "id": "dec-999-noise", "onda_id": "onda-001", "etapa": "specify",
      "agente": "agente-00c-orchestrator",
      "contexto": "Decisao NAO relacionada a selecao — deve ser ignorada",
      "escolha": "a", "justificativa": "noise", "score_justificativa": 3 }
  ]
}
JSON

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  # Paridade com o cenario EN: mesmos numeros via fallback pt-BR.
  _total=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total')
  [ "$_total" = "1" ] || { _fail "legado total=1 (pt fallback)" "obtido $_total"; return 1; }
  _l_onda=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.linhas[0].onda')
  [ "$_l_onda" = "onda-001" ] || { _fail "linha.onda=onda-001 (fallback .onda_id)" "obtido $_l_onda"; return 1; }
  _l_score=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.linhas[0].score')
  [ "$_l_score" = "3" ] || { _fail "linha.score=3 (fallback .score_justificativa)" "obtido $_l_score"; return 1; }
  _wt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.total')
  [ "$_wt" = "2" ] || { _fail "ondas.total=2 (pt fallback)" "obtido $_wt"; return 1; }
  _ao=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_modelo_aplicado.opus')
  [ "$_ao" = "2" ] || { _fail "aplicado opus=2 (pt fallback)" "obtido $_ao"; return 1; }
  _drot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_rotuladas')
  [ "$_drot" = "1" ] || { _fail "divergencias_rotuladas=1 (pt fallback)" "obtido $_drot"; return 1; }
}

scenario_aggregate_fixture_markdown_formato_canonico() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_selecao_fixture || return $?

  # Default e Markdown (sem --json).
  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  # Cabecalho canonico exigido por F5.2.2.
  assert_stdout_contains "## Selecao de modelo por subagente (model-routing)" || return 1
  # Cabecalho de tabela.
  assert_stdout_contains "| subagent_type | etapa | onda | modelo | score | fallback |" || return 1
  # Sumario com totais.
  assert_stdout_contains "**Sumario**:" || return 1
  assert_stdout_contains "- Total: 8" || return 1
  assert_stdout_contains "- haiku: 4" || return 1
  assert_stdout_contains "- sonnet: 3" || return 1
  assert_stdout_contains "- fallback-default: 1 (12.5%)" || return 1
}

# ==== F5.1.2: invariante read-only (IR-1) ====

scenario_ir1_read_only_audit_estatico() {
  # Nenhum jq -i (edit-in-place) no helper.
  if grep -qE 'jq[[:space:]]+(-[a-zA-Z]*i|-[a-zA-Z]*--in-place)' "$SCRIPT"; then
    _fail "audit IR-1: jq -i nao deve aparecer" "encontrado em $SCRIPT"
    return 1
  fi
  # Nenhum redirecionamento direto para state_file (state.json / _mrr_state_file).
  # Filtramos comentarios para nao falsearmos positivos.
  _bad=$(grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -E '>[[:space:]]*"?[^"]*state(\.json|_file)' || :)
  if [ -n "$_bad" ]; then
    _fail "audit IR-1: redirect ao state.json nao permitido" "$_bad"
    return 1
  fi
}

scenario_ir1_read_only_sha256_state_estavel() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1 \
    || { _error "shasum/sha256sum ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_selecao_fixture || return $?

  if command -v shasum >/dev/null 2>&1; then
    _hash_before=$(shasum -a 256 "$TMPDIR_TEST/state.json" | awk '{print $1}')
  else
    _hash_before=$(sha256sum "$TMPDIR_TEST/state.json" | awk '{print $1}')
  fi
  sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json >/dev/null 2>&1
  sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"        >/dev/null 2>&1
  if command -v shasum >/dev/null 2>&1; then
    _hash_after=$(shasum -a 256 "$TMPDIR_TEST/state.json" | awk '{print $1}')
  else
    _hash_after=$(sha256sum "$TMPDIR_TEST/state.json" | awk '{print $1}')
  fi
  [ "$_hash_before" = "$_hash_after" ] || {
    _fail "sha256 do state.json estavel" "before=$_hash_before after=$_hash_after"
    return 1
  }
}

# ==== IR-2: idempotencia (3 invocacoes consecutivas, mesmo output) ====

scenario_ir2_idempotente_3_invocacoes_stdout_identico() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_selecao_fixture || return $?

  _o1=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  _o2=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  _o3=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  [ "$_o1" = "$_o2" ] || { _fail "invocacoes 1 e 2 identicas" "diferem"; return 1; }
  [ "$_o2" = "$_o3" ] || { _fail "invocacoes 2 e 3 identicas" "diferem"; return 1; }
}

# ==== IR-3 (Principio II POSIX): shebang + set -eu + sem bash-isms ====

scenario_ir3_shebang_set_eu_no_bashisms() {
  _line1=$(head -1 "$SCRIPT")
  [ "$_line1" = "#!/bin/sh" ] || { _fail "shebang" "esperado '#!/bin/sh', obtido '$_line1'"; return 1; }
  grep -q '^set -eu$' "$SCRIPT" || { _fail "set -eu" "nao encontrado"; return 1; }
  if grep -qE '\[\[ ' "$SCRIPT"; then
    _fail "bash-ism" "[[ ]] detectado"
    return 1
  fi
}

# ==== F5.2.4: integracao review-task (simulada) ====
#
# review-task e uma skill LLM-driven (Markdown +
# instrucoes textuais — sem entrypoint shell). A integracao testavel
# em CI e: "quando review-task seguir o §4.5 do SKILL.md, o output
# colado no relatorio MUST ser byte-identico ao stdout default do
# helper, posicionado entre 'Progresso por Fase' e 'Recomendacoes'."
#
# Os cenarios abaixo simulam esse pipeline:
#   1. monta um template-base de relatorio (sem secao model-routing)
#   2. invoca o helper e captura stdout
#   3. injeta stdout entre as duas secoes ancoras
#   4. valida estrutura + invariantes do contrato review-task-aggregate.md

# _mrr_build_template_review_report PATH
# Cria um arquivo Markdown minimo (estilo review-N.md) com as duas
# ancoras esperadas pelo §4 do contrato.
_mrr_build_template_review_report() {
  cat > "$1" <<'EOF'
# Relatorio de Status das Tarefas

**Data:** 2026-05-23
**Projeto:** agente-00c-model-routing
**Tipo:** Documentacao

---

## Resumo Executivo

| Metrica | Valor |
|---------|-------|
| Total de Tarefas | 50 |
| Concluidas | 40 (80%) |

---

## Progresso por Fase

| Fase | Total | Concluidas | % |
|------|-------|------------|---|
| 5 - Agregacao review-task | 4 | 4 | 100% |

---

## Recomendacoes

### Acoes Imediatas
1. Fechar FASE 5
EOF
}

# _mrr_inject_section TEMPLATE_PATH HELPER_OUTPUT_PATH
# Insere o conteudo de HELPER_OUTPUT_PATH no TEMPLATE_PATH, entre as
# linhas "## Progresso por Fase" (com sua tabela) e "## Recomendacoes".
# Usa awk POSIX (sem GNU extensions).
_mrr_inject_section() {
  _tmpl=$1
  _src=$2
  _out=$(mktemp -- "${_tmpl}.injected.XXXXXX") || return 2
  # Pre-Reco: ate (mas nao incluindo) "## Recomendacoes".
  # Pos-Reco: a partir de "## Recomendacoes" inclusive.
  awk -v src="$_src" '
    /^## Recomendacoes[[:space:]]*$/ && !injected {
      while ((getline line < src) > 0) print line
      close(src)
      print ""
      print "---"
      print ""
      injected=1
    }
    { print }
  ' "$_tmpl" > "$_out" || { rm -f "$_out"; return 1; }
  mv "$_out" "$_tmpl"
}

scenario_integracao_review_task_template_recebe_secao_canonica() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_selecao_fixture || return $?

  _tmpl="$TMPDIR_TEST/review-001.md"
  _mrr_build_template_review_report "$_tmpl" \
    || { _error "falha ao gerar template"; return 2; }

  # Captura stdout do helper (fonte de verdade do contrato).
  _helper_out="$TMPDIR_TEST/helper.md"
  sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" > "$_helper_out" \
    || { _fail "helper exit !=0" ""; return 1; }

  # Injeta antes de "## Recomendacoes".
  _mrr_inject_section "$_tmpl" "$_helper_out" \
    || { _fail "injecao falhou" ""; return 1; }

  # === Validacoes §3.1 (cabecalho) ===
  grep -qF '## Selecao de modelo por subagente (model-routing)' "$_tmpl" \
    || { _fail "cabecalho canonico ausente no relatorio injetado" ""; return 1; }

  # === Validacoes §3.2 (cabecalho de tabela exato) ===
  grep -qF '| subagent_type | etapa | onda | modelo | score | fallback |' "$_tmpl" \
    || { _fail "cabecalho de tabela canonico ausente" ""; return 1; }
  grep -qF '|---------------|-------|------|--------|-------|----------|' "$_tmpl" \
    || { _fail "separador de tabela canonico ausente" ""; return 1; }

  # === Validacoes §3.3 (sumario com 5 chaves estaveis) ===
  grep -qF '**Sumario**:' "$_tmpl" \
    || { _fail "header de Sumario ausente" ""; return 1; }
  for _key in "Total: 8" "haiku: 4" "sonnet: 3" "opus: 0" "manter-atual: 0" "fallback-default: 1 (12.5%)"; do
    grep -qF -- "- $_key" "$_tmpl" \
      || { _fail "sumario key '$_key' ausente" ""; return 1; }
  done

  # === INV-RT-1 (byte-identidade contra stdout do helper) ===
  # Extrai apenas o bloco da secao (cabecalho ate antes da proxima '## ' ou '---').
  _extracted=$(mktemp -- "${_tmpl}.extracted.XXXXXX") || { _error "mktemp falhou"; return 2; }
  awk '
    /^## Selecao de modelo por subagente \(model-routing\)[[:space:]]*$/ { in_sec=1 }
    in_sec && /^---[[:space:]]*$/ { in_sec=0; exit }
    in_sec && /^## / && !/^## Selecao de modelo/ { in_sec=0; exit }
    in_sec { print }
  ' "$_tmpl" > "$_extracted"

  # Comparar com helper_out (ignorando trailing blank lines em ambos).
  _norm_a=$(awk 'NF{p=1} p {print}' "$_extracted" | awk '{lines[NR]=$0} END{n=NR; while (n>0 && lines[n]=="") n--; for (i=1;i<=n;i++) print lines[i]}')
  _norm_b=$(awk 'NF{p=1} p {print}' "$_helper_out" | awk '{lines[NR]=$0} END{n=NR; while (n>0 && lines[n]=="") n--; for (i=1;i<=n;i++) print lines[i]}')
  [ "$_norm_a" = "$_norm_b" ] || {
    _fail "INV-RT-1: secao injetada diverge do stdout do helper" "diff visivel via awk-normalize"
    return 1
  }
}

scenario_integracao_review_task_posicionamento_apos_progresso_antes_recomendacoes() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_selecao_fixture || return $?

  _tmpl="$TMPDIR_TEST/review-002.md"
  _mrr_build_template_review_report "$_tmpl" || { _error "template fail"; return 2; }

  _helper_out="$TMPDIR_TEST/helper.md"
  sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" > "$_helper_out" \
    || { _fail "helper exit !=0" ""; return 1; }
  _mrr_inject_section "$_tmpl" "$_helper_out" \
    || { _fail "injecao falhou" ""; return 1; }

  # Validar §4: a secao MUST estar apos "## Progresso por Fase" e
  # antes de "## Recomendacoes".
  _ln_progresso=$(grep -n '^## Progresso por Fase' "$_tmpl" | head -1 | cut -d: -f1)
  _ln_modelo=$(grep -n '^## Selecao de modelo por subagente (model-routing)' "$_tmpl" | head -1 | cut -d: -f1)
  _ln_reco=$(grep -n '^## Recomendacoes' "$_tmpl" | head -1 | cut -d: -f1)

  [ -n "$_ln_progresso" ] && [ -n "$_ln_modelo" ] && [ -n "$_ln_reco" ] || {
    _fail "secoes-ancora ausentes" "prog=$_ln_progresso mod=$_ln_modelo reco=$_ln_reco"
    return 1
  }
  [ "$_ln_progresso" -lt "$_ln_modelo" ] || {
    _fail "modelo deve vir APOS Progresso" "prog=$_ln_progresso modelo=$_ln_modelo"
    return 1
  }
  [ "$_ln_modelo" -lt "$_ln_reco" ] || {
    _fail "modelo deve vir ANTES Recomendacoes" "modelo=$_ln_modelo reco=$_ln_reco"
    return 1
  }
}

scenario_integracao_review_task_state_sem_selecoes_omite_secao() {
  # INV-RT-3: state com .total == 0 -> review-task NAO inclui a secao
  # (omitida por completo, sem cabecalho vazio).
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2

  # Cria state minimo SEM selecoes (apenas .decisions vazio; schema EN).
  cat > "$TMPDIR_TEST/state.json" <<'EOF'
{
  "schema_version": "0.1.0",
  "execution": { "status": "em_andamento" },
  "waves": [],
  "decisions": []
}
EOF

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "helper exit 0" "obtido $_CAPTURED_EXIT"; return 1; }

  _total=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total')
  [ "$_total" = "0" ] || { _fail "total=0" "obtido $_total"; return 1; }

  # Trigger semantico do contrato §2: review-task NAO deve incluir a
  # secao quando .total == 0. Aqui validamos que o consumidor pode
  # tomar essa decisao de forma confiavel (helper retorna 0 + total=0,
  # nao confunde com erro).
  # Tambem: o Markdown default NAO deve ter "linhas" de tabela.
  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "Markdown helper exit 0" ""; return 1; }
  # Sumario com Total: 0 esta presente no Markdown (helper sempre
  # imprime cabecalho); o consumidor decide omitir. Validamos
  # apenas que Total: 0 e detectavel via grep.
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -qF -- '- Total: 0' \
    || { _fail "Sumario com 'Total: 0' detectavel" ""; return 1; }
}

scenario_integracao_review_task_contrato_documentado_existe() {
  # Sanity: o contrato review-task-aggregate.md deve existir e ter as
  # secoes esperadas. Falha cedo se docs foram apagadas/movidas.
  _contract="$REPO_ROOT/docs/specs/_archived/agente-00c-model-routing/contracts/review-task-aggregate.md"
  [ -f "$_contract" ] || { _fail "contrato ausente" "$_contract"; return 1; }
  for _anchor in \
    "Path canonico do relatorio" \
    "Trigger de inclusao da secao" \
    "Formato exato da secao" \
    "Posicionamento da secao" \
    "Invariantes" \
  ; do
    grep -qF "$_anchor" "$_contract" \
      || { _fail "ancora '$_anchor' ausente em contrato" ""; return 1; }
  done
}

scenario_integracao_review_task_skill_md_referencia_helper() {
  # Sanity: review-task/SKILL.md DEVE conter referencia explicita ao
  # helper + secao §4.5. Falha cedo se SKILL.md foi reformatada.
  _skill="$REPO_ROOT/global/skills/review-task/SKILL.md"
  [ -f "$_skill" ] || { _fail "SKILL.md ausente" "$_skill"; return 1; }
  grep -qF 'model-routing-report.sh' "$_skill" \
    || { _fail "SKILL.md nao referencia model-routing-report.sh" ""; return 1; }
  grep -qF 'Agregacao de selecao de modelo (model-routing)' "$_skill" \
    || { _fail "secao §4.5 ausente em SKILL.md" ""; return 1; }
}

# ==== FASE 6.1.4 (feature model-routing-por-onda): agregacao mista ====
#
# Cobertura:
#   6.1.1 distribuicao do modelo_aplicado, taxa de fallback, taxa de override
#   6.1.2 divergencias sugerido!=aplicado com origem rotulada; 0 sem rotulo
#   6.1.3 coexistencia legado (fallback-default) + novo SEM quebrar agregacao
#   FR-021/SC-006

# Backward-compat: o bloco LEGADO deve permanecer intacto sobre a fixture
# antiga (que so tem Decisoes "...subagente <T>"), e ondas.total deve ser 0.
scenario_fase6_legado_intacto_ondas_zero() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_selecao_fixture || return $?

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  # Bloco legado preservado (total=8, fallback 12.5%).
  _total=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total')
  [ "$_total" = "8" ] || { _fail "legado total=8" "obtido $_total"; return 1; }
  _pct=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.fallback_pct')
  [ "$_pct" = "12.5%" ] || { _fail "legado fallback_pct=12.5%" "obtido $_pct"; return 1; }

  # Bloco novo zerado (a fixture nao tem Decisoes por-onda).
  _wt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.total')
  [ "$_wt" = "0" ] || { _fail "ondas.total=0 (fixture legada)" "obtido $_wt"; return 1; }
  _wsem=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_sem_rotulo')
  [ "$_wsem" = "0" ] || { _fail "ondas.divergencias_sem_rotulo=0" "obtido $_wsem"; return 1; }

  # Markdown legado NAO inclui a secao por-onda quando ondas.total=0.
  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"
  printf '%s\n' "$_CAPTURED_STDOUT" | grep -qF 'Selecao de modelo por onda' \
    && { _fail "secao por-onda NAO deve aparecer com ondas.total=0" ""; return 1; }
  return 0
}

# Fixture mista: 2 legadas (haiku + fallback-default) + 4 por-onda
# (mapa/refino/override/fallback) + 1 noise. Assert dos rotulos novos.
scenario_fase6_mista_json_contagens_e_rotulos() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_named_fixture "state-with-routing-onda-mixed.json" || return $?

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  # --- Bloco legado: 2 Decisoes "subagente", noise ignorada (FR-021) ---
  _ltot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.total')
  [ "$_ltot" = "2" ] || { _fail "legado total=2" "obtido $_ltot"; return 1; }
  _lh=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo.haiku')
  _lf=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.por_modelo["fallback-default"]')
  [ "$_lh" = "1" ] || { _fail "legado haiku=1" "obtido $_lh"; return 1; }
  [ "$_lf" = "1" ] || { _fail "legado fallback-default=1" "obtido $_lf"; return 1; }

  # --- Bloco novo por-onda: 4 Decisoes (6.1.1) ---
  _wt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.total')
  [ "$_wt" = "4" ] || { _fail "ondas.total=4" "obtido $_wt"; return 1; }

  # Distribuicao do modelo APLICADO: opus=1(mapa)+1(override)=2, sonnet=1,
  # manter-atual=1, haiku=0.
  _ao=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_modelo_aplicado.opus')
  _as=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_modelo_aplicado.sonnet')
  _am=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_modelo_aplicado["manter-atual"]')
  _ah=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_modelo_aplicado.haiku')
  [ "$_ao" = "2" ] || { _fail "aplicado opus=2" "obtido $_ao"; return 1; }
  [ "$_as" = "1" ] || { _fail "aplicado sonnet=1" "obtido $_as"; return 1; }
  [ "$_am" = "1" ] || { _fail "aplicado manter-atual=1" "obtido $_am"; return 1; }
  [ "$_ah" = "0" ] || { _fail "aplicado haiku=0" "obtido $_ah"; return 1; }

  # Por origem: mapa/refino/override-operador/fallback = 1/1/1/1.
  _om=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_origem.mapa')
  _orf=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_origem.refino')
  _oov=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_origem["override-operador"]')
  _ofb=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.por_origem.fallback')
  [ "$_om" = "1" ]  || { _fail "origem mapa=1" "obtido $_om"; return 1; }
  [ "$_orf" = "1" ] || { _fail "origem refino=1" "obtido $_orf"; return 1; }
  [ "$_oov" = "1" ] || { _fail "origem override-operador=1" "obtido $_oov"; return 1; }
  [ "$_ofb" = "1" ] || { _fail "origem fallback=1" "obtido $_ofb"; return 1; }

  # Taxa de fallback (manter-atual) e override: 1/4 = 25% cada.
  _fbpct=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.fallback_pct')
  _ovpct=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.override_pct')
  [ "$_fbpct" = "25%" ] || { _fail "ondas.fallback_pct=25%" "obtido $_fbpct"; return 1; }
  [ "$_ovpct" = "25%" ] || { _fail "ondas.override_pct=25%" "obtido $_ovpct"; return 1; }

  # --- Divergencias (6.1.2 / SC-006): override + fallback divergem,
  # ambas ROTULADAS; 0 sem rotulo. ---
  _div=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias')
  _drot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_rotuladas')
  _dsem=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_sem_rotulo')
  [ "$_div" = "2" ]  || { _fail "divergencias=2 (override+fallback)" "obtido $_div"; return 1; }
  [ "$_drot" = "2" ] || { _fail "divergencias_rotuladas=2" "obtido $_drot"; return 1; }
  [ "$_dsem" = "0" ] || { _fail "divergencias_sem_rotulo=0 (SC-006)" "obtido $_dsem"; return 1; }
}

# Markdown da fixture mista: a secao por-onda DEVE aparecer com cabecalho
# canonico + sumario por onda; o cabecalho legado tambem permanece.
scenario_fase6_mista_markdown_secao_por_onda() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_named_fixture "state-with-routing-onda-mixed.json" || return $?

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  # Cabecalho legado preservado.
  assert_stdout_contains "## Selecao de modelo por subagente (model-routing)" || return 1
  # Cabecalho da nova secao por-onda.
  assert_stdout_contains "## Selecao de modelo por onda (sugerido vs aplicado)" || return 1
  assert_stdout_contains "| onda | etapa | sugerido | aplicado | origem | divergente |" || return 1
  # Sumario por onda com taxas.
  assert_stdout_contains "**Sumario por onda**:" || return 1
  assert_stdout_contains "- Total de ondas roteadas: 4" || return 1
  assert_stdout_contains "- fallback (manter-atual): 1 (25%)" || return 1
  assert_stdout_contains "- override do operador: 1 (25%)" || return 1
  assert_stdout_contains "- divergencias sugerido!=aplicado: 2 (rotuladas: 2, sem rotulo: 0)" || return 1
  # Linha override (haiku->opus, divergente=yes) e linha fallback
  # (sonnet->manter-atual, divergente=yes; origem=fallback).
  assert_stdout_contains "| onda-005 | execute-task | haiku | opus | override-operador | yes |" || return 1
  assert_stdout_contains "| onda-006 | create-tasks | sonnet | manter-atual | fallback | yes |" || return 1
  # Linha mapa (opus->opus) e refino (sonnet->sonnet): nao divergentes.
  assert_stdout_contains "| onda-003 | plan | opus | opus | mapa | no |" || return 1
  assert_stdout_contains "| onda-004 | execute-task | sonnet | sonnet | refino | no |" || return 1
}

# SC-006 DETECTOR: divergencia com origem NAO-rotulada (origem=mapa) DEVE
# aparecer em divergencias_sem_rotulo > 0. Garante que o agregador e um
# detector fiel (nao mascara violacoes).
scenario_fase6_detector_divergencia_sem_rotulo() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_named_fixture "state-with-routing-onda-unlabeled-diverg.json" || return $?

  capture sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit=0" "obtido $_CAPTURED_EXIT"; return 1; }

  _wt=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.total')
  [ "$_wt" = "1" ] || { _fail "ondas.total=1" "obtido $_wt"; return 1; }
  _div=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias')
  _drot=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_rotuladas')
  _dsem=$(printf '%s' "$_CAPTURED_STDOUT" | jq -r '.ondas.divergencias_sem_rotulo')
  [ "$_div" = "1" ]  || { _fail "divergencias=1" "obtido $_div"; return 1; }
  [ "$_drot" = "0" ] || { _fail "divergencias_rotuladas=0 (origem=mapa nao autoriza)" "obtido $_drot"; return 1; }
  [ "$_dsem" = "1" ] || { _fail "divergencias_sem_rotulo=1 (DETECTOR SC-006)" "obtido $_dsem"; return 1; }
}

# Idempotencia do bloco novo: 3 invocacoes -> stdout identico (IR-2).
scenario_fase6_idempotente_bloco_novo() {
  _mrr_have_jq || { _error "jq ausente"; return 2; }
  mktemp_test || return 2
  _mrr_load_named_fixture "state-with-routing-onda-mixed.json" || return $?

  _o1=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  _o2=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST" --json)
  _o3=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST")
  _o3b=$(sh "$SCRIPT" aggregate --state-dir "$TMPDIR_TEST")
  [ "$_o1" = "$_o2" ] || { _fail "JSON 1 e 2 identicos" "diferem"; return 1; }
  [ "$_o3" = "$_o3b" ] || { _fail "Markdown identico" "diferem"; return 1; }
}

run_all_scenarios "$0"
