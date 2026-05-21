---
name: review-features
description: 'GLOBAL feature portfolio dashboard — compare progress, suggest archive/abandon/prioritize. Triggers: "status global", "portfolio de features", "dashboard de features", "comparar features". Cross-feature; for single feature deep-dive use review-task.'
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---

# Skill: Revisar Portfolio de Features

Gere um relatorio comparativo de TODAS as features do projeto, com tabela
agregada de progresso, criticidade pendente e sugestao de acao
(arquivar, abandonar, priorizar ou continuar).

## Pre-requisitos

**Obrigatorio**: pelo menos um diretorio agregador de features. Procurar
nesta ordem:

1. `docs/specs/*/` — padrao SDD (cada feature em sua pasta com `spec.md` + `tasks.md`)
2. `docs/features/*/`
3. Diretorio passado explicitamente pelo usuario

Cada subdiretorio deve conter pelo menos um `tasks.md` para entrar no
relatorio. `spec.md` e opcional (usado para extrair descricao).

## Diferenca para review-task

| Aspecto | review-task | review-features |
|---------|-------------|-----------------|
| Escopo | UMA feature ou projeto | TODAS as features (cross-feature) |
| Saida | Status detalhado + top-3 tasks | Tabela comparativa + sugestao por feature |
| Atualiza arquivos? | Sim (marca tasks `[x]` baseado em evidencia) | Nao (read-only) |
| Pergunta tipica | "qual a proxima task?" | "qual feature priorizar?" |

Se o usuario pediu progresso de UMA feature, use `review-task`. Se pediu
visao global ou comparacao entre features, use esta.

## Proximos passos sugeridos

1. `/review-task` em features marcadas como `PRIORIZAR` para detalhar tasks
2. `/execute-task` na proxima task critica
3. Mover features `ARQUIVAR` para `docs/specs/_archived/` (acao manual,
   pedir confirmacao ao usuario antes de mover)

---

## FLUXO DE EXECUCAO

```
1. DETECCAO     Localizar diretorio raiz das features
     |
2. AGREGACAO    Rodar scripts/aggregate.sh sobre o root
     |
3. ANALISE      Interpretar resultados, identificar outliers
     |
4. RELATORIO    Renderizar tabela + secao de sugestoes acionaveis
```

---

## ETAPA 1: DETECCAO

Procurar root de features nesta ordem (parar no primeiro que existir e
contiver subdiretorios com `tasks.md`):

```bash
ls docs/specs/*/tasks.md 2>/dev/null | head -1     # SDD padrao
ls docs/features/*/tasks.md 2>/dev/null | head -1  # alternativa
```

Se nada for encontrado, pedir ao usuario o caminho do diretorio raiz das
features. Nao inventar caminhos.

---

## ETAPA 2: AGREGACAO

Sempre preferir o script `scripts/aggregate.sh` (mesmo diretorio desta
skill) ao inves de parsear arquivos manualmente. O script e deterministico,
testado e produz tanto markdown quanto JSON-lines.

```bash
# Tabela markdown completa
bash skills/review-features/scripts/aggregate.sh docs/specs/

# Apenas JSON-lines (uma linha por feature) para consumo programatico
bash skills/review-features/scripts/aggregate.sh --json docs/specs/
```

### Campos extraidos por feature

| Campo | Origem | Como e calculado |
|-------|--------|------------------|
| `name` | basename do diretorio | `docs/specs/foo/` → `foo` |
| `description` | `spec.md` | 1a linha nao-heading nao-vazia (truncada em 80 chars) |
| `pct_done` | `tasks.md` | `done * 100 / (done + pending + in_progress + blocked)` |
| `criticality` | `tasks.md` | Maior criticidade (`C` > `A` > `M`) com SUBTASKS pendentes |
| `mtime_days` | `tasks.md` | Dias desde ultima modificacao do arquivo |
| `suggestion` | derivado | Ver tabela na ETAPA 3 |

### Convencoes de marcacao reconhecidas

Mesmas que `review-task` usa, vindas do template `create-tasks`:

- Subtarefas: `- [ ]` pendente, `- [~]` em andamento, `- [x]` concluida, `- [!]` bloqueada
- Tarefas (headers `### N.N`) com criticidade: tag `` `[C]` ``, `` `[A]` ``, `` `[M]` ``

---

## ETAPA 3: ANALISE

### Heuristica de sugestao

A sugestao e calculada deterministicamente pelo script. Logica:

| Sugestao | Condicao | Quando aplicar |
|----------|----------|----------------|
| **ARQUIVAR** | `pct_done == 100` | Feature terminou — mover para arquivo morto, liberar espaco mental |
| **ABANDONAR** | `pct_done == 0` AND `mtime_days > 90` | Sem progresso ha 3+ meses — provavelmente morta, confirmar com usuario |
| **PRIORIZAR** | `criticality == C` AND `pct_done < 50` | Tem critico pendente e pouco avanco — risco de divida tecnica/produto |
| **CONTINUAR** | qualquer outro | Em andamento saudavel |
| **INDEFINIDO** | `tasks.md` vazio | Feature foi esbocada mas nao tem tasks definidas |

**Importante**: a sugestao e *recomendacao*, nao automatica. Nunca arquivar
ou abandonar arquivos sem confirmacao explicita do usuario. A skill so
relata; a acao fica com o humano.

### Identificar outliers

Apos rodar o script, destacar no relatorio:

- **Maior risco**: features com `criticality == C` AND `pct_done < 30%`
- **Maior staleness**: features com `mtime_days` mais alto (top 3)
- **Quase prontas**: features com `pct_done >= 80%` mas nao 100% (push final)
- **Stuck**: features com `blocked > 0` (precisam destrave)

---

## ETAPA 4: RELATORIO

### Formato esperado

```markdown
# Relatorio Global de Features

**Data:** YYYY-MM-DD
**Diretorio:** docs/specs/
**Features analisadas:** N

---

## Tabela comparativa

| Feature | Descricao | % Concluida | Criticidade Pendente | Sugestao |
|---------|-----------|-------------|----------------------|----------|
| auth-service | Autenticacao baseada em JWT com refresh | 75% | A | CONTINUAR |
| oauth2-integration | Integracao OAuth2 com Google e GitHub | 0% | C | ABANDONAR |
| analytics-dashboard | Dashboard de metricas para admin | 100% | - | ARQUIVAR |
| billing-rewrite | Reescrita do modulo de cobranca | 30% | C | PRIORIZAR |

---

## Destaques

### Risco alto (priorizar)

- **billing-rewrite** — 30% concluida, criticidade C, ultima atualizacao ha 12 dias.
  Razao: tem subtasks criticas pendentes e progresso lento.

### Quase prontas (push final)

- **auth-service** — 75% concluida. Faltam X subtasks para fechar.

### Provavelmente mortas (confirmar abandono)

- **oauth2-integration** — sem progresso ha 145 dias. Confirmar com stakeholder.

### Concluidas (arquivar)

- **analytics-dashboard** — 100% concluida. Mover para `docs/specs/_archived/`.

---

## Acoes recomendadas

1. **Detalhar billing-rewrite**: rodar `/review-task` em `docs/specs/billing-rewrite/tasks.md`
2. **Validar abandono de oauth2-integration**: confirmar com stakeholder antes de mover
3. **Arquivar analytics-dashboard**: pedir confirmacao do usuario para mover

---

## JSON (para integracoes)

```json
{"name":"auth-service","pct_done":75,...}
{"name":"oauth2-integration","pct_done":0,...}
```
```

### Checklist antes de finalizar o relatorio

- [ ] Rodei `scripts/aggregate.sh` (nao parsei tasks.md manualmente)
- [ ] Tabela cobre TODAS as features encontradas (nenhuma silenciosamente excluida)
- [ ] Destacei pelo menos as categorias de outlier que existem (PRIORIZAR, ARQUIVAR, ABANDONAR)
- [ ] Acoes recomendadas sao concretas (com paths e comandos)
- [ ] Nao tomei nenhuma acao destrutiva (nao movi/deletei nada — so relatei)

---

## Gotchas

### Esta skill NAO substitui review-task

`review-task` analisa UMA feature em profundidade e ATUALIZA o `tasks.md`
quando detecta inconsistencia (task feita mas nao marcada). `review-features`
e cross-feature e read-only. Se o usuario quer entender uma feature
especifica, redirecione para `review-task`.

### Sugestao e recomendacao, nao acao automatica

Nunca arquivar (`mv`/`rm`) ou abandonar arquivos baseado na coluna `Sugestao`.
A skill so produz o relatorio — a acao destrutiva (mover para `_archived/`,
deletar, etc.) precisa de confirmacao explicita do usuario, e mesmo assim
pertence a outra skill ou a um comando direto. Esta skill e read-only.

### `mtime_days` pode mentir em repos com checkout recente

`git clone` reseta o mtime para o momento do checkout, entao todas as
features parecem "novas" depois de clonar. Se a sugestao `ABANDONAR`
aparecer logo apos um clone, suspeitar e usar `git log -1 --format=%cd
docs/specs/feature/tasks.md` para ver a ultima modificacao real.

### Features sem `tasks.md` sao silenciosamente ignoradas

Se uma feature tem so `spec.md` mas nunca foi decomposta em tasks, ela
nao aparece no relatorio. Mencionar isso explicitamente quando relevante
("X features tem spec mas nao tasks — rodar `/create-tasks` nelas").

### Criticidade `-` significa "sem pendentes", nao "sem criticidade"

Quando a coluna criticidade aparece como `-`, e porque a feature tem 0
pendentes (todas concluidas) — nao porque as tasks nao tinham tag `[C/A/M]`.
Se as tasks da feature nao tem tags de criticidade, a coluna fica `-` mesmo
com pendentes, o que indica problema de qualidade do `tasks.md` (faltam
as tags).

### Descricao truncada em 80 caracteres pode esconder contexto

A coluna `Descricao` corta em 80 chars com `...`. Para features com
descricoes longas no `spec.md`, mencionar que detalhes completos estao
no `spec.md` da feature.
