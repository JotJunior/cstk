# Research: Watchers de Execução em Andamento e Visualização de Documentação

**Feature**: `state-watchers-and-docs` | **Phase**: 0 (Research) | **Date**: 2026-07-15

> Convenção de proveniência: fatos afirmados como REAIS citam arquivo:símbolo do
> código existente. Desenhos NOVOS (ainda inexistentes no código) recebem a marca
> **[PROPOSTA — a validar na implementação]**. Nenhuma assinatura, rota ou valor
> concreto foi inventado (Constitution VI / regra global "Jamais inventar dados").

## Contexto verificado do codebase (grounding)

| Fato | Fonte real |
|------|-----------|
| Framework HTTP: Fastify 5, entrada `main()` | `apps/server/src/index.ts` |
| Prefixo de rotas `/api/v1`; todas `GET` | `apps/server/src/index.ts` (`server.register(..., { prefix: '/api/v1' })`) |
| Bind `127.0.0.1`, porta `PORT` (default 3001) | `apps/server/src/config.ts` (`host: '127.0.0.1'`) |
| SQLite via `better-sqlite3`, aberto **read-only por request** | `apps/server/src/db/open.ts` (`openDb()`, `readonly: true`, `PRAGMA query_only = 1`) |
| DB aberto+fechado por request (sem conexão longa) | rotas fazem `openDb()` … `finally { db.close() }` (`apps/server/src/routes/executions.ts:82-105`) |
| Resolução do path do DB: env `CSTK_KNOWLEDGE_DB` > default `~/.claude/cstk/knowledge.db`, `path.resolve()` | `apps/server/src/config.ts` (`resolveDbPath()`) |
| Envelope `{ data, meta:{ degraded, reason, freshness:{mtime,maxIngestedAt}, schemaVersion, approximate? } }` | `apps/server/src/lib/envelope.ts` (`wrap()`, `wrapDegraded()`) |
| Freshness = `statSync(dbPath).mtime` + `max(ingested_at) FROM executions` | `apps/server/src/db/freshness.ts` (`computeFreshness()`) |
| ETag fraco `W/"<mtimeEpoch>-<maxIngestedEpoch>"` + `If-None-Match`→304 | `apps/server/src/lib/etag.ts` (`generateETag()`, `etagMatches()`) |
| Cliente: TanStack Query `refetchInterval: 10_000` (`AUTO_REFRESH_MS`), pausa em aba oculta | `apps/web/src/lib/query.ts` |
| Cliente ETag: `fetchApi()` guarda ETag por path em localStorage, envia `If-None-Match`, 304→bodyCache | `apps/web/src/lib/api.ts` (`BASE_URL='/api/v1'`) |
| Indicador de frescor existente na UI (FR-011) | `apps/web/src/components/FreshnessLabel.tsx` (`fmtRelative`, usa `mtime`/`maxIngestedAt`) |
| Render seguro de texto UNTRUSTED (sem `dangerouslySetInnerHTML`) | `apps/web/src/components/TextRaw.tsx` |
| DTOs dual-def: interface + Zod | `packages/shared-types/src/entities.ts` + `packages/shared-types/src/schemas/entities.ts` |
| Status de execução (enum): inclui `em_andamento`, `aguardando_humano` | `ExecutionDTO.status` em `packages/shared-types/src/entities.ts` |
| **NÃO existe** coluna `target_project_path`/`projectPath` na knowledge.db | lista de colunas projetadas em `apps/server/src/db/queries/executions.ts` (nenhuma coluna de path); spec §Clarifications Q1 |
| **NÃO existe** render de markdown no projeto (net-new) | busca: sem `react-markdown`/`marked`/`remark`/`markdown-it` em nenhum `package.json` |
| **NÃO existe** uso de `child_process`/`spawn`/`execFile` (net-new) | busca: zero import de `node:child_process` em `apps`/`packages` |
| Comando canônico de ingestão | `cstk recall --ingest --state-dir DIR` — verificado em `cstk recall --help` (cstk v5.18.0: "MODO INGESTAO (--ingest): --state-dir DIR") |
| Layout de state-dir feature-00c | `<project>/.claude/feature-00c-state/<feature>/state.json` (execução corrente roda aqui) |
| Layout de state-dir agente-00c | `<project>/.claude/agente-00c-state/state.json` (único por projeto) |

---

## Decision 1 — Resolução nome-lógico → caminho absoluto (FR-008)

**Decision**: Introduzir uma configuração de **mapeamento `project` → caminho
absoluto** mantida pelo operador, resolvida seguindo o MESMO idioma já usado por
`resolveDbPath()`: variável de ambiente explícita > default. Projeto sem entrada
no mapa = **não observável** (degradação sinalizada, FR-012), nunca erro.

**Rationale**: A clarificação Q1 exige "mesmo padrão de resolução já adotado para
o caminho da `knowledge.db`". O padrão REAL implementado é `env > default`
(`apps/server/src/config.ts:48-54`) — **não** há camada de flag/CLI hoje (o texto
"flag/config > env > default" aparece na constituição §Padrões de Segurança e na
Q1, mas o código só implementa env > default). Honestidade de grounding: mirroramos
o que existe. A `knowledge.db` NÃO ganha coluna de path (FR-008; a spec §Q1 registra
que o painel resolve o path por config do operador, não por coluna no banco).

**Mecanismo concreto** **[PROPOSTA — a validar na implementação]**:
- Env var nova `CSTK_PROJECT_PATHS` contendo um mapa serializado
  `nome=/abs/path` separado por `;` (ex.: `cstk-panel=/Users/jot/…/cstk-panel;outro=/x/y`).
  Alternativa de serialização: JSON via `CSTK_PROJECT_PATHS_FILE` apontando um
  arquivo de config. O formato exato é decisão de implementação; ambos canonicalizam
  cada path com `path.resolve()` (anti-traversal, como `resolveDbPath`).
- Default: mapa vazio → todo projeto é "não observável" até o operador configurar
  (degradação sinalizada, nunca 5xx).
- Função `resolveProjectPath(project): string | null` em `apps/server/src/config.ts`,
  paralela a `resolveDbPath()`.

**Alternatives considered**:
- *Coluna `target_project_path` na knowledge.db*: rejeitada — FR-008 proíbe
  ("MUST NOT ganhar coluna"), e a escrita pertence ao `cstk recall` (Principio I/IV).
- *Descobrir path por heurística (cwd, glob)*: rejeitada — frágil, sem fonte da
  verdade; operador é a autoridade (Q1).

---

## Decision 2 — Mecanismo de watcher / disparo proativo de ingestão (FR-001, FR-004, FR-013)

**Decision**: Um **job de segundo plano** dentro do processo Fastify (timer
recorrente) que: (1) lista execuções com status `em_andamento`/`aguardando_humano`
na knowledge.db (read-only); (2) resolve o caminho do projeto (Decision 1);
(3) deriva o state-dir da execução; (4) **delega** a ingestão canônica executando
`cstk recall --ingest --state-dir <dir>` via subprocesso seguro. NUNCA escreve na
knowledge.db, NUNCA toca `state.json`, NUNCA roda `--reindex`.

**Rationale**: Clarificação Q2 (dec-011) decidiu disparo proativo e recorrente,
somente enquanto houver execução em andamento, sempre delegando ao processo
canônico. Constitution IV Opção B ("delegar ao dono via subprocesso seguro")
sanciona explicitamente o subprocesso; Principio I permanece intacto porque o
painel não emite SQL de mutação — quem escreve é o `cstk` (dono da ingestão).

**Mecanismo concreto** **[PROPOSTA — a validar na implementação]**:
- Módulo novo `apps/server/src/watchers/ingest-watcher.ts` iniciado em `main()`
  (`apps/server/src/index.ts`) com `setInterval` de cadência `WATCH_INTERVAL_MS`
  (default proposto 10_000; ver Decision 5 para orçamento de 30s).
- Subprocesso via `node:child_process` `execFile('cstk', ['recall','--ingest','--state-dir',dir], { timeout, ... })`
  — **execFile (não `exec`)**, argumentos como array (sem shell-string interpolada),
  `timeout` explícito, captura de `stderr`/`stdout`, per Padrões de Segurança
  §"Subprocesso seguro" da constituição. Primeiro ponto onde `node:child_process`
  entra no server (hoje inexistente).
- Ociosidade (FR-013, AC US1-3): quando a consulta não retorna execução em
  andamento, o tick não dispara subprocesso (permanece "reduzido/pausado").
- Isolamento de conexão (Principio VI): o watcher abre/fecha o DB por tick com
  `openDb()` como as rotas — **sem** conexão de longa duração.

**Alternatives considered**:
- *Reimplementar leitura de `state.json` + escrita no DB no painel*: rejeitada —
  FR-004 e Principio I/IV proíbem ("MUST delegar ao processo de ingestão canônico").
- *WebSocket/SSE para push*: rejeitada — decisão prévia do projeto (polling+ETag/304,
  `docs/specs/cstk-panel/tasks.md`); constituição §"Snapshot que Muda" reforça
  verificação recorrente em vez de canal persistente.
- *Disparar ingestão só no fim-de-onda (hook existente do orquestrador)*: rejeitada
  por Q2 — o objetivo é reduzir a latência de minutos para ≤30s durante a onda.

---

## Decision 3 — Derivação do state-dir de uma execução observada (FR-001)

**Decision**: Derivar o state-dir a partir de (caminho do projeto resolvido em
Decision 1) + convenção de layout do orquestrador + coluna `feature` da execução:
- feature-00c: `<projectPath>/.claude/feature-00c-state/<feature>/`
- agente-00c: `<projectPath>/.claude/agente-00c-state/`

**Rationale**: Esses layouts são REAIS (a execução corrente `state-watchers-and-docs`
roda em `<project>/.claude/feature-00c-state/state-watchers-and-docs/`). A knowledge.db
tem colunas `project` e `feature` (`apps/server/src/db/queries/executions.ts`), o que
permite reconstruir o caminho. A distinção feature-00c × agente-00c segue a presença
de `feature` não-nula (feature-00c) vs. nula (agente-00c).

**[PROPOSTA — a validar na implementação]**: a regra exata de escolha de layout e o
tratamento de `session`/worktree (coluna v8 `session`, feature `recall-worktree-identity`)
devem ser confirmados contra execuções reais na implementação; se o state-dir derivado
não existir no filesystem, tratar como **degradado** (FR-012), nunca erro.

**Alternatives considered**:
- *Assumir sempre feature-00c*: rejeitada — quebra observação de execuções agente-00c.

---

## Decision 4 — Idempotência do disparo (FR-014)

**Decision**: Antes de disparar `cstk recall --ingest` para um state-dir, comparar
uma **assinatura do `state.json`** (mtime via `fs.statSync`, ou sha256 do arquivo)
com a última assinatura vista (cache **em memória**, keyed por state-dir). Só dispara
quando a assinatura mudou.

**Rationale**: FR-014 exige evitar trabalho redundante quando o estado subjacente
não mudou. `state.json` é a fonte da verdade transacional; sua mudança (mtime/hash)
é o sinal barato de "há novidade". Cache em memória (não persistido) respeita
Principio I (nada é escrito no state alheio nem na knowledge.db).

**[PROPOSTA — a validar na implementação]**: mtime é mais barato; sha256 é mais
robusto a relógios. Escolha final na implementação. O cache reinicia a cada restart
do server (aceitável: um tick extra de ingestão idempotente não causa dano —
`cstk recall --ingest` é upsert idempotente por chave natural).

**Alternatives considered**:
- *Sempre reingerir a cada tick*: rejeitada — viola FR-014 (trabalho redundante).
- *Persistir assinatura em disco/DB*: rejeitada — Principio I (read-only); o ganho
  não justifica introduzir escrita.

---

## Decision 5 — Orçamento de latência ≤30s (SC-001)

**Decision**: Latência total = (cadência do watcher até disparar ingestão) +
(duração da ingestão `cstk recall --ingest`) + (intervalo de polling do cliente,
`AUTO_REFRESH_MS=10_000`) + (render). Com cadência de watcher ~10s e polling de 10s,
o pior caso fica confortavelmente < 30s.

**Rationale**: O polling do cliente já é 10s (`apps/web/src/lib/query.ts`) e o
frescor/ETag já invalida cache por `mtime`+`max(ingested_at)`. Não é necessário
mudar o polling; basta o watcher manter a knowledge.db fresca. SC-001 (30s) é
folgado frente a 10s+10s.

**[PROPOSTA — a validar na implementação]**: medir a duração real de
`cstk recall --ingest` num state.json típico para confirmar a folga; se a ingestão
exceder ~10s, ajustar a cadência. Nenhum número de duração de ingestão é afirmado
aqui como medido (não foi cronometrado) — é premissa a validar.

**Alternatives considered**:
- *Reduzir polling para <10s*: rejeitada — desnecessário para 30s e aumenta carga.

---

## Decision 6 — Renderização segura de markdown (FR-006, FR-010, Principio V)

**Decision**: Renderizar os artefatos `.md` como markdown formatado (FR-006), porém
com **HTML ativo desabilitado / sanitizado** — nenhum `<script>`, handler inline ou
markup ativo é interpretado (FR-010, Principio V "Conteúdo de Agente é UNTRUSTED").

**Rationale**: Documentos são gerados por agentes → UNTRUSTED. O projeto já tem o
padrão de render seguro para texto puro (`apps/web/src/components/TextRaw.tsx`, sem
`dangerouslySetInnerHTML`), mas markdown formatado exige um renderer. FR-006 pede
formatação; FR-010 proíbe execução de markup — logo é preciso um renderer que
formate markdown E neutralize HTML embutido.

**Mecanismo concreto** **[PROPOSTA — a validar na implementação]**:
- Adicionar uma dependência de markdown seguro. **Preferir `react-markdown` +
  `rehype-sanitize` (schema default)** em vez de sanitizador hand-rolled — o schema
  default do rehype-sanitize já filtra esquemas de URL perigosos. Requisitos DUROS:
  - **raw HTML OFF** + allowlist de tags; nunca `dangerouslySetInnerHTML` com HTML
    não sanitizado.
  - **Allowlist de esquemas de URL** em destinos de link/imagem: só `http`, `https`,
    `mailto` e relativos; **descartar `javascript:`/`data:`/`vbscript:`** (gate
    owasp-security, finding HIGH — esses esquemas vêm do AST do markdown, NÃO do raw
    HTML, logo "raw HTML OFF" sozinho NÃO os bloqueia: `[x](javascript:…)`,
    `![x](data:…)` passariam num render que só desliga HTML). CWE-79 / LLM01 / ASI09.
- Componente novo `apps/web/src/components/MarkdownView.tsx` seguindo a postura de
  `TextRaw.tsx` (defesa LLM01/ASI09). A escolha da lib é decisão de implementação;
  os INVARIANTES são: markup ativo nunca executa E esquema de URL perigoso nunca
  vira href/src navegável.

**Alternatives considered**:
- *Render markdown com HTML habilitado*: **rejeitada — viola FR-010/Principio V**
  (permitiria `<script>`/injection do conteúdo de agente).
- *Exibir como texto bruto (só TextRaw)*: rejeitada — viola FR-006 (exige formatação).

---

## Decision 7 — Confinamento de leitura de artefatos (FR-009)

**Decision**: Toda leitura de artefato é confinada à subárvore
`<projectPath>/docs/specs/<feature>/` (mais os diretórios de docs da feature).
O caminho final é canonicalizado (`path.resolve`) e verificado como prefixado pela
raiz permitida; qualquer path que escape a fronteira é rejeitado.

**Rationale**: FR-009 exige confinamento; a constituição §Padrões de Segurança já
canonicaliza e confina o path do DB. Reusar a mesma postura anti-traversal. O param
`feature`/`artifact` deve validar com regex anti-traversal análoga à de `execucaoId`
(`/^[^/\\.<>]+$/`, `apps/server/src/routes/executions.ts:40-42`).

**Controles DUROS** (regex de param + canonicalização **não bastam** — gate
owasp-security, finding HIGH):
- Após `path.resolve`, resolver **symlinks** com `fs.realpath` no arquivo final e
  re-confinar sob `realpath(root)+path.sep`; rejeitar entradas symlinkadas
  (`lstat`). Motivo: um `.md` gerado por agente (conteúdo UNTRUSTED) pode ser um
  **symlink** apontando para fora da raiz → leitura arbitrária de arquivo local via
  o endpoint de conteúdo. A regex `/^[^/\\.<>]+$/` barra `..`/separadores no PARAM,
  mas não resolve symlinks (A01 / path traversal → info disclosure).
- Comparação de prefixo na **fronteira `path.sep`** (não `startsWith` ingênuo — senão
  `/root` casa `/root-evil`).
- **Cap de tamanho** na leitura do `.md` (evitar exaustão de memória em arquivo grande).

**[PROPOSTA — a validar na implementação]**: a lista exata de diretórios permitidos
(ex.: `docs/specs/<feature>/`, subdir `contracts/`, `checklists/`) e a função de
guarda (`isWithin(root, candidate)` com realpath + fronteira de sep) são net-new.

**Alternatives considered**:
- *Aceitar path arbitrário do cliente*: rejeitada — path traversal (Principio Seg.).
- *Só `path.resolve` + prefix check (sem realpath)*: **rejeitada — deixa escape por
  symlink** (gate owasp HIGH).

---

## Decision 8 — Mapeamento fixo etapa-SDD → artefato(s) (FR-005, FR-007)

**Decision**: Tabela fixa etapa do pipeline SDD → artefato(s) esperado(s), habilitando
o estado "ainda não produzido" (FR-007) quando o arquivo não existe. Arquivos extras
presentes na árvore continuam listáveis/visualizáveis (SC-002).

**Mapeamento** (nomes REAIS gerados pela pipeline — ver `docs/specs/*/`):

| Etapa SDD | Artefato(s) esperado(s) |
|-----------|-------------------------|
| specify | `spec.md` |
| clarify | (atualiza `spec.md` §Clarifications) |
| plan | `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `contracts/` |
| checklist | `checklists/*.md` |
| create-tasks | `tasks.md` |

**Rationale**: Clarificação Q3 decidiu mapeamento fixo (não descoberta dinâmica pura),
mas sem impedir arquivos adicionais. Os nomes de arquivo são os que a pipeline SDD
realmente emite (esta própria feature está produzindo `plan.md`/`research.md`/
`data-model.md`/`quickstart.md`/`contracts/`). "Ainda não produzido" = entrada no
mapa cujo arquivo não existe no filesystem (não é erro).

**Alternatives considered**:
- *Descoberta 100% dinâmica*: rejeitada por Q3 — não habilita "ainda não produzido".
- *Lista hardcoded sem extras*: rejeitada — SC-002 exige 100% dos artefatos já
  produzidos, inclusive extras fora do mapa.

---

## Decision 9 — Hardening de segurança (gate owasp-security, medium)

**Decision**: Além dos controles HIGH em Decision 6 (esquemas de URL) e Decision 7
(realpath/symlink), a implementação DEVE aplicar os controles medium abaixo, todos
**[PROPOSTA — a validar na implementação]**:

1. **Binário `cstk` resolvido de forma confiável** (evitar PATH hijack — ASI04/A08):
   `execFile` usa nome relativo `cstk` resolvido via `$PATH`. Resolver para caminho
   absoluto verificado (ou pinar via config) e passar `env`/`cwd` mínimos ao subprocesso.
2. **Confinar `feature`/`session` na derivação do state-dir** (Decision 3): esses
   valores vêm da knowledge.db (UNTRUSTED, Principio V) e são interpolados no path do
   state-dir. Aplicar a MESMA canonicalização + confinamento + regex anti-traversal
   (`/^[^/\\.<>]+$/`) antes de montar o path — não apenas checar existência. (A forma
   array do `execFile` já neutraliza smuggling de opção; o risco residual é traversal
   do diretório-fonte da ingestão.)
3. **Bound de concorrência + backoff no watcher** (evitar DoS/loop apertado): limitar
   subprocessos `cstk` concorrentes por tick (N execuções ativas ⇒ N spawns) e aplicar
   backoff quando uma ingestão falha persistentemente (o plano já sinaliza "evitar loop
   apertado" em Decision 2 e contracts/watchers §2).

**Rationale**: São controles padrão, baratos, folded no `execute-task`. Todos dentro do
modelo de ameaça local/single-operator/127.0.0.1/sem-auth (blast radius contido), mas
os vetores são reais e a constituição trata segurança como MUST.

**Low (nota, não bloqueante)**: pinar lockfile + `npm audit` das novas deps de markdown;
considerar allowlist de `Host` header (defesa DNS-rebinding para 127.0.0.1); pinar
`env`/`cwd` do subprocesso.

---

## NEEDS CLARIFICATION restantes

Nenhum. As 3 ambiguidades foram resolvidas em `/clarify` (spec §Clarifications:
Q1 FR-008, Q2 FR-004, Q3 FR-005/FR-007). Os pontos marcados **[PROPOSTA]** acima são
decisões de implementação (formato de serialização, lib de markdown, regra de layout),
não ambiguidades de requisito — serão fixados em `execute-task` contra o código real.
