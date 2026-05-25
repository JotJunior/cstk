# Implementation Plan: Agente-00C Artifact Cache

**Feature**: `agente-00c-artifact-cache`
**Spec**: [`spec.md`](./spec.md)
**Created**: 2026-05-20
**Status**: Refinado pos-clarify (Session 2026-05-21)

> Plan refinado apos `/clarify` resolver as 5 Open Questions da spec
> (ver `spec.md` §Clarifications). Decisoes 1-5 consolidadas abaixo;
> sem `[NEEDS CLARIFY]` restantes.

---

## Constitution Check

Verificacao pre-arquitetura contra `docs/constitution.md` do projeto:

| Principio | Decisao arquitetural correspondente |
|-----------|--------------------------------------|
| I. Auditabilidade Total | `state-cache.sh` registra Decisao via `state-decisions.sh register` em toda invalidacao. Metricas em `metricas.cache`. |
| II. Pause-or-Decide | Drift MAJOR → BloqueioHumano; MINOR/PATCH → auto-resolve com Decisao informativa. |
| III. Idempotencia | Cache eh derivado; source eh canonico. Reconstruivel a qualquer momento. |
| IV. Autonomia Limitada | Sem novos loops; invalidacoes nao consomem `ciclos_consumidos`. |
| V. Blast Radius | `state.json` vive em `.claude/agente-00c-state/`; secrets-filter aplicado pre-gravacao; source files read-only. |

**Resultado**: aprovado para `/plan`. Sem violacoes detectadas.

---

## Technical Context

### Linguagem e runtime

- **Primitiva nova `state-cache.sh`**: POSIX shell (sh / bash 3.2+),
  compativel com macOS default. Dependencias externas: `jq`,
  `sha256sum` (linux) / `shasum -a 256` (macos). Mesma stack ja
  usada pelas outras primitivas em `global/skills/agente-00c-runtime/scripts/`.
- **Modificacoes nas skills**: editar `SKILL.md` de `specify`,
  `clarify`, `plan`, `execute-task` para adicionar protocolo de
  leitura FR-CACHE-008 (instrucoes ao LLM em prosa, nao codigo
  executavel — skills sao prompts).

### Limites operacionais

- **Tamanho do resumo**: alvo 1500-2000 chars (~375-500 tokens
  pt-br). Configuravel via campo `config.cache.resumo_max_chars`
  em state.json.
- **Threshold de passthrough**: default 3000 chars (FR-CACHE-007).
- **Timeout de geracao do resumo**: N/A — geracao eh heuristica
  extractiva em POSIX shell, latencia esperada < 100ms para
  arquivos ate 50k chars (resolucao Q1).

### Compatibilidade

- **Schema bump**: state.json schema_version MINOR (ex: 1.4.0 → 1.5.0).
  Campos novos sao opcionais (FR-CACHE-001), sem migracao forcada.
- **Skills standalone**: comportamento preservado (FR-CACHE-014).
- **Execucoes legadas**: state.json sem campos de cache continua
  valido; cache fica vazio, populado na proxima onda 1.

---

## Data Model

### state.json — novos campos

```jsonc
{
  // ... campos existentes ...
  "briefing_cache": {
    "source_path": "/abs/path/to/docs/01-briefing-discovery/briefing.md",
    "source_sha256": "a1b2c3...64chars",
    "source_chars": 8420,
    "resumo": "## Visao\n...\n## Usuarios\n...\n## Restricoes\n...",
    "resumo_chars": 1480,
    "estrategia": "resumo",  // ou "passthrough" ou "desabilitado"
    "gerado_em": "2026-05-20T14:32:11Z",
    "gerado_na_onda": 1
  },
  "constitution_cache": {
    "source_path": "/abs/path/to/docs/constitution.md",
    "source_sha256": "d4e5f6...64chars",
    "source_chars": 11200,
    "resumo": "## Core Principles\n### I. ...\n### II. ...",
    "resumo_chars": 1720,
    "estrategia": "resumo",
    "gerado_em": "2026-05-20T14:33:02Z",
    "gerado_na_onda": 1,
    "version": "1.2.0"  // copia de FR-PRE-004 para audit cross-onda
  },
  "metricas": {
    // ... metricas existentes ...
    "cache": {
      "tokens_cache_hits": 0,
      "tokens_cache_misses_drift": 0,
      "tokens_cache_misses_disabled": 0,
      "tokens_economizados_estimados": 0,
      "ultima_invalidacao": null  // ISO-8601 ou null
    }
  },
  "config": {
    // novo bloco opcional
    "cache": {
      "passthrough_threshold_chars": 3000,
      "resumo_max_chars": 2000,
      "tokens_per_char_ratio": 0.25  // pt-br = 4 chars/tok
    }
  }
}
```

### Decisao auditavel (categoria nova)

```jsonc
{
  "id": "dec-NNN",
  "categoria": "cache-invalidacao",
  "contexto": "drift detectado em constitution.md entre ondas 3 e 4",
  "opcoes": ["regenerar-cache", "abortar-feature", "marcar-cache-stale"],
  "escolha": "regenerar-cache",
  "justificativa": "politica default FR-CACHE-009 (drift MINOR/PATCH = auto-resolve)",
  "agente": "agente-00c-orchestrator",
  "score": 3,
  "registrada_em": "2026-05-20T14:51:08Z"
}
```

---

## API Contracts

### `state-cache.sh` — nova primitiva

Localizacao: `global/skills/agente-00c-runtime/scripts/state-cache.sh`

```bash
# Sintaxe geral
state-cache.sh <subcommand> --state-dir <SD> [opcoes]

# Subcomandos
state-cache.sh ensure --state-dir <SD> --artifact <briefing|constitution> --source-path <PATH>
  # Popula ou atualiza o cache. Detecta drift, gera resumo, aplica secrets-filter, persiste.
  # Exit 0 = cache pronto; exit 1 = arquivo source ausente; exit 2 = falha critica.

state-cache.sh get-resumo --state-dir <SD> --artifact <briefing|constitution>
  # Retorna o resumo via stdout se cache em estado "resumo" + sha256 confirmado.
  # Exit 0 = hit; exit 1 = miss (campo ausente, estrategia != "resumo", ou drift); exit 2 = erro fatal.

state-cache.sh check-drift --state-dir <SD> --artifact <briefing|constitution>
  # Compara sha256 registrado vs hash do arquivo em disco AGORA.
  # Exit 0 = sem drift; exit 1 = drift MINOR/PATCH; exit 2 = drift MAJOR; exit 3 = erro.
  # Para constitution: exit 2 quando version primeiro digito mudou OU >50% chars diff.

state-cache.sh invalidate --state-dir <SD> --artifact <briefing|constitution> --razao <texto>
  # Forca invalidacao. Registra Decisao via state-decisions.sh. Cache fica vazio ate proximo ensure.

state-cache.sh metrics-bump --state-dir <SD> --tipo <hit|miss-drift|miss-disabled> [--chars-economizados N]
  # Incrementa contadores em metricas.cache. Chamado pelas skills apos consumo (ou tentativa).

state-cache.sh status --state-dir <SD> --artifact <briefing|constitution>
  # Imprime JSON com estado completo do cache (path, sha256, estrategia, chars, idade).
  # Exit 0 sempre que state.json eh valido.
```

### Contrato de leitura das skills (FR-CACHE-008)

Skills afetadas (`specify`, `clarify`, `plan`, `execute-task`) terao
em seu `SKILL.md` um bloco novo `## Leitura de artefatos foundational`:

```markdown
## Leitura de artefatos foundational

Antes de ler `briefing.md` ou `docs/constitution.md` direto do disco,
verifique se ha cache valido:

1. Se variavel `AGENTE_00C_STATE_DIR` esta setada OU se
   `<projeto-alvo>/.claude/agente-00c-state/state.json` existe:
   - Invoque via Bash: `state-cache.sh get-resumo --state-dir <SD>
     --artifact <briefing|constitution>`
   - Exit 0 + stdout nao-vazio = use o resumo retornado.
   - Exit 1 = caia em leitura direta do disco.
   - Exit 2 = aborte com diagnostico do stderr (estado corrompido).

2. Caso contrario (rodando standalone): leia direto do disco
   (comportamento atual, sem mudanca).

3. Apos consumo (hit ou miss): chame
   `state-cache.sh metrics-bump --tipo <hit|miss-drift|miss-disabled>
   --chars-economizados N`.
```

---

## Research

### Decisao 1: Geracao do resumo — heuristica extractiva (decidido em clarify)

Opcoes avaliadas:

**A. LLM in-session**: resumo de melhor qualidade semantica, mas
paga tokens extras na onda 1, nao deterministico, dependente do
prompt-cache hit.

**B. Heuristica extractiva** (escolhida): deterministico, zero
tokens, trivial de testar. Algoritmo:
1. Extrair todos os `## H2` e `### H3` headings preservando ordem
   e hierarquia.
2. Para cada heading, extrair a primeira linha de corpo nao-vazia
   imediatamente abaixo dele.
3. Concatenar como markdown valido.
4. Se output excede `resumo_max_chars` (default 2000), dropar
   `### H3` em ordem inversa (do fim para o comeco) ate caber.
5. Mesma entrada de bytes => mesma saida de bytes.

**C. Hibrido (heuristica + LLM fallback)**: descartado por adicionar
caminho duplicado em codigo POSIX puro sem ganho mensuravel.

**Reavaliacao para v2**: plug-in LLM-summarizer pode ser avaliado se
SC-001 falhar no piloto T4.2.

### Decisao 2: Threshold de passthrough — 3000 chars (decidido em clarify)

Default fixo de **3000 chars**, com override opcional via
`config.cache.passthrough_threshold_chars` em `state.json`.

Racional: arquivo pequeno cabe em ~750 tokens. Re-leitura por skill
gera <1k tokens overhead. Geracao de resumo (heuristica) exige
fork+exec de shell por onda, custo nao-zero. Break-even empirico em
torno de 3-4k chars.

Threshold dinamico proporcional a ondas esperadas foi descartado —
exige heuristica que so estima, nao mede; mais complexidade sem
ganho confiavel.

### Decisao 3: Cache da constitution raiz vs feature-delta (decidido em clarify)

Cachear apenas a **constitution ativa** — resolvida via
`pipeline.sh constitution-conflict` (primitiva ja existente):
- Sem feature-delta no projeto: cache aponta para `docs/constitution.md` raiz.
- Com feature-delta: cache aponta para `docs/specs/<feat>/constitution.md`.

UM campo unico `constitution_cache` em `state.json`, com
`source_path` indicando qual constitution foi cacheada. Constitution
raiz nao referenciada pela feature corrente nao consome espaco no
cache.

Opcao "cachear ambas separadamente" descartada — duplica dados sem
ganho de comportamento (skills so consomem a ativa).

### Decisao 4: Re-geracao em retomada (decidido em clarify)

**Confiar no backup-de-onda quando hash bate**. Na retomada:
1. Le `state.json` (com cache) do backup-de-onda anterior.
2. Valida `briefing_cache.source_sha256` contra hash do arquivo source em disco AGORA.
3. Hash igual = cache valido, prossegue normalmente.
4. Hash diferente = trata como drift padrao (FR-CACHE-009 auto-regen
   ou FR-CACHE-010 BloqueioHumano se MAJOR).

Reusa logica de `feature-00c-preflight.sh` ja existente, estendida
para validar campos de cache.

Flag opcional `--regenerate-cache` em /agente-00c-resume foi
descartada — drift detection ja cobre o caso de cache stale, e flag
duplicaria caminho de codigo sem ganho real.

### Decisao 5: Medicao de tokens economizados (decidido em clarify)

Heuristica: `tokens_economizados = (source_chars - resumo_chars) *
tokens_per_char_ratio` por hit.

- `tokens_per_char_ratio` configuravel em
  `config.cache.tokens_per_char_ratio` no `state.json`.
- Default 0.25 (chars/4, pt-br).
- Override para 0.33 (chars/3) em projetos majoritariamente em
  ingles.

Zero dependencias externas, deterministico, mensuravel em tests
offline. Precisao boa o suficiente para validar SC-001 (alvo >=70%
economia) em piloto real T4.2.

Plug-in via API Anthropic (tokenizer real) descartado por exigir
API key em runtime POSIX puro e falhar offline.

---

## Project Structure

```
docs/specs/agente-00c-artifact-cache/
├── spec.md              # ESTE arquivo (already done)
├── plan.md              # ESTE arquivo
├── checklists/          # gerado por /checklist
│   ├── ux.md
│   ├── api.md
│   ├── security.md
│   └── performance.md
├── tasks.md             # gerado por /create-tasks
├── data-model.md        # detalhes do schema (opcional, se necessario)
├── contracts/
│   └── state-cache-sh.md  # contrato da nova primitiva (detalhado)
└── validation-runs/     # outputs de execucoes de validacao
```

Source files modificados:

```
global/skills/agente-00c-runtime/scripts/
├── state-cache.sh          # NOVO — primitiva do cache
├── state-validate.sh       # MOD — adicionar validacao FR-CACHE-017
└── state-rw.sh             # eventualmente MOD se schema_version bump exigir

global/skills/specify/SKILL.md      # MOD — protocolo FR-CACHE-008
global/skills/clarify/SKILL.md      # MOD — protocolo FR-CACHE-008
global/skills/plan/SKILL.md         # MOD — protocolo FR-CACHE-008
global/skills/execute-task/SKILL.md # MOD — protocolo FR-CACHE-008

tests/
├── test_state-cache.sh                  # NOVO — cobertura da primitiva
├── test_state-validate.sh               # EXPANDIR — cenarios de FR-CACHE-017
└── integration_cache-pipeline.sh        # NOVO (opcional) — integracao end-to-end

CHANGELOG.md                            # MOD — entrada nova
```

---

## Complexity Tracking

| Item | Justificativa |
|------|---------------|
| Nova primitiva `state-cache.sh` | Necessaria — nenhuma primitiva existente lida com derivacao de conteudo + filtro de secrets. |
| Modificacao em 4 skills | Necessaria — FR-CACHE-008 exige protocolo de leitura novo. Modificacao eh aditiva (fallback preservado), nao destrutiva. |
| Schema bump MINOR | Necessario para auditabilidade. Mas compativel: campos novos sao opcionais. |
| Sem dependencias novas de runtime | Mantido — usa apenas jq + sha256sum ja exigidos pelas outras primitivas. |
| Heuristica extractiva sem LLM | Reduz complexidade total ao custo de qualidade de resumo. Reavaliavel em v2. |

**Sem violacoes constitucionais detectadas. Plan apto a clarify.**

---

## Phases

### Phase 0 — Clarify (5 perguntas abertas)

Resolver Q1-Q5 antes de /plan finalizar. Saida: plan atualizado +
checklist gerado.

### Phase 1 — Primitiva + schema (M)

- `state-cache.sh` com 6 subcomandos (FR-CACHE-008/009/010/015).
- Schema bump em `state-validate.sh` (FR-CACHE-017).
- Testes unitarios da primitiva (>= 12 cenarios).

### Phase 2 — Skills modificadas (M)

- Editar `SKILL.md` de specify/clarify/plan/execute-task para
  adicionar `## Leitura de artefatos foundational`.
- Testes de regressao standalone (FR-CACHE-014, SC-002).

### Phase 3 — Orquestrador + relatorio (A)

- Modificacoes em `agente-00c-orchestrator.md` e
  `agente-00c-feature-orchestrator.md`:
  - Invocar `state-cache.sh ensure` na onda 1 apos validacao de
    briefing/constitution.
  - Pre-flight drift check no inicio de cada onda N>1.
- `report.sh generate`: secao nova `### Cache de Artefatos`.

### Phase 4 — Integracao + validacao (A)

- Test E2E rodando uma pipeline minimal de 3 ondas com cache ativo.
- Medicao real de `tokens_economizados_estimados` vs baseline.
- Documentacao em CHANGELOG.md + bump de versao.

---

## Risks

| Risco | Probabilidade | Mitigacao |
|-------|--------------|-----------|
| Resumo extractivo perde info critica e degrada decisoes do clarify-answerer | Media | Suite de regressao validando que decisoes em fixture-de-projeto-conhecido nao mudam com cache ativo. |
| TOCTOU race entre check-drift e get-resumo | Baixa | Double-check no momento do consumo (FR-CACHE-008 step 2); lock global ja existente. |
| Schema bump quebra execucoes em andamento | Baixa | Campos novos sao opcionais; state.json legado continua valido. Documentar em CHANGELOG. |
| Filtro de secrets sobre-redacta resumo til | Media | FR-CACHE-007 fallback para passthrough se redacao >50%. |
| Standalone skill quebra por bug em conditional | Alta sem testes | Test de regressao explicito (FR-CACHE-014). |

---

## Out-of-Plan (deferred to Out of Scope da spec)

- Cache de spec/plan/tasks.
- Cache global cross-execucao.
- Configuracao per-skill.
- Migrador de state.json legado.
