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
#   extract-must.sh --constitution <constitution.md> --coverage
#
# Saida (stdout), TSV, uma linha por PRINCIPIO (nao por bullet individual)
# marcado MUST/NON-NEGOTIABLE:
#   <identificador>\t<titulo>
#
# Com --coverage, em vez do TSV imprime o relatorio de cobertura (ver
# §"Relatorio de cobertura" abaixo).
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
#       de regra MUST — cobre o caso de um principio com regras MUST reais
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
# --- Convencoes de marcacao de linha MUST reconhecidas (issue #171) ---
# ANTES desta correcao o sinal (b) casava UMA unica convencao — a linha
# comecando literalmente em "**MUST:**". Contra uma constitution.md que use
# bullet ("- MUST: ..."), formato igualmente valido e produzido por outros
# projetos, o parser lia ZERO regras e o `converge` reportava sucesso como
# se tivesse conferido tudo. Caso medido: 13 regras `- MUST:` no arquivo,
# 0 reconhecidas; o unico principio emitido casou pela via (a) — rotulo de
# heading — sem nenhuma regra lida.
#
# A regra agora aceita, com indentacao opcional e marcador de bullet
# opcional (`-`, `*`, `+`), com ou sem negrito:
#     **MUST:**   |   - MUST:   |   - **MUST:**   |   MUST:   |   * MUST NOT:
# Exigir os dois-pontos e deliberado: mantem "MUST" em prosa corrida fora do
# sinal (b), que e o que dava ao limiar original sua razao de existir.
#
# --- Relatorio de cobertura (--coverage, issue #171) ---
# O modo default responde "quais principios sao MUST", nunca "quanto do
# arquivo eu de fato li". Um gate que le uma fracao e reporta sucesso e pior
# que gate ausente, porque produz confianca. `--coverage` imprime:
#
#   fontes declaradas: <path>
#   ocorrencias da palavra MUST no arquivo (contagem independente): N
#   linhas de regra MUST reconhecidas pelo parser: M
#   principios emitidos: P
#   principios emitidos so por rotulo de heading (sem regra MUST lida): Q
#
# A 2a linha usa gramatica DELIBERADAMENTE diferente da do parser — conta a
# palavra `MUST` isolada (word boundary), sem nenhuma nocao de bullet,
# negrito ou dois-pontos. Se compartilhasse a gramatica do parser, a metrica
# seria autoconfirmatoria e voltaria a reportar 100%. Por ser independente,
# ela e um limite SUPERIOR grosseiro (conta MUST em prosa tambem): N > M nao
# prova lacuna, mas N >> M com M == 0 e exatamente o sintoma de #171.
#
# POSIX sh + awk (ferramentas POSIX canonicas, Constitution II). Zero eval
# sobre conteudo lido (SEC-1). Todas as variaveis quotadas. Sem Bash-isms.

set -eu

_EM_NAME="extract-must"

_em_usage() {
  cat <<'USAGE' >&2
Uso: extract-must.sh --constitution <constitution.md> [--coverage]

Saida: TSV "<identificador>\t<titulo>" em stdout, uma linha por principio
MUST/NON-NEGOTIABLE (nao por bullet individual).

--coverage: em vez do TSV, imprime o relatorio de cobertura (fontes lidas,
contagem independente de MUST, linhas reconhecidas pelo parser, principios
emitidos e quantos vieram so do rotulo do heading).
Exit: 0 sucesso | 1 --constitution ausente | 2 erro de uso
USAGE
}

_em_die_usage() {
  printf '%s: %s\n' "$_EM_NAME" "$1" >&2
  exit 2
}

# ---------- Parse de flags ----------

_CONST=""
_COVERAGE=0

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
    --coverage)
      _COVERAGE=1
      shift
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

# Regra de linha MUST, compartilhada pelo modo default e pelo --coverage
# (uma unica definicao — duas copias driftariam e a metrica de cobertura
# mediria um parser diferente do que roda).
_EM_MUST_RE='^[[:space:]]*([-*+][[:space:]]+)?[*]*MUST([[:space:]]+NOT)?[*]*[[:space:]]*:'

if [ "$_COVERAGE" = 1 ]; then
  # Contagem INDEPENDENTE: a palavra MUST isolada, sem nocao de bullet,
  # negrito ou dois-pontos. Gramatica de proposito diferente da do parser —
  # se compartilhasse, a metrica seria autoconfirmatoria.
  _em_words=$(grep -cE '(^|[^A-Za-z])MUST([^A-Za-z]|$)' "$_CONST" || :)
  # Contagem do PARSER: a mesma regex que o modo default usa (uma definicao
  # so — duas copias mediriam um parser diferente do que roda).
  _em_lines=$(grep -cE "$_EM_MUST_RE" "$_CONST" || :)

  # Classificacao de cada principio emitido: `with-must` (alguma regra MUST
  # foi de fato lida no corpo) x `heading-only` (entrou so pelo rotulo
  # "(NON-NEGOTIABLE)" do heading, sem nenhuma regra lida). Um unico passo —
  # os dois numeros derivam da MESMA saida.
  _em_classes=$(awk -v must_re="$_EM_MUST_RE" '
    function flush() {
      if (pending != "" && (pending_nonneg || pending_hasmust)) {
        print pending_hasmust ? "with-must" : "heading-only"
      }
    }
    /^### / {
      flush()
      raw = $0; sub(/^### /, "", raw)
      pending = raw
      pending_nonneg = (raw ~ /\(NON-NEGOTIABLE\)$/)
      pending_hasmust = 0
      next
    }
    $0 ~ must_re { pending_hasmust = 1; next }
    END { flush() }
  ' "$_CONST")

  _em_emitted=$(printf '%s' "$_em_classes" | grep -c . || :)
  _em_heading_only=$(printf '%s' "$_em_classes" | grep -c '^heading-only' || :)

  printf 'fontes declaradas: %s\n' "$_CONST"
  printf 'ocorrencias da palavra MUST no arquivo (contagem independente): %s\n' "$_em_words"
  printf 'linhas de regra MUST reconhecidas pelo parser: %s\n' "$_em_lines"
  printf 'principios emitidos: %s\n' "$_em_emitted"
  printf 'principios emitidos so por rotulo de heading (sem regra MUST lida): %s\n' "$_em_heading_only"

  # Sintoma exato de #171: o arquivo fala de MUST e o parser nao reconheceu
  # NENHUMA regra. Nesse estado o resultado do gate nao cobre as regras do
  # arquivo — dizer isso alto e o ponto do relatorio.
  if [ "$_em_words" -gt 0 ] && [ "$_em_lines" -eq 0 ]; then
    printf '%s: AVISO: o arquivo contem a palavra MUST mas NENHUMA linha de regra foi reconhecida — convencao de marcacao provavelmente nao suportada; o resultado NAO cobre as regras MUST deste arquivo.\n' "$_EM_NAME" >&2
  fi
  exit 0
fi

awk -v must_re="$_EM_MUST_RE" '
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

  $0 ~ must_re {
    pending_hasmust = 1
    next
  }

  END { flush() }
' "$_CONST"
