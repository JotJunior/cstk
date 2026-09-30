#!/bin/sh
# test_orchestrator-refs-failsafe.sh — falha segura das referencias de fase
# dos orquestradores (FR-010) e regra de leitura unica por fase (SC-006).
#
# Ref: docs/specs/orchestrator-slim/spec.md FR-010, SC-006, US4 cenario 3
#      docs/specs/orchestrator-slim/contracts/pointer-format.md
#      docs/specs/orchestrator-slim/quickstart.md Cenario 5
#
# O comportamento em runtime e prosa do prompt (LLM); o que este teste
# garante e a INSPECAO LITERAL: todo stub e a secao "Referencias de fase" de
# O e F trazem a instrucao de nao executar a fase de memoria, registrar
# Decisao (--classe operacional) + bloqueio humano e encerrar a onda quando
# `orchestrator-refs.sh path` ou o Read falhar; a variante `bootstrap` (sem
# onda aberta) nao chama `state-ondas.sh start`, nao emite `Schedule intent`
# e devolve o turno ao command pai; leitura sem o marcador final ORCH-REF-END
# e falha de leitura; e cada stub cita no maximo uma referencia por fase.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

AGENTS_DIR="$REPO_ROOT/plugins/cstk/agents"
ROOT_PROMPT="$AGENTS_DIR/agente-00c-orchestrator.md"
FEATURE_PROMPT="$AGENTS_DIR/agente-00c-feature-orchestrator.md"
REFS_DIR="$REPO_ROOT/plugins/cstk/skills/agente-00c-runtime/references/orchestrators"

# _stubs <prompt>: uma linha por stub, `<linha>|<marcadores ,-separados>|<texto>`.
# Stub = marcadores ORCH-REF contiguos + blockquote (`> ...`) que os segue;
# o texto e o blockquote sem `> `, com quebras de linha viradas em espaco e
# espacos colapsados (as frases contratuais quebram linha no prompt).
_stubs() {
  awk '
    function flush() {
      if (nm > 0) {
        t = txt
        gsub(/[ \t]+/, " ", t)
        printf "%d|%s|%s\n", start, mk, t
      }
      nm = 0; mk = ""; txt = ""; inq = 0
    }
    /^[ \t]*<!-- ORCH-REF: (root|feature)\/[a-z0-9-]+ -->[ \t]*$/ {
      if (inq) flush()
      if (nm == 0) start = NR
      m = $0
      sub(/^[ \t]*<!-- ORCH-REF: /, "", m); sub(/ -->[ \t]*$/, "", m)
      mk = (nm == 0 ? m : mk "," m); nm++
      next
    }
    nm > 0 && /^[ \t]*>/ {
      l = $0; sub(/^[ \t]*> ?/, "", l)
      txt = txt " " l; inq = 1
      next
    }
    { if (nm > 0) flush() }
    END { flush() }
  ' "$1"
}

# _section_refs <prompt>: texto da secao "## Referencias de fase" (ate o
# proximo `## `), whitespace colapsado.
_section_refs() {
  awk '
    /^## Referencias de fase/ { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' "$1" | tr '\n' ' ' | tr -s ' \t' ' '
}

# _has <texto> <literal>: 0 se o literal (fixo) ocorre no texto.
_has() {
  printf '%s' "$1" | grep -qF -- "$2"
}

# _ref_complete <arquivo>: 0 se a ultima linha e ORCH-REF-END (leitura completa).
_ref_complete() {
  [ -s "$1" ] || return 1
  [ "$(tail -n 1 "$1")" = '<!-- ORCH-REF-END -->' ]
}

# _check_stub_text <texto> <eh_bootstrap> <rotulo>: verifica os literais FR-010.
_check_stub_text() {
  _t="$1"; _b="$2"; _l="$3"
  for _lit in 'Se o comando falhar ou a leitura falhar' \
              'sem o marcador final `ORCH-REF-END`' \
              'NAO execute a fase de memoria' \
              'registre Decisao (`--classe operacional`)' \
              'bloqueio humano'; do
    _has "$_t" "$_lit" || { _fail "stub sem literal FR-010" "$_l: '$_lit'"; return 1; }
  done
  if [ "$_b" = 1 ]; then
    for _lit in 'NAO chame `state-ondas.sh start`' \
                'nenhuma onda esta aberta' \
                '`bloqueios.sh register`' \
                'devolva o turno ao command pai IMEDIATAMENTE' \
                'sem relatorio de onda e sem `Schedule intent`'; do
      _has "$_t" "$_lit" || { _fail "stub bootstrap sem literal" "$_l: '$_lit'"; return 1; }
    done
  else
    _has "$_t" 'encerre a onda' || { _fail "stub sem 'encerre a onda'" "$_l"; return 1; }
    # Stub de fase COM onda aberta nao pode mandar devolver o turno sem fechar.
    if _has "$_t" 'devolva o turno ao command pai'; then
      _fail "stub de fase comum com instrucao da variante bootstrap" "$_l"; return 1
    fi
  fi
  return 0
}

# ==== 7.2.1 / 7.2.2: stubs ====

_check_all_stubs() {
  _prompt="$1"; _orch="$2"
  [ -f "$_prompt" ] || { _error "prompt ausente" "$_prompt"; return 2; }
  _out=$(_stubs "$_prompt")
  [ -n "$_out" ] || { _fail "nenhum stub encontrado" "$_prompt"; return 1; }
  _n=0
  _boot=0
  _oldifs="$IFS"
  IFS='
'
  for _rec in $_out; do
    IFS="$_oldifs"
    _line=${_rec%%|*}
    _rest=${_rec#*|}
    _mk=${_rest%%|*}
    _txt=${_rest#*|}
    _isb=0
    case ",$_mk," in *",$_orch/bootstrap,"*) _isb=1; _boot=$((_boot + 1)) ;; esac
    _check_stub_text "$_txt" "$_isb" "$(basename "$_prompt"):$_line [$_mk]" || return 1
    _n=$((_n + 1))
    IFS='
'
  done
  IFS="$_oldifs"
  [ "$_boot" -ge 1 ] || { _fail "stub bootstrap ausente" "$_prompt"; return 1; }
  return 0
}

scenario_todo_stub_de_O_traz_a_instrucao_de_falha_segura() {
  _check_all_stubs "$ROOT_PROMPT" root || return 1
}

scenario_todo_stub_de_F_traz_a_instrucao_de_falha_segura() {
  _check_all_stubs "$FEATURE_PROMPT" feature || return 1
}

_check_section() {
  _prompt="$1"; _orch="$2"
  _s=$(_section_refs "$_prompt")
  [ -n "$_s" ] || { _fail "secao 'Referencias de fase' ausente" "$_prompt"; return 1; }
  for _lit in "orchestrator-refs.sh path --orchestrator $_orch --phase" \
              'tool Read' \
              'NAO prossiga de memoria' \
              '`--classe operacional`' \
              'bloqueio-humano-referencia-de-fase' \
              '`bloqueios.sh register`' \
              'encerre a onda com `--motivo-termino bloqueio_humano`' \
              'Schedule intent: none; motivo=bloqueio_humano' \
              'ORCH-REF-END'; do
    _has "$_s" "$_lit" || { _fail "secao sem literal FR-010" "$(basename "$_prompt"): '$_lit'"; return 1; }
  done
  # variante bootstrap (7.2.2)
  for _lit in 'Variante `bootstrap`' \
              'NAO chame `state-ondas.sh start`, `record-skill` nem `end`' \
              'devolva o turno ao command pai IMEDIATAMENTE' \
              'sem relatorio de onda e sem `Schedule intent`'; do
    _has "$_s" "$_lit" || { _fail "secao sem variante bootstrap" "$(basename "$_prompt"): '$_lit'"; return 1; }
  done
  return 0
}

scenario_secao_referencias_de_fase_de_O_traz_falha_e_variante_bootstrap() {
  _check_section "$ROOT_PROMPT" root || return 1
}

scenario_secao_referencias_de_fase_de_F_traz_falha_e_variante_bootstrap() {
  _check_section "$FEATURE_PROMPT" feature || return 1
}

# Error case do proprio teste: stub mutilado (sem a instrucao) e reprovado.
scenario_stub_sem_a_instrucao_de_falha_e_reprovado() {
  _bad="$TMPDIR_TEST/bad.md"
  cat > "$_bad" <<'EOF'
### 5.x Secao movida

<!-- ORCH-REF: root/clarify -->
> **Movida para referencia de fase.** Fase/condicao: etapa `clarify`.
> Leia a referencia e siga em frente.

texto seguinte
EOF
  _txt=$(_stubs "$_bad" | sed -e 's/^[0-9]*|[^|]*|//')
  [ -n "$_txt" ] || { _fail "stub de teste nao reconhecido" "$_bad"; return 1; }
  _check_stub_text "$_txt" 0 "bad.md" >/dev/null 2>&1 \
    && { _fail "stub mutilado deveria ser reprovado" "$_bad"; return 1; }
  return 0
}

# ==== 7.2.3: leitura truncada = falha de leitura ====

scenario_referencia_real_termina_no_marcador_final() {
  _n=0
  for _f in "$REFS_DIR"/root/*.md "$REFS_DIR"/feature/*.md; do
    [ -f "$_f" ] || { _error "referencia ausente" "$_f"; return 2; }
    _ref_complete "$_f" || { _fail "referencia sem ORCH-REF-END como ultima linha" "$_f"; return 1; }
    _n=$((_n + 1))
  done
  [ "$_n" -gt 0 ] || { _fail "nenhuma referencia" "$REFS_DIR"; return 1; }
}

scenario_leitura_truncada_e_detectada() {
  _src="$REFS_DIR/feature/specify.md"
  [ -f "$_src" ] || { _error "referencia ausente" "$_src"; return 2; }
  # (a) sem a ultima linha (truncamento no fim)
  sed '$d' "$_src" > "$TMPDIR_TEST/trunc-end.md"
  _ref_complete "$TMPDIR_TEST/trunc-end.md" \
    && { _fail "truncamento no fim nao detectado" "$TMPDIR_TEST/trunc-end.md"; return 1; }
  # (b) cortada no meio (limite de leitura)
  _half=$(( $(wc -l < "$_src" | tr -d ' ') / 2 ))
  head -n "$_half" "$_src" > "$TMPDIR_TEST/trunc-mid.md"
  _ref_complete "$TMPDIR_TEST/trunc-mid.md" \
    && { _fail "truncamento no meio nao detectado" "$TMPDIR_TEST/trunc-mid.md"; return 1; }
  # (c) marcador presente mas nao na ultima linha (conteudo apos o marcador)
  { cat "$_src"; printf 'lixo apos o marcador\n'; } > "$TMPDIR_TEST/trailing.md"
  _ref_complete "$TMPDIR_TEST/trailing.md" \
    && { _fail "marcador fora da ultima linha aceito" "$TMPDIR_TEST/trailing.md"; return 1; }
  # (d) arquivo vazio
  : > "$TMPDIR_TEST/empty.md"
  _ref_complete "$TMPDIR_TEST/empty.md" \
    && { _fail "arquivo vazio aceito" "$TMPDIR_TEST/empty.md"; return 1; }
  # (e) controle positivo: original passa
  _ref_complete "$_src" || { _fail "controle positivo reprovado" "$_src"; return 1; }
  return 0
}

# ==== 7.2.3: leitura unica por fase (SC-006) ====

_check_single_ref_per_phase() {
  _prompt="$1"; _orch="$2"
  _out=$(_stubs "$_prompt")
  _oldifs="$IFS"
  IFS='
'
  for _rec in $_out; do
    IFS="$_oldifs"
    _line=${_rec%%|*}
    _mk=$(printf '%s' "${_rec#*|}" | sed 's/|.*//')
    # Todo marcador do stub pertence ao MESMO orquestrador do prompt
    # (nenhuma referencia compartilhada entre O e F).
    _dups=$(printf '%s\n' "$_mk" | tr ',' '\n' | sort | uniq -d)
    [ -z "$_dups" ] || { _fail "stub cita a mesma referencia mais de uma vez" "$(basename "$_prompt"):$_line $_dups"; return 1; }
    for _m in $(printf '%s\n' "$_mk" | tr ',' ' '); do
      case "$_m" in
        "$_orch"/*) ;;
        *) _fail "stub cita referencia de outro orquestrador" "$(basename "$_prompt"):$_line $_m"; return 1 ;;
      esac
    done
    IFS='
'
  done
  IFS="$_oldifs"
  return 0
}

scenario_cada_stub_cita_no_maximo_uma_referencia_por_fase() {
  _check_single_ref_per_phase "$ROOT_PROMPT" root || return 1
  _check_single_ref_per_phase "$FEATURE_PROMPT" feature || return 1
}

scenario_secao_declara_leitura_unica_por_onda_e_releitura_em_retomada() {
  for _pair in "$ROOT_PROMPT:/agente-00c-resume" "$FEATURE_PROMPT:/feature-00c-resume"; do
    _p=${_pair%%:*}
    _r=${_pair#*:}
    _s=$(_section_refs "$_p")
    for _lit in 'leia o arquivo INTEIRO com a tool Read (uma unica chamada)' \
                'Leia UMA vez por onda' \
                'outros stubs da mesma fase nao geram nova leitura' \
                "Em retomada (\`$_r\`) releia a referencia da fase corrente"; do
      _has "$_s" "$_lit" || { _fail "secao sem regra de leitura unica" "$(basename "$_p"): '$_lit'"; return 1; }
    done
  done
}

run_all_scenarios "$@"
