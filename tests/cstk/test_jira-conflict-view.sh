#!/bin/sh
# test_jira-conflict-view.sh — cobre
# plugins/cstk-jira/scripts/jira-conflict-view.sh (cstk-jira, FASE 6 tarefa
# 6.3 "Skill jira-sync", subtarefas 6.3.5/6.3.6).
#
# Ref: docs/specs/cstk-jira/spec.md US3; plan.md Fluxo 3 "Sync autonomo";
#      data-model.md Entity ConflictRecord; contracts/jira-rest.md R3;
#      contracts/plugin-scripts.md (convencoes/exit codes); checklists/
#      ux.md CHK011; checklists/security.md CHK005/SEC-2; tasks.md 6.3.5/
#      6.3.6.
#
# Estrategia (mesma disciplina de test_jira-sync.sh): NENHUM cenario toca
# rede de verdade. `jira-conflict-view.sh show` fala com o Jira
# exclusivamente via jira-io.sh, que so fala com o cliente HTTP — os
# cenarios que chegam ate a leitura remota instalam um stub por FILA
# (mesmo mecanismo de test_jira-sync.sh _init_queue_stub/_queue_push).
#
# Invariantes cobertos:
#   CV-1 show: --feature ausente -> exit 2, ZERO chamadas de rede
#   CV-2 show: --feature com charset invalido -> exit 2, ZERO chamadas
#   CV-3 show: --local-key ausente -> exit 2, ZERO chamadas
#   CV-4 show: ProjectConfig ausente -> exit 3 (propagado), ZERO chamadas
#   CV-5 show: credencial ausente -> exit 4 (propagado), ZERO chamadas
#   CV-6 show: nenhum ConflictRecord PENDENTE para (F, K) -> exit 1, apos
#         EXATAMENTE 1 chamada de rede (myself — pre-checagem sempre roda
#         antes da consulta local ao conflito)
#   CV-7 show: ConflictRecord pendente + issue com summary/description/
#         status/comment -> stdout rotula CADA campo como conteudo externo
#         NAO-CONFIAVEL (banner de abertura/fechamento envolvendo
#         titulo/status/descricao/comentarios); conflicts.tsv PERMANECE
#         pending (leitura pura, nenhuma escrita) — este e o teste
#         determinístico exigido por 6.3.6

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk-jira/scripts/jira-conflict-view.sh"

# _write_full_config: ProjectConfig completo e valido (mesmo fixture de
# test_jira-sync.sh _write_full_config).
_write_full_config() {
  mkdir -p "$TMPDIR_TEST/.claude/cstk-jira"
  cat > "$TMPDIR_TEST/.claude/cstk-jira/config" <<'EOF'
config_version=1
site_host=cstk-test.atlassian.net
project_key=DEMO
board_id=1
issue_type_epic=10001
issue_type_task=10004
issue_type_subtask=10002
status_pending=To Do
status_in_progress=In Progress
status_pass=Done
status_fail=Failed
sync_autonomous=on
EOF
}

# _write_credential: credencial GLOBAL isolada — SEMPRE combinar com
# XDG_CONFIG_HOME="$TMPDIR_TEST/xdg" (mesmo padrao de test_jira-sync.sh).
_write_credential() {
  mkdir -p "$TMPDIR_TEST/xdg/cstk-jira"
  printf 'site_host=cstk-test.atlassian.net\nemail=%s\napi_token=%s\n' "tester@example.com" "tok-FAKE-000" \
    > "$TMPDIR_TEST/xdg/cstk-jira/credentials"
  chmod 600 "$TMPDIR_TEST/xdg/cstk-jira/credentials"
}

_conflicts_file() {
  printf '%s\n' "$TMPDIR_TEST/.claude/cstk-jira/runtime/conflicts.tsv"
}

_write_pending_conflict() {
  mkdir -p "$(dirname "$(_conflicts_file)")"
  cat > "$(_conflicts_file)" <<EOF
detected_at	feature	local_key	jira_key	reason	resolution
2026-01-01T00:00:00Z	$1	$2	$3	$4	pending
EOF
}

# --- stub de rede por FILA (identico a test_jira-sync.sh _init_queue_stub,
# duplicado aqui porque cada arquivo de teste e standalone) -----------------
_init_queue_stub() {
  _stub_dir="$TMPDIR_TEST/bin-queue"
  mkdir -p "$_stub_dir"
  : > "$TMPDIR_TEST/queue-curl-queue.tsv"
  : > "$TMPDIR_TEST/queue-curl-calls.log"
  cat > "$_stub_dir/curl" <<STUB
#!/bin/sh
_url=""
_out=""
_method="GET"
_prev=""
for _a in "\$@"; do
  case "\$_prev" in
    -o) _out="\$_a" ;;
    -X) _method="\$_a" ;;
  esac
  case "\$_a" in
    https://*) _url="\$_a" ;;
  esac
  _prev="\$_a"
done
_qfile="$TMPDIR_TEST/queue-curl-queue.tsv"
_callsfile="$TMPDIR_TEST/queue-curl-calls.log"
_n=\$(wc -l < "\$_callsfile" 2>/dev/null | tr -d ' ')
_n=\$((_n + 1))
printf '%s %s\n' "\$_method" "\$_url" >> "\$_callsfile"
_line=\$(sed -n "\${_n}p" "\$_qfile")
if [ -z "\$_line" ]; then
  exit 22
fi
_code=\${_line%%|*}
_body=\${_line#*|}
[ -n "\$_out" ] && printf '%s' "\$_body" > "\$_out"
printf '%s' "\$_code"
exit 0
STUB
  chmod +x "$_stub_dir/curl"
  printf '%s' "$_stub_dir"
}

_queue_push() {
  printf '%s|%s\n' "$1" "$2" >> "$TMPDIR_TEST/queue-curl-queue.tsv"
}

_queue_calls_count() {
  [ -f "$TMPDIR_TEST/queue-curl-calls.log" ] || { printf '0'; return; }
  wc -l < "$TMPDIR_TEST/queue-curl-calls.log" | tr -d ' '
}

# =========================== usage / uso incorreto ==========================

scenario_show_sem_feature_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" show --local-key 1.1 || return 1
  return 0
}

scenario_show_feature_charset_invalido_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" show --feature "de mo" --local-key 1.1 || return 1
  return 0
}

scenario_show_sem_local_key_exit2() {
  cd "$TMPDIR_TEST" || return 1
  assert_exit 2 "$SCRIPT" show --feature demo || return 1
  return 0
}

# =========================== pre-checagens propagadas =======================

# CV-4: sem ProjectConfig -> jira-config.sh validate propaga exit 3, ZERO
# chamadas de rede (deps-check nao toca rede; validate falha antes de
# 'request GET /myself').
scenario_show_config_ausente_exit3_zero_rede() {
  cd "$TMPDIR_TEST" || return 1
  _bin="$(_init_queue_stub)"
  PATH="$_bin:$PATH" assert_exit 3 "$SCRIPT" show --feature demo --local-key 1.1 || return 1
  [ "$(_queue_calls_count)" = "0" ] \
    || { _fail "config_ausente_zero_rede" "esperado 0 chamadas, obtido $(_queue_calls_count)"; return 1; }
  return 0
}

# CV-5: config ok mas credencial ausente -> jira-config.sh credential-check
# propaga exit 4, ZERO chamadas de rede.
scenario_show_credencial_ausente_exit4_zero_rede() {
  _write_full_config
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg-vazio"
  _bin="$(_init_queue_stub)"
  PATH="$_bin:$PATH" assert_exit 4 "$SCRIPT" show --feature demo --local-key 1.1 || return 1
  [ "$(_queue_calls_count)" = "0" ] \
    || { _fail "credencial_ausente_zero_rede" "esperado 0 chamadas, obtido $(_queue_calls_count)"; return 1; }
  return 0
}

# =========================== conflito ausente ================================

# CV-6: pre-checagens OK (1 chamada de rede -> GET /myself) mas nenhum
# ConflictRecord PENDENTE para o par -> exit 1, EXATAMENTE 1 chamada de rede
# (a do precheck; a leitura da issue nunca acontece).
scenario_show_sem_conflito_pendente_exit1() {
  _write_full_config
  _write_credential
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"abc"}'
  PATH="$_bin:$PATH" assert_exit 1 "$SCRIPT" show --feature demo --local-key 1.1 || return 1
  [ "$(_queue_calls_count)" = "1" ] \
    || { _fail "sem_conflito_1_chamada" "esperado 1 chamada (myself), obtido $(_queue_calls_count)"; return 1; }
  return 0
}

# CV-6b: existe ConflictRecord mas para OUTRO par (feature/local_key) ->
# tratado como ausente (nunca casa por coincidencia parcial).
scenario_show_conflito_de_outro_par_exit1() {
  _write_full_config
  _write_credential
  _write_pending_conflict "outra" "9.9" "OUT-1" "orphan"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"abc"}'
  PATH="$_bin:$PATH" assert_exit 1 "$SCRIPT" show --feature demo --local-key 1.1 || return 1
  return 0
}

# =========================== CORE: 6.3.6 ====================================

# CV-7: ConflictRecord pendente + issue real (summary/description/status/
# comment) -> stdout rotula CADA campo como conteudo externo NAO-CONFIAVEL
# ANTES de qualquer decisao ficar disponivel ao operador (a unica acao
# citada e sempre `jira-sync.sh resolve`); conflicts.tsv permanece pending
# (leitura pura).
scenario_show_conflito_pendente_rotula_conteudo_untrusted() {
  _write_full_config
  _write_credential
  _write_pending_conflict "demo" "1.1" "DEMO-2" "manual_edit"
  cd "$TMPDIR_TEST" || return 1
  export XDG_CONFIG_HOME="$TMPDIR_TEST/xdg"
  _bin="$(_init_queue_stub)"
  _queue_push 200 '{"accountId":"abc"}'
  _queue_push 200 '{"fields":{"summary":"Titulo Editado Manualmente no Jira","status":{"name":"In Progress"},"description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Descricao vinda do Jira"}]}]},"comment":{"comments":[{"body":"Comentario vindo do Jira"}],"total":1}}}'
  PATH="$_bin:$PATH" assert_exit 0 "$SCRIPT" show --feature demo --local-key 1.1 || return 1

  assert_stdout_contains "CONTEUDO EXTERNO NAO-CONFIAVEL (Jira DEMO-2)" || return 1
  assert_stdout_contains "FIM CONTEUDO EXTERNO (Jira DEMO-2)" || return 1
  assert_stdout_contains "titulo: Titulo Editado Manualmente no Jira" || return 1
  assert_stdout_contains "status: In Progress" || return 1
  assert_stdout_contains "Descricao vinda do Jira" || return 1
  assert_stdout_contains "Comentario vindo do Jira" || return 1
  assert_stdout_contains "jira-sync.sh resolve --feature demo --local-key 1.1 --choice keep_jira|overwrite|ignored" || return 1

  [ "$(_queue_calls_count)" = "2" ] \
    || { _fail "conflito_pendente_2_chamadas" "esperado 2 chamadas (myself+issue), obtido $(_queue_calls_count)"; return 1; }

  grep -q 'demo	1\.1	DEMO-2	manual_edit	pending$' "$(_conflicts_file)" \
    || { _fail "conflito_permanece_pending" "conflicts.tsv foi alterado por um comando de LEITURA: $(cat "$(_conflicts_file)")"; return 1; }
  [ ! -f "$TMPDIR_TEST/.claude/cstk-jira/runtime/outbox.tsv" ] \
    || { _fail "conflito_nao_cria_outbox" "outbox.tsv nao deveria existir (show nunca enfileira nada)"; return 1; }
  return 0
}

run_all_scenarios
