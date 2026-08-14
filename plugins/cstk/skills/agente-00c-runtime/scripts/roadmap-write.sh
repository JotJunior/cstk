#!/bin/sh
# roadmap-write.sh — produtor do artefato docs/roadmap.md (modo roadmap).
#
# Feature: roadmap-mode
# Ref:     docs/specs/roadmap-mode/contracts/roadmap-artifact.md §2, §3,
#          §8, §9.4
#          docs/specs/roadmap-mode/plan.md Fase B passo 6 (task 3.2)
#
# Unico ponto de escrita do artefato. Recebe o conteudo de entrada REDIGIDO
# pelo orquestrador dentro da onda `roadmap` (heading + metadado + prosa,
# gramatica de §2-§3 do contrato — SEM o wrapper de documento: apenas os
# blocos de entrada `### <ordem>. <short-name>` a incorporar nesta
# execucao), funde com o `docs/roadmap.md` preexistente (merge idempotente
# por short-name, §8), aplica `secrets-filter.sh` ANTES de gravar
# (fail-closed — CHK007, §9.4) e grava atomicamente.
#
# A validacao estrutural COMPLETA do artefato ja escrito (as 15 regras de
# §6) e responsabilidade de `pipeline.sh detect-completion --stage
# roadmap` (task 3.1) — caminho distinto e posterior a escrita, de
# proposito (plan.md Fase B passo 6). Este script NAO reimplementa essas
# regras; faz apenas a checagem minima necessaria para poder fazer o
# merge (heading reconhecivel).
#
# Subcomandos:
#   write --projeto-alvo-path PATH --input FILE
#         [--project-name NAME] [--context-paragraph-file FILE]
#         [--env-file FILE] [--ignore-file FILE]
#
#     Grava/atualiza PATH/docs/roadmap.md. Emite em stdout, uma linha por
#     entrada afetada (formato pipe-delimited, parseavel por `cut -d'|'`):
#       ENTRY|added|<short-name>|
#       ENTRY|altered|<short-name>|
#       ENTRY|obsolete|<short-name>|<motivo>
#     Entradas preexistentes intocadas nao produzem linha.
#
# Exit codes:
#   0  gravado com sucesso
#   1  falha de escrita/filtro (secrets-filter ausente, mktemp, mv, ...)
#   2  uso incorreto (flag obrigatoria ausente, --input sem entradas
#      reconheciveis)
#
# POSIX sh puro (grep/sed/awk/sort/cut/wc/tr/mktemp), sem jq — mesma
# disciplina de pipeline.sh::_pl_validate_roadmap (Principio II).

set -eu

_RW_NAME="roadmap-write"

# ---------- helpers de log ----------

_rw_selfdir() { cd -- "$(dirname -- "$0")" && pwd; }
_rw_log_sourced=0
if _rw_sd=$(_rw_selfdir 2>/dev/null) && [ -f "$_rw_sd/_log.sh" ]; then
  # shellcheck disable=SC1090
  . "$_rw_sd/_log.sh" && _rw_log_sourced=1
fi

_rw_err() {
  if [ "$_rw_log_sourced" = 1 ]; then
    log_err "$_RW_NAME: $*"
  else
    printf '%s: %s\n' "$_RW_NAME" "$*" >&2
  fi
}

_rw_die() {
  _rw_err "$1"
  exit "${2:-1}"
}

_rw_die_usage() {
  _rw_err "$1"
  exit 2
}

# ---------- helpers de texto ----------

# _rw_rstrip_blank_lines FILE — remove linhas em branco no FIM do arquivo
# (in-place). Usado para normalizar blocos de entrada antes de remontar.
_rw_rstrip_blank_lines() {
  awk '
    { lines[NR] = $0; n = NR }
    END {
      while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$1" > "$1.rstrip.tmp" && mv "$1.rstrip.tmp" "$1"
}

# _rw_trim_blank_edges FILE — imprime o conteudo sem linhas em branco nas
# extremidades (inicio E fim), preservando linhas em branco internas
# (contracts/roadmap-artifact.md §8.1: "trim de espaco em branco nas
# extremidades", sem normalizacao alem disso).
_rw_trim_blank_edges() {
  awk '
    { lines[NR] = $0; n = NR }
    END {
      start = 1; end = n
      while (start <= n && lines[start] ~ /^[[:space:]]*$/) start++
      while (end >= start && lines[end] ~ /^[[:space:]]*$/) end--
      for (i = start; i <= end; i++) print lines[i]
    }
  ' "$1"
}

# ---------- parsing de entradas (§3.1) ----------

# _rw_parse_entries FILE OUTDIR
# Popula OUTDIR/order.txt (short-names na ordem de aparicao) e, por
# entrada, OUTDIR/entries/<short-name>.md (bloco completo, heading
# incluso, ja com blank-lines finais removidas). Nao falha se FILE nao
# existir ou nao tiver headings — simplesmente produz saida vazia.
_rw_parse_entries() {
  _pe_file=$1
  _pe_out=$2
  mkdir -p "$_pe_out/entries"
  : > "$_pe_out/order.txt"

  [ -f "$_pe_file" ] || return 0

  _pe_heading_re='^###[[:space:]]+[1-9][0-9]*\.[[:space:]]+[a-z][a-z0-9-]*$'
  _pe_heading_lines=$(grep -nE "$_pe_heading_re" "$_pe_file" 2>/dev/null | cut -d: -f1) || :
  [ -n "$_pe_heading_lines" ] || return 0

  _pe_total=$(wc -l < "$_pe_file" | tr -d ' ')
  _pe_i=0
  for _pe_hl in $_pe_heading_lines; do
    _pe_i=$((_pe_i + 1))
    _pe_hd=$(sed -n "${_pe_hl}p" "$_pe_file")
    _pe_short=$(printf '%s' "$_pe_hd" | sed -n 's/^### [1-9][0-9]*\. \(.*\)$/\1/p')
    [ -n "$_pe_short" ] || continue

    _pe_next=$(printf '%s\n' "$_pe_heading_lines" | sed -n "$((_pe_i + 1))p")
    if [ -n "$_pe_next" ]; then _pe_end=$((_pe_next - 1)); else _pe_end=$_pe_total; fi

    sed -n "${_pe_hl},${_pe_end}p" "$_pe_file" > "$_pe_out/entries/$_pe_short.md"
    _rw_rstrip_blank_lines "$_pe_out/entries/$_pe_short.md"
    printf '%s\n' "$_pe_short" >> "$_pe_out/order.txt"
  done
}

# _rw_entry_ordem ENTRY_FILE -> ordem (do heading)
_rw_entry_ordem() {
  sed -n '1s/^### \([1-9][0-9]*\)\..*/\1/p' "$1"
}

# _rw_entry_field ENTRY_FILE PREFIX -> primeira linha que casa PREFIX,
# valor apos o prefixo (sed BRE; PREFIX ja deve vir escapado pelo caller).
_rw_entry_field() {
  sed -n "s/^$2//p" "$1" | head -1
}

# _rw_extract_desc_just ENTRY_FILE -> stdout: bloco Descricao+Justificativa
# (usado na comparacao de alteracao deliberada, §8.1).
_rw_extract_desc_just() {
  awk '
    /^\*\*Descricao\*\*: / { on = 1 }
    /^\*\*Justificativa\*\*: / { on = 1 }
    on { print }
  ' "$1"
}

# _rw_entry_has_obsolete ENTRY_FILE -> 0 se marcado, 1 senao
_rw_entry_has_obsolete() {
  grep -q '^- \*\*marcada-obsoleta\*\*: ' "$1"
}

_rw_entry_obsolete_motivo() {
  sed -n 's/^- \*\*marcada-obsoleta\*\*: //p' "$1" | head -1
}

# ---------- contexto preexistente (paragrafo livre, §2) ----------

# _rw_extract_existing_context ROADMAP_FILE -> paragrafo entre a linha
# '**Atualizado em**:' e o heading '## Ordem sugerida', trimado nas
# extremidades. Vazio se ausente/arquivo inexistente.
_rw_extract_existing_context() {
  _ec_f=$1
  [ -f "$_ec_f" ] || return 0
  _ec_upd=$(grep -n '^\*\*Atualizado em\*\*:' "$_ec_f" 2>/dev/null | head -1 | cut -d: -f1) || :
  _ec_os=$(grep -n '^##[[:space:]]*Ordem sugerida' "$_ec_f" 2>/dev/null | head -1 | cut -d: -f1) || :
  [ -n "$_ec_upd" ] && [ -n "$_ec_os" ] || return 0
  [ "$_ec_os" -gt "$((_ec_upd + 1))" ] || return 0
  sed -n "$((_ec_upd + 1)),$((_ec_os - 1))p" "$_ec_f" > "$_ec_f.ctx.tmp"
  _rw_trim_blank_edges "$_ec_f.ctx.tmp"
  rm -f -- "$_ec_f.ctx.tmp"
}

# ---------- subcomando: write ----------

_rw_cmd_write() {
  _pap=""
  _input=""
  _pname=""
  _ctxfile=""
  _env=""
  _ignore=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --projeto-alvo-path)     _pap=$2;    shift 2 ;;
      --input)                 _input=$2;  shift 2 ;;
      --project-name)          _pname=$2;  shift 2 ;;
      --context-paragraph-file) _ctxfile=$2; shift 2 ;;
      --env-file)               _env=$2;   shift 2 ;;
      --ignore-file)            _ignore=$2; shift 2 ;;
      *) _rw_die_usage "write: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_pap" ]   || _rw_die_usage "write: --projeto-alvo-path obrigatorio"
  [ -n "$_input" ] || _rw_die_usage "write: --input obrigatorio"
  [ -d "$_pap" ]   || _rw_die "write: --projeto-alvo-path nao existe: $_pap" 2
  [ -f "$_input" ] || _rw_die_usage "write: --input nao encontrado: $_input"

  _sf_script="$(_rw_selfdir)/secrets-filter.sh"
  [ -x "$_sf_script" ] \
    || _rw_die "write: secrets-filter.sh ausente/nao-executavel em $(_rw_selfdir) — abortando para nao gravar roadmap.md nao-filtrado" 1

  _docs_dir="$_pap/docs"
  _out="$_docs_dir/roadmap.md"
  mkdir -p "$_docs_dir" || _rw_die "write: falha ao criar $_docs_dir" 1

  _work=$(mktemp -d) || _rw_die "write: mktemp -d falhou" 1
  trap '_rw_cleanup_work' EXIT INT TERM
  _rw_cleanup_work() { rm -rf -- "$_work" 2>/dev/null || :; }

  # Fonte de comparacao (§8.1): le o preexistente ANTES de qualquer merge.
  _rw_parse_entries "$_out" "$_work/existing"
  _rw_parse_entries "$_input" "$_work/candidate"

  _cand_n=$(wc -l < "$_work/candidate/order.txt" 2>/dev/null | tr -d ' ')
  [ -n "$_cand_n" ] && [ "$_cand_n" -gt 0 ] \
    || _rw_die_usage "write: --input sem nenhuma entrada reconhecivel (heading '### <ordem>. <short-name>' esperado, contracts/roadmap-artifact.md §3.1)"

  # Nome do projeto: override explicito > preservado do doc existente >
  # derivado do basename do projeto-alvo.
  if [ -z "$_pname" ]; then
    if [ -f "$_out" ]; then
      _pname=$(sed -n '1s/^# Roadmap: \(.*\)$/\1/p' "$_out")
    fi
    [ -n "$_pname" ] || _pname=$(basename -- "$_pap")
  fi

  # Paragrafo de contexto: flag explicita > preservado do doc existente.
  if [ -n "$_ctxfile" ] && [ -f "$_ctxfile" ]; then
    _rw_trim_blank_edges "$_ctxfile" > "$_work/context.txt"
  else
    _rw_extract_existing_context "$_out" > "$_work/context.txt" 2>/dev/null || : > "$_work/context.txt"
  fi

  # Conjunto final = existentes (preservados, exceto quando redigidos de
  # novo pelo candidato) UNIAO candidatos novos. Identidade por
  # short-name (§8); nunca duplica.
  : > "$_work/final_order.txt"
  : > "$_work/report.txt"

  while IFS= read -r _short; do
    [ -n "$_short" ] || continue
    printf '%s\n' "$_short" >> "$_work/final_order.txt"
  done < "$_work/existing/order.txt"

  while IFS= read -r _short; do
    [ -n "$_short" ] || continue
    if ! grep -qxF "$_short" "$_work/final_order.txt" 2>/dev/null; then
      printf '%s\n' "$_short" >> "$_work/final_order.txt"
    fi
  done < "$_work/candidate/order.txt"

  # Resolve o conteudo final por short-name + classifica o evento.
  mkdir -p "$_work/final"
  while IFS= read -r _short; do
    [ -n "$_short" ] || continue
    _ex_f="$_work/existing/entries/$_short.md"
    _ca_f="$_work/candidate/entries/$_short.md"

    if [ -f "$_ca_f" ]; then
      cp "$_ca_f" "$_work/final/$_short.md"
      if [ -f "$_ex_f" ]; then
        _rw_extract_desc_just "$_ex_f" > "$_work/ex_dj.tmp" 2>/dev/null || : > "$_work/ex_dj.tmp"
        _rw_extract_desc_just "$_ca_f" > "$_work/ca_dj.tmp" 2>/dev/null || : > "$_work/ca_dj.tmp"
        _rw_trim_blank_edges "$_work/ex_dj.tmp" > "$_work/ex_dj_n.tmp"
        _rw_trim_blank_edges "$_work/ca_dj.tmp" > "$_work/ca_dj_n.tmp"
        if ! cmp -s "$_work/ex_dj_n.tmp" "$_work/ca_dj_n.tmp"; then
          printf 'ENTRY|altered|%s|\n' "$_short" >> "$_work/report.txt"
        fi
        rm -f -- "$_work/ex_dj.tmp" "$_work/ca_dj.tmp" "$_work/ex_dj_n.tmp" "$_work/ca_dj_n.tmp"
      else
        printf 'ENTRY|added|%s|\n' "$_short" >> "$_work/report.txt"
      fi
    else
      cp "$_ex_f" "$_work/final/$_short.md"
    fi

    if _rw_entry_has_obsolete "$_work/final/$_short.md"; then
      _motivo=$(_rw_entry_obsolete_motivo "$_work/final/$_short.md")
      printf 'ENTRY|obsolete|%s|%s\n' "$_short" "$_motivo" >> "$_work/report.txt"
    fi
  done < "$_work/final_order.txt"

  # ---------- render ----------
  _now=$(date -u +%Y-%m-%d)
  {
    printf '# Roadmap: %s\n\n' "$_pname"
    printf '**Gerado por**: /agente-00c (modo roadmap)\n'
    printf '**Atualizado em**: %s\n' "$_now"
    if [ -s "$_work/context.txt" ]; then
      printf '\n'
      cat "$_work/context.txt"
    fi
    printf '\n## Ordem sugerida\n\n'
    printf '| # | Feature | Depende de | Descricao (resumo) |\n'
    printf '|---|---------|------------|--------------------|\n'
    # Ordena por ordem numerica (fallback: ordem ausente vai por ultimo).
    while IFS= read -r _short; do
      [ -n "$_short" ] || continue
      _ord=$(_rw_entry_ordem "$_work/final/$_short.md")
      [ -n "$_ord" ] || _ord=999999
      printf '%s\t%s\n' "$_ord" "$_short"
    done < "$_work/final_order.txt" | sort -n -k1,1 > "$_work/sorted.tsv"

    while IFS="$(printf '\t')" read -r _ord _short; do
      [ -n "$_short" ] || continue
      _dep=$(_rw_entry_field "$_work/final/$_short.md" '- \*\*depende-de\*\*: ')
      [ -n "$_dep" ] || _dep='-'
      _desc=$(_rw_entry_field "$_work/final/$_short.md" '\*\*Descricao\*\*: ')
      printf '| %s | `%s` | %s | %s |\n' "$_ord" "$_short" "$_dep" "$_desc"
    done < "$_work/sorted.tsv"

    printf '\n## Features\n'
    while IFS="$(printf '\t')" read -r _ord _short; do
      [ -n "$_short" ] || continue
      printf '\n'
      cat "$_work/final/$_short.md"
    done < "$_work/sorted.tsv"
    printf '\n'
  } > "$_work/raw.md"

  # Filtragem de segredos ANTES da escrita — fail-closed (§9.4, CHK007).
  if ! "$_sf_script" scrub \
        ${_env:+--env-file "$_env"} ${_ignore:+--ignore-file "$_ignore"} \
        < "$_work/raw.md" > "$_work/scrubbed.md" 2>"$_work/sf.err"; then
    cat "$_work/sf.err" >&2 2>/dev/null || :
    _rw_die "write: secrets-filter scrub falhou — roadmap.md NAO gravado" 1
  fi

  # Escrita atomica: mktemp no MESMO diretorio do destino + mv.
  _tmpout=$(mktemp "$_docs_dir/.roadmap.md.XXXXXX") \
    || _rw_die "write: mktemp no destino falhou" 1
  cp "$_work/scrubbed.md" "$_tmpout" \
    || { rm -f -- "$_tmpout"; _rw_die "write: falha ao preparar escrita" 1; }
  mv -- "$_tmpout" "$_out" \
    || { rm -f -- "$_tmpout"; _rw_die "write: falha ao gravar $_out" 1; }

  cat "$_work/report.txt" 2>/dev/null || :
  trap - EXIT INT TERM
  _rw_cleanup_work
  return 0
}

# ---------- dispatch ----------

[ "$#" -gt 0 ] || _rw_die_usage "subcomando obrigatorio: write"

_RW_CMD=$1
shift

case "$_RW_CMD" in
  write) _rw_cmd_write "$@" ;;
  -h|--help|help)
    cat <<'HELP'
roadmap-write.sh write --projeto-alvo-path PATH --input FILE
                        [--project-name NAME]
                        [--context-paragraph-file FILE]
                        [--env-file FILE] [--ignore-file FILE]
HELP
    exit 0
    ;;
  *)
    _rw_die_usage "subcomando desconhecido: $_RW_CMD (valido: write)"
    ;;
esac
