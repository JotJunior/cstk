# Data Model: delivery-tier

A feature nao introduz banco, tabela nem coluna. As "entidades" abaixo
sao: um campo escalar do estado da execucao, uma tabela de referencia
versionada em texto, e um valor derivado (nunca persistido).

Nada aqui e afirmado como existente sem fonte: campos e colunas ja
existentes citam path + linha; o que e novo esta marcado
`[NOVO — a criar]`.

---

## Entity: DeliveryTier (enum)

Finalidade declarada do produto. Conjunto FECHADO de 4 tokens estaveis,
literais de `spec.md` FR-001.

| Token | Ordinal (derivado) | Significado (texto da opcao ao operador) |
|---|---|---|
| `local` | 1 | Uso local, para resolver problemas rapidamente |
| `internal-network` | 2 | Sistema compartilhado na rede interna, para poucos colegas |
| `cloud-internal` | 3 | Sistema publicado em nuvem, somente para uso interno |
| `cloud-public` | 4 | Sistema publicado em nuvem, para uso publico |

**Ordem**: `local < internal-network < cloud-internal < cloud-public`,
por profundidade crescente de entrega (`spec.md` §Key Entities).

**Default**: `cloud-public` (ordinal 4 — profundidade plena). E o valor
aplicado em ausencia de resposta, resposta invalida, execucao
nao-interativa (FR-003) e estado legado sem o campo (FR-010). O default
aponta deliberadamente para o **maximo** de rigor: errar para mais e
zero-regressao, errar para menos seria degradar silenciosamente.

**Divisao binaria nuvem/nao-nuvem** (dec-013, consumida por FR-006):

| Grupo | Tokens | Efeito no backlog |
|---|---|---|
| nao-nuvem | `local`, `internal-network` | omite fases de infra de producao |
| nuvem | `cloud-internal`, `cloud-public` | backlog completo |

**Carve-out de seguranca dentro da omissao (MUST)** — origem: gate
`owasp-security`, finding **F4 (MEDIUM)**, OWASP A09 (Logging Failures).
"Observabilidade de producao" e **logging de seguranca** sao coisas
distintas e a omissao so alcanca a primeira:

| Categoria | Omitivel em `local` / `internal-network`? |
|---|---|
| Dashboards, SLO/SLI, APM, tracing distribuido, alertas de capacidade | **Sim** — e observabilidade de producao |
| Deploy em nuvem, autoescalabilidade, multi-regiao, CDN | **Sim** |
| Log de autenticacao/autorizacao, trilha de auditoria, registro de acesso a dado sensivel | **NAO — nunca omitido** |

Motivo: `internal-network` e, por definicao da propria opcao, um sistema
**compartilhado entre pessoas**. Um sistema multiusuario sem trilha de
autenticacao/autorizacao e A09 direto, e FR-007 proibe o tier de reduzir
postura de seguranca. O tier reduz **escala operacional**, nunca
**rastreabilidade de seguranca**.

### Ordinal — derivado, nunca persistido

O ordinal existe apenas para comparar elevacao vs rebaixamento (FR-009).
E funcao pura do token, resolvida em memoria pelo helper. Persistir o
ordinal criaria um segundo campo capaz de divergir do token
(research.md Decision 3).

### State transitions

```
(init: token escolhido, default cloud-public)
        |
        |  elevacao (ordinal cresce) — permitida
        v
   tier maior  ────────────────────────────> aplica das ondas SEGUINTES
        |
        |  rebaixamento (ordinal diminui)
        v
   RECUSADO (exit 2, nada escrito)
        |
        |  + --allow-downgrade (decisao manual explicita do operador)
        v
   tier menor ─────────────────────────────> aplica das ondas SEGUINTES
```

Invariante (FR-009): nenhuma transicao reprocessa artefato ja gerado. O
helper altera **somente** estado; spec/plan/tasks ja escritos permanecem
como estao.

---

## Entity: campo de estado `.delivery_tier`

| Campo | Tipo | Nivel | Obrigatorio | Default |
|---|---|---|---|---|
| `delivery_tier` | string (1 dos 4 tokens) | **top-level** do documento de estado | nao (ausente = legado) | `cloud-public` |

**Nivel top-level, nao dentro de `.execution`**: espelha os dois campos
gemeos ja existentes. Verificado em
`plugins/cstk/skills/agente-00c-runtime/scripts/state-rw.sh:519-520`,
onde `atomic_commit_enabled` e `roadmap_mode_enabled` sao emitidos como
irmaos de `.execution`, nao como filhos.

### Persistencia por backend

| Backend | Onde mora | Fonte |
|---|---|---|
| JSON | chave de topo em `state.json` | template `jq` do `init`, `state-rw.sh:500-521` |
| SQLite | chave dentro da coluna `extra_fields` de `execution` | catch-all declarado em `references/state-db-schema.sql:69` |

**Nao ha coluna dedicada** e **nao ha alteracao de DDL**
(research.md Decision 1, confirmado por probe: `PRAGMA
table_info(execution)` nao lista `delivery_tier`; `SELECT extra_fields`
retorna `{"roadmap_mode_enabled":false,"delivery_tier":"local"}`).

O `read` sob SQLite remonta o campo no nivel de topo via merge
`($ext + $core)` (`_state-rw-db.sh:361-367`), de modo que `get`/`read`
devolvem o **mesmo documento** nos dois backends — a diferenca de
armazenamento e invisivel a todos os consumidores.

### Escrita

| Momento | Mecanismo | Ref |
|---|---|---|
| init | flag `--delivery-tier <token>` `[NOVO — a criar]` | espelha `--atomic-commit` / `--roadmap-mode`, `state-rw.sh:361-372` |
| entre ondas | `delivery-tier.sh set` `[NOVO — a criar]` | contrato em `contracts/cli-delivery-tier.md` |

### Leitura (contrato de FR-010)

**Consumidores leem SEMPRE via `delivery-tier.sh get`** — nunca o campo
cru. Regra normativa em `contracts/cli-delivery-tier.md` INV-5 (finding
F6 do gate de seguranca): o helper **coage** a saida ao enum de 4 tokens,
enquanto a leitura crua devolveria qualquer texto presente no estado, que
depois seria interpolado na string `args` de invocacao de skills (FR-004)
— um canal de injecao de prompt.

Dentro do helper, a leitura usa fallback no proprio `jq path`, jamais
assumindo presenca:

```
.delivery_tier // "cloud-public"
```

Mesma forma defensiva de `commit-mode.sh` (`is-enabled`), que le
`.atomic_commit_enabled // false` e degrada para o default em qualquer
falha. Consequencia: estado legado **nao precisa de migracao de dados** —
a ausencia ja significa `cloud-public`.

**Duas camadas, nao uma**: o `//` cobre ausencia; a coercao ao enum cobre
presenca com valor invalido (corrompido ou adulterado). Ausencia e
malformacao convergem para o mesmo default seguro.

### Validacao

`state-validate.sh` `[MOD]`: aceita **um dos 4 tokens OU ausente**;
qualquer outro valor vira erro de validacao. Espelha o bloco existente
para `atomic_commit_enabled` (`state-validate.sh:193-201`), onde `null`
(= ausente) e explicitamente valido.

---

## Entity: MatrizTierGate (tabela de referencia)

`[NOVO — a criar]`
`plugins/cstk/skills/agente-00c-runtime/references/tier-gate-map.txt`

Mapeamento versionado de qual modo de execucao um quality gate
complementar assume em cada tier.

| Campo | Tipo | Valores | Notas |
|---|---|---|---|
| `tier` | string | os 4 tokens de DeliveryTier | 1o campo da linha |
| `gate` | string | nome do gate | 2o campo |
| `modo` | enum | `completo` \| `leve` \| `skip` | 3o campo |

**Formato**: texto puro, 3 campos por linha separados por `|`, `#` e
linhas vazias ignoradas, versao declarada como comentario na 1a linha.
Identico a `references/phase-model-map.txt` (formato completo em
`contracts/tier-gate-map.md`).

**Conteudo de dados v1** — 4 linhas, exclusivamente `owasp-security`
(dec-012):

| tier | gate | modo |
|---|---|---|
| `local` | `owasp-security` | `skip` |
| `internal-network` | `owasp-security` | `leve` |
| `cloud-internal` | `owasp-security` | `completo` |
| `cloud-public` | `owasp-security` | `completo` |

**Fail-safe estrutural (FR-005)**: par `(tier, gate)` ausente da tabela
resolve para `completo`, exit 0. Os gates `checklist`,
`validate-documentation`, `validate-docs-rendered` e `analyze`
**deliberadamente nao tem linha** — rodam completos nos 4 tiers por
consequencia do fail-safe, nao por regra escrita. dec-012 vira assim uma
propriedade estrutural da tabela, verificavel por `grep`.

### Relationships

```
DeliveryTier (1) ──< MatrizTierGate >── (1) Gate
                       modo: completo | leve | skip
```

- `DeliveryTier` 1:N `MatrizTierGate` via campo `tier`.
- Par `(tier, gate)` e a chave natural; ausencia da chave e valida e
  significa `completo`.
- Nao ha integridade referencial imposta por codigo (e um arquivo texto):
  linha com tier fora do enum simplesmente nunca casa, e o gate cai no
  fail-safe. Falha na direcao segura.

---

## Nao-entidades (fora de escopo, deliberadamente)

Registrado para impedir expansao silenciosa de escopo:

| Item | Por que nao entra |
|---|---|
| Coluna `delivery_tier` em `state.db` | research.md Decision 1 — catch-all `extra_fields` cobre; nao ha mecanismo de migracao de DDL neste banco |
| Campo `tier` na `knowledge.db` / `executions` | precedente `roadmap_mode_enabled` nao tocou `cli/lib/recall.sh` (zero ocorrencias) |
| Tool MCP para mutar o tier | campo nao mutavel por tool; fora do mapper de paridade |
| Entidade de tier no `/feature-00c` | dec-011 — escopo restrito ao `/agente-00c` |
| Ordinal persistido | derivado do token (Decision 3) |
| Relacao tier -> modelo (routing) | fora de escopo por decisao do operador (`spec.md` §Contexto) |
