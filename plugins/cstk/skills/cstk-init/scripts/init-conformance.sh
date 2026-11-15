#!/bin/sh
# init-conformance.sh — relatorio de conformidade de briefing/constitution/specs com o
# padrao vigente da skill cstk-init (feature cstk-init, tarefa 4.5).
#
# Contrato: SKILL.md §7 (revisao); regras CR-NNN em references/conformance-rules.md.
#
#   init-conformance.sh check --root <dir> --catalog-root <dir-de-skills>
#
# `--catalog-root` e o diretorio que contem `briefing/`, `constitution/` e `specify/` da
# MESMA raiz de catalogo da skill; os titulos exigidos sao LIDOS dos templates instalados,
# nunca embutidos neste script.
#
# stdout (um achado por linha): <artifact><TAB><rule><TAB><detail><TAB><proposal>
#   rule: missing-section (derivada de template) | CR-001..CR-008 (catalogo nomeado)
#   proposal: add-section | migrate-path | fix-footer | add-principle | add-delta-section | manual
# linha final: STATUS<TAB>conformant|divergent
#   `conformant` SO quando nada foi avaliado como divergente E nada foi pulado: artefato que existe
#   mas NAO pode ser avaliado (symlink que escapa da raiz, arquivo ilegivel, diretorio de spec
#   symlink) vira CR-008 (`manual`) e o STATUS e `divergent` — "nao avaliado" nunca aparece como
#   conforme.
# exit: 0 (com ou sem divergencias) | 1 raiz inexistente/ilegivel | 2 uso |
#       4 template de irma ausente (a mensagem cita o caminho e `cstk install`).
#
# SOMENTE LEITURA: o script nunca escreve no projeto-alvo (nem arquivo temporario); o
# conteudo dos artefatos e DADO hostil — so e lido com `read -r` e comparado, nunca
# executado nem interpolado em comando. Artefato cujo caminho passa por symlink que escapa
# da raiz nao e lido (aviso em stderr + achado CR-008).
#
# Artefatos avaliados:
#   briefing      docs/briefing.md (canonico) | docs/01-briefing-discovery/briefing.md (legado)
#   constitution  docs/constitution.md
#   spec          docs/specs/<short>/spec.md (exceto `_*` e `current`)

set -eu
LC_ALL=C
export LC_ALL

TAB=$(printf '\t')
CR=$(printf '\r')

BRIEFING_LEGACY="docs/01-briefing-discovery/briefing.md"
BRIEFING_CANON="docs/briefing.md"

_usage() {
  cat >&2 <<'EOF'
uso:
  init-conformance.sh check --root <dir> --catalog-root <dir-de-skills>
EOF
}

_die_usage() {
  printf 'init-conformance: %s\n' "$1" >&2
  _usage
  exit 2
}

_printable() {
  printf '%s' "$1" | tr '\001-\037\177' '?'
}

DIV_COUNT=0

# _div <artifact> <rule> <detail> <proposal>
_div() {
  DIV_COUNT=$((DIV_COUNT + 1))
  printf '%s\t%s\t%s\t%s\n' "$(_printable "$1")" "$2" "$(_printable "$3")" "$4"
}

# ---------------------------------------------------------------- leitura segura

# _resolve_link <abs-root> <link> — imprime: file | dir | dangling | escape.
_resolve_link() {
  _rl_root=$1
  _rl_cur=$2
  command -v readlink >/dev/null 2>&1 || { printf 'escape'; return 0; }
  _rl_n=0
  while [ -L "$_rl_cur" ]; do
    _rl_n=$((_rl_n + 1))
    [ "$_rl_n" -le 40 ] || { printf 'escape'; return 0; }
    _rl_t=$(readlink -- "$_rl_cur" 2>/dev/null) || { printf 'escape'; return 0; }
    case "$_rl_t" in
      /*) _rl_cur=$_rl_t ;;
      *) _rl_cur="$(dirname -- "$_rl_cur")/$_rl_t" ;;
    esac
  done
  if [ -d "$_rl_cur" ]; then
    _rl_full=$(cd -P -- "$_rl_cur" 2>/dev/null && pwd -P) || { printf 'escape'; return 0; }
    _rl_kind=dir
  else
    _rl_pdir=$(cd -P -- "$(dirname -- "$_rl_cur")" 2>/dev/null && pwd -P) || { printf 'escape'; return 0; }
    _rl_full="$_rl_pdir/$(basename -- "$_rl_cur")"
    if [ -e "$_rl_cur" ]; then _rl_kind=file; else _rl_kind=dangling; fi
  fi
  case "$_rl_full" in
    "$_rl_root"|"$_rl_root"/*) printf '%s' "$_rl_kind" ;;
    *) printf 'escape' ;;
  esac
  return 0
}

# _readable_artifact <rel> — 0 se e arquivo regular legivel e nenhum componente do caminho
# e symlink que escapa da raiz; 1 se simplesmente nao existe; 2 se existe mas nao e seguro
# (aviso em stderr); 3 se existe mas nao e arquivo regular legivel (nao avaliado).
_readable_artifact() {
  _ra_cur=$ROOT_P
  _ra_oldifs=$IFS
  IFS=/
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  IFS=$_ra_oldifs
  for _ra_c in "$@"; do
    _ra_cur="$_ra_cur/$_ra_c"
    if [ -L "$_ra_cur" ]; then
      _ra_k=$(_resolve_link "$ROOT_P" "$_ra_cur")
      if [ "$_ra_k" = escape ]; then
        printf 'init-conformance: caminho com symlink que escapa da raiz, ignorado: %s\n' \
          "$(_printable "${_ra_cur#"$ROOT_P"/}")" >&2
        return 2
      fi
    fi
  done
  [ -e "$_ra_cur" ] || return 1
  if [ ! -f "$_ra_cur" ] || [ ! -r "$_ra_cur" ]; then
    printf 'init-conformance: artefato existe mas nao e arquivo regular legivel, nao avaliado: %s\n' \
      "$(_printable "${_ra_cur#"$ROOT_P"/}")" >&2
    return 3
  fi
  return 0
}

# _not_evaluated <rel> <rc> — registra CR-008 quando _readable_artifact devolveu 2 ou 3
# (artefato existente que NAO foi avaliado); rc 0/1 nao geram achado.
_not_evaluated() {
  case "$2" in
    2) _div "$1" CR-008 "artefato nao avaliado: caminho com symlink que escapa da raiz (nao lido)" manual ;;
    3) _div "$1" CR-008 "artefato nao avaliado: existe mas nao e arquivo regular legivel" manual ;;
  esac
}

# ---------------------------------------------------------------- titulos e templates

# _template_headings <template> <niveis> — titulos de nivel em <niveis> (ex: "2" ou "23")
# sem placeholder (`[`/`<`), fora de bloco de codigo, um por linha.
_template_headings() {
  _th_fence=0
  while IFS= read -r _th_l || [ -n "$_th_l" ]; do
    _th_l=${_th_l%"$CR"}
    case "$_th_l" in
      '```'*|'~~~'*) if [ "$_th_fence" -eq 0 ]; then _th_fence=1; else _th_fence=0; fi; continue ;;
    esac
    [ "$_th_fence" -eq 0 ] || continue
    case "$_th_l" in
      *'['*|*'<'*) continue ;;
      '## '*) case "$2" in *2*) printf '%s\n' "$_th_l" ;; esac ;;
      '### '*) case "$2" in *3*) printf '%s\n' "$_th_l" ;; esac ;;
    esac
  done < "$1"
}

# _template_header_labels <template> — rotulos `**X**` das linhas `**X**:` antes do 1o `## `.
_template_header_labels() {
  while IFS= read -r _tl_l || [ -n "$_tl_l" ]; do
    _tl_l=${_tl_l%"$CR"}
    case "$_tl_l" in
      '## '*) break ;;
      '**'*'**:'*)
        _tl_lab=${_tl_l%%'**:'*}
        printf '%s**\n' "$_tl_lab" ;;
    esac
  done < "$1"
}

# _has_heading <file> <titulo-exato> — 0 se o titulo existe (fora de bloco de codigo).
_has_heading() {
  _hh_fence=0
  while IFS= read -r _hh_l || [ -n "$_hh_l" ]; do
    _hh_l=${_hh_l%"$CR"}
    while case "$_hh_l" in *' ') true ;; *) false ;; esac; do _hh_l=${_hh_l% }; done
    case "$_hh_l" in
      '```'*|'~~~'*) if [ "$_hh_fence" -eq 0 ]; then _hh_fence=1; else _hh_fence=0; fi; continue ;;
    esac
    [ "$_hh_fence" -eq 0 ] || continue
    [ "$_hh_l" = "$2" ] && return 0
  done < "$1"
  return 1
}

# _heading_contains <file> <texto> — 0 se algum titulo (`#`) contem o texto.
_heading_contains() {
  _hc_fence=0
  while IFS= read -r _hc_l || [ -n "$_hc_l" ]; do
    _hc_l=${_hc_l%"$CR"}
    case "$_hc_l" in
      '```'*|'~~~'*) if [ "$_hc_fence" -eq 0 ]; then _hc_fence=1; else _hc_fence=0; fi; continue ;;
    esac
    [ "$_hc_fence" -eq 0 ] || continue
    case "$_hc_l" in
      '#'*"$2"*) return 0 ;;
    esac
  done < "$1"
  return 1
}

# _missing_sections <artifact-rel> <file> <template> <niveis> [excluidos-prefixo...]
# Emite `missing-section` para cada titulo do template ausente no artefato.
_missing_sections() {
  _ms_art=$1
  _ms_file=$2
  _ms_tpl=$3
  _ms_lv=$4
  shift 4
  _ms_list=$(_template_headings "$_ms_tpl" "$_ms_lv")
  _ms_oldifs=$IFS
  IFS='
'
  set -f   # sem globbing: o texto expandido nunca e tratado como padrao de caminho
  for _ms_h in $_ms_list; do
    IFS=$_ms_oldifs
    _ms_skip=0
    for _ms_x in "$@"; do
      case "$_ms_h" in "$_ms_x"*) _ms_skip=1 ;; esac
    done
    if [ "$_ms_skip" -eq 0 ] && ! _has_heading "$_ms_file" "$_ms_h"; then
      _div "$_ms_art" missing-section "$_ms_h" add-section
    fi
    IFS='
'
  done
  set +f
  IFS=$_ms_oldifs
}

# ---------------------------------------------------------------- regras por artefato

# _check_briefing <rel> <file> — CR-003 (cabecalho) + missing-section.
_check_briefing() {
  _cb_rel=$1
  _cb_file=$2
  _cb_labels=$(_template_header_labels "$T_BRIEFING")
  _cb_oldifs=$IFS
  IFS='
'
  set -f
  for _cb_lab in $_cb_labels; do
    IFS=$_cb_oldifs
    _cb_found=0
    while IFS= read -r _cb_l || [ -n "$_cb_l" ]; do
      case "$_cb_l" in '## '*) break ;; esac
      case "$_cb_l" in "$_cb_lab":*) _cb_found=1; break ;; esac
    done < "$_cb_file"
    [ "$_cb_found" -eq 1 ] || _div "$_cb_rel" CR-003 "$_cb_lab: ausente no cabecalho" manual
    IFS='
'
  done
  set +f
  IFS=$_cb_oldifs
  _missing_sections "$_cb_rel" "$_cb_file" "$T_BRIEFING" 2
}

# _check_footer <file> — 0 se ha rodape `**Version**: v | **Ratified**: v | **Last Amended**: v`
# com os tres valores nao vazios e sem placeholder.
_check_footer() {
  while IFS= read -r _cf_l || [ -n "$_cf_l" ]; do
    _cf_l=${_cf_l%"$CR"}
    case "$_cf_l" in
      '**Version**:'*' | **Ratified**:'*' | **Last Amended**:'*) ;;
      *) continue ;;
    esac
    _cf_v=${_cf_l#'**Version**:'}
    _cf_v=${_cf_v%%' | **Ratified**:'*}
    _cf_r=${_cf_l#*' | **Ratified**:'}
    _cf_r=${_cf_r%%' | **Last Amended**:'*}
    _cf_a=${_cf_l#*' | **Last Amended**:'}
    _cf_ok=1
    for _cf_x in "$_cf_v" "$_cf_r" "$_cf_a"; do
      while case "$_cf_x" in ' '*) true ;; *) false ;; esac; do _cf_x=${_cf_x# }; done
      while case "$_cf_x" in *' ') true ;; *) false ;; esac; do _cf_x=${_cf_x% }; done
      case "$_cf_x" in ''|*'['*|*'|'*) _cf_ok=0 ;; esac
    done
    [ "$_cf_ok" -eq 1 ] && return 0
  done < "$1"
  return 1
}

# _principles_without_must <file> — titulos de principio (`### ` sob `## Core Principles`)
# sem a linha `**MUST:**` no bloco, um por linha.
_principles_without_must() {
  _pm_in=0
  _pm_cur=
  _pm_has=0
  _pm_fence=0
  while IFS= read -r _pm_l || [ -n "$_pm_l" ]; do
    _pm_l=${_pm_l%"$CR"}
    case "$_pm_l" in
      '```'*|'~~~'*) if [ "$_pm_fence" -eq 0 ]; then _pm_fence=1; else _pm_fence=0; fi; continue ;;
    esac
    [ "$_pm_fence" -eq 0 ] || continue
    case "$_pm_l" in
      '## '*)
        if [ -n "$_pm_cur" ] && [ "$_pm_has" -eq 0 ]; then printf '%s\n' "$_pm_cur"; fi
        _pm_cur=
        if [ "$_pm_l" = '## Core Principles' ]; then _pm_in=1; else _pm_in=0; fi ;;
      '### '*)
        if [ "$_pm_in" -eq 1 ]; then
          if [ -n "$_pm_cur" ] && [ "$_pm_has" -eq 0 ]; then printf '%s\n' "$_pm_cur"; fi
          _pm_cur=${_pm_l#'### '}
          _pm_has=0
        fi ;;
      '**MUST:**'*) [ "$_pm_in" -ne 1 ] || _pm_has=1 ;;
    esac
  done < "$1"
  if [ "$_pm_in" -eq 1 ] && [ -n "$_pm_cur" ] && [ "$_pm_has" -eq 0 ]; then printf '%s\n' "$_pm_cur"; fi
}

_check_constitution() {
  _cc_rel=$1
  _cc_file=$2
  _missing_sections "$_cc_rel" "$_cc_file" "$T_CONSTITUTION" 2
  if ! _check_footer "$_cc_file"; then
    _div "$_cc_rel" CR-004 "rodape **Version**/**Ratified**/**Last Amended** ausente ou malformado" fix-footer
  fi
  if ! _heading_contains "$_cc_file" 'Veracidade de Dados'; then
    _div "$_cc_rel" CR-005 "principio Veracidade de Dados — Zero Fabricacao ausente" add-principle
  fi
  _cc_list=$(_principles_without_must "$_cc_file")
  _cc_oldifs=$IFS
  IFS='
'
  set -f   # titulo de principio vem do projeto-alvo: `*`/`/etc/*` nao pode virar listagem de caminhos
  for _cc_p in $_cc_list; do
    IFS=$_cc_oldifs
    _div "$_cc_rel" CR-006 "principio sem linha **MUST:**: $_cc_p" manual
    IFS='
'
  done
  set +f
  IFS=$_cc_oldifs
}

_check_spec() {
  _cs_rel=$1
  _cs_file=$2
  # `Delta Requirements` e opcional no template (CR-007) e `Key Entities` e condicional.
  _missing_sections "$_cs_rel" "$_cs_file" "$T_SPEC" 23 '## Delta Requirements' '### Key Entities'
  if ! _has_heading "$_cs_file" '## Delta Requirements'; then
    _div "$_cs_rel" CR-007 "secao ## Delta Requirements ausente" add-delta-section
  fi
}

# ---------------------------------------------------------------- check

cmd_check() {
  _root=$1
  _catalog=$2
  [ -n "$_root" ] || _die_usage "check exige --root"
  [ -n "$_catalog" ] || _die_usage "check exige --catalog-root"
  [ -d "$_root" ] || { printf 'init-conformance: raiz inexistente: %s\n' "$_root" >&2; exit 1; }
  ROOT_P=$(cd -P -- "$_root" 2>/dev/null && pwd -P) || {
    printf 'init-conformance: nao foi possivel resolver a raiz: %s\n' "$_root" >&2; exit 1; }

  T_BRIEFING="$_catalog/briefing/templates/briefing.md"
  T_CONSTITUTION="$_catalog/constitution/templates/constitution.md"
  T_SPEC="$_catalog/specify/templates/feature-spec.md"
  for _t in "$T_BRIEFING" "$T_CONSTITUTION" "$T_SPEC"; do
    if [ ! -f "$_t" ] || [ ! -r "$_t" ]; then
      printf 'init-conformance: template de irma ausente: %s — rode `cstk install` (perfil sdd) para instalar o catalogo\n' \
        "$(_printable "$_t")" >&2
      exit 4
    fi
  done

  # --- briefing
  _has_canon=0
  _has_legacy=0
  _rc=0
  _readable_artifact "$BRIEFING_CANON" || _rc=$?
  [ "$_rc" -ne 0 ] || _has_canon=1
  _not_evaluated "$BRIEFING_CANON" "$_rc"
  _rc=0
  _readable_artifact "$BRIEFING_LEGACY" || _rc=$?
  [ "$_rc" -ne 0 ] || _has_legacy=1
  _not_evaluated "$BRIEFING_LEGACY" "$_rc"

  if [ "$_has_canon" -eq 1 ] && [ "$_has_legacy" -eq 1 ]; then
    _div "$BRIEFING_CANON" CR-002 "briefing nos dois caminhos (canonico e legado); decisao do operador antes de migrar" manual
    _check_briefing "$BRIEFING_CANON" "$ROOT_P/$BRIEFING_CANON"
  elif [ "$_has_canon" -eq 1 ]; then
    _check_briefing "$BRIEFING_CANON" "$ROOT_P/$BRIEFING_CANON"
  elif [ "$_has_legacy" -eq 1 ]; then
    _div "$BRIEFING_LEGACY" CR-001 "briefing so no caminho legado; mover para $BRIEFING_CANON somente com confirmacao por caminho" migrate-path
    _check_briefing "$BRIEFING_LEGACY" "$ROOT_P/$BRIEFING_LEGACY"
  fi

  # --- constitution
  _rc=0
  _readable_artifact docs/constitution.md || _rc=$?
  if [ "$_rc" -eq 0 ]; then
    _check_constitution docs/constitution.md "$ROOT_P/docs/constitution.md"
  else
    _not_evaluated docs/constitution.md "$_rc"
  fi

  # --- specs (nao segue symlink de diretorio; ignora `_*` e `current`)
  if [ -L "$ROOT_P/docs/specs" ]; then
    _div docs/specs CR-008 "artefato nao avaliado: docs/specs e symlink (nao seguido)" manual
  elif [ -d "$ROOT_P/docs/specs" ]; then
    for _d in "$ROOT_P"/docs/specs/*/; do
      [ -d "$_d" ] || continue
      _name=$(basename -- "$_d")
      case "$_name" in _*|current|'*') continue ;; esac
      _rel="docs/specs/$_name/spec.md"
      if [ -L "${_d%/}" ]; then
        _div "docs/specs/$_name" CR-008 "artefato nao avaliado: diretorio de spec e symlink (nao seguido)" manual
        continue
      fi
      _rc=0
      _readable_artifact "$_rel" || _rc=$?
      if [ "$_rc" -ne 0 ]; then
        _not_evaluated "$_rel" "$_rc"
        continue
      fi
      _check_spec "$_rel" "$ROOT_P/$_rel"
    done
  fi

  if [ "$DIV_COUNT" -eq 0 ]; then
    printf 'STATUS\tconformant\n'
  else
    printf 'STATUS\tdivergent\n'
  fi
  exit 0
}

# ---------------------------------------------------------------- main

[ $# -ge 1 ] || _die_usage "subcomando obrigatorio"
SUB=$1
shift

case "$SUB" in
  check)
    ROOT=
    CATALOG=
    while [ $# -gt 0 ]; do
      case "$1" in
        --root) [ $# -ge 2 ] || _die_usage "--root exige valor"; ROOT=$2; shift 2 ;;
        --catalog-root) [ $# -ge 2 ] || _die_usage "--catalog-root exige valor"; CATALOG=$2; shift 2 ;;
        *) _die_usage "argumento desconhecido: $1" ;;
      esac
    done
    cmd_check "$ROOT" "$CATALOG"
    ;;
  -h|--help) _usage; exit 0 ;;
  *) _die_usage "subcomando desconhecido: $SUB" ;;
esac
