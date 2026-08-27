# manifest-coverage.sh — primitivas de validacao/formatacao para a secao
# "Shadowed Scope" do `cstk doctor` (feature doctor-shadowed-scope).
#
# Le `./.claude/<kind>/.cstk-manifest` (o manifesto de ESCOPO DE PROJETO,
# nao o global) para comparar contra o catalogo instalado. Esse arquivo e
# UNTRUSTED (contrato doctor-shadowed-scope-output.md §7): pode ser
# versionado por um repositorio de terceiro e lido ao rodar `cstk doctor`
# dentro dele. Toda funcao aqui trata o conteudo do manifesto como entrada
# hostil.
#
# Funcoes exportadas:
#   manifest_name_is_safe <name>
#     -> exit 0 nome seguro / 1 inseguro. Gate obrigatorio (R1) antes de
#        qualquer uso do valor como componente de path.
#   manifest_scrub_text <valor>
#     -> texto sanitizado em stdout (R3): remove controles C0/DEL, trunca
#        a 64 chars. Usar SEMPRE antes de imprimir name/toolkit_version.
#   manifest_record_is_valid <line>
#     -> exit 0 valido / 1 invalido. 4 campos TAB, campos 1-3 nao vazios,
#        campo 3 = sha256 hex (64), campo 1 aprovado por
#        manifest_name_is_safe. CR terminal removido antes de validar.
#   manifest_count_data_lines <path>
#     -> inteiro em stdout. Denominador: linhas nao-vazias, nao-comentario.
#        Arquivo ausente = 0, exit 0. Robusto a ausencia de newline final.
#   manifest_coverage_line <path> <D> <N> <state> [<motivo>]
#     -> linha de cobertura formatada em stdout (contrato §3.4). <motivo>
#        so e usado quando <state> = unreadable.
#   manifest_within_cap <path>
#     -> exit 0 dentro do teto R5 / 1 excedido (motivo teto-excedido).
#        Cap CONFIGURAVEL (dec-037): CSTK_MANIFEST_MAX_LINES (default
#        10000) e CSTK_MANIFEST_MAX_LINE_BYTES (default 4096). Imposto por
#        LEITURA LIMITADA (head -c do orcamento total ANTES de qualquer
#        processamento) — nunca por checagem de comprimento a posteriori
#        (contrato §7 nota normativa R5): um registro de 50 MB sem `\n`
#        NUNCA e materializado por inteiro.
#   manifest_count_recognized <path>
#     -> "D N" em stdout (D=denominador, N=numerador de linhas
#        'recognized' via manifest_record_is_valid). Helper interno
#        (alem das 5 funcoes do contrato §5 — dec pendente, ver Decisao
#        na execucao) que exercita R4: o laco de iteracao roda sob
#        `set -f` (subshell, restaurado ao sair), precedente literal
#        `cli/lib/recall.sh fts_query_escape()` — impede que uma linha de
#        dados contendo `*` sofra pathname expansion e infle o numerador
#        acima do denominador. Chama manifest_within_cap ANTES de iterar;
#        se excedido, imprime "CAP-EXCEEDED" e devolve exit 1 (caller
#        trata como coverage_state=unreadable, motivo=teto-excedido).
#
# POSIX sh puro. Deps: awk, tr, cut, head, wc, printf.

if [ -n "${_CSTK_MANIFEST_COVERAGE_LOADED:-}" ]; then
  return 0 2>/dev/null
fi
_CSTK_MANIFEST_COVERAGE_LOADED=1

# manifest_name_is_safe <name> -> exit 0 seguro / 1 inseguro (R1).
# Casa ^[A-Za-z0-9._-]+$; rejeita "..", "/", "\", "-" inicial, vazio,
# comprimento > 64.
manifest_name_is_safe() {
  if [ "$#" -ne 1 ]; then
    return 1
  fi
  _mns_name=$1
  [ -n "$_mns_name" ] || return 1
  [ "${#_mns_name}" -le 64 ] || return 1
  case "$_mns_name" in
    -*) return 1 ;;
  esac
  case "$_mns_name" in
    *..*) return 1 ;;
    */*) return 1 ;;
    *\\*) return 1 ;;
  esac
  case "$_mns_name" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# manifest_scrub_text <valor> -> texto sanitizado em stdout (R3).
# Remove bytes de controle C0/DEL ([:cntrl:] em locale C == 0x00-0x1F +
# 0x7F) e trunca a 64 caracteres. LC_ALL=C evita interpretacao multibyte
# tanto no tr quanto no cut.
manifest_scrub_text() {
  if [ "$#" -ne 1 ]; then
    printf ''
    return 0
  fi
  printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]' | LC_ALL=C cut -c1-64
}

# manifest_record_is_valid <line> -> exit 0 valido / 1 invalido.
# Exatamente 4 campos TAB; campos 1-3 nao vazios; campo 3 casa
# ^[0-9a-f]{64}$; campo 1 aprovado por manifest_name_is_safe. `\r`
# terminal removido antes de validar (tolerancia a manifesto CRLF).
manifest_record_is_valid() {
  if [ "$#" -ne 1 ]; then
    return 1
  fi
  _mriv_cr=$(printf '\r')
  _mriv_line=${1%"$_mriv_cr"}

  _mriv_nf=$(printf '%s' "$_mriv_line" | awk -F'\t' '{print NF}')
  [ "$_mriv_nf" -eq 4 ] || return 1

  _mriv_f1=$(printf '%s' "$_mriv_line" | awk -F'\t' '{print $1}')
  _mriv_f2=$(printf '%s' "$_mriv_line" | awk -F'\t' '{print $2}')
  _mriv_f3=$(printf '%s' "$_mriv_line" | awk -F'\t' '{print $3}')

  [ -n "$_mriv_f1" ] || return 1
  [ -n "$_mriv_f2" ] || return 1
  [ -n "$_mriv_f3" ] || return 1

  case "$_mriv_f3" in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#_mriv_f3}" -eq 64 ] || return 1

  manifest_name_is_safe "$_mriv_f1" || return 1

  return 0
}

# manifest_count_data_lines <path> -> inteiro em stdout (denominador).
# Linha nao-vazia, nao-comentario ("#" inicial). Arquivo ausente = 0,
# exit 0. Robusto a ausencia de newline final no ultimo registro (awk
# processa o ultimo record parcial normalmente, ao contrario de
# `grep -c` sobre stdin em alguns shells).
manifest_count_data_lines() {
  if [ "$#" -ne 1 ]; then
    printf 'manifest-coverage: manifest_count_data_lines espera 1 argumento (path)\n' >&2
    return 2
  fi
  if [ ! -f "$1" ]; then
    printf '0\n'
    return 0
  fi
  awk '
    /^[[:space:]]*$/ { next }
    /^#/ { next }
    { n++ }
    END { print n + 0 }
  ' "$1"
}

# manifest_within_cap <path> -> exit 0 dentro do teto R5 / 1 excedido.
# Cap configuravel (dec-037): CSTK_MANIFEST_MAX_LINES (default 10000),
# CSTK_MANIFEST_MAX_LINE_BYTES (default 4096). Le no MAXIMO
# (max_lines+1) * max_line_bytes bytes via `head -c` ANTES de qualquer
# processamento — bound de memoria pelo TETO, nunca pelo tamanho do
# arquivo de entrada (nota normativa contrato §7 R5: um registro de
# varios GB sem `\n` nunca e materializado por inteiro).
manifest_within_cap() {
  if [ "$#" -ne 1 ]; then
    printf 'manifest-coverage: manifest_within_cap espera 1 argumento (path)\n' >&2
    return 2
  fi
  if [ ! -f "$1" ]; then
    return 0
  fi
  _mwc_max_lines=${CSTK_MANIFEST_MAX_LINES:-10000}
  _mwc_max_bytes=${CSTK_MANIFEST_MAX_LINE_BYTES:-4096}
  _mwc_budget=$(( (_mwc_max_lines + 1) * _mwc_max_bytes ))

  head -c "$_mwc_budget" -- "$1" 2>/dev/null | awk -v maxb="$_mwc_max_bytes" -v maxl="$_mwc_max_lines" '
    {
      if (length($0) > maxb) { exceeded=1; exit }
      n++
      if (n > maxl) { exceeded=1; exit }
    }
    END { if (exceeded) exit 1; exit 0 }
  '
}

# manifest_count_recognized <path> -> "D N" em stdout. Ver docstring do
# cabecalho (R4: set -f isolado em subshell durante a iteracao).
manifest_count_recognized() {
  if [ "$#" -ne 1 ]; then
    printf 'manifest-coverage: manifest_count_recognized espera 1 argumento (path)\n' >&2
    return 2
  fi
  if ! manifest_within_cap "$1"; then
    printf 'CAP-EXCEEDED\n'
    return 1
  fi
  _mcr_d=$(manifest_count_data_lines "$1")
  _mcr_n=$(
    set -f
    _mcr_ifs=$IFS
    IFS='
'
    _mcr_n_inner=0
    # shellcheck disable=SC2013 # for-in-command deliberado: IFS=newline +
    # set -f (R4) isolam este laco de word-splitting e pathname expansion;
    # `while read` percorreria os mesmos dados sem ganho de seguranca aqui.
    for _mcr_line in $(awk '/^[[:space:]]*$/ { next } /^#/ { next } { print }' "$1" 2>/dev/null); do
      IFS=$_mcr_ifs
      if manifest_record_is_valid "$_mcr_line"; then
        _mcr_n_inner=$((_mcr_n_inner + 1))
      fi
      IFS='
'
    done
    IFS=$_mcr_ifs
    printf '%s' "$_mcr_n_inner"
  )
  printf '%s %s\n' "$_mcr_d" "$_mcr_n"
}

# manifest_coverage_line <path> <D> <N> <state> [<motivo>]
# -> linha de cobertura formatada em stdout (contrato §3.4). <motivo> so
# e consumido quando <state> = unreadable.
manifest_coverage_line() {
  if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
    printf 'manifest-coverage: manifest_coverage_line espera 4-5 argumentos (path D N state [motivo])\n' >&2
    return 2
  fi
  _mcl_path=$1
  _mcl_d=$2
  _mcl_n=$3
  _mcl_state=$4
  _mcl_motivo=${5:-motivo-desconhecido}

  case "$_mcl_state" in
    full|partial)
      _mcl_u=$((_mcl_d - _mcl_n))
      printf '    %s    [%s]  registros no arquivo: %s  interpretados: %s  nao interpretados: %s\n' \
        "$_mcl_path" "$_mcl_state" "$_mcl_d" "$_mcl_n" "$_mcl_u"
      ;;
    unreadable)
      printf '    %s    [unreadable]  registros no arquivo: ?  interpretados: ?  motivo: %s\n' \
        "$_mcl_path" "$_mcl_motivo"
      ;;
    absent)
      printf '    %s    [absent]  registros no arquivo: 0  interpretados: 0  nao interpretados: 0\n' \
        "$_mcl_path"
      ;;
    inconsistent)
      printf '    %s  [inconsistent]  registros no arquivo: %s  interpretados: %s  (N > D: inconsistencia interna do contador — reporte este caso)\n' \
        "$_mcl_path" "$_mcl_d" "$_mcl_n"
      ;;
    *)
      printf 'manifest-coverage: coverage_state desconhecido: %s\n' "$_mcl_state" >&2
      return 2
      ;;
  esac
}
