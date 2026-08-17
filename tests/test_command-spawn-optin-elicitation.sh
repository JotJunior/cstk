#!/bin/sh
# test_command-spawn-optin-elicitation.sh — smoke textual sobre a FASE 10
# (task 10.1) da feature mcp-elicitation-optins.
#
# Feature: mcp-elicitation-optins
# Ref: docs/specs/mcp-elicitation-optins/tasks.md FASE 10 (10.1.1-10.1.6)
#      docs/specs/mcp-elicitation-optins/plan.md §Estrategia de Testes
#      docs/specs/mcp-elicitation-optins/quickstart.md Scenario 1b
#      docs/specs/mcp-elicitation-optins/contracts/optin-capture-order.md
#
# Natureza: assert TEXTUAL sobre os 4 commands (agente-00c.md,
# agente-00c-resume.md, feature-00c.md, feature-00c-resume.md), os 2 agents
# orquestradores e o source TypeScript de `collect_optins.ts` — mesmo padrao
# de test_command-spawn-delivery-tier.sh (enum/mapeamento/escopo negativo),
# test_command-spawn-roadmap-mode.sh (default seguro) e
# test_command-spawn-mcp-lifecycle.sh:62-68 (assercao de ORDEM por numero de
# linha). NAO mapeia 1:1 a um unico script de skill — registrado interno em
# tests/run.sh::_is_internal_test (10.1.7).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_AGENTE_RES="$REPO_ROOT/plugins/cstk/commands/agente-00c-resume.md"
CMD_FEATURE="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"
CMD_FEATURE_RES="$REPO_ROOT/plugins/cstk/commands/feature-00c-resume.md"
AGENT_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"
AGENT_FEATURE="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"
COLLECT_OPTINS_TS="$REPO_ROOT/mcp/state-server/src/tools/collect_optins.ts"

_first_line_of() {
  # $1=arquivo $2=pattern (grep -E) -> numero da 1a linha casada, ou vazio
  grep -nE "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1
}

_last_line_of() {
  grep -nE "$2" "$1" 2>/dev/null | tail -1 | cut -d: -f1
}

# ---------- 10.1.1: ordem do ramo estruturado (assercao por numero de linha) ----------
#
# Cadeia completa init < mcp-start < spawn < collect_optins < state-ondas.sh
# start atravessa DOIS documentos por par (command de init + agent
# orquestrador correspondente, ligados pelo spawn): dentro do command, init <
# mcp-start(real, secao de ciclo-de-vida — NAO o probe de 2.bis, que roda
# ANTES do proprio init so para decidir o ramo) < cabecalho da secao de
# spawn; dentro do agent, "primeiro ato" de collect_optins < chamada literal
# de state-ondas.sh start.

scenario_ordem_agente_init_mcpstart_spawn() {
  _l_init=$(_first_line_of "$CMD_AGENTE" 'Inicializar .state\.json. v1\.0\.0 via')
  _l_mcp=$(_last_line_of "$CMD_AGENTE" 'cstk mcp start --state-dir')
  _l_spawn=$(_first_line_of "$CMD_AGENTE" '^### 4\. Selecao de modelo')
  [ -n "$_l_init" ] && [ -n "$_l_mcp" ] && [ -n "$_l_spawn" ] \
    || { _error "ancora ausente" "init=$_l_init mcp=$_l_mcp spawn=$_l_spawn"; return 2; }
  [ "$_l_init" -lt "$_l_mcp" ] || { _fail "ordem" "init ($_l_init) deveria vir antes de mcp start real ($_l_mcp)"; return 1; }
  [ "$_l_mcp" -lt "$_l_spawn" ] || { _fail "ordem" "mcp start real ($_l_mcp) deveria vir antes do spawn ($_l_spawn)"; return 1; }
  return 0
}

scenario_ordem_feature_init_mcpstart_spawn() {
  _l_init=$(_first_line_of "$CMD_FEATURE" 'state-rw\.sh init --state-dir')
  _l_mcp=$(_last_line_of "$CMD_FEATURE" 'cstk mcp start --state-dir')
  _l_spawn=$(_first_line_of "$CMD_FEATURE" '^### 4\. Selecionar modelo')
  [ -n "$_l_init" ] && [ -n "$_l_mcp" ] && [ -n "$_l_spawn" ] \
    || { _error "ancora ausente" "init=$_l_init mcp=$_l_mcp spawn=$_l_spawn"; return 2; }
  [ "$_l_init" -lt "$_l_mcp" ] || { _fail "ordem" "init ($_l_init) deveria vir antes de mcp start real ($_l_mcp)"; return 1; }
  [ "$_l_mcp" -lt "$_l_spawn" ] || { _fail "ordem" "mcp start real ($_l_mcp) deveria vir antes do spawn ($_l_spawn)"; return 1; }
  return 0
}

scenario_ordem_agente_collect_optins_antes_de_state_ondas_start() {
  _l_primeiro_ato=$(_first_line_of "$AGENT_AGENTE" '\*\*primeiro ato\*\*')
  _l_onda=$(_first_line_of "$AGENT_AGENTE" '^2\. \*\*Onda nova\*\*: .state-ondas\.sh start')
  [ -n "$_l_primeiro_ato" ] && [ -n "$_l_onda" ] \
    || { _error "ancora ausente" "primeiro_ato=$_l_primeiro_ato onda=$_l_onda"; return 2; }
  [ "$_l_primeiro_ato" -lt "$_l_onda" ] \
    || { _fail "ordem" "collect_optins primeiro-ato ($_l_primeiro_ato) deveria vir antes de state-ondas.sh start ($_l_onda)"; return 1; }
  return 0
}

scenario_ordem_feature_collect_optins_antes_de_state_ondas_start() {
  # "primeiro ato" quebra de linha no markdown fonte (**primeiro\n   ato**
  # em agente-00c-feature-orchestrator.md) — usa o inicio do bloco 3.bis
  # como ancora robusta a rewrap.
  _l_primeiro_ato=$(_first_line_of "$AGENT_FEATURE" '3\.bis \*\*Coleta de opt-ins via MCP')
  _l_onda=$(_first_line_of "$AGENT_FEATURE" '^4\. \*\*Iniciar onda\*\* via .state-ondas\.sh start')
  [ -n "$_l_primeiro_ato" ] && [ -n "$_l_onda" ] \
    || { _error "ancora ausente" "3bis=$_l_primeiro_ato onda=$_l_onda"; return 2; }
  [ "$_l_primeiro_ato" -lt "$_l_onda" ] \
    || { _fail "ordem" "bloco 3.bis ($_l_primeiro_ato) deveria vir antes de state-ondas.sh start ($_l_onda)"; return 1; }
  return 0
}

# ---------- 10.1.2: ramo legado preservado ----------
#
# Nos 2 commands de INIT (agente-00c.md, feature-00c.md): a prosa de opt-in
# (ancora textual "byte-a-byte, FR-005", ja validada por
# test_command-spawn-optin-degradation.sh::scenario_legado_byte_a_byte_documentado)
# continua posicionada ANTES do `state-rw.sh init` real — o ramo legado nao
# foi movido para depois do init.
#
# Nos 2 commands de RESUME (agente-00c-resume.md, feature-00c-resume.md): a
# preservacao e estrutural, nao posicional — estes commands NUNCA chamaram
# `state-rw.sh init` nem tiveram prompt de opt-in antes desta feature (FASE
# 5.2/5.4, "idempotencia de retomada" — o resume so LE `.optin_responses[]`
# via `delivery-tier.sh get`/equivalentes). Continuarem ausentes os dois e a
# prova de que o ramo legado nao vazou para o caminho de retomada.

scenario_ramo_legado_prosa_antes_do_init_agente() {
  _l_prosa=$(_first_line_of "$CMD_AGENTE" 'byte-a-byte, FR-005')
  _l_init=$(_first_line_of "$CMD_AGENTE" 'Inicializar .state\.json. v1\.0\.0 via')
  [ -n "$_l_prosa" ] && [ -n "$_l_init" ] || { _error "ancora ausente" "prosa=$_l_prosa init=$_l_init"; return 2; }
  [ "$_l_prosa" -lt "$_l_init" ] || { _fail "ordem" "prosa legada ($_l_prosa) deveria vir antes do init ($_l_init)"; return 1; }
  return 0
}

scenario_ramo_legado_prosa_antes_do_init_feature() {
  _l_prosa=$(_first_line_of "$CMD_FEATURE" 'byte-a-byte, FR-005')
  _l_init=$(_first_line_of "$CMD_FEATURE" 'state-rw\.sh init --state-dir')
  [ -n "$_l_prosa" ] && [ -n "$_l_init" ] || { _error "ancora ausente" "prosa=$_l_prosa init=$_l_init"; return 2; }
  [ "$_l_prosa" -lt "$_l_init" ] || { _fail "ordem" "prosa legada ($_l_prosa) deveria vir antes do init ($_l_init)"; return 1; }
  return 0
}

scenario_resume_nunca_reintroduziu_init_nem_prompt() {
  for _f in "$CMD_AGENTE_RES" "$CMD_FEATURE_RES"; do
    [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }
    assert_exit 1 grep -Fq 'state-rw.sh init' "$_f" || return 1
    assert_exit 1 grep -Fq 'Habilitar o modo atomic-commit? [s/N]' "$_f" || return 1
  done
  return 0
}

# ---------- 10.1.3 + 10.1.4: correcao dos comentarios stale sobre mode=bash-fallback ----------
#
# A5 (plan.md linha 38): `mode=bash-fallback` nunca e de fato ESCRITO
# (dec-034; ja coberto funcionalmente por
# test_orchestrator-mcp-fallback.sh::scenario_start_sem_docker_funciona_mode_direct_exit_0).
# O papel deste teste e textual: (a) a formulacao antiga que tratava
# `mode=bash-fallback` como um desfecho REAL e alcancavel ("degrada sozinho
# para mode=bash-fallback", tasks.md 5.1.4/5.3.2; e a variante solta
# "(mode=bash-fallback ou init sem Docker)" nos blocos de `mcp stop`
# terminal, corrigida na onda-016) esta AUSENTE dos 4 commands; (b) o novo
# discriminador correto (token vazio/descritor ausente, dec-034) esta
# PRESENTE nos 4. NAO exige ausencia total do literal `mode=bash-fallback`
# em TODO lugar — a explicacao CORRECAO (dec-034) em agente-00c.md/
# feature-00c.md cita o literal deliberadamente, dentro de uma negacao
# ("nao ha caminho de codigo que produza..."), e essa citacao e o
# PRECEDENTE textual que a propria task 5.3.2 instrui preservar
# (`_mcp_token` vazio "bash-fallback" / sem descritor). Testar ausencia
# total apagaria esse precedente sem ganho (net negative) — o invariante
# real e "nenhum command trata bash-fallback como desfecho alcancavel",
# nao "a substring nunca aparece".

scenario_stale_claim_ausente_agente() {
  assert_exit 1 grep -Fq 'degrada sozinho para mode=bash-fallback' "$CMD_AGENTE" || return 1
  assert_exit 1 grep -Fq 'mode=bash-fallback ou init sem Docker' "$CMD_AGENTE" || return 1
  assert_exit 0 grep -Fq 'CORRECAO (dec-034)' "$CMD_AGENTE" || return 1
  return 0
}

scenario_stale_claim_ausente_feature() {
  assert_exit 1 grep -Fq 'degrada sozinho para mode=bash-fallback' "$CMD_FEATURE" || return 1
  assert_exit 1 grep -Fq 'mode=bash-fallback ou init sem Docker' "$CMD_FEATURE" || return 1
  assert_exit 0 grep -Fq 'CORRECAO (dec-034)' "$CMD_FEATURE" || return 1
  return 0
}

scenario_stale_claim_ausente_nos_resumes() {
  for _f in "$CMD_AGENTE_RES" "$CMD_FEATURE_RES"; do
    assert_exit 1 grep -Fq 'mode=bash-fallback ou init sem Docker' "$_f" || return 1
    assert_exit 0 grep -Fq 'dec-034' "$_f" || return 1
  done
  return 0
}

# scenario_seis_valores_outcome_preservados ja cobre a leitura do enum de
# outcome em collect_optins.ts (test_command-spawn-optin-degradation.sh);
# aqui so confirmamos que o precedente textual da linha ~558/795
# (`_mcp_token` vazio) continua intacto nos 2 commands de init — e ele quem
# justifica a nao-exigencia de ausencia total do literal.
scenario_precedente_mcp_token_vazio_intacto() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    assert_exit 0 grep -Fq '`_mcp_token` vazio (`bash-fallback` / sem descritor)' "$_f" || return 1
  done
  return 0
}

# ---------- 10.1.5: condicionalidade de --allow-downgrade (A2/dec-047) ----------
#
# Fonte: mcp/state-server/src/tools/collect_optins.ts (unico ponto que monta
# o argv de `delivery-tier.sh set`). Nao ha teste Node gateado (dec-027) —
# a assercao aqui e sobre o CODIGO-FONTE que decide o argv, nao sobre uma
# execucao real (quickstart.md Scenario 1b cobre a prova funcional,
# nao-gateada).

scenario_allow_downgrade_condicional_no_source() {
  [ -f "$COLLECT_OPTINS_TS" ] || { _error "arquivo ausente" "$COLLECT_OPTINS_TS"; return 2; }
  # 1. a flag so e empurrada dentro do guard de ordinal estritamente menor
  assert_exit 0 grep -Fq 'if (tierOrdinal(wireValue) < tierOrdinal(currentTier)) {' "$COLLECT_OPTINS_TS" || return 1
  assert_exit 0 grep -Fq 'args.push("--allow-downgrade");' "$COLLECT_OPTINS_TS" || return 1
  assert_exit 0 grep -Fq 'dec-047' "$COLLECT_OPTINS_TS" || return 1
  # 2. push da flag e SEMPRE precedido (poucas linhas antes) pelo guard —
  #    nao ha um SEGUNDO push desacoplado do guard (flag incondicional)
  _n_push=$(grep -c 'args\.push("--allow-downgrade")' "$COLLECT_OPTINS_TS")
  [ "$_n_push" = "1" ] || { _fail "push_nao_unico" "esperado exatamente 1 args.push(--allow-downgrade), obtido $_n_push"; return 1; }
  return 0
}

scenario_allow_downgrade_ausente_em_desfechos_degradados() {
  [ -f "$COLLECT_OPTINS_TS" ] || { _error "arquivo ausente" "$COLLECT_OPTINS_TS"; return 2; }
  # writeDeliveryTier (que monta o argv com a flag) so pode ser chamada UMA
  # vez em todo o arquivo: a definicao da funcao ("async function
  # writeDeliveryTier(") + exatamente 1 call-site (dentro do ramo
  # outcome==="accepted", apos o allowlist check). decline/cancel/absent/
  # failed-de-allowlist gravam SAFE_DEFAULTS diretamente e nunca chamam a
  # funcao (Invariante C-3) — logo NUNCA montam argv com a flag.
  _n_total=$(grep -c 'writeDeliveryTier(' "$COLLECT_OPTINS_TS")
  [ "$_n_total" = "2" ] || { _fail "call_sites_inesperados" "esperado 2 ocorrencias (def + 1 call-site), obtido $_n_total"; return 1; }
  assert_exit 0 grep -Fq 'Invariante C-3: so escreve camada 1 para outcome === "accepted".' "$COLLECT_OPTINS_TS" || return 1
  return 0
}

# ---------- 10.1.6: escopo negativo — feature-00c* nao oferece delivery_tier ----------

scenario_escopo_feature00c_sem_delivery_tier_no_source() {
  [ -f "$COLLECT_OPTINS_TS" ] || { _error "arquivo ausente" "$COLLECT_OPTINS_TS"; return 2; }
  assert_exit 0 grep -Fq '"feature-00c": ["atomic_commit"],' "$COLLECT_OPTINS_TS" || return 1
  assert_exit 0 grep -Fq '"agente-00c": ["atomic_commit", "roadmap_mode", "delivery_tier"],' "$COLLECT_OPTINS_TS" || return 1
  return 0
}

scenario_escopo_feature00c_sem_delivery_tier_no_orquestrador() {
  assert_exit 0 grep -Fq 'para `feature-00c` isso e SOMENTE `atomic_commit`' "$AGENT_FEATURE" || return 1
  assert_exit 1 grep -Fq 'delivery_tier' "$AGENT_FEATURE" || return 1
  return 0
}

# ---------- FASE 12 (dec-107): provisionamento de .mcp.json no pre-flight ----------
#
# Sem isto o ramo estruturado so funcionava quando o projeto-alvo JA tinha
# cstk-state registrado (ex.: o proprio repo cstk) — em qualquer OUTRO
# projeto-alvo, `cstk mcp start` mintava um token normalmente mas o HARNESS
# desta sessao nunca teria a tool `collect_optins` de fato disponivel,
# porque `.mcp.json` e lido no BOOT da sessao (achado do E2E Scenario 1,
# dec-107). Os 2 commands de INIT agora chamam `cstk mcp install
# --project-path` (idempotente, best-effort) ANTES do probe, e so tratam o
# ramo como "estruturado" quando `.mcp.json` JA tinha `cstk-state` ANTES
# desta invocacao.

scenario_provisionamento_mcp_install_agente() {
  _l_install=$(_first_line_of "$CMD_AGENTE" 'cstk mcp install --project-path')
  _l_probe=$(_first_line_of "$CMD_AGENTE" 'cstk mcp status --state-dir "<SD>" >/dev/null 2>&1; then')
  [ -n "$_l_install" ] && [ -n "$_l_probe" ] \
    || { _error "ancora ausente" "install=$_l_install probe=$_l_probe"; return 2; }
  [ "$_l_install" -lt "$_l_probe" ] \
    || { _fail "ordem" "mcp install ($_l_install) deveria vir antes do probe estruturado ($_l_probe)"; return 1; }
  return 0
}

scenario_provisionamento_mcp_install_feature() {
  _l_install=$(_first_line_of "$CMD_FEATURE" 'cstk mcp install --project-path')
  _l_probe=$(_first_line_of "$CMD_FEATURE" 'cstk mcp status --state-dir "\$AGENTE_00C_STATE_DIR" >/dev/null 2>&1; then')
  [ -n "$_l_install" ] && [ -n "$_l_probe" ] \
    || { _error "ancora ausente" "install=$_l_install probe=$_l_probe"; return 2; }
  [ "$_l_install" -lt "$_l_probe" ] \
    || { _fail "ordem" "mcp install ($_l_install) deveria vir antes do probe estruturado ($_l_probe)"; return 1; }
  return 0
}

scenario_probe_gated_por_mcpjson_pre_agente() {
  assert_exit 0 grep -Fq 'if [ -n "$_optin_mcpjson_pre" ] && cstk mcp status --state-dir "<SD>"' "$CMD_AGENTE" || return 1
  assert_exit 0 grep -Fq 'grep -q '"'"'"cstk-state"'"'"' "<PAP>/.mcp.json"' "$CMD_AGENTE" || return 1
  return 0
}

scenario_probe_gated_por_mcpjson_pre_feature() {
  assert_exit 0 grep -Fq 'if [ -n "$_optin_mcpjson_pre" ] && cstk mcp status --state-dir "$AGENTE_00C_STATE_DIR"' "$CMD_FEATURE" || return 1
  assert_exit 0 grep -Fq 'grep -q '"'"'"cstk-state"'"'"' "$_proj/.mcp.json"' "$CMD_FEATURE" || return 1
  return 0
}

# ---------- FASE 12 (dec-107): prosa legada persiste .optin_responses[] ----------
#
# Sem isto o guard M4 (`_so_check_optin_invariant`) travava mudo TODA
# execucao no ramo legado desde o inicio (nunca so a degradacao mid-call de
# 4.bis persistia) — mesmo com a prosa tendo rodado e o `state.json` ja
# tendo os valores aplicados via flags de `init`. Ordem: bloco de
# persistencia (3.ter) vem DEPOIS do `init` e ANTES do ciclo de vida do
# servidor MCP (3.quater/3.bis).

scenario_persistencia_legado_optin_responses_agente() {
  _l_init=$(_first_line_of "$CMD_AGENTE" 'Inicializar .state\.json. v1\.0\.0 via')
  _l_persist=$(_first_line_of "$CMD_AGENTE" '### 3\.ter Persistir opt-ins do ramo legado')
  _l_mcp_lifecycle=$(_first_line_of "$CMD_AGENTE" '^### 3\.quater Ciclo de vida do servidor MCP')
  [ -n "$_l_init" ] && [ -n "$_l_persist" ] && [ -n "$_l_mcp_lifecycle" ] \
    || { _error "ancora ausente" "init=$_l_init persist=$_l_persist mcp=$_l_mcp_lifecycle"; return 2; }
  [ "$_l_init" -lt "$_l_persist" ] \
    || { _fail "ordem" "init ($_l_init) deveria vir antes da persistencia (3.ter, $_l_persist)"; return 1; }
  [ "$_l_persist" -lt "$_l_mcp_lifecycle" ] \
    || { _fail "ordem" "persistencia (3.ter, $_l_persist) deveria vir antes do ciclo de vida MCP (3.quater, $_l_mcp_lifecycle)"; return 1; }
  assert_exit 0 grep -Fq 'channel: "prose", outcome: $o, applied_value: $v' "$CMD_AGENTE" || return 1
  assert_exit 0 grep -Fq 'for _pair in "atomic_commit:$_atomic" "roadmap_mode:$_roadmap" "delivery_tier:$_tier"' "$CMD_AGENTE" || return 1
  return 0
}

scenario_persistencia_legado_optin_responses_feature() {
  _l_init=$(_first_line_of "$CMD_FEATURE" 'state-rw\.sh init --state-dir')
  _l_persist=$(_first_line_of "$CMD_FEATURE" '### 3\.ter Persistir opt-in do ramo legado')
  _l_mcp_lifecycle=$(_first_line_of "$CMD_FEATURE" '^### 3\.bis Ciclo de vida do servidor MCP')
  [ -n "$_l_init" ] && [ -n "$_l_persist" ] && [ -n "$_l_mcp_lifecycle" ] \
    || { _error "ancora ausente" "init=$_l_init persist=$_l_persist mcp=$_l_mcp_lifecycle"; return 2; }
  [ "$_l_init" -lt "$_l_persist" ] \
    || { _fail "ordem" "init ($_l_init) deveria vir antes da persistencia (3.ter, $_l_persist)"; return 1; }
  [ "$_l_persist" -lt "$_l_mcp_lifecycle" ] \
    || { _fail "ordem" "persistencia (3.ter, $_l_persist) deveria vir antes do ciclo de vida MCP (3.bis, $_l_mcp_lifecycle)"; return 1; }
  assert_exit 0 grep -Fq 'field: "atomic_commit", channel: "prose", outcome: $o' "$CMD_FEATURE" || return 1
  # escopo negativo: feature-00c nunca persiste roadmap_mode/delivery_tier
  # nesta secao (so entre a ancora 3.ter e a proxima secao 3.bis)
  _block=$(sed -n "${_l_persist},${_l_mcp_lifecycle}p" "$CMD_FEATURE")
  case "$_block" in
    *'field: "roadmap_mode"'*|*'field: "delivery_tier"'*)
      _fail "escopo_vazado" "3.ter de feature-00c nao deveria persistir roadmap_mode/delivery_tier"; return 1 ;;
  esac
  return 0
}

run_all_scenarios "$@"
