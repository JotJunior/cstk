#!/bin/sh
# roadmap-status.sh — cruzamento de portfolio: docs/roadmap.md x docs/specs/.
#
# Feature: roadmap-mode
# Ref:     docs/specs/roadmap-mode/contracts/cli-roadmap-mode.md §6
#          docs/specs/roadmap-mode/contracts/roadmap-artifact.md §5, §9.2
#          docs/specs/roadmap-mode/plan.md Fase B passo 7 (task 3.3)
#          docs/specs/roadmap-mode/research.md Decision 7
#
# Para cada entrada de docs/roadmap.md, deriva o status de execucao contra
# o portfolio real de specs (contracts/roadmap-artifact.md §5) e emite uma
# tabela markdown (default) ou JSON-lines (--json). POSIX puro, sem `jq`
# (Principio II; paridade com aggregate.sh, mesmo diretorio).
#
# Uso:
#   roadmap-status.sh [--roadmap PATH] [--specs-dir DIR] [--json]
#   roadmap-status.sh -h | --help
#
# Flags:
#   --roadmap PATH    artefato a cruzar (default: docs/roadmap.md)
#   --specs-dir DIR   portfolio a inspecionar (default: docs/specs)
#   --json            emite JSON-lines em vez de tabela markdown
#
# Validacao fail-closed na leitura (§9.2) — este script le QUALQUER
# docs/roadmap.md, inclusive um jamais gateado pelo pipeline.sh:
#   - short-name fora de ^[a-z][a-z0-9-]*$ ou > 64 chars -> entrada
#     inteira descartada, aviso em stderr
#   - token de depende-de invalido (apos remover crases) -> token
#     descartado (entrada permanece), aviso em stderr, nunca emitido bruto
#
# Exit codes:
#   0  sucesso (inclusive roadmap valido com 0 entradas -> aviso stderr)
#   1  roadmap AUSENTE
#   2  uso incorreto
#   3  roadmap PRESENTE mas invalido/ilegivel (sem header '# Roadmap')

set -eu

_RS_NAME="roadmap-status"
DEFAULT_ROADMAP="docs/roadmap.md"
DEFAULT_SPECS_DIR="docs/specs"

ROADMAP=""
SPECS_DIR=""
JSON_ONLY=false

print_usage() {
  cat <<'EOF'
Uso: roadmap-status.sh [--roadmap PATH] [--specs-dir DIR] [--json]

Cruza as entradas de docs/roadmap.md com o portfolio real de
docs/specs/, derivando o status de execucao de cada entrada
(contracts/roadmap-artifact.md §5).

Opcoes:
  --roadmap PATH    Artefato a cruzar (default: docs/roadmap.md)
  --specs-dir DIR   Portfolio a inspecionar (default: docs/specs)
  --json            Emite JSON-lines (uma linha por entrada) em vez de
                     tabela markdown
  -h, --help        Mostra esta ajuda

Exit codes: 0 sucesso; 1 roadmap ausente; 2 uso incorreto;
3 roadmap presente mas invalido/ilegivel.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --roadmap)
      [ $# -ge 2 ] || { printf '%s: --roadmap exige valor\n' "$_RS_NAME" >&2; exit 2; }
      ROADMAP=$2; shift 2 ;;
    --specs-dir)
      [ $# -ge 2 ] || { printf '%s: --specs-dir exige valor\n' "$_RS_NAME" >&2; exit 2; }
      SPECS_DIR=$2; shift 2 ;;
    --json)
      JSON_ONLY=true; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      printf '%s: flag desconhecida: %s\n' "$_RS_NAME" "$1" >&2
      print_usage >&2
      exit 2 ;;
  esac
done

[ -n "$ROADMAP" ]   || ROADMAP="$DEFAULT_ROADMAP"
[ -n "$SPECS_DIR" ] || SPECS_DIR="$DEFAULT_SPECS_DIR"

if [ ! -f "$ROADMAP" ]; then
  printf '%s: roadmap nao encontrado: %s\n' "$_RS_NAME" "$ROADMAP" >&2
  exit 1
fi

# Regra 1 de contracts/roadmap-artifact.md §6: primeira linha nao-vazia
# casa '^#[[:space:]]+Roadmap'. Ausencia = documento ilegivel/invalido
# (distinto de "ausente" — sinal de corrupcao, nao de estado normal).
if ! head -5 "$ROADMAP" 2>/dev/null | grep -Eq '^#[[:space:]]+Roadmap'; then
  printf '%s: roadmap presente mas invalido/ilegivel (sem header "# Roadmap"): %s\n' \
    "$_RS_NAME" "$ROADMAP" >&2
  exit 3
fi

# ==== Helpers de escape (paridade com aggregate.sh) ====

# json_escape STRING -> imprime string com " e \ escapados.
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# md_escape STRING -> imprime string com '|' substituido por '/'.
md_escape() {
  printf '%s' "$1" | sed 's/|/\//g'
}

# ==== Derivacao de status (contracts/roadmap-artifact.md §5) ====

# derive_status SHORT_NAME -> nao-iniciada | em-andamento | concluida
derive_status() {
  _ds_short="$1"
  _ds_dir="$SPECS_DIR/$_ds_short"
  [ -d "$_ds_dir" ] || { printf 'nao-iniciada'; return 0; }
  _ds_tasks="$_ds_dir/tasks.md"
  [ -f "$_ds_tasks" ] || { printf 'em-andamento'; return 0; }
  if grep -Eq '^[[:space:]]*-[[:space:]]*\[[ ~]\]' "$_ds_tasks" 2>/dev/null; then
    printf 'em-andamento'
  else
    printf 'concluida'
  fi
}

# ==== Parsing + validacao fail-closed (§9.2) ====

_HEADING_RE='^###[[:space:]]+[1-9][0-9]*\.[[:space:]]+[a-z][a-z0-9-]*$'
_heading_lines=$(grep -nE "$_HEADING_RE" "$ROADMAP" 2>/dev/null | cut -d: -f1) || :

_out_json=""
_out_md=""
_count=0

if [ -n "$_heading_lines" ]; then
  _total_lines=$(wc -l < "$ROADMAP" | tr -d ' ')
  _i=0
  for _hl in $_heading_lines; do
    _i=$((_i + 1))
    _hd=$(sed -n "${_hl}p" "$ROADMAP")
    _ordem=$(printf '%s' "$_hd" | sed -n 's/^### \([1-9][0-9]*\)\..*/\1/p')
    _short=$(printf '%s' "$_hd" | sed -n 's/^### [1-9][0-9]*\. \(.*\)$/\1/p')
    [ -n "$_short" ] || continue

    # §9.2: short-name MUST casar ^[a-z][a-z0-9-]*$ e comprimento <= 64.
    # O padrao de heading ja restringe a classe de caractere; o comprimento
    # exige checagem explicita.
    _len=$(printf '%s' "$_short" | wc -c | tr -d ' ')
    _len=$((_len - 1))  # wc -c inclui o \n do printf; normaliza
    if [ "$_len" -gt 64 ]; then
      printf '%s: entrada descartada — short-name > 64 chars: %s\n' \
        "$_RS_NAME" "$_short" >&2
      continue
    fi

    _next=$(printf '%s\n' "$_heading_lines" | sed -n "$((_i + 1))p")
    if [ -n "$_next" ]; then _end=$((_next - 1)); else _end=$_total_lines; fi
    _block=$(sed -n "${_hl},${_end}p" "$ROADMAP")

    _dep_raw=$(printf '%s\n' "$_block" | sed -n 's/^- \*\*depende-de\*\*: //p' | head -1)
    _deps_valid=""
    if [ -n "$_dep_raw" ] && [ "$_dep_raw" != "-" ]; then
      _dep_tokens=$(printf '%s' "$_dep_raw" | tr -d '`' | tr ',' '\n' | sed 's/^ *//; s/ *$//')
      for _tok in $_dep_tokens; do
        [ -n "$_tok" ] || continue
        if printf '%s' "$_tok" | grep -Eq '^[a-z][a-z0-9-]*$'; then
          if [ -z "$_deps_valid" ]; then _deps_valid="$_tok"; else _deps_valid="$_deps_valid,$_tok"; fi
        else
          # §9.2: token invalido descartado — NUNCA emitido bruto.
          printf '%s: token de depende-de descartado (entrada %s): valor invalido apos remover crases\n' \
            "$_RS_NAME" "$_short" >&2
        fi
      done
    fi

    _status=$(derive_status "$_short")

    _short_j=$(json_escape "$_short")
    _status_j=$(json_escape "$_status")
    _deps_json="[]"
    if [ -n "$_deps_valid" ]; then
      _deps_json="["
      _first=1
      _old_ifs=$IFS
      IFS=,
      for _d in $_deps_valid; do
        _d_j=$(json_escape "$_d")
        if [ "$_first" -eq 1 ]; then _deps_json="${_deps_json}\"${_d_j}\""; _first=0
        else _deps_json="${_deps_json},\"${_d_j}\""; fi
      done
      IFS=$_old_ifs
      _deps_json="${_deps_json}]"
    fi

    _json_line=$(printf '{"ordem":%s,"short_name":"%s","status":"%s","depende_de":%s}' \
      "$_ordem" "$_short_j" "$_status_j" "$_deps_json")

    _short_m=$(md_escape "$_short")
    _dep_m="-"
    [ -n "$_deps_valid" ] && _dep_m=$(md_escape "$_deps_valid")

    _md_line=$(printf '| %s | %s | %s | %s |' "$_ordem" "$_short_m" "$_status" "$_dep_m")

    _out_json="${_out_json}${_json_line}
"
    _out_md="${_out_md}${_md_line}
"
    _count=$((_count + 1))
  done
fi

if [ "$_count" -eq 0 ]; then
  printf '%s: roadmap valido sem nenhuma entrada reconhecivel (0 entradas): %s\n' \
    "$_RS_NAME" "$ROADMAP" >&2
  exit 0
fi

if $JSON_ONLY; then
  printf '%s' "$_out_json"
  exit 0
fi

cat <<EOF
## Cruzamento de Portfolio (roadmap)

**Roadmap:** $ROADMAP
**Specs-dir:** $SPECS_DIR
**Entradas:** $_count

| Ordem | Feature | Status | Depende de |
|-------|---------|--------|------------|
EOF
printf '%s' "$_out_md"
exit 0
