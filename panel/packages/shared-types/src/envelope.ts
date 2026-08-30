/**
 * Envelope padrao ApiEnvelope<T> — envelope de toda resposta da API.
 * Ref: contracts/envelope.md; spec.md FR-023; Principio VI (Snapshot que Muda)
 */

/**
 * Informacoes de frescor do snapshot.
 * mtime: ultima modificacao do arquivo knowledge.db (ISO 8601)
 * maxIngestedAt: max(ingested_at) das execucoes na base (ISO 8601)
 */
export interface Freshness {
  mtime: string;        // ISO 8601 — mtime do arquivo DB
  maxIngestedAt: string; // ISO 8601 — max(ingested_at) das execucoes
}

/**
 * Metadados do envelope — presentes em TODA resposta (200 e degradada).
 * degraded: true indica que o servidor esta operando em modo degradado.
 * reason: motivo da degradacao (null se ok).
 * freshness: informacoes de frescor do snapshot (obrigatorio — FR-014).
 * schemaVersion: versao do schema da knowledge.db que o servidor validou.
 * approximate: true se alguma metrica e derivada/estimada (Principio III).
 */
export interface Meta {
  degraded: boolean;           // obrigatorio — nunca omitido
  reason: string | null;       // motivo da degradacao, null se ok
  freshness: Freshness;        // obrigatorio — FR-014
  schemaVersion: string;       // versao do schema validada ('2')
  approximate?: boolean;       // presente apenas quando true (Principio III)
}

/**
 * Envelope padrao de toda resposta da API.
 * data: null quando degraded=true (nao ha dados confiaveis).
 * meta: sempre presente, mesmo em erro/degradacao.
 */
export interface ApiEnvelope<T> {
  data: T | null;
  meta: Meta;
}

/**
 * Tipos de motivo de degradacao (Principio II — Degradar, Nunca Quebrar).
 */
export type DegradedReason =
  | 'db-missing'       // arquivo knowledge.db nao encontrado
  | 'db-corrupt'       // PRAGMA quick_check retornou != 'ok'
  | 'schema-mismatch'  // schema_version != '2' em schema_meta
  | 'table-empty'      // tabela sem dados por entidade consultada
  // feature state-watchers-and-docs (FR-008/FR-012, CHK056/dec-027):
  | 'project-path-unresolved'    // `project` sem entrada em CSTK_PROJECT_PATHS
  | 'project-path-inaccessible'  // path configurado nao existe/sem permissao de leitura
  | 'watcher-ingestion-failed'   // ultimo `cstk recall --ingest` do watcher falhou (2.4)
  // feature state-watchers-and-docs, task 3.3/3.4 (research.md Decision 7, FR-009):
  | 'artifact-too-large'         // artefato existe mas excede o cap de leitura (confinement.ts)
  | 'artifact-rejected'          // artefato existe mas guard de confinamento rejeitou (symlink/escape de raiz)
  // feature session-tail, task 1.1.3 (data-model.md §Novos literais de DegradedReason):
  | 'sessions-root-missing'      // `~/.claude/projects` (CSTK_SESSIONS_ROOT) nao existe
  | 'sessions-root-unreadable'   // raiz existe, mas `readdirSync` falha (permissao)
  | 'session-not-found'          // `:sessionId` nao resolve para arquivo sob a raiz
  | 'session-rejected'           // guard de confinamento rejeitou o caminho (symlink/escape)
  | 'session-scrub-failed'       // cadeia de scrub nao pode ser concluida; degrada em vez de servir texto cru
  // feature human-bridge, FASE 3 (contracts/panel-bridge-api.md §3.1): literal
  // com underscore (nao kebab-case) — citado assim, verbatim, pelo contrato.
  | 'bridge_unavailable';        // `bridge.db` ausente/ilegivel/`quick_check` falhou no momento da chamada
