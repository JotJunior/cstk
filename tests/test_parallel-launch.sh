#!/bin/sh
# test_parallel-launch.sh — cobre
# plugins/cstk/skills/agente-00c-runtime/scripts/parallel-launch.sh (tasks
# 2.3-2.5, feature roadmap-parallel-launch). Regra de ouro (tasks.md 2.5.4).
#
# Cobertura:
#   check-tmux: presente / ausente (exit 0 / exit 3)
#   emit: composicao automatica (com tmux) e degradada (sem tmux),
#         byte-comparabilidade do trecho `claude --name ... "..."` entre
#         os dois caminhos (contract §4, decisao de desenho)
#   emit: revalidacao de --feature (defesa em profundidade, contract §4.2)
#   emit: validacao de --coordinator-name (allowlist, nao afeta composicao)
#   emit: uso incorreto (--repo/--feature ausentes, flag desconhecida,
#         subcomando desconhecido)
#   guarda anti-duplicidade (TOCTOU-recompute, contract §4.2/2.6.4):
#         worktree ativa bloqueia (outcome=blocked-duplicate, feature
#         omitida da composicao); worktree encerrada libera
#   enforcement-log.jsonl: schema CHK125, scrub aplicado, best-effort
#   testes adversariais (2.7): nome de repo com espaco/aspa (quoting),
#         short-name malicioso (injecao) rejeitado pela revalidacao
#   -h/--help

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/parallel-launch.sh"

# _pl_path_without_tmux: PATH com APENAS um diretorio de shims contendo
# symlinks para os comandos que o SUT e o harness precisam — `tmux`
# deliberadamente de fora.
#
# GOTCHA (queimou a tag v8.2.0 no CI): a versao anterior removia do PATH o
# diretorio onde `command -v tmux` resolvia. Isso funciona no macOS
# (`/opt/homebrew/bin`), mas NAO no Ubuntu do runner: la `tmux` esta em
# `/usr/bin` e `/bin` e symlink de `/usr/bin`, entao remover um segmento
# deixa o outro resolvendo o mesmo binario — o cenario "sem tmux" media, na
# verdade, o caminho COM tmux. Allowlist explicita e a unica forma portatil
# de garantir ausencia (mesmo racional de
# `feedback_test_path_stub_cannot_hide_usrbin`).
_pl_path_without_tmux() {
  _shim="$TMPDIR_TEST/nobin"
  mkdir -p "$_shim"
  # Comandos externos usados por parallel-launch.sh (git/sed/awk/grep/date/
  # dirname/basename/mkdir/cat/tr/cut) + os que o harness usa dentro de `capture`
  # (mktemp/rm/sh/env). `tmux` NUNCA entra nesta lista.
  for _c in sh env git sed awk grep date dirname basename mkdir rm cat mktemp chmod ln find sort head tail tr wc cut; do
    _p=$(command -v "$_c" 2>/dev/null) || continue
    [ -e "$_shim/$_c" ] || ln -s "$_p" "$_shim/$_c" 2>/dev/null || :
  done
  printf '%s' "$_shim"
}

# _pl_git_repo DIR: inicializa repo git minimo em DIR (commit inicial).
_pl_git_repo() {
  _d="$1"
  mkdir -p "$_d"
  (
    cd "$_d" || exit 1
    git init -q .
    # Identidade LOCAL do repo: o runner de CI nao tem ~/.gitconfig, e sem
    # isso `git commit` aborta com "Author identity unknown" (mesmo padrao
    # ja usado por test_commit-mode.sh / test_state-rw.sh).
    git config user.email "test@test.local"
    git config user.name "cstk test"
    git commit -q --allow-empty -m init
  )
}

# ==== check-tmux ====

scenario_check_tmux_presente() {
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado nesta maquina — scenario pulado via ERROR"; return 2; }
  capture "$SCRIPT" check-tmux
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (tmux presente)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_check_tmux_ausente() {
  _fake=$(_pl_path_without_tmux)
  _old_path=$PATH
  PATH="$_fake"
  capture "$SCRIPT" check-tmux
  PATH=$_old_path
  [ "$_CAPTURED_EXIT" = 3 ] || { _fail "exit esperado 3 (tmux ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== emit: composicao automatica (tmux) ====

scenario_emit_composicao_com_tmux() {
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado"; return 2; }
  _repo="$TMPDIR_TEST/repo-tmux"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "cstk session start auth-basica" || return 1
  assert_stdout_contains "tmux split-window -c \"$_repo-auth-basica\" -P -F '#{pane_id}'" || return 1
  assert_stdout_contains "claude --name \"cstk-feature/auth-basica\" '/feature-00c \"auth-basica\" auth-basica'" || return 1
  # nunca new-window: a leva paralela vive em panes do window da coordenadora
  assert_stdout_not_contains "tmux new-window" || return 1
}

scenario_emit_multiplas_features_em_ordem() {
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado"; return 2; }
  _repo="$TMPDIR_TEST/repo-multi"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature primeira --feature segunda
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  _pos_primeira=$(printf '%s' "$_CAPTURED_STDOUT" | grep -n "session start primeira" | cut -d: -f1)
  _pos_segunda=$(printf '%s' "$_CAPTURED_STDOUT" | grep -n "session start segunda" | cut -d: -f1)
  [ -n "$_pos_primeira" ] && [ -n "$_pos_segunda" ] || { _fail "ambas as features deveriam aparecer" "$_CAPTURED_STDOUT"; return 1; }
  [ "$_pos_primeira" -lt "$_pos_segunda" ] || { _fail "ordem das features deveria ser preservada" "$_CAPTURED_STDOUT"; return 1; }
}

# ==== emit: composicao degradada (sem tmux) + byte-comparabilidade ====

scenario_emit_composicao_degradada_sem_tmux() {
  _fake=$(_pl_path_without_tmux)
  _repo="$TMPDIR_TEST/repo-degradado"
  mkdir -p "$_repo"

  _old_path=$PATH
  PATH="$_fake"
  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  PATH=$_old_path
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "cstk session start auth-basica" || return 1
  assert_stdout_not_contains "tmux new-window" || return 1
  assert_stdout_not_contains "tmux split-window" || return 1
  assert_stdout_contains "cd \"$_repo-auth-basica\" && claude --name \"cstk-feature/auth-basica\" '/feature-00c \"auth-basica\" auth-basica'" || return 1
}

scenario_emit_trecho_claude_identico_com_e_sem_tmux() {
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado"; return 2; }
  _repo="$TMPDIR_TEST/repo-comparavel"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (com tmux)" "obtido $_CAPTURED_EXIT"; return 1; }
  _com_tmux_trecho=$(printf '%s' "$_CAPTURED_STDOUT" | grep -o 'claude --name.*$')

  _fake=$(_pl_path_without_tmux)
  _old_path=$PATH
  PATH="$_fake"
  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  PATH=$_old_path
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (sem tmux)" "obtido $_CAPTURED_EXIT"; return 1; }
  _sem_tmux_trecho=$(printf '%s' "$_CAPTURED_STDOUT" | grep -o 'claude --name.*$')

  [ "$_com_tmux_trecho" = "$_sem_tmux_trecho" ] || {
    _fail "trecho claude --name deveria ser byte-identico" "com-tmux=[$_com_tmux_trecho] sem-tmux=[$_sem_tmux_trecho]"
    return 1
  }
}

# ==== emit: revalidacao de --feature (defesa em profundidade) ====

scenario_emit_feature_maiuscula_rejeitada() {
  _repo="$TMPDIR_TEST/repo-inv1"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo" --feature "Auth-Basica"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (feature maiuscula)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "invalido" || return 1
}

scenario_emit_feature_vazia_apos_flag_falta_valor() {
  _repo="$TMPDIR_TEST/repo-inv2"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo" --feature
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (--feature sem valor)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_emit_feature_maior_que_64_chars_rejeitada() {
  _repo="$TMPDIR_TEST/repo-inv3"
  mkdir -p "$_repo"
  _longo=$(printf 'a%.0s' $(seq 1 65))
  capture "$SCRIPT" emit --repo "$_repo" --feature "$_longo"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (feature > 64 chars)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== emit: --coordinator-name ====

scenario_emit_coordinator_name_valido_nao_altera_composicao() {
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado"; return 2; }
  _repo="$TMPDIR_TEST/repo-coord-ok"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica --coordinator-name "cstk-coord/meu-repo"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_not_contains "cstk-coord/meu-repo" || return 1
}

scenario_emit_coordinator_name_invalido_rejeitado() {
  _repo="$TMPDIR_TEST/repo-coord-bad"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica --coordinator-name "nome-qualquer"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (coordinator-name mal-formado)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "coordinator-name" || return 1
}

# ==== emit: uso incorreto ====

scenario_emit_sem_repo_exit2() {
  capture "$SCRIPT" emit --feature auth-basica
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (--repo ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_emit_sem_feature_exit2() {
  _repo="$TMPDIR_TEST/repo-sem-feature"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (--feature ausente)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_emit_flag_desconhecida_exit2() {
  _repo="$TMPDIR_TEST/repo-flag"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica --bogus-flag
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (flag desconhecida)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_subcomando_desconhecido_exit2() {
  capture "$SCRIPT" bogus-subcommand
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (subcomando desconhecido)" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_sem_subcomando_exit2() {
  capture "$SCRIPT"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (sem subcomando)" "obtido $_CAPTURED_EXIT"; return 1; }
}

# ==== guarda anti-duplicidade (TOCTOU-recompute, contract §4.2/2.6.4) ====

scenario_guarda_worktree_ativa_bloqueia() {
  command -v git >/dev/null 2>&1 || { _fail "pre-requisito ausente" "git nao encontrado"; return 2; }
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado"; return 2; }
  _repo="$TMPDIR_TEST/repo-guarda-ativa"
  _pl_git_repo "$_repo"
  (
    cd "$_repo" || exit 1
    git branch feature-ativa
    git worktree add -q "../repo-guarda-ativa-feature-ativa" feature-ativa
  )

  capture "$SCRIPT" emit --repo "$_repo" --feature feature-ativa --feature feature-livre
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (guarda bloqueia, nao aborta)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_not_contains "session start feature-ativa" || return 1
  assert_stdout_contains "session start feature-livre" || return 1
  assert_stderr_contains "feature-ativa" || return 1
  assert_stderr_contains "bloqueado" || return 1

  _log="$_repo/.claude/enforcement-log.jsonl"
  [ -f "$_log" ] || { _fail "enforcement-log.jsonl deveria existir" ""; return 1; }
  grep -q '"short_name":"feature-ativa".*"outcome":"blocked-duplicate"' "$_log" \
    || { _fail "log deveria conter outcome=blocked-duplicate para feature-ativa" "$(cat "$_log")"; return 1; }
  grep -q '"short_name":"feature-livre".*"outcome":"launched"' "$_log" \
    || { _fail "log deveria conter outcome=launched para feature-livre" "$(cat "$_log")"; return 1; }

  git -C "$_repo" worktree remove --force "../repo-guarda-ativa-feature-ativa" >/dev/null 2>&1 || :
}

scenario_guarda_worktree_encerrada_libera() {
  command -v git >/dev/null 2>&1 || { _fail "pre-requisito ausente" "git nao encontrado"; return 2; }
  _repo="$TMPDIR_TEST/repo-guarda-livre"
  _pl_git_repo "$_repo"
  # Nenhuma worktree criada para "feature-recuperada" — simula recuperacao
  # apos `cstk session end` (CHK006): a feature volta a ser candidata.

  capture "$SCRIPT" emit --repo "$_repo" --feature feature-recuperada
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains "session start feature-recuperada" || return 1
}

scenario_guarda_repo_invalido_nao_e_erro_fatal() {
  capture "$SCRIPT" emit --repo "$TMPDIR_TEST/repo-nao-existe" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "repo invalido nao deveria ser erro fatal" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "session start auth-basica" || return 1
}

# ==== enforcement-log.jsonl ====

scenario_enforcement_log_registra_launched() {
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado"; return 2; }
  _repo="$TMPDIR_TEST/repo-log-ok"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }

  _log="$_repo/.claude/enforcement-log.jsonl"
  [ -f "$_log" ] || { _fail "enforcement-log.jsonl deveria ter sido criado" ""; return 1; }
  grep -q '"source":"parallel-launch"' "$_log" || { _fail "campo source ausente" "$(cat "$_log")"; return 1; }
  grep -q '"outcome":"launched"' "$_log" || { _fail "outcome=launched ausente" "$(cat "$_log")"; return 1; }
  grep -q '"short_name":"auth-basica"' "$_log" || { _fail "short_name ausente" "$(cat "$_log")"; return 1; }
}

scenario_enforcement_log_registra_blocked_invalid_feature() {
  _repo="$TMPDIR_TEST/repo-log-invalid"
  mkdir -p "$_repo"
  capture "$SCRIPT" emit --repo "$_repo" --feature "INVALIDO"
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2" "obtido $_CAPTURED_EXIT"; return 1; }

  _log="$_repo/.claude/enforcement-log.jsonl"
  [ -f "$_log" ] || { _fail "enforcement-log.jsonl deveria ter sido criado mesmo em recusa" ""; return 1; }
  grep -q '"outcome":"blocked-invalid-feature"' "$_log" \
    || { _fail "outcome=blocked-invalid-feature ausente" "$(cat "$_log")"; return 1; }
}

# ==== emit: prompt no formato REAL de /feature-00c (descricao + short) ====
#
# Defeito corrigido: `/feature-00c <SHORT>` fazia o short-name ser lido
# como DESCRICAO pelo command (feature-00c.md:113-115) e o short-name real
# ser re-derivado pelo specify — divergindo da worktree/branch criada por
# `cstk session start <SHORT>`.

# Cria um roadmap minimo (contracts/roadmap-artifact.md §2) em REPO/docs.
_pl_write_roadmap() {
  mkdir -p "$1/docs"
  cat >"$1/docs/roadmap.md" <<'EOF'
# Roadmap: teste

## Features

### 1. auth-basica

- **short-name**: `auth-basica`
- **ordem**: 1
- **depende-de**: -

**Descricao**: Autenticacao por e-mail e senha, com sessao assinada
e recuperacao por link expiravel.

**Justificativa**: base das demais.

### 2. perfil-usuario

- **short-name**: `perfil-usuario`
- **ordem**: 2
- **depende-de**: `auth-basica`

**Descricao**: Edicao de perfil com "aspas", $VAR, `crase`, ; e | para
exercitar a sanitizacao.
EOF
}

scenario_emit_prompt_traz_descricao_do_roadmap() {
  _repo="$TMPDIR_TEST/repo-desc-roadmap"
  mkdir -p "$_repo"
  _pl_write_roadmap "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  assert_stdout_contains '/feature-00c "Autenticacao por e-mail e senha, com sessao assinada e recuperacao por link expiravel." auth-basica' || return 1
}

scenario_emit_prompt_pina_short_name_posicional() {
  _repo="$TMPDIR_TEST/repo-desc-pin"
  mkdir -p "$_repo"
  _pl_write_roadmap "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  # o short-name DEVE ser o ultimo token do prompt (2o posicional), nunca
  # o unico argumento
  assert_stdout_match "/feature-00c \"[^\"]+\" auth-basica'" || return 1
  assert_stdout_not_contains "/feature-00c auth-basica" || return 1
}

scenario_emit_description_explicita_vence_roadmap() {
  _repo="$TMPDIR_TEST/repo-desc-explicita"
  mkdir -p "$_repo"
  _pl_write_roadmap "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica --description "Descricao vinda do operador"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '/feature-00c "Descricao vinda do operador" auth-basica' || return 1
  assert_stdout_not_contains "Autenticacao por e-mail" || return 1
}

scenario_emit_description_pareia_com_a_feature_anterior() {
  _repo="$TMPDIR_TEST/repo-desc-pareia"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" \
    --feature primeira --description "Desc da primeira" \
    --feature segunda --description "Desc da segunda"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '/feature-00c "Desc da primeira" primeira' || return 1
  assert_stdout_contains '/feature-00c "Desc da segunda" segunda' || return 1
}

scenario_emit_description_sem_feature_antes_exit2() {
  _repo="$TMPDIR_TEST/repo-desc-orfa"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --description "orfa" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "exit esperado 2 (--description sem --feature antes)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains "--description" || return 1
}

scenario_emit_sem_roadmap_cai_no_short_name_com_aviso() {
  _repo="$TMPDIR_TEST/repo-desc-ausente"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (ausencia de descricao NAO e erro)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '/feature-00c "auth-basica" auth-basica' || return 1
  assert_stderr_contains "descricao ausente" || return 1
}

scenario_emit_roadmap_explicito_inexistente_nao_aborta() {
  _repo="$TMPDIR_TEST/repo-desc-roadmap-inexistente"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica --roadmap "$TMPDIR_TEST/nao-existe.md"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (roadmap inexistente e best-effort)" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '/feature-00c "auth-basica" auth-basica' || return 1
}

scenario_adversarial_descricao_do_roadmap_sanitizada() {
  _repo="$TMPDIR_TEST/repo-desc-adversarial"
  mkdir -p "$_repo"
  _pl_write_roadmap "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature perfil-usuario
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  # nenhuma aspa (simples ou dupla), crase, $ ou metacaractere de shell
  # pode sobreviver dentro do envelope '/feature-00c "..." <short>'
  _prompt=$(printf '%s' "$_CAPTURED_STDOUT" | sed -n "s/.*'\\/feature-00c \"\\(.*\\)\" perfil-usuario'.*/\\1/p")
  [ -n "$_prompt" ] || { _fail "prompt nao casou o envelope esperado" "$_CAPTURED_STDOUT"; return 1; }
  case "$_prompt" in
    *'"'*|*"'"*|*'`'*|*'$'*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*"\\"*)
      _fail "descricao do roadmap deveria estar sanitizada" "[$_prompt]"; return 1 ;;
  esac
}

scenario_adversarial_descricao_explicita_com_injecao_sanitizada() {
  _repo="$TMPDIR_TEST/repo-desc-inj"
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica \
    --description "fecha'; rm -rf / #\$(whoami) \`id\`"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_not_contains "\$(whoami)" || return 1
  assert_stdout_not_contains '`id`' || return 1
  # o envelope de aspas simples permanece integro (fecha so no fim)
  assert_stdout_match "claude --name \"cstk-feature/auth-basica\" '/feature-00c \"[^']*\" auth-basica'" || return 1
}

scenario_emit_descricao_truncada_em_300_chars() {
  _repo="$TMPDIR_TEST/repo-desc-longa"
  mkdir -p "$_repo"
  _longa=$(printf 'a%.0s' $(seq 1 400))

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica --description "$_longa"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  _prompt=$(printf '%s' "$_CAPTURED_STDOUT" | sed -n "s/.*'\\/feature-00c \"\\(.*\\)\" auth-basica'.*/\\1/p")
  _len=$(printf '%s' "$_prompt" | wc -c | tr -d ' ')
  [ "$_len" = 300 ] || { _fail "descricao deveria ser truncada a 300 chars" "obtido $_len"; return 1; }
}

# ==== testes adversariais de injecao (2.7) ====

scenario_adversarial_nome_de_repo_com_espaco_e_aspa() {
  command -v tmux >/dev/null 2>&1 || { _fail "pre-requisito ausente" "tmux nao instalado"; return 2; }
  _repo="$TMPDIR_TEST/repo com espaco e \"aspa\""
  mkdir -p "$_repo"

  capture "$SCRIPT" emit --repo "$_repo" --feature auth-basica
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (repo com espaco/aspa e valor legitimo, nao ataque de sintaxe)" "obtido $_CAPTURED_EXIT; stderr=$_CAPTURED_STDERR"; return 1; }
  # <WORKTREE> MUST estar entre aspas duplas (contract §4.1, INV-7) — a
  # aspa interna do nome do repo NAO deve fechar a aspa do -c prematuramente:
  # a linha inteira continua sendo um UNICO argumento entre -c "..." e -P.
  assert_stdout_match '\-c "[^"]*repo com espaco e .aspa.[^"]*-auth-basica" -P -F' || return 1
}

scenario_adversarial_short_name_malicioso_rejeitado() {
  _repo="$TMPDIR_TEST/repo-adv-short"
  mkdir -p "$_repo"

  for _malicioso in '$(rm -rf /)' 'auth; rm -rf /' 'auth`whoami`' '../../etc/passwd' 'auth basica' 'AUTH-BASICA'; do
    capture "$SCRIPT" emit --repo "$_repo" --feature "$_malicioso"
    [ "$_CAPTURED_EXIT" = 2 ] || { _fail "short-name malicioso deveria ser rejeitado (exit 2)" "valor=[$_malicioso] obtido=$_CAPTURED_EXIT stdout=$_CAPTURED_STDOUT"; return 1; }
    assert_stdout_not_contains "$_malicioso" || { _fail "valor malicioso nao deveria vazar para stdout" "$_malicioso"; return 1; }
  done
}

# ==== -h/--help ====

scenario_help_exit0() {
  capture "$SCRIPT" -h
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "Uso: parallel-launch.sh emit" || return 1
}

scenario_help_declara_superficie_real_sem_exec() {
  capture "$SCRIPT" --help
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains "check-tmux" || return 1
  assert_stdout_not_contains "--exec" || return 1
}

# ==== resolve-offer (feature roadmap-wave, contract roadmap-wave-command.md
# §3; quickstart.md C8-C11, C17) ====

scenario_resolve_offer_absent_ignora_confirm_e_max() {
  # C8 (FR-014): sem operador, sem lancamento — --confirm/--max ignorados
  # por completo, mesmo com valores sintaticamente validos.
  capture "$SCRIPT" resolve-offer --source absent --confirm sim --max 5
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "launch=no
max=2" ] || { _fail "esperado launch=no/max=2" "obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_resolve_offer_absent_sem_flags() {
  capture "$SCRIPT" resolve-offer --source absent
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "launch=no
max=2" ] || { _fail "esperado launch=no/max=2" "obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_resolve_offer_operator_confirm_valido_max_explicito() {
  # C9 (FR-012/FR-013)
  capture "$SCRIPT" resolve-offer --source operator --confirm sim --max 3
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "launch=yes
max=3" ] || { _fail "esperado launch=yes/max=3" "obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_resolve_offer_operator_confirm_valido_max_omitido_default_2() {
  capture "$SCRIPT" resolve-offer --source operator --confirm sim
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "launch=yes
max=2" ] || { _fail "esperado launch=yes/max=2" "obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_resolve_offer_todos_os_tokens_do_enum_de_confirmacao() {
  for _c in s S y Y sim yes; do
    capture "$SCRIPT" resolve-offer --source operator --confirm "$_c"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 para confirm=$_c" "obtido $_CAPTURED_EXIT"; return 1; }
    case "$_CAPTURED_STDOUT" in
      "launch=yes"*) : ;;
      *) _fail "confirm=$_c deveria dar launch=yes" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
    esac
  done
}

scenario_resolve_offer_max_mal_formado_fail_closed() {
  # C10 (FR-007)
  for _m in abc 0 -1; do
    capture "$SCRIPT" resolve-offer --source operator --confirm sim --max "$_m"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (recusar nao e erro) para max=$_m" "obtido $_CAPTURED_EXIT"; return 1; }
    case "$_CAPTURED_STDOUT" in
      "launch=no"*) : ;;
      *) _fail "max=$_m deveria dar launch=no" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
    esac
    assert_stderr_contains "--max invalido" || return 1
  done
}

scenario_resolve_offer_max_fora_da_faixa_999() {
  # C17
  capture "$SCRIPT" resolve-offer --source operator --confirm sim --max 999
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    "launch=no"*) : ;;
    *) _fail "max=999 deveria dar launch=no" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
  assert_stderr_contains "--max invalido" || return 1
}

scenario_resolve_offer_max_limite_superior_8_aceito() {
  capture "$SCRIPT" resolve-offer --source operator --confirm sim --max 8
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "launch=yes
max=8" ] || { _fail "esperado launch=yes/max=8" "obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_resolve_offer_higiene_crlf_no_confirm() {
  # C11 (contract §3.4) — mesma classe de bug corrigida em
  # delivery-tier.sh:306-307: $() nao remove \r.
  capture "$SCRIPT" resolve-offer --source operator --confirm "$(printf 'sim\r')"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  case "$_CAPTURED_STDOUT" in
    "launch=yes"*) : ;;
    *) _fail "confirm=sim\\r deveria dar launch=yes (CRLF removido)" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
  esac
}

scenario_resolve_offer_higiene_crlf_no_max() {
  capture "$SCRIPT" resolve-offer --source operator --confirm sim --max "$(printf '4\r')"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0" "obtido $_CAPTURED_EXIT"; return 1; }
  [ "$_CAPTURED_STDOUT" = "launch=yes
max=4" ] || { _fail "esperado launch=yes/max=4 (CRLF removido)" "obtido: $_CAPTURED_STDOUT"; return 1; }
}

scenario_resolve_offer_confirm_fora_do_enum_inclusive_vazio() {
  for _c in "" "n" "N" "nao" "talvez" "  "; do
    capture "$SCRIPT" resolve-offer --source operator --confirm "$_c"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 para confirm='$_c'" "obtido $_CAPTURED_EXIT"; return 1; }
    case "$_CAPTURED_STDOUT" in
      "launch=no"*) : ;;
      *) _fail "confirm='$_c' deveria dar launch=no" "obtido: $_CAPTURED_STDOUT"; return 1 ;;
    esac
  done
}

scenario_resolve_offer_source_obrigatorio_exit2() {
  capture "$SCRIPT" resolve-offer --confirm sim
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "esperado exit 2 sem --source" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_resolve_offer_source_fora_do_enum_exit2() {
  capture "$SCRIPT" resolve-offer --source talvez
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "esperado exit 2 para --source invalido" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_resolve_offer_flag_desconhecida_exit2() {
  capture "$SCRIPT" resolve-offer --source operator --bogus x
  [ "$_CAPTURED_EXIT" = 2 ] || { _fail "esperado exit 2 para flag desconhecida" "obtido $_CAPTURED_EXIT"; return 1; }
}

scenario_resolve_offer_saida_e_sempre_duas_linhas_chave_valor() {
  # Formato contrato §3.3: sem jq, sempre launch=<yes|no> + max=<inteiro>.
  for _src in operator absent; do
    for _c in "" sim nao "rm -rf /"; do
      capture "$SCRIPT" resolve-offer --source "$_src" --confirm "$_c"
      [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit esperado 0 (src=$_src confirm='$_c')" "obtido $_CAPTURED_EXIT"; return 1; }
      _n_linhas=$(printf '%s\n' "$_CAPTURED_STDOUT" | wc -l | tr -d ' ')
      [ "$_n_linhas" = 2 ] || { _fail "esperado exatamente 2 linhas (src=$_src confirm='$_c')" "obtido $_n_linhas: $_CAPTURED_STDOUT"; return 1; }
      printf '%s\n' "$_CAPTURED_STDOUT" | grep -qE '^launch=(yes|no)$' \
        || { _fail "linha 1 fora do formato launch=<yes|no> (src=$_src confirm='$_c')" "obtido: $_CAPTURED_STDOUT"; return 1; }
      printf '%s\n' "$_CAPTURED_STDOUT" | grep -qE '^max=[0-9]+$' \
        || { _fail "linha 2 fora do formato max=<inteiro> (src=$_src confirm='$_c')" "obtido: $_CAPTURED_STDOUT"; return 1; }
    done
  done
}

run_all_scenarios
