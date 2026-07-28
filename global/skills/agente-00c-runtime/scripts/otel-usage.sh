#!/bin/sh
# otel-usage.sh — consumo real de tokens/custo por onda via telemetria OTel
# nativa do Claude Code (exporter Prometheus).
#
# POR QUE ISTO EXISTE
# -------------------
# A metrica de consumo por onda tinha duas fontes anteriores, ambas furadas:
#
#   1. `posttooluse-agent-usage.sh` (hook PostToolUse/Agent) le o tool_response
#      do spawn. Mas o spawn ENVOLVE a onda — o command pai spawna o
#      orquestrador, e e o orquestrador que abre e fecha a onda por dentro.
#      O tool_result chega DEPOIS do `end` (que ja resetou o sidecar) e e
#      destruido pelo `start` da onda seguinte. O consumo do orquestrador —
#      a maior parte do custo — nunca era capturado.
#
#   2. A Usage & Cost Admin API da Anthropic nao serve: exige Admin key
#      (`sk-ant-admin01-...`), e indisponivel para contas individuais, e
#      NAO tem dimensao de sessao (agrupa por api_key/workspace/model). A
#      Claude Code Analytics API e por usuario/DIA, com 1h de lag.
#
# A telemetria OTel resolve as duas: os contadores sao incrementados A CADA
# API REQUEST, nao no fim do spawn, e carregam `query_source` (main |
# subagent | auxiliary | sdk). Um snapshot no inicio e outro no fim da onda
# dao o delta exato, INDEPENDENTE de quando o spawn retorna — que era a
# causa raiz do bug anterior.
#
# Medido em 2026-07-26 (task delegada trivial): main $0.156535, subagent
# $0.141282, auxiliary $0.000674. O subagente era ~47% do custo — exatamente
# a fatia que o painel mostrava como "-".
#
# PRE-REQUISITO (opt-in do operador, sem segredo nenhum)
# ------------------------------------------------------
#   export CLAUDE_CODE_ENABLE_TELEMETRY=1
#   export OTEL_METRICS_EXPORTER=prometheus
#
# Nao exige API key, nem Admin key, nem organizacao — funciona em plano de
# assinatura. O exporter sobe um HTTP local em 127.0.0.1:9464/metrics; nada
# trafega para fora da maquina.
#
# PRIVACIDADE (regra dura)
# ------------------------
# Os labels do exporter carregam PII: `user_email`, `user_id`,
# `user_account_uuid`, `user_account_id`, `organization_id`. Este script
# descarta TODOS eles no snapshot — so `session_id`, `model`, `query_source`
# e `type` sobrevivem. PII nunca toca o sidecar, o state.json nem a
# knowledge.db.
#
# Subcomandos:
#   otel-usage.sh available [--endpoint URL]
#       — exit 0 se o endpoint responde com metricas claude_code; 1 se nao.
#         Nao escreve nada. Use para decidir se vale chamar snapshot.
#
#   otel-usage.sh snapshot --state-dir DIR --phase start|end [--endpoint URL]
#       — Scrape + filtro + strip de PII -> <state-dir>/otel-<phase>.tsv
#         (TSV: session_id \t query_source \t model \t type \t value;
#         `type` = "cost" na linha de custo). Best-effort: endpoint fora
#         do ar -> exit 0 sem escrever, a onda segue normal.
#
#   otel-usage.sh delta --state-dir DIR
#       — end - start por chave (session, source, model, type), duplicatas
#         SOMADAS, resultado atribuido a UNICA sessao que cresceu (ver
#         bloco MULTIPLAS SESSOES). JSON no stdout. Sem os dois snapshots,
#         mais de uma sessao ativa, processo trocado ou snapshot em
#         formato antigo: imprime `null` e sai 0 (metrica ausente NUNCA e
#         zero fabricado — Principio VI).
#
# MULTIPLAS SESSOES NO MESMO EXPORTER (bug real, 2026-07-28)
# ----------------------------------------------------------
# O processo dono da porta 9464 pode ser um claude -c longevo que expoe
# metricas de MAIS DE UMA sessao — inclusive sessoes paradas ha horas,
# congeladas com acumulado gigante. Na execucao dashboard-refactor, 14
# ondas gravaram 212.447.680 tokens / $88 bit-identicos porque:
#   (a) o parse descartava o session_id das linhas, somando o historico
#       de todas as sessoes do processo; e
#   (b) a chave do join (source, model, type) colide entre linhas que o
#       exporter separa por agent_name/skill_name/effort — o awk
#       sobrescrevia a base (s[k]=$4) e imprimia cada duplicata do end
#       contra essa base unica, transformando o "delta" no acumulado.
# O delta agora agrega por sessao (duplicatas somadas) e so aceita o
# resultado quando EXATAMENTE UMA sessao cresceu entre os snapshots —
# crescimento que, por construcao, aconteceu dentro da janela da onda.
# Sessao congelada tem delta 0 e nao contamina. Dois casos continuam
# indecidiveis e viram null (nunca chute):
#   - mais de uma sessao cresceu (outro claude ativo no mesmo exporter);
#   - sessao do start ausente no end (o processo dono da porta trocou;
#     num exporter vivo sessao nunca some — contador e cumulativo).
# NOTA: o session_id do OTel nao serve como IDENTIDADE da sessao corrente
# (label ja observado apontando para outra sessao/projeto), por isso NAO
# ha match contra env — apenas deteccao de crescimento por sessao.
#
# Exit codes:
#   0  sucesso, ou degradacao best-effort (sem telemetria disponivel)
#   1  erro de I/O
#   2  uso incorreto
#
# POSIX sh + awk + jq (jq ja e dependencia documentada do runtime).

set -eu

_OU_NAME="otel-usage"
# Endpoint default do exporter Prometheus do Claude Code. Override via
# CSTK_OTEL_ENDPOINT para porta customizada (OTEL_EXPORTER_PROMETHEUS_PORT
# no lado do Claude Code) ou para apontar a um arquivo em teste.
_OU_DEFAULT_ENDPOINT="${CSTK_OTEL_ENDPOINT:-http://127.0.0.1:9464/metrics}"

# Labels que NUNCA podem sair do processo. Ver bloco PRIVACIDADE acima.
_OU_PII_LABELS="user_id user_email user_account_uuid user_account_id organization_id"

_ou_die_usage() { printf '%s: %s\n' "$_OU_NAME" "$1" >&2; exit 2; }
_ou_die()       { printf '%s: %s\n' "$_OU_NAME" "$1" >&2; exit "${2:-1}"; }
_ou_warn()      { printf '%s: %s\n' "$_OU_NAME" "$1" >&2; }

_ou_have_curl() { command -v curl >/dev/null 2>&1; }

# _ou_scrape ENDPOINT OUTFILE -> 0 se trouxe as metricas que ESTE script
# consome, 1 se nao. Timeout curto: isto roda no caminho de start/end da
# onda e NUNCA pode pendurar a execucao.
#
# O predicado exige `claude_code_(cost|token)_usage_total`, nao um
# `claude_code_` generico: nos primeiros segundos de uma sessao o exporter
# ja responde com `claude_code_session_count_total` mas ainda nao emitiu
# nenhuma linha de custo/token — e um snapshot dai sai sem `session_id`,
# o que faz o guard do delta descartar a onda inteira. Medido em cold
# start: `available` passava em t=2s e o delta virava null.
_ou_scrape() {
  _ou_have_curl || return 1
  curl -s --max-time 3 -o "$2" "$1" 2>/dev/null || return 1
  [ -s "$2" ] || return 1
  grep -q '^claude_code_\(cost\|token\)_usage_total{' "$2" 2>/dev/null || return 1
  return 0
}

# _ou_parse INFILE -> TSV em stdout:
#   session_id \t query_source \t model \t type \t value
#
# Formato de entrada (verificado empiricamente contra Claude Code 2.1.220):
#   claude_code_cost_usage_total{...,model="X",query_source="Y",...} 0.000637
#   claude_code_token_usage_total{...,query_source="Y",type="input",...} 532
#
# O session_id sai POR LINHA porque o mesmo exporter pode carregar varias
# sessoes (ver bloco MULTIPLAS SESSOES no topo) — o delta precisa separar
# o crescimento da sessao corrente do acumulado congelado das demais.
#
# O strip de PII acontece por CONSTRUCAO: extraimos apenas os 4 labels da
# allowlist e descartamos a linha original. Nao ha caminho em que um label
# nao-listado chegue a saida.
_ou_parse() {
  awk '
    # ANCORAGEM OBRIGATORIA em `{` ou `,`: sem ela, procurar `type="` casa
    # primeiro com `terminal_type="ghostty"` (substring), e o breakdown por
    # tipo de token vira o nome do terminal. Bug observado: by_source com
    # input/output/cache zerados enquanto total_tokens vinha certo.
    function label(line, name,   re, seg) {
      re = "[{,]" name "=\"[^\"]*\""
      if (match(line, re)) {
        seg = substr(line, RSTART + 1, RLENGTH - 1)
        sub(name "=\"", "", seg)
        sub("\"$", "", seg)
        return seg
      }
      return "-"
    }
    /^claude_code_cost_usage_total\{/ {
      v = $NF
      print label($0,"session_id") "\t" label($0,"query_source") "\t" label($0,"model") "\tcost\t" v
      next
    }
    /^claude_code_token_usage_total\{/ {
      v = $NF
      print label($0,"session_id") "\t" label($0,"query_source") "\t" label($0,"model") "\t" label($0,"type") "\t" v
      next
    }
  ' "$1"
}

# _ou_session_id INFILE -> session_id do scrape (primeira ocorrencia), ou "".
# Hoje e so o header INFORMATIVO `# session_id` do snapshot (debug humano).
# O delta NAO depende dele: compara sessoes POR LINHA — o header com a
# "primeira ocorrencia" passava batido quando o scrape misturava sessoes.
_ou_session_id() {
  awk '
    /^claude_code_(cost|token)_usage_total\{/ {
      if (match($0, "session_id=\"[^\"]*\"")) {
        s = substr($0, RSTART, RLENGTH)
        sub("session_id=\"", "", s); sub("\"$", "", s)
        print s; exit
      }
    }
  ' "$1"
}

_ou_cmd_available() {
  _ou_ep="$_OU_DEFAULT_ENDPOINT"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --endpoint) [ "$#" -ge 2 ] || _ou_die_usage "available: --endpoint exige valor"
                  _ou_ep=$2; shift 2 ;;
      *) _ou_die_usage "available: flag desconhecida: $1" ;;
    esac
  done
  _ou_tmp=$(mktemp) || _ou_die "mktemp falhou"
  if _ou_scrape "$_ou_ep" "$_ou_tmp"; then
    rm -f -- "$_ou_tmp"
    return 0
  fi
  rm -f -- "$_ou_tmp"
  return 1
}

_ou_cmd_snapshot() {
  _ou_sdir=""; _ou_phase=""; _ou_ep="$_OU_DEFAULT_ENDPOINT"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) [ "$#" -ge 2 ] || _ou_die_usage "snapshot: --state-dir exige valor"
                   _ou_sdir=$2; shift 2 ;;
      --phase)     [ "$#" -ge 2 ] || _ou_die_usage "snapshot: --phase exige valor"
                   _ou_phase=$2; shift 2 ;;
      --endpoint)  [ "$#" -ge 2 ] || _ou_die_usage "snapshot: --endpoint exige valor"
                   _ou_ep=$2; shift 2 ;;
      *) _ou_die_usage "snapshot: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_ou_sdir" ]  || _ou_die_usage "snapshot: --state-dir obrigatorio"
  [ -n "$_ou_phase" ] || _ou_die_usage "snapshot: --phase obrigatorio"
  case "$_ou_phase" in
    start|end) : ;;
    *) _ou_die_usage "snapshot: --phase deve ser start|end" ;;
  esac
  [ -d "$_ou_sdir" ] || _ou_die "snapshot: state-dir nao existe: $_ou_sdir"

  _ou_tmp=$(mktemp) || _ou_die "mktemp falhou"
  if ! _ou_scrape "$_ou_ep" "$_ou_tmp"; then
    rm -f -- "$_ou_tmp"
    # Best-effort: sem telemetria a onda roda igual, so sem a metrica.
    # Remove um snapshot da fase anterior para nao casar start de uma
    # execucao com end de outra.
    rm -f -- "$_ou_sdir/otel-$_ou_phase.tsv" 2>/dev/null || :
    _ou_warn "telemetria OTel indisponivel em $_ou_ep — metrica de custo da onda ficara ausente (nao zero)"
    return 0
  fi

  _ou_out="$_ou_sdir/otel-$_ou_phase.tsv"
  {
    printf '# session_id\t%s\n' "$(_ou_session_id "$_ou_tmp")"
    _ou_parse "$_ou_tmp"
  } > "$_ou_out.tmp" || { rm -f -- "$_ou_tmp" "$_ou_out.tmp"; _ou_die "snapshot: falha ao escrever $_ou_out"; }
  mv -- "$_ou_out.tmp" "$_ou_out" || { rm -f -- "$_ou_tmp"; _ou_die "snapshot: falha ao mover $_ou_out"; }
  chmod 600 -- "$_ou_out" 2>/dev/null || :
  rm -f -- "$_ou_tmp"

  # Defesa em profundidade: o parse ja e allowlist, mas se algum label de
  # PII aparecer no arquivo final, apaga e falha alto em vez de vazar.
  for _ou_lbl in $_OU_PII_LABELS; do
    if grep -q "$_ou_lbl" "$_ou_out" 2>/dev/null; then
      rm -f -- "$_ou_out"
      _ou_die "snapshot: ABORTADO — label de PII '$_ou_lbl' vazou para o snapshot" 1
    fi
  done
  return 0
}

_ou_cmd_delta() {
  _ou_sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) [ "$#" -ge 2 ] || _ou_die_usage "delta: --state-dir exige valor"
                   _ou_sdir=$2; shift 2 ;;
      *) _ou_die_usage "delta: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_ou_sdir" ] || _ou_die_usage "delta: --state-dir obrigatorio"

  _ou_s="$_ou_sdir/otel-start.tsv"
  _ou_e="$_ou_sdir/otel-end.tsv"
  # Ausencia de qualquer um dos lados => metrica INDISPONIVEL, nao zero.
  if [ ! -f "$_ou_s" ] || [ ! -f "$_ou_e" ]; then
    printf 'null\n'
    return 0
  fi

  command -v jq >/dev/null 2>&1 || { _ou_warn "delta: jq ausente"; printf 'null\n'; return 0; }

  # Join por chave COMPLETA (session, source, model, type), SOMANDO
  # duplicatas nos dois lados — o exporter emite linhas separadas por
  # agent_name/skill_name/effort que colidem nessa chave; sobrescrever
  # congelava o "delta" no acumulado (ver bloco MULTIPLAS SESSOES).
  # O resultado so vale se EXATAMENTE UMA sessao cresceu. Saidas do awk:
  #   exit 0 — rows da sessao vencedora (vazio: nada cresceu -> null)
  #   exit 3 — snapshot em formato antigo (4 colunas, sem session_id)
  #   exit 4 — sessao do start ausente no end (processo do exporter trocou)
  #   exit 5 — mais de uma sessao cresceu (linha "# ambiguous" lista quais)
  _ou_rows=$(mktemp) || _ou_die "mktemp falhou"
  _ou_rc=0
  awk -F'\t' '
    BEGIN { OFMT = "%.12g"; CONVFMT = "%.12g" }
    FILENAME==ARGV[1] && !/^#/ {
      if (NF != 5) { legacy = 1; next }
      s[$1 FS $2 FS $3 FS $4] += $5
      seen_start[$1] = 1
      next
    }
    FILENAME==ARGV[2] && !/^#/ {
      if (NF != 5) { legacy = 1; next }
      e[$1 FS $2 FS $3 FS $4] += $5
      seen_end[$1] = 1
    }
    END {
      if (legacy) exit 3
      for (sid in seen_start) if (!(sid in seen_end)) exit 4
      n = 0
      for (k in e) {
        base = (k in s) ? s[k] : 0
        d = e[k] - base           # contador reiniciado (d<0): nao inventa
        if (d > 0) {
          split(k, p, FS)
          if (!(p[1] in grown)) { n++; list = (n > 1) ? list "," p[1] : p[1] }
          grown[p[1]] = 1
          delta[k] = d
        }
      }
      if (n == 0) exit 0
      if (n > 1) { print "# ambiguous\t" list; exit 5 }
      cur = list
      print "# session_id\t" cur
      for (k in delta) {
        split(k, p, FS)
        if (p[1] == cur) print p[2] FS p[3] FS p[4] FS delta[k]
      }
    }
  ' "$_ou_s" "$_ou_e" > "$_ou_rows" || _ou_rc=$?

  case "$_ou_rc" in
    0) : ;;
    3) _ou_warn "delta: snapshot em formato antigo (sem session_id por linha) — delta descartado nesta onda"
       rm -f -- "$_ou_rows"; printf 'null\n'; return 0 ;;
    4) _ou_warn "delta: sessao do snapshot inicial ausente no snapshot final — processo do exporter trocou, delta descartado"
       rm -f -- "$_ou_rows"; printf 'null\n'; return 0 ;;
    5) _ou_amb=$(awk -F'\t' '/^# ambiguous/{print $2; exit}' "$_ou_rows")
       _ou_warn "delta: mais de uma sessao ativa no exporter ($_ou_amb) — atribuicao ambigua, delta descartado"
       rm -f -- "$_ou_rows"; printf 'null\n'; return 0 ;;
    *) _ou_warn "delta: falha inesperada no join (rc=$_ou_rc) — delta descartado"
       rm -f -- "$_ou_rows"; printf 'null\n'; return 0 ;;
  esac

  _ou_sid=$(awk -F'\t' '/^# session_id/{print $2; exit}' "$_ou_rows")
  grep -v '^#' "$_ou_rows" \
  | jq -c -R -s --arg sid "$_ou_sid" '
      [ split("\n")[] | select(length > 0) | split("\t")
        | {source: .[0], model: .[1], type: .[2], value: (.[3] | tonumber)} ]
      as $rows
      | if ($rows | length) == 0 then null else
      {
        session_id: $sid,
        total_cost_usd: ([$rows[] | select(.type=="cost") | .value] | add // 0),
        total_tokens:   ([$rows[] | select(.type!="cost") | .value] | add // 0),
        by_source: (
          [$rows[] | .source] | unique
          | map(. as $s | {
              key: $s,
              value: {
                cost_usd:       ([$rows[] | select(.source==$s and .type=="cost")          | .value] | add // 0),
                input:          ([$rows[] | select(.source==$s and .type=="input")         | .value] | add // 0),
                output:         ([$rows[] | select(.source==$s and .type=="output")        | .value] | add // 0),
                cache_read:     ([$rows[] | select(.source==$s and .type=="cacheRead")     | .value] | add // 0),
                cache_creation: ([$rows[] | select(.source==$s and .type=="cacheCreation") | .value] | add // 0)
              }
            })
          | from_entries
        ),
        by_model: (
          [$rows[] | .model] | unique
          | map(. as $m | {
              key: $m,
              value: {
                cost_usd:     ([$rows[] | select(.model==$m and .type=="cost") | .value] | add // 0),
                total_tokens: ([$rows[] | select(.model==$m and .type!="cost") | .value] | add // 0)
              }
            })
          | from_entries
        )
      } end
    '
  rm -f -- "$_ou_rows"
  return 0
}

# ---------- dispatch ----------

[ "$#" -gt 0 ] || _ou_die_usage "subcomando obrigatorio: available|snapshot|delta"

_ou_sub=$1
shift
case "$_ou_sub" in
  available) _ou_cmd_available "$@" ;;
  snapshot)  _ou_cmd_snapshot "$@" ;;
  delta)     _ou_cmd_delta "$@" ;;
  -h|--help)
    cat >&2 <<'HELP'
otel-usage.sh — consumo real de tokens/custo por onda (telemetria OTel do Claude Code)

USO:
  otel-usage.sh available [--endpoint URL]
  otel-usage.sh snapshot  --state-dir DIR --phase start|end [--endpoint URL]
  otel-usage.sh delta     --state-dir DIR

Pre-requisito (opt-in, sem segredo):
  export CLAUDE_CODE_ENABLE_TELEMETRY=1
  export OTEL_METRICS_EXPORTER=prometheus

Nao exige API key, Admin key nem organizacao; funciona em plano de assinatura.
Labels de PII (user_email, user_id, user_account_*, organization_id) sao
descartados no snapshot e nunca alcancam disco.

delta agrega por sessao (duplicatas de chave SOMADAS) e atribui o resultado
a unica sessao que cresceu entre os snapshots. Imprime `null` quando a
metrica esta ausente OU quando a atribuicao e ambigua (mais de uma sessao
ativa, processo do exporter trocado, snapshot em formato antigo) — nunca
zero fabricado.
HELP
    exit 2
    ;;
  *) _ou_die_usage "subcomando desconhecido: $_ou_sub" ;;
esac
