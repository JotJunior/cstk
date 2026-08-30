/**
 * Testes de `wrapBridge()`/`computeBridgeFreshness()`/`wrapBridgeDegraded()`
 * (feature human-bridge, task 3.2.3).
 * Ref: docs/specs/human-bridge/contracts/panel-bridge-api.md §3;
 *      docs/specs/human-bridge/tasks.md 3.2.1-3.2.3.
 *
 * Cobre: (a) `wrapBridge()` nunca abre `knowledge.db` (nenhuma chamada a
 * `readSchemaVersion`/tabela `schema_meta` — schemaVersion e um LITERAL
 * fixo, `BRIDGE_SCHEMA_VERSION`); (b) `freshness` reflete `mtime`/
 * timestamps REAIS de `bridge.db`, nao do corpus.
 */
import { describe, it, expect, afterEach } from 'vitest';
import { mkdtempSync, unlinkSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { openBridgeDb } from '../../src/db/bridge.js';
import {
  wrapBridge,
  wrapBridgeDegraded,
  bridgeErrorEnvelope,
  computeBridgeFreshness,
  BRIDGE_SCHEMA_VERSION,
} from '../../src/lib/envelope.js';

const toClean: string[] = [];

afterEach(() => {
  for (const f of toClean) {
    try { unlinkSync(f); } catch { /* ignorar */ }
    try { unlinkSync(f + '-shm'); } catch { /* ignorar */ }
    try { unlinkSync(f + '-wal'); } catch { /* ignorar */ }
  }
  toClean.length = 0;
});

function tmpBridgeDbPath(): string {
  const dir = mkdtempSync(join(tmpdir(), 'cstk-envelope-bridge-test-'));
  const p = join(dir, 'bridge.db');
  toClean.push(p);
  return p;
}

describe('wrapBridge — forma do envelope e schemaVersion fixo', () => {
  it('schemaVersion e sempre BRIDGE_SCHEMA_VERSION, nunca deriva de schema_meta (bridge.db nao tem essa tabela)', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      const envelope = wrapBridge({ ok: true }, {}, path, db);
      expect(envelope.meta.schemaVersion).toBe(BRIDGE_SCHEMA_VERSION);
      expect(envelope.data).toEqual({ ok: true });
      expect(envelope.meta.degraded).toBe(false);
    } finally {
      db.close();
    }
  });

  it('degraded=true zera data e usa freshness vazia (db=null)', () => {
    const envelope = wrapBridgeDegraded('bridge_unavailable', '/nao/existe/bridge.db');
    expect(envelope.data).toBeNull();
    expect(envelope.meta.degraded).toBe(true);
    expect(envelope.meta.reason).toBe('bridge_unavailable');
    expect(envelope.meta.freshness).toEqual({ mtime: '', maxIngestedAt: '' });
  });

  it('bridgeErrorEnvelope() e SEMPRE degraded=false (erro de validacao, nao condicao de dado)', () => {
    const envelope = bridgeErrorEnvelope('value fora de options');
    expect(envelope.meta.degraded).toBe(false);
    expect(envelope.data).toBeNull();
    expect(envelope.error).toBe('value fora de options');
    expect(envelope.meta.schemaVersion).toBe(BRIDGE_SCHEMA_VERSION);
  });
});

describe('computeBridgeFreshness — mtime + max(created_at, resolved_at) REAIS de bridge.db', () => {
  it('db=null -> strings vazias (nunca fabrica um valor)', () => {
    const freshness = computeBridgeFreshness('/nao/existe/bridge.db', null);
    expect(freshness).toEqual({ mtime: '', maxIngestedAt: '' });
  });

  it('tabela vazia -> mtime real do arquivo, maxIngestedAt vazio', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      const freshness = computeBridgeFreshness(path, db);
      const expectedMtime = statSync(path).mtime.toISOString();
      expect(freshness.mtime).toBe(expectedMtime);
      expect(freshness.maxIngestedAt).toBe('');
    } finally {
      db.close();
    }
  });

  it('reflete MAX(created_at, resolved_at) entre linhas — resolved_at mais recente vence', () => {
    const path = tmpBridgeDbPath();
    const db = openBridgeDb(path);
    try {
      db.prepare(
        `INSERT INTO interventions
          (question_id, project_path, project, execution_kind, kind, question, default_value, expires_at, created_at, resolved_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run('q1', '/tmp/proj', 'proj', 'agente-00c', 'text', 'q?', 'default', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', '2026-01-05T00:00:00.000Z');
      db.prepare(
        `INSERT INTO interventions
          (question_id, project_path, project, execution_kind, kind, question, default_value, expires_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run('q2', '/tmp/proj', 'proj', 'agente-00c', 'text', 'q?', 'default', '2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z');

      const freshness = computeBridgeFreshness(path, db);
      expect(freshness.maxIngestedAt).toBe('2026-01-05T00:00:00.000Z');
    } finally {
      db.close();
    }
  });
});
