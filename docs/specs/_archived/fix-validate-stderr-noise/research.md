# Research: fix-validate-stderr-noise

Phase 0 do `/plan`. Esta feature tem escopo cirurgico — so duas decisoes
tecnicas merecem registro formal.

## Decision 1: Padrao de substituicao

**Decision**: aplicar literalmente o mesmo fix do commit `ead1b68` em `metrics.sh`:

```diff
- VAR=$(grep -c PATTERN "$FILE" 2>/dev/null || printf '0')
+ VAR=$(grep -c PATTERN "$FILE" 2>/dev/null) || VAR=0
```

**Rationale**:

- Foi a solucao validada empiricamente no bug historico. Funcionou,
  passou teste de regressao, zero efeitos colaterais observados em 44
  scenarios de suite.
- Preserva semantica: em match, `VAR=<contagem>`; em no-match,
  `grep -c` emite "0" mas sai com codigo 1, disparando `|| VAR=0` que
  sobrescreve com valor limpo (sem newline embedded).
- Evita inventar padrao novo quando existe receita pronta que a base
  de codigo ja conhece.

**Alternatives considered**:

- **Usar `awk` em vez de `grep -c`**: evitaria a idiossincrasia do
  `grep -c` no-match retornando 1, mas troca um idioma POSIX familiar
  por outro. Rejeitado: mudanca de estilo nao-justificada.
- **Redirecionar stderr para /dev/null no ponto de uso**: mascara o
  sintoma sem resolver a causa. Rejeitado: o padrao quebrado continuaria
  no codigo, podendo reaparecer em outros contextos.
- **Eliminar `|| printf '0'` totalmente (confiar no `${VAR:-0}` da
  linha 246)**: parcial, deixa o codigo dependente de fallback remoto
  para corretude de uma linha anterior — fragil. Rejeitado: o idioma
  `cmd || VAR=0` e localizado e autocontido.

## Decision 2: Fixture e contraparte de teste para a regressao

**Decision**: reutilizar o fixture existente `tests/fixtures/docs-site/valid/`
como caso que reproduzia o sintoma, e adicionar o scenario de regressao
em `tests/test_validate.sh` como `scenario_stderr_limpo_em_docs_validos`.

**Rationale**:

- `valid/` e o pior-caso para o bug: zero Mermaid, zero links internos,
  zero blocks, zero frontmatter — ou seja, `ERRORS=0` e `WARNINGS=0` no
  caminho do `grep -c`, que e exatamente quando o `|| printf '0'` dispara
  e concatena `"0\n0"`. Execucao atual produz 4 linhas de "integer
  expression expected" em stderr para este fixture (maior sinal-ruido).
- O `valid/` ja e usado pelo `scenario_docs_validos`, mas esse scenario
  so verifica exit 0 + presenca de "Nenhum issue encontrado" em stdout.
  Nao olha stderr. A nova regressao complementa sem duplicar.
- Nome `scenario_stderr_limpo_em_docs_validos` e auto-descritivo. Convencao
  `stderr_limpo` sinaliza o contrato — stderr sem ruido mecanico.

**Alternatives considered**:

- **Criar fixture novo dedicado apenas para o teste**: redundante —
  `valid/` ja reproduz o sintoma com fidelidade. Rejeitado: aumenta
  superficie de manutencao sem ganho.
- **Adicionar a assercao dentro do `scenario_docs_validos` existente**:
  poluiria um scenario com multipla responsabilidade. Rejeitado:
  one-thing-per-scenario e o padrao da suite (ver `fixtures/docs-site/README.md`
  §Principio de um-problema-por-fixture).
- **Testar via grep na propria `validate.sh` (ex: `grep -q "printf '0'"`)**:
  mistura teste de contrato (saida) com teste de implementacao (source
  code). Rejeitado: contrato observavel (stderr limpo) e o invariant
  real; se futuramente alguem refatorar validate.sh preservando stderr
  limpo mas mudando o padrao interno, o teste nao deve quebrar.
