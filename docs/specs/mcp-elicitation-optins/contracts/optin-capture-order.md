# Contract: ordem de captura dos opt-ins (command pai ↔ orquestrador)

Contrato de **ordem de execucao** entre o slash command pai e o orquestrador
subagente. E o entregavel central de FR-012 (init em duas etapas) e de FR-005
(fallback integral para prosa).

> **Constitution VI**: a ordem ATUAL (§1) e **VERIFICADA** por numero de linha.
> A ordem NOVA (§2/§3) e **[PROPOSTA — a validar na implementacao]**.

---

## 1. Ordem ATUAL (VERIFICADA — linha de base)

Evidencia literal de `plugins/cstk/commands/feature-00c.md` (dec-030):

| Linha | Passo |
|-------|-------|
| 642 | `# Prompt opt-in de commit atomico (FR-001/FR-002 — atomic-commit-pr)` |
| 684 | `state-rw.sh init --state-dir ...` |
| 697 | `### 3.bis Ciclo de vida do servidor MCP (status/start)` |
| 713 | `cstk mcp start --state-dir "$AGENTE_00C_STATE_DIR"` |
| 747 | `### 4. Selecionar modelo da onda + delegar ao orquestrador via Agent` |
| 777 | `subagent_type: "agente-00c-feature-orchestrator"` |

Resumo: **prosa → init (com flags) → mcp start → spawn**. Os opt-ins sao
capturados por prosa **antes** do init e viram flags de init
(`state-rw.sh:371-386`).

---

## 2. Decisao de ramo (o pai decide ANTES do init)

**[PROPOSTA]**. O pai escolhe o ramo com um sinal que ele **pode** obter sem
tool MCP — o descritor/token da sessao. Discriminador **real** (dec-034):
token vazio / descritor ausente, **nunca** o literal `mode=bash-fallback`
(que `_mcp_write_descriptor` jamais grava — VERIFICADO: `mcp.sh:708-709`,
`mcp.sh:100-107`).

| Sinal | Ramo | Comportamento observado pelo operador |
|-------|------|----------------------------------------|
| descritor ausente / `_mcp_token` vazio | **LEGADO** (§4) | identico a hoje; **nenhum** aviso (FR-005, US3-1, SC-005) |
| token presente | **ESTRUTURADO** (§3) | formulario, com degradacao conforme §3.3 |

O padrao de leitura do token ja existe e e VERIFICADO:
`feature-00c.md:741-742` — "`_mcp_token` vazio (bash-fallback / sem descritor)
=> NAO mencione MCP no prompt".

---

## 3. Ramo ESTRUTURADO — init em duas etapas

### 3.1 Sequencia

**[PROPOSTA]**:

| # | Ator | Acao | Fundamento |
|---|------|------|------------|
| 1 | pai | `state-rw.sh init` **sem** `--atomic-commit` / `--roadmap-mode` / `--delivery-tier` | FR-012 etapa (1): defaults seguros `false`/`false`/`cloud-public` |
| 2 | pai | (implicito no init) `.execution.status = em_andamento` | **pre-requisito duro** — sem status ativo o token e recusado com `SESSION_MISMATCH` (VERIFICADO: `mcp-session.sh:25-32`) |
| 3 | pai | `cstk mcp start --state-dir <SD>` | **cunha o token**; NAO sobe processo (VERIFICADO: `mcp.sh:22-30`) |
| 4 | pai | spawn do orquestrador com instrucao explicita de captura | dec-030: so o orquestrador porta as tools |
| 5 | orq. | `mcp__cstk-state__collect_optins` — **primeiro ato**, ANTES de `state-ondas.sh start` | FR-012: nenhuma onda aberta |
| 6 | orq. | prossegue ao Loop principal (passo 3.bis abre a onda-001) | — |

**Invariante O-1**: o passo 5 ocorre **antes** de qualquer
`state-ondas.sh start`. Duas consequencias verificadas:
- FR-012 satisfeito ao pe da letra ("antes de qualquer onda comecar");
- a guarda **write-once** de `roadmap-mode.sh:142` (recusa quando ja ha onda
  com etapa posterior a `constitution`) nunca e acionada.

**Invariante O-2**: os 3 blocos de prosa do pai sao **pulados** neste ramo —
sao a alternativa exclusiva, nunca somados ao formulario (senao o operador
responderia duas vezes; US3-2 proibe perguntar duas vezes).

### 3.2 Retomada (`*-resume`)

**[PROPOSTA]**. Comportamento identico ao dos opt-ins de prosa hoje: **nao
re-perguntar**. O orquestrador chama `collect_optins` normalmente; a tool
detecta os registros existentes em `.optin_responses[]` e retorna `reused`
sem emitir `elicitation/create` (FR-008 + FR-011). A idempotencia mora na
**tool**, nao na prosa do command — assim vale para os dois caminhos de
retomada sem duplicar regra.

### 3.3 Degradacao dentro do ramo estruturado

**[PROPOSTA]**. Dois sub-casos, com tratamentos distintos:

**(a) Sem operador / recusa / teto de tempo** (`absent`, `declined`,
`timeout`): defaults seguros ja vigentes, registro gravado, **execucao
prossegue sem pausa**. Nao ha volta a prosa — perguntar de novo contrariaria
FR-007/SC-002. VERIFICADO como consistente com FR-006 (nenhum default muda).

**(b) Mecanismo indisponivel ou quebrado** (`unavailable`, `failed`): FR-005
exige que a captura aconteca **pela prosa**. Como o orquestrador e subagente e
nao consegue resposta interativa dentro do proprio turno, a prosa MUST rodar no
**pai**. Protocolo de retorno:

1. o orquestrador **nao abre onda**, encerra o turno imediatamente;
2. o pai le o estado — `.optin_responses[]` com `outcome ∈ {unavailable, failed}` —
   via `state-rw.sh get`. **Sinal estrutural, nao texto**: o pai nunca
   interpreta o sumario do subagente (mesma disciplina de "fonte de verdade e o
   state");
3. o pai executa os blocos de prosa existentes (FR-005, texto inalterado);
4. o pai persiste via `commit-mode.sh set-enabled` / `roadmap-mode.sh set-enabled`
   / `delivery-tier.sh set [--allow-downgrade]` (**nao** por flags de init — o
   estado ja existe), e grava os registros com `channel: "prose"`. A flag do
   tier segue a **mesma regra condicional** da invariante C-2
   (`mcp-tool-collect-optins.md`, dec-047): so quando o operador escolheu
   explicitamente um tier de ordinal **menor** que o vigente. O canal muda
   (`prose` em vez de `structured`); a regra de consentimento, nao;
5. o pai re-spawna o orquestrador; a onda-001 comeca com todos os valores
   confirmados.

**Custo**: um round-trip de spawn adicional **apenas** no ramo degradado.
**Ganho**: FR-005, FR-007, FR-012 e SC-002 satisfeitos simultaneamente, sem
depender de nenhuma premissa nao verificada.

**Aviso em stderr** (FR-009 / SC-005): **exatamente uma** linha, e **somente**
no sub-caso `failed`. `unavailable` e silencioso — o mecanismo nunca esteve
disponivel, entao a experiencia MUST ser indistinguivel do ramo LEGADO.

---

## 4. Ramo LEGADO — inalterado (FR-005, zero regressao)

**[PROPOSTA: nenhuma mudanca]**. Quando o token esta ausente, a sequencia
VERIFICADA de §1 permanece **byte-a-byte** como hoje: prosa antes do init,
flags no init, nenhum aviso, nenhuma tentativa visivel de usar o mecanismo
novo.

Regressao a evitar: mover os blocos de prosa para depois do init "para
uniformizar os dois ramos". Isso mudaria o comportamento observavel do ramo
que FR-005 protege — e o ramo LEGADO nao tem motivo estrutural para mudar
(nao ha servidor a esperar).

---

## 5. Correcao de comentarios stale (dec-034)

Defeito colateral que esta feature MUST corrigir, por tocar exatamente estas
linhas:

| Arquivo:linha | Afirmacao stale | Correcao |
|---------------|-----------------|----------|
| `plugins/cstk/commands/feature-00c.md:711` | `start` degrada para `mode=bash-fallback` | `start` grava **sempre** `mode=direct`; o discriminador e token vazio / descritor ausente |
| `plugins/cstk/commands/agente-00c.md:470` | idem | idem |

Fonte da correcao (VERIFICADO): `mcp.sh:100-107` ("reservado ... nao ha
caminho de codigo atual que o produza"), `mcp.sh:1076`, `mcp.sh:708-709`.

**Regra dura**: nenhum teste desta feature pode asserir a string
`mode=bash-fallback` — seria assercao sobre valor que o codigo nunca emite.

---

## 6. Revogacao da clausula normativa (dec-028/dec-032, refinado)

Bloco `<!-- MCP-VS-BASH:BEGIN/END -->`, item 8, **duplicado** em
`agente-00c-feature-orchestrator.md:175-177` e `agente-00c-orchestrator.md:187`
(VERIFICADO).

**Texto atual** (VERIFICADO, literal): "`elicitation/create` permanece FORA de
escopo de uso ativo enquanto FR-010 estiver Deferred (fonte pendente de
sondagem empirica externa) — nao invoque nenhuma tool MCP que dependa dela sem
essa definicao."

**Reescrita [PROPOSTA]** — **narrowing**, nao delecao. MUST:

1. **preservar o literal `elicitation/create`** (ver §6.1);
2. permitir explicitamente o recorte desta feature: captura de opt-ins de
   inicio de execucao **com operador presente**, via `collect_optins`, antes da
   abertura da onda;
3. **manter diferido** o recorte que a spec desta feature declara fora de
   escopo (Edge Cases): elicitation a partir de subagente orquestrador **sem
   operador humano presente** (`orchestrator-mcp-allowlist` FR-010);
4. ser aplicada **simetricamente** nos dois orquestradores.

### 6.1 O guard nao quebra — ele fica cego (correcao a dec-032)

dec-032 registra que editar a prosa sem tocar o teste "quebra a suite". A
leitura literal do teste mostra que isso vale **apenas se a reescrita remover o
literal**. A assercao e uma unica linha de presenca de token
(VERIFICADO, `tests/test_orchestrator-allowlist-guard.sh:489`):

```sh
printf '%s\n' "$_body" | grep -qF 'elicitation/create' || _missing_items="$_missing_items item8"
```

Os itens vizinhos (`:482-490`) seguem o mesmo padrao de presenca de string
(`'Quando preferir MCP'`, `'0 retries'`, `'NUNCA pausa a onda'`, ...).

**O risco real e o inverso**: uma reescrita que **inverta a semantica** e
**mantenha** o literal continua **verde**, e a suite passa a afirmar um item
cujo significado mudou — sem sinal algum.

**Entregavel obrigatorio, no MESMO commit**: fortalecer a assercao do item 8
para verificar os **dois** recortes (permitido: operador presente; diferido:
sem operador presente), nos dois orquestradores. Nao e "consertar teste
quebrado" — e fechar uma cegueira de assercao introduzida pela propria
revogacao.
