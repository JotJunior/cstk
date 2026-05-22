# Contract: Exact Text of Amendment 1.1.0

Este arquivo especifica o texto literal a ser inserido em `docs/constitution.md`
como parte do amendment 1.1.0. E o "contrato" — a tarefa de execucao copia este
bloco sem alteracoes semanticas.

## Insertion Point 1: Sync Impact Report (topo do arquivo)

**Localizacao**: dentro do comentario HTML `<!-- Sync Impact Report ... -->` ja
existente, logo apos a linha `- Version: (none) → 1.0.0 [initial ratification]`.

**Bloco a inserir**:

```
- Version: 1.0.0 → 1.1.0  [MINOR: optional-deps carve-out]
- Bump rationale: amendment que adiciona subsecao no Principio II disciplinando
  "deps opcionais com fallback graceful" em tres condicoes cumulativas.
- Principios afetados: II expandido (nao alterado); I/III/IV/V inalterados.
- Secoes modificadas: Principio II recebe subsecao "Optional dependencies with
  graceful fallback". Decision Framework item 4 recebe nota clarificadora.
- Artefatos que precisam atualizacao:
  * docs/specs/cstk-cli/plan.md §Complexity Tracking: substituir "Violacao de
    Principio II" por referencia ao amendment 1.1.0 e demonstracao das tres
    condicoes. PENDENTE ate FR-010 ser executado.
  * CLAUDE.md: opcional — adicionar ponteiro se considerado relevante. NAO URGENTE.
- TODOs pendentes: nenhum bloqueante.
```

## Insertion Point 2: Subsecao no Principio II

**Localizacao**: `docs/constitution.md`, dentro de `### II. Scripts POSIX sh
Puros, Zero Dependencia Externa (NON-NEGOTIABLE)`, imediatamente apos a ultima
linha do bloco `**MUST:**` (que termina em `Exit codes convencionais (0 sucesso,
1 erro geral, 2 uso incorreto).`) e antes da linha em branco que precede
`**Rationale:**`.

**Bloco a inserir** (separado por linhas em branco antes e depois):

```markdown
#### Optional dependencies with graceful fallback (amendment 1.1.0)

Excecao disciplinada a regra geral de zero dependencia externa. Uma ferramenta
nao-POSIX PODE ser invocada por codigo do toolkit desde que as tres condicoes
abaixo sejam CUMULATIVAS (todas MUST ser satisfeitas):

(a) **Uso genuinamente opcional com fallback graceful documentado E verificavel.**
    A feature MUST funcionar sem a ferramenta; quando ausente, o fallback
    produz resultado correto (possivelmente com UX degradada) e MUST ser coberto
    por teste automatizado.
(b) **Codigo que referencia a dep confinado em UM unico arquivo identificavel.**
    A dep nao se espalha pela codebase — grep pelo nome do executavel localiza
    todas as mencoes em um unico arquivo fonte.
(c) **Dep declarada explicitamente na documentacao da feature que a introduz.**
    A dep aparece em `spec.md` ou `plan.md` da feature com justificativa, caminho
    do arquivo confinado (condicao b) e descricao do fallback (condicao a).

**O que NAO muda:**

- Bash-isms permanecem proibidos em qualquer script (opcional ou nao). A
  disciplina POSIX sh do bloco MUST acima continua integral.
- Ferramentas ja banidas nominalmente (`ripgrep`, `fd`, `bats`) permanecem
  vetadas inclusive como deps opcionais — este carve-out nao as reabilita.
- Dependencias obrigatorias (sem fallback) permanecem proibidas sob o bloco MUST
  do Principio II.

**Primeiro caso concreto sob esta regra**: dep opcional em `jq` em
`cli/lib/hooks.sh` da feature `cstk-cli`, introduzida em amendment 1.1.0. Ver
[specs/cstk-cli/spec.md](specs/cstk-cli/spec.md) §FR-009d e
[specs/cstk-cli/plan.md](specs/cstk-cli/plan.md) §Complexity Tracking.
```

## Insertion Point 3: Nota no Decision Framework item 4

**Localizacao**: `docs/constitution.md`, secao `## Decision Framework`, item
numerado `4.`. Apos a frase existente `Excecao a MUST (Principios I, II, IV)
exige amendment da constitution — nao ha opt-out tacito.`, adicionar nova frase
no mesmo paragrafo.

**Frase a adicionar** (apos o ponto final existente, separado por um espaco):

```
Subsecoes de carve-out dentro de um Principio (como a subsecao "Optional
dependencies with graceful fallback" sob Principio II, introduzida em amendment
1.1.0) sao mecanismo valido de conformidade quando precedidas por amendment com
MINOR bump — representam disciplina explicita do principio, nao opt-out.
```

## Insertion Point 4: Version Footer

**Localizacao**: ultima linha do arquivo.

**Substituicao** (transformacao exata):

- De: `**Version**: 1.0.0 | **Ratified**: 2026-04-20 | **Last Amended**: 2026-04-20`
- Para: `**Version**: 1.1.0 | **Ratified**: 2026-04-20 | **Last Amended**: 2026-04-24`

Apenas `Version` e `Last Amended` mudam. `Ratified` permanece imutavel.

## Pos-Amendment: Edicoes Downstream

### Edit A: cstk-cli/plan.md §Complexity Tracking

**Localizacao**: `docs/specs/cstk-cli/plan.md`, secao `## Complexity Tracking`.

**Transformacao**:

- Substituir o sub-heading `### Exception: jq como dependencia opcional para merge
  de settings.json` por `### Optional-dep registry: jq em cli/lib/hooks.sh
  (conforme constitution 1.1.0)`.
- Reescrever o paragrafo de abertura substituindo:

  > **Violacao**: Principio II (SHOULD/MUST), secao "Zero dependencia externa alem
  > de ferramentas POSIX canonicas". `jq` esta explicitamente listada como banida
  > entre "Ferramentas nao-POSIX (`jq`, `ripgrep`, `fd`, `bats`) estao banidas em
  > scripts que acompanham skills".

  por:

  > **Base legal**: constitution 1.1.0 §Principio II subsecao "Optional
  > dependencies with graceful fallback" autoriza deps nao-POSIX quando as tres
  > condicoes cumulativas sao satisfeitas. Abaixo, demonstracao ponto-a-ponto de
  > conformidade:
  >
  > - **(a) Uso opcional com fallback verificavel**: CLI detecta `jq` via
  >   `command -v jq`. Sem `jq`, imprime JSON para paste manual (FR-009d).
  >   Fallback coberto por teste 7.1.5 (scenario 5 do quickstart).
  > - **(b) Confinamento em unico arquivo**: todas as referencias a `jq`
  >   residem exclusivamente em `cli/lib/hooks.sh`. Verificavel via `grep -rn jq
  >   cli/` retornando apenas esse path.
  > - **(c) Declaracao explicita**: esta subsecao do plan.md, alem de FR-009d
  >   da spec.md, documenta a dep.

- Atualizar a tabela no final da secao substituindo "Violacao" por "Caso
  registrado" na primeira coluna.

### Edit B: Re-run de `/analyze` em cstk-cli

Apos Edits A e Insertions 1-4, rodar mentalmente (ou via skill) `/analyze` em
`docs/specs/cstk-cli/`. Expectativa: finding D1 ("jq exception") nao aparece
como CRITICAL — e substituido por ausencia (ja que conformidade esta
demonstrada) ou, se a skill ainda flagar, por severidade MEDIUM/LOW descrevendo
apenas "documentado sob constitution 1.1.0".
