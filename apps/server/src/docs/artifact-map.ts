/**
 * Mapeamento fixo etapa-SDD -> artefato(s) de documentacao + cruzamento com
 * o filesystem real da feature (research.md Decision 8; spec.md FR-005,
 * FR-007; data-model.md Entity "Documentation Artifact").
 * Task 3.1.
 *
 * Fonte EXCLUSIVA: filesystem `docs/specs/<feature>/` do projeto resolvido
 * (Principio I — server so LE metadados/existencia; nunca a knowledge.db
 * para o conteudo dos artefatos). "produced:false" e sucesso (FR-007),
 * nunca erro — nenhuma funcao aqui lanca excecao (Principio II).
 *
 * Decisoes de implementacao (research.md marca Decision 8 como
 * [PROPOSTA — a validar na implementacao]; fixadas nesta onda contra o
 * codigo real, task 3.1.2):
 *
 * 1. O "mapa fixo" cobre os 6 artefatos de NOME UNICO e estavel (spec,
 *    plan, research, data-model, quickstart, tasks) — so estes tem estado
 *    "produced:false" (ha um nome esperado unico para testar ausencia).
 *    Ordem e nomes espelham literalmente o exemplo de resposta ratificado
 *    em contracts/docs-api.md.
 * 2. `contracts/` (stage 'plan') e `checklists/` (stage 'checklist') sao
 *    LISTAS DINAMICAS de arquivo — Decision 8 tambem os associa a essas
 *    etapas ("plan -> ..., contracts/"; "checklist -> checklists/*.md").
 *    Por isso `extra:false` (estao "no mapa" no sentido lato de Decision 8
 *    e do doc-comment ratificado de FeatureDocDTO.extra em entities.ts:
 *    "true quando o arquivo esta presente na arvore FORA do mapa fixo") —
 *    mesmo sem nome de arquivo unico. Sem placeholder "nao produzido" (nao
 *    ha nome fixo esperado para testar a auséncia do proprio diretorio);
 *    a auséncia de progresso na etapa continua sinalizada pelos artefatos
 *    de nome unico da MESMA etapa (ex.: `plan.md produced:false` ja indica
 *    "etapa plan nao rodou", sem precisar de um segundo sinal via
 *    contracts/ vazio).
 * 3. Qualquer outro arquivo `.md` solto na RAIZ da feature (fora dos 6
 *    fixos e fora de contracts/checklists) e SC-002 "extra" genuino:
 *    `extra:true`. `stage` usa 'create-tasks' como bucket neutro — o valor
 *    nao carrega peso semantico para extras soltos (o frontend, FASE 4,
 *    agrupa por `extra:true` independentemente do `stage`).
 * 4. Escopo de descoberta restrito a EXATAMENTE os diretorios permitidos
 *    por research.md Decision 7 ("docs/specs/<feature>/, subdir
 *    contracts/, checklists/") — sem recursao arbitraria, sem outros
 *    subdiretorios.
 * 5. Somente arquivos `.md` (Documentation Artifact = documento gerado
 *    pela pipeline SDD).
 * 6. `artifactId` NUNCA contem `/` nem `.` — precisa passar pela MESMA
 *    regex anti-traversal usada em `:project`/`:feature`/`:artifact`
 *    (`/^[^/\\.<>]+$/`, Decision 7). Para contracts/checklists o id e
 *    `<prefixo>-<nome-sem-extensao>` (dash, nao slash).
 *
 * Validado empiricamente (2026-07-15): `find docs/specs -name "*.md"` neste
 * proprio repo mostra `docs/specs/cstk-panel/` com extras soltos reais
 * (data-gaps.md, plan-cards.md, review-onda-013.md, tasks-cards.md) e TODAS
 * as features com contracts/checklists como subdiretorios (nunca arquivos
 * soltos com esses nomes) — grounding real para as regras 2 e 3 acima.
 *
 * ── Artefatos de escopo PROJETO (briefing, constitution) ───────────────────
 *
 * As etapas `briefing` e `constitution` rodam UMA vez por projeto, antes de
 * qualquer feature, e gravam FORA de `docs/specs/<feature>/`. Como governam
 * todas as features (a constituicao e a fonte dos principios que a spec/plan
 * de cada feature cita), elas entram na listagem de QUALQUER feature —
 * marcadas com `scope:'project'`, `fileName` relativo a RAIZ DO PROJETO e
 * confinadas a essa raiz na leitura (nao a `featureDir`).
 *
 * Os caminhos candidatos abaixo nao sao inventados: sao exatamente a ordem de
 * descoberta declarada pelas skills que produzem os arquivos —
 * `~/.claude/skills/briefing/SKILL.md` (secao de descoberta, itens 1-3, e o
 * passo de escrita "Salvar em docs/01-briefing-discovery/briefing.md") e
 * `~/.claude/skills/constitution/SKILL.md` (itens 1-2, e "Salvar em
 * docs/constitution.md"). O primeiro candidato existente vence; se nenhum
 * existe, a entrada aparece com `produced:false` apontando o caminho
 * canonico (mesma semantica FR-007 dos artefatos fixos da feature).
 */
import { existsSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import type { FeatureDocDTO, FeatureDocScope, FeatureDocStage } from '@cstk-panel/shared-types';

/** Identica ao regex anti-traversal de path params HTTP (FeatureParamSchema,
 *  routes/features.ts; SAFE_SEGMENT_RE de ingest-watcher.ts) — reaplicada
 *  para filtrar defensivamente nomes vindos de readdirSync antes de
 *  compor artifactId/fileName expostos na resposta. */
const SAFE_SEGMENT_RE = /^[^/\\.<>]+$/;

interface FixedMapEntry {
  stage: FeatureDocStage;
  artifactId: string;
  fileName: string;
}

/**
 * As duas raizes de leitura de uma pagina de feature. `featureDir` sempre e
 * derivado de `projectRoot` (nunca recebido pronto) para que a unica fonte
 * do layout `docs/specs/<feature>/` continue sendo este modulo.
 */
export interface ArtifactRoots {
  projectRoot: string;
  featureDir: string;
}

export function artifactRoots(projectRoot: string, feature: string): ArtifactRoots {
  return { projectRoot, featureDir: join(projectRoot, 'docs', 'specs', feature) };
}

/** Raiz a que `fileName` de uma entrada e relativo — e a que a leitura do
 *  conteudo fica confinada (confinement.ts). */
export function rootForScope(roots: ArtifactRoots, scope: FeatureDocScope): string {
  return scope === 'project' ? roots.projectRoot : roots.featureDir;
}

interface ProjectMapEntry {
  stage: FeatureDocStage;
  artifactId: string;
  /** caminhos relativos ao projectRoot, na ordem de descoberta das skills;
   *  o primeiro existente vence, o primeiro da lista e o canonico */
  candidates: readonly string[];
}

/** Mapa fixo de escopo PROJETO — ver nota "Artefatos de escopo PROJETO" no
 *  topo do arquivo para a proveniencia de cada caminho. */
const PROJECT_MAP: readonly ProjectMapEntry[] = [
  {
    stage: 'briefing',
    artifactId: 'briefing',
    candidates: ['docs/01-briefing-discovery/briefing.md', 'docs/briefing.md'],
  },
  {
    stage: 'constitution',
    artifactId: 'constitution',
    candidates: ['docs/constitution.md', 'constitution.md'],
  },
];

/** Diretorio de briefings do projeto: alem do `briefing.md` canonico, a skill
 *  grava revisoes datadas (`briefing-[DATE].md`, `BRIEFING-*.md`) — listadas
 *  dinamicamente, mesmo tratamento de `contracts/`/`checklists/`. */
const BRIEFING_DIR = 'docs/01-briefing-discovery';

/** Mapa fixo etapa SDD -> artefato de nome unico (research.md Decision 8).
 *  `clarify` nao aparece: so atualiza spec.md, nao produz arquivo novo. */
const FIXED_MAP: readonly FixedMapEntry[] = [
  { stage: 'specify', artifactId: 'spec', fileName: 'spec.md' },
  { stage: 'plan', artifactId: 'plan', fileName: 'plan.md' },
  { stage: 'plan', artifactId: 'research', fileName: 'research.md' },
  { stage: 'plan', artifactId: 'data-model', fileName: 'data-model.md' },
  { stage: 'plan', artifactId: 'quickstart', fileName: 'quickstart.md' },
  { stage: 'create-tasks', artifactId: 'tasks', fileName: 'tasks.md' },
];

/** Subdiretorios de lista dinamica (Decision 8) — nome do dir, stage dono,
 *  prefixo usado para compor um artifactId FLAT (sem "/", sem "."). */
const MAPPED_SUBDIRS: ReadonlyArray<{ dir: string; stage: FeatureDocStage; prefix: string }> = [
  { dir: 'contracts', stage: 'plan', prefix: 'contracts' },
  { dir: 'checklists', stage: 'checklist', prefix: 'checklists' },
];

function stripMdExt(name: string): string {
  return name.endsWith('.md') ? name.slice(0, -3) : name;
}

/** Caminho relativo (sempre com '/') -> caminho absoluto de fs. */
function underRoot(root: string, relPath: string): string {
  return join(root, ...relPath.split('/'));
}

/**
 * artifactId de um briefing datado/alternativo. Normaliza o prefixo para nao
 * gerar ids como `briefing-BRIEFING-2026-01-01`: o prefixo `briefing`/
 * `BRIEFING` que a propria skill ja usa no nome do arquivo e removido antes
 * de reaplicar o prefixo canonico em minusculas.
 */
function briefingArtifactId(baseName: string): string {
  const rest = baseName.replace(/^briefing[-_]?/i, '');
  return rest ? `briefing-${rest}` : 'briefing';
}

/**
 * Lista arquivos `.md` de 1 subdiretorio DIRETO (sem recursao). Inclui
 * symlinks (`d.isSymbolicLink()`) alem de arquivos regulares — a listagem
 * so reporta METADADOS (nunca conteudo); a rejeicao de symlink acontece na
 * LEITURA (confinement.ts, task 3.4), nao aqui. []  se dir ausente/erro de
 * leitura (Principio II — nunca lanca).
 */
function listMdFiles(dirAbsPath: string): string[] {
  try {
    return readdirSync(dirAbsPath, { withFileTypes: true })
      .filter(d => (d.isFile() || d.isSymbolicLink())
        && d.name.endsWith('.md')
        && SAFE_SEGMENT_RE.test(stripMdExt(d.name)))
      .map(d => d.name)
      .sort();
  } catch {
    return [];
  }
}

/**
 * Constroi a listagem de artefatos de 1 feature cruzando os mapas fixos com o
 * filesystem real (task 3.1.2). NUNCA lanca (Principio II) — ausencia do
 * proprio `featureDir` (ou do proprio `projectRoot`) so resulta em
 * produced:false para todo o mapa fixo e nenhuma entrada dinamica/extra
 * (nenhum caso especial necessario: todas as chamadas de fs abaixo ja
 * degradam para "nao encontrado" sozinhas).
 *
 * Ordem = ordem da pipeline SDD: briefing e constitution (escopo projeto)
 * primeiro, depois os artefatos da feature.
 *
 * Retorna metadados apenas — SEM `content` (contrato da listagem, FR-005;
 * o endpoint de conteudo, task 3.3, preenche `content` para 1 entrada).
 */
export function buildFeatureDocsList(roots: ArtifactRoots): FeatureDocDTO[] {
  const { projectRoot, featureDir } = roots;
  const entries: FeatureDocDTO[] = [];
  const claimedFileNames = new Set<string>();
  const claimedProjectFiles = new Set<string>();
  const claimedArtifactIds = new Set<string>();

  // 1. Mapa fixo de PROJETO — briefing e constitution (governam a feature).
  for (const { stage, artifactId, candidates } of PROJECT_MAP) {
    const found = candidates.find(rel => existsSync(underRoot(projectRoot, rel)));
    const fileName = found ?? candidates[0]!; // sem match: caminho canonico + produced:false
    entries.push({ stage, artifactId, scope: 'project', fileName, produced: found !== undefined, extra: false });
    claimedProjectFiles.add(fileName);
    claimedArtifactIds.add(artifactId);
  }

  // 2. Briefings alternativos/datados em docs/01-briefing-discovery/ — lista
  //    dinamica (mesmo tratamento de contracts/ e checklists/).
  for (const name of listMdFiles(underRoot(projectRoot, BRIEFING_DIR))) {
    const relFileName = `${BRIEFING_DIR}/${name}`;
    if (claimedProjectFiles.has(relFileName)) continue;
    const artifactId = briefingArtifactId(stripMdExt(name));
    if (claimedArtifactIds.has(artifactId)) continue; // colisao de id apos normalizacao do prefixo
    claimedArtifactIds.add(artifactId);
    entries.push({
      stage: 'briefing',
      artifactId,
      scope: 'project',
      fileName: relFileName,
      produced: true, // so aparece se foi encontrado — sem placeholder "ausente"
      extra: false,
    });
  }

  // 3. Mapa fixo da FEATURE — 6 artefatos de nome unico e estavel.
  for (const { stage, artifactId, fileName } of FIXED_MAP) {
    const produced = existsSync(join(featureDir, fileName));
    entries.push({ stage, artifactId, scope: 'feature', fileName, produced, extra: false });
    claimedFileNames.add(fileName);
    claimedArtifactIds.add(artifactId);
  }

  // 4. Subdiretorios de lista dinamica (contracts/, checklists/) — Decision 8.
  for (const { dir, stage, prefix } of MAPPED_SUBDIRS) {
    const names = listMdFiles(join(featureDir, dir));
    for (const name of names) {
      const relFileName = `${dir}/${name}`;
      const artifactId = `${prefix}-${stripMdExt(name)}`;
      entries.push({
        stage,
        artifactId,
        scope: 'feature',
        fileName: relFileName,
        produced: true, // so aparece se foi encontrado — sem placeholder "ausente"
        extra: false,
      });
      claimedFileNames.add(relFileName);
      claimedArtifactIds.add(artifactId);
    }
  }

  // 5. Arquivos .md soltos na raiz da feature, fora do mapa fixo (SC-002).
  const rootNames = listMdFiles(featureDir);
  for (const name of rootNames) {
    if (claimedFileNames.has(name)) continue;
    // Um extra pode colidir com um id de escopo projeto (ex.: um `briefing.md`
    // solto dentro da feature). O endpoint de conteudo resolve por artifactId,
    // entao o id precisa ser unico na listagem — desambigua com prefixo de
    // escopo (deterministico: mesma arvore -> mesmos ids).
    const baseId = stripMdExt(name);
    const artifactId = claimedArtifactIds.has(baseId) ? `feature-${baseId}` : baseId;
    if (claimedArtifactIds.has(artifactId)) continue;
    claimedArtifactIds.add(artifactId);
    entries.push({
      stage: 'create-tasks', // bucket neutro — ver nota de decisao (3) no topo do arquivo
      artifactId,
      scope: 'feature',
      fileName: name,
      produced: true,
      extra: true,
    });
  }

  return entries;
}

/**
 * mtime (epoch ms) do artefato mais recente dentre os `produced:true` —
 * usado para o ETag da listagem (contracts/docs-api.md: ETag deriva do
 * mtime dos ARQUIVOS, nao da knowledge.db). `null` se nada foi produzido
 * ainda (nada para basear um ETag).
 */
export function latestArtifactMtimeMs(roots: ArtifactRoots, entries: readonly FeatureDocDTO[]): number | null {
  let latest: number | null = null;
  for (const e of entries) {
    if (!e.produced) continue;
    try {
      const st = statSync(underRoot(rootForScope(roots, e.scope), e.fileName));
      if (latest === null || st.mtimeMs > latest) latest = st.mtimeMs;
    } catch {
      // TOCTOU: arquivo removido entre a checagem `produced` e este stat — ignora (Principio II)
    }
  }
  return latest;
}
