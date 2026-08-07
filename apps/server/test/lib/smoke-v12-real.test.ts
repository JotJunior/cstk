import { describe, it, expect } from 'vitest';
import { existsSync } from 'node:fs';
import { openDb } from '../../src/db/open.js';

const REAL = process.env.CSTK_SMOKE_DB ?? '';

describe('smoke: base v12+ real', () => {
  it.skipIf(!REAL || !existsSync(REAL))('abre a knowledge.db real (v12 ou v13) e le as tabelas', () => {
    const r = openDb(REAL);
    expect(r.ok).toBe(true);
    if (r.ok) {
      const v = r.db.prepare("SELECT value FROM schema_meta WHERE key='schema_version'").get() as { value: string };
      // v13 (loose-usage-capture) e aditiva — as tabelas lidas abaixo existem nas duas
      expect(['12', '13']).toContain(v.value);
      const wmu = r.db.prepare('SELECT count(*) c FROM wave_model_usage').get() as { c: number };
      const w = r.db.prepare('SELECT count(*) c FROM waves').get() as { c: number };
      console.log(`  schema=${v.value} waves=${w.c} wave_model_usage=${wmu.c}`);
      expect(w.c).toBeGreaterThan(0);
      r.db.close();
    }
  });
});
