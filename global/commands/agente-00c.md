---
description: 'Inicia execucao do orquestrador autonomo agente-00C sobre um projeto-alvo. Cria state em <projeto-alvo>/.claude/agente-00c-state/ e delega pipeline SDD ao agente-00c-orchestrator.'
argument-hint: "<descricao-curta> [--stack <stack-json>] [--whitelist <path>] [--projeto-alvo-path <path>]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
  - Glob
  - ScheduleWakeup
---

# /agente-00c

Voce vai iniciar uma nova execucao do orquestrador autonomo agente-00C
conforme contrato em `docs/specs/_archived/agente-00c/contracts/cli-invocation.md`.

> **Fronteira command↔orquestrador (lock + init)**: este command PAI detem
> o lock (acquire no passo 3, release SEMPRE no passo 5.ter) e inicializa o
> `state.json`. O orquestrador NAO adquire lock nem re-inicializa estado —
> contrato canonico em "Fronteira command↔orquestrador" de
> `agente-00c-orchestrator.md`. Identico no resume (`/agente-00c-resume`).

## Argumentos recebidos

```
$ARGUMENTS
```

## Comportamento esperado

### 0. Warm-up de permissoes (CRITICO — antes de qualquer outra coisa)

A pipeline 00C invoca dezenas de skills/tools ao longo de horas/ondas.
Permissoes pedidas "lazy" (no momento de cada invocacao) **quebram a
autonomia** se o operador nao estiver presente para responder o prompt
no instante exato — fluxo trava aguardando humano.

**Solucao**: invocar TODAS as skills/tools que serao usadas em batch
no inicio, ANTES do parse de args. Cada invocacao dispara o prompt de
permissao UMA vez aqui, com o operador ainda na sessao. Apos o
warm-up, o orquestrador roda autonomamente sem interrupcoes.

Apresente ao operador:

```
Agente-00C — Warm-up de permissoes

Vou agora invocar cada skill/tool que sera usada na pipeline para
disparar TODOS os prompts de permissao em batch. Voce sera questionado
sobre cada uma; aprove para autorizar a execucao autonoma posterior.

Apos esse batch, o agente roda sem mais interrupcoes — suas respostas
de permissao aqui valem para todas as ondas subsequentes.

Continuar? [s/N]
```

Se o operador confirmar, execute em sequencia (cada item dispara o
prompt nativo do Claude Code uma vez):

| # | Tool/Skill | Modo de warm-up |
|---|------------|-----------------|
| 1 | tool Skill — `briefing` | invocar com `--help` ou prompt minimo "responda apenas OK" |
| 2 | tool Skill — `constitution` | idem |
| 3 | tool Skill — `specify` | idem |
| 4 | tool Skill — `clarify` | idem |
| 5 | tool Skill — `plan` | idem |
| 6 | tool Skill — `checklist` | idem |
| 7 | tool Skill — `create-tasks` | idem |
| 8 | tool Skill — `execute-task` | idem |
| 9 | tool Skill — `review-task` | idem |
| 10 | tool Skill — `review-features` | idem |
| 11 | tool Agent — `agente-00c-orchestrator` | spawn com prompt `"warm-up: responda apenas READY"` + `subagent_type` correto |
| 12 | tool Agent — `agente-00c-clarify-asker` | idem |
| 13 | tool Agent — `agente-00c-clarify-answerer` | idem |
| 14 | tool ScheduleWakeup | invocacao com `delaySeconds: 60` + `prompt: "warm-up no-op"` + `reason: "agente-00C warm-up"` (depois cancele se possivel via re-schedule muito longo, ou aceite o no-op de 60s) |
| 15 | tool Bash — script `state-rw.sh` | `--help` (no-op) |
| 16 | tool Bash — script `bash-guard.sh check-blocklist --command "true"` | exit 0 sem efeito |
| 17 | tool Bash — `git --version` | dispara permissao para git |
| 18 | tool Bash — `gh --version` | dispara permissao para gh |
| 19 | tool Read — qualquer arquivo do projeto-alvo (ex: `<PAP>/.git/HEAD` se existir, senao `<PAP>` listing) | dispara permissao para Read |
| 20 | tool Write — `<PAP>/.claude/agente-00c-warmup-test` (depois delete) | dispara permissao para Write em `<PAP>` |

Apos o warm-up, registre a primeira Decisao via
`state-decisions.sh register --agente "orquestrador-00c" --etapa
"briefing" --contexto "Warm-up de permissoes concluido com 20
invocacoes batch" --opcoes '["proceder","abortar"]' --escolha
"proceder" --justificativa "Operador aprovou todas as permissoes em
batch; pipeline pode rodar autonomamente sem interrupcoes em ondas
subsequentes"`.

Se o operador NAO confirmar, aborte com mensagem:
```
Agente-00C nao iniciado. Sem warm-up, o fluxo autonomo travara em
prompts de permissao no meio das ondas. Re-execute /agente-00c quando
puder confirmar o warm-up no inicio.
```

### 1. Parse de argumentos

Extrair `descricao-curta` (primeiro posicional, minimo 10 chars),
`--stack`, `--whitelist`, `--projeto-alvo-path` (default = cwd).

#### Checklist pre-execucao (multi-workspace)

Se o `projeto-alvo` declara `package.json` com `workspaces: [...]`,
multiplos `go.mod` (`go.work`), ou Cargo workspace, **verifique se o
operador rodou `bash scripts/bootstrap-deps.sh`** (gerado pela skill
`briefing` na materializacao do pre-flight de bootstrap). Sem isso, a
pipeline encontrara N bloqueios humanos `npm install` em sequencia
(FR-018 nao permite instalacao autonoma).

Detectar:
```bash
test -f "$PAP/scripts/bootstrap-deps.sh" \
  && test -d "$PAP/node_modules" \
  || echo "AVISO: bootstrap-deps.sh ausente ou nao executado"
```

Se a heuristica detecta gap, antes de iniciar a pipeline pergunte:
```
Detectei stack multi-workspace mas nao encontrei sinal de bootstrap
executado. Voce rodou `bash scripts/bootstrap-deps.sh` (gerado pelo
briefing)?

  [s] Sim, prosseguir
  [n] Nao, vou rodar agora e re-invocar /agente-00c
```

Se `n`, abortar; se `s` ou o operador confirma overrride, prosseguir.
Pre-flight nao e bloqueante (operador pode legitimamente ter ambiente
ja preparado fora do script), apenas defensivo.

### 2. Validacao de pre-condicoes

- Descricao curta com >= 10 chars (caso contrario, falhar com mensagem
  pedindo descricao mais completa).
- `--projeto-alvo-path` deve resolver via `realpath`/`readlink -f` para
  fora das zonas proibidas (`/`, `/etc`, `/usr`, `/var`, `~/.claude`,
  `~/.ssh`, `~/.config`, `~/.aws`, `~/.docker`) — FR-024.
  Use `path-guard.sh validate-target --projeto-alvo-path <PAP>`.
- `descricao-curta` <= 500 chars; sanitizar antes de qualquer uso em
  commit message, issue ou path — FR-025.
  Use `sanitize.sh check-length --max 500`.
- Verificar inexistencia de execucao em andamento (`state.json` com status
  `em_andamento` ou `aguardando_humano`) — se existir, instruir uso de
  `/agente-00c-resume` ou `/agente-00c-abort`. Use
  `state-lock.sh check-execution-busy --state-dir <SD>`.

### 2.bis Hooks 00c provisionados no projeto-alvo? (ADVISORY, nunca bloqueia)

Os tres hooks do runtime (guarda de Bash + duas metricas) so chegam ao
projeto-alvo via `cstk install --scope project agente-00c-runtime` rodado
DENTRO dele. O default de `cstk install`/`update` e `--scope global`, que
pula o provisionamento — entao o caso comum e o projeto-alvo NAO ter hook
nenhum. Como o `cstk install` roda no repo do cstk e nao aqui, este e o
unico momento do fluxo que esta dentro do projeto-alvo: e aqui que o
operador precisa ser avisado.

```sh
guard-hooks-status.sh check --projeto-alvo-path "<PROJETO_ALVO_PATH>" || :
```

READ-ONLY: nunca copia hook nem edita `settings.json` (provisionar e
trabalho do `cstk install`, unica fonte da regra). Exit 1 NAO aborta a
execucao — mostre a saida ao operador e siga:

- `pretooluse-bash-guard.sh` inativo → **avise com destaque**: a guarda
  fail-closed de Bash NAO esta enforced nesta execucao. E o item grave;
  o resto e metrica.
- `posttooluse-tool-call-tick.sh` inativo → o orquestrador vai tickar
  manualmente (ver passo 2 do orchestrator); `tool_calls` nao zera.
- `posttooluse-agent-usage.sh` inativo → `agent_usage`/tokens ficam null
  nas ondas; nao ha fallback manual, so o provisionamento resolve.

### 3. Aquisicao do lock + inicializacao de estado

Adquirir o lock ANTES de inicializar o estado (o orquestrador NAO adquire
lock — ver Fronteira). `acquire` cria o `state-dir` se ausente e e
nao-reentrante; liberacao e SEMPRE no passo 5.ter (mesmo em erro):

```bash
state-lock.sh acquire --state-dir <SD> || {
  echo "Lock ocupado em <SD>. Ja ha sessao 00C ativa? Use /agente-00c-resume ou /agente-00c-abort." >&2
  exit 3
}
```

- Criar `<projeto-alvo>/.claude/agente-00c-state/` se ausente.
- Ler `<projeto-alvo>/.env` se presente, extrair URLs como base da
  whitelist inicial.
- Mesclar com `--whitelist` (se passado).
- Validar whitelist via `whitelist-validate.sh check --whitelist-file <WL>`.
- Worktree detection (recall-worktree-identity — FR-001/FR-002/FR-008).
  Toda falha = fallback silencioso; flags omitidas ao init (US3 AC3).
  Deteccao: .git ARQUIVO (worktree) vs .git DIRETORIO (projeto raiz — omitir flags; CHK011).

  ```sh
  # Worktree detection (recall-worktree-identity — FR-001/FR-002/FR-008)
  _canonical="" ; _session=""
  if [ -f "$PAP/.git" ]; then
    # Passo a: obter common-dir (git plumbing, read-only)
    _common=$(git -C "$PAP" rev-parse --git-common-dir 2>/dev/null) || _common=""
    if [ -n "$_common" ]; then
      # Passo b: normalizar para absoluto (git antigo pode retornar path relativo)
      case "$_common" in
        /*) : ;;  # ja absoluto
        *)  _common="$PAP/$_common" ;;
      esac
      # Passo c: canonical = basename do parent do common-dir
      _canonical=$(basename "$(dirname "$_common")")
      # Passo d: session = sufixo apos "<canonical>-" no basename do PAP
      _wtbase=$(basename "$PAP")
      case "$_wtbase" in
        "${_canonical}-"*) _session="${_wtbase#"${_canonical}-"}" ;;
        *)                 _session="" ;;
      esac
    fi
  fi
  # .git diretorio (projeto raiz): _canonical e _session permanecem vazios (flags omitidas).
  ```

#### Prompt opt-in de commit atomico (FR-001/FR-002 — atomic-commit-pr)

Antes de inicializar o `state.json`, pergunte ao operador se deseja
habilitar o modo de commit atomico (opt-in, default "nao"):

```
Modo atomic-commit (opcional):
Quando habilitado, a pipeline cria um commit git a cada etapa concluida
(specify, plan, checklist, create-tasks) e um commit agrupado ao final
de cada onda de execute-task. Ao final da pipeline, faz push+PR
automaticamente se houver branch nao-default.

Habilitar o modo atomic-commit? [s/N]
```

- Respostas afirmativas (`s`, `S`, `y`, `Y`, `sim`, `yes`): `_atomic=true`
- Qualquer outra resposta (inclusive Enter): `_atomic=false` (default seguro)

> **Os commands de resume NAO re-promptam**: `/agente-00c-resume` le
> `.atomic_commit_enabled` diretamente do `state.json` sem interacao.

- Inicializar `state.json` v1.0.0 via `state-rw.sh init`:
  - `--execucao-id "exec-$(date -u +%FT%H-%M-%SZ)-agente-00c-<slug>"`
  - `--projeto-alvo-path <PAP>` (resolvido)
  - `--descricao "<sanitized>"`
  - `--stack-json <stack ou "null">`
  - `--whitelist-urls <JSON-arr>`
  - `${_canonical:+--canonical-project "$_canonical"}` (quando nao-vazio)
  - `${_session:+--session-name "$_session"}` (quando nao-vazio)
  - `--atomic-commit "$_atomic"` (valor capturado acima; `false` = comportamento atual intacto)

  Status inicial: `em_andamento`, etapa `briefing`, `next_instruction`
  apontando para inicio do briefing.

### 4. Selecao de modelo da onda + delegacao ao orquestrador

Migrate defensivo (best-effort): canonicaliza um `state.json` pt-BR legado
para EN no lugar ANTES de qualquer direct-writer (orquestrador, `wave-select`)
tocar o arquivo. Idempotente/no-op em states ja EN; degrada graciosamente:

```bash
state-rw.sh migrate --state-dir <SD>
```

Antes de spawnar, compute o modelo a aplicar nesta onda via `wave-select`
(mapa fase→modelo + refino model-selector + override do operador — FR-002,
FR-009). A selecao e idempotente por onda (re-entrada nao duplica Decisao):

```bash
MODEL=$(model-routing.sh wave-select --state-dir <SD>)
```

`wave-select` SEMPRE emite uma linha em stdout: `haiku` | `sonnet` |
`opus` | `manter-atual` (nunca aborta — fallback gracioso para
`manter-atual`). A escolha ja foi registrada como `DecisaoDeRoteamentoPorOnda`
auditavel dentro do proprio `wave-select`.

Spawnar agente custom `agente-00c-orchestrator` via tool Agent, passando
no prompt:
- `state-dir`: caminho do `.claude/agente-00c-state/`
- `projeto-alvo-path`: PAP resolvido
- `feature-dir`: `<PAP>/docs/specs/<feature>/`
- `whitelist`: path do whitelist file
- `tipo_invocacao`: "primeira_invocacao"

Aplique o param `model` no spawn SOMENTE quando `MODEL != manter-atual`
(FR-006, quickstart C8 — `manter-atual` herda o modelo da sessao):
- Se `MODEL = manter-atual`: spawnar via tool Agent SEM o param `model`.
- Senao (`MODEL ∈ {haiku, sonnet, opus}`): spawnar com `model=<MODEL>`.

> Bidirecionalidade (FR-009): `wave-select` pode subir (sonnet→opus em
> fases profundas) ou descer (opus→haiku em fases rasas) o modelo entre
> ondas. O prompt do orquestrador NAO muda — so o involucro do spawn
> ganha o param `model`.

Aguarde retorno do orquestrador (uma mensagem de sumario contendo, entre
outras linhas, um campo `Schedule intent: ...`).

### 5.pre Rede de seguranca de fechamento de onda (OBRIGATORIO — antes do schedule)

> **Bug recorrente**: o orquestrador frequentemente RETORNA sem fechar a
> onda nem emitir `Schedule intent` (ver "Contrato de conclusao de turno"
> no `agente-00c-orchestrator.md`). Reforco de prompt nao resolve; o PAI
> trata o fechamento como rede de seguranca OBRIGATORIA a CADA retorno,
> nao condicional a `Schedule intent`.

Chame `reconcile-wave` SEMPRE, antes de processar o Schedule intent. E
idempotente: no-op se o orquestrador JA fechou a onda (sem double-count
em `accumulated_metrics`); se a deixou aberta, fecha deterministicamente
(record-skill + end + avanca `current_stage`/`next_instruction`, ou
promove `.execution.status=concluida` na fase terminal). `--terminal-phase
review-features` (agente-00c termina em review-features). Best-effort.

```bash
# Se a fase corrente for execute-task, localize tasks.md e passe --tasks-md.
state-ondas.sh reconcile-wave --state-dir "$STATE_DIR" \
  --terminal-phase review-features \
  2>/dev/null || echo "reconcile-wave: rede de seguranca pulada" >&2
```

Apos reconciliar, derive o Schedule a partir do `.execution.status` real
quando o orquestrador NAO emitiu `Schedule intent` (parou cedo): terminal
(`concluida`/`abortada`/`aguardando_humano`) NAO agenda; `em_andamento`
agenda a proxima onda via `ScheduleWakeup` com `prompt: "/agente-00c-resume <projeto>"`.

### 5. Schedule da proxima onda (CRITICO — ver nota no orchestrator)

Sub-agentes nao podem invocar `ScheduleWakeup` de forma sobrevivente: o
thread deles termina ao retornar. O orquestrador, portanto, apenas
DECIDE os parametros e os retorna como `Schedule intent` no sumario.
Voce, slash command pai, e quem executa o wakeup.

Procure a linha `Schedule intent: ...` no sumario retornado e aplique:

| Forma da linha | Acao |
|----------------|------|
| `Schedule intent: delaySeconds=<N>; reason="<R>"; prompt="<P>"` | Invocar `ScheduleWakeup(delaySeconds=<N>, reason="<R>", prompt="<P>")` |
| `Schedule intent: none; motivo=<X>` | NAO invocar ScheduleWakeup. Anotar motivo para o sumario final. |
| linha ausente OU formato invalido | Anotar `Proxima onda agendada: nenhuma (Schedule intent ausente/invalido — ver report.md)`. NAO tentar adivinhar parametros. |

Se `ScheduleWakeup` falhar (excecao da tool), atualize o estado para
refletir a falha:

```bash
state-rw.sh set --state-dir <SD> \
  --field '.waves[-1].next_wave_scheduled_for' --value 'null'
```

E inclua no sumario final `Proxima onda agendada: nenhuma (ScheduleWakeup
falhou — operador retoma via /agente-00c-resume)`.

### 5.bis Ingestao da onda na knowledge.db (rede de seguranca, best-effort)

A ingestao canonica e o passo **10.bis** do loop do orquestrador
(`agente-00c-orchestrator.md`). Este eco no pai e uma REDE DE SEGURANCA
para o caso de o orquestrador retornar SEM completar o loop (onda fechada/
recuperada sem ter chegado ao 10.bis). Sem ele, a `knowledge.db` fica sem
o conhecimento da onda.

```bash
# <SD> = <projeto-alvo>/.claude/agente-00c-state. Idempotente (upsert por
# chave natural): re-ingerir apos o 10.bis e inofensivo. Read-only sobre o
# state.json; escreve so em ~/.claude/cstk/knowledge.db. NUNCA gateia —
# toda falha (cstk fora do PATH, sqlite3/jq ausentes) degrada para no-op.
cstk recall --ingest --state-dir <SD> 2>/dev/null \
  || echo "knowledge-db: ingestao (rede de seguranca) pulada — cstk/sqlite3/jq ausentes" >&2
```

### 5.ter Liberacao do lock (SEMPRE — inclusive em paths de erro)

O lock e do command pai (ver Fronteira). Libere-o apos o orquestrador
retornar — antes de apresentar o resultado. Em QUALQUER caminho de saida
(sucesso, aborto, ScheduleWakeup falho), o release deve rodar:

```bash
state-lock.sh release --state-dir <SD>
```

### 6. Apresentacao do resultado

Imprima o sumario final no formato:

```
Agente-00C iniciado.
Execucao: <exec-id>
Projeto-alvo: <PAP>
Stack: <stack ou "nao especificada — clarify-answerer escolhera">
Onda 001: <etapa> iniciado, <N> decisoes registradas, <N> bloqueios.
Status apos onda: <em_andamento | aguardando_humano | abortada | concluida>
Proxima onda agendada: <ISO planejado | "nenhuma — <motivo>">
Relatorio parcial: <PAP>/.claude/agente-00c-report.md
```

O campo "Proxima onda agendada" deriva do passo 5: ISO planejado quando
schedule foi disparado, ou string com motivo (`aguardando humano via
/agente-00c-resume`, `execucao abortada`, `execucao concluida`,
`ScheduleWakeup falhou — ...`) quando nao houve schedule.

## Estado atual

**Operacional pos-FASE 9** — todas as primitivas instaladas via
`cstk install` (skill `agente-00c-runtime` + agentes + commands). Em
caso de skill ausente, o orquestrador detecta via path missing e aborta
com mensagem orientando `cstk install`.
