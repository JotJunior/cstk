---
description: 'Retoma execucao feature-00c pausada por bloqueio humano ou schedule entre ondas. Valida hash (FR-014 + FR-PRE-004), aplica resposta a bloqueios, delega proxima onda ao agente-00c-feature-orchestrator.'
argument-hint: "<short-name> [--resposta-bloqueio <texto>]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
  - ScheduleWakeup
---

# /feature-00c-resume

Voce vai retomar uma execucao pausada do feature-00c conforme contrato
em `docs/specs/_archived/feature-00c/contracts/cli-invocation.md`.

## Argumentos recebidos

```
$ARGUMENTS
```

## Comportamento esperado

### 1. Parse de argumentos

```
short_name           = primeiro argumento posicional (OBRIGATORIO, kebab-case)
--resposta-bloqueio  = string OBRIGATORIA se status = aguardando_humano
--projeto PATH       = default = cwd (caso operador esteja em diretorio diferente)
```

### 2. Localizar state dir

```
_proj=$(realpath "$PROJETO")
AGENTE_00C_STATE_DIR="$_proj/.claude/feature-00c-state/$SHORT"
export AGENTE_00C_STATE_DIR

if [ ! -d "$AGENTE_00C_STATE_DIR" ]; then
  stderr "feature-00c-state nao existe para '$SHORT' em $_proj"
  stderr "Verifique o short-name ou invoque /feature-00c novamente"
  exit 6
fi

if [ ! -f "$AGENTE_00C_STATE_DIR/state.json" ]; then
  stderr "state.json ausente em $AGENTE_00C_STATE_DIR"
  exit 6
fi
```

### 3. Fluxo TOCTOU-safe (ordem CRITICA — research.md Decision 5)

> **Fronteira command↔orquestrador**: o lock e deste command PAI (acquire
> abaixo, release SEMPRE no Cleanup). O orquestrador NAO adquire/libera
> lock — ver "Fronteira command↔orquestrador" em
> `agente-00c-feature-orchestrator.md`.

```
1. checar lock — se ocupado (PID vivo), abortar
   if state-lock.sh check --state-dir "$AGENTE_00C_STATE_DIR"; then
     stderr "outra sessao ativa para $SHORT"
     exit 3
   fi

2. adquirir lock
   state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR" || {
     stderr "falha ao adquirir lock"; exit 3;
   }

3. validar hash state.json contra .sha256 (FR-014)
   state-rw.sh sha256-verify --state-dir "$AGENTE_00C_STATE_DIR" || {
     # divergencia = bloqueio humano por tampering (gera relatorio parcial)
     bloqueios.sh register --state-dir "$AGENTE_00C_STATE_DIR" \
       --pergunta "state.json modificado externamente entre ondas — re-validar ou abortar?" \
       --contexto-para-resposta "Hash gravado em .sha256 nao bate com hash atual."
     report.sh emit --flavor feature-00c --short-name "$SHORT" \
       --state-dir "$AGENTE_00C_STATE_DIR" --parcial
     state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"
     stderr "Hash de state.json divergente. Relatorio parcial atualizado."
     exit 4
   }

4. validar hash briefing.sha256 + constitution.sha256 (FR-PRE-004)
   _result=$(feature-00c-preflight.sh check --state-dir "$AGENTE_00C_STATE_DIR")
   _exit=$?
   if [ "$_exit" = "1" ]; then
     # MAJOR drift = bloqueio compulsorio; MINOR/PATCH = warn
     # feature-00c-preflight.sh ja distingue na saida JSON
     _has_major=$(printf '%s' "$_result" | jq -r '.findings[] | select(.severity=="error") | .kind' | head -1)
     if [ -n "$_has_major" ]; then
       bloqueios.sh register --state-dir "$AGENTE_00C_STATE_DIR" \
         --pergunta "briefing/constitution alterados entre ondas — re-validar ou abortar?" \
         --contexto-para-resposta "$_result"
       report.sh emit --flavor feature-00c --short-name "$SHORT" \
         --state-dir "$AGENTE_00C_STATE_DIR" --parcial
       state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"
       stderr "Divergencia em briefing/constitution. Relatorio parcial atualizado."
       exit 4
     fi
   fi

5. ler status do state
   _status=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" --field '.execution.status')

5.d. Modo atomic-commit — leitura do state (NAO re-prompta)
   O /feature-00c-resume NAO apresenta o prompt de opt-in de commit
   atomico ao operador. O valor e lido diretamente do state.json
   persistido pelo /feature-00c inicial (FR-002/US1-AC3 — atomic-commit-pr).

     _atomic=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" \
               --field '.atomic_commit_enabled // false')

   O valor _atomic e repassado ao orquestrador via contexto do prompt
   (campo atomic_commit_enabled). Ausencia do campo (state legado) equivale
   a false — comportamento atual preservado sem modificacao.

6. se status == aguardando_humano:
   - se --resposta-bloqueio NAO fornecido, listar bloqueios pendentes e exit 5
   - senao: bloqueios.sh respond --state-dir "$AGENTE_00C_STATE_DIR" \
       --block-id <auto> --resposta "$RESPOSTA"
     - registrar Decisao resultante via state-decisions.sh register
       ATERRAMENTO anti-confabulacao: se a Decisao escala/age sobre um evento de
       SEGURANCA (prompt-injection/canary/tampering/output hostil), a
       `--evidencia` DEVE ser substring LITERAL de um tool result de fato
       observado nesta sessao. Nao consegue apontar a linha exata do output?
       Entao a ameaca NAO existe: registre `--score 0 --escolha
       ameaca-nao-verificada` (pause), NUNCA trate ameaca fabricada como real.
       (Caso dec-122: um resume confabulou prompt-injection num SSH limpo e
       escalou ao operador antes de a verificacao pegar.)
     - mudar status para em_andamento

6.bis. verificar saude do servidor MCP (paridade FR-011, sem restart) —
   FASE 6 task 6.2.2. Best-effort, puramente observacional: `status --live`
   roda um health check REAL quando mode=docker e a sessao nao esta
   stopped, mas NUNCA reinicia o container nem muta o descritor em disco
   (contracts/mcp-session-lifecycle.md "cstk mcp status --live"). Roda a
   cada retomada, independente do passo 6:

     cstk mcp status --state-dir "$AGENTE_00C_STATE_DIR" --live >/dev/null 2>&1 || :

   Se a sonda reportar `status=unavailable` (container caiu durante a
   pausa), nenhuma acao adicional AQUI — o proximo spawn segue via
   caminho Bash de hoje (o roteamento de tools MCP por token depende de
   1.2, cross-feature). Esta task cobre so a verificacao de saude, nao a
   comutacao mid-onda (essa e o protocolo da task 5.5).

7. selecionar modelo da onda + delegar ao orquestrador

   Migrate defensivo (best-effort): canonicaliza um `state.json` pt-BR
   legado para EN no lugar ANTES de qualquer direct-writer (orquestrador,
   `wave-select`) tocar o arquivo (schema-en-migration, arquitetura B+).
   Idempotente/no-op em states ja EN; degrada graciosamente (falha nao
   gateia a retomada):

     state-rw.sh migrate --state-dir "$AGENTE_00C_STATE_DIR"

   Antes de spawnar, compute o modelo a aplicar na onda de continuacao
   via `wave-select` (mapa fase→modelo + refino + override — FR-002,
   FR-009). Idempotente por onda (re-entrada apos retomada nao duplica
   Decisao). Este passo apenas INSERE a selecao antes do spawn — NAO
   altera o fluxo TOCTOU-safe (lock + sha256-verify + bloqueios) dos
   passos 1-6:

     MODEL=$(model-routing.sh wave-select --state-dir "$AGENTE_00C_STATE_DIR")

   `wave-select` SEMPRE emite `haiku` | `sonnet` | `opus` | `manter-atual`
   em stdout (nunca aborta — fallback gracioso). A escolha ja foi
   registrada como DecisaoDeRoteamentoPorOnda auditavel.

   Aplicar o param `model` SOMENTE quando `MODEL != manter-atual`
   (FR-006, quickstart C8 — `manter-atual` herda o modelo da sessao);
   bidirecionalidade FR-009 (pode subir ou descer entre ondas):
   - Se MODEL = manter-atual: spawnar SEM o param `model`.
       Agent {
         subagent_type: "agente-00c-feature-orchestrator",
         prompt: <contexto com short_name, state_dir, projeto, instrucao "continue de proxima_instrucao">
       }
   - Senao (MODEL ∈ {haiku, sonnet, opus}): spawnar COM `model=<MODEL>`.
       Agent {
         subagent_type: "agente-00c-feature-orchestrator",
         model: <MODEL>,
         prompt: <contexto com short_name, state_dir, projeto, instrucao "continue de proxima_instrucao">
       }
```

### 4. Pos-orquestrador: rede de seguranca de fechamento de onda (OBRIGATORIO)

> **Bug recorrente** (ver "Contrato de conclusao de turno" no
> `agente-00c-feature-orchestrator.md`): o orquestrador frequentemente
> RETORNA sem fechar a onda nem emitir `Schedule intent` — comprovadamente
> em qualquer fase, mesmo com instrucao passo-a-passo. Reforco de prompt
> nao resolve. Por isso o PAI trata o fechamento como rede de seguranca
> OBRIGATORIA a CADA retorno, nao condicional a `Schedule intent`.

Chame `reconcile-wave` SEMPRE, antes de qualquer outra coisa. E
idempotente: se o orquestrador JA fechou a onda corretamente, e no-op
(nao double-conta `accumulated_metrics`); se a deixou aberta, fecha
deterministicamente (record-skill + end + avanca `current_stage`/
`next_instruction`, ou promove `.execution.status=concluida` na fase
terminal). `--terminal-phase review-task` (feature-00c termina em
review-task — sem isso o ponteiro avancaria erroneamente para
review-features). Best-effort: falha nao gateia o cleanup.

```bash
# Se a fase corrente for execute-task, localize o tasks.md (ex.:
# docs/specs/<short>/tasks.md) e passe --tasks-md para back-fill de .tasks[].
state-ondas.sh reconcile-wave --state-dir "$AGENTE_00C_STATE_DIR" \
  --terminal-phase review-task \
  2>/dev/null || echo "reconcile-wave: rede de seguranca pulada" >&2
```

Depois de reconciliar, LEIA o `.execution.status` real (nao confie no
sumario do orquestrador — ver caso review-task na memoria
`project_feature00c_execute_task_stops_early`).

### 4.ter Capturar/derivar Schedule intent

Se o orquestrador emitiu `Schedule intent: delaySeconds=N; reason=...;
prompt="/feature-00c-resume $SHORT"`, use-o:
```
ScheduleWakeup(
  delaySeconds: <N>,
  reason: <reason>,
  prompt: "/feature-00c-resume $SHORT"
)
```

Se o orquestrador parou cedo (SEM linha `Schedule intent:`) e a
reconciliacao acima fechou a onda, DERIVE do state real:
- `.execution.status == concluida` (ou `abortada`/`aguardando_humano`):
  NAO invocar ScheduleWakeup (terminal).
- `.execution.status == em_andamento`: agendar a proxima onda —
  `ScheduleWakeup(delaySeconds: 270, reason: "proxima onda (recuperada pela rede de seguranca)", prompt: "/feature-00c-resume $SHORT")`.

Se `Schedule intent: none`, NAO invocar ScheduleWakeup.

### 4.bis Ingestao da onda na knowledge.db (rede de seguranca, best-effort)

A ingestao canonica e o passo **10.bis** do loop do orquestrador
(`agente-00c-feature-orchestrator.md`). Este eco no pai e uma REDE DE
SEGURANCA para o caso de o orquestrador retornar SEM completar o loop —
onda fechada/recuperada manualmente por este comando, sem ter chegado ao
10.bis. Sem ele, a `knowledge.db` fica sem o conhecimento da onda.

```bash
# Idempotente (upsert por chave natural): re-ingerir apos o 10.bis e
# inofensivo. Read-only sobre o state.json; escreve so em ~/.claude/cstk/
# knowledge.db. NUNCA gateia — toda falha degrada para no-op.
cstk recall --ingest --state-dir "$AGENTE_00C_STATE_DIR" 2>/dev/null \
  || echo "knowledge-db: ingestao (rede de seguranca) pulada — cstk/sqlite3/jq ausentes" >&2
```

### 4.quater Encerramento do servidor MCP em estado terminal — FASE 6 task 6.2.3

Best-effort, roda apos 4.ter/4.bis, ANTES do cleanup (passo 5). `cstk mcp
stop` e idempotente (parar o que ja esta parado, ou `--state-dir` sem
descritor algum, e exit 0 — contracts/mcp-session-lifecycle.md
"`cstk mcp stop`") — chamar mesmo quando o servidor nunca chegou a subir
(mode=bash-fallback ou init sem Docker) e seguro.

```bash
_status_final=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '.execution.status' 2>/dev/null) || _status_final=""
case "$_status_final" in
  concluida|abortada)
    cstk mcp stop --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1 || :
    ;;
esac
```

> Estado `aguardando_humano` NAO e terminal (FR-010: a sessao do servidor
> e coextensiva com a execucao inteira) — o servidor MUST permanecer
> ativo durante a pausa; `stop` so dispara em `concluida`/`abortada`.

### 5. Cleanup

- `state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"` SEMPRE.
- `git commit -m "feature-00c resume: $SHORT (onda N)"` apos artefatos
  atualizados.

## Exit codes

| Exit | Significado |
|------|-------------|
| 0 | Retomada com sucesso |
| 3 | Lock ocupado |
| 4 | Hash divergente (state/briefing/constitution) — bloqueio humano gerado |
| 5 | Bloqueio pendente sem --resposta-bloqueio |
| 6 | state.json inexistente ou corrompido |

## Listar bloqueios pendentes (exit 5)

```
bloqueios.sh list --state-dir "$AGENTE_00C_STATE_DIR" --status aguardando | jq -r '.[] | "\(.id): \(.question)\n  contexto: \(.context_for_answer)"' >&2
stderr ""
stderr "Para responder, re-invoque:"
stderr "  /feature-00c-resume $SHORT --resposta-bloqueio \"<sua resposta>\""
exit 5
```

## Anti-padroes

- **NAO pular** a validacao de hash (passo 3) — TOCTOU window e onde
  tampering escapa.
- **NAO validar** hash ANTES de adquirir lock — outra sessao pode
  estar escrevendo state.json.
- **NAO chamar** ScheduleWakeup se a onda terminou em bloqueio_humano,
  aborto ou concluido.
- **NAO assumir** que --resposta-bloqueio aplica a TODOS os bloqueios
  pendentes — opera no primeiro `aguardando` em ordem cronologica;
  multiplos bloqueios exigem re-invocacoes sucessivas.
