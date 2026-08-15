#!/bin/sh
# test_roadmap-write.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/roadmap-write.sh (task 3.2,
# feature roadmap-mode). Regra de ouro (tasks.md 3.2.5).
#
# Cobertura:
#   geracao inicial: doc criado do zero, estrutura valida (cross-check via
#                     pipeline.sh detect-completion --stage roadmap)
#   re-geracao idempotente: mesmo input duas vezes nao duplica nem
#                            re-reporta alteracao
#   colisao de short-name: entrada existente e preservada/reusada (nunca
#                           duplicada), entradas nao tocadas permanecem
#                           intactas
#   alteracao deliberada: diff de Descricao/Justificativa reportado como
#                          'altered' (contracts/roadmap-artifact.md §8.1)
#   marcacao de obsolescencia: campo `- **marcada-obsoleta**:` reportado
#                               (contracts/roadmap-artifact.md §3.2.1)
#   filtragem de segredo: valor sensivel (AWS key) nao aparece no artefato
#                          escrito (contracts/roadmap-artifact.md §9.4)
#   fail-closed: secrets-filter.sh ausente -> nada e gravado, exit 1
#   usos incorretos: flags obrigatorias ausentes, --input sem entradas

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

RT_DIR="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
SCRIPT="$RT_DIR/roadmap-write.sh"
SCRIPT_PIPELINE="$RT_DIR/pipeline.sh"

# ==== helpers ====

# _write_input FILE CONTENT... — escreve CONTENT (heredoc via $2) em FILE.
_entries_basicas() {
  cat <<'EOF'
### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Permitir que o usuario se autentique via login e senha.

**Justificativa**: Pre-requisito de qualquer feature autenticada.

### 2. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 2
- **depende-de**: `auth-basica`

**Descricao**: Permitir editar dados de perfil.

**Justificativa**: Necessidade recorrente dos usuarios cadastrados.
EOF
}

_validar_estrutura() {
  _pap=$1
  capture "$SCRIPT_PIPELINE" detect-completion --feature-dir "$_pap/docs" \
    --stage roadmap --mode roadmap
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "roadmap.md deveria ser estruturalmente valido (detect-completion)" "exit=$_CAPTURED_EXIT stderr=$_CAPTURED_STDERR"; return 1; }
  return 0
}

# ==== geracao inicial ====

scenario_geracao_inicial_cria_doc_valido() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in="$TMPDIR_TEST/input.md"
  _entries_basicas > "$_in"

  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "write exit" "esperado 0, obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  [ -f "$_pap/docs/roadmap.md" ] || { _fail "roadmap.md nao foi criado" ""; return 1; }

  assert_stdout_contains "ENTRY|added|auth-basica|" || return 1
  assert_stdout_contains "ENTRY|added|perfil-usuario|" || return 1

  _validar_estrutura "$_pap" || return 1

  grep -q '^# Roadmap: pap$' "$_pap/docs/roadmap.md" \
    || { _fail "header ausente/nome de projeto incorreto" "$(head -1 "$_pap/docs/roadmap.md")"; return 1; }
}

scenario_geracao_inicial_project_name_override() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in="$TMPDIR_TEST/input.md"
  _entries_basicas > "$_in"

  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in" --project-name "Meu Projeto X"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "write exit" "obtido $_CAPTURED_EXIT" ; return 1; }
  grep -q '^# Roadmap: Meu Projeto X$' "$_pap/docs/roadmap.md" \
    || { _fail "nome de projeto nao aplicado" "$(head -1 "$_pap/docs/roadmap.md")"; return 1; }
}

# ==== re-geracao idempotente ====

scenario_regeracao_idempotente_mesmo_input_nao_duplica() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in="$TMPDIR_TEST/input.md"
  _entries_basicas > "$_in"

  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "1a escrita" "exit $_CAPTURED_EXIT"; return 1; }

  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "2a escrita (idempotente)" "exit $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "2a escrita nao deveria reportar mudancas (mesmo conteudo)" "obtido: $_CAPTURED_STDOUT"; return 1; }

  _n=$(grep -c '^### [1-9][0-9]*\. ' "$_pap/docs/roadmap.md")
  [ "$_n" = 2 ] || { _fail "esperado 2 entradas apos re-geracao idempotente (sem duplicar)" "obtido $_n"; return 1; }

  _validar_estrutura "$_pap" || return 1
}

# ==== colisao de short-name ====

scenario_colisao_short_name_preserva_entrada_nao_tocada() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in1="$TMPDIR_TEST/input1.md"
  _entries_basicas > "$_in1"
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "escrita inicial" "exit $_CAPTURED_EXIT"; return 1; }

  # Segunda execucao so redige uma entrada NOVA; auth-basica/perfil-usuario
  # nao aparecem no candidato e MUST permanecer intocadas (identidade por
  # short-name, contracts/roadmap-artifact.md §8).
  _in2="$TMPDIR_TEST/input2.md"
  cat > "$_in2" <<'EOF'
### 3. relatorios

- **short-name**: `relatorios`
- **ordem**: 3
- **depende-de**: `auth-basica`

**Descricao**: Gerar relatorios de uso.

**Justificativa**: Visibilidade operacional.
EOF
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "segunda escrita" "exit $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "ENTRY|added|relatorios|" || return 1
  case "$_CAPTURED_STDOUT" in
    *auth-basica*|*perfil-usuario*)
      _fail "entradas nao tocadas nao deveriam aparecer no relatorio de mudancas" "$_CAPTURED_STDOUT"
      return 1
      ;;
  esac

  _n=$(grep -c '^### [1-9][0-9]*\. ' "$_pap/docs/roadmap.md")
  [ "$_n" = 3 ] || { _fail "esperado 3 entradas (2 preservadas + 1 nova)" "obtido $_n"; return 1; }
  grep -q '^### 1\. auth-basica$' "$_pap/docs/roadmap.md" \
    || { _fail "auth-basica deveria ter sido preservada" ""; return 1; }
  grep -q '^### 2\. perfil-usuario$' "$_pap/docs/roadmap.md" \
    || { _fail "perfil-usuario deveria ter sido preservada" ""; return 1; }

  _validar_estrutura "$_pap" || return 1
}

# ==== alteracao deliberada (§8.1) ====

scenario_alteracao_deliberada_reportada() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in1="$TMPDIR_TEST/input1.md"
  _entries_basicas > "$_in1"
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "escrita inicial" "exit $_CAPTURED_EXIT"; return 1; }

  _in2="$TMPDIR_TEST/input-alterado.md"
  cat > "$_in2" <<'EOF'
### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Autenticacao via login/senha E via OAuth de terceiros.

**Justificativa**: Pre-requisito de qualquer feature autenticada.
EOF
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "segunda escrita" "exit $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "ENTRY|altered|auth-basica|" || return 1

  grep -q "OAuth de terceiros" "$_pap/docs/roadmap.md" \
    || { _fail "descricao alterada nao foi aplicada ao artefato" ""; return 1; }
}

# ==== marcacao de obsolescencia (§3.2.1) ====

scenario_marcacao_obsoleta_reportada() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in1="$TMPDIR_TEST/input1.md"
  _entries_basicas > "$_in1"
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in1"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "escrita inicial" "exit $_CAPTURED_EXIT"; return 1; }

  _in2="$TMPDIR_TEST/input-obsoleta.md"
  cat > "$_in2" <<'EOF'
### 2. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 2
- **depende-de**: `auth-basica`
- **marcada-obsoleta**: substituido por perfil-avancado

**Descricao**: Permitir editar dados de perfil.

**Justificativa**: Necessidade recorrente dos usuarios cadastrados.
EOF
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in2"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "segunda escrita" "exit $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "ENTRY|obsolete|perfil-usuario|substituido por perfil-avancado" || return 1

  grep -q '^- \*\*marcada-obsoleta\*\*: substituido por perfil-avancado$' "$_pap/docs/roadmap.md" \
    || { _fail "campo marcada-obsoleta nao persistido no artefato" ""; return 1; }

  # Nao apagou a entrada (regra §8: nunca apagar, marcar e reportar).
  _n=$(grep -c '^### [1-9][0-9]*\. ' "$_pap/docs/roadmap.md")
  [ "$_n" = 2 ] || { _fail "entrada obsoleta nao deveria ser removida" "obtido $_n entradas"; return 1; }
}

# ==== filtragem de segredo (§9.4, CHK007) ====

scenario_filtragem_de_segredo() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in="$TMPDIR_TEST/input-secret.md"
  cat > "$_in" <<'EOF'
### 1. integracao-pagamento

- **short-name**: `integracao-pagamento`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Integrar com AWS usando a credencial AKIAABCDEFGH12345678 para acesso.

**Justificativa**: Necessario para checkout.
EOF
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "write exit" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }

  if grep -q "AKIAABCDEFGH12345678" "$_pap/docs/roadmap.md"; then
    _fail "segredo vazou para o artefato escrito" ""
    return 1
  fi
  grep -q "REDACTED" "$_pap/docs/roadmap.md" \
    || { _fail "esperava marcador REDACTED no lugar do segredo" ""; return 1; }
}

# ==== fail-closed: secrets-filter.sh ausente ====

scenario_fail_closed_sem_secrets_filter() {
  _fakebin="$TMPDIR_TEST/fakebin"
  mkdir -p "$_fakebin"
  # Copia so o roadmap-write.sh (sem secrets-filter.sh nem _log.sh) para um
  # diretorio isolado, forcando o caminho fail-closed.
  cp "$SCRIPT" "$_fakebin/roadmap-write.sh"

  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in="$TMPDIR_TEST/input.md"
  _entries_basicas > "$_in"

  capture sh "$_fakebin/roadmap-write.sh" write --projeto-alvo-path "$_pap" --input "$_in"
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit esperado 1 (fail-closed)" "obtido $_CAPTURED_EXIT"; return 1; }
  [ -f "$_pap/docs/roadmap.md" ] && { _fail "roadmap.md NAO deveria ter sido gravado sem secrets-filter.sh" ""; return 1; }
  assert_stderr_contains "secrets-filter.sh ausente" || return 1
}

# ==== usos incorretos ====

scenario_sem_projeto_alvo_path_exit2() {
  _in="$TMPDIR_TEST/input.md"
  _entries_basicas > "$_in"
  capture "$SCRIPT" write --input "$_in"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sem_input_exit2() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  capture "$SCRIPT" write --projeto-alvo-path "$_pap"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_input_sem_entradas_reconheciveis_exit2() {
  _pap="$TMPDIR_TEST/pap"
  mkdir -p "$_pap"
  _in="$TMPDIR_TEST/input-vazio.md"
  printf 'apenas prosa livre, sem nenhum heading de entrada\n' > "$_in"
  capture "$SCRIPT" write --projeto-alvo-path "$_pap" --input "$_in"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (input sem entradas)" "obtido $_CAPTURED_EXIT"; return 1; }
  if [ -f "$_pap/docs/roadmap.md" ]; then
    _fail "nao deveria ter gravado nada" ""
    return 1
  fi
  return 0
}

run_all_scenarios
