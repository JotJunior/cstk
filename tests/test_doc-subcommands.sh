#!/bin/sh
# test_doc-subcommands.sh — lint de invariante do repositorio (INTERNO).
#
# Garante que toda referencia `<helper>.sh <subcomando>` nos docs de
# orquestrador/command aponte para um subcomando REAL — i.e. um case-label no
# dispatch do script. Pega a classe de bug "subcomando-fantasma":
#   - `suggestions.sh append`        (real: register)
#   - `report.sh emit`               (antes de existir)
#   - `state-ondas.sh skill-invoked` (real: record-skill)
#   - `bash-guard.sh check-cmd`      (real: check)
#   - `spawn-tracker.sh increment`   (real: enter)
#   - flags fantasma de `state-rw.sh init` (5.3.0)
# Essa classe e barata de introduzir (doc escrita contra interface IMAGINADA)
# e cara de pegar (so falha em runtime, dentro de uma onda autonoma).
#
# Escopo: SO valida o verbo/subcomando contra os scripts do runtime 00c
# (plugins/cstk/skills/agente-00c-runtime/scripts/). NAO valida flags (parsing varia
# demais p/ ser confiavel). Refs a scripts fora desse dir, ou a scripts sem
# dispatch (libs sourcadas), sao puladas.
#
# Precisao (zero falso-positivo em CI):
#   - so olha CODIGO: linhas em fences ``` + spans inline `...` (ignora prosa);
#   - ignora linhas de COMENTARIO shell (`#`) dentro de fences (prosa em code);
#   - quebra grupos-alias `a\|b\|c` em tokens individuais;
#   - pula shorthand de brace-expansion `escape-{a,b,c}` (contem `{`/`}`);
#   - limpa lixo a direita do token e pula tokens incompletos (terminam em `-`).

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"
. "$TESTS_ROOT/lib/harness.sh"

SCRIPTS_DIR="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/scripts"
DOC_DIRS="$REPO_ROOT/plugins/cstk/agents $REPO_ROOT/plugins/cstk/commands"

# Tokens meta que nunca sao subcomandos de negocio (nao devem falhar).
_DL_SKIP_TOKENS=" help "

# _dl_valid_subcommands SCRIPT_PATH -> imprime (1/linha) os subcomandos validos
# = case-labels minusculos do script (inclui grupos `a|b|c)`). Vazio = script
# sem dispatch (lib sourcada): caller pula a validacao.
_dl_valid_subcommands() {
  grep -oE '^[[:space:]]*([a-z][a-z0-9_-]*\|)*[a-z][a-z0-9_-]*\)' "$1" 2>/dev/null \
    | tr -d ' )' | tr '|' '\n' | sort -u
}

# _dl_code_spans DOC -> imprime apenas conteudo de CODIGO: linhas dentro de
# fences ``` (menos comentarios shell) + spans inline `...`. Reduz falso-
# positivo de prosa.
_dl_code_spans() {
  awk '
    /^[[:space:]]*```/        { infence = !infence; next }
    infence && /^[[:space:]]*#/ { next }          # comentario shell = prosa
    infence                   { print; next }
    {
      line = $0
      while (match(line, /`[^`]+`/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

# _dl_scan_doc DOC -> imprime "doc<TAB>script<TAB>token" para cada subcomando
# fantasma referenciado.
_dl_scan_doc() {
  _doc=$1
  _dl_code_spans "$_doc" \
    | grep -oE '[a-z][a-z0-9_-]*\.sh[[:space:]]+[^[:space:]]+' \
    | sort -u \
    | while IFS= read -r _ref; do
        _script_name=$(printf '%s' "$_ref" | sed -E 's/(\.sh).*/\1/')
        _script_path="$SCRIPTS_DIR/$_script_name"
        [ -f "$_script_path" ] || continue                 # so runtime 00c
        _grp=$(printf '%s' "$_ref" | sed -E 's/^[^[:space:]]+\.sh[[:space:]]+//')
        case "$_grp" in *'{'* | *'}'*) continue ;; esac     # brace-shorthand
        _valid=$(_dl_valid_subcommands "$_script_path")
        [ -z "$_valid" ] && continue                        # script sem dispatch
        # quebra grupo-alias a\|b\|c em tokens; limpa lixo a direita de cada um
        for _raw in $(printf '%s' "$_grp" | tr '\\|' '  '); do
          _token=$(printf '%s' "$_raw" | sed -E 's/[^a-z0-9_-].*//')
          [ -n "$_token" ] || continue
          case "$_token" in [a-z]*) ;; *) continue ;; esac  # subcomando (nao flag/--opt)
          case "$_token" in *-) continue ;; esac            # token incompleto
          case "$_DL_SKIP_TOKENS" in *" $_token "*) continue ;; esac
          printf '%s\n' "$_valid" | grep -Fxq -- "$_token" \
            || printf '%s\t%s\t%s\n' "$(basename "$_doc")" "$_script_name" "$_token"
        done
      done
}

# _dl_scan_bare DOC -> imprime "doc<TAB>script" para cada INVOCACAO bare:
# `... | <script>.sh` seguido imediatamente de fim-de-comando (`)`, `|`, `;`,
# `>`, `&` ou EOL), i.e. SEM subcomando. Pega a classe-irma do fantasma:
# `printf ... | sanitize.sh)` (issue: orquestrador, exit 2). So vale para
# scripts do runtime 00c COM dispatch (subcomando obrigatorio); libs sourcadas
# (sem case-labels) sao puladas.
_dl_scan_bare() {
  _doc=$1
  _dl_code_spans "$_doc" \
    | grep -oE '\|[[:space:]]*[a-z][a-z0-9_-]*\.sh[[:space:]]*([)|;>&]|$)' \
    | sort -u \
    | while IFS= read -r _ref; do
        # Extrai o token <nome>.sh do match (`| nome.sh)` etc).
        _script_name=$(printf '%s' "$_ref" | grep -oE '[a-z][a-z0-9_-]*\.sh')
        _script_path="$SCRIPTS_DIR/$_script_name"
        [ -f "$_script_path" ] || continue                 # so runtime 00c
        _valid=$(_dl_valid_subcommands "$_script_path")
        [ -z "$_valid" ] && continue                        # script sem dispatch (lib)
        printf '%s\t%s\n' "$(basename "$_doc")" "$_script_name"
      done
}

scenario_no_bare_runtime_invocation() {
  : > "$TMPDIR_TEST/bare.tsv"
  for _dir in $DOC_DIRS; do
    [ -d "$_dir" ] || continue
    for _doc in "$_dir"/*.md; do
      [ -f "$_doc" ] || continue
      _dl_scan_bare "$_doc" >> "$TMPDIR_TEST/bare.tsv"
    done
  done

  if [ -s "$TMPDIR_TEST/bare.tsv" ]; then
    _msg=$(awk -F'\t' '{printf "  %s -> %s (invocado sem subcomando obrigatorio)\n", $1, $2}' \
      "$TMPDIR_TEST/bare.tsv" | sort -u)
    _fail "bare-invocation" "doc invoca script de dispatch sem subcomando (sai exit 2):
$_msg"
    return 1
  fi
  return 0
}

scenario_no_phantom_subcommands() {
  : > "$TMPDIR_TEST/violations.tsv"
  for _dir in $DOC_DIRS; do
    [ -d "$_dir" ] || continue
    for _doc in "$_dir"/*.md; do
      [ -f "$_doc" ] || continue
      _dl_scan_doc "$_doc" >> "$TMPDIR_TEST/violations.tsv"
    done
  done

  if [ -s "$TMPDIR_TEST/violations.tsv" ]; then
    _msg=$(awk -F'\t' '{printf "  %s -> %s %s (subcomando inexistente)\n", $1, $2, $3}' \
      "$TMPDIR_TEST/violations.tsv")
    _fail "phantom-subcommand" "doc referencia subcomando que nao existe no dispatch:
$_msg"
    return 1
  fi
  return 0
}

# Meta-teste: o detector PRECISA pegar um fantasma sintetico e, ao mesmo tempo,
# NAO acusar um subcomando real nem prosa em comentario. Sem isto, um bug no
# extrator passaria verde por nao-detectar (e nao por estar limpo).
scenario_detector_self_check() {
  _fakedoc="$TMPDIR_TEST/fake.md"
  {
    printf '```sh\n'
    printf 'report.sh generate --state-dir X\n'      # real -> nao deve acusar
    printf '# report.sh soprosa aqui dentro\n'        # comentario -> ignorado
    printf 'report.sh inventado --state-dir X\n'      # fantasma -> deve acusar
    printf 'state-ondas.sh start\\|end\\|fantasmal\n' # grupo-alias -> pega o 3o
    printf '```\n'
  } > "$_fakedoc"
  _hits=$(_dl_scan_doc "$_fakedoc" | cut -f3 | sort -u | paste -sd',' -)
  # deve conter os fantasmas, e NAO conter generate nem soprosa
  case ",$_hits," in
    *,inventado,*) : ;; *) _fail "meta" "nao pegou fantasma 'inventado' (hits=$_hits)"; return 1 ;;
  esac
  case ",$_hits," in
    *,fantasmal,*) : ;; *) _fail "meta" "nao pegou fantasma em grupo-alias 'fantasmal' (hits=$_hits)"; return 1 ;;
  esac
  case ",$_hits," in
    *,generate,*) _fail "meta" "acusou subcomando REAL 'generate' (hits=$_hits)"; return 1 ;;
  esac
  case ",$_hits," in
    *,soprosa,*) _fail "meta" "acusou prosa de comentario 'soprosa' (hits=$_hits)"; return 1 ;;
  esac
  return 0
}

# Meta-teste do detector de invocacao bare: precisa pegar `| <script>.sh)` sem
# subcomando, e NAO acusar a mesma chamada COM subcomando nem a mencao do nome
# em span inline (capability table).
scenario_bare_detector_self_check() {
  # Usa um script real do runtime com dispatch (sanitize.sh) p/ ancorar.
  [ -f "$SCRIPTS_DIR/sanitize.sh" ] || { return 0; }  # skip se ausente
  _fakedoc="$TMPDIR_TEST/fake-bare.md"
  {
    printf '```sh\n'
    printf '_d=$(printf %%s "$X" | sanitize.sh)\n'                 # bare -> deve acusar
    printf '_ok=$(printf %%s "$X" | sanitize.sh limit-length)\n'   # com subcmd -> nao
    printf '```\n'
    printf 'Mencao em prosa de `sanitize.sh` na tabela.\n'         # span inline -> nao
  } > "$_fakedoc"
  _hits=$(_dl_scan_bare "$_fakedoc" | wc -l | tr -d ' ')
  [ "$_hits" -eq 1 ] || { _fail "meta-bare" "esperado 1 hit bare, obtido $_hits"; return 1; }
  return 0
}

run_all_scenarios
