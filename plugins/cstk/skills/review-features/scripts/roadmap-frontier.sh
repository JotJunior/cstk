#!/bin/sh
# roadmap-frontier.sh — fronteira de elegibilidade do roadmap (FR-001).
#
# Feature: roadmap-parallel-launch
# Ref:     docs/specs/roadmap-parallel-launch/contracts/roadmap-frontier.md
#          docs/specs/roadmap-parallel-launch/spec.md FR-001, FR-010, SC-004
#
# Deriva a fronteira de elegibilidade do roadmap: entradas `nao-iniciada`
# cujas dependencias declaradas estao TODAS `concluida`. Nao lanca nada, nao
# interage com o operador, nao escreve arquivo algum — computacao pura sobre
# a saida de `roadmap-status.sh --json` (script irmao, INV-3: status NUNCA e
# derivado por leitura propria). POSIX puro, sem `jq` (Principio II).
#
# Quando ha >=2 candidatas na fronteira, tambem computa um aviso
# best-effort de sobreposicao de artefatos (FR-014, US4, contract §6):
# intersecao nao-vazia de tokens de path extraidos do bloco de prosa de
# cada par de candidatas. E INDICIO, nunca afirmacao de conflito
# (Principio VI); informacao insuficiente = nenhum aviso, nunca erro nem
# bloqueio. Prosa do roadmap e tratada como conteudo NAO-CONFIAVEL:
# allowlist de token, truncamento a 128 chars, teto de 10 tokens por par
# e rotulo explicito `roadmap-prose-untrusted` (INV-4/INV-5).
#
# Uso:
#   roadmap-frontier.sh [--roadmap PATH] [--specs-dir DIR] [--json]
#                       [--exclude-active-from-repo PATH]
#   roadmap-frontier.sh -h | --help
#
# Flags:
#   --roadmap PATH    repassado tal-e-qual a roadmap-status.sh (default: docs/roadmap.md)
#   --specs-dir DIR   repassado tal-e-qual a roadmap-status.sh (default: docs/specs)
#   --json            emite JSON-lines em vez de tabela markdown
#   --exclude-active-from-repo PATH
#                     remove da fronteira os short-names que ja tem worktree
#                     ativa no repo PATH (contract §5, FR-011) — guarda
#                     anti-duplicidade e mecanismo de recuperacao (FR-016)
#
# Premissa de confianca (contract §3.1): docs/roadmap.md, docs/specs e o
# repositorio corrente sao do proprio operador (repo coordenador confiavel).
# Paths recebidos por flag com componente ".." sao rejeitados (exit 2) como
# defesa em profundidade.
#
# ATENCAO — este script INVOCA `git -C "$EXCLUDE_ACTIVE_REPO" worktree list`
# (ver a secao da guarda anti-duplicidade abaixo). `git -C` sobre um repo
# hostil pode executar codigo via `.git/config` (ex.: `core.fsmonitor`),
# entao a premissa de confianca acima NAO e decorativa: o path passado em
# `--exclude-active-from-repo` deve ser do proprio operador.
# DIVERGENCIA CONHECIDA (v8.2.0): `contracts/roadmap-frontier.md` §3.1 exige
# rejeitar tambem path que "resolva para fora do repo coordenador" — hoje so
# a checagem sintatica de ".." esta implementada. A contencao real entra com
# a feature `roadmap-wave` (que torna o alvo um argumento de rotina); ate la,
# este comentario e a unica declaracao honesta do estado do codigo.
#
# Exit codes:
#   0  sucesso (inclusive fronteira vazia — nao e erro)
#   1  roadmap-status.sh retornou 1 (roadmap AUSENTE) — propagado
#   2  uso incorreto (flag desconhecida, path invalido)
#   3  roadmap-status.sh retornou 3 (roadmap PRESENTE mas invalido) — propagado
#   4  roadmap-status.sh nao encontrado no diretorio irmao

set -eu

_RF_NAME="roadmap-frontier"
_RF_DIR=$(cd "$(dirname "$0")" && pwd)
_RF_STATUS_SCRIPT="$_RF_DIR/roadmap-status.sh"

DEFAULT_ROADMAP="docs/roadmap.md"
DEFAULT_SPECS_DIR="docs/specs"

ROADMAP=""
SPECS_DIR=""
JSON_ONLY=false
EXCLUDE_ACTIVE_REPO=""

print_usage() {
  cat <<'EOF'
Uso: roadmap-frontier.sh [--roadmap PATH] [--specs-dir DIR] [--json]
                         [--exclude-active-from-repo PATH]

Deriva a fronteira de elegibilidade do roadmap (FR-001): entradas
nao-iniciada cujas dependencias declaradas estao TODAS concluida. Read-only
— nao lanca nada, nao interage com o operador, nao escreve arquivo algum.

Opcoes:
  --roadmap PATH    Artefato a cruzar (default: docs/roadmap.md)
  --specs-dir DIR   Portfolio a inspecionar (default: docs/specs)
  --json            Emite JSON-lines (uma linha por candidata elegivel) em
                     vez de tabela markdown
  --exclude-active-from-repo PATH
                     Remove da fronteira os short-names com worktree ativa
                     em PATH (`git worktree list --porcelain`, contract §5,
                     FR-011). Ausencia de git, path invalido ou repo sem
                     worktrees => nenhuma exclusao + aviso em stderr, NUNCA
                     erro fatal (defesa em profundidade).
  -h, --help        Mostra esta ajuda

Premissa de confianca: docs/roadmap.md, docs/specs e o repositorio corrente
sao do proprio operador (repo coordenador confiavel). Com
--exclude-active-from-repo este script roda `git -C <PATH> worktree list`;
`git -C` sobre repo hostil pode executar codigo via .git/config, entao NAO
aponte a flag para repositorio de terceiros. Paths com componente
".." sao rejeitados (exit 2).

Exit codes: 0 sucesso (inclusive fronteira vazia); 1 roadmap ausente;
2 uso incorreto; 3 roadmap presente mas invalido/ilegivel; 4 roadmap-status.sh
nao encontrado.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --roadmap)
      [ $# -ge 2 ] || { printf '%s: --roadmap exige valor\n' "$_RF_NAME" >&2; exit 2; }
      ROADMAP=$2; shift 2 ;;
    --specs-dir)
      [ $# -ge 2 ] || { printf '%s: --specs-dir exige valor\n' "$_RF_NAME" >&2; exit 2; }
      SPECS_DIR=$2; shift 2 ;;
    --exclude-active-from-repo)
      [ $# -ge 2 ] || { printf '%s: --exclude-active-from-repo exige valor\n' "$_RF_NAME" >&2; exit 2; }
      EXCLUDE_ACTIVE_REPO=$2; shift 2 ;;
    --json)
      JSON_ONLY=true; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      printf '%s: flag desconhecida: %s\n' "$_RF_NAME" "$1" >&2
      print_usage >&2
      exit 2 ;;
  esac
done

[ -n "$ROADMAP" ]   || ROADMAP="$DEFAULT_ROADMAP"
[ -n "$SPECS_DIR" ] || SPECS_DIR="$DEFAULT_SPECS_DIR"

# ==== Validacao de paths (contract §3.1, finding LOW A05) ====
# Rejeita qualquer path com componente ".." isolado (evita apontar para
# fora do repo coordenador). Checagem sintatica, sem depender de
# realpath/readlink -f (nao portaveis entre macOS/Linux).
_rf_reject_dotdot() {
  # $1 = nome da flag (para mensagem), $2 = valor do path
  case "/$2/" in
    */../*)
      printf '%s: path invalido (%s): componente ".." nao permitido: %s\n' \
        "$_RF_NAME" "$1" "$2" >&2
      exit 2 ;;
  esac
}
_rf_reject_dotdot "--roadmap" "$ROADMAP"
_rf_reject_dotdot "--specs-dir" "$SPECS_DIR"
[ -z "$EXCLUDE_ACTIVE_REPO" ] || _rf_reject_dotdot "--exclude-active-from-repo" "$EXCLUDE_ACTIVE_REPO"

[ -x "$_RF_STATUS_SCRIPT" ] || [ -f "$_RF_STATUS_SCRIPT" ] || {
  printf '%s: roadmap-status.sh nao encontrado no diretorio irmao: %s\n' \
    "$_RF_NAME" "$_RF_STATUS_SCRIPT" >&2
  exit 4
}

# ==== Delegacao a roadmap-status.sh (INV-3: fonte unica de status) ====

set +e
_status_out=$("$_RF_STATUS_SCRIPT" --roadmap "$ROADMAP" --specs-dir "$SPECS_DIR" --json)
_status_exit=$?
set -e

case "$_status_exit" in
  0) : ;;
  1) exit 1 ;;
  3) exit 3 ;;
  *)
    printf '%s: roadmap-status.sh retornou exit inesperado: %s\n' \
      "$_RF_NAME" "$_status_exit" >&2
    exit 2 ;;
esac

_ALL_LINES="$_status_out"

# ==== Helpers de parsing (formato fixo emitido por roadmap-status.sh) ====

_rf_field_short() {
  printf '%s' "$1" | sed -n 's/.*"short_name":"\([^"]*\)".*/\1/p'
}

_rf_field_status() {
  printf '%s' "$1" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p'
}

_rf_field_ordem() {
  printf '%s' "$1" | sed -n 's/^{"ordem":\([0-9][0-9]*\),.*/\1/p'
}

_rf_field_deps_json() {
  printf '%s' "$1" | sed -n 's/.*"depende_de":\(\[[^]]*\]\).*/\1/p'
}

# _rf_deps_tokens DEPS_JSON -> tokens (um por linha), sem aspas/colchetes.
#
# NAO usar `${_dj#[}`/`${_dj%]}` aqui: `[`/`]` soltos como padrao de trim de
# parametro tem comportamento DIVERGENTE entre shells POSIX — dash nunca
# remove (bracket-class incompleta = sem match), bash trata como literal
# (remove). Achado empirico ao rodar `dash -n`/execucao real. `sed` com
# `\[`/`\]` escapados e deterministico nas duas.
_rf_deps_tokens() {
  _dj=$(printf '%s' "$1" | sed -n 's/^\[\(.*\)\]$/\1/p')
  [ -n "$_dj" ] || return 0
  printf '%s' "$_dj" | tr ',' '\n' | sed 's/^"//; s/"$//'
}

# _rf_status_of SHORT -> status da entrada SHORT em _ALL_LINES, ou vazio
# se inexistente (dependencia inexistente => nao elegivel, contract §4).
_rf_status_of() {
  _target=$1
  printf '%s\n' "$_ALL_LINES" | while IFS= read -r _ln; do
    [ -n "$_ln" ] || continue
    if [ "$(_rf_field_short "$_ln")" = "$_target" ]; then
      _rf_field_status "$_ln"
      break
    fi
  done
}

# ==== Guarda anti-duplicidade (contract §5, FR-011/FR-016) ====
#
# Com --exclude-active-from-repo PATH, lista `git -C PATH worktree list
# --porcelain` e extrai TODA linha `branch refs/heads/<name>` (GOTCHA
# conhecido: iterar linha a linha, NUNCA `| head -1`, que esconderia
# worktrees adicionais — ver memoria de projeto). Ausencia de git, path
# invalido ou repo sem worktrees => nenhuma exclusao + aviso em stderr,
# NUNCA erro fatal (defesa em profundidade; `cstk session start` ainda
# falharia com exit 6 se houvesse colisao real).
_RF_ACTIVE_BRANCHES=""
if [ -n "$EXCLUDE_ACTIVE_REPO" ]; then
  if command -v git >/dev/null 2>&1; then
    _rf_wt_out=$(git -C "$EXCLUDE_ACTIVE_REPO" worktree list --porcelain 2>/dev/null) || _rf_wt_out=""
    if [ -n "$_rf_wt_out" ]; then
      _RF_ACTIVE_BRANCHES=$(printf '%s\n' "$_rf_wt_out" \
        | sed -n 's/^branch refs\/heads\///p')
    else
      printf '%s: --exclude-active-from-repo: sem worktrees ou path invalido (%s) — nenhuma exclusao\n' \
        "$_RF_NAME" "$EXCLUDE_ACTIVE_REPO" >&2
    fi
  else
    printf '%s: --exclude-active-from-repo: git ausente — nenhuma exclusao\n' "$_RF_NAME" >&2
  fi
fi

# _rf_is_excluded SHORT -> exit 0 se SHORT tem worktree ativa (contract §5).
# Checagem via `case` sobre string com sentinela `\n` em cada ponta — evita
# subshell de pipe (que perderia o `return`) e falso-match de substring
# (ex.: "auth" nao deve casar "auth-basica"). GOTCHA: `$(...)` sempre remove
# newlines FINAIS — um sentinela nao-newline (".") apos o ultimo `\n`
# preserva a newline anterior a ele, necessaria para o match do ultimo item.
_rf_is_excluded() {
  [ -n "$_RF_ACTIVE_BRANCHES" ] || return 1
  _rfie_target=$1
  case "$(printf '\n%s\n.' "$_RF_ACTIVE_BRANCHES")" in
    *"
$_rfie_target
"*) return 0 ;;
  esac
  return 1
}

# ==== Regra de elegibilidade (contract §4) ====
#
# Loop via heredoc (nao via pipe) deliberadamente: `cmd | while ...` roda o
# corpo do while em subshell na maioria das shells POSIX (dash/bash sem
# `lastpipe`), o que perderia toda mutacao de _out_json/_out_md/_eligible_count
# fora do loop. `while ... done <<HEREDOC` roda no shell corrente — sem
# subshell, sem arquivo temporario, portavel macOS/Linux (evita `sed` GNU-only
# como `1~2p`, que nao existe no BSD sed do macOS).

_out_json=""
_out_md=""
_eligible_count=0
_eligible_shorts=""

if [ -n "$_ALL_LINES" ]; then
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue

    _status=$(_rf_field_status "$_line")
    [ "$_status" = "nao-iniciada" ] || continue

    _short_precheck=$(_rf_field_short "$_line")
    _rf_is_excluded "$_short_precheck" && continue

    _deps_json=$(_rf_field_deps_json "$_line")
    _eligible=true
    for _tok in $(_rf_deps_tokens "$_deps_json"); do
      _dep_status=$(_rf_status_of "$_tok")
      if [ "$_dep_status" != "concluida" ]; then
        _eligible=false
        break
      fi
    done

    if [ "$_eligible" = true ]; then
      _ordem=$(_rf_field_ordem "$_line")
      _short=$(_rf_field_short "$_line")
      _dep_tokens=$(_rf_deps_tokens "$_deps_json" | tr '\n' ',' | sed 's/,$//')
      _dep_md="-"
      [ -n "$_dep_tokens" ] && _dep_md="$_dep_tokens"
      _out_json="${_out_json}$(printf '{"ordem":%s,"short_name":"%s","depende_de":%s,"eligible":true}' \
        "$_ordem" "$_short" "$_deps_json")
"
      _out_md="${_out_md}$(printf '| %s | %s | %s |' "$_ordem" "$_short" "$_dep_md")
"
      _eligible_count=$((_eligible_count + 1))
      _eligible_shorts="${_eligible_shorts}${_eligible_shorts:+ }$_short"
    fi
  done <<RF_LINES_EOF
$_ALL_LINES
RF_LINES_EOF
fi

if [ "$_eligible_count" -eq 0 ]; then
  printf '%s: nenhuma feature elegivel na fronteira atual\n' "$_RF_NAME" >&2
  exit 0
fi

# ==== Aviso de sobreposicao de artefatos (contract §6, FR-014, US4) ====
#
# Indicio, NUNCA afirmacao de conflito (Principio VI). Fonte: bloco de
# prosa (Descricao/Justificativa, contracts/roadmap-artifact.md §3.4) de
# cada candidata da fronteira — unica leitura direta de docs/roadmap.md
# neste script (INV-3 cobre so status; prosa nao e status). Best-effort:
# informacao insuficiente (prosa ausente, intersecao vazia) => nenhum
# aviso, NUNCA erro nem bloqueio (AC2/AC3 da US4).
#
# Sanitizacao obrigatoria (finding HIGH LLM01/ASI01, plan.md task 4.4):
# allowlist de token ^[A-Za-z0-9._/-]{1,64}$, truncamento defensivo a
# 128 chars ANTES da validacao pela allowlist, teto de 10 tokens
# emitidos por par, escaping json_escape/md_escape (§7.1) e rotulo
# explicito de conteudo nao-confiavel (§6) em toda saida — nenhum
# caminho emite token bruto do roadmap (INV-4/INV-5).

_out_warn_json=""
_out_warn_md=""

if [ "$_eligible_count" -ge 2 ]; then
  _RF_TOKEN_ALLOW_RE='^[A-Za-z0-9._/-]{1,64}$'
  _RF_EXT_RE='\.(md|sh|ts|tsx|js|jsx|json|yml|yaml|go|py|rb|java|rs|c|h|cpp|toml|cfg|conf|ini|txt|sql|proto|graphql|env)$'
  _RF_HEADING_RE='^###[[:space:]]+[1-9][0-9]*\.[[:space:]]+[a-z][a-z0-9-]*$'
  _rf_heading_lines=$(grep -nE "$_RF_HEADING_RE" "$ROADMAP" 2>/dev/null | cut -d: -f1) || :
  _rf_total_lines=$(wc -l < "$ROADMAP" | tr -d ' ')

  # _rf_prose_block SHORT -> corpo do bloco (heading+1 .. proximo heading-1)
  # com as linhas de metadado (`- **...`) removidas — sobra so a prosa
  # (Descricao/Justificativa). Vazio se SHORT nao encontrado ou bloco sem
  # prosa (informacao insuficiente => nenhum token => nenhum aviso).
  _rf_prose_block() {
    _pb_target=$1
    [ -n "$_rf_heading_lines" ] || return 0
    _pb_i=0
    for _pb_hl in $_rf_heading_lines; do
      _pb_i=$((_pb_i + 1))
      _pb_hd=$(sed -n "${_pb_hl}p" "$ROADMAP")
      _pb_short=$(printf '%s' "$_pb_hd" | sed -n 's/^### [1-9][0-9]*\. \(.*\)$/\1/p')
      if [ "$_pb_short" = "$_pb_target" ]; then
        _pb_next=$(printf '%s\n' "$_rf_heading_lines" | sed -n "$((_pb_i + 1))p")
        if [ -n "$_pb_next" ]; then _pb_end=$((_pb_next - 1)); else _pb_end=$_rf_total_lines; fi
        sed -n "$((_pb_hl + 1)),${_pb_end}p" "$ROADMAP" | grep -Ev '^- \*\*' || :
        return 0
      fi
    done
  }

  # _rf_extract_tokens TEXT -> tokens (um por linha) que PARECEM caminho de
  # artefato (contem "/" ou terminam em extensao conhecida), ja truncados
  # a 128 chars e validados pela allowlist. Pontuacao decorativa de prosa
  # (crases, aspas, virgula, ponto-e-virgula, parenteses/colchetes/chaves,
  # angulares) e removida ANTES da validacao — sem isso, um path citado
  # entre crases (convencao do proprio roadmap) nunca casaria a allowlist.
  _rf_extract_tokens() {
    printf '%s\n' "$1" | tr -s ' \t' '\n' | while IFS= read -r _tk; do
      [ -n "$_tk" ] || continue
      _tk=$(printf '%s' "$_tk" | tr -d "\`\"',;:()[]{}<>")
      _tk=${_tk%.}
      [ -n "$_tk" ] || continue
      _tk=$(printf '%s' "$_tk" | cut -c1-128)
      printf '%s' "$_tk" | grep -Eq "$_RF_TOKEN_ALLOW_RE" || continue
      case "$_tk" in
        */*) : ;;
        *) printf '%s' "$_tk" | grep -Eq "$_RF_EXT_RE" || continue ;;
      esac
      printf '%s\n' "$_tk"
    done
  }

  # _rf_tokens_intersect TOKENS_A TOKENS_B -> intersecao (um por linha),
  # ordem de TOKENS_A, sem duplicatas. Match exato via sentinela `\n`
  # (mesma tecnica de _rf_is_excluded acima) — evita falso-positivo de
  # substring (ex.: "docs/a.md" nao deve casar "docs/ab.md").
  _rf_tokens_intersect() {
    _ti_a=$(printf '%s\n' "$1" | awk '!seen[$0]++ && length($0)>0')
    _ti_b=$(printf '%s\n' "$2" | awk '!seen[$0]++ && length($0)>0')
    [ -n "$_ti_a" ] && [ -n "$_ti_b" ] || return 0
    printf '%s\n' "$_ti_a" | while IFS= read -r _tok; do
      [ -n "$_tok" ] || continue
      case "$(printf '\n%s\n.' "$_ti_b")" in
        *"
$_tok
"*) printf '%s\n' "$_tok" ;;
      esac
    done
  }

  # _rf_emit_warning_if_overlap S1 S2 -> aponta _out_warn_json/_out_warn_md
  # (globais) se a intersecao de tokens de S1/S2 for nao-vazia. Redacao
  # obrigatoria: "as entradas X e Y mencionam ambas <token>" — forma
  # proibida "X e Y vao conflitar" NUNCA emitida (CHK113, Principio VI).
  _rf_emit_warning_if_overlap() {
    _ew_s1=$1
    _ew_s2=$2
    _ew_b1=$(_rf_prose_block "$_ew_s1")
    _ew_b2=$(_rf_prose_block "$_ew_s2")
    [ -n "$_ew_b1" ] && [ -n "$_ew_b2" ] || return 0
    _ew_t1=$(_rf_extract_tokens "$_ew_b1")
    _ew_t2=$(_rf_extract_tokens "$_ew_b2")
    [ -n "$_ew_t1" ] && [ -n "$_ew_t2" ] || return 0
    _ew_common=$(_rf_tokens_intersect "$_ew_t1" "$_ew_t2" | sed -n '1,10p')
    [ -n "$_ew_common" ] || return 0

    _ew_s1_j=$(json_escape "$_ew_s1")
    _ew_s2_j=$(json_escape "$_ew_s2")
    _ew_tokens_json=""
    _ew_tokens_md=""
    _ew_first=1
    while IFS= read -r _ew_tok; do
      [ -n "$_ew_tok" ] || continue
      _ew_tok_j=$(json_escape "$_ew_tok")
      _ew_tok_m=$(md_escape "$_ew_tok")
      if [ "$_ew_first" -eq 1 ]; then
        _ew_tokens_json="\"${_ew_tok_j}\""
        _ew_tokens_md="\`${_ew_tok_m}\`"
        _ew_first=0
      else
        _ew_tokens_json="${_ew_tokens_json},\"${_ew_tok_j}\""
        _ew_tokens_md="${_ew_tokens_md}, \`${_ew_tok_m}\`"
      fi
    done <<RF_TOK_EOF
$_ew_common
RF_TOK_EOF

    _out_warn_json="${_out_warn_json}$(printf '{"warning":"artifact_overlap","pair":["%s","%s"],"tokens":[%s],"source":"roadmap-prose-untrusted"}' \
      "$_ew_s1_j" "$_ew_s2_j" "$_ew_tokens_json")
"
    _out_warn_md="${_out_warn_md}- as entradas \`$(md_escape "$_ew_s1")\` e \`$(md_escape "$_ew_s2")\` mencionam ambas ${_ew_tokens_md} (oriundo de texto livre nao-confiavel do roadmap, nao verificado)
"
  }

  # ==== Helpers de escape (paridade com roadmap-status.sh/aggregate.sh) ====
  # (definidos aqui, so quando ha >=2 candidatas — evitam custo em toda
  # invocacao comum de 0/1 candidata)

  json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
  }

  md_escape() {
    printf '%s' "$1" | sed 's/|/\//g'
  }

  # Pareamento sem repeticao (todo par unico i<j) via peel-and-pair: o
  # primeiro argumento e emparelhado com cada um dos restantes, depois
  # descartado — cobre todos os pares sem duplicar nem comparar consigo
  # mesmo. `$_eligible_shorts` nunca contem espaco em cada short-name
  # (allowlist ^[a-z][a-z0-9-]*$ de roadmap-status.sh), logo o
  # word-splitting abaixo e seguro.
  _rf_pairwise_warnings() {
    while [ $# -gt 1 ]; do
      _pw_s1=$1
      shift
      for _pw_s2 in "$@"; do
        _rf_emit_warning_if_overlap "$_pw_s1" "$_pw_s2"
      done
    done
  }
  # shellcheck disable=SC2086 # word-splitting intencional (short-names sem espaco)
  _rf_pairwise_warnings $_eligible_shorts
fi

if $JSON_ONLY; then
  printf '%s' "$_out_json"
  printf '%s' "$_out_warn_json"
  exit 0
fi

cat <<EOF
## Fronteira de Elegibilidade (roadmap)

**Roadmap:** $ROADMAP
**Specs-dir:** $SPECS_DIR
**Candidatas:** $_eligible_count

| Ordem | Feature | Depende de |
|-------|---------|------------|
EOF
printf '%s' "$_out_md"
if [ -n "$_out_warn_md" ]; then
  printf '\n### Avisos\n\n'
  printf '%s' "$_out_warn_md"
fi
exit 0
