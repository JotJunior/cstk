---
description: 'Retoma execucao feature-00c pausada por bloqueio humano ou schedule entre ondas. Valida hash (FR-014 + FR-PRE-004), aplica resposta a bloqueios, delega proxima onda ao agente-00c-feature-orchestrator.'
argument-hint: "<short-name> [--resposta-bloqueio <texto>]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
  - ScheduleWakeup
  - SendMessage
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
--allow-target-outside-session = opcional; capturar em `_scope_allow`
                       (`--allow-outside` quando presente). Bypass explicito e
                       auditado do passo 2.bis (issues #189/#190/#191).
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

# 2.bis. projeto-alvo sob a raiz DESTA sessao (issues #189/#190/#191) —
# mesma guarda do pre-flight 1.bis do /feature-00c: hooks de guarda e
# servidor MCP so operam sob a raiz da sessao; retomar de outra raiz roda
# a onda SEM guarda enforced (tool_calls=0) e com toda tool MCP em
# SESSION_MISMATCH. Fail-closed ANTES do lock; bypass explicito auditado.
session-scope.sh check --projeto-alvo-path "$_proj" $_scope_allow || exit 3

# Backend-agnostico (state-db-runtime-parity, v6.3): sob backend SQLite
# NAO existe state.json — o estado transacional e state.db. Exigir
# state.json aqui recusaria, com exit 6, toda execucao iniciada apos
# `cstk state enable-sqlite`. Mesma forma ja usada em feature-00c.md.
if [ ! -f "$AGENTE_00C_STATE_DIR/state.json" ] \
   && [ ! -f "$AGENTE_00C_STATE_DIR/state.db" ]; then
  stderr "estado ausente em $AGENTE_00C_STATE_DIR (nem state.json nem state.db)"
  exit 6
fi
```

### 3. Fluxo TOCTOU-safe (ordem CRITICA — research.md Decision 5)

> **Fronteira command↔orquestrador**: o lock e deste command PAI (acquire
> abaixo, release SEMPRE no Cleanup). O orquestrador NAO adquire/libera
> lock — ver "Fronteira command↔orquestrador" em
> `agente-00c-feature-orchestrator.md`.

```
1. checar lock — ATENCAO a semantica REAL do script: `check` sai **0
   quando o lock esta LIVRE** e **3 quando esta DETIDO**, e NAO distingue
   dono vivo de morto (basta o diretorio `.lock` existir). Escrever
   `if state-lock.sh check ...; then abortar` INVERTE a condicao: aborta
   com lock livre e prossegue com lock ocupado.
   state-lock.sh check --state-dir "$AGENTE_00C_STATE_DIR" || _lock_detido=1

2. adquirir lock — quem fez o `acquire` e um shell EFEMERO deste command
   pai, que morre assim que o Bash retorna; quem faz o trabalho da onda e o
   SUBAGENTE orquestrador, que segue vivo depois disso. Logo **"dono morto"
   NAO significa onda encerrada** — durante uma onda em pleno voo o dono do
   lock aparece como morto. O discriminador real esta no ESTADO, nao no
   pid: lock orfao **com a ultima onda FECHADA** e o caso normal entre
   ondas. `acquire --force` aplica exatamente essa regra (issue #182):
   readquire com `DIAG|warning|lock-force-acquired` quando o dono esta
   morto E nao ha onda aberta; RECUSA com exit 3 quando o dono esta VIVO
   (`lock-force-denied-owner-alive`), quando ha onda ABERTA
   (`lock-force-denied-wave-open`) ou quando o estado nao pode ser lido
   (`lock-force-denied-state-unreadable`, fail-closed).
   state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR" \
     || state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR" --force \
     || { stderr "lock nao readquirido para $SHORT — ver o DIAG acima (dono VIVO, onda aberta ou estado ilegivel)"; exit 3; }

   > Preferivel a `--force`: o command pai libera o lock ANTES de agendar a
   > proxima onda (passo 5, Cleanup). Ai a retomada adquire limpo e o
   > `--force` nunca precisa disparar.
   >
   > **Recusa do `--force` NAO se resolve insistindo.** Identifique o caso:
   > - onda aberta com trabalho reconciliavel => `reconcile-wave` fecha a
   >   onda; depois disso o `--force` passa sozinho;
   > - execucao que deve ser derrubada => `/feature-00c-abort` (que ja usa
   >   o caminho `--force-abandoned`);
   > - onda comprovadamente abandonada e JA reconciliada => repetir com
   >   `--force-abandoned`, que e deliberado e fica auditado
   >   (`DIAG|warning|lock-force-abandoned-override`).
   >
   > LIMITE CONHECIDO da guarda: ela nao cobre a janela entre o spawn do
   > subagente e o `open_wave` da onda nova — nessa janela o estado ainda
   > nao tem onda aberta, embora ja possa haver trabalho em disco. Antes de
   > usar `--force-abandoned`, confira `git status --porcelain` e o mtime
   > dos arquivos do escopo da feature.

3. validar hash state.json contra .sha256 (FR-014)
   NOTA (backend SQLite): `sha256-verify` e no-op e sai 0 — a integridade
   do state.db vem de `PRAGMA integrity_check`, por desenho
   (state-db-foundation). Exit 0 aqui NAO significa "hash conferido" sob
   SQLite; significa "nao ha .sha256 a conferir".
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
   roda um health check REAL — em mode=docker (legado), a sonda do
   container; em mode=direct (issue #191), apresenta o `session_id` do
   descritor a `mcp-session.sh resolve` sob a raiz da sessao, o MESMO
   caminho de autorizacao que toda tool percorre — e NUNCA reinicia nada
   nem muta o descritor em disco (contracts/mcp-session-lifecycle.md
   "cstk mcp status --live"). Roda a cada retomada, independente do
   passo 6, e o `status=` DEVE ser lido (nao descartado):

     _mcp_live=$(cstk mcp status --state-dir "$AGENTE_00C_STATE_DIR" --live 2>/dev/null | sed -n 's/^status=//p') || :

   - `active` = sonda saudavel (descritor ok E token resolve).
   - `unresolvable` (mode=direct: descritor ok, token NAO resolve sob a raiz
     desta sessao — `reason=token-unresolvable-under:<raiz>`), `unavailable`
     (container caiu durante a pausa), `stopped`, `unknown` ou vazio = sonda
     NAO saudavel: nenhuma acao adicional AQUI — o proximo spawn segue via
     caminho Bash. Antes da #191 o mode=direct respondia `active`
     incondicionalmente e instruia o orquestrador a usar tools que falhavam
     100% das vezes. Esta etapa cobre so a verificacao de saude, nao a
     comutacao mid-onda (essa e o protocolo da task 5.5).

   **Injecao do token de capacidade (dec-043 / SEC-H3, generalizada
   FR-013)**: apos a sonda, leia o descritor e injete o token no contexto
   do spawn (mesmo protocolo do /feature-00c inicial) SEMPRE que
   `session_id` for nao-vazio, **independentemente do valor de `mode`**
   (contracts/cli-mcp-lifecycle.md §7, P-1/P-2 — a condicao antiga
   restrita a `mode == "docker"` foi removida: apos o cutover desta
   feature nenhuma sessao nova grava `mode=docker`):

     _mcp_token=$(jq -r '.session_id // ""' "$AGENTE_00C_STATE_DIR/mcp-server.json" 2>/dev/null) || _mcp_token=""

   - Token NAO-vazio E sonda saudavel ⇒ linha no prompt do orquestrador:
     `MCP: servidor de estado ativo; session_id=<token>. Prefira as tools
     mcp__cstk-state__* apresentando ESTE session_id; em erro de
     transporte, contrato de queda mid-onda e comutacao para Bash.`
   - Token vazio ou sonda NAO saudavel (`_mcp_live` != `active`) ⇒
     NAO mencione MCP no prompt (caminho Bash, zero regressao).
     Token NUNCA ecoado em stdout/logs.

   **Idempotencia dos opt-ins em retomada (task 5.4.1 — mcp-elicitation-optins,
   FR-008/FR-011)**: este resume NUNCA re-pergunta o opt-in de atomic-commit
   por prosa (ja garantido — le `.atomic_commit_enabled` diretamente do
   state). No ramo estruturado, a mesma garantia vale para `collect_optins`:
   este command **nao precisa** de logica extra alem da injecao
   incondicional de token acima — a Invariante I-2 (nenhuma onda abre com
   campo aplicavel sem registro) e a checagem I-1 (campo com registro
   terminal nunca re-dispara `elicitation/create`, retorna `reused`) vivem
   no **orquestrador**/**tool**, nao no command
   (contracts/optin-capture-order.md §3.2). Injetar o token normalmente e
   suficiente para permitir a chamada de `reused` se o orquestrador
   precisar confirmar o estado apos uma retomada.

7. selecionar modelo da onda + delegar ao orquestrador

   Migrate defensivo (best-effort): canonicaliza um `state.json` pt-BR
   legado para EN no lugar ANTES de qualquer direct-writer (orquestrador,
   `wave-select`) tocar o arquivo (schema-en-migration, arquitetura B+).
   Idempotente/no-op em states ja EN; degrada graciosamente (falha nao
   gateia a retomada):

     state-rw.sh migrate --state-dir "$AGENTE_00C_STATE_DIR"

   Garantia de branch do modo atomic-commit (atomic-commit-ensure-branch
   FR-005): se `commit-mode.sh is-enabled` retornar `true`, re-executar a
   garantia ANTES do spawn — idempotente (`noop` quando ja fora da
   default) e cobre o operador que voltou manualmente para `main` entre
   ondas. Best-effort: falha vira aviso e a retomada segue (o
   guard-branch por onda permanece como defesa):

     if [ "$(commit-mode.sh is-enabled --state-dir "$AGENTE_00C_STATE_DIR")" = "true" ]; then
       commit-mode.sh ensure-branch --projeto-alvo-path "$_proj" \
         --short-name "$SHORT" \
         || echo "ensure-branch falhou — commits por etapa serao pulados pelo guard-branch enquanto HEAD estiver na default" >&2
     fi

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
(init sem Docker, token nunca cunhado — dec-034: o modo reservado para
fallback nunca e de fato escrito pelo `start`; discriminador real e
token vazio/descritor ausente) e seguro.

```bash
_status_final=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '.execution.status' 2>/dev/null) || _status_final=""
case "$_status_final" in
  concluida|abortada)
    cstk mcp stop --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1 || :
    ;;
esac
```

> Estado `aguardando_humano` NAO e terminal — `stop` so dispara em
> `concluida`/`abortada`. Precisao pos-FASE 6 (mcp-direct-transport,
> FR-012 revoga a leitura antiga de FR-010): quem permanece coextensiva
> com a execucao inteira e sobrevive a pausas entre ondas e a **SESSAO
> MCP** (descritor `mcp-server.json` + token, no disco), NAO o processo.
> O **processo** do servidor e coextensivo com a **sessao do harness**
> (pode nao ser o mesmo PID de uma onda para outra; nada precisa
> "permanecer rodando" durante a pausa). A resolucao por chamada
> (`token -> state_dir`, sem TTL, revalidada a cada chamada contra o
> disco) e quem garante que uma nova instancia do processo retoma a
> **SESSAO MCP** correta a partir do descritor persistido.

### 4.quinquies Notificacao de leva paralela a sessao coordenadora (US2 — FR-008/FR-015, `roadmap-parallel-launch`)

Best-effort, roda apos 4.quater, ANTES do cleanup (passo 5). Mesmo
contrato do lado EMISSOR descrito em `feature-00c.md` §5.quater
(`docs/specs/roadmap-parallel-launch/contracts/parallel-launch.md` §6) —
aplicavel aqui porque um resume tambem pode ser o turno em que a execucao
alcanca um dos 3 estados terminais notificaveis (`concluida`, `abortada`,
`aguardando_humano` — **REAL**,
`plugins/cstk/skills/agente-00c-runtime/scripts/state-validate.sh:250`).
`em_andamento` NUNCA notifica.

`--coordinator-name` de `parallel-launch.sh emit` **nunca** e injetado no
comando de lancamento (confirmado em
`tests/test_parallel-launch.sh::scenario_emit_coordinator_name_valido_nao_altera_composicao`)
— o endereçamento e por CONVENCAO, `cstk-coord/<nome-do-repo>`, com
`<nome-do-repo>` derivado da MESMA tecnica de
`cli/lib/session.sh::_session_resolve_repo` (git-common-dir ->
path absoluto do repo principal -> `basename`), reusando `$_proj`.

```bash
case "$_status_final" in
  concluida|abortada|aguardando_humano)
    _gcd=$(git -C "$_proj" rev-parse --git-common-dir 2>/dev/null) || _gcd=""
    _repo_name=""
    if [ -n "$_gcd" ]; then
      _main_repo=$(cd -- "$_proj/$(dirname -- "$_gcd")" 2>/dev/null && pwd -P) || _main_repo=""
      [ -n "$_main_repo" ] && _repo_name=$(basename -- "$_main_repo")
    fi
    if [ -n "$_repo_name" ]; then
      _notify_payload="[cstk-parallel] feature=$SHORT outcome=$_status_final repo=$_repo_name"
      _notify_target="cstk-coord/$_repo_name"
      # invoque a tool SendMessage enderecada a $_notify_target com o
      # payload $_notify_payload — BEST-EFFORT (FR-015): qualquer falha
      # (sessao coordenadora inexistente, sem nome conhecido, erro da
      # tool) NUNCA bloqueia nem altera o passo 5 (Cleanup); apenas log
      # local.
    fi
    ;;
esac
```

Regras duras: imediato (sem intervalo/timeout configuravel); best-effort
(FR-015); esta sessao-filha nunca calcula fronteira nem lanca outra sessao
(FR-012).

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
