# Referencia de fase: review-features (root)

> Conteudo movido do prompt-base `agente-00c-orchestrator.md` sem alteracao semantica
> (feature orchestrator-slim, FR-004). Secoes na ordem original.

   ### 5.f.ter Gate `delta-gate` na etapa `review-features` (archive, CHK020)

   > Origem: feature `living-specs`, FASE 4. Fecha o gate obrigatorio da
   > FR-010 (US3) tambem no fluxo AUTONOMO — o gate ja e obrigatorio na
   > prosa manual de `review-features/SKILL.md` ("Proximos passos
   > sugeridos" item 3); esta secao herda o MESMO comportamento quando o
   > orquestrador invoca a skill sem supervisao (research.md Decision 8).

   **Gatilho**: etapa corrente `review-features`, apos a skill reportar o
   portfolio, para CADA feature classificada `ARQUIVAR` que o
   orquestrador decida mover para `_archived/<YYYY-MM-DD>-<feature>/`:

   ```bash
   OUT=$(bash "$HOME/.claude/skills/review-features/scripts/delta-gate.sh" \
     "docs/specs/<feature>/spec.md" --corpus-dir "docs/specs/current" 2>&1)
   _gate_exit=$?
   ```

   **Exit 0 (liberado)**: rodar `delta-merge.sh docs/specs/<feature>/spec.md
   --feature <feature>` ANTES do `mv` para `_archived/`; merge bloqueado
   (exit 1 — corpus mudou entre gate e merge) suspende o `mv` da MESMA
   feature pela mesma politica de bloqueio abaixo (defesa em
   profundidade). Gate e merge liberados => `mv` acontece normalmente
   (fluxo existente intacto, US2 cenario 5).

   **Exit != 0 (bloqueado)**: aplicar a politica fixada em
   `docs/specs/living-specs/tasks.md` tarefa 1.2.1-1.2.3 (research.md
   Decision 8):

   ```bash
   state-decisions.sh register --state-dir <SD> \
     --agente "orquestrador-00c" --etapa "review-features" \
     --contexto "Gate delta-gate bloqueou archive de <feature>: $OUT" \
     --opcoes '["bloqueio-humano-escopado","abortar-onda"]' \
     --escolha "bloqueio-humano-escopado" \
     --justificativa "FR-010/CHK020: archive sem delta requer preenchimento ou skip explicito; nao falhar silenciosamente" \
     --score 2

   bloqueios.sh register --state-dir <SD> \
     --pergunta "Archive de <feature> bloqueado pelo delta-gate: <FINDING|error|... literal>. Preencher a secao Delta Requirements, registrar skip explicito, ou pular o archive desta feature?" \
     --contexto-para-resposta "<RESULT|<spec>|delta=missing|errors=N|... literal emitido pelo gate>"
   ```

   O bloqueio e **ESCOPADO aquela feature especifica** — NUNCA aborta a
   onda inteira de `review-features`: as demais features do portfolio
   sem bloqueio de gate continuam sendo processadas (arquivadas ou
   apenas avaliadas) normalmente na mesma onda, o mesmo padrao ja usado
   pelos demais Quality Gates complementares (§5.f). A pergunta e o
   contexto-para-resposta citam os `FINDING`/`RESULT` LITERAIS emitidos
   pelo gate (aterramento de evidencia, Constitution VI) — nunca um
   resumo parafraseado sem a linha real.

   Registrar `state-ondas.sh record-skill --skill delta-gate --kind gate`
   (script deterministico) por feature avaliada, para que `/review-task`
   e `/review-features` consigam medir cobertura deste gate tambem.

<!-- ORCH-REF-END -->
