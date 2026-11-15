#!/bin/sh
# init-provenance.sh — lint de marcadores de origem/pendencia da skill cstk-init
# (feature cstk-init, tarefa 4.4, criticidade [C]).
#
# Contrato: SKILL.md ("Ciclo de escrita") e references/markers.md.
#
#   init-provenance.sh lint --root <dir> --file <rel>
#
# stdout (um achado por linha, na ordem do arquivo; <linha> 1-based, 0 = documento todo):
#   PENDING<TAB><linha><TAB><pergunta>
#   DANGLING<TAB><linha><TAB><path-citado-inexistente>
#   BAD-MARKER<TAB><linha><TAB><regra violada (sem o texto da linha)>
#   STATUS<TAB><ok|pending|invalid>
# exit: 0 ok/pending | 3 invalid (DANGLING ou BAD-MARKER) | 1 erro do mecanismo
#       (raiz/arquivo inexistente, --file fora da raiz) | 2 uso.
#
# Regras gerais (qualquer documento):
#   - `(fonte: `<caminho>`)` / `(fonte: `<caminho>:<linha>`)`: caminho relativo a raiz,
#     sem `..`, sem caminho absoluto, sem symlink que escape da raiz (FR-023) => senao
#     BAD-MARKER; caminho (ou linha) inexistente => DANGLING. Forma fora da gramatica
#     (`(fonte: x)` sem crases, citacao sem fechamento, linha 0) => BAD-MARKER.
#   - `[PENDENTE: <pergunta>]`: PENDING; sem pergunta ou sem `]` => BAD-MARKER.
#   - `(informado pelo operador)` e origem valida e nao exige verificacao de caminho.
#
# Spec reconstituida (caminho docs/specs/<short>/spec.md OU presenca do marcador
# `<!-- cstk-init:reconstructed -->`), alem das regras gerais:
#   - o marcador deve existir e vir antes do primeiro `## ` (FR-015);
#   - sob `### Inferido (nao confirmado)`: nenhum MUST/SHOULD (FR-015, FR-019);
#   - FR-028: Success Criterion (item de lista sob `## Success Criteria`) com digito e sem
#     origem, titulo `### User Story` sem origem/PENDENTE (prioridade) e cenario de aceite
#     sem origem/PENDENTE => BAD-MARKER; item `- **FR-NNN**` fora de Inferido sem origem
#     nem PENDENTE => BAD-MARKER (formato "Observado" de markers.md §3).
#
# Os achados NAO reproduzem o texto da linha auditada (so a linha e a regra): o documento pode
# conter valor sensivel e a saida vai para o contexto do modelo e da conversa (FR-024).
#
# Seguranca: o conteudo do arquivo e DADO hostil — nunca e executado, nem interpolado em
# comando; so e lido com `read -r`. A resolucao de caminhos usa `cd -P`/`pwd -P` e `readlink`
# (sem `realpath`); falha de resolucao = escape (fail-closed). O script e somente leitura.

set -eu
LC_ALL=C
export LC_ALL

TAB=$(printf '\t')
NL='
'
CR=$(printf '\r')

MARKER='<!-- cstk-init:reconstructed -->'

_usage() {
  cat >&2 <<'EOF'
uso:
  init-provenance.sh lint --root <dir> --file <rel>
EOF
}

_die_usage() {
  printf 'init-provenance: %s\n' "$1" >&2
  _usage
  exit 2
}

_die() {
  printf 'init-provenance: %s\n' "$1" >&2
  exit 1
}

# _printable <s> — troca caracteres de controle por `?` e trunca em 120 bytes, para nunca
# quebrar o TSV de saida.
_printable() {
  printf '%s' "$1" | tr '\001-\037\177' '?' | cut -c1-120
}

# ---------------------------------------------------------------- resolucao de caminho

# _resolve_link <abs-root> <link> — imprime: file | dir | dangling | escape.
# `escape` = destino fora da raiz ou irresoluvel (fail-closed).
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

# _path_class <root-fisica> <rel> — imprime: ok | bad | missing.
# bad = absoluto, `~`, drive, `..`, caracter de controle, vazio ou symlink que escapa;
# missing = relativo valido que nao existe; ok = existe dentro da raiz.
_path_class() {
  _pc_root=$1
  _pc_rel=$2
  [ -n "$_pc_rel" ] || { printf 'bad'; return 0; }
  case "$_pc_rel" in
    /*|\\*|'~'*|[A-Za-z]:*) printf 'bad'; return 0 ;;
    *"$TAB"*|*"$NL"*|*"$CR"*) printf 'bad'; return 0 ;;
  esac
  case "/$_pc_rel/" in
    */../*) printf 'bad'; return 0 ;;
  esac
  _pc_cur=$_pc_root
  _pc_oldifs=$IFS
  IFS=/
  set -f
  # shellcheck disable=SC2086
  set -- $_pc_rel
  set +f
  IFS=$_pc_oldifs
  for _pc_c in "$@"; do
    case "$_pc_c" in ''|.) continue ;; esac
    _pc_cur="$_pc_cur/$_pc_c"
    if [ -L "$_pc_cur" ]; then
      _pc_k=$(_resolve_link "$_pc_root" "$_pc_cur")
      if [ "$_pc_k" = escape ]; then printf 'bad'; return 0; fi
    fi
  done
  if [ -e "$_pc_cur" ]; then printf 'ok'; else printf 'missing'; fi
  return 0
}

# ---------------------------------------------------------------- achados

BAD_COUNT=0
DANGLING_COUNT=0
PENDING_COUNT=0

_bad() {
  BAD_COUNT=$((BAD_COUNT + 1))
  printf 'BAD-MARKER\t%s\t%s\n' "$1" "$(_printable "$2")"
}

_dangling() {
  DANGLING_COUNT=$((DANGLING_COUNT + 1))
  printf 'DANGLING\t%s\t%s\n' "$1" "$(_printable "$2")"
}

_pending() {
  PENDING_COUNT=$((PENDING_COUNT + 1))
  printf 'PENDING\t%s\t%s\n' "$1" "$(_printable "$2")"
}

# _check_cite <linha> <citacao> — valida o conteudo entre as crases de `(fonte: `...`)`.
_check_cite() {
  _cc_n=$1
  _cc_c=$2
  _cc_p=$_cc_c
  _cc_ln=
  case "$_cc_c" in
    *:*)
      _cc_suf=${_cc_c##*:}
      case "$_cc_suf" in
        ''|*[!0-9]*) ;;
        *) _cc_ln=$_cc_suf; _cc_p=${_cc_c%:*} ;;
      esac ;;
  esac
  if [ -n "$_cc_ln" ]; then
    # remove zeros a esquerda (evita interpretacao octal) e valida 1..999999999
    while case "$_cc_ln" in 0?*) true ;; *) false ;; esac; do _cc_ln=${_cc_ln#0}; done
    if [ "${#_cc_ln}" -gt 9 ] || [ "$_cc_ln" = 0 ]; then
      _bad "$_cc_n" "(fonte: \`$_cc_c\`) linha invalida"
      return 0
    fi
  fi
  _cc_cls=$(_path_class "$ROOT_P" "$_cc_p")
  case "$_cc_cls" in
    bad) _bad "$_cc_n" "(fonte: \`$_cc_c\`) caminho fora do contrato (absoluto, .., symlink que escapa ou vazio)"; return 0 ;;
    missing) _dangling "$_cc_n" "$_cc_c"; return 0 ;;
  esac
  if [ -n "$_cc_ln" ]; then
    # so arquivo regular tem "linha N": diretorio, FIFO e dispositivo nao sao lidos (um FIFO
    # travaria o `grep -c` indefinidamente)
    if [ ! -f "$ROOT_P/$_cc_p" ]; then
      _dangling "$_cc_n" "$_cc_c"
      return 0
    fi
    _cc_total=$(grep -c '' "$ROOT_P/$_cc_p" 2>/dev/null) || _cc_total=0
    if [ "$_cc_ln" -gt "$_cc_total" ]; then
      _dangling "$_cc_n" "$_cc_c"
      return 0
    fi
  fi
  return 0
}

# _scan_markers <linha> <texto> — verifica `(fonte:` e `[PENDENTE` na linha.
_scan_markers() {
  _sm_n=$1
  _sm_rest=$2
  while :; do
    case "$_sm_rest" in *'(fonte:'*) ;; *) break ;; esac
    _sm_rest=${_sm_rest#*'(fonte:'}
    case "$_sm_rest" in
      ' `'*)
        _sm_body=${_sm_rest#' `'}
        case "$_sm_body" in
          *'`)'*)
            _sm_cite=${_sm_body%%'`)'*}
            _sm_rest=${_sm_body#*'`)'}
            _check_cite "$_sm_n" "$_sm_cite" ;;
          *)
            _bad "$_sm_n" "(fonte: sem fechamento \`)"
            break ;;
        esac ;;
      *)
        _bad "$_sm_n" "(fonte: fora da gramatica (esperado: espaco, crase, caminho, crase, parentese)"
        ;;
    esac
  done
  _sm_rest=$2
  while :; do
    case "$_sm_rest" in *'[PENDENTE'*) ;; *) break ;; esac
    _sm_rest=${_sm_rest#*'[PENDENTE'}
    case "$_sm_rest" in
      :*)
        _sm_body=${_sm_rest#:}
        case "$_sm_body" in
          *']'*)
            _sm_q=${_sm_body%%']'*}
            _sm_rest=${_sm_body#*']'}
            # tira espacos das pontas
            while case "$_sm_q" in ' '*) true ;; *) false ;; esac; do _sm_q=${_sm_q# }; done
            while case "$_sm_q" in *' ') true ;; *) false ;; esac; do _sm_q=${_sm_q% }; done
            if [ -z "$_sm_q" ]; then _bad "$_sm_n" "[PENDENTE: vazio"; else _pending "$_sm_n" "$_sm_q"; fi ;;
          *)
            _bad "$_sm_n" "[PENDENTE: sem fechamento ]"
            break ;;
        esac ;;
      *)
        _bad "$_sm_n" "[PENDENTE sem ':' e pergunta"
        ;;
    esac
  done
}

# ---------------------------------------------------------------- regras de spec reconstituida

# _has_origin <texto> — 0 se ha origem de fato OU pendencia na linha.
_has_origin() {
  case "$1" in
    *'(fonte: `'*'`)'*|*'(informado pelo operador)'*|*'[PENDENTE:'*']'*) return 0 ;;
  esac
  return 1
}

# _has_source <texto> — 0 se ha origem de fato (SEM contar PENDENTE).
_has_source() {
  case "$1" in
    *'(fonte: `'*'`)'*|*'(informado pelo operador)'*) return 0 ;;
  esac
  return 1
}

# _strip_spans <texto> — remove `(fonte: ...)`, `(informado pelo operador)` e
# `[PENDENTE: ...]`; resultado em $_STRIPPED.
_strip_spans() {
  _ss_s=$1
  while :; do
    case "$_ss_s" in *'(fonte:'*) ;; *) break ;; esac
    _ss_pre=${_ss_s%%'(fonte:'*}
    _ss_post=${_ss_s#*'(fonte:'}
    case "$_ss_post" in
      *'`)'*) _ss_s="$_ss_pre ${_ss_post#*'`)'}" ;;
      *) _ss_s=$_ss_pre ;;
    esac
  done
  while :; do
    case "$_ss_s" in *'(informado pelo operador)'*) ;; *) break ;; esac
    _ss_pre=${_ss_s%%'(informado pelo operador)'*}
    _ss_post=${_ss_s#*'(informado pelo operador)'}
    _ss_s="$_ss_pre $_ss_post"
  done
  while :; do
    case "$_ss_s" in *'[PENDENTE'*) ;; *) break ;; esac
    _ss_pre=${_ss_s%%'[PENDENTE'*}
    _ss_post=${_ss_s#*'[PENDENTE'}
    case "$_ss_post" in
      *']'*) _ss_s="$_ss_pre ${_ss_post#*']'}" ;;
      *) _ss_s=$_ss_pre ;;
    esac
  done
  for _ss_tok in 'SC-' 'FR-' 'INF-'; do
    while :; do
      case "$_ss_s" in *"$_ss_tok"*) ;; *) break ;; esac
      _ss_pre=${_ss_s%%"$_ss_tok"*}
      _ss_post=${_ss_s#*"$_ss_tok"}
      while case "$_ss_post" in [0-9]*) true ;; *) false ;; esac; do _ss_post=${_ss_post#?}; done
      _ss_s="$_ss_pre $_ss_post"
    done
  done
  _STRIPPED=$_ss_s
}

# _is_list_item <texto> — 0 se item de lista (`-`, `*`, `N.`), ignorando indentacao.
_is_list_item() {
  _li_s=$1
  while case "$_li_s" in ' '*|"$TAB"*) true ;; *) false ;; esac; do _li_s=${_li_s#?}; done
  case "$_li_s" in
    '- '*|'* '*|[0-9]'. '*|[0-9][0-9]'. '*) return 0 ;;
  esac
  return 1
}

# _has_rfc_word <texto> — 0 se contem MUST ou SHOULD como palavra (case-insensitive).
_has_rfc_word() {
  _hr_u=$(printf ' %s ' "$1" | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9' ' ')
  case "$_hr_u" in
    *' MUST '*|*' SHOULD '*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------- lint

cmd_lint() {
  _root=$1
  _file=$2
  [ -n "$_root" ] || _die_usage "lint exige --root"
  [ -n "$_file" ] || _die_usage "lint exige --file"
  [ -d "$_root" ] || _die "raiz inexistente: $_root"
  ROOT_P=$(cd -P -- "$_root" 2>/dev/null && pwd -P) || _die "nao foi possivel resolver a raiz: $_root"

  _cls=$(_path_class "$ROOT_P" "$_file")
  case "$_cls" in
    bad) _die "--file fora do contrato (absoluto, .., symlink que escapa ou vazio): $(_printable "$_file")" ;;
    missing) _die "arquivo inexistente: $(_printable "$_file")" ;;
  esac
  [ -f "$ROOT_P/$_file" ] || _die "nao e arquivo regular: $(_printable "$_file")"
  [ -r "$ROOT_P/$_file" ] || _die "arquivo ilegivel: $(_printable "$_file")"
  _abs="$ROOT_P/$_file"

  # --- pre-varredura: marcador de spec reconstituida e primeiro `## `
  _marker_line=0
  _first_h2=0
  _n=0
  _fence=0
  while IFS= read -r _l || [ -n "$_l" ]; do
    _n=$((_n + 1))
    _l=${_l%"$CR"}
    case "$_l" in
      '```'*|'~~~'*) if [ "$_fence" -eq 0 ]; then _fence=1; else _fence=0; fi; continue ;;
    esac
    [ "$_fence" -eq 0 ] || continue
    if [ "$_l" = "$MARKER" ] && [ "$_marker_line" -eq 0 ]; then _marker_line=$_n; fi
    case "$_l" in
      '## '*) [ "$_first_h2" -ne 0 ] || _first_h2=$_n ;;
    esac
  done < "$_abs"

  _reconstructed=0
  case "$_file" in
    docs/specs/*/spec.md|./docs/specs/*/spec.md) _reconstructed=1 ;;
  esac
  [ "$_marker_line" -eq 0 ] || _reconstructed=1

  if [ "$_reconstructed" -eq 1 ]; then
    if [ "$_marker_line" -eq 0 ]; then
      _bad 0 "spec reconstituida sem o marcador $MARKER"
    elif [ "$_first_h2" -ne 0 ] && [ "$_marker_line" -gt "$_first_h2" ]; then
      _bad "$_marker_line" "marcador de spec reconstituida apos o primeiro '## ' (deve vir logo apos o titulo)"
    fi
  fi

  # --- varredura principal
  _n=0
  _fence=0
  _in_inf=0
  _in_sc=0
  _in_acc=0
  while IFS= read -r _l || [ -n "$_l" ]; do
    _n=$((_n + 1))
    _l=${_l%"$CR"}
    case "$_l" in
      '```'*|'~~~'*) if [ "$_fence" -eq 0 ]; then _fence=1; else _fence=0; fi ;;
    esac

    # origem/pendencia: valem em qualquer documento
    _scan_markers "$_n" "$_l"

    [ "$_reconstructed" -eq 1 ] || continue

    # estrutura (fora de bloco de codigo)
    if [ "$_fence" -eq 0 ]; then
      case "$_l" in
        '## '*|'# '*)
          _in_inf=0; _in_acc=0
          _in_sc=0
          _lc=$(printf '%s' "$_l" | tr 'A-Z' 'a-z')
          case "$_lc" in *'success criteria'*|*'criterios de sucesso'*) _in_sc=1 ;; esac
          continue ;;
        '### '*)
          _in_inf=0; _in_acc=0
          case "$_l" in
            '### Inferido'*) _in_inf=1; continue ;;
          esac
          case "$_l" in
            '### User Story'*)
              if ! _has_origin "$_l"; then
                _bad "$_n" "prioridade de user story sem origem nem [PENDENTE: ...]"
              fi ;;
          esac
          continue ;;
        '#'*) continue ;;
        '**'*) case "$_l" in *'Acceptance Scenarios'*) _in_acc=1 ;; *) _in_acc=0 ;; esac ;;
      esac
    fi

    # Inferido: nenhum MUST/SHOULD
    if [ "$_in_inf" -eq 1 ] && _has_rfc_word "$_l"; then
      _bad "$_n" "MUST/SHOULD sob '### Inferido (nao confirmado)'"
    fi

    if [ "$_in_inf" -eq 0 ] && [ "$_fence" -eq 0 ] && _is_list_item "$_l"; then
      # Success Criterion com meta numerica exige origem de fato (FR-028)
      if [ "$_in_sc" -eq 1 ]; then
        _strip_spans "$_l"
        case "$_STRIPPED" in
          *[0-9]*)
            if ! _has_source "$_l"; then
              _bad "$_n" "Success Criterion com meta numerica sem origem"
            fi ;;
        esac
      fi
      # cenario de aceite exige origem ou PENDENTE (FR-028)
      _is_scn=0
      [ "$_in_acc" -eq 1 ] && _is_scn=1
      case "$_l" in *'Given'*'When'*|*'Given'*'Then'*|*'Dado'*'Quando'*|*'Dado'*'Entao'*) _is_scn=1 ;; esac
      if [ "$_is_scn" -eq 1 ] && ! _has_origin "$_l"; then
        _bad "$_n" "cenario de aceite sem origem nem [PENDENTE: ...]"
      fi
      # requisito observado exige origem ou PENDENTE (markers.md §3)
      case "$_l" in
        '- **FR-'[0-9]*)
          if ! _has_origin "$_l"; then
            _bad "$_n" "requisito observado sem origem nem [PENDENTE: ...]"
          fi ;;
      esac
    fi
  done < "$_abs"

  if [ "$BAD_COUNT" -gt 0 ] || [ "$DANGLING_COUNT" -gt 0 ]; then
    printf 'STATUS\tinvalid\n'
    exit 3
  fi
  if [ "$PENDING_COUNT" -gt 0 ]; then
    printf 'STATUS\tpending\n'
  else
    printf 'STATUS\tok\n'
  fi
  exit 0
}

# ---------------------------------------------------------------- main

[ $# -ge 1 ] || _die_usage "subcomando obrigatorio"
SUB=$1
shift

case "$SUB" in
  lint)
    ROOT=
    FILE=
    while [ $# -gt 0 ]; do
      case "$1" in
        --root) [ $# -ge 2 ] || _die_usage "--root exige valor"; ROOT=$2; shift 2 ;;
        --file) [ $# -ge 2 ] || _die_usage "--file exige valor"; FILE=$2; shift 2 ;;
        *) _die_usage "argumento desconhecido: $1" ;;
      esac
    done
    cmd_lint "$ROOT" "$FILE"
    ;;
  -h|--help) _usage; exit 0 ;;
  *) _die_usage "subcomando desconhecido: $SUB" ;;
esac
