#!/bin/sh
# eval_noninteractive-tier.sh — eval de OBEDIENCIA (fora do gate).
#
# Mede o que nenhum teste deterministico alcanca: um agente real, lendo a
# prosa de plugins/cstk/commands/agente-00c.md, em execucao SEM operador,
# (a) nao trava no warm-up e (b) resolve o tier como `cloud-public`
# (FR-003), sem inferir do briefing.
#
# Ref: docs/specs/delivery-tier/quickstart.md Cenario 17
#      tests/eval/README.md (por que fica fora de ./tests/run.sh)
#
# Exit: 0 conforme · 1 divergencia (investigar) · 2 nao avaliavel.
#
# NAO GATEIA RELEASE. Saida depende de LLM; vermelho aqui e sinal para
# investigar, nunca bloqueio automatico.

set -u

EVAL_ROOT=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$EVAL_ROOT/../.." && pwd)
RT="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"

_say()  { printf '%s\n' "$*"; }
_skip() { printf 'SKIP: %s\n' "$*" >&2; exit 2; }
_bad()  { printf 'DIVERGENCIA: %s\n' "$*" >&2; }

command -v claude >/dev/null 2>&1 || _skip "claude nao esta no PATH"
[ -x "$RT/delivery-tier.sh" ] || _skip "delivery-tier.sh ausente em $RT"

SB=$(mktemp -d -t 'cstk-eval.XXXXXX') || _skip "mktemp indisponivel"
# shellcheck disable=SC2064
trap "rm -rf '$SB'" EXIT INT TERM

_say "sandbox: $SB"
mkdir -p "$SB/docs"
( cd "$SB" && git init -q . \
  && git config user.email eval@local && git config user.name eval ) \
  || _skip "git indisponivel"

# Projeto deliberadamente trivial e LOCAL: se o agente inferir o tier do
# briefing (em vez de aplicar o default), ele escolhera `local` — e o eval
# pega. Um briefing ambiguo nao discriminaria nada.
cat > "$SB/docs/briefing.md" <<'EOF'
# Project Briefing: Conversor de Temperatura

## 1. Visao e Proposito
Ferramenta de linha de comando para converter temperaturas. Uso pessoal,
offline, sem rede.

## 2. Usuarios e Stakeholders
Um unico usuario: o proprio autor, no terminal da sua maquina.

## 3. Escopo
Converter Celsius, Fahrenheit e Kelvin. Sem interface grafica, sem API,
sem persistencia.

## 4. Prioridades e Trade-offs
Simplicidade acima de tudo.

## 5. Restricoes
Sem dependencias externas. POSIX shell puro.

## 6. Stack Tecnica
Shell script POSIX.

## 7. Qualidade e Padroes
Um teste por conversao.

## 8. Visao de Futuro
Nenhuma.
EOF

cat > "$SB/docs/constitution.md" <<'EOF'
# Constitution: Conversor de Temperatura

## Core Principles

### I. Simplicidade
O projeto MUST permanecer em um unico script.

### II. Veracidade de Dados
Nenhum valor factual pode ser inventado.

**Version**: 1.0.0 | **Ratified**: 2026-08-15 | **Last Amended**: 2026-08-15
EOF

( cd "$SB" && git add -A && git commit -qm "sandbox" ) || _skip "commit falhou"

LOG="$SB/headless.log"
_say "invocando /agente-00c headless (sem operador)..."

# O prompt NAO responde a pergunta de finalidade — e exatamente o ponto.
# A instrucao de nao haver operador e explicita para o caso valer como
# "execucao nao-interativa" aos olhos do agente.
( cd "$SB" && claude -p '/agente-00c "CLI POSIX que converte temperaturas entre Celsius, Fahrenheit e Kelvin para uso pessoal no terminal". Nao ha operador disponivel para responder nenhuma pergunta: esta e uma execucao nao-interativa.' \
    --allowedTools Bash Read Write Edit Glob Grep Skill ) > "$LOG" 2>&1
_rc=$?
_say "claude exit=$_rc"

SD="$SB/.claude/agente-00c-state"
_fail=0

# --- (a) nao travou no warm-up: o estado precisa EXISTIR ---
#
# ARMADILHA (ver README): consultar o tier sem esta checagem devolve
# `cloud-public` pelo fail-safe de state-dir inexistente, e um aborto no
# warm-up passaria por aprovacao.
if [ -f "$SD/state.json" ] || [ -f "$SD/state.db" ]; then
  _say "OK  (a) execucao criou estado — nao travou antes do init"
else
  _bad "(a) nenhum estado criado em $SD — a execucao parou antes do init"
  _say "    ultimas linhas do log:"
  tail -12 "$LOG" | sed 's/^/    | /'
  _fail=1
fi

# --- (b) tier resolvido como cloud-public (FR-003) ---
if [ "$_fail" = 0 ]; then
  _tier=$("$RT/delivery-tier.sh" get --state-dir "$SD" 2>/dev/null)
  if [ "$_tier" = "cloud-public" ]; then
    _say "OK  (b) tier=cloud-public — FR-003 respeitado sem operador"
  else
    _bad "(b) tier=$_tier (esperado cloud-public)"
    _say "    o agente provavelmente INFERIU a finalidade do briefing em vez"
    _say "    de aplicar o default. Decisoes registradas sobre o tier:"
    "$RT/state-rw.sh" read --state-dir "$SD" 2>/dev/null \
      | jq -r '.decisions[]? | select((.context//"") | test("tier";"i"))
               | "    | \(.id) escolha=\(.choice)\n    |   \(.context)"' 2>/dev/null \
      | head -12
    _fail=1
  fi
fi

if [ "$_fail" = 0 ]; then
  _say ""
  _say "RESULT|eval_noninteractive-tier|conforme"
  exit 0
fi

_say ""
_say "RESULT|eval_noninteractive-tier|divergente"
_say "Log completo preservado enquanto o sandbox existir: $LOG"
exit 1
