# Memória de conhecimento (`cstk recall`)

> **Trilha avançada** — subsistema do [orquestrador autônomo](./agente-00c.md).

Camada **aditiva** de memória cross-feature: um índice SQLite global
(`~/.claude/cstk/knowledge.db`, full-text via FTS5) alimentado automaticamente
no fim de cada onda dos orquestradores `agente-00c`/`feature-00c`. Permite
buscar decisões, bloqueios, retro-execuções, skills invocadas e **memorias**
(arquivos `.md` do Claude Code) de **qualquer projeto ou feature já executados**,
com proveniência (projeto / feature / onda / data).

Desde o **schema v2** (índice retro-compatível, migração aditiva e silenciosa),
a ingestão também deriva **métricas de dashboard** do `state.json` em tabelas
dedicadas: `executions` (status / motivo / duração por execução), `waves`
(ciclo de vida, `tool_calls`, `wallclock` por onda), `alert_signals` (sinais de
circular / budget breach), `tasks` (outcome pass|fail, testes, lint,
arquivos tocados) e `events`. Métricas como latência humana, clarify-rate e mix
de modelos são **deriváveis** dessas tabelas — consumidas pelo
[`cstk serve`](./cstk-serve.md) (dashboard read-only). As 4 tabelas textuais
originais (`decisions`/`bloqueios`/`retros`/`skills`) seguem inalteradas.

O índice é puramente **derivado** — o `state.json` transacional permanece a
fonte de verdade, intacto e fora do caminho crítico (a ingestão o lê em modo
**somente leitura**, nunca escreve). A base inteira é descartável: pode ser
reconstruída a qualquer momento via `--reindex` a partir dos
`state.json`/`state-history` existentes.

```bash
# Buscar (full-text, ordenado por relevância bm25)
cstk recall "lock contention"

# Filtrar por projeto, tipo de registro e limitar resultados
cstk recall "secrets-filter" --project cstk --type decision --limit 5

# Filtrar só memorias (.md do Claude Code)
cstk recall "setup" --type memory

# Filtrar só sugestões (aprendizado de meta-padrão: diagnóstico + proposta)
cstk recall "websocket auth" --type suggestion

# Reconstruir o índice do zero a partir dos states existentes (inclui memorias)
cstk recall --reindex

# Ingestão manual de uma feature específica (normalmente o hook faz isto)
cstk recall --ingest --state-dir .claude/feature-00c-state/<short-name>

# Leitura-para-contexto (read-back loop): bloco markdown pronto para injeção
cstk recall --context "cache fts query" --limit 4 \
  --exclude-feature minha-feature-corrente --max-bytes 2000

# Listar memorias indexadas (slug + description, sem body)
cstk recall --list-memories [--project P]
```

## Flags do modo busca

- `--project P` — filtra pelo projeto de origem
- `--type T` — `decision` | `bloqueio` | `retro` | `skill` | `memory` | `suggestion`
- `--limit N` — máximo de resultados (inteiro positivo; default 20)
- `--db PATH` — índice alternativo (default `$CSTK_KNOWLEDGE_DB` ou
  `~/.claude/cstk/knowledge.db`)

## Modo `--context` (read-back loop)

Fecha o ciclo da memória — em vez de exibir resultados para leitura humana,
retorna um **bloco markdown enxuto** pronto para injeção no contexto de um
prompt. Os orquestradores `agente-00c`/`feature-00c` o invocam automaticamente
no início das fases `specify` e `plan` (passo PRE-DECISAO), injetando
aprendizado de execuções passadas **antes** de decidir. Diferenças face ao modo
busca: composição **OR** entre termos (maior recall sobre keywords kebab da
feature), anti-eco `--exclude-feature` (omite a feature corrente para não ecoar
suas próprias escritas), e teto duro de bytes.

- `--exclude-feature NAME` — anti-eco: omite achados da feature `NAME` (no SQL)
- `--limit N` — máximo de achados (default **4**; faixa recomendada 3-5)
- `--max-bytes N` — teto de bytes do bloco (default **2000**; corta por achado
  inteiro, nunca no meio)
- `--type T` / `--project P` / `--db PATH` — iguais ao modo busca

É **read-only** e **best-effort**: toda degradação (sem `sqlite3`, índice
ausente/corrompido, zero achados) resulta em **no-op silencioso** (stdout vazio,
exit 0) — nunca gateia uma onda. Contra prompt-injection via memória recuperada
há **duas camadas** (ASI09/LLM01): (1) *scrubbing* de segredos na **ingestão**
(controle técnico real) e (2) injeção com rótulo **UNTRUSTED / não-autoritativo**
— uma **mitigação** defense-in-depth, **não uma garantia**. O risco residual de
um registro antigo *instruir* o modelo permanece; por isso o conteúdo nunca é
tratado como instrução.

**Degradação graciosa**: a ausência de `sqlite3` ou `jq` **nunca** aborta uma
onda — o hook de ingestão e o `recall` saem com status 0 emitindo apenas um
aviso. O índice fica isolado em `~/.claude/cstk/`, separado do estado
transacional por projeto.

## Documentação completa

- [`specs/_archived/cstk-knowledge-db/spec.md`](./specs/_archived/cstk-knowledge-db/spec.md) — user stories, FRs, success criteria
- [`specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md`](./specs/_archived/cstk-knowledge-db/contracts/cstk-recall.md) — modos, flags, exit codes, esquema FTS5
- [`specs/_archived/knowledge-db-metrics/spec.md`](./specs/_archived/knowledge-db-metrics/spec.md) — ingestão de métricas (schema v2)
- [`specs/_archived/knowledge-db-metrics/data-model.md`](./specs/_archived/knowledge-db-metrics/data-model.md) — DDL das tabelas e chaves naturais
