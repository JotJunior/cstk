# Implementation Plan: Servidor MCP de Estado das Execucoes 00C

**Feature**: `state-mcp-server` | **Date**: 2026-08-01 | **Spec**: [spec.md](./spec.md)

## Summary

Expor as mutacoes de estado das execucoes autonomas (`agente-00c`/`feature-00c`)
como **tools MCP com contrato validado**, em vez de sequencias `Bash` que o
orquestrador (um subagente LLM) precisa lembrar de executar ate o fim.

**Abordagem tecnica** (derivada do Phase 0):

1. **O servidor nao reimplementa regra de estado** — cada tool delega ao helper
   POSIX correspondente do `agente-00c-runtime` (research.md D1). As invariantes
   exigidas pelos FRs **ja existem e ja sao testadas** la (score 3 ⇒ evidencia
   >= 20 chars; PK que torna `record_task` um upsert; trigger que impede fechar
   onda duas vezes). Reimplementar em JS criaria duas fontes de verdade e violaria
   FR-014 na pratica.
2. **Transporte `stdio` com entrada estatica no `.mcp.json` + resolucao lazy da
   execucao ativa** (research.md D2) — contorna o risco #1 (registro dinamico de
   servidor mid-sessao e [NAO-VERIFICADO]) sem multiplexar sessoes, e zera a
   superficie de rede (nenhuma porta publicada).
3. **Atomicidade de `close_wave` por pre-imagem + compensacao** (research.md D3),
   porque duas das tres pos-condicoes (backup, hash) sao efeitos fora do banco —
   nenhuma transacao SQL as cobriria.
4. **O servidor nao adquire lock** (research.md D4): o command pai ja detem o
   mutex nao-reentrante durante toda a onda; um `acquire` do servidor daria
   `exit 3` sempre. Achado que corrige o desenho ingenuo.
5. **Auditoria no `enforcement-log.jsonl` existente**, com `source` proprio e a
   ordem obrigatoria **scrub → truncate** (research.md D6).

## Technical Context

**Language/Version**: TypeScript 5.x compilado para Node.js 22 (servidor) +
POSIX `sh` (CLI e helpers) — a primeira arvore Node do repo
**Primary Dependencies**: `@modelcontextprotocol/sdk` (servidor MCP); Zod
(schemas — a confirmar no spike S4); `docker` (dep **opcional**, com fallback
Bash); `jq` e `sqlite3` (dentro do container, herdados dos helpers)
**Storage**: nenhum novo. `state.db` (SQLite, WAL) ou `state.json`, conforme
`_sr_backend` resolve — sempre por intermedio dos helpers
**Testing**: `node:test` (runner embutido, zero dep nova) para o servidor;
harness POSIX `tests/run.sh` para os `.sh` novos
**Target Platform**: macOS/Linux com Docker; degrada para fallback Bash sem Docker
**Project Type**: servico local (processo de sessao) + extensao de CLI
**Performance Goals**: N/A — o gargalo da onda e a inferencia do LLM, nao o
`fork+exec` do helper (dezenas de ms). Health check <= 30s [a calibrar]
**Constraints**: zero rede publicada; nenhuma montagem de `knowledge.db`; blast
radius = **um** state-dir por sessao
**Scale/Scope**: 6 tools; 1 container por execucao ativa; tipicamente 1-2
execucoes concorrentes por projeto

## Constitution Check

*GATE: passou antes do Phase 0; **re-checado apos Phase 1** (secao §Re-check).*

| Principio | Status | Notas |
|-----------|--------|-------|
| I. SDD recursivo (NON-NEGOTIABLE) | **PASS** | Feature entrou por `specify` → `clarify` → `plan`; `create-tasks` na sequencia |
| II. POSIX sh puro, zero dep externa (NON-NEGOTIABLE) | **PASS com carve-out** | Ver analise abaixo — e o ponto de maior tensao do plano |
| III. Formato canonico de skill | **N/A** | Nenhuma skill nova; `SKILL.md` do `agente-00c-runtime` ganha ponteiro para os scripts novos |
| IV. Zero coleta remota (NON-NEGOTIABLE) | **PASS** | Servidor e loopback/stdio local, sem porta e sem endpoint remoto. O unico trafego e `npm install` no **build** da imagem — busca de dependencia, nao telemetria (mesmo padrao ja aceito em `serve-docker.sh`) |
| V. Profundidade sobre adocao | **PASS** | Ataca causa-raiz de bugs cronicos reais (onda nao fechada, `record-task` pulado, half-record), nao superficie de anuncio |
| VI. Veracidade de dados (NON-NEGOTIABLE) | **PASS** | Todo artefato deste plano usa rotulos [VERIFICADO]/[PROPOSAL]/[NAO-VERIFICADO]; as 9 lacunas do SDK/harness estao listadas e viram spikes empiricos, nunca fato |

### Analise do Principio II (ponto de maior tensao)

O Principio II governa **"scripts auxiliares de skills"**. O servidor MCP e um
**processo de servico**, categoria em que o toolkit ja opera fora da disciplina
POSIX — `cli/cstk` (Go) e o `cstk-panel` (Node) sao precedentes vivos, fato que a
propria spec registra. Os artefatos desta feature se dividem assim:

| Artefato | Regime |
|----------|--------|
| `cli/lib/mcp.sh`, `cli/lib/mcp-docker.sh`, `scripts/mcp-session.sh`, `scripts/mcp-launch.sh` | **POSIX sh integral** — `#!/bin/sh`, `set -eu`, sem bash-isms |
| `mcp/state-server/**` (TypeScript) | Processo de servico — mesmo regime de `cli/cstk` e do painel |

Dependencia `docker`: enquadra no **carve-out 1.1.0** (deps opcionais com
fallback graceful), com as tres condicoes cumulativas:

- **(a) fallback graceful verificavel**: FR-007/FR-012 — sem Docker, a execucao
  segue pelo caminho Bash **atual**, coberto por teste (quickstart Scenario 7);
- **(b) codigo confinado**: uso de `docker` desta feature fica **inteiramente**
  em `cli/lib/mcp-docker.sh` — **ver ressalva em §Complexity Tracking**;
- **(c) declarada na feature**: esta secao + `contracts/mcp-session-lifecycle.md`.

`jq`/`sqlite3` dentro do container caem no **carve-out 1.3.0** (dep obrigatoria da
camada de estado transacional): confinamento de camada (a), fail-fast diagnostico
(b), consumidores derivados degradam gracioso (c) e declaracao explicita (d) —
esta secao. Nao ha extensao do carve-out: sao **as mesmas** deps que os helpers ja
exigem hoje, apenas rodando dentro do container.

## Project Structure

### Documentation (this feature)

```
docs/specs/state-mcp-server/
├── spec.md
├── plan.md                              # This file
├── research.md                          # Phase 0
├── data-model.md                        # Phase 1
├── quickstart.md                        # Phase 1
└── contracts/
    ├── mcp-tools.md                     # 6 tools de mutacao
    └── mcp-session-lifecycle.md         # CLI, .mcp.json, container
```

### Source Code (repository root)

Arvore real do repo, com **[NOVO]** no que esta feature acrescenta:

```
cli/
├── cstk                                 # binario (dispatch ganha `mcp)`)
└── lib/
    ├── serve-docker.sh                  # precedente Docker (nao alterado)
    ├── mcp.sh                     [NOVO] # cstk mcp install|status|start|stop
    └── mcp-docker.sh              [NOVO] # TODO uso de `docker` desta feature
global/skills/agente-00c-runtime/
├── scripts/
│   ├── state-rw.sh, state-ondas.sh, state-decisions.sh, bloqueios.sh   # delegatarios (nao alterados)
│   ├── mcp-session.sh             [NOVO] # resolve execucao ativa (precedencia do hook)
│   └── mcp-launch.sh              [NOVO] # entrypoint stdio do .mcp.json
├── references/state-db-schema.sql       # nao alterado (zero tabela nova)
└── hooks/                               # nao alterado
mcp/                               [NOVO] # PRIMEIRA arvore Node do repo
└── state-server/
    ├── package.json / package-lock.json # lock obrigatorio (build falha sem)
    ├── src/
    │   ├── index.ts                     # bootstrap + transporte stdio
    │   ├── tools/                       # 1 arquivo por tool (6)
    │   ├── runtime/exec.ts              # invocacao dos helpers POSIX
    │   ├── session/resolve.ts           # le mcp-server.json / mcp-session.sh
    │   └── audit/log.ts                 # enforcement-log.jsonl (scrub→truncate)
    └── test/                            # node:test
tests/
├── test_mcp-session.sh            [NOVO] # exigido pelo --check-coverage
└── cstk/
    ├── test_mcp.sh                [NOVO] # idem
    └── test_mcp-docker.sh         [NOVO] # idem (+ assercoes estaticas de flags proibidas)
```

**Structure Decision**: confinar **todo** o codigo Node em `mcp/state-server/`.
Como o repo hoje **nao tem `package.json` algum** [VERIFICADO], deixar
`package.json`/`node_modules` na raiz mudaria a natureza percebida do projeto
(um toolkit de shell viraria "um projeto Node") e afetaria tooling de terceiros.
Um unico subdiretorio mantem a mudanca reversivel e legivel.

## Convencoes de Borda

A feature atravessa tres camadas com convencoes **deliberadamente diferentes** —
por isso a tabela e obrigatoria (o cenario 9 do quickstart existe para verifica-la
empiricamente).

| Camada | Case style | Idioma | Validacao | Fonte da verdade |
|--------|-----------|--------|-----------|------------------|
| Payload de tool MCP (request/response) | `snake_case` | **ingles** | `inputSchema` do SDK, **pre-handler** | `contracts/mcp-tools.md` |
| Codigo do servidor (identificadores TS) | `camelCase` | **ingles** | `tsc` | `mcp/state-server/src/**` |
| Flags dos helpers POSIX | `--kebab-case` | **portugues** (`--opcoes`, `--evidencia`) | validacao interna do helper | os proprios `.sh` [VERIFICADO] |
| Colunas do `state.db` | `snake_case` | **ingles** | CHECK/PK/trigger/FK | `references/state-db-schema.sql` [VERIFICADO] |
| Linha do `enforcement-log.jsonl` | `snake_case` | **ingles** | contrato do arquivo | `contracts/enforcement-log.md` (arquivada) [VERIFICADO] |
| Chaves do `.mcp.json` | `camelCase` (`mcpServers`) | ingles | harness do Claude Code | doc oficial |

**Mapper layer (tool ↔ helper)**: `mcp/state-server/src/runtime/exec.ts` — **unico**
lugar autorizado a traduzir campo ingles → flag em portugues. Sem ORM, sem
mapeamento automatico: a traducao e uma tabela explicita, porque as duas pontas
usam idiomas diferentes e nenhuma convencao automatica acertaria
(`evidence` → `--evidencia`, `rationale` → `--justificativa`).

**Risco especifico desta borda**: um campo **opcional** que existe no schema da
tool mas nunca chega ao helper falha em silencio — schema aceita, helper grava
sem ele, nada quebra. O Scenario 9 preenche **todos** os opcionais e compara
campo a campo, nos **dois** backends, exatamente para expor isso.

## Seguranca (resultado do gate `owasp-security` — OWASP Top 10:2025 + LLM Top 10 + Agentic 2026)

O gate rodou sobre o **desenho** (nao ha codigo). Achados e controles adotados —
os tres HIGH ja foram **corrigidos nos artefatos desta onda**, e os dois de
arquitetura foram levados ao operador (ver §Bloqueio humano).

| ID | Sev. | Achado | Controle adotado | Onde |
|----|------|--------|------------------|------|
| SEC-H1 | **HIGH** | Command injection na fronteira Node→POSIX: campos de texto livre (`evidence`, `rationale`, `question`…) vem de um LLM sujeito a injecao indireta; montar linha de comando = RCE no container, que tem o state-dir **rw** | `execFile`/`spawn` com **array de argv** e `shell:false`; proibidos `exec`/`execSync`/`shell:true`/crase; **assercao estatica** no teste | `contracts/mcp-tools.md` §SEC-H1 |
| SEC-H2 | **HIGH** | Montar `<projeto-alvo>/.claude` **rw** daria ao container escrita sobre `hooks/pretooluse-bash-guard.sh` e `settings.json` — escalada de "mutar o proprio estado" para **executar codigo no host** no proximo Bash do operador | Bind-mount do **arquivo** `enforcement-log.jsonl`, nunca do diretorio; teste estatico proibindo mount de `.claude`, `$HOME`, `/`, `docker.sock` | `contracts/mcp-session-lifecycle.md` §SEC-H2 |
| SEC-H3 | **HIGH** | **Confused deputy** (ASI03): rotear pela "execucao ativa" por precedencia faria o orquestrador da `feature-00c` mutar o state-dir da `agente-00c` quando ambas ativas — violacao direta de FR-008/US2-3 | `session_id` vira **token de capacidade** (>=128 bits, CSPRNG, `chmod 600`), injetado pelo pai no spawn; roteamento **pelo token**, fail-closed; precedencia so em consulta read-only | `contracts/mcp-session-lifecycle.md` §SEC-H3 |
| SEC-M1 | MEDIUM | stderr do helper volta ao contexto do LLM (LLM05) | Strip de controle + teto 2 KiB + rotulo de dado | `contracts/mcp-tools.md` |
| SEC-M2 | MEDIUM | Campos de identificador tratados como texto livre | Allowlist por regex no `inputSchema`; nenhum id inicia com `-` | `contracts/mcp-tools.md` |
| SEC-M3 | MEDIUM | Log injection: `"`/`\n` em texto livre forjaria entradas de auditoria (A09) | Serializador JSON real (nunca `printf`); ordem `scrub → truncate → serialize`; truncar por code point | `contracts/mcp-tools.md` |
| SEC-M4 | MEDIUM | Supply chain da **primeira arvore Node** do repo (A03/ASI04/CICD-SEC-3): `npm install` executa lifecycle scripts de dependencia no build | `npm ci --ignore-scripts` (nunca `npm install`), lockfile ja obrigatorio, base pinada por digest, arvore de deps minima, `npm audit` no CI | F5/F6 do backlog |
| SEC-M5 | MEDIUM | O servidor muta estado **sem** passar pelo `bash-guard` (que so cobre a tool Bash) e **sem** lock proprio (D4) | Risco **aceito e declarado**: o contrato da tool + `enforcement-log.jsonl` sao os controles compensatorios; a onda inteira segue dentro do lock do pai | esta secao |
| SEC-L1 | LOW | Sem teto de chamadas por tool/sessao (LLM10) | Recomendado pos-MVP (`budget.sh` orca a onda, nao a tool) | `contracts/mcp-tools.md` |
| SEC-I1 | INFO | OAuth 2.1 / PKCE / RFC 8707 / DPoP do checklist MCP | **N/A justificado**: `stdio`, zero listener de rede, zero credencial ambiente; o token de capacidade cumpre o papel local. **Caduca** se o plano B (HTTP) for acionado | `contracts/mcp-session-lifecycle.md` |

**Auto-atestacao do log (limite conhecido)**: a linha de auditoria e escrita pelo
mesmo processo que executa a mutacao. Um servidor comprometido poderia suprimir o
proprio rastro. Aceitavel neste modelo de ameaca (o container e confiavel por
construcao; o adversario modelado e o **conteudo** que o LLM le, nao o operador),
e mitigado por SEC-H1/H2 — mas **declarado**, nao ignorado.

## Fases de implementacao

| Fase | Conteudo | Gate de saida |
|------|----------|---------------|
| **F0. Spikes** | S1..S5 (research.md) | **BLOQUEANTE**: S1 falho ⇒ bloqueio humano, feature nao prossegue |
| F1. Fundacao POSIX | `mcp-session.sh` + `cstk mcp status` + testes | `tests/run.sh --check-coverage` verde |
| F2. Servidor minimo | `McpServer` + stdio + 1 tool (`record_skill`) + auditoria | Scenario 1 parcial |
| F3. Tools de mutacao | as 6 tools + mapper + rejeicoes tipadas | Scenarios 2, 3, 4 |
| F4. Atomicidade | `close_wave` com pre-imagem/compensacao | Scenario 5 |
| F5. Docker + ciclo de vida | `mcp-docker.sh`, `start/stop`, health check | Scenarios 6, 7, 8 |
| F6. Integracao 00c | `.mcp.json` via `cstk mcp install`; commands pais chamam status/start/stop | Scenario 9 + suite completa |

## Complexity Tracking

| Violacao | Por Que Necessario | Alternativa Simples Rejeitada Porque |
|----------|-------------------|--------------------------------------|
| Primeira arvore Node/TS do repo | O SDK MCP oficial e TypeScript; stack Node e **decisao vinculante do operador** (o `cstk serve` ja traz Node) | Reimplementar o protocolo MCP em POSIX sh: inviavel (JSON-RPC + schema validation em `sh` seria maior e mais fragil que o servidor inteiro) |
| **Dep `docker` passa a ser referenciada em 2 arquivos** — `serve-docker.sh` (existente) e `mcp-docker.sh` (novo) | A condicao (b) do carve-out 1.1.0 exige confinamento "em UM unico arquivo identificavel". A leitura **por feature** (cada feature confina seu uso em um arquivo) tem precedente: `cstk serve` fez exatamente isso | Extrair um `cli/lib/docker-common.sh` compartilhado: refatoraria codigo de uma feature ja entregue e estavel, aumentando o raio da mudanca. **RECOMENDACAO AO OPERADOR**: confirmar que a leitura "um arquivo por feature" e aceita; se a leitura for "um arquivo por dep no repo inteiro", isto exige **amendment** (MINOR) antes de F5 — nao ha opt-out tacito de MUST (Decision Framework item 4) |
| Atomicidade por compensacao, nao por transacao | Backup e hash sao efeitos **fora** do banco; `close_wave` precisa ser all-or-nothing observavel nos dois backends | Transacao SQLite unica: nao alcanca arquivos externos e nao existe no backend `json` |

## Riscos

| # | Risco | Prob. | Impacto | Mitigacao |
|---|-------|-------|---------|-----------|
| 1 | Subagente **nao** consegue chamar tools MCP | media | **fatal** — feature sem consumidor | Spike S1 e o **primeiro** item de trabalho; falha ⇒ bloqueio humano imediato, antes de qualquer codigo |
| 2 | Registro de servidor so vale na proxima sessao | media | alto | Desenho ja imune (entrada **estatica** + resolucao lazy — D2); spike S3 confirma |
| 3 | Helpers POSIX divergem sob busybox | media | medio | Spike S5; escape hatch = `node:22-slim` (custo de tamanho, nao de desenho) |
| 4 | Dois caminhos de escrita (MCP + Bash) intercalam | baixa | alto | D4: ambos dentro do mesmo lock do pai; + `busy_timeout`/retry/WAL no banco |
| 5 | Divergencia silenciosa de campo na borda tool↔helper | **alta** | medio | Scenario 9 (roundtrip real, todos os opcionais, dois backends) |
| 6 | Roteamento de mutacao pela execucao "ativa" atingir a execucao errada (confused deputy) | media | alto | **SEC-H3**: roteamento por token de capacidade, fail-closed; precedencia so em consulta read-only. Cenario 6 do quickstart cobre |
| 7 | Comprometimento do servidor escalar para o host via `.claude` | baixa | **critico** | **SEC-H2**: bind-mount de arquivo unico + teste estatico de montagens proibidas |

## Re-check de Constitution (pos-Phase 1)

O design **nao** introduziu complexidade alem da ja tabulada: zero tabela nova,
zero regra de estado duplicada, zero lock novo, zero porta de rede. Os principios
NON-NEGOTIABLE (I, II, IV, VI) permanecem **PASS**, com **uma ressalva formal
levada ao operador**: a leitura da condicao (b) do carve-out 1.1.0 para a dep
`docker` (§Complexity Tracking, linha 2). Se a leitura correta for "um arquivo
por dep no repo inteiro", a conformidade exige amendment MINOR **antes** da F5 —
e nao ha opt-out tacito para MUST.

## Bloqueio humano aberto nesta onda

O gate `owasp-security` e **obrigatorio** nesta pipeline e achados HIGH exigem
decisao humana. Os controles ja foram aplicados aos artefatos (secao §Seguranca);
o que vai ao operador sao as **duas consequencias arquiteturais** que extrapolam o
plano tecnico:

1. **SEC-H3 muda o contrato do command pai**: `/agente-00c` e `/feature-00c`
   (e resumes) passam a gerar um token de capacidade e injeta-lo no spawn do
   orquestrador. Isso toca arquivos fora desta feature.
2. **SEC-H3 tensiona a leitura literal de FR-016** ("sua propria instancia/porta
   isolada"), ja marcada como interpretacao [PROPOSAL] em research.md D2: o
   isolamento passa a ser por container + capacidade, sem porta.

Some-se a ressalva ja registrada em §Complexity Tracking (leitura da condicao (b)
do carve-out 1.1.0 para a dep `docker` em 2 arquivos), que pode exigir amendment
MINOR antes da F5.

## Proximos passos

1. `/checklist` — quality gate dos requisitos antes de decompor
2. `/create-tasks` — backlog, com **F0 (spikes) como fase 1 e bloqueante**
3. `/analyze` — consistencia cross-artifact apos as tasks
