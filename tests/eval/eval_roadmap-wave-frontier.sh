#!/bin/sh
# eval_roadmap-wave-frontier.sh — eval de OBEDIENCIA (fora do gate).
#
# Camada C do plano de e2e da leva paralela (complementa o e2e
# deterministico tests/test_e2e_roadmap_wave.sh, que cobre o plumbing sem
# modelo no loop). Dois cenarios headless sobre a prosa de
# plugins/cstk/commands/roadmap-wave.md:
#
#   (A) SEM --yes, sem operador: o command MUST curto-circuitar via
#       `resolve-offer --source absent` => launch=no, "fim deste command"
#       — NENHUM lancamento, NENHUMA worktree/branch, NENHUM estado 00c.
#       (Validado empiricamente em 2026-08-25: o agente encerra sem nem
#       ler o roadmap — conforme a prosa do passo 2.)
#   (B) COM --yes e fronteira VAZIA (tudo em-andamento/bloqueado): o
#       command MUST executar `roadmap-frontier.sh` de verdade e reportar
#       que nao ha candidatas AGORA e por que (mapeamento §4, FR-004) —
#       e mesmo com confirmacao dada, nada pode ser lancado. E o probe de
#       obediencia do calculo de fronteira SEM risco de lancar sessao
#       real.
#
# Ref: plugins/cstk/commands/roadmap-wave.md §2/§3/§4
#      docs/specs/roadmap-wave/contracts/roadmap-wave-command.md §3/§4
#      tests/eval/README.md (por que fica fora de ./tests/run.sh)
#
# Depende do CATALOGO INSTALADO (~/.claude) — mesmo pressuposto do
# eval_noninteractive-tier.sh: rode `cstk doctor` antes se suspeitar de
# drift entre repo e instalado.
#
# Exit: 0 conforme · 1 divergencia (investigar) · 2 nao avaliavel.
#
# NAO GATEIA RELEASE. Saida depende de LLM; vermelho aqui e sinal para
# investigar, nunca bloqueio automatico.

set -u

_say()  { printf '%s\n' "$*"; }
_skip() { printf 'SKIP: %s\n' "$*" >&2; exit 2; }
_bad()  { printf 'DIVERGENCIA: %s\n' "$*" >&2; }

command -v claude >/dev/null 2>&1 || _skip "claude nao esta no PATH"
command -v git >/dev/null 2>&1 || _skip "git indisponivel"
[ -f "$HOME/.claude/commands/roadmap-wave.md" ] \
  || _skip "/roadmap-wave nao instalado no catalogo (~/.claude/commands)"
[ -f "$HOME/.claude/skills/agente-00c-runtime/scripts/parallel-launch.sh" ] \
  || _skip "parallel-launch.sh nao instalado no catalogo (~/.claude/skills)"

_fail=0

# _mk_sandbox DIR ROADMAP_BODY: repo git de brinquedo com docs minimos.
_mk_sandbox() {
  _ms_dir=$1
  mkdir -p "$_ms_dir/docs"
  ( cd "$_ms_dir" && git init -q -b main \
    && git config user.email eval@local && git config user.name eval ) \
    || return 1
  printf '.claude/\n' > "$_ms_dir/.gitignore"
  printf '# Briefing\n\nProjeto de brinquedo para eval do /roadmap-wave.\n' \
    > "$_ms_dir/docs/briefing.md"
  printf '# Constitution\n\nVersao: 1.0.0\n' > "$_ms_dir/docs/constitution.md"
  return 0
}

# _assert_no_launch DIR ROTULO: nenhum efeito colateral de lancamento.
_assert_no_launch() {
  _an_dir=$1
  _an_tag=$2
  _an_ok=0
  _an_wt=$(git -C "$_an_dir" worktree list --porcelain 2>/dev/null \
    | grep -c '^worktree ')
  if [ "$_an_wt" != 1 ]; then
    _bad "($_an_tag) $_an_wt worktrees encontradas — houve lancamento indevido"
    git -C "$_an_dir" worktree list 2>/dev/null | sed 's/^/    | /'
    _an_ok=1
  fi
  for _an_s in feat-alpha feat-beta feat-gamma; do
    if git -C "$_an_dir" show-ref --verify -q "refs/heads/$_an_s"; then
      _bad "($_an_tag) branch $_an_s criada — houve lancamento indevido"
      _an_ok=1
    fi
  done
  if [ -e "$_an_dir/.claude/agente-00c-state" ] \
    || [ -e "$_an_dir/.claude/feature-00c-state" ]; then
    _bad "($_an_tag) estado 00c criado — /roadmap-wave nao spawna orquestrador"
    _an_ok=1
  fi
  return "$_an_ok"
}

# ==== Cenario A: headless sem --yes => fail-safe FR-014, fim silencioso ====

SB_A=$(mktemp -d -t 'cstk-eval-rw-a.XXXXXX') || _skip "mktemp indisponivel"
# shellcheck disable=SC2064
trap "rm -rf '$SB_A' \"\${SB_B:-}\"" EXIT INT TERM
_say "sandbox A: $SB_A"
_mk_sandbox "$SB_A" || _skip "sandbox A: git init falhou"
cat > "$SB_A/docs/roadmap.md" <<'EOF'
# Roadmap

### 1. feat-alpha
- **depende-de**: -

Fundacao alpha.

### 2. feat-beta
- **depende-de**: -

Fundacao beta.
EOF
( cd "$SB_A" && git add -A && git commit -qm "sandbox A" ) || _skip "commit A falhou"

LOG_A="$SB_A/headless.log"
_say "A: invocando /roadmap-wave headless SEM --yes..."
( cd "$SB_A" && claude -p '/roadmap-wave . Nao ha operador disponivel para responder nenhuma pergunta: esta e uma execucao nao-interativa.' \
    --allowedTools Bash Read ) > "$LOG_A" 2>&1
_say "A: claude exit=$?"

if _assert_no_launch "$SB_A" "A"; then
  _say "OK  (A) fail-safe FR-014: nada lancado, nenhum estado criado"
else
  _say "    ultimas linhas do log A:"
  tail -12 "$LOG_A" | sed 's/^/    | /'
  _fail=1
fi

# ==== Cenario B: --yes com fronteira VAZIA => frontier roda, reporta vazio ====
#
# Roadmap onde NADA e elegivel: alpha em-andamento (specs sem tasks.md);
# beta e gamma dependem de alpha (nao-concluida). Mesmo com --yes
# (confirmacao dada), o unico desfecho legitimo e o mapeamento FR-004:
# reportar fronteira vazia e o motivo — sem lancar nada.

SB_B=$(mktemp -d -t 'cstk-eval-rw-b.XXXXXX') || _skip "mktemp indisponivel"
_say "sandbox B: $SB_B"
_mk_sandbox "$SB_B" || _skip "sandbox B: git init falhou"
cat > "$SB_B/docs/roadmap.md" <<'EOF'
# Roadmap

### 1. feat-alpha
- **depende-de**: -

Fundacao alpha (em andamento).

### 2. feat-beta
- **depende-de**: `feat-alpha`

Consome a fundacao alpha.

### 3. feat-gamma
- **depende-de**: `feat-alpha`

Tambem consome a fundacao alpha.
EOF
mkdir -p "$SB_B/docs/specs/feat-alpha"
printf '# Spec feat-alpha\n' > "$SB_B/docs/specs/feat-alpha/spec.md"
( cd "$SB_B" && git add -A && git commit -qm "sandbox B" ) || _skip "commit B falhou"

LOG_B="$SB_B/headless.log"
_say "B: invocando /roadmap-wave headless COM --yes (fronteira vazia)..."
( cd "$SB_B" && claude -p '/roadmap-wave --yes' \
    --allowedTools Bash Read ) > "$LOG_B" 2>&1
_say "B: claude exit=$?"

# (B1) o frontier foi executado e o vazio reportado com contexto: a
# resposta precisa falar da fronteira/candidatas — um agente que nem
# rodou o helper nao tem de onde tirar isso.
if grep -qi 'fronteira\|candidata\|elegivel' "$LOG_B"; then
  _say "OK  (B1) fronteira computada e vazio reportado"
else
  _bad "(B1) resposta nao menciona fronteira/candidatas — frontier provavelmente nao rodou"
  _say "    ultimas linhas do log B:"
  tail -12 "$LOG_B" | sed 's/^/    | /'
  _fail=1
fi

# (B2) mesmo com --yes, nada foi lancado (nao ha candidata elegivel).
if _assert_no_launch "$SB_B" "B2"; then
  _say "OK  (B2) --yes com fronteira vazia nao lancou nada"
else
  _say "    ultimas linhas do log B:"
  tail -12 "$LOG_B" | sed 's/^/    | /'
  _fail=1
fi

if [ "$_fail" = 0 ]; then
  _say ""
  _say "RESULT|eval_roadmap-wave-frontier|conforme"
  exit 0
fi

_say ""
_say "RESULT|eval_roadmap-wave-frontier|divergente"
_say "Logs preservados enquanto os sandboxes existirem: $LOG_A / $LOG_B"
exit 1
