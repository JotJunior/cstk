#!/bin/sh
# init-inventory.sh — inventario deterministico do projeto para a skill cstk-init
# (feature cstk-init, tarefa 4.2).
#
# Contrato: SKILL.md §3 (saida TSV `<kind><TAB><path>`).
#
#   init-inventory.sh inventory --root <dir> [--max-items <n>]
#
# stdout: `<kind>\t<path>` (path relativo a raiz), ordenado por path, sem cabecalho.
#   kinds: readme doc manifest ci config test source-dir license changelog
#          secret-bearing symlink-escape
# Linha final `TRUNCATED\t<n>` quando o inventario e PARCIAL (FR-030a), por um destes motivos
# (o motivo vai em stderr, `init-inventory: ...`):
#   - teto de itens (`--max-items`, default 1000): n = itens omitidos (exato se a varredura terminou);
#   - teto de varredura (50 x --max-items arquivos visitados; valor de design, sem medicao
#     empirica, como o default de FR-030): a varredura PARA e n e um limite inferior (>= 1);
#   - erro de leitura/execucao da varredura (permissao negada, `find` ou emissor falhou): n = numero
#     de erros reportados (>= 1). Inventario parcial NUNCA sai silencioso com exit 0.
#
# Regras de seguranca (FR-019, FR-023, FR-024):
#   - NUNCA le conteudo de arquivo: a classificacao e so por caminho/nome. Nenhum valor de
#     configuracao aparece em stdout; `secret-bearing` e decidido so pelo nome.
#   - Symlink cujo destino resolvido sai da raiz => `symlink-escape\t<link>`, nunca seguido.
#     Destino inexistente/irresoluvel (ou ciclo) tambem e tratado como escape (fail-safe).
#     Symlink valido para arquivo dentro da raiz e classificado pelo NOME do link; symlink
#     para diretorio e symlink pendente dentro da raiz sao omitidos (nunca seguidos).
#   - Nomes com TAB, newline ou qualquer caractere de controle sao omitidos (TSV integro, sem
#     injecao de sequencia de terminal no contexto).
#   - Diretorios ignorados: .git node_modules vendor dist build .venv target .claude.
#
# `source-dir`: diretorio que contem ao menos um arquivo de codigo-fonte (extensoes
# conhecidas), emitido uma vez por diretorio (`.` = a propria raiz); os arquivos de codigo
# em si nao sao listados individualmente.
#
# Custo: a classificacao roda no mesmo shell (sem subshell por arquivo) e a varredura e limitada
# por --max-items (teto de varredura acima); o teto nunca limita so a saida.
#
# Exit: 0 sucesso (inclusive parcial, sinalizado por TRUNCATED); 1 raiz inexistente; 2 uso incorreto.

set -eu
LC_ALL=C
export LC_ALL

TAB=$(printf '\t')
NL='
'
DEFAULT_MAX_ITEMS=1000
SCAN_FACTOR=50

_usage() {
  cat >&2 <<EOF
uso: init-inventory.sh inventory --root <dir> [--max-items <n>]
  --root <dir>       raiz do projeto (obrigatorio)
  --max-items <n>    teto de itens emitidos (inteiro positivo; default ${DEFAULT_MAX_ITEMS}, valor de
                     design sem medicao empirica — FR-030a). Acima do teto, a linha final
                     "TRUNCATED<TAB><n-omitidos>" e emitida e o inventario e PARCIAL.
EOF
}

_die_usage() {
  printf 'init-inventory: %s\n' "$1" >&2
  _usage
  exit 2
}

# ---------------------------------------------------------------- classificacao (so por nome)

# _kind_of <rel-path> — define $_K com o kind (vazio = arquivo sem relevancia para o inventario).
# Roda no shell corrente: sem `$(...)` por arquivo (7.5.3).
_kind_of() {
  _ko_rel=$1
  _ko_base=${_ko_rel##*/}
  _K=
  case "$_ko_base" in
    .env|.env.*|.envrc|*.pem|*.key|id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*|*.p12|*.pfx|*.p8|*.jks|*.keystore|\
*.kdbx|*.tfvars|terraform.tfstate*|.npmrc|.netrc|.pypirc|.htpasswd|.git-credentials|\
secrets.*|secret.*|*.secrets.*|service-account*|serviceaccount*|credentials*)
      _K=secret-bearing; return 0 ;;
    README*|readme*|Readme*) _K=readme; return 0 ;;
    LICENSE*|LICENCE*|License*|license*|COPYING*) _K=license; return 0 ;;
    CHANGELOG*|Changelog*|changelog*) _K=changelog; return 0 ;;
    .gitlab-ci.yml|.travis.yml|Jenkinsfile|azure-pipelines.yml) _K=ci; return 0 ;;
  esac
  case "$_ko_rel" in
    .github/workflows/*|.circleci/*) _K=ci; return 0 ;;
    docs/*) _K=doc; return 0 ;;
  esac
  case "/$_ko_rel" in
    */tests/*|*/test/*|*/__tests__/*) _K=test; return 0 ;;
  esac
  case "$_ko_base" in
    *.test.*|*.spec.*|*_test.*|*_spec.*|test_*) _K=test; return 0 ;;
    package.json|go.mod|Cargo.toml|pyproject.toml|requirements.txt|composer.json|pom.xml|\
build.gradle|build.gradle.kts|settings.gradle|Gemfile|mix.exs|setup.py|setup.cfg|Makefile|\
*.csproj|*.sln)
      _K=manifest; return 0 ;;
    *.md|*.rst|*.adoc|*.txt) _K=doc; return 0 ;;
    *.yml|*.yaml|*.toml|*.ini|*.json|*.conf|*.cfg|Dockerfile*|docker-compose*|.editorconfig)
      _K=config; return 0 ;;
    *.js|*.mjs|*.cjs|*.jsx|*.ts|*.tsx|*.py|*.go|*.rs|*.java|*.kt|*.rb|*.php|*.cs|*.c|*.h|\
*.cpp|*.hpp|*.swift|*.sh|*.scala|*.ex|*.exs|*.vue|*.svelte)
      _K=source; return 0 ;;
  esac
  return 0
}

# ---------------------------------------------------------------- symlinks

# _resolve_link <abs-root> <link> — define $_RL: file | dir | dangling | escape.
# `file`/`dir`/`dangling` = destino DENTRO da raiz; `escape` = fora da raiz ou irresoluvel.
_resolve_link() {
  _rl_root=$1
  _rl_cur=$2
  command -v readlink >/dev/null 2>&1 || { _RL=escape; return 0; }
  _rl_n=0
  while [ -L "$_rl_cur" ]; do
    _rl_n=$((_rl_n + 1))
    [ "$_rl_n" -le 40 ] || { _RL=escape; return 0; }
    _rl_t=$(readlink -- "$_rl_cur" 2>/dev/null) || { _RL=escape; return 0; }
    case "$_rl_t" in
      /*) _rl_cur=$_rl_t ;;
      *) _rl_cur="$(dirname -- "$_rl_cur")/$_rl_t" ;;
    esac
  done
  if [ -d "$_rl_cur" ]; then
    _rl_full=$(cd -P -- "$_rl_cur" 2>/dev/null && pwd -P) || { _RL=escape; return 0; }
    _rl_kind=dir
  else
    _rl_pdir=$(cd -P -- "$(dirname -- "$_rl_cur")" 2>/dev/null && pwd -P) || { _RL=escape; return 0; }
    _rl_full="$_rl_pdir/$(basename -- "$_rl_cur")"
    if [ -e "$_rl_cur" ]; then _rl_kind=file; else _rl_kind=dangling; fi
  fi
  case "$_rl_full" in
    "$_rl_root"|"$_rl_root"/*) _RL=$_rl_kind ;;
    *) _RL=escape ;;
  esac
  return 0
}

# ---------------------------------------------------------------- modo interno (-exec de find)

# __emit <abs-root> <cap> <path>... — emite linhas `<kind>\t<rel>` (nao ordenadas) e, no fim,
# `VISITED\t<n>` (caminhos processados neste lote). Processa no maximo <cap> caminhos por lote;
# havendo mais, emite `OVERFLOW\t1` e para (o teto de varredura limita o TRABALHO, 7.5.3).
cmd_emit() {
  _root=$1
  _cap=$2
  shift 2
  _seen=0
  _over=0
  for _p in "$@"; do
    if [ "$_seen" -ge "$_cap" ]; then
      _over=1
      break
    fi
    _seen=$((_seen + 1))
    _rel=${_p#"$_root"/./}
    [ "$_rel" != "$_p" ] || continue
    # TAB/newline quebram o TSV; os demais caracteres de controle (ESC, CR...) injetariam
    # sequencias de terminal/texto no contexto do modelo: nomes assim sao omitidos.
    case "$_rel" in
      *"$TAB"*|*"$NL"*|*[[:cntrl:]]*) continue ;;
    esac
    if [ -L "$_p" ]; then
      _resolve_link "$_root" "$_p"
      case "$_RL" in
        escape) printf 'symlink-escape\t%s\n' "$_rel"; continue ;;
        file) ;;
        *) continue ;;
      esac
    fi
    _kind_of "$_rel"
    case "$_K" in
      '') ;;
      source)
        _dir=${_rel%/*}
        [ "$_dir" != "$_rel" ] || _dir=.
        printf 'source-dir\t%s\n' "$_dir" ;;
      *) printf '%s\t%s\n' "$_K" "$_rel" ;;
    esac
  done
  printf 'VISITED\t%s\n' "$_seen"
  [ "$_over" -eq 0 ] || printf 'OVERFLOW\t1\n'
}

# ---------------------------------------------------------------- inventory

cmd_inventory() {
  _rootarg=$1
  _max=$2
  [ -n "$_rootarg" ] || _die_usage "inventory exige --root"
  case "$_max" in
    ''|*[!0-9]*) _die_usage "--max-items exige inteiro positivo" ;;
  esac
  [ "$_max" -ge 1 ] || _die_usage "--max-items exige inteiro positivo"
  [ -d "$_rootarg" ] || { printf 'init-inventory: raiz inexistente: %s\n' "$_rootarg" >&2; return 1; }
  _abs=$(cd -P -- "$_rootarg" && pwd -P) || return 1

  _self=$(cd -P -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")
  _vcap=$((_max * SCAN_FACTOR))
  _tmp=$(mktemp "${TMPDIR:-/tmp}/init-inventory.XXXXXX") || return 1
  _err=$(mktemp "${TMPDIR:-/tmp}/init-inventory-err.XXXXXX") || { rm -f "$_tmp"; return 1; }
  _st=$(mktemp "${TMPDIR:-/tmp}/init-inventory-st.XXXXXX") || { rm -f "$_tmp" "$_err"; return 1; }
  _meta=$(mktemp "${TMPDIR:-/tmp}/init-inventory-meta.XXXXXX") || { rm -f "$_tmp" "$_err" "$_st"; return 1; }
  trap 'rm -f "$_tmp" "$_err" "$_st" "$_meta"' EXIT INT TERM HUP

  # find -> awk: o awk descarta VISITED/OVERFLOW (so conta), para a leitura ao passar do teto de
  # varredura (find recebe SIGPIPE) e grava o total visitado em $_meta. O status do find vai
  # para $_st e o stderr (permissao negada etc.) para $_err: nada e engolido (7.5.4).
  { find "$_abs/." \
      \( -name .git -o -name node_modules -o -name vendor -o -name dist -o -name build \
         -o -name .venv -o -name target -o -name .claude \) -prune -o \
      \( -type f -o -type l \) -exec sh "$_self" __emit "$_abs" "$_vcap" {} + 2>"$_err"
    printf '%s\n' "$?" > "$_st"
  } | awk -F'\t' -v vcap="$_vcap" -v meta="$_meta" '
      $1 == "VISITED" { v += $2; if (v > vcap) { capped = 1; exit } ; next }
      $1 == "OVERFLOW" { capped = 1; exit }
      { print }
      END { printf "%d %d\n", v, capped + 0 > meta }
    ' > "$_tmp" || :
  sort -t "$TAB" -k2,2 -k1,1 -u "$_tmp" > "$_tmp.s" 2>/dev/null && mv "$_tmp.s" "$_tmp" || rm -f "$_tmp.s"

  _visited=0
  _capped=0
  # shellcheck disable=SC2162
  read _visited _capped < "$_meta" 2>/dev/null || :
  : "${_visited:=0}" "${_capped:=0}"
  _fstat=$(cat "$_st" 2>/dev/null || printf '1')
  case "$_fstat" in ''|*[!0-9]*) _fstat=1 ;; esac
  _nerr=$(wc -l < "$_err" | tr -d ' ')

  _total=$(wc -l < "$_tmp" | tr -d ' ')
  _omitted=0
  if [ "$_total" -gt "$_max" ]; then
    _omitted=$((_total - _max))
  fi

  # erro de varredura: o status do find so conta como erro se NAO foi o SIGPIPE do nosso teto.
  _scanerr=0
  if [ "$_capped" -eq 1 ]; then
    [ "$_nerr" -eq 0 ] || _scanerr=$_nerr
  elif [ "$_fstat" -ne 0 ] || [ "$_nerr" -gt 0 ]; then
    _scanerr=$_nerr
    [ "$_scanerr" -gt 0 ] || _scanerr=1
  fi

  if [ "$_total" -gt "$_max" ]; then head -n "$_max" "$_tmp"; else cat "$_tmp"; fi

  _trunc=0
  if [ "$_capped" -eq 1 ]; then
    _lb=$_omitted
    [ "$_lb" -ge 1 ] || _lb=1
    _trunc=$((_trunc + _lb))
    printf 'init-inventory: teto de varredura excedido (visitados %s, teto %s = %s x --max-items): inventario PARCIAL, omitidos >= %s\n' \
      "$_visited" "$_vcap" "$SCAN_FACTOR" "$_lb" >&2
  else
    _trunc=$_omitted
  fi
  if [ "$_scanerr" -gt 0 ]; then
    _trunc=$((_trunc + _scanerr))
    _first=$(head -n 1 "$_err" 2>/dev/null | tr '\001-\037\177' '?')
    printf 'init-inventory: varredura com erro (find exit %s, %s erro(s) reportado(s)): inventario PARCIAL%s\n' \
      "$_fstat" "$_nerr" "${_first:+; primeiro: $_first}" >&2
  fi
  if [ "$_trunc" -gt 0 ]; then
    printf 'TRUNCATED\t%s\n' "$_trunc"
  fi
  return 0
}

# ---------------------------------------------------------------- main

[ $# -ge 1 ] || { _usage; exit 2; }
_sub=$1
shift

if [ "$_sub" = "__emit" ]; then
  cmd_emit "$@"
  exit 0
fi

_root=""
_max=$DEFAULT_MAX_ITEMS
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || _die_usage "--root exige valor"
      _root=$2; shift 2 ;;
    --max-items)
      [ $# -ge 2 ] || _die_usage "--max-items exige valor"
      _max=$2; shift 2 ;;
    -h|--help)
      _usage 2>&1; exit 0 ;;
    *)
      _die_usage "argumento desconhecido: $1" ;;
  esac
done

case "$_sub" in
  inventory) cmd_inventory "$_root" "$_max" ;;
  -h|--help) _usage 2>&1; exit 0 ;;
  *) _die_usage "subcomando desconhecido: $_sub" ;;
esac
