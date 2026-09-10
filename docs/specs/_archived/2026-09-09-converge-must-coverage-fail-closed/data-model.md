# Data Model: Gate de Convergência Recusa Cobertura Zero de MUST

Esta feature **não cria persistência nova**. Ela adiciona (a) um campo de saída
a um relatório já existente e (b) uma instância determinística de uma entidade
já existente. As duas entidades abaixo são as tocadas.

## Entity: MustCoverageReport (saída de `extract-must.sh --coverage`)

Relatório textual em stdout, uma métrica por linha. Entidade **efêmera** (não
persistida): consumida pelo agente na ETAPA 3 da `converge/SKILL.md`.

| Field | Type | Constraints | Notes |
|-------|------|-------------|-------|
| `fontes declaradas` | string (path) | NOT NULL | valor de `--constitution`, literal — **existente** |
| `ocorrencias da palavra MUST no arquivo (contagem independente)` | int >= 0 | NOT NULL | `N`; gramática independente da do parser — **existente** |
| `linhas de regra MUST reconhecidas pelo parser` | int >= 0 | NOT NULL | `M`; mesma regex do modo default — **existente** |
| `principios emitidos` | int >= 0 | NOT NULL | `P` — **existente** |
| `principios emitidos so por rotulo de heading (sem regra MUST lida)` | int >= 0 | `<= P` | `Q` — **existente** |
| `cobertura de MUST` | enum | `ok` \| `zero-reconhecida` \| `sem-must-declarado` | **NOVO** (FR-001) — veredito derivado; sempre a última linha |

### Derivação do veredito (função total de `N` e `M`)

| Guarda (ordem de avaliação) | `cobertura de MUST` | Exit code |
|---|---|---|
| `M > 0` | `ok` | 0 |
| `N > 0 && M == 0` | `zero-reconhecida` | **3** (NOVO) |
| `N == 0` (⇒ `M == 0`) | `sem-must-declarado` | 0 |

Invariantes:
- **INV-1**: `M > 0 ⇒ N > 0`. A regex do parser (`_EM_MUST_RE`) só casa linhas
  contendo a palavra `MUST`, que a contagem independente também casa — logo os
  três estados acima são exaustivos e mutuamente exclusivos (função total).
- **INV-2**: veredito e o aviso em stderr derivam da **mesma** guarda
  (`_em_words > 0 && _em_lines == 0`) — nunca discordam.
- **INV-3**: constituição ausente **não** produz veredito algum (exit 1, saída
  vazia). É estado distinto de `sem-must-declarado`.

### State Transitions

Não aplicável — função pura de leitura, sem estado entre invocações.

## Entity: Gap (achado de convergência) — instância `must-coverage`

`Gap` é entidade **pré-existente** da skill `converge` (in-memory do agente,
materializada na tabela do `ConvergenceReport` e como tarefa em `tasks.md`).
Esta feature define **uma instância determinística** dela.

| Field | Type | Valor fixo desta instância | Fonte |
|-------|------|----------------------------|-------|
| `path` | string | path da constituição do projeto-alvo (`$CONSTITUTION` da ETAPA 1) | FR-003 |
| `origin` | string | `extract-must --coverage` (token literal fechado) | FR-003 |
| `type` | enum | `contradicts` | FR-002 |
| `story_priority` | enum | `P1` (**intrínseca**, não derivada de story) | FR-002 + carve-out §5.2 |
| `must_violated` | bool | `false` | FR-002 / Constitution VI |
| `severity` | enum | `HIGH` (derivado, não digitado) | `severity.sh`, medido |
| `gap_key` | sha256-12 | derivado de `(path, type, origin)` | `converge-tasks.sh gap-key` |
| `criticality_tag` | enum | `[C]` (mapa `HIGH -> [C]`) | `templates/convergence-phase.md` |

### Relationships

- `MustCoverageReport.cobertura de MUST = zero-reconhecida` **1:0..1** `Gap(must-coverage)`
  — cardinalidade máxima **1 por execução**; os outros dois vereditos produzem 0.
- `Gap(must-coverage)` **N:1** `ConvergenceStatusRecord` — entra na contagem
  `actionable` (`N`) por ser `type=contradicts` (ETAPA 7).

### Idempotência entre execuções

`gap_key` é função de `(path, type, origin)`, todos fixos ⇒ chave **estável**.
Uma 2ª execução de `converge` sobre a mesma feature encontra a chave em
`converge-tasks.sh existing-keys` e **não** duplica a tarefa (FR-012 da
feature-base `skill-converge`, `docs/specs/_archived/2026-07-28-skill-converge/spec.md`). O achado continua contando em `N` na ETAPA 7
enquanto a condição persistir — o que preserva FR-004/SC-001 sem reapendar fase.

### State Transitions

```
zero-reconhecida  --(corrigir marcação na constitution do alvo)-->  ok
                  --(remover todo MUST da constitution do alvo)-->  sem-must-declarado
```

Nos dois destinos o achado deixa de ser gerado na execução seguinte; a tarefa
já apendada em `tasks.md` permanece (append-only, FR-009 da feature-base `skill-converge`, `docs/specs/_archived/2026-07-28-skill-converge/spec.md`) e é
fechada pelo operador marcando o checkbox.
