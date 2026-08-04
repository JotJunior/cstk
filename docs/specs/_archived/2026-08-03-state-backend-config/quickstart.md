# Quickstart: Configuração de Backend do state.db (Cutover Fase 2)

Cenários de teste que validam a implementação end-to-end. Um cenário por fluxo
crítico (happy path + error cases), rastreados aos critérios de sucesso da spec.

> **Isolamento obrigatório**: todos os cenários manipulam
> `$HOME/.claude/cstk/config`, que é o arquivo **real do operador**. Os testes
> automatizados MUST rodar com `HOME` apontando para um diretório temporário
> (padrão já usado na suíte), nunca contra o `HOME` real. Um teste que ative o
> backend SQLite no ambiente do operador por engano é um efeito colateral
> inaceitável.

---

## Scenario 1: Ativação bem-sucedida (happy path) — SC-001

1. Ambiente com `sqlite3` ≥ `3.45.1` e runtime do catálogo atualizado
2. Config global ausente (instalação limpa)
3. Rodar `cstk state enable-sqlite`
4. **Expected**: exit 0; `$HOME/.claude/cstk/config` passa a conter
   `state_backend=sqlite`
5. Inicializar uma execução 00c nova, num diretório de estado **sem**
   `state.json` e **sem** `state.db`
6. **Expected**: a inicialização cria `<state-dir>/state.db`; **não** cria
   `state.json`. Nenhuma ação manual adicional do operador além do passo 3.

---

## Scenario 2: Recusa por dependência abaixo do mínimo — SC-002

1. Ambiente onde `sqlite3` está presente porém **abaixo** de `3.45.1`
2. Config global em estado conhecido (ausente, ou com `state_backend=json`)
3. Capturar o conteúdo exato da config antes da tentativa
4. Rodar `cstk state enable-sqlite`
5. **Expected**: exit **não-zero**; a mensagem de erro cita **a versão mínima
   exigida** e **a versão efetivamente detectada**; a config está **byte-a-byte
   idêntica** à captura do passo 3.

---

## Scenario 2.5: Payload de injeção na config nunca é executado — CHK002

1. Escrever em `$HOME/.claude/cstk/config` uma linha sintaticamente
   `key=value` cujo valor é um payload de shell, ex.:
   `state_backend=$(touch /tmp/pwned)`
2. Rodar `cstk doctor --deps` (ou `state-backend.sh resolve` diretamente)
3. **Expected**: o valor é tratado como fora-da-allowlist (nem `sqlite` nem
   `json`) ⇒ `reason=config-invalida` ⇒ `effective_backend=json`; o comando
   `touch /tmp/pwned` **nunca é executado** — o canary não passa a existir.
   Contrapartida de teste para P1/SEC-01 (o leitor NUNCA usa `.`/`source`/
   `eval` sobre o arquivo).

---

## Scenario 2.6: Valor sintaticamente válido porém fora da allowlist — CHK006

1. Escrever `state_backend=mysql` em `$HOME/.claude/cstk/config` (linha
   `key=value` bem formada, mas o valor não pertence a `sqlite`\|`json`)
2. Rodar `state-backend.sh resolve`
3. **Expected**: `reason=config-invalida`, `effective_backend=json`.
   Distinto do Scenario 7 ("linha sem `=`"): aqui o parse da linha é
   válido, é o **valor** que falha a allowlist (P3).

---

## Scenario 2.7: Chave desconhecida é ignorada — CHK007

1. Escrever em `$HOME/.claude/cstk/config`:
   ```
   chave_nova=valor
   state_backend=sqlite
   ```
2. Rodar `state-backend.sh resolve` (com `sqlite3` adequado)
3. **Expected**: a chave desconhecida não quebra o parse nem é reportada
   como erro (P4); `state_backend=sqlite` é honrado normalmente
   (`reason=configurado-dependencia-adequada`, `effective_backend=sqlite`).

---

## Scenario 3: Recusa por dependência ausente — FR-004

1. Ambiente sem `sqlite3` no `PATH`
2. Rodar `cstk state enable-sqlite`
3. **Expected**: exit não-zero; mensagem cita a ausência da dependência e a
   versão mínima exigida; config inalterada.

> **GOTCHA de teste** (lição registrada na memória do projeto): um stub de `PATH`
> **não esconde** um binário instalado em `/usr/bin`. Um teste de "dependência
> ausente" que apenas manipula `PATH` passa localmente e quebra no CI (ou
> vice-versa). O SUT precisa ter seu mecanismo de lookup desacoplado do `PATH`
> do processo de teste — seguir o padrão já usado na suíte para esse tipo de
> cenário.

---

## Scenario 4: Recusa por runtime do catálogo incapaz — FR-004A

1. Ambiente com `sqlite3` ≥ `3.45.1` (dependência **adequada**)
2. Catálogo instalado **anterior** a esta feature — o `state-backend.sh` não
   existe no runtime instalado
3. Rodar `cstk state enable-sqlite`
4. **Expected**: exit não-zero; a mensagem cita a necessidade de rodar
   `cstk update` / `cstk self-update`; config **inalterada**.

> Este cenário é o que impede a falha silenciosa mais provável desta feature:
> binário novo + catálogo antigo. Sem ele, a ativação "teria sucesso" e as novas
> execuções continuariam em JSON sem nenhum sinal ao operador —
> violando SC-001 sem erro visível.

---

## Scenario 4.5: Coexistência repo + catálogo instalado com capabilities divergentes — CHK009

1. Ambiente com `sqlite3` ≥ `3.45.1` (dependência **adequada**)
2. Catálogo instalado (`~/.claude/skills/agente-00c-runtime/scripts/state-backend.sh`)
   presente, porém **antigo** — não reconhece o subcomando `capability`
   (simula um `cstk update` desatualizado)
3. Árvore de repo (`$CSTK_LIB/../../global/skills/agente-00c-runtime/scripts/state-backend.sh`)
   com o script **novo/capaz** — coexistindo com o catálogo antigo
4. Rodar `cstk state enable-sqlite`
5. **Expected**: exit não-zero; a mensagem cita `capability verificado via
   catalogo-instalado (<path>)` — o **catálogo instalado prevalece** mesmo
   com um repo capaz disponível; config **inalterada**. Prova de que P8 é
   prioridade determinística, não apenas ordem de fallback.

> Este é o único risco de severidade Média (SEC-03) que não tinha
> contrapartida de teste antes desta feature (CHK009). Sem este cenário, uma
> reintrodução futura do resolvedor padrão `PATH`→repo→instalado (usado por
> `_state_migrate_script_path`) para `enable-sqlite` passaria despercebida —
> validando um runtime e executando outro.

---

## Scenario 5: Idempotência da ativação — FR-009-INFRA-IDEMP

1. Ambiente adequado; rodar `cstk state enable-sqlite` uma vez (sucesso)
2. Rodar `cstk state enable-sqlite` **de novo**
3. **Expected**: exit 0, sucesso silencioso; a config contém **exatamente uma**
   linha `state_backend=` (sem entrada duplicada); nenhum erro reportado.

---

## Scenario 5.5: Permissões e atomicidade — CHK013

1. Ambiente adequado, config global ausente
2. Rodar `cstk state enable-sqlite`
3. **Expected**: `$HOME/.claude/cstk/` fica com permissão `700`;
   `$HOME/.claude/cstk/config` fica com permissão `600` (P6); nenhum
   arquivo temporário residual (`config.XXXXXX` do `mktemp`) permanece em
   `$HOME/.claude/cstk/` após a execução (P7 — write-temp-then-rename).

---

## Scenario 6: Diagnóstico como gate de CI — SC-003

**6a — sem anomalia:**

1. Ambiente com `sqlite3` ≥ `3.45.1` e `jq` presentes
2. Rodar `cstk doctor --deps`
3. **Expected**: exit **0**; stdout lista `sqlite3` e `jq` com presença e versão
   detectada, e informa o backend efetivo + o motivo.

**6b — com anomalia:**

1. Ambiente com `sqlite3` abaixo do mínimo (ou ausente)
2. Rodar `cstk doctor --deps`
3. **Expected**: exit **não-zero**; o relatório **ainda é emitido** em stdout,
   identificando qual dependência está anômala. `cstk doctor --deps || exit 1`
   funciona como gate sem nenhum parsing da saída.

**6c — instalação padrão nunca configurada:**

1. Config global ausente
2. Rodar `cstk doctor --deps`, com dependências adequadas
3. **Expected**: exit **0** — "nunca configurado" é o default legítimo, não
   anomalia (FR-008); motivo reportado como `nunca-configurado`; backend
   efetivo `json`.

---

## Scenario 7: Config ausente ou corrompida não quebra nada — FR-008

1. Escrever lixo não-interpretável em `$HOME/.claude/cstk/config`
   (ex.: linhas sem `=`)
2. Rodar `cstk doctor --deps`
3. **Expected**: exit governado **apenas** pelas dependências (config inválida
   não é anomalia); motivo `config-invalida`; backend efetivo `json`
4. Inicializar uma execução 00c nova
5. **Expected**: a inicialização **conclui com sucesso** criando `state.json`
   (fallback legado) — não falha, não aborta.

---

## Scenario 8: Projetos existentes intocados — FR-006 / SC-005

**8a — projeto com `state.json` não migrado:**

1. Diretório de estado com `state.json` existente, execução em andamento
2. Ativar o backend SQLite (`cstk state enable-sqlite`)
3. Operar normalmente sobre esse estado
4. **Expected**: o projeto continua usando `state.json`; **nenhuma** migração é
   disparada; comportamento idêntico ao anterior à ativação.

**8b — projeto já migrado (`state.db`):**

1. Diretório de estado com `state.db` presente
2. **Expected**: comportamento inalterado — o dispatch por presença de `state.db`
   (`_state-rw-db.sh:41-48`) já resolve para `sqlite` independentemente da config.

**8c — regressão zero:**

1. Rodar a suíte completa (`./tests/run.sh`)
2. **Expected**: 0 regressões atribuíveis a esta feature.

> **GOTCHA de execução da suíte** (registrado na memória do projeto): a suíte
> completa leva ~12 min, bem acima do que a documentação sugere. Rodar em
> background preso ao processo pai — foreground é morto por timeout e um
> subagente dedicado morre junto. Além disso, sob locale `pt_BR` há FAIL falso
> conhecido; usar `LC_ALL=C`.

---

## Scenario 9: Roundtrip de consistência entre os dois caminhos — SC-004

Análogo, para esta feature, do cenário "Roundtrip End-to-End" do template: em vez
de uma borda backend↔frontend, a borda que pode driftar aqui é
**binário `cstk` ↔ runtime dos orquestradores**. É a divergência que SC-004 mede
e o teste MUST ser empírico — comparar as duas saídas reais, não asserções
separadas sobre cada caminho.

Para **cada** uma das combinações de config × ambiente abaixo:

| Config | `sqlite3` |
|--------|-----------|
| ausente | adequado |
| `state_backend=json` | adequado |
| `state_backend=sqlite` | adequado |
| `state_backend=sqlite` | abaixo do mínimo |
| `state_backend=sqlite` | ausente |
| inválida (lixo) | adequado |

1. Obter o backend resolvido pelo **caminho do binário** (`cstk doctor --deps`)
2. Obter o backend efetivamente aplicado pelo **caminho do runtime** — inicializar
   uma execução nova num state-dir limpo e observar **qual arquivo foi criado**
   (`state.db` ou `state.json`)
3. **Expected**: os dois concordam em **100%** das combinações — 0% de
   divergência.

> **Por que este cenário é obrigatório**: SC-004 exige 0% de divergência "medido
> em teste automatizado". A Decision 2 torna isso verdadeiro por construção (uma
> única implementação de `resolve`), mas o teste é o que **impede a regressão**
> caso alguém reintroduza um parser paralelo no CLI por conveniência. Sem ele, a
> unicidade é convenção; com ele, é contrato.
