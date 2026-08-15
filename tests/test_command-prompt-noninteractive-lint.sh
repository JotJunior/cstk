#!/bin/sh
# test_command-prompt-noninteractive-lint.sh — LINT DE CLASSE sobre os
# commands: todo ponto que pergunta algo ao operador DEVE declarar, no
# mesmo bloco, o que acontece em execucao nao-interativa.
#
# Ref: docs/specs/delivery-tier/quickstart.md Cenario 17
#
# POR QUE UM LINT E NAO MAIS UM ASSERT PONTUAL
# --------------------------------------------
# O spike headless de 2026-08-15 mostrou que `/agente-00c` abortava em
# `Continuar? [s/N]` do warm-up sem criar state-dir algum. Ao corrigir
# APENAS o warm-up, uma varredura revelou que o opt-in de atomic-commit
# tinha o mesmo buraco nos DOIS commands — ele dizia "Qualquer outra
# resposta (inclusive Enter): _atomic=false", frase que pressupoe que
# houve UMA resposta e nada diz sobre a ausencia de operador.
#
# Corrigir instancia a instancia e whack-a-mole: o proximo prompt nasce
# com o mesmo buraco. Este lint falha para QUALQUER prompt novo sem
# clausula, inclusive em commands que ainda nao existem.
#
# Natureza: assert TEXTUAL varrendo plugins/cstk/commands/*.md — nao ha
# script unico sob teste (a "implementacao" e a prosa lida pelo LLM).
# Existence-guarded ao diretorio de commands.
#
# LIMITE HONESTO: isto verifica que a clausula ESTA ESCRITA, nao que o
# agente a OBEDECE. Obediencia so se mede por eval headless — ver
# tests/eval/README.md, que roda fora do gate de release.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

CMD_DIR="$REPO_ROOT/plugins/cstk/commands"

# Marcadores de "pergunta ao operador" usados no corpus.
_PROMPT_RE='\[s/N\]|\[y/N\]|Selecione \['
# Marcadores aceitos como clausula de nao-interatividade.
_CLAUSE_RE='nao-interativ|nao interativ'

# Lista "arquivo:linha:texto" de cada prompt REAL (citacoes excluidas).
# Uma linha cujo primeiro caractere nao-espaco e '>' e blockquote — texto
# explicativo citando um prompt, nao o prompt em si.
_lint_prompts() {
  for _f in "$CMD_DIR"/*.md; do
    [ -f "$_f" ] || continue
    grep -nE "$_PROMPT_RE" "$_f" 2>/dev/null | while IFS=: read -r _ln _rest; do
      case "$(printf '%s' "$_rest" | sed 's/^[[:space:]]*//' | cut -c1)" in
        '>') continue ;;
      esac
      printf '%s:%s:%s\n' "$_f" "$_ln" "$_rest"
    done
  done
}

# Fim do bloco de um prompt = a PRIMEIRA de duas fronteiras: o proximo
# heading (## / ###) ou o proximo prompt. Sem fechar no proximo prompt, a
# janela vaza para o bloco vizinho e um prompt sem clausula passa por
# emprestimo da clausula do vizinho (falso OK observado em
# agente-00c.md:312, que herdava a clausula do roadmap logo abaixo).
_lint_block_end() {
  _bf=$1; _bl=$2
  _btotal=$(wc -l < "$_bf")
  _bh=$(awk -v s="$_bl" 'NR>s && /^#{2,3} /{print NR; exit}' "$_bf")
  [ -n "$_bh" ] || _bh=$_btotal
  # NB: a busca do proximo prompt usa grep, NAO `awk -v re=...`. O awk nao
  # interpreta os escapes do ERE (`\[`) do mesmo jeito que o grep, entao o
  # padrao nunca casava, `_bp` virava o fim do arquivo e a janela vazava
  # para o bloco vizinho — um prompt sem clausula passava "emprestando" a
  # clausula do vizinho. Pego por mutation test, nao por leitura.
  _bp=$(grep -nE "$_PROMPT_RE" "$_bf" | awk -F: -v s="$_bl" '$1>s {print $1; exit}')
  [ -n "$_bp" ] || _bp=$_btotal
  if [ "$_bp" -lt "$_bh" ]; then printf '%s\n' "$_bp"; else printf '%s\n' "$_bh"; fi
}

# ==== O lint encontra prompts (guarda contra regex que para de casar) ====
#
# Sem este cenario, apagar o corpus ou quebrar o _PROMPT_RE faria os
# demais cenarios passarem vacuamente (nada a checar = tudo OK).

scenario_lint_encontra_prompts_no_corpus() {
  [ -d "$CMD_DIR" ] || { _error "diretorio ausente" "$CMD_DIR"; return 2; }
  _n=$(_lint_prompts | wc -l | tr -d ' ')
  [ "$_n" -ge 4 ] || {
    _fail "esperado >=4 prompts reais no corpus de commands" "encontrado $_n"; return 1; }
}

# ==== Todo prompt tem clausula de nao-interatividade no proprio bloco ====

scenario_todo_prompt_declara_comportamento_nao_interativo() {
  mktemp_test || return 2
  _viol=""
  _lint_prompts > "$TMPDIR_TEST/prompts.txt" 2>/dev/null || true
  while IFS=: read -r _f _ln _rest; do
    [ -n "$_f" ] || continue
    _end=$(_lint_block_end "$_f" "$_ln")
    if ! sed -n "${_ln},${_end}p" "$_f" | grep -qiE "$_CLAUSE_RE"; then
      _viol="$_viol
  $(basename "$_f"):$_ln  $(printf '%s' "$_rest" | sed 's/^[[:space:]]*//' | cut -c1-48)"
    fi
  done < "$TMPDIR_TEST/prompts.txt"

  [ -z "$_viol" ] || {
    _fail "prompt(s) ao operador sem clausula de nao-interatividade no bloco" "$_viol
  -> adicione ao bloco o que acontece SEM operador (pular/default), nunca
     deixe a execucao travar aguardando resposta."
    return 1; }
}

# ==== Os dois commands-pai continuam cobertos individualmente ====
#
# Redundante com o cenario acima por desenho: se alguem afrouxar a
# varredura, estes ainda seguram os dois arquivos que ja reproduziram o
# aborto no spike.

scenario_agente_00c_todos_os_prompts_cobertos() {
  _f="$CMD_DIR/agente-00c.md"
  [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }
  mktemp_test || return 2
  grep -nE "$_PROMPT_RE" "$_f" | while IFS=: read -r _ln _rest; do
    case "$(printf '%s' "$_rest" | sed 's/^[[:space:]]*//' | cut -c1)" in '>') continue ;; esac
    _end=$(_lint_block_end "$_f" "$_ln")
    sed -n "${_ln},${_end}p" "$_f" | grep -qiE "$_CLAUSE_RE" || { echo "VIOL:$_ln"; }
  done > "$TMPDIR_TEST/ag.txt"
  [ ! -s "$TMPDIR_TEST/ag.txt" ] || {
    _fail "agente-00c.md tem prompt sem clausula" "$(cat "$TMPDIR_TEST/ag.txt")"; return 1; }
}

scenario_feature_00c_todos_os_prompts_cobertos() {
  _f="$CMD_DIR/feature-00c.md"
  [ -f "$_f" ] || { _error "arquivo ausente" "$_f"; return 2; }
  mktemp_test || return 2
  grep -nE "$_PROMPT_RE" "$_f" | while IFS=: read -r _ln _rest; do
    case "$(printf '%s' "$_rest" | sed 's/^[[:space:]]*//' | cut -c1)" in '>') continue ;; esac
    _end=$(_lint_block_end "$_f" "$_ln")
    sed -n "${_ln},${_end}p" "$_f" | grep -qiE "$_CLAUSE_RE" || { echo "VIOL:$_ln"; }
  done > "$TMPDIR_TEST/ft.txt"
  [ ! -s "$TMPDIR_TEST/ft.txt" ] || {
    _fail "feature-00c.md tem prompt sem clausula" "$(cat "$TMPDIR_TEST/ft.txt")"; return 1; }
}

# ==== O lint detecta de fato uma violacao (auto-teste do detector) ====
#
# Um lint que nunca falha e indistinguivel de um lint quebrado. Este
# cenario injeta um command sintetico COM prompt e SEM clausula e exige
# que a deteccao acuse.

scenario_detector_acusa_prompt_sem_clausula() {
  mktemp_test || return 2
  _fake="$TMPDIR_TEST/fake-command.md"
  cat > "$_fake" <<'FAKE'
## Passo 1

Habilitar o modo turbo? [s/N]

- Respostas afirmativas: liga
- Qualquer outra resposta: desliga

## Passo 2
FAKE
  _ln=$(grep -nE "$_PROMPT_RE" "$_fake" | head -1 | cut -d: -f1)
  [ -n "$_ln" ] || { _fail "detector nao achou o prompt sintetico" "-"; return 1; }
  _end=$(_lint_block_end "$_fake" "$_ln")
  if sed -n "${_ln},${_end}p" "$_fake" | grep -qiE "$_CLAUSE_RE"; then
    _fail "detector deveria acusar ausencia de clausula no command sintetico" "nao acusou"
    return 1
  fi
}

scenario_detector_aceita_prompt_com_clausula() {
  mktemp_test || return 2
  _fake="$TMPDIR_TEST/fake-ok.md"
  cat > "$_fake" <<'FAKE'
## Passo 1

Habilitar o modo turbo? [s/N]

- Respostas afirmativas: liga
- Qualquer outra resposta: desliga
- **Nao-interativo**: desliga sem perguntar, nunca aguarde resposta.

## Passo 2
FAKE
  _ln=$(grep -nE "$_PROMPT_RE" "$_fake" | head -1 | cut -d: -f1)
  _end=$(_lint_block_end "$_fake" "$_ln")
  sed -n "${_ln},${_end}p" "$_fake" | grep -qiE "$_CLAUSE_RE" || {
    _fail "detector deveria aceitar bloco com clausula" "acusou falso positivo"; return 1; }
}

# ==== Citacao (blockquote) nao conta como prompt ====

scenario_citacao_em_blockquote_e_ignorada() {
  mktemp_test || return 2
  _fake="$TMPDIR_TEST/fake-quote.md"
  cat > "$_fake" <<'FAKE'
## Passo 1

> O command antigo parava em `Continuar? [s/N]` e abortava.

## Passo 2
FAKE
  # Reusa o MESMO extrator dos cenarios reais apontando CMD_DIR ao tmpdir —
  # testar o extrator de verdade, nao uma reimplementacao inline (que foi o
  # que quebrou a sintaxe aqui na primeira versao).
  _cmd_dir_bak=$CMD_DIR
  CMD_DIR=$TMPDIR_TEST
  _n=$(_lint_prompts | wc -l | tr -d ' ')
  CMD_DIR=$_cmd_dir_bak
  [ "$_n" = 0 ] || { _fail "blockquote deveria ser ignorado" "contou $_n prompts"; return 1; }
}

run_all_scenarios "$0"
