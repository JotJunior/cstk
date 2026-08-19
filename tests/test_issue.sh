#!/bin/sh
# test_issue.sh — cobre plugins/cstk/skills/agente-00c-runtime/scripts/issue.sh.
#
# Testes apenas locais (dry-run) — NAO chama gh real para nao gerar issues
# de teste em produçao. check-duplicate exige rede + auth, portanto e
# deixado para validacao end-to-end.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/issue.sh"
RW="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh"
DEC="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/state-decisions.sh"
SG="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/suggestions.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_issue.sh: jq ausente — pulando\n'
  exit 0
fi

_setup() {
  # HOME sandbox SEM config global: forca backend JSON deterministico mesmo
  # em hosts com `state_backend=sqlite` em ~/.claude/cstk/config (padrao de
  # hermeticidade do test__state-read.sh; state-db-runtime-parity 2.4.8).
  _s_home="$TMPDIR_TEST/home-json"
  mkdir -p "$_s_home"
  capture env HOME="$_s_home" "$RW" init --state-dir "$1" --execucao-id "exec-issue-test" \
    --projeto-alvo-path "/tmp/p" --descricao "POC issue tests"
  [ "$_CAPTURED_EXIT" = 0 ] || return 1
  capture "$DEC" register --state-dir "$1" \
    --agente "orquestrador-00c" --etapa "clarify" \
    --contexto "Tentou avancar pipeline com perguntas contraditorias" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste"
  capture "$SG" register --state-dir "$1" --suggestions-file "$2" \
    --skill "clarify" --severidade "impeditiva" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo" \
    --proposta "Adicionar etapa de cross-check entre perguntas geradas pela skill"
}

scenario_hash_deterministico() {
  capture "$SCRIPT" hash --diagnostico "test diagnostico"
  _h1=$_CAPTURED_STDOUT
  capture "$SCRIPT" hash --diagnostico "test diagnostico"
  _h2=$_CAPTURED_STDOUT
  if [ "$_h1" != "$_h2" ]; then
    _fail "hash determinismo" "$_h1 != $_h2"
    return 1
  fi
  # 8 chars hex
  case "$_h1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) _fail "hash format" "esperado 8 hex chars, obtido: $_h1"; return 1 ;;
  esac
}

scenario_hash_normaliza_whitespace_e_case() {
  capture "$SCRIPT" hash --diagnostico "Test Diagnostico"
  _h1=$_CAPTURED_STDOUT
  capture "$SCRIPT" hash --diagnostico "  test  diagnostico  "
  _h2=$_CAPTURED_STDOUT
  if [ "$_h1" != "$_h2" ]; then
    _fail "normalizacao" "$_h1 != $_h2 (devia ser igual apos lowercase + collapse ws)"
    return 1
  fi
}

scenario_dry_run_imprime_template_completo() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "Adicionar etapa de cross-check entre perguntas" \
    --por-que-impeditivo "Pipeline ja consumiu 1 retro — terceira tentativa violaria limite" \
    --reproducao "Onda 2 disparou bug" \
    --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "DRY-RUN" || return 1
  assert_stdout_contains "Title: [agente-00C] Bug em clarify" || return 1
  assert_stdout_contains "Repo: JotJunior/cstk" || return 1
  assert_stdout_contains "Labels: agente-00c,bug,skill-global" || return 1
  assert_stdout_contains "## Skill afetada" || return 1
  assert_stdout_contains "## Diagnostico" || return 1
  assert_stdout_contains "## Reproducao" || return 1
  assert_stdout_contains "## Por que e impeditivo" || return 1
  assert_stdout_contains "## Proposta de correcao" || return 1
  assert_stdout_contains "## Anexos" || return 1
}

scenario_dry_run_inclui_hash_no_titulo() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "fix proposta detalhada" \
    --dry-run
  # Hash deve aparecer entre parenteses no titulo
  case "$_CAPTURED_STDOUT" in
    *"Title: [agente-00C] Bug em clarify ("*")"*) ;;
    *) _fail "hash no titulo" "esperado padrao 'Bug em SKILL (HASH):'"; return 1 ;;
  esac
}

scenario_dry_run_aplica_secrets_filter() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _env="$TMPDIR_TEST/.env"
  printf 'DB_PWD=mysupersecretpwd123\n' > "$_env"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify falhou — leak: api_key=abcdef1234567890123456789xyz aqui" \
    --proposta "fix com mysupersecretpwd123 vazando aqui" \
    --env-file "$_env" \
    --dry-run
  case "$_CAPTURED_STDOUT" in
    *abcdef1234567890123456789xyz*)
      _fail "token vazou" "secrets-filter nao aplicado"; return 1 ;;
    *mysupersecretpwd123*)
      _fail "env vazou" "env-file scrub nao aplicado"; return 1 ;;
  esac
  assert_stdout_contains "REDACTED" || return 1
}

scenario_create_sem_state_falha() {
  _sd="$TMPDIR_TEST/empty"
  mkdir -p "$_sd"
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "x" \
    --diagnostico "Diagnostico longo o suficiente para passar a validacao" \
    --proposta "fix" --dry-run
  if [ "$_CAPTURED_EXIT" = 0 ]; then
    _fail "sem state" "esperado != 0"
    return 1
  fi
}

# --- Back-compat: fixture pt-BR legada lida via reader-fallback (.en // .pt) ---
# schema-en-migration: _ish_get_state / _ish_build_body leem o state.json com
# paths EN + fallback pt-BR. Prova que um state.json legado (escrito antes da
# migracao, com chaves .execucao/.etapa_corrente/.ondas/.decisoes/.contexto)
# continua sendo lido sem migrate previo — os valores legados afloram no body
# do dry-run. (As fixtures default via state-rw.sh init ja produzem EN no disco,
# entao exercitam o lado EN do fallback.)
_write_legacy_ptbr_state() {
  # $1 = state-dir. Escreve um state.json minimo com chaves pt-BR legadas.
  mkdir -p "$1"
  cat > "$1/state.json" <<'PTBR'
{
  "schema_version": 1,
  "execucao": {
    "id": "exec-legado-ptbr",
    "projeto_alvo_path": "/tmp/legado",
    "projeto_alvo_descricao": "Projeto legado pt-BR back-compat"
  },
  "etapa_corrente": "clarify",
  "ondas": [{ "id": "onda-042" }],
  "decisoes": [
    {
      "id": "dec-001",
      "contexto": "Decisao legada que evidencia bug via fallback pt-BR"
    }
  ]
}
PTBR
}

# (Os dois cenarios de leitor abaixo testam que o contexto do projeto-alvo
# FLUI pelo reader — por isso passam --include-project-context; o default
# redigido e coberto em scenario_issue143_*.)
scenario_ptbr_legado_reader_fallback() {
  # _ish_get_state le execucao.id / projeto_alvo_descricao / etapa_corrente /
  # ondas[-1].id via fallback; _ish_build_body le decisoes[].contexto via
  # fallback. Todos afloram no body do dry-run.
  _sd="$TMPDIR_TEST/legacy"
  _write_legacy_ptbr_state "$_sd"
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify falhou em estado legado pt-BR para validar fallback" \
    --proposta "fix proposta detalhada" \
    --dry-run --include-project-context
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run pt-BR" "$_CAPTURED_STDERR"; return 1; }
  # execucao.id (fallback) aparece no cabecalho do body
  assert_stdout_contains "exec-legado-ptbr" || return 1
  # projeto_alvo_descricao (fallback) aparece em Projeto-alvo
  assert_stdout_contains "Projeto legado pt-BR back-compat" || return 1
  # etapa_corrente (fallback) aparece em Etapa
  assert_stdout_contains "Etapa: \`clarify\`" || return 1
  # ondas[-1].id (fallback) aparece em Onda
  assert_stdout_contains "Onda: \`onda-042\`" || return 1
  # decisoes[].id + contexto (fallback) afloram nas decisoes relevantes
  assert_stdout_contains "Decisao \`dec-001\`" || return 1
  assert_stdout_contains "Decisao legada que evidencia bug via fallback pt-BR" || return 1
}

# ==== Backend SQLite (state-db-runtime-parity FASE 2.4 / FR-001 / SC-003) ====
# _ish_get_state/_ish_build_body leem via _state-read.sh (materializacao).
# Segue dry-run only (nunca gh real).

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  [ -n "$_v" ]
}

_setup_sqlite() {
  _ss_home="$TMPDIR_TEST/home-sqlite"
  mkdir -p "$_ss_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_ss_home/.claude/cstk/config"
  env HOME="$_ss_home" "$RW" init --state-dir "$1" \
    --execucao-id "exec-issue-sqlite" --projeto-alvo-path "/tmp/p" \
    --descricao "POC issue sqlite" >/dev/null 2>&1 || return 1
  [ -f "$1/state.db" ] || return 1
  "$DEC" register --state-dir "$1" \
    --agente "orquestrador-00c" --etapa "clarify" \
    --contexto "Decisao sqlite que evidencia o bug reportado" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "Justificativa de tamanho ok aqui sim para teste" >/dev/null 2>&1 || return 1
  "$SG" register --state-dir "$1" --suggestions-file "$2" \
    --skill "clarify" --severidade "impeditiva" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 no cenario sqlite" \
    --proposta "Adicionar etapa de cross-check entre perguntas geradas" >/dev/null 2>&1
}

scenario_sqlite_dry_run_le_estado_do_state_db() {
  _sqlite3_adequate || { printf "# skip: sqlite3 indisponivel\n"; return 0; }
  _sd="$TMPDIR_TEST/state-sqlite"; _md="$TMPDIR_TEST/sug-sqlite.md"
  _setup_sqlite "$_sd" "$_md" || { _error "fixture sqlite" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 no cenario sqlite" \
    --proposta "Adicionar etapa de cross-check entre perguntas" \
    --dry-run --include-project-context
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run sqlite" "exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  case "$_CAPTURED_STDERR" in
    *"state.json ausente"*) _fail "dry-run sqlite" "degradou com 'state.json ausente'"; return 1 ;;
  esac
  # Valores do estado afloram no body: exec id + decisao registrada no state.db
  assert_stdout_contains "exec-issue-sqlite" || return 1
  assert_stdout_contains "Decisao sqlite que evidencia o bug reportado" || return 1
  # FR-003: nenhuma operacao pode materializar state.json no state-dir.
  if [ -f "$_sd/state.json" ]; then
    _fail "anti-mirror" "issue criou state.json dentro do state-dir sqlite"
    return 1
  fi
}

# ==== FASE 3.2 (claude-plugin-packaging) — candidato ${CLAUDE_PLUGIN_ROOT} ====
#
# Task 3.2.6: `_ish_skills_base` (via `_resolve-root.sh`) substitui o
# antigo `~/.claude/skills/$_skill/` hardcoded na secao "Caminho instalado"
# do corpo da issue (Constitution VI — nunca fabricar path). Os scenarios
# abaixo isolam issue.sh + _state-read.sh (unica dependencia real para
# backend JSON) num diretorio SEM sibling `_resolve-root.sh` algum.

# _copy_issue_isolated DEST_DIR -> copia issue.sh + _state-read.sh (unica
# dep exercitada sob backend JSON) para DEST_DIR; ecoa o path do issue.sh
# isolado.
_copy_issue_isolated() {
  mkdir -p "$1"
  cp "$SCRIPT" "$1/issue.sh"
  cp "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_state-read.sh" "$1/_state-read.sh"
  chmod +x "$1/issue.sh"
  printf '%s/issue.sh' "$1"
}

scenario_caminho_instalado_reflete_raiz_resolvida() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo" \
    --proposta "fix proposta detalhada" \
    --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  # Rodando in-tree, o sibling de issue.sh resolve a raiz REAL do repo —
  # o path nao pode mais ser o antigo literal fixo ~/.claude/skills/.
  assert_stdout_contains "$REPO_ROOT/plugins/cstk/skills/clarify/" || return 1
}

scenario_plugin_root_resolve_caminho_instalado_via_claude_plugin_root() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }

  _isolated=$(_copy_issue_isolated "$TMPDIR_TEST/isolated-plugin")
  _plugin_scripts="$TMPDIR_TEST/fake-plugin/skills/agente-00c-runtime/scripts"
  mkdir -p "$_plugin_scripts"
  cp "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/_resolve-root.sh" "$_plugin_scripts/_resolve-root.sh"
  _fake_home="$TMPDIR_TEST/fake-home-plugin"
  mkdir -p "$_fake_home"

  capture env HOME="$_fake_home" CLAUDE_PLUGIN_ROOT="$TMPDIR_TEST/fake-plugin" \
    "$_isolated" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo" \
    --proposta "fix proposta detalhada" \
    --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "esperado 0 (resolvido via plugin), obtido $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "$TMPDIR_TEST/fake-plugin/skills/clarify/" || return 1
}

# Prova o proprio objetivo da task 3.2.6 (Constitution VI): quando a raiz
# de agente-00c-runtime e irresolvivel (sibling, plugin E classico
# falham), issue.sh MUST falhar (CLI comum: exit != 0 + stderr) em vez de
# fabricar um "Caminho instalado" adivinhado no corpo da issue.
scenario_falha_caminho_instalado_irresolvivel_bloqueia_create() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }

  _isolated=$(_copy_issue_isolated "$TMPDIR_TEST/isolated-irresolvivel")
  _fake_home="$TMPDIR_TEST/fake-home-irresolvivel"
  mkdir -p "$_fake_home"

  capture env HOME="$_fake_home" CLAUDE_PLUGIN_ROOT="" \
    "$_isolated" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo" \
    --proposta "fix proposta detalhada" \
    --dry-run
  [ "$_CAPTURED_EXIT" != 0 ] || { _fail "exit" "raiz irresolvivel deveria falhar (Constitution VI), obtido 0: $_CAPTURED_STDOUT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    *"claude/skills"*) _fail "fabricacao" "corpo da issue nao deveria ter sido emitido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  assert_stderr_contains "irresolvivel" || return 1
}

# ==== issue #143: privacidade por default + draft/publish ====
scenario_issue143_default_redige_contexto_do_projeto() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "Adicionar etapa de cross-check entre perguntas" \
    --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  # Conteudo tecnico continua la...
  assert_stdout_contains "## Diagnostico" || return 1
  assert_stdout_contains "Skill clarify gerou opcoes contraditorias" || return 1
  assert_stdout_contains "Etapa: \`" || return 1
  # ...mas descricao do projeto, ID da execucao, Decisoes e path absoluto NAO.
  case "$_CAPTURED_STDOUT" in
    *"POC issue tests"*) _fail "descricao do projeto vazou" ""; return 1 ;;
    *"exec-issue-test"*) _fail "ID da execucao vazou" ""; return 1 ;;
    *"Tentou avancar pipeline"*) _fail "trecho de Decisao vazou" ""; return 1 ;;
    *"/tmp/p/.claude"*) _fail "path absoluto do projeto vazou" ""; return 1 ;;
  esac
  assert_stdout_contains "omitid" || return 1
  assert_stdout_contains "<projeto-alvo>/.claude/agente-00c-report.md" || return 1
}

scenario_issue143_include_project_context_restaura_corpo_completo() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "Adicionar etapa de cross-check entre perguntas" \
    --dry-run --include-project-context
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "dry-run exit" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "POC issue tests" || return 1
  assert_stdout_contains "exec-issue-test" || return 1
  assert_stdout_contains "Tentou avancar pipeline" || return 1
  assert_stdout_contains "/tmp/p/.claude/agente-00c-report.md" || return 1
}

scenario_issue143_draft_grava_arquivo_e_nao_publica() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  _draft="$TMPDIR_TEST/pap/.claude/agente-00c-issues/sug-001.md"
  # gh stub que FALHA se for chamado: draft nunca pode tocar o GitHub.
  _stub="$TMPDIR_TEST/stub-gh-draft"; mkdir -p "$_stub"
  printf '#!/bin/sh\necho "gh NAO deveria ser chamado: $*" >&2; exit 99\n' > "$_stub/gh"; chmod +x "$_stub/gh"
  capture env PATH="$_stub:$PATH" "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "Adicionar etapa de cross-check entre perguntas" \
    --draft "$_draft"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "draft exit" "$_CAPTURED_STDERR"; return 1; }
  [ "$_CAPTURED_STDOUT" = "$_draft" ] || { _fail "stdout deveria ser o path do rascunho" "obtido '$_CAPTURED_STDOUT'"; return 1; }
  assert_stderr_contains "NAO publicado" || return 1
  [ -f "$_draft" ] || { _fail "rascunho nao gravado" ""; return 1; }
  head -1 "$_draft" | grep -q '^Title: \[agente-00C\] Bug em clarify (' || { _fail "linha 1 do rascunho" "$(head -1 "$_draft")"; return 1; }
  grep -q '^## Diagnostico' "$_draft" || { _fail "corpo do rascunho" ""; return 1; }
  # Default redigido tambem no draft.
  if grep -q "POC issue tests" "$_draft"; then _fail "descricao do projeto vazou no draft" ""; return 1; fi
  case "$_CAPTURED_STDERR" in *"gh NAO deveria"*) _fail "draft chamou gh" ""; return 1 ;; esac
}

scenario_issue143_publish_dry_run_le_rascunho_e_rescruba() {
  _sd="$TMPDIR_TEST/state"; _md="$TMPDIR_TEST/sug.md"
  _setup "$_sd" "$_md" || { _error "fixture" ""; return 2; }
  _draft="$TMPDIR_TEST/drafts/sug-001.md"
  capture "$SCRIPT" create --state-dir "$_sd" --suggestion-id "sug-001" \
    --skill "clarify" \
    --diagnostico "Skill clarify gerou opcoes contraditorias entre perguntas Q3 e Q5 para o mesmo escopo de armazenamento" \
    --proposta "Adicionar etapa de cross-check entre perguntas" \
    --draft "$_draft"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "draft" "$_CAPTURED_STDERR"; return 1; }
  # Operador edita o rascunho a mao e deixa escapar um token: publish re-scruba.
  printf '\nNota do operador: api_key=abcdef1234567890123456789xyz\n' >> "$_draft"
  capture "$SCRIPT" publish --from "$_draft" --dry-run
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "publish dry-run" "$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "Title: [agente-00C] Bug em clarify (" || return 1
  assert_stdout_contains "## Diagnostico" || return 1
  case "$_CAPTURED_STDOUT" in *abcdef1234567890123456789xyz*) _fail "publish nao re-scrubou" ""; return 1 ;; esac
  assert_stdout_contains "REDACTED" || return 1
}

scenario_issue143_publish_rascunho_invalido_falha() {
  _bad="$TMPDIR_TEST/bad-draft.md"
  printf 'sem linha Title\n\ncorpo\n' > "$_bad"
  capture "$SCRIPT" publish --from "$_bad" --dry-run
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "exit" "esperado 1, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "rascunho invalido" || return 1
  capture "$SCRIPT" publish --dry-run
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit sem --from" "esperado 2, obtido $_CAPTURED_EXIT"; return 1; }
}

run_all_scenarios
