#!/bin/sh
# briefing-items.sh — extrai itens de impacto Alto da tabela "## Itens a
# Definir" do briefing (FR-007, structural-decision-human-gate FASE 3).
#
# Ref: docs/specs/structural-decision-human-gate/spec.md FR-007
#      docs/specs/structural-decision-human-gate/data-model.md
#        §Entity Item a Definir (briefing), §Derivacao da chave,
#        §Distincao "sem itens" != "sem briefing" (finding M2)
#      docs/specs/structural-decision-human-gate/contracts/cli-structural-class.md
#        §Command: briefing-items.sh list-high
#      docs/specs/structural-decision-human-gate/research.md Decision 5
#
# Subcomandos:
#   briefing-items.sh list-high --briefing PATH
#       — Extrai os itens de impacto Alto da tabela "## Itens a Definir" do
#         briefing (canonico docs/briefing.md ou legado
#         docs/01-briefing-discovery/briefing.md — a resolucao do path e do
#         chamador, P6).
#       — Stdout: uma linha `item_key<TAB>item<TAB>dimensao` por item de
#         impacto Alto, seguida SEMPRE de uma linha final
#         `STATUS<TAB><token>` com <token> em
#         {ok, sem-itens-alto, tabela-irreconhecivel, briefing-ausente}
#         (data-model.md §Distincao "sem itens" != "sem briefing" — finding
#         M2: stdout vazio nao distingue "zero itens Alto" de "briefing
#         ausente"; o token torna a degradacao visivel, sem falhar a onda).
#       — item_key: funcao pura do texto (ja saneado, P7) da coluna Item,
#         ordem fixa: caixa baixa; [^a-z0-9] -> '-'; colapso de '-'
#         repetidos; trim de '-' nas pontas; truncagem do slug em 48 chars;
#         sufixo '-<cksum do texto integral JA NORMALIZADO, isto e, apos as
#         4 primeiras transformacoes e ANTES da truncagem>' (data-model.md
#         §Derivacao da chave). `cksum` — CRC, NAO hash criptografico —
#         declarado na mesma secao: suficiente para dedup de boa-fe, nao e
#         fronteira de autorizacao (essa e o status do BloqueioHumano, R6).
#       — Cada celula e saneada (NUL/TAB/CR/LF removidos, whitespace
#         colapsado) ANTES de compor a linha de saida (P7, finding L1 —
#         impede que uma celula com TAB embutido forje uma coluna extra no
#         TSV). NUL/TAB/CR sao removidos do CONTEUDO INTEIRO do arquivo
#         antes do parser ver qualquer linha — equivalente byte-a-byte a
#         remove-los por celula, e evita que o delimitador TAB usado na
#         nossa PROPRIA saida colida com algo vindo do briefing.
#       — So o impacto `Alto` e consumido (INV-B3); casado pelo TOKEN
#         INICIAL da celula, case-insensitive (P3 — cobre "Alto — define a
#         interface...", "Alto (parenteses)", nao so a celula inteira
#         "Alto").
#       — Heading casado ignorando caixa e espacos extras (P1); linha de
#         cabecalho e separadora da tabela markdown sao descartadas sem
#         validar conteudo (P2).
#       — Heading presente sem tabela reconhecivel (ex: lista numerada, ou
#         heading no fim do arquivo) => zero itens + aviso em stderr +
#         STATUS tabela-irreconhecivel (P4).
#       — Briefing ausente/ilegivel => zero itens + aviso em stderr +
#         STATUS briefing-ausente (P5).
#       — Heading "## Itens a Definir" ausente do briefing inteiro (secao
#         opcional simplesmente nao usada) => zero itens + STATUS
#         sem-itens-alto, SEM aviso — nao e degradacao, e uma estrutura de
#         briefing valida sem essa secao (distinto de P4, que exige o
#         heading estar PRESENTE).
#       — Exit 0 SEMPRE nesses 4 casos: quem decide o que fazer com o
#         estado degradado e o orquestrador chamador, nao o parser.
#
# Exit codes:
#   0 sucesso (inclusive os 4 casos de STATUS acima — nunca falha por parse)
#   2 uso incorreto (subcomando/flag ausente ou desconhecida)
#
# POSIX sh + awk/sed/tr/cksum/cut. Sem jq (INV-B1).

set -eu

_BI_NAME="briefing-items"

_bi_die_usage() {
  printf '%s: %s\n' "$_BI_NAME" "$1" >&2
  exit 2
}

_bi_warn() {
  printf '%s: %s\n' "$_BI_NAME" "$1" >&2
}

# _bi_sanitize_cell TEXT -> stdout: remove NUL/TAB/CR/LF, colapsa whitespace
# remanescente, trim de bordas (P7, finding L1).
_bi_sanitize_cell() {
  printf '%s' "$1" \
    | tr -d '\000\011\015\012' \
    | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ *//' -e 's/ *$//'
}

# _bi_derive_key TEXT -> stdout: item_key (data-model.md §Derivacao da
# chave). TEXT ja deve vir saneado (_bi_sanitize_cell aplicado antes).
_bi_derive_key() {
  _bik_norm=$(printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-*//' -e 's/-*$//')
  _bik_slug=$(printf '%s' "$_bik_norm" | cut -c1-48)
  _bik_cksum=$(printf '%s' "$_bik_norm" | cksum | awk '{print $1}')
  printf '%s-%s' "$_bik_slug" "$_bik_cksum"
}

_bi_cmd_list_high() {
  _bi_briefing=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --briefing) _bi_briefing=$2; shift 2 ;;
      *) _bi_die_usage "list-high: flag desconhecida: $1" ;;
    esac
  done
  [ -n "$_bi_briefing" ] || _bi_die_usage "list-high: --briefing obrigatorio"

  if [ ! -f "$_bi_briefing" ] || [ ! -r "$_bi_briefing" ]; then
    _bi_warn "list-high: briefing ausente ou ilegivel: $_bi_briefing"
    printf 'STATUS\tbriefing-ausente\n'
    return 0
  fi

  _bi_tmp=$(mktemp) || {
    _bi_warn "list-high: mktemp falhou; degradando para tabela-irreconhecivel"
    printf 'STATUS\ttabela-irreconhecivel\n'
    return 0
  }
  trap 'rm -f "$_bi_tmp"' EXIT INT TERM

  # tr remove NUL/TAB/CR do CONTEUDO INTEIRO antes do awk — ver comentario
  # de cabecalho (P7/finding L1). O awk faz o parsing da tabela e decide o
  # estado (absent|broken|parsed), emitindo:
  #   D\t<item>\t<dimensao>   — uma linha por item de impacto Alto
  #   S\t<absent|broken|parsed>  — sempre a ultima linha
  tr -d '\000\011\015' < "$_bi_briefing" | awk '
    BEGIN { stage = 0; state = "absent" }
    {
      line = $0
      trimmed = line
      gsub(/^[ \t]+/, "", trimmed)
      gsub(/[ \t]+$/, "", trimmed)

      if (stage == 0) {
        norm = tolower(trimmed)
        gsub(/[ \t]+/, " ", norm)
        if (norm == "## itens a definir") {
          stage = 1
          state = "broken"
        }
        next
      }
      if (stage == 9) { next }

      if (stage == 1) {
        if (trimmed == "") { next }
        if (substr(trimmed, 1, 1) == "|") { stage = 2; next }
        stage = 9
        next
      }

      if (stage == 2) {
        if (substr(trimmed, 1, 1) == "|") { stage = 3; state = "parsed"; next }
        stage = 9
        next
      }

      if (stage == 3) {
        if (substr(trimmed, 1, 1) != "|") { stage = 9; next }
        row = trimmed
        sub(/^\|/, "", row)
        sub(/\|$/, "", row)
        n = split(row, cells, "|")
        item = (1 in cells) ? cells[1] : ""
        dim  = (2 in cells) ? cells[2] : ""
        imp  = (3 in cells) ? cells[3] : ""
        gsub(/^[ \t]+/, "", item); gsub(/[ \t]+$/, "", item)
        gsub(/^[ \t]+/, "", dim);  gsub(/[ \t]+$/, "", dim)
        gsub(/^[ \t]+/, "", imp);  gsub(/[ \t]+$/, "", imp)
        impl = tolower(imp)
        if (impl == "alto" || match(impl, /^alto[^a-z0-9]/)) {
          printf "D\t%s\t%s\n", item, dim
        }
        next
      }
    }
    END {
      printf "S\t%s\n", state
    }
  ' > "$_bi_tmp"

  _bi_count=0
  _bi_state="absent"
  while IFS="$(printf '\t')" read -r _bi_tag _bi_f2 _bi_f3; do
    case "$_bi_tag" in
      D)
        _bi_item=$(_bi_sanitize_cell "$_bi_f2")
        [ -n "$_bi_item" ] || continue
        _bi_dim=$(_bi_sanitize_cell "$_bi_f3")
        _bi_key=$(_bi_derive_key "$_bi_item")
        printf '%s\t%s\t%s\n' "$_bi_key" "$_bi_item" "$_bi_dim"
        _bi_count=$((_bi_count + 1))
        ;;
      S)
        _bi_state=$_bi_f2
        ;;
    esac
  done < "$_bi_tmp"

  rm -f "$_bi_tmp"
  trap - EXIT INT TERM

  case "$_bi_state" in
    broken)
      _bi_warn "list-high: heading 'Itens a Definir' presente mas tabela nao reconhecivel: $_bi_briefing"
      printf 'STATUS\ttabela-irreconhecivel\n'
      ;;
    parsed)
      if [ "$_bi_count" -gt 0 ]; then
        printf 'STATUS\tok\n'
      else
        printf 'STATUS\tsem-itens-alto\n'
      fi
      ;;
    *)
      printf 'STATUS\tsem-itens-alto\n'
      ;;
  esac
}

_bi_main() {
  [ "$#" -ge 1 ] || _bi_die_usage "subcomando obrigatorio: list-high"
  _bi_sub=$1
  shift
  case "$_bi_sub" in
    list-high) _bi_cmd_list_high "$@" ;;
    *) _bi_die_usage "subcomando desconhecido: $_bi_sub" ;;
  esac
}

_bi_main "$@"
