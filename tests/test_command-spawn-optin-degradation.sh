#!/bin/sh
# test_command-spawn-optin-degradation.sh — smoke textual sobre a FASE 6
# (fallback integral para prosa) da feature mcp-elicitation-optins.
#
# Feature: mcp-elicitation-optins
# Ref: docs/specs/mcp-elicitation-optins/tasks.md FASE 6 (6.1, 6.2)
#      docs/specs/mcp-elicitation-optins/contracts/optin-capture-order.md §3.3(b), §4
#      docs/specs/mcp-elicitation-optins/data-model.md §Registros terminais x
#        nao-terminais (R-1/R-2/R-3), §Enum outcome
#
# Natureza: assert TEXTUAL sobre os 4 arquivos de prosa (2 commands + 2
# agents) — mesmo padrao de tests/test_command-spawn-roadmap-mode.sh e
# tests/test_orchestrator-allowlist-guard.sh. Nao ha helper POSIX novo: a
# "implementacao" da FASE 6 e o bloco de prosa/pseudo-shell embutido nos
# arquivos .md que orientam o command pai e o orquestrador subagente.
#
# Cobre as DUAS trilhas de FR-005/SC-003/SC-006 (US3-AC1/US3-AC2): (a) o
# ramo LEGADO quando o mecanismo NUNCA esteve disponivel (token vazio desde
# o inicio) permanece byte-a-byte intacto; (b) a degradacao MID-CALL
# (mecanismo existia, `elicitation/create` falhou) converge para o MESMO
# comportamento observavel do operador (mesma prosa/defaults), distinguindo-
# se apenas por 1 linha de aviso em stderr presente SOMENTE na trilha (b).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_AGENTE="$REPO_ROOT/plugins/cstk/commands/agente-00c.md"
CMD_FEATURE="$REPO_ROOT/plugins/cstk/commands/feature-00c.md"
AGENT_AGENTE="$REPO_ROOT/plugins/cstk/agents/agente-00c-orchestrator.md"
AGENT_FEATURE="$REPO_ROOT/plugins/cstk/agents/agente-00c-feature-orchestrator.md"

# ---------- 6.1.1: trilha (a) — ramo legado permanece intacto ----------

# scenario_legado_byte_a_byte_documentado (6.1.1)
# O texto que declara a garantia byte-a-byte da secao 3 (prosa ANTES do
# init) precisa continuar presente e inalterado nos 2 commands — e o
# ANCORA textual que a FASE 6 nao pode regredir (contracts §4).
scenario_legado_byte_a_byte_documentado() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }
    assert_exit 0 grep -Fq 'byte-a-byte, FR-005' "$_f" || return 1
  done
  return 0
}

# scenario_prompt_atomic_commit_intacto (6.1.1)
# O prompt de opt-in de commit atomico (secao 3, ramo legado) continua
# presente ipsis litteris nos 2 commands — nenhuma reescrita "para
# uniformizar com o ramo estruturado" (regressao que o contrato proibe
# explicitamente em §4).
scenario_prompt_atomic_commit_intacto() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    assert_exit 0 grep -Fq 'Habilitar o modo atomic-commit? [s/N]' "$_f" || return 1
  done
  return 0
}

# ---------- 6.1.2: as DUAS trilhas convergem ----------

# scenario_degradacao_reusa_prompt_legado (6.1.2)
# A secao 4.bis (degradacao mid-call) roda o MESMO bloco de prosa da
# secao 3 (nao reescreve um prompt paralelo) — garante que as respostas
# observadas pelo operador sao identicas nas duas trilhas.
scenario_degradacao_reusa_prompt_legado() {
  assert_exit 0 grep -Fq 'EXATAMENTE o mesmo bloco de prosa da secao 3 acima' "$CMD_FEATURE" || return 1
  assert_exit 0 grep -Fq 'EXATAMENTE os mesmos blocos de prosa da secao 3 acima' "$CMD_AGENTE" || return 1
  return 0
}

# scenario_degradacao_zero_mencao_mcp (6.1.2, US3-AC1/AC2)
# O operador nao percebe que o mecanismo estruturado existiu — nenhuma
# mencao a MCP no prompt reaproveitado.
scenario_degradacao_zero_mencao_mcp() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    assert_exit 0 grep -Fq 'zero mencao ao MCP' "$_f" || return 1
  done
  return 0
}

# scenario_aviso_stderr_somente_failed (6.1.2/6.2.1, FR-009/SC-005)
# A UNICA diferenca observavel entre as 2 trilhas: o aviso de 1 linha em
# stderr, presente SOMENTE no sub-caso "failed" — "unavailable" e
# documentado como silencioso nos 2 orquestradores.
scenario_aviso_stderr_somente_failed() {
  for _f in "$AGENT_AGENTE" "$AGENT_FEATURE"; do
    assert_exit 0 grep -Fq 'SOMENTE no sub-caso' "$_f" || return 1
    assert_exit 0 grep -Fq 'exatamente uma linha' "$_f" || return 1
    assert_exit 0 grep -Fq 'SILENCIOSO' "$_f" || return 1
  done
  return 0
}

# scenario_seis_valores_outcome_preservados (FR-004)
# O enum de 6 outcomes (accepted/declined/absent/timeout/unavailable/
# failed) e a origem canonica do dado real — validar que a fonte
# (collect_optins.ts) continua declarando os 6 valores; a prosa dos
# orquestradores nunca deve inventar um 7o outcome.
scenario_seis_valores_outcome_preservados() {
  _src="$REPO_ROOT/plugins/cstk/mcp/state-server/src/tools/collect_optins.ts"
  [ -f "$_src" ] || { _error "arquivo ausente" "$_src"; return 2; }
  for _v in accepted declined absent timeout unavailable failed; do
    assert_exit 0 grep -Fq "\"$_v\"" "$_src" || return 1
  done
  return 0
}

# ---------- 6.2.1: orquestrador nao abre onda em unavailable|failed ----------

scenario_orquestrador_nao_abre_onda_em_degradacao() {
  for _f in "$AGENT_AGENTE" "$AGENT_FEATURE"; do
    assert_exit 0 grep -Fq 'NAO chame `state-ondas.sh start`' "$_f" || return 1
    assert_exit 0 grep -Fq 'devolva o turno ao command pai' "$_f" || return 1
  done
  return 0
}

# scenario_orquestrador_le_mechanism (6.2.1)
scenario_orquestrador_le_mechanism() {
  for _f in "$AGENT_AGENTE" "$AGENT_FEATURE"; do
    assert_exit 0 grep -Fq 'result.mechanism' "$_f" || return 1
    assert_exit 0 grep -Fq 'mechanism: "structured"' "$_f" || return 1
  done
  return 0
}

# ---------- 6.2.2: pai le .optin_responses[], roda prosa, re-spawna ----------

scenario_pai_le_sinal_estrutural() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    assert_exit 0 grep -Fq '.optin_responses[]?' "$_f" || return 1
    assert_exit 0 grep -Fq 'Sinal estrutural, nunca o' "$_f" || return 1
  done
  return 0
}

scenario_pai_persiste_channel_prose() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    assert_exit 0 grep -Fq 'channel: "prose"' "$_f" || return 1
  done
  return 0
}

scenario_pai_re_spawna_apos_prosa() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    assert_exit 0 grep -Fq 're-spawne o' "$_f" || return 1
  done
  return 0
}

# ---------- 6.2.3: anti-loop (R-3), operador nunca perguntado 2x ----------

scenario_anti_loop_r3_documentado() {
  for _f in "$CMD_AGENTE" "$CMD_FEATURE" "$AGENT_AGENTE" "$AGENT_FEATURE"; do
    assert_exit 0 grep -Fq 'R-3' "$_f" || return 1
  done
  return 0
}

scenario_cap_m6_reuse_documentado() {
  for _f in "$AGENT_AGENTE" "$AGENT_FEATURE"; do
    assert_exit 0 grep -Fq 'retorna `reused`' "$_f" || return 1
    assert_exit 0 grep -Fq 'cap M6' "$_f" || return 1
  done
  for _f in "$CMD_AGENTE" "$CMD_FEATURE"; do
    assert_exit 0 grep -Fq 'cap M6' "$_f" || return 1
  done
  return 0
}

scenario_operador_nunca_perguntado_duas_vezes() {
  for _f in "$AGENT_AGENTE" "$AGENT_FEATURE"; do
    assert_exit 0 grep -Fq 'NUNCA e perguntado duas vezes' "$_f" || return 1
  done
  return 0
}

# ---------- Confinamento de escopo (paridade dec-083) ----------

# scenario_escopo_feature00c_so_atomic_commit (dec-083)
# A secao NOVA (4.bis) de feature-00c.md nunca OPERA sobre roadmap_mode/
# delivery_tier (setters/persistencia) — mesmo confinamento que
# test_command-spawn-roadmap-mode.sh ja garante para o ramo legado. Uma
# UNICA linha de esclarecimento de escopo ("sao exclusivos de agente-00c")
# e permitida — o que a secao NAO pode fazer e chamar os setters desses
# campos nem persistir registros `.optin_responses[]` para eles.
scenario_escopo_feature00c_so_atomic_commit() {
  # Isola so o corpo da secao 4.bis (entre o header dela e o proximo "### 5.")
  _body=$(awk '/^### 4\.bis /{f=1} f && /^### 5\. /{exit} f' "$CMD_FEATURE")
  [ -n "$_body" ] || { _fail "secao_ausente" "$CMD_FEATURE: secao 4.bis nao encontrada"; return 1; }
  if printf '%s\n' "$_body" | grep -Fq 'roadmap-mode.sh set-enabled'; then
    _fail "escopo_vazou" "$CMD_FEATURE: secao 4.bis opera roadmap-mode.sh — feature-00c so oferece atomic_commit (dec-083)"
    return 1
  fi
  if printf '%s\n' "$_body" | grep -Fq 'delivery-tier.sh set'; then
    _fail "escopo_vazou" "$CMD_FEATURE: secao 4.bis opera delivery-tier.sh — feature-00c so oferece atomic_commit (dec-083)"
    return 1
  fi
  return 0
}

# scenario_escopo_agente00c_tres_campos (contraste positivo)
scenario_escopo_agente00c_tres_campos() {
  _body=$(awk '/^### 4\.bis /{f=1} f && /^### 5\.pre /{exit} f' "$CMD_AGENTE")
  [ -n "$_body" ] || { _fail "secao_ausente" "$CMD_AGENTE: secao 4.bis nao encontrada"; return 1; }
  for _campo in atomic_commit roadmap_mode delivery_tier; do
    printf '%s\n' "$_body" | grep -Fq "$_campo" || {
      _fail "campo_ausente" "$CMD_AGENTE: secao 4.bis nao cobre '$_campo'"
      return 1
    }
  done
  return 0
}

run_all_scenarios "$0"
