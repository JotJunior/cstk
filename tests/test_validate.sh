#!/bin/sh
# test_validate.sh — cobre plugins/cstk/skills/validate-docs-rendered/scripts/validate.sh.
#
# Contrato declarado no cabecalho do script:
#   "Exit code: 0 se zero ERROs, 1 se houver ERROs."
#
# ATENCAO — UM bug latente em validate.sh foi descoberto na FASE 2 deste
# backlog e esta registrado em docs/specs/shell-scripts-tests/tasks.md:
#
#   (a) Mesmo padrao 'grep -c || printf "0"' do bug historico de metrics.sh
#       gera "[: 0\n0: integer expression expected" em stderr nas linhas
#       273-284 de validate.sh. Nao afeta exit code nem stdout — so polui
#       stderr. Os scenarios abaixo tolerarem esse stderr noise; nao usam
#       assert_stderr_contains para esse padrao.
#
# (Correcao inicial deste cabecalho indicava um segundo bug sobre exit code
# — isso foi uma leitura errada de um `echo exit=$?` apos echo, que sempre
# retorna 0. O exit code real de validate.sh E correto.)

TESTS_ROOT="${TESTS_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$TESTS_ROOT/.." && pwd)}"

. "$TESTS_ROOT/lib/harness.sh"

SCRIPT="$REPO_ROOT/plugins/cstk/skills/validate-docs-rendered/scripts/validate.sh"

# ==== 3.5.1 docs validos ====

scenario_docs_validos() {
  fixture "docs-site/valid" || return 2
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST" || return 1
  # Sinal concreto de sucesso: stdout contem "Nenhum issue encontrado".
  # (Nao usamos '*ERRO*' porque a palavra aparece no header da tabela de
  # resumo, independente de haver ou nao ERROs reais.)
  assert_stdout_contains "Nenhum issue encontrado" || return 1
  # Invariant adicional desbloqueado pelo fix em fix-validate-stderr-noise
  # (FR-006): antes do fix, as comparacoes aritmeticas no bloco "Proximos
  # Passos" do validate.sh falhavam silenciosamente quando ERRORS/WARNINGS
  # eram "0\n0", e a linha "Nenhuma acao necessaria" nunca aparecia. Apos
  # o fix, ela aparece corretamente em docs validos. Ancoramos aqui para
  # que um futuro bug que quebre essa semantica seja detectado.
  assert_stdout_contains "Nenhuma acao necessaria" || return 1
}

# ==== 3.5.2 mermaid quebrado (ver nota sobre bug (b) acima) ====

scenario_mermaid_quebrado() {
  fixture "docs-site/broken-mermaid" || return 2
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST" || return 1
  assert_stdout_contains "Mermaid" || return 1
}

# ==== 3.5.3 link quebrado ====

scenario_link_quebrado() {
  fixture "docs-site/broken-link" || return 2
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST" || return 1
  assert_stdout_contains "Link" || return 1
  assert_stdout_contains "nao-existe.md" || return 1
}

# ==== 3.5.4 frontmatter malformado ====

scenario_frontmatter_malformado() {
  fixture "docs-site/broken-frontmatter" || return 2
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST" || return 1
  assert_stdout_contains "Frontmatter" || return 1
}

# ==== 3.5.5 path inexistente ====

scenario_path_inexistente() {
  capture sh "$SCRIPT" "/caminho/que-nao-existe-xyz-999" || return 2
  if [ "$_CAPTURED_EXIT" -eq 0 ]; then
    _fail "scenario_path_inexistente" "esperado exit != 0 em path inexistente, obtido 0"
    return 1
  fi
  assert_stderr_contains "nao encontrado" || return 1
}

# ==== 3.5.6 default docs/ quando sem argumento ====

scenario_default_docs() {
  # Sem argumento, validate.sh usa "./docs". Cria um docs/ minimo valido
  # no tmpdir e executa o script com CWD=TMPDIR_TEST.
  mkdir -p "$TMPDIR_TEST/docs" || return 2
  # Um arquivo .md simples, sem diagramas/links — so um H1.
  printf '# Doc minimo\n\nConteudo trivial.\n' > "$TMPDIR_TEST/docs/index.md" || return 2
  # Executa no tmpdir. Aceita qualquer exit code (o objetivo e verificar que o
  # fluxo do default nao crasha) mas nao deve ter erros de shell (set -eu
  # aborto, stacktrace). Se comportamento do default mudar, o teste falha.
  capture sh -c "cd '$TMPDIR_TEST' && sh '$SCRIPT'" || return 2
  # Shell errors esperados vao para stderr com padroes caracteristicos.
  case "$_CAPTURED_STDERR" in
    *"unbound variable"*)
      _fail "scenario_default_docs" "stderr contem 'unbound variable' — bug de set -u"
      return 1
      ;;
  esac
}

# ==== Regressao — stderr limpo em docs validos ====
#
# Ref: docs/specs/fix-validate-stderr-noise/spec.md §FR-003, §FR-004, §US2.
# Historia: durante a entrega de shell-scripts-tests descobriu-se que o
# validate.sh emite "integer expression expected" em stderr quando algum
# contador interno nao encontra matches (fixture `valid/` e o pior caso —
# zera ERROS e AVISOS). O padrao `grep -c || printf '0'` nas linhas 244-245
# e analogo ao bug historico de metrics.sh (ead1b68).
#
# Este scenario captura esse contrato negativo: stderr NAO pode conter
# "integer expression expected" nem "[:" apos execucao normal.

scenario_stderr_limpo_em_docs_validos() {
  fixture "docs-site/valid" || return 2
  capture sh "$SCRIPT" "$TMPDIR_TEST" || return 2
  # Invariant: stderr livre de mensagens mecanicas do bug grep -c.
  case "${_CAPTURED_STDERR:-}" in
    *"integer expression expected"*)
      _fail "scenario_stderr_limpo_em_docs_validos" \
        "stderr contem 'integer expression expected' — bug latente do grep -c ativo"
      return 1
      ;;
    *"[: "*)
      _fail "scenario_stderr_limpo_em_docs_validos" \
        "stderr contem '[: ' — sintoma de comparacao aritmetica com valor corrompido"
      return 1
      ;;
  esac
}

# ==== Issue #156: subgraph...end em flowchart/graph ====
#
# A checagem 1b (balanco de blocos) roda para TODO bloco mermaid, nao so
# para sequenceDiagram. Antes do fix ela so reconhecia alt|loop|par|opt|
# critical|rect como abridores, mas contava QUALQUER `end` isolado como
# fechador — logo um flowchart com N subgraphs validos reportava
# "0 abertos, N fechados" e bloqueava o doc com ERRO falso (exit 1).
#
# Um segundo defeito, da mesma checagem, foi encontrado ao corrigir o
# primeiro: o idioma gsub(/(^|\n)...(\n|$)/) consumia o \n terminal do
# match, entao linhas ADJACENTES so contavam uma vez (`^` em awk casa
# inicio da STRING, nao de linha). Isso subcontava o `end` de subgraph
# ANINHADO. Por isso ha scenario dedicado para o caso aninhado.

# _vd_write_mermaid ARQUIVO CORPO -> escreve um .md com um unico bloco
# ```mermaid contendo CORPO em $TMPDIR_TEST.
_vd_write_mermaid() {
  {
    printf '# Doc\n\n'
    printf '```mermaid\n'
    printf '%s\n' "$2"
    printf '```\n'
  } >"$TMPDIR_TEST/$1"
}

scenario_mermaid_flowchart_subgraph_valido() {
  _vd_write_mermaid "flow.md" 'flowchart TD
  subgraph A[Front]
    A1[UI] --> A2[API]
  end
  subgraph B[Back]
    B1[svc] --> B2[db]
  end
  A2 --> B1'
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/flow.md" || return 1
  assert_stdout_not_contains "sem \`end\` correspondente" || return 1
}

scenario_mermaid_subgraph_aninhado_valido() {
  _vd_write_mermaid "nested.md" 'flowchart TD
  subgraph Out[Externo]
    subgraph In[Interno]
      X --> Y
    end
  end'
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/nested.md" || return 1
  assert_stdout_not_contains "sem \`end\` correspondente" || return 1
}

scenario_mermaid_subgraph_sem_titulo_valido() {
  _vd_write_mermaid "bare.md" 'graph LR
  subgraph
    X --> Y
  end'
  assert_exit 0 sh "$SCRIPT" "$TMPDIR_TEST/bare.md" || return 1
  assert_stdout_not_contains "sem \`end\` correspondente" || return 1
}

# Contratos negativos: o fix NAO pode cegar a checagem. Desbalanco real
# — em subgraph ou em alt — continua sendo ERRO com exit 1.

scenario_mermaid_subgraph_sem_end_ainda_erro() {
  _vd_write_mermaid "unclosed-subgraph.md" 'flowchart TD
  subgraph A[Front]
    X --> Y'
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/unclosed-subgraph.md" || return 1
  assert_stdout_contains "sem \`end\` correspondente" || return 1
}

scenario_mermaid_alt_sem_end_ainda_erro() {
  _vd_write_mermaid "unclosed-alt.md" 'sequenceDiagram
  participant A
  participant B
  alt caso
    A->>B: x'
  assert_exit 1 sh "$SCRIPT" "$TMPDIR_TEST/unclosed-alt.md" || return 1
  assert_stdout_contains "sem \`end\` correspondente" || return 1
}

run_all_scenarios
