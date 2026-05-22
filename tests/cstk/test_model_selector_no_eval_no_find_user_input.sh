#!/bin/sh
# test_model_selector_no_eval_no_find_user_input.sh
#
# Cobre subtarefas 5.5.1 e 5.5.2 da feature `model-selector` (CHK022,
# CHK060; resolvidos via onda-006 /analyze dec-029). Garante que
# nenhum script em `global/skills/model-selector/scripts/` usa:
#
#   (1) `eval` em QUALQUER caminho de execucao — sem excecao. `eval`
#       expande argumentos como comandos shell, e o input da skill
#       (`$1`, descricao da tarefa) e textual nao-confiavel; expor
#       `eval` ao input do operador permitiria injecao de comando.
#       (CHK022)
#
#   (2) `find <expressao-derivada-de-$1>` — find com root path ou
#       criterio derivado direta ou indiretamente do input do usuario.
#       Find sobre input arbitrario expoe: traversal fora do projeto
#       (-path /etc, /home/outro_usuario), execucao via `-exec` ou
#       `-delete`, e cycling via symlink. (CHK060)
#
# Por que isso e invariante (CHK022 + CHK060):
#   A skill carrega o input textual do usuario em `$1`. POSIX shell
#   nao expande automaticamente metacaracteres em parametros entre
#   aspas — entao "$1" como argumento de comando deterministico (`grep`,
#   `tr`, `awk`) e seguro por construcao. PERDE seguranca apenas se
#   houver `eval` (que faz expansao adicional) ou `find` ousando
#   navegar/executar com base em valor derivado do input.
#
# Mecanismo (CHK022, CHK060):
#   `grep -nE '\beval\b|\bfind\b' scripts/`
#   filtrando comentarios shell (linhas que iniciam com `#` apos
#   whitespace). Esperado: ZERO hits em codigo executavel.
#
# Regra de cobertura (subtarefa 5.5.2 — concatenacao indireta):
#   O teste cobre tambem o caso de variavel intermediaria que carrega
#   `$1`. Exemplo proibido:
#     VAR="$1"; find "$VAR" -name "*.txt"
#   Esse padrao aparece no grep como `\bfind\b` em codigo executavel
#   — e reprovado independente de onde a variavel veio. A regra dura
#   e: "nenhum `find` em scripts/ da skill, ponto final". Se a skill
#   precisar listar arquivos no futuro, usar `ls` ou expansao de glob
#   com bounded scope.
#
# Limitacoes (intencional):
#   - `find` em comentarios shell e permitido (uso explicativo).
#   - O teste nao distingue "find sobre input do usuario" de "find
#     sobre path fixo `references/`" — adotamos a regra mais rigorosa:
#     nenhum find. Se um caso legitimo surgir, sera necessario aprovar
#     via whitelist explicita aqui.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPTS_DIR="$REPO_ROOT/global/skills/model-selector/scripts"
export SCRIPTS_DIR

# Regex ERE (-E): `\b` e word boundary do GNU grep; em BSD/macOS,
# `\b` tambem funciona no modo -E. Fallback POSIX seguro seria
# `(^|[^A-Za-z])eval([^A-Za-z]|$)`, mas o ambiente de teste do
# repo ja roda GNU grep e BSD grep com -E sem regressao.
UNSAFE_REGEX='\beval\b|\bfind\b'

scenario_5_5_1_scripts_sem_eval_nem_find() {
  if [ ! -d "$SCRIPTS_DIR" ]; then
    _error "scripts_ausentes" "esperado $SCRIPTS_DIR"
    return 2
  fi
  _hits=$(grep -rnE "$UNSAFE_REGEX" "$SCRIPTS_DIR" 2>/dev/null \
            | grep -v '^[^:]*:[[:space:]]*[0-9][0-9]*:[[:space:]]*#' \
            || true)
  if [ -n "$_hits" ]; then
    _fail "eval_ou_find_em_scripts" \
      "padrao=$UNSAFE_REGEX; matches=$_hits"
    return 1
  fi
}

run_all_scenarios
