/**
 * Queries read-only para a entidade `memories` (schema v4 — recall-memory-mirror).
 * Ref: ../claude-ai-tips/docs/specs/recall-memory-mirror/data-model.md §Entity: memories
 *
 * Tabela DEDICADA, chave natural (project, slug). Espelho de arquivos `.md` de
 * auto-memoria do Claude Code. O painel apenas LE — a fonte canonica sao os `.md`.
 *
 * Tolerancia de schema (Principio II): bases v2/v3 NAO tem a tabela `memories`.
 * Toda funcao checa `hasTable` antes e degrada para vazio, em vez de lancar.
 */
import type Database from 'better-sqlite3';
import { hasTable } from '../columns.js';

/** Tipos conhecidos (FR-007 do produtor) — qualquer outro vira 'user'. */
const KNOWN_TYPES = ['index', 'feedback', 'project', 'reference', 'user'] as const;
export type MemoryType = (typeof KNOWN_TYPES)[number];

/** Coage um valor cru de `type` para o enum conhecido (defesa em profundidade). */
export function normalizeMemoryType(raw: string | null | undefined): MemoryType {
  return (KNOWN_TYPES as readonly string[]).includes(raw ?? '')
    ? (raw as MemoryType)
    : 'user';
}

export interface MemoryRow {
  project: string;
  slug: string;
  type: string;
  description: string | null;
  body_scrubbed: string | null;
  path: string | null;
  indexed_at: string | null;
}

export interface MemoryFilters {
  project?: string;
  limit: number;
  offset: number;
}

/** True se a base expoe a tabela `memories` (v4+). */
export function hasMemories(db: Database.Database): boolean {
  return hasTable(db, 'memories');
}

/**
 * Lista distinta de projetos com memorias — alimenta o seletor de filtro.
 * Independente do filtro corrente: o dropdown deve listar TODOS os projetos.
 */
export function listMemoryProjects(db: Database.Database): string[] {
  if (!hasMemories(db)) return [];
  const rows = db
    .prepare('SELECT DISTINCT project FROM memories ORDER BY project ASC')
    .all() as Array<{ project: string }>;
  return rows.map((r) => r.project);
}

/** Total de memorias (filtrado por projeto quando informado). */
export function countMemories(db: Database.Database, project?: string): number {
  if (!hasMemories(db)) return 0;
  if (project !== undefined) {
    return (
      db.prepare('SELECT count(*) as n FROM memories WHERE project = ?').get(project) as {
        n: number;
      }
    ).n;
  }
  return (db.prepare('SELECT count(*) as n FROM memories').get() as { n: number }).n;
}

/**
 * Lista memorias, opcionalmente filtradas por projeto, paginadas.
 * Ordenacao agrupavel: project → type → slug.
 */
export function listMemories(db: Database.Database, f: MemoryFilters): MemoryRow[] {
  if (!hasMemories(db)) return [];
  return db
    .prepare(
      `
      SELECT project, slug, type, description, body_scrubbed, path, indexed_at
      FROM memories
      WHERE (? IS NULL OR project = ?)
      ORDER BY project ASC, type ASC, slug ASC
      LIMIT ? OFFSET ?
    `,
    )
    .all(f.project ?? null, f.project ?? null, f.limit, f.offset) as MemoryRow[];
}
