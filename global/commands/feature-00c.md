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
   _desc=$(printf '%s' "$DESC" | sanitize.sh)
   - se >500 chars, truncar + warning

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
     _status=$(jq -r '.execucao.status // "unknown"' "$_agstate" 2>/dev/null)
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

7. lock por short-name (FR-028):
   _lock="$AGENTE_00C_STATE_DIR/.lock"
   state-lock.sh acquire --state-dir "$AGENTE_00C_STATE_DIR"
   - se ocupado, stderr "outra sessao ativa para $SHORT"; exit 3
```

### 3. Init do state.json

```
mkdir -p "$AGENTE_00C_STATE_DIR/backups"
_br_sha=$(sha256sum "$_br" | awk '{print $1}')
_ct_sha=$(sha256sum "$_ct" | awk '{print $1}')
_ct_ver=$(grep -E '^\*\*Version\*\*:' "$_ct" | sed -E 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
_aspectos=$(drift.sh extract --texto "$_desc")  # 3-7 keywords

state-rw.sh init --state-dir "$AGENTE_00C_STATE_DIR" \
  --short-name "$SHORT" \
  --projeto-alvo-path "$_proj" \
  --descricao "$_desc" \
  --briefing-path "$_br" --briefing-sha256 "$_br_sha" \
  --constitution-path "$_ct" --constitution-sha256 "$_ct_sha" \
  --constitution-version "$_ct_ver" \
  --aspectos-chave "$_aspectos"
```

### 4. Selecionar modelo da onda + delegar ao orquestrador via Agent

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

### 5. Pos-orquestrador: capturar Schedule intent

O orquestrador retorna no sumario uma linha tipo:

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

Se `Schedule intent: none`, NAO invocar ScheduleWakeup. Apenas liberar
lock e exit 0.

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
