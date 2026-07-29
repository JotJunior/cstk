# Contracts: panel-docker — CLI `--docker` + contrato de container

Interface externa desta feature: a extensao do comando `cstk serve` com o modo Docker.
As flags EXISTENTES (`--port`, `--host`, `--update`, `--reinstall`, `--allow-unverified`,
`--help`) sao contrato REAL ja implementado (serve.sh L367-475). A flag `--docker` e o
container-run abaixo sao **[PROPOSTA — a validar na implementacao]** (Constituicao VI:
distinguir contrato afirmado como real de contrato desenhado do zero).

## Command: `cstk serve --docker`

**Dispatch**: `cli/cstk` `serve)` -> `serve_main "$@"` (L211-220, real). O parse de
`--docker` entra no laco `while/case` existente de `serve_main` (serve.sh L368-475).

### Flags (composicao)

| Flag | Origem | Semantica no modo Docker |
|------|--------|--------------------------|
| `--docker` | **[PROPOSTA]** | opt-in; ativa o modo container. Ausente = nativo intacto (FR-002) |
| `--port PORT` | real (L370-376) | porta publicada no host `-p 127.0.0.1:PORT:...`; inteiro 1024-65535 |
| `--host HOST` | real (L377-383) | lado host do `-p`; so `127.0.0.1` pleno, mesmo aviso (L510-517) |
| `--update` | real (L387) | re-baixa+verifica e **reconstroi a imagem** se houver release nova; senao reusa (best-effort) |
| `--reinstall` | real (L384) | **remove a imagem e reconstroi do zero**, incondicional |
| `--allow-unverified` | real (L390-393) | bypass de integridade no **download do painel** (host); mismatch nunca bypassa |
| `--help` | real (L394) | MUST documentar `--docker` + semantica docker de update/reinstall (FR-014) |

### Sequencia (contrato de alto nivel — nao codigo)

```
1. parse flags (inclui --docker)
2. validar porta (real, L486-508)
3. [FR-003] checar runtime de container ANTES de rede:
     3a. command -v docker falha        -> erro "docker nao instalado" (exit 1)
     3b. daemon inacessivel (sonda != 0) -> erro "daemon parado/inacessivel" (exit 1)  [FR-004]
4. resolver/baixar/verificar painel (reusa fluxo real: trusted-hosts + integridade
   fail-closed + extracao; SEM npm no host — FR-006)
5. (re)construir imagem local conforme --update/--reinstall (Decision 5)
6. reconciliar container remanescente pelo nome (docker rm -f, idempotente) [FR-012]
7. docker run (contrato abaixo)
8. trap host INT/TERM -> docker stop (grace ~5s) -> (--rm) remove [FR-011]
```

### Exit codes (paridade com nativo, serve.sh L434-438)

| Code | Condicao |
|------|----------|
| 0 | painel subiu / `--help` |
| 1 | docker ausente ou daemon down; download/integridade; build da imagem; run falhou |
| 2 | uso incorreto (porta invalida, flag desconhecida) |

### Erros (mensagens acionaveis, especificas do cstk — nunca erro cru do runtime)

| Condicao | Mensagem (contrato; texto exato `[a fixar]`) |
|----------|----------------------------------------------|
| docker nao instalado | aponta como instalar o runtime de container; nenhuma rede tentada antes (SC-006) |
| daemon inacessivel | DISTINTA da anterior (FR-004): "runtime instalado mas daemon parado/sem permissao" |
| porta em uso | diagnostico de porta ocupada (host ou container), acionavel |
| container remanescente irreconciliavel | mensagem cstk, nunca stack do runtime (US4 cenario 2) |
| integridade nao confirmada | mesmo texto/fluxo do nativo (L307-308) + como usar `--allow-unverified` |

## Contract: `docker run` (invocacao do container)

**[PROPOSTA — parametros exatos a fixar/testar em execute-task; nenhum valor inventado
alem dos defaults aterrados]**

| Parametro | Valor (contrato) | Fonte/Decision |
|-----------|------------------|----------------|
| nome | deterministico, ex. `cstk-panel` `[a fixar]` | FR-012 / Decision 6 |
| label | ex. `cstk.managed=serve` | Decision 6 |
| publish `-p` | `127.0.0.1:<porta-host>:<porta-container>` | Decision 4 |
| env `PORT` | porta interna do painel (config.ts L80) | Decision 4 |
| env `CSTK_KNOWLEDGE_DB` | `<target>/knowledge.db` | config.ts L49 / Decision 3 |
| volume `-v` | `<dir-cstk-host>:<target>:ro` (read-only) | FR-008/009 / Decision 3 |
| `--init` | PID 1 = tini (sinal + reaping) | Decision 6 |
| `--rm` | auto-remove ao parar | Decision 6 |
| hardening | `--cap-drop`/`--read-only`/`tmpfs` `[a validar]` | Decision 7 |
| imagem | tag LOCAL; **nunca** `docker push` | FR-013 |

### In-container (contrato do encaminhador — FR-005)

- Painel: `npm run start` (`node apps/server/dist/index.js`, package.json L13) faz bind
  em `127.0.0.1:<PORT>` (config.ts L81 — imutavel, nao se toca no cstk-panel).
- Encaminhador: escuta `0.0.0.0:<porta-container>` e repassa a `127.0.0.1:<PORT>`
  (mesmo netns). Ferramenta: `socat` recomendado; proxy Node como alternativa. Comando
  exato `[detalhe de execute-task]` (Decision 2) — NAO afirmado aqui.

### Invariantes de seguranca (gate owasp — sem finding critical/high; MEDIUM viraram defaults)

- knowledge.db exposto **somente leitura** (`:ro`) e restrito ao dir de dados do cstk;
  imagem **nao** contem o knowledge.db (montado em runtime).
- container roda como **usuario nao-root** (`USER node`).
- `--cap-drop ALL` + `--security-opt no-new-privileges` + rootfs `--read-only` (+ `tmpfs`)
  como default; **sem** `--privileged`, **sem** `CAP_NET_ADMIN`.
- porta no **loopback do host** por default (`127.0.0.1`); `--host` nao-loopback expoe na
  rede (mesmo caveat do nativo — documentar).
- base `node` fixada por **digest**; install do painel na imagem via **`npm ci`** (lockfile).
- trusted-hosts + integridade fail-closed preservados no download (host).
- **nenhum** push a registry remoto (FR-013 / Constituicao IV) — teste assegura ausencia
  de `docker push` no helper.
