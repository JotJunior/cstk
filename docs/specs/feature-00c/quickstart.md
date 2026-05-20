# Quickstart: Feature-00C

Cenarios de teste manual cobrindo happy path, edge cases e roundtrip
empirico. Cada cenario tem passos numerados + resultado esperado.
Suite e executada pelo operador em projeto-alvo controlado.

---

## Cenario 1 — Happy path: feature completa em 1 sessao (P1)

**Pre-condicoes**:
- Projeto-alvo com `docs/01-briefing-discovery/briefing.md` valido
- `docs/constitution.md` versao >= 1.0.0 ratificada
- Nenhuma execucao agente-00c ativa
- `feature-00c-state/` ausente

**Passos**:

1. Operador invoca: `/feature-00c "Adicionar export CSV de relatorios"`
2. Slash command executa pre-flight (briefing, constitution, coexistencia)
3. Orquestrador inicia pipeline: specify → clarify → plan → checklist →
   create-tasks → execute-task → review-task
4. Em cada fase, skills sao invocadas via tool `Skill`
5. Clarify-asker gera perguntas; clarify-answerer responde com score 3
6. execute-task loop por todas as tasks de tasks.md
7. review-task gera resumo final
8. Estado e persistido a cada onda; backups em `backups/`

**Expected**:
- `<projeto-alvo>/docs/specs/export-csv/spec.md`, `plan.md`, `tasks.md`,
  `checklists/*.md` existem e nao-vazios
- Codigo da feature implementado e testes passando
- `<projeto-alvo>/.claude/feature-00c-state/export-csv/feature-00c-report.md`
  com 6 secoes obrigatorias preenchidas
- Status final no state.json: `concluida`
- Pelo menos 1 backup `backups/wave-001.json` existe
- Nenhum secret em report ou backups (verificavel via `grep` de padroes
  conhecidos do filtro)

---

## Cenario 2 — Pre-flight failure: briefing ausente

**Pre-condicoes**:
- Projeto-alvo sem `briefing.md`
- `constitution.md` ratificada
- `feature-00c-state/` ausente

**Passos**:

1. Operador invoca: `/feature-00c "Nova feature qualquer"`
2. Slash command checa existencia de briefing
3. Falha — briefing.md nao encontrado

**Expected**:
- Exit code 1
- stderr contem diagnostico: "feature-00c requer projeto com briefing
  pre-existente; rode `/briefing` antes ou use `/agente-00c` para
  bootstrap"
- `<projeto-alvo>/.claude/feature-00c-state/` PERMANECE inexistente
  (SC-PRE-001 — nenhum artefato criado em disco)

**Variantes**:
- 2a: briefing existe mas e stub (apenas headers) → mesma falha
- 2b: briefing existe mas tem `[TBD]` em secao minima → mesma falha
  (FR-PRE-003)

---

## Cenario 3 — Clarify autonomo com score 3/3 (P2)

**Pre-condicoes**: pre-flight OK; spec inicial gerada na onda anterior
com 3 ambiguidades.

**Passos**:

1. Orquestrador entra na fase clarify
2. Spawna `feature-00c-clarify-asker` com spec + briefing
3. Asker retorna 3 perguntas com 3 opcoes cada
4. Orquestrador spawna `feature-00c-clarify-answerer` com perguntas +
   briefing + constitution + spec + decisoes_anteriores
5. Answerer aplica scoring 0..3 e devolve respostas
6. Orquestrador integra respostas na spec via `Skill` clarify

**Expected**:
- Cada Decisao do answerer tem score >= 2 (FR-023 — score < 2 vira
  bloqueio humano)
- Cada Decisao registra `referencias` com >= 1 path para
  briefing/constitution/spec (FR-017)
- Spec atualizada inclui secao `## Clarifications` com bullets
  pergunta→resposta
- `state.json.decisoes` cresce em 3 entradas

---

## Cenario 4 — Resume apos wakeup (P3)

**Pre-condicoes**:
- Execucao em progresso (fase plan, onda 3)
- Onda 3 atingiu threshold (>=80 tool calls)
- Estado persistido + backup wave-003.json gerado
- ScheduleWakeup invocado com delaySeconds=270

**Passos**:

1. Aguardar wakeup disparar (271s depois)
2. Harness invoca `/feature-00c-resume <short_name>` automaticamente
3. Resume checa lock (ausente; OK)
4. Resume valida state.json.sha256 (match; OK)
5. Resume valida briefing.sha256 + constitution.sha256 (match; OK)
6. Carrega state.json + delega ao orquestrador
7. Orquestrador continua de `proxima_instrucao`
8. Onda 4 inicia em fase plan, continua de onde parou

**Expected**:
- Onda 4 registrada em `state.ondas[]` com `numero=4`,
  `fase_inicial=plan`
- Decisoes anteriores preservadas (size de `state.decisoes` cresceu, nao
  resetou)
- Sem re-execucao de subtasks ja completadas (campo `tasks_concluidas`
  consultado)

**Variantes**:
- 4a: hash state.json divergente entre ondas → bloqueio humano
  (FR-014); resume retorna exit 4
- 4b: constitution mudou MAJOR entre ondas → bloqueio compulsorio
  (FR-PRE-004); resume retorna exit 4

---

## Cenario 5 — Aborto manual graceful (P4)

**Pre-condicoes**: execucao em andamento; operador decide abortar.

**Passos**:

1. Operador invoca: `/feature-00c-abort <short_name>`
2. Abort le state, adquire lock force-mode
3. Marca status=abortada, motivo_termino="aborto manual"
4. Gera relatorio parcial via `report.sh`
5. Commit local
6. Libera lock

**Expected**:
- Exit 0 dentro de 60 segundos (SC-005)
- `feature-00c-report.md` existe com Secao 1 indicando aborto manual
- Status no state.json: `abortada`
- Backup wave-N.json final tambem gravado (com estado pos-aborto)
- Idempotente: re-invocar `/feature-00c-abort` no mesmo short_name
  retorna "execucao ja em status terminal".

---

## Cenario 6 — Coexistencia com agente-00c em terminal (P5 AC#1)

**Pre-condicoes**:
- Projeto-alvo tem `agente-00c-state/state.json` com status=concluida
  (execucao antiga do 00c)
- Sem feature-00c ativa

**Passos**:

1. Operador invoca: `/feature-00c "Adicionar paginacao na listagem"`
2. Slash command checa agente-00c — status terminal, OK
3. Pre-flight + invocacao normal seguem

**Expected**:
- Execucao inicia normalmente em `feature-00c-state/paginacao/`
- `agente-00c-state/` NAO e modificado (verificavel por diff de
  diretorio antes/depois)
- SC-012: snapshot do `.claude/` mostra apenas novos arquivos sob
  `feature-00c-state/`

---

## Cenario 7 — Conflito com agente-00c ativo (P5 AC#2)

**Pre-condicoes**:
- `agente-00c-state/state.json` indica status=em_andamento

**Passos**:

1. Operador invoca: `/feature-00c "Nova feature"`
2. Slash command checa agente-00c — status em_andamento
3. Rejeita invocacao

**Expected**:
- Exit 2
- stderr: "agente-00c esta ativo (status: em_andamento). Resolva via
  /agente-00c-abort ou /agente-00c-resume antes de invocar
  /feature-00c."
- `feature-00c-state/` NAO criado

---

## Cenario 8 — Features paralelas no mesmo projeto (P5 AC#3)

**Pre-condicoes**:
- Sem agente-00c ativo
- Feature A (`user-auth`) ja em andamento em `feature-00c-state/user-auth/`

**Passos**:

1. Em sessao 2 (paralelo), operador invoca:
   `/feature-00c "Adicionar dashboard de analytics" analytics-dashboard`
2. Slash command checa: agente-00c OK, lock de
   `feature-00c-state/analytics-dashboard/` ausente
3. Inicia normalmente

**Expected**:
- Sessao 1 e Sessao 2 rodam em paralelo
- Cada uma escreve em `feature-00c-state/<seu_short_name>/`
- Suggestions compartilhada em `feature-00c-suggestions.md` recebe
  bullets de ambas (append-only por id incremental)
- Nenhuma race condition (lock por short_name garante isolamento)

---

## Cenario 9 — Gatilho de loop: 6 ciclos sem progresso (P4 + FR-022.a)

**Pre-condicoes**: execucao em fase execute-task; task T003 falhando
ha 5 ondas.

**Passos**:

1. Onda 6 inicia
2. Pipeline tenta novamente T003
3. Detector de progresso (`cycles.sh` herdado do 00c) verifica:
   nenhum dos 4 criterios de "progresso mensuravel" (cross-reference para
   agente-00c spec §FR-014) foi atendido nas ultimas 5 ondas
4. Aborto disparado

**Expected**:
- Status=abortada, motivo_termino="tendencia a loop em fase execute-task"
- Relatorio parcial em <60s
- Secao 6 do relatorio (Licoes) contem item sobre T003
- Suggestions pode conter sugestao para skill `execute-task` (split de
  tasks de migracao, etc)

---

## Cenario 10 — ROUNDTRIP END-TO-END: integridade de backup com secrets

**Pre-condicoes**:
- Projeto-alvo tem `.env` com `API_TOKEN=sk-prod-aaaaaaaaaaaaaaaaaaaaaaa`
- Execucao em andamento que registrou uma decisao mencionando o token
  no campo de contexto (cenario realista: log de erro vazou o token)

**Passos**:

1. Onda finaliza; orquestrador grava state.json (com token preservado)
2. Orquestrador grava backup `backups/wave-NNN.json` apos passar por
   `secrets-filter.sh --redact`
3. Orquestrador grava report.md tambem filtrado

**Expected (verificacao real, nao mock)**:
- `grep "sk-prod-" state.json` → match (state operacional preservado)
- `grep "sk-prod-" backups/wave-NNN.json` → SEM match
- `grep "REDACTED" backups/wave-NNN.json` → match
- `grep "sk-prod-" feature-00c-report.md` → SEM match
- Hash `state_sha256_self` no backup bate com SHA do conteudo filtrado
  (verifica: `sha256sum < <(jq '.state_snapshot' backups/wave-NNN.json)`
  == campo `state_sha256_self`)

Este e o roundtrip empirico exigido pela skill plan §5.3 — testa o
contrato real (filtro + hash) sobre um payload realista, nao um mock.

---

## Cenario 11 — Constitution evolui MAJOR durante pausa

**Pre-condicoes**:
- Execucao pausada (status=aguardando_humano)
- `constitution.sha256` registrado no state aponta para v1.1.0
- Operador atualiza constitution para v2.0.0 manualmente entre ondas

**Passos**:

1. Operador invoca `/feature-00c-resume <short_name> --resposta-bloqueio "..."`
2. Resume le state, valida lock OK
3. Valida hash state.json (OK), depois hash constitution
4. Hash diverge; resume detecta versao mudou para v2.0.0 (MAJOR bump)
5. Bloqueio humano compulsorio: registra blq pedindo decisao
   "re-validar decisoes ou abortar"
6. Resume retorna exit 4

**Expected**:
- Relatorio parcial atualizado com blq adicional
- state.json com novo bloqueio em `bloqueios_humanos[]`
- exit 4
- Operador precisa de nova invocacao com --resposta-bloqueio para
  prosseguir

---

## Cenario 12 — Quality Gate de seguranca dispara BloqueioHumano (§5.f port)

**Pre-condicoes**:
- Execucao em andamento que acabou de gerar `plan.md`
- Plan descreve arquitetura com endpoint HTTP autenticado por API key
  em URL queryparam (anti-pattern OWASP)
- 3 skills-gate (`validate-documentation`, `validate-docs-rendered`,
  `owasp-security`) pre-aprovadas no warm-up

**Passos**:

1. Orquestrador conclui fase `plan` (skill `plan` retorna plan.md valido)
2. Orquestrador entra na §"Quality Gates complementares" (posicao
   apos passo 7 do Loop, antes do passo 8 backup)
3. Invoca `Skill(skill="owasp-security", args="<feature-dir>/plan.md")`
4. owasp-security retorna finding `severity: high` ("API key em URL
   queryparam — log/proxy exposure")
5. Orquestrador detecta `severity in [critical, high]` E `gate=security`
6. Bloqueio humano OBRIGATORIO (constitution exige seguranca como MUST)
7. `bloqueios.sh register` com pergunta + contexto do finding
8. `state-decisions.sh register` com `kind=gate-finding`,
   `agente=agente-00c-feature-orchestrator`,
   `escolha=escalar-para-humano`
9. Backup da onda gerado (filtrado), report parcial emitido
10. Status: `aguardando_humano`; Schedule intent: none

**Expected**:
- Bloqueio in `state.json.bloqueios_humanos[]` com `status=aguardando`
- Relatorio parcial Secao 4 (Bloqueios Humanos) lista o blq
- Operador resolve via `/feature-00c-resume <short> --resposta-bloqueio "..."`
- Resposta gera nova Decisao referenciando o blq + alteracao no plan.md
  (corrigir-agora) OU aborto graceful (escalar=abortar)

**Variantes**:
- 12a: severity=`critical` em `validate-documentation` apos specify
  (spec com TBD em FR critico) → BloqueioHumano (mesmo fluxo)
- 12b: severity=`high` em `validate-docs-rendered` apos create-tasks
  (Mermaid invalido) → NAO obrigatorio (apenas Decisao + tentativa de
  Edit automatico)
- 12c: feature trivial sem superficie de seguranca, orquestrador opta
  por skip do gate `owasp-security` apos plan → registrar Decisao com
  `kind=gate_skipped`, `escolha=skip-com-justificativa`, score 3.
  `/review-task` audita: features com >2 skips sem justificativa
  solida viram finding `quality-gate-bypass`.

---

## Resumo dos cenarios

| # | Foco | Story | FRs cobertos | SC verificado |
|---|------|-------|--------------|---------------|
| 1 | Happy path | US1 | FR-007, FR-018 | SC-001 |
| 2 | Pre-flight briefing | edge case | FR-PRE-001 | SC-PRE-001, SC-008 |
| 3 | Clarify autonomo | US2 | FR-009, FR-017, FR-023 | SC-002, SC-007 |
| 4 | Resume cross-onda | US3 | FR-014, FR-016, FR-PRE-004 | SC-003, SC-PRE-002 |
| 5 | Abort manual | US4 | FR-019, FR-025 | SC-005 |
| 6 | Coexistencia OK | US5 | FR-026, FR-027 | SC-012 |
| 7 | Coexistencia bloqueada | US5 | FR-026 | SC-010 |
| 8 | Features paralelas | US5 | FR-028 | SC-009 |
| 9 | Loop trigger | US4 | FR-022 | SC-004 |
| 10 | **Roundtrip secrets** | seguranca | FR-029, FR-034 | privacy gap |
| 11 | Constitution drift | edge case | FR-PRE-004 | SC-PRE-002 |
| 12 | **Quality Gate security** | §5.f port | FR-024, owasp-security | gate-finding flow |
