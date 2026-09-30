# Referencia de fase: converge (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

   ### 5.f.bis Etapa `convergence` (execute-task -> review-task, US5/FR-015/FR-019 de `skill-converge`; FR-001/FR-006 de `pipeline-converge`)

   > Origem: feature `skill-converge`, FASE 4; reclassificada por
   > `pipeline-converge`, FASE 6 (FR-006: "tratar a convergencia, em
   > execucoes autonomas, como etapa regular do historico de execucao —
   > com o mesmo nivel de rastreabilidade/auditoria das demais etapas —
   > em vez de um caso especial fora da maquina de etapas"). `converge`
   > e inserida por `pipeline.sh` (`_PL_STAGES_LIST`) entre `execute-task`
   > e `review-task` na lista canonica — **nao** e mais um bloco de gate
   > paralelo ao Loop principal: e uma onda como qualquer outra fase, so
   > que com fechamento CONDICIONAL (branch abaixo) em vez de sempre
   > avancar linearmente.

   **Disparo**: quando `.current_stage = converge` (resolvido pela onda
   anterior de `execute-task` ao esgotar o backlog — `- [ ]`/`- [~]`
   zeradas em `tasks.md`, `state-ondas.sh end --advance` avanca via
   `pipeline.sh next-stage` sem logica adicional), invoque
   `Skill(skill="converge", args="<FD>")` normalmente como a fase
   corrente (passo 5). Nenhuma flag de skip existe para esta etapa
   (FR-015, redacao MUST literal): seu criterio de conclusao e delegado
   a `pipeline.sh detect-completion --stage converge` (que consulta
   `converge-status.sh check`), nao a uma checagem estrutural manual.

   **Registro**: `converge` auto-detecta o modo autonomo (via
   `AGENTE_00C_STATE_DIR`/presenca de
   `<PAP>/.claude/agente-00c-state/state.json`) e registra o PROPRIO
   two-step na sua ETAPA 8 (`state-decisions.sh register --agente
   "orquestrador-00c" --etapa "converge"` + `state-ondas.sh record-skill
   --skill converge --kind gate` quando disparada pela fronteira
   `execute-task -> review-task`; `--kind skill`, o default, quando
   invocada avulsamente — Decision 9 de `pipeline-converge`). Este e o
   mecanismo que satisfaz FR-006 sem exigir que o orquestrador chame
   `register`/`record-skill` de novo para esta etapa — duplicaria
   Decisao para o mesmo evento.

   **Fechamento da onda (passo 3 do Loop principal / etapa 8) — 3 ramos
   pelo retorno da skill**:
   - `escolha = "escalar-para-humano"` (achado `CRITICAL` sem correcao
     inline possivel — FR-019: "converge nao trava sozinha", quem decide
     o bloqueio e o orquestrador) -> emita `bloqueios.sh register`
     OBRIGATORIO; feche a onda SEM `--advance` (`current_stage`
     permanece `converge` para a proxima retomada).
   - Relatorio (ETAPA 7 da skill) diz "Fase de convergência apendada:
     FASE N" -> `tasks.md` ganhou tarefas novas; feche a onda com
     `current_stage` voltando a `execute-task` (NAO use `--advance` aqui
     — `pipeline.sh next-stage converge` resolveria linearmente para
     `review-task`; grave `.current_stage="execute-task"` +
     `next_instruction` explicita ANTES do `state-ondas.sh end`).
   - Relatorio diz "nenhuma — feature convergida" -> `execute-task`/
     `converge` estao de fato esgotadas; feche a onda normalmente com
     `state-ondas.sh end --advance` (`pipeline.sh next-stage converge`
     -> `review-task`).

   Ciclo (executar pendentes -> converge -> se apendou fase, volta a
   executar -> converge de novo) e finito por construcao: dedup
   `existing-keys`/`gap-key` da propria skill (FR-011/FR-012) garante que
   a mesma divergencia nunca vira uma segunda tarefa; os gatilhos de
   aborto do passo 7 (`cycles.sh`/`circular.sh`) permanecem como rede de
   seguranca adicional caso o padrao normal nao se sustente.
   `reconcile-wave` (rede de seguranca do command pai) tem um aviso SOFT
   simetrico para a fronteira `converge -> review-task` — nao bloqueante,
   apenas anota `AVISO: convergencia pendente` na `next_instruction`
   quando o veredito nao e converged/risk-accepted (ver `research.md`
   Decision 14 de `pipeline-converge`).

<!-- ORCH-REF-END -->
