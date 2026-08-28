/**
 * getModelMixByStage — `model-routing` NAO e uma etapa SDD.
 *
 * Decisoes de roteamento LEGADAS (runtime agente-00c, model-routing.sh —
 * dec-006/FR-021) gravaram `stage='model-routing'` e codificaram a fase real
 * no lead do contexto `"Selecao de modelo para onda <N> (fase <f>)"`. O card
 * "Mix de modelos por etapa" exibia `model-routing` como uma etapa propria
 * (719 decisoes na base real) em vez de soma-las a etapa SDD correspondente.
 * Regra espelhada do dono canonico do relatorio (model-routing-report.sh,
 * `etapa_of_onda`): sem `(fase …)` parseavel, o stage original e mantido.
 * A mesma normalizacao vale para `getThroughputByStage` (card "Throughput
 * por etapa"), que contava 726 decisoes sob `model-routing`.
 */
import { describe, it, expect } from 'vitest';
import Database from 'better-sqlite3';
import { getModelMixByStage, getThroughputByStage, stageFromRoutingContext } from '../../src/db/queries/metrics.js';

function makeDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO schema_meta VALUES ('schema_version', '14');
    CREATE TABLE decisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project TEXT NOT NULL, feature TEXT NOT NULL, wave TEXT NOT NULL,
      execution_id TEXT NOT NULL, source_ts TEXT NOT NULL, source_id TEXT NOT NULL,
      agent TEXT, stage TEXT, choice TEXT, options TEXT, score INTEGER,
      context TEXT, rationale TEXT, evidence TEXT, ingested_at TEXT NOT NULL,
      UNIQUE(project, feature, wave, source_id)
    );
  `);
  const ins = db.prepare(`
    INSERT INTO decisions (project, feature, wave, execution_id, source_ts, source_id,
      agent, stage, choice, context, ingested_at)
    VALUES ('p', 'f', ?, 'e1', '2026-05-27T10:00:00Z', ?, 'orch', ?, ?, ?, '2026-05-27T10:00:00Z')
  `);
  // Geracao NOVA: stage = fase da onda.
  ins.run('onda-005', 'dec-01', 'execute-task', 'model:sonnet', 'Selecao de modelo para onda 5 (fase execute-task)');
  ins.run('onda-006', 'dec-02', 'execute-task', 'model:sonnet', 'Selecao de modelo para onda 6 (fase execute-task)');
  ins.run('onda-002', 'dec-03', 'plan', 'model:opus', 'Selecao de modelo para onda 2 (fase plan)');
  // Geracao LEGADA: stage=model-routing, fase no lead do contexto.
  ins.run('onda-007', 'dec-04', 'model-routing', 'model:sonnet', 'Selecao de modelo para onda 7 (fase execute-task)');
  ins.run('onda-013', 'dec-05', 'model-routing', 'model:haiku', 'Selecao de modelo para onda 13 (fase review-task)');
  ins.run('onda-003', 'dec-06', 'model-routing', 'model:opus', 'Selecao de modelo para onda 3 (fase plan)');
  // Legada SEM fase parseavel: mantem model-routing (nunca inventar etapa).
  ins.run('init', 'dec-07', 'model-routing', 'model:sonnet', 'Selecao de modelo para subagente X');
  // Nao-roteamento (choice sem prefixo model:) — fora do mix.
  ins.run('onda-001', 'dec-08', 'clarify', 'opcao-a', 'qualquer');
  // Roteamento legado com choice manter-atual: fora do mix, mas conta no
  // throughput na etapa do contexto.
  ins.run('onda-009', 'dec-09', 'model-routing', 'manter-atual', 'Selecao de modelo para onda 9 (fase review-features)');
  return db;
}

describe('stageFromRoutingContext', () => {
  it('extrai a fase do lead "(fase <f>)"', () => {
    expect(stageFromRoutingContext('Selecao de modelo para onda 13 (fase review-task)')).toBe('review-task');
    expect(stageFromRoutingContext('Selecao de modelo para onda init (fase specify)')).toBe('specify');
  });
  it('devolve null sem lead parseavel / vazio / null', () => {
    expect(stageFromRoutingContext('Selecao de modelo para subagente X')).toBeNull();
    expect(stageFromRoutingContext('onda 3 (fase )')).toBeNull();
    expect(stageFromRoutingContext('')).toBeNull();
    expect(stageFromRoutingContext(null)).toBeNull();
  });
});

describe('getModelMixByStage — model-routing nao e etapa', () => {
  it('reatribui linhas legadas a etapa SDD do contexto e soma as nativas', () => {
    const db = makeDb();
    const rows = getModelMixByStage(db);
    db.close();
    const byKey = Object.fromEntries(rows.map(r => [`${r.stage}/${r.modelo}`, r.n]));
    expect(byKey).toEqual({
      'execute-task/sonnet': 3,   // 2 nativas + 1 legada
      'plan/opus': 2,             // 1 nativa + 1 legada
      'review-task/haiku': 1,     // so legada
      'model-routing/sonnet': 1,  // legada sem fase parseavel: preservada
    });
  });

  it('projeta exclusivamente stage/modelo/n (contrato do endpoint)', () => {
    const db = makeDb();
    const rows = getModelMixByStage(db);
    db.close();
    for (const r of rows) expect(Object.keys(r).sort()).toEqual(['modelo', 'n', 'stage']);
  });

  it('degrada sem a coluna context: mantem o stage original', () => {
    const db = new Database(':memory:');
    db.exec(`
      CREATE TABLE decisions (id INTEGER PRIMARY KEY, stage TEXT, choice TEXT);
      INSERT INTO decisions (stage, choice) VALUES ('model-routing', 'model:sonnet'), ('plan', 'model:opus');
    `);
    const rows = getModelMixByStage(db);
    db.close();
    expect(rows).toEqual([
      { stage: 'model-routing', modelo: 'sonnet', n: 1 },
      { stage: 'plan', modelo: 'opus', n: 1 },
    ]);
  });
});

describe('getThroughputByStage — model-routing nao e etapa', () => {
  it('reatribui linhas legadas a etapa do contexto, soma as nativas e ordena por count desc', () => {
    const db = makeDb();
    const rows = getThroughputByStage(db);
    db.close();
    expect(rows).toEqual([
      { stage: 'execute-task', count: 3 },     // 2 nativas + 1 legada
      { stage: 'plan', count: 2 },             // 1 nativa + 1 legada
      { stage: 'clarify', count: 1 },
      { stage: 'model-routing', count: 1 },    // legada sem fase parseavel: preservada
      { stage: 'review-features', count: 1 },  // legada manter-atual
      { stage: 'review-task', count: 1 },      // legada haiku
    ]);
  });

  it('degrada sem a coluna context: mantem o stage original', () => {
    const db = new Database(':memory:');
    db.exec(`
      CREATE TABLE decisions (id INTEGER PRIMARY KEY, stage TEXT, choice TEXT);
      INSERT INTO decisions (stage, choice) VALUES ('model-routing', 'model:sonnet'), ('model-routing', 'x'), ('plan', 'model:opus');
    `);
    const rows = getThroughputByStage(db);
    db.close();
    expect(rows).toEqual([{ stage: 'model-routing', count: 2 }, { stage: 'plan', count: 1 }]);
  });
});
