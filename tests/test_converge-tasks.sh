#!/bin/sh
# test_converge-tasks.sh — cobre global/skills/converge/scripts/converge-tasks.sh.
#
# Ref: docs/specs/skill-converge/tasks.md tarefa 2.5.7
#      docs/specs/skill-converge/contracts/converge-interfaces.md §4
#      docs/specs/skill-converge/data-model.md §Definição de normalize()
#      docs/specs/skill-converge/research.md Decision 2 (fronteira de
#      idempotencia vive no CHAMADOR, nao em append-phase)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/global/skills/converge/scripts/converge-tasks.sh"
NEXT_TASK_ID="$REPO_ROOT/global/skills/create-tasks/scripts/next-task-id.sh"

_write_tasks() {
  cat > "$TMPDIR_TEST/tasks.md"
}

# ---------- next-phase: com/sem fases existentes ----------

scenario_next_phase_com_fases_existentes() {
  _write_tasks <<'EOF'
# Tasks

## FASE 1 - Primeira

### 1.1 Algo `[A]`
- [x] 1.1.1 feito

## FASE 3 - Terceira

### 3.1 Outro `[A]`
- [ ] 3.1.1 pendente
EOF
  capture "$SCRIPT" next-phase --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "4" ] || { _fail "next-phase" "esperado 4 (max=3+1), obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_next_phase_sem_fase_alguma_retorna_1() {
  : > "$TMPDIR_TEST/tasks.md"
  capture "$SCRIPT" next-phase --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "1" ] || { _fail "next-phase" "esperado 1 (feature nunca teve FASE), obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_next_phase_tasks_ausente_exit1() {
  capture "$SCRIPT" next-phase --tasks "$TMPDIR_TEST/nao-existe.md"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- existing-keys: com/sem marcadores ----------

scenario_existing_keys_sem_marcadores_saida_vazia() {
  _write_tasks <<'EOF'
# Tasks

## FASE 1 - Primeira

### 1.1 Algo `[A]`
- [x] 1.1.1 feito, sem marcador de convergencia
EOF
  capture "$SCRIPT" existing-keys --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "existing-keys" "esperado vazio (feature nunca convergida), obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_existing_keys_com_multiplos_marcadores() {
  _write_tasks <<'EOF'
# Tasks

## FASE 1 - Primeira
### 1.1 Algo `[A]`
- [x] 1.1.1 feito

## FASE 2 - Convergência

### 2.1 Corrigir path ausente `[A]`
- [ ] 2.1.1 implementar path X
<!-- converge-key: aaaaaaaaaaaa -->

### 2.2 Revisar path extra `[M]`
- [ ] 2.2.1 revisar path Y
<!-- converge-key: bbbbbbbbbbbb -->
EOF
  capture "$SCRIPT" existing-keys --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "aaaaaaaaaaaa" || return 1
  assert_stdout_contains "bbbbbbbbbbbb" || return 1
  _n=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c .)
  [ "$_n" = 2 ] || { _fail "contagem" "esperado 2 chaves, obtido $_n"; return 1; }
}

scenario_existing_keys_tasks_ausente_exit1() {
  capture "$SCRIPT" existing-keys --tasks "$TMPDIR_TEST/nao-existe.md"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- gap-key: deterministico + normalize() ----------

scenario_gap_key_deterministico_mesma_entrada_mesma_saida() {
  capture "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "FR-007"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _first="$_CAPTURED_STDOUT"
  capture "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "FR-007"
  _second="$_CAPTURED_STDOUT"
  [ "$_first" = "$_second" ] || { _fail "determinismo" "esperado mesma saida, obtido $_first vs $_second"; return 1; }
  # 12 chars hex minusculos (sha256-12)
  case "$_first" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) _fail "formato" "esperado 12 chars hex minusculos, obtido: $_first"; return 1 ;;
  esac
}

scenario_gap_key_normalize_path_equivalencia() {
  _k1=$(sh "$SCRIPT" gap-key --path "./scripts/foo.sh" --type missing --origin "FR-007")
  _k2=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "FR-007")
  _k3=$(sh "$SCRIPT" gap-key --path "scripts//foo.sh" --type missing --origin "FR-007")
  _k4=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh/" --type missing --origin "FR-007")
  if [ "$_k1" != "$_k2" ] || [ "$_k2" != "$_k3" ] || [ "$_k3" != "$_k4" ]; then
    _fail "normalize(path)" "esperado todas iguais: k1=$_k1 k2=$_k2 k3=$_k3 k4=$_k4"
    return 1
  fi
}

scenario_gap_key_normalize_origin_fr_case_equivalencia() {
  _k1=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "fr-007")
  _k2=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "FR-007")
  _k3=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "Fr-007")
  if [ "$_k1" != "$_k2" ] || [ "$_k2" != "$_k3" ]; then
    _fail "normalize(origin) FR-" "esperado todas iguais: k1=$_k1 k2=$_k2 k3=$_k3"
    return 1
  fi
}

scenario_gap_key_normalize_origin_heading_reduzido_a_nm() {
  _k1=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing \
    --origin '### 2.1 scripts/path-contains.sh — contenção de blast radius [C]')
  _k2=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "2.1")
  [ "$_k1" = "$_k2" ] || { _fail "normalize(origin) heading" "esperado igual a '2.1', obtido k1=$_k1 k2=$_k2"; return 1; }
}

scenario_gap_key_paths_distintos_geram_chaves_distintas() {
  _k1=$(sh "$SCRIPT" gap-key --path "scripts/foo.sh" --type missing --origin "FR-007")
  _k2=$(sh "$SCRIPT" gap-key --path "scripts/bar.sh" --type missing --origin "FR-007")
  [ "$_k1" != "$_k2" ] || { _fail "unicidade" "paths distintos geraram a mesma chave: $_k1"; return 1; }
}

scenario_gap_key_type_fora_do_enum_exit2() {
  capture "$SCRIPT" gap-key --path "a" --type invalido --origin "FR-007"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_gap_key_flags_obrigatorias_ausentes_exit2() {
  capture "$SCRIPT" gap-key --type missing --origin "FR-007"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit (sem --path)" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" gap-key --path "a" --origin "FR-007"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit (sem --type)" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" gap-key --path "a" --type missing
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit (sem --origin)" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- gap-key: conteudo adversarial (SEC-1) — nunca executa ----------

scenario_gap_key_conteudo_adversarial_nao_executa() {
  _marker="$TMPDIR_TEST/should-not-exist-gap-key-marker"
  capture "$SCRIPT" gap-key \
    --path "\$(touch $_marker)\`touch $_marker\`; touch $_marker" \
    --type missing --origin "FR-001"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (path adversarial ainda e string valida), obtido $_CAPTURED_EXIT"; return 1; }
  if [ -e "$_marker" ]; then
    _fail "side-effect" "conteudo adversarial foi executado"
    return 1
  fi
  assert_no_side_effect || return 1
}

# ---------- append-phase: falha sem escrever quando vazia (FR-010) ----------

scenario_append_phase_vazia_falha_sem_escrever() {
  _write_tasks <<'EOF'
# Tasks

## FASE 1 - Primeira
### 1.1 Algo `[A]`
- [x] 1.1.1 feito
EOF
  _before=$(cat "$TMPDIR_TEST/tasks.md")
  : > "$TMPDIR_TEST/empty-phase.md"
  capture "$SCRIPT" append-phase --tasks "$TMPDIR_TEST/tasks.md" --phase-file "$TMPDIR_TEST/empty-phase.md"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  _after=$(cat "$TMPDIR_TEST/tasks.md")
  [ "$_before" = "$_after" ] || { _fail "append-only" "tasks.md foi alterado apesar da guarda FR-010"; return 1; }
}

scenario_append_phase_tasks_ausente_exit1() {
  printf '## FASE 2 - X\n' > "$TMPDIR_TEST/phase.md"
  capture "$SCRIPT" append-phase --tasks "$TMPDIR_TEST/nao-existe.md" --phase-file "$TMPDIR_TEST/phase.md"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_append_phase_phase_file_ausente_exit1() {
  _write_tasks <<'EOF'
## FASE 1 - X
EOF
  capture "$SCRIPT" append-phase --tasks "$TMPDIR_TEST/tasks.md" --phase-file "$TMPDIR_TEST/nao-existe-fase.md"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

# ---------- append-phase: append-only preserva conteudo pre-existente ----------

scenario_append_phase_preserva_conteudo_preexistente_byte_a_byte() {
  _write_tasks <<'EOF'
# Tasks

## FASE 1 - Primeira

### 1.1 Algo `[A]`
- [x] 1.1.1 feito
EOF
  cp "$TMPDIR_TEST/tasks.md" "$TMPDIR_TEST/tasks.md.before"
  cat > "$TMPDIR_TEST/phase.md" <<'EOF'
## FASE 2 - Convergência

### 2.1 Corrigir path ausente `[A]`
- [ ] 2.1.1 implementar path X
<!-- converge-key: aaaaaaaaaaaa -->
EOF
  capture "$SCRIPT" append-phase --tasks "$TMPDIR_TEST/tasks.md" --phase-file "$TMPDIR_TEST/phase.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }

  _before_lines=$(wc -l < "$TMPDIR_TEST/tasks.md.before" | tr -d ' ')
  if ! head -n "$_before_lines" "$TMPDIR_TEST/tasks.md" | diff -q - "$TMPDIR_TEST/tasks.md.before" >/dev/null 2>&1; then
    _fail "append-only" "prefixo do tasks.md nao bate byte-a-byte com o conteudo pre-existente"
    return 1
  fi
  assert_stdout_contains "" || return 1
  grep -q "FASE 1 - Primeira" "$TMPDIR_TEST/tasks.md" || { _fail "preservacao" "FASE 1 sumiu"; return 1; }
  grep -q "FASE 2 - Convergência" "$TMPDIR_TEST/tasks.md" || { _fail "apendado" "FASE 2 nao foi apendada"; return 1; }
}

# ---------- append-phase: conteudo adversarial pre-existente permanece literal (SEC-1, 2.5.6) ----------

scenario_append_phase_conteudo_adversarial_preexistente_permanece_literal() {
  _marker="$TMPDIR_TEST/should-not-exist-append-phase-marker"
  _write_tasks <<EOF
# Tasks

## FASE 1 - Primeira

### 1.1 Tarefa com conteudo adversarial \`[A]\`
- [x] 1.1.1 texto com \$(touch $_marker) e \`touch $_marker\` embutido como dado
EOF
  cat > "$TMPDIR_TEST/phase.md" <<'EOF'
## FASE 2 - Convergência

### 2.1 Nova `[A]`
- [ ] 2.1.1 novo item
<!-- converge-key: cccccccccccc -->
EOF
  capture "$SCRIPT" append-phase --tasks "$TMPDIR_TEST/tasks.md" --phase-file "$TMPDIR_TEST/phase.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  if [ -e "$_marker" ]; then
    _fail "side-effect" "conteudo adversarial pre-existente foi executado durante o append"
    return 1
  fi
  grep -q 'touch' "$TMPDIR_TEST/tasks.md" || { _fail "preservacao" "texto adversarial nao foi preservado literalmente"; return 1; }
}

# ---------- Reuso obrigatorio de next-task-id.sh (tarefa 2.5.5) ----------
# Demonstra o padrao de composicao fim-a-fim: quem monta o phase-file numera
# via next-task-id.sh [REAL] chamado iterativamente CONTRA O PROPRIO
# phase-file em construcao (nunca contra o tasks.md inteiro) — cada chamada
# subsequente ve as tarefas ja escritas e incrementa corretamente.

scenario_reuso_next_task_id_numera_fase_apendada_sequencialmente() {
  [ -x "$NEXT_TASK_ID" ] || { _error "next-task-id.sh ausente/nao executavel" "$NEXT_TASK_ID"; return 2; }
  _write_tasks <<'EOF'
## FASE 1 - Primeira
### 1.1 Algo `[A]`
- [x] 1.1.1 feito
EOF
  _phase_n=$(sh "$SCRIPT" next-phase --tasks "$TMPDIR_TEST/tasks.md")
  [ "$_phase_n" = "2" ] || { _fail "next-phase" "esperado 2, obtido $_phase_n"; return 1; }

  _phase_file="$TMPDIR_TEST/phase-new.md"
  printf '## FASE %s - Convergência\n\n' "$_phase_n" > "$_phase_file"

  _tid1=$(sh "$NEXT_TASK_ID" "$_phase_n" "$_phase_file")
  [ "$_tid1" = "2.1" ] || { _fail "next-task-id 1a chamada" "esperado 2.1, obtido $_tid1"; return 1; }
  printf '### %s Corrigir X `[A]`\n- [ ] %s.1 implementar\n<!-- converge-key: dddddddddddd -->\n\n' \
    "$_tid1" "$_tid1" >> "$_phase_file"

  _tid2=$(sh "$NEXT_TASK_ID" "$_phase_n" "$_phase_file")
  [ "$_tid2" = "2.2" ] || { _fail "next-task-id 2a chamada" "esperado 2.2 (sequencial dentro da fase), obtido $_tid2"; return 1; }
  printf '### %s Revisar Y `[M]`\n- [ ] %s.1 revisar\n<!-- converge-key: eeeeeeeeeeee -->\n' \
    "$_tid2" "$_tid2" >> "$_phase_file"

  capture "$SCRIPT" append-phase --tasks "$TMPDIR_TEST/tasks.md" --phase-file "$_phase_file"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "append-phase" "esperado exit 0, obtido $_CAPTURED_EXIT"; return 1; }
  grep -q '### 2.1 Corrigir X' "$TMPDIR_TEST/tasks.md" || { _fail "numeracao" "2.1 ausente no resultado final"; return 1; }
  grep -q '### 2.2 Revisar Y' "$TMPDIR_TEST/tasks.md" || { _fail "numeracao" "2.2 ausente no resultado final"; return 1; }
}

# ---------- Idempotencia fim-a-fim (SC-003): gap-key + existing-keys + skip ----------
# append-phase em si NAO deduplica (research.md Decision 2: a fronteira de
# idempotencia vive no CHAMADOR). Este scenario exercita o contrato completo:
# 1a convergencia apenda a fase; reconvergencia SEM mudanca de codigo produz
# a MESMA gap-key, que o chamador encontra em existing-keys e por isso NAO
# invoca append-phase de novo -> tasks.md permanece byte-identico.

scenario_idempotencia_fim_a_fim_sem_mudanca_de_codigo_tasks_byte_identico() {
  _write_tasks <<'EOF'
## FASE 1 - Primeira
### 1.1 Algo `[A]`
- [x] 1.1.1 feito
EOF
  _path="scripts/severity.sh"
  _type="missing"
  _origin="FR-006"

  # --- 1a convergencia: gap novo, chave ausente -> apenda ---
  _key=$(sh "$SCRIPT" gap-key --path "$_path" --type "$_type" --origin "$_origin")
  _existing_before=$(sh "$SCRIPT" existing-keys --tasks "$TMPDIR_TEST/tasks.md")
  case "$_existing_before" in
    *"$_key"*) _fail "pre-condicao" "chave ja deveria estar ausente na 1a convergencia"; return 1 ;;
  esac

  _phase_n=$(sh "$SCRIPT" next-phase --tasks "$TMPDIR_TEST/tasks.md")
  _phase_file="$TMPDIR_TEST/phase-1.md"
  printf '## FASE %s - Convergência\n\n### %s.1 Corrigir X `[A]`\n- [ ] %s.1.1 implementar\n<!-- converge-key: %s -->\n' \
    "$_phase_n" "$_phase_n" "$_phase_n" "$_key" > "$_phase_file"
  sh "$SCRIPT" append-phase --tasks "$TMPDIR_TEST/tasks.md" --phase-file "$_phase_file" \
    || { _fail "append-phase 1a rodada" "falhou inesperadamente"; return 1; }

  cp "$TMPDIR_TEST/tasks.md" "$TMPDIR_TEST/tasks.md.after-run1"

  # --- Reconvergencia: MESMO path/type/origin (codigo nao mudou) ---
  _key_rerun=$(sh "$SCRIPT" gap-key --path "$_path" --type "$_type" --origin "$_origin")
  [ "$_key_rerun" = "$_key" ] || { _fail "determinismo entre rodadas" "chaves diferentes: $_key vs $_key_rerun"; return 1; }

  _existing_after=$(sh "$SCRIPT" existing-keys --tasks "$TMPDIR_TEST/tasks.md")
  case "$_existing_after" in
    *"$_key_rerun"*) : ;;
    *) _fail "dedup" "chave deveria estar presente apos a 1a convergencia"; return 1 ;;
  esac

  # Contrato FR-011/FR-012: chave ja existe -> chamador NAO invoca append-phase.
  # (nao ha 2a chamada aqui, por design — e o proprio teste do contrato)

  diff "$TMPDIR_TEST/tasks.md" "$TMPDIR_TEST/tasks.md.after-run1" >/dev/null 2>&1 \
    || { _fail "SC-003" "tasks.md deveria permanecer byte-identico sem nova chamada a append-phase"; return 1; }
}

# ---------- Erros de uso gerais ----------

scenario_sem_subcomando_exit2() {
  capture "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_subcomando_desconhecido_exit2() {
  capture "$SCRIPT" bogus-subcommand
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_help_exit0() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "Uso:" || return 1
}

scenario_next_phase_sem_flag_tasks_exit2() {
  capture "$SCRIPT" next-phase
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

run_all_scenarios
