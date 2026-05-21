# Quickstart: Agente-00C

Cenarios de teste end-to-end que validam a feature completa. Cada cenario
deve ser executavel manualmente apos a implementacao, e cobre um fluxo
critico identificado nas user stories da spec.

---

## Scenario 1 — Happy path completo (US1 + US2 + US3)

**Pre-condicoes**:

- Toolkit `claude-ai-tips` instalado, comandos e agentes registrados.
- Diretorio de trabalho `/tmp/test-poc-foo` existe e esta vazio.
- Sessao Claude Code com Auto mode ativo.

**Passos**:

1. Operador invoca:
   ```
   /agente-00c "POC de bot que sumariza canais Slack" --projeto-alvo-path /tmp/test-poc-foo --stack '{"linguagem":"Go","framework":"chi","banco":"PostgreSQL"}'
   ```
2. Operador deixa rodar sem intervir. Espera ondas serem geradas e agendadas
   automaticamente (proxy-trigger ativa por wallclock ~90min ou tool-calls
   ~80).
3. Apos N ondas (entre 3 e 10, dependendo da pipeline), pipeline deve completar
   ate `review-features`.
4. Operador abre `/tmp/test-poc-foo/.claude/agente-00c-report.md`.

**Expected**:

- Arquivo de relatorio existe.
- Possui as 6 secoes obrigatorias preenchidas.
- Status final: `concluida`.
- Motivo termino: `concluida_com_sucesso`.
- Pelo menos 1 decisao de cada agente: orquestrador, clarify-asker,
  clarify-answerer, executor-task.
- Toda decisao do clarify-answerer tem `score_justificativa >= 1`.
- Numero de bloqueios humanos: 0 (path feliz).
- Pelo menos 1 entrada em "Licoes aprendidas".

---

## Scenario 2 — Pause por bloqueio humano (US1)

**Pre-condicoes**:

- Mesmo do Scenario 1.
- Stack-sugerida **omitida** (forca clarify-answerer a decidir stack).
- Briefing do projeto-alvo intencionalmente generico de modo que o
  clarify-answerer nao consiga atingir score >= 1 em pelo menos uma pergunta.

**Passos**:

1. Operador invoca `/agente-00c "ferramenta CLI generica" --projeto-alvo-path /tmp/test-pause-foo` (sem `--stack`).
2. Operador aguarda execucao chegar a etapa `clarify`.
3. Pipeline para automaticamente quando `clarify-answerer` retorna pelo
   menos uma resposta com `score_justificativa = 0`.
4. Operador abre o relatorio parcial e ve a pergunta na secao 4.1 Pendentes.
5. Operador responde:
   ```
   /agente-00c-resume --projeto-alvo-path /tmp/test-pause-foo --resposta-bloqueio "block-001:opcao-b"
   ```

**Expected**:

- Apos passo 3: status do estado = `aguardando_humano`. Onda corrente
  finalizada graciosamente.
- Relatorio parcial contem a pergunta com contexto suficiente para responder
  sem releitura de artefatos (SC-006).
- Apos passo 5: pipeline retoma da mesma etapa (`clarify`), aplica resposta
  como decisao auditavel, prossegue.
- Decisao registrada com agente=`humano` e justificativa contendo a resposta
  do operador.

---

## Scenario 3 — Aborto por loop em etapa (US4)

**Pre-condicoes**:

- Estado preparado de modo que a etapa corrente seja `execute-task` em uma
  task que sempre falha (bug intencional).

**Passos**:

1. Estado inicial:
   ```json
   {
     "etapa_corrente": "execute-task",
     "orcamentos.ciclos_consumidos_etapa_corrente": 5,
     ...
   }
   ```
2. Operador dispara onda manual: `/agente-00c-resume --projeto-alvo-path /tmp/test-loop-foo`.
3. Orquestrador detecta que iniciar nova iteracao seria 6o ciclo (acima do
   limite).

**Expected**:

- Aborto imediato sem iniciar 6a iteracao.
- Status final: `abortada`.
- Motivo termino: `loop_em_etapa`.
- Relatorio gerado em <60 segundos apos disparo de aborto (SC-005).
- Secao "Linha do tempo" do relatorio mostra clara a etapa onde travou.
- Secao "Decisoes" inclui a decisao de aborto com 5 campos preenchidos.

---

## Scenario 4 — Retomada apos /clear (US3)

**Pre-condicoes**:

- Execucao em andamento com 2 ondas ja registradas em `state.json`.
- Operador executa `/clear` no Claude Code (limpa contexto da sessao).

**Passos**:

1. Operador invoca novamente `/agente-00c-resume --projeto-alvo-path /tmp/test-resume-foo`.
2. Orquestrador le `state.json` e valida schema.
3. Orquestrador reconstroi contexto necessario lendo briefing.md, spec.md
   etc do disco — sem depender da memoria perdida.
4. Pipeline continua na etapa `etapa_corrente` registrada no estado.

**Expected**:

- Validacao de schema passa.
- Numero de decisoes preservado (nao recomeca do zero).
- Profundidade `profundidade_max_atingida` preservada.
- Onda 003 inicia exatamente apos onda 002, com `tool_calls` resetado para 0
  na onda corrente mas `tool_calls_total` agregado preservado.

---

## Scenario 5 — Aborto manual via /agente-00c-abort (US1 + FR-022)

**Pre-condicoes**:

- Execucao em andamento com status `em_andamento` e algumas decisoes
  registradas.

**Passos**:

1. Operador, em outra sessao Claude Code: `/agente-00c-abort --projeto-alvo-path /tmp/test-manual-abort-foo`.

**Expected**:

- Status final: `abortada`.
- Motivo termino: `aborto_manual`.
- Relatorio final gerado com todas as 6 secoes.
- Commit local feito no projeto-alvo: `chore(agente-00c): aborto manual da
  execucao <id>`.
- Sessao do operador recebe confirmacao com path do relatorio.
- Onda anterior (que pode ainda estar agendada) ao acordar detecta status
  `abortada` e nao executa.

---

## Scenario 6 — Bug em skill global vira issue (US5 + FR-021)

**Pre-condicoes**:

- Skill global instalada com bug intencional (ex: clarify retorna perguntas
  contraditorias).
- Repo `JotJunior/claude-ai-tips` acessivel via `gh` autenticado localmente.

**Passos**:

1. Operador invoca `/agente-00c "qualquer projeto" --projeto-alvo-path /tmp/test-skill-bug-foo`.
2. Pipeline avanca ate que o orquestrador detecta o bug impeditivo durante a
   etapa clarify (o orcamento de retro-execucao se esgota tentando resolver
   contradicao).

**Expected**:

- Sugestao registrada em
  `/tmp/test-skill-bug-foo/.claude/agente-00c-suggestions.md` com
  `severidade: impeditiva`.
- Issue aberta automaticamente em `JotJunior/claude-ai-tips` com:
  - Titulo no formato `[agente-00C] Bug em clarify: <resumo>`.
  - Corpo seguindo `contracts/issue-template.md`.
  - Labels: `agente-00c`, `bug`, `skill-global`.
- Status final: `abortada`.
- Motivo termino: `bug_skill_global`.
- Relatorio final lista a issue com numero/URL na secao 5.1.

---

## Scenario 7 — URL fora da whitelist e bloqueada (FR-018, V do toolkit)

**Pre-condicoes**:

- Whitelist em `.claude/agente-00c-whitelist` contem apenas `https://pkg.go.dev/**`.
- Pipeline tenta acessar `https://npmjs.com/...` durante a etapa plan.

**Passos**:

1. Operador invoca `/agente-00c "..." --projeto-alvo-path /tmp/test-whitelist-foo`.
2. Etapa plan tenta `curl https://npmjs.com/package/foo`.

**Expected**:

- Tentativa bloqueada antes da chamada efetiva.
- Decisao registrada com motivo "url fora da whitelist" e opcao "bloquear"
  vs "adicionar a whitelist e seguir" (escolhe bloquear por default).
- Bloqueio humano disparado: pergunta se adicionar a whitelist ou abortar.
- Status: `aguardando_humano`.

---

## Scenario 8 — Tentativa de spawnar tataraneto (FR-013)

**Pre-condicoes**:

- Estado configurado com `profundidade_corrente_subagentes = 3`.
- Task corrente requer spawn de mais um nivel.

**Passos**:

1. Bisneto tenta usar tool Agent.
2. Tool falha por nao estar autorizada na definicao do bisneto.

**Expected**:

- Falha de tool retornada ao orquestrador raiz.
- Decisao registrada: "limite de profundidade atingido, plano alternativo X".
- Pipeline tenta caminho alternativo (delegar ao neto, ou orquestrador faz
  o trabalho).
- Se nenhum caminho alternativo funciona dentro do orcamento de ciclos,
  bloqueio humano.

---

## Scenario 9 — Movimento circular detectado (FR-014)

**Pre-condicoes**:

- Pipeline em loop fix-bug-fix-mesmo-bug. Buffer
  `historico_movimento_circular` no estado tem 5 entradas formando padrao
  circular conforme research.md Decision 4.

**Passos**:

1. Orquestrador chega a 6a entrada com par (P=A, S=X) — ja visto no inicio.

**Expected**:

- Heuristica detecta o ciclo.
- Aborto imediato com `motivo_termino = movimento_circular`.
- Relatorio inclui o buffer completo na secao "Linha do tempo" + uma decisao
  na secao "Decisoes" descrevendo a deteccao.

---

## Scenario 10 — Estado corrompido na retomada (FR-008)

**Pre-condicoes**:

- Arquivo `state.json` modificado manualmente para invalidar o schema (ex:
  `schema_version` removido).

**Passos**:

1. Operador invoca `/agente-00c-resume --projeto-alvo-path /tmp/test-corrupt-foo`.
2. Orquestrador valida schema antes de qualquer acao.

**Expected**:

- Validacao falha.
- Bloqueio obrigatorio com mensagem clara.
- Sem auto-correcao silenciosa.
- Operador resolve manualmente (restaura backup de state-history/ ou
  comeca nova execucao).
