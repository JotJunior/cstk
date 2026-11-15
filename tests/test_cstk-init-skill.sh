#!/bin/sh
# test_cstk-init-skill.sh — assert ESTATICO do SKILL.md da skill cstk-init
# (feature cstk-init, tarefa 5.1.5). Teste de forma/consistencia, nao mapeia 1:1 para um
# script (registrado em tests/run.sh::_is_internal_test).
#
# Ref: spec da feature cstk-init (docs/specs/cstk-init/spec.md) FR-026; Constitution III (formato canonico de skill);
#      docs/specs/cstk-init/contracts/cli-invocation.md.
#
# Cobertura:
#   - frontmatter valido (name = diretorio, description-como-trigger, argument-hint, allowed-tools)
#   - SKILL.md cita os seis scripts init-*.sh, requirement-coverage.sh e secrets-filter.sh
#   - secao ## Gotchas presente, com os itens exigidos pela tarefa 5.1.4
#   - toda flag/subcomando citado no fluxo existe no --help do script correspondente
#   - toda referencia em references/ e templates/ citada no SKILL.md existe
#   - autocontida (tarefa 5.7): nenhum arquivo do subtree cita docs/specs/cstk-init; exemplos de
#     references/markers.md conferidos contra init-provenance.sh lint
#   - write-policy.md (tarefa 5.2): conteudo exigido + Scenario 6 do quickstart conferido contra a
#     politica escrita (constitution emendada por insercao, trecho anterior identico)
#
# POSIX sh puro. Convencao de exit de scenario: 0 PASS, 1 FAIL, 2 ERROR.

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SKILL_DIR="$REPO_ROOT/plugins/cstk/skills/cstk-init"
SKILL="$SKILL_DIR/SKILL.md"

_need_skill() {
  [ -f "$SKILL" ] || { _fail "skill" "SKILL.md ausente: $SKILL"; return 1; }
}

# _frontmatter — imprime so o bloco entre o primeiro e o segundo `---`
_frontmatter() {
  awk 'NR==1 && $0 != "---" { exit 1 } NR>1 && $0 == "---" { exit 0 } NR>1 { print }' "$SKILL"
}

scenario_frontmatter_is_valid() {
  _need_skill || return 1
  _fm=$(_frontmatter) || { _fail "frontmatter" "SKILL.md nao abre com ---"; return 1; }
  [ -n "$_fm" ] || { _fail "frontmatter" "bloco vazio ou nao fechado"; return 1; }
  printf '%s\n' "$_fm" | grep -q '^name: cstk-init$' || { _fail "frontmatter" "name != cstk-init"; return 1; }
  printf '%s\n' "$_fm" | grep -q '^description: ' || { _fail "frontmatter" "description ausente"; return 1; }
  printf '%s\n' "$_fm" | grep -q '^argument-hint: ' || { _fail "frontmatter" "argument-hint ausente"; return 1; }
  printf '%s\n' "$_fm" | grep -q '^allowed-tools:' || { _fail "frontmatter" "allowed-tools ausente"; return 1; }
  for _t in Read Glob Grep Bash Write Edit AskUserQuestion Skill; do
    printf '%s\n' "$_fm" | grep -q "^  - $_t\$" || { _fail "frontmatter" "allowed-tools sem $_t"; return 1; }
  done
  [ "$(basename "$SKILL_DIR")" = "cstk-init" ] || { _fail "frontmatter" "diretorio != name"; return 1; }
}

scenario_description_is_a_trigger_with_skip_targets() {
  _need_skill || return 1
  _d=$(_frontmatter | grep '^description: ')
  for _needle in 'Triggers:' 'cstk-init' 'adotar o cstk' 'adopt cstk' 'Skip for' '(use briefing)' \
                 '(use constitution)' '(use reconcile-docs)'; do
    printf '%s\n' "$_d" | grep -qF -- "$_needle" || { _fail "description" "sem: $_needle"; return 1; }
  done
}

scenario_skill_cites_all_scripts() {
  _need_skill || return 1
  for _s in init-probe.sh init-inventory.sh init-guard.sh init-provenance.sh init-conformance.sh \
            init-candidates.sh requirement-coverage.sh secrets-filter.sh; do
    grep -qF -- "$_s" "$SKILL" || { _fail "scripts" "SKILL.md nao cita $_s"; return 1; }
  done
  # os seis scripts existem e sao executaveis
  for _s in init-probe init-inventory init-guard init-provenance init-conformance init-candidates; do
    [ -x "$SKILL_DIR/scripts/$_s.sh" ] || { _fail "scripts" "$_s.sh ausente ou sem permissao de execucao"; return 1; }
  done
}

scenario_gotchas_section_has_required_items() {
  _need_skill || return 1
  grep -q '^## Gotchas' "$SKILL" || { _fail "gotchas" "secao ## Gotchas ausente"; return 1; }
  _g=$(sed -n '/^## Gotchas/,$p' "$SKILL")
  for _needle in 'procedimental' 'risco residual' 'fail-closed' 'TOCTOU' 'sem ledger' 'TRUNCATED' \
                 'lint invalid' 'Colisao de trigger' 'init-guard.sh check'; do
    printf '%s\n' "$_g" | grep -qF -- "$_needle" || { _fail "gotchas" "sem: $_needle"; return 1; }
  done
}

scenario_hard_rules_are_present() {
  _need_skill || return 1
  grep -q '^## Regras duras' "$SKILL" || { _fail "regras" "secao ## Regras duras ausente"; return 1; }
  _r=$(sed -n '/^## Regras duras/,/^## Fluxo/p' "$SKILL")
  for _needle in 'Inventario antes de qualquer pergunta' 'ate 5 perguntas' '[PENDENTE:' 'Create-only' \
                 'ate 5 candidatas' 'checklist` e `data-model' 'DADO nao confiavel' 'Nunca ecoe valor' \
                 'secrets-filter.sh' 'exit 1'; do
    printf '%s\n' "$_r" | grep -qF -- "$_needle" || { _fail "regras" "sem: $_needle"; return 1; }
  done
}

# FR-035/FR-036/FR-037 (tarefa 7.5.1, achado M1): briefing exibido antes de gravar; imperativo do
# projeto nao vira restricao do briefing; modo nao-interativo so descritivo e com aviso. A regra e
# procedimental (sem lint lexical: ver Gotchas), entao o que se verifica aqui e o texto da skill.
scenario_briefing_shown_before_write_and_no_imperative_copy() {
  _need_skill || return 1
  _r=$(sed -n '/^## Regras duras/,/^## Fluxo/p' "$SKILL")
  for _needle in 'Briefing: mostre antes de gravar' 'NAO vira restricao' '(informado pelo operador)' \
                 'fato descritivo' 'pergunta ao operador'; do
    printf '%s\n' "$_r" | grep -qF -- "$_needle" || { _fail "m1" "regras duras sem: $_needle"; return 1; }
  done
  _b=$(sed -n '/^### 5\. Briefing/,/^### 6\./p' "$SKILL")
  for _needle in 'Mostre o briefing completo ao' 'antes de gravar' 'regra dura 14'; do
    printf '%s\n' "$_b" | grep -qF -- "$_needle" || { _fail "m1" "secao Briefing sem: $_needle"; return 1; }
  done
  _n=$(sed -n '/^## Modo nao-interativo/,/^## Referencias/p' "$SKILL")
  for _needle in 'SO fatos descritivos' 'sem revisao' 'pergunta em aberto'; do
    printf '%s\n' "$_n" | grep -qF -- "$_needle" || { _fail "m1" "modo nao-interativo sem: $_needle"; return 1; }
  done
  _g=$(sed -n '/^## Gotchas/,$p' "$SKILL")
  printf '%s\n' "$_g" | grep -qF -- 'verificacao so procedimental' \
    || { _fail "m1" "Gotchas sem o limite conhecido (sem lint lexical)"; return 1; }
  grep -qF -- 'sem revisao do operador' "$SKILL_DIR/templates/summary.md" \
    || { _fail "m1" "summary.md sem o aviso de briefing nao revisado"; return 1; }
  grep -qF -- 'FR-035' "$SKILL_DIR/references/write-policy.md" \
    || { _fail "m1" "write-policy.md sem a regra de exibicao previa do briefing"; return 1; }
}

scenario_cited_script_flags_exist_in_help() {
  _need_skill || return 1
  _chk() { # _chk <script> <token...>
    _sc=$1; shift
    _h=$(sh "$SKILL_DIR/scripts/$_sc.sh" --help 2>&1) || :
    for _tk in "$@"; do
      printf '%s\n' "$_h" | grep -qF -- "$_tk" || { _fail "flags" "$_sc --help sem $_tk (citado no SKILL.md)"; return 1; }
      grep -qF -- "$_tk" "$SKILL" || { _fail "flags" "SKILL.md nao cita $_tk"; return 1; }
    done
  }
  _chk init-probe preflight artifacts version --skill-dir || return 1
  _chk init-inventory inventory --max-items || return 1
  _chk init-conformance check --catalog-root || return 1
  _chk init-candidates evidence name || return 1
  _chk init-guard check scan migrate --probe --confirmed --op || return 1
  _chk init-provenance lint --file || return 1
}

scenario_skill_cites_only_existing_references() {
  _need_skill || return 1
  # citacoes `[$CATALOG/]<irma>/references|templates/x.md` apontam para skill irma do catalogo
  # (resolvidas contra plugins/cstk/skills/<irma>); as demais, para o subtree desta skill.
  _refs=$(grep -oE '(\$CATALOG/)?([A-Za-z0-9._-]+/)?(references|templates)/[A-Za-z0-9._-]+\.md' "$SKILL" | sort -u)
  [ -n "$_refs" ] || { _fail "refs" "SKILL.md nao cita references/templates"; return 1; }
  for _r in $_refs; do
    _rest=${_r#'$CATALOG/'}
    case "$_rest" in
      references/*|templates/*)
        [ -f "$SKILL_DIR/$_rest" ] || { _fail "refs" "SKILL.md cita $_r que nao existe"; return 1; } ;;
      *)
        [ -f "$REPO_ROOT/plugins/cstk/skills/$_rest" ] \
          || { _fail "refs" "SKILL.md cita $_r que nao existe no catalogo"; return 1; } ;;
    esac
  done
  # as referencias proprias previstas estao todas citadas
  for _r in references/markers.md references/write-policy.md references/conformance-rules.md \
            references/feature-recognition.md templates/reconstructed-spec-addendum.md templates/summary.md; do
    printf '%s\n' "$_refs" | grep -qxF -- "$_r" || { _fail "refs" "SKILL.md nao cita $_r"; return 1; }
  done
}

# ---- convergencia FASE 9 (tarefa 9.1): reconsulta de pendencias e gate cobrem spec reconstituida ----

# _section <titulo-prefixo-nivel-3> — imprime o `### N. ...` do SKILL.md ate o proximo `### `
_section() {
  awk -v p="$1" 'index($0, "### " p) == 1 { f = 1; print; next } f && /^### / { exit } f { print }' "$SKILL"
}

scenario_pending_review_and_gate_cover_reconstructed_specs() {
  _need_skill || return 1
  _s7=$(_section '7.')
  [ -n "$_s7" ] || { _fail "fase9" "secao '### 7.' nao encontrada"; return 1; }
  _s8=$(_section '8.')
  [ -n "$_s8" ] || { _fail "fase9" "secao '### 8.' nao encontrada"; return 1; }
  # §7: a reconsulta de PENDING inclui spec reconstituida (marcador) e os complementares gerados
  for _needle in 'cstk-init:reconstructed' 'spec reconstituida' 'data-model.md' 'checklists/' 'BAD-MARKER'; do
    printf '%s\n' "$_s7" | grep -qF -- "$_needle" || { _fail "fase9" "§7 sem: $_needle"; return 1; }
  done
  # §8 passo 1: o gate de `lint invalid` cobre as specs reconstituidas e os complementares
  _g=$(printf '%s\n' "$_s8" | awk '/^1\. Gate/ { f = 1; print; next } f && /^[0-9]+\. / { exit } f { print }')
  [ -n "$_g" ] || { _fail "fase9" "§8 passo 1 (Gate) nao encontrado"; return 1; }
  for _needle in 'cstk-init:reconstructed' 'reconstituidas' 'data-model.md'; do
    printf '%s\n' "$_g" | grep -qF -- "$_needle" || { _fail "fase9" "§8 passo 1 sem: $_needle"; return 1; }
  done
  # spec nativa (sem marcador) fica fora do escopo
  printf '%s\n%s\n' "$_s7" "$_g" | grep -qi 'sem o marcador' || { _fail "fase9" "nao exclui spec nativa sem o marcador"; return 1; }
}

# FASE 9 (tarefa 9.2): write-policy §4 permite o amend confirmado que preenche pendencia em spec
# reconstituida e complementares gerados, coerente com SKILL.md §7/§8 (9.1).
scenario_write_policy_s4_allows_pending_fill_in_reconstructed_spec() {
  _wp="$SKILL_DIR/references/write-policy.md"
  [ -f "$_wp" ] || { _fail "write-policy" "references/write-policy.md ausente"; return 1; }
  _s4=$(awk '/^## 4\./ { f = 1; print; next } f && /^## / { exit } f { print }' "$_wp")
  [ -n "$_s4" ] || { _fail "fase9" "secao '## 4.' nao encontrada"; return 1; }
  for _needle in 'cstk-init:reconstructed' 'data-model.md' 'checklists/' '[PENDENTE: ...]' \
                 '(fonte: ...)' '(informado pelo operador)' 'SO preenche' 'Spec nativa' \
                 'CR-007' 'missing-section' 'vedada'; do
    printf '%s\n' "$_s4" | grep -qF -- "$_needle" || { _fail "fase9" "write-policy §4 sem: $_needle"; return 1; }
  done
  # coerencia com o SKILL.md (9.1): o mesmo marcador delimita o escopo no §7
  _need_skill || return 1
  _section '7.' | grep -qF 'cstk-init:reconstructed' || { _fail "fase9" "SKILL.md §7 sem o marcador"; return 1; }
}

# ---- references/write-policy.md (tarefa 5.2) ----

scenario_write_policy_documents_required_rules() {
  _wp="$SKILL_DIR/references/write-policy.md"
  [ -f "$_wp" ] || { _fail "write-policy" "references/write-policy.md ausente"; return 1; }
  for _needle in 'create-only' 'bump' 'Sync Impact Report' 'Last Amended' 'MINOR' \
                 'init-guard.sh migrate' 'MOVE' 'confirmacao NOMINAL' 'VCS' 'lote declarado' \
                 'tudo' '`both`' 'texto anterior permanece identico'; do
    grep -qiF -- "$_needle" "$_wp" || { _fail "write-policy" "sem: $_needle"; return 1; }
  done
}

# Scenario 6 do quickstart (fixture legacy) conferido contra a politica escrita:
# migracao recusada = briefing identico; emenda confirmada = so insercao + rodape;
# migrate sem confirmacao nao move; com confirmacao move (MOVE).
scenario_quickstart6_legacy_amend_follows_write_policy() {
  mktemp_test || return 2
  fixture cstk-init/legacy || return 1
  _g="$SKILL_DIR/scripts/init-guard.sh"
  _c="$SKILL_DIR/scripts/init-conformance.sh"
  _p="$SKILL_DIR/scripts/init-provenance.sh"
  _cat="$REPO_ROOT/plugins/cstk/skills"
  _r="$TMPDIR_TEST"
  cp "$_r/docs/01-briefing-discovery/briefing.md" "$_r/.briefing.orig"
  cp "$_r/docs/constitution.md" "$_r/.constitution.orig"

  # (1) divergencias esperadas pelo catalogo
  _out=$(sh "$_c" check --root "$_r" --catalog-root "$_cat") || { _fail "q6" "conformance falhou"; return 1; }
  printf '%s\n' "$_out" | grep -q 'CR-001' || { _fail "q6" "sem CR-001"; return 1; }
  printf '%s\n' "$_out" | grep -q 'missing-section' || { _fail "q6" "sem missing-section"; return 1; }

  # (2) sem confirmacao a emenda e negada; com confirmacao nominal e permitida
  sh "$_g" check --root "$_r" --path docs/constitution.md --op amend >/dev/null 2>&1 \
    && { _fail "q6" "amend sem --confirmed deveria negar"; return 1; }
  sh "$_g" check --root "$_r" --path docs/constitution.md --op amend --confirmed >/dev/null 2>&1 \
    || { _fail "q6" "amend com --confirmed deveria permitir"; return 1; }

  # (3) emenda por insercao (politica §3): Sync Impact Report no topo, secao antes do rodape,
  #     MINOR 1.0.0 -> 1.1.0, Last Amended atualizado, Ratified intacto
  _new="$_r/.constitution.new"
  {
    printf '%s\n' '<!--' 'Sync Impact Report' '- Version: 1.0.0 -> 1.1.0' \
      '- Secoes adicionadas: Governance (origem: cstk-init, regra missing-section)' '-->' ''
    grep -v '^\*\*Version\*\*:' "$_r/docs/constitution.md"
    printf '%s\n' '## Governance' '' '[PENDENTE: quais sao as regras de governanca deste projeto?]' ''
    printf '%s\n' '**Version**: 1.1.0 | **Ratified**: 2025-01-01 | **Last Amended**: 2026-11-14'
  } > "$_new"
  cp "$_new" "$_r/docs/constitution.md"

  # (4) trecho ratificado identico: toda linha original (exceto o rodape) segue presente, na ordem
  grep -v '^\*\*Version\*\*:' "$_r/.constitution.orig" > "$_r/.orig.body"
  _pos=0
  while IFS= read -r _l; do
    [ -n "$_l" ] || continue
    _n=$(grep -nxF -- "$_l" "$_r/docs/constitution.md" | head -n 1 | cut -d: -f1)
    [ -n "$_n" ] && [ "$_n" -ge "$_pos" ] || { _fail "q6" "linha ratificada perdida/reordenada: $_l"; return 1; }
    _pos=$_n
  done < "$_r/.orig.body"
  grep -q 'Ratified\*\*: 2025-01-01' "$_r/docs/constitution.md" || { _fail "q6" "Ratified mudou"; return 1; }

  # (5) apos a emenda: Governance nao e mais divergencia; lint ok/pending; scan clean
  _out=$(sh "$_c" check --root "$_r" --catalog-root "$_cat") || return 1
  printf '%s\n' "$_out" | grep -q 'constitution.md.*missing-section' && { _fail "q6" "missing-section persiste"; return 1; }
  sh "$_p" lint --root "$_r" --file docs/constitution.md | grep -q 'STATUS.pending' \
    || { _fail "q6" "lint deveria ser pending"; return 1; }
  sh "$_g" scan --file "$_r/docs/constitution.md" --catalog-root "$_cat" >/dev/null || { _fail "q6" "scan nao clean"; return 1; }

  # (6) migracao recusada = briefing identico; migrate sem confirmacao nao move
  sh "$_g" migrate --root "$_r" >/dev/null 2>&1 && { _fail "q6" "migrate sem --confirmed deveria falhar"; return 1; }
  cmp -s "$_r/docs/01-briefing-discovery/briefing.md" "$_r/.briefing.orig" || { _fail "q6" "briefing mudou sem confirmacao"; return 1; }

  # (7) migrate confirmado e MOVE
  sh "$_g" migrate --root "$_r" --confirmed >/dev/null || { _fail "q6" "migrate confirmado falhou"; return 1; }
  [ -f "$_r/docs/briefing.md" ] && [ ! -e "$_r/docs/01-briefing-discovery/briefing.md" ] \
    || { _fail "q6" "migrate nao foi MOVE"; return 1; }
  cmp -s "$_r/docs/briefing.md" "$_r/.briefing.orig" || { _fail "q6" "conteudo do briefing mudou no move"; return 1; }
}

# ---- autocontencao da skill (tarefa 5.7) ----

# A skill instalada num projeto de terceiro so leva o proprio subtree: citar a spec interna
# deste repo (docs/specs/cstk-init) deixa o leitor sem a fonte. Nenhum arquivo sob o subtree pode
# citar esse caminho; a gramatica normativa mora em references/markers.md.
scenario_skill_does_not_cite_internal_spec_paths() {
  _need_skill || return 1
  _hits=$(grep -rn -- 'docs/specs/cstk-init' "$SKILL_DIR" 2>/dev/null || true)
  [ -z "$_hits" ] || { _fail "autocontida" "citacao a docs/specs/cstk-init no subtree: $_hits"; return 1; }
  [ -f "$SKILL_DIR/references/markers.md" ] || { _fail "autocontida" "references/markers.md ausente"; return 1; }
  grep -qF 'references/markers.md' "$SKILL" || { _fail "autocontida" "SKILL.md nao cita references/markers.md"; return 1; }
}

# Os exemplos de references/markers.md (aceitos e rejeitados) conferidos contra o lint real.
scenario_markers_reference_matches_lint() {
  mktemp_test || return 2
  _p="$SKILL_DIR/scripts/init-provenance.sh"
  _r="$TMPDIR_TEST"
  mkdir -p "$_r/src"
  printf 'um\ndois\n' > "$_r/src/app.js"

  # _lint <conteudo> <esperado: ok|pending|invalid> <token-esperado-ou-vazio>
  _lint() {
    printf '%s\n' "$1" > "$_r/doc.md"
    _lo=$(sh "$_p" lint --root "$_r" --file doc.md 2>/dev/null); _lx=$?
    printf '%s\n' "$_lo" | grep -q "^STATUS.$2\$" || { _fail "markers" "esperado STATUS $2 para: $1 (obtido: $_lo)"; return 1; }
    [ -z "$3" ] || printf '%s\n' "$_lo" | grep -q "^$3" || { _fail "markers" "esperado $3 para: $1 (obtido: $_lo)"; return 1; }
    return 0
  }

  _lint 'fato (fonte: `src/app.js`) fim' ok '' || return 1
  _lint 'fato (fonte: `src/app.js:2`) fim' ok '' || return 1
  _lint 'fato (informado pelo operador)' ok '' || return 1
  _lint 'campo [PENDENTE: qual o valor?]' pending PENDING || return 1
  _lint 'fato (fonte: src/app.js)' invalid BAD-MARKER || return 1
  _lint 'fato (fonte: `../fora.txt`)' invalid BAD-MARKER || return 1
  _lint 'fato (fonte: `/etc/passwd`)' invalid BAD-MARKER || return 1
  _lint 'fato (fonte: `src/app.js:0`)' invalid BAD-MARKER || return 1
  _lint 'fato (fonte: `nao-existe.txt`)' invalid DANGLING || return 1
  _lint 'fato (fonte: `src/app.js:99`)' invalid DANGLING || return 1
  _lint 'campo [PENDENTE: ]' invalid BAD-MARKER || return 1
  _lint 'campo [PENDENTE sem fechamento' invalid BAD-MARKER || return 1

  # spec reconstituida (secao 3 de markers.md)
  _spec() { # <corpo apos o titulo e o marcador>
    printf '# Feature\n\n<!-- cstk-init:reconstructed -->\n> **Origem**: x\n\n%s\n' "$1" > "$_r/doc.md"
  }
  _spec_lint() { # <esperado> <token>
    _lo=$(sh "$_p" lint --root "$_r" --file doc.md 2>/dev/null)
    printf '%s\n' "$_lo" | grep -q "^STATUS.$1\$" || { _fail "markers" "spec: esperado STATUS $1 (obtido: $_lo)"; return 1; }
    [ -z "$2" ] || printf '%s\n' "$_lo" | grep -q "^$2" || { _fail "markers" "spec: esperado $2 (obtido: $_lo)"; return 1; }
    return 0
  }
  _spec '## Requirements

- **FR-001**: O sistema expoe a rota. (fonte: `src/app.js`)
- **FR-002**: O sistema grava. [PENDENTE: qual arquivo?]'
  _spec_lint pending PENDING || return 1
  _spec '## Requirements

- **FR-003**: O sistema exporta CSV.'
  _spec_lint invalid BAD-MARKER || return 1
  _spec '## Requirements

### Inferido (nao confirmado)

- **INF-001**: O sistema SHOULD cachear.'
  _spec_lint invalid BAD-MARKER || return 1
  _spec '## Success Criteria

- **SC-001**: Responde em 200 ms.'
  _spec_lint invalid BAD-MARKER || return 1
  _spec '## Success Criteria

- **SC-001**: Responde em 200 ms. (fonte: `src/app.js`)'
  _spec_lint ok '' || return 1
  _spec '## Requirements

### User Story 1 - x (Priority: P1)'
  _spec_lint invalid BAD-MARKER || return 1
  # marcador depois do primeiro ## e ausente
  printf '# Feature\n\n## Requirements\n\n<!-- cstk-init:reconstructed -->\n' > "$_r/doc.md"
  _spec_lint invalid BAD-MARKER || return 1
}

run_all_scenarios
