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

_write_roadmap_valido() {
  _path=$1
  cat > "$_path" <<'EOF'
# Roadmap: projeto foo

**Gerado por**: agente-00c (modo roadmap)
**Atualizado em**: 2026-08-14

Contexto curto do portfolio.

## Ordem sugerida

| # | Feature | Depende de | Descricao (resumo) |
|---|---------|------------|---------------------|
| 1 | `auth-basica` | - | Autenticacao de usuario |
| 2 | `perfil-usuario` | `auth-basica` | Edicao de perfil |

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Permite que o usuario autentique na plataforma.

**Justificativa**: Pre-requisito de toda funcionalidade autenticada.

### 2. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 2
- **depende-de**: `auth-basica`

**Descricao**: Permite editar dados de perfil do usuario.

**Justificativa**: Feature de retencao solicitada pelo dono do produto.
EOF
}

scenario_stages_lista_11_etapas_em_ordem() {
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
converge
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

# tarefa 3.3.2 (contracts/pipeline-stage-machine.md §D1): a insercao de
# `converge` entre execute-task e review-task reflete nos 3 subcomandos
# lineares sem nenhuma linha de codigo adicional (efeito automatico da
# lista, tabela do contrato).
scenario_next_stage_execute_task_aponta_converge() {
  capture "$SCRIPT" next-stage --current execute-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "converge" ] || { _fail "next-stage execute-task" "esperado converge, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_next_stage_converge_aponta_review_task() {
  capture "$SCRIPT" next-stage --current converge
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "review-task" ] || { _fail "next-stage converge" "esperado review-task, obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_prev_stage_review_task_aponta_converge() {
  capture "$SCRIPT" prev-stage --current review-task
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "converge" ] || { _fail "prev-stage review-task" "esperado converge, obtido: $_CAPTURED_STDOUT"; return 1; }
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

# ==== Issue #3: briefing aceita path da hierarquia numerada legada via --projeto-alvo-path ====
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

  # Briefing SO no path legado 01-briefing-discovery -> exit 0 (com PAP)
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

# ---------- detect-completion --stage converge (tarefa 3.2, §D2) ----------
#
# converge-status.sh (delegado por esta etapa) resolve --root via
# path-contains.sh ascendendo a partir do CWD (nao do --path) — precisa
# rodar com CWD DENTRO de um repo sintetico (marcador .git/) que contenha
# o feature-dir, senao a resolucao automatica encontra o .git do PROPRIO
# repo cstk (CWD real dos testes) e rejeita o feature-dir em /tmp como
# "fora da raiz" (F3), mascarando o veredito que o cenario quer exercitar.
# Helpers espelham _cs_quote/_cs_run de tests/test_converge-status.sh.
_pl_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

_pl_run_cwd() {
  _cwd=$1
  shift
  _cmd="cd $(_pl_quote "$_cwd") && $(_pl_quote "$SCRIPT")"
  for _a in "$@"; do
    _cmd="$_cmd $(_pl_quote "$_a")"
  done
  capture env -i PATH="$PATH" HOME="$HOME" sh -c "$_cmd"
}

_pl_make_repo() {
  _repo="$TMPDIR_TEST/repo"
  mkdir -p "$_repo/.git"
  printf '%s\n' "$_repo"
}

scenario_detect_completion_converge_tasks_ausente_exit0() {
  _repo=$(_pl_make_repo)
  _fd="$_repo/docs/specs/feat"
  mkdir -p "$_fd"
  _pl_run_cwd "$_repo" detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_detect_completion_converge_tasks_vazio_exit0() {
  _repo=$(_pl_make_repo)
  _fd="$_repo/docs/specs/feat"
  mkdir -p "$_fd"
  printf 'so prosa, nenhuma tarefa\n' > "$_fd/tasks.md"
  _pl_run_cwd "$_repo" detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_detect_completion_converge_pendente_exit1() {
  _repo=$(_pl_make_repo)
  _fd="$_repo/docs/specs/feat"
  mkdir -p "$_fd"
  printf -- '- [x] 1.1 done\n' > "$_fd/tasks.md"
  _pl_run_cwd "$_repo" detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (nunca convergiu), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_detect_completion_converge_convergida_exit0() {
  _repo=$(_pl_make_repo)
  _fd="$_repo/docs/specs/feat"
  mkdir -p "$_fd"
  printf -- '- [x] 1.1 done\n' > "$_fd/tasks.md"
  _cs="$REPO_ROOT/plugins/cstk/skills/converge/scripts/converge-status.sh"
  capture env -i PATH="$PATH" HOME="$HOME" sh -c \
    "cd $(_pl_quote "$_repo") && $(_pl_quote "$_cs") record --feature-dir $(_pl_quote "$_fd") --outcome clean --provenance gate --actionable 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "setup" "record falhou: $_CAPTURED_STDERR"; return 1; }
  _pl_run_cwd "$_repo" detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_detect_completion_converge_stale_exit1() {
  _repo=$(_pl_make_repo)
  _fd="$_repo/docs/specs/feat"
  mkdir -p "$_fd"
  printf -- '- [x] 1.1 done\n' > "$_fd/tasks.md"
  _cs="$REPO_ROOT/plugins/cstk/skills/converge/scripts/converge-status.sh"
  capture env -i PATH="$PATH" HOME="$HOME" sh -c \
    "cd $(_pl_quote "$_repo") && $(_pl_quote "$_cs") record --feature-dir $(_pl_quote "$_fd") --outcome clean --provenance gate --actionable 0"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "setup" "record falhou: $_CAPTURED_STDERR"; return 1; }
  printf -- '- [x] 1.2 novo\n' >> "$_fd/tasks.md"
  _pl_run_cwd "$_repo" detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (stale), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

# Cenario 14 do quickstart.md (tarefa 3.3.3): distingue skill `converge`
# NAO instalada (degradacao aceitavel, exit 0) de catalogo corrompido —
# skill instalada mas converge-status.sh ausente (fail-closed, exit 1,
# F1). Roda uma COPIA de pipeline.sh fora da arvore do repo (para que a
# resolucao DEV `${0%/*}/../../converge` nao encontre a skill real) com
# HOME isolado (para controlar a resolucao de instalacao
# `${HOME}/.claude/skills/converge`).
_pl_make_fake_catalog() {
  _fake_rt="$TMPDIR_TEST/fake-catalog/agente-00c-runtime/scripts"
  mkdir -p "$_fake_rt"
  cp "$SCRIPT" "$_fake_rt/pipeline.sh"
  cp "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_state-read.sh" "$_fake_rt/_state-read.sh"
  printf '%s\n' "$_fake_rt/pipeline.sh"
}

scenario_detect_completion_converge_skill_nao_instalada_exit0() {
  _fake_pipeline=$(_pl_make_fake_catalog)
  _fake_home="$TMPDIR_TEST/fakehome-none"
  mkdir -p "$_fake_home"
  _fd="$TMPDIR_TEST/feat-nao-instalada"
  mkdir -p "$_fd"
  printf -- '- [x] 1.1 done\n' > "$_fd/tasks.md"
  capture env -i PATH="$PATH" HOME="$_fake_home" sh "$_fake_pipeline" \
    detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "nao instalada" || return 1
}

scenario_detect_completion_converge_catalogo_corrompido_exit1() {
  _fake_pipeline=$(_pl_make_fake_catalog)
  _fake_home="$TMPDIR_TEST/fakehome-corrompido"
  mkdir -p "$_fake_home/.claude/skills/converge/scripts"
  # skill "instalada" (diretorio existe) mas SEM converge-status.sh — o
  # catalogo esta corrompido/incompleto (falta o script deterministico).
  _fd="$TMPDIR_TEST/feat-corrompida"
  mkdir -p "$_fd"
  printf -- '- [x] 1.1 done\n' > "$_fd/tasks.md"
  capture env -i PATH="$PATH" HOME="$_fake_home" sh "$_fake_pipeline" \
    detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (fail-closed), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stderr_contains "corrompido" || return 1
}

scenario_detect_completion_converge_script_nao_executavel_exit1() {
  _fake_pipeline=$(_pl_make_fake_catalog)
  _fake_home="$TMPDIR_TEST/fakehome-perm"
  mkdir -p "$_fake_home/.claude/skills/converge/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$_fake_home/.claude/skills/converge/scripts/converge-status.sh"
  chmod -x "$_fake_home/.claude/skills/converge/scripts/converge-status.sh"
  _fd="$TMPDIR_TEST/feat-perm"
  mkdir -p "$_fd"
  printf -- '- [x] 1.1 done\n' > "$_fd/tasks.md"
  capture env -i PATH="$PATH" HOME="$_fake_home" sh "$_fake_pipeline" \
    detect-completion --feature-dir "$_fd" --stage converge
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1 (fail-closed), obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
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

# ==== --mode (feature roadmap-mode, tasks 2.3/2.4) ====

# 2.3.4: assercao de regressao — stages SEM --mode continua retornando as
# 11 etapas INTACTAS, na mesma ordem (_PL_STAGES_LIST, D1: pipeline-converge
# insere `converge` entre execute-task e review-task; --mode em si NUNCA
# altera a lista dinamicamente).
scenario_stages_sem_mode_permanece_11_etapas_intacta() {
  capture "$SCRIPT" stages
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stages sem --mode exit" "$_CAPTURED_EXIT"; return 1; }
  _expected="briefing
constitution
specify
clarify
plan
checklist
create-tasks
execute-task
converge
review-task
review-features"
  [ "$_CAPTURED_STDOUT" = "$_expected" ] || { _fail "stages sem --mode" "divergente: $_CAPTURED_STDOUT"; return 1; }
}

scenario_stages_mode_default_explicito_igual_omitido() {
  capture "$SCRIPT" stages --mode default
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stages --mode default exit" "$_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "review-features" || return 1
  assert_stdout_contains "specify" || return 1
}

# quickstart.md Cenario 1 passo 3 (SC-003, gate FASE 6 6.3.1): reforca a
# assercao acima com comparacao BYTE-IDENTICA (nao so substring) entre
# `stages` sem --mode e `stages --mode default` — prova que a lista nao
# apenas contem os nomes esperados, mas e a MESMA string na MESMA ordem.
scenario_stages_mode_default_byte_identico_a_sem_mode() {
  capture "$SCRIPT" stages
  _sem_mode="$_CAPTURED_STDOUT"
  capture "$SCRIPT" stages --mode default
  _com_mode_default="$_CAPTURED_STDOUT"
  [ "$_sem_mode" = "$_com_mode_default" ] || {
    _fail "stages vs stages --mode default" "divergente: [$_sem_mode] != [$_com_mode_default]"
    return 1
  }
}

# quickstart.md Cenario 1 passo 2 (SC-003, gate FASE 6 6.3.1): a etapa
# SEGUINTE de constitution na pipeline DEFAULT (sem --mode) continua
# `specify` — prova que o modo roadmap (que resolveria `roadmap` no
# mesmo ponto) nao vazou para o caminho default.
scenario_next_stage_constitution_sem_mode_retorna_specify() {
  capture "$SCRIPT" next-stage --current constitution
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "next-stage --current constitution exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "specify" ] || {
    _fail "next-stage --current constitution" "esperado specify, obtido: $_CAPTURED_STDOUT"
    return 1
  }
}

scenario_stages_mode_roadmap_lista_escopada() {
  capture "$SCRIPT" stages --mode roadmap
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "stages --mode roadmap exit" "$_CAPTURED_EXIT"; return 1; }
  _expected="briefing
constitution
roadmap"
  [ "$_CAPTURED_STDOUT" = "$_expected" ] || { _fail "stages --mode roadmap" "divergente: $_CAPTURED_STDOUT"; return 1; }
}

scenario_stages_mode_invalido_exit2() {
  capture "$SCRIPT" stages --mode bogus
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "stages --mode bogus exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_next_stage_mode_roadmap_avanca_e_termina_vazio() {
  capture "$SCRIPT" next-stage --current briefing --mode roadmap
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "next-stage briefing --mode roadmap exit" "$_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "constitution" ] || { _fail "next-stage briefing --mode roadmap" "obtido '$_CAPTURED_STDOUT'"; return 1; }

  capture "$SCRIPT" next-stage --current constitution --mode roadmap
  [ "$_CAPTURED_STDOUT" = "roadmap" ] || { _fail "next-stage constitution --mode roadmap" "obtido '$_CAPTURED_STDOUT'"; return 1; }

  # Terminalidade contratada (contracts/cli-roadmap-mode.md §3): stdout
  # vazio + exit 0 na ultima etapa do modo roadmap.
  capture "$SCRIPT" next-stage --current roadmap --mode roadmap
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "next-stage roadmap --mode roadmap exit" "$_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "next-stage roadmap --mode roadmap deveria ser vazio" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

scenario_next_stage_mode_roadmap_etapa_fora_da_lista_falha() {
  # 'specify' nao pertence a lista escopada do modo roadmap.
  capture "$SCRIPT" next-stage --current specify --mode roadmap
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "next-stage specify --mode roadmap deveria falhar" "exit=0"; return 1; }
}

scenario_prev_stage_mode_roadmap_volta_linear() {
  capture "$SCRIPT" prev-stage --current roadmap --mode roadmap
  [ "$_CAPTURED_STDOUT" = "constitution" ] || { _fail "prev-stage roadmap --mode roadmap" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  capture "$SCRIPT" prev-stage --current briefing --mode roadmap
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "prev-stage briefing --mode roadmap exit" "$_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "prev-stage briefing --mode roadmap deveria ser vazio" "obtido '$_CAPTURED_STDOUT'"; return 1; }
}

# 2.4.4: assercao de regressao OBRIGATORIA — --stage roadmap SEM
# --mode roadmap continua invalido (exit 2), mesmo com o artefato presente.
scenario_detect_completion_stage_roadmap_sem_mode_continua_invalido() {
  _fd="$TMPDIR_TEST/feat-roadmap-sem-mode"
  _pap="$TMPDIR_TEST/pap-roadmap-sem-mode"
  mkdir -p "$_fd" "$_pap/docs"
  _write_roadmap_valido "$_pap/docs/roadmap.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "--stage roadmap sem --mode roadmap" "esperado exit 2, obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_detect_completion_mode_roadmap_invalido_exit2() {
  _fd="$TMPDIR_TEST/feat-roadmap-mode-invalido"
  mkdir -p "$_fd"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode bogus
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "--mode bogus" "esperado exit 2, obtido $_CAPTURED_EXIT"; return 1; }
}

# 2.4.1/2.4.2: --stage roadmap COM --mode roadmap localiza docs/roadmap.md
# via PAP (project-level, como briefing/constitution) e valida a estrutura
# completa (15 regras — task 3.1; ver _pl_validate_roadmap).
scenario_detect_completion_stage_roadmap_com_mode_localiza_via_pap() {
  _fd="$TMPDIR_TEST/feat-roadmap-com-mode"
  _pap="$TMPDIR_TEST/pap-roadmap-com-mode"
  mkdir -p "$_fd" "$_pap/docs"

  # Ausente -> exit 1.
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "sem roadmap.md" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }

  # Presente e valido -> exit 0.
  _write_roadmap_valido "$_pap/docs/roadmap.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "com roadmap.md valido" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
}

scenario_detect_completion_stage_roadmap_sem_header_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-sem-header"
  _pap="$TMPDIR_TEST/pap-roadmap-sem-header"
  mkdir -p "$_fd" "$_pap/docs"
  printf 'algum texto sem header valido\n\n## Features\n\n### 1. foo\n' > "$_pap/docs/roadmap.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "roadmap sem header" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "header" || return 1
}

scenario_detect_completion_stage_roadmap_sem_features_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-sem-features"
  _pap="$TMPDIR_TEST/pap-roadmap-sem-features"
  mkdir -p "$_fd" "$_pap/docs"
  printf '# Roadmap: foo\n\nsem secao features\n' > "$_pap/docs/roadmap.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "roadmap sem Features" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "Features" || return 1
}

scenario_detect_completion_stage_roadmap_sem_entrada_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-sem-entrada"
  _pap="$TMPDIR_TEST/pap-roadmap-sem-entrada"
  mkdir -p "$_fd" "$_pap/docs"
  printf '# Roadmap: foo\n\n## Features\n\nnenhuma entrada ainda\n' > "$_pap/docs/roadmap.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "roadmap sem entrada" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== 3.1: validador estrutural COMPLETO — 1 fixture invalida por regra ====
# Regras 1-3 ja cobertas acima (sem_header/sem_features/sem_entrada). A
# regra 12 (aciclicidade) nao tem fixture dedicada: e coberta por
# construcao pela regra 11 (comentario em _pl_validate_roadmap explica por
# que nao ha estado alcancavel em que 11 passa e 12 falha).

scenario_roadmap_regra4_sem_metadado_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r4"
  _pap="$TMPDIR_TEST/pap-roadmap-r4"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

Descricao solta, sem as 3 linhas de metadado.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 4" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 4" || return 1
}

scenario_roadmap_regra5_metadado_diverge_heading_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r5"
  _pap="$TMPDIR_TEST/pap-roadmap-r5"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

- **short-name**: `outro-nome`
- **ordem**: 1
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 5" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 5" || return 1
}

scenario_roadmap_regra6_short_name_duplicado_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r6"
  _pap="$TMPDIR_TEST/pap-roadmap-r6"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.

### 2. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 2
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 6" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 6" || return 1
}

scenario_roadmap_regra7_dependencia_inexistente_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r7"
  _pap="$TMPDIR_TEST/pap-roadmap-r7"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: `fantasma`

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 7" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 7" || return 1
}

scenario_roadmap_regra8_placeholder_residual_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r8"
  _pap="$TMPDIR_TEST/pap-roadmap-r8"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: [TBD]

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 8" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 8" || return 1
}

scenario_roadmap_regra9_short_name_muito_longo_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r9"
  _pap="$TMPDIR_TEST/pap-roadmap-r9"
  mkdir -p "$_fd" "$_pap/docs"
  _long=$(printf 'a%.0s' $(seq 1 70))
  cat > "$_pap/docs/roadmap.md" <<EOF
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. $_long

- **short-name**: \`$_long\`
- **ordem**: 1
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 9" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 9" || return 1
}

scenario_roadmap_regra10_ordem_duplicada_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r10"
  _pap="$TMPDIR_TEST/pap-roadmap-r10"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.

### 1. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 1
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 10" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 10" || return 1
}

scenario_roadmap_regra11_precedencia_violada_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r11"
  _pap="$TMPDIR_TEST/pap-roadmap-r11"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: `perfil-usuario`

**Descricao**: texto.

**Justificativa**: texto.

### 2. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 2
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 11" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 11" || return 1
}

scenario_roadmap_regra13_limite_50_entradas_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r13"
  _pap="$TMPDIR_TEST/pap-roadmap-r13"
  mkdir -p "$_fd" "$_pap/docs"
  {
    printf '# Roadmap: foo\n\n**Gerado por**: agente-00c\n**Atualizado em**: 2026-08-14\n\n## Ordem sugerida\n\n| # | Feature |\n|---|---------|\n\n## Features\n\n'
    _n=1
    while [ "$_n" -le 51 ]; do
      printf '### %d. feature-%d\n\n- **short-name**: `feature-%d`\n- **ordem**: %d\n- **depende-de**: -\n\n**Descricao**: texto.\n\n**Justificativa**: texto.\n\n' \
        "$_n" "$_n" "$_n" "$_n"
      _n=$((_n + 1))
    done
  } > "$_pap/docs/roadmap.md"
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 13" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 13" || return 1
}

scenario_roadmap_regra14_sem_provenencia_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r14"
  _pap="$TMPDIR_TEST/pap-roadmap-r14"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

## Ordem sugerida

| # | Feature |
|---|---------|

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 14" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 14" || return 1
}

scenario_roadmap_regra15_sem_ordem_sugerida_falha() {
  _fd="$TMPDIR_TEST/feat-roadmap-r15"
  _pap="$TMPDIR_TEST/pap-roadmap-r15"
  mkdir -p "$_fd" "$_pap/docs"
  cat > "$_pap/docs/roadmap.md" <<'EOF'
# Roadmap: foo

**Gerado por**: agente-00c
**Atualizado em**: 2026-08-14

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: texto.

**Justificativa**: texto.
EOF
  capture "$SCRIPT" detect-completion --feature-dir "$_fd" --stage roadmap --mode roadmap --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "regra 15" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "regra 15" || return 1
}

run_all_scenarios
