#!/bin/sh
# delivery-tier.sh — helper POSIX para o tier de entrega (feature
# delivery-tier).
#
# Feature: delivery-tier
# Ref:     docs/specs/delivery-tier/contracts/cli-delivery-tier.md
#          docs/specs/delivery-tier/contracts/tier-gate-map.md
#          docs/specs/delivery-tier/data-model.md
#
# Espelha roadmap-mode.sh (is-enabled/set-enabled) e model-routing.sh
# (phase-model-lookup, resolucao de path relativo ao script + parser
# POSIX-puro sem jq) — os dois precedentes citados no contrato.
#
# Subcomandos:
#   get      --state-dir DIR
#            stdout: exatamente 1 dos 4 tokens do enum + "\n". Exit 0
#            SEMPRE (exceto uso incorreto). Campo ausente/estado
#            ilegivel/token fora do enum => "cloud-public" (INV-1,
#            maior profundidade — degradar para MENOS rigor seria a
#            falha insegura). UNICA porta de leitura autorizada do tier
#            (INV-5) — nunca ler `.delivery_tier` cru via state-rw.sh.
#   set      --state-dir DIR --value <token> [--allow-downgrade]
#            Grava `.delivery_tier`. --value fora do enum => exit 2 sem
#            escrever. Elevacao (ordinal novo > atual) => grava, exit 0.
#            Ordinal igual => no-op idempotente, exit 0. Rebaixamento
#            (ordinal novo < atual) sem --allow-downgrade => exit 2 sem
#            escrever; com a flag, grava. NAO registra Decisao — quem
#            registra e o chamador (INV-4: SEMPRE o operador entre
#            ondas, nunca o orquestrador por iniciativa propria).
#   gate-mode --gate NOME [--tier TOKEN] [--state-dir DIR]
#            stdout: completo|leve|skip + "\n". Exit 0 SEMPRE (exceto
#            uso incorreto). --tier informado usa esse valor direto sem
#            ler estado; --tier omitido resolve via `get --state-dir
#            DIR` (exige --state-dir). Par (tier,gate) ausente da
#            tabela, tabela ausente/ilegivel, ou --gate desconhecido =>
#            "completo" (INV-2 — fail-safe SEMPRE na direcao da
#            profundidade; nenhum caminho de erro produz "skip").
#
# Exit codes (Principio II da constitution — 0/1/2):
#   0  sucesso (get/gate-mode: sempre, exceto uso incorreto; set:
#      gravado ou no-op idempotente)
#   1  falha de escrita no estado / state-rw.sh ausente
#   2  uso incorreto (flag faltando/desconhecida, --value fora do enum,
#      rebaixamento sem --allow-downgrade, --gate ausente)
#
# POSIX sh puro. gate-mode NAO depende de jq nem de state-rw.sh (so le o
# arquivo de mapa). get/set dependem de state-rw.sh (mesmo diretorio),
# que por sua vez exige jq.

set -eu

_DT_NAME="delivery-tier"

# ---------- helpers de log ----------

_dt_selfdir() { cd -- "$(dirname -- "$0")" && pwd; }
_dt_log_sourced=0
if _dt_sd0=$(_dt_selfdir 2>/dev/null) && [ -f "$_dt_sd0/_log.sh" ]; then
  # shellcheck disable=SC1090
  . "$_dt_sd0/_log.sh" && _dt_log_sourced=1
fi

_dt_err() {
  if [ "$_dt_log_sourced" = 1 ]; then
    log_err "$_DT_NAME: $*"
  else
    printf '%s: %s\n' "$_DT_NAME" "$*" >&2
  fi
}

_dt_die() {
  _dt_err "$1"
  exit "${2:-1}"
}

_dt_die_usage() {
  _dt_err "$1"
  exit 2
}

# Localiza state-rw.sh no mesmo diretorio que este script.
_dt_rw() {
  _dt_d=$(_dt_selfdir 2>/dev/null) || _dt_die "nao foi possivel resolver selfdir" 1
  printf '%s/state-rw.sh' "$_dt_d"
}

# Resolve o path canonico de tier-gate-map.txt, irmao de scripts/ dentro
# da skill agente-00c-runtime — mesma tecnica de
# model-routing.sh:_mr_phase_map_path. NAO falha se o arquivo nao
# existir; a checagem -f/-r fica no consumidor (fail-safe INV-2).
_dt_map_path() {
  _dt_msd=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || return 1
  printf '%s/../references/tier-gate-map.txt\n' "$_dt_msd"
}

# _dt_ordinal TOKEN -> imprime a posicao ordinal (0..3) do token no enum
# `local < internal-network < cloud-internal < cloud-public`
# (data-model.md §Ordem). TOKEN ja deve estar validado contra o enum
# pelo chamador; token desconhecido nunca chega aqui.
_dt_ordinal() {
  case "$1" in
    local)             printf '0' ;;
    internal-network)  printf '1' ;;
    cloud-internal)    printf '2' ;;
    cloud-public)      printf '3' ;;
  esac
}

# ---------- subcomando: get ----------
_dt_cmd_get() {
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir) _sdir=$2; shift 2 ;;
      *) _dt_die_usage "get: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ] || _dt_die_usage "get: --state-dir obrigatorio"

  _rw=$(_dt_rw)
  if [ ! -f "$_rw" ]; then
    printf 'cloud-public\n'
    return 0
  fi

  # Leitura defensiva (INV-1): estado ausente/ilegivel/campo ausente =>
  # "cloud-public". Nunca propaga erro do state-rw.sh.
  _val=$(sh "$_rw" get --state-dir "$_sdir" \
    --field '.delivery_tier // "cloud-public"' 2>/dev/null) || _val="cloud-public"

  # R1-equivalente (INV-5, finding F6 LLM01): coercao ao enum fechado.
  # NUNCA ecoar $_val verbatim — token corrompido/adulterado/fora do
  # enum vira "cloud-public" (maior profundidade), nunca outro valor.
  case "$_val" in
    local|internal-network|cloud-internal|cloud-public) printf '%s\n' "$_val" ;;
    *) printf 'cloud-public\n' ;;
  esac
  return 0
}

# ---------- subcomando: set ----------
_dt_cmd_set() {
  _sdir=""
  _value=""
  _allow_downgrade=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --state-dir)        _sdir=$2;  shift 2 ;;
      --value)            _value=$2; shift 2 ;;
      --allow-downgrade)  _allow_downgrade=1; shift 1 ;;
      *) _dt_die_usage "set: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_sdir" ]  || _dt_die_usage "set: --state-dir obrigatorio"
  [ -n "$_value" ] || _dt_die_usage "set: --value obrigatorio"

  case "$_value" in
    local|internal-network|cloud-internal|cloud-public) ;;
    *) _dt_die_usage "set: --value aceita apenas local|internal-network|cloud-internal|cloud-public" ;;
  esac

  _rw=$(_dt_rw)
  [ -f "$_rw" ] || _dt_die "state-rw.sh nao encontrado: $_rw" 1

  _current=$(_dt_cmd_get --state-dir "$_sdir")
  _cur_ord=$(_dt_ordinal "$_current")
  _new_ord=$(_dt_ordinal "$_value")

  if [ "$_new_ord" -lt "$_cur_ord" ] && [ "$_allow_downgrade" -ne 1 ]; then
    _dt_die "set: rebaixamento de '$_current' para '$_value' exige --allow-downgrade explicita (FR-009 — decisao manual do operador)" 2
  fi

  if [ "$_new_ord" -eq "$_cur_ord" ]; then
    # No-op idempotente: nao reescreve o estado desnecessariamente.
    return 0
  fi

  sh "$_rw" set --state-dir "$_sdir" \
    --field '.delivery_tier' \
    --value "\"$_value\"" || _dt_die "set: falha ao gravar state" 1

  return 0
}

# ---------- subcomando: gate-mode ----------
_dt_cmd_gate_mode() {
  _dt_gate=""
  _dt_tier=""
  _sdir=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gate)      _dt_gate=$2; shift 2 ;;
      --tier)      _dt_tier=$2; shift 2 ;;
      --state-dir) _sdir=$2;    shift 2 ;;
      *) _dt_die_usage "gate-mode: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_dt_gate" ] || _dt_die_usage "gate-mode: --gate obrigatorio"

  if [ -z "$_dt_tier" ]; then
    [ -n "$_sdir" ] || _dt_die_usage "gate-mode: --tier ou --state-dir obrigatorio"
    _dt_tier=$(_dt_cmd_get --state-dir "$_sdir")
  fi

  _dt_map=$(_dt_map_path) || {
    # Nao foi possivel resolver o diretorio do runtime: fail-safe INV-2.
    printf 'completo\n'
    return 0
  }

  [ -f "$_dt_map" ] && [ -r "$_dt_map" ] || {
    printf 'completo\n'
    return 0
  }

  # Parsing POSIX-puro (sem jq), espelha model-routing.sh
  # _mr_cmd_phase_model_lookup (:1076-1105).
  #
  # NOTA DE PORTABILIDADE (herdada, MUST): NAO usar `case ... esac`
  # dentro deste `$( ... )`. Varios `sh` (inclusive bash em modo POSIX
  # no macOS) falham no parse de `case` aninhado em
  # command-substitution ("syntax error near `;;'"). Skip de
  # comentario/branco e feito via expansao de parametro (extracao do
  # 1o caractere), 100% POSIX e sem esse bug.
  _dt_result=$(
    while IFS='|' read -r _t _g _m _rest; do
      [ -z "$_t" ] && continue
      _dt_first=${_t%"${_t#?}"}
      [ "$_dt_first" = "#" ] && continue
      # R2 (MUST): remover CR dos 3 campos antes de comparar/emitir —
      # tabela em CRLF (Windows/core.autocrlf) nao pode degradar
      # silenciosamente todo o arquivo. Gotcha ja ocorrido neste repo
      # (fix next-id, v7.5.1): `$( )` NAO remove `\r`.
      _t=$(printf '%s' "$_t" | tr -d '\r')
      _g=$(printf '%s' "$_g" | tr -d '\r')
      _m=$(printf '%s' "$_m" | tr -d '\r')
      if [ "$_t" = "$_dt_tier" ] && [ "$_g" = "$_dt_gate" ]; then
        printf '%s\n' "$_m"
        break
      fi
    done < "$_dt_map"
  )

  # R1 (MUST, OBRIGATORIO): coacao ao enum fechado. NUNCA ecoar
  # $_dt_result verbatim — par ausente, tabela malformada ou modo fora
  # do enum (`skipp`, `SKIP`, vazio, CRLF residual) vira "completo",
  # NUNCA "skip" (INV-2).
  case "$_dt_result" in
    completo|leve|skip) printf '%s\n' "$_dt_result" ;;
    *)                  printf 'completo\n' ;;
  esac
  return 0
}

# ---------- resolve-initial ----------
#
# Resolve o tier INICIAL do prompt de finalidade (FR-003). Existe para
# tirar a regra da prosa do command e coloca-la em codigo testavel: antes
# desta funcao, "execucao nao-interativa => cloud-public" era so uma
# instrucao em linguagem natural, e um spike headless (2026-08-15)
# mostrou um agente sobrepondo-a com raciocinio de Principio VI, gravando
# `local` a partir do briefing.
#
# `--source` e OBRIGATORIO e nao tem default: quem chama DECLARA se houve
# operador. Nao ha deteccao automatica porque nao existe sinal confiavel
# no shell — `[ -t 0 ]` e falso mesmo em sessao interativa do harness
# (o Bash tool roda sem tty), o que tornaria toda execucao "nao-interativa"
# e forcaria cloud-public sempre.
#
#   --source absent    => cloud-public SEMPRE; --answer e ignorado por
#                         completo (nem lido). E o fail-safe do FR-003.
#   --source operator  => mapeia --answer 1..4 no enum; qualquer outra
#                         coisa (vazio, fora de 1-4, lixo) => cloud-public.
#
# Consequencia deliberada: rebaixar o tier sem operador exige declarar
# `--source operator` mentindo — acao explicita, visivel no
# enforcement-log, e nao mais uma inferencia silenciosa.
_dt_cmd_resolve_initial() {
  _source=""
  _answer=""
  _saw_source=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --source) _source=${2:-}; _saw_source=1; shift 2 ;;
      --answer) _answer=${2:-}; shift 2 ;;
      *) _dt_die_usage "resolve-initial: flag desconhecida: $1" ;;
    esac
  done

  [ "$_saw_source" = 1 ] \
    || _dt_die_usage "resolve-initial: --source e obrigatorio (operator|absent)"

  case "$_source" in
    absent)
      # FR-003 literal: sem operador o tier e cloud-public, ponto. NAO
      # inferir de briefing/constitution/descricao — ver INV-4/ASI01.
      printf 'cloud-public\n'
      return 0
      ;;
    operator) : ;;
    *)
      _dt_die_usage "resolve-initial: --source aceita apenas operator|absent"
      ;;
  esac

  # CRLF: entrada pode vir de arquivo/pipe com terminador Windows — `$()`
  # NAO remove \r (mesma classe do bug corrigido no next-id em v7.5.1).
  _answer=$(printf '%s' "$_answer" | tr -d '\r\n')

  case "$_answer" in
    1) printf 'local\n' ;;
    2) printf 'internal-network\n' ;;
    3) printf 'cloud-internal\n' ;;
    4) printf 'cloud-public\n' ;;
    # Enter, vazio, fora de 1-4, texto arbitrario: default seguro.
    *) printf 'cloud-public\n' ;;
  esac
  return 0
}

# ---------- dispatch ----------

[ "$#" -gt 0 ] || _dt_die_usage "subcomando obrigatorio: get|set|gate-mode|resolve-initial"

_DT_CMD=$1
shift

case "$_DT_CMD" in
  get)             _dt_cmd_get             "$@" ;;
  set)             _dt_cmd_set             "$@" ;;
  gate-mode)       _dt_cmd_gate_mode       "$@" ;;
  resolve-initial) _dt_cmd_resolve_initial "$@" ;;
  -h|--help|help)
    printf 'delivery-tier.sh get --state-dir DIR\ndelivery-tier.sh set --state-dir DIR --value <token> [--allow-downgrade]\ndelivery-tier.sh gate-mode --gate NOME [--tier TOKEN] [--state-dir DIR]\ndelivery-tier.sh resolve-initial --source <operator|absent> [--answer RAW]\n'
    exit 0
    ;;
  *)
    _dt_die_usage "subcomando desconhecido: $_DT_CMD (validos: get|set|gate-mode|resolve-initial)"
    ;;
esac
