#!/bin/sh
# test_state-parity-sweep.sh — varredura anti-regressao da paridade do
# runtime com o backend SQLite (feature state-db-runtime-parity, FASE 6.1).
#
# Ref: spec FR-009/FR-010; research.md Decision 5; checklists CHK016/CHK032.
#
# Teste de COMPOSICAO interno (registrado em tests/run.sh::_is_internal_test,
# precedente: test_state-db-concurrency.sh) — nao mapeia 1:1 para um script.
#
# Duas camadas:
#
# (a) DINAMICA — manifest literal dos leitores do FR-001 (15 originais +
#     state-rw.sh infer-aspectos, issues #118/#119/#121/#124), cada um
#     executado contra um state-dir SQLite POPULADO (fixture minima da
#     research §CHK032: 9 passos via primitivas, nunca write direto).
#     Falha se: stdout/stderr contem o marcador de degradacao
#     "state.json ausente"; exit code fora do conjunto contratual aterrado
#     empiricamente (onda-014); ou existe state.json no state-dir apos a
#     varredura (SC-004 anti-mirror).
#
# (b) ESTATICA — grep por CONSTRUCAO DE PATH de state.json (`/state\.json`,
#     operacionalizacao mecanica do criterio codigo-real-vs-prosa de FR-010:
#     mensagem voltada a humano cita "state.json" como palavra, sem barra;
#     acesso real constroi "<dir>/state.json") sobre os scripts do runtime +
#     cli/lib/00c-bootstrap.sh + plugins/cstk/skills/agente-00c-runtime/hooks/*.sh
#     (feature hooks-db-parity FASE 7, task 7.1.1 — a lacuna original que
#     deixou a regressao de triplicacao dos hooks passar despercebida), com
#     linhas de comentario descartadas ANTES do match. Hit em arquivo fora
#     da ALLOWLIST literal abaixo falha o teste (US5 AS2: helper novo com
#     acesso direto e detectado).
#
# Manutencao da allowlist (CHK016): uma entrada por linha
# `<script-basename>:<classificacao>` com classificacao ∈ {prosa,
# codigo-real} e comentario-justificativa. Item novo e adicionado no MESMO
# commit da mudanca que introduz o hit; aprovacao via review do PR. Entrada
# `codigo-real` fora do conjunto canonico (state-rw.sh, _state-rw-db.sh,
# _state-read.sh, state-db-migrate.sh, state-lock.sh) exige que o script
# esteja coberto pelo manifest dinamico ou por testes proprios de backend.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

R="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"

if ! command -v jq >/dev/null 2>&1; then
  printf '# test_state-parity-sweep.sh: jq ausente — pulando\n'
  exit 0
fi

MIN_SQLITE_VER="3.45.1"

_sqlite3_adequate() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  _v=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1) || return 1
  _va=$(printf '%s' "$_v" | cut -d'.' -f1); _vb=$(printf '%s' "$_v" | cut -d'.' -f2); _vc=$(printf '%s' "$_v" | cut -d'.' -f3)
  _ma=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f1); _mb=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f2); _mc=$(printf '%s' "$MIN_SQLITE_VER" | cut -d'.' -f3)
  [ "${_va:-0}" -gt "${_ma:-0}" ] 2>/dev/null && return 0
  [ "${_va:-0}" -lt "${_ma:-0}" ] 2>/dev/null && return 1
  [ "${_vb:-0}" -gt "${_mb:-0}" ] 2>/dev/null && return 0
  [ "${_vb:-0}" -lt "${_mb:-0}" ] 2>/dev/null && return 1
  [ "${_vc:-0}" -ge "${_mc:-0}" ] 2>/dev/null
}

# ==== Fixture CHK032: state-dir SQLite populado via primitivas (9 passos) ====
# Seta globais: SWEEP_HOME, SWEEP_SD. Retorna 1 em falha de fixture.
_mk_populated_sqlite_sd() {
  SWEEP_HOME="$TMPDIR_TEST/home-sweep"
  mkdir -p "$SWEEP_HOME/.claude/cstk"
  printf 'state_backend=sqlite\n' > "$SWEEP_HOME/.claude/cstk/config"
  SWEEP_SD="$TMPDIR_TEST/sd-sweep"

  # 1. init com >=3 key-aspects (drift.sh EXIGE initial_key_aspects)
  env HOME="$SWEEP_HOME" "$R/state-rw.sh" init --state-dir "$SWEEP_SD" \
    --execucao-id "exec-sweep" --projeto-alvo-path "/tmp/p-sweep" \
    --descricao "descricao de teste com tamanho suficiente para validacao" \
    --key-aspects '["parity","sqlite","runtime"]' >/dev/null 2>&1 || return 1
  [ -f "$SWEEP_SD/state.db" ] || return 1

  # 2. 1 onda FECHADA + 1 onda ABERTA (budget/wave-usage/model-routing)
  env HOME="$SWEEP_HOME" "$R/state-ondas.sh" start --state-dir "$SWEEP_SD" >/dev/null 2>&1 || return 1
  env HOME="$SWEEP_HOME" "$R/state-ondas.sh" end --state-dir "$SWEEP_SD" \
    --motivo-termino etapa_concluida_avancando >/dev/null 2>&1 || return 1
  env HOME="$SWEEP_HOME" "$R/state-ondas.sh" start --state-dir "$SWEEP_SD" >/dev/null 2>&1 || return 1

  # 3. 2 decisoes: 1 generica + 1 de roteamento pareada com record-skill
  #    (par Decisao⟷skill p/ state-decisions-reconcile caminho real)
  env HOME="$SWEEP_HOME" "$R/state-decisions.sh" register --state-dir "$SWEEP_SD" \
    --agente "orquestrador-00c" --etapa "briefing" \
    --contexto "Decisao generica para popular a fixture da varredura" \
    --opcoes '["A","B"]' --escolha "A" \
    --justificativa "justificativa com tamanho suficiente aqui" >/dev/null 2>&1 || return 1
  _swp_d2=$(env HOME="$SWEEP_HOME" "$R/state-decisions.sh" register --state-dir "$SWEEP_SD" \
    --agente "orquestrador-00c" --etapa "specify" \
    --contexto "Selecao de modelo para onda 2 (fixture)" \
    --opcoes '["haiku","sonnet"]' --escolha "sonnet" \
    --justificativa "roteamento de fixture para paridade" 2>/dev/null) || return 1
  env HOME="$SWEEP_HOME" "$R/state-ondas.sh" record-skill --state-dir "$SWEEP_SD" \
    --skill model-selector --decisao-id "$_swp_d2" >/dev/null 2>&1 || return 1

  # 4. 1 bloqueio RESPONDIDO (pipeline/issue leem .human_blocks)
  _swp_b1=$(env HOME="$SWEEP_HOME" "$R/bloqueios.sh" register --state-dir "$SWEEP_SD" \
    --decisao-id dec-001 \
    --pergunta "Pergunta de fixture para popular bloqueio?" \
    --contexto-para-resposta "contexto de resposta da fixture" 2>/dev/null) || return 1
  env HOME="$SWEEP_HOME" "$R/bloqueios.sh" respond --state-dir "$SWEEP_SD" \
    --block-id "$_swp_b1" --resposta "resposta de fixture" >/dev/null 2>&1 || return 1

  # 5. 2 pushes circulares (.circular_movement_history nao-vazio)
  env HOME="$SWEEP_HOME" "$R/circular.sh" push --state-dir "$SWEEP_SD" \
    --problema "problema um" --solucao "solucao um" >/dev/null 2>&1 || return 1
  env HOME="$SWEEP_HOME" "$R/circular.sh" push --state-dir "$SWEEP_SD" \
    --problema "problema dois" --solucao "solucao dois" >/dev/null 2>&1 || return 1

  # 6. 1 retro consumida (retro.sh check exige contagem nao-trivial)
  env HOME="$SWEEP_HOME" "$R/retro.sh" consume --state-dir "$SWEEP_SD" >/dev/null 2>&1 || return 1

  # 7. 1 sugestao (.suggestions nao-vazio; pre-condicao de issue.sh)
  env HOME="$SWEEP_HOME" "$R/suggestions.sh" register --state-dir "$SWEEP_SD" \
    --suggestions-file "$TMPDIR_TEST/sweep-sug.md" \
    --skill "specify" --severidade informativa \
    --diagnostico "diagnostico de fixture com pelo menos cinquenta caracteres para passar a trava" \
    --proposta "proposta concreta de fixture" >/dev/null 2>&1 || return 1

  # 8. 1 record-task (.tasks[] nao-vazio p/ schema completo)
  env HOME="$SWEEP_HOME" "$R/state-ondas.sh" record-task --state-dir "$SWEEP_SD" \
    --task-id "1.1" --titulo "Task fixture" --wave-id "onda-002" \
    --outcome pass --testes-rodados 1 --testes-passados 1 --lint-ok true \
    --arquivos '["a.sh"]' --origem execute-task >/dev/null 2>&1 || return 1

  # 9. 1 metrics-bump (.accumulated_metrics.cache.* real)
  env HOME="$SWEEP_HOME" "$R/state-cache.sh" metrics-bump --state-dir "$SWEEP_SD" \
    --tipo hit >/dev/null 2>&1 || return 1
  return 0
}

# ==== Camada (a) DINAMICA ====
# Manifest literal dos 15 leitores do FR-001 (research Decision 6).
# Formato: <label>|<exits aceitos separados por espaco>|<comando...>
# Exits aterrados empiricamente contra a fixture (onda-014):
#   - model-routing idempotent-check: 1 = "nao existe Decisao p/ (onda,T)"
#     e veredito legitimo de leitura (nao degradacao).
#   - state-cache get-resumo: 1 = cache miss legitimo (sem cache populado).
#   - state-lock check-execution-busy: 3 = execucao em_andamento detectada —
#     PROVA de leitura real (degradacao devolveria 0 "estado ausente=livre").
_sweep_manifest() {
  cat <<EOF
budget-check|0|$R/budget.sh check --state-dir $SWEEP_SD
cycles-check|0|$R/cycles.sh check --state-dir $SWEEP_SD
circular-detect|0|$R/circular.sh detect --state-dir $SWEEP_SD
drift-check|0|$R/drift.sh check --state-dir $SWEEP_SD
retro-check|0|$R/retro.sh check --state-dir $SWEEP_SD
suggestions-list|0|$R/suggestions.sh list --state-dir $SWEEP_SD
wave-usage-report-aggregate|0|$R/wave-usage-report.sh aggregate --state-dir $SWEEP_SD --json
model-routing-idempotent-check|0 1|$R/model-routing.sh idempotent-check --state-dir $SWEEP_SD --onda-id onda-002 --subagent-type feature-00c-clarify-asker
model-routing-report-aggregate|0|$R/model-routing-report.sh aggregate --state-dir $SWEEP_SD
state-cache-get-resumo|0 1|$R/state-cache.sh get-resumo --state-dir $SWEEP_SD --artifact briefing
state-validate|0|$R/state-validate.sh --state-dir $SWEEP_SD
state-decisions-reconcile-check|0|$R/state-decisions-reconcile.sh check --state-dir $SWEEP_SD
issue-create-dry-run|0|$R/issue.sh create --state-dir $SWEEP_SD --suggestion-id sug-001 --skill specify --diagnostico diagnostico-de-fixture-com-tamanho-suficiente-para-a-trava-de-cinquenta --proposta proposta-concreta --dry-run
pipeline-require-blockade-resolved|0|$R/pipeline.sh require-blockade-resolved --state-dir $SWEEP_SD --etapa specify
state-lock-check-execution-busy|3|$R/state-lock.sh check-execution-busy --state-dir $SWEEP_SD
state-rw-infer-aspectos|0|$R/state-rw.sh infer-aspectos --state-dir $SWEEP_SD --projeto-alvo-path $SWEEP_SD
EOF
}

scenario_dinamica_16_leitores_sqlite_sem_degradacao() {
  _sqlite3_adequate || { printf '# skip: sqlite3 real >= %s indisponivel\n' "$MIN_SQLITE_VER"; return 0; }
  _mk_populated_sqlite_sd || { _error "fixture" "construcao da fixture CHK032 falhou"; return 2; }

  _fails=""
  _count=0
  _tmpout="$TMPDIR_TEST/sweep-out.txt"
  _sweep_manifest > "$TMPDIR_TEST/sweep-manifest.txt"
  while IFS='|' read -r _label _exits _cmd; do
    [ -n "$_label" ] || continue
    _count=$((_count + 1))
    _rc=0
    # split intencional: o manifest controla o argv
    # shellcheck disable=SC2086
    env HOME="$SWEEP_HOME" $_cmd > "$_tmpout" 2>&1 || _rc=$?
    if grep -q 'state\.json ausente' "$_tmpout"; then
      _fails="$_fails $_label(DEGRADADO:state.json-ausente)"
      continue
    fi
    _ok=1
    for _e in $_exits; do
      [ "$_rc" = "$_e" ] && _ok=0
    done
    [ "$_ok" = 0 ] || _fails="$_fails $_label(exit=$_rc,esperado:$_exits)"
  done < "$TMPDIR_TEST/sweep-manifest.txt"

  [ "$_count" = 16 ] || { _fail "manifest" "esperado 16 leitores, obtido $_count"; return 1; }
  [ -z "$_fails" ] || { _fail "leitores degradados/divergentes" "$_fails"; return 1; }

  # SC-004 anti-mirror: nenhum state.json materializado DENTRO do state-dir
  [ ! -e "$SWEEP_SD/state.json" ] || { _fail "anti-mirror" "state.json apareceu no state-dir apos a varredura"; return 1; }
}

# ==== Camada (b) ESTATICA ====
# Allowlist CHK016 (formato <basename>:<classificacao>). Justificativas:
#   state-rw.sh:codigo-real        — interface canonica (builder + sha256)
#   _state-rw-db.sh:codigo-real    — fundacao do backend (conjunto canonico)
#   _state-read.sh:codigo-real     — fallback JSON do materializador (FR-004)
#   state-db-migrate.sh:codigo-real— migracao json->db LE state.json por definicao
#   state-lock.sh:codigo-real      — _SL_STATE usado so no fluxo JSON (research D5)
#   bloqueios.sh:codigo-real       — mutador dual-backend: builder do fluxo JSON
#   spawn-tracker.sh:codigo-real   — idem (dual-backend desde state-db-foundation)
#   state-decisions.sh:codigo-real — idem
#   state-ondas.sh:codigo-real     — idem
#   report.sh:prosa                — linha de texto markdown gerado (path de
#                                    exemplo no corpo do relatorio)
#   wave-usage-report.sh:prosa     — "transcript/state.json" em mensagem de erro
#
# Feature hooks-db-parity FASE 7 (task 7.1.2) adiciona:
#   _hook-active-exec.sh:codigo-real — fundacao do backend para os hooks;
#                                    helper unico de deteccao tri-estado,
#                                    mesma familia do conjunto canonico acima
#   pretooluse-bash-guard.sh:codigo-real       — pre-check inline (`[ -f ]`
#   posttooluse-tool-call-tick.sh:codigo-real  — apenas, sem jq/sourcing)
#   posttooluse-agent-usage.sh:codigo-real     — MUST pelo contrato SEC-H1/
#     dec-026/FR-008 (contracts/hook-active-exec.md), ANTES de resolver ou
#     sourcear o helper: "existe ao menos um state.json OU state.db sob
#     .../agente-00c-state/ ou .../feature-00c-state/*/?". Checagem
#     SIMETRICA de existencia (nunca le/parseia conteudo, nunca so
#     state.json) — nao e a classe de regressao que este sweep cacha
#     (leitura direta que quebraria sob backend so-sqlite); e o fast-path
#     que garante 100% das sessoes manuais nao tocarem em arquivo nenhum.
#     tasks.md 7.1.3 pedia os 3 hooks FORA da allowlist; a divergencia e do
#     desenho ja ratificado (SEC-H1 e MUST), nao um erro de implementacao —
#     mesmo precedente de tasks.md 4.2.1.
#
# Feature loose-usage-capture adiciona:
#   posttooluse-loose-usage.sh:codigo-real — mesma classe dos 3 hooks acima:
#     pre-check inline de existencia (`[ -f state.json ] || [ -f state.db ]`,
#     builtins puros, sem jq/sourcing) ANTES de resolver
#     _hook-active-exec.sh (SEC-H1/dec-006, polaridade invertida). Checagem
#     SIMETRICA (nunca le/parseia conteudo, nunca so state.json) — nao
#     quebra sob backend so-sqlite.
#
# Feature feature-reopen (FASE 2) adiciona:
#   state-rounds.sh:codigo-real — os 3 hits remanescentes sao SO checagem
#     de existencia (`[ -f DIR/state.json ]`), nunca leitura de conteudo:
#     (a) list — determina o rotulo de backend impresso na linha de saida
#     (b) rotate — pre-condicao 1 ("ha estado a rotacionar?", mesma familia
#         do `[ -f state.json ] || [ -f state.db ]` dos hooks acima)
#     (c) rotate — decide se `state.json.sha256` entra no conjunto de
#         arquivos movidos (rotacao move arquivos, nao interpreta conteudo)
#     As 2 leituras de CONTEUDO que existiam neste script (meta id/status
#     em _sr_read_meta e finished_at em `list`) foram migradas para
#     `state_read_materialize` (_state-read.sh) neste mesmo commit — nao
#     restam mais leituras diretas de state.json. codigo-real fora do
#     conjunto canonico coberto por `tests/test_state-rounds.sh` (18
#     cenarios, inclusive backend sqlite e json).
_static_allowlist() {
  cat <<'EOF'
state-rw.sh:codigo-real
_state-rw-db.sh:codigo-real
_state-read.sh:codigo-real
state-db-migrate.sh:codigo-real
state-lock.sh:codigo-real
bloqueios.sh:codigo-real
spawn-tracker.sh:codigo-real
state-decisions.sh:codigo-real
state-ondas.sh:codigo-real
report.sh:prosa
wave-usage-report.sh:prosa
_hook-active-exec.sh:codigo-real
pretooluse-bash-guard.sh:codigo-real
posttooluse-tool-call-tick.sh:codigo-real
posttooluse-agent-usage.sh:codigo-real
posttooluse-loose-usage.sh:codigo-real
state-rounds.sh:codigo-real
EOF
}

# _static_hits FILE -> imprime (uma por linha) os numeros de linha onde FILE
# constroi um path de state.json (`/state\.json`), descartando linhas de
# comentario ANTES do match (criterio CHK016) — match por CONSTRUCAO DE
# PATH, nao por mencao em mensagem (palavra sem barra = prosa por
# construcao). Fatorado de scenario_estatica_sem_acesso_direto_fora_da_
# allowlist (task 7.1.1) para ser reusavel pelo cenario negativo dedicado
# (task 7.1.4).
_static_hits() {
  grep -n '/state\.json' "$1" 2>/dev/null | awk -F: '
    { line=$0; sub(/^[0-9]+:/,"",line); gsub(/^[[:space:]]+/,"",line);
      if (line !~ /^#/) print $1 }'
}

scenario_estatica_sem_acesso_direto_fora_da_allowlist() {
  _viol=""
  for _f in "$R"/*.sh "$REPO_ROOT/cli/lib/00c-bootstrap.sh" \
            "$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks"/*.sh; do
    [ -f "$_f" ] || continue
    _base=$(basename "$_f")
    _hits=$(_static_hits "$_f")
    [ -n "$_hits" ] || continue
    if ! _static_allowlist | grep -q "^$_base:"; then
      _viol="$_viol $_base(linhas:$(printf '%s' "$_hits" | tr '\n' ','))"
    fi
  done
  [ -z "$_viol" ] || { _fail "acesso direto a state.json fora da allowlist" "$_viol — adicionar via interface canonica (_state-read.sh) ou registrar na allowlist com classificacao+justificativa no MESMO commit"; return 1; }
}

# ---- 7.1.4: cenario negativo — introduzir path direto num hook e confirmar
# que o mecanismo de deteccao aponta arquivo e linha ----
#
# Nao modifica os hooks reais (regressao deliberada so num scratch file, via
# TMPDIR_TEST); exercita a MESMA funcao (_static_hits) usada pelo scenario
# acima, contra um arquivo cujo basename nunca esta na allowlist real —
# prova que o mecanismo de deteccao (nao so a allowlist ja aprovada hoje)
# continua vivo e discrimina codigo real de comentario.
scenario_estatica_deteccao_regressao_deliberada_em_hook() {
  _rogue="$TMPDIR_TEST/rogue-hook.sh"
  cat > "$_rogue" <<'ROGUE'
#!/bin/sh
# NAO construir "$dir/state.json" diretamente aqui (apenas documentacao)
_dir="$1"
if [ -f "$_dir/state.json" ]; then
  cat "$_dir/state.json"
fi
ROGUE

  _hits=$(_static_hits "$_rogue")
  [ -n "$_hits" ] || { _fail "deteccao" "esperado hit de construcao direta de path no arquivo injetado, obtido nenhum"; return 1; }

  # Linha 2 (comentario, com barra antes de state.json) NAO deve contar;
  # linhas 4 e 5 (codigo real) DEVEM.
  case "$_hits" in
    *2*) _fail "falso positivo" "linha de comentario (2) nao deveria ser reportada; hits=$_hits"; return 1 ;;
  esac
  case "$_hits" in
    *4*) : ;;
    *) _fail "falso negativo" "esperado linha 4 (construcao real) reportada; hits=$_hits"; return 1 ;;
  esac
  case "$_hits" in
    *5*) : ;;
    *) _fail "falso negativo" "esperado linha 5 (construcao real) reportada; hits=$_hits"; return 1 ;;
  esac

  # basename do scratch nunca esta na allowlist real -> se este arquivo
  # estivesse no conjunto varrido pelo scenario principal, seria classificado
  # como violacao (mesma condicao usada la).
  _base=$(basename "$_rogue")
  if _static_allowlist | grep -q "^$_base:"; then
    _fail "allowlist" "arquivo de teste nao deveria estar pre-aprovado na allowlist real"; return 1
  fi
}

scenario_estatica_allowlist_sem_entradas_mortas() {
  # Entrada morta (arquivo listado sem hit real) mascara regressao futura:
  # exigimos que cada entrada da allowlist ainda tenha pelo menos 1 hit.
  _dead=""
  _hooks_dir="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/hooks"
  for _entry in $(_static_allowlist | cut -d: -f1); do
    if [ "$_entry" = "00c-bootstrap.sh" ]; then
      _f="$REPO_ROOT/cli/lib/00c-bootstrap.sh"
    elif [ -f "$_hooks_dir/$_entry" ]; then
      _f="$_hooks_dir/$_entry"
    else
      _f="$R/$_entry"
    fi
    if [ ! -f "$_f" ]; then
      _dead="$_dead $_entry(arquivo-inexistente)"
      continue
    fi
    _hits=$(_static_hits "$_f")
    # Excecao: entradas do conjunto canonico podem ficar sem hit (a lista
    # canonica e estavel por contrato, nao por contagem de hits).
    case "$_entry" in
      state-rw.sh|_state-rw-db.sh|_state-read.sh|state-db-migrate.sh) continue ;;
    esac
    [ -n "$_hits" ] || _dead="$_dead $_entry(sem-hit)"
  done
  [ -z "$_dead" ] || { _fail "allowlist com entrada morta" "$_dead — remover a entrada obsoleta"; return 1; }
}

run_all_scenarios
