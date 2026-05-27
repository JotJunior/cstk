---
feature: panel-installer
short_name: panel-installer
version: 0.1.0
status: draft
created: 2026-05-26
---

# Feature Spec: panel-installer

Comando `cstk serve` que instala e serve o painel de visualizacao de conhecimento
(`cstk-panel`) sob demanda, na primeira invocacao, reutilizando a instalacao em
execucoes subsequentes.

---

## User Scenarios & Testing

### P1 — Primeiro uso: instalar e servir o painel

**Como** operador do toolkit que quer visualizar o historico de execucoes e
decisoes cross-feature,
**quero** rodar `cstk serve` e ter o painel acessivel no browser em segundos,
**para que** eu nao precise instalar nada manualmente nem saber de onde vem o painel.

**Acceptance Criteria:**
- Ao rodar `cstk serve` pela primeira vez, o sistema baixa o release mais recente
  do painel automaticamente sem intervencao do usuario.
- O painel sobe e fica acessivel no endereco exibido no terminal.
- O terminal exibe a URL de acesso e mensagem clara de que o painel esta rodando.
- Se o download falhar (rede indisponivel, release ausente), o sistema exibe mensagem
  de erro clara e sai com codigo de saida nao-zero.

**Edge Cases:**
- Rede indisponivel durante o download: mensagem de erro + exit 1.
- Release nao existe na API GitHub: mensagem de erro + exit 1.
- Espaco em disco insuficiente: detectar e reportar antes de tentar instalar.
- `npm` nao encontrado no PATH: mensagem clara pedindo instalacao do Node.js + exit 1.

---

### P2 — Uso subsequente: reutilizar painel ja instalado

**Como** operador que ja executou `cstk serve` anteriormente,
**quero** que o comando suba o painel imediatamente sem re-baixar,
**para que** o painel esteja disponivel em segundos sem consumir banda.

**Acceptance Criteria:**
- Ao rodar `cstk serve` com painel ja instalado, o sistema nao faz nenhuma
  requisicao de rede para o GitHub.
- O painel sobe diretamente da instalacao local.
- O tempo para o painel ficar acessivel e visivelmente menor que na primeira vez.

**Edge Cases:**
- Instalacao corrompida (arquivos faltando): detectar e oferecer `cstk serve --reinstall`.
- Diretorio de instalacao removido manualmente: tratar como primeira execucao.

---

### P3 — Configuracao de porta e host

**Como** operador que ja tem outro servico na porta 5173 ou quer expor em
interface especifica,
**quero** configurar porta e host via flags `--port` e `--host`,
**para que** o painel suba sem conflito e atenda ao ambiente de trabalho.

**Acceptance Criteria:**
- `cstk serve --port 3000` sobe o painel na porta 3000 (backend Fastify via `PORT=3000`).
- `cstk serve --host 0.0.0.0` aceita a flag sem erro; exibe aviso de que o backend
  esta fixo em 127.0.0.1 (limitacao do cstk-panel atual).
- Combinacao de flags funciona sem erro: `cstk serve --port 8080 --host 0.0.0.0`.
- Valores invalidos (porta fora de 1-65535) geram mensagem de erro + exit 2
  (uso incorreto).
- O terminal confirma a URL com porta efetiva (host sempre 127.0.0.1).

**Edge Cases:**
- Porta ja em uso: mensagem clara + sugestao de usar `--port`.
- Porta < 1024 sem privilegio: mensagem informando restricao de SO.

---

### P4 — Forcar reinstalacao

**Como** operador que suspeita de instalacao corrompida ou quer atualizar o painel,
**quero** poder forcar o download e instalacao novamente,
**para que** tenha sempre uma versao limpa e atual.

**Acceptance Criteria:**
- `cstk serve --reinstall` remove a instalacao existente e baixa novamente.
- Apos reinstalacao, o painel sobe normalmente.
- O terminal confirma a reinstalacao e o processo completo.

---

## Requirements

### Functional Requirements

**FR-001 — Download na primeira execucao (lazy-install)**
Na primeira invocacao de `cstk serve` (sem instalacao local presente), o sistema
DEVE consultar a API GitHub para descobrir a tag do release mais recente de
`JotJunior/cstk-panel`, baixar o tarball e instalar em diretorio local padrao.
O processo de download DEVE mostrar progresso visivel ao operador.

**FR-002 — Reutilizacao em execucoes subsequentes**
Se a instalacao local existir e for valida (diretorio presente com `package.json`
reconhecivel), o sistema NAO DEVE fazer requisicoes de rede e DEVE iniciar o painel
diretamente da instalacao local.

**FR-003 — Execucao via npm start**
Apos instalacao, o painel e iniciado via `npm run start` na raiz do repositorio,
que executa `node apps/server/dist/index.js` (backend Fastify).
A configuracao de porta/host segue o contrato do cstk-panel:
- **Porta**: passada via variavel de ambiente `PORT` (ex: `PORT=5173 npm run start`,
  onde 5173 e o default da flag `--port` do `cstk serve`). O backend le
  `process.env['PORT']` e so cai no proprio fallback interno `3001` quando `PORT`
  nao e setado — o que nunca ocorre no caminho do `cstk serve`.
- **Host**: hardcoded como `127.0.0.1` no config.ts do cstk-panel (FR-017 do painel,
  por design de seguranca). O parametro `--host` do `cstk serve` e aceito na
  interface CLI e reservado para compatibilidade futura, mas NAO tem efeito no
  binding atual do backend. O operador deve ser informado via aviso no terminal.

**FR-004 — Flags --port e --host**
O subcomando `cstk serve` DEVE aceitar:
- `--port N` (default: **5173**) — porta TCP onde o backend do painel escuta.
  Passada ao processo filho via env var `PORT` (`cstk serve` SEMPRE exporta
  `PORT=<valor resolvido>`, nunca deixando o painel cair no proprio fallback
  interno `3001`). Ver RECONCILIACAO na secao Clarifications: o `3001` e fallback
  do painel, nao o default da flag.
- `--host H` (default: 127.0.0.1) — interface de rede declarada. Aceita na
  interface CLI para compatibilidade futura; o backend atual ignora este valor
  (host hardcoded em 127.0.0.1 pelo cstk-panel). O terminal DEVE exibir aviso
  quando `--host` difere de 127.0.0.1.
Valores invalidos (porta fora de 1-65535) DEVEM ser rejeitados com mensagem de
erro e exit 2.

**FR-005 — Flag --reinstall**
O subcomando `cstk serve` DEVE aceitar `--reinstall` para forcar remocao da
instalacao existente e re-download do release mais recente antes de iniciar.

**FR-006 — Verificacao de prerequisitos**
Antes de tentar baixar ou iniciar o painel, o sistema DEVE verificar:
- `curl` disponivel no PATH (necessario para download)
- `npm` disponivel no PATH (necessario para run)
Se ausentes, exibir mensagem de erro especifica e sair com exit 1.

**FR-007 — Diretorio de instalacao**
O painel instalado DEVE residir em `~/.local/share/cstk/panel/` (convencao ja
usada pelo runtime do cstk para dados locais). O caminho DEVE ser sobreponivel
via variavel de ambiente `CSTK_PANEL_DIR` para testes e ambientes alternativos.

**FR-008 — Integridade do download**
O release do `cstk-panel` nao publica arquivo `.sha256` — o download e via
`tarball_url` GitHub nativo (source tarball) sem asset de checksum associado
(confirmado: release v0.1.0 tem `assets: []`).
O sistema DEVE prosseguir sem verificacao de integridade e DEVE exibir aviso
no terminal informando que a verificacao nao esta disponivel. NAO deve bloquear
a instalacao por ausencia de `.sha256`. Se em releases futuros o asset `.sha256`
for publicado, o sistema DEVE utilizá-lo automaticamente (verificacao best-effort).

**FR-009 — Sinal de interrupcao (Ctrl+C)**
Ao receber SIGINT/SIGTERM, o processo npm filho DEVE ser encerrado graciosamente
antes de o `cstk serve` sair. O terminal DEVE exibir mensagem de encerramento.

**FR-010 — Compatibilidade retroativa do painel**
A spec assume que o release mais recente do `cstk-panel` e sempre retro-compativel.
O sistema NAO implementa gerenciamento de versao ou pin de versao especifica.

**FR-011 — Principio II: POSIX sh puro para o helper**
O helper `cli/lib/serve.sh` DEVE ser POSIX sh puro (`#!/bin/sh`, `set -eu`,
sem Bash-isms). As chamadas externas a `npm` e `curl` sao deps opcionais
com fallback (exit 1 com mensagem) — cobertas pelo carve-out do amendment
1.1.0 do Principio II, pois:
(a) fallback graceful verificavel por teste automatizado,
(b) deps confinadas em `cli/lib/serve.sh` (unico arquivo),
(c) documentadas nesta spec com justificativa.
Justificativa: `npm` e dep do PAINEL (runtime externo), nao do `cstk` em si;
o subcomando `serve` e inerentemente opt-in (nao e parte do core POSIX toolkit).

**FR-012 — Sem telemetria ou coleta remota**
O subcomando `cstk serve` NAO DEVE enviar nenhum dado para endpoints externos
alem dos necessarios para download do release (GitHub API + CDN do release).
Nenhuma informacao do ambiente local e transmitida. (Principio IV.)

### Decisoes de Infraestrutura

> **Decisoes de infraestrutura**: declaradas abaixo por ser feature que gerencia
> processo filho de longo prazo.

**FR-013-INFRA-PROC — Gerenciamento de processo filho**
O processo `npm run start` e filho direto do `cstk serve` (nao daemon). O
`cstk serve` permanece em foreground aguardando o filho. Ao sair, propaga sinal
ao filho via `kill`. NAO ha gerenciamento de PID em arquivo (nao e servico de
sistema). Rationale: operador controla o ciclo de vida via terminal; modo daemon
nao foi solicitado.

**FR-014-INFRA-LOCK — Sem lock de instancia unica (nao aplicavel)**
Multiplas instancias de `cstk serve` podem rodar em portas diferentes. O
sistema NAO impede isso. Se a mesma porta for solicitada duas vezes, o SO
retorna erro de "porta em uso" que o helper detecta e reporta.

**FR-015-INFRA-SCHED — Sem scheduling (nao aplicavel)**
Feature stateless em relacao ao agendador. Cada `cstk serve` e invocacao
manual e independente.

### Key Entities

**PainelInstalado** — representa a instalacao local do cstk-panel:
- `diretorio`: path absoluto (`~/.local/share/cstk/panel/` por padrao)
- `versao_tag`: tag GitHub do release instalado (armazenada em `.panel-version`)
- `valido`: bool derivado da presenca de `package.json` no diretorio

**ReleaseGitHub** — release consultado via API:
- `tag_name`: string da tag mais recente
- `tarball_url`: URL de download do tarball `.tar.gz`
- `sha256_url`: URL do arquivo `.sha256` (pode estar ausente)

---

## Success Criteria

- Operador sem instalacao previa roda `cstk serve` e tem o painel acessivel no
  browser em menos de 60 segundos (excluindo tempo de download da rede).
- Operador com painel ja instalado tem o painel acessivel em menos de 10 segundos
  (sem acesso a rede).
- 100% dos erros de prerequisito (npm ausente, curl ausente, rede indisponivel)
  resultam em mensagem clara no terminal com instrucao de correcao — zero erros
  silenciosos.
- O subcomando `serve` nao interfere em nenhum outro subcomando do `cstk` (isolamento
  total via `cli/lib/serve.sh`).
- Suite de testes `tests/cstk/test_serve.sh` cobre primeira execucao, execucao
  subsequente, flags invalidas e prerequisito ausente — sem dependencia de rede real
  (mocks via variaveis de ambiente).

---

## Clarifications

### Session 2026-05-26 (mediacao inline, score 3 via investigacao empirica)

- Q: Como o cstk-panel aceita configuracao de porta/host — env vars (`PORT`, `HOST`)
  ou args de CLI para `npm run start`?
  → A: Porta via env var `PORT` (lida em `config.ts` como `process.env['PORT'] ?? '3001'`).
  Host hardcoded `127.0.0.1` no backend (FR-017 do cstk-panel); `--host` aceito na CLI
  do cstk serve mas sem efeito atual.

  **RECONCILIACAO (operador, 2026-05-26 — reconcilia clarify onda-002):** o default
  da flag `--port` do `cstk serve` e **5173** (intencao explicita do usuario na
  formulacao da feature), NAO 3001. O `3001` e apenas o fallback INTERNO do cstk-panel
  (`process.env['PORT'] ?? '3001'`) e e irrelevante no caminho do `cstk serve`, porque
  o `cstk serve` SEMPRE exporta `PORT=<valor resolvido>` ao subir o painel — entao o
  fallback do painel nunca e atingido quando o painel sobe via `cstk serve`. Toda
  referencia a "default 3001" nesta spec deve ser lida como "fallback do painel quando
  `PORT` nao e setado", e o default da flag `--port` permanece 5173 (ver FR-004
  reconciliado abaixo). Decisao auditada no state.json da execucao feature-00c
  (etapa plan).

- Q: O release do cstk-panel publica arquivo `.sha256` junto ao tarball? Se nao, o
  comportamento deve ser prosseguir com aviso ou bloquear com erro?
  → A: Nao publica (release v0.1.0 tem `assets: []`). Comportamento: prosseguir sem
  verificacao com aviso no terminal. Verificacao best-effort se asset `.sha256` for
  publicado em releases futuros.
