#!/bin/sh
# test_pipeline.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/pipeline.sh"

# Helpers para gerar artefatos validos minimos (estruturas que o pipeline
# detect-completion aceita).
_write_briefing_valido() {
  _path=$1
  cat > "$_path" <<'EOF'
# Project Briefing: foo

## 1. Visao e Proposito
xx
## 2. Usuarios e Stakeholders
yy
## 3. Escopo
zz
## 4. Prioridades
aa
## 5. Restricoes
bb
EOF
}

_write_tasks_valido() {
  _path=$1
  cat > "$_path" <<'EOF'
# Tarefas Foo - Backlog

## FASE 1 - Fundacao
### 1.1 Setup `[C]`
- [ ] 1.1.1 Criar projeto

## Matriz de Dependencias
```mermaid
flowchart TD
F1
```

## Resumo Quantitativo
| Fase | T |

## Escopo Coberto
| 1 | ... |

## Escopo Excluido
| 1 | ... |
EOF
}

scenario_stages_lista_10_etapas_em_ordem() {
  capture "$SCRIPT" stages
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stages exit" "$_CAPTURED_EXIT"; return 1; }
  _expected="briefing
constitution
specify
clarify
plan
checklist
create-tasks
execute-task
review-task
review-features"
  if [ "$_CAPTURED_STDOUT" != "$_expected" ]; then
    _fail "stages output" "ordem ou conteudo divergente:
got=
$_CAPTURED_STDOUT
expected=
$_expected"
    return 1
  fi
}

scenario_next_stage_avanca_linear() {
  capture "$SCRIPT" next-stage --current briefing
  assert_stdout_contains "constitution" || return 1
  capture "$SCRIPT" next-stage --current plan
  assert_stdout_contains "checklist" || return 1
}

scenario_next_stage_na_ultima_imprime_vazio() {
  capture "$SCRIPT" next-stage --current review-features
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" ""; return 1; }
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "next na ultima" "esperado vazio, obtido: $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_prev_stage_volta_linear() {
  capture "$SCRIPT" prev-stage --current specify
  assert_stdout_contains "constitution" || return 1
}

scenario_prev_stage_na_primeira_imprime_vazio() {
  capture "$SCRIPT" prev-stage --current briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" ""; return 1; }
  if [ -n "$_CAPTURED_STDOUT" ]; then
    _fail "prev na primeira" "esperado vazio, obtido: $_CAPTURED_STDOUT"
    return 1
  fi
}

scenario_etapa_invalida_falha() {
  capture "$SCRIPT" next-stage --current xyz-fake
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "etapa invalida" "esperado != 0"
    return 1
  fi
  assert_stderr_contains "etapa desconhecida" || return 1
}

scenario_detect_completion_briefing() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "no briefing.md" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  _write_briefing_valido "$_fd/briefing.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "with briefing.md valido" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

# ==== Issue #3: briefing aceita path do /initialize-docs via --projeto-alvo-path ====
scenario_detect_completion_briefing_aceita_path_initialize_docs() {
  _fd="$TMPDIR_TEST/feat"
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_fd" "$_pap/docs/01-briefing-discovery"

  # Sem briefing em nenhum lugar -> exit 1
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing \
    --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "sem briefing" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  }

  # Briefing SO no path do /initialize-docs -> exit 0 (com PAP)
  _write_briefing_valido "$_pap/docs/01-briefing-discovery/briefing.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing \
    --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "briefing em PAP" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  }

  # Sem --projeto-alvo-path, ainda exige briefing.md no feature-dir
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing
  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "sem PAP, briefing.md fora do FD" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  }
}

# ==== Briefing canonico em docs/briefing.md (legado 01-briefing-discovery preservado) ====
scenario_detect_completion_briefing_aceita_path_canonico_docs() {
  _fd="$TMPDIR_TEST/feat-canon"
  _pap="$TMPDIR_TEST/pap-canon"
  mkdir -p "$_fd" "$_pap/docs"

  # Briefing SO em docs/briefing.md (canonico) -> exit 0 (com PAP)
  _write_briefing_valido "$_pap/docs/briefing.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing \
    --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "briefing canonico em PAP" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  }

  # Precedencia: canonico INVALIDO vence o legado valido -> exit 1
  # (prova que docs/briefing.md e checado antes do path legado)
  mkdir -p "$_pap/docs/01-briefing-discovery"
  _write_briefing_valido "$_pap/docs/01-briefing-discovery/briefing.md"
  printf '# so header, sem secoes\n' > "$_pap/docs/briefing.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing \
    --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "precedencia canonico sobre legado" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  }

  # Canonico valido + legado valido -> exit 0 (canonico usado)
  _write_briefing_valido "$_pap/docs/briefing.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing \
    --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "canonico+legado validos" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  }
}

# ==== Issue #3: constitution aceita docs/constitution.md via --projeto-alvo-path ====
scenario_detect_completion_constitution_aceita_path_initialize_docs() {
  _fd="$TMPDIR_TEST/feat"
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_fd" "$_pap/docs"

  # Sem constitution -> exit 1
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage constitution \
    --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || {
    _fail "sem constitution" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  }

  # Constitution em docs/constitution.md (path da skill constitution) -> exit 0
  printf '# constitution\n' > "$_pap/docs/constitution.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage constitution \
    --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "constitution em PAP" "esperado 0, obtido $_CAPTURED_EXIT"
    return 1
  }
}

scenario_detect_completion_checklist_requer_md_dentro() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd/checklists"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage checklist
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "checklists/ vazia" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  printf 'x\n' > "$_fd/checklists/api.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage checklist
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "com .md em checklists" "$_CAPTURED_EXIT"; return 1; }
}

scenario_detect_completion_execute_task_requer_x_em_tasks() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  printf '# tasks\n- [ ] foo\n' > "$_fd/tasks.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage execute-task
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "tasks sem [x]" "esperado 1"
    return 1
  fi
  printf '# tasks\n- [x] foo\n' > "$_fd/tasks.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage execute-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "tasks com [x]" "$_CAPTURED_EXIT"; return 1; }
}

scenario_detect_completion_review_sempre_passa() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage review-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "review-task" "$_CAPTURED_EXIT"; return 1; }
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage review-features
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "review-features" "$_CAPTURED_EXIT"; return 1; }
}

scenario_skill_conflict_local_vence() {
  _pap="$TMPDIR_TEST/proj"
  mkdir -p "$_pap/.claude/skills/clarify"
  # Para nao depender de ~/.claude/skills/clarify real, isolamos HOME
  _fakehome="$TMPDIR_TEST/fakehome"
  mkdir -p "$_fakehome/.claude/skills/clarify"
  capture env HOME="$_fakehome" "$SCRIPT" skill-conflict --skill clarify --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT; $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status: conflict" || return 1
  assert_stdout_contains "resolution: local-wins" || return 1
}

scenario_skill_conflict_so_local() {
  _pap="$TMPDIR_TEST/proj"
  mkdir -p "$_pap/.claude/skills/skl-x"
  _fakehome="$TMPDIR_TEST/fakehome"
  mkdir -p "$_fakehome/.claude"
  capture env HOME="$_fakehome" "$SCRIPT" skill-conflict --skill skl-x --projeto-alvo-path "$_pap"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "status: only-local" || return 1
}

scenario_skill_conflict_so_global() {
  _pap="$TMPDIR_TEST/proj"
  mkdir -p "$_pap/.claude/skills"
  _fakehome="$TMPDIR_TEST/fakehome"
  mkdir -p "$_fakehome/.claude/skills/skl-y"
  capture env HOME="$_fakehome" "$SCRIPT" skill-conflict --skill skl-y --projeto-alvo-path "$_pap"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "status: only-global" || return 1
}

scenario_skill_conflict_nenhuma_exit_3() {
  _pap="$TMPDIR_TEST/proj"
  mkdir -p "$_pap/.claude/skills"
  _fakehome="$TMPDIR_TEST/fakehome"
  mkdir -p "$_fakehome/.claude"
  capture env HOME="$_fakehome" "$SCRIPT" skill-conflict --skill skl-z --projeto-alvo-path "$_pap"
  if [ "$_CAPTURED_EXIT" != 3 ]; then
    _fail "exit" "esperado 3, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "status: not-found" || return 1
}

# ==== Validacao estrutural de briefing (defesa contra briefing.md vazio) ====
scenario_briefing_sem_header_falha() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  printf '## Visao\nxx\n## Usuarios\nyy\n## Escopo\nzz\n## Stack\naa\n' > "$_fd/briefing.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1 (sem header), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "sem header" || return 1
}

scenario_briefing_poucas_secoes_falha() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  cat > "$_fd/briefing.md" <<'EOF'
# Project Briefing
## Visao
xx
## Usuarios
yy
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage briefing
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1 (apenas 2 secoes), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "secoes nucleares" || return 1
}

# ==== Validacao estrutural de tasks (defesa contra tasks.md fora-de-padrao) ====
scenario_tasks_sem_legenda_C_A_M_falha() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  # tasks.md com P0/P1/P2/P3 em vez de [C]/[A]/[M] (caso real da exec rolledback)
  cat > "$_fd/tasks.md" <<'EOF'
# Tasks: Iniciacao
## FASE 1 - Foo
### T1.1 [P0] Test
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage create-tasks
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1 (sem legendas), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "criticidade no padrao" || return 1
}

scenario_tasks_sem_matriz_dependencias_falha() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  cat > "$_fd/tasks.md" <<'EOF'
# Tarefas Foo
## FASE 1 - Foo
### 1.1 Test `[C]`
- [ ] 1.1.1 X

## Resumo Quantitativo
| Fase | T |

## Escopo Coberto
| 1 | ... |

## Escopo Excluido
| 1 | ... |
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage create-tasks
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1 (sem matriz), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "Matriz de Dependencias" || return 1
}

scenario_tasks_completo_passa() {
  _fd="$TMPDIR_TEST/feat"
  mkdir -p "$_fd"
  _write_tasks_valido "$_fd/tasks.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage create-tasks
  if [ "$_CAPTURED_EXIT" != 0 ]; then
    _fail "exit" "esperado 0 (template valido), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  fi
}

# ==== constitution-conflict (4 cenarios — defesa contra dec-004 rolledback) ====
scenario_constitution_conflict_none_exists() {
  _pap="$TMPDIR_TEST/proj"
  _fd="$_pap/docs/specs/foo"
  mkdir -p "$_fd" "$_pap/docs"
  capture "$SCRIPT" constitution-conflict --projeto-alvo-path "$_pap" --feature-dir "$_fd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "status: none-exists" || return 1
}

scenario_constitution_conflict_pre_skill_alert() {
  _pap="$TMPDIR_TEST/proj"
  _fd="$_pap/docs/specs/foo"
  mkdir -p "$_fd" "$_pap/docs"
  echo "# Constitution Global v1.0.0" > "$_pap/docs/constitution.md"
  capture "$SCRIPT" constitution-conflict --projeto-alvo-path "$_pap" --feature-dir "$_fd"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2 (alerta pre-skill), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stdout_contains "status: pre-skill-alert" || return 1
  assert_stdout_contains "atualizar-global" || return 1
  assert_stdout_contains "criar-delta-com-sync-impact" || return 1
}

scenario_constitution_conflict_conflict_silencioso() {
  _pap="$TMPDIR_TEST/proj"
  _fd="$_pap/docs/specs/foo"
  mkdir -p "$_fd" "$_pap/docs"
  echo "# Constitution Global" > "$_pap/docs/constitution.md"
  # Feature constitution SEM referencia a raiz (caso real do dec-004)
  echo "# Feature Constitution" > "$_fd/constitution.md"
  capture "$SCRIPT" constitution-conflict --projeto-alvo-path "$_pap" --feature-dir "$_fd"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1 (conflito), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "status: conflict" || return 1
  assert_stderr_contains "Predecessor" || return 1
}

scenario_constitution_conflict_coordenado() {
  _pap="$TMPDIR_TEST/proj"
  _fd="$_pap/docs/specs/foo"
  mkdir -p "$_fd" "$_pap/docs"
  echo "# Constitution Global v1.0.0" > "$_pap/docs/constitution.md"
  cat > "$_fd/constitution.md" <<'EOF'
# Feature Constitution
**Predecessor**: docs/constitution.md v1.0.0
EOF
  capture "$SCRIPT" constitution-conflict --projeto-alvo-path "$_pap" --feature-dir "$_fd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (coordenado), obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "status: coordinated" || return 1
}

# ==== detect-completion constitution bloqueia feature-delta silencioso ====
scenario_detect_completion_constitution_bloqueia_delta_sem_predecessor() {
  _fd="$TMPDIR_TEST/feat"
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_fd" "$_pap/docs"
  echo "# Constitution Global" > "$_pap/docs/constitution.md"
  echo "# Feature Constitution" > "$_fd/constitution.md"  # sem Predecessor
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage constitution --projeto-alvo-path "$_pap"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1 (feature sem Predecessor), obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "nao referencia a global" || return 1
}

scenario_detect_completion_constitution_aceita_delta_com_predecessor() {
  _fd="$TMPDIR_TEST/feat"
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_fd" "$_pap/docs"
  echo "# Constitution Global v1.0.0" > "$_pap/docs/constitution.md"
  cat > "$_fd/constitution.md" <<'EOF'
# Feature Constitution

**Predecessor**: docs/constitution.md v1.0.0
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage constitution --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

# --- require-blockade-resolved (regressao do bypass dec-004) -----------

_RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
_SD="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh"
_BL="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/bloqueios.sh"

_init_preflight_state() {
  # Cria state.json + registra decisao pre-flight (score=0) com as 3
  # opcoes canonicas. Retorna o id da decisao em $_CAPTURED_STDOUT.
  # HOME sandbox SEM config global: backend JSON deterministico mesmo em
  # hosts com `state_backend=sqlite` (state-db-runtime-parity 2.1.8).
  _ips_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_ips_home"
  capture env HOME="$_ips_home" "$_RW" init --state-dir "$1" \
    --execucao-id "exec-test-preflight" --projeto-alvo-path "/tmp/p" --descricao "POC preflight"
  capture "$_SD" register --state-dir "$1" \
    --agente "orquestrador-00c" --etapa "constitution" \
    --contexto "Detectada constitution global; alerta pre-skill exit=2" \
    --opcoes '["atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report","abortar-feature-sem-principios-proprios"]' \
    --escolha "pause-humano" \
    --justificativa "Exit=2 detectado, registrando para BloqueioHumano" \
    --score 0
}

scenario_require_blockade_etapa_nao_constitution_passa() {
  # Para etapas que ainda nao tem enforcement, retorna exit 0.
  _sd="$TMPDIR_TEST/state"
  capture "$_RW" init --state-dir "$_sd" \
    --execucao-id "exec-x" --projeto-alvo-path "/tmp/p" --descricao "x"
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa briefing
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "etapa nao enforcada" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "not-enforced" || return 1
}

scenario_require_blockade_sem_decisao_preflight_falha() {
  # Sem nenhuma decisao com as 3 opcoes canonicas, exit 1.
  _sd="$TMPDIR_TEST/state"
  capture "$_RW" init --state-dir "$_sd" \
    --execucao-id "exec-x" --projeto-alvo-path "/tmp/p" --descricao "x"
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "esperado exit 1" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "missing-preflight-decision" || return 1
}

scenario_require_blockade_decisao_sem_bloqueio_falha() {
  # Decisao pre-flight existe mas BloqueioHumano nao foi criado.
  _sd="$TMPDIR_TEST/state"
  _init_preflight_state "$_sd"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "init+register" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "esperado exit 1" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "missing-blockade" || return 1
}

scenario_require_blockade_aguardando_falha() {
  # Bloqueio criado mas ainda nao respondido = exit 1.
  _sd="$TMPDIR_TEST/state"
  _init_preflight_state "$_sd"
  _dec_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" register --state-dir "$_sd" --decisao-id "$_dec_id" \
    --pergunta "Detectei docs/constitution.md global v1.1.0. Como tratar?" \
    --contexto-para-resposta "ver paths X e Y" \
    --opcoes-recomendadas '["atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report","abortar-feature-sem-principios-proprios"]'
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "bloqueio register" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "esperado exit 1" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "blockade-pending" || return 1
}

scenario_require_blockade_respondido_criar_delta_passa() {
  # Bloqueio respondido com criar-feature-delta = exit 0.
  _sd="$TMPDIR_TEST/state"
  _init_preflight_state "$_sd"
  _dec_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" register --state-dir "$_sd" --decisao-id "$_dec_id" \
    --pergunta "Detectei docs/constitution.md global v1.1.0. Como tratar?" \
    --contexto-para-resposta "ver paths"
  _bl_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" respond --state-dir "$_sd" --block-id "$_bl_id" \
    --resposta "criar-feature-delta-com-sync-impact-report"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "respond" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "esperado exit 0" "exit=$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status: resolved" || return 1
  assert_stdout_contains "criar-feature-delta-com-sync-impact-report" || return 1
}

scenario_require_blockade_respondido_atualizar_global_passa() {
  # Bloqueio respondido com atualizar-global = exit 0.
  _sd="$TMPDIR_TEST/state"
  _init_preflight_state "$_sd"
  _dec_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" register --state-dir "$_sd" --decisao-id "$_dec_id" \
    --pergunta "Detectei docs/constitution.md global v1.1.0. Como tratar?" \
    --contexto-para-resposta "ver paths"
  _bl_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" respond --state-dir "$_sd" --block-id "$_bl_id" \
    --resposta "atualizar-global-via-bump-SemVer"
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "esperado exit 0" "exit=$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "status: resolved" || return 1
}

scenario_require_blockade_respondido_abortar_falha() {
  # Bloqueio respondido com abortar = exit 1 (skill nao deve rodar).
  _sd="$TMPDIR_TEST/state"
  _init_preflight_state "$_sd"
  _dec_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" register --state-dir "$_sd" --decisao-id "$_dec_id" \
    --pergunta "Detectei docs/constitution.md global v1.1.0. Como tratar?" \
    --contexto-para-resposta "ver paths"
  _bl_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" respond --state-dir "$_sd" --block-id "$_bl_id" \
    --resposta "abortar-feature-sem-principios-proprios"
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "esperado exit 1 (abortar)" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "blockade-resolved-abort" || return 1
}

scenario_require_blockade_resposta_invalida_falha() {
  # Bloqueio respondido com string nao-canonica = exit 1.
  _sd="$TMPDIR_TEST/state"
  _init_preflight_state "$_sd"
  _dec_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" register --state-dir "$_sd" --decisao-id "$_dec_id" \
    --pergunta "Detectei docs/constitution.md global v1.1.0. Como tratar?" \
    --contexto-para-resposta "ver paths"
  _bl_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" respond --state-dir "$_sd" --block-id "$_bl_id" \
    --resposta "sim por favor faca delta"
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "esperado exit 1 (resposta invalida)" "exit=$_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "blockade-invalid-response" || return 1
}

# --- back-compat: state.json LEGADO em pt-BR (reader-fallback EN // pt) ------
# Prova que require-blockade-resolved ainda LE um state.json escrito no schema
# antigo (pre-migracao: .decisoes/.opcoes_consideradas/.bloqueios_humanos/
# .decisao_id/.resposta_humana). Os helpers ja escrevem EN, entao montamos o
# fixture pt-BR na mao.
scenario_require_blockade_legacy_pt_state_fallback() {
  _sd="$TMPDIR_TEST/legacy-state"
  mkdir -p "$_sd"
  cat > "$_sd/state.json" <<'EOF'
{
  "schema_version": 6,
  "execucao": { "id": "exec-legacy", "status": "em_andamento" },
  "decisoes": [
    {
      "id": "dec-001",
      "etapa": "constitution",
      "opcoes_consideradas": [
        "atualizar-global-via-bump-SemVer",
        "criar-feature-delta-com-sync-impact-report",
        "abortar-feature-sem-principios-proprios"
      ],
      "escolha": "pause-humano"
    }
  ],
  "bloqueios_humanos": [
    {
      "id": "blk-001",
      "decisao_id": "dec-001",
      "status": "respondido",
      "resposta_humana": "criar-feature-delta-com-sync-impact-report"
    }
  ]
}
EOF
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 0 ] || {
    _fail "legacy pt-BR state" "esperado exit 0 (reader-fallback), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"
    return 1
  }
  assert_stdout_contains "status: resolved" || return 1
  assert_stdout_contains "criar-feature-delta-com-sync-impact-report" || return 1
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.1 / FR-002 / SC-003) ====
# Fixture por CHK032: decisao pre-flight + bloqueio RESPONDIDO via primitivas.

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_init_preflight_state_sqlite() {
  _ipss_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_ipss_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_ipss_home/.claude/cstk/config"
  env HOME="$_ipss_home" "$_RW" init --state-dir "$1" \
    --execucao-id "exec-pl-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC preflight sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
  capture "$_SD" register --state-dir "$1" \
    --agente "orquestrador-00c" --etapa "constitution" \
    --contexto "Detectada constitution global; alerta pre-skill exit=2" \
    --opcoes '["atualizar-global-via-bump-SemVer","criar-feature-delta-com-sync-impact-report","abortar-feature-sem-principios-proprios"]' \
    --escolha "pause-humano" \
    --justificativa "Exit=2 detectado, registrando para BloqueioHumano" \
    --score 0
}

scenario_sqlite_require_blockade_respondido_criar_delta_passa() {
  _sqlite3_adequate || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _init_preflight_state_sqlite "$_sd" || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  _dec_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" register --state-dir "$_sd" --decisao-id "$_dec_id" \
    --pergunta "Detectei docs/constitution.md global v1.1.0. Como tratar?" \
    --contexto-para-resposta "ver paths"
  _bl_id="$(printf '%s' "$_CAPTURED_STDOUT" | tail -1)"
  capture "$_BL" respond --state-dir "$_sd" --block-id "$_bl_id" \
    --resposta "criar-feature-delta-com-sync-impact-report"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "respond sqlite" "$_CAPTURED_STDERR"; return 1; }
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "esperado exit 0" "exit=$_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  # Veredito equivalente ao JSON (SC-003).
  assert_stdout_contains "status: resolved" || return 1
  assert_stdout_contains "criar-feature-delta-com-sync-impact-report" || return 1
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
}

scenario_sqlite_require_blockade_sem_decisao_falha_e_sem_mirror() {
  _sqlite3_adequate || { printf '# skip: sqlite3 indisponivel\n'; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"
  _ipsq_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_ipsq_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_ipsq_home/.claude/cstk/config"
  env HOME="$_ipsq_home" "$_RW" init --state-dir "$_sd" \
    --execucao-id "exec-pl-sqlite2" --projeto-alvo-path "/tmp/p" \
    --descricao "POC preflight sqlite" >/dev/null 2>&1
  [ -f "$_sd/state.db" ] || { _fail "fixture sqlite" "init nao gerou state.db"; return 1; }
  capture "$SCRIPT" require-blockade-resolved --state-dir "$_sd" --etapa constitution
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "sem decisao preflight sqlite" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
  assert_stderr_contains "missing-preflight-decision" || return 1
  # Anti-mirror (FR-003).
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "leitura criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

run_all_scenarios
