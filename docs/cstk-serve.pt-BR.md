[English](./cstk-serve.md) · **Português (pt-BR)**

# Painel Web (`cstk serve`)

Inicia a interface web do cstk panel localmente. Na primeira execução, baixa
automaticamente a release mais recente de
[JotJunior/cstk-panel](https://github.com/JotJunior/cstk-panel) e instala em
`~/.local/share/cstk/panel`. Execuções subsequentes reutilizam a instalação em
cache.

O `cstk serve` compila os workspaces (`npm run build` — shared-types, server e
web) e então sobe um **único processo Fastify** (`npm run start`) que serve a
**API e o SPA buildado** (`apps/web/dist`) na **mesma porta**. Não há modo
dev nem proxy do Vite. Abra **http://127.0.0.1:5173** (ou a porta de `--port`)
no navegador. Requer `cstk-panel >= 0.2.0`.

**Dependências**: `curl` sempre; `npm` e `node` (Node.js) apenas no modo nativo
(padrão). Com `--docker` (abaixo), `npm`/`node` **não** são necessários no
host: só é preciso Docker Engine/Desktop instalado **e** o daemon rodando.

```bash
cstk serve                      # compila e inicia o painel (API + SPA na mesma porta)
cstk serve --update             # atualiza o painel se houver release nova, depois inicia
cstk serve --reinstall          # remove e reinstala do zero, depois inicia
cstk serve --docker             # roda o painel num container Docker local (sem npm/node no host)
```

## Opções

| Flag | Padrão | Descrição |
|------|--------|-----------|
| `--update` | — | Consulta o GitHub e reinstala o painel **somente** se houver release mais nova (best-effort: falha de rede/API mantém a versão instalada). Com `--docker`, reconstrói a **imagem** local. |
| `--reinstall` | — | Remove a instalação existente e reinstala do GitHub (incondicional; vence `--update`). Com `--docker`, reconstrói a **imagem** do zero. |
| `--port PORT` | `5173` | Porta onde o servidor Fastify escuta (inteiro 1024–65535; também lê `$PORT`). |
| `--host HOST` | `127.0.0.1` | Host de bind (apenas loopback tem suporte completo). |
| `--docker` | — | Roda o painel dentro de um container Docker local (opt-in; ausente = comportamento nativo 100% preservado). |
| `--help`, `-h` | — | Exibe ajuda e sai. |

## Variáveis de ambiente

- `CSTK_PANEL_DIR` — Substitui o diretório de instalação (padrão:
  `~/.local/share/cstk/panel`).
- `PORT` — Porta padrão quando `--port` não é informado.
- `CSTK_KNOWLEDGE_DB` — Caminho do `knowledge.db`; com `--docker`, o
  **diretório** deste arquivo é montado somente leitura no container
  (padrão: `~/.claude/cstk/knowledge.db`).

**Exit codes**: `0` sucesso · `1` erro geral (prereq ausente, download/build
falhou, instalação corrompida; com `--docker` também: Docker ausente/daemon
inacessível, build da imagem falhou, container remanescente irreconciliável) ·
`2` erro de uso (porta inválida, flag desconhecida).

**Segurança**: apenas URLs de `api.github.com`, `github.com`,
`codeload.github.com` e `objects.githubusercontent.com` são autorizadas no
download (SSRF allowlist). Integridade **fail-closed por padrão**: pacote sem
`.sha256` bloqueia (`unverifiable-blocked`); bypass explícito e auditado via
`--allow-unverified`/`CSTK_SERVE_ALLOW_UNVERIFIED=1`; divergência de checksum
bloqueia sempre. Host `127.0.0.1` é o único com suporte completo.

## Modo Docker (`cstk serve --docker`)

Roda o painel dentro de um **container Docker local** em vez de nativamente no
host — útil quando `npm`/`node` não estão disponíveis (ou não são desejados)
na máquina.

**Pré-requisitos**: Docker Engine ou Docker Desktop instalado **e** o daemon
rodando. Ambos são checados antes de qualquer acesso à rede, com mensagens
distintas para "Docker não instalado" vs "daemon parado/inacessível".

**O que acontece**: na primeira execução (ou em `--reinstall`, ou em
`--update` quando há release nova), constrói uma imagem local
(`cstk-panel:<versão>`, **nunca** publicada em registry) a partir da mesma
árvore-fonte verificada usada no modo nativo — mesmo mecanismo de integridade
fail-closed. Builds subsequentes reusam a imagem já construída. O container
roda com hardening por padrão (usuário não-root, `--cap-drop ALL`,
`--security-opt no-new-privileges`, rootfs somente leitura) e nome
determinístico (`cstk-panel`) — um container remanescente de uma execução
anterior é automaticamente reconciliado.

**Paridade de dados com o modo nativo**: o diretório do `~/.claude/cstk/`
(ou o diretório de `$CSTK_KNOWLEDGE_DB`, se definida) é montado **somente
leitura** dentro do container — o painel containerizado lê o **mesmo**
`knowledge.db` do modo nativo, byte a byte. Gravações concorrentes no host
ficam visíveis na próxima requisição, **sem precisar reiniciar** o container.

`Ctrl+C` encerra o container graciosamente (`docker stop`, mesmo grace
period do modo nativo). Detalhes completos:
[`specs/panel-docker/spec.md`](./specs/panel-docker/spec.md).
