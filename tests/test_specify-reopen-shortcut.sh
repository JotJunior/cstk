#!/bin/sh
# test_specify-reopen-shortcut.sh — guarda ESTRUTURAL (INTERNO) sobre
# plugins/cstk/skills/specify/SKILL.md §0.0/§0.4/§0.5.
#
# Contexto (feature-reopen FASE 6.1 / dec-058): a §0.0 (atalho de modo
# autonomo) foi estendida para herdar TAMBEM a decisao da §0.4 ("Atualizar
# spec existente vs abrir feature nova") quando o state da execucao
# corrente tem `.previous_round` preenchido (contexto de reabertura via
# `/feature-00c --reopen`). A mudanca e ADITIVA e GATED por desenho: o
# caminho SEM `--reopen` (autonomo normal ou interativo) MUST continuar
# avaliando 0.4 exatamente como antes.
#
# `specify/SKILL.md` e prosa consumida por um agente LLM, nao codigo
# executavel — nao existe (e nao existiu antes desta feature) nenhum
# harness que exercite o COMPORTAMENTO da skill. Este teste e portanto um
# guard de PRESENCA/AUSENCIA de texto (regressao estrutural), nao um teste
# comportamental: garante que (a) a prosa original da secao 0.4 (o
# caminho nao-gated) permanece intacta byte-a-byte nos trechos-chave, e
# (b) a nova prosa gated existe, esta corretamente ancorada em
# `.previous_round`, e declara explicitamente a nao-regressao do caminho
# sem reabertura. Nenhuma alegacao de cobertura comportamental e feita.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_MD="$REPO_ROOT/plugins/cstk/skills/specify/SKILL.md"

# ==== 6.1-a: arquivo existe ====

scenario_skill_md_existe() {
  [ -f "$SKILL_MD" ] || { printf 'SKILL.md nao encontrado: %s\n' "$SKILL_MD" >&2; return 1; }
  return 0
}

# ==== 6.1-b: nao-regressao — prosa original da §0.4 intacta ====

scenario_secao_04_original_intacta() {
  grep -qF '### 0.4 Atualizar spec existente vs abrir feature nova' "$SKILL_MD" || return 1
  grep -qF '**Mesma intencao / refinamento**' "$SKILL_MD" || return 1
  grep -qF '**Intencao mudou / escopo expandiu**' "$SKILL_MD" || return 1
  grep -qF '**Nenhuma spec existente se relaciona ao pedido**' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.1-c: gated — deteccao de .previous_round dentro da 0.0 ====

scenario_deteccao_previous_round_presente() {
  grep -qF "'.previous_round'" "$SKILL_MD" || return 1
  grep -qF 'contexto de reabertura' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.1-d: gated — declaracao explicita de nao-regressao (dec-058) ====

scenario_declaracao_nao_regressao_presente() {
  grep -qF 'Sem esse campo' "$SKILL_MD" || return 1
  grep -qF 'a secao' "$SKILL_MD" || return 1
  grep -qF '0.4 continua sendo avaliada normalmente' "$SKILL_MD" || return 1
  grep -qF 'mudanca de comportamento no caminho sem `--reopen`' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.1-e: modo de incremento (0.5) referenciado e presente ====

scenario_secao_05_modo_incremento_presente() {
  grep -qF '### 0.5 Modo de incremento' "$SKILL_MD" || return 1
  grep -qF '## Delta Requirements' "$SKILL_MD" || return 1
  grep -qF 'FR-014' "$SKILL_MD" || return 1
  # 6.1.3: nunca criar um segundo spec.md para a mesma feature
  grep -qF 'Nunca criar um segundo `spec.md`' "$SKILL_MD" || return 1
  return 0
}

# ==== 6.1-f: ordem estrutural — 0.5 vem depois de 0.4 e antes da ETAPA 1 ====

scenario_ordem_estrutural_0_4_0_5_etapa1() {
  _LN_04=$(grep -n '^### 0.4 Atualizar spec existente' "$SKILL_MD" | head -n1 | cut -d: -f1)
  _LN_05=$(grep -n '^### 0.5 Modo de incremento' "$SKILL_MD" | head -n1 | cut -d: -f1)
  _LN_E1=$(grep -n '^## ETAPA 1: ANALISE' "$SKILL_MD" | head -n1 | cut -d: -f1)
  [ -n "$_LN_04" ] && [ -n "$_LN_05" ] && [ -n "$_LN_E1" ] || return 1
  [ "$_LN_04" -lt "$_LN_05" ] || return 1
  [ "$_LN_05" -lt "$_LN_E1" ] || return 1
  return 0
}

run_all_scenarios
