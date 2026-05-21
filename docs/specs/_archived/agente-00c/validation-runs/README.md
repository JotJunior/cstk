# Validation Runs do Agente-00C

Cada execucao real do agente-00C deve produzir um arquivo aqui no formato:

```
<YYYY-MM-DD>-<short-description>.md
```

Exemplos:
- `2026-05-06-end-to-end-shell-simulation.md` (validacao shell-level)
- `2026-05-15-poc-bot-slack.md` (primeira execucao real em projeto-alvo)
- `2026-06-01-cli-utility-cron.md` (segunda execucao em outro projeto-alvo)

## Template

```markdown
# Validation Run: <YYYY-MM-DD> — <projeto-alvo>

**Tipo**: [shell-simulation | end-to-end-real]
**Versao do toolkit**: <vX.Y.Z>
**Operador**: <nome>
**Sessao Claude Code**: <model + duration>

## Setup

- Projeto-alvo: `<caminho>`
- Stack-sugerida: `<JSON ou "omitida">`
- Whitelist inicial: `<contagem de URLs>`

## Cenarios executados

| Scenario | Resultado | Observacoes |
|----------|-----------|-------------|
| 1 - Happy path | PASS / FAIL / N/A | ... |
| 2 - Pause por bloqueio humano | ... | ... |
| ...

## Metricas coletadas

| Metrica | Valor | SC referenciado |
|---------|-------|-----------------|
| Ondas total | N | - |
| Tool calls total | N | - |
| Decisoes registradas | N | - |
| Bloqueios humanos | N | - |
| Sugestoes para skills globais | N | - |
| Issues abertas no toolkit | N | - |
| Profundidade max subagentes | N | FR-013 |
| Tempo total wallclock (h) | N | - |
| Tempo geracao relatorio (s) | N | SC-005 |

## Success Criteria (SC-001 a SC-010)

| SC | Atendido? | Evidencia |
|----|-----------|-----------|
| SC-001 — Relatorio com 6 secoes obrigatorias | yes/no | `report.sh validate` exit code |
| SC-002 — ... | ... | ... |

## Observacoes qualitativas

- O que funcionou bem
- O que nao funcionou
- Surpresas

## Anexos

- Relatorio final: `<projeto-alvo>/.claude/agente-00c-report.md`
- Estado: `<projeto-alvo>/.claude/agente-00c-state/state.json`
- Backups: `<projeto-alvo>/.claude/agente-00c-state/state-history/`
```

## Tipos de validation run

### shell-simulation

Executa os scripts da skill `agente-00c-runtime` via Bash diretamente,
SEM invocar o agente Claude Code. Valida que as primitivas se compoem
corretamente (state-rw + state-decisions + bloqueios + report + etc).
NAO valida o comportamento do LLM (heuristica de score, qualidade
das perguntas do clarify, etc).

Util para regressao: detectar quando um script quebra a integracao com
outros sem precisar de sessao Claude Code real.

### end-to-end-real

Sessao Claude Code completa invocando `/agente-00c` em projeto-alvo
real. Mede tudo: comportamento do LLM, qualidade do registro de
decisoes, formato do relatorio final, tempo wallclock.

E o que conta para SC-001 a SC-010 e para SC-006 (leitor reproduz
mentalmente decisoes via relatorio).
