---
description: 'Aborta manualmente a execucao corrente do agente-00C no projeto-alvo. Marca status como abortada, gera relatorio final, commit local. Idempotente.'
argument-hint: "[--projeto-alvo-path <path>]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
---

# /agente-00c-abort

Aborto manual de execucao 00C conforme contrato em
`docs/specs/_archived/agente-00c/contracts/cli-invocation.md`.

## Argumentos recebidos

```
$ARGUMENTS
```

## Comportamento esperado

Use os scripts em `~/.claude/skills/agente-00c-runtime/scripts/`. Aborto
e operacao terminal — depois dela a execucao nao pode mais ser retomada
(`/agente-00c-resume` em estado abortado retorna mensagem informativa).

### 1. Parse de argumentos

Extrair `--projeto-alvo-path` (default = `cwd`). Defina:
- `<PAP>` = projeto-alvo-path
- `<SD>` = `<PAP>/.claude/agente-00c-state`

### 2. Validar pre-condicoes

#### 2.a. Estado existe?

```bash
[ -f <SD>/state.json ] || die "Nao ha execucao 00C em <PAP>."
```

Se nao existe, retorne mensagem clara e termine (exit 0 — operador pode
ter chamado abort em projeto errado, nao e erro tecnico).

#### 2.b. Adquirir lock

```bash
state-lock.sh acquire --state-dir <SD>
```

Exit 3 = outra execucao em andamento. Aborte com mensagem orientando
aguardar conclusao da onda em andamento OU usar /agente-00c-abort apos a
onda corrente fechar.

#### 2.c. Validar schema

```bash
state-validate.sh --state-dir <SD>
```

Schema invalido = aviso especial (NAO bloqueia o abort — operador pode
querer abortar exatamente porque o estado esta corrompido). Continue
mesmo com warning, mas registre em stderr:

```
AVISO: schema do state.json invalido. Aborto procedera mesmo assim.
Operador deve inspecionar manualmente <SD>/state.json apos abort.
```

### 3. Verificar idempotencia

```bash
status=$(state-rw.sh get --state-dir <SD> --field '.execucao.status')
```

Se `status` ja e terminal (`abortada` ou `concluida`):

```
Execucao em status <status>. Nada a abortar.
Relatorio final: <PAP>/.claude/agente-00c-report.md (se existir)
```

Libere o lock e termine. NAO altere estado (idempotencia).

### 4. Atualizar estado para abortada

Em ordem:

```bash
now=$(date -u +%FT%TZ)

# Se ha onda em andamento (sem fim), feche-a primeiro com motivo aborto
if [ -n "$(state-rw.sh get --state-dir <SD> --field '.ondas[-1].fim // empty')" ]; then
  : # ultima onda ja fechada
else
  state-ondas.sh end --state-dir <SD> --motivo-termino aborto
fi

state-rw.sh set --state-dir <SD> --field '.execucao.status' --value '"abortada"'
state-rw.sh set --state-dir <SD> --field '.execucao.motivo_termino' --value '"aborto_manual"'
state-rw.sh set --state-dir <SD> --field '.execucao.terminada_em' --value "\"$now\""
```

Cada `set` ja faz backup automatico em `state-history/`.

### 5. Gerar relatorio final

**FASE 8 (relatorio operacional) ainda nao implementada.** Stub: gere um
relatorio parcial minimal em `<PAP>/.claude/agente-00c-report.md`
contendo apenas:

```markdown
# Relatorio de Execucao Agente-00C

**Status**: ABORTADA (manual)
**ID**: <execucao.id>
**Iniciada em**: <iniciada_em>
**Terminada em**: <terminada_em>

## Resumo

Execucao abortada manualmente via `/agente-00c-abort`. Para
inspecao detalhada do estado:

- State: `<SD>/state.json`
- History: `<SD>/state-history/`
- Decisoes registradas: <count via state-decisions.sh count>
- Bloqueios totais: <count via bloqueios.sh count>

Relatorio completo (6 secoes) sera gerado quando FASE 8 estiver
implementada.
```

Aplique filtro de secrets ANTES de gravar:
```bash
gerar_stub | secrets-filter.sh scrub --env-file <PAP>/.env > <PAP>/.claude/agente-00c-report.md
```

### 6. Commit local

```bash
state-ondas.sh git-commit --state-dir <SD> --projeto-alvo-path <PAP> \
  --motivo "aborto manual da execucao $(state-rw.sh get --state-dir <SD> --field '.execucao.id')"
```

NUNCA `git push` — Principio V (Blast Radius Confinado). Se `<PAP>` nao
e repo git, o commit falha silenciosamente (state-ondas.sh emit warning,
nao bloqueia o abort).

### 7. Liberar lock

```bash
state-lock.sh release --state-dir <SD>
```

### 8. Apresentar resultado ao operador

```
Execucao <id> abortada manualmente.
Status final: abortada
Relatorio final: <PAP>/.claude/agente-00c-report.md
Commit local: <hash> (ou "nao foi feito — projeto-alvo nao e repo git")
```

Capture o hash do commit via `git -C <PAP> rev-parse --short HEAD`.

## Idempotencia explicita

Chamar `/agente-00c-abort` 2x na mesma execucao e seguro:
- 1a chamada: status `em_andamento` → `abortada` + relatorio + commit
- 2a chamada: status ja `abortada` → mensagem informativa, NAO altera nada

Mesma garantia para chamadas durante onda ativa do orquestrador (lock
exclui concorrencia).

## Estado atual

**FASE 7.4 — operacional.** Relatorio final e stub minimal — FASE 8
expandira para 6 secoes auditaveis conforme
`docs/specs/_archived/agente-00c/contracts/report-format.md`.
