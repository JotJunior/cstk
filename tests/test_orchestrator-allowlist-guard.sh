#!/bin/sh
# test_orchestrator-allowlist-guard.sh — FASE 1 da feature
# orchestrator-mcp-allowlist (guard de composicao de allowlist).
#
# Feature: orchestrator-mcp-allowlist
# Ref: docs/specs/orchestrator-mcp-allowlist/tasks.md FASE 1 (1.1)
#      docs/specs/orchestrator-mcp-allowlist/contracts/orchestrator-allowlist-guard.md
#      docs/specs/orchestrator-mcp-allowlist/spec.md FR-002, FR-003, FR-004, FR-012
#
# Natureza: scenario-based, POSIX sh puro, SEM jq (research.md Decision 4).
# Substitui a garantia estrutural que `tests/test_orchestrator-mcp-fallback.sh`
# cobria via regex `^\s*-\s*mcp__` (linhas 61 e 70) — essa regex so casava a
# forma de LISTA YAML de `tools:` e por isso era INERTE contra a forma
# INLINE (`tools: A, B, mcp__x`) realmente usada nos 7 agentes do repo
# (research.md Decision 1). Este guard parseia AS DUAS formas (inline e
# lista) e protege a garantia real: a allowlist nunca pode ficar vazia nem
# so-MCP — nao "nao pode ter mcp__*" (essa era a garantia cerimonial
# revogada por FR-001, ver tarefa 2.1).
#
# Descoberta de alvos: glob `plugins/cstk/agents/*-orchestrator.md`, NUNCA
# lista hardcodeada (dec-016/FR-002) — se o glob nao casar nada, e um
# ponto-cego (research Decision 3), coberto por
# scenario_orchestrator_glob_nao_vazio.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

AGENTS_DIR="$REPO_ROOT/plugins/cstk/agents"

# ---------- Contrato de parsing (contracts/orchestrator-allowlist-guard.md) ----------

# _frontmatter_block FILE
# Imprime as linhas entre a 1a e a 2a linha `---` (delimitadores
# excluidos). Fora desse bloco NADA e lido — evita casar `mcp__` na prosa
# do agente.
_frontmatter_block() {
  awk '
    /^---[[:space:]]*$/ {
      n++
      if (n == 1) { next }
      if (n == 2) { exit }
    }
    n == 1 { print }
  ' "$1"
}

# _tools_key_present FILE -> exit 0 se a chave `tools:` existe no
# frontmatter, 1 caso contrario.
_tools_key_present() {
  _frontmatter_block "$1" | grep -qE '^tools:'
}

# _tools_entries FILE
# Imprime (uma por linha) as entradas normalizadas de `tools:`, cobrindo
# as DUAS formas:
#   - inline: `tools: A, B, C` na mesma linha (split por virgula)
#   - lista:  `tools:` seguido de linhas `- A` ate a proxima chave de
#             frontmatter ou o fim do bloco
# Trim de espacos; entradas vazias descartadas.
_tools_entries() {
  _frontmatter_block "$1" | awk '
  {
    if (mode == "collect") {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
        val = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", val)
        gsub(/[[:space:]]+$/, "", val)
        if (val != "") print val
        next
      } else {
        mode = "none"
      }
    }
    if ($0 ~ /^tools:/) {
      val = $0
      sub(/^tools:[[:space:]]*/, "", val)
      gsub(/[[:space:]]+$/, "", val)
      if (val != "") {
        n = split(val, arr, ",")
        for (i = 1; i <= n; i++) {
          e = arr[i]
          gsub(/^[[:space:]]+/, "", e)
          gsub(/[[:space:]]+$/, "", e)
          if (e != "") print e
        }
        mode = "none"
      } else {
        mode = "collect"
      }
    }
  }
  '
}

# _native_entries FILE -> entradas SEM o prefixo mcp__
_native_entries() {
  _tools_entries "$1" | grep -v '^mcp__' 2>/dev/null || :
}

# _mcp_entries FILE -> entradas COM o prefixo mcp__
_mcp_entries() {
  _tools_entries "$1" | grep '^mcp__' 2>/dev/null || :
}

# _classify_allowlist FILE
# Imprime um dos vereditos: tools_key_absent | empty_allowlist |
# mcp_only_allowlist | pass — mesma tabela de decisao da secao "State
# transitions" de data-model.md / tabela do contrato.
_classify_allowlist() {
  _cl_f="$1"
  if ! _tools_key_present "$_cl_f"; then
    printf '%s\n' "tools_key_absent"
    return 0
  fi
  _cl_entries=$(_tools_entries "$_cl_f")
  if [ -z "$_cl_entries" ]; then
    printf '%s\n' "empty_allowlist"
    return 0
  fi
  _cl_native=$(printf '%s\n' "$_cl_entries" | grep -v '^mcp__' 2>/dev/null || :)
  if [ -z "$_cl_native" ]; then
    printf '%s\n' "mcp_only_allowlist"
    return 0
  fi
  printf '%s\n' "pass"
  return 0
}

# _guidance_block FILE
# Imprime o conteudo entre os marcadores MCP-VS-BASH:BEGIN/END (exclusive).
# Vazio se os marcadores estiverem ausentes ou o corpo estiver vazio.
_guidance_block() {
  awk '
    /^<!-- MCP-VS-BASH:BEGIN -->[[:space:]]*$/ { f = 1; next }
    /^<!-- MCP-VS-BASH:END -->[[:space:]]*$/ { f = 0 }
    f { print }
  ' "$1"
}

# _list_orchestrator_targets
# Emite (uma por linha) os paths absolutos casados pelo glob canonico.
_list_orchestrator_targets() {
  for _t in "$AGENTS_DIR"/*-orchestrator.md; do
    [ -f "$_t" ] || continue
    printf '%s\n' "$_t"
  done
}

# ---------- Fixtures sinteticas (tabela "Casos negativos" do contrato) ----------
# Escritas SEMPRE em $TMPDIR_TEST (mktemp -d por scenario, via
# mktemp_test do harness) — NUNCA os agentes reais sao editados.

_fixture_so_mcp_inline() {
  cat > "$TMPDIR_TEST/so-mcp-inline.md" <<'EOF'
---
name: fixture-so-mcp-inline
tools: mcp__cstk-state__open_wave, mcp__cstk-state__get_status
---
body
EOF
  printf '%s\n' "$TMPDIR_TEST/so-mcp-inline.md"
}

_fixture_so_mcp_lista() {
  cat > "$TMPDIR_TEST/so-mcp-lista.md" <<'EOF'
---
name: fixture-so-mcp-lista
tools:
  - mcp__cstk-state__open_wave
---
body
EOF
  printf '%s\n' "$TMPDIR_TEST/so-mcp-lista.md"
}

_fixture_vazia() {
  cat > "$TMPDIR_TEST/vazia.md" <<'EOF'
---
name: fixture-vazia
tools:
description: 'sem entradas'
---
body
EOF
  printf '%s\n' "$TMPDIR_TEST/vazia.md"
}

_fixture_ausente() {
  cat > "$TMPDIR_TEST/ausente.md" <<'EOF'
---
name: fixture-ausente
description: 'frontmatter sem chave tools'
---
body
EOF
  printf '%s\n' "$TMPDIR_TEST/ausente.md"
}

_fixture_mista_inline() {
  cat > "$TMPDIR_TEST/mista-inline.md" <<'EOF'
---
name: fixture-mista-inline
tools: Bash, mcp__cstk-state__open_wave
---
body
EOF
  printf '%s\n' "$TMPDIR_TEST/mista-inline.md"
}

_fixture_mista_lista() {
  cat > "$TMPDIR_TEST/mista-lista.md" <<'EOF'
---
name: fixture-mista-lista
tools:
  - Bash
  - mcp__cstk-state__open_wave
---
body
EOF
  printf '%s\n' "$TMPDIR_TEST/mista-lista.md"
}

_fixture_so_nativa() {
  cat > "$TMPDIR_TEST/so-nativa.md" <<'EOF'
---
name: fixture-so-nativa
tools: Agent, Skill, Bash
---
body
EOF
  printf '%s\n' "$TMPDIR_TEST/so-nativa.md"
}

# _fixture_item8_correto / _fixture_item8_invertido (FASE 7.2.3, dec-089)
# Fixtures MINIMAS com marcadores MCP-VS-BASH reais, isolando so o item 8
# (nao os demais 8 itens de conteudo minimo). A versao "invertido" mantem
# o literal `elicitation/create` (para provar que uma assercao so por esse
# literal e cega) mas reescreve a semantica para "sempre permitido" —
# removendo as duas frases que amarram o recorte (b) da FASE 7.1.1.
_fixture_item8_correto() {
  cat > "$TMPDIR_TEST/item8-correto.md" <<'EOF'
---
name: fixture-item8-correto
tools: Bash
---
<!-- MCP-VS-BASH:BEGIN -->
8. `elicitation/create` tem dois recortes: (a) permitido — disparar
   collect_optins quando ha operador humano presente na sessao; (b) fora
   de escopo — sem operador humano presente permanece Deferred (FR-010).
<!-- MCP-VS-BASH:END -->
EOF
  printf '%s\n' "$TMPDIR_TEST/item8-correto.md"
}

_fixture_item8_invertido() {
  cat > "$TMPDIR_TEST/item8-invertido.md" <<'EOF'
---
name: fixture-item8-invertido
tools: Bash
---
<!-- MCP-VS-BASH:BEGIN -->
8. `elicitation/create` e SEMPRE permitido, independente de operador
   humano estar presente na sessao. Nao ha excecao: nada fica pendente
   nem aguardando definicao futura.
<!-- MCP-VS-BASH:END -->
EOF
  printf '%s\n' "$TMPDIR_TEST/item8-invertido.md"
}

# ---------- Scenarios sobre os alvos REAIS (glob) ----------

# scenario_orchestrator_glob_nao_vazio (anti-ponto-cego, research Decision 3)
scenario_orchestrator_glob_nao_vazio() {
  _n=$(_list_orchestrator_targets | wc -l | tr -d ' ')
  if [ "$_n" -eq 0 ]; then
    _fail "no_orchestrator_found" "glob $AGENTS_DIR/*-orchestrator.md nao casou nenhum arquivo"
    return 1
  fi
  return 0
}

# scenario_allowlist_nunca_vazia_nem_so_mcp (FR-002, FR-004)
scenario_allowlist_nunca_vazia_nem_so_mcp() {
  _targets=$(_list_orchestrator_targets)
  if [ -z "$_targets" ]; then
    _error "sem_alvos" "nenhum orquestrador encontrado para avaliar"
    return 2
  fi
  _old_ifs="$IFS"
  IFS='
'
  for _t in $_targets; do
    IFS="$_old_ifs"
    _verdict=$(_classify_allowlist "$_t")
    if [ "$_verdict" != "pass" ]; then
      _fail "$_verdict" "$_t: allowlist reprovada com veredito '$_verdict'"
      return 1
    fi
  done
  IFS="$_old_ifs"
  return 0
}

# scenario_allowlist_declara_as_9_tools_mcp (FR-003 + FASE 7.2/dec-087,
# dec-089; human-bridge FASE 2 task 2.7 — 9a tool `ask_operator`)
# Comparacao LITERAL contra as 9 entradas exatas — nunca regex
# `mcp__cstk-state__.*` (plan.md "Convencoes de Borda", protege contra
# typo silencioso). A 8a tool (`collect_optins`, feature
# `mcp-elicitation-optins`) foi incluida no required set porque e o
# PRIMEIRO ato do orquestrador (bootstrap da onda-001) — sem este scenario
# exigindo-a, a tool pode ser removida do frontmatter sem que o guard
# acuse (mesma classe do guard inerte revogado em
# orchestrator-mcp-allowlist). A 9a tool (`ask_operator`, feature
# `human-bridge`, contrato mcp-tool-ask-operator.md §9 "Cobertura") entra
# pelo MESMO motivo. Prova por mutacao em
# scenario_prova_deteccao_mutacao_collect_optins abaixo.
scenario_allowlist_declara_as_9_tools_mcp() {
  _targets=$(_list_orchestrator_targets)
  if [ -z "$_targets" ]; then
    _error "sem_alvos" "nenhum orquestrador encontrado para avaliar"
    return 2
  fi
  _required="mcp__cstk-state__open_wave
mcp__cstk-state__record_decision
mcp__cstk-state__record_skill
mcp__cstk-state__record_task
mcp__cstk-state__register_human_block
mcp__cstk-state__close_wave
mcp__cstk-state__get_status
mcp__cstk-state__collect_optins
mcp__cstk-state__ask_operator"
  _old_ifs="$IFS"
  IFS='
'
  for _t in $_targets; do
    IFS="$_old_ifs"
    _present=$(_mcp_entries "$_t")
    _missing=""
    _ifs2="$IFS"
    IFS='
'
    for _req in $_required; do
      IFS="$_ifs2"
      case "$_present" in
        *"$_req"*) : ;;
        *) _missing="$_missing $_req" ;;
      esac
    done
    IFS="$_ifs2"
    if [ -n "$_missing" ]; then
      _fail "mcp_tools_missing" "$_t: faltam tools mcp__cstk-state__* =>$_missing"
      return 1
    fi
  done
  IFS="$_old_ifs"
  return 0
}

# scenario_prova_mutacao_ask_operator_removido_de_cada_orquestrador
# (human-bridge task 5.2.9, Cenario 12 do quickstart, passos 2-3): prova
# por mutacao de que `scenario_allowlist_declara_as_9_tools_mcp` NAO e cega
# — a comentario da linha ~318 referenciava um
# `scenario_prova_deteccao_mutacao_collect_optins` que nunca chegou a
# existir neste arquivo (achado desta task); esta e a prova real,
# equivalente, para a 9a tool (`ask_operator`). Copia CADA orquestrador
# REAL para uma fixture em $TMPDIR_TEST (harness NUNCA edita os agentes
# reais), remove SO a entrada `mcp__cstk-state__ask_operator` do `tools:`
# inline, e roda a MESMA logica de required-set de
# scenario_allowlist_declara_as_9_tools_mcp contra a fixture mutada —
# confirmando FAIL citando o orquestrador. Repete para os DOIS
# orquestradores reais (passos 2 e 3 do Cenario 12).
scenario_prova_mutacao_ask_operator_removido_de_cada_orquestrador() {
  _targets=$(_list_orchestrator_targets)
  if [ -z "$_targets" ]; then
    _error "sem_alvos" "nenhum orquestrador encontrado para avaliar"
    return 2
  fi
  _old_ifs="$IFS"
  IFS='
'
  for _t in $_targets; do
    IFS="$_old_ifs"
    _base=$(basename "$_t")
    _mutant="$TMPDIR_TEST/mutant-$_base"
    # Remove SO a 9a tool da linha `tools:` inline — preserva as outras 8 e
    # todo o resto do arquivo intacto (mutacao minima e representativa).
    sed 's/, mcp__cstk-state__ask_operator//' "$_t" > "$_mutant"
    if grep -q 'mcp__cstk-state__ask_operator' "$_mutant"; then
      _fail "mutante_ainda_contem_ask_operator" "$_base: sed nao removeu a entrada — fixture nao reproduz a mutacao pretendida"
      return 1
    fi
    _present=$(_mcp_entries "$_mutant")
    case "$_present" in
      *"mcp__cstk-state__ask_operator"*)
        _fail "mutacao_nao_detectada" "$_base: fixture mutada ainda reporta ask_operator presente"
        return 1
        ;;
    esac
    # A logica real (scenario_allowlist_declara_as_9_tools_mcp) FALHARIA
    # para esta fixture: confirma que a ausencia e VISIVEL ao parser, nao
    # so ausente do grep isolado acima (evita falso-positivo por parsing
    # quebrado que "some" com tudo, nao so com a 9a tool).
    _outras_presentes=$(printf '%s\n' "$_present" | grep -c '^mcp__cstk-state__' || :)
    [ "$_outras_presentes" -eq 8 ] || {
      _fail "parsing_quebrado" "$_base: fixture mutada deveria preservar EXATAMENTE as outras 8 tools mcp__cstk-state__*, achou $_outras_presentes"
      return 1
    }
  done
  IFS="$_old_ifs"
  return 0
}

# scenario_allowlist_preserva_bash (FR-004: "no minimo, a tool de
# execucao de comandos")
scenario_allowlist_preserva_bash() {
  _targets=$(_list_orchestrator_targets)
  if [ -z "$_targets" ]; then
    _error "sem_alvos" "nenhum orquestrador encontrado para avaliar"
    return 2
  fi
  _old_ifs="$IFS"
  IFS='
'
  for _t in $_targets; do
    IFS="$_old_ifs"
    _native=$(_native_entries "$_t")
    case "$_native" in
      *Bash*) : ;;
      *)
        _fail "bash_ausente" "$_t: Bash ausente de native_entries"
        return 1
        ;;
    esac
  done
  IFS="$_old_ifs"
  return 0
}

# ---------- Scenarios sobre as fixtures sinteticas (uma por veredito) ----------

scenario_fixture_so_mcp_inline_falha_mcp_only() {
  _f=$(_fixture_so_mcp_inline)
  _v=$(_classify_allowlist "$_f")
  [ "$_v" = "mcp_only_allowlist" ] || {
    _fail "veredito_inesperado" "fixture so-MCP inline: esperado mcp_only_allowlist, obtido $_v"
    return 1
  }
  return 0
}

scenario_fixture_so_mcp_lista_falha_mcp_only() {
  _f=$(_fixture_so_mcp_lista)
  _v=$(_classify_allowlist "$_f")
  [ "$_v" = "mcp_only_allowlist" ] || {
    _fail "veredito_inesperado" "fixture so-MCP lista: esperado mcp_only_allowlist, obtido $_v"
    return 1
  }
  return 0
}

scenario_fixture_vazia_falha_empty_allowlist() {
  _f=$(_fixture_vazia)
  _v=$(_classify_allowlist "$_f")
  [ "$_v" = "empty_allowlist" ] || {
    _fail "veredito_inesperado" "fixture vazia: esperado empty_allowlist, obtido $_v"
    return 1
  }
  return 0
}

scenario_fixture_ausente_falha_tools_key_absent() {
  _f=$(_fixture_ausente)
  _v=$(_classify_allowlist "$_f")
  [ "$_v" = "tools_key_absent" ] || {
    _fail "veredito_inesperado" "fixture ausente: esperado tools_key_absent, obtido $_v"
    return 1
  }
  return 0
}

scenario_fixture_mista_inline_passa() {
  _f=$(_fixture_mista_inline)
  _v=$(_classify_allowlist "$_f")
  [ "$_v" = "pass" ] || {
    _fail "veredito_inesperado" "fixture mista inline: esperado pass, obtido $_v"
    return 1
  }
  return 0
}

scenario_fixture_mista_lista_passa() {
  _f=$(_fixture_mista_lista)
  _v=$(_classify_allowlist "$_f")
  [ "$_v" = "pass" ] || {
    _fail "veredito_inesperado" "fixture mista lista: esperado pass, obtido $_v"
    return 1
  }
  return 0
}

scenario_fixture_so_nativa_passa() {
  _f=$(_fixture_so_nativa)
  _v=$(_classify_allowlist "$_f")
  [ "$_v" = "pass" ] || {
    _fail "veredito_inesperado" "fixture so-nativa: esperado pass, obtido $_v"
    return 1
  }
  return 0
}

# scenario_prova_deteccao_forma_inline (tasks.md 1.1.8)
# PROVA EXPLICITA de que o guard NOVO detecta a forma inline — o guard
# ANTIGO (tests/test_orchestrator-mcp-fallback.sh:61 e :70, regex
# `^\s*-\s*mcp__`) so casava a forma de LISTA e por isso NUNCA teria
# reprovado a fixture "so-MCP inline" abaixo nem validado a "mista
# inline". Teste dedicado que reproduziria o bug antigo (research.md
# Decision 1) se a cobertura da forma inline fosse removida do parser.
scenario_prova_deteccao_forma_inline() {
  _so_mcp=$(_fixture_so_mcp_inline)
  _v_so_mcp=$(_classify_allowlist "$_so_mcp")
  if [ "$_v_so_mcp" != "mcp_only_allowlist" ]; then
    _fail "forma_inline_nao_detectada_so_mcp" "so-MCP inline deveria falhar com mcp_only_allowlist, obtido $_v_so_mcp — o guard nao detecta a forma inline (reproducao do bug do guard antigo)"
    return 1
  fi

  _mista=$(_fixture_mista_inline)
  _v_mista=$(_classify_allowlist "$_mista")
  if [ "$_v_mista" != "pass" ]; then
    _fail "forma_inline_nao_detectada_mista" "mista inline deveria passar, obtido $_v_mista — o guard nao esta lendo entradas nativas da forma inline"
    return 1
  fi

  return 0
}

# scenario_prova_mutacao_item8_inverte_semantica (tasks.md 7.2.3, Scenario
# 9.3) PROVA de que a assercao de item8 (8a/8b/8c em
# scenario_guidance_block_conteudo_minimo) NAO e cega a uma reescrita que
# inverte a semantica do item 8 mantendo o literal `elicitation/create`.
# A fixture invertida mantem 8a mas remove 8b ("quando ha operador humano
# presente") e 8c ("permanece Deferred") — reproduzindo em miniatura o que
# aconteceria se um dos 2 orquestradores reais fosse mutado dessa forma.
scenario_prova_mutacao_item8_inverte_semantica() {
  _correto=$(_fixture_item8_correto)
  _body_correto=$(_guidance_block "$_correto")
  printf '%s\n' "$_body_correto" | grep -qF 'elicitation/create' || {
    _fail "fixture_correta_sem_8a" "fixture item8-correto deveria conter o literal elicitation/create"
    return 1
  }
  printf '%s\n' "$_body_correto" | grep -qF 'quando ha operador humano presente' || {
    _fail "fixture_correta_sem_8b" "fixture item8-correto deveria conter 'quando ha operador humano presente'"
    return 1
  }
  printf '%s\n' "$_body_correto" | grep -qF 'permanece Deferred' || {
    _fail "fixture_correta_sem_8c" "fixture item8-correto deveria conter 'permanece Deferred'"
    return 1
  }

  _invertido=$(_fixture_item8_invertido)
  _body_invertido=$(_guidance_block "$_invertido")
  printf '%s\n' "$_body_invertido" | grep -qF 'elicitation/create' || {
    _fail "fixture_invertida_sem_literal" "fixture item8-invertido deveria PRESERVAR o literal elicitation/create (senao a mutacao nao e representativa do risco descrito em 7.2.2)"
    return 1
  }
  if printf '%s\n' "$_body_invertido" | grep -qF 'quando ha operador humano presente'; then
    _fail "mutacao_nao_detectada_8b" "fixture invertida NAO deveria conter 'quando ha operador humano presente' — se contem, a fixture nao reproduz a inversao de semantica"
    return 1
  fi
  if printf '%s\n' "$_body_invertido" | grep -qF 'permanece Deferred'; then
    _fail "mutacao_nao_detectada_8c" "fixture invertida NAO deveria conter 'permanece Deferred' — se contem, a fixture nao reproduz a inversao de semantica"
    return 1
  fi

  return 0
}

# ---------- Scenarios do bloco de orientacao MCP-vs-Bash (FASE 4, FR-005/FR-006/FR-011) ----------

# scenario_guidance_block_presente (FR-005)
scenario_guidance_block_presente() {
  _targets=$(_list_orchestrator_targets)
  if [ -z "$_targets" ]; then
    _error "sem_alvos" "nenhum orquestrador encontrado para avaliar"
    return 2
  fi
  _old_ifs="$IFS"
  IFS='
'
  for _t in $_targets; do
    IFS="$_old_ifs"
    _body=$(_guidance_block "$_t")
    if [ -z "$_body" ]; then
      _fail "guidance_block_ausente" "$_t: marcadores MCP-VS-BASH:BEGIN/END ausentes ou corpo vazio"
      return 1
    fi
  done
  IFS="$_old_ifs"
  return 0
}

# scenario_guidance_block_conteudo_minimo (FR-006)
# Grep por trecho-chave estavel de cada um dos 9 itens obrigatorios de
# data-model.md secao "Conteudo minimo obrigatorio do body".
#
# item8 (FASE 7.2.2/dec-089): a mera presenca literal de
# 'elicitation/create' e uma assercao FRACA — casaria tanto o texto ANTIGO
# (proibicao total, item 8 pre-revogacao) quanto uma reescrita futura que
# INVERTESSE a semantica (ex.: "SEMPRE permitido, mesmo sem operador")
# mantendo o mesmo literal. Por isso item8 exige TRES sub-checks
# independentes que juntos amarram os dois recortes de 7.1.1: (8a) o
# literal em si; (8b) o uso permitido condicionado a presenca de operador
# humano ("quando ha operador humano presente"); (8c) o encaminhamento do
# caso sem-operador a FR-010/Deferred ("permanece Deferred"). Prova de que
# 8b/8c realmente detectam inversao de semantica:
# scenario_prova_mutacao_item8_inverte_semantica abaixo.
scenario_guidance_block_conteudo_minimo() {
  _targets=$(_list_orchestrator_targets)
  if [ -z "$_targets" ]; then
    _error "sem_alvos" "nenhum orquestrador encontrado para avaliar"
    return 2
  fi
  _old_ifs="$IFS"
  IFS='
'
  for _t in $_targets; do
    IFS="$_old_ifs"
    _body=$(_guidance_block "$_t")
    if [ -z "$_body" ]; then
      _fail "guidance_block_ausente" "$_t: corpo vazio ao checar conteudo minimo"
      return 1
    fi
    _missing_items=""
    printf '%s\n' "$_body" | grep -qF 'Quando preferir MCP' || _missing_items="$_missing_items item1"
    printf '%s\n' "$_body" | grep -qF 'da PROPRIA execucao' || _missing_items="$_missing_items item2"
    printf '%s\n' "$_body" | grep -qF 'Deteccao de indisponibilidade' || _missing_items="$_missing_items item3"
    printf '%s\n' "$_body" | grep -qF '0 retries' || _missing_items="$_missing_items item4"
    printf '%s\n' "$_body" | grep -qF 'va direto pelo caminho Bash' || _missing_items="$_missing_items item5"
    printf '%s\n' "$_body" | grep -qF 'NUNCA pausa a onda' || _missing_items="$_missing_items item6"
    printf '%s\n' "$_body" | grep -qF 'Mapa operacao MCP' || _missing_items="$_missing_items item7"
    printf '%s\n' "$_body" | grep -qF 'elicitation/create' || _missing_items="$_missing_items item8a"
    printf '%s\n' "$_body" | grep -qF 'quando ha operador humano presente' || _missing_items="$_missing_items item8b"
    printf '%s\n' "$_body" | grep -qF 'permanece Deferred' || _missing_items="$_missing_items item8c"
    printf '%s\n' "$_body" | grep -qF 'Nao-exfiltracao do' || _missing_items="$_missing_items item9"
    if [ -n "$_missing_items" ]; then
      _fail "conteudo_minimo_incompleto" "$_t: itens ausentes =>$_missing_items"
      return 1
    fi
  done
  IFS="$_old_ifs"
  return 0
}

# scenario_guidance_block_regra_nao_exfiltracao (gate owasp-security F1)
scenario_guidance_block_regra_nao_exfiltracao() {
  _targets=$(_list_orchestrator_targets)
  if [ -z "$_targets" ]; then
    _error "sem_alvos" "nenhum orquestrador encontrado para avaliar"
    return 2
  fi
  _old_ifs="$IFS"
  IFS='
'
  for _t in $_targets; do
    IFS="$_old_ifs"
    _body=$(_guidance_block "$_t")
    printf '%s\n' "$_body" | grep -qF 'NUNCA e escrito em artefato, log, mensagem' || {
      _fail "regra_nao_exfiltracao_ausente" "$_t: regra de nao-exfiltracao do session_id ausente ou incompleta"
      return 1
    }
  done
  IFS="$_old_ifs"
  return 0
}

# scenario_guidance_block_paridade (FR-011)
# body dos 2 alvos e byte-identico apos trim de whitespace terminal de
# linha. Falha com diff apontando a linha divergente se nao for.
scenario_guidance_block_paridade() {
  _targets=$(_list_orchestrator_targets)
  _n=$(printf '%s\n' "$_targets" | wc -l | tr -d ' ')
  if [ -z "$_targets" ] || [ "$_n" -lt 2 ]; then
    _error "alvos_insuficientes" "paridade exige >= 2 alvos, encontrados: $_n"
    return 2
  fi
  _first=$(printf '%s\n' "$_targets" | sed -n '1p')
  _second=$(printf '%s\n' "$_targets" | sed -n '2p')
  _body1_file="$TMPDIR_TEST/guidance-body-1.txt"
  _body2_file="$TMPDIR_TEST/guidance-body-2.txt"
  _guidance_block "$_first" | sed -e 's/[[:space:]]*$//' > "$_body1_file"
  _guidance_block "$_second" | sed -e 's/[[:space:]]*$//' > "$_body2_file"
  if ! diff -q "$_body1_file" "$_body2_file" >/dev/null 2>&1; then
    _diff_out=$(diff "$_body1_file" "$_body2_file" 2>&1 | head -20)
    _fail "guidance_block_diverge" "$_first vs $_second divergem: $_diff_out"
    return 1
  fi
  return 0
}

run_all_scenarios "$0"
