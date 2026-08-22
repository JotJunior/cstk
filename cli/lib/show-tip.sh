#!/bin/sh
# show-tip.sh — exibe uma dica aleatoria sobre skills do toolkit (US1/US3/US4).
#
# Implementa o mecanismo de exibicao de dicas de `cstk show-tip`. Le o catalogo
# `tips/catalog.md` (Markdown + frontmatter YAML), seleciona uma entrada via RNG
# POSIX (/dev/urandom + awk srand) e formata um Tip Block ASCII em stdout.
#
# Despachado por cli/cstk: `cstk show-tip [SKILL] [FLAGS]` -> show_tip_main "$@"
#
# POSIX sh puro. Sem bash-isms. Sem dependencias externas.
# Ferramentas base: awk, grep, od, find, printf, sed, date, basename, dirname.
#
# FR-006 — fail-silent absoluto: em modo exibicao, SEMPRE exit 0.
# OWASP A05 — injecao: valores de usuario passados via -v awk (NUNCA interpolados).
# Ref: docs/specs/_archived/show-tips/contracts/cli-show-tip.md

set -eu

# ==== Guard de sourcing (idempotencia) ====
#
# Analogamente a recall.sh: a variavel _SHOW_TIP_LOADED previne que sourcing
# multiplo (por cli/cstk ou testes) redefina funcoes ou rode codigo de topo-nivel.
# SC2317 avoided: usar exit em vez de return||exit para compatibilidade universal.
if [ -n "${_SHOW_TIP_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_SHOW_TIP_LOADED=1

# ==== Sourcing de logging compartilhado ====
#
# Quando despachado por cli/cstk, common.sh ja foi sourced. Em invocacao
# direta (testes), sourcing idempotente garante log_info/warn/error.
if [ -z "${_CSTK_COMMON_LOADED:-}" ]; then
  _st_self_dir=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd 2>/dev/null) \
    || _st_self_dir=""
  if [ -n "${CSTK_LIB:-}" ] && [ -f "$CSTK_LIB/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$CSTK_LIB/common.sh"
  elif [ -n "$_st_self_dir" ] && [ -f "$_st_self_dir/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$_st_self_dir/common.sh"
  fi
fi

# Fallback minimo de logging caso common.sh nao esteja disponivel.
if ! command -v log_warn >/dev/null 2>&1; then
  log_warn()  { printf '[warn] %s\n' "$*" >&2; }
  log_error() { printf '[error] %s\n' "$*" >&2; }
fi

# ==== Exit codes ====
#
# Modo exibicao: SEMPRE 0 (FR-006 fail-silent absoluto).
# Modo audit: 0=completo, 1=gaps, 2=uso incorreto.
SHOW_TIP_EXIT_OK=0
SHOW_TIP_EXIT_GAPS=1
SHOW_TIP_EXIT_USAGE=2

# ==== Resolucao de paths ====
#
# Determina a raiz do repositorio a partir da localizacao do script.
# Prioridade: $CSTK_REPO_ROOT (override para testes) > layout instalado
# > layout de dev (cli/lib/show-tip.sh -> raiz = cli/lib/../../).
_st_resolve_repo_root() {
  if [ -n "${CSTK_REPO_ROOT:-}" ]; then
    printf '%s\n' "$CSTK_REPO_ROOT"
    return 0
  fi
  # Quando sourced via cstk, CSTK_LIB aponta para cli/lib/; raiz = dois niveis acima.
  if [ -n "${CSTK_LIB:-}" ]; then
    _st_root=$(unset CDPATH; cd -- "$CSTK_LIB/../.." && pwd 2>/dev/null) || _st_root=""
    if [ -n "$_st_root" ]; then
      printf '%s\n' "$_st_root"
      return 0
    fi
  fi
  # Layout de dev / invocacao direta: este script esta em cli/lib/; raiz = dois niveis acima.
  # Nota: quando sourced, $0 e o script que fez o source (nao este arquivo);
  # CSTK_LIB deve estar definido nesse caso para a resolucao funcionar.
  _st_script_dir=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd 2>/dev/null) \
    || { printf '' ; return 0; }
  # Sobe dois niveis: cli/lib/ -> cli/ -> raiz (so funciona corretamente se
  # $0 e este proprio script, i.e. invocacao direta, nao via source)
  _st_root=$(cd -- "$_st_script_dir/../.." && pwd 2>/dev/null) || _st_root=""
  printf '%s\n' "$_st_root"
}

# ==== Resolucao do catalogo ====
#
# Retorna path absoluto do catalogo. Usa --catalog override se fornecido,
# senao tips/catalog.md relativo a raiz do repo.
_st_resolve_catalog() {
  # $1 = valor de --catalog (vazio se nao passado)
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  _st_root=$(_st_resolve_repo_root)
  printf '%s/tips/catalog.md\n' "$_st_root"
}

# ==== RNG POSIX ====
#
# _st_rng_pick N: retorna indice aleatorio em [0, N-1] usando /dev/urandom
# como fonte de entropia (4 bytes -> seed para awk srand). Fallback para
# date +%s quando /dev/urandom nao disponivel (ambientes restritos).
# N=0: retorna string vazia (sem divisao por zero).
# N=1: retorna 0 diretamente (sem RNG desnecessario).
_st_rng_pick() {
  _st_n="${1:-0}"

  # Guarda de N=0: catalogo vazio
  if [ "$_st_n" -eq 0 ] 2>/dev/null; then
    printf ''
    return 0
  fi

  # Guarda de N=1: unica entrada disponivel
  if [ "$_st_n" -eq 1 ] 2>/dev/null; then
    printf '0\n'
    return 0
  fi

  # Fonte primaria: /dev/urandom (POSIX, disponivel em macOS e Linux CI)
  if [ -r /dev/urandom ]; then
    _st_seed=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \t\n') \
      || _st_seed=""
    if [ -n "$_st_seed" ]; then
      printf '%s\n' "$_st_n" \
        | awk -v seed="$_st_seed" '{srand(seed); print int(rand()*$0)}'
      return 0
    fi
  fi

  # Fallback: date +%s como seed (POSIX; resolucao de 1s — aceitavel para UX)
  _st_seed_fb=$(date +%s 2>/dev/null) || _st_seed_fb=42
  printf '%s\n' "$_st_n" \
    | awk -v seed="$_st_seed_fb" '{srand(seed); print int(rand()*$0)}'
}

# ==== Parser do catalogo (maquina de estados awk) ====
#
# _st_parse_catalog CATALOG_PATH SKILL FILTER_CATEGORY
#
# Le o catalogo e imprime entradas correspondentes ao filtro.
# Saida por entrada: linhas delimitadas com prefixo de campo.
#
# Formato de saida (uma entrada por bloco separado por linha "ENTRY"):
#   ENTRY
#   SKILL:<valor>
#   CATEGORY:<valor>
#   TEXT:<valor>
#   BODY:<linha-do-corpo>
#   BODY:<linha-do-corpo>
#   ...
#
# Maquina de estados:
#   out        -> linha "---" -> frontmatter
#   frontmatter -> linha "---" -> body
#   body        -> linha "---" -> out (emite entrada se match)
#
# OWASP A05: SKILL e FILTER_CATEGORY passados via -v (NUNCA interpolados
# no programa awk). Match literal via index() em vez de regex para evitar
# metacaracteres awk nos valores de usuario.
_st_parse_catalog() {
  _st_cat_path="$1"
  _st_filter_skill="${2:-}"
  _st_filter_cat="${3:-}"

  [ -r "$_st_cat_path" ] || return 0

  awk \
    -v filter_skill="$_st_filter_skill" \
    -v filter_cat="$_st_filter_cat" \
    '
    BEGIN {
      state = "out"
      cur_skill = ""
      cur_cat   = ""
      cur_text  = ""
      body      = ""
    }

    # Linha separadora "---" (exatamente tres hifens, sem espacos)
    /^---$/ {
      if (state == "out") {
        # Inicio de nova entrada: resetar acumuladores
        state     = "frontmatter"
        cur_skill = ""
        cur_cat   = ""
        cur_text  = ""
        body      = ""
        next
      }
      if (state == "frontmatter") {
        # Transicao frontmatter -> body
        state = "body"
        next
      }
      if (state == "body") {
        # Fim de entrada: emitir se passa no filtro
        _emit_if_match()
        # Transicao direta para frontmatter da proxima entrada (nao para "out"),
        # para que as linhas skill:/category:/text: que vem a seguir sejam capturadas.
        # Se nao houver proxima entrada, state fica em frontmatter sem campos e sem body
        # e nenhuma emissao espuria ocorre (campos obrigatorios estarao vazios).
        state     = "frontmatter"
        cur_skill = ""
        cur_cat   = ""
        cur_text  = ""
        body      = ""
        next
      }
    }

    state == "frontmatter" {
      # Extrair campo skill
      if (substr($0, 1, 7) == "skill: ") {
        cur_skill = substr($0, 8)
        next
      }
      # Extrair campo category
      if (substr($0, 1, 10) == "category: ") {
        cur_cat = substr($0, 11)
        next
      }
      # Extrair campo text
      if (substr($0, 1, 6) == "text: ") {
        cur_text = substr($0, 7)
        next
      }
      next
    }

    state == "body" {
      # Acumular corpo (preservar linhas em branco e fences)
      if (body == "") {
        body = $0
      } else {
        body = body "\n" $0
      }
      next
    }

    # Linhas fora de entrada (comentarios de cabecalho etc.) -> ignorar

    function _emit_if_match(    match_skill, match_cat) {
      # Validar campos obrigatorios
      if (cur_skill == "" || cur_cat == "" || cur_text == "") return

      # Filtro por skill: match literal (OWASP A05 — sem regex de input)
      if (filter_skill != "") {
        if (cur_skill != filter_skill) return
      }

      # Filtro por categoria (raramente usado diretamente)
      if (filter_cat != "") {
        if (cur_cat != filter_cat) return
      }

      # Emitir entrada
      printf "ENTRY\n"
      printf "SKILL:%s\n", cur_skill
      printf "CATEGORY:%s\n", cur_cat
      printf "TEXT:%s\n", cur_text
      printf "BODY:%s\n", body
    }
    ' "$_st_cat_path"
}

# ==== Coleta de candidatos ====
#
# _st_collect_candidates CATALOG_PATH SKILL
#
# Retorna lista de entradas (uma por linha) como indice sequencial.
# Na pratica, escreve as entradas em linhas separadas; o caller conta.
_st_collect_candidates() {
  _st_cat_path="$1"
  _st_skill="${2:-}"
  _st_parse_catalog "$_st_cat_path" "$_st_skill" ""
}

# ==== Selecionar entrada pelo indice ====
#
# _st_pick_entry_by_idx CATALOG_PATH SKILL IDX
#
# Imprime a entrada no indice IDX (base 0) do conjunto filtrado.
# Formato de saida: 4 variaveis separadas por \n:
#   SKILL:<skill>
#   CATEGORY:<cat>
#   TEXT:<text>
#   BODY:<corpo>
_st_pick_entry_by_idx() {
  _st_cat_path="$1"
  _st_skill="${2:-}"
  _st_idx="${3:-0}"

  _st_parse_catalog "$_st_cat_path" "$_st_skill" "" \
    | awk -v target_idx="$_st_idx" '
      BEGIN { cur_idx = -1; in_entry = 0; collecting = 0 }
      /^ENTRY$/ {
        cur_idx++
        if (cur_idx == target_idx) {
          collecting = 1
        } else {
          collecting = 0
        }
        next
      }
      collecting { print }
    '
}

# ==== Mapeamento fase -> skill ====
#
# _st_phase_to_skill FASE
#
# Imprime o nome da skill mapeada para a fase, ou string vazia se nao
# mapeada (fallback aleatorio global — FR-010).
_st_phase_to_skill() {
  case "${1:-}" in
    specify)      printf 'specify\n'      ;;
    clarify)      printf 'clarify\n'      ;;
    plan)         printf 'plan\n'         ;;
    create-tasks) printf 'create-tasks\n' ;;
    execute-task) printf 'execute-task\n' ;;
    converge)     printf 'converge\n'     ;;
    review-task)  printf 'review-task\n'  ;;
    checklist)    printf 'checklist\n'    ;;
    *)            printf '\n'             ;;
  esac
}

# ==== Formatacao do Tip Block ====
#
# _st_format_tip SKILL CATEGORY TEXT BODY
#
# Emite o bloco visual ASCII em stdout. Largura fixa de 56 caracteres
# para os separadores (portavel em terminais 80 colunas). ASCII puro:
# sem ANSI, sem Unicode decorativo (CHK032).
_st_format_tip() {
  _st_tip_skill="$1"
  _st_tip_cat="$2"
  _st_tip_text="$3"
  _st_tip_body="$4"

  _st_sep_top="========================================================"
  _st_sep_mid="--------------------------------------------------------"

  printf '%s\n' "$_st_sep_top"
  printf ' Dica: skill `%s`  [%s]\n' "$_st_tip_skill" "$_st_tip_cat"
  printf '%s\n' "$_st_sep_mid"
  # Emitir texto principal identado
  printf ' %s\n' "$_st_tip_text"
  # Emitir corpo (exemplos) se presente
  if [ -n "$_st_tip_body" ]; then
    printf '\n'
    # Emitir cada linha do corpo identada (preservar linhas em branco)
    printf '%s\n' "$_st_tip_body" | while IFS= read -r _st_bline; do
      if [ -n "$_st_bline" ]; then
        printf ' %s\n' "$_st_bline"
      else
        printf '\n'
      fi
    done
  fi
  printf '%s\n' "$_st_sep_top"
}

# ==== Contagem de candidatos ====
#
# _st_count_candidates CATALOG_PATH SKILL
#
# Retorna (stdout) o numero de entradas candidatas (sempre inteiro limpo).
# grep -c retorna exit 1 quando nao encontra matches — usar subshell para
# tratar esse caso sem propagar falha; awk para garantir inteiro sem espacos.
_st_count_candidates() {
  _st_cat_path="$1"
  _st_skill="${2:-}"

  _st_parse_catalog "$_st_cat_path" "$_st_skill" "" \
    | awk '/^ENTRY$/{n++} END{print n+0}'
}

# ==== Modo exibicao ====
#
# _st_display CATALOG_PATH SKILL
#
# Seleciona e exibe uma dica. Fail-silent: stdout vazio em caso de erro.
# SKILL pode ser vazio (selecao aleatoria global) ou nome de skill.
_st_display() {
  _st_cat_path="$1"
  _st_target_skill="${2:-}"

  # Verificar existencia do catalogo (fail-silent FR-006)
  if [ ! -r "$_st_cat_path" ]; then
    return 0
  fi

  # Contar candidatos
  _st_n=$(_st_count_candidates "$_st_cat_path" "$_st_target_skill") || _st_n=0

  if [ "$_st_n" -eq 0 ]; then
    return 0
  fi

  # Selecionar indice aleatorio
  _st_idx=$(_st_rng_pick "$_st_n") || _st_idx=0
  [ -n "$_st_idx" ] || _st_idx=0

  # Extrair campos da entrada selecionada
  _st_entry=$(_st_pick_entry_by_idx "$_st_cat_path" "$_st_target_skill" "$_st_idx") \
    || _st_entry=""
  [ -n "$_st_entry" ] || return 0

  _st_tip_sk=$(printf '%s\n' "$_st_entry" | grep "^SKILL:" | sed 's/^SKILL://')
  _st_tip_cat=$(printf '%s\n' "$_st_entry" | grep "^CATEGORY:" | sed 's/^CATEGORY://')
  _st_tip_text=$(printf '%s\n' "$_st_entry" | grep "^TEXT:" | sed 's/^TEXT://')
  _st_tip_body=$(printf '%s\n' "$_st_entry" | grep "^BODY:" | sed 's/^BODY://')

  [ -n "$_st_tip_sk" ]   || return 0
  [ -n "$_st_tip_text" ] || return 0

  _st_format_tip "$_st_tip_sk" "${_st_tip_cat:-uso}" "$_st_tip_text" "$_st_tip_body"
}

# ==== Mensagem amigavel: skill sem dicas (modo explicito) ====
#
# _st_friendly_no_tips SKILL CATALOG_PATH
#
# Emite mensagem amigavel em stdout quando o usuario pediu uma skill
# explicitamente mas ela nao tem dicas no catalogo (FR-006 / dec-020).
_st_friendly_no_tips() {
  _st_req_skill="$1"
  _st_cat_path="$2"

  printf 'Sem dicas cadastradas para `%s`.\n' "$_st_req_skill"
  printf '\n'
  printf 'Skills com dicas disponiveis:\n'

  # Listar skills unicas do catalogo (OWASP A05: sem input de usuario em awk)
  if [ -r "$_st_cat_path" ]; then
    _st_parse_catalog "$_st_cat_path" "" "" \
      | grep "^SKILL:" \
      | sed 's/^SKILL://' \
      | sort -u \
      | while IFS= read -r _st_s; do
          printf '  - %s\n' "$_st_s"
        done
  fi
}

# ==== Modo audit ====
#
# _st_audit CATALOG_PATH REPO_ROOT
#
# Valida cobertura: todas as skills do universo devem ter >= 2 entradas
# com as categorias `uso` e `gotcha`. Descobre skills dinamicamente.
# Exit 0: catalogo completo. Exit 1: gaps. Exit 2: uso incorreto.
_st_audit() {
  _st_cat_path="$1"
  _st_root="$2"

  # Catalogo ausente = cobertura 0%
  if [ ! -r "$_st_cat_path" ]; then
    printf 'AUDIT FAIL: catalogo ausente: %s\n' "$_st_cat_path"
    return "$SHOW_TIP_EXIT_GAPS"
  fi

  # Descoberta dinamica do universo de skills:
  # 1. Diretorios em plugins/cstk/skills/ (cada diretorio = 1 skill)
  # 2. Arquivos SKILL.md em plugins/cstk-language-*/skills/ (perfis de
  #    linguagem relocados para plugin — claude-plugin-packaging FASE 4;
  #    dirname do arquivo = skill)
  _st_universe_file=$(mktemp)
  # Coletar universo de skills
  {
    if [ -d "$_st_root/plugins/cstk/skills" ]; then
      find "$_st_root/plugins/cstk/skills" -maxdepth 1 -mindepth 1 -type d \
        2>/dev/null \
        | while IFS= read -r _st_d; do basename -- "$_st_d"; done
    fi
    for _st_langdir in "$_st_root/plugins/"cstk-language-*/; do
      [ -d "$_st_langdir" ] || continue
      find "$_st_langdir" -name "SKILL.md" 2>/dev/null \
        | while IFS= read -r _st_f; do
            _st_dir=$(dirname -- "$_st_f")
            basename -- "$_st_dir"
          done
    done
  } | sort -u > "$_st_universe_file"

  _st_universe_count=$(awk 'END{print NR+0}' "$_st_universe_file")
  if [ "$_st_universe_count" -eq 0 ]; then
    printf 'AUDIT WARN: nenhuma skill encontrada no universo (plugins/cstk/skills/ e plugins/cstk-language-*/skills/).\n'
    rm -f "$_st_universe_file"
    return "$SHOW_TIP_EXIT_GAPS"
  fi

  # Para cada skill do universo, verificar entradas no catalogo
  _st_gaps=0
  _st_gap_list=""

  while IFS= read -r _st_sk; do
    [ -n "$_st_sk" ] || continue

    # Contar entradas totais para esta skill
    _st_total=$(_st_count_candidates "$_st_cat_path" "$_st_sk") || _st_total=0

    # Verificar presenca de categorias uso e gotcha (awk para inteiro limpo)
    _st_has_uso=$(_st_parse_catalog "$_st_cat_path" "$_st_sk" "uso" \
      | awk '/^ENTRY$/{n++} END{print n+0}')
    _st_has_gotcha=$(_st_parse_catalog "$_st_cat_path" "$_st_sk" "gotcha" \
      | awk '/^ENTRY$/{n++} END{print n+0}')

    _st_skill_ok=1
    _st_skill_issues=""

    if [ "$_st_total" -lt 2 ]; then
      _st_skill_ok=0
      _st_skill_issues="$_st_skill_issues entradas=$_st_total/<2"
    fi
    if [ "$_st_has_uso" -eq 0 ]; then
      _st_skill_ok=0
      _st_skill_issues="$_st_skill_issues categoria-uso=ausente"
    fi
    if [ "$_st_has_gotcha" -eq 0 ]; then
      _st_skill_ok=0
      _st_skill_issues="$_st_skill_issues categoria-gotcha=ausente"
    fi

    if [ "$_st_skill_ok" -eq 0 ]; then
      _st_gaps=$((_st_gaps + 1))
      printf 'GAP: %s [%s]\n' "$_st_sk" "$_st_skill_issues"
    fi
  done < "$_st_universe_file"

  rm -f "$_st_universe_file"

  if [ "$_st_gaps" -eq 0 ]; then
    printf 'AUDIT OK: catalogo completo (%s skills cobertas).\n' "$_st_universe_count"
    return "$SHOW_TIP_EXIT_OK"
  else
    printf 'AUDIT FAIL: %s skill(s) com cobertura insuficiente.\n' "$_st_gaps"
    return "$SHOW_TIP_EXIT_GAPS"
  fi
}

# ==== Mensagem de uso ====
_st_usage() {
  cat <<'USAGE'
uso: cstk show-tip [SKILL] [--phase FASE] [--audit] [--catalog PATH] [-h]

Exibe uma dica sobre uma skill do toolkit.

ARGUMENTOS:
  SKILL           nome da skill alvo (sem dicas: mensagem amigavel)

FLAGS:
  --phase FASE    fase corrente do pipeline (specify|clarify|plan|
                  create-tasks|execute-task|converge|review-task|checklist)
  --audit         valida cobertura do catalogo (nao exibe dica)
  --catalog PATH  override do caminho do catalogo (padrao: tips/catalog.md)
  -h, --help      esta mensagem

EXIT CODES (modo exibicao): sempre 0 (fail-silent FR-006)
EXIT CODES (modo audit):    0=completo  1=gaps  2=uso incorreto

USAGE
}

# ==== Entrypoint principal ====
#
# show_tip_main "$@" — despachado por cli/cstk.
# Pode ser sourced (cstk show-tip) ou invocado diretamente (sh show-tip.sh).
show_tip_main() {
  # --- Parsing de argumentos ---
  _st_skill=""
  _st_phase=""
  _st_audit=0
  _st_catalog_override=""
  _st_explicit_skill=0  # 1 se SKILL foi dado explicitamente pelo usuario

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        _st_usage
        return "$SHOW_TIP_EXIT_OK"
        ;;
      --phase)
        if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
          printf 'show-tip: --phase requer argumento\n' >&2
          return "$SHOW_TIP_EXIT_USAGE"
        fi
        _st_phase="$2"
        shift 2
        ;;
      --audit)
        _st_audit=1
        shift
        ;;
      --catalog)
        if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
          printf 'show-tip: --catalog requer argumento\n' >&2
          return "$SHOW_TIP_EXIT_USAGE"
        fi
        _st_catalog_override="$2"
        shift 2
        ;;
      --*)
        printf 'show-tip: flag desconhecida: %s\n' "$1" >&2
        return "$SHOW_TIP_EXIT_USAGE"
        ;;
      *)
        # Argumento posicional: nome da skill
        _st_skill="$1"
        _st_explicit_skill=1
        shift
        ;;
    esac
  done

  # --- Resolver paths ---
  _st_catalog=$(_st_resolve_catalog "$_st_catalog_override")
  _st_root=$(_st_resolve_repo_root)

  # --- Modo audit ---
  if [ "$_st_audit" -eq 1 ]; then
    _st_audit "$_st_catalog" "$_st_root"
    return "$?"
  fi

  # --- Modo exibicao (fail-silent absoluto FR-006) ---

  # Determinar skill alvo
  _st_target=""

  if [ -n "$_st_skill" ]; then
    # SKILL explicitamente fornecido: prevalece sobre --phase
    _st_target="$_st_skill"
  elif [ -n "$_st_phase" ]; then
    # --phase: mapear para skill
    _st_target=$(_st_phase_to_skill "$_st_phase")
  fi
  # Se _st_target ainda vazio: selecao aleatoria global (FR-010)

  # Verificar existencia do catalogo
  if [ ! -r "$_st_catalog" ]; then
    # Fail-silent: stdout vazio, exit 0
    return "$SHOW_TIP_EXIT_OK"
  fi

  # Caso especial: SKILL explicita, verificar se ha dicas
  if [ -n "$_st_target" ] && [ "$_st_explicit_skill" -eq 1 ]; then
    _st_n=$(_st_count_candidates "$_st_catalog" "$_st_target") || _st_n=0
    if [ "$_st_n" -eq 0 ]; then
      # Modo explicito sem dicas: mensagem amigavel (dec-020)
      _st_friendly_no_tips "$_st_target" "$_st_catalog"
      return "$SHOW_TIP_EXIT_OK"
    fi
  fi

  # Exibir dica (fail-silent interno: _st_display nunca propaga erro)
  _st_display "$_st_catalog" "$_st_target" || true

  return "$SHOW_TIP_EXIT_OK"
}

# ==== Invocacao direta (nao sourced) ====
#
# Quando executado como `sh cli/lib/show-tip.sh ...` (nao via cstk),
# chama show_tip_main com os argumentos recebidos e propaga o exit code.
# Detectado pelo pattern: $0 contem show-tip (nao e "sh" ou "dash" puro).
_st_self=$(basename -- "${0:-sh}")
case "$_st_self" in
  show-tip.sh|show-tip)
    # Desabilitar set -e localmente para capturar exit code de --audit (pode ser 1/2)
    # sem que o shell aborte. O exit propaga o codigo correto para o chamador.
    set +e
    show_tip_main "$@"
    _st_exit_code="$?"
    set -e
    exit "$_st_exit_code"
    ;;
esac
