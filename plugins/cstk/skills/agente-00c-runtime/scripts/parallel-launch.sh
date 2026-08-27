#!/bin/sh
# parallel-launch.sh — compoe (nunca executa) os comandos de lancamento de
# uma leva paralela de sessoes-filha em worktrees dedicadas (FR-005, FR-006).
#
# Feature: roadmap-parallel-launch (emit, check-tmux) + roadmap-wave
# (resolve-offer)
# Ref: docs/specs/roadmap-parallel-launch/contracts/parallel-launch.md §4
#      docs/specs/roadmap-parallel-launch/spec.md FR-005, FR-006, FR-007,
#      FR-011, FR-017, FR-018
#      docs/specs/roadmap-wave/contracts/roadmap-wave-command.md §3
#
# Uso:
#   parallel-launch.sh emit --repo PATH --feature SHORT [--description TEXT]
#                            [--feature SHORT [--description TEXT] ...]
#                            [--roadmap PATH] [--coordinator-name NAME]
#   parallel-launch.sh check-tmux
#   parallel-launch.sh resolve-offer --source <operator|absent>
#                                    [--confirm RAW] [--max RAW]
#   parallel-launch.sh -h | --help
#
# `resolve-offer` (feature roadmap-wave, contract roadmap-wave-command.md
# §3): espelha em codigo testavel a decisao hoje descrita so em prosa nos
# passos 4-5 de agente-00c.md §6.ter — se a leva paralela deve ser lancada
# e com qual teto. Precedente real: `delivery-tier.sh resolve-initial
# --source <operator|absent> [--answer RAW]`. So compoe/decide, nunca
# executa nem lanca nada.
#
# Decisao de desenho (contract §4): `emit` SOMENTE compoe e imprime os
# comandos — NUNCA executa. Quem executa e o command pai (/agente-00c,
# /agente-00c-resume), que ja tem Bash e ja e o dono da interacao com o
# operador. Isso torna o caminho automatico (com tmux) e o degradado (sem
# tmux) comparaveis byte a byte na parte `claude --name ... "..."` — mesma
# composicao, so envolvida de forma diferente (§4, decisao de desenho).
#
# Telemetria (issue #168): a composicao `claude ...` e prefixada por
# `env CLAUDE_CODE_ENABLE_TELEMETRY=1 ... CSTK_OTEL_ENDPOINT=...` com UMA
# porta sorteada POR FILHA — sem isso a filha sobe sem telemetria (o wrapper
# do rc e funcao de shell e nao alcanca `sh -c` nao-interativo do tmux).
# Kill switch: CSTK_TELEMETRY_AUTO=0. Detalhe em _pl_otel_prefix.
#
# Wrapper tmux: SEMPRE `split-window` (pane irmao no window da
# coordenadora), nunca `new-window`. O prompt da filha e sempre
# `/feature-00c "<DESCRICAO>" <SHORT>` — formato REAL do command
# (feature-00c.md:113-115), com o short-name POSICIONAL pinando a feature.
# INALTERADO por este script: cli/lib/session.sh.
#
# --coordinator-name NAME: aceito e validado por allowlist
# (^cstk-coord/[A-Za-z0-9._-]{1,64}$, <=64 chars) como defesa em
# profundidade (contract §4.1), mas NAO e injetado na composicao emitida —
# a composicao literal do contrato §4.1 nao referencia a coordenadora; o
# encaminhamento do nome da coordenadora ate a sessao-filha para fins de
# notificacao (contract §6) e escopo da prosa de /feature-00c (fase
# posterior desta feature), nao deste helper.
#
# Guarda anti-duplicidade (FR-011): NAO vive aqui — `roadmap-frontier.sh
# --exclude-active-from-repo PATH` (contract roadmap-frontier.md §5) e a
# fonte da guarda, executada ANTES da oferta ao operador. Este script so
# revalida cada --feature (defesa em profundidade, contract §4.2) no
# momento do emit — camada independente da fronteira, custo zero.
#
# POSIX sh puro, sem `jq` (Principio II).
#
# Exit codes:
#   0  sucesso (resolve-offer: inclusive launch=no — recusar nao e erro)
#   2  uso incorreto (subcomando desconhecido, flag sem valor, --repo
#      ausente, nenhum --feature, --feature ou --coordinator-name
#      mal-formado; resolve-offer: --source ausente ou fora do enum)
#   3  check-tmux: tmux ausente

set -eu

_PL_NAME="parallel-launch"
_PL_DIR=$(cd "$(dirname "$0")" && pwd)

_PL_TAB=$(printf '\t')

_PL_SHORT_RE='^[a-z][a-z0-9-]*$'
_PL_CHILD_RE='^cstk-feature/[a-z][a-z0-9-]*$'
_PL_COORD_RE='^cstk-coord/[A-Za-z0-9._-]{1,64}$'

print_usage() {
  cat <<'EOF'
Uso: parallel-launch.sh emit --repo PATH --feature SHORT [--description TEXT]
                              [--feature SHORT [--description TEXT] ...]
                              [--roadmap PATH] [--coordinator-name NAME]
     parallel-launch.sh check-tmux
     parallel-launch.sh resolve-offer --source <operator|absent>
                                      [--confirm RAW] [--max RAW]
     parallel-launch.sh -h | --help

`emit` compoe e IMPRIME (nunca executa) o par de comandos de lancamento de
cada --feature: `cstk session start <SHORT>` + `tmux split-window ...` (ou a
forma degradada `cd ... && env ... claude ...` quando tmux esta ausente). A
composicao `claude ...` vem prefixada por `env` com as variaveis de
telemetria local (porta por filha; desative com CSTK_TELEMETRY_AUTO=0). Quem
executa e o chamador (command pai) — este script nunca invoca cli/lib/
session.sh nem qualquer outro comando de efeito colateral.

Opcoes de `emit`:
  --repo PATH             Repositorio coordenador (obrigatorio; deriva
                           <WORKTREE> = <pai-do-repo>/<nome-do-repo>-<SHORT>,
                           mesma derivacao de cli/lib/session.sh:243)
  --feature SHORT         Short-name a lancar (repetivel; >=1 obrigatorio).
                           Revalidado contra ^[a-z][a-z0-9-]*$ (<=64 chars)
                           no momento do emit — defesa em profundidade
                           (exit 2 se nao casar).
  --description TEXT      Descricao da feature imediatamente anterior
                           (opcional). Vence o roadmap. Sanitizada
                           (sem aspas nem metacaractere de shell) e
                           truncada a 300 chars. Exit 2 se vier sem um
                           --feature antes.
  --roadmap PATH          Roadmap de onde extrair `**Descricao**:` quando
                           --description nao foi informado. Default:
                           <PATH-do---repo>/docs/roadmap.md. Ausente ou
                           sem a entrada => fallback para o proprio
                           short-name (aviso em stderr), NUNCA erro.
  --coordinator-name NAME Nome da sessao coordenadora (opcional), validado
                           contra ^cstk-coord/[A-Za-z0-9._-]{1,64}$ se
                           informado (exit 2 se mal-formado). Nao altera a
                           composicao emitida (ver cabecalho do script).

Guarda anti-duplicidade (FR-011): `emit` recomputa `git -C PATH worktree
list --porcelain` sobre --repo IMEDIATAMENTE antes de compor (janela
TOCTOU, contract §4.2) e PULA (nao compoe, nao imprime) qualquer --feature
que ja tenha worktree ativa, registrando outcome=blocked-duplicate. Isso e
a SEGUNDA camada — a primeira e `roadmap-frontier.sh --exclude-active-from-repo`
(contract roadmap-frontier.md §5), que filtra ANTES da interacao com o
operador. Ausencia de git ou repo sem worktrees => nenhuma exclusao.

`check-tmux`: exit 0 se `tmux` esta disponivel no PATH; exit 3 se ausente.
Nunca aguarda, nunca falha em silencio.

Cada lancamento (ou recusa por --feature invalido) e registrado em
<PATH>/.claude/enforcement-log.jsonl (source: "parallel-launch"), com o
campo `command` filtrado por secrets-filter.sh scrub — best-effort, falha
de log NUNCA aborta o emit.

`resolve-offer` (feature roadmap-wave, contract roadmap-wave-command.md
§3): decide se a leva paralela deve ser lancada (`launch=yes|no`) e com
qual teto (`max=<inteiro>`), sem executar nada.

  --source <operator|absent>  OBRIGATORIO, sem default. Quem chama
                               DECLARA se houve operador — nao ha
                               deteccao automatica de interatividade
                               (`[ -t 0 ]` e falso mesmo em sessao
                               interativa do harness).
  --confirm RAW                Resposta do operador (opcional). Valida
                                contra o enum `s|S|y|Y|sim|yes`; qualquer
                                outra coisa (inclusive vazio/Enter)
                                ⇒ launch=no.
  --max RAW                    Teto desejado (opcional). Inteiro em
                                1..8 ⇒ usado tal-e-qual; ausente/vazio
                                com --confirm valido ⇒ default 2;
                                mal-formado/0/negativo/>8 ⇒ launch=no
                                (fail-closed).

`--source absent` ignora --confirm/--max por completo (nem le) e sempre
resolve `launch=no`/`max=2` (FR-014) — fail-safe: sem operador, sem
lancamento algum.

`--confirm`/`--max` tem `\r`/`\n` removidos ANTES de comparar (mesma
classe de bug corrigida em delivery-tier.sh:306-307 — `$()` NAO remove
`\r`).

Saida (stdout, chave=valor, sem jq):
  launch=<yes|no>
  max=<inteiro>
Diagnosticos em stderr.

Exit codes: 0 sucesso; 2 uso incorreto; 3 (check-tmux) tmux ausente.
EOF
}

[ $# -ge 1 ] || { print_usage >&2; exit 2; }

_PL_SUBCOMMAND=$1
shift

# ==== check-tmux ====

_pl_cmd_check_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    exit 0
  fi
  exit 3
}

# ==== helpers de validacao (defesa em profundidade, contract §4.1/§4.2) ====

# _pl_len STRING -> comprimento em chars (via wc -c, normalizado para o \n
# do printf) — mesma tecnica ja usada por roadmap-status.sh.
_pl_len() {
  _pl_l=$(printf '%s' "$1" | wc -c | tr -d ' ')
  printf '%s' "$_pl_l"
}

# _pl_valid_short SHORT -> exit 0 se casa ^[a-z][a-z0-9-]*$ e <=64 chars.
_pl_valid_short() {
  [ "$(_pl_len "$1")" -le 64 ] || return 1
  printf '%s' "$1" | grep -Eq "$_PL_SHORT_RE"
}

# _pl_valid_coordinator NAME -> exit 0 se casa ^cstk-coord/[A-Za-z0-9._-]{1,64}$.
_pl_valid_coordinator() {
  printf '%s' "$1" | grep -Eq "$_PL_COORD_RE"
}

# _pl_valid_child NAME -> exit 0 se casa ^cstk-feature/[a-z][a-z0-9-]*$.
_pl_valid_child() {
  printf '%s' "$1" | grep -Eq "$_PL_CHILD_RE"
}

# ==== TOCTOU-recompute da guarda anti-duplicidade (contract §4.2/2.6.4) ====
#
# `roadmap-frontier.sh --exclude-active-from-repo` ja filtra a oferta ANTES
# da interacao com o operador (contract roadmap-frontier.md §5) — mas essa
# interacao tem duracao ilimitada. `emit` roda imediatamente antes da
# execucao de fato, entao recomputa a MESMA checagem aqui como segunda
# camada (backstop final continua sendo o exit 6 de `cstk session start`,
# cli/lib/session.sh). Mesmo parsing de `git worktree list --porcelain`
# (linha `branch refs/heads/<name>`), independente do de roadmap-frontier.sh
# (scripts distintos, sem dependencia cruzada).
_PL_ACTIVE_BRANCHES=""
_pl_load_active_branches() {
  _pl_lab_repo=$1
  command -v git >/dev/null 2>&1 || return 0
  _pl_lab_out=$(git -C "$_pl_lab_repo" worktree list --porcelain 2>/dev/null) || return 0
  [ -n "$_pl_lab_out" ] || return 0
  _PL_ACTIVE_BRANCHES=$(printf '%s\n' "$_pl_lab_out" | sed -n 's/^branch refs\/heads\///p')
}

# _pl_is_duplicate SHORT -> exit 0 se SHORT ja tem worktree ativa.
# Sentinela nao-newline (".") apos a ultima newline: `$(...)` sempre remove
# newlines finais, o que quebraria o match do ultimo item sem o sentinela
# (mesmo achado documentado em roadmap-frontier.sh).
_pl_is_duplicate() {
  [ -n "$_PL_ACTIVE_BRANCHES" ] || return 1
  _pl_id_target=$1
  case "$(printf '\n%s\n.' "$_PL_ACTIVE_BRANCHES")" in
    *"
$_pl_id_target
"*) return 0 ;;
  esac
  return 1
}

# ==== JSON escaping (paridade com json_escape de roadmap-status.sh, mais
# newline: o campo `command` do enforcement-log e multi-linha) ====
#
# awk (nao sed `:a;N;$!ba`) deliberadamente: o idiolma sed de juntar linhas
# via `N` FALHA silenciosamente (sem imprimir nada) em input de UMA linha
# so no BSD/macOS sed — `N` sem proxima linha disponivel aborta o ciclo sem
# auto-print (comportamento POSIX-estrito, diferente do GNU sed). Achado
# empirico ao testar `--feature` de token unico (sem newline embutido).
# awk processa por registro (linha) sem essa armadilha, em qualquer awk.
_pl_json_escape() {
  printf '%s' "$1" | awk '
    {
      gsub(/\\/, "\\\\");
      gsub(/"/, "\\\"");
      out = out (NR > 1 ? "\\n" : "") $0
    }
    END { printf "%s", out }
  '
}

# ==== enforcement-log.jsonl (contract §4.2, schema CHK125) ====
#
# Best-effort: falha de resolucao de secrets-filter.sh, falha de escrita,
# ou --repo invalido NUNCA abortam o emit (efeito colateral de auditoria,
# nao gate — mesma politica do hook pretooluse-bash-guard.sh).
_pl_write_log() {
  _pl_repo_path=$1
  _pl_wl_short=$2
  _pl_wl_repo_name=$3
  _pl_wl_worktree=$4
  _pl_wl_outcome=$5
  _pl_wl_command=$6

  _pl_sf="$_PL_DIR/secrets-filter.sh"
  if [ -x "$_pl_sf" ]; then
    _pl_wl_cmd_safe=$(printf '%s' "$_pl_wl_command" | "$_pl_sf" scrub 2>/dev/null | cut -c1-2000) \
      || _pl_wl_cmd_safe="[secrets-filter-falhou]"
  else
    _pl_wl_cmd_safe="[secrets-filter indisponivel - comando omitido por seguranca]"
  fi

  _pl_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _pl_ts=""

  _pl_line=$(printf '{"source":"parallel-launch","timestamp":"%s","short_name":"%s","repo":"%s","worktree_path":"%s","outcome":"%s","command":"%s"}' \
    "$(_pl_json_escape "$_pl_ts")" \
    "$(_pl_json_escape "$_pl_wl_short")" \
    "$(_pl_json_escape "$_pl_wl_repo_name")" \
    "$(_pl_json_escape "$_pl_wl_worktree")" \
    "$(_pl_json_escape "$_pl_wl_outcome")" \
    "$(_pl_json_escape "$_pl_wl_cmd_safe")")

  mkdir -p "$_pl_repo_path/.claude" 2>/dev/null || return 0
  printf '%s\n' "$_pl_line" >>"$_pl_repo_path/.claude/enforcement-log.jsonl" 2>/dev/null || :
  return 0
}

# ==== Descricao da feature (contract §4.1a) ====
#
# O prompt da sessao-filha precisa casar o contrato REAL de /feature-00c
# (plugins/cstk/commands/feature-00c.md:113-115): primeiro argumento
# posicional = DESCRICAO (string em quotes), segundo = short-name
# (opcional, kebab-case). Emitir so `/feature-00c <SHORT>` fazia o
# short-name ser lido como descricao e o short-name REAL ser re-derivado
# pelo specify — divergindo da worktree/branch ja criada por
# `cstk session start <SHORT>` e do `feature=<short>` da notificacao.
#
# Fonte da descricao, em ordem de precedencia:
#   1. --description TEXT (explicito, pareado com o --feature anterior)
#   2. bloco `**Descricao**:` da entrada em docs/roadmap.md
#      (contracts/roadmap-artifact.md §2)
#   3. fallback = o proprio SHORT (degradado, com aviso em stderr)
#
# Conteudo do roadmap e UNTRUSTED (mesmo rotulo `roadmap-prose-untrusted`
# ja usado por roadmap-frontier.sh §6): NUNCA entra bruto na composicao —
# passa sempre por _pl_sanitize_desc.

# _pl_sanitize_desc TEXT -> texto de uma linha, sem metacaractere de shell
# nem aspa (de qualquer especie), colapsado e truncado a 300 chars.
# A remocao de `'` e `"` e o que torna seguro o envelope
# `'/feature-00c "<DESC>" <SHORT>'` da composicao (§4.1).
_pl_sanitize_desc() {
  printf '%s' "$1" \
    | tr '\n\r\t' '   ' \
    | tr -d '[:cntrl:]' \
    | tr -d "\"\`\\\\\$;&|<>!#" \
    | tr -d "'" \
    | tr -s ' ' \
    | sed 's/^ *//; s/ *$//' \
    | cut -c1-300
}

# _pl_desc_from_roadmap ROADMAP SHORT -> texto do paragrafo
# `**Descricao**:` da entrada `### N. SHORT` (linhas de continuacao
# juntadas por espaco). Vazio se o arquivo, a entrada ou o campo nao
# existirem — ausencia NUNCA e erro (best-effort, mesma politica do aviso
# de sobreposicao de roadmap-frontier.sh).
_pl_desc_from_roadmap() {
  [ -f "$1" ] || return 0
  awk -v target="$2" '
    /^###[[:space:]]+[0-9]+\.[[:space:]]+/ {
      hdr = $0
      sub(/^###[[:space:]]+[0-9]+\.[[:space:]]+/, "", hdr)
      sub(/[[:space:]]+$/, "", hdr)
      inblock = (hdr == target)
      collecting = 0
      next
    }
    !inblock { next }
    /^\*\*Descri[^*]*\*\*:/ {
      line = $0
      sub(/^\*\*Descri[^*]*\*\*:[[:space:]]*/, "", line)
      out = line
      collecting = 1
      next
    }
    collecting {
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*[*-]/ || $0 ~ /^#/) {
        collecting = 0
        next
      }
      out = out " " $0
    }
    END { printf "%s", out }
  ' "$1" 2>/dev/null || :
}

# _pl_resolve_desc SHORT EXPLICIT_DESC -> descricao final ja sanitizada.
# Aplica a precedencia acima e avisa (stderr) quando cai no fallback.
_pl_resolve_desc() {
  _pl_rd_short=$1
  _pl_rd_explicit=$2

  _pl_rd_out=$(_pl_sanitize_desc "$_pl_rd_explicit")
  if [ -z "$_pl_rd_out" ] && [ -n "$_pl_roadmap" ]; then
    _pl_rd_out=$(_pl_sanitize_desc "$(_pl_desc_from_roadmap "$_pl_roadmap" "$_pl_rd_short")")
  fi
  if [ -z "$_pl_rd_out" ]; then
    _pl_rd_out=$_pl_rd_short
    printf '%s: descricao ausente para %s (nem --description nem **Descricao**: em %s) — usando o short-name como descricao\n' \
      "$_PL_NAME" "$_pl_rd_short" "${_pl_roadmap:-<sem roadmap>}" >&2
  fi
  printf '%s' "$_pl_rd_out"
}

# _pl_flush_pending: fecha o par (--feature, --description) corrente na
# lista `_pl_features`, uma entrada por linha no formato
# `SHORT<TAB>DESC_BRUTA`. O TAB e separador seguro porque a descricao so
# entra na composicao depois de _pl_sanitize_desc (que ja remove TAB).
_pl_flush_pending() {
  [ -n "$_pl_pending_short" ] || return 0
  _pl_features=$(printf '%s%s\t%s\n' "$_pl_features" "$_pl_pending_short" "$_pl_pending_desc")
  _pl_features="${_pl_features}
"
  _pl_pending_short=""
  _pl_pending_desc=""
}

# ==== telemetria da filha (issue #168) ====
#
# O wrapper de telemetria que `cstk install` oferece e uma FUNCAO de shell
# `claude()`. A linha emitida aqui e executada por `tmux split-window`, que
# roda o comando por um `sh -c` NAO-INTERATIVO — o rc nem e lido, a funcao
# nao existe, e a filha subia sem telemetria (otel_usage null em todas as
# ondas dela). Prefixamos a composicao com `env VAR=... ` para nao depender
# de rc, shell nem tmux. `env` (binario real) em vez do prefixo nu
# `VAR=v cmd` porque tmux pode executar a lista de argumentos sem passar por
# shell, e nesse caminho o prefixo nu seria tratado como nome de programa.
#
# DIFERENCA DELIBERADA em relacao a cli/lib/telemetry-env.sh: la, um
# CSTK_OTEL_ENDPOINT ja presente no ambiente significa "ja configurado, nao
# toca", porque o exec SUBSTITUI o processo corrente. Aqui nao: o ambiente
# corrente e o da SESSAO COORDENADORA, e cada filha precisa da PROPRIA porta
# (o exporter vive dentro de cada processo `claude`; duas filhas na mesma
# porta = uma delas nao mede). Herdar o endpoint da coordenadora seria o bug
# que `cstk setup` ja avisa em outro contexto.
#
# Sem porta sorteavel (python3 ausente) NAO caimos na porta default fixa
# 9464 — ao contrario do lancador de processo unico: aqui ha N filhas por
# construcao, e todas na mesma porta fixa e pior que nenhuma. Emite aviso e
# segue sem telemetria.
#
# Kill switch: CSTK_TELEMETRY_AUTO=0.
_PL_OTEL_OK=0

# _pl_otel_check -> decide UMA vez por invocacao de `emit` se ha como ligar
# telemetria, e avisa (uma unica linha) se nao ha. Precisa rodar FORA de
# command substitution: `_pl_otel_prefix` e chamado dentro de `$( )`, que e
# subshell — um flag setado la nao volta, e o aviso sairia uma vez por
# filha.
_pl_otel_check() {
  _PL_OTEL_OK=0
  case "${CSTK_TELEMETRY_AUTO:-1}" in
    0|no|NO|off|OFF|false|FALSE) return 0 ;;
  esac
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s: telemetria: python3 ausente — nao ha como sortear porta livre; filha(s) lancada(s) SEM telemetria (custo/tokens ficarao "-" no painel). Ver: cstk help telemetry\n' \
      "$_PL_NAME" >&2
    return 0
  fi
  _PL_OTEL_OK=1
}

# _pl_otel_prefix -> imprime `env VAR=... ` (com espaco final) ou nada.
# Uma porta NOVA por chamada (uma por filha).
_pl_otel_prefix() {
  [ "$_PL_OTEL_OK" = 1 ] || return 0
  _plop_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null) || _plop_port=""
  case "$_plop_port" in
    ''|*[!0-9]*) _plop_port="" ;;
  esac
  if [ -z "$_plop_port" ]; then
    # python3 existe mas o bind falhou (raro). Avisa por filha afetada — o
    # stderr do subshell chega ao chamador normalmente.
    printf '%s: telemetria: falha ao sortear porta livre — esta filha sobe SEM telemetria.\n' \
      "$_PL_NAME" >&2
    return 0
  fi
  printf 'env CLAUDE_CODE_ENABLE_TELEMETRY=1 OTEL_METRICS_EXPORTER=prometheus OTEL_EXPORTER_PROMETHEUS_PORT=%s CSTK_OTEL_ENDPOINT=http://127.0.0.1:%s/metrics ' \
    "$_plop_port" "$_plop_port"
}

# ==== emit ====

_pl_cmd_emit() {
  _pl_repo=""
  _pl_coordinator=""
  _pl_roadmap=""
  _pl_saw_roadmap=0
  _pl_features=""
  _pl_n_features=0
  _pl_pending_short=""
  _pl_pending_desc=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        [ $# -ge 2 ] || { printf '%s: --repo exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_repo=$2; shift 2 ;;
      --feature)
        [ $# -ge 2 ] || { printf '%s: --feature exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_flush_pending
        _pl_pending_short=$2
        _pl_pending_desc=""
        _pl_n_features=$((_pl_n_features + 1))
        shift 2 ;;
      --description)
        [ $# -ge 2 ] || { printf '%s: --description exige valor\n' "$_PL_NAME" >&2; exit 2; }
        [ -n "$_pl_pending_short" ] || {
          printf '%s: --description exige um --feature imediatamente antes\n' "$_PL_NAME" >&2
          exit 2
        }
        _pl_pending_desc=$2
        shift 2 ;;
      --roadmap)
        [ $# -ge 2 ] || { printf '%s: --roadmap exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_roadmap=$2; _pl_saw_roadmap=1; shift 2 ;;
      --coordinator-name)
        [ $# -ge 2 ] || { printf '%s: --coordinator-name exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_coordinator=$2; shift 2 ;;
      *)
        printf '%s: flag desconhecida: %s\n' "$_PL_NAME" "$1" >&2
        exit 2 ;;
    esac
  done

  _pl_flush_pending

  [ -n "$_pl_repo" ] || { printf '%s: --repo obrigatorio\n' "$_PL_NAME" >&2; exit 2; }
  [ "$_pl_n_features" -ge 1 ] || { printf '%s: pelo menos um --feature obrigatorio\n' "$_PL_NAME" >&2; exit 2; }

  # Decide uma unica vez se ha telemetria (e avisa, uma linha so, se nao ha).
  # Depois da validacao de argumentos: erro de uso nao deve vir precedido de
  # aviso de telemetria.
  _pl_otel_check

  # Default do roadmap: <repo>/docs/roadmap.md (contract §4.1a). Ausente =>
  # nenhuma descricao vinda do roadmap, NUNCA erro. `--roadmap` explicito
  # com path inexistente tambem nao aborta (best-effort), so nao rende
  # descricao.
  if [ "$_pl_saw_roadmap" = 0 ]; then
    _pl_roadmap="$_pl_repo/docs/roadmap.md"
  fi
  [ -f "$_pl_roadmap" ] || _pl_roadmap=""

  if [ -n "$_pl_coordinator" ] && ! _pl_valid_coordinator "$_pl_coordinator"; then
    printf '%s: --coordinator-name invalido (esperado ^cstk-coord/[A-Za-z0-9._-]{1,64}$): %s\n' \
      "$_PL_NAME" "$_pl_coordinator" >&2
    exit 2
  fi

  # Derivacao de <WORKTREE> = <pai-do-repo>/<nome-do-repo>-<SHORT>, mesma
  # derivacao literal de cli/lib/session.sh:243. dirname/basename sao
  # puramente sintaticos — nao exige que --repo exista no disco.
  _pl_parent=$(dirname -- "$_pl_repo")
  _pl_repo_name=$(basename -- "$_pl_repo")

  _pl_have_tmux=false
  if command -v tmux >/dev/null 2>&1; then
    _pl_have_tmux=true
  fi

  # TOCTOU-recompute (contract §4.2/2.6.4) — segunda camada da guarda
  # anti-duplicidade, independente de roadmap-frontier.sh, no momento mais
  # proximo possivel da execucao de fato.
  _pl_load_active_branches "$_pl_repo"

  IFS='
'
  for _pl_entry in $_pl_features; do
    unset IFS
    [ -n "$_pl_entry" ] || continue
    # TAB literal via variavel: em sh o padrao `\t` dentro de ${v%%...} e
    # um `t` escapado, NAO um tab.
    _pl_short=${_pl_entry%%"$_PL_TAB"*}
    _pl_desc_raw=${_pl_entry#*"$_PL_TAB"}
    [ "$_pl_desc_raw" != "$_pl_entry" ] || _pl_desc_raw=""
    [ -n "$_pl_short" ] || continue

    if ! _pl_valid_short "$_pl_short"; then
      printf '%s: --feature invalido (esperado ^[a-z][a-z0-9-]*$, <=64 chars): %s\n' \
        "$_PL_NAME" "$_pl_short" >&2
      _pl_write_log "$_pl_repo" "$_pl_short" "$_pl_repo_name" "" \
        "blocked-invalid-feature" "" || :
      exit 2
    fi

    _pl_worktree="$_pl_parent/$_pl_repo_name-$_pl_short"
    _pl_child="cstk-feature/$_pl_short"

    if _pl_is_duplicate "$_pl_short"; then
      printf '%s: %s ja tem worktree ativa em %s — lancamento bloqueado (guarda anti-duplicidade)\n' \
        "$_PL_NAME" "$_pl_short" "$_pl_repo" >&2
      _pl_write_log "$_pl_repo" "$_pl_short" "$_pl_repo_name" "$_pl_worktree" \
        "blocked-duplicate" "" || :
      continue
    fi

    if ! _pl_valid_child "$_pl_child"; then
      # Nao deveria ocorrer (SHORT ja validado acima constroi um valor que
      # sempre casa) — defesa em profundidade contra regressao futura no
      # padrao de composicao.
      printf '%s: <CHILD_NAME> composto invalido (bug interno): %s\n' \
        "$_PL_NAME" "$_pl_child" >&2
      exit 2
    fi

    # Composicao compartilhada (byte a byte identica nos dois caminhos —
    # contract §4, decisao de desenho: US1 automatico e US3 degradado
    # comparaveis).
    # Prompt da filha no formato REAL de /feature-00c: "<DESCRICAO>" <SHORT>
    # (feature-00c.md:113-115). O short-name posicional PINA a feature —
    # sem ele o specify re-derivaria um short-name possivelmente diferente
    # da worktree/branch criada por `cstk session start <SHORT>`.
    # Envelope em aspas SIMPLES para caber as aspas duplas da descricao;
    # seguro porque _pl_sanitize_desc remove aspa simples, aspa dupla,
    # crase, `\`, `$` e demais metacaracteres (§4.1).
    _pl_desc=$(_pl_resolve_desc "$_pl_short" "$_pl_desc_raw")
    _pl_prompt=$(printf "'/feature-00c \"%s\" %s'" "$_pl_desc" "$_pl_short")
    # Prefixo de telemetria: UMA porta por filha (issue #168). Fica FORA do
    # trecho comparado byte a byte entre os dois caminhos (a comparacao
    # comeca em `claude --name`), justamente porque a porta e por-filha e
    # nao poderia ser identica entre duas invocacoes.
    _pl_claude_argv=$(printf '%sclaude --name "%s" %s' \
      "$(_pl_otel_prefix)" "$_pl_child" "$_pl_prompt")

    _pl_line1=$(printf 'cstk session start %s' "$_pl_short")
    if $_pl_have_tmux; then
      # SEMPRE split-window (nunca new-window): a leva paralela fica no
      # MESMO window da coordenadora, em panes irmaos. `split-window` nao
      # tem `-n` (nao nomeia window) — a identificacao da filha continua
      # sendo `claude --name "<CHILD_NAME>"` + o pane_id devolvido por
      # `-P -F '#{pane_id}'`.
      _pl_line2=$(printf 'tmux split-window -c "%s" -P -F '"'"'#{pane_id}'"'"' \\\n  %s' \
        "$_pl_worktree" "$_pl_claude_argv")
    else
      _pl_line2=$(printf 'cd "%s" && %s' "$_pl_worktree" "$_pl_claude_argv")
    fi

    printf '%s\n%s\n' "$_pl_line1" "$_pl_line2"

    _pl_write_log "$_pl_repo" "$_pl_short" "$_pl_repo_name" "$_pl_worktree" \
      "launched" "$(printf '%s\n%s' "$_pl_line1" "$_pl_line2")" || :
  done
}

# ==== resolve-offer (feature roadmap-wave, contract
# roadmap-wave-command.md §3) ====
#
# Espelha em codigo testavel a decisao hoje descrita so em prosa nos
# passos 4-5 de agente-00c.md §6.ter. Precedente real:
# delivery-tier.sh resolve-initial --source <operator|absent> [--answer].
#
# _pl_strip_crlf STRING -> STRING sem \r/\n (contract §3.4). `$()` NAO
# remove \r — mesma classe do bug corrigido em delivery-tier.sh:306-307.
_pl_strip_crlf() {
  printf '%s' "$1" | tr -d '\r\n'
}

# _pl_is_int_1_8 STRING -> exit 0 se STRING e um inteiro decimal (sem
# sinal, sem espacos) em 1..8. POSIX puro, sem depender de `expr`/`bc`.
_pl_is_int_1_8() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 8 ]
}

_pl_cmd_resolve_offer() {
  _pl_ro_source=""
  _pl_ro_saw_source=0
  _pl_ro_confirm=""
  _pl_ro_max=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --source)
        [ $# -ge 2 ] || { printf '%s: --source exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_ro_source=$2; _pl_ro_saw_source=1; shift 2 ;;
      --confirm)
        [ $# -ge 2 ] || { printf '%s: --confirm exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_ro_confirm=$2; shift 2 ;;
      --max)
        [ $# -ge 2 ] || { printf '%s: --max exige valor\n' "$_PL_NAME" >&2; exit 2; }
        _pl_ro_max=$2; shift 2 ;;
      *)
        printf '%s: resolve-offer: flag desconhecida: %s\n' "$_PL_NAME" "$1" >&2
        exit 2 ;;
    esac
  done

  [ "$_pl_ro_saw_source" = 1 ] \
    || { printf '%s: resolve-offer: --source e obrigatorio (operator|absent)\n' "$_PL_NAME" >&2; exit 2; }

  case "$_pl_ro_source" in
    absent)
      # FR-014: sem operador, sem lancamento — --confirm/--max NEM SAO
      # lidos (fail-safe, paridade com delivery-tier.sh resolve-initial
      # --source absent).
      printf 'launch=no\nmax=2\n'
      return 0 ;;
    operator) : ;;
    *)
      printf '%s: resolve-offer: --source aceita apenas operator|absent\n' "$_PL_NAME" >&2
      exit 2 ;;
  esac

  # Higiene de entrada (contract §3.4) — ANTES de qualquer comparacao.
  _pl_ro_confirm=$(_pl_strip_crlf "$_pl_ro_confirm")
  _pl_ro_max=$(_pl_strip_crlf "$_pl_ro_max")

  case "$_pl_ro_confirm" in
    s|S|y|Y|sim|yes) : ;;
    *)
      # Fora do enum, inclusive vazio/Enter ⇒ launch=no (FR-007).
      printf 'launch=no\nmax=2\n'
      return 0 ;;
  esac

  if [ -z "$_pl_ro_max" ]; then
    # confirm valido + max ausente/vazio ⇒ default 2 (FR-007, FR-013).
    printf 'launch=yes\nmax=2\n'
    return 0
  fi

  if _pl_is_int_1_8 "$_pl_ro_max"; then
    printf 'launch=yes\nmax=%s\n' "$_pl_ro_max"
    return 0
  fi

  # max mal-formado/0/negativo/>8 ⇒ launch=no + diagnostico, fail-closed
  # (FR-007). Teto 8 e politica de design ja fixada no contract (F2 do
  # gate owasp-security) — nao reabrir esse numero.
  printf '%s: resolve-offer: --max invalido (esperado inteiro 1..8): %s\n' \
    "$_PL_NAME" "$_pl_ro_max" >&2
  printf 'launch=no\nmax=2\n'
  return 0
}

case "$_PL_SUBCOMMAND" in
  emit)
    _pl_cmd_emit "$@" ;;
  check-tmux)
    _pl_cmd_check_tmux ;;
  resolve-offer)
    _pl_cmd_resolve_offer "$@" ;;
  -h|--help)
    print_usage; exit 0 ;;
  *)
    printf '%s: subcomando desconhecido: %s\n' "$_PL_NAME" "$_PL_SUBCOMMAND" >&2
    print_usage >&2
    exit 2 ;;
esac
