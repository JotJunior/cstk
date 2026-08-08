#!/bin/sh
# guard-hooks-status.sh — verifica se os hooks 00c estao provisionados no
# projeto-alvo (READ-ONLY, nunca escreve nada).
#
# PROBLEMA QUE ISTO RESOLVE
# -------------------------
# Os tres hooks do runtime 00c so chegam a um projeto-alvo via
# `apply_guard_hooks()` (cli/lib/hooks.sh), que roda EXCLUSIVAMENTE quando
# `cstk install`/`cstk update` e invocado com `--scope project` E com
# `agente-00c-runtime` na selecao. O default de ambos os comandos e
# `--scope global`, que pula o provisionamento por FR-009c.
#
# Consequencia observada em campo: projeto com 35 ondas 00c executadas e
# ZERO hooks em .claude/hooks/ —
#   - pretooluse-bash-guard.sh ausente  => a guarda fail-closed de Bash
#     (enforced-guards US1) nunca foi enforced; a execucao inteira rodou
#     sem a protecao que a doc afirma estar ativa. E o item GRAVE.
#   - posttooluse-tool-call-tick.sh ausente => tool_calls fica 0 em todas
#     as ondas (proxy de orcamento inutilizado).
#   - posttooluse-agent-usage.sh ausente => agent_usage/tokens ficam null.
#
# Como o `cstk install` roda no repo do cstk e nao no projeto-alvo, nao ha
# momento natural para avisar o operador la. O ponto de checagem correto e
# o inicio da execucao 00c, que ja esta DENTRO do projeto-alvo — dai este
# script, consumido pelos commands /agente-00c e /feature-00c.
#
# SEGUNDO MODO DE FALHA DE CAMPO: a copia STALE
# ---------------------------------------------
# `present + registered` NAO implica funcional. A copia em
# <PAP>/.claude/hooks/ e um SNAPSHOT tirado no dia do provisionamento; o
# catalogo (~/.claude/skills/agente-00c-runtime/hooks/) segue evoluindo e
# NADA reconcilia os dois — `cstk update` so reprovisiona quando invocado
# com `--scope project` E com agente-00c-runtime na selecao (default e
# global), e roda no repo do cstk, nao no projeto-alvo.
#
# Consequencia observada em campo (03/ago/2026): apos o cutover
# state.json -> state.db (features state-db-runtime-parity/hooks-db-parity),
# projetos seguiram com a copia de jul/2026 do posttooluse-tool-call-tick.sh,
# que detectava execucao ativa lendo SO `state.json`. Com backend sqlite o
# hook nao enxerga mais a execucao, sai 0 mudo, e o sidecar
# tool-call-ticks.log nunca e criado => tool_calls=0 em TODAS as ondas de
# 2 projetos. Falha dupla: `check` dizia "3/3 ativos" e `tick-mode` dizia
# "hook", entao o orquestrador tambem nao tickava na mao.
#
# Dai a 3a dimensao (`current|stale|unknown`) e o rebaixamento do tick-mode
# quando a copia e cega ao backend em uso.
#
# Subcomandos:
#   guard-hooks-status.sh check --projeto-alvo-path PATH [--quiet]
#       [--include-loose-usage] [--verify-registration]
#       — stdout: uma linha TSV por hook (4 colunas; 5 com
#         --verify-registration):
#             <arquivo>\t<present|missing>\t<registered|unregistered>\t<current|stale|unknown>[\t<canonical|divergent|indeterminate>]
#         "registered" = o basename aparece em <PAP>/.claude/settings.json
#         (o hook so roda de fato se estiver copiado E registrado).
#         "current"/"stale" = comparacao byte-a-byte (cmp) da copia do
#         projeto com a do catalogo; "unknown" = hook ausente ou catalogo
#         irresolvivel (nao e veredito, nao reprova).
#       — stderr: diagnostico + comando de remediacao (suprimido por --quiet).
#       — exit 0 se os 3 estao present+registered+(current|unknown), e (com
#         --verify-registration) nenhum "divergent"; 1 caso contrario
#         (inclui stale e divergent).
#
#       --include-loose-usage (feature cstk-setup, FASE 2.1, FR-002/FR-008):
#         extensao ADITIVA — acrescenta uma 4a linha TSV para
#         posttooluse-loose-usage.sh (mesmo formato de 4 colunas; NUNCA
#         ganha a 5a coluna mesmo com --verify-registration — ver abaixo).
#         NAO altera o exit code (hook opt-in, ausencia nunca e anomalia).
#         Sem a flag, saida byte-a-byte identica a atual. Runtime instalado
#         anterior a esta extensao rejeita a flag em _gh_die_usage com
#         exit 2 — o consumidor MUST tratar como
#         loose_usage_status=indeterminate, nunca como falha da area.
#
#       --verify-registration (feature cstk-setup, FASE 2.2, FR-016):
#         extensao ADITIVA — acrescenta uma 5a coluna TSV
#         (canonical|divergent|indeterminate) a cada hook de _GH_HOOKS,
#         verificando que o "command" registrado em settings.json e a
#         forma canonica do catalogo (fecha o caso de linha-isca
#         decorativa, achado SEC-01). "divergent" muda o exit para 1.
#         Sem a flag, saida e exit identicos aos atuais. Runtime instalado
#         anterior rejeita a flag com exit 2 — o consumidor MUST tratar
#         como indeterminate (nunca divergent, nunca configured — I5).
#         SEMPRE invocada ISOLADA da chamada baseline (achado SEC-03): nunca
#         combine as duas flags com a baseline numa unica invocacao — um
#         runtime antigo que rejeita qualquer uma delas perderia tambem o
#         veredito basico que ele SABE responder.
#
#   guard-hooks-status.sh tick-mode --projeto-alvo-path PATH
#       — stdout: "hook" se posttooluse-tool-call-tick.sh esta ativo
#         (present+registered) E capaz de enxergar o backend em uso; senao
#         "manual".
#         Consumido pelo orquestrador para decidir se chama
#         `state-ondas.sh tool-call-tick` na mao. A regra "NAO tickar
#         manualmente" so vale quando o hook existe — sem esta checagem o
#         default virava "nao ticka" e a metrica zerava em silencio.
#         Rebaixa para "manual" quando a copia do projeto e CEGA A BACKEND
#         (nao referencia _hook-active-exec.sh, i.e. anterior a
#         hooks-db-parity) E ha `state.db` num state-dir do projeto: nesse
#         par exato o hook nunca ticka, entao o orquestrador precisa tickar.
#         O rebaixamento e condicionado ao par (cego + sqlite) de proposito:
#         copia cega sobre backend JSON SEGUE funcionando, e devolver
#         "manual" ali produziria contagem DUPLA (hook + tick manual).
#       — exit 0 sempre (0 = consulta respondida, nao veredito).
#
# Override do catalogo (so para teste/diagnostico):
#   CSTK_HOOKS_CATALOG_DIR=<dir> — diretorio com as copias de referencia.
#   Sem ele: sibling `<script_dir>/../hooks`, depois
#   `${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/hooks` (via
#   `_resolve-root.sh`, Ordem A — feature claude-plugin-packaging, task
#   3.2.5), depois `$HOME/.claude/skills/agente-00c-runtime/hooks`.
#
# Exit codes:
#   0  check: tudo provisionado e atual | tick-mode: consulta respondida
#   1  check: pelo menos um hook ausente, nao-registrado ou stale
#   2  uso incorreto
#
# READ-ONLY por construcao: nao copia hook, nao edita settings.json, nao
# toca state.json. Provisionar e trabalho do `cstk install --scope project`
# (unica fonte da regra); reimplementar a copia aqui duplicaria a regra em
# dois lugares — mesmo motivo pelo qual o hook PreToolUse delega a decisao
# a bash-guard.sh em vez de reimplementa-la.
#
# POSIX sh puro. Sem jq, sem sqlite3, sem rede.

set -eu

_GH_NAME="guard-hooks-status"

# Bootstrap: localizar+sourcear `_resolve-root.sh` (feature
# claude-plugin-packaging, task 3.2.5). Este script ja vive em
# `scripts/agente-00c-runtime` — sibling de `_resolve-root.sh` e o proprio
# diretorio (sem `../scripts`). Ordem A (CLI comum) — plugin/classico
# resolvidos por `resolve_runtime_root` (default, sem `strict`) dentro de
# `_gh_catalog_hook`; este bootstrap so localiza o ARQUIVO do helper.
_GH_RR_SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || _GH_RR_SELF_DIR=""
_gh_rr_helper=""
if [ -n "$_GH_RR_SELF_DIR" ] && [ -r "$_GH_RR_SELF_DIR/_resolve-root.sh" ]; then
  _gh_rr_helper="$_GH_RR_SELF_DIR/_resolve-root.sh"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _gh_rr_helper="${CLAUDE_PLUGIN_ROOT}/skills/agente-00c-runtime/scripts/_resolve-root.sh"
elif [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh" ]; then
  _gh_rr_helper="$HOME/.claude/skills/agente-00c-runtime/scripts/_resolve-root.sh"
fi
if [ -n "$_gh_rr_helper" ]; then
  # shellcheck disable=SC1090 # caminho resolvido dinamicamente pela cadeia de candidatos acima
  . "$_gh_rr_helper"
fi

_gh_die_usage() { printf '%s: %s\n' "$_GH_NAME" "$1" >&2; exit 2; }
_gh_err()       { printf '%s: %s\n' "$_GH_NAME" "$1" >&2; }

# Os 3 hooks provisionados por apply_guard_hooks(). Ordem = a do
# settings.snippet.json (guard primeiro, metricas depois).
_GH_HOOKS='pretooluse-bash-guard.sh
posttooluse-tool-call-tick.sh
posttooluse-agent-usage.sh'

# _gh_present PAP HOOK -> 0 se o arquivo existe e e executavel
_gh_present() {
  [ -f "$1/.claude/hooks/$2" ] && [ -x "$1/.claude/hooks/$2" ]
}

# _gh_registered PAP HOOK -> 0 se o basename aparece no settings.json.
# Busca textual (grep -F) em vez de parse: o hook e registrado como
# fragmento de linha de comando ("$CLAUDE_PROJECT_DIR"/.claude/hooks/X.sh),
# entao a presenca do basename e condicao necessaria e suficiente na
# pratica — e mantem o script sem dependencia de jq (que pode faltar
# justamente no projeto-alvo mal provisionado que estamos diagnosticando).
_gh_registered() {
  _gh_settings="$1/.claude/settings.json"
  [ -f "$_gh_settings" ] || return 1
  grep -Fq -- "$2" "$_gh_settings" 2>/dev/null
}

# _gh_self_dir -> diretorio do proprio script (vazio se irresolvivel).
_gh_self_dir() {
  (CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || printf ''
}

# _gh_catalog_hook HOOK -> ecoa o path da copia de referencia do catalogo,
# ou nada (exit 1) se irresolvivel. Ordem: override de teste, sibling do
# proprio script (<catalog>/skills/agente-00c-runtime/scripts/..), $HOME.
_gh_catalog_hook() {
  _gh_ch_h=$1
  if [ -n "${CSTK_HOOKS_CATALOG_DIR:-}" ] && [ -r "$CSTK_HOOKS_CATALOG_DIR/$_gh_ch_h" ]; then
    printf '%s' "$CSTK_HOOKS_CATALOG_DIR/$_gh_ch_h"
    return 0
  fi
  _gh_ch_self=$(_gh_self_dir)
  if [ -n "$_gh_ch_self" ] && [ -r "$_gh_ch_self/../hooks/$_gh_ch_h" ]; then
    printf '%s' "$_gh_ch_self/../hooks/$_gh_ch_h"
    return 0
  fi
  # Plugin/classico (Ordem A, CLI comum) via helper compartilhado (feature
  # claude-plugin-packaging, task 3.2.5).
  if _gh_ch_root=$(resolve_runtime_root 2>/dev/null) && [ -n "$_gh_ch_root" ] \
     && [ -r "$_gh_ch_root/hooks/$_gh_ch_h" ]; then
    printf '%s' "$_gh_ch_root/hooks/$_gh_ch_h"
    return 0
  fi
  return 1
}

# _gh_freshness PAP HOOK -> "current" | "stale" | "unknown".
# "unknown" (nao reprova) quando o hook nao esta no projeto ou quando nao
# ha copia de catalogo com que comparar — na duvida NAO se acusa drift.
_gh_freshness() {
  _gh_fr_proj="$1/.claude/hooks/$2"
  [ -f "$_gh_fr_proj" ] || { printf 'unknown'; return 0; }
  # Sem `cmp` no PATH nao ha como comparar — "unknown", nunca "stale"
  # (acusar drift sem ter comparado seria inventar veredito).
  command -v cmp >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  if _gh_fr_cat=$(_gh_catalog_hook "$2"); then
    if cmp -s -- "$_gh_fr_proj" "$_gh_fr_cat"; then
      printf 'current'
    else
      printf 'stale'
    fi
  else
    printf 'unknown'
  fi
  return 0
}

# _gh_has_state_db PAP -> 0 se existe `state.db` em algum state-dir 00c do
# projeto (agente-00c-state/ ou feature-00c-state/*/). Builtins puros.
_gh_has_state_db() {
  [ -f "$1/.claude/agente-00c-state/state.db" ] && return 0
  _gh_sd_root="$1/.claude/feature-00c-state"
  if [ -d "$_gh_sd_root" ]; then
    for _gh_sd_d in "$_gh_sd_root"/*/; do
      [ -d "$_gh_sd_d" ] || continue
      [ -f "${_gh_sd_d}state.db" ] && return 0
    done
  fi
  return 1
}

# _gh_backend_blind PAP HOOK -> 0 se a copia do projeto NAO referencia
# _hook-active-exec.sh, i.e. e anterior a hooks-db-parity e so sabe ler
# `state.json` (cega ao backend sqlite).
_gh_backend_blind() {
  _gh_bb_f="$1/.claude/hooks/$2"
  [ -f "$_gh_bb_f" ] || return 1
  grep -Fq -- "_hook-active-exec.sh" "$_gh_bb_f" 2>/dev/null && return 1
  return 0
}

# _gh_verify_registration PAP HOOK -> "canonical" | "divergent" | "indeterminate"
# (feature cstk-setup, FASE 2.2, FR-016). Extensao aditiva consumida via
# `check --verify-registration`. Regra textual (achado SEC-01): toda linha
# do settings.json que contenha o basename do hook MUST tambem conter o
# fragmento canonico (a forma literal do snippet do catalogo,
# "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/<basename>") E o token literal
# "command" NA MESMA LINHA — senao "divergent". Isso fecha o caso de uma
# linha-isca decorativa (ex.: "description") que cite basename+fragmento
# canonico sem ser a atribuicao "command" de fato.
# "indeterminate" (nunca reprova, nunca vira "canonical" por omissao):
#   - settings.json ausente;
#   - hook nao mencionado em nenhuma linha (nao registrado);
#   - layout minificado numa unica linha fisica (impede atribuicao por
#     linha; ver "Limite textual declarado" em contracts/cli-setup.md §2.3).
# Read-only, POSIX puro (sem jq — mesma restricao de _gh_registered).
_gh_verify_registration() {
  _gh_vr_pap="$1"
  _gh_vr_hook="$2"
  _gh_vr_settings="$_gh_vr_pap/.claude/settings.json"

  [ -f "$_gh_vr_settings" ] || { printf 'indeterminate'; return 0; }

  # Layout minificado (uma unica linha fisica) impede atribuicao por linha.
  _gh_vr_nr=$(awk 'END{print NR}' "$_gh_vr_settings" 2>/dev/null || printf '0')
  case "$_gh_vr_nr" in '' | 0 | 1) printf 'indeterminate'; return 0 ;; esac

  _gh_vr_canonical="\\\"\$CLAUDE_PROJECT_DIR\\\"/.claude/hooks/$_gh_vr_hook"
  _gh_vr_matched=0
  _gh_vr_all_ok=1
  while IFS= read -r _gh_vr_line; do
    [ -n "$_gh_vr_line" ] || continue
    _gh_vr_matched=1
    _gh_vr_has_cmd=0
    _gh_vr_has_canon=0
    case "$_gh_vr_line" in *'"command"'*) _gh_vr_has_cmd=1 ;; esac
    case "$_gh_vr_line" in *"$_gh_vr_canonical"*) _gh_vr_has_canon=1 ;; esac
    if [ "$_gh_vr_has_cmd" = 0 ] || [ "$_gh_vr_has_canon" = 0 ]; then
      _gh_vr_all_ok=0
    fi
  done <<GHVR
$(grep -F -- "$_gh_vr_hook" "$_gh_vr_settings" 2>/dev/null)
GHVR

  if [ "$_gh_vr_matched" -eq 0 ]; then
    printf 'indeterminate'
    return 0
  fi
  if [ "$_gh_vr_all_ok" -eq 1 ]; then
    printf 'canonical'
  else
    printf 'divergent'
  fi
  return 0
}

_gh_cmd_check() {
  _pap=""
  _quiet=0
  _include_loose=0
  _verify_reg=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path)     _pap=$2; shift 2 ;;
      --quiet)                 _quiet=1; shift ;;
      --include-loose-usage)   _include_loose=1; shift ;;
      --verify-registration)   _verify_reg=1; shift ;;
      *) _gh_die_usage "check: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ] || _gh_die_usage "check: --projeto-alvo-path obrigatorio"
  [ -d "$_pap" ] || _gh_die_usage "check: --projeto-alvo-path nao e diretorio: $_pap"

  _missing=0
  _stale=0
  _divergent=0
  _guard_missing=0
  _guard_stale=0
  _guard_divergent=0
  for _h in $_GH_HOOKS; do
    if _gh_present "$_pap" "$_h"; then
      _st_file="present"
    else
      _st_file="missing"
    fi
    if _gh_registered "$_pap" "$_h"; then
      _st_reg="registered"
    else
      _st_reg="unregistered"
    fi
    _st_fresh=$(_gh_freshness "$_pap" "$_h")
    if [ "$_verify_reg" = 1 ]; then
      _st_verify=$(_gh_verify_registration "$_pap" "$_h")
      printf '%s\t%s\t%s\t%s\t%s\n' "$_h" "$_st_file" "$_st_reg" "$_st_fresh" "$_st_verify"
    else
      printf '%s\t%s\t%s\t%s\n' "$_h" "$_st_file" "$_st_reg" "$_st_fresh"
    fi
    if [ "$_st_file" != "present" ] || [ "$_st_reg" != "registered" ]; then
      _missing=$((_missing + 1))
      [ "$_h" = "pretooluse-bash-guard.sh" ] && _guard_missing=1
    elif [ "$_st_fresh" = stale ]; then
      # So conta como stale o hook que de fato rodaria (present+registered);
      # hook ausente ja esta contabilizado em _missing.
      _stale=$((_stale + 1))
      [ "$_h" = "pretooluse-bash-guard.sh" ] && _guard_stale=1
    fi
    if [ "$_verify_reg" = 1 ] && [ "$_st_verify" = divergent ]; then
      _divergent=$((_divergent + 1))
      [ "$_h" = "pretooluse-bash-guard.sh" ] && _guard_divergent=1
    fi
  done

  # --include-loose-usage: 4a linha aditiva para o hook opt-in. NUNCA soma
  # a _missing/_stale/_divergent — o hook e opt-in, sua ausencia jamais e
  # anomalia; o exit continua derivado apenas dos 3 hooks de _GH_HOOKS.
  if [ "$_include_loose" = 1 ]; then
    _lh="posttooluse-loose-usage.sh"
    if _gh_present "$_pap" "$_lh"; then
      _lst_file="present"
    else
      _lst_file="missing"
    fi
    if _gh_registered "$_pap" "$_lh"; then
      _lst_reg="registered"
    else
      _lst_reg="unregistered"
    fi
    _lst_fresh=$(_gh_freshness "$_pap" "$_lh")
    if [ "$_verify_reg" = 1 ]; then
      _lst_verify=$(_gh_verify_registration "$_pap" "$_lh")
      printf '%s\t%s\t%s\t%s\t%s\n' "$_lh" "$_lst_file" "$_lst_reg" "$_lst_fresh" "$_lst_verify"
    else
      printf '%s\t%s\t%s\t%s\n' "$_lh" "$_lst_file" "$_lst_reg" "$_lst_fresh"
    fi
  fi

  [ "$_missing" -eq 0 ] && [ "$_stale" -eq 0 ] && [ "$_divergent" -eq 0 ] && return 0

  if [ "$_quiet" = 0 ]; then
    if [ "$_missing" -gt 0 ]; then
      _gh_err "$_missing de 3 hooks 00c NAO estao ativos em $_pap/.claude/"
    fi
    if [ "$_stale" -gt 0 ]; then
      _gh_err "$_stale de 3 hooks 00c estao STALE em $_pap/.claude/hooks/ (copia diverge do catalogo)"
    fi
    if [ "$_divergent" -gt 0 ]; then
      _gh_err "$_divergent de 3 hooks 00c estao com registro DIVERGENTE (settings.json aponta para outro comando)"
    fi
    if [ "$_guard_missing" = 1 ]; then
      _gh_err "ATENCAO: pretooluse-bash-guard.sh inativo — a guarda fail-closed de Bash NAO esta enforced nesta execucao."
    fi
    if [ "$_guard_stale" = 1 ]; then
      _gh_err "ATENCAO: pretooluse-bash-guard.sh STALE — a guarda roda com regras de uma versao anterior do catalogo."
    fi
    if [ "$_guard_divergent" = 1 ]; then
      _gh_err "ATENCAO: pretooluse-bash-guard.sh com registro DIVERGENTE — o \"command\" registrado nao aponta para a copia canonica."
    fi
    _gh_err "Remediacao (so os hooks; rode uma vez):"
    _gh_err "  cstk hooks install --project-path $_pap"
    _gh_err "Alternativa (tambem duplica skill+commands+agents no repo):"
    _gh_err "  cd $_pap && cstk install --scope project agente-00c-runtime"
    _gh_err "Sem isso: tool_calls fica 0 e agent_usage fica null em todas as ondas."
  fi
  return 1
}

_gh_cmd_tick_mode() {
  _pap=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path) _pap=$2; shift 2 ;;
      *) _gh_die_usage "tick-mode: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ] || _gh_die_usage "tick-mode: --projeto-alvo-path obrigatorio"

  if ! _gh_present "$_pap" "posttooluse-tool-call-tick.sh" \
     || ! _gh_registered "$_pap" "posttooluse-tool-call-tick.sh"; then
    printf 'manual\n'
    return 0
  fi

  # Ativo mas CEGO ao backend em uso: copia anterior a hooks-db-parity (so
  # le state.json) num projeto que ja tem state.db. Nesse par o hook nunca
  # ticka — rebaixa para manual em vez de zerar a metrica em silencio.
  # Fora desse par (copia cega + backend JSON) o hook funciona: devolver
  # "manual" ali produziria contagem DUPLA.
  if _gh_backend_blind "$_pap" "posttooluse-tool-call-tick.sh" \
     && _gh_has_state_db "$_pap"; then
    printf 'manual\n'
    return 0
  fi

  printf 'hook\n'
  return 0
}

# ---------- dispatch ----------

[ "$#" -gt 0 ] || _gh_die_usage "subcomando obrigatorio: check|tick-mode"

_gh_sub=$1
shift
case "$_gh_sub" in
  check)     _gh_cmd_check "$@" ;;
  tick-mode) _gh_cmd_tick_mode "$@" ;;
  -h|--help)
    cat >&2 <<'HELP'
guard-hooks-status.sh — hooks 00c provisionados no projeto-alvo? (READ-ONLY)

USO:
  guard-hooks-status.sh check     --projeto-alvo-path PATH [--quiet]
                                   [--include-loose-usage] [--verify-registration]
  guard-hooks-status.sh tick-mode --projeto-alvo-path PATH

check     TSV <hook>\t<present|missing>\t<registered|unregistered>\t<current|stale|unknown>;
          exit 0 se os 3 ativos E atuais, 1 caso contrario.
          --include-loose-usage acrescenta 4a linha (posttooluse-loose-usage.sh),
          nao afeta o exit. --verify-registration acrescenta 5a coluna
          (canonical|divergent|indeterminate); "divergent" muda exit p/ 1.
          Invoque cada flag SEPARADA da chamada baseline (nunca combinadas).
tick-mode "hook" ou "manual" — o orquestrador so ticka na mao em "manual".
          "manual" tambem quando a copia do hook e cega a backend (pre
          hooks-db-parity) e o projeto ja usa state.db.

Remediacao quando faltam ou estao stale:
  cstk hooks install --project-path PATH
HELP
    exit 2
    ;;
  *) _gh_die_usage "subcomando desconhecido: $_gh_sub" ;;
esac
