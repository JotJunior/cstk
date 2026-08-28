/**
 * Configuracao do servidor — resolucao do path do banco.
 * Ref: plan.md §Project Structure; spec.md FR-018
 *
 * Ordem de resolucao (FR-018):
 * 1. Variavel de ambiente CSTK_KNOWLEDGE_DB (config explicita)
 * 2. Default: ~/.claude/cstk/knowledge.db
 *
 * O path e canonicalizado via path.resolve para evitar path traversal.
 *
 * Versoes de schema aceitas (FR-V3-001): vindas do env CSTK_SCHEMA_VERSIONS
 * (CSV; default '2,3'). NUNCA hardcoded no guard de abertura — assim um
 * operador aceita uma versao futura sem rebuild ou trava numa so.
 */
import { homedir } from 'node:os';
import { resolve } from 'node:path';

/** Default quando CSTK_SCHEMA_VERSIONS nao esta definido — aceita v2..v15.
 *  v4 (recall-memory-mirror) adiciona a tabela `memories`; v5 (recall-suggestions)
 *  adiciona a tabela `suggestions`; v6 adiciona a coluna `decisions.options`;
 *  v7 (new-schema) migra todas as colunas pt-BR→EN snake_case;
 *  v8 (recall-worktree-identity) adiciona a coluna `session` em `executions` e `waves`;
 *  v9 (executions-target-path) adiciona `executions.target_project_path`;
 *  v10 (wave-token-metrics, cstk 5.25.0) adiciona 9 colunas `agent_*` em `waves`
 *  com o consumo real de subagentes (tokens, tool uses, duracao);
 *  v11 (otel-wave-cost, cstk 5.30.0) adiciona 5 colunas `otel_*` em `waves`
 *  com o custo REAL em USD e os tokens medidos pela telemetria do Claude Code
 *  (`otel_cost_usd` e fracionario — REAL, nao INTEGER);
 *  v12 (otel-model-breakdown, cstk 5.33.0) adiciona a tabela `wave_model_usage`
 *  (grao onda x modelo: `model` como string BRUTA do OTel, `cost_usd`,
 *  `total_tokens`) e 8 colunas `otel_{main,subagent}_{input,output,cache_read,
 *  cache_creation}_tokens` em `waves` com o breakdown de tokens por fonte.
 *  Permite custo por modelo (opus vs sonnet) e cache-hit ratio, antes
 *  impossiveis. `wave_model_usage` NAO alimenta a FTS — o label de modelo vem
 *  de fonte externa e nunca deve alcancar contexto de LLM.
 *  v13 (loose-usage-capture, cstk 6.6.0) adiciona a tabela `loose_usage`
 *  (consumo avulso: sessoes interativas FORA de execucoes 00c, grao
 *  processo/projeto — nao confundir com `wave_model_usage`, grao onda x
 *  modelo);
 *  v14 (plan-usage-capture, cstk 7.2.0) adiciona a tabela `plan_usage`
 *  (gauge `rate_limits` da CONTA por escopo `five_hour`/`seven_day`, capturado
 *  pelo hook `statusLine.command` a cada render — append-only, grao escopo x
 *  momento de captura). Fora do fluxo state.json/onda, mesma familia de
 *  `loose_usage`: sem `feature`/`wave`/`execution_id` por construcao.
 *  v15 (structural-decision-human-gate, cstk 8.6.0) adiciona 3 colunas TEXT
 *  aditivas em `decisions` — `decision_class` (enum fechado
 *  `estrutural`/`operacional`; NULL = nao declarada), `structural_axis`
 *  (enum fechado de eixos estruturais) e `human_consent_block_id`
 *  (id `block-NNN` do BloqueioHumano respondido que consente a decisao).
 *  Decisao legada sem os campos → NULL, nunca fabricado.
 *  Todas sao aditivas, entao as telas existentes seguem operando e os recursos
 *  novos aparecem so quando a tabela/coluna esta presente (Principio II). */
export const DEFAULT_SCHEMA_VERSIONS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15'] as const;

export interface ServerConfig {
  /** Path absoluto canonicalizado para knowledge.db */
  dbPath: string;
  /** Porta do servidor HTTP (bind em localhost) */
  port: number;
  /** Host — SEMPRE 127.0.0.1 (FR-017: localhost bind) */
  host: string;
  /** Origem permitida para CORS */
  corsOrigin: string;
  /** Versoes de schema_meta.schema_version aceitas na abertura (FR-V3-001). */
  supportedSchemaVersions: string[];
  /**
   * Diretorio do SPA buildado (apps/web/dist) servido estaticamente para que
   * `npm run start` suba API + front-end no mesmo processo/porta. Resolvido
   * relativo ao dist do server (__dirname = apps/server/dist) ou via env
   * CSTK_WEB_DIR. Pode nao existir (build do web ausente) — o server degrada:
   * sobe so a API e loga aviso (Principio II).
   */
  webDir: string;
}

function resolveDbPath(): string {
  const fromEnv = process.env['CSTK_KNOWLEDGE_DB'];
  if (fromEnv && fromEnv.trim() !== '') {
    return resolve(fromEnv.trim());
  }
  return resolve(homedir(), '.claude', 'cstk', 'knowledge.db');
}

/**
 * Resolve o diretorio do SPA buildado. Env CSTK_WEB_DIR tem prioridade; senao
 * sobe de apps/server/dist ate apps/ e desce em web/dist. __dirname existe no
 * build CommonJS (modulo CommonJS em apps/server/tsconfig.json).
 */
function resolveWebDir(): string {
  const fromEnv = process.env['CSTK_WEB_DIR'];
  if (fromEnv && fromEnv.trim() !== '') {
    return resolve(fromEnv.trim());
  }
  return resolve(__dirname, '..', '..', 'web', 'dist');
}

/** Parseia CSTK_SCHEMA_VERSIONS (CSV) em lista; vazio/ausente → default. */
function resolveSchemaVersions(): string[] {
  const raw = process.env['CSTK_SCHEMA_VERSIONS'];
  if (!raw || raw.trim() === '') return [...DEFAULT_SCHEMA_VERSIONS];
  const parsed = raw.split(',').map(v => v.trim()).filter(v => v !== '');
  return parsed.length > 0 ? parsed : [...DEFAULT_SCHEMA_VERSIONS];
}

/**
 * Resolve o mapa nome-logico -> caminho absoluto de projetos observaveis
 * (FR-008, research.md Decision 1).
 *
 * Formato do env CSTK_PROJECT_PATHS (decisao de implementacao — [PROPOSTA]
 * do research.md validada aqui): lista de pares `nome=/abs/path` separados
 * por `;`, ex.: `CSTK_PROJECT_PATHS="cstk-panel=/Users/jot/…/cstk-panel;outro=/x/y"`.
 * Cada path e canonicalizado via `path.resolve()` (mesmo anti-traversal de
 * resolveDbPath()). Entradas malformadas (sem `=`, nome vazio) sao ignoradas
 * silenciosamente — nunca lanca excecao (Principio II: Degradar-Nunca-Quebrar).
 *
 * Lido a cada chamada (sem cache), espelhando resolveSchemaVersions() — o
 * mapa e pequeno e a config pode ser ajustada pelo operador sem restart do
 * processo hospedeiro dos testes.
 */
function resolveProjectPathsMap(): Record<string, string> {
  const raw = process.env['CSTK_PROJECT_PATHS'];
  const map: Record<string, string> = {};
  if (!raw || raw.trim() === '') return map;
  for (const entry of raw.split(';')) {
    const trimmed = entry.trim();
    if (trimmed === '') continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx <= 0) continue; // sem '=' ou nome vazio -> entrada malformada, ignorar
    const name = trimmed.slice(0, eqIdx).trim();
    const rawPath = trimmed.slice(eqIdx + 1).trim();
    if (name === '' || rawPath === '') continue;
    map[name] = resolve(rawPath);
  }
  return map;
}

/**
 * Resolve o nome logico de um projeto (`project`) para o caminho absoluto
 * configurado pelo operador via CSTK_PROJECT_PATHS (FR-008). Retorna `null`
 * (NUNCA lanca) quando o projeto nao esta no mapa — aciona a degradacao
 * graciosa de FR-012 nos consumidores (watcher, rotas de docs), nunca 5xx.
 *
 * Default (env ausente/vazio): mapa vazio. Desde o schema v9 da knowledge.db
 * (cstk >= 5.19) existe fallback automatico via executions.target_project_path
 * — ver resolveProjectRoot() em lib/project-root.ts, que encadeia esta
 * funcao (override do operador, sempre vence) com a leitura validada da db.
 */
export function resolveProjectPath(project: string): string | null {
  const map = resolveProjectPathsMap();
  return map[project] ?? null;
}

/**
 * Lista os caminhos absolutos de TODOS os projetos configurados pelo operador
 * via CSTK_PROJECT_PATHS. Consumido pela descoberta via filesystem do watcher
 * (ingest-watcher): raizes onde procurar `state.json` recem-criados que ainda
 * NAO possuem linha na knowledge.db (ovo-e-galinha da descoberta via db).
 * Mesmo contrato de resolveProjectPath: nunca lanca; env ausente ⇒ lista vazia.
 */
export function listConfiguredProjectPaths(): string[] {
  return Object.values(resolveProjectPathsMap());
}

export function loadConfig(): ServerConfig {
  return {
    dbPath: resolveDbPath(),
    port: parseInt(process.env['PORT'] ?? '3001', 10),
    host: '127.0.0.1', // FR-017: bind APENAS em localhost
    corsOrigin: process.env['CORS_ORIGIN'] ?? 'http://localhost:5173',
    supportedSchemaVersions: resolveSchemaVersions(),
    webDir: resolveWebDir(),
  };
}
