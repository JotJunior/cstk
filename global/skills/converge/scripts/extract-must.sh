#!/bin/sh
# extract-must.sh — extracao deterministica de principios MUST/NON-NEGOTIABLE
# de constitution.md para a skill `converge` (FR-002, FR-006).
#
# Ref: docs/specs/skill-converge/contracts/converge-interfaces.md §3
#      docs/specs/skill-converge/tasks.md tarefa 2.3
#      docs/specs/skill-converge/quickstart.md Scenario 15 (tarefa 1.4.3)
#
# USO:
#   extract-must.sh --constitution <constitution.md>
#
# Saida (stdout), TSV, uma linha por PRINCIPIO (nao por bullet individual)
# marcado MUST/NON-NEGOTIABLE:
#   <identificador>\t<titulo>
#
# EXIT:
#   0  sucesso (0+ linhas)
#   1  --constitution ausente (Scenario 15: escalada CRITICAL por violacao
#      de MUST fica indisponivel; demais criterios de severidade SEGUEM se
#      aplicando — quem chama este script NAO aborta a skill inteira so
#      porque este script retornou 1)
#   2  erro de uso
#
# --- Por que NAO assumir numeracao romana (I, II, III...) ---
# O template generico da skill `constitution` (templates/constitution.md)
# usa placeholders SEM numeracao ("### [PRINCIPLE_1_NAME]"), e o proprio
# principio-base OBRIGATORIO que a skill semeia em toda constituicao gerada
# (SKILL.md linha ~141) tambem NAO tem numeral: "### Veracidade de Dados —
# Zero Fabricacao (NON-NEGOTIABLE)". A numeracao romana (I, II, III...) e
# uma escolha estilistica QUE ESTE REPOSITORIO fez para a PROPRIA
# constitution.md — nao e garantida em constitution.md de outros projetos-
# alvo. Por isso a deteccao de heading abaixo aceita AMBOS os formatos
# (com ou sem prefixo curto de identificador), nunca fabrica uma numeracao
# que nao esteja literalmente no texto (Constitution VI).
#
# --- Regra de deteccao de principio MUST/NON-NEGOTIABLE ---
# Cada heading "### <texto>" e candidato. Dele, extrai (identificador,
# titulo):
#   - se <texto>, apos remover um eventual sufixo " (NON-NEGOTIABLE)",
#     comeca com um prefixo curto reconhecido ("I. ", "IV. ", "12. " —
#     numeral romano OU arabico seguido de ". ") esse prefixo vira o
#     identificador e o restante vira o titulo;
#   - senao, NAO HA identificador separado no texto-fonte — usar o proprio
#     titulo (limpo) como identificador tambem, em vez de inventar uma
#     numeracao que a fonte nao declara.
# O principio e EMITIDO se, e somente se, pelo menos um dos dois sinais
# (ambos puramente textuais, verificados empiricamente contra
# docs/constitution.md deste repo) estiver presente:
#   (a) o heading (antes de limpar) termina literalmente em
#       "(NON-NEGOTIABLE)" — convencao ensinada pela propria skill
#       `constitution` (SKILL.md) para o principio-base obrigatorio e
#       usada em todo principio NON-NEGOTIABLE deste repo; OU
#   (b) o corpo do principio (ate o proximo "### " ou EOF) contem uma linha
#       "**MUST:**" — cobre o caso de um principio com regras MUST reais
#       mas cujo HEADING nao leva o sufixo "(NON-NEGOTIABLE)" (ex.:
#       Principio III deste repo: "Formato Canonico de Skill..." tem bloco
#       "**MUST:**" mas o proprio Decision Framework da constituicao NAO o
#       lista entre os 4 principios NON-NEGOTIABLE "grandes" — mesmo assim,
#       uma violacao de um MUST explicito dentro dele e exatamente o que a
#       regra de severidade "Gap cuja causa viola principio MUST" (research
#       §Decision 3) precisa capturar).
# Principios so-SHOULD (ex.: Principio V deste repo, usa "**SHOULD:**" e
# nao tem sufixo NON-NEGOTIABLE) NAO satisfazem (a) nem (b) e sao excluidos
# corretamente.
#
# POSIX sh + awk (ferramentas POSIX canonicas, Constitution II). Zero eval
# sobre conteudo lido (SEC-1). Todas as variaveis quotadas. Sem Bash-isms.

set -eu

_EM_NAME="extract-must"

_em_usage() {
  cat <<'USAGE' >&2
Uso: extract-must.sh --constitution <constitution.md>

Saida: TSV "<identificador>\t<titulo>" em stdout, uma linha por principio
MUST/NON-NEGOTIABLE (nao por bullet individual).
Exit: 0 sucesso | 1 --constitution ausente | 2 erro de uso
USAGE
}

_em_die_usage() {
  printf '%s: %s\n' "$_EM_NAME" "$1" >&2
  exit 2
}

# ---------- Parse de flags ----------

_CONST=""

if [ "$#" -eq 0 ]; then
  _em_usage
  exit 2
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --constitution)
      [ "$#" -ge 2 ] || _em_die_usage "--constitution requer valor"
      _CONST=$2
      shift 2
      ;;
    -h | --help)
      _em_usage
      exit 0
      ;;
    *)
      _em_die_usage "flag desconhecida: $1"
      ;;
  esac
done

[ -n "$_CONST" ] || _em_die_usage "--constitution e obrigatorio"

if [ ! -f "$_CONST" ]; then
  printf '%s: constitution.md ausente: %s\n' "$_EM_NAME" "$_CONST" >&2
  exit 1
fi

# ---------- Extracao ----------
# Buffer-e-flush: ao encontrar um novo heading "### ", primeiro decide se
# o PRINCIPIO PENDENTE (o anterior) deve ser emitido (com base no que foi
# visto no corpo dele ate aqui), depois comeca a acumular o novo. O ultimo
# principio do arquivo e resolvido no bloco END.

awk '
  function flush() {
    if (pending != "" && (pending_nonneg || pending_hasmust)) {
      printf "%s\t%s\n", pending_id, pending_title
    }
  }

  /^### / {
    flush()

    raw = $0
    sub(/^### /, "", raw)

    pending = raw
    pending_nonneg = (raw ~ /\(NON-NEGOTIABLE\)$/)
    pending_hasmust = 0

    title = raw
    sub(/ *\(NON-NEGOTIABLE\)$/, "", title)

    if (title ~ /^[IVXLCDM]{1,6}\. /) {
      dp = index(title, ". ")
      pending_id = substr(title, 1, dp - 1)
      pending_title = substr(title, dp + 2)
    } else if (title ~ /^[0-9]{1,3}\. /) {
      dp = index(title, ". ")
      pending_id = substr(title, 1, dp - 1)
      pending_title = substr(title, dp + 2)
    } else {
      pending_id = title
      pending_title = title
    }
    next
  }

  /^\*\*MUST:\*\*/ {
    pending_hasmust = 1
    next
  }

  END { flush() }
' "$_CONST"
