#!/bin/sh
# test_setup.sh — cobre cli/lib/setup.sh (feature cstk-setup, wizard guiado
# de configuracao: hooks, backend de estado, MCP, telemetria).
#
# Cenarios:
#   1  scenario_dispatch_setup_wiring (task 1.1.5) — wiring do dispatcher:
#      `setup` existe no case generico, no help geral, no help por
#      subcomando e nas 2 listas de "Comandos validos" das mensagens de
#      erro. Segue o precedente de `scenario_help_lista_hooks` /
#      `scenario_help_hooks_aponta_doc` em test_cstk-main.sh (5.27.0):
#      o que se testa aqui e o WIRING — o comando existe, aparece no help
#      e nao cai no ramo "comando desconhecido" — independente de
#      cli/lib/setup.sh ja ter a implementacao completa da area.
#   2  scenario_git_root_gate (task 1.2.5, quickstart Scenario 8, FR-011) —
#      diretorio sem `.git` recusa com exit 3 e zero escrita; worktree
#      (`.git` arquivo-ponteiro) e aceito.
#   3  scenario_non_interactive_no_flag_fails_fast (task 1.2.6, quickstart
#      Scenario 6, FR-007) — sem TTY e sem --dry-run/--yes, falha imediata
#      exit 3 apontando as duas flags, sem bloquear esperando input.
#   4  scenario_dry_run_precedes_yes (task 1.3.4, quickstart Scenario 5,
#      FR-006) — `--dry-run --yes` juntas => mode=preview, zero escrita.
#   5  scenario_unknown_flag_usage_error (task 1.3.5) — flag desconhecida
#      => exit 2.
#   6  scenario_catalog_flag_rejected (task 1.3.6, quickstart Scenario 16,
#      FR-018) — `cstk setup --catalog /qualquer/dir` => exit 2 (nenhuma
#      flag de override de catalogo existe neste subcomando).
#
# FASE 3 (area de hooks, contracts/cli-setup.md §2):
#   7  scenario_hooks_three_calls_isolated (task 3.1.5, achado SEC-03) —
#      as 3 chamadas a guard-hooks-status.sh (baseline, --verify-registration,
#      --include-loose-usage) ocorrem SEPARADAS, nunca combinadas.
#   8  scenario_hooks_second_run_zero_calls (task 3.2.4, quickstart
#      Scenario 2, I1) — segundo run com status=configured nao chama
#      `hooks install`; arvore .claude identica antes/depois.
#   9  scenario_hooks_paste_instructed_surfaces_warning (task 3.2.5,
#      quickstart Scenario 7 sub-caso jq ausente) — exit 0 de `hooks
#      install` em paste-instructed carrega aviso, nao vira applied cego.
#  10  scenario_loose_usage_declined_mandatory_still_applied (task 3.3.4,
#      quickstart Scenario 9, FR-008) — default skip do hook opt-in nao
#      impede a aplicacao dos 3 hooks obrigatorios.
#  11  scenario_hooks_divergent_no_install_call (task 3.4.4, quickstart
#      Scenario 13, I6) — status=divergent nunca chama `hooks install`;
#      .claude nem chega a ser criado no projeto.
#  12  scenario_hooks_unavailable_status_reason (task 3.4.5, quickstart
#      Scenario 15) — status=unavailable distingue "nao consegui
#      verificar" do texto de divergent ("esta errado").
#
# FASE 4 (area de state-backend, contracts/cli-setup.md §3):
#  13  scenario_state_backend_deliberate_json_not_migrated (task 4.1.4,
#      quickstart Scenario 3, US2 AC3) — `state_backend=json` explicito e
#      reportado como already-configured (nunca not-configured) e `--yes`
#      NAO migra para sqlite.
#  14  scenario_state_backend_global_label_shown (task 4.2.4, quickstart
#      Scenario 16 parte FR-017) — rotulo de escopo GLOBAL aparece so na
#      area state-backend (inclusive em --dry-run), nunca em hooks.
#  15  scenario_state_backend_unavailable_sqlite_missing (task 4.3.4,
#      quickstart Scenario 7) — sqlite3 ausente do PATH que o SUT enxerga
#      (state_backend=sqlite declarado) => area failed, zero escrita,
#      exit 1; o wizard prossegue (nao aborta o processo).
#  16  scenario_state_backend_doctor_diagnostic_surfaced (task 4.4.2) —
#      texto de `cstk doctor --deps` (sqlite3 presente+versao) aparece no
#      motivo exibido para status=unavailable.
#
# FASE 5 (area de MCP, contracts/cli-setup.md §4):
#  17  scenario_mcp_status_displayed_before_action (task 5.1.3, FR-002) —
#      status da area mcp e impresso ANTES da linha de preview/acao,
#      mesmo em --dry-run.
#  18  scenario_mcp_applied_without_docker_warns (task 5.2.5, quickstart
#      Scenario 14 + Clarifications item 3, FR-015) — `--yes` sem Docker
#      no PATH aplica `mcp install` mesmo assim e emite aviso claro;
#      `.mcp.json` e escrito de verdade.
#  19  scenario_mcp_divergent_no_install_call (task 5.3.4, quickstart
#      Scenario 14a, I6) — status=divergent nunca chama `mcp install`;
#      `.mcp.json` permanece byte-a-byte identico; remediacao em duas
#      etapas exibida.
#  20  scenario_mcp_cross_layer_not_divergent (task 5.3.5, quickstart
#      Scenario 14b) — mesmo cenario cross-layer de
#      scenario_mcp_configured_cross_layer (test_mcp.sh, FASE 2.3.9),
#      agora validado no nivel de orquestracao do wizard: `configured`,
#      nunca falso-positivo `divergent`.
#
# FASE 6 (area de telemetria, contracts/cli-setup.md §5):
#  21  scenario_telemetry_readonly_no_home_write (task 6.1.4, FR-012) —
#      `otel-usage.sh preflight` diagnostica (status=disabled no HOME
#      sandboxado, sem as env vars de telemetria); a arvore de $HOME e
#      byte-a-byte identica antes/depois; outcome nunca `applied`
#      (INALCANCAVEL nesta area); as instrucoes exibidas citam os valores
#      EXATOS de README.md (CLAUDE_CODE_ENABLE_TELEMETRY=1,
#      OTEL_METRICS_EXPORTER=prometheus, CSTK_OTEL_ENDPOINT,
#      OTEL_EXPORTER_PROMETHEUS_PORT, 127.0.0.1:9464), nunca inventados.
#
# FASE 7 (sumario final, contracts/cli-setup.md §1 "Saida (stdout)"):
#  22  scenario_summary_lists_all_four_areas (task 7.1.4, quickstart
#      Scenario 1/7) — o `SetupRunSummary` lista as 4 areas em STDOUT, na
#      ordem fixa `hooks`/`state-backend`/`mcp`/`telemetry`, mesmo com
#      falha parcial (sqlite3 ausente força a area state-backend a
#      `failed`); `[escopo]=global` so na linha de state-backend; texto
#      de diagnostico/progresso continua so em stderr.
#  23  scenario_summary_declares_verification_scope (task 7.2.2, achado
#      SEC-07/CHK009) — o summary declara que so os 3 hooks obrigatorios
#      de `_GH_HOOKS` foram verificados, sem implicar auditoria do
#      `settings.json`/`.mcp.json` inteiro.
#
# FASE 8 (integracao — tasks.md 8.1.3, quickstart Scenario 1):
#  24  scenario_interactive_happy_path_accepts_all (task 8.1.3) — UNICO
#      cenario que roda em mode=interactive de verdade (sem --yes/--dry-run),
#      via CSTK_FORCE_INTERACTIVE=1 (bypassa require_tty, ui.sh:43) +
#      stdin alimentado com as respostas dos 4 prompts reais na ordem fixa
#      (hooks-mandatorio, loose-usage, state-backend, mcp — telemetria
#      nunca pergunta, FR-012): y/n/y/y (quickstart Scenario 1: afirmativa
#      p/ hooks, negativa p/ loose usage). Todos os demais 23 cenarios
#      usam --yes/--dry-run, que pulam _setup_prompt_yn inteiramente — este
#      e o unico que exercita a leitura de stdin do wizard de ponta a
#      ponta.
#
# Ref: docs/specs/cstk-setup/tasks.md FASE 1, FASE 3, FASE 4, FASE 5,
#      FASE 6, FASE 7, FASE 8; contracts/cli-setup.md §1, §2, §3, §5.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CSTK="$REPO_ROOT/cli/cstk"
CSTK_LIB="$REPO_ROOT/cli/lib"
export CSTK_LIB

# Helper: cria repo git limpo em $1 (DIR), commit inicial vazio, branch main.
# Mesmo padrao de tests/cstk/test_session.sh::_make_repo.
_make_repo() {
  _mr_dir=$1
  mkdir -p "$_mr_dir"
  ( cd "$_mr_dir" \
    && git init -q -b main \
    && git config user.email test@example.com \
    && git config user.name "Test" \
    && git commit -q --allow-empty -m "init" )
}

# ==== Helpers FASE 3 (area de hooks) ====

# _make_fake_catalog HOME_DIR -> cria um catalogo MINIMO em
# $HOME_DIR/.claude/skills/agente-00c-runtime/hooks com os 3 hooks
# obrigatorios (scripts triviais, so precisam existir+ser copiaveis) e o
# settings.snippet.json REAL do repo (para que jq faca merge de verdade).
# Ecoa o path do catalogo em stdout.
_make_fake_catalog() {
  _mfc_dir="$1/.claude/skills/agente-00c-runtime/hooks"
  mkdir -p "$_mfc_dir"
  for _mfc_h in pretooluse-bash-guard.sh posttooluse-tool-call-tick.sh posttooluse-agent-usage.sh; do
    printf '#!/bin/sh\nexit 0\n' > "$_mfc_dir/$_mfc_h"
    chmod +x "$_mfc_dir/$_mfc_h"
  done
  cp "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks/settings.snippet.json" "$_mfc_dir/"
  printf '%s' "$_mfc_dir"
}

# _make_shim_path_no_jq -> mesmo padrao de _make_shim_path
# (tests/cstk/test_hooks.sh) — PATH curado SEM jq, para exercitar o
# caminho paste-instructed (jq ausente). Inclui `cmp` (freshness) e `sh`
# (necessario para o proprio `env -i PATH=... sh "$CSTK" ...` executar).
# Inclui `sqlite3` deliberadamente (FASE 4): este shim so quer isolar jq
# — sem sqlite3 no PATH, a area state-backend (agora ativa) tentaria
# `enable-sqlite` (reason=nunca-configurado) e falharia com exit 3,
# mudando o exit code GERAL do wizard e quebrando cenarios desta area que
# testam so o comportamento de `hooks`. Cenarios que precisam de sqlite3
# genuinamente ausente usam `_make_shim_path_no_sqlite3` (abaixo).
_make_shim_path_no_jq() {
  _msp_dir=$(mktemp -d "$TMPDIR_TEST/shimbin.XXXXXX")
  for _msp_c in sh mktemp awk sed grep find head printf cp mv rm mkdir \
                chmod ls dirname basename tr cut wc env command sort \
                uniq date cat cmp sqlite3; do
    _msp_src=$(command -v "$_msp_c" 2>/dev/null) || continue
    [ -n "$_msp_src" ] || continue
    ln -sf "$_msp_src" "$_msp_dir/$_msp_c" 2>/dev/null || :
  done
  printf '%s' "$_msp_dir"
}

# ==== 1.1.5 wiring do dispatcher ====

scenario_dispatch_setup_wiring() {
  # (a) aparece no help geral
  assert_exit 0 sh "$CSTK" --help || return 1
  assert_stdout_contains "setup" || return 1

  # (b) `cstk help setup` aponta para o contrato
  assert_exit 0 sh "$CSTK" help setup || return 1
  assert_stdout_contains "setup" || return 1
  assert_stdout_contains "cli-setup.md" || return 1

  # (c) `cstk setup --help` chega no ramo generico do dispatcher — nunca
  # "comando desconhecido" (exit 2), esteja setup.sh ja implementado ou
  # ainda no estagio de scaffold ("nao implementado ainda", exit 1).
  capture sh "$CSTK" setup --help
  if [ "$_CAPTURED_EXIT" = "2" ]; then
    _fail "scenario_dispatch_setup_wiring" \
      "cstk setup --help caiu no ramo de comando desconhecido (exit 2)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"comando desconhecido"*)
      _fail "scenario_dispatch_setup_wiring" \
        "stderr contem 'comando desconhecido': $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  # (d) checagem estatica dos 4 pontos de edicao em cli/cstk
  grep -q "setup.*Wizard guiado" "$CSTK" || {
    _fail "scenario_dispatch_setup_wiring" "COMANDOS: entrada de setup ausente"
    return 1
  }
  grep -qE '^ *setup\)$' "$CSTK" || {
    _fail "scenario_dispatch_setup_wiring" "case de help por subcomando: setup) ausente"
    return 1
  }
  # `setup` precisa ser UMA das alternativas do case generico — em qualquer
  # posicao. A ancora `\|setup\)$` anterior exigia que fosse a ULTIMA, o que
  # nunca foi invariante: bastou a v7.2.0 acrescentar `plan-usage` depois
  # dela para o cenario reprovar com o wiring intacto.
  grep -qE '\|setup[|)]' "$CSTK" || {
    _fail "scenario_dispatch_setup_wiring" "case generico do dispatch: setup ausente das alternativas"
    return 1
  }
  _n_validos=$(grep -c "usage, setup, 00c" "$CSTK") || _n_validos=0
  if [ "$_n_validos" -lt 2 ]; then
    _fail "scenario_dispatch_setup_wiring" \
      "esperava setup nas 2 listas 'Comandos validos', achou $_n_validos"
    return 1
  fi
}

# ==== 1.2.5 gate de raiz de repo git (FR-011, quickstart Scenario 8) ====

scenario_git_root_gate() {
  # (a) diretorio SEM .git -> exit 3, diagnostico claro, zero escrita
  _bare="$TMPDIR_TEST/no-git-dir"
  mkdir -p "$_bare"
  capture sh "$CSTK" setup --project-path "$_bare" --yes
  if [ "$_CAPTURED_EXIT" != "3" ]; then
    _fail "scenario_git_root_gate" \
      "esperado exit 3 sem .git, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  _n_entries=$(find "$_bare" -mindepth 1 | wc -l | tr -d ' ')
  if [ "$_n_entries" != "0" ]; then
    _fail "scenario_git_root_gate" \
      "diretorio sem .git nao deveria receber escrita, achou $_n_entries entradas"
    return 1
  fi

  # (b) worktree real (.git e arquivo-ponteiro, nao diretorio) -> aceito,
  # ou seja, NAO recusado pela pre-condicao FR-011 (segue adiante e
  # retorna 0 — FASE 1 ainda nao implementa as areas).
  _src="$TMPDIR_TEST/repo-wt-gate"
  _make_repo "$_src"
  _wt_path="$( cd "$TMPDIR_TEST" && pwd -P )/repo-wt-gate-feat"
  ( cd "$_src" && git worktree add -q -b feat-gate "$_wt_path" ) || {
    _fail "scenario_git_root_gate" "git worktree add falhou"
    return 1
  }
  [ -f "$_wt_path/.git" ] || {
    _fail "scenario_git_root_gate" "pre-condicao do teste falhou: .git da worktree nao e arquivo"
    return 1
  }
  assert_exit 0 sh "$CSTK" setup --project-path "$_wt_path" --dry-run || return 1
}

# ==== 1.2.6 falha rapida sem TTY e sem --dry-run/--yes (FR-007, quickstart
# Scenario 6) ====

scenario_non_interactive_no_flag_fails_fast() {
  _repo="$TMPDIR_TEST/repo-no-tty"
  _make_repo "$_repo"

  # stdin de /dev/null simula ausencia de TTY sem bloquear o test runner.
  capture sh -c 'sh "$1" setup --project-path "$2" < /dev/null' _ "$CSTK" "$_repo"
  if [ "$_CAPTURED_EXIT" != "3" ]; then
    _fail "scenario_non_interactive_no_flag_fails_fast" \
      "esperado exit 3, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"--dry-run"*"--yes"*|*"--yes"*"--dry-run"*) : ;;
    *)
      _fail "scenario_non_interactive_no_flag_fails_fast" \
        "stderr nao aponta --dry-run/--yes: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== 1.3.4 --dry-run precede --yes (FR-006, quickstart Scenario 5) ====

scenario_dry_run_precedes_yes() {
  _repo="$TMPDIR_TEST/repo-dryrun-yes"
  _make_repo "$_repo"
  _before=$(find "$_repo" -mindepth 1 | sort)

  assert_exit 0 sh "$CSTK" setup --verbose --project-path "$_repo" --dry-run --yes || return 1
  # Diagnosticos de modo vao para stderr (Constitution II: dados em stdout,
  # erros/avisos em stderr) — cli/lib/common.sh::log_info.
  assert_stderr_contains "mode=preview" || return 1

  _after=$(find "$_repo" -mindepth 1 | sort)
  if [ "$_before" != "$_after" ]; then
    _fail "scenario_dry_run_precedes_yes" \
      "esperava zero escrita com --dry-run --yes; arvore mudou"
    return 1
  fi

  # Ordem invertida (--yes --dry-run) deve dar o mesmo resultado —
  # precedencia e por PRESENCA da flag, nao por posicao.
  assert_exit 0 sh "$CSTK" setup --verbose --project-path "$_repo" --yes --dry-run || return 1
  assert_stderr_contains "mode=preview" || return 1
}

# ==== 1.3.5 flag desconhecida => exit 2 (uso incorreto) ====

scenario_unknown_flag_usage_error() {
  capture sh "$CSTK" setup --project-path "$PWD" --bogus-flag
  if [ "$_CAPTURED_EXIT" != "2" ]; then
    _fail "scenario_unknown_flag_usage_error" \
      "esperado exit 2, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"flag desconhecida"*) : ;;
    *)
      _fail "scenario_unknown_flag_usage_error" \
        "stderr nao menciona 'flag desconhecida': $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== 1.3.6 --catalog e rejeitada — FR-018, ausencia deliberada
# (quickstart Scenario 16) ====

scenario_catalog_flag_rejected() {
  # Nenhuma flag de override de catalogo existe neste subcomando (FR-018)
  # — --catalog cai no mesmo ramo generico de "flag desconhecida" que
  # qualquer outra flag nao reconhecida, exit 2.
  assert_exit 2 sh "$CSTK" setup --catalog /qualquer/dir || return 1

  # Confirmacao estatica: setup.sh nunca implementa um case-arm para
  # --catalog (mencoes em comentario explicando a ausencia deliberada,
  # como esta propria linha do header do arquivo, nao contam).
  if grep -qE -- '--catalog\)' "$CSTK_LIB/setup.sh"; then
    _fail "scenario_catalog_flag_rejected" \
      "cli/lib/setup.sh implementa um case-arm --catalog) — FR-018 exige ausencia deliberada"
    return 1
  fi
  return 0
}

# ==== FASE 3 — Area de hooks ====

# ==== 3.1.5 tres chamadas isoladas (achado SEC-03) ====

scenario_hooks_three_calls_isolated() {
  _repo="$TMPDIR_TEST/repo-hooks-isolated"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-hooks-isolated"
  mkdir -p "$_home"

  _stubbin="$TMPDIR_TEST/stubbin-isolated"
  mkdir -p "$_stubbin"
  _calls="$TMPDIR_TEST/gh-calls-isolated.log"
  : > "$_calls"
  cat > "$_stubbin/guard-hooks-status.sh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$_calls"
case "\$*" in
  *--verify-registration*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    exit 0 ;;
  *--include-loose-usage*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-loose-usage.sh\tmissing\tunregistered\tunknown\n'
    exit 0 ;;
  *)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\n'
    exit 0 ;;
esac
STUB
  chmod +x "$_stubbin/guard-hooks-status.sh"

  assert_exit 0 env PATH="$_stubbin:$PATH" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --dry-run || return 1

  _n=$(wc -l < "$_calls" | tr -d ' ')
  if [ "$_n" != "3" ]; then
    _fail "scenario_hooks_three_calls_isolated" \
      "esperava exatamente 3 chamadas, obteve $_n: $(cat "$_calls")"
    return 1
  fi

  if grep -qE -- '--verify-registration.*--include-loose-usage|--include-loose-usage.*--verify-registration' "$_calls"; then
    _fail "scenario_hooks_three_calls_isolated" \
      "as duas flags de extensao foram combinadas numa unica chamada"
    return 1
  fi

  _n_baseline=$(grep -vc -- '--verify-registration\|--include-loose-usage' "$_calls")
  if [ "$_n_baseline" != "1" ]; then
    _fail "scenario_hooks_three_calls_isolated" \
      "esperava exatamente 1 chamada baseline sem flags, obteve $_n_baseline"
    return 1
  fi
  grep -q -- '--verify-registration' "$_calls" || {
    _fail "scenario_hooks_three_calls_isolated" "chamada --verify-registration ausente"
    return 1
  }
  grep -q -- '--include-loose-usage' "$_calls" || {
    _fail "scenario_hooks_three_calls_isolated" "chamada --include-loose-usage ausente"
    return 1
  }
}

# ==== 5a coluna de gate na linha de loose-usage (issue #162) ====
#
# O hook opt-in gateia em CSTK_OTEL_ENDPOINT e sai 0 mudo sem ela: provisionado
# porem inerte. `configured` para esse caso era dizer "ok" a um caminho que
# grava zero — dai `configured-inert`. Runtime antigo (4 colunas, sem gate)
# devolve $5 vazio e MUST preservar `configured`, nunca inventar `-inert`.

# _stub_ghs_loose DIR GATE_TOKEN -> stub com a linha loose present/registered
# e a 5a coluna sendo GATE_TOKEN (string vazia = runtime antigo, 4 colunas).
_stub_ghs_loose() {
  _sgl_dir=$1
  _sgl_gate=$2
  mkdir -p "$_sgl_dir"
  if [ -n "$_sgl_gate" ]; then
    _sgl_loose_line="posttooluse-loose-usage.sh\\tpresent\\tregistered\\tcurrent\\t$_sgl_gate\\n"
  else
    _sgl_loose_line="posttooluse-loose-usage.sh\\tpresent\\tregistered\\tcurrent\\n"
  fi
  cat > "$_sgl_dir/guard-hooks-status.sh" <<STUB
#!/bin/sh
case "\$*" in
  *--verify-registration*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    exit 0 ;;
  *--include-loose-usage*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\n'
    printf '$_sgl_loose_line'
    exit 0 ;;
  *)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\n'
    exit 0 ;;
esac
STUB
  chmod +x "$_sgl_dir/guard-hooks-status.sh"
}

# _run_setup_loose NAME GATE_TOKEN -> roda `cstk setup --dry-run --verbose`
# com o stub acima; deixa a saida combinada em $_CAPTURED_STDOUT/_STDERR.
_run_setup_loose() {
  _rsl_repo="$TMPDIR_TEST/repo-$1"
  _make_repo "$_rsl_repo"
  _rsl_home="$TMPDIR_TEST/home-$1"
  mkdir -p "$_rsl_home"
  _stub_ghs_loose "$TMPDIR_TEST/stubbin-$1" "$2"
  capture env PATH="$TMPDIR_TEST/stubbin-$1:$PATH" HOME="$_rsl_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_rsl_repo" --dry-run --verbose
}

scenario_loose_gate_inert_reportado() {
  _run_setup_loose loose-inert endpoint-unset
  if ! printf '%s\n%s\n' "$_CAPTURED_STDOUT" "$_CAPTURED_STDERR" | grep -q 'configured-inert'; then
    _fail "scenario_loose_gate_inert_reportado" \
      "esperava loose_usage_status=configured-inert; obtido: $_CAPTURED_STDOUT $_CAPTURED_STDERR"
    return 1
  fi
  if ! printf '%s\n%s\n' "$_CAPTURED_STDOUT" "$_CAPTURED_STDERR" | grep -q 'CSTK_OTEL_ENDPOINT'; then
    _fail "scenario_loose_gate_inert_reportado" \
      "esperava explicacao citando CSTK_OTEL_ENDPOINT"
    return 1
  fi
  return 0
}

scenario_loose_gate_armed_segue_configured() {
  _run_setup_loose loose-armed endpoint-set
  if ! printf '%s\n%s\n' "$_CAPTURED_STDOUT" "$_CAPTURED_STDERR" | grep -q 'loose usage.*: configured$'; then
    _fail "scenario_loose_gate_armed_segue_configured" \
      "esperava loose_usage_status=configured; obtido: $_CAPTURED_STDOUT $_CAPTURED_STDERR"
    return 1
  fi
  return 0
}

# Runtime antigo: 4 colunas, $5 vazio => preserva `configured` (o gate e
# desconhecido, nao "ausente"); jamais fabrica `-inert`.
scenario_loose_gate_runtime_antigo_preserva_configured() {
  _run_setup_loose loose-old ''
  if printf '%s\n%s\n' "$_CAPTURED_STDOUT" "$_CAPTURED_STDERR" | grep -q 'configured-inert'; then
    _fail "scenario_loose_gate_runtime_antigo_preserva_configured" \
      "runtime sem a coluna de gate nao pode virar configured-inert"
    return 1
  fi
  if ! printf '%s\n%s\n' "$_CAPTURED_STDOUT" "$_CAPTURED_STDERR" | grep -q 'loose usage.*: configured$'; then
    _fail "scenario_loose_gate_runtime_antigo_preserva_configured" \
      "esperava configured; obtido: $_CAPTURED_STDOUT $_CAPTURED_STDERR"
    return 1
  fi
  return 0
}

# ==== 3.2.4 status=configured -> zero chamadas de aplicacao (I1) ====

scenario_hooks_second_run_zero_calls() {
  _repo="$TMPDIR_TEST/repo-hooks-idem"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-hooks-idem"
  mkdir -p "$_home"
  _cat=$(_make_fake_catalog "$_home")

  assert_exit 0 env HOME="$_home" CSTK_HOOKS_CATALOG_DIR="$_cat" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --yes || return 1

  [ -f "$_repo/.claude/hooks/pretooluse-bash-guard.sh" ] || {
    _fail "scenario_hooks_second_run_zero_calls" \
      "pre-condicao do teste falhou: primeiro run nao provisionou os hooks"
    return 1
  }
  cp -R "$_repo/.claude" "$TMPDIR_TEST/hooks-idem-snapshot"

  capture env HOME="$_home" CSTK_HOOKS_CATALOG_DIR="$_cat" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --yes
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_hooks_second_run_zero_calls" \
      "segundo run esperava exit 0, obteve $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"already-configured"*) : ;;
    *)
      _fail "scenario_hooks_second_run_zero_calls" \
        "segundo run nao reportou already-configured: $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  if ! diff -r "$TMPDIR_TEST/hooks-idem-snapshot" "$_repo/.claude" >/dev/null 2>&1; then
    _fail "scenario_hooks_second_run_zero_calls" \
      ".claude mudou no segundo run — esperava zero chamada de aplicacao (I1)"
    return 1
  fi
}

# ==== 3.2.5 paste-instructed (jq ausente) nao vira applied cego ====

scenario_hooks_paste_instructed_surfaces_warning() {
  if ! command -v jq >/dev/null 2>&1; then
    _error "no_jq" "jq nao disponivel no ambiente — cenario exige jq presente no PATH real para o shim ter algo a excluir"
  fi
  _repo="$TMPDIR_TEST/repo-hooks-paste"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-hooks-paste"
  mkdir -p "$_home"
  _cat=$(_make_fake_catalog "$_home")
  _shim=$(_make_shim_path_no_jq)

  capture env -i PATH="$_shim" HOME="$_home" CSTK_HOOKS_CATALOG_DIR="$_cat" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --yes
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_hooks_paste_instructed_surfaces_warning" \
      "esperado exit 0 (applied com aviso), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"jq ausente"*) : ;;
    *)
      _fail "scenario_hooks_paste_instructed_surfaces_warning" \
        "stderr nao carrega o aviso de jq ausente / colagem manual: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"outcome=applied"*) : ;;
    *)
      _fail "scenario_hooks_paste_instructed_surfaces_warning" \
        "outcome nao reportado como applied: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== 3.3.4 loose usage recusado nao impede hooks obrigatorios (FR-008) ====

scenario_loose_usage_declined_mandatory_still_applied() {
  _repo="$TMPDIR_TEST/repo-hooks-loose-declined"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-hooks-loose-declined"
  mkdir -p "$_home"
  _cat=$(_make_fake_catalog "$_home")
  # Hook opt-in TAMBEM presente no catalogo — prova que a ausencia no
  # projeto e por ESCOLHA (default skip em --yes), nao por ausencia no
  # catalogo.
  printf '#!/bin/sh\nexit 0\n' > "$_cat/posttooluse-loose-usage.sh"
  chmod +x "$_cat/posttooluse-loose-usage.sh"

  assert_exit 0 env HOME="$_home" CSTK_HOOKS_CATALOG_DIR="$_cat" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --yes || return 1

  assert_exit 0 env HOME="$_home" CSTK_HOOKS_CATALOG_DIR="$_cat" \
    sh "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts/guard-hooks-status.sh" \
    check --projeto-alvo-path "$_repo" --quiet || return 1

  if [ -f "$_repo/.claude/hooks/posttooluse-loose-usage.sh" ]; then
    _fail "scenario_loose_usage_declined_mandatory_still_applied" \
      "hook opt-in de loose usage foi provisionado apesar do default skip"
    return 1
  fi
  if grep -q "posttooluse-loose-usage" "$_repo/.claude/settings.json" 2>/dev/null; then
    _fail "scenario_loose_usage_declined_mandatory_still_applied" \
      "hook opt-in de loose usage foi registrado em settings.json apesar do default skip"
    return 1
  fi
}

# ==== 3.4.4 status=divergent -> zero chamada de aplicacao (I6) ====

scenario_hooks_divergent_no_install_call() {
  _repo="$TMPDIR_TEST/repo-hooks-divergent"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-hooks-divergent"
  mkdir -p "$_home"
  # Catalogo REAL presente — se hooks_main fosse chamado por engano isso
  # deixaria rastro (.claude criado/populado no projeto).
  _make_fake_catalog "$_home" >/dev/null

  _stubbin="$TMPDIR_TEST/stubbin-divergent"
  mkdir -p "$_stubbin"
  cat > "$_stubbin/guard-hooks-status.sh" <<'STUB'
#!/bin/sh
case "$*" in
  *--verify-registration*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\tdivergent\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    exit 1 ;;
  *--include-loose-usage*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-loose-usage.sh\tmissing\tunregistered\tunknown\n'
    exit 0 ;;
  *)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-tool-call-tick.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-agent-usage.sh\tpresent\tregistered\tcurrent\n'
    exit 0 ;;
esac
STUB
  chmod +x "$_stubbin/guard-hooks-status.sh"

  capture env PATH="$_stubbin:$PATH" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --yes
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "scenario_hooks_divergent_no_install_call" \
      "esperado exit 1 (area divergente), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  if [ -e "$_repo/.claude" ]; then
    _fail "scenario_hooks_divergent_no_install_call" \
      "status=divergent NAO pode chamar aplicacao (I6); .claude foi criado no projeto"
    return 1
  fi
}

# ==== 3.4.5 status=unavailable distingue motivo de divergent ====

scenario_hooks_unavailable_status_reason() {
  _repo="$TMPDIR_TEST/repo-hooks-unavailable"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-hooks-unavailable"
  mkdir -p "$_home"
  mkdir -p "$_repo/.claude/hooks"
  printf '#!/bin/sh\nexit 0\n' > "$_repo/.claude/hooks/pretooluse-bash-guard.sh"
  chmod +x "$_repo/.claude/hooks/pretooluse-bash-guard.sh"
  # settings.json minificado numa unica linha fisica: impede atribuicao
  # por linha em _gh_verify_registration -> indeterminate (nunca
  # canonical) — e como o hook ESTA registrado (baseline), isso e
  # ambiguidade REAL, nao o caso trivial "nada para autenticar".
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\\"$CLAUDE_PROJECT_DIR\\"/.claude/hooks/pretooluse-bash-guard.sh"}]}]}}' \
    > "$_repo/.claude/settings.json"

  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --yes
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "scenario_hooks_unavailable_status_reason" \
      "esperado exit 1 (unavailable), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"unavailable"*) : ;;
    *)
      _fail "scenario_hooks_unavailable_status_reason" \
        "stderr nao reporta status=unavailable: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"registro nao-canonico detectado"*)
      _fail "scenario_hooks_unavailable_status_reason" \
        "reason usou o texto de divergent ('esta errado') em vez do de unavailable ('nao consegui verificar')"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"nao pode ser confirmada nem refutada"*) : ;;
    *)
      _fail "scenario_hooks_unavailable_status_reason" \
        "reason nao distingue 'nao consegui verificar': $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== Helpers FASE 4 (area de state-backend) ====

# _make_shim_path_no_sqlite3 -> mesmo padrao de _make_shim_path_no_jq:
# PATH curado SEM sqlite3 nem jq (nenhum dos dois esta na allowlist copiada),
# desacoplando a deteccao do SUT do PATH real do harness (gotcha registrado
# no projeto — "PATH-stub nao esconde binario de /usr/bin": nao tentamos
# "esconder" nada, construimos um PATH isolado que nunca inclui o dir onde
# sqlite3 mora, em vez de tentar sobrepor um dir anterior).
_make_shim_path_no_sqlite3() {
  _mss_dir=$(mktemp -d "$TMPDIR_TEST/shimbin-nosqlite.XXXXXX")
  for _mss_c in sh mktemp awk sed grep find head printf cp mv rm mkdir \
                chmod ls dirname basename tr cut wc env command sort \
                uniq date cat cmp; do
    _mss_src=$(command -v "$_mss_c" 2>/dev/null) || continue
    [ -n "$_mss_src" ] || continue
    ln -sf "$_mss_src" "$_mss_dir/$_mss_c" 2>/dev/null || :
  done
  printf '%s' "$_mss_dir"
}

# ==== FASE 4 — Area de state-backend ====

# ==== 4.1.4 escolha deliberada de json NAO e migrada (US2 AC3, quickstart
# Scenario 3) ====

scenario_state_backend_deliberate_json_not_migrated() {
  _repo="$TMPDIR_TEST/repo-sb-json-deliberate"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-sb-json-deliberate"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=json\n' > "$_home/.claude/cstk/config"
  chmod 600 "$_home/.claude/cstk/config"

  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --yes
  case "$_CAPTURED_STDERR" in
    *"[state-backend] status atual = configured"*"reason=json-explicito"*) : ;;
    *)
      _fail "scenario_state_backend_deliberate_json_not_migrated" \
        "esperava status=configured com reason=json-explicito: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"[state-backend] ja configurado"*) : ;;
    *)
      _fail "scenario_state_backend_deliberate_json_not_migrated" \
        "esperava 'ja configurado' (I1, zero chamada de aplicacao): $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  _content_after=$(cat "$_home/.claude/cstk/config")
  if [ "$_content_after" != "state_backend=json" ]; then
    _fail "scenario_state_backend_deliberate_json_not_migrated" \
      "--yes migrou a escolha deliberada de json para: $_content_after"
    return 1
  fi
}

# ==== 4.2.4 rotulo de escopo GLOBAL — FR-017 (quickstart Scenario 16) ====

scenario_state_backend_global_label_shown() {
  _repo="$TMPDIR_TEST/repo-sb-global-label"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-sb-global-label"
  mkdir -p "$_home"

  # (a) em --dry-run: rotulo aparece ANTES de qualquer decisao, mesmo sem
  # aplicar nada.
  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --dry-run
  case "$_CAPTURED_STDERR" in
    *"[state-backend] ESCOPO GLOBAL"*"TODOS os projetos"*) : ;;
    *)
      _fail "scenario_state_backend_global_label_shown" \
        "rotulo de escopo global ausente em --dry-run: $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  # (b) em --yes tambem (nao so em preview).
  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --yes
  case "$_CAPTURED_STDERR" in
    *"[state-backend] ESCOPO GLOBAL"*) : ;;
    *)
      _fail "scenario_state_backend_global_label_shown" \
        "rotulo de escopo global ausente em --yes: $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  # (c) as outras areas (hooks) NAO carregam esse rotulo.
  _hooks_block=$(printf '%s\n' "$_CAPTURED_STDERR" | grep '\[hooks\]')
  case "$_hooks_block" in
    *"ESCOPO GLOBAL"*)
      _fail "scenario_state_backend_global_label_shown" \
        "area de hooks carregou o rotulo de escopo global (FR-017 restringe a state-backend)"
      return 1
      ;;
  esac
}

# ==== 4.3.4 sqlite3 ausente/abaixo do minimo => area failed, isolada
# (task 4.3.3, quickstart Scenario 7) ====

scenario_state_backend_unavailable_sqlite_missing() {
  _repo="$TMPDIR_TEST/repo-sb-unavailable"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-sb-unavailable"
  mkdir -p "$_home/.claude/cstk"
  # backend=sqlite ja declarado -> resolve() checa sqlite3 internamente e
  # devolve reason=configurado-dependencia-ausente quando nao encontrado
  # no PATH que o SUT enxerga.
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  chmod 600 "$_home/.claude/cstk/config"
  _shim=$(_make_shim_path_no_sqlite3)

  capture env -i PATH="$_shim" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --yes
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "scenario_state_backend_unavailable_sqlite_missing" \
      "esperado exit 1 (area failed), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"[state-backend] status atual = unavailable"*"reason=configurado-dependencia-ausente"*) : ;;
    *)
      _fail "scenario_state_backend_unavailable_sqlite_missing" \
        "esperava status=unavailable/reason=configurado-dependencia-ausente: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"[state-backend] nenhuma chamada de aplicacao sera feita."*) : ;;
    *)
      _fail "scenario_state_backend_unavailable_sqlite_missing" \
        "esperava aviso de zero chamada de aplicacao: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  # config global INTOCADA (zero escrita sobre status=unavailable).
  _content_after=$(cat "$_home/.claude/cstk/config")
  if [ "$_content_after" != "state_backend=sqlite" ]; then
    _fail "scenario_state_backend_unavailable_sqlite_missing" \
      "config global foi escrita apesar de status=unavailable: $_content_after"
    return 1
  fi
  # FR-009: o wizard prossegue apos a falha isolada — nao aborta o
  # processo no meio da area; a area seguinte (mcp) ainda roda.
  case "$_CAPTURED_STDERR" in
    *"[mcp] outcome="*) : ;;
    *)
      _fail "scenario_state_backend_unavailable_sqlite_missing" \
        "wizard nao prosseguiu apos falha isolada em state-backend (FR-009): $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== 4.4.2 diagnostico de `cstk doctor --deps` reusado quando unavailable
# (task 4.4.1) ====

scenario_state_backend_doctor_diagnostic_surfaced() {
  _repo="$TMPDIR_TEST/repo-sb-doctor-diag"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-sb-doctor-diag"
  mkdir -p "$_home/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  chmod 600 "$_home/.claude/cstk/config"
  _shim=$(_make_shim_path_no_sqlite3)

  capture env -i PATH="$_shim" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --yes
  case "$_CAPTURED_STDERR" in
    *"diagnostico (cstk doctor --deps)"*) : ;;
    *)
      _fail "scenario_state_backend_doctor_diagnostic_surfaced" \
        "diagnostico de cstk doctor --deps ausente: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"sqlite3: presente=nao"*) : ;;
    *)
      _fail "scenario_state_backend_doctor_diagnostic_surfaced" \
        "diagnostico nao cita sqlite3 presente=nao: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"minima=3.45.1"*) : ;;
    *)
      _fail "scenario_state_backend_doctor_diagnostic_surfaced" \
        "diagnostico nao cita a versao minima exigida: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== Helpers FASE 5 (area de MCP) ====

# _make_shim_path_no_docker -> mesmo padrao de _make_shim_path_no_jq /
# _make_shim_path_no_sqlite3: PATH curado incluindo jq E sqlite3 (para
# isolar a area mcp de efeitos colaterais nas outras 3 areas) mas
# deliberadamente SEM docker — prova que a area mcp aplica normalmente
# mesmo sem Docker no PATH (mcp-direct-transport, FR-006), sem depender
# de o Docker estar instalado ou nao na maquina que roda a suite.
_make_shim_path_no_docker() {
  _msnd_dir=$(mktemp -d "$TMPDIR_TEST/shimbin-nodocker.XXXXXX")
  for _msnd_c in sh mktemp awk sed grep find head printf cp mv rm mkdir \
                chmod ls dirname basename tr cut wc env command sort \
                uniq date cat cmp jq sqlite3; do
    _msnd_src=$(command -v "$_msnd_c" 2>/dev/null) || continue
    [ -n "$_msnd_src" ] || continue
    ln -sf "$_msnd_src" "$_msnd_dir/$_msnd_c" 2>/dev/null || :
  done
  printf '%s' "$_msnd_dir"
}

# ==== FASE 5 — Area de MCP ====

# ==== 5.1.3 status exibido ANTES de qualquer decisao (FR-002) ====

scenario_mcp_status_displayed_before_action() {
  _repo="$TMPDIR_TEST/repo-mcp-status-order"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-mcp-status-order"
  mkdir -p "$_home"

  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --dry-run
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_mcp_status_displayed_before_action" \
      "esperado exit 0 (dry-run), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"[mcp] status atual = not-configured"*) : ;;
    *)
      _fail "scenario_mcp_status_displayed_before_action" \
        "status da area mcp nao foi exibido: $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  _status_line=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -n '\[mcp\] status atual' | head -1 | cut -d: -f1)
  _preview_line=$(printf '%s\n' "$_CAPTURED_STDERR" | grep -n '\[mcp\] preview' | head -1 | cut -d: -f1)
  if [ -z "$_status_line" ] || [ -z "$_preview_line" ]; then
    _fail "scenario_mcp_status_displayed_before_action" \
      "nao foi possivel localizar as duas linhas para comparar ordem: $_CAPTURED_STDERR"
    return 1
  fi
  if [ "$_status_line" -ge "$_preview_line" ]; then
    _fail "scenario_mcp_status_displayed_before_action" \
      "status (linha $_status_line) nao apareceu ANTES do preview de acao (linha $_preview_line) — FR-002"
    return 1
  fi
}

# ==== 5.2.5 --yes sem Docker aplica normalmente, sem aviso de Docker
# (mcp-direct-transport, FR-006: MCP nunca depende de motor de
# containers) ====

scenario_mcp_applied_without_docker_no_warning() {
  if ! command -v jq >/dev/null 2>&1; then
    _error "no_jq" "jq nao disponivel no ambiente — cenario exige jq presente no PATH real para o merge de verdade ocorrer"
  fi
  _repo="$TMPDIR_TEST/repo-mcp-no-docker"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-mcp-no-docker"
  mkdir -p "$_home"
  _cat=$(_make_fake_catalog "$_home")
  _shim=$(_make_shim_path_no_docker)

  capture env -i PATH="$_shim" HOME="$_home" CSTK_HOOKS_CATALOG_DIR="$_cat" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --yes
  case "$_CAPTURED_STDERR" in
    *"[mcp] outcome=applied"*) : ;;
    *)
      _fail "scenario_mcp_applied_without_docker_no_warning" \
        "area mcp nao ficou applied mesmo sem Docker (FR-006): $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  # Pos-cutover: Docker e irrelevante para o registro mcp — nenhum aviso
  # sobre Docker deve ser emitido (avisar seria informacao FALSA).
  case "$_CAPTURED_STDERR" in
    *"Docker nao encontrado"*)
      _fail "scenario_mcp_applied_without_docker_no_warning" \
        "aviso obsoleto de Docker ausente foi emitido (mcp nao depende mais de Docker): $_CAPTURED_STDERR"
      return 1
      ;;
    *) : ;;
  esac
  if ! grep -Fq -- '"cstk-state"' "$_repo/.mcp.json" 2>/dev/null; then
    _fail "scenario_mcp_applied_without_docker_no_warning" \
      ".mcp.json nao foi escrito com a entrada mcpServers.cstk-state"
    return 1
  fi
}

# ==== 5.3.4 status=divergent nunca chama `mcp install` (I6, FR-016) ====

scenario_mcp_divergent_no_install_call() {
  _repo="$TMPDIR_TEST/repo-mcp-divergent"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-mcp-divergent"
  mkdir -p "$_home"
  _mcp_file="$_repo/.mcp.json"
  cat > "$_mcp_file" <<'JSON'
{
  "mcpServers": {
    "cstk-state": {
      "type": "stdio",
      "command": "/tmp/fake-launch.sh",
      "args": []
    }
  }
}
JSON
  _snapshot=$(cat "$_mcp_file")

  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --yes
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "scenario_mcp_divergent_no_install_call" \
      "esperado exit 1 (mcp divergent), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"[mcp] status atual = divergent"*) : ;;
    *)
      _fail "scenario_mcp_divergent_no_install_call" \
        "status divergent nao reportado: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"[mcp] outcome=failed"*) : ;;
    *)
      _fail "scenario_mcp_divergent_no_install_call" \
        "outcome divergent nao virou failed: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"[mcp] remediacao (duas etapas"*) : ;;
    *)
      _fail "scenario_mcp_divergent_no_install_call" \
        "remediacao em duas etapas ausente: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  _after=$(cat "$_mcp_file")
  if [ "$_after" != "$_snapshot" ]; then
    _fail "scenario_mcp_divergent_no_install_call" \
      ".mcp.json foi alterado apesar de status=divergent (I6)"
    return 1
  fi
}

# ==== 5.3.5 cross-layer legitimo NAO pode ser divergent (quickstart 14b) ====

scenario_mcp_cross_layer_not_divergent() {
  _repo="$TMPDIR_TEST/repo-mcp-cross-layer"
  _make_repo "$_repo"
  _fake_home="$TMPDIR_TEST/home-mcp-cross-layer"
  _catalog_launcher="$_fake_home/.claude/skills/agente-00c-runtime/scripts/mcp-launch.sh"
  mkdir -p "$(dirname "$_catalog_launcher")"
  printf '#!/bin/sh\nexit 0\n' > "$_catalog_launcher"
  chmod +x "$_catalog_launcher"
  printf '{\n  "mcpServers": {\n    "cstk-state": {\n      "type": "stdio",\n      "command": "%s",\n      "args": []\n    }\n  }\n}\n' \
    "$_catalog_launcher" > "$_repo/.mcp.json"

  # Mesmo cenario de scenario_mcp_configured_cross_layer (test_mcp.sh,
  # FASE 2.3.9): CSTK_LIB=repo (contexto DIFERENTE do HOME onde o
  # candidato "instalado" mora) — agora validado no nivel do wizard.
  capture env HOME="$_fake_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --dry-run
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_mcp_cross_layer_not_divergent" \
      "esperado exit 0 (dry-run, configured), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"[mcp] status atual = configured"*) : ;;
    *)
      _fail "scenario_mcp_cross_layer_not_divergent" \
        "esperado status=configured (cross-layer), obtido: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"[mcp] status atual = divergent"*)
      _fail "scenario_mcp_cross_layer_not_divergent" \
        "falso-positivo: cross-layer legitimo reportado como divergent"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"[mcp] ja configurado"*) : ;;
    *)
      _fail "scenario_mcp_cross_layer_not_divergent" \
        "already-configured/I1 nao confirmado: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== 6.1.4 telemetria e 100% read-only, zero escrita em $HOME (FR-012) ====

scenario_telemetry_readonly_no_home_write() {
  _repo="$TMPDIR_TEST/repo-telemetry-ro"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-telemetry-ro"
  mkdir -p "$_home"

  # Snapshot recursivo de $HOME (nomes + conteudo) ANTES do run. Sem env
  # de telemetria setadas -> otel-usage.sh preflight reporta
  # status=disabled (nem CLAUDE_CODE_ENABLE_TELEMETRY nem
  # OTEL_METRICS_EXPORTER estao presentes neste `env -i`).
  _before=$(find "$_home" -type f -exec cksum {} + 2>/dev/null | sort)

  capture env -i HOME="$_home" PATH="$PATH" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --verbose --project-path "$_repo" --dry-run
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_telemetry_readonly_no_home_write" \
      "esperado exit 0 (--dry-run), obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi

  _after=$(find "$_home" -type f -exec cksum {} + 2>/dev/null | sort)
  if [ "$_before" != "$_after" ]; then
    _fail "scenario_telemetry_readonly_no_home_write" \
      "\$HOME mudou apos o wizard — area telemetry (e nenhuma outra, em --dry-run) MUST ser 100% read-only (FR-012)"
    return 1
  fi

  # FR-002 — status exibido ANTES de qualquer instrucao/decisao.
  case "$_CAPTURED_STDERR" in
    *"[telemetry] status atual = status=disabled"*) : ;;
    *)
      _fail "scenario_telemetry_readonly_no_home_write" \
        "status nao exibido (ou inesperado): $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  # outcome=applied e INALCANCAVEL para esta area (task 6.1.3).
  case "$_CAPTURED_STDERR" in
    *"[telemetry] outcome=applied"*)
      _fail "scenario_telemetry_readonly_no_home_write" \
        "outcome=applied apareceu para telemetry — INALCANCAVEL por FR-012"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"[telemetry] outcome=skipped"*) : ;;
    *)
      _fail "scenario_telemetry_readonly_no_home_write" \
        "esperado outcome=skipped (status=disabled), obtido: $_CAPTURED_STDERR"
      return 1
      ;;
  esac

  # task 6.1.2 — valores EXATOS citados de README.md, nunca inventados.
  for _val in "CLAUDE_CODE_ENABLE_TELEMETRY=1" "OTEL_METRICS_EXPORTER=prometheus" \
              "CSTK_OTEL_ENDPOINT" "OTEL_EXPORTER_PROMETHEUS_PORT" "127.0.0.1:9464"; do
    case "$_CAPTURED_STDERR" in
      *"$_val"*) : ;;
      *)
        _fail "scenario_telemetry_readonly_no_home_write" \
          "instrucao exibida nao contem o valor exato '$_val' (README.md): $_CAPTURED_STDERR"
        return 1
        ;;
    esac
  done
}

# ==== FASE 7 — Sumario Final ====

# ==== 7.1.4 summary lista as 4 areas, mesmo com falha parcial (quickstart
# Scenario 1/7, SC-005) ====

scenario_summary_lists_all_four_areas() {
  _repo="$TMPDIR_TEST/repo-summary-4areas"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-summary-4areas"
  mkdir -p "$_home/.claude/cstk"
  # Mesmo padrao de scenario_state_backend_unavailable_sqlite_missing:
  # forca SO a area state-backend a `failed`, isolando o efeito nas
  # demais 3 (FR-009 — falha isolada nao interrompe o resto).
  printf 'state_backend=sqlite\n' > "$_home/.claude/cstk/config"
  chmod 600 "$_home/.claude/cstk/config"
  _shim=$(_make_shim_path_no_sqlite3)

  capture env -i PATH="$_shim" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --yes
  if [ "$_CAPTURED_EXIT" != "1" ]; then
    _fail "scenario_summary_lists_all_four_areas" \
      "esperado exit 1 (state-backend failed), obtido $_CAPTURED_EXIT (stdout: $_CAPTURED_STDOUT; stderr: $_CAPTURED_STDERR)"
    return 1
  fi

  # As 4 areas aparecem no summary, na ordem fixa de FR-001, MESMO com
  # state-backend em failed.
  _sm_prev_line=0
  for _sm_area in hooks state-backend mcp telemetry; do
    _sm_line=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -n "^$_sm_area  " | head -n 1 | cut -d: -f1)
    if [ -z "$_sm_line" ]; then
      _fail "scenario_summary_lists_all_four_areas" \
        "area '$_sm_area' ausente do summary: $_CAPTURED_STDOUT"
      return 1
    fi
    if [ "$_sm_line" -le "$_sm_prev_line" ]; then
      _fail "scenario_summary_lists_all_four_areas" \
        "ordem fixa violada em '$_sm_area' (linha $_sm_line, anterior $_sm_prev_line): $_CAPTURED_STDOUT"
      return 1
    fi
    _sm_prev_line=$_sm_line
  done

  case "$_CAPTURED_STDOUT" in
    *"state-backend  failed  global"*) : ;;
    *)
      _fail "scenario_summary_lists_all_four_areas" \
        "linha de state-backend nao reporta failed+escopo global: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac

  # `[escopo]=global` e EXCLUSIVO de state-backend (FR-017/task 7.1.2) —
  # nenhuma outra linha do summary carrega " global".
  _sm_global_lines=$(printf '%s\n' "$_CAPTURED_STDOUT" | grep -c '  global')
  if [ "$_sm_global_lines" != "1" ]; then
    _fail "scenario_summary_lists_all_four_areas" \
      "rotulo 'global' apareceu $_sm_global_lines vezes no summary (esperado 1, so em state-backend): $_CAPTURED_STDOUT"
    return 1
  fi

  # Progresso/diagnostico (log_info/log_warn/log_error) continua em
  # stderr — o summary em si nao duplica no stdout.
  case "$_CAPTURED_STDOUT" in
    *"[hooks]"* | *"[mcp]"* | *"[telemetry]"* | *"[state-backend]"*)
      _fail "scenario_summary_lists_all_four_areas" \
        "stdout carrega linhas de progresso ([area]) que deveriam estar so em stderr: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac
}

# ==== 7.2.2 summary declara o escopo real da verificacao (SEC-07/CHK009)
# ====

scenario_summary_declares_verification_scope() {
  _repo="$TMPDIR_TEST/repo-summary-scope"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-summary-scope"
  mkdir -p "$_home"

  capture env HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --dry-run
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_summary_declares_verification_scope" \
      "esperado exit 0 (--dry-run), obtido $_CAPTURED_EXIT (stdout: $_CAPTURED_STDOUT; stderr: $_CAPTURED_STDERR)"
    return 1
  fi

  # Cita os 3 hooks obrigatorios REAIS de _GH_HOOKS (nunca inventados).
  for _sv_hook in "pretooluse-bash-guard.sh" "posttooluse-tool-call-tick.sh" \
                  "posttooluse-agent-usage.sh"; do
    case "$_CAPTURED_STDOUT" in
      *"$_sv_hook"*) : ;;
      *)
        _fail "scenario_summary_declares_verification_scope" \
          "declaracao de escopo nao cita '$_sv_hook': $_CAPTURED_STDOUT"
        return 1
        ;;
    esac
  done

  # Declara explicitamente que o settings.json/.mcp.json NAO foi todo
  # auditado — nao pode implicar garantia mais ampla (CHK009).
  case "$_CAPTURED_STDOUT" in
    *"nao foi auditada"* | *"NAO foi auditada"* \
      | *"nao foram auditadas"* | *"NAO foram auditadas"*) : ;;
    *)
      _fail "scenario_summary_declares_verification_scope" \
        "declaracao nao deixa claro que o restante do settings.json/.mcp.json NAO foi auditado: $_CAPTURED_STDOUT"
      return 1
      ;;
  esac

  # A declaracao de escopo vive em stdout (dado de saida), nao stderr.
  case "$_CAPTURED_STDERR" in
    *"_GH_HOOKS"*)
      _fail "scenario_summary_declares_verification_scope" \
        "declaracao de escopo vazou para stderr em vez de stdout: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== FASE 8 — Integracao: modo interativo real (task 8.1.3) ====

# ==== 8.1.3 happy path interativo aceitando os 4 prompts (quickstart
# Scenario 1) ====

scenario_interactive_happy_path_accepts_all() {
  if ! command -v jq >/dev/null 2>&1; then
    _error "no_jq" "jq nao disponivel no ambiente — cenario exige jq presente no PATH real para os merges de hooks/mcp ocorrerem de verdade"
  fi
  if ! command -v sqlite3 >/dev/null 2>&1; then
    _error "no_sqlite3" "sqlite3 nao disponivel no ambiente — cenario exige sqlite3 presente no PATH real para enable-sqlite aplicar de verdade"
  fi

  _repo="$TMPDIR_TEST/repo-interactive-happy"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-interactive-happy"
  mkdir -p "$_home"
  _cat=$(_make_fake_catalog "$_home")

  # Sem --yes/--dry-run -> mode=interactive (_setup_resolve_mode). Os 4
  # prompts reais de _setup_prompt_yn, na ordem em que o wizard os emite:
  #   1. [hooks] instalar os hooks obrigatorios agora?      -> y
  #   2. [hooks] tambem habilitar loose usage (default nao)? -> n
  #   3. [state-backend] ativar backend sqlite GLOBALMENTE?  -> y
  #   4. [mcp] registrar o servidor de estado MCP agora?     -> y
  # (telemetria e 100% read-only, FR-012 — nunca pergunta.)
  capture env CSTK_FORCE_INTERACTIVE=1 HOME="$_home" \
    CSTK_HOOKS_CATALOG_DIR="$_cat" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" <<EOF
y
n
y
y
EOF

  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_interactive_happy_path_accepts_all" \
      "esperado exit 0, obtido $_CAPTURED_EXIT (stdout: $_CAPTURED_STDOUT; stderr: $_CAPTURED_STDERR)"
    return 1
  fi

  # As 4 areas presentes no summary final (FR-010), ordem fixa de FR-001.
  for _a in "hooks" "state-backend" "mcp" "telemetry"; do
    case "$_CAPTURED_STDOUT" in
      *"$_a "*) : ;;
      *)
        _fail "scenario_interactive_happy_path_accepts_all" \
          "summary nao lista a area '$_a': $_CAPTURED_STDOUT"
        return 1
        ;;
    esac
  done

  # hooks obrigatorios de fato provisionados apos aceite interativo (y).
  if [ ! -f "$_repo/.claude/hooks/pretooluse-bash-guard.sh" ]; then
    _fail "scenario_interactive_happy_path_accepts_all" \
      "hooks obrigatorios nao foram aplicados apesar do aceite interativo (y)"
    return 1
  fi

  # loose usage recusado interativamente (n) -> hook opt-in NAO provisionado.
  if [ -f "$_repo/.claude/hooks/posttooluse-loose-usage.sh" ]; then
    _fail "scenario_interactive_happy_path_accepts_all" \
      "loose usage foi provisionado apesar da resposta negativa (n)"
    return 1
  fi

  # state-backend aceito interativamente (y) -> config global GRAVADA.
  if ! grep -q '^state_backend=sqlite$' "$_home/.claude/cstk/config" 2>/dev/null; then
    _fail "scenario_interactive_happy_path_accepts_all" \
      "state-backend nao foi migrado apesar do aceite interativo (y); config: $(cat "$_home/.claude/cstk/config" 2>/dev/null)"
    return 1
  fi

  # mcp aceito interativamente (y) -> .mcp.json ESCRITO no projeto.
  if ! grep -Fq -- '"cstk-state"' "$_repo/.mcp.json" 2>/dev/null; then
    _fail "scenario_interactive_happy_path_accepts_all" \
      ".mcp.json nao foi escrito apesar do aceite interativo (y)"
    return 1
  fi
}

# ==== modo silencioso default (ajuste de UX 2026-08-07) ====

# Default (sem --verbose): sucesso emite so [OK] por area + summary —
# nenhuma linha de progresso [info] de status/preview aparece.
scenario_quiet_default_emits_ok_lines() {
  _repo="$TMPDIR_TEST/repo-quiet-ok"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-quiet-ok"
  mkdir -p "$_home"

  capture env -i PATH="$PATH" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --dry-run
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_quiet_default_emits_ok_lines" \
      "esperado exit 0 em dry-run, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  for _qa in hooks state-backend mcp telemetry; do
    case "$_CAPTURED_STDERR" in
      *"[OK] $_qa"*) : ;;
      *)
        _fail "scenario_quiet_default_emits_ok_lines" \
          "linha '[OK] $_qa' ausente no modo silencioso: $_CAPTURED_STDERR"
        return 1
        ;;
    esac
  done
  case "$_CAPTURED_STDERR" in
    *"status atual"* | *"pre-condicoes OK"*)
      _fail "scenario_quiet_default_emits_ok_lines" \
        "linhas de progresso vazaram sem --verbose: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# --verbose restaura o progresso detalhado (status atual, preview, outcome=).
scenario_verbose_flag_restores_progress() {
  _repo="$TMPDIR_TEST/repo-verbose-progress"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-verbose-progress"
  mkdir -p "$_home"

  capture env -i PATH="$PATH" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --dry-run --verbose
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_verbose_flag_restores_progress" \
      "esperado exit 0, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"[hooks] status atual"*) : ;;
    *)
      _fail "scenario_verbose_flag_restores_progress" \
        "--verbose nao restaurou o progresso detalhado: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
  case "$_CAPTURED_STDERR" in
    *"pre-condicoes OK"*) : ;;
    *)
      _fail "scenario_verbose_flag_restores_progress" \
        "--verbose nao mostrou pre-condicoes: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# ==== Dedup plugin-vence na area de hooks (FR-005, feature
# claude-plugin-packaging FASE 6, task 6.2.4) — mesma regra 3-condicoes de
# cli/lib/hooks.sh::hooks_main, replicada em _setup_run_hooks_area. ====

# _setup_plugin_home_fixture HOME_DIR MODE: popula registro nativo
# "cstk@cstk" instalado+habilitado em HOME_DIR; MODE=with-hooks cria
# hooks/hooks.json no installPath, MODE=without-hooks nao (achado F4).
_setup_plugin_home_fixture() {
  _sphf_home=$1
  _sphf_mode=$2
  _sphf_ip="$_sphf_home/plugins/cache/cstk/6.8.0"
  mkdir -p "$_sphf_home/.claude/plugins" "$_sphf_ip"
  cat > "$_sphf_home/.claude/plugins/installed_plugins.json" <<EOF
{"version":2,"plugins":{"cstk@cstk":[{"scope":"user","installPath":"$_sphf_ip","installedAt":"2026-08-01T00:00:00.000Z","lastUpdated":"2026-08-08T00:00:00.000Z"}]}}
EOF
  cat > "$_sphf_home/.claude/settings.json" <<'EOF'
{"enabledPlugins": {"cstk@cstk": true}}
EOF
  if [ "$_sphf_mode" = "with-hooks" ]; then
    mkdir -p "$_sphf_ip/hooks"
    printf '{"hooks":{}}\n' > "$_sphf_ip/hooks/hooks.json"
  fi
}

# Condicao 1: plugin cobre os hooks -> area pulada, ZERO chamada a
# guard-hooks-status.sh (deteccao classica nem roda), exit 0.
scenario_setup_hooks_dedup_skip_quando_plugin_cobre() {
  _repo="$TMPDIR_TEST/repo-setup-dedup-skip"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-setup-dedup-skip"
  mkdir -p "$_home"
  _setup_plugin_home_fixture "$_home" with-hooks

  _stubbin="$TMPDIR_TEST/stubbin-dedup-skip"
  mkdir -p "$_stubbin"
  _calls="$TMPDIR_TEST/gh-calls-dedup-skip.log"
  : > "$_calls"
  cat > "$_stubbin/guard-hooks-status.sh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$_calls"
exit 1
STUB
  chmod +x "$_stubbin/guard-hooks-status.sh"

  capture env PATH="$_stubbin:$PATH" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --dry-run
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_setup_hooks_dedup_skip_quando_plugin_cobre" \
      "esperado exit 0, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  _n=$(wc -l < "$_calls" | tr -d ' ')
  if [ "$_n" != "0" ]; then
    _fail "scenario_setup_hooks_dedup_skip_quando_plugin_cobre" \
      "guard-hooks-status.sh nao deveria ser chamado (dedup pula deteccao classica); chamadas=$_n"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"dedup, plugin vence"*) ;;
    *)
      _fail "scenario_setup_hooks_dedup_skip_quando_plugin_cobre" \
        "esperava aviso de dedup em stderr: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

# Condicao 2 (F4): plugin habilitado sem hooks.json -> prossegue com
# deteccao classica normalmente (3 chamadas), so com aviso extra.
scenario_setup_hooks_dedup_f4_prossegue_classico() {
  _repo="$TMPDIR_TEST/repo-setup-dedup-f4"
  _make_repo "$_repo"
  _home="$TMPDIR_TEST/home-setup-dedup-f4"
  mkdir -p "$_home"
  _setup_plugin_home_fixture "$_home" without-hooks

  _stubbin="$TMPDIR_TEST/stubbin-dedup-f4"
  mkdir -p "$_stubbin"
  _calls="$TMPDIR_TEST/gh-calls-dedup-f4.log"
  : > "$_calls"
  cat > "$_stubbin/guard-hooks-status.sh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$_calls"
case "\$*" in
  *--verify-registration*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\tcanonical\n'
    exit 0 ;;
  *--include-loose-usage*)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    printf 'posttooluse-loose-usage.sh\tmissing\tunregistered\tunknown\n'
    exit 0 ;;
  *)
    printf 'pretooluse-bash-guard.sh\tpresent\tregistered\tcurrent\n'
    exit 0 ;;
esac
STUB
  chmod +x "$_stubbin/guard-hooks-status.sh"

  # --verbose: a mensagem de inconsistencia F4 e emitida via _setup_info,
  # gated por _SU_VERBOSE (default quiet so mostra o resumo [OK]/[FAIL]).
  capture env PATH="$_stubbin:$PATH" HOME="$_home" CSTK_LIB="$CSTK_LIB" \
    sh "$CSTK" setup --project-path "$_repo" --dry-run --verbose
  if [ "$_CAPTURED_EXIT" != "0" ]; then
    _fail "scenario_setup_hooks_dedup_f4_prossegue_classico" \
      "esperado exit 0, obtido $_CAPTURED_EXIT (stderr: $_CAPTURED_STDERR)"
    return 1
  fi
  _n=$(wc -l < "$_calls" | tr -d ' ')
  if [ "$_n" != "3" ]; then
    _fail "scenario_setup_hooks_dedup_f4_prossegue_classico" \
      "esperava 3 chamadas classicas (F4 nao deve pular deteccao), obteve $_n"
    return 1
  fi
  case "$_CAPTURED_STDERR" in
    *"instalacao do plugin parece incompleta"*) ;;
    *)
      _fail "scenario_setup_hooks_dedup_f4_prossegue_classico" \
        "esperava aviso F4 em stderr: $_CAPTURED_STDERR"
      return 1
      ;;
  esac
}

run_all_scenarios
