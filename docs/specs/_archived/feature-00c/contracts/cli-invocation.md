# Contract: Slash Commands `/feature-00c*`

Define a interface dos 3 slash commands que compoem a feature, suas
sintaxes, parametros, validacoes pre-execucao e codigos de saida.

---

## `/feature-00c` — Invocacao inicial

**Sintaxe**:

```
/feature-00c "<descricao_curta>" [<short-name>] [--projeto <path>] \
  [--whitelist <url1,url2,...>]
```

**Parametros**:

| Param | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `descricao_curta` | string em quotes | sim | <= 500 chars (FR-029, herdado de 00c FR-025) |
| `short_name` | kebab-case | nao | derivado por `specify` se omitido (FR-001) |
| `--projeto` | path | nao | default = cwd |
| `--whitelist` | csv URLs | nao | adicional ao `.env` (FR-002) |

**Validacoes pre-execucao** (ordem):

1. **Path do projeto-alvo**: resolve realpath; rejeita zonas proibidas
   (FR-029, herdado 00c FR-024).
2. **Descricao curta**: sanitiza contra injecao Bash/git/issue; trunca
   se >500 chars + warning.
3. **Briefing**: valida existencia + secoes minimas + ausencia de
   placeholders (FR-PRE-001 + FR-PRE-003).
4. **Constitution**: valida existencia + versao >= 1.0.0 + principios
   ratificados (FR-PRE-002 + FR-PRE-003).
5. **Coexistencia com agente-00c**: rejeita se `agente-00c-state/state.json`
   indica `em_andamento` ou `aguardando_humano` (FR-026).
6. **Feature pre-existente**: se `docs/specs/<short_name>/spec.md` ja
   existe e nao-vazio, dispara bloqueio humano com opcoes (FR-006).
7. **Lock de feature**: tenta criar
   `feature-00c-state/<short_name>/.lock`; se ja existe e processo vivo,
   rejeita (FR-028).

**Saida**:

- **Sucesso**: cria `state.json` + delega ao agente-00c-feature-orchestrator;
  exit 0.
- **Falha pre-flight**: stderr com diagnostico + sugestao acionavel
  (path do command a invocar); exit 1; NENHUM arquivo criado em
  `<projeto-alvo>/.claude/feature-00c-state/` (SC-PRE-001).
- **Coexistencia bloqueada**: stderr com diagnostico + comandos para
  resolver; exit 2.
- **Feature pre-existente (decisao operador)**: bloqueio humano in-band;
  aguarda resposta (NAO retorna).

---

## `/feature-00c-resume <short_name>` — Retomada

**Sintaxe**:

```
/feature-00c-resume <short_name> [--resposta-bloqueio "<resposta>"]
```

**Parametros**:

| Param | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `short_name` | kebab-case | sim | identifica qual feature retomar |
| `--resposta-bloqueio` | string | condicional | obrigatorio se status = `aguardando_humano` |

**Fluxo** (Decision 5 do research):

```
1. ler <projeto-alvo>/.claude/feature-00c-state/<short_name>/state.json
2. checar lock (.lock) — se ocupado, exit 3 com diagnostico
3. adquirir lock
4. validar hash state.json contra .sha256 — se diverge, bloqueio humano
5. validar hash briefing.sha256 + constitution.sha256 — se diverge,
   bloqueio humano (MAJOR = compulsorio; MINOR = aviso + pergunta)
6. se status == aguardando_humano e nao ha --resposta-bloqueio,
   rejeita com diagnostico apontando os bloqueios pendentes
7. se --resposta-bloqueio: integra resposta no state, marca blq como
   respondido, gera Decisao resultante
8. delega ao agente-00c-feature-orchestrator com state carregado
9. orquestrador continua de proxima_instrucao
```

**Saida**:

- **Sucesso retomada**: agente reinicia execucao; exit 0 (a sessao fica
  no Claude Code para a proxima onda).
- **Lock ocupado**: exit 3 + diagnostico ("outra sessao ativa para esta
  feature").
- **Hash divergente**: gera relatorio parcial atualizado, persiste
  bloqueio, exit 4.
- **Bloqueio pendente sem --resposta-bloqueio**: exit 5 + lista de
  perguntas.
- **state.json inexistente ou corrompido**: exit 6 + sugestao de invocar
  `/feature-00c` novamente.

---

## `/feature-00c-abort <short_name>` — Aborto manual

**Sintaxe**:

```
/feature-00c-abort <short_name> [--purge-backups] [--motivo "<texto>"]
```

**Parametros**:

| Param | Tipo | Obrigatorio | Notas |
|-------|------|-------------|-------|
| `short_name` | kebab-case | sim | qual feature abortar |
| `--purge-backups` | flag | nao | apaga `backups/` apos abort (default: preserva) |
| `--motivo` | string | nao | default: "aborto manual" |

**Fluxo** (FR-025, atualizado com SIGTERM + grace period):

```
1. ler state.json; se status terminal, apenas reporta (idempotente)
2. checar .lock — se existe, ler PID detentor
3. se PID existe e processo vivo:
   3a. enviar SIGTERM ao PID
   3b. aguardar grace period de ate 60s pela liberacao do lock
   3c. se lock liberado antes de 60s: prosseguir para passo 4
   3d. se timeout (60s): force-acquire do lock como fallback
4. marcar status=abortada + motivo_termino="<motivo>" + terminada_em=now
5. gerar relatorio parcial via report.sh (FR-019) — output filtrado por
   secrets-filter (FR-036)
6. commit local com mensagem "feature-00c abort: <short_name>"
7. se --purge-backups, apaga `backups/` e suggestions referentes
8. liberar lock
```

**Garantia adicional**: SC-005 (relatorio em <60s) e medido a partir da
liberacao do lock pelo grace period (passo 3c) OU do force-acquire
(passo 3d), nao da invocacao do abort. Logo, tempo total
operador→relatorio = grace period (max 60s) + tempo de geracao do
relatorio (<60s) = max 120s no pior caso.

**Saida**:

- **Sucesso**: exit 0 + path do relatorio parcial gerado.
- **Estado terminal**: exit 0 + mensagem "execucao ja em status terminal
  (X); nenhuma acao".
- **state.json inexistente**: exit 1 + diagnostico.
- **Falha na geracao do relatorio** (raro): exit 7 + estado preservado.

**Garantia**: SC-005 — relatorio parcial salvo em <60s desde invocacao
do abort. Mesma metrica do agente-00c.

---

## Codigos de saida consolidados

| Exit | Significado | Onde aplica |
|------|-------------|-------------|
| 0 | Sucesso | todos |
| 1 | Erro geral / pre-flight | `/feature-00c`, `/feature-00c-abort` |
| 2 | Coexistencia bloqueada | `/feature-00c` |
| 3 | Lock ocupado | `/feature-00c-resume` |
| 4 | Hash divergente (state/briefing/constitution) | `/feature-00c-resume` |
| 5 | Bloqueio pendente sem resposta | `/feature-00c-resume` |
| 6 | state.json inexistente / corrompido | `/feature-00c-resume` |
| 7 | Falha I/O critica | `/feature-00c-abort` |

---

## Interacao com ScheduleWakeup

Slash commands NAO invocam `ScheduleWakeup` diretamente. O orquestrador
retorna um intent JSON ao final da onda; o slash command corrente
(pai) le esse intent e chama `ScheduleWakeup` antes de finalizar a
turn (FR-032-INFRA-SCHED).

Formato do intent:

```json
{
  "schedule": true,
  "delaySeconds": 270,
  "cmd": "/feature-00c-resume user-auth",
  "reason": "wave threshold atingido apos 47 tool calls"
}
```

`delaySeconds` segue heuristica do agente-00c (60-3600s clamp do
harness Claude Code). `reason` aparece em telemetria do harness e no
relatorio (Linha do Tempo, motivo_fim da onda).
