---
description: 'Retoma execucao 00C apos pausa por bloqueio humano ou schedule entre ondas. Valida hash de integridade (FR-029), aplica resposta a bloqueios pendentes, delega proxima onda ao agente-00c-orchestrator.'
argument-hint: "[--projeto-alvo-path <path>] [--resposta-bloqueio <id>:<resposta>] [--init-aspectos <json-array>] [--init-aspectos-tecnicos <json-array>] [--init-aspectos-operacionais <json-array>]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
  - ScheduleWakeup
---

# /agente-00c-resume

Retomada de execucao 00C conforme contrato em
`docs/specs/_archived/agente-00c/contracts/cli-invocation.md`.

## Argumentos recebidos

```
$ARGUMENTS
```

## Comportamento esperado

Execute estes passos em ordem. Use os scripts em
`~/.claude/skills/agente-00c-runtime/scripts/` para todas as operacoes
de estado — nao manipule `state.json` diretamente com jq.

### 1. Parse de argumentos

Extrair:
- `--projeto-alvo-path` (default = `cwd`)
- `--resposta-bloqueio` opcional, formato `<block-id>:<resposta>`
- `--init-aspectos` opcional, JSON array de 3..7 strings — usado para
  re-inicializar `initial_key_aspects` em execucoes legadas (criadas
  antes da FASE 3 da evolucao, com aspectos=null). Forca overwrite via
  `drift.sh init --force`.
- `--init-aspectos-tecnicos` opcional, JSON array 0..7 strings
- `--init-aspectos-operacionais` opcional, JSON array 0..7 strings

Defina `<SD> = <PAP>/.claude/agente-00c-state` para os comandos abaixo.

### 2. Adquirir lock

> **Fronteira command↔orquestrador**: o lock e deste command PAI (acquire
> aqui, release SEMPRE no passo 7). O orquestrador NAO adquire/libera lock
> — ver "Fronteira command↔orquestrador" em `agente-00c-orchestrator.md`.

```bash
state-lock.sh acquire --state-dir <SD>
```

Exit 3 = outra execucao em andamento neste projeto. Aborte com mensagem
clara apontando para `/agente-00c-abort` ou aguardar conclusao.

### 3. Validar estado

```bash
state-validate.sh --state-dir <SD>
state-rw.sh sha256-verify --state-dir <SD>
```

Validacao falha (FR-008) OU hash divergente (FR-029) = SEM auto-correcao
(Principio III). Crie BloqueioHumano via `bloqueios.sh register` com a
ultima Decisao da execucao + diagnostico tecnico:
- Para schema invalido: `pergunta: "Estado em <SD> tem schema invalido.
  Corrigir manualmente OU autorizar abort?"`
- Para hash divergente: `pergunta: "Estado modificado externamente entre
  ondas. Aceitar estado atual OU autorizar abort?"`

Em ambos os casos, emit aviso na saida e termine sem invocar orquestrador.

### 3.bis. Resume gate de plugin LLM (FR-016)

Apos validar hash e estado, e ANTES de delegar ao orquestrador, re-verificar
o plugin LLM (se houver) para garantir que continua instalado e integro entre
ondas (plugin pode ser removido ou adulterado enquanto o agente dorme).

```bash
_llm=$(state-rw.sh get --state-dir <SD> \
         --field '.execution.llm_plugin // "claude"' 2>/dev/null) || _llm="claude"
if [ -n "$_llm" ] && [ "$_llm" != "claude" ] && [ "$_llm" != "null" ]; then
  # Requer CSTK_LIB no ambiente para source plugin-common.sh.
  _pc="${CSTK_LIB:-$HOME/.local/share/cstk/lib}/plugin-common.sh"
  [ -f "$_pc" ] && . "$_pc" || {
    bloqueios.sh register --state-dir <SD> \
      --pergunta "plugin-common.sh ausente; nao e possivel verificar plugin LLM '$_llm'. Reinstale cstk e retome." \
      --contexto-para-resposta "CSTK_LIB=$CSTK_LIB; plugin-common.sh nao encontrado."
    state-lock.sh release --state-dir <SD>
    exit 4
  }
  if ! plugin_is_installed "$_llm" 2>/dev/null; then
    bloqueios.sh register --state-dir <SD> \
      --pergunta "Plugin LLM '$_llm' removido entre ondas. Reinstale via 'cstk plugin-add $_llm' e retome." \
      --contexto-para-resposta "execution.llm_plugin=$_llm; plugin_is_installed retornou false."
    state-lock.sh release --state-dir <SD>
    exit 4
  fi
  _llm_store=$(plugin_store_dir "$_llm")
  _llm_sha=$(grep '"bundle_sha256"' "$_llm_store/plugin-manifest.json" 2>/dev/null \
               | sed 's/.*"bundle_sha256"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if ! plugin_verify_bundle_checksum "$_llm_store" "$_llm_sha" 2>/dev/null; then
    bloqueios.sh register --state-dir <SD> \
      --pergunta "Plugin LLM '$_llm' adulterado entre ondas (checksum divergiu). Reinstale e retome." \
      --contexto-para-resposta "execution.llm_plugin=$_llm; plugin_verify_bundle_checksum falhou."
    state-lock.sh release --state-dir <SD>
    exit 4
  fi
fi
```

### 4. Verificar status atual

```bash
status=$(state-rw.sh get --state-dir <SD> --field '.execution.status')
```

Casos:
- `concluida` ou `abortada`: retorne mensagem informativa, NAO retome.
  ```
  Execucao em status terminal (<status>). Nada a retomar.
  Para nova execucao, use /agente-00c em outro projeto-alvo.
  ```
- `em_andamento`: retomada normal pos-schedule. Pule para passo 6.
- `aguardando_humano`: requer `--resposta-bloqueio`. Continue passo 5.

### 5. Aplicar resposta a bloqueio (se status = aguardando_humano)

#### 5.a. Sem `--resposta-bloqueio`

Liste bloqueios pendentes e termine:

```bash
bloqueios.sh list --state-dir <SD> --status aguardando
```

Output:
```
Status: aguardando_humano. Bloqueios pendentes:

  block-NNN  dec-MMM  <pergunta>
  ...

Re-execute com --resposta-bloqueio <block-id>:<sua-resposta>
```

#### 5.b. Com `--resposta-bloqueio <id>:<resp>`

Parse o argumento:
- `block_id = parte antes do primeiro ":"`
- `resposta = parte depois do primeiro ":"` (preserve `:` adicionais)

Sanitize a resposta:
```bash
resposta_safe=$(printf '%s' "$resposta" | sanitize.sh limit-length --max 2000)
```

Aplique:
```bash
bloqueios.sh respond --state-dir <SD> --block-id <block_id> --resposta "$resposta_safe"
```

Erros:
- `bloqueio nao encontrado`: emit lista de bloqueios validos + retorne.
- `nao esta em status aguardando`: bloqueio ja respondido — informe ao
  operador, mas continue (status pode ja ter voltado para `em_andamento`
  via outro respond).

Apos `respond`, se `bloqueios.sh count --pending-only` retornar 0,
`.execution.status` ja esta de volta para `em_andamento` automaticamente.
Caso contrario, ainda ha pendentes — liste-os e instrua o operador a
chamar `/agente-00c-resume` novamente com mais respostas.

### 5.c. Re-inicializar aspectos-chave (apenas se --init-aspectos passado)

Aplicavel a execucoes legadas (anteriores a FASE 3 da evolucao) que
nao tem `.initial_key_aspects` populado. Sem aspectos, `drift.sh
check` fica permanentemente em modo `desabilitado` — re-inicializacao
manual relaxa a idempotencia normal do `drift.sh init`.

```bash
drift.sh init --state-dir <SD> \
  --aspectos "$init_aspectos" \
  [--tecnicos "$init_aspectos_tecnicos"] \
  [--operacionais "$init_aspectos_operacionais"] \
  --force
```

Apos init, registre Decisao:

```bash
state-decisions.sh register --state-dir <SD> \
  --agente "orquestrador-00c" --etapa "briefing" \
  --contexto "Re-init de aspectos via /agente-00c-resume --init-aspectos
  (execucao legada sem aspectos populados)" \
  --opcoes '["init","nao-init"]' \
  --escolha "init" \
  --justificativa "Drift check desabilitado nesta execucao ate aspectos
  serem gravados; operador autorizou re-init explicitamente"
```

Se `--init-aspectos` foi passado mas `.initial_key_aspects` ja
existe, exibir aviso de overwrite e prosseguir (assume-se intencao
explicita do operador).

**ATERRAMENTO anti-confabulacao (qualquer Decisao que este comando PAI
registre):** se a Decisao escala/age sobre um evento de SEGURANCA
(prompt-injection/canary/tampering/output hostil) detectado em tool result, a
`--evidencia` DEVE ser substring LITERAL de um output de fato observado nesta
sessao. Nao consegue apontar a linha exata? A ameaca NAO existe: registre
`--score 0 --escolha ameaca-nao-verificada` (pause), nunca trate ameaca
fabricada como real. Detalhe + caso `dec-122` na secao "Score-de-decisao" do
`agente-00c-orchestrator`.

### 6. Spawnar agente-orquestrador (continuacao da pipeline)

Antes de qualquer leitor/escritor de estado rodar, canonicalize o
`state.json` para EN no disco (migrate defensivo — schema-en-migration,
arquitetura B+). Idempotente/no-op em states ja EN; best-effort (falha
nao gateia a retomada):

```bash
state-rw.sh migrate --state-dir <SD>
```

Antes de spawnar, compute o modelo a aplicar na onda de continuacao via
`wave-select` (mapa fase→modelo + refino + override — FR-002, FR-009).
Idempotente por onda (re-entrada apos retomada nao duplica Decisao):

```bash
MODEL=$(model-routing.sh wave-select --state-dir <SD>)
```

`wave-select` SEMPRE emite uma linha em stdout: `haiku` | `sonnet` |
`opus` | `manter-atual` (nunca aborta). A escolha ja foi registrada como
`DecisaoDeRoteamentoPorOnda` auditavel dentro do proprio `wave-select`.

> Este passo apenas INSERE a selecao de modelo antes do spawn — nao
> altera o fluxo TOCTOU-safe (lock + sha256-verify + bloqueios) ja
> executado nos passos 1-5.

Aplique o param `model` SOMENTE quando `MODEL != manter-atual` (FR-006,
quickstart C8 — `manter-atual` herda o modelo da sessao):
- Se `MODEL = manter-atual`: usar o bloco `Agent(...)` abaixo SEM o param `model`.
- Senao (`MODEL ∈ {haiku, sonnet, opus}`): adicionar `model: <MODEL>` ao
  bloco `Agent(...)` (logo apos `subagent_type`).

Bidirecionalidade (FR-009): a onda de continuacao pode subir ou descer
o modelo conforme a fase corrente — o prompt do orquestrador nao muda.

Use a tool Agent:

```
Agent(
  description: "Continuar pipeline 00C apos retomada",
  subagent_type: "agente-00c-orchestrator",
  prompt: """
    Voce esta sendo invocado como CONTINUACAO de uma execucao 00C
    existente (NAO uma nova execucao).

    Context:
    - state-dir: <SD>
    - projeto-alvo-path: <PAP>
    - feature-dir: <PAP>/docs/specs/<feature> (deduzir de
      .current_stage e estrutura existente)
    - whitelist: <PAP>/.claude/agente-00c-whitelist
    - retomada_motivo: "<resume_after_block|resume_after_schedule>"

    Comece pelo Loop principal — passo 2 (start nova onda) — pulando o
    item 1 (lock + validate + sha256-verify) que ja foi feito por este
    /agente-00c-resume.

    Use as primitivas operacionais documentadas no seu prompt
    (~/.claude/agents/agente-00c-orchestrator.md) sem desvios.
  """
)
```

Aguarde retorno do orquestrador (uma mensagem de sumario contendo um
campo `Schedule intent: ...`).

### 6.bis Rede de seguranca de fechamento de onda (OBRIGATORIO — com lock ainda ativo)

> **Bug recorrente**: o orquestrador frequentemente RETORNA sem fechar a
> onda nem emitir `Schedule intent` (ver "Contrato de conclusao de turno"
> no `agente-00c-orchestrator.md`). Reforco de prompt nao resolve; o PAI
> trata o fechamento como rede de seguranca OBRIGATORIA a CADA retorno.

Chame `reconcile-wave` SEMPRE, AINDA com o lock ativo (antes do §7), pois
ele escreve no state.json. E idempotente: no-op se o orquestrador JA
fechou a onda (sem double-count); se a deixou aberta, fecha
deterministicamente (record-skill + end + avanca `current_stage`/
`next_instruction`, ou promove `.execution.status=concluida` na fase
terminal). `--terminal-phase review-features` (agente-00c termina em
review-features). Best-effort.

```bash
# Se a fase corrente for execute-task, localize tasks.md e passe --tasks-md.
state-ondas.sh reconcile-wave --state-dir <SD> \
  --terminal-phase review-features \
  2>/dev/null || echo "reconcile-wave: rede de seguranca pulada" >&2
```

Quando o orquestrador NAO emitiu `Schedule intent` (parou cedo) e a
reconciliacao fechou a onda, o §8 deve DERIVAR do `.execution.status`
real: terminal NAO agenda; `em_andamento` agenda a proxima onda.

### 7. Liberar lock

```bash
state-lock.sh release --state-dir <SD>
```

### 8. Schedule da proxima onda (CRITICO — ver nota no orchestrator)

Identico ao passo 5 de `/agente-00c`: o orquestrador (sub-agent) nao pode
disparar `ScheduleWakeup` sobrevivente — apenas DECIDE os parametros e os
expressa em `Schedule intent: ...`. Voce, slash command pai, executa o
wakeup.

Procure a linha `Schedule intent: ...` no sumario e aplique:

| Forma da linha | Acao |
|----------------|------|
| `Schedule intent: delaySeconds=<N>; reason="<R>"; prompt="<P>"` | Invocar `ScheduleWakeup(delaySeconds=<N>, reason="<R>", prompt="<P>")` |
| `Schedule intent: none; motivo=<X>` | NAO invocar ScheduleWakeup. Anotar motivo. |
| linha ausente OU formato invalido | Anotar `Proxima onda agendada: nenhuma (Schedule intent ausente/invalido)`. NAO tentar adivinhar. |

Se `ScheduleWakeup` falhar, limpe o estado:

```bash
state-rw.sh set --state-dir <SD> \
  --field '.waves[-1].next_wave_scheduled_for' --value 'null'
```

### 8.bis Ingestao da onda na knowledge.db (rede de seguranca, best-effort)

A ingestao canonica e o passo **10.bis** do loop do orquestrador
(`agente-00c-orchestrator.md`). Este eco no pai e uma REDE DE SEGURANCA
para o caso de o orquestrador retornar SEM completar o loop (onda fechada/
recuperada sem ter chegado ao 10.bis). Sem ele, a `knowledge.db` fica sem
o conhecimento da onda.

```bash
# Idempotente (upsert por chave natural): re-ingerir apos o 10.bis e
# inofensivo. Read-only sobre o state.json; escreve so em ~/.claude/cstk/
# knowledge.db. NUNCA gateia — toda falha degrada para no-op.
cstk recall --ingest --state-dir <SD> 2>/dev/null \
  || echo "knowledge-db: ingestao (rede de seguranca) pulada — cstk/sqlite3/jq ausentes" >&2
```

### 9. Apresentar resultado ao operador

Imprima o sumario retornado pelo orquestrador, anotando que e retomada e
incluindo a confirmacao de schedule:

```
Agente-00C retomado.
Execucao: <id>
Tipo: <retomada apos bloqueio|retomada apos schedule>
[sumario do orquestrador aqui — pode reformatar "Schedule intent: ..."
 como "Proxima onda agendada: <ISO planejado | nenhuma — <motivo>>"
 para clareza ao operador]
```

## Estado atual

**FASE 7.2 — operacional.** Depende das primitivas instaladas via
`cstk install`: `~/.claude/skills/agente-00c-runtime/scripts/`. Em caso
de skill ausente, falhe com mensagem orientando `cstk install`.
