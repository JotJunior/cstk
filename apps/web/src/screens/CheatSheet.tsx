/**
 * CheatSheet — referência rápida dos comandos do cstk + passo-a-passo de
 * setup (completo: MCP + state.db | básico: Bash + state.json).
 *
 * Conteúdo ESTÁTICO (não consome API): derivado do help real do
 * `cstk v6.2.0` (2026-08-02). Ao mudar a superfície de comandos do CLI,
 * atualizar este texto junto (fonte de verdade: `cstk help [CMD]` e
 * docs/specs/cstk-cli/contracts/cli-commands.md no repo JotJunior/cstk).
 *
 * Renderizado via MarkdownView (renderer seguro do painel: GFM, sem HTML
 * bruto, allowlist de esquemas de URL) — mesmo caminho das docs SDD.
 */
import { MarkdownView } from '@/components/MarkdownView.js';

const CHEATSHEET_MD = `
# cstk cheat sheet (v6.2.0)

Comandos do CLI e os dois caminhos de setup para rodar as pipelines
autônomas 00c: **completo** (servidor MCP + state.db) ou **básico**
(Bash + state.json).

## Instalação e manutenção

O toolkit vive em duas metades: o **catálogo** (skills/commands/agents em
\`~/.claude/\`) e o **runtime** (binário + \`cli/lib\` em \`~/.local/\`).
Cada metade tem seu comando de atualização.

| Comando | O que faz |
| --- | --- |
| \`curl -fsSL .../install.sh \\| sh\` | Instalação inicial (uma vez por máquina), da release mais recente |
| \`cstk update\` | Atualiza o **catálogo**, preservando edits locais |
| \`cstk self-update\` | Atualiza o **binário + runtime** — \`update\` NÃO faz isso |
| \`cstk install --from "file://...tar.gz"\` | Instala o catálogo de um tarball local (fluxo dev) |
| \`cstk doctor\` | Detecta drift entre manifest e disco — rode **antes** de editar skill |
| \`cstk doctor --deps\` | Diagnóstico read-only: sqlite3/jq, backend efetivo e motivo |
| \`cstk list\` | Lista skills instaladas (cheque \`grep -- -dev\` após tarball dev) |

> **GOTCHA**: \`install\`/\`update\` tocam só o catálogo. Um fix em
> \`cli/lib/*.sh\` exige \`cstk self-update\` — senão o código velho continua
> rodando ("o fix funciona no repo mas não na sessão").

## Estado transacional 00c

| Comando | O que faz |
| --- | --- |
| \`cstk state enable-sqlite\` | Ativa \`state_backend=sqlite\` global (\`~/.claude/cstk/config\`). Vale para execuções **novas**; recusa (exit 3) se sqlite3 < 3.45.1 |
| \`cstk state migrate --state-dir DIR\` | Migra o \`state.json\` de um projeto para \`state.db\`. Explícita, nunca automática; recusa execução \`em_andamento\` |

> A config global nunca força migração: projeto que já tem \`state.json\`
> continua nele — \`enable-sqlite\` só influencia o init de state-dir limpo.

## Servidor MCP de estado

As primitivas de mutação do estado viram tools de contrato (\`open_wave\`,
\`record_decision\`, \`record_skill\`, \`record_task\`, \`register_human_block\`,
\`close_wave\` atômico, \`get_status\`). Um container por execução; roteamento
por token de capacidade, fail-closed.

| Comando | O que faz |
| --- | --- |
| \`cstk mcp install [--project-path P]\` | Registra \`mcpServers.cstk-state\` no \`.mcp.json\` do projeto (idempotente; recusa \`$HOME\`) |
| \`cstk mcp status [--state-dir D] [--live]\` | \`active / stopped / unavailable\`; \`--live\` roda health check real sem reiniciar |
| \`cstk mcp start --state-dir D\` | Sobe o container (invocado pelo command pai). Docker ausente/falho => \`mode=bash-fallback\`, exit 3 não-fatal |
| \`cstk mcp stop --state-dir D\` | Para o container (grace 5s). Idempotente |
| \`cstk mcp gc [--dry-run]\` | Remove containers órfãos de execuções terminais (fail-safe por label) |

Env útil: \`MCP_MAX_TOOL_CALLS=N\` — teto de chamadas por sessão (SEC-L1,
default 2000; exceder rejeita com \`TOOL_CALL_LIMIT_EXCEEDED\`, o servidor
permanece de pé).

## Pipelines autônomas (slash commands no Claude Code)

Pré-requisito do \`/feature-00c\`: briefing + constitution ratificados
(sem eles, \`/agente-00c\` faz o bootstrap).

| Comando | O que faz |
| --- | --- |
| \`cstk 00c <path>\` | Bootstrap interativo de um projeto-alvo novo |
| \`/agente-00c\` | Pipeline SDD completa: briefing → constitution → specify → ... → review-features |
| \`/feature-00c "<desc>" <short>\` | Pipeline SDD de UMA feature: specify → clarify → plan → checklist → create-tasks → execute-task → review-task |
| \`/feature-00c-resume <short>\` | Retoma após pausa; \`--resposta-bloqueio "..."\` responde bloqueio humano |
| \`/agente-00c-abort\` · \`/feature-00c-abort\` | Aborto limpo com relatório parcial. Idempotentes |

## Sessões, memória, painel, hooks

| Comando | O que faz |
| --- | --- |
| \`cstk session start/list/pr/end <nome>\` | Worktree + branch isolada por feature (multi-sessão sem colisão de state) |
| \`cstk recall "<query>"\` | Busca full-text na knowledge.db (\`--project\`, \`--type decision/block/retro/skill/memory\`, \`--limit\`) |
| \`cstk recall --context "<termos>"\` | Bloco markdown pronto para injetar em prompt (\`--exclude-feature\` evita eco) |
| \`cstk recall --reindex --states-root ~/Projects\` | Reconstrói o índice (states-root explícito é bem mais rápido) |
| \`cstk serve [--docker] [--update]\` | Este painel, em \`http://127.0.0.1:5173\` |
| \`cstk hooks install [--project-path P]\` | Provisiona os 3 hooks: bash-guard fail-closed + tool-call-tick + agent-usage |
| \`cstk show-tip\` | Dica aleatória (ou por skill/fase) sobre o toolkit |

---

## Passo a passo — setup COMPLETO (MCP + state.db)

1. **Toolkit + sanidade**

   \`\`\`sh
   curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
   cstk doctor && cstk doctor --deps
   \`\`\`

2. **Backend SQLite global** — execuções novas nascem em \`state.db\`:

   \`\`\`sh
   cstk state enable-sqlite
   \`\`\`

3. **No projeto-alvo: hooks + MCP**

   \`\`\`sh
   cd ~/meu-projeto
   cstk hooks install
   cstk mcp install
   \`\`\`

4. **Telemetria de custo real (opcional)** — sem API key, tudo local:

   \`\`\`sh
   export CLAUDE_CODE_ENABLE_TELEMETRY=1
   export OTEL_METRICS_EXPORTER=prometheus
   \`\`\`

   Atenção: a porta 9464 aceita um único processo do Claude Code.

5. **Reiniciar a sessão do Claude Code** — o \`.mcp.json\` só carrega no boot.

6. **Rodar a pipeline** (no Claude Code):

   \`\`\`text
   /feature-00c "descrição da feature" meu-short-name
   \`\`\`

   O command pai sobe o container MCP, injeta o token de capacidade no
   orquestrador e agenda as ondas. Bloqueio humano pausa; responda com
   \`/feature-00c-resume meu-short-name --resposta-bloqueio "..."\`.

7. **Higiene eventual**

   \`\`\`sh
   cstk mcp gc --dry-run
   cstk recall "tema" --project meu-projeto
   \`\`\`

Docker indisponível em qualquer etapa? Nada quebra: o start grava
\`mode=bash-fallback\` e a pipeline segue 100% pelo caminho Bash (SC-004).

## Passo a passo — setup BÁSICO (sem MCP, state.json)

1. **Toolkit**

   \`\`\`sh
   curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
   cstk doctor
   \`\`\`

2. **Hooks no projeto (recomendado mesmo no básico)**

   \`\`\`sh
   cd ~/meu-projeto
   cstk hooks install
   \`\`\`

3. **Rodar direto** (no Claude Code):

   \`\`\`text
   /feature-00c "descrição da feature" meu-short-name
   \`\`\`

   Sem \`enable-sqlite\` o backend é \`state.json\` (default seguro); sem
   \`mcp install\` não há container — tudo via Bash, comportamento clássico.

**Upgrade do básico para o completo depois**: \`cstk state enable-sqlite\` +
\`cstk mcp install\` + reiniciar a sessão. Execuções já iniciadas em
\`state.json\` continuam nele; para converter uma específica:
\`cstk state migrate --state-dir <dir>\`.
`;

export function CheatSheet() {
  return (
    <div className="cheatsheet-screen">
      <MarkdownView content={CHEATSHEET_MD} />
    </div>
  );
}
