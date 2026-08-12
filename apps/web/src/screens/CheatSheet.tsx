/**
 * CheatSheet — referência rápida dos comandos do cstk + passo-a-passo de
 * setup (completo: MCP + state.db | básico: Bash + state.json).
 *
 * Conteúdo ESTÁTICO (não consome API): derivado do help real do
 * `cstk v7.3.1` (2026-08-12), do README e do CHANGELOG do repo
 * JotJunior/cstk (v7.0.0 = empacotamento como plugin nativo do Claude
 * Code + remoção da skill initialize-docs; profiles conferidos em
 * scripts/profiles.txt.in). Ao mudar a superfície de comandos do CLI,
 * atualizar este texto junto (fonte de verdade: `cstk help [CMD]` /
 * `cstk <cmd> --help`).
 *
 * Renderizado via MarkdownView (renderer seguro do painel: GFM, sem HTML
 * bruto, allowlist de esquemas de URL) — mesmo caminho das docs SDD.
 */
import { MarkdownView } from '@/components/MarkdownView.js';

const CHEATSHEET_MD = `
# cstk cheat sheet (v7.3.1)

Comandos do CLI e os dois caminhos de setup para rodar as pipelines
autônomas 00c: **completo** (servidor MCP + state.db) ou **básico**
(Bash + state.json). Desde a v7.0.0 há **duas formas oficiais** de
instalar o catálogo: o CLI clássico e o plugin nativo do Claude Code.
Passo-a-passo mais mastigado por pergunta: veja o [FAQ](#/faq).

## Instalação e manutenção

O toolkit vive em duas metades: o **catálogo** (skills/commands/agents em
\`~/.claude/\`) e o **runtime** (binário + \`cli/lib\` em \`~/.local/\`).
Cada metade tem seu comando de atualização.

| Comando | O que faz |
| --- | --- |
| \`curl -fsSL .../install.sh \\| sh\` | Instalação inicial (uma vez por máquina), da release mais recente |
| \`cstk update\` | Atualiza o **catálogo**, preservando edits locais (\`--force\` sobrescreve, \`--keep\` silencia, \`--prune\` remove órfãs) |
| \`cstk self-update\` | Atualiza o **binário + runtime** — \`update\` NÃO faz isso (\`--check\` só consulta) |
| \`cstk install --from "file://...tar.gz"\` | Instala o catálogo de um tarball local (fluxo dev) |
| \`cstk setup\` | Wizard guiado das 4 áreas num projeto (hooks, backend de estado, MCP, telemetria); \`--dry-run\` / \`--yes\` |
| \`cstk doctor\` | Detecta drift entre manifest e disco — rode **antes** de editar skill. Com o plugin habilitado, ganha a seção **Distribution Paths** (clássico vs plugin, por hash) |
| \`cstk doctor --deps\` | Diagnóstico read-only: sqlite3/jq, backend efetivo e motivo |
| \`cstk list\` | Lista skills instaladas (cheque \`grep -- -dev\` após tarball dev); \`--available --from URL\` lista o catálogo de uma release |

> **GOTCHA**: \`install\`/\`update\` tocam só o catálogo. Um fix em
> \`cli/lib/*.sh\` exige \`cstk self-update\` — senão o código velho continua
> rodando ("o fix funciona no repo mas não na sessão").

## Plugin nativo do Claude Code (desde a v7.0.0)

Segunda forma oficial de entrega do catálogo — sem binário, sem \`curl\`:

\`\`\`text
/plugin marketplace add JotJunior/cstk
/plugin install cstk@cstk
# opcional, projetos Go: /plugin install cstk-language-go@cstk
\`\`\`

Habilitado o plugin, uma sessão nova já ativa skills, os 6 commands
\`/agente-00c*\`/\`/feature-00c*\` e os 3 guard hooks **sem**
\`cstk hooks install\` por projeto. O hook opt-in de consumo avulso
(\`posttooluse-loose-usage\`) fica deliberadamente **fora** do plugin.

| | CLI clássico | Plugin |
| --- | --- | --- |
| Traz o binário \`cstk\` (\`recall\`, \`usage\`, \`mcp\`, \`session\`, \`serve\`) | Sim | **Não** — para esses, instale também pelo one-liner |
| Guard hooks no projeto | \`cstk hooks install\` | Automáticos no boot da sessão |
| Atualização | \`cstk update\` | \`claude plugin marketplace update\` + \`claude plugin update cstk\` + reiniciar a sessão |

Os dois caminhos convivem: \`cstk hooks install\`/\`cstk setup\` detectam o
plugin e **não** registram a guarda em dobro ("plugin vence"); registro
clássico remanescente gera prompt de remoção (\`--remove-classic\` para
CI/script, backup em \`settings.json.bak-pre-dedup\`).

## Estado transacional 00c

Todos os leitores do runtime e os hooks do harness funcionam contra os
dois backends (\`state.json\` e \`state.db\`) — nenhum degrada mudo sob
SQLite.

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
(sem eles, \`/agente-00c\` faz o bootstrap). O briefing canônico vive em
\`docs/briefing.md\` — o caminho legado
\`docs/01-briefing-discovery/briefing.md\` é aceito só como fallback. A
skill \`initialize-docs\` foi **removida na v7.0.0**: o layout SDD
(\`docs/briefing.md\` + \`docs/constitution.md\` + \`docs/specs/\`) é criado
pelas próprias skills, sem scaffold prévio.

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
| \`cstk recall "<query>"\` | Busca full-text na knowledge.db (\`--project\`, \`--type decision/block/retro/skill/memory/suggestion\`, \`--limit\`) |
| \`cstk recall --context "<termos>"\` | Bloco markdown pronto para injetar em prompt (\`--exclude-feature\` evita eco) |
| \`cstk recall --list-memories [--project P]\` | Lista as auto-memórias indexadas |
| \`cstk recall --reindex --states-root ~/Projects\` | Reconstrói o índice (states-root explícito é bem mais rápido) |
| \`cstk serve [--docker] [--update]\` | Este painel, em \`http://127.0.0.1:5173\` |
| \`cstk hooks install [--project-path P]\` | Provisiona os 3 hooks: bash-guard fail-closed + tool-call-tick + agent-usage (pulado se o plugin já os provê) |
| \`cstk hooks install --with-loose-usage\` | Também provisiona o hook opt-in de consumo avulso (default DESLIGADO; nunca vem pelo plugin) |
| \`cstk statusline install\` | Captura de uso do plano via \`statusLine.command\` no \`~/.claude/settings.json\` (preserva customização prévia em \`CSTK_STATUSLINE_INNER_COMMAND\`); \`status\` inspeciona |
| \`cstk show-tip\` | Dica aleatória (ou por skill/fase) sobre o toolkit |

> **GOTCHA**: cópias de hooks são snapshots — \`cstk update\` NÃO reconcilia
> os hooks já copiados em \`<projeto>/.claude/hooks/\`. Cópia stale roda
> regras antigas (sintoma real: \`tool_calls=0\` em todas as ondas sob
> state.db). O diagnóstico dos commands 00c acusa hook \`stale\`;
> remediação: rodar \`cstk hooks install\` de novo em cada projeto (ou
> migrar para o plugin, que ativa os hooks direto do catálogo).

## Consumo avulso (\`cstk usage\`)

Tokens/custo das sessões interativas comuns do Claude Code — invisíveis
para o \`cstk recall\`, que só cobre ondas de orquestrador. Captura via
hook opt-in (\`--with-loose-usage\`) em sidecar local; índice na
\`knowledge.db\` (tabela \`loose_usage\`; schema atual v14). Campo sem
medição imprime \`nao medido\` (\`null\` no \`--json\`) — nunca \`0\` fabricado.

| Comando | O que faz |
| --- | --- |
| \`cstk usage [--project P] [--since ISO] [--limit N] [--json]\` | Lista consumo avulso: uma seção por projeto, uma linha por modelo (tokens, custo, participação) |
| \`cstk usage compare [--project P] [--since ISO] [--json]\` | Mix de modelos e custo blended, avulso vs pipeline lado a lado |
| \`cstk usage prune [--dry-run] [--older-than-days N]\` | Poda segmentos fechados do sidecar + linhas do índice acima do TTL (default 90 dias; segmentos abertos nunca são elegíveis) |

> O hook captura com throttle (default 300s) e detecta execução 00c ativa
> para não contar duas vezes o consumo que já entra pelas ondas.

---

## Passo a passo — setup COMPLETO (MCP + state.db)

> **Atalho**: depois do passo 2, \`cstk setup\` no projeto-alvo cobre os
> passos 3–5 de uma vez (wizard interativo; \`--yes\` aplica os defaults).

1. **Toolkit + sanidade**

   \`\`\`sh
   curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
   cstk doctor && cstk doctor --deps
   \`\`\`

   O one-liner instala só o **runtime** (binário + \`cli/lib\`) — as
   skills/commands/agents vêm no próximo passo.

2. **Catálogo: skills + commands + agents**

   \`\`\`sh
   cstk install
   \`\`\`

   Sem este passo os slash commands não existem na sessão. O profile
   default \`sdd\` traz as skills da pipeline (briefing → review-features),
   os gates de qualidade (validate-documentation, validate-docs-rendered,
   owasp-security, converge), \`agente-00c-runtime\` e \`model-selector\`;
   commands e agents (\`/agente-00c\`, \`/feature-00c\`, subagentes) são
   instalados sempre, sem filtro de profile. \`cstk install --profile all\`
   instala também as complementares.

   *Alternativa sem binário*: o plugin nativo (seção acima) ativa
   skills + commands + guard hooks — mas não os comandos \`cstk\` deste
   cheat sheet.

3. **Backend SQLite global** — execuções novas nascem em \`state.db\`:

   \`\`\`sh
   cstk state enable-sqlite
   \`\`\`

4. **No projeto-alvo: hooks + MCP**

   \`\`\`sh
   cd ~/meu-projeto
   cstk hooks install
   cstk mcp install
   \`\`\`

5. **Telemetria de custo real (opcional)** — sem API key, tudo local:

   \`\`\`sh
   export CLAUDE_CODE_ENABLE_TELEMETRY=1
   export OTEL_METRICS_EXPORTER=prometheus
   \`\`\`

   Atenção: a porta 9464 aceita um único processo do Claude Code.

6. **Reiniciar a sessão do Claude Code** — o \`.mcp.json\` só carrega no boot.

7. **Rodar a pipeline** (no Claude Code):

   \`\`\`text
   /feature-00c "descrição da feature" meu-short-name
   \`\`\`

   O command pai sobe o container MCP, injeta o token de capacidade no
   orquestrador e agenda as ondas. Bloqueio humano pausa; responda com
   \`/feature-00c-resume meu-short-name --resposta-bloqueio "..."\`.

8. **Higiene eventual**

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
\`cstk mcp install\` + reiniciar a sessão (ou \`cstk setup\` de uma vez).
Execuções já iniciadas em \`state.json\` continuam nele; para converter uma
específica: \`cstk state migrate --state-dir <dir>\`.
`;

export function CheatSheet() {
  return (
    <div className="cheatsheet-screen">
      <MarkdownView content={CHEATSHEET_MD} />
    </div>
  );
}
