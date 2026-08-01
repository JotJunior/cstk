# Contracts: `state-backend.sh` (runtime `agente-00c-runtime`)

Contrato do script que é a **fonte única** de leitura da configuração de backend
(Decision 2). O binário `cstk` **delega** a ele; não reimplementa nada do que está
aqui. É essa unicidade que torna SC-004 (0% de divergência entre os dois caminhos)
verdadeiro por construção.

> **STATUS: `[PROPOSTA — a validar na implementação]`**
> Este script não existe hoje. Verificado em 2026-08-01: não há nenhum
> `state-backend.sh` nem qualquer marcador de capability no runtime
> (`grep -rn "RUNTIME_VERSION\|_RUNTIME_VER\|CAPABILITY\|capability"` nos scripts
> de `global/skills/agente-00c-runtime/scripts/` não retorna resultado).
> Toda assinatura abaixo é projetada, não observada.

**Caminho projetado**:
`global/skills/agente-00c-runtime/scripts/state-backend.sh`
**Instalado em**: `$HOME/.claude/skills/agente-00c-runtime/scripts/state-backend.sh`
**Teste correspondente** (convenção do `CLAUDE.md`): `tests/test_state-backend.sh`

---

## Resolução do caminho pelo CLI

`cli/lib/config.sh` MUST resolver este script com o **mesmo resolvedor de três
camadas** já usado por `_state_migrate_script_path` em `cli/lib/state.sh`
(verificado L43-61):

1. `PATH` (via `command -v`);
2. layout de repo relativo a `CSTK_LIB`
   (`$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/`);
3. layout instalado (`$HOME/.claude/skills/agente-00c-runtime/scripts/`).

A camada (2) **não é opcional**: o comentário logo acima da função
(`cli/lib/state.sh:42`) registra a lição de campo que a motiva — testes e CI rodam
o CLI da árvore do repo sem ter o runtime em `~/.claude`, e resolver só via
`~/.claude` "passa local e quebra no CI fresh-checkout" (mesma licão de
`recall_secrets_filter_path` em `cli/lib/recall.sh`).

---

## Subcommand: `capability`

Reporta que este runtime suporta o backend configurável. É o alvo da checagem
ativa exigida por FR-004A.

**Invocação**: `state-backend.sh capability`

| Saída | Condição |
|-------|----------|
| stdout: token de capability versionado; exit 0 | Runtime suporta backend config |
| exit não-zero | Subcomando não reconhecido (runtime intermediário) |

**Ausência do arquivo** é o terceiro sinal — e o mais comum: um runtime anterior a
esta feature simplesmente não tem o script. O chamador MUST tratar os três casos
(arquivo ausente / subcomando não reconhecido / token abaixo do mínimo) como a
mesma decisão: **recusar a ativação** com o diagnóstico de FR-004A.

---

## Subcommand: `resolve`

Resolve qual backend uma **nova** inicialização usaria agora, considerando config
e dependências. É o núcleo compartilhado por `cstk doctor --deps` e por
`state-rw.sh init` — a mesma resposta para os dois, por construção.

**Invocação**: `state-backend.sh resolve`

| Saída | Descrição |
|-------|-----------|
| stdout | Backend efetivo (`sqlite` ou `json`) e o motivo (domínio de `reason` em `data-model.md`) |
| exit 0 | Resolução concluída — **inclusive** quando o resultado é o fallback `json` |

**Contrato de não-falha**: `resolve` **nunca** falha por config ausente ou
inválida (FR-008). Config ilegível ⇒ resultado `json` com motivo
`config-invalida`, exit 0. Falhar aqui quebraria a inicialização de qualquer
projeto cujo arquivo de config tenha sido editado à mão — desproporcional a uma
configuração opcional.

---

## Subcommand: `enable-sqlite`

Implementa a ativação. É o alvo da delegação de `cstk state enable-sqlite`; o
contrato de operador (pré-condições, idempotência, diagnósticos, exit codes) está
em [`cli-surface.md`](./cli-surface.md) e não é duplicado aqui.

**Invocação**: `state-backend.sh enable-sqlite`

Este é o **único** subcomando que escreve. `capability` e `resolve` são
estritamente read-only.

---

## Consumo por `state-rw.sh init`

`state-rw.sh init` MUST consultar a resolução acima **antes** de decidir o que
criar, e honrá-la (FR-005).

### Comportamento resultante

| Resolução | `init` cria |
|-----------|-------------|
| `json` (qualquer motivo) | `state.json` — comportamento atual, inalterado |
| `sqlite` | `state.db`, via `state-db-schema.sh create --db <state-dir>/state.db` + população da execução |

### Guardas existentes preservadas

Ambas verificadas em `state-rw.sh` e **mantidas**:

- **L390-395** — `init` recusa quando `state.db` já existe. Continua válida e
  necessária: protege contra criar um `state.json` paralelo num projeto já
  migrado, que nunca seria a fonte de verdade (C2/Decision 9 da Fase 1).
- **L397-400** — `init` recusa quando `state.json` já existe.

A mudança desta feature é sobre **qual arquivo `init` cria quando não existe
nenhum**. Nenhuma guarda é relaxada.

### Por que `init` cria o `state.db` diretamente (e não via migração)

`state-db-migrate.sh:202-204` recusa a migração quando
`.execution.status = em_andamento`, e `init` escreve exatamente esse status. Um
`state.json` recém-criado seria portanto **sempre** recusado pela migração
(exit 3). Detalhamento em [`../research.md`](../research.md) Decision 3.

---

## Contrato de parsing (vinculante — ver plan.md §Superfície de segurança)

Cláusulas obrigatórias para qualquer implementação de `resolve`:

| # | Cláusula |
|---|----------|
| P1 | **MUST NOT** usar `.` / `source` / `eval` sobre o arquivo de config. Um arquivo `key=value` é shell sintaticamente válido; sourceá-lo executaria `state_backend=$(comando)` (SEC-01) |
| P2 | Parse linha a linha, separando no **primeiro** `=`. Linhas iniciadas por `#` e linhas em branco são ignoradas; linha sem `=` marca a config como inválida |
| P3 | O valor **MUST** ser validado contra a allowlist `sqlite` \| `json` **antes** de qualquer uso. Fora do domínio ⇒ `config-invalida` ⇒ fallback `json` (SEC-02, FR-008) |
| P4 | Chave desconhecida é **ignorada**, não é erro — mantém o arquivo extensível sem quebrar leitores antigos |
| P5 | Toda expansão de variável **MUST** ser citada (`"$var"`), sem exceção |

Cláusulas obrigatórias para `enable-sqlite`:

| # | Cláusula |
|---|----------|
| P6 | Diretório criado com `700`; arquivo de config com `600` — coerente com `_state_db_secure_perms` (`_state-db.sh:147-152`), que já aplica `600` ao `state.db` (SEC-05) |
| P7 | Escrita via `mktemp` **no mesmo diretório** + `mv` (SEC-06, research.md Decision 7) |
| P8 | A checagem de capability **MUST** priorizar o **catálogo instalado** (`~/.claude/skills/...`) quando repo e catálogo coexistirem, e **MUST** reportar qual caminho foi validado — validar um runtime e executar outro reproduz o falso "sucesso" que FR-004A existe para impedir (SEC-03) |

> **Nota sobre P8**: esta é uma divergência **deliberada** da ordem de
> `_state_migrate_script_path` (`PATH` → repo → instalado). Aquela ordem serve a
> testes e CI; esta decisão precisa refletir o runtime que as execuções 00c reais
> consomem.

## Invariante de consistência (SC-004)

> Para uma mesma configuração e um mesmo ambiente, a decisão de backend obtida
> por `cstk doctor --deps` e a decisão efetivamente aplicada por `state-rw.sh init`
> MUST ser idênticas.

Isso é garantido estruturalmente — ambos chamam `resolve`, que tem uma única
implementação — e MUST ser coberto por teste automatizado, conforme SC-004
("medido em teste automatizado").
