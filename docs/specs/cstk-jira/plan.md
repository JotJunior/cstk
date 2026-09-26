# Implementation Plan: Integracao CSTK-Jira

**Feature**: `cstk-jira` | **Date**: 2026-09-24 | **Spec**: [spec.md](./spec.md)

## Summary

Novo plugin `plugins/cstk-jira/` no marketplace do toolkit que converte uma
feature documentada (spec + tasks.md) em Epic > Task > Sub-task no Jira Cloud,
mantem um board dedicado por projeto-alvo e sincroniza o status dos cards
durante execucoes autonomas `feature-00c`/`agente-00c`.

Abordagem (decisoes estruturais com consentimento do operador):

- **Arquitetura A1** (dec-020 / block-001): skills interativas usam o
  Atlassian Rovo MCP oficial quando suas tools estao visiveis na sessao; o
  resto passa por um helper REST local. O sync autonomo e disparado por
  **hooks do proprio plugin** nos pontos de ciclo de vida ja existentes
  (`record_task` / `close_wave`, e seus equivalentes Bash) e usa REST. Sem
  servidor MCP dedicado (FR-010) e sem tocar no allowlist fechado dos
  orquestradores.
- **Runtime B1** (dec-021 / block-002): POSIX sh; `jq` e o cliente HTTP ja
  usado em `cli/lib/http.sh` confinados em UM arquivo
  (`plugins/cstk-jira/scripts/jira-io.sh`) sob o carve-out 1.1.0.
- **Persistencia C1** (dec-022 / block-003): `docs/specs/<feature>/jira-map.tsv`
  versionado e a fonte primaria do mapeamento; entity property `cstk-jira.sync`
  na issue e o marcador secundario de conflito (FR-011).
- **Ambiente D1** (dec-023 / block-004): somente Jira Cloud. Data Center/Server
  fora de escopo.
- **Autenticacao** (research Decision 2): API token do Atlassian account (Basic
  auth). Sem renovacao automatica possivel => FR-019-INFRA-REFRESH resolvido pelo ramo
  "tratar como credencial invalida" (FR-016): suspensao explicita, nunca retry.

## Technical Context

**Language/Version**: POSIX sh (`#!/bin/sh`, `set -eu`) para scripts e hooks;
Markdown para skills.
**Primary Dependencies**: `jq` + cliente HTTP de linha de comando (o mesmo de
`cli/lib/http.sh`), ambos OPCIONAIS sob o carve-out 1.1.0 e confinados em
`plugins/cstk-jira/scripts/jira-io.sh`; Atlassian Rovo MCP Server (remoto,
oficial, configurado pelo usuario — nao empacotado).
**Storage**: arquivos texto — `jira-map.tsv` versionado por feature;
`.claude/cstk-jira/config` (sem segredo); `.claude/cstk-jira/runtime/`
(outbox/conflitos, nao versionado); credencial em
`${XDG_CONFIG_HOME:-$HOME/.config}/cstk-jira/credentials` (`0600`).
**Testing**: suite POSIX existente (`tests/run.sh`, descoberta em
`tests/cstk/test_*.sh`); cliente HTTP substituido por stub — nenhum teste toca
rede. Licao ja registrada no repo: stub no PATH nao esconde binario de
`/usr/bin`, entao o teste de "dependencia ausente" MUST controlar o PATH
inteiro do SUT (PATH minimo explicito), nao so prefixar um diretorio.
**Target Platform**: macOS e Linux com Claude Code + plugins (ambiente POSIX — constitution Principio II); Jira Cloud (spec D1).
**Project Type**: plugin do Claude Code (skills + hooks + scripts).
**Performance Goals**: SC-003 — card reflete o outcome ate o fim da mesma onda
em >=95% das sincronizacoes (garantido pelo drain obrigatorio em
`close_wave`).
**Constraints**: FR-015 (so o host configurado); rate limit Jira (429 +
`Retry-After`; 20 escritas / 2 s por issue — research Decision 3); cota do
Rovo MCP por plano; hooks nunca bloqueiam/atrasam o orquestrador.
**Scale/Scope**: um projeto Jira + um board por projeto-alvo; dezenas a poucas
centenas de itens por feature (limite de 50 no bulk create — research
Decision 3 — nao e usado no MVP; criacao item a item preserva o mapeamento
atomico).

## Constitution Check

*GATE: Deve passar antes do Phase 0. Re-checado apos Phase 1 (abaixo).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo | PASS | spec + clarify + plan nesta pipeline; tasks.md vira na etapa create-tasks. Plugin novo nao altera contrato de skill existente; CHANGELOG + bump de versao no release (lockstep MP-5) |
| II. POSIX sh, zero dep | PASS com carve-out 1.1.0 | `jq` + cliente HTTP so em `jira-io.sh` (condicao b); declarados aqui com justificativa e fallback (condicao c); fallback verificavel = caminho interativo via Rovo MCP + scripts POSIX puros, com o sync autonomo saindo com exit 5 e eventos preservados no outbox (condicao a — coberto por teste com PATH sem as deps). Consentimento explicito do operador: block-002 |
| III. Formato canonico de skill | PASS | 3 skills (`jira-setup`, `jira-convert`, `jira-sync`) com SKILL.md enxuto, `references/`, Gotchas e description-como-trigger |
| IV. Zero coleta remota | PASS | rede so para o host Jira do proprio usuario, que e o proposito inerente da feature; nenhum endpoint do autor; host unico validado por salto (FR-015) |
| V. Profundidade | PASS | escopo fechado nas 4 user stories; DC fora (D1) |
| VI. Zero fabricacao | PASS condicionado | todo endpoint/campo/tool em `contracts/` tem URL + citacao; itens sem fonte ficam marcados `NAO ENCONTRADO` e FORA do contrato; tarefa bloqueante de reconferencia contra a pagina de referencia (ou chamada observada) antes de codificar o cliente REST |

## Architecture

```mermaid
flowchart LR
    subgraph interactive[Sessao interativa]
        S1[skill jira-setup]
        S2[skill jira-convert]
        S3[skill jira-sync]
    end
    subgraph autonomous[Execucao 00c]
        O[orquestrador] -->|record_task / close_wave| H[hook PostToolUse async]
    end
    S1 & S2 & S3 -->|tools visiveis| MCP[Rovo MCP oficial]
    S1 & S2 & S3 --> POSIX[jira-config / jira-tasks / jira-map]
    S2 & S3 -->|sem MCP| ENG[jira-sync.sh]
    H --> OB[(outbox runtime)] --> ENG
    ENG --> IO[jira-io.sh: jq + HTTP]
    IO -->|so site_host| JIRA[(Jira Cloud)]
    MCP --> JIRA
    ENG --> MAP[(docs/specs/feature/jira-map.tsv)]
    G[hook PreToolUse] -.->|exit 2| MCP
```

Fluxos:

1. **Setup (US4, FR-007)** — `jira-setup`: grava `ProjectConfig`; instrui o
   operador a gravar a credencial num terminal proprio (nunca no chat);
   valida credencial remota; descobre tipos de issue (createmeta) e
   transicoes/status do workflow e pede ao operador o mapeamento
   `pending/in_progress/pass/fail` (recusa `fail == pass`); lista os tipos de
   issue retornados (`id`, `name`, `hierarchyLevel`, `subtask`) e pede ao
   operador que CONFIRME explicitamente qual e Epic, qual e Task e qual e
   Sub-task antes de gravar `issue_type_*` — o valor de `hierarchyLevel` que
   corresponde a Epic e `NAO ENCONTRADO` nas fontes oficiais
   (`contracts/jira-rest.md` R8), entao o sistema NUNCA infere esse
   mapeamento sozinho (checklist CHK006 do gate `api`); cria ou reusa o
   filtro + board kanban do projeto (US2 cenario 2: reuso, sem duplicar).
   Projeto Jira: reusa um existente; criacao so via tool `createJiraProject`
   do Rovo MCP ou pela UI do Jira (path REST v3 de criacao de projeto =
   `NAO ENCONTRADO`, research Decision 3).
2. **Convert (US1, FR-001/003/013/014)** — `jira-convert`: pre-checagens
   completas antes da 1a escrita; cria Epic, Tasks filhas (`parent`) e
   Sub-tasks; grava `jira-map.tsv` item a item; grava SyncMarker. Reexecucao
   cria so o que falta (US1 cenario 2).
3. **Sync autonomo (US3, FR-004/005/018)** — hook async enfileira e drena;
   drain obrigatorio no `close_wave` (SC-003). Conflito manual (FR-011) =>
   nao escreve, registra ConflictRecord. Credencial rejeitada => `auth_failed`,
   suspende chamadas ate reconfigurar. Jira indisponivel => `deferred`; a
   execucao da feature NUNCA para por causa do Jira (edge case da spec).
4. **Board (US2)** — board kanban sobre filtro JQL do projeto; colunas =
   status do workflow; o plugin move cards so por transicao de status.

## Project Structure

### Documentation (this feature)

```text
docs/specs/cstk-jira/
├── spec.md
├── research.md        # Phase 0 (onda-003)
├── plan.md            # este arquivo
├── data-model.md
├── quickstart.md
└── contracts/
    ├── jira-rest.md       # subconjunto REST v3 + Agile, com fontes
    ├── rovo-mcp.md        # tools do Rovo MCP usadas + deny-list
    ├── hooks.md           # hooks.json do plugin
    └── plugin-scripts.md  # CLI interna do plugin
```

### Source Code (repository root)

```text
plugins/cstk-jira/                      # NOVO (so esta subarvore e instalada)
├── .claude-plugin/plugin.json          # version em lockstep (MP-5)
├── hooks/
│   ├── hooks.json
│   ├── posttooluse-jira-sync.sh
│   └── pretooluse-jira-deny-destructive.sh
├── scripts/
│   ├── jira-io.sh                      # UNICO arquivo com jq + cliente HTTP
│   ├── jira-config.sh
│   ├── jira-tasks.sh
│   ├── jira-map.sh
│   └── jira-sync.sh
└── skills/
    ├── jira-setup/{SKILL.md,references/}
    ├── jira-convert/{SKILL.md,references/}
    └── jira-sync/{SKILL.md,references/}

.claude-plugin/marketplace.json         # ALTERADO: 3a entrada cstk-jira
scripts/validate-plugin-manifests.sh    # ALTERADO: MP-2 "exatamente 2" -> "exatamente 3"
tests/cstk/test_validate-plugin-manifests.sh  # ALTERADO: fixture com 3 plugins
tests/cstk/test_jira-*.sh               # NOVOS (descobertos por tests/run.sh L140)
CHANGELOG.md                            # ALTERADO no release
```

**Structure Decision**: plugin separado (padrao `cstk-language-go`), instalado
so via marketplace (FR-008). NAO espelhado no tarball do `cstk install`
(`scripts/build-release.sh` so espelha `plugins/cstk/` e
`plugins/cstk-language-*/` — L160-227): distribuir por dois canais dobraria a
matriz de teste sem ganho, e hooks de plugin so existem no canal plugin.

## Pontos explicitos exigidos pela onda-003

| # | Ponto | Tratamento no plano |
|---|-------|---------------------|
| 1 | Gate `MP-2` exige exatamente 2 plugins (`scripts/validate-plugin-manifests.sh` L11, L95-98) | mudar para exatamente 3 + fixture de teste; mantida a rigidez (um plugin a mais/a menos continua quebrando o gate). `MP-5` exige `plugin.json` do cstk-jira na mesma versao do release |
| 2 | Deny-list de `deleteJiraIssue` (FR-012) | hook `PreToolUse` com matcher regex `mcp__.*__(deleteJiraIssue\|executeDestructive)` e exit 2 (`contracts/hooks.md`); `jira-io.sh` nao tem metodo `DELETE`; skills citam a proibicao em Gotchas |
| 3 | Dominio Jira no allowlist de URLs da execucao | NAO necessario e deliberadamente NAO feito: o `bash-guard` e hook `PreToolUse` com matcher `Bash` (`plugins/cstk/hooks/hooks.json`) e so inspeciona comandos da tool Bash; o sync autonomo roda como subprocesso de hook do plugin e nenhum script recebe URL em argv. A garantia de FR-015 fica no proprio `jira-io.sh` (host unico por igualdade exata, sem seguir redirect para outro host) — mesmo desenho do `cli/lib/http.sh` pos-issue #178. Registrado como Decisao desta onda |
| 4 | Descritor local do Rovo MCP em `/v1/mcp` vs recomendado `/v2/mcp` | o plugin NAO empacota `.mcp.json` (evita segunda conexao ao mesmo servidor e acoplamento a um endpoint); `jira-setup` detecta tools visiveis por sufixo de nome e o quickstart recomenda `https://mcp.atlassian.com/v2/mcp` (README oficial). Os nomes de tool usados existem so no MCP v2 (research Decision 1) — com descritor v1 as tools v2 passam a ser expostas conforme o README; divergencia de data da migracao fica registrada como ressalva |
| 5 | API token expira em ate 1 ano sem renovacao automatica | FR-019-INFRA-REFRESH pelo ramo "nao e possivel": `401` => `auth_failed`, suspende o drain, diagnostico de reconfiguracao (FR-016) — expiracao de token se manifesta como `401`, nao `403` (403 em R1/R2 e permissao insuficiente, distinto — ver Test Strategy "Falha"); `jira-setup` exibe a data de validade informada pelo operador como lembrete (nao ha API citada para ler a expiracao) |

## Convencoes de Borda

| Camada | Case style | Validacao | Fonte da verdade |
|--------|------------|-----------|------------------|
| Arquivos do plugin (config, TSV, chave de property) | snake_case (colunas/chaves), kebab-case (arquivos) | `jira-config.sh validate`, cabecalho TSV | `data-model.md` |
| Payload REST Jira | como definido pela Atlassian (camelCase na maioria dos campos citados) | nomes so de `contracts/jira-rest.md` | paginas oficiais citadas no contrato |
| Parametros de tool Rovo MCP | como definido pela Atlassian | nomes so de `contracts/rovo-mcp.md` | paginas oficiais citadas |
| stdin de hook | snake_case (Claude Code) | leitura por campo nomeado | `contracts/hooks.md` |

**Mapper layer**: `jira-sync.sh` traduz `LocalWorkItem` -> corpo REST (via
`jira-io.sh json-build`); nenhum outro arquivo monta JSON.

## Test Strategy

| Nivel | O que cobre | Como |
|-------|-------------|------|
| Unit (POSIX) | parse de tasks.md, derivacao de `local_state`, mapeamento atomico, deteccao de orfao, validacao de config/host | fixtures de tasks.md em `tests/cstk/fixtures/` |
| Contrato | corpo/metodo/path gerados pelo motor batem com `contracts/jira-rest.md` | stub do cliente HTTP grava a requisicao; assert sobre metodo, path e chaves |
| Idempotencia (SC-002) | 10 execucoes de `convert` seguidas => 0 criacoes apos a 1a | stub com estado |
| Falha | 401 (qualquer operacao) => `auth_failed` sem retry; 403 em R1/R2 (criar/editar issue) => `permission_denied` (diagnostico "credencial valida, permissao insuficiente no projeto/tipo", NUNCA reconfiguracao de credencial — `contracts/jira-rest.md` "Validacao de credencial": 403 em R1/R2 e permissao, nao credencial); 403 nas demais operacoes (sem fonte que os distinga) segue tratado como `auth_failed` ate nova fonte; 429 => `deferred`; host divergente/redirect => recusa sem requisicao; deps ausentes => exit 5 | stub + PATH controlado |
| Hooks | no-op sem config (SC-006); fail-open; nunca imprime/grava `session_id`; guarda exit 2 | stdin sintetico |
| Mutation | cada guarda (host, DELETE, deny, no-op) e quebrada de proposito para provar que o teste pega | pratica ja adotada no repo |
| E2E manual | roundtrip REAL contra um site Jira Cloud de teste | `quickstart.md` cenario 6 (captura do payload real e comparacao com o contrato) |

## Complexity Tracking

| Violacao / tensao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|-------------------|--------------------|--------------------------------------|
| Deps nao-POSIX (`jq` + cliente HTTP) no plugin | parse/geracao de JSON e HTTPS sao inerentes a uma API REST; confinadas em `jira-io.sh` com fallback interativo (carve-out 1.1.0, consentido em block-002) | Node/TS zero-dep (B2) — rejeitado pelo operador; JSON em `awk` puro — fragil para respostas reais e seria parser proprio sem teste de conformidade |
| Sync autonomo so via REST (MCP so no interativo) | hooks de linha de comando nao chamam tools MCP; o allowlist dos orquestradores e fechado (research Decision 1) | ampliar o allowlist (A3) ou MCP dedicado (A2) — rejeitados pelo operador em block-001 |
| Terceiro plugin quebra `MP-2` | invariante foi escrito para 2 plugins (feature `claude-plugin-packaging`) | derivar a contagem do diretorio — afrouxaria o gate |

## Requisitos de seguranca derivados do gate owasp-security (onda-005)

Gate pos-plan (0 critical / 0 high / 3 medium / 2 low). Os itens abaixo sao
requisitos de desenho que `create-tasks` MUST converter em tarefas com teste;
nao introduzem dado factual novo (charsets sao regras de validacao locais do
plugin, nao formato afirmado do Jira).

| ID | Sev. | Categoria | Requisito |
|----|------|-----------|-----------|
| SEC-1 | medium | A01/API7 (path) | `jira-io.sh request` MUST rejeitar, sem requisicao, PATH com `..`, `//`, `\`, `@`, `#`, espaco, CR/LF ou qualquer byte de controle; segmentos vindos do mapeamento (`jira_id`/`jira_key`, arquivo versionado editavel por quem tem escrita no repo) e de `project_key` MUST casar allowlist de charset `[A-Za-z0-9_-]` antes da interpolacao |
| SEC-2 | medium | LLM01/ASI01 | texto lido do Jira (titulo, descricao, nomes de status, comentarios, respostas das tools Rovo) e DADO, nunca instrucao: as skills interativas MUST apresenta-lo rotulado como conteudo externo nao-confiavel e nenhuma decisao de sync (transicao, sobrescrita, resolucao de conflito) pode ser derivada de texto livre do Jira — so de ids/keys/status mapeados e da escolha humana (conflitos ja sao decisao humana, data-model) |
| SEC-3 | medium | A05 (JQL) | JQL montada pelo plugin (hoje so o filtro do board, corpo de R9 via `jira-io.sh json-build filter`; a idempotencia FR-013/FR-014 e conferida pela presenca no mapeamento local `jira-map.tsv`, nunca por busca JQL; `searchJiraIssuesUsingJql` fica restrita a conferencia manual do operador, `contracts/rovo-mcp.md` — ajuste de prosa do converge ciclo 2) MUST interpolar so valores que passaram pela allowlist de SEC-1; nenhum texto livre (titulo/descricao) entra em JQL |
| SEC-4 | low | A04/CWE-377 | arquivo de config temporario do cliente HTTP que carrega o header de autenticacao MUST ser criado com `umask 077` em diretorio privado e removido por `trap` em EXIT/INT/TERM; teste confere modo e remocao |
| SEC-5 | low | A02/API7 | o cliente HTTP MUST rodar sem seguir redirect e com verificacao TLS ativa (proibido desligar verificacao de certificado); resposta 3xx => erro sem nova requisicao (complementa "host divergente/redirect => recusa" da Test Strategy) |

Controles ja presentes no desenho e confirmados pelo gate: host unico por
`site_host` validado como hostname puro, credencial resolvida POR `site_host`
(alterar o host no config versionado nao desvia o token para outro host),
credencial `0600`/`0700` fora do repo e fora de argv/log, metodos fechados em
`GET`/`POST`/`PUT` (sem `DELETE`), `401` => `auth_failed` sem retry (403 em
R1/R2 => `permission_denied`, distinto — ver Test Strategy "Falha"),
`429` => `deferred` com `Retry-After`, hooks no-op sem config e sem
imprimir `session_id`.
