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

**Nao-interativo**: PULE o warm-up inteiro e prossiga para o passo 1 —
nunca aborte, nunca fique aguardando a confirmacao. Sem operador presente
nao ha prompt de permissao a enfileirar (a politica ja esta resolvida por
allowlist/settings do processo), entao o warm-up perde a funcao; abortar
aqui inviabiliza toda automacao legitima (cron, CI, execucao agendada).
Emita o aviso e registre a Decisao:

```
Warm-up pulado: execucao nao-interativa (nenhum operador para confirmar).
Ferramentas sem permissao previa falharao pontualmente em vez de travar a
onda.
```

`state-decisions.sh register --agente "feature-00c" --etapa "specify"
--contexto "Warm-up de permissoes pulado: execucao nao-interativa"
--opcoes '["proceder","abortar"]' --escolha "proceder" --justificativa
"Sem operador para confirmar; warm-up nao tem funcao em execucao
nao-interativa e abortar inviabilizaria automacao"`.

> Esta clausula NAO afrouxa nenhuma guarda: `bash-guard.sh`,
> `path-guard.sh` e `secrets-filter.sh` seguem enforced, e o hook
> `PreToolUse` continua fail-closed. O que muda e apenas o enfileiramento
> antecipado de prompts, que so faz sentido com humano presente.
>
> Paridade com `/agente-00c`: mesma clausula, mesmo motivo (achado do
> spike headless de 2026-08-15, em que ambos os commands abortavam em
> `Continuar? [s/N]` e nenhuma execucao agendada conseguia iniciar).

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

#### Modo de reabertura (`--reopen`) — FR-001, FR-019

```
/feature-00c --reopen <short-name> "<descricao do incremento>"
```

Quando o **primeiro argumento** e literalmente `--reopen`, o parsing muda:

```
short_name       = segundo argumento (OBRIGATORIO, kebab-case — sem
                   fallback via specify: a feature ja existe)
descricao_curta  = terceiro argumento (string em quotes, OBRIGATORIO,
                   <=500 chars) — descreve o INCREMENTO, nao a feature
                   inteira
--projeto PATH   = default = cwd (mesma semantica do modo normal)
```

Este modo se aplica **somente** a pipeline de feature individual —
`/agente-00c` e seus resumes **nao sao tocados** (FR-019). Os itens 1-5
do pre-flight abaixo sao **integralmente reaproveitados**; o modo de
reabertura se insere como ramo entre os itens 6 e 7 — ver "### 2.bis Modo
de reabertura (--reopen)" logo apos o pre-flight.

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
   _br="$_proj/docs/briefing.md"
   [ -f "$_br" ] || _br="$_proj/docs/01-briefing-discovery/briefing.md"  # legado
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

6. deteccao de execucao pre-existente (FR-006, FR-016, FR-017) — **so
   roda no modo de abertura NORMAL** (sem `--reopen`). Se a invocacao ja
   comecou com `--reopen`, PULE este item inteiro e va direto para
   "### 2.bis Modo de reabertura (--reopen)" abaixo, comecando em 6.a.

   _spec="$_proj/docs/specs/$SHORT/spec.md"
   _has_spec=false
   [ -f "$_spec" ] && [ -s "$_spec" ] && _has_spec=true

   # FR-017: o item 6 antigo so testava spec.md — o caso mais comum no
   # repo (spec arquivada + estado terminal no lugar) nao disparava
   # aviso nenhum. Detectar TAMBEM state-dir com estado terminal:
   _has_terminal_state=false
   if [ -d "$AGENTE_00C_STATE_DIR" ] && \
      { [ -f "$AGENTE_00C_STATE_DIR/state.json" ] || [ -f "$AGENTE_00C_STATE_DIR/state.db" ]; }; then
     if state-lock.sh check-execution-busy --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1; then
       _has_terminal_state=true   # exit 0 = ''/abortada/concluida (terminal)
     fi
     # exit 3 (em_andamento/aguardando_humano): NAO e "pre-existente
     # encerrada" — segue o pre-flight normal; o item 7 (lock) resolve
     # a colisao de execucao viva na hora certa, sem passar por aqui
   fi

   if [ "$_has_spec" = true ] || [ "$_has_terminal_state" = true ]; then
     - apresentar bloqueio humano IN-BAND (prosa — nenhuma escrita em
       disco ainda, mesma disciplina do restante do pre-flight) com as
       opcoes:
       (a) reabrir a partir do estado existente — FR-016: esta opcao
           MUST levar a uma execucao de fato, NUNCA a um aborto (o bug
           antigo: `state-rw.sh init` morria contra o state.json/
           state.db ja existente logo depois)
       (b) abortar a invocacao
     - a mensagem MUST citar comandos do escopo de FEATURE, NUNCA
       `/agente-00c-*` (FR-017): "/feature-00c --reopen $SHORT
       \"<descricao>\"", "/feature-00c-resume $SHORT",
       "/feature-00c-abort $SHORT"
     - aguardar resposta antes de prosseguir
     - se (a): NAO chamar `state-rw.sh init` aqui. Prossiga para
       "### 2.bis Modo de reabertura (--reopen)" abaixo, comecando em
       6.a, com `_desc` = a descricao ja fornecida nesta invocacao
       normal (tratada como o incremento) e `SHORT` inalterado
     - se (b): abortar a invocacao, exit 0
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

### 2.bis Modo de reabertura (`--reopen`) — passos 6.a..3''

Ref: `docs/specs/feature-reopen/contracts/reopen-flow.md`.

Executado quando: (a) a invocacao comecou com `--reopen`, OU (b) o item 6
acima detectou execucao pre-existente e o operador escolheu a opcao
"reabrir". Nos dois casos os itens 1-5 do pre-flight ja rodaram
normalmente (path-guard, sanitize, briefing, constitution, coexistencia
agente-00c) — este modo NAO os repete.

Ordem normativa: **toda recusa acontece antes de qualquer escrita em
disco**.

```
6.a   pre-condicoes de recusa       [NENHUMA ESCRITA ATE AQUI]
6.b   sonda de trabalho pendente
6.c   parecer + bloqueio humano     [aguarda operador]
7     lock (acquire)                [primeira escrita possivel — item 7 acima]
7.a   re-verificacao pos-lock       (fecha TOCTOU)
7.b   state-rounds.sh recover       (limbo pendente?)
7.c   state-rounds.sh rotate        [ponto de commit da rotacao]
7.d   restauracao de spec arquivada (se aplicavel)
8     diagnostico de consumo        (item 8 acima, sem mudanca)
3'    state-rw.sh init              (secao 3 abaixo, com 1 flag derivada)
3''   grava .previous_round + Decisao do parecer
```

#### 6.a — pre-condicoes de recusa (FR-002, FR-003)

Nenhum comando abaixo escreve em disco.

```
_skip_rotate=false

if [ ! -d "$AGENTE_00C_STATE_DIR" ] || \
   { [ ! -f "$AGENTE_00C_STATE_DIR/state.json" ] && [ ! -f "$AGENTE_00C_STATE_DIR/state.db" ]; }; then
  # raiz sem estado transacional — checar 1b antes de recusar
  _has_round=false
  if [ -d "$AGENTE_00C_STATE_DIR/rounds" ]; then
    for _rd in "$AGENTE_00C_STATE_DIR"/rounds/r*/; do
      [ -d "$_rd" ] || continue
      { [ -f "${_rd}state.json" ] || [ -f "${_rd}state.db" ]; } && _has_round=true
    done
  fi
  if [ "$_has_round" = false ]; then
    stderr "feature '$SHORT' nao possui execucao anterior. Use a abertura normal: /feature-00c \"<descricao>\" $SHORT"
    exit 4
  fi
  # 1b (T-37): rotacao ja consumada por uma invocacao anterior cujo init
  # nunca rodou — NAO e recusa, e conciliacao (3.3.6): pular o passo 7.c,
  # ir direto ao init usando o maior label existente
  _skip_rotate=true
else
  _busy_err=$(state-lock.sh check-execution-busy --state-dir "$AGENTE_00C_STATE_DIR" 2>&1 1>/dev/null)
  _busy_rc=$?
  if [ "$_busy_rc" != 0 ]; then
    if [ "$_busy_rc" = 3 ]; then
      stderr "execucao anterior de '$SHORT' ainda ativa. Use /feature-00c-resume $SHORT para retomar, ou /feature-00c-abort $SHORT para abortar."
      exit 5
    fi
    stderr "$_busy_err"
    exit 1
  fi
fi
```

`check-execution-busy` e read-only; exit `0` cobre `''`/`abortada`/
`concluida` (terminal ou vazio) — exatamente o que FR-003 e FR-020
precisam.

#### 6.b — sonda de trabalho pendente (FR-021, delegada a `commit-mode.sh`)

```
_branch=$(git -C "$_proj" branch --show-current 2>/dev/null) || _branch=""
_pending_note="trabalho pendente: nao verificado (repositorio sem branch git detectavel)"
if [ -n "$_branch" ]; then
  _probe_line=$(commit-mode.sh probe-pending-work --state-dir "$AGENTE_00C_STATE_DIR" \
    --projeto-alvo-path "$_proj" -- "$_branch" 2>/dev/null) || _probe_line=""
  if [ -n "$_probe_line" ]; then
    IFS='|' read -r _pw_tag _pw_branch _pw_default _pw_merged _pw_prstate \
      _pw_prurl _pw_source _pw_status <<PROBE_EOF
$_probe_line
PROBE_EOF
    case "$_pw_status" in
      checked)
        if [ "$_pw_merged" = "no" ]; then
          _pending_note="trabalho pendente: branch '$_pw_branch' ainda nao mesclada em '$_pw_default'"
          if [ "$_pw_prstate" != "unknown" ] && [ "$_pw_prstate" != "-" ]; then
            _pending_note="$_pending_note; PR $_pw_prstate ($_pw_prurl)"
          fi
          _pending_note="$_pending_note (fonte: $_pw_source)"
        else
          _pending_note="sem trabalho pendente detectado (branch '$_pw_branch' ja mesclada em '$_pw_default'; fonte: $_pw_source)"
        fi
        ;;
      *)
        _pending_note="trabalho pendente: nao verificado (probe_status=$_pw_status; fonte: $_pw_source)"
        ;;
    esac
  fi
fi
```

Principio VI (I-P1): `_pending_note` NUNCA afirma "sem pendencia" quando
o `probe_status` nao foi `checked` — sempre "nao verificado". O aviso e
sempre informativo, nunca bloqueia (FR-021).

#### 6.c — parecer + bloqueio humano (FR-004, FR-005, FR-006, FR-020, FR-021)

Antes de qualquer escrita, monte e apresente ao operador (in-band, mesma
disciplina do item 6):

- **Recomendacao** (`reabrir` | `abrir-feature-nova`): leia a spec da
  feature-alvo (path ativo se existir; senao a copia sob `_archived/`,
  resolvida pela MESMA logica de 7.d abaixo — leitura, sem copiar ainda)
  e compare com `_desc` (o incremento). Cite os pontos comparados na
  justificativa. Esta comparacao e semantica — feita por voce, LLM
  orquestrador, NUNCA por score automatico (restricao travada, Decision
  10 de `research.md`).
- **Status do round anterior**: se `abortada`, declare explicitamente que
  o round anterior **nao chegou ao fim** (FR-020).
- **`$_pending_note`** (passo 6.b) — informativo, nunca bloqueia.
- Se a spec estiver arquivada (nao ha `docs/specs/$SHORT/spec.md` ativo e
  nao-vazio), avise que ela sera restaurada de `_archived/...` na
  confirmacao (FR-013).

Apresente as duas opcoes ao operador:

```
(a) reabrir — prossegue com a reabertura (mesmo se contrariar a
    recomendacao — FR-005)
(b) abortar-invocacao — nada e escrito, exit 0
```

Se `abortar-invocacao`: exit `0` (deliberado — o fluxo consultou e
obedeceu, nada foi escrito). Se o parecer recomendou `abrir-feature-nova`
e o operador escolhe abortar, **nao** crie a feature nova por conta
propria (FR-005) — apenas ja instruiu como faze-lo no parecer.

Guarde em memoria `_recommendation`, `_operator_choice="reabrir"` e
`_rationale` — a Decisao so pode ser gravada **depois** do init (passo
3'', ela e "da execucao nova" — FR-006).

#### 7 — lock (primeira escrita possivel)

Reusar o item 7 do pre-flight acima (`state-lock.sh acquire --state-dir
"$AGENTE_00C_STATE_DIR"`), sem mudanca.

#### 7.a — re-verificacao pos-lock (fecha TOCTOU)

```
if [ "$_skip_rotate" = false ]; then
  if ! state-lock.sh check-execution-busy --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1; then
    state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"
    stderr "execucao anterior de '$SHORT' ficou ativa entre a checagem e o lock. Use /feature-00c-resume $SHORT ou /feature-00c-abort $SHORT."
    exit 5
  fi
  if [ ! -f "$AGENTE_00C_STATE_DIR/state.json" ] && [ ! -f "$AGENTE_00C_STATE_DIR/state.db" ]; then
    state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"
    stderr "estado de '$SHORT' desapareceu entre a checagem e o lock (janela TOCTOU rara)."
    exit 4
  fi
fi
```

Janela remanescente entre 6.a e o `acquire` e aceitavel e documentada
(Decision 7 de `research.md`).

#### 7.b — `state-rounds.sh recover`

```
_rec_rc=0
recover_line=$(state-rounds.sh recover --state-dir "$AGENTE_00C_STATE_DIR") || _rec_rc=$?
if [ "$_rec_rc" != 0 ]; then
  state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"
  if [ "$_rec_rc" = 1 ]; then
    stderr "rotacao pendente irrecuperavel automaticamente para '$SHORT' (journal invalido). Nada rotacionado."
    exit 6
  fi
  stderr "erro inesperado em state-rounds.sh recover: $recover_line"
  exit 1
fi
```

`recover` e idempotente (sem journal ⇒ no-op exit `0`) e seguro de
chamar mesmo quando `_skip_rotate=true`.

#### 7.c — `state-rounds.sh rotate` (pulado se `_skip_rotate=true`)

```
if [ "$_skip_rotate" = false ]; then
  _round_line=$(state-rounds.sh rotate --state-dir "$AGENTE_00C_STATE_DIR") || {
    state-lock.sh release --state-dir "$AGENTE_00C_STATE_DIR"
    stderr "erro inesperado em state-rounds.sh rotate: $_round_line"
    exit 1
  }
  # ROUND|<label>|<backend>|<state_file>|<execution_id>|<status>
  IFS='|' read -r _rl_tag _label _rl_backend _rl_state_file _prev_exec_id _prev_status <<ROUND_EOF
$_round_line
ROUND_EOF
  _rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
else
  # 1b: rotacao ja consumada em invocacao anterior — usar o maior label
  # existente (state-rounds.sh list ordena lexicograficamente crescente)
  _list_line=$(state-rounds.sh list --state-dir "$AGENTE_00C_STATE_DIR" | tail -1)
  IFS='|' read -r _label _rl_backend _rl_state_file _prev_exec_id _prev_status _finished_at <<LIST_EOF
$_list_line
LIST_EOF
  _round_dir="$AGENTE_00C_STATE_DIR/rounds/$_label"
  _mtime_epoch=$(stat -c '%Y' -- "$_round_dir" 2>/dev/null) || \
    _mtime_epoch=$(stat -f '%m' -- "$_round_dir" 2>/dev/null) || _mtime_epoch=""
  _rotated_at=""
  if [ -n "$_mtime_epoch" ]; then
    _rotated_at=$(date -u -d "@$_mtime_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || \
      _rotated_at=$(date -u -r "$_mtime_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _rotated_at=""
  fi
  [ -n "$_rotated_at" ] || _rotated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi
```

Ponto de commit da rotacao (quando nao pulada). `_label`/`_prev_exec_id`/
`_prev_status` alimentam `.previous_round` no passo 3''.

#### 7.d — restauracao de spec arquivada (FR-013, so diretorios)

```
_spec="$_proj/docs/specs/$SHORT/spec.md"
_spec_dir="$_proj/docs/specs/$SHORT"
if [ ! -s "$_spec" ] && { [ ! -d "$_spec_dir" ] || [ -z "$(ls -A "$_spec_dir" 2>/dev/null)" ]; }; then
  _origin=""
  if [ -d "$_proj/docs/specs/_archived/$SHORT" ]; then
    _origin="$_proj/docs/specs/_archived/$SHORT"
  else
    _origin=$(find "$_proj/docs/specs/_archived" -maxdepth 1 -type d -name "*-$SHORT" 2>/dev/null | sort | tail -1)
  fi
  if [ -n "$_origin" ] && [ -d "$_origin" ]; then
    mkdir -p "$_spec_dir"
    cp -R "$_origin"/. "$_spec_dir"/
    # informar ao operador: "spec restaurada de $_origin para $_spec_dir
    # (origem sob _archived/ permanece intacta)"
  fi
fi
```

`_origin` permanece intacto (`cp`, nunca `mv` — a regra de imutabilidade
de `_archived/` de `review-features/SKILL.md` e respeitada ao pe da
letra). `docs/specs/$SHORT/` ja existente e nao-vazio ⇒ o bloco acima nem
entra (o disco vence — Edge Case "spec editada a mao").

Prossiga agora para o **item 8** do pre-flight acima (coleta de consumo,
sem mudanca).

#### 3' — init da execucao nova (herda `--atomic-commit`, FR-022)

Repita a secao "### 3. Init do state.json" abaixo tal como esta descrita,
com UMA diferenca: **pule o prompt interativo de atomic-commit** e derive
`_atomic` do round anterior:

```
_atomic="false"
if [ -n "$_label" ]; then
  _v=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR/rounds/$_label" \
    --field '.atomic_commit_enabled' 2>/dev/null) || _v=""
  [ "$_v" = "true" ] && _atomic="true"
fi

# Garantia de branch herdada (atomic-commit-ensure-branch FR-004): sem
# prompt neste caminho, a garantia roda best-effort — falha vira aviso e
# a execucao segue (guard-branch por onda permanece como defesa).
if [ "$_atomic" = "true" ]; then
  commit-mode.sh ensure-branch \
    --projeto-alvo-path "$_proj" --short-name "$SHORT" \
    || echo "ensure-branch falhou — commits por etapa serao pulados pelo guard-branch enquanto HEAD estiver na default" >&2
fi
```

Ausencia, leitura falha ou valor nao reconhecido ⇒ `_atomic="false"`
(default seguro, FR-022, literal). Nenhum `--force` e necessario nem
existe: a raiz do state-dir esta sem `state.json`/`state.db` apos a
rotacao (ou, no caso `_skip_rotate`, ja estava sem desde a rotacao
anterior), entao as guardas de "state.json ja existe" do `init` nao
disparam. O backend da execucao nova segue a config global corrente
(mecanismo ja existente de `init`), independente do backend do round
anterior — sem heranca, sem flag `--backend` (Decision 14, dec-022).

#### 3'' — ponteiro `.previous_round` + Decisao do parecer (FR-006, FR-008)

```
_prev_round_json=$(jq -n \
  --arg round "$_label" \
  --arg path "rounds/$_label" \
  --arg execution_id "$_prev_exec_id" \
  --arg status "$_prev_status" \
  --arg rotated_at "$_rotated_at" \
  '{round:$round, path:$path, execution_id:$execution_id, status:$status, rotated_at:$rotated_at}')

state-rw.sh set --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '.previous_round' --value "$_prev_round_json"

_diverged="false"
[ "$_operator_choice" != "$_recommendation" ] && _diverged="true"

state-decisions.sh register --state-dir "$AGENTE_00C_STATE_DIR" \
  --agente "feature-00c" --etapa "reopen" \
  --contexto "Reabertura de '$SHORT': recomendacao=$_recommendation; round anterior=$_label ($_prev_status); $_pending_note" \
  --opcoes '["reabrir","abrir-feature-nova"]' \
  --escolha "$_operator_choice" \
  --justificativa "diverged=$_diverged; $_rationale"
```

Objeto **inteiro** em `.previous_round` (path aninhado e rejeitado sob
backend SQLite — Decision 4 de `research.md`). `--score` omitido de
proposito: a decisao e humana, nunca pontuada por heuristica (registra
como `null`).

O lock so e liberado no Cleanup (item 6 da secao final abaixo) — nao
antes: cobre a rotacao **inteira**, do `acquire` (item 7) ate ali
(FR-012).

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

# Decisao de ramo: MCP estruturado vs prosa legada (FASE 5 — mcp-elicitation-optins,
# dec-080). Probe best-effort ANTES do prompt de opt-in — NUNCA bloqueia (FR-005/FR-012).
# Escopo de campos do formulario MCP (servidor-side, ja implementado em
# collect_optins.ts:APPLICABLE_FIELDS_BY_KIND, task 3.1.2): SOMENTE
# atomic_commit. roadmap_mode e o campo de finalidade de entrega sao
# exclusivos de agente-00c (feature-00c roda dentro de um projeto ja
# calibrado; contrato vigente, ver
# tests/test_command-spawn-roadmap-mode.sh scenario_ausente_em_feature_00c
# e dec-010). O ramo LEGADO deste command so tem prosa/flag para
# atomic_commit (feature-00c nunca ofereceu roadmap-mode por prosa) —
# nada muda aqui alem do que ja e omitido hoje.
mkdir -p "$AGENTE_00C_STATE_DIR" 2>/dev/null || :
# Provisionamento idempotente do .mcp.json do projeto-alvo (dec-107,
# FASE 12/mcp-elicitation-optins). Sem isto, o ramo estruturado so
# funcionava quando o projeto-alvo JA tinha cstk-state registrado (ex.:
# o proprio repo cstk) — em qualquer OUTRO projeto-alvo, `cstk mcp start`
# mintava um token normalmente (nao depende do .mcp.json), mas o HARNESS
# desta sessao NUNCA teria a tool collect_optins de fato disponivel (o
# .mcp.json e lido no BOOT da sessao, nao em tempo real) — a onda-001
# abria sem opt-ins coletados e o guard M4/I-2 travava mudo (dec-107,
# achado do E2E Scenario 1). Best-effort: falha nunca bloqueia a
# pipeline, so cai no ramo legado normalmente.
_optin_mcpjson_pre=""
if [ -f "$_proj/.mcp.json" ] && grep -q '"cstk-state"' "$_proj/.mcp.json" 2>/dev/null; then
  _optin_mcpjson_pre="1"
fi
cstk mcp install --project-path "$_proj" >/dev/null 2>&1 || :
_optin_branch="legado"
_optin_probe_rc=1
# So tenta o probe estruturado quando `.mcp.json` JA tinha cstk-state
# ANTES desta invocacao — se acabou de ser registrado agora (linha
# acima), esta sessao (harness ja bootada) nao tem a tool de qualquer
# forma; a proxima sessao neste projeto-alvo ja nasce com o ramo
# estruturado disponivel.
if [ -n "$_optin_mcpjson_pre" ] && cstk mcp status --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1; then
  cstk mcp start --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1; _optin_probe_rc=$? || :
fi
if [ "$_optin_probe_rc" -eq 0 ]; then
  _optin_token=$(jq -r '.session_id // ""' "$AGENTE_00C_STATE_DIR/mcp-server.json" 2>/dev/null) || _optin_token=""
  [ -n "$_optin_token" ] && _optin_branch="estruturado"
fi
# _optin_branch = "legado": siga o prompt de prosa abaixo exatamente como
#   hoje (byte-a-byte, FR-005) — nenhuma mencao ao MCP.
# _optin_branch = "estruturado": pule o prompt de prosa abaixo por
#   completo — _atomic permanece NAO-DEFINIDO; a flag --atomic-commit do
#   init (mais abaixo) e OMITIDA; a captura acontece via collect_optins
#   dentro do turno do orquestrador (ver "Injecao do token de capacidade"
#   mais abaixo). Chamar `cstk mcp start` de novo apos o init e seguro e
#   idempotente — reusa o session_id ja cunhado aqui, so refresca
#   target_project_path no descritor (mcp.sh:_mcp_cmd_start sempre
#   re-grava mesmo em reuse).

# Prompt opt-in de commit atomico (FR-001/FR-002 — atomic-commit-pr)
# Aplica-se APENAS quando _optin_branch = "legado" (ver decisao de ramo acima).
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
# Se HEAD estiver na branch default, habilitar cria/troca para a branch
# feature/<short-name> agora (senao TODO commit seria pulado pelo
# guard-branch, FR-005 — o modo nunca operaria).
#
# Habilitar o modo atomic-commit? [s/N]
# ---
# - Respostas afirmativas (s/S/y/Y/sim/yes): _atomic=true
# - Qualquer outra resposta (inclusive Enter): _atomic=false (default seguro)
# - Nao-interativo: _atomic=false sem perguntar e sem aguardar — nunca
#   travar esperando resposta. "Qualquer outra resposta" pressupoe que
#   houve UMA resposta; sem operador nao ha resposta alguma, e o default
#   seguro vale igual.
# Os commands de resume NAO re-promptam: /feature-00c-resume le
# .atomic_commit_enabled diretamente do state.json sem interacao.

# Garantia de branch (atomic-commit-ensure-branch FR-004): com
# _atomic=true, garantir HEAD fora da default ANTES do init — e o unico
# momento com humano presente para consentir/corrigir. Idempotente
# (stdout: created|switched|noop <branch>).
if [ "$_atomic" = "true" ]; then
  if ! commit-mode.sh ensure-branch \
       --projeto-alvo-path "$_proj" --short-name "$SHORT"; then
    # Falha (git ausente / checkout conflitante): mostre a saida do git ao
    # operador com a remediacao (resolver a working tree, ou isolamento
    # total via `cstk session start $SHORT`) e PERGUNTE: corrigir e tentar
    # de novo, ou prosseguir SEM atomic-commit? Prosseguir => _atomic=false
    # (o guard-branch por onda permanece como defesa em profundidade).
    :
  fi
fi

# Ramo "legado": --atomic-commit "$_atomic" (capturado pelo prompt de prosa).
# Ramo "estruturado": a flag e OMITIDA — init grava o default seguro
# `false` (FR-012 etapa 1); captura real via collect_optins depois.
_atomic_flag=""
[ "$_optin_branch" = "legado" ] && _atomic_flag="--atomic-commit $_atomic"

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
  $_atomic_flag
```

**Pre-requisito duro (dec-031)**: e exatamente este `.execution.status =
em_andamento`, gravado pelo `init` acima, que habilita as chamadas de tool
no ramo estruturado — sem ele, toda chamada retorna `SESSION_MISMATCH`
(`mcp-session.sh:25-32`).

### 3.ter Persistir opt-in do ramo legado em `.optin_responses[]` (FASE 12/dec-107)

Aplica-se **apenas** quando `_optin_branch = "legado"` (decisao de ramo
acima). Fecha a Invariante I-2 (guard M4, `_so_check_optin_invariant`)
tambem para o ramo legado: sem este passo, a prosa "desde o inicio"
(mecanismo indisponivel) nunca gravava nada em `.optin_responses[]` — so
a degradacao MID-CALL (4.bis) persistia. Onda-001 ficava presa no guard
mesmo com a prosa ja tendo rodado e o `state.json` ja tendo o valor
aplicado via `--atomic-commit` do `init`. Mesmo padrao de append de
4.bis (`channel: "prose"`), rodando logo apos o `state-rw.sh init`
acima. Escopo `feature-00c` (dec-083): SOMENTE `atomic_commit` — nenhum
outro campo de opt-in (os demais campos de `agente-00c` sao exclusivos
dele, ver `scenario_ausente_em_feature_00c_commands`).

```bash
if [ "$_optin_branch" = "legado" ]; then
  _now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _cur=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" --field '.optin_responses // []')
  [ "$_atomic" = "true" ] && _out="accepted" || _out="declined"
  _cur=$(printf '%s' "$_cur" | jq -c \
    --arg v "$_atomic" --arg o "$_out" --arg ts "$_now" \
    '. + [{field: "atomic_commit", channel: "prose", outcome: $o, applied_value: $v, recorded_at: $ts, reason: null}]')
  state-rw.sh set --state-dir "$AGENTE_00C_STATE_DIR" --field '.optin_responses' --value "$_cur"
fi
```

Ramo `_optin_branch = "estruturado"`: pule este passo por completo — a
persistencia acontece via `collect_optins` no primeiro ato do
orquestrador (ou via 4.bis se degradar no meio da chamada).

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
  # inicializada; cli/lib/mcp.sh::_mcp_print_status_from_descriptor).
  # CORRECAO (dec-034): `start` grava SEMPRE `mode=direct` — nao ha
  # caminho de codigo que produza `mode=bash-fallback` (mcp.sh:100-107,
  # :708-709 VERIFICADO; o valor e reservado pelo contrato, nunca emitido
  # de fato). O discriminador real de indisponibilidade e token vazio /
  # descritor ausente (`_mcp_token`, mais abaixo), nunca o literal
  # `mode=bash-fallback`.
  cstk mcp start --state-dir "$AGENTE_00C_STATE_DIR" >/dev/null 2>&1 || :
else
  : # subcomando `mcp` ausente (instalacao sem self-update recente) ou
    # `--state-dir` invalido — pula silenciosamente; pipeline segue no
    # caminho Bash de hoje (zero regressao)
fi
```

> **Injecao do token de capacidade (dec-043 / SEC-H3, generalizada FR-013)**
> — consumacao da coordenacao cross-feature da task 1.2. Apos o `start`,
> leia o descritor e injete o token no CONTEXTO do spawn do orquestrador
> SEMPRE que o descritor existir e `session_id` for nao-vazio,
> **independentemente do valor de `mode`** (contracts/cli-mcp-lifecycle.md
> §7, P-1/P-2 — a condicao antiga restrita a `mode == "docker"` foi
> removida: apos o cutover desta feature nenhuma sessao nova grava
> `mode=docker`):
>
> ```bash
> _mcp_token=$(jq -r '.session_id // ""' "$AGENTE_00C_STATE_DIR/mcp-server.json" 2>/dev/null) || _mcp_token=""
> ```
>
> - `_mcp_token` NAO-vazio ⇒ inclua no prompt do orquestrador a linha:
>   `MCP: servidor de estado ativo; session_id=<token>. Prefira as tools
>   mcp__cstk-state__* (open_wave, record_decision, record_skill,
>   record_task, register_human_block, close_wave, get_status)
>   apresentando ESTE session_id em cada chamada; em erro de transporte,
>   contrato de queda mid-onda (0 retries + 1 confirmacao via cstk mcp
>   status --live) e comutacao para Bash no resto da onda.`
> - **Ramo `_optin_branch = "estruturado"` (decisao de ramo acima, task
>   5.3.1/5.5.1 — mcp-elicitation-optins)**: acrescente TAMBEM, na mesma
>   injecao, a linha: `MCP: ramo estruturado de opt-ins ativo (dec-080).
>   Chame mcp__cstk-state__collect_optins como o PRIMEIRO ato desta
>   execucao, ANTES de qualquer state-ondas.sh start/open_wave da
>   onda-001 (FR-012, Invariante O-1 — nenhuma onda pode abrir com campo
>   aplicavel sem registro em .optin_responses[]).`
> - `_mcp_token` vazio (`bash-fallback` / sem descritor) ⇒ NAO mencione MCP
>   no prompt; o orquestrador segue o caminho Bash (zero regressao, SC-004).
>   Neste caso `_optin_branch` ja e `"legado"` por construcao (mesmo
>   `_mcp_token` testado na decisao de ramo acima) — o opt-in ja foi
>   capturado por prosa ANTES do init; nada pendente para o orquestrador.
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

### 4.bis Degradacao mid-call do MCP: fallback por prosa + re-spawn (FASE 6.2, `mcp-elicitation-optins`)

Aplica-se SOMENTE quando `_optin_branch = "estruturado"` (secao 3 acima) E
esta e a primeira invocacao (`tipo_invocacao=primeira_invocacao` no spawn
acima) — retomadas nunca chamam `collect_optins` de novo (3.bis do
orquestrador, cap M6/dec-057). Escopo de campos de `feature-00c`: SOMENTE
`atomic_commit` (os demais campos do formulario MCP de `agente-00c` nao se
aplicam aqui — dec-083; mesmo confinamento ja vigente na secao 3 acima).

Apos o retorno do spawn acima, ANTES da rede de seguranca da secao 5,
verifique se o orquestrador devolveu o turno sem abrir NENHUMA onda por
degradacao mid-call do mecanismo estruturado
(`contracts/optin-capture-order.md` §3.3(b)). **Sinal estrutural, nunca o
sumario de texto do subagente** (mesma disciplina de "fonte de verdade e
o state"):

```bash
_last=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" \
  --field '[.optin_responses[]? | select(.field == "atomic_commit")] | last // {}')
_last_ch=$(printf '%s' "$_last" | jq -r '.channel // ""')
_last_out=$(printf '%s' "$_last" | jq -r '.outcome // ""')
_optin_degraded="false"
case "$_last_ch:$_last_out" in
  structured:unavailable|structured:failed) _optin_degraded="true" ;;
esac
```

Se `_optin_degraded = "false"`: nada a fazer — prossiga normalmente a
`5.` (caminho comum: captura funcionou ou o ramo ja era legado).

Se `_optin_degraded = "true"` (R-2: registro **nao-terminal**), rode
EXATAMENTE o mesmo bloco de prosa da secao 3 acima ("Prompt opt-in de
commit atomico"): mesmo texto, mesmo default, zero mencao ao MCP (o
operador nao percebe que o mecanismo estruturado chegou a existir).

1. Persista via `commit-mode.sh set-enabled --state-dir
   "$AGENTE_00C_STATE_DIR" --value <true|false>` (**nunca** por flag de
   init — o `state.json` ja existe).
2. Acrescente o registro em `.optin_responses[]` com `channel: "prose"`
   (append-only; NUNCA sobrescreva o registro `structured` ja existente —
   R-1, vale o mais recente):
   ```bash
   _now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
   _cur=$(state-rw.sh get --state-dir "$AGENTE_00C_STATE_DIR" --field '.optin_responses // []')
   _new=$(printf '%s' "$_cur" | jq -c --arg v "$_atomic" --arg ts "$_now" \
     '. + [{field: "atomic_commit", channel: "prose", outcome: "accepted", applied_value: $v, recorded_at: $ts, reason: null}]')
   state-rw.sh set --state-dir "$AGENTE_00C_STATE_DIR" --field '.optin_responses' --value "$_new"
   ```
   Sem operador para responder (execucao nao-interativa): grave
   `outcome: "absent"` em vez de `"accepted"` — mesmo default seguro do
   ramo legado, nunca `"declined"` (nao houve recusa explicita, so
   ausencia de quem decida).
3. **Anti-loop (R-3)**: este passo roda **no maximo uma vez** por campo
   por execucao — um registro mais recente com `channel: "prose"` encerra
   o campo qualquer que seja o `outcome`.

Depois de persistir, **re-spawne o orquestrador** (repita o bloco de
spawn acima, ainda com `tipo_invocacao=primeira_invocacao` — a onda-001
nao abriu, nao ha ponteiro para avancar). No re-spawn, `collect_optins`
(3.bis do orquestrador) detecta que `atomic_commit` ja tem registro
(agora terminal, `channel: "prose"`) e retorna `reused` sem re-disparar
`elicitation/create` (cap M6) — o operador NUNCA e perguntado duas vezes
pelo mesmo campo. So entao prossiga normalmente a `5.`.

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
(init sem Docker, token nunca cunhado — dec-034: o modo reservado para
fallback nunca e de fato escrito pelo `start`; discriminador real e
token vazio/descritor ausente) e seguro. Raro na primeira invocacao
(normalmente termina em `em_andamento` com Schedule intent),
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
| 0 | Sucesso, ou modo `--reopen` com operador escolhendo abortar apos o parecer (deliberado — nada foi escrito) |
| 1 | Erro geral / pre-flight falhou |
| 2 | Coexistencia bloqueada (agente-00c ativo) |
| 3 | Lock ocupado |
| 4 | `--reopen`: short-name sem execucao anterior — usar abertura normal (FR-002) |
| 5 | `--reopen`: execucao anterior nao-terminal — usar `/feature-00c-resume`/`/feature-00c-abort` (FR-003) |
| 6 | `--reopen`: rotacao pendente irrecuperavel automaticamente (`state-rounds.sh recover` saiu `1`) — FR-011 |

Exit codes `4`..`6` sao exclusivos do modo `--reopen`
(`docs/specs/feature-reopen/contracts/reopen-flow.md`).

## Anti-padroes

- **NAO criar artefatos antes do passo 7** (lock). SC-PRE-001 exige
  filesystem inalterado em caso de pre-flight falhar.
- **NAO chamar ScheduleWakeup** se status terminal (bloqueio/aborto/
  concluido) — schedule e exclusivo para status `em_andamento`.
- **NAO bypassar** o check de coexistencia (FR-026) — execucao
  concorrente com agente-00c quebra namespace isolation.
- **`--reopen`: NAO escrever nada em disco antes do passo 7** (lock) —
  os passos 6.a/6.b/6.c sao estritamente read-only; `state-rounds.sh
  rotate`/`recover` e `state-rw.sh init` so rodam depois do `acquire`
  (FR-002, FR-004, Decision 7).
- **`--reopen`: NAO oferecer uma opcao que termina em aborto do proprio
  fluxo que a ofereceu** (SC-007) — o bug fechado por FR-016 era
  exatamente isso: a opcao (a) do item 6 antigo levava a um `init` que
  morria.
- **`--reopen`: NAO decidir `reabrir` vs `abrir-feature-nova` por score
  automatico** — a comparacao e semantica (Decision 10), feita pelo
  LLM orquestrador; o operador sempre confirma, mesmo contra a
  recomendacao (FR-005).
- **`--reopen`: NAO mover nem renomear** o diretorio sob
  `docs/specs/_archived/` na restauracao de spec (7.d) — sempre `cp`,
  nunca `mv` (FR-013).
