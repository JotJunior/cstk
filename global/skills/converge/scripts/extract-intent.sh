#!/bin/sh
# extract-intent.sh — extracao deterministica de paths declarados + origem
# para a skill `converge` (FR-001, FR-003, FR-007).
#
# Ref: docs/specs/skill-converge/contracts/converge-interfaces.md §2
#      docs/specs/skill-converge/research.md Decision 4
#      docs/specs/skill-converge/data-model.md §Definição de normalize()
#      docs/specs/skill-converge/tasks.md tarefa 2.2 (consome normalize()
#      da tarefa 1.1)
#
# USO:
#   extract-intent.sh --tasks <tasks.md> [--plan <plan.md>]
#
# Parseia tasks.md (fonte primaria) e, se --plan for fornecido e existir,
# plan.md (fonte secundaria, opcional — Scenario 14: ausencia nao impede a
# execucao) para os paths de arquivo declarados + sua origem.
#
# Saida (stdout), TSV determinístico, uma linha por par (path, origin)
# UNICO (dedupe preservando a ordem de primeira ocorrencia):
#   <path>\t<origin>
#
# EXIT:
#   0  sucesso (0+ linhas)
#   1  --tasks nao encontrado
#   2  erro de uso
#
# --- tasks.md (fonte primaria) ---
# So linhas ESTRUTURADAS sao varridas: headings "### N.M ..." (tambem
# atualiza a origem corrente) e linhas de subtarefa "- [ |x|~|!] N.M.K ..."
# (legenda de status do tasks.md). Prosa solta ("Ref: ...", tabelas, texto
# livre) e ignorada por design (tarefa 2.2.1). A origem de QUALQUER path
# encontrado em uma linha e sempre o heading `### N.M` mais proximo — nunca
# o id da subtarefa `N.M.K` (data-model.md §Definição de normalize()).
#
# --- plan.md (fonte secundaria, se --plan for passado) ---
# So a secao "## Project Structure" e varrida (da heading ate o proximo
# "## "). Um path so e emitido com origem=FR-NNN quando a MESMA linha
# contem, literalmente, tanto o path quanto "FR-NNN" — este script NUNCA
# "herda" o FR mais proximo de linhas anteriores/posteriores: fazer isso
# fabricaria uma associacao path<->requisito que nao esta literalmente
# presente no texto (Constitution VI — jamais inventar dados/associações).
# Por isso plan.md contribui menos linhas que sua arvore completa; e a
# fonte SECUNDARIA por design (tasks.md ja cobre os paths de forma
# abrangente — Edge Case spec.md, Scenario 14).
#
# --- Heuristica de "isto e um path?" (SEC-1: puramente textual) ---
# Um token (isolado por qualquer caractere fora de [A-Za-z0-9_./-]) e
# candidato a path SE E SOMENTE SE termina em "<alfanumerico-ou-underscore>
# .<extensao-da-allowlist>" — checagem via sufixo exato (regex ancorada em
# "$", nunca prefixo/substring). Duas exigencias, cada uma fechando uma
# classe de falso-positivo encontrada empiricamente ao rodar este script
# contra os tasks.md/plan.md REAIS desta feature durante a implementacao:
#   (a) extensao na allowlist — exclui referencias de tarefa "N.M" (ex.:
#       "2.1"), ranges "SC-001..006", placeholders de template "{N}.M" que
#       uma regex generica demais leria como arquivo de extensao ".1"/
#       ".SC"/".M". Allowlist levantada via grep de todas as extensoes
#       citadas em docs/specs/**/tasks.md deste repo; estende-la e seguro
#       (aditivo) se um novo tipo de arquivo aparecer em outra feature.
#   (b) caractere alfanumerico/underscore IMEDIATAMENTE ANTES do ponto —
#       exclui fragmentos sem "nome de arquivo" antes da extensao, como o
#       ".sh" isolado que sobra ao tokenizar o placeholder de convencao de
#       nome `tests/test_<nome>.sh` (o "<"/">" quebram o span em 3 tokens;
#       sem esta exigencia, o token final ".sh" — so a extensao, sem base —
#       seria lido como path).
#
# Ambas exigencias vivem numa UNICA regex ERE **literal** (`/.../ `) escrita
# diretamente no programa awk, nunca passada via `awk -v var="$shell_var"`:
# `-v` faz o valor atravessar o processamento de escape de STRING do awk
# ANTES de virar regex, e esse processamento e subespecificado pelo POSIX
# para sequencias nao-reconhecidas como `\.` — o awk instalado neste
# ambiente (macOS, "one true awk"/BWK) DESCARTA o backslash nesse caminho,
# entao `\.` vira `.` (== "qualquer caractere" em regex) em vez de "ponto
# literal". Bug real encontrado nesta tarefa: com o pattern passado via
# `-v`, o token "contradicts" (termina em "cts") e "Requirements" (termina
# em "ts") batiam com ".ts$" (qualquer-caractere + "ts" + fim), sendo lidos
# como arquivos de extensao ".ts" — nunca houve ponto nessas palavras.
# Regex ESCRITA COMO LITERAL no corpo do programa nao sofre esse processo
# (o lexer do awk interpreta `/\./ ` como ERE diretamente, sem a passagem
# intermediaria por regras de escape de string) — por isso `has_ext()` usa
# a regex inline em vez de uma variavel `-v` (fix verificado empiricamente
# contra os dois casos acima antes de finalizar este script).
#
# POSIX sh + awk (ferramentas POSIX canonicas, Constitution II). Zero eval
# sobre conteudo lido — awk faz apenas casamento de padrao/substituicao de
# STRING sobre dados, nunca interpreta o conteudo lido como codigo (SEC-1).
# Todas as variaveis quotadas. Sem Bash-isms.

set -eu

_EI_NAME="extract-intent"

_ei_usage() {
  cat <<'USAGE' >&2
Uso: extract-intent.sh --tasks <tasks.md> [--plan <plan.md>]

  --tasks <f>  tasks.md da feature (obrigatorio, fonte primaria)
  --plan <f>   plan.md da feature (opcional, fonte secundaria — Scenario 14)

Saida: TSV "<path>\t<origin>" em stdout, uma linha por par unico.
Exit: 0 sucesso | 1 --tasks ausente | 2 erro de uso
USAGE
}

_ei_die_usage() {
  printf '%s: %s\n' "$_EI_NAME" "$1" >&2
  exit 2
}

# ---------- Parse de flags ----------

_TASKS=""
_PLAN=""

if [ "$#" -eq 0 ]; then
  _ei_usage
  exit 2
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tasks)
      [ "$#" -ge 2 ] || _ei_die_usage "--tasks requer valor"
      _TASKS=$2
      shift 2
      ;;
    --plan)
      [ "$#" -ge 2 ] || _ei_die_usage "--plan requer valor"
      _PLAN=$2
      shift 2
      ;;
    -h | --help)
      _ei_usage
      exit 0
      ;;
    *)
      _ei_die_usage "flag desconhecida: $1"
      ;;
  esac
done

[ -n "$_TASKS" ] || _ei_die_usage "--tasks e obrigatorio"

if [ ! -f "$_TASKS" ]; then
  printf '%s: tasks.md ausente: %s\n' "$_EI_NAME" "$_TASKS" >&2
  exit 1
fi

# ---------- Extracao de tasks.md (fonte primaria) ----------

_ei_extract_tasks() {
  awk '
    function has_ext(tok) {
      return (tok ~ /[A-Za-z0-9_]\.(sh|md|json|jsonl|yml|yaml|txt|py|ts|tsx|js|jsx|go|css|html|db|sql)$/)
    }

    # normalize(path) — data-model.md: trim (tokens de split() ja vem sem
    # espaco) -> remove prefixo "./" -> colapsa "//"+ em "/" -> remove "/"
    # final exceto raiz -> sem case-fold (nenhuma transformacao de caixa
    # aplicada ao path, por design).
    function normalize_path(p) {
      sub(/^\.\//, "", p)
      gsub(/\/\/+/, "/", p)
      if (p != "/") sub(/\/$/, "", p)
      return p
    }

    # normalize(origin) — so a etapa "uppercase do prefixo FR-" se aplica
    # aqui: a etapa "reduzir heading a N.M" ja acontece na propria extracao
    # (origin so e populado a partir de "### N.M", nunca do heading
    # completo) — ver comentario de cabecalho do script.
    function normalize_origin(o) {
      if (o ~ /^[Ff][Rr]-/) sub(/^[Ff][Rr]-/, "FR-", o)
      return o
    }

    # scan(text, org): varre TODOS os spans entre backticks em "text" via
    # index()/substr() (POSIX puro — sem gensub, sem regex non-greedy).
    # Para cada span, tokeniza em runs de [A-Za-z0-9_./-] e imprime uma
    # linha TSV para cada token cuja extensao esteja na allowlist.
    function scan(text, org,    rest, start, end, span, n, toks, i, tok) {
      rest = text
      while (1) {
        start = index(rest, "`")
        if (start == 0) break
        rest = substr(rest, start + 1)
        end = index(rest, "`")
        if (end == 0) break
        span = substr(rest, 1, end - 1)
        rest = substr(rest, end + 1)
        n = split(span, toks, /[^A-Za-z0-9_.\/-]+/)
        for (i = 1; i <= n; i++) {
          tok = toks[i]
          if (tok == "") continue
          if (has_ext(tok)) printf "%s\t%s\n", normalize_path(tok), normalize_origin(org)
        }
      }
    }

    /^### [0-9]+\.[0-9]+/ {
      line = $0
      sub(/^### /, "", line)
      split(line, parts, " ")
      origin = parts[1]
      scan(line, origin)
      next
    }
    /^- \[[ x~!]\]/ {
      scan($0, origin)
      next
    }
  ' "$_TASKS"
}

# ---------- Extracao de plan.md §Project Structure (fonte secundaria) ----------

_ei_extract_plan() {
  [ -n "$_PLAN" ] || return 0
  [ -f "$_PLAN" ] || return 0

  awk '
    function has_ext(tok) {
      return (tok ~ /[A-Za-z0-9_]\.(sh|md|json|jsonl|yml|yaml|txt|py|ts|tsx|js|jsx|go|css|html|db|sql)$/)
    }
    function normalize_path(p) {
      sub(/^\.\//, "", p)
      gsub(/\/\/+/, "/", p)
      if (p != "/") sub(/\/$/, "", p)
      return p
    }
    function normalize_origin(o) {
      if (o ~ /^[Ff][Rr]-/) sub(/^[Ff][Rr]-/, "FR-", o)
      return o
    }

    /^## Project Structure/ { in_structure = 1; next }
    /^## / { if (in_structure) exit; next }
    {
      if (!in_structure) next
      if ($0 !~ /[Ff][Rr]-[0-9]+/) next
      line = $0
      if (!match(line, /[Ff][Rr]-[0-9]+/)) next
      frtok = normalize_origin(substr(line, RSTART, RLENGTH))
      n = split(line, toks, /[^A-Za-z0-9_.\/-]+/)
      for (i = 1; i <= n; i++) {
        tok = toks[i]
        if (tok == "") continue
        if (has_ext(tok)) printf "%s\t%s\n", normalize_path(tok), frtok
      }
    }
  ' "$_PLAN"
}

# ---------- Saida final: concatena as duas fontes + dedupe estavel ----------
# "!seen[$0]++" e o idioma awk canonico para dedupe preservando a ordem de
# PRIMEIRA ocorrencia (distinto de "sort -u", que reordena alfabeticamente
# — quebraria "mesma entrada -> mesma saida, mesma ordem" do contrato).

{
  _ei_extract_tasks
  _ei_extract_plan
} | awk '!seen[$0]++'
