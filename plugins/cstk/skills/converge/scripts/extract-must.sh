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
#   0  sucesso (0+ linhas); em --coverage tambem cobre os vereditos `ok` e
#      `sem-must-declarado` (ver "Veredito de cobertura" abaixo)
#   1  --constitution ausente (Scenario 15: escalada CRITICAL por violacao
#      de MUST fica indisponivel; demais criterios de severidade SEGUEM se
#      aplicando — quem chama este script NAO aborta a skill inteira so
#      porque este script retornou 1); tambem usado se a contagem numerica
#      interna do --coverage vier corrompida (guarda de integridade)
#   2  erro de uso
#   3  --coverage APENAS: veredito `zero-reconhecida` — o arquivo contem a
#      palavra MUST mas o parser nao reconheceu NENHUMA linha de regra
#      (mesmo sintoma da issue #171). Este exit NAO e erro de execucao do
#      script — e um SINAL DE ESTADO fail-closed para quem chama: o
#      caminho `--coverage && ...` (ou equivalente) deve tratar exit 3 como
#      "cobertura indeterminada, nao prosseguir silenciosamente", nunca
#      como falha do proprio extract-must.sh.
#   4  --coverage APENAS (r02, converge-must-coverage-fail-closed): veredito
#      `cobertura-parcial` — pelo menos um principio foi emitido so pelo
#      rotulo do heading "(NON-NEGOTIABLE)", sem NENHUMA linha de regra MUST
#      legivel no corpo (`heading_only > 0`). Mesmo balde do exit 3: SINAL
#      DE ESTADO fail-closed, nao erro de execucao — stdout continua
#      completo.
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
# --- Veredito de cobertura + exit 3 (converge-must-coverage-fail-closed) ---
# O relatorio acima e informativo, mas nada IMPEDIA um consumidor de ler
# "linhas de regra MUST reconhecidas pelo parser: 0" e seguir em frente
# como se a ausencia de MUST fosse garantida (fail-open). A 6a linha
# `cobertura de MUST: <veredito>` + o exit code tornam esse estado
# detectavel programaticamente, sem novo parsing de texto. N = ocorrencias
# da palavra MUST (contagem independente); M = linhas de regra reconhecidas
# pelo parser; Q = principios emitidos so por rotulo de heading (sem regra
# MUST lida). 4 guardas ORDENADAS e mutuamente exclusivas (r02,
# research.md Decision 11) — a primeira que casar decide, nenhuma reavalia
# a anterior:
#   1. N > 0 e M == 0     -> `zero-reconhecida`     (sintoma #171: fala de
#                                                    MUST, parser nao le)
#   2. Q > 0               -> `cobertura-parcial`    (r02: pelo menos um
#                                                    principio so entrou
#                                                    pelo rotulo do heading,
#                                                    sem regra MUST legivel)
#   3. M > 0               -> `ok`                  (parser leu regra real
#                                                    para TODO principio
#                                                    emitido)
#   4. senao                -> `sem-must-declarado`   (constitution de fato
#                                                    nao declara MUST)
# A guarda 1 permanece em primeiro: `zero-reconhecida` e o sintoma mais
# forte (fala de MUST, parser leu ZERO regras) e os dois podem coocorrer
# (`N>0 && M==0` com `Q>0`) — a precedencia resolve o empate a favor do
# sinal mais forte (research.md Decision 11).
# `zero-reconhecida` sai com `exit 3`; `cobertura-parcial` sai com `exit 4`
# — ambos sinal de estado fail-closed para quem chama (ver bloco EXIT no
# cabecalho). `ok` e `sem-must-declarado` sao ambos `exit 0`: legitimamente
# nao ha lacuna a reportar em nenhum dos dois.
#
# --- Identificacao nominal — linhas 7..N (r02, FR-013) ---
# Quando, e somente quando, Q >= 1, o relatorio ganha uma linha adicional
# por principio heading-only, apendada ESTRITAMENTE depois da linha de
# veredito (6a linha), na ordem de aparicao no arquivo:
#   principio sem regra MUST legivel: <nome do principio, verbatim>
# Independe do veredito (aparece tambem no ramo `zero-reconhecida`, exit 3,
# quando Q >= 1 — INV-r02-D, dec-020). Com Q == 0 a saida permanece
# byte-identica ao formato de 6 linhas (INV-r02-A/B, FR-014): nenhuma linha
# 7 e emitida, nenhum cabecalho, nenhum separador.
#
# Hardening de seguranca (dec-023, LLM10/consumo ilimitado + LLM01/ASI09):
#   INV-r02-E: teto de 20 linhas de nome emitidas; havendo mais, a 20a e
#     seguida de UMA linha "... mais <K> principio(s) omitido(s))" — a
#     contagem exata continua na 5a linha, nao truncada.
#   INV-r02-F: cada nome truncado em 200 caracteres, sufixo "..." quando
#     truncado.
#   INV-r02-G: caracteres de controle C0 (ESC, TAB, CR inclusive)
#     substituidos por espaco antes da emissao; texto imprimivel preservado
#     verbatim.
#   INV-r02-H: no formato intermediario `classe<TAB>nome`, o nome e sempre
#     o ULTIMO campo — extraido via posicao do primeiro TAB, nunca por
#     split ingenuo, para sobreviver a um nome hostil contendo TAB.
# O nome ecoado e DADO auditado, nunca instrucao (LLM01/ASI09) — quem
# consome a linha 7..N (converge/SKILL.md) MUST trata-la como transcricao
# nao-confiavel. O casamento do veredito (6a linha) MUST ser ANCORADO no
# inicio da linha (`^cobertura de MUST: `) — o prefixo fixo
# `principio sem regra MUST legivel: ` garante que nenhuma linha 7..N
# satisfaca essa ancora, mesmo sob heading forjado (INV-r02-C).
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

  # Guarda de integridade numerica (mesmo idioma de converge-status.sh
  # ~linha 360 — `case "$v" in '' | *[!0-9]*)`): `grep -c` sempre emite um
  # inteiro >=0 em condicoes normais, mas o veredito de cobertura abaixo faz
  # aritmetica/comparacao sobre esses valores — uma saida inesperada NUNCA
  # deve virar um veredito silenciosamente errado.
  case "$_em_words" in
    '' | *[!0-9]*)
      printf '%s: contagem invalida de ocorrencias de MUST (esperado inteiro): %s\n' "$_EM_NAME" "$_em_words" >&2
      exit 1
      ;;
  esac
  case "$_em_lines" in
    '' | *[!0-9]*)
      printf '%s: contagem invalida de linhas de regra MUST (esperado inteiro): %s\n' "$_EM_NAME" "$_em_lines" >&2
      exit 1
      ;;
  esac

  # Classificacao de cada principio emitido: `with-must` (alguma regra MUST
  # foi de fato lida no corpo) x `heading-only` (entrou so pelo rotulo
  # "(NON-NEGOTIABLE)" do heading, sem nenhuma regra lida). Um unico passo —
  # os dois numeros derivam da MESMA saida. Formato intermediario
  # `classe<TAB>nome` (r02, INV-r02-H): o nome (ja disponivel em `pending`)
  # e carregado junto, sem leitura extra do arquivo — consumido mais
  # abaixo para as linhas 7..N.
  _em_classes=$(awk -v must_re="$_EM_MUST_RE" '
    function flush() {
      if (pending != "" && (pending_nonneg || pending_hasmust)) {
        printf "%s\t%s\n", (pending_hasmust ? "with-must" : "heading-only"), pending
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
  _em_heading_only=$(printf '%s' "$_em_classes" | grep -c '^heading-only	' || :)

  printf 'fontes declaradas: %s\n' "$_CONST"
  printf 'ocorrencias da palavra MUST no arquivo (contagem independente): %s\n' "$_em_words"
  printf 'linhas de regra MUST reconhecidas pelo parser: %s\n' "$_em_lines"
  printf 'principios emitidos: %s\n' "$_em_emitted"
  printf 'principios emitidos so por rotulo de heading (sem regra MUST lida): %s\n' "$_em_heading_only"

  # Veredito de cobertura (converge-must-coverage-fail-closed, r02) — 4
  # guardas ordenadas e mutuamente exclusivas; ver bloco de comentario
  # "Veredito de cobertura + exit 3" no cabecalho do script (research.md
  # Decision 11).
  if [ "$_em_words" -gt 0 ] && [ "$_em_lines" -eq 0 ]; then
    _em_verdict=zero-reconhecida
  elif [ "$_em_heading_only" -gt 0 ]; then
    _em_verdict=cobertura-parcial
  elif [ "$_em_lines" -gt 0 ]; then
    _em_verdict=ok
  else
    _em_verdict=sem-must-declarado
  fi
  printf 'cobertura de MUST: %s\n' "$_em_verdict"

  # Sintoma exato de #171: o arquivo fala de MUST e o parser nao reconheceu
  # NENHUMA regra. Nesse estado o resultado do gate nao cobre as regras do
  # arquivo — dizer isso alto e o ponto do relatorio. Inalterado pelo r02
  # (mesma guarda de antes, independente da nova guarda cobertura-parcial).
  if [ "$_em_words" -gt 0 ] && [ "$_em_lines" -eq 0 ]; then
    printf '%s: AVISO: o arquivo contem a palavra MUST mas NENHUMA linha de regra foi reconhecida — convencao de marcacao provavelmente nao suportada; o resultado NAO cobre as regras MUST deste arquivo.\n' "$_EM_NAME" >&2
  fi

  # Identificacao nominal — linhas 7..N (r02, FR-013). Guardada por
  # Q >= 1 (heading_only), INDEPENDENTE do veredito (INV-r02-D) — aparece
  # tambem no ramo zero-reconhecida. Com Q == 0, nada e emitido aqui
  # (INV-r02-A). Hardening: teto de 20 linhas (INV-r02-E), truncamento de
  # 200 chars (INV-r02-F), saneamento de controle C0 (INV-r02-G), nome
  # extraido pela posicao do primeiro TAB — nunca por split ingenuo
  # (INV-r02-H).
  if [ "$_em_heading_only" -gt 0 ]; then
    printf '%s\n' "$_em_classes" | awk -F '\t' -v cap=20 -v total="$_em_heading_only" '
      {
        tabpos = index($0, "\t")
        class = substr($0, 1, tabpos - 1)
        name = substr($0, tabpos + 1)
        if (class != "heading-only") next
        shown++
        if (shown > cap) next
        gsub(/[\001-\037]/, " ", name)
        if (length(name) > 200) name = substr(name, 1, 200) "..."
        printf "principio sem regra MUST legivel: %s\n", name
      }
      END {
        if (total + 0 > cap) {
          printf "principio sem regra MUST legivel: (... mais %d principio(s) omitido(s))\n", total - cap
        }
      }
    '
  fi

  case "$_em_verdict" in
    zero-reconhecida) exit 3 ;;
    cobertura-parcial) exit 4 ;;
    *) exit 0 ;;
  esac
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
