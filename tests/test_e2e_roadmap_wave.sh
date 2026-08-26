#!/bin/sh
# test_e2e_roadmap_wave.sh — e2e deterministico da CADEIA da leva paralela
# pos-roadmap (Camada B do plano de e2e; equivalente ao
# test_e2e_model_routing.sh para a orquestracao paralela).
#
# Features cobertas em COMPOSICAO (cada elo ja tem cobertura unitaria):
#   roadmap-parallel-launch + roadmap-wave + cstk-session +
#   session-end-state-preservation
# Ref: docs/specs/roadmap-parallel-launch/contracts/parallel-launch.md §4/§6
#      docs/specs/roadmap-parallel-launch/contracts/roadmap-frontier.md §4/§5
#      docs/specs/roadmap-wave/contracts/roadmap-wave-command.md §3
#      docs/specs/roadmap-mode/contracts/roadmap-artifact.md §5
#      CLAUDE.md §"Modo roadmap + leva paralela de features"
#
# O que este arquivo valida que NENHUM teste unitario valida: a corrente
# inteira que o command pai executa em producao —
#
#   frontier --json -> resolve-offer -> emit -> `cstk session start` REAL
#   -> sessao-filha executa na worktree (stub de `claude` dirigindo o
#   runtime REAL state-rw.sh init modo-feature) -> notificacao
#   [cstk-parallel] parseada fail-closed -> merge do resultado -> `cstk
#   session end` preserva o state 00c no checkout principal -> fronteira
#   recalculada desbloqueia a entrada dependente do roadmap.
#
# Estrategia de stubs (deterministico, sem modelo no loop):
#   - `claude` e substituido por script em $TMPDIR_TEST/bin que simula a
#     sessao-filha /feature-00c: invoca o state-rw.sh REAL (init
#     modo-feature), materializa docs/specs/<short>/ com tasks 100%
#     concluidas, commita na branch da sessao e emite a linha de
#     notificacao do contrato §6 num mailbox em disco.
#   - `cstk` e um wrapper para $REPO_ROOT/cli/cstk com CSTK_LIB fixado
#     (mesma tecnica de tests/cstk/test_session.sh) — as linhas emitidas
#     por `parallel-launch.sh emit` sao executadas TAL-E-QUAL impressas.
#   - `gh` e um stub que falha (exit 1): o PR-check do `session end` vira
#     "pulado" deterministicamente (FR-005 e best-effort), independente do
#     gh/auth da maquina.
#   - HOME e sandboxado ao invocar filhas => state-backend resolve sempre
#     "json" (nunca-configurado), independente da config global do operador.
#   - tmux NAO e stubado nem escondido (PATH-stub nao esconde binario de
#     sistema — gotcha conhecido): o cenario de janela usa tmux REAL em
#     socket privado (-L) + -f /dev/null, e os demais cenarios extraem da
#     saida do emit a composicao `claude --name ...` (byte-identica nas
#     duas formas, contract §4) em vez de depender da forma tmux/degradada
#     do ambiente corrente.
#
# Dependencias: git, jq (deps ja exigidas pela suite), shasum|sha256sum.
# O cenario de tmux e condicional: sem tmux no ambiente, PASS com aviso
# (a composicao claude ja foi validada nos cenarios deterministicos).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK_BIN="$REPO_ROOT/cli/cstk"
CSTK_LIB="$REPO_ROOT/cli/lib"
RUNTIME_DIR="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
REVIEW_DIR="$REPO_ROOT/plugins/cstk/skills/review-features/scripts"
FRONTIER="$REVIEW_DIR/roadmap-frontier.sh"
RSTATUS="$REVIEW_DIR/roadmap-status.sh"
PLAUNCH="$RUNTIME_DIR/parallel-launch.sh"
PNPARSE="$RUNTIME_DIR/parallel-notification-parse.sh"

# ==== Setup compartilhado ====
#
# _setup_toy: monta em $TMPDIR_TEST o projeto-alvo de brinquedo + stubs.
# Define/exporta: _PHYS _REPO _STUB_BIN E2E_HOME E2E_MAILBOX E2E_MARKER_DIR
# E2E_REPO_NAME E2E_RUNTIME_DIR.
# Roadmap DAG: feat-alpha e feat-beta sem deps; feat-gamma depende de
# feat-alpha (contracts/roadmap-artifact.md §3).
_setup_toy() {
  _PHYS=$(cd "$TMPDIR_TEST" && pwd -P) || { _error "pwd" "pwd -P falhou"; return 2; }
  _REPO="$_PHYS/proj"
  _STUB_BIN="$_PHYS/bin"
  E2E_HOME="$_PHYS/home"
  E2E_MAILBOX="$_PHYS/mailbox.txt"
  E2E_MARKER_DIR="$_PHYS/markers"
  E2E_REPO_NAME="proj"
  E2E_RUNTIME_DIR="$RUNTIME_DIR"
  export E2E_HOME E2E_MAILBOX E2E_MARKER_DIR E2E_REPO_NAME E2E_RUNTIME_DIR

  mkdir -p "$_REPO/docs" "$_STUB_BIN" "$E2E_HOME" "$E2E_MARKER_DIR"
  : > "$E2E_MAILBOX"

  ( cd "$_REPO" \
    && git init -q -b main \
    && git config user.email e2e@example.com \
    && git config user.name "E2E" ) || { _error "git" "init do repo falhou"; return 2; }

  printf '.claude/\n' > "$_REPO/.gitignore"
  printf '# Briefing\n\nProjeto de brinquedo para e2e da leva paralela.\n' \
    > "$_REPO/docs/briefing.md"
  printf '# Constitution\n\nVersao: 1.0.0\n' > "$_REPO/docs/constitution.md"
  cat > "$_REPO/docs/roadmap.md" <<'EOF'
# Roadmap

### 1. feat-alpha
- **depende-de**: -

Fundacao alpha do projeto de brinquedo.

### 2. feat-beta
- **depende-de**: -

Fundacao beta, independente de alpha.

### 3. feat-gamma
- **depende-de**: `feat-alpha`

Consome a fundacao alpha.
EOF
  ( cd "$_REPO" && git add -A && git commit -q -m "seed projeto de brinquedo" ) \
    || { _error "git" "commit seed falhou"; return 2; }

  # stub `cstk`: wrapper para o binario real com CSTK_LIB fixado — permite
  # executar a linha `cstk session start <short>` TAL-E-QUAL emitida.
  cat > "$_STUB_BIN/cstk" <<EOF
#!/bin/sh
CSTK_LIB="$CSTK_LIB"
export CSTK_LIB
exec sh "$CSTK_BIN" "\$@"
EOF

  # stub `gh`: falha sempre => PR-check do session end deterministicamente
  # "pulado" (best-effort, FR-005), independente do gh real da maquina.
  cat > "$_STUB_BIN/gh" <<'EOF'
#!/bin/sh
exit 1
EOF

  # stub `claude`: simula a sessao-filha /feature-00c dirigindo o runtime
  # REAL. Composicao invocante (contract §4.1, byte-identica tmux/degradado):
  #   claude --name "cstk-feature/<short>" '/feature-00c "<DESCRICAO>" <short>'
  # O short-name e o SEGUNDO posicional (o primeiro e a descricao) — o stub
  # so aceita esse formato: se o emit regredir para `/feature-00c <short>`,
  # o parse falha (exit 64) e o e2e quebra, que e o efeito desejado.
  cat > "$_STUB_BIN/claude" <<'EOF'
#!/bin/sh
set -eu
short=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      [ $# -ge 2 ] || exit 64
      shift 2 ;;
    "/feature-00c "*)
      # prompt = /feature-00c "<DESCRICAO>" <short>
      _rest=${1#/feature-00c }
      case "$_rest" in
        '"'*)
          _rest=${_rest#\"}       # remove aspa inicial da descricao
          desc=${_rest%%\"*}      # descricao (nao usada pelo stub)
          _rest=${_rest#*\"}      # sobra: ` <short>`
          short=${_rest# }
          ;;
        *) exit 64 ;;             # formato antigo (`/feature-00c <short>`)
      esac
      [ -n "${desc:-}" ] || exit 64
      shift ;;
    *) shift ;;
  esac
done
[ -n "$short" ] || exit 64

_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# HOME sandboxado: state-backend resolve "json" (nunca-configurado),
# independente da config global do operador.
HOME="$E2E_HOME"
export HOME

sd=".claude/feature-00c-state/$short"
sh "$E2E_RUNTIME_DIR/state-rw.sh" init \
  --state-dir "$sd" \
  --short-name "$short" \
  --projeto-alvo-path "$PWD" \
  --descricao "sessao-filha e2e $short" \
  --briefing-path docs/briefing.md \
  --briefing-sha256 "$(_sha docs/briefing.md)" \
  --constitution-path docs/constitution.md \
  --constitution-sha256 "$(_sha docs/constitution.md)" \
  --constitution-version "1.0.0" >/dev/null

mkdir -p "docs/specs/$short"
printf '# Spec %s\n' "$short" > "docs/specs/$short/spec.md"
printf '# Plan %s\n' "$short" > "docs/specs/$short/plan.md"
printf '# Tasks %s\n\n- [x] T001 implementacao concluida (e2e stub)\n' "$short" \
  > "docs/specs/$short/tasks.md"
git add "docs/specs/$short"
git commit -q -m "feat($short): specs concluidas (e2e stub)"

printf '[cstk-parallel] feature=%s outcome=concluida repo=%s\n' \
  "$short" "$E2E_REPO_NAME" >> "$E2E_MAILBOX"
: > "$E2E_MARKER_DIR/$short.done"

# Linger opcional: mantem a janela tmux viva para o assert do kill switch.
[ -n "${E2E_STUB_LINGER:-}" ] && sleep "$E2E_STUB_LINGER"
exit 0
EOF
  chmod +x "$_STUB_BIN/cstk" "$_STUB_BIN/gh" "$_STUB_BIN/claude"
  return 0
}

# _run_in_repo CMD...: executa no repo coordenador com PATH dos stubs na
# frente (claude/cstk/gh resolvem para os stubs; git e o real).
_run_in_repo() {
  _rir_cmd=$1
  capture env PATH="$_STUB_BIN:$PATH" HOME="$E2E_HOME" \
    sh -c "cd '$_REPO' && $_rir_cmd"
}

# _wait_file FILE MAX_DECISECONDS: espera FILE existir; exit 1 se estourar.
_wait_file() {
  _wf_i=0
  while [ "$_wf_i" -lt "$2" ]; do
    [ -f "$1" ] && return 0
    sleep 0.2
    _wf_i=$((_wf_i + 1))
  done
  [ -f "$1" ]
}

# _extract_claude_part EMIT_OUT SHORT: extrai a composicao `claude --name
# ...` da feature SHORT — byte-identica nas formas tmux e degradada
# (contract §4, decisao de desenho), entao o e2e nao depende de qual forma
# o ambiente corrente produz.
_extract_claude_part() {
  printf '%s\n' "$1" \
    | grep -o "claude --name \"cstk-feature/$2\".*\$" \
    | head -1
}

# ==== Cenario 1: fronteira inicial + resolve-offer ====

scenario_fronteira_inicial_e_resolve_offer() {
  _setup_toy || return 2

  # Fronteira inicial: alpha e beta elegiveis (sem deps, nao-iniciada);
  # gamma NAO (dependencia feat-alpha nao esta concluida).
  capture sh -c "cd '$_REPO' && sh '$FRONTIER' --json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "frontier: esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"short_name":"feat-alpha"' || return 1
  assert_stdout_contains '"short_name":"feat-beta"' || return 1
  assert_stdout_not_contains '"short_name":"feat-gamma"' || return 1

  # resolve-offer: operador confirma => launch=yes com teto default 2.
  capture sh "$PLAUNCH" resolve-offer --source operator --confirm y
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "resolve-offer: esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains 'launch=yes' || return 1
  assert_stdout_contains 'max=2' || return 1

  # Sem operador (headless/cron): fail-safe, nunca lanca (FR-014).
  capture sh "$PLAUNCH" resolve-offer --source absent
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "resolve-offer absent: esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains 'launch=no' || return 1
}

# ==== Cenario 2: a corrente inteira (caminho deterministico) ====

scenario_corrente_completa_leva_paralela() {
  _setup_toy || return 2

  # -- emit para as 2 elegiveis --
  capture sh "$PLAUNCH" emit --repo "$_REPO" \
    --feature feat-alpha --feature feat-beta
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "emit: esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  _emit_out=$_CAPTURED_STDOUT
  assert_stdout_contains 'cstk session start feat-alpha' || return 1
  assert_stdout_contains 'cstk session start feat-beta' || return 1
  # Composicao da filha presente para ambas, independente da forma
  # (tmux/degradada) do ambiente corrente.
  for _s in feat-alpha feat-beta; do
    _cp=$(_extract_claude_part "$_emit_out" "$_s")
    [ -n "$_cp" ] || { _fail "emit" "composicao claude ausente para $_s"; return 1; }
  done
  # Auditoria: 2 lancamentos no enforcement-log do repo coordenador.
  _launched=$(grep -c '"outcome":"launched"' "$_REPO/.claude/enforcement-log.jsonl" 2>/dev/null || echo 0)
  [ "$_launched" = 2 ] || { _fail "log" "esperado 2 outcome=launched, obtido $_launched"; return 1; }

  # -- executar as linhas `cstk session start` TAL-E-QUAL emitidas --
  printf '%s\n' "$_emit_out" | grep '^cstk session start ' | while IFS= read -r _l1; do
    env PATH="$_STUB_BIN:$PATH" HOME="$E2E_HOME" \
      sh -c "cd '$_REPO' && $_l1" >/dev/null 2>&1 || exit 1
  done || { _fail "session-start" "linha emitida de session start falhou"; return 1; }
  for _s in feat-alpha feat-beta; do
    [ -d "$_PHYS/proj-$_s" ] || { _fail "worktree" "worktree proj-$_s nao criada"; return 1; }
    ( cd "$_REPO" && git show-ref --verify -q "refs/heads/$_s" ) \
      || { _fail "branch" "branch $_s nao criada"; return 1; }
  done

  # -- TOCTOU: re-emit com worktrees ativas => tudo bloqueado, stdout vazio --
  capture sh "$PLAUNCH" emit --repo "$_REPO" \
    --feature feat-alpha --feature feat-beta
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "re-emit: esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "toctou" "re-emit deveria ter stdout vazio (tudo duplicado)"; return 1; }
  assert_stderr_contains 'bloqueado' || return 1
  _blocked=$(grep -c '"outcome":"blocked-duplicate"' "$_REPO/.claude/enforcement-log.jsonl" 2>/dev/null || echo 0)
  [ "$_blocked" = 2 ] || { _fail "log" "esperado 2 blocked-duplicate, obtido $_blocked"; return 1; }

  # -- fronteira com exclusao de ativas: vazia (alpha/beta ativas; gamma
  #    ainda depende de alpha nao-concluida) --
  capture sh -c "cd '$_REPO' && sh '$FRONTIER' --json --exclude-active-from-repo ."
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "frontier excluida: esperado 0, obtido $_CAPTURED_EXIT"; return 1; }
  assert_stderr_contains 'nenhuma feature elegivel' || return 1

  # -- sessoes-filha executam (stub claude dirige o runtime REAL) --
  for _s in feat-alpha feat-beta; do
    _cp=$(_extract_claude_part "$_emit_out" "$_s")
    capture env PATH="$_STUB_BIN:$PATH" HOME="$E2E_HOME" \
      sh -c "cd '$_PHYS/proj-$_s' && $_cp"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "filha" "filha $_s falhou (exit $_CAPTURED_EXIT): $_CAPTURED_STDERR"; return 1; }
    [ -f "$E2E_MARKER_DIR/$_s.done" ] || { _fail "filha" "marker de $_s ausente"; return 1; }
    # state 00c REAL criado pelo state-rw.sh init na worktree
    _sj="$_PHYS/proj-$_s/.claude/feature-00c-state/$_s/state.json"
    [ -f "$_sj" ] || { _fail "state" "state.json ausente em $_s"; return 1; }
    _sn=$(jq -r '.short_name' "$_sj" 2>/dev/null)
    [ "$_sn" = "$_s" ] || { _fail "state" "short_name esperado $_s, obtido '$_sn'"; return 1; }
    # specs commitadas na branch da sessao, worktree limpa
    [ -z "$(git -C "$_PHYS/proj-$_s" status --porcelain)" ] \
      || { _fail "filha" "worktree $_s suja apos commit do stub"; return 1; }
  done

  # -- notificacao [cstk-parallel]: parse fail-closed (contract §6) --
  _n_msgs=$(wc -l < "$E2E_MAILBOX" | tr -d ' ')
  [ "$_n_msgs" = 2 ] || { _fail "mailbox" "esperado 2 notificacoes, obtido $_n_msgs"; return 1; }
  while IFS= read -r _msg; do
    capture sh "$PNPARSE" check "$_msg"
    [ "$_CAPTURED_EXIT" = 0 ] || { _fail "parse" "notificacao legitima recusada: $_msg"; return 1; }
    assert_stdout_contains 'outcome=concluida' || return 1
    assert_stdout_contains "repo=$E2E_REPO_NAME" || return 1
  done < "$E2E_MAILBOX"
  # Forjada (sobra de texto) => recusada sem imprimir nada (ASI07).
  capture sh "$PNPARSE" check '[cstk-parallel] feature=feat-alpha outcome=concluida repo=proj EXTRA'
  [ "$_CAPTURED_EXIT" = 1 ] || { _fail "parse" "mensagem forjada aceita (exit $_CAPTURED_EXIT)"; return 1; }
  [ -z "$_CAPTURED_STDOUT" ] || { _fail "parse" "mensagem forjada produziu stdout"; return 1; }

  # -- alpha: merge (simula PR mergeado) + session end preserva state --
  ( cd "$_REPO" && git merge -q --no-edit feat-alpha >/dev/null 2>&1 ) \
    || { _fail "merge" "merge de feat-alpha falhou"; return 1; }
  _run_in_repo "cstk session end feat-alpha"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "session end feat-alpha: exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  [ ! -d "$_PHYS/proj-feat-alpha" ] || { _fail "end" "worktree feat-alpha ainda existe"; return 1; }
  if ( cd "$_REPO" && git show-ref --verify -q refs/heads/feat-alpha ); then
    _fail "end" "branch feat-alpha nao removida"; return 1
  fi
  # Preservacao do state 00c no checkout principal (session-end-state-preservation)
  _psj="$_REPO/.claude/feature-00c-state/feat-alpha/state.json"
  [ -f "$_psj" ] || { _fail "preserve" "state 00c de feat-alpha nao preservado no principal"; return 1; }
  _psn=$(jq -r '.short_name' "$_psj" 2>/dev/null)
  [ "$_psn" = "feat-alpha" ] || { _fail "preserve" "state preservado corrompido (short_name='$_psn')"; return 1; }

  # -- status derivado + fronteira recalculada --
  # alpha concluida (specs mergeadas, tasks 100%); beta segue nao-iniciada
  # NO PRINCIPAL (specs so na branch da worktree ativa) — exatamente o caso
  # que exige --exclude-active-from-repo (FR-011).
  capture sh -c "cd '$_REPO' && sh '$RSTATUS' --json"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "roadmap-status: exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"short_name":"feat-alpha","status":"concluida"' || return 1
  assert_stdout_contains '"short_name":"feat-beta","status":"nao-iniciada"' || return 1

  capture sh -c "cd '$_REPO' && sh '$FRONTIER' --json"
  assert_stdout_contains '"short_name":"feat-beta"' || return 1
  assert_stdout_contains '"short_name":"feat-gamma"' || return 1

  capture sh -c "cd '$_REPO' && sh '$FRONTIER' --json --exclude-active-from-repo ."
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "frontier pos-alpha: exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"short_name":"feat-gamma"' || return 1
  assert_stdout_not_contains '"short_name":"feat-beta"' || return 1

  # -- beta: mesmo fechamento; fronteira final = so gamma --
  ( cd "$_REPO" && git merge -q --no-edit feat-beta >/dev/null 2>&1 ) \
    || { _fail "merge" "merge de feat-beta falhou"; return 1; }
  _run_in_repo "cstk session end feat-beta"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "end" "session end feat-beta: exit $_CAPTURED_EXIT: $_CAPTURED_STDERR"; return 1; }
  [ -f "$_REPO/.claude/feature-00c-state/feat-beta/state.json" ] \
    || { _fail "preserve" "state 00c de feat-beta nao preservado"; return 1; }

  capture sh -c "cd '$_REPO' && sh '$RSTATUS' --json"
  assert_stdout_contains '"short_name":"feat-beta","status":"concluida"' || return 1
  assert_stdout_contains '"short_name":"feat-gamma","status":"nao-iniciada"' || return 1

  capture sh -c "cd '$_REPO' && sh '$FRONTIER' --json --exclude-active-from-repo ."
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "frontier final: exit $_CAPTURED_EXIT"; return 1; }
  assert_stdout_contains '"short_name":"feat-gamma"' || return 1
  assert_stdout_not_contains '"short_name":"feat-alpha"' || return 1
  assert_stdout_not_contains '"short_name":"feat-beta"' || return 1
}

# ==== Cenario 3: pane tmux REAL (condicional) ====
#
# Valida o caminho automatico (US1): a linha `tmux split-window ...` emitida
# e executada DENTRO de um servidor tmux privado (-L socket proprio,
# -f /dev/null — nunca toca o servidor do operador), a filha roda o stub
# de claude ate produzir o marker, e o kill switch documentado
# (`tmux kill-pane -t <pane_id>`) encerra o pane. A filha entra como pane
# irmao no window ja existente — nenhum window novo e criado. Sem tmux no ambiente: PASS com
# aviso (a composicao claude ja foi validada no cenario 2, que e
# forma-agnostica por contrato).
scenario_tmux_pane_real_e_kill_switch() {
  if ! command -v tmux >/dev/null 2>&1; then
    printf '  # tmux ausente — cenario condicional pulado (composicao coberta pelo cenario 2)\n'
    return 0
  fi
  _setup_toy || return 2
  _SOCK="cstk-e2e-$$"
  _tmux_kill() { tmux -L "$_SOCK" kill-server 2>/dev/null || :; }

  # emit COM tmux presente => forma tmux garantida.
  capture sh "$PLAUNCH" emit --repo "$_REPO" --feature feat-alpha
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "exit" "emit: exit $_CAPTURED_EXIT"; return 1; }
  _emit_out=$_CAPTURED_STDOUT
  assert_stdout_contains 'tmux split-window' || return 1
  assert_stdout_not_contains 'tmux new-window' || return 1
  _l1=$(printf '%s\n' "$_emit_out" | grep '^cstk session start ')
  env PATH="$_STUB_BIN:$PATH" HOME="$E2E_HOME" sh -c "cd '$_REPO' && $_l1" >/dev/null 2>&1 \
    || { _fail "session-start" "session start feat-alpha falhou"; return 1; }

  # Bloco tmux emitido (linha com continuacao \) vira script executado
  # DENTRO do servidor privado — mesmo ambiente do command pai em producao
  # (que roda dentro de tmux).
  printf '%s\n' "$_emit_out" | grep -v '^cstk session start ' > "$_PHYS/launch.sh"

  E2E_STUB_LINGER=20
  export E2E_STUB_LINGER
  env PATH="$_STUB_BIN:$PATH" HOME="$E2E_HOME" \
      E2E_HOME="$E2E_HOME" E2E_MAILBOX="$E2E_MAILBOX" \
      E2E_MARKER_DIR="$E2E_MARKER_DIR" E2E_REPO_NAME="$E2E_REPO_NAME" \
      E2E_RUNTIME_DIR="$E2E_RUNTIME_DIR" E2E_STUB_LINGER="$E2E_STUB_LINGER" \
    tmux -L "$_SOCK" -f /dev/null new-session -d -s boot /bin/sh \
    || { _fail "tmux" "nao consegui subir servidor tmux privado"; return 1; }

  # Panes ANTES do split (a filha entra como pane irmao no MESMO window —
  # `split-window`, nunca `new-window`).
  _panes_before=$(tmux -L "$_SOCK" list-panes -t boot -F '#{pane_id}' 2>/dev/null)

  tmux -L "$_SOCK" send-keys -t boot "sh '$_PHYS/launch.sh'" Enter \
    || { _tmux_kill; _fail "tmux" "send-keys falhou"; return 1; }

  if ! _wait_file "$E2E_MARKER_DIR/feat-alpha.done" 100; then
    _tmux_kill
    _fail "tmux" "filha na janela tmux nao produziu marker em 20s"
    return 1
  fi

  # Pane novo no MESMO window (linger mantem vivo) + kill switch por pane.
  # `split-window` nao nomeia window (nao tem `-n`): a identificacao e o
  # pane_id, que e justamente o que `-P -F '#{pane_id}'` devolve.
  _panes_after=$(tmux -L "$_SOCK" list-panes -t boot -F '#{pane_id}' 2>/dev/null)
  _pane_novo=$(printf '%s\n' "$_panes_after" | grep -vxF "$_panes_before" | head -1)
  [ -n "$_pane_novo" ] || {
    _tmux_kill
    _fail "tmux" "nenhum pane novo no window boot (antes=[$_panes_before] depois=[$_panes_after])"
    return 1
  }
  _wins=$(tmux -L "$_SOCK" list-windows -t boot -F '#{window_name}' 2>/dev/null)
  _n_wins=$(printf '%s\n' "$_wins" | grep -c . || :)
  [ "$_n_wins" = 1 ] || {
    _tmux_kill
    _fail "tmux" "split-window nao deveria criar window nova: [$_wins]"
    return 1
  }
  tmux -L "$_SOCK" kill-pane -t "$_pane_novo" 2>/dev/null \
    || { _tmux_kill; _fail "tmux" "kill-pane falhou"; return 1; }
  _panes_final=$(tmux -L "$_SOCK" list-panes -t boot -F '#{pane_id}' 2>/dev/null)
  case "$(printf '\n%s\n.' "$_panes_final")" in
    *"
$_pane_novo
"*) _tmux_kill; _fail "tmux" "pane sobreviveu ao kill switch"; return 1 ;;
  esac
  _tmux_kill

  # Efeitos da filha identicos ao caminho degradado (paridade byte a byte
  # da composicao, contract §4): state real + notificacao parseavel.
  _sj="$_PHYS/proj-feat-alpha/.claude/feature-00c-state/feat-alpha/state.json"
  [ -f "$_sj" ] || { _fail "state" "state.json ausente na worktree (via tmux)"; return 1; }
  capture sh "$PNPARSE" check "$(head -1 "$E2E_MAILBOX")"
  [ "$_CAPTURED_EXIT" = 0 ] || { _fail "parse" "notificacao da filha tmux nao parseou"; return 1; }
  unset E2E_STUB_LINGER
}

run_all_scenarios
