#!/bin/sh
# test_roadmap-status.sh — cobre
# plugins/cstk/skills/review-features/scripts/roadmap-status.sh (task 3.3,
# feature roadmap-mode). Regra de ouro (tasks.md 3.3.6).
#
# Cobertura:
#   tabela markdown (default) + status derivado por entrada (§5: nao-iniciada
#   /em-andamento/concluida)
#   --json (JSON-lines)
#   4 exit codes: 0 sucesso (inclusive 0 entradas), 1 roadmap ausente,
#                 2 uso incorreto, 3 roadmap invalido/ilegivel
#   escape de '|' na tabela markdown e de '"'/'\' em JSON
#   fail-closed: short-name > 64 chars descartado; token de depende-de
#                invalido (apos remover crases) descartado, nunca emitido bruto

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/review-features/scripts/roadmap-status.sh"

# ==== helpers ====

_roadmap_basico() {
  cat <<'EOF'
# Roadmap: teste

**Gerado por**: /agente-00c (modo roadmap)
**Atualizado em**: 2026-08-14

## Ordem sugerida

| # | Feature | Depende de | Descricao (resumo) |
|---|---------|------------|--------------------|
| 1 | `auth-basica` | - | Autenticacao. |
| 2 | `perfil-usuario` | `auth-basica` | Perfil. |
| 3 | `relatorios` | `auth-basica`, `perfil-usuario` | Relatorios. |

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Autenticacao.

**Justificativa**: Pre-requisito.

### 2. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 2
- **depende-de**: `auth-basica`

**Descricao**: Perfil.

**Justificativa**: Necessario.

### 3. relatorios

- **short-name**: `relatorios`
- **ordem**: 3
- **depende-de**: `auth-basica`, `perfil-usuario`

**Descricao**: Relatorios.

**Justificativa**: Visibilidade.
EOF
}

# ==== tabela markdown + derivacao de status ====

scenario_markdown_default_deriva_status_por_entrada() {
  _rm="$TMPDIR_TEST/roadmap.md"
  _specs="$TMPDIR_TEST/specs"
  _roadmap_basico > "$_rm"

  # auth-basica: concluida (tasks.md sem pendentes)
  mkdir -p "$_specs/auth-basica"
  printf -- '- [x] 1.1 feito\n' > "$_specs/auth-basica/tasks.md"

  # perfil-usuario: em-andamento (tasks.md com pendente)
  mkdir -p "$_specs/perfil-usuario"
  printf -- '- [x] 1.1 feito\n- [ ] 1.2 pendente\n' > "$_specs/perfil-usuario/tasks.md"

  # relatorios: nao-iniciada (dir inexistente) — nao criado.

  capture "$SCRIPT" --roadmap "$_rm" --specs-dir "$_specs"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }

  assert_stdout_contains "| 1 | auth-basica | concluida | - |" || return 1
  assert_stdout_contains "| 2 | perfil-usuario | em-andamento | auth-basica |" || return 1
  assert_stdout_contains "| 3 | relatorios | nao-iniciada | auth-basica,perfil-usuario |" || return 1
  assert_stdout_contains "**Entradas:** 3" || return 1
}

scenario_em_andamento_quando_dir_existe_sem_tasks_md() {
  _rm="$TMPDIR_TEST/roadmap.md"
  _specs="$TMPDIR_TEST/specs"
  _roadmap_basico > "$_rm"
  mkdir -p "$_specs/auth-basica"   # sem tasks.md

  capture "$SCRIPT" --roadmap "$_rm" --specs-dir "$_specs"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "| 1 | auth-basica | em-andamento | - |" || return 1
}

# ==== --json ====

scenario_json_lines() {
  _rm="$TMPDIR_TEST/roadmap.md"
  _roadmap_basico > "$_rm"

  capture "$SCRIPT" --roadmap "$_rm" --specs-dir "$TMPDIR_TEST/specs-inexistente" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '{"ordem":1,"short_name":"auth-basica","status":"nao-iniciada","depende_de":[]}' || return 1
  assert_stdout_contains '"depende_de":["auth-basica"]' || return 1
  assert_stdout_contains '"depende_de":["auth-basica","perfil-usuario"]' || return 1
  # Sem envelope markdown no modo --json.
  case "$_CAPTURED_STDOUT" in
    *'## Cruzamento'*) _fail "modo --json nao deveria emitir cabecalho markdown" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
}

# ==== exit codes ====

scenario_exit1_roadmap_ausente() {
  capture "$SCRIPT" --roadmap "$TMPDIR_TEST/nao-existe.md"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit esperado 1" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "nao encontrado" || return 1
}

scenario_exit2_flag_desconhecida() {
  capture "$SCRIPT" --flag-inexistente
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_exit2_flag_sem_valor() {
  capture "$SCRIPT" --roadmap
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (--roadmap sem valor)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_exit3_roadmap_sem_header() {
  _rm="$TMPDIR_TEST/invalido.md"
  printf 'isto nao e um roadmap valido\n' > "$_rm"
  capture "$SCRIPT" --roadmap "$_rm"
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit esperado 3" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "invalido/ilegivel" || return 1
}

scenario_exit0_zero_entradas_com_aviso() {
  _rm="$TMPDIR_TEST/vazio.md"
  cat > "$_rm" <<'EOF'
# Roadmap: vazio

**Gerado por**: x
**Atualizado em**: 2026-08-14

## Ordem sugerida

## Features
EOF
  capture "$SCRIPT" --roadmap "$_rm"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (0 entradas nao e erro)" "obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "stdout deveria ser vazio (0 entradas)" "$_CAPTURED_STDOUT"; return 1; }
  assert_stderr_contains "0 entradas" || return 1
}

# ==== escape ====

scenario_escape_pipe_na_tabela_markdown() {
  _rm="$TMPDIR_TEST/roadmap-pipe.md"
  # depende-de com token invalido nao entra na saida; testamos o escape de
  # '|' indiretamente via short-name que NAO pode conter '|' (regex ja
  # impede), entao validamos que a tabela permanece bem-formada mesmo com
  # muitas entradas (regressao estrutural simples).
  _roadmap_basico > "$_rm"
  capture "$SCRIPT" --roadmap "$_rm"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT"; return 1; }
  _cols=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep '^| 1 |' | awk -F'|' '{print NF}')
  [ "$_cols" = 6 ] || { _fail "linha da tabela deveria ter 4 colunas (6 campos apos split por '|')" "obtido $_cols"; return 1; }
}

scenario_escape_json_aspas_e_backslash() {
  _rm="$TMPDIR_TEST/roadmap.md"
  cat > "$_rm" <<'EOF'
# Roadmap: teste

**Gerado por**: x
**Atualizado em**: 2026-08-14

## Ordem sugerida

## Features

### 1. feature-normal

- **short-name**: `feature-normal`
- **ordem**: 1
- **depende-de**: -

**Descricao**: teste.

**Justificativa**: teste.
EOF
  capture "$SCRIPT" --roadmap "$_rm" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT"; return 1; }
  # short_name so pode conter [a-z0-9-] (regex de heading), entao nao ha
  # aspas/backslash a escapar no caso feliz — o teste valida que a funcao
  # json_escape produz JSON parseavel (aspas balanceadas).
  _n_quotes=$(printf '%s' "$_CAPTURED_STDOUT" | tr -dc '"' | wc -c | tr -d ' ')
  [ $((_n_quotes % 2)) -eq 0 ] || { _fail "JSON com aspas desbalanceadas" "$_CAPTURED_STDOUT"; return 1; }
}

# ==== fail-closed (§9.2) ====

scenario_fail_closed_short_name_muito_longo_descartado() {
  _long=$(printf 'a%.0s' $(seq 1 70))
  _rm="$TMPDIR_TEST/roadmap-longo.md"
  cat > "$_rm" <<EOF
# Roadmap: teste

**Gerado por**: x
**Atualizado em**: 2026-08-14

## Ordem sugerida

## Features

### 1. $_long

- **short-name**: \`$_long\`
- **ordem**: 1
- **depende-de**: -

**Descricao**: teste.

**Justificativa**: teste.

### 2. ok-feature

- **short-name**: \`ok-feature\`
- **ordem**: 2
- **depende-de**: -

**Descricao**: teste.

**Justificativa**: teste.
EOF
  capture "$SCRIPT" --roadmap "$_rm" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"$_long"*) _fail "entrada com short-name > 64 chars nao deveria aparecer na saida" ""; return 1 ;;
  esac
  assert_stdout_contains '"short_name":"ok-feature"' || return 1
  assert_stderr_contains "> 64 chars" || return 1
}

scenario_fail_closed_depende_de_invalido_descartado_sem_emitir_bruto() {
  _rm="$TMPDIR_TEST/roadmap-dep-invalida.md"
  cat > "$_rm" <<'EOF'
# Roadmap: teste

**Gerado por**: x
**Atualizado em**: 2026-08-14

## Ordem sugerida

## Features

### 1. feature-a

- **short-name**: `feature-a`
- **ordem**: 1
- **depende-de**: `../etc/passwd`, `feature-b`

**Descricao**: teste.

**Justificativa**: teste.
EOF
  capture "$SCRIPT" --roadmap "$_rm" --specs-dir "$TMPDIR_TEST/specs-inexistente" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"etc/passwd"*) _fail "token de depende-de invalido nao deveria ser emitido bruto" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
  assert_stdout_contains '"depende_de":["feature-b"]' || return 1
  assert_stderr_contains "token de depende-de descartado" || return 1
}

# quickstart.md Cenario 11 passo 3 (seguranca H2, gate FASE 6 6.3.3):
# payload literal com '|' em depende-de (nao so via short-name, que a
# regex de heading ja impede por construcao). Prova que o token e
# descartado ANTES de alcancar a tabela markdown — nenhuma coluna extra,
# nenhum '|' bruto na linha de dado.
scenario_fail_closed_depende_de_com_pipe_nao_quebra_tabela() {
  _rm="$TMPDIR_TEST/roadmap-dep-pipe.md"
  cat > "$_rm" <<'EOF'
# Roadmap: teste

**Gerado por**: x
**Atualizado em**: 2026-08-14

## Ordem sugerida

## Features

### 1. feature-a

- **short-name**: `feature-a`
- **ordem**: 1
- **depende-de**: `a|b|c`, `feature-b`

**Descricao**: teste.

**Justificativa**: teste.
EOF
  capture "$SCRIPT" --roadmap "$_rm" --specs-dir "$TMPDIR_TEST/specs-inexistente"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  _cols=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep '^| 1 |' | awk -F'|' '{print NF}')
  [ "$_cols" = 6 ] || { _fail "tabela deveria ter 4 colunas (6 campos apos split por '|')" "obtido $_cols"; return 1; }
  assert_stdout_contains 'feature-b' || return 1
  assert_stderr_contains "token de depende-de descartado" || return 1
}

# quickstart.md Cenario 11 passo 4 (seguranca H2, gate FASE 6 6.3.3):
# payload literal com '"' e '\' em depende-de, com --json. Prova que o
# token e descartado ANTES do json_escape — a linha permanece parseavel
# (aspas balanceadas) mesmo com o payload hostil na entrada bruta.
scenario_fail_closed_depende_de_com_aspas_e_backslash_json_parseavel() {
  _rm="$TMPDIR_TEST/roadmap-dep-aspas.md"
  cat > "$_rm" <<'EOF'
# Roadmap: teste

**Gerado por**: x
**Atualizado em**: 2026-08-14

## Ordem sugerida

## Features

### 1. feature-a

- **short-name**: `feature-a`
- **ordem**: 1
- **depende-de**: `a"b\c`, `feature-b`

**Descricao**: teste.

**Justificativa**: teste.
EOF
  capture "$SCRIPT" --roadmap "$_rm" --specs-dir "$TMPDIR_TEST/specs-inexistente" --json
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *'a"b\c'*) _fail "token hostil nao deveria ser emitido bruto no JSON" "$_CAPTURED_STDOUT"; return 1 ;;
  esac
  assert_stdout_contains '"depende_de":["feature-b"]' || return 1
  # aspas duplas balanceadas na linha de saida da entrada (paridade par).
  _linha=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep '"short_name":"feature-a"')
  _n_aspas=$(printf '%s' "$_linha" | tr -cd '"' | wc -c | tr -d ' ')
  [ $((_n_aspas % 2)) -eq 0 ] || { _fail "aspas desbalanceadas no JSON" "$_linha"; return 1; }
  assert_stderr_contains "token de depende-de descartado" || return 1
}

run_all_scenarios
