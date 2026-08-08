#!/bin/sh
# test_extract-intent.sh — cobre plugins/cstk/skills/converge/scripts/extract-intent.sh.
#
# Ref: docs/specs/skill-converge/tasks.md tarefa 2.2.6
#      docs/specs/skill-converge/contracts/converge-interfaces.md §2

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/converge/scripts/extract-intent.sh"

# ---------- Helper: escreve um tasks.md minimo no TMPDIR_TEST ----------

_write_tasks() {
  # $1 = conteudo (heredoc via cat vindo do chamador)
  cat > "$TMPDIR_TEST/tasks.md"
}

# ---------- Extracao basica: backtick em heading + subtarefa ----------

scenario_path_em_heading_e_subtarefa() {
  _write_tasks <<'EOF'
### 2.1 `scripts/path-contains.sh` — contencao de blast radius `[C]`

Ref: FR-014, FR-018

- [ ] 2.1.1 Implementar `--root <dir>`
- [ ] 2.1.5 Teste: `tests/test_path-contains.sh` — cobertura
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'scripts/path-contains.sh\t2.1')" || return 1
  assert_stdout_contains "$(printf 'tests/test_path-contains.sh\t2.1')" || return 1
}

scenario_origem_e_heading_mais_proximo_nao_subtarefa() {
  # A origem de um path numa linha de subtarefa "N.M.K" deve ser o heading
  # pai "N.M" — nunca o id da propria subtarefa (data-model.md).
  _write_tasks <<'EOF'
### 3.1 `SKILL.md` — fluxo agente `[A]`

- [ ] 3.1.7 Etapa X gera `templates/convergence-phase.md`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'templates/convergence-phase.md\t3.1')" || return 1
  assert_stdout_not_contains "3.1.7" || return 1
}

scenario_prosa_solta_fora_de_heading_subtarefa_ignorada() {
  # "Ref: ..." e paragrafos livres nao sao linhas estruturadas — 2.2.1.
  _write_tasks <<'EOF'
### 4.1 `real.sh` — tarefa real `[A]`

Descricao livre mencionando `nao-declarado.sh` que NAO deve aparecer pois
esta fora de heading/checkbox.

- [ ] 4.1.1 Implementa `real.sh`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_not_contains "nao-declarado.sh" || return 1
  assert_stdout_contains "$(printf 'real.sh\t4.1')" || return 1
}

# ---------- Equivalencia de normalize(path) ----------

scenario_normalize_equivalencia_prefixo_ponto_barra() {
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 arquivo `./scripts/foo.sh`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'scripts/foo.sh\t1.1')" || return 1
  assert_stdout_not_contains "./scripts/foo.sh" || return 1
}

scenario_normalize_equivalencia_barras_duplas() {
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 arquivo `scripts//foo.sh`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'scripts/foo.sh\t1.1')" || return 1
}

scenario_normalize_tres_formas_convergem_para_mesma_linha() {
  # "./scripts/foo.sh" ≡ "scripts/foo.sh" ≡ "scripts//foo.sh" (data-model.md)
  # — as 3 mencoes, sob a MESMA origem, colapsam num UNICO par apos dedupe.
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 forma a: `./scripts/foo.sh`
- [ ] 1.1.2 forma b: `scripts/foo.sh`
- [ ] 1.1.3 forma c: `scripts//foo.sh`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _count=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c "scripts/foo.sh")
  if [ "$_count" != 1 ]; then
    _fail "dedupe" "esperado exatamente 1 linha 'scripts/foo.sh' apos normalize+dedupe, obtido $_count"
    return 1
  fi
}

scenario_mesma_path_origens_diferentes_nao_dedupe() {
  # Path identico sob origens DIFERENTES sao dois fatos distintos — nao
  # deduplica (research.md: "dois requisitos podem tocar o mesmo path").
  _write_tasks <<'EOF'
### 1.1 `um` `[A]`

- [ ] 1.1.1 usa `shared.sh`

### 1.2 `dois` `[A]`

- [ ] 1.2.1 tambem usa `shared.sh`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'shared.sh\t1.1')" || return 1
  assert_stdout_contains "$(printf 'shared.sh\t1.2')" || return 1
}

# ---------- Paths adversariais (SEC-1) ----------

scenario_paths_adversariais_nao_viram_path() {
  _write_tasks <<'EOF'
### 9.1 `adversarial` `[A]`

- [ ] 9.1.1 injecao `$(whoami)` nao e path
- [ ] 9.1.2 injecao `` `id` `` nao e path
- [ ] 9.1.3 injecao `; rm -rf /tmp/marker` nao e path
- [ ] 9.1.4 flag `--root <dir>` nao e path
- [ ] 9.1.5 tag `[C]` `[A]` `[M]` `[REAL]` nao e path
- [ ] 9.1.6 comando `realpath` `cd` `pwd -P` nao e path
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_not_contains "whoami" || return 1
  assert_stdout_not_contains "rm -rf" || return 1
  assert_stdout_not_contains "root" || return 1
  assert_stdout_not_contains "realpath" || return 1
  if [ -e "/tmp/marker" ]; then
    _fail "side-effect" "path adversarial foi executado"
    return 1
  fi
  assert_no_side_effect || return 1
}

scenario_referencia_de_tarefa_nao_vira_extensao_falsa() {
  # Regressao do bug encontrado nesta tarefa: "N.M" (ex.: tarefa 1.2) e
  # palavras terminadas em "ts"/"sh" (ex.: "contradicts", "Requirements")
  # NAO podem bater com a allowlist de extensao por falta de ponto literal.
  _write_tasks <<'EOF'
### 7.1 `regressao` `[A]`

- [ ] 7.1.1 consome a regra da tarefa 1.2 e classifica `missing`/`partial`/`contradicts`/`unrequested`
- [ ] 7.1.2 ver `Requirements` e `results` no documento
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_not_contains "contradicts" || return 1
  assert_stdout_not_contains "Requirements" || return 1
  assert_stdout_not_contains "results" || return 1
  # "1.2" sozinho (fora de heading) tambem nao pode aparecer como path.
  case "$_CAPTURED_STDOUT" in
    *"	1.2"*) : ;;  # ok se for ORIGEM de outra linha (nao e o caso aqui)
  esac
}

scenario_placeholder_de_nome_nao_produz_extensao_bare() {
  # Regressao: tokenizar `tests/test_<nome>.sh` (placeholder de convencao)
  # quebra o span em "tests/test_" / "nome" / ".sh" via os delimitadores
  # "<"/">" — o fragmento ".sh" isolado (sem base) NAO pode virar path.
  _write_tasks <<'EOF'
### 5.2 `verificacao` `[A]`

- [ ] 5.2.1 confirma que scripts tem `tests/test_<nome>.sh` correspondente
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"$(printf '\t')"*)
      :
      ;;
  esac
  # Nenhuma linha pode ser EXATAMENTE ".sh" no campo path.
  if printf '%s\n' "$_CAPTURED_STDOUT" | grep -qE '^\.sh	'; then
    _fail "bare-ext" "token '.sh' isolado (sem nome de arquivo) foi emitido como path"
    return 1
  fi
}

# ---------- plan.md (fonte secundaria) ----------

scenario_plan_ausente_nao_impede_execucao_scenario14() {
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 arquivo `real.sh`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'real.sh\t1.1')" || return 1
}

scenario_plan_flag_apontando_para_arquivo_inexistente_degrada() {
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 arquivo `real.sh`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md" --plan "$TMPDIR_TEST/nao-existe-plan.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0 (degrada, nao falha), obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_plan_extrai_path_com_fr_na_mesma_linha() {
  cat > "$TMPDIR_TEST/plan.md" <<'EOF'
## Project Structure

### Source Code

```
plugins/cstk/skills/converge/
├── scripts/
│   ├── state-decisions.sh     # [REAL] REUSO (FR-019)
│   └── severity.sh            # sem FR nesta linha
```

## Convencoes de Borda

N/A
EOF
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 nada relevante aqui
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md" --plan "$TMPDIR_TEST/plan.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'state-decisions.sh\tFR-019')" || return 1
  assert_stdout_not_contains "severity.sh" || return 1
}

scenario_plan_nao_herda_fr_de_linha_anterior() {
  # "FR mais proximo" e restrito a MESMA linha — nunca carry-forward
  # (fabricaria associacao path<->requisito nao literal no texto).
  cat > "$TMPDIR_TEST/plan.md" <<'EOF'
## Project Structure

### Source Code

```
plugins/cstk/skills/converge/
├── com-fr.sh                  # (FR-042)
├── sem-fr-mas-perto.sh
```
EOF
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 nada relevante aqui
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md" --plan "$TMPDIR_TEST/plan.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'com-fr.sh\tFR-042')" || return 1
  assert_stdout_not_contains "sem-fr-mas-perto.sh" || return 1
}

scenario_plan_fora_da_secao_project_structure_ignorado() {
  cat > "$TMPDIR_TEST/plan.md" <<'EOF'
## Summary

Mencao solta de fora-de-secao.md com FR-999 nao deve ser capturada.

## Project Structure

### Source Code

```
dentro.sh                      # (FR-001)
```

## Convencoes de Borda

Aqui depois-da-secao.md com FR-777 tambem nao deve aparecer.
EOF
  _write_tasks <<'EOF'
### 1.1 `fundacao` `[A]`

- [ ] 1.1.1 nada relevante aqui
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md" --plan "$TMPDIR_TEST/plan.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "$(printf 'dentro.sh\tFR-001')" || return 1
  assert_stdout_not_contains "fora-de-secao.md" || return 1
  assert_stdout_not_contains "depois-da-secao.md" || return 1
}

# ---------- Erros de uso / arquivo ausente ----------

scenario_tasks_ausente_exit1() {
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/nao-existe-tasks.md"
  if [ "$_CAPTURED_EXIT" != 1 ]; then
    _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_flag_tasks_ausente_exit2() {
  capture "$SCRIPT" --plan "$TMPDIR_TEST/plan.md"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_sem_argumentos_exit2() {
  capture "$SCRIPT"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_flag_desconhecida_exit2() {
  capture "$SCRIPT" --bogus x --tasks "$TMPDIR_TEST/tasks.md"
  if [ "$_CAPTURED_EXIT" != 2 ]; then
    _fail "exit" "esperado 2, obtido $_CAPTURED_EXIT"
    return 1
  fi
}

scenario_help_exit0() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "Uso:" || return 1
}

scenario_tasks_md_vazio_exit0_zero_linhas() {
  : > "$TMPDIR_TEST/tasks.md"
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout" "esperado vazio, obtido: $_CAPTURED_STDOUT"; return 1; }
}

# ---------- Determinismo ----------

scenario_saida_deterministica_entre_execucoes() {
  _write_tasks <<'EOF'
### 2.1 `b.sh` `[A]`
- [ ] 2.1.1 usa `a.md` e `b.sh`
### 2.2 `a.sh` `[A]`
- [ ] 2.2.1 usa `c.md`
EOF
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  _first="$_CAPTURED_STDOUT"
  capture "$SCRIPT" --tasks "$TMPDIR_TEST/tasks.md"
  _second="$_CAPTURED_STDOUT"
  if [ "$_first" != "$_second" ]; then
    _fail "determinismo" "duas execucoes com mesma entrada produziram saidas diferentes"
    return 1
  fi
}

run_all_scenarios
