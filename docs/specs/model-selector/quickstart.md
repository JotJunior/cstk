# Quickstart: model-selector

Cenarios end-to-end que validam a implementacao. Cobrem os 3 fluxos
das User Stories da spec + casos de erro + auditoria.

**Roundtrip backend↔frontend**: **N/A — single-layer** (skill toolkit
POSIX, sem servidor/cliente). Cenario obrigatorio do template (§3 do
quickstart template) nao se aplica.

---

## Scenario 1: Happy path — orquestrador recebe sugestao "haiku" para clarify trivial (User Story 1)

1. Estado inicial: agente-00c em onda de uma feature trivial; etapa
   `clarify`; 3 perguntas previamente identificadas, todas com
   evidencia direta no briefing/constitution.
2. Orquestrador invoca a skill `model-selector` com input descritivo
   do contexto:
   ```sh
   sh global/skills/model-selector/scripts/classify.sh \
     "spawn clarify-answerer para 3 perguntas com evidencia direta no briefing, score esperado 2-3, zero ambiguidade"
   ```
3. **Expected output (stdout)**:
   ```markdown
   ## Sugestao

   **modelo**: haiku
   **score**: 2
   **alternativa**: sonnet

   ## Sinais detectados

   - spawn: rasa (peso=1)
   - clarify: rasa (peso=1)
   - evidencia: rasa (peso=1)

   ## Justificativa

   [texto citando os 3 sinais matched]

   ## Acao sugerida (operador humano)

   `/model haiku` (se operador quiser trocar; nao executado pela skill)
   ```
4. Orquestrador registra Decisao via `state-decisions.sh register`
   com `escolha="aceitar-sugestao"`, `score=2`, justificativa
   reusando o texto da skill.
5. Orquestrador atualiza `metricas_acumuladas.model_selector`:
   `sugestoes_total++`, `por_modelo_sugerido.haiku++`,
   `por_resultado.aceitas++`, `ultima_invocacao_iso=now`.
6. Orquestrador spawna `clarify-answerer` com parametro de modelo
   `haiku` (mecanismo concreto fora do escopo desta feature — ver
   Decision 3 do research).
7. **Expected final**: clarify-answerer responde JSON valido (schema
   scores 0..3 + perguntas com 1 escolhida); zero `retro_execucoes`
   consumida (qualidade preservada).

---

## Scenario 2: Operador humano vai trocar manualmente para haiku (User Story 2)

1. Operador abre Claude Code, digita primeira mensagem: `"rode grep -c
   TODO src/ e me retorne o numero"`.
2. Operador (ou hook leve) invoca:
   ```sh
   sh global/skills/model-selector/scripts/classify.sh \
     "rode grep -c TODO src/ e me retorne o numero"
   ```
3. **Expected output**: `modelo=haiku`, `score=2`, justificativa
   citando `rode`, `grep`, `numero` (ou similar).
4. Operador le a secao "Acao sugerida" e copia `/model haiku`.
5. Operador cola `/model haiku` no Claude Code — harness troca.
6. **Expected final**: operador continua a sessao no modelo barato;
   skill nao chamou `/model`, nao manipulou estado (FR-006 preservado).

---

## Scenario 3: Verbo de design → manter-atual (User Story 2, fail-safe)

1. Operador digita: `"refatore este modulo para usar pattern Repository"`.
2. Invoca a skill com esse input.
3. **Expected output**:
   ```markdown
   ## Sugestao

   **modelo**: manter-atual
   **score**: 2
   **alternativa**: none
   ...
   ## Sinais detectados

   - refatore: profunda (peso=1)
   - pattern: profunda (peso=1)

   ## Justificativa

   Verbo de design (`refatore`) + conceito arquitetural (`pattern`)
   indicam decisao com consequencia — faixa profunda mantem modelo
   atual (Opus).
   ```
4. **Expected final**: operador NAO troca de modelo; SC-006 (zero
   falsos positivos para verbos de design) preservado.

---

## Scenario 4: Sinais contraditorios — vence o conservador (FR-005)

1. Input: `"explique e refatore este arquivo"`.
2. **Expected output**:
   ```markdown
   ## Sugestao

   **modelo**: manter-atual
   **score**: 2
   **alternativa**: none

   ## Sinais detectados

   - explique: media (peso=1)
   - refatore: profunda (peso=1)

   ## Justificativa

   Sinais contraditorios (`explique` em faixa media, `refatore` em
   faixa profunda). Conforme FR-005, vence o sinal mais conservador
   — faixa profunda mantem modelo atual.
   ```
3. **Expected final**: invariante FR-005 verificavel via
   `test_model_selector_ambiguo.sh`.

---

## Scenario 5: Input vazio → manter-atual com score 0 (Decision 7 do research)

1. Input: `""` (string vazia, via `sh classify.sh ""`).
2. **Expected output**:
   ```markdown
   ## Sugestao

   **modelo**: manter-atual
   **score**: 0
   **alternativa**: none

   ## Sinais detectados

   (nenhum sinal detectado)

   ## Justificativa

   Input curto demais para classificacao confiavel: 0 tokens uteis.
   Conforme Decision 7 do research, faixa default e conservadora.

   ## Acao sugerida (operador humano)

   `(nenhuma troca sugerida — manter modelo atual)`
   ```
3. **Expected final**: exit code 0 (sem erro — fail-safe, nao
   fail-fast). Score 0 explicitamente comunicado.

---

## Scenario 6: Erro de uso — argumento ausente

1. Invocacao: `sh classify.sh` (sem argumentos).
2. **Expected**:
   - stdout: vazio.
   - stderr: `model-selector: input obrigatorio (uso: classify.sh "<texto>")`.
   - exit code: 2.

---

## Scenario 7: Catalogo ausente — erro interno (FR-017 cobertura)

1. Estado: `references/sinais.md` removido ou path errado.
2. Invocacao: `sh classify.sh "qualquer texto"`.
3. **Expected**:
   - stdout: vazio.
   - stderr: `model-selector: catalogo de sinais nao encontrado em <path>`.
   - exit code: 1.

---

## Scenario 8: Relatorio agregado (FR-012, User Story 3, sem jq)

1. Estado: 2 execucoes do feature-00c em
   `.claude/feature-00c-state/` cada uma com 3 sugestoes registradas
   em `metricas_acumuladas.model_selector`.
2. Operador roda:
   ```sh
   PATH="/sbin:/usr/sbin:/bin:/usr/bin" \
   sh global/skills/model-selector/scripts/report.sh \
     --state-dir .claude/feature-00c-state/
   ```
   (PATH minimizado para garantir que `jq` NAO esteja disponivel —
   forca o fallback POSIX puro.)
3. **Expected output**:
   ```markdown
   | feature | sugestoes | aceitas | rejeitadas | no-op | haiku | sonnet | opus | manter-atual |
   |---------|-----------|---------|------------|-------|-------|--------|------|--------------|
   | feature-a | 3 | 2 | 1 | 0 | 1 | 1 | 0 | 1 |
   | feature-b | 3 | 3 | 0 | 0 | 2 | 0 | 0 | 1 |
   | **total** | 6 | 5 | 1 | 0 | 3 | 1 | 0 | 2 |
   ```
4. Operador roda DE NOVO, agora com `jq` no PATH normal:
   ```sh
   sh scripts/report.sh --state-dir .claude/feature-00c-state/
   ```
5. **Expected**: output IDENTICO ao caminho fallback. Comparacao
   automatizada em `tests/cstk/test_report_without_jq.sh`.

---

## Scenario 9: Confinamento do `jq` (FR-010a condicao b)

1. Comando: `grep -rn '\bjq\b' global/skills/model-selector/`.
2. **Expected**: retorna apenas linhas em
   `global/skills/model-selector/scripts/report.sh`. Nenhuma outra
   ocorrencia em `SKILL.md`, em `references/`, ou em outros scripts.
3. Verificavel via `test_report_jq_confinement.sh`.

---

## Scenario 10: Zero rede (SC-005, Principio IV)

1. Comando:
   `grep -rn 'curl\|wget\|http\|nc\b\|socat\|ssh' global/skills/model-selector/`.
2. **Expected**: retorna vazio OU apenas comentarios markdown
   (documentacao) que NAO sao codigo executavel. Validado
   manualmente quando primeira execucao acontecer; teste automatizado
   em `test_model_selector_zero_rede.sh`.

---

## Scenario 11: Performance do relatorio (SC-003)

1. Setup: fixture com 20 `state.json` mockados em
   `tests/fixtures/state-dirs-20/`, cada um com 5 sugestoes
   registradas.
2. Comando: `time sh scripts/report.sh --state-dir tests/fixtures/state-dirs-20/`.
3. **Expected**: real time <500ms em maquina dev tipica (M1/M2 ou
   Linux x86_64 modesto). Validado por
   `tests/cstk/test_report_performance.sh`.

---

## Resumo de cobertura por SC/FR

| Cenario | SC/FR coberto |
|---------|---------------|
| 1 | User Story 1, FR-001, FR-002, FR-007, FR-008, SC-001, SC-002 |
| 2 | User Story 2, FR-006, FR-013(a) |
| 3 | User Story 2, FR-003 (faixa profunda), SC-006 |
| 4 | FR-005 (sinais contraditorios), edge case 5 |
| 5 | Decision 7 do research, edge case 1, FR-005 |
| 6 | FR-017 cobertura de uso incorreto |
| 7 | FR-017 cobertura de erro interno |
| 8 | FR-010a (a), FR-012, User Story 3, SC-003 |
| 9 | FR-010a (b) |
| 10 | SC-005, Principio IV |
| 11 | SC-003 |
