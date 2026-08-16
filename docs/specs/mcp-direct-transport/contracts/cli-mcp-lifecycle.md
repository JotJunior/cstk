# Contrato: `cstk mcp` (lifecycle apos o cutover)

**Feature**: `mcp-direct-transport` | **Phase**: 1 | **Date**: 2026-08-16

Cobre FR-006, FR-007, FR-008, FR-010, FR-014, FR-015.

## Etiquetas

- **[REAL]** — contrato vigente, com fonte citada.
- **[PROPOSTA — a validar na implementacao]** — mudanca desta feature.

---

## 1. Contrato de saida vigente [REAL]

Fonte: cabecalho de `cli/lib/mcp.sh:69-94`.

**stdout — uma chave por linha** (mesmo estilo de `state-backend.sh resolve`):

```
status=active|stopped|unavailable
reason=<motivo>            # presente quando != active
container=<nome>|-
session_id=<id>|-
mode=docker|bash-fallback|-
```

**Exit codes** [REAL]:

| Subcomando | Code | Significado |
|------------|------|-------------|
| `status` | 0 | consulta bem-sucedida (**inclusive `status=unavailable`** — nao e erro) |
| `status` | 1 | erro inesperado (path invalido) |
| `status` | 2 | uso incorreto |
| `start`/`stop` | 0 | sucesso (`start`: modo ativo; `stop`: parado ou ja estava parado) |
| `start`/`stop` | 1 | erro inesperado (jq ausente, `--state-dir` invalido, IO) |
| `start`/`stop` | 2 | uso incorreto |
| `start` | 3 | indisponivel: `mode=bash-fallback` gravado — **nao e erro fatal**, o pai segue pelo caminho Bash |

---

## 2. `cstk mcp start` — onde esta o trabalho

### 2.1 Fluxo atual [REAL]

```
preflight docker → build imagem → docker run → healthcheck → descritor mode=docker
      │                │              │             │
      └─ falha ────────┴──────────────┴─────────────┴──▶ descritor mode=bash-fallback + exit 3
```

Motivos de fallback gravados hoje [REAL]: `mcp.sh:583` (preflight),
`:601` (`server-source-missing`), `:615` (`image-build-failed`), `:656`
(`container-start-failed`), `:671` (`health-timeout`).

### 2.2 Fluxo contratado [PROPOSTA — a validar na implementacao]

```
resolver state-dir → gerar/reusar token → gravar descritor mode=direct → exit 0
```

| Regra | Requisito | FR |
|-------|-----------|-----|
| S-1 | MUST concluir com sucesso em maquina **sem** motor de containers | FR-006 |
| S-2 | MUST gravar descritor com token + metadados, **sem** `mode=docker` nem `container_name` | FR-006, clarify dec-011 |
| S-3 | MUST ser idempotente: chamado de novo para execucao com sessao ativa, **reusa** — nao duplica processo nem invalida a sessao em curso | FR-010, SC-005 |
| S-4 | MUST detectar descritor legado `mode=docker`, **avisar em stderr** e sobrescrever — nunca falhar por causa de estado legado | FR-014, clarify dec-015 |
| S-5 | O `start` MUST NOT iniciar processo algum — o processo do servidor e criado pelo **harness** ao conectar o `.mcp.json` (research Decision 10) | FR-012 |

> **S-5 e a mudanca conceitual mais facil de errar.** Apos o cutover,
> `cstk mcp start` deixa de "subir servidor": ele **prepara a sessao**
> (descritor + token). Quem cria o processo e o harness. E por isso que
> S-1 e satisfeito trivialmente — nao ha nada para subir.

### 2.3 Exit code 3 apos o cutover [PROPOSTA]

O `bash-fallback` **nao desaparece**: continua sendo o caminho quando a
sessao nao pode ser preparada (ex.: `state-dir` invalido, IO). O que
desaparece sao os 5 motivos **especificos de Docker** listados em 2.1.

| Regra | Requisito |
|-------|-----------|
| S-6 | O contrato de exit code (0/1/2/3) MUST ser preservado integralmente — commands pai ja o consomem |
| S-7 | Motivos de fallback especificos de Docker MUST sair junto com o caminho Docker |

---

## 3. `cstk mcp status` — no-change funcional

| Fato [REAL] | Fonte |
|-------------|-------|
| O healthcheck de container e guardado por `--live` **e** `mode=docker` | `mcp.sh:349` `if [ $_live = 1 ] && [ $_mode = docker ] && [ $_container != - ]` |
| Sem `mode=docker`, o bloco e pulado e o status ja vem do descritor | idem |

| Regra | Requisito | FR |
|-------|-----------|-----|
| ST-1 | MUST reportar o estado real (ativa/parada/indisponivel) sem inspecionar container | FR-007 |
| ST-2 | O guard de `mcp.sh:349` **ja satisfaz** FR-007 para sessoes novas — **nenhuma mudanca funcional necessaria** | FR-007 |
| ST-3 | `--live` MUST permanecer aceito (compatibilidade); vira no-op para `mode=direct` | — |

---

## 4. `cstk mcp stop` — no-change funcional

| Fato [REAL] | Fonte |
|-------------|-------|
| `docker stop` e condicionado a `mode=docker` | `mcp.sh:731` `if [ $_msp_mode = docker ] && [ $_msp_container != - ] && [ -n $_msp_container ]; then` |
| Sem esse branch, a gravacao de `stopped_at` acontece identica | mesma funcao |

| Regra | Requisito | FR |
|-------|-----------|-----|
| SP-1 | MUST encerrar a sessao sem depender de parar container | FR-008 |
| SP-2 | MUST ser idempotente para sessao ja parada | FR-008 |
| SP-3 | **FR-008 ja passa hoje sem Docker** — o branch guardado e a unica dependencia | FR-008 |
| SP-4 | Apos `stop`, chamadas de tool com aquele token MUST ser rejeitadas | US2 cenario 3; garantido por `mcp-session.sh:130` |

---

## 5. `cstk mcp gc` — NAO vira no-op

| Fato [REAL] | Fonte |
|-------------|-------|
| Ja degrada com summary e **exit 0** quando o preflight Docker falha | `mcp.sh:805-808` `if ! _mcp_docker_preflight 2>/dev/null; then printf summary=docker-indisponivel examined:0 removed:0 kept:0 skipped:0; return 0` |

| Regra | Requisito | FR |
|-------|-----------|-----|
| G-1 | MUST **continuar** detectando e removendo containers orfaos `cstk-mcp-state-*` de sessoes pre-cutover | FR-015, clarify dec-015 |
| G-2 | MUST NOT virar no-op — apenas deixa de ter containers **novos** para gerenciar | FR-015 |
| G-3 | MUST manter a degradacao com exit 0 quando Docker esta ausente | [REAL] preservado |

> **Por que `gc` sobrevive a remocao do Docker**: e a unica via de limpeza
> do **passivo** deixado pela feature anterior. Sobrescrever descritores
> legados em silencio (sem `gc`) deixaria containers orfaos permanentes —
> a razao explicita de clarify dec-015 ter ajustado dec-011.

### 5.1 Tensao de desenho a resolver na implementacao

| Fato | Tensao |
|------|--------|
| FR-015 exige que `gc` continue removendo containers | `gc` **precisa** de codigo Docker |
| research Decision 11 remove `cli/lib/mcp-docker.sh` | onde vive o codigo Docker que `gc` ainda usa? |

**[PROPOSTA — a validar na implementacao]**: preservar em `mcp.sh` **apenas**
o minimo que `gc` consome (preflight + listagem/remocao por padrao de nome),
e remover de `mcp-docker.sh` o que so servia ao `start` (build de imagem,
`docker run` com montagens, healthcheck). A alternativa — manter
`mcp-docker.sh` inteiro so pelo `gc` — conservaria justamente o codigo de
`run`/`build` que o cutover existe para eliminar.

> Esta e a decisao de fronteira mais delicada da implementacao e MUST ser
> validada com o codigo em maos: o recorte exato entre "o que `gc` usa" e
> "o que so o `start` usava" nao foi verificado linha a linha nesta fase.

---

## 6. `cstk mcp install` — no-change

| Regra | Requisito |
|-------|-----------|
| I-1 | A entrada `mcpServers.cstk-state` do `.mcp.json` permanece **estatica**, sem bloco `env` — [REAL] heredoc `MCPJSON` |
| I-2 | Injetar o token via `env` no `.mcp.json` e **explicitamente proibido** (research Decision 8): arquivo escrito uma vez por projeto, token muda a cada `start`, e versionar token contraria SEC-H3/US3 |
| I-3 | Roda **uma vez por projeto**, nao por execucao — [REAL] `mcp.sh:48-49` |

---

## 7. Injecao do token nos commands pai (FR-013)

| Fato [REAL] | Consequencia |
|-------------|--------------|
| `feature-00c.md:728` e `agente-00c.md:487` condicionam a injecao do token a `mode == "docker"` | apos o cutover **nenhuma** sessao nova grava `mode=docker` ⇒ o orquestrador **nunca** receberia `session_id` ⇒ toda chamada morreria em `SESSION_MISMATCH` |

| Regra | Requisito |
|-------|-----------|
| P-1 | A condicao `mode == "docker"` MUST ser removida/generalizada nos **dois** commands |
| P-2 | Criterio novo: injetar sempre que o descritor existir e tiver `session_id` valido, **independentemente de `mode`** |
| P-3 | Ambos MUST mudar no mesmo commit — deixar um so gera assimetria silenciosa entre `/agente-00c` e `/feature-00c` |

> **P-1 e o requisito mais facil de esquecer e o mais caro de esquecer.**
> Sem ele a feature fica no estado intermediario enganoso descrito em
> research Decision 13: `/mcp` lista as 7 tools (parece funcionar) e toda
> chamada e rejeitada (nao funciona).
