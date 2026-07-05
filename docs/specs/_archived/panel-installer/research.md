# Phase 0 — Research: panel-installer

Decisoes tecnicas que resolvem os unknowns do Technical Context antes do design.
Formato: Decision / Rationale / Alternatives considered.

---

## D1 — Como obter o "release mais recente" do cstk-panel

**Decision**: consultar a GitHub REST API em
`https://api.github.com/repos/JotJunior/cstk-panel/releases/latest`, extrair
`tag_name` e `tarball_url` da resposta JSON com `grep`/`sed` POSIX (sem `jq`), e
baixar o source tarball nativo do GitHub via `http_download` (helper existente).

**Rationale**:
- `/releases/latest` retorna o release mais recente NAO-prerelease/NAO-draft sem
  precisar listar+ordenar tags client-side — endpoint canonico, 1 request.
- `tarball_url` aponta para `codeload.github.com`/`objects.githubusercontent.com`
  (CDN ja na whitelist externa do state) e nao exige autenticacao para repo publico.
- Evitar `jq` no caminho do `serve` mantem a dep opcional `jq` confinada onde ja
  existe (`hooks.sh`/`recall.sh`); `tag_name` e `tarball_url` sao campos planos,
  extraiveis por `grep -o '"tag_name"[^,]*' | sed ...` de forma robusta o bastante
  para a resposta da API (campos string sem aninhamento).

**Alternatives considered**:
- **`git clone --depth 1`**: rejeitado — exige `git` (nova dep opcional), traz
  historico/`.git`, e nao da controle sobre "release" (clona o branch default, nao a
  tag de release). Conflita com a semantica "release mais recente".
- **Listar `/releases` e ordenar client-side**: rejeitado — mais requests, exige
  parse/ordenacao de array JSON (precisaria de `jq` ou parsing fragil); `/latest` ja
  resolve.
- **Hardcode da tag**: rejeitado — viola FR-001 (descobrir tag mais recente
  dinamicamente) e FR-010 (sem pin de versao).
- **Parse com `jq`**: rejeitado para o caminho `serve` (manter dep opcional confinada),
  mas o fallback com `jq`, se presente, e aceitavel como refinamento futuro; o caminho
  POSIX-puro com `grep`/`sed` e a base.

---

## D2 — Verificacao de integridade do download (ASI04 supply-chain)

**Decision**: integridade **best-effort**. O release v0.1.0 do cstk-panel tem
`assets: []` (confirmado na clarify, dec-007) — nao publica `.sha256`. Portanto
`serve.sh` NAO reusa `cli/lib/tarball.sh::download_and_verify` (que exige `sha256_url`
e ABORTA na ausencia). Em vez disso: baixa o tarball, tenta localizar um asset
`.sha256` correspondente; se presente, verifica via `sha256_file` (compat.sh) e ABORTA
em mismatch; se ausente, EXIBE AVISO claro no terminal ("verificacao de integridade
indisponivel: release sem asset .sha256") e prossegue (FR-008). Mitigacoes de
supply-chain que permanecem: (1) download SOMENTE via HTTPS de hosts na whitelist
(`api.github.com`, `objects.githubusercontent.com`) — `http_download` usa `curl -fsSL`;
(2) extracao em diretorio temporario privado (`mktemp -d`) e move atomico para o destino
so apos extracao bem-sucedida; (3) o `tarball_url` vem da resposta autenticada da API
(nao de URL fornecida pelo usuario), reduzindo superficie de SSRF/URL injection.

**Rationale**:
- Bloquear a instalacao por ausencia de `.sha256` quebraria a feature inteira (o
  upstream simplesmente nao publica o asset) — viola SC "operador tem painel em <60s".
- A reutilizacao de `download_and_verify` foi avaliada e REJEITADA tecnicamente: seu
  contrato (`tarball.sh` linhas 52-64) faz `http_download "$_surl"` e aborta se o
  `.sha256` estiver vazio/ausente. Forcar uma URL `.sha256` inexistente resultaria em
  HTTP 404 ⇒ exit 1, instalacao impossivel.
- Best-effort com aviso e o comportamento ratificado na clarify (dec-007, score 3 via
  investigacao empirica do release real). Se releases futuros publicarem `.sha256`, o
  mesmo codigo o detecta e passa a verificar automaticamente (sem mudanca de contrato).

**Alternatives considered**:
- **Bloquear sem `.sha256`**: rejeitado (clarify dec-007) — inviabiliza a feature.
- **Verificar assinatura GPG / sigstore**: rejeitado — upstream nao assina; introduz
  deps pesadas (`gpg`/`cosign`) fora do escopo e do carve-out.
- **Reusar `download_and_verify` com URL `.sha256` dummy**: rejeitado — falharia em 404.
- **Pin de hash conhecido no codigo do cstk**: rejeitado — viola FR-010 (sem pin de
  versao; release mais recente e sempre dinamico).

> **Nota de seguranca (ASI05/A03 — execucao de codigo de terceiros)**: o painel baixado
> roda `node` arbitrario do upstream. Isso e inerente a "baixar e rodar um painel" e foi
> aceito pelo usuario na formulacao da feature (opt-in explicito via `serve`). O gate
> owasp-security desta onda registra os findings residuais; a mitigacao principal e
> proveniencia confinada (so `JotJunior/cstk-panel` via API oficial) + HTTPS + whitelist.

---

## D3 — Onde instalar o painel

**Decision**: `~/.local/share/cstk/panel/` por padrao, sobreponivel via env var
`CSTK_PANEL_DIR` (FR-007). O diretorio guarda a arvore extraida do tarball (que tem
um nivel de prefixo `JotJunior-cstk-panel-<sha>/` — tratar com `tar --strip-components 1`
ou normalizacao pos-extract) e o marker `.panel-version`.

**Rationale**:
- `~/.local/share/cstk/` ja e a convencao de dados locais do runtime cstk (vide
  `cli/cstk` `_resolve_lib_dir` e `self-update.sh` usam `~/.local/share/cstk/lib`).
  Reusar essa raiz mantem consistencia de layout (XDG-ish data dir).
- `CSTK_PANEL_DIR` override e ESSENCIAL para teste sem tocar o `$HOME` real (mocks de
  `test_serve.sh` apontam para um tmpdir) e para ambientes alternativos.

**Alternatives considered**:
- **Dentro do repo do toolkit (`cli/panel/`)**: rejeitado — painel e artefato baixado,
  nao versionado; poluiria a arvore git e o tarball de release do cstk.
- **`/tmp`**: rejeitado — efemero, quebraria FR-002 (reuso em execucoes subsequentes).
- **`~/.cache/cstk/`**: rejeitado — `.cache` semanticamente e descartavel; o painel
  instalado e dado persistente esperado, `.local/share` e o lugar XDG correto.

---

## D4 — Deteccao de "primeira invocacao" (lazy install)

**Decision**: a instalacao e considerada PRESENTE E VALIDA se
`<panel-dir>/package.json` existe e e legivel (FR-002 — "diretorio presente com
`package.json` reconhecivel"). Logica: se `<panel-dir>` ausente OU `package.json`
ausente ⇒ tratar como primeira invocacao (baixar+instalar). Se `--reinstall` ⇒ remover
`<panel-dir>` e tratar como primeira invocacao incondicionalmente (FR-005).
Instalacao corrompida (diretorio existe mas `package.json` faltando) ⇒ detectar e
sugerir `cstk serve --reinstall` (P2 edge case).

**Rationale**:
- `package.json` na raiz e o sinal minimo confiavel de uma arvore do cstk-panel
  extraida (o painel e monorepo npm; `package.json` raiz sempre presente — confirmado
  pelo read-back: cstk-panel usa `npm install`/`npm run typecheck` com workspaces).
- Checar so a existencia do diretorio seria fragil (diretorio vazio pos-extracao
  falha); checar `package.json` distingue "instalado" de "corrompido".

**Alternatives considered**:
- **So `[ -d "$panel_dir" ]`**: rejeitado — nao distingue instalacao corrompida/vazia.
- **Checar `node_modules/`**: rejeitado — `node_modules` so existe apos `npm install`;
  a deteccao precisa funcionar ANTES de decidir rodar `npm install`. O marker correto
  de "codigo presente" e `package.json`; deps sao instaladas depois.
- **Validar via `.panel-version` apenas**: rejeitado — marker pode existir sem a arvore
  (escrita parcial); `package.json` e o sinal de conteudo real.

---

## D5 — Pre-requisitos de runtime e degradacao

**Decision**: ANTES de qualquer download ou start, `serve.sh` verifica
`command -v curl` e `command -v npm` (FR-006). Ausente ⇒ mensagem especifica + exit 1
(`CSTK_EXIT_ERROR`):
- `curl` ausente: "cstk serve: curl nao encontrado no PATH (necessario para baixar o
  painel)". (Tecnicamente `http.sh` ja reporta isso; `serve.sh` faz a checagem upfront
  para falhar cedo, antes de consultar a API.)
- `npm` ausente: "cstk serve: npm nao encontrado no PATH. Instale o Node.js
  (https://nodejs.org) para rodar o painel.".
Espaco em disco insuficiente (P1 edge): best-effort — se `mkdir`/extract falhar por
ENOSPC, reportar a falha de extracao com exit 1 (nao ha pre-check portavel POSIX
confiavel de espaco livre; aceitar a deteccao reativa).

**Rationale**:
- Falhar cedo (antes do download) economiza banda e da mensagem acionavel — SC "zero
  erros silenciosos; 100% dos prereqs ausentes com instrucao de correcao".
- `command -v` e POSIX puro e nao executa a ferramenta (seguro).

**Alternatives considered**:
- **Tentar usar e tratar o erro do `npm`/`curl`**: rejeitado — mensagem menos clara
  (erro generico de "command not found" do shell) e desperdicio de download se `npm`
  falta so na hora de subir.
- **Pre-check de espaco em disco com `df`**: rejeitado — `df` output nao e portavel
  (formato varia BSD/GNU), parsing fragil; deteccao reativa via falha de extract e
  suficiente e mais simples.

---

## D6 — Entrega de PORT/HOST e ciclo de vida do processo

**Decision**: porta entregue ao painel via env var `PORT` — `serve.sh` resolve a
porta (`--port`, default **5173**), valida 1-65535 (senao exit 2 `CSTK_EXIT_USAGE`),
exporta `PORT=<valor>` e executa `npm run start` na raiz do `<panel-dir>` em
FOREGROUND (FR-013-INFRA-PROC). Host: `--host` (default `127.0.0.1`) e ACEITO e
validado, mas NAO entregue ao backend (hardcoded `127.0.0.1` no cstk-panel); se
`--host` != `127.0.0.1`, exibir AVISO (FR-004). SIGINT/SIGTERM: instalar `trap` que
envia `kill` ao PID do filho `npm` e exibe mensagem de encerramento antes de sair
(FR-009). O `cstk serve` exporta `PORT` SEMPRE, entao o fallback interno `3001` do
painel nunca e atingido (reconciliacao do operador).

**Rationale**:
- Env var `PORT` e o contrato real do cstk-panel (`config.ts:
  process.env['PORT'] ?? '3001'` — clarify dec-006, score 3 empirico). Passar como arg
  de CLI ao `npm run start` nao tem efeito (o painel le do ambiente).
- Foreground + trap e o modelo mais simples e correto para "operador controla via
  terminal" (sem daemon/PID file — FR-013-INFRA-PROC). `trap '...' INT TERM` e POSIX.
- Default 5173 honra a intencao explicita do usuario (reconciliacao); exportar `PORT`
  sempre torna o default interno 3001 do painel irrelevante neste caminho.

**Alternatives considered**:
- **Default 3001 (fallback do painel)**: REJEITADO pela reconciliacao do operador —
  o usuario pediu 5173 explicitamente; 3001 e so o fallback do painel quando `PORT`
  nao e setado (fora do caminho do `cstk serve`).
- **Passar `--host` ao backend**: rejeitado — backend ignora (hardcoded); aceitar a
  flag + avisar e o contrato forward-compat ja ratificado (FR-004).
- **Modo daemon / PID file**: rejeitado — nao solicitado; foreground e o escopo
  (FR-013-INFRA-PROC).
- **Nao instalar trap (deixar SIGINT matar so o cstk)**: rejeitado — deixaria o `npm`
  filho orfao; FR-009 exige encerramento gracioso do filho.

---

## Sintese — unknowns resolvidos

Nenhum `NEEDS CLARIFICATION` remanescente. Todas as decisoes acima sao deterministicas
e ancoradas em (1) helpers POSIX ja existentes no repo (`http.sh`, `compat.sh`),
(2) contrato empirico do cstk-panel (clarify dec-006/dec-007, score 3), (3) convencoes
de layout do cstk (`~/.local/share/cstk/`), e (4) a reconciliacao do operador
(default `--port` = 5173).
