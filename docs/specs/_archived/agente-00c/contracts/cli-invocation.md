# Contract: Invocacao CLI do Agente-00C

Comandos slash expostos pelo toolkit ao operador. Registrados em
`global/commands/`.

---

## /agente-00c

**Forma de invocacao** (slash command no Claude Code):

```
/agente-00c <descricao-curta-do-projeto-alvo> [--stack <stack-json>] [--whitelist <path>] [--projeto-alvo-path <path>]
```

**Argumentos**:

| Argumento | Tipo | Obrigatorio | Validacao |
|-----------|------|-------------|-----------|
| descricao-curta | texto livre | sim | min 10 chars; primeiro argumento posicional |
| --stack | JSON inline ou caminho .json | nao | objeto com chaves opcionais: linguagem, framework, banco, cache, filas |
| --whitelist | caminho relativo | nao | arquivo deve existir ou sera criado vazio |
| --projeto-alvo-path | caminho absoluto ou relativo | nao | default = `cwd`; se nao existir, sera criado como diretorio vazio |

**Pre-condicoes**:

- Operador esta em uma sessao Claude Code com Auto mode ativo (recomendado).
- O diretorio do projeto-alvo, se existente, nao tem execucao 00C em
  andamento (verificavel via existencia de
  `<projeto-alvo>/.claude/agente-00c-state/state.json` com status
  `em_andamento` ou `aguardando_humano`).

**Comportamento esperado**:

1. Le argumentos. Se descricao curta vazia ou < 10 chars, falha com mensagem
   pedindo descricao mais completa.
2. Cria/garante diretorio `<projeto-alvo>/.claude/agente-00c-state/`.
3. Le `<projeto-alvo>/.env` se existir, extrai URLs como base da whitelist
   inicial.
4. Se `--whitelist` passado, le e mescla com URLs do `.env`.
5. Inicializa `state.json` com `status: em_andamento`, `etapa_corrente:
   briefing`, `proxima_instrucao` apontando para inicio do briefing.
6. Spawna o agente custom `agente-00c-orchestrator` passando como contexto:
   - Caminho do estado.
   - Caminho dos artefatos esperados (briefing, constitution, etc).
   - Caminho da whitelist.
7. Aguarda retorno do orquestrador (uma mensagem) com sumario da onda.
8. Apresenta ao operador: id da execucao, etapa onde parou, motivo do termino
   da onda, link para relatorio parcial (sempre existe ao final de onda).

**Saida esperada na sessao do operador**:

```
Agente-00C iniciado.
Execucao: exec-2026-05-05T14-23-00Z-agente-00c-poc-foo
Projeto-alvo: /Users/jot/Projects/_lab/poc-foo
Stack: nao especificada (clarify-answerer escolhera)
Onda 001: briefing iniciado, 12 perguntas geradas, 8 respondidas autonomamente, 4 viraram bloqueio humano.
Status apos onda: aguardando_humano
Proxima onda agendada: 2026-05-05T14:35:00Z (5min)
Relatorio parcial: /Users/jot/Projects/_lab/poc-foo/.claude/agente-00c-report.md
```

**Erros**:

| Condicao | Mensagem | Acao |
|----------|----------|------|
| Descricao < 10 chars | "Descricao do projeto-alvo muito curta. Informe pelo menos 10 caracteres." | Aborta |
| Execucao em andamento detectada | "Ja existe execucao em status <status> em <path>. Use /agente-00c-resume para retomar ou /agente-00c-abort para abortar antes." | Aborta |
| `--stack` invalido (nao parseavel como JSON) | "Argumento --stack precisa ser JSON valido ou caminho para arquivo .json." | Aborta |
| `--projeto-alvo-path` aponta para arquivo (nao diretorio) | "Caminho aponta para arquivo, nao diretorio." | Aborta |
| `--projeto-alvo-path` fora de zona segura (ex: `/`, `/etc`, `~/.claude`) | "Caminho do projeto-alvo viola Principio V (Blast Radius). Escolha um diretorio dedicado." | Aborta |

---

## /agente-00c-abort

**Forma de invocacao**:

```
/agente-00c-abort [--projeto-alvo-path <path>]
```

**Argumentos**:

| Argumento | Tipo | Obrigatorio | Validacao |
|-----------|------|-------------|-----------|
| --projeto-alvo-path | caminho | nao | default = cwd |

**Pre-condicoes**:

- Existe `<projeto-alvo>/.claude/agente-00c-state/state.json` com status
  `em_andamento` ou `aguardando_humano`.

**Comportamento esperado**:

1. Le estado corrente.
2. Se status ja e terminal (abortada/concluida), retorna mensagem informativa
   sem alterar nada.
3. Atualiza `status` para `abortada` e `motivo_termino` para `aborto_manual`.
4. Atualiza `terminada_em` com timestamp atual.
5. Gera relatorio final em
   `<projeto-alvo>/.claude/agente-00c-report.md` (sobrescreve relatorio
   parcial existente).
6. Faz commit local no projeto-alvo com mensagem `chore(agente-00c): aborto
   manual da execucao <id>`.
7. Apresenta ao operador: confirmacao + link para relatorio.

**Saida esperada**:

```
Execucao exec-2026-05-05T14-23-00Z-agente-00c-poc-foo abortada manualmente.
Status final: abortada
Relatorio final: /Users/jot/Projects/_lab/poc-foo/.claude/agente-00c-report.md
Commit local: a3f2b1c
```

**Erros**:

| Condicao | Mensagem | Acao |
|----------|----------|------|
| Estado nao encontrado | "Nao ha execucao 00C em <path>." | Aborta |
| Estado corrompido (schema invalido) | "Estado em <path> tem schema invalido — recomendado intervencao manual." | Aborta |

---

## /agente-00c-resume

**Forma de invocacao**:

```
/agente-00c-resume [--projeto-alvo-path <path>] [--resposta-bloqueio <id>:<resposta>]
```

**Argumentos**:

| Argumento | Tipo | Obrigatorio | Validacao |
|-----------|------|-------------|-----------|
| --projeto-alvo-path | caminho | nao | default = cwd |
| --resposta-bloqueio | string com formato `<block-id>:<resposta>` | nao | obrigatorio quando status = aguardando_humano e ha bloqueios pendentes |

**Pre-condicoes**:

- Existe estado com status `em_andamento` (continuacao normal pos-schedule)
  ou `aguardando_humano` (resposta a bloqueio).

**Comportamento esperado**:

1. Le estado.
2. Se status = aguardando_humano: aplica `--resposta-bloqueio` ao
   BloqueioHumano correspondente, marca como respondido, atualiza status para
   em_andamento.
3. Spawna agente-orquestrador passando contexto de retomada.
4. Comportamento dali em diante e identico ao /agente-00c (avanca a pipeline,
   gera onda, etc).

**Saida esperada**: similar a /agente-00c, indicando que e retomada.

**Erros**: similares a /agente-00c-abort (estado nao encontrado, corrompido).
