#!/bin/sh
# test_model_selector_gotchas.sh
#
# Cobre subtarefa 5.4.3 da feature `model-selector` (FR-013 a-e,
# CHK032, CHK033, CHK035, CHK045). Garante que `SKILL.md` contem
# EXATAMENTE 5 (ou mais) sub-headings sob a secao `## Gotchas`, e que
# o Gotcha (d) cita explicitamente o teto pratico de score 2 na
# auto-invocacao (resolve CHK045).
#
# Por que isso e invariante (FR-013, CHK033, CHK035):
#   A secao Gotchas existe para economizar uma onda de fix-reveal-fix
#   em outras skills que importarem padroes. Se o numero de gotchas
#   regride para <5 (ex: alguem deletar um por engano), um dos 5
#   pilares de uso seguro (sugestao=nao=troca, sinais=conservador,
#   ambiguo=manter-atual, score3=evidencia, sem-spawn) sai de
#   conformidade.
#
# Mecanismo (CHK033):
#   awk extrai bloco entre `## Gotchas` (inclusive) e o proximo `## `
#   (exclusive). Em seguida `grep -c '^### '` conta sub-headings.
#   Resultado esperado: >= 5 (5 e o numero exato hoje; >=5 permite
#   expansao futura sem quebrar o teste).
#
# Cobertura CHK045 (teto 2 na auto-invocacao no Gotcha (d)):
#   Procura literal `teto pratico de score 2` (ou equivalente proximo)
#   na secao Gotchas. Justifica-se porque score 3 e reservado para
#   evolucao futura (dec-006) e o orquestrador precisa saber que match
#   de verbo NUNCA satisfaz FR-EVI-001.
#
# Limitacoes:
#   - NAO valida o CONTEUDO de cada sub-heading — so a presenca dos 5
#     headers. O conteudo e validado por revisao manual + outros
#     testes (ex: `test_model_selector_no_spawn.sh` valida Gotcha (e)).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_MD="$REPO_ROOT/plugins/cstk/skills/model-selector/SKILL.md"
export SKILL_MD

scenario_5_4_3_gotchas_tem_pelo_menos_5_subheadings() {
  if [ ! -f "$SKILL_MD" ]; then
    _error "skill_md_ausente" "esperado $SKILL_MD"
    return 2
  fi
  # awk extrai do `## Gotchas` ate o proximo `## ` (heading H2 nao-Gotchas).
  # O range `/A/,/B/` em awk e inclusivo nos extremos; descartamos o
  # ultimo registro via condicional para nao incluir um H2 estranho.
  _count=$(awk '
    /^## Gotchas[[:space:]]*$/ { in_g=1; next }
    in_g && /^## / { in_g=0 }
    in_g { print }
  ' "$SKILL_MD" | grep -c '^### ' || true)

  # `grep -c` retorna a contagem como inteiro decimal. Comparacao
  # POSIX via -lt.
  if [ "${_count:-0}" -lt 5 ]; then
    _fail "gotchas_subheadings_insuficientes" \
      "esperado >=5; obtido=$_count"
    return 1
  fi
}

scenario_5_4_3_gotcha_d_cita_teto_2_na_auto_invocacao() {
  if [ ! -f "$SKILL_MD" ]; then
    _error "skill_md_ausente" "esperado $SKILL_MD"
    return 2
  fi
  # Procura literal de "teto pratico de score 2" dentro do bloco
  # Gotchas. A frase exata e canonica (CHK045) — se alguem reescrever
  # o gotcha sem citar o teto, o teste reprova.
  _bloco=$(awk '
    /^## Gotchas[[:space:]]*$/ { in_g=1; next }
    in_g && /^## / { in_g=0 }
    in_g { print }
  ' "$SKILL_MD")
  if ! printf '%s' "$_bloco" | grep -F 'teto pratico de score 2' >/dev/null 2>&1; then
    _fail "gotcha_d_sem_teto_2" \
      "secao Gotchas deve citar literalmente 'teto pratico de score 2' (CHK045)"
    return 1
  fi
}

run_all_scenarios
