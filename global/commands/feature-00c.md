---
description: 'Inicia execucao feature-00c sobre UMA feature individual em projeto com briefing+constitution ratificados. Cria state em .claude/feature-00c-state/<short-name>/ e delega pipeline SDD (specify→clarify→plan→checklist→create-tasks→execute-task→review-task) ao agente-00c-feature-orchestrator.'
argument-hint: '"<descricao-curta>" [<short-name>] [--projeto <path>] [--whitelist <urls>]'
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
  - Glob
  - ScheduleWakeup
---

# /feature-00c

Voce vai iniciar uma execucao do orquestrador autonomo feature-00c
conforme contrato em `docs/specs/_archived/feature-00c/contracts/cli-invocation.md`.

> **Fronteira command↔orquestrador (lock + init)**: este command PAI detem
> o lock (acquire no passo 7, release SEMPRE no Cleanup) e inicializa o
> `state.json` (passo 3). O orquestrador NAO adquire lock nem re-inicializa
> estado — contrato canonico em "Fronteira command↔orquestrador" de
> `agente-00c-feature-orchestrator.md`. Identico no resume
> (`/feature-00c-resume`).

## Argumentos recebidos

```
$ARGUMENTS
```

## Comportamento esperado

### 0. Warm-up de permissoes (CRITICO — antes de qualquer outra coisa)

A pipeline feature-00c invoca varias skills/tools ao longo de ondas.
Permissoes pedidas "lazy" quebram a autonomia se o operador nao estiver
presente. Solucao: invocar TODAS as skills/tools em batch ANTES de
qualquer logica.

Apresente ao operador:

```
Feature-00C — Warm-up de permissoes

Vou agora invocar cada skill/tool que sera usada na pipeline para
disparar TODOS os prompts de permissao em batch. Voce sera questionado
sobre cada uma; aprove para autorizar a execucao autonoma posterior.

Continuar? [s/N]
```

Se confirmado, execute em sequencia (cada item dispara o prompt nativo):

| # | Tool/Skill | Modo de warm-up |
|---|------------|-----------------|
| 1 | tool Skill — `specify` | invocar com prompt minimo "responda OK" |
| 2 | tool Skill — `clarify` | idem |
| 3 | tool Skill — `plan` | idem |
| 4 | tool Skill — `checklist` | idem |
| 5 | tool Skill — `create-tasks` | idem |
| 6 | tool Skill — `execute-task` | idem |
| 7 | tool Skill — `review-task` | idem |
| 8 | tool Skill — `validate-documentation` (Quality Gate) | invocar com `--help` ou prompt minimo "responda OK" |
| 9 | tool Skill — `validate-docs-rendered` (Quality Gate) | idem |
| 10 | tool Skill — `owasp-security` (Quality Gate) | idem |
| 11 | tool Agent — `agente-00c-feature-orchestrator` | spawn com prompt `"warm-up: responda READY"` |
| 12 | tool Agent — `feature-00c-clarify-asker` | idem |
| 13 | tool Agent — `feature-00c-clarify-answerer` | idem |
| 14 | tool ScheduleWakeup | `delaySeconds: 60` + `prompt: "warm-up no-op"` |
| 15 | tool Bash — `state-rw.sh --help` | dispara permissao Bash |

> **Quality Gates (items 8-10)**: skills incentivadas pelo PR #6 do
> toolkit (v3.12.0), portadas para feature-00c via §"Quality Gates
> complementares" do `agente-00c-feature-orchestrator.md`. Cobrem
> doc-quality apos specify+plan, security (OWASP) apos plan, e
> docs-render apos create-tasks. Sem warm-up, primeira invocacao trava
> aguardando permissao.

Se o operador NAO confirmar, abortar com exit 0 + mensagem instrutiva.

### 1. Parse de argumentos

```
descricao_curta  = primeiro argumento (string em quotes, OBRIGATORIO, <=500 chars)
short_name       = segundo argumento posicional opcional (kebab-case);
                   se omitido, derivar via specify
--projeto PATH   = default = cwd
--whitelist CSV  = URLs externas adicionais ao .env (opcional)
```

Validar:
- `descricao_curta` nao-vazio, <=500 chars
- `short_name` (se fornecido) e kebab-case valido: `^[a-z][a-z0-9-]*$`

### 2. Pre-flight (ordem CRITICA — falhas abortam antes de tocar disco)

Exporte: `AGENTE_00C_STATE_DIR=<projeto>/.claude/feature-00c-state/<short_name>`

```
1. realpath do projeto:
   _proj=$(realpath "$PROJETO" 2>/dev/null) || abortar exit 1
   - rejeitar zonas proibidas via path-guard.sh validate-target

2. sanitizar descricao_curta:
   _desc=$(printf '%s' "$DESC" | sanitize.sh limit-length --max 500)
   - se >500 chars, truncar + warning (limit-length trunca e adiciona "...")

3. validar briefing (FR-PRE-001):
   _br="$_proj/docs/01-briefing-discovery/briefing.md"
   - existe + nao-vazio + seções mínimas (visão, usuários-alvo, restrições, prioridades)
   - sem placeholders [TBD]/[A definir]/[FILL]/TODO em seções minimas
   - se falha: stderr "/briefing antes ou /agente-00c para bootstrap"; exit 1

4. validar constitution (FR-PRE-002):
   _ct="$_proj/docs/constitution.md"
   - existe + versao >=1.0.0 no rodape **Version**: X.Y.Z
   - bloco ## Core Principles com >=1 principio com corpo
   - sem placeholder no body dos principios
   - se falha: stderr "/constitution antes ou /agente-00c para bootstrap"; exit 1

5. coexistencia agente-00c (FR-026):
   _agstate="$_proj/.claude/agente-00c-state/state.json"
   if [ -f "$_agstate" ]; then
     _status=$(jq -r '(.execution.status // .execucao.status) // "unknown"' "$_agstate" 2>/dev/null)
     case "$_status" in
       em_andamento|aguardando_humano)
         stderr "agente-00c esta ativo (status=$_status). Resolva via /agente-00c-abort ou /agente-00c-resume."
         exit 2
         ;;
     esac
   fi

6. feature pre-existente (FR-006):
   _spec="$_proj/docs/specs/$SHORT/spec.md"
   if [ -f "$_spec" ] && [ -s "$_spec" ]; then
     - apresentar bloqueio humano in-band com 2 opcoes:
       (a) retomar a partir da spec existente (entra direto em clarify)
       (b) abortar a invocacao
     - aguardar resposta antes de prosseguir
   fi

7. lock por short-name (FR-028) — o command PAI detem o lock; o
   orquestrador NAO o re-adquire (ver Fronteira):
   _lock="$AGENTE_00C_STATE_DIR/.lock"
   state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR"
   - se ocupado, stderr "outra sessao ativa para $SHORT"; exit 3

8. coleta de consumo: PEDIR instalacao ao operador (nunca instalar sozinho)
   guard-hooks-status.sh check --projeto-alvo-path "$_proj" || :
   otel-usage.sh preflight || :
   - READ-ONLY: diagnosticam, nunca instalam. Os tres hooks ativos E
     `current` (4a coluna do TSV) => siga sem incomodar o operador.
   - 4a coluna `stale` = copia do projeto diverge da do catalogo: reprova
     igual a ausente, MESMA remediacao (`cstk hooks install`). Copia stale
     roda codigo de versao anterior — foi assim que o cutover
     `state.json`->`state.db` zerou `tool_calls` em projetos que exibiam
     "3/3 hooks ativos". `unknown` nao e veredito: siga.
   - preflight com `status=port-conflict` (porta do exporter presa por
     OUTRO processo; owner_pid/owner_cwd na saida) ou `status=exporter-down`
     => REPASSE o aviso ao operador antes de seguir (execucao sairia com
     otel_usage null em toda onda). ok/disabled/unverified => siga.
   - Faltando algum OU algum `stale` => PECA a instalacao, apresentando os
     3 pontos:

     (1) O que instala e para que serve — nenhum e redundante:
         . pretooluse-bash-guard.sh  -> guarda fail-closed de Bash.
           NAO substituivel: e seguranca, nao metrica.
         . posttooluse-tool-call-tick.sh -> alimenta tool_calls (proxy de
           orcamento da onda). NAO substituivel: a telemetria OTel conta
           API requests e tokens, nao tool calls.
         . posttooluse-agent-usage.sh -> consumo POR SPAWN (agent_id,
           agent_type). Parcialmente substituido: o total por onda hoje vem
           do OTel com mais precisao; o detalhe por spawn so vem daqui.

     (2) O custo — diga o NUMERO (medido; nao ha custo de token, sao shell
         local):
         . tick: ~30 ms por tool call (matcher "*", roda em TODAS) —
           ~6 s numa onda de ~200 tool calls
         . bash-guard: ~177 ms por chamada Bash
         . coleta de custo real por onda (opcional): ~37 ms x2 por onda

     (3) Como ativa — dois opt-ins independentes:
         cd "$_proj" && cstk hooks install
         export CLAUDE_CODE_ENABLE_TELEMETRY=1
         export OTEL_METRICS_EXPORTER=prometheus
         (o segundo nao exige API key, Admin key nem organizacao; funciona
          em assinatura e nada sai de 127.0.0.1. ATENCAO: so UM processo do
          Claude Code faz bind da porta fixa 9464 — com outro processo aberto
          antes, esta sessao nao mede nada, otel_usage null em toda onda; o
          preflight do diagnostico acima detecta. Mitigacao: launcher de
          porta dinamica por processo, ver README "Real per-wave cost")

   - Regra de decisao:
     . sim  => pedir que rode `cstk hooks install` e confirmar antes de seguir
     . nao / sem resposta => SEGUIR normalmente (metrica nunca bloqueia a
       pipeline), mas registrar sem eufemismo: a guarda de Bash nao esta
       enforced nesta execucao e tool_calls ficara 0 (ausente, nao medido)
     . NUNCA instalar sem consentimento: `cstk hooks install` escreve em
       <projeto-alvo>/.claude/settings.json, que pode estar versionado
```

### 3. Init do state.json

```
mkdir -p "$AGENTE_00C_STATE_DIR/backups"
_br_sha=$(sha256sum "$_br" | awk '{print $1}')
_ct_sha=$(sha256sum "$_ct" | awk '{print $1}')
_ct_ver=$(grep -E '^\*\*Version\*\*:' "$_ct" | sed -E 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
_aspectos=$(drift.sh extract --text "$_desc")  # 3-7 keywords

# Worktree detection (recall-worktree-identity — FR-001/FR-002/FR-008)
# Toda falha = fallback silencioso; flags omitidas ao init (US3 AC3).
# Deteccao: .git ARQUIVO (worktree) vs .git DIRETORIO (projeto raiz — omitir flags; CHK011).
_canonical="" ; _session=""
if [ -f "$_proj/.git" ]; then
  # Passo a: obter common-dir (git plumbing, read-only)
  _common=$(git -C "$_proj" rev-parse --git-common-dir 2>/dev/null) || _common=""
  if [ -n "$_common" ]; then
    # Passo b: normalizar para absoluto (git antigo pode retornar path relativo)
    case "$_common" in
      /*) : ;;  # ja absoluto
      *)  _common="$_proj/$_common" ;;
    esac
    # Passo c: canonical = basename do parent do common-dir
    _canonical=$(basename "$(dirname "$_common")")
    # Passo d: session = sufixo apos "<canonical>-" no basename do PAP
    _wtbase=$(basename "$_proj")
    case "$_wtbase" in
      "${_canonical}-"*) _session="${_wtbase#"${_canonical}-"}" ;;
      *)                 _session="" ;;
    esac
  fi
fi
# .git diretorio (projeto raiz): _canonical e _session permanecem vazios (flags omitidas).

# Prompt opt-in de commit atomico (FR-001/FR-002 — atomic-commit-pr)
# Antes de inicializar o state.json, perguntar ao operador se deseja
# habilitar o modo de commit atomico (opt-in, default "nao"):
#
# Apresente ao operador:
# ---
# Modo atomic-commit (opcional):
# Quando habilitado, a pipeline cria um commit git a cada etapa concluida
# (specify, plan, checklist, create-tasks) e um commit agrupado ao final
# de cada onda de execute-task. Ao final da pipeline, faz push+PR
# automaticamente se houver branch nao-default.
#
# Habilitar o modo atomic-commit? [s/N]
# ---
# - Respostas afirmativas (s/S/y/Y/sim/yes): _atomic=true
# - Qualquer outra resposta (inclusive Enter): _atomic=false (default seguro)
# Os commands de resume NAO re-promptam: /feature-00c-resume le
# .atomic_commit_enabled diretamente do state.json sem interacao.

state-rw.sh init --state-dir "$AGENTE_00C_STATE_DIR" \
  --short-name "$SHORT" \
  --projeto-alvo-path "$_proj" \
  --descricao "$_desc" \
  --briefing-path "$_br" --briefing-sha256 "$_br_sha" \
  --constitution-path "$_ct" --constitution-sha256 "$_ct_sha" \
  --constitution-version "$_ct_ver" \
  --key-aspects "$_aspectos" \
  ${_canonical:+--canonical-project "$_canonical"} \
  ${_session:+--session-name "$_session"} \
  --atomic-commit "$_atomic"
```

### 3.bis Ciclo de vida do servidor MCP (status/start) — FASE 6 task 6.2.1

Best-effort, NUNCA bloqueia a pipeline (FR-007/FR-012 — indisponibilidade
do MCP cai no caminho `Bash` existente, zero regressao). Roda logo apos o
init do `state.json` (passo 3), ANTES do spawn do orquestrador (passo 4):

```bash
if cstk mcp status --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1; then
  # "disponivel" aqui significa: o subcomando `cstk mcp` existe e respondeu
  # nesta instalacao (nao que o Docker esteja de pe — status=unavailable
  # com reason=no-active-execution E ESPERADO neste ponto, ja que o
  # descritor mcp-server.json ainda nao existe para uma execucao recem-
  # inicializada; cli/lib/mcp.sh::_mcp_print_status_from_descriptor). A
  # decisao real de disponibilidade de Docker fica DENTRO de `start`, que
  # faz seu proprio preflight e degrada sozinho para mode=bash-fallback
  # sem abortar (dec-099).
  cstk mcp start --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1 || :
else
  : # subcomando `mcp` ausente (instalacao sem self-update recente) ou
    # `--state-dir` invalido — pula silenciosamente; pipeline segue no
    # caminho Bash de hoje (zero regressao)
fi
```

> **Injecao do token de capacidade (dec-043 / SEC-H3)** — consumacao da
> coordenacao cross-feature da task 1.2. Apos o `start`, leia o descritor
> e injete o token no CONTEXTO do spawn do orquestrador:
>
> ```bash
> _mcp_mode=$(jq -r '.mode // "-"' "$AGENTE_00C_STATE_DIR/mcp-server.json" 2>/dev/null) || _mcp_mode="-"
> _mcp_token=""
> if [ "$_mcp_mode" = "docker" ]; then
>   _mcp_token=$(jq -r '.session_id // ""' "$AGENTE_00C_STATE_DIR/mcp-server.json" 2>/dev/null) || _mcp_token=""
> fi
> ```
>
> - `_mcp_token` NAO-vazio ⇒ inclua no prompt do orquestrador a linha:
>   `MCP: servidor de estado ativo; session_id=<token>. Prefira as tools
>   mcp__cstk-state__* (open_wave, record_decision, record_skill,
>   record_task, register_human_block, close_wave, get_status)
>   apresentando ESTE session_id em cada chamada; em erro de transporte,
>   contrato de queda mid-onda (0 retries + 1 confirmacao via cstk mcp
>   status --live) e comutacao para Bash no resto da onda.`
> - `_mcp_token` vazio (`bash-fallback` / sem descritor) ⇒ NAO mencione MCP
>   no prompt; o orquestrador segue o caminho Bash (zero regressao, SC-004).
> - O token NUNCA e ecoado em stdout/stderr/logs do command — vive apenas
>   no descritor (`chmod 600`) e no prompt do spawn (SEC-H3: roteamento por
>   capacidade, nunca por precedencia).

### 4. Selecionar modelo da onda + delegar ao orquestrador via Agent

Migrate defensivo (best-effort): canonicaliza um `state.json` pt-BR legado
para EN no lugar ANTES de qualquer direct-writer (orquestrador, `wave-select`)
tocar o arquivo (schema-en-migration, arquitetura B+). Idempotente/no-op em
states ja EN; degrada graciosamente (falha nao gateia):

```bash
state-rw.sh migrate --state-dir "$AGENTE_00C_STATE_DIR"
```

Antes de spawnar, compute o modelo a aplicar nesta onda via `wave-select`
(mapa fase→modelo + refino model-selector + override do operador — FR-002,
FR-009). A seleção é idempotente por onda (re-entrada não duplica Decisão):

```bash
MODEL=$(model-routing.sh wave-select --state-dir "$AGENTE_00C_STATE_DIR")
```

`wave-select` SEMPRE emite uma linha em stdout: `haiku` | `sonnet` |
`opus` | `manter-atual` (nunca aborta — fallback gracioso para
`manter-atual`). A escolha já foi registrada como `DecisãoDeRoteamentoPorOnda`
auditável dentro do próprio `wave-select`.

Spawne aplicando o param `model` SOMENTE quando `MODEL != manter-atual`
(FR-006, quickstart C8 — `manter-atual` herda o modelo da sessão):

- Se `MODEL = manter-atual`: spawnar SEM o param `model`.
  ```
  Agent {
    subagent_type: "agente-00c-feature-orchestrator",
    prompt: <contexto com short_name, projeto, state_dir, briefing_path, constitution_path>
  }
  ```
- Senão (`MODEL ∈ {haiku, sonnet, opus}`): spawnar COM `model=<MODEL>`.
  ```
  Agent {
    subagent_type: "agente-00c-feature-orchestrator",
    model: <MODEL>,
    prompt: <contexto com short_name, projeto, state_dir, briefing_path, constitution_path>
  }
  ```

> Bidirecionalidade (FR-009): `wave-select` pode subir (sonnet→opus em
> fases profundas) ou descer (opus→haiku em fases rasas) o modelo entre
> ondas. O prompt do orquestrador NÃO muda — só o invólucro do spawn
> ganha o param `model`.

### 5. Pos-orquestrador: rede de seguranca de fechamento de onda (OBRIGATORIO)

> **Bug recorrente**: o orquestrador frequentemente RETORNA sem fechar a
> onda nem emitir `Schedule intent` (ver "Contrato de conclusao de turno"
> no `agente-00c-feature-orchestrator.md`). Reforco de prompt nao resolve;
> o PAI trata o fechamento como rede de seguranca OBRIGATORIA a CADA
> retorno, nao condicional a `Schedule intent`.

Chame `reconcile-wave` SEMPRE, antes de capturar o Schedule intent. E
idempotente: no-op se o orquestrador JA fechou a onda (sem double-count);
se a deixou aberta, fecha deterministicamente (record-skill + end +
avanca `current_stage`/`next_instruction`, ou promove
`.execution.status=concluida` na fase terminal). `--terminal-phase
review-task` (feature-00c termina em review-task). Best-effort.

```bash
# Se a fase corrente for execute-task, localize tasks.md e passe --tasks-md.
state-ondas.sh reconcile-wave --state-dir "$AGENTE_00C_STATE_DIR" \
  --terminal-phase review-task \
  2>/dev/null || echo "reconcile-wave: rede de seguranca pulada" >&2
```

Depois, capture/derive o Schedule intent. O orquestrador retorna no
sumario uma linha tipo:

```
Schedule intent: delaySeconds=270; reason="<...>"; prompt="/feature-00c-resume <short>"
```

OU:

```
Schedule intent: none (motivo: bloqueio_humano|aborto|concluido)
```

Se `Schedule intent: ...` com parametros:
```
ScheduleWakeup(
  delaySeconds: <N>,
  reason: <reason>,
  prompt: "/feature-00c-resume <short>"
)
```

Se o orquestrador parou cedo (SEM linha `Schedule intent:`) e a
reconciliacao fechou a onda, DERIVE do `.execution.status` real:
- terminal (`concluida`/`abortada`/`aguardando_humano`): NAO agendar.
- `em_andamento`: `ScheduleWakeup(delaySeconds: 270, reason: "proxima onda (recuperada pela rede de seguranca)", prompt: "/feature-00c-resume <short>")`.

Se `Schedule intent: none`, NAO invocar ScheduleWakeup. Apenas liberar
lock e exit 0.

### 5.bis Ingestao da onda na knowledge.db (rede de seguranca, best-effort)

A ingestao canonica e o passo **10.bis** do loop do orquestrador
(`agente-00c-feature-orchestrator.md`). Este eco no pai e uma REDE DE
SEGURANCA para o caso de o orquestrador retornar SEM completar o loop —
onda fechada/recuperada manualmente por este comando, sem ter chegado ao
10.bis. Sem ele, a `knowledge.db` fica sem o conhecimento da onda (sintoma
observado: state.json atualizado, knowledge.db vazia).

```bash
# Idempotente (upsert por chave natural (project,feature,wave,source_id)):
# se o orquestrador JA ingeriu no 10.bis, re-ingerir e inofensivo. Read-only
# sobre o state.json; escreve apenas em ~/.claude/cstk/knowledge.db (indice
# derivado/reconstruivel). NUNCA gateia — toda falha (cstk fora do PATH,
# sqlite3/jq ausentes, dir nao-gravavel) degrada para no-op.
cstk recall --ingest --state-dir "$AGENTE_00C_STATE_DIR" 2>/dev/null \
  || echo "knowledge-db: ingestao (rede de seguranca) pulada — cstk/sqlite3/jq ausentes" >&2
```

### 5.ter Encerramento do servidor MCP em estado terminal — FASE 6 task 6.2.3

Best-effort, roda apos 5.bis, ANTES do cleanup (passo 6). `cstk mcp stop`
e idempotente (parar o que ja esta parado, ou `--state-dir` sem descritor
algum, e exit 0) — chamar mesmo quando o servidor nunca chegou a subir
(mode=bash-fallback ou init sem Docker) e seguro. Raro na primeira
invocacao (normalmente termina em `em_andamento` com Schedule intent),
mas cobre o caso de uma execucao curta que ja fecha terminal na propria
primeira onda:

```bash
_status_final=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '.execution.status' 2>/dev/null) || _status_final=""
case "$_status_final" in
  concluida|abortada)
    cstk mcp stop --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1 || :
    ;;
esac
```

### 6. Cleanup

- `state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"` SEMPRE
  (mesmo em paths de erro).
- `git add` + `git commit -m "feature-00c init: $SHORT"` (commit local
  do estado inicial; alinha com auditoria — sem `git push`).

## Exit codes (cli-invocation.md)

| Exit | Significado |
|------|-------------|
| 0 | Sucesso |
| 1 | Erro geral / pre-flight falhou |
| 2 | Coexistencia bloqueada (agente-00c ativo) |
| 3 | Lock ocupado |

## Anti-padroes

- **NAO criar artefatos antes do passo 7** (lock). SC-PRE-001 exige
  filesystem inalterado em caso de pre-flight falhar.
- **NAO chamar ScheduleWakeup** se status terminal (bloqueio/aborto/
  concluido) — schedule e exclusivo para status `em_andamento`.
- **NAO bypassar** o check de coexistencia (FR-026) — execucao
  concorrente com agente-00c quebra namespace isolation.
