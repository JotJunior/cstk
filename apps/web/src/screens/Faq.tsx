/**
 * Faq — perguntas frequentes com respostas passo-a-passo, mais fáceis de
 * achar do que varrer as listas de comandos do Cheat Sheet.
 *
 * Conteúdo ESTÁTICO (não consome API). Fontes de verdade (2026-08-12):
 *  - `cstk v7.3.1`: `cstk help`, `cstk <cmd> --help` (setup, mcp, hooks, state)
 *  - README do repo JotJunior/cstk (seções Instalação, plugin nativo e
 *    "ative a captura de custo e tokens")
 *  - docs/cstk-serve.pt-BR.md do repo JotJunior/cstk
 *  - Docs oficiais do Claude Code sobre plugins/marketplaces:
 *    https://code.claude.com/docs/en/discover-plugins.md e
 *    https://code.claude.com/docs/en/desktop.md
 * Ao mudar a superfície de comandos do CLI, atualizar este texto junto.
 *
 * Respostas renderizadas via MarkdownView (renderer seguro do painel: GFM,
 * sem HTML bruto, allowlist de esquemas de URL) — mesmo caminho das docs SDD.
 */
import { useMemo, useState } from 'react';
import { Icon } from '@/components/Icon.js';
import { MarkdownView } from '@/components/MarkdownView.js';

interface FaqItem {
  id: string;
  category: string;
  question: string;
  /** Resposta em markdown (GFM) — renderizada pelo MarkdownView. */
  answer: string;
}

const FAQ_ITEMS: FaqItem[] = [
  {
    id: 'install-linux-mac',
    category: 'Instalação',
    question: 'Como instalo no terminal do Linux e do macOS?',
    answer: `
1. **Instale o runtime** (binário \`cstk\` + libs) com o one-liner oficial — sem sudo:

   \`\`\`sh
   curl -fsSL https://github.com/JotJunior/cstk/releases/latest/download/install.sh | sh
   \`\`\`

   O instalador valida SHA-256, coloca o binário em \`~/.local/bin/\` e avisa
   se esse diretório não estiver no seu \`PATH\`.

2. **Instale o catálogo** (skills + commands + agents) — sem este passo os
   slash commands não existem na sessão:

   \`\`\`sh
   cstk --version   # confirma a instalação
   cstk install     # profile default 'sdd'
   \`\`\`

   Quer tudo? \`cstk install --profile all\`.

3. **Sanidade**:

   \`\`\`sh
   cstk doctor
   \`\`\`
`,
  },
  {
    id: 'install-windows',
    category: 'Instalação',
    question: 'Como instalo no terminal do Windows?',
    answer: `
Não existe instalador nativo para Windows: o \`cstk\` é um CLI POSIX shell
(o instalador depende de \`curl\`, \`tar\`, \`sha256sum\`/\`shasum\` etc.).
O caminho é o **WSL** (Windows Subsystem for Linux):

1. Instale o WSL com uma distribuição Linux (ex.: Ubuntu): \`wsl --install\`
   num PowerShell como administrador.
2. Abra o terminal do WSL e siga o passo-a-passo de **Linux** (pergunta acima).
3. Use o Claude Code **dentro do WSL** nos seus projetos.

> **Atenção**: segundo a documentação oficial do Claude Code, plugins não
> funcionam em sessões WSL — no Windows, use o caminho clássico
> (instalador + \`cstk install\`) em vez do plugin.
`,
  },
  {
    id: 'install-plugin-terminal',
    category: 'Plugin do Claude Code',
    question: 'Como instalo o plugin no terminal (Claude Code CLI)?',
    answer: `
Dentro de uma sessão do Claude Code:

\`\`\`text
/plugin marketplace add JotJunior/cstk
/plugin install cstk@cstk
\`\`\`

Projetos Go (opcional): \`/plugin install cstk-language-go@cstk\`.

Fora da sessão (não-interativo, direto no shell):

\`\`\`sh
claude plugin install cstk@cstk --scope user
\`\`\`

Nesse caso o plugin só carrega na próxima sessão — ou rode
\`/reload-plugins\` na sessão aberta.

**O que o plugin ativa**: skills, os 6 commands \`/agente-00c*\` /
\`/feature-00c*\` e os 3 guard hooks, automaticamente, sem
\`cstk hooks install\` por projeto.

**O que o plugin NÃO traz**: o binário \`cstk\` (\`recall\`, \`usage\`,
\`mcp\`, \`session\`, \`serve\`) — para esses comandos, instale também pelo
one-liner clássico (pergunta de instalação acima). Os dois caminhos
convivem: \`cstk doctor\` detecta o plugin e evita registrar hooks em dobro.
`,
  },
  {
    id: 'install-plugin-desktop',
    category: 'Plugin do Claude Code',
    question: 'Como instalo o plugin no Claude Code Desktop?',
    answer: `
No app desktop (Mac/Windows) há uma UI dedicada de plugins:

1. Se o marketplace ainda não foi adicionado, rode numa sessão:
   \`/plugin marketplace add JotJunior/cstk\` — o browser de plugins lista
   os marketplaces já configurados.
2. Clique no botão **+** ao lado da caixa de prompt.
3. Selecione **Plugins** no submenu e depois **Add plugin**.
4. No browser de plugins, escolha \`cstk\` e o escopo de instalação.

Para habilitar, desabilitar ou desinstalar depois: mesmo submenu →
**Manage plugins**.

> **Limitações documentadas**: o browser de plugins não está disponível em
> cloud sessions, e plugins não funcionam em sessões WSL.
`,
  },
  {
    id: 'panel-activate',
    category: 'Painel',
    question: 'Como ativo o painel?',
    answer: `
\`\`\`sh
cstk serve
\`\`\`

Na primeira execução o comando baixa a release mais recente do
\`cstk-panel\`, instala em \`~/.local/share/cstk/panel\` e sobe API + SPA na
mesma porta. Abra **http://127.0.0.1:5173** no navegador.

Variações úteis:

| Comando | Quando usar |
| --- | --- |
| \`cstk serve --update\` | Atualiza o painel se houver release nova, depois inicia |
| \`cstk serve --port 8080\` | Muda a porta (default 5173) |
| \`cstk serve --docker\` | Roda num container local — dispensa \`npm\`/\`node\` no host (requer Docker com daemon rodando) |

Dependências no modo nativo: \`node\` + \`npm\` (além de \`curl\`).
`,
  },
  {
    id: 'tokens-cost',
    category: 'Tokens e custo',
    question: 'Como habilito a captura dos tokens e custo?',
    answer: `
Duas variáveis de ambiente — sem API key, sem Admin key; funciona em plano
de assinatura:

\`\`\`sh
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=prometheus
\`\`\`

1. Coloque as duas linhas no seu \`~/.zshrc\` / \`~/.bashrc\` para não perder
   ondas por esquecimento.
2. Reinicie o terminal (ou \`source\` no rc) antes de abrir o Claude Code.

Com elas, cada onda do orquestrador registra o consumo **real** (custo e
tokens, separando \`main\` de \`subagent\`) e este painel mostra o gasto por
onda. Sem elas tudo é no-op e o campo fica \`null\` — ausente, nunca zero
fabricado. Nada sai da máquina (exporter em \`127.0.0.1:9464\`).

> **GOTCHA**: a porta fixa 9464 aceita **um único** processo do Claude Code
> — os demais não medem nada, em silêncio. Para vários processos ao mesmo
> tempo, use o launcher de porta por processo documentado no README do cstk
> (seção "Custo real por onda").
`,
  },
  {
    id: 'loose-usage',
    category: 'Tokens e custo',
    question: 'Como capturo o consumo das sessões comuns (fora das pipelines)?',
    answer: `
O consumo avulso (sessões interativas normais do Claude Code) é capturado
por um hook **opt-in**, que não vem no plugin nem no provisionamento padrão:

\`\`\`sh
cd ~/meu-projeto
cstk hooks install --with-loose-usage
\`\`\`

Consulta depois:

\`\`\`sh
cstk usage                # por projeto, uma linha por modelo
cstk usage compare        # avulso vs pipeline lado a lado
cstk usage prune --dry-run  # poda dados acima do TTL (default 90 dias)
\`\`\`

O hook usa throttle e detecta execução 00c ativa para não contar duas vezes
o que já entra pelas ondas.
`,
  },
  {
    id: 'mcp-enable',
    category: 'MCP e estado',
    question: 'Como habilito o MCP?',
    answer: `
1. **No projeto-alvo**, registre o servidor de estado no \`.mcp.json\`:

   \`\`\`sh
   cd ~/meu-projeto
   cstk mcp install
   \`\`\`

   Idempotente (rodar de novo não duplica); recusa rodar no \`$HOME\`.

2. **Reinicie a sessão do Claude Code** — o \`.mcp.json\` só carrega no boot.

3. **Opcional, recomendado junto**: backend SQLite para execuções novas:

   \`\`\`sh
   cstk state enable-sqlite
   \`\`\`

Verificação: \`cstk mcp status\` (\`--live\` roda um health check real).
O container é iniciado pelo command pai a cada execução — você não roda
\`cstk mcp start\` manualmente. Docker ausente ou falho **não quebra nada**:
o start grava \`mode=bash-fallback\` e a pipeline segue 100% pelo caminho Bash.
`,
  },
  {
    id: 'setup-wizard',
    category: 'MCP e estado',
    question: 'Existe um jeito rápido de configurar um projeto inteiro?',
    answer: `
Sim — o wizard guiado cobre as 4 áreas recomendadas (hooks, backend de
estado, MCP e telemetria) de uma vez, na raiz de um repositório git:

\`\`\`sh
cd ~/meu-projeto
cstk setup             # interativo, pergunta área a área
cstk setup --dry-run   # preview: mostra o que seria aplicado, sem escrever
cstk setup --yes       # não-interativo: aplica o default recomendado
\`\`\`
`,
  },
  {
    id: 'update-toolkit',
    category: 'Manutenção',
    question: 'Como atualizo o toolkit (e o painel)?',
    answer: `
Cada metade tem seu comando — este é o gotcha mais comum:

| O que atualizar | Comando |
| --- | --- |
| Catálogo (skills/commands/agents) | \`cstk update\` |
| Binário + runtime (\`cli/lib\`) | \`cstk self-update\` — \`update\` **não** faz isso |
| Painel web | \`cstk serve --update\` |
| Plugin do Claude Code | \`claude plugin marketplace update\` + \`claude plugin update cstk\`, e reinicie a sessão |

> **GOTCHA**: cópias de hooks em \`<projeto>/.claude/hooks/\` são snapshots —
> \`cstk update\` não as reconcilia. Após atualizar, rode \`cstk hooks install\`
> de novo em cada projeto que usa o provisionamento clássico.
`,
  },
];

/** Ordem de exibição das categorias (derivada da ordem dos itens). */
const CATEGORIES = [...new Set(FAQ_ITEMS.map((i) => i.category))];

/** Normaliza para busca: minúsculas e sem acentos (áé → ae). */
function normalize(s: string): string {
  return s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
}

export function Faq() {
  const [query, setQuery] = useState('');
  const [openIds, setOpenIds] = useState<Set<string>>(new Set());

  const q = normalize(query.trim());
  const filtering = q.length > 0;

  const visible = useMemo(
    () =>
      filtering
        ? FAQ_ITEMS.filter((item) =>
            normalize(`${item.category} ${item.question} ${item.answer}`).includes(q),
          )
        : FAQ_ITEMS,
    [filtering, q],
  );

  const toggle = (id: string) =>
    setOpenIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* Campo de filtro */}
      <div className="card">
        <div className="card-body">
          <div
            style={{
              display: 'flex', alignItems: 'center', gap: 10,
              background: 'var(--bg-2)', border: '1px solid var(--border)',
              borderRadius: 'var(--r-md)', padding: '10px 14px',
            }}
          >
            <Icon name="search" size={16} style={{ color: 'var(--text-2)', flexShrink: 0 }} />
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Filtrar perguntas: instalar, plugin, painel, tokens, MCP…"
              aria-label="Filtrar perguntas do FAQ"
              style={{
                background: 'transparent', border: 'none', outline: 'none',
                color: 'var(--text-0)', fontSize: 14, flex: 1,
              }}
            />
            {query && (
              <button
                onClick={() => setQuery('')}
                aria-label="Limpar filtro"
                style={{
                  background: 'transparent', border: 'none',
                  color: 'var(--text-3)', cursor: 'pointer', padding: 4,
                }}
              >
                <Icon name="x" size={14} />
              </button>
            )}
          </div>
          {filtering && (
            <div
              style={{
                marginTop: 8, fontSize: 11.5, color: 'var(--text-2)',
                fontFamily: 'var(--font-mono)',
              }}
            >
              {visible.length} pergunta{visible.length !== 1 ? 's' : ''} para "{query.trim()}"
            </div>
          )}
        </div>
      </div>

      {/* Perguntas agrupadas por categoria */}
      {CATEGORIES.map((category) => {
        const items = visible.filter((i) => i.category === category);
        if (items.length === 0) return null;
        return (
          <div key={category} className="card">
            <div className="card-head">
              <h3>{category}</h3>
            </div>
            <div>
              {items.map((item) => {
                // Filtrando, a resposta que casou já abre expandida.
                const open = filtering || openIds.has(item.id);
                return (
                  <div key={item.id} style={{ borderTop: '1px solid var(--border)' }}>
                    <button
                      onClick={() => toggle(item.id)}
                      aria-expanded={open}
                      aria-controls={`faq-answer-${item.id}`}
                      style={{
                        display: 'flex', alignItems: 'center', gap: 10,
                        width: '100%', textAlign: 'left', cursor: 'pointer',
                        background: 'transparent', border: 'none',
                        padding: '12px 18px', color: 'var(--text-0)',
                        fontSize: 13.5, fontWeight: 600,
                      }}
                    >
                      <Icon
                        name={open ? 'chevron-down' : 'chevron-right'}
                        size={14}
                        style={{ color: 'var(--text-2)', flexShrink: 0 }}
                      />
                      <span>{item.question}</span>
                    </button>
                    {open && (
                      <div
                        id={`faq-answer-${item.id}`}
                        style={{ padding: '0 18px 14px 42px' }}
                      >
                        <MarkdownView content={item.answer} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}

      {filtering && visible.length === 0 && (
        <div className="card">
          <div className="card-body" style={{ color: 'var(--text-2)', fontSize: 13 }}>
            Nenhuma pergunta casa com "{query.trim()}". Tente outro termo ou
            consulte o Cheat Sheet para a lista completa de comandos.
          </div>
        </div>
      )}
    </div>
  );
}
