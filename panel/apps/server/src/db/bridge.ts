/**
 * Conexao de escrita para `bridge.db` — a UNICA conexao read-write do
 * processo do painel (Principio I, "Read-Only sobre o CORPUS", constitution
 * 2.0.0). `knowledge.db` (corpus derivado, `db/open.ts`) fica INTOCADO: esta
 * conexao aponta para um arquivo SEPARADO, dedicado a Ponte de intervencao
 * humana ("human-bridge"), que nao e corpus, nao e lido por `cstk recall` e
 * nao e reconstruido por `--reindex` (research.md Decision 2).
 *
 * Ref: docs/specs/human-bridge/data-model.md §"Entity: Intervention";
 * docs/specs/human-bridge/plan.md (Project Structure, `db/bridge.ts` NOVO);
 * docs/specs/human-bridge/contracts/panel-bridge-api.md §11.4
 * Tasks: 1.2.1 - 1.2.5
 *
 * NOTA (achado registrado como Decisao na onda-008): este arquivo contem os
 * verbos `CREATE TABLE`/`CREATE INDEX` literais, algo que
 * `panel/scripts/readonly-check.sh` hoje reprova por variar `apps/server/src`
 * INTEIRO (nao apenas `db/queries/**`). Isso e o comportamento ESPERADO e
 * aceito pela propria constitution ("Enquanto o script nao for atualizado
 * ele permanece MAIS restritivo que a constituicao — falha fechada, segura,
 * mas reprovaria o primeiro commit da Ponte", panel/docs/constitution.md
 * §Sync Impact Report da emenda 2026-08-26). O estreitamento do escopo do
 * gate para `db/queries/**` e tarefa 3.1.9 e MUST acontecer no MESMO commit
 * de `routes/bridge.ts` (3.1.1-3.1.8) — nunca antes. Ate la,
 * `npm run lint:readonly-check` FALHA de proposito para este arquivo; isso
 * NAO bloqueia esta tarefa (nao esta cabeado a `npm test`/CI — verificado:
 * nenhum workflow em `.github/workflows/` invoca `readonly-check.sh`).
 */
import Database from 'better-sqlite3';
import { chmodSync, existsSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';

/**
 * Resolve o path de `bridge.db` — MESMA precedencia ja usada para o corpus
 * (`config.ts:resolveDbPath`, verificado `config.ts:6-7,77`):
 * 1. Variavel de ambiente `CSTK_BRIDGE_DB` (config explicita)
 * 2. Default: `~/.claude/cstk/bridge.db`
 * Ref: research.md Decision 2.
 */
export function resolveBridgeDbPath(): string {
  const fromEnv = process.env['CSTK_BRIDGE_DB'];
  if (fromEnv && fromEnv.trim() !== '') {
    return resolve(fromEnv.trim());
  }
  return resolve(homedir(), '.claude', 'cstk', 'bridge.db');
}

/**
 * DDL da tabela `interventions` (data-model.md §"Entity: Intervention") + os
 * dois indices propostos. `IF NOT EXISTS` torna a aplicacao idempotente —
 * chamada em toda abertura, sem custo relevante num schema ja aplicado.
 */
const DDL = `
CREATE TABLE IF NOT EXISTS interventions (
  question_id    TEXT NOT NULL PRIMARY KEY,
  project_path   TEXT NOT NULL,
  project        TEXT NOT NULL,
  short_name     TEXT,
  execution_kind TEXT NOT NULL,
  kind           TEXT NOT NULL CHECK (kind IN ('choice', 'confirm', 'text')),
  question       TEXT NOT NULL,
  options_json   TEXT,
  default_value  TEXT NOT NULL,
  resolution     TEXT CHECK (resolution IN ('answered', 'declined')),
  applied_value  TEXT,
  untrusted_text TEXT,
  expires_at     TEXT NOT NULL,
  created_at     TEXT NOT NULL,
  resolved_at    TEXT
);

CREATE INDEX IF NOT EXISTS idx_interventions_open
  ON interventions(expires_at)
  WHERE resolution IS NULL;

CREATE INDEX IF NOT EXISTS idx_interventions_created
  ON interventions(created_at DESC);
`;

/**
 * Aplica permissoes restritivas best-effort (diretorio `700` / arquivo
 * `600`) — mesmo idioma de `recall_normalize_db_perms`
 * (`cli/lib/recall.sh:750-758`, verificado): NUNCA bloqueia o caller. Ausencia
 * de suporte a `chmod` no SO, permissao negada, ou corrida com outro processo
 * apenas degradam para no-op silencioso.
 */
function normalizePermsBestEffort(dbPath: string): void {
  try {
    chmodSync(dirname(dbPath), 0o700);
  } catch {
    /* best-effort — nunca bloqueia o caller (contracts §11.4) */
  }
  try {
    if (existsSync(dbPath)) {
      chmodSync(dbPath, 0o600);
    }
  } catch {
    /* best-effort — nunca bloqueia o caller (contracts §11.4) */
  }
}

/**
 * Abre `bridge.db` numa conexao READ-WRITE nova e DISTINTA da conexao
 * readonly do corpus (`db/open.ts`, INTOCADO por esta feature) — nenhuma
 * query desta conexao passa pelo handle do corpus, e vice-versa. Cria o
 * diretorio pai se ausente, aplica o DDL (idempotente) e normaliza
 * permissoes. Quem chama e responsavel por `db.close()` (mesma convencao de
 * `openDb`/`db/open.ts`, usada em todas as rotas de leitura).
 *
 * Ao contrario de `openDb` (que retorna `OpenResult` com motivos de
 * degradacao — o corpus pode estar ausente/corrompido/desatualizado),
 * `openBridgeDb` nao tem estado "degradado": o arquivo e criado sob demanda
 * pelo proprio processo que o possui. Erros de abertura (ex.: diretorio
 * sem permissao de escrita, ou `quick_check` acusando corrupcao) propagam
 * como excecao — o mapeamento para `meta.degraded=true` na resposta HTTP e
 * responsabilidade das rotas (`routes/bridge.ts`, tarefa 3.1, decisao
 * 1.1.2).
 *
 * Achado 6.3/6.4 da convergencia (`contracts/panel-bridge-api.md:102`;
 * `plan.md:126`): os passos pos-`new Database()` (pragmas, `PRAGMA
 * quick_check`, DDL, normalizacao de permissoes) rodam dentro de um
 * try/catch que fecha o handle antes de repropagar. Sem isso, uma falha
 * nesses passos deixava a atribuicao `db = openBridgeDb()` do chamador
 * nunca completar — o `finally { db?.close(); }` das rotas encontrava
 * `null` e virava no-op, vazando o handle SQLite. `PRAGMA quick_check`
 * (nomeado pelo contrato como gatilho de degradacao, junto com
 * `packages/shared-types/src/envelope.ts:65`) detecta corrupcao que o DDL
 * sozinho (`CREATE TABLE IF NOT EXISTS`, que nao toca paginas de dados ja
 * existentes) pode nao acusar.
 */
export function openBridgeDb(dbPath: string = resolveBridgeDbPath()): Database.Database {
  const dir = dirname(dbPath);
  mkdirSync(dir, { recursive: true, mode: 0o700 });

  const db = new Database(dbPath);
  try {
    db.pragma('journal_mode = WAL');
    db.pragma('foreign_keys = ON');

    const qcRows = db.pragma('quick_check') as Array<{ quick_check: string }>;
    const qcResult = qcRows[0]?.quick_check ?? 'error';
    if (qcResult !== 'ok') {
      throw new Error(`bridge.db quick_check falhou: ${qcResult}`);
    }

    db.exec(DDL);
    normalizePermsBestEffort(dbPath);
  } catch (err) {
    db.close();
    throw err;
  }

  return db;
}
