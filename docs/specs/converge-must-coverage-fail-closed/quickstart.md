# Quickstart: Gate de Convergência Recusa Cobertura Zero de MUST

Cenários que validam a implementação. Todos são executáveis sem rede, sem
serviço subindo e sem estado compartilhado — a feature é single-layer (POSIX sh
+ prosa normativa de skill). Cenários 1-5 viram casos em
`tests/test_extract-must.sh`; 6-8 são verificação manual/textual.

> **Nota sobre o Scenario "Roundtrip End-to-End"** do template: **N/A** — não há
> borda backend↔frontend, endpoint HTTP nem payload serializado nesta feature
> (ver `plan.md` §Convenções de Borda).

## Scenario 1: Cobertura zero — o caso da issue #173 (happy path do gate)

1. Criar `constitution.md` temporária com a palavra MUST **só em prosa**:
   ```
   ### I. Primeiro
   Nota: o time MUST revisar cada release antes de publicar.
   ```
2. Rodar `extract-must.sh --constitution <tmp> --coverage`; capturar stdout e `$?`.
3. **Expected**:
   - stdout contém `ocorrencias da palavra MUST no arquivo (contagem independente): 1`
   - stdout contém `linhas de regra MUST reconhecidas pelo parser: 0`
   - stdout contém `cobertura de MUST: zero-reconhecida`
   - exit code = `3`
   - stderr contém `NAO cobre as regras MUST deste arquivo` (aviso preservado)

## Scenario 2: Cobertura ok — nenhum achado (FR-006, SC-002)

1. Criar `constitution.md` com pelo menos uma linha rotulada **e** MUST em prosa:
   ```
   ### I. Primeiro (NON-NEGOTIABLE)
   **MUST:** toda escrita e atomica.
   Nota: o time MUST revisar.
   ```
2. Rodar `extract-must.sh --constitution <tmp> --coverage`.
3. **Expected**: `linhas de regra MUST reconhecidas pelo parser: 1` (>= 1);
   `cobertura de MUST: ok`; exit code = `0`.

## Scenario 3: Nenhum MUST declarado — nenhum achado (FR-005, SC-002)

1. Criar `constitution.md` sem a palavra MUST em lugar nenhum:
   ```
   ### I. Primeiro
   Preferimos simplicidade a abstracao prematura.
   ```
2. Rodar `extract-must.sh --constitution <tmp> --coverage`.
3. **Expected**: `ocorrencias da palavra MUST no arquivo (contagem independente): 0`;
   `cobertura de MUST: sem-must-declarado`; exit code = `0`;
   **nenhum** aviso em stderr.

## Scenario 4 (error case): constituição ausente permanece exit 1

1. Rodar `extract-must.sh --constitution <path-inexistente> --coverage`.
2. **Expected**: exit code = `1`; stdout **vazio** (nenhuma linha `cobertura de
   MUST:` é impressa); stderr contém `constitution.md ausente`. Estado distinto
   de `sem-must-declarado` (Edge Case da spec, `data-model.md` INV-3).

## Scenario 5: Compatibilidade — modo default e as 5 linhas existentes

1. Rodar `extract-must.sh --constitution <tmp> ` (**sem** `--coverage`) sobre a
   fixture do Scenario 2.
2. **Expected**: saída TSV inalterada (`<identificador>\t<titulo>`), sem
   nenhuma linha `cobertura de MUST:`; exit code `0`.
3. Rodar **com** `--coverage` e comparar as 5 primeiras linhas com a saída
   pré-mudança.
4. **Expected**: as 5 linhas existentes byte-idênticas, em ordem; a nova é a
   **6ª** (mudança estritamente aditiva).

## Scenario 6: Severidade do achado é HIGH e é derivada, não digitada

1. Rodar `severity.sh --type contradicts --priority P1 --must-violated false`.
2. **Expected**: stdout exatamente `HIGH`; exit `0`; nenhum arquivo do repo
   modificado (`severity.sh` permanece intocado no diff da feature).

## Scenario 7: SC-003 — constituição recém-gerada nunca nasce com cobertura zero

1. Transcrever, **verbatim**, o texto-semente de Veracidade de Dados tal como
   ele aparece em `plugins/cstk/skills/constitution/SKILL.md` §3.2 (pós-mudança)
   para um `constitution.md` temporário — simulando o que a skill produz.
2. Rodar `extract-must.sh --constitution <tmp> --coverage`.
3. **Expected**: `linhas de regra MUST reconhecidas pelo parser: >= 1` e
   `cobertura de MUST: ok`. Se o resultado for `zero-reconhecida`, a marcação do
   texto-semente regrediu (tipicamente: voltou a ficar sob prefixo `> `).

> Este cenário é o **anti-regressão do gotcha do blockquote**: `> **MUST:**` não
> é reconhecido pelo parser (medido). Transcrever *verbatim* é exatamente o que
> a instrução "Texto-semente" convida a fazer.

## Scenario 8: FR-009 — nenhuma constituição existente é tocada

1. Antes da implementação, registrar `sha256` de `docs/constitution.md` deste
   repositório.
2. Após a implementação completa, recalcular.
3. **Expected**: hashes idênticos; `git diff --name-only` da feature **não**
   contém `docs/constitution.md`. (O hash também é validado a cada retomada da
   execução autônoma — divergência abriria bloqueio por drift.)

## Scenario 9: Dogfooding — o `converge` desta própria pipeline não se auto-acusa

1. Com a mudança aplicada, rodar
   `extract-must.sh --constitution docs/constitution.md --coverage` na raiz
   deste repositório.
2. **Expected**: `linhas de regra MUST reconhecidas pelo parser: 5` e
   `cobertura de MUST: ok` ⇒ nenhum achado desta feature dispara contra a
   constituição deste repo quando a etapa `converge` rodar (`research.md`
   Decision 9).
