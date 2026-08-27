#!/bin/sh
# telemetry-env.sh — injecao das variaveis de telemetria OTel nos lancadores
# do proprio cstk (issue #168).
#
# ---- O problema que esta lib existe para resolver ----
# O opt-in de telemetria que `cstk install` oferece (e que `cstk help
# telemetry` imprime) e uma FUNCAO DE SHELL `claude()` no rc do operador.
# Os lancadores do proprio cstk chamam o BINARIO via `exec claude`, e `exec`
# nunca resolve funcao de shell:
#
#   $ sh -c 'foo() { echo FUNCAO; }; exec foo'
#   sh: exec: foo: not found
#
# Pior: esses lancadores rodam em `sh` NAO-INTERATIVO, onde o rc sequer e
# lido — a funcao nem existe ali. Resultado medido (issue #168): toda sessao
# iniciada por `cstk session start --claude`, `cstk 00c` ou pela leva
# paralela do roadmap rodava SEM telemetria, e o painel mostrava CUSTO e
# TOKENS·SUBAGENTES como "—" com os hooks todos corretamente provisionados.
# O produto anulava, por construcao, um recurso que o produto instala.
#
# A correcao e nao depender da funcao: resolver a porta e exportar as
# variaveis aqui, no proprio lancador, replicando o que o snippet canonico
# de `cli/install.sh` (telemetry_snippet) faz. Isso vale igual para quem usa
# o plugin nativo, que nao instala wrapper nenhum.
#
# ---- Fronteira ----
# Esta lib e RUNTIME do binario (`cstk self-update`), nao catalogo. O
# terceiro lancador — `parallel-launch.sh emit` — vive no catalogo e nao
# pode carregar esta lib; ele replica a MESMA decisao no proprio arquivo, e
# `tests/cstk/test_cstk-main.sh` gateia o drift entre os tres pontos + o
# snippet canonico.
#
# ---- Precedencia (nunca sobrescreve escolha explicita do operador) ----
#   1. CSTK_TELEMETRY_AUTO=0            -> nao injeta nada (kill switch)
#   2. CSTK_OTEL_ENDPOINT ja definido   -> ja configurado, nao toca
#   3. CLAUDE_CODE_ENABLE_TELEMETRY definido com valor != 1
#                                       -> opt-out explicito, nao toca
#   4. caso contrario                   -> injeta
#
# POSIX sh. Sem dependencia alem de python3 (mesma do snippet canonico).

# telemetry_env_enabled -> exit 0 se a injecao deve acontecer.
# Silencioso: quem chama decide se avisa.
telemetry_env_enabled() {
  case "${CSTK_TELEMETRY_AUTO:-1}" in
    0|no|NO|off|OFF|false|FALSE) return 1 ;;
  esac
  [ -z "${CSTK_OTEL_ENDPOINT:-}" ] || return 1
  case "${CLAUDE_CODE_ENABLE_TELEMETRY:-}" in
    ''|1) ;;
    *) return 1 ;;
  esac
  return 0
}

# telemetry_env_free_port -> imprime uma porta TCP livre em 127.0.0.1.
# Silencioso + exit 1 quando nao consegue (python3 ausente, bind negado).
#
# Mesma tecnica do snippet canonico: bind em porta 0 (o kernel escolhe uma
# livre), le o numero, fecha. Ha uma janela de corrida entre o close e o
# bind do exporter dentro do processo `claude` — janela que o snippet
# canonico ja tem e aceita; esta lib nao piora nem melhora esse ponto.
telemetry_env_free_port() {
  command -v python3 >/dev/null 2>&1 || return 1
  _tefp_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null) || return 1
  case "$_tefp_port" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s' "$_tefp_port"
}

# telemetry_exec_claude ARGS... -> exec do binario `claude` com as variaveis
# de telemetria ligadas SO no ambiente desse processo (nada e exportado para
# o shell chamador — mesma propriedade do snippet canonico, que evita o
# falso alarme "exporter-down" em terminal sem sessao ativa).
#
# NUNCA retorna em caso de sucesso (exec substitui o processo).
#
# Degradacao, em ordem:
#   - injecao desabilitada (ver telemetry_env_enabled) -> exec limpo, mudo;
#   - sem porta livre (python3 ausente) -> liga telemetria na porta default
#     fixa 9464, exatamente como o ramo sem-python3 do snippet canonico, e
#     AVISA que CSTK_OTEL_ENDPOINT ficou ausente. Isso mantem o custo por
#     onda medindo (cai no default) mas deixa `cstk usage` respondendo
#     "nao medido" — o hook de consumo avulso gateia nessa variavel.
telemetry_exec_claude() {
  if ! telemetry_env_enabled; then
    exec claude "$@"
  fi

  if _tec_port=$(telemetry_env_free_port); then
    CLAUDE_CODE_ENABLE_TELEMETRY=1 \
    OTEL_METRICS_EXPORTER=prometheus \
    OTEL_EXPORTER_PROMETHEUS_PORT="$_tec_port" \
    CSTK_OTEL_ENDPOINT="http://127.0.0.1:${_tec_port}/metrics" \
    exec claude "$@"
  fi

  printf 'cstk: telemetria: python3 ausente — nao consegui sortear porta livre.\n' >&2
  printf 'cstk: telemetria: subindo na porta default 9464 e SEM CSTK_OTEL_ENDPOINT;\n' >&2
  printf 'cstk: telemetria: o custo por onda mede, mas `cstk usage` vai responder "nao medido".\n' >&2
  printf 'cstk: telemetria: detalhes e alternativas: cstk help telemetry\n' >&2
  CLAUDE_CODE_ENABLE_TELEMETRY=1 \
  OTEL_METRICS_EXPORTER=prometheus \
  exec claude "$@"
}
