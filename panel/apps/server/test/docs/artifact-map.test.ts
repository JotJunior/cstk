/**
 * Testes unitarios de buildFeatureDocsList / latestArtifactMtimeMs (task 3.1.3).
 *
 * Ref: research.md Decision 8 (FR-005, FR-007); contracts/docs-api.md;
 * data-model.md Entity "Documentation Artifact"; SC-002.
 *
 * Convencao do projeto: mkdtempSync(tmpdir()) + mkdirSync/writeFileSync +
 * rmSync no afterEach (ver test/watchers/ingest-watcher.test.ts).
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  artifactRoots,
  buildFeatureDocsList,
  latestArtifactMtimeMs,
  type ArtifactRoots,
} from '../../src/docs/artifact-map.js';

let tmpRoot: string;
let featureDir: string;
let roots: ArtifactRoots;

beforeEach(() => {
  tmpRoot = mkdtempSync(join(tmpdir(), 'cstk-docs-map-'));
  roots = artifactRoots(tmpRoot, 'minha-feature');
  featureDir = roots.featureDir;
  mkdirSync(featureDir, { recursive: true });
});

afterEach(() => {
  rmSync(tmpRoot, { recursive: true, force: true });
});

describe('buildFeatureDocsList — feature completa', () => {
  it('marca produced:true para os 7 artefatos fixos quando todos existem', () => {
    for (const name of ['spec.md', 'plan.md', 'research.md', 'data-model.md', 'quickstart.md', 'tasks.md', 'converge-report.md']) {
      writeFileSync(join(featureDir, name), `# ${name}`);
    }
    const entries = buildFeatureDocsList(roots);
    const fixedIds = ['spec', 'plan', 'research', 'data-model', 'quickstart', 'tasks', 'converge-report'];
    for (const id of fixedIds) {
      const e = entries.find(x => x.artifactId === id);
      expect(e, `entrada ${id} deve existir`).toBeDefined();
      expect(e!.produced).toBe(true);
      expect(e!.extra).toBe(false);
      expect(e!.content).toBeUndefined(); // listagem nunca inclui content
    }
  });

  it('reflete exatamente stage/artifactId/fileName do mapa fixo (Decision 8)', () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    const entries = buildFeatureDocsList(roots);
    const spec = entries.find(e => e.artifactId === 'spec');
    expect(spec).toEqual({ stage: 'specify', artifactId: 'spec', scope: 'feature', fileName: 'spec.md', produced: true, extra: false });
    const plan = entries.find(e => e.artifactId === 'plan');
    expect(plan).toMatchObject({ stage: 'plan', fileName: 'plan.md', produced: false, extra: false });
    const tasks = entries.find(e => e.artifactId === 'tasks');
    expect(tasks).toMatchObject({ stage: 'create-tasks', fileName: 'tasks.md' });
  });
});

describe('buildFeatureDocsList — feature parcial (FR-007)', () => {
  it('marca produced:false (nao erro) para artefatos do mapa fixo ausentes', () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    writeFileSync(join(featureDir, 'plan.md'), '# plan');
    // research.md, data-model.md, quickstart.md, tasks.md ausentes

    const entries = buildFeatureDocsList(roots);
    expect(entries.find(e => e.artifactId === 'spec')?.produced).toBe(true);
    expect(entries.find(e => e.artifactId === 'plan')?.produced).toBe(true);
    expect(entries.find(e => e.artifactId === 'research')?.produced).toBe(false);
    expect(entries.find(e => e.artifactId === 'data-model')?.produced).toBe(false);
    expect(entries.find(e => e.artifactId === 'quickstart')?.produced).toBe(false);
    expect(entries.find(e => e.artifactId === 'tasks')?.produced).toBe(false);
    expect(entries.find(e => e.artifactId === 'converge-report')?.produced).toBe(false);
    // Ausencia nunca remove a entrada do mapa fixo (ela deve sempre aparecer)
    expect(entries.filter(e => e.scope === 'feature' && !e.extra)).toHaveLength(7);
  });

  it('degrada para 100% produced:false quando o proprio featureDir nao existe (nunca lanca)', () => {
    const inexistente = artifactRoots(tmpRoot, 'nao-existe');
    expect(() => buildFeatureDocsList(inexistente)).not.toThrow();
    const entries = buildFeatureDocsList(inexistente);
    // 7 fixos da feature + briefing + constitution + roadmap (escopo projeto)
    expect(entries).toHaveLength(10);
    expect(entries.every(e => e.produced === false)).toBe(true);
  });
});

describe('buildFeatureDocsList — artefatos de escopo projeto (briefing/constitution)', () => {
  it('lista briefing e constitution com scope:project e caminho relativo a raiz do projeto', () => {
    mkdirSync(join(tmpRoot, 'docs', '01-briefing-discovery'), { recursive: true });
    writeFileSync(join(tmpRoot, 'docs', '01-briefing-discovery', 'briefing.md'), '# briefing');
    writeFileSync(join(tmpRoot, 'docs', 'constitution.md'), '# constituicao');

    const entries = buildFeatureDocsList(roots);
    expect(entries.find(e => e.artifactId === 'briefing')).toEqual({
      stage: 'briefing', artifactId: 'briefing', scope: 'project',
      fileName: 'docs/01-briefing-discovery/briefing.md', produced: true, extra: false,
    });
    expect(entries.find(e => e.artifactId === 'constitution')).toEqual({
      stage: 'constitution', artifactId: 'constitution', scope: 'project',
      fileName: 'docs/constitution.md', produced: true, extra: false,
    });
  });

  it('aparecem antes dos artefatos da feature (ordem da pipeline SDD)', () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    const ids = buildFeatureDocsList(roots).map(e => e.artifactId);
    expect(ids.slice(0, 2)).toEqual(['briefing', 'constitution']);
  });

  it('produced:false com o caminho canonico quando nenhum candidato existe (FR-007)', () => {
    const entries = buildFeatureDocsList(roots);
    expect(entries.find(e => e.artifactId === 'briefing')).toMatchObject({
      produced: false, fileName: 'docs/01-briefing-discovery/briefing.md',
    });
    expect(entries.find(e => e.artifactId === 'constitution')).toMatchObject({
      produced: false, fileName: 'docs/constitution.md',
    });
  });

  it('cai no caminho alternativo declarado pelas skills quando o canonico nao existe', () => {
    writeFileSync(join(tmpRoot, 'docs', 'briefing.md'), '# briefing solto');
    writeFileSync(join(tmpRoot, 'constitution.md'), '# constituicao na raiz');
    const entries = buildFeatureDocsList(roots);
    expect(entries.find(e => e.artifactId === 'briefing')).toMatchObject({
      produced: true, fileName: 'docs/briefing.md',
    });
    expect(entries.find(e => e.artifactId === 'constitution')).toMatchObject({
      produced: true, fileName: 'constitution.md',
    });
  });

  it('lista briefings adicionais do diretorio de discovery normalizando o prefixo do id', () => {
    const dir = join(tmpRoot, 'docs', '01-briefing-discovery');
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'briefing.md'), '# canonico');
    writeFileSync(join(dir, 'backend-brief.md'), '# backend');
    writeFileSync(join(dir, 'BRIEFING-2026-01-01.md'), '# revisao datada');

    const entries = buildFeatureDocsList(roots);
    const briefings = entries.filter(e => e.stage === 'briefing').map(e => e.artifactId);
    expect(briefings).toEqual(['briefing', 'briefing-2026-01-01', 'briefing-backend-brief']);
    expect(entries.find(e => e.artifactId === 'briefing-backend-brief')).toMatchObject({
      scope: 'project', fileName: 'docs/01-briefing-discovery/backend-brief.md', produced: true, extra: false,
    });
  });

  it('extra da feature que colide com id de escopo projeto e desambiguado', () => {
    mkdirSync(join(tmpRoot, 'docs'), { recursive: true });
    writeFileSync(join(tmpRoot, 'docs', 'constitution.md'), '# constituicao do projeto');
    writeFileSync(join(featureDir, 'constitution.md'), '# nota solta na feature');

    const entries = buildFeatureDocsList(roots);
    const ids = entries.map(e => e.artifactId);
    expect(new Set(ids).size).toBe(ids.length); // ids unicos — a rota resolve por id
    expect(entries.find(e => e.artifactId === 'constitution')).toMatchObject({ scope: 'project' });
    expect(entries.find(e => e.artifactId === 'feature-constitution')).toMatchObject({
      scope: 'feature', fileName: 'constitution.md', extra: true,
    });
  });
});

describe('buildFeatureDocsList — arquivos extra fora do mapa (SC-002)', () => {
  it('lista arquivo .md solto na raiz como extra:true, produced:true', () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    writeFileSync(join(featureDir, 'data-gaps.md'), '# gaps');
    const entries = buildFeatureDocsList(roots);
    const extra = entries.find(e => e.artifactId === 'data-gaps');
    expect(extra).toBeDefined();
    expect(extra!.extra).toBe(true);
    expect(extra!.produced).toBe(true);
    expect(extra!.fileName).toBe('data-gaps.md');
  });

  it('ignora arquivos nao-.md soltos na raiz', () => {
    writeFileSync(join(featureDir, 'notes.txt'), 'nao e markdown');
    const entries = buildFeatureDocsList(roots);
    expect(entries.find(e => e.fileName === 'notes.txt')).toBeUndefined();
  });

  it('lista arquivos de contracts/ como extra:false, stage plan (Decision 8)', () => {
    mkdirSync(join(featureDir, 'contracts'), { recursive: true });
    writeFileSync(join(featureDir, 'contracts', 'docs-api.md'), '# contrato');
    const entries = buildFeatureDocsList(roots);
    const e = entries.find(x => x.artifactId === 'contracts-docs-api');
    expect(e).toBeDefined();
    expect(e).toMatchObject({ stage: 'plan', fileName: 'contracts/docs-api.md', produced: true, extra: false });
  });

  it('lista arquivos de checklists/ como extra:false, stage checklist (Decision 8)', () => {
    mkdirSync(join(featureDir, 'checklists'), { recursive: true });
    writeFileSync(join(featureDir, 'checklists', 'security.md'), '# checklist');
    const entries = buildFeatureDocsList(roots);
    const e = entries.find(x => x.artifactId === 'checklists-security');
    expect(e).toBeDefined();
    expect(e).toMatchObject({ stage: 'checklist', fileName: 'checklists/security.md', produced: true, extra: false });
  });

  it('multiplos arquivos em contracts/ e checklists/ aparecem todos (ordenados)', () => {
    mkdirSync(join(featureDir, 'contracts'), { recursive: true });
    mkdirSync(join(featureDir, 'checklists'), { recursive: true });
    writeFileSync(join(featureDir, 'contracts', 'docs-api.md'), '# a');
    writeFileSync(join(featureDir, 'contracts', 'watchers.md'), '# b');
    writeFileSync(join(featureDir, 'checklists', 'security.md'), '# c');
    writeFileSync(join(featureDir, 'checklists', 'performance.md'), '# d');
    const entries = buildFeatureDocsList(roots);
    const contractIds = entries.filter(e => e.artifactId.startsWith('contracts-')).map(e => e.artifactId);
    const checklistIds = entries.filter(e => e.artifactId.startsWith('checklists-')).map(e => e.artifactId);
    expect(contractIds).toEqual(['contracts-docs-api', 'contracts-watchers']);
    expect(checklistIds).toEqual(['checklists-performance', 'checklists-security']);
  });

  it('inclui arquivo symlinkado na listagem (metadados apenas — rejeicao acontece na leitura, task 3.4)', () => {
    const outsideFile = join(tmpRoot, 'fora-da-raiz.md');
    writeFileSync(outsideFile, '# fora');
    symlinkSync(outsideFile, join(featureDir, 'evil.md'));
    const entries = buildFeatureDocsList(roots);
    const evil = entries.find(e => e.artifactId === 'evil');
    expect(evil).toBeDefined();
    expect(evil!.extra).toBe(true);
    expect(evil!.produced).toBe(true);
  });
});

describe('latestArtifactMtimeMs', () => {
  it('retorna null quando nenhum artefato foi produzido', () => {
    const entries = buildFeatureDocsList(roots);
    expect(latestArtifactMtimeMs(roots, entries)).toBeNull();
  });

  it('retorna o mtime mais recente dentre os artefatos produzidos', () => {
    writeFileSync(join(featureDir, 'spec.md'), '# spec');
    const entries = buildFeatureDocsList(roots);
    const latest = latestArtifactMtimeMs(roots, entries);
    expect(latest).not.toBeNull();
    expect(typeof latest).toBe('number');
    expect(latest!).toBeGreaterThan(0);
  });
});

/**
 * Artefatos que entraram no pipeline DEPOIS que este mapa foi escrito e
 * ficavam invisiveis no painel:
 *   - `roadmap.md` — escopo PROJETO (ordena as features entre si; nao existe
 *     roadmap por feature), ao lado de briefing e constitution;
 *   - `converge-report.md` — escopo FEATURE, produzido pela etapa `converge`
 *     (feature `pipeline-converge`).
 */
describe('buildFeatureDocsList — roadmap (projeto) e converge-report (feature)', () => {
  it('lista roadmap com scope:project a partir de docs/roadmap.md', () => {
    mkdirSync(join(tmpRoot, 'docs'), { recursive: true });
    writeFileSync(join(tmpRoot, 'docs', 'roadmap.md'), '# roadmap');

    expect(buildFeatureDocsList(roots).find(e => e.artifactId === 'roadmap')).toEqual({
      stage: 'roadmap', artifactId: 'roadmap', scope: 'project',
      fileName: 'docs/roadmap.md', produced: true, extra: false,
    });
  });

  it('aceita roadmap.md na raiz como candidato alternativo', () => {
    writeFileSync(join(tmpRoot, 'roadmap.md'), '# roadmap na raiz');
    const e = buildFeatureDocsList(roots).find(x => x.artifactId === 'roadmap');
    expect(e?.produced).toBe(true);
    expect(e?.fileName).toBe('roadmap.md');
  });

  it('lista converge-report com scope:feature', () => {
    writeFileSync(join(featureDir, 'converge-report.md'), '# convergencia');

    expect(buildFeatureDocsList(roots).find(e => e.artifactId === 'converge-report')).toEqual({
      stage: 'converge', artifactId: 'converge-report', scope: 'feature',
      fileName: 'converge-report.md', produced: true, extra: false,
    });
  });

  it('marca produced:false (nao erro) quando ausentes — projeto sem roadmap e comum', () => {
    const entries = buildFeatureDocsList(roots);
    expect(entries.find(e => e.artifactId === 'roadmap')?.produced).toBe(false);
    expect(entries.find(e => e.artifactId === 'converge-report')?.produced).toBe(false);
  });

  it('roadmap vem junto dos demais artefatos de projeto, antes dos da feature', () => {
    mkdirSync(join(tmpRoot, 'docs'), { recursive: true });
    writeFileSync(join(tmpRoot, 'docs', 'roadmap.md'), '# roadmap');
    writeFileSync(join(featureDir, 'spec.md'), '# spec');

    const entries = buildFeatureDocsList(roots);
    const idxRoadmap = entries.findIndex(e => e.artifactId === 'roadmap');
    const idxSpec = entries.findIndex(e => e.artifactId === 'spec');
    expect(idxRoadmap).toBeGreaterThanOrEqual(0);
    expect(idxRoadmap).toBeLessThan(idxSpec);
  });
});
